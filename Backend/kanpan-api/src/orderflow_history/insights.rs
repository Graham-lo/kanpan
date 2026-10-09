//! 盘口洞察：真实大额成交的分钟 × 簿 × 价桶聚合，绝不从分钟总额回填成交价。
//! 每币报价与 Tracker 已规范化的成交一致。交割不进入；各交易所、产品、币对始终独立。
//! 空分钟也保存观测标记，断线、重启、丢帧、写失败撤销连续覆盖。仅保留三天聚合，
//! 真实成交 ID 的短时哈希用于重连 / 重启去重，没有逐笔价格量历史。
use super::book::VenueInfo;
use super::minutes::{self,MINUTE_MS,Row};
use super::{Answer,Answers,HISTORY_READS,POOL,REGISTRY,accepts_gzip,flow,footprint,now_ms,packed,store};
use crate::AppState;
use crate::error::{ApiError,Params,Result};
use crate::orderflow_instruments as instruments;
use crate::storage_budget::{self,Budget};
use axum::extract::State;
use axum::response::Response;
use serde::{Deserialize,Serialize};
use futures_util::TryStreamExt;
use sha2::{Digest,Sha256};
use sqlx::postgres::{PgPool,PgRow,Postgres};
use sqlx::query_builder::Separated;
use sqlx::Row as _;
use std::collections::{BTreeMap,HashMap,HashSet};
use std::sync::{LazyLock,Mutex,OnceLock};
use std::sync::atomic::AtomicU64;
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::task::JoinHandle;

pub(super) const PATH:&str="/v1/market/orderflow/insights";
const TTL:Duration=Duration::from_secs(20);
const CACHE_CONTROL:&str="public, max-age=20";
const QUEUE:usize=256;
const MAX_LEVELS:usize=512;
const MAX_IDS:usize=512;
const MAX_READ_LEVELS:usize=8192;
const REPLAY_MS:i64=3*MINUTE_MS;

#[derive(Clone,Debug,Serialize,Deserialize,PartialEq)]
struct Level {
 venue_id:String,exchange:String,product:String,step:f64,bucket:i64,
 buy:f64,sell:f64,first:i64,last:i64,
}

/// 一只 base 一分钟；payload 不含逐笔价量，seen 只含大额成交真实 ID 的哈希。
#[derive(Clone,Debug,Serialize,Deserialize,PartialEq)]
pub(super) struct Minute {
 #[serde(skip)] pub minute_ms:i64,
 coverage_since:Option<i64>,observed_until:i64,last_trade:Option<i64>,
 levels:Vec<Level>,#[serde(default)] seen:BTreeMap<String,Vec<String>>,#[serde(default)] watermarks:BTreeMap<String,i64>,
}
impl Minute {
 fn new(minute_ms:i64)->Self {Self{minute_ms,coverage_since:None,observed_until:minute_ms,last_trade:None,levels:vec![],seen:BTreeMap::new(),watermarks:BTreeMap::new()}}
}

#[derive(Clone,Debug,Default)]
struct Live {since:Option<i64>,fault:i64}
static LIVE:LazyLock<Mutex<HashMap<String,Live>>>=LazyLock::new(Default::default);
static VENUE_BASE:LazyLock<Mutex<HashMap<String,String>>>=LazyLock::new(Default::default);
fn live(base:&str)->Live {LIVE.lock().unwrap_or_else(|e|e.into_inner()).get(base).cloned().unwrap_or_default()}
pub(super) fn gap(base:&str,at:i64) {
 let mut all=LIVE.lock().unwrap_or_else(|e|e.into_inner());
 let state=all.entry(base.to_string()).or_default();
 state.fault=state.fault.max(at);state.since=None;
}
fn publish(base:&str,since:Option<i64>) {LIVE.lock().unwrap_or_else(|e|e.into_inner()).entry(base.to_string()).or_default().since=since;}
pub(super) fn gap_venue(venue:&str,at:i64) {
 let base=VENUE_BASE.lock().unwrap_or_else(|e|e.into_inner()).get(venue).cloned();
 if let Some(base)=base {gap(&base,at);}
}

static DROPPED:AtomicU64=AtomicU64::new(0);
impl Row for Minute {
 const TABLE:&'static str="orderflow_insights";
 const COLUMNS:&'static str="payload";
 const BUDGET:Budget=storage_budget::FOOTPRINT;
 const PENDING_LIMIT:usize=256;
 fn dropped()->&'static AtomicU64 {&DROPPED}
 fn minute_ms(&self)->i64 {self.minute_ms}
 fn failed(base:&str,_minute:i64) {gap(base,now_ms());}
 fn merge(&mut self,later:Self) {
  if later.observed_until>=self.observed_until {self.coverage_since=later.coverage_since;self.observed_until=later.observed_until;}
  self.last_trade=self.last_trade.max(later.last_trade);
  for level in later.levels {
   if let Some(old)=self.levels.iter_mut().find(|old|old.venue_id==level.venue_id&&old.step==level.step&&old.bucket==level.bucket) {
    old.buy+=level.buy;old.sell+=level.sell;old.first=old.first.min(level.first);old.last=old.last.max(level.last);
   } else {self.levels.push(level);}
  }
  for (venue,ids) in later.seen {
   let existing=self.seen.entry(venue).or_default();
   let mut known:HashSet<String>=existing.iter().cloned().collect();
   existing.extend(ids.into_iter().filter(|id|known.insert(id.clone())));
  }
  for (venue,id) in later.watermarks {let old=self.watermarks.entry(venue).or_insert(id);*old=(*old).max(id);}
  if self.levels.len()>MAX_LEVELS||self.seen.values().map(Vec::len).sum::<usize>()>MAX_IDS {
   // 罕见的同分钟多进程片段叠加仍受硬上限约束；撤销覆盖，不能把截断结果当完整数据。
   self.levels.truncate(MAX_LEVELS);let mut left=MAX_IDS;
   for ids in self.seen.values_mut() {ids.truncate(left);left=left.saturating_sub(ids.len());}
   self.coverage_since=None;
   DROPPED.fetch_add(1,std::sync::atomic::Ordering::Relaxed);
  }
 }
 fn push_binds(&self,b:&mut Separated<'_,'_,Postgres,&'static str>) {
  b.push_bind(sqlx::types::Json(self.clone()));
 }
 fn from_pg(row:&PgRow)->Option<Self> {
  let mut m:Minute=row.try_get::<sqlx::types::Json<Minute>,_>(1).ok()?.0;
  m.minute_ms=row.try_get(0).ok()?;
  m.levels.iter().all(|l|l.step.is_finite()&&l.step>0.0&&l.buy.is_finite()&&l.buy>=0.0&&l.sell.is_finite()&&l.sell>=0.0).then_some(m)
 }
}

#[derive(Debug)]
struct Source {exchange:String,product:String,tick:f64,step:Option<f64>,connections:HashSet<u64>}

/// 一个 Tracker 的有界累积器；只在大额成交入口使用真实 ID 去重。
#[derive(Debug,Default)]
pub(super) struct Acc {
 base:String,sources:HashMap<String,Source>,open:BTreeMap<i64,Minute>,
 seen:BTreeMap<i64,HashSet<(String,String)>>,next_minute:Option<i64>,since:Option<i64>,fault:i64,
 watermarks:HashMap<String,i64>,
}
impl Drop for Acc {
 fn drop(&mut self) {
  LIVE.lock().unwrap_or_else(|e|e.into_inner()).remove(&self.base);
  let mut bases=VENUE_BASE.lock().unwrap_or_else(|e|e.into_inner());
  for venue in self.sources.keys() {if bases.get(venue)==Some(&self.base) {bases.remove(venue);}}
 }
}
impl Acc {
 pub fn new(base:&str,now:i64)->Self {
  gap(base,now);
  let mut acc=Self::default();acc.base=base.into();acc.next_minute=Some(now.div_euclid(MINUTE_MS)*MINUTE_MS);acc.fault=now;acc
 }
 pub fn register(&mut self,venue:&VenueInfo,tick:f64) {
  if venue.product=="delivery"||self.sources.contains_key(&venue.id) {return}
  self.sources.insert(venue.id.clone(),Source{exchange:venue.label.into(),product:venue.product.into(),tick,step:None,connections:HashSet::new()});
  VENUE_BASE.lock().unwrap_or_else(|e|e.into_inner()).insert(venue.id.clone(),self.base.clone());
  self.since=None;publish(&self.base,None);
 }
 pub fn remove(&mut self,id:&str,now:i64) {
  self.sources.remove(id);self.reset(now);
  VENUE_BASE.lock().unwrap_or_else(|e|e.into_inner()).remove(id);
 }
 fn reset(&mut self,now:i64) {self.fault=now;self.since=None;gap(&self.base,now);}
 /// 只接成交连接状态（币安 U 本位深度连接不参与）。交接时旧连接下线不会掐断仍在线的新连接。
 pub fn stream(&mut self,id:&str,connection:u64,online:bool,now:i64) {
  let Some(source)=self.sources.get_mut(id) else {return};
  let was_online=!source.connections.is_empty();
  if online {source.connections.insert(connection);} else {source.connections.remove(&connection);}
  if was_online!=!source.connections.is_empty() {self.reset(now);}
  if online&&self.sources.values().all(|s|!s.connections.is_empty()) {self.since.get_or_insert(now);publish(&self.base,self.since);}
 }
 fn refresh(&mut self,cut:Option<f64>,now:i64) {
  let fault=live(&self.base).fault;
  if fault>self.fault {self.fault=fault;self.since=None;}
  if cut.is_none()||self.sources.is_empty()||self.sources.values().any(|s|s.connections.is_empty()) {self.since=None;}
  else if self.since.is_none() {self.since=Some(now.max(self.fault));}
  publish(&self.base,self.since);
 }
 /// 恢复最近三分钟 ID 检查点。重启仍重新计算覆盖，不继承旧进程的连续性。
 pub async fn restore(&mut self,pool:&PgPool,now:i64)->sqlx::Result<()> {
  for m in read(pool,&self.base,now-REPLAY_MS,now).await? {self.restore_minute(&m);}
  Ok(())
 }
 fn restore_minute(&mut self,m:&Minute) {
  let ids=self.seen.entry(m.minute_ms).or_default();
  for (venue,seen) in &m.seen {ids.extend(seen.iter().cloned().map(|id|(venue.clone(),id)));}
  for (venue,id) in &m.watermarks {let old=self.watermarks.entry(venue.clone()).or_insert(*id);*old=(*old).max(*id);}
 }
 pub fn add(&mut self,venue:&str,price:f64,usd:f64,buy:bool,token:Option<&str>,at:i64,now:i64,cut:Option<f64>) {
  self.refresh(cut,now);
  let Some(cut)=cut else {return};
  if !(price.is_finite()&&price>0.0&&usd.is_finite()&&usd>0.0)||!self.sources.contains_key(venue) {return}
  let minute=at.div_euclid(MINUTE_MS)*MINUTE_MS;
  self.seen.retain(|minute,_|*minute>=now-REPLAY_MS);
  let m=self.open.entry(minute).or_insert_with(||Minute::new(minute));
  m.last_trade=m.last_trade.max(Some(at));
  if usd<cut {return}
  // 不用时间 + 价 + 量猜成交身份，同毫秒的两笔真成交仍各自计入。
  let monotonic=venue.starts_with("binance:").then(||token.and_then(|id|id.parse::<i64>().ok())).flatten();
  if monotonic.is_some_and(|id|self.watermarks.get(venue).is_some_and(|old|id<=*old)) {return}
  let fingerprint=if monotonic.is_none() {token.map(|id|hex::encode(&Sha256::digest(id.as_bytes())[..16]))} else {None};
  if let Some(id)=&fingerprint {
   if self.seen.values().any(|seen|seen.contains(&(venue.to_string(),id.clone()))) {return}
   if self.seen.get(&minute).map_or(0,HashSet::len)>=MAX_IDS {DROPPED.fetch_add(1,std::sync::atomic::Ordering::Relaxed);self.reset(now);return}
  }
  let source=self.sources.get_mut(venue).unwrap();
  let step=footprint::step(price,source.tick,source.step);
  source.step=Some(step);
  let bucket=footprint::bucket(price,step);
  let m=self.open.get_mut(&minute).unwrap();
  let index=m.levels.iter().position(|l|l.venue_id==venue&&l.step==step&&l.bucket==bucket);
  let index=match index {
   Some(index)=>index,
   None=>{
    if m.levels.len()>=MAX_LEVELS {DROPPED.fetch_add(1,std::sync::atomic::Ordering::Relaxed);self.reset(now);return}
    m.levels.push(Level{venue_id:venue.into(),exchange:source.exchange.clone(),product:source.product.clone(),step,bucket,buy:0.0,sell:0.0,first:at,last:at});
    m.levels.len()-1
   },
  };
  let level=&mut m.levels[index];
  if buy {level.buy+=usd} else {level.sell+=usd}
  level.first=level.first.min(at);level.last=level.last.max(at);
  if let Some(id)=fingerprint {
   self.seen.entry(minute).or_default().insert((venue.into(),id.clone()));
   m.seen.entry(venue.into()).or_default().push(id);
  }
  if let Some(id)=monotonic {self.watermarks.insert(venue.into(),id);m.watermarks.insert(venue.into(),id);}
 }
 pub fn roll(&mut self,now:i64,cut:Option<f64>)->Vec<Minute> {
  self.refresh(cut,now);
  let current=now.div_euclid(MINUTE_MS)*MINUTE_MS;
  let first=self.next_minute.unwrap_or(current).max(current-REPLAY_MS);
  for minute in (first..=current).step_by(MINUTE_MS as usize) {self.open.entry(minute).or_insert_with(||Minute::new(minute));}
  self.next_minute=Some(current);
  for m in self.open.values_mut() {m.coverage_since=self.since;m.observed_until=now.min(m.minute_ms+MINUTE_MS);m.watermarks=self.watermarks.iter().map(|(venue,id)|(venue.clone(),*id)).collect();}
  let keys:Vec<i64>=self.open.keys().copied().filter(|m|minutes::closed(*m,now)).collect();
  keys.into_iter().filter_map(|m|self.open.remove(&m)).collect()
 }
 pub fn take(&mut self,now:i64)->Vec<Minute> {
  publish(&self.base,None);
  for m in self.open.values_mut() {m.coverage_since=self.since;m.observed_until=now.min(m.minute_ms+MINUTE_MS);m.watermarks=self.watermarks.iter().map(|(venue,id)|(venue.clone(),*id)).collect();}
  std::mem::take(&mut self.open).into_values().collect()
 }
}

static TX:OnceLock<Mutex<Option<mpsc::Sender<(String,Minute)>>>>=OnceLock::new();
static WRITER:OnceLock<Mutex<Option<JoinHandle<()>>>>=OnceLock::new();
pub(super) fn start(pool:PgPool) {
 TX.get_or_init(||{
  let (tx,task)=minutes::channel_with_task(pool,QUEUE);
  WRITER.get_or_init(||Mutex::new(Some(task)));
  Mutex::new(Some(tx))
 });
}
pub(super) fn submit(base:&str,rows:Vec<Minute>) {
 let Some(tx)=TX.get() else {return};
 let tx=tx.lock().unwrap_or_else(|e|e.into_inner());
 minutes::submit(tx.as_ref(),base,rows);
}
/// Tracker 已交完半分钟以后关闭全局通道，复用 minutes writer 排空，仍受总停机期限限制。
pub(super) async fn drained(deadline:tokio::time::Instant)->bool {
 if let Some(tx)=TX.get() {tx.lock().unwrap_or_else(|e|e.into_inner()).take();}
 let task=WRITER.get().and_then(|task|task.lock().unwrap_or_else(|e|e.into_inner()).take());
 match task {Some(task)=>matches!(tokio::time::timeout_at(deadline,task).await,Ok(Ok(()))),None=>true}
}
pub(super) async fn purge(pool:&PgPool,now:i64)->sqlx::Result<u64> {minutes::purge::<Minute>(pool,now).await}

// ------------------------------------------------------------------ 固定客户端契约
#[derive(Debug,Serialize,PartialEq)]
#[serde(rename_all="camelCase")]
struct Summary {
 base:String,generated_at_ms:i64,day_start_ms:i64,tracked:bool,coverage_since_ms:Option<i64>,last_trade_ms:Option<i64>,big_usd:Option<f64>,
 windows:Vec<Window>,zones:Vec<Zone>,
}
#[derive(Debug,Serialize,PartialEq)]
struct Window {minutes:i64,sources:Vec<FlowSource>}
#[derive(Debug,Serialize,PartialEq)]
#[serde(rename_all="camelCase")]
struct FlowSource {#[serde(rename="venueID")] venue_id:String,exchange:String,product:String,buy_usd:f64,sell_usd:f64}
#[derive(Clone,Debug,Serialize,PartialEq)]
#[serde(rename_all="camelCase")]
struct Zone {
 #[serde(rename="venueID")] venue_id:String,exchange:String,product:String,low:f64,high:f64,
 buy_usd:f64,sell_usd:f64,recent_buy_usd:f64,recent_sell_usd:f64,first_ms:i64,last_ms:i64,
}
fn day_start(now:i64)->i64 {(now+8*3_600_000).div_euclid(store::DAY_MS)*store::DAY_MS-8*3_600_000}
fn window_end(now:i64)->i64 {(now-minutes::GRACE_MS).div_euclid(MINUTE_MS)*MINUTE_MS}
/// 只声明逐分钟反向核实过的完整连续段，部分首分钟不参与判断。
/// 预算裁剪、坏行、库写失败造成的中间缺口都在这里截断，不靠在线状态猜覆盖。
fn coverage_since(rows:&[Minute],state:&Live,end:i64)->Option<i64> {
 let since=state.since?;
 let mut by_minute:BTreeMap<i64,&Minute>=BTreeMap::new();
 for m in rows.iter().filter(|m|m.minute_ms<end&&m.observed_until>=m.minute_ms+MINUTE_MS) {
  let old=by_minute.entry(m.minute_ms).or_insert(m);
  if m.observed_until>old.observed_until {*old=m;}
 }
 let mut earliest=end;
 let mut cursor=end-MINUTE_MS;
 while let Some(m)=by_minute.get(&cursor) {
  let Some(observed)=m.coverage_since else {break};
  if observed.max(since)>cursor {break}
  earliest=cursor;cursor-=MINUTE_MS;
 }
 (earliest<end).then_some(earliest)
}
fn summary(base:&str,now:i64,tracked:bool,big:Option<f64>,rows:&[Minute],state:&Live)->Summary {
 let day=day_start(now);
 let end=window_end(now);
 // 不能用旧行让重启后的新一段看起来已经完整；最后一个结束分钟未落盘时也不宣称实时覆盖。
 let coverage=coverage_since(rows,state,end);
 let mut windows=Vec::new();
 if tracked {for count in [5,15,60] {
  let mut sources:BTreeMap<String,FlowSource>=BTreeMap::new();
  for m in rows.iter().filter(|m|coverage.is_some_and(|since|m.minute_ms>=since)&&m.minute_ms>=end-count*MINUTE_MS&&m.minute_ms<end&&m.observed_until>=m.minute_ms+MINUTE_MS) {
   for l in &m.levels {
    let source=sources.entry(l.venue_id.clone()).or_insert_with(||FlowSource{venue_id:l.venue_id.clone(),exchange:l.exchange.clone(),product:l.product.clone(),buy_usd:0.0,sell_usd:0.0});
    source.buy_usd+=l.buy;source.sell_usd+=l.sell;
   }
  }
  windows.push(Window{minutes:count,sources:sources.into_values().collect()});
 }}
 let mut by_venue:BTreeMap<String,Vec<Zone>>=BTreeMap::new();
 for m in rows.iter().filter(|m|coverage.is_some_and(|since|m.minute_ms>=since)&&m.minute_ms>=day&&m.minute_ms<end&&m.observed_until>=m.minute_ms+MINUTE_MS) {
  for l in &m.levels {
   let recent=m.minute_ms>=end-15*MINUTE_MS;
   by_venue.entry(l.venue_id.clone()).or_default().push(Zone{venue_id:l.venue_id.clone(),exchange:l.exchange.clone(),product:l.product.clone(),low:l.bucket as f64*l.step,high:(l.bucket+1) as f64*l.step,
    buy_usd:l.buy,sell_usd:l.sell,recent_buy_usd:if recent {l.buy} else {0.0},recent_sell_usd:if recent {l.sell} else {0.0},first_ms:l.first,last_ms:l.last});
  }
 }
 let mut zones=Vec::new();
 for (_,mut levels) in by_venue {
  levels.sort_by(|a,b|a.low.total_cmp(&b.low).then_with(||a.high.total_cmp(&b.high)));
  // 同一价桶先合计。相邻非零桶不能一路串成全天价格范围；每簿先选局部密度峰，
  // 再吸收连续邻桶，区间最多为该簿最粗已观测桶宽的 5 倍，最多三个互不重叠区。
  let mut merged:Vec<Zone>=vec![];
  for level in levels {
   if let Some(last)=merged.last_mut() && level.low==last.low&&level.high==last.high {
    last.buy_usd+=level.buy_usd;last.sell_usd+=level.sell_usd;
    last.recent_buy_usd+=level.recent_buy_usd;last.recent_sell_usd+=level.recent_sell_usd;
    last.first_ms=last.first_ms.min(level.first_ms);last.last_ms=last.last_ms.max(level.last_ms);
   } else {merged.push(level);}
  }
  let coarse=merged.iter().map(|z|z.high-z.low).fold(0.0,f64::max);
  let mut used=vec![false;merged.len()];
  let mut selected:Vec<Zone>=vec![];
  for _ in 0..3 {
   let peak=merged.iter().enumerate().filter(|(i,z)|!used[*i]&&!selected.iter().any(|s|z.low<s.high&&z.high>s.low))
    .max_by(|(_,a),(_,b)|((a.buy_usd+a.sell_usd)/(a.high-a.low)).total_cmp(&((b.buy_usd+b.sell_usd)/(b.high-b.low))).then_with(||b.low.total_cmp(&a.low)));
   let Some((index,seed))=peak else {break};
   let (min,max)=(seed.low-2.0*coarse,seed.high+2.0*coarse);
   let mut zone=seed.clone();used[index]=true;
   // 局部邻桶仅归并到真实桶边缘，金额与近 15 分钟均只加这些完整包含的桶。
   for direction in [-1isize,1] {
    let mut i=index as isize+direction;
    while i>=0&&(i as usize)<merged.len() {
     let j=i as usize;let other=&merged[j];
     if used[j]||other.low<min||other.high>max||other.low>zone.high+coarse*1e-8||other.high<zone.low-coarse*1e-8
      ||selected.iter().any(|s|other.low<s.high&&other.high>s.low) {break}
     used[j]=true;zone.low=zone.low.min(other.low);zone.high=zone.high.max(other.high);
     zone.buy_usd+=other.buy_usd;zone.sell_usd+=other.sell_usd;zone.recent_buy_usd+=other.recent_buy_usd;zone.recent_sell_usd+=other.recent_sell_usd;
     zone.first_ms=zone.first_ms.min(other.first_ms);zone.last_ms=zone.last_ms.max(other.last_ms);
     i+=direction;
    }
   }
   selected.push(zone);
  }
  zones.extend(selected);
 }
 zones.sort_by(|a,b|(b.buy_usd+b.sell_usd).total_cmp(&(a.buy_usd+a.sell_usd)).then_with(||a.venue_id.cmp(&b.venue_id)));
 zones.truncate(12);
 Summary{base:base.into(),generated_at_ms:now,day_start_ms:day,tracked,coverage_since_ms:coverage,last_trade_ms:rows.iter().filter_map(|m|m.last_trade).max(),big_usd:big,windows,zones}
}
async fn read(pool:&PgPool,base:&str,from:i64,to:i64)->sqlx::Result<Vec<Minute>> {
 let rows=sqlx::query("SELECT minute_ms,payload FROM orderflow_insights WHERE base=$1 AND minute_ms BETWEEN $2 AND $3 ORDER BY minute_ms")
  .bind(base).bind(from).bind(to).fetch_all(pool).await?;
 Ok(rows.iter().filter_map(Minute::from_pg).collect())
}
/// API 分两步：先读小体积覆盖标记，再流式读取当前连续段的价桶；短期 ID 检查点不进 API 内存。
/// 同一窗口档和价桶立即归并，最多 8192 个聚合桶；达到上限返回不可用，不无界展开整日逐价位。
async fn read_compact(pool:&PgPool,base:&str,from:i64,to:i64,state:&Live)->sqlx::Result<Vec<Minute>> {
 let metadata=sqlx::query("SELECT minute_ms,payload-'levels'-'seen'-'watermarks' FROM orderflow_insights WHERE base=$1 AND minute_ms BETWEEN $2 AND $3 ORDER BY minute_ms")
  .bind(base).bind(from).bind(to).fetch_all(pool).await?;
 let mut rows=Vec::with_capacity(metadata.len());
 for r in metadata {
  let minute=r.try_get::<i64,_>(0)?;
  let payload=r.try_get::<sqlx::types::Json<serde_json::Value>,_>(1)?.0;
  rows.push(metadata_minute(minute,payload)?);
 }
 let end=window_end(to);
 let Some(since)=coverage_since(&rows,state,end) else {return Ok(rows)};
 let mut stream=sqlx::query("SELECT minute_ms,payload->'levels' FROM orderflow_insights WHERE base=$1 AND minute_ms>=$2 AND minute_ms<$3 ORDER BY minute_ms")
  .bind(base).bind(since.max(from)).bind(end).fetch(pool);
 let mut grouped:BTreeMap<(i64,bool,String,u64,i64),(i64,Level)>=BTreeMap::new();
 while let Some(row)=stream.try_next().await? {
  let minute:i64=row.try_get(0)?;
  let levels=row.try_get::<sqlx::types::Json<Vec<Level>>,_>(1)?.0;
  let band=if minute>=end-5*MINUTE_MS {0} else if minute>=end-15*MINUTE_MS {1} else if minute>=end-60*MINUTE_MS {2} else {3};
  for level in levels {
   if !(level.step.is_finite()&&level.step>0.0&&level.buy.is_finite()&&level.buy>=0.0&&level.sell.is_finite()&&level.sell>=0.0) {return Err(sqlx::Error::Protocol("invalid insights bucket".into()))}
   let key=(band,minute>=day_start(to),level.venue_id.clone(),level.step.to_bits(),level.bucket);
   if let Some((_,old))=grouped.get_mut(&key) {old.buy+=level.buy;old.sell+=level.sell;old.first=old.first.min(level.first);old.last=old.last.max(level.last);}
   else {
    if grouped.len()>=MAX_READ_LEVELS {return Err(sqlx::Error::Protocol("insights snapshot bucket limit".into()))}
    grouped.insert(key,(minute,level));
   }
  }
 }
 for (_, (minute,level)) in grouped {
  rows.push(Minute{minute_ms:minute,coverage_since:Some(since),observed_until:minute+MINUTE_MS,last_trade:None,levels:vec![level],seen:BTreeMap::new(),watermarks:BTreeMap::new()});
 }
 Ok(rows)
}
#[derive(Deserialize)]
struct Metadata {coverage_since:Option<i64>,observed_until:i64,last_trade:Option<i64>}
fn metadata_minute(minute_ms:i64,payload:serde_json::Value)->sqlx::Result<Minute> {
 let m:Metadata=serde_json::from_value(payload).map_err(|_|sqlx::Error::Protocol("invalid insights coverage metadata".into()))?;
 if minute_ms<0||minute_ms%MINUTE_MS!=0||m.observed_until<minute_ms||m.observed_until>minute_ms+MINUTE_MS
  ||m.coverage_since.is_some_and(|since|since<0)||m.last_trade.is_some_and(|last|last<minute_ms||last>=minute_ms+MINUTE_MS) {
  return Err(sqlx::Error::Protocol("invalid insights coverage interval".into()))
 }
 Ok(Minute{minute_ms,coverage_since:m.coverage_since,observed_until:m.observed_until,last_trade:m.last_trade,levels:vec![],seen:BTreeMap::new(),watermarks:BTreeMap::new()})
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct InsightsQuery {base:String}
#[derive(Clone,Debug,PartialEq,Eq,Hash)]
struct Key {base:String,big:Option<u64>,gzip:bool}
static ANSWERS:LazyLock<Answers<Key>>=LazyLock::new(||Answers::new(TTL));
fn answer(summary:&Summary,gzip:bool)->Result<Answer> {packed(serde_json::to_string(summary).map_err(|_|ApiError::bad("invalid_insights"))?,gzip,CACHE_CONTROL)}
pub(super) async fn insights(State(s):State<AppState>,headers:axum::http::HeaderMap,Params(q):Params<InsightsQuery>)->Result<Response> {
 if !instruments::valid_base(&q.base) {return Err(ApiError::bad("invalid_base"))}
 let gzip=accepts_gzip(&headers);
 let now=now_ms();
 // 只读，不调用 Registry::request，不因为开洞察订阅全市场或拉历史回填。
 let registry=REGISTRY.get();
 if !registry.is_some_and(|r|r.is_tracked(&q.base)) {return Ok(answer(&summary(&q.base,now,false,None,&[],&Live::default()),gzip)?.response())}
 let big=registry.and_then(|r|r.thresholds(&q.base)).as_ref().and_then(flow::big_cut);
 let key=Key{base:q.base.clone(),big:big.map(f64::to_bits),gzip};
 let pool=POOL.get().unwrap_or(&s.pool);
 let answer=ANSWERS.get_or_build(key,||async {
  let _slot=HISTORY_READS.acquire().await.map_err(|_|ApiError(axum::http::StatusCode::SERVICE_UNAVAILABLE,"temporarily_unavailable"))?;
  let now=now_ms();
  // 零点前后一小时窗口仍需昨天的真实分钟；今日价区只在 summary 内截北京时间零点。
  let state=live(&q.base);
  let rows=read_compact(pool,&q.base,day_start(now).min(window_end(now)-60*MINUTE_MS),now,&state).await?;
  drop(_slot);
  answer(&summary(&q.base,now,true,big,&rows,&live(&q.base)),gzip)
 }).await?;
 Ok(answer.response())
}

#[cfg(test)]
mod tests {
 use super::*;
 use super::super::book::Sequence;
 use super::super::model::Notional;
 fn venue(id:&str,product:&'static str)->VenueInfo {VenueInfo::test(id,"BTCUSDT",product,Notional::Linear(1.0),Sequence::StrictIncrementing,true,false)}
 fn acc(base:&str,now:i64)->Acc {
  let mut a=Acc::new(base,now);a.register(&venue("binance:usdtPerp:BTCUSDT","usdtPerp"),0.1);a.stream("binance:usdtPerp:BTCUSDT",1,true,now);a
 }
 fn add(a:&mut Acc,price:f64,usd:f64,token:Option<&str>,at:i64) {a.add("binance:usdtPerp:BTCUSDT",price,usd,true,token,at,at,Some(100.0));}

 #[test] fn only_real_big_trades_count_and_real_ids_dedupe_without_collapsing_equal_trades() {
  let mut a=acc("ZZINSIDS",60_000);
  add(&mut a,60_001.0,99.0,Some("small"),60_001);
  add(&mut a,60_001.0,100.0,Some("one"),60_001);
  add(&mut a,60_001.0,100.0,Some("one"),60_001);
  add(&mut a,60_001.0,100.0,Some("two"),60_001);
  add(&mut a,60_001.0,100.0,None,60_001);add(&mut a,60_001.0,100.0,None,60_001);
  let rows=a.roll(123_000,Some(100.0));
  assert_eq!(rows.len(),1);assert_eq!(rows[0].levels[0].buy,400.0);
  assert_eq!((rows[0].levels[0].first,rows[0].levels[0].last),(60_001,60_001));
  assert_eq!(rows[0].seen.values().map(Vec::len).sum::<usize>(),2);
 }
 #[test] fn restart_restores_replay_ids_but_does_not_claim_old_coverage() {
  let mut a=acc("ZZINSRESTART",60_000);add(&mut a,60_001.0,100.0,Some("one"),60_001);
  let old=a.take(90_000).remove(0);
  let mut b=acc("ZZINSRESTART",90_000);b.restore_minute(&old);
  add(&mut b,60_001.0,100.0,Some("one"),90_001);add(&mut b,60_002.0,200.0,Some("two"),90_002);
  let mut merged=old;merged.merge(b.roll(123_000,Some(100.0)).remove(0));
  assert_eq!(merged.levels.iter().map(|l|l.buy).sum::<f64>(),300.0);
  let s=summary("BTC",123_000,true,Some(100.0),&[merged],&live("ZZINSRESTART"));
  assert_eq!(s.coverage_since_ms,None,"重启后的首个半分钟不能算完整分钟");
 }
 #[test] fn disconnects_write_loss_and_missing_minutes_never_claim_continuity() {
  let mut a=acc("ZZINSGAP",60_000);add(&mut a,60_001.0,100.0,Some("one"),60_001);
  let first=a.roll(123_000,Some(100.0));
  assert!(summary("BTC",123_000,true,None,&first,&live("ZZINSGAP")).coverage_since_ms.is_some());
  a.stream("binance:usdtPerp:BTCUSDT",1,false,124_000);
  assert_eq!(summary("BTC",124_000,true,None,&first,&live("ZZINSGAP")).coverage_since_ms,None);
  a.stream("binance:usdtPerp:BTCUSDT",2,true,130_000);
  a.roll(130_000,Some(100.0));
  let second=a.roll(183_000,Some(100.0));
  assert_eq!(summary("BTC",183_000,true,None,&second,&live("ZZINSGAP")).coverage_since_ms,None,"恢复所在半分钟不能算完整");
  gap("ZZINSGAP",184_000);
  assert_eq!(summary("BTC",184_000,true,None,&second,&live("ZZINSGAP")).coverage_since_ms,None);
  assert_eq!(summary("BTC",243_000,true,None,&second,&Live{since:Some(130_000),fault:0}).coverage_since_ms,None,"最后完整分钟缺失");
 }
 #[test] fn beijing_day_and_completed_minute_boundaries_are_exact() {
  let midnight=100*store::DAY_MS-8*3_600_000;
  assert_eq!(day_start(midnight),midnight);assert_eq!(day_start(midnight-1),midnight-store::DAY_MS);
  assert_eq!(window_end(122_999),60_000);assert_eq!(window_end(123_000),120_000);
 }
 #[test] fn zones_merge_adjacent_buckets_only_inside_one_book_and_windows_cross_midnight() {
  let now=100*store::DAY_MS-8*3_600_000+123_000;
  let day=day_start(now);let make=|minute_ms,venue:&str,bucket,buy|Minute{minute_ms,coverage_since:Some(day-60_000),observed_until:minute_ms+MINUTE_MS,last_trade:Some(minute_ms+10),
   seen:BTreeMap::new(),watermarks:BTreeMap::new(),levels:vec![Level{venue_id:venue.into(),exchange:"币安".into(),product:"usdtPerp".into(),step:10.0,bucket,buy,sell:0.0,first:minute_ms+10,last:minute_ms+10}]};
  let rows=vec![make(day-60_000,"a",6000,50.0),make(day,"a",6000,100.0),make(day+60_000,"a",6001,200.0),make(day+60_000,"b",6001,300.0)];
  let s=summary("BTC",now,true,Some(100.0),&rows,&Live{since:Some(day-60_000),fault:0});
  assert_eq!(s.windows[0].sources.iter().map(|s|s.buy_usd).sum::<f64>(),650.0);
  assert_eq!(s.zones.len(),2);assert!(s.zones.iter().all(|z|z.buy_usd==300.0));
  let a=s.zones.iter().find(|z|z.venue_id=="a").unwrap();
  assert_eq!((a.low,a.high,a.first_ms,a.last_ms),(60_000.0,60_020.0,day+10,day+60_010));
 }
 #[test] fn source_windows_and_zone_counts_are_bounded_and_wire_names_match() {
  let mut rows=vec![];
  for v in 0..8 {for bucket in 0..5 {
   let mut m=Minute::new(60_000);m.observed_until=120_000;
   m.levels.push(Level{venue_id:format!("v{v}"),exchange:"币安".into(),product:"spot".into(),step:1.0,bucket:bucket*2,buy:(bucket+1) as f64,sell:0.0,first:60_001,last:60_002});rows.push(m);
  }}
  for m in &mut rows {m.coverage_since=Some(60_000);}
  let s=summary("BTC",123_000,true,Some(100.0),&rows,&Live{since:Some(60_000),fault:0});
  assert_eq!(s.zones.len(),12);
  for v in 0..8 {assert!(s.zones.iter().filter(|z|z.venue_id==format!("v{v}")).count()<=3);}
  let json=serde_json::to_value(&s).unwrap();
  for key in ["base","generatedAtMs","dayStartMs","tracked","coverageSinceMs","lastTradeMs","bigUsd","windows","zones"] {assert!(json.get(key).is_some(),"{key}");}
  assert_eq!(json["windows"][0]["sources"][0]["venueID"],"v0");assert!(json["zones"][0].get("recentBuyUsd").is_some());
  let response=answer(&s,true).unwrap().response();
  assert_eq!(response.headers()[axum::http::header::CACHE_CONTROL],CACHE_CONTROL);
  assert_eq!(response.headers()[axum::http::header::CONTENT_ENCODING],"gzip");
 }
 #[test] fn delivery_and_thresholdless_periods_are_excluded() {
  let mut a=acc("ZZINSCUT",60_000);a.register(&venue("binance:delivery:BTCQ","delivery"),0.1);
  a.add("binance:delivery:BTCQ",60_000.0,1000.0,true,Some("a"),60_001,60_001,Some(100.0));
  a.add("binance:usdtPerp:BTCUSDT",60_000.0,1000.0,true,Some("b"),60_001,60_001,None);
  let rows=a.roll(123_000,None);
  assert!(rows.iter().all(|m|m.levels.is_empty()&&m.coverage_since.is_none()));
 }
 #[test] fn a_gap_inside_history_cuts_coverage_even_when_the_latest_minute_exists() {
  let mut rows=vec![];
  for minute in [60_000,120_000,240_000,300_000] {
   let mut m=Minute::new(minute);m.coverage_since=Some(60_000);m.observed_until=minute+MINUTE_MS;rows.push(m);
  }
  let state=Live{since:Some(60_000),fault:0};
  assert_eq!(coverage_since(&rows,&state,360_000),Some(240_000));
  rows[2].coverage_since=None;
  assert_eq!(coverage_since(&rows,&state,360_000),Some(300_000),"坏行 / 未知覆盖一样截断");
 }
 #[test] fn continuous_daywide_price_bands_become_bounded_local_peaks() {
  let mut m=Minute::new(60_000);m.coverage_since=Some(60_000);m.observed_until=120_000;
  for bucket in 0..100 {m.levels.push(Level{venue_id:"a".into(),exchange:"币安".into(),product:"spot".into(),step:10.0,bucket,buy:if bucket==30 {1_000.0} else {1.0},sell:0.0,first:60_001,last:60_002});}
  let s=summary("BTC",123_000,true,None,&[m],&Live{since:Some(60_000),fault:0});
  assert_eq!(s.zones.len(),3);assert!(s.zones.iter().all(|z|z.high-z.low<=50.0+1e-9));
  assert!(s.zones.iter().any(|z|z.low<=300.0&&z.high>300.0&&z.buy_usd==1004.0));
  for (i,a) in s.zones.iter().enumerate() {for b in &s.zones[i+1..] {assert!(a.high<=b.low||b.high<=a.low);}}
 }
 #[test] fn busy_small_trades_and_monotonic_big_ids_do_not_exhaust_the_hash_budget() {
  let mut a=acc("ZZINSBUSY",60_000);
  for i in 0..10_000 {add(&mut a,60_001.0,1.0,Some(&i.to_string()),60_001);}
  for i in 10_000..11_000 {add(&mut a,60_001.0,100.0,Some(&i.to_string()),60_002);}
  let rows=a.roll(123_000,Some(100.0));
  assert_eq!(rows[0].levels[0].buy,100_000.0);
  assert!(rows[0].seen.is_empty());assert_eq!(rows[0].watermarks.len(),1);
  assert_eq!(summary("BTC",123_000,true,None,&rows,&live("ZZINSBUSY")).coverage_since_ms,Some(60_000));
 }
 #[test] fn overlapping_connection_rotation_preserves_coverage_but_a_real_disconnect_resets_it() {
  let mut a=acc("ZZINSROTATE",60_000);add(&mut a,60_001.0,100.0,Some("1"),60_001);
  a.stream("binance:usdtPerp:BTCUSDT",2,true,90_000);
  a.stream("binance:usdtPerp:BTCUSDT",1,false,95_000);
  let rows=a.roll(123_000,Some(100.0));
  assert_eq!(summary("BTC",123_000,true,None,&rows,&live("ZZINSROTATE")).coverage_since_ms,Some(60_000));
  a.stream("binance:usdtPerp:BTCUSDT",2,false,124_000);
  assert_eq!(live("ZZINSROTATE").since,None);
 }
 #[test] fn missing_null_or_malformed_metadata_returns_an_error_without_panicking() {
  for value in [serde_json::json!({}),serde_json::Value::Null,serde_json::json!({"observed_until":null}),
   serde_json::json!({"observed_until":"bad"}),serde_json::json!({"observed_until":120_001}),serde_json::json!({"observed_until":120_000,"coverage_since":"bad"})] {
   assert!(metadata_minute(60_000,value).is_err());
  }
  let missing_coverage=metadata_minute(60_000,serde_json::json!({"observed_until":120_000})).unwrap();
  assert_eq!(coverage_since(&[missing_coverage],&Live{since:Some(60_000),fault:0},120_000),None);
 }
 #[tokio::test] async fn untracked_api_is_read_only_and_validates_queries_without_database_access() {
  use axum::{body::Body,http::{Request,StatusCode}};
  use tower::ServiceExt;
  use std::sync::Arc;
  let pool=sqlx::postgres::PgPoolOptions::new().connect_lazy("postgres://unused:unused@127.0.0.1:1/unused").unwrap();
  let secrets=Arc::new(crate::crypto::Secrets{pepper:vec![1;32],encryption:[2;32]});
  let state=AppState{pool,secrets,dummy_hash:Arc::new(String::new())};
  let app=super::super::routes().with_state(state);
  for (query,status) in [("base=ZZINSREADONLY",StatusCode::OK),("base=btc",StatusCode::BAD_REQUEST),("base=BTC&from=1",StatusCode::BAD_REQUEST)] {
   let response=app.clone().oneshot(Request::builder().uri(format!("{PATH}?{query}")).body(Body::empty()).unwrap()).await.unwrap();
   assert_eq!(response.status(),status);
   if status==StatusCode::OK {
    let body=axum::body::to_bytes(response.into_body(),10_000).await.unwrap();
    let json:serde_json::Value=serde_json::from_slice(&body).unwrap();
    assert_eq!(json["tracked"],false);assert_eq!(json["zones"],serde_json::json!([]));assert_eq!(json["coverageSinceMs"],serde_json::Value::Null);
    assert!(!REGISTRY.get().is_some_and(|r|r.is_tracked("ZZINSREADONLY")));
   }
  }
 }
 #[tokio::test] async fn postgres_merges_partial_minutes_and_purges_three_days() {
  let Some(pool)=store::tests::isolated_pool().await else {return};
  let base="ZZINSDB";let now=100*store::DAY_MS;
  sqlx::query("DELETE FROM orderflow_insights WHERE base=$1").bind(base).execute(&pool).await.unwrap();
  store::start(&pool,base,now).await.unwrap();
  let mut a=acc(base,now-60_000);add(&mut a,60_001.0,100.0,Some("one"),now-59_999);
  let first=a.take(now-30_000);
  minutes::write(&pool,first.into_iter().map(|m|(base.into(),m)).collect()).await.unwrap();
  let mut b=acc(base,now-30_000);b.restore(&pool,now-30_000).await.unwrap();
  add(&mut b,60_001.0,100.0,Some("one"),now-29_999);add(&mut b,60_002.0,200.0,Some("two"),now-29_998);
  let second=b.roll(now+3_000,Some(100.0));
  minutes::write(&pool,second.into_iter().map(|m|(base.into(),m)).collect()).await.unwrap();
  let rows=read(&pool,base,now-60_000,now).await.unwrap();
  assert_eq!(rows.iter().flat_map(|m|&m.levels).map(|l|l.buy).sum::<f64>(),300.0);
  let mut old=Minute::new(now-store::RETENTION_MS-MINUTE_MS);old.observed_until=old.minute_ms+MINUTE_MS;
  minutes::write(&pool,vec![(base.into(),old)]).await.unwrap();
  assert!(purge(&pool,now).await.unwrap()>=1);
  assert_eq!(read(&pool,base,0,now-60_001).await.unwrap().len(),0);
 }
 #[tokio::test] async fn postgres_compact_snapshot_matches_full_history_and_rejects_broken_metadata() {
  let Some(pool)=store::tests::isolated_pool().await else {return};
  let base="ZZINSCOMPACT";let now=100*store::DAY_MS-8*3_600_000+32*MINUTE_MS+3_000;
  let day=day_start(now);let state=Live{since:Some(day-10*MINUTE_MS),fault:0};
  store::start(&pool,base,now).await.unwrap();
  let mut original=vec![];
  for i in -10..32 {
   let minute=day+i*MINUTE_MS;let mut m=Minute::new(minute);m.coverage_since=state.since;m.observed_until=minute+MINUTE_MS;m.last_trade=Some(minute+1);
   for (venue,product,bucket,buy) in [("a","spot",6000,100.0),("b","usdtPerp",6001,200.0)] {
    m.levels.push(Level{venue_id:venue.into(),exchange:"币安".into(),product:product.into(),step:10.0,bucket,buy,sell:10.0,first:minute+1,last:minute+2});
    m.seen.insert(venue.into(),vec![format!("dedup{i}")]);
   }
   original.push(m);
  }
  minutes::write(&pool,original.iter().cloned().map(|m|(base.into(),m)).collect()).await.unwrap();
  let compact=read_compact(&pool,base,day-60*MINUTE_MS,now,&state).await.unwrap();
  assert!(compact.iter().all(|m|m.seen.is_empty()));
  assert_eq!(summary(base,now,true,Some(100.0),&compact,&state),summary(base,now,true,Some(100.0),&original,&state));
  assert!(compact.iter().map(|m|m.levels.len()).sum::<usize>()<=10,"每个窗口档立即归并价桶");
  sqlx::query("UPDATE orderflow_insights SET payload='{}'::jsonb WHERE base=$1 AND minute_ms=$2").bind(base).bind(day+30*MINUTE_MS).execute(&pool).await.unwrap();
  assert!(read_compact(&pool,base,day-60*MINUTE_MS,now,&state).await.is_err(),"缺失覆盖字段须返回错误，不能崩请求 / 宣称完整");
 }
}
