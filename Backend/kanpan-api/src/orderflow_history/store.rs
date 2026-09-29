//! 大单的库：`orderflow_live`（挂着的，一单一行）、`orderflow_orders`（结束的，一单一行）与
//! `orderflow_bases`（跟踪过哪些 base）。迁移见 0024、0031。
//!
//! * 挂着的单每 15 秒整批 upsert 进 `orderflow_live`（几千行的小表，重写与停机刷新都落在这里）；
//!   结束的单一结束就写进 `orderflow_orders`、同一条语句里从 `orderflow_live` 删掉。
//!   挂着的只在 `orderflow_orders` 里没有这一单时才写（`NOT EXISTS`）：晚到的一批「挂着」不会把刚写进去的结束翻回去。
//!   0031 之前挂着的和结束的同在一张 200 万行的表里，挂着的散在各处、停机刷新一句 UPDATE 要 1 900 次冷随机读（1.5–2.5 秒）。
//! * 保留：按结束时刻滚动 3 天（2026-09-25 从 30 天改：没人往回看超过几天）；另有总量闸门，表文件超过 20 GB 时从结束得最早的删起、删到 18 GB 以下。
//!   删行不会让表文件变小（空间留给后来的行复用），所以「删到多少」按「行数 × 每行占用」估，不按文件大小——
//!   按文件大小会每小时都判超、一路删光。
use super::book::Side;
use super::model::{BigOrder,Restored,STALE_MS,Status};
use sqlx::{PgPool,Postgres,QueryBuilder,Row};

pub const DAY_MS:i64=86_400_000;
/// 结束的单留多久。
pub const RETENTION_MS:i64=3*DAY_MS;
/// 总量闸门：表文件超过它就删，删到估算占用低于 `GATE_TARGET`。
pub const GATE_BYTES:f64=20e9;
pub const GATE_TARGET:f64=18e9;
/// 一行连同三条索引大约占多少字节（堆上一行约 200 字节、主键与两条索引各约 50–80 字节，取整往大里估）。
pub const ROW_BYTES:f64=450.0;
/// 一条语句最多删几行：serve 的连接挂着 20 秒语句死线，一口气删几十万行会半路断。
const DELETE_BATCH:i64=10_000;
/// 一次最多回几条（3 天 BTC 的量级远低于它；这只是防御上限）。
pub const MAX_ROWS:i64=200_000;

const COLUMNS:&str="base,venue_id,exchange,product,side,bucket,price,first_seen_ms,end_ms,status,initial_notional,notional,filled_notional,threshold,vanished_notional,step,seen_ms";
const PK:&str="base,venue_id,side,bucket,first_seen_ms";
/// 两张表按主键对上的条件（`a`、`b` 是两边的别名）。
fn same(a:&str,b:&str)->String {format!("{a}.base={b}.base AND {a}.venue_id={b}.venue_id AND {a}.side={b}.side AND {a}.bucket={b}.bucket AND {a}.first_seen_ms={b}.first_seen_ms")}

/// 写一批（挂着的、刚结束的都走这里）。`seen` 为挂着的单最后一次看到的时刻，结束的单填结束时刻。
/// 先写结束的再写挂着的：同一批里（或前后两批）同一单先结束后又来一份「挂着」，`NOT EXISTS` 挡得住。
pub async fn upsert(pool:&PgPool,base:&str,step:f64,rows:&[(BigOrder,i64)])->sqlx::Result<()> {
 let (live,ended):(Vec<&(BigOrder,i64)>,Vec<&(BigOrder,i64)>)=rows.iter().partition(|(o,_)|o.end_ms.is_none());
 for chunk in ended.chunks(500) {write_ended(pool,base,step,chunk).await?;}
 for chunk in live.chunks(500) {write_live(pool,base,step,chunk).await?;}
 Ok(())
}

fn values<'a>(q:&mut QueryBuilder<'a,Postgres>,base:&'a str,step:f64,chunk:&'a [&'a (BigOrder,i64)]) {
 q.push_values(chunk,|mut b,(o,seen)| {
  b.push_bind(base).push_bind(&o.venue_id).push_bind(&o.exchange).push_bind(&o.product).push_bind(o.side.wire()).push_bind(o.bucket)
   .push_bind(o.price).push_bind(o.first_seen_ms).push_bind(o.end_ms).push_bind(o.status.wire()).push_bind(o.initial_notional)
   .push_bind(o.notional).push_bind(o.filled_notional).push_bind(o.threshold).push_bind(o.vanished_notional).push_bind(step).push_bind(*seen);
 });
}

/// 挂着的：写进 `orderflow_live`，`orderflow_orders` 里已经结束的那一单不写（晚到的「挂着」不翻回去）。
/// 已经在的更新价位、名义、成交、消失量；`seen_ms` 只往后推（停机刷新与写库任务两边谁后落都不倒退）。
async fn write_live(pool:&PgPool,base:&str,step:f64,chunk:&[&(BigOrder,i64)])->sqlx::Result<()> {
 let mut q=QueryBuilder::<Postgres>::new(format!("INSERT INTO orderflow_live({COLUMNS}) SELECT {COLUMNS} FROM ("));
 values(&mut q,base,step,chunk);
 q.push(format!(") AS v({COLUMNS}) WHERE NOT EXISTS (SELECT 1 FROM orderflow_orders o WHERE {}) \
  ON CONFLICT({PK}) DO UPDATE SET price=EXCLUDED.price,notional=EXCLUDED.notional,filled_notional=EXCLUDED.filled_notional,\
  threshold=EXCLUDED.threshold,vanished_notional=EXCLUDED.vanished_notional,seen_ms=GREATEST(orderflow_live.seen_ms,EXCLUDED.seen_ms)",same("o","v")));
 q.build().execute(pool).await?;
 Ok(())
}

/// 结束的：一条语句里写进 `orderflow_orders`、从 `orderflow_live` 删掉（数据修改 CTE，同一快照、一起提交）。
/// `orderflow_orders` 里已有的只改还挂着的行（0031 之前的老进程留下的）：结束写过一次就不再改。
async fn write_ended(pool:&PgPool,base:&str,step:f64,chunk:&[&(BigOrder,i64)])->sqlx::Result<()> {
 let mut q=QueryBuilder::<Postgres>::new(format!("WITH v({COLUMNS}) AS ("));
 values(&mut q,base,step,chunk);
 q.push(format!("), ins AS (INSERT INTO orderflow_orders({COLUMNS}) SELECT {COLUMNS} FROM v ON CONFLICT({PK}) DO UPDATE SET \
  price=EXCLUDED.price,end_ms=EXCLUDED.end_ms,status=EXCLUDED.status,notional=EXCLUDED.notional,filled_notional=EXCLUDED.filled_notional,\
  threshold=EXCLUDED.threshold,vanished_notional=EXCLUDED.vanished_notional,seen_ms=EXCLUDED.seen_ms WHERE orderflow_orders.end_ms IS NULL) \
  DELETE FROM orderflow_live l USING v WHERE {}",same("l","v")));
 q.build().execute(pool).await?;
 Ok(())
}

/// 0031 之前的老进程写进 `orderflow_orders` 的挂着的行搬到 `orderflow_live`（活单表里已有同一单的以活单表为准）。
/// 读回与每小时清理都先做一次；平时这句碰不到行（走 `orderflow_orders_end` 的 `end_ms IS NULL` 段）。
async fn sweep(pool:&PgPool,base:&str)->sqlx::Result<u64> {
 Ok(sqlx::query(&format!("WITH moved AS (DELETE FROM orderflow_orders WHERE base=$1 AND end_ms IS NULL RETURNING {COLUMNS}) \
  INSERT INTO orderflow_live({COLUMNS}) SELECT {COLUMNS} FROM moved ON CONFLICT({PK}) DO NOTHING")).bind(base).execute(pool).await?.rows_affected())
}

/// 停机时要刷的一条挂着的单：主键加最后一次看到的时刻。
pub struct SeenRow<'a> {pub base:&'a str,pub venue_id:&'a str,pub side:Side,pub bucket:i64,pub first_seen_ms:i64,pub seen_ms:i64}

/// 停机收尾：一句 UPDATE 把所有挂着的单的 `seen_ms` 刷到跟踪器手里的最后一次看到。只动 `orderflow_live`（已结束的不在那里）；
/// 只往后推不往前拉（写库任务同时在写的一批里 `seen_ms` 可能更旧，`upsert` 对挂着的行也取大的，两边谁后落都不倒退）。
/// 库里还没有的（刚出现、还没刷过盘的）不在这里插，交给写库任务。返回改了几行。
pub async fn refresh_seen(pool:&PgPool,rows:&[SeenRow<'_>])->sqlx::Result<u64> {
 if rows.is_empty() {return Ok(0)}
 let base:Vec<&str>=rows.iter().map(|r|r.base).collect();
 let venue:Vec<&str>=rows.iter().map(|r|r.venue_id).collect();
 let side:Vec<&str>=rows.iter().map(|r|r.side.wire()).collect();
 let bucket:Vec<i64>=rows.iter().map(|r|r.bucket).collect();
 let first:Vec<i64>=rows.iter().map(|r|r.first_seen_ms).collect();
 let seen:Vec<i64>=rows.iter().map(|r|r.seen_ms).collect();
 let done=sqlx::query(&format!("UPDATE orderflow_live o SET seen_ms=v.seen_ms \
  FROM unnest($1::text[],$2::text[],$3::text[],$4::bigint[],$5::bigint[],$6::bigint[]) AS v(base,venue_id,side,bucket,first_seen_ms,seen_ms) \
  WHERE {} AND o.seen_ms<v.seen_ms",same("o","v")))
  .bind(base).bind(venue).bind(side).bind(bucket).bind(first).bind(seen).execute(pool).await?;
 Ok(done.rows_affected())
}

fn order(row:&sqlx::postgres::PgRow)->Option<BigOrder> {
 Some(BigOrder{
  venue_id:row.try_get("venue_id").ok()?,exchange:row.try_get("exchange").ok()?,product:row.try_get("product").ok()?,
  side:Side::parse(row.try_get::<&str,_>("side").ok()?)?,bucket:row.try_get("bucket").ok()?,price:row.try_get("price").ok()?,
  first_seen_ms:row.try_get("first_seen_ms").ok()?,end_ms:row.try_get("end_ms").ok()?,status:Status::parse(row.try_get::<&str,_>("status").ok()?)?,
  initial_notional:row.try_get("initial_notional").ok()?,notional:row.try_get("notional").ok()?,filled_notional:row.try_get("filled_notional").ok()?,
  threshold:row.try_get("threshold").ok()?,vanished_notional:row.try_get("vanished_notional").ok()?,
 })
}

/// 一只 base 还挂着的单（进程重启读回用）。先把历史表里还挂着的老行搬过来。
pub async fn live(pool:&PgPool,base:&str)->sqlx::Result<Vec<Restored>> {
 sweep(pool,base).await?;
 let rows=sqlx::query(&format!("SELECT {COLUMNS} FROM orderflow_live WHERE base=$1")).bind(base).fetch_all(pool).await?;
 Ok(rows.iter().filter_map(|r|Some(Restored{order:order(r)?,step:r.try_get("step").ok()?,seen_ms:r.try_get("seen_ms").ok()?})).collect())
}

/// `[from, to]` 里出现过的单：出现 ≤ to，且还挂着或结束 ≥ from。按出现时刻升序。
///
/// 拆成三段各走各的索引：还挂着的（`orderflow_live`，走主键的 base 段）；在窗口里结束的（结束时刻的区间扫）；
/// 跨过窗口右沿才结束的。写成一句 `end_ms IS NULL OR end_ms >= from` 的话，拉最近一天也要把整个月结束的行都扫一遍。
/// 线上走 [`range_each`]（边读边交）；攒成一张表的这两个只给测试核对结果用。
#[cfg(test)]
pub async fn range(pool:&PgPool,base:&str,from:i64,to:i64)->sqlx::Result<Vec<BigOrder>> {range_capped(pool,base,from,to,0,MAX_ROWS).await}

/// 超过 `cap` 条时留最新的：先按出现时刻倒序取 `cap` 条、再翻回升序。原来升序取前 `cap` 条，截掉的恰好是
/// 最新的那一段——图的右沿（此刻）空着，手机的增量游标也从截断处往后接，永远补不上。
#[cfg(test)]
async fn range_capped(pool:&PgPool,base:&str,from:i64,to:i64,min_life:i64,cap:i64)->sqlx::Result<Vec<BigOrder>> {
 let mut orders=Vec::new();
 range_each(pool,base,from,to,min_life,cap,|o|orders.push(o)).await?;
 Ok(orders)
}

/// 同 `range`，但一行一行交出来、不攒成一整张表（历史接口直接边读边写 JSON）。
///
/// 原来 `fetch_all` 把 20 万行 `PgRow` 全攒在手里，再转成 `BigOrder`、再转成 `serde_json::Value` 树、
/// 再序列化：一个请求常驻内存涨 690 MB（答复本身 62 MB），serve 的上限一共 1 GB。
/// 翻回升序交给库做（外面再套一层 ORDER BY），这里就能按到达顺序直接往外交。
///
/// `min_life`（毫秒，0 = 不滤）：已结束的单寿命（`end_ms − first_seen_ms`）短于它的不回，还挂着的一律回。
/// 写在结束的那两路各自的 WHERE 里（挂着的那一路没有结束时刻，不滤），`LIMIT` 之前就滤掉，
/// 20 万行的上限留给真要的行；仍走 `(base, end_ms)` 那条索引，只是多一个行过滤条件。
pub async fn range_each(pool:&PgPool,base:&str,from:i64,to:i64,min_life:i64,cap:i64,mut each:impl FnMut(BigOrder))->sqlx::Result<usize> {
 use futures_util::TryStreamExt;
 let sql=range_sql();
 let mut rows=sqlx::query(&sql).bind(base).bind(from).bind(to).bind(cap).bind(min_life).fetch(pool);
 let mut n=0;
 while let Some(row)=rows.try_next().await? {
  if let Some(o)=order(&row) {each(o);n+=1;}
 }
 Ok(n)
}

/// `range_each` 的查询：$1 base、$2 from、$3 to、$4 行数上限、$5 最短寿命。结束的两路都要走得上 `orderflow_orders_end`（测试里 EXPLAIN 核对）。
pub(super) fn range_sql()->String {
 let cols=COLUMNS;
 format!("SELECT * FROM (SELECT * FROM (\
  SELECT {cols} FROM orderflow_live WHERE base=$1 AND first_seen_ms<=$3 \
  UNION ALL SELECT {cols} FROM orderflow_orders WHERE base=$1 AND end_ms>=$2 AND end_ms<=$3 AND end_ms-first_seen_ms>=$5 \
  UNION ALL SELECT {cols} FROM orderflow_orders WHERE base=$1 AND end_ms>$3 AND first_seen_ms<=$3 AND end_ms-first_seen_ms>=$5\
  ) t ORDER BY first_seen_ms DESC,venue_id DESC,side DESC,bucket DESC LIMIT $4) newest \
  ORDER BY first_seen_ms,venue_id,side,bucket")
}

/// 跟踪器最后一次活着距今超过这么久，就算上一段断了：历史从下一次起跟的那一刻重新算起。
/// 跟踪器活着时每分钟记一次（见 `alive`）；部署重启那一两分钟不算断。
pub const GAP_MS:i64=10*60_000;

/// 历史从什么时候起是连着的：上一段断了（最后一次活着早于 `GAP_MS` 以前）就是此刻；
/// 从没记过活着（新 base，或 0026 之前的老行）照旧用 since。
pub fn continuous_since(since:i64,alive:Option<i64>,now:i64)->i64 {
 match alive {Some(alive) if alive<now-GAP_MS=>now.max(since),_=>since}
}

/// 有人要这只 base：记下时刻；第一次要的记下「从这一刻起有历史」。返回（since，最后一次活着）。
pub async fn touch(pool:&PgPool,base:&str,now:i64)->sqlx::Result<(i64,Option<i64>)> {
 sqlx::query_as("INSERT INTO orderflow_bases(base,since_ms,requested_ms) VALUES($1,$2,$2) \
  ON CONFLICT(base) DO UPDATE SET requested_ms=GREATEST(orderflow_bases.requested_ms,EXCLUDED.requested_ms) RETURNING since_ms,alive_ms")
  .bind(base).bind(now).fetch_one(pool).await
}

/// 跟踪器起跟：第一次跟的记下 since；上一段断了的把 since 重置到此刻（原来 since 永不更新，
/// 停了几天再跟，手机拿到的历史起点还是几天前，中间没跟的那段被当成「没有大单」）。
pub async fn start(pool:&PgPool,base:&str,now:i64)->sqlx::Result<()> {
 sqlx::query("INSERT INTO orderflow_bases(base,since_ms,requested_ms,alive_ms) VALUES($1,$2,0,$2) \
  ON CONFLICT(base) DO UPDATE SET since_ms=CASE WHEN orderflow_bases.alive_ms<$3 THEN GREATEST(orderflow_bases.since_ms,EXCLUDED.since_ms) \
  ELSE orderflow_bases.since_ms END,alive_ms=EXCLUDED.alive_ms")
  .bind(base).bind(now).bind(now-GAP_MS).execute(pool).await?;
 Ok(())
}

/// 跟踪器还活着、手里的都写进库了。
pub async fn alive(pool:&PgPool,base:&str,now:i64)->sqlx::Result<()> {
 sqlx::query("UPDATE orderflow_bases SET alive_ms=GREATEST(alive_ms,$2) WHERE base=$1").bind(base).bind(now).execute(pool).await?;
 Ok(())
}

/// 进程起来时接着跟哪些：最近 24 小时有人要过的（连同最后一次要的时刻），按最近要的先后。
pub async fn recent_bases(pool:&PgPool,now:i64)->sqlx::Result<Vec<(String,i64)>> {
 sqlx::query_as("SELECT base,requested_ms FROM orderflow_bases WHERE requested_ms>=$1 ORDER BY requested_ms DESC").bind(now-DAY_MS).fetch_all(pool).await
}

async fn bases(pool:&PgPool)->sqlx::Result<Vec<String>> {sqlx::query_scalar("SELECT base FROM orderflow_bases").fetch_all(pool).await}

/// 分批删：一条语句最多 `DELETE_BATCH` 行。返回删了多少。
async fn delete_ended_before(pool:&PgPool,base:&str,cutoff:i64)->sqlx::Result<u64> {
 let mut total=0;
 loop {
  let n=sqlx::query("DELETE FROM orderflow_orders WHERE ctid IN (SELECT ctid FROM orderflow_orders WHERE base=$1 AND end_ms<$2 LIMIT $3)")
   .bind(base).bind(cutoff).bind(DELETE_BATCH).execute(pool).await?.rows_affected();
  total+=n;
  if n<DELETE_BATCH as u64 {return Ok(total)}
 }
}

/// 正在跟的 base 上，挂着的行多久没刷新 `seen_ms` 就算没人管了：跟踪器手里的单最迟每 60 秒 + 15 秒重写一次
/// （库写不进去时在写库任务里退避重写），读回时两分钟没见的也已经当场结束——还这么久没动的，
/// 是结束那一笔没写进库、跟踪器手里已经没有的行。留足余量，不去碰跟踪器手里的。
pub const ORPHAN_MS:i64=30*60_000;

/// 挂着的行按最后一次看到失联结束的截止时刻：没在跟的缺席两分钟就算，正在跟的要等 `ORPHAN_MS`。
pub fn stale_cutoff(tracked:bool,now:i64)->i64 {now-if tracked {ORPHAN_MS} else {STALE_MS}}

/// 每小时一次：3 天以前结束的删掉；挂着却很久没看到的按最后一次看到时失联结束（截止见 `stale_cutoff`；
/// 从 `orderflow_live` 搬进 `orderflow_orders`，状态 lost、不记消失量）；估算体积超过闸门就从最旧的删起。返回（删了几行，失联结束几行）。
///
/// 原来只收没在跟的 base：正在跟的 base 上结束那笔没写进库的行，要等这只 base 停掉或进程重启才会结束，
/// 主币永远不停，图上那条线就一直画到「现在」。
pub async fn purge(pool:&PgPool,now:i64,tracked:&[String])->sqlx::Result<(u64,u64)> {
 let bases=bases(pool).await?;
 let mut deleted=0;
 for base in &bases {sweep(pool,base).await?;deleted+=delete_ended_before(pool,base,now-RETENTION_MS).await?;}
 let mut closed=0;
 for base in &bases {
  closed+=sqlx::query(&format!("WITH moved AS (DELETE FROM orderflow_live WHERE base=$1 AND seen_ms<$2 RETURNING *) \
   INSERT INTO orderflow_orders({COLUMNS}) SELECT base,venue_id,exchange,product,side,bucket,price,first_seen_ms,GREATEST(first_seen_ms,seen_ms),'lost',\
   initial_notional,notional,filled_notional,threshold,NULL,step,seen_ms FROM moved ON CONFLICT({PK}) DO NOTHING"))
   .bind(base).bind(stale_cutoff(tracked.contains(base),now)).execute(pool).await?.rows_affected();
 }
 // 总量闸门：表文件（pg_total_relation_size）超过 20 GB 才动手；删到「行数 × 每行占用」估出来的
 // 实际占用低于 18 GB。行数用 reltuples（上一次 ANALYZE 的估计，够用），删完按删掉的行数往下扣。
 let tuples:f32=sqlx::query_scalar("SELECT reltuples FROM pg_class WHERE oid='orderflow_orders'::regclass").fetch_one(pool).await?;
 let mut rows=(tuples.max(0.0) as f64)-deleted as f64;
 if size(pool).await? as f64>GATE_BYTES&&rows*ROW_BYTES>GATE_TARGET {
  let oldest:Option<i64>=sqlx::query_scalar("SELECT min(end_ms) FROM orderflow_orders WHERE end_ms IS NOT NULL").fetch_one(pool).await?;
  let mut cutoff=oldest.unwrap_or(now);
  while rows*ROW_BYTES>GATE_TARGET&&cutoff<now {
   cutoff+=DAY_MS/4;
   for base in &bases {
    let n=delete_ended_before(pool,base,cutoff).await?;
    deleted+=n;rows-=n as f64;
   }
  }
  tracing::warn!("Orderflow history: size gate trimmed to end_ms >= {cutoff}");
 }
 Ok((deleted,closed))
}

/// 两张表此刻的体积之和（容量实测用）。
pub async fn size(pool:&PgPool)->sqlx::Result<i64> {
 sqlx::query_scalar("SELECT pg_total_relation_size('orderflow_orders')+pg_total_relation_size('orderflow_live')").fetch_one(pool).await
}

#[cfg(test)]
pub(super) mod tests {
 use super::*;

 pub(in super::super) async fn isolated_pool()->Option<PgPool> {
  let (Ok(admin),Ok(url),Ok(role))=(std::env::var("KANPAN_TEST_ADMIN_URL"),std::env::var("KANPAN_TEST_DATABASE_URL"),std::env::var("KANPAN_TEST_ROLE")) else {
   eprintln!("Skipping the orderflow_orders database assertions: run ops/test.py for an isolated PostgreSQL");
   return None;
  };
  assert!(role.chars().all(|c|c.is_ascii_alphanumeric()||c=='_'));
  for target in [&admin,&url] {assert!(target.contains("@127.0.0.1:")||target.contains("@localhost:"),"tests must never target a database off this machine");}
  let admin=PgPool::connect(&admin).await.unwrap();
  sqlx::migrate!().run(&admin).await.unwrap();
  for sql in [format!("GRANT USAGE ON SCHEMA public TO {role}"),format!("GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO {role}")] {
   sqlx::query(&sql).execute(&admin).await.unwrap();
  }
  Some(PgPool::connect(&url).await.unwrap())
 }

 /// 两张表里都清掉这些 base 的行。
 pub(in super::super) async fn clear(pool:&PgPool,bases:&[&str]) {
  for table in ["orderflow_live","orderflow_orders","orderflow_bases"] {
   sqlx::query(&format!("DELETE FROM {table} WHERE base=ANY($1)")).bind(bases.iter().map(|b|b.to_string()).collect::<Vec<_>>()).execute(pool).await.unwrap();
  }
 }
 /// 一单在哪张表里、`seen_ms` 是多少：挂着的在 `orderflow_live`，结束的在 `orderflow_orders`；两张都没有给 None。
 async fn seen_of(pool:&PgPool,base:&str,bucket:i64)->Option<(&'static str,i64)> {
  for table in ["orderflow_live","orderflow_orders"] {
   if let Some(seen)=sqlx::query_scalar::<_,i64>(&format!("SELECT seen_ms FROM {table} WHERE base=$1 AND bucket=$2")).bind(base).bind(bucket).fetch_optional(pool).await.unwrap() {
    return Some((table,seen));
   }
  }
  None
 }

 fn order(bucket:i64,first:i64,end:Option<i64>)->BigOrder {
  BigOrder{venue_id:"binance:usdtPerp:BTCUSDT".into(),exchange:"币安".into(),product:"usdtPerp".into(),side:Side::Bid,bucket,price:bucket as f64*100.0,
   first_seen_ms:first,end_ms:end,status:if end.is_some() {Status::Cancelled} else {Status::Live},initial_notional:6e6,notional:6e6,
   filled_notional:0.0,threshold:5e6,vanished_notional:end.map(|_|6e6)}
 }

 #[test] fn history_starts_over_after_a_gap_in_tracking() {
  let now=100*DAY_MS;
  assert_eq!(continuous_since(now-2*DAY_MS,Some(now-30_000),now),now-2*DAY_MS,"一直在跟");
  assert_eq!(continuous_since(now-2*DAY_MS,Some(now-GAP_MS+1),now),now-2*DAY_MS,"重启那一会儿不算断");
  assert_eq!(continuous_since(now-2*DAY_MS,Some(now-DAY_MS),now),now,"停了一天：从此刻起算");
  assert_eq!(continuous_since(now,None,now),now,"新 base");
  assert_eq!(continuous_since(now-2*DAY_MS,None,now),now-2*DAY_MS,"0026 之前的老行：不知道断没断，照旧");
  // 心跳一分钟一次，远在断开判定以内。
  assert!(super::super::ALIVE_EVERY.as_millis() as i64*5<=GAP_MS);
 }

 #[test] fn tracked_bases_close_only_rows_the_tracker_no_longer_rewrites() {
  let now=100*DAY_MS;
  assert_eq!(stale_cutoff(false,now),now-STALE_MS);
  assert_eq!(stale_cutoff(true,now),now-ORPHAN_MS);
  // 跟踪器手里的行最迟 60 秒 + 一次 15 秒刷盘就会重写 seen_ms；写库退避最长 1 分钟。都远在 ORPHAN_MS 以内。
  let rewrite=super::super::LIVE_REWRITE_MS+super::super::FLUSH.as_millis() as i64+super::super::WRITE_RETRY_MAX.as_millis() as i64;
  assert!(rewrite*10<ORPHAN_MS);
 }

 /// `minLifeMs`：已结束的单寿命短于它的不回（边界上的回），还挂着的不管多短一律回；三路 UNION 里结束的两路都滤。
 #[tokio::test]
 async fn min_life_drops_only_short_ended_orders() {
  let Some(pool)=isolated_pool().await else {return};
  clear(&pool,&["ZZM"]).await;
  let now=100*DAY_MS;
  let rows=[
   (order(1,now-1_000,None),now),                                 // 挂着、才 1 秒
   (order(2,now-3_600_000,Some(now-3_600_000+299_999)),now),      // 窗口里结束、差 1 ms 到 5 分钟
   (order(3,now-3_000_000,Some(now-3_000_000+300_000)),now),      // 窗口里结束、正好 5 分钟
   (order(4,now-2*DAY_MS,Some(now-DAY_MS+1)),now),                 // 窗口里结束、活了一天多 1 ms
   (order(5,now-10_000,Some(now+5_000)),now+5_000),               // 跨过右沿才结束、15 秒
   (order(6,now-600_000,Some(now+5_000)),now+5_000),              // 跨过右沿才结束、10 分 5 秒
  ];
  upsert(&pool,"ZZM",100.0,&rows).await.unwrap();
  let buckets=|v:Vec<BigOrder>|v.iter().map(|o|o.bucket).collect::<Vec<_>>();
  assert_eq!(buckets(range_capped(&pool,"ZZM",now-DAY_MS,now,0,MAX_ROWS).await.unwrap()),vec![4,2,3,6,5,1],"0 = 不滤");
  assert_eq!(buckets(range_capped(&pool,"ZZM",now-DAY_MS,now,300_000,MAX_ROWS).await.unwrap()),vec![4,3,6,1],"短于 5 分钟的结束单不回，正好 5 分钟的回，挂着的回");
  assert_eq!(buckets(range_capped(&pool,"ZZM",now-DAY_MS,now,86_400_000,MAX_ROWS).await.unwrap()),vec![4,1],"上限一天：只剩挂着的与活满一天的");
  assert_eq!(buckets(range_capped(&pool,"ZZM",now-DAY_MS,now,300_000,2).await.unwrap()),vec![6,1],"先滤再截：上限只留给要回的行");
  clear(&pool,&["ZZM"]).await;
 }

 /// 停机那一句 UPDATE：只刷还挂着的行，只往后推；库里没有的不插。写库任务同时落一批更旧的 `seen_ms` 也拉不回去。
 #[tokio::test]
 async fn shutdown_refresh_moves_live_seen_forward_only() {
  let Some(pool)=isolated_pool().await else {return};
  clear(&pool,&["ZZS","ZZS2"]).await;
  let now=100*DAY_MS;
  let (a,b,c)=(order(1,now-60_000,None),order(2,now-60_000,None),order(3,now-60_000,Some(now-1_000)));
  upsert(&pool,"ZZS",100.0,&[(a.clone(),now-50_000),(b.clone(),now-5_000),(c.clone(),now-1_000)]).await.unwrap();
  upsert(&pool,"ZZS2",100.0,&[(a.clone(),now-50_000)]).await.unwrap();
  let row=|base,o:&BigOrder,seen|SeenRow{base,venue_id:"binance:usdtPerp:BTCUSDT",side:o.side,bucket:o.bucket,first_seen_ms:o.first_seen_ms,seen_ms:seen};
  let d=order(4,now-1,None);
  let rows=[row("ZZS",&a,now),row("ZZS",&b,now-9_000),row("ZZS",&c,now),row("ZZS",&d,now),row("ZZS2",&a,now-40_000)];
  assert_eq!(refresh_seen(&pool,&rows).await.unwrap(),2,"a 与 ZZS2 的 a；b 更旧不动、c 已结束不动、d 库里没有不插");
  assert_eq!(refresh_seen(&pool,&[]).await.unwrap(),0);
  let seen=|base:&'static str,bucket:i64|{let pool=pool.clone();async move {seen_of(&pool,base,bucket).await.map(|(_,s)|s)}};
  assert_eq!((seen("ZZS",1).await,seen("ZZS",2).await,seen("ZZS",3).await,seen("ZZS",4).await,seen("ZZS2",1).await),
   (Some(now),Some(now-5_000),Some(now-1_000),None,Some(now-40_000)));
  // 写库任务晚落一批旧的：挂着的行 seen_ms 取大的，量照写。
  let mut moved=a.clone();moved.notional=7e6;
  upsert(&pool,"ZZS",100.0,&[(moved,now-30_000)]).await.unwrap();
  assert_eq!(seen("ZZS",1).await,Some(now));
  assert_eq!(sqlx::query_scalar::<_,f64>("SELECT notional FROM orderflow_live WHERE base='ZZS' AND bucket=1").fetch_one(&pool).await.unwrap(),7e6);
  // 结束的照写结束那一刻（可以比挂着时写的 seen_ms 早：失联按最后一次真看到结束）。
  let mut lost=a.clone();lost.end_ms=Some(now-55_000);lost.status=Status::Lost;
  upsert(&pool,"ZZS",100.0,&[(lost,now-55_000)]).await.unwrap();
  assert_eq!(seen_of(&pool,"ZZS",1).await,Some(("orderflow_orders",now-55_000)),"结束的搬进历史表");
  clear(&pool,&["ZZS","ZZS2"]).await;
 }

 /// 挂着的只在活单表、结束的只在历史表；结束是一条语句里搬过去的；结束之后晚到的「挂着」不再进活单表；
 /// 老进程写进历史表的挂着的行读回时搬过来；失联结束从活单表搬进历史表；体积算两张表。
 #[tokio::test]
 async fn live_orders_live_in_their_own_table_until_they_end() {
  let Some(pool)=isolated_pool().await else {return};
  clear(&pool,&["ZZL"]).await;
  let now=100*DAY_MS;
  let count=|table:&'static str|{let pool=pool.clone();async move {
   sqlx::query_scalar::<_,i64>(&format!("SELECT count(*) FROM {table} WHERE base='ZZL'")).fetch_one(&pool).await.unwrap()}};
  let (a,b)=(order(1,now-60_000,None),order(2,now-60_000,None));
  upsert(&pool,"ZZL",100.0,&[(a.clone(),now-1_000),(b.clone(),now-1_000)]).await.unwrap();
  assert_eq!((count("orderflow_live").await,count("orderflow_orders").await),(2,0));
  // a 结束：一批里既有结束的 a 也有仍挂着的 b。
  let mut ended=a.clone();ended.end_ms=Some(now);ended.status=Status::Filled;ended.filled_notional=5e6;
  upsert(&pool,"ZZL",100.0,&[(ended.clone(),now),(b.clone(),now)]).await.unwrap();
  assert_eq!((count("orderflow_live").await,count("orderflow_orders").await),(1,1));
  assert_eq!(seen_of(&pool,"ZZL",1).await,Some(("orderflow_orders",now)));
  assert_eq!(seen_of(&pool,"ZZL",2).await,Some(("orderflow_live",now)));
  // 晚到的一批「a 挂着」：不进活单表、历史表里的结束不动。
  upsert(&pool,"ZZL",100.0,&[(a.clone(),now+500)]).await.unwrap();
  assert_eq!((count("orderflow_live").await,count("orderflow_orders").await),(1,1));
  assert_eq!(range(&pool,"ZZL",now-DAY_MS,now+1).await.unwrap().iter().map(|o|(o.bucket,o.status)).collect::<Vec<_>>(),vec![(1,Status::Filled),(2,Status::Live)]);
  // 老进程留在历史表里的挂着的行（0031 之前的写法）：读回时搬进活单表；活单表里已有同一单的以活单表为准。
  sqlx::query(&format!("INSERT INTO orderflow_orders({COLUMNS}) VALUES('ZZL','binance:usdtPerp:BTCUSDT','币安','usdtPerp','bid',3,300,$1,NULL,'live',6e6,6e6,0,5e6,NULL,100,$1)")).bind(now-30_000).execute(&pool).await.unwrap();
  sqlx::query(&format!("INSERT INTO orderflow_orders({COLUMNS}) VALUES('ZZL','binance:usdtPerp:BTCUSDT','币安','usdtPerp','bid',2,200,$1,NULL,'live',6e6,6e6,0,5e6,NULL,100,$2)")).bind(now-60_000).bind(now-59_000).execute(&pool).await.unwrap();
  let back=super::live(&pool,"ZZL").await.unwrap();
  assert_eq!(back.iter().map(|r|(r.order.bucket,r.seen_ms)).collect::<std::collections::BTreeSet<_>>(),[(2,now),(3,now-30_000)].into_iter().collect(),"3 号搬过来，2 号仍是活单表那份");
  assert_eq!((count("orderflow_live").await,count("orderflow_orders").await),(2,1));
  // 失联结束：从活单表搬进历史表，状态 lost、结束时刻 = 最后一次看到、不记消失量。清理只看登记过的 base。
  start(&pool,"ZZL",now).await.unwrap();
  let (_,closed)=purge(&pool,now+ORPHAN_MS+10,&["ZZL".to_string()]).await.unwrap();
  assert_eq!(closed,2);
  assert_eq!((count("orderflow_live").await,count("orderflow_orders").await),(0,3));
  let lost=range(&pool,"ZZL",now-DAY_MS,now+ORPHAN_MS).await.unwrap();
  assert_eq!(lost.iter().filter(|o|o.status==Status::Lost).map(|o|(o.bucket,o.end_ms,o.vanished_notional)).collect::<Vec<_>>(),vec![(2,Some(now),None),(3,Some(now-30_000),None)]);
  assert!(size(&pool).await.unwrap()>0);
  clear(&pool,&["ZZL"]).await;
 }

 #[tokio::test]
 async fn writes_reads_and_rolls() {
  let Some(pool)=isolated_pool().await else {return};
  clear(&pool,&["ZZT"]).await;
  let now=100*DAY_MS;
  // 挂着的、窗口里结束的、跨过窗口右沿才结束的、4 天前结束的（超过 3 天保留期）。
  let live=order(1,now-3_600_000,None);
  let inside=order(2,now-2*DAY_MS,Some(now-3_600_000));
  let across=order(3,now-7_200_000,Some(now+1));
  let old=order(4,now-5*DAY_MS,Some(now-4*DAY_MS));
  upsert(&pool,"ZZT",100.0,&[(live.clone(),now-1000),(inside.clone(),now-3_600_000),(across.clone(),now+1),(old.clone(),now-4*DAY_MS)]).await.unwrap();
  let got=range(&pool,"ZZT",now-DAY_MS,now).await.unwrap();
  assert_eq!(got.iter().map(|o|o.bucket).collect::<Vec<_>>(),vec![2,3,1],"按出现时刻升序，4 天前结束的不在最近一天里");
  assert_eq!(range(&pool,"ZZT",now-DAY_MS,now-5_000_000).await.unwrap().iter().map(|o|o.bucket).collect::<Vec<_>>(),vec![2,3],"右沿之后才出现的（挂着的 1 号）不回，跨过右沿的 3 号要回");
  assert_eq!(range_capped(&pool,"ZZT",now-DAY_MS,now,0,2).await.unwrap().iter().map(|o|o.bucket).collect::<Vec<_>>(),vec![3,1],"超了上限留最新的，仍按升序");
  // 结束写进去之后，晚到的一批「挂着」翻不回去。
  let mut ended=live.clone();ended.end_ms=Some(now);ended.status=Status::Filled;
  upsert(&pool,"ZZT",100.0,&[(ended.clone(),now)]).await.unwrap();
  upsert(&pool,"ZZT",100.0,&[(live.clone(),now+500)]).await.unwrap();
  let back=range(&pool,"ZZT",now-DAY_MS,now).await.unwrap();
  assert_eq!(back.iter().find(|o|o.bucket==1).unwrap().status,Status::Filled);
  assert!(super::live(&pool,"ZZT").await.unwrap().is_empty());
  // 读回挂着的单带步长与最后一次看到的时刻。
  let again=order(5,now,None);
  upsert(&pool,"ZZT",100.0,&[(again.clone(),now+2)]).await.unwrap();
  assert_eq!(super::live(&pool,"ZZT").await.unwrap(),vec![Restored{order:again,step:100.0,seen_ms:now+2}]);
  // since 只在第一次写；最近 24 小时要过的才接着跟。
  assert_eq!(touch(&pool,"ZZT",now).await.unwrap(),(now,None));
  assert_eq!(touch(&pool,"ZZT",now+9).await.unwrap(),(now,None));
  assert!(recent_bases(&pool,now+10).await.unwrap().contains(&("ZZT".to_string(),now+9)),"带回最后一次要的时刻");
  // 起跟、活着：since 不动；断了十分钟以上再起跟：since 重置到那一刻。
  start(&pool,"ZZT",now+10).await.unwrap();
  alive(&pool,"ZZT",now+60_000).await.unwrap();
  start(&pool,"ZZT",now+120_000).await.unwrap();
  assert_eq!(touch(&pool,"ZZT",now+120_001).await.unwrap(),(now,Some(now+120_000)),"重启那一两分钟不算断");
  start(&pool,"ZZT",now+120_000+GAP_MS+1).await.unwrap();
  assert_eq!(touch(&pool,"ZZT",now+120_000+GAP_MS+2).await.unwrap().0,now+120_000+GAP_MS+1);
  // 正在跟的 base：跟踪器手里的行两分钟没刷新不动，满 ORPHAN_MS 才收。
  let (deleted,_)=purge(&pool,now+STALE_MS+10,&["ZZT".to_string()]).await.unwrap();
  assert!(deleted>=1);
  assert_eq!(super::live(&pool,"ZZT").await.unwrap().len(),1,"正在跟：两分钟没刷新不收");
  let (_,closed)=purge(&pool,now+ORPHAN_MS+10,&["ZZT".to_string()]).await.unwrap();
  assert!(closed>=1,"结束没写进库的行，正在跟也要收");
  assert!(super::live(&pool,"ZZT").await.unwrap().is_empty());
  // 滚动清理：3 天以前结束的删掉；没在跟的 base 上缺席的挂单失联结束。
  let (_,closed)=purge(&pool,now+STALE_MS+10,&[]).await.unwrap();
  assert_eq!(closed,0,"已经收过了");
  // 窗口拉到 6 天前：4 号要是没删会落在这里面。
  let rest=range(&pool,"ZZT",now-6*DAY_MS,now+STALE_MS).await.unwrap();
  assert!(rest.iter().all(|o|o.bucket!=4));
  assert_eq!(rest.iter().find(|o|o.bucket==5).map(|o|(o.status,o.end_ms)),Some((Status::Lost,Some(now+2))));
  clear(&pool,&["ZZT"]).await;
  sqlx::query("DELETE FROM orderflow_bases WHERE base='ZZT'").execute(&pool).await.unwrap();
 }
}
