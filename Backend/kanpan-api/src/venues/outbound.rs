//! 每家交易所出站的共用件：一家一个节拍（[`Pacer`]）、拿不到的原因（[`Upstream`]）、
//! 原样回给客户端的答复（[`Reply`] / [`json_body`] / [`refuse`]）、带节拍的 GET / POST、
//! 同键合流的短缓存（[`Answers`]）与单飞的整表缓存（[`Memo`]）。
//!
//! 规矩（2026-10-08 交易所模块框架）：**一家交易所一个 `static PACER`**，这一家的所有 REST 出站——
//! 透传、提醒补缺、订单流品种表、持仓量 / 费率、`market_meta` 与 `listing_watch` 顺手拉的品种表——
//! 全部经它排队。以前 OKX 的持仓量历史、K 线均价各有一道自己的滑动窗口，Coinbase 的透传一道、
//! 订单流品种表不经任何一道：同一个出口 IP 上几套互不知道的限流，谁都以为自己没超。
//!
//! 节拍按两层算：全家共用的最小间隔 `gap`（乘这一笔的「份量」`cost`，Hyperliquid 按权重记），
//! 加上按路径前缀的几条「车道」（[`Lane`]：某个接口 N 秒内最多几次，照官方文档的单接口限速）。
//! 位置是**预约**出来的（排到哪个时刻就睡到哪个时刻），所以同时到的请求按到达先后排开，
//! 不会一起醒来一起撞上限；排队超过 `longest_queue` 就不排了，直接回「忙」（客户端有自己的退避）。
//! 被上游 429 了就 [`Pacer::penalize`]：全家从现在起那么久谁都不许出站。
//!
//! 币安不在这里：它按权重记一分钟滚动预算（`venues::binance` 的账本）外加进程级封禁闸
//! （`binance_gate`），那两样本来就是「一家一道」，形状和这里不同，不硬塞进来。
use axum::body::Bytes;
use axum::http::{HeaderValue,StatusCode,header};
use axum::response::{IntoResponse,Response};
use serde_json::{Value,json};
use std::collections::{HashMap,VecDeque};
use std::future::Future;
use std::sync::{Arc,Mutex,OnceLock};
use std::time::Duration;
use tokio::time::Instant;

// ------------------------------------------------------------------ 节拍

/// 一条车道：路径以 `prefix` 开头（不带开头的 `/`）的出站，`window` 之内最多 `count` 次。
pub struct Lane {pub prefix:&'static str,pub count:usize,pub window:Duration}

/// 一家交易所的出站节拍。`static` 一份，整个进程共用。
pub struct Pacer {
 gap:Duration,
 longest_queue:Duration,
 lanes:&'static [Lane],
 state:Mutex<Option<Booked>>,
}
/// 已经约出去的位置：下一个最早能出发的时刻，和每条车道最近约出去的那几次。
struct Booked {next:Instant,lanes:Vec<VecDeque<Instant>>}

impl Pacer {
 pub const fn new(gap:Duration,longest_queue:Duration,lanes:&'static [Lane])->Self {
  Self{gap,longest_queue,lanes,state:Mutex::new(None)}
 }
 fn booked<'a>(&self,slot:&'a mut Option<Booked>,now:Instant)->&'a mut Booked {
  slot.get_or_insert_with(||Booked{next:now,lanes:vec![VecDeque::new();self.lanes.len()]})
 }
 /// 约一个出发时刻；排不上（要等超过 `longest_queue`）是 `None`，账不动。
 fn reserve(&self,now:Instant,path:&str,cost:u32)->Option<Instant> {
  let mut slot=self.state.lock().unwrap_or_else(|e|e.into_inner());
  let booked=self.booked(&mut slot,now);
  let mut at=booked.next.max(now);
  let lane=self.lanes.iter().position(|l|path.starts_with(l.prefix));
  if let Some(i)=lane {
   let (rule,log)=(&self.lanes[i],&mut booked.lanes[i]);
   while log.front().is_some_and(|t|*t+rule.window<=now) {log.pop_front();}
   // 约出去的时刻是单调的（每一个都不早于上一个 + gap），队头就是这条车道最早的那一次。
   if log.len()>=rule.count && let Some(first)=log.get(log.len()-rule.count) {at=at.max(*first+rule.window)}
  }
  if at.saturating_duration_since(now)>self.longest_queue {return None}
  booked.next=at+self.gap*cost.max(1);
  if let Some(i)=lane {
   let log=&mut booked.lanes[i];
   log.push_back(at);
   while log.len()>self.lanes[i].count {log.pop_front();}
  }
  Some(at)
 }
 /// 排一个出站的位置并睡到那一刻；排不上返回 `false`。
 pub async fn pace(&self,path:&str,cost:u32)->bool {
  match self.reserve(Instant::now(),path,cost) {
   Some(at)=>{tokio::time::sleep_until(at).await;true},
   None=>false,
  }
 }
 /// 被上游限流了：全家从现在起这么久谁都不许再出站（只会往后推，不会往回拉）。
 pub fn penalize(&self,span:Duration) {
  let now=Instant::now();
  let until=now+span.clamp(Duration::from_millis(500),Duration::from_secs(60));
  let mut slot=self.state.lock().unwrap_or_else(|e|e.into_inner());
  let booked=self.booked(&mut slot,now);
  if booked.next<until {booked.next=until}
 }
}

/// `https://host/a/b?x=1` → `a/b`（车道按它认）。
pub fn path_of(url:&str)->&str {
 let rest=url.split_once("://").map_or(url,|(_,r)|r);
 let path=rest.split_once('/').map_or("",|(_,p)|p);
 path.split_once('?').map_or(path,|(p,_)|p)
}

/// 这个地址归哪一家的节拍管（按注册表里各家登记的主机认）。给不认识交易所的通用取数口用
/// （`market_meta::get_json`、订单流的 `get_bytes` / `post_json`）：它们经手的 OKX / Bybit /
/// Coinbase / Hyperliquid 地址也得排进那一家的队，不能绕过去。
pub fn pacer_for(url:&str)->Option<(&'static Pacer,&'static dyn super::Venue)> {
 let rest=url.split_once("://").map_or(url,|(_,r)|r);
 let host=rest.split(['/','?',':']).next().unwrap_or("");
 super::venues().iter().find(|v|v.hosts().contains(&host)).and_then(|v|v.pacer().map(|p|(p,*v)))
}
/// 通用取数口出站前排队：不归任何一家管的地址直接放行；归的话排那一家的队，排不上是 `false`。
pub async fn admit(url:&str,body:Option<&Value>)->bool {
 match pacer_for(url) {
  Some((pacer,venue))=>pacer.pace(path_of(url),venue.cost(path_of(url),body)).await,
  None=>true,
 }
}
/// 通用取数口拿到答复后记账：429 按 `Retry-After` 罚那一家。
pub fn note(url:&str,status:u16,retry_after:Option<&str>) {
 if status!=429 {return}
 if let Some((pacer,_))=pacer_for(url) {pacer.penalize(Duration::from_secs(retry_after.and_then(|v|v.trim().parse().ok()).unwrap_or(1)))}
}

// ------------------------------------------------------------------ 出站

/// 这一次没拿到的原因。复盘那边按它分「退一步」和「去看上游」。
#[derive(Debug,Clone,PartialEq)]
pub enum Upstream {
 /// 被限流（或本进程的出站队列排满了）。带着对方说的秒数。
 RateLimited(Option<u64>),
 /// 连不上、5xx、正文读不出来。
 Unavailable,
 /// 4xx：这一笔本身不对（品种不存在、参数不对），重试也一样。
 Rejected(u16),
}

/// 上游的原样答复：状态码、`Retry-After`、正文。
#[derive(Clone,Debug)]
pub struct Reply {pub status:StatusCode,pub retry_after:Option<String>,pub body:Bytes}

/// 一次出站最多等多久（和订单流拉品种表一样）。
const TIMEOUT:Duration=Duration::from_secs(20);

/// 带节拍出站一次：`body` 是 `Some` 就 POST 那段 JSON，否则 GET。429 当场罚这一家。
pub async fn send(pacer:&Pacer,url:&str,query:&[(String,String)],body:Option<&Value>,cost:u32)->Result<Reply,Upstream> {
 if !pacer.pace(path_of(url),cost).await {return Err(Upstream::RateLimited(Some(1)))}
 let client=crate::http::shared();
 let request=match body {Some(b)=>client.post(url).json(b),None=>client.get(url)};
 let response=request.query(query).timeout(TIMEOUT).send().await.map_err(|_|Upstream::Unavailable)?;
 let status=StatusCode::from_u16(response.status().as_u16()).unwrap_or(StatusCode::BAD_GATEWAY);
 let retry_after=response.headers().get(reqwest::header::RETRY_AFTER).and_then(|v|v.to_str().ok()).map(str::to_owned);
 if status==StatusCode::TOO_MANY_REQUESTS {
  pacer.penalize(Duration::from_secs(retry_after.as_deref().and_then(|v|v.trim().parse().ok()).unwrap_or(1)));
 }
 let body=response.bytes().await.map_err(|_|Upstream::Unavailable)?;
 Ok(Reply{status,retry_after,body})
}
/// 几个等价的主机（Bybit 的 `api.bybit.com` / `api.bytick.com`）按先后试：连不上、5xx 换下一个；
/// 答了的（2xx / 4xx / 429）就以它为准。`path` 拼在每个主机后面。
pub async fn send_any(pacer:&Pacer,hosts:&[&str],path:&str,query:&[(String,String)],cost:u32)->Result<Reply,Upstream> {
 let mut last=Err(Upstream::Unavailable);
 for host in hosts {
  match send(pacer,&format!("{host}/{path}"),query,None,cost).await {
   Ok(reply) if reply.status.is_server_error()=>last=Ok(reply),
   Err(Upstream::Unavailable)=>{},
   other=>return other,
  }
 }
 last
}

/// 带节拍出站、要 2xx 的原文（订单流品种表这类「拿不到就是错」的用处）。
pub async fn bytes(pacer:&Pacer,url:&str,query:&[(String,String)],body:Option<&Value>,cost:u32)->anyhow::Result<Bytes> {
 let reply=send(pacer,url,query,body,cost).await.map_err(|e|anyhow::anyhow!("{url}: {e:?}"))?;
 anyhow::ensure!(reply.status.is_success(),"{url} answered {}",reply.status);
 Ok(reply.body)
}

/// 把非 200 翻成 [`Upstream`]，200 的正文解成 JSON。
pub fn json_of(reply:&Reply)->Result<Value,Upstream> {
 match reply.status.as_u16() {
  200=>serde_json::from_slice(&reply.body).map_err(|_|Upstream::Unavailable),
  429=>Err(Upstream::RateLimited(reply.retry_after.as_deref().and_then(|v|v.trim().parse().ok()))),
  s@400..=499=>Err(Upstream::Rejected(s)),
  _=>Err(Upstream::Unavailable),
 }
}
pub async fn get_json(pacer:&Pacer,url:&str,query:&[(String,String)],cost:u32)->Result<Value,Upstream> {
 json_of(&send(pacer,url,query,None,cost).await?)
}
pub async fn post_json(pacer:&Pacer,url:&str,body:&Value,cost:u32)->Result<Value,Upstream> {
 json_of(&send(pacer,url,&[],Some(body),cost).await?)
}

/// 服务端自己的用处（持仓量、费率、品种表）拿不到时答什么。
pub fn api_error(e:Upstream)->crate::error::ApiError {
 match e {
  Upstream::Rejected(404)=>crate::error::ApiError::missing(),
  _=>crate::error::ApiError(StatusCode::SERVICE_UNAVAILABLE,"market_upstream_unavailable"),
 }
}

// ------------------------------------------------------------------ 原样回

/// 一份 JSON 正文原样回：状态码照上游，`Retry-After` 照上游，不缓存。
pub fn json_body(status:StatusCode,body:Bytes,retry_after:Option<String>)->Response {
 let mut response=(status,body).into_response();
 let headers=response.headers_mut();
 headers.insert(header::CONTENT_TYPE,HeaderValue::from_static("application/json"));
 headers.insert(header::CACHE_CONTROL,HeaderValue::from_static("no-store"));
 if let Some(v)=retry_after.and_then(|v|HeaderValue::from_str(&v).ok()) {headers.insert(header::RETRY_AFTER,v);}
 response
}
/// 这边自己拒的：`{"error":…}`，429 带 `Retry-After: 1`。
pub fn refuse(status:StatusCode,error:&str)->Response {
 json_body(status,Bytes::from(json!({"error":error}).to_string()),(status==StatusCode::TOO_MANY_REQUESTS).then(||"1".to_owned()))
}
/// 透传的收尾：拿到了就原样回（5xx 也原样回，客户端据此换备用网关），没拿到就是 429 / 502。
pub fn pass(reply:Result<Reply,Upstream>)->Response {
 match reply {
  Ok(reply)=>json_body(reply.status,reply.body,reply.retry_after),
  Err(Upstream::RateLimited(_))=>refuse(StatusCode::TOO_MANY_REQUESTS,"upstream_rate_limited"),
  Err(_)=>refuse(StatusCode::BAD_GATEWAY,"upstream_unavailable"),
 }
}

/// 查询参数按白名单抄一份往上游带：`source` 是给我们自己分发用的，不带；别的键或过长的值整条拒。
pub fn forward(query:&[(String,String)],key_ok:impl Fn(&str,&str)->bool)->Option<Vec<(String,String)>> {
 let mut out=Vec::with_capacity(query.len());
 for (k,v) in query {
  if k=="source" {continue}
  if v.len()>200||!key_ok(k,v) {return None}
  out.push((k.clone(),v.clone()));
 }
 out.sort();
 Some(out)
}

// ------------------------------------------------------------------ 同键合流的短缓存

type Slot=Arc<tokio::sync::Mutex<Option<(Instant,Reply)>>>;
/// 键多到这个数就整个清掉（带时间参数的历史页键是无界的）。
const MOST_KEYS:usize=2048;

/// 透传答复的短缓存：同一个键（路径 + 排好序的查询）一把异步锁——第一个来的拿着锁去取，
/// 同键的后来者等锁、醒来直接读它存下的答案。三台手机同时冷启动，整张品种表只拉一次。
pub struct Answers {slots:OnceLock<Mutex<HashMap<String,Slot>>>}
impl Answers {
 pub const fn new()->Self {Self{slots:OnceLock::new()}}
 fn slot(&self,key:String)->Slot {
  let mut map=self.slots.get_or_init(Default::default).lock().unwrap_or_else(|e|e.into_inner());
  if map.len()>=MOST_KEYS&&!map.contains_key(&key) {map.clear()}
  map.entry(key).or_default().clone()
 }
 /// `ttl` 内的答案直接给；否则同键只出站一次。`keep` 说这一份能不能留给后来者
 /// （200 但正文里写着「限流了」的那种不留）。
 pub async fn get<F,Fut>(&self,key:String,ttl:Duration,keep:fn(&Reply)->bool,fetch:F)->Result<Reply,Upstream>
 where F:FnOnce()->Fut,Fut:Future<Output=Result<Reply,Upstream>> {
  if ttl.is_zero() {return fetch().await}
  let slot=self.slot(key);
  let mut held=slot.lock().await;
  if let Some((at,reply))=held.as_ref()&&at.elapsed()<ttl {return Ok(reply.clone())}
  let reply=fetch().await?;
  if reply.status==StatusCode::OK&&keep(&reply) {*held=Some((Instant::now(),reply.clone()))}
  Ok(reply)
 }
}
/// 200 就留。
pub fn any_ok(_:&Reply)->bool {true}

// ------------------------------------------------------------------ 单飞的整表缓存

/// 一张整表（Bybit 全部 tickers、Hyperliquid 的 meta）：`ttl` 内直接给；过期了只让一个调用方出站，
/// 同时到的其余调用方等它；刚失败过（两秒内）一起拿失败，不挨个再撞一遍；拿不到时
/// `max_age` 之内的旧表还能用。
pub struct Memo<T> {slot:tokio::sync::Mutex<(Option<(Instant,Arc<T>)>,Option<Instant>)>}
const FAILURE_HOLD:Duration=Duration::from_secs(2);
impl<T> Memo<T> {
 pub const fn new()->Self {Self{slot:tokio::sync::Mutex::const_new((None,None))}}
 pub async fn get<F,Fut>(&self,ttl:Duration,max_age:Duration,fetch:F)->Result<Arc<T>,Upstream>
 where F:FnOnce()->Fut,Fut:Future<Output=Result<T,Upstream>> {
  let mut slot=self.slot.lock().await;
  let (value,failed)=&mut *slot;
  if let Some((at,v))=value.as_ref()&&at.elapsed()<ttl {return Ok(v.clone())}
  let stale=||value.as_ref().filter(|(at,_)|at.elapsed()<max_age).map(|(_,v)|v.clone());
  if failed.is_some_and(|at|at.elapsed()<FAILURE_HOLD) {return stale().ok_or(Upstream::Unavailable)}
  match fetch().await {
   Ok(fresh)=>{let fresh=Arc::new(fresh);*value=Some((Instant::now(),fresh.clone()));*failed=None;Ok(fresh)},
   Err(e)=>{*failed=Some(Instant::now());stale().ok_or(e)},
  }
 }
}

#[cfg(test)]
mod tests {
 use super::*;

 const LANES:&[Lane]=&[Lane{prefix:"api/slow",count:2,window:Duration::from_secs(2)}];

 #[test] fn paths_are_read_off_the_url() {
  assert_eq!(path_of("https://www.okx.com/api/v5/market/tickers?instType=SWAP"),"api/v5/market/tickers");
  assert_eq!(path_of("https://api.hyperliquid.xyz/info"),"info");
  assert_eq!(path_of("https://example.com"),"");
 }

 #[test] fn the_gap_spaces_out_requests_and_cost_multiplies_it() {
  let pacer=Pacer::new(Duration::from_millis(100),Duration::from_secs(1),&[]);
  let t0=Instant::now();
  assert_eq!(pacer.reserve(t0,"x",1),Some(t0));
  assert_eq!(pacer.reserve(t0,"x",3),Some(t0+Duration::from_millis(100)));
  assert_eq!(pacer.reserve(t0,"x",1),Some(t0+Duration::from_millis(400)),"上一笔份量 3，占三格");
  // 已经约到一秒开外的，再来就不排了，账不动。
  for _ in 0..6 {pacer.reserve(t0,"x",1);}
  assert_eq!(pacer.reserve(t0,"x",1),None);
  assert_eq!(pacer.reserve(t0+Duration::from_millis(500),"x",1),Some(t0+Duration::from_millis(1100)),"排不上的那次没占位置");
 }

 #[test] fn a_lane_caps_one_endpoint_without_slowing_the_others() {
  let pacer=Pacer::new(Duration::from_millis(10),Duration::from_secs(5),LANES);
  let t0=Instant::now();
  let a=pacer.reserve(t0,"api/slow/x",1).unwrap();
  let b=pacer.reserve(t0,"api/slow/x",1).unwrap();
  assert_eq!((a,b),(t0,t0+Duration::from_millis(10)));
  assert_eq!(pacer.reserve(t0,"api/slow/y",1),Some(t0+Duration::from_secs(2)),"同一条车道第三次等最早那次滚出窗口");
  assert_eq!(pacer.reserve(t0,"api/fast",1),Some(t0+Duration::from_secs(2)+Duration::from_millis(10)),"全家的间隔照样排在它后面");
  let pacer=Pacer::new(Duration::from_millis(10),Duration::from_secs(1),LANES);
  pacer.reserve(t0,"api/slow",1);pacer.reserve(t0,"api/slow",1);
  assert_eq!(pacer.reserve(t0,"api/slow",1),None,"车道要等的超过队长也不排");
  assert_eq!(pacer.reserve(t0,"api/other",1),Some(t0+Duration::from_millis(20)));
 }

 #[tokio::test(start_paused=true)] async fn a_penalty_holds_everyone_back() {
  let pacer=Pacer::new(Duration::from_millis(10),Duration::from_secs(30),&[]);
  pacer.penalize(Duration::from_secs(5));
  let t0=Instant::now();
  assert!(pacer.pace("x",1).await);
  assert!(t0.elapsed()>=Duration::from_secs(5));
  pacer.penalize(Duration::from_millis(1));
  let t1=Instant::now();
  assert!(pacer.pace("x",1).await);
  assert!(t1.elapsed()>=Duration::from_millis(500),"最短也罚半秒");
 }

 #[test] fn forwarded_queries_are_whitelisted_and_sorted() {
  let q=|pairs:&[(&str,&str)]|pairs.iter().map(|(k,v)|(k.to_string(),v.to_string())).collect::<Vec<_>>();
  let ok=|k:&str,_:&str|matches!(k,"a"|"b");
  assert_eq!(forward(&q(&[("source","x"),("b","2"),("a","1")]),ok),Some(q(&[("a","1"),("b","2")])));
  assert_eq!(forward(&q(&[("c","1")]),ok),None);
  assert_eq!(forward(&q(&[("a",&"x".repeat(201))]),ok),None);
 }

 #[test] fn replies_turn_into_errors_by_status() {
  let r=|s:u16,retry:Option<&str>|Reply{status:StatusCode::from_u16(s).unwrap(),retry_after:retry.map(str::to_owned),body:Bytes::from_static(b"{\"a\":1}")};
  assert_eq!(json_of(&r(200,None)),Ok(json!({"a":1})));
  assert_eq!(json_of(&r(429,Some("3"))),Err(Upstream::RateLimited(Some(3))));
  assert_eq!(json_of(&r(404,None)),Err(Upstream::Rejected(404)));
  assert_eq!(json_of(&r(503,None)),Err(Upstream::Unavailable));
 }

 #[tokio::test] async fn same_key_requests_share_one_fetch() {
  use std::sync::atomic::{AtomicUsize,Ordering};
  static ANSWERS:Answers=Answers::new();
  static CALLS:AtomicUsize=AtomicUsize::new(0);
  let mut set=tokio::task::JoinSet::new();
  for _ in 0..20 {set.spawn(ANSWERS.get("k".into(),Duration::from_secs(5),any_ok,||async {
   CALLS.fetch_add(1,Ordering::SeqCst);tokio::time::sleep(Duration::from_millis(30)).await;
   Ok(Reply{status:StatusCode::OK,retry_after:None,body:Bytes::from_static(b"1")})
  }));}
  while let Some(r)=set.join_next().await {assert_eq!(&r.unwrap().unwrap().body[..],b"1");}
  assert_eq!(CALLS.load(Ordering::SeqCst),1);
 }

 #[tokio::test] async fn a_memo_serves_stale_within_its_age_when_the_refresh_fails() {
  let memo:Memo<u32>=Memo::new();
  assert_eq!(*memo.get(Duration::ZERO,Duration::from_secs(60),||async {Ok(1)}).await.unwrap(),1);
  assert_eq!(*memo.get(Duration::ZERO,Duration::from_secs(60),||async {Err(Upstream::Unavailable)}).await.unwrap(),1,"刷不动拿旧表");
  assert!(memo.get(Duration::ZERO,Duration::ZERO,||async {Ok(2)}).await.is_err(),"刚失败过两秒内一起失败，太旧的旧表不算");
 }
}
