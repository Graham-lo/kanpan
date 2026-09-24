//! 各家的连接：一条 WebSocket 一个任务，解出来的帧经 mpsc 交给跟踪器。
//!
//! * 币安 U 本位：深度走 `fstream …/public/stream`、成交走 `fstream …/market/stream`（两路分开，
//!   混在一条上只到一种，见 market_relay.rs 文件头）；币本位深度与成交同在 `dstream …/stream`；
//!   现货深度与成交同在 `data-stream.binance.vision/stream`。快照走 REST（合约 www.binance.com，
//!   过 `binance_gate`；现货 data-api.binance.vision）。**绝不接 `*.binancefuture.com`（测试网）。**
//! * OKX：`ws.okx.com:8443/ws/v5/public`，订 books + trades，每 20 秒发文本 `ping`。
//! * Coinbase：`advanced-trade-ws.coinbase.com`，一个产品一条连接（序号按整条连接计），
//!   level2 + market_trades + heartbeats。
//! * 任一条 60 秒没有任何帧（币安连 pong 都没有）就断开重连，退避 1 秒起、翻倍到 30 秒。
//! * 每次连上换一个全局递增的连接代号；簿按代号认帧，旧连接迟到的帧进不来。
use super::book::{Delta,Level,Message,Side,Snapshot,Trade,VenueInfo};
use crate::binance_gate;
use futures_util::{SinkExt,StreamExt};
use serde_json::Value;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64,Ordering};
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::time::Instant;
use tokio_tungstenite::tungstenite::{self,Message as Up};

const UM_DEPTH:&str="wss://fstream.binance.com/public/stream";
const UM_TRADES:&str="wss://fstream.binance.com/market/stream";
const CM:&str="wss://dstream.binance.com/stream";
const SPOT:&str="wss://data-stream.binance.vision/stream";
const OKX:&str="wss://ws.okx.com:8443/ws/v5/public";
const COINBASE:&str="wss://advanced-trade-ws.coinbase.com";
const UM_REST:&str="https://www.binance.com/fapi/v1/depth";
const CM_REST:&str="https://www.binance.com/dapi/v1/depth";
const SPOT_REST:&str="https://data-api.binance.vision/api/v3/depth";
const SNAPSHOT_LEVELS:usize=1000;
const PING:Duration=Duration::from_secs(20);
const IDLE:Duration=Duration::from_secs(60);
const CONNECT:Duration=Duration::from_secs(15);
const SEND:Duration=Duration::from_secs(10);
/// 币安一条组合流最多带几路（官方上限 1024；这里一只币十几路，给得很宽）。
const MAX_STREAMS:usize=200;

static CONNECTIONS:AtomicU64=AtomicU64::new(1);

/// 连接任务 → 跟踪器。
#[derive(Debug)]
pub enum Event {
 /// 带簿的连接连上了（只订成交的那条不发）。
 Opened{venues:Vec<String>,connection:u64},
 Closed{venues:Vec<String>,connection:u64},
 Frame{venue:String,connection:u64,message:Message},
 Trade{venue:String,trade:Trade},
 Snapshot{venue:String,connection:u64,snapshot:Option<Snapshot>},
}

/// 跟踪器 → 连接任务：重订某本簿的流内快照（OKX 退订再订；Coinbase 整条重连）。
#[derive(Debug)]
pub struct Resubscribe(pub String);

#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum Kind {BinanceUmDepth,BinanceUmTrades,BinanceCm,BinanceSpot,Okx,Coinbase}

/// 一条连接要订的东西。
#[derive(Clone,Debug)]
pub struct Socket {pub kind:Kind,pub venues:Vec<VenueInfo>}

impl Socket {
 fn carries_books(&self)->bool {self.kind!=Kind::BinanceUmTrades}
 fn url(&self)->String {
  let binance=|base:&str,suffixes:&[&str]| {
   let streams:Vec<String>=self.venues.iter().flat_map(|v|suffixes.iter().map(move|s|format!("{}@{s}",v.instrument.to_lowercase()))).collect();
   format!("{base}?streams={}",streams.join("/"))
  };
  match self.kind {
   Kind::BinanceUmDepth=>binance(UM_DEPTH,&["depth@100ms"]),
   Kind::BinanceUmTrades=>binance(UM_TRADES,&["aggTrade"]),
   Kind::BinanceCm=>binance(CM,&["depth@100ms","aggTrade"]),
   Kind::BinanceSpot=>binance(SPOT,&["depth@100ms","aggTrade"]),
   Kind::Okx=>OKX.into(),
   Kind::Coinbase=>COINBASE.into(),
  }
 }
 fn subscribe(&self)->Vec<String> {
  match self.kind {
   Kind::Okx=>self.venues.chunks(6).map(|chunk| {
    let args:Vec<Value>=chunk.iter().flat_map(|v|[serde_json::json!({"channel":"books","instId":v.instrument}),serde_json::json!({"channel":"trades","instId":v.instrument})]).collect();
    serde_json::json!({"op":"subscribe","args":args}).to_string()
   }).collect(),
   Kind::Coinbase=>{
    let product=self.venues.first().map(|v|v.instrument.clone()).unwrap_or_default();
    vec![serde_json::json!({"type":"subscribe","channel":"level2","product_ids":[product]}).to_string(),
     serde_json::json!({"type":"subscribe","channel":"market_trades","product_ids":[product]}).to_string(),
     serde_json::json!({"type":"subscribe","channel":"heartbeats"}).to_string()]
   },
   _=>Vec::new(),
  }
 }
 fn binance(&self)->bool {matches!(self.kind,Kind::BinanceUmDepth|Kind::BinanceUmTrades|Kind::BinanceCm)}
}

/// 把一只币的簿分到连接上：币安按市场、每条最多 `MAX_STREAMS` 路；OKX 一条最多 12 本；Coinbase 一本一条。
pub fn plan(venues:&[VenueInfo])->Vec<Socket> {
 let mut out=Vec::new();
 let group=|pred:&dyn Fn(&VenueInfo)->bool|->Vec<VenueInfo> {venues.iter().filter(|v|pred(v)).cloned().collect()};
 let binance_um=group(&|v|v.exchange=="binance"&&v.product!="spot"&&matches!(v.notional,super::model::Notional::Linear(_)));
 let binance_cm=group(&|v|v.exchange=="binance"&&v.product!="spot"&&matches!(v.notional,super::model::Notional::Inverse(_)));
 let binance_spot=group(&|v|v.exchange=="binance"&&v.product=="spot");
 for (kind,rows,per) in [(Kind::BinanceUmDepth,&binance_um,1),(Kind::BinanceUmTrades,&binance_um,1),(Kind::BinanceCm,&binance_cm,2),(Kind::BinanceSpot,&binance_spot,2)] {
  for chunk in rows.chunks(MAX_STREAMS/per) {out.push(Socket{kind,venues:chunk.to_vec()});}
 }
 for chunk in group(&|v|v.exchange=="okx").chunks(12) {out.push(Socket{kind:Kind::Okx,venues:chunk.to_vec()});}
 for v in group(&|v|v.exchange=="coinbase") {out.push(Socket{kind:Kind::Coinbase,venues:vec![v]});}
 out
}

// ------------------------------------------------------------------ 解帧

fn num(v:&Value)->Option<f64> {
 let x=match v {Value::String(s)=>s.parse::<f64>().ok()?,Value::Number(n)=>n.as_f64()?,_=>return None};
 x.is_finite().then_some(x)
}
fn int(v:&Value)->Option<i64> {match v {Value::Number(n)=>n.as_i64(),Value::String(s)=>s.parse().ok(),_=>None}}

/// `[[价, 量], …]`（币安、OKX 都是这个形状；OKX 每档后面还有两项，不看）。
fn levels(v:&Value,venue:&VenueInfo)->Option<Vec<Level>> {
 let rows=v.as_array()?;
 let mut out=Vec::with_capacity(rows.len());
 for row in rows {
  let (Some(p),Some(q))=(row.get(0).and_then(num),row.get(1).and_then(num)) else {return None};
  if p<=0.0||q<0.0 {return None}
  out.push(venue.level(p,q));
 }
 Some(out)
}

fn trade(venue:&VenueInfo,price:f64,quantity:f64,hit:Side)->Option<Trade> {
 if !(price>0.0&&quantity>0.0) {return None}
 let (price,quantity)=venue.level(price,quantity);
 Some(Trade{price,quantity,hit})
}

/// 一条连接收到的一帧 → （哪本簿，消息）。成交与簿分开发：成交不看连接代号。
pub enum Decoded {Book(String,Message),Trade(String,Trade)}

pub struct Decoder {kind:Kind,by_instrument:HashMap<String,VenueInfo>}

impl Decoder {
 pub fn new(socket:&Socket)->Self {
  let upper=matches!(socket.kind,Kind::BinanceUmDepth|Kind::BinanceUmTrades|Kind::BinanceCm|Kind::BinanceSpot);
  let by_instrument=socket.venues.iter().map(|v|(if upper {v.instrument.to_uppercase()} else {v.instrument.clone()},v.clone())).collect();
  Self{kind:socket.kind,by_instrument}
 }

 pub fn decode(&self,text:&str)->Vec<Decoded> {
  let Ok(frame)=serde_json::from_str::<Value>(text) else {return Vec::new()};
  match self.kind {Kind::Okx=>self.okx(&frame),Kind::Coinbase=>self.coinbase(&frame),_=>self.binance(&frame)}
 }

 fn binance(&self,frame:&Value)->Vec<Decoded> {
  let body=if frame.get("data").is_some_and(Value::is_object) {&frame["data"]} else {frame};
  let Some(venue)=body["s"].as_str().and_then(|s|self.by_instrument.get(&s.to_uppercase())) else {return Vec::new()};
  match body["e"].as_str() {
   Some("depthUpdate")=>{
    let (Some(first),Some(last),Some(bids),Some(asks))=(int(&body["U"]),int(&body["u"]),levels(&body["b"],venue),levels(&body["a"],venue)) else {return Vec::new()};
    let prev=if self.kind==Kind::BinanceSpot {None} else {int(&body["pu"])};
    vec![Decoded::Book(venue.id.clone(),Message::Delta(Delta{first,last,prev,bids,asks}))]
   },
   Some("aggTrade")=>{
    let (Some(p),Some(q))=(num(&body["p"]),num(&body["q"])) else {return Vec::new()};
    let hit=if body["m"].as_bool().unwrap_or(false) {Side::Bid} else {Side::Ask};
    trade(venue,p,q,hit).map(|t|Decoded::Trade(venue.id.clone(),t)).into_iter().collect()
   },
   _=>Vec::new(),
  }
 }

 fn okx(&self,frame:&Value)->Vec<Decoded> {
  if frame.get("event").is_some() {return Vec::new()}
  let arg=&frame["arg"];
  let Some(venue)=arg["instId"].as_str().and_then(|s|self.by_instrument.get(s)) else {return Vec::new()};
  let Some(items)=frame["data"].as_array() else {return Vec::new()};
  match arg["channel"].as_str() {
   Some("trades")=>items.iter().filter_map(|t| {
    let hit=match t["side"].as_str()? {"buy"=>Side::Ask,"sell"=>Side::Bid,_=>return None};
    trade(venue,num(&t["px"])?,num(&t["sz"])?,hit).map(|t|Decoded::Trade(venue.id.clone(),t))
   }).collect(),
   Some("books")=>{
    let (Some(action),[item])=(frame["action"].as_str(),items.as_slice()) else {return Vec::new()};
    let (Some(seq),Some(bids),Some(asks))=(int(&item["seqId"]),levels(&item["bids"],venue),levels(&item["asks"],venue)) else {return Vec::new()};
    let message=match action {
     "snapshot"=>Message::Snapshot(Snapshot{last:seq,requested:usize::MAX,bids,asks}),
     "update"=>{
      let Some(prev)=int(&item["prevSeqId"]) else {return Vec::new()};
      if seq<prev {Message::Reset} else {Message::Delta(Delta{first:seq,last:seq,prev:Some(prev),bids,asks})}
     },
     _=>return Vec::new(),
    };
    vec![Decoded::Book(venue.id.clone(),message)]
   },
   _=>Vec::new(),
  }
 }

 fn coinbase(&self,frame:&Value)->Vec<Decoded> {
  let Some(venue)=self.by_instrument.values().next() else {return Vec::new()};
  let Some(seq)=int(&frame["sequence_num"]) else {return Vec::new()};
  let id=venue.id.clone();
  let advance=||Decoded::Book(id.clone(),Message::Delta(Delta{first:seq,last:seq,prev:None,bids:vec![],asks:vec![]}));
  let events=frame["events"].as_array().map(Vec::as_slice).unwrap_or(&[]);
  match frame["channel"].as_str() {
   Some("l2_data")|Some("level2")=>{
    let (mut bids,mut asks,mut snapshot)=(Vec::new(),Vec::new(),false);
    for event in events.iter().filter(|e|e["product_id"].as_str()==Some(venue.instrument.as_str())) {
     if event["type"].as_str()==Some("snapshot") {snapshot=true;bids.clear();asks.clear();}
     for u in event["updates"].as_array().map(Vec::as_slice).unwrap_or(&[]) {
      let (Some(p),Some(q))=(num(&u["price_level"]),num(&u["new_quantity"])) else {continue};
      if p<=0.0||q<0.0 {continue}
      let level=venue.level(p,q);
      match u["side"].as_str() {Some("bid")=>bids.push(level),Some("offer")|Some("ask")=>asks.push(level),_=>{}}
     }
    }
    let message=if snapshot {
     Message::Snapshot(Snapshot{last:seq,requested:usize::MAX,bids,asks})
    } else {Message::Delta(Delta{first:seq,last:seq,prev:None,bids,asks})};
    vec![Decoded::Book(id,message)]
   },
   Some("market_trades")=>{
    let mut out=vec![advance()];
    for event in events.iter().filter(|e|e["type"].as_str()==Some("update")) {
     for t in event["trades"].as_array().map(Vec::as_slice).unwrap_or(&[]) {
      if t["product_id"].as_str()!=Some(venue.instrument.as_str()) {continue}
      let hit=match t["side"].as_str().map(str::to_uppercase).as_deref() {Some("BUY")=>Side::Ask,Some("SELL")=>Side::Bid,_=>continue};
      let (Some(p),Some(q))=(num(&t["price"]),num(&t["size"])) else {continue};
      if let Some(t)=trade(venue,p,q,hit) {out.push(Decoded::Trade(id.clone(),t));}
     }
    }
    out
   },
   _=>vec![advance()],
  }
 }
}

// ------------------------------------------------------------------ 连接任务

type Ws=tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

async fn open(socket:&Socket)->anyhow::Result<Ws> {
 if socket.binance()&&binance_gate::blocked() {anyhow::bail!("binance egress is on hold")}
 match tokio::time::timeout(CONNECT,tokio_tungstenite::connect_async(socket.url())).await {
  Ok(Ok((ws,_)))=>Ok(ws),
  Ok(Err(tungstenite::Error::Http(reply)))=>{
   if socket.binance() {binance_gate::note(reply.status().as_u16(),reply.headers().get("retry-after").and_then(|v|v.to_str().ok()));}
   anyhow::bail!("handshake refused with {}",reply.status())
  },
  Ok(Err(e))=>Err(e.into()),
  Err(_)=>anyhow::bail!("handshake timed out"),
 }
}

/// 一条连接的一生：连上、订阅、转帧，断了退避重连。`events` 那头关了（跟踪器停了）就结束。
pub async fn run(socket:Socket,events:mpsc::Sender<Event>,mut commands:mpsc::Receiver<Resubscribe>) {
 let decoder=Decoder::new(&socket);
 let ids:Vec<String>=socket.venues.iter().map(|v|v.id.clone()).collect();
 let mut backoff=Duration::from_secs(1);
 // 跟踪器只给带簿的连接留命令口；只订成交的那条（币安 U 本位 aggTrade）从来没有发送端，
 // `recv()` 立刻回 None——不能把它当成「跟踪器停了」退出（2026-09-24 线上就是这样丢了全部 U 本位成交），
 // 关掉这条分支接着转帧就是。跟踪器停了的判据是 `events` 那头关了。
 let mut commands_open=true;
 loop {
  if events.is_closed() {return}
  let ws=match open(&socket).await {
   Ok(ws)=>ws,
   Err(e)=>{
    tracing::debug!("Orderflow history: {:?} {} unreachable: {e}",socket.kind,ids.join(","));
    tokio::time::sleep(backoff).await;backoff=(backoff*2).min(Duration::from_secs(30));continue;
   },
  };
  let connection=CONNECTIONS.fetch_add(1,Ordering::Relaxed);
  let (mut tx,mut rx)=ws.split();
  let mut ok=true;
  for text in socket.subscribe() {
   if !matches!(tokio::time::timeout(SEND,tx.send(Up::Text(text.into()))).await,Ok(Ok(()))) {ok=false;break}
  }
  if ok&&socket.carries_books()&&events.send(Event::Opened{venues:ids.clone(),connection}).await.is_err() {return}
  let started=Instant::now();
  let mut ping=tokio::time::interval_at(Instant::now()+PING,PING);
  let mut deadline=Instant::now()+IDLE;
  while ok {
   tokio::select! {
    frame=rx.next()=>{
     let text=match frame {
      Some(Ok(Up::Text(text)))=>text,
      Some(Ok(Up::Close(_)))|Some(Err(_))|None=>break,
      Some(Ok(_))=>{deadline=Instant::now()+IDLE;continue},
     };
     deadline=Instant::now()+IDLE;
     for decoded in decoder.decode(text.as_str()) {
      let event=match decoded {
       Decoded::Book(venue,message)=>Event::Frame{venue,connection,message},
       Decoded::Trade(venue,trade)=>Event::Trade{venue,trade},
      };
      if events.send(event).await.is_err() {return}
     }
    },
    command=commands.recv(),if commands_open=>{
     let Some(Resubscribe(venue))=command else {commands_open=false;continue};
     match socket.kind {
      Kind::Okx=>{
       let Some(v)=socket.venues.iter().find(|v|v.id==venue) else {continue};
       for op in ["unsubscribe","subscribe"] {
        let text=serde_json::json!({"op":op,"args":[{"channel":"books","instId":v.instrument}]}).to_string();
        if !matches!(tokio::time::timeout(SEND,tx.send(Up::Text(text.into()))).await,Ok(Ok(()))) {ok=false;break}
       }
      },
      // Coinbase 的序号按整条连接计，只能整条重连。
      _=>break,
     }
    },
    _=ping.tick()=>{
     let frame=if socket.kind==Kind::Okx {Up::Text("ping".into())} else {Up::Ping(Default::default())};
     if !matches!(tokio::time::timeout(SEND,tx.send(frame)).await,Ok(Ok(()))) {break}
    },
    _=tokio::time::sleep_until(deadline)=>{tracing::debug!("Orderflow history: {:?} silent for {IDLE:?}",socket.kind);break},
   }
  }
  let _=tokio::time::timeout(Duration::from_secs(1),tx.close()).await;
  if socket.carries_books()&&events.send(Event::Closed{venues:ids.clone(),connection}).await.is_err() {return}
  // 活过一分钟的算正常断开，退避从头来。
  if started.elapsed()>Duration::from_secs(60) {backoff=Duration::from_secs(1)}
  tokio::time::sleep(backoff).await;
  backoff=(backoff*2).min(Duration::from_secs(30));
 }
}

/// 币安一本簿的 REST 快照（1000 档）。失败返回 None，由跟踪器 2 秒后再要。
pub async fn fetch_snapshot(venue:&VenueInfo)->Option<Snapshot> {
 let base=match (venue.product,venue.notional) {
  ("spot",_)=>SPOT_REST,
  (_,super::model::Notional::Inverse(_))=>CM_REST,
  _=>UM_REST,
 };
 let url=format!("{base}?symbol={}&limit={SNAPSHOT_LEVELS}",venue.instrument.to_uppercase());
 let gated=binance_gate::covers(&url);
 if gated&&binance_gate::blocked() {return None}
 let response=crate::market_meta::http().get(&url).timeout(Duration::from_secs(10)).send().await.ok()?;
 if gated&&binance_gate::note_reply(&response) {return None}
 let body:Value=response.error_for_status().ok()?.json().await.ok()?;
 parse_snapshot(&body,venue)
}

pub fn parse_snapshot(body:&Value,venue:&VenueInfo)->Option<Snapshot> {
 Some(Snapshot{last:int(&body["lastUpdateId"])?,requested:SNAPSHOT_LEVELS,bids:levels(&body["bids"],venue)?,asks:levels(&body["asks"],venue)?})
}

#[cfg(test)]
mod tests {
 use super::*;
 use super::super::book::Sequence;
 use super::super::model::Notional;

 fn v(exchange:&'static str,product:&'static str,instrument:&str,notional:Notional,scale:f64)->VenueInfo {
  VenueInfo{id:format!("{exchange}:{product}:{instrument}"),exchange,label:"x",product,instrument:instrument.into(),notional,price_scale:scale,
   sequence:Sequence::RangeOverlap,in_band:exchange!="binance"}
 }

 #[test] fn plan_splits_binance_by_market_and_never_touches_the_testnet() {
  let venues=vec![v("binance","usdtPerp","BTCUSDT",Notional::Linear(1.0),1.0),v("binance","coinPerp","BTCUSD_PERP",Notional::Inverse(100.0),1.0),
   v("binance","spot","BTCUSDT",Notional::Linear(1.0),1.0),v("okx","usdtPerp","BTC-USDT-SWAP",Notional::Linear(0.01),1.0),v("coinbase","spot","BTC-USD",Notional::Linear(1.0),1.0)];
  let sockets=plan(&venues);
  let urls:Vec<String>=sockets.iter().map(Socket::url).collect();
  assert_eq!(urls,vec![
   "wss://fstream.binance.com/public/stream?streams=btcusdt@depth@100ms".to_string(),
   "wss://fstream.binance.com/market/stream?streams=btcusdt@aggTrade".into(),
   "wss://dstream.binance.com/stream?streams=btcusd_perp@depth@100ms/btcusd_perp@aggTrade".into(),
   "wss://data-stream.binance.vision/stream?streams=btcusdt@depth@100ms/btcusdt@aggTrade".into(),
   OKX.into(),COINBASE.into()]);
  assert!(urls.iter().all(|u|!u.contains("binancefuture")));
  assert!(!sockets[1].carries_books());
 }

 #[test] fn binance_frames_scale_prices_to_one_coin() {
  let socket=Socket{kind:Kind::BinanceUmDepth,venues:vec![v("binance","usdtPerp","1000PEPEUSDT",Notional::Linear(1.0),1000.0)]};
  let d=Decoder::new(&socket);
  let out=d.decode(r#"{"stream":"1000pepeusdt@depth@100ms","data":{"e":"depthUpdate","s":"1000PEPEUSDT","U":5,"u":7,"pu":4,"b":[["0.0120","100"]],"a":[]}}"#);
  let [Decoded::Book(id,Message::Delta(delta))]=out.as_slice() else {panic!("one delta")};
  assert_eq!(id,"binance:usdtPerp:1000PEPEUSDT");
  assert_eq!((delta.first,delta.last,delta.prev),(5,7,Some(4)));
  assert!((delta.bids[0].0-0.000012).abs()<1e-12&&(delta.bids[0].1-100_000.0).abs()<1e-6);
  let socket=Socket{kind:Kind::BinanceUmTrades,venues:socket.venues};
  let out=Decoder::new(&socket).decode(r#"{"data":{"e":"aggTrade","s":"1000PEPEUSDT","p":"0.012","q":"5","m":true}}"#);
  let [Decoded::Trade(_,t)]=out.as_slice() else {panic!("one trade")};
  assert_eq!(t.hit,Side::Bid);
 }

 #[test] fn okx_books_and_trades() {
  let socket=Socket{kind:Kind::Okx,venues:vec![v("okx","usdtPerp","BTC-USDT-SWAP",Notional::Linear(0.01),1.0)]};
  let d=Decoder::new(&socket);
  let snap=d.decode(r#"{"arg":{"channel":"books","instId":"BTC-USDT-SWAP"},"action":"snapshot","data":[{"bids":[["60000","10","0","1"]],"asks":[["60001","2","0","1"]],"seqId":9,"prevSeqId":-1}]}"#);
  assert!(matches!(snap.as_slice(),[Decoded::Book(_,Message::Snapshot(s))] if s.last==9&&s.bids.len()==1));
  let reset=d.decode(r#"{"arg":{"channel":"books","instId":"BTC-USDT-SWAP"},"action":"update","data":[{"bids":[],"asks":[],"seqId":3,"prevSeqId":9}]}"#);
  assert!(matches!(reset.as_slice(),[Decoded::Book(_,Message::Reset)]));
  let trades=d.decode(r#"{"arg":{"channel":"trades","instId":"BTC-USDT-SWAP"},"data":[{"px":"60000","sz":"3","side":"buy"}]}"#);
  assert!(matches!(trades.as_slice(),[Decoded::Trade(_,t)] if t.hit==Side::Ask));
  assert!(d.decode(r#"{"event":"subscribe","arg":{"channel":"books","instId":"BTC-USDT-SWAP"}}"#).is_empty());
 }

 #[test] fn coinbase_advances_the_connection_sequence_on_every_frame() {
  let socket=Socket{kind:Kind::Coinbase,venues:vec![v("coinbase","spot","BTC-USD",Notional::Linear(1.0),1.0)]};
  let d=Decoder::new(&socket);
  let snap=d.decode(r#"{"channel":"l2_data","sequence_num":4,"events":[{"type":"snapshot","product_id":"BTC-USD","updates":[{"side":"bid","price_level":"60000","new_quantity":"1"},{"side":"offer","price_level":"60001","new_quantity":"2"}]}]}"#);
  assert!(matches!(snap.as_slice(),[Decoded::Book(_,Message::Snapshot(s))] if s.last==4&&s.asks.len()==1));
  let hb=d.decode(r#"{"channel":"heartbeats","sequence_num":5,"events":[]}"#);
  assert!(matches!(hb.as_slice(),[Decoded::Book(_,Message::Delta(x))] if x.first==5&&x.bids.is_empty()));
  let trades=d.decode(r#"{"channel":"market_trades","sequence_num":6,"events":[{"type":"snapshot","trades":[{"product_id":"BTC-USD","price":"1","size":"1","side":"BUY"}]},{"type":"update","trades":[{"product_id":"BTC-USD","price":"60000","size":"1","side":"SELL"}]}]}"#);
  assert_eq!(trades.len(),2,"快照里的历史成交不算");
  assert!(matches!(&trades[1],Decoded::Trade(_,t) if t.hit==Side::Bid));
 }

 #[test] fn rest_snapshot_parses() {
  let venue=v("binance","usdtPerp","BTCUSDT",Notional::Linear(1.0),1.0);
  let s=parse_snapshot(&serde_json::json!({"lastUpdateId":77,"bids":[["60000","1"]],"asks":[["60001","2"]]}),&venue).unwrap();
  assert_eq!((s.last,s.requested,s.bids.len()),(77,1000,1));
 }
}
