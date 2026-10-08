//! Coinbase 给服务端提醒评估的 1 分钟行情：它没有 1 分钟 K 线推送（`candles` 频道固定 5 分钟），
//! 所以订 `market_trades`，逐笔交给评估循环拼 1 分钟 K 线（`alerts::MinuteBars`）。
//!
//! - 触线：这一分钟的高 / 低被刷新时才判一次；收盘穿越：一分钟收完才判（下一分钟的第一笔到了，
//!   或者这一分钟结束后两秒还没有新的一笔）。
//! - 订着心跳频道，每秒一帧；三十秒一帧都没有就判断线。
//! - 断线补缺用原生 1 分钟 K 线（经本家 `PACER`）。
use crate::alerts::{Candle,KlineFeed,Socket,Tick};
use crate::venues::Fut;
use serde_json::Value;
use std::time::Duration;

/// 这一支只开一条连接，一条连接最多订这么多个产品。
pub const MAX_PRODUCTS:usize=200;
/// 心跳每秒一帧；三十秒一帧都没有就当它死了。
const SILENCE:Duration=Duration::from_secs(30);

pub struct Feed;
pub static FEED:Feed=Feed;

impl KlineFeed for Feed {
 fn venue(&self)->&'static dyn crate::venues::Venue {&super::COINBASE}
 fn task(&self)->&'static str {"alerts-coinbase"}
 fn max_symbols(&self)->usize {MAX_PRODUCTS}
 fn silence(&self)->Duration {SILENCE}
 fn connect<'a>(&'a self,symbols:&'a [String])->Fut<'a,anyhow::Result<Socket>> {
  Box::pin(crate::alerts::dial(super::WS,vec![super::control("subscribe","heartbeats",&[]),super::control("subscribe","market_trades",symbols)]))
 }
 fn decode(&self,text:&str,out:&mut Vec<Tick>) {
  out.extend(coinbase_trades(text).into_iter().map(|(symbol,time,price)|Tick::Trade{symbol,time,price}));
 }
 fn backfill<'a>(&'a self,symbol:String,first:i64,end:i64)->Fut<'a,Option<Vec<Candle>>> {
  Box::pin(async move {super::candles(&symbol,60,first/1000,end/1000).await.ok().map(|rows|coinbase_rows(&symbol,rows,first,end))})
 }
}

/// Coinbase 的原生 1 分钟 K 线（秒、字符串价）换成评估器的样子。没成交的分钟 Coinbase
/// 不给，缺着就缺着——和逐笔拼出来的那一支同一个口径。
pub fn coinbase_rows(symbol:&str,rows:Vec<super::Candle>,first:i64,end:i64)->Vec<Candle> {
 rows.into_iter().filter_map(|c|{
  let number=|s:&str|s.parse::<f64>().ok().filter(|v|v.is_finite());
  let open_time=c.start*1000;
  if open_time<first||open_time>=end {return None}
  Some(Candle{symbol:symbol.to_string(),open_time,low:number(&c.low)?,high:number(&c.high)?,close:number(&c.close)?,closed:true})
 }).collect()
}

/// 一帧 `market_trades` 里的逐笔：(品种, 成交时间毫秒, 价)，按成交先后排好。
/// `snapshot` 事件是订阅那一刻补发的最近几十笔历史，不拿来判提醒。
pub fn coinbase_trades(text:&str)->Vec<(String,i64,f64)> {
 let Ok(v)=serde_json::from_str::<Value>(text) else {return vec![]};
 if v.get("channel").and_then(Value::as_str)!=Some("market_trades") {return vec![]}
 let mut out=vec![];
 for event in v.get("events").and_then(Value::as_array).into_iter().flatten() {
  if event.get("type").and_then(Value::as_str)!=Some("update") {continue}
  for t in event.get("trades").and_then(Value::as_array).into_iter().flatten() {
   let (Some(symbol),Some(time),Some(price))=(
    t.get("product_id").and_then(Value::as_str),
    t.get("time").and_then(Value::as_str).and_then(super::iso_ms),
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
