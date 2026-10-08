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
//! 同时到的请求按到达先后排成一队（先来先得），排头的睡到账上允许的最早时刻、醒来**再对一次账**才出站，
//! 不会一起醒来一起撞上限；账上记的是**真正出站过的**时刻，不是约出去的——所以排着的被取消
//! （客户端断开、超时把 future 丢掉）不留占位，排头睡着时被罚站也不会到点就冲出去。
//! 来的时候按队里此刻真在等的那些推算要等多久，超过 `longest_queue` 就不排了，直接回「忙」
//! （客户端有自己的退避）；排着排着被罚得比队长还久的，轮到时也回「忙」，不傻等罚完。
//! 被上游 429 了就 [`Pacer::penalize`]：全家从现在起那么久谁都不许出站（已经在排队的也一样）。
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
 book:Mutex<Book>,
 /// 轮到谁：tokio 的 `Mutex` 先来先得，排头的拿着它睡到自己的时刻；它被丢掉（取消）下一个就接上。
 turn:tokio::sync::Mutex<()>,
}
/// 账：真正出站过的那几笔，加上此刻在排队的。
struct Book {
 /// 上一笔真正出站的时刻与份量：下一笔不早于它 + `gap` × 份量。
 last:Option<(Instant,u32)>,
 /// 罚站到什么时候。
 held:Option<Instant>,
 /// 每条车道最近真正出站的那几次（最多 `count` 个，按时刻先后）。
 lanes:Vec<VecDeque<Instant>>,
 /// 正在排队的：(票号, 车道, 份量)，按到达先后。只用来推算新来的要等多久。
 waiting:VecDeque<(u64,Option<usize>,u32)>,
 tickets:u64,
}
/// 一张排队的票：丢掉（出站了、被拒了、被取消了）就从队里划掉。
struct Ticket<'a> {pacer:&'a Pacer,id:u64}
impl Drop for Ticket<'_> {
 fn drop(&mut self) {self.pacer.book().waiting.retain(|w|w.0!=self.id);}
}
/// 排头醒来发现要等的比到达时推算的还久（被罚站了）时，最多再多容忍这么久（真实时钟下每笔都会睡过头一点，
/// 一长队累起来几十毫秒，不该为这个把排了半天的拒掉）。
const OVERSLEEP:Duration=Duration::from_millis(500);

impl Pacer {
 pub const fn new(gap:Duration,longest_queue:Duration,lanes:&'static [Lane])->Self {
  Self{gap,longest_queue,lanes,book:Mutex::new(Book{last:None,held:None,lanes:Vec::new(),waiting:VecDeque::new(),tickets:0}),turn:tokio::sync::Mutex::const_new(())}
 }
 fn book(&self)->std::sync::MutexGuard<'_,Book> {
  let mut book=self.book.lock().unwrap_or_else(|e|e.into_inner());
  if book.lanes.len()<self.lanes.len() {book.lanes.resize(self.lanes.len(),VecDeque::new())}
  book
 }
 fn lane_of(&self,path:&str)->Option<usize> {self.lanes.iter().position(|l|path.starts_with(l.prefix))}
 /// 按这份账，`now` 起最早什么时候能出一笔走 `lane` 的。
 fn earliest(&self,last:Option<(Instant,u32)>,held:Option<Instant>,lanes:&[VecDeque<Instant>],lane:Option<usize>,now:Instant)->Instant {
  let mut at=now;
  if let Some(until)=held {at=at.max(until)}
  if let Some((t,cost))=last {at=at.max(t+self.gap*cost)}
  if let Some(i)=lane {
   let (rule,log)=(&self.lanes[i],&lanes[i]);
   // 车道日志按时刻先后，倒数第 `count` 个滚出窗口之后才轮得到下一次。
   if rule.count>0&&log.len()>=rule.count {at=at.max(log[log.len()-rule.count]+rule.window)}
  }
  at
 }
 fn note_lane(&self,lanes:&mut [VecDeque<Instant>],lane:Option<usize>,at:Instant) {
  if let Some(i)=lane {
   let log=&mut lanes[i];
   log.push_back(at);
   while log.len()>self.lanes[i].count {log.pop_front();}
  }
 }
 /// 新来的一笔（走 `lane`）要等到什么时候：队里在等的那些按先后一笔笔走完，再轮到它。
 fn projected(&self,book:&Book,lane:Option<usize>,now:Instant)->Instant {
  let (mut last,mut lanes)=(book.last,book.lanes.clone());
  for &(_,l,cost) in &book.waiting {
   let at=self.earliest(last,book.held,&lanes,l,now);
   last=Some((at,cost));
   self.note_lane(&mut lanes,l,at);
  }
  self.earliest(last,book.held,&lanes,lane,now)
 }
 /// 排一个出站的位置并睡到那一刻；排不上（或排着排着被罚得比队长还久）返回 `false`，账不动。
 /// 中途被取消（future 被丢掉）也不留占位。
 pub async fn pace(&self,path:&str,cost:u32)->bool {
  let (lane,cost,arrived)=(self.lane_of(path),cost.max(1),Instant::now());
  let _ticket={
   let mut book=self.book();
   if self.projected(&book,lane,arrived).saturating_duration_since(arrived)>self.longest_queue {return false}
   let id=book.tickets;
   book.tickets+=1;
   book.waiting.push_back((id,lane,cost));
   Ticket{pacer:self,id}
  };
  let _turn=self.turn.lock().await;
  loop {
   let now=Instant::now();
   let at={
    let mut book=self.book();
    let at=self.earliest(book.last,book.held,&book.lanes,lane,now);
    if at<=now {
     // 记真正出站的这一刻（不是约的那一刻）：睡过头了也按实际算，窗口只会更宽。
     book.last=Some((now,cost));
     let lanes=&mut book.lanes;
     self.note_lane(lanes,lane,now);
     return true
    }
    at
   };
   if at.saturating_duration_since(arrived)>self.longest_queue+OVERSLEEP {return false}
   // 醒来再对一次账：睡着的时候可能被罚站了。
   tokio::time::sleep_until(at).await;
  }
 }
 /// 被上游限流了：全家从现在起这么久谁都不许再出站（只会往后推，不会往回拉）。已经在排队的、
 /// 排头正睡着的也一样：醒来对账时看得见。
 pub fn penalize(&self,span:Duration) {
  let until=Instant::now()+span.clamp(Duration::from_millis(500),Duration::from_secs(60));
  let mut book=self.book();
  if book.held.is_none_or(|h|h<until) {book.held=Some(until)}
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
 #[cfg(test)]
 if let Ok(reply)=fake::UPSTREAM.try_with(|answer|answer(url,query,body)) {return reply}
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
/// 测试用的假出站口：在 `UPSTREAM.scope(…)` 里跑的代码，[`send`] 不排节拍、不出网，把地址、查询与正文交给它答。
/// 按任务各管各的（`task_local`），并行跑的别的测试看不见。
#[cfg(test)]
pub(crate) mod fake {
 pub type Answer=std::sync::Arc<dyn Fn(&str,&[(String,String)],Option<&serde_json::Value>)->Result<super::Reply,super::Upstream>+Send+Sync>;
 tokio::task_local! {pub static UPSTREAM:Answer;}
 /// 一份 200 + JSON 正文。
 pub fn ok(body:&serde_json::Value)->Result<super::Reply,super::Upstream> {
  Ok(super::Reply{status:axum::http::StatusCode::OK,retry_after:None,body:axum::body::Bytes::from(body.to_string())})
 }
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
  // 控制字符（`\0`、换行）一律不往上游带：上游的签名 / 日志 / 缓存键都不该见到它们。
  if v.len()>200||v.chars().any(char::is_control)||!key_ok(k,v) {return None}
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

 /// 按先后排进来一串（暂停的时钟、单线程：先 spawn 的先排上），等它们都进了队再返回。
 /// 每个任务回放行时距 `t0` 多久（排不上是 `None`）。
 async fn queue(pacer:&'static Pacer,t0:Instant,jobs:&[(&'static str,u32)])->Vec<tokio::task::JoinHandle<Option<Duration>>> {
  let handles=jobs.iter().map(|&(path,cost)|tokio::spawn(async move {pacer.pace(path,cost).await.then(||Instant::now()-t0)})).collect();
  tokio::task::yield_now().await;
  handles
 }
 async fn outcomes(handles:Vec<tokio::task::JoinHandle<Option<Duration>>>)->Vec<Option<u64>> {
  let mut out=Vec::new();
  for h in handles {out.push(h.await.unwrap().map(|d|d.as_millis() as u64))}
  out
 }

 #[tokio::test(start_paused=true)] async fn the_gap_spaces_out_requests_and_cost_multiplies_it() {
  let pacer=leak(Pacer::new(Duration::from_millis(100),Duration::from_secs(1),&[]));
  let t0=Instant::now();
  // 0、100（份量 3，占三格）、400、500 … 1000；再来的要等 1.1 秒，超过队长，不排，账不动。
  let mut jobs=vec![("x",1),("x",3)];
  jobs.extend([("x",1);7]);
  let first=queue(pacer,t0,&jobs).await;
  assert!(!pacer.pace("x",1).await,"已经排到一秒开外，再来就不排");
  assert_eq!(outcomes(first).await,vec![Some(0),Some(100),Some(400),Some(500),Some(600),Some(700),Some(800),Some(900),Some(1000)]);
  assert!(pacer.pace("x",1).await);
  assert_eq!((Instant::now()-t0).as_millis(),1100,"排不上的那次没占位置");
 }

 #[tokio::test(start_paused=true)] async fn a_lane_caps_one_endpoint_without_slowing_the_others() {
  let pacer=leak(Pacer::new(Duration::from_millis(10),Duration::from_secs(5),LANES));
  let t0=Instant::now();
  let got=outcomes(queue(pacer,t0,&[("api/slow/x",1),("api/slow/x",1),("api/slow/y",1),("api/fast",1)]).await).await;
  assert_eq!(got,vec![Some(0),Some(10),Some(2000),Some(2010)],"同一条车道第三次等最早那次滚出窗口；全家的间隔照样排在它后面");
  let pacer=leak(Pacer::new(Duration::from_millis(10),Duration::from_secs(1),LANES));
  let t0=Instant::now();
  let two=queue(pacer,t0,&[("api/slow",1),("api/slow",1)]).await;
  assert!(!pacer.pace("api/slow",1).await,"车道要等的超过队长也不排");
  assert_eq!(outcomes(two).await,vec![Some(0),Some(10)]);
  assert!(pacer.pace("api/other",1).await);
  assert_eq!((Instant::now()-t0).as_millis(),20);
 }

 #[tokio::test(start_paused=true)] async fn a_penalty_holds_everyone_back() {
  let pacer=leak(Pacer::new(Duration::from_millis(10),Duration::from_secs(30),&[]));
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

 // ---------------------------------------------------------------- 压测（暂停的时钟，几百个并发任务）

 /// 确定的伪随机（xorshift），压测可复现。
 struct Rng(u64);
 impl Rng {fn next(&mut self)->u64 {self.0^=self.0<<13;self.0^=self.0>>7;self.0^=self.0<<17;self.0} fn below(&mut self,n:u64)->u64 {self.next()%n}}

 /// 一笔真正放出去的出站：时刻、路径、份量。
 type Fired=Vec<(Instant,&'static str,u32)>;
 /// 起 `n` 个任务，第 `i` 个在 `arrive(i)` 之后来排 `path(i)`（份量 `cost(i)`）；返回放行的（按时刻排好）与被拒的个数，
 /// 以及每个放行的从到达到放行等了多久里最长的那一次。
 async fn storm(pacer:&'static Pacer,n:usize,arrive:impl Fn(usize)->Duration,path:impl Fn(usize)->&'static str,cost:impl Fn(usize)->u32)->(Fired,usize,Duration) {
  let mut set=tokio::task::JoinSet::new();
  for i in 0..n {
   let (delay,path,cost)=(arrive(i),path(i),cost(i));
   set.spawn(async move {
    tokio::time::sleep(delay).await;
    let asked=Instant::now();
    pacer.pace(path,cost).await.then(||(Instant::now(),path,cost,Instant::now()-asked))
   });
  }
  let (mut fired,mut refused,mut longest)=(Vec::new(),0,Duration::ZERO);
  while let Some(r)=set.join_next().await {
   match r.unwrap() {Some((at,p,c,waited))=>{fired.push((at,p,c));longest=longest.max(waited)},None=>refused+=1}
  }
  fired.sort_by_key(|f|f.0);
  (fired,refused,longest)
 }
 /// 任意一个 `[t, t+window)` 里，`pick` 选中的那些放行加起来的份量最多是多少（滑动窗口取最大）。
 fn busiest(fired:&Fired,window:Duration,pick:impl Fn(&str)->Option<u32>)->u32 {
  let picked:Vec<(Instant,u32)>=fired.iter().filter_map(|(t,p,c)|pick(p).map(|w|(*t,w*c))).collect();
  let (mut most,mut sum,mut tail)=(0,0,0);
  for head in 0..picked.len() {
   sum+=picked[head].1;
   while picked[tail].0+window<=picked[head].0 {sum-=picked[tail].1;tail+=1;}
   most=most.max(sum);
  }
  most
 }
 fn leak(p:Pacer)->&'static Pacer {Box::leak(Box::new(p))}
 fn copy(p:&Pacer)->&'static Pacer {leak(Pacer::new(p.gap,p.longest_queue,p.lanes))}

 /// OKX：按接口各算，官方「每 IP 每 2 秒」——candles 40、history-candles 20、tickers / ticker / instruments /
 /// open-interest 20、funding-rate / mark-price 10、持仓量历史 5。几百个并发任务一起来、接着一分钟里陆续来，
 /// 任意 2 秒窗口里每条接口都不超；全家（最小间隔 50 ms）任意 2 秒不超 41 次；排得上的都在队长之内放行，排不上的当场拒。
 #[tokio::test(start_paused=true)] async fn okx_lanes_hold_under_a_storm() {
  const PATHS:[(&str,u32);10]=[
   ("api/v5/market/candles",40),("api/v5/market/history-candles",20),("api/v5/market/tickers",20),("api/v5/market/ticker",20),
   ("api/v5/public/instruments",20),("api/v5/public/open-interest",20),("api/v5/public/funding-rate",10),("api/v5/public/mark-price",10),
   ("api/v5/rubik/stat/contracts/open-interest-history",5),("api/v5/market/books",20)];
  let pacer=copy(&crate::venues::okx::PACER);
  let rng=Mutex::new(Rng(0x9e37_79b9_7f4a_7c15));
  let picks:Vec<(u64,usize)>=(0..900).map(|i|{let mut r=rng.lock().unwrap();(if i<300 {0} else {r.below(60_000)},r.below(100) as usize)}).collect();
  // 一半打在 K 线上（补缺与透传最多的那条），其余均匀撒开。
  let path=|i:usize|{let k=picks[i].1;PATHS[if k<50 {0} else {k%PATHS.len()}].0};
  let (fired,refused,longest)=storm(pacer,picks.len(),|i|Duration::from_millis(picks[i].0),path,|_|1).await;
  assert!(refused>0,"头一秒 300 个一起来，排不下的该拒");
  assert!(fired.len()>400,"放行太少（{}），节拍卡得过死",fired.len());
  assert!(longest<=pacer.longest_queue+Duration::from_millis(1),"放行的最长等了 {longest:?}，超过队长");
  for (p,official) in PATHS {
   let most=busiest(&fired,Duration::from_secs(2),|q|(q==p).then_some(1));
   assert!(most<=official,"{p}：任意 2 秒最多放了 {most} 次，官方上限 {official}");
  }
  assert!(busiest(&fired,Duration::from_secs(2),|_|Some(1))<=41,"全家 50 ms 一次，2 秒最多 41 次");
  eprintln!("OKX 压测：900 个任务，放行 {}、拒 {refused}、最长等 {longest:?}；candles 任意 2 秒最多 {} 次（官方 40）、全家任意 2 秒最多 {} 次",
   fired.len(),busiest(&fired,Duration::from_secs(2),|q|(q=="api/v5/market/candles").then_some(1)),busiest(&fired,Duration::from_secs(2),|_|Some(1)));
  for w in fired.windows(2) {assert!(w[1].0-w[0].0>=pacer.gap,"两次出站隔了 {:?}，不到全家最小间隔",w[1].0-w[0].0)}
 }

 /// Bybit：所有接口合计，官方任意 5 秒 ≤ 600 次。几百个并发 + 一分钟持续来，任意 5 秒不超 101 次（50 ms 一次），离官方上限远。
 #[tokio::test(start_paused=true)] async fn bybit_family_holds_under_a_storm() {
  let pacer=copy(&crate::venues::bybit::PACER);
  let mut rng=Rng(7);
  let arrivals:Vec<u64>=(0..1200).map(|i|if i<400 {0} else {rng.below(60_000)}).collect();
  let (fired,refused,longest)=storm(pacer,arrivals.len(),|i|Duration::from_millis(arrivals[i]),|_|"v5/market/kline",|_|1).await;
  assert!(refused>0);
  assert!(longest<=pacer.longest_queue+Duration::from_millis(1),"{longest:?}");
  let most=busiest(&fired,Duration::from_secs(5),|_|Some(1));
  assert!(most<=101&&most<=600,"任意 5 秒放了 {most} 次");
  eprintln!("Bybit 压测：1200 个任务，放行 {}、拒 {refused}、最长等 {longest:?}；任意 5 秒最多 {most} 次（官方 600）",fired.len());
 }

 /// Hyperliquid：按权重，官方每分钟 1200；一格 = 权重 2。`meta` 10 格、K 线 13 格、`allMids` 1 格混着来，
 /// 任意 60 秒里的权重合计不超过 1200（节拍按 1000 留余量）。
 #[tokio::test(start_paused=true)] async fn hyperliquid_weight_holds_under_a_storm() {
  let pacer=copy(&crate::venues::hyperliquid::PACER);
  let mut rng=Rng(11);
  let jobs:Vec<(u64,u32)>=(0..600).map(|i|(if i<200 {0} else {rng.below(120_000)},[1,10,13][rng.below(3) as usize])).collect();
  let (fired,refused,longest)=storm(pacer,jobs.len(),|i|Duration::from_millis(jobs[i].0),|_|"info",|i|jobs[i].1).await;
  assert!(refused>0);
  assert!(longest<=pacer.longest_queue+Duration::from_millis(1),"{longest:?}");
  let weight=busiest(&fired,Duration::from_secs(60),|_|Some(2));
  assert!(weight<=1200,"任意 60 秒权重合计 {weight}，官方上限 1200");
  assert!(weight<=1000+26,"节拍是按每分钟 1000 设的（再加最后一笔的份量），实际 {weight}");
  eprintln!("Hyperliquid 压测：600 个任务，放行 {}、拒 {refused}、最长等 {longest:?}；任意 60 秒权重最多 {weight}（官方 1200）",fired.len());
  for w in fired.windows(2) {assert!(w[1].0-w[0].0>=pacer.gap*w[0].2,"上一笔份量 {}，间隔只有 {:?}",w[0].2,w[1].0-w[0].0)}
 }

 /// Coinbase：公开接口每 IP 每秒 10 次。
 #[tokio::test(start_paused=true)] async fn coinbase_holds_under_a_storm() {
  let pacer=copy(&crate::venues::coinbase::PACER);
  let mut rng=Rng(3);
  let arrivals:Vec<u64>=(0..500).map(|i|if i<200 {0} else {rng.below(30_000)}).collect();
  let (fired,_,_)=storm(pacer,arrivals.len(),|i|Duration::from_millis(arrivals[i]),|_|"api/v3/brokerage/market/products",|_|1).await;
  assert!(busiest(&fired,Duration::from_secs(1),|_|Some(1))<=10);
 }

 /// 真实时钟、多线程：几百个任务一起排一条车道 + 全家间隔，中途随机取消一批、插一次罚站。真实的睡眠只会睡过头，
 /// 所以按实际出站时刻量，任意窗口仍不超；取消的不留占位（全部跑完不超过推算的时长）。约 1.5 秒。
 #[tokio::test(flavor="multi_thread",worker_threads=4)] async fn real_clock_threads_keep_the_limits() {
  const LANE:&[Lane]=&[Lane{prefix:"lane",count:5,window:Duration::from_millis(200)}];
  let pacer=leak(Pacer::new(Duration::from_millis(4),Duration::from_secs(3),LANE));
  let fired=Arc::new(Mutex::new(Vec::<(Instant,&'static str)>::new()));
  let mut rng=Rng(99);
  let mut handles=Vec::new();
  for i in 0..400 {
   let path:&'static str=if rng.below(3)==0 {"lane/x"} else {"other"};
   let fired=fired.clone();
   let delay=Duration::from_millis(rng.below(400));
   handles.push((i,tokio::spawn(async move {
    tokio::time::sleep(delay).await;
    if pacer.pace(path,1).await {fired.lock().unwrap().push((Instant::now(),path));}
   })));
  }
  tokio::time::sleep(Duration::from_millis(150)).await;
  for (i,h) in &handles {if i%5==0 {h.abort()}}
  tokio::time::sleep(Duration::from_millis(100)).await;
  pacer.penalize(Duration::from_millis(500));
  let penalized=Instant::now();
  for (_,h) in handles {let _=h.await;}
  let mut fired=fired.lock().unwrap().clone();
  fired.sort_by_key(|f|f.0);
  let as_fired:Fired=fired.iter().map(|(t,p)|(*t,*p,1)).collect();
  assert!(busiest(&as_fired,Duration::from_millis(200),|p|(p=="lane/x").then_some(1))<=5,"车道窗口超了");
  for w in fired.windows(2) {assert!(w[1].0-w[0].0>=Duration::from_millis(4),"全家间隔被挤穿：{:?}",w[1].0-w[0].0)}
  // 罚站时正在跑的那一笔可能已经出了门，之后半秒里一笔都不许有（留 5 ms 给「刚好在罚之前醒来对完账」的那一笔）。
  let during=fired.iter().filter(|(t,_)|*t>penalized+Duration::from_millis(5)&&*t<penalized+Duration::from_millis(500)).count();
  assert_eq!(during,0,"罚站期间出了 {during} 笔");
  assert!(fired.len()>=150,"放行太少：{}",fired.len());
 }

 /// 罚站中途插进来：已经在排队、约好了时刻的那些也不许在罚站期间出站（以前约好的照样按点出发，
 /// 429 之后紧跟着又是一串请求打上去——Bybit 那边是 403 封 10 分钟）。
 #[tokio::test(start_paused=true)] async fn a_penalty_in_the_middle_holds_back_everyone_already_queued() {
  let pacer=leak(Pacer::new(Duration::from_millis(50),Duration::from_secs(30),&[]));
  let t0=Instant::now();
  let mut set=tokio::task::JoinSet::new();
  for _ in 0..100 {set.spawn(async move {pacer.pace("x",1).await.then(Instant::now)});}
  // 跑到第 300 ms（放出去 6、7 笔）时被 429 了，罚 5 秒。
  tokio::time::sleep(Duration::from_millis(310)).await;
  pacer.penalize(Duration::from_secs(5));
  let penalized=Instant::now();
  let mut fired=Vec::new();
  while let Some(r)=set.join_next().await {if let Some(at)=r.unwrap() {fired.push(at)}}
  let early=fired.iter().filter(|t|**t>penalized&&**t<penalized+Duration::from_secs(5)).count();
  assert_eq!(early,0,"罚站期间放出去了 {early} 笔");
  assert_eq!(fired.iter().filter(|t|**t<=penalized).count(),7,"罚之前放的照常");
  assert_eq!(fired.len(),100,"队长 30 秒，罚完都还排得上");
  fired.sort();
  for w in fired.windows(2) {assert!(w[1]-w[0]>=Duration::from_millis(50))}
  assert!(fired[7]>=t0+Duration::from_millis(310)+Duration::from_secs(5));
 }

 /// 罚得比队长还久：排着的不再傻等罚完，到了队长就拒（客户端有自己的退避）。
 #[tokio::test(start_paused=true)] async fn a_penalty_longer_than_the_queue_refuses_the_queued() {
  let pacer=leak(Pacer::new(Duration::from_millis(100),Duration::from_secs(2),&[]));
  let mut set=tokio::task::JoinSet::new();
  for _ in 0..10 {set.spawn(async move {let asked=Instant::now();(pacer.pace("x",1).await,Instant::now()-asked)});}
  tokio::time::sleep(Duration::from_millis(1)).await;
  pacer.penalize(Duration::from_secs(30));
  let mut results=Vec::new();
  while let Some(r)=set.join_next().await {results.push(r.unwrap())}
  assert_eq!(results.iter().filter(|r|r.0).count(),1,"罚之前第一笔已经放了");
  assert!(results.iter().all(|r|r.1<=Duration::from_secs(3)),"谁都没有等过队长太多：{results:?}");
 }

 /// 取消（future 被丢掉：客户端断开、超时）不留占位：一大批排队的全取消之后，下一个马上就能走。
 #[tokio::test(start_paused=true)] async fn cancelled_waiters_leave_no_reservation_behind() {
  const LANE:&[Lane]=&[Lane{prefix:"lane",count:3,window:Duration::from_secs(2)}];
  let pacer=leak(Pacer::new(Duration::from_millis(50),Duration::from_secs(8),LANE));
  let mut handles=Vec::new();
  for i in 0..150 {handles.push(tokio::spawn(async move {pacer.pace(if i%2==0 {"lane/x"} else {"other"},1).await}));}
  tokio::time::sleep(Duration::from_millis(1)).await;
  for h in &handles {h.abort();}
  for h in handles {let _=h.await;}
  tokio::time::sleep(Duration::from_millis(60)).await;
  let t=Instant::now();
  assert!(pacer.pace("other",1).await);
  assert!(Instant::now()-t<=Duration::from_millis(1),"被取消的 149 个还占着位置：等了 {:?}",Instant::now()-t);
  // 车道里也没留下占位：被取消的没有真的出站，不算进车道的次数（第一笔已经出去了，所以还能走两笔）。
  let t=Instant::now();
  assert!(pacer.pace("lane/y",1).await&&pacer.pace("lane/y",1).await);
  assert!(Instant::now()-t<=Duration::from_millis(101),"车道被取消的占位卡住：{:?}",Instant::now()-t);
  // 一个等着的被 `timeout` 取消（它自己的 future 被丢掉），后来的照常按队排。
  let slow=tokio::time::timeout(Duration::from_millis(1),pacer.pace("lane/z",1)).await;
  assert!(slow.is_err(),"车道满了，它要等到第一笔滚出 2 秒窗口");
  let t=Instant::now();
  assert!(pacer.pace("other",1).await);
  assert!(Instant::now()-t<=Duration::from_millis(51),"超时丢掉的那个没留占位：{:?}",Instant::now()-t);
 }

 /// 队长按队里真在等的算：排满就拒，队里的走掉了（放行或取消）就又能排。
 #[tokio::test(start_paused=true)] async fn the_queue_limit_counts_only_live_waiters() {
  let pacer=leak(Pacer::new(Duration::from_millis(100),Duration::from_secs(1),&[]));
  let mut handles=Vec::new();
  for _ in 0..11 {handles.push(tokio::spawn(async move {pacer.pace("x",1).await}));}
  tokio::time::sleep(Duration::from_millis(1)).await;
  assert!(!pacer.pace("x",1).await,"0、100、…、1000 ms 都约出去了，再来一个要等 1.1 秒");
  for h in handles.drain(5..) {h.abort();}
  tokio::time::sleep(Duration::from_millis(1)).await;
  let t=Instant::now();
  assert!(pacer.pace("x",1).await,"后面六个取消了，又排得上");
  assert!(Instant::now()-t<=Duration::from_millis(500),"{:?}",Instant::now()-t);
  for h in handles {assert!(h.await.unwrap())}
 }

 #[tokio::test] async fn a_memo_serves_stale_within_its_age_when_the_refresh_fails() {
  let memo:Memo<u32>=Memo::new();
  assert_eq!(*memo.get(Duration::ZERO,Duration::from_secs(60),||async {Ok(1)}).await.unwrap(),1);
  assert_eq!(*memo.get(Duration::ZERO,Duration::from_secs(60),||async {Err(Upstream::Unavailable)}).await.unwrap(),1,"刷不动拿旧表");
  assert!(memo.get(Duration::ZERO,Duration::ZERO,||async {Ok(2)}).await.is_err(),"刚失败过两秒内一起失败，太旧的旧表不算");
 }
}
