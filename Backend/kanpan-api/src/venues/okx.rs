//! OKX 永续的持仓量与资金费率。
//!
//! OKX 在看盘里不是用户可见的交易所：它只是币安永续在网关线路上的替身（币安的
//! `fapi` 在美国 VPS 上回 451）。网关线路上顶栏六格要的「仓」和「费率 / 结算」由这里供：
//!
//! - `open_interest`：由 `market_meta` 的 `/v1/market/open-interest?source=okx` 分发过来；
//! - `funding`：`/v1/market/funding?source=okx`，整张表一次给（见 `venues::funding`）。
//!
//! 两样都是 OKX 自己的数，不拿币安的顶（不混源）。
use crate::error::{ApiError,Result};
use crate::market_meta::{Cache,LIVE_TTL,OpenInterest,QUOTES,get_json,num,rows};
use serde_json::Value;
use std::collections::HashMap;
use std::sync::{Arc,OnceLock};
use std::time::Duration;

const OI_URL:&str="https://www.okx.com/api/v5/public/open-interest?instType=SWAP";
/// 官方文档（Public Data › Get funding rate）：`instId=ANY` 一次返回全部永续的当期费率。
/// 限速按「IP + 品种」算，每 2 秒 10 次；整张表缓存着答所有手机，一分钟最多问两次。
const FUNDING_URL:&str="https://www.okx.com/api/v5/public/funding-rate?instId=ANY";
/// 费率一期几个小时才结算一次，预测值在期内缓慢漂；手机一分钟来问一次，
/// 三十秒的表足够新，又不会让几台手机把上游敲成每秒一次。
const FUNDING_TTL:Duration=Duration::from_secs(30);
/// 十分钟没刷成功就不再答：再旧，「下次结算」可能已经过去了。
pub const FUNDING_MAX_AGE:Duration=Duration::from_secs(600);
/// 只给和币安 U 本位对得上的线性永续（`BTC-USDT-SWAP` → `BTCUSDT`）。币本位
/// （`BTC-USD-SWAP`）在币安 U 本位合约表里没有对应品种，不给。
const FUNDING_QUOTES:[&str;2]=["USDT","USDC"];
/// 整张表一起抓。十五分钟没刷成功就不再拿它答题：持仓量是分钟级的量，
/// 一刻钟前的表已经不是「现在」了。
pub const OI_MAX_AGE:Duration=Duration::from_secs(900);

fn cache()->&'static Cache<HashMap<String,OpenInterest>> {static C:OnceLock<Cache<HashMap<String,OpenInterest>>>=OnceLock::new();C.get_or_init(Cache::new)}
fn funding_cache()->&'static Cache<Vec<Funding>> {static C:OnceLock<Cache<Vec<Funding>>>=OnceLock::new();C.get_or_init(Cache::new)}

/// 一只永续的当期资金费率。`symbol` 是币安那种写法（`BTCUSDT`），手机按它对表。
#[derive(Clone,Debug,PartialEq)]
pub struct Funding {pub symbol:String,pub rate:f64,pub next_funding_time:i64}

/// `BTC-USDT-SWAP` → `BTCUSDT`；不是 U / USDC 本位永续的给 `None`。
pub fn plain_symbol(instrument:&str)->Option<String> {
 let up=instrument.to_ascii_uppercase();
 let pair=up.strip_suffix("-SWAP")?;
 let (base,quote)=pair.rsplit_once('-')?;
 if base.is_empty()||base.contains('-')||!FUNDING_QUOTES.contains(&quote) {return None}
 Some(format!("{base}{quote}"))
}

/// OKX `funding-rate?instId=ANY` 的一页。`fundingRate` 是下一次结算（`fundingTime`）
/// 要用的预测费率，和币安 `premiumIndex` 的 `lastFundingRate` + `nextFundingTime` 同义；
/// OKX 自己的 `nextFundingTime` 是再下一期，不用它。
pub fn parse_funding(body:&Value)->Vec<Funding> {
 let mut out:Vec<Funding>=rows(body).iter().filter_map(|row|{
  let symbol=plain_symbol(row["instId"].as_str()?)?;
  let rate=num(&row["fundingRate"])?;
  let time=row["fundingTime"].as_str().and_then(|t|t.parse().ok()).or_else(||row["fundingTime"].as_i64())?;
  (time>0).then_some(Funding{symbol,rate,next_funding_time:time})
 }).collect();
 out.sort_by(|a,b|a.symbol.cmp(&b.symbol));
 out
}

pub fn funding_payload(table:&[Funding])->Value {
 let rows:Vec<Value>=table.iter().map(|f|serde_json::json!({"symbol":f.symbol,"rate":f.rate,"nextFundingTime":f.next_funding_time})).collect();
 serde_json::json!({"source":"okx","rows":rows})
}

pub async fn funding()->Result<Arc<Vec<Funding>>> {
 if let Some(table)=funding_cache().fresh(FUNDING_TTL) {return Ok(table)}
 match get_json(FUNDING_URL).await {
  Ok(body)=>{
   let table=parse_funding(&body);
   // 上游回了个空表（换信封、限速回 code≠0）不当新表存：别拿一张空表盖掉好表。
   if table.is_empty() {return funding_cache().fresh(FUNDING_MAX_AGE).ok_or_else(ApiError::missing)}
   Ok(funding_cache().store(table))
  },
  Err(e)=>funding_cache().fresh(FUNDING_MAX_AGE).ok_or(e),
 }
}

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
 fn okx_funding_uses_the_upcoming_settlement() {
  let body=json!({"code":"0","data":[
   {"instId":"BTC-USDT-SWAP","instType":"SWAP","fundingRate":"0.0000182221218054","fundingTime":"1743609600000","nextFundingTime":"1743638400000"},
   {"instId":"ETH-USDC-SWAP","instType":"SWAP","fundingRate":"-0.0001","fundingTime":"1743609600000","nextFundingTime":"1743638400000"},
   {"instId":"BTC-USD-SWAP","instType":"SWAP","fundingRate":"0.0001","fundingTime":"1743609600000"},
   {"instId":"XAU-USDT-SWAP","instType":"SWAP","fundingRate":"","fundingTime":"1743609600000"},
   {"instId":"SOL-USDT-SWAP","instType":"SWAP","fundingRate":"0.0002","fundingTime":""}]});
  let table=parse_funding(&body);
  assert_eq!(table,vec![
   Funding{symbol:"BTCUSDT".into(),rate:0.0000182221218054,next_funding_time:1_743_609_600_000},
   Funding{symbol:"ETHUSDC".into(),rate:-0.0001,next_funding_time:1_743_609_600_000}]);
  assert_eq!(funding_payload(&table[..1]),json!({"source":"okx","rows":[{"symbol":"BTCUSDT","rate":0.0000182221218054,"nextFundingTime":1_743_609_600_000_i64}]}));
 }
 #[test]
 fn only_linear_swaps_map_back_to_binance_symbols() {
  assert_eq!(plain_symbol("btc-usdt-swap").as_deref(),Some("BTCUSDT"));
  assert_eq!(plain_symbol("1000PEPE-USDT-SWAP").as_deref(),Some("1000PEPEUSDT"));
  assert_eq!(plain_symbol("BTC-USD-SWAP"),None);
  assert_eq!(plain_symbol("BTC-USDT-250926"),None);
  assert_eq!(plain_symbol("USDT-SWAP"),None);
 }
 #[test]
 fn okx_instrument_ids_are_built_from_the_plain_symbol() {
  assert_eq!(instrument("BTCUSDT"),"BTC-USDT-SWAP");
  assert_eq!(instrument("btc-usdt-swap"),"BTC-USDT-SWAP");
  assert_eq!(instrument("PEPE-USDT"),"PEPE-USDT-SWAP");
 }
}
