//! 主力订单流 · 服务端历史（2026-09-24，2026-09-25 改成分层常驻）。
//!
//! 手机上的订单流只在打开一只品种时才开始跟，关掉就断：刚打开时图上是空的，往左拖也没有。
//! 这里在 serve 进程里常驻跟踪，一单一行写进 `orderflow_orders`；手机打开品种先拉最近 24 小时，
//! 之后每分钟增量拉一次，往左拖再一天一天补（最多 3 天）。
//!
//! * 跟踪规则和手机那份（`OrderFlowModel.swift`）逐条一致，见 `model.rs`；簿的接续见 `book.rs`；
//!   帧的解码见 `feeds.rs`；连接池见 `hub.rs`；REST 快照队列见 `snapshots.rs`；分层见 `layers.rs`；
//!   资源闸门见 `resources.rs`；库见 `store.rs`。
//! * 只按**默认门槛**跟（`OrderFlowDefaults` 那张表 + 前一日收盘推的步长；非币按簿深标定，见下）。
//!   用户在手机上改过门槛的，手机拿到之后自己按自己的门槛过滤。
//! * 跟哪些币：主币、固定（美股 / 大宗 / 指数）、山寨（成交额前 40）、热点（四路信号，每小时）、按需（手机打开的）
//!   五层，总数最多 220 只，满了只踢按需与热点里最久没人要的；详见 `layers.rs`。
//!   `KANPAN_ORDERFLOW_LAYERS` 选开哪几层，缺省全开。
//! * **手机的行情转发永远优先**：这里的连接与 REST 全部自己开、自己限速（各家额度的一小份），
//!   资源闸门（RSS > 2.5 GB 或最近一分钟 CPU > 300%）一过就不再新增，并按热点 → 山寨 → 固定卸层，
//!   转发那一侧一概不动。
//! * 非币默认门槛：T = round125(0.03 × D)，夹 [5 万, 200 万]，D 为各 U 本位永续簿中间价 ±1% 以内买卖两侧美元之和；
//!   簿全部拿到首个快照时标定；有簿还没连上或快照还在排队就接着等（最多 10 分钟），不再有簿在等
//!   （或到了 10 分钟）之后 8 秒，用已就绪的标，之后簿都齐了再补标一次；每个 UTC 日重标一次。标定前不评估、不读回挂着的单，
//!   `/history` 回的 `thresholds.usdtPerp` 为空。一本簿都没有回退 200 万。
//! * 写库：挂着的单每 15 秒刷一次，只写新出现的、名义 / 成交 / 门槛变了 1% 以上的、以及 60 秒没写过的
//!   （刷新 `seen_ms`）；结束的单一结束就写；所有币合起来最多同时占 3 条库连接。进程重启读回挂着的单，
//!   缺席超过 2 分钟的按最后一次看到时失联结束。每小时滚动清理一次（3 天 + 20 GB 闸门）。
//! * 接口 `GET /v1/market/orderflow/history?base=&from=&to=`：`to` 缺省为此刻，`from` 缺省为
//!   `to` 前 24 小时，区间最长 3 天；回 `{base, thresholds, trackedSinceMs, orders}`，gzip。
//!   没在跟的币回空表、`trackedSinceMs` 为此刻，并从这一刻开始跟（按需层）。`trackedSinceMs` 是这一段连着跟的起点：
//!   跟踪器断过十分钟以上（停掉、没人要）再起跟，从起跟那一刻重新算（0026 的 `alive_ms`）。
//! * 只在带库的 serve 进程里有；备用节点跑的是 metrics（没有库），不挂这条路由。
mod book;
mod feeds;
mod hub;
mod layers;
mod model;
mod resources;
mod snapshots;
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
use feeds::Event;
use layers::Enabled;
use model::{BigOrder,Model,Notional,Restored,Thresholds};
use serde::Deserialize;
use serde_json::Value;
use sqlx::PgPool;
use std::collections::{HashMap,HashSet};
use std::sync::atomic::{AtomicBool,AtomicU8,AtomicU64,Ordering};
use std::sync::{Arc,Mutex,OnceLock};
use std::time::Duration;
use tokio::sync::{mpsc,watch};
use tokio::task::JoinHandle;

const PATH:&str="/v1/market/orderflow/history";
/// 一直跟的三只。
const ALWAYS:[&str;3]=layers::MAJORS;
/// 同时最多跟几只（五层合计）。
const MAX_BASES:usize=220;
/// 按需层（只因为有人要才跟的）最多几只。
const MAX_ON_DEMAND:usize=20;
/// 按需的多久没人要就停；山寨、热点掉榜之后再跟多久。
const IDLE_MS:i64=store::DAY_MS;
const LINGER_MS:i64=store::DAY_MS;
const DEFAULT_SPAN_MS:i64=store::DAY_MS;
const MAX_SPAN_MS:i64=store::RETENTION_MS;
const EVALUATE:Duration=Duration::from_millis(500);
const FLUSH:Duration=Duration::from_secs(15);
const REFRESH:Duration=Duration::from_secs(10*60);
const THRESHOLDS_EVERY_MS:i64=60*60*1000;
const SWEEP:Duration=Duration::from_secs(10*60);
const PURGE:Duration=Duration::from_secs(60*60);
/// 快照失败之后隔多久再排：第一次 2 秒，之后每连着失败一次翻倍，最多 5 分钟；拿到一份就从头算。
/// 原来一律 2 秒：一本簿的快照一直拿不到（下架 / 结算中回 400、回的东西解析不了），它每 2 秒排一次，
/// 在限速队里（每条通道每分钟 30 份）按层抢在前面，主币上的一本就能把整条通道的配额吃光，别的簿都等不到快照。
const SNAPSHOT_RETRY_MS:i64=2_000;
const SNAPSHOT_RETRY_MAX_MS:i64=5*60_000;

/// 连着失败 `failures` 次（≥ 1）之后隔多久再排。
fn snapshot_backoff(failures:u32)->i64 {SNAPSHOT_RETRY_MS.saturating_mul(1i64<<failures.saturating_sub(1).min(20)).min(SNAPSHOT_RETRY_MAX_MS)}
/// 没变化的挂着的单多久重写一次（刷新 `seen_ms`）；须小于 `model::STALE_MS`（120 秒）。
const LIVE_REWRITE_MS:i64=60_000;
const SNAPSHOT_SETTLE:Duration=Duration::from_millis(500);
/// 非币门槛标定最多等多久（从订阅起）：满额 220 只冷启动时 U 本位快照按每分钟 30 份排，最后一份约 7 分钟后到。
const CALIBRATION_CAP_MS:i64=10*60_000;
/// 还拿不到步长（收盘没拉到）时隔多久再试。
const RESOLVE_RETRY:Duration=Duration::from_secs(30);
/// 成批起跟踪（进程启动、层重算）时两只之间隔多久：拉品种表、收盘、订阅都错开，不一口气打出去。
const START_GAP:Duration=Duration::from_millis(250);
/// 资源采样与层的节拍。
const SAMPLE:Duration=Duration::from_secs(15);
const LAYER_TICK:Duration=Duration::from_secs(60);
const HOT_EVERY_MS:i64=60*60*1000;
const FIXED_EVERY_MS:i64=10*60*1000;
/// 资源闸门连续多少分钟不超才放回一层。
const SHED_RECOVER_MINUTES:u32=10;

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

/// 是不是币：主币是；跟踪器已经判过的照旧（`known`）；币安没有这只 U 本位永续的按币算；
/// 否则看它在合约表里的 `underlyingType` 是不是 COIN。合约表拿不到（`info` 为 None）回 None：不知道就不猜。
///
/// 原来拿不到合约表一律按币算：那一刻起跟的美股按币的成交额分档拿门槛、也不按簿深标定，一直错到这只停掉；
/// 每小时重算门槛时再撞上一次失败，已经在标定的美股也会被换成币的门槛。
fn crypto_kind(base:&str,perp:Option<&Venue>,known:Option<bool>,info:Option<&Value>)->Option<bool> {
 if model::is_major(base) {return Some(true)}
 if let Some(known)=known {return Some(known)}
 let Some(perp)=perp else {return Some(true)};
 let info=info?;
 Some(info["symbols"].as_array().and_then(|rows|rows.iter().find(|s|s["symbol"].as_str()==Some(perp.instrument.as_str())))
  .and_then(|s|s["underlyingType"].as_str()).is_none_or(|t|t=="COIN"))
}

async fn is_crypto(base:&str,perp:Option<&Venue>,known:Option<bool>)->Option<bool> {
 if let Some(kind)=crypto_kind(base,perp,known,None) {return Some(kind)}
 let info=crate::market_meta::exchange_info().await.ok()?;
 crypto_kind(base,perp,known,Some(&info))
}

fn number(v:&Value)->Option<f64> {
 let x=match v {Value::String(s)=>s.parse().ok()?,Value::Number(n)=>n.as_f64()?,_=>return None};
 (x as f64).is_finite().then_some(x)
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

/// 这只币此刻的默认门槛与步长（步长可能还是 None：收盘没拉到），以及它是不是币。
/// 非币的 U 本位门槛这里给的是回退值 200 万，真正用的是跟踪器按簿深标定的那个。
/// `known`：跟踪器起跟时已经判过是不是币，重算门槛时沿用；还没判过而合约表拿不到时回 None。
async fn resolve(base:&str,venues:&[Venue],now:i64,known:Option<bool>)->Option<(Thresholds,bool)> {
 let perp=binance_perp(venues);
 let crypto=is_crypto(base,perp,known).await?;
 let turnover=match perp {Some(p) if crypto&&!model::is_major(base)=>layers::turnover(&p.instrument).await,_=>None};
 let mut t=model::defaults(base,crypto,turnover);
 if t.step.is_none() {t.step=derived_step(venues,model::reference_day(now)).await;}
 Some((t,crypto))
}

// ------------------------------------------------------------------ 一只币的跟踪

/// 写库只走一个任务：挂着的与结束的按到达先后写，不会乱序把结束翻回挂着。
struct Write {step:f64,rows:Vec<(BigOrder,i64)>}

/// 所有币的写库任务合起来最多同时占这么多条库连接：连接池一共 8 条，还要留给账号、同步与读历史的请求。
/// 本地全开 154 只时，几十个跟踪任务同一时刻刷盘把池子占满，账号请求拿连接要等 2–3 秒（sqlx 慢获取告警）。
static WRITE_SLOTS:tokio::sync::Semaphore=tokio::sync::Semaphore::const_new(3);

/// 写失败之后隔多久再写：从 1 秒起翻倍，最多 1 分钟。
const WRITE_RETRY_MIN:Duration=Duration::from_secs(1);
const WRITE_RETRY_MAX:Duration=Duration::from_secs(60);
/// 跟踪停了之后还没写进去的最多再试多久（跟踪任务等写库任务结束才算收完尾，见 `Registry::stop`）。
const WRITE_DRAIN:Duration=Duration::from_secs(60);
/// 写库任务手里没有积压时多久记一次「还活着」（`orderflow_bases.alive_ms`，见 `store::continuous_since`）。
const ALIVE_EVERY:Duration=Duration::from_secs(60);
/// 一只币积压的行最多留多少：库长时间写不进去时先丢挂着的（它们一分钟之内会整行重写），再丢结束得最早的。
const PENDING_CAP:usize=50_000;

/// 还没写进库的行，一单只留一份。同一单后来的那份盖掉前面的——但结束的不被挂着的盖回去，
/// 和库里 upsert 的 `WHERE end_ms IS NULL` 同一个规矩。写失败的留在这里跟下一批一起写。
#[derive(Default)]
struct Pending {rows:HashMap<LiveKey,(f64,BigOrder,i64)>}

impl Pending {
 fn add(&mut self,w:Write) {
  for (order,seen) in w.rows {
   let key:LiveKey=(order.venue_id.clone(),order.side,order.bucket,order.first_seen_ms);
   if self.rows.get(&key).is_some_and(|(_,o,_)|o.end_ms.is_some()&&order.end_ms.is_none()) {continue}
   self.rows.insert(key,(w.step,order,seen));
  }
  if self.rows.len()>PENDING_CAP {self.shed();}
 }
 /// 超了上限：先丢挂着的，还超就丢结束得最早的。返回丢了几行。
 fn shed(&mut self)->usize {
  let before=self.rows.len();
  self.rows.retain(|_,(_,o,_)|o.end_ms.is_some());
  if self.rows.len()>PENDING_CAP {
   let mut oldest:Vec<(i64,LiveKey)>=self.rows.iter().map(|(k,(_,o,_))|(o.end_ms.unwrap_or(i64::MIN),k.clone())).collect();
   oldest.sort_unstable_by_key(|(end,_)|*end);
   for (_,key) in oldest.into_iter().take(self.rows.len()-PENDING_CAP) {self.rows.remove(&key);}
  }
  before-self.rows.len()
 }
 fn is_empty(&self)->bool {self.rows.is_empty()}
 /// 按步长分组、每组最多 500 行一批：写进去的从积压里拿掉，写失败的那一批与后面的都留着。
 fn batches(&self)->Vec<(f64,Vec<LiveKey>)> {
  let mut groups:HashMap<u64,Vec<LiveKey>>=HashMap::new();
  for (key,(step,_,_)) in &self.rows {groups.entry(step.to_bits()).or_default().push(key.clone());}
  groups.into_iter().flat_map(|(step,keys)|keys.chunks(500).map(|c|(f64::from_bits(step),c.to_vec())).collect::<Vec<_>>()).collect()
 }
 async fn flush(&mut self,pool:&PgPool,base:&str)->sqlx::Result<()> {
  for (step,keys) in self.batches() {
   let rows:Vec<(BigOrder,i64)>=keys.iter().filter_map(|k|self.rows.get(k).map(|(_,o,s)|(o.clone(),*s))).collect();
   store::upsert(pool,base,step,&rows).await?;
   for k in &keys {self.rows.remove(k);}
  }
  Ok(())
 }
}

/// 一只币的写库任务。库写不进去（重启、连接池满、语句超时）时整批留着退避重写，同时照常收跟踪那边发来的，
/// 不让跟踪任务卡在 `send` 上；原来失败就记一条日志丢掉，结束的单丢了，库里那行就一直挂成「进行中」。
/// 手里的都写进去了，每分钟记一次「还活着」。
async fn writer(pool:PgPool,base:String,mut rx:mpsc::Receiver<Write>) {
 let mut pending=Pending::default();
 let mut backoff=WRITE_RETRY_MIN;
 let mut open=true;
 let mut drain_until=None;
 let mut alive_at=tokio::time::Instant::now();
 loop {
  if pending.is_empty() {
   if !open {return}
   tokio::select! {
    w=rx.recv()=>match w {Some(w)=>pending.add(w),None=>return},
    _=tokio::time::sleep_until(alive_at)=>{},
   }
  }
  while let Ok(w)=rx.try_recv() {pending.add(w);}
  let result={
   // 排库连接（全进程 3 条）的时候也接着收：两百多只一起刷盘时可能要排上好一阵，这期间通道满了跟踪任务就卡在 send 上。
   let slot=loop {
    tokio::select! {
     slot=WRITE_SLOTS.acquire()=>break slot,
     w=rx.recv(),if open=>match w {Some(w)=>pending.add(w),None=>open=false},
    }
   };
   let Ok(_slot)=slot else {return};
   let mut result=pending.flush(&pool,&base).await;
   if result.is_ok()&&tokio::time::Instant::now()>=alive_at {
    result=store::alive(&pool,&base,now_ms()).await;
    if result.is_ok() {alive_at=tokio::time::Instant::now()+ALIVE_EVERY;}
   }
   result
  };
  match result {
   Ok(())=>backoff=WRITE_RETRY_MIN,
   Err(e)=>{
    tracing::warn!("Orderflow history: {base} write failed ({} rows waiting, retry in {backoff:?}): {e}",pending.rows.len());
    let wake=tokio::time::Instant::now()+backoff;
    backoff=(backoff*2).min(WRITE_RETRY_MAX);
    // 等的时候接着收，不让跟踪那边的 send 堵住。
    while open {
     tokio::select! {
      _=tokio::time::sleep_until(wake)=>break,
      w=rx.recv()=>match w {Some(w)=>pending.add(w),None=>open=false},
     }
    }
    if !open {
     let until=*drain_until.get_or_insert_with(||tokio::time::Instant::now()+WRITE_DRAIN);
     if tokio::time::Instant::now()>=until {
      tracing::warn!("Orderflow history: {base} stopped with {} rows unwritten (restore / purge will close them)",pending.rows.len());
      return;
     }
     tokio::time::sleep_until(wake.min(until)).await;
    }
   },
  }
 }
}

/// 非币门槛的标定（见模块说明）。
struct Calibration {
 /// 非币才要标。
 needed:bool,
 /// 标出来的门槛与标定那天（`reference_day`）。
 value:Option<f64>,
 day:Option<i64>,
 /// 上一次标定时不是所有簿都就绪：等它们都就绪了再补标一次（只补一次）。
 partial:bool,
 /// 8 秒从哪一刻起算：订阅那一刻；之后只要还有簿没连上（币安的新簿要攒 5–15 秒成批开连接）、
 /// 或者它的快照还在排队，就往后推——这两段等待是这里的连接批次与快照限速造成的，
 /// 不该让 OKX 那一本（流内快照、立刻就绪）单独把门槛标了。最多等 `CALIBRATION_CAP_MS`。
 since:i64,
 subscribed:i64,
 /// 标定之前读回来的挂单：标定之后再读回（照手机：标定前不评估、不读回）。
 restored:Option<Vec<Restored>>,
}

impl Calibration {
 /// 此刻该不该标：第一次——簿全就绪、没有簿，或者至少一本就绪且 8 秒里没有簿还在等连接 / 等快照
 /// （等了 `CALIBRATION_CAP_MS` 就不再等）；之后——跨了 UTC 日，或上次只标了一部分簿、现在都就绪了。
 fn due(&mut self,now:i64,day:i64,total:usize,ready:usize,waiting:bool)->bool {
  if !self.needed {return false}
  if self.value.is_none() {
   if waiting&&now-self.subscribed<CALIBRATION_CAP_MS {self.since=now;}
   return total==0||ready==total||(ready>=1&&now-self.since>=model::CALIBRATION_WAIT_MS)
  }
  if self.partial&&total>0&&ready==total {return true}
  self.day!=Some(day)&&ready>0
 }
}

struct Tracker {
 base:String,
 model:Model,
 events:mpsc::Sender<Event>,
 open:HashSet<String>,
 /// 排着的快照：簿 → 那份请求的 epoch。
 inflight:HashMap<String,u64>,
 retry:HashMap<String,i64>,
 /// 每本簿连着失败了几次快照（拿到一份清零）。
 failures:HashMap<String,u32>,
 /// 每本簿此刻的 epoch，快照队列按它丢过期的请求。
 epochs:HashMap<String,Arc<AtomicU64>>,
 /// 每本簿最后一笔成交号（换连接的重叠期里两条连接都推同一笔，按号去重）。
 last_trade:HashMap<String,i64>,
 /// 挂着的单上次写库时的量、成交、门槛与时刻（见 `changed_live`）。
 written:HashMap<LiveKey,(f64,f64,f64,i64)>,
 priority:Arc<AtomicU8>,
 writes:mpsc::Sender<Write>,
 calibration:Calibration,
 /// 订阅按这套门槛挑产品（非币标定之前 `model.thresholds.usdt_perp` 是空的，但 U 本位永续要订）。
 planned:Thresholds,
 shared:watch::Sender<Thresholds>,
}

impl Tracker {
 fn step(&self)->f64 {self.model.thresholds.step.unwrap_or(0.0)}
 fn calibrating(&self)->bool {self.calibration.needed&&self.calibration.value.is_none()}

 fn add_venues(&mut self,venues:&[Venue]) {
  let known:HashSet<String>=self.model.venue_ids().into_iter().collect();
  let fresh:Vec<VenueInfo>=venues.iter().filter(|v|self.planned.of(wire_product(v.product)).is_some()).map(info).filter(|v|!known.contains(&v.id)).collect();
  if fresh.is_empty() {return}
  tracing::debug!("Orderflow history: {} tracks {}",self.base,fresh.iter().map(|v|v.id.as_str()).collect::<Vec<_>>().join(", "));
  for v in &fresh {self.model.add_venue(v.clone());}
  hub::add(fresh,&self.events);
 }

 fn sync_epoch(&mut self,id:&str) {
  let Some(epoch)=self.model.book_mut(id).map(|b|b.epoch) else {return};
  self.epochs.entry(id.to_string()).or_insert_with(||Arc::new(AtomicU64::new(0))).store(epoch,Ordering::Relaxed);
 }

 fn act(&mut self,venue:&str,action:Action) {
  match action {
   Action::None=>{},
   Action::Resubscribe=>hub::resubscribe(venue.to_string()),
   Action::FetchSnapshot=>self.fetch(venue,SNAPSHOT_SETTLE),
  }
 }

 /// 排一份 REST 快照（全进程一条限速队列，见 `snapshots.rs`）。同一 epoch 已经排着就不重复排。
 fn fetch(&mut self,venue:&str,settle:Duration) {
  let Some(book)=self.model.book_mut(venue) else {return};
  let (info,epoch)=(book.venue.clone(),book.epoch);
  if self.inflight.get(venue)==Some(&epoch) {return}
  self.inflight.insert(venue.to_string(),epoch);
  self.retry.remove(venue);
  self.sync_epoch(venue);
  let Some(current)=self.epochs.get(venue).cloned() else {return};
  snapshots::request(snapshots::Request{venue:info,epoch,priority:self.priority.clone(),not_before:tokio::time::Instant::now()+settle,events:self.events.clone(),current});
 }

 fn handle(&mut self,event:Event) {
  let now=now_ms();
  match event {
   Event::Opened{venues,connection}=>for id in venues {
    self.open.insert(id.clone());
    let action=self.model.book_mut(&id).map_or(Action::None,|b|b.opened(connection));
    self.sync_epoch(&id);
    self.act(&id,action);
   },
   // 连接池换连接（24 小时前换新、合并）：还连着的簿接着用，两条连接的帧都认；没连着的按新连接从头开。
   Event::Handover{venues,connection}=>for id in venues {
    let was_open=self.open.contains(&id);
    let action=self.model.book_mut(&id).map_or(Action::None,|b|if was_open {b.handover(connection)} else {b.opened(connection)});
    self.open.insert(id.clone());
    self.sync_epoch(&id);
    self.act(&id,action);
   },
   Event::Closed{venues,connection}=>for id in venues {
    if self.model.book_mut(&id).is_some_and(|b|b.connection==connection) {self.open.remove(&id);}
    self.model.closed(&id,connection);
    self.sync_epoch(&id);
   },
   Event::Frame{venue,connection,message}=>{
    let action=self.model.ingest(&venue,connection,message,now);
    self.act(&venue,action);
   },
   Event::Trade{venue,trade,id}=>{
    if let Some(id)=id {
     let last=self.last_trade.entry(venue.clone()).or_insert(i64::MIN);
     if id<=*last {return}
     *last=id;
    }
    self.model.trade(&venue,trade);
   },
   Event::Snapshot{venue,epoch,snapshot}=>{
    if self.inflight.get(&venue)==Some(&epoch) {self.inflight.remove(&venue);}
    let Some(book)=self.model.book_mut(&venue) else {return};
    // 排队期间断过线：这份是上一轮的，新一轮的请求在 opened 时已经排上了。
    if book.epoch!=epoch {return}
    match snapshot {
     Some(s)=>{self.failures.remove(&venue);let action=book.snapshot(s,now);self.act(&venue,action);},
     None=>{
      let failures=self.failures.entry(venue.clone()).or_insert(0);
      *failures+=1;
      if *failures==6 {tracing::warn!("Orderflow history: {venue} snapshot failed 6 times in a row, retrying every {}s at most",SNAPSHOT_RETRY_MAX_MS/1000);}
      let at=now+snapshot_backoff(*failures);
      self.retry.insert(venue,at);
     },
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

 /// 非币门槛：到点就标，跨 UTC 日重标。第一次标完才开始评估、读回挂着的单。
 fn calibrate(&mut self,now:i64) {
  if !self.calibration.needed {return}
  let day=model::reference_day(now);
  let books:Vec<String>=self.model.venue_ids();
  let total=books.len();
  let ready=self.model.ready_count();
  let waiting=books.iter().any(|id|!self.open.contains(id)||self.inflight.contains_key(id));
  if !self.calibration.due(now,day,total,ready,waiting) {return}
  let depth=self.model.depth_usd(model::CALIBRATION_BPS);
  let value=model::calibrated_threshold(depth);
  let first=self.calibration.value.is_none();
  self.calibration.value=Some(value);
  self.calibration.day=Some(day);
  self.calibration.partial=ready<total;
  tracing::info!("Orderflow history: {} usdtPerp threshold calibrated to {value} (±1% depth {depth:.0} USD over {ready}/{total} books)",self.base);
  let mut next=self.model.thresholds;
  next.usdt_perp=Some(value);
  if next!=self.model.thresholds {self.model.set_thresholds(next,now);}
  self.shared.send_replace(next);
  if first && let Some(rows)=self.calibration.restored.take() {
   let n=rows.len();
   self.model.restore(rows,now);
   if n>0 {tracing::info!("Orderflow history: {} restored {n} live orders after calibration ({} ended as lost)",self.base,self.model.ended.len());}
  }
 }

 async fn write_ended(&mut self) {
  let ended=self.model.take_ended();
  if ended.is_empty() {return}
  let rows=ended.into_iter().map(|o|{let at=o.end_ms.unwrap_or(o.first_seen_ms);(o,at)}).collect();
  let _=self.writes.send(Write{step:self.step(),rows}).await;
 }

 async fn write_live(&mut self) {
  let rows=changed_live(self.model.live(),&mut self.written,now_ms());
  if rows.is_empty() {return}
  let _=self.writes.send(Write{step:self.step(),rows}).await;
 }
}

/// 一条挂着的单在库里的身份：簿、侧、桶、出现时刻。
type LiveKey=(String,book::Side,i64,i64);

/// 这一轮要写的挂着的单：新出现的、量或成交或门槛变了 1% 以上的、以及上次写已经过了 `LIVE_REWRITE_MS` 的
/// （`seen_ms` 要赶在 `model::STALE_MS` 之前刷新，重启读回时才不会被当成失联）。220 只全开时每 15 秒整表重写
/// 一遍是本地实测里 Postgres 出现慢语句的原因，大部分墙在两次刷新之间根本没动。
fn changed_live(rows:Vec<(BigOrder,i64)>,written:&mut HashMap<LiveKey,(f64,f64,f64,i64)>,now:i64)->Vec<(BigOrder,i64)> {
 let moved=|a:f64,b:f64|(a-b).abs()>b.abs()*0.01;
 let mut keep=HashSet::new();
 let mut out=Vec::new();
 for (order,seen) in rows {
  let key:LiveKey=(order.venue_id.clone(),order.side,order.bucket,order.first_seen_ms);
  let fresh=(order.notional,order.filled_notional,order.threshold);
  let due=match written.get(&key) {
   None=>true,
   Some(&(n,f,t,at))=>moved(fresh.0,n)||moved(fresh.1,f)||moved(fresh.2,t)||now-at>=LIVE_REWRITE_MS,
  };
  if due {written.insert(key.clone(),(fresh.0,fresh.1,fresh.2,now));out.push((order,seen));}
  keep.insert(key);
 }
 written.retain(|k,_|keep.contains(k));
 out
}

/// 拿品种表与门槛，直到步长有了。停了返回 None。
async fn prepare(base:&str,stop:&mut watch::Receiver<bool>)->Option<(Vec<Venue>,Thresholds,bool)> {
 loop {
  let venues=instruments::venues(base).await;
  let resolved=if venues.is_empty() {None} else {resolve(base,&venues,now_ms(),None).await};
  match resolved {
   Some((thresholds,crypto)) if thresholds.step.is_some()=>return Some((venues,thresholds,crypto)),
   Some((thresholds,_))=>tracing::info!("Orderflow history: {base} not ready ({} venues, step {:?}), retrying",venues.len(),thresholds.step),
   None=>tracing::info!("Orderflow history: {base} not ready ({} venues, coin or not unknown), retrying",venues.len()),
  }
  tokio::select! {_=stop.changed()=>return None,_=tokio::time::sleep(RESOLVE_RETRY)=>{}}
 }
}

async fn track(pool:PgPool,base:String,shared:watch::Sender<Thresholds>,mut stop:watch::Receiver<bool>,priority:Arc<AtomicU8>,delay:Duration,
 after:Option<JoinHandle<()>>) {
 // 上一任还在收尾：等它把结束的单写进库，再读回挂着的。
 if let Some(previous)=after {
  tokio::select! {_=stop.changed()=>return,_=previous=>{}}
 }
 if !delay.is_zero() {
  tokio::select! {_=stop.changed()=>return,_=tokio::time::sleep(delay)=>{}}
 }
 let Some((venues,thresholds,crypto))=prepare(&base,&mut stop).await else {return};
 if let Err(e)=store::start(&pool,&base,now_ms()).await {tracing::warn!("Orderflow history: {base} not recorded: {e}");}
 let needed=!crypto;
 let mut published=thresholds;
 if needed {published.usdt_perp=None;}
 shared.send_replace(published);
 let (events,mut inbox)=mpsc::channel::<Event>(8192);
 let (writes,rx)=mpsc::channel::<Write>(256);
 let writer=tokio::spawn(writer(pool.clone(),base.clone(),rx));
 let mut t=Tracker{base:base.clone(),model:Model::new(&base,published),events,open:HashSet::new(),inflight:HashMap::new(),retry:HashMap::new(),failures:HashMap::new(),
  epochs:HashMap::new(),last_trade:HashMap::new(),written:HashMap::new(),priority,writes,
  calibration:Calibration{needed,value:None,day:None,partial:false,since:now_ms(),subscribed:now_ms(),restored:None},planned:thresholds,shared};
 match store::live(&pool,&base).await {
  Ok(rows) if needed=>t.calibration.restored=Some(rows),
  Ok(rows)=>{let n=rows.len();t.model.restore(rows,now_ms());if n>0 {tracing::info!("Orderflow history: {base} restored {n} live orders ({} ended as lost)",t.model.ended.len());}},
  Err(e)=>tracing::warn!("Orderflow history: {base} restore failed: {e}"),
 }
 t.write_ended().await;
 t.add_venues(&venues);
 (t.calibration.since,t.calibration.subscribed)=(now_ms(),now_ms());
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
    t.calibrate(now);
    if t.calibrating() {t.model.trim();} else {t.model.evaluate(now);}
    t.due_retries(now);
    t.write_ended().await;
    // 跨 UTC 日：步长按新的前一日收盘重算。
    if model::reference_day(now)!=resolved_day {resolved_at=0;}
   },
   _=flush.tick()=>t.write_live().await,
   _=refresh.tick()=>{
    let venues=instruments::venues(&base).await;
    let now=now_ms();
    if now-resolved_at>=THRESHOLDS_EVERY_MS
     && let Some((mut next,_))=resolve(&base,&venues,now,Some(!t.calibration.needed)).await && next.step.is_some() {
     t.planned=next;
     if t.calibration.needed {next.usdt_perp=t.calibration.value;}
     if next!=t.model.thresholds {tracing::info!("Orderflow history: {base} thresholds {:?} -> {next:?}",t.model.thresholds);t.model.set_thresholds(next,now);t.shared.send_replace(next);}
     resolved_at=now;resolved_day=model::reference_day(now);
    }
    t.add_venues(&venues);
    t.write_ended().await;
    tracing::debug!("Orderflow history: {} {}/{} books ready, {} live",t.model.base,t.model.ready_count(),t.model.venue_ids().len(),t.model.live_count());
   },
  }
 }
 t.model.stop();
 t.write_ended().await;
 hub::remove(t.model.venue_ids(),&t.events);
 drop(t);
 // 等写库任务写完手里的（它自己最多再试 `WRITE_DRAIN`）：注册表按这个任务结束判断收尾完了。
 let _=writer.await;
 tracing::info!("Orderflow history: {base} stopped");
}

// ------------------------------------------------------------------ 跟哪些币

/// 一只币为什么在跟，按强到弱。数值也是快照队列里的先后（小的先）。
#[derive(Clone,Copy,Debug,PartialEq,Eq,PartialOrd,Ord,Hash)]
enum Layer {Major=0,OnDemand=1,Fixed=2,Alt=3,Hot=4}

impl Layer {
 fn label(self)->&'static str {match self {Layer::Major=>"majors",Layer::OnDemand=>"on-demand",Layer::Fixed=>"fixed",Layer::Alt=>"alts",Layer::Hot=>"hot"}}
}

/// 资源闸门卸到第几层：0 不卸，1 卸热点，2 再卸山寨，3 再卸固定。主币与按需不卸。
fn shed_label(level:u8)->&'static str {match level {0=>"nothing",1=>"hot",2=>"hot+alts",_=>"hot+alts+fixed"}}

/// 在榜上（没有截止时刻）。
const LISTED:i64=i64::MAX;

struct Entry {
 major:bool,
 fixed:bool,
 /// 山寨 / 热点：在榜上为 `LISTED`，掉榜之后为掉榜时刻 + 24 小时，不在这一层为 0。
 alt_until:i64,
 hot_until:i64,
 /// 最后一次在热点榜上的时刻。
 hot_seen:i64,
 /// 最后一次有人要的时刻（没人要过为 0）。
 requested:i64,
 priority:Arc<AtomicU8>,
 stop:watch::Sender<bool>,
 thresholds:watch::Receiver<Thresholds>,
 task:JoinHandle<()>,
}

impl Entry {
 fn on_demand(&self,now:i64)->bool {self.requested>0&&now-self.requested<IDLE_MS}
 /// 此刻最强的理由（按卸层之后算）；None 就是不该再跟了。
 fn layer(&self,now:i64,shed:u8)->Option<Layer> {
  if self.major {Some(Layer::Major)}
  else if self.on_demand(now) {Some(Layer::OnDemand)}
  else if self.fixed&&shed<3 {Some(Layer::Fixed)}
  else if self.alt_until>now&&shed<2 {Some(Layer::Alt)}
  else if self.hot_until>now&&shed<1 {Some(Layer::Hot)}
  else {None}
 }
 /// 满了可以踢的：只因为按需或热点在跟的。
 fn evictable(&self,now:i64)->bool {!self.major&&!self.fixed&&self.alt_until<=now}
 fn wanted_at(&self)->i64 {self.requested.max(self.hot_seen)}
 fn only_on_demand(&self,now:i64)->bool {self.on_demand(now)&&!self.major&&!self.fixed&&self.alt_until<=now&&self.hot_until<=now}
 fn only_hot(&self,now:i64)->bool {self.hot_until>now&&!self.major&&!self.fixed&&self.alt_until<=now&&!self.on_demand(now)}
}

/// 各层最近一次算出来的名单（卸层恢复时重新套用）。
#[derive(Default)]
struct Lists {fixed:Vec<String>,alts:Vec<String>,hot:Vec<String>}

struct Registry {
 pool:PgPool,
 entries:Mutex<HashMap<String,Entry>>,
 lists:Mutex<Lists>,
 /// 资源闸门此刻超没超（超了不再新增）。
 over:AtomicBool,
 shed:AtomicU8,
 /// 成批起跟踪时下一只排到什么时候。
 next_start:Mutex<tokio::time::Instant>,
 /// 停掉了、还在收尾（结束挂着的单、把积压写进库）的跟踪任务。同一只马上又被起跟时，新的等旧的收完尾再读回挂着的单。
 retiring:Mutex<HashMap<String,JoinHandle<()>>>,
}

static REGISTRY:OnceLock<Arc<Registry>>=OnceLock::new();

type Entries=HashMap<String,Entry>;

impl Registry {
 fn new(pool:PgPool)->Self {
  Self{pool,entries:Mutex::new(HashMap::new()),lists:Mutex::new(Lists::default()),over:AtomicBool::new(false),shed:AtomicU8::new(0),
   next_start:Mutex::new(tokio::time::Instant::now()),retiring:Mutex::new(HashMap::new())}
 }
 fn lock(&self)->std::sync::MutexGuard<'_,Entries> {self.entries.lock().unwrap_or_else(|e|e.into_inner())}
 fn shed(&self)->u8 {self.shed.load(Ordering::Relaxed)}
 fn over(&self)->bool {self.over.load(Ordering::Relaxed)}

 fn delay(&self,immediate:bool)->Duration {
  if immediate {return Duration::ZERO}
  let mut next=self.next_start.lock().unwrap_or_else(|e|e.into_inner());
  let now=tokio::time::Instant::now();
  let at=(*next).max(now)+START_GAP;
  *next=at;
  at-now
 }

 fn start(&self,entries:&mut Entries,base:&str,now:i64,immediate:bool,tag:impl FnOnce(&mut Entry)) {
  let (stop,rx)=watch::channel(false);
  let (shared,thresholds)=watch::channel(Thresholds::default());
  let priority=Arc::new(AtomicU8::new(Layer::Hot as u8));
  let after=self.retiring.lock().unwrap_or_else(|e|e.into_inner()).remove(base);
  let task=tokio::spawn(track(self.pool.clone(),base.to_string(),shared,rx,priority.clone(),self.delay(immediate),after));
  let mut e=Entry{major:false,fixed:false,alt_until:0,hot_until:0,hot_seen:0,requested:0,priority,stop,thresholds,task};
  tag(&mut e);
  if let Some(layer)=e.layer(now,self.shed()) {e.priority.store(layer as u8,Ordering::Relaxed);}
  entries.insert(base.to_string(),e);
 }

 /// 停掉一只：发停止信号，任务交给 `retiring` 收尾。原来停了就不管：同一只紧接着又被要（踢出按需后马上有人看、
 /// 掉出热点又进按需），新任务读回的「挂着的单」里有旧任务正要写成失联结束的——旧的结束一落库，
 /// 新任务手里那几条再写都被 `WHERE end_ms IS NULL` 挡掉，墙还在、历史里却断在停的那一刻。
 fn stop(&self,entries:&mut Entries,base:&str,why:&str) {
  let Some(e)=entries.remove(base) else {return};
  let _=e.stop.send(true);
  tracing::info!("Orderflow history: {base} {why}");
  let mut retiring=self.retiring.lock().unwrap_or_else(|e|e.into_inner());
  retiring.retain(|_,task|!task.is_finished());
  retiring.insert(base.to_string(),e.task);
 }

 /// 满了就踢按需 / 热点里最久没人要的那只（主币、固定、山寨不踢）。踢不动返回 false。
 fn make_room(&self,entries:&mut Entries,now:i64)->bool {
  if entries.len()<MAX_BASES {return true}
  let victim=entries.iter().filter(|(_,e)|e.evictable(now)).min_by_key(|(b,e)|(e.wanted_at(),(*b).clone())).map(|(b,_)|b.clone());
  let Some(victim)=victim else {return false};
  self.stop(entries,&victim,"evicted for room");
  true
 }

 /// 有人要这只：记下时刻，没在跟就开始跟（按需层）。回此刻的门槛（还没算出来是全空）。
 fn request(&self,base:&str,now:i64)->Thresholds {
  let mut entries=self.lock();
  let shed=self.shed();
  if let Some(e)=entries.get_mut(base) {
   e.requested=now;
   if let Some(layer)=e.layer(now,shed) {e.priority.store(layer as u8,Ordering::Relaxed);}
   return *e.thresholds.borrow()
  }
  if self.over() {tracing::info!("Orderflow history: {base} requested but the resource gate is over, not tracking");return Thresholds::default()}
  let demand:Vec<(i64,String)>=entries.iter().filter(|(_,e)|e.only_on_demand(now)).map(|(b,e)|(e.requested,b.clone())).collect();
  if demand.len()>=MAX_ON_DEMAND && let Some((_,victim))=demand.into_iter().min() {self.stop(&mut entries,&victim,"evicted from on-demand for a newer request");}
  if self.make_room(&mut entries,now) {self.start(&mut entries,base,now,true,|e|e.requested=now);}
  Thresholds::default()
 }

 fn tracked(&self)->Vec<String> {self.lock().keys().cloned().collect()}
 fn is_tracked(&self,base:&str)->bool {self.lock().contains_key(base)}

 /// 不该再跟的停掉、先后重排、热点层（含掉榜还在跟的）超过 30 只就停掉最早掉榜的。
 fn settle(&self,entries:&mut Entries,now:i64) {
  let shed=self.shed();
  let gone:Vec<String>=entries.iter().filter(|(_,e)|e.layer(now,shed).is_none()).map(|(b,_)|b.clone()).collect();
  for base in gone {self.stop(entries,&base,"no longer wanted, stopped");}
  let mut tails:Vec<(i64,String)>=entries.iter().filter(|(_,e)|e.only_hot(now)&&e.hot_until!=LISTED).map(|(b,e)|(e.hot_seen,b.clone())).collect();
  let hot=entries.values().filter(|e|e.only_hot(now)).count();
  if hot>layers::MAX_HOT {
   tails.sort();
   for (_,base) in tails.into_iter().take(hot-layers::MAX_HOT) {self.stop(entries,&base,"dropped off the hot list, cap reached");}
  }
  for e in entries.values() {if let Some(layer)=e.layer(now,shed) {e.priority.store(layer as u8,Ordering::Relaxed);}}
 }

 /// 套一层的名单：在榜的打上标记（没在跟就起），不在榜的去掉标记（山寨 / 热点改成再跟 24 小时）。
 fn apply(&self,layer:Layer,list:&[String],now:i64) {
  {
   let mut lists=self.lists.lock().unwrap_or_else(|e|e.into_inner());
   match layer {Layer::Fixed=>lists.fixed=list.to_vec(),Layer::Alt=>lists.alts=list.to_vec(),Layer::Hot=>lists.hot=list.to_vec(),_=>{}}
  }
  let set:HashSet<&str>=list.iter().map(String::as_str).collect();
  let mut entries=self.lock();
  for (base,e) in entries.iter_mut() {
   let on=set.contains(base.as_str());
   match layer {
    Layer::Fixed=>e.fixed=on,
    Layer::Alt=>{if on {e.alt_until=LISTED} else if e.alt_until==LISTED {e.alt_until=now+LINGER_MS}},
    Layer::Hot=>{if on {e.hot_until=LISTED;e.hot_seen=now} else if e.hot_until==LISTED {e.hot_until=now+LINGER_MS}},
    _=>{},
   }
  }
  let shed=self.shed();
  let shed_here=match layer {Layer::Fixed=>shed>=3,Layer::Alt=>shed>=2,Layer::Hot=>shed>=1,_=>false};
  let (mut started,mut refused)=(0,0);
  for base in list {
   if entries.contains_key(base) {continue}
   if shed_here||self.over()||!self.make_room(&mut entries,now) {refused+=1;continue}
   self.start(&mut entries,base,now,false,|e|match layer {
    Layer::Fixed=>e.fixed=true,
    Layer::Alt=>e.alt_until=LISTED,
    Layer::Hot=>{e.hot_until=LISTED;e.hot_seen=now},
    _=>{},
   });
   started+=1;
  }
  self.settle(&mut entries,now);
  tracing::info!("Orderflow history: {} layer {} bases ({started} started{}): {}",layer.label(),list.len(),
   if refused>0 {format!(", {refused} held back by the resource gate / cap")} else {String::new()},list.join(" "));
 }

 /// 热点要排除的：已经因为别的理由在跟的，加上固定与山寨名单。
 fn not_hot(&self,now:i64)->HashSet<String> {
  let mut out:HashSet<String>=self.lock().iter().filter(|(_,e)|e.major||e.fixed||e.alt_until>now||e.on_demand(now)).map(|(b,_)|b.clone()).collect();
  let lists=self.lists.lock().unwrap_or_else(|e|e.into_inner());
  out.extend(lists.fixed.iter().cloned());
  out.extend(lists.alts.iter().cloned());
  out.extend(layers::MAJORS.iter().map(|m|m.to_string()));
  out
 }

 /// 每十分钟：不该再跟的停掉；意外结束的任务重起（标记不变）。
 fn sweep(&self,now:i64) {
  let mut entries=self.lock();
  self.settle(&mut entries,now);
  let dead:Vec<String>=entries.iter().filter(|(_,e)|e.task.is_finished()).map(|(b,_)|b.clone()).collect();
  for base in dead {
   let Some(old)=entries.remove(&base) else {continue};
   tracing::warn!("Orderflow history: {base} tracker ended unexpectedly, restarting");
   self.start(&mut entries,&base,now,false,|e|{e.major=old.major;e.fixed=old.fixed;e.alt_until=old.alt_until;e.hot_until=old.hot_until;e.hot_seen=old.hot_seen;e.requested=old.requested;});
  }
 }

 /// 资源闸门（每分钟）：超了就不再新增，并卸一层；连续 10 分钟不超放回一层、重新套名单。
 fn gate(&self,now:i64,clear:&mut u32) {
  let load=resources::last();
  let over=load.over();
  self.over.store(over,Ordering::Relaxed);
  let shed=self.shed();
  if over {
   *clear=0;
   if shed<3 {
    self.shed.store(shed+1,Ordering::Relaxed);
    tracing::warn!("Orderflow history: resource gate over ({}), shedding {}",load.describe(),shed_label(shed+1));
    let mut entries=self.lock();
    self.settle(&mut entries,now);
   } else {
    tracing::warn!("Orderflow history: resource gate still over ({}) with only majors and on-demand left",load.describe());
   }
  } else if shed>0 {
   *clear+=1;
   if *clear>=SHED_RECOVER_MINUTES {
    *clear=0;
    self.shed.store(shed-1,Ordering::Relaxed);
    tracing::info!("Orderflow history: resource gate clear for {SHED_RECOVER_MINUTES} minutes ({}), now shedding {}",load.describe(),shed_label(shed-1));
    let lists=std::mem::take(&mut *self.lists.lock().unwrap_or_else(|e|e.into_inner()));
    self.apply(Layer::Fixed,&lists.fixed,now);
    self.apply(Layer::Alt,&lists.alts,now);
    self.apply(Layer::Hot,&lists.hot,now);
   }
  }
 }

 /// 一行现状：各层多少只、连接数、进程负载、卸层。
 fn status(&self,now:i64)->String {
  let shed=self.shed();
  let entries=self.lock();
  let mut counts:HashMap<Layer,usize>=HashMap::new();
  for e in entries.values() {if let Some(l)=e.layer(now,shed) {*counts.entry(l).or_default()+=1;}}
  let parts:Vec<String>=[Layer::Major,Layer::OnDemand,Layer::Fixed,Layer::Alt,Layer::Hot].iter().map(|l|format!("{} {}",l.label(),counts.get(l).copied().unwrap_or(0))).collect();
  format!("tracking {} ({}), {} connections, {}, shedding {}",entries.len(),parts.join(", "),hub::connections(),resources::last().describe(),shed_label(shed))
 }
}

/// 热点那一路要取 150 次持仓历史（约 45 秒），单独起任务，不挡着资源采样与闸门。
async fn recompute_hot(registry:Arc<Registry>,running:crate::supervise::Running) {
 // 守卫握到函数结束：以前是末尾一句 `store(false)`，中途 panic 就跳过了，热点层从此再也不重算。
 let _running=running;
 let result=async {
  let info=crate::market_meta::exchange_info().await.ok()?;
  let tickers=layers::ticker_map(&*layers::tickers().await.ok()?);
  let exclude=registry.not_hot(now_ms());
  let candidates=layers::oi_candidates(&info,&tickers,&exclude);
  let oi=layers::oi_changes(&candidates).await;
  let exclude=registry.not_hot(now_ms());
  Some((layers::pick_hot(&info,&tickers,&oi,&exclude),oi.len(),candidates.len()))
 }.await;
 match result {
  Some((hot,got,asked))=>{
   tracing::info!("Orderflow history: hot signals ready (open interest for {got}/{asked} contracts)");
   registry.apply(Layer::Hot,&hot,now_ms());
  },
  None=>tracing::warn!("Orderflow history: hot layer not recomputed (contract list or tickers unavailable), keeping the last one"),
 }
}

/// 层的循环：每 15 秒采一次资源；每分钟过一遍闸门，到点重算固定（10 分钟对一次合约表）、山寨（UTC 0 点）、
/// 热点（每小时）。
async fn run_layers(registry:Arc<Registry>,enabled:Enabled) {
 let mut sample=tokio::time::interval(SAMPLE);
 sample.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
 let mut tick=tokio::time::interval(LAYER_TICK);
 tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
 // 0 而不是 i64::MIN：`now - i64::MIN` 会溢出（Release 下绕成负数，层永远不起）。
 let (mut fixed_at,mut hot_at,mut alts_day)=(0i64,0i64,None::<i64>);
 let mut clear=0u32;
 let mut missing_named:Option<Vec<String>>=None;
 let hot_running=Arc::new(AtomicBool::new(false));
 let started=now_ms();
 let mut status_at=0i64;
 loop {
  tokio::select! {
   _=sample.tick()=>{resources::sample();},
   _=tick.tick()=>{
    let now=now_ms();
    registry.gate(now,&mut clear);
    let info=if enabled.fixed||enabled.alts||enabled.hot {
     match crate::market_meta::exchange_info().await {
      Ok(info)=>Some(info),
      Err(_)=>{tracing::warn!("Orderflow history: contract list unavailable, layers retried next minute");None},
     }
    } else {None};
    if let Some(info)=info {
     if enabled.fixed&&now-fixed_at>=FIXED_EVERY_MS {
      let (found,missing)=layers::fixed_bases(&info);
      if missing_named.as_ref()!=Some(&missing) {
       tracing::info!("Orderflow history: fixed layer {} of {} names listed on Binance; not listed, skipped: {}",found.len(),found.len()+missing.len(),
        if missing.is_empty() {"none".to_string()} else {missing.join(" ")});
       missing_named=Some(missing);
      }
      registry.apply(Layer::Fixed,&found,now);
      fixed_at=now;
     }
     let day=now.div_euclid(store::DAY_MS);
     if enabled.alts&&alts_day!=Some(day) {
      match layers::tickers().await {
       Ok(body)=>{
        let tickers=layers::ticker_map(&body);
        let fixed:HashSet<String>=layers::fixed_bases(&info).0.into_iter().collect();
        let alts=layers::pick_alts(&info,&tickers,&fixed);
        registry.apply(Layer::Alt,&alts,now);
        alts_day=Some(day);
       },
       Err(_)=>tracing::warn!("Orderflow history: tickers unavailable, alts layer retried next minute"),
      }
     }
     if enabled.hot&&now-hot_at>=HOT_EVERY_MS && let Some(claim)=crate::supervise::Running::claim(&hot_running) {
      hot_at=now;
      crate::supervise::spawn_logged("orderflow-hot",crate::supervise::Life::Once,recompute_hot(registry.clone(),claim));
     }
    }
    // 起来的头十分钟每分钟一行现状，之后十分钟一行。
    let every=if now-started<10*60_000 {60_000} else {10*60_000};
    if now-status_at>=every-1_000 {status_at=now;tracing::info!("Orderflow history: {}",registry.status(now));}
   },
  }
 }
}

/// 进程起来时接着跟的按需币，带着库里记的最后一次要的时刻（不是现在）：原来一律记成现在，每重启一次就把
/// 闲置的 24 小时从头算，23 小时前看过一眼的币又被多跟一整天，发版勤的时候一直跟下去、占着按需层名额。
fn resumable<'a>(recent:&'a [(String,i64)],admit:&HashSet<&str>,now:i64)->Vec<(&'a str,i64)> {
 recent.iter().filter(|(b,r)|admit.contains(b.as_str())&&now-r<IDLE_MS).take(MAX_ON_DEMAND).map(|(b,r)|(b.as_str(),*r)).collect()
}

/// 起跟踪：主币、最近 24 小时有人要过的（最多 20 只），再按 `KANPAN_ORDERFLOW_LAYERS` 起固定 / 山寨 / 热点；
/// 之后每十分钟清一遍、每小时滚动清理。
pub fn spawn(pool:PgPool)->JoinHandle<()> {
 tokio::spawn(async move {
  let registry=REGISTRY.get_or_init(||Arc::new(Registry::new(pool.clone()))).clone();
  let enabled=Enabled::from_env();
  tracing::info!("Orderflow history: layers {} (up to {MAX_BASES} bases)",enabled.describe());
  let now=now_ms();
  let recent=store::recent_bases(&pool,now).await.unwrap_or_else(|e|{tracing::warn!("Orderflow history: recent bases unreadable: {e}");Vec::new()});
  {
   let mut entries=registry.lock();
   for base in ALWAYS {registry.start(&mut entries,base,now,false,|e|e.major=true);}
  }
  // 已经不挂了的（或者修复之前打错的代号被记进来的）不再接着跟。
  let mut admit=HashSet::new();
  for (base,_) in recent.iter().filter(|(b,_)|!ALWAYS.contains(&b.as_str())&&instruments::valid_base(b)) {
   if admitted(false,instruments::listed(base).await) {admit.insert(base.as_str());}
  }
  {
   let mut entries=registry.lock();
   for (base,requested) in resumable(&recent,&admit,now) {
    registry.start(&mut entries,base,now,false,|e|e.requested=requested);
   }
  }
  // 层的循环没有自己的状态要保（时刻都从 0 重算，第一次 tick 就把各层重新对一遍），死了原地再起。
  {let registry=registry.clone();crate::supervise::spawn_restarting("orderflow-layers",move ||run_layers(registry.clone(),enabled));}
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

/// 要不要为这只 base 起跟踪、记进库：已经在跟的照旧；合约表判得了而三家都没挂的不起；判不了（表还没拉到）的放行。
fn admitted(tracked:bool,listed:Option<bool>)->bool {tracked||listed!=Some(false)}

/// 校验并补齐区间：`to` 缺省此刻，`from` 缺省 `to` 前 24 小时，最长 3 天。
fn window(from:Option<i64>,to:Option<i64>,now:i64)->std::result::Result<(i64,i64),&'static str> {
 let to=to.unwrap_or(now);
 // to 是请求带来的任意 i64：i64::MIN 附近直接减会溢出（调试构建里是 panic，发布构建靠回绕碰巧判成 invalid_range）。
 let from=from.unwrap_or(to.saturating_sub(DEFAULT_SPAN_MS));
 if from<0||to<0||from>to {return Err("invalid_range")}
 if to-from>MAX_SPAN_MS {return Err("range_too_long")}
 Ok((from,to))
}

async fn history(State(s):State<AppState>,Params(q):Params<HistoryQuery>)->Result<Response> {
 if !instruments::valid_base(&q.base) {return Err(ApiError::bad("invalid_base"))}
 let now=now_ms();
 let (from,to)=window(q.from,q.to,now).map_err(ApiError::bad)?;
 // 三家都没挂的 base（打错的、早下架的）：不起跟踪、不记进 orderflow_bases。原来照样起一只按需跟踪，
 // 占着按需层的名额（满了还会把真有人在看的踢掉），prepare 每 30 秒空转一次、一跟 24 小时，重启后还会被接着跟。
 let tracked=REGISTRY.get().is_some_and(|r|r.is_tracked(&q.base));
 let admit=admitted(tracked,instruments::listed(&q.base).await);
 let (thresholds,tracked_since)=if admit {
  let thresholds=REGISTRY.get().map(|r|r.request(&q.base,now)).unwrap_or_default();
  let (since,alive)=store::touch(&s.pool,&q.base,now).await?;
  (thresholds,store::continuous_since(since,alive,now).max(now-MAX_SPAN_MS))
 } else {(Thresholds::default(),now)};
 let orders=store::range(&s.pool,&q.base,from,to).await?;
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

 #[test] fn live_rows_are_rewritten_only_when_they_move_or_age() {
  use model::Status;
  let order=|notional:f64,filled:f64|BigOrder{venue_id:"binance:usdtPerp:BTCUSDT".into(),exchange:"币安".into(),product:"usdtPerp".into(),side:book::Side::Bid,
   bucket:599,price:59_950.0,first_seen_ms:1_000,end_ms:None,status:Status::Live,initial_notional:6e6,notional,filled_notional:filled,threshold:5e6,vanished_notional:None};
  let mut written=HashMap::new();
  assert_eq!(changed_live(vec![(order(6e6,0.0),0)],&mut written,0).len(),1,"新出现的写");
  assert!(changed_live(vec![(order(6.03e6,0.0),15_000)],&mut written,15_000).is_empty(),"动了不到 1% 不写");
  assert_eq!(changed_live(vec![(order(6.2e6,0.0),30_000)],&mut written,30_000).len(),1,"量动了写");
  assert_eq!(changed_live(vec![(order(6.2e6,1e5),45_000)],&mut written,45_000).len(),1,"成交动了写");
  assert!(changed_live(vec![(order(6.2e6,1e5),60_000)],&mut written,60_000).is_empty());
  assert_eq!(changed_live(vec![(order(6.2e6,1e5),105_000)],&mut written,105_000).len(),1,"一分钟没写过：刷新 seen_ms");
  assert!(LIVE_REWRITE_MS<model::STALE_MS);
  changed_live(Vec::new(),&mut written,120_000);
  assert!(written.is_empty(),"不再挂着的不留");
 }

 #[test] fn pending_writes_keep_the_latest_row_and_never_reopen_an_end() {
  use model::Status;
  let order=|bucket:i64,notional:f64,end:Option<i64>|BigOrder{venue_id:"binance:usdtPerp:BTCUSDT".into(),exchange:"币安".into(),product:"usdtPerp".into(),
   side:book::Side::Bid,bucket,price:59_950.0,first_seen_ms:1_000,end_ms:end,status:if end.is_some() {Status::Cancelled} else {Status::Live},
   initial_notional:6e6,notional,filled_notional:0.0,threshold:5e6,vanished_notional:None};
  let mut p=Pending::default();
  p.add(Write{step:100.0,rows:vec![(order(599,6e6,None),10_000),(order(598,6e6,None),10_000)]});
  // 第一批写失败留着；这期间 599 结束了、598 量变了。
  p.add(Write{step:100.0,rows:vec![(order(599,6e6,Some(20_000)),20_000)]});
  p.add(Write{step:100.0,rows:vec![(order(598,7e6,None),25_000)]});
  // 晚到的一份「599 还挂着」不能把结束盖回去。
  p.add(Write{step:100.0,rows:vec![(order(599,6e6,None),26_000)]});
  assert_eq!(p.rows.len(),2,"一单一份");
  let get=|b:i64|p.rows.values().find(|(_,o,_)|o.bucket==b).unwrap();
  assert_eq!(get(599).1.end_ms,Some(20_000));
  assert_eq!((get(598).1.notional,get(598).2),(7e6,25_000));
  // 步长不同分两批，每批最多 500 行。
  p.add(Write{step:50.0,rows:(0..1_200).map(|b|(order(10_000+b,6e6,None),30_000)).collect()});
  let batches=p.batches();
  assert!(batches.iter().all(|(_,k)|k.len()<=500));
  assert_eq!(batches.iter().filter(|(s,_)|*s==100.0).map(|(_,k)|k.len()).sum::<usize>(),2);
  assert_eq!(batches.iter().filter(|(s,_)|*s==50.0).map(|(_,k)|k.len()).sum::<usize>(),1_200);
 }

 #[test] fn pending_writes_shed_live_rows_before_ends() {
  use model::Status;
  let order=|bucket:i64,end:Option<i64>|BigOrder{venue_id:"a".into(),exchange:"币安".into(),product:"spot".into(),side:book::Side::Ask,bucket,price:1.0,
   first_seen_ms:0,end_ms:end,status:if end.is_some() {Status::Lost} else {Status::Live},initial_notional:1.0,notional:1.0,filled_notional:0.0,threshold:1.0,vanished_notional:None};
  let mut p=Pending::default();
  p.add(Write{step:1.0,rows:(0..10).map(|b|(order(b,None),0)).collect()});
  p.add(Write{step:1.0,rows:(0..PENDING_CAP as i64).map(|b|(order(100+b,Some(b)),b)).collect()});
  assert_eq!(p.rows.len(),PENDING_CAP,"挂着的先丢（一分钟内会整行重写）");
  assert!(p.rows.values().all(|(_,o,_)|o.end_ms.is_some()));
  p.add(Write{step:1.0,rows:vec![(order(-1,Some(1_000_000)),1_000_000)]});
  assert_eq!(p.rows.len(),PENDING_CAP);
  assert!(!p.rows.values().any(|(_,o,_)|o.end_ms==Some(0)),"还超就丢结束得最早的");
 }

 #[test] fn coin_or_not_is_never_guessed() {
  let perp=Venue{exchange:Exchange::Binance,product:Product::UsdtPerp,instrument:"NVDAUSDT".into(),margin:None,
   notional:instruments::Notional::Linear{multiplier:1.0},tick:0.01,expiry_ms:None,price_scale:None,listed_base:"NVDA".into()};
  let info=serde_json::json!({"symbols":[{"symbol":"NVDAUSDT","underlyingType":"EQUITY"},{"symbol":"DOGEUSDT","underlyingType":"COIN"}]});
  assert_eq!(crypto_kind("NVDA",Some(&perp),None,Some(&info)),Some(false));
  assert_eq!(crypto_kind("NVDA",Some(&perp),None,None),None,"合约表拿不到：不知道，不按币算");
  assert_eq!(crypto_kind("NVDA",Some(&perp),Some(false),None),Some(false),"起跟时判过的，重算门槛时沿用");
  assert_eq!(crypto_kind("BTC",Some(&perp),None,None),Some(true),"主币不用查");
  assert_eq!(crypto_kind("FOO",None,None,None),Some(true),"币安没有这只永续：按币算");
  let doge=Venue{instrument:"DOGEUSDT".into(),listed_base:"DOGE".into(),..perp.clone()};
  assert_eq!(crypto_kind("DOGE",Some(&doge),None,Some(&info)),Some(true));
 }

 #[test] fn snapshot_retries_back_off_to_five_minutes() {
  assert_eq!((1..=9).map(snapshot_backoff).collect::<Vec<_>>(),vec![2_000,4_000,8_000,16_000,32_000,64_000,128_000,256_000,300_000]);
  assert_eq!(snapshot_backoff(u32::MAX),SNAPSHOT_RETRY_MAX_MS);
  // 一直拿不到的一本：一小时里只占十几份配额，不是 1800 份。
  let (mut t,mut n,mut f)=(0i64,0,1u32);
  while t<3_600_000 {t+=snapshot_backoff(f);f+=1;n+=1;}
  assert!(n<20,"{n}");
 }

 #[test] fn calibration_waits_for_every_book_to_connect_and_its_snapshot() {
  let mut c=Calibration{needed:true,value:None,day:None,partial:false,since:0,subscribed:0,restored:None};
  // OKX 一本秒就绪，币安那本还在攒连接 / 排快照：不标。
  assert!(!c.due(5_000,0,2,1,true));
  assert!(!c.due(60_000,0,2,1,true),"还在等就一直往后推");
  // 币安那本连上、快照也拿到了但还没接上序号：从这一刻起 8 秒。
  assert!(!c.due(60_000+7_999,0,2,1,false));
  assert!(c.due(60_000+8_000,0,2,1,false));
  // 两本都就绪：立刻标。
  let mut c=Calibration{needed:true,value:None,day:None,partial:false,since:0,subscribed:0,restored:None};
  assert!(c.due(3_000,0,2,2,true));
  // 等满 10 分钟还有簿在等：用就绪的那本标。
  let mut c=Calibration{needed:true,value:None,day:None,partial:false,since:0,subscribed:0,restored:None};
  assert!(!c.due(CALIBRATION_CAP_MS-1,0,2,1,true));
  assert!(c.due(CALIBRATION_CAP_MS+model::CALIBRATION_WAIT_MS,0,2,1,true));
  // 没有簿：直接标（回退 200 万）。
  let mut c=Calibration{needed:true,value:None,day:None,partial:false,since:0,subscribed:0,restored:None};
  assert!(c.due(0,0,0,0,false));
 }

 #[test] fn calibration_upgrades_once_and_renews_daily() {
  let day=86_400_000;
  let mut c=Calibration{needed:true,value:Some(50_000.0),day:Some(day),partial:true,since:0,subscribed:0,restored:None};
  assert!(!c.due(1,day,2,1,false),"同一天、还是一部分簿：不补标");
  assert!(c.due(1,day,2,2,false),"全就绪了：补标一次");
  c.partial=false;
  assert!(!c.due(1,day,2,2,false));
  assert!(c.due(1,2*day,2,2,false),"跨 UTC 日重标");
  assert!(!c.due(1,2*day,2,0,false),"一本都没就绪不重标");
  let mut crypto=Calibration{needed:false,value:None,day:None,partial:false,since:0,subscribed:0,restored:None};
  assert!(!crypto.due(0,0,0,0,false),"币不标");
 }

 #[tokio::test] async fn a_base_started_again_waits_for_its_previous_tracker() {
  let r=Registry::new(PgPool::connect_lazy("postgres://nobody@127.0.0.1:1/none").unwrap());
  let (release,wait)=tokio::sync::oneshot::channel::<()>();
  let previous=tokio::spawn(async move {let _=wait.await;});
  r.retiring.lock().unwrap().insert("ZZT".into(),previous);
  {let mut entries=r.lock();r.start(&mut entries,"ZZT",0,true,|e|e.requested=1);}
  assert!(r.retiring.lock().unwrap().is_empty(),"上一任交给了新任务");
  tokio::time::sleep(Duration::from_millis(50)).await;
  assert!(!r.lock()["ZZT"].task.is_finished(),"上一任没收完尾：新任务在等，还没去读回挂着的单");
  // 停掉：任务进 retiring 收尾；等的时候被停就直接结束。
  {let mut entries=r.lock();r.stop(&mut entries,"ZZT","stopped by the test");}
  assert!(!r.lock().contains_key("ZZT"));
  let task=r.retiring.lock().unwrap().remove("ZZT").expect("停掉的任务留给下一任等");
  tokio::time::timeout(Duration::from_secs(1),task).await.unwrap().unwrap();
  drop(release);
 }

 #[tokio::test] async fn the_writer_keeps_taking_rows_while_it_waits_for_a_connection_slot() {
  use model::Status;
  let order=|bucket:i64|BigOrder{venue_id:"binance:usdtPerp:ZZWUSDT".into(),exchange:"币安".into(),product:"usdtPerp".into(),
   side:book::Side::Bid,bucket,price:1.0,first_seen_ms:1_000,end_ms:None,status:Status::Live,
   initial_notional:6e6,notional:6e6,filled_notional:0.0,threshold:5e6,vanished_notional:None};
  // 三条写库连接全被别的币占着。
  let held=WRITE_SLOTS.acquire_many(3).await.unwrap();
  let (tx,rx)=mpsc::channel::<Write>(2);
  let task=tokio::spawn(writer(PgPool::connect_lazy("postgres://nobody@127.0.0.1:1/none").unwrap(),"ZZW".into(),rx));
  // 远超通道容量的一串：写库任务在排连接时也要接着收，跟踪那边的 send 不能卡住。
  let sent=tokio::time::timeout(Duration::from_secs(2),async {
   for b in 0..50 {tx.send(Write{step:1.0,rows:vec![(order(b),10_000)]}).await.unwrap();}
  }).await;
  assert!(sent.is_ok(),"排连接的时候通道没人收，跟踪任务卡在 send 上");
  drop(held);
  task.abort();
 }

 #[test] fn a_restart_does_not_reset_the_idle_clock() {
  let now=10*store::DAY_MS;
  let hour=3_600_000;
  let recent=vec![("AAA".to_string(),now-23*hour),("BBB".to_string(),now-hour),("CCC".to_string(),now-2*hour)];
  let admit:HashSet<&str>=["AAA","BBB"].into_iter().collect();
  let got=resumable(&recent,&admit,now);
  assert_eq!(got,vec![("AAA",now-23*hour),("BBB",now-hour)],"库里记的时刻原样带回；没放行的不接着跟");
  // 23 小时前要过的：重启后一小时多一点就到 24 小时闲置，照常停，不因为重启再多跟一天。
  assert!(now+hour+1-got[0].1>=IDLE_MS);
  let full:Vec<(String,i64)>=(0..30).map(|i|(format!("B{i}"),now-i)).collect();
  let admit_all:HashSet<&str>=full.iter().map(|(b,_)|b.as_str()).collect();
  assert_eq!(resumable(&full,&admit_all,now).len(),MAX_ON_DEMAND);
 }

 #[test] fn unlisted_bases_are_not_tracked() {
  assert!(!admitted(false,Some(false)),"三家都没挂：不跟");
  assert!(admitted(false,Some(true)));
  assert!(admitted(false,None),"表还没拉到：判不了就放行");
  assert!(admitted(true,Some(false)),"已经在跟的（刚下架）照旧");
 }

 #[test] fn window_defaults_and_limits() {
  let now=100*store::DAY_MS;
  assert_eq!(window(None,None,now),Ok((now-store::DAY_MS,now)));
  assert_eq!(window(Some(5),Some(9),now),Ok((5,9)));
  assert_eq!(window(None,Some(now-store::DAY_MS),now),Ok((now-2*store::DAY_MS,now-store::DAY_MS)));
  assert_eq!(window(Some(now-3*store::DAY_MS),None,now),Ok((now-3*store::DAY_MS,now)));
  assert_eq!(window(Some(now-3*store::DAY_MS-1),None,now),Err("range_too_long"));
  assert_eq!(window(Some(9),Some(5),now),Err("invalid_range"));
  assert_eq!(window(Some(-1),Some(5),now),Err("invalid_range"));
  assert_eq!(window(None,Some(i64::MIN),now),Err("invalid_range"),"极端的 to 不溢出");
  assert_eq!(window(Some(0),Some(i64::MAX),now),Err("range_too_long"));
  assert_eq!(window(Some(i64::MAX),None,now),Err("invalid_range"));
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
