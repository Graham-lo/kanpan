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

/// 改密码、删账号上验旧密码和登录共用同一本失败账：以前只有登录记账，拿着一张令牌的人
/// 可以在改密码上无限次试旧密码。现在猜错五次锁一分钟，锁着时猜对也改不了、删不了、
/// 登录不了；回的码照旧是 wrong_password（登录那边照旧 401），协议不变。
#[tokio::test]
async fn guessing_the_old_password_counts_against_the_same_lock_as_login() {
 let (s,app,admin)=boot().await;
 let peer="192.0.2.72:19000";let username=name("guess");let d=device("A phone");
 let a=signup(&app,&username,&d).await;let at=a["accessToken"].as_str().unwrap().to_string();
 for _ in 0..5 {
  let (status,v)=request(&app,"/v1/auth/password/change","POST",peer,&[],Some(&at),json!({"currentPassword":"Wrongpass123","newPassword":"Passcode456"})).await;
  assert_eq!((status.as_u16(),v["error"]["code"].as_str()),(401,Some("wrong_password")),"{v}");
 }
 let (status,v)=request(&app,"/v1/auth/password/change","POST",peer,&[],Some(&at),json!({"currentPassword":"Passcode123","newPassword":"Passcode456"})).await;
 assert_eq!((status.as_u16(),v["error"]["code"].as_str()),(401,Some("wrong_password")),"锁着的时候猜对也改不了：{v}");
 let (status,_)=request(&app,"/v1/auth/account","DELETE",peer,&[],Some(&at),json!({"password":"Passcode123"})).await;
 assert_eq!(status,401,"锁着的时候也删不了");
 let (status,_)=request(&app,"/v1/auth/login","POST",peer,&[],None,json!({"username":username,"password":"Passcode123","device":d})).await;
 assert_eq!(status,401,"同一本账：改密码上猜错，登录也锁着");
 sqlx::query("DELETE FROM account_limits WHERE key=$1").bind(s.secrets.keyed(&format!("login:{username}"))).execute(&admin).await.unwrap();
 let (status,v)=request(&app,"/v1/auth/password/change","POST",peer,&[],Some(&at),json!({"currentPassword":"Passcode123","newPassword":"Passcode456"})).await;
 assert_eq!(status,200,"锁过了就照常：{v}");
 let left:i64=sqlx::query_scalar("SELECT count(*) FROM account_limits WHERE key=$1").bind(s.secrets.keyed(&format!("login:{username}"))).fetch_one(&admin).await.unwrap();
 assert_eq!(left,0,"改成功后失败账清零");
 s.pool.close().await;admin.close().await;
}

// ---- 每一类设备同时只准一台在线（2026-09-19）----
//
// 手机一类、平板一类、电脑一类：一部 iPhone + 一台 iPad + 一台 Mac 同时在线是允许的，
// 两部手机不行，后登录的把先登录的顶下去。这是服务端的规矩，不是客户端的提示，
// 所以被顶掉的那条会话要从服务端拿到一个自己的错误码。

fn device_of(name:&str,kind:&str)->Value {let mut d=device(name);d["kind"]=json!(kind);d}
async fn login(app:&Router,username:&str,d:&Value)->Value {
 let (status,v)=request(app,"/v1/auth/login","POST","127.0.0.1:19000",&[],None,json!({"username":username,"password":"Passcode123","device":d})).await;
 assert_eq!(status,200,"{v}");v["data"].clone()
}
async fn refresh(app:&Router,token:&Value,d:&Value)->(StatusCode,Value) {
 request(app,"/v1/auth/refresh","POST","127.0.0.1:19000",&[],None,json!({"refreshToken":token,"requestId":Uuid::new_v4(),"device":d})).await
}

/// 第二部手机登录，第一部被顶下去——而且它要知道自己是被顶掉的。
/// 笼统的 authentication_failed 只能写成「登录已失效」，界面上就说不出
/// 「这个账号在另一台手机上登录了」。
#[tokio::test]
async fn a_second_phone_replaces_the_first_one() {
 let (s,app,admin)=boot().await;
 let user=name("phones");
 let first=device_of("旧 iPhone","phone");
 let a=signup(&app,&user,&first).await;
 let second=device_of("新 iPhone","phone");
 let b=login(&app,&user,&second).await;
 let (status,v)=refresh(&app,&a["refreshToken"],&first).await;
 assert_eq!(status,401,"{v}");
 assert_eq!(v["error"]["code"],"session_replaced","被顶掉要有自己的错误码：{v}");
 assert_eq!(v["error"]["deviceKind"],"phone","还要说清是哪一类设备把它顶掉的：{v}");
 let (status,v)=request(&app,"/v1/auth/me","GET","127.0.0.1:19000",&[],a["accessToken"].as_str(),json!({})).await;
 assert_eq!(status,401);assert_eq!(v["error"]["code"],"session_replaced","access 这条路也一样：{v}");
 // 后登录的那条照常活着。
 assert_eq!(request(&app,"/v1/auth/me","GET","127.0.0.1:19000",&[],b["accessToken"].as_str(),json!({})).await.0,200);
 let (status,v)=refresh(&app,&b["refreshToken"],&second).await;assert_eq!(status,200,"{v}");
 let sid=Uuid::parse_str(a["sessionId"].as_str().unwrap()).unwrap();
 let reason:Option<String>=sqlx::query_scalar("SELECT revoked_reason FROM account_sessions WHERE id=$1").bind(sid).fetch_one(&admin).await.unwrap();
 assert_eq!(reason.as_deref(),Some("replaced"),"撤销原因要落在库里");
 s.pool.close().await;admin.close().await;
}

/// 手机 + 平板 + 电脑各一台同时在线，互不影响。
#[tokio::test]
async fn one_device_of_each_kind_may_be_online_together() {
 let (s,app,admin)=boot().await;
 let user=name("kinds");
 let phone=device_of("iPhone","phone");let tablet=device_of("iPad","tablet");let desktop=device_of("Mac","desktop");
 let a=signup(&app,&user,&phone).await;
 let b=login(&app,&user,&tablet).await;
 let c=login(&app,&user,&desktop).await;
 for (session,d) in [(&a,&phone),(&b,&tablet),(&c,&desktop)] {
  assert_eq!(request(&app,"/v1/auth/me","GET","127.0.0.1:19000",&[],session["accessToken"].as_str(),json!({})).await.0,200,"三类设备互不相干");
  let (status,v)=refresh(&app,&session["refreshToken"],d).await;assert_eq!(status,200,"{v}");
 }
 let owner=Uuid::parse_str(a["user"]["id"].as_str().unwrap()).unwrap();
 let live:i64=sqlx::query_scalar("SELECT count(*) FROM account_sessions WHERE user_id=$1 AND revoked_at IS NULL").bind(owner).fetch_one(&admin).await.unwrap();
 assert_eq!(live,3,"三条会话都要活着");
 let (_,list)=request(&app,"/v1/auth/devices","GET","127.0.0.1:19000",&[],a["accessToken"].as_str(),json!({})).await;
 let mut kinds:Vec<String>=list["data"]["devices"].as_array().unwrap().iter().map(|d|d["kind"].as_str().unwrap_or("missing").to_owned()).collect();
 kinds.sort();
 assert_eq!(kinds,vec!["desktop","phone","tablet"],"设备列表要报出类别：{list}");
 s.pool.close().await;admin.close().await;
}

/// 线上现在装着的那个 iPhone 包不发 kind，它必须照常登录、照常刷新，并且算作手机——
/// 再来一台手机就该把它顶掉。
#[tokio::test]
async fn a_device_without_a_kind_counts_as_a_phone() {
 let (s,app,admin)=boot().await;
 let user=name("legacy");
 let old=device("旧版 iPhone");
 let a=signup(&app,&user,&old).await;
 let (status,rotated)=refresh(&app,&a["refreshToken"],&old).await;assert_eq!(status,200,"旧客户端要能刷新：{rotated}");
 let rotated=rotated["data"].clone();
 let sid=Uuid::parse_str(a["sessionId"].as_str().unwrap()).unwrap();
 let stored:String=sqlx::query_scalar("SELECT device_kind FROM account_sessions WHERE id=$1").bind(sid).fetch_one(&admin).await.unwrap();
 assert_eq!(stored,"phone","不带 kind 就是手机");
 let _new=login(&app,&user,&device_of("新 iPhone","phone")).await;
 let (status,v)=refresh(&app,&rotated["refreshToken"],&old).await;
 assert_eq!(status,401,"{v}");assert_eq!(v["error"]["code"],"session_replaced","旧包也会被新手机顶掉：{v}");
 s.pool.close().await;admin.close().await;
}

/// 刷新时改口说自己是别的类别，就是在绕开「每类一台」的限制。
#[tokio::test]
async fn a_refresh_may_not_rename_its_device_kind() {
 let (s,app,admin)=boot().await;
 let phone=device_of("iPhone","phone");
 let a=signup(&app,&name("liar"),&phone).await;
 let mut lying=phone.clone();lying["kind"]=json!("tablet");
 let (status,v)=refresh(&app,&a["refreshToken"],&lying).await;
 assert_eq!(status,400,"{v}");assert_eq!(v["error"]["code"],"invalid_device","会话记的是手机，就不许改口叫平板：{v}");
 let (status,v)=refresh(&app,&a["refreshToken"],&phone).await;assert_eq!(status,200,"说实话照常刷新：{v}");
 let mut junk=phone.clone();junk["kind"]=json!("watch");
 let (status,v)=refresh(&app,&a["refreshToken"],&junk).await;
 assert!(status.is_client_error(),"没有这一类设备：{v}");
 s.pool.close().await;admin.close().await;
}

/// 0010 给 `device_kind` 加列时用的是 `DEFAULT 'phone'`，于是升级那一刻还在线的 iPad 和
/// 电脑全被记成了手机。这本来只是「我的设备」里显示不准，但顶人是按这个字段来的
/// （上面那几条用例验的就是「每类只许一台」），所以这个人下一次用手机登录，会把自己
/// 那台被误记成手机的 iPad 踢下线。0013 按会话自己报的设备名把它们认回来。
///
/// 这条用例跑的是**迁移文件本身**的那两句 SQL，不是照抄一遍——照抄只能证明抄对了。
#[tokio::test]
async fn the_upgrade_must_not_call_every_old_session_a_phone() {
 let (s,app,admin)=boot().await;
 let tag=Uuid::new_v4().simple().to_string();
 let cases=[("Graham 的 iPad","tablet"),("MacBook Pro","desktop"),("Windows PC","desktop"),("iPhone 15 Pro","phone")];
 for (device_name,_) in cases {signup(&app,&name("kind"),&device(&format!("{device_name} {tag}"))).await;}
 // 先把它们全摆回升级那一刻的样子：0010 的默认值让每一条都是 'phone'。
 sqlx::query("UPDATE account_sessions SET device_kind='phone' WHERE device_name LIKE '%'||$1").bind(&tag).execute(&admin).await.unwrap();
 let sql=std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"),"/migrations/0013_device_kind_backfill.sql")).unwrap();
 sqlx::raw_sql(&sql).execute(&admin).await.unwrap();
 for (device_name,expected) in cases {
  let kind:String=sqlx::query_scalar("SELECT device_kind FROM account_sessions WHERE device_name=$1").bind(format!("{device_name} {tag}")).fetch_one(&admin).await.unwrap();
  assert_eq!(kind,expected,"「{device_name}」回填成了 {kind}");
 }
 // 客户端自己报过的类别不许被名字猜测盖掉：只动仍然记着 'phone' 的行，所以重复执行
 // 这条迁移不会有第二次效果。
 sqlx::query("UPDATE account_sessions SET device_kind='desktop' WHERE device_name=$1").bind(format!("Graham 的 iPad {tag}")).execute(&admin).await.unwrap();
 sqlx::raw_sql(&sql).execute(&admin).await.unwrap();
 let kind:String=sqlx::query_scalar("SELECT device_kind FROM account_sessions WHERE device_name=$1").bind(format!("Graham 的 iPad {tag}")).fetch_one(&admin).await.unwrap();
 assert_eq!(kind,"desktop","已经有明确类别的会话不该被设备名改写");
 s.pool.close().await;admin.close().await;
}

/// 审查 A6：登录、改密码、删账号的 Argon2 挪到了事务外面（先不加锁读哈希去验，
/// 再上锁重读、哈希没变才算数）。挪完之后几条规矩要照旧：猜错五次锁一分钟、锁着时
/// 猜对也进不去；改完密码旧的进不去、新的能进；删账号要现在的密码。
#[tokio::test]
async fn password_checks_keep_their_rules_outside_the_lock() {
 let (s,app,admin)=boot().await;
 let peer="192.0.2.71:19000";let username=name("argon");let d=device("A phone");
 let a=signup(&app,&username,&d).await;let at=a["accessToken"].as_str().unwrap().to_string();
 let try_login=|password:&'static str|{let app=app.clone();let username=username.clone();let d=d.clone();async move {
  request(&app,"/v1/auth/login","POST",peer,&[],None,json!({"username":username,"password":password,"device":d})).await
 }};
 for _ in 0..5 {assert_eq!(try_login("Wrongpass123").await.0,401);}
 assert_eq!(try_login("Passcode123").await.0,401,"锁着的时候猜对也进不去");
 sqlx::query("DELETE FROM account_limits WHERE key=$1").bind(s.secrets.keyed(&format!("login:{username}"))).execute(&admin).await.unwrap();
 let (status,v)=try_login("Passcode123").await;assert_eq!(status,200,"{v}");
 let fresh=v["data"]["accessToken"].as_str().unwrap().to_string();
 assert_ne!(fresh,at);
 let (status,v)=request(&app,"/v1/auth/password/change","POST",peer,&[],Some(&fresh),json!({"currentPassword":"Passcode123","newPassword":"Passcode456"})).await;
 assert_eq!(status,200,"{v}");
 assert_eq!(try_login("Passcode123").await.0,401,"旧密码进不去");
 let (status,v)=try_login("Passcode456").await;assert_eq!(status,200,"新密码能进：{v}");
 let token=v["data"]["accessToken"].as_str().unwrap().to_string();
 let (status,v)=request(&app,"/v1/auth/account","DELETE",peer,&[],Some(&token),json!({"password":"Passcode123"})).await;
 assert_eq!((status.as_u16(),v["error"]["code"].as_str()),(401,Some("wrong_password")),"删账号要的是现在的密码");
 let (status,v)=request(&app,"/v1/auth/account","DELETE",peer,&[],Some(&token),json!({"password":"Passcode456"})).await;assert_eq!(status,200,"{v}");
 assert_eq!(try_login("Passcode456").await.0,401,"删掉的账号进不去");
 let gone:i64=sqlx::query_scalar("SELECT count(*) FROM account_users WHERE email=$1").bind(&username).fetch_one(&admin).await.unwrap();assert_eq!(gone,0);
 s.pool.close().await;admin.close().await;
}
