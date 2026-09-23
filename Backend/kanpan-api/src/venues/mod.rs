//! 每家交易所在服务端的那一截。
//!
//! 客户端的「行情提供者」在网关线路上要的东西，按交易所一族一个文件放在这里：
//!
//! - `okx`：币安永续在网关线路上的替身数据——持仓量（`/v1/market/open-interest?source=okx`）、
//!   整张资金费率表（`/v1/market/funding?source=okx`）、带 USDT 成交额的 24h 行情
//!   （`/v1/market/ticker?source=okx`）与持仓量历史（`/v1/market/open-interest/history?source=okx`）。
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
  .route("/v1/market/funding",get(funding))
  .route("/v1/market/ticker",get(ticker))
  .route("/v1/market/open-interest/history",get(oi_history))
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

/// 整张资金费率表。只有「替身」需要它：直连线路上手机自己问币安 `premiumIndex`，
/// 网关线路上币安 `fapi` 在美国回 451，替身 OKX 的推送里又没有费率，只能在这里整表给。
async fn funding(Query(query):Query<Vec<(String,String)>>)->Response {
 match source(&query) {
  Some("okx")=>match okx::funding().await {
   Ok(table)=>crate::envelope(okx::funding_payload(&table)).into_response(),
   Err(e)=>e.into_response(),
  },
  _=>unsupported(),
 }
}

fn param<'a>(query:&'a [(String,String)],key:&str)->Option<&'a str> {
 query.iter().find(|(k,_)|k==key).map(|(_,v)|v.as_str())
}
/// 代号只收字母、数字和连字符：它会被拼进上游地址。
fn symbol_param(query:&[(String,String)])->Option<&str> {
 param(query,"symbol").filter(|s|!s.is_empty()&&s.len()<=40&&s.chars().all(|c|c.is_ascii_alphanumeric()||c=='-'))
}
fn bad(code:&'static str)->Response {crate::error::ApiError::bad(code).into_response()}

/// 一只永续的 24h 行情，币安 `/fapi/v1/ticker/24hr` 的形状。网关 Python 那一截的
/// `/market/v1/ticker?source=okx` 给不出计价币成交额（OKX 只给币量），这里用 OKX
/// 自己的 K 线把币量换算成 USDT，顶栏「额」在网关线路上才有数。
async fn ticker(Query(query):Query<Vec<(String,String)>>)->Response {
 match source(&query) {
  Some("okx")=>{
   let Some(symbol)=symbol_param(&query) else {return bad("invalid_symbol")};
   match okx::ticker(symbol).await {
    Ok(body)=>crate::envelope(body).into_response(),
    Err(e)=>e.into_response(),
   }
  },
  _=>unsupported(),
 }
}

/// 持仓量历史，参数照币安 `openInterestHist`（`period` / `limit` ≤ 500 / `endTime` 含端点），
/// 答复 `{"source":"okx","rows":[[毫秒, 币的个数, 美元名义值|null], …]}`，时间升序。
async fn oi_history(Query(query):Query<Vec<(String,String)>>)->Response {
 match source(&query) {
  Some("okx")=>{
   let Some(symbol)=symbol_param(&query) else {return bad("invalid_symbol")};
   let Some(period)=param(&query,"period").filter(|p|okx::okx_period(p).is_some()) else {return bad("unsupported_period")};
   let limit=match param(&query,"limit") {None=>okx::OI_HISTORY_MAX,Some(v)=>match v.parse::<usize>() {Ok(n) if n>0=>n,_=>return bad("invalid_limit")}};
   let end=match param(&query,"endTime") {None=>None,Some(v)=>match v.parse::<i64>() {Ok(t) if t>0=>Some(t),_=>return bad("invalid_end_time")}};
   let now=chrono::Utc::now().timestamp_millis();
   match okx::oi_history(symbol,period,limit,end,now).await {
    Ok(rows)=>crate::envelope(okx::oi_history_payload(&symbol.to_ascii_uppercase(),period,&rows)).into_response(),
    Err(e)=>e.into_response(),
   }
  },
  _=>unsupported(),
 }
}

async fn stream(ws:WebSocketUpgrade,Query(query):Query<Vec<(String,String)>>)->Response {
 match source(&query) {
  Some(coinbase::SOURCE)=>ws.on_upgrade(coinbase::serve_client),
  _=>unsupported(),
 }
}
