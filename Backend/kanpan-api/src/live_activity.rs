//! 画线提醒的实时活动（Live Activity）：锁屏与灵动岛上那一小块。
//!
//! 客户端建活动时把静态属性（`symbol` / `alertID` / `toolLabel`）定死，服务端一个字都不改；
//! 服务端只管那一小块里会变的东西——现价、24h 涨跌幅、线在此刻的价、现价到线的相对距离——
//! 以及它什么时候该结束。
//!
//! **为什么是心跳而不是逐笔推流。** app 在前台时价格由客户端自己的 `AlertEngine` 本地更新，
//! 服务端一条都不用推；这条链路存在的唯一理由是 app 被系统挂起之后，锁屏上那个数字不要
//! 一直冻着。所以是六十秒一拍的心跳（`HEARTBEAT`），不是每来一帧就推一次——十个人的
//! app 也不值得把苹果的推送通道当成行情流来用，苹果也会按预算把它掐掉。
//!
//! **`stale-date` 是这条链路的安全阀。** 每一拍都把它设成「此刻 + 150 秒」（心跳的 2.5 倍，
//! `STALE_AFTER`）：漏收两拍客户端就进 stale 态，锁屏上写「价格已停更」而不是继续展示一个
//! 冻住的数字。对一个行情 app 来说，**冻住的数字比没有数字更危险**——用户会照着它做决定。
//! 这个倍数是设计意图，别往长里调。
//!
//! **没有 APNs 密钥是当前的常态**（见 `src/apns.rs` 开头）。所以这里每一条路都分成两截：
//! 落库、记账、算内容照常走完，只有最后 `push_live_activity` 那一句被跳过，而且只留一行
//! info——`deliver` 返回 `Skipped`，调用方该删的行照样删。没有密钥不是一个会自己好起来的
//! 错误，不排队、不重试、不报警。
//!
//! **活动和提醒是怎么对上的。** 一枚 liveActivity 推送 token 就是「这台设备上正在跑的那
//! 一个活动」，`device_push_tokens` 的 `(user_id,device_id,kind)` 本来就是它的身份；0017
//! 只补了它缺的两件事：`alert_id`（它盯的是哪一条提醒）与 `started_at`（它是什么时候开始
//! 的，八小时从这里算）。触发时只推 `alert_id` 对得上的那一行，别的活动一概不碰。
use crate::{AppState,alerts::{Line,price_at},apns::{Apns,Outcome},auth::Identity,envelope,error::{ApiError,Payload,Result}};
use axum::{Router,Json,extract::State,routing::post};
use serde::Deserialize;
use serde_json::{Value,json};
use sqlx::{Postgres,Row,Transaction};
use std::collections::BTreeMap;
use std::time::Duration;
use uuid::Uuid;

/// 两拍之间隔多久。前台由客户端自己更新，这一拍只为被挂起的 app 而存在。
pub const HEARTBEAT:Duration=Duration::from_secs(60);
/// 每一拍把 `stale-date` 设到「此刻 + 这么久」。漏收两拍就进 stale 态。
pub const STALE_AFTER:Duration=Duration::from_secs(150);
/// 一个活动最长活这么久，到点一律 end + 清行。
pub const LIFETIME:Duration=Duration::from_secs(8*60*60);

/// 评估器那条连接上顺手记下来的行情。两个字段各自可空：只订到 K 线还没订到 ticker 的
/// 品种有价没有涨跌幅，这时涨跌幅就该是 `null`，不能拿 0 冒充。
#[derive(Clone,Copy,Debug,Default,PartialEq)]
pub struct Quote {pub price:Option<f64>,pub change:Option<f64>}

// ——————————————————————— content-state ———————————————————————

/// 一个可空的数。**取不到就是 `null`，不拿 0 或者上一拍的旧值冒充**——锁屏上一个过期的
/// 价格看起来和一个新鲜的价格一模一样，而用户会照着它做决定。非有限值（NaN / inf）同样
/// 当成取不到：它们序列化出来也是 `null`，但在这里显式收口，免得靠序列化器的脾气。
fn number(v:Option<f64>)->Value {match v {Some(v) if v.is_finite()=>json!(v),_=>Value::Null}}

/// 现价到线的**相对**距离 `(price - line) / line`。缺任一边、线价为零都算取不到。
pub fn distance(price:Option<f64>,line:Option<f64>)->Option<f64> {
 let (price,line)=(price?,line?);
 if !price.is_finite()||!line.is_finite()||line==0.0 {return None}
 Some((price-line)/line)
}

/// 推上去的那个 JSON 对象。七个键的形状是定死的契约，客户端的 `ContentState` 一一对应：
/// 少一个键客户端就解不出来，所以**每一拍七个键都在**，取不到的那几个是 `null` 而不是缺席。
pub fn content_state(price:Option<f64>,change:Option<f64>,line:Option<f64>,fired_at:Option<i64>,at:i64)->Value {
 json!({
  "price":number(price),
  "change":number(change),
  "line":number(line),
  "distance":number(distance(price,line)),
  "state":if fired_at.is_some() {"fired"} else {"watching"},
  "firedAt":fired_at,
  "updatedAt":at,
 })
}
/// 提醒响了那一下的 content-state。除了七个键，另带一个 `firedPrice`——它和 `price` 此刻
/// 是同一个数，但活动结束后客户端要留住的是「触发时的价」而不是「最后一次更新的价」，
/// 多一个键 Swift 的 `Decodable` 也不会因此解不出来。
///
/// `fired_at` 与 `at` 分开给：响的那一下两者相等，但心跳兜底去结束一个几小时前就响过、
/// 当时没推成功的活动时，`firedAt` 仍是当时那一刻，`updatedAt` 是这一拍——把两者写成
/// 同一个数，锁屏上那一块会显示成「几小时前更新的」。
pub fn fired_state(price:Option<f64>,change:Option<f64>,line:Option<f64>,fired_at:i64,at:i64)->Value {
 let mut state=content_state(price,change,line,Some(fired_at),at);
 if let Some(map)=state.as_object_mut() {map.insert("firedPrice".into(),number(price));}
 state
}

/// 这条提醒的线在此刻的价。
///
/// 一条提醒可能摊出好几条线（通道的两条边、斐波那契的每一级），锁屏上只有一个数的位置：
/// 取**离现价最近**的那一条——用户在等的就是那一条。趋势线是斜的，所以每一拍都要按当前
/// 时刻重算，用的是评估器那份 `price_at`，不另写一份。
pub fn line_price(lines:&[Line],price:Option<f64>,at:i64)->Option<f64> {
 let candidates=||lines.iter().filter_map(|l|price_at(l,at)).filter(|p|p.is_finite());
 let Some(price)=price.filter(|p|p.is_finite()) else {return candidates().next()};
 candidates().min_by(|a,b|(a-price).abs().partial_cmp(&(b-price).abs()).unwrap_or(std::cmp::Ordering::Equal))
}

// ——————————————————————— 推一条出去 ———————————————————————

/// 两种事件。`update` 是心跳，`end` 是这个活动到此为止。
#[derive(Debug,PartialEq,Eq,Clone,Copy)]
pub enum Event {Update,End}
impl Event {pub fn name(self)->&'static str {match self {Self::Update=>"update",Self::End=>"end"}}}

/// 一次推送的结局。`Skipped` 是**没有密钥**那一种：它不是失败，链路的其余部分照常走完。
#[derive(Debug,PartialEq,Eq,Clone,Copy)]
pub enum Delivery {Skipped,Delivered,Gone,Failed}

/// `stale-date`：此刻（秒）加 150 秒。APNs 的 `timestamp` 与 `stale-date` 都是秒。
pub fn stale_date(now:i64)->i64 {now+STALE_AFTER.as_secs() as i64}

/// 推完之后那一行还留着吗。
///
/// - `end` 一律删：活动已经结束，这行 token 再也推不出有意义的东西，留着只会让下一次
///   八小时清理去背它。推失败也删——重试一条已经结束的活动没有任何意义。
/// - `update` 只在苹果说这枚 token 已经不在了（`Gone`）时删。推不出去（网络、5xx）不删：
///   下一拍还要用它。
pub fn drops_the_row(event:Event,delivery:Delivery)->bool {matches!(event,Event::End)||delivery==Delivery::Gone}

/// 把一条 content-state 交给苹果。没有密钥时**不发信，但照样返回**，调用方该删的行照样删。
pub async fn deliver(apns:Option<&Apns>,token:&str,environment:&str,state:&Value,event:Event,now:i64)->Delivery {
 let Some(apns)=apns else {
  tracing::info!("A live activity {} was prepared and recorded, not pushed (no APNs key)",event.name());
  return Delivery::Skipped
 };
 match apns.push_live_activity(token,environment,state,event.name(),stale_date(now)).await {
  Ok(Outcome::Delivered)=>Delivery::Delivered,
  Ok(Outcome::Gone)=>{tracing::info!("A live activity token is gone; dropping it");Delivery::Gone}
  Err(_)=>{tracing::warn!("A live activity {} could not be pushed",event.name());Delivery::Failed}
 }
}

// ——————————————————————— 登记在册的活动 ———————————————————————

/// 库里那一行活动登记。`activity_id` / `alert_id` 可空是因为这张表同时装着 `alerts`
/// 与 `widget` 两种 kind——它们没有活动，读上来也不该被当成活动推。
#[derive(Clone,Debug,PartialEq)]
pub struct Registration {
 pub device:Uuid,pub token:String,pub environment:String,
 pub activity_id:Option<String>,pub alert_id:Option<String>,
 /// 这个活动已经开了多少秒（`started_at` 缺席的旧行退回 `updated_at`）。
 pub age:f64,
}
/// 这条提醒对得上的那些活动行。
///
/// **两道闸缺一不可**：`alert_id` 要和这条提醒相等——同一个人的另一条提醒开着的活动
/// 不该被这一下推成 fired；`activity_id` 要真的在——没有活动的纯 token 行（`alerts`
/// kind、或者一行还没带上活动 id 的登记）推过去只会被苹果拒绝。
pub fn targets<'a>(rows:&'a [Registration],alert_id:&str)->Vec<&'a Registration> {
 rows.iter().filter(|r|r.activity_id.is_some()&&r.alert_id.as_deref()==Some(alert_id)).collect()
}

/// 这一行活动下一步该怎么办。纯函数，因为这里的每一个分支都是一条用户看得见的行为。
#[derive(Debug,PartialEq,Eq,Clone,Copy)]
pub enum Step {
 /// 不是一个活动（没有活动 id 的纯 token 行），不碰。
 Idle,
 /// 心跳。
 Update,
 /// 到此为止。带着 `firedAt`（提醒响过才有）。
 End(Option<i64>),
}
/// - **满八小时一律结束**，哪怕提醒还活着：ActivityKit 自己也会在八小时后把活动收走，
///   服务端这一下是为了让锁屏上那一块是「结束」而不是「停更」。
/// - **提醒没了就结束**：用户在别的设备上把这条提醒删了，物化表那一行跟着没了
///   （`alerts::materialize`），活动就没有盯的对象了。
/// - **提醒不是 active 就结束**：`fired` 是响过了（`fire()` 通常已经推过一条 end，这里
///   兜住它推失败的那一次），别的状态（暂停）也没有继续更新的道理。
pub fn next_step(activity:bool,age:f64,status:Option<&str>,fired_at:Option<i64>)->Step {
 if !activity {return Step::Idle}
 if !age.is_finite()||age>=LIFETIME.as_secs() as f64 {return Step::End(fired_at)}
 match status {
  Some("active")=>Step::Update,
  _=>Step::End(fired_at),
 }
}

/// 这个人所有登记在册的活动 token 行。
async fn registrations(tx:&mut Transaction<'_,Postgres>,owner:Uuid)->Result<Vec<Registration>> {
 let rows=sqlx::query("SELECT device_id,token,environment,activity_id,alert_id,\
  EXTRACT(EPOCH FROM (now()-COALESCE(started_at,updated_at)))::double precision AS age \
  FROM device_push_tokens WHERE user_id=$1 AND kind='liveActivity'")
  .bind(owner).fetch_all(&mut **tx).await?;
 Ok(rows.iter().map(|r|Registration{
  device:r.get("device_id"),token:r.get("token"),environment:r.get("environment"),
  activity_id:r.get("activity_id"),alert_id:r.get("alert_id"),age:r.get::<Option<f64>,_>("age").unwrap_or_default(),
 }).collect())
}
/// 正被实时活动盯着的品种。评估器拿它决定要不要顺带订一条 `@ticker`（24h 涨跌幅只有
/// 那条流里有），所以这里只算「活动还在、提醒也还活着」的那些。
pub async fn active_symbols(tx:&mut Transaction<'_,Postgres>,owner:Uuid)->Result<Vec<String>> {
 Ok(sqlx::query_scalar("SELECT w.symbol FROM device_push_tokens t \
  JOIN alert_watches w ON w.user_id=t.user_id AND w.alert_id=t.alert_id \
  WHERE t.user_id=$1 AND t.kind='liveActivity' AND t.activity_id IS NOT NULL AND w.status='active'")
  .bind(owner).fetch_all(&mut **tx).await?)
}
/// 清掉一行活动登记。
async fn drop_row(s:&AppState,owner:Uuid,device:Uuid)->Result<()> {
 let mut tx=s.personal(owner).await?;
 sqlx::query("DELETE FROM device_push_tokens WHERE user_id=$1 AND device_id=$2 AND kind='liveActivity'")
  .bind(owner).bind(device).execute(&mut *tx).await?;
 tx.commit().await?;Ok(())
}
/// 推一条，然后按 `drops_the_row` 决定这一行还留不留。
async fn settle(s:&AppState,apns:Option<&Apns>,owner:Uuid,row:&Registration,state:&Value,event:Event,now:i64)->Result<()> {
 let delivery=deliver(apns,&row.token,&row.environment,state,event,now).await;
 if drops_the_row(event,delivery) {drop_row(s,owner,row.device).await?}
 Ok(())
}

// ——————————————————————— 两条入口：触发与心跳 ———————————————————————

/// 提醒响了：把盯着这条提醒的活动结束掉。由 `alerts::fire` 在写完库之后调用。
///
/// **没有密钥时这里照样走完**——查库、算 content-state、清那一行登记一样不少，少的只是
/// 发信那一句。这就是为什么 `fire()` 里它排在「没有密钥就 return」那一句的前面。
pub async fn end_fired(s:&AppState,apns:Option<&Apns>,owner:Uuid,alert_id:&str,quote:Quote,line:Option<f64>,at:i64)->Result<()> {
 let rows={
  let mut tx=s.personal(owner).await?;
  let rows=registrations(&mut tx,owner).await?;
  tx.commit().await?;rows
 };
 let targets=targets(&rows,alert_id);
 if targets.is_empty() {return Ok(())}
 let state=fired_state(quote.price,quote.change,line,at,at);
 let now=at/1000;
 for row in targets {settle(s,apns,owner,row,&state,Event::End,now).await?}
 Ok(())
}

/// 一拍心跳：所有人所有登记在册的活动各走一次 `next_step`。
///
/// 为什么逐个用户开事务：`device_push_tokens` 与 `alert_watches` 都挂着 FORCE ROW LEVEL
/// SECURITY，运行期角色既不是属主也没有 BYPASSRLS，没有一条能一次看见所有人的通道。
/// 代价是一拍 N 个短事务，而 N 是个位数——和 `alerts::load`、`maintenance::cleanup` 用的
/// 是同一套分页。
pub async fn beat(s:&AppState,apns:Option<&Apns>,quotes:&BTreeMap<String,Quote>)->Result<()> {
 let at=chrono::Utc::now().timestamp_millis();
 let now=at/1000;
 let mut after:Option<Uuid>=None;
 loop {
  let owners:Vec<Uuid>=sqlx::query_scalar("SELECT id FROM account_users WHERE disabled_at IS NULL AND ($1::uuid IS NULL OR id>$1) ORDER BY id LIMIT 100").bind(after).fetch_all(&s.pool).await?;
  if owners.is_empty() {break}
  for owner in &owners {
   let rows={
    let mut tx=match s.personal(*owner).await {Ok(tx)=>tx,Err(_)=>continue};
    // 一次把活动和它盯的那条提醒读齐：提醒没了（LEFT JOIN 出 NULL）正是「该结束」的
    // 判据之一，分两次读就得处理「读完活动之后提醒才被删」那种中间态。
    let rows=sqlx::query("SELECT t.device_id,t.token,t.environment,t.activity_id,t.alert_id,\
     EXTRACT(EPOCH FROM (now()-COALESCE(t.started_at,t.updated_at)))::double precision AS age,\
     w.symbol,w.lines,w.status,w.fired_at \
     FROM device_push_tokens t LEFT JOIN alert_watches w ON w.user_id=t.user_id AND w.alert_id=t.alert_id \
     WHERE t.user_id=$1 AND t.kind='liveActivity'")
     .bind(owner).fetch_all(&mut *tx).await?;
    tx.commit().await?;rows
   };
   for r in rows {
    let registration=Registration{
     device:r.get("device_id"),token:r.get("token"),environment:r.get("environment"),
     activity_id:r.get("activity_id"),alert_id:r.get("alert_id"),
     age:r.get::<Option<f64>,_>("age").unwrap_or_default(),
    };
    let status:Option<String>=r.get("status");
    let fired_at:Option<i64>=r.get("fired_at");
    let step=next_step(registration.activity_id.is_some(),registration.age,status.as_deref(),fired_at);
    if step==Step::Idle {continue}
    let symbol:Option<String>=r.get("symbol");
    let quote=symbol.as_deref().and_then(|s|quotes.get(s)).copied().unwrap_or_default();
    // 线要按**此刻**重算：斜线的价随时间走，锁屏上那个数不能是画线那一天的。
    let lines:Vec<Line>=r.get::<Option<Value>,_>("lines").and_then(|v|serde_json::from_value(v).ok()).unwrap_or_default();
    let line=line_price(&lines,quote.price,at);
    let (state,event)=match step {
     Step::Update=>(content_state(quote.price,quote.change,line,None,at),Event::Update),
     Step::End(fired)=>(match fired {
      Some(fired)=>fired_state(quote.price,quote.change,line,fired,at),
      None=>content_state(quote.price,quote.change,line,None,at),
     },Event::End),
     Step::Idle=>continue,
    };
    settle(s,apns,*owner,&registration,&state,event,now).await?;
   }
  }
  after=owners.last().copied();
 }
 Ok(())
}

// ——————————————————————— 手动结束 ———————————————————————

#[derive(Deserialize)]
#[serde(rename_all="camelCase",deny_unknown_fields)]
struct EndBody {activity_id:String}

pub fn routes()->Router<AppState> {
 Router::new().route("/v1/devices/live-activity/end",post(end))
}
/// `POST /v1/devices/live-activity/end`：用户自己把锁屏上那一块划掉了。
///
/// 只清行，不推 end——活动已经在那台设备上结束了，再推一条只是白跑一趟苹果。客户端忘了
/// 调也不会漏：提醒响了会清（`end_fired`）、提醒被删或满八小时会清（`beat`）、
/// 再不济还有 `maintenance::cleanup` 的八小时兜底。
async fn end(State(s):State<AppState>,i:Identity,Payload(v):Payload<EndBody>)->Result<Json<Value>> {
 if v.activity_id.is_empty()||v.activity_id.len()>200 {return Err(ApiError::bad("invalid_activity"))}
 let mut tx=s.personal(i.user).await?;
 sqlx::query("DELETE FROM device_push_tokens WHERE user_id=$1 AND kind='liveActivity' AND activity_id=$2")
  .bind(i.user).bind(&v.activity_id).execute(&mut *tx).await?;
 tx.commit().await?;
 Ok(envelope(json!({"ok":true})))
}

#[cfg(test)]
mod tests {
 use super::*;
 use crate::alerts::Point;

 fn line(points:&[(f64,f64)],left:bool,right:bool)->Line {
  Line{points:points.iter().map(|(t,p)|Point{t:*t,p:*p}).collect(),extend_left:left,extend_right:right}
 }
 fn registration(activity:Option<&str>,alert:Option<&str>)->Registration {
  Registration{device:Uuid::nil(),token:"a".repeat(64),environment:"production".into(),
   activity_id:activity.map(str::to_string),alert_id:alert.map(str::to_string),age:0.0}
 }

 /// 心跳推的就是契约里那七个键，一个不多一个不少，名字一个字都不能变——客户端的
 /// `ContentState` 是按这七个键解的。
 #[test] fn a_heartbeat_carries_the_seven_agreed_keys() {
  let state=content_state(Some(63_120.5),Some(-0.0123),Some(62_800.0),None,1_758_499_990_000);
  let map=state.as_object().expect("an object");
  let mut keys:Vec<&str>=map.keys().map(String::as_str).collect();keys.sort_unstable();
  assert_eq!(keys,vec!["change","distance","firedAt","line","price","state","updatedAt"]);
  assert_eq!(state["price"],json!(63_120.5));
  assert_eq!(state["change"],json!(-0.0123));
  assert_eq!(state["line"],json!(62_800.0));
  assert_eq!(state["state"],json!("watching"));
  assert_eq!(state["firedAt"],Value::Null);
  assert_eq!(state["updatedAt"],json!(1_758_499_990_000i64));
  // 距离是相对的：(63120.5-62800)/62800。
  let d=state["distance"].as_f64().expect("a number");
  assert!((d-0.005_103_5).abs()<1e-6,"{d}");
 }
 /// **取不到就是 `null`，而且那个键仍旧在。** 拿 0 或者上一拍的旧值冒充，锁屏上看起来
 /// 和新鲜数据一模一样——那正是这条链路最该避免的事。
 #[test] fn a_value_we_do_not_have_is_null_and_still_present() {
  let state=content_state(None,None,None,None,7);
  for key in ["price","change","line","distance"] {
   assert_eq!(state[key],Value::Null,"{key} 取不到就该是 null");
   assert!(state.get(key).is_some(),"{key} 这个键不能缺席");
  }
  assert_eq!(state["state"],json!("watching"));
  // 只有价没有线：距离算不出来，价照常发。
  let half=content_state(Some(100.0),None,None,None,7);
  assert_eq!(half["price"],json!(100.0));
  assert_eq!(half["distance"],Value::Null);
  // NaN / inf 一样当成取不到。
  let broken=content_state(Some(f64::NAN),Some(f64::INFINITY),Some(0.0),None,7);
  assert_eq!(broken["price"],Value::Null);
  assert_eq!(broken["change"],Value::Null);
  assert_eq!(broken["distance"],Value::Null,"线价为零时距离没有意义");
 }
 /// 响了那一下：state 变 fired、firedAt 有值，另带一个 firedPrice。
 #[test] fn the_firing_state_says_fired_and_keeps_the_price() {
  let state=fired_state(Some(63_000.0),Some(0.01),Some(63_000.0),1_758_499_990_000,1_758_499_995_000);
  assert_eq!(state["state"],json!("fired"));
  assert_eq!(state["firedAt"],json!(1_758_499_990_000i64));
  assert_eq!(state["updatedAt"],json!(1_758_499_995_000i64),"响的那一刻和这一拍算出来的时刻是两个数");
  assert_eq!(state["firedPrice"],json!(63_000.0));
  assert_eq!(state["distance"],json!(0.0));
 }
 /// **`stale-date` 是此刻 + 150 秒**，心跳周期的 2.5 倍。漏收两拍锁屏就写「价格已停更」，
 /// 而不是继续展示一个冻住的数字。往长里调等于把过期价格当成现价给用户看。
 #[test] fn the_stale_date_is_one_hundred_and_fifty_seconds_out() {
  assert_eq!(STALE_AFTER.as_secs(),150);
  assert_eq!(HEARTBEAT.as_secs(),60);
  assert_eq!(STALE_AFTER.as_secs(),HEARTBEAT.as_secs()*5/2);
  assert_eq!(stale_date(1_758_499_990),1_758_500_140);
  assert_eq!(stale_date(0),150);
 }
 /// 锁屏上只有一个数的位置：一组线里取离现价最近的那一条，而且按此刻重算（斜线会走）。
 #[test] fn the_line_shown_is_the_nearest_one_at_this_moment() {
  let lines=vec![line(&[(0.0,100.0),(100.0,200.0)],false,true),line(&[(0.0,300.0)],true,true)];
  assert_eq!(line_price(&lines,Some(190.0),100),Some(200.0));
  assert_eq!(line_price(&lines,Some(280.0),100),Some(300.0));
  // 同一条斜线，时刻不同价就不同。
  assert_eq!(line_price(&lines,Some(140.0),50),Some(150.0));
  // 没有现价时退回第一条有值的线，而不是什么都不给。
  assert_eq!(line_price(&lines,None,50),Some(150.0));
  // 一条都不覆盖此刻（线段之外、不延伸）就是取不到。
  let closed=vec![line(&[(0.0,100.0),(100.0,200.0)],false,false)];
  assert_eq!(line_price(&closed,Some(190.0),500),None);
  assert_eq!(line_price(&[],Some(190.0),50),None);
 }
 /// **只推 alert_id 对得上的那一行。** 同一个人另一条提醒开着的活动不该被这一下推成
 /// fired；没有活动 id 的纯 token 行（`alerts` kind 的那一行也长这样）一概不推。
 #[test] fn only_the_activity_registered_for_this_alert_is_pushed() {
  let mine=registration(Some("ACT-1"),Some("binance/usd_m/BTCUSDT/9F1E"));
  let other=registration(Some("ACT-2"),Some("binance/usd_m/ETHUSDT/AAAA"));
  let bare=registration(None,Some("binance/usd_m/BTCUSDT/9F1E"));
  let unbound=registration(Some("ACT-3"),None);
  let rows=vec![mine.clone(),other,bare,unbound];
  let picked=targets(&rows,"binance/usd_m/BTCUSDT/9F1E");
  assert_eq!(picked,vec![&mine],"别人的活动、没有活动 id 的行、没绑提醒的行都不推");
  assert!(targets(&rows,"binance/usd_m/BTCUSDT/0000").is_empty());
 }
 /// **满八小时一律 end + 清行**，哪怕提醒还活着。
 #[test] fn an_activity_ends_after_eight_hours_and_its_row_goes_with_it() {
  assert_eq!(LIFETIME.as_secs(),8*60*60);
  assert_eq!(next_step(true,7.9*3600.0,Some("active"),None),Step::Update);
  assert_eq!(next_step(true,8.0*3600.0,Some("active"),None),Step::End(None));
  assert_eq!(next_step(true,9.0*3600.0,Some("active"),None),Step::End(None));
  // end 之后那一行一定不留——推成功、推失败、根本没推，都一样。
  for delivery in [Delivery::Delivered,Delivery::Failed,Delivery::Skipped,Delivery::Gone] {
   assert!(drops_the_row(Event::End,delivery),"{delivery:?}：结束了就不该留着这一行");
  }
 }
 /// 提醒没了 / 不是 active 了，活动跟着结束；响过的那一下带上 firedAt。
 #[test] fn an_alert_that_is_gone_or_fired_ends_its_activity() {
  assert_eq!(next_step(true,10.0,None,None),Step::End(None),"提醒被删了");
  assert_eq!(next_step(true,10.0,Some("fired"),Some(1_758_499_990_000)),Step::End(Some(1_758_499_990_000)));
  assert_eq!(next_step(true,10.0,Some("paused"),None),Step::End(None));
  assert_eq!(next_step(true,10.0,Some("active"),None),Step::Update);
  // 没有活动 id 的行不是活动：既不推也不删。
  assert_eq!(next_step(false,10.0,Some("active"),None),Step::Idle);
  assert_eq!(next_step(false,99_999.0,None,None),Step::Idle);
 }
 /// **没有密钥时链路的其余部分照常走完。** 发信那一句被跳过，返回的是 `Skipped` 而不是
 /// 失败：结束一个活动照样把那一行清掉，心跳照样算完这一拍、不重试、不报错。
 #[tokio::test] async fn without_a_key_everything_but_the_push_still_happens() {
  let state=content_state(Some(63_120.5),None,Some(62_800.0),None,1);
  assert_eq!(deliver(None,&"a".repeat(64),"production",&state,Event::Update,1_758_499_990).await,Delivery::Skipped);
  assert_eq!(deliver(None,&"a".repeat(64),"production",&state,Event::End,1_758_499_990).await,Delivery::Skipped);
  // 没推出去也要把结束了的那一行清掉；心跳这一拍则把它留到下一拍。
  assert!(drops_the_row(Event::End,Delivery::Skipped));
  assert!(!drops_the_row(Event::Update,Delivery::Skipped));
 }
 /// **`Gone` 时那一行被删。** 苹果说这枚 token 不在了（app 卸了、活动早就结束了），
 /// 留着它每一拍都要多跑一次往返，而且苹果会把持续推死 token 的 provider 记一笔。
 /// 推不出去（网络、5xx）则不删——下一拍还要用。
 #[test] fn a_token_apple_says_is_gone_is_dropped() {
  assert!(drops_the_row(Event::Update,Delivery::Gone));
  assert!(!drops_the_row(Event::Update,Delivery::Delivered));
  assert!(!drops_the_row(Event::Update,Delivery::Failed));
 }
 /// 距离是相对的，方向有意义：现价在线上方为正。
 #[test] fn the_distance_is_relative_and_signed() {
  assert_eq!(distance(Some(110.0),Some(100.0)),Some(0.1));
  assert_eq!(distance(Some(90.0),Some(100.0)),Some(-0.1));
  assert_eq!(distance(Some(100.0),Some(100.0)),Some(0.0));
  assert_eq!(distance(None,Some(100.0)),None);
  assert_eq!(distance(Some(100.0),None),None);
  assert_eq!(distance(Some(100.0),Some(0.0)),None);
 }
 /// 事件名是契约里那两个字符串，客户端按它分「更新」和「结束」。
 #[test] fn the_two_events_are_update_and_end() {
  assert_eq!(Event::Update.name(),"update");
  assert_eq!(Event::End.name(),"end");
 }
}
