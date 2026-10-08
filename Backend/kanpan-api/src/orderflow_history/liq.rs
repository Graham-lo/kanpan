//! 爆仓（强平）分钟聚合（2026-10-08，网页版底部「大单」抽屉里独立的一块「爆仓」）。
//!
//! 为什么自己攒：币安没有强平历史接口（09-22 砍掉强平功能的原因之一），只能从接入这天起在服务端常驻收推送、按分钟攒 3 天；
//! 网页只要「每分钟多空各爆了多少、最大一笔多大」，不逐笔存。
//!
//! 规则：
//! * 源（2026-10-08 在新加坡 VPS 上实测过帧，见 ops/README「爆仓分钟聚合」）：
//!   - 币安 U 本位 `wss://fstream.binance.com/market/ws/!forceOrder@arr`：2026 年 fstream 分 `/public` 与 `/market` 两路，
//!     强平在 `/market`（老的 `/ws/` 连得上但一条不推）。帧 `{"e":"forceOrder","E",…,"o":{"s","S","q","p","ap","X","l","z","T",…}}`。
//!     `S`=SELL 是多头被平（系统卖出平多），BUY 是空头被平。名义 = 均价 `ap` × 已成交 `z`（缺了退回 `p` × `q`），USDT / USDC 当美元。
//!     **币安是抽样**：每个品种 1 秒内只推最后一条，同一秒里别的强平单看不到，所以币安那份是下限。
//!   - 币安币本位 `wss://dstream.binance.com/ws/!forceOrder@arr`：同样的帧，`q` / `z` 是张数，名义 = 张数 × 合约面值（contractSize 美元）。
//!     实测这条地址眼下也推 U 本位的单（和上一条逐条相同），所以每条连接只认自己那一族的代号
//!     （币本位 `…USD_PERP` / `…USD_yymmdd`，其余算 U 本位），不重复记。
//!   - OKX `wss://ws.okx.com:8443/ws/v5/public` 订 `liquidation-orders` 的 SWAP 与 FUTURES 两路（一条连接、一条订阅请求）。
//!     帧 `{"arg":…,"data":[{"instId","instFamily","instType","details":[{"side","posSide","bkPx","sz","ts"}]}]}`；`side`=sell 是多头被平。
//!     名义：U 本位 = bkPx × sz × 面值（ctVal×ctMult，币），币本位 = sz × 面值（美元）。
//!   - Coinbase 只接现货，没有强平。
//! * 品种 → base 与面值：用 `orderflow_instruments` 的合约表（每 30 秒按此刻跟踪的 base 重建一次映射）。先按交易所代号查；
//!   查不到的 OKX 按 instFamily、币安按交易对（`BTCUSD_PERP` → `BTCUSD`）借同一族的面值（同族面值相同，周 / 月交割、USDC 永续靠这条）；
//!   币安 U 本位再查不到的按代号去掉交割后缀与 USDT / USDC、再去 `1000` 前缀（名义不要面值）。拿不到面值的丢掉，每小时报数。
//!   **只记服务端正在跟踪的 base**（`REGISTRY`），其余直接丢。
//! * 分钟：交易所给的时刻离本机 10 秒以内才信，否则用本机收到的时刻（和足迹一样）；全进程一份累加器，每秒看一次，
//!   分钟末 + 3 秒宽限之后交给写库任务；宽限之后才到的作为增量再交一次（写库时加上去）。
//! * 写库、清理、接口全照 `flow.rs`：一个写库任务攒批合并同一（base，分钟）、多行 INSERT 写 `orderflow_liq`（迁移 0052），
//!   金额与笔数相加、最大一笔取大；占 `WRITE_SLOTS`；通道满了丢这一分钟。每小时和订单流的清理一起逐只 base 删 3 天以前的，
//!   220 只 3 天最多约 95 万行，不设体积闸门。停机（`CLOSING`）把手上没交的分钟全部交出去，`super::shutdown` 等它们写完（同一个 10 秒上限）。
//! * 接口 `GET /v1/market/orderflow/liq?base=&from=&to=` → `{"base","tracked","rows":[[minute_ms,多头被平,空头被平,笔数,最大一笔,最大一笔价格,哪边,哪家],…]}`：
//!   哪边 0 多头被平 / 1 空头被平，哪家 0 币安 / 1 OKX；金额取整美元，价格原样。区间、`tracked:false`（不读库）、不要登录、
//!   20 秒合并读库、gzip、`Cache-Control: public, max-age=20`、读库占 `HISTORY_READS`，全和 `flow.rs` 一致。
//! * 连接照 `hub.rs`：建连走同一个节拍器（`hub::open`：币安全部连接共用、两次至少隔 1 秒、5 分钟最多 60 条、尊重币安封禁闸门；
//!   OKX 至少隔 400 毫秒），断线退避 1 秒起翻倍封顶 30 秒、带 ±50% 抖动，连上活过一分钟的退避从头来；每 20 秒 ping
//!   （OKX 发文本 `ping`），60 秒一帧没有就断开重连；OKX `{"event":"error"}` 打 warn；断连只打 debug，每小时一行 info 报数。
//! * 只聚合，不判定。
use super::feeds::{Decoder,Kind};
use super::hub::{self,Ws};
use super::{Answer,Answers,CLOSING,HISTORY_READS,POOL,REGISTRY,WRITE_SLOTS,accepts_gzip,json_number,now_ms,packed,store};
use crate::AppState;
use crate::error::{ApiError,Params,Result};
use crate::orderflow_instruments::{self as instruments,Exchange,Notional,Product,Venue};
use axum::extract::State;
use axum::response::Response;
use futures_util::{SinkExt,StreamExt};
use serde::Deserialize;
use serde_json::Value;
use sqlx::{PgPool,Row as _};
use std::collections::{BTreeMap,HashMap};
use std::sync::atomic::{AtomicBool,AtomicU64,AtomicUsize,Ordering};
use std::sync::{Arc,Mutex,OnceLock,RwLock};
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::time::Instant;
use tokio_tungstenite::tungstenite::Message as Up;

pub(super) const PATH:&str="/v1/market/orderflow/liq";
const MINUTE_MS:i64=60_000;
/// 分钟末之后再等多久才交：交易所时刻与本机差一点、推送晚到一点都还算进这一分钟。
const GRACE_MS:i64=3_000;
/// 交易所给的时刻离本机多远以内才信。
const TRUST_MS:i64=10_000;
/// 同样的请求合成一次读库、答复留多久；也是答复头上 `max-age` 的秒数。
const LIQ_TTL:Duration=Duration::from_secs(20);
const CACHE_CONTROL:&str="public, max-age=20";
const MAX_SPAN_MS:i64=store::RETENTION_MS;
/// 累加器到写库任务的通道（一项是一只 base 的一分钟）。强平一分钟也就几十只有，放得下很多分钟。
const QUEUE:usize=4096;
/// 一条 INSERT 最多几行（每行 9 个参数）。
const INSERT_ROWS:usize=2_000;
const PENDING_CAP:usize=20_000;
const DELETE_BATCH:i64=20_000;
const REPORT:Duration=Duration::from_secs(60*60);
/// 多久按此刻跟踪的 base 重建一次「品种 → base 与面值」的映射（只查内存里的合约表）。
const REMAP:Duration=Duration::from_secs(30);

/// 哪边被平。
pub(super) const LONG:i16=0;
pub(super) const SHORT:i16=1;
/// 哪家。
pub(super) const BINANCE:i16=0;
pub(super) const OKX:i16=1;

// ------------------------------------------------------------------ 分钟

/// 一只 base 一分钟的爆仓（美元）。
#[derive(Clone,Debug,Default,PartialEq)]
pub(super) struct Minute {
 pub minute_ms:i64,pub long_usd:f64,pub short_usd:f64,pub n:i32,
 /// 这一分钟最大的一笔：名义、价格、哪边、哪家。
 pub max_usd:f64,pub max_price:f64,pub max_side:i16,pub max_ex:i16,
}

impl Minute {
 /// 把另一份加进来：金额与笔数相加，最大一笔取大（一样大留原来的）。
 fn fold(&mut self,o:&Minute) {
  self.long_usd+=o.long_usd;self.short_usd+=o.short_usd;self.n+=o.n;
  if o.max_usd>self.max_usd {self.max_usd=o.max_usd;self.max_price=o.max_price;self.max_side=o.max_side;self.max_ex=o.max_ex;}
 }
}

/// 一笔已经换成 base 与美元的强平。
#[derive(Clone,Debug,PartialEq)]
pub(super) struct Hit {pub base:String,pub at:i64,pub side:i16,pub usd:f64,pub price:f64,pub ex:i16}

/// 全进程一份：各家连接把强平记进来，每秒交出过完（含宽限）的分钟。
#[derive(Debug,Default)]
pub(super) struct Acc {open:BTreeMap<(i64,String),Minute>}

impl Acc {
 pub fn add(&mut self,h:&Hit) {
  if !(h.usd.is_finite()&&h.usd>0.0&&h.price.is_finite()) {return}
  let minute_ms=h.at.div_euclid(MINUTE_MS)*MINUTE_MS;
  let one=Minute{minute_ms,long_usd:if h.side==LONG {h.usd} else {0.0},short_usd:if h.side==SHORT {h.usd} else {0.0},n:1,
   max_usd:h.usd,max_price:h.price,max_side:h.side,max_ex:h.ex};
  self.open.entry((minute_ms,h.base.clone())).or_insert_with(||Minute{minute_ms,..Minute::default()}).fold(&one);
 }
 /// 分钟末 + 宽限已过的全部交出来（按分钟先后）。
 pub fn due(&mut self,now:i64)->Vec<(String,Minute)> {
  let mut out=Vec::new();
  while let Some(e)=self.open.first_entry() {
   if e.key().0+MINUTE_MS+GRACE_MS>now {break}
   let ((_,base),m)=e.remove_entry();
   out.push((base,m));
  }
  out
 }
 /// 停机时把没过完的也交出来（下一任接着加到同一行上）。
 pub fn take(&mut self)->Vec<(String,Minute)> {std::mem::take(&mut self.open).into_iter().map(|((_,base),m)|(base,m)).collect()}
}

static ACC:Mutex<Acc>=Mutex::new(Acc{open:BTreeMap::new()});

fn acc()->std::sync::MutexGuard<'static,Acc> {ACC.lock().unwrap_or_else(|e|e.into_inner())}

/// 交易所给的时刻离本机 10 秒以内才信，否则用本机收到的时刻。
fn stamp(exchange_ms:Option<i64>,local:i64)->i64 {
 match exchange_ms {Some(t) if (t-local).abs()<=TRUST_MS=>t,_=>local}
}

// ------------------------------------------------------------------ 源与解析

#[derive(Clone,Copy,Debug,PartialEq,Eq,Hash)]
pub(super) enum Source {BinanceUm,BinanceCm,Okx}

const SOURCES:[Source;3]=[Source::BinanceUm,Source::BinanceCm,Source::Okx];

impl Source {
 fn url(self)->&'static str {
  match self {
   Source::BinanceUm=>"wss://fstream.binance.com/market/ws/!forceOrder@arr",
   Source::BinanceCm=>"wss://dstream.binance.com/ws/!forceOrder@arr",
   Source::Okx=>"wss://ws.okx.com:8443/ws/v5/public",
  }
 }
 /// 建连走 hub 里哪一家的节拍器（币安的 U 本位 / 币本位共用一个）。
 fn kind(self)->Kind {match self {Source::BinanceUm=>Kind::BinanceUmTrades,Source::BinanceCm=>Kind::BinanceCm,Source::Okx=>Kind::Okx}}
 fn label(self)->&'static str {match self {Source::BinanceUm=>"binance-um",Source::BinanceCm=>"binance-cm",Source::Okx=>"okx"}}
 fn ex(self)->i16 {if self==Source::Okx {OKX} else {BINANCE}}
 fn index(self)->usize {self as usize}
 /// 币安两条连接各认各的：币本位只认 `…USD_PERP` / `…USD_yymmdd`，其余算 U 本位。
 fn accepts(self,symbol:&str)->bool {
  match self {Source::BinanceUm=>!coin_margined(symbol),Source::BinanceCm=>coin_margined(symbol),Source::Okx=>true}
 }
 /// 一张合约表的行属于哪一路（现货与 Coinbase 不属于任何一路）。
 fn of(v:&Venue)->Option<Source> {
  match (v.exchange,v.product,v.notional) {
   (_,Product::Spot,_)|(Exchange::Coinbase,..)=>None,
   (Exchange::Binance,_,Notional::Linear{..})=>Some(Source::BinanceUm),
   (Exchange::Binance,_,Notional::Inverse{..})=>Some(Source::BinanceCm),
   (Exchange::Okx,..)=>Some(Source::Okx),
  }
 }
}

fn coin_margined(symbol:&str)->bool {symbol.split_once('_').is_some_and(|(pair,_)|pair.ends_with("USD"))}

/// 同一族：币安按交易对（去掉 `_` 之后的交割 / 永续后缀），OKX 按前两段（`BTC-USDT-SWAP` → `BTC-USDT`）。
fn family(src:Source,instrument:&str)->String {
 match src {
  Source::Okx=>instrument.splitn(3,'-').take(2).collect::<Vec<_>>().join("-"),
  _=>instrument.split('_').next().unwrap_or(instrument).to_string(),
 }
}

/// 解析出来、还没换成 base 与美元的一笔强平。
#[derive(Clone,Debug,PartialEq)]
pub(super) struct Raw {pub symbol:String,pub family:Option<String>,pub side:i16,pub price:f64,pub qty:f64,pub at:Option<i64>}

fn positive(v:&Value)->Option<f64> {
 let n=match v {Value::String(s)=>s.parse::<f64>().ok()?,Value::Number(n)=>n.as_f64()?,_=>return None};
 (n.is_finite()&&n>0.0).then_some(n)
}

/// 币安 `forceOrder`（单流 `/ws/` 的裸帧，或组合流 `{"stream","data"}` 包着的）。
fn binance(text:&str)->Option<Raw> {
 let frame:Value=serde_json::from_str(text).ok()?;
 let body=if frame.get("data").is_some_and(Value::is_object) {&frame["data"]} else {&frame};
 if body["e"].as_str()!=Some("forceOrder") {return None}
 let o=&body["o"];
 let symbol=o["s"].as_str()?.to_ascii_uppercase();
 // 系统卖出 = 平多（多头被平），买入 = 平空。
 let side=match o["S"].as_str()? {"SELL"=>LONG,"BUY"=>SHORT,_=>return None};
 let (price,qty)=match (positive(&o["ap"]),positive(&o["z"])) {(Some(p),Some(q))=>(p,q),_=>(positive(&o["p"])?,positive(&o["q"])?)};
 let at=o["T"].as_i64().or_else(||body["E"].as_i64());
 Some(Raw{symbol,family:None,side,price,qty,at})
}

/// OKX `liquidation-orders`：一帧可能几只合约、每只几笔。订阅回执、`pong` 之类回空。
fn okx(text:&str)->Vec<Raw> {
 let Ok(frame)=serde_json::from_str::<Value>(text) else {return Vec::new()};
 if frame["arg"]["channel"].as_str()!=Some("liquidation-orders") {return Vec::new()}
 let mut out=Vec::new();
 for d in frame["data"].as_array().map(Vec::as_slice).unwrap_or_default() {
  let Some(symbol)=d["instId"].as_str() else {continue};
  let family=d["instFamily"].as_str().or_else(||d["uly"].as_str()).filter(|f|!f.is_empty()).map(str::to_string);
  for x in d["details"].as_array().map(Vec::as_slice).unwrap_or_default() {
   // side 是这笔强平单的方向：sell = 平多（多头被平）。缺了看 posSide。
   let side=match (x["side"].as_str(),x["posSide"].as_str()) {
    (Some("sell"),_)|(None,Some("long"))=>LONG,
    (Some("buy"),_)|(None,Some("short"))=>SHORT,
    _=>continue,
   };
   let (Some(price),Some(qty))=(positive(&x["bkPx"]),positive(&x["sz"])) else {continue};
   let at=x["ts"].as_str().and_then(|s|s.parse::<i64>().ok()).or_else(||x["ts"].as_i64());
   out.push(Raw{symbol:symbol.to_string(),family:family.clone(),side,price,qty,at});
  }
 }
 out
}

/// 币安 U 本位查不到表时按代号认 base：去掉交割后缀与 USDT / USDC，再去 `1000` 前缀。
fn um_base(symbol:&str)->Option<String> {
 let pair=symbol.split('_').next()?;
 let listed=pair.strip_suffix("USDT").or_else(||pair.strip_suffix("USDC"))?;
 let base=instruments::unscaled(listed);
 instruments::valid_base(base).then(||base.to_string())
}

fn usd(notional:Notional,price:f64,qty:f64)->Option<f64> {
 let v=match notional {Notional::Linear{multiplier}=>price*qty*multiplier,Notional::Inverse{contract_usd}=>qty*contract_usd};
 (v.is_finite()&&v>0.0).then_some(v)
}

// ------------------------------------------------------------------ 品种 → base 与面值

/// 此刻跟踪的 base 在各家的合约（不含现货）：按代号、按同族。
#[derive(Debug,Default)]
pub(super) struct Book {
 by_symbol:HashMap<(Source,String),(String,Notional)>,
 by_family:HashMap<(Source,String),(String,Notional)>,
}

impl Book {
 fn build<'a>(rows:impl IntoIterator<Item=(&'a str,&'a Venue)>)->Self {
  let mut book=Book::default();
  for (base,v) in rows {
   let Some(src)=Source::of(v) else {continue};
   let symbol=v.instrument.to_ascii_uppercase();
   book.by_family.entry((src,family(src,&symbol))).or_insert_with(||(base.to_string(),v.notional));
   book.by_symbol.insert((src,symbol),(base.to_string(),v.notional));
  }
  book
 }
 /// 一笔换成（base，美元名义）；拿不到面值为 None。
 fn resolve(&self,src:Source,raw:&Raw)->Option<(String,f64)> {
  let fam=raw.family.clone().unwrap_or_else(||family(src,&raw.symbol));
  if let Some((base,notional))=self.by_symbol.get(&(src,raw.symbol.clone())).or_else(||self.by_family.get(&(src,fam))) {
   return Some((base.clone(),usd(*notional,raw.price,raw.qty)?))
  }
  if src==Source::BinanceUm {return Some((um_base(&raw.symbol)?,usd(Notional::Linear{multiplier:1.0},raw.price,raw.qty)?))}
  None
 }
}

static BOOK:std::sync::LazyLock<RwLock<Arc<Book>>>=std::sync::LazyLock::new(||RwLock::new(Arc::new(Book::default())));

async fn remap() {
 let mut tick=tokio::time::interval(REMAP);
 tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
 loop {
  tick.tick().await;
  let Some(registry)=REGISTRY.get() else {continue};
  let mut rows=Vec::new();
  for base in registry.tracked() {
   for v in instruments::venues(&base).await {rows.push((base.clone(),v));}
  }
  let book=Book::build(rows.iter().map(|(b,v)|(b.as_str(),v)));
  *BOOK.write().unwrap_or_else(|e|e.into_inner())=Arc::new(book);
 }
}

// ------------------------------------------------------------------ 连接

static SEEN:[AtomicU64;3]=[const {AtomicU64::new(0)};3];
static KEPT:[AtomicU64;3]=[const {AtomicU64::new(0)};3];
static UNMAPPED:[AtomicU64;3]=[const {AtomicU64::new(0)};3];
static CONNECTS:[AtomicU64;3]=[const {AtomicU64::new(0)};3];

/// 一帧：解析、换算、只留在跟的 base，记进累加器。
fn handle(src:Source,text:&str,now:i64) {
 let raws=match src {
  Source::Okx=>okx(text),
  _=>binance(text).into_iter().filter(|r|src.accepts(&r.symbol)).collect(),
 };
 if raws.is_empty() {return}
 let book=BOOK.read().unwrap_or_else(|e|e.into_inner()).clone();
 let registry=REGISTRY.get();
 let i=src.index();
 let mut hits=Vec::new();
 for raw in raws {
  SEEN[i].fetch_add(1,Ordering::Relaxed);
  let Some((base,usd))=book.resolve(src,&raw) else {UNMAPPED[i].fetch_add(1,Ordering::Relaxed);continue};
  if !registry.is_some_and(|r|r.is_tracked(&base)) {continue}
  KEPT[i].fetch_add(1,Ordering::Relaxed);
  hits.push(Hit{base,at:stamp(raw.at,now),side:raw.side,usd,price:raw.price,ex:src.ex()});
 }
 let mut acc=acc();
 for h in &hits {acc.add(h);}
}

/// 一路连接的一生：连上就收，断了抖动退避重连（和 `hub::run` 同一套节奏）。
async fn feed(src:Source) {
 let mut backoff=Duration::from_secs(1);
 loop {
  let started=Instant::now();
  match hub::open(src.kind(),src.url()).await {
   Ok(ws)=>{CONNECTS[src.index()].fetch_add(1,Ordering::Relaxed);listen(src,ws).await;},
   Err(e)=>tracing::debug!("Orderflow liq: {} unreachable: {e}",src.label()),
  }
  // 活过一分钟的算正常断开，退避从头来。
  if started.elapsed()>Duration::from_secs(60) {backoff=Duration::from_secs(1)}
  tokio::time::sleep(hub::jittered(backoff)).await;
  backoff=(backoff*2).min(Duration::from_secs(30));
 }
}

const OKX_SUBSCRIBE:&str=r#"{"op":"subscribe","args":[{"channel":"liquidation-orders","instType":"SWAP"},{"channel":"liquidation-orders","instType":"FUTURES"}]}"#;

async fn listen(src:Source,ws:Ws) {
 let (mut tx,mut rx)=ws.split();
 let send=|text:&'static str|Up::Text(text.into());
 if src==Source::Okx&&!matches!(tokio::time::timeout(hub::SEND,tx.send(send(OKX_SUBSCRIBE))).await,Ok(Ok(()))) {return}
 let mut ping=tokio::time::interval_at(Instant::now()+hub::PING,hub::PING);
 let mut deadline=Instant::now()+hub::IDLE;
 loop {
  tokio::select! {
   frame=rx.next()=>{
    let text=match frame {
     Some(Ok(Up::Text(text)))=>text,
     Some(Ok(Up::Close(_)))|Some(Err(_))|None=>break,
     Some(Ok(_))=>{deadline=Instant::now()+hub::IDLE;continue},
    };
    deadline=Instant::now()+hub::IDLE;
    if src==Source::Okx {
     if text.as_str()=="pong" {continue}
     if let Some(error)=Decoder::okx_error(text.as_str()) {tracing::warn!("Orderflow liq: okx error {error}");continue}
    }
    handle(src,text.as_str(),now_ms());
   },
   _=ping.tick()=>{
    let frame=if src==Source::Okx {send("ping")} else {Up::Ping(Default::default())};
    if !matches!(tokio::time::timeout(hub::SEND,tx.send(frame)).await,Ok(Ok(()))) {break}
   },
   _=tokio::time::sleep_until(deadline)=>{tracing::debug!("Orderflow liq: {} silent for {:?}",src.label(),hub::IDLE);break},
  }
 }
 let _=tokio::time::timeout(Duration::from_secs(1),tx.close()).await;
}

/// 每秒把过完的分钟交给写库任务；停机时全部交出；每小时报一次各路收了多少。
async fn flush() {
 let mut tick=tokio::time::interval(Duration::from_secs(1));
 tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
 let mut report=Instant::now()+REPORT;
 let mut closing=CLOSING.subscribe();
 let mut closed=false;
 loop {
  tokio::select! {
   _=tick.tick()=>{
    let due=acc().due(now_ms());
    for (base,m) in due {submit(&base,m);}
    if Instant::now()>=report {
     report=Instant::now()+REPORT;
     let parts:Vec<String>=SOURCES.iter().map(|s|{
      let i=s.index();
      format!("{} {} seen, {} kept, {} unmapped, {} connects",s.label(),SEEN[i].swap(0,Ordering::Relaxed),KEPT[i].swap(0,Ordering::Relaxed),
       UNMAPPED[i].swap(0,Ordering::Relaxed),CONNECTS[i].swap(0,Ordering::Relaxed))
     }).collect();
     tracing::info!("Orderflow liq: last {}s {}",REPORT.as_secs(),parts.join("; "));
    }
   },
   r=closing.changed(),if !closed=>{
    if r.is_err()||*closing.borrow() {
     closed=true;
     let rest=acc().take();
     for (base,m) in rest {submit(&base,m);}
     HANDED.store(true,Ordering::SeqCst);
    }
   },
  }
 }
}

// ------------------------------------------------------------------ 写库

static TX:OnceLock<mpsc::Sender<(String,Minute)>>=OnceLock::new();
static DROPPED:AtomicU64=AtomicU64::new(0);
/// 已交给写库任务、还没写完（写进或写失败）的分钟数；停机时 [`drained`] 等它归零。
static IN_FLIGHT:AtomicUsize=AtomicUsize::new(0);
/// 停机时 [`flush`] 已经把手上没交的分钟全交出去了。
static HANDED:AtomicBool=AtomicBool::new(false);

/// 停机收尾（`super::shutdown`，和跟踪任务交单同时进行）：等 [`flush`] 交完手上的分钟、写库任务把它们写完，
/// 最多等到 `deadline`。没起爆仓聚合（测试、备用节点）直接算完。返回是否写完了。
pub(super) async fn drained(deadline:Instant)->bool {
 if TX.get().is_none() {return true}
 loop {
  if HANDED.load(Ordering::SeqCst)&&IN_FLIGHT.load(Ordering::SeqCst)==0 {return true}
  if Instant::now()>=deadline {return false}
  tokio::time::sleep(Duration::from_millis(10)).await;
 }
}

/// 起写库任务、每秒交分钟的任务、映射重建与三路连接（serve 进程起订单流时一次）。
pub(super) fn start(pool:PgPool) {
 if TX.get().is_some() {return}
 TX.get_or_init(||{
  let (tx,rx)=mpsc::channel(QUEUE);
  tokio::spawn(writer(pool,rx));
  tx
 });
 crate::supervise::spawn_restarting("orderflow-liq-flush",flush);
 crate::supervise::spawn_restarting("orderflow-liq-map",remap);
 crate::supervise::spawn_restarting("orderflow-liq-binance-um",||feed(Source::BinanceUm));
 crate::supervise::spawn_restarting("orderflow-liq-binance-cm",||feed(Source::BinanceCm));
 crate::supervise::spawn_restarting("orderflow-liq-okx",||feed(Source::Okx));
}

/// 交一分钟：不等，通道满了就丢。
fn submit(base:&str,m:Minute) {
 let Some(tx)=TX.get() else {return};
 IN_FLIGHT.fetch_add(1,Ordering::SeqCst);
 if tx.try_send((base.to_string(),m)).is_err() {IN_FLIGHT.fetch_sub(1,Ordering::SeqCst);DROPPED.fetch_add(1,Ordering::Relaxed);}
}

/// 一批里同一（base，分钟）的先合成一行：一条 `ON CONFLICT DO UPDATE` 不能两次碰同一行。
fn merge(rows:Vec<(String,Minute)>)->Vec<(String,Minute)> {
 let mut by:BTreeMap<(String,i64),Minute>=BTreeMap::new();
 for (base,m) in rows {
  by.entry((base,m.minute_ms)).or_insert_with(||Minute{minute_ms:m.minute_ms,..Minute::default()}).fold(&m);
 }
 by.into_iter().map(|((base,_),m)|(base,m)).collect()
}

async fn writer(pool:PgPool,mut rx:mpsc::Receiver<(String,Minute)>) {
 let (mut written,mut failed)=(0u64,0u64);
 let mut report=Instant::now()+REPORT;
 let mut warned:Option<Instant>=None;
 while let Some(first)=rx.recv().await {
  let mut rows=vec![first];
  while rows.len()<PENDING_CAP && let Ok(more)=rx.try_recv() {rows.push(more);}
  let received=rows.len();
  let rows=merge(rows);
  let Ok(_slot)=WRITE_SLOTS.acquire().await else {return};
  for chunk in rows.chunks(INSERT_ROWS) {
   match insert(&pool,chunk).await {
    Ok(())=>written+=chunk.len() as u64,
    Err(e)=>{
     failed+=chunk.len() as u64;
     if warned.is_none_or(|at|at.elapsed()>=Duration::from_secs(60)) {warned=Some(Instant::now());tracing::warn!("Orderflow liq: write failed, {} minutes dropped: {e}",chunk.len());}
    },
   }
  }
  drop(_slot);
  IN_FLIGHT.fetch_sub(received,Ordering::SeqCst);
  if Instant::now()>=report {
   tracing::info!("Orderflow liq: last {}s wrote {written} base-minutes; dropped {} (queue full), {failed} (write failed)",REPORT.as_secs(),DROPPED.swap(0,Ordering::Relaxed));
   (written,failed)=(0,0);
   report=Instant::now()+REPORT;
  }
 }
}

async fn insert(pool:&PgPool,rows:&[(String,Minute)])->sqlx::Result<()> {
 let mut q=sqlx::QueryBuilder::<sqlx::Postgres>::new("INSERT INTO orderflow_liq(base,minute_ms,long_usd,short_usd,n,max_usd,max_price,max_side,max_ex) ");
 q.push_values(rows,|mut b,(base,m)|{
  b.push_bind(base).push_bind(m.minute_ms).push_bind(m.long_usd).push_bind(m.short_usd).push_bind(m.n)
   .push_bind(m.max_usd).push_bind(m.max_price).push_bind(m.max_side).push_bind(m.max_ex);
 });
 // 迟到的、停机交出的半分钟与重启后接着的另半分钟：金额与笔数加在一起，最大一笔取大（右边读的都是原来那行）。
 q.push(" ON CONFLICT(base,minute_ms) DO UPDATE SET long_usd=orderflow_liq.long_usd+EXCLUDED.long_usd,short_usd=orderflow_liq.short_usd+EXCLUDED.short_usd,\
  n=orderflow_liq.n+EXCLUDED.n,\
  max_price=CASE WHEN EXCLUDED.max_usd>orderflow_liq.max_usd THEN EXCLUDED.max_price ELSE orderflow_liq.max_price END,\
  max_side=CASE WHEN EXCLUDED.max_usd>orderflow_liq.max_usd THEN EXCLUDED.max_side ELSE orderflow_liq.max_side END,\
  max_ex=CASE WHEN EXCLUDED.max_usd>orderflow_liq.max_usd THEN EXCLUDED.max_ex ELSE orderflow_liq.max_ex END,\
  max_usd=GREATEST(orderflow_liq.max_usd,EXCLUDED.max_usd)");
 q.build().execute(pool).await.map(|_|())
}

// ------------------------------------------------------------------ 清理

/// 每小时一次：逐只 base 按主键删 3 天以前的。
pub(super) async fn purge(pool:&PgPool,now:i64)->sqlx::Result<u64> {
 let cutoff=now-store::RETENTION_MS;
 let mut deleted=0;
 for base in store::bases(pool).await? {
  loop {
   let n=sqlx::query("DELETE FROM orderflow_liq WHERE ctid=ANY(ARRAY(SELECT ctid FROM orderflow_liq WHERE base=$1 AND minute_ms<$2 LIMIT $3))")
    .bind(&base).bind(cutoff).bind(DELETE_BATCH).execute(pool).await?.rows_affected();
   deleted+=n;
   if n<DELETE_BATCH as u64 {break}
  }
 }
 Ok(deleted)
}

/// 表（含索引）此刻多大。
pub(super) async fn size(pool:&PgPool)->sqlx::Result<i64> {
 sqlx::query_scalar("SELECT pg_total_relation_size('orderflow_liq')").fetch_one(pool).await
}

// ------------------------------------------------------------------ 接口

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct LiqQuery {base:String,from:Option<i64>,to:Option<i64>}

/// 校验并补齐区间：`to` 缺省此刻，`from` 缺省 `to` 前 3 天；超过 3 天把 `from` 夹回来，不报错；两端按分钟向下取整。
fn window(from:Option<i64>,to:Option<i64>,now:i64)->std::result::Result<(i64,i64),&'static str> {
 let to=to.unwrap_or(now);
 let from=from.unwrap_or(to.saturating_sub(MAX_SPAN_MS));
 if from<0||to<0||from>to {return Err("invalid_range")}
 let floor=|v:i64|v.div_euclid(MINUTE_MS)*MINUTE_MS;
 Ok((floor(from.max(to-MAX_SPAN_MS)),floor(to)))
}

fn body(base:&str,tracked:bool,rows:&[Minute])->String {
 let mut out=String::with_capacity(64+rows.len()*64);
 out.push_str("{\"base\":");out.push_str(&serde_json::Value::from(base).to_string());
 out.push_str(",\"tracked\":");out.push_str(if tracked {"true"} else {"false"});
 out.push_str(",\"rows\":[");
 for (i,m) in rows.iter().enumerate() {
  if i>0 {out.push(',');}
  out.push('[');json_number(&mut out,m.minute_ms as f64);
  for v in [m.long_usd.round(),m.short_usd.round(),f64::from(m.n),m.max_usd.round(),m.max_price,f64::from(m.max_side),f64::from(m.max_ex)] {
   out.push(',');json_number(&mut out,v);
  }
  out.push(']');
 }
 out.push_str("]}");
 out
}

async fn read(pool:&PgPool,base:&str,from:i64,to:i64)->sqlx::Result<Vec<Minute>> {
 let rows=sqlx::query("SELECT minute_ms,long_usd,short_usd,n,max_usd,max_price,max_side,max_ex FROM orderflow_liq WHERE base=$1 AND minute_ms BETWEEN $2 AND $3 ORDER BY minute_ms")
  .bind(base).bind(from).bind(to).fetch_all(pool).await?;
 Ok(rows.iter().map(|r|Minute{minute_ms:r.get(0),long_usd:r.get(1),short_usd:r.get(2),n:r.get(3),max_usd:r.get(4),max_price:r.get(5),max_side:r.get(6),max_ex:r.get(7)}).collect())
}

#[derive(Clone,Debug,PartialEq,Eq,Hash)]
struct Key {base:String,from:i64,to:i64,gzip:bool}

static ANSWERS:std::sync::LazyLock<Answers<Key>>=std::sync::LazyLock::new(||Answers::new(LIQ_TTL));

fn answer(json:String,gzip:bool)->Result<Answer> {packed(json,gzip,CACHE_CONTROL)}

pub(super) async fn liq(State(s):State<AppState>,headers:axum::http::HeaderMap,Params(q):Params<LiqQuery>)->Result<Response> {
 if !instruments::valid_base(&q.base) {return Err(ApiError::bad("invalid_base"))}
 let (from,to)=window(q.from,q.to,now_ms()).map_err(ApiError::bad)?;
 let gzip=accepts_gzip(&headers);
 // 没在跟的不读库、也不因此起跟。
 if !REGISTRY.get().is_some_and(|r|r.is_tracked(&q.base)) {return Ok(answer(body(&q.base,false,&[]),gzip)?.response())}
 let pool=POOL.get().unwrap_or(&s.pool);
 let key=Key{base:q.base.clone(),from,to,gzip};
 let answer=ANSWERS.get_or_build(key,||async {
  let busy=||ApiError(axum::http::StatusCode::SERVICE_UNAVAILABLE,"temporarily_unavailable");
  let _slot=HISTORY_READS.acquire().await.map_err(|_|busy())?;
  let rows=read(pool,&q.base,from,to).await?;
  drop(_slot);
  answer(body(&q.base,true,&rows),gzip)
 }).await?;
 Ok(answer.response())
}

#[cfg(test)]
mod tests {
 use super::*;
 use crate::orderflow_instruments::Margin;

 // 2026-10-08 在新加坡 VPS 上抓到的原帧。
 const UM:&str=r#"{"e":"forceOrder","E":1791435250143,"o":{"s":"XRPUSDT","S":"BUY","o":"LIMIT","f":"IOC","q":"15.4","p":"1.4111","ap":"1.4043","X":"FILLED","l":"15.4","z":"15.4","T":1791435249136,"ps":"XRPUSDT","st":1}}"#;
 const UM_SELL:&str=r#"{"e":"forceOrder","E":1791435151350,"o":{"s":"AINUSDT","S":"SELL","o":"LIMIT","f":"IOC","q":"1861","p":"0.0348700","ap":"0.0387407","X":"FILLED","l":"38","z":"1861","T":1791435150342,"ps":"AINUSDT","st":1}}"#;
 const OKX_FRAME:&str=r#"{"arg":{"channel":"liquidation-orders","instType":"SWAP"},"data":[{"details":[{"bkLoss":"0","bkPx":"0.072682","ccy":"","posSide":"long","side":"sell","sz":"2","ts":"1791435480289"}],"instFamily":"MUBARAK-USDT","instId":"MUBARAK-USDT-SWAP","instType":"SWAP","uly":"MUBARAK-USDT"}]}"#;

 fn venue(exchange:Exchange,product:Product,instrument:&str,notional:Notional)->Venue {
  Venue{exchange,product,instrument:instrument.into(),margin:Some(Margin::Usdt),notional,tick:0.1,expiry_ms:None,price_scale:None,listed_base:String::new()}
 }

 fn book()->Book {
  let rows=[
   ("BTC",venue(Exchange::Binance,Product::Spot,"BTCUSDT",Notional::Linear{multiplier:1.0})),
   ("BTC",venue(Exchange::Binance,Product::UsdtPerp,"BTCUSDT",Notional::Linear{multiplier:1.0})),
   ("BTC",venue(Exchange::Binance,Product::CoinPerp,"BTCUSD_PERP",Notional::Inverse{contract_usd:100.0})),
   ("BTC",venue(Exchange::Okx,Product::UsdtPerp,"BTC-USDT-SWAP",Notional::Linear{multiplier:0.01})),
   ("BTC",venue(Exchange::Okx,Product::CoinPerp,"BTC-USD-SWAP",Notional::Inverse{contract_usd:100.0})),
   ("PEPE",venue(Exchange::Binance,Product::UsdtPerp,"1000PEPEUSDT",Notional::Linear{multiplier:1.0})),
   ("BTC",venue(Exchange::Coinbase,Product::Spot,"BTC-USD",Notional::Linear{multiplier:1.0})),
  ];
  Book::build(rows.iter().map(|(b,v)|(*b,v)))
 }

 #[test] fn binance_frames_parse_side_price_and_filled_quantity() {
  assert_eq!(binance(UM),Some(Raw{symbol:"XRPUSDT".into(),family:None,side:SHORT,price:1.4043,qty:15.4,at:Some(1791435249136)}),"BUY = 空头被平，均价 × 已成交");
  assert_eq!(binance(UM_SELL).unwrap().side,LONG,"SELL = 多头被平");
  // 组合流包着的也认；均价 / 已成交缺了退回委托价 × 数量；时刻缺 T 用 E。
  let wrapped=r#"{"stream":"!forceOrder@arr","data":{"e":"forceOrder","E":5,"o":{"s":"btcusd_perp","S":"SELL","q":"3","p":"80000","ap":"0","z":"0"}}}"#;
  assert_eq!(binance(wrapped),Some(Raw{symbol:"BTCUSD_PERP".into(),family:None,side:LONG,price:80000.0,qty:3.0,at:Some(5)}));
  assert_eq!(binance(r#"{"e":"aggTrade","s":"BTCUSDT"}"#),None);
  assert_eq!(binance(r#"{"e":"forceOrder","o":{"s":"BTCUSDT","S":"HOLD","q":"1","p":"1"}}"#),None);
  assert_eq!(binance("not json"),None);
 }

 #[test] fn each_binance_connection_only_takes_its_own_family() {
  // 币本位那条地址眼下也推 U 本位的单：两条各认各的，同一笔不记两次。
  for (symbol,cm) in [("BTCUSD_PERP",true),("ETHUSD_251226",true),("BTCUSDT",false),("BTCUSDT_251226",false),("BTCUSDC",false),("1000PEPEUSDT",false)] {
   assert_eq!(Source::BinanceCm.accepts(symbol),cm,"{symbol}");
   assert_eq!(Source::BinanceUm.accepts(symbol),!cm,"{symbol}");
  }
 }

 #[test] fn okx_frames_parse_every_detail_and_skip_receipts() {
  assert_eq!(okx(OKX_FRAME),vec![Raw{symbol:"MUBARAK-USDT-SWAP".into(),family:Some("MUBARAK-USDT".into()),side:LONG,price:0.072682,qty:2.0,at:Some(1791435480289)}]);
  let two=r#"{"arg":{"channel":"liquidation-orders","instType":"FUTURES"},"data":[{"instId":"BTC-USD-251010","instFamily":"BTC-USD","details":[
   {"side":"buy","posSide":"short","bkPx":"83000","sz":"5","ts":"7"},{"posSide":"long","bkPx":"82000","sz":"1","ts":"8"},{"side":"buy","bkPx":"0","sz":"1","ts":"9"}]}]}"#;
  let raws=okx(two);
  assert_eq!(raws.iter().map(|r|(r.side,r.qty,r.at)).collect::<Vec<_>>(),vec![(SHORT,5.0,Some(7)),(LONG,1.0,Some(8))],"side 缺了看 posSide；价格为 0 的丢");
  assert!(okx(r#"{"event":"subscribe","arg":{"channel":"liquidation-orders","instType":"SWAP"}}"#).is_empty());
  assert!(okx("pong").is_empty());
  assert!(okx(r#"{"arg":{"channel":"trades"},"data":[{"instId":"BTC-USDT-SWAP","details":[{"side":"sell","bkPx":"1","sz":"1"}]}]}"#).is_empty());
 }

 #[test] fn notional_uses_the_contract_face_value() {
  let b=book();
  let raw=|symbol:&str,family:Option<&str>,price,qty|Raw{symbol:symbol.into(),family:family.map(str::to_string),side:LONG,price,qty,at:None};
  assert_eq!(b.resolve(Source::BinanceUm,&raw("BTCUSDT",None,80_000.0,0.5)),Some(("BTC".into(),40_000.0)));
  assert_eq!(b.resolve(Source::BinanceCm,&raw("BTCUSD_PERP",None,80_000.0,7.0)),Some(("BTC".into(),700.0)),"币本位 = 张数 × 面值");
  assert_eq!(b.resolve(Source::BinanceCm,&raw("BTCUSD_251226",None,80_000.0,2.0)),Some(("BTC".into(),200.0)),"表里没有的交割借同一交易对的面值");
  assert_eq!(b.resolve(Source::Okx,&raw("BTC-USDT-SWAP",Some("BTC-USDT"),80_000.0,3.0)),Some(("BTC".into(),2_400.0)),"U 本位 = 价 × 张 × 面值（币）");
  assert_eq!(b.resolve(Source::Okx,&raw("BTC-USD-251010",Some("BTC-USD"),80_000.0,4.0)),Some(("BTC".into(),400.0)),"周交割按 instFamily 借面值");
  assert_eq!(b.resolve(Source::Okx,&raw("BTC-USDC-SWAP",Some("BTC-USDC"),80_000.0,4.0)),None,"拿不到面值的丢");
  assert_eq!(b.resolve(Source::BinanceUm,&raw("1000PEPEUSDT",None,0.01,1_000.0)),Some(("PEPE".into(),10.0)));
  assert_eq!(b.resolve(Source::BinanceUm,&raw("SOLUSDC",None,200.0,2.0)),Some(("SOL".into(),400.0)),"表外的 U 本位按代号认");
  assert_eq!(b.resolve(Source::BinanceUm,&raw("1000BONKUSDT_251226",None,0.02,100.0)),Some(("BONK".into(),2.0)));
  assert_eq!(b.resolve(Source::BinanceUm,&raw("ETHBTC",None,0.03,1.0)),None);
  assert_eq!(b.by_symbol.len(),5,"现货与 Coinbase 不进映射");
 }

 #[test] fn exchange_time_is_trusted_only_near_the_local_clock() {
  assert_eq!(stamp(Some(100_000),105_000),100_000);
  assert_eq!(stamp(Some(100_000),110_001),110_001,"差 10 秒以上用本机");
  assert_eq!(stamp(None,7),7);
 }

 fn hit(base:&str,at:i64,side:i16,usd:f64,price:f64,ex:i16)->Hit {Hit{base:base.into(),at,side,usd,price,ex}}

 #[test] fn liquidations_land_in_their_minute_and_hand_over_after_the_grace() {
  let mut a=Acc::default();
  a.add(&hit("BTC",60_000,LONG,1_000.0,80_000.0,BINANCE));
  a.add(&hit("BTC",61_000,SHORT,5_000.0,80_100.0,OKX));
  a.add(&hit("BTC",62_000,LONG,2_000.0,79_900.0,BINANCE));
  a.add(&hit("ETH",62_000,LONG,0.0,3_000.0,OKX));
  a.add(&hit("ETH",62_000,LONG,f64::NAN,3_000.0,OKX));
  a.add(&hit("BTC",120_500,LONG,9.0,1.0,BINANCE));
  assert!(a.due(122_999).is_empty(),"分钟末之后还有 3 秒宽限");
  assert_eq!(a.due(123_000),vec![("BTC".into(),Minute{minute_ms:60_000,long_usd:3_000.0,short_usd:5_000.0,n:3,max_usd:5_000.0,max_price:80_100.0,max_side:SHORT,max_ex:OKX})]);
  // 宽限之后才到的同一分钟：作为增量再交一次（写库时加上去）。
  a.add(&hit("BTC",59_000,LONG,7.0,1.0,BINANCE));
  assert_eq!(a.due(123_001).len(),1);
  assert_eq!(a.take(),vec![("BTC".into(),Minute{minute_ms:120_000,long_usd:9.0,n:1,max_usd:9.0,max_price:1.0,..Minute::default()})],"停机把没过完的交出来");
  assert!(a.take().is_empty());
 }

 #[test] fn a_batch_merges_the_same_minute_and_keeps_the_biggest() {
  let m=|minute_ms,long_usd,max_usd,max_ex|Minute{minute_ms,long_usd,n:1,max_usd,max_price:max_usd*2.0,max_side:LONG,max_ex,..Minute::default()};
  let out=merge(vec![("BTC".into(),m(0,1.0,1.0,BINANCE)),("ETH".into(),m(0,5.0,5.0,OKX)),("BTC".into(),m(0,2.0,2.0,OKX)),("BTC".into(),m(60_000,4.0,4.0,BINANCE))]);
  assert_eq!(out,vec![
   ("BTC".into(),Minute{minute_ms:0,long_usd:3.0,n:2,max_usd:2.0,max_price:4.0,max_side:LONG,max_ex:OKX,..Minute::default()}),
   ("BTC".into(),m(60_000,4.0,4.0,BINANCE)),("ETH".into(),m(0,5.0,5.0,OKX)),
  ]);
 }

 #[test] fn window_defaults_to_three_days_floors_to_minutes_and_clamps() {
  let now=10*store::DAY_MS+12_345;
  assert_eq!(window(None,None,now),Ok((7*store::DAY_MS,10*store::DAY_MS)));
  assert_eq!(window(Some(0),Some(now),now),Ok((7*store::DAY_MS,10*store::DAY_MS)),"超过 3 天夹回来");
  assert_eq!(window(Some(61_000),Some(125_000),now),Ok((60_000,120_000)));
  assert_eq!(window(Some(60_000),Some(60_000),now),Ok((60_000,60_000)),"闭区间，一分钟也行");
  assert_eq!(window(Some(5),Some(4),now),Err("invalid_range"));
  assert_eq!(window(Some(-1),None,now),Err("invalid_range"));
  assert_eq!(window(None,Some(i64::MIN),now),Err("invalid_range"));
 }

 #[test] fn body_has_the_agreed_shape() {
  let rows=[Minute{minute_ms:60_000,long_usd:150_000.4,short_usd:0.6,n:3,max_usd:120_000.5,max_price:142.375,max_side:LONG,max_ex:OKX}];
  assert_eq!(body("SOL",true,&rows),r#"{"base":"SOL","tracked":true,"rows":[[60000,150000,1,3,120001,142.375,0,1]]}"#);
  let v:serde_json::Value=serde_json::from_str(&body("MU",false,&[])).unwrap();
  assert_eq!(v,serde_json::json!({"base":"MU","tracked":false,"rows":[]}));
 }

 #[test] fn answers_are_publicly_cacheable_for_twenty_seconds() {
  let a=answer(body("BTC",true,&[]),true).unwrap().response();
  assert_eq!(a.headers()[axum::http::header::CACHE_CONTROL],"public, max-age=20");
  assert_eq!(a.headers()[axum::http::header::CONTENT_ENCODING],"gzip");
 }

 #[tokio::test] async fn minutes_add_up_keep_the_biggest_and_old_ones_are_purged() {
  let Some(pool)=store::tests::isolated_pool().await else {return};
  let base="LIQTEST";
  sqlx::query("DELETE FROM orderflow_liq WHERE base=$1").bind(base).execute(&pool).await.unwrap();
  let now=10*store::DAY_MS;
  // 清理的名单取自 orderflow_bases：跟踪器起跟时登记。
  store::start(&pool,base,now).await.unwrap();
  let m=|minute_ms,long_usd,short_usd,max_usd,max_side,max_ex|Minute{minute_ms,long_usd,short_usd,n:1,max_usd,max_price:max_usd/10.0,max_side,max_ex};
  let old=now-store::RETENTION_MS-MINUTE_MS;
  insert(&pool,&[(base.into(),m(now-120_000,100.0,0.0,100.0,LONG,BINANCE)),(base.into(),m(now-60_000,50.0,0.0,50.0,LONG,BINANCE)),(base.into(),m(old,9.0,9.0,9.0,LONG,OKX))]).await.unwrap();
  // 迟到 / 停机交出的另一半：金额笔数相加，大的那笔换上来；小的不换。
  insert(&pool,&[(base.into(),m(now-60_000,0.0,80.0,80.0,SHORT,OKX)),(base.into(),m(now-120_000,1.0,0.0,1.0,SHORT,OKX))]).await.unwrap();
  let rows=read(&pool,base,now-store::RETENTION_MS,now).await.unwrap();
  assert_eq!(rows,vec![
   Minute{minute_ms:now-120_000,long_usd:101.0,short_usd:0.0,n:2,max_usd:100.0,max_price:10.0,max_side:LONG,max_ex:BINANCE},
   Minute{minute_ms:now-60_000,long_usd:50.0,short_usd:80.0,n:2,max_usd:80.0,max_price:8.0,max_side:SHORT,max_ex:OKX},
  ]);
  assert_eq!(read(&pool,base,now-60_000,now-60_000).await.unwrap().len(),1,"闭区间");
  assert_eq!(purge(&pool,now).await.unwrap(),1);
  let left:i64=sqlx::query_scalar("SELECT count(*) FROM orderflow_liq WHERE base=$1").bind(base).fetch_one(&pool).await.unwrap();
  assert_eq!(left,2);
  sqlx::query("DELETE FROM orderflow_liq WHERE base=$1").bind(base).execute(&pool).await.unwrap();
  sqlx::query("DELETE FROM orderflow_bases WHERE base=$1").bind(base).execute(&pool).await.unwrap();
 }

 /// 停机收尾靠「在途归零 = 已经写进库」：写库任务写完（或写失败）才减在途，减到零时行一定已经在库里。
 #[tokio::test] async fn in_flight_reaches_zero_only_after_the_rows_are_written() {
  let Some(pool)=store::tests::isolated_pool().await else {return};
  let base="LIQDRAIN";
  sqlx::query("DELETE FROM orderflow_liq WHERE base=$1").bind(base).execute(&pool).await.unwrap();
  let (tx,rx)=mpsc::channel(8);
  tokio::spawn(writer(pool.clone(),rx));
  let m=|minute_ms|Minute{minute_ms,long_usd:5.0,short_usd:0.0,n:1,max_usd:5.0,max_price:1.0,max_side:LONG,max_ex:BINANCE};
  IN_FLIGHT.fetch_add(2,Ordering::SeqCst);
  tx.send((base.into(),m(60_000))).await.unwrap();
  tx.send((base.into(),m(120_000))).await.unwrap();
  let deadline=Instant::now()+Duration::from_secs(10);
  while IN_FLIGHT.load(Ordering::SeqCst)!=0 {assert!(Instant::now()<deadline,"写库任务没把在途减回零");tokio::time::sleep(Duration::from_millis(5)).await;}
  let n:i64=sqlx::query_scalar("SELECT count(*) FROM orderflow_liq WHERE base=$1").bind(base).fetch_one(&pool).await.unwrap();
  assert_eq!(n,2,"在途归零时两分钟都已在库里");
  sqlx::query("DELETE FROM orderflow_liq WHERE base=$1").bind(base).execute(&pool).await.unwrap();
 }
}
