//! Coinbase 在主力订单流里的那一截：品种表（只有现货，USD 计价）。
//!
//! 取舍：只列 online 且没停交易的 USD 计价现货；USDT / EUR 计价不列。
use crate::venues::orderflow::{ExchangeKey,Notional,Product,Table,TableSource,Venue,boxed,get_bytes,index,number};
use serde::Deserialize;

pub const KEY:ExchangeKey=ExchangeKey("coinbase");
const PRODUCTS:&str="https://api.exchange.coinbase.com/products";

// ------------------------------------------------------------------ 品种表

#[derive(Deserialize)]
struct Listing {
 id:String,
 base_currency:String,
 quote_currency:String,
 #[serde(default)] quote_increment:String,
 #[serde(default)] status:String,
 #[serde(default)] trading_disabled:bool,
}

/// Coinbase 现货：只要 USD 计价、online 且没停交易的。
pub fn parse(body:&[u8])->anyhow::Result<Table> {
 let products:Vec<Listing>=serde_json::from_slice(body)?;
 let rows=products.into_iter().filter_map(|p| {
  if p.status!="online"||p.trading_disabled||p.quote_currency!="USD" {return None}
  let tick=number(&p.quote_increment)?;
  Some(Venue{exchange:KEY,product:Product::Spot,instrument:p.id,margin:None,notional:Notional::Linear{multiplier:1.0},tick,expiry_ms:None,price_scale:None,listed_base:p.base_currency})
 }).collect();
 Ok(index(rows))
}

pub fn tables()->Vec<TableSource> {
 vec![TableSource{name:"coinbase spot",exchange:KEY,scaled:false,fetch:||boxed(async {parse(&get_bytes(PRODUCTS).await?)})}]
}

#[cfg(test)]
pub(crate) mod tests {
 use super::*;

 const COINBASE_FIX:&str=r#"[
  {"id":"BTC-USD","base_currency":"BTC","quote_currency":"USD","quote_increment":"0.01","base_increment":"0.00000001","status":"online","trading_disabled":false},
  {"id":"BTC-EUR","base_currency":"BTC","quote_currency":"EUR","quote_increment":"0.01","status":"online","trading_disabled":false},
  {"id":"BTC-USDT","base_currency":"BTC","quote_currency":"USDT","quote_increment":"0.01","status":"online","trading_disabled":false},
  {"id":"DOGE-USD","base_currency":"DOGE","quote_currency":"USD","quote_increment":"0.00001","status":"online","trading_disabled":false},
  {"id":"OLD-USD","base_currency":"OLD","quote_currency":"USD","quote_increment":"0.01","status":"delisted","trading_disabled":true},
  {"id":"HALT-USD","base_currency":"HALT","quote_currency":"USD","quote_increment":"0.01","status":"online","trading_disabled":true}
 ]"#;


 pub(crate) fn fixtures()->Vec<Table> {vec![parse(COINBASE_FIX.as_bytes()).unwrap()]}

 #[test]
 fn what_is_left_out() {
  let table=&fixtures()[0];
  let btc:Vec<&str>=table["BTC"].iter().map(|v|v.instrument.as_str()).collect();
  assert_eq!(btc,["BTC-USD"],"EUR / USDT 计价不列");
  assert!(!table.contains_key("OLD")&&!table.contains_key("HALT"),"下架的、停交易的不列");
 }

 #[test]
 fn broken_upstream_bodies_are_errors_not_empty_tables() {
  assert!(parse(br#"{"message":"rate limited"}"#).is_err());
 }
}
