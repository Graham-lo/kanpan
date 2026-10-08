//! Hyperliquid 在主力订单流里的那一截：品种表（只有永续，USDC 结算，按 U 本位永续列）。
//!
//! 表：`POST https://api.hyperliquid.xyz/info {"type":"meta"}`，答复 `universe` 每项一只永续
//! （`name` 就是订流用的币名，`szDecimals` 是数量的小数位）。取舍：
//! * `isDelisted` 的不列；
//! * 价格最多 `6 − szDecimals` 位小数（另有 5 位有效数字的限制，那是按价位的，不算进 tick），
//!   所以 tick = 10^-(6−szDecimals)；
//! * 单价极小的币挂成 `kPEPE`（价格与数量按 1000 个币报）：`priceScale=1000`，按 base `PEPE` 列，
//!   和币安 / Bybit 的 `1000PEPEUSDT` 落在同一只币下；
//! * 线性，一个数量单位就是一个（`k` 的是 1000 个）币：multiplier 1。
use crate::venues::orderflow::{ExchangeKey,Notional,Product,Table,TableSource,Venue,boxed,index};
use serde::Deserialize;

pub const KEY:ExchangeKey=ExchangeKey("hyperliquid");

// ------------------------------------------------------------------ 品种表

#[derive(Deserialize)]
struct Meta {universe:Vec<Asset>}
#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
struct Asset {
 name:String,
 sz_decimals:u32,
 #[serde(default)] is_delisted:bool,
}

/// `kPEPE` → (`PEPE`, 1000)；别的原样、不带倍数。
pub fn listed(name:&str)->(&str,Option<u64>) {
 match name.strip_prefix('k') {
  Some(rest) if rest.bytes().next().is_some_and(|b|b.is_ascii_uppercase())=>(rest,Some(1000)),
  _=>(name,None),
 }
}

/// 价格最多几位小数对应的 tick。
pub fn tick(sz_decimals:u32)->Option<f64> {(sz_decimals<=6).then(||10f64.powi(-(6-sz_decimals as i32)))}

pub fn parse_meta(body:&[u8])->anyhow::Result<Table> {
 let meta:Meta=serde_json::from_slice(body)?;
 let rows=meta.universe.into_iter().filter(|a|!a.is_delisted).filter_map(|a| {
  if !super::hub::valid_coin(&a.name) {return None}
  let (base,price_scale)=listed(&a.name);
  if !crate::orderflow_instruments::valid_base(base) {return None}
  let base=base.to_owned();
  let tick=tick(a.sz_decimals)?;
  Some(Venue{exchange:KEY,product:Product::UsdtPerp,instrument:a.name,margin:None,notional:Notional::Linear{multiplier:1.0},tick,expiry_ms:None,price_scale,listed_base:base})
 }).collect();
 Ok(index(rows))
}

pub fn tables()->Vec<TableSource> {
 vec![TableSource{name:"hyperliquid perps",exchange:KEY,scaled:false,fetch:||boxed(async {parse_meta(&super::info_bytes(&serde_json::json!({"type":"meta"})).await?)})}]
}

#[cfg(test)]
pub(crate) mod tests {
 use super::*;

 // 2026-10-08 从 api.hyperliquid.xyz 拉的真 meta 里挑的几项（marginTables 裁掉了）。
 pub(crate) const META:&str=r#"{"universe":[
  {"szDecimals":5,"name":"BTC","maxLeverage":40,"marginTableId":56},
  {"szDecimals":4,"name":"ETH","maxLeverage":25,"marginTableId":55},
  {"szDecimals":1,"name":"MATIC","maxLeverage":20,"marginTableId":20,"isDelisted":true},
  {"szDecimals":2,"name":"SOL","maxLeverage":20,"marginTableId":54},
  {"szDecimals":0,"name":"DOGE","maxLeverage":10,"marginTableId":52},
  {"szDecimals":0,"name":"kPEPE","maxLeverage":10,"marginTableId":52}
 ],"marginTables":[],"collateralToken":0}"#;

 pub(crate) fn fixtures()->Vec<Table> {vec![parse_meta(META.as_bytes()).unwrap()]}

 #[test]
 fn meta_rows_with_tick_scale_and_delisted() {
  let table=&fixtures()[0];
  let row=|base:&str|table[base][0].clone();
  assert_eq!((row("BTC").instrument.as_str(),row("BTC").tick),("BTC",0.1));
  assert_eq!(row("ETH").tick,0.01);
  assert_eq!(row("SOL").tick,0.0001);
  assert_eq!(row("DOGE").tick,0.000001);
  let pepe=row("PEPE");
  assert_eq!((pepe.instrument.as_str(),pepe.price_scale,pepe.tick),("kPEPE",Some(1000),0.000001));
  assert!(!table.contains_key("kPEPE"));
  assert!(!table.contains_key("MATIC"),"下架的不列");
  assert!(table.values().flatten().all(|v|v.product==Product::UsdtPerp&&v.notional==Notional::Linear{multiplier:1.0}));
 }

 #[test]
 fn the_k_prefix_is_only_a_lowercase_k_before_a_capital() {
  assert_eq!(listed("kPEPE"),("PEPE",Some(1000)));
  assert_eq!(listed("kBONK"),("BONK",Some(1000)));
  assert_eq!(listed("BTC"),("BTC",None));
  assert_eq!(listed("k"),("k",None));
  assert_eq!(listed("kaito"),("kaito",None));
  assert_eq!(tick(7),None);
 }

 #[test]
 fn broken_bodies_are_errors() {
  assert!(parse_meta(br#"{"error":"busy"}"#).is_err());
  assert!(parse_meta(b"null").is_err());
 }
}
