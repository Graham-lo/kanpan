//! 主力订单流 · 服务端历史（2026-09-24）。
//!
//! 手机上的订单流只在打开一只品种时才开始跟，关掉就断：刚打开时图上是空的，往左拖也没有。
//! 这里在 serve 进程里常驻跟踪，一单一行写进 `orderflow_orders`；手机打开品种先拉最近 24 小时，
//! 之后每分钟增量拉一次，往左拖再一天一天补（最多 30 天）。
//!
//! * 跟踪规则和手机那份（`OrderFlowModel.swift`）逐条一致，见 `model.rs`；簿的接续见 `book.rs`；
//!   各家连接见 `feeds.rs`；库见 `store.rs`。
//! * 只按**默认门槛**跟（`OrderFlowDefaults` 那张表 + 前一日收盘推的步长）。用户在手机上改过门槛的，
//!   手机拿到之后自己按自己的门槛过滤（比默认门槛低的那部分服务端没有，只能靠手机本地跟）。
//! * 跟哪些币：BTC / ETH / SOL 一直跟；其它币第一次有人要才开始跟，24 小时没人要就停；
//!   最多同时 20 只，满了踢掉最久没人要的那只（三只主币不踢）。
//! * 写库：挂着的单每 15 秒整批 upsert，结束的单一结束就写；进程重启读回挂着的单，
//!   缺席超过 2 分钟的按最后一次看到时失联结束。每小时滚动清理一次（30 天 + 20 GB 闸门）。
//! * 接口 `GET /v1/market/orderflow/history?base=&from=&to=`：`to` 缺省为此刻，`from` 缺省为
//!   `to` 前 24 小时，区间最长 30 天；回 `{base, thresholds, trackedSinceMs, orders}`，gzip。
//!   没在跟的币回空表、`trackedSinceMs` 为此刻，并从这一刻开始跟。
//! * 只在带库的 serve 进程里有；备用节点跑的是 metrics（没有库），不挂这条路由。
mod book;
mod feeds;
mod model;
mod store;

use crate::AppState;
use crate::error::{ApiError,Params,Result};
use crate::orderflow_instruments::{self as instruments,Exchange,Product,Venue};
use axum::extract::State;
use axum::http::{HeaderValue,header};
use axum::response::{IntoResponse,Response};
use axum::routing::get;
use axum::{Json,Router};
use book::{Action,Sequence,VenueInfo};
use feeds::{Event,Resubscribe};
use model::{BigOrder,Model,Notional,Thresholds};
use serde::Deserialize;
use serde_json::Value;
use sqlx::PgPool;
use std::collections::{HashMap,HashSet};
use std::sync::{Arc,Mutex,OnceLock};
use std::time::Duration;
use tokio::sync::{mpsc,watch};
use tokio::task::JoinHandle;

const PATH:&str="/v1/market/orderflow/history";
/// 一直跟的三只。
const ALWAYS:[&str;3]=["BTC","ETH","SOL"];
const MAX_BASES:usize=20;
/// 其它币多久没人要就停。
const IDLE_MS:i64=store::DAY_MS;
const DEFAULT_SPAN_MS:i64=store::DAY_MS;
const MAX_SPAN_MS:i64=store::RETENTION_MS;
const EVALUATE:Duration=Duration::from_millis(500);
const FLUSH:Duration=Duration::from_secs(15);
const REFRESH:Duration=Duration::from_secs(10*60);
const THRESHOLDS_EVERY_MS:i64=60*60*1000;
const SWEEP:Duration=Duration::from_secs(10*60);
const PURGE:Duration=Duration::from_secs(60*60);
/// 快照失败或过期之后隔多久再拉；拉之前先等一小会儿让增量攒起来（照手机那份）。
const SNAPSHOT_RETRY_MS:i64=2_000;
const SNAPSHOT_SETTLE:Duration=Duration::from_millis(500);
/// 还拿不到步长（收盘没拉到）时隔多久再试。
const RESOLVE_RETRY:Duration=Duration::from_secs(30);

fn now_ms()->i64 {chrono::Utc::now().timestamp_millis()}

// ------------------------------------------------------------------ 品种表 → 簿

fn wire_product(p:Product)->&'static str {match p {Product::Spot=>"spot",Product::UsdtPerp=>"usdtPerp",Product::CoinPerp=>"coinPerp",Product::Delivery=>"delivery"}}

/// 品种表的一行 → 簿的身份。id 与手机上 `OrderFlowVenue.id` 同一个写法。
fn info(v:&Venue)->VenueInfo {
 let (exchange,label,sequence,in_band)=match v.exchange {
  Exchange::Binance=>("binance","币安",if v.product==Product::Spot {Sequence::RangeOverlap} else {Sequence::PreviousFinalOverlap},false),
  Exchange::Okx=>("okx","OKX",Sequence::PreviousFinalExact,true),
  Exchange::Coinbase=>("coinbase","Coinbase",Sequence::StrictIncrementing,true),
 };
 let product=wire_product(v.product);
 let notional=match v.notional {
  instruments::Notional::Linear{multiplier}=>Notional::Linear(multiplier),
  instruments::Notional::Inverse{contract_usd}=>Notional::Inverse(contract_usd),
 };
 VenueInfo{id:format!("{exchange}:{product}:{}",v.instrument),exchange,label,product,instrument:v.instrument.clone(),notional,
  price_scale:v.price_scale.unwrap_or(1).max(1) as f64,sequence,in_band}
}

// ------------------------------------------------------------------ 门槛

/// 币安 U 本位永续（门槛分档、是不是币、推步长都看它）。
fn binance_perp(venues:&[Venue])->Option<&Venue> {venues.iter().find(|v|v.exchange==Exchange::Binance&&v.product==Product::UsdtPerp)}

/// 是不是币：币安 U 本位永续的 `underlyingType` 为 COIN；币安没有这只永续的按币算。
async fn is_crypto(perp:Option<&Venue>)->bool {
 let Some(perp)=perp else {return true};
 let Ok(info)=crate::market_meta::exchange_info().await else {return true};
 info["symbols"].as_array().and_then(|rows|rows.iter().find(|s|s["symbol"].as_str()==Some(perp.instrument.as_str())))
  .and_then(|s|s["underlyingType"].as_str()).is_none_or(|t|t=="COIN")
}

fn number(v:&Value)->Option<f64> {
 let x=match v {Value::String(s)=>s.parse().ok()?,Value::Number(n)=>n.as_f64()?,_=>return None};
 (x as f64).is_finite().then_some(x)
}

async fn turnover(perp:Option<&Venue>)->Option<f64> {
 let perp=perp?;
 let body=crate::market_meta::get_json(&format!("https://www.binance.com/fapi/v1/ticker/24hr?symbol={}",perp.instrument)).await.ok()?;
 number(&body["quoteVolume"]).filter(|t|*t>=0.0)
}

/// 前一 UTC 日那根日线的收盘（照手机的 `previousClose`）。
fn previous_close(rows:&Value,day:i64)->Option<f64> {
 let rows=rows.as_array()?;
 let open=|r:&Value|r.get(0).and_then(|t|t.as_i64());
 let close=|r:&Value|r.get(4).and_then(number);
 rows.iter().rev().find(|r|open(r)==Some(day)).and_then(close)
  .or_else(||rows.iter().rev().find(|r|open(r).is_some_and(|t|t<day+store::DAY_MS)).and_then(close))
}

/// 按前一日收盘推步长：先看币安 U 本位永续，没有再看币安现货。都是每个币的价（去掉 `1000` 前缀的倍数）。
async fn derived_step(venues:&[Venue],day:i64)->Option<f64> {
 let spot=venues.iter().find(|v|v.exchange==Exchange::Binance&&v.product==Product::Spot);
 for (venue,host) in [(binance_perp(venues),"https://www.binance.com/fapi/v1/klines"),(spot,"https://data-api.binance.vision/api/v3/klines")] {
  let Some(v)=venue else {continue};
  let Ok(rows)=crate::market_meta::get_json(&format!("{host}?symbol={}&interval=1d&limit=3",v.instrument)).await else {continue};
  let scale=v.price_scale.unwrap_or(1).max(1) as f64;
  if let Some(close)=previous_close(&rows,day) {
   if let Some(step)=model::derived_step(close/scale,Some(v.tick/scale)) {return Some(step)}
  }
 }
 None
}

/// 这只币此刻的默认门槛与步长。步长可能还是 None（收盘没拉到）。
async fn resolve(base:&str,venues:&[Venue],now:i64)->Thresholds {
 let perp=binance_perp(venues);
 let crypto=model::is_major(base)||is_crypto(perp).await;
 let turnover=if crypto&&!model::is_major(base) {turnover(perp).await} else {None};
 let mut t=model::defaults(base,crypto,turnover);
 if t.step.is_none() {t.step=derived_step(venues,model::reference_day(now)).await;}
 t
}

// ------------------------------------------------------------------ 一只币的跟踪

/// 写库只走一个任务：挂着的与结束的按到达先后写，不会乱序把结束翻回挂着。
struct Write {step:f64,rows:Vec<(BigOrder,i64)>}

async fn writer(pool:PgPool,base:String,mut rx:mpsc::Receiver<Write>) {
 while let Some(w)=rx.recv().await {
  if w.rows.is_empty() {continue}
  if let Err(e)=store::upsert(&pool,&base,w.step,&w.rows).await {tracing::warn!("Orderflow history: {base} write of {} rows failed: {e}",w.rows.len());}
 }
}

struct Tracker {
 base:String,
 model:Model,
 events:mpsc::Sender<Event>,
 commands:HashMap<String,mpsc::Sender<Resubscribe>>,
 sockets:Vec<JoinHandle<()>>,
 open:HashSet<String>,
 inflight:HashSet<String>,
 retry:HashMap<String,i64>,
 writes:mpsc::Sender<Write>,
}

impl Tracker {
 fn step(&self)->f64 {self.model.thresholds.step.unwrap_or(0.0)}

 fn spawn_sockets(&mut self,venues:Vec<VenueInfo>) {
  for socket in feeds::plan(&venues) {
   let (tx,rx)=mpsc::channel(16);
   for v in &socket.venues {if socket.kind!=feeds::Kind::BinanceUmTrades {self.commands.insert(v.id.clone(),tx.clone());}}
   self.sockets.push(tokio::spawn(feeds::run(socket,self.events.clone(),rx)));
  }
 }

 fn add_venues(&mut self,venues:&[Venue]) {
  let known:HashSet<String>=self.model.venue_ids().into_iter().collect();
  let fresh:Vec<VenueInfo>=venues.iter().filter(|v|self.model.thresholds.of(wire_product(v.product)).is_some()).map(info).filter(|v|!known.contains(&v.id)).collect();
  if fresh.is_empty() {return}
  tracing::info!("Orderflow history: {} tracks {}",self.base,fresh.iter().map(|v|v.id.as_str()).collect::<Vec<_>>().join(", "));
  for v in &fresh {self.model.add_venue(v.clone());}
  self.spawn_sockets(fresh);
 }

 fn act(&mut self,venue:&str,action:Action) {
  match action {
   Action::None=>{},
   Action::Resubscribe=>{if let Some(tx)=self.commands.get(venue) {let _=tx.try_send(Resubscribe(venue.to_string()));}},
   Action::FetchSnapshot=>self.fetch(venue,SNAPSHOT_SETTLE),
  }
 }

 fn fetch(&mut self,venue:&str,settle:Duration) {
  if self.inflight.contains(venue) {return}
  let Some(book)=self.model.book_mut(venue) else {return};
  let (info,connection)=(book.venue.clone(),book.connection);
  self.inflight.insert(venue.to_string());
  self.retry.remove(venue);
  let events=self.events.clone();
  tokio::spawn(async move {
   tokio::time::sleep(settle).await;
   let snapshot=feeds::fetch_snapshot(&info).await;
   let _=events.send(Event::Snapshot{venue:info.id,connection,snapshot}).await;
  });
 }

 fn handle(&mut self,event:Event) {
  let now=now_ms();
  match event {
   Event::Opened{venues,connection}=>for id in venues {
    self.open.insert(id.clone());
    let action=self.model.book_mut(&id).map_or(Action::None,|b|b.opened(connection));
    self.act(&id,action);
   },
   Event::Closed{venues,connection}=>for id in venues {
    if self.model.book_mut(&id).is_some_and(|b|b.connection==connection) {self.open.remove(&id);}
    self.model.closed(&id,connection);
   },
   Event::Frame{venue,connection,message}=>{
    let action=self.model.ingest(&venue,connection,message,now);
    self.act(&venue,action);
   },
   Event::Trade{venue,trade}=>self.model.trade(&venue,trade),
   Event::Snapshot{venue,connection,snapshot}=>{
    self.inflight.remove(&venue);
    let Some(book)=self.model.book_mut(&venue) else {return};
    match snapshot {
     Some(s) if book.connection==connection=>{let action=book.snapshot(s,now);self.act(&venue,action);},
     _=>{self.retry.insert(venue,now+SNAPSHOT_RETRY_MS);},
    }
   },
  }
 }

 /// 到点的重拉：只拉还连着、还没就绪、快照不在流里的簿。
 fn due_retries(&mut self,now:i64) {
  let due:Vec<String>=self.retry.iter().filter(|(_,at)|**at<=now).map(|(v,_)|v.clone()).collect();
  for venue in due {
   self.retry.remove(&venue);
   let wanted=self.open.contains(&venue)&&self.model.book_mut(&venue).is_some_and(|b|!b.venue.in_band&&!b.is_ready());
   if wanted {self.fetch(&venue,Duration::ZERO);}
  }
 }

 async fn write_ended(&mut self) {
  let ended=self.model.take_ended();
  if ended.is_empty() {return}
  let rows=ended.into_iter().map(|o|{let at=o.end_ms.unwrap_or(o.first_seen_ms);(o,at)}).collect();
  let _=self.writes.send(Write{step:self.step(),rows}).await;
 }

 async fn write_live(&mut self) {
  let rows=self.model.live();
  if rows.is_empty() {return}
  let _=self.writes.send(Write{step:self.step(),rows}).await;
 }
}

/// 拿品种表与门槛，直到步长有了。停了返回 None。
async fn prepare(base:&str,stop:&mut watch::Receiver<bool>)->Option<(Vec<Venue>,Thresholds)> {
 loop {
  let venues=instruments::venues(base).await;
  let thresholds=resolve(base,&venues,now_ms()).await;
  if !venues.is_empty()&&thresholds.step.is_some() {return Some((venues,thresholds))}
  tracing::info!("Orderflow history: {base} not ready ({} venues, step {:?}), retrying",venues.len(),thresholds.step);
  tokio::select! {_=stop.changed()=>return None,_=tokio::time::sleep(RESOLVE_RETRY)=>{}}
 }
}

async fn track(pool:PgPool,base:String,shared:watch::Sender<Thresholds>,mut stop:watch::Receiver<bool>) {
 let Some((venues,thresholds))=prepare(&base,&mut stop).await else {return};
 shared.send_replace(thresholds);
 let (events,mut inbox)=mpsc::channel::<Event>(8192);
 let (writes,rx)=mpsc::channel::<Write>(256);
 let writer=tokio::spawn(writer(pool.clone(),base.clone(),rx));
 let mut t=Tracker{base:base.clone(),model:Model::new(&base,thresholds),events,commands:HashMap::new(),sockets:Vec::new(),
  open:HashSet::new(),inflight:HashSet::new(),retry:HashMap::new(),writes};
 match store::live(&pool,&base).await {
  Ok(rows)=>{let n=rows.len();t.model.restore(rows,now_ms());if n>0 {tracing::info!("Orderflow history: {base} restored {n} live orders ({} ended as lost)",t.model.ended.len());}},
  Err(e)=>tracing::warn!("Orderflow history: {base} restore failed: {e}"),
 }
 t.write_ended().await;
 t.add_venues(&venues);
 let mut evaluate=tokio::time::interval(EVALUATE);
 evaluate.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
 let mut flush=tokio::time::interval_at(tokio::time::Instant::now()+FLUSH,FLUSH);
 let mut refresh=tokio::time::interval_at(tokio::time::Instant::now()+REFRESH,REFRESH);
 let (mut resolved_at,mut resolved_day)=(now_ms(),model::reference_day(now_ms()));
 loop {
  tokio::select! {
   _=stop.changed()=>break,
   Some(event)=inbox.recv()=>{
    t.handle(event);
    // 一口气把排着的都吃掉再评估，别让评估插在一串帧中间。
    while let Ok(event)=inbox.try_recv() {t.handle(event);}
   },
   _=evaluate.tick()=>{
    let now=now_ms();
    t.model.evaluate(now);
    t.due_retries(now);
    t.write_ended().await;
    // 跨 UTC 日：步长按新的前一日收盘重算。
    if model::reference_day(now)!=resolved_day {resolved_at=0;}
   },
   _=flush.tick()=>t.write_live().await,
   _=refresh.tick()=>{
    let venues=instruments::venues(&base).await;
    let now=now_ms();
    if now-resolved_at>=THRESHOLDS_EVERY_MS {
     let next=resolve(&base,&venues,now).await;
     if next.step.is_some() {
      if next!=t.model.thresholds {tracing::info!("Orderflow history: {base} thresholds {:?} -> {next:?}",t.model.thresholds);t.model.set_thresholds(next,now);shared.send_replace(next);}
      resolved_at=now;resolved_day=model::reference_day(now);
     }
    }
    t.add_venues(&venues);
    t.write_ended().await;
    tracing::info!("Orderflow history: {} {}/{} books ready, {} live",t.model.base,t.model.ready_count(),t.model.venue_ids().len(),t.model.live_count());
   },
  }
 }
 t.model.stop();
 t.write_ended().await;
 for s in &t.sockets {s.abort();}
 drop(t);
 let _=tokio::time::timeout(Duration::from_secs(10),writer).await;
 tracing::info!("Orderflow history: {base} stopped");
}

// ------------------------------------------------------------------ 跟哪些币

struct Entry {requested:i64,stop:watch::Sender<bool>,thresholds:watch::Receiver<Thresholds>,task:JoinHandle<()>}

struct Registry {pool:PgPool,entries:Mutex<HashMap<String,Entry>>}

static REGISTRY:OnceLock<Arc<Registry>>=OnceLock::new();

impl Registry {
 fn lock(&self)->std::sync::MutexGuard<'_,HashMap<String,Entry>> {self.entries.lock().unwrap_or_else(|e|e.into_inner())}

 fn start(&self,entries:&mut HashMap<String,Entry>,base:&str,requested:i64) {
  let (stop,rx)=watch::channel(false);
  let (shared,thresholds)=watch::channel(Thresholds::default());
  let task=tokio::spawn(track(self.pool.clone(),base.to_string(),shared,rx));
  entries.insert(base.to_string(),Entry{requested,stop,thresholds,task});
 }

 /// 满了就踢最久没人要的那只（三只主币不踢）。踢不动返回 false。
 fn make_room(entries:&mut HashMap<String,Entry>)->bool {
  if entries.len()<MAX_BASES {return true}
  let victim=entries.iter().filter(|(b,_)|!model::is_major(b)).min_by_key(|(_,e)|e.requested).map(|(b,_)|b.clone());
  let Some(victim)=victim else {return false};
  if let Some(e)=entries.remove(&victim) {let _=e.stop.send(true);tracing::info!("Orderflow history: {victim} evicted for room");}
  true
 }

 /// 有人要这只：记下时刻，没在跟就开始跟。回此刻的门槛（还没算出来是全空）。
 fn request(&self,base:&str,now:i64)->Thresholds {
  let mut entries=self.lock();
  if let Some(e)=entries.get_mut(base) {e.requested=now;return *e.thresholds.borrow()}
  if Self::make_room(&mut entries) {self.start(&mut entries,base,now);}
  Thresholds::default()
 }

 fn tracked(&self)->Vec<String> {self.lock().keys().cloned().collect()}

 /// 每十分钟：24 小时没人要的其它币停掉；意外结束的任务重起。
 fn sweep(&self,now:i64) {
  let mut entries=self.lock();
  let idle:Vec<String>=entries.iter().filter(|(b,e)|!model::is_major(b)&&now-e.requested>=IDLE_MS).map(|(b,_)|b.clone()).collect();
  for base in idle {if let Some(e)=entries.remove(&base) {let _=e.stop.send(true);tracing::info!("Orderflow history: {base} idle for a day, stopped");}}
  let dead:Vec<(String,i64)>=entries.iter().filter(|(_,e)|e.task.is_finished()).map(|(b,e)|(b.clone(),e.requested)).collect();
  for (base,requested) in dead {tracing::warn!("Orderflow history: {base} tracker ended unexpectedly, restarting");self.start(&mut entries,&base,requested);}
 }
}

/// 起跟踪：三只主币、以及最近 24 小时有人要过的（最多 20 只）；之后每十分钟清一遍、每小时滚动清理。
pub fn spawn(pool:PgPool)->JoinHandle<()> {
 tokio::spawn(async move {
  let registry=REGISTRY.get_or_init(||Arc::new(Registry{pool:pool.clone(),entries:Mutex::new(HashMap::new())})).clone();
  let now=now_ms();
  let recent=store::recent_bases(&pool,now).await.unwrap_or_else(|e|{tracing::warn!("Orderflow history: recent bases unreadable: {e}");Vec::new()});
  for base in ALWAYS {
   if let Err(e)=store::touch(&pool,base,now,false).await {tracing::warn!("Orderflow history: {base} not recorded: {e}");}
  }
  {
   let mut entries=registry.lock();
   for base in ALWAYS {registry.start(&mut entries,base,0);}
   for base in recent.iter().filter(|b|!ALWAYS.contains(&b.as_str())&&instruments::valid_base(b)).take(MAX_BASES-ALWAYS.len()) {
    registry.start(&mut entries,base,now);
   }
  }
  let mut sweep=tokio::time::interval_at(tokio::time::Instant::now()+SWEEP,SWEEP);
  // 进程起来一分钟后先清一次，之后每小时一次。
  let mut purge=tokio::time::interval_at(tokio::time::Instant::now()+Duration::from_secs(60),PURGE);
  loop {
   tokio::select! {
    _=sweep.tick()=>registry.sweep(now_ms()),
    _=purge.tick()=>{
     let tracked=registry.tracked();
     match store::purge(&pool,now_ms(),&tracked).await {
      Ok((deleted,closed))=>tracing::info!("Orderflow history: purge deleted {deleted}, closed {closed}; table {} bytes",store::size(&pool).await.unwrap_or(-1)),
      Err(e)=>tracing::warn!("Orderflow history: purge failed: {e}"),
     }
    },
   }
  }
 })
}

// ------------------------------------------------------------------ 路由

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct HistoryQuery {base:String,from:Option<i64>,to:Option<i64>}

/// 校验并补齐区间：`to` 缺省此刻，`from` 缺省 `to` 前 24 小时，最长 30 天。
fn window(from:Option<i64>,to:Option<i64>,now:i64)->std::result::Result<(i64,i64),&'static str> {
 let to=to.unwrap_or(now);
 let from=from.unwrap_or(to-DEFAULT_SPAN_MS);
 if from<0||to<0||from>to {return Err("invalid_range")}
 if to-from>MAX_SPAN_MS {return Err("range_too_long")}
 Ok((from,to))
}

async fn history(State(s):State<AppState>,Params(q):Params<HistoryQuery>)->Result<Response> {
 if !instruments::valid_base(&q.base) {return Err(ApiError::bad("invalid_base"))}
 let now=now_ms();
 let (from,to)=window(q.from,q.to,now).map_err(ApiError::bad)?;
 let thresholds=REGISTRY.get().map(|r|r.request(&q.base,now)).unwrap_or_default();
 let since=store::touch(&s.pool,&q.base,now,true).await?;
 let orders=store::range(&s.pool,&q.base,from,to).await?;
 let tracked_since=since.max(now-MAX_SPAN_MS);
 let mut response=Json(serde_json::json!({"base":q.base,"thresholds":thresholds,"trackedSinceMs":tracked_since,"orders":orders})).into_response();
 response.headers_mut().insert(header::CACHE_CONTROL,HeaderValue::from_static("no-cache"));
 Ok(response)
}

pub fn routes()->Router<AppState> {
 Router::new().route(PATH,get(history)).route_layer(tower_http::compression::CompressionLayer::new())
}

#[cfg(test)]
mod tests {
 use super::*;

 #[test] fn window_defaults_and_limits() {
  let now=100*store::DAY_MS;
  assert_eq!(window(None,None,now),Ok((now-store::DAY_MS,now)));
  assert_eq!(window(Some(5),Some(9),now),Ok((5,9)));
  assert_eq!(window(None,Some(now-store::DAY_MS),now),Ok((now-2*store::DAY_MS,now-store::DAY_MS)));
  assert_eq!(window(Some(now-30*store::DAY_MS),None,now),Ok((now-30*store::DAY_MS,now)));
  assert_eq!(window(Some(now-30*store::DAY_MS-1),None,now),Err("range_too_long"));
  assert_eq!(window(Some(9),Some(5),now),Err("invalid_range"));
  assert_eq!(window(Some(-1),Some(5),now),Err("invalid_range"));
 }

 #[test] fn previous_close_prefers_the_utc_day_row() {
  let day=20*store::DAY_MS;
  let rows=serde_json::json!([[day-store::DAY_MS,"0","0","0","90"],[day,"0","0","0","100"],[day+store::DAY_MS,"0","0","0","110"]]);
  assert_eq!(previous_close(&rows,day),Some(100.0));
  let shifted=serde_json::json!([[day-3_600_000,"0","0","0","95"],[day+store::DAY_MS-3_600_000,"0","0","0","105"]]);
  assert_eq!(previous_close(&shifted,day),Some(105.0));
 }

 #[test] fn venue_ids_match_the_phone() {
  let v=Venue{exchange:Exchange::Binance,product:Product::UsdtPerp,instrument:"1000PEPEUSDT".into(),margin:None,
   notional:instruments::Notional::Linear{multiplier:1.0},tick:0.0000001,expiry_ms:None,price_scale:Some(1000),listed_base:"1000PEPE".into()};
  let i=info(&v);
  assert_eq!((i.id.as_str(),i.label,i.price_scale,i.in_band),("binance:usdtPerp:1000PEPEUSDT","币安",1000.0,false));
  assert_eq!(i.sequence,Sequence::PreviousFinalOverlap);
  let v=Venue{exchange:Exchange::Coinbase,product:Product::Spot,instrument:"BTC-USD".into(),margin:None,
   notional:instruments::Notional::Linear{multiplier:1.0},tick:0.01,expiry_ms:None,price_scale:None,listed_base:"BTC".into()};
  assert_eq!(info(&v).id,"coinbase:spot:BTC-USD");
 }
}
