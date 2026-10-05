//! 大单与散户的分钟成交（2026-09-29，网页版副图「大单与散户累计量差」的历史）。
//!
//! * 记：跟踪任务收到的每一笔成交（三家全部簿，按成交号去重之后，见 `Tracker::handle`）按收到的那一分钟分桶，
//!   一笔 ≥ 大单线（订单流门槛的 1/50，门槛取 U 本位永续、没有取现货、再没有取币本位 / 交割里小的那个，和网页的 `tapeBase` 一致）
//!   记进大单，< 1 万美元记进散户，主动买（吃卖一）/ 主动卖（吃买一）分开记美元额；中间那一段两边都不记。
//!   门槛还没有（非币标定之前）的这段不记。一分钟过完（跟踪任务每 0.5 秒看一次）交给全进程一个写库任务，
//!   攒一批用一条多行 INSERT 写进 `orderflow_flow`（见迁移 0036），同一分钟再来（停机交出的半分钟、重启后接着的另半分钟）就加上去。
//!   写库占 `WRITE_SLOTS` 的一条；通道满了（库慢）丢这一分钟，不堵跟踪任务。
//! * 清理：每小时和订单流的滚动清理一起，逐只 base 按主键删 3 天以前的（`store::RETENTION_MS`）。一只一分钟一行，
//!   220 只 3 天最多约 95 万行、几十 MB，不设体积闸门。
//! * 接口 `GET /v1/market/orderflow/flow?base=&from=&to=` → `{"base","bigUsd","smallUsd","tracked","rows":[[minute_ms,大买,大卖,小买,小卖],…]}`：
//!   美元额取整；`to` 缺省此刻、`from` 缺省 `to` 前 3 天，超过 3 天把 `from` 夹回来；两端按分钟向下取整，闭区间。
//!   区间最长 3 天 = 最多 4321 行（gzip 后几十 KB），不分页。`bigUsd` 是此刻的大单线（门槛还没有为 null）。
//!   没在跟的 base 回 `tracked:false` 与空 `rows`，不读库、也不因此起跟。鉴权、合并读库、gzip 与深度热力同一套：
//!   不要登录，同样的请求（同一分钟的区间）20 秒内合成一次读库，答复带 `Cache-Control: public, max-age=20`，读库占 `HISTORY_READS`。
//!   只聚合，不判定。
use super::book::Side;
use super::model::Thresholds;
use super::{Answer,Answers,HISTORY_READS,POOL,REGISTRY,WRITE_SLOTS,accepts_gzip,json_number,now_ms,packed,store};
use crate::AppState;
use crate::error::{ApiError,Params,Result};
use crate::orderflow_instruments as instruments;
use axum::extract::State;
use axum::response::Response;
use serde::Deserialize;
use sqlx::{PgPool,Row as _};
use std::collections::BTreeMap;
use std::sync::OnceLock;
use std::sync::atomic::{AtomicU64,Ordering};
use std::time::Duration;
use tokio::sync::mpsc;

pub(super) const PATH:&str="/v1/market/orderflow/flow";
const MINUTE_MS:i64=60_000;
/// 散户线：一笔不到 1 万美元。
pub(super) const SMALL_USD:f64=10_000.0;
/// 大单线 = 门槛 ÷ 这个数。
const BIG_DIVISOR:f64=50.0;
/// 同样的请求合成一次读库、答复留多久；也是答复头上 `max-age` 的秒数。一分钟才多一行，网页每分钟增量拉一次。
const FLOW_TTL:Duration=Duration::from_secs(20);
const CACHE_CONTROL:&str="public, max-age=20";
const MAX_SPAN_MS:i64=store::RETENTION_MS;
/// 跟踪任务到写库任务的通道（一项是一只 base 的一分钟）：220 只一分钟交一次，放得下好几分钟。
const QUEUE:usize=4096;
/// 一条 INSERT 最多几行（每行 6 个参数）。
const INSERT_ROWS:usize=2_000;
const PENDING_CAP:usize=20_000;
const DELETE_BATCH:i64=20_000;
const REPORT:Duration=Duration::from_secs(60*60);

/// 一只 base 一分钟的四个数（美元）。
#[derive(Clone,Debug,Default,PartialEq)]
pub(super) struct Minute {pub minute_ms:i64,pub big_buy:f64,pub big_sell:f64,pub small_buy:f64,pub small_sell:f64}

/// 大单线：门槛（U 本位永续，没有取现货，再没有取币本位 / 交割里小的那个）的 1/50。门槛都没有为 None。
pub(super) fn big_cut(t:&Thresholds)->Option<f64> {
 let min=[t.coin_perp,t.delivery].into_iter().flatten().filter(|v|v.is_finite()&&*v>0.0).fold(None,|m:Option<f64>,v|Some(m.map_or(v,|m|m.min(v))));
 t.usdt_perp.or(t.spot).or(min).filter(|v|v.is_finite()&&*v>0.0).map(|v|v/BIG_DIVISOR)
}

/// 跟踪任务手里正在攒的这一分钟。
#[derive(Debug,Default)]
pub(super) struct Acc {current:Option<Minute>}

impl Acc {
 /// 进一笔（美元额、是不是主动买、此刻的大单线、收到的时刻）。跨进了下一分钟就把上一分钟交出来。
 /// 大单线还没有的不记（照样把过完的那一分钟交出来）。
 pub fn add(&mut self,usd:f64,buy:bool,cut:Option<f64>,now:i64)->Option<Minute> {
  let done=self.roll(now);
  let Some(cut)=cut else {return done};
  if !(usd.is_finite()&&usd>0.0) {return done}
  let minute_ms=now.div_euclid(MINUTE_MS)*MINUTE_MS;
  let m=self.current.get_or_insert_with(||Minute{minute_ms,..Minute::default()});
  if usd>=cut {if buy {m.big_buy+=usd} else {m.big_sell+=usd}}
  if usd<SMALL_USD {if buy {m.small_buy+=usd} else {m.small_sell+=usd}}
  done
 }
 /// 这一分钟过完了就交出来。
 pub fn roll(&mut self,now:i64)->Option<Minute> {
  if self.current.as_ref().is_some_and(|m|now>=m.minute_ms+MINUTE_MS) {self.current.take()} else {None}
 }
 /// 停下时把没过完的这一分钟也交出来（下一任接着加到同一行上）。
 pub fn take(&mut self)->Option<Minute> {self.current.take()}
}

// ------------------------------------------------------------------ 写库

static TX:OnceLock<mpsc::Sender<(String,Minute)>>=OnceLock::new();
static DROPPED:AtomicU64=AtomicU64::new(0);

/// 起写库任务（serve 进程起订单流时一次）。
pub(super) fn start(pool:PgPool) {
 TX.get_or_init(||{
  let (tx,rx)=mpsc::channel(QUEUE);
  tokio::spawn(writer(pool,rx));
  tx
 });
}

/// 跟踪任务交一分钟：不等，通道满了就丢。
pub(super) fn submit(base:&str,m:Option<Minute>) {
 let (Some(m),Some(tx))=(m,TX.get()) else {return};
 if tx.try_send((base.to_string(),m)).is_err() {DROPPED.fetch_add(1,Ordering::Relaxed);}
}

/// 一批里同一（base，分钟）的先合成一行：一条 `ON CONFLICT DO UPDATE` 不能两次碰同一行。
fn merge(rows:Vec<(String,Minute)>)->Vec<(String,Minute)> {
 let mut by:BTreeMap<(String,i64),Minute>=BTreeMap::new();
 for (base,m) in rows {
  let e=by.entry((base,m.minute_ms)).or_insert_with(||Minute{minute_ms:m.minute_ms,..Minute::default()});
  e.big_buy+=m.big_buy;e.big_sell+=m.big_sell;e.small_buy+=m.small_buy;e.small_sell+=m.small_sell;
 }
 by.into_iter().map(|((base,_),m)|(base,m)).collect()
}

async fn writer(pool:PgPool,mut rx:mpsc::Receiver<(String,Minute)>) {
 let (mut written,mut failed)=(0u64,0u64);
 let mut report=tokio::time::Instant::now()+REPORT;
 let mut warned:Option<tokio::time::Instant>=None;
 while let Some(first)=rx.recv().await {
  let mut rows=vec![first];
  while rows.len()<PENDING_CAP && let Ok(more)=rx.try_recv() {rows.push(more);}
  let rows=merge(rows);
  let Ok(_slot)=WRITE_SLOTS.acquire().await else {return};
  for chunk in rows.chunks(INSERT_ROWS) {
   match insert(&pool,chunk).await {
    Ok(())=>written+=chunk.len() as u64,
    Err(e)=>{
     failed+=chunk.len() as u64;
     if warned.is_none_or(|at|at.elapsed()>=Duration::from_secs(60)) {warned=Some(tokio::time::Instant::now());tracing::warn!("Orderflow flow: write failed, {} minutes dropped: {e}",chunk.len());}
    },
   }
  }
  drop(_slot);
  if tokio::time::Instant::now()>=report {
   tracing::info!("Orderflow flow: last {}s wrote {written} base-minutes; dropped {} (queue full), {failed} (write failed)",REPORT.as_secs(),DROPPED.swap(0,Ordering::Relaxed));
   (written,failed)=(0,0);
   report=tokio::time::Instant::now()+REPORT;
  }
 }
}

async fn insert(pool:&PgPool,rows:&[(String,Minute)])->sqlx::Result<()> {
 let mut q=sqlx::QueryBuilder::<sqlx::Postgres>::new("INSERT INTO orderflow_flow(base,minute_ms,big_buy,big_sell,small_buy,small_sell) ");
 q.push_values(rows,|mut b,(base,m)|{
  b.push_bind(base).push_bind(m.minute_ms).push_bind(m.big_buy).push_bind(m.big_sell).push_bind(m.small_buy).push_bind(m.small_sell);
 });
 // 停机交出的半分钟与重启后接着的另半分钟加在一起。
 q.push(" ON CONFLICT(base,minute_ms) DO UPDATE SET big_buy=orderflow_flow.big_buy+EXCLUDED.big_buy,big_sell=orderflow_flow.big_sell+EXCLUDED.big_sell,\
  small_buy=orderflow_flow.small_buy+EXCLUDED.small_buy,small_sell=orderflow_flow.small_sell+EXCLUDED.small_sell");
 q.build().execute(pool).await.map(|_|())
}

// ------------------------------------------------------------------ 清理

/// 每小时一次：逐只 base 按主键删 3 天以前的。
pub(super) async fn purge(pool:&PgPool,now:i64)->sqlx::Result<u64> {
 let cutoff=now-store::RETENTION_MS;
 let mut deleted=0;
 for base in store::bases(pool).await? {
  loop {
   let n=sqlx::query("DELETE FROM orderflow_flow WHERE ctid=ANY(ARRAY(SELECT ctid FROM orderflow_flow WHERE base=$1 AND minute_ms<$2 LIMIT $3))")
    .bind(&base).bind(cutoff).bind(DELETE_BATCH).execute(pool).await?.rows_affected();
   deleted+=n;
   if n<DELETE_BATCH as u64 {break}
  }
 }
 Ok(deleted)
}

/// 表（含索引）此刻多大。
pub(super) async fn size(pool:&PgPool)->sqlx::Result<i64> {
 sqlx::query_scalar("SELECT pg_total_relation_size('orderflow_flow')").fetch_one(pool).await
}

// ------------------------------------------------------------------ 接口

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct FlowQuery {base:String,from:Option<i64>,to:Option<i64>}

/// 校验并补齐区间：`to` 缺省此刻，`from` 缺省 `to` 前 3 天；超过 3 天把 `from` 夹回来，不报错；两端按分钟向下取整。
fn window(from:Option<i64>,to:Option<i64>,now:i64)->std::result::Result<(i64,i64),&'static str> {
 let to=to.unwrap_or(now);
 let from=from.unwrap_or(to.saturating_sub(MAX_SPAN_MS));
 if from<0||to<0||from>to {return Err("invalid_range")}
 let floor=|v:i64|v.div_euclid(MINUTE_MS)*MINUTE_MS;
 Ok((floor(from.max(to-MAX_SPAN_MS)),floor(to)))
}

fn body(base:&str,big:Option<f64>,tracked:bool,rows:&[Minute])->String {
 let mut out=String::with_capacity(96+rows.len()*48);
 out.push_str("{\"base\":");out.push_str(&serde_json::Value::from(base).to_string());
 out.push_str(",\"bigUsd\":");
 match big {Some(v)=>json_number(&mut out,v.round()),None=>out.push_str("null")}
 out.push_str(",\"smallUsd\":");json_number(&mut out,SMALL_USD);
 out.push_str(",\"tracked\":");out.push_str(if tracked {"true"} else {"false"});
 out.push_str(",\"rows\":[");
 for (i,m) in rows.iter().enumerate() {
  if i>0 {out.push(',');}
  out.push('[');json_number(&mut out,m.minute_ms as f64);
  for v in [m.big_buy,m.big_sell,m.small_buy,m.small_sell] {out.push(',');json_number(&mut out,v.round());}
  out.push(']');
 }
 out.push_str("]}");
 out
}

async fn read(pool:&PgPool,base:&str,from:i64,to:i64)->sqlx::Result<Vec<Minute>> {
 let rows=sqlx::query("SELECT minute_ms,big_buy,big_sell,small_buy,small_sell FROM orderflow_flow WHERE base=$1 AND minute_ms BETWEEN $2 AND $3 ORDER BY minute_ms")
  .bind(base).bind(from).bind(to).fetch_all(pool).await?;
 Ok(rows.iter().map(|r|Minute{minute_ms:r.get(0),big_buy:r.get(1),big_sell:r.get(2),small_buy:r.get(3),small_sell:r.get(4)}).collect())
}

#[derive(Clone,Debug,PartialEq,Eq,Hash)]
struct Key {base:String,from:i64,to:i64,big:Option<u64>,gzip:bool}

static ANSWERS:std::sync::LazyLock<Answers<Key>>=std::sync::LazyLock::new(||Answers::new(FLOW_TTL));

fn answer(json:String,gzip:bool)->Result<Answer> {packed(json,gzip,CACHE_CONTROL)}

pub(super) async fn flow(State(s):State<AppState>,headers:axum::http::HeaderMap,Params(q):Params<FlowQuery>)->Result<Response> {
 if !instruments::valid_base(&q.base) {return Err(ApiError::bad("invalid_base"))}
 let (from,to)=window(q.from,q.to,now_ms()).map_err(ApiError::bad)?;
 let gzip=accepts_gzip(&headers);
 let registry=REGISTRY.get();
 // 没在跟的不读库、也不因此起跟（网页打开品种时数据层拉 `/history` 会起）。
 if !registry.is_some_and(|r|r.is_tracked(&q.base)) {return Ok(answer(body(&q.base,None,false,&[]),gzip)?.response())}
 let big=registry.and_then(|r|r.thresholds(&q.base)).as_ref().and_then(big_cut);
 let pool=POOL.get().unwrap_or(&s.pool);
 let key=Key{base:q.base.clone(),from,to,big:big.map(f64::to_bits),gzip};
 let answer=ANSWERS.get_or_build(key,||async {
  let busy=||ApiError(axum::http::StatusCode::SERVICE_UNAVAILABLE,"temporarily_unavailable");
  let _slot=HISTORY_READS.acquire().await.map_err(|_|busy())?;
  let rows=read(pool,&q.base,from,to).await?;
  drop(_slot);
  answer(body(&q.base,big,true,&rows),gzip)
 }).await?;
 Ok(answer.response())
}

/// 一笔成交是不是主动买：吃掉的是卖一。
pub(super) fn is_buy(hit:Side)->bool {hit==Side::Ask}

#[cfg(test)]
mod tests {
 use super::*;

 fn t(usdt_perp:Option<f64>,spot:Option<f64>,coin:Option<f64>,delivery:Option<f64>)->Thresholds {Thresholds{spot,usdt_perp,coin_perp:coin,delivery,step:Some(1.0)}}

 #[test] fn the_big_line_is_a_fiftieth_of_the_tape_base() {
  assert_eq!(big_cut(&t(Some(5_000_000.0),Some(1_000_000.0),None,None)),Some(100_000.0),"U 本位优先");
  assert_eq!(big_cut(&t(None,Some(1_000_000.0),Some(3e6),None)),Some(20_000.0),"没有 U 本位取现货");
  assert_eq!(big_cut(&t(None,None,Some(3e6),Some(2e6))),Some(40_000.0),"再没有取币本位 / 交割里小的");
  assert_eq!(big_cut(&t(None,None,None,None)),None);
  assert_eq!(big_cut(&t(Some(0.0),None,None,None)),None);
 }

 #[test] fn trades_land_in_their_minute_and_split_big_and_small() {
  let mut a=Acc::default();
  let cut=Some(100_000.0);
  assert_eq!(a.add(150_000.0,true,cut,60_000),None);
  assert_eq!(a.add(200_000.0,false,cut,60_500),None);
  assert_eq!(a.add(5_000.0,true,cut,61_000),None);
  assert_eq!(a.add(9_999.0,false,cut,62_000),None);
  assert_eq!(a.add(50_000.0,true,cut,63_000),None,"中间那一段两边都不记");
  assert_eq!(a.add(0.0,true,cut,64_000),None);
  assert_eq!(a.roll(119_999),None,"这一分钟还没过完");
  let done=a.add(1_000.0,true,cut,120_000).expect("跨进下一分钟交出上一分钟");
  assert_eq!(done,Minute{minute_ms:60_000,big_buy:150_000.0,big_sell:200_000.0,small_buy:5_000.0,small_sell:9_999.0});
  assert_eq!(a.roll(180_000),Some(Minute{minute_ms:120_000,small_buy:1_000.0,..Minute::default()}),"没有新成交也按时交");
  assert_eq!(a.roll(300_000),None,"交过就空了");
 }

 #[test] fn nothing_is_counted_before_the_threshold_exists_and_a_stop_hands_over_the_partial_minute() {
  let mut a=Acc::default();
  assert_eq!(a.add(500_000.0,true,None,0),None);
  assert_eq!(a.take(),None,"门槛还没有的这段不记");
  a.add(500_000.0,false,Some(1_000.0),30_000);
  assert_eq!(a.take(),Some(Minute{minute_ms:0,big_sell:500_000.0,..Minute::default()}));
  assert!(is_buy(Side::Ask)&&!is_buy(Side::Bid));
 }

 #[test] fn a_batch_merges_the_same_minute_before_the_upsert() {
  let m=|minute_ms,big_buy|Minute{minute_ms,big_buy,..Minute::default()};
  let out=merge(vec![("BTC".into(),m(0,1.0)),("ETH".into(),m(0,5.0)),("BTC".into(),m(0,2.0)),("BTC".into(),m(60_000,4.0))]);
  assert_eq!(out,vec![("BTC".into(),m(0,3.0)),("BTC".into(),m(60_000,4.0)),("ETH".into(),m(0,5.0))]);
 }

 #[test] fn window_defaults_to_three_days_floors_to_minutes_and_clamps() {
  let now=10*store::DAY_MS+12_345;
  assert_eq!(window(None,None,now),Ok((7*store::DAY_MS,10*store::DAY_MS)));
  assert_eq!(window(Some(0),Some(now),now),Ok((7*store::DAY_MS,10*store::DAY_MS)),"超过 3 天夹回来");
  assert_eq!(window(Some(61_000),Some(125_000),now),Ok((60_000,120_000)));
  assert_eq!(window(Some(5),Some(4),now),Err("invalid_range"));
  assert_eq!(window(Some(-1),None,now),Err("invalid_range"));
  assert_eq!(window(None,Some(i64::MIN),now),Err("invalid_range"));
 }

 #[test] fn body_has_the_agreed_shape() {
  let rows=[Minute{minute_ms:60_000,big_buy:150_000.4,big_sell:0.0,small_buy:5_000.6,small_sell:1.0}];
  assert_eq!(body("BTC",Some(100_000.0),true,&rows),r#"{"base":"BTC","bigUsd":100000,"smallUsd":10000,"tracked":true,"rows":[[60000,150000,0,5001,1]]}"#);
  let v:serde_json::Value=serde_json::from_str(&body("MU",None,false,&[])).unwrap();
  assert_eq!(v,serde_json::json!({"base":"MU","bigUsd":null,"smallUsd":10000,"tracked":false,"rows":[]}));
 }

 #[test] fn answers_are_publicly_cacheable_for_twenty_seconds() {
  let a=answer(body("BTC",None,true,&[]),true).unwrap().response();
  assert_eq!(a.headers()[axum::http::header::CACHE_CONTROL],"public, max-age=20");
  assert_eq!(a.headers()[axum::http::header::CONTENT_ENCODING],"gzip");
 }

 #[tokio::test] async fn minutes_add_up_across_a_restart_and_old_ones_are_purged() {
  let Some(pool)=store::tests::isolated_pool().await else {return};
  let base="FLOWTEST";
  sqlx::query("DELETE FROM orderflow_flow WHERE base=$1").bind(base).execute(&pool).await.unwrap();
  let now=10*store::DAY_MS;
  // 清理的名单取自 orderflow_bases：跟踪器起跟时登记。
  store::start(&pool,base,now).await.unwrap();
  let m=|minute_ms,big_buy,small_sell|Minute{minute_ms,big_buy,small_sell,..Minute::default()};
  let old=now-store::RETENTION_MS-MINUTE_MS;
  insert(&pool,&[(base.into(),m(now-120_000,100.0,1.0)),(base.into(),m(now-60_000,50.0,0.0)),(base.into(),m(old,9.0,9.0))]).await.unwrap();
  // 停机交出的半分钟 + 重启后的另半分钟：加在一起。
  insert(&pool,&[(base.into(),m(now-60_000,25.0,2.0))]).await.unwrap();
  let rows=read(&pool,base,now-store::RETENTION_MS,now).await.unwrap();
  assert_eq!(rows,vec![m(now-120_000,100.0,1.0),m(now-60_000,75.0,2.0)]);
  assert_eq!(purge(&pool,now).await.unwrap(),1);
  let left:i64=sqlx::query_scalar("SELECT count(*) FROM orderflow_flow WHERE base=$1").bind(base).fetch_one(&pool).await.unwrap();
  assert_eq!(left,2);
  sqlx::query("DELETE FROM orderflow_flow WHERE base=$1").bind(base).execute(&pool).await.unwrap();
  sqlx::query("DELETE FROM orderflow_bases WHERE base=$1").bind(base).execute(&pool).await.unwrap();
 }
}
