//! Bybit 给服务端提醒评估的 1 分钟 K 线：linear 公开推送的 `kline.1.<SYMBOL>`（官方文档 WebSocket Stream ›
//! Public › Kline）。一帧 `{"topic":"kline.1.BTCUSDT","data":[{"start":…,"open":…,"high":…,"low":…,"close":…,"confirm":bool}]}`，
//! `confirm` 为真就是这一根收了。官方要求每 20 秒发一次 `{"op":"ping"}` 保活（回帧也算一帧）。
//! 主机连不上换 `stream.bytick.com`；断线补缺走 REST `kline`（经本家 `PACER`）。
use crate::alerts::{Candle,KlineFeed,Socket,Tick};
use crate::venues::Fut;
use serde_json::Value;
use std::time::Duration;

/// 一条订阅消息最多几个 args（三个 category 统一按现货的硬限 10）。
const ARGS_PER_MESSAGE:usize=10;

pub struct Feed;
pub static FEED:Feed=Feed;

pub fn subscribe_frames(symbols:&[String])->Vec<String> {
 let topics:Vec<String>=symbols.iter().filter(|s|super::symbol_ok(s)).map(|s|format!("kline.1.{s}")).collect();
 topics.chunks(ARGS_PER_MESSAGE).map(|chunk|serde_json::json!({"op":"subscribe","args":chunk}).to_string()).collect()
}

pub fn decode(text:&str,out:&mut Vec<Tick>) {
 let Ok(v)=serde_json::from_str::<Value>(text) else {return};
 let Some(symbol)=v["topic"].as_str().and_then(|t|t.strip_prefix("kline.1.")).filter(|s|super::symbol_ok(s)) else {return};
 for k in v["data"].as_array().into_iter().flatten() {
  let n=|key:&str|k[key].as_str().and_then(|s|s.parse::<f64>().ok()).filter(|x|x.is_finite());
  let (Some(open_time),Some(high),Some(low),Some(close))=(k["start"].as_i64(),n("high"),n("low"),n("close")) else {continue};
  out.push(Tick::Bar(Candle{symbol:symbol.to_owned(),open_time,low,high,close,closed:k["confirm"].as_bool()==Some(true)}));
 }
}

impl KlineFeed for Feed {
 fn venue(&self)->&'static dyn crate::venues::Venue {&super::BYBIT}
 fn task(&self)->&'static str {"alerts-bybit"}
 fn keepalive(&self)->Option<(Duration,&'static str)> {Some((Duration::from_secs(20),r#"{"op":"ping"}"#))}
 fn connect<'a>(&'a self,symbols:&'a [String])->Fut<'a,anyhow::Result<Socket>> {
  Box::pin(async move {
   let mut last=anyhow::anyhow!("no host");
   for base in super::WS_BASES {
    match crate::alerts::dial(&format!("{base}/linear"),subscribe_frames(symbols)).await {Ok(s)=>return Ok(s),Err(e)=>last=e}
   }
   Err(last)
  })
 }
 fn decode(&self,text:&str,out:&mut Vec<Tick>) {decode(text,out)}
}

#[cfg(test)]
mod tests {
 use super::*;

 #[test] fn subscriptions_are_kline_1_topics_ten_per_frame() {
  let symbols:Vec<String>=(0..11).map(|i|format!("C{i}USDT")).chain(["BTCPERP".to_string()]).collect();
  let frames=subscribe_frames(&symbols);
  assert_eq!(frames.len(),2);
  let first:Value=serde_json::from_str(&frames[0]).unwrap();
  assert_eq!(first["args"][0],"kline.1.C0USDT");
  assert_eq!(first["args"].as_array().unwrap().len(),10);
 }

 /// 夹具照官方文档的推送示例写。
 #[test] fn kline_pushes_become_bars() {
  let mut out=vec![];
  decode(r#"{"topic":"kline.1.BTCUSDT","data":[{"start":1672324800000,"end":1672324859999,"interval":"1","open":"16649.5","close":"16677","high":"16677","low":"16608","volume":"2.081","turnover":"34666.4005","confirm":false,"timestamp":1672324988882}],"ts":1672324988882,"type":"snapshot"}"#,&mut out);
  assert_eq!(out,vec![Tick::Bar(Candle{symbol:"BTCUSDT".into(),open_time:1_672_324_800_000,low:16608.0,high:16677.0,close:16677.0,closed:false})]);
  out.clear();
  for other in [r#"{"success":true,"ret_msg":"pong","op":"ping"}"#,r#"{"topic":"kline.5.BTCUSDT","data":[]}"#,r#"{"topic":"tickers.BTCUSDT","data":{}}"#] {decode(other,&mut out)}
  assert!(out.is_empty());
 }
}
