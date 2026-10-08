//! OKX 在服务端的那一截：OKX 这一家自己的数据（2026-10-08 起 OKX 是和币安、Bybit 平起平坐的一家，
//! 用户在 app 里搜 OKX 的永续、加自选、看 K 线、设提醒；不再是币安永续在网关线路上的替身）。
//!
//! 品种只收 USDT 线性永续。看盘键是币安形状的 `BTCUSDT`（`okx/usd_m/BTCUSDT`，同一只币和币安只差 venue），
//! OKX 的 `instId` 是 `BTC-USDT-SWAP`：两者的互译只在这里（[`inst_id`] / [`key_of`]）。
//!
//! - `GET /v1/market/raw/<path>?source=okx&…`：公开行情原样透传（[`raw`]，白名单见 [`ttl_of`]）；
//! - `/v1/market/open-interest?source=okx`：整表抓、按品种答（[`open_interest`]）；
//! - `/v1/market/funding?source=okx`：整张资金费率表（[`funding`]）；
//! - `/v1/market/open-interest/history?source=okx`：持仓量历史（[`oi_history`]）；
//! - `candles`：提醒补缺用的原生 K 线（`history-candles`）；
//! - `relay`：`/v1/market/ws/okx` 中继的上行白名单（`?endpoint=business` 连 K 线所在的 business 端点）；
//! - `orderflow`：主力订单流的品种表；`alerts`：提醒评估的 1 分钟 K 线来源。
//!
//! 这一家的全部 REST 出站都排 [`PACER`]。全是 OKX 自己的数，不拿币安的顶（不混源）。
pub mod alerts;
pub mod orderflow;
pub mod relay;
use super::outbound::{self,Answers,Lane,Pacer,Reply,Upstream,refuse};
use super::{Bar,Fut};
use crate::error::{ApiError,Result};
use crate::market_meta::{Cache,LIVE_TTL,OpenInterest,num,rows};
use axum::http::StatusCode;
use axum::response::{IntoResponse,Response};
use serde_json::Value;
use std::collections::HashMap;
use std::sync::{Arc,Mutex,OnceLock};
use std::time::{Duration,Instant};

pub const SOURCE:&str="okx";
pub const REST:&str="https://www.okx.com";
pub const HOSTS:&[&str]=&["www.okx.com"];
/// 公开推送：行情、成交、盘口、标记价、资金费率。
pub const WS_PUBLIC:&str="wss://ws.okx.com:8443/ws/v5/public";
/// K 线频道（`candle*`）只在 business 端点上。
pub const WS_BUSINESS:&str="wss://ws.okx.com:8443/ws/v5/business";

// ------------------------------------------------------------------ 出站节拍

/// 官方文档（2026-09 现行）的单接口限速都是「每 IP 每 2 秒 N 次」，按 2.1 秒、略少几次留余量；
/// 全家另有 50 ms 的最小间隔（每秒 20 次封顶）。`tickers` 要排在 `ticker` 前面（前缀匹配）。
const LANES:&[Lane]=&[
 Lane{prefix:"api/v5/rubik/stat/contracts/open-interest-history",count:5,window:Duration::from_millis(2100)},
 Lane{prefix:"api/v5/market/history-candles",count:18,window:Duration::from_millis(2100)},
 Lane{prefix:"api/v5/market/candles",count:36,window:Duration::from_millis(2100)},
 Lane{prefix:"api/v5/market/tickers",count:18,window:Duration::from_millis(2100)},
 Lane{prefix:"api/v5/market/ticker",count:18,window:Duration::from_millis(2100)},
 Lane{prefix:"api/v5/public/instruments",count:18,window:Duration::from_millis(2100)},
 Lane{prefix:"api/v5/public/funding-rate",count:9,window:Duration::from_millis(2100)},
 Lane{prefix:"api/v5/public/open-interest",count:18,window:Duration::from_millis(2100)},
 Lane{prefix:"api/v5/public/mark-price",count:9,window:Duration::from_millis(2100)},
];
/// 这一家唯一的出站节拍：透传、持仓量 / 费率 / 持仓量历史、补缺 K 线、订单流品种表都排它。
pub static PACER:Pacer=Pacer::new(Duration::from_millis(50),Duration::from_secs(8),LANES);

async fn get(path:&str,query:&[(String,String)])->std::result::Result<Reply,Upstream> {
 outbound::send(&PACER,&format!("{REST}/{path}"),query,None,1).await
}
async fn get_json(path:&str,query:&[(&str,&str)])->std::result::Result<Value,Upstream> {
 let query:Vec<(String,String)>=query.iter().map(|(k,v)|(k.to_string(),v.to_string())).collect();
 outbound::json_of(&get(path,&query).await?)
}

// ------------------------------------------------------------------ 代号

/// 看盘键 `BTCUSDT` 合不合规：大写字母数字，以 USDT 结尾、前面不空。
pub fn symbol_ok(key:&str)->bool {super::upper_alnum(key,5..=40)&&key.strip_suffix("USDT").is_some_and(|b|!b.is_empty())}
/// `BTCUSDT` → `BTC-USDT-SWAP`。
pub fn inst_id(key:&str)->Option<String> {
 symbol_ok(key).then(||format!("{}-USDT-SWAP",&key[..key.len()-4]))
}
/// `BTC-USDT-SWAP` → `BTCUSDT`；不是 USDT 线性永续的给 `None`。
pub fn key_of(inst:&str)->Option<String> {
 let base=inst.strip_suffix("-USDT-SWAP")?;
 let key=format!("{base}USDT");
 (!base.is_empty()&&!base.contains('-')&&symbol_ok(&key)).then_some(key)
}
/// 透传里的 `instId`：只收 USDT 线性永续（`BASE-USDT-SWAP`）。
fn inst_ok(inst:&str)->bool {key_of(inst).is_some()}

// ------------------------------------------------------------------ REST 透传

/// 周期写法（K 线 `bar`）：6 小时以上用 `utc` 那一族，和币安（UTC）的桶头对齐。
const BARS:[&str;13]=["1m","3m","5m","15m","30m","1H","2H","4H","6Hutc","12Hutc","1Dutc","1Wutc","1Mutc"];

fn param<'a>(query:&'a [(String,String)],key:&str)->Option<&'a str> {query.iter().find(|(k,_)|k==key).map(|(_,v)|v.as_str())}

/// 放行的路径与这条答案能给后来者用多久。品种表变得慢；带 `after` 的历史页不会再变；
/// 最新一页 K 线与行情要新鲜。
fn ttl_of(path:&str,query:&[(String,String)])->Option<Duration> {
 let paged=param(query,"after").is_some();
 Some(match path {
  "api/v5/public/instruments"=>Duration::from_secs(60),
  "api/v5/market/tickers"=>Duration::from_secs(2),
  "api/v5/market/ticker"|"api/v5/public/mark-price"=>Duration::from_secs(1),
  "api/v5/market/candles"|"api/v5/market/history-candles"=>if paged {Duration::from_secs(60)} else {Duration::from_secs(2)},
  "api/v5/public/funding-rate"=>Duration::from_secs(10),
  "api/v5/public/open-interest"=>Duration::from_secs(3),
  _=>return None,
 })
}
fn digits(v:&str)->bool {(1..=20).contains(&v.len())&&v.bytes().all(|b|b.is_ascii_digit())}
/// 查询键与值的白名单：只看 USDT 线性永续（`instType=SWAP`）。
fn query_ok(key:&str,value:&str)->bool {
 match key {
  "instType"=>value=="SWAP",
  "instId"=>inst_ok(value),
  "instFamily"|"uly"=>value.strip_suffix("-USDT").is_some_and(|b|super::upper_alnum(b,1..=30)),
  "bar"=>BARS.contains(&value),
  "after"|"before"|"limit"=>digits(value),
  _=>false,
 }
}
/// 200 但 `code` 不是 `"0"`（OKX 限流时也可能这么答）的不留给后来者。
fn okx_ok(reply:&Reply)->bool {
 #[derive(serde::Deserialize)] struct Code {code:String}
 serde_json::from_slice::<Code>(&reply.body).is_ok_and(|c|c.code=="0")
}
static ANSWERS:Answers=Answers::new();

pub async fn raw(path:&str,query:&[(String,String)])->Response {
 let Some(ttl)=ttl_of(path,query) else {return refuse(StatusCode::NOT_FOUND,"unsupported_path")};
 let Some(forward)=outbound::forward(query,query_ok) else {return refuse(StatusCode::BAD_REQUEST,"unsupported_query")};
 outbound::pass(ANSWERS.get(format!("{path}?{forward:?}"),ttl,okx_ok,||get(path,&forward)).await)
}

// ------------------------------------------------------------------ K 线（提醒补缺）

fn bar_of(step:i64)->Option<&'static str> {
 Some(match step {60=>"1m",180=>"3m",300=>"5m",900=>"15m",1800=>"30m",3600=>"1H",7200=>"2H",14_400=>"4H",21_600=>"6Hutc",43_200=>"12Hutc",86_400=>"1Dutc",_=>return None})
}
/// 官方文档（Market Data › Get candlesticks）：`market/candles` 只给最新的 1440 根，一页最多 300 行；
/// 更早的在 `history-candles`（一页最多 100 行），它是给更早的历史用的，不保证覆盖最新的那一段。
const RECENT_BARS:i64=1440;
const RECENT_PAGE:usize=300;
const HISTORY_PAGE:usize=100;

/// 往回翻的这一页（`after=cursor`，要的是比 `cursor` 早的那些）该问哪条接口、一页几根：
/// `cursor` 还在最新 1440 根之内就问 `market/candles`，翻出去了才问 `history-candles`。`now` 是毫秒。
fn page_source(cursor:i64,step:i64,now:i64)->(&'static str,usize) {
 let floor=now.div_euclid(step*1000)*step*1000-(RECENT_BARS-1)*step*1000;
 if cursor>floor {("api/v5/market/candles",RECENT_PAGE)} else {("api/v5/market/history-candles",HISTORY_PAGE)}
}

/// 一页 K 线：每行 `[ts,o,h,l,c,vol,volCcy,volCcyQuote,confirm]`，新的在前。量取 `volCcy`（币的个数）。
pub fn parse_candles(body:&Value)->Vec<Bar> {
 rows(body).iter().filter_map(|row|{
  let n=|i:usize|num(&row[i]);
  let bar=Bar{open_time:row[0].as_str()?.parse().ok()?,open:n(1)?,high:n(2)?,low:n(3)?,close:n(4)?,volume:n(6).unwrap_or(0.0)};
  bar.sane().then_some(bar)
 }).collect()
}

/// `[start, end)`（秒）里的 K 线，升序。`after` 是「比这一刻早的」、`before` 是「比这一刻晚的」，两端都不含；
/// 一页给的是窗口里最新的那些（新的在前），所以从 `end` 往回翻：提醒补缺的窗口（最近几分钟到一小时）
/// 落在最新 1440 根之内，走 `market/candles`；翻出去的更早那段才走 `history-candles`（见 [`page_source`]）。
pub async fn candles(key:&str,step:i64,start:i64,end:i64)->std::result::Result<Vec<Bar>,Upstream> {
 let (Some(inst),Some(bar))=(inst_id(key),bar_of(step)) else {return Err(Upstream::Rejected(400))};
 let (from,until)=(start*1000,end*1000);
 let now=chrono::Utc::now().timestamp_millis();
 let mut out:Vec<Bar>=Vec::new();
 let mut cursor=until;
 for _ in 0..64 {
  if cursor<=from {break}
  let (path,page_size)=page_source(cursor,step,now);
  let (after,before,limit)=(cursor.to_string(),(from-1).to_string(),page_size.to_string());
  let page=parse_candles(&get_json(path,&[("instId",&inst),("bar",bar),("after",&after),("before",&before),("limit",&limit)]).await?);
  let Some(oldest)=page.iter().map(|b|b.open_time).min() else {
   // 最新那段问空了不等于更早也没有：翻进历史接口再问一次。
   if path=="api/v5/market/candles" {let floor=now.div_euclid(step*1000)*step*1000-(RECENT_BARS-1)*step*1000;if floor<cursor&&floor>from {cursor=floor;continue}}
   break
  };
  let full=page.len()>=page_size;
  out.extend(page.into_iter().filter(|b|b.open_time>=from&&b.open_time<until));
  if !full||oldest>=cursor {break}
  cursor=oldest;
 }
 out.sort_by_key(|b|b.open_time);out.dedup_by_key(|b|b.open_time);
 Ok(out)
}

// ------------------------------------------------------------------ 资金费率

/// 官方文档（Public Data › Get funding rate）：`instId=ANY` 一次返回全部永续的当期费率。
/// 整张表缓存着答所有手机，一分钟最多问两次。
const FUNDING_TTL:Duration=Duration::from_secs(30);
/// 十分钟没刷成功就不再答：再旧，「下次结算」可能已经过去了。
pub const FUNDING_MAX_AGE:Duration=Duration::from_secs(600);
/// 整张表一起抓。十五分钟没刷成功就不再拿它答题：持仓量是分钟级的量。
pub const OI_MAX_AGE:Duration=Duration::from_secs(900);

fn oi_cache()->&'static Cache<HashMap<String,OpenInterest>> {static C:OnceLock<Cache<HashMap<String,OpenInterest>>>=OnceLock::new();C.get_or_init(Cache::new)}
fn funding_cache()->&'static Cache<Vec<Funding>> {static C:OnceLock<Cache<Vec<Funding>>>=OnceLock::new();C.get_or_init(Cache::new)}

/// 一只永续的当期资金费率。`symbol` 是看盘键（`BTCUSDT`）。
#[derive(Clone,Debug,PartialEq)]
pub struct Funding {pub symbol:String,pub rate:f64,pub next_funding_time:i64}

/// `funding-rate?instId=ANY` 的一页。`fundingRate` 是下一次结算（`fundingTime`）要用的预测费率；
/// OKX 自己的 `nextFundingTime` 是再下一期，不用它。只留 USDT 线性永续。
pub fn parse_funding(body:&Value)->Vec<Funding> {
 let mut out:Vec<Funding>=rows(body).iter().filter_map(|row|{
  let symbol=key_of(&row["instId"].as_str()?.to_ascii_uppercase())?;
  let rate=num(&row["fundingRate"])?;
  let time=row["fundingTime"].as_str().and_then(|t|t.parse().ok()).or_else(||row["fundingTime"].as_i64())?;
  (time>0).then_some(Funding{symbol,rate,next_funding_time:time})
 }).collect();
 out.sort_by(|a,b|a.symbol.cmp(&b.symbol));
 out
}

pub fn funding_payload(source:&str,table:&[Funding])->Value {
 let rows:Vec<Value>=table.iter().map(|f|serde_json::json!({"symbol":f.symbol,"rate":f.rate,"nextFundingTime":f.next_funding_time})).collect();
 serde_json::json!({"source":source,"rows":rows})
}

pub async fn funding()->Result<Arc<Vec<Funding>>> {
 // 单飞：过期时同时到的请求只出站一次（见 `Cache::refresh`）。
 let fresh=funding_cache().refresh(FUNDING_TTL,||async {
  let table=parse_funding(&get_json("api/v5/public/funding-rate",&[("instId","ANY")]).await.map_err(outbound::api_error)?);
  // 上游回了个空表（换信封、限速回 code≠0）不当新表存：别拿一张空表盖掉好表。
  if table.is_empty() {return Err(ApiError::missing())}
  Ok(table)
 }).await;
 match fresh {
  Ok(table)=>Ok(table),
  Err(e)=>funding_cache().fresh(FUNDING_MAX_AGE).ok_or(e),
 }
}

// ------------------------------------------------------------------ 持仓量

/// OKX 一次给全部永续：`oiCcy` 是币的个数，`oiUsd` 是美元名义值。键是 `instId`。
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

pub async fn open_interest(key:&str)->Result<OpenInterest> {
 let inst=inst_id(key).ok_or_else(ApiError::missing)?;
 let table=match oi_cache().refresh(LIVE_TTL,||async {
  get_json("api/v5/public/open-interest",&[("instType","SWAP")]).await.map(|body|parse_oi(&body)).map_err(outbound::api_error)
 }).await {
  Ok(table)=>table,
  Err(e)=>oi_cache().fresh(OI_MAX_AGE).ok_or(e)?,
 };
 table.get(&inst).copied().ok_or_else(ApiError::missing)
}

// ------------------------------------------------------------------ 持仓量历史

/// 官方文档（Trading Statistics › Get contract open interest history）：
/// 每行 `[ts, oi(张), oiCcy(币), oiUsd]`，新的在前；`end` / `begin` 都是开区间；
/// 一页最多 100 行；限速每 IP 每 2 秒 5 次（[`LANES`] 第一条）。能回溯多远看周期：5m 约四五天、
/// 1H 约两个月、1D 两年以上。更早就是没有——不拿币安归档去补（不混源）。
const OI_HISTORY_PATH:&str="api/v5/rubik/stat/contracts/open-interest-history";
const OI_PAGE:usize=100;
/// 和币安 `openInterestHist` 一样一次最多 500 行，手机那头的翻页逻辑一行不用改。
pub const OI_HISTORY_MAX:usize=500;
/// 最新那一页一分钟内共用；更早的页不会再变，存半小时。
const OI_LATEST_TTL:Duration=Duration::from_secs(60);
const OI_PAST_TTL:Duration=Duration::from_secs(1800);

/// 按键存、按时限取的小表（持仓量历史页按品种和参数各存一份）。
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
 serde_json::json!({"source":SOURCE,"symbol":symbol,"period":period,"rows":rows})
}

/// 不晚于 `end_time`（含）的最多 `limit` 条，按时间升序。`end_time` 缺省就是「到现在」。
pub async fn oi_history(key:&str,period:&str,limit:usize,end_time:Option<i64>,now:i64)->Result<Arc<Vec<OiPoint>>> {
 let inst=inst_id(key).ok_or_else(ApiError::missing)?;
 let bar=okx_period(period).ok_or(ApiError::bad("unsupported_period"))?;
 let limit=limit.clamp(1,OI_HISTORY_MAX);
 // 最近几分钟以内的 `end_time` 都当「最新一页」：手机每次给的都是自己的 now，按毫秒当键就永远不中。
 let latest=end_time.is_none_or(|t|t>=now-300_000);
 let cache_key=if latest {format!("{inst}|{bar}|{limit}|latest")} else {format!("{inst}|{bar}|{limit}|{}",end_time.unwrap_or(0))};
 if let Some(hit)=oi_history_cache().get(&cache_key,if latest {OI_LATEST_TTL} else {OI_PAST_TTL}) {
  return Ok(Arc::new(hit.iter().copied().filter(|p|end_time.is_none_or(|t|p.time<=t)).collect()))
 }
 let mut out:Vec<OiPoint>=Vec::with_capacity(limit);
 // 币安的 endTime 含端点，OKX 的 end 不含：加一毫秒。最新一页不带 end。
 let mut cursor=if latest {None} else {end_time.map(|t|t+1)};
 let page_size=OI_PAGE.to_string();
 while out.len()<limit {
  let end=cursor.map(|c|c.to_string());
  let mut query=vec![("instId",inst.as_str()),("period",bar),("limit",page_size.as_str())];
  if let Some(end)=end.as_deref() {query.push(("end",end))}
  let page=parse_oi_history(&get_json(OI_HISTORY_PATH,&query).await.map_err(outbound::api_error)?);
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
 oi_history_cache().put(&cache_key,out.clone());
 Ok(Arc::new(out.iter().copied().filter(|p|end_time.is_none_or(|t|p.time<=t)).collect()))
}

/// `/v1/market/open-interest/history?source=okx`：参数照币安 `openInterestHist`（`period` / `limit` ≤ 500 /
/// `endTime` 含端点），答复 `{"source":"okx","rows":[[毫秒, 币的个数, 美元名义值|null], …]}`，时间升序。
async fn oi_history_route(query:&[(String,String)])->Response {
 use super::{bad,query_param,symbol_param};
 let Some(symbol)=symbol_param(query).map(str::to_ascii_uppercase).filter(|s|symbol_ok(s)) else {return bad("invalid_symbol")};
 let Some(period)=query_param(query,"period").filter(|p|okx_period(p).is_some()) else {return bad("unsupported_period")};
 let limit=match query_param(query,"limit") {None=>OI_HISTORY_MAX,Some(v)=>match v.parse::<usize>() {Ok(n) if n>0=>n,_=>return bad("invalid_limit")}};
 let end=match query_param(query,"endTime") {None=>None,Some(v)=>match v.parse::<i64>() {Ok(t) if t>0=>Some(t),_=>return bad("invalid_end_time")}};
 let now=chrono::Utc::now().timestamp_millis();
 match oi_history(&symbol,period,limit,end,now).await {
  Ok(rows)=>crate::envelope(oi_history_payload(&symbol,period,&rows)).into_response(),
  Err(e)=>e.into_response(),
 }
}

// ------------------------------------------------------------------ 注册表里的这一家

pub struct Okx;
pub static OKX:Okx=Okx;

impl super::Venue for Okx {
 fn source(&self)->&'static str {SOURCE}
 fn short_name(&self)->&'static str {"OKX"}
 fn market(&self)->&'static str {"usd_m"}
 fn market_key(&self)->&'static str {"okx/usd_m"}
 fn symbol_ok(&self,symbol:&str)->bool {symbol_ok(symbol)}
 fn webhook_name(&self,symbol:&str)->String {super::without_usdt(symbol).to_owned()}
 fn pacer(&self)->Option<&'static Pacer> {Some(&PACER)}
 fn hosts(&self)->&'static [&'static str] {HOSTS}
 fn raw<'a>(&'a self,path:&'a str,query:&'a [(String,String)])->Fut<'a,Response> {Box::pin(raw(path,query))}
 fn candles<'a>(&'a self,symbol:&'a str,step:i64,start:i64,end:i64)->Fut<'a,std::result::Result<Vec<Bar>,Upstream>> {Box::pin(candles(symbol,step,start,end))}
 fn open_interest<'a>(&'a self,symbol:&'a str)->Option<Fut<'a,Result<OpenInterest>>> {Some(Box::pin(open_interest(symbol)))}
 fn funding(&self)->Option<Fut<'static,Result<Value>>> {Some(Box::pin(async {funding().await.map(|t|funding_payload(SOURCE,&t))}))}
 fn oi_history<'a>(&'a self,query:&'a [(String,String)])->Option<Fut<'a,Response>> {Some(Box::pin(oi_history_route(query)))}
 fn alert_feed(&self)->Option<&'static dyn crate::alerts::KlineFeed> {Some(&alerts::FEED)}
}

#[cfg(test)]
mod tests {
 use super::*;
 use serde_json::json;

 fn q(pairs:&[(&str,&str)])->Vec<(String,String)> {pairs.iter().map(|(k,v)|(k.to_string(),v.to_string())).collect()}

 #[test]
 fn okx_swaps_parse_with_their_own_notional() {
  let body=json!({"code":"0","data":[{"instId":"BTC-USDT-SWAP","oi":"1084317","oiCcy":"10843.17","oiUsd":"832000000","ts":"1789661435379"}]});
  let table=parse_oi(&body);
  let oi=table["BTC-USDT-SWAP"];
  assert_eq!(oi.open_interest,10_843.17);
  assert_eq!(oi.value,Some(832_000_000.0));
  assert_eq!(oi.time,1_789_661_435_379);
 }
 /// 夹具照官方文档（Public Data › Get funding rate 的示例答复）写。
 #[test]
 fn okx_funding_uses_the_upcoming_settlement_and_only_usdt_swaps() {
  let body=json!({"code":"0","data":[
   {"instId":"BTC-USDT-SWAP","instType":"SWAP","fundingRate":"0.0000182221218054","fundingTime":"1743609600000","nextFundingTime":"1743638400000"},
   {"instId":"ETH-USDC-SWAP","instType":"SWAP","fundingRate":"-0.0001","fundingTime":"1743609600000","nextFundingTime":"1743638400000"},
   {"instId":"BTC-USD-SWAP","instType":"SWAP","fundingRate":"0.0001","fundingTime":"1743609600000"},
   {"instId":"XAU-USDT-SWAP","instType":"SWAP","fundingRate":"","fundingTime":"1743609600000"},
   {"instId":"SOL-USDT-SWAP","instType":"SWAP","fundingRate":"0.0002","fundingTime":""}]});
  let table=parse_funding(&body);
  assert_eq!(table,vec![Funding{symbol:"BTCUSDT".into(),rate:0.0000182221218054,next_funding_time:1_743_609_600_000}]);
  assert_eq!(funding_payload(SOURCE,&table),json!({"source":"okx","rows":[{"symbol":"BTCUSDT","rate":0.0000182221218054,"nextFundingTime":1_743_609_600_000_i64}]}));
 }
 /// 看盘键与 instId 互译：只收 USDT 线性永续；`1000PEPE` 不再按币安的打包合约剥前缀（OKX 有什么就是什么）。
 #[test]
 fn keys_and_inst_ids_translate_both_ways() {
  assert_eq!(inst_id("BTCUSDT").as_deref(),Some("BTC-USDT-SWAP"));
  assert_eq!(inst_id("1INCHUSDT").as_deref(),Some("1INCH-USDT-SWAP"));
  assert_eq!(inst_id("PEPEUSDT").as_deref(),Some("PEPE-USDT-SWAP"));
  for bad in ["USDT","BTCUSDC","btcusdt","BTC-USDT-SWAP","BTCUSDT "] {assert_eq!(inst_id(bad),None,"{bad}")}
  assert_eq!(key_of("BTC-USDT-SWAP").as_deref(),Some("BTCUSDT"));
  for bad in ["BTC-USD-SWAP","BTC-USDC-SWAP","BTC-USDT-250926","USDT-SWAP","-USDT-SWAP","A-B-USDT-SWAP","btc-usdt-swap"] {assert_eq!(key_of(bad),None,"{bad}")}
 }
 #[test]
 fn only_public_market_paths_and_keys_pass_through() {
  for ok in ["api/v5/public/instruments","api/v5/market/tickers","api/v5/market/ticker","api/v5/market/candles","api/v5/market/history-candles","api/v5/public/funding-rate","api/v5/public/open-interest","api/v5/public/mark-price"] {
   assert!(ttl_of(ok,&[]).is_some(),"{ok}");
  }
  for bad in ["","api/v5/account/balance","api/v5/trade/order","api/v5/market/books","api/v5/public/instruments/x","api/v5/market/../account"] {assert!(ttl_of(bad,&[]).is_none(),"{bad}")}
  assert_eq!(ttl_of("api/v5/market/candles",&q(&[("after","1")])),Some(Duration::from_secs(60)),"翻历史的页留得久");
  assert!(query_ok("instType","SWAP")&&!query_ok("instType","SPOT"));
  assert!(query_ok("instId","BTC-USDT-SWAP")&&!query_ok("instId","BTC-USD-SWAP")&&!query_ok("instId","ANY"));
  assert!(query_ok("bar","1H")&&query_ok("bar","1Dutc")&&!query_ok("bar","1D ")&&!query_ok("bar","2m"));
  assert!(query_ok("after","1790000000000")&&!query_ok("after","-1")&&!query_ok("limit",""));
  assert!(query_ok("instFamily","BTC-USDT")&&!query_ok("instFamily","BTC-USD"));
  assert!(!query_ok("apiKey","x")&&!query_ok("sign","x"));
 }
 #[test]
 fn only_a_zero_code_is_kept_for_later_callers() {
  let r=|b:&'static str|Reply{status:StatusCode::OK,retry_after:None,body:axum::body::Bytes::from_static(b.as_bytes())};
  assert!(okx_ok(&r(r#"{"code":"0","data":[]}"#)));
  assert!(!okx_ok(&r(r#"{"code":"50011","msg":"Too Many Requests","data":[]}"#)));
  assert!(!okx_ok(&r("<html>")));
 }
 /// 夹具照官方文档（Market Data › Get candlesticks history 的示例答复）写：新的在前，坏行丢掉。
 #[test]
 fn candle_pages_are_parsed_newest_first_rows() {
  let body=json!({"code":"0","msg":"","data":[
   ["1597026383085","3.721","3.743","3.677","3.708","8422410","22698348.04828491","12698348.04828491","1"],
   ["1597026323085","3.731","3.799","3.494","3.72","24912403","67632347.24399722","37632347.24399722","1"],
   ["bad","1","1","1","1","1","1","1","1"],
   ["1597026263085","0","1","1","1","1","1","1","1"]]});
  let bars=parse_candles(&body);
  assert_eq!(bars.len(),2);
  assert_eq!(bars[0],Bar{open_time:1_597_026_383_085,open:3.721,high:3.743,low:3.677,close:3.708,volume:22698348.04828491});
  assert_eq!(bar_of(60),Some("1m"));assert_eq!(bar_of(86_400),Some("1Dutc"));assert_eq!(bar_of(61),None);
 }
 /// 提醒补缺的窗口（最近几分钟到几小时）走 `market/candles`；翻出最新 1440 根之外才走 `history-candles`。
 #[test]
 fn recent_windows_ask_candles_and_older_ones_ask_history() {
  let minute=1_790_000_040_000;  // 整分钟
  assert_eq!(minute%60_000,0);
  let now=minute+30_000;  // 这一分钟走到一半
  assert_eq!(page_source(minute,60,now),("api/v5/market/candles",300),"补缺：从这一分钟往回");
  assert_eq!(page_source(minute-3_600_000,60,now),("api/v5/market/candles",300),"一小时前仍在最新 1440 根里");
  let floor=minute-1439*60_000;
  assert_eq!(page_source(floor+60_000,60,now).0,"api/v5/market/candles");
  assert_eq!(page_source(floor,60,now),("api/v5/market/history-candles",100),"比最新 1440 根还早的走历史接口");
  assert_eq!(page_source(minute-3*86_400_000,60,now).0,"api/v5/market/history-candles");
  assert_eq!(page_source(minute-30*86_400_000,3600,now).0,"api/v5/market/candles","1 小时线 1440 根是两个月");
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
 #[tokio::test] async fn private_paths_and_keys_are_refused_before_going_upstream() {
  assert_eq!(raw("api/v5/account/balance",&q(&[("source","okx")])).await.status(),StatusCode::NOT_FOUND);
  assert_eq!(raw("api/v5/market/tickers",&q(&[("source","okx"),("instType","SWAP"),("apiKey","x")])).await.status(),StatusCode::BAD_REQUEST);
  assert_eq!(raw("api/v5/market/candles",&q(&[("instId","BTC-USDT-SWAP"),("bar","7m")])).await.status(),StatusCode::BAD_REQUEST);
 }
}
