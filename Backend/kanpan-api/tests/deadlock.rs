//! P2.6：死锁试验。两条链路以**相反的顺序**碰同两张表，靠项目约定的锁顺序不死锁。
//!
//! 约定写在三处注释里（`src/sync.rs` 的 `lock`、`src/share.rs` 的 `send`、
//! `src/alerts.rs` 的 `record_fired`）：
//!
//! - 同步链路：API 的 `sync::push` 是「sync_objects 行 → alert_watches 行」，worker 的
//!   `alerts::record_fired` 是「alert_watches 行 → sync_objects 行」，正好相反。两边都在拿
//!   任何行锁**之前**先拿同一把 `sync:{owner}` advisory 锁，于是永远排成一队。
//! - 分享链路：A→B 与 B→A 互发，各自先插自己那一行 friendships 再插对方那一行，也正好相反。
//!   两边都按 UUID 从小到大拿 `shares:{uuid}` 两把 advisory 锁，于是也排成一队。
//!
//! 这里分三层证明，缺一层都不算数：
//!
//! 1. **反例**：同一对行锁、相反顺序、不拿 advisory 锁，PostgreSQL 必须报 40P01。
//!    这证明试验本身抓得到死锁——否则后面「没有 40P01」可能只是没撞上。
//!    分享那边再多一条：advisory 锁本身不排序（A 先 B 后 / B 先 A 后）同样 40P01，
//!    证明「按 UUID 排序」这一步不是装饰。
//! 2. **正例**：同一个交错，只是两边都先拿约定的 advisory 锁，两边都提交、没有 40P01。
//! 3. **真函数压测**：不再手写 SQL，而是两个真入口并发各打 N=50 轮——
//!    `POST /v1/sync/operations`（线上 serve 同款池子：lock_timeout=5s）对
//!    `kanpan_api::alerts::record_fired`（线上 worker 同款池子），以及
//!    `POST /v1/shares` A→B 对 B→A。每一轮都必须 200 / Ok，整段有总时限。
//!    约定哪天被人改坏，这里会以 503（死锁被转成 `temporarily_unavailable`）或超时红掉。
//!    这一层的灵敏度实测过（2026-09-23 变异试验，改完即还原）：把 `record_fired` 里的
//!    `sync::lock` 注释掉，push × record_fired 第 0 轮就 503；把 `share::send` 的
//!    「按 UUID 排序」改成「自己先、对方后」，互发第 10 轮 503。
mod review_common;
use axum::{Router,body::Body,extract::ConnectInfo,http::Request};
use http_body_util::BodyExt;
use kanpan_api::AppState;
use review_common::{World,boot,request,signup};
use serde_json::{Value,json};
use sqlx::{PgPool,Postgres,Transaction};
use std::{net::SocketAddr,sync::Arc,time::Duration};
use tokio::sync::Barrier;
use tower::ServiceExt;
use uuid::Uuid;

const ROUNDS:usize=50;
/// 整段压测的总时限。正常一轮是几十毫秒；真死锁会卡满 deadlock_timeout（1s）再报错，
/// 锁等待则会卡满 lock_timeout（5s）——任何一种都会让某一轮失败，这个时限只是兜住「挂死」。
const BUDGET:Duration=Duration::from_secs(180);
const DEADLOCK:&str="40P01";

fn code(e:&sqlx::Error)->String {
 e.as_database_error().and_then(|d|d.code()).map(|c|c.into_owned()).unwrap_or_else(||e.to_string())
}
async fn run(tx:&mut Transaction<'static,Postgres>,sql:&str)->Result<(),String> {
 sqlx::query(sql).execute(&mut **tx).await.map(|_|()).map_err(|e|code(&e))
}
async fn advisory(tx:&mut Transaction<'static,Postgres>,key:&str)->Result<(),String> {
 sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))").bind(key).execute(&mut **tx).await.map(|_|()).map_err(|e|code(&e))
}
/// 跑完剩下那一句并提交；出错就回滚并交回 SQLSTATE。
async fn finish(mut tx:Transaction<'static,Postgres>,sql:&str)->Result<(),String> {
 match run(&mut tx,sql).await {
  Ok(())=>tx.commit().await.map_err(|e|code(&e)),
  Err(c)=>{let _=tx.rollback().await;Err(c)}
 }
}

/// 反例：甲先 `first` 后 `second`，乙先 `second` 后 `first`，谁都不拿 advisory 锁。
/// 先让两边**各自**拿稳第一把锁（顺序执行，不靠调度碰运气），再同时去拿第二把。
async fn crossed(pool:&PgPool,first:&str,second:&str)->[Result<(),String>;2] {
 let mut a=pool.begin().await.unwrap();let mut b=pool.begin().await.unwrap();
 run(&mut a,first).await.unwrap();run(&mut b,second).await.unwrap();
 let (x,y)=tokio::join!(finish(a,second),finish(b,first));
 [x,y]
}

/// 正例：同一个交错，但两边都先按同一顺序拿 `gates` 这几把 advisory 锁。
/// 甲拿到锁、拿了第一把行锁之后，**确认乙真的堵在 advisory 锁上**（查 pg_locks），
/// 再去拿第二把——这就是反例里会死锁的那个时刻。
async fn gated(pool:&PgPool,gates:&[String],first:&str,second:&str)->[Result<(),String>;2] {
 let mut a=pool.begin().await.unwrap();
 for g in gates {advisory(&mut a,g).await.unwrap();}
 run(&mut a,first).await.unwrap();
 let other=pool.clone();let (keys,sql1,sql2)=(gates.to_vec(),first.to_owned(),second.to_owned());
 let b=tokio::spawn(async move {
  let mut b=other.begin().await.unwrap();
  for g in &keys {advisory(&mut b,g).await?;}
  run(&mut b,&sql2).await?;finish(b,&sql1).await
 });
 wait_for_advisory_waiter(pool).await;
 let x=finish(a,second).await;
 [x,b.await.unwrap()]
}
/// 等到本库里出现一个「在等 advisory 锁」的会话。整台 PostgreSQL 是和别的库共用的，
/// 所以按 database 过滤。
async fn wait_for_advisory_waiter(pool:&PgPool) {
 for _ in 0..500 {
  let n:i64=sqlx::query_scalar("SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND NOT granted AND database=(SELECT oid FROM pg_database WHERE datname=current_database())")
   .fetch_one(pool).await.unwrap();
  if n>0 {return}
  tokio::time::sleep(Duration::from_millis(10)).await;
 }
 panic!("乙始终没有堵在 advisory 锁上：试验没有摆出要证明的那个交错");
}
/// 恰好一边是 40P01、另一边提交成功。
fn one_deadlock_victim(r:&[Result<(),String>;2],what:&str) {
 let victims=r.iter().filter(|x|x.as_ref().err().map(String::as_str)==Some(DEADLOCK)).count();
 let committed=r.iter().filter(|x|x.is_ok()).count();
 assert!(victims==1&&committed==1,"{what}：应当恰好一边被判 40P01、另一边提交，实际 {r:?}");
}

// ——————————————————————— 夹具 ———————————————————————

fn alert_fields(armed:i64,price:f64)->Value {
 json!({
  "kind":"drawing","symbol":"BTCUSDT","market":"binance/usd_m",
  "drawingID":"binance/usd_m/BTCUSDT/deadlock-1","condition":"touch","status":"active","once":true,
  "armedAt":armed,"created":armed,"title":"死锁试验",
  "lines":[{"points":[{"t":armed,"p":price},{"t":armed+3_600_000,"p":price}],"extendLeft":false,"extendRight":true}],
 })
}
/// `baseRevision` 永远填 0：`merge` 只在「基线比服务器新」时报 409，0 永远不会；
/// 字段谁赢由 LWW 戳决定。这里要的是每一轮都真的走完整条写路径，不在乎谁赢。
fn operation(device:Uuid,object_id:&str,fields:Value)->Value {
 json!({"id":Uuid::new_v4(),"collection":"alerts","objectId":object_id,"deviceId":device,
  "baseRevision":0,"generation":0,"timestamp":chrono::Utc::now().timestamp_millis(),"logical":0,
  "action":"patch","fields":fields,"importBatch":null})
}
/// 注册一个自己知道设备号的账号（`review_common::signup` 不交出设备号，而推同步要它）。
/// 对端地址单独给一个，不和别的用例抢注册限额。
async fn register(app:&Router,name:&str)->(String,Uuid,Uuid) {
 let device=Uuid::new_v4();
 let body=json!({"username":name,"password":"Passcode123","device":{"id":device,"name":"deadlock","secret":kanpan_api::crypto::random_token()}});
 let mut req=Request::builder().uri("/v1/auth/register").method("POST").header("content-type","application/json").body(Body::from(body.to_string())).unwrap();
 req.extensions_mut().insert(ConnectInfo("203.0.113.66:19000".parse::<SocketAddr>().unwrap()));
 let res=app.clone().oneshot(req).await.unwrap();let status=res.status();
 let v:Value=serde_json::from_slice(&res.into_body().collect().await.unwrap().to_bytes()).unwrap();
 assert_eq!(status,201,"{v}");
 (v["data"]["accessToken"].as_str().unwrap().into(),Uuid::parse_str(v["data"]["user"]["id"].as_str().unwrap()).unwrap(),device)
}
/// 线上两套池子：serve 带死线（`pool_options(true)`，lock_timeout=5s），worker 不带。
async fn state(w:&World,deadlines:bool)->AppState {
 let pool=kanpan_api::pool_options(deadlines).connect(&std::env::var("KANPAN_TEST_DATABASE_URL").unwrap()).await.unwrap();
 AppState{pool,secrets:w.s.secrets.clone(),dummy_hash:w.s.dummy_hash.clone()}
}

// ——————————————————————— 同步链路：push 对 record_fired ———————————————————————

/// 反例 + 正例：sync_objects 那一行与 alert_watches 那一行，以 push / record_fired 各自的
/// 顺序交错去拿。不拿 advisory 锁必死锁；先拿 `sync::lock` 那把就排成一队。
#[tokio::test(flavor="multi_thread",worker_threads=4)]
async fn sync_row_locks_deadlock_without_the_gate_and_queue_behind_it() {
 let w=boot().await;
 let (token,owner,device)=register(&w.app,&review_common::name("qa_dl_sync")).await;
 let id="binance/usd_m/BTCUSDT/deadlock-proof";
 let (status,v)=request(&w.app,"/v1/sync/operations","POST",Some(&token),None,json!({"operations":[operation(device,id,alert_fields(1_800_000_000_000,63_000.0))]})).await;
 assert_eq!(status,200,"{v}");
 // push 的第一把行锁（它先 SELECT … FOR UPDATE 同步对象）与 record_fired 的第一把行锁（它先 UPDATE 物化表）。
 let object=format!("SELECT 1 FROM sync_objects WHERE user_id='{owner}' AND collection='alerts' AND id='{id}' FOR UPDATE");
 let watch=format!("UPDATE alert_watches SET updated_at=now() WHERE user_id='{owner}' AND alert_id='{id}'");

 let r=crossed(&w.admin,&object,&watch).await;
 one_deadlock_victim(&r,"不拿 sync 闸、push 顺序对 record_fired 顺序");

 // 真正的 `sync::lock` 拿的那把：键是 `sync:{owner}`。
 let r=gated(&w.admin,&[format!("sync:{owner}")],&object,&watch).await;
 assert!(r.iter().all(Result::is_ok),"先拿 sync 闸之后两边都该提交：{r:?}");
 w.close().await;
}

/// 真函数压测：API 入口的 `POST /v1/sync/operations` 对 worker 入口的 `record_fired`，
/// 同一个人、同一条提醒，并发 50 轮。
#[tokio::test(flavor="multi_thread",worker_threads=4)]
async fn push_and_record_fired_race_fifty_rounds_without_deadlock() {
 let w=boot().await;
 let serve=state(&w,true).await;let worker=state(&w,false).await;
 let app=kanpan_api::router(serve.clone());
 let (token,owner,device)=register(&app,&review_common::name("qa_dl_race")).await;
 let id="binance/usd_m/BTCUSDT/deadlock-race";
 let armed=1_800_000_000_000i64;
 let (status,v)=request(&app,"/v1/sync/operations","POST",Some(&token),None,json!({"operations":[operation(device,id,alert_fields(armed,63_000.0))]})).await;
 assert_eq!(status,200,"{v}");

 let started=std::time::Instant::now();
 let fired=tokio::time::timeout(BUDGET,async {
  let mut fired=0usize;
  for round in 0..ROUNDS {
   // 每一轮都把物化表摆回 active：record_fired 才会一路走到 apply_server，两张表都碰到。
   sqlx::query("UPDATE alert_watches SET status='active',fired_at=NULL,fired_price=NULL WHERE user_id=$1 AND alert_id=$2").bind(owner).bind(id).execute(&w.admin).await.unwrap();
   let gate=Arc::new(Barrier::new(2));
   let api={
    let (gate,app,token)=(gate.clone(),app.clone(),token.clone());
    let body=json!({"operations":[operation(device,id,alert_fields(armed+round as i64,63_000.0+round as f64))]});
    tokio::spawn(async move {gate.wait().await;request(&app,"/v1/sync/operations","POST",Some(&token),None,body).await})
   };
   let evaluator={
    let (gate,worker)=(gate.clone(),worker.clone());
    tokio::spawn(async move {gate.wait().await;kanpan_api::alerts::record_fired(&worker,owner,id,Some(64_000.0+round as f64),armed+10_000+round as i64).await})
   };
   let (status,v)=api.await.unwrap();
   assert_eq!(status,200,"第 {round} 轮 push 失败（死锁或锁等待超时都会变成 503）：{v}");
   match evaluator.await.unwrap() {
    Ok(true)=>fired+=1,
    Ok(false)=>{},
    Err(e)=>panic!("第 {round} 轮 record_fired 失败：{e:?}"),
   }
  }
  fired
 }).await.expect("压测超出总时限：有一轮挂住了");
 // 物化表每轮都被摆回 active、同步对象一直在，所以 worker 每一轮都应当真的写到了同步日志。
 assert_eq!(fired,ROUNDS,"每一轮 record_fired 都该走完 apply_server，否则这一轮根本没和 push 抢同两把锁");
 let changes:i64=sqlx::query_scalar("SELECT count(*) FROM sync_changes WHERE user_id=$1 AND object_id=$2").bind(owner).bind(id).fetch_one(&w.admin).await.unwrap();
 assert_eq!(changes,1+2*ROUNDS as i64,"初始一条 + 每轮 push 一条 + 每轮 worker 一条");
 println!("push × record_fired：{ROUNDS} 轮全部成功，用时 {:?}，无 40P01",started.elapsed());
 serve.pool.close().await;worker.pool.close().await;w.close().await;
}

// ——————————————————————— 分享链路：A→B 对 B→A ———————————————————————

async fn user_name(w:&World,id:Uuid)->String {
 sqlx::query_scalar("SELECT email FROM account_users WHERE id=$1").bind(id).fetch_one(&w.admin).await.unwrap()
}

/// 反例 + 正例：friendships 的 (A,B) 与 (B,A) 两行，以互发时两边各自的顺序去插。
/// 不拿锁必死锁；advisory 锁不排序也照样死锁；按 UUID 排序拿就排成一队。
#[tokio::test(flavor="multi_thread",worker_threads=4)]
async fn friendship_inserts_deadlock_unless_share_locks_are_sorted() {
 let w=boot().await;
 let a=signup(&w.app,"qa_dl_fa").await.id;let b=signup(&w.app,"qa_dl_fb").await.id;
 let ab=format!("INSERT INTO friendships(user_id,friend_id) VALUES('{a}','{b}') ON CONFLICT DO NOTHING");
 let ba=format!("INSERT INTO friendships(user_id,friend_id) VALUES('{b}','{a}') ON CONFLICT DO NOTHING");
 let clear=format!("DELETE FROM friendships WHERE user_id IN ('{a}','{b}')");

 sqlx::query(&clear).execute(&w.admin).await.unwrap();
 let r=crossed(&w.admin,&ab,&ba).await;
 one_deadlock_victim(&r,"不拿 shares 锁、A→B 对 B→A 插 friendships");

 // advisory 锁本身不排序：A→B 先锁 A、B→A 先锁 B，一样是环。
 let lock=|u:Uuid|format!("SELECT pg_advisory_xact_lock(hashtextextended('shares:{u}',0))");
 let r=crossed(&w.admin,&lock(a),&lock(b)).await;
 one_deadlock_victim(&r,"shares 锁按「自己先、对方后」拿");

 // 约定：两边都按 UUID 从小到大拿 `shares:{uuid}`（`share::send` 的那一行）。
 sqlx::query(&clear).execute(&w.admin).await.unwrap();
 let gates=[format!("shares:{}",a.min(b)),format!("shares:{}",a.max(b))];
 let r=gated(&w.admin,&gates,&ab,&ba).await;
 assert!(r.iter().all(Result::is_ok),"按 UUID 排序拿锁之后两边都该提交：{r:?}");
 w.close().await;
}

/// 真函数压测：A→B 与 B→A 同时 `POST /v1/shares`，50 轮。每轮开始前把两人的朋友关系删掉，
/// 让两边每一轮都真的要插那两行（否则 ON CONFLICT DO NOTHING 不抢任何锁，等于没压）；
/// 同时清掉两人的发信限额（20 次/分钟），否则第 21 轮起就是 429 而不是在抢锁。
#[tokio::test(flavor="multi_thread",worker_threads=4)]
async fn mutual_shares_race_fifty_rounds_without_deadlock() {
 let w=boot().await;
 let serve=state(&w,true).await;let app=kanpan_api::router(serve.clone());
 let a=signup(&app,"qa_dl_sa").await;let b=signup(&app,"qa_dl_sb").await;
 let (name_a,name_b)=(user_name(&w,a.id).await,user_name(&w,b.id).await);
 let limits=vec![serve.secrets.keyed(&format!("share-send:{}",a.id)),serve.secrets.keyed(&format!("share-send:{}",b.id))];
 let payload=|to:&str|json!({"to":to,"symbol":"BTCUSDT","interval":"1h","view":{"from":1_800_000_000_000i64,"to":1_800_003_600_000i64},
  "drawings":[{"id":"line1","kind":"trend","points":[{"t":1_800_000_000_000i64,"p":100},{"t":1_800_003_600_000i64,"p":110}],"lineWidth":1.3,"dash":"solid","filled":true,"locked":false,"hidden":false,"levels":[]}],"alerted":[]});

 let started=std::time::Instant::now();
 tokio::time::timeout(BUDGET,async {
  for round in 0..ROUNDS {
   sqlx::query("DELETE FROM friendships WHERE user_id=ANY($1)").bind(vec![a.id,b.id]).execute(&w.admin).await.unwrap();
   sqlx::query("DELETE FROM account_limits WHERE key=ANY($1)").bind(limits.clone()).execute(&w.admin).await.unwrap();
   let gate=Arc::new(Barrier::new(2));
   let send=|token:String,body:Value|{
    let (gate,app)=(gate.clone(),app.clone());
    tokio::spawn(async move {gate.wait().await;request(&app,"/v1/shares","POST",Some(&token),None,body).await})
   };
   let x=send(a.token.clone(),payload(&name_b));let y=send(b.token.clone(),payload(&name_a));
   for (who,(status,v)) in [("A→B",x.await.unwrap()),("B→A",y.await.unwrap())] {
    assert_eq!(status,200,"第 {round} 轮 {who} 失败（死锁或锁等待超时都会变成 503）：{v}");
   }
  }
 }).await.expect("压测超出总时限：有一轮挂住了");
 let shares:i64=sqlx::query_scalar("SELECT count(*) FROM shares WHERE (from_user=$1 AND to_user=$2) OR (from_user=$2 AND to_user=$1)").bind(a.id).bind(b.id).fetch_one(&w.admin).await.unwrap();
 assert_eq!(shares,2*ROUNDS as i64,"每一轮两封信都该落库");
 let friends:i64=sqlx::query_scalar("SELECT count(*) FROM friendships WHERE user_id=ANY($1)").bind(vec![a.id,b.id]).fetch_one(&w.admin).await.unwrap();
 assert_eq!(friends,2,"最后一轮互发之后双方互为朋友，各一行");
 println!("A→B × B→A：{ROUNDS} 轮全部成功，用时 {:?}，无 40P01",started.elapsed());
 serve.pool.close().await;w.close().await;
}
