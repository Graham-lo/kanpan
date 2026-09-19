//! 账号安全那几条的回归：转发地址的额度归属、刷新重试的判定、冷启动后的会话吊销、
//! 刷新的节流，以及「密码不对」和「登录已失效」要分得开。
//!
//! 和 `accounts.rs` 共用同一个隔离库（`ops/test.py` 建的那个），用例之间靠随机用户名
//! 互不干扰；`--test-threads=1` 保证它们一条一条跑。
use kanpan_api::{AppState,crypto::Secrets};
use axum::{Router,body::Body,http::{Request,StatusCode},extract::ConnectInfo};
use http_body_util::BodyExt;
use serde_json::{Value,json};
use std::{sync::Arc,net::SocketAddr};
use tower::ServiceExt;
use uuid::Uuid;

/// 一次请求。`peer` 是 TCP 对端（线上就是本机 Caddy），`headers` 放转发头。
async fn request(app:&Router,path:&str,method:&str,peer:&str,headers:&[(&str,&str)],token:Option<&str>,body:Value)->(StatusCode,Value) {
 let mut req=Request::builder().uri(path).method(method).header("content-type","application/json");
 for (name,value) in headers {req=req.header(*name,*value);}
 if let Some(token)=token {req=req.header("authorization",format!("Bearer {token}"));}
 let mut req=req.body(Body::from(body.to_string())).unwrap();
 req.extensions_mut().insert(ConnectInfo(peer.parse::<SocketAddr>().unwrap()));
 let result=app.clone().oneshot(req).await.unwrap();let status=result.status();
 let bytes=result.into_body().collect().await.unwrap().to_bytes();
 (status,serde_json::from_slice(&bytes).unwrap_or_else(|_|json!({"nonJSON":true})))
}
fn device(name:&str)->Value {json!({"id":Uuid::new_v4(),"name":name,"secret":kanpan_api::crypto::random_token()})}
fn name(prefix:&str)->String {format!("{prefix}_{}",&Uuid::new_v4().simple().to_string()[..8])}

/// 隔离库 + 非特权角色，和 `accounts.rs` 里那套一致。
async fn boot()->(AppState,Router,sqlx::PgPool) {
 let admin_url=std::env::var("KANPAN_TEST_ADMIN_URL").expect("Run ops/test.py; an isolated database is required");
 let admin=sqlx::PgPool::connect(&admin_url).await.unwrap();sqlx::migrate!().run(&admin).await.unwrap();
 let role=std::env::var("KANPAN_TEST_ROLE").unwrap();assert!(role.chars().all(|c|c.is_ascii_alphanumeric()||c=='_'));
 for sql in [format!("GRANT USAGE ON SCHEMA public TO {role}"),format!("GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO {role}"),format!("GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO {role}")] {sqlx::query(&sql).execute(&admin).await.unwrap();}
 let pool=sqlx::postgres::PgPoolOptions::new().max_connections(6).connect(&std::env::var("KANPAN_TEST_DATABASE_URL").unwrap()).await.unwrap();
 let secrets=Arc::new(Secrets{pepper:vec![31;32],encryption:[43;32]});let dummy_hash=Arc::new(secrets.hash_password("dummy123456").unwrap());
 let s=AppState{pool,secrets,dummy_hash};let app=kanpan_api::router(s.clone());(s,app,admin)
}
async fn signup(app:&Router,username:&str,d:&Value)->Value {
 let (status,v)=request(app,"/v1/auth/register","POST","127.0.0.1:19000",&[],None,json!({"username":username,"password":"Passcode123","device":d})).await;
 assert_eq!(status,201,"{v}");v["data"].clone()
}
/// 把某个额度键直接顶到上限，省得为了触发限流去跑几十次 Argon2。
async fn saturate(s:&AppState,admin:&sqlx::PgPool,key:&str,failures:i32) {
 sqlx::query("INSERT INTO account_limits(key,failures,window_start) VALUES($1,$2,now()) ON CONFLICT(key) DO UPDATE SET failures=$2,window_start=now()")
  .bind(s.secrets.keyed(key)).bind(failures).execute(admin).await.unwrap();
}

/// A-04：线上 API 前面只有本机 Caddy 一跳，对端永远是 127.0.0.1。额度要按转发头里
/// **Caddy 追加的那一段**（最后一段）算，不能按对端算（全员共用一份），也不能按
/// 第一段算（客户端自己写的，换一个就是一份新额度）。外网直连带来的转发头不作数。
#[tokio::test]
async fn forwarded_client_addresses_own_their_quota() {
 let (s,app,admin)=boot().await;
 saturate(&s,&admin,"login-ip:203.0.113.7",60).await;
 let body=|user:&str|json!({"email":user,"password":"Passcode123","device":device("probe")});
 // 真正跑满额度的那个客户端：Caddy 把它的地址追加在链表尾部。
 let (status,v)=request(&app,"/v1/auth/login","POST","127.0.0.1:19000",&[("x-forwarded-for","198.51.100.1, 203.0.113.7")],None,body("nobody_a")).await;
 assert_eq!(status,StatusCode::TOO_MANY_REQUESTS,"额度要落在转发链尾段那个地址上：{v}");
 assert_eq!(v["error"]["code"],"try_later","限流要能和密码错误区分开：{v}");
 // 另一台客户端：它的地址是尾段，第一段是谁写的都不算数。
 let (status,v)=request(&app,"/v1/auth/login","POST","127.0.0.1:19000",&[("x-forwarded-for","203.0.113.7, 198.51.100.2")],None,body("nobody_b")).await;
 assert_eq!(status,StatusCode::UNAUTHORIZED,"邻居跑满额度不该连累别人：{v}");
 // 直连（对端不是回环）时转发头一律不信，否则谁都能挑一个地址换额度。
 let (status,v)=request(&app,"/v1/auth/login","POST","198.51.100.9:40000",&[("x-forwarded-for","203.0.113.7")],None,body("nobody_c")).await;
 assert_eq!(status,StatusCode::UNAUTHORIZED,"非回环对端的转发头不可信：{v}");
 saturate(&s,&admin,"login-ip:198.51.100.9",60).await;
 let (status,v)=request(&app,"/v1/auth/login","POST","198.51.100.9:40000",&[("x-forwarded-for","203.0.113.99")],None,body("nobody_c")).await;
 assert_eq!(status,StatusCode::TOO_MANY_REQUESTS,"直连时按对端算额度：{v}");
 s.pool.close().await;admin.close().await;
}

/// A-03：同一次刷新的重试，隔多久回来都只是重试。手机断网、切后台、进电梯，
/// 60 秒远不够一次真实的中断；超时就把整条会话吊销等于替攻击者把人踢下线。
/// 只有「换了 request_id 还拿着用过的 refresh」才是重用。
#[tokio::test]
async fn a_delayed_refresh_retry_is_not_token_reuse() {
 let (s,app,admin)=boot().await;
 let d=device("A phone");let a=signup(&app,&name("retry"),&d).await;
 let sid=Uuid::parse_str(a["sessionId"].as_str().unwrap()).unwrap();
 let rid=Uuid::new_v4();let refresh=json!({"refreshToken":a["refreshToken"],"requestId":rid,"device":d});
 let (status,first)=request(&app,"/v1/auth/refresh","POST","127.0.0.1:19000",&[],None,refresh.clone()).await;assert_eq!(status,200,"{first}");
 // 把这次刷新推到十分钟以前：客户端在电梯里待了十分钟才重发同一个请求。
 sqlx::query("UPDATE account_tokens SET used_at=now()-interval '10 minutes' WHERE request_id=$1").bind(rid).execute(&admin).await.unwrap();
 let (status,again)=request(&app,"/v1/auth/refresh","POST","127.0.0.1:19000",&[],None,refresh.clone()).await;
 assert_eq!(status,200,"同一个 request_id 的重试仍是重试：{again}");
 assert_eq!(first,again,"重试要拿回同一份令牌");
 let revoked:Option<chrono::DateTime<chrono::Utc>>=sqlx::query_scalar("SELECT revoked_at FROM account_sessions WHERE id=$1").bind(sid).fetch_one(&admin).await.unwrap();
 assert!(revoked.is_none(),"重试不该吊销会话");
 // 超出保留窗（维护任务清掉密封结果）之后只能重新登录，但会话仍旧不该被吊销。
 sqlx::query("UPDATE account_tokens SET response_sealed=NULL WHERE request_id=$1").bind(rid).execute(&admin).await.unwrap();
 let (status,_)=request(&app,"/v1/auth/refresh","POST","127.0.0.1:19000",&[],None,refresh).await;assert_eq!(status,401);
 let revoked:Option<chrono::DateTime<chrono::Utc>>=sqlx::query_scalar("SELECT revoked_at FROM account_sessions WHERE id=$1").bind(sid).fetch_one(&admin).await.unwrap();
 assert!(revoked.is_none(),"结果过期只是拿不回来，不是重用");
 assert_eq!(request(&app,"/v1/auth/me","GET","127.0.0.1:19000",&[],first["data"]["accessToken"].as_str(),json!({})).await.0,200,"上一次换到的令牌还活着");
 // 换了 request_id 还拿着用过的 refresh——这才是重用，整条会话吊销。
 let reuse=json!({"refreshToken":a["refreshToken"],"requestId":Uuid::new_v4(),"device":d});
 assert_eq!(request(&app,"/v1/auth/refresh","POST","127.0.0.1:19000",&[],None,reuse).await.0,401);
 let revoked:Option<chrono::DateTime<chrono::Utc>>=sqlx::query_scalar("SELECT revoked_at FROM account_sessions WHERE id=$1").bind(sid).fetch_one(&admin).await.unwrap();
 assert!(revoked.is_some(),"真正的重用要吊销会话");
 s.pool.close().await;admin.close().await;
}

/// A-02：access 从不落盘，冷启动之后手上只有 refresh。退登要让服务端那条会话真的结束，
/// 就得有一条拿 refresh + 设备绑定认证的吊销路——而且它不轮换令牌：
/// 退登不该先换一对新的再扔掉。
#[tokio::test]
async fn a_cold_started_client_can_revoke_its_session() {
 let (s,app,admin)=boot().await;
 let d=device("A phone");let a=signup(&app,&name("revoke"),&d).await;
 let sid=Uuid::parse_str(a["sessionId"].as_str().unwrap()).unwrap();
 let mut wrong=d.clone();wrong["secret"]=json!(kanpan_api::crypto::random_token());
 let (status,v)=request(&app,"/v1/auth/session/revoke","POST","127.0.0.1:19000",&[],None,json!({"refreshToken":a["refreshToken"],"device":wrong})).await;
 assert_eq!(status,401,"设备绑定对不上不能吊销别人的会话：{v}");
 assert_eq!(request(&app,"/v1/auth/me","GET","127.0.0.1:19000",&[],a["accessToken"].as_str(),json!({})).await.0,200);
 let payload=json!({"refreshToken":a["refreshToken"],"device":d});
 let (status,v)=request(&app,"/v1/auth/session/revoke","POST","127.0.0.1:19000",&[],None,payload.clone()).await;assert_eq!(status,200,"{v}");
 let revoked:Option<chrono::DateTime<chrono::Utc>>=sqlx::query_scalar("SELECT revoked_at FROM account_sessions WHERE id=$1").bind(sid).fetch_one(&admin).await.unwrap();
 assert!(revoked.is_some(),"退登之后服务端那条会话要真的结束");
 assert_eq!(request(&app,"/v1/auth/me","GET","127.0.0.1:19000",&[],a["accessToken"].as_str(),json!({})).await.0,401);
 assert_eq!(request(&app,"/v1/auth/refresh","POST","127.0.0.1:19000",&[],None,json!({"refreshToken":a["refreshToken"],"requestId":Uuid::new_v4(),"device":d})).await.0,401);
 // 网络不稳时客户端会重发；重发一次仍旧是 200，别让退登卡在错误里。
 assert_eq!(request(&app,"/v1/auth/session/revoke","POST","127.0.0.1:19000",&[],None,payload).await.0,200);
 s.pool.close().await;admin.close().await;
}

/// A.5：刷新这条路没有密码那一关，只有令牌，此前也没有任何节流。
/// 一条会话 60 秒里刷新超过 30 次就退 429——正常客户端 15 分钟才换一次，碰不到。
#[tokio::test]
async fn refresh_is_paced_per_session() {
 let (s,app,admin)=boot().await;
 let d=device("A phone");let a=signup(&app,&name("pace"),&d).await;
 let sid=a["sessionId"].as_str().unwrap().to_owned();
 saturate(&s,&admin,&format!("refresh-sid:{sid}"),30).await;
 let (status,v)=request(&app,"/v1/auth/refresh","POST","127.0.0.1:19000",&[],None,json!({"refreshToken":a["refreshToken"],"requestId":Uuid::new_v4(),"device":d})).await;
 assert_eq!(status,StatusCode::TOO_MANY_REQUESTS,"刷新要有节流：{v}");
 assert_eq!(v["error"]["code"],"try_later","{v}");
 s.pool.close().await;admin.close().await;
}

/// A-05：「密码不对」和「登录已失效」必须分得开。客户端把两者都写成「密码不对」，
/// 是因为服务端两边都回同一个 authentication_failed。
#[tokio::test]
async fn a_wrong_password_is_told_apart_from_a_dead_session() {
 let (s,app,admin)=boot().await;
 let d=device("A phone");let a=signup(&app,&name("code"),&d).await;
 let at=a["accessToken"].as_str().unwrap();
 let (status,v)=request(&app,"/v1/auth/password/change","POST","127.0.0.1:19000",&[],Some(at),json!({"currentPassword":"Wrongpass123","newPassword":"Passcode456"})).await;
 assert_eq!(status,401);assert_eq!(v["error"]["code"],"wrong_password","密码不对要有自己的码：{v}");
 let (status,v)=request(&app,"/v1/auth/password/change","POST","127.0.0.1:19000",&[],Some("not-a-token"),json!({"currentPassword":"Passcode123","newPassword":"Passcode456"})).await;
 assert_eq!(status,401);assert_eq!(v["error"]["code"],"authentication_failed","会话失效仍是 authentication_failed：{v}");
 let (status,v)=request(&app,"/v1/auth/account","DELETE","127.0.0.1:19000",&[],Some(at),json!({"password":"Wrongpass123"})).await;
 assert_eq!(status,401);assert_eq!(v["error"]["code"],"wrong_password","{v}");
 s.pool.close().await;admin.close().await;
}
