//! 提醒这条链路上真正碰数据库的那几段：物化表、推送 token 端点、以及「同一条提醒
//! 只触发一次」。单测能覆盖几何与 JWT，但 SQL 的列名、RLS 的策略、ON CONFLICT 的目标
//! 只有真库能验——写错一个列名，单测全绿，线上第一条提醒就静悄悄地丢了。
use kanpan_api::{AppState,crypto::Secrets};
use axum::{Router,body::Body,http::{Request,StatusCode},extract::ConnectInfo};
use http_body_util::BodyExt;
use serde_json::{Value,json};
use std::{sync::Arc,net::SocketAddr};
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
fn alert_fields(armed:i64,price:f64)->Value {
 json!({
  "kind":"drawing","symbol":"BTCUSDT","market":"binance/usd_m",
  "drawingID":"binance/usd_m/BTCUSDT/trend-1","condition":"touch","status":"active","once":true,
  "armedAt":armed,"created":armed,"title":"BTC 触到你画的趋势线",
  "lines":[{"points":[{"t":armed,"p":price},{"t":armed+3_600_000,"p":price}],"extendLeft":false,"extendRight":true}],
 })
}
fn operation(device:&Value,object_id:&str,base:i64,action:&str,fields:Value)->Value {
 json!({"id":Uuid::new_v4(),"collection":"alerts","objectId":object_id,"deviceId":device["id"],
  "baseRevision":base,"generation":0,"timestamp":chrono::Utc::now().timestamp_millis(),"logical":0,
  "action":action,"fields":fields,"importBatch":null})
}

#[tokio::test]
async fn real_postgres_alerts_materialize_fire_once_and_register_tokens() {
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

 let device=json!({"id":Uuid::new_v4(),"name":"A phone","secret":kanpan_api::crypto::random_token()});
 let (status,body)=request(&app,"/v1/auth/register","POST",None,json!({"username":"alerts_test","password":"Passcode123","device":device})).await;
 assert_eq!(status,201,"{body}");
 let token=body["data"]["accessToken"].as_str().unwrap().to_string();
 let owner=Uuid::parse_str(body["data"]["user"]["id"].as_str().unwrap()).unwrap();
 let id="binance/usd_m/BTCUSDT/9F1E";

 // 一条提醒同步上来：sync_objects 与 alert_watches 在同一个事务里都该有它。
 let armed=1_800_000_000_000i64;
 let (status,v)=request(&app,"/v1/sync/operations","POST",Some(&token),json!({"operations":[operation(&device,id,0,"patch",alert_fields(armed,63_000.0))]})).await;
 assert_eq!(status,200,"{v}");
 assert!(v["data"]["results"][0]["droppedFields"].as_array().unwrap().is_empty(),"表 2.2 的字段一个都不该被丢掉：{v}");
 let row=sqlx::query_as::<_,(String,String,i64,Value)>("SELECT symbol,status,armed_at,lines FROM alert_watches WHERE user_id=$1 AND alert_id=$2")
  .bind(owner).bind(id).fetch_one(&admin).await.expect("the alert was materialised");
 assert_eq!(row.0,"BTCUSDT");assert_eq!(row.1,"active");assert_eq!(row.2,armed);
 assert_eq!(row.3[0]["points"][0]["p"],json!(63_000.0));

 // 用户把被提醒的那条线拖到别处：同一个 alert id 再上传一次，几何与 armedAt 一起换掉。
 let moved=armed+600_000;
 let (status,v)=request(&app,"/v1/sync/operations","POST",Some(&token),json!({"operations":[operation(&device,id,1,"patch",alert_fields(moved,64_500.0))]})).await;
 assert_eq!(status,200,"{v}");
 let row=sqlx::query_as::<_,(i64,Value)>("SELECT armed_at,lines FROM alert_watches WHERE user_id=$1 AND alert_id=$2")
  .bind(owner).bind(id).fetch_one(&admin).await.unwrap();
 assert_eq!(row.0,moved,"移动之后重新武装");
 assert_eq!(row.1[0]["points"][0]["p"],json!(64_500.0),"下一帧起用新几何");

 // 推送 token 端点：设备身份从会话反查，不由客户端自称。
 let hex="a".repeat(64);
 let (status,v)=request(&app,"/v1/devices/push-token","POST",Some(&token),json!({"token":hex,"kind":"alerts","environment":"production"})).await;
 assert_eq!(status,200,"{v}");
 let (stored,environment):(String,String)=sqlx::query_as("SELECT token,environment FROM device_push_tokens WHERE user_id=$1 AND kind='alerts'").bind(owner).fetch_one(&admin).await.unwrap();
 assert_eq!(stored,hex);assert_eq!(environment,"production");
 // 同一台设备同一个 kind 重复注册是覆盖，不是第二行。
 let hex2="b".repeat(64);
 assert_eq!(request(&app,"/v1/devices/push-token","POST",Some(&token),json!({"token":hex2,"kind":"alerts","environment":"sandbox"})).await.0,200);
 let count:i64=sqlx::query_scalar("SELECT count(*) FROM device_push_tokens WHERE user_id=$1").bind(owner).fetch_one(&admin).await.unwrap();
 assert_eq!(count,1);
 for bad in [json!({"token":"zz","kind":"alerts","environment":"production"}),
             json!({"token":"a".repeat(64),"kind":"telepathy","environment":"production"}),
             json!({"token":"a".repeat(64),"kind":"alerts","environment":"staging"})] {
  assert_eq!(request(&app,"/v1/devices/push-token","POST",Some(&token),bad.clone()).await.0,400,"{bad}");
 }
 assert_eq!(request(&app,"/v1/devices/push-token","POST",None,json!({"token":"a".repeat(64),"kind":"alerts","environment":"production"})).await.0,401);

 // ——————————— 实时活动：登记、心跳、八小时、结束 ———————————
 //
 // 这一段测的全是只有真库能验的东西：0017 加的那两列叫什么、那条 LEFT JOIN 拼得对不对、
 // 该删的行是不是真的删了。单测验的是内容与取舍，列名写错在那边是全绿的。
 let live="c".repeat(64);
 // liveActivity 这一种必须同时带 activityId 与 alertId：缺哪一个，这一行都会变成一个
 // 推不出去也结束不掉的孤儿，所以在门口就拒掉。
 for bad in [json!({"token":live,"kind":"liveActivity","environment":"production"}),
             json!({"token":live,"kind":"liveActivity","environment":"production","activityId":"ACT-1"}),
             json!({"token":live,"kind":"liveActivity","environment":"production","alertId":id})] {
  assert_eq!(request(&app,"/v1/devices/push-token","POST",Some(&token),bad.clone()).await.0,400,"{bad}");
 }
 let (status,v)=request(&app,"/v1/devices/push-token","POST",Some(&token),json!({"token":live,"kind":"liveActivity","environment":"production","activityId":"ACT-1","alertId":id})).await;
 assert_eq!(status,200,"{v}");
 let (activity,bound,timed):(Option<String>,Option<String>,bool)=sqlx::query_as("SELECT activity_id,alert_id,started_at IS NOT NULL FROM device_push_tokens WHERE user_id=$1 AND kind='liveActivity'").bind(owner).fetch_one(&admin).await.unwrap();
 assert_eq!(activity.as_deref(),Some("ACT-1"));
 assert_eq!(bound.as_deref(),Some(id),"活动盯着哪条提醒要存下来，否则响了不知道该结束谁");
 assert!(timed,"八小时是从 started_at 算的");
 let count:i64=sqlx::query_scalar("SELECT count(*) FROM device_push_tokens WHERE user_id=$1").bind(owner).fetch_one(&admin).await.unwrap();
 assert_eq!(count,2,"alerts 与 liveActivity 是同一台设备上的两行，不互相覆盖");

 // 一拍心跳。**没有密钥也要走完**：发信那一句跳过，其余照常——活动还活着，这一行不动。
 let quotes=std::collections::BTreeMap::new();
 kanpan_api::live_activity::beat(&s,None,&quotes).await.unwrap();
 let left:i64=sqlx::query_scalar("SELECT count(*) FROM device_push_tokens WHERE user_id=$1 AND kind='liveActivity'").bind(owner).fetch_one(&admin).await.unwrap();
 assert_eq!(left,1,"活动还在八小时以内、提醒也还活着，心跳不该把它清掉");

 // 满八小时：心跳推一条 end 再把那一行清掉，提醒本身一动不动。
 sqlx::query("UPDATE device_push_tokens SET started_at=now()-interval '9 hours' WHERE user_id=$1 AND kind='liveActivity'").bind(owner).execute(&admin).await.unwrap();
 kanpan_api::live_activity::beat(&s,None,&quotes).await.unwrap();
 let left:i64=sqlx::query_scalar("SELECT count(*) FROM device_push_tokens WHERE user_id=$1 AND kind='liveActivity'").bind(owner).fetch_one(&admin).await.unwrap();
 assert_eq!(left,0,"八小时到了就 end + 清行");
 let alive:i64=sqlx::query_scalar("SELECT count(*) FROM alert_watches WHERE user_id=$1 AND status='active'").bind(owner).fetch_one(&admin).await.unwrap();
 assert_eq!(alive,1,"结束的是那个活动，不是那条提醒");

 // 提醒响了：只结束 alert_id 对得上的那一个活动。
 assert_eq!(request(&app,"/v1/devices/push-token","POST",Some(&token),json!({"token":live,"kind":"liveActivity","environment":"production","activityId":"ACT-2","alertId":id})).await.0,200);
 let quote=kanpan_api::live_activity::Quote{price:Some(64_500.0),change:Some(-0.0123)};
 kanpan_api::live_activity::end_fired(&s,None,owner,"binance/usd_m/BTCUSDT/0000",quote,None,moved).await.unwrap();
 let left:i64=sqlx::query_scalar("SELECT count(*) FROM device_push_tokens WHERE user_id=$1 AND kind='liveActivity'").bind(owner).fetch_one(&admin).await.unwrap();
 assert_eq!(left,1,"别的提醒响了不许动这个活动");
 kanpan_api::live_activity::end_fired(&s,None,owner,id,quote,Some(64_000.0),moved).await.unwrap();
 let left:i64=sqlx::query_scalar("SELECT count(*) FROM device_push_tokens WHERE user_id=$1 AND kind='liveActivity'").bind(owner).fetch_one(&admin).await.unwrap();
 assert_eq!(left,0,"自己这条提醒响了就 end + 清行");

 // 用户自己把锁屏上那一块划掉：只清行，不推。
 assert_eq!(request(&app,"/v1/devices/push-token","POST",Some(&token),json!({"token":live,"kind":"liveActivity","environment":"production","activityId":"ACT-3","alertId":id})).await.0,200);
 assert_eq!(request(&app,"/v1/devices/live-activity/end","POST",Some(&token),json!({"activityId":"ACT-9"})).await.0,200,"不认识的活动 id 不是错误，只是什么都没删");
 let left:i64=sqlx::query_scalar("SELECT count(*) FROM device_push_tokens WHERE user_id=$1 AND kind='liveActivity'").bind(owner).fetch_one(&admin).await.unwrap();
 assert_eq!(left,1);
 assert_eq!(request(&app,"/v1/devices/live-activity/end","POST",Some(&token),json!({"activityId":"ACT-3"})).await.0,200);
 let left:i64=sqlx::query_scalar("SELECT count(*) FROM device_push_tokens WHERE user_id=$1 AND kind='liveActivity'").bind(owner).fetch_one(&admin).await.unwrap();
 assert_eq!(left,0);
 assert_eq!(request(&app,"/v1/devices/live-activity/end","POST",None,json!({"activityId":"ACT-3"})).await.0,401);

 // 服务端触发：物化表置 fired + 往同步日志写一条 op，同一个事务。
 let at=moved+60_000;
 assert!(kanpan_api::alerts::record_fired(&s,owner,id,64_500.0,at).await.unwrap(),"the server fires it");
 let (status,fired_at,fired_price):(String,Option<i64>,Option<f64>)=sqlx::query_as("SELECT status,fired_at,fired_price FROM alert_watches WHERE user_id=$1 AND alert_id=$2").bind(owner).bind(id).fetch_one(&admin).await.unwrap();
 assert_eq!(status,"fired");assert_eq!(fired_at,Some(at));assert_eq!(fired_price,Some(64_500.0));
 // 客户端下次拉取就该看到 fired——不写同步日志的话，手机上那条提醒会一直显示「活动」。
 let (_,v)=request(&app,"/v1/sync/bootstrap?collection=alerts","GET",Some(&token),json!({})).await;
 let object=&v["data"]["objects"][0];
 assert_eq!(object["body"]["status"],json!("fired"),"{v}");
 assert_eq!(object["body"]["firedPrice"],json!(64_500.0),"{v}");
 assert_eq!(object["revision"],json!(3),"服务端那一下和客户端的改动走同一条路，修订号照常往前");

 // 无密钥模式（线上现在就是这个样子：还没有 Apple 开发者会员，.p8 根本不存在）。
 // 装不出 Apns 来不是错误——而上面这一整段（fired 落库、op 进 alerts 集合、客户端
 // 拉同步看得到）已经全部发生过了，证明推送不是这条链路的前提，只是它的最后一步。
 assert!(kanpan_api::apns::Apns::from_env().is_none(),"no developer account means no key; everything above must still hold");

 // **同一条提醒只触发一次。** 第二次什么都不该发生——客户端前台先置 fired 再同步上来时
 // 走的是同一条路（那时库里已经是 fired），服务端不再推。
 assert!(!kanpan_api::alerts::record_fired(&s,owner,id,70_000.0,at+1).await.unwrap(),"a fired alert does not fire again");
 let price:Option<f64>=sqlx::query_scalar("SELECT fired_price FROM alert_watches WHERE user_id=$1 AND alert_id=$2").bind(owner).bind(id).fetch_one(&admin).await.unwrap();
 assert_eq!(price,Some(64_500.0),"第二次不许把第一次的记录改掉");

 // 删掉提醒：物化表那一行跟着走，评估器不会再订阅这个品种。
 let (status,v)=request(&app,"/v1/sync/operations","POST",Some(&token),json!({"operations":[operation(&device,id,3,"delete",json!({}))]})).await;
 assert_eq!(status,200,"{v}");
 let left:i64=sqlx::query_scalar("SELECT count(*) FROM alert_watches WHERE user_id=$1").bind(owner).fetch_one(&admin).await.unwrap();
 assert_eq!(left,0);

 // RLS 在这两张表上也要 fail closed：没有 owner 上下文时一行都看不见。
 let seen:i64=sqlx::query_scalar("SELECT count(*) FROM device_push_tokens").fetch_one(&s.pool).await.unwrap();
 assert_eq!(seen,0,"device_push_tokens must fail closed without an owner context");
 let seen:i64=sqlx::query_scalar("SELECT count(*) FROM alert_watches").fetch_one(&s.pool).await.unwrap();
 assert_eq!(seen,0,"alert_watches must fail closed without an owner context");
}
