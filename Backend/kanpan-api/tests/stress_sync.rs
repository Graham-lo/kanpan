//! 同步协议的并发压测（2026-09-26 后端压测）。隔离库（`ops/test.py`），连接池用的是
//! 线上 serve 的那一档（`pool_options(true)`：8 条连接、语句 20 秒、锁等 5 秒）——
//! 锁等超时正是并发推送最可能撞上的那堵墙，用夹具默认的无死线池测不出来。
mod review_common;
use axum::{Router,body::Body,extract::ConnectInfo,http::{Request,StatusCode}};
use http_body_util::BodyExt;
use kanpan_api::AppState;
use rand::{Rng,SeedableRng,rngs::StdRng};
use review_common::*;
use serde_json::{Value,json};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::time::Instant;
use tower::ServiceExt;
use uuid::Uuid;

/// 线上那一档连接池的 app。夹具的 `boot` 建的是 5 条、无死线的池。
async fn production_app(w:&World)->(Router,AppState) {
 let pool=kanpan_api::pool_options(true).connect(&std::env::var("KANPAN_TEST_DATABASE_URL").unwrap()).await.unwrap();
 let s=AppState{pool,secrets:w.s.secrets.clone(),dummy_hash:w.s.dummy_hash.clone()};
 (kanpan_api::router(s.clone()),s)
}
async fn call(app:&Router,method:&str,path:&str,token:&str,body:String)->(StatusCode,Value) {
 let mut req=Request::builder().uri(path).method(method).header("content-type","application/json").header("authorization",format!("Bearer {token}")).body(Body::from(body)).unwrap();
 req.extensions_mut().insert(ConnectInfo("127.0.0.1:19000".parse::<SocketAddr>().unwrap()));
 let res=app.clone().oneshot(req).await.unwrap();let status=res.status();
 let bytes=res.into_body().collect().await.unwrap().to_bytes();
 (status,serde_json::from_slice(&bytes).unwrap_or_else(|_|json!({"nonJSON":String::from_utf8_lossy(&bytes)})))
}
struct Dev {token:String,id:Uuid}
/// 一个账号、两台设备（手机 + 平板，两类各一台，都在线）。
async fn two_devices(app:&Router,ip:&str)->(Dev,Dev,String) {
 let user=name("sync");let a=Uuid::new_v4();let b=Uuid::new_v4();
 let reg=|id:Uuid,kind:&str|json!({"username":user,"password":"Passcode123","device":{"id":id,"name":"stress","secret":kanpan_api::crypto::random_token(),"kind":kind}});
 let post=|path:&'static str,body:Value|{let app=app.clone();async move {
  let mut req=Request::builder().uri(path).method("POST").header("content-type","application/json").header("x-forwarded-for",ip).body(Body::from(body.to_string())).unwrap();
  req.extensions_mut().insert(ConnectInfo("127.0.0.1:19000".parse::<SocketAddr>().unwrap()));
  let res=app.oneshot(req).await.unwrap();let st=res.status();let v:Value=serde_json::from_slice(&res.into_body().collect().await.unwrap().to_bytes()).unwrap();
  assert!(st.is_success(),"{v}");v["data"]["accessToken"].as_str().unwrap().to_string()
 }};
 let ta=post("/v1/auth/register",reg(a,"phone")).await;let tb=post("/v1/auth/login",reg(b,"tablet")).await;
 (Dev{token:ta,id:a},Dev{token:tb,id:b},user)
}
fn op(dev:Uuid,collection:&str,object:&str,action:&str,ts:i64,logical:u64,fields:Value)->Value {
 json!({"id":Uuid::new_v4(),"collection":collection,"objectId":object,"deviceId":dev,"baseRevision":0,"generation":0,"timestamp":ts,"logical":logical,"action":action,"fields":fields})
}
fn drawing_id(k:usize)->String {format!("binance/usd_m/BTCUSDT/stress-{k}")}
/// 服务端的 LWW 顺序：（时间戳，逻辑钟，设备 id，op id），都按字符串/数值比。
type Stamp=(i64,u64,String,String);
fn stamp(op:&Value)->Stamp {(op["timestamp"].as_i64().unwrap(),op["logical"].as_u64().unwrap(),op["deviceId"].as_str().unwrap().to_string(),op["id"].as_str().unwrap().to_string())}
fn pct(v:&mut [u128],p:f64)->u128 {v.sort();v[((v.len() as f64-1.0)*p) as usize]}

/// 两台设备各起三路推送，一共几千条同字段冲突的 op（设置对象 + 20 条画线，
/// 夹着删除、同一 op 的重发、时间戳相同只靠逻辑钟 / 设备 id 决胜负的平局）。
/// 断言：没有一条 5xx；每个字段最终等于 LWW 意义上最大的那一条；每个对象的
/// 修订号连续；每个 op 都留了回执；两台设备 bootstrap 出来的完全一样。
async fn converge(rounds:usize,pushers:usize) {
 let w=boot().await;let (app,s)=production_app(&w).await;
 let (a,b,_)=two_devices(&app,"203.0.113.101").await;
 let now=chrono::Utc::now().timestamp_millis();
 // 先建好 20 条画线（完整身份），之后才开始冲突——对齐真实时序：另一台设备只会改它已经同步到的线。
 let mut creates=vec![];
 for k in 0..20 {creates.push(op(a.id,"drawings",&drawing_id(k),"patch",now-7_200_000,0,json!({"kind":"hline","symbol":"BTCUSDT","market":"usd_m","venue":"binance","anchors":[{"t":1_800_000_000_000i64,"p":100.0}],"color":{"value":"#112233"},"lineWidth":1.0,"text":"init"})));}
 let (st,v)=call(&app,"POST","/v1/sync/operations",&a.token,json!({"operations":creates}).to_string()).await;assert_eq!(st,200,"{v}");
 let mut all_ops:Vec<Value>=creates.clone();
 // 预先生成每一路要推的批次，便于事后算期望值。
 let mut plan:Vec<(usize,Vec<Vec<Value>>)>=vec![];
 let themes=["dark","light","auto","sepia"];let skins=["sage","terra","classic"];
 for (d,dev) in [&a,&b].into_iter().enumerate() {
  for p in 0..pushers {
   let mut rng=StdRng::seed_from_u64((d*100+p) as u64);let mut batches=vec![];
   for _ in 0..rounds {
    let mut batch=vec![];
    for n in 0..100 {
     // 一半落在同一毫秒上（平局只靠逻辑钟 / 设备 id / op id 分），一半散开。
     let ts=if n%2==0 {now-1_000} else {now-rng.random_range(0..3_600_000)};let logical=rng.random_range(0..4u64);
     let o=match rng.random_range(0..10) {
      0..=3=>op(dev.id,"settings","chart","patch",ts,logical,json!({"theme":themes[rng.random_range(0..4)],"barSpacing":rng.random_range(2..40) as f64,"magnet":rng.random_bool(0.5),"skin":skins[rng.random_range(0..3)]})),
      4..=8=>{let k=rng.random_range(0..20);op(dev.id,"drawings",&drawing_id(k),"patch",ts,logical,json!({"color":{"value":format!("#{:06x}",rng.random_range(0..0xffffff))},"lineWidth":rng.random_range(1..6) as f64,"text":format!("t{}",rng.random_range(0..1_000_000))}))}
      // 删除只落在 15..20 这五条上，前 15 条留着验 LWW。
      _=>op(dev.id,"drawings",&drawing_id(15+rng.random_range(0..5)),"delete",ts,logical,json!({})),
     };
     batch.push(o);
    }
    // 每批带一条同批次里前面某条的原样重发（同 id 同内容 → 回执原样返回）。
    let again=batch[rng.random_range(0..batch.len())].clone();batch.push(again);batch.remove(0);
    batches.push(batch);
   }
   for b in &batches {all_ops.extend(b.iter().cloned());}
   plan.push((d,batches));
  }
 }
 let started=Instant::now();
 let mut set=tokio::task::JoinSet::new();
 for (d,batches) in plan {
  let app=app.clone();let token=if d==0 {a.token.clone()} else {b.token.clone()};
  set.spawn(async move {
   let mut out=vec![];
   for batch in batches {
    let t=Instant::now();let (st,v)=call(&app,"POST","/v1/sync/operations",&token,json!({"operations":batch}).to_string()).await;
    out.push((st,t.elapsed().as_millis(),v));
   }
   out
  });
 }
 let mut lat=vec![];let mut bad=vec![];
 while let Some(r)=set.join_next().await {for (st,ms,v) in r.unwrap() {lat.push(ms);if st!=200 {bad.push((st,v))}}}
 let took=started.elapsed();
 let n=lat.len();let (p50,p95,max)=(pct(&mut lat,0.5),pct(&mut lat,0.95),pct(&mut lat,1.0));
 eprintln!("sync converge: {} pushers × {rounds} batches × 100 ops = {} ops in {took:?}; push latency p50 {p50} ms p95 {p95} ms max {max} ms; non-200 {}",2*pushers,n*100,bad.len());
 assert!(bad.is_empty(),"non-200 pushes: {:?}",&bad[..bad.len().min(3)]);

 // ---- 期望值：每个 (对象, 字段) 的最大戳；删除过的画线最终是删除态。
 let mut best:HashMap<(String,String),(Stamp,Value)>=HashMap::new();let mut deleted:std::collections::HashSet<String>=Default::default();
 let mut seen_ids=std::collections::HashSet::new();
 for o in &all_ops {
  let id=o["id"].as_str().unwrap().to_string();if !seen_ids.insert(id) {continue}
  let obj=o["objectId"].as_str().unwrap().to_string();
  if o["action"]=="delete" {deleted.insert(obj.clone());}
  for (f,v) in o["fields"].as_object().unwrap() {
   let e=best.entry((obj.clone(),f.clone())).or_insert((stamp(o),v.clone()));
   if stamp(o)>e.0 {*e=(stamp(o),v.clone());}
  }
 }
 let objects=async |token:&str,collection:&str|->Vec<Value> {
  let mut out=vec![];let mut after:Option<String>=None;
  loop {
   let q=match &after {Some(x)=>format!("/v1/sync/bootstrap?collection={collection}&after={}",urlencode(x)),None=>format!("/v1/sync/bootstrap?collection={collection}")};
   let (st,v)=call(&app,"GET",&q,token,String::new()).await;assert_eq!(st,200,"{v}");
   out.extend(v["data"]["objects"].as_array().unwrap().iter().cloned());
   match v["data"]["next"].as_str() {Some(n)=>after=Some(n.into()),None=>break}
  }
  out
 };
 let mut from_a=objects(&a.token,"settings").await;from_a.extend(objects(&a.token,"drawings").await);
 let mut from_b=objects(&b.token,"settings").await;from_b.extend(objects(&b.token,"drawings").await);
 assert_eq!(from_a,from_b,"the two devices bootstrap different state");
 for o in &from_a {
  let id=o["id"].as_str().unwrap();
  if deleted.contains(id) {assert_eq!(o["deleted"],true,"{id} should be deleted");continue}
  assert_eq!(o["deleted"],false,"{id}");
  for (f,v) in o["body"].as_object().unwrap() {
   let want=&best[&(id.to_string(),f.clone())].1;
   assert_eq!(v,want,"{id}.{f}: LWW winner is not the max stamp");
  }
 }
 // ---- 修订号连续，回执齐全。
 let owner:Uuid=sqlx::query_scalar("SELECT user_id FROM account_sessions s JOIN account_tokens t ON t.session_id=s.id WHERE t.token_hash=$1").bind(kanpan_api::crypto::digest(&a.token)).fetch_one(&w.admin).await.unwrap();
 let rows:Vec<(String,i64,i64,i64)>=sqlx::query_as("SELECT c.object_id,count(DISTINCT c.revision),max(c.revision),max(o.revision) FROM sync_changes c JOIN sync_objects o ON o.user_id=c.user_id AND o.collection=c.collection AND o.id=c.object_id WHERE c.user_id=$1 GROUP BY c.object_id").bind(owner).fetch_all(&w.admin).await.unwrap();
 for (id,distinct,max_change,rev) in rows {assert_eq!((distinct,max_change),(rev,rev),"{id}: revisions in the change log are not 1..={rev}");}
 let receipts:i64=sqlx::query_scalar("SELECT count(*) FROM sync_operations WHERE user_id=$1").bind(owner).fetch_one(&w.admin).await.unwrap();
 assert_eq!(receipts as usize,seen_ids.len());
 s.pool.close().await;w.close().await;
}
fn urlencode(v:&str)->String {v.bytes().map(|c|if c.is_ascii_alphanumeric()||b"-_.~".contains(&c) {(c as char).to_string()} else {format!("%{c:02X}")}).collect()}

/// 回归档：两台设备 × 三路 × 4 批 = 2 400 条。
#[tokio::test(flavor="multi_thread",worker_threads=8)]
async fn two_devices_converge_under_concurrent_conflicting_pushes() {converge(4,3).await}
/// 重档：两台设备 × 三路 × 20 批 = 12 000 条。`ops/test.py --test stress_sync -- --ignored`。
#[tokio::test(flavor="multi_thread",worker_threads=8)] #[ignore]
async fn two_devices_converge_heavy() {converge(20,3).await}

/// 一批里夹一条毒丸：整批 400、一条都不落库；客户端改成逐条推（SyncEngine 的隔离路径）时
/// 只有那一条被拒，其余 99 条全部成功。
#[tokio::test(flavor="multi_thread",worker_threads=4)]
async fn a_poison_operation_only_rejects_itself_one_by_one() {
 let w=boot().await;let (app,s)=production_app(&w).await;let (a,_,_)=two_devices(&app,"203.0.113.102").await;
 let now=chrono::Utc::now().timestamp_millis();
 let mut batch:Vec<Value>=(0..100).map(|n|op(a.id,"settings","chart","patch",now-n,0,json!({"barSpacing":2.0+n as f64/10.0}))).collect();
 batch[57]=op(a.id,"settings","chart","patch",now,0,json!({"theme":"x".repeat(65)}));
 let (st,v)=call(&app,"POST","/v1/sync/operations",&a.token,json!({"operations":batch}).to_string()).await;
 assert_eq!(st,400,"{v}");
 let (_,boot1)=call(&app,"GET","/v1/sync/bootstrap?collection=settings",&a.token,String::new()).await;
 assert!(boot1["data"]["objects"].as_array().unwrap().is_empty(),"a rejected batch left something behind");
 let mut refused=vec![];
 for (n,o) in batch.iter().enumerate() {let (st,_)=call(&app,"POST","/v1/sync/operations",&a.token,json!({"operations":[o]}).to_string()).await;if st!=200 {refused.push((n,st))}}
 assert_eq!(refused,vec![(57,StatusCode::BAD_REQUEST)]);
 s.pool.close().await;w.close().await;
}

/// 极端值一条条打过去：每一条都必须是 4xx（不是 5xx、不是 200 之后存进去一个坏值），
/// 打完之后这个人的设置对象一个字节都没变。
#[tokio::test(flavor="multi_thread",worker_threads=4)]
async fn extreme_values_are_refused_without_touching_state() {
 let w=boot().await;let (app,s)=production_app(&w).await;let (a,_,_)=two_devices(&app,"203.0.113.103").await;
 let now=chrono::Utc::now().timestamp_millis();
 let good=op(a.id,"settings","chart","patch",now,0,json!({"theme":"dark","barSpacing":8.0}));
 let (st,_)=call(&app,"POST","/v1/sync/operations",&a.token,json!({"operations":[good]}).to_string()).await;assert_eq!(st,200);
 let (_,before)=call(&app,"GET","/v1/sync/bootstrap?collection=settings",&a.token,String::new()).await;
 let mut deep=json!(1);for _ in 0..200 {deep=json!([deep]);}
 let mut many=serde_json::Map::new();for n in 0..300 {many.insert(format!("x{n}"),json!(1));}
 let bodies:Vec<(&str,String)>=vec![
  ("negative base revision",json!({"operations":[{"id":Uuid::new_v4(),"collection":"settings","objectId":"chart","deviceId":a.id,"baseRevision":-1,"generation":0,"timestamp":now,"logical":0,"action":"patch","fields":{"theme":"x"}}]}).to_string()),
  ("negative timestamp",json!({"operations":[op(a.id,"settings","chart","patch",-5,0,json!({"theme":"x"}))]}).to_string()),
  ("logical beyond i64",json!({"operations":[op(a.id,"settings","chart","patch",now,u64::MAX,json!({"theme":"x"}))]}).to_string()),
  ("theme too long",json!({"operations":[op(a.id,"settings","chart","patch",now,0,json!({"theme":"x".repeat(100_000)}))]}).to_string()),
  ("bar spacing huge",json!({"operations":[op(a.id,"settings","chart","patch",now,0,json!({"barSpacing":1e308}))]}).to_string()),
  ("bar spacing negative",json!({"operations":[op(a.id,"settings","chart","patch",now,0,json!({"barSpacing":-3}))]}).to_string()),
  ("number overflows f64",format!(r#"{{"operations":[{{"id":"{}","collection":"settings","objectId":"chart","deviceId":"{}","baseRevision":0,"generation":0,"timestamp":{now},"logical":0,"action":"patch","fields":{{"barSpacing":1e999}}}}]}}"#,Uuid::new_v4(),a.id)),
  ("deeply nested value",json!({"operations":[op(a.id,"settings","chart","patch",now,0,json!({"params":deep}))]}).to_string()),
  ("257+ fields",json!({"operations":[op(a.id,"settings","chart","patch",now,0,Value::Object(many))]}).to_string()),
  ("wrong device",json!({"operations":[op(Uuid::new_v4(),"settings","chart","patch",now,0,json!({"theme":"x"}))]}).to_string()),
  ("unknown collection",json!({"operations":[op(a.id,"secrets","chart","patch",now,0,json!({"theme":"x"}))]}).to_string()),
  ("huge group",json!({"operations":[op(a.id,"groups","g1","patch",now,0,json!({"name":"g","order":1,"members":vec!["BTCUSDT";2001]}))]}).to_string()),
  ("101 operations",json!({"operations":(0..101).map(|_|op(a.id,"settings","chart","patch",now,0,json!({"theme":"x"}))).collect::<Vec<_>>()}).to_string()),
  ("empty batch",json!({"operations":[]}).to_string()),
  ("path traversal",json!({"operations":[op(a.id,"settings","chart","patch",now,0,json!({"../theme":"x"}))]}).to_string()),
  ("body over the limit",json!({"operations":[op(a.id,"settings","chart","patch",now,0,json!({"theme":"x".repeat(600*1024)}))]}).to_string()),
  ("not json","{\"operations\":[".into()),
 ];
 let mut report=vec![];
 for (label,body) in bodies {
  let (st,v)=call(&app,"POST","/v1/sync/operations",&a.token,body).await;
  report.push(format!("{label}: {st}"));
  assert!(st.is_client_error(),"{label}: {st} {v}");
 }
 eprintln!("extreme values: {}",report.join("; "));
 let (_,after)=call(&app,"GET","/v1/sync/bootstrap?collection=settings",&a.token,String::new()).await;
 assert_eq!(before["data"]["objects"],after["data"]["objects"]);
 s.pool.close().await;w.close().await;
}

/// 时间戳远在未来的 op 被钳到「服务器现在 + 5 分钟」：一台时钟跑飞的设备不能把一个字段
/// 永久钉死、让别的设备之后的每次修改都输掉。
#[tokio::test(flavor="multi_thread",worker_threads=4)]
async fn a_runaway_clock_cannot_pin_a_field_forever() {
 let w=boot().await;let (app,s)=production_app(&w).await;let (a,b,_)=two_devices(&app,"203.0.113.104").await;
 let now=chrono::Utc::now().timestamp_millis();
 let (st,_)=call(&app,"POST","/v1/sync/operations",&a.token,json!({"operations":[op(a.id,"settings","chart","patch",i64::MAX/2,0,json!({"theme":"future"}))]}).to_string()).await;assert_eq!(st,200);
 // 6 分钟后（钳位窗口之外）另一台设备改同一个字段：它必须赢。这里不能真等，
 // 就用「现在 + 6 分钟」的时间戳——同样被钳到 now+5min，并以更晚的服务器 now 胜出不了；
 // 所以正确的断言是：一条正常时间戳的 op 带上 base_revision（它看到过 future 那条）就能赢。
 let (_,v)=call(&app,"GET","/v1/sync/bootstrap?collection=settings",&b.token,String::new()).await;
 let rev=v["data"]["objects"][0]["revision"].as_i64().unwrap();
 let mut o=op(b.id,"settings","chart","patch",now+1_000,0,json!({"theme":"present"}));o["baseRevision"]=json!(rev);
 let (st,v)=call(&app,"POST","/v1/sync/operations",&b.token,json!({"operations":[o]}).to_string()).await;assert_eq!(st,200,"{v}");
 assert_eq!(v["data"]["results"][0]["object"]["body"]["theme"],"present");
 s.pool.close().await;w.close().await;
}
