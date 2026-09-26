//! 币安 REST 深度快照：全进程排一条队，按 IP 配额的四分之一限速（2026-09-25）。
//!
//! 币安的 REST 权重按 IP 算，和手机行情转发（`market_relay`）、行情元数据、板块历史共用一份。
//! 订单流跟踪最多拿四分之一，绝不把 IP 撞到 429：
//!
//! | 通道 | 端点 | limit=1000 的权重 | IP 每分钟权重 | 这里每分钟最多 | 占比 |
//! | --- | --- | --- | --- | --- | --- |
//! | U 本位 | `www.binance.com/fapi/v1/depth` | 20 | 2400 | 30 次（600） | 25% |
//! | 币本位 | `www.binance.com/dapi/v1/depth` | 20 | 2400 | 30 次（600） | 25% |
//! | 现货 | `data-api.binance.vision/api/v3/depth` | 50 | 6000 | 30 次（1500） | 25% |
//!
//! * 每条通道一个滑动窗口：任意 60 秒内最多 30 次、两次之间至少 1 秒（令牌桶的严格版：
//!   容量 30 的桶在一开始会一口气放出 30 次、下一分钟再放 30 次，那一个窗口里就是 60 次）。超了的排队，不丢。
//! * 队里按层排先后：主币 → 有人在看的（按需）→ 固定 → 山寨 → 热点，同层先来先走。层由注册表随时改
//!   （`Arc<AtomicU8>`），排着的请求跟着变。
//! * 乱序重同步（增量接不上）要的快照也走这条队——所以断网重连后几百本簿同时要快照也不会撞墙，只是慢慢补上。
//! * 合约两条通道出站前看 `binance_gate`（整个进程对币安 `*.binance.com` 的封禁截止时间）；现货走的
//!   `data-api.binance.vision` 不在那道闸里，这里自己记一条。429 / 418 立刻按 Retry-After 停（没给就
//!   429 停 60 秒、418 停 5 分钟），打一条 warn。
//! * 跟踪器停了（事件口关了）、或簿在排队期间断线重来（epoch 变了）的请求直接丢掉，不花配额。
use super::book::{Snapshot,VenueInfo};
use super::feeds::{self,Event};
use super::model::Notional;
use crate::binance_gate;
use std::collections::VecDeque;
use std::sync::atomic::{AtomicU8,AtomicU64,Ordering};
use std::sync::{Arc,Mutex,OnceLock};
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::time::Instant;

const UM_REST:&str="https://www.binance.com/fapi/v1/depth";
const CM_REST:&str="https://www.binance.com/dapi/v1/depth";
const SPOT_REST:&str="https://data-api.binance.vision/api/v3/depth";
/// 每条通道任意 60 秒内最多几次。
pub const PER_MINUTE:usize=30;
const WINDOW:Duration=Duration::from_secs(60);
const MIN_GAP:Duration=Duration::from_secs(1);
const TIMEOUT:Duration=Duration::from_secs(10);
const UNTOLD_429:Duration=Duration::from_secs(60);
const UNTOLD_418:Duration=Duration::from_secs(300);
const REPORT:Duration=Duration::from_secs(60);

#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum Lane {Um,Cm,Spot}
const LANES:[Lane;3]=[Lane::Um,Lane::Cm,Lane::Spot];

impl Lane {
 pub fn of(venue:&VenueInfo)->Lane {
  match (venue.product,venue.notional) {("spot",_)=>Lane::Spot,(_,Notional::Inverse(_))=>Lane::Cm,_=>Lane::Um}
 }
 fn label(self)->&'static str {match self {Lane::Um=>"um",Lane::Cm=>"cm",Lane::Spot=>"spot"}}
 fn url(self,venue:&VenueInfo)->String {
  let base=match self {Lane::Um=>UM_REST,Lane::Cm=>CM_REST,Lane::Spot=>SPOT_REST};
  format!("{base}?symbol={}&limit={}",venue.instrument.to_uppercase(),feeds::SNAPSHOT_LEVELS)
 }
 /// 这条通道还要停多久（429 / 418 之后）。
 fn hold(self)->Option<Duration> {
  match self {
   Lane::Um|Lane::Cm=>binance_gate::wait(),
   Lane::Spot=>{
    let mut slot=spot_hold().lock().unwrap_or_else(|e|e.into_inner());
    let until=(*slot)?;
    let now=Instant::now();
    if until<=now {*slot=None;return None}
    Some(until-now)
   },
  }
 }
}

fn spot_hold()->&'static Mutex<Option<Instant>> {static H:OnceLock<Mutex<Option<Instant>>>=OnceLock::new();H.get_or_init(||Mutex::new(None))}

/// 排队的一份快照。
pub struct Request {
 pub venue:VenueInfo,
 pub epoch:u64,
 /// 层的先后（小的先走），注册表随时改。
 pub priority:Arc<AtomicU8>,
 /// 最早什么时候发：连上之后先等一小会儿让增量攒起来。
 pub not_before:Instant,
 pub events:mpsc::Sender<Event>,
 /// 这本簿此刻的 epoch（跟踪器随时改）：排着的时候簿断过线重来了，这份请求出队时就丢掉，不花配额。
 pub current:Arc<AtomicU64>,
}

/// 排进队里。进程里第一次调用时起三条通道的任务。
pub fn request(r:Request) {
 static LANE_TX:OnceLock<Vec<mpsc::UnboundedSender<Request>>>=OnceLock::new();
 let lanes=LANE_TX.get_or_init(|| LANES.iter().map(|&lane| {
  let (tx,rx)=mpsc::unbounded_channel();
  crate::supervise::spawn_essential("orderflow-snapshots",run(lane,rx));
  tx
 }).collect());
 let index=LANES.iter().position(|l|*l==Lane::of(&r.venue)).unwrap_or(0);
 let _=lanes[index].send(r);
}

/// 滑动窗口：任意 `WINDOW` 内最多 `max` 次、两次之间至少 `gap`。
#[derive(Debug)]
pub struct Limiter {max:usize,window:Duration,gap:Duration,sent:VecDeque<Instant>}

impl Limiter {
 pub fn new(max:usize,window:Duration,gap:Duration)->Self {Self{max,window,gap,sent:VecDeque::new()}}
 /// 还要等多久才能发下一次；`None` 表示现在就能发。
 pub fn wait(&mut self,now:Instant)->Option<Duration> {
  while self.sent.front().is_some_and(|t|now.duration_since(*t)>=self.window) {self.sent.pop_front();}
  let by_gap=self.sent.back().map(|t|(*t+self.gap).saturating_duration_since(now)).unwrap_or_default();
  let by_window=if self.sent.len()>=self.max {self.sent.front().map(|t|(*t+self.window).saturating_duration_since(now)).unwrap_or_default()} else {Duration::ZERO};
  let w=by_gap.max(by_window);
  (!w.is_zero()).then_some(w)
 }
 pub fn record(&mut self,now:Instant) {self.sent.push_back(now);}
 pub fn in_window(&self)->usize {self.sent.len()}
}

/// 出队顺序：层小的先、同层先来先走；只挑到了时间的。
fn pick(queue:&[(u64,Request)],now:Instant)->Option<usize> {
 queue.iter().enumerate().filter(|(_,(_,r))|r.not_before<=now)
  .min_by_key(|(_,(seq,r))|(r.priority.load(Ordering::Relaxed),*seq)).map(|(i,_)|i)
}

async fn run(lane:Lane,mut rx:mpsc::UnboundedReceiver<Request>) {
 let mut queue:Vec<(u64,Request)>=Vec::new();
 let mut seq=0u64;
 let mut limiter=Limiter::new(PER_MINUTE,WINDOW,MIN_GAP);
 let (mut sent,mut longest)=(0usize,Duration::ZERO);
 let mut report=tokio::time::interval_at(Instant::now()+REPORT,REPORT);
 loop {
  let now=Instant::now();
  queue.retain(|(_,r)|!r.events.is_closed()&&r.current.load(Ordering::Relaxed)==r.epoch);
  // 这一轮要等多久：没东西等新请求；有东西但都没到时间、或在封禁里、或限速里，等到那一刻（期间照收新请求）。
  let wait=if queue.is_empty() {None} else {
   let earliest=queue.iter().map(|(_,r)|r.not_before).min().unwrap_or(now);
   let by_time=earliest.saturating_duration_since(now);
   let w=by_time.max(lane.hold().unwrap_or_default()).max(limiter.wait(now).unwrap_or_default());
   Some(w)
  };
  if let Some(Duration::ZERO)=wait {
   let Some(index)=pick(&queue,now) else {continue};
   let (_,r)=queue.swap_remove(index);
   limiter.record(now);
   sent+=1;
   longest=longest.max(now.saturating_duration_since(r.not_before));
   tokio::spawn(fetch(lane,r));
   continue;
  }
  tokio::select! {
   got=rx.recv()=>match got {Some(r)=>{seq+=1;queue.push((seq,r));while let Ok(r)=rx.try_recv() {seq+=1;queue.push((seq,r));}},None=>return},
   _=tokio::time::sleep(wait.unwrap_or(Duration::from_secs(3600)))=>{},
   _=report.tick()=>{
    if sent>0||!queue.is_empty() {
     tracing::info!("Orderflow history: snapshot queue {} sent {sent}/min, {} in the last 60s, {} waiting, longest wait {}s",lane.label(),limiter.in_window(),queue.len(),longest.as_secs());
    }
    sent=0;longest=Duration::ZERO;
   },
  }
 }
}

/// 发出去、回一个事件给跟踪器。失败回 None，由跟踪器退避再排（2 秒起翻倍，最多 5 分钟）。
async fn fetch(lane:Lane,r:Request) {
 let snapshot=get(lane,&r.venue).await;
 let _=r.events.send(Event::Snapshot{venue:r.venue.id.clone(),epoch:r.epoch,snapshot}).await;
}

async fn get(lane:Lane,venue:&VenueInfo)->Option<Snapshot> {
 let url=lane.url(venue);
 if lane.hold().is_some() {return None}
 let response=crate::market_meta::http().get(&url).timeout(TIMEOUT).send().await.ok()?;
 let status=response.status().as_u16();
 match lane {
  // 合约：进程级的币安闸门记下并打 warn。
  Lane::Um|Lane::Cm=>{if binance_gate::note_reply(&response) {tracing::warn!("Orderflow history: snapshot {} answered {status}, lane {} holds",venue.instrument,lane.label());return None}},
  Lane::Spot=>if status==429||status==418 {
   let told=response.headers().get(reqwest::header::RETRY_AFTER).and_then(|v|v.to_str().ok()).and_then(|s|s.trim().parse::<u64>().ok()).map(Duration::from_secs);
   let span=told.unwrap_or(if status==429 {UNTOLD_429} else {UNTOLD_418});
   let until=Instant::now()+span;
   let mut slot=spot_hold().lock().unwrap_or_else(|e|e.into_inner());
   if slot.is_none_or(|t|t<until) {*slot=Some(until);}
   tracing::warn!("Orderflow history: snapshot {} answered {status}, spot lane holds for {}s",venue.instrument,span.as_secs());
   return None
  },
 }
 let body:serde_json::Value=response.error_for_status().ok()?.json().await.ok()?;
 feeds::parse_snapshot(&body,venue)
}

#[cfg(test)]
mod tests {
 use super::*;
 use super::super::book::Sequence;

 fn venue(product:&'static str,notional:Notional)->VenueInfo {
  VenueInfo{id:format!("binance:{product}:X"),exchange:"binance",label:"币安",product,instrument:"btcusdt".into(),notional,price_scale:1.0,
   sequence:Sequence::PreviousFinalOverlap,in_band:false}
 }

 #[test] fn lanes_and_urls() {
  let um=venue("usdtPerp",Notional::Linear(1.0));
  let cm=venue("coinPerp",Notional::Inverse(100.0));
  let spot=venue("spot",Notional::Linear(1.0));
  assert_eq!((Lane::of(&um),Lane::of(&cm),Lane::of(&spot)),(Lane::Um,Lane::Cm,Lane::Spot));
  assert_eq!(Lane::Um.url(&um),"https://www.binance.com/fapi/v1/depth?symbol=BTCUSDT&limit=1000");
  assert_eq!(Lane::Spot.url(&spot),"https://data-api.binance.vision/api/v3/depth?symbol=BTCUSDT&limit=1000");
  assert!(binance_gate::covers(&Lane::Cm.url(&cm))&&!binance_gate::covers(&Lane::Spot.url(&spot)));
 }

 #[test] fn never_more_than_thirty_in_any_minute() {
  let start=Instant::now();
  let mut l=Limiter::new(PER_MINUTE,WINDOW,MIN_GAP);
  let mut t=start;
  let mut sent=Vec::new();
  // 十分钟里能发就发。
  while t<start+Duration::from_secs(600) {
   match l.wait(t) {None=>{l.record(t);sent.push(t);},Some(w)=>t+=w}
  }
  for (i,a) in sent.iter().enumerate() {
   let n=sent[i..].iter().take_while(|b|b.duration_since(*a)<WINDOW).count();
   assert!(n<=PER_MINUTE,"{n} in a minute");
  }
  for pair in sent.windows(2) {assert!(pair[1].duration_since(pair[0])>=MIN_GAP);}
  assert!(sent.len()>=PER_MINUTE*10-1,"不能限得比 30/分还紧：{}",sent.len());
 }

 /// 压测（2026-09-26）：一条 U 本位深度连接断了，挂在上面的 200 本簿同时要快照。
 /// 这条队每分钟 30 本，最后一本要等 6 分 19 秒、有 140 本等过两分钟（`STALE_MS`）；重启时整个进程的 U 本位簿（`MAX_BASES` 220 个品种
 /// 的永续 + 主币交割，按 260 算）同时要，最后一本等 8 分 19 秒。等快照期间簿上的单按「价位不知道」
 /// 处理（model.rs `UNKNOWN_MS`），这个上限必须盖得住排队时长，不然排在后面的簿上的单会被误判失联。
 #[test] fn a_full_connection_reconnecting_is_served_within_the_unknown_window() {
  let (tx,_rx)=mpsc::channel(1);
  for books in [super::super::feeds::Kind::BinanceUmDepth.capacity(),260] {
   let start=Instant::now();
   let r=||Request{venue:venue("usdtPerp",Notional::Linear(1.0)),epoch:1,priority:Arc::new(AtomicU8::new(0)),not_before:start,events:tx.clone(),current:Arc::new(AtomicU64::new(1))};
   let mut queue:Vec<(u64,Request)>=(0..books as u64).map(|i|(i,r())).collect();
   let mut l=Limiter::new(PER_MINUTE,WINDOW,MIN_GAP);
   let mut t=start;
   let (mut last,mut late)=(Duration::ZERO,0);
   while !queue.is_empty() {
    match l.wait(t) {
     None=>{let i=pick(&queue,t).unwrap();queue.swap_remove(i);l.record(t);last=t.duration_since(start);if last.as_millis()>=super::super::model::STALE_MS as u128 {late+=1}},
     Some(w)=>t+=w,
    }
   }
   println!("{books} 本同时要快照：最后一本等 {}s，{late} 本等过 STALE_MS",last.as_secs());
   assert!(last.as_millis()<super::super::model::UNKNOWN_MS as u128,"{books} 本：最后一本等 {}s，超过了等快照的容忍上限",last.as_secs());
  }
 }

 /// 一本主币层的簿，拿到的快照每次都接不上（REST 快照落后于流），同一条通道上还有 60 本山寨等首份快照。
 /// 按真的 `VenueBook` 对序号、真的限速器与出队顺序模拟 10 分钟：接不上之后马上重排（原来）对按 `resync_delay` 退避。
 fn starve(backoff:bool)->(usize,usize,Option<Duration>) {
  use super::super::book::{Action,Delta,Message,VenueBook};
  let (tx,_rx)=mpsc::channel(1);
  let start=Instant::now();
  let req=|id:&str,p:u8,at:Instant|Request{venue:VenueInfo{id:id.into(),..venue("usdtPerp",Notional::Linear(1.0))},epoch:1,
   priority:Arc::new(AtomicU8::new(p)),not_before:at,events:tx.clone(),current:Arc::new(AtomicU64::new(1))};
  let mut book=VenueBook::new(venue("usdtPerp",Notional::Linear(1.0)));
  assert_eq!(book.opened(1),Action::FetchSnapshot);
  book.ingest(Message::Delta(Delta{first:1_000,last:1_010,prev:Some(999),..Delta::default()}),0);
  let mut queue=vec![(0u64,req("bad",0,start))];
  queue.extend((1..=60u64).map(|i|(i,req("alt",3,start))));
  let mut seq=61u64;
  let mut l=Limiter::new(PER_MINUTE,WINDOW,MIN_GAP);
  let end=start+Duration::from_secs(600);
  let (mut t,mut reply)=(start,None::<Instant>);
  let (mut bad,mut alts,mut last_alt,mut failures)=(0,0,None,0u32);
  while t<end {
   if let Some(at)=reply && at<=t {
    reply=None;
    let now=at.duration_since(start).as_millis() as i64;
    let ready=book.ready_since();
    let action=book.snapshot(Snapshot{last:500,requested:1000,bids:vec![(99.0,1.0)],asks:vec![(101.0,1.0)]},now);
    assert_eq!(action,Action::FetchSnapshot,"快照比缓冲的增量旧，接不上");
    let delay=if backoff {super::super::resync_delay(&mut failures,ready,now)} else {0};
    // 马上重排的走 SNAPSHOT_SETTLE（0.5 秒），退避的到点由 due_retries 不等就排。
    let not_before=at+if delay==0 {Duration::from_millis(500)} else {Duration::from_millis(delay as u64)};
    queue.push((seq,req("bad",0,not_before)));seq+=1;
    continue;
   }
   let wait=l.wait(t);
   if wait.is_none() && let Some(i)=pick(&queue,t) {
    let (_,r)=queue.swap_remove(i);
    l.record(t);
    if r.venue.id=="bad" {bad+=1;reply=Some(t+Duration::from_millis(300));} else {alts+=1;last_alt=Some(t.duration_since(start));}
    continue;
   }
   let mut next=end;
   match wait {
    Some(w)=>next=next.min(t+w),
    None=>if let Some(e)=queue.iter().map(|(_,r)|r.not_before).filter(|x|*x>t).min() {next=next.min(e)},
   }
   if let Some(at)=reply {next=next.min(at)}
   t=next.max(t+Duration::from_millis(1));
  }
  (bad,alts,last_alt)
 }

 #[test] fn a_book_whose_snapshots_never_line_up_does_not_starve_the_lane() {
  let (bad,alts,last)=starve(false);
  println!("接不上马上重排：10 分钟里那一本拉了 {bad} 份，60 本山寨拿到 {alts} 本，最后一本 {:?}",last.map(|d|d.as_secs()));
  let (bad,alts,last)=starve(true);
  println!("按 resync_delay 退避：10 分钟里那一本拉了 {bad} 份，60 本山寨拿到 {alts} 本，最后一本 {:?}",last.map(|d|d.as_secs()));
  assert_eq!(alts,60,"同一条通道上的别的簿都要拿到快照");
  assert!(bad<=12,"一本接不上的簿 10 分钟拉了 {bad} 份");
  assert!(last.is_some_and(|d|d<Duration::from_secs(180)),"60 本山寨的最后一本 {last:?} 才拿到");
 }

 #[test] fn priority_then_first_come() {
  let now=Instant::now();
  let (tx,_rx)=mpsc::channel(1);
  let r=|p:u8,delay:u64|Request{venue:venue("usdtPerp",Notional::Linear(1.0)),epoch:1,priority:Arc::new(AtomicU8::new(p)),not_before:now+Duration::from_secs(delay),events:tx.clone(),current:Arc::new(AtomicU64::new(1))};
  let queue=vec![(1,r(3,0)),(2,r(1,0)),(3,r(1,0)),(4,r(0,5))];
  assert_eq!(pick(&queue,now),Some(1),"层小的先，同层先来的先");
  assert_eq!(pick(&queue,now+Duration::from_secs(5)),Some(3),"到了时间的主币插到最前");
  queue[0].1.priority.store(0,Ordering::Relaxed);
  assert_eq!(pick(&queue,now),Some(0),"层随时改，排着的跟着变");
 }
}
