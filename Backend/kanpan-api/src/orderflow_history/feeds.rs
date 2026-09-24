//! 各家的行情流：地址、流名、解帧。连接怎么建、怎么合并、怎么换新见 `hub.rs`；REST 快照排队见 `snapshots.rs`。
//!
//! * 币安 U 本位：深度走 `fstream …/public/stream`、成交走 `fstream …/market/stream`（两路分开，
//!   混在一条上只到一种，见 market_relay.rs 文件头）；币本位深度与成交同在 `dstream …/stream`；
//!   现货深度与成交同在 `data-stream.binance.vision/stream`。**绝不接 `*.binancefuture.com`（测试网）。**
//!   全部是组合流：订哪些流直接写进 URL（`?streams=a/b/c`），一条最多 200 路，连上之后不再发 SUBSCRIBE
//!   （币安每条连接每秒最多收 10 条消息，逐条订一多就被断）。
//! * 深度用 `@depth@500ms`（合约）/ `@depth`（现货只有 1000ms 与 100ms 两档，取 1000ms）。合并逻辑不依赖 100ms：
//!   大单的出现 / 消失是每 500ms 评估一轮、两次确认间隔 ≥ 300ms，看的是本地簿在评估那一刻的状态；
//!   增量推得慢只是同一档的几次改动被币安先合成一次再推，序号照样首尾相接（`pu` / `U..u`），簿的接续不受影响。
//!   成交（aggTrade）是逐笔实时的，成交归因不受深度推送频率影响。
//! * OKX：`ws.okx.com:8443/ws/v5/public`，订 books + trades，每 20 秒发文本 `ping`。
//! * Coinbase：`advanced-trade-ws.coinbase.com`，一个产品一条连接（序号按整条连接计），
//!   level2 + market_trades + heartbeats。
use super::book::{Delta,Level,Message,Side,Snapshot,Trade,VenueInfo};
use serde_json::Value;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64,Ordering};

pub const UM_DEPTH:&str="wss://fstream.binance.com/public/stream";
pub const UM_TRADES:&str="wss://fstream.binance.com/market/stream";
pub const CM:&str="wss://dstream.binance.com/stream";
pub const SPOT:&str="wss://data-stream.binance.vision/stream";
pub const OKX:&str="wss://ws.okx.com:8443/ws/v5/public";
pub const COINBASE:&str="wss://advanced-trade-ws.coinbase.com";
pub const SNAPSHOT_LEVELS:usize=1000;
/// 币安一条组合流最多带几路。官方上限 1024，这里按 200：URL 不至于太长，一条断了影响面也小。
pub const MAX_STREAMS:usize=200;
/// OKX 一条连接最多挂几本簿（每本 books + trades 两个频道）。OKX 没有硬上限，50 本一条时单条的推送量
/// 与 Binance 一条满载的组合流相当。
pub const OKX_PER_CONNECTION:usize=50;

static CONNECTIONS:AtomicU64=AtomicU64::new(1);
/// 每次连上换一个全局递增的连接代号；簿按代号认帧，旧连接迟到的帧进不来。
pub fn next_connection()->u64 {CONNECTIONS.fetch_add(1,Ordering::Relaxed)}

/// 连接任务 → 跟踪器。
#[derive(Debug)]
pub enum Event {
 /// 带簿的连接（重新）连上了：簿从头来（只订成交的那种连接不发）。
 Opened{venues:Vec<String>,connection:u64},
 /// 新连接接手这几本簿：推的是同一串全局序号，簿接着用，两条连接的帧都认（见 `VenueBook::handover`）。
 Handover{venues:Vec<String>,connection:u64},
 Closed{venues:Vec<String>,connection:u64},
 Frame{venue:String,connection:u64,message:Message},
 /// `id`：币安 aggTrade 的 `a`。交接期间两条连接会推同一笔，跟踪器按它去重。
 Trade{venue:String,trade:Trade,id:Option<i64>},
 /// `epoch`：发请求时簿的 `VenueBook::epoch`，对不上的丢掉。
 Snapshot{venue:String,epoch:u64,snapshot:Option<Snapshot>},
}

#[derive(Clone,Copy,Debug,PartialEq,Eq,Hash,PartialOrd,Ord)]
pub enum Kind {BinanceUmDepth,BinanceUmTrades,BinanceCm,BinanceSpot,Okx,Coinbase}

pub const KINDS:[Kind;6]=[Kind::BinanceUmDepth,Kind::BinanceUmTrades,Kind::BinanceCm,Kind::BinanceSpot,Kind::Okx,Kind::Coinbase];

impl Kind {
 pub fn index(self)->usize {self as usize}
 pub fn binance(self)->bool {matches!(self,Kind::BinanceUmDepth|Kind::BinanceUmTrades|Kind::BinanceCm|Kind::BinanceSpot)}
 /// 只订成交的那种连接不管簿，不发 Opened / Handover / Closed。
 pub fn carries_books(self)->bool {self!=Kind::BinanceUmTrades}
 /// 币安一本簿在这种连接上占几路流。
 pub fn suffixes(self)->&'static [&'static str] {
  match self {
   Kind::BinanceUmDepth=>&["depth@500ms"],
   Kind::BinanceUmTrades=>&["aggTrade"],
   Kind::BinanceCm=>&["depth@500ms","aggTrade"],
   // 现货没有 500ms 档：`@depth` 是 1000ms。
   Kind::BinanceSpot=>&["depth","aggTrade"],
   Kind::Okx|Kind::Coinbase=>&[],
  }
 }
 /// 一条连接最多挂几本簿。
 pub fn capacity(self)->usize {
  match self {
   Kind::Okx=>OKX_PER_CONNECTION,
   Kind::Coinbase=>1,
   _=>MAX_STREAMS/self.suffixes().len(),
  }
 }
 pub fn label(self)->&'static str {
  match self {
   Kind::BinanceUmDepth=>"binance-um-depth",Kind::BinanceUmTrades=>"binance-um-trades",Kind::BinanceCm=>"binance-cm",
   Kind::BinanceSpot=>"binance-spot",Kind::Okx=>"okx",Kind::Coinbase=>"coinbase",
  }
 }
 /// 连接地址。币安把这条连接的全部流写进 URL；OKX / Coinbase 连上之后再订。
 pub fn url(self,venues:&[&VenueInfo])->String {
  let base=match self {
   Kind::BinanceUmDepth=>UM_DEPTH,Kind::BinanceUmTrades=>UM_TRADES,Kind::BinanceCm=>CM,Kind::BinanceSpot=>SPOT,
   Kind::Okx=>return OKX.into(),Kind::Coinbase=>return COINBASE.into(),
  };
  let streams:Vec<String>=venues.iter().flat_map(|v|self.suffixes().iter().map(move|s|format!("{}@{s}",v.instrument.to_lowercase()))).collect();
  format!("{base}?streams={}",streams.join("/"))
 }
}

/// 一本簿要挂在哪几种连接上：币安 U 本位深度与成交分两种；其余一家一种。
pub fn kinds_of(v:&VenueInfo)->&'static [Kind] {
 match (v.exchange,v.product,v.notional) {
  ("binance","spot",_)=>&[Kind::BinanceSpot],
  ("binance",_,super::model::Notional::Inverse(_))=>&[Kind::BinanceCm],
  ("binance",_,_)=>&[Kind::BinanceUmDepth,Kind::BinanceUmTrades],
  ("okx",_,_)=>&[Kind::Okx],
  _=>&[Kind::Coinbase],
 }
}

/// OKX 订 / 退一批簿：一条消息带一批 args（一条消息算一次操作，限额是每条连接每小时 480 次），
/// 每条最多 20 本（40 个 args，约 2 KB，远小于 64 KB 的消息上限）。
pub fn okx_ops(op:&str,instruments:&[&str],books_only:bool)->Vec<String> {
 instruments.chunks(20).map(|chunk| {
  let args:Vec<Value>=chunk.iter().flat_map(|i| {
   let mut a=vec![serde_json::json!({"channel":"books","instId":i})];
   if !books_only {a.push(serde_json::json!({"channel":"trades","instId":i}));}
   a
  }).collect();
  serde_json::json!({"op":op,"args":args}).to_string()
 }).collect()
}

pub fn coinbase_subscribe(product:&str)->Vec<String> {
 vec![serde_json::json!({"type":"subscribe","channel":"level2","product_ids":[product]}).to_string(),
  serde_json::json!({"type":"subscribe","channel":"market_trades","product_ids":[product]}).to_string(),
  serde_json::json!({"type":"subscribe","channel":"heartbeats"}).to_string()]
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
pub enum Decoded {Book(String,Message),Trade(String,Trade,Option<i64>)}

/// 一条连接的解码器。挂在这条连接上的簿会变（OKX 动态订退、币安交接后退掉旧簿），所以可增删。
pub struct Decoder {kind:Kind,by_instrument:HashMap<String,VenueInfo>}

impl Decoder {
 pub fn new(kind:Kind)->Self {Self{kind,by_instrument:HashMap::new()}}
 fn key(&self,instrument:&str)->String {if self.kind.binance() {instrument.to_uppercase()} else {instrument.to_string()}}
 pub fn insert(&mut self,venue:&VenueInfo) {let key=self.key(&venue.instrument);self.by_instrument.insert(key,venue.clone());}
 pub fn remove(&mut self,venue:&VenueInfo) {let key=self.key(&venue.instrument);self.by_instrument.remove(&key);}

 pub fn decode(&self,text:&str)->Vec<Decoded> {
  let Ok(frame)=serde_json::from_str::<Value>(text) else {return Vec::new()};
  match self.kind {Kind::Okx=>self.okx(&frame),Kind::Coinbase=>self.coinbase(&frame),_=>self.binance(&frame)}
 }

 /// OKX 的 `{"event":"error",…}`：订阅被拒（限额、频道名错），交给连接任务记日志。
 pub fn okx_error(text:&str)->Option<String> {
  let frame:Value=serde_json::from_str(text).ok()?;
  (frame["event"].as_str()==Some("error")).then(||format!("{} {}",frame["code"].as_str().unwrap_or("?"),frame["msg"].as_str().unwrap_or("")))
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
    trade(venue,p,q,hit).map(|t|Decoded::Trade(venue.id.clone(),t,int(&body["a"]))).into_iter().collect()
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
    trade(venue,num(&t["px"])?,num(&t["sz"])?,hit).map(|t|Decoded::Trade(venue.id.clone(),t,None))
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
      if let Some(t)=trade(venue,p,q,hit) {out.push(Decoded::Trade(id.clone(),t,None));}
     }
    }
    out
   },
   _=>vec![advance()],
  }
 }
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
 fn decoder(kind:Kind,venues:&[VenueInfo])->Decoder {let mut d=Decoder::new(kind);for v in venues {d.insert(v);}d}

 #[test] fn urls_split_binance_by_market_use_slow_depth_and_never_touch_the_testnet() {
  let um=v("binance","usdtPerp","BTCUSDT",Notional::Linear(1.0),1.0);
  let eth=v("binance","usdtPerp","ETHUSDT",Notional::Linear(1.0),1.0);
  let cm=v("binance","coinPerp","BTCUSD_PERP",Notional::Inverse(100.0),1.0);
  let spot=v("binance","spot","BTCUSDT",Notional::Linear(1.0),1.0);
  let okx=v("okx","usdtPerp","BTC-USDT-SWAP",Notional::Linear(0.01),1.0);
  let cb=v("coinbase","spot","BTC-USD",Notional::Linear(1.0),1.0);
  assert_eq!(kinds_of(&um),&[Kind::BinanceUmDepth,Kind::BinanceUmTrades]);
  assert_eq!(kinds_of(&cm),&[Kind::BinanceCm]);
  assert_eq!(kinds_of(&spot),&[Kind::BinanceSpot]);
  assert_eq!((kinds_of(&okx),kinds_of(&cb)),(&[Kind::Okx][..],&[Kind::Coinbase][..]));
  let urls=vec![Kind::BinanceUmDepth.url(&[&um,&eth]),Kind::BinanceUmTrades.url(&[&um]),Kind::BinanceCm.url(&[&cm]),Kind::BinanceSpot.url(&[&spot]),
   Kind::Okx.url(&[&okx]),Kind::Coinbase.url(&[&cb])];
  assert_eq!(urls,vec![
   "wss://fstream.binance.com/public/stream?streams=btcusdt@depth@500ms/ethusdt@depth@500ms".to_string(),
   "wss://fstream.binance.com/market/stream?streams=btcusdt@aggTrade".into(),
   "wss://dstream.binance.com/stream?streams=btcusd_perp@depth@500ms/btcusd_perp@aggTrade".into(),
   "wss://data-stream.binance.vision/stream?streams=btcusdt@depth/btcusdt@aggTrade".into(),
   OKX.into(),COINBASE.into()]);
  assert!(urls.iter().all(|u|!u.contains("binancefuture")&&!u.contains("@100ms")));
  assert!(!Kind::BinanceUmTrades.carries_books());
  assert_eq!((Kind::BinanceUmDepth.capacity(),Kind::BinanceCm.capacity(),Kind::BinanceSpot.capacity(),Kind::Okx.capacity(),Kind::Coinbase.capacity()),(200,100,100,50,1));
 }

 #[test] fn okx_subscribes_in_batches_under_the_message_limit() {
  let names:Vec<String>=(0..45).map(|i|format!("C{i}-USDT-SWAP")).collect();
  let refs:Vec<&str>=names.iter().map(String::as_str).collect();
  let ops=okx_ops("subscribe",&refs,false);
  assert_eq!(ops.len(),3,"45 本分 20 / 20 / 5 三条");
  assert!(ops.iter().all(|m|m.len()<64*1024));
  let first:Value=serde_json::from_str(&ops[0]).unwrap();
  assert_eq!(first["args"].as_array().unwrap().len(),40);
  let books:Value=serde_json::from_str(&okx_ops("unsubscribe",&refs[..1],true)[0]).unwrap();
  assert_eq!(books,serde_json::json!({"op":"unsubscribe","args":[{"channel":"books","instId":"C0-USDT-SWAP"}]}));
  assert_eq!(Decoder::okx_error(r#"{"event":"error","code":"60014","msg":"Requests too frequent."}"#).as_deref(),Some("60014 Requests too frequent."));
  assert!(Decoder::okx_error(r#"{"event":"subscribe"}"#).is_none());
 }

 #[test] fn binance_frames_scale_prices_to_one_coin() {
  let venues=[v("binance","usdtPerp","1000PEPEUSDT",Notional::Linear(1.0),1000.0)];
  let d=decoder(Kind::BinanceUmDepth,&venues);
  let out=d.decode(r#"{"stream":"1000pepeusdt@depth@500ms","data":{"e":"depthUpdate","s":"1000PEPEUSDT","U":5,"u":7,"pu":4,"b":[["0.0120","100"]],"a":[]}}"#);
  let [Decoded::Book(id,Message::Delta(delta))]=out.as_slice() else {panic!("one delta")};
  assert_eq!(id,"binance:usdtPerp:1000PEPEUSDT");
  assert_eq!((delta.first,delta.last,delta.prev),(5,7,Some(4)));
  assert!((delta.bids[0].0-0.000012).abs()<1e-12&&(delta.bids[0].1-100_000.0).abs()<1e-6);
  let mut trades=decoder(Kind::BinanceUmTrades,&venues);
  let text=r#"{"data":{"e":"aggTrade","s":"1000PEPEUSDT","a":42,"p":"0.012","q":"5","m":true}}"#;
  let out=trades.decode(text);
  let [Decoded::Trade(_,t,id)]=out.as_slice() else {panic!("one trade")};
  assert_eq!((t.hit,*id),(Side::Bid,Some(42)));
  trades.remove(&venues[0]);
  assert!(trades.decode(text).is_empty(),"退掉的簿不再解");
 }

 #[test] fn okx_books_and_trades() {
  let d=decoder(Kind::Okx,&[v("okx","usdtPerp","BTC-USDT-SWAP",Notional::Linear(0.01),1.0)]);
  let snap=d.decode(r#"{"arg":{"channel":"books","instId":"BTC-USDT-SWAP"},"action":"snapshot","data":[{"bids":[["60000","10","0","1"]],"asks":[["60001","2","0","1"]],"seqId":9,"prevSeqId":-1}]}"#);
  assert!(matches!(snap.as_slice(),[Decoded::Book(_,Message::Snapshot(s))] if s.last==9&&s.bids.len()==1));
  let reset=d.decode(r#"{"arg":{"channel":"books","instId":"BTC-USDT-SWAP"},"action":"update","data":[{"bids":[],"asks":[],"seqId":3,"prevSeqId":9}]}"#);
  assert!(matches!(reset.as_slice(),[Decoded::Book(_,Message::Reset)]));
  let trades=d.decode(r#"{"arg":{"channel":"trades","instId":"BTC-USDT-SWAP"},"data":[{"px":"60000","sz":"3","side":"buy"}]}"#);
  assert!(matches!(trades.as_slice(),[Decoded::Trade(_,t,None)] if t.hit==Side::Ask));
  assert!(d.decode(r#"{"event":"subscribe","arg":{"channel":"books","instId":"BTC-USDT-SWAP"}}"#).is_empty());
  assert!(d.decode("pong").is_empty());
 }

 #[test] fn coinbase_advances_the_connection_sequence_on_every_frame() {
  let d=decoder(Kind::Coinbase,&[v("coinbase","spot","BTC-USD",Notional::Linear(1.0),1.0)]);
  let snap=d.decode(r#"{"channel":"l2_data","sequence_num":4,"events":[{"type":"snapshot","product_id":"BTC-USD","updates":[{"side":"bid","price_level":"60000","new_quantity":"1"},{"side":"offer","price_level":"60001","new_quantity":"2"}]}]}"#);
  assert!(matches!(snap.as_slice(),[Decoded::Book(_,Message::Snapshot(s))] if s.last==4&&s.asks.len()==1));
  let hb=d.decode(r#"{"channel":"heartbeats","sequence_num":5,"events":[]}"#);
  assert!(matches!(hb.as_slice(),[Decoded::Book(_,Message::Delta(x))] if x.first==5&&x.bids.is_empty()));
  let trades=d.decode(r#"{"channel":"market_trades","sequence_num":6,"events":[{"type":"snapshot","trades":[{"product_id":"BTC-USD","price":"1","size":"1","side":"BUY"}]},{"type":"update","trades":[{"product_id":"BTC-USD","price":"60000","size":"1","side":"SELL"}]}]}"#);
  assert_eq!(trades.len(),2,"快照里的历史成交不算");
  assert!(matches!(&trades[1],Decoded::Trade(_,t,_) if t.hit==Side::Bid));
 }

 #[test] fn rest_snapshot_parses() {
  let venue=v("binance","usdtPerp","BTCUSDT",Notional::Linear(1.0),1.0);
  let s=parse_snapshot(&serde_json::json!({"lastUpdateId":77,"bids":[["60000","1"]],"asks":[["60001","2"]]}),&venue).unwrap();
  assert_eq!((s.last,s.requested,s.bids.len()),(77,1000,1));
 }
}
