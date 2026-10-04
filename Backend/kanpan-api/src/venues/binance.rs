//! 币安合约公开 REST 在服务端的透传——网页版「网关」线路的取数口。
//!
//! `GET /v1/market/raw/<path>?source=binance&…` → `https://fapi.binance.com/<path>?…`
//! （`dapi/…` 开头的去 `dapi.binance.com`）。只放公开行情那几条路径、查询键只放已知的几个；
//! 状态码、正文、`Retry-After` 原样回，客户端的解析两条线路共用一份。
//!
//! 为什么要有它（2026-10-02）：网页版在浏览器里能跨域拿的只有 `fapi.binance.com`，而这个域名
//! 在国内不开代理根本连不上（DNS 污染 + TLS 重置）；iOS 直连走的是 `dstream.binance.me` 这类
//! 国内能到的域名，浏览器没有这条路。新加坡这台连币安畅通，所以网页版的网关线路把 REST 也
//! 交给它转一道（以前「网关」只管 WebSocket，K 线、品种表照样浏览器直打币安，手机 4G 上就是空图）。
//!
//! 一台主机的出口 IP 由所有网页用户共享，币安按 IP 记权重（合约 2400 / 分钟），超了回 429、
//! 再打就 418 封 IP——封了连同机的 Python 网关一起遭殃。所以：
//! 1. 短 TTL 缓存 + 同键并发合流：三台手机同时启动，`exchangeInfo` 只打一次；
//! 2. 按官方权重表记一分钟滚动预算（这里取 1600，余下留给 Python 网关、推送 hub 与本进程的归档任务），
//!    超了先排队等最早的几笔滚出窗口，排不上回 429；
//! 3. 回了 429 / 418 整进程按 `Retry-After` 冷却，`X-MBX-USED-WEIGHT-1M` 逼近上限时也先停到下一分钟。
use axum::body::Bytes;
use axum::http::{HeaderValue,StatusCode,header};
use axum::response::{IntoResponse,Response};
use serde_json::json;
use std::collections::{HashMap,VecDeque};
use std::sync::{Arc,OnceLock};
use std::time::Duration;
use tokio::time::Instant;

pub const SOURCE:&str="binance";
const FAPI:&str="https://fapi.binance.com";
const DAPI:&str="https://dapi.binance.com";

// ------------------------------------------------------------------ 路径与查询

/// 透传放行的路径。`fapi/v1/*` 与 `futures/data/*` 去 U 本位主机，`dapi/v1/*` 去币本位主机。
fn upstream_of(path:&str)->Option<&'static str> {
 match path {
  "fapi/v1/exchangeInfo"|"fapi/v1/ticker/24hr"|"fapi/v1/premiumIndex"|"fapi/v1/klines"|"fapi/v1/openInterest"|"fapi/v1/depth"
  |"futures/data/openInterestHist"|"futures/data/globalLongShortAccountRatio"|"futures/data/topLongShortPositionRatio"|"futures/data/takerlongshortRatio"
  |"futures/data/basis"=>Some(FAPI),
  "dapi/v1/klines"|"dapi/v1/depth"|"dapi/v1/premiumIndex"=>Some(DAPI),
  _=>None,
 }
}
/// 查询参数只放已知的几个，`source` 是给我们自己分发用的，不往上游带。
/// `contractType` 是基差（`futures/data/basis?pair=…&contractType=PERPETUAL`）必带的；少了它手机网页走网关时基差副图整条是空的。
fn query_ok(key:&str,value:&str)->bool {
 matches!(key,"symbol"|"pair"|"interval"|"limit"|"startTime"|"endTime"|"period"|"contractType")
  &&!value.is_empty()&&value.len()<=64
  &&value.chars().all(|c|c.is_ascii_alphanumeric()||c=='_'||c=='-'||(!c.is_ascii()&&c.is_alphanumeric()))  // 中文底名合约（龙虾USDT），见 instruments::binance_symbol_char
}
fn param<'a>(query:&'a [(String,String)],key:&str)->Option<&'a str> {
 query.iter().find(|(k,_)|k==key).map(|(_,v)|v.as_str())
}
fn limit_of(query:&[(String,String)])->u32 {
 param(query,"limit").and_then(|v|v.parse().ok()).unwrap_or(0)
}

/// 官方权重表（2026-09 的现行文档）。`futures/data/*` 不计入一分钟权重（另有 1000 / 5 分钟的 IP 限），记 1 占个位。
fn weight_of(path:&str,query:&[(String,String)])->u32 {
 let limit=limit_of(query);
 let has_symbol=param(query,"symbol").is_some()||param(query,"pair").is_some();
 match path {
  "fapi/v1/klines"|"dapi/v1/klines"=>{let n=if limit==0 {500} else {limit}; if n<100 {1} else if n<500 {2} else if n<=1000 {5} else {10}}
  "fapi/v1/depth"|"dapi/v1/depth"=>{let n=if limit==0 {500} else {limit}; if n<=50 {2} else if n<=100 {5} else if n<=500 {10} else {20}}
  "fapi/v1/ticker/24hr"=>if has_symbol {1} else {40},
  "fapi/v1/premiumIndex"|"dapi/v1/premiumIndex"=>if has_symbol {1} else {10},
  _=>1,
 }
}
/// 这一条答案可以给后来者用多久。品种表变得慢；最新一页 K 线与盘口要新鲜；带 `endTime` 的历史页不会再变。
fn ttl_of(path:&str,query:&[(String,String)])->Duration {
 match path {
  "fapi/v1/exchangeInfo"=>Duration::from_secs(60),
  "fapi/v1/klines"|"dapi/v1/klines"=>if param(query,"endTime").is_some() {Duration::from_secs(60)} else {Duration::from_secs(2)},
  "fapi/v1/depth"|"dapi/v1/depth"=>Duration::from_millis(800),
  "fapi/v1/openInterest"=>Duration::from_secs(3),
  p if p.starts_with("futures/data/")=>Duration::from_secs(30),
  _=>Duration::from_secs(3),
 }
}

// ------------------------------------------------------------------ 权重预算（纯逻辑，单测覆盖）

/// 一分钟滚动窗口里的本地预算。官方 2400，同一出口还有 Python 网关、推送 hub 与板块 / OI 归档
/// （2026-10-03 实测这些合计一分钟 15–500）；真正防封的是下面 `UPSTREAM_STOP` 那道按币安自报权重的闸。
/// 网页每个浏览器走网关时只用 800（Web/src/market/limit.ts GATEWAY_SHARE），这里要装得下两台同时开十六图——
/// 原来的 1000 连一台的 1200 都装不下，一台高频切换就把排队挤爆，回 429 让整片格子空着。
const BUDGET:u32=1600;
const WINDOW:Duration=Duration::from_secs(60);
/// 排队超过这么久就不排了，直接回 429：客户端有自己的退避。
const LONGEST_QUEUE:Duration=Duration::from_secs(8);
/// 币安报的已用权重到了这个数就不再发，等下一分钟——它记的是整个出口 IP 的，比我们自己记的全。
const UPSTREAM_STOP:u32=2200;

#[derive(Default)]
struct Ledger {
 log:VecDeque<(Instant,u32)>,
 cool_until:Option<Instant>,
}
impl Ledger {
 /// 记一笔。`Ok(())` 现在就能发；`Err(wait)` 要等这么久再问。
 fn admit(&mut self,now:Instant,weight:u32)->Result<(),Duration> {
  if let Some(until)=self.cool_until {
   if until>now {return Err(until-now)}
   self.cool_until=None;
  }
  while let Some((at,_))=self.log.front() {
   if now.duration_since(*at)>=WINDOW {self.log.pop_front();} else {break}
  }
  let used:u32=self.log.iter().map(|(_,w)|*w).sum();
  if used+weight<=BUDGET {self.log.push_back((now,weight));return Ok(())}
  let wait=self.log.front().map(|(at,_)|WINDOW.saturating_sub(now.duration_since(*at))).unwrap_or(Duration::ZERO);
  Err(wait.max(Duration::from_millis(50)))
 }
 /// 整进程从现在起这么久谁都不许再出站。
 fn cool(&mut self,now:Instant,span:Duration) {
  let until=now+span.clamp(Duration::from_millis(500),Duration::from_secs(1800));
  if self.cool_until.is_none_or(|u|u<until) {self.cool_until=Some(until)}
 }
}

fn ledger()->&'static tokio::sync::Mutex<Ledger> {
 static L:OnceLock<tokio::sync::Mutex<Ledger>>=OnceLock::new();
 L.get_or_init(Default::default)
}
/// 排一个出站的位置；排不上返回要等的秒数。
async fn pace(weight:u32)->Result<(),u64> {
 let started=Instant::now();
 loop {
  let wait={
   let mut l=ledger().lock().await;
   match l.admit(Instant::now(),weight) {Ok(())=>return Ok(()),Err(w)=>w}
  };
  if started.elapsed()+wait>LONGEST_QUEUE {return Err(wait.as_secs().max(1))}
  tokio::time::sleep(wait).await;
 }
}
async fn penalize(span:Duration) {ledger().lock().await.cool(Instant::now(),span)}
/// 到下一分钟整还有多久（币安的权重窗口按自然分钟记）。
fn until_next_minute()->Duration {
 let secs=std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d|d.as_secs()).unwrap_or(0);
 Duration::from_secs(60-secs%60+1)
}

// ------------------------------------------------------------------ 出站

#[derive(Clone)]
struct Reply {status:StatusCode,retry_after:Option<String>,body:Bytes}

enum Upstream {RateLimited(u64),Unavailable}

async fn fetch(base:&str,path:&str,query:&[(String,String)],weight:u32)->Result<Reply,Upstream> {
 pace(weight).await.map_err(Upstream::RateLimited)?;
 let response=crate::market_meta::http().get(format!("{base}/{path}")).query(query).send().await.map_err(|_|Upstream::Unavailable)?;
 let status=StatusCode::from_u16(response.status().as_u16()).unwrap_or(StatusCode::BAD_GATEWAY);
 let retry_after=response.headers().get(reqwest::header::RETRY_AFTER).and_then(|v|v.to_str().ok()).map(str::to_owned);
 let used=response.headers().get("x-mbx-used-weight-1m").and_then(|v|v.to_str().ok()).and_then(|v|v.trim().parse::<u32>().ok());
 if status==StatusCode::TOO_MANY_REQUESTS||status.as_u16()==418 {
  let secs=retry_after.as_deref().and_then(|v|v.trim().parse::<u64>().ok());
  let fallback=if status.as_u16()==418 {300} else {60};
  penalize(Duration::from_secs(secs.unwrap_or(fallback))).await;
 } else if used.is_some_and(|u|u>=UPSTREAM_STOP) {
  penalize(until_next_minute()).await;
 }
 let body=response.bytes().await.map_err(|_|Upstream::Unavailable)?;
 Ok(Reply{status,retry_after,body})
}

// ------------------------------------------------------------------ 缓存 + 合流

/// 每个键一把异步锁：第一个来的拿着锁去取，同键的后来者等锁、醒来直接读新鲜的答案。
type Slot=Arc<tokio::sync::Mutex<Option<(Instant,Reply)>>>;
/// 键多到这个数就整个清掉（历史页的键是无界的）。
const MOST_KEYS:usize=4096;

fn slots()->&'static std::sync::Mutex<HashMap<String,Slot>> {
 static C:OnceLock<std::sync::Mutex<HashMap<String,Slot>>>=OnceLock::new();
 C.get_or_init(Default::default)
}
fn slot_for(key:String)->Slot {
 let mut map=slots().lock().unwrap_or_else(|e|e.into_inner());
 if map.len()>=MOST_KEYS&&!map.contains_key(&key) {map.clear()}
 map.entry(key).or_default().clone()
}

fn json_body(status:StatusCode,body:Bytes,retry_after:Option<String>)->Response {
 let mut response=(status,body).into_response();
 let headers=response.headers_mut();
 headers.insert(header::CONTENT_TYPE,HeaderValue::from_static("application/json"));
 headers.insert(header::CACHE_CONTROL,HeaderValue::from_static("no-store"));
 if let Some(v)=retry_after.and_then(|v|HeaderValue::from_str(&v).ok()) {headers.insert(header::RETRY_AFTER,v);}
 response
}
fn refuse(status:StatusCode,error:&str,retry_after:Option<u64>)->Response {
 json_body(status,Bytes::from(json!({"error":error}).to_string()),retry_after.map(|s|s.to_string()))
}

pub async fn raw(path:&str,query:&[(String,String)])->Response {
 let Some(base)=upstream_of(path) else {return refuse(StatusCode::NOT_FOUND,"unsupported_path",None)};
 let mut forward=vec![];
 for (k,v) in query {
  if k=="source" {continue}
  if !query_ok(k,v) {return refuse(StatusCode::BAD_REQUEST,"unsupported_query",None)}
  forward.push((k.clone(),v.clone()));
 }
 forward.sort();
 let ttl=ttl_of(path,&forward);
 let slot=slot_for(format!("{path}?{forward:?}"));
 let mut held=slot.lock().await;
 if let Some((at,reply))=held.as_ref()&&at.elapsed()<ttl {
  return json_body(reply.status,reply.body.clone(),None);
 }
 match fetch(base,path,&forward,weight_of(path,&forward)).await {
  Ok(reply)=>{
   if reply.status==StatusCode::OK {*held=Some((Instant::now(),reply.clone()))}
   // 非 200 原样回（4xx 是这一笔本身不对，5xx 客户端据此退避），不缓存。
   json_body(reply.status,reply.body,reply.retry_after)
  }
  Err(Upstream::RateLimited(secs))=>refuse(StatusCode::TOO_MANY_REQUESTS,"upstream_rate_limited",Some(secs)),
  Err(Upstream::Unavailable)=>refuse(StatusCode::BAD_GATEWAY,"upstream_unavailable",None),
 }
}

#[cfg(test)]
mod tests {
 use super::*;

 fn q(pairs:&[(&str,&str)])->Vec<(String,String)> {pairs.iter().map(|(k,v)|(k.to_string(),v.to_string())).collect()}

 #[test] fn only_public_futures_paths_pass_through() {
  for ok in ["fapi/v1/exchangeInfo","fapi/v1/klines","fapi/v1/ticker/24hr","fapi/v1/premiumIndex","fapi/v1/openInterest","fapi/v1/depth","futures/data/openInterestHist","futures/data/takerlongshortRatio"] {
   assert_eq!(upstream_of(ok),Some(FAPI),"{ok}");
  }
  assert_eq!(upstream_of("dapi/v1/klines"),Some(DAPI));
  for bad in ["","fapi/v1/order","fapi/v1/account","fapi/v1/klines/x","api/v3/klines","fapi/v1/../order","fapi/v2/account","sapi/v1/capital"] {
   assert!(upstream_of(bad).is_none(),"{bad}");
  }
  assert!(query_ok("symbol","LINKUSDT")&&query_ok("endTime","1700000000000")&&query_ok("period","5m"));
  assert!(!query_ok("source","binance")&&!query_ok("apiKey","x")&&!query_ok("symbol","")&&!query_ok("symbol","a b")&&!query_ok("symbol","x/..")&&!query_ok("symbol",&"A".repeat(65)));
  assert!(query_ok("symbol","龙虾USDT")&&query_ok("symbol","币安人生USDT")&&!query_ok("symbol","龙虾 USDT")&&!query_ok("symbol","龙虾／USDT"));
 }

 #[test] fn basis_passes_through_with_its_contract_type() {
  // 手机网页的基差副图（Web/src/m/chart/external.source.ts 的 BASIS）：pair + contractType，不是 symbol
  assert_eq!(upstream_of("futures/data/basis"),Some(FAPI));
  assert!(query_ok("pair","BTCUSDT")&&query_ok("contractType","PERPETUAL")&&query_ok("contractType","CURRENT_QUARTER"));
  assert!(!query_ok("contractType","")&&!query_ok("contractType","a b")&&!query_ok("contractType",&"A".repeat(65)));
  assert_eq!(ttl_of("futures/data/basis",&q(&[("pair","BTCUSDT")])),Duration::from_secs(30));
  assert_eq!(weight_of("futures/data/basis",&q(&[("pair","BTCUSDT")])),1);
 }

 #[test] fn weights_follow_the_official_table() {
  assert_eq!(weight_of("fapi/v1/klines",&q(&[("limit","99")])),1);
  assert_eq!(weight_of("fapi/v1/klines",&q(&[("limit","100")])),2);
  assert_eq!(weight_of("fapi/v1/klines",&q(&[("limit","500")])),5);
  assert_eq!(weight_of("fapi/v1/klines",&q(&[("limit","1500")])),10);
  assert_eq!(weight_of("fapi/v1/klines",&q(&[])),5,"没写 limit 按默认 500");
  assert_eq!(weight_of("fapi/v1/ticker/24hr",&q(&[])),40);
  assert_eq!(weight_of("fapi/v1/ticker/24hr",&q(&[("symbol","BTCUSDT")])),1);
  assert_eq!(weight_of("fapi/v1/premiumIndex",&q(&[])),10);
  assert_eq!(weight_of("fapi/v1/depth",&q(&[("limit","1000")])),20);
  assert_eq!(weight_of("fapi/v1/exchangeInfo",&q(&[])),1);
  assert_eq!(weight_of("futures/data/openInterestHist",&q(&[("symbol","BTCUSDT")])),1);
 }

 #[test] fn fresh_pages_are_short_lived_and_history_pages_stick() {
  assert_eq!(ttl_of("fapi/v1/exchangeInfo",&q(&[])),Duration::from_secs(60));
  assert_eq!(ttl_of("fapi/v1/klines",&q(&[("symbol","BTCUSDT")])),Duration::from_secs(2));
  assert_eq!(ttl_of("fapi/v1/klines",&q(&[("endTime","1")])),Duration::from_secs(60));
  assert!(ttl_of("fapi/v1/depth",&q(&[]))<Duration::from_secs(1));
  assert_eq!(ttl_of("futures/data/openInterestHist",&q(&[])),Duration::from_secs(30));
 }

 #[test] fn the_ledger_queues_at_the_budget_and_cools_on_demand() {
  let mut l=Ledger::default();
  let t0=Instant::now();
  for _ in 0..40 {assert_eq!(l.admit(t0,40),Ok(()));}            // 1600 用满
  let wait=l.admit(t0+Duration::from_secs(10),1).unwrap_err();
  assert_eq!(wait,Duration::from_secs(50),"等最早那笔滚出窗口");
  assert_eq!(l.admit(t0+WINDOW,1),Ok(()),"一分钟后整窗清空");
  l.cool(t0+WINDOW,Duration::from_secs(30));
  assert_eq!(l.admit(t0+WINDOW+Duration::from_secs(5),1),Err(Duration::from_secs(25)));
  assert_eq!(l.admit(t0+WINDOW+Duration::from_secs(31),1),Ok(()),"冷却过了照常放行");
  l.cool(t0,Duration::from_secs(1));
  assert_eq!(l.admit(t0+WINDOW+Duration::from_secs(32),1),Ok(()),"更早、更短的冷却不会把已有的往回拉");
 }

 #[tokio::test] async fn unknown_paths_and_private_keys_are_refused_before_going_upstream() {
  let r=raw("fapi/v1/account",&q(&[("source","binance")])).await;
  assert_eq!(r.status(),StatusCode::NOT_FOUND);
  let r=raw("fapi/v1/klines",&q(&[("source","binance"),("signature","abc")])).await;
  assert_eq!(r.status(),StatusCode::BAD_REQUEST);
 }
}
