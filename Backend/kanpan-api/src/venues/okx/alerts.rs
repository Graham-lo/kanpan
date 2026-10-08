//! OKX 给服务端提醒评估的 1 分钟 K 线：business 端点的 `candle1m` 频道（官方文档 WebSocket › Public
//! Channel › Candlesticks channel；K 线类频道只在 business 端点上）。
//!
//! 一帧 `{"arg":{"channel":"candle1m","instId":"BTC-USDT-SWAP"},"data":[[ts,o,h,l,c,vol,volCcy,volCcyQuote,confirm]]}`，
//! `confirm` 是 `"1"` 就是这一根收了（没等到的由评估循环按下一根 / 收盘宽限替它收）。冷门品种可能
//! 一分钟都没有一帧，所以每 20 秒发一次文本 `ping`（回 `pong`，也算一帧），六十秒一帧都没有才判断线。断线补缺走 `history-candles`（经本家 `PACER`）。
use crate::alerts::{Candle,KlineFeed,Socket,Tick};
use crate::venues::Fut;
use serde_json::Value;
use std::time::Duration;

/// 一条订阅消息最多带几个品种（官方限的是一条消息 64 KB，这里远在线下）。
const ARGS_PER_MESSAGE:usize=20;

pub struct Feed;
pub static FEED:Feed=Feed;

/// 订这些看盘键的 1 分钟 K 线要发的帧。
pub fn subscribe_frames(symbols:&[String])->Vec<String> {
 let args:Vec<Value>=symbols.iter().filter_map(|s|super::inst_id(s)).map(|inst|serde_json::json!({"channel":"candle1m","instId":inst})).collect();
 args.chunks(ARGS_PER_MESSAGE).map(|chunk|serde_json::json!({"op":"subscribe","args":chunk}).to_string()).collect()
}

/// 一帧推送 → 1 分钟 K 线（看盘键）。订阅回执、`pong`、错误帧什么都不给。
pub fn decode(text:&str,out:&mut Vec<Tick>) {
 let Ok(v)=serde_json::from_str::<Value>(text) else {return};
 if v["arg"]["channel"]!="candle1m" {return}
 let Some(symbol)=v["arg"]["instId"].as_str().and_then(super::key_of) else {return};
 for row in v["data"].as_array().into_iter().flatten() {
  let n=|i:usize|row[i].as_str().and_then(|s|s.parse::<f64>().ok()).filter(|x|x.is_finite());
  let (Some(open_time),Some(high),Some(low),Some(close))=(row[0].as_str().and_then(|s|s.parse::<i64>().ok()),n(2),n(3),n(4)) else {continue};
  out.push(Tick::Bar(Candle{symbol:symbol.clone(),open_time,low,high,close,closed:row[8].as_str()==Some("1")}));
 }
}

impl KlineFeed for Feed {
 fn venue(&self)->&'static dyn crate::venues::Venue {&super::OKX}
 fn task(&self)->&'static str {"alerts-okx"}
 fn keepalive(&self)->Option<(Duration,&'static str)> {Some((Duration::from_secs(20),"ping"))}
 fn connect<'a>(&'a self,symbols:&'a [String])->Fut<'a,anyhow::Result<Socket>> {
  Box::pin(crate::alerts::dial(super::WS_BUSINESS,subscribe_frames(symbols)))
 }
 fn decode(&self,text:&str,out:&mut Vec<Tick>) {decode(text,out)}
}

#[cfg(test)]
mod tests {
 use super::*;

 #[test] fn subscriptions_are_chunked_candle1m_frames() {
  let symbols:Vec<String>=(0..25).map(|i|format!("C{i}USDT")).collect();
  let frames=subscribe_frames(&symbols);
  assert_eq!(frames.len(),2);
  let first:Value=serde_json::from_str(&frames[0]).unwrap();
  assert_eq!(first["args"][0],serde_json::json!({"channel":"candle1m","instId":"C0-USDT-SWAP"}));
  assert_eq!(first["args"].as_array().unwrap().len(),20);
 }

 /// 夹具照官方文档的推送示例写。
 #[test] fn candle_pushes_become_bars_with_their_confirm_flag() {
  let mut out=vec![];
  decode(r#"{"arg":{"channel":"candle1m","instId":"BTC-USDT-SWAP"},"data":[["1597026383085","8533.02","8553.74","8527.17","8548.26","45247","529.5858061","5281","1"]]}"#,&mut out);
  assert_eq!(out,vec![Tick::Bar(Candle{symbol:"BTCUSDT".into(),open_time:1_597_026_383_085,low:8527.17,high:8553.74,close:8548.26,closed:true})]);
  out.clear();
  decode(r#"{"arg":{"channel":"candle1m","instId":"BTC-USDT-SWAP"},"data":[["1597026383085","1","2","0.5","1.5","1","1","1","0"]]}"#,&mut out);
  assert!(matches!(&out[0],Tick::Bar(c) if !c.closed));
  out.clear();
  for other in ["pong",r#"{"event":"subscribe","arg":{"channel":"candle1m","instId":"BTC-USDT-SWAP"}}"#,
   r#"{"arg":{"channel":"candle1m","instId":"BTC-USD-SWAP"},"data":[["1","1","1","1","1","1","1","1","1"]]}"#] {decode(other,&mut out)}
  assert!(out.is_empty());
 }
}
