//! 连接池的压测（2026-09-26 后端压测）：线上 serve 那一档池（`pool_options(true)`，八条连接、
//! 语句 20 秒 / 锁等 5 秒 / 事务里发呆 30 秒），两百多个请求同时到、连接中途被库那边掐断、
//! 某个人的行被长时间锁住。隔离库（`ops/test.py`），不碰线上。
mod review_common;
use axum::{Router,body::Body,extract::ConnectInfo,http::{Request,StatusCode}};
use http_body_util::BodyExt;
use kanpan_api::AppState;
use review_common::*;
use serde_json::{Value,json};
use std::net::SocketAddr;
use std::time::{Duration,Instant};
use tower::ServiceExt;
use uuid::Uuid;

async fn production_app(w:&World)->(Router,AppState) {
 let pool=kanpan_api::pool_options(true).connect(&std::env::var("KANPAN_TEST_DATABASE_URL").unwrap()).await.unwrap();
 let s=AppState{pool,secrets:w.s.secrets.clone(),dummy_hash:w.s.dummy_hash.clone()};
 (kanpan_api::router(s.clone()),s)
}
async fn call(app:&Router,method:&str,path:&str,token:Option<&str>,ip:&str,body:String)->(StatusCode,Value) {
 let mut req=Request::builder().uri(path).method(method).header("content-type","application/json").header("x-forwarded-for",ip);
 if let Some(t)=token {req=req.header("authorization",format!("Bearer {t}"));}
 let mut req=req.body(Body::from(body)).unwrap();
 req.extensions_mut().insert(ConnectInfo("127.0.0.1:19000".parse::<SocketAddr>().unwrap()));
 let res=app.clone().oneshot(req).await.unwrap();let status=res.status();
 let bytes=res.into_body().collect().await.unwrap().to_bytes();
 (status,serde_json::from_slice(&bytes).unwrap_or_else(|_|json!({"nonJSON":String::from_utf8_lossy(&bytes)})))
}
#[derive(Clone)]
struct Who {token:String,device:Uuid}
/// 注册一个账号；每个账号一个不重样的来源地址，各算各的额度。
async fn register(app:&Router,n:usize)->Who {
 let device=Uuid::new_v4();
 let body=json!({"username":name("pool"),"password":"Passcode123","device":{"id":device,"name":"stress","secret":kanpan_api::crypto::random_token(),"kind":"phone"}});
 let (st,v)=call(app,"POST","/v1/auth/register",None,&format!("203.0.{}.{}",113+n/250,n%250+1),body.to_string()).await;
 assert!(st.is_success(),"{v}");
 Who{token:v["data"]["accessToken"].as_str().unwrap().to_string(),device}
}
fn push_body(dev:Uuid,n:usize)->String {
 let op=json!({"id":Uuid::new_v4(),"collection":"settings","objectId":"chart","deviceId":dev,"baseRevision":0,"generation":0,"timestamp":chrono::Utc::now().timestamp_millis(),"logical":n as u64,"action":"patch","fields":{"barSpacing":2.0+(n%50) as f64/10.0}});
 json!({"operations":[op]}).to_string()
}
/// 一个人的一次请求：轮着打推送、bootstrap、增量、收件箱、提醒列表——都是要进 `personal`
/// 事务、占一条连接的那一类。
async fn one(app:&Router,who:&Who,n:usize)->StatusCode {
 let ip="198.18.0.1";
 match n%5 {
  0=>call(app,"POST","/v1/sync/operations",Some(&who.token),ip,push_body(who.device,n)).await.0,
  1=>call(app,"GET","/v1/sync/bootstrap?collection=settings",Some(&who.token),ip,String::new()).await.0,
  2=>call(app,"GET","/v1/sync/changes?after=0",Some(&who.token),ip,String::new()).await.0,
  3=>call(app,"GET","/v1/shares/inbox",Some(&who.token),ip,String::new()).await.0,
  _=>call(app,"GET","/v1/friends",Some(&who.token),ip,String::new()).await.0,
 }
}
fn pct(v:&mut [u128],p:f64)->u128 {v.sort();v[((v.len() as f64-1.0)*p) as usize]}

/// 250 个请求同时到，八条连接轮着用：一条都不能因为等连接而失败（池子取连接的默认上限
/// 是 30 秒，和请求超时一样长——真排到那里就是 408 / 500），也不能出现「八个请求各攥一条、
/// 都在等第二条」的池内死锁。
#[tokio::test(flavor="multi_thread",worker_threads=8)]
async fn two_hundred_fifty_requests_share_eight_connections() {
 let w=boot().await;let (app,s)=production_app(&w).await;
 let mut people=vec![];for n in 0..25 {people.push(register(&app,n).await);}
 const BURST:usize=250;
 let started=Instant::now();let mut set=tokio::task::JoinSet::new();
 for n in 0..BURST {
  let (app,who)=(app.clone(),people[n%people.len()].clone());
  set.spawn(async move {let t=Instant::now();let st=one(&app,&who,n).await;(st,t.elapsed().as_millis(),n%5)});
 }
 let mut lat=vec![];let mut bad=vec![];
 while let Some(r)=set.join_next().await {let (st,ms,kind)=r.unwrap();lat.push(ms);if st!=StatusCode::OK {bad.push((kind,st))}}
 let took=started.elapsed();
 eprintln!("pool burst: {BURST} requests on 8 connections in {took:?}, p50 {} ms, p95 {} ms, max {} ms, non-200 {:?}",pct(&mut lat,0.5),pct(&mut lat,0.95),pct(&mut lat,1.0),bad);
 assert!(bad.is_empty(),"{bad:?}");
 assert!(took<Duration::from_secs(20),"250 requests took {took:?}");
 s.pool.close().await;w.close().await;
}

/// 库那边把 app 的连接全部掐掉（Postgres 重启、主备切换、运维 `pg_terminate_backend`）：
/// 之后来的请求要靠池子换新连接照常成功，不能拿着死连接回 500。
#[tokio::test(flavor="multi_thread",worker_threads=8)]
async fn requests_after_the_database_drops_every_connection_still_succeed() {
 let w=boot().await;let (app,s)=production_app(&w).await;
 let mut people=vec![];for n in 0..8 {people.push(register(&app,300+n).await);}
 // 先把八条连接都建起来、放回池里闲着。
 let mut set=tokio::task::JoinSet::new();
 for n in 0..40 {let (app,who)=(app.clone(),people[n%8].clone());set.spawn(async move {one(&app,&who,n).await});}
 while let Some(r)=set.join_next().await {assert_eq!(r.unwrap(),StatusCode::OK);}
 let idle=s.pool.num_idle();
 let role=std::env::var("KANPAN_TEST_ROLE").unwrap();
 let killed:i64=sqlx::query_scalar("SELECT count(*) FROM (SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename=$1 AND pid<>pg_backend_pid()) x").bind(&role).fetch_one(&w.admin).await.unwrap();
 tokio::time::sleep(Duration::from_millis(200)).await;
 let mut set=tokio::task::JoinSet::new();
 for n in 0..80 {let (app,who)=(app.clone(),people[n%8].clone());set.spawn(async move {(n%5,one(&app,&who,n).await)});}
 let mut bad=vec![];while let Some(r)=set.join_next().await {let (k,st)=r.unwrap();if st!=StatusCode::OK {bad.push((k,st))}}
 eprintln!("reconnect: {idle} idle connections, {killed} terminated by the database, 80 requests after → non-200 {bad:?}");
 assert!(killed>0);
 assert!(bad.is_empty(),"requests failed on dead pooled connections: {bad:?}");
 s.pool.close().await;w.close().await;
}

/// 一个人的账号行被长时间锁住（维护任务、迁移、别的事务卡在半路；同步 / 复盘 / 分享的
/// 每人 advisory 锁同理）：他自己的请求在锁等 5 秒后报错，但其他人不受影响——他在锁上
/// 干等的请求不能把八条连接全占住（`lib.rs` 的 `session_slots`）。
#[tokio::test(flavor="multi_thread",worker_threads=8)]
async fn one_locked_account_does_not_starve_everyone_else() {
 let w=boot().await;let (app,s)=production_app(&w).await;
 let victim=register(&app,400).await;let mut others=vec![];for n in 0..8 {others.push(register(&app,401+n).await);}
 let victim_id:Uuid=sqlx::query_scalar("SELECT user_id FROM account_sessions WHERE device_id=$1").bind(victim.device).fetch_one(&w.admin).await.unwrap();
 let mut lock=w.admin.begin().await.unwrap();
 sqlx::query("SELECT 1 FROM account_users WHERE id=$1 FOR UPDATE").bind(victim_id).execute(&mut *lock).await.unwrap();
 // 受害者同时发 16 个请求：以前每个都攥着一条连接等锁。
 let mut stuck=tokio::task::JoinSet::new();
 for n in 0..16 {let (app,who)=(app.clone(),victim.clone());stuck.spawn(async move {one(&app,&who,n).await});}
 tokio::time::sleep(Duration::from_millis(300)).await;
 let started=Instant::now();let mut set=tokio::task::JoinSet::new();
 for n in 0..80 {let (app,who)=(app.clone(),others[n%8].clone());set.spawn(async move {(one(&app,&who,n).await,Instant::now())});}
 let mut bad=vec![];let mut last=started;
 while let Some(r)=set.join_next().await {let (st,at)=r.unwrap();if st!=StatusCode::OK {bad.push(st)};last=last.max(at);}
 let others_took=last-started;
 // 其他人做完了再放锁：受害者排着的那些请求随后照常成功（没轮上的在锁等上限处 503）。
 lock.rollback().await.unwrap();
 let mut victim_statuses=vec![];while let Some(r)=stuck.join_next().await {victim_statuses.push(r.unwrap().as_u16());}
 victim_statuses.sort();
 eprintln!("row lock: others' 80 requests took {others_took:?} (non-200 {bad:?}); victim's 16 → {victim_statuses:?}");
 assert!(bad.is_empty(),"{bad:?}");
 // 修前 9.8 秒（等两轮锁等超时）；修后和没人被锁时一个量级。
 assert!(others_took<Duration::from_secs(2),"one locked account held everyone else up for {others_took:?}");
 s.pool.close().await;w.close().await;
}
