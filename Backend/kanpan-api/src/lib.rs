pub mod auth;
pub mod crypto;
pub mod error;
pub mod sync;
pub mod sync_validation;
pub mod mail;
pub mod review;
pub mod review_worker;
pub mod search;
pub mod market_meta;
pub mod oi_archive;
pub mod maintenance;
use axum::{Router,Json,routing::get,extract::DefaultBodyLimit};
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
 pub mail_enabled: bool,
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
pub fn router(s: AppState) -> Router {
 Router::new().route("/health",get(||async{envelope(json!({"ok":true}))}))
  .merge(auth::routes()).merge(sync::routes()).merge(review::routes()).merge(search::routes()).merge(market_meta::routes()).merge(oi_archive::routes())
  .layer(DefaultBodyLimit::max(512*1024))
  .with_state(s)
}

pub mod review_domain;
pub mod review_market;
