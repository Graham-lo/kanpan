//! OKX 永续的持仓量。
//!
//! OKX 在看盘里不是用户可见的交易所：它只是币安永续在网关线路上的替身（币安的
//! `fapi` 在美国 VPS 上回 451）。这里只剩一件事——网关线路上的持仓量副图——所以
//! 这一族也只有一个出口 `open_interest`，由 `market_meta` 的 `source=okx` 分发过来。
use crate::error::{ApiError,Result};
use crate::market_meta::{Cache,LIVE_TTL,OpenInterest,QUOTES,get_json,num,rows};
use serde_json::Value;
use std::collections::HashMap;
use std::sync::OnceLock;
use std::time::Duration;

const OI_URL:&str="https://www.okx.com/api/v5/public/open-interest?instType=SWAP";
/// 整张表一起抓。十五分钟没刷成功就不再拿它答题：持仓量是分钟级的量，
/// 一刻钟前的表已经不是「现在」了。
pub const OI_MAX_AGE:Duration=Duration::from_secs(900);

fn cache()->&'static Cache<HashMap<String,OpenInterest>> {static C:OnceLock<Cache<HashMap<String,OpenInterest>>>=OnceLock::new();C.get_or_init(Cache::new)}

/// `BTCUSDT` -> `BTC-USDT-SWAP`; an instrument id passed in as-is stays intact.
pub fn instrument(symbol:&str)->String {
 let up=symbol.to_ascii_uppercase();
 if up.contains('-') {return if up.ends_with("-SWAP"){up}else{format!("{up}-SWAP")}}
 let clean:String=up.chars().filter(char::is_ascii_alphanumeric).collect();
 for quote in QUOTES {
  if let Some(rest)=clean.strip_suffix(quote)&& !rest.is_empty() {return format!("{rest}-{quote}-SWAP")}
 }
 format!("{clean}-USDT-SWAP")
}

/// OKX sends every swap at once: `oiCcy` is coin-denominated, `oiUsd` notional.
pub fn parse_oi(body:&Value)->HashMap<String,OpenInterest> {
 let mut out=HashMap::new();
 for row in rows(body) {
  let Some(instrument)=row["instId"].as_str() else {continue};
  let Some(amount)=num(&row["oiCcy"]).or_else(||num(&row["oi"])) else {continue};
  let time=row["ts"].as_str().and_then(|t|t.parse().ok()).or_else(||row["ts"].as_i64()).unwrap_or(0);
  out.insert(instrument.to_ascii_uppercase(),OpenInterest{open_interest:amount,value:num(&row["oiUsd"]),time});
 }
 out
}

pub async fn open_interest(symbol:&str)->Result<OpenInterest> {
 let table=match cache().fresh(LIVE_TTL) {
  Some(table)=>table,
  // 一刻钟没刷成功就不再拿旧表答题：持仓量是分钟级的量。
  None=>match get_json(OI_URL).await {Ok(body)=>cache().store(parse_oi(&body)),Err(e)=>cache().fresh(OI_MAX_AGE).ok_or(e)?}
 };
 table.get(&instrument(symbol)).copied().ok_or_else(ApiError::missing)
}

#[cfg(test)]
mod tests {
 use super::*;
 use serde_json::json;

 #[test]
 fn okx_swaps_parse_with_their_own_notional() {
  let body=json!({"code":"0","data":[{"instId":"BTC-USDT-SWAP","oi":"1084317","oiCcy":"10843.17","oiUsd":"832000000","ts":"1789661435379"}]});
  let table=parse_oi(&body);
  let oi=table["BTC-USDT-SWAP"];
  assert_eq!(oi.open_interest,10_843.17);
  assert_eq!(oi.value,Some(832_000_000.0));
  assert_eq!(oi.time,1_789_661_435_379);
 }
 #[test]
 fn okx_instrument_ids_are_built_from_the_plain_symbol() {
  assert_eq!(instrument("BTCUSDT"),"BTC-USDT-SWAP");
  assert_eq!(instrument("btc-usdt-swap"),"BTC-USDT-SWAP");
  assert_eq!(instrument("PEPE-USDT"),"PEPE-USDT-SWAP");
 }
}
