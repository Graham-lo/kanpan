pub mod auth;
pub mod crypto;
pub mod error;
pub mod sync;
pub mod sync_validation;
pub mod review;
pub mod review_worker;
pub mod search;
pub mod market_meta;
pub mod sector_history;
pub mod oi_archive;
pub mod maintenance;
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
  Ok(())
 }))
}
/// The market fallback host answers open interest and nothing else. It keeps no
/// accounts, so it gets no database — which is why these routes are split out
/// rather than served by `router` with a pool nobody would query.
pub fn metrics_router() -> Router {
 Router::new().route("/health",get(||async{envelope(json!({"ok":true}))}))
  .merge(oi_archive::routes())
}
pub fn router(s: AppState) -> Router {
 Router::new().route("/health",get(||async{envelope(json!({"ok":true}))}))
  .merge(auth::routes()).merge(sync::routes()).merge(review::routes()).merge(search::routes()).merge(market_meta::routes()).merge(sector_history::routes()).merge(oi_archive::routes())
  .layer(DefaultBodyLimit::max(512*1024))
  // 一个请求最多占住一条连接三十秒。池子只有八条连接，一个卡死的查询就能把
  // 剩下的人一起挡在门外；超时之后连接回池，客户端本来也早就重试了。
  .layer(tower_http::timeout::TimeoutLayer::with_status_code(axum::http::StatusCode::REQUEST_TIMEOUT,Duration::from_secs(30)))
  .with_state(s)
}

pub mod review_domain;
pub mod review_market;
