//! 常驻跟踪分几层（2026-09-25）：主币、固定美股 / 大宗 / 指数、山寨、热点、按需。
//!
//! | 层 | 谁 | 多久算一次 | 上限 | 掉榜之后 |
//! | --- | --- | --- | --- | --- |
//! | 主币 | BTC ETH SOL | — | 3 | 一直跟 |
//! | 固定 | 下面 [`FIXED`] 那张表里币安真有的（U 本位 + OKX 有的永续） | 启动时与每 10 分钟对一次合约表 | 表长 | 一直跟 |
//! | 山寨 | 币安 U 本位 COIN 永续按 24h 成交额前 40（去掉主币、固定、稳定币） | UTC 0 点（与启动时） | 40 | 再跟 24 小时 |
//! | 热点 | 四路信号去重并集（见 [`pick_hot`]） | 每小时 | 30 | 再跟 24 小时 |
//! | 按需 | 手机打开的 | 有人要时 | 20 | 24 小时没人要就停 |
//!
//! 总数最多 220 只；满了只从按需与热点里踢最久没人要的，主币与固定永远不踢。
//! `KANPAN_ORDERFLOW_LAYERS` 选开哪几层（`fixed` / `fixed,alts,hot` / `all` / `none`），缺省全开；
//! 主币与按需两层一直开（它们是改版之前就有的行为）。
//!
//! 热点只用币安文档里有的公开接口：`/fapi/v1/ticker/24hr` 不带 symbol（权重 40，一小时一次，
//! 与山寨共用这一份，5 分钟内复用）、`/futures/data/openInterestHist`（只取成交额前 150、间隔 300 毫秒）。
//! 网页版那个 `bapi/composite/v1/public/marketing/symbol/list` 的标签只能拿来分板块，不当热点榜用，这里不接。
use crate::market_meta::{self,Shared};
use crate::orderflow_instruments::unscaled;
use serde_json::Value;
use std::collections::{HashMap,HashSet};
use std::sync::{Arc,OnceLock};
use std::time::Duration;

/// 主币。
pub const MAJORS:[&str;3]=["BTC","ETH","SOL"];

/// 固定层：美股、大宗、指数。改名单只改这张表；币安没有的合约跳过并在日志里点名一次。
/// AI 产业链一个不删（2026-09-25 用户明说：存储四个代号 SNDK / MU / SKHYNIX / SKHY、INTC、ARM、NVDA 都要在）。
pub const FIXED:[(&str,&[&str]);4]=[
 ("AI 产业链",&[
  "NVDA","AMD","AVGO","TSM","INTC","ARM","MU","SNDK","SKHYNIX","SKHY","SAMSUNG","DRAM","CXMT","MRVL","AAOI","CRDO","COHR","ALAB",
  "SMCI","DELL","AMAT","LRCX","KLAC","ASML","GLW","CIEN","LITE","WDC","STXX","TER","SOXL","SOXS","SMH","SPCX","VRT","ANET","GEV",
  "VST","BE","CRWV","NBIS","IREN","APLD","IONQ","OPENAI","ANTHROPIC","ZHIPU","MINIMAX","UNITREE","GIGADEV","META","GOOGL","MSFT",
  "AMZN","AAPL","TSLA","ORCL","PLTR","NOW","SNOW","DDOG","NET","CRWD","PANW","RDDT","TEM","AXTI",
 ]),
 ("加密股",&["MSTR","COIN","HOOD","CRCL","BMNR"]),
 ("指数 ETF",&["QQQ","SPY","TQQQ","SQQQ","IWM"]),
 ("大宗",&["XAU","XAG","XPT","XPD","CL","BZ","NATGAS","COPPER"]),
];

pub const MAX_ALTS:usize=40;
pub const MAX_HOT:usize=30;
/// 热点四路各取几只。
const HOT_MOVERS:usize=8;
const HOT_OI:usize=8;
const HOT_TURNOVER:usize=8;
const HOT_EQUITY:usize=6;
/// 涨跌幅那一路只看 24h 成交额 ≥ 5000 万的。
const HOT_MOVER_MIN_TURNOVER:f64=50_000_000.0;
/// 持仓变化那一路只对成交额前 150 取。
const OI_CANDIDATES:usize=150;
const OI_GAP:Duration=Duration::from_millis(300);
const OI_HIST:&str="https://www.binance.com/futures/data/openInterestHist";
const TICKERS:&str="https://www.binance.com/fapi/v1/ticker/24hr";
const TICKERS_TTL:Duration=Duration::from_secs(5*60);
const STABLES:[&str;8]=["USDC","FDUSD","TUSD","USDP","DAI","USDE","BUSD","USD1"];

/// `KANPAN_ORDERFLOW_LAYERS` 开了哪几层。
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub struct Enabled {pub fixed:bool,pub alts:bool,pub hot:bool}

impl Enabled {
 pub const ALL:Enabled=Enabled{fixed:true,alts:true,hot:true};
 pub fn parse(text:Option<&str>)->Enabled {
  let Some(text)=text.map(str::trim).filter(|t|!t.is_empty()) else {return Enabled::ALL};
  let mut e=Enabled{fixed:false,alts:false,hot:false};
  for word in text.split([',',' ']).map(|w|w.trim().to_ascii_lowercase()).filter(|w|!w.is_empty()) {
   match word.as_str() {
    "all"=>e=Enabled::ALL,
    "none"=>{},
    "fixed"=>e.fixed=true,
    "alts"|"alt"=>e.alts=true,
    "hot"=>e.hot=true,
    other=>tracing::warn!("Orderflow history: unknown layer {other:?} in KANPAN_ORDERFLOW_LAYERS (fixed, alts, hot, all, none)"),
   }
  }
  e
 }
 pub fn from_env()->Enabled {Enabled::parse(std::env::var("KANPAN_ORDERFLOW_LAYERS").ok().as_deref())}
 pub fn describe(&self)->String {
  let names:Vec<&str>=[(self.fixed,"fixed"),(self.alts,"alts"),(self.hot,"hot")].into_iter().filter(|(on,_)|*on).map(|(_,n)|n).collect();
  if names.is_empty() {"majors + on-demand only".into()} else {format!("majors + on-demand + {}",names.join(","))}
 }
}

fn number(v:&Value)->Option<f64> {
 let x=match v {Value::String(s)=>s.parse().ok()?,Value::Number(n)=>n.as_f64()?,_=>return None};
 f64::is_finite(x).then_some(x)
}

/// 合约表里一只 USDT 本位、正在交易的永续（含 TRADIFI_PERPETUAL）。
struct Perp<'a> {symbol:&'a str,base:&'a str,underlying:&'a str}

fn perps(info:&Value)->Vec<Perp<'_>> {
 info["symbols"].as_array().map(Vec::as_slice).unwrap_or_default().iter().filter_map(|s| {
  if s["status"].as_str()!=Some("TRADING")||s["quoteAsset"].as_str()!=Some("USDT") {return None}
  if !matches!(s["contractType"].as_str(),Some("PERPETUAL"|"TRADIFI_PERPETUAL")) {return None}
  Some(Perp{symbol:s["symbol"].as_str()?,base:unscaled(s["baseAsset"].as_str()?),underlying:s["underlyingType"].as_str().unwrap_or("COIN")})
 }).collect()
}

/// 固定层里币安此刻真有的，和没有的（按表的顺序）。
pub fn fixed_bases(info:&Value)->(Vec<String>,Vec<String>) {
 let listed:HashSet<&str>=perps(info).into_iter().filter(|p|p.underlying!="COIN").map(|p|p.base).collect();
 let mut found=Vec::new();let mut missing=Vec::new();
 let mut seen=HashSet::new();
 for (_,names) in FIXED {
  for name in names {
   if !seen.insert(*name) {continue}
   if listed.contains(name) {found.push(name.to_string())} else {missing.push(name.to_string())}
  }
 }
 (found,missing)
}

/// 币安 U 本位全表 24h 行情，5 分钟内复用一份（山寨、热点、默认门槛的成交额分档都用它）。
pub async fn tickers()->crate::error::Result<Arc<Value>> {
 static SHARED:OnceLock<Shared>=OnceLock::new();
 SHARED.get_or_init(Shared::default).get(TICKERS_TTL,||market_meta::get_json(TICKERS)).await
}

/// 一行 24h 行情。
#[derive(Clone,Copy,Debug,Default)]
pub struct Ticker {pub turnover:f64,pub change_pct:f64}

pub fn ticker_map(body:&Value)->HashMap<String,Ticker> {
 body.as_array().map(Vec::as_slice).unwrap_or_default().iter().filter_map(|row| {
  let symbol=row["symbol"].as_str()?.to_string();
  Some((symbol,Ticker{turnover:number(&row["quoteVolume"]).unwrap_or(0.0),change_pct:number(&row["priceChangePercent"]).unwrap_or(0.0)}))
 }).collect()
}

/// 一只 U 本位永续的 24h 成交额（门槛分档用）。
pub async fn turnover(symbol:&str)->Option<f64> {
 let body=tickers().await.ok()?;
 body.as_array()?.iter().find(|r|r["symbol"].as_str()==Some(symbol)).and_then(|r|number(&r["quoteVolume"])).filter(|t|*t>=0.0)
}

/// 候选：COIN 永续，去掉稳定币与 `exclude`，同一 base 只留成交额大的那只。按成交额降序。
fn coins<'a>(info:&'a Value,tickers:&HashMap<String,Ticker>,exclude:&HashSet<String>)->Vec<(&'a str,&'a str,Ticker)> {
 let mut best:HashMap<&str,(&str,Ticker)>=HashMap::new();
 for p in perps(info).into_iter().filter(|p|p.underlying=="COIN") {
  if exclude.contains(p.base)||STABLES.contains(&p.base)||MAJORS.contains(&p.base) {continue}
  let t=tickers.get(p.symbol).copied().unwrap_or_default();
  let slot=best.entry(p.base).or_insert((p.symbol,t));
  if t.turnover>slot.1.turnover {*slot=(p.symbol,t)}
 }
 let mut out:Vec<(&str,&str,Ticker)>=best.into_iter().map(|(base,(symbol,t))|(base,symbol,t)).collect();
 out.sort_by(|a,b|b.2.turnover.total_cmp(&a.2.turnover).then(a.0.cmp(b.0)));
 out
}

/// 山寨层：COIN 永续按 24h 成交额前 40，去掉主币、固定层与稳定币。
pub fn pick_alts(info:&Value,tickers:&HashMap<String,Ticker>,fixed:&HashSet<String>)->Vec<String> {
 coins(info,tickers,fixed).into_iter().filter(|c|c.2.turnover>0.0).take(MAX_ALTS).map(|c|c.0.to_string()).collect()
}

/// 持仓变化那一路要取哪些合约：候选按成交额前 150。
pub fn oi_candidates(info:&Value,tickers:&HashMap<String,Ticker>,exclude:&HashSet<String>)->Vec<(String,String)> {
 coins(info,tickers,exclude).into_iter().filter(|c|c.2.turnover>0.0).take(OI_CANDIDATES).map(|c|(c.0.to_string(),c.1.to_string())).collect()
}

/// `openInterestHist period=1h limit=5` 的五行 → 4 小时持仓变化的绝对百分比。
pub fn oi_change(rows:&Value)->Option<f64> {
 let rows=rows.as_array()?;
 let first=number(&rows.first()?["sumOpenInterest"])?;
 let last=number(&rows.last()?["sumOpenInterest"])?;
 (rows.len()>=2&&first>0.0).then(||((last-first)/first*100.0).abs())
}

/// 逐只取 4 小时持仓变化，间隔 300 毫秒（150 只约 45 秒、权重 150 左右，远在 2400/分之内）。
/// 币安出口被封着就停下，拿到多少用多少。
pub async fn oi_changes(candidates:&[(String,String)])->HashMap<String,f64> {
 let mut out=HashMap::new();
 for (base,symbol) in candidates {
  if crate::binance_gate::blocked() {break}
  if let Ok(rows)=market_meta::get_json(&format!("{OI_HIST}?symbol={symbol}&period=1h&limit=5")).await
   && let Some(change)=oi_change(&rows) {out.insert(base.clone(),change);}
  tokio::time::sleep(OI_GAP).await;
 }
 out
}

/// 热点层：四路去重并集，按 ①②③④ 的顺序，最多 30 只。
/// ① 24h 涨跌幅绝对值前 8（成交额 < 5000 万的不看）；② 4 小时持仓变化前 8；③ 24h 成交额前 8；
/// ④ 美股单独一组，涨跌幅绝对值前 6。①②③ 只看 COIN 永续，④ 只看 EQUITY；`exclude` 是已经在别的层里跟着的。
pub fn pick_hot(info:&Value,tickers:&HashMap<String,Ticker>,oi:&HashMap<String,f64>,exclude:&HashSet<String>)->Vec<String> {
 let pool=coins(info,tickers,exclude);
 let mut out:Vec<String>=Vec::new();
 let push=|names:Vec<&str>,take:usize,out:&mut Vec<String>| {
  for n in names.into_iter().take(take) {if !out.iter().any(|o|o==n) {out.push(n.to_string())}}
 };
 let mut movers:Vec<&(&str,&str,Ticker)>=pool.iter().filter(|c|c.2.turnover>=HOT_MOVER_MIN_TURNOVER).collect();
 movers.sort_by(|a,b|b.2.change_pct.abs().total_cmp(&a.2.change_pct.abs()).then(a.0.cmp(b.0)));
 push(movers.iter().map(|c|c.0).collect(),HOT_MOVERS,&mut out);
 let mut by_oi:Vec<(&str,f64)>=pool.iter().filter_map(|c|oi.get(c.0).map(|v|(c.0,*v))).collect();
 by_oi.sort_by(|a,b|b.1.total_cmp(&a.1).then(a.0.cmp(b.0)));
 push(by_oi.iter().map(|c|c.0).collect(),HOT_OI,&mut out);
 push(pool.iter().filter(|c|c.2.turnover>0.0).map(|c|c.0).collect(),HOT_TURNOVER,&mut out);
 let mut equities:Vec<(&str,Ticker)>=perps(info).into_iter().filter(|p|p.underlying=="EQUITY"&&!exclude.contains(p.base))
  .map(|p|(p.base,tickers.get(p.symbol).copied().unwrap_or_default())).filter(|e|e.1.turnover>0.0).collect();
 equities.sort_by(|a,b|b.1.change_pct.abs().total_cmp(&a.1.change_pct.abs()).then(a.0.cmp(b.0)));
 push(equities.iter().map(|e|e.0).collect(),HOT_EQUITY,&mut out);
 out.truncate(MAX_HOT);
 out
}

#[cfg(test)]
mod tests {
 use super::*;
 use serde_json::json;

 fn sym(symbol:&str,base:&str,kind:&str,underlying:&str)->Value {
  json!({"symbol":symbol,"baseAsset":base,"quoteAsset":"USDT","status":"TRADING","contractType":kind,"underlyingType":underlying})
 }
 fn tick(symbol:&str,turnover:f64,change:f64)->Value {json!({"symbol":symbol,"quoteVolume":turnover.to_string(),"priceChangePercent":change.to_string()})}

 #[test] fn layer_switch_parses() {
  assert_eq!(Enabled::parse(None),Enabled::ALL);
  assert_eq!(Enabled::parse(Some("")),Enabled::ALL);
  assert_eq!(Enabled::parse(Some("fixed")),Enabled{fixed:true,alts:false,hot:false});
  assert_eq!(Enabled::parse(Some("fixed, alts,hot")),Enabled::ALL);
  assert_eq!(Enabled::parse(Some("none")),Enabled{fixed:false,alts:false,hot:false});
  assert_eq!(Enabled::parse(Some("FIXED,Hot")).describe(),"majors + on-demand + fixed,hot");
 }

 #[test] fn fixed_keeps_the_whole_ai_chain_and_names_what_binance_lacks() {
  let names:Vec<&str>=FIXED.iter().flat_map(|(_,n)|n.iter().copied()).collect();
  for must in ["SNDK","MU","SKHYNIX","SKHY","INTC","ARM","NVDA"] {assert!(names.contains(&must),"{must} 必须在固定层");}
  assert_eq!(FIXED[0].1.len(),67);
  let unique:HashSet<&str>=names.iter().copied().collect();
  assert_eq!(unique.len(),names.len(),"名单里没有重复");
  let info=json!({"symbols":[
   sym("NVDAUSDT","NVDA","TRADIFI_PERPETUAL","EQUITY"),
   sym("XAUUSDT","XAU","TRADIFI_PERPETUAL","COMMODITY"),
   // 同名的币不算（固定层要的是股票那只）。
   sym("NETUSDT","NET","PERPETUAL","COIN"),
   json!({"symbol":"SNDKUSDT","baseAsset":"SNDK","quoteAsset":"USDT","status":"SETTLING","contractType":"TRADIFI_PERPETUAL","underlyingType":"EQUITY"}),
  ]});
  let (found,missing)=fixed_bases(&info);
  assert_eq!(found,vec!["NVDA","XAU"]);
  assert!(missing.contains(&"NET".to_string())&&missing.contains(&"SNDK".to_string()));
  assert_eq!(found.len()+missing.len(),names.len());
 }

 fn market()->(Value,HashMap<String,Ticker>) {
  let mut symbols=vec![sym("BTCUSDT","BTC","PERPETUAL","COIN"),sym("USDCUSDT","USDC","PERPETUAL","COIN"),sym("1000PEPEUSDT","1000PEPE","PERPETUAL","COIN"),
   sym("NVDAUSDT","NVDA","TRADIFI_PERPETUAL","EQUITY"),sym("RKLBUSDT","RKLB","TRADIFI_PERPETUAL","EQUITY"),sym("HIMSUSDT","HIMS","TRADIFI_PERPETUAL","EQUITY")];
  let mut tickers=vec![tick("BTCUSDT",9e9,1.0),tick("USDCUSDT",8e9,0.0),tick("1000PEPEUSDT",7e9,3.0),tick("NVDAUSDT",1e9,9.0),tick("RKLBUSDT",1e8,-12.0),tick("HIMSUSDT",1e8,4.0)];
  for i in 0..60 {
   let base=format!("C{i:02}");
   symbols.push(sym(&format!("{base}USDT"),&base,"PERPETUAL","COIN"));
   // 成交额从大到小；涨跌幅大的在后面（C55 以后最猛但成交额只有 1000 万，涨跌幅那一路不看它们）。
   tickers.push(tick(&format!("{base}USDT"),if i>=55 {1e7} else {6e9-i as f64*1e8},i as f64*0.5));
  }
  (json!({"symbols":symbols}),ticker_map(&json!(tickers)))
 }

 #[test] fn alts_are_the_top_forty_coins_by_turnover() {
  let (info,tickers)=market();
  let fixed:HashSet<String>=["NVDA".to_string()].into();
  let alts=pick_alts(&info,&tickers,&fixed);
  assert_eq!(alts.len(),40);
  assert_eq!(alts[0],"PEPE","去掉 1000 前缀；BTC 与 USDC 不算");
  assert_eq!(alts[1],"C00");
  assert!(!alts.contains(&"BTC".to_string())&&!alts.contains(&"USDC".to_string())&&!alts.contains(&"NVDA".to_string()));
 }

 #[test] fn hot_is_the_union_of_four_signals() {
  let (info,tickers)=market();
  let fixed:HashSet<String>=["NVDA".to_string()].into();
  let alts=pick_alts(&info,&tickers,&fixed);
  let mut exclude=fixed.clone();exclude.extend(alts.iter().cloned());
  let oi:HashMap<String,f64>=[("C45".to_string(),30.0),("C50".to_string(),20.0),("C00".to_string(),99.0)].into();
  let hot=pick_hot(&info,&tickers,&oi,&exclude);
  // ① 涨跌幅：成交额 ≥ 5000 万里涨跌幅最大的。
  assert_eq!(hot[0],"C54","C55 以后成交额不到 5000 万");
  assert!(!hot[..8].contains(&"C59".to_string()));
  // ② 持仓变化：C00 已在山寨层，不算。
  assert!(hot.contains(&"C45".to_string())&&hot.contains(&"C50".to_string())&&!hot.contains(&"C00".to_string()));
  // ④ 美股单独一组：NVDA 在固定层，RKLB 涨跌幅最大。
  assert!(hot.contains(&"RKLB".to_string())&&hot.contains(&"HIMS".to_string())&&!hot.contains(&"NVDA".to_string()));
  assert!(hot.len()<=MAX_HOT);
  let unique:HashSet<&String>=hot.iter().collect();
  assert_eq!(unique.len(),hot.len());
  for h in &hot {assert!(!exclude.contains(h));}
 }

 #[test] fn oi_change_reads_four_hours() {
  let rows=json!([{"sumOpenInterest":"100"},{"sumOpenInterest":"110"},{"sumOpenInterest":"90"},{"sumOpenInterest":"95"},{"sumOpenInterest":"80"}]);
  assert_eq!(oi_change(&rows),Some(20.0));
  assert_eq!(oi_change(&json!([{"sumOpenInterest":"100"}])),None);
  assert_eq!(oi_change(&json!({"code":-1})),None);
 }
}
