//! 交易复盘（`kind = "trade"`，docs/交易复盘-协议-2026-09-27.md）的服务端回归：上传、换版、
//! 持仓中→已平仓、校验拒收、按人隔离、导出，以及 worker 按写死的 K 线回写结果与到期排程。
//!
//! 夹具与观点复盘那几份一样（`review_common`）：隔离库、非特权角色、注入式行情。
mod review_common;
use chrono::Utc;
use kanpan_api::review_trade::{JOB,round_id};
use review_common::*;
use serde_json::{Value,json};
use uuid::Uuid;

const MINUTE:i64=60_000;
const HOUR:i64=3_600_000;

/// 一笔成交：时间、方向、数量、价格、角色。
type F=(i64,&'static str,&'static str,&'static str,&'static str);
/// 照协议 2.1 拼一个回合。聚合字段由用例给（服务端不重算，只校验形状）。
struct Spec {symbol:&'static str,side:&'static str,direction:&'static str,fills:Vec<F>,closed:bool,open_avg:&'static str,close_avg:Option<&'static str>,qty:&'static str,realized:&'static str,commission:&'static str,funding:&'static str,net:&'static str,updated:Option<i64>}
fn round(spec:&Spec)->Value {
 let first=spec.fills[0].0;let last=spec.fills.last().unwrap().0;
 let fills:Vec<Value>=spec.fills.iter().enumerate().map(|(n,(t,side,qty,price,role))|json!({
  "id":format!("{}",7_000_000+n),"orderId":format!("{}",9_000_000+n),"time":t,"side":side,"positionSide":spec.side,
  "price":price,"qty":qty,"quoteQty":"0","commission":"0.5","commissionAsset":"USDT","realizedPnl":"0","maker":false,"role":role,"split":false,
 })).collect();
 let id=round_id("binance","usd_m","primary",spec.symbol,spec.side,&fills[0]["id"].as_str().unwrap().to_owned());
 json!({
  "version":1,"id":id,"venue":"binance","market":"usd_m","symbol":spec.symbol,"accountTag":"primary",
  "positionSide":spec.side,"direction":spec.direction,"status":if spec.closed {"closed"} else {"open"},"quoteAsset":"USDT",
  "openedAt":first,"closedAt":spec.closed.then_some(last),"holdingMs":spec.closed.then_some(last-first),
  "openAvgPrice":spec.open_avg,"closeAvgPrice":spec.close_avg,"openedQty":spec.qty,"closedQty":if spec.closed {spec.qty} else {"0"},
  "maxQty":spec.qty,"peakNotional":"210","leverage":10,"realizedPnl":spec.realized,"commission":spec.commission,
  "commissionByAsset":{"USDT":spec.commission},"commissionUnpriced":false,"funding":spec.funding,"netPnl":spec.net,
  "fills":fills,"updatedAt":spec.updated.unwrap_or(last),
 })
}
/// 多头：开 1 @100，加 1 @110（均价 105），平 2 @120；净 29。
fn long(base:i64)->Spec {
 Spec{symbol:"BTCUSDT",side:"BOTH",direction:"long",closed:true,open_avg:"105",close_avg:Some("120"),qty:"2",realized:"30",commission:"1",funding:"0",net:"29",updated:None,
  fills:vec![(base+10_000,"BUY","1","100","open"),(base+70_000,"BUY","1","110","add"),(base+130_000,"SELL","2","120","close")]}
}
/// 空头（双向持仓）：开 2 @100，平 2 @90；净 20。
fn short(base:i64)->Spec {
 Spec{symbol:"ETHUSDT",side:"SHORT",direction:"short",closed:true,open_avg:"100",close_avg:Some("90"),qty:"2",realized:"20",commission:"0",funding:"0",net:"20",updated:None,
  fills:vec![(base+5_000,"SELL","2","100","open"),(base+65_000,"BUY","2","90","close")]}
}
async fn upload(w:&World,a:&Account,rounds:Vec<Value>)->(u16,Value) {
 let (status,v)=request(&w.app,"/v1/native-review/trades","POST",Some(&a.token),Some(Uuid::new_v4()),json!({"rounds":rounds})).await;
 (status.as_u16(),v)
}
async fn upload_ok(w:&World,a:&Account,r:&Value)->Value {
 let (status,v)=upload(w,a,vec![r.clone()]).await;assert_eq!(status,200,"{v}");v["data"]["records"][0].clone()
}
async fn get(w:&World,a:&Account,path:&str)->(u16,Value) {
 let (status,v)=request(&w.app,path,"GET",Some(&a.token),None,json!({})).await;(status.as_u16(),v)
}
async fn rows(w:&World,a:&Account)->i64 {
 sqlx::query_scalar("SELECT count(*) FROM review_records WHERE user_id=$1").bind(a.id).fetch_one(&w.admin).await.unwrap()
}
async fn jobs(w:&World,a:&Account,id:Uuid)->i64 {
 sqlx::query_scalar("SELECT count(*) FROM review_jobs WHERE user_id=$1 AND record_id=$2").bind(a.id).bind(id).fetch_one(&w.admin).await.unwrap()
}
fn id_of(r:&Value)->Uuid {Uuid::parse_str(r["id"].as_str().unwrap()).unwrap()}
/// 整点对齐、两天前：平仓后 24 小时那一格也已经到期。
fn two_days_ago()->i64 {(Utc::now().timestamp_millis()-2*86_400_000).div_euclid(HOUR)*HOUR}
/// 跑这一条记录的结果任务，回来时给出库里的记录。
async fn compute(w:&World,a:&Account,id:Uuid,market:&Market)->Value {
 focus(w,a,id,JOB).await;assert!(run(w,market).await,"应当认领到这条结果任务");stored(w,a,id).await
}
/// 把库里这个回合的所有时刻整体往前挪（模拟时间过去了），结果原样留着。
async fn shift(w:&World,a:&Account,id:Uuid,by:i64) {
 let mut r=stored(w,a,id).await;let round=&mut r["round"];
 for k in ["openedAt","closedAt","updatedAt"] {round[k]=json!(round[k].as_i64().unwrap()-by);}
 for f in round["fills"].as_array_mut().unwrap() {f["time"]=json!(f["time"].as_i64().unwrap()-by);}
 sqlx::query("UPDATE review_records SET record=$3 WHERE user_id=$1 AND id=$2").bind(a.id).bind(id).bind(&r).execute(&w.admin).await.unwrap();
}

/// 上传、重放、同内容再传、晚到的旧版本、持仓中→已平仓、备注；列表 / 详情 / 统计的边界。
#[tokio::test]
async fn upload_overwrites_by_round_id_and_open_becomes_closed() {
 let w=boot().await;let a=signup(&w.app,"qa_trade_up").await;
 let base=two_days_ago();
 // 持仓中：只有开仓那一笔。
 let mut open=long(base);open.closed=false;open.close_avg=None;open.fills.truncate(1);open.qty="1";open.open_avg="100";open.realized="0";open.net="-1";
 let first=round(&open);let id=id_of(&first);
 let key=Uuid::new_v4();
 let (status,v)=request(&w.app,"/v1/native-review/trades","POST",Some(&a.token),Some(key),json!({"rounds":[first]})).await;
 assert_eq!(status,200,"{v}");
 let r=&v["data"]["records"][0];
 assert_eq!(r["kind"],"trade");assert_eq!(r["id"],json!(id));assert_eq!(r["revision"],1);assert_eq!(r["voided"],false);
 assert_eq!(r["result"],Value::Null);assert_eq!(r["note"],Value::Null);assert_eq!(r["round"],first);
 assert_eq!(jobs(&w,&a,id).await,0,"持仓中不排结果任务");
 // 同一个键重放：一字不差地回同一条；同一个键换了内容：拒。
 let (status,again)=request(&w.app,"/v1/native-review/trades","POST",Some(&a.token),Some(key),json!({"rounds":[first]})).await;
 assert_eq!(status,200);assert_eq!(again["data"],v["data"]);
 let mut other=first.clone();other["updatedAt"]=json!(first["updatedAt"].as_i64().unwrap()+1);
 let (status,m)=request(&w.app,"/v1/native-review/trades","POST",Some(&a.token),Some(key),json!({"rounds":[other]})).await;
 assert_eq!(status,409,"{m}");assert_eq!(m["error"]["code"],"idempotency_mismatch");
 // 换一个键、内容相同：不动。
 assert_eq!(upload_ok(&w,&a,&first).await["revision"],1);
 // 大小写不同的同一个 id：同一条，库里存规范的小写。
 let mut upper=first.clone();upper["id"]=json!(id.to_string().to_uppercase());
 assert_eq!(upload_ok(&w,&a,&upper).await["revision"],1);
 // 加仓了、仍持仓：换版。
 let mut added=long(base);added.closed=false;added.close_avg=None;added.fills.truncate(2);added.open_avg="105";added.realized="0";added.net="-1";
 let second=round(&added);assert_eq!(id_of(&second),id,"同一个回合，同一个 id");
 let r=upload_ok(&w,&a,&second).await;assert_eq!(r["revision"],2);assert_eq!(r["round"],second);
 // 晚到的旧版本：丢掉，回库里现在的样子。
 let r=upload_ok(&w,&a,&first).await;assert_eq!(r["revision"],2);assert_eq!(r["round"],second);
 // 平仓：换版、排结果任务。
 let closed=round(&long(base));
 let r=upload_ok(&w,&a,&closed).await;assert_eq!(r["revision"],3);assert_eq!(r["round"]["status"],"closed");assert_eq!(r["result"],Value::Null);
 assert_eq!(rows(&w,&a).await,1,"覆盖，不是重复");
 let j=job(&w,&a,id,JOB).await;assert!(!j.finished);assert!(j.delay<=1.0);
 // 列表：默认不列交易复盘（老客户端解不开）；kind=trade 只列它。
 let (status,v)=get(&w,&a,"/v1/native-review/records").await;assert_eq!(status,200,"{v}");assert_eq!(v["data"]["records"],json!([]));
 let (_,v)=get(&w,&a,"/v1/native-review/records?todo=true").await;assert_eq!(v["data"]["records"],json!([]),"交易复盘不进「待判定」");
 let (status,v)=get(&w,&a,"/v1/native-review/records?kind=trade").await;assert_eq!(status,200,"{v}");
 assert_eq!(v["data"]["records"].as_array().unwrap().len(),1);assert_eq!(v["data"]["records"][0]["id"],json!(id));
 let (_,v)=get(&w,&a,"/v1/native-review/records?kind=trade&symbol=ETHUSDT").await;assert_eq!(v["data"]["records"],json!([]));
 assert_eq!(get(&w,&a,"/v1/native-review/records?kind=view").await.0,400);
 let (status,v)=get(&w,&a,&format!("/v1/native-review/records/{id}")).await;assert_eq!(status,200,"{v}");assert_eq!(v["data"]["record"]["revision"],3);
 assert_eq!(stats(&w,&a).await["groups"],json!([]),"统计不算交易复盘");
 // 观点复盘的改动接口不收交易复盘。
 let (status,v)=request(&w.app,&format!("/v1/native-review/records/{id}/void"),"POST",Some(&a.token),Some(Uuid::new_v4()),json!({"expectedRevision":3})).await;
 assert_eq!(status,400,"{v}");assert_eq!(v["error"]["code"],"invalid_change");
 // 备注：乐观锁、清空、长度。
 let note=|rev:i64,text:&str|json!({"expectedRevision":rev,"text":text});
 let path=format!("/v1/native-review/trades/{id}/note");
 let (status,v)=request(&w.app,&path,"POST",Some(&a.token),Some(Uuid::new_v4()),note(3,"追高了")).await;assert_eq!(status,200,"{v}");
 assert_eq!(v["data"]["record"]["revision"],4);assert_eq!(v["data"]["record"]["note"]["text"],"追高了");
 let (status,v)=request(&w.app,&path,"POST",Some(&a.token),Some(Uuid::new_v4()),note(3,"x")).await;assert_eq!(status,409);assert_eq!(v["error"]["code"],"record_revision_changed");
 let (status,_)=request(&w.app,&path,"POST",Some(&a.token),Some(Uuid::new_v4()),note(4,&"字".repeat(2001))).await;assert_eq!(status,400);
 let (status,v)=request(&w.app,&path,"POST",Some(&a.token),Some(Uuid::new_v4()),note(4,"  ")).await;assert_eq!(status,200,"{v}");
 assert_eq!(v["data"]["record"]["note"],Value::Null);assert_eq!(v["data"]["record"]["revision"],5);
 // 备注不清结果、不动结果任务。
 assert!(!job(&w,&a,id,JOB).await.finished);
 w.close().await;
}

/// 校验拒收：整批不落库。
#[tokio::test]
async fn invalid_rounds_are_refused_whole_batch() {
 let w=boot().await;let a=signup(&w.app,"qa_trade_bad").await;
 let base=two_days_ago();let good=round(&long(base));
 let refuse=|r:Value,code:&'static str|(r,code);
 let mut cases=vec![];
 let mut v=good.clone();v["id"]=json!(Uuid::new_v4());cases.push(refuse(v,"invalid_round_id"));
 let mut v=good.clone();v["version"]=json!(2);cases.push(refuse(v,"unsupported_round_version"));
 let mut v=good.clone();v["netPnl"]=json!("1e5");cases.push(refuse(v,"invalid_round"));
 let mut v=good.clone();v["netPnl"]=json!(29);cases.push(refuse(v,"invalid_round"));
 let mut v=good.clone();v["closedAt"]=Value::Null;cases.push(refuse(v,"invalid_round"));
 let mut v=good.clone();v["openedAt"]=json!(v["openedAt"].as_f64().unwrap()+0.5);cases.push(refuse(v,"invalid_round"));
 let mut v=good.clone();v["fills"]=json!([]);cases.push(refuse(v,"invalid_round"));
 let mut v=good.clone();v["fills"][1]["time"]=json!(base);cases.push(refuse(v,"invalid_round"));
 let mut v=good.clone();v["market"]=json!("spot");cases.push(refuse(v,"invalid_round"));
 let mut v=good.clone();v["updatedAt"]=json!(Utc::now().timestamp_millis()+3_600_000);cases.push(refuse(v,"invalid_round"));
 for (bad,code) in cases {
  let (status,v)=upload(&w,&a,vec![round(&short(base)),bad]).await;
  assert_eq!(status,400,"{code}: {v}");assert_eq!(v["error"]["code"],code);
 }
 assert_eq!(rows(&w,&a).await,0,"有一个不合格，整批都不收");
 let (status,v)=upload(&w,&a,vec![good.clone();101]).await;assert_eq!(status,400);assert_eq!(v["error"]["code"],"too_many_rounds");
 let (status,v)=request(&w.app,"/v1/native-review/trades","POST",Some(&a.token),None,json!({"rounds":[good]})).await;
 assert_eq!(status,400);assert_eq!(v["error"]["code"],"idempotency_key_required");
 let (status,_)=request(&w.app,"/v1/native-review/trades","POST",None,Some(Uuid::new_v4()),json!({"rounds":[]})).await;assert_eq!(status,401);
 let (status,v)=upload(&w,&a,vec![]).await;assert_eq!(status,200);assert_eq!(v["data"]["records"],json!([]));
 w.close().await;
}

/// 按人隔离：别人看不见、改不了；同一个回合 id 在两个人名下是两条。导出带着交易复盘。
#[tokio::test]
async fn trades_are_personal_and_exported() {
 let w=boot().await;let a=signup(&w.app,"qa_trade_a").await;let b=signup(&w.app,"qa_trade_b").await;
 let r=round(&long(two_days_ago()));let id=id_of(&r);
 upload_ok(&w,&a,&r).await;
 assert_eq!(get(&w,&b,&format!("/v1/native-review/records/{id}")).await.0,404);
 assert_eq!(get(&w,&b,"/v1/native-review/records?kind=trade").await.1["data"]["records"],json!([]));
 let (status,_)=request(&w.app,&format!("/v1/native-review/trades/{id}/note"),"POST",Some(&b.token),Some(Uuid::new_v4()),json!({"expectedRevision":1,"text":"x"})).await;assert_eq!(status,404);
 // b 传同一个回合：他自己名下的一条，a 那条纹丝不动。
 let mut theirs=r.clone();theirs["updatedAt"]=json!(r["updatedAt"].as_i64().unwrap()+1);
 assert_eq!(upload_ok(&w,&b,&theirs).await["revision"],1);
 assert_eq!(stored(&w,&a,id).await["round"],r);
 // 运行角色带着 a 的身份，也读不到 b 的行（RLS）。
 let mut tx=w.s.personal(a.id).await.unwrap();
 let seen:i64=sqlx::query_scalar("SELECT count(*) FROM review_records WHERE id=$1").bind(id).fetch_one(&mut *tx).await.unwrap();
 assert_eq!(seen,1);tx.commit().await.unwrap();
 let (status,v)=get(&w,&a,"/v1/auth/me/export").await;assert_eq!(status,200,"{v}");
 let records=v["data"]["review"]["records"].as_array().unwrap();
 assert_eq!(records.len(),1);assert_eq!(records[0]["record"]["kind"],"trade");assert_eq!(records[0]["record"]["round"],r);
 let events=v["data"]["review"]["events"].as_array().unwrap();assert!(events.iter().any(|e|e["kind"]=="trade_uploaded"));
 let (_,v)=get(&w,&b,"/v1/auth/me/export").await;assert_eq!(v["data"]["review"]["records"][0]["record"]["round"],theirs);
 w.close().await;
}

/// 多头：写死的 1m K 线 → 浮盈浮亏、盈亏比、平仓后三格、截图窗口。
#[tokio::test]
async fn long_result_from_fixture_klines() {
 let w=boot().await;let a=signup(&w.app,"qa_trade_long").await;
 let base=two_days_ago();let r=round(&long(base));let id=id_of(&r);upload_ok(&w,&a,&r).await;
 let closed=base+130_000;
 let mut bars=series(base,MINUTE,&[(101.0,95.0,100.0),(112.0,104.0,110.0),(125.0,119.0,121.0)]);
 let after=|h:i64,close:f64|{let t=(closed+h*HOUR).div_euclid(MINUTE)*MINUTE-MINUTE;bar(t,MINUTE,close+1.0,close-1.0,close)};
 bars.extend([after(1,126.0),after(4,114.0),after(24,120.6)]);
 let market=Market::bars(bars);
 let v=compute(&w,&a,id,&market).await;
 let res=&v["result"];
 assert_eq!(v["revision"],2,"{v}");
 assert_eq!(res["version"],1);
 assert_eq!(res["excursion"],json!({"maxFavorable":"40","maxFavorablePct":"0.190476","maxFavorableAt":base+120_000,"maxAdverse":"-5","maxAdversePct":"-0.05","maxAdverseAt":base,"rewardRisk":"5.8"}));
 assert_eq!(res["after"]["h1"],json!({"at":closed+HOUR,"price":"126","changePct":"0.05"}));
 assert_eq!(res["after"]["h4"],json!({"at":closed+4*HOUR,"price":"114","changePct":"-0.05"}));
 assert_eq!(res["after"]["h24"],json!({"at":closed+24*HOUR,"price":"120.6","changePct":"0.005"}));
 assert_eq!(res["unavailable"],json!({}));
 assert_eq!(res["chart"],json!({"interval":"5m","start":base-3_000_000,"end":base+3_300_000}));
 let j=job(&w,&a,id,JOB).await;assert!(j.finished&&!j.leased,"三格都有了，任务收掉");
 let cols:(String,i64,i64)=sqlx::query_as("SELECT timeframe,range_start,range_end FROM review_records WHERE user_id=$1 AND id=$2").bind(a.id).bind(id).fetch_one(&w.admin).await.unwrap();
 assert_eq!(cols,("5m".into(),base-3_000_000,base+3_300_000),"三列跟着截图窗口走");
 let kinds:Vec<String>=sqlx::query_scalar("SELECT kind FROM review_events WHERE user_id=$1 AND record_id=$2 ORDER BY created_at").bind(a.id).bind(id).fetch_all(&w.admin).await.unwrap();
 assert_eq!(kinds,["trade_uploaded","trade_result"]);
 // 结果出来之后成交变了（补进来一笔手续费更正）：结果清空、任务重排。
 let mut fixed=long(base);fixed.net="28";fixed.commission="2";let fixed=round(&{let mut s=fixed;s.updated=Some(closed+1);s});
 let r=upload_ok(&w,&a,&fixed).await;assert_eq!(r["revision"],3);assert_eq!(r["result"],Value::Null);
 assert!(!job(&w,&a,id,JOB).await.finished);
 let v=compute(&w,&a,id,&market).await;assert_eq!(v["result"]["excursion"]["rewardRisk"],"5.6");
 w.close().await;
}

/// 空头：浮盈看低点、浮亏看高点。
#[tokio::test]
async fn short_result_from_fixture_klines() {
 let w=boot().await;let a=signup(&w.app,"qa_trade_short").await;
 let base=two_days_ago();let r=round(&short(base));let id=id_of(&r);upload_ok(&w,&a,&r).await;
 let closed=base+65_000;
 let mut bars=series(base,MINUTE,&[(103.0,99.0,101.0),(95.0,88.0,90.0)]);
 let after=|h:i64,close:f64|{let t=(closed+h*HOUR).div_euclid(MINUTE)*MINUTE-MINUTE;bar(t,MINUTE,close+1.0,close-1.0,close)};
 bars.extend([after(1,99.0),after(4,81.0),after(24,90.0)]);
 let v=compute(&w,&a,id,&Market::bars(bars)).await;let res=&v["result"];
 assert_eq!(res["excursion"],json!({"maxFavorable":"24","maxFavorablePct":"0.12","maxFavorableAt":base+60_000,"maxAdverse":"-6","maxAdversePct":"-0.03","maxAdverseAt":base,"rewardRisk":"3.3333"}));
 // 平仓后的涨跌是价格本身的涨跌，不按方向翻号。
 assert_eq!(res["after"]["h1"]["changePct"],"0.1");assert_eq!(res["after"]["h4"]["changePct"],"-0.1");assert_eq!(res["after"]["h24"]["changePct"],"0");
 w.close().await;
}

/// 到期排程：平仓 2 小时后只填得出浮盈浮亏与 1h，4h / 24h 等到点再补；
/// 等的那几格不算「拿不到」，也不进「待判定」。
#[tokio::test]
async fn cells_are_filled_when_due() {
 let w=boot().await;let a=signup(&w.app,"qa_trade_due").await;
 let now=Utc::now().timestamp_millis();let closed=now-2*HOUR;
 let mut spec=short(closed-65_000);spec.symbol="SOLUSDT";let r=round(&spec);let id=id_of(&r);upload_ok(&w,&a,&r).await;
 let market=Market::wave();
 let v=compute(&w,&a,id,&market).await;let res=&v["result"];
 assert!(res["excursion"].is_object(),"{v}");assert!(res["after"]["h1"].is_object());
 assert_eq!(res["after"]["h4"],Value::Null);assert_eq!(res["after"]["h24"],Value::Null);assert_eq!(res["unavailable"],json!({}));
 let j=job(&w,&a,id,JOB).await;assert!(!j.finished&&!j.leased);
 let due=((closed+4*HOUR+30_000-Utc::now().timestamp_millis()) as f64)/1000.0;
 assert!((j.delay-due).abs()<5.0,"下一次排在 4h 那一格到期：{} vs {due}",j.delay);
 // 还没到点：认领不到。
 assert!(!run(&w,&market).await);
 let (_,list)=get(&w,&a,"/v1/native-review/records?todo=true").await;assert_eq!(list["data"]["records"],json!([]));
 // 过了三小时：4h 那一格补上，已有的不重算，24h 还在等。
 let calls=market.calls();shift(&w,&a,id,3*HOUR).await;
 let v=compute(&w,&a,id,&market).await;let res2=&v["result"];
 assert_eq!(v["revision"],3);assert_eq!(market.calls(),calls+1,"只问了 4h 那一根");
 assert_eq!(res2["excursion"],res["excursion"]);assert_eq!(res2["after"]["h1"],res["after"]["h1"]);
 assert!(res2["after"]["h4"].is_object());assert_eq!(res2["after"]["h24"],Value::Null);
 assert!(!job(&w,&a,id,JOB).await.finished);
 w.close().await;
}

/// 拿不到数据：不编数，留 null 并写原因；交易所缺这一段是终态，被拒一天后再试，暂时不通 60 秒后重试。
#[tokio::test]
async fn unavailable_data_is_null_with_a_reason() {
 let w=boot().await;let a=signup(&w.app,"qa_trade_gap").await;
 let base=two_days_ago();
 let missing=round(&long(base));let id=id_of(&missing);upload_ok(&w,&a,&missing).await;
 let v=compute(&w,&a,id,&Market::bars(vec![])).await;let res=&v["result"];
 assert_eq!(res["excursion"],Value::Null);assert_eq!(res["after"],json!({"h1":null,"h4":null,"h24":null}));
 assert_eq!(res["unavailable"],json!({"excursion":"klines_missing","h1":"klines_missing","h4":"klines_missing","h24":"klines_missing"}));
 assert!(job(&w,&a,id,JOB).await.finished,"交易所没有这一段，不再重试");

 let blocked=round(&short(base));let id=id_of(&blocked);upload_ok(&w,&a,&blocked).await;
 let v=compute(&w,&a,id,&Market::refusing(Reply::Blocked)).await;let res=&v["result"];
 assert_eq!(res["excursion"],Value::Null);assert_eq!(res["unavailable"]["excursion"],"market_region_blocked");
 let j=job(&w,&a,id,JOB).await;assert!(!j.finished);assert!((j.delay-86_400.0).abs()<10.0,"{}",j.delay);
 // 解封之后：补上，原因码跟着消失。
 let v=compute(&w,&a,id,&Market::wave()).await;assert!(v["result"]["excursion"].is_object());assert_eq!(v["result"]["unavailable"],json!({}));

 let mut spec=long(base);spec.symbol="BNBUSDT";let down=round(&spec);let id=id_of(&down);upload_ok(&w,&a,&down).await;
 let v=compute(&w,&a,id,&Market::refusing(Reply::Down)).await;
 assert_eq!(v["result"],Value::Null);assert_eq!(v["revision"],1);
 let j=job(&w,&a,id,JOB).await;assert!(!j.finished);assert!((j.delay-60.0).abs()<10.0);assert_eq!(j.attempts,1,"算一次失败");
 w.close().await;
}

/// 已平仓的回合又变回持仓中（客户端重拼时发现漏了成交）：结果清空、任务收掉，不给持仓中的回合算结果。
#[tokio::test]
async fn reopened_round_drops_its_result() {
 let w=boot().await;let a=signup(&w.app,"qa_trade_reopen").await;
 let base=two_days_ago();let r=round(&long(base));let id=id_of(&r);upload_ok(&w,&a,&r).await;
 compute(&w,&a,id,&Market::wave()).await;
 let mut open=long(base);open.closed=false;open.close_avg=None;open.fills.truncate(2);open.updated=Some(base+200_000);
 let v=upload_ok(&w,&a,&round(&open)).await;assert_eq!(v["result"],Value::Null);assert_eq!(v["round"]["status"],"open");
 assert!(job(&w,&a,id,JOB).await.finished);
 w.close().await;
}
