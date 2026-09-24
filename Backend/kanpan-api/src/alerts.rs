//! 提醒的服务端那一半：几何、物化表、评估器、推送 token 端点。
//!
//! 分工是这样的：**客户端负责把一条画线摊平成若干条价格折线**（`AlertGeometry`），
//! 服务端只认 `[{points:[{t,p}],extendLeft,extendRight}]` 这一种形状，在时间上做线性
//! 插值与外推。所以这里没有一行代码知道什么是斐波那契、什么是平行通道——新加一把画线
//! 工具不需要动服务端，这正是把几何放在客户端算的理由。
//!
//! 评估器跑在 `kanpan-worker` 里（`main.rs` 的 worker 分支）。它订阅币安 1m K 线，
//! 每一帧对该品种的活动提醒算一次，`condition` 决定怎么算——两种判法和客户端
//! `KanpanCore/Sources/KanpanCore/Alerts/AlertEvaluator.swift` 里那份规则一字对一字：
//!
//! - `touch`：K 线开盘时间 `t ≥ armedAt` 的那根，若某条折线在 `t` 处的价落在
//!   `[low, high]` 里就算触碰。盘中帧也算。
//! - `close`（收盘穿过）：只在**这一根真的收了**的那一帧上判（币安 kline 帧里的
//!   `k.x == true`），拿「上一根已收盘的收盘价」和「这一根的收盘价」跟线在 `t` 处的
//!   价比，两者分在线的两侧（正好收在线上也算穿过）才算。盘中来回穿一概不算。
//!
//! 触发后**在同一个事务里**把物化表置 fired 并往这个人的同步日志写一条 op，然后才推送。
//!
//! 读流判定与写库、推送分成两半并排跑（`Effect`）：读循环里不 await 任何数据库事务和
//! APNs 往返；断线重连后先从 REST 把缺口里收掉的 1 分钟 K 线补回来再读流（`backfill`）。
use crate::{AppState,apns::{Apns,Outcome},auth::Identity,envelope,error::{ApiError,Result},live_activity::Quote,sync::Object};
use axum::{Router,Json,extract::State,routing::post};
use futures_util::StreamExt;
use serde::Deserialize;
use serde_json::{Value,json};
use sqlx::Row;
use std::collections::BTreeMap;
use std::time::Duration;
use uuid::Uuid;

// ——————————————————————————— 几何 ———————————————————————————

/// 折线上的一个点：`t` 毫秒、`p` 价格。
#[derive(Deserialize,Clone,Copy,Debug,PartialEq)]
pub struct Point {pub t:f64,pub p:f64}
/// 一条摊平出来的价格折线。`extendLeft/Right` 是「这条线在图上往那一侧无限延伸吗」，
/// 由客户端按各把工具的实际画法给（射线只延伸一侧，延长线两侧都延伸，线段都不延伸）。
#[derive(Deserialize,Clone,Debug)]
#[serde(rename_all="camelCase")]
pub struct Line {pub points:Vec<Point>,#[serde(default)] pub extend_left:bool,#[serde(default)] pub extend_right:bool}

/// 这条折线在时刻 `t` 处的价；线不覆盖这个时刻就是 `None`。
///
/// 三种情况分开写，因为它们的错法各不一样：
/// - **在两点之间**：线性插值。两点同时刻（竖直段）时不除以零，取左端那个价。
/// - **越过某一端**：那一侧标了延伸才外推，用最靠边的两点定斜率；没标就是 `None`
///   ——「不延伸的一侧超出即不评估」是方案文档 2.4 的原话，也是唯一正确的做法：
///   一条画到昨天为止的线段，今天的价格穿过它的**延长线**并不是穿过那条线。
/// - **只有一个点**：摊平出来的水平线。此刻之外要看该侧是否延伸，价恒为那个点的价。
pub fn price_at(line:&Line,t:i64)->Option<f64> {
 let ps=&line.points;
 // 点在物化（`materialize`）和读进内存（`load`）时都已经按时间排好，这里通常一步都
 // 不用排：评估器每来一帧、每条提醒都要走这里，原来那一次 clone + sort 就是白白的
 // 分配。仍然留着乱序的兜底——客户端理应按时间递增给点，但「理应」不是保证，一条乱序
 // 的折线会让区间查找找不到任何一段，提醒就此变成哑的、而且没有任何迹象。
 if ps.is_sorted_by(|a,b|a.t<=b.t) {return on_sorted(line,ps,t)}
 let mut sorted:Vec<Point>=ps.clone();
 sort_points(&mut sorted);
 on_sorted(line,&sorted,t)
}
/// 按时间把点排好（稳定排序；NaN 之类比不出大小的原地不动）。物化、读库、兜底共用。
fn sort_points(points:&mut [Point]) {
 points.sort_by(|a,b|a.t.partial_cmp(&b.t).unwrap_or(std::cmp::Ordering::Equal));
}
/// 三种情况分开写，理由见 [`price_at`]。`sorted` 必须已经按时间递增。
fn on_sorted(line:&Line,sorted:&[Point],t:i64)->Option<f64> {
 let t=t as f64;
 let (first,last)=(*sorted.first()?,*sorted.last()?);
 if t<first.t {
  if !line.extend_left {return None}
  return Some(extrapolate(sorted,t,true))
 }
 if t>last.t {
  if !line.extend_right {return None}
  return Some(extrapolate(sorted,t,false))
 }
 for w in sorted.windows(2) {
  let (a,b)=(w[0],w[1]);
  if t>=a.t&&t<=b.t {
   if b.t<=a.t {return Some(a.p)}
   return Some(a.p+(b.p-a.p)*(t-a.t)/(b.t-a.t))
  }
 }
 Some(first.p)
}
/// 把 `alerts` 同步对象里的 `lines` 按时间排好点再落库（评估器的快路径靠它）。
/// 形状不认识的部分原样放过：白名单那一层已经挡过，这里不当第二道校验。
fn sorted_lines(mut lines:Value)->Value {
 for line in lines.as_array_mut().into_iter().flatten() {
  let Some(points)=line.get_mut("points").and_then(Value::as_array_mut) else {continue};
  let t=|v:&Value|v.get("t").and_then(Value::as_f64).unwrap_or(f64::NAN);
  points.sort_by(|a,b|t(a).partial_cmp(&t(b)).unwrap_or(std::cmp::Ordering::Equal));
 }
 lines
}
/// 越过端点之后的外推。只有一个点时是水平线（没有斜率可言）。
fn extrapolate(sorted:&[Point],t:f64,left:bool)->f64 {
 if sorted.len()<2 {return sorted[0].p}
 let (a,b)=if left {(sorted[0],sorted[1])} else {(sorted[sorted.len()-2],sorted[sorted.len()-1])};
 let edge=if left {a} else {b};
 if b.t<=a.t {return edge.p}
 edge.p+(b.p-a.p)*(t-edge.t)/(b.t-a.t)
}
/// 这根 K 线碰到这组折线里的任何一条了吗；碰到就返回被碰到的那条线在该时刻的价。
///
/// `armedAt` 之前开盘的 K 线一概不算：提醒创建的那一刻价格常常就贴在线上，不挡这一下
/// 的话每条新提醒都会立刻响。
pub fn touched(lines:&[Line],open_time:i64,armed_at:i64,low:f64,high:f64)->Option<f64> {
 if open_time<armed_at {return None}
 if !low.is_finite()||!high.is_finite() {return None}
 // 高低颠倒时先归一，和客户端 `AlertEvaluator.touchHit` 的 `min/max` 一字对一字——
 // 原来这里当坏帧返回 None，两端同一根 K 线会一个响、一个不响。
 let (low,high)=(low.min(high),low.max(high));
 lines.iter().filter_map(|l|price_at(l,open_time)).find(|p|p.is_finite()&&*p>=low&&*p<=high)
}

/// `condition='close'`（收盘穿过）：这一根收了之后，两根收盘价分在线的两侧了吗。
///
/// **阈值和 `touched` 取的是同一个值**——线在这一根 K 线开盘时刻上的价（趋势线的价随
/// 时间变，所以每一根都要重算）。换掉的只是拿去比的东西：`[low,high]` 换成「上一根已
/// 收盘的收盘价」和「这一根的收盘价」两个点。
///
/// 为什么非要两个点：只看当前收盘价在线的哪一侧，第一次评估就会把「一直在线上方」判成
/// 「刚刚穿上去」——那是一条在用户什么都没做的时候自己响的提醒。穿越要有前后两个状态
/// 才成立。
///
/// **正好收在线上算穿过**（`close == p`），但 `previous_close == p` 不算：上一根就已经
/// 收在线上了，那一下该由上一根去响；提醒是 `once` 的，在这儿再响一次就是重复。
///
/// 盘中帧不进这里（调用方按 `k.x` 挡掉）：穿过去又收回来正是用户选这一档想避开的。
pub fn crossed_on_close(lines:&[Line],open_time:i64,armed_at:i64,previous_close:f64,close:f64)->Option<f64> {
 if open_time<armed_at {return None}
 if !previous_close.is_finite()||!close.is_finite() {return None}
 lines.iter().filter_map(|l|price_at(l,open_time)).find(|p|p.is_finite()&&crosses(previous_close,close,*p))
}
fn crosses(previous:f64,close:f64,line:f64)->bool {
 (previous<line&&close>=line)||(previous>line&&close<=line)
}

// ——————————————————————— 物化（同步写入时顺手刷新） ———————————————————————

/// 把一条 `alerts` 同步对象刷进 `alert_watches`。由 `sync::push` 在同一个事务里调用。
///
/// 三种 kind 都物化（P3.1）：
///
/// - `drawing`：画线提醒，按摊平的折线判。
/// - `price`：裸价格「到价提醒」。客户端把目标价摊成一条两端都延伸的水平线放进
///   `lines`，所以评估器对它和画线提醒是**同一套**判法，不需要第二套几何。
/// - `reviewDue`：复盘到点。没有线，按 `due_at` 判；`review_id` 给推送的深链用。
///
/// 删除、认不得的 kind 一律把行删掉——评估器读的就是这张表，删掉就等于停评估，
/// 不需要第二处开关。暂停与已触发照样留着行（`status` 列挡住评估）。
///
/// 每次都整行覆盖，所以用户把被提醒的那条线拖到别处、客户端用同一个 alert id 重传
/// `lines` 时，`lines` 与 `armedAt` 是一起换掉的，评估器下一帧就用新几何。
pub async fn materialize(tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,owner:Uuid,object:&Object)->Result<()> {
 let keep=!object.deleted
  && matches!(object.body.get("kind").and_then(Value::as_str),Some("drawing"|"price"|"reviewDue"))
  && object.body.get("symbol").and_then(Value::as_str).is_some();
 if !keep {
  sqlx::query("DELETE FROM alert_watches WHERE user_id=$1 AND alert_id=$2").bind(owner).bind(&object.id).execute(&mut **tx).await?;
  return Ok(())
 }
 let text=|k:&str|object.body.get(k).and_then(Value::as_str).unwrap_or_default().to_string();
 let number=|k:&str|object.body.get(k).and_then(Value::as_f64);
 sqlx::query("INSERT INTO alert_watches(user_id,alert_id,kind,symbol,market,drawing_id,lines,condition,title,armed_at,status,fired_at,fired_price,due_at,review_id,\
  webhook,webhook_text,note,updated_at) \
  VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,now()) \
  ON CONFLICT(user_id,alert_id) DO UPDATE SET kind=excluded.kind,symbol=excluded.symbol,market=excluded.market,drawing_id=excluded.drawing_id,\
  lines=excluded.lines,condition=excluded.condition,title=excluded.title,armed_at=excluded.armed_at,status=excluded.status,\
  fired_at=excluded.fired_at,fired_price=excluded.fired_price,due_at=excluded.due_at,review_id=excluded.review_id,\
  webhook=excluded.webhook,webhook_text=excluded.webhook_text,note=excluded.note,updated_at=now()")
  .bind(owner).bind(&object.id).bind(text("kind")).bind(text("symbol"))
  .bind(object.body.get("market").and_then(Value::as_str).unwrap_or(BINANCE))
  .bind(object.body.get("drawingID").and_then(Value::as_str))
  .bind(sorted_lines(object.body.get("lines").cloned().unwrap_or_else(||json!([]))))
  .bind(object.body.get("condition").and_then(Value::as_str).unwrap_or("touch"))
  .bind(text("title"))
  .bind(number("armedAt").unwrap_or_default() as i64)
  .bind(object.body.get("status").and_then(Value::as_str).unwrap_or("active"))
  .bind(number("firedAt").map(|v|v as i64))
  .bind(number("firedPrice"))
  .bind(number("dueAt").map(|v|v as i64))
  .bind(object.body.get("reviewID").and_then(Value::as_str))
  // 空串和 null 一样当「没有」存成 NULL，评估器只需要看一种「没有」。
  .bind(optional_text(object,"webhook"))
  .bind(optional_text(object,"webhookText"))
  .bind(optional_text(object,"note"))
  .execute(&mut **tx).await?;
 Ok(())
}

/// 可空的文本字段：null、缺、空串都是 `None`。
fn optional_text<'a>(object:&'a Object,key:&str)->Option<&'a str> {
 object.body.get(key).and_then(Value::as_str).filter(|v|!v.is_empty())
}

// ——————————————————————— 推送 token 端点 ———————————————————————

#[derive(Deserialize)]
#[serde(rename_all="camelCase",deny_unknown_fields)]
struct TokenBody {token:String,kind:String,environment:String,#[serde(default)] activity_id:Option<String>,#[serde(default)] alert_id:Option<String>}

pub fn routes()->Router<AppState> {
 Router::new().route("/v1/devices/push-token",post(push_token))
}
/// `POST /v1/devices/push-token`：把这台设备的 APNs token 记下来。
///
/// 设备身份不由客户端自称：从会话反查 `account_sessions.device_id`，和 `sync::push`
/// 认设备用的是同一条语句。一台设备同一个 kind 只留一行，重复注册就是覆盖
/// （token 会在重装、还原、系统更新之后变）。
///
/// `kind="liveActivity"` 这一种**必须同时带 `activityId` 与 `alertId`**：实时活动的
/// 推送 token 是一个活动一枚（ActivityKit 给的），而它存在的全部意义就是盯着某一条提醒。
/// 缺哪一个都让这一行变成推不出去、也结束不掉的孤儿，所以在门口就拒掉——一个静悄悄
/// 不更新的锁屏活动是查不出来的那种 bug。
async fn push_token(State(s):State<AppState>,i:Identity,Json(v):Json<TokenBody>)->Result<Json<Value>> {
 if !matches!(v.kind.as_str(),"alerts"|"liveActivity"|"widget"|"reviewDue") {return Err(ApiError::bad("invalid_token_kind"))}
 if !matches!(v.environment.as_str(),"production"|"sandbox") {return Err(ApiError::bad("invalid_token_environment"))}
 // APNs 的设备 token 是 32 字节的十六进制（64 个字符），但历史上长过、苹果也说过还会变，
 // 所以卡的是「十六进制、长度在一个合理的区间里」而不是等于 64。
 if v.token.len()<32||v.token.len()>200||!v.token.bytes().all(|c|c.is_ascii_hexdigit()) {return Err(ApiError::bad("invalid_token"))}
 let activity=v.activity_id.as_deref().map(str::trim).filter(|a|!a.is_empty());
 let alert=v.alert_id.as_deref().map(str::trim).filter(|a|!a.is_empty());
 if activity.is_some_and(|a|a.len()>200) {return Err(ApiError::bad("invalid_activity"))}
 if alert.is_some_and(|a|a.len()>200) {return Err(ApiError::bad("invalid_alert"))}
 if v.kind=="liveActivity" {
  if activity.is_none() {return Err(ApiError::bad("invalid_activity"))}
  if alert.is_none() {return Err(ApiError::bad("invalid_alert"))}
 }
 let mut tx=s.personal(i.user).await?;
 let device:Uuid=sqlx::query_scalar("SELECT device_id FROM account_sessions WHERE id=$1 AND user_id=$2 AND revoked_at IS NULL")
  .bind(i.session).bind(i.user).fetch_optional(&mut *tx).await?.ok_or_else(ApiError::unauthorized)?;
 // `started_at` 只在活动**换了一个**的时候重新计时：token 会在活动进行中轮换
 // （ActivityKit 的 pushTokenUpdates），那一下不该把八小时的钟拨回零。
 sqlx::query("INSERT INTO device_push_tokens(user_id,device_id,kind,environment,token,activity_id,alert_id,started_at,updated_at) VALUES($1,$2,$3,$4,$5,$6,$7,now(),now()) \
  ON CONFLICT(user_id,device_id,kind) DO UPDATE SET environment=excluded.environment,token=excluded.token,activity_id=excluded.activity_id,alert_id=excluded.alert_id,\
  started_at=CASE WHEN device_push_tokens.activity_id IS DISTINCT FROM excluded.activity_id THEN now() ELSE COALESCE(device_push_tokens.started_at,now()) END,updated_at=now()")
  .bind(i.user).bind(device).bind(&v.kind).bind(&v.environment).bind(&v.token).bind(activity).bind(alert)
  .execute(&mut *tx).await?;
 tx.commit().await?;
 Ok(envelope(json!({"ok":true})))
}

// ——————————————————————— 评估器 ———————————————————————

/// 币安 USDⓈ-M 合约的组合流。
///
/// **路径是量出来的，不是抄文档的。** `/stream?streams=…` 在这台 VPS 上握手回
/// `101 Switching Protocols` 然后一帧都不发（Mac 上同样），`/market/stream?streams=…`
/// 秒出帧——后者正是 `Backend/kanpan-gateway/stream_hub.py` 一直在用的那条。
/// 改这一行之前先在 VPS 上实测，别信握手成功。
const STREAM:&str="wss://fstream.binance.com/market/stream";
/// 币安对组合流的上限是 200 条/连接。十来个用户远够不着，够不着也要有个说法。
const MAX_STREAMS:usize=200;

/// 怎么算「穿过」。和客户端 `Alert.Condition` 一一对应的两档。
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum Condition {Touch,Close}
impl Condition {
 /// 库里存的是字符串。**认不得的值退回 `touch`**（出厂值），和客户端解码器的兜底
 /// 一样——一条来自更新版本客户端的提醒，宁可按最宽的那一档判，也不要变成哑的。
 pub fn of(text:&str)->Self {if text=="close" {Self::Close} else {Self::Touch}}
}

/// `alert_watches.market` 的两个取值（客户端 `InstrumentID.marketKey`）。币安那一个就是
/// 裸代号的默认交易所（`instruments::DEFAULT_MARKET_KEY`），缺 `market` 的老提醒按它记。
pub const BINANCE:&str=crate::instruments::DEFAULT_MARKET_KEY;
pub const COINBASE:&str="coinbase/spot";

/// 评估器在内存里保有的一条活动提醒。
#[derive(Clone,Debug)]
struct Watch {
 owner:Uuid,alert_id:String,symbol:String,drawing_id:Option<String>,
 title:String,lines:Vec<Line>,armed_at:i64,condition:Condition,
 /// `binance/usd_m` 或 `coinbase/spot`：决定这条提醒由哪一条行情流来评估。
 market:String,
 /// 响了往这里 POST 一份 JSON（见 [`webhook_body`]）。
 webhook:Option<String>,
 /// Webhook 里 `text` 的模板；空用 [`DEFAULT_WEBHOOK_TEXT`]。
 webhook_text:Option<String>,
 /// 用户写的备注：APNs 正文与 Webhook 都带上。
 note:Option<String>,
}

/// 一条还没到点的复盘到点提醒。它不看价，不进 K 线流，只在每轮刷新时看一眼钟。
#[derive(Clone,Debug)]
struct Due {owner:Uuid,alert_id:String,symbol:String,review_id:String,title:String,due_at:i64}

/// `binance/usd_m` → `binance`（自选同步对象里交易所和市场是分开的两个字段）。
fn venue_of(market:&str)->&str {market.split('/').next().unwrap_or(market)}

/// 一轮刷新读回来的东西：所有人的活动价格提醒（画线 + 裸价格）、已经到点的复盘提醒、
/// 自选波动提醒开着的人，以及其中哪些品种正被实时活动盯着。
struct Loaded {watches:Vec<Watch>,due:Vec<Due>,movers:Vec<crate::watch_move::Mover>,live:Vec<String>}

/// 把所有用户的活动提醒读成一张内存表。
///
/// 为什么逐个用户开事务：这两张表和同步表一样挂着 FORCE ROW LEVEL SECURITY，运行期角色
/// 既不是属主也没有 BYPASSRLS，所以**没有**一条能一次看见所有人的通道——这是故意的。
/// 代价是一次刷新 N 个短事务，而 N 是个位数（`maintenance::cleanup` 用的同一套分页）。
async fn load(s:&AppState,market:&str)->Result<Loaded> {
 let mut out=vec![];
 let mut due=vec![];
 let mut movers=vec![];
 let mut live=vec![];
 let mut after:Option<Uuid>=None;
 loop {
  let owners:Vec<Uuid>=sqlx::query_scalar("SELECT id FROM account_users WHERE disabled_at IS NULL AND ($1::uuid IS NULL OR id>$1) ORDER BY id LIMIT 100").bind(after).fetch_all(&s.pool).await?;
  if owners.is_empty(){break}
  for owner in &owners {
   let mut tx=match s.personal(*owner).await {Ok(tx)=>tx,Err(_)=>continue};
   // `price` 和 `drawing` 同一种形状（`lines`），一起读。
   let rows=sqlx::query("SELECT alert_id,symbol,drawing_id,title,lines,armed_at,condition,market,webhook,webhook_text,note FROM alert_watches WHERE user_id=$1 AND status='active' AND kind IN ('drawing','price') AND market=$2")
    .bind(owner).bind(market).fetch_all(&mut *tx).await?;
   // 复盘到点只读**已经到点**的那几条：没到点的留在库里，下一轮再看，不占内存。
   // 它不看价、不分交易所，只在币安那一支里判一次（两支都判会各推一遍）。
   let now=chrono::Utc::now().timestamp_millis();
   if market==BINANCE {for r in sqlx::query("SELECT alert_id,symbol,title,due_at,review_id FROM alert_watches WHERE user_id=$1 AND status='active' AND kind='reviewDue' AND due_at IS NOT NULL AND due_at<=$2")
    .bind(owner).bind(now).fetch_all(&mut *tx).await? {
    let review_id:Option<String>=r.get("review_id");
    due.push(Due{owner:*owner,alert_id:r.get("alert_id"),symbol:r.get("symbol"),review_id:review_id.unwrap_or_default(),
     title:r.get("title"),due_at:r.get::<Option<i64>,_>("due_at").unwrap_or(now)});
   }}
   // 自选波动：每一支只读这家交易所的自选（币安的组合流订不了别家的代号）。
   if let Some(mover)=crate::watch_move::load_mover(&mut tx,*owner,venue_of(market)).await.unwrap_or(None) {movers.push(mover)}
   // 同一个事务里顺手问一句「这个人有实时活动盯着哪些品种」：那些品种要多订一条
   // `@ticker`（24h 涨跌幅只有那条流里有）。没有活动的时候这一句什么都不返回，
   // 订阅串和从前一模一样。
   if market==BINANCE {live.extend(crate::live_activity::active_symbols(&mut tx,*owner).await.unwrap_or_default());}
   tx.commit().await?;
   for r in rows {
    let mut lines:Vec<Line>=match serde_json::from_value(r.get::<Value,_>("lines")) {
     Ok(v)=>v,
     // 形状对不上就当这条提醒不存在，而不是让整轮刷新失败——一条坏数据不该让所有人
     // 的提醒一起停摆。白名单那一层已经挡过一次，真走到这里说明有别的路写进去了。
     Err(e)=>{tracing::warn!("An alert has unusable geometry and will not be evaluated: {e}");continue}
    };
    // 物化时已经排过；这一步给「排序上线之前写进去的老行」兜底，一次读库排一次，
    // 之后每一帧都走 `price_at` 的快路径。
    for line in &mut lines {sort_points(&mut line.points)}
    out.push(Watch{owner:*owner,alert_id:r.get("alert_id"),symbol:r.get("symbol"),
     drawing_id:r.get("drawing_id"),title:r.get("title"),lines,armed_at:r.get("armed_at"),
     condition:Condition::of(&r.get::<String,_>("condition")),market:r.get("market"),
     webhook:r.get("webhook"),webhook_text:r.get("webhook_text"),note:r.get("note")});
   }
  }
  after=owners.last().copied();
 }
 live.sort();live.dedup();
 Ok(Loaded{watches:out,due,movers,live})
}

/// 触发：物化表置 fired + 往同步日志写一条 op，**同一个事务**。返回「这一下真的是我触发的」。
///
/// 「同一条提醒只触发一次」靠的不是内存里的标记，是那条 `WHERE status='active'`：
/// 客户端前台的 `AlertWatcher` 可能先一步把它置成 fired 并同步上来，那时这条 UPDATE
/// 一行都改不到，函数直接返回、不写 op、也不推。反过来如果是服务端先到，客户端拉到的
/// 就是服务端写的那条 op。两边谁先都对，而且不会推两次。
///
/// 拿锁的顺序和 `sync::push` 一致（先 advisory、后行锁），否则 worker 和 API 会以相反的
/// 顺序拿同两把锁——那是教科书上的死锁。
///
/// 返回 `false` 的两种情形都不该推送：已经是 fired（客户端前台先到了），
/// 或者这条提醒的同步对象已经被删了。
///
/// `price` 是 `None` 的只有复盘到点那一种：它不看价，`firedPrice` 就不写，不拿 0 冒充。
pub async fn record_fired(s:&AppState,owner:Uuid,alert_id:&str,price:Option<f64>,at:i64)->Result<bool> {
 let mut tx=s.personal(owner).await?;
 crate::sync::lock(&mut tx,owner).await?;
 let changed=sqlx::query("UPDATE alert_watches SET status='fired',fired_at=$3,fired_price=$4,updated_at=now() WHERE user_id=$1 AND alert_id=$2 AND status='active'")
  .bind(owner).bind(alert_id).bind(at).bind(price).execute(&mut *tx).await?.rows_affected();
 if changed==0 {tx.commit().await?;return Ok(false)}
 // 同步对象没了（用户在别的设备上删了这条提醒，而这一轮的内存快照还没刷新）：
 // 把物化表那一行一起清掉就好，不要拿一条不存在的对象去写 op。
 let present=crate::sync::read_object(&mut tx,owner,crate::sync::ALERTS,alert_id).await?.is_some();
 if !present {
  sqlx::query("DELETE FROM alert_watches WHERE user_id=$1 AND alert_id=$2").bind(owner).bind(alert_id).execute(&mut *tx).await?;
  tx.commit().await?;return Ok(false)
 }
 let mut fields:BTreeMap<String,Value>=[("status",json!("fired")),("firedAt",json!(at))]
  .into_iter().map(|(k,v)|(k.to_string(),v)).collect();
 if let Some(price)=price {fields.insert("firedPrice".into(),json!(price));}
 crate::sync::apply_server_op(&mut tx,owner,crate::sync::ALERTS,alert_id,fields).await?;
 tx.commit().await?;
 Ok(true)
}
/// 触发之后把通知推给这个人所有注册过的设备。
///
/// 推送**在事务之外**做：HTTP/2 一个往返几百毫秒，握着这个人的同步闸等苹果回话，
/// 等于把他所有设备的同步一起挂在那儿。
async fn fire(s:&AppState,apns:Option<&Apns>,w:&Watch,quote:Quote,price:f64,at:i64)->Result<()> {
 if !record_fired(s,w.owner,&w.alert_id,Some(price),at).await? {return Ok(())}
 // 锁屏上那一块要当场收掉：event=end、state=fired。这一句排在下面「没有密钥就 return」
 // 的**前面**是故意的——没有密钥时它照样把活动登记那一行清干净，少的只是发信那一下。
 // 推不出去不算触发失败：提醒已经落库、已经进同步日志了。
 let line=crate::live_activity::line_price(&w.lines,Some(price),at);
 let quote=Quote{price:Some(price),change:quote.change};
 if let Err(e)=crate::live_activity::end_fired(s,apns,w.owner,&w.alert_id,quote,line,at).await {
  tracing::warn!("An alert fired but its live activity could not be ended ({e:?})");
 }
 // Webhook 在事务之外、「没有 APNs 就 return」之前：线上现在没有 APNs 密钥，排在后面
 // 就一条都发不出去。另起一个任务去发——最坏要 8 秒 + 3 秒 + 8 秒，不能让这一条的
 // 对面慢吞吞地把后面所有提醒的落库和推送一起挂住。发不出去只留日志，不回滚状态。
 if let Some(url)=w.webhook.as_deref().filter(|u|!u.is_empty()) {
  if webhook_allowed(url) {
   let (url,body,alert_id)=(url.to_string(),webhook_body(w,price,at),w.alert_id.clone());
   tokio::spawn(async move {
    if let Err(e)=deliver_webhook(crate::http::shared(),&url,&body,WEBHOOK_RETRY).await {
     tracing::warn!("Alert {alert_id} fired but its webhook to {} failed: {e}",webhook_host(&url));
    }
   });
  } else {
   tracing::warn!("Alert {} has a webhook to a local or private address ({}); not posting",w.alert_id,webhook_host(url));
  }
 }
 let Some(apns)=apns else {
  // 没有 APNs 密钥时这就是终点，而且是一个完整的终点：状态已经落库、op 已经写进
  // alerts 集合，客户端下次拉同步（开 app 就会拉）照样看得到这条已触发的提醒。
  // 这里只留一行 info 当证据，不排队、不重试——没有密钥不是一个会自己好起来的错误。
  tracing::info!("{} triggered {} at {}; recorded and synced, not pushed (no APNs key)",w.symbol,w.alert_id,money(price));
  return Ok(())
 };
 notify(s,apns,w.owner,&Notice{title:title_of(w),body:alert_body(price,w.note.as_deref()),link:link_of(w),kind:"alert"}).await
}

/// 通知标题：用户（客户端）起的标题；没有就「BTCUSDT 触到你画的线」。Webhook 的 `title` 同一个。
fn title_of(w:&Watch)->String {
 if w.title.is_empty() {format!("{} 触到你画的线",display_symbol(&w.market,&w.symbol))} else {w.title.clone()}
}
/// APNs 正文：「现价 84,671」；有备注就接在后面，「现价 84,671 · 突破就加仓」。
fn alert_body(price:f64,note:Option<&str>)->String {
 let body=format!("现价 {}",money(price));
 match note.map(str::trim).filter(|n|!n.is_empty()) {Some(note)=>format!("{body} · {note}"),None=>body}
}

// ——————————————————————————— Webhook ———————————————————————————

/// Webhook 单次请求的超时。
const WEBHOOK_TIMEOUT:Duration=Duration::from_secs(8);
/// 网络错误或 5xx 之后等多久重试（只重试一次）。
const WEBHOOK_RETRY:Duration=Duration::from_secs(3);
/// Webhook 请求的 UA：让接收方认得出是谁在发。
const WEBHOOK_UA:&str="Hkline-Alerts/1";
/// 用户没写模板时 `text` 用的模板。
pub const DEFAULT_WEBHOOK_TEXT:&str="{品种} {条件} {目标价}，现价 {价格}";

/// 渲染 Webhook 文案要的那几样东西。
pub struct WebhookFill<'a> {
 pub market:&'a str,pub symbol:&'a str,pub condition:Condition,
 pub target:Option<f64>,pub price:f64,pub at:i64,pub note:&'a str,
}

/// `{品种}`：币安去掉尾巴上的 `USDT`（`BTCUSDT` → `BTC`，没有这个尾巴就原样）；
/// Coinbase 把 `-` 换成 `/`（`BTC-USD` → `BTC/USD`）。
pub fn webhook_name(market:&str,symbol:&str)->String {
 if market==BINANCE {symbol.strip_suffix("USDT").filter(|b|!b.is_empty()).unwrap_or(symbol).to_string()} else {symbol.replace('-',"/")}
}
/// `{条件}`：`碰到` / `收盘穿过`。
fn condition_word(c:Condition)->&'static str {match c {Condition::Touch=>"碰到",Condition::Close=>"收盘穿过"}}
fn condition_key(c:Condition)->&'static str {match c {Condition::Touch=>"touch",Condition::Close=>"close"}}
/// `{时间}`：ISO 8601、UTC、到秒，`2026-09-24T16:44:00Z`。
pub fn iso_time(at:i64)->String {
 chrono::DateTime::from_timestamp_millis(at).map(|t|t.format("%Y-%m-%dT%H:%M:%SZ").to_string()).unwrap_or_default()
}
/// Webhook 里的价：千分位，小数照原样（最多 8 位、去掉尾巴上的 0）。
///
/// 不用 [`money`]：它按量级截小数（≥ 1000 不留小数），`84662.2` 会写成 `84,662`——
/// 目标价是用户自己填的，Webhook 里要和他填的一模一样。8 位是为了吃掉浮点尾巴
/// （`84662.20000000001` 仍写 `84,662.2`）。
pub fn webhook_money(v:f64)->String {
 if !v.is_finite() {return String::new()}
 let text=format!("{v:.8}");
 let text=text.trim_end_matches('0').trim_end_matches('.');
 let (sign,rest)=match text.strip_prefix('-') {Some(r) if r!="0"=>("-",r),Some(r)=>("",r),None=>("",text)};
 let (whole,fraction)=rest.split_once('.').map_or((rest,""),|(a,b)|(a,b));
 let mut grouped=String::new();
 for (i,c) in whole.chars().enumerate() {
  if i>0&&(whole.len()-i)%3==0 {grouped.push(',')}
  grouped.push(c);
 }
 if fraction.is_empty() {format!("{sign}{grouped}")} else {format!("{sign}{grouped}.{fraction}")}
}
/// 把模板里的占位符换成这一次的值。**一遍扫完**：备注里要是写了 `{价格}`，它就是字面的
/// `{价格}`，不会被第二轮替换再换一次。认不得的 `{…}` 原样留着。空模板用默认模板。
pub fn render_webhook_text(template:Option<&str>,f:&WebhookFill)->String {
 let template=template.filter(|t|!t.trim().is_empty()).unwrap_or(DEFAULT_WEBHOOK_TEXT);
 let value=|key:&str|->Option<String> {Some(match key {
  "品种"=>webhook_name(f.market,f.symbol),
  "代号"=>f.symbol.to_string(),
  "价格"=>webhook_money(f.price),
  "目标价"=>f.target.map(webhook_money).unwrap_or_default(),
  "条件"=>condition_word(f.condition).to_string(),
  "时间"=>iso_time(f.at),
  "备注"=>f.note.to_string(),
  _=>return None,
 })};
 let mut out=String::new();
 let mut rest=template;
 while let Some(start)=rest.find('{') {
  out.push_str(&rest[..start]);
  let tail=&rest[start..];
  let Some(end)=tail.find('}') else {rest=tail;break};
  match value(&tail[1..end]) {
   Some(v)=>{out.push_str(&v);rest=&tail[end+1..]}
   None=>{out.push('{');rest=&tail[1..]}
  }
 }
 out.push_str(rest);
 out
}
/// `{目标价}`：`lines` 第一条的第一个点的价（物化时已按时间排过）。
fn target_of(w:&Watch)->Option<f64> {w.lines.first().and_then(|l|l.points.first()).map(|p|p.p)}
/// POST 出去的那份 JSON。字段和客户端的字段契约一一对应；`once` 照契约写死 `true`
/// （提醒一律响一次就结束）。
fn webhook_body(w:&Watch,price:f64,at:i64)->Value {
 let note=w.note.as_deref().unwrap_or_default();
 let target=target_of(w);
 let text=render_webhook_text(w.webhook_text.as_deref(),&WebhookFill{market:&w.market,symbol:&w.symbol,condition:w.condition,target,price,at,note});
 json!({
  "event":"alert","alertId":w.alert_id,"symbol":w.symbol,"market":w.market,
  "name":webhook_name(&w.market,&w.symbol),"title":title_of(w),"condition":condition_key(w.condition),
  "once":true,"target":target,"price":price,"firedAt":at,"time":iso_time(at),"note":note,"text":text,
 })
}
/// 日志里只写主机名：Webhook 地址里常带着接收方的密钥（机器人 token 之类）。
fn webhook_host(url:&str)->String {
 reqwest::Url::parse(url).ok().and_then(|u|u.host_str().map(str::to_string)).unwrap_or_else(||"?".into())
}
/// 不往本机和内网发：这台 VPS 的 127.0.0.1 上跑着 API 本身和别的服务，一条填了
/// `http://127.0.0.1:8794/...` 的提醒不该能从服务端里面去敲它们。只挡字面上的
/// localhost 与内网 / 回环 / 链路本地地址；用户只有几个朋友，不为 DNS 重绑定再加一层。
fn webhook_allowed(url:&str)->bool {
 use std::net::IpAddr;
 let Ok(url)=reqwest::Url::parse(url) else {return false};
 if !matches!(url.scheme(),"http"|"https") {return false}
 let Some(host)=url.host_str() else {return false};
 let host=host.trim_start_matches('[').trim_end_matches(']').to_ascii_lowercase();
 if host=="localhost"||host.ends_with(".localhost") {return false}
 let v4_ok=|ip:std::net::Ipv4Addr|!(ip.is_loopback()||ip.is_private()||ip.is_link_local()||ip.is_unspecified()||ip.is_broadcast()||ip.octets()[0]==100&&(ip.octets()[1]&0xc0)==64);
 match host.parse::<IpAddr>() {
  Ok(IpAddr::V4(ip))=>v4_ok(ip),
  Ok(IpAddr::V6(ip))=>match ip.to_ipv4_mapped() {
   Some(v4)=>v4_ok(v4),
   None=>!(ip.is_loopback()||ip.is_unspecified()||(ip.segments()[0]&0xfe00)==0xfc00||(ip.segments()[0]&0xffc0)==0xfe80),
  },
  Err(_)=>true,
 }
}
/// POST 一次；网络错误或 5xx 等 `retry` 之后再试一次。4xx 是对面明确不收，不重试。
/// 返回最后一次失败的原因，给调用方留日志。
async fn deliver_webhook(client:&reqwest::Client,url:&str,body:&Value,retry:Duration)->std::result::Result<(),String> {
 use reqwest::header::{CONTENT_TYPE,USER_AGENT};
 let payload=body.to_string();
 let mut last=String::new();
 for attempt in 0..2 {
  if attempt>0 {tokio::time::sleep(retry).await}
  let sent=client.post(url).timeout(WEBHOOK_TIMEOUT)
   .header(CONTENT_TYPE,"application/json").header(USER_AGENT,WEBHOOK_UA)
   .body(payload.clone()).send().await;
  match sent {
   Ok(r) if r.status().is_success()=>return Ok(()),
   Ok(r) if r.status().is_server_error()=>last=format!("HTTP {}",r.status().as_u16()),
   Ok(r)=>return Err(format!("HTTP {}",r.status().as_u16())),
   // 错误文本里可能带着整条地址，只留类别。
   Err(e)=>last=if e.is_timeout() {"timed out".into()} else if e.is_connect() {"could not connect".into()} else {"request failed".into()},
  }
 }
 Err(last)
}

/// 一条推送的内容。`kind` 原样进 payload：客户端前台已经自己出过提示的那几种
/// （复盘到点、自选波动）靠它在 `willPresent` 里把横幅压掉，不让前台响两下。
pub struct Notice {pub title:String,pub body:String,pub link:String,pub kind:&'static str}

/// 画线提醒点开去那条线；裸价格提醒没有线，只开品种。
fn link_of(w:&Watch)->String {
 let symbol=symbol_path(&w.market,&w.symbol);
 match w.drawing_id.as_deref().filter(|d|!d.is_empty()) {
  Some(drawing)=>format!("hkline://drawing/{symbol}/{drawing}"),
  None=>format!("hkline://symbol/{symbol}"),
 }
}

/// 深链里的品种段。币安沿用老写法（裸代号，老客户端也认）；别家带上完整的
/// `venue/market/symbol`，不然客户端会把 `BTC-USD` 当成币安的品种去开。
pub fn symbol_path(market:&str,symbol:&str)->String {
 if market==BINANCE {symbol.to_string()} else {format!("{market}/{symbol}")}
}
/// 通知标题里的品种名：和界面上一样，Coinbase 写 `BTC/USD`。
pub fn display_symbol(market:&str,symbol:&str)->String {
 if market==BINANCE {symbol.to_string()} else {symbol.replace('-',"/")}
}

/// 这一种通知推给哪一类 token。
///
/// 复盘到点单独一类（迁移 0023）：客户端在「本地日历通知」和「服务端推送」两条通道里
/// 只选一条，选了推送才注册 `reviewDue` 的 token；推给 `alerts` 就会和本地那条撞成两条。
/// 老客户端只注册 `alerts`，所以它们收不到复盘到点的推送——它们本来就有本地那一条。
pub fn token_kind(notice_kind:&str)->&'static str {
 if notice_kind=="reviewDue" {"reviewDue"} else {"alerts"}
}

/// 把一条通知推给这个人所有注册过的设备。触发类（提醒、复盘到点、自选波动）共用。
pub async fn notify(s:&AppState,apns:&Apns,owner:Uuid,notice:&Notice)->Result<()> {
 let kind=token_kind(notice.kind);
 let (tokens,sound)={
  let mut tx=s.personal(owner).await?;
  let rows=sqlx::query("SELECT device_id,token,environment FROM device_push_tokens WHERE user_id=$1 AND kind=$2")
   .bind(owner).bind(kind).fetch_all(&mut *tx).await?;
  // 与 token 在同一个个人事务里读取；不缓存，用户改声后下一条提醒立即采用新值。
  let settings=crate::sync::settings_body(&mut tx,owner).await?;
  let sound=crate::apns::alert_sound(settings.as_ref());
  tx.commit().await?;(rows,sound)
 };
 for row in tokens {
  let token:String=row.get("token");
  let environment:String=row.get("environment");
  match apns.push_alert(&token,&environment,&notice.title,&notice.body,&notice.link,sound,notice.kind).await {
   Ok(Outcome::Delivered)=>{}
   Ok(Outcome::Gone)=>{
    let device:Uuid=row.get("device_id");
    let mut tx=s.personal(owner).await?;
    sqlx::query("DELETE FROM device_push_tokens WHERE user_id=$1 AND device_id=$2 AND kind=$3").bind(owner).bind(device).bind(kind).execute(&mut *tx).await?;
    tx.commit().await?;
   }
   // 推不出去不回滚状态：提醒确实触发了，客户端下次拉取照样看得到，
   // 少的只是那一下横幅。把状态跟着推送一起回滚才是真的丢事件。
   Err(_)=>tracing::warn!("An alert fired but could not be pushed"),
  }
 }
 Ok(())
}

/// 复盘到点：到了就置 fired、写同步 op、推送。和价格提醒走同一个 `record_fired`，
/// 所以「客户端前台先一步置了 fired」时这里同样一行都改不到、不会推第二次。
///
/// 推送只发给选了「服务端推送」通道的设备（`reviewDue` 类 token，见 `token_kind`）；
/// 走本地日历通知那条通道的设备（今天是全部）不注册它，所以这里只落账、同步，不重复叫人。
async fn settle_due(s:&AppState,apns:Option<&Apns>,due:&[Due]) {
 let at=chrono::Utc::now().timestamp_millis();
 for d in due {
  if d.due_at>at {continue}
  match record_fired(s,d.owner,&d.alert_id,None,at).await {
   Ok(true)=>{}
   Ok(false)=>continue,
   Err(e)=>{tracing::warn!("A review reminder could not be recorded as fired ({e:?}); the next refresh will retry");continue}
  }
  let Some(apns)=apns else {
   tracing::info!("{} review {} is due; recorded and synced, not pushed (no APNs key)",d.symbol,d.alert_id);
   continue
  };
  let notice=due_notice(d);
  if let Err(e)=notify(s,apns,d.owner,&notice).await {tracing::warn!("A review reminder was recorded but could not be pushed ({e:?})")}
 }
}
/// 复盘到点那条推送长什么样：和本地日历通知一字不差，点开去那一条复盘。
fn due_notice(d:&Due)->Notice {
 let short=crate::watch_move::short(&d.symbol);
 Notice{
  title:if d.title.is_empty() {format!("{short} 到点了")} else {d.title.clone()},
  body:"去看看这一笔判对了没有".into(),
  link:format!("hkline://review/{}",d.review_id),
  kind:"reviewDue",
 }
}

/// 通知正文里的价。K/M 那套金额单位是给成交额用的，价格要看得清每一位。
pub fn money(v:f64)->String {
 let magnitude=v.abs();
 let decimals=if magnitude>=1000.0 {0} else if magnitude>=1.0 {2} else if magnitude>=0.01 {4} else {8};
 let text=format!("{v:.decimals$}");
 let (sign,rest)=if let Some(r)=text.strip_prefix('-') {("-",r)} else {("",text.as_str())};
 let (whole,fraction)=rest.split_once('.').map_or((rest,""),|(a,b)|(a,b));
 let mut grouped=String::new();
 for (i,c) in whole.chars().enumerate() {
  if i>0&&(whole.len()-i)%3==0 {grouped.push(',')}
  grouped.push(c);
 }
 if fraction.is_empty() {format!("{sign}{grouped}")} else {format!("{sign}{grouped}.{fraction}")}
}

/// 一帧组合流消息里我们要的东西。
///
/// `closed` 就是币安 kline 帧里的 `k.x`：这一根收了没有。同一根 K 线一分钟里会发来
/// 几十帧，只有最后那一帧是 `true`，`close` 到那一帧才是真正的收盘价——`condition='close'`
/// 的提醒只认那一帧。
#[derive(Clone,Debug,PartialEq)]
struct Candle {symbol:String,open_time:i64,low:f64,high:f64,close:f64,closed:bool}
fn parse(text:&str)->Option<Candle> {
 let v:Value=serde_json::from_str(text).ok()?;
 let data=v.get("data").unwrap_or(&v);
 if data.get("e").and_then(Value::as_str)!=Some("kline") {return None}
 let k=data.get("k")?;
 // 币安把所有价格都发成字符串（浮点在 JSON 里过一手就不精确了）。
 let number=|key:&str|k.get(key).and_then(Value::as_str).and_then(|s|s.parse::<f64>().ok());
 Some(Candle{
  symbol:data.get("s").and_then(Value::as_str)?.to_string(),
  open_time:k.get("t").and_then(Value::as_i64)?,
  low:number("l")?,high:number("h")?,close:number("c")?,
  // `x` 是个真布尔（不像价格那样被发成字符串）。缺了就当没收：漏一根收盘穿过，
  // 好过把一根没收的当成收了、在盘中就响。
  closed:k.get("x").and_then(Value::as_bool).unwrap_or(false),
 })
}
/// 一帧 `@ticker`（24 小时滚动统计）。只在有实时活动盯着这个品种时才订得到它。
///
/// 要的只有两样：`c` 最新价、`P` 24h 涨跌**百分数**。契约里的 `change` 是小数，所以这里
/// 除以 100——发上去的 `-0.0123` 意思是跌 1.23%，不是跌 123%。
/// 读不出来的字段返回 `None`，让锁屏上那一格空着，不拿 0 冒充。
fn parse_ticker(text:&str)->Option<(String,Option<f64>,Option<f64>)> {
 let v:Value=serde_json::from_str(text).ok()?;
 let data=v.get("data").unwrap_or(&v);
 if data.get("e").and_then(Value::as_str)!=Some("24hrTicker") {return None}
 let number=|key:&str|data.get(key).and_then(Value::as_str).and_then(|s|s.parse::<f64>().ok()).filter(|v:&f64|v.is_finite());
 Some((data.get("s").and_then(Value::as_str)?.to_string(),number("c"),number("P").map(|p|p/100.0)))
}

// ——————————————————————— 副作用（写库、推送）走另一条路 ———————————————————————

/// 评估器攒下来、交给 [`work`] 去做的事。
///
/// 为什么要分开：原来评估器在 WebSocket 读循环里**当场** await 写库事务和 APNs 往返。
/// 一次推送几百毫秒、一次写库碰上锁等几秒，这期间读循环一帧都不读——帧在缓冲里堆着，
/// 堆到九十秒的死线就被当成断流重连，重连又丢一段 K 线。现在读循环只做纯计算（外加
/// 十秒一次的只读刷新），要做的事塞进一条有界队列，由同一个任务里并排跑着的 [`work`]
/// 一件件做完。
enum Effect {
 /// 一条价格提醒碰到了线：落库、写同步 op、收实时活动、推送。
 Fire{watch:Box<Watch>,quote:Quote,price:f64,at:i64},
 /// 自选波动响了。
 Move{owner:Uuid,event:crate::watch_move::Event},
 /// 这一轮刷新读到的已到点复盘提醒。
 Due(Vec<Due>),
 /// 实时活动的一拍心跳（带着那一刻的行情表）。
 Beat(BTreeMap<String,Quote>),
}
/// 队列多深。十来个用户、一分钟一根 K 线，正常时队列里不会超过个位数；排满只会是
/// 数据库或 APNs 卡死了，那时候再往里塞也做不完。
const EFFECT_QUEUE:usize=1024;

/// 已经交出去、还没做完的那几条提醒（`(owner, alert_id)`）。
///
/// 为什么要记：评估器十秒一刷，从库里读回所有 active 的提醒。交出去的那条在 [`work`]
/// 把它落成 fired 之前在库里还是 active，不挡一下的话它会被读回来、下一帧又判中、
/// 又交一次——APNs 慢的时候每秒几次地往队列里塞同一条。落库那道 `WHERE status='active'`
/// 让它不会推两次，但每一次都是一个白开的事务。做完（不论成败）就放掉：失败的那条
/// 下一轮刷新自然读回来重判，这就是原来「失败了塞回内存表」的那条重试路。
#[derive(Clone,Default)]
struct Busy(std::sync::Arc<std::sync::Mutex<std::collections::HashSet<(Uuid,String)>>>);
impl Busy {
 fn set(&self)->std::sync::MutexGuard<'_,std::collections::HashSet<(Uuid,String)>> {self.0.lock().unwrap_or_else(|e|e.into_inner())}
 fn claim(&self,owner:Uuid,alert_id:&str)->bool {self.set().insert((owner,alert_id.to_string()))}
 fn holds(&self,owner:Uuid,alert_id:&str)->bool {self.set().contains(&(owner,alert_id.to_string()))}
 fn done(&self,owner:Uuid,alert_id:&str) {self.set().remove(&(owner,alert_id.to_string()));}
}

/// 评估器手里那一头：往队列里放事，**永不等待**。
#[derive(Clone)]
struct Effects {queue:tokio::sync::mpsc::Sender<Effect>,busy:Busy}
impl Effects {
 fn channel(depth:usize)->(Self,tokio::sync::mpsc::Receiver<Effect>) {
  let (queue,rx)=tokio::sync::mpsc::channel(depth);
  (Self{queue,busy:Busy::default()},rx)
 }
 /// 排满了就丢掉并留一行日志。丢掉是安全的：提醒和复盘到点在库里还是 active，
 /// 下一轮刷新（十秒内）重新读回来再判；心跳下一拍再走；只有自选波动那一下会真的
 /// 少一条横幅。
 fn send(&self,effect:Effect) {
  use tokio::sync::mpsc::error::TrySendError;
  let rejected=match self.queue.try_send(effect) {
   Ok(())=>return,
   Err(TrySendError::Full(e))=>{tracing::warn!("The alert side-effect queue is full; dropping one (active alerts are re-read on the next refresh)");e}
   Err(TrySendError::Closed(e))=>{tracing::warn!("The alert side-effect worker is gone; dropping one");e}
  };
  // 没交出去的那几条要放掉，不然它们永远被当成「在做」、再也不判。
  match rejected {
   Effect::Fire{watch,..}=>self.busy.done(watch.owner,&watch.alert_id),
   Effect::Due(due)=>for d in due {self.busy.done(d.owner,&d.alert_id)},
   Effect::Move{..}|Effect::Beat(_)=>{}
  }
 }
 fn fire(&self,watch:Watch,quote:Quote,price:f64,at:i64) {
  if !self.busy.claim(watch.owner,&watch.alert_id) {return}
  self.send(Effect::Fire{watch:Box::new(watch),quote,price,at});
 }
 fn due(&self,due:Vec<Due>) {
  let due:Vec<Due>=due.into_iter().filter(|d|self.busy.claim(d.owner,&d.alert_id)).collect();
  if !due.is_empty() {self.send(Effect::Due(due))}
 }
 /// 刷新读回来的提醒里，去掉已经交出去还没做完的那几条。
 fn idle(&self,watches:Vec<Watch>)->Vec<Watch> {watches.into_iter().filter(|w|!self.busy.holds(w.owner,&w.alert_id)).collect()}
}

/// 把队列里的事一件件做完。按先来后到串行：同一个人的推送顺序不乱，同一时刻只占
/// 一条数据库连接。
async fn work(s:&AppState,apns:Option<&Apns>,market:&'static str,mut queue:tokio::sync::mpsc::Receiver<Effect>,busy:Busy) {
 while let Some(effect)=queue.recv().await {
  match effect {
   Effect::Fire{watch,quote,price,at}=>{
    if let Err(e)=fire(s,apns,&watch,quote,price,at).await {
     tracing::warn!("An alert could not be recorded as fired ({e:?}); the next refresh will retry it");
    }
    busy.done(watch.owner,&watch.alert_id);
   }
   Effect::Move{owner,event}=>crate::watch_move::notify(s,apns,owner,&event,market).await,
   Effect::Due(due)=>{
    settle_due(s,apns,&due).await;
    for d in &due {busy.done(d.owner,&d.alert_id)}
   }
   Effect::Beat(quotes)=>if let Err(e)=crate::live_activity::beat(s,apns,&quotes).await {
    tracing::warn!("A live activity heartbeat could not be delivered ({e:?}); the next beat will try again");
   },
  }
 }
}

/// 每个品种最近一根**已收盘** K 线的（开盘时刻, 收盘价）。开盘时刻是断线后补 K 线的
/// 起点，也用来认出「这一根已经按收盘判过了」（补回来的那根又从流里来一遍）。
type Closes=BTreeMap<String,(i64,f64)>;

/// worker 的评估器入口（币安那一支）。永不返回：连不上就退几秒再连，品种集合变了就重订阅。
/// Coinbase 的提醒不在币安那条组合流里，是另一条常驻任务 [`run_coinbase`]；两条由
/// worker 各自起、各自被 `supervise` 看着，两边互不牵连。
///
/// 判定和做事在同一个任务里并排跑（`join!`）：任何一边 panic 都带着另一边一起倒，
/// 由 `supervise` 整个重启，不会出现「还在判、做事的那一半已经没了」的半死状态。
pub async fn run(s:AppState,apns:Option<std::sync::Arc<Apns>>) {
 tracing::info!("Alert evaluator started");
 let (effects,queue)=Effects::channel(EFFECT_QUEUE);
 let busy=effects.busy.clone();
 tokio::join!(binance(&s,effects),work(&s,apns.as_deref(),BINANCE,queue,busy));
}
async fn binance(s:&AppState,effects:Effects) {
 let mut watches:Vec<Watch>=vec![];
 // 每个品种最近一根**已收盘**的收盘价。`condition='close'` 要两个点才判得出穿越，
 // 这就是那第一个点。
 //
 // 它活在重连之外（不放在 `session` 里）是故意的：断线重连、品种集合变化都不该把它
 // 丢掉。重连之后先按它记下的开盘时刻把断线期间收掉的 K 线补回来（[`backfill`]），
 // 补不回来的部分，这一比就是「跨过那段缺口有没有穿过线」——价格确实从一侧走到了
 // 另一侧，该响；清空它换来的只是白白漏掉一次。
 let mut closes:Closes=BTreeMap::new();
 // 每个品种此刻的价与 24h 涨跌幅。K 线帧一直在刷价，涨跌幅只有 `@ticker` 那条流里有，
 // 而那条流只在有实时活动盯着这个品种时才订——没有活动的时候这张表里就只有价。
 // 实时活动的心跳（`live_activity::beat`）读的就是它。
 let mut quotes:BTreeMap<String,Quote>=BTreeMap::new();
 // 上一拍心跳。它活在重连之外：断线重连不该让锁屏上的活动多等一整拍。
 // 减一拍是为了「起来就先走一拍」；刚开机的机器上 Instant 减不动，那就当这一拍刚走过。
 let mut beat=std::time::Instant::now().checked_sub(crate::live_activity::HEARTBEAT).unwrap_or_else(std::time::Instant::now);
 // 自选波动提醒的各人状态。和 `closes` 一样活在重连之外：闸不因断线复位，同一个
 // 窗口里重连回来不许再响一次。
 let mut movers=crate::watch_move::Movers::default();
 loop {
  let fresh=match load(s,BINANCE).await {
   Ok(v)=>v,
   Err(_)=>{tracing::warn!("Alerts could not be loaded; will retry");tokio::time::sleep(Duration::from_secs(10)).await;continue}
  };
  movers.refresh(&fresh.movers);
  // 复盘到点不看价：有没有 K 线流都要按时判，所以放在「一个品种都没有」那条岔路前面。
  effects.due(fresh.due);
  let symbols=symbols_of(&fresh.watches,&movers.symbols());
  let streams=streams_of(&symbols,&fresh.live);
  watches=effects.idle(fresh.watches);
  if symbols.is_empty() {
   // 一条提醒都没有的时候也要走心跳：提醒刚被删掉、而它的活动还挂在别人锁屏上的
   // 那一下，正是最该推 end 的时候。
   heartbeat(&effects,&quotes,&mut beat);
   tokio::time::sleep(Duration::from_secs(10)).await;continue
  }
  // 不再盯的品种没必要一直留着它的收盘价与行情。
  closes.retain(|symbol,_|symbols.iter().any(|s|s==symbol));
  quotes.retain(|symbol,_|symbols.iter().any(|s|s==symbol));
  if let Err(e)=session(s,&effects,&streams,&mut watches,&mut movers,&mut closes,&mut quotes,&mut beat).await {
   tracing::warn!("Alert stream ended ({e}); reconnecting");
   tokio::time::sleep(Duration::from_secs(5)).await;
  }
 }
}
/// 要订的品种：有活动价格提醒的，加上开着自选波动提醒的人的自选。
fn symbols_of(watches:&[Watch],movers:&std::collections::BTreeSet<String>)->Vec<String> {
 let mut all:Vec<String>=watches.iter().map(|w|w.symbol.clone()).chain(movers.iter().cloned()).collect();
 all.sort();all.dedup();
 if all.len()>MAX_STREAMS {
  tracing::warn!("{} symbols have alerts but one combined stream carries {MAX_STREAMS}; the rest are not watched",all.len());
  all.truncate(MAX_STREAMS);
 }
 all
}
/// 这一轮要订的流。
///
/// K 线是每个有提醒的品种都要的；`@ticker` 只给**正被实时活动盯着**的那几个品种加——
/// 24h 涨跌幅只有那条流里有，而锁屏上要显示它。没有活动时这个函数吐出来的东西和从前
/// 一字不差，所以「没人用实时活动」这个常态下评估器的上游负载一点没变。
/// 两种流共用一条连接（币安的组合流上限 200 条），不新开连接、也不碰 REST 那道限流闸。
fn streams_of(symbols:&[String],live:&[String])->Vec<String> {
 let mut out:Vec<String>=symbols.iter().map(|s|format!("{}@kline_1m",s.to_lowercase())).collect();
 for symbol in live {
  if out.len()>=MAX_STREAMS {break}
  if symbols.iter().any(|s|s==symbol) {out.push(format!("{}@ticker",symbol.to_lowercase()))}
 }
 out
}
/// 到点了就走一拍实时活动的心跳。**六十秒一拍**，不是每来一帧推一次：前台由客户端自己
/// 更新，这一拍只为被挂起的 app 而存在。发信交给 [`work`]，这里只看钟、抄一份行情。
fn heartbeat(effects:&Effects,quotes:&BTreeMap<String,Quote>,beat:&mut std::time::Instant) {
 if beat.elapsed()<crate::live_activity::HEARTBEAT {return}
 *beat=std::time::Instant::now();
 effects.send(Effect::Beat(quotes.clone()));
}

/// 一次连接的生命周期。要订的流变了就返回，让外层重连。
#[allow(clippy::too_many_arguments)]
async fn session(s:&AppState,effects:&Effects,streams:&[String],watches:&mut Vec<Watch>,movers:&mut crate::watch_move::Movers,closes:&mut Closes,quotes:&mut BTreeMap<String,Quote>,beat:&mut std::time::Instant)->anyhow::Result<()> {
 let url=format!("{STREAM}?streams={}",streams.join("/"));
 let (mut stream,_)=tokio_tungstenite::connect_async(&url).await?;
 // 新连上的这一条和上一条之间有缺口：断线前那一根记下的「收盘」不是真收盘，
 // 波动判定要的五分钟前参照全部作废，从缺口重新开始（缺口不冒充零波动）。
 movers.forget_prices();
 tracing::info!("Alert evaluator watching {} stream(s)",streams.len());
 // 先连上再补：补的那几秒里新帧在连接里排着，一帧不丢；反过来先补后连，补完到连上
 // 之间收掉的那一根就又漏了。
 for candle in backfill(BINANCE,closes,chrono::Utc::now().timestamp_millis()).await {
  evaluate(effects,watches,closes,quotes,&candle);
 }
 let mut refresh=tokio::time::interval(Duration::from_secs(10));
 refresh.tick().await;
 loop {
  tokio::select! {
   // 币安每三分钟发一次 ping，正常品种的 1m K 线每秒都有好几帧。九十秒一帧都没有
   // 只有一种解释：这条连接已经死了而 TCP 还没告诉我们。读循环里不再有写库和推送，
   // 所以这条死线不会再被自己的慢动作撞上。
   frame=tokio::time::timeout(Duration::from_secs(90),stream.next())=>{
    let Some(frame)=frame? else {anyhow::bail!("the stream closed")};
    let message=frame?;
    let Some(text)=message.into_text().ok() else {continue};
    if let Some(candle)=parse(&text) {
     // 最新价就是这一根还没收的收盘价。涨跌幅不动：它只从 ticker 帧来，这里覆盖成
     // None 等于每来一根 K 线就把锁屏上的涨跌幅抹掉一次。
     quotes.entry(candle.symbol.clone()).or_default().price=candle.close.is_finite().then_some(candle.close);
     evaluate(effects,watches,closes,quotes,&candle);
     for (owner,event) in movers.observe(&candle.symbol,candle.open_time,candle.close,candle.closed) {
      effects.send(Effect::Move{owner,event});
     }
     continue
    }
    if let Some((symbol,price,change))=parse_ticker(&text) {
     let quote=quotes.entry(symbol).or_default();
     if price.is_some() {quote.price=price}
     if change.is_some() {quote.change=change}
    }
   }
   _=refresh.tick()=>{
    match load(s,BINANCE).await {
     Ok(fresh)=>{
      movers.refresh(&fresh.movers);
      effects.due(fresh.due);
      let changed=streams_of(&symbols_of(&fresh.watches,&movers.symbols()),&fresh.live)!=streams;
      *watches=effects.idle(fresh.watches);
      if changed {return Ok(())}
     }
     Err(_)=>tracing::warn!("Alerts could not be refreshed; keeping the current set"),
    }
    heartbeat(effects,quotes,beat);
   }
  }
 }
}

/// 一根 K 线对一条提醒响不响：响了返回线在这一刻的价。和客户端 `AlertEvaluator.hit`
/// 是同一个入口、同一套规则，`contract/alert-cases.json` 的每条用例两边都跑一遍
/// （`every_shared_alert_case_agrees` 与 KanpanCore 的 `AlertCasesContractTests`）。
fn judge(lines:&[Line],condition:Condition,armed_at:i64,candle:&Candle,previous:Option<f64>)->Option<f64> {
 match condition {
  Condition::Touch=>touched(lines,candle.open_time,armed_at,candle.low,candle.high),
  // 这一根没收就一个字都不判；没有上一根的收盘价（刚起来、或者这个品种第一次收）
  // 也不判——宁可漏一根，也不拿一个不知道是哪一根的价去算穿越。
  Condition::Close=>if candle.closed {previous.and_then(|p|crossed_on_close(lines,candle.open_time,armed_at,p,candle.close))} else {None},
 }
}

/// 一帧 K 线对上这一批提醒。**纯计算，不 await**：判中的交给 [`work`] 去落库、推送。
///
/// 触发过的从内存里摘掉：下一次刷新（十秒内）才会重新读库，中间这段时间不摘就会
/// 每来一帧交一次。库里那条 `WHERE status='active'` 是最终的那道闸，这里只是不做无用功。
///
/// `closes` 里那一条**先读后写**：这一帧要拿的是上一根的收盘价，写进去的是这一根的。
/// 顺序反了的话每一根都在和自己比，`close` 这一档永远不会响。
///
/// 这一根已经按收盘判过（记下的开盘时刻不早于它：断线补回来的那根又从流里收了一遍）时，
/// 收盘穿越不再判第二次，`closes` 也不再改——拿它和自己比永远不会穿，拿更早那根比会把
/// 同一次穿越算两遍。
fn evaluate(effects:&Effects,watches:&mut Vec<Watch>,closes:&mut Closes,quotes:&BTreeMap<String,Quote>,candle:&Candle) {
 let at=chrono::Utc::now().timestamp_millis();
 let last=closes.get(&candle.symbol).copied();
 let seen=last.is_some_and(|(open_time,_)|open_time>=candle.open_time);
 let previous=last.filter(|_|!seen).map(|(_,close)|close);
 let mut fired=vec![];
 for (index,w) in watches.iter().enumerate() {
  if w.symbol!=candle.symbol {continue}
  if judge(&w.lines,w.condition,w.armed_at,candle,previous).is_some() {fired.push(index)}
 }
 if candle.closed&&candle.close.is_finite()&&!seen {closes.insert(candle.symbol.clone(),(candle.open_time,candle.close));}
 let quote=quotes.get(&candle.symbol).copied().unwrap_or_default();
 for index in fired.iter().rev() {
  effects.fire(watches.remove(*index),quote,candle.close,at);
 }
}

// ——————————————————————— 断线补 K 线 ———————————————————————

/// 断线最多往回补多久。再往前的缺口不补：一小时前碰过的线现在才推，用户已经不需要了，
/// 那一段按原来的规矩只拿缺口两端的收盘价比一次穿越。
const BACKFILL_MS:i64=60*60_000;
/// 补 K 线最多等多久。补不回来就算了，新连接不能一直不读流。
const BACKFILL_WAIT:Duration=Duration::from_secs(15);
/// 同时问几个品种。币安、Coinbase 的 REST 都有限速，几个品种一起补不必排成一列，
/// 也不该一下子全撒出去。
const BACKFILL_PARALLEL:usize=4;
/// 币安 K 线走 www.binance.com：美国那台 VPS 上 fapi.binance.com 回 451（见
/// `sector_history::KLINES`）。
const BINANCE_KLINES:&str="https://www.binance.com/fapi/v1/klines";

/// 这个品种该补哪一段：`last` 是最后一根记下来的已收盘 K 线的开盘时刻。返回
/// `[first, end)`（开盘时刻，毫秒）——`end` 是此刻还没收的那一根，它之前的都已经收了。
/// 一根都没漏就是 `None`：断线只有几秒、没跨过分钟线的那种重连一次 REST 都不发。
fn gap(last:i64,now:i64)->Option<(i64,i64)> {
 let end=now.div_euclid(60_000)*60_000;
 let first=(last+60_000).max(end-BACKFILL_MS);
 (first<end).then_some((first,end))
}
/// 币安 `/fapi/v1/klines` 的一页：`[[开盘时刻, "开", "高", "低", "收", …], …]`。
/// 只留 `[first, end)` 里的（那一段都已经收了）。
fn binance_rows(symbol:&str,v:&Value,first:i64,end:i64)->Vec<Candle> {
 v.as_array().into_iter().flatten().filter_map(|row|{
  let row=row.as_array()?;
  let number=|i:usize|row.get(i)?.as_str()?.parse::<f64>().ok().filter(|v|v.is_finite());
  let open_time=row.first()?.as_i64()?;
  if open_time<first||open_time>=end {return None}
  Some(Candle{symbol:symbol.to_string(),open_time,low:number(3)?,high:number(2)?,close:number(4)?,closed:true})
 }).collect()
}
/// Coinbase 的原生 1 分钟 K 线（秒、字符串价）换成评估器的样子。没成交的分钟 Coinbase
/// 不给，缺着就缺着——和逐笔拼出来的那一支同一个口径。
fn coinbase_rows(symbol:&str,rows:Vec<crate::venues::coinbase::Candle>,first:i64,end:i64)->Vec<Candle> {
 rows.into_iter().filter_map(|c|{
  let number=|s:&str|s.parse::<f64>().ok().filter(|v|v.is_finite());
  let open_time=c.start*1000;
  if open_time<first||open_time>=end {return None}
  Some(Candle{symbol:symbol.to_string(),open_time,low:number(&c.low)?,high:number(&c.high)?,close:number(&c.close)?,closed:true})
 }).collect()
}

/// 重连之后，把断线期间收掉的 1 分钟 K 线从 REST 补回来，按时间排好交给 `evaluate`
/// （当成已收盘的那一帧判：触线、收盘穿越都判）。
///
/// 为什么要补：原来断一次线就丢一段 K 线，这段时间里碰过线又回来的价格，提醒就再也
/// 不会响了——而断线正是 APNs 慢、数据库慢时最常发生的事。
///
/// 只补 `closes` 里有底的品种（这个进程里见过它收盘）：刚起来、或者新加进来的品种，
/// 不知道缺口从哪儿开始，也就不补。补回来的 K 线**不喂**自选波动：它们的窗口早就过了，
/// 现在推「五分钟涨 1.6%」是一条过期的横幅。
async fn backfill(market:&'static str,closes:&Closes,now:i64)->Vec<Candle> {
 use futures_util::stream;
 let jobs:Vec<(String,i64,i64)>=closes.iter().filter_map(|(symbol,(last,_))|gap(*last,now).map(|(first,end)|(symbol.clone(),first,end))).collect();
 if jobs.is_empty() {return vec![]}
 let asked=jobs.len();
 let fetch=stream::iter(jobs).map(|(symbol,first,end)|async move {
  if market==COINBASE {
   crate::venues::coinbase::candles(&symbol,60,first/1000,end/1000).await.ok().map(|rows|coinbase_rows(&symbol,rows,first,end))
  } else {
   let limit=(end-first)/60_000;
   let url=format!("{BINANCE_KLINES}?symbol={symbol}&interval=1m&startTime={first}&endTime={}&limit={limit}",end-1);
   crate::market_meta::get_json(&url).await.ok().map(|v|binance_rows(&symbol,&v,first,end))
  }
 }).buffered(BACKFILL_PARALLEL);
 let mut fetch=std::pin::pin!(fetch);
 let deadline=tokio::time::sleep(BACKFILL_WAIT);
 let mut deadline=std::pin::pin!(deadline);
 let (mut out,mut answered,mut failed)=(vec![],0usize,0usize);
 loop {
  tokio::select! {
   next=fetch.next()=>match next {
    Some(Some(candles))=>{answered+=1;out.extend(candles)}
    Some(None)=>{answered+=1;failed+=1}
    None=>break,
   },
   _=&mut deadline=>{tracing::warn!("Backfilling {market} candles after a reconnect timed out; {} of {asked} symbol(s) answered",answered);break}
  }
 }
 if failed>0 {tracing::warn!("{failed} of {asked} {market} symbol(s) could not be backfilled after a reconnect; their gap is judged by the closes on either side")}
 // 稳定排序：同一个品种的先后不变，不同品种交错着来无所谓。
 out.sort_by_key(|c|c.open_time);
 if !out.is_empty() {tracing::info!("Backfilled {} {market} candle(s) missed while reconnecting",out.len())}
 out
}

// ------------------------------------------------------------------ Coinbase

/// Coinbase 这一支：它没有 1 分钟 K 线推送（`candles` 频道固定 5 分钟），所以订
/// `market_trades`，用逐笔在这里拼 1 分钟 K 线，再交给和币安同一个 `evaluate`。
///
/// - 触线：这一分钟的高/低被刷新时才判一次（逐笔成百上千，没刷新极值的那几笔判了也
///   只是重复）；
/// - 收盘穿越：一分钟收完才判。「收完」= 下一分钟的第一笔到了，或者这一分钟结束后
///   `SETTLE` 过去还没有新的一笔（冷门品种一分钟可能一笔都没有）。
/// - 连接十秒一刷提醒集合，品种集合变了就重连；心跳频道每秒一帧，三十秒一帧都没有就判断线。
/// - 和币安那一支一样：判定和做事分两半并排跑，重连后先补断线期间的 K 线。
pub async fn run_coinbase(s:AppState,apns:Option<std::sync::Arc<Apns>>) {
 let (effects,queue)=Effects::channel(EFFECT_QUEUE);
 let busy=effects.busy.clone();
 tokio::join!(coinbase(&s,effects),work(&s,apns.as_deref(),COINBASE,queue,busy));
}
async fn coinbase(s:&AppState,effects:Effects) {
 let mut closes:Closes=BTreeMap::new();
 // 这一支自己的自选波动状态（只装 Coinbase 的自选）。和币安那一支一样活在重连之外。
 let mut movers=crate::watch_move::Movers::default();
 loop {
  let fresh=match load(s,COINBASE).await {
   Ok(v)=>v,
   Err(_)=>{tracing::warn!("Coinbase alerts could not be loaded; will retry");tokio::time::sleep(Duration::from_secs(10)).await;continue}
  };
  movers.refresh(&fresh.movers);
  let symbols=symbols_of(&fresh.watches,&movers.symbols());
  if symbols.is_empty() {closes.clear();tokio::time::sleep(Duration::from_secs(10)).await;continue}
  closes.retain(|symbol,_|symbols.contains(symbol));
  if let Err(e)=coinbase_session(s,&effects,&symbols,effects.idle(fresh.watches),&mut movers,&mut closes).await {
   tracing::warn!("Coinbase alert stream ended ({e}); reconnecting");
   tokio::time::sleep(Duration::from_secs(5)).await;
  }
 }
}

async fn coinbase_session(s:&AppState,effects:&Effects,symbols:&[String],mut watches:Vec<Watch>,movers:&mut crate::watch_move::Movers,closes:&mut Closes)->anyhow::Result<()> {
 use futures_util::SinkExt;
 use tokio_tungstenite::tungstenite::Message;
 use crate::venues::coinbase;
 let (mut stream,_)=tokio::time::timeout(Duration::from_secs(10),tokio_tungstenite::connect_async(coinbase::WS)).await??;
 stream.send(Message::Text(coinbase::control("subscribe","heartbeats",&[]).into())).await?;
 stream.send(Message::Text(coinbase::control("subscribe","market_trades",symbols).into())).await?;
 tracing::info!("Coinbase alert evaluator watching {} product(s)",symbols.len());
 // 新连上的这一条和上一条之间有缺口：五分钟前的参照全部作废（和币安那一支同一条规矩）。
 movers.forget_prices();
 let mut quotes:BTreeMap<String,Quote>=BTreeMap::new();
 // 订阅之后再补（理由同币安那一支）。
 for candle in backfill(COINBASE,closes,chrono::Utc::now().timestamp_millis()).await {
  evaluate(effects,&mut watches,closes,&quotes,&candle);
 }
 let mut bars=MinuteBars::default();
 let mut refresh=tokio::time::interval(Duration::from_secs(10));
 refresh.tick().await;
 let mut settle=tokio::time::interval(Duration::from_secs(1));
 loop {
  let mut candles=vec![];
  tokio::select! {
   frame=tokio::time::timeout(Duration::from_secs(30),stream.next())=>{
    let Some(frame)=frame? else {anyhow::bail!("the stream closed")};
    let text=match frame? {
     Message::Text(text)=>text,
     Message::Ping(p)=>{stream.send(Message::Pong(p)).await?;continue}
     Message::Close(_)=>anyhow::bail!("Coinbase closed the stream"),
     _=>continue,
    };
    for (symbol,time,price) in coinbase_trades(text.as_str()) {
     if !symbols.contains(&symbol) {continue}
     quotes.entry(symbol.clone()).or_default().price=Some(price);
     candles.extend(bars.trade(&symbol,time,price));
    }
   }
   _=settle.tick()=>{
    candles.extend(bars.settle(chrono::Utc::now().timestamp_millis()));
   }
   _=refresh.tick()=>{
    match load(s,COINBASE).await {
     Ok(fresh)=>{
      movers.refresh(&fresh.movers);
      let changed=symbols_of(&fresh.watches,&movers.symbols())!=symbols;
      watches=effects.idle(fresh.watches);
      if changed {return Ok(())}
     }
     Err(_)=>tracing::warn!("Coinbase alerts could not be refreshed; keeping the current set"),
    }
   }
  }
  for candle in candles {
   evaluate(effects,&mut watches,closes,&quotes,&candle);
   for (owner,event) in movers.observe(&candle.symbol,candle.open_time,candle.close,candle.closed) {
    effects.send(Effect::Move{owner,event});
   }
  }
 }
}

/// 一分钟结束后再等这么久才判它收了：推送的逐笔会比成交时间晚一点到。
const SETTLE_MS:i64=2_000;

/// 每个品种正在走的那一根 1 分钟 K 线。
#[derive(Default)]
struct MinuteBars {open:BTreeMap<String,Candle>}
impl MinuteBars {
 /// 一笔成交。返回要评估的 K 线：上一分钟收了就先给那一根（`closed`），这一根的
 /// 高/低被刷新了再给这一根（未收）。比当前这一根还早的成交（迟到的、或者跨分钟乱序）
 /// 不再改动已经判过的那一根。
 fn trade(&mut self,symbol:&str,time:i64,price:f64)->Vec<Candle> {
  if !price.is_finite()||price<=0.0 {return vec![]}
  let minute=time.div_euclid(60_000)*60_000;
  let mut out=vec![];
  match self.open.get_mut(symbol) {
   Some(bar) if minute<bar.open_time=>{}
   Some(bar) if minute==bar.open_time=>{
    let extended=price<bar.low||price>bar.high;
    bar.low=bar.low.min(price);bar.high=bar.high.max(price);bar.close=price;
    if extended {out.push(bar.clone())}
   }
   _=>{
    if let Some(mut done)=self.open.remove(symbol) {done.closed=true;out.push(done)}
    let bar=Candle{symbol:symbol.to_string(),open_time:minute,low:price,high:price,close:price,closed:false};
    out.push(bar.clone());
    self.open.insert(symbol.to_string(),bar);
   }
  }
  out
 }
 /// 一分钟过完 `SETTLE_MS` 还没等到下一笔的那几根，就当它们收了。
 fn settle(&mut self,now:i64)->Vec<Candle> {
  let due:Vec<String>=self.open.iter().filter(|(_,b)|now>=b.open_time+60_000+SETTLE_MS).map(|(k,_)|k.clone()).collect();
  due.into_iter().filter_map(|k|self.open.remove(&k)).map(|mut b|{b.closed=true;b}).collect()
 }
}

/// 一帧 `market_trades` 里的逐笔：(品种, 成交时间毫秒, 价)，按成交先后排好。
/// `snapshot` 事件是订阅那一刻补发的最近几十笔历史，不拿来判提醒。
fn coinbase_trades(text:&str)->Vec<(String,i64,f64)> {
 let Ok(v)=serde_json::from_str::<Value>(text) else {return vec![]};
 if v.get("channel").and_then(Value::as_str)!=Some("market_trades") {return vec![]}
 let mut out=vec![];
 for event in v.get("events").and_then(Value::as_array).into_iter().flatten() {
  if event.get("type").and_then(Value::as_str)!=Some("update") {continue}
  for t in event.get("trades").and_then(Value::as_array).into_iter().flatten() {
   let (Some(symbol),Some(time),Some(price))=(
    t.get("product_id").and_then(Value::as_str),
    t.get("time").and_then(Value::as_str).and_then(crate::venues::coinbase::iso_ms),
    t.get("price").and_then(Value::as_str).and_then(|p|p.parse::<f64>().ok()),
   ) else {continue};
   let id=t.get("trade_id").and_then(Value::as_str).and_then(|s|s.parse::<i64>().ok()).unwrap_or(0);
   out.push((id,symbol.to_string(),time,price));
  }
 }
 // Coinbase 一帧里是新的在前。
 out.sort_by_key(|(id,_,time,_)|(*time,*id));
 out.into_iter().map(|(_,s,t,p)|(s,t,p)).collect()
}

#[cfg(test)]
mod tests {
 use super::*;

 /// **提醒判定两端一字不差：同一份夹具，客户端和服务端各跑一遍。**
 ///
 /// 判定器有两份（前台 `AlertEvaluator.swift`、这里），规则靠注释「照着同一段文字实现」，
 /// 已经分歧过两次：low > high 时 Swift 归一、这里当坏帧（cc025383 修掉），竖直段 Swift 取
 /// 靠后那个点、这里取靠前那个。同一根 K 线一端响一端不响，用户就会收到一条前台没响过的
 /// 推送，或者反过来。夹具是手工维护的 `contract/alert-cases.json`；改规则先改它。
 /// 服务端只返回价，所以这里只核价；`line` 下标由客户端那一半核。
 #[test] fn every_shared_alert_case_agrees() {
  let fixture:Value=serde_json::from_str(include_str!("../contract/alert-cases.json")).expect("contract/alert-cases.json");
  assert_eq!(fixture["version"],json!(1),"alert-cases.json 的格式版本变了，这里的读法要一起改");
  let cases=fixture["cases"].as_array().expect("cases");
  assert!(cases.len()>=30,"夹具被删薄了");
  for case in cases {
   let name=case["name"].as_str().expect("name");
   let lines:Vec<Line>=serde_json::from_value(case["lines"].clone()).expect("lines");
   let bar=&case["bar"];
   let int=|v:&Value|v.as_i64().unwrap_or_else(||panic!("{name}: 时间要是毫秒整数"));
   let candle=Candle{symbol:String::new(),open_time:int(&bar["openTime"]),low:bar["low"].as_f64().expect("low"),
    high:bar["high"].as_f64().expect("high"),close:bar["close"].as_f64().unwrap_or(f64::NAN),closed:bar["closed"].as_bool().expect("closed")};
   let got=judge(&lines,Condition::of(case["condition"].as_str().expect("condition")),int(&case["armedAt"]),&candle,bar["previousClose"].as_f64());
   let want=case["expect"]["price"].as_f64();
   assert_eq!(got,want,"{name}：{}",case["why"].as_str().unwrap_or(""));
  }
 }

 fn line(points:&[(f64,f64)],left:bool,right:bool)->Line {
  Line{points:points.iter().map(|(t,p)|Point{t:*t,p:*p}).collect(),extend_left:left,extend_right:right}
 }

 /// 两点之间就是一条直线上的插值。
 #[test] fn a_segment_is_interpolated_between_its_points() {
  let l=line(&[(0.0,100.0),(100.0,200.0)],false,false);
  assert_eq!(price_at(&l,0),Some(100.0));
  assert_eq!(price_at(&l,50),Some(150.0));
  assert_eq!(price_at(&l,100),Some(200.0));
 }
 /// **不延伸的一侧超出即不评估。** 一条画到昨天为止的线段，今天的价格穿过它的延长线
 /// 并不是穿过那条线——这里返回 None 而不是把端点的价拿来凑数。
 #[test] fn a_segment_does_not_exist_outside_itself() {
  let l=line(&[(0.0,100.0),(100.0,200.0)],false,false);
  assert_eq!(price_at(&l,-1),None);
  assert_eq!(price_at(&l,101),None);
 }
 /// 射线只往标了的那一侧延伸，斜率沿用最靠边的两点。
 #[test] fn a_ray_extrapolates_on_the_side_it_extends() {
  let right=line(&[(0.0,100.0),(100.0,200.0)],false,true);
  assert_eq!(price_at(&right,200),Some(300.0));
  assert_eq!(price_at(&right,-100),None);
  let left=line(&[(0.0,100.0),(100.0,200.0)],true,false);
  assert_eq!(price_at(&left,-100),Some(0.0));
  assert_eq!(price_at(&left,200),None);
 }
 /// 水平线摊平之后只有一个点，两端都延伸；没有斜率可言，价恒定。
 #[test] fn a_flat_line_is_one_point_extended_both_ways() {
  let l=line(&[(500.0,63_000.0)],true,true);
  for t in [0,500,9_000_000] {assert_eq!(price_at(&l,t),Some(63_000.0))}
  let half=line(&[(500.0,63_000.0)],false,true);
  assert_eq!(price_at(&half,0),None);
  assert_eq!(price_at(&half,600),Some(63_000.0));
 }
 /// 多段折线（比如通道的一条边被摊成三段）各段各算各的。
 #[test] fn a_polyline_uses_the_segment_the_time_falls_in() {
  let l=line(&[(0.0,100.0),(100.0,200.0),(200.0,150.0)],false,false);
  assert_eq!(price_at(&l,150),Some(175.0));
  assert_eq!(price_at(&l,200),Some(150.0));
 }
 /// 点乱序给上来也要算对——客户端理应递增，但哑掉的提醒是查不出来的那种 bug。
 #[test] fn points_out_of_order_still_describe_the_same_line() {
  let l=line(&[(100.0,200.0),(0.0,100.0)],false,false);
  assert_eq!(price_at(&l,50),Some(150.0));
 }
 /// 竖直段（两点同一时刻）不除以零。
 #[test] fn a_vertical_segment_does_not_divide_by_zero() {
  let l=line(&[(100.0,100.0),(100.0,200.0)],true,true);
  assert!(price_at(&l,100).is_some_and(f64::is_finite));
  assert!(price_at(&l,0).is_some_and(f64::is_finite));
 }
 /// 触发判定：K 线的 [low,high] 含住线价就算碰到。
 #[test] fn a_candle_that_straddles_the_line_triggers() {
  let l=vec![line(&[(0.0,100.0),(100.0,100.0)],false,false)];
  assert_eq!(touched(&l,50,0,99.0,101.0),Some(100.0));
  assert_eq!(touched(&l,50,0,100.0,100.0),Some(100.0),"贴着线也算触碰");
  assert_eq!(touched(&l,50,0,101.0,102.0),None);
  assert_eq!(touched(&l,50,0,98.0,99.0),None);
 }
 /// **`armedAt` 之前开盘的 K 线一概不算。** 不挡这一下的话，在贴着线的地方新建一条提醒
 /// 会立刻响——用户要的是「以后碰到再告诉我」。
 #[test] fn a_candle_that_opened_before_arming_never_triggers() {
  let l=vec![line(&[(0.0,100.0),(1_000.0,100.0)],false,false)];
  assert_eq!(touched(&l,100,500,99.0,101.0),None);
  assert_eq!(touched(&l,500,500,99.0,101.0),Some(100.0));
  assert_eq!(touched(&l,600,500,99.0,101.0),Some(100.0));
 }
 /// 一组折线里任意一条碰到就算（矩形的上下边、斐波那契的每一级都在同一条提醒里）。
 #[test] fn any_line_in_the_set_can_trigger_the_alert() {
  let l=vec![line(&[(0.0,100.0),(100.0,100.0)],false,false),line(&[(0.0,200.0),(100.0,200.0)],false,false)];
  assert_eq!(touched(&l,50,0,199.0,201.0),Some(200.0));
 }
 /// 坏数字不许把判定变成恒真或恒假。
 #[test] fn a_candle_with_impossible_numbers_is_ignored() {
  let l=vec![line(&[(0.0,100.0),(100.0,100.0)],false,false)];
  assert_eq!(touched(&l,50,0,f64::NAN,101.0),None);
  // 高低颠倒不是坏帧：和客户端 `AlertEvaluator.touchHit` 一样先归一再判。
  assert_eq!(touched(&l,50,0,101.0,99.0),Some(100.0),"low 比 high 大时归一，和 Swift 同判");
  assert_eq!(touched(&l,50,0,102.0,101.0),None);
  assert_eq!(touched(&l,50,0,f64::INFINITY,99.0),None);
 }
 /// 一帧真的币安组合流消息。
 #[test] fn a_binance_frame_becomes_a_candle() {
  let text=r#"{"stream":"btcusdt@kline_1m","data":{"e":"kline","E":1800000000123,"s":"BTCUSDT","k":{"t":1800000000000,"T":1800000059999,"s":"BTCUSDT","i":"1m","f":1,"L":2,"o":"63000.0","c":"63120.5","h":"63200.0","l":"62900.0","v":"1.0","n":3,"x":false,"q":"1.0","V":"1.0","Q":"1.0","B":"0"}}}"#;
  let c=parse(text).expect("a kline frame");
  assert_eq!(c.symbol,"BTCUSDT");
  assert_eq!(c.open_time,1_800_000_000_000);
  assert_eq!(c.close,63_120.5);
  assert_eq!(c.high,63_200.0);
  assert_eq!(c.low,62_900.0);
  // `x:false` —— 这一根还没收。`condition='close'` 的提醒在这一帧上什么都不做。
  assert!(!c.closed);
  // 同一根收了的那一帧只有 `x` 不一样，`c` 到这时才是真正的收盘价。
  let settled=text.replace(r#""x":false"#,r#""x":true"#);
  assert!(parse(&settled).expect("the closing frame").closed);
  // `x` 缺了就当没收：漏一根，好过在盘中把它当成收盘价。
  let without=text.replace(r#","x":false"#,"");
  assert!(!parse(&without).expect("a frame without x").closed);
  // 别的事件（订阅回执、aggTrade）不是 K 线，跳过而不是崩。
  assert!(parse(r#"{"result":null,"id":1}"#).is_none());
  assert!(parse("not json").is_none());
 }
 // ————————————————— 收盘穿过（condition='close'） —————————————————

 /// **盘中穿过不算，收了才算。** 这就是用户选这一档想要的东西：一根 K 线在线上下扎了
 /// 十几次，只有它收在哪一侧算数。
 ///
 /// 这里只验判定本身（`crossed_on_close`）；「没收的帧根本不进来」由 `evaluate` 里的
 /// `if candle.closed` 保证，下面 `a_frame_that_has_not_closed_cannot_confirm_anything`
 /// 验那一层。
 #[test] fn a_close_that_crosses_the_line_confirms_it() {
  let l=vec![line(&[(0.0,100.0)],true,true)];
  // 上一根收在线下、这一根收在线上：穿过。
  assert_eq!(crossed_on_close(&l,50,0,95.0,105.0),Some(100.0));
  // 反过来也是穿过。
  assert_eq!(crossed_on_close(&l,50,0,105.0,95.0),Some(100.0));
 }
 /// 一直在同一侧，每一根都不算——不然提醒会在第一次评估时就自己响。
 #[test] fn closes_on_the_same_side_never_confirm() {
  let l=vec![line(&[(0.0,100.0)],true,true)];
  for (previous,close) in [(105.0,110.0),(110.0,101.0),(101.0,100.5),(95.0,90.0),(90.0,99.5)] {
   assert_eq!(crossed_on_close(&l,50,0,previous,close),None,"{previous} → {close} 没换过边");
  }
 }
 /// **正好收在线上算穿过**；但从线上走开不算，那一下上一根已经算过了。
 #[test] fn landing_exactly_on_the_line_counts_but_leaving_it_does_not() {
  let l=vec![line(&[(0.0,100.0)],true,true)];
  assert_eq!(crossed_on_close(&l,50,0,95.0,100.0),Some(100.0));
  assert_eq!(crossed_on_close(&l,50,0,105.0,100.0),Some(100.0));
  assert_eq!(crossed_on_close(&l,50,0,100.0,105.0),None,"上一根就收在线上，这一下是重复");
  assert_eq!(crossed_on_close(&l,50,0,100.0,95.0),None);
  assert_eq!(crossed_on_close(&l,50,0,100.0,100.0),None);
 }
 /// 阈值是**线在这一根上的价**，和 `touch` 取的是同一个值——趋势线随时间变。
 #[test] fn the_threshold_is_the_line_price_at_this_bar() {
  let l=vec![line(&[(0.0,100.0),(100.0,200.0)],false,false)];
  // 中点线价 150：145 → 155 穿过。
  assert_eq!(crossed_on_close(&l,50,0,145.0,155.0),Some(150.0));
  // 同样两根收盘价，挪到起点（线价 100）就没穿——两根都在线上方。
  assert_eq!(crossed_on_close(&l,0,0,145.0,155.0),None);
  // 线段之外、那一头又不延：没有价可比。
  assert_eq!(crossed_on_close(&l,200,0,145.0,155.0),None);
 }
 /// `armedAt` 和坏数字这两道闸，`close` 和 `touch` 是同一套。
 #[test] fn a_close_confirmation_respects_arming_and_bad_numbers() {
  let l=vec![line(&[(0.0,100.0)],true,true)];
  assert_eq!(crossed_on_close(&l,100,500,95.0,105.0),None,"armedAt 之前开盘的不算");
  assert_eq!(crossed_on_close(&l,500,500,95.0,105.0),Some(100.0));
  assert_eq!(crossed_on_close(&l,50,0,f64::NAN,105.0),None);
  assert_eq!(crossed_on_close(&l,50,0,95.0,f64::NAN),None);
 }
 /// 一组折线里任意一条被收盘穿过就算。
 #[test] fn any_line_in_the_set_can_be_crossed_on_close() {
  let l=vec![line(&[(0.0,100.0)],true,true),line(&[(0.0,200.0)],true,true)];
  assert_eq!(crossed_on_close(&l,50,0,195.0,205.0),Some(200.0));
 }
 /// 没收的帧确认不了任何事——判定的入口是 `evaluate` 里那个 `candle.closed`。
 ///
 /// 这条测试盯的是那一行 `if`：`crossed_on_close` 本身不认识「收没收」，一旦有人把
 /// 那道闸删了，盘中每一帧都会拿「此刻的价」当收盘价，`close` 就退化成一个更差的
 /// `touch`。所以这里直接模拟 `evaluate` 的取舍。
 #[test] fn a_frame_that_has_not_closed_cannot_confirm_anything() {
  let l=vec![line(&[(0.0,100.0)],true,true)];
  let previous=95.0;
  let confirm=|c:&Candle|if c.closed {crossed_on_close(&l,c.open_time,0,previous,c.close)} else {None};
  let intraday=Candle{symbol:"BTCUSDT".into(),open_time:50,low:90.0,high:110.0,close:105.0,closed:false};
  assert_eq!(confirm(&intraday),None,"盘中已经穿到线上面去了，但这一根没收");
  let settled=Candle{closed:true,..intraday};
  assert_eq!(confirm(&settled),Some(100.0),"同一根收了就算");
 }
 /// **`condition` 认不得的值退回 `touch`。** 一条哑掉的提醒是查不出来的那种 bug。
 #[test] fn an_unknown_condition_falls_back_to_touch() {
  assert_eq!(Condition::of("touch"),Condition::Touch);
  assert_eq!(Condition::of("close"),Condition::Close);
  assert_eq!(Condition::of("wick"),Condition::Touch);
  assert_eq!(Condition::of(""),Condition::Touch);
 }

 /// 裸价格提醒没有线，点开只开品种；画线提醒去那条线。
 #[test] fn a_price_alert_links_to_its_symbol() {
  let mut w=Watch{owner:Uuid::nil(),alert_id:"p".into(),symbol:"BTCUSDT".into(),drawing_id:None,title:"BTC 涨到 70,000".into(),
   lines:vec![line(&[(0.0,70_000.0)],true,true)],armed_at:0,condition:Condition::Touch,market:BINANCE.into(),webhook:None,webhook_text:None,note:None};
  assert_eq!(link_of(&w),"hkline://symbol/BTCUSDT");
  w.drawing_id=Some(String::new());
  assert_eq!(link_of(&w),"hkline://symbol/BTCUSDT");
  w.drawing_id=Some("trend-1".into());
  assert_eq!(link_of(&w),"hkline://drawing/BTCUSDT/trend-1");
 }
 /// 裸价格提醒就是一条两端都延伸的水平线：任何时刻、按 `touch` 判，碰到目标价就响。
 #[test] fn a_price_alert_fires_when_the_candle_reaches_the_target() {
  let l=vec![line(&[(1_800_000_000_000.0,70_000.0)],true,true)];
  assert_eq!(touched(&l,1_800_000_060_000,1_800_000_000_000,69_900.0,70_010.0),Some(70_000.0));
  assert_eq!(touched(&l,1_800_000_060_000,1_800_000_000_000,69_000.0,69_990.0),None);
  // 建之前开盘的那根不算。
  assert_eq!(touched(&l,1_799_999_940_000,1_800_000_000_000,69_900.0,70_010.0),None);
 }
 /// 复盘到点的推送和本地日历通知一字不差，点开去那一条复盘。
 #[test] fn a_review_due_notice_links_to_the_record() {
  let d=Due{owner:Uuid::nil(),alert_id:"binance/usd_m/BTCUSDT/r1".into(),symbol:"BTCUSDT".into(),review_id:"9F1E".into(),title:String::new(),due_at:0};
  let n=due_notice(&d);
  assert_eq!(n.title,"BTC 到点了");
  assert_eq!(n.body,"去看看这一笔判对了没有");
  assert_eq!(n.link,"hkline://review/9F1E");
  assert_eq!(n.kind,"reviewDue");
  let named=Due{title:"ETH 到点了".into(),..d};
  assert_eq!(due_notice(&named).title,"ETH 到点了");
 }
 /// 复盘到点只推给选了「服务端推送」通道的设备（`reviewDue` 类 token）；别的触发类照旧
 /// 推给 `alerts`。推给 `alerts` 就会和手机上那条本地日历通知撞成两条。
 #[test] fn review_due_pushes_only_reach_review_due_tokens() {
  assert_eq!(token_kind("reviewDue"),"reviewDue");
  for kind in ["alert","watchMove",""] {assert_eq!(token_kind(kind),"alerts")}
  let migration=include_str!("../migrations/0023_review_due_push_token.sql");
  assert!(migration.contains("'alerts','liveActivity','widget','reviewDue'"),"0023 要放行 reviewDue，旧的三类一个不能少");
 }

 /// 通知正文里的价要看得清每一位，小币种也是。
 #[test] fn the_notification_shows_a_readable_price() {
  assert_eq!(money(63_120.0),"63,120");
  assert_eq!(money(1_234_567.0),"1,234,567");
  assert_eq!(money(12.5),"12.50");
  assert_eq!(money(0.1234),"0.1234");
  assert_eq!(money(0.00001234),"0.00001234");
 }
 /// 一帧 `@ticker`：实时活动要的 24h 涨跌幅只有这条流里有，而契约里它是小数不是百分数。
 #[test] fn a_ticker_frame_carries_the_twenty_four_hour_change() {
  let text=r#"{"stream":"btcusdt@ticker","data":{"e":"24hrTicker","E":1800000000123,"s":"BTCUSDT","p":"-780.0","P":"-1.230","w":"63000.0","c":"63120.5","Q":"1.0","o":"63900.5","h":"64000.0","l":"62000.0","v":"100.0","q":"1.0","O":1799913600000,"C":1800000000123,"F":1,"L":2,"n":3}}"#;
  let (symbol,price,change)=parse_ticker(text).expect("a ticker frame");
  assert_eq!(symbol,"BTCUSDT");
  assert_eq!(price,Some(63_120.5));
  assert_eq!(change,Some(-0.0123),"P 是百分数，契约里的 change 是小数");
  // K 线帧不是 ticker，ticker 帧也不是 K 线：两条解析各认各的。
  assert!(parse_ticker(r#"{"data":{"e":"kline","s":"BTCUSDT","k":{}}}"#).is_none());
  assert!(parse(text).is_none());
  // 缺字段就是取不到，不拿 0 冒充。
  let without=text.replace(r#","P":"-1.230""#,"");
  let (_,_,change)=parse_ticker(&without).expect("still a ticker frame");
  assert_eq!(change,None);
 }
 /// 订阅串就是网关一直在用的那条路径的形状，外加实时活动要的那几条 `@ticker`。
 #[test] fn the_stream_url_is_the_one_measured_on_the_vps() {
  assert_eq!(STREAM,"wss://fstream.binance.com/market/stream");
  let watches=vec![
   Watch{owner:Uuid::nil(),alert_id:"a".into(),symbol:"ETHUSDT".into(),drawing_id:None,title:String::new(),lines:vec![],armed_at:0,condition:Condition::Touch,market:BINANCE.into(),webhook:None,webhook_text:None,note:None},
   Watch{owner:Uuid::nil(),alert_id:"b".into(),symbol:"BTCUSDT".into(),drawing_id:None,title:String::new(),lines:vec![],armed_at:0,condition:Condition::Touch,market:BINANCE.into(),webhook:None,webhook_text:None,note:None},
   Watch{owner:Uuid::nil(),alert_id:"c".into(),symbol:"BTCUSDT".into(),drawing_id:None,title:String::new(),lines:vec![],armed_at:0,condition:Condition::Close,market:BINANCE.into(),webhook:None,webhook_text:None,note:None},
  ];
  let symbols=symbols_of(&watches,&Default::default());
  assert_eq!(symbols,vec!["BTCUSDT".to_string(),"ETHUSDT".to_string()],"同一品种只订一次，顺序稳定");
  // 开着自选波动提醒的人的自选也要订，和提醒品种合并去重。
  let movers:std::collections::BTreeSet<String>=["SOLUSDT".to_string(),"BTCUSDT".to_string()].into();
  assert_eq!(symbols_of(&watches,&movers),vec!["BTCUSDT".to_string(),"ETHUSDT".to_string(),"SOLUSDT".to_string()]);
  // 没有实时活动时和从前一字不差：常态下上游负载一点没变。
  assert_eq!(streams_of(&symbols,&[]).join("/"),"btcusdt@kline_1m/ethusdt@kline_1m");
  // 有活动盯着 BTC 时才多一条 @ticker，而且只多那一个品种的。
  assert_eq!(streams_of(&symbols,&["BTCUSDT".to_string()]).join("/"),"btcusdt@kline_1m/ethusdt@kline_1m/btcusdt@ticker");
  // 没有提醒的品种就算登记过活动也不订：那条活动下一拍就会被结束掉。
  assert_eq!(streams_of(&symbols,&["SOLUSDT".to_string()]).join("/"),"btcusdt@kline_1m/ethusdt@kline_1m");
  // 一条连接 200 条流封顶，加 ticker 也不许越过它。
  let many:Vec<String>=(0..MAX_STREAMS).map(|i|format!("S{i}USDT")).collect();
  assert_eq!(streams_of(&many,&many).len(),MAX_STREAMS);
 }
 /// Coinbase 没有 1 分钟推送：逐笔拼出来的 K 线要在极值刷新时判触线、在收完时判收盘。
 #[test] fn coinbase_trades_build_minute_bars_that_close_on_the_next_minute_or_after_settling() {
  let mut bars=MinuteBars::default();
  let t0=1_790_000_040_000; // 某一分钟的开头
  let first=bars.trade("BTC-USD",t0+1_000,100.0);
  assert_eq!(first.len(),1);assert!(!first[0].closed);
  assert!(bars.trade("BTC-USD",t0+2_000,100.0).is_empty(),"没刷新极值就不重判");
  let up=bars.trade("BTC-USD",t0+3_000,101.0);
  assert_eq!((up[0].low,up[0].high,up[0].closed),(100.0,101.0,false));
  // 下一分钟第一笔：先交上一根（收了，收盘 101），再开新的一根。
  let next=bars.trade("BTC-USD",t0+61_000,99.0);
  assert_eq!(next.len(),2);
  assert!(next[0].closed&&next[0].close==101.0&&next[0].open_time==t0);
  assert!(!next[1].closed&&next[1].open_time==t0+60_000);
  // 迟到的上一分钟成交不再改已经收了的那一根。
  assert!(bars.trade("BTC-USD",t0+59_000,50.0).is_empty());
  // 冷门品种一分钟没有下一笔：过了 SETTLE_MS 由定时器收。
  assert!(bars.settle(t0+120_000+SETTLE_MS-1).is_empty());
  let settled=bars.settle(t0+120_000+SETTLE_MS);
  assert_eq!(settled.len(),1);assert!(settled[0].closed&&settled[0].close==99.0);
 }
 #[test] fn coinbase_trade_frames_skip_the_snapshot_and_come_out_in_trade_order() {
  let frame=r#"{"channel":"market_trades","events":[
   {"type":"snapshot","trades":[{"trade_id":"1","product_id":"BTC-USD","price":"1","size":"1","side":"BUY","time":"2026-09-23T00:00:00Z"}]},
   {"type":"update","trades":[
    {"trade_id":"12","product_id":"BTC-USD","price":"101.5","size":"1","side":"BUY","time":"2026-09-23T00:00:01.250Z"},
    {"trade_id":"11","product_id":"BTC-USD","price":"101","size":"1","side":"SELL","time":"2026-09-23T00:00:01.250Z"}]}]}"#;
  let trades=coinbase_trades(frame);
  assert_eq!(trades.iter().map(|t|t.2).collect::<Vec<_>>(),vec![101.0,101.5]);
  assert_eq!(trades[0].1%1000,250);
  assert!(coinbase_trades(r#"{"channel":"heartbeats","events":[]}"#).is_empty());
 }
 #[test] fn coinbase_alerts_open_the_coinbase_chart_and_read_like_the_app() {
  let mut w=Watch{owner:Uuid::nil(),alert_id:"a".into(),symbol:"BTC-USD".into(),drawing_id:Some("d1".into()),title:String::new(),lines:vec![],armed_at:0,condition:Condition::Touch,market:COINBASE.into(),webhook:None,webhook_text:None,note:None};
  assert_eq!(link_of(&w),"hkline://drawing/coinbase/spot/BTC-USD/d1");
  assert_eq!(display_symbol(&w.market,&w.symbol),"BTC/USD");
  w.drawing_id=None;
  assert_eq!(link_of(&w),"hkline://symbol/coinbase/spot/BTC-USD","裸价格提醒也要开 Coinbase 那只");
  w.market=BINANCE.into();w.symbol="BTCUSDT".into();w.drawing_id=Some("d1".into());
  assert_eq!(link_of(&w),"hkline://drawing/BTCUSDT/d1","币安沿用老链接，老客户端也认");
  assert_eq!(venue_of(COINBASE),"coinbase");assert_eq!(venue_of(BINANCE),"binance");
 }

 // ——— A5：锚点预排序、判定与做事解耦、断线补 K 线 ———

 fn watch(alert_id:&str,condition:Condition,lines:Vec<Line>)->Watch {
  Watch{owner:Uuid::nil(),alert_id:alert_id.into(),symbol:"BTCUSDT".into(),drawing_id:None,title:String::new(),
   lines,armed_at:0,condition,market:BINANCE.into(),webhook:None,webhook_text:None,note:None}
 }
 fn bar(open_time:i64,low:f64,high:f64,close:f64,closed:bool)->Candle {
  Candle{symbol:"BTCUSDT".into(),open_time,low,high,close,closed}
 }
 fn fired(rx:&mut tokio::sync::mpsc::Receiver<Effect>)->Vec<(String,f64)> {
  let mut out=vec![];
  while let Ok(e)=rx.try_recv() {if let Effect::Fire{watch,price,..}=e {out.push((watch.alert_id,price))}}
  out
 }

 /// 排好序的折线走快路径，算出来的价和乱序那条慢路径一模一样。
 #[test] fn sorted_and_unsorted_points_price_the_same() {
  let sorted=line(&[(0.0,100.0),(100.0,200.0),(300.0,0.0)],true,true);
  let shuffled=line(&[(300.0,0.0),(0.0,100.0),(100.0,200.0)],true,true);
  assert!(sorted.points.is_sorted_by(|a,b|a.t<=b.t));
  for t in [-50,0,50,100,200,300,400] {assert_eq!(price_at(&sorted,t),price_at(&shuffled,t),"t={t}")}
  let mut fixed=shuffled.clone();sort_points(&mut fixed.points);
  assert_eq!(fixed.points,sorted.points,"读库时排一次，之后就是快路径");
 }
 /// 物化时把 `lines` 里的点按时间排好再落库；形状不认识的部分原样放过。
 #[test] fn materialized_lines_are_stored_sorted() {
  let v=sorted_lines(json!([{"points":[{"t":300,"p":1},{"t":0,"p":2},{"t":100,"p":3}],"extendLeft":true},{"extendRight":true},"odd"]));
  assert_eq!(v,json!([{"points":[{"t":0,"p":2},{"t":100,"p":3},{"t":300,"p":1}],"extendLeft":true},{"extendRight":true},"odd"]));
  assert_eq!(sorted_lines(json!({"not":"an array"})),json!({"not":"an array"}));
 }

 /// 判中了只往队列里放一件事就返回：评估器不 await 写库和推送。摘掉的那条在做完
 /// 之前不会被刷新读回来再判一次。
 #[test] fn a_hit_is_handed_to_the_side_effect_queue() {
  let (effects,mut rx)=Effects::channel(8);
  let flat=vec![line(&[(0.0,100.0)],true,true)];
  let mut watches=vec![watch("a1",Condition::Touch,flat.clone()),watch("a2",Condition::Touch,vec![line(&[(0.0,500.0)],true,true)])];
  let mut closes=Closes::new();
  evaluate(&effects,&mut watches,&mut closes,&BTreeMap::new(),&bar(60_000,99.0,101.0,100.5,false));
  assert_eq!(fired(&mut rx),vec![("a1".to_string(),100.5)]);
  assert_eq!(watches.iter().map(|w|w.alert_id.as_str()).collect::<Vec<_>>(),vec!["a2"],"判中的那条从内存里摘掉");
  // 十秒刷新读回来的时候它在库里还是 active：交出去、还没做完的不再放回来。
  let reloaded=effects.idle(vec![watch("a1",Condition::Touch,flat.clone()),watch("a2",Condition::Touch,vec![])]);
  assert_eq!(reloaded.iter().map(|w|w.alert_id.as_str()).collect::<Vec<_>>(),vec!["a2"]);
  // 做完（不论成败）就放掉：失败的那条下一轮刷新读回来重判。
  effects.busy.done(Uuid::nil(),"a1");
  assert_eq!(effects.idle(vec![watch("a1",Condition::Touch,flat)]).len(),1);
 }
 /// 队列排满时丢掉这一件、不等待，并且把这条提醒放掉，让下一轮刷新重新读回来。
 #[test] fn a_full_queue_drops_the_effect_without_waiting_and_releases_the_alert() {
  let (effects,mut rx)=Effects::channel(1);
  effects.send(Effect::Beat(BTreeMap::new()));
  let mut watches=vec![watch("a1",Condition::Touch,vec![line(&[(0.0,100.0)],true,true)])];
  evaluate(&effects,&mut watches,&mut Closes::new(),&BTreeMap::new(),&bar(60_000,99.0,101.0,100.0,false));
  assert!(watches.is_empty());
  assert!(!effects.busy.holds(Uuid::nil(),"a1"),"没交出去的不能一直占着");
  assert!(matches!(rx.try_recv(),Ok(Effect::Beat(_))));
  assert!(rx.try_recv().is_err());
  // 复盘到点同一条规矩：重复读到的只交一次；交不出去就放掉。
  let (effects,mut rx)=Effects::channel(4);
  let due=|id:&str|Due{owner:Uuid::nil(),alert_id:id.into(),symbol:"BTCUSDT".into(),review_id:"r".into(),title:String::new(),due_at:0};
  effects.due(vec![due("r1")]);effects.due(vec![due("r1"),due("r2")]);
  let mut seen=vec![];
  while let Ok(Effect::Due(d)) = rx.try_recv() {seen.extend(d.into_iter().map(|d|d.alert_id))}
  assert_eq!(seen,vec!["r1","r2"]);
 }
 /// 收盘穿越：断线期间收掉的那根从 REST 补回来按收盘判；同一根再从流里收一遍，
 /// 不再判第二次，也不把「上一根」改成它自己。
 #[test] fn a_backfilled_close_confirms_once_and_the_stream_repeat_is_ignored() {
  let (effects,mut rx)=Effects::channel(8);
  let l=vec![line(&[(0.0,102.0)],true,true)];
  let mut watches=vec![watch("c1",Condition::Close,l.clone())];
  let mut closes:Closes=[("BTCUSDT".to_string(),(0,100.0))].into_iter().collect();
  // 补回来的第 1、2 分钟：第 1 分钟收在线下，第 2 分钟收上去了。
  for c in [bar(60_000,99.0,101.0,101.0,true),bar(120_000,101.0,104.0,103.0,true)] {evaluate(&effects,&mut watches,&mut closes,&BTreeMap::new(),&c)}
  assert_eq!(fired(&mut rx),vec![("c1".to_string(),103.0)]);
  assert_eq!(closes["BTCUSDT"],(120_000,103.0));
  // 流里又收了一遍第 2 分钟（补的时候它刚收）：换一条同样的提醒来看，它不会被这一帧判中。
  watches=vec![watch("c2",Condition::Close,l)];
  evaluate(&effects,&mut watches,&mut closes,&BTreeMap::new(),&bar(120_000,101.0,104.0,103.0,true));
  assert!(fired(&mut rx).is_empty());
  assert_eq!(closes["BTCUSDT"],(120_000,103.0),"已经判过的那根不改「上一根」");
  // 下一根照常拿第 2 分钟比。
  evaluate(&effects,&mut watches,&mut closes,&BTreeMap::new(),&bar(180_000,100.0,103.0,101.0,true));
  assert_eq!(fired(&mut rx),vec![("c2".to_string(),101.0)]);
 }
 /// 该补哪一段：只补已经收了的整分钟，最多一小时；没跨过分钟线的重连一次 REST 都不发。
 #[test] fn the_gap_covers_closed_minutes_only_and_at_most_an_hour() {
  let m=1_800_000_000_000;
  assert_eq!(m%60_000,0,"整分钟");
  assert_eq!(gap(m,m+59_000),None,"断了几秒，那一根还没收");
  assert_eq!(gap(m,m+120_500),Some((m+60_000,m+120_000)),"第 1 分钟收了，第 2 分钟还没收");
  assert_eq!(gap(m,m+60_000),None);
  assert_eq!(gap(m,m+3*3_600_000+1),Some((m+3*3_600_000-BACKFILL_MS,m+3*3_600_000)),"再往前的不补");
 }
 /// 币安 `/fapi/v1/klines` 一页换成已收盘的 K 线，窗口外的与读不出的都丢掉。
 #[test] fn binance_kline_rows_become_closed_candles() {
  let v=json!([
   [0,"1","2","0.5","1.5","10",59_999,"0",1,"0","0","0"],
   [60_000,"1.5","3","1","2.5","10",119_999,"0",1,"0","0","0"],
   [120_000,"2.5","4","2","x","10",179_999,"0",1,"0","0","0"],
   [180_000,"3","5","2","4","10",239_999,"0",1,"0","0","0"],
  ]);
  let rows=binance_rows("BTCUSDT",&v,60_000,180_000);
  assert_eq!(rows,vec![Candle{symbol:"BTCUSDT".into(),open_time:60_000,low:1.0,high:3.0,close:2.5,closed:true}]);
  assert!(binance_rows("BTCUSDT",&json!({"code":-1121}),0,1).is_empty());
 }
 /// Coinbase 的原生 K 线（秒、字符串价）同样换成已收盘的 1 分钟 K 线。
 #[test] fn coinbase_candles_become_closed_candles() {
  let c=|start:i64,close:&str|crate::venues::coinbase::Candle{start,open:"1".into(),high:"3".into(),low:"0.5".into(),close:close.into(),volume:"1".into()};
  let rows=coinbase_rows("BTC-USD",vec![c(60,"2"),c(120,"nan?"),c(180,"2")],60_000,180_000);
  assert_eq!(rows,vec![Candle{symbol:"BTC-USD".into(),open_time:60_000,low:0.5,high:3.0,close:2.0,closed:true}]);
 }

 // ——— 从图上加提醒：备注、Webhook ———

 /// 模板渲染逐字对：契约里那一句默认文案。
 #[test] fn the_default_webhook_text_reads_exactly_like_the_contract() {
  let f=WebhookFill{market:BINANCE,symbol:"BTCUSDT",condition:Condition::Touch,target:Some(84_662.2),price:84_670.5,at:1_758_732_240_000,note:""};
  assert_eq!(render_webhook_text(None,&f),"BTC 碰到 84,662.2，现价 84,670.5");
  assert_eq!(render_webhook_text(Some(""),&f),"BTC 碰到 84,662.2，现价 84,670.5","空模板用默认");
  assert_eq!(render_webhook_text(Some("  "),&f),"BTC 碰到 84,662.2，现价 84,670.5","全是空白也算空");
 }
 /// 每一个占位符都换得对；认不得的、没合上的原样留着；备注里的占位符不会被二次替换。
 #[test] fn every_webhook_placeholder_is_filled_once() {
  let f=WebhookFill{market:BINANCE,symbol:"BTCUSDT",condition:Condition::Close,target:Some(84_662.2),price:84_670.5,at:1_758_732_240_000,note:"看{价格}"};
  assert_eq!(render_webhook_text(Some("{品种}|{代号}|{价格}|{目标价}|{条件}|{时间}|{备注}"),&f),
   "BTC|BTCUSDT|84,670.5|84,662.2|收盘穿过|2025-09-24T16:44:00Z|看{价格}");
  assert_eq!(render_webhook_text(Some("{不认识} {{品种}} {价格"),&f),"{不认识} {BTC} {价格");
  let coinbase=WebhookFill{market:COINBASE,symbol:"BTC-USD",target:None,note:"",..f};
  assert_eq!(render_webhook_text(Some("{品种} {代号} [{目标价}] [{备注}]"),&coinbase),"BTC/USD BTC-USD [] []");
 }
 #[test] fn the_webhook_name_drops_usdt_only_on_binance() {
  assert_eq!(webhook_name(BINANCE,"BTCUSDT"),"BTC");
  assert_eq!(webhook_name(BINANCE,"BTCUSDC"),"BTCUSDC","没有 USDT 尾巴就原样");
  assert_eq!(webhook_name(BINANCE,"USDT"),"USDT");
  assert_eq!(webhook_name(COINBASE,"BTC-USD"),"BTC/USD");
 }
 /// Webhook 的价：千分位 + 原样小数，不按量级截。
 #[test] fn webhook_prices_keep_the_digits_the_user_typed() {
  assert_eq!(webhook_money(84_662.2),"84,662.2");
  assert_eq!(webhook_money(84_662.200_000_000_01),"84,662.2");
  assert_eq!(webhook_money(63_120.0),"63,120");
  assert_eq!(webhook_money(1_234_567.891),"1,234,567.891");
  assert_eq!(webhook_money(0.000_012_34),"0.00001234");
  assert_eq!(webhook_money(-1_500.5),"-1,500.5");
  assert_eq!(webhook_money(12.5),"12.5");
 }
 #[test] fn the_webhook_time_is_utc_to_the_second() {
  assert_eq!(iso_time(1_758_732_240_000),"2025-09-24T16:44:00Z");
  assert_eq!(iso_time(1_758_732_240_999),"2025-09-24T16:44:00Z");
 }
 fn hooked(note:Option<&str>)->Watch {
  let mut w=watch("binance/usd_m/BTCUSDT/a1",Condition::Touch,vec![line(&[(0.0,84_662.2)],true,true)]);
  w.title="BTC 涨到 84,662.2".into();w.webhook=Some("https://hooks.example.com/x".into());w.note=note.map(str::to_string);
  w
 }
 /// POST 出去的 body 和字段契约一个键都不差。
 #[test] fn the_webhook_body_carries_every_contract_key() {
  let at=1_758_732_240_000;
  assert_eq!(webhook_body(&hooked(None),84_670.5,at),json!({
   "event":"alert","alertId":"binance/usd_m/BTCUSDT/a1","symbol":"BTCUSDT","market":"binance/usd_m","name":"BTC",
   "title":"BTC 涨到 84,662.2","condition":"touch","once":true,"target":84_662.2,"price":84_670.5,"firedAt":at,
   "time":"2025-09-24T16:44:00Z","note":"","text":"BTC 碰到 84,662.2，现价 84,670.5"}));
  let mut w=hooked(Some("突破加仓"));w.webhook_text=Some("{品种} {备注}".into());w.title=String::new();
  let body=webhook_body(&w,84_670.5,at);
  assert_eq!(body["note"],json!("突破加仓"));assert_eq!(body["text"],json!("BTC 突破加仓"));
  assert_eq!(body["title"],json!("BTCUSDT 触到你画的线"),"没有标题时和推送标题同一个兜底");
 }
 /// APNs 正文：有备注接在现价后面，没有就照旧。
 #[test] fn the_push_body_appends_the_note() {
  assert_eq!(alert_body(84_671.2,None),"现价 84,671");
  assert_eq!(alert_body(84_671.2,Some("")),"现价 84,671");
  assert_eq!(alert_body(84_671.2,Some(" 突破加仓 ")),"现价 84,671 · 突破加仓");
 }
 /// 本机、内网地址不发；公网地址和域名照发。
 #[test] fn webhooks_to_local_addresses_are_refused() {
  for ok in ["https://hooks.example.com/x","http://8.8.8.8/x","https://[2001:4860::8888]/x"] {assert!(webhook_allowed(ok),"{ok}")}
  for bad in ["http://127.0.0.1:8794/v1","http://localhost/x","http://a.localhost/x","http://10.0.0.1/","http://192.168.1.1/","http://172.16.0.1/",
   "http://169.254.169.254/latest","http://0.0.0.0/","http://[::1]/","http://[fd00::1]/","http://[fe80::1]/","http://[::ffff:127.0.0.1]/","http://100.64.0.1/","ftp://example.com/","not a url"] {
   assert!(!webhook_allowed(bad),"{bad}")
  }
  assert_eq!(webhook_host("https://api.telegram.org/bot123:SECRET/sendMessage"),"api.telegram.org","日志里不带密钥");
 }

 /// 本机起一个假接收端：按顺序回 `statuses` 里的状态码，把每一个请求（头 + body）交回来。
 async fn receiver(statuses:Vec<u16>)->(String,tokio::sync::mpsc::UnboundedReceiver<(String,Vec<u8>)>) {
  use tokio::io::{AsyncReadExt,AsyncWriteExt};
  let listener=tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
  let url=format!("http://{}/hook",listener.local_addr().unwrap());
  let (tx,rx)=tokio::sync::mpsc::unbounded_channel();
  tokio::spawn(async move {
   for status in statuses {
    let Ok((mut socket,_))=listener.accept().await else {return};
    let mut buffer=vec![];let mut chunk=[0u8;4096];
    let (head,body)=loop {
     let n=socket.read(&mut chunk).await.unwrap();if n==0 {return}
     buffer.extend_from_slice(&chunk[..n]);
     let Some(split)=buffer.windows(4).position(|w|w==b"\r\n\r\n") else {continue};
     let head=String::from_utf8_lossy(&buffer[..split]).to_string();
     let length=head.lines().find_map(|l|l.to_ascii_lowercase().strip_prefix("content-length:").map(|v|v.trim().parse::<usize>().unwrap())).unwrap_or(0);
     while buffer.len()<split+4+length {let n=socket.read(&mut chunk).await.unwrap();if n==0 {break};buffer.extend_from_slice(&chunk[..n])}
     break (head,buffer[split+4..split+4+length].to_vec());
    };
    tx.send((head,body)).unwrap();
    socket.write_all(format!("HTTP/1.1 {status} X\r\nContent-Length: 0\r\nConnection: close\r\n\r\n").as_bytes()).await.unwrap();
    socket.shutdown().await.ok();
   }
  });
  (url,rx)
 }
 fn header<'a>(head:&'a str,name:&str)->Option<&'a str> {
  head.lines().find_map(|l|l.split_once(':').filter(|(k,_)|k.eq_ignore_ascii_case(name)).map(|(_,v)|v.trim()))
 }
 /// 真的发得出去：POST、JSON、UA；5xx 之后重试一次就成。
 #[tokio::test] async fn a_webhook_is_posted_and_retried_once_after_a_server_error() {
  let (url,mut rx)=receiver(vec![503,200]).await;
  let body=webhook_body(&hooked(Some("看量")),84_670.5,1_758_732_240_000);
  deliver_webhook(crate::http::shared(),&url,&body,Duration::from_millis(20)).await.expect("the retry succeeds");
  for _ in 0..2 {
   let (head,bytes)=rx.recv().await.unwrap();
   assert!(head.starts_with("POST /hook HTTP/1.1"),"{head}");
   assert_eq!(header(&head,"content-type"),Some("application/json"));
   assert_eq!(header(&head,"user-agent"),Some("Hkline-Alerts/1"),"不是共享客户端的浏览器 UA");
   let sent:Value=serde_json::from_slice(&bytes).unwrap();
   assert_eq!(sent,body);
   assert_eq!(sent["text"],json!("BTC 碰到 84,662.2，现价 84,670.5"));
  }
  assert!(rx.try_recv().is_err(),"成了就不再发");
 }
 /// 两次都 5xx：只试两次，报最后一次的原因。4xx：对面明确不收，不重试。
 #[tokio::test] async fn a_webhook_gives_up_after_one_retry_and_never_retries_a_refusal() {
  let (url,mut rx)=receiver(vec![500,502,200]).await;
  let body=json!({"event":"alert"});
  assert_eq!(deliver_webhook(crate::http::shared(),&url,&body,Duration::from_millis(20)).await,Err("HTTP 502".into()));
  assert!(rx.recv().await.is_some()&&rx.recv().await.is_some());
  assert!(rx.try_recv().is_err(),"只重试一次");
  let (url,mut rx)=receiver(vec![404,200]).await;
  assert_eq!(deliver_webhook(crate::http::shared(),&url,&body,Duration::from_millis(20)).await,Err("HTTP 404".into()));
  assert!(rx.recv().await.is_some());
  tokio::time::sleep(Duration::from_millis(100)).await;
  assert!(rx.try_recv().is_err(),"4xx 不重试");
 }
 /// 连不上（对面没人听）也按网络错误重试一次，最后报「连不上」，不带地址。
 #[tokio::test] async fn a_webhook_to_nobody_retries_then_reports_a_connect_failure() {
  let port={let l=std::net::TcpListener::bind("127.0.0.1:0").unwrap();l.local_addr().unwrap().port()};
  let started=std::time::Instant::now();
  let result=deliver_webhook(crate::http::shared(),&format!("http://127.0.0.1:{port}/hook"),&json!({}),Duration::from_millis(200)).await;
  assert_eq!(result,Err("could not connect".into()));
  assert!(started.elapsed()>=Duration::from_millis(200),"中间等了一次重试间隔");
 }
}
