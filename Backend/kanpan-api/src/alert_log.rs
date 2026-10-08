//! 提醒触发记录（2026-10-05，迁移 0043）。
//!
//! 提醒「触发即删」：响完之后同步对象与 `alert_watches` 那一行都没了，用户想回头看
//! 「哪几条响过、响在多少」无处可查。这里只追加一张流水：
//!
//! - **服务端判响**：`alerts::record_fired`（币安 / Coinbase / 美元指数三支的价格与画线、
//!   条件提醒、复盘到点全走它）在同一个事务里写一行；
//! - **客户端判响**：同步推上来的「非 fired → fired」，`alerts::materialize` 在同一个事务里写一行。
//!
//! 两条路都在这个人的同步咨询锁里、都只认那一次转变，谁先到谁写；
//! `(user_id, alert_id, fired_at)` 唯一再兜一层（客户端重推同一次触发不会多一行）。
//! 留 30 天（[`RETENTION_MS`]），`maintenance::cleanup` 每小时按批删。
//!
//! 接口：`GET /v1/alerts/log?symbol=&since=&limit=` 与 `DELETE /v1/alerts/log?symbol=`，
//! 协议见 `docs/提醒日志-协议-2026-10-05.md`。字段名是 iOS 那边已经照着写的，不要改。
use crate::{AppState,alerts,auth::Identity,envelope,error::{ApiError,Params,Result},sync::Object};
use axum::{Router,Json,extract::State,http::StatusCode,routing::get};
use serde::Deserialize;
use serde_json::{Value,json};
use sqlx::Row;
use uuid::Uuid;

/// 留多久：30 天。清理语句（`maintenance::PERSONAL`）里写的是同一个毫秒数。
pub const RETENTION_MS:i64=30*24*60*60*1000;
/// `limit` 缺省与上限。
pub const DEFAULT_LIMIT:i64=200;
pub const MAX_LIMIT:i64=500;

/// 一次触发写一行。`object` 是这条提醒此刻的同步对象（标题、种类、几何、条件都从它取），
/// `price` 是触发价（复盘到点没有），`at` 是触发时刻（毫秒）。
///
/// 同一次触发已经记过就什么都不做（`ON CONFLICT DO NOTHING`）。比 30 天还早的不记——
/// 记了下一轮清理也是删，而且那多半是旧设备补报上来的陈年状态，不是一次新的触发。
pub async fn record(tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,owner:Uuid,object:&Object,price:Option<f64>,at:i64)->Result<()> {
 if chrono::Utc::now().timestamp_millis()-at>RETENTION_MS {return Ok(())}
 let entry=Entry::of(object,price.filter(|p|p.is_finite()),at);
 sqlx::query("INSERT INTO alert_log(user_id,id,alert_id,kind,symbol,title,condition,fired_at,fired_price) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) \
  ON CONFLICT (user_id,alert_id,fired_at) DO NOTHING")
  .bind(owner).bind(Uuid::new_v4()).bind(&object.id).bind(&entry.kind).bind(&entry.symbol).bind(&entry.title).bind(&entry.condition)
  .bind(at).bind(price.filter(|p|p.is_finite()))
  .execute(&mut **tx).await?;
 Ok(())
}

/// 一行记录里由同步对象算出来的那几列。
#[derive(Debug,PartialEq)]
pub struct Entry {pub kind:String,pub symbol:String,pub title:String,pub condition:String}

impl Entry {
 pub fn of(object:&Object,price:Option<f64>,at:i64)->Entry {
  let text=|k:&str|object.body.get(k).and_then(Value::as_str).unwrap_or_default();
  let kind=text("kind").to_string();
  let market=Some(text("market")).filter(|m|!m.is_empty()).unwrap_or(alerts::BINANCE);
  let bare=text("symbol");
  // 完整品种键：客户端 `InstrumentID.canonical` 认这一种，三家交易所之间不会撞名。
  let symbol=format!("{market}/{bare}");
  let display=alerts::display_symbol(market,bare);
  let rule=object.body.get("rule").and_then(crate::conditions::Rule::parse);
  let condition=match kind.as_str() {
   "condition"=>rule.as_ref().map(|r|r.phrase()).unwrap_or_else(||"条件提醒".into()),
   "reviewDue"=>"复盘到点".into(),
   // 画线 / 裸价格：Webhook 默认文案里「{条件} {目标价}」那一段，「价格达到 86,000」。
   _=>{
    let word=alerts::condition_word(alerts::Condition::of(Some(text("condition")).filter(|c|!c.is_empty()).unwrap_or("touch")));
    let mut lines:Vec<alerts::Line>=serde_json::from_value(object.body.get("lines").cloned().unwrap_or_else(||json!([]))).unwrap_or_default();
    for line in &mut lines {line.points.sort_by(|a,b|a.t.partial_cmp(&b.t).unwrap_or(std::cmp::Ordering::Equal))}
    // 没有触发价（不该发生）就拿第一条线的第一个点当参照，选「离它最近的那条线」。
    let near=price.or_else(||lines.first().and_then(|l|l.points.first()).map(|p|p.p));
    match near.and_then(|p|alerts::target_of(&lines,p,at)) {
     Some(target)=>format!("{word} {}",alerts::webhook_money(target)),
     None=>word.to_string(),
    }
   }
  };
  // 标题：用户（客户端）起的那个；没有就和推送的兜底标题一样。
  let title=match text("title") {
   "" if kind=="reviewDue"=>format!("{} 到点了",crate::watch_move::short(bare)),
   "" if kind=="condition"=>format!("{display} {condition}"),
   ""=>format!("{display} 触到你画的线"),
   t=>t.to_string(),
  };
  Entry{kind,symbol,title,condition}
 }
}

pub fn routes()->Router<AppState> {
 Router::new().route("/v1/alerts/log",get(list).delete(clear))
}

#[derive(Deserialize)]
struct ListQuery {symbol:Option<String>,since:Option<i64>,limit:Option<i64>}
#[derive(Deserialize)]
struct ClearQuery {symbol:Option<String>}

/// `symbol` 参数：完整品种键（带 `/`）原样比；裸代号按币安 U 本位补全（和客户端
/// `InstrumentID.canonical` 一个口径）。空串当没给。
fn symbol_key(symbol:Option<&str>)->Result<Option<String>> {
 let Some(s)=symbol.map(str::trim).filter(|s|!s.is_empty()) else {return Ok(None)};
 if s.len()>80||!s.bytes().all(|b|b.is_ascii_alphanumeric()||matches!(b,b'/'|b'-'|b'_'|b'.')) {return Err(ApiError::bad("invalid_symbol"))}
 Ok(Some(if s.contains('/') {s.to_string()} else {format!("{}/{s}",alerts::BINANCE)}))
}
fn clamp_limit(limit:Option<i64>)->i64 {limit.unwrap_or(DEFAULT_LIMIT).clamp(1,MAX_LIMIT)}

/// `GET /v1/alerts/log`：这个人的触发记录，按触发时刻从新到旧。
async fn list(State(s):State<AppState>,i:Identity,Params(q):Params<ListQuery>)->Result<Json<Value>> {
 let symbol=symbol_key(q.symbol.as_deref())?;
 let mut tx=s.personal(i.user).await?;
 let rows=sqlx::query("SELECT id,alert_id,kind,symbol,title,condition,fired_at,fired_price FROM alert_log \
  WHERE user_id=$1 AND ($2::text IS NULL OR symbol=$2) AND ($3::bigint IS NULL OR fired_at>=$3) \
  ORDER BY fired_at DESC,id DESC LIMIT $4")
  .bind(i.user).bind(symbol).bind(q.since).bind(clamp_limit(q.limit)).fetch_all(&mut *tx).await?;
 tx.commit().await?;
 let records:Vec<Value>=rows.iter().map(|r|json!({
  "id":r.get::<Uuid,_>("id"),"alertId":r.get::<String,_>("alert_id"),"kind":r.get::<String,_>("kind"),
  "symbol":r.get::<String,_>("symbol"),"title":r.get::<String,_>("title"),"condition":r.get::<String,_>("condition"),
  "firedAt":r.get::<i64,_>("fired_at"),"firedPrice":r.get::<Option<f64>,_>("fired_price"),
 })).collect();
 Ok(envelope(json!({"records":records})))
}

/// `DELETE /v1/alerts/log`：清空（带 `symbol` 只清那一只）。204。
async fn clear(State(s):State<AppState>,i:Identity,Params(q):Params<ClearQuery>)->Result<StatusCode> {
 let symbol=symbol_key(q.symbol.as_deref())?;
 let mut tx=s.personal(i.user).await?;
 sqlx::query("DELETE FROM alert_log WHERE user_id=$1 AND ($2::text IS NULL OR symbol=$2)").bind(i.user).bind(symbol).execute(&mut *tx).await?;
 tx.commit().await?;
 Ok(StatusCode::NO_CONTENT)
}

#[cfg(test)]
mod tests {
 use super::*;
 use std::collections::BTreeMap;

 fn object(body:Value)->Object {
  let body:BTreeMap<String,Value>=serde_json::from_value(body).unwrap();
  Object{collection:"alerts".into(),id:"binance/usd_m/BTCUSDT/A1".into(),fields:BTreeMap::new(),body,revision:1,deleted:false,generation:0}
 }

 #[test] fn a_price_alert_reads_like_the_webhook_wording() {
  let o=object(json!({"kind":"price","symbol":"BTCUSDT","market":"binance/usd_m","condition":"touch","title":"BTC 涨到 86,000",
   "lines":[{"points":[{"t":1.0,"p":86000.0}],"extendLeft":true,"extendRight":true}]}));
  let e=Entry::of(&o,Some(86012.5),1_800_000_000_000);
  assert_eq!(e,Entry{kind:"price".into(),symbol:"binance/usd_m/BTCUSDT".into(),title:"BTC 涨到 86,000".into(),condition:"价格达到 86,000".into()});
 }
 #[test] fn a_drawing_alert_names_the_line_price_at_the_moment_it_fired_and_close_says_so() {
  let o=object(json!({"kind":"drawing","symbol":"BTC-USD","market":"coinbase/spot","condition":"close","title":"",
   "lines":[{"points":[{"t":0.0,"p":100.0},{"t":1000.0,"p":200.0}],"extendLeft":false,"extendRight":true}]}));
  let e=Entry::of(&o,Some(150.0),500);
  assert_eq!(e.symbol,"coinbase/spot/BTC-USD");
  assert_eq!(e.condition,"收盘穿过 150");
  assert_eq!(e.title,"CB BTC/USD 触到你画的线","没有标题就用推送的兜底标题");
 }
 #[test] fn macro_condition_and_review_rows() {
  let dxy=object(json!({"kind":"price","symbol":"DXY","market":"macro/index","title":"",
   "lines":[{"points":[{"t":1.0,"p":104.25}],"extendLeft":true,"extendRight":true}]}));
  let e=Entry::of(&dxy,Some(104.3),2);
  assert_eq!((e.symbol.as_str(),e.condition.as_str(),e.title.as_str()),("macro/index/DXY","价格达到 104.25","美元指数 触到你画的线"));
  let cond=object(json!({"kind":"condition","symbol":"ETHUSDT","market":"binance/usd_m","title":"",
   "rule":{"type":"funding","side":"above","rate":"0.001"}}));
  let e=Entry::of(&cond,Some(3000.0),2);
  assert_eq!(e.condition,"资金费率高于 0.1%");assert_eq!(e.title,"币安 ETHUSDT 资金费率高于 0.1%");
  let review=object(json!({"kind":"reviewDue","symbol":"SOLUSDT","title":""}));
  let e=Entry::of(&review,None,2);
  assert_eq!((e.symbol.as_str(),e.condition.as_str(),e.title.as_str()),("binance/usd_m/SOLUSDT","复盘到点","SOL 到点了"),"缺 market 的老提醒按币安记");
 }
 #[test] fn symbol_filter_and_limit() {
  assert_eq!(symbol_key(None).unwrap(),None);
  assert_eq!(symbol_key(Some(" ")).unwrap(),None);
  assert_eq!(symbol_key(Some("BTCUSDT")).unwrap().as_deref(),Some("binance/usd_m/BTCUSDT"));
  assert_eq!(symbol_key(Some("macro/index/DXY")).unwrap().as_deref(),Some("macro/index/DXY"));
  assert!(symbol_key(Some("BTC USDT")).is_err());
  assert_eq!((clamp_limit(None),clamp_limit(Some(0)),clamp_limit(Some(9999)),clamp_limit(Some(50))),(200,1,500,50));
 }
}
