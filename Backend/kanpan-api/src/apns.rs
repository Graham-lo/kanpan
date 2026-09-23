//! 苹果推送（APNs）的 provider 端：HTTP/2 + `.p8` 令牌认证。
//!
//! **没有密钥是当前的常态，不是待办。** 这个项目还没有 Apple 开发者会员，也就没有 .p8，
//! 所以这个模块的每一条路都按「密钥根本不在」设计：`Apns::from_env` 只写一行 info 并返回
//! `None`，服务照常起、评估器照常跑、fired / firedAt / firedPrice 照常写库并进 alerts 同步
//! 集合——客户端开 app 拉一次同步就看得到那条已触发的提醒，少的只是锁屏上那一下横幅。
//! 不重试、不报错、不在启动时拦任何东西；将来真拿到密钥，填上那几个环境变量重启即可生效。
use crate::error::{ApiError,Result};
use jsonwebtoken::{Algorithm,EncodingKey,Header};
use serde::Serialize;
use serde_json::json;
use std::sync::Mutex;
use std::time::{Duration,Instant};

/// 一次推送的结局里服务端唯一需要分辨的两种。
///
/// `Gone` 是「这枚 token 已经死了，别再留着」：app 被卸载、重装、或者环境搞错
/// （用 sandbox 的 token 推 production）。苹果对这种情况回 410 或者
/// 400 + `BadDeviceToken`，两者都要当场把那一行删掉，否则每条提醒都要为一枚死 token
/// 多跑一次往返，而且苹果会把持续推死 token 的 provider 记一笔。
#[derive(Debug,PartialEq,Eq,Clone,Copy)]
pub enum Outcome {Delivered,Gone}

/// APNs 的两个环境。开发包（Xcode 直接跑到手机上的那种）拿到的 token 只有 sandbox
/// 认，TestFlight 与 App Store 的包只有 production 认，两边的 token 长得一模一样。
fn host(environment:&str)->&'static str {
 if environment=="sandbox" {"https://api.sandbox.push.apple.com"} else {"https://api.push.apple.com"}
}

/// 签好的 provider 令牌与它的出生时间。
///
/// 苹果的规矩：同一个 JWT 至少用 20 分钟、最多 60 分钟，太勤快地换会被当成滥用挡回来
/// （`TooManyProviderTokenUpdates`），过期了则是 403 `ExpiredProviderToken`。
/// 55 分钟落在窗口正中间。
struct Cached {token:String,born:Instant}

pub struct Apns {
 client:reqwest::Client,
 key:EncodingKey,
 key_id:String,
 team_id:String,
 topic:String,
 /// 某一行 token 没说自己是哪个环境时按它算（`KANPAN_APNS_ENV`）。
 default_environment:String,
 cached:Mutex<Option<Cached>>,
}

#[derive(Serialize)]
struct Claims<'a> {iss:&'a str,iat:i64}

/// 签一枚 APNs provider 令牌。
///
/// 故意不带 `exp`：苹果的 provider 令牌只认 `iat`，自己按一小时算过期。解码侧因此也要
/// 把 `exp` 的必填与校验都关掉（见本文件的测试），不然验的是一个协议里根本没有的字段。
fn sign(key:&EncodingKey,key_id:&str,team_id:&str,issued_at:i64)->Result<String> {
 let mut header=Header::new(Algorithm::ES256);
 header.kid=Some(key_id.to_string());
 jsonwebtoken::encode(&header,&Claims{iss:team_id,iat:issued_at},key).map_err(|e|{
  tracing::warn!("APNs token could not be signed: {e}");
  ApiError::bad("apns_token")
 })
}

/// 只允许随账号同步的四档；旧账号、损坏字段与新版本未知值都使用系统声。
pub fn alert_sound(settings:Option<&serde_json::Value>)->&'static str {
 match settings.and_then(|v|v.get("alertSound")).and_then(serde_json::Value::as_str) {
  Some("crisp")=>"alert-crisp.caf",
  Some("electronic")=>"alert-electronic.caf",
  Some("glass")=>"alert-glass.caf",
  _=>"default",
 }
}

/// 生产推送与回归验收共用同一个 payload 构造口。
///
/// `kind` 是这条推送从哪儿来（`alert` / `reviewDue` / `watchMove`）。客户端前台自己已经
/// 提示过的那几种靠它在 `willPresent` 里把横幅压掉，免得前台响两下。
fn alert_payload(title:&str,body:&str,link:&str,sound:&str,kind:&str)->serde_json::Value {
 json!({
  "aps":{"alert":{"title":title,"body":body},"sound":sound,"thread-id":"alerts"},
  "link":link,
  "kind":kind,
 })
}

impl Apns {
 /// 从 `/etc/kanpan-api/service.env` 那五个变量把推送装起来；缺一样就不装。
 ///
 /// 返回 `None` 不是错误路径，是**目前的常态**：这个项目还没有 Apple 开发者会员，
 /// 于是根本不存在 .p8 密钥。没有密钥时提醒的其余部分一样不少——照样评估、照样把
 /// fired / firedAt / firedPrice 写库并写进 alerts 同步集合，客户端下次拉同步就看得到——
 /// 少的只是最后那一下横幅。所以它是 info 不是 warn：这不是一个待办，是一种运行方式。
 /// 调用方（worker）在启动时调一次，所以日志里正好一行，之后不再重试、不再抱怨。
 pub fn from_env()->Option<Self> {
  let get=|k:&str|std::env::var(k).ok().filter(|v|!v.trim().is_empty());
  let (Some(path),Some(key_id),Some(team_id),Some(topic))=
   (get("KANPAN_APNS_KEY_PATH"),get("KANPAN_APNS_KEY_ID"),get("KANPAN_APNS_TEAM_ID"),get("KANPAN_APNS_TOPIC")) else {
   tracing::info!("APNs is not configured (KANPAN_APNS_KEY_PATH/KEY_ID/TEAM_ID/TOPIC); alerts still fire, still record firedAt/firedPrice and still sync -- only the banner is skipped");
   return None
  };
  let pem=match std::fs::read(&path) {
   Ok(v)=>v,
   Err(e)=>{tracing::warn!("APNs key {path} could not be read ({e}); alerts will still fire and sync, but nothing will be pushed");return None}
  };
  let key=match EncodingKey::from_ec_pem(&pem) {
   Ok(v)=>v,
   Err(e)=>{tracing::warn!("APNs key {path} is not a usable ES256 .p8 ({e}); alerts will still fire and sync, but nothing will be pushed");return None}
  };
  let environment=get("KANPAN_APNS_ENV").unwrap_or_else(||"production".into());
  // 连接池留着：一次触发可能要推这个人的两三台设备，重开 TLS + HTTP/2 握手是纯浪费。
  // ALPN 由 reqwest 的 http2 特性带上（Cargo.toml 里已经开了）；APNs 只说 HTTP/2，
  // 所以协商出来的一定是 h2——这里不写死 prior knowledge，免得握手上再加一层假设。
  let client=match reqwest::Client::builder().timeout(Duration::from_secs(10)).pool_idle_timeout(Duration::from_secs(300)).build() {
   Ok(v)=>v,
   Err(e)=>{tracing::warn!("APNs HTTP client could not be built ({e}); nothing will be pushed");return None}
  };
  tracing::info!("APNs ready: topic {topic}, default environment {environment}");
  Some(Self{client,key,key_id,team_id,topic,default_environment:environment,cached:Mutex::new(None)})
 }
 /// 当前该用的 provider 令牌，超过 55 分钟就换一枚。
 fn token(&self)->Result<String> {
  let mut cached=self.cached.lock().map_err(|_|ApiError::bad("apns_token"))?;
  if let Some(v)=cached.as_ref() && v.born.elapsed()<Duration::from_secs(55*60) {return Ok(v.token.clone())}
  let token=sign(&self.key,&self.key_id,&self.team_id,chrono::Utc::now().timestamp())?;
  *cached=Some(Cached{token:token.clone(),born:Instant::now()});
  Ok(token)
 }
 /// 一条提醒的推送。payload 的形状写死在方案文档 2.4 里。
 ///
 /// `link` 是深链（`hkline://drawing/<SYMBOL>/<drawingID>`），点通知就跳回那条线上。
 pub async fn push_alert(&self,device_token:&str,environment:&str,title:&str,body:&str,link:&str,sound:&str,kind:&str)->Result<Outcome> {
  let payload=alert_payload(title,body,link,sound,kind);
  self.send(device_token,environment,"alert",None,&payload).await
 }
 /// 灵动岛 / 锁屏实时活动的推送。调用方是 `src/live_activity.rs`（心跳与结束两条路）。
 ///
 /// 它和上面那条只差三处，而这三处正是容易搞错的地方：push type 是 `liveactivity`、
 /// topic 要在 bundle id 后面缀 `.push-type.liveactivity`、payload 里是 `content-state`
 /// 而不是 `alert`。
 ///
 /// `stale_after` 是一个**绝对**的 UNIX 秒（和 `timestamp` 同一把尺），不是「多少秒之后」。
 /// 客户端过了这个点就把那一块标成停更——调用方一律给「此刻 + 150 秒」。
 pub async fn push_live_activity(&self,device_token:&str,environment:&str,content_state:&serde_json::Value,event:&str,stale_after:i64)->Result<Outcome> {
  let payload=json!({
   "aps":{"timestamp":chrono::Utc::now().timestamp(),"event":event,"content-state":content_state,"stale-date":stale_after},
  });
  let topic=format!("{}.push-type.liveactivity",self.topic);
  self.send(device_token,environment,"liveactivity",Some(&topic),&payload).await
 }
 /// 环境是**每一枚 token 自己的属性**，不是整个服务的：Xcode 直接装到手机上的开发包拿到
 /// 的是 sandbox token，TestFlight / App Store 的包拿到的是 production token，而同一个
 /// 账号完全可能两台设备各装一种。所以主机名按行选，`KANPAN_APNS_ENV` 只是那一行没说
 /// 清楚时的缺省——把整个服务钉在一个环境上，另一种包就永远收不到通知。
 async fn send(&self,device_token:&str,environment:&str,push_type:&str,topic:Option<&str>,payload:&serde_json::Value)->Result<Outcome> {
  // token 是客户端报上来的十六进制串。拼进 URL 之前先把形状卡死：这一段是路径，
  // 一个带斜杠的「token」就能把请求发到别的地方去。
  if device_token.is_empty()||device_token.len()>200||!device_token.bytes().all(|c|c.is_ascii_hexdigit()) {
   return Ok(Outcome::Gone)
  }
  let environment=if environment.is_empty() {self.default_environment.as_str()} else {environment};
  let url=format!("{}/3/device/{device_token}",host(environment));
  let response=self.client.post(&url)
   .header("authorization",format!("bearer {}",self.token()?))
   .header("apns-topic",topic.unwrap_or(&self.topic))
   .header("apns-push-type",push_type)
   .header("apns-priority","10")
   .header("apns-expiration","0")
   .json(payload).send().await.map_err(|e|{tracing::warn!("APNs request failed: {e}");ApiError::bad("apns_unreachable")})?;
  let status=response.status();
  if status.is_success() {return Ok(Outcome::Delivered)}
  let reason=response.text().await.unwrap_or_default();
  // 410 是「这枚 token 不在了」；400 + BadDeviceToken 是同一件事的另一种说法
  // （环境搞错时苹果回的是后者）。两种都要把那一行删掉。
  if status.as_u16()==410||reason.contains("BadDeviceToken")||reason.contains("Unregistered") {
   tracing::info!("APNs dropped a dead device token ({status})");
   return Ok(Outcome::Gone)
  }
  tracing::warn!("APNs refused a push: {status} {reason}");
  Err(ApiError::bad("apns_refused"))
 }
}

#[cfg(test)]
mod tests {
 use super::*;
 use base64::Engine;
 use jsonwebtoken::{DecodingKey,Validation};
 use ring::signature::KeyPair;

 #[test] fn alert_sound_falls_back_for_old_or_invalid_settings() {
  assert_eq!(alert_sound(None),"default");
  for settings in [json!({}),json!(null),json!({"alertSound":null}),json!({"alertSound":1}),json!({"alertSound":true}),json!({"alertSound":"unknown"}),json!({"alertSound":"../custom.caf"})] {
   assert_eq!(alert_sound(Some(&settings)),"default");
  }
 }

 #[test] fn alert_payload_uses_the_selected_sound_and_keeps_the_deep_link() {
  for (setting,sound) in [("default","default"),("crisp","alert-crisp.caf"),("electronic","alert-electronic.caf"),("glass","alert-glass.caf")] {
   let settings=json!({"alertSound":setting});
   let payload=alert_payload("铃声验收 · 玻璃","现价 64500","hkline://symbol/BTCUSDT",alert_sound(Some(&settings)),"alert");
   assert_eq!(payload["aps"]["sound"],sound);
   assert_eq!(payload["aps"]["alert"]["title"],"铃声验收 · 玻璃");
   assert_eq!(payload["aps"]["alert"]["body"],"现价 64500");
   assert_eq!(payload["aps"]["thread-id"],"alerts");
   assert_eq!(payload["link"],"hkline://symbol/BTCUSDT");
   assert_eq!(payload["kind"],"alert");
   if setting=="glass" {println!("RINGTONE_PAYLOAD={payload}");}
  }
 }

 /// 现造一把 P-256 私钥，PEM 包成 `.p8` 的样子。
 ///
 /// 不往仓库里放真钥匙：一枚测试用的 EC 私钥进了 git，以后谁也说不清它是不是真的
 /// 没被用过。ring 本来就在依赖树里（rustls 用它）。
 fn generated_key()->(Vec<u8>,Vec<u8>) {
  let rng=ring::rand::SystemRandom::new();
  let pkcs8=ring::signature::EcdsaKeyPair::generate_pkcs8(&ring::signature::ECDSA_P256_SHA256_FIXED_SIGNING,&rng).expect("a P-256 key");
  let pair=ring::signature::EcdsaKeyPair::from_pkcs8(&ring::signature::ECDSA_P256_SHA256_FIXED_SIGNING,pkcs8.as_ref(),&rng).expect("the key parses back");
  let body=base64::engine::general_purpose::STANDARD.encode(pkcs8.as_ref());
  let pem=format!("-----BEGIN PRIVATE KEY-----\n{}\n-----END PRIVATE KEY-----\n",
   body.as_bytes().chunks(64).map(|c|String::from_utf8_lossy(c).into_owned()).collect::<Vec<_>>().join("\n"));
  (pem.into_bytes(),pair.public_key().as_ref().to_vec())
 }

 /// **签出来的是一枚苹果会认的 ES256 令牌。**
 ///
 /// 认的标准有三条，缺一条苹果就是 403：算法 ES256、header 带 `kid`、载荷里 `iss` 是
 /// team id 且有 `iat`。这里用同一把钥匙的公钥验一遍，顺带把 `exp` 的校验关掉——
 /// provider 令牌里没有这个字段，默认的 `Validation` 会因为它缺席而拒绝。
 #[test] fn a_provider_token_is_a_signed_es256_jwt() {
  let (pem,public)=generated_key();
  let key=EncodingKey::from_ec_pem(&pem).expect("the generated .p8 loads");
  let issued=1_800_000_000i64;
  let token=sign(&key,"ABC1234567","27Y32PT2HZ",issued).expect("signing works");
  let header=jsonwebtoken::decode_header(&token).expect("a readable header");
  assert_eq!(header.alg,Algorithm::ES256);
  assert_eq!(header.kid.as_deref(),Some("ABC1234567"));
  let mut validation=Validation::new(Algorithm::ES256);
  validation.validate_exp=false;
  validation.required_spec_claims.clear();
  let decoded=jsonwebtoken::decode::<serde_json::Value>(&token,&DecodingKey::from_ec_der(&public),&validation).expect("the signature verifies");
  assert_eq!(decoded.claims["iss"],json!("27Y32PT2HZ"));
  assert_eq!(decoded.claims["iat"],json!(issued));
 }

 /// 换一把钥匙就验不过——上面那条测试才不是在验一个恒真的东西。
 #[test] fn another_key_does_not_verify_it() {
  let (pem,_)=generated_key();
  let (_,other)=generated_key();
  let key=EncodingKey::from_ec_pem(&pem).expect("the generated .p8 loads");
  let token=sign(&key,"ABC1234567","27Y32PT2HZ",1_800_000_000).expect("signing works");
  let mut validation=Validation::new(Algorithm::ES256);
  validation.validate_exp=false;
  validation.required_spec_claims.clear();
  assert!(jsonwebtoken::decode::<serde_json::Value>(&token,&DecodingKey::from_ec_der(&other),&validation).is_err());
 }

 /// 环境挑主机名：开发包的 token 只有 sandbox 认。
 #[test] fn the_environment_picks_the_host() {
  assert_eq!(host("sandbox"),"https://api.sandbox.push.apple.com");
  assert_eq!(host("production"),"https://api.push.apple.com");
  // 拼错了按生产算：线上的包是生产包，猜错方向的代价小得多。
  assert_eq!(host(""),"https://api.push.apple.com");
 }

 /// 密钥不在的时候不要 panic，也不要把服务拦住。
 #[test] fn a_missing_key_is_not_an_error() {
  // 这条测试不去改进程环境（并发跑的别的测试也在读它），只**读**：机器上没有配
  // KANPAN_APNS_* 时——线上现在就是这个样子——`from_env` 必须安安静静地返回 None。
  if std::env::var_os("KANPAN_APNS_KEY_PATH").is_none() {
   assert!(Apns::from_env().is_none(),"no key configured is a way to run, not a failure");
  }
  // 缺的若是密钥本身的内容（文件在但不是 ES256 .p8），走的也是同一个函数的另一支。
  assert!(EncodingKey::from_ec_pem(b"not a key").is_err());
 }
}
