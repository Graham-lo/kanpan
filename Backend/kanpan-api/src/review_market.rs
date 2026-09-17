//! Venue-preserving temporary OHLC fetches through our bounded market gateway.
use crate::{error::{ApiError,Result},review::core};
use scorebook_core::{api::native_review::ChartRange,domain::criteria::Bar,market::MarketDataProvider};
use chrono::{DateTime,Utc};
use serde_json::{Value,json};
use std::sync::OnceLock;

/// The upstream refused this node's region (HTTP 451) or the request itself.
/// Either way it will refuse again in a minute, so it must not look transient.
pub const BLOCKED:&str="market_region_blocked";
fn blocked()->ApiError {ApiError(axum::http::StatusCode::UNAVAILABLE_FOR_LEGAL_REASONS,BLOCKED)}

pub async fn klines(provider:&dyn MarketDataProvider,r:&ChartRange,start:DateTime<Utc>,end:DateTime<Utc>)->Result<Value> {
 // A provider error that already says "do not retry" is, on these VPS, almost
 // always Binance answering 451. Flattening it into market_unavailable made the
 // worker re-ask the same refusal every 60 seconds for the life of the record.
 if r.venue=="binance" {return provider.klines(&r.market,&r.symbol,&r.interval,start,end).await.map_err(|e|if e.retry.retryable(){ApiError(axum::http::StatusCode::SERVICE_UNAVAILABLE,"market_unavailable")}else{blocked()})}
 if r.venue!="okx" || r.market!="usd_m" {return Err(ApiError::bad("invalid_chart_range"))}
 static HTTP:OnceLock<reqwest::Client>=OnceLock::new();
 let client=HTTP.get_or_init(||reqwest::Client::builder().timeout(std::time::Duration::from_secs(35)).build().expect("HTTP client"));
 let mut cursor=start.timestamp_millis();let mut bars=Vec::<Bar>::new();let mut complete=true;
 for _ in 0..8 {
  let response=client.get("http://127.0.0.1:8792/market/v1/klines").query(&[("source","okx".to_owned()),("symbol",r.symbol.clone()),("interval",r.interval.clone()),("startTime",cursor.to_string()),("endTime",(end.timestamp_millis()-1).to_string()),("limit","500".into())]).send().await.map_err(|_|ApiError::bad("market_unavailable"))?;
  // The gateway forwards a geographic block as 451 rather than a generic 503.
  if response.status()==reqwest::StatusCode::UNAVAILABLE_FOR_LEGAL_REASONS {return Err(blocked())}
  let response=response.error_for_status().map_err(|_|ApiError::bad("market_unavailable"))?;
  let v:Value=response.json().await.map_err(|_|ApiError::bad("invalid_market_response"))?;
  if v["source"]!="okx" || v["symbol"]!=r.symbol || v["interval"]!=r.interval {return Err(ApiError::bad("market_source_mismatch"))}
  let rows=v["bars"].as_array().ok_or_else(||ApiError::bad("invalid_market_response"))?;
  if rows.is_empty(){break}
  let previous=cursor;
  for row in rows {
   let at=row[0].as_i64().ok_or_else(||ApiError::bad("invalid_market_response"))?;
   let to=row[6].as_i64().ok_or_else(||ApiError::bad("invalid_market_response"))?+1;
   if at<cursor || to<=at {return Err(ApiError::bad("invalid_market_response"))}
   if at!=cursor {complete=false} cursor=to;
   if to>end.timestamp_millis() || to>Utc::now().timestamp_millis(){continue}
   let value=|i:usize|row[i].as_str().map(str::to_owned).ok_or_else(||ApiError::bad("invalid_market_response"));
   bars.push(Bar{start:core(crate::review_domain::time(at))?,end:core(crate::review_domain::time(to))?,open:value(1)?,high:value(2)?,low:value(3)?,close:value(4)?,volume:Some(value(5)?)});
  }
  if cursor<=previous {return Err(ApiError::bad("market_pagination_stalled"))}
  if cursor>=end.timestamp_millis() || rows.len()<500 {break}
 }
 complete=complete && bars.first().is_some_and(|b|b.start==start) && bars.last().is_some_and(|b|b.end==end);
 Ok(json!({"provider":"okx","bars":bars,"coverage_complete":complete}))
}
