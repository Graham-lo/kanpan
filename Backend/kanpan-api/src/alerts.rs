//! 提醒的服务端那一半：几何、物化表、评估器、推送 token 端点。
//!
//! 分工是这样的：**客户端负责把一条画线摊平成若干条价格折线**（`AlertGeometry`），
//! 服务端只认 `[{points:[{t,p}],extendLeft,extendRight}]` 这一种形状，在时间上做线性
//! 插值与外推。所以这里没有一行代码知道什么是斐波那契、什么是平行通道——新加一把画线
//! 工具不需要动服务端，这正是把几何放在客户端算的理由。
//!
//! 评估器跑在 `kanpan-worker` 里（`main.rs` 的 worker 分支）。它订阅币安 1m K 线，
//! 每一帧对该品种的活动提醒算一次：K 线开盘时间 `t ≥ armedAt` 的那根，若某条折线在
//! `t` 处的价落在 `[low, high]` 里就算触碰。触发后**在同一个事务里**把物化表置 fired
//! 并往这个人的同步日志写一条 op，然后才推送。
use crate::{AppState,apns::{Apns,Outcome},auth::Identity,envelope,error::{ApiError,Result},sync::Object};
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

// ——————————————————————— 物化（同步写入时顺手刷新） ———————————————————————

/// 把一条 `alerts` 同步对象刷进 `alert_watches`。由 `sync::push` 在同一个事务里调用。
///
/// 只物化 `kind == "drawing"` 的提醒：`reviewDue` 整条链路都在客户端本地通知里，
/// `price` 本轮只进模型与白名单。其余情况（包括删除、改成别的 kind、暂停）一律把行删掉
/// ——评估器读的就是这张表，删掉就等于停评估，不需要第二处开关。
///
/// 每次都整行覆盖，所以用户把被提醒的那条线拖到别处、客户端用同一个 alert id 重传
/// `lines` 时，`lines` 与 `armedAt` 是一起换掉的，评估器下一帧就用新几何。
pub async fn materialize(tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,owner:Uuid,object:&Object)->Result<()> {
 let keep=!object.deleted
  && object.body.get("kind").and_then(Value::as_str)==Some("drawing")
  && object.body.get("symbol").and_then(Value::as_str).is_some();
 if !keep {
  sqlx::query("DELETE FROM alert_watches WHERE user_id=$1 AND alert_id=$2").bind(owner).bind(&object.id).execute(&mut **tx).await?;
  return Ok(())
 }
 let text=|k:&str|object.body.get(k).and_then(Value::as_str).unwrap_or_default().to_string();
 let number=|k:&str|object.body.get(k).and_then(Value::as_f64);
 sqlx::query("INSERT INTO alert_watches(user_id,alert_id,kind,symbol,market,drawing_id,lines,condition,title,armed_at,status,fired_at,fired_price,updated_at) \
  VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,now()) \
  ON CONFLICT(user_id,alert_id) DO UPDATE SET kind=excluded.kind,symbol=excluded.symbol,market=excluded.market,drawing_id=excluded.drawing_id,\
  lines=excluded.lines,condition=excluded.condition,title=excluded.title,armed_at=excluded.armed_at,status=excluded.status,\
  fired_at=excluded.fired_at,fired_price=excluded.fired_price,updated_at=now()")
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
  .execute(&mut **tx).await?;
 Ok(())
}

// ——————————————————————— 推送 token 端点 ———————————————————————

#[derive(Deserialize)]
#[serde(rename_all="camelCase",deny_unknown_fields)]
struct TokenBody {token:String,kind:String,environment:String,#[serde(default)] activity_id:Option<String>}

pub fn routes()->Router<AppState> {
 Router::new().route("/v1/devices/push-token",post(push_token))
}
/// `POST /v1/devices/push-token`：把这台设备的 APNs token 记下来。
///
/// 设备身份不由客户端自称：从会话反查 `account_sessions.device_id`，和 `sync::push`
/// 认设备用的是同一条语句。一台设备同一个 kind 只留一行，重复注册就是覆盖
/// （token 会在重装、还原、系统更新之后变）。
async fn push_token(State(s):State<AppState>,i:Identity,Json(v):Json<TokenBody>)->Result<Json<Value>> {
 if !matches!(v.kind.as_str(),"alerts"|"liveActivity"|"widget") {return Err(ApiError::bad("invalid_token_kind"))}
 if !matches!(v.environment.as_str(),"production"|"sandbox") {return Err(ApiError::bad("invalid_token_environment"))}
 // APNs 的设备 token 是 32 字节的十六进制（64 个字符），但历史上长过、苹果也说过还会变，
 // 所以卡的是「十六进制、长度在一个合理的区间里」而不是等于 64。
 if v.token.len()<32||v.token.len()>200||!v.token.bytes().all(|c|c.is_ascii_hexdigit()) {return Err(ApiError::bad("invalid_token"))}
 if v.activity_id.as_ref().is_some_and(|a|a.len()>200) {return Err(ApiError::bad("invalid_activity"))}
 let mut tx=s.personal(i.user).await?;
 let device:Uuid=sqlx::query_scalar("SELECT device_id FROM account_sessions WHERE id=$1 AND user_id=$2 AND revoked_at IS NULL")
  .bind(i.session).bind(i.user).fetch_optional(&mut *tx).await?.ok_or_else(ApiError::unauthorized)?;
 sqlx::query("INSERT INTO device_push_tokens(user_id,device_id,kind,environment,token,activity_id,updated_at) VALUES($1,$2,$3,$4,$5,$6,now()) \
  ON CONFLICT(user_id,device_id,kind) DO UPDATE SET environment=excluded.environment,token=excluded.token,activity_id=excluded.activity_id,updated_at=now()")
  .bind(i.user).bind(device).bind(&v.kind).bind(&v.environment).bind(&v.token).bind(v.activity_id.as_deref())
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

/// 评估器在内存里保有的一条活动提醒。
#[derive(Clone,Debug)]
struct Watch {
 owner:Uuid,alert_id:String,symbol:String,drawing_id:Option<String>,
 title:String,lines:Vec<Line>,armed_at:i64,
}

/// 把所有用户的活动画线提醒读成一张内存表。
///
/// 为什么逐个用户开事务：这两张表和同步表一样挂着 FORCE ROW LEVEL SECURITY，运行期角色
/// 既不是属主也没有 BYPASSRLS，所以**没有**一条能一次看见所有人的通道——这是故意的。
/// 代价是一次刷新 N 个短事务，而 N 是个位数（`maintenance::cleanup` 用的同一套分页）。
async fn load(s:&AppState)->Result<Vec<Watch>> {
 let mut out=vec![];
 let mut after:Option<Uuid>=None;
 let mut skipped_close=0usize;
 loop {
  let owners:Vec<Uuid>=sqlx::query_scalar("SELECT id FROM account_users WHERE disabled_at IS NULL AND ($1::uuid IS NULL OR id>$1) ORDER BY id LIMIT 100").bind(after).fetch_all(&s.pool).await?;
  if owners.is_empty(){break}
  for owner in &owners {
   let mut tx=match s.personal(*owner).await {Ok(tx)=>tx,Err(_)=>continue};
   let rows=sqlx::query("SELECT alert_id,symbol,drawing_id,title,lines,armed_at,condition FROM alert_watches WHERE user_id=$1 AND status='active' AND kind='drawing'")
    .bind(owner).fetch_all(&mut *tx).await?;
   tx.commit().await?;
   for r in rows {
    // TODO(第二波)：`condition='close'`（收盘确认）要等 K 线收了（帧里的 `k.x==true`）
    // 再判，而且判的是收盘价而不是 [low,high]。本轮只实现 `touch`，遇到 close 的活动
    // 提醒跳过不评估——**不报错、不拒收**，它在同步协议里是合法值，客户端已经能存能改。
    if r.get::<String,_>("condition")!="touch" {skipped_close+=1;continue}
    let lines:Vec<Line>=match serde_json::from_value(r.get::<Value,_>("lines")) {
     Ok(v)=>v,
     // 形状对不上就当这条提醒不存在，而不是让整轮刷新失败——一条坏数据不该让所有人
     // 的提醒一起停摆。白名单那一层已经挡过一次，真走到这里说明有别的路写进去了。
     Err(e)=>{tracing::warn!("An alert has unusable geometry and will not be evaluated: {e}");continue}
    };
    out.push(Watch{owner:*owner,alert_id:r.get("alert_id"),symbol:r.get("symbol"),
     drawing_id:r.get("drawing_id"),title:r.get("title"),lines,armed_at:r.get("armed_at")});
   }
  }
  after=owners.last().copied();
 }
 if skipped_close>0 {tracing::debug!("{skipped_close} close-confirmation alerts are not evaluated yet");}
 Ok(out)
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
pub async fn record_fired(s:&AppState,owner:Uuid,alert_id:&str,price:f64,at:i64)->Result<bool> {
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
 let fields:BTreeMap<String,Value>=[("status",json!("fired")),("firedAt",json!(at)),("firedPrice",json!(price))]
  .into_iter().map(|(k,v)|(k.to_string(),v)).collect();
 crate::sync::apply_server(&mut tx,owner,"alerts",alert_id,fields).await?;
 tx.commit().await?;
 Ok(true)
}
/// 触发之后把通知推给这个人所有注册过的设备。
///
/// 推送**在事务之外**做：HTTP/2 一个往返几百毫秒，握着这个人的同步闸等苹果回话，
/// 等于把他所有设备的同步一起挂在那儿。
async fn fire(s:&AppState,apns:Option<&Apns>,w:&Watch,price:f64,at:i64)->Result<()> {
 if !record_fired(s,w.owner,&w.alert_id,price,at).await? {return Ok(())}
 let Some(apns)=apns else {
  // 没有 APNs 密钥时这就是终点，而且是一个完整的终点：状态已经落库、op 已经写进
  // alerts 集合，客户端下次拉同步（开 app 就会拉）照样看得到这条已触发的提醒。
  // 这里只留一行 info 当证据，不排队、不重试——没有密钥不是一个会自己好起来的错误。
  tracing::info!("{} touched {} at {}; recorded and synced, not pushed (no APNs key)",w.symbol,w.alert_id,money(price));
  return Ok(())
 };
 let tokens={
  let mut tx=s.personal(w.owner).await?;
  let rows=sqlx::query("SELECT device_id,token,environment FROM device_push_tokens WHERE user_id=$1 AND kind='alerts'")
   .bind(w.owner).fetch_all(&mut *tx).await?;
  tx.commit().await?;rows
 };
 let link=format!("hkline://drawing/{}/{}",w.symbol,w.drawing_id.clone().unwrap_or_default());
 let title=if w.title.is_empty() {format!("{} 触到你画的线",w.symbol)} else {w.title.clone()};
 let body=format!("现价 {}",money(price));
 for row in tokens {
  let token:String=row.get("token");
  let environment:String=row.get("environment");
  match apns.push_alert(&token,&environment,&title,&body,&link).await {
   Ok(Outcome::Delivered)=>{}
   Ok(Outcome::Gone)=>{
    let device:Uuid=row.get("device_id");
    let mut tx=s.personal(w.owner).await?;
    sqlx::query("DELETE FROM device_push_tokens WHERE user_id=$1 AND device_id=$2 AND kind='alerts'").bind(w.owner).bind(device).execute(&mut *tx).await?;
    tx.commit().await?;
   }
   // 推不出去不回滚状态：提醒确实触发了，客户端下次拉取照样看得到，
   // 少的只是那一下横幅。把状态跟着推送一起回滚才是真的丢事件。
   Err(_)=>tracing::warn!("An alert fired but could not be pushed"),
  }
 }
 Ok(())
}

/// 通知正文里的价。K/M 那套金额单位是给成交额用的，价格要看得清每一位。
fn money(v:f64)->String {
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
struct Candle {symbol:String,open_time:i64,low:f64,high:f64,close:f64}
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
 })
}

/// worker 的评估器入口。永不返回：连不上就退几秒再连，品种集合变了就重订阅。
pub async fn run(s:AppState,apns:Option<Apns>) {
 tracing::info!("Alert evaluator started");
 let mut watches:Vec<Watch>=vec![];
 loop {
  match load(&s).await {
   Ok(v)=>watches=v,
   Err(_)=>{tracing::warn!("Alerts could not be loaded; will retry");tokio::time::sleep(Duration::from_secs(10)).await;continue}
  }
  let symbols=symbols_of(&watches);
  if symbols.is_empty() {tokio::time::sleep(Duration::from_secs(10)).await;continue}
  if let Err(e)=session(&s,apns.as_ref(),&symbols,&mut watches).await {
   tracing::warn!("Alert stream ended ({e}); reconnecting");
   tokio::time::sleep(Duration::from_secs(5)).await;
  }
 }
}
fn symbols_of(watches:&[Watch])->Vec<String> {
 let mut all:Vec<String>=watches.iter().map(|w|w.symbol.clone()).collect();
 all.sort();all.dedup();
 if all.len()>MAX_STREAMS {
  tracing::warn!("{} symbols have alerts but one combined stream carries {MAX_STREAMS}; the rest are not watched",all.len());
  all.truncate(MAX_STREAMS);
 }
 all
}

/// 一次连接的生命周期。品种集合变了就返回，让外层重连。
async fn session(s:&AppState,apns:Option<&Apns>,symbols:&[String],watches:&mut Vec<Watch>)->anyhow::Result<()> {
 let url=format!("{STREAM}?streams={}",symbols.iter().map(|s|format!("{}@kline_1m",s.to_lowercase())).collect::<Vec<_>>().join("/"));
 let (mut stream,_)=tokio_tungstenite::connect_async(&url).await?;
 tracing::info!("Alert evaluator watching {} symbol(s)",symbols.len());
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
    let Some(candle)=parse(&text) else {continue};
    evaluate(s,apns,watches,&candle).await;
   }
   _=refresh.tick()=>{
    match load(s).await {
     Ok(fresh)=>{
      let changed=symbols_of(&fresh)!=symbols;
      *watches=fresh;
      if changed {return Ok(())}
     }
     Err(_)=>tracing::warn!("Alerts could not be refreshed; keeping the current set"),
    }
   }
  }
 }
}

/// 一帧 K 线对上这一批提醒。
///
/// 触发过的从内存里摘掉：下一次刷新（十秒内）才会重新读库，中间这段时间不摘就会
/// 每来一帧推一次。库里那条 `WHERE status='active'` 是最终的那道闸，这里只是不做无用功。
async fn evaluate(s:&AppState,apns:Option<&Apns>,watches:&mut Vec<Watch>,candle:&Candle) {
 let at=chrono::Utc::now().timestamp_millis();
 let mut fired=vec![];
 for (index,w) in watches.iter().enumerate() {
  if w.symbol!=candle.symbol {continue}
  if touched(&w.lines,candle.open_time,w.armed_at,candle.low,candle.high).is_some() {fired.push(index)}
 }
 for index in fired.iter().rev() {
  let w=watches.remove(*index);
  if let Err(e)=fire(s,apns,&w,candle.close,at).await {
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
  // 别的事件（订阅回执、aggTrade）不是 K 线，跳过而不是崩。
  assert!(parse(r#"{"result":null,"id":1}"#).is_none());
  assert!(parse("not json").is_none());
 }
 /// 通知正文里的价要看得清每一位，小币种也是。
 #[test] fn the_notification_shows_a_readable_price() {
  assert_eq!(money(63_120.0),"63,120");
  assert_eq!(money(1_234_567.0),"1,234,567");
  assert_eq!(money(12.5),"12.50");
  assert_eq!(money(0.1234),"0.1234");
  assert_eq!(money(0.00001234),"0.00001234");
 }
 /// 订阅串就是网关一直在用的那条路径的形状。
 #[test] fn the_stream_url_is_the_one_measured_on_the_vps() {
  assert_eq!(STREAM,"wss://fstream.binance.com/market/stream");
  let watches=vec![
   Watch{owner:Uuid::nil(),alert_id:"a".into(),symbol:"ETHUSDT".into(),drawing_id:None,title:String::new(),lines:vec![],armed_at:0},
   Watch{owner:Uuid::nil(),alert_id:"b".into(),symbol:"BTCUSDT".into(),drawing_id:None,title:String::new(),lines:vec![],armed_at:0},
   Watch{owner:Uuid::nil(),alert_id:"c".into(),symbol:"BTCUSDT".into(),drawing_id:None,title:String::new(),lines:vec![],armed_at:0},
  ];
  let symbols=symbols_of(&watches);
  assert_eq!(symbols,vec!["BTCUSDT".to_string(),"ETHUSDT".to_string()],"同一品种只订一次，顺序稳定");
  let streams=symbols.iter().map(|s|format!("{}@kline_1m",s.to_lowercase())).collect::<Vec<_>>().join("/");
  assert_eq!(streams,"btcusdt@kline_1m/ethusdt@kline_1m");
 }
}
