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

/// 这一次拿不到 K 线的内部原因。对外两者都还是 `market_unavailable`——响应形状
/// 不动——但它们要分开记：限流是「我们该退一步」，不可用是「该去看网关」。
#[derive(Clone,Copy,Debug,PartialEq)]
enum Refusal {RateLimited,Unavailable}
fn refused(kind:Refusal)->ApiError {
 match kind {
  Refusal::RateLimited=>tracing::warn!("Review chart: the market gateway is rate limited; not calling it again until the cooldown lapses"),
  Refusal::Unavailable=>tracing::warn!("Review chart: the market gateway did not answer"),
 }
 ApiError::bad("market_unavailable")
}
/// 网关被它的上游限流时回 429 + `Retry-After` + `{"error":"upstream_rate_limited",
/// "retryAfter":N}`；它自己排不下时回同样形状的 `busy`。原来这里把所有非 2xx
/// （除 451）压成一句 market_unavailable，`retryAfter` 被丢掉，于是复盘 worker
/// 每 60 秒照原样再撞一次，网关那边的限流窗口永远走不完。
///
/// 只有一个网关主机（127.0.0.1:8792），所以冷却也只有一格。
const GATEWAY:&str="http://127.0.0.1:8792/market/v1/klines";
/// 网关没说等多久时等这些。
const UNTOLD_COOLDOWN:std::time::Duration=std::time::Duration::from_secs(10);
/// 网关说得再离谱也不超过这个：它的限流窗口是分钟级的。
const LONGEST_COOLDOWN:std::time::Duration=std::time::Duration::from_secs(300);
fn gateway_cooldown()->&'static std::sync::Mutex<Option<tokio::time::Instant>> {
 static C:OnceLock<std::sync::Mutex<Option<tokio::time::Instant>>>=OnceLock::new();
 C.get_or_init(||std::sync::Mutex::new(None))
}
/// 冷却还剩多久；`None` 表示现在可以出站。
fn cooling()->Option<std::time::Duration> {
 let mut slot=gateway_cooldown().lock().unwrap_or_else(|e|e.into_inner());
 let until=(*slot)?;
 let now=tokio::time::Instant::now();
 if until<=now {*slot=None;return None}
 Some(until-now)
}
/// 记下网关让我们等多久。只延长不缩短。
fn cool_down(span:std::time::Duration) {
 let until=tokio::time::Instant::now()+span.clamp(std::time::Duration::from_secs(1),LONGEST_COOLDOWN);
 let mut slot=gateway_cooldown().lock().unwrap_or_else(|e|e.into_inner());
 if slot.is_none_or(|current|current<until) {*slot=Some(until);}
}
/// 网关这一次说等多久：先看 `Retry-After`，再看 body 里的 `retryAfter`，都没有
/// 就按默认值。`error` 是 `upstream_rate_limited` 还是 `busy` 不改变结论——429
/// 就是 429——但它写进日志，好分清是上游限流还是网关自己排满了。
fn told_to_wait(header:Option<&str>,body:&Value)->std::time::Duration {
 let from_header=header.and_then(|v|v.trim().parse::<u64>().ok()).filter(|s|*s>0);
 let from_body=body["retryAfter"].as_f64().filter(|s|*s>0.0).map(|s|s.ceil() as u64)
  .or_else(||body["retryAfter"].as_str().and_then(|v|v.trim().parse::<u64>().ok()));
 if let Some(why)=body["error"].as_str() {tracing::warn!("Market gateway refused a review chart: {why}")}
 from_header.or(from_body).map(std::time::Duration::from_secs).unwrap_or(UNTOLD_COOLDOWN)
}

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
  // 冷却里就不出站：网关刚说过它在限流，再问一次只是让它的窗口更难走完。
  if cooling().is_some() {return Err(refused(Refusal::RateLimited))}
  let response=client.get(GATEWAY).query(&[("source","okx".to_owned()),("symbol",r.symbol.clone()),("interval",r.interval.clone()),("startTime",cursor.to_string()),("endTime",(end.timestamp_millis()-1).to_string()),("limit","500".into())]).send().await.map_err(|_|refused(Refusal::Unavailable))?;
  // The gateway forwards a geographic block as 451 rather than a generic 503.
  if response.status()==reqwest::StatusCode::UNAVAILABLE_FOR_LEGAL_REASONS {return Err(blocked())}
  if response.status()==reqwest::StatusCode::TOO_MANY_REQUESTS {
   let header=response.headers().get(reqwest::header::RETRY_AFTER).and_then(|v|v.to_str().ok()).map(str::to_owned);
   let body:Value=response.json().await.unwrap_or_default();
   cool_down(told_to_wait(header.as_deref(),&body));
   return Err(refused(Refusal::RateLimited));
  }
  let response=response.error_for_status().map_err(|_|refused(Refusal::Unavailable))?;
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

#[cfg(test)]
mod tests {
 use super::*;

 #[test]
 fn the_gateway_says_how_long_to_wait_and_we_believe_the_header_first() {
  let body=json!({"error":"upstream_rate_limited","retryAfter":30});
  assert_eq!(told_to_wait(Some("5"),&body),std::time::Duration::from_secs(5));
  assert_eq!(told_to_wait(None,&body),std::time::Duration::from_secs(30));
  assert_eq!(told_to_wait(None,&json!({"error":"busy","retryAfter":"2"})),std::time::Duration::from_secs(2));
  // 什么都没说、或者说了读不出来的东西，按默认值等，绝不当成「可以马上再来」。
  assert_eq!(told_to_wait(None,&json!({"error":"busy"})),UNTOLD_COOLDOWN);
  assert_eq!(told_to_wait(Some("soon"),&Value::Null),UNTOLD_COOLDOWN);
  assert_eq!(told_to_wait(None,&json!({"error":"busy","retryAfter":0})),UNTOLD_COOLDOWN);
 }

 #[tokio::test(start_paused=true)]
 async fn a_rate_limited_gateway_is_left_alone_until_the_cooldown_lapses() {
  *gateway_cooldown().lock().unwrap_or_else(|e|e.into_inner())=None;
  assert!(cooling().is_none());
  cool_down(std::time::Duration::from_secs(30));
  assert!(cooling().is_some_and(|left|left>std::time::Duration::from_secs(29)));
  // 第二次更短的冷却不许把已经记下的那条线拉近。
  cool_down(std::time::Duration::from_secs(1));
  assert!(cooling().is_some_and(|left|left>std::time::Duration::from_secs(28)));
  // 说得再离谱也有上限。
  cool_down(std::time::Duration::from_secs(9999));
  assert!(cooling().is_some_and(|left|left<=LONGEST_COOLDOWN));
  tokio::time::sleep(LONGEST_COOLDOWN+std::time::Duration::from_secs(1)).await;
  assert!(cooling().is_none(),"冷却过了就照常出站");
 }
}
