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
#[derive(Deserialize)] #[serde(deny_unknown_fields)] struct Cursor {after:Option<String>}
#[derive(Deserialize)] #[serde(deny_unknown_fields)] struct AddFriend {username:String}
pub fn routes()->Router<AppState> {
 Router::new().route("/v1/friends",get(friends).post(add_friend))
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
/// 朋友页上的「加朋友」：只把对方记进**我自己**的朋友表，不替他加我。
///
/// 从前朋友只能靠「发一次线」结成（P4.11 把没人用的这条删了）；朋友页要有自己的入口
/// （审查 U15），就又要回来。和删朋友一样只动自己那一行——通讯录是自己的，
/// 往别人的通讯录里塞人只该发生在真的给他发了东西的时候（`send` 那条双向建）。
/// 用户名规则和注册同一条（`username`），对方不存在回 404 `no_such_user`，加自己回
/// 400 `cannot_send_self`；已经是朋友时照样 200，按钮点两下不算错。
async fn add_friend(State(s):State<AppState>,who:Identity,Payload(v):Payload<AddFriend>)->Result<Json<Value>> {
 let name=username(&v.username)?;
 if !hit_limit(&s,&format!("friend-add:{}",who.user),30,60).await? {return Err(ApiError(StatusCode::TOO_MANY_REQUESTS,"try_later"))}
 let mut tx=s.personal(who.user).await?;let other=recipient(&mut tx,&name,who.user).await?;
 befriend(&mut tx,who.user,other).await?;
 tx.commit().await?;Ok(envelope(json!({"username":name})))
}
async fn remove_friend(State(s):State<AppState>,who:Identity,Route(name):Route<String>)->Result<Json<Value>> {
 let name=username(&name)?;let mut tx=s.personal(who.user).await?;
 sqlx::query("DELETE FROM friendships WHERE user_id=$1 AND friend_id IN (SELECT id FROM account_users WHERE email=$2)").bind(who.user).bind(name).execute(&mut *tx).await?;
 tx.commit().await?;Ok(envelope(json!({"ok":true})))
}
fn share_identity(symbol:&str)->(&str,&str,&str) {
 let parts:Vec<_>=symbol.split('/').collect();
 if parts.len()==3 {(parts[0],parts[1],parts[2])} else {(crate::instruments::DEFAULT_VENUE,crate::instruments::DEFAULT_MARKET,symbol)}
}
/// 分享里每条画线可能出现的键（去掉 `id`，它单独校验）：就是客户端 `Drawing` 编码会写的那些。
/// 和 `SHARE_REQUIRED`、`SHARE_RENAMED` 一起逐项对着 `contract/drawing-fields.json`
/// （由 Swift 那边拿真实编码生成）——测试 `share_fields_are_what_drawing_encodes`。
pub const SHARE_FIELDS:[&str;10]=["color","dash","filled","hidden","kind","levels","lineWidth","locked","points","text"];
/// 每条画线都一定会写的键：`color` 只在设过颜色时写、`text` 只有带文字的工具写，所以不在这里。
pub const SHARE_REQUIRED:[&str;8]=["dash","filled","hidden","kind","levels","lineWidth","locked","points"];
/// 分享用 `Drawing` 自己的键名，个人同步用线上的名字；改完名交给同一套值规则。
pub const SHARE_RENAMED:[(&str,&str);1]=[("points","anchors")];
fn validate(v:&Send)->Result<()> {
 let (venue,market,symbol)=share_identity(&v.symbol);
 if !sync_validation::field(sync::DRAWINGS,"symbol",&json!(symbol)) || !sync_validation::identity(venue,market,symbol) || !crate::instruments::is_interval(&v.interval) || v.view.from<0 || v.view.to>9_000_000_000_000_000 || v.view.from>=v.view.to || !(1..=200).contains(&v.drawings.len()) {return Err(ApiError::bad("invalid_share"))}
 let mut ids=HashSet::new();
 for drawing in &v.drawings {
  let map=drawing.as_object().ok_or(ApiError::bad("invalid_drawing"))?;
  let id=map.get("id").and_then(Value::as_str).filter(|s|!s.is_empty()&&s.len()<=100&&s.bytes().all(|b|b.is_ascii_alphanumeric()||b==b'-'||b==b'_')).ok_or(ApiError::bad("invalid_drawing"))?;
  if !ids.insert(id) {return Err(ApiError::bad("invalid_drawing"))}
  // Drawing Codable 使用 points，个人同步使用 anchors；这里只适配名称，规则完全共用。
  if SHARE_REQUIRED.iter().any(|key|!map.contains_key(*key)) {return Err(ApiError::bad("invalid_drawing"))}
  let mut body=BTreeMap::new();
  for (key,value) in map {
   if key=="id" {continue}
   if !SHARE_FIELDS.contains(&key.as_str()) {return Err(ApiError::bad("invalid_drawing"))}
   let wire=SHARE_RENAMED.iter().find(|(from,_)|*from==key).map_or(key.as_str(),|(_,to)|*to);
   body.insert(wire.to_string(),value.clone());
  }
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
/// 收件箱的游标。客户端当它是不透明的字符串，原样放回 `after`。
#[derive(Clone,Debug,PartialEq)]
pub enum InboxCursor {
 /// 没截断：本次查询的时刻，下次取改动时刻 `>=` 它的（RFC3339，和以前的游标一模一样）。
 Since(DateTime<Utc>),
 /// 截断了：这一页最后一封的（改动时刻, id），下次取严格排在它后面的（`时刻~id`）。
 ///
 /// 以前截断时只回最后一封的时刻、下次按 `>=` 接着拉：同一时刻的信超过一页时
 /// （一次批量「已读」就能让几百封的改动时刻落在同一个事务时刻上），游标永远停在
 /// 那个时刻、每次都拉回同一页，排在后面的再也拉不到。按 (时刻, id) 复合比较就不会卡住。
 After(DateTime<Utc>,String),
}
impl InboxCursor {
 pub fn encode(&self)->String {
  let ts=|t:&DateTime<Utc>|t.to_rfc3339_opts(chrono::SecondsFormat::AutoSi,true);
  match self {Self::Since(t)=>ts(t),Self::After(t,id)=>format!("{}~{id}",ts(t))}
 }
 pub fn parse(text:&str)->Option<Self> {
  if text.len()>200 {return None}
  let time=|t:&str|DateTime::parse_from_rfc3339(t).ok().map(|t|t.with_timezone(&Utc));
  match text.split_once('~') {
   None=>time(text).map(Self::Since),
   Some((t,id)) if !id.is_empty()&&id.len()<=64&&id.bytes().all(|b|b.is_ascii_alphanumeric())=>Some(Self::After(time(t)?,id.to_owned())),
   Some(_)=>None,
  }
 }
}
/// 这一页之后客户端下次该从哪儿接着拉：没截断回 `now`，截断了回这一页最后一封。
pub fn inbox_cursor(rows:&[(DateTime<Utc>,String)],now:DateTime<Utc>)->InboxCursor {
 match rows.get(INBOX_PAGE-1) {
  Some((changed,id)) if rows.len()>INBOX_PAGE=>InboxCursor::After(*changed,id.clone()),
  _=>InboxCursor::Since(now),
 }
}
async fn inbox(State(s):State<AppState>,who:Identity,Params(v):Params<Cursor>)->Result<Json<Value>> {
 let (after,after_id)=match v.after.as_deref().map(InboxCursor::parse) {
  None=>(None,None),
  Some(None)=>return Err(ApiError::bad("invalid_cursor")),
  Some(Some(InboxCursor::Since(t)))=>(Some(t),None),
  Some(Some(InboxCursor::After(t,id)))=>(Some(t),Some(id)),
 };
 let mut tx=s.personal(who.user).await?;lock(&mut tx,who.user).await?;
 // 列表不带截图（`shot` 每封最多 300 KB，原来 `SELECT s.*` 把它们整列读出来又丢掉）；
 // 截图走 `GET /v1/shares/{id}/shot` 单取。按改动时刻正序分页，多取一行判断截断没有；
 // 客户端自己按创建时间排序，不依赖这里的顺序。
 let mut rows=sqlx::query("SELECT s.id,s.symbol,s.market,s.interval,s.view_from,s.view_to,s.drawings,s.alerted,s.created_at,s.opened_at,s.kept_at,s.reply_to,u.email AS sender,greatest(s.created_at,s.opened_at,s.kept_at) AS changed FROM shares s JOIN account_users u ON u.id=s.from_user WHERE to_user=$1 AND ($2::timestamptz IS NULL OR ($3::text IS NULL AND greatest(s.created_at,s.opened_at,s.kept_at)>=$2) OR ($3::text IS NOT NULL AND (greatest(s.created_at,s.opened_at,s.kept_at),s.id)>($2,$3))) ORDER BY changed,s.id LIMIT $4")
  .bind(who.user).bind(after).bind(after_id).bind(INBOX_PAGE as i64+1).fetch_all(&mut *tx).await?;
 let now:DateTime<Utc>=sqlx::query_scalar("SELECT clock_timestamp()").fetch_one(&mut *tx).await?;
 let cursor=inbox_cursor(&rows.iter().map(|r|(r.get::<DateTime<Utc>,_>("changed"),r.get::<String,_>("id"))).collect::<Vec<_>>(),now).encode();
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
 /// 「发给朋友」填的用户名和注册用的是同一条规则：客户端的加朋友输入框与注册页
 /// 共用 `AccountCredentialRules`，这里对的是同一份 `contract/account-credentials.json`。
 #[test]
 fn recipient_names_follow_the_shared_username_rule() {
  let v:Value=serde_json::from_str(include_str!("../contract/account-credentials.json")).expect("contract/account-credentials.json is not valid JSON");
  for c in v["username"]["cases"].as_array().expect("username cases") {
   let input=c["input"].as_str().expect("input");
   assert_eq!(username(input).ok(),c["accepted"].as_str().map(str::to_string),"share 用户名 {input:?}");
  }
 }
 /// 客户端 `Drawing` 编码导出的那份，编进来而不是运行时读：文件缺了或坏了是编译错误。
 const DRAWING_CONTRACT:&str=include_str!("../contract/drawing-fields.json");
 fn drawing_contract()->Value {serde_json::from_str(DRAWING_CONTRACT).expect("contract/drawing-fields.json is not valid JSON; regenerate it with `make sync-contract`")}
 fn strings(v:&Value)->Vec<String> {let mut all:Vec<String>=v.as_array().expect("contract list").iter().map(|s|s.as_str().expect("string").to_string()).collect();all.sort();all}
 fn ours(list:&[&str])->Vec<String> {let mut all:Vec<String>=list.iter().map(|s|s.to_string()).collect();all.sort();all}
 /// **分享收哪些画线键、哪些必须在，就是客户端 `Drawing` 编码写哪些键。**
 ///
 /// 这两张表从前是 `validate` 里两段手写的字面量，和 `Drawing.encode(to:)` 各管各的：
 /// 客户端多编一个键，服务端不认 → 整次分享 400；服务端多要一个客户端不一定写的键 → 同样 400。
 /// 契约是 Swift 那边拿真实编码结果生成的，它是对的一方：照它改这里的三个常量。
 /// 只有契约本身过期（有人改了 Drawing 没重新生成）时，才先在仓库根跑 `make sync-contract`。
 #[test] fn share_fields_are_what_drawing_encodes() {
  let c=drawing_contract();
  assert_eq!(c["version"],json!(1),"drawing-fields.json 的格式版本变了，这里的读法要一起改");
  assert_eq!(ours(&SHARE_FIELDS),strings(&c["shareFields"]),"SHARE_FIELDS 和契约的 shareFields 对不上");
  assert_eq!(ours(&SHARE_REQUIRED),strings(&c["shareRequiredFields"]),"SHARE_REQUIRED 和契约的 shareRequiredFields 对不上");
  let renamed:Vec<(String,String)>=c["renamed"].as_object().expect("renamed").iter().map(|(k,v)|(k.clone(),v.as_str().expect("string").to_string())).collect();
  let mut have:Vec<(String,String)>=SHARE_RENAMED.iter().map(|(a,b)|(a.to_string(),b.to_string())).collect();have.sort();
  assert_eq!(have,renamed,"SHARE_RENAMED 和契约的 renamed 对不上");
 }
 /// 契约里每种工具的样本（点数、颜色、文字都照客户端会写的那样）整条分享都收；
 /// 少了任何一个必带键就拒。这一条证明上面三个常量在 `validate` 里真的被用上了。
 #[test] fn every_tool_the_client_encodes_is_shareable() {
  let c=drawing_contract();
  for (kind,count) in c["anchorCounts"].as_object().expect("anchorCounts") {
   let n=count.as_u64().expect("count") as i64;
   let points:Vec<Value>=(0..n).map(|i|json!({"t":1_800_000_000_000i64+i*60_000,"p":100+i})).collect();
   let mut v=good();
   v["drawings"][0]=json!({"id":"line1","kind":kind,"points":points,"color":{"value":"#112233"},"text":"x","lineWidth":1.3,"dash":"solid","filled":true,"hidden":false,"locked":false,"levels":[]});
   assert!(validate(&serde_json::from_value(v.clone()).unwrap()).is_ok(),"{kind}");
   for key in SHARE_REQUIRED {
    let mut w=v.clone();w["drawings"][0].as_object_mut().unwrap().remove(key);
    assert!(validate(&serde_json::from_value(w).unwrap()).is_err(),"{kind} without {key}");
   }
  }
 }
 fn good()->Value {json!({"to":"qa_friend","symbol":"BTCUSDT","interval":"1h","view":{"from":1,"to":2},"drawings":[{"id":"line1","kind":"trend","points":[{"t":1,"p":100},{"t":2,"p":110}],"lineWidth":1.3,"dash":"solid","filled":true,"hidden":false,"locked":false,"levels":[]}],"alerted":["line1"]})}
 /// 截断了就停在这一页最后一封（时刻 + id），下次从它后面接着拉；没截断照旧回「现在」。
 #[test] fn a_truncated_inbox_page_resumes_from_its_last_letter() {
  let t=|n:i64|DateTime::<Utc>::from_timestamp(1_800_000_000+n,0).unwrap();
  let now=t(10_000);
  let row=|n:i64|(t(n),format!("id{n:04}"));
  assert_eq!(inbox_cursor(&[],now),InboxCursor::Since(now));
  let full:Vec<_>=(0..INBOX_PAGE as i64).map(row).collect();
  assert_eq!(inbox_cursor(&full,now),InboxCursor::Since(now),"刚好一页不算截断");
  let over:Vec<_>=(0..=INBOX_PAGE as i64).map(row).collect();
  assert_eq!(inbox_cursor(&over,now),InboxCursor::After(t(INBOX_PAGE as i64-1),format!("id{:04}",INBOX_PAGE-1)),"多出来的那一封下次还拿得到");
 }
 /// 同一时刻的信超过一页：游标带上 id，下一页从这一刻里排在它后面的那封接着拉，不会原地打转。
 #[test] fn a_page_of_letters_sharing_one_instant_still_moves_the_cursor() {
  let at=DateTime::<Utc>::from_timestamp(1_800_000_000,123_456_000).unwrap();
  let rows:Vec<_>=(0..=INBOX_PAGE).map(|n|(at,format!("id{n:04}"))).collect();
  let cursor=inbox_cursor(&rows,at);
  assert_eq!(cursor,InboxCursor::After(at,format!("id{:04}",INBOX_PAGE-1)));
  // 编出去再读回来是同一个游标；以前那种纯时刻的游标仍然认。
  assert_eq!(InboxCursor::parse(&cursor.encode()),Some(cursor.clone()));
  assert_eq!(cursor.encode(),"2027-01-15T08:00:00.123456Z~id0199");
  assert_eq!(InboxCursor::parse("2027-01-15T08:00:00.123456Z"),Some(InboxCursor::Since(at)));
  assert_eq!(InboxCursor::parse(&InboxCursor::Since(at).encode()),Some(InboxCursor::Since(at)));
  for bad in ["","yesterday","2027-01-15T08:00:00Z~","2027-01-15T08:00:00Z~a b","2027-01-15T08:00:00Z~a~b"] {assert_eq!(InboxCursor::parse(bad),None,"{bad}");}
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
