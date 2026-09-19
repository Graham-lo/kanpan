use crate::{AppState,crypto::digest,envelope,error::{ApiError,Result}};
use axum::{Router,Json,extract::{State,Path,ConnectInfo,FromRequestParts},routing::{get,post,delete},http::{HeaderMap,request::Parts,StatusCode}};
use chrono::{DateTime,Duration,Utc};
use serde::{Deserialize,Serialize};
use serde_json::{Value,json};
use sqlx::{Row,Postgres,Transaction};
use std::net::{IpAddr,SocketAddr};
use uuid::Uuid;
use subtle::ConstantTimeEq;

#[derive(Clone,Copy)]
pub struct Identity {pub user:Uuid,pub session:Uuid}
impl FromRequestParts<AppState> for Identity {
 type Rejection=ApiError;
 async fn from_request_parts(parts:&mut Parts,s:&AppState)->Result<Self> {
  let token=parts.headers.get("authorization").and_then(|h|h.to_str().ok()).and_then(|v|v.strip_prefix("Bearer ")).filter(|t|t.len()<=128).ok_or_else(ApiError::unauthorized)?;
  let row=sqlx::query("SELECT s.user_id,s.id FROM account_tokens t JOIN account_sessions s ON s.id=t.session_id JOIN account_users u ON u.id=s.user_id WHERE t.token_hash=$1 AND t.kind='access' AND t.expires_at>now() AND s.expires_at>now() AND s.revoked_at IS NULL AND u.disabled_at IS NULL")
   .bind(digest(token)).fetch_optional(&s.pool).await?.ok_or_else(ApiError::unauthorized)?;
  Ok(Self{user:row.get("user_id"),session:row.get("id")})
 }
}
#[derive(Deserialize,Serialize,Clone)]
#[serde(rename_all="camelCase",deny_unknown_fields)]
pub struct Device {pub id:Uuid,pub name:String,pub secret:String}
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
fn client_ip(peer:&SocketAddr,headers:&HeaderMap)->IpAddr {
 if !peer.ip().is_loopback() {return peer.ip()}
 if let Some(list)=headers.get("x-forwarded-for").and_then(|h|h.to_str().ok()) {
  if let Some(last)=list.rsplit(',').next() {
   if let Some(ip)=parse_ip(last) {return ip}
  }
 }
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
async fn hit_limit(s:&AppState,key:&str,limit:i32,seconds:i64)->Result<bool> {
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
async fn new_session(s:&AppState,tx:&mut Transaction<'_,Postgres>,user:Uuid,device:&Device)->Result<Value> {
 let session=Uuid::new_v4();
 sqlx::query("UPDATE account_sessions SET revoked_at=now() WHERE user_id=$1 AND device_id=$2 AND revoked_at IS NULL").bind(user).bind(device.id).execute(&mut **tx).await?;
 sqlx::query("INSERT INTO account_sessions(id,user_id,device_id,device_name,binding_hash,expires_at) VALUES($1,$2,$3,$4,$5,now()+interval '30 days')")
  .bind(session).bind(user).bind(device.id).bind(device.name.trim()).bind(digest(&device.secret)).execute(&mut **tx).await?;
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
 let mut tx=s.pool.begin().await?;lock_email(&mut tx,&email).await?;
 let key=s.secrets.keyed(&format!("login:{email}"));
 let locked:bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM account_limits WHERE key=$1 AND locked_until>now())").bind(&key).fetch_one(&mut *tx).await?;
 let row=sqlx::query("SELECT id,password_hash FROM account_users WHERE email=$1 AND disabled_at IS NULL FOR UPDATE").bind(&email).fetch_optional(&mut *tx).await?;
 let h=row.as_ref().map(|r|r.get::<String,_>("password_hash")).unwrap_or_else(||s.dummy_hash.as_ref().clone());
 let valid=verify(&s,v.password,h).await?;
 if locked || !valid || row.is_none() {
  if !locked {sqlx::query("INSERT INTO account_limits(key,failures) VALUES($1,1) ON CONFLICT(key) DO UPDATE SET failures=CASE WHEN account_limits.locked_until<=now() THEN 1 ELSE account_limits.failures+1 END,locked_until=CASE WHEN account_limits.locked_until<=now() THEN NULL WHEN account_limits.failures>=4 THEN now()+interval '60 seconds' ELSE NULL END")
   .bind(key).execute(&mut *tx).await?;}
  tx.commit().await?;return Err(ApiError::unauthorized());
 }
 sqlx::query("DELETE FROM account_limits WHERE key=$1").bind(key).execute(&mut *tx).await?;
 let response=new_session(&s,&mut tx,row.unwrap().get("id"),&v.device).await?;tx.commit().await?;Ok(envelope(response))
}
async fn refresh(State(s):State<AppState>,Json(v):Json<RefreshInput>)->Result<Json<Value>> {
 v.device.validate()?;if v.refresh_token.len()>128{return Err(ApiError::unauthorized())}
 // 刷新没有密码那一关，只有一把令牌，此前也没有任何节流。access 十五分钟才换一次，
 // 正常客户端一条会话一分钟内绝到不了三十次；到了就是有人在拿它磨服务器。
 // 键取会话而不是令牌：轮换之后令牌每次都是新的，只有会话是同一条。
 let paced:Option<Uuid>=sqlx::query_scalar("SELECT session_id FROM account_tokens WHERE token_hash=$1 AND kind='refresh'").bind(digest(&v.refresh_token)).fetch_optional(&s.pool).await?;
 if let Some(sid)=paced {
  if !hit_limit(&s,&format!("refresh-sid:{sid}"),30,60).await? {return Err(ApiError(StatusCode::TOO_MANY_REQUESTS,"try_later"))}
 }
 let mut tx=s.pool.begin().await?;
 let row=sqlx::query("SELECT t.*,s.user_id,s.device_id,s.binding_hash,s.revoked_at,s.expires_at AS session_expires,u.disabled_at FROM account_tokens t JOIN account_sessions s ON s.id=t.session_id JOIN account_users u ON u.id=s.user_id WHERE t.token_hash=$1 AND t.kind='refresh' FOR UPDATE OF t,s,u")
  .bind(digest(&v.refresh_token)).fetch_optional(&mut *tx).await?.ok_or_else(ApiError::unauthorized)?;
 let sid:Uuid=row.get("session_id");let user:Uuid=row.get("user_id");
 if row.get::<Option<DateTime<Utc>>,_>("revoked_at").is_some() || row.get::<Option<DateTime<Utc>>,_>("disabled_at").is_some() || row.get::<DateTime<Utc>,_>("session_expires")<=Utc::now() || row.get::<DateTime<Utc>,_>("expires_at")<=Utc::now() {return Err(ApiError::unauthorized())}
 let bound=row.get::<Uuid,_>("device_id")==v.device.id && row.get::<String,_>("binding_hash").as_bytes().ct_eq(digest(&v.device.secret).as_bytes()).unwrap_u8()==1;
 if !bound {return Err(ApiError::unauthorized())}
 if row.get::<Option<DateTime<Utc>>,_>("used_at").is_some() {
  // 同一个 request_id 就是同一次请求的重试，隔多久回来都还是重试：手机断网、切后台、
  // 进电梯，一次真实的中断远不止六十秒。此前超过六十秒就连整条会话一起吊销，
  // 等于替一次丢包把人踢下线。把当时那份密封结果原样还回去就够了。
  if row.get::<Option<Uuid>,_>("request_id")==Some(v.request_id) {
   // 保留窗（`maintenance` 那边扫的二十四小时）之外结果已被清掉，只能重新登录；
   // 但这仍然不是「令牌被别人捡去用了」，会话不该因此被吊销——那一轮换到的新令牌
   // 也许正在别的设备上好好用着。
   let Some(sealed)=row.get::<Option<String>,_>("response_sealed") else {return Err(ApiError::unauthorized())};
   let response=serde_json::from_slice(&s.secrets.open(&sealed)?)?;tx.commit().await?;return Ok(envelope(response));
  }
  // 换了 request_id 还拿着已经用过的 refresh：这才是重用，整条会话就此结束。
  sqlx::query("UPDATE account_sessions SET revoked_at=now() WHERE id=$1").bind(sid).execute(&mut *tx).await?;tx.commit().await?;return Err(ApiError::unauthorized());
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
 sqlx::query("UPDATE account_sessions SET revoked_at=now() WHERE id=$1 AND user_id=$2").bind(i.session).bind(i.user).execute(&s.pool).await?;Ok(envelope(json!({"ok":true})))
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
 sqlx::query("UPDATE account_sessions SET revoked_at=now() WHERE id=$1 AND revoked_at IS NULL").bind(sid).execute(&mut *tx).await?;
 tx.commit().await?;Ok(envelope(json!({"ok":true})))
}
async fn devices(State(s):State<AppState>,i:Identity)->Result<Json<Value>> {
 let rows=sqlx::query("SELECT id,device_name,created_at,seen_at FROM account_sessions WHERE user_id=$1 AND revoked_at IS NULL AND expires_at>now() ORDER BY seen_at DESC").bind(i.user).fetch_all(&s.pool).await?;
 Ok(envelope(json!({"devices":rows.iter().map(|r|json!({"id":r.get::<Uuid,_>("id"),"name":r.get::<String,_>("device_name"),"createdAt":r.get::<DateTime<Utc>,_>("created_at").timestamp_millis(),"lastSeen":r.get::<DateTime<Utc>,_>("seen_at").timestamp_millis(),"current":r.get::<Uuid,_>("id")==i.session})).collect::<Vec<_>>()})))
}
async fn revoke_device(State(s):State<AppState>,i:Identity,Path(id):Path<Uuid>)->Result<Json<Value>> {
 sqlx::query("UPDATE account_sessions SET revoked_at=now() WHERE id=$1 AND user_id=$2").bind(id).bind(i.user).execute(&s.pool).await?;Ok(envelope(json!({"ok":true})))
}
async fn change_password(State(s):State<AppState>,i:Identity,Json(v):Json<ChangeInput>)->Result<Json<Value>> {
 password(&v.new_password)?;
 let mut tx=s.pool.begin().await?;
 let row=sqlx::query("SELECT password_hash FROM account_users WHERE id=$1 AND disabled_at IS NULL FOR UPDATE").bind(i.user).fetch_optional(&mut *tx).await?.ok_or_else(ApiError::unauthorized)?;
 // 「密码不对」和「登录已失效」都回 authentication_failed 时，客户端只能把两者
 // 写成同一句话；改密码填错一次就被告知「密码不对」是对的，会话过期被告知
 // 「密码不对」就是在骗人。
 if !verify(&s,v.current_password,row.get("password_hash")).await? {return Err(ApiError(StatusCode::UNAUTHORIZED,"wrong_password"))}
 let h=hash(&s,v.new_password).await?;
 sqlx::query("UPDATE account_users SET password_hash=$2 WHERE id=$1").bind(i.user).bind(h).execute(&mut *tx).await?;
 sqlx::query("UPDATE account_sessions SET revoked_at=now() WHERE user_id=$1 AND id<>$2").bind(i.user).bind(i.session).execute(&mut *tx).await?;
 tx.commit().await?;Ok(envelope(json!({"ok":true})))
}
async fn delete_account(State(s):State<AppState>,i:Identity,Json(v):Json<DeleteInput>)->Result<Json<Value>> {
 let mut tx=s.personal(i.user).await?;
 let row=sqlx::query("SELECT password_hash,email FROM account_users WHERE id=$1 AND disabled_at IS NULL FOR UPDATE").bind(i.user).fetch_optional(&mut *tx).await?.ok_or_else(ApiError::unauthorized)?;
 if !verify(&s,v.password,row.get("password_hash")).await? {return Err(ApiError(StatusCode::UNAUTHORIZED,"wrong_password"))}
 sqlx::query("INSERT INTO account_deletions(user_id) VALUES($1) ON CONFLICT DO NOTHING").bind(i.user).execute(&mut *tx).await?;
 // Foreign-key cascades cover every personal table; durable deletion ledger survives backups.
 sqlx::query("DELETE FROM account_users WHERE id=$1").bind(i.user).execute(&mut *tx).await?;
 sqlx::query("UPDATE account_deletions SET completed_at=now() WHERE user_id=$1").bind(i.user).execute(&mut *tx).await?;
 tx.commit().await?;Ok(envelope(json!({"ok":true})))
}

#[cfg(test)]
mod tests {
 use super::*;
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
