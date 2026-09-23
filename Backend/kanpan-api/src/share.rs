//! 一封只带线的信。布局与提醒实例不会越过账号边界。
use crate::{AppState,auth::{Identity,hit_limit},envelope,error::{ApiError,Result,Payload,Params,Route},sync,sync_validation};
use axum::{Router,Json,body::Bytes,extract::State,http::{StatusCode,HeaderMap,header},routing::{get,post,put,delete},response::IntoResponse};
use chrono::{DateTime,Utc};
use rand::distr::{Alphanumeric,SampleString};
use serde::Deserialize;
use serde_json::{Value,json};
use sqlx::{Row,Postgres,Transaction};
use std::collections::{BTreeMap,HashSet};
use uuid::Uuid;
#[derive(Deserialize)] #[serde(deny_unknown_fields)] struct View {from:i64,to:i64}
#[derive(Deserialize)] #[serde(deny_unknown_fields)]
struct Send {to:String,symbol:String,interval:String,view:View,drawings:Vec<Value>,#[serde(default)] alerted:Vec<String>,
 // 「回给他」：在他发来的那封信的线上接着画，再发回去。只能指向**我收到的、正是他发的**那一封。
 #[serde(default,rename="replyTo")] reply_to:Option<String>}
#[derive(Deserialize)] #[serde(deny_unknown_fields)] struct Cursor {after:Option<DateTime<Utc>>}
pub fn routes()->Router<AppState> {
 Router::new().route("/v1/friends",get(friends))
  .route("/v1/friends/{username}",delete(remove_friend))
  .route("/v1/shares",post(send)).route("/v1/shares/inbox",get(inbox))
  .route("/v1/shares/{id}/shot",put(put_shot).get(get_shot))
  .route("/v1/shares/{id}/opened",post(opened)).route("/v1/shares/{id}/kept",post(kept))
}
fn username(v:&str)->Result<String> {
 let v=v.trim().to_ascii_lowercase();
 if !(3..=32).contains(&v.len()) || !v.bytes().all(|b|b.is_ascii_alphanumeric()||b==b'_') {return Err(ApiError::bad("invalid_username"))} Ok(v)
}
async fn recipient(tx:&mut Transaction<'_,Postgres>,name:&str,owner:Uuid)->Result<Uuid> {
 let id:Uuid=sqlx::query_scalar("SELECT id FROM account_users WHERE email=$1 AND disabled_at IS NULL FOR SHARE").bind(name).fetch_optional(&mut **tx).await?.ok_or(ApiError(StatusCode::NOT_FOUND,"no_such_user"))?;
 if id==owner {return Err(ApiError::bad("cannot_send_self"))} Ok(id)
}
// 对同一收件箱串行写入 / 取游标；锁内取 clock_timestamp，不漏较早开事务、较晚提交的信。
async fn lock(tx:&mut Transaction<'_,Postgres>,owner:Uuid)->Result<()> {
 sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))").bind(format!("shares:{owner}")).execute(&mut **tx).await?; Ok(())
}
async fn befriend(tx:&mut Transaction<'_,Postgres>,owner:Uuid,other:Uuid)->Result<()> {
 sqlx::query("INSERT INTO friendships(user_id,friend_id) VALUES($1,$2) ON CONFLICT DO NOTHING").bind(owner).bind(other).execute(&mut **tx).await?; Ok(())
}
async fn friends(State(s):State<AppState>,who:Identity)->Result<Json<Value>> {
 let mut tx=s.personal(who.user).await?;
 let names:Vec<String>=sqlx::query_scalar("SELECT u.email FROM friendships f JOIN account_users u ON u.id=f.friend_id WHERE f.user_id=$1 AND u.disabled_at IS NULL ORDER BY u.email").bind(who.user).fetch_all(&mut *tx).await?;
 tx.commit().await?; Ok(envelope(json!(names.into_iter().map(|username|json!({"username":username})).collect::<Vec<_>>())))
}
async fn remove_friend(State(s):State<AppState>,who:Identity,Route(name):Route<String>)->Result<Json<Value>> {
 let name=username(&name)?;let mut tx=s.personal(who.user).await?;
 sqlx::query("DELETE FROM friendships WHERE user_id=$1 AND friend_id IN (SELECT id FROM account_users WHERE email=$2)").bind(who.user).bind(name).execute(&mut *tx).await?;
 tx.commit().await?;Ok(envelope(json!({"ok":true})))
}
fn share_identity(symbol:&str)->(&str,&str,&str) {
 let parts:Vec<_>=symbol.split('/').collect();
 if parts.len()==3 {(parts[0],parts[1],parts[2])} else {("binance","usd_m",symbol)}
}
fn validate(v:&Send)->Result<()> {
 let (venue,market,symbol)=share_identity(&v.symbol);
 if !sync_validation::field(sync::DRAWINGS,"symbol",&json!(symbol)) || !sync_validation::identity(venue,market,symbol) || !crate::instruments::is_interval(&v.interval) || v.view.from<0 || v.view.to>9_000_000_000_000_000 || v.view.from>=v.view.to || !(1..=200).contains(&v.drawings.len()) {return Err(ApiError::bad("invalid_share"))}
 let mut ids=HashSet::new();
 for drawing in &v.drawings {
  let map=drawing.as_object().ok_or(ApiError::bad("invalid_drawing"))?;
  let id=map.get("id").and_then(Value::as_str).filter(|s|!s.is_empty()&&s.len()<=100&&s.bytes().all(|b|b.is_ascii_alphanumeric()||b==b'-'||b==b'_')).ok_or(ApiError::bad("invalid_drawing"))?;
  if !ids.insert(id) {return Err(ApiError::bad("invalid_drawing"))}
  // Drawing Codable 使用 points，个人同步使用 anchors；这里只适配名称，规则完全共用。
  let mut body=BTreeMap::new();
  for (key,value) in map {
   if key=="id" {continue}
   if !["kind","points","color","lineWidth","dash","filled","locked","hidden","levels","text"].contains(&key.as_str()) {return Err(ApiError::bad("invalid_drawing"))}
   body.insert(if key=="points" {"anchors".into()} else {key.clone()},value.clone());
  }
  for key in ["kind","anchors","lineWidth","dash","filled","locked","hidden","levels"] {if !body.contains_key(key) {return Err(ApiError::bad("invalid_drawing"))}}
  body.insert("symbol".into(),json!(symbol));
  body.insert("venue".into(),json!(venue)); body.insert("market".into(),json!(market));
  sync_validation::object(&sync::Object{collection:sync::DRAWINGS.into(),id:format!("{venue}/{market}/{symbol}/{id}"),body,fields:BTreeMap::new(),revision:0,deleted:false,generation:0})?;
 }
 if v.reply_to.as_deref().is_some_and(|r|r.len()!=22||!r.bytes().all(|b|b.is_ascii_alphanumeric())) {return Err(ApiError::bad("invalid_reply_to"))}
 if v.alerted.len()>ids.len() || v.alerted.iter().any(|id|!ids.contains(id.as_str())) || v.alerted.iter().collect::<HashSet<_>>().len()!=v.alerted.len() {return Err(ApiError::bad("invalid_alerted"))} Ok(())
}
async fn send(State(s):State<AppState>,who:Identity,Payload(v):Payload<Send>)->Result<Json<Value>> {
 validate(&v)?;let name=username(&v.to)?;
 if !hit_limit(&s,&format!("share-send:{}",who.user),20,60).await? {return Err(ApiError(StatusCode::TOO_MANY_REQUESTS,"try_later"))}
 let mut tx=s.personal(who.user).await?;let other=recipient(&mut tx,&name,who.user).await?;
 // 双向建朋友在一个事务中完成，按 UUID 排锁，互发也不会死锁。
 for owner in [who.user.min(other),who.user.max(other)] {lock(&mut tx,owner).await?;}
 befriend(&mut tx,who.user,other).await?;
 sqlx::query("SELECT set_config('kanpan.user_id',$1,true)").bind(other.to_string()).execute(&mut *tx).await?;
 befriend(&mut tx,other,who.user).await?;
 sqlx::query("SELECT set_config('kanpan.user_id',$1,true)").bind(who.user.to_string()).execute(&mut *tx).await?;
 if let Some(reply)=&v.reply_to {
  // RLS 下我只看得见自己收发的信；再加两道条件：收件人是我、发件人正是这次的收件人。
  let ok:bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM shares WHERE id=$1 AND to_user=$2 AND from_user=$3)").bind(reply).bind(who.user).bind(other).fetch_one(&mut *tx).await?;
  if !ok {return Err(ApiError::bad("invalid_reply_to"))}
 }
 let id=Alphanumeric.sample_string(&mut rand::rng(),22);
  let (venue,market,_)=share_identity(&v.symbol); let market_key=format!("{venue}/{market}");
  sqlx::query("INSERT INTO shares(id,from_user,to_user,symbol,interval,view_from,view_to,drawings,alerted,market,reply_to) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)").bind(&id).bind(who.user).bind(other).bind(v.symbol).bind(v.interval).bind(v.view.from).bind(v.view.to).bind(json!(v.drawings)).bind(json!(v.alerted)).bind(market_key).bind(&v.reply_to).execute(&mut *tx).await?;
 tx.commit().await?;Ok(envelope(json!({"id":id})))
}
/// 收件箱一页最多这么多封。
pub const INBOX_PAGE:usize=200;
/// 这一页之后客户端下次该从哪儿接着拉。
///
/// 没截断：`now`（本次查询的时刻），和原来一样。截断了：这一页最后一封的改动时刻——
/// 查询条件是 `>=`，所以那一封下次会再来一遍（客户端按 id 合并，重复无害），而这一页
/// 之后的那些一封都不会漏。原来截断之后照样回 `now`，没拿到的那些就永远拿不到了。
pub fn inbox_cursor(changed:&[DateTime<Utc>],now:DateTime<Utc>)->DateTime<Utc> {
 if changed.len()>INBOX_PAGE {changed[INBOX_PAGE-1]} else {now}
}
async fn inbox(State(s):State<AppState>,who:Identity,Params(v):Params<Cursor>)->Result<Json<Value>> {
 let mut tx=s.personal(who.user).await?;lock(&mut tx,who.user).await?;
 // 列表不带截图（`shot` 每封最多 300 KB，原来 `SELECT s.*` 把它们整列读出来又丢掉）；
 // 截图走 `GET /v1/shares/{id}/shot` 单取。按改动时刻正序分页，多取一行判断截断没有；
 // 客户端自己按创建时间排序，不依赖这里的顺序。
 let mut rows=sqlx::query("SELECT s.id,s.symbol,s.market,s.interval,s.view_from,s.view_to,s.drawings,s.alerted,s.created_at,s.opened_at,s.kept_at,s.reply_to,u.email AS sender,greatest(s.created_at,s.opened_at,s.kept_at) AS changed FROM shares s JOIN account_users u ON u.id=s.from_user WHERE to_user=$1 AND ($2::timestamptz IS NULL OR greatest(s.created_at,s.opened_at,s.kept_at)>=$2) ORDER BY changed,s.id LIMIT $3")
  .bind(who.user).bind(v.after).bind(INBOX_PAGE as i64+1).fetch_all(&mut *tx).await?;
 let now:DateTime<Utc>=sqlx::query_scalar("SELECT clock_timestamp()").fetch_one(&mut *tx).await?;
 let cursor=inbox_cursor(&rows.iter().map(|r|r.get::<DateTime<Utc>,_>("changed")).collect::<Vec<_>>(),now);
 rows.truncate(INBOX_PAGE);
 let items:Vec<Value>=rows.iter().map(|r|json!({"id":r.get::<String,_>("id"),"from":r.get::<String,_>("sender"),"symbol":r.get::<String,_>("symbol"),"market":r.get::<String,_>("market"),"interval":r.get::<String,_>("interval"),"view":{"from":r.get::<i64,_>("view_from"),"to":r.get::<i64,_>("view_to")},"drawings":r.get::<Value,_>("drawings"),"alerted":r.get::<Value,_>("alerted"),"createdAt":r.get::<DateTime<Utc>,_>("created_at"),"openedAt":r.get::<Option<DateTime<Utc>>,_>("opened_at"),"keptAt":r.get::<Option<DateTime<Utc>>,_>("kept_at"),"replyTo":r.get::<Option<String>,_>("reply_to")})).collect();
 tx.commit().await?;Ok(envelope(json!({"items":items,"cursor":cursor})))
}
async fn put_shot(State(s):State<AppState>,who:Identity,Route(id):Route<String>,headers:HeaderMap,body:Bytes)->Result<Json<Value>> {
 if body.len()>300*1024 {return Err(ApiError(StatusCode::PAYLOAD_TOO_LARGE,"shot_too_large"))}
 if headers.get(header::CONTENT_TYPE).and_then(|v|v.to_str().ok())!=Some("image/jpeg") || !body.starts_with(&[0xff,0xd8,0xff]) || !body.ends_with(&[0xff,0xd9]) {return Err(ApiError::bad("invalid_shot"))}
 let mut tx=s.personal(who.user).await?;
 if sqlx::query("UPDATE shares SET shot=$1 WHERE id=$2 AND from_user=$3").bind(body.as_ref()).bind(id).bind(who.user).execute(&mut *tx).await?.rows_affected()==0 {return Err(ApiError::missing())}
 tx.commit().await?;Ok(envelope(json!({"ok":true})))
}
async fn get_shot(State(s):State<AppState>,who:Identity,Route(id):Route<String>)->Result<impl IntoResponse> {
 let mut tx=s.personal(who.user).await?;
 let shot:Option<Vec<u8>>=sqlx::query_scalar("SELECT shot FROM shares WHERE id=$1 AND (from_user=$2 OR to_user=$2)").bind(id).bind(who.user).fetch_optional(&mut *tx).await?.flatten();
 tx.commit().await?;Ok(([(header::CONTENT_TYPE,"image/jpeg"),(header::CACHE_CONTROL,"private, no-store")],shot.ok_or_else(ApiError::missing)?))
}
async fn mark(s:&AppState,owner:Uuid,id:&str,keep:bool)->Result<Json<Value>> {
 let mut tx=s.personal(owner).await?;lock(&mut tx,owner).await?;
 let sql=if keep {"UPDATE shares SET opened_at=coalesce(opened_at,clock_timestamp()),kept_at=coalesce(kept_at,clock_timestamp()) WHERE id=$1 AND to_user=$2"} else {"UPDATE shares SET opened_at=coalesce(opened_at,clock_timestamp()) WHERE id=$1 AND to_user=$2"};
 if sqlx::query(sql).bind(id).bind(owner).execute(&mut *tx).await?.rows_affected()==0 {return Err(ApiError::missing())}
 tx.commit().await?;Ok(envelope(json!({"ok":true})))
}
async fn opened(State(s):State<AppState>,who:Identity,Route(id):Route<String>)->Result<Json<Value>> {mark(&s,who.user,&id,false).await}
async fn kept(State(s):State<AppState>,who:Identity,Route(id):Route<String>)->Result<Json<Value>> {mark(&s,who.user,&id,true).await}
#[cfg(test)] mod tests {
 use super::*;
 fn good()->Value {json!({"to":"qa_friend","symbol":"BTCUSDT","interval":"1h","view":{"from":1,"to":2},"drawings":[{"id":"line1","kind":"trend","points":[{"t":1,"p":100},{"t":2,"p":110}],"lineWidth":1.3,"dash":"solid","filled":true,"hidden":false,"locked":false,"levels":[]}],"alerted":["line1"]})}
 /// 截断了就停在这一页最后一封，下次从它接着拉；没截断照旧回「现在」。
 #[test] fn a_truncated_inbox_page_resumes_from_its_last_letter() {
  let t=|n:i64|DateTime::<Utc>::from_timestamp(1_800_000_000+n,0).unwrap();
  let now=t(10_000);
  assert_eq!(inbox_cursor(&[],now),now);
  let full:Vec<_>=(0..INBOX_PAGE as i64).map(t).collect();
  assert_eq!(inbox_cursor(&full,now),now,"刚好一页不算截断");
  let over:Vec<_>=(0..=INBOX_PAGE as i64).map(t).collect();
  assert_eq!(inbox_cursor(&over,now),t(INBOX_PAGE as i64-1),"多出来的那一封下次还拿得到");
 }
 #[test] fn bad_drawings_use_sync_validation() {
  assert!(validate(&serde_json::from_value(good()).unwrap()).is_ok());
  for (field,bad) in [("points",json!([{"t":1,"p":2}])),("lineWidth",json!(90)),("kind",json!("unknown")),("hidden",json!("false")),("color",json!({"value":"bad"})),("other",json!(true))] {
   let mut v=good();v["drawings"][0][field]=bad;assert!(validate(&serde_json::from_value(v).unwrap()).is_err(),"{field}");
  }
  let mut v=good();v["alerted"]=json!(["not-present"]);assert!(validate(&serde_json::from_value(v).unwrap()).is_err());
  let mut v=good();v["interval"]=json!("8h");assert!(validate(&serde_json::from_value(v).unwrap()).is_err());

 }
 #[test] fn reply_to_must_look_like_a_share_id() {
  let mut v=good();v["replyTo"]=json!("abcdefghijklmnopqrstuv");assert!(validate(&serde_json::from_value(v).unwrap()).is_ok());
  for bad in ["short","abcdefghijklmnopqrstu/","abcdefghijklmnopqrstuvw"] {
   let mut v=good();v["replyTo"]=json!(bad);assert!(validate(&serde_json::from_value(v).unwrap()).is_err(),"{bad}");
  }
  let mut v=good();v["reply_to"]=json!("abcdefghijklmnopqrstuv");assert!(serde_json::from_value::<Send>(v).is_err(),"snake_case is an unknown field");
 }
 /// 周期表只有一份（`instruments::INTERVALS`，那边逐项对着 Swift 比）。分享只收对方周期条上
 /// 点得到的：同步还收着的老周期（8h、3d）在这里要被拒。
 #[test] fn a_share_is_on_an_interval_the_friend_can_pick() {
  for interval in crate::instruments::INTERVALS {
   let mut v=good();v["interval"]=json!(interval);assert!(validate(&serde_json::from_value(v).unwrap()).is_ok(),"{interval}");
  }
  for interval in crate::instruments::LEGACY_INTERVALS.iter().chain(["7h",""].iter()) {
   let mut v=good();v["interval"]=json!(interval);assert!(validate(&serde_json::from_value(v).unwrap()).is_err(),"{interval}");
  }
 }
}
