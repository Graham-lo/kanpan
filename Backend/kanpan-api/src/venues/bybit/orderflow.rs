//! Bybit 在主力订单流里的那一截：品种表（linear / inverse / spot 三张）。
//!
//! 表：`GET /v5/market/instruments-info?category=spot|linear|inverse&limit=1000`，合约按
//! `result.nextPageCursor` 翻页（现货一页给全、不带游标）。主机 `api.bybit.com`，连不上换 `api.bytick.com`。
//!
//! 取舍：只列 `status=Trading` 的——
//! * 现货：只要 USDT 计价；
//! * U 本位永续：`LinearPerpetual` 且计价 / 结算都是 USDT（USDC 永续 `BTCPERP` 不列）；
//! * 币本位永续：`InversePerpetual`，一张 1 美元；
//! * 交割：`LinearFutures`（USDT，U 本位交割）与 `InverseFutures`（币本位交割），只要当季与次季。
//!   Bybit 没有 alias 字段，季度合约按「交割日在 3/6/9/12 月的最后一个周五（UTC）」认，周 / 月合约
//!   不列；每只币每种保证金取还没到期的最早两张。
//!
//! 合约把单价极小的币挂成 `1000PEPEUSDT`（baseCoin `1000PEPE`），和币安同一张前缀表（`scaled`）。
//! `SHIB1000` 这种前缀在后面的、`10000` 这种不在前缀表里的，不认（列不进对应的 base）。
use crate::venues::orderflow::{ExchangeKey,Margin,Notional,Product,Table,TableSource,Venue,boxed,index,number};
use chrono::{Datelike,TimeZone,Weekday};
use serde::Deserialize;

pub const KEY:ExchangeKey=ExchangeKey("bybit");
/// 一张表最多翻几页（linear 现在约 900 行，一页就够；留足余量又不至于死循环）。
const MAX_PAGES:usize=20;

// ------------------------------------------------------------------ 品种表

#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
struct Page {ret_code:i64,#[serde(default)] ret_msg:String,result:Option<PageResult>}
#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
struct PageResult {#[serde(default)] list:Vec<Instrument>,#[serde(default)] next_page_cursor:Option<String>}

#[derive(Clone,Deserialize)]
#[serde(rename_all="camelCase")]
pub struct Instrument {
 symbol:String,
 #[serde(default)] contract_type:String,
 #[serde(default)] status:String,
 #[serde(default)] base_coin:String,
 #[serde(default)] quote_coin:String,
 #[serde(default)] settle_coin:String,
 #[serde(default)] delivery_time:String,
 #[serde(default)] price_filter:PriceFilter,
}
#[derive(Clone,Default,Deserialize)]
#[serde(rename_all="camelCase")]
struct PriceFilter {#[serde(default)] tick_size:String}

impl Instrument {
 fn tick(&self)->Option<f64> {number(&self.price_filter.tick_size)}
 fn expiry(&self)->Option<i64> {self.delivery_time.trim().parse::<i64>().ok().filter(|t|*t>0)}
}

/// 一页答复：这一页的行与下一页的游标（空的算没有）。`retCode` 不是 0 就是错，不当空表。
pub fn parse_page(body:&[u8])->anyhow::Result<(Vec<Instrument>,Option<String>)> {
 let page:Page=serde_json::from_slice(body)?;
 anyhow::ensure!(page.ret_code==0,"answered retCode {} {}",page.ret_code,page.ret_msg);
 let result=page.result.ok_or_else(||anyhow::anyhow!("no result"))?;
 Ok((result.list,result.next_page_cursor.filter(|c|!c.is_empty())))
}

/// 交割日是不是季度合约那天：3 / 6 / 9 / 12 月的最后一个周五（UTC）。
pub fn quarterly(expiry_ms:i64)->bool {
 let Some(at)=chrono::Utc.timestamp_millis_opt(expiry_ms).single() else {return false};
 let day=at.date_naive();
 matches!(day.month(),3|6|9|12)&&day.weekday()==Weekday::Fri&&(day+chrono::Days::new(7)).month()!=day.month()
}

/// 交割里每只币每种保证金只留还没到期的最早两张季度合约（当季、次季）。
fn two_quarters(mut rows:Vec<Venue>,now_ms:i64)->Vec<Venue> {
 rows.retain(|v|v.product!=Product::Delivery||v.expiry_ms.is_some_and(|at|at>now_ms&&quarterly(at)));
 rows.sort_by(|a,b|(a.listed_base.as_str(),a.rank()).cmp(&(b.listed_base.as_str(),b.rank())));
 let mut seen:std::collections::HashMap<(String,Option<Margin>),usize>=std::collections::HashMap::new();
 rows.retain(|v| {
  if v.product!=Product::Delivery {return true}
  let n=seen.entry((v.listed_base.clone(),v.margin)).or_default();
  *n+=1;
  *n<=2
 });
 rows
}

/// linear：USDT 永续与 USDT 交割（当季 / 次季）。
pub fn parse_linear(rows:Vec<Instrument>,now_ms:i64)->Table {
 let rows=rows.into_iter().filter_map(|i| {
  if i.status!="Trading"||i.quote_coin!="USDT"||i.settle_coin!="USDT" {return None}
  let tick=i.tick()?;
  let (product,margin,expiry)=match i.contract_type.as_str() {
   "LinearPerpetual"=>(Product::UsdtPerp,None,None),
   "LinearFutures"=>(Product::Delivery,Some(Margin::Usdt),Some(i.expiry()?)),
   _=>return None,
  };
  Some(Venue{exchange:KEY,product,instrument:i.symbol,margin,notional:Notional::Linear{multiplier:1.0},tick,expiry_ms:expiry,price_scale:None,listed_base:i.base_coin})
 }).collect();
 index(two_quarters(rows,now_ms))
}

/// inverse：币本位永续与币本位交割（当季 / 次季），一张 1 美元。
pub fn parse_inverse(rows:Vec<Instrument>,now_ms:i64)->Table {
 let rows=rows.into_iter().filter_map(|i| {
  if i.status!="Trading"||i.quote_coin!="USD" {return None}
  let tick=i.tick()?;
  let (product,margin,expiry)=match i.contract_type.as_str() {
   "InversePerpetual"=>(Product::CoinPerp,None,None),
   "InverseFutures"=>(Product::Delivery,Some(Margin::Coin),Some(i.expiry()?)),
   _=>return None,
  };
  Some(Venue{exchange:KEY,product,instrument:i.symbol,margin,notional:Notional::Inverse{contract_usd:1.0},tick,expiry_ms:expiry,price_scale:None,listed_base:i.base_coin})
 }).collect();
 index(two_quarters(rows,now_ms))
}

/// spot：只要 USDT 计价。
pub fn parse_spot(rows:Vec<Instrument>)->Table {
 let rows=rows.into_iter().filter_map(|i| {
  if i.status!="Trading"||i.quote_coin!="USDT" {return None}
  let tick=i.tick()?;
  Some(Venue{exchange:KEY,product:Product::Spot,instrument:i.symbol,margin:None,notional:Notional::Linear{multiplier:1.0},tick,expiry_ms:None,price_scale:None,listed_base:i.base_coin})
 }).collect();
 index(rows)
}

/// 游标原样带上（Bybit 给的已经是转义过的），只把不该出现在查询串里的字符转义掉。
fn cursor_component(cursor:&str)->String {
 let mut out=String::new();
 for b in cursor.bytes() {
  if b.is_ascii_alphanumeric()||matches!(b,b'-'|b'_'|b'.'|b'~'|b'%') {out.push(b as char)} else {out.push_str(&format!("%{b:02X}"))}
 }
 out
}

/// 拉一个 category 的全部行（翻页，每页主机按先后试）。
async fn fetch(category:&str)->anyhow::Result<Vec<Instrument>> {
 let mut rows=Vec::new();
 let mut cursor:Option<String>=None;
 for _ in 0..MAX_PAGES {
  let query=match &cursor {Some(c)=>format!("category={category}&limit=1000&cursor={}",cursor_component(c)),None=>format!("category={category}&limit=1000")};
  let (page,next)=parse_page(&super::rest_bytes(&format!("v5/market/instruments-info?{query}")).await?)?;
  rows.extend(page);
  match next {Some(next) if cursor.as_deref()!=Some(next.as_str())=>cursor=Some(next),_=>return Ok(rows)}
 }
 anyhow::bail!("{category}: more than {MAX_PAGES} pages")
}

fn now_ms()->i64 {chrono::Utc::now().timestamp_millis()}

pub fn tables()->Vec<TableSource> {
 vec![
  TableSource{name:"bybit linear",exchange:KEY,scaled:true,fetch:||boxed(async {Ok(parse_linear(fetch("linear").await?,now_ms()))})},
  TableSource{name:"bybit inverse",exchange:KEY,scaled:true,fetch:||boxed(async {Ok(parse_inverse(fetch("inverse").await?,now_ms()))})},
  TableSource{name:"bybit spot",exchange:KEY,scaled:true,fetch:||boxed(async {Ok(parse_spot(fetch("spot").await?))})},
 ]
}

#[cfg(test)]
pub(crate) mod tests {
 use super::*;

 /// 2026-09-24：夹具里的季度合约都还没到期。
 const NOW:i64=1_790_200_000_000;

 // 2026-10-08 从 api.bybit.com 拉的真表里挑的行（字段裁到这里用得上的）。
 const SPOT_PAGE:&str=r#"{"retCode":0,"retMsg":"OK","result":{"category":"spot","list":[
  {"symbol":"BTCUSDT","status":"Trading","baseCoin":"BTC","quoteCoin":"USDT","priceFilter":{"tickSize":"0.1"}},
  {"symbol":"BTCUSDC","status":"Trading","baseCoin":"BTC","quoteCoin":"USDC","priceFilter":{"tickSize":"0.1"}},
  {"symbol":"PEPEUSDT","status":"Trading","baseCoin":"PEPE","quoteCoin":"USDT","priceFilter":{"tickSize":"0.000000001"}},
  {"symbol":"DOGEUSDT","status":"Trading","baseCoin":"DOGE","quoteCoin":"USDT","priceFilter":{"tickSize":"0.00001"}}
 ]},"retExtInfo":{},"time":1791460000000}"#;
 const LINEAR_PAGE:&str=r#"{"retCode":0,"retMsg":"OK","result":{"category":"linear","list":[
  {"symbol":"BTCUSDT","contractType":"LinearPerpetual","status":"Trading","baseCoin":"BTC","quoteCoin":"USDT","settleCoin":"USDT","deliveryTime":"0","priceFilter":{"tickSize":"0.10"}},
  {"symbol":"BTCPERP","contractType":"LinearPerpetual","status":"Trading","baseCoin":"BTC","quoteCoin":"USDC","settleCoin":"USDC","deliveryTime":"0","priceFilter":{"tickSize":"0.10"}},
  {"symbol":"1000PEPEUSDT","contractType":"LinearPerpetual","status":"Trading","baseCoin":"1000PEPE","quoteCoin":"USDT","settleCoin":"USDT","deliveryTime":"0","priceFilter":{"tickSize":"0.0000010"}},
  {"symbol":"BTCUSDT-09OCT26","contractType":"LinearFutures","status":"Trading","baseCoin":"BTC","quoteCoin":"USDT","settleCoin":"USDT","deliveryTime":"1791532800000","priceFilter":{"tickSize":"0.1"}},
  {"symbol":"BTCUSDT-27NOV26","contractType":"LinearFutures","status":"Trading","baseCoin":"BTC","quoteCoin":"USDT","settleCoin":"USDT","deliveryTime":"1795766400000","priceFilter":{"tickSize":"0.1"}},
  {"symbol":"BTCUSDT-25DEC26","contractType":"LinearFutures","status":"Trading","baseCoin":"BTC","quoteCoin":"USDT","settleCoin":"USDT","deliveryTime":"1798185600000","priceFilter":{"tickSize":"0.10"}},
  {"symbol":"BTCUSDT-26MAR27","contractType":"LinearFutures","status":"Trading","baseCoin":"BTC","quoteCoin":"USDT","settleCoin":"USDT","deliveryTime":"1806048000000","priceFilter":{"tickSize":"0.1"}},
  {"symbol":"BTCUSDT-25JUN27","contractType":"LinearFutures","status":"Trading","baseCoin":"BTC","quoteCoin":"USDT","settleCoin":"USDT","deliveryTime":"1813910400000","priceFilter":{"tickSize":"0.1"}},
  {"symbol":"DOGEUSDT","contractType":"LinearPerpetual","status":"Trading","baseCoin":"DOGE","quoteCoin":"USDT","settleCoin":"USDT","deliveryTime":"0","priceFilter":{"tickSize":"0.00001"}},
  {"symbol":"DOGEUSDT-09OCT26","contractType":"LinearFutures","status":"Trading","baseCoin":"DOGE","quoteCoin":"USDT","settleCoin":"USDT","deliveryTime":"1791532800000","priceFilter":{"tickSize":"0.00001"}},
  {"symbol":"NEWUSDT","contractType":"LinearPerpetual","status":"PreLaunch","baseCoin":"NEW","quoteCoin":"USDT","settleCoin":"USDT","deliveryTime":"0","priceFilter":{"tickSize":"0.0001"}}
 ],"nextPageCursor":""},"retExtInfo":{},"time":1791460000000}"#;
 const INVERSE_PAGE:&str=r#"{"retCode":0,"retMsg":"OK","result":{"category":"inverse","list":[
  {"symbol":"BTCUSD","contractType":"InversePerpetual","status":"Trading","baseCoin":"BTC","quoteCoin":"USD","settleCoin":"BTC","deliveryTime":"0","priceFilter":{"tickSize":"0.10"}},
  {"symbol":"BTCUSDZ26","contractType":"InverseFutures","status":"Trading","baseCoin":"BTC","quoteCoin":"USD","settleCoin":"BTC","deliveryTime":"1798185600000","priceFilter":{"tickSize":"0.50"}},
  {"symbol":"BTCUSDH27","contractType":"InverseFutures","status":"Trading","baseCoin":"BTC","quoteCoin":"USD","settleCoin":"BTC","deliveryTime":"1806048000000","priceFilter":{"tickSize":"0.50"}},
  {"symbol":"DOGEUSD","contractType":"InversePerpetual","status":"Trading","baseCoin":"DOGE","quoteCoin":"USD","settleCoin":"DOGE","deliveryTime":"0","priceFilter":{"tickSize":"0.00001"}}
 ],"nextPageCursor":"first%3D1%26last%3D26"},"retExtInfo":{},"time":1791460000000}"#;

 fn rows(page:&str)->Vec<Instrument> {parse_page(page.as_bytes()).unwrap().0}

 /// 三张表的夹具（顺序同 [`tables`]）。
 pub(crate) fn fixtures()->Vec<Table> {
  vec![parse_linear(rows(LINEAR_PAGE),NOW),parse_inverse(rows(INVERSE_PAGE),NOW),parse_spot(rows(SPOT_PAGE))]
 }

 fn names(table:&Table,base:&str)->Vec<String> {table.get(base).map(|rows|rows.iter().map(|v|v.instrument.clone()).collect()).unwrap_or_default()}

 #[test]
 fn only_the_two_quarterlies_and_usdt_rows_are_listed() {
  let [linear,inverse,spot]=<[Table;3]>::try_from(fixtures()).ok().unwrap();
  assert_eq!(names(&linear,"BTC"),["BTCUSDT","BTCUSDT-25DEC26","BTCUSDT-26MAR27"],"周 / 月合约、第三季、USDC 永续都不列");
  assert_eq!(names(&linear,"DOGE"),["DOGEUSDT"],"只有周合约的币没有交割");
  assert_eq!(names(&linear,"1000PEPE"),["1000PEPEUSDT"]);
  assert!(names(&linear,"NEW").is_empty(),"PreLaunch 不列");
  assert_eq!(names(&inverse,"BTC"),["BTCUSD","BTCUSDZ26","BTCUSDH27"]);
  assert_eq!(inverse["BTC"][1].margin,Some(Margin::Coin));
  assert_eq!(inverse["BTC"][1].notional,Notional::Inverse{contract_usd:1.0});
  assert_eq!(inverse["BTC"][1].tick,0.5);
  assert_eq!(linear["BTC"][1].margin,Some(Margin::Usdt));
  assert_eq!(names(&spot,"BTC"),["BTCUSDT"],"USDC 计价不列");
  assert_eq!(spot["PEPE"][0].tick,0.000000001);
 }

 /// 当季到期之后、表还没刷新之前：次季顶上来，第三季那张补进来当次季。
 #[test]
 fn after_the_quarter_expires_the_next_two_are_picked() {
  let after=1798185600000+1;
  let linear=parse_linear(rows(LINEAR_PAGE),after);
  assert_eq!(names(&linear,"BTC"),["BTCUSDT","BTCUSDT-26MAR27","BTCUSDT-25JUN27"]);
 }

 #[test]
 fn quarterly_is_the_last_friday_of_a_quarter_month() {
  for (at,yes) in [(1798185600000_i64,true),(1806048000000,true),(1813910400000,true),(1791532800000,false),(1795766400000,false),(1792137600000,false)] {
   assert_eq!(quarterly(at),yes,"{at}");
  }
 }

 #[test]
 fn pages_carry_the_cursor_and_errors_are_errors() {
  assert_eq!(parse_page(INVERSE_PAGE.as_bytes()).unwrap().1.as_deref(),Some("first%3D1%26last%3D26"));
  assert_eq!(parse_page(LINEAR_PAGE.as_bytes()).unwrap().1,None,"空游标就是最后一页");
  assert_eq!(parse_page(SPOT_PAGE.as_bytes()).unwrap().1,None,"现货不带游标");
  assert!(parse_page(br#"{"retCode":10006,"retMsg":"Too many visits!","result":{}}"#).is_err());
  assert!(parse_page(b"<html>blocked</html>").is_err());
  assert_eq!(cursor_component("first%3D1%26last%3D26"),"first%3D1%26last%3D26");
  assert_eq!(cursor_component("a=b&c"),"a%3Db%26c");
 }
}
