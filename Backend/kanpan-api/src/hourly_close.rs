//! 小时收盘，以及读它的那一条路由：`/v1/market/hourly-closes`（2026-09-30）。
//!
//! 网页版的「指标与叠加」要拿一篮子合约过去 170 个整小时的收盘价（相对强弱、相关性这类跨品种的算法），
//! 浏览器自己去币安拉就是每只一次 K 线请求、两百只两百次，而且直连在国内时好时坏。这里在服务端
//! 常驻收一份：全部 U 本位永续（`sector_history::perpetuals`，含美股 / ETF / 贵金属那两百只
//! `TRADIFI_PERPETUAL`），每小时整点后扫一遍，存进公开表 `hourly_close`（迁移 0037），保留 8 天、滚动删。
//!
//! 和 `sector_history` 一个路数：
//!
//! * 走网站主机 `www.binance.com/fapi/v1/klines`（VPS 在美国，`fapi.binance.com` 回 451）；
//! * 出站前看 [`binance_gate`]，429 / 418 记进那条全进程共享的截止时间、本轮到此为止；
//! * 全进程一秒一个请求（[`REQUEST_GAP`]），一次一只。
//!
//! **只问缺的**：每只先看库里最新那一小时，只要它之后到「最近一个已收盘的整小时」之间缺的那几根
//! （稳态每小时 `limit=2`、权重 1；新上市或空表时一次最多 171 根，权重 2）。所以 serve 重启时这一路
//! 几乎不出站——重启后的那几分钟正是订单流快照通道排着一百多本簿的时候（压测 C 路第 3 项）。
//! 七百来只一秒一只，一轮十二分钟左右，一小时花币安的权重不到八百（稳态一只 1）。
//!
//! 路由契约（网页版照这个写，不许改）：
//!
//! ```text
//! GET /v1/market/hourly-closes?symbols=BTCUSDT,ETHUSDT      最多 200 只，大写，逗号分隔
//! 200 {"asOf":1790000000000,"hours":170,"series":{"BTCUSDT":[[hour_open_ms,close],…],…}}
//! ```
//!
//! * 每只按时间升序，只给已收盘的整小时，最多 170 根；库里没有的品种键不出现（不给空数组）。
//! * `asOf` 是这份答复截止的那一刻：当前这一小时的开盘时刻（= 最近一个已收盘小时的收盘时刻）。
//! * `Cache-Control: public, max-age=300`；不套 `{"data":…}` 信封。
//! * `symbols` 缺失、为空、超过 200 只、或有一只不是合约名（大写字母 / 数字 / 下划线，≤ 32 字）：
//!   400 `{"error":"invalid_symbols"}`。
//!
//! 和别的公开行情一样不要登录。
use crate::{AppState,binance_gate,market_meta,sector_history};
use axum::{Router,extract::{RawQuery,State},http::{StatusCode,header},response::{IntoResponse,Response},routing::get};
use chrono::Utc;
use serde_json::{Value,json};
use sqlx::PgPool;
use std::collections::{BTreeMap,HashMap};
use std::time::Duration;

const KLINES:&str="https://www.binance.com/fapi/v1/klines";
pub const HOUR_MS:i64=3_600_000;
/// 答复里每只最多几根，也是空表回填的根数。
pub const HOURS:usize=170;
/// 一次最多问几只。
pub const MAX_SYMBOLS:usize=200;
/// 表里留多久：8 天（192 小时），比答复要的 170 小时多一截，整点前后、扫描跑到一半都不缺。
pub const RETENTION_MS:i64=8*24*HOUR_MS;
/// 全进程一秒一个请求。
const REQUEST_GAP:Duration=Duration::from_secs(1);
const TRANSPORT_TRIES:u32=2;
const TRANSPORT_PAUSE:Duration=Duration::from_secs(2);
/// 整点后多久开扫：等币安把刚收的那根落定。
const AFTER_HOUR:Duration=Duration::from_secs(60);
/// 一轮没收完（封禁、5xx、断连）几分钟后再来——下一轮只问还缺的。
const RETRY:Duration=Duration::from_secs(300);
const CACHE:&str="public, max-age=300";

pub fn routes()->Router<AppState> {
 Router::new().route("/v1/market/hourly-closes",get(hourly_closes))
}

// ------------------------------------------------------------------ the calendar

/// 最近一个已收盘整小时的开盘时刻。
pub fn last_closed(now_ms:i64)->i64 {now_ms.div_euclid(HOUR_MS)*HOUR_MS-HOUR_MS}

/// 下一轮什么时候开：下一个整点过 [`AFTER_HOUR`]。
pub fn until_next_run(now_ms:i64)->Duration {
 let next=(now_ms.div_euclid(HOUR_MS)+1)*HOUR_MS+AFTER_HOUR.as_millis() as i64;
 let this=now_ms.div_euclid(HOUR_MS)*HOUR_MS+AFTER_HOUR.as_millis() as i64;
 let at=if this>now_ms {this} else {next};
 Duration::from_millis((at-now_ms).max(0) as u64)
}

/// 这一只要问几根（`limit`）；`None` 是已经齐了、不用问。
///
/// 多问一根：币安最后回的那根是还没收完的当前小时，到手就扔（[`parse_hourly_closes`] 按收盘时间判）。
pub fn limit_for(newest:Option<i64>,last_closed:i64)->Option<usize> {
 let owed=match newest {
  None=>HOURS,
  Some(have) if have>=last_closed=>return None,
  Some(have)=>(((last_closed-have)/HOUR_MS) as usize).min(HOURS),
 };
 Some(owed+1)
}

// ------------------------------------------------------------------- the parsers

fn num(v:&Value)->Option<f64> {
 match v {Value::String(s)=>s.parse().ok(),_=>v.as_f64()}.filter(|x:&f64|x.is_finite())
}

/// `[[openTime,open,high,low,close,volume,closeTime,…],…]` 里已收盘的整小时：`(hour_open_ms, close)`，升序。
///
/// 只读 `closeTime` 已经过去的那几根（当前这一小时的收盘价整个小时都在变）；开盘时刻不在整点上、
/// 收盘价不是正数的行不收。
pub fn parse_hourly_closes(body:&Value,now_ms:i64)->Vec<(i64,f64)> {
 let Some(rows)=body.as_array() else {return Vec::new()};
 let mut out:Vec<(i64,f64)>=rows.iter().filter_map(|row|{
  let open=row[0].as_i64()?;
  if row[6].as_i64().is_none_or(|close_time|close_time>=now_ms)||open.rem_euclid(HOUR_MS)!=0 {return None}
  let close=num(&row[4]).filter(|c|*c>0.0)?;
  Some((open,close))
 }).collect();
 out.sort_by_key(|r|r.0);
 // 同一条 `ON CONFLICT` 语句不许碰同一行两次。
 out.dedup_by_key(|r|r.0);
 out
}

/// `symbols` 查询参数：逗号分隔、大写合约名、1–200 只；重复的只算一次。不合规就是 `None`。
pub fn parse_symbols(query:Option<&str>)->Option<Vec<String>> {
 let raw=query?.split('&').find_map(|pair|pair.strip_prefix("symbols="))?;
 // 逗号可能被编码成 %2C。
 let raw=raw.replace("%2C",",").replace("%2c",",");
 let mut out:Vec<String>=Vec::new();
 for symbol in raw.split(',') {
  // 中文底名合约（龙虾USDT）浏览器会编成 %XX 送来；以前这里见 % 就整批 400，一个板块的走势线全空。
  let symbol=crate::instruments::url_decode(symbol)?;
  if symbol.is_empty()||symbol.chars().count()>32||!symbol.chars().all(crate::instruments::binance_symbol_char) {return None}
  out.push(symbol);
 }
 out.sort_unstable();out.dedup();
 (!out.is_empty()&&out.len()<=MAX_SYMBOLS).then_some(out)
}

/// 答复的体。`rows` 按 (symbol, hour) 升序。
pub fn payload(as_of:i64,rows:&[(String,i64,f64)])->Value {
 let mut series:BTreeMap<&str,Vec<Value>>=BTreeMap::new();
 for (symbol,hour,close) in rows {
  if !close.is_finite()||*close<=0.0 {continue}
  series.entry(symbol.as_str()).or_default().push(json!([hour,close]));
 }
 json!({"asOf":as_of,"hours":HOURS,"series":series})
}

// ----------------------------------------------------------------- the collection

async fn throttle() {
 static LAST:std::sync::OnceLock<tokio::sync::Mutex<Option<tokio::time::Instant>>>=std::sync::OnceLock::new();
 let mut last=LAST.get_or_init(||tokio::sync::Mutex::new(None)).lock().await;
 let now=tokio::time::Instant::now();
 let earliest=last.map(|t|t+REQUEST_GAP).unwrap_or(now);
 if earliest>now {tokio::time::sleep_until(earliest).await}
 *last=Some(tokio::time::Instant::now());
}

/// 一只这一次的结果。`Banned` 是整轮的事。
enum Fetch {Body(Value),Skip,Retry,Banned}

async fn klines(symbol:&str,limit:usize)->Fetch {
 let url=format!("{KLINES}?symbol={}&interval=1h&limit={limit}",crate::instruments::url_component(symbol));
 for attempt in 0..TRANSPORT_TRIES {
  if let Some(left)=binance_gate::wait() {
   tracing::warn!("Hourly closes: this egress is held for another {}s; stopping the round",left.as_secs());
   return Fetch::Banned;
  }
  throttle().await;
  let reply=match crate::http::shared().get(&url).send().await {
   Ok(reply)=>reply,
   Err(_)=>{if attempt+1<TRANSPORT_TRIES {tokio::time::sleep(TRANSPORT_PAUSE).await} continue}
  };
  if binance_gate::note_reply(&reply) {return Fetch::Banned}
  let status=reply.status();
  if !status.is_success() {return if status.is_server_error() {Fetch::Retry} else {Fetch::Skip}}
  return match reply.json::<Value>().await {Ok(body)=>Fetch::Body(body),Err(_)=>Fetch::Retry};
 }
 Fetch::Retry
}

async fn upsert(pool:&PgPool,symbol:&str,bars:&[(i64,f64)])->sqlx::Result<()> {
 let hours:Vec<i64>=bars.iter().map(|b|b.0).collect();
 let closes:Vec<f64>=bars.iter().map(|b|b.1).collect();
 // 值没变就不写（不留死元组）；币安真改了哪一根才更新。
 sqlx::query("INSERT INTO hourly_close(symbol,hour_ms,close) SELECT $1,h,c FROM UNNEST($2::bigint[],$3::double precision[]) AS t(h,c) \
  ON CONFLICT(symbol,hour_ms) DO UPDATE SET close=EXCLUDED.close WHERE hourly_close.close IS DISTINCT FROM EXCLUDED.close")
  .bind(symbol).bind(&hours).bind(&closes).execute(pool).await?;
 Ok(())
}

/// 每只库里最新的那一小时。
async fn newest(pool:&PgPool)->sqlx::Result<HashMap<String,i64>> {
 let rows:Vec<(String,i64)>=sqlx::query_as("SELECT symbol,max(hour_ms) FROM hourly_close GROUP BY symbol").fetch_all(pool).await?;
 Ok(rows.into_iter().collect())
}

/// 滚动删：8 天前的一律删，上没上市都一样（下市的品种 8 天后自然清空）。
async fn prune(pool:&PgPool,now_ms:i64)->sqlx::Result<u64> {
 Ok(sqlx::query("DELETE FROM hourly_close WHERE hour_ms<$1").bind(now_ms-RETENTION_MS).execute(pool).await?.rows_affected())
}

/// 一轮的结果。
#[derive(Debug,Default,PartialEq)]
pub struct Round {pub asked:usize,pub written:usize,pub skipped:usize,pub transient:usize,pub banned:bool}

/// 一轮：合约表 → 每只缺几根 → 一只一只问 → 滚动删。
pub async fn sweep(pool:&PgPool)->anyhow::Result<Round> {
 let body=market_meta::exchange_info().await.map_err(|_|anyhow::anyhow!("exchangeInfo unavailable"))?;
 let symbols=sector_history::perpetuals(&body);
 anyhow::ensure!(!symbols.is_empty(),"exchangeInfo listed no tradable perpetual");
 let target=last_closed(Utc::now().timestamp_millis());
 let have=newest(pool).await?;
 let mut round=Round::default();
 for symbol in &symbols {
  let Some(limit)=limit_for(have.get(symbol).copied(),target) else {continue};
  round.asked+=1;
  let body=match klines(symbol,limit).await {
   Fetch::Body(body)=>body,
   Fetch::Skip=>{round.skipped+=1;continue}
   Fetch::Retry=>{round.transient+=1;continue}
   Fetch::Banned=>{round.banned=true;break}
  };
  let bars=parse_hourly_closes(&body,Utc::now().timestamp_millis());
  if bars.is_empty() {round.skipped+=1;continue}
  match upsert(pool,symbol,&bars).await {
   Ok(())=>round.written+=bars.len(),
   Err(e)=>{tracing::warn!("Hourly closes: {symbol} not stored ({e})");round.transient+=1}
  }
 }
 let pruned=prune(pool,Utc::now().timestamp_millis()).await?;
 tracing::info!("Hourly closes: {} contracts, {} asked, {} rows written, {} skipped, {} to retry, {} pruned",
  symbols.len(),round.asked,round.written,round.skipped,round.transient,pruned);
 Ok(round)
}

/// 常驻任务，serve 里起（和路由同一个进程）。启动那一轮就是回填：空表时每只 170 根，
/// 已经有数据时只补重启期间缺的那几根。
pub fn spawn(pool:PgPool)->tokio::task::JoinHandle<()> {
 tokio::spawn(async move {
  loop {
   let wait=match sweep(&pool).await {
    Ok(round) if !round.banned&&round.transient==0=>until_next_run(Utc::now().timestamp_millis()),
    Ok(_)=>RETRY.min(until_next_run(Utc::now().timestamp_millis())),
    Err(e)=>{tracing::warn!("Hourly closes: round will retry ({e})");RETRY}
   };
   tokio::time::sleep(wait).await;
  }
 })
}

// ----------------------------------------------------------------------- handler

fn reply(status:StatusCode,body:Value,cache:&'static str)->Response {
 (status,[(header::CONTENT_TYPE,"application/json"),(header::CACHE_CONTROL,cache)],serde_json::to_vec(&body).unwrap_or_default()).into_response()
}

pub async fn read(pool:&PgPool,symbols:&[String],now_ms:i64)->sqlx::Result<Value> {
 let last=last_closed(now_ms);
 let first=last-(HOURS as i64-1)*HOUR_MS;
 let rows:Vec<(String,i64,f64)>=sqlx::query_as("SELECT symbol,hour_ms,close FROM hourly_close WHERE symbol=ANY($1) AND hour_ms BETWEEN $2 AND $3 ORDER BY symbol,hour_ms")
  .bind(symbols).bind(first).bind(last).fetch_all(pool).await?;
 Ok(payload(last+HOUR_MS,&rows))
}

async fn hourly_closes(State(s):State<AppState>,RawQuery(query):RawQuery)->Response {
 let Some(symbols)=parse_symbols(query.as_deref()) else {
  return reply(StatusCode::BAD_REQUEST,json!({"error":"invalid_symbols"}),"no-store");
 };
 match read(&s.pool,&symbols,Utc::now().timestamp_millis()).await {
  Ok(body)=>reply(StatusCode::OK,body,CACHE),
  Err(e)=>{
   tracing::warn!("Hourly closes unavailable ({e})");
   reply(StatusCode::SERVICE_UNAVAILABLE,json!({"error":"temporarily_unavailable"}),"no-store")
  }
 }
}

#[cfg(test)]
mod tests {
 use super::*;

 const T0:i64=1_790_000_000_000/HOUR_MS*HOUR_MS;
 fn bar(open:i64,close:&str)->Value {json!([open,"1","2","0",close,"10",open+HOUR_MS-1,"100",42,"5","5","0"])}

 #[test]
 fn only_closed_whole_hours_are_read() {
  let now=T0+2*HOUR_MS+120_000;
  let body=json!([
   bar(T0,"100.5"),
   bar(T0+HOUR_MS,"101"),
   // 当前这一小时还没收完。
   bar(T0+2*HOUR_MS,"102"),
  ]);
  assert_eq!(parse_hourly_closes(&body,now),vec![(T0,100.5),(T0+HOUR_MS,101.0)]);
  // 不在整点上的、收盘价不是正数的、读不出来的：不收；重复的一根只留一根，顺序按时间。
  let odd=json!([bar(T0+HOUR_MS,"7"),bar(T0+30_000,"5"),bar(T0,"0"),bar(T0,"x"),bar(T0+HOUR_MS,"7"),json!("nope")]);
  assert_eq!(parse_hourly_closes(&odd,now),vec![(T0+HOUR_MS,7.0)]);
  assert!(parse_hourly_closes(&json!({"code":-1121}),now).is_empty());
 }

 #[test]
 fn only_the_missing_hours_are_asked_for() {
  let last=T0;
  // 空表：170 根已收盘的加上还没收完的那一根。
  assert_eq!(limit_for(None,last),Some(HOURS+1));
  // 已经齐了：不出站。
  assert_eq!(limit_for(Some(last),last),None);
  // 稳态：缺刚收的那一根，问两根（权重 1）。
  assert_eq!(limit_for(Some(last-HOUR_MS),last),Some(2));
  // 重启空了三个小时：补三根。
  assert_eq!(limit_for(Some(last-3*HOUR_MS),last),Some(4));
  // 停了十天：照空表回填，不多问。
  assert_eq!(limit_for(Some(last-240*HOUR_MS),last),Some(HOURS+1));
 }

 #[test]
 fn the_calendar_is_whole_utc_hours() {
  assert_eq!(last_closed(T0),T0-HOUR_MS);
  assert_eq!(last_closed(T0+HOUR_MS-1),T0-HOUR_MS);
  assert_eq!(last_closed(T0+HOUR_MS),T0);
  // 整点过一分钟开扫：还没到就等到这一点，过了就等下一个整点。
  assert_eq!(until_next_run(T0),AFTER_HOUR);
  assert_eq!(until_next_run(T0+AFTER_HOUR.as_millis() as i64),Duration::from_millis(HOUR_MS as u64));
  assert_eq!(until_next_run(T0+10*60_000),Duration::from_millis((HOUR_MS-10*60_000) as u64)+AFTER_HOUR);
 }

 #[test]
 fn the_symbols_parameter_is_one_to_two_hundred_contract_names() {
  assert_eq!(parse_symbols(Some("symbols=ETHUSDT,BTCUSDT,ETHUSDT")),Some(vec!["BTCUSDT".to_owned(),"ETHUSDT".to_owned()]));
  assert_eq!(parse_symbols(Some("x=1&symbols=BTCUSDT%2C1000PEPEUSDT")),Some(vec!["1000PEPEUSDT".to_owned(),"BTCUSDT".to_owned()]));
  // 浏览器把中文底名编成 %XX 送来（板块里混着「龙虾USDT」时整批不能 400）。
  assert_eq!(parse_symbols(Some("symbols=BTCUSDT,%E9%BE%99%E8%99%BEUSDT")),Some(vec!["BTCUSDT".to_owned(),"龙虾USDT".to_owned()]));
  assert_eq!(parse_symbols(Some("symbols=%E9%BE%99%E8%99%BE%2FUSDT")),None);
  for bad in [None,Some(""),Some("symbols="),Some("symbols=btcusdt"),Some("symbols=BTCUSDT,,ETHUSDT"),Some("symbols=BTC%20USDT"),Some("symbol=BTCUSDT")] {
   assert_eq!(parse_symbols(bad),None,"{bad:?}");
  }
  let two_hundred=(0..200).map(|i|format!("S{i}USDT")).collect::<Vec<_>>().join(",");
  assert_eq!(parse_symbols(Some(&format!("symbols={two_hundred}"))).map(|v|v.len()),Some(200));
  assert_eq!(parse_symbols(Some(&format!("symbols={two_hundred},MOREUSDT"))),None);
  assert_eq!(parse_symbols(Some(&format!("symbols={}","A".repeat(33)))),None);
 }

 #[test]
 fn a_symbol_with_no_rows_has_no_key() {
  let rows=vec![("BTCUSDT".to_owned(),T0,1.0),("BTCUSDT".to_owned(),T0+HOUR_MS,2.0),("ETHUSDT".to_owned(),T0,f64::NAN)];
  assert_eq!(payload(T0+2*HOUR_MS,&rows),json!({"asOf":T0+2*HOUR_MS,"hours":170,"series":{"BTCUSDT":[[T0,1.0],[T0+HOUR_MS,2.0]]}}));
 }

 async fn isolated_pool()->Option<PgPool> {
  let (Ok(admin),Ok(url),Ok(role))=(std::env::var("KANPAN_TEST_ADMIN_URL"),std::env::var("KANPAN_TEST_DATABASE_URL"),std::env::var("KANPAN_TEST_ROLE")) else {
   eprintln!("Skipping the hourly_close database assertions: run ops/test.py for an isolated PostgreSQL");
   return None;
  };
  assert!(role.chars().all(|c|c.is_ascii_alphanumeric()||c=='_'));
  for target in [&admin,&url] {
   assert!(target.contains("@127.0.0.1:")||target.contains("@localhost:"),"tests must never target a database off this machine");
  }
  let admin=PgPool::connect(&admin).await.unwrap();
  sqlx::migrate!().run(&admin).await.unwrap();
  for sql in [format!("GRANT USAGE ON SCHEMA public TO {role}"),format!("GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO {role}")] {
   sqlx::query(&sql).execute(&admin).await.unwrap();
  }
  Some(PgPool::connect(&url).await.unwrap())
 }

 #[tokio::test]
 async fn the_table_serves_the_last_170_closed_hours_and_rolls_off_after_eight_days() {
  let Some(pool)=isolated_pool().await else {return};
  sqlx::query("DELETE FROM hourly_close WHERE symbol LIKE 'HCT%'").execute(&pool).await.unwrap();
  let now=Utc::now().timestamp_millis();
  let last=last_closed(now);
  // 200 个小时：比答复要的 170 多，也跨过了 8 天的保留线之内。
  let bars:Vec<(i64,f64)>=(0..200).map(|k|(last-(199-k)*HOUR_MS,100.0+k as f64)).collect();
  upsert(&pool,"HCTAUSDT",&bars).await.unwrap();
  // 重跑同一批：一行不多、一个元组不改。
  let versions=||{let pool=pool.clone();async move{sqlx::query_scalar::<_,String>("SELECT string_agg(xmin::text,',' ORDER BY hour_ms) FROM hourly_close WHERE symbol='HCTAUSDT'").fetch_one(&pool).await.unwrap()}};
  let before=versions().await;
  upsert(&pool,"HCTAUSDT",&bars).await.unwrap();
  assert_eq!(versions().await,before,"没变的小时不重写");
  upsert(&pool,"HCTBUSDT",&[(last-HOUR_MS,5.0),(last,6.0)]).await.unwrap();
  // 最新的那一小时：增量只问之后缺的。
  let have=newest(&pool).await.unwrap();
  assert_eq!(have.get("HCTAUSDT"),Some(&last));
  assert_eq!(limit_for(have.get("HCTAUSDT").copied(),last),None);

  let body=read(&pool,&["HCTAUSDT".to_owned(),"HCTBUSDT".to_owned(),"HCTNONEUSDT".to_owned()],now).await.unwrap();
  assert_eq!(body["asOf"],json!(last+HOUR_MS));
  assert_eq!(body["hours"],json!(170));
  let a=body["series"]["HCTAUSDT"].as_array().unwrap();
  assert_eq!(a.len(),170,"只给最近 170 个已收盘小时");
  assert_eq!(a.first().unwrap(),&json!([last-169*HOUR_MS,130.0]));
  assert_eq!(a.last().unwrap(),&json!([last,299.0]));
  assert!(a.windows(2).all(|w|w[0][0].as_i64()<w[1][0].as_i64()),"升序");
  assert_eq!(body["series"]["HCTBUSDT"],json!([[last-HOUR_MS,5.0],[last,6.0]]));
  assert!(body["series"].get("HCTNONEUSDT").is_none(),"没有数据的品种键不出现");

  // 滚动删：8 天以前的删掉，以内的留着。
  upsert(&pool,"HCTOLDUSDT",&[(now-RETENTION_MS-HOUR_MS,1.0),(now-RETENTION_MS+HOUR_MS,2.0)]).await.unwrap();
  prune(&pool,now).await.unwrap();
  let old:Vec<i64>=sqlx::query_scalar("SELECT hour_ms FROM hourly_close WHERE symbol='HCTOLDUSDT'").fetch_all(&pool).await.unwrap();
  assert_eq!(old,vec![now-RETENTION_MS+HOUR_MS]);

  // 路由：不要登录、不套信封、五分钟缓存；参数不对回 400 invalid_symbols。
  use axum::{body::Body,http::Request};
  use http_body_util::BodyExt;
  use tower::ServiceExt;
  use std::sync::Arc;
  let secrets=Arc::new(crate::crypto::Secrets{pepper:vec![31;32],encryption:[43;32]});
  let dummy_hash=Arc::new(secrets.hash_password("dummy123456").unwrap());
  let app=crate::router(AppState{pool:pool.clone(),secrets,dummy_hash});
  let reply=app.clone().oneshot(Request::builder().uri("/v1/market/hourly-closes?symbols=HCTBUSDT,HCTNONEUSDT").body(Body::empty()).unwrap()).await.unwrap();
  assert_eq!(reply.status(),StatusCode::OK);
  assert_eq!(reply.headers()[header::CACHE_CONTROL],"public, max-age=300");
  let served:Value=serde_json::from_slice(&reply.into_body().collect().await.unwrap().to_bytes()).unwrap();
  assert!(served.get("data").is_none(),"不套信封");
  assert_eq!(served["series"],json!({"HCTBUSDT":[[last-HOUR_MS,5.0],[last,6.0]]}));
  let too_many=(0..201).map(|i|format!("S{i}USDT")).collect::<Vec<_>>().join(",");
  for uri in ["/v1/market/hourly-closes".to_owned(),format!("/v1/market/hourly-closes?symbols={too_many}")] {
   let reply=app.clone().oneshot(Request::builder().uri(uri).body(Body::empty()).unwrap()).await.unwrap();
   assert_eq!(reply.status(),StatusCode::BAD_REQUEST);
   let served:Value=serde_json::from_slice(&reply.into_body().collect().await.unwrap().to_bytes()).unwrap();
   assert_eq!(served,json!({"error":"invalid_symbols"}));
  }
  sqlx::query("DELETE FROM hourly_close WHERE symbol LIKE 'HCT%'").execute(&pool).await.unwrap();
 }
}
