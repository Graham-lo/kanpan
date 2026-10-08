//! 主力订单流和各家交易所之间的那一层：通用的描述，加上把各家登记到一起的那张表。
//!
//! 订单流（`orderflow_history` 与 `orderflow_instruments`）只认这里的类型，不认识任何一家：
//! 一家交易所在订单流里是什么样，全由它自己的 `venues/<ex>/orderflow.rs` 填这里的描述——
//!
//! * 品种表（本文件的上半）：从哪儿拉、怎么解析成 [`Venue`] 的行、要不要按「N 个币」前缀找；
//! * 连接种类、快照通道、爆仓源与参考盘（见下半）。
//!
//! 接一家新交易所：新建 `venues/<ex>/orderflow.rs`，在下面几个登记函数里各加一行（见
//! `docs/多交易所-接入指南.md`）。
use serde::Serialize;
use std::collections::HashMap;
use std::future::Future;
use std::pin::Pin;
use std::time::Duration;

use super::{binance,bybit,coinbase,hyperliquid,okx};

// ------------------------------------------------------------------ 品种表的形状

/// 交易所代号（`binance` / `okx` / `coinbase` / `bybit` / `hyperliquid`）。和客户端约定的
/// `exchange` 字段就是它，也是簿 id `{exchange}:{product}:{instrument}` 的第一段。
#[derive(Clone,Copy,Debug,PartialEq,Eq,Hash,Serialize)]
#[serde(transparent)]
pub struct ExchangeKey(pub &'static str);

#[derive(Clone,Copy,Debug,PartialEq,Eq,Hash,Serialize)]
#[serde(rename_all="camelCase")]
pub enum Product {Spot,UsdtPerp,CoinPerp,Delivery}

impl Product {
 /// 簿 id 与历史里用的那个名字（和序列化出来的一样）。
 pub fn wire(self)->&'static str {
  match self {Product::Spot=>"spot",Product::UsdtPerp=>"usdtPerp",Product::CoinPerp=>"coinPerp",Product::Delivery=>"delivery"}
 }
}

#[derive(Clone,Copy,Debug,PartialEq,Eq,Hash,Serialize)]
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
 pub exchange:ExchangeKey,
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
 /// 这一行在交易所表里挂的 base（可能带 `1000` 前缀）。只用来建索引，不发出去。
 #[serde(skip)]
 pub listed_base:String,
}

impl Venue {
 /// 同一张表里的先后：永续在交割前，U 本位在币本位前，交割按到期先后。
 pub fn rank(&self)->(u8,i64) {
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

/// 把解析出来的行按挂的 base 建索引，每个 base 里按 [`Venue::rank`] 排好。
pub fn index(rows:Vec<Venue>)->Table {
 let mut table:Table=HashMap::new();
 for row in rows {table.entry(row.listed_base.clone()).or_default().push(row);}
 for rows in table.values_mut() {rows.sort_by_key(Venue::rank);}
 table
}

/// 表里的数字字段（字符串）：有限的正数才算。
pub fn number(text:&str)->Option<f64> {text.trim().parse::<f64>().ok().filter(|v|v.is_finite()&&*v>0.0)}

/// 单价极小的币挂成「N 个币」一个单位：`1000PEPE`、`1000000MOG`、`1MBABYDOGE`。
/// 客户端 `OrderFlowBase.scaledPrefixes` 有同一张（它要从图上那只 `1000PEPEUSDT` 反推 base），
/// 两边经 `contract/settings-fields.json` 的 `orderFlow.binanceScaledPrefixes` 对账（键名是历史留下的）。
/// 哪几张表按它找由各表的 [`TableSource::scaled`] 定。
pub const SCALED_PREFIXES:[(&str,u64);3]=[("1000000",1_000_000),("1000",1000),("1M",1_000_000)];

/// 表里的 base → 手机与这里用的 base：去掉「N 个币」前缀（`1000PEPE` → `PEPE`）。
pub fn unscaled(base:&str)->&str {
 for (prefix,_) in SCALED_PREFIXES {
  if let Some(rest)=base.strip_prefix(prefix) && !rest.is_empty() && rest.bytes().next().is_some_and(|b|b.is_ascii_uppercase()) {return rest}
 }
 base
}

/// 挂的 base 带的是哪个前缀：`(1000, "PEPE")`；不带就是 `(1, base)`。
pub fn scale_of(listed:&str)->(u64,&str) {
 let base=unscaled(listed);
 if base.len()==listed.len() {return (1,listed)}
 SCALED_PREFIXES.iter().find(|(prefix,_)|listed.len()==prefix.len()+base.len()&&listed.starts_with(prefix)).map_or((1,listed),|(_,s)|(*s,base))
}

// ------------------------------------------------------------------ 品种表从哪儿来

pub type Fetched=Pin<Box<dyn Future<Output=anyhow::Result<Table>>+Send>>;

/// 把一个 future 装成 [`Fetched`]。
pub fn boxed<F:Future<Output=anyhow::Result<Table>>+Send+'static>(f:F)->Fetched {Box::pin(f)}

/// 一张品种表的来源。
pub struct TableSource {
 /// 日志里的名字（`bybit linear`）。
 pub name:&'static str,
 pub exchange:ExchangeKey,
 /// 这张表里同一只币可能挂成「N 个币」（`1000PEPE`）：按 base 找时连带前缀的一起找。
 pub scaled:bool,
 pub fetch:fn()->Fetched,
}

/// 全部品种表，按答复里的先后：币安、OKX、Coinbase、Bybit、Hyperliquid。
pub fn tables()->Vec<TableSource> {
 [binance::orderflow::tables(),okx::orderflow::tables(),coinbase::orderflow::tables(),bybit::orderflow::tables(),hyperliquid::orderflow::tables()].into_iter().flatten().collect()
}

/// 拉一张表最多等多久。币安现货那张约 2.5 MB，美国 VPS 上 1–3 秒。
pub const FETCH_TIMEOUT:Duration=Duration::from_secs(20);

/// GET 一个地址拿回原文。落在币安出站闸门里的地址先看闸门（被罚着就不出站），答复记进闸门。
pub async fn get_bytes(url:&str)->anyhow::Result<axum::body::Bytes> {
 let gated=crate::binance_gate::covers(url);
 if gated&&crate::binance_gate::blocked() {anyhow::bail!("egress on hold")}
 let response=crate::market_meta::http().get(url).timeout(FETCH_TIMEOUT).send().await?;
 if gated&&crate::binance_gate::note_reply(&response) {anyhow::bail!("rate limited")}
 let response=response.error_for_status()?;
 Ok(response.bytes().await?)
}

/// 同一份东西有几个主机：按先后试，第一个答成的为准；都不成给最后那个错。
pub async fn get_bytes_any(urls:&[String])->anyhow::Result<axum::body::Bytes> {
 let mut last=anyhow::anyhow!("no host");
 for url in urls {
  match get_bytes(url).await {Ok(body)=>return Ok(body),Err(e)=>last=e}
 }
 Err(last)
}

/// POST 一段 JSON 拿回原文（Hyperliquid 的 `info`）。
pub async fn post_json(url:&str,body:&serde_json::Value)->anyhow::Result<axum::body::Bytes> {
 let response=crate::market_meta::http().post(url).json(body).timeout(FETCH_TIMEOUT).send().await?;
 let response=response.error_for_status()?;
 Ok(response.bytes().await?)
}

#[cfg(test)]
mod tests {
 //! 五家的表合在一起按 base 取：各家的夹具在各家的 `orderflow.rs` 里，这里只看合起来的先后与口径。
 use super::*;
 use serde_json::{Value,json};
 use std::sync::Arc;

 const NOW:i64=1_790_200_000_000; // 2026-09-24，BTCUSDT_260925 还没到期

 /// 前缀表和客户端那张逐项相同、顺序也相同（长的在前，`1000000` 要先于 `1000` 试）。
 #[test] fn scaled_prefixes_are_the_contract_ones() {
  let contract:Value=serde_json::from_str(include_str!("../../contract/settings-fields.json")).expect("contract JSON");
  let rows=contract["orderFlow"]["binanceScaledPrefixes"].as_array()
   .expect("contract has no orderFlow.binanceScaledPrefixes; run `make sync-contract` from the repo root");
  let theirs:Vec<(String,u64)>=rows.iter().map(|r|(r["prefix"].as_str().unwrap().to_string(),r["scale"].as_u64().unwrap())).collect();
  let ours:Vec<(String,u64)>=SCALED_PREFIXES.iter().map(|(p,s)|(p.to_string(),*s)).collect();
  assert_eq!(theirs,ours);
 }

 #[test] fn scale_of_reads_the_prefix() {
  assert_eq!(scale_of("1000PEPE"),(1000,"PEPE"));
  assert_eq!(scale_of("1000000MOG"),(1_000_000,"MOG"));
  assert_eq!(scale_of("1MBABYDOGE"),(1_000_000,"BABYDOGE"));
  assert_eq!(scale_of("BTC"),(1,"BTC"));
  assert_eq!(scale_of("1INCH"),(1,"1INCH"));
 }

 /// 登记的顺序就是答复的顺序；代号与 `scaled` 各家各自定。
 #[test] fn the_registry_lists_every_table_in_order() {
  let got:Vec<(&str,&str,bool)>=tables().iter().map(|t|(t.name,t.exchange.0,t.scaled)).collect();
  assert_eq!(got,vec![
   ("binance usdt-m","binance",true),("binance coin-m","binance",true),("binance spot","binance",true),
   ("okx spot","okx",false),("okx swap","okx",false),("okx futures","okx",false),
   ("coinbase spot","coinbase",false),
   ("bybit linear","bybit",true),("bybit inverse","bybit",true),("bybit spot","bybit",true),
   ("hyperliquid perps","hyperliquid",false),
  ]);
 }

 /// 五家的夹具表（顺序同 [`tables`]）。
 pub(crate) fn all()->Vec<(bool,Option<Arc<Table>>)> {
  let mut out:Vec<(bool,Option<Arc<Table>>)>=Vec::new();
  for t in binance::orderflow::tests::fixtures() {out.push((true,Some(Arc::new(t))));}
  for t in okx::orderflow::tests::fixtures() {out.push((false,Some(Arc::new(t))));}
  for t in coinbase::orderflow::tests::fixtures() {out.push((false,Some(Arc::new(t))));}
  for t in bybit::orderflow::tests::fixtures() {out.push((true,Some(Arc::new(t))));}
  for t in hyperliquid::orderflow::tests::fixtures() {out.push((false,Some(Arc::new(t))));}
  out
 }

 use crate::orderflow_instruments::{listed_in,pick};

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
   {"exchange":"bybit","product":"usdtPerp","instrument":"BTCUSDT","notional":{"kind":"linear","multiplier":1.0},"tick":0.1},
   {"exchange":"bybit","product":"delivery","instrument":"BTCUSDT-25DEC26","margin":"usdt","notional":{"kind":"linear","multiplier":1.0},"tick":0.1,"expiryMs":1798185600000_i64},
   {"exchange":"bybit","product":"delivery","instrument":"BTCUSDT-26MAR27","margin":"usdt","notional":{"kind":"linear","multiplier":1.0},"tick":0.1,"expiryMs":1806048000000_i64},
   {"exchange":"bybit","product":"coinPerp","instrument":"BTCUSD","notional":{"kind":"inverse","contractUsd":1.0},"tick":0.1},
   {"exchange":"bybit","product":"delivery","instrument":"BTCUSDZ26","margin":"coin","notional":{"kind":"inverse","contractUsd":1.0},"tick":0.5,"expiryMs":1798185600000_i64},
   {"exchange":"bybit","product":"delivery","instrument":"BTCUSDH27","margin":"coin","notional":{"kind":"inverse","contractUsd":1.0},"tick":0.5,"expiryMs":1806048000000_i64},
   {"exchange":"bybit","product":"spot","instrument":"BTCUSDT","notional":{"kind":"linear","multiplier":1.0},"tick":0.1},
   {"exchange":"hyperliquid","product":"usdtPerp","instrument":"BTC","notional":{"kind":"linear","multiplier":1.0},"tick":0.1},
  ]));
 }

 /// PEPE：币安、Bybit 合约挂成 1000PEPEUSDT，Hyperliquid 挂成 kPEPE，三家都带 priceScale 1000；
 /// 现货是 PEPEUSDT，不带。
 #[test]
 fn every_thousand_pepe_carries_the_same_scale() {
  let pepe=serde_json::to_value(pick(&all(),"PEPE",NOW)).unwrap();
  assert_eq!(pepe,json!([
   {"exchange":"binance","product":"usdtPerp","instrument":"1000PEPEUSDT","notional":{"kind":"linear","multiplier":1.0},"tick":0.0000001,"priceScale":1000},
   {"exchange":"binance","product":"spot","instrument":"PEPEUSDT","notional":{"kind":"linear","multiplier":1.0},"tick":0.00000001},
   {"exchange":"bybit","product":"usdtPerp","instrument":"1000PEPEUSDT","notional":{"kind":"linear","multiplier":1.0},"tick":0.000001,"priceScale":1000},
   {"exchange":"bybit","product":"spot","instrument":"PEPEUSDT","notional":{"kind":"linear","multiplier":1.0},"tick":0.000000001},
   {"exchange":"hyperliquid","product":"usdtPerp","instrument":"kPEPE","notional":{"kind":"linear","multiplier":1.0},"tick":0.000001,"priceScale":1000},
  ]));
 }

 #[test]
 fn a_missing_exchange_is_just_left_out_and_listed_waits_for_every_table() {
  let tables=all();
  assert_eq!(listed_in(&tables,"BTC",NOW),Some(true));
  assert_eq!(listed_in(&tables,"NOSUCHCOIN",NOW),Some(false));
  let mut partial=all();
  let last=partial.len()-1;
  partial[last].1=None;
  assert_eq!(listed_in(&partial,"BTC",NOW),Some(true),"别家有就够了");
  assert_eq!(listed_in(&partial,"NOSUCHCOIN",NOW),None,"最后那张还没拉到：判不了");
  let venues=pick(&partial,"BTC",NOW);
  assert!(venues.iter().all(|v|v.exchange.0!="hyperliquid"));
  assert_eq!(venues.len(),20);
 }

 #[test]
 fn expired_deliveries_drop_out_even_before_the_table_refreshes() {
  let after=1798185600000+1;
  let names:Vec<String>=pick(&all(),"BTC",after).into_iter().map(|v|v.instrument).collect();
  for gone in ["BTCUSDT_261225","BTCUSD_261225","BTCUSDT-25DEC26","BTCUSDZ26"] {assert!(!names.contains(&gone.to_owned()),"{gone}");}
  for kept in ["BTCUSDT-26MAR27","BTCUSDH27","BTC-USD-270326"] {assert!(names.contains(&kept.to_owned()),"{kept}");}
 }
}
