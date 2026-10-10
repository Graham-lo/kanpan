//! 条件提醒与品种状态通知碰真库的那几段（`docs/条件提醒-协议-2026-09-27.md`）：
//! 同步上来的形状收不收、物化表存没存 `rule`、老客户端那条 op 会不会把它弄坏、
//! 四种条件各自「按时判、只响一次」，以及品种状态通知每人每个变化只记一次、拉得到。
use kanpan_api::{AppState,crypto::Secrets,conditions::{self,Premium,OiPoint,Bar,walls::{Watch,WallView}}};
use axum::{Router,body::Body,http::{Request,StatusCode},extract::ConnectInfo};
use http_body_util::BodyExt;
use serde_json::{Value,json};
use std::{collections::HashMap,sync::Arc,net::SocketAddr};
use tower::ServiceExt;
use uuid::Uuid;

async fn request(app:&Router,path:&str,method:&str,token:Option<&str>,body:Value)->(StatusCode,Value) {
 let mut req=Request::builder().uri(path).method(method).header("content-type","application/json");
 if let Some(token)=token {req=req.header("authorization",format!("Bearer {token}"));}
 let mut req=req.body(Body::from(body.to_string())).unwrap();
 req.extensions_mut().insert(ConnectInfo("127.0.0.1:19000".parse::<SocketAddr>().unwrap()));
 let result=app.clone().oneshot(req).await.unwrap();let status=result.status();
 let bytes=result.into_body().collect().await.unwrap().to_bytes();
 (status,serde_json::from_slice(&bytes).unwrap_or_else(|_|json!({"nonJSON":true})))
}
fn operation(device:&Value,collection:&str,object_id:&str,base:i64,action:&str,fields:Value)->Value {
 json!({"id":Uuid::new_v4(),"collection":collection,"objectId":object_id,"deviceId":device["id"],
  "baseRevision":base,"generation":0,"timestamp":chrono::Utc::now().timestamp_millis(),"logical":0,
  "action":action,"fields":fields,"importBatch":null})
}
/// 新客户端写的一条条件提醒（协议第 1 节的整张表）。
fn condition(symbol:&str,armed:i64,rule:Value)->Value {
 json!({"kind":"condition","symbol":symbol,"market":"binance/usd_m","condition":"touch","status":"active","once":true,
  "armedAt":armed,"created":armed,"title":"","note":null,"webhook":null,"webhookText":null,"lines":[],"rule":rule})
}

struct Env {admin:sqlx::PgPool,s:AppState,app:Router}
async fn env()->Env {
 let admin_url=std::env::var("KANPAN_TEST_ADMIN_URL").expect("Run ops/test.py; an isolated database is required");
 let admin=sqlx::PgPool::connect(&admin_url).await.unwrap();sqlx::migrate!().run(&admin).await.unwrap();
 let role=std::env::var("KANPAN_TEST_ROLE").unwrap();assert!(role.chars().all(|c|c.is_ascii_alphanumeric()||c=='_'));
 for sql in [format!("GRANT USAGE ON SCHEMA public TO {role}"),format!("GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO {role}"),format!("GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO {role}")] {
  sqlx::query(&sql).execute(&admin).await.unwrap();
 }
 let pool=sqlx::postgres::PgPoolOptions::new().max_connections(6).connect(&std::env::var("KANPAN_TEST_DATABASE_URL").unwrap()).await.unwrap();
 let secrets=Arc::new(Secrets{pepper:vec![31;32],encryption:[43;32]});
 let dummy_hash=Arc::new(secrets.hash_password("dummy123456").unwrap());
 let s=AppState{pool,secrets,dummy_hash};let app=kanpan_api::router(s.clone());
 Env{admin,s,app}
}
struct Who {token:String,owner:Uuid,device:Value}
async fn register(app:&Router,name:&str)->Who {
 let device=json!({"id":Uuid::new_v4(),"name":"A phone","secret":kanpan_api::crypto::random_token()});
 let (status,body)=request(app,"/v1/auth/register","POST",None,json!({"username":name,"password":"Passcode123","device":device})).await;
 assert_eq!(status,201,"{body}");
 Who{token:body["data"]["accessToken"].as_str().unwrap().to_string(),owner:Uuid::parse_str(body["data"]["user"]["id"].as_str().unwrap()).unwrap(),device}
}
async fn push(app:&Router,who:&Who,ops:Vec<Value>)->(StatusCode,Value) {request(app,"/v1/sync/operations","POST",Some(&who.token),json!({"operations":ops})).await}
async fn status_of(e:&Env,owner:Uuid,id:&str)->(String,Option<f64>) {
 sqlx::query_as("SELECT status,fired_price FROM alert_watches WHERE user_id=$1 AND alert_id=$2").bind(owner).bind(id).fetch_one(&e.admin).await.unwrap()
}
fn find<'a>(all:&'a [conditions::CondAlert],id:&str)->&'a conditions::CondAlert {all.iter().find(|a|a.alert_id==id).unwrap_or_else(||panic!("{id} not loaded"))}

#[tokio::test]
async fn real_postgres_condition_alerts_validate_materialize_and_fire_once() {
 let e=env().await;
 let who=register(&e.app,"conditions_test").await;
 let now=chrono::Utc::now().timestamp_millis();
 let armed=now-3*3_600_000;

 // ——— 收什么、拒什么（协议第 7 节）———
 let funding_id="binance/usd_m/BTCUSDT/cond-funding";
 let funding_rule=json!({"type":"funding","side":"above","rate":"0.0005"});
 let (status,v)=push(&e.app,&who,vec![operation(&who.device,"alerts",funding_id,0,"patch",condition("BTCUSDT",armed,funding_rule.clone()))]).await;
 assert_eq!(status,200,"{v}");
 assert!(v["data"]["results"][0]["droppedFields"].as_array().unwrap().is_empty(),"rule 不能被当成未知字段丢掉：{v}");
 let (kind,rule):(String,Option<Value>)=sqlx::query_as("SELECT kind,rule FROM alert_watches WHERE user_id=$1 AND alert_id=$2").bind(who.owner).bind(funding_id).fetch_one(&e.admin).await.unwrap();
 assert_eq!(kind,"condition");assert_eq!(rule,Some(funding_rule.clone()),"物化表存 rule 原样");

 let rejected=[
  ("费率越界",condition("ETHUSDT",armed,json!({"type":"funding","side":"above","rate":"0.5"}))),
  ("费率用了数字",condition("ETHUSDT",armed,json!({"type":"funding","side":"above","rate":0.0005}))),
  ("没有 rule",{let mut f=condition("ETHUSDT",armed,json!(null));f.as_object_mut().unwrap().remove("rule");f}),
  ("rule 是 null",condition("ETHUSDT",armed,json!(null))),
  ("年线",condition("ETHUSDT",armed,json!({"type":"maCross","interval":"1y","length":20,"side":"above"}))),
  ("N 超过 1000",condition("ETHUSDT",armed,json!({"type":"maCross","interval":"4h","length":1001,"side":"above"}))),
  ("大单门槛太低",condition("ETHUSDT",armed,json!({"type":"orderflowWall","threshold":"100"}))),
  ("持仓量门槛不是规范十进制",condition("ETHUSDT",armed,json!({"type":"openInterestChange","threshold":"5%"}))),
  ("rule 超过 1 KB",condition("ETHUSDT",armed,json!({"type":"funding","side":"above","rate":"0.0005","pad":"x".repeat(1100)}))),
 ];
 for (what,fields) in rejected {
  let (status,v)=push(&e.app,&who,vec![operation(&who.device,"alerts","binance/usd_m/ETHUSDT/bad",0,"patch",fields)]).await;
  assert_eq!(status,400,"{what}：{v}");
 }
 // 条件提醒只在币安 U 本位上。
 let mut coinbase=condition("BTC-USD",armed,funding_rule.clone());coinbase["market"]=json!("coinbase/spot");
 let (status,v)=push(&e.app,&who,vec![operation(&who.device,"alerts","coinbase/spot/BTC-USD/cond",0,"patch",coinbase)]).await;
 assert_eq!(status,400,"Coinbase 上不收条件提醒：{v}");
 let bad:i64=sqlx::query_scalar("SELECT count(*) FROM alert_watches WHERE user_id=$1 AND alert_id IN ('binance/usd_m/ETHUSDT/bad','coinbase/spot/BTC-USD/cond')").bind(who.owner).fetch_one(&e.admin).await.unwrap();
 assert_eq!(bad,0);

 // 将来的新条件：收下、存着、不判。
 let future_id="binance/usd_m/BTCUSDT/cond-future";
 let (status,v)=push(&e.app,&who,vec![operation(&who.device,"alerts",future_id,0,"patch",condition("BTCUSDT",armed,json!({"type":"liquidationDistance","ratio":"0.1"})))]).await;
 assert_eq!(status,200,"认不得的 type 不整条拒收：{v}");

 // ——— 老客户端回写（协议第 5 节）———
 // 它把认不得的 kind 当成 drawing 再编码回来（rule 原样留在对象上）：服务端改回 condition，照常 200。
 let (status,v)=push(&e.app,&who,vec![operation(&who.device,"alerts",funding_id,1,"patch",json!({"kind":"drawing","condition":"touch","title":"老客户端改了标题"}))]).await;
 assert_eq!(status,200,"老客户端那条 op 不能堵住队列：{v}");
 let body:Value=sqlx::query_scalar("SELECT body FROM sync_objects WHERE user_id=$1 AND collection='alerts' AND id=$2").bind(who.owner).bind(funding_id).fetch_one(&e.admin).await.unwrap();
 assert_eq!(body["kind"],"condition","规范化回 condition");assert_eq!(body["rule"],funding_rule);assert_eq!(body["title"],"老客户端改了标题");
 let (kind,rule):(String,Option<Value>)=sqlx::query_as("SELECT kind,rule FROM alert_watches WHERE user_id=$1 AND alert_id=$2").bind(who.owner).bind(funding_id).fetch_one(&e.admin).await.unwrap();
 assert_eq!((kind.as_str(),rule),("condition",Some(funding_rule.clone())));
 // 把标题清回空，默认标题才是协议里那句。
 assert_eq!(push(&e.app,&who,vec![operation(&who.device,"alerts",funding_id,2,"patch",json!({"title":""}))]).await.0,200);

 // 价格提醒的形状一点没变：rule 列是 NULL，还是 price 那条评估器在读。
 let price_id="binance/usd_m/BTCUSDT/price-1";
 let price=json!({"kind":"price","symbol":"BTCUSDT","market":"binance/usd_m","condition":"touch","status":"active","once":true,
  "armedAt":armed,"created":armed,"title":"BTC 涨到 90,000","note":null,"webhook":null,"webhookText":null,
  "lines":[{"points":[{"t":armed,"p":90_000.0}],"extendLeft":true,"extendRight":true}]});
 let (status,v)=push(&e.app,&who,vec![operation(&who.device,"alerts",price_id,0,"patch",price)]).await;
 assert_eq!(status,200,"{v}");
 let (kind,rule):(String,Option<Value>)=sqlx::query_as("SELECT kind,rule FROM alert_watches WHERE user_id=$1 AND alert_id=$2").bind(who.owner).bind(price_id).fetch_one(&e.admin).await.unwrap();
 assert_eq!((kind.as_str(),rule),("price",None));

 // ——— 另外三种 ———
 let oi_id="binance/usd_m/BTCUSDT/cond-oi";
 let ma_id="binance/usd_m/BTCUSDT/cond-ma";
 let wall_id="binance/usd_m/1000PEPEUSDT/cond-wall";
 let (status,v)=push(&e.app,&who,vec![
  operation(&who.device,"alerts",oi_id,0,"patch",condition("BTCUSDT",armed,json!({"type":"openInterestChange","threshold":"0.05"}))),
  operation(&who.device,"alerts",ma_id,0,"patch",condition("BTCUSDT",armed,json!({"type":"maCross","interval":"1h","length":3,"side":"above"}))),
  operation(&who.device,"alerts",wall_id,0,"patch",{let mut f=condition("1000PEPEUSDT",armed,json!({"type":"orderflowWall","threshold":"5000000"}));f["webhook"]=json!("https://127.0.0.1:9/never");f}),
 ]).await;
 assert_eq!(status,200,"{v}");

 // 读出来：四条能判的，认不得的那条不在里面，价格提醒不在里面。
 let all=conditions::load(&e.s).await.unwrap();
 let mine:Vec<&conditions::CondAlert>=all.iter().filter(|a|a.owner==who.owner).collect();
 assert_eq!(mine.len(),4,"{mine:?}");
 assert!(mine.iter().all(|a|a.alert_id!=future_id&&a.alert_id!=price_id));
 let all:Vec<conditions::CondAlert>=mine.into_iter().cloned().collect();

 // 费率：窗口外不判；窗口里判一次；过线就响，firedPrice 是标记价格。
 let funding=find(&all,funding_id);
 assert_eq!(funding.title(),"BTC 资金费率高于 0.05%");
 let settle=now+10*60_000;
 let table=HashMap::from([("BTCUSDT".to_string(),Premium{rate:"0.000612".parse().unwrap(),mark:84_943.5,next_funding:settle})]);
 let mut judged=HashMap::new();
 assert!(conditions::judge_funding(std::slice::from_ref(funding),&table,settle-16*60_000,&mut judged).is_empty(),"结算前 16 分钟还不判");
 let hits=conditions::judge_funding(std::slice::from_ref(funding),&table,now,&mut judged);
 assert_eq!(hits.len(),1);
 assert!(conditions::judge_funding(std::slice::from_ref(funding),&table,now+60_000,&mut judged).is_empty(),"同一次结算只判一次");
 let (a,o)=&hits[0];
 assert!(conditions::fire(&e.s,None,a,o).await.unwrap(),"第一次触发");
 assert!(!conditions::fire(&e.s,None,a,o).await.unwrap(),"只响一次");
 assert_eq!(status_of(&e,who.owner,funding_id).await,("fired".into(),Some(84_943.5)));
 // 手机下次拉同步就看到 fired。
 let (_,v)=request(&e.app,"/v1/sync/bootstrap?collection=alerts","GET",Some(&who.token),json!({})).await;
 let object=v["data"]["objects"].as_array().unwrap().iter().find(|o|o["id"]==funding_id).cloned().unwrap();
 assert_eq!(object["body"]["status"],"fired","{object}");assert_eq!(object["body"]["firedPrice"],json!(84_943.5));
 assert_eq!(object["body"]["rule"],funding_rule,"服务端那一下不动 rule");

 // 持仓量：最新点和一小时前比。
 let oi=find(&all,oi_id);
 let last_at=conditions::expected_oi_point(now);
 let mut points:Vec<OiPoint>=(0..13).map(|i|OiPoint{at:last_at-(12-i)*300_000,amount:"100".parse().unwrap(),value:"8400000".parse().unwrap()}).collect();
 assert!(conditions::judge_open_interest(std::slice::from_ref(oi),"BTCUSDT",&points,now).is_empty(),"没变不响");
 points[12].amount="106.21".parse().unwrap();points[12].value="8998000".parse().unwrap();
 let hits=conditions::judge_open_interest(std::slice::from_ref(oi),"BTCUSDT",&points,now);
 assert_eq!(hits.len(),1);
 assert!(hits[0].1.detail.starts_with("1 小时持仓量 +6.21%"),"{}",hits[0].1.detail);
 assert!(conditions::fire(&e.s,None,&hits[0].0,&hits[0].1).await.unwrap());
 assert!(!conditions::fire(&e.s,None,&hits[0].0,&hits[0].1).await.unwrap());
 let (status,price)=status_of(&e,who.owner,oi_id).await;
 assert_eq!(status,"fired");assert!((price.unwrap()-8_998_000.0/106.21).abs()<1e-6);

 // 均线：只在真的收盘穿过的那一根上响，收盘在武装之前的不算。
 let ma=find(&all,ma_id);
 let h=3_600_000;
 let start=(now/h-6)*h;
 let bars:Vec<Bar>=[10.0,10.0,10.0,9.0,12.0].iter().enumerate().map(|(i,c)|Bar{open_time:start+i as i64*h,close:*c,close_time:start+(i as i64+1)*h-1}).collect();
 assert!(conditions::judge_ma(std::slice::from_ref(ma),"BTCUSDT","1h",&bars[..4],now).is_empty(),"还没穿过");
 let hits=conditions::judge_ma(std::slice::from_ref(ma),"BTCUSDT","1h",&bars,now);
 assert_eq!(hits.len(),1);
 assert!(conditions::fire(&e.s,None,&hits[0].0,&hits[0].1).await.unwrap());
 assert!(!conditions::fire(&e.s,None,&hits[0].0,&hits[0].1).await.unwrap());
 assert_eq!(status_of(&e,who.owner,ma_id).await,("fired".into(),Some(12.0)));

 // 大单：武装后第一次看到时就在的老墙不响，新墙响；价按提醒品种的口径乘回 1000；有 Webhook 也照样落库。
 let wall=find(&all,wall_id).clone();
 let (base,scale)=conditions::walls::orderflow_base(&wall.symbol);
 assert_eq!((base.as_str(),scale),("PEPE",1000.0));
 let mut w=Watch::new(wall,scale).unwrap();
 let view=|key:&str,notional:f64,first:i64|WallView{key:key.into(),exchange:"币安".into(),product:"usdtPerp".into(),side:"ask",price:0.0000123,notional,first_seen_ms:first};
 assert!(w.judge(&[view("old",9e6,armed-1)],now).is_none(),"老墙");
 let o=w.judge(&[view("old",9e6,armed-1),view("new",6e6,armed+1)],now).expect("新墙");
 assert_eq!(o.detail,"币安 U 本位 卖墙 6M @ 0.0123");
 assert!(conditions::fire(&e.s,None,&w.alert,&o).await.unwrap());
 assert!(!conditions::fire(&e.s,None,&w.alert,&o).await.unwrap());
 let (status,price)=status_of(&e,who.owner,wall_id).await;
 assert_eq!(status,"fired");assert!((price.unwrap()-0.0123).abs()<1e-12);

 // 触发过的不再被读出来判。
 let left=conditions::load(&e.s).await.unwrap().into_iter().filter(|a|a.owner==who.owner).count();
 assert_eq!(left,0);

 // 暂停的不响：用户在手机上暂停了之后，服务端手里那份旧快照判中了也改不到。
 let paused_id="binance/usd_m/BTCUSDT/cond-paused";
 assert_eq!(push(&e.app,&who,vec![operation(&who.device,"alerts",paused_id,0,"patch",condition("BTCUSDT",armed,json!({"type":"openInterestChange","threshold":"0.05"})))]).await.0,200);
 let snapshot=conditions::load(&e.s).await.unwrap().into_iter().find(|a|a.alert_id==paused_id).unwrap();
 assert_eq!(push(&e.app,&who,vec![operation(&who.device,"alerts",paused_id,1,"patch",json!({"status":"paused"}))]).await.0,200);
 let hits=conditions::judge_open_interest(std::slice::from_ref(&snapshot),"BTCUSDT",&points,now);
 assert!(!conditions::fire(&e.s,None,&hits[0].0,&hits[0].1).await.unwrap(),"暂停了就不响");
 assert_eq!(status_of(&e,who.owner,paused_id).await.0,"paused");
}

#[tokio::test]
async fn real_postgres_listing_notices_go_once_to_people_who_opted_in() {
 use kanpan_api::listing_watch;
 let e=env().await;
 let on=register(&e.app,"listing_on").await;
 let off=register(&e.app,"listing_off").await;
 // 开关跟着账号同步：白名单里有它，不会被当成未知字段丢掉。
 let (status,v)=push(&e.app,&on,vec![
  operation(&on.device,"settings","chart",0,"patch",json!({"notifyListingChanges":true})),
  operation(&on.device,"favorites","binance/usd_m/ABCUSDT",0,"patch",json!({"venue":"binance","market":"usd_m","symbol":"ABCUSDT","order":0})),
 ]).await;
 assert_eq!(status,200,"{v}");
 assert!(v["data"]["results"][0]["droppedFields"].as_array().unwrap().is_empty(),"notifyListingChanges 不能被丢掉：{v}");
 // 只收 bool。设置里的坏值 2026-10-10 起只丢这个字段（回执 `invalidFields` 点名），不拒整条，存着的仍是 true。
 let (status,v)=push(&e.app,&on,vec![operation(&on.device,"settings","chart",1,"patch",json!({"notifyListingChanges":"yes"}))]).await;
 assert_eq!(status,200,"{v}");
 assert_eq!(v["data"]["results"][0]["invalidFields"],json!(["notifyListingChanges"]),"{v}");
 assert_eq!(v["data"]["results"][0]["object"]["body"]["notifyListingChanges"],json!(true),"只收 bool：{v}");
 // 没开的人自选里也有它，但照样不推。
 assert_eq!(push(&e.app,&off,vec![operation(&off.device,"favorites","binance/usd_m/ABCUSDT",0,"patch",json!({"venue":"binance","market":"usd_m","symbol":"ABCUSDT","order":0}))]).await.0,200);

 let far=listing_watch::BINANCE_NO_DELIVERY;
 let perp=|symbol:&str,status:&str,delivery:i64|json!({"symbol":symbol,"contractType":"PERPETUAL","status":status,"deliveryDate":delivery});
 let seed=json!({"symbols":[perp("BTCUSDT","TRADING",far),perp("ABCUSDT","TRADING",far),perp("XYZUSDT","TRADING",far),perp("NEWUSDT","PENDING_TRADING",far)]});
 let now=chrono::Utc::now().timestamp_millis();
 // 第一次只建基线。
 listing_watch::round(&e.s,None,Some(&seed),None,now).await.unwrap();
 let events:i64=sqlx::query_scalar("SELECT count(*) FROM listing_events").fetch_one(&e.admin).await.unwrap();
 assert_eq!(events,0,"空目录只建基线");
 // 明显残缺的一轮跳过，不当成全下架。
 listing_watch::round(&e.s,None,Some(&json!({"symbols":[perp("BTCUSDT","TRADING",far)]})),None,now).await.unwrap();
 let events:i64=sqlx::query_scalar("SELECT count(*) FROM listing_events").fetch_one(&e.admin).await.unwrap();
 assert_eq!(events,0,"只剩四分之一：跳过这一轮");
 // 下一轮：NEW 上线、ABC 排上下架、XYZ 暂停。
 let delivery=now+6*86_400_000;
 let next=json!({"symbols":[perp("BTCUSDT","TRADING",far),perp("ABCUSDT","TRADING",delivery),perp("XYZUSDT","BREAK",far),perp("NEWUSDT","TRADING",far)]});
 listing_watch::round(&e.s,None,Some(&next),None,now+600_000).await.unwrap();
 let kinds:Vec<(String,String)>=sqlx::query_as("SELECT symbol,event FROM listing_events ORDER BY symbol").fetch_all(&e.admin).await.unwrap();
 assert_eq!(kinds,vec![("ABCUSDT".into(),"delistScheduled".into()),("NEWUSDT".into(),"listed".into()),("XYZUSDT".into(),"halted".into())]);
 // 开了开关的人：上新 + 自选里的 ABC；XYZ 不在他自选里。没开的人一条都没有。重跑不重复。
 let notices=|who:Uuid|{let admin=e.admin.clone();async move {sqlx::query_scalar::<_,i64>("SELECT count(*) FROM listing_notices WHERE user_id=$1").bind(who).fetch_one(&admin).await.unwrap()}};
 assert_eq!(notices(on.owner).await,2);
 assert_eq!(notices(off.owner).await,0);
 listing_watch::round(&e.s,None,Some(&next),None,now+1_200_000).await.unwrap();
 assert_eq!(listing_watch::fan_out(&e.s,None,now+1_200_000).await.unwrap(),0,"每个变化每人只记一次");
 assert_eq!(notices(on.owner).await,2);
 // 1 小时之后才开开关的：那时的事件已经过了推送窗口。
 assert_eq!(push(&e.app,&off,vec![operation(&off.device,"settings","chart",0,"patch",json!({"notifyListingChanges":true}))]).await.0,200);
 assert_eq!(listing_watch::fan_out(&e.s,None,now+2*3_600_000).await.unwrap(),0);
 assert_eq!(notices(off.owner).await,0);

 // 拉取：新的在前，deliveryAt 只有将下架那一条有。
 let (status,v)=request(&e.app,"/v1/alerts/listing-notices","GET",Some(&on.token),json!({})).await;
 assert_eq!(status,200,"{v}");
 let list=v["data"]["notices"].as_array().unwrap();
 assert_eq!(list.len(),2,"{v}");
 let abc=list.iter().find(|n|n["symbol"]=="ABCUSDT").unwrap();
 assert_eq!(abc["event"],"delistScheduled");assert_eq!(abc["deliveryAt"],json!(delivery));assert_eq!(abc["title"],"ABCUSDT 将下架");
 assert!(abc["body"].as_str().unwrap().starts_with("币安合约 · "),"{abc}");
 let new=list.iter().find(|n|n["symbol"]=="NEWUSDT").unwrap();
 assert_eq!((new["event"].as_str(),new["title"].as_str(),new["deliveryAt"].is_null(),new["venue"].as_str(),new["market"].as_str()),(Some("listed"),Some("新上线：NEWUSDT"),true,Some("binance"),Some("usd_m")));
 let (_,v)=request(&e.app,"/v1/alerts/listing-notices","GET",Some(&off.token),json!({})).await;
 assert_eq!(v["data"]["notices"],json!([]));
 assert_eq!(request(&e.app,"/v1/alerts/listing-notices","GET",None,json!({})).await.0,401);
 // RLS：没有属主上下文时一行都看不见。
 let seen:i64=sqlx::query_scalar("SELECT count(*) FROM listing_notices").fetch_one(&e.s.pool).await.unwrap();
 assert_eq!(seen,0,"listing_notices must fail closed without an owner context");

 // 30 天前的事件连同通知一起清掉。
 listing_watch::round(&e.s,None,None,None,now+31*86_400_000).await.unwrap();
 let left:i64=sqlx::query_scalar("SELECT count(*) FROM listing_events").fetch_one(&e.admin).await.unwrap();
 assert_eq!(left,0);
 assert_eq!(notices(on.owner).await,0,"通知跟着事件一起走");
}
