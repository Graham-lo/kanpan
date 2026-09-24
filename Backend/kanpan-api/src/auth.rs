use crate::{AppState,crypto::digest,envelope,error::{ApiError,Result}};
use axum::{Router,Json,extract::{State,Path,ConnectInfo,FromRequestParts},routing::{get,post,delete},http::{HeaderMap,request::Parts,StatusCode},response::{IntoResponse,Response}};
use chrono::{DateTime,Duration,Utc};
use serde::{Deserialize,Serialize};
use serde_json::{Value,json};
use sqlx::{Row,Postgres,Transaction};
use std::net::{IpAddr,SocketAddr};
use uuid::Uuid;
use subtle::ConstantTimeEq;

/// 认证这条路上多出来的一个结果：会话被同一类设备顶下去了。
///
/// 「登录已失效」和「这个账号在另一台手机上登录了」在界面上是两句话，服务端两边
/// 都回 `authentication_failed` 时客户端只能写成同一句。被顶掉这件事要带着设备类别
/// 一起说出来（`{"error":{"code":"session_replaced","deviceKind":"phone"}}`），
/// 其余的撤销（退登、踢设备、改密、注销）仍旧是笼统的那一句。
pub enum AuthError {Api(ApiError),Replaced(DeviceKind)}
pub type AuthResult<T>=std::result::Result<T,AuthError>;
impl From<ApiError> for AuthError {fn from(v:ApiError)->Self {Self::Api(v)}}
impl From<sqlx::Error> for AuthError {fn from(v:sqlx::Error)->Self {Self::Api(v.into())}}
impl From<serde_json::Error> for AuthError {fn from(v:serde_json::Error)->Self {Self::Api(v.into())}}
impl IntoResponse for AuthError {
 fn into_response(self)->Response {
  match self {
   Self::Api(e)=>e.into_response(),
   Self::Replaced(kind)=>(StatusCode::UNAUTHORIZED,Json(json!({"error":{"code":"session_replaced","deviceKind":kind.as_str()}}))).into_response(),
  }
 }
}
fn kind_of(row:&sqlx::postgres::PgRow)->DeviceKind {DeviceKind::parse(&row.get::<String,_>("device_kind"))}
/// 会话已经不在了，要说清是怎么没的。只有「被顶下去」有自己的码。
fn dead_session(row:&sqlx::postgres::PgRow)->AuthError {
 if row.get::<Option<String>,_>("revoked_reason").as_deref()==Some("replaced") {AuthError::Replaced(kind_of(row))} else {AuthError::Api(ApiError::unauthorized())}
}

#[derive(Clone,Copy)]
pub struct Identity {pub user:Uuid,pub session:Uuid}
impl FromRequestParts<AppState> for Identity {
 type Rejection=AuthError;
 async fn from_request_parts(parts:&mut Parts,s:&AppState)->AuthResult<Self> {
  let token=parts.headers.get("authorization").and_then(|h|h.to_str().ok()).and_then(|v|v.strip_prefix("Bearer ")).filter(|t|t.len()<=128).ok_or_else(ApiError::unauthorized)?;
  // 会话死没死改在 Rust 这边判：令牌本身对得上、还能定位到会话时，被顶下去的那条
  // 要回 `session_replaced`，所以不能像以前那样在 SQL 里把撤销过的会话直接滤掉。
  // 令牌对不上仍旧什么都问不出来。
  let row=sqlx::query("SELECT s.user_id,s.id,s.device_kind,s.revoked_at,s.revoked_reason,s.expires_at,u.disabled_at FROM account_tokens t JOIN account_sessions s ON s.id=t.session_id JOIN account_users u ON u.id=s.user_id WHERE t.token_hash=$1 AND t.kind='access' AND t.expires_at>now()")
   .bind(digest(token)).fetch_optional(&s.pool).await?.ok_or_else(ApiError::unauthorized)?;
  if row.get::<Option<DateTime<Utc>>,_>("revoked_at").is_some() {return Err(dead_session(&row))}
  if row.get::<DateTime<Utc>,_>("expires_at")<=Utc::now() || row.get::<Option<DateTime<Utc>>,_>("disabled_at").is_some() {return Err(ApiError::unauthorized().into())}
  Ok(Self{user:row.get("user_id"),session:row.get("id")})
 }
}
/// 设备类别。一个账号每一类同时只准一台在线：手机一类、平板一类、电脑一类。
///
/// 线上现在装着的那些包还不发这个字段，缺省就当手机——它们本来也全是 iPhone，
/// 而且这样一来新旧两个包指的是同一条「手机」名额，不会各占一条。
#[derive(Deserialize,Serialize,Clone,Copy,PartialEq,Eq,Debug,Default)]
#[serde(rename_all="lowercase")]
pub enum DeviceKind {#[default] Phone,Tablet,Desktop}
impl DeviceKind {
 pub fn as_str(self)->&'static str {match self {Self::Phone=>"phone",Self::Tablet=>"tablet",Self::Desktop=>"desktop"}}
 fn parse(v:&str)->Self {match v {"tablet"=>Self::Tablet,"desktop"=>Self::Desktop,_=>Self::Phone}}
}
#[derive(Deserialize,Serialize,Clone)]
#[serde(rename_all="camelCase",deny_unknown_fields)]
pub struct Device {pub id:Uuid,pub name:String,pub secret:String,#[serde(default)] pub kind:DeviceKind}
impl Device {
 fn validate(&self)->Result<()> {
  if self.name.trim().is_empty() || self.name.len()>120 || !(32..=128).contains(&self.secret.len()) {return Err(ApiError::bad("invalid_device"))} Ok(())
 }
}
#[derive(Deserialize)]
#[serde(rename_all="camelCase",deny_unknown_fields)]
struct PasswordInput {#[serde(rename="username",alias="email")] email:String,password:String,device:Device}
#[derive(Deserialize)]
#[serde(rename_all="camelCase",deny_unknown_fields)]
struct RefreshInput {refresh_token:String,request_id:Uuid,device:Device}
#[derive(Deserialize)]
#[serde(rename_all="camelCase",deny_unknown_fields)]
struct ChangeInput {current_password:String,new_password:String}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct DeleteInput {password:String}
#[derive(Deserialize)]
#[serde(rename_all="camelCase",deny_unknown_fields)]
struct RevokeInput {refresh_token:String,device:Device}

pub fn routes()->Router<AppState> {
 Router::new()
 .route("/v1/auth/register",post(register))
 .route("/v1/auth/login",post(login))
 .route("/v1/auth/refresh",post(refresh))
 .route("/v1/auth/logout",post(logout))
 .route("/v1/auth/session/revoke",post(revoke_session))
 .route("/v1/auth/me",get(me))
 .route("/v1/auth/password/change",post(change_password))
 .route("/v1/auth/devices",get(devices))
 .route("/v1/auth/devices/{id}",delete(revoke_device))
 .route("/v1/auth/account",delete(delete_account))
}
fn email(raw:&str)->Result<String> {
 let v=raw.trim().to_ascii_lowercase();
 if !(3..=32).contains(&v.len()) || !v.bytes().all(|c|c.is_ascii_alphanumeric() || c==b'_') {return Err(ApiError::bad("invalid_username"))} Ok(v)
}
fn password(v:&str)->Result<()> {
 if v.chars().count()<8 || v.len()>128 || !v.chars().any(|c|c.is_ascii_alphabetic()) || !v.chars().any(|c|c.is_ascii_digit()) {return Err(ApiError::bad("invalid_password"))} Ok(())
}
async fn hash(s:&AppState,v:String)->Result<String> {
 let secret=s.secrets.clone(); tokio::task::spawn_blocking(move||secret.hash_password(&v)).await.map_err(|_|ApiError::bad("password_unavailable"))?
}
async fn verify(s:&AppState,v:String,h:String)->Result<bool> {
 let secret=s.secrets.clone(); tokio::task::spawn_blocking(move||secret.verify_password(&v,&h)).await.map_err(|_|ApiError::unauthorized())
}
async fn lock_email(tx:&mut Transaction<'_,Postgres>,email:&str)->Result<()> {
 sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))").bind(format!("account:{email}")).execute(&mut **tx).await?; Ok(())
}
/// 谁在打这个接口。
///
/// 线上 API 只听 127.0.0.1，前面是同一台机器上的 Caddy，所以对端地址永远是回环，
/// 按它算额度等于所有人共用一份——一个人打满，另外两个人连不上。只有对端是回环时
/// 才认转发头里的地址；外网直连过来的请求带的转发头一律不信，否则随手换一个地址
/// 就是一份新额度。
///
/// 取 `X-Forwarded-For` 的**最后一段**：反向代理是往已有链表的尾部追加它亲眼看到的
/// 对端地址，客户端自己伪造的那几段只会排在前面。尾段解不出地址就当没有这个头，
/// 宁可退回对端也不要去信前面那几段。`X-Real-IP` 只在没有 `X-Forwarded-For` 时兜底。
pub(crate) fn client_ip(peer:&SocketAddr,headers:&HeaderMap)->IpAddr {
 if !peer.ip().is_loopback() {return peer.ip()}
 if let Some(list)=headers.get("x-forwarded-for").and_then(|h|h.to_str().ok())
  && let Some(last)=list.rsplit(',').next()
   && let Some(ip)=parse_ip(last) {return ip}
 if let Some(ip)=headers.get("x-real-ip").and_then(|h|h.to_str().ok()).and_then(parse_ip) {return ip}
 peer.ip()
}
/// `1.2.3.4`、`1.2.3.4:5678`、`[::1]`、`[::1]:5678` 都可能出现在转发头里。
fn parse_ip(raw:&str)->Option<IpAddr> {
 let v=raw.trim();
 if v.is_empty() {return None}
 if let Ok(ip)=v.parse::<IpAddr>() {return Some(ip)}
 if let Ok(address)=v.parse::<SocketAddr>() {return Some(address.ip())}
 v.strip_prefix('[').and_then(|r|r.split(']').next()).and_then(|r|r.parse::<IpAddr>().ok())
}
pub(crate) async fn hit_limit(s:&AppState,key:&str,limit:i32,seconds:i64)->Result<bool> {
 let count:i32=sqlx::query_scalar("INSERT INTO account_limits(key,failures) VALUES($1,1) ON CONFLICT(key) DO UPDATE SET failures=CASE WHEN account_limits.window_start<now()-make_interval(secs=>$2::double precision) THEN 1 ELSE account_limits.failures+1 END,window_start=CASE WHEN account_limits.window_start<now()-make_interval(secs=>$2::double precision) THEN now() ELSE account_limits.window_start END RETURNING failures")
  .bind(s.secrets.keyed(key)).bind(seconds as f64).fetch_one(&s.pool).await?; Ok(count<=limit)
}
async fn register(State(s):State<AppState>,ConnectInfo(peer):ConnectInfo<SocketAddr>,headers:HeaderMap,Json(v):Json<PasswordInput>)->Result<(StatusCode,Json<Value>)> {
 let email=email(&v.email)?;password(&v.password)?;v.device.validate()?;
 if !hit_limit(&s,&format!("code-ip:{}",client_ip(&peer,&headers)),30,60).await? {return Err(ApiError(StatusCode::TOO_MANY_REQUESTS,"try_later"))}
 let h=hash(&s,v.password).await?;
 let mut tx=s.pool.begin().await?;lock_email(&mut tx,&email).await?;
 let id=Uuid::new_v4();
 let inserted=sqlx::query("INSERT INTO account_users(id,email,password_hash) VALUES($1,$2,$3) ON CONFLICT(email) DO NOTHING").bind(id).bind(&email).bind(h).execute(&mut *tx).await?.rows_affected();
 if inserted==0 {return Err(ApiError(StatusCode::CONFLICT,"username_taken"))}
 let response=new_session(&s,&mut tx,id,&v.device).await?;
 tx.commit().await?;Ok((StatusCode::CREATED,envelope(response)))
}
/// 建一条新会话，并把该让位的那几条顶下去。
///
/// 一个账号每一类设备同时只准一台在线：新开的这条是手机，就把这个人名下所有还活着的
/// 手机会话撤掉；平板和电脑各自不受影响。同一台设备（`device_id` 相同）重新登录也一样
/// 让位——哪怕它这次报的类别变了，否则同一台机器会在两个类别里各留一条。
///
/// 登录与注册都在 `lock_email` 的账号级顾问锁里，所以「先撤旧的再插新的」不会
/// 被另一次并发登录穿过去。
async fn new_session(s:&AppState,tx:&mut Transaction<'_,Postgres>,user:Uuid,device:&Device)->Result<Value> {
 let session=Uuid::new_v4();
 sqlx::query("UPDATE account_sessions SET revoked_at=now(),revoked_reason='replaced' WHERE user_id=$1 AND revoked_at IS NULL AND (device_kind=$2 OR device_id=$3)")
  .bind(user).bind(device.kind.as_str()).bind(device.id).execute(&mut **tx).await?;
 sqlx::query("INSERT INTO account_sessions(id,user_id,device_id,device_name,device_kind,binding_hash,expires_at) VALUES($1,$2,$3,$4,$5,$6,now()+interval '30 days')")
  .bind(session).bind(user).bind(device.id).bind(device.name.trim()).bind(device.kind.as_str()).bind(digest(&device.secret)).execute(&mut **tx).await?;
 tokens(s,tx,user,session).await
}
async fn tokens(_s:&AppState,tx:&mut Transaction<'_,Postgres>,user:Uuid,session:Uuid)->Result<Value> {
 let access=crate::crypto::random_token();let refresh=crate::crypto::random_token();let now=Utc::now();
 for (token,kind,expiry) in [(&access,"access",now+Duration::minutes(15)),(&refresh,"refresh",now+Duration::days(30))] {
  sqlx::query("INSERT INTO account_tokens(token_hash,session_id,kind,expires_at) VALUES($1,$2,$3,$4)").bind(digest(token)).bind(session).bind(kind).bind(expiry).execute(&mut **tx).await?;
 }
 let email:String=sqlx::query_scalar("SELECT email FROM account_users WHERE id=$1").bind(user).fetch_one(&mut **tx).await?;
 Ok(json!({"user":{"id":user,"email":email},"sessionId":session,"accessToken":access,"refreshToken":refresh,"expiresAt":(now+Duration::minutes(15)).timestamp_millis(),"serverTime":now.timestamp_millis()}))
}
async fn login(State(s):State<AppState>,ConnectInfo(peer):ConnectInfo<SocketAddr>,headers:HeaderMap,Json(v):Json<PasswordInput>)->Result<Json<Value>> {
 let email=email(&v.email).map_err(|_|ApiError::unauthorized())?;v.device.validate()?;
 if v.password.len()>128 {return Err(ApiError::unauthorized())}
 // 额度打满要说自己是额度打满。此前这里回 401，界面上写成「用户名或密码不对」，
 // 人会以为自己记错了密码，一遍遍重试，把剩下那点额度也烧光。
 if !hit_limit(&s,&format!("login-ip:{}",client_ip(&peer,&headers)),60,60).await? {return Err(ApiError(StatusCode::TOO_MANY_REQUESTS,"try_later"))}
 // Argon2 在事务**外面**算（审查 A6）：它要几十到上百毫秒的 CPU，以前是攥着账号顾问锁、
 // 用户行的 FOR UPDATE 和一条池连接算的——同一个人的另一次登录、改密码、推送都得等它。
 // 先不加锁读出哈希去验，再开事务上锁、重读一遍，哈希没变才算数（`still_current`）。
 let seen=credential(&s.pool,&email,false).await?;
 let h=seen.as_ref().map(|(_,h)|h.clone()).unwrap_or_else(||s.dummy_hash.as_ref().clone());
 let valid=verify(&s,v.password,h).await?;
 let mut tx=s.pool.begin().await?;lock_email(&mut tx,&email).await?;
 let key=s.secrets.keyed(&format!("login:{email}"));
 let locked:bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM account_limits WHERE key=$1 AND locked_until>now())").bind(&key).fetch_one(&mut *tx).await?;
 let now=credential(&mut *tx,&email,true).await?;
 if locked || !valid || seen.is_none() {
  if !locked {sqlx::query("INSERT INTO account_limits(key,failures) VALUES($1,1) ON CONFLICT(key) DO UPDATE SET failures=CASE WHEN account_limits.locked_until<=now() THEN 1 ELSE account_limits.failures+1 END,locked_until=CASE WHEN account_limits.locked_until<=now() THEN NULL WHEN account_limits.failures>=4 THEN now()+interval '60 seconds' ELSE NULL END")
   .bind(key).execute(&mut *tx).await?;}
  tx.commit().await?;return Err(ApiError::unauthorized());
 }
 // 密码对，但验的那一刻到上锁之间密码被改了、账号被删或停用了：验过的是一把旧钥匙。
 // 这不是猜错，不记失败次数。
 let Some(id)=still_current(&seen,&now) else {return Err(ApiError::unauthorized())};
 sqlx::query("DELETE FROM account_limits WHERE key=$1").bind(key).execute(&mut *tx).await?;
 let response=new_session(&s,&mut tx,id,&v.device).await?;tx.commit().await?;Ok(envelope(response))
}
/// 这个用户名现在的（id，密码哈希）；停用的账号当不存在。`for_update` 只在上了账号锁的
/// 那个事务里用：事务外那次读是给 Argon2 取料的，不该锁任何东西。
async fn credential<'e,E:sqlx::PgExecutor<'e>>(e:E,email:&str,for_update:bool)->Result<Option<(Uuid,String)>> {
 let sql=if for_update {"SELECT id,password_hash FROM account_users WHERE email=$1 AND disabled_at IS NULL FOR UPDATE"}
  else {"SELECT id,password_hash FROM account_users WHERE email=$1 AND disabled_at IS NULL"};
 Ok(sqlx::query_as(sql).bind(email).fetch_optional(e).await?)
}
/// 事务外验过的那把哈希，上锁之后是否还是这个账号现在的那一把。是就交回账号 id。
fn still_current(seen:&Option<(Uuid,String)>,now:&Option<(Uuid,String)>)->Option<Uuid> {
 match (seen,now) {(Some(a),Some(b)) if a==b=>Some(a.0),_=>None}
}
async fn refresh(State(s):State<AppState>,Json(v):Json<RefreshInput>)->AuthResult<Json<Value>> {
 v.device.validate()?;if v.refresh_token.len()>128{return Err(ApiError::unauthorized().into())}
 // 刷新没有密码那一关，只有一把令牌，此前也没有任何节流。access 十五分钟才换一次，
 // 正常客户端一条会话一分钟内绝到不了三十次；到了就是有人在拿它磨服务器。
 // 键取会话而不是令牌：轮换之后令牌每次都是新的，只有会话是同一条。
 let paced:Option<Uuid>=sqlx::query_scalar("SELECT session_id FROM account_tokens WHERE token_hash=$1 AND kind='refresh'").bind(digest(&v.refresh_token)).fetch_optional(&s.pool).await?;
 if let Some(sid)=paced
  && !hit_limit(&s,&format!("refresh-sid:{sid}"),30,60).await? {return Err(ApiError(StatusCode::TOO_MANY_REQUESTS,"try_later").into())}
 let mut tx=s.pool.begin().await?;
 let row=sqlx::query("SELECT t.*,s.user_id,s.device_id,s.device_kind,s.binding_hash,s.revoked_at,s.revoked_reason,s.expires_at AS session_expires,u.disabled_at FROM account_tokens t JOIN account_sessions s ON s.id=t.session_id JOIN account_users u ON u.id=s.user_id WHERE t.token_hash=$1 AND t.kind='refresh' FOR UPDATE OF t,s,u")
  .bind(digest(&v.refresh_token)).fetch_optional(&mut *tx).await?.ok_or_else(ApiError::unauthorized)?;
 let sid:Uuid=row.get("session_id");let user:Uuid=row.get("user_id");
 // 设备绑定先过。`session_replaced` 等于告诉对方「这个账号刚在另一台手机上登录了」，
 // 这话只该说给真正拿着这台设备密钥的人听。
 let bound=row.get::<Uuid,_>("device_id")==v.device.id && row.get::<String,_>("binding_hash").as_bytes().ct_eq(digest(&v.device.secret).as_bytes()).unwrap_u8()==1;
 if !bound {return Err(ApiError::unauthorized().into())}
 if row.get::<Option<DateTime<Utc>>,_>("revoked_at").is_some() {return Err(dead_session(&row))}
 if row.get::<Option<DateTime<Utc>>,_>("disabled_at").is_some() || row.get::<DateTime<Utc>,_>("session_expires")<=Utc::now() || row.get::<DateTime<Utc>,_>("expires_at")<=Utc::now() {return Err(ApiError::unauthorized().into())}
 // 会话是哪一类设备开的，刷新时就得还是那一类。改口说自己是平板，无非是想让同一台
 // 机器在两个类别里各占一条会话，绕开「每类一台」。旧包不发 kind、算作手机，
 // 和它自己那条手机会话对得上，不受这一条影响。
 if kind_of(&row)!=v.device.kind {return Err(ApiError::bad("invalid_device").into())}
 if row.get::<Option<DateTime<Utc>>,_>("used_at").is_some() {
  // 同一个 request_id 就是同一次请求的重试，隔多久回来都还是重试：手机断网、切后台、
  // 进电梯，一次真实的中断远不止六十秒。此前超过六十秒就连整条会话一起吊销，
  // 等于替一次丢包把人踢下线。把当时那份密封结果原样还回去就够了。
  if row.get::<Option<Uuid>,_>("request_id")==Some(v.request_id) {
   // 保留窗（`maintenance` 那边扫的二十四小时）之外结果已被清掉，只能重新登录；
   // 但这仍然不是「令牌被别人捡去用了」，会话不该因此被吊销——那一轮换到的新令牌
   // 也许正在别的设备上好好用着。
   let Some(sealed)=row.get::<Option<String>,_>("response_sealed") else {return Err(ApiError::unauthorized().into())};
   let response=serde_json::from_slice(&s.secrets.open(&sealed)?)?;tx.commit().await?;return Ok(envelope(response));
  }
  // 换了 request_id 还拿着已经用过的 refresh：这才是重用，整条会话就此结束。
  sqlx::query("UPDATE account_sessions SET revoked_at=now() WHERE id=$1 AND revoked_at IS NULL").bind(sid).execute(&mut *tx).await?;tx.commit().await?;return Err(ApiError::unauthorized().into());
 }
 let response=tokens(&s,&mut tx,user,sid).await?;
 sqlx::query("UPDATE account_tokens SET used_at=now(),request_id=$2,response_sealed=$3 WHERE token_hash=$1")
  .bind(digest(&v.refresh_token)).bind(v.request_id).bind(s.secrets.seal(&serde_json::to_vec(&response)?)?).execute(&mut *tx).await?;
 sqlx::query("UPDATE account_sessions SET seen_at=now(),expires_at=now()+interval '30 days' WHERE id=$1").bind(sid).execute(&mut *tx).await?;
 tx.commit().await?;Ok(envelope(response))
}
async fn me(State(s):State<AppState>,i:Identity)->Result<Json<Value>> {
 let email:String=sqlx::query_scalar("SELECT email FROM account_users WHERE id=$1 AND disabled_at IS NULL").bind(i.user).fetch_optional(&s.pool).await?.ok_or_else(ApiError::unauthorized)?;
 Ok(envelope(json!({"id":i.user,"email":email,"sessionId":i.session})))
}
async fn logout(State(s):State<AppState>,i:Identity)->Result<Json<Value>> {
 sqlx::query("UPDATE account_sessions SET revoked_at=now(),revoked_reason='logout' WHERE id=$1 AND user_id=$2 AND revoked_at IS NULL").bind(i.session).bind(i.user).execute(&s.pool).await?;Ok(envelope(json!({"ok":true})))
}
/// 冷启动之后手上只有 refresh——access 从不落盘。退登要让服务端那条会话真的结束，
/// 就得有一条不依赖 access 的吊销路：拿 refresh + 设备绑定认证，和 `refresh` 同一把尺子。
///
/// 它**不轮换令牌**：为了退登先换一对新的再扔掉，只会在服务端多留一份没人要的凭据。
/// 重发是安全的——会话已经吊销过了仍旧回 200，别让退登卡在错误里。
async fn revoke_session(State(s):State<AppState>,Json(v):Json<RevokeInput>)->Result<Json<Value>> {
 v.device.validate()?;if v.refresh_token.len()>128 {return Err(ApiError::unauthorized())}
 let mut tx=s.pool.begin().await?;
 let row=sqlx::query("SELECT t.session_id,s.device_id,s.binding_hash FROM account_tokens t JOIN account_sessions s ON s.id=t.session_id WHERE t.token_hash=$1 AND t.kind='refresh' FOR UPDATE OF t,s")
  .bind(digest(&v.refresh_token)).fetch_optional(&mut *tx).await?.ok_or_else(ApiError::unauthorized)?;
 let bound=row.get::<Uuid,_>("device_id")==v.device.id && row.get::<String,_>("binding_hash").as_bytes().ct_eq(digest(&v.device.secret).as_bytes()).unwrap_u8()==1;
 if !bound {return Err(ApiError::unauthorized())}
 let sid:Uuid=row.get("session_id");
 sqlx::query("UPDATE account_sessions SET revoked_at=now(),revoked_reason='logout' WHERE id=$1 AND revoked_at IS NULL").bind(sid).execute(&mut *tx).await?;
 tx.commit().await?;Ok(envelope(json!({"ok":true})))
}
async fn devices(State(s):State<AppState>,i:Identity)->Result<Json<Value>> {
 let rows=sqlx::query("SELECT id,device_name,device_kind,created_at,seen_at FROM account_sessions WHERE user_id=$1 AND revoked_at IS NULL AND expires_at>now() ORDER BY seen_at DESC").bind(i.user).fetch_all(&s.pool).await?;
 Ok(envelope(json!({"devices":rows.iter().map(|r|json!({"id":r.get::<Uuid,_>("id"),"name":r.get::<String,_>("device_name"),"kind":r.get::<String,_>("device_kind"),"createdAt":r.get::<DateTime<Utc>,_>("created_at").timestamp_millis(),"lastSeen":r.get::<DateTime<Utc>,_>("seen_at").timestamp_millis(),"current":r.get::<Uuid,_>("id")==i.session})).collect::<Vec<_>>()})))
}
async fn revoke_device(State(s):State<AppState>,i:Identity,Path(id):Path<Uuid>)->Result<Json<Value>> {
 sqlx::query("UPDATE account_sessions SET revoked_at=now(),revoked_reason='device_revoked' WHERE id=$1 AND user_id=$2 AND revoked_at IS NULL").bind(id).bind(i.user).execute(&s.pool).await?;Ok(envelope(json!({"ok":true})))
}
async fn change_password(State(s):State<AppState>,i:Identity,Json(v):Json<ChangeInput>)->Result<Json<Value>> {
 password(&v.new_password)?;
 // 验旧密码、算新哈希两次 Argon2 都在事务外面（审查 A6），理由同 `login`。
 let seen=current_hash(&s.pool,i.user,false).await?.ok_or_else(ApiError::unauthorized)?;
 // 「密码不对」和「登录已失效」都回 authentication_failed 时，客户端只能把两者
 // 写成同一句话；改密码填错一次就被告知「密码不对」是对的，会话过期被告知
 // 「密码不对」就是在骗人。
 if !verify(&s,v.current_password,seen.clone()).await? {return Err(wrong_password())}
 let h=hash(&s,v.new_password).await?;
 let mut tx=s.pool.begin().await?;
 let now=current_hash(&mut *tx,i.user,true).await?.ok_or_else(ApiError::unauthorized)?;
 // 验完到上锁之间，另一台设备已经把密码改掉了：这里填的已经不是现在的密码。
 if now!=seen {return Err(wrong_password())}
 sqlx::query("UPDATE account_users SET password_hash=$2 WHERE id=$1").bind(i.user).bind(h).execute(&mut *tx).await?;
 sqlx::query("UPDATE account_sessions SET revoked_at=now(),revoked_reason='password_change' WHERE user_id=$1 AND id<>$2 AND revoked_at IS NULL").bind(i.user).bind(i.session).execute(&mut *tx).await?;
 tx.commit().await?;Ok(envelope(json!({"ok":true})))
}
async fn delete_account(State(s):State<AppState>,i:Identity,Json(v):Json<DeleteInput>)->Result<Json<Value>> {
 // Argon2 在事务外面（审查 A6）：这个事务要删的是这个人的全部数据，锁住的行最多，
 // 更不该一边攥着它们一边算哈希。
 let seen=current_hash(&s.pool,i.user,false).await?.ok_or_else(ApiError::unauthorized)?;
 if !verify(&s,v.password,seen.clone()).await? {return Err(wrong_password())}
 let mut tx=s.personal(i.user).await?;
 let now=current_hash(&mut *tx,i.user,true).await?.ok_or_else(ApiError::unauthorized)?;
 if now!=seen {return Err(wrong_password())}
 sqlx::query("INSERT INTO account_deletions(user_id) VALUES($1) ON CONFLICT DO NOTHING").bind(i.user).execute(&mut *tx).await?;
 // Foreign-key cascades cover every personal table; durable deletion ledger survives backups.
 sqlx::query("DELETE FROM account_users WHERE id=$1").bind(i.user).execute(&mut *tx).await?;
 sqlx::query("UPDATE account_deletions SET completed_at=now() WHERE user_id=$1").bind(i.user).execute(&mut *tx).await?;
 tx.commit().await?;Ok(envelope(json!({"ok":true})))
}
fn wrong_password()->ApiError {ApiError(StatusCode::UNAUTHORIZED,"wrong_password")}
/// 这个人现在的密码哈希；停用的账号当不存在。`for_update` 的含义同 `credential`。
async fn current_hash<'e,E:sqlx::PgExecutor<'e>>(e:E,user:Uuid,for_update:bool)->Result<Option<String>> {
 let sql=if for_update {"SELECT password_hash FROM account_users WHERE id=$1 AND disabled_at IS NULL FOR UPDATE"}
  else {"SELECT password_hash FROM account_users WHERE id=$1 AND disabled_at IS NULL"};
 Ok(sqlx::query_scalar(sql).bind(user).fetch_optional(e).await?)
}

/// 运维 CLI `kanpan-api reset-password <username>`：忘了密码的朋友找过来时，由我在服务器上
/// 替他换一把一次性新密码，登录后让他自己在账号页改掉。app 里不做「忘记密码」——
/// 没有邮箱就没有第二条能证明「你是你」的路，交给认识他的人来判断反而更可靠。
///
/// 换密码的同时吊销这个账号的全部会话、清掉登录失败的锁：旧设备上谁拿着令牌都得重新登录。
/// 吊销原因沿用 `password_change`（`revoked_reason` 有 CHECK 约束，客户端也只区分 `replaced`）。
pub async fn reset_password(s:&AppState,username:&str)->Result<String> {
 let name=email(username)?;
 let fresh=one_time_password();
 password(&fresh)?;
 let h=hash(s,fresh.clone()).await?;
 let mut tx=s.pool.begin().await?;lock_email(&mut tx,&name).await?;
 let user:Uuid=sqlx::query_scalar("UPDATE account_users SET password_hash=$2 WHERE email=$1 AND disabled_at IS NULL RETURNING id").bind(&name).bind(h).fetch_optional(&mut *tx).await?.ok_or(ApiError(StatusCode::NOT_FOUND,"unknown_username"))?;
 sqlx::query("UPDATE account_sessions SET revoked_at=now(),revoked_reason='password_change' WHERE user_id=$1 AND revoked_at IS NULL").bind(user).execute(&mut *tx).await?;
 sqlx::query("DELETE FROM account_limits WHERE key=$1").bind(s.secrets.keyed(&format!("login:{name}"))).execute(&mut *tx).await?;
 tx.commit().await?;Ok(fresh)
}
/// 十四位、去掉了 0/O、1/l/I 这类念出来容易抄错的字符；保证至少一个字母一个数字，满足注册规则。
fn one_time_password()->String {
 use rand::Rng;
 const LETTERS:&[u8]=b"abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ";const DIGITS:&[u8]=b"23456789";
 let mut rng=rand::rng();
 loop {
  let v:String=(0..14).map(|i|{let pool=if i%4==3 {DIGITS} else {LETTERS};pool[rng.random_range(0..pool.len())] as char}).collect();
  if v.chars().any(|c|c.is_ascii_digit()) && v.chars().any(|c|c.is_ascii_alphabetic()) {return v}
 }
}

#[cfg(test)]
mod tests {
 use super::*;
 /// 事务外验过的哈希，上锁后必须还是同一个账号的同一把，登录才算数。
 #[test]
 fn a_hash_verified_outside_the_lock_must_still_be_current() {
  let a=Uuid::new_v4();let b=Uuid::new_v4();
  let seen=Some((a,"h1".to_string()));
  assert_eq!(still_current(&seen,&Some((a,"h1".into()))),Some(a));
  assert_eq!(still_current(&seen,&Some((a,"h2".into()))),None,"验完之后密码被改了");
  assert_eq!(still_current(&seen,&Some((b,"h1".into()))),None,"账号删了又被别人注册了同名");
  assert_eq!(still_current(&seen,&None),None,"验完之后账号被删或停用了");
  assert_eq!(still_current(&None,&Some((a,"h1".into()))),None);
 }
 /// **用户名、密码规则两端一个口径**：客户端边输边校验（`AccountCredentialRules`），
 /// 不合格就不让点提交；这里是最终裁决。夹具里每一条，`email`（注册 / 登录）和
 /// `password` 的结论都必须和夹具一字不差——客户端那边的 CredentialRulesContractTests
 /// 读的是同一份；「发给朋友」那一处的 `share::username` 在 share.rs 里对同一份夹具。
 #[test]
 fn every_shared_credential_case_agrees() {
  let v:Value=serde_json::from_str(include_str!("../contract/account-credentials.json")).expect("contract/account-credentials.json is not valid JSON");
  assert_eq!(v["version"],1,"account-credentials.json 的格式版本变了，这里的读法要一起改");
  let names=v["username"]["cases"].as_array().expect("username cases");
  assert!(names.len()>=10,"用户名夹具被删薄了");
  for c in names {
   let input=c["input"].as_str().expect("input");
   let want=c["accepted"].as_str().map(str::to_string);
   assert_eq!(email(input).ok(),want,"auth 用户名 {input:?}");
  }
  let words=v["password"]["cases"].as_array().expect("password cases");
  assert!(words.len()>=10,"密码夹具被删薄了");
  for c in words {
   let input=c["input"].as_str().expect("input");
   assert_eq!(password(input).is_ok(),c["ok"].as_bool().expect("ok"),"密码 {input:?}");
  }
 }
 #[test]
 fn one_time_passwords_pass_the_signup_rule_and_differ() {
  let a=one_time_password();let b=one_time_password();
  assert!(password(&a).is_ok());assert_eq!(a.len(),14);assert_ne!(a,b);
  assert!(!a.contains(['0','O','1','l','I']));
 }
 fn headers(pairs:&[(&str,&str)])->HeaderMap {
  let mut h=HeaderMap::new();
  for (k,v) in pairs {h.insert(axum::http::HeaderName::from_bytes(k.as_bytes()).unwrap(),v.parse().unwrap());}
  h
 }
 #[test]
 fn only_a_loopback_peer_may_name_the_client() {
  let proxy:SocketAddr="127.0.0.1:19000".parse().unwrap();
  let direct:SocketAddr="198.51.100.9:40000".parse().unwrap();
  // 反向代理把它看到的对端追加在尾部，客户端伪造的排在前面。
  assert_eq!(client_ip(&proxy,&headers(&[("x-forwarded-for","203.0.113.7, 198.51.100.2")])).to_string(),"198.51.100.2");
  assert_eq!(client_ip(&proxy,&headers(&[("x-forwarded-for","198.51.100.2:443")])).to_string(),"198.51.100.2");
  assert_eq!(client_ip(&proxy,&headers(&[("x-forwarded-for","[2001:db8::1]:443")])).to_string(),"2001:db8::1");
  assert_eq!(client_ip(&proxy,&headers(&[("x-real-ip","198.51.100.3")])).to_string(),"198.51.100.3");
  // 尾段是垃圾就当没有这个头，退回对端，绝不去信前面那几段。
  assert_eq!(client_ip(&proxy,&headers(&[("x-forwarded-for","198.51.100.2, not-an-address")])).to_string(),"127.0.0.1");
  assert_eq!(client_ip(&proxy,&headers(&[])).to_string(),"127.0.0.1");
  // 直连过来的请求带什么头都不算数。
  assert_eq!(client_ip(&direct,&headers(&[("x-forwarded-for","203.0.113.7"),("x-real-ip","203.0.113.8")])).to_string(),"198.51.100.9");
 }
}
