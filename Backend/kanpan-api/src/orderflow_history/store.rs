//! 大单的库：`orderflow_orders`（一单一行）与 `orderflow_bases`（跟踪过哪些 base）。迁移见 0024。
//!
//! * 挂着的单每 15 秒整批 upsert 一次，结束的单一结束就写。upsert 只改还没结束的行
//!   （`WHERE orderflow_orders.end_ms IS NULL`）：晚到的一批「挂着」不会把刚写进去的结束翻回去。
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

/// 写一批（挂着的、刚结束的都走这里）。`seen` 为挂着的单最后一次看到的时刻，结束的单填结束时刻。
pub async fn upsert(pool:&PgPool,base:&str,step:f64,rows:&[(BigOrder,i64)])->sqlx::Result<()> {
 for chunk in rows.chunks(500) {
  let mut q=QueryBuilder::<Postgres>::new(format!("INSERT INTO orderflow_orders({COLUMNS}) "));
  q.push_values(chunk,|mut b,(o,seen)| {
   b.push_bind(base).push_bind(&o.venue_id).push_bind(&o.exchange).push_bind(&o.product).push_bind(o.side.wire()).push_bind(o.bucket)
    .push_bind(o.price).push_bind(o.first_seen_ms).push_bind(o.end_ms).push_bind(o.status.wire()).push_bind(o.initial_notional)
    .push_bind(o.notional).push_bind(o.filled_notional).push_bind(o.threshold).push_bind(o.vanished_notional).push_bind(step).push_bind(*seen);
  });
  q.push(" ON CONFLICT(base,venue_id,side,bucket,first_seen_ms) DO UPDATE SET price=EXCLUDED.price,end_ms=EXCLUDED.end_ms,status=EXCLUDED.status,\
   notional=EXCLUDED.notional,filled_notional=EXCLUDED.filled_notional,threshold=EXCLUDED.threshold,vanished_notional=EXCLUDED.vanished_notional,\
   seen_ms=EXCLUDED.seen_ms WHERE orderflow_orders.end_ms IS NULL");
  q.build().execute(pool).await?;
 }
 Ok(())
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

/// 一只 base 还挂着的单（进程重启读回用）。
pub async fn live(pool:&PgPool,base:&str)->sqlx::Result<Vec<Restored>> {
 let rows=sqlx::query(&format!("SELECT {COLUMNS} FROM orderflow_orders WHERE base=$1 AND end_ms IS NULL")).bind(base).fetch_all(pool).await?;
 Ok(rows.iter().filter_map(|r|Some(Restored{order:order(r)?,step:r.try_get("step").ok()?,seen_ms:r.try_get("seen_ms").ok()?})).collect())
}

/// `[from, to]` 里出现过的单：出现 ≤ to，且还挂着或结束 ≥ from。按出现时刻升序。
///
/// 拆成三段各走各的索引：还挂着的；在窗口里结束的（结束时刻的区间扫）；跨过窗口右沿才结束的。
/// 写成一句 `end_ms IS NULL OR end_ms >= from` 的话，拉最近一天也要把整个月结束的行都扫一遍。
pub async fn range(pool:&PgPool,base:&str,from:i64,to:i64)->sqlx::Result<Vec<BigOrder>> {range_capped(pool,base,from,to,MAX_ROWS).await}

/// 超过 `cap` 条时留最新的：先按出现时刻倒序取 `cap` 条、再翻回升序。原来升序取前 `cap` 条，截掉的恰好是
/// 最新的那一段——图的右沿（此刻）空着，手机的增量游标也从截断处往后接，永远补不上。
async fn range_capped(pool:&PgPool,base:&str,from:i64,to:i64,cap:i64)->sqlx::Result<Vec<BigOrder>> {
 let cols=COLUMNS;
 let sql=format!("SELECT * FROM (\
  SELECT {cols} FROM orderflow_orders WHERE base=$1 AND end_ms IS NULL AND first_seen_ms<=$3 \
  UNION ALL SELECT {cols} FROM orderflow_orders WHERE base=$1 AND end_ms>=$2 AND end_ms<=$3 \
  UNION ALL SELECT {cols} FROM orderflow_orders WHERE base=$1 AND end_ms>$3 AND first_seen_ms<=$3\
  ) t ORDER BY first_seen_ms DESC,venue_id DESC,side DESC,bucket DESC LIMIT $4");
 let rows=sqlx::query(&sql).bind(base).bind(from).bind(to).bind(cap).fetch_all(pool).await?;
 let mut orders:Vec<BigOrder>=rows.iter().filter_map(order).collect();
 orders.reverse();
 Ok(orders)
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

/// 进程起来时接着跟哪些：最近 24 小时有人要过的，按最近要的先后。
pub async fn recent_bases(pool:&PgPool,now:i64)->sqlx::Result<Vec<String>> {
 sqlx::query_scalar("SELECT base FROM orderflow_bases WHERE requested_ms>=$1 ORDER BY requested_ms DESC").bind(now-DAY_MS).fetch_all(pool).await
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

/// 每小时一次：3 天以前结束的删掉；挂着却很久没看到的按最后一次看到时失联结束（截止见 `stale_cutoff`）；
/// 估算体积超过闸门就从最旧的删起。返回（删了几行，失联结束几行）。
///
/// 原来只收没在跟的 base：正在跟的 base 上结束那笔没写进库的行，要等这只 base 停掉或进程重启才会结束，
/// 主币永远不停，图上那条线就一直画到「现在」。
pub async fn purge(pool:&PgPool,now:i64,tracked:&[String])->sqlx::Result<(u64,u64)> {
 let bases=bases(pool).await?;
 let mut deleted=0;
 for base in &bases {deleted+=delete_ended_before(pool,base,now-RETENTION_MS).await?;}
 let mut closed=0;
 for base in &bases {
  closed+=sqlx::query("UPDATE orderflow_orders SET status='lost',end_ms=GREATEST(first_seen_ms,seen_ms),vanished_notional=NULL \
   WHERE base=$1 AND end_ms IS NULL AND seen_ms<$2").bind(base).bind(stale_cutoff(tracked.contains(base),now)).execute(pool).await?.rows_affected();
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

/// 表此刻的体积（容量实测用）。
pub async fn size(pool:&PgPool)->sqlx::Result<i64> {sqlx::query_scalar("SELECT pg_total_relation_size('orderflow_orders')").fetch_one(pool).await}

#[cfg(test)]
mod tests {
 use super::*;

 async fn isolated_pool()->Option<PgPool> {
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

 #[tokio::test]
 async fn writes_reads_and_rolls() {
  let Some(pool)=isolated_pool().await else {return};
  sqlx::query("DELETE FROM orderflow_orders WHERE base='ZZT'").execute(&pool).await.unwrap();
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
  assert_eq!(range_capped(&pool,"ZZT",now-DAY_MS,now,2).await.unwrap().iter().map(|o|o.bucket).collect::<Vec<_>>(),vec![3,1],"超了上限留最新的，仍按升序");
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
  assert!(recent_bases(&pool,now+10).await.unwrap().contains(&"ZZT".to_string()));
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
  sqlx::query("DELETE FROM orderflow_orders WHERE base='ZZT'").execute(&pool).await.unwrap();
  sqlx::query("DELETE FROM orderflow_bases WHERE base='ZZT'").execute(&pool).await.unwrap();
 }
}
