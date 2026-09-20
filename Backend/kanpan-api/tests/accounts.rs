use kanpan_api::{AppState,crypto::Secrets};
use axum::{Router,body::Body,http::{Request,StatusCode},extract::ConnectInfo};
use http_body_util::BodyExt;
use serde_json::{Value,json};
use std::{sync::Arc,net::SocketAddr};
use tower::ServiceExt;
use uuid::Uuid;

async fn request(app:&Router,path:&str,method:&str,token:Option<&str>,body:Value)->(StatusCode,Value) {
 let mut req=Request::builder().uri(path).method(method).header("content-type","application/json");
 if let Some(id)=body.get("_testKey").and_then(Value::as_str) {req=req.header("idempotency-key",id);}
 let mut body=body; if let Some(object)=body.as_object_mut(){object.remove("_testKey");}
 if let Some(token)=token {req=req.header("authorization",format!("Bearer {token}"));}
 let mut req=req.body(Body::from(body.to_string())).unwrap();req.extensions_mut().insert(ConnectInfo("127.0.0.1:19000".parse::<SocketAddr>().unwrap()));
 let result=app.clone().oneshot(req).await.unwrap();let status=result.status();
 let bytes=result.into_body().collect().await.unwrap().to_bytes();
 let body=serde_json::from_slice(&bytes).unwrap_or_else(|_|json!({"nonJSON":true}));(status,body)
}
fn device(name:&str)->Value {json!({"id":Uuid::new_v4(),"name":name,"secret":kanpan_api::crypto::random_token()})}
async fn signup(app:&Router,_s:&AppState,username:&str,d:&Value)->Value {
 let (status,v)=request(app,"/v1/auth/register","POST",None,json!({"username":username,"password":"Passcode123","device":d})).await;assert_eq!(status,201,"{v}");v["data"].clone()
}
fn operation(d:&Value,id:&str,base:i64,action:&str,mut fields:Value)->Value {
 if let Some(color)=fields["color"].as_str().map(str::to_owned) {fields["color"]=json!({"value":color});}
 if base==0&&action=="patch" {fields["kind"]=json!("hline");fields["anchors"]=json!([{"t":1_700_000_000_000.0,"p":100.0}]);fields["symbol"]=json!("BTCUSDT");fields["market"]=json!("usd_m");fields["venue"]=json!("binance");}
 let id=format!("binance/usd_m/{id}");
 json!({"id":Uuid::new_v4(),"collection":"drawings","objectId":id,"deviceId":d["id"],"baseRevision":base,"generation":0,"timestamp":chrono::Utc::now().timestamp_millis(),"logical":0,"action":action,"fields":fields,"importBatch":null})
}
#[tokio::test]
async fn real_postgres_accounts_isolation_and_retry() {
 let admin_url=std::env::var("KANPAN_TEST_ADMIN_URL").expect("Run ops/test.py; an isolated database is required");
 let admin=sqlx::PgPool::connect(&admin_url).await.unwrap();sqlx::migrate!().run(&admin).await.unwrap();
 let role=std::env::var("KANPAN_TEST_ROLE").unwrap();assert!(role.chars().all(|c|c.is_ascii_alphanumeric()||c=='_'));
 for sql in [format!("GRANT USAGE ON SCHEMA public TO {role}"),format!("GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO {role}"),format!("GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO {role}")] {sqlx::query(&sql).execute(&admin).await.unwrap();}
 let pool=sqlx::postgres::PgPoolOptions::new().max_connections(6).connect(&std::env::var("KANPAN_TEST_DATABASE_URL").unwrap()).await.unwrap();
 let secrets=Arc::new(Secrets{pepper:vec![31;32],encryption:[43;32]});let dummy_hash=Arc::new(secrets.hash_password("dummy123456").unwrap());
 let s=AppState{pool,secrets,dummy_hash};let app=kanpan_api::router(s.clone());
 let a_device=device("A phone");let b_device=device("B phone");
 let a=signup(&app,&s,"alice_test",&a_device).await;let b=signup(&app,&s,"bob_test",&b_device).await;
 let at=a["accessToken"].as_str().unwrap();let bt=b["accessToken"].as_str().unwrap();
 let op=operation(&a_device,"BTCUSDT/line",0,"patch",json!({"color":"#FF9900","lineWidth":2}));
 let (status,first)=request(&app,"/v1/sync/operations","POST",Some(at),json!({"operations":[op]})).await;assert_eq!(status,200,"{first}");
 let (_,repeat)=request(&app,"/v1/sync/operations","POST",Some(at),json!({"operations":[op]})).await;assert_eq!(first["data"]["results"],repeat["data"]["results"]);
 let (_,bv)=request(&app,"/v1/sync/bootstrap?collection=drawings","GET",Some(bt),json!({})).await;assert_eq!(bv["data"]["objects"].as_array().unwrap().len(),0);
 let direct:i64=sqlx::query_scalar("SELECT count(*) FROM sync_objects").fetch_one(&s.pool).await.unwrap();assert_eq!(direct,0,"RLS must fail closed with no owner context");
 let (status,_)=request(&app,"/v1/sync/operations","POST",Some(bt),json!({"operations":[op]})).await;assert_eq!(status,400,"device identity cannot cross accounts");
 // Two accounts may use the same object ID without sharing content.
 let bop=operation(&b_device,"BTCUSDT/line",0,"patch",json!({"color":"#000000"}));
 assert_eq!(request(&app,"/v1/sync/operations","POST",Some(bt),json!({"operations":[bop]})).await.0,200);
 let del=operation(&a_device,"BTCUSDT/line",1,"delete",json!({}));
 assert_eq!(request(&app,"/v1/sync/operations","POST",Some(at),json!({"operations":[del]})).await.0,200);
 let stale=operation(&a_device,"BTCUSDT/line",1,"patch",json!({"color":"#00FF00"}));
 let (status,v)=request(&app,"/v1/sync/operations","POST",Some(at),json!({"operations":[stale]})).await;assert_eq!(status,200);assert_eq!(v["data"]["results"][0]["object"]["deleted"],true);
 // No truncation of a 60-object archive at the old chart's limit of 50.
 let ops:Vec<_>=(0..60).map(|n|operation(&a_device,&format!("BTCUSDT/{n:03}"),0,"patch",json!({"lineWidth":1}))).collect();
 assert_eq!(request(&app,"/v1/sync/operations","POST",Some(at),json!({"operations":ops})).await.0,200);
 let (_,v)=request(&app,"/v1/sync/bootstrap?collection=drawings","GET",Some(at),json!({})).await;assert_eq!(v["data"]["objects"].as_array().unwrap().len(),61);
 // /v1/sync/changes resolves subscribed rows through one join instead of a
 // query per change: in-scope rows carry the current object, everything else
 // stays an invalidation, and the cursor still walks past both kinds.
 let (_,ch)=request(&app,"/v1/sync/changes?cursor=0&collection=drawings&prefix=binance/usd_m/BTCUSDT/00","GET",Some(at),json!({})).await;
 let objects=ch["data"]["objects"].as_array().unwrap().clone();let invalidations=ch["data"]["invalidations"].as_array().unwrap().clone();
 assert_eq!(objects.len(),10,"{ch}");
 assert!(objects.iter().all(|o|o["id"].as_str().unwrap().starts_with("binance/usd_m/BTCUSDT/00")&&o["body"]["lineWidth"]==1&&o["collection"]=="drawings"),"{ch}");
 assert!(invalidations.iter().any(|v|v["id"]=="binance/usd_m/BTCUSDT/line"&&v["deleted"]==true),"{ch}");
 assert_eq!(objects.len()+invalidations.len(),63,"every change is reported exactly once: {ch}");
 assert_eq!(ch["data"]["hasMore"],false);
 let (_,all)=request(&app,"/v1/sync/changes?cursor=0","GET",Some(at),json!({})).await;
 assert!(all["data"]["objects"].as_array().unwrap().is_empty(),"an unscoped poll invalidates, it does not download: {all}");
 assert_eq!(all["data"]["invalidations"].as_array().unwrap().len(),63,"{all}");
 let tail=ch["data"]["cursor"].as_i64().unwrap();
 let (_,none)=request(&app,&format!("/v1/sync/changes?cursor={tail}&collection=drawings"),"GET",Some(at),json!({})).await;
 assert!(none["data"]["objects"].as_array().unwrap().is_empty()&&none["data"]["invalidations"].as_array().unwrap().is_empty(),"{none}");
 let (_,other)=request(&app,"/v1/sync/changes?cursor=0&collection=drawings","GET",Some(bt),json!({})).await;
 let mine=other["data"]["objects"].as_array().unwrap();
 assert!(mine.len()==1&&mine[0]["id"]=="binance/usd_m/BTCUSDT/line"&&mine[0]["body"]["color"]["value"]=="#000000","the join must stay owner-scoped: {other}");
 let alice=Uuid::parse_str(a["user"]["id"].as_str().unwrap()).unwrap();
 review_contract(&app,&s,&admin,alice,at,bt).await;
 search_contract(&app,&s,&admin,alice,at,bt).await;
 // 用户名归一化之后不能被重复注册。
 assert_eq!(request(&app,"/v1/auth/register","POST",None,json!({"username":"ALICE_TEST","password":"Passcode123","device":a_device})).await.0,409);
 assert_eq!(request(&app,"/v1/auth/register","POST",None,json!({"username":"x","password":"Passcode123","device":a_device})).await.0,400);
 // 邮箱验证码那条路已经整条下线，连路由都不该还在。
 assert_eq!(request(&app,"/v1/auth/password/code","POST",None,json!({"email":"alice_test"})).await.0,404);
 // Identical refresh retry returns the same rotated pair, a different reuse revokes the family.
 let rid=Uuid::new_v4();let refresh=json!({"refreshToken":a["refreshToken"],"requestId":rid,"device":a_device});
 let (status,new)=request(&app,"/v1/auth/refresh","POST",None,refresh.clone()).await;assert_eq!(status,200,"{new}");
 assert_eq!(new,request(&app,"/v1/auth/refresh","POST",None,refresh).await.1);
 let reuse=json!({"refreshToken":a["refreshToken"],"requestId":Uuid::new_v4(),"device":a_device});
 assert_eq!(request(&app,"/v1/auth/refresh","POST",None,reuse).await.0,401);
 assert_eq!(request(&app,"/v1/auth/me","GET",new["data"]["accessToken"].as_str(),json!({})).await.0,401);
 // A five-attempt lock applies even when the next password is correct.
 for _ in 0..5 {assert_eq!(request(&app,"/v1/auth/login","POST",None,json!({"email":"bob_test","password":"wrongpass","device":b_device})).await.0,401);}
 assert_eq!(request(&app,"/v1/auth/login","POST",None,json!({"email":"bob_test","password":"Passcode123","device":b_device})).await.0,401);
 let (status,v)=request(&app,"/v1/auth/account","DELETE",Some(bt),json!({"password":"Passcode123"})).await;assert_eq!(status,200,"{v}");
 assert_eq!(request(&app,"/v1/auth/me","GET",Some(bt),json!({})).await.0,401);
 let remaining:i64=sqlx::query_scalar("SELECT count(*) FROM sync_objects WHERE user_id=$1").bind(Uuid::parse_str(b["user"]["id"].as_str().unwrap()).unwrap()).fetch_one(&admin).await.unwrap();assert_eq!(remaining,0);
 s.pool.close().await;admin.close().await;
}

async fn review_contract(app:&Router,s:&AppState,admin:&sqlx::PgPool,owner:Uuid,at:&str,bt:&str) {
 let now=chrono::Utc::now().timestamp_millis();let end=now/60_000*60_000;
 let make=||json!({"id":Uuid::new_v4(),"range":{"venue":"binance","market":"usd_m","symbol":"BTCUSDT","interval":"1m","start":end-180_000,"end":end,"bars":3},"rule":{"version":"criteria-v2","direction":"long","confirmation":"bar_close","reference":100.0,"target":110.0,"invalidation":90.0,"expires":now+3_600_000},"text":"","origin":"chart_first","created":now,"_testKey":Uuid::new_v4()});
 let draft=make();let id=draft["id"].as_str().unwrap();
 let (status,response)=request(app,"/v1/native-review/records","POST",Some(at),draft.clone()).await;assert_eq!(status,200,"{response}");
 assert_eq!(response,request(app,"/v1/native-review/records","POST",Some(at),draft.clone()).await.1);
 let path=format!("/v1/native-review/records/{id}");
 assert_eq!(request(app,&path,"GET",Some(bt),json!({})).await.0,404);
 let direct:i64=sqlx::query_scalar("SELECT count(*) FROM review_records").fetch_one(&s.pool).await.unwrap();assert_eq!(direct,0);
 assert_eq!(request(app,&path,"GET",Some(at),json!({})).await.0,200);
 let edit=json!({"_testKey":Uuid::new_v4(),"expectedRevision":0,"reflection":{"note":"先等收盘","nextTime":"少画一条线","revision":0,"publishedAt":null},"publish":true});
 let change_path=format!("{path}/reflection");
 let (status,changed)=request(app,&change_path,"POST",Some(at),edit.clone()).await;assert_eq!(status,200,"{changed}");
 assert_eq!(changed["data"]["record"]["revision"],1);
 assert_eq!(changed,request(app,&change_path,"POST",Some(at),edit.clone()).await.1);
 let mut stale=edit.clone();stale["_testKey"]=json!(Uuid::new_v4());
 assert_eq!(request(app,&change_path,"POST",Some(at),stale).await.0,409);
 assert_eq!(request(app,&change_path,"POST",Some(bt),edit).await.0,404);
 let mut invalid=make();invalid["range"]["start"]=json!(end-180_000+1);
 assert_eq!(request(app,"/v1/native-review/records","POST",Some(at),invalid).await.0,400);
 let mut invalid=make();use base64::Engine;
 invalid["chartSettings"]=json!(base64::engine::general_purpose::STANDARD.encode(br#"{"version":1,"fields":{"apiHost":"https://private.example"}}"#));
 assert_eq!(request(app,"/v1/native-review/records","POST",Some(at),invalid).await.0,400);
 for _ in 0..51 {assert_eq!(request(app,"/v1/native-review/records","POST",Some(at),make()).await.0,200);}
 let (_,page)=request(app,"/v1/native-review/records","GET",Some(at),json!({})).await;
 assert_eq!(page["data"]["records"].as_array().unwrap().len(),50);
 let cursor=page["data"]["next"].as_str().unwrap();
 let (_,tail)=request(app,&format!("/v1/native-review/records?after={cursor}"),"GET",Some(at),json!({})).await;
 assert_eq!(tail["data"]["records"].as_array().unwrap().len(),2);assert!(tail["data"]["next"].is_null());
 let ids:std::collections::HashSet<_>=page["data"]["records"].as_array().unwrap().iter().chain(tail["data"]["records"].as_array().unwrap()).map(|v|v["serverId"].as_str().unwrap()).collect();assert_eq!(ids.len(),52);
 let (_,empty)=request(app,"/v1/native-review/records","GET",Some(bt),json!({})).await;assert!(empty["data"]["records"].as_array().unwrap().is_empty());
 let (status,voided)=request(app,&format!("{path}/void"),"POST",Some(at),json!({"_testKey":Uuid::new_v4(),"expectedRevision":1})).await;assert_eq!(status,200,"{voided}");assert_eq!(voided["data"]["record"]["voided"],true);
 // 同样先摆 RLS 上下文再读（见 search_contract 里那段注释）。顺带把「一共有几条」也数出来：
 // 只断言「没有未完成的」在一行都看不见的时候会白白通过，那等于什么都没验。
 let mut conn=admin.acquire().await.unwrap();
 sqlx::query("SELECT set_config('kanpan.user_id',$1,false)").bind(owner.to_string()).execute(&mut *conn).await.unwrap();
 let (total,unfinished):(i64,i64)=sqlx::query_as("SELECT count(*),count(*) FILTER (WHERE NOT finished) FROM review_jobs WHERE user_id=$1 AND record_id=$2").bind(owner).bind(Uuid::parse_str(id).unwrap()).fetch_one(&mut *conn).await.unwrap();
 assert!(total>0&&unfinished==0,"作废之后这条记录的任务该一条不剩地收干净：{total} 条里还有 {unfinished} 条没完");
 let (_,stats)=request(app,"/v1/native-review/statistics","GET",Some(at),json!({})).await;assert!(stats["data"]["groups"].as_array().unwrap().is_empty(),"Unverified and pending episode records cannot enter statistics");
}

struct FixtureMarket;
fn fixture_bars(start:chrono::DateTime<chrono::Utc>,end:chrono::DateTime<chrono::Utc>)->Vec<scorebook_core::domain::criteria::Bar> {
 let mut bars=vec![];let mut at=start;let mut n=0;
 while at<end {let base=100.0+n as f64*0.3+(n as f64*0.6).sin();
  bars.push(scorebook_core::domain::criteria::Bar{start:at,end:at+chrono::Duration::minutes(1),open:base.to_string(),high:(base+2.0).to_string(),low:(base-1.0).to_string(),close:(base+0.5).to_string(),volume:Some("100".into())});at+=chrono::Duration::minutes(1);n+=1;
 }bars
}
impl scorebook_core::market::MarketDataProvider for FixtureMarket {
 fn klines<'a>(&'a self,_:&'a str,_:&'a str,_:&'a str,start:chrono::DateTime<chrono::Utc>,end:chrono::DateTime<chrono::Utc>)->scorebook_core::market::ProviderFuture<'a>{Box::pin(async move{Ok(json!({"coverage_complete":true,"bars":fixture_bars(start,end)}))})}
 fn trades<'a>(&'a self,_:&'a str,_:&'a str,_:chrono::DateTime<chrono::Utc>,_:chrono::DateTime<chrono::Utc>)->scorebook_core::market::ProviderFuture<'a>{Box::pin(async{Ok(json!({"coverage_complete":true,"raw":[]}))})}
 fn exchange_info<'a>(&'a self,_:&'a str)->scorebook_core::market::ProviderFuture<'a>{Box::pin(async{Ok(json!({}))})}
 fn tickers_24h<'a>(&'a self,_:&'a str)->scorebook_core::market::ProviderFuture<'a>{Box::pin(async{Ok(json!({}))})}
}
async fn search_contract(app:&Router,s:&AppState,admin:&sqlx::PgPool,owner:Uuid,at:&str,bt:&str) {
 use scorebook_core::domain::chart_match;
 let cutoff=chrono::Utc::now().timestamp_millis()/60_000*60_000;
 let sample=fixture_bars(chrono::DateTime::from_timestamp_millis(cutoff-1_200_000).unwrap(),chrono::DateTime::from_timestamp_millis(cutoff).unwrap());
 let vector=format!("{:?}",chart_match::descriptor(&chart_match::from_bars(&sample).unwrap()).unwrap());let candidate=Uuid::new_v4();
 for (id,symbol,end) in [(candidate,"ETHUSDT",cutoff-86_400_000),(Uuid::new_v4(),"BTCUSDT",cutoff),(Uuid::new_v4(),"SOLUSDT",cutoff+60_000)] {
  sqlx::query("INSERT INTO market_features(id,market,symbol,timeframe,start_at,end_at,bars_count,model_id,render_version,embedding,input_hash,source,published) VALUES($1,'usd_m',$2,'1m',$3,$4,20,'candle-geometry-v2','ohlc-geometry-resample64-v2',$5::vector,'fixture','binance',true)").bind(id).bind(symbol).bind(end-1_200_000).bind(end).bind(&vector).execute(admin).await.unwrap();
 }
 let id=Uuid::new_v4();let query=json!({"_testKey":id,"range":{"venue":"binance","market":"usd_m","symbol":"BTCUSDT","interval":"1m","start":cutoff-1_200_000,"end":cutoff,"bars":20},"cutoff":cutoff,"scope":"history"});
 let (status,value)=request(app,"/v1/native-review/searches","POST",Some(at),query.clone()).await;assert_eq!(status,200,"{value}");assert_eq!(value,request(app,"/v1/native-review/searches","POST",Some(at),query).await.1);
 let path=format!("/v1/native-review/searches/{id}");assert_eq!(request(app,&path,"GET",Some(bt),json!({})).await.0,404);
 assert!(kanpan_api::search::run_one(s,&FixtureMarket).await.unwrap());
 let (_,job)=request(app,&path,"GET",Some(at),json!({})).await;assert_eq!(job["data"]["status"],"completed","{job}");assert_eq!(job["data"]["checked"],1);
 let (_,result)=request(app,&format!("{path}/results"),"GET",Some(at),json!({})).await;
 let items=result["data"]["items"].as_array().unwrap();assert_eq!(items.len(),1);assert_eq!(items[0]["id"],candidate.to_string());assert!(items[0]["score"].as_f64().unwrap()>=0.999);
 let input=json!({"_testKey":Uuid::new_v4(),"searchId":id,"matchId":candidate});
 assert_eq!(request(app,"/v1/native-review/saved-matches","POST",Some(bt),input.clone()).await.0,404);
 assert_eq!(request(app,"/v1/native-review/saved-matches","POST",Some(at),input).await.0,200);
 let (_,own)=request(app,"/v1/native-review/saved-matches","GET",Some(at),json!({})).await;assert_eq!(own["data"]["items"].as_array().unwrap().len(),1);
 let (_,other)=request(app,"/v1/native-review/saved-matches","GET",Some(bt),json!({})).await;assert!(other["data"]["items"].as_array().unwrap().is_empty());
 let cancel=Uuid::new_v4();let cancel_path=format!("/v1/native-review/searches/{cancel}");
 assert_eq!(request(app,&cancel_path,"DELETE",Some(at),json!({"_testKey":Uuid::new_v4()})).await.0,200);
 let payload=json!({"_testKey":cancel,"range":{"venue":"binance","market":"usd_m","symbol":"BTCUSDT","interval":"1m","start":cutoff-1_200_000,"end":cutoff,"bars":20},"cutoff":cutoff,"scope":"history"});
 let (_,cancelled)=request(app,"/v1/native-review/searches","POST",Some(at),payload).await;assert_eq!(cancelled["data"]["status"],"cancelled","Cancel arriving before create must still fence it");
 // A short record can be verified for scoring without pretending the search model accepts it.
 //
 // 复盘表是 FORCE ROW LEVEL SECURITY，连表的属主都要按策略来。下面这几条是拿 admin 连接
 // 直接摆夹具，以前能读到只是因为那个角色恰好有 BYPASSRLS（ops/test.py 现在把这条前提
 // 写成了显式断言）；只要哪天它降成普通属主，`SELECT id FROM review_records` 就会一行
 // 都看不见、在 fetch_one 上 RowNotFound。所以这里改成走同一条连接、先把 RLS 上下文
 // 摆上，再按 user_id 明确圈住范围——和服务端自己那条路一模一样，谁来跑都成立。
 let mut conn=admin.acquire().await.unwrap();
 sqlx::query("SELECT set_config('kanpan.user_id',$1,false)").bind(owner.to_string()).execute(&mut *conn).await.unwrap();
 let rid:Uuid=sqlx::query_scalar("SELECT id FROM review_records WHERE user_id=$1 AND record->>'voided'='false' LIMIT 1").bind(owner).fetch_one(&mut *conn).await.unwrap();
 sqlx::query("UPDATE review_jobs SET finished=true WHERE user_id=$1").bind(owner).execute(&mut *conn).await.unwrap();
 sqlx::query("UPDATE review_jobs SET finished=false,next_at=now() WHERE user_id=$1 AND record_id=$2 AND kind='index'").bind(owner).bind(rid).execute(&mut *conn).await.unwrap();
 sqlx::query("UPDATE review_dispatch SET next_at=now() WHERE user_id=$1").bind(owner).execute(&mut *conn).await.unwrap();
 assert!(kanpan_api::review_worker::run_one(s,&FixtureMarket).await.unwrap());
 let row:Value=sqlx::query_scalar("SELECT record FROM review_records WHERE user_id=$1 AND id=$2").bind(owner).bind(rid).fetch_one(&mut *conn).await.unwrap();assert_eq!(row["eligible"],true,"3 bars may qualify although geometry needs 16");
}
