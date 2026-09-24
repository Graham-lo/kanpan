//! 订单流跟踪的连接池（2026-09-25）：按「交易所 × 市场」合用连接，不再一只币一组连接。
//!
//! 常驻跟两百来只之后，按币开连接要上千条；这里把全部跟踪器的簿收到一处，每种连接按容量装满：
//!
//! | 种类 | 地址 | 一本簿几路 | 一条装多少 |
//! | --- | --- | --- | --- |
//! | 币安 U 本位深度 | `fstream …/public/stream` | 1（`@depth@500ms`） | 200 本 |
//! | 币安 U 本位成交 | `fstream …/market/stream` | 1（`@aggTrade`） | 200 本 |
//! | 币安币本位 | `dstream …/stream` | 2 | 100 本 |
//! | 币安现货 | `data-stream.binance.vision/stream` | 2（`@depth` 1000ms + `@aggTrade`） | 100 本 |
//! | OKX | `ws.okx.com:8443/ws/v5/public` | books + trades | 50 本 |
//! | Coinbase | `advanced-trade-ws.coinbase.com` | level2 + market_trades | 1 本（序号按整条连接计） |
//!
//! **优先级：手机的 K 线与行情转发（`market_relay` / 网关的 stream hub）永远在前。** 这里的连接全是
//! 自己开的，不和转发共用任何一条；连接数、新建频率都只拿各家 IP 额度的一小份，资源闸门先砍这里（见注册表）。
//!
//! 币安（组合流）：
//! * 订哪些流写进 URL 一次建好，连上之后不发 SUBSCRIBE（每条连接每秒最多收 10 条消息）。于是一条币安连接
//!   建好之后簿只减不加：新来的簿先攒一小会儿（最多 15 秒），再和当前最小的那条合成一条新连接；
//!   簿退掉的只在本地不再转发，连接里空出来的流由每分钟一次的合并收回。
//! * 同一 IP 每 5 分钟最多新建 300 条连接：这里所有币安连接共用一个节拍器，两次新建至少隔 1 秒、
//!   5 分钟内最多 60 条（额度的五分之一，剩下的留给行情转发）；断线重连退避带 ±50% 抖动，不会一起撞回去。
//! * 币安 24 小时整把连接断掉：每条连接活到 23 小时（再加 0–30 分钟随机，错开）就先建一条一模一样的新连接，
//!   新连接收到第一帧（或 5 秒）后通知旧连接退掉那些簿，3 秒重叠期里两条连接都认（`VenueBook::handover`，
//!   序号全局，重复帧按序号丢；成交按 aggTrade 号去重）——簿不重拉快照、不断档。合并也走同一套交接。
//!
//! OKX：
//! * 同一 IP 每秒最多新建 3 条连接：这里至少隔 400 毫秒。
//! * 每条连接每小时最多 480 次订阅 / 退订请求，一条请求带一批 args 只算一次：订退都攒 1 秒成一批发，
//!   一批最多 20 本（消息远小于 64 KB 上限）；一小时内这条连接用到 400 次还要再发就整条重连（新连接额度重算）。
//! * `{"event":"error"}` 打 warn。
//!
//! Coinbase：一本一条连接，新建至少隔 250 毫秒；簿要重订就整条重连。
//!
//! 帧送给跟踪器用 `try_send`：某个跟踪器堵住了只丢它自己的帧（丢帧 = 序号断档，簿自己重同步），
//! 不拖慢同一条连接上的其它币；Opened / Handover / Closed 这几种要紧的带 2 秒超时地等。
//! 每分钟打一行各种连接的条数、簿数、流数、帧数与丢帧数。
use super::book::VenueInfo;
use super::feeds::{self,Decoded,Decoder,Event,Kind,KINDS};
use crate::binance_gate;
use futures_util::{SinkExt,StreamExt};
use std::collections::{HashMap,HashSet,VecDeque};
use std::sync::OnceLock;
use std::sync::atomic::{AtomicU64,Ordering};
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::time::Instant;
use tokio_tungstenite::tungstenite::{self,Message as Up};

const PING:Duration=Duration::from_secs(20);
const IDLE:Duration=Duration::from_secs(60);
const CONNECT:Duration=Duration::from_secs(15);
const SEND:Duration=Duration::from_secs(10);
const DELIVER:Duration=Duration::from_secs(2);
/// 新连接连上之后最多等多久第一帧，再告诉池子「我接手了」。
const UP_AFTER:Duration=Duration::from_secs(5);
/// 交接重叠期：新连接接手之后旧连接再推多久。
const OVERLAP:Duration=Duration::from_secs(3);
/// 币安新簿攒批：最早的等够 5 秒且最近 2 秒没有新来的就建；最早的等到 15 秒无论如何都建。
const BATCH_QUIET:Duration=Duration::from_secs(2);
const BATCH_MIN:Duration=Duration::from_secs(5);
const BATCH_MAX:Duration=Duration::from_secs(15);
/// 币安连接活多久换新（再加 0–30 分钟随机）。
const ROTATE_AFTER:Duration=Duration::from_secs(23*60*60);
const ROTATE_JITTER_SECS:u64=30*60;
/// 活过这么久的连接才参与合并（刚建好的先别动）。
const COMPACT_AFTER:Duration=Duration::from_secs(120);
const MAINTAIN:Duration=Duration::from_secs(60);
const OKX_FLUSH:Duration=Duration::from_secs(1);
/// OKX 每条连接每小时订退请求的上限是 480，这里到 400 就换连接。
const OKX_OPS_PER_HOUR:usize=400;

// ------------------------------------------------------------------ 统计

static FRAMES:[AtomicU64;6]=[const {AtomicU64::new(0)};6];
static DROPS:[AtomicU64;6]=[const {AtomicU64::new(0)};6];

// ------------------------------------------------------------------ 新建连接的节拍

/// 各家新建连接的节拍：两次之间至少 `gap`，`window` 内最多 `max` 条。
struct Pace {gap:Duration,window:Duration,max:usize}

fn pace(kind:Kind)->(usize,Pace) {
 if kind.binance() {return (0,Pace{gap:Duration::from_secs(1),window:Duration::from_secs(300),max:60})}
 match kind {
  Kind::Okx=>(1,Pace{gap:Duration::from_millis(400),window:Duration::from_secs(1),max:3}),
  _=>(2,Pace{gap:Duration::from_millis(250),window:Duration::from_secs(1),max:4}),
 }
}

/// 等到能新建一条这种连接为止（同一家的连接共用一个节拍器）。币安出口被封着时也等。
async fn permit(kind:Kind) {
 static LOGS:OnceLock<[tokio::sync::Mutex<VecDeque<Instant>>;3]>=OnceLock::new();
 let logs=LOGS.get_or_init(||[const {tokio::sync::Mutex::const_new(VecDeque::new())};3]);
 let (family,p)=pace(kind);
 let mut log=logs[family].lock().await;
 loop {
  let now=Instant::now();
  while log.front().is_some_and(|t|now.duration_since(*t)>=p.window) {log.pop_front();}
  let by_gap=log.back().map(|t|(*t+p.gap).saturating_duration_since(now)).unwrap_or_default();
  let by_window=if log.len()>=p.max {log.front().map(|t|(*t+p.window).saturating_duration_since(now)).unwrap_or_default()} else {Duration::ZERO};
  let by_gate=if kind.binance() {binance_gate::wait().unwrap_or_default()} else {Duration::ZERO};
  let w=by_gap.max(by_window).max(by_gate);
  if w.is_zero() {break}
  tokio::time::sleep(w).await;
 }
 log.push_back(Instant::now());
}

/// 退避带 ±50% 抖动。
fn jittered(d:Duration)->Duration {d.mul_f64(rand::random_range(0.5..1.5))}

// ------------------------------------------------------------------ 对外

/// 一本簿挂到哪个跟踪器。
#[derive(Clone,Debug)]
pub struct Route {pub venue:VenueInfo,pub events:mpsc::Sender<Event>}

enum HubCmd {Add(Vec<Route>),Remove(Vec<String>),Resubscribe(String),Up(u64),Gone(u64)}

enum ConnCmd {Assign(Vec<Route>),Drop(Vec<String>),Resubscribe(String)}

fn hub()->&'static mpsc::UnboundedSender<HubCmd> {
 static HUB:OnceLock<mpsc::UnboundedSender<HubCmd>>=OnceLock::new();
 HUB.get_or_init(|| {
  let (tx,rx)=mpsc::unbounded_channel();
  tokio::spawn(manage(rx,tx.clone()));
  tx
 })
}

/// 这些簿开始要推送。
pub fn add(venues:Vec<VenueInfo>,events:&mpsc::Sender<Event>) {
 if venues.is_empty() {return}
 let _=hub().send(HubCmd::Add(venues.into_iter().map(|venue|Route{venue,events:events.clone()}).collect()));
}
/// 这些簿不要了（跟踪器停了）。
pub fn remove(ids:Vec<String>) {if !ids.is_empty() {let _=hub().send(HubCmd::Remove(ids));}}
/// 流内快照的簿接不上了：OKX 退订再订这一本；Coinbase 整条重连。
pub fn resubscribe(id:String) {let _=hub().send(HubCmd::Resubscribe(id));}

// ------------------------------------------------------------------ 池子

struct Slot {
 kind:Kind,
 venues:HashMap<String,Route>,
 tx:mpsc::UnboundedSender<ConnCmd>,
 born:Instant,
 up:bool,
 /// 正在被新连接接手（换新 / 合并）：不再参与别的换新与合并。
 moving:bool,
 rotate_at:Instant,
 /// 这条连接接手了哪些旧连接上的哪些簿（等它 Up 之后让旧连接退掉）。
 replaces:Vec<(u64,Vec<String>)>,
}

impl Slot {fn streams(&self)->usize {self.venues.len()*self.kind.suffixes().len().max(1)}}

struct Pending {routes:Vec<Route>,since:Instant,last:Instant}

#[derive(Default)]
struct Pool {slots:HashMap<u64,Slot>,pending:HashMap<Kind,Pending>,next:u64,drops:Vec<(Instant,u64,Vec<String>)>,frames:[u64;6],drops_seen:[u64;6]}

impl Pool {
 fn spawn(&mut self,kind:Kind,routes:Vec<Route>,replaces:Vec<(u64,Vec<String>)>,hub_tx:&mpsc::UnboundedSender<HubCmd>)->u64 {
  self.next+=1;
  let id=self.next;
  let (tx,rx)=mpsc::unbounded_channel();
  let jitter=Duration::from_secs(rand::random_range(0..=ROTATE_JITTER_SECS));
  let now=Instant::now();
  let venues:HashMap<String,Route>=routes.iter().map(|r|(r.venue.id.clone(),r.clone())).collect();
  self.slots.insert(id,Slot{kind,venues,tx,born:now,up:false,moving:false,rotate_at:now+ROTATE_AFTER+jitter,replaces});
  tokio::spawn(run(id,kind,routes,rx,hub_tx.clone()));
  id
 }

 fn add(&mut self,routes:Vec<Route>,hub_tx:&mpsc::UnboundedSender<HubCmd>) {
  let now=Instant::now();
  let known:HashSet<(Kind,String)>=self.slots.values().flat_map(|s|s.venues.keys().map(move|id|(s.kind,id.clone()))).collect();
  let mut okx=Vec::new();
  for route in routes {
   for &kind in feeds::kinds_of(&route.venue) {
    if known.contains(&(kind,route.venue.id.clone())) {continue}
    match kind {
     Kind::Coinbase=>{self.spawn(kind,vec![route.clone()],Vec::new(),hub_tx);},
     Kind::Okx=>okx.push(route.clone()),
     _=>{
      let p=self.pending.entry(kind).or_insert_with(||Pending{routes:Vec::new(),since:now,last:now});
      if p.routes.iter().any(|r|r.venue.id==route.venue.id) {continue}
      p.routes.push(route.clone());p.last=now;
     },
    }
   }
  }
  // OKX：先填有空位的连接（装得最满的先填，少开连接），不够再开。
  while !okx.is_empty() {
   let target=self.slots.iter().filter(|(_,s)|s.kind==Kind::Okx&&s.venues.len()<Kind::Okx.capacity())
    .max_by_key(|(id,s)|(s.venues.len(),std::cmp::Reverse(**id))).map(|(id,_)|*id);
   match target {
    Some(id)=>{
     let slot=self.slots.get_mut(&id).expect("slot");
     let room=Kind::Okx.capacity()-slot.venues.len();
     let batch:Vec<Route>=okx.drain(..room.min(okx.len())).collect();
     for r in &batch {slot.venues.insert(r.venue.id.clone(),r.clone());}
     let _=slot.tx.send(ConnCmd::Assign(batch));
    },
    None=>{
     let batch:Vec<Route>=okx.drain(..Kind::Okx.capacity().min(okx.len())).collect();
     self.spawn(Kind::Okx,batch,Vec::new(),hub_tx);
    },
   }
  }
 }

 fn remove(&mut self,ids:&[String]) {
  let set:HashSet<&String>=ids.iter().collect();
  for p in self.pending.values_mut() {p.routes.retain(|r|!set.contains(&r.venue.id));}
  for slot in self.slots.values_mut() {
   let hit:Vec<String>=slot.venues.keys().filter(|id|set.contains(id)).cloned().collect();
   if hit.is_empty() {continue}
   for id in &hit {slot.venues.remove(id);}
   let _=slot.tx.send(ConnCmd::Drop(hit));
  }
 }

 fn resubscribe(&mut self,id:&str) {
  for slot in self.slots.values().filter(|s|matches!(s.kind,Kind::Okx|Kind::Coinbase)&&s.venues.contains_key(id)) {
   let _=slot.tx.send(ConnCmd::Resubscribe(id.to_string()));
  }
 }

 /// 新连接接手了：重叠期过后让旧连接退掉这些簿。
 fn up(&mut self,id:u64) {
  let Some(slot)=self.slots.get_mut(&id) else {return};
  slot.up=true;
  let replaces=std::mem::take(&mut slot.replaces);
  let at=Instant::now()+OVERLAP;
  for (old,ids) in replaces {self.drops.push((at,old,ids));}
 }

 fn due_drops(&mut self,now:Instant) {
  let (due,rest):(Vec<_>,Vec<_>)=std::mem::take(&mut self.drops).into_iter().partition(|(at,_,_)|*at<=now);
  self.drops=rest;
  for (_,old,ids) in due {
   let Some(slot)=self.slots.get_mut(&old) else {continue};
   for id in &ids {slot.venues.remove(id);}
   let _=slot.tx.send(ConnCmd::Drop(ids));
  }
 }

 /// 币安攒着的新簿到点了：和当前最小、装得下的那条合成一条新连接；没有装得下的就单开。
 fn flush(&mut self,now:Instant,hub_tx:&mpsc::UnboundedSender<HubCmd>) {
  let kinds:Vec<Kind>=self.pending.keys().copied().collect();
  for kind in kinds {
   let Some(p)=self.pending.get(&kind) else {continue};
   if p.routes.is_empty() {self.pending.remove(&kind);continue}
   let full=p.routes.len()>=kind.capacity();
   let due=full||now.duration_since(p.since)>=BATCH_MAX||(now.duration_since(p.since)>=BATCH_MIN&&now.duration_since(p.last)>=BATCH_QUIET);
   if !due {continue}
   let Some(p)=self.pending.remove(&kind) else {continue};
   let mut routes=p.routes;
   while !routes.is_empty() {
    let take=routes.len().min(kind.capacity());
    let batch:Vec<Route>=routes.drain(..take).collect();
    let target=self.slots.iter().filter(|(_,s)|s.kind==kind&&s.up&&!s.moving&&s.venues.len()+batch.len()<=kind.capacity())
     .min_by_key(|(id,s)|(s.venues.len(),**id)).map(|(id,_)|*id);
    match target {
     Some(old)=>{
      let slot=self.slots.get_mut(&old).expect("slot");
      slot.moving=true;
      let moved:Vec<Route>=slot.venues.values().cloned().collect();
      let ids:Vec<String>=moved.iter().map(|r|r.venue.id.clone()).collect();
      let mut all=moved;all.extend(batch);
      self.spawn(kind,all,vec![(old,ids)],hub_tx);
     },
     None=>{self.spawn(kind,batch,Vec::new(),hub_tx);},
    }
   }
  }
 }

 /// 每分钟一次、每种币安连接最多一个动作：到点的换新，否则把两条最小的合起来（合得下的话）。
 fn maintain(&mut self,now:Instant,hub_tx:&mpsc::UnboundedSender<HubCmd>) {
  for kind in KINDS.into_iter().filter(|k|k.binance()) {
   let candidates:Vec<u64>=self.slots.iter().filter(|(_,s)|s.kind==kind&&s.up&&!s.moving&&!s.venues.is_empty()).map(|(id,_)|*id).collect();
   if let Some(&old)=candidates.iter().filter(|id|self.slots[*id].rotate_at<=now).min_by_key(|id|self.slots[*id].born) {
    let slot=self.slots.get_mut(&old).expect("slot");
    slot.moving=true;
    let routes:Vec<Route>=slot.venues.values().cloned().collect();
    let ids:Vec<String>=routes.iter().map(|r|r.venue.id.clone()).collect();
    tracing::info!("Orderflow history: {} connection {old} renewed ahead of the 24h cut ({} books)",kind.label(),ids.len());
    self.spawn(kind,routes,vec![(old,ids)],hub_tx);
    continue;
   }
   let mut small:Vec<u64>=candidates.into_iter().filter(|id|now.duration_since(self.slots[id].born)>=COMPACT_AFTER).collect();
   small.sort_by_key(|id|(self.slots[id].venues.len(),*id));
   if let [a,b,..]=small[..] {
    if self.slots[&a].venues.len()+self.slots[&b].venues.len()<=kind.capacity() {
     let mut routes=Vec::new();
     let mut replaces=Vec::new();
     for old in [a,b] {
      let slot=self.slots.get_mut(&old).expect("slot");
      slot.moving=true;
      let moved:Vec<Route>=slot.venues.values().cloned().collect();
      replaces.push((old,moved.iter().map(|r|r.venue.id.clone()).collect()));
      routes.extend(moved);
     }
     tracing::info!("Orderflow history: {} connections {a} + {b} merged ({} books)",kind.label(),routes.len());
     self.spawn(kind,routes,replaces,hub_tx);
    }
   }
  }
 }

 fn report(&mut self) {
  let mut parts=Vec::new();
  for kind in KINDS {
   let slots:Vec<&Slot>=self.slots.values().filter(|s|s.kind==kind).collect();
   let frames=FRAMES[kind.index()].load(Ordering::Relaxed);
   let drops=DROPS[kind.index()].load(Ordering::Relaxed);
   let (df,dd)=(frames-self.frames[kind.index()],drops-self.drops_seen[kind.index()]);
   self.frames[kind.index()]=frames;self.drops_seen[kind.index()]=drops;
   if slots.is_empty()&&df==0 {continue}
   let books:usize=slots.iter().map(|s|s.venues.len()).sum();
   let streams:usize=slots.iter().map(|s|s.streams()).sum();
   let up=slots.iter().filter(|s|s.up).count();
   let pending=self.pending.get(&kind).map_or(0,|p|p.routes.len());
   parts.push(format!("{} {}/{} conns {books} books{} {df} frames{}",kind.label(),up,slots.len(),
    if kind.binance() {format!(" {streams} streams")} else {String::new()},
    if dd>0||pending>0 {format!(" ({dd} dropped, {pending} pending)")} else {String::new()}));
  }
  if !parts.is_empty() {tracing::info!("Orderflow history: connections per minute: {}",parts.join("; "));}
 }
}

/// 连接总数（资源闸门与日志用）。
pub fn connections()->usize {CONNECTION_COUNT.load(Ordering::Relaxed) as usize}
static CONNECTION_COUNT:AtomicU64=AtomicU64::new(0);

async fn manage(mut rx:mpsc::UnboundedReceiver<HubCmd>,hub_tx:mpsc::UnboundedSender<HubCmd>) {
 let mut pool=Pool::default();
 let mut tick=tokio::time::interval(Duration::from_secs(1));
 tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
 let mut maintain=tokio::time::interval_at(Instant::now()+MAINTAIN,MAINTAIN);
 loop {
  tokio::select! {
   cmd=rx.recv()=>match cmd {
    Some(HubCmd::Add(routes))=>pool.add(routes,&hub_tx),
    Some(HubCmd::Remove(ids))=>pool.remove(&ids),
    Some(HubCmd::Resubscribe(id))=>pool.resubscribe(&id),
    Some(HubCmd::Up(id))=>pool.up(id),
    Some(HubCmd::Gone(id))=>{pool.slots.remove(&id);},
    None=>return,
   },
   _=tick.tick()=>{let now=Instant::now();pool.due_drops(now);pool.flush(now,&hub_tx);},
   _=maintain.tick()=>{pool.maintain(Instant::now(),&hub_tx);pool.report();},
  }
  CONNECTION_COUNT.store(pool.slots.len() as u64,Ordering::Relaxed);
 }
}

// ------------------------------------------------------------------ 一条连接

type Ws=tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

async fn open(kind:Kind,url:&str)->anyhow::Result<Ws> {
 permit(kind).await;
 match tokio::time::timeout(CONNECT,tokio_tungstenite::connect_async(url)).await {
  Ok(Ok((ws,_)))=>Ok(ws),
  Ok(Err(tungstenite::Error::Http(reply)))=>{
   if kind.binance()&&kind!=Kind::BinanceSpot {binance_gate::note(reply.status().as_u16(),reply.headers().get("retry-after").and_then(|v|v.to_str().ok()));}
   anyhow::bail!("handshake refused with {}",reply.status())
  },
  Ok(Err(e))=>Err(e.into()),
  Err(_)=>anyhow::bail!("handshake timed out"),
 }
}

/// 一条连接挂着的簿与解码器。
struct Conn {kind:Kind,routes:HashMap<String,Route>,decoder:Decoder}

impl Conn {
 fn insert(&mut self,route:Route) {self.decoder.insert(&route.venue);self.routes.insert(route.venue.id.clone(),route);}
 fn drop_ids(&mut self,ids:&[String])->Vec<Route> {
  ids.iter().filter_map(|id|self.routes.remove(id)).inspect(|r|self.decoder.remove(&r.venue)).collect()
 }
 fn url(&self)->String {
  let mut venues:Vec<&VenueInfo>=self.routes.values().map(|r|&r.venue).collect();
  venues.sort_by(|a,b|a.id.cmp(&b.id));
  self.kind.url(&venues)
 }
 fn instruments(&self)->Vec<String> {self.routes.values().map(|r|r.venue.instrument.clone()).collect()}

 /// 给这些簿各自的跟踪器发一条要紧的（Opened / Handover / Closed）。只订成交的连接不发。
 async fn announce(&self,routes:&[&Route],make:impl Fn(Vec<String>)->Event) {
  if !self.kind.carries_books() {return}
  for r in routes {
   if r.events.is_closed() {continue}
   let _=tokio::time::timeout(DELIVER,r.events.send(make(vec![r.venue.id.clone()]))).await;
  }
 }

 /// 帧送给跟踪器：堵住了就丢（记数），不拖别的币。
 fn deliver(&self,decoded:Decoded,connection:u64) {
  let (id,event)=match decoded {
   Decoded::Book(venue,message)=>(venue.clone(),Event::Frame{venue,connection,message}),
   Decoded::Trade(venue,trade,id)=>(venue.clone(),Event::Trade{venue,trade,id}),
  };
  let Some(route)=self.routes.get(&id) else {return};
  FRAMES[self.kind.index()].fetch_add(1,Ordering::Relaxed);
  if let Err(mpsc::error::TrySendError::Full(_))=route.events.try_send(event) {DROPS[self.kind.index()].fetch_add(1,Ordering::Relaxed);}
 }
}

/// 离线（退避中）收到的命令：只改挂着的簿。
fn apply_offline(conn:&mut Conn,cmd:ConnCmd) {
 match cmd {
  ConnCmd::Assign(routes)=>for r in routes {conn.insert(r)},
  ConnCmd::Drop(ids)=>{conn.drop_ids(&ids);},
  ConnCmd::Resubscribe(_)=>{},
 }
}

async fn send_text(tx:&mut futures_util::stream::SplitSink<Ws,Up>,text:String)->bool {
 matches!(tokio::time::timeout(SEND,tx.send(Up::Text(text.into()))).await,Ok(Ok(())))
}

/// 一条连接的一生：连上（首次连上按交接通知、之后按重连通知）、转帧、跟池子的命令增删簿，
/// 断了抖动退避重连；挂着的簿退光了就结束。
async fn run(slot:u64,kind:Kind,routes:Vec<Route>,mut cmds:mpsc::UnboundedReceiver<ConnCmd>,hub_tx:mpsc::UnboundedSender<HubCmd>) {
 let mut conn=Conn{kind,routes:HashMap::new(),decoder:Decoder::new(kind)};
 for r in routes {conn.insert(r);}
 let mut backoff=Duration::from_secs(1);
 let mut first=true;
 let mut cmds_open=true;
 'life: loop {
  if conn.routes.is_empty()||conn.routes.values().all(|r|r.events.is_closed()) {break}
  let ws=match open(kind,&conn.url()).await {
   Ok(ws)=>ws,
   Err(e)=>{
    tracing::debug!("Orderflow history: {} connection {slot} unreachable: {e}",kind.label());
    let until=Instant::now()+jittered(backoff);
    backoff=(backoff*2).min(Duration::from_secs(30));
    loop {
     tokio::select! {
      cmd=cmds.recv(),if cmds_open=>match cmd {Some(c)=>apply_offline(&mut conn,c),None=>cmds_open=false},
      _=tokio::time::sleep_until(until)=>break,
     }
     if conn.routes.is_empty() {break 'life}
    }
    continue;
   },
  };
  let connection=feeds::next_connection();
  let (mut tx,mut rx)=ws.split();
  let mut ok=true;
  // OKX 每条连接一小时内的订退请求时刻。
  let mut ops:VecDeque<Instant>=VecDeque::new();
  match kind {
   Kind::Okx=>{
    let instruments=conn.instruments();
    let refs:Vec<&str>=instruments.iter().map(String::as_str).collect();
    for text in feeds::okx_ops("subscribe",&refs,false) {ops.push_back(Instant::now());if !send_text(&mut tx,text).await {ok=false;break}}
   },
   Kind::Coinbase=>{
    let product=conn.routes.values().next().map(|r|r.venue.instrument.clone()).unwrap_or_default();
    for text in feeds::coinbase_subscribe(&product) {if !send_text(&mut tx,text).await {ok=false;break}}
   },
   _=>{},
  }
  let all:Vec<Route>=conn.routes.values().cloned().collect();
  let refs:Vec<&Route>=all.iter().collect();
  // 首次连上：可能是接手旧连接上的簿（换新 / 合并），也可能是全新的簿——跟踪器按簿此刻连没连着分辨。
  if first {conn.announce(&refs,|venues|Event::Handover{venues,connection}).await} else {conn.announce(&refs,|venues|Event::Opened{venues,connection}).await}
  let started=Instant::now();
  let mut announced_up=!first;
  let up_deadline=started+UP_AFTER;
  first=false;
  let mut ping=tokio::time::interval_at(Instant::now()+PING,PING);
  let mut flush=tokio::time::interval_at(Instant::now()+OKX_FLUSH,OKX_FLUSH);
  let mut deadline=Instant::now()+IDLE;
  let (mut to_sub,mut to_unsub,mut to_resub):(Vec<String>,Vec<String>,Vec<String>)=(Vec::new(),Vec::new(),Vec::new());
  while ok {
   tokio::select! {
    frame=rx.next()=>{
     let text=match frame {
      Some(Ok(Up::Text(text)))=>text,
      Some(Ok(Up::Close(_)))|Some(Err(_))|None=>break,
      Some(Ok(_))=>{deadline=Instant::now()+IDLE;continue},
     };
     deadline=Instant::now()+IDLE;
     if !announced_up {announced_up=true;let _=hub_tx.send(HubCmd::Up(slot));}
     if kind==Kind::Okx&&let Some(error)=Decoder::okx_error(text.as_str()) {tracing::warn!("Orderflow history: okx connection {slot} error {error}");continue}
     for decoded in conn.decoder.decode(text.as_str()) {conn.deliver(decoded,connection);}
    },
    cmd=cmds.recv(),if cmds_open=>match cmd {
     None=>cmds_open=false,
     Some(ConnCmd::Assign(routes))=>{
      let fresh:Vec<Route>=routes.into_iter().filter(|r|!conn.routes.contains_key(&r.venue.id)).collect();
      for r in &fresh {to_sub.push(r.venue.instrument.clone());conn.insert(r.clone());}
      let refs:Vec<&Route>=fresh.iter().collect();
      conn.announce(&refs,|venues|Event::Opened{venues,connection}).await;
     },
     Some(ConnCmd::Drop(ids))=>{
      let dropped=conn.drop_ids(&ids);
      if kind==Kind::Okx {to_unsub.extend(dropped.iter().map(|r|r.venue.instrument.clone()));}
      let refs:Vec<&Route>=dropped.iter().collect();
      conn.announce(&refs,|venues|Event::Closed{venues,connection}).await;
      if conn.routes.is_empty() {let _=tokio::time::timeout(Duration::from_secs(1),tx.close()).await;break 'life}
     },
     Some(ConnCmd::Resubscribe(id))=>match kind {
      Kind::Okx=>if let Some(r)=conn.routes.get(&id) {to_resub.push(r.venue.instrument.clone())},
      // Coinbase 的序号按整条连接计，只能整条重连。
      _=>break,
     },
    },
    _=flush.tick(),if kind==Kind::Okx=>{
     let now=Instant::now();
     while ops.front().is_some_and(|t|now.duration_since(*t)>=Duration::from_secs(3600)) {ops.pop_front();}
     let mut batches=Vec::new();
     let (sub,unsub,resub)=(std::mem::take(&mut to_sub),std::mem::take(&mut to_unsub),std::mem::take(&mut to_resub));
     let refs=|v:&Vec<String>|v.iter().map(String::as_str).map(str::to_string).collect::<Vec<String>>();
     let (sub,unsub,resub)=(refs(&sub),refs(&unsub),refs(&resub));
     let s:Vec<&str>=sub.iter().map(String::as_str).collect();
     let u:Vec<&str>=unsub.iter().map(String::as_str).collect();
     let r:Vec<&str>=resub.iter().map(String::as_str).collect();
     batches.extend(feeds::okx_ops("unsubscribe",&u,false));
     batches.extend(feeds::okx_ops("unsubscribe",&r,true));
     batches.extend(feeds::okx_ops("subscribe",&r,true));
     batches.extend(feeds::okx_ops("subscribe",&s,false));
     if batches.is_empty() {continue}
     // 这条连接一小时的订退额度快用完了：整条重连（重连后订全部，额度重算），不去撞 480。
     if ops.len()+batches.len()>OKX_OPS_PER_HOUR {
      tracing::info!("Orderflow history: okx connection {slot} used {} subscribe ops this hour, reconnecting",ops.len());
      break;
     }
     for text in batches {ops.push_back(now);if !send_text(&mut tx,text).await {ok=false;break}}
    },
    _=ping.tick()=>{
     let frame=if kind==Kind::Okx {Up::Text("ping".into())} else {Up::Ping(Default::default())};
     if !matches!(tokio::time::timeout(SEND,tx.send(frame)).await,Ok(Ok(()))) {break}
    },
    _=tokio::time::sleep_until(up_deadline),if !announced_up=>{announced_up=true;let _=hub_tx.send(HubCmd::Up(slot));},
    _=tokio::time::sleep_until(deadline)=>{tracing::debug!("Orderflow history: {} connection {slot} silent for {IDLE:?}",kind.label());break},
   }
  }
  let _=tokio::time::timeout(Duration::from_secs(1),tx.close()).await;
  let all:Vec<Route>=conn.routes.values().cloned().collect();
  let refs:Vec<&Route>=all.iter().collect();
  conn.announce(&refs,|venues|Event::Closed{venues,connection}).await;
  // 活过一分钟的算正常断开，退避从头来。
  if started.elapsed()>Duration::from_secs(60) {backoff=Duration::from_secs(1)}
  let until=Instant::now()+jittered(backoff);
  backoff=(backoff*2).min(Duration::from_secs(30));
  loop {
   tokio::select! {
    cmd=cmds.recv(),if cmds_open=>match cmd {Some(c)=>apply_offline(&mut conn,c),None=>cmds_open=false},
    _=tokio::time::sleep_until(until)=>break,
   }
   if conn.routes.is_empty() {break 'life}
  }
 }
 let _=hub_tx.send(HubCmd::Gone(slot));
}

#[cfg(test)]
mod tests {
 use super::*;
 use super::super::book::Sequence;
 use super::super::model::Notional;

 fn route(exchange:&'static str,product:&'static str,instrument:&str,events:&mpsc::Sender<Event>)->Route {
  let notional=if product=="coinPerp" {Notional::Inverse(100.0)} else {Notional::Linear(1.0)};
  Route{venue:VenueInfo{id:format!("{exchange}:{product}:{instrument}"),exchange,label:"x",product,instrument:instrument.into(),notional,price_scale:1.0,
   sequence:Sequence::PreviousFinalOverlap,in_band:exchange!="binance"},events:events.clone()}
 }

 /// 池子的排布（不开连接：连接任务起在测试运行时里，连不上外网也只是退避）。
 #[tokio::test(start_paused=true)] async fn binance_batches_merge_into_the_smallest_connection_and_okx_fills_up() {
  let (events,_rx)=mpsc::channel(8);
  let (hub_tx,_hub_rx)=mpsc::unbounded_channel();
  let mut pool=Pool::default();
  let t0=Instant::now();
  pool.add(vec![route("binance","usdtPerp","AUSDT",&events),route("binance","spot","AUSDT",&events),route("okx","usdtPerp","A-USDT-SWAP",&events),route("coinbase","spot","A-USD",&events)],&hub_tx);
  // Coinbase 立刻开；OKX 立刻开（没有能填的）；币安攒着。
  assert_eq!(pool.slots.len(),2);
  assert_eq!(pool.pending[&Kind::BinanceUmDepth].routes.len(),1);
  assert_eq!(pool.pending[&Kind::BinanceUmTrades].routes.len(),1);
  pool.flush(t0+Duration::from_secs(3),&hub_tx);
  assert_eq!(pool.slots.len(),2,"不到 5 秒不建");
  pool.flush(t0+BATCH_MIN+BATCH_QUIET,&hub_tx);
  assert_eq!(pool.slots.len(),5,"U 本位深度、成交、现货各一条");
  let depth=*pool.slots.iter().find(|(_,s)|s.kind==Kind::BinanceUmDepth).unwrap().0;
  pool.up(depth);
  // 再来一本：并进那条已有的，新连接接手旧连接上的簿。
  pool.add(vec![route("binance","usdtPerp","BUSDT",&events),route("okx","usdtPerp","B-USDT-SWAP",&events)],&hub_tx);
  assert_eq!(pool.slots.values().filter(|s|s.kind==Kind::Okx).count(),1,"OKX 填进已有的那条");
  assert_eq!(pool.slots.values().find(|s|s.kind==Kind::Okx).unwrap().venues.len(),2);
  pool.flush(t0+Duration::from_secs(30),&hub_tx);
  let merged:Vec<&Slot>=pool.slots.values().filter(|s|s.kind==Kind::BinanceUmDepth).collect();
  assert_eq!(merged.len(),2);
  let new=merged.iter().find(|s|!s.replaces.is_empty()).expect("new connection replaces the old");
  assert_eq!(new.venues.len(),2);
  assert_eq!(new.replaces,vec![(depth,vec!["binance:usdtPerp:AUSDT".to_string()])]);
  assert!(pool.slots[&depth].moving);
  // 同一本不会重复挂。
  pool.add(vec![route("binance","usdtPerp","BUSDT",&events)],&hub_tx);
  assert!(pool.pending.get(&Kind::BinanceUmDepth).is_none_or(|p|p.routes.is_empty()));
  // 退掉：从所有挂着它的连接上拿下。
  pool.remove(&["binance:usdtPerp:AUSDT".to_string()]);
  assert!(pool.slots.values().all(|s|!s.venues.contains_key("binance:usdtPerp:AUSDT")));
 }

 #[tokio::test(start_paused=true)] async fn renewal_and_merge_after_the_new_one_is_up() {
  let (events,_rx)=mpsc::channel(8);
  let (hub_tx,_hub_rx)=mpsc::unbounded_channel();
  let mut pool=Pool::default();
  let a=pool.spawn(Kind::BinanceUmDepth,vec![route("binance","usdtPerp","AUSDT",&events)],Vec::new(),&hub_tx);
  let b=pool.spawn(Kind::BinanceUmDepth,vec![route("binance","usdtPerp","BUSDT",&events)],Vec::new(),&hub_tx);
  pool.up(a);pool.up(b);
  let t=Instant::now()+COMPACT_AFTER;
  pool.maintain(t,&hub_tx);
  let merged=pool.slots.iter().find(|(id,_)|**id!=a&&**id!=b).map(|(id,_)|*id).expect("merged");
  assert_eq!(pool.slots[&merged].venues.len(),2);
  pool.up(merged);
  pool.due_drops(Instant::now());
  assert_eq!(pool.slots[&a].venues.len(),1,"重叠期里旧连接还挂着");
  pool.due_drops(Instant::now()+OVERLAP+Duration::from_millis(1));
  assert!(pool.slots[&a].venues.is_empty()&&pool.slots[&b].venues.is_empty(),"重叠期过后旧连接退光");
  // 到 23 小时（+ 抖动）换新。
  let late=Instant::now()+ROTATE_AFTER+Duration::from_secs(ROTATE_JITTER_SECS+1);
  pool.slots.remove(&a);pool.slots.remove(&b);
  pool.maintain(late,&hub_tx);
  assert!(pool.slots[&merged].moving);
  assert_eq!(pool.slots.len(),2);
 }

 #[test] fn pacing_is_per_exchange_family() {
  let (b,p)=pace(Kind::BinanceSpot);
  assert_eq!((b,p.max,p.window),(0,60,Duration::from_secs(300)),"币安 5 分钟最多 60 条（IP 额度 300 的五分之一）");
  assert_eq!(pace(Kind::BinanceUmDepth).0,pace(Kind::BinanceCm).0);
  let (o,p)=pace(Kind::Okx);
  assert!(o!=b&&p.max<=3&&p.gap>=Duration::from_millis(334),"OKX 每秒最多 3 条");
  for _ in 0..100 {let j=jittered(Duration::from_secs(10));assert!(j>=Duration::from_secs(5)&&j<=Duration::from_secs(15));}
 }
}
