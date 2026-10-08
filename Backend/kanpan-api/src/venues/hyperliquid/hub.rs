//! Hyperliquid 的进程级共用上游。
//!
//! Hyperliquid 的限流是按 IP 的硬限：每 IP 最多 10 条 WS、每分钟最多 30 条新连接、最多 1000 个订阅、
//! 每分钟最多 2000 条上行消息。所以整个进程只开**一条**上游，常驻跟踪与给手机 / 网页的中继都从这里拿：
//!
//! * 每个使用方 `join` 一次拿到一个 `Link`：一条收帧的通道加一个订退把手。把手（连同它的全部克隆）
//!   丢掉就算离开，它订着的全部退掉。
//! * 订阅按 (频道, 币) 引用计数：第一个人订时才向上游订，最后一个人退时才向上游退。
//! * `l2Book` / `trades` / `activeAssetCtx` 帧按 `data.coin`、`candle` 帧按 `data.s` + `data.i` 只发给订了它的使用方；
//!   `l2Book`（整本）、`candle`（正在走的那一根）、`activeAssetCtx`（标记价、费率、持仓量）手上留最近一帧，
//!   后来订的人马上先拿到它，不必等下一帧。
//! * 上游的 `subscriptionResponse` 发给发起那次订阅的使用方；订的东西上游早就订着时由这里答一份
//!   同样形状的回执。
//! * 上游断了（或 `silence` 没有任何帧）就按退避重连，连上后把手上全部订阅重新发一遍；使用方只看到
//!   一个 `Down` 再一个 `Up`，通道不断。
//! * 上行消息（订、退、心跳）排队按 `gap` 一条一条发，`gap` 34 ms ≈ 每分钟 1760 条，低于 2000 的硬限；
//!   新连接之间至少隔 `connect_gap`（2 秒，每分钟最多 30 条）。
//! * 订阅总数封顶 `max_topics`（900，硬限 1000），其中常驻跟踪最多占 `max_tracking`（600），
//!   给中继留出余量。超了的订阅答一帧 `{"channel":"error",…}`，不向上游发。
//! * 收帧跟不上的中继（通道满了）直接踢掉：手机那头断开重连，比悄悄丢帧好；常驻跟踪跟不上只丢帧、计数。
use futures_util::{SinkExt,StreamExt};
use serde::Deserialize;
use serde_json::{Value,json,value::RawValue};
use std::borrow::Cow;
use std::collections::{HashMap,HashSet,VecDeque};
use std::future::Future;
use std::pin::Pin;
use std::sync::atomic::{AtomicBool,AtomicU64,AtomicUsize,Ordering};
use std::sync::{Arc,OnceLock};
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::time::Instant;
use tokio_tungstenite::tungstenite::Message;

/// 上游地址。
pub const WS:&str="wss://api.hyperliquid.xyz/ws";

/// hub 的节拍与上限（测试里换成自己的）。
#[derive(Clone,Copy,Debug)]
pub struct Limits {
 /// 同时订着的 (频道, 币) 最多几个。
 pub max_topics:usize,
 /// 其中常驻跟踪最多占几个。
 pub max_tracking:usize,
 /// 两条上行消息之间至少隔多久。
 pub gap:Duration,
 /// 多久发一次心跳。
 pub ping:Duration,
 /// 上游多久没有任何帧就断开重连。
 pub silence:Duration,
 /// 握手最多等多久。
 pub connect:Duration,
 /// 两次新建连接之间至少隔多久。
 pub connect_gap:Duration,
 /// 重连退避的起点与封顶（再 ±50% 抖动）。
 pub backoff_min:Duration,
 pub backoff_max:Duration,
 /// 最后一个订阅退掉之后，上游连接再留多久。
 pub linger:Duration,
 /// 往上游发一帧最多等多久。
 pub send:Duration,
}

pub const LIMITS:Limits=Limits{
 max_topics:900,
 max_tracking:600,
 gap:Duration::from_millis(34),
 ping:Duration::from_secs(20),
 silence:Duration::from_secs(60),
 connect:Duration::from_secs(15),
 connect_gap:Duration::from_secs(2),
 backoff_min:Duration::from_secs(1),
 backoff_max:Duration::from_secs(30),
 linger:Duration::from_secs(60),
 send:Duration::from_secs(10),
};

// ------------------------------------------------------------------ 订阅

/// 频道。`Candle` 带周期（只收 [`super::INTERVALS`] 里那几档，所以是 `&'static str`）。
#[derive(Clone,Copy,Debug,PartialEq,Eq,Hash,PartialOrd,Ord)]
pub enum Channel {L2Book,Trades,Candle(&'static str),AssetCtx}

/// 一个订阅：频道 + 币。`l2Book` 一律 4 位有效数字（`nSigFigs:4`）。
#[derive(Clone,Debug,PartialEq,Eq,Hash,PartialOrd,Ord)]
pub struct Topic {pub channel:Channel,pub coin:String}

/// 币名：`^[A-Za-z0-9]{1,16}$`（`BTC`、`kPEPE`）。
pub fn valid_coin(coin:&str)->bool {(1..=16).contains(&coin.len())&&coin.bytes().all(|b|b.is_ascii_alphanumeric())}

/// 周期 → 静态的那一个（不认识的是 `None`）。
pub fn interval(text:&str)->Option<&'static str> {super::INTERVALS.iter().copied().find(|i|*i==text)}

impl Topic {
 pub fn book(coin:impl Into<String>)->Self {Self{channel:Channel::L2Book,coin:coin.into()}}
 pub fn trades(coin:impl Into<String>)->Self {Self{channel:Channel::Trades,coin:coin.into()}}
 pub fn candle(coin:impl Into<String>,interval:&'static str)->Self {Self{channel:Channel::Candle(interval),coin:coin.into()}}
 pub fn asset_ctx(coin:impl Into<String>)->Self {Self{channel:Channel::AssetCtx,coin:coin.into()}}
 /// 上游认的订阅对象。
 pub fn subscription(&self)->Value {
  match self.channel {
   Channel::L2Book=>json!({"type":"l2Book","coin":self.coin,"nSigFigs":4}),
   Channel::Trades=>json!({"type":"trades","coin":self.coin}),
   Channel::Candle(interval)=>json!({"type":"candle","coin":self.coin,"interval":interval}),
   Channel::AssetCtx=>json!({"type":"activeAssetCtx","coin":self.coin}),
  }
 }
 /// 这一频道的帧要不要留最近一帧给后来者（逐笔不留：补一帧旧成交没有意义）。
 fn keeps_last(&self)->bool {self.channel!=Channel::Trades}
 /// 一条订 / 退消息。
 pub fn message(&self,subscribe:bool)->String {
  json!({"method":if subscribe {"subscribe"} else {"unsubscribe"},"subscription":self.subscription()}).to_string()
 }
 /// 从上游回执里的订阅对象认出是哪一个（回执多带的 `mantissa` / `fast` 之类不管）。
 /// 只认 4 位有效数字的 `l2Book` 与 `trades`。
 pub fn of(subscription:&Value)->Option<Self> {
  let coin=subscription.get("coin")?.as_str()?;
  if !valid_coin(coin) {return None}
  match subscription.get("type")?.as_str()? {
   "l2Book" if subscription.get("nSigFigs").and_then(Value::as_u64)==Some(4)=>Some(Self::book(coin)),
   "trades"=>Some(Self::trades(coin)),
   "candle"=>Some(Self::candle(coin,interval(subscription.get("interval")?.as_str()?)?)),
   "activeAssetCtx"=>Some(Self::asset_ctx(coin)),
   _=>None,
  }
 }
}

/// 发给使用方的东西。
#[derive(Clone,Debug)]
pub enum Feed {
 /// 上游连上了（或者加入时它已经连着）。
 Up,
 /// 上游断了；hub 自己会重连并重订，使用方不用做什么。
 Down,
 /// 一帧上游原文（`l2Book` / `trades` / `subscriptionResponse`），或者 hub 自己答的一帧同形状的。
 Text(Arc<str>),
}

/// 使用方是谁：决定它占哪一份名额、跟不上时怎么办。
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum Class {Relay,Tracking}

enum Cmd {
 Join {id:u64,class:Class,tx:mpsc::Sender<Feed>},
 Leave(u64),
 Subscribe(u64,Topic),
 Unsubscribe(u64,Topic),
}

/// 进程里那一个 hub 的计数（给日志）。
#[derive(Default)]
pub struct Counters {
 pub up:AtomicBool,
 pub topics:AtomicUsize,
 pub tracking:AtomicUsize,
 pub clients:AtomicUsize,
 pub frames:AtomicU64,
 pub drops:AtomicU64,
 pub connects:AtomicU64,
 pub sent:AtomicU64,
}

#[derive(Clone)]
pub struct Hub {tx:mpsc::UnboundedSender<Cmd>,next:Arc<AtomicU64>,pub counters:Arc<Counters>}

/// 一个使用方手上的东西。
pub struct Link {pub rx:mpsc::Receiver<Feed>,pub handle:Handle}

/// 订退把手。全部克隆都丢掉时算离开。
#[derive(Clone)]
pub struct Handle {id:u64,tx:mpsc::UnboundedSender<Cmd>,_leave:Arc<Leave>}
struct Leave {id:u64,tx:mpsc::UnboundedSender<Cmd>}
impl Drop for Leave {fn drop(&mut self) {let _=self.tx.send(Cmd::Leave(self.id));}}

impl Handle {
 pub fn subscribe(&self,topic:Topic) {let _=self.tx.send(Cmd::Subscribe(self.id,topic));}
 pub fn unsubscribe(&self,topic:Topic) {let _=self.tx.send(Cmd::Unsubscribe(self.id,topic));}
}

impl Hub {
 /// 起一个 hub（要在 tokio 运行时里调）。上游等到有人订了东西才连。
 pub fn start(url:String,limits:Limits)->Self {
  let (tx,rx)=mpsc::unbounded_channel();
  let counters=Arc::new(Counters::default());
  crate::supervise::spawn_logged("hyperliquid-hub",crate::supervise::Life::Once,run(rx,State::new(url,limits,counters.clone())));
  Self{tx,next:Arc::new(AtomicU64::new(1)),counters}
 }
 /// 加入：`capacity` 是这个使用方的收帧通道能攒几帧。
 pub fn join(&self,class:Class,capacity:usize)->Link {
  let id=self.next.fetch_add(1,Ordering::Relaxed);
  let (tx,rx)=mpsc::channel(capacity.max(1));
  let _=self.tx.send(Cmd::Join{id,class,tx});
  Link{rx,handle:Handle{id,tx:self.tx.clone(),_leave:Arc::new(Leave{id,tx:self.tx.clone()})}}
 }
}

/// 进程里共用的那一个（第一次用时起；要在 tokio 运行时里）。
pub fn shared()->&'static Hub {
 static H:OnceLock<Hub>=OnceLock::new();
 H.get_or_init(||Hub::start(WS.to_owned(),LIMITS))
}

/// 已经起过的话给出共用那个的计数，没起过就是 `None`（不为了打日志把它起起来）。
pub fn shared_counters()->Option<Arc<Counters>> {SHARED_COUNTERS.get().cloned()}
static SHARED_COUNTERS:OnceLock<Arc<Counters>>=OnceLock::new();

// ------------------------------------------------------------------ 状态

struct Client {tx:mpsc::Sender<Feed>,class:Class,topics:HashSet<Topic>}

#[derive(Default)]
struct TopicState {
 subs:HashSet<u64>,
 /// 这一次连接上，上游回过这条订阅的回执了没有。
 confirmed:bool,
 /// 等上游回执的使用方。
 pending:Vec<u64>,
 /// 最近一帧（逐笔不留）。
 last:Option<Arc<str>>,
}

struct State {
 url:String,
 limits:Limits,
 counters:Arc<Counters>,
 clients:HashMap<u64,Client>,
 topics:HashMap<Topic,TopicState>,
 queue:VecDeque<String>,
 connected:bool,
}

fn response(method:&str,topic:&Topic)->Arc<str> {
 json!({"channel":"subscriptionResponse","data":{"method":method,"subscription":topic.subscription()}}).to_string().into()
}
fn refusal(topic:&Topic)->Arc<str> {
 json!({"channel":"error","data":format!("subscription limit reached: {}",topic.message(true))}).to_string().into()
}

#[derive(Deserialize)]
struct Head<'a> {#[serde(borrow)] channel:Cow<'a,str>,#[serde(borrow,default)] data:Option<&'a RawValue>}
#[derive(Deserialize)]
struct CoinOnly {coin:String}
/// `candle` 帧的 `data`：币在 `s`、周期在 `i`。
#[derive(Deserialize)]
struct CandleHead {s:String,i:String}
#[derive(Deserialize)]
struct Ack {method:String,subscription:Value}

impl State {
 fn new(url:String,limits:Limits,counters:Arc<Counters>)->Self {
  Self{url,limits,counters,clients:HashMap::new(),topics:HashMap::new(),queue:VecDeque::new(),connected:false}
 }

 fn tracking_topics(&self)->usize {
  self.topics.values().filter(|t|t.subs.iter().any(|id|self.clients.get(id).is_some_and(|c|c.class==Class::Tracking))).count()
 }

 fn publish_counts(&self) {
  self.counters.topics.store(self.topics.len(),Ordering::Relaxed);
  self.counters.tracking.store(self.tracking_topics(),Ordering::Relaxed);
  self.counters.clients.store(self.clients.len(),Ordering::Relaxed);
 }

 /// 发给一个使用方；跟不上的中继踢掉（返回 `false`）。
 fn send_to(&mut self,id:u64,feed:Feed)->bool {
  let Some(client)=self.clients.get(&id) else {return true};
  match client.tx.try_send(feed) {
   Ok(())=>true,
   Err(mpsc::error::TrySendError::Full(_)) if client.class==Class::Tracking=>{self.counters.drops.fetch_add(1,Ordering::Relaxed);true},
   Err(_)=>false,
  }
 }

 fn deliver(&mut self,ids:Vec<u64>,text:&Arc<str>) {
  let mut gone=Vec::new();
  for id in ids {if !self.send_to(id,Feed::Text(text.clone())) {gone.push(id);}}
  for id in gone {
   tracing::info!("Hyperliquid hub: client {id} fell behind or left, dropping it");
   self.leave(id);
  }
 }

 fn broadcast(&mut self,feed:Feed) {
  let ids:Vec<u64>=self.clients.keys().copied().collect();
  let mut gone=Vec::new();
  for id in ids {if !self.send_to(id,feed.clone()) {gone.push(id);}}
  for id in gone {self.leave(id);}
 }

 fn command(&mut self,cmd:Cmd) {
  match cmd {
   Cmd::Join{id,class,tx}=>{
    if self.connected {let _=tx.try_send(Feed::Up);}
    self.clients.insert(id,Client{tx,class,topics:HashSet::new()});
   },
   Cmd::Leave(id)=>self.leave(id),
   Cmd::Subscribe(id,topic)=>self.subscribe(id,topic),
   Cmd::Unsubscribe(id,topic)=>{
    let had=self.clients.get_mut(&id).is_some_and(|c|c.topics.remove(&topic));
    if had {
     self.release(id,&topic);
     let text=response("unsubscribe",&topic);
     self.deliver(vec![id],&text);
    }
   },
  }
  self.publish_counts();
 }

 fn subscribe(&mut self,id:u64,topic:Topic) {
  let Some(client)=self.clients.get(&id) else {return};
  let class=client.class;
  if client.topics.contains(&topic) {
   let text=response("subscribe",&topic);
   self.deliver(vec![id],&text);
   return;
  }
  let existing=self.topics.get(&topic);
  let tracked=existing.is_some_and(|t|t.subs.iter().any(|s|self.clients.get(s).is_some_and(|c|c.class==Class::Tracking)));
  let over=(existing.is_none()&&self.topics.len()>=self.limits.max_topics)
   ||(class==Class::Tracking&&!tracked&&self.tracking_topics()>=self.limits.max_tracking);
  if over {
   tracing::warn!("Hyperliquid hub: refused {:?} {} ({} topics, {} for tracking)",topic.channel,topic.coin,self.topics.len(),self.tracking_topics());
   let text=refusal(&topic);
   self.deliver(vec![id],&text);
   return;
  }
  if let Some(client)=self.clients.get_mut(&id) {client.topics.insert(topic.clone());}
  let fresh=!self.topics.contains_key(&topic);
  let state=self.topics.entry(topic.clone()).or_default();
  state.subs.insert(id);
  if state.confirmed {
   let last=state.last.clone();
   let text=response("subscribe",&topic);
   self.deliver(vec![id],&text);
   if let Some(last)=last {self.deliver(vec![id],&last);}
  } else {
   state.pending.push(id);
   if fresh&&self.connected {self.queue.push_back(topic.message(true));}
  }
 }

 fn release(&mut self,id:u64,topic:&Topic) {
  let Some(state)=self.topics.get_mut(topic) else {return};
  state.subs.remove(&id);
  state.pending.retain(|p|*p!=id);
  if state.subs.is_empty() {
   self.topics.remove(topic);
   if self.connected {self.queue.push_back(topic.message(false));}
  }
 }

 fn leave(&mut self,id:u64) {
  let Some(client)=self.clients.remove(&id) else {return};
  for topic in client.topics {self.release(id,&topic);}
  self.publish_counts();
 }

 fn on_up(&mut self) {
  self.connected=true;
  self.counters.up.store(true,Ordering::Relaxed);
  self.queue.clear();
  let mut topics:Vec<Topic>=self.topics.keys().cloned().collect();
  topics.sort();
  for topic in topics {self.queue.push_back(topic.message(true));}
  self.broadcast(Feed::Up);
 }

 fn on_down(&mut self) {
  self.connected=false;
  self.counters.up.store(false,Ordering::Relaxed);
  self.queue.clear();
  for state in self.topics.values_mut() {state.confirmed=false;state.last=None;}
  self.broadcast(Feed::Down);
 }

 /// 一帧发给订了 `topic` 的全部使用方；该留最近一帧的留着。
 fn fan_out(&mut self,topic:&Topic,text:&str) {
  let Some(state)=self.topics.get_mut(topic) else {return};
  let text:Arc<str>=text.into();
  if topic.keeps_last() {state.last=Some(text.clone());}
  let ids:Vec<u64>=state.subs.iter().copied().collect();
  self.counters.frames.fetch_add(1,Ordering::Relaxed);
  self.deliver(ids,&text);
 }

 fn upstream(&mut self,text:&str) {
  let Ok(head)=serde_json::from_str::<Head>(text) else {return};
  match head.channel.as_ref() {
   "l2Book"|"activeAssetCtx"=>{
    let Some(coin)=head.data.and_then(|d|serde_json::from_str::<CoinOnly>(d.get()).ok()) else {return};
    let topic=if head.channel=="l2Book" {Topic::book(coin.coin)} else {Topic::asset_ctx(coin.coin)};
    self.fan_out(&topic,text);
   },
   "candle"=>{
    // 官方文档写的是 `Candle[]`，实际推的是单个对象：两种都认，按第一根定是哪个订阅。
    let Some(data)=head.data else {return};
    let first=serde_json::from_str::<CandleHead>(data.get()).ok().or_else(||serde_json::from_str::<Vec<CandleHead>>(data.get()).ok().and_then(|v|v.into_iter().next()));
    let Some(candle)=first else {return};
    let Some(interval)=interval(&candle.i) else {return};
    self.fan_out(&Topic::candle(candle.s,interval),text);
   },
   "trades"=>{
    let Some(rows)=head.data.and_then(|d|serde_json::from_str::<Vec<CoinOnly>>(d.get()).ok()) else {return};
    let Some(first)=rows.into_iter().next() else {return};
    let Some(state)=self.topics.get(&Topic::trades(first.coin)) else {return};
    let ids:Vec<u64>=state.subs.iter().copied().collect();
    self.counters.frames.fetch_add(1,Ordering::Relaxed);
    self.deliver(ids,&text.into());
   },
   "subscriptionResponse"=>{
    let Some(ack)=head.data.and_then(|d|serde_json::from_str::<Ack>(d.get()).ok()) else {return};
    if ack.method!="subscribe" {return}
    let Some(topic)=Topic::of(&ack.subscription) else {return};
    let Some(state)=self.topics.get_mut(&topic) else {return};
    state.confirmed=true;
    let ids=std::mem::take(&mut state.pending);
    self.deliver(ids,&text.into());
   },
   "error"=>tracing::warn!("Hyperliquid hub: upstream error {}",text.chars().take(300).collect::<String>()),
   _=>{},
  }
 }
}

// ------------------------------------------------------------------ 上游循环

type Upstream=tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;
type Connecting=Pin<Box<dyn Future<Output=Result<Upstream,String>>+Send>>;

fn jittered(d:Duration)->Duration {d.mul_f64(rand::random_range(0.5..1.5))}

fn backoff(limits:&Limits,failures:u32)->Duration {
 let doubled=limits.backoff_min.saturating_mul(1u32<<failures.saturating_sub(1).min(16));
 jittered(doubled.min(limits.backoff_max))
}

async fn connect(url:String,timeout:Duration)->Result<Upstream,String> {
 match tokio::time::timeout(timeout,tokio_tungstenite::connect_async(url.as_str())).await {
  Ok(Ok((stream,_)))=>Ok(stream),
  Ok(Err(e))=>Err(e.to_string()),
  Err(_)=>Err("handshake timed out".to_owned()),
 }
}

async fn run(mut rx:mpsc::UnboundedReceiver<Cmd>,mut s:State) {
 if s.url==WS {let _=SHARED_COUNTERS.set(s.counters.clone());}
 let limits=s.limits;
 let mut writer:Option<futures_util::stream::SplitSink<Upstream,Message>>=None;
 let mut reader:Option<futures_util::stream::SplitStream<Upstream>>=None;
 let mut connecting:Option<Connecting>=None;
 let mut failures:u32=0;
 let mut next_attempt=Instant::now();
 let mut last_connect:Option<Instant>=None;
 let mut up_at=Instant::now();
 let mut heard=Instant::now();
 let mut next_ping=Instant::now();
 let mut next_send=Instant::now();
 let mut empty_since:Option<Instant>=None;
 loop {
  let now=Instant::now();
  let want=!s.topics.is_empty();
  if want {empty_since=None;} else if empty_since.is_none() {empty_since=Some(now);}
  if want&&reader.is_none()&&connecting.is_none()&&now>=next_attempt {
   last_connect=Some(now);
   s.counters.connects.fetch_add(1,Ordering::Relaxed);
   connecting=Some(Box::pin(connect(s.url.clone(),limits.connect)));
  }
  // 下一次要醒来做事的时刻。
  let far=now+Duration::from_secs(3600);
  let wake=if reader.is_some() {
   let mut at=(heard+limits.silence).min(next_ping);
   if !s.queue.is_empty() {at=at.min(next_send);}
   if let Some(since)=empty_since {at=at.min(since+limits.linger);}
   at
  } else if want&&connecting.is_none() {next_attempt} else {far};
  let mut drop_reason:Option<String>=None;
  tokio::select! {
   cmd=rx.recv()=>match cmd {
    Some(cmd)=>s.command(cmd),
    None=>return,
   },
   result=async {connecting.as_mut().expect("guarded").await},if connecting.is_some()=>{
    connecting=None;
    match result {
     Ok(stream)=>{
      let (w,r)=stream.split();
      writer=Some(w);
      reader=Some(r);
      let now=Instant::now();
      up_at=now;heard=now;next_ping=now+limits.ping;next_send=now;
      tracing::info!("Hyperliquid hub: connected, {} topics to subscribe",s.topics.len());
      s.on_up();
     },
     Err(e)=>{
      failures+=1;
      let wait=backoff(&limits,failures);
      let earliest=last_connect.map(|t|t+limits.connect_gap).unwrap_or(Instant::now());
      next_attempt=(Instant::now()+wait).max(earliest);
      tracing::warn!("Hyperliquid hub: connect failed ({e}), retrying in {:?}",next_attempt-Instant::now());
     },
    }
   },
   frame=async {reader.as_mut().expect("guarded").next().await},if reader.is_some()=>{
    match frame {
     Some(Ok(Message::Text(text)))=>{heard=Instant::now();s.upstream(text.as_str());},
     Some(Ok(Message::Close(_)))|Some(Err(_))|None=>drop_reason=Some("closed".to_owned()),
     Some(Ok(_))=>heard=Instant::now(),
    }
   },
   _=tokio::time::sleep_until(wake)=>{
    let now=Instant::now();
    if reader.is_some() {
     if now>=heard+limits.silence {
      drop_reason=Some(format!("silent for {:?}",limits.silence));
     } else if empty_since.is_some_and(|since|now>=since+limits.linger) {
      drop_reason=Some("nobody subscribed".to_owned());
     } else {
      if now>=next_ping {s.queue.push_back(r#"{"method":"ping"}"#.to_owned());next_ping=now+limits.ping;}
      if now>=next_send && let Some(text)=s.queue.pop_front() && let Some(w)=writer.as_mut() {
       next_send=now+limits.gap;
       s.counters.sent.fetch_add(1,Ordering::Relaxed);
       if !matches!(tokio::time::timeout(limits.send,w.send(Message::Text(text.into()))).await,Ok(Ok(()))) {
        drop_reason=Some("send stuck".to_owned());
       }
      }
     }
    }
   },
  }
  if let Some(reason)=drop_reason {
   if let Some(mut w)=writer.take() {let _=tokio::time::timeout(Duration::from_secs(1),w.close()).await;}
   reader=None;
   let quiet=reason=="nobody subscribed";
   if quiet {
    tracing::info!("Hyperliquid hub: closed the upstream, nobody subscribed for {:?}",limits.linger);
    failures=0;
   } else {
    if up_at.elapsed()>Duration::from_secs(60) {failures=0;}
    failures+=1;
    tracing::warn!("Hyperliquid hub: upstream {reason}, reconnecting");
   }
   let wait=if quiet {Duration::ZERO} else {backoff(&limits,failures)};
   let earliest=last_connect.map(|t|t+limits.connect_gap).unwrap_or(Instant::now());
   next_attempt=(Instant::now()+wait).max(earliest);
   s.on_down();
  }
 }
}

#[cfg(test)]
mod tests {
 use super::*;
 use axum::extract::ws::{Message as Down,WebSocketUpgrade};
 use axum::{Router,response::Response};
 use tokio::sync::broadcast;

 /// 假上游：每条连接收到的文本都报给测试（带连接序号），测试经广播往全部连接推帧；
 /// 推 `"<close>"` 就把当前连接关掉。
 struct Fake {port:u16,heard:mpsc::UnboundedReceiver<(usize,String)>,push:broadcast::Sender<String>}
 async fn fake()->Fake {
  let (heard_tx,heard)=mpsc::unbounded_channel::<(usize,String)>();
  let (push,_)=broadcast::channel::<String>(64);
  let conns=Arc::new(AtomicUsize::new(0));
  let push_for=push.clone();
  let app=Router::new().fallback(move|ws:WebSocketUpgrade|{
   let heard_tx=heard_tx.clone();
   let mut pushes=push_for.subscribe();
   let n=conns.fetch_add(1,Ordering::SeqCst)+1;
   async move {
    let reply:Response=ws.on_upgrade(move|mut socket| async move {
     loop {
      tokio::select! {
       m=socket.recv()=>match m {
        Some(Ok(Down::Text(t)))=>{let _=heard_tx.send((n,t.as_str().to_owned()));},
        Some(Ok(_))=>{},
        _=>break,
       },
       p=pushes.recv()=>match p {
        Ok(t) if t=="<close>"=>{let _=socket.send(Down::Close(None)).await;break},
        Ok(t)=>{if socket.send(Down::Text(t.into())).await.is_err() {break}},
        Err(_)=>break,
       },
      }
     }
    });
    reply
   }
  });
  let listener=tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
  let port=listener.local_addr().unwrap().port();
  tokio::spawn(async move {axum::serve(listener,app).await.unwrap()});
  Fake{port,heard,push}
 }
 const QUICK:Limits=Limits{max_topics:6,max_tracking:3,gap:Duration::from_millis(1),ping:Duration::from_secs(30),silence:Duration::from_secs(30),
  connect:Duration::from_secs(2),connect_gap:Duration::from_millis(20),backoff_min:Duration::from_millis(20),backoff_max:Duration::from_millis(100),linger:Duration::from_secs(30),send:Duration::from_secs(2)};

 async fn heard(f:&mut Fake)->(usize,Value) {
  let (n,t)=tokio::time::timeout(Duration::from_secs(3),f.heard.recv()).await.expect("上游该收到一帧").unwrap();
  (n,serde_json::from_str(&t).unwrap())
 }
 async fn quiet(f:&mut Fake,within:Duration) {
  if let Ok(Some((n,t)))=tokio::time::timeout(within,f.heard.recv()).await {panic!("上游不该再收到东西，实际 #{n} {t}")}
 }
 async fn text(link:&mut Link)->Value {
  loop {
   match tokio::time::timeout(Duration::from_secs(3),link.rx.recv()).await.expect("该收到一帧").unwrap() {
    Feed::Text(t)=>return serde_json::from_str(&t).unwrap(),
    _=>continue,
   }
  }
 }
 async fn feed(link:&mut Link)->Feed {tokio::time::timeout(Duration::from_secs(3),link.rx.recv()).await.expect("该收到一帧").unwrap()}
 async fn nothing(link:&mut Link,within:Duration) {
  if let Ok(Some(Feed::Text(t)))=tokio::time::timeout(within,link.rx.recv()).await {panic!("不该收到 {t}")}
 }
 fn ack(topic:&Topic)->String {json!({"channel":"subscriptionResponse","data":{"method":"subscribe","subscription":{"type":if topic.channel==Channel::L2Book {"l2Book"} else {"trades"},"coin":topic.coin,"nSigFigs":if topic.channel==Channel::L2Book {json!(4)} else {Value::Null},"mantissa":null,"fast":false}}}).to_string()}
 fn book_frame(coin:&str,time:i64)->String {json!({"channel":"l2Book","data":{"coin":coin,"time":time,"levels":[[{"px":"82640.0","sz":"7.5","n":31}],[{"px":"82650.0","sz":"1.2","n":3}]]}}).to_string()}
 fn trades_frame(coin:&str)->String {json!({"channel":"trades","data":[{"coin":coin,"side":"B","px":"82625.0","sz":"0.00025","time":1791457522600_i64,"hash":"0x0","tid":615263281857618_i64,"users":["0xa","0xb"]}]}).to_string()}

 #[tokio::test]
 async fn subscriptions_are_reference_counted_and_frames_go_only_to_their_subscribers() {
  let mut f=fake().await;
  let hub=Hub::start(format!("ws://127.0.0.1:{}",f.port),QUICK);
  let mut a=hub.join(Class::Relay,64);
  let mut b=hub.join(Class::Tracking,64);
  let btc=Topic::book("BTC");
  a.handle.subscribe(btc.clone());
  assert_eq!(heard(&mut f).await.1,json!({"method":"subscribe","subscription":{"type":"l2Book","coin":"BTC","nSigFigs":4}}));
  assert!(matches!(feed(&mut a).await,Feed::Up));
  assert!(matches!(feed(&mut b).await,Feed::Up));
  f.push.send(ack(&btc)).unwrap();
  assert_eq!(text(&mut a).await["channel"],"subscriptionResponse","上游回执给发起订阅的那个");
  f.push.send(book_frame("BTC",1)).unwrap();
  assert_eq!(text(&mut a).await["data"]["time"],1);
  // b 再订同一个：上游不再收到订阅，b 马上拿到 hub 答的回执与手上最近那一帧。
  b.handle.subscribe(btc.clone());
  let reply=text(&mut b).await;
  assert_eq!(reply,json!({"channel":"subscriptionResponse","data":{"method":"subscribe","subscription":{"type":"l2Book","coin":"BTC","nSigFigs":4}}}));
  assert_eq!(text(&mut b).await["data"]["time"],1,"后来订的先拿到最近一帧整本");
  quiet(&mut f,Duration::from_millis(200)).await;
  // 别的币、别的频道的帧谁都不发。
  a.handle.subscribe(Topic::trades("ETH"));
  assert_eq!(heard(&mut f).await.1["subscription"],json!({"type":"trades","coin":"ETH"}));
  f.push.send(trades_frame("ETH")).unwrap();
  assert_eq!(text(&mut a).await["data"][0]["coin"],"ETH");
  f.push.send(trades_frame("SOL")).unwrap();
  f.push.send(book_frame("ETH",9)).unwrap();
  nothing(&mut b,Duration::from_millis(200)).await;
  // a 退 BTC：还有 b 订着，上游不退；b 离开（把手丢掉）才退。
  a.handle.unsubscribe(btc.clone());
  assert_eq!(text(&mut a).await["data"]["method"],"unsubscribe");
  quiet(&mut f,Duration::from_millis(200)).await;
  drop(b);
  assert_eq!(heard(&mut f).await.1,json!({"method":"unsubscribe","subscription":{"type":"l2Book","coin":"BTC","nSigFigs":4}}));
  // a 离开：它订着的 ETH 成交也退掉。
  drop(a);
  assert_eq!(heard(&mut f).await.1,json!({"method":"unsubscribe","subscription":{"type":"trades","coin":"ETH"}}));
 }

 #[tokio::test]
 async fn after_a_reconnect_every_live_subscription_is_sent_again() {
  let mut f=fake().await;
  let hub=Hub::start(format!("ws://127.0.0.1:{}",f.port),Limits{max_tracking:6,..QUICK});
  let mut a=hub.join(Class::Tracking,64);
  for coin in ["BTC","ETH"] {a.handle.subscribe(Topic::book(coin));a.handle.subscribe(Topic::trades(coin));}
  let mut first=Vec::new();
  for _ in 0..4 {let (n,v)=heard(&mut f).await;assert_eq!(n,1);first.push(v["subscription"].clone());}
  assert!(matches!(feed(&mut a).await,Feed::Up));
  a.handle.unsubscribe(Topic::trades("ETH"));
  assert_eq!(heard(&mut f).await.1["method"],"unsubscribe");
  f.push.send("<close>".to_owned()).unwrap();
  // 断了：先 Down，再连上第二条、Up，三个还订着的全部重订（退掉的那个不再订）。
  let mut seen=Vec::new();
  loop {
   match feed(&mut a).await {
    Feed::Down=>seen.push("down"),
    Feed::Up=>{seen.push("up");break},
    Feed::Text(_)=>{},
   }
  }
  assert_eq!(seen,vec!["down","up"]);
  let mut again=Vec::new();
  for _ in 0..3 {let (n,v)=heard(&mut f).await;assert_eq!(n,2,"重订走新连接");assert_eq!(v["method"],"subscribe");again.push(v["subscription"].clone());}
  again.sort_by_key(|v|v.to_string());
  let mut want=vec![json!({"type":"l2Book","coin":"BTC","nSigFigs":4}),json!({"type":"trades","coin":"BTC"}),json!({"type":"l2Book","coin":"ETH","nSigFigs":4})];
  want.sort_by_key(|v|v.to_string());
  assert_eq!(again,want);
  quiet(&mut f,Duration::from_millis(200)).await;
  // 新连接上的帧照常到。
  f.push.send(book_frame("ETH",5)).unwrap();
  assert_eq!(text(&mut a).await["data"]["coin"],"ETH");
  assert_eq!(hub.counters.connects.load(Ordering::Relaxed),2);
 }

 #[tokio::test]
 async fn the_caps_refuse_without_asking_upstream() {
  let mut f=fake().await;
  let hub=Hub::start(format!("ws://127.0.0.1:{}",f.port),QUICK);
  let mut tracking=hub.join(Class::Tracking,64);
  let mut relay=hub.join(Class::Relay,64);
  for coin in ["A1","A2","A3"] {tracking.handle.subscribe(Topic::book(coin));}
  for _ in 0..3 {heard(&mut f).await;}
  tracking.handle.subscribe(Topic::book("A4"));
  let refused=loop {if let Feed::Text(t)=feed(&mut tracking).await {break serde_json::from_str::<Value>(&t).unwrap()}};
  assert_eq!(refused["channel"],"error","跟踪最多占 3 个");
  quiet(&mut f,Duration::from_millis(150)).await;
  // 中继还能订到总数 6 为止；跟踪订一个中继已经订着的也算它的名额，满了照样拒。
  for coin in ["B1","B2","B3"] {relay.handle.subscribe(Topic::book(coin));}
  for _ in 0..3 {heard(&mut f).await;}
  relay.handle.subscribe(Topic::book("B4"));
  assert_eq!(text(&mut relay).await["channel"],"error","总数最多 6 个");
  tracking.handle.subscribe(Topic::book("B1"));
  assert_eq!(text(&mut tracking).await["channel"],"error");
  quiet(&mut f,Duration::from_millis(150)).await;
 }

 #[tokio::test]
 async fn a_relay_that_falls_behind_is_dropped_but_tracking_only_loses_frames() {
  let mut f=fake().await;
  let hub=Hub::start(format!("ws://127.0.0.1:{}",f.port),QUICK);
  let mut slow_relay=hub.join(Class::Relay,2);
  let mut slow_tracking=hub.join(Class::Tracking,2);
  slow_relay.handle.subscribe(Topic::book("BTC"));
  slow_tracking.handle.subscribe(Topic::book("BTC"));
  heard(&mut f).await;
  for t in 0..10 {f.push.send(book_frame("BTC",t)).unwrap();}
  tokio::time::sleep(Duration::from_millis(300)).await;
  // 中继：攒满就被踢掉，通道读完就结束。
  let mut ended=false;
  for _ in 0..10 {if tokio::time::timeout(Duration::from_secs(1),slow_relay.rx.recv()).await.unwrap().is_none() {ended=true;break}}
  assert!(ended,"跟不上的中继被踢掉");
  // 跟踪：还连着，丢的帧有数。
  assert!(hub.counters.drops.load(Ordering::Relaxed)>0);
  f.push.send(book_frame("BTC",99)).unwrap();
  let mut got_last=false;
  for _ in 0..5 {if let Ok(Some(Feed::Text(t)))=tokio::time::timeout(Duration::from_secs(1),slow_tracking.rx.recv()).await && t.contains("\"time\":99") {got_last=true;break}}
  assert!(got_last,"跟踪那条还在收");
 }

 /// `candle` 按 `data.s` + `data.i` 分发，`activeAssetCtx` 按 `data.coin`；两种都留最近一帧给后来者。
 #[tokio::test]
 async fn candles_and_asset_contexts_are_routed_and_replayed() {
  let mut f=fake().await;
  let hub=Hub::start(format!("ws://127.0.0.1:{}",f.port),QUICK);
  let mut a=hub.join(Class::Relay,64);
  let one=Topic::candle("BTC","1m");
  a.handle.subscribe(one.clone());
  assert_eq!(heard(&mut f).await.1["subscription"],json!({"type":"candle","coin":"BTC","interval":"1m"}));
  a.handle.subscribe(Topic::asset_ctx("BTC"));
  heard(&mut f).await;
  f.push.send(json!({"channel":"subscriptionResponse","data":{"method":"subscribe","subscription":{"type":"candle","coin":"BTC","interval":"1m"}}}).to_string()).unwrap();
  assert_eq!(text(&mut a).await["channel"],"subscriptionResponse");
  f.push.send(json!({"channel":"candle","data":{"t":1,"T":2,"s":"BTC","i":"5m","o":"1","c":"1","h":"1","l":"1","v":"1","n":1}}).to_string()).unwrap();
  f.push.send(json!({"channel":"candle","data":{"t":1,"T":2,"s":"BTC","i":"1m","o":"1","c":"2","h":"2","l":"1","v":"1","n":1}}).to_string()).unwrap();
  let got=text(&mut a).await;
  assert_eq!((got["data"]["i"].as_str(),got["data"]["c"].as_str()),(Some("1m"),Some("2")),"5 分钟那根没人订，不发");
  f.push.send(json!({"channel":"activeAssetCtx","data":{"coin":"BTC","ctx":{"markPx":"1","funding":"0.0001","openInterest":"5"}}}).to_string()).unwrap();
  assert_eq!(text(&mut a).await["channel"],"activeAssetCtx");
  // 后来订同一根 K 线的：回执 + 最近那一帧。
  let mut b=hub.join(Class::Relay,64);
  b.handle.subscribe(one);
  assert_eq!(text(&mut b).await["channel"],"subscriptionResponse");
  assert_eq!(text(&mut b).await["data"]["c"],"2");
 }

 #[test]
 fn topics_from_acks() {
  assert_eq!(Topic::of(&json!({"type":"l2Book","coin":"kPEPE","nSigFigs":4,"mantissa":null,"fast":false})),Some(Topic::book("kPEPE")));
  assert_eq!(Topic::of(&json!({"type":"l2Book","coin":"BTC","nSigFigs":3})),None);
  assert_eq!(Topic::of(&json!({"type":"l2Book","coin":"BTC"})),None);
  assert_eq!(Topic::of(&json!({"type":"trades","coin":"BTC"})),Some(Topic::trades("BTC")));
  assert_eq!(Topic::of(&json!({"type":"allMids"})),None);
  assert_eq!(Topic::of(&json!({"type":"candle","coin":"kPEPE","interval":"1m"})),Some(Topic::candle("kPEPE","1m")));
  assert_eq!(Topic::of(&json!({"type":"candle","coin":"BTC","interval":"7m"})),None);
  assert_eq!(Topic::of(&json!({"type":"activeAssetCtx","coin":"BTC"})),Some(Topic::asset_ctx("BTC")));
  assert_eq!(Topic::candle("BTC","1h").message(true),r#"{"method":"subscribe","subscription":{"coin":"BTC","interval":"1h","type":"candle"}}"#);
  assert!(valid_coin("kPEPE")&&valid_coin("BTC")&&!valid_coin("")&&!valid_coin("BTC-USD")&&!valid_coin(&"A".repeat(17)));
 }
}
