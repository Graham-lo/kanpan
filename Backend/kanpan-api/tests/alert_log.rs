//! 提醒触发记录（迁移 0043、`src/alert_log.rs`）真碰数据库的那几段：两条写入路（服务端判响 /
//! 客户端判响同步上来）、同一次触发只留一行、排序 / 条数 / 品种 / since 过滤、DELETE、
//! 30 天清理、RLS 串不了号。列名、唯一约束、策略写错，单测全绿而线上一行都记不下来。
mod review_common;
use review_common::{World,Account,boot,signup,request};
use serde_json::{Value,json};
use uuid::Uuid;

async fn device(w:&World,a:&Account)->Uuid {
 sqlx::query_scalar("SELECT device_id FROM account_sessions WHERE user_id=$1 AND revoked_at IS NULL").bind(a.id).fetch_one(&w.admin).await.unwrap()
}
fn price_fields(symbol:&str,market:&str,target:f64,armed:i64)->Value {
 json!({"kind":"price","symbol":symbol,"market":market,"condition":"touch","status":"active","once":true,
  "armedAt":armed,"created":armed,"title":format!("{symbol} 涨到 {target}"),"note":null,"webhook":null,"webhookText":null,
  "lines":[{"points":[{"t":armed,"p":target}],"extendLeft":true,"extendRight":true}]})
}
fn op(device:Uuid,id:&str,base:i64,action:&str,fields:Value)->Value {
 json!({"id":Uuid::new_v4(),"collection":"alerts","objectId":id,"deviceId":device,"baseRevision":base,"generation":0,
  "timestamp":chrono::Utc::now().timestamp_millis(),"logical":0,"action":action,"fields":fields,"importBatch":null})
}
async fn push(w:&World,a:&Account,ops:Vec<Value>) {
 let (status,v)=request(&w.app,"/v1/sync/operations","POST",Some(&a.token),None,json!({"operations":ops})).await;
 assert_eq!(status,200,"{v}");
 for r in v["data"]["results"].as_array().unwrap() {assert!(r["droppedFields"].as_array().is_none_or(|d|d.is_empty()),"{v}");assert_ne!(r["status"],json!("rejected"),"{v}");}
}
async fn log(w:&World,a:&Account,query:&str)->Vec<Value> {
 let (status,v)=request(&w.app,&format!("/v1/alerts/log{query}"),"GET",Some(&a.token),None,json!({})).await;
 assert_eq!(status,200,"{v}");
 v["data"]["records"].as_array().unwrap().clone()
}

#[tokio::test]
async fn alert_log_records_both_paths_once_filters_clears_purges_and_isolates() {
 let w=boot().await;
 let a=signup(&w.app,"qa_alertlog").await;
 let b=signup(&w.app,"qa_alertlog_b").await;
 let dev=device(&w,&a).await;
 let now=chrono::Utc::now().timestamp_millis();

 // ① 客户端判响：活动 → 已触发同步上来，记一行；字段名与大小写就是协议里那几个。
 let btc="binance/usd_m/BTCUSDT/C1";
 push(&w,&a,vec![op(dev,btc,0,"patch",price_fields("BTCUSDT","binance/usd_m",86_000.0,now-60_000))]).await;
 assert!(log(&w,&a,"").await.is_empty(),"活动中的提醒不记");
 let fired_at=now-30_000;
 push(&w,&a,vec![op(dev,btc,1,"patch",json!({"status":"fired","firedAt":fired_at,"firedPrice":86_010.5}))]).await;
 let records=log(&w,&a,"").await;
 assert_eq!(records.len(),1,"{records:?}");
 let r=&records[0];
 let keys:std::collections::BTreeSet<&str>=r.as_object().unwrap().keys().map(String::as_str).collect();
 assert_eq!(keys,["alertId","condition","firedAt","firedPrice","id","kind","symbol","title"].into_iter().collect());
 assert_eq!(r["alertId"],json!(btc));assert_eq!(r["kind"],json!("price"));
 assert_eq!(r["symbol"],json!("binance/usd_m/BTCUSDT"));assert_eq!(r["title"],json!("BTCUSDT 涨到 86000"));
 assert_eq!(r["condition"],json!("价格达到 86,000"));
 assert_eq!(r["firedAt"],json!(fired_at));assert_eq!(r["firedPrice"],json!(86_010.5));
 assert!(Uuid::parse_str(r["id"].as_str().unwrap()).is_ok());

 // 同一次触发：客户端重推一遍、评估器后到（库里已是 fired）都不再多一行。
 push(&w,&a,vec![op(dev,btc,2,"patch",json!({"status":"fired","firedAt":fired_at,"firedPrice":86_010.5}))]).await;
 assert!(!kanpan_api::alerts::record_fired(&w.s,a.id,btc,Some(86_020.0),fired_at+5).await.unwrap(),"客户端先到，评估器不再触发");
 assert_eq!(log(&w,&a,"").await.len(),1,"去重");
 // 触发即删：客户端随后删掉这条提醒，记录留着。
 push(&w,&a,vec![op(dev,btc,3,"delete",json!({}))]).await;
 assert_eq!(log(&w,&a,"").await.len(),1,"提醒删了，触发记录还在");

 // ② 服务端判响：record_fired 在同一个事务里记一行，Coinbase、条件提醒、复盘到点都是这一条路。
 let cb="coinbase/spot/ETH-USD/S1";
 push(&w,&a,vec![op(dev,cb,0,"patch",price_fields("ETH-USD","coinbase/spot",3_000.0,now-60_000))]).await;
 assert!(kanpan_api::alerts::record_fired(&w.s,a.id,cb,Some(2_999.5),now-20_000).await.unwrap());
 assert!(!kanpan_api::alerts::record_fired(&w.s,a.id,cb,Some(2_999.0),now-19_000).await.unwrap(),"只触发一次");
 let review="binance/usd_m/SOLUSDT/R1";
 push(&w,&a,vec![op(dev,review,0,"patch",json!({"kind":"reviewDue","symbol":"SOLUSDT","market":"binance/usd_m","status":"active","once":true,
  "armedAt":now-60_000,"created":now-60_000,"title":"SOL 到点了","dueAt":now-1000,"reviewID":Uuid::new_v4().to_string(),"lines":[],"condition":"touch",
  "note":null,"webhook":null,"webhookText":null}))]).await;
 assert!(kanpan_api::alerts::record_fired(&w.s,a.id,review,None,now-10_000).await.unwrap());
 let records=log(&w,&a,"").await;
 assert_eq!(records.len(),3);
 // 从新到旧。
 let order:Vec<&str>=records.iter().map(|r|r["alertId"].as_str().unwrap()).collect();
 assert_eq!(order,[review,cb,btc]);
 assert_eq!(records[0]["kind"],json!("reviewDue"));assert_eq!(records[0]["condition"],json!("复盘到点"));assert_eq!(records[0]["firedPrice"],Value::Null,"复盘到点没有价，不拿 0 冒充");
 assert_eq!(records[1]["symbol"],json!("coinbase/spot/ETH-USD"));assert_eq!(records[1]["condition"],json!("价格达到 3,000"));assert_eq!(records[1]["firedPrice"],json!(2_999.5));

 // 条数、品种、since。
 let one=log(&w,&a,"?limit=1").await;assert_eq!(one.len(),1);assert_eq!(one[0]["alertId"],json!(review));
 assert_eq!(log(&w,&a,"?limit=0").await.len(),1,"夹到 1");
 assert_eq!(log(&w,&a,"?limit=100000").await.len(),3,"夹到 500");
 let only=log(&w,&a,"?symbol=BTCUSDT").await;assert_eq!(only.len(),1);assert_eq!(only[0]["alertId"],json!(btc),"裸代号按币安 U 本位");
 assert_eq!(log(&w,&a,"?symbol=coinbase/spot/ETH-USD").await.len(),1);
 assert_eq!(log(&w,&a,&format!("?since={}",now-25_000)).await.len(),2);
 assert_eq!(request(&w.app,"/v1/alerts/log?limit=abc","GET",Some(&a.token),None,json!({})).await.0,400);
 assert_eq!(request(&w.app,"/v1/alerts/log?symbol=BTC%20USDT","GET",Some(&a.token),None,json!({})).await.0,400);
 assert_eq!(request(&w.app,"/v1/alerts/log","GET",None,None,json!({})).await.0,401);

 // 函数层面再写一遍同一次触发：唯一约束兜着。
 let object={let mut tx=w.s.personal(a.id).await.unwrap();
  // 已删掉的提醒读不到同步对象，换一条还活着的来试。
  let o=kanpan_api::sync::read_object(&mut tx,a.id,"alerts",review).await.unwrap().expect("复盘到点不删");tx.commit().await.unwrap();o};
 {let mut tx=w.s.personal(a.id).await.unwrap();kanpan_api::alert_log::record(&mut tx,a.id,&object,None,now-10_000).await.unwrap();tx.commit().await.unwrap();}
 assert_eq!(log(&w,&a,"").await.len(),3,"(user_id, alert_id, fired_at) 唯一");

 // RLS：B 看不见、删不掉 A 的；没有 owner 上下文时一行都看不见。
 assert!(log(&w,&b,"").await.is_empty());
 assert_eq!(request(&w.app,"/v1/alerts/log","DELETE",Some(&b.token),None,json!({})).await.0,204);
 assert_eq!(log(&w,&a,"").await.len(),3,"B 的 DELETE 碰不到 A");
 let seen:i64=sqlx::query_scalar("SELECT count(*) FROM alert_log").fetch_one(&w.s.pool).await.unwrap();
 assert_eq!(seen,0,"alert_log must fail closed without an owner context");
 let forged={let mut tx=w.s.personal(b.id).await.unwrap();
  let r=sqlx::query("INSERT INTO alert_log(user_id,id,alert_id,kind,symbol,fired_at) VALUES($1,$2,'x','price','binance/usd_m/BTCUSDT',1)").bind(a.id).bind(Uuid::new_v4()).execute(&mut *tx).await;r.is_err()};
 assert!(forged,"WITH CHECK 挡住替别人写");

 // 30 天：把 BTC 那一行挪到 31 天前，清理一轮就没了，其余不动。
 sqlx::query("UPDATE alert_log SET fired_at=$3 WHERE user_id=$1 AND alert_id=$2").bind(a.id).bind(btc).bind(now-31*86_400_000).execute(&w.admin).await.unwrap();
 sqlx::query("UPDATE alert_log SET fired_at=$3 WHERE user_id=$1 AND alert_id=$2").bind(a.id).bind(cb).bind(now-29*86_400_000).execute(&w.admin).await.unwrap();
 assert_eq!(kanpan_api::maintenance::cleanup(&w.s).await.unwrap(),0,"no step failed");
 let left:Vec<String>=log(&w,&a,"").await.iter().map(|r|r["alertId"].as_str().unwrap().to_string()).collect();
 assert_eq!(left,[review,cb],"31 天前的清掉，29 天前的留着");
 // 31 天前才报上来的触发（旧设备补报）不记：记了下一轮也是删。
 let stale="binance/usd_m/BTCUSDT/OLD";
 push(&w,&a,vec![op(dev,stale,0,"patch",price_fields("BTCUSDT","binance/usd_m",50_000.0,now-40*86_400_000))]).await;
 push(&w,&a,vec![op(dev,stale,1,"patch",json!({"status":"fired","firedAt":now-35*86_400_000,"firedPrice":50_001.0}))]).await;
 assert_eq!(log(&w,&a,"").await.len(),2);

 // DELETE：带品种只清那一只，不带全清。204，没有正文。
 let (status,_)=request(&w.app,"/v1/alerts/log?symbol=coinbase/spot/ETH-USD","DELETE",Some(&a.token),None,json!({})).await;
 assert_eq!(status,204);
 let left:Vec<String>=log(&w,&a,"").await.iter().map(|r|r["alertId"].as_str().unwrap().to_string()).collect();
 assert_eq!(left,[review]);
 assert_eq!(request(&w.app,"/v1/alerts/log","DELETE",Some(&a.token),None,json!({})).await.0,204);
 assert!(log(&w,&a,"").await.is_empty());
 assert_eq!(request(&w.app,"/v1/alerts/log","DELETE",None,None,json!({})).await.0,401);
 w.close().await;
}

/// 美元指数（2026-10-05 放行 `macro/index`）：自选、画线、对比、价格提醒同步得上来；价格提醒落进
/// `alert_watches`（market = `macro/index`），`run_macro` 用的那个 `load` 盯得上它，响了照样记一行。
/// 别的代号 / 市场的搭配仍然整条拒。
#[tokio::test]
async fn macro_index_dxy_syncs_lands_in_watches_and_logs() {
 let w=boot().await;
 let a=signup(&w.app,"qa_alertlog_dxy").await;
 let dev=device(&w,&a).await;
 let now=chrono::Utc::now().timestamp_millis();
 let any=|collection:&str,id:&str,fields:Value|{
  let mut o=op(dev,id,0,"patch",fields);o["collection"]=json!(collection);o
 };
 push(&w,&a,vec![
  any("favorites","macro/index/DXY",json!({"venue":"macro","market":"index","symbol":"DXY","order":1.0})),
  any("drawings","macro/index/DXY/hline-1",json!({"kind":"hline","venue":"macro","market":"index","symbol":"DXY",
   "anchors":[{"t":now,"p":100.0}],"color":{"value":"#FF8800"},"lineWidth":1.0,"dash":"solid","filled":false,"locked":false,"hidden":false,"levels":[],"created":now})),
  any("settings","chart",json!({"compareSymbols":["macro/index/DXY","binance/usd_m/BTCUSDT"]})),
 ]).await;

 let id="macro/index/DXY/M1";
 push(&w,&a,vec![op(dev,id,0,"patch",price_fields("DXY","macro/index",100.0,now-60_000))]).await;
 let mut tx=w.s.personal(a.id).await.unwrap();
 let row:(String,String,String,String)=sqlx::query_as("SELECT market,symbol,kind,status FROM alert_watches WHERE user_id=$1 AND alert_id=$2")
  .bind(a.id).bind(id).fetch_one(&mut *tx).await.unwrap();
 tx.commit().await.unwrap();
 assert_eq!(row,("macro/index".into(),"DXY".into(),"price".into(),"active".into()));
 let watched=kanpan_api::alerts::watching(&w.s,kanpan_api::alerts::MACRO).await.unwrap();
 assert!(watched.contains(&(id.to_string(),"DXY".to_string())),"run_macro 的判定表里要有它：{watched:?}");
 assert!(!kanpan_api::alerts::watching(&w.s,kanpan_api::alerts::BINANCE).await.unwrap().iter().any(|(i,_)|i==id),"不串到币安那条流");

 assert!(kanpan_api::alerts::record_fired(&w.s,a.id,id,Some(100.02),now-5_000).await.unwrap());
 let records=log(&w,&a,"?symbol=macro/index/DXY").await;
 assert_eq!(records.len(),1,"{records:?}");
 assert_eq!(records[0]["symbol"],json!("macro/index/DXY"));
 assert_eq!(records[0]["condition"],json!("价格达到 100"));

 // 别的搭配仍然拒：代号不是 DXY、市场不是 index、条件提醒挂在美元指数上。
 for (collection,oid,fields) in [
  ("favorites","macro/index/EURUSD",json!({"venue":"macro","market":"index","symbol":"EURUSD"})),
  ("favorites","macro/usd_m/DXY",json!({"venue":"macro","market":"usd_m","symbol":"DXY"})),
  ("alerts","macro/index/DXY/C1",json!({"kind":"condition","symbol":"DXY","market":"macro/index","status":"active","once":true,"armedAt":now,"created":now,
   "title":"x","lines":[],"condition":"touch","rule":{"type":"funding","side":"above","rate":"0.0005"}})),
 ] {
  let (status,v)=request(&w.app,"/v1/sync/operations","POST",Some(&a.token),None,json!({"operations":[any(collection,oid,fields)]})).await;
  assert!(status==400||v["data"]["results"][0]["status"]==json!("rejected"),"{oid} 应被拒：{status} {v}");
 }
 w.close().await;
}
