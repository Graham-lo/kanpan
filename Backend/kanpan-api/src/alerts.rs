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
 let t=t as f64;
 let ps=&line.points;
 let first=ps.first()?;
 let last=ps.last()?;
 // 客户端理应按时间递增给点，但「理应」不是保证：一条乱序的折线会让下面的区间查找
 // 找不到任何一段，提醒就此变成哑的、而且没有任何迹象。排一次的代价可以忽略。
 let mut sorted:Vec<Point>=ps.clone();
 sorted.sort_by(|a,b|a.t.partial_cmp(&b.t).unwrap_or(std::cmp::Ordering::Equal));
 let (first,last)=(if sorted[0].t<=first.t {sorted[0]} else {*first},if sorted[sorted.len()-1].t>=last.t {sorted[sorted.len()-1]} else {*last});
 if t<first.t {
  if !line.extend_left {return None}
  return Some(extrapolate(&sorted,t,true))
 }
 if t>last.t {
  if !line.extend_right {return None}
  return Some(extrapolate(&sorted,t,false))
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
 if !low.is_finite()||!high.is_finite()||low>high {return None}
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
 sqlx::query("INSERT INTO alert_watches(user_id,alert_id,kind,symbol,market,drawing_id,lines,condition,title,armed_at,status,fired_at,fired_price,due_at,review_id,updated_at) \
  VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,now()) \
  ON CONFLICT(user_id,alert_id) DO UPDATE SET kind=excluded.kind,symbol=excluded.symbol,market=excluded.market,drawing_id=excluded.drawing_id,\
  lines=excluded.lines,condition=excluded.condition,title=excluded.title,armed_at=excluded.armed_at,status=excluded.status,\
  fired_at=excluded.fired_at,fired_price=excluded.fired_price,due_at=excluded.due_at,review_id=excluded.review_id,updated_at=now()")
  .bind(owner).bind(&object.id).bind(text("kind")).bind(text("symbol"))
  .bind(object.body.get("market").and_then(Value::as_str).unwrap_or("binance/usd_m"))
  .bind(object.body.get("drawingID").and_then(Value::as_str))
  .bind(object.body.get("lines").cloned().unwrap_or_else(||json!([])))
  .bind(object.body.get("condition").and_then(Value::as_str).unwrap_or("touch"))
  .bind(text("title"))
  .bind(number("armedAt").unwrap_or_default() as i64)
  .bind(object.body.get("status").and_then(Value::as_str).unwrap_or("active"))
  .bind(number("firedAt").map(|v|v as i64))
  .bind(number("firedPrice"))
  .bind(number("dueAt").map(|v|v as i64))
  .bind(object.body.get("reviewID").and_then(Value::as_str))
  .execute(&mut **tx).await?;
 Ok(())
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
 if !matches!(v.kind.as_str(),"alerts"|"liveActivity"|"widget") {return Err(ApiError::bad("invalid_token_kind"))}
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

/// 评估器在内存里保有的一条活动提醒。
#[derive(Clone,Debug)]
struct Watch {
 owner:Uuid,alert_id:String,symbol:String,drawing_id:Option<String>,
 title:String,lines:Vec<Line>,armed_at:i64,condition:Condition,
}

/// 一条还没到点的复盘到点提醒。它不看价，不进 K 线流，只在每轮刷新时看一眼钟。
#[derive(Clone,Debug)]
struct Due {owner:Uuid,alert_id:String,symbol:String,review_id:String,title:String,due_at:i64}

/// 一轮刷新读回来的东西：所有人的活动价格提醒（画线 + 裸价格）、已经到点的复盘提醒、
/// 自选波动提醒开着的人，以及其中哪些品种正被实时活动盯着。
struct Loaded {watches:Vec<Watch>,due:Vec<Due>,movers:Vec<crate::watch_move::Mover>,live:Vec<String>}

/// 把所有用户的活动提醒读成一张内存表。
///
/// 为什么逐个用户开事务：这两张表和同步表一样挂着 FORCE ROW LEVEL SECURITY，运行期角色
/// 既不是属主也没有 BYPASSRLS，所以**没有**一条能一次看见所有人的通道——这是故意的。
/// 代价是一次刷新 N 个短事务，而 N 是个位数（`maintenance::cleanup` 用的同一套分页）。
async fn load(s:&AppState)->Result<Loaded> {
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
   let rows=sqlx::query("SELECT alert_id,symbol,drawing_id,title,lines,armed_at,condition FROM alert_watches WHERE user_id=$1 AND status='active' AND kind IN ('drawing','price')")
    .bind(owner).fetch_all(&mut *tx).await?;
   // 复盘到点只读**已经到点**的那几条：没到点的留在库里，下一轮再看，不占内存。
   let now=chrono::Utc::now().timestamp_millis();
   for r in sqlx::query("SELECT alert_id,symbol,title,due_at,review_id FROM alert_watches WHERE user_id=$1 AND status='active' AND kind='reviewDue' AND due_at IS NOT NULL AND due_at<=$2")
    .bind(owner).bind(now).fetch_all(&mut *tx).await? {
    let review_id:Option<String>=r.get("review_id");
    due.push(Due{owner:*owner,alert_id:r.get("alert_id"),symbol:r.get("symbol"),review_id:review_id.unwrap_or_default(),
     title:r.get("title"),due_at:r.get::<Option<i64>,_>("due_at").unwrap_or(now)});
   }
   if let Some(mover)=crate::watch_move::load_mover(&mut tx,*owner).await.unwrap_or(None) {movers.push(mover)}
   // 同一个事务里顺手问一句「这个人有实时活动盯着哪些品种」：那些品种要多订一条
   // `@ticker`（24h 涨跌幅只有那条流里有）。没有活动的时候这一句什么都不返回，
   // 订阅串和从前一模一样。
   live.extend(crate::live_activity::active_symbols(&mut tx,*owner).await.unwrap_or_default());
   tx.commit().await?;
   for r in rows {
    let lines:Vec<Line>=match serde_json::from_value(r.get::<Value,_>("lines")) {
     Ok(v)=>v,
     // 形状对不上就当这条提醒不存在，而不是让整轮刷新失败——一条坏数据不该让所有人
     // 的提醒一起停摆。白名单那一层已经挡过一次，真走到这里说明有别的路写进去了。
     Err(e)=>{tracing::warn!("An alert has unusable geometry and will not be evaluated: {e}");continue}
    };
    out.push(Watch{owner:*owner,alert_id:r.get("alert_id"),symbol:r.get("symbol"),
     drawing_id:r.get("drawing_id"),title:r.get("title"),lines,armed_at:r.get("armed_at"),
     condition:Condition::of(&r.get::<String,_>("condition"))});
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
 let present:bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM sync_objects WHERE user_id=$1 AND collection='alerts' AND id=$2 AND NOT deleted)")
  .bind(owner).bind(alert_id).fetch_one(&mut *tx).await?;
 if !present {
  sqlx::query("DELETE FROM alert_watches WHERE user_id=$1 AND alert_id=$2").bind(owner).bind(alert_id).execute(&mut *tx).await?;
  tx.commit().await?;return Ok(false)
 }
 let mut fields:BTreeMap<String,Value>=[("status",json!("fired")),("firedAt",json!(at))]
  .into_iter().map(|(k,v)|(k.to_string(),v)).collect();
 if let Some(price)=price {fields.insert("firedPrice".into(),json!(price));}
 crate::sync::apply_server(&mut tx,owner,"alerts",alert_id,fields).await?;
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
 let Some(apns)=apns else {
  // 没有 APNs 密钥时这就是终点，而且是一个完整的终点：状态已经落库、op 已经写进
  // alerts 集合，客户端下次拉同步（开 app 就会拉）照样看得到这条已触发的提醒。
  // 这里只留一行 info 当证据，不排队、不重试——没有密钥不是一个会自己好起来的错误。
  tracing::info!("{} triggered {} at {}; recorded and synced, not pushed (no APNs key)",w.symbol,w.alert_id,money(price));
  return Ok(())
 };
 let title=if w.title.is_empty() {format!("{} 触到你画的线",w.symbol)} else {w.title.clone()};
 notify(s,apns,w.owner,&Notice{title,body:format!("现价 {}",money(price)),link:link_of(w),kind:"alert"}).await
}

/// 一条推送的内容。`kind` 原样进 payload：客户端前台已经自己出过提示的那几种
/// （复盘到点、自选波动）靠它在 `willPresent` 里把横幅压掉，不让前台响两下。
pub struct Notice {pub title:String,pub body:String,pub link:String,pub kind:&'static str}

/// 画线提醒点开去那条线；裸价格提醒没有线，只开品种。
fn link_of(w:&Watch)->String {
 match w.drawing_id.as_deref().filter(|d|!d.is_empty()) {
  Some(drawing)=>format!("hkline://drawing/{}/{drawing}",w.symbol),
  None=>format!("hkline://symbol/{}",w.symbol),
 }
}

/// 把一条通知推给这个人所有注册过的设备。触发类（提醒、复盘到点、自选波动）共用。
pub async fn notify(s:&AppState,apns:&Apns,owner:Uuid,notice:&Notice)->Result<()> {
 let (tokens,sound)={
  let mut tx=s.personal(owner).await?;
  let rows=sqlx::query("SELECT device_id,token,environment FROM device_push_tokens WHERE user_id=$1 AND kind='alerts'")
   .bind(owner).fetch_all(&mut *tx).await?;
  // 与 token 在同一个个人事务里读取；不缓存，用户改声后下一条提醒立即采用新值。
  let settings:Option<Value>=sqlx::query_scalar("SELECT body FROM sync_objects WHERE user_id=$1 AND collection='settings' AND id='chart' AND NOT deleted")
   .bind(owner).fetch_optional(&mut *tx).await?;
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
    sqlx::query("DELETE FROM device_push_tokens WHERE user_id=$1 AND device_id=$2 AND kind='alerts'").bind(owner).bind(device).execute(&mut *tx).await?;
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
/// 手机上还有一条本地日历通知兜底（`ReviewDueNotifications`，服务器宕机也照响），
/// 这一条推送是给「换了设备 / 本地排程被系统清掉」的那一下的。
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

/// worker 的评估器入口。永不返回：连不上就退几秒再连，品种集合变了就重订阅。
pub async fn run(s:AppState,apns:Option<Apns>) {
 tracing::info!("Alert evaluator started");
 let mut watches:Vec<Watch>=vec![];
 // 每个品种最近一根**已收盘**的收盘价。`condition='close'` 要两个点才判得出穿越，
 // 这就是那第一个点。
 //
 // 它活在重连之外（不放在 `session` 里）是故意的：断线重连、品种集合变化都不该把它
 // 丢掉。中间断了几分钟的话，这一比就是「跨过那段缺口有没有穿过线」——价格确实从
 // 一侧走到了另一侧，该响；清空它换来的只是白白漏掉一次。
 let mut closes:BTreeMap<String,f64>=BTreeMap::new();
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
  let fresh=match load(&s).await {
   Ok(v)=>v,
   Err(_)=>{tracing::warn!("Alerts could not be loaded; will retry");tokio::time::sleep(Duration::from_secs(10)).await;continue}
  };
  movers.refresh(&fresh.movers);
  // 复盘到点不看价：有没有 K 线流都要按时判，所以放在「一个品种都没有」那条岔路前面。
  settle_due(&s,apns.as_ref(),&fresh.due).await;
  let symbols=symbols_of(&fresh.watches,&movers.symbols());
  let streams=streams_of(&symbols,&fresh.live);
  watches=fresh.watches;
  if symbols.is_empty() {
   // 一条提醒都没有的时候也要走心跳：提醒刚被删掉、而它的活动还挂在别人锁屏上的
   // 那一下，正是最该推 end 的时候。
   heartbeat(&s,apns.as_ref(),&quotes,&mut beat).await;
   tokio::time::sleep(Duration::from_secs(10)).await;continue
  }
  // 不再盯的品种没必要一直留着它的收盘价与行情。
  closes.retain(|symbol,_|symbols.iter().any(|s|s==symbol));
  quotes.retain(|symbol,_|symbols.iter().any(|s|s==symbol));
  if let Err(e)=session(&s,apns.as_ref(),&streams,&mut watches,&mut movers,&mut closes,&mut quotes,&mut beat).await {
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
/// 更新，这一拍只为被挂起的 app 而存在。
async fn heartbeat(s:&AppState,apns:Option<&Apns>,quotes:&BTreeMap<String,Quote>,beat:&mut std::time::Instant) {
 if beat.elapsed()<crate::live_activity::HEARTBEAT {return}
 *beat=std::time::Instant::now();
 if let Err(e)=crate::live_activity::beat(s,apns,quotes).await {
  tracing::warn!("A live activity heartbeat could not be delivered ({e:?}); the next beat will try again");
 }
}

/// 一次连接的生命周期。要订的流变了就返回，让外层重连。
#[allow(clippy::too_many_arguments)]
async fn session(s:&AppState,apns:Option<&Apns>,streams:&[String],watches:&mut Vec<Watch>,movers:&mut crate::watch_move::Movers,closes:&mut BTreeMap<String,f64>,quotes:&mut BTreeMap<String,Quote>,beat:&mut std::time::Instant)->anyhow::Result<()> {
 let url=format!("{STREAM}?streams={}",streams.join("/"));
 let (mut stream,_)=tokio_tungstenite::connect_async(&url).await?;
 // 新连上的这一条和上一条之间有缺口：断线前那一根记下的「收盘」不是真收盘，
 // 波动判定要的五分钟前参照全部作废，从缺口重新开始（缺口不冒充零波动）。
 movers.forget_prices();
 tracing::info!("Alert evaluator watching {} stream(s)",streams.len());
 let mut refresh=tokio::time::interval(Duration::from_secs(10));
 refresh.tick().await;
 loop {
  tokio::select! {
   // 币安每三分钟发一次 ping，正常品种的 1m K 线每秒都有好几帧。九十秒一帧都没有
   // 只有一种解释：这条连接已经死了而 TCP 还没告诉我们。
   frame=tokio::time::timeout(Duration::from_secs(90),stream.next())=>{
    let Some(frame)=frame? else {anyhow::bail!("the stream closed")};
    let message=frame?;
    let Some(text)=message.into_text().ok() else {continue};
    if let Some(candle)=parse(&text) {
     // 最新价就是这一根还没收的收盘价。涨跌幅不动：它只从 ticker 帧来，这里覆盖成
     // None 等于每来一根 K 线就把锁屏上的涨跌幅抹掉一次。
     quotes.entry(candle.symbol.clone()).or_default().price=candle.close.is_finite().then_some(candle.close);
     evaluate(s,apns,watches,closes,quotes,&candle).await;
     for (owner,event) in movers.observe(&candle.symbol,candle.open_time,candle.close,candle.closed) {
      crate::watch_move::notify(s,apns,owner,&event).await;
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
    match load(s).await {
     Ok(fresh)=>{
      movers.refresh(&fresh.movers);
      settle_due(s,apns,&fresh.due).await;
      let changed=streams_of(&symbols_of(&fresh.watches,&movers.symbols()),&fresh.live)!=streams;
      *watches=fresh.watches;
      if changed {return Ok(())}
     }
     Err(_)=>tracing::warn!("Alerts could not be refreshed; keeping the current set"),
    }
    heartbeat(s,apns,quotes,beat).await;
   }
  }
 }
}

/// 一帧 K 线对上这一批提醒。
///
/// 触发过的从内存里摘掉：下一次刷新（十秒内）才会重新读库，中间这段时间不摘就会
/// 每来一帧推一次。库里那条 `WHERE status='active'` 是最终的那道闸，这里只是不做无用功。
///
/// `closes` 里那一条**先读后写**：这一帧要拿的是上一根的收盘价，写进去的是这一根的。
/// 顺序反了的话每一根都在和自己比，`close` 这一档永远不会响。
async fn evaluate(s:&AppState,apns:Option<&Apns>,watches:&mut Vec<Watch>,closes:&mut BTreeMap<String,f64>,quotes:&BTreeMap<String,Quote>,candle:&Candle) {
 let at=chrono::Utc::now().timestamp_millis();
 let previous=closes.get(&candle.symbol).copied();
 let mut fired=vec![];
 for (index,w) in watches.iter().enumerate() {
  if w.symbol!=candle.symbol {continue}
  let hit=match w.condition {
   Condition::Touch=>touched(&w.lines,candle.open_time,w.armed_at,candle.low,candle.high),
   // 这一根没收就一个字都不判；没有上一根的收盘价（刚起来、或者这个品种第一次收）
   // 也不判——宁可漏一根，也不拿一个不知道是哪一根的价去算穿越。
   Condition::Close=>if candle.closed {previous.and_then(|p|crossed_on_close(&w.lines,candle.open_time,w.armed_at,p,candle.close))} else {None},
  };
  if hit.is_some() {fired.push(index)}
 }
 if candle.closed&&candle.close.is_finite() {closes.insert(candle.symbol.clone(),candle.close);}
 let quote=quotes.get(&candle.symbol).copied().unwrap_or_default();
 for index in fired.iter().rev() {
  let w=watches.remove(*index);
  if let Err(e)=fire(s,apns,&w,quote,candle.close,at).await {
   tracing::warn!("An alert could not be recorded as fired ({:?}); it will be retried",e);
   watches.push(w);
  }
 }
}

#[cfg(test)]
mod tests {
 use super::*;

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
  assert_eq!(touched(&l,50,0,101.0,99.0),None,"low 比 high 大是坏帧");
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
   lines:vec![line(&[(0.0,70_000.0)],true,true)],armed_at:0,condition:Condition::Touch};
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
   Watch{owner:Uuid::nil(),alert_id:"a".into(),symbol:"ETHUSDT".into(),drawing_id:None,title:String::new(),lines:vec![],armed_at:0,condition:Condition::Touch},
   Watch{owner:Uuid::nil(),alert_id:"b".into(),symbol:"BTCUSDT".into(),drawing_id:None,title:String::new(),lines:vec![],armed_at:0,condition:Condition::Touch},
   Watch{owner:Uuid::nil(),alert_id:"c".into(),symbol:"BTCUSDT".into(),drawing_id:None,title:String::new(),lines:vec![],armed_at:0,condition:Condition::Close},
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
}
