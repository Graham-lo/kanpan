//! 深度热力快照（2026-09-29，网页版大屏的深度热力图）。
//!
//! * 落库：跟踪任务每 5 秒（对齐到墙钟 5 秒格的中间）把手里每本就绪簿中间价 ±5% 以内按这只的步长分桶，
//!   同一交易所同一产品的几本簿（交割好几期）合成一条带子；名义不到该产品门槛 5% 的那一侧记 0，两侧都是 0 的桶不写，
//!   空带子不写。交给全进程一个写库任务，攒一批用一条多行 INSERT 写进 `orderflow_heat`（一条带子一行，桶在数组里，见 0033）。
//!   写库占 `WRITE_SLOTS` 的一条；通道满了（库慢）就丢这一拍的快照，不堵跟踪任务。
//! * 清理：每小时和订单流的滚动清理一起，逐只 base 按主键删 3 天以前的；表超过 36 GB 再按时间往前删到约 32 GB。
//! * 接口 `GET /v1/market/orderflow/heat?base=&from=&to=&step=` → `{"step","bucketMs","rows":[[t_ms,price,bid_usd,ask_usd],…]}`：
//!   三家合起来；价格按 `max(step, 存储步长)` 向下取整合并（同一时刻各桶相加）；时间按 `bucketMs` 合并（取这一格里各快照的平均，
//!   某个快照里没有这个桶按 0 算）。`to` 缺省此刻、`from` 缺省 `to` 前 1 小时，超过 3 天把 `from` 夹到 `to` 前 3 天。
//!   行数估出来超过 20 万就把 `bucketMs` 放大到 10 s / 30 s / 60 s（3 天全量在 60 s 也装不下，再往上 2.5 / 5 / 15 / 30 / 60 分钟），
//!   放大之后隔几个快照取一个（每格至少 4 个），读完还超就再放大一档。没在跟的 base 回空 `rows`。只聚合，不判定。
//! * 收窄（2026-09-29，网页版按可见窗口取）：再带 `lo`/`hi`（价格上下沿）或 `around`/`pct`（以某价为中心 ±pct%，
//!   `pct` 缺省 5、最大 50）只回这段价格里的格；带 `bucketMs` 是时间格的下限提示（取梯子上不细于它、又装得下的最细一档）。
//!   带了其中任何一个就按收窄的额度算：一次最多 1.4 万行（约 500 KB 原文）、最多取 720 个快照，估行数不加漂移余量（超了读的时候原地放大）；
//!   都不带的老请求照旧 20 万行。
//!   快照按主键点查（`bucket_ms = ANY(数组)`，不走 `generate_series` 连接——那样计划器只按 base 扫整只）。
//!   同样的请求 5 秒内合成一次读库（缺省的 `to` 取整到 5 秒格），答复带 `Cache-Control: public, max-age=5`。
//! * 预聚合（2026-09-30，C 路压测「热力冷读慢」的根因修复，0038）：原来读几小时到三天要在十几 GB 的原始表里点查几百个快照，
//!   冷页随机读，2 并发 p95 约 3 秒。现在后台每 30 秒把收完的时间段并成段（30 秒 ← 原始快照、150 秒 ← 30 秒、900 秒 ← 150 秒），
//!   一段一只 base 一个步长一行，存各桶名义的总和与快照数。读的时候时间格是哪一段的整数倍就读那一段（900 秒一格读三天只要约 300 行），
//!   段没盖到的头尾（区间起点没对齐、最近还没并的几十秒）用细一级的段、最后用原始快照补。格里仍是「各快照取平均、没有这个桶按 0 算」：
//!   段里记的是所有快照的总和与个数，比原来隔几个取一个更准；接口的参数、形状、梯子、缓存头一律不变。
use super::book::{Buckets,Side,bucket_index};
use super::model::{Model,Thresholds};
use super::{Answer,Answers,HISTORY_READS,POOL,REGISTRY,WRITE_SLOTS,accepts_gzip,json_number as number,now_ms,packed,store};
use crate::AppState;
use crate::error::{ApiError,Params,Result};
use crate::orderflow_instruments as instruments;
use axum::extract::State;
use axum::response::Response;
use futures_util::TryStreamExt;
use serde::Deserialize;
use sqlx::{PgPool,Row};
use std::collections::{BTreeMap,HashMap};
use std::sync::OnceLock;
use std::sync::atomic::{AtomicU64,Ordering};
use std::time::Duration;
use tokio::sync::mpsc;

pub(super) const PATH:&str="/v1/market/orderflow/heat";
/// 快照的时间格。
pub(super) const BUCKET_MS:i64=5_000;
/// 中间价两侧多宽（±5%）。
const RADIUS_BPS:f64=500.0;
/// 名义不到该产品门槛的这么多倍的桶不写。
const CUT_RATIO:f64=0.05;
/// 一次答复最多几行。
const MAX_ROWS:usize=200_000;
/// 收窄的请求（带价格范围或时间格提示）最多几行：一行约 34 字节，1.4 万行原文约 480 KB。
const SCOPED_ROWS:usize=14_000;
/// 收窄的请求最多取几个快照（一个快照约 9 行，720 个约 6500 行、库里几十毫秒）。
const SNAPSHOTS:i64=720;
/// `around` 两侧缺省多宽、最多多宽（百分比）。
const DEFAULT_PCT:f64=5.0;
const MAX_PCT:f64=50.0;
/// 同样的请求合成一次读库、答复留多久；也是答复头上 `max-age` 的秒数。
const HEAT_TTL:Duration=Duration::from_secs(5);
const CACHE_CONTROL:&str="public, max-age=5";
/// `from` 缺省 `to` 前多久。
const DEFAULT_SPAN_MS:i64=60*60_000;
const MAX_SPAN_MS:i64=store::RETENTION_MS;
/// 时间格一档一档放大：（格宽，隔多久取一个快照）。读的过程中超了原地并到后面第一个格宽是它整数倍的档（`next_level`）：
/// 2.5 分钟不是 60 秒的整数倍，60 秒超了直接并到 5 分钟；2.5 分钟是给「几小时、±5%」这种收窄请求留的，1.4 万行装得下。
const LADDER:[(i64,i64);9]=[(5_000,5_000),(10_000,5_000),(30_000,5_000),(60_000,15_000),(150_000,30_000),(300_000,60_000),(900_000,225_000),(1_800_000,450_000),(3_600_000,900_000)];
/// 按最近一个快照的桶数估行数时，给这段时间里价格漂出去的新桶留的余量。
const DRIFT:f64=1.5;
/// 跟踪任务到写库任务的通道（一项是一只 base 一拍的带子）：220 只一起交也放得下四轮。
const QUEUE:usize=1024;
/// 一条 INSERT 最多几行（每行 9 个参数，Postgres 一条最多 65535 个）。
const INSERT_ROWS:usize=1_000;
/// 写库任务一次最多攒多少行。
const PENDING_CAP:usize=20_000;
/// 清理一批删多少行（一行几 KB）。
const DELETE_BATCH:i64=5_000;
/// 体积闸门：表（含索引）超过这么大，按时间往前删到估出来的实际占用低于目标。
const GATE_BYTES:f64=36.0*1024.0*1024.0*1024.0;
const GATE_TARGET:f64=32.0*1024.0*1024.0*1024.0;
/// 写库统计多久打一行日志。
const REPORT:Duration=Duration::from_secs(10*60);
/// 预聚合的段宽（细到粗）：150 秒不是 60 秒的整数倍，所以 30 秒这一档既给 30 / 60 秒格用，也是 150 秒段的来源；
/// 梯子上 30 秒以上的每一档都是其中某一档的整数倍。
pub(super) const ROLLUPS:[i64;3]=[30_000,150_000,900_000];
/// 一段收完之后再等多久才并（写库任务慢一点、跟踪任务晚一拍的快照还能赶上）。
const ROLL_GRACE:i64=30_000;
/// 后台并段多久看一次；落后时（刚部署、重启后）一段一段追，中间只歇一小会。
const ROLL_EVERY:Duration=Duration::from_secs(30);
const ROLL_CATCHUP_PAUSE:Duration=Duration::from_millis(500);
/// 追的时候一条语句最多并多长：原始快照 10 分钟（约 6 万行），段 6 小时。
const RAW_SLICE:i64=10*60_000;
const ROLLUP_SLICE:i64=6*3_600_000;
/// 同一段连着失败几次就跳过（坏数据不能把后面的段永远堵住）。
const ROLL_GIVE_UP:u32=5;

/// 一只 base 在一家一个产品上一个快照的带子（库里一行）。
#[derive(Clone,Debug,PartialEq)]
pub(super) struct Band {
 pub base:String,
 pub exchange:&'static str,
 pub product:&'static str,
 pub bucket_ms:i64,
 pub step:f64,
 pub lo:i64,
 pub offsets:Vec<i32>,
 pub bids:Vec<f32>,
 pub asks:Vec<f32>,
}

/// 下一个快照在什么时候拍（跟踪任务的节拍）：对齐到墙钟 5 秒格的中间，跟踪任务手里的抖动不至于两拍落进同一格。
pub(super) fn first_tick(now:i64)->Duration {
 let at=now.div_euclid(BUCKET_MS)*BUCKET_MS+BUCKET_MS/2;
 let at=if at<=now {at+BUCKET_MS} else {at};
 Duration::from_millis((at-now) as u64)
}

/// 此刻这只 base 的一拍快照（步长还没有就是空的；门槛为空的产品——非币标定之前的 U 本位——跳过）。
pub(super) fn snapshot(model:&mut Model,now:i64)->Vec<Band> {
 let Some(step)=model.thresholds.step.filter(|s|s.is_finite()&&*s>0.0) else {return Vec::new()};
 let thresholds=model.thresholds;
 let bands=model.bands(step,RADIUS_BPS);
 fold(&model.base,&thresholds,step,now.div_euclid(BUCKET_MS)*BUCKET_MS,bands)
}

/// 各本簿的桶 → 按（交易所，产品）合成带子，按门槛 5% 过滤。
pub(super) fn fold(base:&str,thresholds:&Thresholds,step:f64,bucket_ms:i64,books:Vec<(&'static str,&'static str,Buckets)>)->Vec<Band> {
 let mut groups:BTreeMap<(&'static str,&'static str),BTreeMap<i64,(f64,f64)>>=BTreeMap::new();
 for (exchange,product,buckets) in books {
  if thresholds.of(product).is_none() {continue}
  let group=groups.entry((exchange,product)).or_default();
  for ((side,index),bucket) in buckets {
   let cell=group.entry(index).or_default();
   match side {Side::Bid=>cell.0+=bucket.notional,Side::Ask=>cell.1+=bucket.notional}
  }
 }
 let mut out=Vec::new();
 for ((exchange,product),cells) in groups {
  let cut=thresholds.of(product).unwrap_or(0.0)*CUT_RATIO;
  let keep=|v:f64|if v>=cut&&v>0.0 {v as f32} else {0.0};
  let kept:Vec<(i64,f32,f32)>=cells.into_iter().map(|(i,(b,a))|(i,keep(b),keep(a))).filter(|(_,b,a)|*b>0.0||*a>0.0).collect();
  let Some(&(lo,_,_))=kept.first() else {continue};
  let mut band=Band{base:base.to_string(),exchange,product,bucket_ms,step,lo,offsets:Vec::with_capacity(kept.len()),bids:Vec::with_capacity(kept.len()),asks:Vec::with_capacity(kept.len())};
  for (i,b,a) in kept {
   let Ok(offset)=i32::try_from(i-lo) else {continue};
   band.offsets.push(offset);band.bids.push(b);band.asks.push(a);
  }
  out.push(band);
 }
 out
}

// ------------------------------------------------------------------ 写库

static TX:OnceLock<mpsc::Sender<Vec<Band>>>=OnceLock::new();
/// 通道满了丢掉的带子数（写库统计日志里报）。
static DROPPED:AtomicU64=AtomicU64::new(0);

/// 起写库任务与后台并段任务（serve 进程起订单流时一次）。
pub(super) fn start(pool:PgPool) {
 TX.get_or_init(||{
  let (tx,rx)=mpsc::channel(QUEUE);
  tokio::spawn(writer(pool.clone(),rx));
  crate::supervise::spawn_restarting("orderflow-heat-rollup",move ||roller(pool.clone()));
  tx
 });
}

/// 跟踪任务交一拍快照：不等，通道满了就丢。
pub(super) fn submit(bands:Vec<Band>) {
 if bands.is_empty() {return}
 let Some(tx)=TX.get() else {return};
 let n=bands.len() as u64;
 if tx.try_send(bands).is_err() {DROPPED.fetch_add(n,Ordering::Relaxed);}
}

#[derive(Default)]
struct Stats {rows:u64,buckets:u64,bytes:u64,failed:u64,statements:u64,busy:Duration}

async fn writer(pool:PgPool,mut rx:mpsc::Receiver<Vec<Band>>) {
 let mut stats=Stats::default();
 let mut report=tokio::time::Instant::now()+REPORT;
 let mut warned:Option<tokio::time::Instant>=None;
 while let Some(first)=rx.recv().await {
  let mut rows=first;
  while rows.len()<PENDING_CAP && let Ok(more)=rx.try_recv() {rows.extend(more);}
  let Ok(_slot)=WRITE_SLOTS.acquire().await else {return};
  let started=tokio::time::Instant::now();
  for chunk in rows.chunks(INSERT_ROWS) {
   match insert(&pool,chunk).await {
    Ok(())=>{
     stats.rows+=chunk.len() as u64;stats.statements+=1;
     for b in chunk {stats.buckets+=b.offsets.len() as u64;stats.bytes+=row_bytes(b) as u64;}
    },
    Err(e)=>{
     stats.failed+=chunk.len() as u64;
     if warned.is_none_or(|at|at.elapsed()>=Duration::from_secs(60)) {warned=Some(tokio::time::Instant::now());tracing::warn!("Orderflow heat: write failed, {} bands dropped: {e}",chunk.len());}
    },
   }
  }
  stats.busy+=started.elapsed();
  drop(_slot);
  if tokio::time::Instant::now()>=report {
   let secs=REPORT.as_secs_f64();
   tracing::info!("Orderflow heat: last {}s wrote {} bands / {} buckets ({:.1} bands/s, ~{:.1} MB/day of rows) in {} statements, {:.1}s busy; dropped {} (queue full), {} (write failed)",
    REPORT.as_secs(),stats.rows,stats.buckets,stats.rows as f64/secs,stats.bytes as f64/secs*86_400.0/1e6,stats.statements,stats.busy.as_secs_f64(),DROPPED.swap(0,Ordering::Relaxed),stats.failed);
   stats=Stats::default();
   report=tokio::time::Instant::now()+REPORT;
  }
 }
}

/// 一行在堆里大约多大：行头与定长列约 60 字节，三个数组各 24 字节头，每桶 12 字节；另加主键索引一项约 50 字节。
fn row_bytes(b:&Band)->usize {60+b.base.len()+b.exchange.len()+b.product.len()+3*24+12*b.offsets.len()+50}

async fn insert(pool:&PgPool,rows:&[Band])->sqlx::Result<()> {
 let mut q=sqlx::QueryBuilder::<sqlx::Postgres>::new("INSERT INTO orderflow_heat(base,exchange,product,bucket_ms,step,price_lo,price_bucket,bid_notional,ask_notional) ");
 q.push_values(rows,|mut b,r|{
  b.push_bind(&r.base).push_bind(r.exchange).push_bind(r.product).push_bind(r.bucket_ms).push_bind(r.step).push_bind(r.lo).push_bind(&r.offsets).push_bind(&r.bids).push_bind(&r.asks);
 });
 // 同一格里两拍（跟踪任务被拖慢时）留先到的那份。
 q.push(" ON CONFLICT(base,bucket_ms,exchange,product) DO NOTHING");
 q.build().execute(pool).await.map(|_|())
}

// ------------------------------------------------------------------ 预聚合

/// 一档段所在的分区表（0038）。
fn rollup_table(width:i64)->&'static str {
 match width {30_000=>"orderflow_heat_rollup_30s",150_000=>"orderflow_heat_rollup_150s",_=>"orderflow_heat_rollup_900s"}
}

/// 并段的后半截：来源 `src(base,t,step,price_lo,price_bucket,bid_notional,ask_notional)` 与每段快照数 `n(base,t,step,samples)`
/// 已经定义好，这里把各行的桶展开、同一（base，段，步长，桶）相加，再按桶号排好收成一行写进 `table`。
fn fold_sql(width:i64,table:&str)->String {
 format!("c AS (SELECT s.base,s.t,s.step,s.price_lo+u.o AS p,sum(u.b::float8) AS b,sum(u.a::float8) AS a \
   FROM src s CROSS JOIN LATERAL unnest(s.price_bucket,s.bid_notional,s.ask_notional) AS u(o,b,a) GROUP BY 1,2,3,4), \
  m AS (SELECT c.*,min(c.p) OVER (PARTITION BY c.base,c.t,c.step) AS lo FROM c), \
  g AS (SELECT base,t,step,lo,array_agg((p-lo)::int ORDER BY p) AS o,array_agg(b::real ORDER BY p) AS bb,array_agg(a::real ORDER BY p) AS aa FROM m GROUP BY 1,2,3,4) \
  INSERT INTO {table}(base,width_ms,bucket_ms,step,samples,price_lo,price_bucket,bid_notional,ask_notional) \
  SELECT g.base,{width},g.t,g.step,n.samples,g.lo,g.o,g.bb,g.aa FROM g JOIN n USING(base,t,step) ON CONFLICT DO NOTHING")
}

/// 原始快照 → 30 秒段：逐只 base 按主键取这段时间（主键头是 base，不带 base 的时间范围走不了索引）。
fn raw_roll_sql()->String {
 let w=ROLLUPS[0];
 format!("WITH src AS (SELECT h.base,h.bucket_ms-h.bucket_ms%{w} AS t,h.bucket_ms AS snap,h.step,h.price_lo,h.price_bucket,h.bid_notional,h.ask_notional \
   FROM unnest($1::text[]) b(base) CROSS JOIN LATERAL (SELECT * FROM orderflow_heat h WHERE h.base=b.base AND h.bucket_ms>=$2 AND h.bucket_ms<$3) h), \
  n AS (SELECT base,t,step,count(DISTINCT snap)::int AS samples FROM src GROUP BY 1,2,3), {}",fold_sql(w,rollup_table(w)))
}

/// 细一级的段 → 这一级：快照数相加。
fn rollup_roll_sql(width:i64,lower:i64)->String {
 format!("WITH src AS (SELECT base,bucket_ms-bucket_ms%{width} AS t,samples,step,price_lo,price_bucket,bid_notional,ask_notional \
   FROM {} WHERE width_ms={lower} AND bucket_ms>=$1 AND bucket_ms<$2), \
  n AS (SELECT base,t,step,sum(samples)::int AS samples FROM src GROUP BY 1,2,3), {}",rollup_table(lower),fold_sql(width,rollup_table(width)))
}

/// 把 [a,b) 这段并成第 `k` 档（`ROLLUPS[k]`）的段；`bases` 只给第 0 档（从原始快照并）用。
/// 聚合在一个事务里、`work_mem` 放到 64 MB（缺省 4 MB 时十分钟的追赶会把分组溢出到磁盘），语句死线放到 2 分钟（冷盘追赶）。
async fn roll_range(pool:&PgPool,k:usize,bases:&[String],a:i64,b:i64)->sqlx::Result<u64> {
 let Ok(_slot)=WRITE_SLOTS.acquire().await else {return Ok(0)};
 let mut tx=pool.begin().await?;
 sqlx::query("SET LOCAL work_mem='64MB'").execute(&mut *tx).await?;
 sqlx::query("SET LOCAL statement_timeout='120s'").execute(&mut *tx).await?;
 let n=if k==0 {
  sqlx::query(&raw_roll_sql()).bind(bases).bind(a).bind(b).execute(&mut *tx).await?.rows_affected()
 } else {
  sqlx::query(&rollup_roll_sql(ROLLUPS[k],ROLLUPS[k-1])).bind(a).bind(b).execute(&mut *tx).await?.rows_affected()
 };
 tx.commit().await?;
 Ok(n)
}

/// 起来时从哪接着并：每档已有的最后一段之后；一段都没有就从原始快照最早的那格起（刚部署时把已有的都追上），
/// 表是空的就从此刻起。3 天以前的（已经清掉的）不追。
///
/// 最早那格只在某档一段都没有时才去查：每只 base 的 `min(bucket_ms)` 落在主键里这只 base 最旧的那一头，
/// 正是每小时清理刚删掉的那一截（死索引项要逐条回表确认），平时各档都有段，用不着它。
async fn resume(pool:&PgPool,bases:&[String],now:i64)->sqlx::Result<[i64;3]> {
 let mut lasts=[None;3];
 for (k,&w) in ROLLUPS.iter().enumerate() {
  lasts[k]=sqlx::query_scalar::<_,Option<i64>>(&format!("SELECT max(bucket_ms) FROM {} WHERE width_ms={w}",rollup_table(w))).fetch_one(pool).await?;
 }
 let first:Option<i64>=if lasts.iter().all(Option::is_some) {None} else {
  sqlx::query_scalar("SELECT min(m) FROM unnest($1::text[]) b(base) CROSS JOIN LATERAL (SELECT min(bucket_ms) AS m FROM orderflow_heat WHERE base=b.base) x")
   .bind(bases).fetch_one(pool).await?
 };
 let mut done=[0;3];
 for (k,&w) in ROLLUPS.iter().enumerate() {
  let start=lasts[k].map(|t|t+w).or(first).unwrap_or(now-ROLL_GRACE).max(now-store::RETENTION_MS);
  done[k]=start.div_euclid(w)*w;
 }
 Ok(done)
}

/// 并段的进度与连着失败的次数。
struct Roller {done:[i64;3],failures:[u32;3]}

impl Roller {
 /// 每档此刻能并到哪（不含）：30 秒段要这一段收完再过 `ROLL_GRACE`；粗的要细一级已经并到。
 fn ready(&self,k:usize,now:i64)->i64 {
  let w=ROLLUPS[k];
  if k==0 {(now-ROLL_GRACE).div_euclid(w)*w} else {self.done[k-1].div_euclid(w)*w}
 }

 /// 一轮：每档往前并一截。返回还落不落后（落后就马上接着来）。
 async fn step(&mut self,pool:&PgPool,now:i64)->sqlx::Result<bool> {
  let bases=store::bases(pool).await?;
  let mut behind=false;
  for (k,&w) in ROLLUPS.iter().enumerate() {
   let floor=(now-store::RETENTION_MS).div_euclid(w)*w;
   self.done[k]=self.done[k].max(floor);
   let ready=self.ready(k,now);
   if self.done[k]>=ready {continue}
   let end=ready.min(self.done[k]+if k==0 {RAW_SLICE} else {ROLLUP_SLICE});
   match roll_range(pool,k,&bases,self.done[k],end).await {
    Ok(_)=>{self.done[k]=end;self.failures[k]=0;},
    Err(e)=>{
     self.failures[k]+=1;
     if self.failures[k]<ROLL_GIVE_UP {return Err(e)}
     tracing::warn!("Orderflow heat: rollup {w} ms of [{}, {end}) failed {ROLL_GIVE_UP} times, skipped: {e}",self.done[k]);
     self.done[k]=end;self.failures[k]=0;
    },
   }
   behind|=end<ready;
  }
  Ok(behind)
 }
}

/// 后台并段任务：起来先定进度，之后每 30 秒并一轮；落后时一截接一截追。
async fn roller(pool:PgPool) {
 let mut warned:Option<tokio::time::Instant>=None;
 let mut warn=|what:&str,e:sqlx::Error|if warned.is_none_or(|at|at.elapsed()>=Duration::from_secs(600)) {
  warned=Some(tokio::time::Instant::now());tracing::warn!("Orderflow heat: rollup {what} failed: {e}");
 };
 let mut roller=loop {
  let now=now_ms();
  match async {let bases=store::bases(&pool).await?;resume(&pool,&bases,now).await}.await {
   Ok(done)=>break Roller{done,failures:[0;3]},
   Err(e)=>{warn("resume",e);tokio::time::sleep(ROLL_EVERY).await;},
  }
 };
 tracing::info!("Orderflow heat: rollup resumes at {:?}",roller.done);
 loop {
  let pause=match roller.step(&pool,now_ms()).await {
   Ok(true)=>ROLL_CATCHUP_PAUSE,
   Ok(false)=>ROLL_EVERY,
   Err(e)=>{warn("step",e);ROLL_EVERY},
  };
  tokio::time::sleep(pause).await;
 }
}

/// 这只 base 每档段盖到哪（不含）：最后一段之后。后台是一截时间里所有 base 一起并的，所以最后一段之前没有段的格就是真没有快照。
async fn coverage(pool:&PgPool,base:&str)->sqlx::Result<[Option<i64>;3]> {
 let sql=format!("SELECT {}",ROLLUPS.map(|w|format!("(SELECT max(bucket_ms) FROM {} WHERE base=$1 AND width_ms={w})",rollup_table(w))).join(","));
 let row=sqlx::query(&sql).bind(base).fetch_one(pool).await?;
 let mut out=[None;3];
 for (k,&w) in ROLLUPS.iter().enumerate() {out[k]=row.get::<Option<i64>,_>(k).map(|t|t+w);}
 Ok(out)
}

/// 一段 [lo,hi) 怎么读：时间格 `width` 是哪几档段的整数倍，就从粗到细用这几档（`covered` 是各档盖到哪），
/// 每档只取完整落在区间里、又已经并好的段，两头剩下的交给细一级，最后剩下的读原始快照。返回（段：（段宽，起，止）；原始：（起，止））。
fn pieces(lo:i64,hi:i64,width:i64,covered:&[Option<i64>;3])->(Vec<(i64,i64,i64)>,Vec<(i64,i64)>) {
 let plan:Vec<(i64,i64)>=ROLLUPS.iter().zip(covered).rev().filter_map(|(&r,end)|(width%r==0).then_some(*end).flatten().map(|e|(r,e))).collect();
 let (mut rolled,mut raw)=(Vec::new(),Vec::new());
 let mut todo=vec![(0usize,lo,hi)];
 while let Some((i,lo,hi))=todo.pop() {
  if lo>=hi {continue}
  let Some(&(r,end))=plan.get(i) else {raw.push((lo,hi));continue};
  let a=lo.div_euclid(r)*r+if lo.rem_euclid(r)==0 {0} else {r};
  let b=(hi.div_euclid(r)*r).min(end.div_euclid(r)*r);
  if a<b {rolled.push((r,a,b));todo.push((i+1,lo,a));todo.push((i+1,b,hi));} else {todo.push((i+1,lo,hi));}
 }
 rolled.sort();raw.sort();
 (rolled,raw)
}

/// 段的清理：和原始快照同一个截止时刻，按分区逐张删。
async fn delete_rollups_before(pool:&PgPool,cutoff:i64)->sqlx::Result<u64> {
 let mut deleted=0;
 for w in ROLLUPS {
  let table=rollup_table(w);
  loop {
   let n=sqlx::query(&format!("DELETE FROM {table} WHERE ctid=ANY(ARRAY(SELECT ctid FROM {table} WHERE width_ms={w} AND bucket_ms<$1 LIMIT $2))"))
    .bind(cutoff).bind(DELETE_BATCH).execute(pool).await?.rows_affected();
   deleted+=n;
   if n<DELETE_BATCH as u64 {break}
  }
 }
 Ok(deleted)
}

// ------------------------------------------------------------------ 清理

async fn delete_before(pool:&PgPool,base:&str,cutoff:i64)->sqlx::Result<u64> {
 let mut deleted=0;
 loop {
  let n=sqlx::query("DELETE FROM orderflow_heat WHERE ctid=ANY(ARRAY(SELECT ctid FROM orderflow_heat WHERE base=$1 AND bucket_ms<$2 LIMIT $3))")
   .bind(base).bind(cutoff).bind(DELETE_BATCH).execute(pool).await?.rows_affected();
  deleted+=n;
  if n<DELETE_BATCH as u64 {return Ok(deleted)}
 }
}

/// 表（含索引）此刻多大。
pub(super) async fn size(pool:&PgPool)->sqlx::Result<i64> {
 sqlx::query_scalar("SELECT pg_total_relation_size('orderflow_heat')").fetch_one(pool).await
}

/// 每小时一次：删 3 天以前的（预聚合的段同一个截止时刻一起删，返回两边合计删了几行）；表超过 `GATE_BYTES` 时按「行数 × 最近一行的平均大小」估实际占用，
/// 超过 `GATE_TARGET` 就把截止时刻往后挪（每次 6 小时）接着删。删掉的空间留给以后的插入用，文件不缩，所以不能直接拿文件大小判断。
pub(super) async fn purge(pool:&PgPool,now:i64)->sqlx::Result<u64> {
 let bases=store::bases(pool).await?;
 let mut deleted=0;
 for base in &bases {deleted+=delete_before(pool,base,now-store::RETENTION_MS).await?;}
 if size(pool).await? as f64>GATE_BYTES {
  let tuples:f32=sqlx::query_scalar("SELECT reltuples FROM pg_class WHERE oid='orderflow_heat'::regclass").fetch_one(pool).await?;
  let average:Option<f64>=sqlx::query_scalar("SELECT avg(pg_column_size(h.*))::float8 FROM orderflow_heat h WHERE base=ANY($1) AND bucket_ms>=$2")
   .bind(&bases).bind(now-60_000).fetch_one(pool).await?;
  let per_row=average.unwrap_or(2_000.0)+50.0;
  let mut rows=(tuples.max(0.0) as f64)-deleted as f64;
  let mut cutoff=now-store::RETENTION_MS;
  while rows*per_row>GATE_TARGET&&cutoff<now-store::DAY_MS/4 {
   cutoff+=store::DAY_MS/4;
   for base in &bases {let n=delete_before(pool,base,cutoff).await?;deleted+=n;rows-=n as f64;}
  }
  tracing::warn!("Orderflow heat: size gate trimmed to bucket_ms >= {cutoff}");
  deleted+=delete_rollups_before(pool,cutoff).await?;
  return Ok(deleted)
 }
 deleted+=delete_rollups_before(pool,now-store::RETENTION_MS).await?;
 Ok(deleted)
}

// ------------------------------------------------------------------ 接口

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct HeatQuery {
 base:String,from:Option<i64>,to:Option<i64>,step:Option<f64>,
 lo:Option<f64>,hi:Option<f64>,around:Option<f64>,pct:Option<f64>,
 #[serde(rename="bucketMs")] bucket_ms:Option<i64>,
}

/// 收窄的请求：价格范围（服务端价格，闭区间）与时间格下限提示。
#[derive(Clone,Copy,Debug,PartialEq)]
struct Scope {prices:Option<(f64,f64)>,hint:i64}

/// 新参数：`lo`/`hi` 与 `around`/`pct` 二选一（`pct` 离不开 `around`），`bucketMs` 要正的。都没带是老请求（`None`）。
fn scope(q:&HeatQuery)->std::result::Result<Option<Scope>,&'static str> {
 if q.lo.is_none()&&q.hi.is_none()&&q.around.is_none()&&q.pct.is_none()&&q.bucket_ms.is_none() {return Ok(None)}
 let price=|v:f64|v.is_finite()&&v>=0.0;
 let prices=match (q.lo,q.hi,q.around,q.pct) {
  (None,None,None,None)=>None,
  (Some(lo),Some(hi),None,None) if price(lo)&&price(hi)&&hi>lo=>Some((lo,hi)),
  (None,None,Some(c),pct) if c.is_finite()&&c>0.0=>{
   let pct=pct.unwrap_or(DEFAULT_PCT);
   if !(pct>0.0&&pct<=MAX_PCT) {return Err("invalid_price")}
   Some((c*(1.0-pct/100.0),c*(1.0+pct/100.0)))
  },
  _=>return Err("invalid_price"),
 };
 let hint=match q.bucket_ms {None=>BUCKET_MS,Some(v) if v>0=>v,Some(_)=>return Err("invalid_bucket")};
 Ok(Some(Scope{prices,hint}))
}

/// 校验并补齐区间：`to` 缺省此刻，`from` 缺省 `to` 前 1 小时；超过 3 天把 `from` 夹回来，不报错。
fn window(from:Option<i64>,to:Option<i64>,now:i64)->std::result::Result<(i64,i64),&'static str> {
 let to=to.unwrap_or(now);
 let from=from.unwrap_or(to.saturating_sub(DEFAULT_SPAN_MS));
 if from<0||to<0||from>to {return Err("invalid_range")}
 Ok((from.max(to-MAX_SPAN_MS),to))
}

/// 客户端的步长：缺省用存储步长，给了就得是正的有限数。
fn requested_step(step:Option<f64>)->std::result::Result<Option<f64>,&'static str> {
 match step {None=>Ok(None),Some(v) if v.is_finite()&&v>0.0=>Ok(Some(v)),Some(_)=>Err("invalid_step")}
}

/// 挑时间格：估出来的行数（格数 × 每格价格桶数 × 漂移余量）不超过上限的最细一档；都超就用最粗的。
fn pick_level(span:i64,prices:usize,cap:usize)->usize {pick_from(0,span,(prices.max(1) as f64)*DRIFT,cap)}

/// 从第 `min` 档起挑：估出来的行数（格数 × 每格价格桶数）不超过上限的最细一档；都超就用最粗的。
fn pick_from(min:usize,span:i64,prices:f64,cap:usize)->usize {
 let prices=prices.max(1.0);
 (min.min(LADDER.len()-1)..LADDER.len()).find(|&i|((span/LADDER[i].0+1) as f64)*prices<=cap as f64).unwrap_or(LADDER.len()-1)
}

/// 原地放大时并到哪一档：后面第一个格宽是这一档整数倍的（最粗那档是所有档的整数倍，总有）。
fn next_level(level:usize)->usize {
 (level+1..LADDER.len()).find(|&j|LADDER[j].0%LADDER[level].0==0).unwrap_or(LADDER.len()-1)
}

/// 时间格提示落到梯子上：不细于它的最细一档（比最粗的还粗就用最粗的）。
fn min_level(hint:i64)->usize {LADDER.iter().position(|(bucket,_)|*bucket>=hint).unwrap_or(LADDER.len()-1)}

/// 隔多久取一个快照：这一档自己的间隔；收窄的请求再保证这段最多取 `SNAPSHOTS` 个（取能整除格宽的最小间隔，
/// 每格取的个数一样）；区间比时间格还短时至少取 8 个。
fn stride(level:usize,span:i64,budget:bool)->i64 {
 let (width,own)=LADDER[level];
 let mut s=own;
 let want=span/SNAPSHOTS;
 if budget&&want>s {s=(1..=width/BUCKET_MS).map(|k|k*BUCKET_MS).find(|d|width%d==0&&*d>=want).unwrap_or(width);}
 s.min((span/8/BUCKET_MS*BUCKET_MS).max(BUCKET_MS))
}

/// 读出来的快照攒成答复：同一（时间格，价格桶）各快照、各家相加，每格记有几个快照，出的时候除掉（取平均）。
struct Heat {
 step:f64,
 level:usize,
 cap:usize,
 cells:BTreeMap<(i64,i64),(f64,f64)>,
 samples:HashMap<i64,u32>,
 last_snapshot:Option<i64>,
 /// 只收这段价格桶（按答复的步长，闭区间）；`None` 不限。
 range:Option<(i64,i64)>,
}

impl Heat {
 fn new(step:f64,level:usize,cap:usize)->Self {Self{step,level,cap,cells:BTreeMap::new(),samples:HashMap::new(),last_snapshot:None,range:None}}
 fn bucket_ms(&self)->i64 {LADDER[self.level].0}

 /// 一行（一家一个产品一个快照的带子）。行要按 `bucket_ms` 从早到晚来。
 fn add(&mut self,bucket_ms:i64,row_step:f64,lo:i64,offsets:&[i32],bids:&[f32],asks:&[f32]) {
  let t=bucket_ms.div_euclid(self.bucket_ms())*self.bucket_ms();
  if self.last_snapshot!=Some(bucket_ms) {self.last_snapshot=Some(bucket_ms);*self.samples.entry(t).or_default()+=1;}
  self.put(t,row_step,lo,offsets,bids,asks);
 }

 /// 一行预聚合的段（起点 `period`，里面 `samples` 个快照的总和）。段宽总能整除时间格，段整个落在一格里；行不用按时间来。
 #[allow(clippy::too_many_arguments)]
 fn add_rolled(&mut self,period:i64,samples:u32,row_step:f64,lo:i64,offsets:&[i32],bids:&[f32],asks:&[f32]) {
  let t=period.div_euclid(self.bucket_ms())*self.bucket_ms();
  *self.samples.entry(t).or_default()+=samples;
  self.put(t,row_step,lo,offsets,bids,asks);
 }

 /// 把一行的桶加进时间格 `t`（按答复的步长换桶、按价格范围过滤），超了上限原地放大时间格。
 fn put(&mut self,t:i64,row_step:f64,lo:i64,offsets:&[i32],bids:&[f32],asks:&[f32]) {
  let same=(row_step-self.step).abs()<=self.step*1e-12;
  for ((&o,&b),&a) in offsets.iter().zip(bids).zip(asks) {
   let index=lo+o as i64;
   let p=if same {index} else {bucket_index(index as f64*row_step,self.step)};
   if self.range.is_some_and(|(a,b)|p<a||p>b) {continue}
   let cell=self.cells.entry((t,p)).or_default();
   cell.0+=b as f64;cell.1+=a as f64;
  }
  while self.cells.len()>self.cap&&self.level+1<LADDER.len() {self.coarsen();}
 }

 /// 放大一档时间格（到下一个整数倍的档）：已经攒的原地并上去。
 fn coarsen(&mut self) {
  self.level=next_level(self.level);
  let width=self.bucket_ms();
  let mut cells=BTreeMap::new();
  for ((t,p),(b,a)) in std::mem::take(&mut self.cells) {
   let cell:&mut (f64,f64)=cells.entry((t.div_euclid(width)*width,p)).or_default();
   cell.0+=b;cell.1+=a;
  }
  let mut samples=HashMap::new();
  for (t,n) in std::mem::take(&mut self.samples) {*samples.entry(t.div_euclid(width)*width).or_default()+=n;}
  self.cells=cells;self.samples=samples;
 }

 /// 答复的行：`[t_ms, price, bid_usd, ask_usd]`，按时间、价格排好；名义取到整美元，两侧都不到 1 美元的不出。
 fn rows(&self)->Vec<(i64,f64,f64,f64)> {
  let decimals=decimals(self.step);
  self.cells.iter().filter_map(|(&(t,p),&(b,a))|{
   let n=self.samples.get(&t).copied().unwrap_or(1).max(1) as f64;
   let (b,a)=((b/n).round(),(a/n).round());
   (b>=1.0||a>=1.0).then(||(t,tidy(p as f64*self.step,decimals),b,a))
  }).collect()
 }
}

/// 步长有几位小数（最多 12 位）：价格按它四舍五入，免得 0.1 × 1233 写成 123.30000000000001。
fn decimals(step:f64)->i32 {
 (0..=12).find(|d|{let x=step*10f64.powi(*d);(x-x.round()).abs()<=1e-9*x.abs().max(1.0)}).unwrap_or(12)
}
fn tidy(v:f64,decimals:i32)->f64 {let k=10f64.powi(decimals);(v*k).round()/k}

fn body(step:f64,bucket_ms:i64,rows:&[(i64,f64,f64,f64)])->String {
 let mut out=String::with_capacity(48+rows.len()*36);
 out.push_str("{\"step\":");number(&mut out,step);
 out.push_str(",\"bucketMs\":");number(&mut out,bucket_ms as f64);
 out.push_str(",\"rows\":[");
 for (i,(t,p,b,a)) in rows.iter().enumerate() {
  if i>0 {out.push(',');}
  out.push('[');number(&mut out,*t as f64);out.push(',');number(&mut out,*p);out.push(',');number(&mut out,*b);out.push(',');number(&mut out,*a);out.push(']');
 }
 out.push_str("]}");
 out
}

const COLUMNS:&str="h.bucket_ms,h.step,h.price_lo,h.price_bucket,h.bid_notional,h.ask_notional";

/// 读区间、攒答复。返回（步长，时间格，行）。库里这段没有快照的回空行，步长用客户端给的或跟踪器此刻的。
/// `scope` 是收窄的请求（价格范围、时间格提示）；带了它时挑时间格从提示那一档起、快照数有上限。
#[allow(clippy::too_many_arguments)]
async fn read(pool:&PgPool,base:&str,from:i64,to:i64,requested:Option<f64>,current:Option<f64>,cap:usize,scope:Option<Scope>)->sqlx::Result<(f64,i64,Vec<(i64,f64,f64,f64)>)> {
 // 最近一个快照：拿存储步长、估每格有几个价格桶。
 let latest=sqlx::query(&format!("SELECT {COLUMNS} FROM orderflow_heat h WHERE h.base=$1 AND h.bucket_ms=(SELECT max(bucket_ms) FROM orderflow_heat WHERE base=$1 AND bucket_ms BETWEEN $2 AND $3)"))
  .bind(base).bind(from).bind(to).fetch_all(pool).await?;
 let stored=latest.iter().map(|r|r.get::<f64,_>("step")).fold(None,|m:Option<f64>,s|Some(m.map_or(s,|m|m.max(s))));
 let Some(stored)=stored else {
  let step=match (requested,current) {(Some(r),Some(c))=>r.max(c),(r,c)=>r.or(c).unwrap_or(0.0)};
  return Ok((step,BUCKET_MS,Vec::new()))
 };
 let step=requested.map_or(stored,|r|r.max(stored));
 let range=scope.and_then(|s|s.prices).map(|(lo,hi)|(bucket_index(lo,step),bucket_index(hi,step)));
 let mut prices=std::collections::HashSet::new();
 for r in &latest {
  let (row_step,lo,offsets)=(r.get::<f64,_>("step"),r.get::<i64,_>("price_lo"),r.get::<Vec<i32>,_>("price_bucket"));
  for o in offsets {
   let p=bucket_index((lo+o as i64) as f64*row_step,step);
   if range.is_none_or(|(a,b)|p>=a&&p<=b) {prices.insert(p);}
  }
 }
 // 挑时间格按这段里真有数据的那一截算（刚部署、刚开始跟的 base 只有最近一小段，别因为问了 3 天就给 5 分钟一格）。
 let first:Option<i64>=sqlx::query_scalar("SELECT min(bucket_ms) FROM orderflow_heat WHERE base=$1 AND bucket_ms BETWEEN $2 AND $3")
  .bind(base).bind(from).bind(to).fetch_one(pool).await?;
 let last:i64=latest[0].get("bucket_ms");
 let (from,to)=(first.unwrap_or(from).max(from),last.min(to));
 let span=to-from;
 let level=match scope {
  None=>pick_level(span,prices.len(),cap),
  // 收窄的：按最近一个快照在范围里的桶数估、不加漂移余量——额度只有 1.4 万行，加了余量几小时的窗口就被推到 5 分钟格；
  // 真漂出去超了，读的时候原地放大一档（最多抽 720 个快照，多读的有限）。
  Some(s)=>pick_from(min_level(s.hint),span,prices.len() as f64,cap),
 };
 let mut heat=Heat::new(step,level,cap);
 heat.range=range;
 // 先读预聚合的段（格宽是哪几档段的整数倍就用哪几档），段没盖到的头尾再读原始快照。
 let covered=coverage(pool,base).await?;
 let (rolled,raw)=pieces(from,to+1,LADDER[level].0,&covered);
 for (width,a,b) in rolled {
  // 不排序：段整个落在一格里，先后无所谓；按（base，段宽，起点）主键范围取，900 秒一档三天约 300 行。
  let sql=format!("SELECT bucket_ms,step,samples,price_lo,price_bucket,bid_notional,ask_notional FROM {} WHERE base=$1 AND width_ms={width} AND bucket_ms>=$2 AND bucket_ms<$3",rollup_table(width));
  let mut rows=sqlx::query(&sql).bind(base).bind(a).bind(b).fetch(pool);
  while let Some(r)=rows.try_next().await? {
   let (offsets,bids,asks)=(r.get::<Vec<i32>,_>("price_bucket"),r.get::<Vec<f32>,_>("bid_notional"),r.get::<Vec<f32>,_>("ask_notional"));
   heat.add_rolled(r.get("bucket_ms"),r.get::<i32,_>("samples").max(0) as u32,r.get("step"),r.get("price_lo"),&offsets,&bids,&asks);
  }
 }
 let all=format!("SELECT {COLUMNS} FROM orderflow_heat h WHERE h.base=$1 AND h.bucket_ms BETWEEN $2 AND $3 ORDER BY h.bucket_ms");
 // 隔 `stride` 取一个快照：按主键逐个点查（`bucket_ms = ANY(数组)` 进索引条件），不把这段整个扫一遍。
 // 原来用 generate_series 连接，计划器只按 base 走位图扫描，BTC 3 天几十万行过一遍，并发时一条要 1.6–2.1 秒。
 let sampled=format!("SELECT {COLUMNS} FROM orderflow_heat h WHERE h.base=$1 AND h.bucket_ms=ANY($2::bigint[]) ORDER BY h.bucket_ms");
 for (a,b) in raw {
  let (a,b)=(a,b-1);
  // 隔几个快照取一个，但这一截里至少取 8 个（比时间格还短时别一个都取不到）；段都没有时这一截就是整个区间，和原来一样。
  let stride=stride(level,b-a,scope.is_some());
  let mut rows=if stride<=BUCKET_MS {
   sqlx::query(&all).bind(base).bind(a).bind(b).fetch(pool)
  } else {
   let at:Vec<i64>=((a+stride-1).div_euclid(stride)*stride..=b).step_by(stride as usize).collect();
   sqlx::query(&sampled).bind(base).bind(at).fetch(pool)
  };
  while let Some(r)=rows.try_next().await? {
   let (offsets,bids,asks)=(r.get::<Vec<i32>,_>("price_bucket"),r.get::<Vec<f32>,_>("bid_notional"),r.get::<Vec<f32>,_>("ask_notional"));
   heat.add(r.get("bucket_ms"),r.get("step"),r.get("price_lo"),&offsets,&bids,&asks);
  }
 }
 Ok((step,heat.bucket_ms(),heat.rows()))
}

/// 合并与缓存的键：请求的全部参数（浮点按位）、此刻跟踪器的步长（只影响空答复）、回不回 gzip。
#[derive(Clone,Debug,PartialEq,Eq,Hash)]
struct Key {base:String,from:i64,to:i64,step:Option<u64>,current:Option<u64>,prices:Option<(u64,u64)>,hint:Option<i64>,gzip:bool}

static ANSWERS:std::sync::LazyLock<Answers<Key>>=std::sync::LazyLock::new(||Answers::new(HEAT_TTL));

pub(super) async fn heat(State(s):State<AppState>,headers:axum::http::HeaderMap,Params(q):Params<HeatQuery>)->Result<Response> {
 if !instruments::valid_base(&q.base) {return Err(ApiError::bad("invalid_base"))}
 let scope=scope(&q).map_err(ApiError::bad)?;
 // 缺省的 to（此刻）取整到 5 秒格：快照本来就 5 秒一个，同一格里到的请求合成一个键。
 let (from,to)=window(q.from,q.to,now_ms().div_euclid(BUCKET_MS)*BUCKET_MS).map_err(ApiError::bad)?;
 let requested=requested_step(q.step).map_err(ApiError::bad)?;
 let gzip=accepts_gzip(&headers);
 let registry=REGISTRY.get();
 // 没在跟的不读库、也不因此起跟（手机 / 网页打开品种时拉 `/history` 会起）。
 if !registry.is_some_and(|r|r.is_tracked(&q.base)) {return Ok(answer(body(requested.unwrap_or(0.0),BUCKET_MS,&[]),gzip)?.response())}
 let current=registry.and_then(|r|r.step(&q.base));
 let pool=POOL.get().unwrap_or(&s.pool);
 let key=Key{base:q.base.clone(),from,to,step:requested.map(f64::to_bits),current:current.map(f64::to_bits),
  prices:scope.and_then(|s|s.prices).map(|(a,b)|(a.to_bits(),b.to_bits())),hint:scope.map(|s|s.hint),gzip};
 let cap=if scope.is_some() {SCOPED_ROWS} else {MAX_ROWS};
 let answer=ANSWERS.get_or_build(key,||async {
  let busy=||ApiError(axum::http::StatusCode::SERVICE_UNAVAILABLE,"temporarily_unavailable");
  // 和读订单历史同一组名额（订单流的池子按它留了两条读连接）。
  let _slot=HISTORY_READS.acquire().await.map_err(|_|busy())?;
  let (step,bucket_ms,rows)=read(pool,&q.base,from,to,requested,current,cap,scope).await?;
  drop(_slot);
  answer(body(step,bucket_ms,&rows),gzip)
 }).await?;
 Ok(answer.response())
}

/// 组好的 JSON 装成答复（要 gzip 就压好），带 `Cache-Control: public, max-age=5`（和分钟成交共用 `packed`）。
fn answer(json:String,gzip:bool)->Result<Answer> {packed(json,gzip,CACHE_CONTROL)}

#[cfg(test)]
mod tests {
 use super::*;
 use super::super::book::Bucket;

 fn buckets(cells:&[(Side,i64,f64)])->Buckets {cells.iter().map(|&(s,i,n)|((s,i),Bucket{notional:n,top:n,price:0.0})).collect()}
 fn btc()->Thresholds {Thresholds{spot:Some(1_000_000.0),usdt_perp:Some(5_000_000.0),coin_perp:Some(5_000_000.0),delivery:Some(5_000_000.0),step:Some(100.0)}}

 #[test] fn fold_merges_books_of_one_product_and_cuts_below_five_percent_of_the_threshold() {
  let books=vec![
   // 交割两期合成一条；永续门槛 500 万，5% = 25 万。
   ("binance","delivery",buckets(&[(Side::Bid,599,200_000.0),(Side::Ask,601,300_000.0)])),
   ("binance","delivery",buckets(&[(Side::Bid,599,100_000.0),(Side::Ask,605,10_000.0)])),
   // 现货门槛 100 万，5% = 5 万。
   ("binance","spot",buckets(&[(Side::Bid,598,60_000.0),(Side::Bid,597,49_999.0),(Side::Ask,600,0.0)])),
   ("okx","usdtPerp",buckets(&[(Side::Bid,590,1_000.0)])),
  ];
  let out=fold("BTC",&btc(),100.0,10_000,books);
  assert_eq!(out.len(),2,"OKX 那条全被过滤掉，不写空带子");
  let delivery=out.iter().find(|b|b.product=="delivery").unwrap();
  assert_eq!((delivery.lo,delivery.offsets.clone(),delivery.bids.clone(),delivery.asks.clone()),(599,vec![0,2],vec![300_000.0,0.0],vec![0.0,300_000.0]));
  assert_eq!((delivery.exchange,delivery.bucket_ms,delivery.step),("binance",10_000,100.0));
  let spot=out.iter().find(|b|b.product=="spot").unwrap();
  assert_eq!((spot.lo,spot.offsets.clone(),spot.bids.clone()),(598,vec![0],vec![60_000.0]));
 }

 #[test] fn fold_skips_products_without_a_threshold() {
  let mut t=btc();t.usdt_perp=None;
  assert!(fold("MU",&t,1.0,0,vec![("binance","usdtPerp",buckets(&[(Side::Bid,1,1e9)]))]).is_empty(),"非币标定之前不写");
 }

 #[test] fn ticks_land_in_the_middle_of_a_five_second_cell() {
  assert_eq!(first_tick(10_000),Duration::from_millis(2_500));
  assert_eq!(first_tick(12_499),Duration::from_millis(1));
  assert_eq!(first_tick(12_500),Duration::from_millis(5_000));
  assert_eq!(first_tick(14_000),Duration::from_millis(3_500));
 }

 #[test] fn window_defaults_and_clamps_instead_of_failing() {
  let now=10*store::DAY_MS;
  assert_eq!(window(None,None,now),Ok((now-DEFAULT_SPAN_MS,now)));
  assert_eq!(window(Some(0),Some(now),now),Ok((now-3*store::DAY_MS,now)),"超过 3 天夹回来");
  assert_eq!(window(Some(5),Some(4),now),Err("invalid_range"));
  assert_eq!(window(Some(-1),None,now),Err("invalid_range"));
  assert_eq!(window(None,Some(i64::MIN),now),Err("invalid_range"));
 }

 #[test] fn step_must_be_positive_and_finite() {
  assert_eq!(requested_step(None),Ok(None));
  assert_eq!(requested_step(Some(250.0)),Ok(Some(250.0)));
  for bad in [0.0,-1.0,f64::NAN,f64::INFINITY] {assert_eq!(requested_step(Some(bad)),Err("invalid_step"));}
 }

 #[test] fn exchanges_add_up_and_snapshots_average_within_a_cell() {
  let mut h=Heat::new(100.0,0,MAX_ROWS);
  // 同一快照两家同一个桶：相加。
  h.add(5_000,100.0,600,&[0],&[1_000.0],&[0.0]);
  h.add(5_000,100.0,600,&[0],&[500.0],&[0.0]);
  assert_eq!(h.rows(),vec![(5_000,60_000.0,1_500.0,0.0)]);
  // 放大到 10 秒格：两个快照取平均，第二个快照里没有 601 这个桶按 0 算。
  let mut h=Heat::new(100.0,1,MAX_ROWS);
  h.add(10_000,100.0,600,&[0,1],&[1_000.0,0.0],&[0.0,400.0]);
  h.add(15_000,100.0,600,&[0],&[3_000.0],&[0.0]);
  assert_eq!(h.bucket_ms(),10_000);
  assert_eq!(h.rows(),vec![(10_000,60_000.0,2_000.0,0.0),(10_000,60_100.0,0.0,200.0)]);
 }

 #[test] fn a_coarser_step_sums_prices_and_rows_keep_their_own_stored_step() {
  let mut h=Heat::new(250.0,0,MAX_ROWS);
  // 存储步长 100：600、601、602 → 250 的格 240（60 000–60 250）；603 → 241。
  h.add(0,100.0,600,&[0,1,2,3],&[1.0,2.0,3.0,4.0],&[0.0;4]);
  // 另一天存的步长是 50：1201 × 50 = 60 050 → 240。
  h.add(0,50.0,1201,&[0],&[10.0],&[0.0]);
  assert_eq!(h.rows(),vec![(0,60_000.0,16.0,0.0),(0,60_250.0,4.0,0.0)]);
 }

 #[test] fn prices_are_tidied_to_the_step_decimals() {
  let mut h=Heat::new(0.1,0,MAX_ROWS);
  h.add(0,0.1,1233,&[0],&[5.0],&[0.0]);
  assert_eq!(h.rows()[0].1,123.3);
  assert_eq!(decimals(0.0001),4);
  assert_eq!(decimals(100.0),0);
 }

 #[test] fn too_many_cells_widen_the_time_cell_in_place() {
  let mut h=Heat::new(1.0,0,4);
  for k in 0..6 {h.add(k*5_000,1.0,0,&[0,1],&[10.0,10.0],&[0.0,0.0]);assert!(h.cells.len()<=4,"并上去之后不超上限");}
  assert_eq!(h.bucket_ms(),30_000,"5 秒格第三拍超 → 10 秒，第五拍又超 → 30 秒");
  assert_eq!(h.rows(),vec![(0,0.0,10.0,0.0),(0,1.0,10.0,0.0)],"六个快照平均回每个 10");
  // 60 秒格超了跳过 2.5 分钟（不整除）直接并到 5 分钟。
  let mut h=Heat::new(1.0,3,2);
  for k in 0..3 {h.add(k*60_000,1.0,0,&[0],&[6.0],&[0.0]);}
  assert_eq!((h.bucket_ms(),h.rows()),(300_000,vec![(0,0.0,6.0,0.0)]));
 }

 #[test] fn the_ladder_is_picked_from_the_estimate() {
  // 估算：（格数 + 1）× 桶数 × 1.5。
  assert_eq!(pick_level(60*60_000,100,MAX_ROWS),0,"一小时 × 100 桶 5 秒格装得下");
  assert_eq!(pick_level(60*60_000,200,MAX_ROWS),1,"一小时 × 200 桶要 10 秒格");
  assert_eq!(pick_level(store::DAY_MS,200,MAX_ROWS),4,"一天 × 200 桶 60 秒格也装不下，2.5 分钟");
  assert_eq!(pick_level(3*store::DAY_MS,200,MAX_ROWS),6,"三天 × 200 桶 15 分钟");
  assert_eq!(pick_level(3*store::DAY_MS,100_000,MAX_ROWS),LADDER.len()-1,"怎么都装不下就用最粗的，读的时候再并");
  for i in 0..LADDER.len()-1 {let j=next_level(i);assert!(j>i&&LADDER[j].0%LADDER[i].0==0,"每档都有能原地并上去的下一档");}
  assert_eq!((next_level(3),next_level(4)),(5,5),"60 秒跳过 2.5 分钟直接并到 5 分钟");
  for (bucket,stride) in LADDER {assert_eq!(bucket%stride,0);assert_eq!(stride%BUCKET_MS,0);}
 }

 #[test] fn body_has_the_agreed_shape() {
  let json=body(100.0,5_000,&[(1_000,60_000.0,12.0,0.0),(1_000,0.5,1.0,2.0)]);
  assert_eq!(json,r#"{"step":100,"bucketMs":5000,"rows":[[1000,60000,12,0],[1000,0.5,1,2]]}"#);
  let v:serde_json::Value=serde_json::from_str(&body(0.1,10_000,&[])).unwrap();
  assert_eq!(v,serde_json::json!({"step":0.1,"bucketMs":10000,"rows":[]}));
 }

 #[tokio::test] async fn heat_round_trips_through_the_table() {
  let Some(pool)=store::tests::isolated_pool().await else {return};
  let base="HEATTEST";
  sqlx::query("DELETE FROM orderflow_heat WHERE base=$1").bind(base).execute(&pool).await.unwrap();
  sqlx::query("DELETE FROM orderflow_bases WHERE base=$1").bind(base).execute(&pool).await.unwrap();
  let band=|exchange:&'static str,t:i64,bid:f32|Band{base:base.into(),exchange,product:"usdtPerp",bucket_ms:t,step:100.0,lo:600,offsets:vec![0,3],bids:vec![bid,0.0],asks:vec![0.0,7.0]};
  let now=10*store::DAY_MS;
  let old=now-store::RETENTION_MS-BUCKET_MS;
  insert(&pool,&[band("binance",now-10_000,100.0),band("okx",now-10_000,50.0),band("binance",now-5_000,300.0),band("binance",old,1.0)]).await.unwrap();
  // 同一格再来一拍：留先到的。
  insert(&pool,&[band("binance",now-5_000,999.0)]).await.unwrap();
  let (step,bucket_ms,rows)=read(&pool,base,now-60_000,now,None,None,MAX_ROWS,None).await.unwrap();
  assert_eq!((step,bucket_ms),(100.0,5_000));
  assert_eq!(rows,vec![(now-10_000,60_000.0,150.0,0.0),(now-10_000,60_300.0,0.0,14.0),(now-5_000,60_000.0,300.0,0.0),(now-5_000,60_300.0,0.0,7.0)]);
  // 客户端步长比存储的小：按存储步长回；大：合并。
  assert_eq!(read(&pool,base,now-60_000,now,Some(10.0),None,MAX_ROWS,None).await.unwrap().0,100.0);
  let (step,_,rows)=read(&pool,base,now-60_000,now,Some(1_000.0),None,MAX_ROWS,None).await.unwrap();
  assert_eq!(step,1_000.0);
  assert_eq!(rows,vec![(now-10_000,60_000.0,150.0,14.0),(now-5_000,60_000.0,300.0,7.0)]);
  // 行数上限：放大时间格。
  let (_,bucket_ms,rows)=read(&pool,base,now-60_000,now,None,None,2,None).await.unwrap();
  assert!(bucket_ms>5_000&&rows.len()<=2&&!rows.is_empty(),"{bucket_ms} {rows:?}");
  // 问 3 天但只有最近 10 秒有数据：时间格按有数据的那一截挑，不放大。
  let (_,bucket_ms,rows)=read(&pool,base,now-store::RETENTION_MS+1,now,None,None,1_000,None).await.unwrap();
  assert_eq!((bucket_ms,rows.len()),(5_000,4));
  // 这一段没有快照：空行，步长取客户端的与跟踪器此刻的较大者。
  assert_eq!(read(&pool,base,0,1_000,Some(5.0),Some(100.0),MAX_ROWS,None).await.unwrap(),(100.0,BUCKET_MS,vec![]));
  // 清理按 orderflow_bases 逐只走：还没登记的 base 不动（起跟时 start 写库失败的情形）……
  assert_eq!(purge(&pool,now).await.unwrap(),0);
  // ……跟踪器每分钟报活时补上这一行，下一次清理就收得到：3 天以前的删掉，其余留着。
  store::alive(&pool,base,now).await.unwrap();
  assert_eq!(purge(&pool,now).await.unwrap(),1);
  let left:i64=sqlx::query_scalar("SELECT count(*) FROM orderflow_heat WHERE base=$1").bind(base).fetch_one(&pool).await.unwrap();
  assert_eq!(left,3);
  sqlx::query("DELETE FROM orderflow_heat WHERE base=$1").bind(base).execute(&pool).await.unwrap();
  sqlx::query("DELETE FROM orderflow_bases WHERE base=$1").bind(base).execute(&pool).await.unwrap();
 }

 fn query(lo:Option<f64>,hi:Option<f64>,around:Option<f64>,pct:Option<f64>,bucket_ms:Option<i64>)->HeatQuery {
  HeatQuery{base:"BTC".into(),from:None,to:None,step:None,lo,hi,around,pct,bucket_ms}
 }

 #[test] fn scope_takes_either_a_range_or_a_ring_and_a_positive_hint() {
  assert_eq!(scope(&query(None,None,None,None,None)),Ok(None),"老请求");
  assert_eq!(scope(&query(Some(100.0),Some(200.0),None,None,None)),Ok(Some(Scope{prices:Some((100.0,200.0)),hint:BUCKET_MS})));
  assert_eq!(scope(&query(None,None,Some(100_000.0),None,None)),Ok(Some(Scope{prices:Some((95_000.0,105_000.0)),hint:BUCKET_MS})),"pct 缺省 5");
  let Ok(Some(Scope{prices:Some((a,b)),hint}))=scope(&query(None,None,Some(200.0),Some(10.0),Some(60_000))) else {panic!()};
  assert!((a-180.0).abs()<1e-9&&(b-220.0).abs()<1e-9&&hint==60_000);
  assert_eq!(scope(&query(None,None,None,None,Some(60_000))),Ok(Some(Scope{prices:None,hint:60_000})),"只给时间格提示");
  for bad in [query(Some(1.0),None,None,None,None),query(None,Some(1.0),None,None,None),query(Some(2.0),Some(1.0),None,None,None),query(Some(1.0),Some(1.0),None,None,None),
   query(Some(-1.0),Some(1.0),None,None,None),query(Some(f64::NAN),Some(1.0),None,None,None),query(Some(1.0),Some(f64::INFINITY),None,None,None),
   query(Some(1.0),Some(2.0),Some(1.5),None,None),query(None,None,None,Some(5.0),None),query(None,None,Some(0.0),None,None),
   query(None,None,Some(1.0),Some(0.0),None),query(None,None,Some(1.0),Some(50.1),None),query(None,None,Some(1.0),Some(f64::NAN),None)] {
   assert_eq!(scope(&bad),Err("invalid_price"));
  }
  assert_eq!(scope(&query(None,None,Some(1.0),Some(50.0),None)).map(|s|s.is_some()),Ok(true));
  assert_eq!(scope(&query(None,None,None,None,Some(0))),Err("invalid_bucket"));
  assert_eq!(scope(&query(None,None,None,None,Some(-5_000))),Err("invalid_bucket"));
 }

 /// 查询串：新参数的名字（`bucketMs` 驼峰）、解析不了的回 400，蛇形名字算多给的参数。
 #[tokio::test] async fn heat_query_string_is_parsed_and_validated() {
  use axum::{Router,body::Body,http::{Request,StatusCode},routing::get};
  use http_body_util::BodyExt;
  use tower::ServiceExt;
  let app=||Router::<()>::new().route(PATH,get(|Params(q):Params<HeatQuery>|async move {scope(&q).map_err(ApiError::bad).map(|s|format!("{s:?}"))}));
  for (q,want) in [("base=BTC",Ok("None")),("base=BTC&around=100000&pct=5&bucketMs=60000",Ok("Some(Scope { prices: Some((95000.0, 105000.0)), hint: 60000 })")),
   ("base=BTC&lo=1&hi=2",Ok("Some(Scope { prices: Some((1.0, 2.0)), hint: 5000 })")),("base=BTC&lo=2&hi=1",Err("invalid_price")),
   ("base=BTC&bucketMs=0",Err("invalid_bucket")),("base=BTC&bucket_ms=60000",Err("invalid_query")),("base=BTC&pct=abc&around=1",Err("invalid_query"))] {
   let reply=app().oneshot(Request::builder().uri(format!("{PATH}?{q}")).body(Body::empty()).unwrap()).await.unwrap();
   let status=reply.status();
   let body=reply.into_body().collect().await.unwrap().to_bytes();
   match want {
    Ok(v)=>{assert_eq!(status,StatusCode::OK,"{q}");assert_eq!(&body[..],v.as_bytes(),"{q}");},
    Err(code)=>{assert_eq!(status,StatusCode::BAD_REQUEST,"{q}");assert_eq!(serde_json::from_slice::<serde_json::Value>(&body).unwrap()["error"]["code"],code,"{q}");},
   }
  }
 }

 #[test] fn the_hint_is_a_floor_on_the_ladder_and_snapshots_are_budgeted() {
  assert_eq!(min_level(1),0);
  assert_eq!(min_level(5_000),0);
  assert_eq!(min_level(20_000),2,"20 秒 → 30 秒格");
  assert_eq!(min_level(60_000),3);
  assert_eq!(min_level(10*3_600_000),LADDER.len()-1);
  // 一小时、每格 100 桶、上限 1.4 万：30 秒格装得下（121 × 100），10 秒格装不下；提示 5 分钟就从 5 分钟起。
  assert_eq!(pick_from(0,3_600_000,100.0,SCOPED_ROWS),2);
  assert_eq!(pick_from(min_level(300_000),3_600_000,100.0,SCOPED_ROWS),5);
  // 6 小时 × 110 桶：5 分钟格（73 × 110 ≈ 8 000；2.5 分钟 145 × 110 超）；4 小时 × 82 桶：2.5 分钟（97 × 82 ≈ 8 000）。
  assert_eq!(pick_from(0,6*3_600_000,110.0,SCOPED_ROWS),5);
  assert_eq!(pick_from(0,4*3_600_000,82.0,SCOPED_ROWS),4);
  // 快照间隔：老请求照梯子；收窄的最多 720 个，取整到能整除格宽。
  assert_eq!(stride(3,3_600_000,false),15_000);
  assert_eq!(stride(3,3_600_000,true),15_000,"一小时 15 秒一个是 240 个，没超");
  assert_eq!(stride(3,6*3_600_000,true),30_000,"6 小时要 30 秒一个（720 个）");
  assert_eq!(stride(5,3*store::DAY_MS,true),300_000,"3 天 5 分钟格：一格最多取一个");
  assert_eq!(stride(4,7*3_600_000,true),50_000,"7 小时 2.5 分钟格：35 秒往上取能整除 150 秒的 50 秒，一格三个");
 }

 #[test] fn a_price_range_keeps_only_its_buckets() {
  let mut h=Heat::new(100.0,0,MAX_ROWS);
  h.range=Some((601,602));
  h.add(0,100.0,600,&[0,1,2,3],&[1.0,2.0,3.0,4.0],&[0.0;4]);
  assert_eq!(h.rows(),vec![(0,60_100.0,2.0,0.0),(0,60_200.0,3.0,0.0)]);
  // 桶全在范围外的快照也算一个快照（平均时的分母），不然只偶尔进范围的格会被放大。
  let mut h2=Heat::new(100.0,1,MAX_ROWS);
  h2.range=Some((601,601));
  h2.add(0,100.0,600,&[1],&[10.0],&[0.0]);
  h2.add(5_000,100.0,600,&[0],&[10.0],&[0.0]);
  assert_eq!(h2.rows(),vec![(0,60_100.0,5.0,0.0)]);
 }

 #[test] fn answers_are_publicly_cacheable_for_five_seconds() {
  let a=answer(body(100.0,5_000,&[]),false).unwrap().response();
  assert_eq!(a.headers()[axum::http::header::CACHE_CONTROL],"public, max-age=5");
  assert_eq!(a.headers()[axum::http::header::CONTENT_LENGTH],"38");
  let z=answer(body(100.0,5_000,&[]),true).unwrap().response();
  assert_eq!(z.headers()[axum::http::header::CONTENT_ENCODING],"gzip");
  assert_eq!(HEAT_TTL,Duration::from_secs(5));
 }

 /// 收窄的请求走抽样（`ANY(数组)`）：一小时 5 秒一个快照，提示 60 秒、价格只要 60 250 以上。
 #[tokio::test] async fn scoped_reads_sample_by_primary_key_and_filter_prices() {
  let Some(pool)=store::tests::isolated_pool().await else {return};
  let base="HEATSCOPE";
  sqlx::query("DELETE FROM orderflow_heat WHERE base=$1").bind(base).execute(&pool).await.unwrap();
  let now=10*store::DAY_MS;
  let from=now-3_600_000;
  let bands:Vec<Band>=(0..720).flat_map(|k|{
   let t=from+k*BUCKET_MS;
   ["binance","okx"].map(|exchange|Band{base:base.into(),exchange,product:"usdtPerp",bucket_ms:t,step:100.0,lo:600,offsets:vec![0,3,10],bids:vec![100.0,0.0,0.0],asks:vec![0.0,40.0,8.0]})
  }).collect();
  for chunk in bands.chunks(INSERT_ROWS) {insert(&pool,chunk).await.unwrap();}
  let last=from+719*BUCKET_MS;
  // 老请求：一小时 × 3 个桶，5 秒格全读。
  let (_,bucket_ms,rows)=read(&pool,base,from,last,None,None,MAX_ROWS,None).await.unwrap();
  assert_eq!((bucket_ms,rows.len()),(5_000,720*3));
  // 收窄：提示 60 秒、价格 60 250–60 500：只剩 60 300 这一个桶，60 秒一格（15 秒取一个快照），两家相加后取平均。
  let s=Scope{prices:Some((60_250.0,60_500.0)),hint:60_000};
  let (step,bucket_ms,rows)=read(&pool,base,from,last,None,None,SCOPED_ROWS,Some(s)).await.unwrap();
  assert_eq!((step,bucket_ms),(100.0,60_000));
  assert_eq!(rows.len(),60);
  assert!(rows.iter().all(|&(_,p,b,a)|p==60_300.0&&b==0.0&&a==80.0),"{:?}",&rows[..3]);
  // 行数上限压到 20：原地放大到 5 分钟格。
  let (_,bucket_ms,rows)=read(&pool,base,from,last,None,None,20,Some(s)).await.unwrap();
  assert_eq!((bucket_ms,rows.len()),(300_000,12));
  // 只给提示、不限价格：三个桶都在。
  let (_,_,rows)=read(&pool,base,from,last,None,None,SCOPED_ROWS,Some(Scope{prices:None,hint:60_000})).await.unwrap();
  assert_eq!(rows.len(),60*3);
  sqlx::query("DELETE FROM orderflow_heat WHERE base=$1").bind(base).execute(&pool).await.unwrap();
 }

 /// 计划对比（2026-09-29）：照线上 BTC 的形状摆两只 base 各一天（5 秒一个快照 × 9 个交易所产品、一条带子 40 个桶），
 /// 对 6 小时 60 秒一个快照比原来的 `generate_series` 连接与现在的 `ANY(数组)`，再比 1 小时 10 秒一个。
 /// `python3 ops/test.py --lib -- heat::tests::explain_old_join_against_primary_key_sampling --ignored --nocapture`。
 #[ignore] #[tokio::test] async fn explain_old_join_against_primary_key_sampling() {
  let Some(pool)=store::tests::isolated_pool().await else {return};
  let bases=["ZZHEATA","ZZHEATB"];
  for b in bases {sqlx::query("DELETE FROM orderflow_heat WHERE base=$1").bind(b).execute(&pool).await.unwrap();}
  let now=20*store::DAY_MS;
  let from=now-store::DAY_MS;
  sqlx::query("INSERT INTO orderflow_heat(base,exchange,product,bucket_ms,step,price_lo,price_bucket,bid_notional,ask_notional) \
   SELECT b,v.ex,v.pr,t,100,600,ARRAY(SELECT generate_series(0,39)),array_fill(1e6::real,ARRAY[40]),array_fill(2e5::real,ARRAY[40]) \
   FROM unnest($1::text[]) b,generate_series($2::bigint,$3::bigint,5000) t, \
   (VALUES ('binance','usdtPerp'),('binance','spot'),('binance','coinPerp'),('binance','delivery'),('okx','usdtPerp'),('okx','spot'),('okx','coinPerp'),('okx','delivery'),('coinbase','spot')) v(ex,pr)")
   .bind(bases.map(String::from).to_vec()).bind(from).bind(now).execute(&pool).await.unwrap();
  sqlx::query("ANALYZE orderflow_heat").execute(&pool).await.unwrap();
  let old=format!("SELECT {COLUMNS} FROM generate_series($2::bigint,$3::bigint,$4::bigint) g(t) JOIN orderflow_heat h ON h.base=$1 AND h.bucket_ms=g.t ORDER BY h.bucket_ms");
  let new=format!("SELECT {COLUMNS} FROM orderflow_heat h WHERE h.base=$1 AND h.bucket_ms=ANY($2::bigint[]) ORDER BY h.bucket_ms");
  let plan=|sql:String,old:bool,a:i64,b:i64,stride:i64|{let pool=pool.clone();async move {
   let q=format!("EXPLAIN (ANALYZE,BUFFERS) {sql}");
   let q=sqlx::query_scalar::<_,String>(&q).bind(bases[0]);
   let q=if old {q.bind(a).bind(b).bind(stride)} else {q.bind((0..).map(|k|a+k*stride).take_while(|&t|t<=b).collect::<Vec<i64>>())};
   q.fetch_all(&pool).await.unwrap().join("\n")
  }};
  for (span,stride) in [(6*3_600_000,60_000),(3_600_000,10_000)] {
   let a=now-span;
   for _ in 0..2 {let _=plan(old.clone(),true,a,now,stride).await;let _=plan(new.clone(),false,a,now,stride).await;}
   let before=plan(old.clone(),true,a,now,stride).await;
   let after=plan(new.clone(),false,a,now,stride).await;
   println!("—— {} 小时、{} 秒一个快照 ——\n原来（generate_series 连接）：\n{before}\n现在（ANY 数组）：\n{after}\n",span/3_600_000,stride/1000);
   assert!(after.contains("Index Cond")&&after.contains("bucket_ms = ANY"),"现在应按主键点查：\n{after}");
  }
  for b in bases {sqlx::query("DELETE FROM orderflow_heat WHERE base=$1").bind(b).execute(&pool).await.unwrap();}
 }

 #[test] fn pieces_use_the_coarsest_rollup_that_divides_the_cell_and_raw_for_the_rest() {
  // 30 秒段并到 3 990 000（段的端点都对齐自己的宽度）、150 秒到 3 750 000、900 秒到 3 600 000；900 秒格从没对齐的 35 000 读到 4 100 000。
  let covered=[Some(3_990_000),Some(3_750_000),Some(3_600_000)];
  let (rolled,raw)=pieces(35_000,4_100_000,900_000,&covered);
  assert_eq!(rolled,vec![(30_000,60_000,150_000),(30_000,3_750_000,3_990_000),(150_000,150_000,900_000),(150_000,3_600_000,3_750_000),(900_000,900_000,3_600_000)]);
  assert_eq!(raw,vec![(35_000,60_000),(3_990_000,4_100_000)],"头上没对齐的 25 秒、尾上还没并的 110 秒读原始快照");
  // 60 秒格只能用 30 秒段；10 秒格一档都用不上；一档段都还没有（None）就跳过这一档。
  assert_eq!(pieces(0,120_000,60_000,&covered),(vec![(30_000,0,120_000)],vec![]));
  assert_eq!(pieces(0,120_000,10_000,&covered),(vec![],vec![(0,120_000)]));
  assert_eq!(pieces(0,1_800_000,900_000,&[None,Some(900_000),None]),(vec![(150_000,0,900_000)],vec![(900_000,1_800_000)]));
  // 每一截不重不漏：拼起来正好是 [lo,hi)。
  let (rolled,raw)=pieces(12_345,9_876_543,3_600_000,&[Some(9_000_000),Some(8_850_000),Some(7_200_000)]);
  let mut spans:Vec<(i64,i64)>=rolled.iter().map(|&(_,a,b)|(a,b)).chain(raw).collect();
  spans.sort();
  assert_eq!(spans.first().unwrap().0,12_345);assert_eq!(spans.last().unwrap().1,9_876_543);
  for w in spans.windows(2) {assert_eq!(w[0].1,w[1].0,"{spans:?}");}
  for (r,a,b) in rolled {assert!(a%r==0&&b%r==0&&a<b&&3_600_000%r==0);}
 }

 #[test] fn rolled_rows_carry_their_snapshot_count_into_the_average() {
  let mut h=Heat::new(100.0,3,MAX_ROWS);
  // 60 秒格里两段 30 秒、各 6 个快照：600 这个桶两段各 600（每快照 100），601 只在第一段里有一次 120。
  h.add_rolled(60_000,6,100.0,600,&[0,1],&[600.0,0.0],&[0.0,120.0]);
  h.add_rolled(90_000,6,100.0,600,&[0],&[600.0],&[0.0]);
  assert_eq!(h.rows(),vec![(60_000,60_000.0,100.0,0.0),(60_000,60_100.0,0.0,10.0)]);
  // 段与原始快照可以落在同一格：分母是两边快照数之和。
  h.add(115_000,100.0,600,&[0],&[100.0],&[0.0]);
  assert_eq!(h.rows()[0],(60_000,60_000.0,100.0,0.0));
  assert_eq!(h.samples[&60_000],13);
 }

 /// 后台并段（原始 → 30 秒 → 150 秒 → 900 秒）与读法：并好的那截是每个快照的精确平均，没并的头尾照旧读原始快照。
 #[tokio::test] async fn rollups_average_every_snapshot_and_reads_stitch_them_with_raw() {
  let Some(pool)=store::tests::isolated_pool().await else {return};
  let base="HEATROLL";
  let wipe=||{let pool=pool.clone();async move {
   sqlx::query("DELETE FROM orderflow_heat WHERE base=$1").bind(base).execute(&pool).await.unwrap();
   sqlx::query("DELETE FROM orderflow_heat_rollup WHERE base=$1").bind(base).execute(&pool).await.unwrap();
  }};
  wipe().await;
  let now=20*store::DAY_MS;
  let from=now-3_600_000;
  // 并段与清理的名单取自 orderflow_bases：跟踪器起跟时登记。
  store::start(&pool,base,from).await.unwrap();
  // 一小时 720 个快照：币安 600 买 100 每拍都有、601 卖 60 只在每 30 秒的头两拍；OKX 603 买 10 每拍都有。
  let bands:Vec<Band>=(0..720).flat_map(|k:i64|{
   let t=from+k*BUCKET_MS;
   let binance=if k%6<2 {Band{base:base.into(),exchange:"binance",product:"usdtPerp",bucket_ms:t,step:100.0,lo:600,offsets:vec![0,1],bids:vec![100.0,0.0],asks:vec![0.0,60.0]}}
    else {Band{base:base.into(),exchange:"binance",product:"usdtPerp",bucket_ms:t,step:100.0,lo:600,offsets:vec![0],bids:vec![100.0],asks:vec![0.0]}};
   [binance,Band{base:base.into(),exchange:"okx",product:"spot",bucket_ms:t,step:100.0,lo:603,offsets:vec![0],bids:vec![10.0],asks:vec![0.0]}]
  }).collect();
  for chunk in bands.chunks(INSERT_ROWS) {insert(&pool,chunk).await.unwrap();}
  let last=from+719*BUCKET_MS;
  let at=|rows:&[(i64,f64,f64,f64)],price:f64|rows.iter().filter(|r|r.1==price).map(|r|(r.0,r.2+r.3)).collect::<Vec<_>>();
  let s60=Scope{prices:None,hint:60_000};
  // 没有段：60 秒格隔 15 秒取一个快照（每格 4 个，601 只抽到 k%6==0 那一拍）→ 601 是 30。
  let (_,bucket_ms,before)=read(&pool,base,from,last,None,None,SCOPED_ROWS,Some(s60)).await.unwrap();
  assert_eq!((bucket_ms,before.len()),(60_000,180));
  assert!(at(&before,60_100.0).iter().all(|&(_,v)|v==30.0));
  // 后台追到 45 分钟（此刻 = 45 分钟 + 宽限）。
  let then=from+45*60_000+ROLL_GRACE;
  let mut roller=Roller{done:resume(&pool,&[base.to_string()],then).await.unwrap(),failures:[0;3]};
  assert_eq!(roller.done,[from,from,from],"一段都没有时从最早的原始快照起");
  while roller.step(&pool,then).await.unwrap() {}
  assert_eq!(roller.done,[from+2_700_000;3]);
  let rolled:Vec<(i64,i64,i32)>=sqlx::query_as("SELECT width_ms,count(*),min(samples) FROM orderflow_heat_rollup WHERE base=$1 GROUP BY 1 ORDER BY 1").bind(base).fetch_all(&pool).await.unwrap();
  assert_eq!(rolled,vec![(30_000,90,6),(150_000,18,30),(900_000,3,180)]);
  let (lo,offsets,bids,asks,samples):(i64,Vec<i32>,Vec<f32>,Vec<f32>,i32)=sqlx::query_as("SELECT price_lo,price_bucket,bid_notional,ask_notional,samples FROM orderflow_heat_rollup WHERE base=$1 AND width_ms=900000 AND bucket_ms=$2")
   .bind(base).bind(from).fetch_one(&pool).await.unwrap();
  assert_eq!((lo,offsets,bids,asks,samples),(600,vec![0,1,3],vec![18_000.0,0.0,1_800.0],vec![0.0,3_600.0,0.0],180),"三家各产品相加、各快照相加");
  // 重跑同一截不重复写；进度从表里接得上。
  assert_eq!(roll_range(&pool,0,&[base.to_string()],from,from+60_000).await.unwrap(),0);
  assert_eq!(resume(&pool,&[base.to_string()],then).await.unwrap(),[from+2_700_000;3]);
  // 有段之后：前 45 分钟的格是每个快照的精确平均（601 = 60 × 2/6 = 20），最后 15 分钟照旧抽样（30）；行数、别的桶不变。
  let (_,bucket_ms,after)=read(&pool,base,from,last,None,None,SCOPED_ROWS,Some(s60)).await.unwrap();
  assert_eq!((bucket_ms,after.len()),(60_000,180));
  for (t,v) in at(&after,60_100.0) {assert_eq!(v,if t<from+2_700_000 {20.0} else {30.0},"{t}");}
  assert!(at(&after,60_000.0).iter().all(|&(_,v)|v==100.0)&&at(&after,60_300.0).iter().all(|&(_,v)|v==10.0));
  // 900 秒格：前三格整段读 900 秒段。
  let (_,bucket_ms,wide)=read(&pool,base,from,last,None,None,SCOPED_ROWS,Some(Scope{prices:None,hint:900_000})).await.unwrap();
  assert_eq!(bucket_ms,900_000);
  assert_eq!(&at(&wide,60_100.0)[..3],&[(from,20.0),(from+900_000,20.0),(from+1_800_000,20.0)]);
  // 起点没对齐（从第 7 拍起）：头上 25 秒原始、再 30 秒段、再 150 秒段拼成第一格：601 出现 1 + 6 + 50 次 / 173 个快照 × 60 ≈ 20。
  let (_,_,shifted)=read(&pool,base,from+35_000,last,None,None,SCOPED_ROWS,Some(Scope{prices:None,hint:900_000})).await.unwrap();
  assert_eq!(at(&shifted,60_100.0)[0],(from,20.0));
  assert_eq!(at(&shifted,60_000.0)[0],(from,100.0));
  // 价格范围照样只留范围里的桶。
  let (_,_,narrow)=read(&pool,base,from,last,None,None,SCOPED_ROWS,Some(Scope{prices:Some((60_100.0,60_150.0)),hint:900_000})).await.unwrap();
  assert!(!narrow.is_empty()&&narrow.iter().all(|r|r.1==60_100.0));
  // 清理：段和原始快照同一个截止时刻删。
  purge(&pool,now+store::RETENTION_MS+1).await.unwrap();
  let left:i64=sqlx::query_scalar("SELECT count(*) FROM orderflow_heat_rollup WHERE base=$1").bind(base).fetch_one(&pool).await.unwrap();
  assert_eq!(left,0);
  wipe().await;
  sqlx::query("DELETE FROM orderflow_bases WHERE base=$1").bind(base).execute(&pool).await.unwrap();
 }
}
