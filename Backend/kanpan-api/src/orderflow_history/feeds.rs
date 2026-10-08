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
/// 币安 REST 深度快照要几档：合约（U 本位、币本位）最多 1000；现货最多 5000（权重 250，见 `snapshots`）。
pub const SNAPSHOT_LEVELS:usize=1000;
pub const SPOT_SNAPSHOT_LEVELS:usize=5000;
/// OKX `books` 频道：快照与增量都只到前 400 档（窗口增量，见 `book::Levels`）。
pub const OKX_BOOK_LEVELS:usize=400;
/// 这本币安簿的 REST 快照要几档。
pub fn snapshot_levels(venue:&VenueInfo)->usize {if venue.product=="spot" {SPOT_SNAPSHOT_LEVELS} else {SNAPSHOT_LEVELS}}
/// 币安一条组合流最多带几路。官方上限 1024，这里按 200：URL 不至于太长，一条断了影响面也小。
pub const MAX_STREAMS:usize=200;
/// OKX 一条连接最多挂几本簿（每本 books + trades 两个频道）。OKX 没有硬上限，50 本一条时单条的推送量
/// 与 Binance 一条满载的组合流相当。
pub const OKX_PER_CONNECTION:usize=50;
/// Bybit 一条连接最多挂几本簿（每本 `orderbook.1000` + `publicTrade` 两个话题）。官方没写单连接上限，
/// 按契约取 50；一条订阅消息最多 10 个 args（5 本），见 [`bybit_ops`]。
pub const BYBIT_PER_CONNECTION:usize=50;
/// Bybit `orderbook.1000`：快照与增量都只到前 1000 档（滑动窗口）。
pub const BYBIT_BOOK_LEVELS:usize=1000;
/// Hyperliquid 跟踪这一路在共用 hub 里占的名额（每本 `l2Book` + `trades` 两个话题，见 `venues::hyperliquid::hub`）。
pub const HL_TRACKING_CAPACITY:usize=300;
/// Hyperliquid `l2Book` 一帧至少 20 档（4 位有效数字聚合之后两侧各最多 20 档），整本就是这一帧。
pub const HL_BOOK_LEVELS:usize=20;

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
 /// `at`：交易所给的成交时刻（毫秒；币安 `T`、OKX `ts`、Coinbase `time`），足迹图与秒线按它分秒、分钟。
 Trade{venue:String,trade:Trade,id:Option<i64>,at:Option<i64>},
 /// `epoch`：发请求时簿的 `VenueBook::epoch`，对不上的丢掉。
 Snapshot{venue:String,epoch:u64,snapshot:Option<Snapshot>},
}

#[derive(Clone,Copy,Debug,PartialEq,Eq,Hash,PartialOrd,Ord)]
pub enum Kind {BinanceUmDepth,BinanceUmTrades,BinanceCm,BinanceSpot,Okx,Coinbase,BybitSpot,BybitLinear,BybitInverse,Hyperliquid}

pub const KINDS:[Kind;10]=[Kind::BinanceUmDepth,Kind::BinanceUmTrades,Kind::BinanceCm,Kind::BinanceSpot,Kind::Okx,Kind::Coinbase,
 Kind::BybitSpot,Kind::BybitLinear,Kind::BybitInverse,Kind::Hyperliquid];

impl Kind {
 pub fn index(self)->usize {self as usize}
 pub fn binance(self)->bool {matches!(self,Kind::BinanceUmDepth|Kind::BinanceUmTrades|Kind::BinanceCm|Kind::BinanceSpot)}
 pub fn bybit(self)->bool {matches!(self,Kind::BybitSpot|Kind::BybitLinear|Kind::BybitInverse)}
 /// 连上之后再一批批订 / 退的那几种（OKX、Bybit）：一条连接挂多本，簿进出不用重连。
 pub fn batched(self)->bool {self==Kind::Okx||self.bybit()}
 /// Bybit 这一类在 URL 里的名字。
 pub fn bybit_category(self)->Option<&'static str> {
  match self {Kind::BybitSpot=>Some("spot"),Kind::BybitLinear=>Some("linear"),Kind::BybitInverse=>Some("inverse"),_=>None}
 }
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
   _=>&[],
  }
 }
 /// 一条连接最多挂几本簿。
 pub fn capacity(self)->usize {
  match self {
   Kind::Okx=>OKX_PER_CONNECTION,
   Kind::Coinbase=>1,
   Kind::BybitSpot|Kind::BybitLinear|Kind::BybitInverse=>BYBIT_PER_CONNECTION,
   Kind::Hyperliquid=>HL_TRACKING_CAPACITY,
   _=>MAX_STREAMS/self.suffixes().len(),
  }
 }
 pub fn label(self)->&'static str {
  match self {
   Kind::BinanceUmDepth=>"binance-um-depth",Kind::BinanceUmTrades=>"binance-um-trades",Kind::BinanceCm=>"binance-cm",
   Kind::BinanceSpot=>"binance-spot",Kind::Okx=>"okx",Kind::Coinbase=>"coinbase",
   Kind::BybitSpot=>"bybit-spot",Kind::BybitLinear=>"bybit-linear",Kind::BybitInverse=>"bybit-inverse",Kind::Hyperliquid=>"hyperliquid",
  }
 }
 /// 连接地址。币安把这条连接的全部流写进 URL；OKX / Coinbase 连上之后再订。
 #[cfg(test)]
 pub fn url(self,venues:&[&VenueInfo])->String {self.url_at(venues,0)}
 /// 第 `attempt` 次连接的地址：Bybit 主域名与备用域名 `stream.bytick.com` 轮着用（主域名连不上时下一次换备用）。
 pub fn url_at(self,venues:&[&VenueInfo],attempt:u32)->String {
  if let Some(category)=self.bybit_category() {
   let bases=crate::venues::bybit::WS_BASES;
   return format!("{}/{category}",bases[attempt as usize%bases.len()]);
  }
  let base=match self {
   Kind::BinanceUmDepth=>UM_DEPTH,Kind::BinanceUmTrades=>UM_TRADES,Kind::BinanceCm=>CM,Kind::BinanceSpot=>SPOT,
   Kind::Okx=>return OKX.into(),Kind::Coinbase=>return COINBASE.into(),
   Kind::Hyperliquid=>return crate::venues::hyperliquid::hub::WS.into(),
   Kind::BybitSpot|Kind::BybitLinear|Kind::BybitInverse=>unreachable!(),
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
  ("bybit","spot",_)=>&[Kind::BybitSpot],
  ("bybit",_,super::model::Notional::Inverse(_))=>&[Kind::BybitInverse],
  ("bybit",_,_)=>&[Kind::BybitLinear],
  ("hyperliquid",_,_)=>&[Kind::Hyperliquid],
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

/// Bybit 订 / 退一批簿：一条消息最多 10 个 args（官方上限），即 5 本（`orderbook.1000` + `publicTrade`）；
/// `books_only` 只动簿那一个话题（断档后退订再订，拿一份新快照，成交不断）。
pub fn bybit_ops(op:&str,instruments:&[&str],books_only:bool)->Vec<String> {
 let args:Vec<String>=instruments.iter().flat_map(|i| {
  let mut a=vec![format!("orderbook.{BYBIT_BOOK_LEVELS}.{i}")];
  if !books_only {a.push(format!("publicTrade.{i}"));}
  a
 }).collect();
 args.chunks(10).map(|chunk|serde_json::json!({"op":op,"args":chunk}).to_string()).collect()
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
/// 成交带（簿，成交，成交号，交易所给的成交时刻）。
pub enum Decoded {Book(String,Message),Trade(String,Trade,Option<i64>,Option<i64>)}

/// 一条连接的解码器。挂在这条连接上的簿会变（OKX 动态订退、币安交接后退掉旧簿），所以可增删。
pub struct Decoder {kind:Kind,by_instrument:HashMap<String,VenueInfo>,
 /// Hyperliquid：每个币订上（或上游重连）之后第一帧 `trades` 是最近几笔的回放，不是新成交；
 /// 币 → （还要丢的第一帧，此刻之前的成交一律不要）。
 fresh:HashMap<String,(bool,i64)>}

impl Decoder {
 pub fn new(kind:Kind)->Self {Self{kind,by_instrument:HashMap::new(),fresh:HashMap::new()}}
 /// 这个币刚订上 / 上游刚重连：下一帧成交是回放，丢掉；`now` 之前的成交也不算（见 `fresh`）。
 pub fn subscribed(&mut self,instrument:&str,now:i64) {self.fresh.insert(instrument.to_string(),(true,now));}
 fn key(&self,instrument:&str)->String {if self.kind.binance() {instrument.to_uppercase()} else {instrument.to_string()}}
 pub fn insert(&mut self,venue:&VenueInfo) {let key=self.key(&venue.instrument);self.by_instrument.insert(key,venue.clone());}
 pub fn remove(&mut self,venue:&VenueInfo) {let key=self.key(&venue.instrument);self.by_instrument.remove(&key);self.fresh.remove(&key);}

 pub fn decode(&mut self,text:&str)->Vec<Decoded> {
  let Ok(frame)=serde_json::from_str::<Value>(text) else {return Vec::new()};
  match self.kind {
   Kind::Okx=>self.okx(&frame),Kind::Coinbase=>self.coinbase(&frame),
   Kind::BybitSpot|Kind::BybitLinear|Kind::BybitInverse=>self.bybit(&frame),
   Kind::Hyperliquid=>self.hyperliquid(&frame),
   _=>self.binance(&frame),
  }
 }

 /// Bybit 的订阅回执 `{"success":false,"ret_msg":…,"op":"subscribe"}`：订阅被拒，交给连接任务记日志。
 pub fn bybit_error(text:&str)->Option<String> {
  let frame:Value=serde_json::from_str(text).ok()?;
  (frame["success"].as_bool()==Some(false)).then(||format!("{} {}",frame["op"].as_str().unwrap_or("?"),frame["ret_msg"].as_str().unwrap_or("")))
 }

 /// Hyperliquid 的 `{"channel":"error","data":…}`（订阅被拒、超了 hub 的名额）。
 pub fn hyperliquid_error(text:&str)->Option<String> {
  let frame:Value=serde_json::from_str(text).ok()?;
  (frame["channel"].as_str()==Some("error")).then(||frame["data"].to_string())
 }

 /// `orderbook.1000.X`：`snapshot` 整本重来，`delta` 按 `u` 加一接续（`u`=1 是对面服务重启后的新快照）；
 /// `publicTrade.X`：`S`=Buy 是主动买，吃的是卖盘。Bybit 的成交号是 UUID，不带号（交接期不去重）。
 fn bybit(&self,frame:&Value)->Vec<Decoded> {
  let Some(topic)=frame["topic"].as_str() else {return Vec::new()};
  if let Some(rest)=topic.strip_prefix("publicTrade.") {
   let Some(venue)=self.by_instrument.get(rest) else {return Vec::new()};
   let items=frame["data"].as_array().map(Vec::as_slice).unwrap_or(&[]);
   return items.iter().filter_map(|t| {
    let hit=match t["S"].as_str()? {"Buy"=>Side::Ask,"Sell"=>Side::Bid,_=>return None};
    trade(venue,num(&t["p"])?,num(&t["v"])?,hit).map(|x|Decoded::Trade(venue.id.clone(),x,None,int(&t["T"])))
   }).collect();
  }
  let Some(rest)=topic.strip_prefix("orderbook.") else {return Vec::new()};
  let Some(venue)=rest.split_once('.').and_then(|(_,i)|self.by_instrument.get(i)) else {return Vec::new()};
  let data=&frame["data"];
  let (Some(u),Some(bids),Some(asks))=(int(&data["u"]),levels(&data["b"],venue),levels(&data["a"],venue)) else {return Vec::new()};
  let message=match frame["type"].as_str() {
   Some("snapshot")=>Message::Snapshot(Snapshot{last:u,requested:BYBIT_BOOK_LEVELS,bids,asks}),
   Some("delta")=>Message::Delta(Delta{first:u,last:u,prev:None,bids,asks}),
   _=>return Vec::new(),
  };
  vec![Decoded::Book(venue.id.clone(),message)]
 }

 /// `l2Book`：每帧都是整本（4 位有效数字聚合），按 `time` 排先后；`trades`：`side` B 是主动买、吃卖盘。
 /// Hyperliquid 的成交号 `tid` 不保证单调，不带号；订上之后的第一帧成交与订之前的成交丢掉（见 `fresh`）。
 fn hyperliquid(&mut self,frame:&Value)->Vec<Decoded> {
  let data=&frame["data"];
  match frame["channel"].as_str() {
   Some("l2Book")=>{
    let Some(venue)=data["coin"].as_str().and_then(|c|self.by_instrument.get(c)) else {return Vec::new()};
    let Some(time)=int(&data["time"]) else {return Vec::new()};
    let side=|i:usize|->Option<Vec<Level>> {
     let rows=data["levels"].get(i)?.as_array()?;
     let mut out=Vec::with_capacity(rows.len());
     for row in rows {
      let (Some(p),Some(q))=(num(&row["px"]),num(&row["sz"])) else {return None};
      if p<=0.0||q<0.0 {return None}
      out.push(venue.level(p,q));
     }
     Some(out)
    };
    let (Some(bids),Some(asks))=(side(0),side(1)) else {return Vec::new()};
    let requested=HL_BOOK_LEVELS.max(bids.len()).max(asks.len());
    vec![Decoded::Book(venue.id.clone(),Message::Snapshot(Snapshot{last:time,requested,bids,asks}))]
   },
   Some("trades")=>{
    let Some(items)=data.as_array() else {return Vec::new()};
    let Some(coin)=items.first().and_then(|t|t["coin"].as_str()) else {return Vec::new()};
    let Some(venue)=self.by_instrument.get(coin) else {return Vec::new()};
    let since=match self.fresh.get_mut(coin) {
     Some((first,since))=>{if *first {*first=false;return Vec::new()} *since},
     None=>i64::MIN,
    };
    items.iter().filter_map(|t| {
     if t["coin"].as_str()!=Some(coin) {return None}
     let at=int(&t["time"])?;
     if at<since {return None}
     let hit=match t["side"].as_str()? {"B"=>Side::Ask,"A"=>Side::Bid,_=>return None};
     trade(venue,num(&t["px"])?,num(&t["sz"])?,hit).map(|x|Decoded::Trade(venue.id.clone(),x,None,Some(at)))
    }).collect()
   },
   _=>Vec::new(),
  }
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
    trade(venue,p,q,hit).map(|t|Decoded::Trade(venue.id.clone(),t,int(&body["a"]),int(&body["T"]))).into_iter().collect()
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
    let at=int(&t["ts"]);
    trade(venue,num(&t["px"])?,num(&t["sz"])?,hit).map(|t|Decoded::Trade(venue.id.clone(),t,None,at))
   }).collect(),
   Some("books")=>{
    let (Some(action),[item])=(frame["action"].as_str(),items.as_slice()) else {return Vec::new()};
    let (Some(seq),Some(bids),Some(asks))=(int(&item["seqId"]),levels(&item["bids"],venue),levels(&item["asks"],venue)) else {return Vec::new()};
    let message=match action {
     "snapshot"=>Message::Snapshot(Snapshot{last:seq,requested:OKX_BOOK_LEVELS,bids,asks}),
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
      let at=t["time"].as_str().and_then(|v|chrono::DateTime::parse_from_rfc3339(v).ok()).map(|v|v.timestamp_millis());
      if let Some(t)=trade(venue,p,q,hit) {out.push(Decoded::Trade(id.clone(),t,None,at));}
     }
    }
    out
   },
   _=>vec![advance()],
  }
 }
}

pub fn parse_snapshot(body:&Value,venue:&VenueInfo)->Option<Snapshot> {
 Some(Snapshot{last:int(&body["lastUpdateId"])?,requested:snapshot_levels(venue),bids:levels(&body["bids"],venue)?,asks:levels(&body["asks"],venue)?})
}

#[cfg(test)]
mod tests {
 use super::*;
 use super::super::book::Sequence;
 use super::super::model::Notional;

 fn v(exchange:&'static str,product:&'static str,instrument:&str,notional:Notional,scale:f64)->VenueInfo {
  VenueInfo{id:format!("{exchange}:{product}:{instrument}"),exchange,label:"x",product,instrument:instrument.into(),notional,price_scale:scale,
   sequence:Sequence::RangeOverlap,in_band:exchange!="binance",sliding:exchange=="okx"}
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
  let mut d=decoder(Kind::BinanceUmDepth,&venues);
  let out=d.decode(r#"{"stream":"1000pepeusdt@depth@500ms","data":{"e":"depthUpdate","s":"1000PEPEUSDT","U":5,"u":7,"pu":4,"b":[["0.0120","100"]],"a":[]}}"#);
  let [Decoded::Book(id,Message::Delta(delta))]=out.as_slice() else {panic!("one delta")};
  assert_eq!(id,"binance:usdtPerp:1000PEPEUSDT");
  assert_eq!((delta.first,delta.last,delta.prev),(5,7,Some(4)));
  assert!((delta.bids[0].0-0.000012).abs()<1e-12&&(delta.bids[0].1-100_000.0).abs()<1e-6);
  let mut trades=decoder(Kind::BinanceUmTrades,&venues);
  let text=r#"{"data":{"e":"aggTrade","s":"1000PEPEUSDT","a":42,"p":"0.012","q":"5","m":true,"T":1700000000123}}"#;
  let out=trades.decode(text);
  let [Decoded::Trade(_,t,id,at)]=out.as_slice() else {panic!("one trade")};
  assert_eq!((t.hit,*id,*at),(Side::Bid,Some(42),Some(1_700_000_000_123)));
  trades.remove(&venues[0]);
  assert!(trades.decode(text).is_empty(),"退掉的簿不再解");
 }

 #[test] fn okx_books_and_trades() {
  let mut d=decoder(Kind::Okx,&[v("okx","usdtPerp","BTC-USDT-SWAP",Notional::Linear(0.01),1.0)]);
  let snap=d.decode(r#"{"arg":{"channel":"books","instId":"BTC-USDT-SWAP"},"action":"snapshot","data":[{"bids":[["60000","10","0","1"]],"asks":[["60001","2","0","1"]],"seqId":9,"prevSeqId":-1}]}"#);
  assert!(matches!(snap.as_slice(),[Decoded::Book(_,Message::Snapshot(s))] if s.last==9&&s.bids.len()==1&&s.requested==400),"OKX 快照只到 400 档，不是全簿");
  let reset=d.decode(r#"{"arg":{"channel":"books","instId":"BTC-USDT-SWAP"},"action":"update","data":[{"bids":[],"asks":[],"seqId":3,"prevSeqId":9}]}"#);
  assert!(matches!(reset.as_slice(),[Decoded::Book(_,Message::Reset)]));
  let trades=d.decode(r#"{"arg":{"channel":"trades","instId":"BTC-USDT-SWAP"},"data":[{"px":"60000","sz":"3","side":"buy","ts":"1700000000456"}]}"#);
  assert!(matches!(trades.as_slice(),[Decoded::Trade(_,t,None,Some(1_700_000_000_456))] if t.hit==Side::Ask));
  assert!(d.decode(r#"{"event":"subscribe","arg":{"channel":"books","instId":"BTC-USDT-SWAP"}}"#).is_empty());
  assert!(d.decode("pong").is_empty());
 }

 #[test] fn coinbase_advances_the_connection_sequence_on_every_frame() {
  let mut d=decoder(Kind::Coinbase,&[v("coinbase","spot","BTC-USD",Notional::Linear(1.0),1.0)]);
  let snap=d.decode(r#"{"channel":"l2_data","sequence_num":4,"events":[{"type":"snapshot","product_id":"BTC-USD","updates":[{"side":"bid","price_level":"60000","new_quantity":"1"},{"side":"offer","price_level":"60001","new_quantity":"2"}]}]}"#);
  assert!(matches!(snap.as_slice(),[Decoded::Book(_,Message::Snapshot(s))] if s.last==4&&s.asks.len()==1));
  let hb=d.decode(r#"{"channel":"heartbeats","sequence_num":5,"events":[]}"#);
  assert!(matches!(hb.as_slice(),[Decoded::Book(_,Message::Delta(x))] if x.first==5&&x.bids.is_empty()));
  let trades=d.decode(r#"{"channel":"market_trades","sequence_num":6,"events":[{"type":"snapshot","trades":[{"product_id":"BTC-USD","price":"1","size":"1","side":"BUY"}]},{"type":"update","trades":[{"product_id":"BTC-USD","price":"60000","size":"1","side":"SELL","time":"2023-11-14T22:13:20.789Z"}]}]}"#);
  assert_eq!(trades.len(),2,"快照里的历史成交不算");
  assert!(matches!(&trades[1],Decoded::Trade(_,t,_,Some(1_700_000_000_789)) if t.hit==Side::Bid));
 }

 #[test] fn rest_snapshot_parses() {
  let venue=v("binance","usdtPerp","BTCUSDT",Notional::Linear(1.0),1.0);
  let s=parse_snapshot(&serde_json::json!({"lastUpdateId":77,"bids":[["60000","1"]],"asks":[["60001","2"]]}),&venue).unwrap();
  assert_eq!((s.last,s.requested,s.bids.len()),(77,1000,1));
  let spot=v("binance","spot","BTCUSDT",Notional::Linear(1.0),1.0);
  let s=parse_snapshot(&serde_json::json!({"lastUpdateId":78,"bids":[["60000","1"]],"asks":[["60001","2"]]}),&spot).unwrap();
  assert_eq!(s.requested,5000,"现货快照要 5000 档");
 }

 // 下面几帧是 2026-10-08 在 kanpan-sg 上连 Bybit / Hyperliquid 录下来的原样帧（只截短了档位）。
 #[test] fn bybit_books_trades_and_pongs() {
  let linear=v("bybit","usdtPerp","BTCUSDT",Notional::Linear(1.0),1.0);
  let mut d=decoder(Kind::BybitLinear,&[linear.clone()]);
  let snap=r#"{"topic":"orderbook.1000.BTCUSDT","type":"snapshot","ts":1791457528402,"data":{"s":"BTCUSDT","b":[["82642.80","1.336"],["82642.70","0.017"]],"a":[["82642.90","4.575"],["82643.20","0.002"]],"u":33344277,"seq":822323444395},"cts":1791457528401}"#;
  match &d.decode(snap)[..] {
   [Decoded::Book(id,Message::Snapshot(s))]=>{
    assert_eq!((id.as_str(),s.last,s.requested),("bybit:usdtPerp:BTCUSDT",33344277,1000));
    assert_eq!((s.bids[0],s.asks[1]),((82642.8,1.336),(82643.2,0.002)));
   },
   other=>panic!("{}",other.len()),
  }
  let delta=r#"{"topic":"orderbook.1000.BTCUSDT","type":"delta","ts":1791457528603,"data":{"s":"BTCUSDT","b":[["82642.80","1.034"],["82636.00","0"]],"a":[],"u":33344278,"seq":822323444500},"cts":1791457528602}"#;
  match &d.decode(delta)[..] {
   [Decoded::Book(_,Message::Delta(x))]=>{assert_eq!((x.first,x.last,x.prev),(33344278,33344278,None));assert_eq!(x.bids,vec![(82642.8,1.034),(82636.0,0.0)]);},
   _=>panic!("delta"),
  }
  let trade=r#"{"topic":"publicTrade.BTCUSDT","type":"snapshot","ts":1791457528912,"data":[{"T":1791457528911,"s":"BTCUSDT","S":"Buy","v":"0.011","p":"82642.90","L":"PlusTick","i":"5be1261b-d231-533b-89cd-0653c4f333be","BT":false,"RPI":false,"seq":822323446907},{"T":1791457528913,"s":"BTCUSDT","S":"Sell","v":"0.2","p":"82642.80","i":"x","BT":false}]}"#;
  match &d.decode(trade)[..] {
   [Decoded::Trade(_,a,None,Some(1791457528911)),Decoded::Trade(_,b,None,Some(1791457528913))]=>{
    assert_eq!((a.hit,a.price,a.quantity),(Side::Ask,82642.9,0.011),"S=Buy 是主动买、吃卖盘");
    assert_eq!(b.hit,Side::Bid);
   },
   _=>panic!("trade"),
  }
  for quiet in [r#"{"success":true,"ret_msg":"pong","conn_id":"db294p9abbveig58ile0-ozeu","req_id":"","op":"ping"}"#,
   r#"{"success":true,"ret_msg":"","conn_id":"db294p9abbveig58ile0-ozeu","req_id":"","op":"subscribe"}"#,
   r#"{"topic":"orderbook.1000.ETHUSDT","type":"delta","ts":1,"data":{"s":"ETHUSDT","b":[],"a":[],"u":5}}"#] {
   assert!(d.decode(quiet).is_empty());
   assert!(Decoder::bybit_error(quiet).is_none());
  }
  assert_eq!(Decoder::bybit_error(r#"{"success":false,"ret_msg":"error:handler not found","conn_id":"x","op":"subscribe"}"#).as_deref(),Some("subscribe error:handler not found"));
  // 币本位：量是张数（1 张 1 美元），现货：`i` 是数字串，一样不带号。
  let inverse=v("bybit","coinPerp","BTCUSD",Notional::Inverse(1.0),1.0);
  let mut d=decoder(Kind::BybitInverse,&[inverse]);
  let delta=r#"{"topic":"orderbook.1000.BTCUSD","type":"delta","ts":1791457527205,"data":{"s":"BTCUSD","b":[["82564.70","499"],["82564.50","0"]],"a":[["82586.50","40199"]],"u":32949562,"seq":118895328882},"cts":1791457527203}"#;
  assert!(matches!(&d.decode(delta)[..],[Decoded::Book(id,Message::Delta(x))] if id=="bybit:coinPerp:BTCUSD"&&x.last==32949562&&x.asks==vec![(82586.5,40199.0)]));
  let spot=v("bybit","spot","BTCUSDT",Notional::Linear(1.0),1.0);
  let mut d=decoder(Kind::BybitSpot,&[spot]);
  let trade=r#"{"topic":"publicTrade.BTCUSDT","ts":1791457528952,"type":"snapshot","data":[{"i":"2290000001227213949","T":1791457528951,"p":"82680","v":"0.001185","S":"Buy","seq":115115351336,"s":"BTCUSDT","BT":false,"RPI":false}]}"#;
  assert!(matches!(&d.decode(trade)[..],[Decoded::Trade(id,t,None,Some(1791457528951))] if id=="bybit:spot:BTCUSDT"&&t.hit==Side::Ask));
 }

 #[test] fn bybit_urls_ops_and_capacity() {
  let one=v("bybit","usdtPerp","BTCUSDT",Notional::Linear(1.0),1.0);
  assert_eq!(Kind::BybitLinear.url_at(&[&one],0),"wss://stream.bybit.com/v5/public/linear");
  assert_eq!(Kind::BybitLinear.url_at(&[&one],1),"wss://stream.bytick.com/v5/public/linear","连不上换备用域名");
  assert_eq!(Kind::BybitSpot.url_at(&[&one],2),"wss://stream.bybit.com/v5/public/spot");
  assert_eq!(Kind::BybitInverse.url(&[&one]),"wss://stream.bybit.com/v5/public/inverse");
  assert_eq!((Kind::BybitLinear.capacity(),Kind::Hyperliquid.capacity()),(50,300));
  let names:Vec<String>=(0..12).map(|i|format!("A{i}USDT")).collect();
  let refs:Vec<&str>=names.iter().map(String::as_str).collect();
  let ops=bybit_ops("subscribe",&refs,false);
  assert_eq!(ops.len(),3,"一条最多 10 个 args：12 本 24 个话题 → 10 + 10 + 4");
  let first:Value=serde_json::from_str(&ops[0]).unwrap();
  assert_eq!(first["args"].as_array().unwrap().len(),10);
  assert_eq!(first["args"][0],"orderbook.1000.A0USDT");
  assert_eq!(first["args"][1],"publicTrade.A0USDT");
  assert_eq!(bybit_ops("unsubscribe",&["BTCUSDT"],true),vec![r#"{"args":["orderbook.1000.BTCUSDT"],"op":"unsubscribe"}"#.to_string()],"断档只退订簿");
  assert!(ops.iter().all(|o|!o.contains("binancefuture")));
 }

 #[test] fn hyperliquid_books_and_trades() {
  let btc=v("hyperliquid","usdtPerp","BTC",Notional::Linear(1.0),1.0);
  let pepe=v("hyperliquid","usdtPerp","kPEPE",Notional::Linear(1.0),1000.0);
  let mut d=decoder(Kind::Hyperliquid,&[btc,pepe]);
  let book=r#"{"channel":"l2Book","data":{"coin":"BTC","time":1791457528112,"levels":[[{"px":"82640.0","sz":"7.50863","n":31},{"px":"82630.0","sz":"25.79214","n":63},{"px":"82620.0","sz":"76.81878","n":71}],[{"px":"82650.0","sz":"9.37405","n":30},{"px":"82660.0","sz":"31.91316","n":76},{"px":"82670.0","sz":"51.15626","n":69}]]}}"#;
  match &d.decode(book)[..] {
   [Decoded::Book(id,Message::Snapshot(s))]=>{
    assert_eq!((id.as_str(),s.last,s.requested),("hyperliquid:usdtPerp:BTC",1791457528112,20));
    assert_eq!((s.bids.len(),s.asks.len(),s.bids[0],s.asks[2]),(3,3,(82640.0,7.50863),(82670.0,51.15626)));
   },
   _=>panic!("book"),
  }
  // kPEPE 是一千个 PEPE：价按 1000 拆回单个 PEPE、量乘回 1000（和币安 1000PEPEUSDT 落进同一个价位）。
  let pepe_book=r#"{"channel":"l2Book","data":{"coin":"kPEPE","time":1791457528657,"levels":[[{"px":"0.004031","sz":"773030.0","n":4}],[{"px":"0.004032","sz":"243777.0","n":1}]]}}"#;
  match &d.decode(pepe_book)[..] {
   [Decoded::Book(_,Message::Snapshot(s))]=>{assert!((s.bids[0].0-0.000004031).abs()<1e-15);assert!((s.bids[0].1-773030000.0).abs()<1e-3);},
   _=>panic!("pepe"),
  }
  // 订上之后第一帧成交是回放：整帧丢掉；之后订阅那一刻之前的成交也不要。
  d.subscribed("BTC",1791457522700);
  let replay=r#"{"channel":"trades","data":[{"coin":"BTC","side":"B","px":"82625.0","sz":"0.00025","time":1791457522600,"hash":"0x0c","tid":615263281857618}]}"#;
  assert!(d.decode(replay).is_empty(),"第一帧回放丢掉");
  let live=r#"{"channel":"trades","data":[{"coin":"BTC","side":"B","px":"82625.0","sz":"0.00025","time":1791457522600,"hash":"0x0c","tid":615263281857618},{"coin":"BTC","side":"A","px":"82627.0","sz":"0.00242","time":1791457522888,"hash":"0x3a","tid":351151329239414}]}"#;
  match &d.decode(live)[..] {
   [Decoded::Trade(id,t,None,Some(1791457522888))]=>{assert_eq!((id.as_str(),t.hit,t.price,t.quantity),("hyperliquid:usdtPerp:BTC",Side::Bid,82627.0,0.00242));},
   other=>panic!("{}",other.len()),
  }
  let buy=r#"{"channel":"trades","data":[{"coin":"BTC","side":"B","px":"82625.0","sz":"1","time":1791457523000,"tid":1}]}"#;
  assert!(matches!(&d.decode(buy)[..],[Decoded::Trade(_,t,None,_)] if t.hit==Side::Ask),"B 是主动买、吃卖盘");
  for quiet in [r#"{"channel":"subscriptionResponse","data":{"method":"subscribe","subscription":{"type":"l2Book","coin":"BTC","nSigFigs":4,"mantissa":null,"fast":false}}}"#,
   r#"{"channel":"l2Book","data":{"coin":"ETH","time":1,"levels":[[],[]]}}"#] {assert!(d.decode(quiet).is_empty())}
  assert_eq!(Decoder::hyperliquid_error(r#"{"channel":"error","data":"Already subscribed"}"#).as_deref(),Some(r#""Already subscribed""#));
 }

}
