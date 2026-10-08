//! Hyperliquid 给服务端提醒评估的 1 分钟 K 线：`candle` 订阅（`interval:"1m"`，官方文档 WebSocket › Subscriptions）。
//! 一帧 `{"channel":"candle","data":{"t":…,"s":"kPEPE","i":"1m","o":…,"h":…,"l":…,"c":…}}`，没有「收了」的标记：
//! 由评估循环按「下一根到了 / 过了收盘宽限」替它收。
//!
//! 评估器跑在 worker 进程里，和 api 进程那条共用 hub 不在一个进程，所以自己开一条连接（每 IP 10 条的硬限
//! 里只占一条）。订阅要上游原名（`kPEPE`），连接前按 `meta` 译好；帧里的原名大写成看盘键。
//! 每 30 秒发一次 `{"method":"ping"}`（回 `{"channel":"pong"}`，也算一帧）。
use crate::alerts::{Candle,KlineFeed,Socket,Tick};
use crate::venues::Fut;
use serde_json::Value;
use std::time::Duration;

pub struct Feed;
pub static FEED:Feed=Feed;

/// 一只的订阅帧（`coin` 是上游原名）。
pub fn subscribe_frame(coin:&str)->String {
 serde_json::json!({"method":"subscribe","subscription":{"type":"candle","coin":coin,"interval":"1m"}}).to_string()
}

pub fn decode(text:&str,out:&mut Vec<Tick>) {
 let Ok(v)=serde_json::from_str::<Value>(text) else {return};
 if v["channel"]!="candle" {return}
 let one=|c:&Value|{
  if c["i"]!="1m" {return None}
  let symbol=c["s"].as_str().filter(|s|super::hub::valid_coin(s))?.to_ascii_uppercase();
  let bar=super::parse_candle(c)?;
  Some(Tick::Bar(Candle{symbol,open_time:bar.open_time,low:bar.low,high:bar.high,close:bar.close,closed:false}))
 };
 match &v["data"] {
  Value::Array(rows)=>out.extend(rows.iter().filter_map(one)),
  data=>out.extend(one(data)),
 }
}

impl KlineFeed for Feed {
 fn venue(&self)->&'static dyn crate::venues::Venue {&super::HYPERLIQUID}
 fn task(&self)->&'static str {"alerts-hyperliquid"}
 /// 每 IP 最多 1000 个订阅，这条连接只拿一小份（api 进程那条 hub 还要用）。
 fn max_symbols(&self)->usize {100}
 fn keepalive(&self)->Option<(Duration,&'static str)> {Some((Duration::from_secs(30),r#"{"method":"ping"}"#))}
 fn connect<'a>(&'a self,symbols:&'a [String])->Fut<'a,anyhow::Result<Socket>> {
  Box::pin(async move {
   let mut frames=Vec::with_capacity(symbols.len());
   for key in symbols {
    match super::coin_name(key).await {
     Ok(coin)=>frames.push(subscribe_frame(&coin)),
     // 品种表里没有（下架了、键写错了）：这一只不订，别的照订；表拿不到就整条重连再试。
     Err(crate::venues::outbound::Upstream::Rejected(_))=>tracing::warn!("Hyperliquid has no coin {key}; its alerts are not watched"),
     Err(e)=>anyhow::bail!("Hyperliquid coin names are unavailable ({e:?})"),
    }
   }
   crate::alerts::dial(super::hub::WS,frames).await
  })
 }
 fn decode(&self,text:&str,out:&mut Vec<Tick>) {decode(text,out)}
}

#[cfg(test)]
mod tests {
 use super::*;

 #[test] fn candle_pushes_become_bars_under_the_upper_key() {
  let mut out=vec![];
  decode(r#"{"channel":"candle","data":{"t":1681923600000,"T":1681923659999,"s":"kPEPE","i":"1m","o":"0.01","c":"0.012","h":"0.013","l":"0.009","v":"10","n":3}}"#,&mut out);
  assert_eq!(out,vec![Tick::Bar(Candle{symbol:"KPEPE".into(),open_time:1_681_923_600_000,low:0.009,high:0.013,close:0.012,closed:false})]);
  out.clear();
  decode(r#"{"channel":"candle","data":[{"t":1,"s":"BTC","i":"1m","o":"1","c":"1","h":"1","l":"1","v":"1"}]}"#,&mut out);
  assert_eq!(out.len(),1,"数组形状也认");
  out.clear();
  for other in [r#"{"channel":"pong"}"#,r#"{"channel":"candle","data":{"t":1,"s":"BTC","i":"5m","o":"1","c":"1","h":"1","l":"1","v":"1"}}"#,r#"{"channel":"subscriptionResponse","data":{}}"#] {decode(other,&mut out)}
  assert!(out.is_empty());
  assert_eq!(subscribe_frame("kPEPE"),r#"{"method":"subscribe","subscription":{"coin":"kPEPE","interval":"1m","type":"candle"}}"#);
 }
}
