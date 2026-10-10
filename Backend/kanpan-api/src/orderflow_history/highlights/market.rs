//! 首页榜单（原型 §12 `/v1/market/board`）：持仓增加 / 持仓减少 / 涨幅 / 跌幅 × 1 时 / 4 时 / 24 时，全市场永续、四家合并到基础币。
//!
//! 每 5 分钟扫一次全市场（不起跟踪、不开流）：
//! * 币安 U 本位：合约表 + 24h 行情全表各一次（与山寨 / 热点层共用 5 分钟缓存）；持仓没有全表接口，只对成交额前 150
//!   逐只取 `openInterest`（间隔 250 毫秒，权重 150 / 5 分钟）。
//! * Bybit `v5/market/tickers?category=linear`、OKX `market/tickers` 与 `public/open-interest`（SWAP）、Hyperliquid
//!   `metaAndAssetCtxs`：都是一次拿全表，自带持仓金额。
//!
//! 价格按家优先取一家（币安 → Bybit → OKX → Hyperliquid，换算到每个币），持仓金额四家相加，成交额四家相加。
//! 每次扫完记一份快照：近 4.5 小时每份都留、更早的每小时留一份、最多 25 小时；1 时 / 4 时的涨跌与持仓变化拿它对，
//! 24 时涨跌直接用那一家自己的 24 小时涨跌。持仓变化只比两边都有的那几家（币安前 150 的名单进进出出不算变化）。
//! 快照每 15 分钟落一份进 `orderflow_highlights`（行名 `~board`）；冷启动没有快照时，用币安 `openInterestHist`
//! 5 分钟历史给成交额前 150 补一天（价格取持仓金额 ÷ 持仓量）。
use super::super::layers;
use super::{Answers,accepts_gzip,instruments,now_ms,packed};
use crate::AppState;
use crate::error::{ApiError,Params,Result};
use axum::extract::State as Axum;
use axum::response::Response;
use serde::Deserialize;
use serde_json::{Value,json};
use sqlx::{PgPool,Row};
use std::collections::{BTreeMap,HashMap,VecDeque};
use std::sync::{LazyLock,RwLock};
use std::time::Duration;

pub(in super::super) const PATH:&str="/v1/market/board";
const TTL:Duration=Duration::from_secs(60);
const CACHE_CONTROL:&str="public, max-age=60";
const M:i64=60_000;
const HOUR_MS:i64=60*M;
const SCAN_EVERY:Duration=Duration::from_secs(5*60);
/// 每份都留的那一段。
const FINE_MS:i64=270*M;
/// 最多留多久。
const KEEP_MS:i64=25*HOUR_MS;
const PERSIST_EVERY_MS:i64=15*M;
const KEY:&str="~board";
/// 币安逐只取持仓的只数与间隔。
const BINANCE_OI_TOP:usize=150;
const OI_GAP:Duration=Duration::from_millis(250);
/// 进榜门槛：持仓金额（持仓榜）与四家 24h 成交额（涨跌榜）。
const MIN_OI_USD:f64=1_000_000.0;
const MIN_TURNOVER:f64=1_000_000.0;
const MAX_ROWS:usize=100;

const OI_BN:&str="https://www.binance.com/fapi/v1/openInterest";
const OI_HIST_BN:&str="https://www.binance.com/futures/data/openInterestHist";
const TICKERS_BYBIT:&str="https://api.bybit.com/v5/market/tickers?category=linear";
const TICKERS_OKX:&str="https://www.okx.com/api/v5/market/tickers?instType=SWAP";
const OI_OKX:&str="https://www.okx.com/api/v5/public/open-interest?instType=SWAP";

/// 四家（币安 0 · Bybit 1 · OKX 2 · Hyperliquid 3）：价格优先级也是这个顺序。
const BN:usize=0;
#[cfg(test)]
const BYBIT:usize=1;
const HL:usize=3;

/// 此刻一只（四家合并）。
#[derive(Clone,Debug,Default,PartialEq)]
pub(super) struct Cur {
 /// 每个币的价格与给出价格的那一家（四家里优先级最高的）。
 pub px:f64,
 pub src:usize,
 /// 那一家自己的 24 小时涨跌（%）。
 pub change24:Option<f64>,
 /// 各家持仓金额（USD）。
 pub oi:[Option<f64>;4],
 /// 四家 24h 成交额相加（USD）。
 pub turnover:f64,
}

/// 一份快照里的一只。
#[derive(Clone,Copy,Debug,Default,PartialEq)]
pub(super) struct Cell {pub px:f64,pub oi:[Option<f32>;4]}

#[derive(Clone,Debug,Default)]
pub(super) struct Snapshot {pub at:i64,pub cells:HashMap<String,Cell>}

#[derive(Default)]
struct Board {latest:Option<(i64,HashMap<String,Cur>)>,ring:VecDeque<Snapshot>}

static BOARD:LazyLock<RwLock<Board>>=LazyLock::new(||RwLock::new(Board::default()));
static ANSWERS:LazyLock<Answers<(u8,u8,bool)>>=LazyLock::new(||Answers::new(TTL));

fn num(v:&Value)->Option<f64> {
 let x=match v {Value::String(s)=>s.parse().ok()?,Value::Number(n)=>n.as_f64()?,_=>return None};
 x.is_finite().then_some(x)
}

// ------------------------------------------------------------------ 四家全表

/// 合并时一家报上来的一行（`listed` 是表里的 base，可能带「N 个币」前缀）。
#[derive(Clone,Debug,PartialEq)]
pub(super) struct Quote {pub listed:String,pub px:Option<f64>,pub change24:Option<f64>,pub oi_usd:Option<f64>,pub turnover:f64}

/// 把一家的 base 换成手机用的 base 与倍数；Hyperliquid 的 `kPEPE` 是 1000 个。
fn coin(listed:&str,venue:usize)->(u64,String) {
 if venue==HL && let Some(rest)=listed.strip_prefix('k') && rest.bytes().next().is_some_and(|b|b.is_ascii_uppercase()) {return (1000,rest.to_string())}
 let (scale,base)=instruments::scale_of(listed);
 (scale,base.to_string())
}

/// 币安：合约表筛出的永续 × 24h 行情全表（价、24h 涨跌、成交额）× 前 150 的持仓量。
pub(super) fn binance_quotes(listing:&[(String,String)],tickers:&Value,oi:&HashMap<String,f64>)->Vec<Quote> {
 let rows:HashMap<&str,&Value>=tickers.as_array().map(Vec::as_slice).unwrap_or_default().iter().filter_map(|r|Some((r["symbol"].as_str()?,r))).collect();
 listing.iter().filter_map(|(symbol,listed)| {
  let r=rows.get(symbol.as_str())?;
  let px=num(&r["lastPrice"]).filter(|p|*p>0.0);
  Some(Quote{listed:listed.clone(),px,change24:num(&r["priceChangePercent"]),oi_usd:oi.get(symbol).zip(px).map(|(q,p)|q*p),turnover:num(&r["quoteVolume"]).unwrap_or(0.0)})
 }).collect()
}

/// Bybit linear 全表：只要 `XUSDT` 永续。
pub(super) fn bybit_quotes(body:&Value)->Vec<Quote> {
 body["result"]["list"].as_array().map(Vec::as_slice).unwrap_or_default().iter().filter_map(|r| {
  let listed=r["symbol"].as_str()?.strip_suffix("USDT")?;
  if listed.is_empty()||listed.contains('-') {return None}
  Some(Quote{listed:listed.to_string(),px:num(&r["lastPrice"]).filter(|p|*p>0.0),change24:num(&r["price24hPcnt"]).map(|x|x*100.0),
   oi_usd:num(&r["openInterestValue"]),turnover:num(&r["turnover24h"]).unwrap_or(0.0)})
 }).collect()
}

/// OKX：行情全表（`X-USDT-SWAP` 的价、24h 涨跌、成交额）+ 持仓全表（U 本位与币本位永续的 `oiUsd` 相加）。
pub(super) fn okx_quotes(tickers:&Value,oi:&Value)->Vec<Quote> {
 let mut oi_by:HashMap<&str,f64>=HashMap::new();
 for r in oi["data"].as_array().map(Vec::as_slice).unwrap_or_default() {
  let Some(id)=r["instId"].as_str() else {continue};
  let Some(base)=id.strip_suffix("-SWAP").and_then(|s|s.rsplit_once('-')).map(|(b,_)|b) else {continue};
  if let Some(v)=num(&r["oiUsd"]) {*oi_by.entry(base).or_default()+=v;}
 }
 let mut out:Vec<Quote>=tickers["data"].as_array().map(Vec::as_slice).unwrap_or_default().iter().filter_map(|r| {
  let base=r["instId"].as_str()?.strip_suffix("-USDT-SWAP")?;
  let px=num(&r["last"]).filter(|p|*p>0.0);
  let open=num(&r["open24h"]).filter(|p|*p>0.0);
  Some(Quote{listed:base.to_string(),px,change24:px.zip(open).map(|(p,o)|(p/o-1.0)*100.0),oi_usd:oi_by.remove(base),
   turnover:num(&r["volCcy24h"]).zip(px).map_or(0.0,|(v,p)|v*p)})
 }).collect();
 // 只有币本位、没有 U 本位行情的：持仓照样算进去。
 out.extend(oi_by.into_iter().map(|(b,v)|Quote{listed:b.to_string(),px:None,change24:None,oi_usd:Some(v),turnover:0.0}));
 out
}

/// Hyperliquid `metaAndAssetCtxs`：`[meta, ctxs]`，按序一一对应；下架的跳过。持仓量是币数，乘标记价。
pub(super) fn hyperliquid_quotes(body:&Value)->Vec<Quote> {
 let (Some(universe),Some(ctxs))=(body[0]["universe"].as_array(),body[1].as_array()) else {return Vec::new()};
 universe.iter().zip(ctxs).filter_map(|(u,c)| {
  if u["isDelisted"].as_bool()==Some(true) {return None}
  let px=num(&c["markPx"]).filter(|p|*p>0.0);
  let prev=num(&c["prevDayPx"]).filter(|p|*p>0.0);
  Some(Quote{listed:u["name"].as_str()?.to_string(),px,change24:px.zip(prev).map(|(p,o)|(p/o-1.0)*100.0),
   oi_usd:num(&c["openInterest"]).zip(px).map(|(q,p)|q*p),turnover:num(&c["dayNtlVlm"]).unwrap_or(0.0)})
 }).collect()
}

/// 四家合并到基础币。
pub(super) fn merge(venues:[Vec<Quote>;4])->HashMap<String,Cur> {
 let mut out:HashMap<String,Cur>=HashMap::new();
 for (v,quotes) in venues.into_iter().enumerate() {
  for q in quotes {
   let (scale,base)=coin(&q.listed,v);
   if !instruments::valid_base(&base) {continue}
   let c=out.entry(base).or_insert_with(||Cur{src:usize::MAX,..Cur::default()});
   if let Some(px)=q.px && v<c.src {c.px=px/scale as f64;c.src=v;c.change24=q.change24;}
   if let Some(oi)=q.oi_usd.filter(|x|x.is_finite()&&*x>=0.0) {*c.oi[v].get_or_insert(0.0)+=oi;}
   if q.turnover.is_finite()&&q.turnover>0.0 {c.turnover+=q.turnover;}
  }
 }
 out.retain(|_,c|c.src!=usize::MAX);
 out
}

fn snapshot_of(at:i64,cur:&HashMap<String,Cur>)->Snapshot {
 Snapshot{at,cells:cur.iter().map(|(b,c)|(b.clone(),Cell{px:c.px,oi:c.oi.map(|x|x.map(|v|v as f32))})).collect()}
}

/// 收进一份快照，按「近 4.5 小时全留、更早每小时一份、最多 25 小时」修剪。
pub(super) fn push(ring:&mut VecDeque<Snapshot>,snap:Snapshot) {
 let now=snap.at;
 ring.push_back(snap);
 let mut ring_sorted:Vec<Snapshot>=std::mem::take(ring).into();
 ring_sorted.sort_by_key(|s|s.at);
 let mut hours=std::collections::HashSet::new();
 for s in ring_sorted {
  let age=now-s.at;
  if age>KEEP_MS {continue}
  if age>FINE_MS&&!hours.insert(s.at.div_euclid(HOUR_MS)) {continue}
  ring.push_back(s);
 }
}

/// 离 `target` 相差不超过 `tol` 的那几份，近的在前。一只在最近那份里没有（冷启动补的那一天各合约的起点差几分钟、
/// 币安前 150 进进出出）就往下一份找。
fn near(ring:&VecDeque<Snapshot>,target:i64,tol:i64)->Vec<&Snapshot> {
 let mut out:Vec<&Snapshot>=ring.iter().filter(|s|(s.at-target).abs()<=tol).collect();
 out.sort_by_key(|s|(s.at-target).abs());
 out
}

fn cell<'a>(then:&[&'a Snapshot],base:&str)->Option<&'a Cell> {then.iter().find_map(|s|s.cells.get(base))}

/// 持仓变化（%）：只比两边都有的那几家。
fn oi_change(now:&[Option<f64>;4],then:&[Option<f32>;4])->Option<f64> {
 let (mut a,mut b)=(0.0,0.0);
 for i in 0..4 {if let (Some(x),Some(y))=(now[i],then[i]) {a+=x;b+=f64::from(y);}}
 (b>0.0).then(||(a/b-1.0)*100.0)
}

#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub(super) enum Kind {Oi,OiDown,Gainers,Losers}
const WINDOWS:[(&str,i64);3]=[("1h",HOUR_MS),("4h",4*HOUR_MS),("24h",24*HOUR_MS)];

/// 拼一份榜：`then` 是窗口起点附近的快照、近的在前（24 时涨跌不用它）。
pub(super) fn rank(kind:Kind,window:usize,latest:&HashMap<String,Cur>,then:&[&Snapshot],now:i64)->Value {
 let falling=matches!(kind,Kind::Losers|Kind::OiDown);
 let mut rows:Vec<(f64,&String,&Cur)>=latest.iter().filter_map(|(b,c)| {
  let total:Option<f64>=c.oi.iter().flatten().copied().reduce(|a,b|a+b);
  let change=match kind {
   Kind::Oi|Kind::OiDown=>{
    if total.unwrap_or(0.0)<MIN_OI_USD {return None}
    oi_change(&c.oi,&cell(then,b)?.oi)?
   },
   Kind::Gainers|Kind::Losers=>{
    if c.turnover<MIN_TURNOVER {return None}
    if WINDOWS[window].0=="24h" {c.change24?} else {
     let old=cell(then,b)?.px;
     if !(old>0.0) {return None}
     (c.px/old-1.0)*100.0
    }
   },
  };
   // 持仓增加榜看「钱往哪建仓」、持仓减少榜看「钱从哪撤」，涨幅榜只放涨的、跌幅榜只放跌的：方向不对的不拿来凑满 100 行。
  // 按写出去的两位小数判：0.00 / -0.00 不进榜。
  let change=(change*100.0).round()/100.0+0.0;
  let right_way=if falling {change<0.0} else {change>0.0};
  (change.is_finite()&&right_way).then_some((change,b,c))
 }).collect();
 rows.sort_by(|a,b|{let o=b.0.total_cmp(&a.0);(if falling {o.reverse()} else {o}).then_with(||a.1.cmp(b.1))});
 let rows:Vec<Value>=rows.into_iter().take(MAX_ROWS).map(|(change,b,c)|{
  let total:Option<f64>=c.oi.iter().flatten().copied().reduce(|a,b|a+b);
  json!({"base":b,"oiUsd":total.map(|v|v.round()),"changePct":change,"price":super::state::sig(c.px)})
 }).collect();
 json!({"generatedAtMs":now,"rows":rows})
}

// ------------------------------------------------------------------ 扫描

async fn get(url:&str)->Option<Value> {crate::market_meta::get_json(url).await.ok()}

async fn binance()->Vec<Quote> {
 let (Ok(info),Ok(tickers))=(crate::market_meta::exchange_info().await,layers::tickers().await) else {return Vec::new()};
 let listing=layers::perp_listing(&info);
 let oi=binance_oi(&listing,&tickers).await;
 binance_quotes(&listing,&tickers,&oi)
}

/// 成交额前 150 的币安合约（按 24h 成交额降序）。
fn top_symbols(listing:&[(String,String)],tickers:&Value)->Vec<String> {
 let turnover:HashMap<&str,f64>=tickers.as_array().map(Vec::as_slice).unwrap_or_default().iter()
  .filter_map(|r|Some((r["symbol"].as_str()?,num(&r["quoteVolume"]).unwrap_or(0.0)))).collect();
 let mut syms:Vec<(f64,&String)>=listing.iter().map(|(s,_)|(turnover.get(s.as_str()).copied().unwrap_or(0.0),s)).filter(|x|x.0>0.0).collect();
 syms.sort_by(|a,b|b.0.total_cmp(&a.0).then_with(||a.1.cmp(b.1)));
 syms.into_iter().take(BINANCE_OI_TOP).map(|x|x.1.clone()).collect()
}

async fn binance_oi(listing:&[(String,String)],tickers:&Value)->HashMap<String,f64> {
 let mut out=HashMap::new();
 for symbol in top_symbols(listing,tickers) {
  if crate::binance_gate::blocked() {break}
  if let Some(v)=get(&format!("{OI_BN}?symbol={symbol}")).await && let Some(q)=num(&v["openInterest"]) {out.insert(symbol,q);}
  tokio::time::sleep(OI_GAP).await;
 }
 out
}

async fn hyperliquid()->Vec<Quote> {
 match crate::venues::hyperliquid::info_bytes(&json!({"type":"metaAndAssetCtxs"})).await {
  Ok(bytes)=>serde_json::from_slice::<Value>(&bytes).map(|v|hyperliquid_quotes(&v)).unwrap_or_default(),
  Err(e)=>{tracing::debug!("Market board: hyperliquid unavailable: {e}");Vec::new()},
 }
}

async fn scan()->HashMap<String,Cur> {
 let (bn,bybit,okx,hl)=tokio::join!(
  binance(),
  async {get(TICKERS_BYBIT).await.map(|v|bybit_quotes(&v)).unwrap_or_default()},
  async {let (t,o)=tokio::join!(get(TICKERS_OKX),get(OI_OKX));okx_quotes(&t.unwrap_or(Value::Null),&o.unwrap_or(Value::Null))},
  hyperliquid(),
 );
 tracing::debug!("Market board: binance {} bybit {} okx {} hyperliquid {}",bn.len(),bybit.len(),okx.len(),hl.len());
 merge([bn,bybit,okx,hl])
}

/// 冷启动：币安成交额前 150 的 5 分钟持仓历史（一天），折成只有币安那一家的快照。
async fn bootstrap(now:i64)->Vec<Snapshot> {
 let (Ok(info),Ok(tickers))=(crate::market_meta::exchange_info().await,layers::tickers().await) else {return Vec::new()};
 let listing=layers::perp_listing(&info);
 let listed:HashMap<&str,&str>=listing.iter().map(|(s,l)|(s.as_str(),l.as_str())).collect();
 let mut by_at:BTreeMap<i64,HashMap<String,Cell>>=BTreeMap::new();
 for symbol in top_symbols(&listing,&tickers) {
  if crate::binance_gate::blocked() {break}
  let Some(l)=listed.get(symbol.as_str()) else {continue};
  if let Some(rows)=get(&format!("{OI_HIST_BN}?symbol={symbol}&period=5m&limit=289")).await {
   for (at,cell) in hist_cells(&rows,l) {by_at.entry(at).or_default().insert(coin(l,BN).1,cell);}
  }
  tokio::time::sleep(OI_GAP).await;
 }
 by_at.into_iter().filter(|(at,_)|now-at<=KEEP_MS).map(|(at,cells)|Snapshot{at,cells}).collect()
}

/// `openInterestHist` 的行 → (时刻, 只有币安的格)；价格 = 持仓金额 ÷ 持仓量（换算到每个币）。
pub(super) fn hist_cells(rows:&Value,listed:&str)->Vec<(i64,Cell)> {
 let (scale,_)=coin(listed,BN);
 rows.as_array().map(Vec::as_slice).unwrap_or_default().iter().filter_map(|r| {
  let at=r["timestamp"].as_i64()?;
  let q=num(&r["sumOpenInterest"]).filter(|q|*q>0.0)?;
  let v=num(&r["sumOpenInterestValue"]).filter(|v|*v>0.0)?;
  let mut oi=[None;4];
  oi[BN]=Some(v as f32);
  Some((at,Cell{px:v/q/scale as f64,oi}))
 }).collect()
}

// ------------------------------------------------------------------ 每分钟的价（波动异动）

const PRICES_BN:&str="https://www.binance.com/fapi/v1/ticker/price";

/// 币安价格全表 `[{symbol, price}]` 按合约表筛出永续。
pub(super) fn binance_price_quotes(listing:&[(String,String)],body:&Value)->Vec<Quote> {
 let rows:HashMap<&str,f64>=body.as_array().map(Vec::as_slice).unwrap_or_default().iter()
  .filter_map(|r|Some((r["symbol"].as_str()?,num(&r["price"]).filter(|p|*p>0.0)?))).collect();
 listing.iter().filter_map(|(symbol,listed)|Some(Quote{listed:listed.clone(),px:Some(*rows.get(symbol.as_str())?),change24:None,oi_usd:None,turnover:0.0})).collect()
}

async fn binance_prices()->Vec<Quote> {
 if crate::binance_gate::blocked() {return Vec::new()}
 let (Ok(info),Some(body))=(crate::market_meta::exchange_info().await,get(PRICES_BN).await) else {return Vec::new()};
 binance_price_quotes(&layers::perp_listing(&info),&body)
}

/// 此刻全市场永续的价（四家合并、价按同一优先级取一家）：币安只取价格全表（权重低），其余三家同榜单的行情全表；不取持仓。
pub(super) async fn prices()->HashMap<String,Cur> {
 let (bn,bybit,okx,hl)=tokio::join!(
  binance_prices(),
  async {get(TICKERS_BYBIT).await.map(|v|bybit_quotes(&v)).unwrap_or_default()},
  async {get(TICKERS_OKX).await.map(|t|okx_quotes(&t,&Value::Null)).unwrap_or_default()},
  hyperliquid(),
 );
 merge([bn,bybit,okx,hl])
}

/// 榜单最近一次扫到的四家 24h 成交额相加（USD），按基础币。
pub(super) fn turnover()->HashMap<String,f64> {
 let b=BOARD.read().unwrap_or_else(|e|e.into_inner());
 b.latest.as_ref().map(|(_,cur)|cur.iter().map(|(k,c)|(k.clone(),c.turnover)).collect()).unwrap_or_default()
}

// ------------------------------------------------------------------ 落盘

pub(super) fn payload(ring:&VecDeque<Snapshot>)->Value {
 let snaps:Vec<Value>=ring.iter().map(|s|{
  let mut cells:Vec<(&String,&Cell)>=s.cells.iter().collect();
  cells.sort_by(|a,b|a.0.cmp(b.0));
  json!([s.at,cells.into_iter().map(|(b,c)|json!([b,super::state::sig(c.px),c.oi[0],c.oi[1],c.oi[2],c.oi[3]])).collect::<Vec<_>>()])
 }).collect();
 json!({"v":1,"snaps":snaps})
}

pub(super) fn restore(v:&Value)->VecDeque<Snapshot> {
 let mut ring=VecDeque::new();
 if v["v"]!=json!(1) {return ring}
 for s in v["snaps"].as_array().map(Vec::as_slice).unwrap_or_default() {
  let Some(at)=s[0].as_i64() else {continue};
  let cells=s[1].as_array().map(Vec::as_slice).unwrap_or_default().iter().filter_map(|c| {
   let f=|i:usize|c[i].as_f64().map(|x|x as f32);
   Some((c[0].as_str()?.to_string(),Cell{px:c[1].as_f64()?,oi:[f(2),f(3),f(4),f(5)]}))
  }).collect();
  ring.push_back(Snapshot{at,cells});
 }
 ring
}

async fn load(pool:&PgPool)->Option<Value> {
 let row=sqlx::query("SELECT payload FROM orderflow_highlights WHERE base=$1").bind(KEY).fetch_optional(pool).await.ok()??;
 row.try_get::<sqlx::types::Json<Value>,_>(0).ok().map(|j|j.0)
}

async fn save(pool:&PgPool,payload:&Value,at:i64) {
 let r=sqlx::query("INSERT INTO orderflow_highlights(base,updated_ms,payload) VALUES($1,$2,$3) ON CONFLICT(base) DO UPDATE SET updated_ms=EXCLUDED.updated_ms,payload=EXCLUDED.payload")
  .bind(KEY).bind(at).bind(sqlx::types::Json(payload)).execute(pool).await;
 if let Err(e)=r {tracing::warn!("Market board: save failed: {e}");}
}

pub(super) async fn run(pool:PgPool) {
 let now=now_ms();
 let mut ring=load(&pool).await.map(|v|restore(&v)).unwrap_or_default();
 ring.retain(|s|now-s.at<=KEEP_MS);
 if ring.is_empty() {
  for s in bootstrap(now).await {push(&mut ring,s);}
  tracing::info!("Market board: bootstrapped {} snapshots from Binance open interest history",ring.len());
 }
 BOARD.write().unwrap_or_else(|e|e.into_inner()).ring=ring;
 let mut saved=0;
 let mut tick=tokio::time::interval(SCAN_EVERY);
 tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
 loop {
  tick.tick().await;
  let cur=scan().await;
  let now=now_ms();
  if cur.is_empty() {tracing::warn!("Market board: scan returned nothing");continue}
  let payload={
   let mut b=BOARD.write().unwrap_or_else(|e|e.into_inner());
   push(&mut b.ring,snapshot_of(now,&cur));
   b.latest=Some((now,cur));
   (now-saved>=PERSIST_EVERY_MS).then(||payload(&b.ring))
  };
  if let Some(p)=payload {save(&pool,&p,now).await;saved=now;}
 }
}

// ------------------------------------------------------------------ 接口

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(in super::super) struct BoardQuery {kind:String,window:Option<String>}

fn kind_of(s:&str)->Option<Kind> {match s {"oi"=>Some(Kind::Oi),"oidown"=>Some(Kind::OiDown),"gainers"=>Some(Kind::Gainers),"losers"=>Some(Kind::Losers),_=>None}}

/// 榜单：`kind=oi|oidown|gainers|losers`，`window=1h|4h|24h`（缺省 4h，原型出厂档）。
pub(in super::super) async fn market_board(Axum(_s):Axum<AppState>,headers:axum::http::HeaderMap,Params(q):Params<BoardQuery>)->Result<Response> {
 let kind=kind_of(&q.kind).ok_or_else(||ApiError::bad("invalid_kind"))?;
 let window=WINDOWS.iter().position(|(w,_)|*w==q.window.as_deref().unwrap_or("4h")).ok_or_else(||ApiError::bad("invalid_window"))?;
 let gzip=accepts_gzip(&headers);
 let answer=ANSWERS.get_or_build((kind as u8,window as u8,gzip),||async move {
  let now=now_ms();
  let json={
   let b=BOARD.read().unwrap_or_else(|e|e.into_inner());
   match &b.latest {
    Some((at,latest))=>{
     let span=WINDOWS[window].1;
     let then=near(&b.ring,at-span,if span>=24*HOUR_MS {40*M} else {10*M});
     rank(kind,window,latest,&then,now)
    },
    None=>json!({"generatedAtMs":now,"rows":[]}),
   }
  };
  packed(json.to_string(),gzip,CACHE_CONTROL)
 }).await?;
 Ok(answer.response())
}

#[cfg(test)]
mod tests {
 use super::*;

 fn q(listed:&str,px:f64,oi:Option<f64>,turnover:f64,ch:f64)->Quote {Quote{listed:listed.into(),px:Some(px),change24:Some(ch),oi_usd:oi,turnover}}

 #[test]
 fn parses_the_three_bulk_payloads() {
  let bybit=json!({"result":{"list":[
   {"symbol":"0GUSDT","lastPrice":"0.2586","price24hPcnt":"-0.108275","openInterestValue":"2821955.04","turnover24h":"3560802.66"},
   {"symbol":"BTCPERP","lastPrice":"1"},{"symbol":"ETH-26DEC25","lastPrice":"1"}]}});
  let b=bybit_quotes(&bybit);
  assert_eq!(b.len(),1);
  assert_eq!(b[0].listed,"0G");
  assert!((b[0].change24.unwrap()+10.8275).abs()<1e-9);
  let okx_t=json!({"data":[{"instId":"PI-USDT-SWAP","last":"0.08","open24h":"0.1","volCcy24h":"1000"},{"instId":"BTC-USD-SWAP","last":"1"}]});
  let okx_o=json!({"data":[{"instId":"BTC-USD-SWAP","oiUsd":"500"},{"instId":"BTC-USDT-SWAP","oiUsd":"700"},{"instId":"PI-USDT-SWAP","oiUsd":"9"}]});
  let mut o=okx_quotes(&okx_t,&okx_o);
  o.sort_by(|a,b|a.listed.cmp(&b.listed));
  assert_eq!(o[0],Quote{listed:"BTC".into(),px:None,change24:None,oi_usd:Some(1200.0),turnover:0.0});
  assert_eq!(o[1].listed,"PI");
  assert!((o[1].change24.unwrap()+20.0).abs()<1e-9);
  assert!((o[1].turnover-80.0).abs()<1e-9);
  let hl=json!([{"universe":[{"name":"BTC"},{"name":"MATIC","isDelisted":true},{"name":"kPEPE"}]},
   [{"markPx":"100","prevDayPx":"80","openInterest":"2","dayNtlVlm":"5"},{"markPx":"1"},{"markPx":"0.01","openInterest":"1000"}]]);
  let h=hyperliquid_quotes(&hl);
  assert_eq!(h.len(),2);
  assert_eq!(h[0].oi_usd,Some(200.0));
  assert_eq!(h[0].change24,Some(25.0));
  assert_eq!(h[1].listed,"kPEPE");
 }

 #[test]
 fn binance_rows_join_listing_tickers_and_oi() {
  let listing=vec![("1000PEPEUSDT".to_string(),"1000PEPE".to_string()),("BTCUSDT".to_string(),"BTC".to_string())];
  let tickers=json!([{"symbol":"BTCUSDT","lastPrice":"100","priceChangePercent":"2.5","quoteVolume":"9"},{"symbol":"1000PEPEUSDT","lastPrice":"0.01","quoteVolume":"3"},{"symbol":"XUSDT","lastPrice":"1"}]);
  let oi=HashMap::from([("BTCUSDT".to_string(),3.0)]);
  let rows=binance_quotes(&listing,&tickers,&oi);
  assert_eq!(rows.len(),2);
  assert_eq!(rows[1].oi_usd,Some(300.0));
  let px=binance_price_quotes(&listing,&json!([{"symbol":"BTCUSDT","price":"101.5"},{"symbol":"XUSDT","price":"1"},{"symbol":"1000PEPEUSDT","price":"0"}]));
  assert_eq!(px,vec![Quote{listed:"BTC".into(),px:Some(101.5),change24:None,oi_usd:None,turnover:0.0}]);
  assert_eq!(rows[0].oi_usd,None);
  assert_eq!(top_symbols(&listing,&tickers),vec!["BTCUSDT","1000PEPEUSDT"]);
 }

 #[test]
 fn merge_prefers_binance_price_and_sums_oi_per_coin() {
  let m=merge([vec![q("1000PEPE",0.01,Some(100.0),10.0,1.0)],vec![q("1000PEPE",0.0101,Some(50.0),5.0,9.0),q("ONLYBY",2.0,None,1.0,-3.0)],
   vec![q("PEPE",0.00001,Some(25.0),1.0,0.0)],vec![q("kPEPE",0.0102,Some(5.0),1.0,0.0)]]);
  let p=&m["PEPE"];
  assert!((p.px-0.00001).abs()<1e-15);
  assert_eq!(p.src,BN);
  assert_eq!(p.change24,Some(1.0));
  assert_eq!(p.oi,[Some(100.0),Some(50.0),Some(25.0),Some(5.0)]);
  assert!((p.turnover-17.0).abs()<1e-9);
  assert_eq!(m["ONLYBY"].src,BYBIT);
 }

 #[test]
 fn ring_keeps_fine_then_hourly_up_to_a_day() {
  let mut ring=VecDeque::new();
  let end=30*HOUR_MS;
  let mut t=0;
  while t<=end {push(&mut ring,Snapshot{at:t,cells:HashMap::new()});t+=5*M;}
  assert!(ring.iter().all(|s|end-s.at<=KEEP_MS));
  let fine=ring.iter().filter(|s|end-s.at<=FINE_MS).count();
  assert_eq!(fine,(FINE_MS/(5*M)+1) as usize);
  let coarse:Vec<i64>=ring.iter().filter(|s|end-s.at>FINE_MS).map(|s|s.at.div_euclid(HOUR_MS)).collect();
  let mut d=coarse.clone();d.dedup();
  assert_eq!(coarse,d,"one per hour beyond 4.5h");
  assert!(!near(&ring,end-24*HOUR_MS,40*M).is_empty());
  assert_eq!(near(&ring,end-HOUR_MS,10*M)[0].at,end-HOUR_MS);
 }

 #[test]
 fn oi_change_only_compares_venues_on_both_sides() {
  // 币安这次有、那次没有（掉出前 150）：只比 Bybit。
  assert_eq!(oi_change(&[Some(500.0),Some(110.0),None,None],&[None,Some(100.0),None,None]).map(|x|(x*1e6).round()/1e6),Some(10.0));
  assert_eq!(oi_change(&[Some(1.0),None,None,None],&[None,Some(1.0),None,None]),None);
 }

 #[test]
 fn ranks_each_kind_and_window() {
  let cur=|px:f64,oi:f64,t:f64,ch:f64|Cur{px,src:BN,change24:Some(ch),oi:[Some(oi),None,None,None],turnover:t};
  let latest=HashMap::from([("A".to_string(),cur(110.0,2e6,5e6,30.0)),("B".to_string(),cur(90.0,3e6,5e6,-4.0)),("C".to_string(),cur(50.0,5e5,5e6,1.0)),("D".to_string(),cur(1.0,9e6,10.0,99.0))]);
  let mut cells=HashMap::new();
  for (b,px,oi) in [("A",100.0,1e6),("B",100.0,3.3e6),("C",40.0,1e5),("D",0.5,1e6)] {cells.insert(b.to_string(),Cell{px,oi:[Some(oi as f32),None,None,None]});}
  let then=Snapshot{at:0,cells};
  let bases=|v:&Value|v["rows"].as_array().unwrap().iter().map(|r|r["base"].as_str().unwrap().to_string()).collect::<Vec<_>>();
  let oi=rank(Kind::Oi,0,&latest,&[&then],5);
  assert_eq!(bases(&oi),vec!["D","A"],"C below the OI floor; B lost open interest");
  let down=rank(Kind::OiDown,0,&latest,&[&then],5);
  assert_eq!(bases(&down),vec!["B"],"only bases that lost open interest");
  assert_eq!(down["rows"][0]["changePct"],-9.09);
  assert_eq!(kind_of("oidown"),Some(Kind::OiDown));
  assert_eq!(oi["rows"][1]["changePct"],100.0);
  assert_eq!(oi["rows"][1]["oiUsd"],2e6);
  assert_eq!(bases(&rank(Kind::Gainers,1,&latest,&[&then],5)),vec!["C","A"],"D below turnover floor; B fell");
  assert_eq!(bases(&rank(Kind::Losers,1,&latest,&[&then],5)),vec!["B"],"only fallers");
  let flat=HashMap::from([("F".to_string(),cur(100.004,2e6,5e6,0.0)),("G".to_string(),cur(99.996,2e6,5e6,0.0))]);
  let flat_then=Snapshot{at:0,cells:HashMap::from([("F".to_string(),Cell{px:100.0,oi:[Some(2e6),None,None,None]}),("G".to_string(),Cell{px:100.0,oi:[Some(2e6),None,None,None]})])};
  assert!(bases(&rank(Kind::Gainers,1,&flat,&[&flat_then],5)).is_empty(),"+0.004% rounds to 0.00");
  assert!(bases(&rank(Kind::Losers,1,&flat,&[&flat_then],5)).is_empty(),"-0.004% rounds to -0.00");
  assert_eq!(bases(&rank(Kind::Gainers,2,&latest,&[],5)),vec!["A","C"],"24h uses the venue's own change");
  assert!(rank(Kind::Gainers,0,&latest,&[],5)["rows"].as_array().unwrap().is_empty());
  let r=&rank(Kind::Gainers,2,&latest,&[],5)["rows"][0];
  for k in ["base","oiUsd","changePct","price"] {assert!(r.get(k).is_some(),"{k}");}
 }

 #[test]
 fn a_base_missing_from_the_nearest_snapshot_falls_back_to_the_next() {
  let latest=HashMap::from([("A".to_string(),Cur{px:110.0,src:BN,change24:None,oi:[Some(2e6),None,None,None],turnover:5e6})]);
  let near_one=Snapshot{at:0,cells:HashMap::new()};
  let next=Snapshot{at:5,cells:HashMap::from([("A".to_string(),Cell{px:100.0,oi:[Some(1e6),None,None,None]})])};
  let v=rank(Kind::Gainers,0,&latest,&[&near_one,&next],9);
  assert_eq!(v["rows"][0]["changePct"],10.0);
 }

 #[test]
 fn hist_rows_become_binance_cells() {
  let rows=json!([{"timestamp":300000,"sumOpenInterest":"2000","sumOpenInterestValue":"20"}]);
  let c=hist_cells(&rows,"1000PEPE");
  assert_eq!(c[0].0,300000);
  assert!((c[0].1.px-0.00001).abs()<1e-15);
  assert_eq!(c[0].1.oi[BN],Some(20.0));
 }

 #[test]
 fn payload_round_trips() {
  let mut ring=VecDeque::new();
  ring.push_back(Snapshot{at:7,cells:HashMap::from([("BTC".to_string(),Cell{px:100.5,oi:[Some(1.0),None,Some(3.0),None]})])});
  let back=restore(&payload(&ring));
  assert_eq!(back.len(),1);
  assert_eq!(back[0].at,7);
  assert_eq!(back[0].cells["BTC"],Cell{px:100.5,oi:[Some(1.0),None,Some(3.0),None]});
 }
}
