//! 币安在主力订单流里的那一截：品种表（U 本位 / 币本位 / 现货三张）。
//!
//! 取舍：只列在交易的（TRADING）；交割只列当季与次季（contractType CURRENT_QUARTER / NEXT_QUARTER）；
//! 现货只列 USDT 计价。合约把单价极小的币挂成「N 个币」一个单位（`1000PEPEUSDT`），三张表都按
//! 前缀找（`scaled`）。U 本位那张和 `market_meta` / `sector_history` 共用进程里那一份
//! （`market_meta::exchange_info`），不多拉一次。
use crate::venues::orderflow::{ExchangeKey,Margin,Notional,Product,Table,TableSource,Venue,boxed,get_bytes,index,number};
use serde::Deserialize;

pub const KEY:ExchangeKey=ExchangeKey("binance");
const SPOT:&str="https://data-api.binance.vision/api/v3/exchangeInfo?symbolStatus=TRADING&showPermissionSets=false";
const CM:&str="https://www.binance.com/dapi/v1/exchangeInfo";

// ------------------------------------------------------------------ 品种表

#[derive(Deserialize)]
struct Info {symbols:Vec<Symbol>}
#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
struct Symbol {
 symbol:String,
 #[serde(default)] status:String,
 /// dapi 用这个名字表示状态。
 #[serde(default)] contract_status:String,
 #[serde(default)] contract_type:String,
 base_asset:String,
 quote_asset:String,
 #[serde(default)] margin_asset:String,
 #[serde(default)] delivery_date:Option<i64>,
 #[serde(default)] contract_size:Option<f64>,
 #[serde(default="yes")] is_spot_trading_allowed:bool,
 #[serde(default)] filters:Vec<Filter>,
}
fn yes()->bool {true}
#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
struct Filter {filter_type:String,#[serde(default)] tick_size:Option<String>}
impl Symbol {
 fn tick(&self)->Option<f64> {
  self.filters.iter().find(|f|f.filter_type=="PRICE_FILTER").and_then(|f|f.tick_size.as_deref()).and_then(number)
 }
 fn quarter(&self)->bool {matches!(self.contract_type.as_str(),"CURRENT_QUARTER"|"NEXT_QUARTER")}
}

/// 币安 U 本位（fapi exchangeInfo）：USDT 永续（含 TRADIFI_PERPETUAL）与 USDT 交割的当季 / 次季。
pub fn parse_um(info:&serde_json::Value)->anyhow::Result<Table> {
 let info=Info::deserialize(info)?;
 let rows=info.symbols.into_iter().filter_map(|s| {
  if s.status!="TRADING"||s.quote_asset!="USDT"||s.margin_asset!="USDT" {return None}
  let tick=s.tick()?;
  let (product,margin,expiry)=match s.contract_type.as_str() {
   "PERPETUAL"|"TRADIFI_PERPETUAL"=>(Product::UsdtPerp,None,None),
   _ if s.quarter()=>(Product::Delivery,Some(Margin::Usdt),Some(s.delivery_date?)),
   _=>return None,
  };
  Some(Venue{exchange:KEY,product,instrument:s.symbol,margin,notional:Notional::Linear{multiplier:1.0},tick,expiry_ms:expiry,price_scale:None,listed_base:s.base_asset})
 }).collect();
 Ok(index(rows))
}

/// 币安币本位（dapi exchangeInfo）：币本位永续与币本位交割的当季 / 次季，一张合约 contractSize 美元。
pub fn parse_cm(body:&[u8])->anyhow::Result<Table> {
 let info:Info=serde_json::from_slice(body)?;
 let rows=info.symbols.into_iter().filter_map(|s| {
  if s.contract_status!="TRADING"||s.quote_asset!="USD" {return None}
  let tick=s.tick()?;
  let contract_usd=s.contract_size.filter(|v|v.is_finite()&&*v>0.0)?;
  let (product,margin,expiry)=match s.contract_type.as_str() {
   "PERPETUAL"=>(Product::CoinPerp,None,None),
   _ if s.quarter()=>(Product::Delivery,Some(Margin::Coin),Some(s.delivery_date?)),
   _=>return None,
  };
  Some(Venue{exchange:KEY,product,instrument:s.symbol,margin,notional:Notional::Inverse{contract_usd},tick,expiry_ms:expiry,price_scale:None,listed_base:s.base_asset})
 }).collect();
 Ok(index(rows))
}

/// 币安现货（data-api.binance.vision exchangeInfo）：只要 USDT 计价、在交易的。
pub fn parse_spot(body:&[u8])->anyhow::Result<Table> {
 let info:Info=serde_json::from_slice(body)?;
 let rows=info.symbols.into_iter().filter_map(|s| {
  if s.status!="TRADING"||s.quote_asset!="USDT"||!s.is_spot_trading_allowed {return None}
  let tick=s.tick()?;
  Some(Venue{exchange:KEY,product:Product::Spot,instrument:s.symbol,margin:None,notional:Notional::Linear{multiplier:1.0},tick,expiry_ms:None,price_scale:None,listed_base:s.base_asset})
 }).collect();
 Ok(index(rows))
}


pub fn tables()->Vec<TableSource> {
 vec![
  TableSource{name:"binance usdt-m",exchange:KEY,scaled:true,fetch:||boxed(async {let info=crate::market_meta::exchange_info().await.map_err(|e|anyhow::anyhow!("{}",e.1))?;parse_um(&info)})},
  TableSource{name:"binance coin-m",exchange:KEY,scaled:true,fetch:||boxed(async {parse_cm(&get_bytes(CM).await?)})},
  TableSource{name:"binance spot",exchange:KEY,scaled:true,fetch:||boxed(async {parse_spot(&get_bytes(SPOT).await?)})},
 ]
}

#[cfg(test)]
pub(crate) mod tests {
 use super::*;
 use serde_json::{Value,json};

 pub(crate) fn fapi()->Value {json!({"symbols":[
  {"symbol":"BTCUSDT","status":"TRADING","contractType":"PERPETUAL","baseAsset":"BTC","quoteAsset":"USDT","marginAsset":"USDT","deliveryDate":4133404800000_i64,"filters":[{"filterType":"PRICE_FILTER","tickSize":"0.10","minPrice":"556.80"},{"filterType":"LOT_SIZE","stepSize":"0.001"}]},
  {"symbol":"BTCUSDT_261225","status":"TRADING","contractType":"NEXT_QUARTER","baseAsset":"BTC","quoteAsset":"USDT","marginAsset":"USDT","deliveryDate":1798185600000_i64,"filters":[{"filterType":"PRICE_FILTER","tickSize":"0.1"}]},
  {"symbol":"BTCUSDT_260925","status":"TRADING","contractType":"CURRENT_QUARTER","baseAsset":"BTC","quoteAsset":"USDT","marginAsset":"USDT","deliveryDate":1790323200000_i64,"filters":[{"filterType":"PRICE_FILTER","tickSize":"0.1"}]},
  {"symbol":"BTCUSDC","status":"TRADING","contractType":"PERPETUAL","baseAsset":"BTC","quoteAsset":"USDC","marginAsset":"USDC","filters":[{"filterType":"PRICE_FILTER","tickSize":"0.1"}]},
  {"symbol":"ETHUSDT","status":"SETTLING","contractType":"PERPETUAL","baseAsset":"ETH","quoteAsset":"USDT","marginAsset":"USDT","filters":[{"filterType":"PRICE_FILTER","tickSize":"0.01"}]},
  {"symbol":"1000PEPEUSDT","status":"TRADING","contractType":"PERPETUAL","baseAsset":"1000PEPE","quoteAsset":"USDT","marginAsset":"USDT","filters":[{"filterType":"PRICE_FILTER","tickSize":"0.0000001"}]},
  {"symbol":"TSLAUSDT","status":"TRADING","contractType":"TRADIFI_PERPETUAL","baseAsset":"TSLA","quoteAsset":"USDT","marginAsset":"USDT","filters":[{"filterType":"PRICE_FILTER","tickSize":"0.01"}]}
 ]})}
 const DAPI:&str=r#"{"symbols":[
  {"symbol":"BTCUSD_PERP","pair":"BTCUSD","contractType":"PERPETUAL","deliveryDate":4133404800000,"contractStatus":"TRADING","baseAsset":"BTC","quoteAsset":"USD","marginAsset":"BTC","contractSize":100,"filters":[{"minPrice":"1000","filterType":"PRICE_FILTER","tickSize":"0.1","maxPrice":"4520958"}]},
  {"symbol":"BTCUSD_260925","pair":"BTCUSD","contractType":"CURRENT_QUARTER","deliveryDate":1790323200000,"contractStatus":"TRADING","baseAsset":"BTC","quoteAsset":"USD","marginAsset":"BTC","contractSize":100,"filters":[{"tickSize":"0.1","filterType":"PRICE_FILTER"}]},
  {"symbol":"BTCUSD_261225","pair":"BTCUSD","contractType":"NEXT_QUARTER","deliveryDate":1798185600000,"contractStatus":"TRADING","baseAsset":"BTC","quoteAsset":"USD","marginAsset":"BTC","contractSize":100,"filters":[{"tickSize":"0.1","filterType":"PRICE_FILTER"}]},
  {"symbol":"DOGEUSD_PERP","pair":"DOGEUSD","contractType":"PERPETUAL","deliveryDate":4133404800000,"contractStatus":"TRADING","baseAsset":"DOGE","quoteAsset":"USD","marginAsset":"DOGE","contractSize":10,"filters":[{"tickSize":"0.000010","filterType":"PRICE_FILTER"}]},
  {"symbol":"ETHUSD_260626","pair":"ETHUSD","contractType":"CURRENT_QUARTER","deliveryDate":1782460800000,"contractStatus":"DELIVERING","baseAsset":"ETH","quoteAsset":"USD","marginAsset":"ETH","contractSize":10,"filters":[{"tickSize":"0.01","filterType":"PRICE_FILTER"}]}
 ]}"#;
 const SPOT:&str=r#"{"timezone":"UTC","symbols":[
  {"symbol":"BTCUSDT","status":"TRADING","baseAsset":"BTC","quoteAsset":"USDT","isSpotTradingAllowed":true,"filters":[{"filterType":"PRICE_FILTER","minPrice":"0.01000000","maxPrice":"1000000.00000000","tickSize":"0.01000000"},{"filterType":"LOT_SIZE","minQty":"0.00001000"}]},
  {"symbol":"BTCFDUSD","status":"TRADING","baseAsset":"BTC","quoteAsset":"FDUSD","isSpotTradingAllowed":true,"filters":[{"filterType":"PRICE_FILTER","tickSize":"0.01000000"}]},
  {"symbol":"DOGEUSDT","status":"TRADING","baseAsset":"DOGE","quoteAsset":"USDT","isSpotTradingAllowed":true,"filters":[{"filterType":"PRICE_FILTER","tickSize":"0.00001000"}]},
  {"symbol":"PEPEUSDT","status":"TRADING","baseAsset":"PEPE","quoteAsset":"USDT","isSpotTradingAllowed":true,"filters":[{"filterType":"PRICE_FILTER","tickSize":"0.00000001"}]},
  {"symbol":"LUNAUSDT","status":"BREAK","baseAsset":"LUNA","quoteAsset":"USDT","filters":[{"filterType":"PRICE_FILTER","tickSize":"0.0001"}]}
 ]}"#;

 /// 三张表的夹具（顺序同 [`tables`]）。
 pub(crate) fn fixtures()->Vec<Table> {
  vec![parse_um(&fapi()).unwrap(),parse_cm(DAPI.as_bytes()).unwrap(),parse_spot(SPOT.as_bytes()).unwrap()]
 }

 fn names(table:&Table,base:&str)->Vec<String> {table.get(base).map(|rows|rows.iter().map(|v|v.instrument.clone()).collect()).unwrap_or_default()}

 #[test]
 fn what_is_left_out() {
  let [um,cm,spot]=<[Table;3]>::try_from(fixtures()).ok().unwrap();
  assert_eq!(names(&um,"BTC"),["BTCUSDT","BTCUSDT_260925","BTCUSDT_261225"],"USDC 本位不列");
  assert!(names(&um,"ETH").is_empty(),"SETTLING 不列");
  assert_eq!(names(&um,"TSLA"),["TSLAUSDT"],"股票永续也是 U 本位永续");
  assert_eq!(names(&um,"1000PEPE"),["1000PEPEUSDT"],"按挂的 base 建索引，前缀由取的时候认");
  assert_eq!(names(&cm,"BTC"),["BTCUSD_PERP","BTCUSD_260925","BTCUSD_261225"]);
  assert!(names(&cm,"ETH").is_empty(),"DELIVERING 不列");
  assert_eq!(names(&spot,"BTC"),["BTCUSDT"],"FDUSD 计价不列");
  assert!(names(&spot,"LUNA").is_empty());
  assert_eq!(cm["DOGE"][0].notional,Notional::Inverse{contract_usd:10.0});
 }

 #[test]
 fn broken_upstream_bodies_are_errors_not_empty_tables() {
  assert!(parse_cm(b"<html>challenge</html>").is_err());
  assert!(parse_um(&json!({"code":-1003})).is_err());
  let _:Value=fapi();
 }
}
