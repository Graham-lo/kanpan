//! 要点引擎（手机首页「异动」与行情页上滑「盘口要点」，2026-10-10，原型 §11 / §12）。
//!
//! 跑在 serve 进程里、和订单流跟踪同一套跟踪集合：每分钟对每只在跟的 base 折进这一分钟的新数据、算一份答复放内存，
//! 接口再加 20 秒缓存。输入全是已经在收的：
//! * 全部成交（足迹每分钟的各价位主动买卖额，合约 + 现货、全部家）→ 净主动、成交额、账本的吃单；
//! * 挂单墙（跟踪器每分钟交一份挂着的，结束的从写库那一步交）→ 账本的墙、墙事件；
//! * 爆仓推送（`liq.rs` 收到的每一笔）→ 爆仓序列、账本的爆仓；
//! * 参考永续的 1 分钟线与现货最新价（跟踪器的成交里顺手记）→ 涨跌、触及、已破、区间、现货溢价；
//! * 持仓（币安 5 分钟 / 1 小时历史，每 5 分钟取一次）与资金费率（全市场一次）。
//!
//! 门槛全按这只自己的历史分位（近 3 天 P95 / 近 30 天 P60 / P90 / P10），30 天的样本从现在开始攒、起步时用库里 3 天
//! 与 REST 历史补；不够 3 天的分位为 null，不挡功能。接口只发稳定的枚举键（`w`、`t`、`wallState`、`combo`、`refs`、
//! `cat`、`kind`），中文由客户端按 terms.json 的 `highlights` 一节拼。
//!
//! 落盘：账本、样本、小时线、持仓小时序列每 30 分钟进 `orderflow_highlights`（一只一行，jsonb），连同「账本记到哪」；
//! 重启后先读回，再用库里的足迹 / 爆仓分钟 / 大单把落盘之后到这一任开始收之前那一段补上。7 天没更新的行删掉。
mod board;
mod events;
mod fetch;
mod ledger;
mod market;
mod moves;
mod range;
mod state;
mod stats;

use super::{ALWAYS,Answers,REGISTRY,accepts_gzip,footprint,instruments,now_ms,packed,want};
use super::book::Side;
use super::minutes::closed;
use super::model::{BigOrder,Status};
use crate::AppState;
use crate::error::{ApiError,Params,Result};
use axum::extract::State as Axum;
use axum::response::Response;
use events::Ended;
use ledger::Live;
use serde::Deserialize;
use serde_json::{Value,json};
use sqlx::{PgPool,Row};
use state::{Bar,Pending,Snap,State};
use std::collections::{HashMap,HashSet};
use std::sync::atomic::{AtomicBool,Ordering};
use std::sync::{Arc,LazyLock,Mutex,RwLock};
use std::time::Duration;
use tokio::sync::mpsc;

pub(super) const PATH:&str="/v1/market/orderflow/highlights";
pub(super) const BOARD_PATH:&str=board::PATH;
pub(super) const MARKET_BOARD_PATH:&str=market::PATH;
pub(super) use market::market_board;
pub(super) const MOVES_PATH:&str=moves::PATH;
pub(super) use moves::market_moves;
const TTL:Duration=Duration::from_secs(20);
const CACHE_CONTROL:&str="public, max-age=20";
const M:i64=60_000;
/// 每只 30 分钟落一次盘（按 base 错开）。
const PERSIST_EVERY:i64=30;
/// 7 天没更新的落盘行删掉。
const FORGET_MS:i64=7*stats::DAY_MS;
/// 每分钟的第几秒算（足迹与爆仓分钟要过完 + 3 秒宽限才交出来）。
const TICK_OFFSET_MS:i64=12_000;

static ON:AtomicBool=AtomicBool::new(false);
static INBOX:LazyLock<Mutex<HashMap<String,Pending>>>=LazyLock::new(||Mutex::new(HashMap::new()));
static SNAPS:LazyLock<RwLock<HashMap<String,Arc<Snap>>>>=LazyLock::new(||RwLock::new(HashMap::new()));
/// 最近一次全市场费率（按 base）。
static FUNDING:LazyLock<Mutex<HashMap<String,f64>>>=LazyLock::new(||Mutex::new(HashMap::new()));
static ANSWERS:LazyLock<Answers<(String,bool)>>=LazyLock::new(||Answers::new(TTL));
static BOARD_ANSWERS:LazyLock<Answers<(String,bool)>>=LazyLock::new(||Answers::new(TTL));
/// 引擎收「起步补齐」的口子：接口那条快路补完也从这里交给引擎（引擎重起时换一个）。
static INJECT:LazyLock<Mutex<Option<mpsc::Sender<Done>>>>=LazyLock::new(||Mutex::new(None));
static POOL:std::sync::OnceLock<PgPool>=std::sync::OnceLock::new();
/// 正在走快路补齐的（同一只同时只补一份；引擎看到就不再排自己的起步）。
static QUICK:LazyLock<Mutex<HashMap<String,Arc<Quick>>>>=LazyLock::new(||Mutex::new(HashMap::new()));
/// 打开一只没算好的品种，接口最多等多久。
const QUICK_WAIT:Duration=Duration::from_secs(2);

/// 一份快路补齐：各路 REST 与库谁先回来谁先写进 `boot`；`done` 全回来了为 true。
struct Quick {started:i64,restored:Mutex<Option<Value>>,boot:Mutex<fetch::Boot>,done:tokio::sync::watch::Sender<bool>}

fn on()->bool {ON.load(Ordering::Relaxed)}
fn push(base:&str,f:impl FnOnce(&mut Pending)) {
 if !on() {return}
 let mut inbox=INBOX.lock().unwrap_or_else(|e|e.into_inner());
 let p=inbox.entry(base.to_string()).or_default();
 f(p);
 p.cap();
}

fn snapshot(base:&str)->Option<Arc<Snap>> {SNAPS.read().unwrap_or_else(|e|e.into_inner()).get(base).cloned()}

// ------------------------------------------------------------------ 从各处收

/// 跟踪器收完的足迹分钟（写库之前顺手交一份）。
pub(super) fn footprint(base:&str,rows:&[footprint::Minute]) {
 if rows.is_empty() {return}
 push(base,|p|for m in rows {
  if !(m.step>0.0) {continue}
  let (net,vol,fills)=fetch::fold_levels(&m.levels,m.step);
  let f=p.flow.entry(m.minute_ms).or_insert((0.0,0.0));
  f.0+=net;f.1+=vol;
  p.fills.push((m.minute_ms,fills));
 });
}

/// 跟踪器写库前交出的结束的墙（失联的不算）。
pub(super) fn ended(base:&str,orders:&[BigOrder]) {
 let rows:Vec<Ended>=orders.iter().filter(|o|matches!(o.status,Status::Filled|Status::Cancelled)).map(|o|Ended{bid:o.side==Side::Bid,price:o.price,
  initial:o.initial_notional,filled:o.filled_notional,left:o.notional,cancelled:o.status==Status::Cancelled,end:o.end_ms.unwrap_or(o.first_seen_ms)}).collect();
 if !rows.is_empty() {push(base,|p|p.ended.extend(rows));}
}

/// 爆仓推送里在跟的那几只（`liq.rs` 收到就交）。
pub(super) fn liq(hits:&[super::liq::Hit]) {
 for h in hits {push(&h.base,|p|p.liq.push((h.at,h.side==super::liq::LONG,h.usd,h.price)));}
}

/// 跟踪器手里的一条「带子」：参考永续这一分钟的开高低收、现货最新价，每分钟交一根；每分钟交一份挂着的墙。
#[derive(Debug,Default)]
pub(super) struct Tape {minute:i64,done:i64,bar:Option<(u8,[f64;4])>,spot:Option<(u8,f64,i64)>,wall_minute:i64}

/// 参考永续：币安 > OKX > Bybit > Hyperliquid 的 U 本位永续。
fn perp_rank(venue:&str)->Option<u8> {
 let mut parts=venue.split(':');
 let (exchange,product)=(parts.next()?,parts.next()?);
 if product!="usdtPerp" {return None}
 match exchange {"binance"=>Some(0),"okx"=>Some(1),"bybit"=>Some(2),"hyperliquid"=>Some(3),_=>None}
}
/// 现货：币安 > Coinbase > OKX > Bybit。
fn spot_rank(venue:&str)->Option<u8> {
 let mut parts=venue.split(':');
 let (exchange,product)=(parts.next()?,parts.next()?);
 if product!="spot" {return None}
 match exchange {"binance"=>Some(0),"coinbase"=>Some(1),"okx"=>Some(2),"bybit"=>Some(3),_=>None}
}

impl Tape {
 /// 一笔成交：簿、每个币的价、交易所时刻。
 pub fn trade(&mut self,base:&str,venue:&str,price:f64,at:i64) {
  if !on()||!(price.is_finite()&&price>0.0) {return}
  let minute=at.div_euclid(M)*M;
  if let Some(r)=spot_rank(venue) {
   if self.spot.is_none_or(|(sr,_,m)|r<=sr||minute>m) {self.spot=Some((r,price,minute));}
   return;
  }
  let Some(r)=perp_rank(venue) else {return};
  if minute<=self.done {return}
  if minute>self.minute {self.flush(base);self.minute=minute;}
  if minute<self.minute {return}
  match &mut self.bar {
   Some((br,b)) if *br==r=>{b[1]=b[1].max(price);b[2]=b[2].min(price);b[3]=price;},
   Some((br,_)) if *br<r=>{},
   _=>self.bar=Some((r,[price;4])),
  }
 }
 fn flush(&mut self,base:&str) {
  let Some((_,b))=self.bar.take() else {return};
  self.done=self.minute;
  let bar=Bar{t:self.minute,o:b[0],h:b[1],l:b[2],c:b[3],spot:self.spot.map(|s|s.1)};
  push(base,|p|p.bars.push(bar));
 }
 /// 评估那一拍：这一分钟过完（含宽限）就交。
 pub fn roll(&mut self,base:&str,now:i64) {
  if on()&&self.bar.is_some()&&closed(self.minute,now) {self.flush(base);}
 }
 /// 每分钟交一份挂着的墙（标定前不调）。
 pub fn walls(&mut self,base:&str,now:i64,live:impl FnOnce()->Vec<(BigOrder,i64)>) {
  if !on() {return}
  let minute=now.div_euclid(M)*M;
  if minute==self.wall_minute {return}
  self.wall_minute=minute;
  let walls:Vec<Live>=live().into_iter().filter(|(o,_)|o.status==Status::Live).map(|(o,_)|Live{bid:o.side==Side::Bid,price:o.price,usd:o.notional,
   initial:o.initial_notional,filled:o.filled_notional,first:o.first_seen_ms}).collect();
  push(base,|p|p.walls.push((minute,walls)));
 }
}

// ------------------------------------------------------------------ 引擎

enum Job {
 Boot{base:String,live_from:i64},
 Oi{base:String,hourly:bool,price:Option<f64>},
 Funding,
 Save{base:String,payload:Value,at:i64},
 Purge,
}
enum Done {
 Boot{base:String,restored:Option<Value>,boot:Box<fetch::Boot>},
 Oi{base:String,five:Vec<(i64,f64)>,hour:Vec<(i64,f64)>,funding:Vec<(i64,f64)>},
 Funding(HashMap<String,f64>),
}

/// 起引擎（serve 起订单流时一次）。
pub(super) fn start(pool:PgPool) {
 if ON.swap(true,Ordering::SeqCst) {return}
 let _=POOL.set(pool.clone());
 let board_pool=pool.clone();
 crate::supervise::spawn_restarting("market-board",move ||market::run(board_pool.clone()));
 let moves_pool=pool.clone();
 crate::supervise::spawn_restarting("market-moves",move ||moves::run(moves_pool.clone()));
 crate::supervise::spawn_restarting("orderflow-highlights",move ||run(pool.clone()));
}

async fn run(pool:PgPool) {
 let (jobs,job_rx)=mpsc::unbounded_channel::<Job>();
 let (done_tx,mut done)=mpsc::channel::<Done>(64);
 *INJECT.lock().unwrap_or_else(|e|e.into_inner())=Some(done_tx.clone());
 let worker=tokio::spawn(worker(pool,job_rx,done_tx));
 let _abort=Abort(worker);
 let mut states:HashMap<String,State>=HashMap::new();
 let mut booting:HashSet<String>=HashSet::new();
 let first=TICK_OFFSET_MS-now_ms().rem_euclid(M);
 let first=if first<=0 {first+M} else {first};
 let mut tick=tokio::time::interval_at(tokio::time::Instant::now()+Duration::from_millis(first as u64),Duration::from_secs(60));
 tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
 let _=jobs.send(Job::Funding);
 loop {
  tokio::select! {
   Some(d)=done.recv()=>receive(&mut states,&mut booting,d),
   _=tick.tick()=>step(&mut states,&mut booting,&jobs),
  }
 }
}

struct Abort(tokio::task::JoinHandle<()>);
impl Drop for Abort {fn drop(&mut self) {self.0.abort();}}

fn receive(states:&mut HashMap<String,State>,booting:&mut HashSet<String>,d:Done) {
 let now=now_ms();
 match d {
  Done::Boot{base,restored,boot}=>{
   booting.remove(&base);
   // 接口快路补齐时引擎可能还没给它建状态（起跟是在请求里起的，状态要等下一拍）：在跟就现在建。
   if !states.contains_key(&base) {
    if !REGISTRY.get().is_some_and(|r|r.is_tracked(&base)) {return}
    states.insert(base.clone(),fresh(&base,now));
   }
   let Some(s)=states.get_mut(&base) else {return};
   // 快路与引擎自己的起步都补齐了：只认先到的那份，不然账本里补的那段会加两遍。
   if s.booted {return}
   let started=s.created.min(s.live_from.unwrap_or(i64::MAX));
   boot_state(s,restored,*boot,now,started);
   tracing::info!("Orderflow highlights: {base} ready ({} hours, {} ledger buckets, {} oi points)",s.hours.len(),s.ledger.b.len(),s.oi5.len());
   // 补齐就出一份，不等下一拍。
   let snap=Arc::new(s.compute(now,true));
   SNAPS.write().unwrap_or_else(|e|e.into_inner()).insert(base,snap);
  },
  Done::Oi{base,five,hour,funding}=>if let Some(s)=states.get_mut(&base) {
   for (t,v) in five {s.oi5.insert(t,v);}
   for (t,v) in hour {s.oi1h.insert(t,v);}
   for (t,v) in funding {s.samples.funding.put(t,v);}
  },
  Done::Funding(rates)=>{
   for (base,s) in states.iter_mut() {if let Some(r)=rates.get(base) {s.funding=Some(*r);}}
   // 后起跟的那几只起步时就有费率，不用等下一个 5 分钟。
   *FUNDING.lock().unwrap_or_else(|e|e.into_inner())=rates;
  },
 }
}

fn fresh(base:&str,now:i64)->State {
 let mut s=State::new(base,now);
 s.funding=FUNDING.lock().unwrap_or_else(|e|e.into_inner()).get(base).copied();
 s
}

/// 起步补齐：读回落过的盘（有就并进来）、合进 REST 与库里的历史；库里没有落过盘的算新起跟，从 `started` 起「观察中」。
fn boot_state(s:&mut State,restored:Option<Value>,boot:fetch::Boot,now:i64,started:i64) {
 let old=restored.as_ref().and_then(|v|State::restore(&s.base,v,now));
 let fresh_start=old.is_none();
 if let Some(old)=old {merge(s,old);}
 // 全市场费率表里没有（非币安、或那一下没取到）就先用最近一期的历史费率。
 let settled=boot.funding.iter().max_by_key(|(t,_)|*t).map(|(_,v)|*v);
 s.apply(boot,now);
 if s.funding.is_none() {s.funding=settled;}
 if fresh_start {s.observing_since=Some(started);}
}

/// 读回的那份并进这一任已经收了几分钟的状态：账本相加、样本与小时线补缺。
fn merge(s:&mut State,old:State) {
 for (k,o) in old.ledger.b {
  let b=s.ledger.b.entry(k).or_default();
  b.w+=o.w;b.wm+=o.wm;b.fb+=o.fb;b.fs+=o.fs;b.lq+=o.lq;b.tests+=o.tests;
  b.first=match (b.first,o.first) {(Some(a),Some(c))=>Some(a.min(c)),(a,c)=>a.or(c)};
  b.last=b.last.max(o.last);
  b.active=b.active.max(o.active);
  if b.role==0 {b.role=o.role;}
  if b.pos==0 {b.pos=o.pos;}
  b.broken|=o.broken;
 }
 for (t,h) in old.hours {s.hours.entry(t).or_insert(h);}
 for (t,v) in old.oi1h {s.oi1h.entry(t).or_insert(v);}
 let fill=|into:&mut stats::Samples,from:stats::Samples|for (t,v) in from.0 {into.0.entry(t).or_insert(v);};
 let o=old.samples;
 fill(&mut s.samples.n15,o.n15);fill(&mut s.samples.n1h,o.n1h);fill(&mut s.samples.n4h,o.n4h);fill(&mut s.samples.n24,o.n24);
 fill(&mut s.samples.oi,o.oi);fill(&mut s.samples.funding,o.funding);fill(&mut s.samples.premium,o.premium);
 s.until=s.until.max(old.until);
 s.touches_backfilled|=old.touches_backfilled;
}

fn hash(base:&str)->i64 {base.bytes().fold(0i64,|h,b|(h*31+i64::from(b)).rem_euclid(1_000_003))}

fn step(states:&mut HashMap<String,State>,booting:&mut HashSet<String>,jobs:&mpsc::UnboundedSender<Job>) {
 let now=now_ms();
 let minute=now.div_euclid(M);
 // 费率排在这一分钟的起步补齐前面（工人是单行道）；起步那一下没取到（多半撞上 429 闸门）就每分钟再要，
 // 不然要等一百多只补完、三五分钟里费率全空。
 let no_funding=FUNDING.lock().unwrap_or_else(|e|e.into_inner()).is_empty();
 if minute%5==0||no_funding {let _=jobs.send(Job::Funding);}
 let registry=REGISTRY.get();
 let mut tracked:Vec<String>=registry.map(|r|r.tracked()).unwrap_or_default();
 // 主币先起步。
 tracked.sort_by_key(|b|(!ALWAYS.contains(&b.as_str()),b.clone()));
 let set:HashSet<&str>=tracked.iter().map(String::as_str).collect();
 // 不跟了的：落一次盘，扔掉。
 let gone:Vec<String>=states.keys().filter(|b|!set.contains(b.as_str())).cloned().collect();
 for base in gone {
  if let Some(mut s)=states.remove(&base) && s.booted {s.settle_hours();let _=jobs.send(Job::Save{base:base.clone(),payload:s.payload(),at:now});}
  SNAPS.write().unwrap_or_else(|e|e.into_inner()).remove(&base);
 }
 let inbox=std::mem::take(&mut *INBOX.lock().unwrap_or_else(|e|e.into_inner()));
 for base in &tracked {states.entry(base.clone()).or_insert_with(||fresh(base,now));}
 for (base,p) in inbox {if let Some(s)=states.get_mut(&base) {s.fold(p,now);}}
 let mut snaps=HashMap::with_capacity(states.len());
 // 主币先补（冷启动时一百多只排队，打开最多的几只别排在后面）。
 let mut order:Vec<&String>=states.keys().collect();
 order.sort_by_key(|b|(!ALWAYS.contains(&b.as_str()),(*b).clone()));
 for base in order {
  let s=&states[base];
  if !s.booted&&!booting.contains(base)&&!QUICK.lock().unwrap_or_else(|e|e.into_inner()).contains_key(base) {
   booting.insert(base.clone());
   let _=jobs.send(Job::Boot{base:base.clone(),live_from:s.live_from.unwrap_or(minute*M)});
  }
 }
 for (base,s) in states.iter_mut() {
  if s.booted {
   s.sample_due(now);
   let slot=hash(base);
   if (minute+slot)%5==0 {let _=jobs.send(Job::Oi{base:base.clone(),hourly:(minute%60)<5,price:s.last_close()});}
   if (minute+slot)%PERSIST_EVERY==0 {s.settle_hours();let _=jobs.send(Job::Save{base:base.clone(),payload:s.payload(),at:now});}
  }
  // 还没补齐历史（起步 REST 与库里那一段）之前不发：只有头一分钟的数据，四行流向一样、涨跌全空，像真的又不对。
  if s.booted {snaps.insert(base.clone(),Arc::new(s.compute(now,true)));}
 }
 *SNAPS.write().unwrap_or_else(|e|e.into_inner())=snaps;
 if minute%60==7 {let _=jobs.send(Job::Purge);}
}

async fn worker(pool:PgPool,mut jobs:mpsc::UnboundedReceiver<Job>,done:mpsc::Sender<Done>) {
 while let Some(job)=jobs.recv().await {
  let out=match job {
   Job::Boot{base,live_from}=>{
    let restored=match load(&pool,&base).await {Ok(v)=>v,Err(e)=>{tracing::warn!("Orderflow highlights: {base} saved state unreadable: {e}");None}};
    let now=now_ms();
    let until=restored.as_ref().and_then(|v|v["until"].as_i64()).filter(|u|*u>0).unwrap_or(0);
    let from=until.max(now-3*stats::DAY_MS).min(live_from);
    let boot=fetch::boot(&pool,&base,from,live_from,now).await;
    Some(Done::Boot{base,restored,boot:Box::new(boot)})
   },
   Job::Oi{base,hourly,price}=>{
    let (five,hour)=fetch::oi(&base,hourly,price,now_ms()).await;
    let funding=if hourly {match fetch::symbols(&base).await.perp {Some((sym,_))=>fetch::funding_hist(&sym,3).await,None=>Vec::new()}} else {Vec::new()};
    Some(Done::Oi{base,five,hour,funding})
   },
   Job::Funding=>fetch::premium_all().await.map(Done::Funding),
   Job::Save{base,payload,at}=>{if let Err(e)=save(&pool,&base,&payload,at).await {tracing::warn!("Orderflow highlights: {base} not saved: {e}");}None},
   Job::Purge=>{
    match sqlx::query("DELETE FROM orderflow_highlights WHERE updated_ms<$1").bind(now_ms()-FORGET_MS).execute(&pool).await {
     Ok(r) if r.rows_affected()>0=>tracing::info!("Orderflow highlights: purge deleted {}",r.rows_affected()),
     Ok(_)=>{},
     Err(e)=>tracing::warn!("Orderflow highlights: purge failed: {e}"),
    }
    None
   },
  };
  if let Some(d)=out && done.send(d).await.is_err() {return}
 }
}

async fn load(pool:&PgPool,base:&str)->sqlx::Result<Option<Value>> {
 let row=sqlx::query("SELECT payload FROM orderflow_highlights WHERE base=$1").bind(base).fetch_optional(pool).await?;
 row.map(|r|r.try_get::<sqlx::types::Json<Value>,_>(0).map(|j|j.0)).transpose()
}

async fn save(pool:&PgPool,base:&str,payload:&Value,at:i64)->sqlx::Result<()> {
 sqlx::query("INSERT INTO orderflow_highlights(base,updated_ms,payload) VALUES($1,$2,$3) ON CONFLICT(base) DO UPDATE SET updated_ms=EXCLUDED.updated_ms,payload=EXCLUDED.payload")
  .bind(base).bind(at).bind(sqlx::types::Json(payload)).execute(pool).await?;
 Ok(())
}

// ------------------------------------------------------------------ 接口

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct HighlightsQuery {base:String}

/// 没在跟（或刚起跟、还没算出第一份）时的答复。
fn untracked(base:&str,now:i64)->Value {
 json!({"base":base,"generatedAtMs":now,"tracked":false,"staleMs":null,"observingSinceMs":null,"partial":false,"flow":null,"range":null,"levels":[],"position":null,"events":[]})
}

/// 快路：没算好的品种当场补一份（各路并发，最多等 [`QUICK_WAIT`]），能从 REST 历史拼出来的流向、区间、持仓 · 费率 · 现货溢价、
/// 触及次数马上给，`tracked:true` + `observingSinceMs`；到点没补完就先拿已经回来的算、`partial:true`，剩下的在后台补完交给引擎。
async fn quick(base:&str,now:i64)->Value {
 let q={
  let mut m=QUICK.lock().unwrap_or_else(|e|e.into_inner());
  m.entry(base.to_string()).or_insert_with(||{
   let q=Arc::new(Quick{started:now,restored:Mutex::new(None),boot:Mutex::new(fetch::Boot::default()),done:tokio::sync::watch::channel(false).0});
   tokio::spawn(fill(base.to_string(),q.clone()));
   q
  }).clone()
 };
 let mut rx=q.done.subscribe();
 let complete=tokio::time::timeout(QUICK_WAIT,rx.wait_for(|d|*d)).await.is_ok_and(|r|r.is_ok());
 if complete && let Some(s)=snapshot(base) && s.json.get("tracked")==Some(&json!(true)) {return s.json.clone()}
 let restored=q.restored.lock().unwrap_or_else(|e|e.into_inner()).clone();
 let boot=q.boot.lock().unwrap_or_else(|e|e.into_inner()).clone();
 let mut s=fresh(base,now);
 boot_state(&mut s,restored,boot,now,q.started);
 let snap=s.compute(now,true);
 let mut json=snap.json.clone();
 json["partial"]=json!(!complete);
 if complete {SNAPS.write().unwrap_or_else(|e|e.into_inner()).entry(base.to_string()).or_insert_with(||Arc::new(snap));}
 json
}

/// 快路的后台那一半：读回落过的盘、各路并发补齐，补完交给引擎（引擎已经补齐过就丢掉）。
async fn fill(base:String,q:Arc<Quick>) {
 let Some(pool)=POOL.get() else {let _=q.done.send(true);return};
 let restored=match load(pool,&base).await {Ok(v)=>v,Err(e)=>{tracing::warn!("Orderflow highlights: {base} saved state unreadable: {e}");None}};
 *q.restored.lock().unwrap_or_else(|e|e.into_inner())=restored.clone();
 let now=now_ms();
 let live_from=q.started.div_euclid(M)*M;
 let until=restored.as_ref().and_then(|v|v["until"].as_i64()).filter(|u|*u>0).unwrap_or(0);
 let from=until.max(now-3*stats::DAY_MS).min(live_from);
 fetch::boot_into(pool,&base,from,live_from,now,&q.boot).await;
 let boot=q.boot.lock().unwrap_or_else(|e|e.into_inner()).clone();
 let tx=INJECT.lock().unwrap_or_else(|e|e.into_inner()).clone();
 if let Some(tx)=tx {let _=tx.send(Done::Boot{base:base.clone(),restored,boot:Box::new(boot)}).await;}
 let _=q.done.send(true);
 QUICK.lock().unwrap_or_else(|e|e.into_inner()).remove(&base);
}

/// 一台设备：带登录令牌的按令牌（摘要），游客按来源地址（`auth::client_ip`，对端是本机的 Caddy 才认转发头）。
pub(super) struct Client(String);
impl<S:Send+Sync> axum::extract::FromRequestParts<S> for Client {
 type Rejection=std::convert::Infallible;
 async fn from_request_parts(parts:&mut axum::http::request::Parts,_:&S)->std::result::Result<Self,Self::Rejection> {
  use std::hash::{Hash,Hasher};
  if let Some(token)=parts.headers.get("authorization").and_then(|h|h.to_str().ok()).and_then(|v|v.strip_prefix("Bearer ")).filter(|t|!t.is_empty()) {
   let mut h=std::hash::DefaultHasher::new();
   token.hash(&mut h);
   return Ok(Client(format!("t:{:016x}",h.finish())))
  }
  let peer=parts.extensions.get::<axum::extract::ConnectInfo<std::net::SocketAddr>>().map(|c|c.0)
   .unwrap_or(std::net::SocketAddr::from((std::net::Ipv4Addr::UNSPECIFIED,0)));
  Ok(Client(format!("ip:{}",crate::auth::client_ip(&peer,&parts.headers))))
 }
}

pub(super) async fn highlights(Axum(_s):Axum<AppState>,headers:axum::http::HeaderMap,client:Client,Params(q):Params<HighlightsQuery>)->Result<Response> {
 if !instruments::valid_base(&q.base) {return Err(ApiError::bad("invalid_base"))}
 let gzip=accepts_gzip(&headers);
 let base=q.base;
 // 打开一只就记进这台设备的名单（自选层的设备那一份，缓存命中也记）。
 super::touch_device(&client.0,std::slice::from_ref(&base),now_ms()).await;
 let answer=ANSWERS.get_or_build((base.clone(),gzip),||async {
  let now=now_ms();
  // 打开一只就算「有人要」：没在跟的起跟（按需层），在跟的续上。
  let tracked=want(&base,now).await;
  let json=match snapshot(&base) {
   Some(s) if tracked=>s.json.clone(),
   // 挂牌的永续不回空答复：当场用 REST 历史补一份（资源闸门挡住没起跟的也照补，只是不会接着现场收）。
   _ if instruments::listed(&base).await!=Some(false)=>quick(&base,now).await,
   _=>untracked(&base,now),
  };
  packed(json.to_string(),gzip,CACHE_CONTROL)
 }).await?;
 Ok(answer.response())
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct BoardQuery {bases:Option<String>}

/// 首页异动一列：自选（`bases`，客户端带）∪ 热点层，每只一行。只读算好的那一份，不起跟。
pub(super) async fn highlights_board(Axum(_s):Axum<AppState>,headers:axum::http::HeaderMap,client:Client,Params(q):Params<BoardQuery>)->Result<Response> {
 let gzip=accepts_gzip(&headers);
 let favorites=board::parse(q.bases.as_deref());
 // 带上来的自选按客户端给的顺序记进这台设备的名单（每台最多 30），马上起跟，不等 10 分钟的账号自选重算、不要登录。
 let ordered:Vec<String>={
  let set:HashSet<&str>=favorites.iter().map(String::as_str).collect();
  let mut seen=HashSet::new();
  q.bases.as_deref().unwrap_or("").split(',').map(|b|b.trim().to_ascii_uppercase()).filter(|b|set.contains(b.as_str())&&seen.insert(b.clone())).collect()
 };
 if !ordered.is_empty() {super::touch_device(&client.0,&ordered,now_ms()).await;}
 let answer=BOARD_ANSWERS.get_or_build((favorites.join(","),gzip),||async {
  let hot=REGISTRY.get().map(|r|r.hot_list()).unwrap_or_default();
  let json=board::answer(&favorites,&hot,snapshot,&moves::current(),now_ms());
  packed(json.to_string(),gzip,CACHE_CONTROL)
 }).await?;
 Ok(answer.response())
}

#[cfg(test)]
mod tests {
 use super::*;

 #[test]
 fn a_fresh_base_answers_from_rest_history_then_levels_follow_live_data() {
  use fetch::{Boot,K};
  let now:i64=1_791_600_000_000+30_000;
  let t0=now.div_euclid(M)*M;
  let minutes:Vec<K>=(1..=1500).map(|i|K{t:t0-i*M,o:100.0,h:100.5,l:99.5,c:100.0}).collect();
  let kflow=minutes.iter().map(|k|(k.t,(100.0,1000.0))).collect();
  let hours:Vec<K>=(1..=20).map(|i|K{t:t0.div_euclid(stats::HOUR_MS)*stats::HOUR_MS-i*stats::HOUR_MS,o:100.0,h:101.0,l:99.0,c:100.0}).collect();
  let oi5:Vec<(i64,f64)>=(0..100).map(|i|(t0.div_euclid(5*M)*5*M-i*5*M,1e8-1e5*i as f64)).collect();
  let spot_minutes:Vec<K>=(1..=60).map(|i|K{t:t0-i*M,o:100.1,h:100.1,l:100.1,c:100.1}).collect();
  let boot=Boot{minutes,kflow,spot_minutes,hours,oi5,funding:vec![(t0-8*stats::HOUR_MS,0.0001)],gap:(t0-3*stats::DAY_MS,t0),..Boot::default()};
  let mut s=fresh("FRESH",now);
  boot_state(&mut s,None,boot,now,now);
  let j=s.compute(now,true).json;
  assert_eq!(j["tracked"],true);
  assert_eq!(j["observingSinceMs"],now,"a never-tracked base says when live observation started");
  assert_eq!(j["partial"],false);
  let rows=j["flow"]["rows"].as_array().unwrap();
  assert_eq!(rows[0]["netUsd"],json!(1500.0),"15m from the 1-minute klines' taker-buy volume");
  assert_eq!(rows[1]["netUsd"],json!(6000.0));
  assert_eq!(rows[2]["netUsd"],json!(24000.0));
  assert!(rows[3]["netUsd"].is_number(),"24h / range row covered by 25 hours of minutes");
  assert!(j["position"]["oi"]["pct1h"].is_number(),"open interest from the 5-minute history");
  assert_eq!(j["position"]["funding"]["rate"],json!(0.0001),"funding falls back to the latest settled rate");
  assert_eq!(j["position"]["spotPremium"]["pct"],json!(0.1),"spot premium from the spot 1-minute klines");
  assert!(j["levels"].as_array().unwrap().is_empty(),"levels need live walls / fills");
  // 现场收到墙与成交之后，关键价位就出来了。
  let mut p=Pending::default();
  p.fills.push((t0,std::collections::BTreeMap::from([(ledger::key(100.2),(5e5,1e5))])));
  p.walls.push((t0,vec![Live{bid:true,price:99.8,usd:2e6,initial:2e6,filled:0.0,first:t0}]));
  s.fold(p,now+M);
  let j=s.compute(now+M,true).json;
  assert!(!j["levels"].as_array().unwrap().is_empty(),"live data turns into levels");
  assert_eq!(j["observingSinceMs"],now);
  // 落过盘的不算新起跟。
  let mut old=fresh("FRESH",now);
  boot_state(&mut old,Some(s.payload()),Boot{gap:(t0,t0),..Boot::default()},now,now);
  assert_eq!(old.compute(now,true).json["observingSinceMs"],Value::Null);
 }

 #[test]
 fn venue_ranks() {
  assert_eq!(perp_rank("binance:usdtPerp:BTCUSDT"),Some(0));
  assert_eq!(perp_rank("hyperliquid:usdtPerp:BTC"),Some(3));
  assert_eq!(perp_rank("binance:coinPerp:BTCUSD_PERP"),None);
  assert_eq!(spot_rank("coinbase:spot:BTC-USD"),Some(1));
  assert_eq!(spot_rank("okx:usdtPerp:BTC-USDT-SWAP"),None);
 }

 #[test]
 fn untracked_answer_has_the_contract_keys() {
  let v=untracked("AXS",5);
  for k in ["base","generatedAtMs","tracked","staleMs","flow","range","levels","position","events"] {assert!(v.get(k).is_some(),"{k}");}
  assert_eq!(v["tracked"],false);
 }

 #[test]
 fn merge_adds_ledgers_and_fills_samples() {
  let mut live=State::new("X",0);
  live.ledger.b.insert(5,ledger::Bucket{w:1.0,tests:1,last:Some(10),..Default::default()});
  live.samples.oi.put(3_600_000,1.0);
  let mut old=State::new("X",0);
  old.ledger.b.insert(5,ledger::Bucket{w:2.0,tests:3,first:Some(1),last:Some(5),role:1,..Default::default()});
  old.samples.oi.put(3_600_000,9.0);
  old.samples.oi.put(0,2.0);
  old.until=7;
  merge(&mut live,old);
  let b=&live.ledger.b[&5];
  assert_eq!((b.w,b.tests,b.first,b.last,b.role),(3.0,4,Some(1),Some(10),1));
  assert_eq!(live.samples.oi.0.get(&3_600_000),Some(&1.0),"live sample wins");
  assert_eq!(live.samples.oi.len(),2);
  assert_eq!(live.until,7);
 }
}
