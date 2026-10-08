//! OKX 在主力订单流里的那一截：品种表（现货 / 永续 / 交割三张）。
//!
//! 取舍：只列 live 的；现货只列 `BASE-USDT`；永续列 `BASE-USDT-SWAP`（线性，面值 ctVal×ctMult 个币）
//! 与 `BASE-USD-SWAP`（反向，面值 ctVal×ctMult 美元）；交割只列 alias 为 quarter / next_quarter 的。
//! `-USD_UM-` 那种 USD 保证金线性合约、USDC 本位都不列。
use crate::venues::orderflow::{ExchangeKey,Margin,Notional,Product,Table,TableSource,Venue,boxed,get_bytes,index,number};
use serde::Deserialize;

pub const KEY:ExchangeKey=ExchangeKey("okx");
const SPOT:&str="https://www.okx.com/api/v5/public/instruments?instType=SPOT";
const SWAP:&str="https://www.okx.com/api/v5/public/instruments?instType=SWAP";
const FUTURES:&str="https://www.okx.com/api/v5/public/instruments?instType=FUTURES";

// ------------------------------------------------------------------ 品种表

#[derive(Deserialize)]
struct Reply {code:String,#[serde(default)] data:Vec<Instrument>}
#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
struct Instrument {
 inst_id:String,
 #[serde(default)] state:String,
 #[serde(default)] base_ccy:String,
 #[serde(default)] quote_ccy:String,
 #[serde(default)] uly:String,
 #[serde(default)] ct_type:String,
 #[serde(default)] ct_val:String,
 #[serde(default)] ct_mult:String,
 #[serde(default)] ct_val_ccy:String,
 #[serde(default)] settle_ccy:String,
 #[serde(default)] alias:String,
 #[serde(default)] exp_time:String,
 #[serde(default)] tick_sz:String,
}
impl Instrument {
 /// 一张合约的面值：ctVal × ctMult（ctMult 空着按 1）。
 fn face(&self)->Option<f64> {
  let mult=if self.ct_mult.trim().is_empty() {1.0} else {number(&self.ct_mult)?};
  number(&self.ct_val).map(|v|v*mult)
 }
 /// `BTC-USDT` → (`BTC`, `USDT`)。
 fn underlying(&self)->Option<(&str,&str)> {self.uly.split_once('-').filter(|(b,q)|!b.is_empty()&&!q.contains('-'))}
 /// 线性（U 本位）还是反向（币本位）：给出 (保证金口径, 面值)。其它组合（USDC、USD 保证金线性）不要。
 fn contract(&self)->Option<(Margin,Notional)> {
  let (base,quote)=self.underlying()?;
  let face=self.face()?;
  match (self.ct_type.as_str(),quote) {
   ("linear","USDT") if self.settle_ccy=="USDT"&&self.ct_val_ccy==base=>Some((Margin::Usdt,Notional::Linear{multiplier:face})),
   ("inverse","USD") if self.ct_val_ccy=="USD"=>Some((Margin::Coin,Notional::Inverse{contract_usd:face})),
   _=>None,
  }
 }
}

fn rows(body:&[u8])->anyhow::Result<Vec<Instrument>> {
 let reply:Reply=serde_json::from_slice(body)?;
 anyhow::ensure!(reply.code=="0","OKX answered code {}",reply.code);
 Ok(reply.data.into_iter().filter(|i|i.state=="live").collect())
}

/// OKX 现货：只要 `BASE-USDT`。
pub fn parse_spot(body:&[u8])->anyhow::Result<Table> {
 let rows=rows(body)?.into_iter().filter_map(|i| {
  if i.quote_ccy!="USDT"||i.inst_id!=format!("{}-USDT",i.base_ccy) {return None}
  let tick=number(&i.tick_sz)?;
  Some(Venue{exchange:KEY,product:Product::Spot,instrument:i.inst_id,margin:None,notional:Notional::Linear{multiplier:1.0},tick,expiry_ms:None,price_scale:None,listed_base:i.base_ccy})
 }).collect();
 Ok(index(rows))
}

/// OKX 永续：`BASE-USDT-SWAP`（线性，面值按币）与 `BASE-USD-SWAP`（反向，面值按美元）。
pub fn parse_swap(body:&[u8])->anyhow::Result<Table> {
 let rows=rows(body)?.into_iter().filter_map(|i| {
  if i.inst_id!=format!("{}-SWAP",i.uly) {return None}
  let (margin,notional)=i.contract()?;
  let tick=number(&i.tick_sz)?;
  let product=match margin {Margin::Usdt=>Product::UsdtPerp,Margin::Coin=>Product::CoinPerp};
  let base=i.underlying()?.0.to_owned();
  Some(Venue{exchange:KEY,product,instrument:i.inst_id,margin:None,notional,tick,expiry_ms:None,price_scale:None,listed_base:base})
 }).collect();
 Ok(index(rows))
}

/// OKX 交割：只要 alias 为 quarter / next_quarter 的 `BASE-USD-yymmdd`（与 `BASE-USDT-yymmdd`，如果有）。
pub fn parse_futures(body:&[u8])->anyhow::Result<Table> {
 let rows=rows(body)?.into_iter().filter_map(|i| {
  if !matches!(i.alias.as_str(),"quarter"|"next_quarter") {return None}
  let suffix=i.inst_id.strip_prefix(&i.uly)?.strip_prefix('-')?;
  if suffix.len()!=6||!suffix.bytes().all(|b|b.is_ascii_digit()) {return None}
  let (margin,notional)=i.contract()?;
  let tick=number(&i.tick_sz)?;
  let expiry=i.exp_time.trim().parse::<i64>().ok()?;
  let base=i.underlying()?.0.to_owned();
  Some(Venue{exchange:KEY,product:Product::Delivery,instrument:i.inst_id,margin:Some(margin),notional,tick,expiry_ms:Some(expiry),price_scale:None,listed_base:base})
 }).collect();
 Ok(index(rows))
}

pub fn tables()->Vec<TableSource> {
 vec![
  TableSource{name:"okx spot",exchange:KEY,scaled:false,fetch:||boxed(async {parse_spot(&get_bytes(SPOT).await?)})},
  TableSource{name:"okx swap",exchange:KEY,scaled:false,fetch:||boxed(async {parse_swap(&get_bytes(SWAP).await?)})},
  TableSource{name:"okx futures",exchange:KEY,scaled:false,fetch:||boxed(async {parse_futures(&get_bytes(FUTURES).await?)})},
 ]
}

#[cfg(test)]
pub(crate) mod tests {
 use super::*;

 const SPOT_FIX:&str=r#"{"code":"0","msg":"","data":[
  {"instId":"BTC-USDT","instType":"SPOT","state":"live","baseCcy":"BTC","quoteCcy":"USDT","tickSz":"0.1","ctVal":"","ctType":"","uly":"","alias":""},
  {"instId":"BTC-USDC","instType":"SPOT","state":"live","baseCcy":"BTC","quoteCcy":"USDC","tickSz":"0.1"},
  {"instId":"DOGE-USDT","instType":"SPOT","state":"live","baseCcy":"DOGE","quoteCcy":"USDT","tickSz":"0.00001"},
  {"instId":"OLD-USDT","instType":"SPOT","state":"suspend","baseCcy":"OLD","quoteCcy":"USDT","tickSz":"0.001"}
 ]}"#;
 const SWAP_FIX:&str=r#"{"code":"0","msg":"","data":[
  {"instId":"BTC-USD-SWAP","instType":"SWAP","state":"live","ctType":"inverse","ctVal":"100","ctMult":"1","ctValCcy":"USD","settleCcy":"BTC","uly":"BTC-USD","instFamily":"BTC-USD","tickSz":"0.1","alias":"","expTime":""},
  {"instId":"BTC-USDT-SWAP","instType":"SWAP","state":"live","ctType":"linear","ctVal":"0.01","ctMult":"1","ctValCcy":"BTC","settleCcy":"USDT","uly":"BTC-USDT","instFamily":"BTC-USDT","tickSz":"0.1"},
  {"instId":"BTC-USDC-SWAP","instType":"SWAP","state":"live","ctType":"linear","ctVal":"0.0001","ctMult":"1","ctValCcy":"BTC","settleCcy":"USDC","uly":"BTC-USDC","tickSz":"0.1"},
  {"instId":"DOGE-USDT-SWAP","instType":"SWAP","state":"live","ctType":"linear","ctVal":"1000","ctMult":"1","ctValCcy":"DOGE","settleCcy":"USDT","uly":"DOGE-USDT","tickSz":"0.00001"},
  {"instId":"DOGE-USD-SWAP","instType":"SWAP","state":"live","ctType":"inverse","ctVal":"10","ctMult":"1","ctValCcy":"USD","settleCcy":"DOGE","uly":"DOGE-USD","tickSz":"0.00001"}
 ]}"#;
 const FUTURES_FIX:&str=r#"{"code":"0","msg":"","data":[
  {"instId":"BTC-USD-260925","instType":"FUTURES","state":"live","alias":"this_month","ctType":"inverse","ctVal":"100","ctMult":"1","ctValCcy":"USD","settleCcy":"BTC","uly":"BTC-USD","expTime":"1790323200000","tickSz":"0.1"},
  {"instId":"BTC-USD-261225","instType":"FUTURES","state":"live","alias":"quarter","ctType":"inverse","ctVal":"100","ctMult":"1","ctValCcy":"USD","settleCcy":"BTC","uly":"BTC-USD","expTime":"1798185600000","tickSz":"0.1"},
  {"instId":"BTC-USD-270326","instType":"FUTURES","state":"live","alias":"next_quarter","ctType":"inverse","ctVal":"100","ctMult":"1","ctValCcy":"USD","settleCcy":"BTC","uly":"BTC-USD","expTime":"1806048000000","tickSz":"0.1"},
  {"instId":"BTC-USD-270625","instType":"FUTURES","state":"live","alias":"third_quarter","ctType":"inverse","ctVal":"100","ctMult":"1","ctValCcy":"USD","settleCcy":"BTC","uly":"BTC-USD","expTime":"1813910400000","tickSz":"0.1"},
  {"instId":"BTC-USD_UM-261225","instType":"FUTURES","state":"live","alias":"quarter","ctType":"linear","ctVal":"0.01","ctMult":"1","ctValCcy":"BTC","settleCcy":"USD","uly":"BTC-USD","expTime":"1798185600000","tickSz":"0.1"},
  {"instId":"ETH-USDT-261225","instType":"FUTURES","state":"live","alias":"quarter","ctType":"linear","ctVal":"0.1","ctMult":"1","ctValCcy":"ETH","settleCcy":"USDT","uly":"ETH-USDT","expTime":"1798185600000","tickSz":"0.01"}
 ]}"#;

 /// 三张表的夹具（顺序同 [`tables`]）。
 pub(crate) fn fixtures()->Vec<Table> {
  vec![parse_spot(SPOT_FIX.as_bytes()).unwrap(),parse_swap(SWAP_FIX.as_bytes()).unwrap(),parse_futures(FUTURES_FIX.as_bytes()).unwrap()]
 }

 fn names(table:&Table,base:&str)->Vec<String> {table.get(base).map(|rows|rows.iter().map(|v|v.instrument.clone()).collect()).unwrap_or_default()}

 #[test]
 fn what_is_left_out() {
  let [spot,swap,futures]=<[Table;3]>::try_from(fixtures()).ok().unwrap();
  assert_eq!(names(&spot,"BTC"),["BTC-USDT"],"USDC 计价不列");
  assert!(names(&spot,"OLD").is_empty(),"suspend 不列");
  assert_eq!(names(&swap,"BTC"),["BTC-USDT-SWAP","BTC-USD-SWAP"],"USDC 本位不列");
  assert_eq!(swap["DOGE"][0].notional,Notional::Linear{multiplier:1000.0});
  assert_eq!(names(&futures,"BTC"),["BTC-USD-261225","BTC-USD-270326"],"本月、第三季、USD_UM 都不列");
  let eth=&futures["ETH"][0];
  assert_eq!((eth.instrument.as_str(),eth.margin,eth.notional),("ETH-USDT-261225",Some(Margin::Usdt),Notional::Linear{multiplier:0.1}));
 }

 #[test]
 fn broken_upstream_bodies_are_errors_not_empty_tables() {
  assert!(parse_spot(br#"{"code":"50011","msg":"Too Many Requests","data":[]}"#).is_err());
  assert!(parse_swap(b"<html></html>").is_err());
 }
}
