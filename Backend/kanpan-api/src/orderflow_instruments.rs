//! 主力订单流的品种表：`GET /v1/market/orderflow/instruments?base=BTC`。
//!
//! 手机打开一只币（按 base 资产，例如 BTC），主力订单流要把这只币在币安 / OKX / Coinbase
//! 的现货、U 本位永续、币本位永续、交割（当季 + 次季）每一本簿都订上。每一家各有自己的
//! 合约表、自己的面值口径（线性按币、反向按美元一张），手机不该自己去拉七张全表——有的
//! 它在国内根本连不上（OKX），有的一张就好几 MB（币安现货）。所以由这里汇总：
//!
//! * 后台每 10 分钟把七张全表各拉一次（币安 U 本位 / 币本位 / 现货、OKX 现货 / 永续 / 交割、
//!   Coinbase 现货），只留下这个功能要用的几列，按 base 建索引。拉失败的那一张 30 秒后再试，
//!   手上那份旧的照常用；从来没拉成功过的那一家这一次就不出现（其他照给，接口仍 200）。
//! * 请求只查内存，不出站。进程起来后第一个请求会等第一轮拉完（最多 `FIRST_WAIT`），
//!   之后再也不等。
//! * 币安 U 本位那张表和 `market_meta` / `sector_history` 共用进程里那一份
//!   （`market_meta::exchange_info`），不多拉一次。
//!
//! 返回的每一项（字段名是和客户端的约定，改名就是改协议）：
//! * `exchange`：`binance` / `okx` / `coinbase`；
//! * `product`：`spot` / `usdtPerp` / `coinPerp` / `delivery`；
//! * `instrument`：这家交易所自己的代号，原样拿去订流、取快照；
//! * `margin`：只有交割有，`usdt`（U 本位交割）或 `coin`（币本位交割）；
//! * `notional`：一个数量单位值多少——
//!   `{"kind":"linear","multiplier":m}`：名义美元 = 价格 × 数量 × m（m 是一个数量单位是多少个币：
//!   币安与 Coinbase 为 1，OKX 永续 / 交割为 ctVal×ctMult）；
//!   `{"kind":"inverse","contractUsd":c}`：名义美元 = 张数 × c（币安币本位的 contractSize，
//!   OKX `-USD-SWAP` / `-USD-` 交割的 ctVal×ctMult）；
//! * `tick`：最小价格变动，按这家自己的报价；
//! * `expiryMs`：只有交割有，交割时间（毫秒）；
//! * `priceScale`：只在不等于 1 时出现。币安把 PEPE、SHIB 这类单价极小的币挂成
//!   `1000PEPEUSDT`：价格和数量都是按「1000 个币」报的。这时 `priceScale=1000`，
//!   换成每个币的价格 = 价格 ÷ priceScale；名义美元仍按上面 linear 的算法用原始价格算
//!   （multiplier 仍是 1）。只有币安会这样挂（`1000` / `1000000` / `1M` 三种前缀）。
//!
//! 取舍（和用户约定的口径）：只列在交易的（币安 TRADING、OKX live、Coinbase online 且没停交易）；
//! 交割只列当季与次季（币安 contractType CURRENT_QUARTER / NEXT_QUARTER，OKX alias quarter /
//! next_quarter）；现货只列 USDT 计价（币安、OKX）与 USD 计价（Coinbase）。OKX 的
//! `-USD_UM-` 那种 USD 保证金线性合约、USDC 本位都不列。已过交割时间的合约在答复时剔掉，
//! 哪怕表还没刷新。
use crate::{AppState,binance_gate,error::{ApiError,Params},market_meta};
use axum::{Json,Router,http::{HeaderValue,header},response::{IntoResponse,Response},routing::get};
use serde::{Deserialize,Serialize};
use std::collections::HashMap;
use std::future::Future;
use std::pin::Pin;
use std::sync::{Arc,OnceLock};
use std::time::Duration;
use tokio::sync::watch;

const PATH:&str="/v1/market/orderflow/instruments";
const BINANCE_SPOT:&str="https://data-api.binance.vision/api/v3/exchangeInfo?symbolStatus=TRADING&showPermissionSets=false";
const BINANCE_CM:&str="https://www.binance.com/dapi/v1/exchangeInfo";
const OKX_SPOT:&str="https://www.okx.com/api/v5/public/instruments?instType=SPOT";
const OKX_SWAP:&str="https://www.okx.com/api/v5/public/instruments?instType=SWAP";
const OKX_FUTURES:&str="https://www.okx.com/api/v5/public/instruments?instType=FUTURES";
const COINBASE:&str="https://api.exchange.coinbase.com/products";

/// 一张表拉成功之后多久再拉。合约上下架一天几次，交割换季一个季度一次。
const FRESH:Duration=Duration::from_secs(10*60);
/// 一张表拉失败之后多久再试。手上的旧表照常用，所以不必急。
const RETRY:Duration=Duration::from_secs(30);
/// 拉一张表最多等多久。币安现货那张约 2.5 MB，美国 VPS 上 1–3 秒。
const FETCH_TIMEOUT:Duration=Duration::from_secs(20);
/// 进程起来后的第一个请求最多等第一轮拉多久。比路由上那层 30 秒超时短得多。
const FIRST_WAIT:Duration=Duration::from_secs(8);
/// 答复可以被中间层缓存多久。
const CACHE_CONTROL:&str="max-age=60";

// ------------------------------------------------------------------ 输出形状

#[derive(Clone,Copy,Debug,PartialEq,Eq,Serialize)]
#[serde(rename_all="lowercase")]
pub enum Exchange {Binance,Okx,Coinbase}

#[derive(Clone,Copy,Debug,PartialEq,Eq,Serialize)]
#[serde(rename_all="camelCase")]
pub enum Product {Spot,UsdtPerp,CoinPerp,Delivery}

#[derive(Clone,Copy,Debug,PartialEq,Eq,Serialize)]
#[serde(rename_all="lowercase")]
pub enum Margin {Usdt,Coin}

#[derive(Clone,Copy,Debug,PartialEq,Serialize)]
#[serde(tag="kind",rename_all="lowercase")]
pub enum Notional {
 Linear {multiplier:f64},
 Inverse {#[serde(rename="contractUsd")] contract_usd:f64},
}

#[derive(Clone,Debug,PartialEq,Serialize)]
#[serde(rename_all="camelCase")]
pub struct Venue {
 pub exchange:Exchange,
 pub product:Product,
 pub instrument:String,
 #[serde(skip_serializing_if="Option::is_none")]
 pub margin:Option<Margin>,
 pub notional:Notional,
 pub tick:f64,
 #[serde(skip_serializing_if="Option::is_none")]
 pub expiry_ms:Option<i64>,
 #[serde(skip_serializing_if="Option::is_none")]
 pub price_scale:Option<u64>,
 /// 这一行在交易所表里挂的 base（币安可能带 `1000` 前缀）。只用来建索引，不发出去。
 #[serde(skip)]
 pub listed_base:String,
}

impl Venue {
 /// 同一张表里的先后：永续在交割前，U 本位在币本位前，交割按到期先后。
 fn rank(&self)->(u8,i64) {
  let product=match (self.product,self.margin) {
   (Product::UsdtPerp,_)=>0,
   (Product::Delivery,Some(Margin::Usdt))=>1,
   (Product::CoinPerp,_)=>2,
   (Product::Delivery,_)=>3,
   (Product::Spot,_)=>4,
  };
  (product,self.expiry_ms.unwrap_or(0))
 }
}

/// 一张表：按交易所挂的 base 建的索引。
pub type Table=HashMap<String,Vec<Venue>>;

fn index(rows:Vec<Venue>)->Table {
 let mut table:Table=HashMap::new();
 for row in rows {table.entry(row.listed_base.clone()).or_default().push(row);}
 for rows in table.values_mut() {rows.sort_by_key(Venue::rank);}
 table
}

fn number(text:&str)->Option<f64> {text.trim().parse::<f64>().ok().filter(|v|v.is_finite()&&*v>0.0)}

// ------------------------------------------------------------------ 币安

#[derive(Deserialize)]
struct BinanceInfo {symbols:Vec<BinanceSymbol>}
#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
struct BinanceSymbol {
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
 #[serde(default)] filters:Vec<BinanceFilter>,
}
fn yes()->bool {true}
#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
struct BinanceFilter {filter_type:String,#[serde(default)] tick_size:Option<String>}
impl BinanceSymbol {
 fn tick(&self)->Option<f64> {
  self.filters.iter().find(|f|f.filter_type=="PRICE_FILTER").and_then(|f|f.tick_size.as_deref()).and_then(number)
 }
 fn quarter(&self)->bool {matches!(self.contract_type.as_str(),"CURRENT_QUARTER"|"NEXT_QUARTER")}
}

/// 币安 U 本位（fapi exchangeInfo）：USDT 永续（含 TRADIFI_PERPETUAL）与 USDT 交割的当季 / 次季。
pub fn parse_binance_um(info:&serde_json::Value)->anyhow::Result<Table> {
 let info=BinanceInfo::deserialize(info)?;
 let rows=info.symbols.into_iter().filter_map(|s| {
  if s.status!="TRADING"||s.quote_asset!="USDT"||s.margin_asset!="USDT" {return None}
  let tick=s.tick()?;
  let (product,margin,expiry)=match s.contract_type.as_str() {
   "PERPETUAL"|"TRADIFI_PERPETUAL"=>(Product::UsdtPerp,None,None),
   _ if s.quarter()=>(Product::Delivery,Some(Margin::Usdt),Some(s.delivery_date?)),
   _=>return None,
  };
  Some(Venue{exchange:Exchange::Binance,product,instrument:s.symbol,margin,notional:Notional::Linear{multiplier:1.0},tick,expiry_ms:expiry,price_scale:None,listed_base:s.base_asset})
 }).collect();
 Ok(index(rows))
}

/// 币安币本位（dapi exchangeInfo）：币本位永续与币本位交割的当季 / 次季，一张合约 contractSize 美元。
pub fn parse_binance_cm(body:&[u8])->anyhow::Result<Table> {
 let info:BinanceInfo=serde_json::from_slice(body)?;
 let rows=info.symbols.into_iter().filter_map(|s| {
  if s.contract_status!="TRADING"||s.quote_asset!="USD" {return None}
  let tick=s.tick()?;
  let contract_usd=s.contract_size.filter(|v|v.is_finite()&&*v>0.0)?;
  let (product,margin,expiry)=match s.contract_type.as_str() {
   "PERPETUAL"=>(Product::CoinPerp,None,None),
   _ if s.quarter()=>(Product::Delivery,Some(Margin::Coin),Some(s.delivery_date?)),
   _=>return None,
  };
  Some(Venue{exchange:Exchange::Binance,product,instrument:s.symbol,margin,notional:Notional::Inverse{contract_usd},tick,expiry_ms:expiry,price_scale:None,listed_base:s.base_asset})
 }).collect();
 Ok(index(rows))
}

/// 币安现货（data-api.binance.vision exchangeInfo）：只要 USDT 计价、在交易的。
pub fn parse_binance_spot(body:&[u8])->anyhow::Result<Table> {
 let info:BinanceInfo=serde_json::from_slice(body)?;
 let rows=info.symbols.into_iter().filter_map(|s| {
  if s.status!="TRADING"||s.quote_asset!="USDT"||!s.is_spot_trading_allowed {return None}
  let tick=s.tick()?;
  Some(Venue{exchange:Exchange::Binance,product:Product::Spot,instrument:s.symbol,margin:None,notional:Notional::Linear{multiplier:1.0},tick,expiry_ms:None,price_scale:None,listed_base:s.base_asset})
 }).collect();
 Ok(index(rows))
}

/// 币安把单价极小的币挂成「N 个币」一个单位：`1000PEPE`、`1000000MOG`、`1MBABYDOGE`。
const BINANCE_SCALED:[(&str,u64);3]=[("1000000",1_000_000),("1000",1000),("1M",1_000_000)];

// ------------------------------------------------------------------ OKX

#[derive(Deserialize)]
struct OkxReply {code:String,#[serde(default)] data:Vec<OkxInstrument>}
#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
struct OkxInstrument {
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
impl OkxInstrument {
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

fn okx_rows(body:&[u8])->anyhow::Result<Vec<OkxInstrument>> {
 let reply:OkxReply=serde_json::from_slice(body)?;
 anyhow::ensure!(reply.code=="0","OKX answered code {}",reply.code);
 Ok(reply.data.into_iter().filter(|i|i.state=="live").collect())
}

/// OKX 现货：只要 `BASE-USDT`。
pub fn parse_okx_spot(body:&[u8])->anyhow::Result<Table> {
 let rows=okx_rows(body)?.into_iter().filter_map(|i| {
  if i.quote_ccy!="USDT"||i.inst_id!=format!("{}-USDT",i.base_ccy) {return None}
  let tick=number(&i.tick_sz)?;
  Some(Venue{exchange:Exchange::Okx,product:Product::Spot,instrument:i.inst_id,margin:None,notional:Notional::Linear{multiplier:1.0},tick,expiry_ms:None,price_scale:None,listed_base:i.base_ccy})
 }).collect();
 Ok(index(rows))
}

/// OKX 永续：`BASE-USDT-SWAP`（线性，面值按币）与 `BASE-USD-SWAP`（反向，面值按美元）。
pub fn parse_okx_swap(body:&[u8])->anyhow::Result<Table> {
 let rows=okx_rows(body)?.into_iter().filter_map(|i| {
  if i.inst_id!=format!("{}-SWAP",i.uly) {return None}
  let (margin,notional)=i.contract()?;
  let tick=number(&i.tick_sz)?;
  let product=match margin {Margin::Usdt=>Product::UsdtPerp,Margin::Coin=>Product::CoinPerp};
  let base=i.underlying()?.0.to_owned();
  Some(Venue{exchange:Exchange::Okx,product,instrument:i.inst_id,margin:None,notional,tick,expiry_ms:None,price_scale:None,listed_base:base})
 }).collect();
 Ok(index(rows))
}

/// OKX 交割：只要 alias 为 quarter / next_quarter 的 `BASE-USD-yymmdd`（与 `BASE-USDT-yymmdd`，如果有）。
pub fn parse_okx_futures(body:&[u8])->anyhow::Result<Table> {
 let rows=okx_rows(body)?.into_iter().filter_map(|i| {
  if !matches!(i.alias.as_str(),"quarter"|"next_quarter") {return None}
  let suffix=i.inst_id.strip_prefix(&i.uly)?.strip_prefix('-')?;
  if suffix.len()!=6||!suffix.bytes().all(|b|b.is_ascii_digit()) {return None}
  let (margin,notional)=i.contract()?;
  let tick=number(&i.tick_sz)?;
  let expiry=i.exp_time.trim().parse::<i64>().ok()?;
  let base=i.underlying()?.0.to_owned();
  Some(Venue{exchange:Exchange::Okx,product:Product::Delivery,instrument:i.inst_id,margin:Some(margin),notional,tick,expiry_ms:Some(expiry),price_scale:None,listed_base:base})
 }).collect();
 Ok(index(rows))
}

// ------------------------------------------------------------------ Coinbase

#[derive(Deserialize)]
struct CoinbaseProduct {
 id:String,
 base_currency:String,
 quote_currency:String,
 #[serde(default)] quote_increment:String,
 #[serde(default)] status:String,
 #[serde(default)] trading_disabled:bool,
}

/// Coinbase 现货：只要 USD 计价、online 且没停交易的。
pub fn parse_coinbase(body:&[u8])->anyhow::Result<Table> {
 let products:Vec<CoinbaseProduct>=serde_json::from_slice(body)?;
 let rows=products.into_iter().filter_map(|p| {
  if p.status!="online"||p.trading_disabled||p.quote_currency!="USD" {return None}
  let tick=number(&p.quote_increment)?;
  Some(Venue{exchange:Exchange::Coinbase,product:Product::Spot,instrument:p.id,margin:None,notional:Notional::Linear{multiplier:1.0},tick,expiry_ms:None,price_scale:None,listed_base:p.base_currency})
 }).collect();
 Ok(index(rows))
}

// ------------------------------------------------------------------ 按 base 取

/// 从一张表里取这只币的那几行。币安的表还要看带前缀的那种（`1000PEPE` 之于 `PEPE`）。
fn rows_for(table:&Table,exchange_scales:bool,base:&str)->Vec<Venue> {
 let mut out:Vec<Venue>=table.get(base).cloned().unwrap_or_default();
 if exchange_scales {
  for (prefix,scale) in BINANCE_SCALED {
   if let Some(rows)=table.get(&format!("{prefix}{base}")) {
    out.extend(rows.iter().cloned().map(|mut v|{v.price_scale=Some(scale);v}));
   }
  }
 }
 out
}

/// 按表的先后把这只币的各家各产品排成一张清单，剔掉已经过了交割时间的。
pub fn pick(tables:&[(Exchange,Option<Arc<Table>>)],base:&str,now_ms:i64)->Vec<Venue> {
 let mut out=Vec::new();
 for (exchange,table) in tables {
  let Some(table)=table else {continue};
  let mut rows=rows_for(table,*exchange==Exchange::Binance,base);
  rows.retain(|v|v.expiry_ms.is_none_or(|at|at>now_ms));
  rows.sort_by_key(Venue::rank);
  out.extend(rows);
 }
 out
}

fn valid_base(base:&str)->bool {(1..=20).contains(&base.len())&&base.bytes().all(|b|b.is_ascii_uppercase()||b.is_ascii_digit())}

// ------------------------------------------------------------------ 后台拉表

type Fetched=Pin<Box<dyn Future<Output=anyhow::Result<Table>>+Send>>;

/// 一张表的来源。
struct Source {
 name:&'static str,
 exchange:Exchange,
 fetch:fn()->Fetched,
}

#[derive(Clone,Default)]
struct Held {table:Option<Arc<Table>>,tried:bool}

struct Book {sources:Vec<(Exchange,watch::Receiver<Held>)>}

async fn get_bytes(url:&str)->anyhow::Result<axum::body::Bytes> {
 let gated=binance_gate::covers(url);
 if gated&&binance_gate::blocked() {anyhow::bail!("binance egress is on hold")}
 let response=market_meta::http().get(url).timeout(FETCH_TIMEOUT).send().await?;
 if gated&&binance_gate::note_reply(&response) {anyhow::bail!("binance rate limit")}
 let response=response.error_for_status()?;
 Ok(response.bytes().await?)
}

fn sources()->Vec<Source> {
 fn boxed<F:Future<Output=anyhow::Result<Table>>+Send+'static>(f:F)->Fetched {Box::pin(f)}
 vec![
  Source{name:"binance usdt-m",exchange:Exchange::Binance,fetch:||boxed(async {let info=market_meta::exchange_info().await.map_err(|e|anyhow::anyhow!("{}",e.1))?;parse_binance_um(&info)})},
  Source{name:"binance coin-m",exchange:Exchange::Binance,fetch:||boxed(async {parse_binance_cm(&get_bytes(BINANCE_CM).await?)})},
  Source{name:"binance spot",exchange:Exchange::Binance,fetch:||boxed(async {parse_binance_spot(&get_bytes(BINANCE_SPOT).await?)})},
  Source{name:"okx spot",exchange:Exchange::Okx,fetch:||boxed(async {parse_okx_spot(&get_bytes(OKX_SPOT).await?)})},
  Source{name:"okx swap",exchange:Exchange::Okx,fetch:||boxed(async {parse_okx_swap(&get_bytes(OKX_SWAP).await?)})},
  Source{name:"okx futures",exchange:Exchange::Okx,fetch:||boxed(async {parse_okx_futures(&get_bytes(OKX_FUTURES).await?)})},
  Source{name:"coinbase spot",exchange:Exchange::Coinbase,fetch:||boxed(async {parse_coinbase(&get_bytes(COINBASE).await?)})},
 ]
}

/// 每张表一个后台循环：成功隔 10 分钟再拉，失败隔 30 秒再试，旧表一直留着用。
fn start()->Book {
 let sources=sources().into_iter().map(|source| {
  let (tx,rx)=watch::channel(Held::default());
  tokio::spawn(async move {
   loop {
    let wait=match tokio::time::timeout(FETCH_TIMEOUT+Duration::from_secs(5),(source.fetch)()).await {
     Ok(Ok(table))=>{
      let table=Arc::new(table);
      tx.send_modify(|held|{held.table=Some(table);held.tried=true;});
      FRESH
     },
     Ok(Err(e))=>{tracing::warn!("Orderflow instruments: {} table failed: {e}",source.name);tx.send_modify(|held|held.tried=true);RETRY},
     Err(_)=>{tracing::warn!("Orderflow instruments: {} table timed out",source.name);tx.send_modify(|held|held.tried=true);RETRY},
    };
    tokio::time::sleep(wait).await;
   }
  });
  (source.exchange,rx)
 }).collect();
 Book{sources}
}

/// 那一份后台表。第一次有人问时才开始拉（测试和不用这个功能的进程不出站）。
fn book()->&'static Book {
 static B:OnceLock<Book>=OnceLock::new();
 B.get_or_init(start)
}

async fn snapshot(book:&Book)->Vec<(Exchange,Option<Arc<Table>>)> {
 let waits=book.sources.iter().map(|(exchange,rx)| {
  let mut rx=rx.clone();
  async move {
   if !rx.borrow().tried {let _=tokio::time::timeout(FIRST_WAIT,rx.wait_for(|held|held.tried)).await;}
   let table=rx.borrow().table.clone();
   (*exchange,table)
  }
 });
 futures_util::future::join_all(waits).await
}

// ------------------------------------------------------------------ 路由

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct InstrumentsQuery {base:String}

fn reply(base:&str,venues:Vec<Venue>,now_ms:i64)->Response {
 let mut response=Json(serde_json::json!({"base":base,"asOfMs":now_ms,"venues":venues})).into_response();
 response.headers_mut().insert(header::CACHE_CONTROL,HeaderValue::from_static(CACHE_CONTROL));
 response
}

async fn instruments(Params(query):Params<InstrumentsQuery>)->Response {
 if !valid_base(&query.base) {return ApiError::bad("invalid_base").into_response()}
 let tables=snapshot(book()).await;
 let now=chrono::Utc::now().timestamp_millis();
 let venues=pick(&tables,&query.base,now);
 reply(&query.base,venues,now)
}

pub fn routes()->Router<AppState> {Router::new().route(PATH,get(instruments))}

#[cfg(test)]
mod tests {
 use super::*;
 use serde_json::{Value,json};

 const NOW:i64=1_790_200_000_000; // 2026-09-24，BTCUSDT_260925 还没到期

 fn fapi()->Value {json!({"symbols":[
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
 const OKX_SPOT_FIX:&str=r#"{"code":"0","msg":"","data":[
  {"instId":"BTC-USDT","instType":"SPOT","state":"live","baseCcy":"BTC","quoteCcy":"USDT","tickSz":"0.1","ctVal":"","ctType":"","uly":"","alias":""},
  {"instId":"BTC-USDC","instType":"SPOT","state":"live","baseCcy":"BTC","quoteCcy":"USDC","tickSz":"0.1"},
  {"instId":"DOGE-USDT","instType":"SPOT","state":"live","baseCcy":"DOGE","quoteCcy":"USDT","tickSz":"0.00001"},
  {"instId":"OLD-USDT","instType":"SPOT","state":"suspend","baseCcy":"OLD","quoteCcy":"USDT","tickSz":"0.001"}
 ]}"#;
 const OKX_SWAP_FIX:&str=r#"{"code":"0","msg":"","data":[
  {"instId":"BTC-USD-SWAP","instType":"SWAP","state":"live","ctType":"inverse","ctVal":"100","ctMult":"1","ctValCcy":"USD","settleCcy":"BTC","uly":"BTC-USD","instFamily":"BTC-USD","tickSz":"0.1","alias":"","expTime":""},
  {"instId":"BTC-USDT-SWAP","instType":"SWAP","state":"live","ctType":"linear","ctVal":"0.01","ctMult":"1","ctValCcy":"BTC","settleCcy":"USDT","uly":"BTC-USDT","instFamily":"BTC-USDT","tickSz":"0.1"},
  {"instId":"BTC-USDC-SWAP","instType":"SWAP","state":"live","ctType":"linear","ctVal":"0.0001","ctMult":"1","ctValCcy":"BTC","settleCcy":"USDC","uly":"BTC-USDC","tickSz":"0.1"},
  {"instId":"DOGE-USDT-SWAP","instType":"SWAP","state":"live","ctType":"linear","ctVal":"1000","ctMult":"1","ctValCcy":"DOGE","settleCcy":"USDT","uly":"DOGE-USDT","tickSz":"0.00001"},
  {"instId":"DOGE-USD-SWAP","instType":"SWAP","state":"live","ctType":"inverse","ctVal":"10","ctMult":"1","ctValCcy":"USD","settleCcy":"DOGE","uly":"DOGE-USD","tickSz":"0.00001"}
 ]}"#;
 const OKX_FUTURES_FIX:&str=r#"{"code":"0","msg":"","data":[
  {"instId":"BTC-USD-260925","instType":"FUTURES","state":"live","alias":"this_month","ctType":"inverse","ctVal":"100","ctMult":"1","ctValCcy":"USD","settleCcy":"BTC","uly":"BTC-USD","expTime":"1790323200000","tickSz":"0.1"},
  {"instId":"BTC-USD-261225","instType":"FUTURES","state":"live","alias":"quarter","ctType":"inverse","ctVal":"100","ctMult":"1","ctValCcy":"USD","settleCcy":"BTC","uly":"BTC-USD","expTime":"1798185600000","tickSz":"0.1"},
  {"instId":"BTC-USD-270326","instType":"FUTURES","state":"live","alias":"next_quarter","ctType":"inverse","ctVal":"100","ctMult":"1","ctValCcy":"USD","settleCcy":"BTC","uly":"BTC-USD","expTime":"1806048000000","tickSz":"0.1"},
  {"instId":"BTC-USD-270625","instType":"FUTURES","state":"live","alias":"third_quarter","ctType":"inverse","ctVal":"100","ctMult":"1","ctValCcy":"USD","settleCcy":"BTC","uly":"BTC-USD","expTime":"1813910400000","tickSz":"0.1"},
  {"instId":"BTC-USD_UM-261225","instType":"FUTURES","state":"live","alias":"quarter","ctType":"linear","ctVal":"0.01","ctMult":"1","ctValCcy":"BTC","settleCcy":"USD","uly":"BTC-USD","expTime":"1798185600000","tickSz":"0.1"},
  {"instId":"ETH-USDT-261225","instType":"FUTURES","state":"live","alias":"quarter","ctType":"linear","ctVal":"0.1","ctMult":"1","ctValCcy":"ETH","settleCcy":"USDT","uly":"ETH-USDT","expTime":"1798185600000","tickSz":"0.01"}
 ]}"#;
 const COINBASE_FIX:&str=r#"[
  {"id":"BTC-USD","base_currency":"BTC","quote_currency":"USD","quote_increment":"0.01","base_increment":"0.00000001","status":"online","trading_disabled":false},
  {"id":"BTC-EUR","base_currency":"BTC","quote_currency":"EUR","quote_increment":"0.01","status":"online","trading_disabled":false},
  {"id":"BTC-USDT","base_currency":"BTC","quote_currency":"USDT","quote_increment":"0.01","status":"online","trading_disabled":false},
  {"id":"DOGE-USD","base_currency":"DOGE","quote_currency":"USD","quote_increment":"0.00001","status":"online","trading_disabled":false},
  {"id":"OLD-USD","base_currency":"OLD","quote_currency":"USD","quote_increment":"0.01","status":"delisted","trading_disabled":true},
  {"id":"HALT-USD","base_currency":"HALT","quote_currency":"USD","quote_increment":"0.01","status":"online","trading_disabled":true}
 ]"#;

 fn all()->Vec<(Exchange,Option<Arc<Table>>)> {
  vec![
   (Exchange::Binance,Some(Arc::new(parse_binance_um(&fapi()).unwrap()))),
   (Exchange::Binance,Some(Arc::new(parse_binance_cm(DAPI.as_bytes()).unwrap()))),
   (Exchange::Binance,Some(Arc::new(parse_binance_spot(SPOT.as_bytes()).unwrap()))),
   (Exchange::Okx,Some(Arc::new(parse_okx_spot(OKX_SPOT_FIX.as_bytes()).unwrap()))),
   (Exchange::Okx,Some(Arc::new(parse_okx_swap(OKX_SWAP_FIX.as_bytes()).unwrap()))),
   (Exchange::Okx,Some(Arc::new(parse_okx_futures(OKX_FUTURES_FIX.as_bytes()).unwrap()))),
   (Exchange::Coinbase,Some(Arc::new(parse_coinbase(COINBASE_FIX.as_bytes()).unwrap()))),
  ]
 }

 #[test]
 fn btc_lists_every_venue_and_product_in_order_with_the_agreed_field_names() {
  let venues=pick(&all(),"BTC",NOW);
  let got=serde_json::to_value(&venues).unwrap();
  assert_eq!(got,json!([
   {"exchange":"binance","product":"usdtPerp","instrument":"BTCUSDT","notional":{"kind":"linear","multiplier":1.0},"tick":0.1},
   {"exchange":"binance","product":"delivery","instrument":"BTCUSDT_260925","margin":"usdt","notional":{"kind":"linear","multiplier":1.0},"tick":0.1,"expiryMs":1790323200000_i64},
   {"exchange":"binance","product":"delivery","instrument":"BTCUSDT_261225","margin":"usdt","notional":{"kind":"linear","multiplier":1.0},"tick":0.1,"expiryMs":1798185600000_i64},
   {"exchange":"binance","product":"coinPerp","instrument":"BTCUSD_PERP","notional":{"kind":"inverse","contractUsd":100.0},"tick":0.1},
   {"exchange":"binance","product":"delivery","instrument":"BTCUSD_260925","margin":"coin","notional":{"kind":"inverse","contractUsd":100.0},"tick":0.1,"expiryMs":1790323200000_i64},
   {"exchange":"binance","product":"delivery","instrument":"BTCUSD_261225","margin":"coin","notional":{"kind":"inverse","contractUsd":100.0},"tick":0.1,"expiryMs":1798185600000_i64},
   {"exchange":"binance","product":"spot","instrument":"BTCUSDT","notional":{"kind":"linear","multiplier":1.0},"tick":0.01},
   {"exchange":"okx","product":"spot","instrument":"BTC-USDT","notional":{"kind":"linear","multiplier":1.0},"tick":0.1},
   {"exchange":"okx","product":"usdtPerp","instrument":"BTC-USDT-SWAP","notional":{"kind":"linear","multiplier":0.01},"tick":0.1},
   {"exchange":"okx","product":"coinPerp","instrument":"BTC-USD-SWAP","notional":{"kind":"inverse","contractUsd":100.0},"tick":0.1},
   {"exchange":"okx","product":"delivery","instrument":"BTC-USD-261225","margin":"coin","notional":{"kind":"inverse","contractUsd":100.0},"tick":0.1,"expiryMs":1798185600000_i64},
   {"exchange":"okx","product":"delivery","instrument":"BTC-USD-270326","margin":"coin","notional":{"kind":"inverse","contractUsd":100.0},"tick":0.1,"expiryMs":1806048000000_i64},
   {"exchange":"coinbase","product":"spot","instrument":"BTC-USD","notional":{"kind":"linear","multiplier":1.0},"tick":0.01},
  ]));
 }

 #[test]
 fn what_is_left_out() {
  let venues=pick(&all(),"BTC",NOW);
  let names:Vec<&str>=venues.iter().map(|v|v.instrument.as_str()).collect();
  for absent in ["BTCUSDC","BTCFDUSD","BTC-USDC","BTC-USDC-SWAP","BTC-USD-260925","BTC-USD-270625","BTC-USD_UM-261225","BTC-EUR","BTC-USDT"] {
   // BTC-USDT 只能作为 OKX 现货出现一次，不能作为 Coinbase 的 USDT 计价出现。
   if absent=="BTC-USDT" {assert_eq!(names.iter().filter(|n|**n=="BTC-USDT").count(),1);continue}
   assert!(!names.contains(&absent),"{absent} 不该出现");
  }
  // 暂停交易的、下架的、停交易的都不在表里。
  let tables=all();
  assert!(pick(&tables,"ETH",NOW).iter().all(|v|v.instrument!="ETHUSDT"&&v.instrument!="ETHUSD_260626"));
  assert!(pick(&tables,"LUNA",NOW).is_empty());
  assert!(pick(&tables,"OLD",NOW).is_empty());
  assert!(pick(&tables,"HALT",NOW).is_empty());
  // OKX 的 USDT 交割按同样的规则收（线性，面值按币）。
  let eth=pick(&tables,"ETH",NOW);
  assert_eq!(serde_json::to_value(&eth).unwrap(),json!([{"exchange":"okx","product":"delivery","instrument":"ETH-USDT-261225","margin":"usdt","notional":{"kind":"linear","multiplier":0.1},"tick":0.01,"expiryMs":1798185600000_i64}]));
 }

 #[test]
 fn expired_deliveries_drop_out_even_before_the_table_refreshes() {
  let after=1790323200000+1;
  let names:Vec<String>=pick(&all(),"BTC",after).into_iter().map(|v|v.instrument).collect();
  assert!(!names.contains(&"BTCUSDT_260925".to_owned()));
  assert!(!names.contains(&"BTCUSD_260925".to_owned()));
  assert!(names.contains(&"BTCUSDT_261225".to_owned()));
 }

 #[test]
 fn doge_and_the_thousand_prefix() {
  let tables=all();
  assert_eq!(serde_json::to_value(pick(&tables,"DOGE",NOW)).unwrap(),json!([
   {"exchange":"binance","product":"coinPerp","instrument":"DOGEUSD_PERP","notional":{"kind":"inverse","contractUsd":10.0},"tick":0.00001},
   {"exchange":"binance","product":"spot","instrument":"DOGEUSDT","notional":{"kind":"linear","multiplier":1.0},"tick":0.00001},
   {"exchange":"okx","product":"spot","instrument":"DOGE-USDT","notional":{"kind":"linear","multiplier":1.0},"tick":0.00001},
   {"exchange":"okx","product":"usdtPerp","instrument":"DOGE-USDT-SWAP","notional":{"kind":"linear","multiplier":1000.0},"tick":0.00001},
   {"exchange":"okx","product":"coinPerp","instrument":"DOGE-USD-SWAP","notional":{"kind":"inverse","contractUsd":10.0},"tick":0.00001},
   {"exchange":"coinbase","product":"spot","instrument":"DOGE-USD","notional":{"kind":"linear","multiplier":1.0},"tick":0.00001},
  ]));
  // PEPE：币安合约挂成 1000PEPEUSDT，带 priceScale；现货是 PEPEUSDT，不带。
  assert_eq!(serde_json::to_value(pick(&tables,"PEPE",NOW)).unwrap(),json!([
   {"exchange":"binance","product":"usdtPerp","instrument":"1000PEPEUSDT","notional":{"kind":"linear","multiplier":1.0},"tick":0.0000001,"priceScale":1000},
   {"exchange":"binance","product":"spot","instrument":"PEPEUSDT","notional":{"kind":"linear","multiplier":1.0},"tick":0.00000001},
  ]));
  // 股票永续也是 U 本位永续。
  assert_eq!(pick(&tables,"TSLA",NOW)[0].instrument,"TSLAUSDT");
 }

 #[test]
 fn a_missing_venue_is_just_left_out() {
  let mut tables=all();
  tables[3].1=None; tables[4].1=None; tables[5].1=None; // OKX 三张都没拉到
  let venues=pick(&tables,"BTC",NOW);
  assert!(venues.iter().all(|v|v.exchange!=Exchange::Okx));
  assert_eq!(venues.len(),8);
 }

 #[test]
 fn broken_upstream_bodies_are_errors_not_empty_tables() {
  assert!(parse_okx_spot(br#"{"code":"50011","msg":"Too Many Requests","data":[]}"#).is_err());
  assert!(parse_binance_cm(b"<html>challenge</html>").is_err());
  assert!(parse_coinbase(br#"{"message":"rate limited"}"#).is_err());
  assert!(parse_binance_um(&json!({"code":-1003})).is_err());
 }

 #[test]
 fn base_is_checked() {
  for good in ["BTC","1000PEPE","A","DOGE","ABCDEFGHIJKLMNOPQRST"] {assert!(valid_base(good),"{good}");}
  for bad in ["","btc","BTC-USD","BTC_USD","ABCDEFGHIJKLMNOPQRSTU","中文","BTC USD"] {assert!(!valid_base(bad),"{bad}");}
 }

 #[tokio::test]
 async fn bad_base_is_400_and_the_reply_carries_cache_control() {
  use axum::{body::Body,http::{Request,StatusCode}};
  use http_body_util::BodyExt;
  use tower::ServiceExt;
  let app=||Router::<()>::new().route(PATH,get(instruments));
  for (query,code) in [("","invalid_query"),("base=btc","invalid_base"),("base=BTC-USDT","invalid_base"),("base=BTC&x=1","invalid_query")] {
   let reply=app().oneshot(Request::builder().uri(format!("{PATH}?{query}")).body(Body::empty()).unwrap()).await.unwrap();
   assert_eq!(reply.status(),StatusCode::BAD_REQUEST,"{query}");
   let body:Value=serde_json::from_slice(&reply.into_body().collect().await.unwrap().to_bytes()).unwrap();
   assert_eq!(body["error"]["code"],code,"{query}");
  }
  // 答复的形状（不经网络：直接拿夹具拼）。
  let response=reply("BTC",pick(&all(),"BTC",NOW),NOW);
  assert_eq!(response.headers()[header::CACHE_CONTROL],"max-age=60");
  let body:Value=serde_json::from_slice(&response.into_body().collect().await.unwrap().to_bytes()).unwrap();
  assert_eq!(body["base"],"BTC");
  assert_eq!(body["asOfMs"],NOW);
  assert_eq!(body["venues"].as_array().unwrap().len(),13);
 }
}
