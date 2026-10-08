//! Coinbase 现货（Advanced Trade 公开行情）在服务端的那一截。
//!
//! 三件事，都不改 Coinbase 的报文：
//!
//! 1. **REST 透传** `GET /v1/market/raw/<path>?source=coinbase&…` → `api.coinbase.com
//!    /api/v3/brokerage/market/<path>?…`。只放公开行情那几条路径；状态码、正文、
//!    `Retry-After` 原样回，客户端的解析两条线路共用一份。品种表一条就一兆多，十五秒内
//!    的重复请求直接答缓存。
//! 2. **推送 hub** `GET /v1/market/stream?source=coinbase`：所有手机共用一条上游连接，
//!    按（频道, 品种）引用计数订阅；说的协议和 Coinbase 原生的一模一样
//!    （`{"type":"subscribe","channel":…,"product_ids":[…]}`），所以客户端的推送代码
//!    两条线路也共用一份。后来者订一个已经在订的品种时，先补给它最近一帧 24h 行情 /
//!    K 线，不必等下一笔成交。
//! 3. **复盘 worker 的取数**：`candles`（K 线页）与 `trades`（逐笔，给 `trade_touch`）。
//!
//! 整个进程共用一道出站节拍 [`PACER`]（公开端点按 IP 10 次/秒，这里取 8 次留余量）。
//! 4. 服务端提醒评估：`alerts`（逐笔拼 1 分钟 K 线）。
pub mod orderflow;
use super::outbound::{self,Answers,Pacer,Reply,refuse};
use axum::extract::ws::{Message,WebSocket,WebSocketUpgrade};
use axum::http::StatusCode;
use axum::response::Response;
use futures_util::{SinkExt,StreamExt};
use serde_json::{Value,json};
use std::collections::{BTreeMap,BTreeSet,HashMap};
pub mod alerts;
use std::sync::{Arc,OnceLock};
use std::sync::atomic::{AtomicU64,Ordering};
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::time::Instant;

pub const SOURCE:&str="coinbase";
const REST:&str="https://api.coinbase.com/api/v3/brokerage/market";
pub const WS:&str="wss://advanced-trade-ws.coinbase.com";

// ------------------------------------------------------------------ 出站

/// 这一家唯一的出站节拍：公开端点按 IP 10 次/秒，这里取 8 次留余量。透传、复盘取数、订单流品种表
/// （`api.exchange.coinbase.com`）、`market_meta` / `listing_watch` 拉的现货表都排这一队。
/// 排队超过八秒就不排了，直接回「忙」：客户端有自己的退避，让它在手机上等好过让这边的连接一直挂着。
pub static PACER:Pacer=Pacer::new(Duration::from_millis(125),Duration::from_secs(8),&[]);
/// 这一家的 REST 主机。
pub const HOSTS:&[&str]=&["api.coinbase.com","api.exchange.coinbase.com"];

pub use super::outbound::Upstream;

async fn fetch(path:&str,query:&[(String,String)])->Result<Reply,Upstream> {
 outbound::send(&PACER,&format!("{REST}/{path}"),query,None,1).await
}
/// `fetch` 再把非 200 翻成 `Upstream`。
async fn fetch_json(path:&str,query:&[(String,String)])->Result<Value,Upstream> {
 outbound::json_of(&fetch(path,query).await?)
}

// ------------------------------------------------------------------ REST 透传

/// 品种代号：`BTC-USD` 这一类。大写字母数字加连字符，不给别的字符进路径。
pub fn product_ok(id:&str)->bool {
 !id.is_empty()&&id.len()<=40&&id.bytes().all(|c|c.is_ascii_uppercase()||c.is_ascii_digit()||c==b'-')
}
/// 透传只放公开行情这四条路径。
fn path_ok(path:&str)->bool {
 match path.split('/').collect::<Vec<_>>().as_slice() {
  ["products"]=>true,
  ["products",id]|["products",id,"candles"|"ticker"]=>product_ok(id),
  _=>false,
 }
}
/// 查询参数也只放已知的几个，`source` 是给我们自己分发用的，不往上游带；值按键各认各的形状
/// （以前值不看，`limit=1;DROP`、`granularity=` 加什么都原样往上游带，和 OKX / Bybit 两家的口径不一）。
fn query_ok(key:&str,value:&str)->bool {
 let digits=|v:&str|(1..=20).contains(&v.len())&&v.bytes().all(|b|b.is_ascii_digit());
 match key {
  "product_type"=>matches!(value,"SPOT"|"FUTURE"),
  "product_ids"=>product_ok(value),
  "limit"|"offset"|"start"|"end"=>digits(value),
  "granularity"=>matches!(value,"ONE_MINUTE"|"FIVE_MINUTE"|"FIFTEEN_MINUTE"|"THIRTY_MINUTE"|"ONE_HOUR"|"TWO_HOUR"|"FOUR_HOUR"|"SIX_HOUR"|"ONE_DAY"),
  "get_all_products"=>matches!(value,"true"|"false"),
  _=>false,
 }
}
/// 品种表缓存多久。一条就一兆多，三台手机同时启动不必各拉一遍（同键合流，只出站一次）。
const PRODUCTS_TTL:Duration=Duration::from_secs(15);
static ANSWERS:Answers=Answers::new();

pub async fn raw(path:&str,query:&[(String,String)])->Response {
 if !path_ok(path) {return refuse(StatusCode::NOT_FOUND,"unsupported_path")}
 let Some(forward)=outbound::forward(query,query_ok) else {return refuse(StatusCode::BAD_REQUEST,"unsupported_query")};
 // 只有品种表缓存；K 线、行情要新鲜，照旧每次都出站（仍然排节拍）。
 let ttl=if path=="products" {PRODUCTS_TTL} else {Duration::ZERO};
 outbound::pass(ANSWERS.get(format!("{path}?{forward:?}"),ttl,outbound::any_ok,||fetch(path,&forward)).await)
}

// ------------------------------------------------------------------ 复盘取数

/// Coinbase 原生的 9 档周期（秒 → `granularity`）。
pub fn granularity(step_secs:i64)->Option<&'static str> {
 Some(match step_secs {
  60=>"ONE_MINUTE",300=>"FIVE_MINUTE",900=>"FIFTEEN_MINUTE",1800=>"THIRTY_MINUTE",
  3600=>"ONE_HOUR",7200=>"TWO_HOUR",14_400=>"FOUR_HOUR",21_600=>"SIX_HOUR",86_400=>"ONE_DAY",
  _=>return None,
 })
}
/// 一页最多多少根（起止两端都含，跨度要小于 350 步）。
pub const PAGE:i64=350;

/// 一根原生 K 线。价格保留 Coinbase 的原串（复盘判定按字符串解析，不经一道浮点再格式化）。
#[derive(Debug,Clone,PartialEq)]
pub struct Candle {pub start:i64,pub open:String,pub high:String,pub low:String,pub close:String,pub volume:String}

fn candle(v:&Value)->Option<Candle> {
 let s=|k:&str|v[k].as_str().map(str::to_owned);
 let start=v["start"].as_str()?.parse::<i64>().ok()?;
 let c=Candle{start,open:s("open")?,high:s("high")?,low:s("low")?,close:s("close")?,volume:s("volume")?};
 [&c.open,&c.high,&c.low,&c.close].iter().all(|p|p.parse::<f64>().is_ok_and(|x|x.is_finite()&&x>0.0)).then_some(c)
}
/// 一页 K 线 → 升序。
pub fn parse_candles(v:&Value)->Option<Vec<Candle>> {
 let mut out:Vec<Candle>=v["candles"].as_array()?.iter().filter_map(candle).collect();
 out.sort_by_key(|c|c.start);out.dedup_by_key(|c|c.start);
 Some(out)
}

/// `[start, end)`（秒）内的原生 K 线，按页翻，升序。没成交的那几根 Coinbase 不给——
/// 缺口留给调用方处理。
pub async fn candles(product:&str,step:i64,start:i64,end:i64)->Result<Vec<Candle>,Upstream> {
 let Some(g)=granularity(step) else {return Err(Upstream::Rejected(400))};
 if !product_ok(product) {return Err(Upstream::Rejected(400))}
 let mut out=vec![];
 let mut cursor=start;
 while cursor<end {
  let last=(cursor+(PAGE-1)*step).min(end-step);
  if last<cursor {break}
  let v=fetch_json(&format!("products/{product}/candles"),&[("granularity".into(),g.into()),("start".into(),cursor.to_string()),("end".into(),last.to_string())]).await?;
  let page=parse_candles(&v).ok_or(Upstream::Unavailable)?;
  out.extend(page.into_iter().filter(|c|c.start>=cursor&&c.start<=last));
  cursor=last+step;
 }
 out.sort_by_key(|c|c.start);out.dedup_by_key(|c|c.start);
 Ok(out)
}

/// 逐笔一页最多多少笔。回满了说明窗口里还有更早的，要拆开再问。
const TRADES_LIMIT:usize=1000;

/// `[from, until]`（毫秒，两端都含）里的全部逐笔，换成复盘判定要的形状
/// `{"raw":[{"a":成交号,"T":毫秒,"p":"价"}],"coverage_complete":…}`，按成交号升序。
///
/// Coinbase 的成交号在同一个品种上是连续的；一页给的是窗口里**最新**的那
/// `limit` 笔，所以回满了就把窗口对半拆开各问一次，拆到一秒还满就认不完整。
pub async fn trades(product:&str,from:i64,until:i64)->Result<Value,Upstream> {
 if !product_ok(product) {return Err(Upstream::Rejected(400))}
 let mut rows:BTreeMap<i64,(i64,String)>=BTreeMap::new();
 let mut complete=true;
 // 秒级窗口，两端都含。
 let mut windows=vec![(from.div_euclid(1000),until.div_euclid(1000))];
 let mut asked=0;
 while let Some((a,b))=windows.pop() {
  asked+=1;
  if asked>64 {complete=false;break}
  let v=fetch_json(&format!("products/{product}/ticker"),&[("limit".into(),TRADES_LIMIT.to_string()),("start".into(),a.to_string()),("end".into(),(b+1).to_string())]).await?;
  let list=v["trades"].as_array().ok_or(Upstream::Unavailable)?;
  if list.len()>=TRADES_LIMIT {
   if a>=b {complete=false;continue}
   let mid=a+(b-a)/2;
   windows.push((a,mid));windows.push((mid+1,b));
   continue
  }
  for t in list {
   let (Some(id),Some(at),Some(price))=(t["trade_id"].as_str().and_then(|s|s.parse::<i64>().ok()),t["time"].as_str().and_then(iso_ms),t["price"].as_str()) else {complete=false;continue};
   if at<from||at>until {continue}
   rows.insert(id,(at,price.to_owned()));
  }
 }
 let raw:Vec<Value>=rows.into_iter().map(|(a,(t,p))|json!({"a":a,"T":t,"p":p})).collect();
 Ok(json!({"raw":raw,"coverage_complete":complete}))
}

/// `2026-09-22T23:19:46.408897Z` → 毫秒。
pub fn iso_ms(s:&str)->Option<i64> {
 chrono::DateTime::parse_from_rfc3339(s).ok().map(|t|t.timestamp_millis())
}

// ------------------------------------------------------------------ 推送 hub

/// 客户端能订的频道。`level2`、`user` 这些不给（不是公开行情，或者量太大）。
fn channel_ok(c:&str)->bool {matches!(c,"heartbeats"|"ticker"|"ticker_batch"|"market_trades"|"candles")}
/// 一条连接最多订多少个（频道, 品种）。一台手机同时开的也就一两个图加自选页。
const MAX_SUBS_PER_CLIENT:usize=200;
/// 同时最多多少条客户端连接（用户是个位数）。
const MAX_CLIENTS:usize=64;
/// 发给一个客户端的队列多长。排满了说明它读不动了，断开它，让它自己重连补。
const CLIENT_QUEUE:usize=4096;
/// 上游多久一帧都没有就算断了（订着心跳，每秒一帧）。
const UPSTREAM_SILENCE:Duration=Duration::from_secs(30);
/// 最后一个客户端走了之后，上游连接再留多久（切页面、切线路时不必重连）。
const IDLE_GRACE:Duration=Duration::from_secs(60);
/// 两条上游控制帧之间隔多久。官方（Advanced Trade WebSocket rate limits）：未鉴权连接每 IP 上行 ≤ 8 条 / 秒，
/// 这台机器只有一个出口 IP，150 ms（≈ 6.7 条 / 秒）才在线下；原来的 120 ms 是 8.3 条 / 秒，贴着线上。
const CONTROL_GAP:Duration=Duration::from_millis(150);

type Key=(String,String);

enum Cmd {
 Join{id:u64,tx:mpsc::Sender<Arc<str>>},
 Change{id:u64,subscribe:bool,channel:String,products:Vec<String>},
 Leave{id:u64},
}

fn hub()->&'static mpsc::UnboundedSender<Cmd> {
 static H:OnceLock<mpsc::UnboundedSender<Cmd>>=OnceLock::new();
 H.get_or_init(||{
  let (tx,rx)=mpsc::unbounded_channel();
  crate::supervise::spawn_essential("coinbase-hub",Hub::default().run(rx));
  tx
 })
}

/// 频道 → 帧里装品种那一栏的字段名。
fn items_field(channel:&str)->Option<&'static str> {
 match channel {"ticker"|"ticker_batch"=>Some("tickers"),"market_trades"=>Some("trades"),"candles"=>Some("candles"),_=>None}
}

/// 把一帧行情按品种拆开：返回（品种, 只含这个品种的帧）。
/// 一帧只有一个品种（最常见）时原文照发，不重新序列化。
pub fn split(text:&str)->Option<(String,Vec<(String,Arc<str>)>)> {
 let v:Value=serde_json::from_str(text).ok()?;
 let channel=v["channel"].as_str()?.to_owned();
 let field=items_field(&channel)?;
 let events=v["events"].as_array()?;
 let mut products=BTreeSet::new();
 for e in events {for item in e[field].as_array().into_iter().flatten() {if let Some(p)=item["product_id"].as_str() {products.insert(p.to_owned());}}}
 if products.len()<=1 {
  return Some((channel,products.into_iter().map(|p|(p,Arc::from(text))).collect()))
 }
 let mut out=vec![];
 for p in products {
  let mut one=v.clone();
  for e in one["events"].as_array_mut().into_iter().flatten() {
   if let Some(items)=e[field].as_array_mut() {items.retain(|item|item["product_id"].as_str()==Some(p.as_str()))}
  }
  if let Some(es)=one["events"].as_array_mut() {es.retain(|e|e[field].as_array().is_none_or(|a|!a.is_empty()))}
  out.push((p,Arc::from(one.to_string())));
 }
 Some((channel,out))
}

type Upstreamed=tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

#[derive(Default)]
struct Client {tx:Option<mpsc::Sender<Arc<str>>>,subs:BTreeSet<Key>}

#[derive(Default)]
struct Hub {
 clients:HashMap<u64,Client>,
 /// 每个（频道, 品种）有几个客户端在订。`heartbeats` 不在这里：上游永远订着它。
 refs:BTreeMap<Key,usize>,
 /// 上游那条连接上已经订了的。
 sent:BTreeSet<Key>,
 /// 最近一帧 24h 行情 / K 线，给后来的订阅者先补一帧。
 last:HashMap<Key,Arc<str>>,
}

impl Hub {
 async fn run(mut self,mut rx:mpsc::UnboundedReceiver<Cmd>) {
  let mut upstream:Option<Upstreamed>=None;
  let mut retry_at=Instant::now();
  let mut backoff=Duration::from_secs(1);
  let mut idle_since:Option<Instant>=None;
  let mut last_frame=Instant::now();
  loop {
   // 有人在用、没连着、到了该重试的时候：连。
   if upstream.is_none()&&!self.clients.is_empty()&&Instant::now()>=retry_at {
    match self.connect().await {
     Ok(s)=>{upstream=Some(s);backoff=Duration::from_secs(1);last_frame=Instant::now();tracing::info!("Coinbase hub connected upstream")}
     Err(e)=>{
      tracing::warn!("Coinbase hub could not connect upstream ({e}); retrying in {backoff:?}");
      retry_at=Instant::now()+backoff;backoff=(backoff*2).min(Duration::from_secs(30));
     }
    }
   }
   if let Some(s)=upstream.as_mut()&&self.wanted()!=self.sent {
    if let Err(e)=self.sync(s).await {tracing::warn!("Coinbase hub could not update its subscriptions ({e}); reconnecting");self.drop_upstream(&mut upstream);continue}
   }
   // 下一次该自己醒来的时刻：没连着就等重试，连着但没人用就等宽限期满。
   let wake=if upstream.is_none() {(!self.clients.is_empty()).then_some(retry_at)} else {idle_since.map(|t|t+IDLE_GRACE)};
   tokio::select! {
    cmd=rx.recv()=>{
     let Some(cmd)=cmd else {return};
     self.handle(cmd);
     idle_since=if self.clients.is_empty(){idle_since.or(Some(Instant::now()))}else{None};
    }
    frame=async {
     match upstream.as_mut() {
      Some(s)=>tokio::time::timeout_at(last_frame+UPSTREAM_SILENCE,s.next()).await,
      None=>std::future::pending().await,
     }
    }=>{
     match frame {
      Ok(Some(Ok(message)))=>{
       last_frame=Instant::now();
       match message {
        tokio_tungstenite::tungstenite::Message::Text(text)=>self.route(text.as_str()),
        tokio_tungstenite::tungstenite::Message::Ping(p)=>{if let Some(s)=upstream.as_mut() {let _=s.send(tokio_tungstenite::tungstenite::Message::Pong(p)).await;}}
        tokio_tungstenite::tungstenite::Message::Close(_)=>{tracing::warn!("Coinbase closed the hub's upstream; reconnecting");self.drop_upstream(&mut upstream)}
        _=>{}
       }
      }
      Ok(Some(Err(e)))=>{tracing::warn!("Coinbase hub upstream failed ({e}); reconnecting");self.drop_upstream(&mut upstream)}
      Ok(None)=>{tracing::warn!("Coinbase hub upstream ended; reconnecting");self.drop_upstream(&mut upstream)}
      Err(_)=>{tracing::warn!("Coinbase hub upstream was silent for {UPSTREAM_SILENCE:?}; reconnecting");self.drop_upstream(&mut upstream)}
     }
    }
    _=async {
     match wake {Some(at)=>tokio::time::sleep_until(at).await,None=>std::future::pending().await}
    }=>{
     if upstream.is_some()&&self.clients.is_empty()&&idle_since.is_some_and(|t|t.elapsed()>=IDLE_GRACE) {
      tracing::info!("Coinbase hub has no clients; closing upstream");
      self.drop_upstream(&mut upstream);idle_since=None;
     }
    }
   }
  }
 }

 async fn connect(&mut self)->anyhow::Result<Upstreamed> {
  let (mut s,_)=tokio::time::timeout(Duration::from_secs(10),tokio_tungstenite::connect_async(WS)).await??;
  // Coinbase 连上五秒内不订东西就断；心跳每秒一帧，也是上游活着的证据。
  s.send(control("subscribe","heartbeats",&[]).into()).await?;
  self.sent.clear();
  Ok(s)
 }

 /// 上游断了：订阅清单和「最近一帧」一起作废。断线这段时间价格可能已经走远，
 /// 重连前后才订进来的人不能先拿到一帧断线前的旧行情当现价；重连后上游会先推一帧快照，
 /// 由它重新填上。
 fn drop_upstream(&mut self,upstream:&mut Option<Upstreamed>) {
  *upstream=None;self.sent.clear();self.last.clear();
 }

 fn wanted(&self)->BTreeSet<Key> {self.refs.iter().filter(|(_,n)|**n>0).map(|(k,_)|k.clone()).collect()}

 /// 退订先于订阅，一帧只说一个频道。
 async fn sync(&mut self,s:&mut Upstreamed)->anyhow::Result<()> {
  let wanted=self.wanted();
  for (subscribe,keys) in [(false,self.sent.difference(&wanted).cloned().collect::<Vec<_>>()),(true,wanted.difference(&self.sent).cloned().collect())] {
   let mut by_channel:BTreeMap<String,Vec<String>>=BTreeMap::new();
   for (c,p) in &keys {by_channel.entry(c.clone()).or_default().push(p.clone())}
   for (channel,products) in by_channel {
    s.send(control(if subscribe{"subscribe"}else{"unsubscribe"},&channel,&products).into()).await?;
    for p in products {let k=(channel.clone(),p);if subscribe{self.sent.insert(k);}else{self.sent.remove(&k);self.last.remove(&k);}}
    tokio::time::sleep(CONTROL_GAP).await;
   }
  }
  Ok(())
 }

 fn handle(&mut self,cmd:Cmd) {
  match cmd {
   Cmd::Join{id,tx}=>{self.clients.insert(id,Client{tx:Some(tx),subs:BTreeSet::new()});}
   Cmd::Leave{id}=>self.remove(id),
   Cmd::Change{id,subscribe,channel,products}=>{
    let Some(client)=self.clients.get_mut(&id) else {return};
    if channel=="heartbeats" {return}
    let mut replay=vec![];
    for p in products {
     let key=(channel.clone(),p);
     if subscribe {
      if client.subs.len()>=MAX_SUBS_PER_CLIENT||!client.subs.insert(key.clone()) {continue}
      *self.refs.entry(key.clone()).or_default()+=1;
      if let Some(frame)=self.last.get(&key) {replay.push(frame.clone())}
     } else if client.subs.remove(&key) {
      Self::release(&mut self.refs,&key);
     }
    }
    for frame in replay {self.deliver(id,frame)}
   }
  }
 }

 fn release(refs:&mut BTreeMap<Key,usize>,key:&Key) {
  if let Some(n)=refs.get_mut(key) {*n=n.saturating_sub(1);if *n==0 {refs.remove(key);}}
 }

 fn remove(&mut self,id:u64) {
  if let Some(client)=self.clients.remove(&id) {for key in &client.subs {Self::release(&mut self.refs,key)}}
 }

 /// 发给一个客户端。它的队列满了就断开它——读不动的连接留着只会越积越旧。
 fn deliver(&mut self,id:u64,frame:Arc<str>) {
  let full=self.clients.get(&id).and_then(|c|c.tx.as_ref()).is_some_and(|tx|tx.try_send(frame).is_err());
  if full {tracing::warn!("A Coinbase hub client fell behind; disconnecting it");self.remove(id)}
 }

 fn route(&mut self,text:&str) {
  let v:Value=match serde_json::from_str(text) {Ok(v)=>v,Err(_)=>return};
  match v["channel"].as_str() {
   Some("heartbeats")=>{
    let frame:Arc<str>=Arc::from(text);
    let ids:Vec<u64>=self.clients.keys().copied().collect();
    for id in ids {self.deliver(id,frame.clone())}
    return
   }
   Some("subscriptions")|None=>{
    if v["type"]=="error" {tracing::warn!("Coinbase hub upstream error: {}",v["message"])}
    return
   }
   _=>{}
  }
  let Some((channel,parts))=split(text) else {return};
  for (product,frame) in parts {
   let key=(channel.clone(),product);
   if channel!="market_trades" {self.last.insert(key.clone(),frame.clone());}
   let ids:Vec<u64>=self.clients.iter().filter(|(_,c)|c.subs.contains(&key)).map(|(id,_)|*id).collect();
   for id in ids {self.deliver(id,frame.clone())}
  }
 }
}

pub fn control(kind:&str,channel:&str,products:&[String])->String {
 let mut v=json!({"type":kind,"channel":channel});
 if !products.is_empty() {v["product_ids"]=json!(products)}
 v.to_string()
}

static CLIENTS:AtomicU64=AtomicU64::new(0);
static NEXT_ID:AtomicU64=AtomicU64::new(1);

/// 一条客户端连接：读它的订阅帧交给 hub，把 hub 发来的帧写回去。
pub async fn serve_client(socket:WebSocket) {
 let (mut sink,mut stream)=socket.split();
 if CLIENTS.fetch_add(1,Ordering::SeqCst)>=MAX_CLIENTS as u64 {
  CLIENTS.fetch_sub(1,Ordering::SeqCst);
  let _=sink.send(Message::Text(json!({"type":"error","message":"too many connections"}).to_string().into())).await;
  return
 }
 let id=NEXT_ID.fetch_add(1,Ordering::SeqCst);
 let (tx,mut rx)=mpsc::channel::<Arc<str>>(CLIENT_QUEUE);
 let _=hub().send(Cmd::Join{id,tx});
 let (errors_tx,mut errors)=mpsc::channel::<String>(16);
 let writer=async {
  loop {
   let text:String=tokio::select! {
    frame=rx.recv()=>match frame {Some(f)=>f.to_string(),None=>break},
    e=errors.recv()=>match e {Some(e)=>e,None=>continue},
   };
   if sink.send(Message::Text(text.into())).await.is_err() {break}
  }
 };
 let reader=async {
  while let Some(Ok(message))=stream.next().await {
   match message {
    Message::Text(text)=>match parse_control(text.as_str()) {
     Ok((subscribe,channel,products))=>{let _=hub().send(Cmd::Change{id,subscribe,channel,products});}
     Err(why)=>{let _=errors_tx.try_send(json!({"type":"error","message":why}).to_string());}
    },
    // 对方先发了 Close：回执已排进 tungstenite 的发送队列，要等下一次读才冲出去；直接 break
    // 客户端看到的是 1006 而不是 1000（2026-10-05 服务端回归实测）。再读一次把回执送出去
    // （读到的只会是「已关闭」），对方卡着不关 TCP 也只等 2 秒。
    Message::Close(_)=>{let _=tokio::time::timeout(Duration::from_secs(2),stream.next()).await;break}
    _=>{}
   }
  }
 };
 tokio::select! {_=writer=>{},_=reader=>{}}
 let _=hub().send(Cmd::Leave{id});
 CLIENTS.fetch_sub(1,Ordering::SeqCst);
}

/// 客户端发来的一帧订阅控制。形状和 Coinbase 原生的一样。
pub fn parse_control(text:&str)->Result<(bool,String,Vec<String>),&'static str> {
 let v:Value=serde_json::from_str(text).map_err(|_|"malformed message")?;
 let subscribe=match v["type"].as_str() {Some("subscribe")=>true,Some("unsubscribe")=>false,_=>return Err("unknown type")};
 let channel=v["channel"].as_str().filter(|c|channel_ok(c)).ok_or("unsupported channel")?.to_owned();
 let products:Vec<String>=match &v["product_ids"] {
  Value::Null=>vec![],
  Value::Array(a)=>a.iter().map(|p|p.as_str().filter(|p|product_ok(p)).map(str::to_owned).ok_or("invalid product")).collect::<Result<_,_>>()?,
  _=>return Err("invalid product_ids"),
 };
 if products.len()>MAX_SUBS_PER_CLIENT {return Err("too many products")}
 if products.is_empty()&&channel!="heartbeats" {return Err("product_ids required")}
 Ok((subscribe,channel,products))
}

// ------------------------------------------------------------------ 注册表里的这一家

/// Coinbase 现货（USD 计价）。
pub struct Coinbase;
pub static COINBASE:Coinbase=Coinbase;

/// 看盘键里的 Coinbase 代号：`BASE-USD`，BASE 只有 ASCII 大写与数字。
pub fn symbol_ok(s:&str)->bool {
 s.len()<=40 && s.strip_suffix("-USD").is_some_and(|b|!b.is_empty() && b.bytes().all(|c|c.is_ascii_uppercase()||c.is_ascii_digit()))
}

impl super::Venue for Coinbase {
 fn source(&self)->&'static str {SOURCE}
 fn short_name(&self)->&'static str {"CB"}
 fn market(&self)->&'static str {"spot"}
 fn market_key(&self)->&'static str {"coinbase/spot"}
 fn symbol_ok(&self,symbol:&str)->bool {symbol_ok(symbol)}
 fn review(&self)->bool {true}
 /// 和界面上一样写 `BTC/USD`：「CB BTC/USD」。
 fn display(&self,symbol:&str)->String {super::labeled(self.short_name(),&symbol.replace('-',"/"))}
 fn webhook_name(&self,symbol:&str)->String {symbol.replace('-',"/")}
 fn pacer(&self)->Option<&'static Pacer> {Some(&PACER)}
 fn hosts(&self)->&'static [&'static str] {HOSTS}
 fn raw<'a>(&'a self,path:&'a str,query:&'a [(String,String)])->super::Fut<'a,Response> {Box::pin(raw(path,query))}
 fn stream(&self,ws:WebSocketUpgrade,_query:&[(String,String)])->Option<Response> {Some(ws.on_upgrade(serve_client))}
 fn candles<'a>(&'a self,symbol:&'a str,step:i64,start:i64,end:i64)->super::Fut<'a,Result<Vec<super::Bar>,Upstream>> {
  Box::pin(async move {
   let number=|s:&str|s.parse::<f64>().ok();
   Ok(candles(symbol,step,start,end).await?.into_iter().filter_map(|c|{
    let bar=super::Bar{open_time:c.start*1000,open:number(&c.open)?,high:number(&c.high)?,low:number(&c.low)?,close:number(&c.close)?,volume:number(&c.volume).unwrap_or(0.0)};
    bar.sane().then_some(bar)
   }).collect())
  })
 }
 fn alert_feed(&self)->Option<&'static dyn crate::alerts::KlineFeed> {Some(&alerts::FEED)}
}

#[cfg(test)]
mod tests {
 use super::*;

 #[test] fn only_public_market_paths_pass_through() {
  for ok in ["products","products/BTC-USD","products/BTC-USD/candles","products/ETH-USD/ticker"] {assert!(path_ok(ok),"{ok}")}
  for bad in ["","products/btc-usd","products/BTC-USD/book","accounts","products/BTC-USD/candles/x","products/../accounts","products/BTC%2FUSD"] {assert!(!path_ok(bad),"{bad}")}
  assert!(query_ok("granularity","ONE_MINUTE")&&!query_ok("granularity","ONE_MINUTE;x")&&!query_ok("limit","1;DROP")&&query_ok("product_type","SPOT")&&!query_ok("source","coinbase")&&!query_ok("api_key","x"));
 }

 #[test] fn candle_pages_come_back_ascending_and_valid() {
  let v=json!({"candles":[
   {"start":"1700000120","low":"1","high":"3","open":"2","close":"2.5","volume":"10"},
   {"start":"1700000060","low":"1","high":"3","open":"2","close":"2.5","volume":"10"},
   {"start":"1700000000","low":"0","high":"3","open":"2","close":"2.5","volume":"10"}]});
  let c=parse_candles(&v).unwrap();
  assert_eq!(c.iter().map(|c|c.start).collect::<Vec<_>>(),vec![1_700_000_060,1_700_000_120],"降序翻成升序，零价那根丢掉");
  assert_eq!(granularity(60),Some("ONE_MINUTE"));assert_eq!(granularity(180),None);
 }

 #[test] fn a_mixed_frame_is_split_per_product_and_a_single_one_is_passed_verbatim() {
  let single=r#"{"channel":"ticker","timestamp":"2026-09-22T00:00:00Z","events":[{"type":"update","tickers":[{"product_id":"BTC-USD","price":"1"}]}]}"#;
  let (channel,parts)=split(single).unwrap();
  assert_eq!(channel,"ticker");assert_eq!(parts.len(),1);assert_eq!(&*parts[0].1,single);
  let mixed=json!({"channel":"market_trades","events":[{"type":"update","trades":[{"product_id":"BTC-USD","price":"1"},{"product_id":"ETH-USD","price":"2"}]}]}).to_string();
  let (_,parts)=split(&mixed).unwrap();
  assert_eq!(parts.len(),2);
  let eth:Value=serde_json::from_str(&parts.iter().find(|(p,_)|p=="ETH-USD").unwrap().1).unwrap();
  assert_eq!(eth["events"][0]["trades"].as_array().unwrap().len(),1);
  assert_eq!(eth["events"][0]["trades"][0]["price"],"2");
 }

 #[test] fn control_frames_are_the_coinbase_shape_and_bounded() {
  assert_eq!(parse_control(r#"{"type":"subscribe","channel":"ticker","product_ids":["BTC-USD"]}"#).unwrap(),(true,"ticker".into(),vec!["BTC-USD".into()]));
  assert_eq!(parse_control(r#"{"type":"subscribe","channel":"heartbeats"}"#).unwrap(),(true,"heartbeats".into(),vec![]));
  assert!(parse_control(r#"{"type":"subscribe","channel":"level2","product_ids":["BTC-USD"]}"#).is_err());
  assert!(parse_control(r#"{"type":"subscribe","channel":"ticker","product_ids":["btc/usd"]}"#).is_err());
  assert!(parse_control(r#"{"type":"subscribe","channel":"ticker"}"#).is_err());
  assert_eq!(control("unsubscribe","candles",&["BTC-USD".into()]),r#"{"channel":"candles","product_ids":["BTC-USD"],"type":"unsubscribe"}"#);
 }

 #[tokio::test] async fn a_late_subscriber_gets_the_last_ticker_first_and_refs_are_counted() {
  let mut hub=Hub::default();
  let (a,mut ra)=mpsc::channel(8);let (b,mut rb)=mpsc::channel(8);
  hub.handle(Cmd::Join{id:1,tx:a});hub.handle(Cmd::Join{id:2,tx:b});
  hub.handle(Cmd::Change{id:1,subscribe:true,channel:"ticker".into(),products:vec!["BTC-USD".into()]});
  let frame=r#"{"channel":"ticker","events":[{"type":"snapshot","tickers":[{"product_id":"BTC-USD","price":"1"}]}]}"#;
  hub.route(frame);
  assert_eq!(&*ra.try_recv().unwrap(),frame);
  assert!(rb.try_recv().is_err(),"没订的不发");
  hub.handle(Cmd::Change{id:2,subscribe:true,channel:"ticker".into(),products:vec!["BTC-USD".into()]});
  assert_eq!(&*rb.try_recv().unwrap(),frame,"后来的先补最近一帧");
  assert_eq!(hub.refs.get(&("ticker".into(),"BTC-USD".into())),Some(&2));
  hub.handle(Cmd::Leave{id:1});
  assert_eq!(hub.refs.get(&("ticker".into(),"BTC-USD".into())),Some(&1));
  hub.handle(Cmd::Change{id:2,subscribe:false,channel:"ticker".into(),products:vec!["BTC-USD".into()]});
  assert!(hub.wanted().is_empty());
 }

 #[tokio::test] async fn after_the_upstream_drops_a_new_subscriber_is_not_replayed_a_stale_frame() {
  let mut hub=Hub::default();
  let (a,mut ra)=mpsc::channel(8);let (b,mut rb)=mpsc::channel(8);
  hub.handle(Cmd::Join{id:1,tx:a});hub.handle(Cmd::Join{id:2,tx:b});
  hub.handle(Cmd::Change{id:1,subscribe:true,channel:"ticker".into(),products:vec!["BTC-USD".into()]});
  hub.route(r#"{"channel":"ticker","events":[{"type":"update","tickers":[{"product_id":"BTC-USD","price":"1"}]}]}"#);
  assert!(ra.try_recv().is_ok());
  let mut upstream=None;
  hub.drop_upstream(&mut upstream);
  hub.handle(Cmd::Change{id:2,subscribe:true,channel:"ticker".into(),products:vec!["BTC-USD".into()]});
  assert!(rb.try_recv().is_err(),"断线前的那一帧不能当现价补给新订阅者");
  // 重连后上游推来的新帧照常补。
  let fresh=r#"{"channel":"ticker","events":[{"type":"snapshot","tickers":[{"product_id":"BTC-USD","price":"2"}]}]}"#;
  hub.route(fresh);
  assert_eq!(&*rb.try_recv().unwrap(),fresh);
 }

 #[test] fn iso_times_keep_milliseconds() {
  assert_eq!(iso_ms("1970-01-01T00:00:01.2345Z"),Some(1234));
  assert_eq!(iso_ms("2026-09-23T00:28:42.713058Z").map(|t|t%1000),Some(713));
 }

 /// 客户端先关，服务端要回一帧 Close，客户端那边才是干净的 1000（见 macro_index::stream 同名用例）。
 #[tokio::test] async fn a_client_close_is_answered_with_a_close_frame() {
  use tokio_tungstenite::tungstenite::{Error,Message as Frame,error::ProtocolError};
  let app=axum::Router::new().route("/s",axum::routing::get(|ws:axum::extract::WebSocketUpgrade|async move {ws.on_upgrade(serve_client)}));
  let listener=tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();let addr=listener.local_addr().unwrap();
  tokio::spawn(async move {axum::serve(listener,app).await.unwrap()});
  let (mut client,_)=tokio_tungstenite::connect_async(format!("ws://{addr}/s")).await.unwrap();
  client.close(None).await.unwrap();
  let answer=loop {
   match tokio::time::timeout(Duration::from_secs(5),client.next()).await.expect("服务端 5 秒内没回话") {
    Some(Ok(Frame::Close(_)))=>break Ok(()),
    Some(Ok(_))=>continue,
    Some(Err(Error::Protocol(ProtocolError::ResetWithoutClosingHandshake)))=>break Err("没回 Close 就断了"),
    other=>break Err(if other.is_none() {"流结束却没见到 Close"} else {"读出错"}),
   }
  };
  assert_eq!(answer,Ok(()));
 }
}
