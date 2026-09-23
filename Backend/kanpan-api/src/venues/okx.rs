//! OKX 永续的持仓量与资金费率。
//!
//! OKX 在看盘里不是用户可见的交易所：它只是币安永续在网关线路上的替身（币安的
//! `fapi` 在美国 VPS 上回 451）。网关线路上顶栏六格要的「仓」和「费率 / 结算」由这里供：
//!
//! - `open_interest`：由 `market_meta` 的 `/v1/market/open-interest?source=okx` 分发过来；
//! - `funding`：`/v1/market/funding?source=okx`，整张表一次给（见 `venues::funding`）。
//!
//! - `ticker`：`/v1/market/ticker?source=okx&symbol=`，币安形状的 24h 行情，
//!   带上网关 Python 那一截给不出的 USDT 成交额（见 `ticker_payload`）；
//! - `oi_history`：`/v1/market/open-interest/history?source=okx`，持仓量副图的历史。
//!
//! 全都是 OKX 自己的数，不拿币安的顶（不混源）。
use crate::error::{ApiError,Result};
use crate::market_meta::{Cache,LIVE_TTL,OpenInterest,QUOTES,get_json,num,rows};
use serde_json::Value;
use std::collections::{HashMap,VecDeque};
use std::sync::{Arc,Mutex,OnceLock};
use std::time::{Duration,Instant};

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

// -------------------------------------------------------------------- 24h 行情

/// 官方文档（Market Data › Get tickers）：一次给全部永续的 `last`、滚动 24 小时的
/// `open24h` / `high24h` / `low24h`，和币安 `/fapi/v1/ticker/24hr` 同一个口径（都是滚动
/// 24 小时，不是自然日）。整张表一起抓：自选列表冷启动时手机一口气补二十几只，
/// 逐只问 `market/ticker` 会撞上它每 2 秒 20 次的限速。
const TICKERS_URL:&str="https://www.okx.com/api/v5/market/tickers?instType=SWAP";
/// 官方文档（Market Data › Get candlesticks）：每行 `[ts,o,h,l,c,vol,volCcy,volCcyQuote,confirm]`，
/// 一次最多 300 行；288 根 5 分钟正好一天。
const CANDLES_URL:&str="https://www.okx.com/api/v5/market/candles?bar=5m&limit=288&instId=";
/// 整张行情表两秒内共用一份。
const TICKER_TTL:Duration=Duration::from_secs(2);
/// 表刷不动时，十五秒内的旧表还能答（价格旧几秒总比整格「—」强，手机那头推送随后就盖上）。
const TICKER_MAX_AGE:Duration=Duration::from_secs(15);
/// 24 小时的成交均价一分钟重算一次就够：它只用来把币量换成 USDT，一分钟里挪不了几个基点。
const VWAP_TTL:Duration=Duration::from_secs(60);
/// 十分钟没刷成功就不再拿旧均价换算，宁可这一格留空。
const VWAP_MAX_AGE:Duration=Duration::from_secs(600);

/// 按键存、按时限取的小表。行情、均价、持仓量历史页都按品种（和参数）各存一份。
struct Slots<T> {slots:Mutex<HashMap<String,(Instant,T)>>}
impl<T:Clone> Slots<T> {
 fn new()->Self {Self{slots:Mutex::new(HashMap::new())}}
 fn get(&self,key:&str,ttl:Duration)->Option<T> {
  self.slots.lock().unwrap_or_else(|e|e.into_inner()).get(key).filter(|(at,_)|at.elapsed()<ttl).map(|(_,v)|v.clone())
 }
 fn put(&self,key:&str,value:T) {
  let mut slots=self.slots.lock().unwrap_or_else(|e|e.into_inner());
  if slots.len()>=1024 {slots.clear()}
  slots.insert(key.to_owned(),(Instant::now(),value));
 }
}
fn tickers_cache()->&'static Cache<HashMap<String,Ticker>> {static C:OnceLock<Cache<HashMap<String,Ticker>>>=OnceLock::new();C.get_or_init(Cache::new)}
fn vwap_cache()->&'static Slots<f64> {static C:OnceLock<Slots<f64>>=OnceLock::new();C.get_or_init(Slots::new)}

/// OKX 一只永续的 24h 行情。价格都保留 OKX 给的原文，免得 `f64` 来回一趟多出一串尾数。
#[derive(Clone,Debug,PartialEq)]
pub struct Ticker {
 pub last:String,pub open:String,pub high:String,pub low:String,
 /// `volCcy24h`：永续上是**币的个数**，不是 USDT。
 pub base_volume:f64,
 pub time:i64,
}

fn ticker_row(row:&Value)->Option<Ticker> {
 let text=|k:&str|row[k].as_str().map(str::trim).filter(|s|num(&Value::String((*s).to_owned())).is_some()).map(str::to_owned);
 let last=text("last")?;
 if num(&Value::String(last.clone()))? <= 0.0 {return None}
 Some(Ticker{last,open:text("open24h")?,high:text("high24h")?,low:text("low24h")?,
  base_volume:num(&row["volCcy24h"]).unwrap_or(f64::NAN),
  time:row["ts"].as_str().and_then(|t|t.parse().ok()).or_else(||row["ts"].as_i64()).unwrap_or(0)})
}

/// `market/tickers` 的整张表，键是 OKX 的品种号（`BTC-USDT-SWAP`）。
pub fn parse_tickers(body:&Value)->HashMap<String,Ticker> {
 rows(body).iter().filter_map(|row|Some((row["instId"].as_str()?.to_ascii_uppercase(),ticker_row(row)?))).collect()
}

/// 近 24 小时的成交均价：`Σ volCcyQuote / Σ volCcy`，两列都是 OKX 自己按笔累出来的。
/// 没有成交（新上、停牌）就给不出，给 `None`。
pub fn vwap(body:&Value)->Option<f64> {
 let (mut quote,mut base)=(0.0,0.0);
 for row in rows(body) {
  let (Some(b),Some(q))=(num(&row[6]),num(&row[7])) else {continue};
  if b>0.0&&q>=0.0 {base+=b;quote+=q}
 }
 (base>0.0&&quote>0.0).then(||quote/base)
}

fn decimals(s:&str)->usize {s.split_once('.').map_or(0,|(_,f)|f.len())}

/// 币安 `/fapi/v1/ticker/24hr` 的形状，手机那头拿同一个解码器解。
///
/// `quoteVolume`（顶栏「额」）= OKX 自己的滚动 24h 币量 × 近 24h 成交均价。
/// 为什么不直接拿「币量 × 最新价」：一天里价格走了 5% 就差 5%，网关注释里说过不能这么顶；
/// 成交均价是 OKX 自己逐根 K 线的 `volCcyQuote / volCcy` 累出来的，换算出来和
/// 「把这一天每一笔的成交额加起来」是一回事。换算不出来就是空串，手机显示「—」。
pub fn ticker_payload(symbol:&str,t:&Ticker,vwap:Option<f64>)->Value {
 let last:f64=t.last.parse().unwrap_or(f64::NAN);
 let open:f64=t.open.parse().unwrap_or(f64::NAN);
 let places=decimals(&t.last).max(decimals(&t.open));
 let (change,percent)=if open.is_finite()&&open>0.0&&last.is_finite() {
  (format!("{:.*}",places,last-open),format!("{:.3}",(last-open)/open*100.0))
 } else {(String::new(),String::new())};
 let quote=match vwap {
  Some(p) if t.base_volume.is_finite()&&t.base_volume>=0.0=>format!("{:.2}",t.base_volume*p),
  _=>String::new(),
 };
 let volume=if t.base_volume.is_finite(){t.base_volume.to_string()}else{String::new()};
 serde_json::json!({"source":"okx","ticker":{
  "symbol":symbol,"lastPrice":t.last,"priceChange":change,"priceChangePercent":percent,
  "openPrice":t.open,"highPrice":t.high,"lowPrice":t.low,
  "volume":volume,"quoteVolume":quote,"closeTime":t.time}})
}

async fn ticker_raw(inst:&str)->Result<Ticker> {
 static REFRESH:OnceLock<tokio::sync::Mutex<()>>=OnceLock::new();
 let table=match tickers_cache().fresh(TICKER_TTL) {
  Some(table)=>table,
  None=>{
   // 同一时刻只让一个请求去刷表，其余的等它刷完直接读——冷启动时二十几只一起到。
   let _guard=REFRESH.get_or_init(||tokio::sync::Mutex::new(())).lock().await;
   match tickers_cache().fresh(TICKER_TTL) {
    Some(table)=>table,
    None=>match get_json(TICKERS_URL).await {
     Ok(body)=>{
      let table=parse_tickers(&body);
      if table.is_empty() {tickers_cache().fresh(TICKER_MAX_AGE).ok_or_else(ApiError::missing)?}
      else {tickers_cache().store(table)}
     },
     Err(e)=>tickers_cache().fresh(TICKER_MAX_AGE).ok_or(e)?,
    },
   }
  },
 };
 table.get(inst).cloned().ok_or_else(ApiError::missing)
}
/// K 线接口每 IP 每 2 秒 40 次；留余量按每秒 18 次放行。
async fn candle_pace() {
 static SENT:OnceLock<tokio::sync::Mutex<VecDeque<Instant>>>=OnceLock::new();
 let mut sent=SENT.get_or_init(||tokio::sync::Mutex::new(VecDeque::new())).lock().await;
 let window=Duration::from_secs(1);
 while sent.front().is_some_and(|t|t.elapsed()>=window) {sent.pop_front();}
 if sent.len()>=18 && let Some(first)=sent.front().copied() {
  tokio::time::sleep(window.saturating_sub(first.elapsed())).await;
  sent.pop_front();
 }
 sent.push_back(Instant::now());
}
async fn vwap_for(inst:&str)->Option<f64> {
 if let Some(p)=vwap_cache().get(inst,VWAP_TTL) {return Some(p)}
 candle_pace().await;
 match get_json(&format!("{CANDLES_URL}{inst}")).await.ok().and_then(|b|vwap(&b)) {
  Some(p)=>{vwap_cache().put(inst,p);Some(p)},
  None=>vwap_cache().get(inst,VWAP_MAX_AGE),
 }
}

/// 一只永续的 24h 行情（带 USDT 成交额）。`symbol` 是币安写法（`BTCUSDT`）。
pub async fn ticker(symbol:&str)->Result<Value> {
 let inst=instrument(symbol);
 let (t,p)=tokio::join!(ticker_raw(&inst),vwap_for(&inst));
 Ok(ticker_payload(&symbol.to_ascii_uppercase(),&t?,p))
}

// -------------------------------------------------------------------- 持仓量历史

/// 官方文档（Trading Statistics › Get contract open interest history）：
/// 每行 `[ts, oi(张), oiCcy(币), oiUsd]`，新的在前；`end` / `begin` 都是开区间；
/// 一页最多 100 行；限速每 IP 每 2 秒 5 次。能回溯多远看周期：5m 约四五天、1H 约两个月、
/// 1D 两年以上。更早就是没有——不拿币安归档去补（不混源）。
const OI_HISTORY_URL:&str="https://www.okx.com/api/v5/rubik/stat/contracts/open-interest-history";
const OI_PAGE:usize=100;
/// 和币安 `openInterestHist` 一样一次最多 500 行，手机那头的翻页逻辑一行不用改。
pub const OI_HISTORY_MAX:usize=500;
/// 最新那一页一分钟内共用；更早的页不会再变，存半小时。
const OI_LATEST_TTL:Duration=Duration::from_secs(60);
const OI_PAST_TTL:Duration=Duration::from_secs(1800);

fn oi_history_cache()->&'static Slots<Arc<Vec<OiPoint>>> {static C:OnceLock<Slots<Arc<Vec<OiPoint>>>>=OnceLock::new();C.get_or_init(Slots::new)}

/// 一条持仓量：时间、币的个数（和币安 `sumOpenInterest` 同一个单位）、美元名义值。
#[derive(Clone,Copy,Debug,PartialEq)]
pub struct OiPoint {pub time:i64,pub coins:f64,pub usd:Option<f64>}

/// 手机用币安的周期写法问；翻成 OKX 的。6h / 12h / 1d 要 `utc` 那一族：
/// 不带后缀的是按香港时间开盘，和币安（UTC）的桶头差八小时。
pub fn okx_period(period:&str)->Option<&'static str> {
 Some(match period {
  "5m"=>"5m","15m"=>"15m","30m"=>"30m","1h"=>"1H","2h"=>"2H","4h"=>"4H",
  "6h"=>"6Hutc","12h"=>"12Hutc","1d"=>"1Dutc",
  _=>return None,
 })
}

pub fn parse_oi_history(body:&Value)->Vec<OiPoint> {
 rows(body).iter().filter_map(|row|{
  let time=row[0].as_str().and_then(|t|t.parse().ok()).or_else(||row[0].as_i64())?;
  let coins=num(&row[2])?;
  (time>0&&coins>=0.0).then(||OiPoint{time,coins,usd:num(&row[3])})
 }).collect()
}

pub fn oi_history_payload(symbol:&str,period:&str,points:&[OiPoint])->Value {
 let rows:Vec<Value>=points.iter().map(|p|serde_json::json!([p.time,p.coins,p.usd])).collect();
 serde_json::json!({"source":"okx","symbol":symbol,"period":period,"rows":rows})
}

/// 每 IP 每 2 秒 5 次（留一点余量按 2.1 秒算）。几台手机同时翻历史时在这里排队，
/// 而不是一起撞上限把整段都变成 429。
async fn pace() {
 static LAST:OnceLock<tokio::sync::Mutex<VecDeque<Instant>>>=OnceLock::new();
 let mut sent=LAST.get_or_init(||tokio::sync::Mutex::new(VecDeque::new())).lock().await;
 let window=Duration::from_millis(2100);
 while sent.front().is_some_and(|t|t.elapsed()>=window) {sent.pop_front();}
 if sent.len()>=5 && let Some(first)=sent.front().copied() {
  tokio::time::sleep(window.saturating_sub(first.elapsed())).await;
  sent.pop_front();
 }
 sent.push_back(Instant::now());
}

/// 不晚于 `end_time`（含）的最多 `limit` 条，按时间升序。`end_time` 缺省就是「到现在」。
pub async fn oi_history(symbol:&str,period:&str,limit:usize,end_time:Option<i64>,now:i64)->Result<Arc<Vec<OiPoint>>> {
 let bar=okx_period(period).ok_or(ApiError::bad("unsupported_period"))?;
 let inst=instrument(symbol);
 let limit=limit.clamp(1,OI_HISTORY_MAX);
 // 最近几分钟以内的 `end_time` 都当「最新一页」：手机每次给的都是自己的 now，按毫秒当键就永远不中。
 let latest=end_time.is_none_or(|t|t>=now-300_000);
 let key=if latest {format!("{inst}|{bar}|{limit}|latest")} else {format!("{inst}|{bar}|{limit}|{}",end_time.unwrap_or(0))};
 if let Some(hit)=oi_history_cache().get(&key,if latest {OI_LATEST_TTL} else {OI_PAST_TTL}) {
  return Ok(Arc::new(hit.iter().copied().filter(|p|end_time.is_none_or(|t|p.time<=t)).collect()))
 }
 let mut out:Vec<OiPoint>=Vec::with_capacity(limit);
 // 币安的 endTime 含端点，OKX 的 end 不含：加一毫秒。最新一页不带 end。
 let mut cursor=if latest {None} else {end_time.map(|t|t+1)};
 while out.len()<limit {
  pace().await;
  let mut url=format!("{OI_HISTORY_URL}?instId={inst}&period={bar}&limit={OI_PAGE}");
  if let Some(end)=cursor {url.push_str(&format!("&end={end}"))}
  let page=parse_oi_history(&get_json(&url).await?);
  let Some(oldest)=page.iter().map(|p|p.time).min() else {break};
  let full=page.len()>=OI_PAGE;
  out.extend(page);
  if !full {break}
  cursor=Some(oldest);
 }
 out.sort_by_key(|p|p.time);
 out.dedup_by_key(|p|p.time);
 if out.len()>limit {out.drain(..out.len()-limit);}
 let out=Arc::new(out);
 oi_history_cache().put(&key,out.clone());
 Ok(Arc::new(out.iter().copied().filter(|p|end_time.is_none_or(|t|p.time<=t)).collect()))
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

 #[test]
 fn ticker_turnover_is_okx_coins_times_okx_average_price() {
  let table=parse_tickers(&json!({"code":"0","data":[{"instId":"BTC-USDT-SWAP","last":"85701.6","open24h":"86048.7",
   "high24h":"87245","low24h":"85406","volCcy24h":"72722.3712","vol24h":"7272237.12","ts":"1790162237169"}]}));
  let ticker=table["BTC-USDT-SWAP"].clone();
  let candles=json!({"code":"0","data":[
   ["1790162100000","85717.9","85722","85701.6","85701.6","3676.49","36.7649","3151022.15994","0"],
   ["1790161800000","85821.6","85821.7","85666.7","85717.8","27164.55","271.6455","23287754.86518","1"],
   ["1790161500000","1","1","1","1","0","0","0","1"]]});
  let average=vwap(&candles).unwrap();
  assert!((average-(3151022.15994+23287754.86518)/(36.7649+271.6455)).abs()<1e-9);
  let body=ticker_payload("BTCUSDT",&ticker,Some(average));
  let t=&body["ticker"];
  assert_eq!(body["source"],"okx");
  assert_eq!(t["lastPrice"],"85701.6");
  assert_eq!(t["openPrice"],"86048.7");
  assert_eq!(t["priceChange"],"-347.1");
  assert_eq!(t["priceChangePercent"],"-0.403");
  assert_eq!(t["highPrice"],"87245");
  assert_eq!(t["closeTime"],1_790_162_237_169_i64);
  let quote:f64=t["quoteVolume"].as_str().unwrap().parse().unwrap();
  assert!((quote-72722.3712*average).abs()<0.01);
  // 换算不出来就留空，绝不拿「币量 × 最新价」去顶。
  assert_eq!(ticker_payload("BTCUSDT",&ticker,None)["ticker"]["quoteVolume"],"");
  assert_eq!(vwap(&json!({"code":"0","data":[]})),None);
 }
 #[test]
 fn ticker_without_a_price_is_not_a_ticker() {
  assert!(parse_tickers(&json!({"code":"50011","data":[],"msg":"Too Many Requests"})).is_empty());
  let table=parse_tickers(&json!({"code":"0","data":[
   {"instId":"ETH-USDT-SWAP","last":"","open24h":"1","high24h":"1","low24h":"1"},
   {"instId":"SOL-USDT-SWAP","last":"150","open24h":"","high24h":"1","low24h":"1"},
   {"last":"1","open24h":"1","high24h":"1","low24h":"1"},
   {"instId":"xrp-usdt-swap","last":"2.1","open24h":"2","high24h":"2.2","low24h":"1.9","volCcy24h":"","ts":"1"}]}));
  assert_eq!(table.keys().collect::<Vec<_>>(),vec!["XRP-USDT-SWAP"]);
  assert!(table["XRP-USDT-SWAP"].base_volume.is_nan());
 }
 #[test]
 fn oi_history_keeps_coins_and_maps_binance_periods() {
  let rows=parse_oi_history(&json!({"code":"0","data":[
   ["1790162100000","3085475.63","30854.7563","2644808000.52"],
   ["1790161800000","3084985.49","30849.8549",""],
   ["bad","1","1","1"]]}));
  assert_eq!(rows,vec![OiPoint{time:1_790_162_100_000,coins:30854.7563,usd:Some(2644808000.52)},
   OiPoint{time:1_790_161_800_000,coins:30849.8549,usd:None}]);
  assert_eq!(oi_history_payload("BTCUSDT","5m",&rows[..1]),
   json!({"source":"okx","symbol":"BTCUSDT","period":"5m","rows":[[1_790_162_100_000_i64,30854.7563,2644808000.52]]}));
  assert_eq!(okx_period("1h"),Some("1H"));
  assert_eq!(okx_period("1d"),Some("1Dutc"));
  assert_eq!(okx_period("12h"),Some("12Hutc"));
  assert_eq!(okx_period("1m"),None);
  assert_eq!(okx_period("1w"),None);
 }
}
