pub mod auth;
pub mod crypto;
pub mod error;
pub mod sync;
pub mod sync_validation;
pub mod instruments;
pub mod review;
pub mod review_worker;
pub mod search;
pub mod binance_gate;
pub mod market_meta;
pub mod market_depth;
pub mod venues;
pub mod sector_history;
pub mod oi_archive;
pub mod maintenance;
pub mod alerts;
pub mod apns;
pub mod live_activity;
pub mod share;
pub mod watch_move;
pub mod export;
pub mod legal;
pub mod supervise;
use axum::{Router,Json,routing::get,extract::DefaultBodyLimit};
use std::time::Duration;
use serde_json::{Value,json};
use sqlx::{PgPool,Postgres,Transaction};
use std::sync::Arc;
use uuid::Uuid;
use error::Result;

#[derive(Clone)]
pub struct AppState {
 pub pool: PgPool,
 pub secrets: Arc<crypto::Secrets>,
 pub dummy_hash: Arc<String>,
}
impl AppState {
 pub async fn personal(&self, owner: Uuid) -> Result<Transaction<'_,Postgres>> {
  let mut tx=self.pool.begin().await?;
  let active:Option<Uuid>=sqlx::query_scalar("SELECT id FROM account_users WHERE id=$1 AND disabled_at IS NULL FOR SHARE").bind(owner).fetch_optional(&mut *tx).await?;
  if active.is_none() {return Err(error::ApiError::unauthorized())}
  sqlx::query("SELECT set_config('kanpan.user_id',$1,true)").bind(owner.to_string()).execute(&mut *tx).await?;
  Ok(tx)
 }
}
pub fn envelope(value: Value) -> Json<Value> { Json(json!({"data":value})) }
/// 建连接池。`deadlines` 为真时给每条新连接挂上数据库自己的那层死线。
///
/// 三层截止里的最后一层：请求体有 512 KiB 上限、请求有 30 秒超时，但那两层只管到
/// Rust 这边——超时之后把 future 丢掉，Postgres 那条语句仍在服务器上跑。池子只有八条
/// 连接，一条锁等、一条全表扫就能把三个人一起卡住，所以在连接上直接挂死线：
/// 语句 20 秒、锁等 5 秒、事务里发呆 30 秒。都比上面那层 30 秒短，报错才落在业务这边。
///
/// 只有 `serve` 该挂。worker 与 migrate 都是独立进程、独立连接池，占不到 API 那八条连接：
/// worker 的板块历史、OI 归档、日线收盘、复盘计算本来就是长查询加批量写，migrate 建索引
/// 改表也会跑很久、要排队等锁——给它们挂二十秒只会让任务和升级半路断在中间。
///
/// 三条 `SET` 必须**一条一条**发。塞进同一个 `sqlx::query` 里会被 Postgres 顶回来
/// （扩展协议不许一条语句里放多个命令：`cannot insert multiple commands into a prepared
/// statement`），而 `after_connect` 一报错就是**每一条连接都建不起来**——服务起得来，
/// 却一个请求都接不了。`sqlx::raw_sql` 能一次发三条，但它在 `after_connect` 这个
/// 高阶闭包里过不了 `Executor` 的生命周期，所以这里就按三条发。
pub fn pool_options(deadlines: bool) -> sqlx::postgres::PgPoolOptions {
 sqlx::postgres::PgPoolOptions::new().max_connections(8).after_connect(move|conn,_|Box::pin(async move {
  if deadlines {
   for sql in ["SET statement_timeout='20s'","SET lock_timeout='5s'","SET idle_in_transaction_session_timeout='30s'"] {
    sqlx::query(sql).execute(&mut *conn).await?;
   }
  }
  // 这两条对 serve 和 worker 都要挂：找相似图形的近邻查询跑在 worker 里。
  //
  // pgvector 0.8 的 hnsw.iterative_scan 默认是 off：HNSW 只按 ef_search 取回固定的一批
  // 候选，**然后**才拿 WHERE 里的 market/timeframe/source 去过滤。过滤掉的不会补，于是
  // 要一百行只回六行——不是"没有更像的了"，是被截断了。strict_order 让它在不够的时候
  // 继续往下迭代，而且仍旧严格按距离递增吐行（relaxed_order 快一点，但吐出来的顺序不是
  // 严格递增的，我们外层还要按 distance 定序，不能要）。
  // max_scan_tuples 是配套的刹车：过滤条件筛得太狠时，迭代会一直往下走，这里封顶。
  for sql in ["SET hnsw.iterative_scan='strict_order'","SET hnsw.max_scan_tuples='20000'"] {
   sqlx::query(sql).execute(&mut *conn).await?;
  }
  Ok(())
 }))
}
/// The market fallback host answers open interest and nothing else. It keeps no
/// accounts, so it gets no database — which is why these routes are split out
/// rather than served by `router` with a pool nobody would query.
pub fn metrics_router() -> Router {
 Router::new().route("/health",get(||async{envelope(json!({"ok":true}))}))
  .merge(oi_archive::routes()).merge(venues::routes())
}
pub fn router(s: AppState) -> Router {
 Router::new().route("/health",get(||async{envelope(json!({"ok":true}))}))
  .merge(auth::routes()).merge(export::routes()).merge(legal::routes()).merge(sync::routes()).merge(alerts::routes()).merge(live_activity::routes()).merge(share::routes()).merge(review::routes()).merge(search::routes()).merge(market_meta::routes()).merge(market_depth::routes()).merge(sector_history::routes()).merge(oi_archive::routes()).merge(venues::routes())
  .layer(DefaultBodyLimit::max(512*1024))
  // 一个请求最多占住一条连接三十秒。池子只有八条连接，一个卡死的查询就能把
  // 剩下的人一起挡在门外；超时之后连接回池，客户端本来也早就重试了。
  .layer(tower_http::timeout::TimeoutLayer::with_status_code(axum::http::StatusCode::REQUEST_TIMEOUT,Duration::from_secs(30)))
  .with_state(s)
}

pub mod review_domain;
pub mod review_market;

#[cfg(test)]
mod migrations {
 /// 0001–0010 已经在线上跑过，sqlx 校验校验和，一个字都不能改；这条只管 0011 起的
 /// 新迁移。规矩写在 `migrations/README.md`：建索引一律 CONCURRENTLY（因此整个文件不能
 /// 在事务里，首行必须是 `-- no-transaction`），加列一律可空或者带常量默认值。
 #[test] fn migrations_after_0010_are_lock_free() {
  let dir=std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("migrations");
  let mut names:Vec<_>=std::fs::read_dir(&dir).expect("migrations directory").map(|e|e.expect("directory entry").file_name().to_string_lossy().into_owned()).collect();
  names.sort();
  for name in names {
   let Some(number)=name.split('_').next().and_then(|v|v.parse::<u32>().ok()) else {continue};
   if number<=10 || !name.ends_with(".sql") {continue}
   let sql=std::fs::read_to_string(dir.join(&name)).expect("readable migration");
   // 注释里写着「CREATE INDEX」不算语句。
   let body=sql.lines().filter(|l|!l.trim_start().starts_with("--")).collect::<Vec<_>>().join("\n").to_lowercase();
   // 同一事务刚创建的表上建索引不会锁旧表；已有表仍必须 CONCURRENTLY。
   let fresh_tables:Vec<_>=body.split("create table ").skip(1).filter_map(|v|v.split_whitespace().next()).collect();
   let body=body.split(';').filter(|statement| {
    let statement=statement.trim();
    !(statement.starts_with("create index ") && !statement.starts_with("create index concurrently ")
      && fresh_tables.iter().any(|table|statement.contains(&format!(" on {table}("))))
   }).collect::<Vec<_>>().join(";");
   assert_eq!(body.matches("create index").count(),body.matches("create index concurrently").count(),"{name}：建索引要 CONCURRENTLY，否则升级时整张表的写都在排队");
   // 删索引同样要 CONCURRENTLY：普通 DROP INDEX 拿的是表上的 ACCESS EXCLUSIVE，
   // 一边排在长查询后面，一边把后面所有的读写都堵在自己后面。
   assert_eq!(body.matches("drop index").count(),body.matches("drop index concurrently").count(),"{name}：删索引也要 CONCURRENTLY，普通 DROP INDEX 要拿表上的 ACCESS EXCLUSIVE");
   if body.contains("create index")||body.contains("drop index") {
    assert_eq!(sql.lines().next().map(str::trim),Some("-- no-transaction"),"{name}：CONCURRENTLY 不能在事务里跑，首行必须是 -- no-transaction");
   }
   // 不在事务里的那种迁移，一个文件只许放一条语句。sqlx 仍旧是把整份文件当**一条**
   // 简单查询发过去，而 Postgres 对「一条简单查询里有多个命令」会自己包一个隐式事务
   // ——于是 CONCURRENTLY 照样会报 cannot run inside a transaction block。
   if sql.starts_with("-- no-transaction") {
    assert_eq!(body.matches(';').count(),1,"{name}：不在事务里的迁移一个文件只能放一条语句（多条会被 Postgres 包进隐式事务）");
   }
   for clause in body.split("add column").skip(1) {
    let clause=clause.split(';').next().unwrap_or_default();
    assert!(!clause.contains("not null")||clause.contains("default"),"{name}：加 NOT NULL 列要带常量默认值，否则旧行会把迁移顶回来");
   }
  }
 }
}
