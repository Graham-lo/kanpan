//! The open interest archive routes as the phone reaches them.
//!
//! These exercise the request surface only — path shape, validation, the
//! answers that are decided before anything is downloaded — so they need
//! neither the archive nor a database: the pool is opened lazily and never
//! used, because nothing under `/oi/` touches it.
use axum::{Router,body::Body,http::{Request,StatusCode}};
use http_body_util::BodyExt;
use kanpan_api::{AppState,crypto::Secrets};
use std::sync::Arc;
use tower::ServiceExt;

fn app()->Router {
 let pool=sqlx::postgres::PgPoolOptions::new().connect_lazy("postgres://unused@127.0.0.1:1/unused").unwrap();
 let secrets=Arc::new(Secrets{pepper:vec![31;32],encryption:[43;32]});
 let dummy_hash=Arc::new(secrets.hash_password("dummy123456").unwrap());
 kanpan_api::router(AppState{pool,secrets,dummy_hash,mail_enabled:false})
}

async fn get(path:&str)->(StatusCode,String) {
 let request=Request::builder().uri(path).body(Body::empty()).unwrap();
 let reply=app().oneshot(request).await.unwrap();
 let status=reply.status();
 let body=reply.into_body().collect().await.unwrap().to_bytes();
 (status,String::from_utf8_lossy(&body).into_owned())
}

#[tokio::test]
async fn a_symbol_that_could_name_a_file_elsewhere_is_refused() {
 for symbol in ["..%2Fetc","%2Fetc%2Fpasswd","btcusdt","BTC%20USDT","BTC%2FUSDT","BTC.USDT"] {
  let (status,_)=get(&format!("/oi/v1/metrics/{symbol}/range?interval=1d&from=1600000000000&to=1600100000000")).await;
  assert_ne!(status,StatusCode::OK,"{symbol} must not be read as a symbol");
 }
}

#[tokio::test]
async fn a_range_is_checked_before_a_single_day_is_downloaded() {
 let now=chrono::Utc::now().timestamp_millis();
 let bad=[
  format!("interval=2d&from={}&to={now}",now-86_400_000),      // no such chart interval
  format!("interval=1d&from=1000000000000&to={now}"),          // older than the archive
  format!("interval=1d&from={now}&to={}",now+86_400_000),      // into the future
  format!("interval=1d&from={}&to={}",now-86_400_000,now-172_800_000), // backwards
  format!("interval=5m&from={}&to={now}",now-400*86_400_000i64),       // more buckets than a chart can hold
 ];
 for query in bad {
  let (status,body)=get(&format!("/oi/v1/metrics/BTCUSDT/range?{query}")).await;
  assert_eq!(status,StatusCode::BAD_REQUEST,"{query} -> {body}");
 }
}

#[tokio::test]
async fn a_window_that_ends_before_the_archive_begins_is_an_empty_series() {
 let now=chrono::Utc::now().timestamp_millis();
 // Today has no archive yet: the window falls entirely inside the day that is
 // still being written, so the answer is an empty series, not an error.
 let (status,body)=get(&format!("/oi/v1/metrics/BTCUSDT/range?interval=5m&from={}&to={}",now/86_400_000*86_400_000,now-1000)).await;
 assert_eq!(status,StatusCode::OK,"{body}");
 assert_eq!(body,"[]");
}

#[tokio::test]
async fn a_day_outside_the_archive_is_a_plain_not_found() {
 for tail in ["2019-01-01.json","2999-01-01.json","notadate.json","2024-01-01"] {
  let (status,_)=get(&format!("/oi/v1/metrics/BTCUSDT/{tail}")).await;
  assert_eq!(status,StatusCode::NOT_FOUND,"{tail}");
 }
}
