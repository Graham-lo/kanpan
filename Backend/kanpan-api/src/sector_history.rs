//! Daily closes, and the one route that reads them: `/v1/market/sector-history`.
//!
//! Sector strength over five and twenty days needs two numbers per contract —
//! the close five complete UTC days ago and the close twenty complete UTC days
//! ago — which the phone divides its live price by. That is one candle per
//! contract per day, so this is a daily collection and a table of about seven
//! hundred rows a day, not a streaming job.
//!
//! Unlike `market_meta`, which is a cache with no storage behind it, history is
//! the whole point here: a day that is not collected is a day nobody can
//! recover later. So it lands in PostgreSQL, in a public table with no owner
//! and no row level security, and the served answer is a process cache in front
//! of it — thirty kilobytes for the whole market.
//!
//! Like the rest of the public market surface this route carries no
//! authentication.
use crate::{AppState,binance_gate,market_meta};
use axum::{Router,extract::State,http::{StatusCode,header},response::{IntoResponse,Response},routing::get};
use chrono::{DateTime,Days,NaiveDate,Utc};
use serde_json::{Value,json};
use sqlx::PgPool;
use std::collections::{BTreeMap,HashSet};
use std::future::Future;
use std::pin::Pin;
use std::sync::{Arc,OnceLock,RwLock};
use std::time::Duration;

/// Read through the website host, never `fapi.binance.com`: both market VPS sit
/// in the United States, where the API hosts answer 451 and the same paths
/// served off `www.binance.com` answer 200 with production data. The reasoning
/// and the measurement are in `market_meta.rs`, which reaches the same family
/// of paths for open interest and prices.
const KLINES:&str="https://www.binance.com/fapi/v1/klines";
/// Twenty-one complete days are what the twenty-day window needs; the
/// twenty-second is today's unfinished candle, which is dropped on arrival.
const HISTORY_LIMIT:usize=22;
/// One request a second across the whole process. Seven hundred contracts is
/// then a twelve minute sweep once a day, which costs Binance less in an hour
/// than a single chart does, and leaves the weight budget to the live routes.
const REQUEST_GAP:Duration=Duration::from_secs(1);
/// 429 和 418 不在这里退避了：它们说的是「这个 IP 现在别出站」，是整个进程的事，
/// 归 [`binance_gate`] 那条共享截止时间管（A-06）。这里只留传输层的一次重试：
/// keep-alive 连接被掐断是家常事，跟限速无关。
const TRANSPORT_TRIES:u32=2;
const TRANSPORT_PAUSE:Duration=Duration::from_secs(2);
/// The collection starts ten minutes after midnight UTC, by which time the day
/// Binance closed at midnight is settled.
const RUN_MINUTE:u32=10;
/// A failed sweep is retried within the hour rather than waited out until
/// tomorrow: the five-day window would survive the gap, a cold table would not.
const RETRY:Duration=Duration::from_secs(600);
/// How long a row lives. A year is far more than the twenty-day window asks
/// for; it is what makes the table worth keeping at all if a longer window is
/// ever wanted, and at thirteen megabytes a year it is not worth trimming.
const RETENTION_DAYS:u64=365;
/// A contract that has left `exchangeInfo` keeps its history for a month. Long
/// enough that a symbol suspended over a weekend is not thrown away, short
/// enough that delistings do not accumulate.
const DELISTED_GRACE_DAYS:u64=30;

pub fn routes()->Router<AppState> {
 Router::new().route("/v1/market/sector-history",get(sector_history))
}

// --------------------------------------------------------------- the calendar

/// `asof` minus `back` complete UTC days. Calendar arithmetic, not milliseconds:
/// five days before the first of March is the twenty-fourth of February in a
/// leap year and the twenty-third in every other one, and subtracting a fixed
/// number of seconds would get exactly one of those right.
pub fn window_day(asof:NaiveDate,back:u64)->NaiveDate {
 asof.checked_sub_days(Days::new(back)).unwrap_or(asof)
}

/// How long until the next collection. The next 00:10 UTC strictly after `now`,
/// so a sweep that finishes at 00:22 waits for tomorrow rather than starting
/// again immediately.
pub fn until_next_run(now:DateTime<Utc>)->Duration {
 let at=|day:NaiveDate|day.and_hms_opt(0,RUN_MINUTE,0).map(|t|t.and_utc());
 let today=now.date_naive();
 let next=match at(today) {
  Some(t) if t>now=>Some(t),
  _=>at(today.checked_add_days(Days::new(1)).unwrap_or(today)),
 };
 next.and_then(|t|(t-now).to_std().ok()).unwrap_or(RETRY)
}

// ----------------------------------------------------------------- the parsers

fn num(v:&Value)->Option<f64> {
 match v {Value::String(s)=>s.parse().ok(),_=>v.as_f64()}.filter(|x:&f64|x.is_finite())
}

/// The symbols worth collecting: perpetual contracts that are open for trading.
///
/// Both perpetual flavours count. Binance marks the equity, ETF and metal
/// contracts `TRADIFI_PERPETUAL` rather than `PERPETUAL`, and those two hundred
/// symbols are the whole of the phone's "US" market — collecting only
/// `PERPETUAL` left that market with no history at all and its five-day window
/// permanently empty.
///
/// `exchangeInfo` also lists quarterly futures and contracts in `SETTLING`,
/// `PENDING_TRADING` or `BREAK`. A quarterly's history belongs to a contract
/// that expires, and a contract that is not trading has no live price for the
/// phone to divide, so neither earns a daily request.
///
/// The predicate itself lives in `instruments::is_live_perpetual`, shared with the
/// open-interest warm-up, so the two can no longer disagree about what a perpetual is.
pub fn perpetuals(body:&Value)->Vec<String> {
 let Some(rows)=body["symbols"].as_array() else {return Vec::new()};
 let mut out:Vec<String>=rows.iter().filter(|row|crate::instruments::is_live_perpetual(row)).filter_map(|row|row["symbol"].as_str()).filter(|symbol|{
  // The name goes into a query string; anything that is not a contract name
  // is a row we cannot read rather than a request to make.
  !symbol.is_empty()&&symbol.len()<=32&&symbol.chars().all(|c|c.is_ascii_alphanumeric()||c=='_')
 }).map(str::to_ascii_uppercase).collect();
 out.sort_unstable();out.dedup();out
}

/// `[[openTime,open,high,low,close,volume,closeTime,quoteAssetVolume,…],…]`,
/// oldest first, into `(UTC day, close, quote volume)`.
///
/// Only candles whose `closeTime` is already behind `now_ms` are read: a daily
/// candle asked for at 00:10 ends with the day that started ten minutes ago,
/// whose close is whatever the price happens to be right now. Writing it would
/// put a number in the table that changes all day, and every window that
/// touched it would move under the phone.
///
/// 原来是「不看就扔掉最后一行」：上游那一刻还没长出今天那根（新日刚开、这只合约
/// 还没成交，或者回来的是一只停在 BREAK 里的合约）时，扔掉的是**昨天那根完整的**，
/// 于是这只合约永远缺昨天、每轮都被当成「还欠一天」。按收盘时间判，才只扔真没收完的。
pub fn parse_daily_closes(body:&Value,now_ms:i64)->Vec<(NaiveDate,f64,f64)> {
 let Some(rows)=body.as_array() else {return Vec::new()};
 let mut out=Vec::with_capacity(rows.len());
 for row in rows {
  if !row[6].as_i64().is_some_and(|close_time|close_time<now_ms) {continue}
  let Some(day)=row[0].as_i64().and_then(DateTime::from_timestamp_millis).map(|t|t.date_naive()) else {continue};
  let (Some(close),Some(volume))=(num(&row[4]),num(&row[7])) else {continue};
  if close<=0.0||volume<0.0 {continue}
  out.push((day,close,volume));
 }
 // The upsert writes one statement per contract, and PostgreSQL refuses to let
 // a single `ON CONFLICT` statement touch the same row twice. Binance does not
 // repeat a day, but one repeated day would otherwise fail a whole contract.
 out.dedup_by(|a,b|a.0==b.0);
 out
}

/// The served body: every contract that has a close at one or both window
/// starts, keyed by symbol.
///
/// A missing figure is an absent field, never a zero — the phone divides by it,
/// and a zero would read as an infinite gain rather than as "no history yet".
/// A contract with neither figure is left out of `symbols` altogether instead of
/// appearing as an empty object.
pub fn payload(asof:NaiveDate,rows:&[(String,NaiveDate,f64)])->Value {
 let (five,twenty)=(window_day(asof,5),window_day(asof,20));
 let mut symbols:BTreeMap<&str,serde_json::Map<String,Value>>=BTreeMap::new();
 for (symbol,day,close) in rows {
  let field=if *day==five {"c5"} else if *day==twenty {"c20"} else {continue};
  if !close.is_finite()||*close<=0.0 {continue}
  symbols.entry(symbol.as_str()).or_default().insert(field.to_owned(),json!(close));
 }
 let symbols:serde_json::Map<String,Value>=symbols.into_iter()
  .filter(|(_,fields)|!fields.is_empty())
  .map(|(symbol,fields)|(symbol.to_owned(),Value::Object(fields))).collect();
 json!({"asof":asof.to_string(),"symbols":symbols})
}

// ---------------------------------------------------------------- the cache

/// The whole answer, serialised once. `asof` is the day it was built for, which
/// is how a snapshot is noticed to be yesterday's.
pub struct Snapshot {pub asof:NaiveDate,pub body:Vec<u8>}
fn cache()->&'static RwLock<Option<Arc<Snapshot>>> {
 static C:OnceLock<RwLock<Option<Arc<Snapshot>>>>=OnceLock::new();
 C.get_or_init(||RwLock::new(None))
}
fn stale()->Option<Arc<Snapshot>> {cache().read().unwrap_or_else(|e|e.into_inner()).clone()}
fn cached(asof:NaiveDate)->Option<Arc<Snapshot>> {stale().filter(|s|s.asof==asof)}

/// Reads the two window days out of the table and replaces the cache.
///
/// Called after every collection, and by the first request of a new UTC day:
/// `asof` moves at midnight even though nothing new has been collected, because
/// the day five days back moves with it.
pub async fn rebuild(pool:&PgPool,asof:NaiveDate)->sqlx::Result<Arc<Snapshot>> {
 let rows:Vec<(String,NaiveDate,f64)>=sqlx::query_as("SELECT symbol,day,close FROM daily_close WHERE day=$1 OR day=$2")
  .bind(window_day(asof,5)).bind(window_day(asof,20)).fetch_all(pool).await?;
 // The `{"data":…}` wrapper `crate::envelope` writes, spelled out because this
 // route sets `Cache-Control` and so builds its own response rather than
 // returning `Json`.
 let body=serde_json::to_vec(&json!({"data":payload(asof,&rows)})).unwrap_or_default();
 Ok(install(Arc::new(Snapshot{asof,body})))
}

/// 放进缓存，但不许往回退。午夜前后可能同时有几次重建在跑：日任务 23:59 起的那次
/// 是给昨天算的，请求 00:00 起的是给今天算的；昨天那次后完成的话，原来会把今天的
/// 盖掉，下一个请求又得重建一遍。日期更早的那份照样返回给调它的人，只是不进缓存。
fn install(snapshot:Arc<Snapshot>)->Arc<Snapshot> {install_into(cache(),snapshot)}
fn install_into(slot:&RwLock<Option<Arc<Snapshot>>>,snapshot:Arc<Snapshot>)->Arc<Snapshot> {
 let mut slot=slot.write().unwrap_or_else(|e|e.into_inner());
 if slot.as_ref().is_none_or(|current|current.asof<=snapshot.asof) {*slot=Some(snapshot.clone())}
 snapshot
}

// -------------------------------------------------------------- the collection

/// One request a second for the whole process, retries included. The lock is
/// held across the wait on purpose: that is what makes the sweep serial, so two
/// callers cannot each believe they are the one request this second.
async fn throttle() {
 static LAST:OnceLock<tokio::sync::Mutex<Option<tokio::time::Instant>>>=OnceLock::new();
 let mut last=LAST.get_or_init(||tokio::sync::Mutex::new(None)).lock().await;
 let now=tokio::time::Instant::now();
 let earliest=last.map(|t|t+REQUEST_GAP).unwrap_or(now);
 if earliest>now {tokio::time::sleep_until(earliest).await}
 *last=Some(tokio::time::Instant::now());
}

/// 上游这一次的回答，只留下判断退避需要的东西。
enum Reply {Body(Value),Status(u16,Option<String>),Transport}
/// 抓一个品种的日 K 这一步抽成 trait，好让「两个品种先后被 418」这种时序在不联网
/// 的情况下也跑得出来——原来它只有真的撞上币安的封禁才走得到，于是「换个品种就把
/// 退避重置一遍」这个毛病没有任何测试拦得住。
trait Klines:Send+Sync {
 fn get<'a>(&'a self,symbol:&'a str)->Pin<Box<dyn Future<Output=Reply>+Send+'a>>;
}
struct Binance;
impl Klines for Binance {
 fn get<'a>(&'a self,symbol:&'a str)->Pin<Box<dyn Future<Output=Reply>+Send+'a>> {
  Box::pin(async move {
   let url=format!("{KLINES}?symbol={symbol}&interval=1d&limit={HISTORY_LIMIT}");
   let reply=match crate::http::shared().get(&url).send().await {Ok(reply)=>reply,Err(_)=>return Reply::Transport};
   let status=reply.status();
   if !status.is_success() {
    let retry_after=reply.headers().get(header::RETRY_AFTER).and_then(|v|v.to_str().ok()).map(str::to_owned);
    return Reply::Status(status.as_u16(),retry_after);
   }
   match reply.json::<Value>().await {Ok(body)=>Reply::Body(body),Err(_)=>Reply::Transport}
  })
 }
}
/// 一个品种这一轮的结果。`Banned` 是整轮的事，不是这一个品种的事。
/// `Skip` 是上游明说这一只没有（404、451 这类 4xx），今天再问也一样；
/// `Retry` 是上游或网络这一下没接住（5xx、连接断），过几分钟再问多半就有了。
enum Fetch {Body(Value),Skip,Retry,Banned}

/// One contract's daily candles.
///
/// 429 / 418 记进共享闸门，然后本轮就到此为止：原来每个品种都从 2 秒重新起一轮
/// 2/4/8/16 秒的退避，还把 `Retry-After` 丢在一边，七百个品种就是七百次撞同一道
/// 墙。其它状态码（404、451、5xx）只是这一个品种今天没有，不值得为它放掉另外
/// 七百个。
async fn klines(source:&dyn Klines,symbol:&str)->Fetch {
 for attempt in 0..TRANSPORT_TRIES {
  // 每一次出站前都查一遍闸门，不是进函数时查一次就算了：传输失败要等
  // TRANSPORT_PAUSE 再重试，那两秒里别的品种完全可能已经把闸门按下去了，
  // 而重试出去的那一下正好落在封禁期里、只会把封禁撞得更长。
  if let Some(left)=binance_gate::wait() {
   tracing::warn!("Daily closes: this egress is held for another {}s; stopping the round",left.as_secs());
   return Fetch::Banned;
  }
  throttle().await;
  match source.get(symbol).await {
   Reply::Body(body)=>return Fetch::Body(body),
   Reply::Status(status,retry_after)=>{
    if binance_gate::note(status,retry_after.as_deref()) {return Fetch::Banned}
    return if status>=500 {Fetch::Retry} else {Fetch::Skip};
   }
   Reply::Transport=>{if attempt+1<TRANSPORT_TRIES {tokio::time::sleep(TRANSPORT_PAUSE).await}}
  }
 }
 Fetch::Retry
}

async fn upsert(pool:&PgPool,symbol:&str,bars:&[(NaiveDate,f64,f64)])->sqlx::Result<()> {
 let days:Vec<NaiveDate>=bars.iter().map(|b|b.0).collect();
 let closes:Vec<f64>=bars.iter().map(|b|b.1).collect();
 let volumes:Vec<f64>=bars.iter().map(|b|b.2).collect();
 // One statement for the contract's three weeks rather than twenty-one round
 // trips. Re-running the day leaves the same values in place, which is what
 // makes a retried sweep free of consequence.
 //
 // `IS DISTINCT FROM`（审查 A7）：已经收过的日子币安不会改，每天的扫描却要把三周
 // 都重写一遍。无条件的 DO UPDATE 每行都生成一个新元组、留一个死元组给 vacuum，
 // 几百个合约乘二十一天，天天如此；值没变就不写，只有币安真的改了口径那一天才更新。
 sqlx::query("INSERT INTO daily_close(symbol,day,close,quote_volume) \
  SELECT $1,d,c,q FROM UNNEST($2::date[],$3::double precision[],$4::double precision[]) AS t(d,c,q) \
  ON CONFLICT(symbol,day) DO UPDATE SET close=EXCLUDED.close,quote_volume=EXCLUDED.quote_volume \
  WHERE (daily_close.close,daily_close.quote_volume) IS DISTINCT FROM (EXCLUDED.close,EXCLUDED.quote_volume)")
  .bind(symbol).bind(&days).bind(&closes).bind(&volumes).execute(pool).await?;
 Ok(())
}

/// Retention. Rows older than a year go unconditionally; a contract that has
/// left `exchangeInfo` goes once its newest row is a month old, all of it at
/// once, so the table does not keep a stub of every delisting forever.
async fn prune(pool:&PgPool,live:&[String])->sqlx::Result<()> {
 let today=Utc::now().date_naive();
 sqlx::query("DELETE FROM daily_close WHERE day<$1").bind(window_day(today,RETENTION_DAYS)).execute(pool).await?;
 // An empty list would mean every contract is delisted. `collect` refuses to
 // get this far with one, and this is the second lock on that door.
 if live.is_empty() {return Ok(())}
 sqlx::query("DELETE FROM daily_close WHERE symbol IN \
  (SELECT symbol FROM daily_close WHERE symbol<>ALL($1::text[]) GROUP BY symbol HAVING max(day)<$2)")
  .bind(live).bind(window_day(today,DELISTED_GRACE_DAYS)).execute(pool).await?;
 Ok(())
}

/// 一轮收集的结果。
#[derive(Debug,Default,PartialEq)]
pub struct Collected {
 pub written:usize,
 pub skipped:usize,
 /// 上游或网络这一下没接住、写库失败的品种数。有就让这一轮按 `RETRY` 再来：
 /// 原来它们和 404 一起记成「跳过」、这一轮照样算成功，要等到明天 00:10 才再问，
 /// 新上市的合约因此白等一整天才有第一根历史。
 pub transient:usize,
 pub banned:bool,
}

/// Three weeks of candles for each contract in `targets`, upserted as they
/// arrive.
///
/// The list is given rather than derived so the caller can hand over only the
/// contracts that are actually short of history: one request a second means a
/// full list is a twelve minute sweep, and re-asking for the six hundred
/// contracts already stored would buy nothing.
///
/// 撞上封禁就停本轮，下一轮再来：接着往下走只会把几百个品种各自记成一次失败，
/// 同时把封禁越撞越久。
pub async fn collect(pool:&PgPool,targets:&[String])->Collected {
 let mut out=Collected::default();
 for symbol in targets {
  let body=match klines(&Binance,symbol).await {
   Fetch::Body(body)=>body,
   Fetch::Skip=>{tracing::warn!("Daily closes: {symbol} unavailable, skipped");out.skipped+=1;continue}
   Fetch::Retry=>{tracing::warn!("Daily closes: {symbol} did not answer, will retry");out.transient+=1;continue}
   Fetch::Banned=>{out.banned=true;return out}
  };
  // 新上市、还没有一根收完的日线：今天本来就没什么可存，不是失败。
  let bars=parse_daily_closes(&body,Utc::now().timestamp_millis());
  if bars.is_empty() {out.skipped+=1;continue}
  match upsert(pool,symbol,&bars).await {
   Ok(())=>out.written+=bars.len(),
   Err(e)=>{tracing::warn!("Daily closes: {symbol} not stored ({e})");out.transient+=1}
  }
 }
 out
}

/// Which contracts already have the newest day a finished sweep would have
/// written. Yesterday, because today's candle is still open and never stored.
async fn collected(pool:&PgPool,day:NaiveDate)->sqlx::Result<Vec<String>> {
 sqlx::query_scalar("SELECT symbol FROM daily_close WHERE day=$1").bind(day).fetch_all(pool).await
}

/// The contracts still owed a sweep: listed and trading, but without that day's
/// row. In `live` order, which is sorted.
///
/// This is what makes the job incremental. A restart in the middle of the
/// afternoon used to see one stored row for yesterday and conclude the whole
/// day was done, so a contract that was newly listed — or newly *readable*,
/// which is how the two hundred `TRADIFI_PERPETUAL` symbols arrived — waited
/// until the next 00:10 UTC for any history at all. Asking per contract instead
/// of per day closes that window without re-requesting what is already stored.
pub fn missing(live:&[String],have:&[String])->Vec<String> {
 let stored:HashSet<&str>=have.iter().map(String::as_str).collect();
 live.iter().filter(|s|!stored.contains(s.as_str())).cloned().collect()
}

/// One pass of the daily job: the contract list, the ones still owed a day,
/// their candles, then retention. Returns how many rows were written.
pub async fn sweep(pool:&PgPool)->anyhow::Result<usize> {
 let body=market_meta::exchange_info().await.map_err(|_|anyhow::anyhow!("exchangeInfo unavailable"))?;
 let symbols=perpetuals(&body);
 anyhow::ensure!(!symbols.is_empty(),"exchangeInfo listed no tradable perpetual");
 let yesterday=window_day(Utc::now().date_naive(),1);
 let targets=missing(&symbols,&collected(pool,yesterday).await?);
 let round=if targets.is_empty() {Collected::default()} else {collect(pool,&targets).await};
 prune(pool,&symbols).await?;
 tracing::info!("Daily closes: {} contracts, {} to collect, {} rows written, {} skipped, {} to retry",
  symbols.len(),targets.len(),round.written,round.skipped,round.transient);
 settle(&round)?;
 Ok(round.written)
}

/// 这一轮算不算完。算不完就让 `spawn_daily` 按 RETRY 再来一次——下一轮只问还缺的，
/// 已经写下的不会重问。
///
/// 被封禁打断：到时候要是封禁还在，第一个品种出站前就会被闸门拦住，代价是零。
/// 有品种没接住（5xx、断连、写库失败）：十分钟后再问它们，而不是等到明天。
fn settle(round:&Collected)->anyhow::Result<()> {
 anyhow::ensure!(!round.banned,"Binance is holding this egress; the round stopped early");
 anyhow::ensure!(round.transient==0,"{} contracts did not answer; asking them again shortly",round.transient);
 Ok(())
}

/// The daily job, started from `serve` beside `market_meta::spawn_refresh`.
/// It shares the process with the route so the cache it refreshes is the one
/// requests are answered from.
pub fn spawn_daily(pool:PgPool)->tokio::task::JoinHandle<()> {
 tokio::spawn(async move {
  loop {
   // Every pass asks what is missing first, so the one that runs at startup
   // costs nothing on a node that is already up to date and still picks up a
   // contract listed since the last sweep.
   let wait=match sweep(&pool).await {
    Ok(_)=>until_next_run(Utc::now()),
    Err(e)=>{tracing::warn!("Daily closes: collection will retry ({e})");RETRY}
   };
   if let Err(e)=rebuild(&pool,Utc::now().date_naive()).await {tracing::warn!("Daily closes: cache not refreshed ({e})")}
   tokio::time::sleep(wait).await;
  }
 })
}

// ------------------------------------------------------------------- handler

fn reply(status:StatusCode,body:Vec<u8>,cache:&'static str)->Response {
 (status,[(header::CONTENT_TYPE,"application/json"),(header::CACHE_CONTROL,cache)],body).into_response()
}

async fn sector_history(State(s):State<AppState>)->Response {
 let today=Utc::now().date_naive();
 let snapshot=match cached(today) {
  Some(snapshot)=>Some(snapshot),
  None=>match rebuild(&s.pool,today).await {
   Ok(fresh)=>Some(fresh),
   // Yesterday's snapshot is still five- and twenty-day history, and the phone
   // reads `asof` to see how old it is. Only a cold process with an
   // unreachable database has nothing at all to say.
   Err(e)=>{tracing::warn!("Sector history unavailable ({e})");stale()}
  }
 };
 match snapshot {
  Some(snapshot)=>reply(StatusCode::OK,snapshot.body.clone(),"public, max-age=3600"),
  None=>reply(StatusCode::SERVICE_UNAVAILABLE,
   serde_json::to_vec(&json!({"error":{"code":"temporarily_unavailable"}})).unwrap_or_default(),"no-store"),
 }
}

#[cfg(test)]
mod tests {
 use super::*;

 fn day(text:&str)->NaiveDate {NaiveDate::parse_from_str(text,"%Y-%m-%d").unwrap()}
 fn ms(text:&str)->i64 {day(text).and_hms_opt(0,0,0).unwrap().and_utc().timestamp_millis()}
 fn bar(date:&str,close:&str,volume:&str)->Value {
  json!([ms(date),"1","2","0",close,"10",ms(date)+86_399_999,volume,42,"5","5","0"])
 }

 #[test]
 fn only_trading_perpetuals_are_collected() {
  let body=json!({"symbols":[
   {"symbol":"BTCUSDT","contractType":"PERPETUAL","status":"TRADING"},
   {"symbol":"ETHUSDT","contractType":"PERPETUAL","status":"TRADING"},
   // The equities, ETFs and metals: a second perpetual flavour, and the whole
   // of the phone's "US" market. Collected like any other perpetual.
   {"symbol":"NVDAUSDT","contractType":"TRADIFI_PERPETUAL","status":"TRADING"},
   {"symbol":"XAUTUSDT","contractType":"TRADIFI_PERPETUAL","status":"BREAK"},
   // A quarterly: its history belongs to a contract that expires.
   {"symbol":"BTCUSDT_250926","contractType":"CURRENT_QUARTER","status":"TRADING"},
   {"symbol":"ETHUSDT_251226","contractType":"NEXT_QUARTER","status":"TRADING"},
   // Perpetual, but not open: no live price for the phone to divide.
   {"symbol":"LUNAUSDT","contractType":"PERPETUAL","status":"SETTLING"},
   {"symbol":"NEWUSDT","contractType":"PERPETUAL","status":"PENDING_TRADING"},
   {"symbol":"HALTUSDT","contractType":"PERPETUAL","status":"BREAK"},
   // Rows we cannot read are skipped rather than guessed at.
   {"contractType":"PERPETUAL","status":"TRADING"},
   {"symbol":"BAD/SYMBOL","contractType":"PERPETUAL","status":"TRADING"},
   {"symbol":"SOLUSDT","status":"TRADING"},
  ]});
  assert_eq!(perpetuals(&body),
   vec!["BTCUSDT".to_owned(),"ETHUSDT".to_owned(),"NVDAUSDT".to_owned()]);
  assert!(perpetuals(&json!({})).is_empty());
 }

 #[test]
 fn only_the_contracts_short_of_yesterday_are_asked_for() {
  let own=|names:&[&str]|names.iter().map(|s|(*s).to_owned()).collect::<Vec<String>>();
  let live=own(&["AAAUSDT","BBBUSDT","CCCUSDT","NVDAUSDT"]);
  // The everyday case: the sweep ran, one contract was newly listed since.
  assert_eq!(missing(&live,&own(&["AAAUSDT","BBBUSDT","CCCUSDT"])),own(&["NVDAUSDT"]));
  // Nothing stored for the day — a cold table, or the first run after
  // `perpetuals` learned a whole new contract type.
  assert_eq!(missing(&live,&[]),live);
  // Everything stored: no request at all, which is what makes the restart free.
  assert!(missing(&live,&live).is_empty());
  // A delisted contract still holding rows is not a contract to ask about.
  assert_eq!(missing(&own(&["AAAUSDT"]),&own(&["ZZZUSDT"])),own(&["AAAUSDT"]));
 }

 #[test]
 fn todays_unfinished_candle_is_dropped() {
  let body=json!([
   bar("2026-09-15","100.5","1000"),
   bar("2026-09-16","101.5","1100"),
   bar("2026-09-17","102.5","1200"),
   // 00:10 UTC on the 18th: this one closes tonight.
   bar("2026-09-18","103.5","7"),
  ]);
  let now=ms("2026-09-18")+600_000;
  let bars=parse_daily_closes(&body,now);
  assert_eq!(bars.len(),3,"the day in progress must not be stored");
  assert_eq!(bars[0],(day("2026-09-15"),100.5,1000.0));
  assert_eq!(bars[2].0,day("2026-09-17"));
  // A single candle is only the day in progress, so nothing is complete.
  assert!(parse_daily_closes(&json!([bar("2026-09-18","103.5","7")]),now).is_empty());
  assert!(parse_daily_closes(&json!([]),now).is_empty());
  assert!(parse_daily_closes(&json!({"code":-1121}),now).is_empty());
 }

 /// 上游还没长出今天那根时，最后一根就是昨天那根完整的——不能因为它排在最后就扔掉。
 #[test]
 fn a_finished_last_candle_is_kept() {
  let body=json!([bar("2026-09-16","101.5","1100"),bar("2026-09-17","102.5","1200")]);
  let bars=parse_daily_closes(&body,ms("2026-09-18")+600_000);
  assert_eq!(bars.iter().map(|b|b.0).collect::<Vec<_>>(),vec![day("2026-09-16"),day("2026-09-17")]);
  // 收盘时间读不出来的行不知道收没收完，不存。
  let unknown=json!([[ms("2026-09-16"),"1","2","0","101.5","10",null,"1100",1,"1","1","0"]]);
  assert!(parse_daily_closes(&unknown,ms("2026-09-18")).is_empty());
 }

 /// 午夜前后给昨天算的那次重建后完成，也不能把给今天算好的缓存换回去。
 #[test]
 fn an_older_rebuild_does_not_replace_a_newer_cache() {
  // 自己的一格，不碰进程里那份：别的测试要用它。
  let slot=RwLock::new(None);
  install_into(&slot,Arc::new(Snapshot{asof:day("2026-09-18"),body:b"today".to_vec()}));
  let late=install_into(&slot,Arc::new(Snapshot{asof:day("2026-09-17"),body:b"yesterday".to_vec()}));
  assert_eq!(late.body,b"yesterday","the caller still gets what it built");
  let kept=|slot:&RwLock<Option<Arc<Snapshot>>>|slot.read().unwrap().as_ref().map(|s|s.body.clone());
  assert_eq!(kept(&slot),Some(b"today".to_vec()));
  install_into(&slot,Arc::new(Snapshot{asof:day("2026-09-19"),body:b"tomorrow".to_vec()}));
  assert_eq!(kept(&slot),Some(b"tomorrow".to_vec()),"a newer day still replaces it");
 }

 /// 5xx 和断连是「过一会儿再问」，这一轮不算完；404 是这一只今天没有，这一轮照样算完。
 #[test]
 fn a_round_with_unanswered_contracts_is_retried_soon() {
  assert!(settle(&Collected{written:40,skipped:2,..Default::default()}).is_ok());
  assert!(settle(&Collected{written:40,transient:1,..Default::default()}).is_err());
  assert!(settle(&Collected{banned:true,..Default::default()}).is_err());
 }

 #[test]
 fn unreadable_rows_are_skipped_not_zeroed() {
  let body=json!([
   bar("2026-09-15","100.0","1000"),
   json!([ms("2026-09-16"),"1","2","0","not a number","10",0,"1200",1,"1","1","0"]),
   json!(["2026-09-17"]),
   bar("2026-09-18","0","1200"),
   bar("2026-09-19","105.0","1300"),
   bar("2026-09-20","106.0","1400"),
  ]);
  let bars=parse_daily_closes(&body,ms("2026-09-20")+600_000);
  assert_eq!(bars,vec![(day("2026-09-15"),100.0,1000.0),(day("2026-09-19"),105.0,1300.0)]);
 }

 #[test]
 fn window_days_are_calendar_days() {
  // Plain case.
  assert_eq!(window_day(day("2026-09-18"),5),day("2026-09-13"));
  assert_eq!(window_day(day("2026-09-18"),20),day("2026-08-29"));
  // Across a month boundary, and across one with thirty-one days.
  assert_eq!(window_day(day("2026-09-03"),5),day("2026-08-29"));
  assert_eq!(window_day(day("2026-11-05"),20),day("2026-10-16"));
  // Across a year boundary.
  assert_eq!(window_day(day("2027-01-03"),5),day("2026-12-29"));
  assert_eq!(window_day(day("2027-01-10"),20),day("2026-12-21"));
  // February in a leap year: the twenty-ninth exists and must be counted.
  assert_eq!(window_day(day("2028-03-04"),5),day("2028-02-28"));
  assert_eq!(window_day(day("2028-03-01"),1),day("2028-02-29"));
  assert_eq!(window_day(day("2028-03-10"),20),day("2028-02-19"));
  // The same dates in a common year land one day later in February.
  assert_eq!(window_day(day("2026-03-04"),5),day("2026-02-27"));
  assert_eq!(window_day(day("2026-03-01"),1),day("2026-02-28"));
  // A leap day is a legal `asof` of its own.
  assert_eq!(window_day(day("2028-02-29"),5),day("2028-02-24"));
  assert_eq!(window_day(day("2028-02-29"),20),day("2028-02-09"));
 }

 #[test]
 fn the_next_run_is_the_next_ten_past_midnight() {
  let at=|text:&str|DateTime::parse_from_rfc3339(text).unwrap().with_timezone(&Utc);
  assert_eq!(until_next_run(at("2026-09-18T00:00:00Z")),Duration::from_secs(600));
  // A sweep that ran long waits for tomorrow instead of starting again.
  assert_eq!(until_next_run(at("2026-09-18T00:22:00Z")),Duration::from_secs(23*3600+48*60));
  assert_eq!(until_next_run(at("2026-09-18T23:00:00Z")),Duration::from_secs(70*60));
  // Exactly on the minute counts as done, not as due.
  assert_eq!(until_next_run(at("2026-09-18T00:10:00Z")),Duration::from_secs(24*3600));
 }

 #[test]
 fn the_payload_omits_what_it_does_not_have() {
  let asof=day("2026-09-18");
  let rows=vec![
   ("BTCUSDT".to_owned(),day("2026-09-13"),61234.5),
   ("BTCUSDT".to_owned(),day("2026-08-29"),58900.1),
   // Listed nine days ago: five days of history, not twenty.
   ("NEWUSDT".to_owned(),day("2026-09-13"),1.25),
   // Twenty days of history but no candle at the five-day mark.
   ("GAPUSDT".to_owned(),day("2026-08-29"),9.5),
   // Neither window: the symbol itself is left out.
   ("OLDUSDT".to_owned(),day("2026-09-01"),3.0),
  ];
  let body=payload(asof,&rows);
  assert_eq!(body["asof"],json!("2026-09-18"));
  assert_eq!(body["symbols"]["BTCUSDT"],json!({"c5":61234.5,"c20":58900.1}));
  assert_eq!(body["symbols"]["NEWUSDT"],json!({"c5":1.25}));
  assert!(body["symbols"]["NEWUSDT"].get("c20").is_none(),"a missing close is absent, never zero");
  assert_eq!(body["symbols"]["GAPUSDT"],json!({"c20":9.5}));
  assert!(body["symbols"].get("OLDUSDT").is_none());
  assert_eq!(body["symbols"].as_object().unwrap().len(),3);
  // A cold table answers with the day and an empty market, not with an error.
  assert_eq!(payload(asof,&[]),json!({"asof":"2026-09-18","symbols":{}}));
 }

 /// The isolated database `ops/test.py` builds, or nothing.
 ///
 /// The assertions below are about what PostgreSQL does — the primary key, the
 /// `ON CONFLICT` rewrite, the retention deletes — so they cannot be faked, and
 /// they only run where a throwaway database is offered. Plain `cargo test`
 /// skips them rather than failing, and nothing here may reach a database that
 /// is not on this machine.
 async fn isolated_pool()->Option<PgPool> {
  let (Ok(admin),Ok(url),Ok(role))=(std::env::var("KANPAN_TEST_ADMIN_URL"),std::env::var("KANPAN_TEST_DATABASE_URL"),std::env::var("KANPAN_TEST_ROLE")) else {
   eprintln!("Skipping the daily_close database assertions: run ops/test.py for an isolated PostgreSQL");
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
 async fn the_table_takes_a_repeated_sweep_without_growing_or_drifting() {
  let Some(pool)=isolated_pool().await else {return};
  sqlx::query("DELETE FROM daily_close").execute(&pool).await.unwrap();
  let rows=|pool:PgPool|async move{sqlx::query_scalar::<_,i64>("SELECT count(*) FROM daily_close").fetch_one(&pool).await.unwrap()};
  let asof=Utc::now().date_naive();
  let (five,twenty)=(window_day(asof,5),window_day(asof,20));
  let bars=vec![(twenty,100.0,1.0),(five,200.0,2.0),(window_day(asof,1),300.0,3.0)];
  upsert(&pool,"AAAUSDT",&bars).await.unwrap();
  assert_eq!(rows(pool.clone()).await,3);
  // The sweep that retried, or simply ran twice: the same three rows — and the
  // same tuples. `xmin` changes only when a row is rewritten, so an unchanged
  // `xmin` is the proof the repeated sweep wrote nothing.
  let versions=|pool:PgPool|async move{sqlx::query_scalar::<_,String>("SELECT string_agg(xmin::text,',' ORDER BY day) FROM daily_close WHERE symbol='AAAUSDT'").fetch_one(&pool).await.unwrap()};
  let before=versions(pool.clone()).await;
  upsert(&pool,"AAAUSDT",&bars).await.unwrap();
  assert_eq!(rows(pool.clone()).await,3,"a repeated sweep must not duplicate a day");
  assert_eq!(versions(pool.clone()).await,before,"unchanged days are not rewritten");
  // A day Binance restates is corrected in place, not appended beside itself.
  upsert(&pool,"AAAUSDT",&[(five,222.0,2.5)]).await.unwrap();
  assert_ne!(versions(pool.clone()).await,before,"a restated day is rewritten");
  assert_eq!(rows(pool.clone()).await,3);
  let (close,volume):(f64,f64)=sqlx::query_as("SELECT close,quote_volume FROM daily_close WHERE symbol='AAAUSDT' AND day=$1")
   .bind(five).fetch_one(&pool).await.unwrap();
  assert_eq!((close,volume),(222.0,2.5));

  // A contract with only part of the history gets only the field it has.
  upsert(&pool,"BBBUSDT",&[(five,9.0,1.0)]).await.unwrap();
  let snapshot=rebuild(&pool,asof).await.unwrap();
  let body:Value=serde_json::from_slice(&snapshot.body).unwrap();
  assert_eq!(body["data"]["asof"],json!(asof.to_string()));
  assert_eq!(body["data"]["symbols"]["AAAUSDT"],json!({"c5":222.0,"c20":100.0}));
  assert_eq!(body["data"]["symbols"]["BBBUSDT"],json!({"c5":9.0}));
  // Yesterday's close is stored, but no window starts there, so it is not served.
  assert_eq!(body["data"]["symbols"].as_object().unwrap().len(),2);

  // Retention: a year old goes whatever its listing, a delisted contract keeps
  // its history for a month, and a listed one is never touched.
  upsert(&pool,"OLDUSDT",&[(window_day(asof,400),1.0,1.0),(window_day(asof,40),2.0,1.0)]).await.unwrap();
  upsert(&pool,"GONEUSDT",&[(window_day(asof,3),4.0,1.0)]).await.unwrap();
  prune(&pool,&["AAAUSDT".to_owned(),"BBBUSDT".to_owned()]).await.unwrap();
  let held=|pool:PgPool,symbol:&'static str,day:NaiveDate|async move{
   sqlx::query_scalar::<_,bool>("SELECT EXISTS(SELECT 1 FROM daily_close WHERE symbol=$1 AND day=$2)")
    .bind(symbol).bind(day).fetch_one(&pool).await.unwrap()
  };
  assert!(!held(pool.clone(),"OLDUSDT",window_day(asof,400)).await,"past a year");
  assert!(!held(pool.clone(),"OLDUSDT",window_day(asof,40)).await,"delisted over a month ago");
  assert!(held(pool.clone(),"GONEUSDT",window_day(asof,3)).await,"delisted three days ago, still held");
  assert!(held(pool.clone(),"AAAUSDT",five).await,"a listed contract is never pruned");

  // The route itself: no token, the envelope the account API writes, and an
  // hour of caching.
  use axum::{body::Body,http::Request};
  use http_body_util::BodyExt;
  use tower::ServiceExt;
  let secrets=Arc::new(crate::crypto::Secrets{pepper:vec![31;32],encryption:[43;32]});
  let dummy_hash=Arc::new(secrets.hash_password("dummy123456").unwrap());
  let app=crate::router(AppState{pool:pool.clone(),secrets,dummy_hash});
  let reply=app.oneshot(Request::builder().uri("/v1/market/sector-history").body(Body::empty()).unwrap()).await.unwrap();
  assert_eq!(reply.status(),StatusCode::OK);
  assert_eq!(reply.headers()[header::CACHE_CONTROL],"public, max-age=3600");
  let served:Value=serde_json::from_slice(&reply.into_body().collect().await.unwrap().to_bytes()).unwrap();
  assert_eq!(served["data"]["symbols"]["AAAUSDT"]["c5"],json!(222.0));
  sqlx::query("DELETE FROM daily_close").execute(&pool).await.unwrap();
 }

 #[test]
 fn the_payload_windows_move_with_asof() {
  // The same row is the five-day close on one day and nothing on the next.
  let rows=vec![("BTCUSDT".to_owned(),day("2026-09-13"),61234.5)];
  assert_eq!(payload(day("2026-09-18"),&rows)["symbols"]["BTCUSDT"],json!({"c5":61234.5}));
  assert!(payload(day("2026-09-19"),&rows)["symbols"].as_object().unwrap().is_empty());
  assert_eq!(payload(day("2026-10-03"),&rows)["symbols"]["BTCUSDT"],json!({"c20":61234.5}));
 }

 /// 只会拒绝的上游，记下被问过几次。
 struct Refusing {status:u16,retry_after:Option<String>,asked:std::sync::atomic::AtomicUsize}
 impl Klines for Refusing {
  fn get<'a>(&'a self,_symbol:&'a str)->Pin<Box<dyn Future<Output=Reply>+Send+'a>> {
   self.asked.fetch_add(1,std::sync::atomic::Ordering::Relaxed);
   let (status,retry_after)=(self.status,self.retry_after.clone());
   Box::pin(async move {Reply::Status(status,retry_after)})
  }
 }

 /// A-T17：两个品种都撞上 418，第二个不得把截止时间重置，也不得绕过它出站。
 ///
 /// 旧代码每个品种各自从 2 秒起退避四次，于是「换个品种」就等于「把退避忘了」——
 /// 七百个品种就是七百次往同一道墙上撞，418 只会越滚越长。
 // 跨 await 持有是故意的：这把锁就是「同时只许一条测试碰那道进程级闸门」的实现。
 #[allow(clippy::await_holding_lock)]
 #[tokio::test(start_paused=true)]
 async fn a_second_contract_neither_resets_nor_slips_past_the_ban() {
  let _guard=binance_gate::test_lock().lock().unwrap();
  binance_gate::clear();
  let source=Refusing{status:418,retry_after:None,asked:std::sync::atomic::AtomicUsize::new(0)};

  // 第一个品种：出站一次，撞上 418，本轮到此为止。
  assert!(matches!(klines(&source,"AAAUSDT").await,Fetch::Banned));
  assert_eq!(source.asked.load(std::sync::atomic::Ordering::Relaxed),1);
  let first=binance_gate::wait().expect("418 must hold this egress");
  assert!(first>Duration::from_secs(119),"headerless 418 starts at two minutes, got {first:?}");

  // 第二个品种：连出站都不该发生，闸门直接把它拦下。
  tokio::time::advance(Duration::from_secs(30)).await;
  assert!(matches!(klines(&source,"BBBUSDT").await,Fetch::Banned));
  assert_eq!(source.asked.load(std::sync::atomic::Ordering::Relaxed),1,
   "the second contract must not go out while the egress is held");
  let left=binance_gate::wait().expect("still held");
  assert!(left<first,"the deadline must keep counting down, not restart: {first:?} -> {left:?}");

  // 传输层失败要重试的那条路也一样过闸门：闸门按下时它一次都不出站。原来的守卫在
  // 循环外面，重试的那一下是绕过去的。
  struct Broken {asked:std::sync::atomic::AtomicUsize}
  impl Klines for Broken {
   fn get<'a>(&'a self,_symbol:&'a str)->Pin<Box<dyn Future<Output=Reply>+Send+'a>> {
    self.asked.fetch_add(1,std::sync::atomic::Ordering::Relaxed);
    Box::pin(async {Reply::Transport})
   }
  }
  let broken=Broken{asked:std::sync::atomic::AtomicUsize::new(0)};
  assert!(matches!(klines(&broken,"DDDUSDT").await,Fetch::Banned));
  assert_eq!(broken.asked.load(std::sync::atomic::Ordering::Relaxed),0,
   "the gate is checked before every attempt, retries included");

  // 截止时间过了才重新放行；这一次又被拒，于是又是一轮完整的封禁。
  tokio::time::advance(Duration::from_secs(120)).await;
  assert!(binance_gate::wait().is_none());
  assert!(matches!(klines(&source,"CCCUSDT").await,Fetch::Banned));
  assert_eq!(source.asked.load(std::sync::atomic::Ordering::Relaxed),2);
  binance_gate::clear();
 }

 /// 429 带 Retry-After 就按它说的等；别的状态码只是这一个品种今天没有。
 // 跨 await 持有是故意的：这把锁就是「同时只许一条测试碰那道进程级闸门」的实现。
 #[allow(clippy::await_holding_lock)]
 #[tokio::test(start_paused=true)]
 async fn a_told_wait_is_believed_and_other_failures_are_just_one_contract() {
  let _guard=binance_gate::test_lock().lock().unwrap();
  binance_gate::clear();
  let told=Refusing{status:429,retry_after:Some("45".to_owned()),asked:std::sync::atomic::AtomicUsize::new(0)};
  assert!(matches!(klines(&told,"AAAUSDT").await,Fetch::Banned));
  let left=binance_gate::wait().expect("429 holds the egress too");
  assert!(left>Duration::from_secs(44)&&left<=Duration::from_secs(45),"got {left:?}");
  binance_gate::clear();

  let missing=Refusing{status:404,retry_after:None,asked:std::sync::atomic::AtomicUsize::new(0)};
  assert!(matches!(klines(&missing,"GONEUSDT").await,Fetch::Skip));
  assert!(binance_gate::wait().is_none(),"a 404 is not a ban");
  let down=Refusing{status:503,retry_after:None,asked:std::sync::atomic::AtomicUsize::new(0)};
  assert!(matches!(klines(&down,"BUSYUSDT").await,Fetch::Retry),"a 5xx is worth asking again today");
  binance_gate::clear();
 }
}
