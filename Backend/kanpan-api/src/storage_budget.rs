//! 行情类历史的磁盘预算（2026-10-07）：一张常量表定死每张表各占多少，全仓库只有这里写预算数字。
//!
//! 服务端存行情历史的几张大表合起来不超过 [`TOTAL_GIB`]（用户 2026-10-07 定的总闸），按 [`BUDGETS`] 分到各自头上。
//! 每张表只看自己那一条线：超了只删自己最旧的，不挤别人。删法沿用原来那两道（不另起一套）：
//!
//! 1. 滚动：各自按自己的保留期删（订单流几张表 3 天、找相似的公开索引 365 天）。
//! 2. 体积闸门：表文件（`pg_total_relation_size`，含索引与 TOAST）超过这一条线才动手，
//!    按「行数 × 每行占用」估出来的实际占用删到线下 10%（[`TARGET_PERCENT`]），从最旧的一截一截往后删（[`trim`]）。
//!    删掉的空间留给以后的插入用，表文件不缩，所以只拿文件大小判断「要不要删」，删到哪儿看估算。
//!
//! 每小时订单流清理之后打一行合计（[`report`]），合计超过总闸记一条 warn。
use sqlx::PgPool;
use std::future::Future;

const GIB:u64=1<<30;

/// 一条预算：名字（日志里用）、算在它头上的表、上限（GiB）。
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub struct Budget {pub name:&'static str,pub tables:&'static [&'static str],pub gib:u64}

/// 行情历史合起来的总闸（GiB）。
pub const TOTAL_GIB:u64=30;

/// 唯一一张预算表。热力的预聚合段跟原始快照同一个截止时刻删，算在热力头上；
/// 订单流的大单（历史表 + 挂着的）分到总闸剩下的那 4 GiB（原来单独一条 20 GB 的闸门）。
pub const BUDGETS:[Budget;5]=[HEAT,FOOTPRINT,SECONDS,FEATURES,ORDERS];
pub const HEAT:Budget=Budget{name:"orderflow_heat",tables:&["orderflow_heat","orderflow_heat_rollup_30s","orderflow_heat_rollup_150s","orderflow_heat_rollup_900s"],gib:20};
pub const FOOTPRINT:Budget=Budget{name:"orderflow_footprint",tables:&["orderflow_footprint"],gib:2};
pub const SECONDS:Budget=Budget{name:"klines_seconds",tables:&["klines_seconds"],gib:1};
pub const FEATURES:Budget=Budget{name:"market_features",tables:&["market_features"],gib:3};
pub const ORDERS:Budget=Budget{name:"orderflow_orders",tables:&["orderflow_orders","orderflow_live"],gib:4};

/// 闸门一动手就删到线的这个百分比以下。
pub const TARGET_PERCENT:u64=90;

const _:()={
 let mut sum=0;let mut i=0;
 while i<BUDGETS.len() {sum+=BUDGETS[i].gib;i+=1;}
 assert!(sum<=TOTAL_GIB,"各表预算加起来超过总闸");
};

impl Budget {
 pub const fn line(&self)->f64 {(self.gib*GIB) as f64}
 pub const fn target(&self)->f64 {(self.gib*GIB/100*TARGET_PERCENT) as f64}
}

/// 这条预算名下几张表此刻的文件大小（含索引与 TOAST）合计。表还没建（迁移没跑）算 0。
pub async fn size(pool:&PgPool,budget:&Budget)->sqlx::Result<i64> {
 let names:Vec<&str>=budget.tables.to_vec();
 sqlx::query_scalar("SELECT COALESCE(sum(pg_total_relation_size(to_regclass(t))),0)::bigint FROM unnest($1::text[]) t")
  .bind(names).fetch_one(pool).await
}

/// 文件超过这条线了吗：超了回此刻的文件大小。
pub async fn over(pool:&PgPool,budget:&Budget)->sqlx::Result<Option<i64>> {
 let size=size(pool,budget).await?;
 Ok((size as f64>budget.line()).then_some(size))
}

/// 一张表里活着的数据估多大：行数（`reltuples`，上一次 ANALYZE 的估计）×（每行平均大小 `row` + 行头与行指针 28 字节）
/// ×（含索引的总大小 ÷ 不含索引的大小）。`row` 由调用方从最近写的一小撮行上量（各表取样的条件不一样）。
/// 回（估出来的占用，每行折合多少字节——删一行往下扣多少）。
pub async fn estimate(pool:&PgPool,table:&str,row:f64)->sqlx::Result<(f64,f64)> {
 let (tuples,total,heap):(f32,i64,i64)=sqlx::query_as("SELECT GREATEST(reltuples,0)::real,pg_total_relation_size(oid),pg_table_size(oid) FROM pg_class WHERE oid=$1::regclass")
  .bind(table).fetch_one(pool).await?;
 let per_row=per_row(row,total,heap);
 Ok((tuples.max(0.0) as f64*per_row,per_row))
}

/// 一行折合多少字节：（平均大小 + 28）×（含索引的总大小 ÷ 不含索引的大小）。
pub fn per_row(row:f64,total:i64,heap:i64)->f64 {
 let indexes=if heap>0 {(total as f64/heap as f64).max(1.0)} else {1.0};
 (row.max(0.0)+28.0)*indexes
}

/// 闸门的第二道：估出来的占用 `live` 高于 `target` 就从 `cutoff` 起一截 `step` 一截地往后删（不越过 `limit`），
/// 每删一截按删掉的行数 × `per_row` 往下扣。`delete(from,to)` 删 `[from,to)` 这一截、回删了几行。
/// 回（删到的截止时刻，删了几行）；没动手时截止时刻原样回去。
pub async fn trim<F,Fut>(mut live:f64,target:f64,per_row:f64,mut cutoff:i64,limit:i64,step:i64,mut delete:F)->sqlx::Result<(i64,u64)>
where F:FnMut(i64,i64)->Fut,Fut:Future<Output=sqlx::Result<u64>> {
 let mut deleted=0;
 while live>target&&cutoff<limit&&step>0 {
  let next=cutoff.saturating_add(step).min(limit);
  let n=delete(cutoff,next).await?;
  deleted+=n;live-=n as f64*per_row;cutoff=next;
 }
 Ok((cutoff,deleted))
}

/// 每小时一行：各条预算此刻的文件大小与合计；合计超过总闸记 warn。
pub async fn report(pool:&PgPool) {
 let mut parts=Vec::with_capacity(BUDGETS.len());
 let mut total=0i64;
 for b in &BUDGETS {
  match size(pool,b).await {
   Ok(s)=>{total+=s;parts.push(format!("{} {:.2}/{} GiB",b.name,s as f64/GIB as f64,b.gib));},
   Err(e)=>{tracing::warn!("Storage budget: sizing {} failed: {e}",b.name);return},
  }
 }
 let gib=total as f64/GIB as f64;
 if total as f64>(TOTAL_GIB*GIB) as f64 {tracing::warn!("Storage budget: market history {gib:.2} GiB is over the {TOTAL_GIB} GiB total ({})",parts.join(", "));}
 else {tracing::info!("Storage budget: market history {gib:.2}/{TOTAL_GIB} GiB ({})",parts.join(", "));}
}

#[cfg(test)]
mod tests {
 use super::*;
 use std::cell::RefCell;

 #[test] fn the_table_adds_up_to_the_total_and_targets_are_ten_percent_under() {
  assert_eq!(BUDGETS.iter().map(|b|b.gib).sum::<u64>(),TOTAL_GIB);
  assert_eq!((HEAT.gib,FOOTPRINT.gib,SECONDS.gib,FEATURES.gib),(20,2,1,3));
  assert_eq!(SECONDS.line(),1073741824.0);
  assert_eq!(SECONDS.target(),SECONDS.line()*0.9);
  let names:std::collections::HashSet<&str>=BUDGETS.iter().flat_map(|b|b.tables.iter().copied()).collect();
  assert_eq!(names.len(),BUDGETS.iter().map(|b|b.tables.len()).sum::<usize>(),"一张表只算在一条预算头上");
 }

 #[test] fn per_row_counts_overhead_and_indexes() {
  assert_eq!(per_row(72.0,300,200),150.0);
  assert_eq!(per_row(72.0,0,0),100.0,"表还空着");
  assert_eq!(per_row(-1.0,100,200),28.0,"总大小不会比不含索引的小，放大至少 1 倍");
 }

 fn run<F:Future>(f:F)->F::Output {tokio::runtime::Builder::new_current_thread().build().unwrap().block_on(f)}

 #[test] fn the_gate_trims_oldest_slices_until_under_target_and_no_further() {
  // 每一截删 10 行、每行 10 字节：从 1000 字节删到 700 以下要删 4 截。
  let calls=RefCell::new(Vec::new());
  let (cutoff,deleted)=run(trim(1000.0,700.0,10.0,0,100,10,|from,to|{calls.borrow_mut().push((from,to));async {Ok(10)}})).unwrap();
  assert_eq!((cutoff,deleted),(40,40));
  assert_eq!(*calls.borrow(),vec![(0,10),(10,20),(20,30),(30,40)]);
 }

 #[test] fn the_gate_never_crosses_its_limit_and_does_nothing_when_under() {
  let (cutoff,deleted)=run(trim(1e12,1.0,1.0,0,25,10,|_,_|async {Ok(1)})).unwrap();
  assert_eq!((cutoff,deleted),(25,3),"最后一截收在 limit 上");
  let (cutoff,deleted)=run(trim(500.0,700.0,1.0,7,100,10,|_,_|async {panic!("线下不删")})).unwrap();
  assert_eq!((cutoff,deleted),(7,0));
  let (cutoff,_)=run(trim(1e12,1.0,1.0,50,40,10,|_,_|async {panic!("起点已过 limit")})).unwrap();
  assert_eq!(cutoff,50);
 }

 #[test] fn a_failed_delete_stops_the_gate() {
  let r=run(trim(1e12,1.0,1.0,0,100,10,|_,_|async {Err(sqlx::Error::PoolTimedOut)}));
  assert!(r.is_err());
 }
}
