//! 账号接口的并发压测（2026-09-26 后端压测）。都在隔离库里跑（`ops/test.py`），
//! 一条也不碰线上。每条用例都是「很多请求同时到」的形状——读代码时看不出来的
//! 那一类毛病只在这种时序下才冒头。
mod review_common;
use axum::{Router,body::Body,extract::ConnectInfo,http::{Request,StatusCode}};
use http_body_util::BodyExt;
use review_common::*;
use serde_json::{Value,json};
use std::net::SocketAddr;
use std::sync::{Arc,atomic::{AtomicBool,AtomicU64,Ordering}};
use tower::ServiceExt;
use uuid::Uuid;

/// 一次从「某个外网地址」来的请求：对端是回环（线上前面是本机 Caddy），
/// 真实地址放在 `X-Forwarded-For` 里——和线上的形状一样，额度按这个地址算。
async fn from(app:&Router,ip:&str,path:&str,token:Option<&str>,body:Value)->(StatusCode,Value) {
 let mut req=Request::builder().uri(path).method("POST").header("content-type","application/json").header("x-forwarded-for",ip);
 if let Some(t)=token {req=req.header("authorization",format!("Bearer {t}"));}
 let mut req=req.body(Body::from(body.to_string())).unwrap();
 req.extensions_mut().insert(ConnectInfo("127.0.0.1:19000".parse::<SocketAddr>().unwrap()));
 let res=app.clone().oneshot(req).await.unwrap();let status=res.status();
 let bytes=res.into_body().collect().await.unwrap().to_bytes();
 (status,serde_json::from_slice(&bytes).unwrap_or_else(|_|json!({"nonJSON":String::from_utf8_lossy(&bytes)})))
}
fn device(kind:&str)->Value {json!({"id":Uuid::new_v4(),"name":"stress","secret":kanpan_api::crypto::random_token(),"kind":kind})}

/// 本进程此刻的常驻内存（KiB）。`ps` 在 macOS 与 Linux 上都有，不引新依赖。
fn rss_kib()->u64 {
 let out=std::process::Command::new("ps").args(["-o","rss=","-p",&std::process::id().to_string()]).output().unwrap();
 String::from_utf8_lossy(&out.stdout).trim().parse().unwrap_or(0)
}
/// 在后台每 5 ms 采一次 RSS，返回（停止开关，峰值）。
fn sample_rss()->(Arc<AtomicBool>,Arc<AtomicU64>,std::thread::JoinHandle<()>) {
 let stop=Arc::new(AtomicBool::new(false));let peak=Arc::new(AtomicU64::new(0));
 let (s,p)=(stop.clone(),peak.clone());
 let h=std::thread::spawn(move||while !s.load(Ordering::SeqCst) {p.fetch_max(rss_kib(),Ordering::SeqCst);std::thread::sleep(std::time::Duration::from_millis(5));});
 (stop,peak,h)
}

/// 一阵登录同时到，Argon2 的内存不能跟着并发数一起涨。
///
/// 每次 Argon2（默认参数）要 19 MiB 的工作区。以前 `hash` / `verify` 直接丢进
/// `spawn_blocking`，同时来多少次登录就同时开多少份：同一个地址一分钟有 60 次额度，
/// 60 × 19 MiB ≈ 1.1 GB，而线上 serve 单元 `MemoryMax=1G`——一个人（连不存在的用户名
/// 也走假哈希那一遍）一口气打满额度，整个进程连同订单流跟踪一起被 OOM 杀掉。
#[tokio::test(flavor="multi_thread",worker_threads=8)]
async fn login_burst_keeps_password_hashing_memory_bounded() {
 let w=boot().await;
 const BURST:usize=48;
 // 先热身一次，把分配器、连接池、路由的首次开销排除在测量之外。
 let _=from(&w.app,"203.0.113.250","/v1/auth/login",None,json!({"username":"nobody_warm","password":"Passcode123","device":device("phone")})).await;
 let base=rss_kib();
 let (stop,peak,h)=sample_rss();
 let started=std::time::Instant::now();
 let mut set=tokio::task::JoinSet::new();
 for n in 0..BURST {
  let app=w.app.clone();
  // 不存在的用户名：不用建号，也正是攻击者能白打的那条路（假哈希照样算一遍）。
  set.spawn(async move {from(&app,"203.0.113.9","/v1/auth/login",None,json!({"username":format!("nobody_{n}"),"password":"Passcode123","device":device("phone")})).await.0});
 }
 let mut statuses=Vec::new();while let Some(r)=set.join_next().await {statuses.push(r.unwrap());}
 let took=started.elapsed();
 stop.store(true,Ordering::SeqCst);h.join().unwrap();
 let grew=peak.load(Ordering::SeqCst).saturating_sub(base)/1024;
 eprintln!("login burst: {BURST} concurrent, took {took:?}, rss base {} MiB, peak growth {grew} MiB",base/1024);
 assert!(statuses.iter().all(|s|*s==StatusCode::UNAUTHORIZED),"{statuses:?}");
 // 两个名额的工作区是 38 MiB；给分配器与请求本身留足余量，仍远低于「每请求一份」的 900 MiB。
 assert!(grew<256,"Argon2 working memory grew {grew} MiB for {BURST} concurrent logins — hashing is not bounded");
 w.close().await;
}

/// 同一把 refresh 同时来 50 路、同一个 request_id（客户端断线重发）：只能换出**一对**
/// 新令牌，其余拿到的是同一份密封结果；会话不能被当成「重用」吊销。
#[tokio::test(flavor="multi_thread",worker_threads=8)]
async fn fifty_concurrent_refresh_retries_mint_one_pair() {
 let w=boot().await;
 let dev=device("phone");let user=name("rf");
 let (st,v)=from(&w.app,"203.0.113.20","/v1/auth/register",None,json!({"username":user,"password":"Passcode123","device":dev})).await;assert_eq!(st,201,"{v}");
 let refresh=v["data"]["refreshToken"].as_str().unwrap().to_string();let rid=Uuid::new_v4();
 let mut set=tokio::task::JoinSet::new();
 // 额度是每会话一分钟 30 次，所以 50 路里会有 20 路回 429——那是节流在做事，
 // 要断言的是：拿到 200 的那些全都拿到同一对令牌。
 for _ in 0..50 {
  let app=w.app.clone();let body=json!({"refreshToken":refresh,"requestId":rid,"device":dev});
  set.spawn(async move {from(&app,"203.0.113.20","/v1/auth/refresh",None,body).await});
 }
 let mut ok=Vec::new();let mut other=Vec::new();
 while let Some(r)=set.join_next().await {let (s,v)=r.unwrap();if s==200 {ok.push(v)} else {other.push((s,v))}}
 assert!(!ok.is_empty());
 let first=ok[0]["data"]["accessToken"].as_str().unwrap().to_string();
 assert!(ok.iter().all(|v|v["data"]["accessToken"].as_str()==Some(first.as_str())),"two different pairs were minted");
 assert!(other.iter().all(|(s,_)|*s==StatusCode::TOO_MANY_REQUESTS),"{other:?}");
 let pairs:i64=sqlx::query_scalar("SELECT count(*) FROM account_tokens t JOIN account_sessions s ON s.id=t.session_id JOIN account_users u ON u.id=s.user_id WHERE u.email=$1 AND t.kind='refresh'").bind(&user).fetch_one(&w.admin).await.unwrap();
 assert_eq!(pairs,2,"original refresh + exactly one rotated refresh");
 let revoked:bool=sqlx::query_scalar("SELECT bool_or(s.revoked_at IS NOT NULL) FROM account_sessions s JOIN account_users u ON u.id=s.user_id WHERE u.email=$1").bind(&user).fetch_one(&w.admin).await.unwrap();
 assert!(!revoked,"retries of one refresh were treated as token reuse");
 w.close().await;
}

/// 同一个账号、同一类设备（手机）从 12 台机器同时登录：每一次都可以成功，
/// 但最后活着的手机会话只能有一条——「每类一台」不能被并发穿过去。
#[tokio::test(flavor="multi_thread",worker_threads=8)]
async fn concurrent_same_kind_logins_leave_one_live_session() {
 let w=boot().await;
 let user=name("kick");
 let (st,_)=from(&w.app,"203.0.113.30","/v1/auth/register",None,json!({"username":user,"password":"Passcode123","device":device("phone")})).await;assert_eq!(st,201);
 let mut set=tokio::task::JoinSet::new();
 for n in 0..12 {
  let app=w.app.clone();let user=user.clone();
  let kind=if n%3==0 {"tablet"} else {"phone"};
  set.spawn(async move {from(&app,&format!("203.0.113.{}",40+n),"/v1/auth/login",None,json!({"username":user,"password":"Passcode123","device":device(kind)})).await.0});
 }
 while let Some(r)=set.join_next().await {assert_eq!(r.unwrap(),StatusCode::OK);}
 let live:Vec<(String,i64)>=sqlx::query_as("SELECT s.device_kind,count(*) FROM account_sessions s JOIN account_users u ON u.id=s.user_id WHERE u.email=$1 AND s.revoked_at IS NULL GROUP BY 1 ORDER BY 1").bind(&user).fetch_all(&w.admin).await.unwrap();
 assert_eq!(live,vec![("phone".to_string(),1),("tablet".to_string(),1)]);
 w.close().await;
}

/// 20 路错密码从 20 个地址同时打同一个用户名：失败账不能各数各的。五次就锁，
/// 锁着时连对的密码也进不来；锁的次数账上至少要记满五次。
#[tokio::test(flavor="multi_thread",worker_threads=8)]
async fn concurrent_guessing_locks_the_account() {
 let w=boot().await;
 let user=name("guess");
 let (st,_)=from(&w.app,"203.0.113.60","/v1/auth/register",None,json!({"username":user,"password":"Passcode123","device":device("phone")})).await;assert_eq!(st,201);
 let mut set=tokio::task::JoinSet::new();
 for n in 0..20 {
  let app=w.app.clone();let user=user.clone();
  set.spawn(async move {from(&app,&format!("198.18.0.{}",n+1),"/v1/auth/login",None,json!({"username":user,"password":"Wrongpass999","device":device("phone")})).await.0});
 }
 while let Some(r)=set.join_next().await {assert_eq!(r.unwrap(),StatusCode::UNAUTHORIZED);}
 let (st,_)=from(&w.app,"198.18.1.1","/v1/auth/login",None,json!({"username":user,"password":"Passcode123","device":device("phone")})).await;
 assert_eq!(st,StatusCode::UNAUTHORIZED,"correct password must still be refused while the account is locked");
 w.close().await;
}

/// 改密码与另一台设备上的登录同时发生（用旧密码登录 × 10，改密 × 1）：
/// 改完之后，旧密码登进来的会话不能活着——要么在改密之前登进来、被改密吊销，
/// 要么在改密之后被拒。
#[tokio::test(flavor="multi_thread",worker_threads=8)]
async fn password_change_racing_logins_leaves_no_old_password_session() {
 let w=boot().await;
 let user=name("chg");
 let (st,v)=from(&w.app,"203.0.113.70","/v1/auth/register",None,json!({"username":user,"password":"Passcode123","device":device("desktop")})).await;assert_eq!(st,201);
 let token=v["data"]["accessToken"].as_str().unwrap().to_string();
 let mut set=tokio::task::JoinSet::new();
 for n in 0..10 {
  let app=w.app.clone();let user=user.clone();
  set.spawn(async move {from(&app,&format!("198.18.2.{}",n+1),"/v1/auth/login",None,json!({"username":user,"password":"Passcode123","device":device(if n%2==0 {"phone"} else {"tablet"})})).await.0});
 }
 let app=w.app.clone();
 let change=tokio::spawn(async move {from(&app,"203.0.113.70","/v1/auth/password/change",Some(&token),json!({"currentPassword":"Passcode123","newPassword":"Newpass4567"})).await.0});
 while let Some(r)=set.join_next().await {let s=r.unwrap();assert!(s==StatusCode::OK||s==StatusCode::UNAUTHORIZED,"{s}");}
 assert_eq!(change.await.unwrap(),StatusCode::OK);
 let live:i64=sqlx::query_scalar("SELECT count(*) FROM account_sessions s JOIN account_users u ON u.id=s.user_id WHERE u.email=$1 AND s.revoked_at IS NULL AND s.device_kind<>'desktop'").bind(&user).fetch_one(&w.admin).await.unwrap();
 assert_eq!(live,0,"a session opened with the old password survived the change");
 w.close().await;
}
