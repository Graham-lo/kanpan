//! 每家交易所在服务端的那一截。
//!
//! 客户端的「行情提供者」在网关线路上要的东西，按交易所一族一个文件放在这里：
//!
//! - `okx`：只剩币安永续在网关线路上的持仓量替身（`/v1/market/open-interest?source=okx`）。
//! - `coinbase`：REST 原样透传（`/v1/market/raw/…?source=coinbase`）、推送 hub
//!   （`/v1/market/stream?source=coinbase`）、复盘 worker 用的 K 线与逐笔。
//!
//! 接第三家：新建 `venues/<id>.rs`，在下面两个分发里各加一行，别处不动
//! （见 `docs/多交易所-接入指南.md`）。挂在 `/v1/market/` 下而不是 `/market/`：
//! 后者在 Caddy 上整段归 Python 网关。
use axum::{Router,extract::{Path,Query,ws::WebSocketUpgrade},response::{IntoResponse,Response},routing::get};
use axum::http::StatusCode;
use serde_json::json;

pub mod coinbase;
pub mod okx;

/// 两族路由都不读数据库，所以 API 主机与只答持仓量的备用主机挂的是同一份。
pub fn routes<S:Clone+Send+Sync+'static>()->Router<S> {
 Router::new()
  .route("/v1/market/raw/{*path}",get(raw))
  .route("/v1/market/stream",get(stream))
}

fn source(query:&[(String,String)])->Option<&str> {
 query.iter().find(|(k,_)|k=="source").map(|(_,v)|v.as_str())
}
fn unsupported()->Response {
 (StatusCode::BAD_REQUEST,axum::Json(json!({"error":"unsupported_source"}))).into_response()
}

async fn raw(Path(path):Path<String>,Query(query):Query<Vec<(String,String)>>)->Response {
 match source(&query) {
  Some(coinbase::SOURCE)=>coinbase::raw(&path,&query).await,
  _=>unsupported(),
 }
}

async fn stream(ws:WebSocketUpgrade,Query(query):Query<Vec<(String,String)>>)->Response {
 match source(&query) {
  Some(coinbase::SOURCE)=>ws.on_upgrade(coinbase::serve_client),
  _=>unsupported(),
 }
}
