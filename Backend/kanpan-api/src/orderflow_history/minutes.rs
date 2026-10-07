//! 一只 base 一分钟一行、内容打包成一段字节的历史表（2026-10-07：足迹图 `orderflow_footprint`、秒线 `klines_seconds`）共用的写库与清理。
//!
//! * 写库：跟踪任务把收完的一分钟交给这张表的写库任务（通道满了丢，不堵跟踪任务）；写库任务攒一批，同一（base，分钟）先合成一行，
//!   一条多行 `INSERT … ON CONFLICT DO NOTHING RETURNING` 写进去。库里已经有这一分钟的（停机交出的半分钟、重启后的另半分钟、
//!   晚到几秒的几笔）在一个事务里 `SELECT … FOR UPDATE` 读出来、在这边合并、写回去——打包的字节没法在 SQL 里相加。写库占 `WRITE_SLOTS` 的一条。
//! * 清理：每小时和订单流的滚动清理一起，逐只 base 按主键删 3 天以前的（`store::RETENTION_MS`）；再看这张表的磁盘预算
//!   （`storage_budget`），超了从最旧的 6 小时一截一截往后删到线下 10%。
use super::{WRITE_SLOTS,store};
use crate::storage_budget::{self,Budget};
use sqlx::postgres::{PgPool,PgRow,Postgres};
use sqlx::query_builder::Separated;
use std::collections::{BTreeMap,HashSet};
use std::sync::atomic::{AtomicU64,Ordering};
use std::time::Duration;
use tokio::sync::mpsc;

pub(super) const MINUTE_MS:i64=60_000;
/// 一条 INSERT 最多几行。
const INSERT_ROWS:usize=1_000;
const PENDING_CAP:usize=10_000;
const DELETE_BATCH:i64=10_000;
const REPORT:Duration=Duration::from_secs(60*60);

/// 一行：这一分钟、打包前的内容。
pub(super) trait Row:Send+Sync+Sized+'static {
 const TABLE:&'static str;
 /// 除 `base`、`minute_ms` 以外的列，按 `push_binds` / `from_pg` 的顺序。
 const COLUMNS:&'static str;
 const BUDGET:Budget;
 /// 这张表交不进写库通道（满了）丢了几分钟，每小时报一次清零。
 fn dropped()->&'static AtomicU64;
 fn minute_ms(&self)->i64;
 /// 把同一分钟后来的那一份并进来（`self` 是先到的）。
 fn merge(&mut self,later:Self);
 fn push_binds(&self,b:&mut Separated<'_,'_,Postgres,&'static str>);
 /// 从 `SELECT minute_ms,{COLUMNS}` 读出来的一行还原；字节坏了回 None。
 fn from_pg(row:&PgRow)->Option<Self>;
}

/// 一批里同一（base，分钟）的先合成一行。
pub(super) fn merge<R:Row>(rows:Vec<(String,R)>)->Vec<(String,R)> {
 let mut by:BTreeMap<(String,i64),R>=BTreeMap::new();
 for (base,row) in rows {
  match by.entry((base,row.minute_ms())) {
   std::collections::btree_map::Entry::Vacant(e)=>{e.insert(row);},
   std::collections::btree_map::Entry::Occupied(mut e)=>e.get_mut().merge(row),
  }
 }
 by.into_iter().map(|((base,_),row)|(base,row)).collect()
}

pub(super) fn channel<R:Row>(pool:PgPool,queue:usize)->mpsc::Sender<(String,R)> {
 let (tx,rx)=mpsc::channel(queue);
 tokio::spawn(writer(pool,rx));
 tx
}

/// 交收完的几分钟：不等，通道满了就丢（记在这张表的 `dropped` 上）。
pub(super) fn submit<R:Row>(tx:Option<&mpsc::Sender<(String,R)>>,base:&str,rows:Vec<R>) {
 let Some(tx)=tx else {return};
 for row in rows {
  if tx.try_send((base.to_string(),row)).is_err() {R::dropped().fetch_add(1,Ordering::Relaxed);}
 }
}

async fn writer<R:Row>(pool:PgPool,mut rx:mpsc::Receiver<(String,R)>) {
 let (mut written,mut merged,mut failed)=(0u64,0u64,0u64);
 let mut report=tokio::time::Instant::now()+REPORT;
 let mut warned:Option<tokio::time::Instant>=None;
 while let Some(first)=rx.recv().await {
  let mut rows=vec![first];
  while rows.len()<PENDING_CAP && let Ok(more)=rx.try_recv() {rows.push(more);}
  let mut rows=merge(rows);
  let Ok(_slot)=WRITE_SLOTS.acquire().await else {return};
  while !rows.is_empty() {
   let rest=rows.split_off(rows.len().min(INSERT_ROWS));
   let n=rows.len() as u64;
   match write(&pool,rows).await {
    Ok(m)=>{written+=n;merged+=m;},
    Err(e)=>{
     failed+=n;
     if warned.is_none_or(|at|at.elapsed()>=Duration::from_secs(60)) {warned=Some(tokio::time::Instant::now());tracing::warn!("Orderflow {}: write failed, {n} minutes dropped: {e}",R::TABLE);}
    },
   }
   rows=rest;
  }
  drop(_slot);
  if tokio::time::Instant::now()>=report {
   tracing::info!("Orderflow {}: last {}s wrote {written} base-minutes ({merged} merged into existing rows); dropped {} (queue full), {failed} (write failed)",
    R::TABLE,REPORT.as_secs(),R::dropped().swap(0,Ordering::Relaxed));
   (written,merged,failed)=(0,0,0);
   report=tokio::time::Instant::now()+REPORT;
  }
 }
}

/// 写一批（同一（base，分钟）已经合过）：新的直接插，库里已有的读出来合并再写回。回合并了几行。
pub(super) async fn write<R:Row>(pool:&PgPool,rows:Vec<(String,R)>)->sqlx::Result<u64> {
 if rows.is_empty() {return Ok(0)}
 let mut q=sqlx::QueryBuilder::<Postgres>::new(format!("INSERT INTO {}(base,minute_ms,{}) ",R::TABLE,R::COLUMNS));
 q.push_values(&rows,|mut b,(base,row)|{
  b.push_bind(base.clone()).push_bind(row.minute_ms());
  row.push_binds(&mut b);
 });
 q.push(" ON CONFLICT(base,minute_ms) DO NOTHING RETURNING base,minute_ms");
 let inserted:HashSet<(String,i64)>=q.build_query_as::<(String,i64)>().fetch_all(pool).await?.into_iter().collect();
 let mut merged=0;
 for (base,row) in rows {
  if inserted.contains(&(base.clone(),row.minute_ms())) {continue}
  let mut tx=pool.begin().await?;
  let existing=sqlx::query(&format!("SELECT minute_ms,{} FROM {} WHERE base=$1 AND minute_ms=$2 FOR UPDATE",R::COLUMNS,R::TABLE))
   .bind(&base).bind(row.minute_ms()).fetch_optional(&mut *tx).await?;
  // 坏了的旧行（读不回来）让新的盖掉；中间被清理删掉的照新的写。
  let row=match existing.as_ref().and_then(R::from_pg) {Some(mut old)=>{old.merge(row);old},None=>row};
  let mut q=sqlx::QueryBuilder::<Postgres>::new(format!("INSERT INTO {}(base,minute_ms,{}) ",R::TABLE,R::COLUMNS));
  q.push_values(std::iter::once(&row),|mut b,row|{
   b.push_bind(base.clone()).push_bind(row.minute_ms());
   row.push_binds(&mut b);
  });
  q.push(format!(" ON CONFLICT(base,minute_ms) DO UPDATE SET ({})=ROW({})",R::COLUMNS,
   R::COLUMNS.split(',').map(|c|format!("EXCLUDED.{}",c.trim())).collect::<Vec<_>>().join(",")));
  q.build().execute(&mut *tx).await?;
  tx.commit().await?;
  merged+=1;
 }
 Ok(merged)
}

/// 逐只 base 按主键删 `minute_ms < cutoff` 的，一条语句最多 `DELETE_BATCH` 行。
async fn delete_before(pool:&PgPool,table:&str,bases:&[String],cutoff:i64)->sqlx::Result<u64> {
 let mut deleted=0;
 for base in bases {
  loop {
   let n=sqlx::query(&format!("DELETE FROM {table} WHERE ctid=ANY(ARRAY(SELECT ctid FROM {table} WHERE base=$1 AND minute_ms<$2 LIMIT $3))"))
    .bind(base).bind(cutoff).bind(DELETE_BATCH).execute(pool).await?.rows_affected();
   deleted+=n;
   if n<DELETE_BATCH as u64 {break}
  }
 }
 Ok(deleted)
}

/// 每小时一次：删 3 天以前的；表文件超过这张表的预算再从最旧的往后删到线下 10%（最近 6 小时不动）。回删了几行。
pub(super) async fn purge<R:Row>(pool:&PgPool,now:i64)->sqlx::Result<u64> {
 let bases=store::bases(pool).await?;
 let cutoff=now-store::RETENTION_MS;
 let mut deleted=delete_before(pool,R::TABLE,&bases,cutoff).await?;
 let budget=R::BUDGET;
 if storage_budget::over(pool,&budget).await?.is_some() {
  let average:Option<f64>=sqlx::query_scalar(&format!("SELECT avg(pg_column_size(t.*))::float8 FROM {} t WHERE base=ANY($1) AND minute_ms>=$2",R::TABLE))
   .bind(&bases).bind(now-3_600_000).fetch_one(pool).await?;
  let (live,per_row)=storage_budget::estimate(pool,R::TABLE,average.unwrap_or(1_000.0)).await?;
  let live=live-deleted as f64*per_row;
  let (done,n)=storage_budget::trim(live,budget.target(),per_row,cutoff,now-store::DAY_MS/4,store::DAY_MS/4,|_,to|{
   let bases=&bases;
   async move {delete_before(pool,R::TABLE,bases,to).await}
  }).await?;
  deleted+=n;
  if done>cutoff {tracing::warn!("Orderflow {}: size gate trimmed to minute_ms >= {done}",R::TABLE);}
 }
 Ok(deleted)
}

// ------------------------------------------------------------------ 打包用的小件

/// 无符号变长整数（每字节 7 位，高位为 1 表示后面还有）。
pub(super) fn put_uvarint(out:&mut Vec<u8>,mut v:u64) {
 while v>=0x80 {out.push((v as u8)|0x80);v>>=7;}
 out.push(v as u8);
}
pub(super) fn put_varint(out:&mut Vec<u8>,v:i64) {put_uvarint(out,((v<<1)^(v>>63)) as u64)}

/// 从字节里按顺序往外读。
pub(super) struct Reader<'a> {bytes:&'a [u8],at:usize}
impl<'a> Reader<'a> {
 pub fn new(bytes:&'a [u8])->Self {Self{bytes,at:0}}
 pub fn done(&self)->bool {self.at>=self.bytes.len()}
 fn take<const N:usize>(&mut self)->Option<[u8;N]> {
  let s=self.bytes.get(self.at..self.at+N)?;
  self.at+=N;
  s.try_into().ok()
 }
 pub fn u64(&mut self)->Option<u64> {self.take::<8>().map(u64::from_le_bytes)}
 pub fn i64(&mut self)->Option<i64> {self.take::<8>().map(i64::from_le_bytes)}
 pub fn f32(&mut self)->Option<f32> {self.take::<4>().map(f32::from_le_bytes)}
 pub fn uvarint(&mut self)->Option<u64> {
  let mut v=0u64;
  for shift in (0..64).step_by(7) {
   let b=*self.bytes.get(self.at)?;
   self.at+=1;
   v|=u64::from(b&0x7f)<<shift;
   if b<0x80 {return Some(v)}
  }
  None
 }
 pub fn varint(&mut self)->Option<i64> {self.uvarint().map(|u|((u>>1) as i64)^-((u&1) as i64))}
}

/// 交易所给的成交时刻和此刻差得比这多就不信它（本机或交易所的钟歪了），按收到的时刻算。
pub(super) const SKEW_MS:i64=10_000;
/// 一分钟过完再等多久才交出去（交易所时刻晚到一两秒的几笔还能落进它那一分钟）。
pub(super) const GRACE_MS:i64=3_000;

/// 一笔成交算在哪一刻：交易所给的时刻，离此刻太远或没给就用收到的时刻。
pub(super) fn trade_time(at:Option<i64>,now:i64)->i64 {at.filter(|a|(a-now).abs()<=SKEW_MS).unwrap_or(now)}

/// 这一分钟（起点）收完了吗：过了一分钟再加 `GRACE_MS`。
pub(super) fn closed(minute_ms:i64,now:i64)->bool {now>=minute_ms+MINUTE_MS+GRACE_MS}

/// 一个价在 `unit` 的整数倍上打几位小数刚好（最多 12 位）。
pub(super) fn decimals(unit:f64)->usize {
 for d in 0..=12 {
  let v=unit.abs()*10f64.powi(d as i32);
  let r=v.round();
  if r>=1.0&&(v-r).abs()<=1e-9*v {return d}
 }
 12
}

/// `count × unit` 按 `unit` 的小数位写出来，去掉末尾的 0（`600003 × 0.1` 写成 `60000.3`，不是 `60000.300000000003`）。
pub(super) fn push_fixed(out:&mut String,count:i64,unit:f64,places:usize) {
 let mut s=format!("{:.*}",places,count as f64*unit);
 if s.contains('.') {
  while s.ends_with('0') {s.pop();}
  if s.ends_with('.') {s.pop();}
 }
 if s=="-0" {s="0".into();}
 out.push_str(&s);
}

/// 接口里的 `symbol`（币安 U 本位永续的写法，`BTCUSDT`、`1000PEPEUSDT`、`PEPEUSDT`）→（base，价按几个币报）。
/// 不是 `…USDT` 或 base 不合法回 None。
pub(super) fn parse_symbol(symbol:&str)->Option<(String,f64)> {
 let listed=symbol.strip_suffix("USDT")?;
 let base=crate::orderflow_instruments::unscaled(listed);
 if !crate::orderflow_instruments::valid_base(base) {return None}
 let scale=if base==listed {1} else {
  crate::orderflow_instruments::BINANCE_SCALED.iter().find(|(prefix,_)|listed.strip_prefix(prefix)==Some(base)).map_or(1,|(_,s)|*s)
 };
 Some((base.to_string(),scale as f64))
}

/// 接口的区间：`to` 缺省此刻、`from` 缺省 `to` 前 `default`；超过 `max` 回 400（不夹），倒着的、负的也回 400。
pub(super) fn window(from:Option<i64>,to:Option<i64>,now:i64,default:i64,max:i64)->std::result::Result<(i64,i64),&'static str> {
 let to=to.unwrap_or(now);
 let from=from.unwrap_or(to.saturating_sub(default));
 if from<0||to<0||from>to {return Err("invalid_range")}
 if to-from>max {return Err("range_too_long")}
 Ok((from,to))
}

#[cfg(test)]
mod tests {
 use super::*;

 #[test] fn symbols_map_to_bases_and_their_price_scale() {
  assert_eq!(parse_symbol("BTCUSDT"),Some(("BTC".into(),1.0)));
  assert_eq!(parse_symbol("1000PEPEUSDT"),Some(("PEPE".into(),1000.0)));
  assert_eq!(parse_symbol("1000000MOGUSDT"),Some(("MOG".into(),1e6)));
  assert_eq!(parse_symbol("PEPEUSDT"),Some(("PEPE".into(),1.0)));
  assert_eq!(parse_symbol("BTCUSDC"),None);
  assert_eq!(parse_symbol("USDT"),None);
  assert_eq!(parse_symbol("btcusdt"),None);
 }

 #[test] fn windows_default_and_cap_without_clamping() {
  let h=3_600_000;
  assert_eq!(window(None,None,10*h,h,6*h),Ok((9*h,10*h)));
  assert_eq!(window(Some(4*h),Some(10*h),0,h,6*h),Ok((4*h,10*h)),"正好 6 小时可以");
  assert_eq!(window(Some(4*h-1),Some(10*h),0,h,6*h),Err("range_too_long"),"多 1 毫秒就 400");
  assert_eq!(window(Some(5),Some(4),0,h,6*h),Err("invalid_range"));
  assert_eq!(window(Some(-1),None,10*h,h,6*h),Err("invalid_range"));
  assert_eq!(window(None,Some(i64::MIN),0,h,6*h),Err("invalid_range"));
 }

 #[test] fn varints_round_trip() {
  let mut out=Vec::new();
  let values:[i64;7]=[0,1,-1,63,-64,1<<40,i64::MIN/2];
  for v in values {put_varint(&mut out,v);}
  put_uvarint(&mut out,u64::MAX);
  let mut r=Reader::new(&out);
  for v in values {assert_eq!(r.varint(),Some(v));}
  assert_eq!(r.uvarint(),Some(u64::MAX));
  assert!(r.done());
  assert_eq!(Reader::new(&[0x80]).uvarint(),None,"截断的字节读不出来");
  assert_eq!(Reader::new(&[1,2,3]).u64(),None);
 }

 #[test] fn exchange_time_is_trusted_only_near_now() {
  assert_eq!(trade_time(Some(1_000),5_000),1_000);
  assert_eq!(trade_time(Some(-20_000),5_000),5_000,"差太多不信");
  assert_eq!(trade_time(None,5_000),5_000);
  assert!(!closed(60_000,122_999)&&closed(60_000,123_000),"过完一分钟再等 3 秒");
 }

 #[test] fn fixed_prices_print_without_float_noise() {
  let mut s=String::new();
  push_fixed(&mut s,600_003,0.1,decimals(0.1));s.push(',');
  push_fixed(&mut s,12_000,0.0000001,decimals(0.0000001));s.push(',');
  push_fixed(&mut s,3,5.0,decimals(5.0));s.push(',');
  push_fixed(&mut s,7,0.25,decimals(0.25));
  assert_eq!(s,"60000.3,0.0012,15,1.75");
  assert_eq!((decimals(1.0),decimals(0.01),decimals(2e-8),decimals(1e-10),decimals(1e-7/1000.0)),(0,2,8,10,10),"很小的单位不能当成 0 位");
 }
}
