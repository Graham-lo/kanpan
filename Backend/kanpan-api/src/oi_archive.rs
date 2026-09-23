//! Historical open interest, served from Binance's daily metrics archive.
//!
//! Binance's REST endpoint only answers for the last thirty days. Everything
//! older lives on `data.binance.vision` as one zip per symbol per day — about
//! 11.5 KB holding 288 five-minute observations — so a year of chart is 365
//! small downloads. The whole cost of this endpoint is latency, not work:
//! measured from the market VPS a day costs 0.42 s to arrive and 7 ms to parse.
//!
//! That is why the Python gateway this replaces took 54 s to answer a cold year
//! and why the phone showed “持仓量加载中” for most of a minute: it read the days
//! four at a time, on a connection it opened and closed for each one. Here they
//! go out sixteen at a time over one keep-alive client, every parsed day is kept
//! on disk — with all four ratio columns in versioned metrics slices — and the days a chart just touched stay
//! parsed in memory. A symbol the user looked at is then filled in the
//! background, all the way back to 2020, so the second look costs nothing.
//!
//! Nothing here is personal: no authentication, no database, no per-user state.
use axum::{Router,extract::{Path,Query},http::{StatusCode,header},response::{IntoResponse,Response},routing::get};
use crate::binance_gate;
use chrono::{DateTime,Datelike,NaiveDate,NaiveDateTime,Utc};
use std::collections::{HashMap,HashSet,VecDeque};
use std::future::Future;
use std::io::Read;
use std::path::PathBuf;
use std::pin::Pin;
use std::sync::{Arc,Mutex,OnceLock,atomic::{AtomicI64,AtomicU32,AtomicU64,Ordering}};
use std::time::{Duration,SystemTime};
use tokio::sync::Semaphore;

const ARCHIVE:&str="https://data.binance.vision/data/futures/um/daily/metrics/";
const DAY:i64=86_400_000;
/// The first day the archive holds anything at all; earlier dates are 404 for
/// every symbol, and each symbol is 404 until its own listing day.
const EPOCH:i64=1_598_918_400_000; // 2020-09-01 UTC
/// Days in flight for one range request. Sixteen is where the measured curve
/// flattens: 32 days cost 3.33 s at four lanes, 1.62 s at eight with keep-alive,
/// 1.37 s at sixteen — past that the archive, not the link, is the limit.
const LANES:usize=16;
/// Background filling runs narrower than a request the user is waiting on.
const PREFETCH_LANES:usize=4;
/// The gate every download passes, so a backfill cannot take the whole host.
const GATE:usize=24;
/// Parsed days held in memory. A day is ~4.6 KB of pairs, so this is ~19 MB —
/// worth it because it makes a repeated year of chart answer without touching
/// the disk at all.
const MEM_DAYS:usize=4096;
/// Disk cache ceiling. One symbol's whole archive is ~16 MB, the twenty symbols
/// anyone here looks at are ~320 MB, and the host has 121 GB free: the point of
/// the ceiling is that the directory cannot grow without bound, not thrift.
const DEFAULT_LIMIT:u64=4*1024*1024*1024;
/// 目录条目上限。
///
/// 字节预算只数字节，而缺口标记是 0 字节的空文件：上市日之前的那些天，一个合约能
/// 写出上千个标记，528 个合约就是几十万个——`disk.bytes` 一动不动，ext4 的目录项和
/// inode 却是实打实被占掉的，`read_dir` 启动扫描也跟着变慢。所以再加一条只数条目的
/// 上限。二十万是这么来的：真按最费的用法算，开机预热是 528 个合约 × 180 天 ≈ 9.5 万
/// 条，加上有人真的看过的二十来个品种的全量历史（每个 ~2200 天）≈ 4.4 万条，合起来
/// 还不到十四万；二十万在这之上留了余量，又远在单目录塌掉的量级之下。
const MAX_FILES:usize=200_000;
/// 一轮里连着这么多次被拒，就不再往前翻日期了。
///
/// 一次尝试算一次，`download` 一天最多试两次，所以这条线大约是「连着两天都没抓到」。
const REFUSALS:u32=3;
/// 被拒到上面那条线之后，这个源歇多久。
///
/// 403 / 超时 / 5xx 说的是「这会儿这个源不理这台机器」，不是「这一天没有数据」。
/// 不歇的话，一次预热会拿同一个拒绝把 528 × 180 天全撞一遍，每天两次尝试；歇太久
/// 又会让一次偶发的边缘故障把整段历史推迟到几十分钟以后。五分钟够让边缘节点换一台，
/// 也短到一次图表请求的重试就能自己恢复。
const SOURCE_COOLDOWN:i64=5*60_000;
/// A day that has just ended may not be published yet, so its absence is not
/// yet evidence of anything and must not be remembered as a gap.
const SETTLED:i64=2*DAY;
/// 还没到结算期的那些天，一次 404 只记这么久。
///
/// 记一下是必须的：一张图要的是十几到几百天，要是每一天的 404 都当场再去问一次
/// 上游，刚打开的那张图会被拖成同样多次网络往返。但它同样不能永久——归档比实际
/// 晚发布几分钟到几小时是常事，一旦把这种 404 永久记进内存，这个进程就只有等它
/// 被 FIFO 挤出去、或者等到重启，才会再看一眼，在那之前用户图上最近这一天一直缺着。
const RECENT_ABSENT_TTL:i64=10*60_000;
/// How far back the boot warm-up fills every listed contract. A first look at a
/// symbol nobody has opened on this host costs 4.6 s for a year, measured, and
/// that cost lands on the one person unlucky enough to open it first.
const WARM_DAYS:i64=180;
/// The warm-up runs narrower than even a background backfill: it is speculative
/// work for a user who has not arrived, and it must never be what someone waits
/// behind. Three symbols at a time, a breath between days.
const WARM_LANES:usize=3;
const WARM_PAUSE:Duration=Duration::from_millis(60);
/// The contract list, and the volume that decides what gets warmed first.
/// `fapi.binance.com` answers 451 from this datacentre; `www.binance.com/fapi`
/// answers 200 — same data, different edge, which is why the host here is not
/// the documented one.
const LISTING:&str="https://www.binance.com/fapi/v1/exchangeInfo";
const TICKER:&str="https://www.binance.com/fapi/v1/ticker/24hr";

/// Generic over the state because these routes never read it: the standby
/// gateway serves open interest with no database behind it at all.
pub fn routes<S:Clone+Send+Sync+'static>()->Router<S> {
 // One route rather than a static `/range` beside a dynamic `/{day}.json`:
 // the two shapes differ only in the last segment, and dispatching here keeps
 // the router free of sibling rules whose precedence would have to be trusted.
 Router::new().route("/oi/v1/metrics/{symbol}/{tail}",get(metrics))
}

/// Warm the disk index at startup so the first request does not pay for the
/// directory scan.
/// Open the store, then fill the recent window of every listed contract while
/// nobody is waiting.
///
/// Without this the archive is only ever warmed by someone paying for it: the
/// first person to open a symbol here waits the full cold path, and does so
/// again for the next symbol. The work is bounded (180 days of 528 contracts is
/// ~700 MB against a 4 GB ceiling), ordered by turnover so the symbols anyone
/// is likely to open come first, and skipped entirely for days already on disk —
/// so a restart resumes rather than repeats. `KANPAN_OI_WARM_DAYS=0` turns it off.
pub fn spawn_warm()->tokio::task::JoinHandle<()> {
 tokio::spawn(async {
  let store=store().await;
  let days=std::env::var("KANPAN_OI_WARM_DAYS").ok().and_then(|v|v.parse().ok()).unwrap_or(WARM_DAYS);
  if days<=0 {return}
  let Some(symbols)=perpetuals(&store.client).await else {
   tracing::warn!("Open interest warm-up skipped: the contract list could not be read");
   return;
  };
  tracing::info!("Open interest warm-up: {} contracts, {days} days",symbols.len());
  store.warm(symbols,days).await;
 })
}

/// The USDT perpetuals that are actually trading, busiest first.
///
/// The order is the whole point of the second request: warming alphabetically
/// would spend the first hour on contracts nobody here has ever opened.
async fn perpetuals(client:&reqwest::Client)->Option<Vec<Arc<str>>> {
 // 合约列表和 24h 榜单都在 binance.com 上，跟 `market_meta`、`sector_history` 撞的是
 // 同一道按 IP 算的限速墙，所以走同一条封禁截止时间：被封期间这轮预热直接不开。
 if binance_gate::blocked() {return None}
 let reply=client.get(LISTING).send().await.ok()?;
 if binance_gate::note_reply(&reply) {return None}
 let listing:serde_json::Value=reply.json().await.ok()?;
 let mut symbols:Vec<&str>=listing.get("symbols")?.as_array()?.iter()
  // 「正在交易的永续」和板块历史用同一个判定（`instruments::is_live_perpetual`）：以前这里只认
  // `PERPETUAL`，美股、贵金属那些 `TRADIFI_PERPETUAL` 板块历史里有、预热里没有。
  // 只留 USDT 计价是这里自己的取舍：USDC / USD1 那几只是同一个标的的双胞胎，预热是替
  // 还没来的人做的投机性工作，双胞胎各热一遍只是把币安的权重花两次。
  .filter(|row|crate::instruments::is_live_perpetual(row)&&row.get("quoteAsset").and_then(serde_json::Value::as_str)==Some("USDT"))
  .filter_map(|row|row.get("symbol").and_then(serde_json::Value::as_str))
  .collect();
 symbols.sort_unstable();
 symbols.dedup();
 // Turnover is a nicety: without it the list is still correct, just ordered badly.
 let mut turnover:HashMap<&str,f64>=HashMap::new();
 let ticker:Option<serde_json::Value>=if binance_gate::blocked() {None} else {
  match client.get(TICKER).send().await {
   Ok(reply)=>{if binance_gate::note_reply(&reply) {None} else {reply.json().await.ok()}}
   Err(_)=>None,
  }
 };
 if let Some(rows)=ticker.as_ref().and_then(serde_json::Value::as_array) {
  for row in rows {
   let (Some(symbol),Some(volume))=(row.get("symbol").and_then(serde_json::Value::as_str),
                                    row.get("quoteVolume").and_then(serde_json::Value::as_str))
    else {continue};
   if let Some(symbol)=symbols.iter().find(|s|**s==symbol) {
    turnover.insert(symbol,volume.parse().unwrap_or(0.0));
   }
  }
 }
 symbols.sort_by(|a,b|turnover.get(b).unwrap_or(&0.0).total_cmp(turnover.get(a).unwrap_or(&0.0)));
 Some(symbols.into_iter().map(Arc::from).collect())
}

// ---------------------------------------------------------------- the routes

async fn metrics(Path((symbol,tail)):Path<(String,String)>,Query(query):Query<HashMap<String,String>>)->Response {
 // The symbol becomes a file name, so it is checked before anything else and
 // against a whitelist, not against a list of things to reject.
 if !(1..=30).contains(&symbol.len())||!symbol.bytes().all(|b|b.is_ascii_uppercase()||b.is_ascii_digit()||b==b'_') {
  return fail(StatusCode::BAD_REQUEST,"invalid symbol");
 }
 if tail=="range" {range(&symbol,&query).await} else {single(&symbol,&tail,query.get("metrics").is_some_and(|v|v=="1")).await}
}

/// `GET /oi/v1/metrics/{symbol}/range?interval=&from=&to=` — the archive days
/// covering `[from,to]`, aggregated to one value per chart bucket.
async fn range(symbol:&str,query:&HashMap<String,String>)->Response {
 let Some(interval)=query.get("interval").map(String::as_str) else {return fail(StatusCode::BAD_REQUEST,"invalid historical range")};
 let (Some(step),Some(from),Some(to))=(step(interval),number(query.get("from")),number(query.get("to")))
  else {return fail(StatusCode::BAD_REQUEST,"invalid historical range")};
 let now=Utc::now().timestamp_millis();
 if !(EPOCH<=from&&from<=to&&to<now) {return fail(StatusCode::BAD_REQUEST,"invalid historical range")}
 // Refuse what no chart can show: a request must stay under ten years and
 // under twenty thousand buckets of its own interval.
 if to-from>(3660*DAY).min(20_000*step.max(300_000)) {return fail(StatusCode::BAD_REQUEST,"invalid historical range")}
 let (first,last)=(from.div_euclid(DAY),to.div_euclid(DAY).min(now.div_euclid(DAY)-1));
 let metrics=query.get("metrics").is_some_and(|v|v=="1");
 if last<first {return series(Vec::new(),metrics)}

 let store=store().await;
 let symbol:Arc<str>=Arc::from(symbol);
 // Bucket -> the latest observation inside it. Open interest is a level, not a
 // flow: a bucket takes its last value and never a sum. The archive's rows are
 // not in time order, so the time is kept alongside to decide "latest".
 let mut buckets:HashMap<i64,MetricRow>=HashMap::new();
 let mut tasks=tokio::task::JoinSet::new();
 let (mut next,mut live,mut lost)=(first,0usize,0usize);
 loop {
  while live<LANES&&next<=last {
   let (store,symbol,day)=(store.clone(),symbol.clone(),next);
   next+=1; live+=1;
   tasks.spawn(async move {store.day(&symbol,day).await.0});
  }
  let Some(done)=tasks.join_next().await else {break};
  live-=1;
  match done {
   Ok(Ok(Day::Points(points)))=>for &row in points.iter() {
    let time=row.0;
    if from<=time&&time<=to {
     let slot=buckets.entry(bucket(time,interval)).or_insert(row);
     if time>=slot.0 {*slot=row;}
    }
   },
   Ok(Ok(Day::Absent))=>{}                       // a gap stays a gap; never invent a value
   Ok(Err(()))|Err(_)=>lost+=1,
  }
 }
 // A day or two lost to the archive looks like the gaps the data already has,
 // and the phone can draw around it. More than that is not a chart, and it
 // must not be handed out with an hour of cache lifetime on it.
 if lost>2 {return fail(StatusCode::BAD_GATEWAY,"archive unavailable")}

 let mut rows:Vec<MetricRow>=buckets.into_iter().map(|(bucket,mut row)|{row.0=bucket;row}).collect();
 rows.sort_unstable_by_key(|row|row.0);
 // The user has shown interest in this symbol; fill the rest of its archive
 // while nobody is waiting, so the next zoom out is already on disk.
 store.spawn_prefetch(symbol);
 series(rows,metrics)
}

/// `GET /oi/v1/metrics/{symbol}/{YYYY-MM-DD}.json` — one raw day, the fallback
/// the phone uses when it has to aggregate locally.
async fn single(symbol:&str,tail:&str,metrics:bool)->Response {
 let Some(date)=tail.strip_suffix(".json").and_then(|d|NaiveDate::parse_from_str(d,"%Y-%m-%d").ok())
  else {return fail(StatusCode::NOT_FOUND,"not found")};
 let day=date.and_hms_opt(0,0,0).map(|t|t.and_utc().timestamp_millis()).unwrap_or(0).div_euclid(DAY);
 let now=Utc::now().timestamp_millis();
 if day*DAY<EPOCH||day>=now.div_euclid(DAY) {return fail(StatusCode::NOT_FOUND,"no archive for date")}
 match store().await.day(symbol,day).await {
  (Ok(Day::Points(points)),hit)=>{
   let mut response=body(StatusCode::OK,encode_rows(&points,metrics),"public, max-age=86400");
   response.headers_mut().insert("X-OI-Cache",header::HeaderValue::from_static(if hit {"HIT"} else {"MISS"}));
   response
  }
  (Ok(Day::Absent),_)=>fail(StatusCode::NOT_FOUND,"no archive for date"),
  (Err(()),_)=>fail(StatusCode::BAD_GATEWAY,"archive unavailable"),
 }
}

// ------------------------------------------------------------------ replies

/// The phone decodes a bare `[[ms,value],…]`; these routes predate the
/// `{"data":…}` envelope the account API uses and keep their own shape.
fn encode_rows(rows:&[MetricRow],metrics:bool)->Vec<u8> {
 if metrics {serde_json::to_vec(rows)} else {serde_json::to_vec(&rows.iter().map(|r|(r.0,r.1)).collect::<Vec<_>>())}
  .unwrap_or_else(|_|b"[]".to_vec())
}
fn series(rows:Vec<MetricRow>,metrics:bool)->Response {
 body(StatusCode::OK,encode_rows(&rows,metrics),"public, max-age=3600")
}
fn fail(status:StatusCode,message:&str)->Response {
 body(status,serde_json::to_vec(&serde_json::json!({"error":message})).unwrap_or_default(),"no-store")
}
fn body(status:StatusCode,payload:Vec<u8>,cache:&'static str)->Response {
 (status,[(header::CONTENT_TYPE,"application/json"),(header::CACHE_CONTROL,cache)],payload).into_response()
}

fn number(value:Option<&String>)->Option<i64> {value.and_then(|v|v.parse().ok())}

// -------------------------------------------------------------- the calendar

/// Chart step in milliseconds. `1M` and `1y` are nominal here, as they are on
/// the phone: the bucket itself is found by the calendar, not by division.
pub fn step(interval:&str)->Option<i64> {
 Some(match interval {
  "1m"=>60_000,"3m"=>180_000,"5m"=>300_000,"15m"=>900_000,"30m"=>1_800_000,
  "1h"=>3_600_000,"2h"=>7_200_000,"4h"=>14_400_000,"6h"=>21_600_000,"12h"=>43_200_000,
  "1d"=>DAY,"1w"=>7*DAY,"1M"=>30*DAY,"1y"=>365*DAY,_=>return None})
}

/// The bucket an observation belongs to.
///
/// `1m` and `3m` are finer than the archive's own five-minute cadence, so an
/// observation keeps its own timestamp rather than being moved onto a bucket
/// the source never measured. Weeks start Monday (the epoch was a Thursday),
/// months and years start on the calendar.
pub fn bucket(time:i64,interval:&str)->i64 {
 match interval {
  "1m"|"3m"=>time,
  "1w"=>(time-4*DAY).div_euclid(7*DAY)*(7*DAY)+4*DAY,
  "1M"|"1y"=>{
   let Some(date)=DateTime::from_timestamp_millis(time) else {return time};
   let date=date.naive_utc().date();
   NaiveDate::from_ymd_opt(date.year(),if interval=="1y" {1} else {date.month()},1)
    .and_then(|d|d.and_hms_opt(0,0,0)).map(|d|d.and_utc().timestamp_millis()).unwrap_or(time)
  }
  _=>{let step=step(interval).unwrap_or(DAY);time.div_euclid(step)*step}
 }
}

fn day_name(day:i64)->String {
 DateTime::from_timestamp(day*86_400,0).map(|d|d.format("%Y-%m-%d").to_string()).unwrap_or_default()
}

// ------------------------------------------------------------------ the zip

/// Timestamp, open interest, top-account ratio, top-position ratio, account ratio, taker ratio.
type MetricRow=(i64,f64,Option<f64>,Option<f64>,Option<f64>,Option<f64>);

/// One day of observations, or the knowledge that the archive has none.
#[derive(Clone)]
enum Day {Points(Arc<Vec<MetricRow>>),Absent}

/// Read `sum_open_interest` out of a metrics zip.
///
/// Rows and fields that cannot be read are skipped rather than failing the day:
/// this is an undocumented dump whose columns have changed before, and a day
/// short a few rows is still a usable day. Duplicated timestamps keep the last
/// row, as the gateway did.
fn parse(data:&[u8])->Result<Vec<MetricRow>,()> {
 let mut archive=zip::ZipArchive::new(std::io::Cursor::new(data)).map_err(|_|())?;
 let mut points:HashMap<i64,MetricRow>=HashMap::new();
 for index in 0..archive.len() {
  let mut entry=archive.by_index(index).map_err(|_|())?;
  if !entry.name().ends_with(".csv") {continue}
  if entry.size()>20*1024*1024 {return Err(())}
  let mut text=String::new();
  entry.read_to_string(&mut text).map_err(|_|())?;
  let mut lines=text.lines();
  let Some(header)=lines.next() else {continue};
  let header=header.trim_start_matches('\u{feff}');
  let column=|name:&str|header.split(',').position(|c|c.trim()==name);
  let (Some(at),Some(value))=(column("create_time"),column("sum_open_interest")) else {continue};
  let ratios=[column("count_toptrader_long_short_ratio"),column("sum_toptrader_long_short_ratio"),
              column("count_long_short_ratio"),column("sum_taker_long_short_vol_ratio")];
  for line in lines {
   let fields:Vec<&str>=line.split(',').collect();
   let (Some(time),Some(raw))=(fields.get(at),fields.get(value)) else {continue};
   let (Some(time),Ok(raw))=(timestamp(time),raw.trim().parse::<f64>()) else {continue};
   if raw.is_finite()&&raw>=0.0 {
    let ratio=|i:usize|ratios[i].and_then(|c|fields.get(c)).and_then(|v|v.trim().parse::<f64>().ok()).filter(|v|v.is_finite()&&*v>=0.0);
    points.insert(time,(time,raw,ratio(0),ratio(1),ratio(2),ratio(3)));
   }
  }
 }
 let mut rows:Vec<MetricRow>=points.into_values().collect();
 rows.sort_unstable_by_key(|row|row.0);
 Ok(rows)
}

/// `2026-09-10 01:45:00`, and the ISO spelling of the same thing in case the
/// dump ever switches.
fn timestamp(text:&str)->Option<i64> {
 let text=text.trim();
 NaiveDateTime::parse_from_str(text,"%Y-%m-%d %H:%M:%S").ok()
  .or_else(||NaiveDateTime::parse_from_str(text,"%Y-%m-%dT%H:%M:%S").ok())
  .or_else(||NaiveDateTime::parse_from_str(text,"%Y-%m-%d %H:%M:%S%.f").ok())
  .map(|t|t.and_utc().timestamp_millis())
}

// ------------------------------------------------------------ 时钟与上游

/// 时间从这里读，不直接问 `Utc::now()`：最近缺失的那一天要不要重问，取决于
/// 「这一天结算了没有」和「负缓存过期了没有」两个时刻，测试得能把它们一起推过去，
/// 否则这条修复要靠真的等十分钟才验得了。路由里的时间判断不走这里，它们跟缓存无关。
enum Clock {System,#[cfg_attr(not(test),allow(dead_code))] Fixed(Arc<AtomicI64>)}
impl Clock {
 fn now(&self)->i64 {
  match self {Clock::System=>Utc::now().timestamp_millis(),Clock::Fixed(at)=>at.load(Ordering::Relaxed)}
 }
}

/// 一次抓取的结果。三种情况要分开：`Missing` 是归档明确说没有（404），
/// `Failed` 是这一次没问到，两者对缓存的意义完全不同——只有 `Missing` 能变成缺口，
/// `Failed`（403 / 超时 / 5xx / 连接断了）永远不许写永久标记，它说的是这个源现在
/// 不理我们，不是这一天没有数据。
enum Reply {Body(Vec<u8>),Missing,Failed}
/// 抓归档这一步抽成 trait，好让测试造出「先 404、过一会儿变 200」这种时序——
/// 真的 data.binance.vision 没法按需切换。
trait Origin:Send+Sync {
 fn fetch<'a>(&'a self,url:&'a str)->Pin<Box<dyn Future<Output=Reply>+Send+'a>>;
}
struct Vision(reqwest::Client);
impl Origin for Vision {
 fn fetch<'a>(&'a self,url:&'a str)->Pin<Box<dyn Future<Output=Reply>+Send+'a>> {
  Box::pin(async move {
   match self.0.get(url).send().await {
    Ok(response) if response.status()==reqwest::StatusCode::NOT_FOUND=>Reply::Missing,
    Ok(response) if response.status().is_success()=>match response.bytes().await {
     Ok(bytes)=>Reply::Body(bytes.to_vec()),
     Err(_)=>Reply::Failed,
    },
    _=>Reply::Failed,
   }
  })
 }
}

// ---------------------------------------------------------------- the store

static STORE:OnceLock<Arc<Store>>=OnceLock::new();
static TEMP:AtomicU64=AtomicU64::new(0);

async fn store()->Arc<Store> {
 if let Some(store)=STORE.get() {return store.clone()}
 let built=tokio::task::spawn_blocking(Store::new).await.unwrap_or_else(|_|Store::detached());
 STORE.get_or_init(||Arc::new(built)).clone()
}

struct Store {
 /// `None` when the cache directory cannot be used: the service still answers,
 /// it just pays the network every time.
 dir:Option<PathBuf>,
 limit:u64,
 /// 目录条目上限，见 `MAX_FILES`。
 entries:usize,
 client:reqwest::Client,
 origin:Box<dyn Origin>,
 clock:Clock,
 memory:Mutex<Memory>,
 disk:Mutex<Disk>,
 /// One download per (symbol, day) even when several charts ask at once.
 inflight:Mutex<HashMap<String,Arc<tokio::sync::Mutex<()>>>>,
 gate:Semaphore,
 prefetching:Mutex<HashSet<Arc<str>>>,
 /// 连着被拒了几次。抓到任何一个回答（包括 404）就清零。
 refusals:AtomicU32,
 /// 这个源歇到什么时候（`clock` 的毫秒）；0 表示没在歇。
 cold_until:AtomicI64,
}

/// Days kept parsed, oldest arrival evicted first.
///
/// 每条记录带一个到期时刻：`None` 是永久的（真的抓到了，或者那一天已经结算、
/// 确定不会再出现），`Some` 只有一种来路——还没结算就 404 的那几天。
#[derive(Default)]
struct Memory {map:HashMap<String,(Day,Option<i64>)>,order:VecDeque<String>}
impl Memory {
 /// 取一条还没过期的记录。过期的当场扔掉，好让调用方照常落到磁盘和网络上去；
 /// 留着不清，下一次还是会读到同一个过期的「没有」。
 fn get(&mut self,stem:&str,now:i64)->Option<Day> {
  if matches!(self.map.get(stem),Some((_,Some(until))) if *until<=now) {
   self.map.remove(stem);
   self.order.retain(|key|key!=stem);
   return None;
  }
  self.map.get(stem).map(|(day,_)|day.clone())
 }
}
/// What the cache directory holds, so eviction never has to stat it again.
///
/// `bytes` 不含 0 字节的缺口标记，`files` 含——两条上限分别看这两个数。
#[derive(Default)]
struct Disk {bytes:u64,files:HashMap<PathBuf,(u64,SystemTime)>}

impl Store {
 fn detached()->Store {
  // 归档和合约列表共用同一个 client，keep-alive 的连接池也就只有这一个。
  let client=client();
  Store{dir:None,limit:DEFAULT_LIMIT,entries:MAX_FILES,origin:Box::new(Vision(client.clone())),client,clock:Clock::System,
   memory:Mutex::default(),disk:Mutex::default(),
   inflight:Mutex::default(),gate:Semaphore::new(GATE),prefetching:Mutex::default(),
   refusals:AtomicU32::new(0),cold_until:AtomicI64::new(0)}
 }
 /// 测试用的实例：自己的目录、自己的时钟、自己的上游。
 #[cfg(test)]
 fn fake(dir:PathBuf,clock:Arc<AtomicI64>,origin:Box<dyn Origin>)->Arc<Store> {
  Store::fake_capped(dir,clock,origin,MAX_FILES)
 }
 /// 同上，外加一条能在测试里够得着的条目数上限——真的写二十万个文件是没法测的。
 #[cfg(test)]
 fn fake_capped(dir:PathBuf,clock:Arc<AtomicI64>,origin:Box<dyn Origin>,entries:usize)->Arc<Store> {
  Arc::new(Store{dir:Some(dir),limit:DEFAULT_LIMIT,entries,origin,clock:Clock::Fixed(clock),client:client(),
   memory:Mutex::default(),disk:Mutex::default(),
   inflight:Mutex::default(),gate:Semaphore::new(GATE),prefetching:Mutex::default(),
   refusals:AtomicU32::new(0),cold_until:AtomicI64::new(0)})
 }

 fn new()->Store {
  let mut store=Store::detached();
  store.limit=std::env::var("KANPAN_OI_CACHE_BYTES").ok().and_then(|v|v.parse().ok()).unwrap_or(DEFAULT_LIMIT);
  store.entries=std::env::var("KANPAN_OI_CACHE_FILES").ok().and_then(|v|v.parse().ok()).unwrap_or(MAX_FILES);
  let dir=PathBuf::from(std::env::var("KANPAN_OI_CACHE").unwrap_or_else(|_|"/var/cache/kanpan-api/oi".into()));
  if std::fs::create_dir_all(&dir).is_err() {tracing::warn!("Open interest cache is unavailable; answers will not be stored");return store}
  let (mut files,mut bytes)=(HashMap::new(),0u64);
  if let Ok(entries)=std::fs::read_dir(&dir) {
   for entry in entries.flatten() {
    let Ok(meta)=entry.metadata() else {continue};
    if !meta.is_file() {continue}
    let modified=meta.modified().unwrap_or(SystemTime::UNIX_EPOCH);
    bytes+=meta.len();
    files.insert(entry.path(),(meta.len(),modified));
   }
  }
  store.disk=Mutex::new(Disk{bytes,files});
  store.dir=Some(dir);
  store
 }

 /// The day's observations, and whether the answer came without the network.
 async fn day(self:&Arc<Self>,symbol:&str,day:i64)->(Result<Day,()>,bool) {
  let stem=format!("{symbol}-{}",day_name(day));
  if let Some(hit)=self.cached(&stem) {return (Ok(hit),true)}
  // Behind this lock the day is fetched once; everyone else re-reads what the
  // winner stored rather than opening a second connection for the same file.
  let lock=self.inflight.lock().ok().map(|mut table|table.entry(stem.clone()).or_default().clone());
  let Some(lock)=lock else {return (self.download(symbol,day,&stem).await,false)};
  let _held=lock.lock().await;
  if let Some(hit)=self.cached(&stem) {self.release(&stem);return (Ok(hit),true)}
  let fetched=self.download(symbol,day,&stem).await;
  self.release(&stem);
  (fetched,false)
 }

 fn release(&self,stem:&str) {
  if let Ok(mut table)=self.inflight.lock()
   && table.get(stem).is_some_and(|lock|Arc::strong_count(lock)<=1) {table.remove(stem);}
 }

 /// Memory first, then six-column slices. Old two-column files remain available
 /// to older binaries but are never mistaken for complete metrics.
 fn cached(&self,stem:&str)->Option<Day> {
  if let Ok(mut memory)=self.memory.lock()&& let Some(day)=memory.get(stem,self.clock.now()) {return Some(day)}
  let dir=self.dir.as_ref()?;
  // `.none` 只在那一天结算之后才写，所以磁盘上的缺口是永久的。
  if dir.join(format!("{stem}.none")).exists() {self.remember(stem,Day::Absent,None);return Some(Day::Absent)}
  let path=dir.join(format!("{stem}.metrics.json"));
  let raw=std::fs::read(&path).ok()?;
  let rows:Vec<MetricRow>=serde_json::from_slice(&raw).ok()?;
  let day=Day::Points(Arc::new(rows));
  self.touch(&path);
  self.remember(stem,day.clone(),None);
  Some(day)
 }

 /// What the caches already know about a day, without parsing or reading it:
 /// the answer prefetching needs to skip a day it has.
 fn known(&self,stem:&str)->Option<bool> {
  if let Ok(mut memory)=self.memory.lock()
   && let Some(day)=memory.get(stem,self.clock.now()) {return Some(matches!(day,Day::Points(_)))}
  let dir=self.dir.as_ref()?;
  if dir.join(format!("{stem}.none")).exists() {return Some(false)}
  if dir.join(format!("{stem}.metrics.json")).exists()||dir.join(format!("{stem}.json")).exists() {return Some(true)}
  None
 }

 /// `expires` 是到期时刻；`None` 表示这条记录永久有效。
 fn remember(&self,stem:&str,day:Day,expires:Option<i64>) {
  let Ok(mut memory)=self.memory.lock() else {return};
  if memory.map.insert(stem.to_owned(),(day,expires)).is_none() {memory.order.push_back(stem.to_owned());}
  while memory.order.len()>MEM_DAYS {
   let Some(oldest)=memory.order.pop_front() else {break};
   memory.map.remove(&oldest);
  }
 }

 async fn download(self:&Arc<Self>,symbol:&str,day:i64,stem:&str)->Result<Day,()> {
  // 这个源刚刚连着拒了好几次，本轮就不再往前翻日期了：一张图或者一次预热排着几百天，
  // 少了这一句它们会把同一个 403 撞几百遍，还每天各撞两次。查得比闸门更早，是为了让
  // 排在信号量后面的那几百天当场散掉，而不是一个一个挤过去再各自返回失败。
  if self.cooling() {return Err(())}
  let date=day_name(day);
  let url=format!("{ARCHIVE}{symbol}/{symbol}-metrics-{date}.zip");
  let _permit=self.gate.acquire().await.map_err(|_|())?;
  let mut last=Err(());
  // Two tries: a lost connection on a keep-alive pool is ordinary, and a
  // second attempt is far cheaper than failing a year of chart over one day.
  for attempt in 0..2 {
   if attempt>0 {tokio::time::sleep(Duration::from_millis(300)).await;}
   match self.origin.fetch(&url).await {
    Reply::Missing=>{
     // Before its listing day a symbol has no archive and never will; after
     // the day has settled, remember that instead of asking again.
     let settled=self.clock.now()-day*DAY>SETTLED;
     if settled {self.mark_absent(stem);}
     // 还没结算的那一天，404 只说明「这会儿还没发布」，不是缺口，所以只记短短
     // 一会儿：够挡住同一张图上那十几天的重复请求，又能在归档补发之后自己回来
     // 再问一次。不带到期时刻的话，这一天要等到被 FIFO 挤出内存或者进程重启才
     // 会被重新看一眼，用户那张图在此之前一直缺着最近这一段。
     self.remember(stem,Day::Absent,(!settled).then(||self.clock.now()+RECENT_ABSENT_TTL));
     self.answered();
     return Ok(Day::Absent);
    }
    Reply::Body(bytes)=>{
     if bytes.len()>2*1024*1024 {return Err(())}
     let Ok(rows)=tokio::task::spawn_blocking(move ||parse(&bytes)).await.map_err(|_|())? else {continue};
     self.answered();
     let day=Day::Points(Arc::new(rows));
     if let Day::Points(ref rows)=day&& !rows.is_empty() {self.store(stem,rows);}
     self.remember(stem,day.clone(),None);
     return Ok(day);
    }
    // 403 / 超时 / 5xx / 断开：这一天没问到，但绝不当成缺口——不写 `.none`，也不记
    // 进内存。连着撞到 `REFUSALS` 次就把这个源按下去，后面那些天连出站都不出。
    Reply::Failed=>{last=Err(()); if self.refused() {break}}
   }
  }
  last
 }

 /// 这个源正在歇吗。
 fn cooling(&self)->bool {self.cold_until.load(Ordering::Relaxed)>self.clock.now()}
 /// 记一次被拒；返回「就是这一次把源按下去了」。
 fn refused(&self)->bool {
  if self.refusals.fetch_add(1,Ordering::Relaxed)+1<REFUSALS {return false}
  // 计数清零：冷却结束之后要从头再数，否则歇完第一次被拒就又歇一轮。
  self.refusals.store(0,Ordering::Relaxed);
  self.cold_until.store(self.clock.now()+SOURCE_COOLDOWN,Ordering::Relaxed);
  tracing::warn!("The open interest archive refused {REFUSALS} times in a row; holding this source for {}s",SOURCE_COOLDOWN/1000);
  true
 }
 /// 上游回话了（200 或 404 都算），连续计数归零。
 fn answered(&self) {self.refusals.store(0,Ordering::Relaxed);}

 /// Write the slice, then bring the directory back under its ceiling.
 fn store(&self,stem:&str,rows:&[MetricRow]) {
  let (Some(dir),Ok(payload))=(self.dir.as_ref(),serde_json::to_vec(rows)) else {return};
  let temporary=dir.join(format!(".tmp-{}-{}",std::process::id(),TEMP.fetch_add(1,Ordering::Relaxed)));
  let path=dir.join(format!("{stem}.metrics.json"));
  if std::fs::write(&temporary,&payload).is_err()||std::fs::rename(&temporary,&path).is_err() {
   let _=std::fs::remove_file(&temporary);
   return;
  }
  let evicted={
   let Ok(mut disk)=self.disk.lock() else {return};
   if let Some((size,_))=disk.files.remove(&path) {disk.bytes-=size.min(disk.bytes);}
   disk.bytes+=payload.len() as u64;
   disk.files.insert(path.clone(),(payload.len() as u64,SystemTime::now()));
   self.shrink(&mut disk,&path)
  };
  for victim in evicted {let _=std::fs::remove_file(victim);}
 }

 /// 越界了吗——两条上限，字节预算和条目数，谁先满算谁。
 fn over(&self,disk:&Disk)->bool {disk.bytes>self.limit||disk.files.len()>self.entries}

 /// 把目录拉回两条上限以内，返回该从磁盘上删掉的那些路径。
 ///
 /// 先扔最旧的缺口标记，再扔最旧的切片。标记一个字节都不占，所以撑爆条目数的只会是
 /// 它们；而丢掉一个标记的代价只是下次为那一天多问一次 404，丢掉一个切片却要重新下载
 /// 整天的数据。`keep` 是刚写进去的那个，永远不做牺牲品。
 fn shrink(&self,disk:&mut Disk,keep:&std::path::Path)->Vec<PathBuf> {
  let mut evicted=Vec::new();
  if !self.over(disk) {return evicted}
  let mut ages:Vec<(PathBuf,SystemTime)>=disk.files.iter().map(|(p,(_,at))|(p.clone(),*at)).collect();
  ages.sort_by_key(|(_,at)|*at);
  for markers_first in [true,false] {
   for (victim,_) in &ages {
    if !self.over(disk) {return evicted}
    if victim.as_path()==keep {continue}
    if victim.extension().is_some_and(|kind|kind=="none")!=markers_first {continue}
    if let Some((size,_))=disk.files.remove(victim) {
     disk.bytes-=size.min(disk.bytes);
     evicted.push(victim.clone());
    }
   }
  }
  evicted
 }

 fn touch(&self,path:&std::path::Path) {
  if let Ok(mut disk)=self.disk.lock()
   && let Some(entry)=disk.files.get_mut(path) {entry.1=SystemTime::now();}
 }

 /// A zero-byte marker: this day is not in the archive and will not appear.
 ///
 /// 标记不花字节，但它花一个目录项，所以写完也要过一遍条目数上限——否则「上市日
 /// 之前的每一天各一个标记」这条路能把目录撑到几十万个文件，而字节预算一声不响。
 fn mark_absent(&self,stem:&str) {
  let Some(dir)=self.dir.as_ref() else {return};
  let path=dir.join(format!("{stem}.none"));
  if std::fs::write(&path,b"").is_err() {return}
  let evicted={
   let Ok(mut disk)=self.disk.lock() else {return};
   disk.files.insert(path.clone(),(0,SystemTime::now()));
   self.shrink(&mut disk,&path)
  };
  for victim in evicted {let _=std::fs::remove_file(victim);}
 }

 // ------------------------------------------------------------- prefetching

 /// Fill a symbol's archive backwards from yesterday while nobody is waiting.
 ///
 /// It stops after a month of consecutive absent days, which is how the listing
 /// date announces itself, and it runs once per symbol per process: the days it
 /// would add on a second pass are the recent ones, which a chart request
 /// fetches anyway.
 /// The boot warm-up: `WARM_LANES` symbols at a time, each walking its own days
 /// backwards from yesterday. Per-symbol rather than per-day so the "thirty
 /// absent days means this contract was not listed yet" test stays meaningful —
 /// it only reads as a run when the days arrive in order.
 async fn warm(self:&Arc<Self>,symbols:Vec<Arc<str>>,days:i64) {
  let last=self.clock.now().div_euclid(DAY)-1;
  let first=(last-days+1).max(EPOCH.div_euclid(DAY));
  let mut tasks=tokio::task::JoinSet::new();
  let mut queue=symbols.into_iter();
  loop {
   while tasks.len()<WARM_LANES {
    let Some(symbol)=queue.next() else {break};
    let store=self.clone();
    tasks.spawn(async move {
     let mut absent=0;
     for day in (first..=last).rev() {
      if absent>=30 {break}                  // before this contract was listed
      match store.known(&format!("{symbol}-{}",day_name(day))) {
       Some(true)=>{absent=0;continue}
       Some(false)=>{absent+=1;continue}
       None=>{}
      }
      match store.day(&symbol,day).await.0 {
       Ok(Day::Absent)=>absent+=1,
       Ok(Day::Points(_))=>absent=0,
       Err(())=>{}
      }
      tokio::time::sleep(WARM_PAUSE).await;
     }
    });
   }
   if tasks.is_empty() {break}
   let _=tasks.join_next().await;
  }
  tracing::info!("Open interest warm-up finished");
 }

 fn spawn_prefetch(self:&Arc<Self>,symbol:Arc<str>) {
  {
   let Ok(mut running)=self.prefetching.lock() else {return};
   if !running.insert(symbol.clone()) {return}
  }
  let store=self.clone();
  tokio::spawn(async move {
   let last=store.clock.now().div_euclid(DAY)-1;
   let first=EPOCH.div_euclid(DAY);
   let mut absent=0;
   let mut day=last;
   let mut tasks=tokio::task::JoinSet::new();
   while day>=first&&absent<30 {
    while tasks.len()<PREFETCH_LANES&&day>=first&&absent<30 {
     let at=day;
     day-=1;
     // A day already on disk is left there: reading it back would buy nothing
     // and would push the days a chart is using out of the memory cache.
     match store.known(&format!("{symbol}-{}",day_name(at))) {
      Some(true)=>{absent=0;continue}
      Some(false)=>{absent+=1;continue}
      None=>{}
     }
     let (store,symbol)=(store.clone(),symbol.clone());
     tasks.spawn(async move {store.day(&symbol,at).await.0});
    }
    if tasks.is_empty() {break}
    match tasks.join_next().await {
     Some(Ok(Ok(Day::Absent)))=>absent+=1,
     Some(Ok(Ok(Day::Points(_))))=>absent=0,
     _=>{}
    }
    // Background work yields the host to whoever is actually waiting.
    tokio::time::sleep(Duration::from_millis(40)).await;
   }
   tasks.abort_all();
   tracing::debug!("Open interest archive filled for {symbol}");
  });
 }
}

/// One client for the life of the process: the connections it keeps open to
/// the archive are the whole difference between 54 s and a few seconds.
fn client()->reqwest::Client {
 reqwest::Client::builder()
  .pool_max_idle_per_host(GATE)
  .pool_idle_timeout(Duration::from_secs(90))
  .connect_timeout(Duration::from_secs(6))
  .timeout(Duration::from_secs(20))
  .user_agent("kanpan-api/1.0")
  .build().unwrap_or_default()
}

#[cfg(test)]
mod tests {
 use super::*;

 fn zip_of(csv:&str)->Vec<u8> {
  let mut writer=zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
  writer.start_file::<_,()>("ETHUSDT-metrics-2026-09-10.csv",zip::write::SimpleFileOptions::default()).unwrap();
  std::io::Write::write_all(&mut writer,csv.as_bytes()).unwrap();
  writer.finish().unwrap().into_inner()
 }

 #[test]
 fn metric_columns_survive_parse_storage_and_versioned_response() {
  let csv="create_time,symbol,sum_open_interest,count_toptrader_long_short_ratio,sum_toptrader_long_short_ratio,count_long_short_ratio,sum_taker_long_short_vol_ratio\n2026-09-10 01:45:00,ETHUSDT,100,1.1,1.2,0.8,1.3\n";
  let rows=parse(&zip_of(csv)).unwrap();
  assert_eq!(rows[0],(1_789_004_700_000,100.0,Some(1.1),Some(1.2),Some(0.8),Some(1.3)));
  let restored:Vec<MetricRow>=serde_json::from_slice(&encode_rows(&rows,true)).unwrap();
  assert_eq!(restored,rows);
  let legacy:Vec<(i64,f64)>=serde_json::from_slice(&encode_rows(&rows,false)).unwrap();
  assert_eq!(legacy,vec![(rows[0].0,100.0)]);
  assert!(serde_json::from_slice::<Vec<MetricRow>>(b"[[1789004700000,100]]").is_err(),"two-column caches must miss");
 }

 #[test]
 fn archive_rows_parse_in_time_order_however_the_dump_is_ordered() {
  let csv="create_time,symbol,sum_open_interest,sum_open_interest_value\n\
           2026-09-10 03:35:00,ETHUSDT,2267091.793,5608152911.19\n\
           2026-09-10 01:45:00,ETHUSDT,2271325.644,5591857102.96\n";
  let rows=parse(&zip_of(csv)).unwrap();
  assert_eq!(rows.len(),2);
  assert_eq!(rows[0].0,1_789_004_700_000);
  assert!(rows[0].1>rows[1].1);                   // 01:45 first, and it is the larger figure
 }

 #[test]
 fn unreadable_rows_are_skipped_not_fatal() {
  let csv="create_time,symbol,sum_open_interest\n\
           2026-09-10 01:45:00,ETHUSDT,100\n\
           not-a-time,ETHUSDT,200\n\
           2026-09-10 01:50:00,ETHUSDT,nan\n\
           2026-09-10 01:55:00,ETHUSDT,-5\n\
           2026-09-10 02:00:00,ETHUSDT,300\n";
  let rows=parse(&zip_of(csv)).unwrap();
  assert_eq!(rows.iter().map(|r|r.1).collect::<Vec<_>>(),vec![100.0,300.0]);
 }

 #[test]
 fn a_missing_column_leaves_the_day_empty_rather_than_guessing() {
  let rows=parse(&zip_of("create_time,symbol\n2026-09-10 01:45:00,ETHUSDT\n")).unwrap();
  assert!(rows.is_empty());
 }

 #[test]
 fn buckets_follow_the_calendar_and_leave_the_finest_intervals_alone() {
  let time=1_789_004_700_000;                     // 2026-09-10 01:45:00 UTC, a Thursday
  assert_eq!(bucket(time,"1m"),time);             // finer than the source: not moved
  assert_eq!(bucket(time,"1h"),1_789_002_000_000);
  assert_eq!(bucket(time,"1d"),1_788_998_400_000);
  assert_eq!(bucket(time,"1w"),1_788_739_200_000);// Monday 2026-09-07
  assert_eq!(bucket(time,"1M"),1_788_220_800_000);// 2026-09-01
  assert_eq!(bucket(time,"1y"),1_767_225_600_000);// 2026-01-01
 }

 #[test]
 fn a_week_bucket_starts_on_monday_for_a_midweek_observation() {
  let wednesday=1_788_912_000_000;                // 2026-09-09 00:00 UTC
  assert_eq!(bucket(wednesday,"1w"),1_788_739_200_000);
 }

 #[test]
 fn day_names_address_the_archive() {
  assert_eq!(day_name(EPOCH/DAY),"2020-09-01");
 }

 // ---------------------------------------- 最近缺失的那一天只记一小会儿

 /// 一个能在 404、200 和「拒绝」之间切换的假归档，外加它被问了几次。
 #[derive(Default)]
 struct Upstream {zip:Mutex<Option<Vec<u8>>>,asked:AtomicU64,refusing:std::sync::atomic::AtomicBool}
 impl Upstream {
  fn asked(&self)->u64 {self.asked.load(Ordering::Relaxed)}
  fn publish(&self,bytes:Vec<u8>) {*self.zip.lock().unwrap()=Some(bytes);}
  fn withdraw(&self) {*self.zip.lock().unwrap()=None;}
  /// 403 / 超时 / 5xx——`Vision` 把这些都归成 `Reply::Failed`，这里就直接发那一种。
  fn refuse(&self,yes:bool) {self.refusing.store(yes,Ordering::Relaxed);}
 }
 impl Origin for Arc<Upstream> {
  fn fetch<'a>(&'a self,_url:&'a str)->Pin<Box<dyn Future<Output=Reply>+Send+'a>> {
   self.asked.fetch_add(1,Ordering::Relaxed);
   if self.refusing.load(Ordering::Relaxed) {return Box::pin(async {Reply::Failed})}
   let body=self.zip.lock().unwrap().clone();
   Box::pin(async move {body.map_or(Reply::Missing,Reply::Body)})
  }
 }
 fn one_day()->Vec<u8> {zip_of("create_time,symbol,sum_open_interest\n2026-09-10 01:45:00,ETHUSDT,100\n")}
 /// 一天的归档，和一个停在给定时刻的 store。
 fn store_at(dir:&std::path::Path,now:i64)->(Arc<Store>,Arc<Upstream>,Arc<AtomicI64>) {
  let clock=Arc::new(AtomicI64::new(now));
  let upstream=Arc::new(Upstream::default());
  (Store::fake(dir.to_path_buf(),clock.clone(),Box::new(upstream.clone())),upstream,clock)
 }

 #[tokio::test]
 async fn a_recent_missing_day_is_asked_again_once_the_short_ttl_lapses() {
  let dir=tempfile::tempdir().expect("temp dir");
  let day=EPOCH.div_euclid(DAY)+400;
  // 这一天刚结束一小时：归档可能只是还没发布，还不到结算期。
  let (store,upstream,clock)=store_at(dir.path(),(day+1)*DAY+3_600_000);

  assert!(matches!(store.day("ETHUSDT",day).await.0,Ok(Day::Absent)));
  assert_eq!(upstream.asked(),1);
  assert!(matches!(store.day("ETHUSDT",day).await.0,Ok(Day::Absent)));
  assert_eq!(upstream.asked(),1,"这一小会儿里同一张图的其他天不用各问一次上游");
  assert!(!dir.path().join(format!("ETHUSDT-{}.none",day_name(day))).exists(),"没结算的那天不落永久标记");

  // 归档晚了十几分钟才发布出来。
  clock.fetch_add(RECENT_ABSENT_TTL+1,Ordering::Relaxed);
  upstream.publish(one_day());
  assert!(matches!(store.day("ETHUSDT",day).await.0,Ok(Day::Points(_))),"不必重启，这一天自己补上了");
  assert_eq!(upstream.asked(),2);
  // 补上之后就是永久的了，不会因为时间继续走又去问一遍。
  clock.fetch_add(10*RECENT_ABSENT_TTL,Ordering::Relaxed);
  assert!(matches!(store.day("ETHUSDT",day).await.0,Ok(Day::Points(_))));
  assert_eq!(upstream.asked(),2);
 }

 #[tokio::test]
 async fn a_settled_missing_day_is_a_permanent_gap_and_is_never_asked_again() {
  let dir=tempfile::tempdir().expect("temp dir");
  let day=EPOCH.div_euclid(DAY)+400;
  // 已经过了结算期：这一天确实不在归档里（上市日之前的那些天就是这样）。
  let (store,upstream,clock)=store_at(dir.path(),day*DAY+SETTLED+1);

  assert!(matches!(store.day("ETHUSDT",day).await.0,Ok(Day::Absent)));
  assert!(dir.path().join(format!("ETHUSDT-{}.none",day_name(day))).exists(),"结算之后的缺口落一个永久标记");

  clock.fetch_add(365*DAY,Ordering::Relaxed);
  upstream.publish(one_day());
  assert!(matches!(store.day("ETHUSDT",day).await.0,Ok(Day::Absent)),"永久缺口不受那条短 TTL 影响");
  assert_eq!(upstream.asked(),1,"再也不问上游");
 }

 // ---------------------------------------- 被拒的源歇一会儿（A-T18）

 #[tokio::test]
 async fn a_source_that_keeps_refusing_is_held_off_instead_of_being_asked_for_every_day() {
  let dir=tempfile::tempdir().expect("temp dir");
  let day=EPOCH.div_euclid(DAY)+400;
  // 这些天早就结算了：要是把拒绝当成「没有」，就会在这里落下永久缺口。
  let (store,upstream,clock)=store_at(dir.path(),(day+40)*DAY);
  upstream.refuse(true);

  // 第一天：两次尝试都被拒，算两次。
  assert!(store.day("ETHUSDT",day).await.0.is_err());
  assert_eq!(upstream.asked(),2);
  assert!(!dir.path().join(format!("ETHUSDT-{}.none",day_name(day))).exists(),
   "403 / 超时 / 5xx 不是缺口，永远不许写永久标记");

  // 第二天：第三次被拒把这个源按下去，连这一天的第二次尝试都不发了。
  assert!(store.day("ETHUSDT",day-1).await.0.is_err());
  assert_eq!(upstream.asked(),3);

  // 后面那十天是一张图里剩下的日期：一次都不出站。
  for back in 2..12 {assert!(store.day("ETHUSDT",day-back).await.0.is_err());}
  assert_eq!(upstream.asked(),3,"冷却期内不再往前翻日期");
  for back in 0..12 {
   assert!(!dir.path().join(format!("ETHUSDT-{}.none",day_name(day-back))).exists(),"冷却期内也不许留下缺口");
  }

  // 歇满五分钟，边缘节点也好了。
  clock.fetch_add(SOURCE_COOLDOWN+1,Ordering::Relaxed);
  upstream.refuse(false);
  upstream.publish(one_day());
  assert!(matches!(store.day("ETHUSDT",day-2).await.0,Ok(Day::Points(_))),"冷却到期就自己恢复，不用重启");
  assert_eq!(upstream.asked(),4);

  // 抓到一天就把连续计数清了：接下来偶发的两次失败不该立刻又按下去。
  upstream.refuse(true);
  assert!(store.day("ETHUSDT",day-3).await.0.is_err());
  assert_eq!(upstream.asked(),6,"两次尝试都发了出去，说明没在歇");
 }

 // ---------------------------------------- 目录条目上限（A.8）

 #[tokio::test]
 async fn the_entry_ceiling_evicts_the_zero_byte_markers_before_any_real_slice() {
  let dir=tempfile::tempdir().expect("temp dir");
  let day=EPOCH.div_euclid(DAY)+400;
  let clock=Arc::new(AtomicI64::new((day+40)*DAY));
  let upstream=Arc::new(Upstream::default());
  // 上限压到两条，好在测试里真的越界；线上是 `MAX_FILES`。
  let store=Store::fake_capped(dir.path().to_path_buf(),clock.clone(),Box::new(upstream.clone()),2);
  let marker=|d:i64|dir.path().join(format!("ETHUSDT-{}.none",day_name(d)));
  let slice=dir.path().join(format!("ETHUSDT-{}.metrics.json",day_name(day-2)));

  // 两个缺口标记：0 字节，字节预算一动不动，占的却是两个目录项。
  for back in [0,1] {assert!(matches!(store.day("ETHUSDT",day-back).await.0,Ok(Day::Absent)));}
  assert!(marker(day).exists()&&marker(day-1).exists());
  assert_eq!(store.disk.lock().unwrap().bytes,0,"标记不花字节，所以只有条目数能拦住它们");

  // 第三个条目是一天真的数据：越界了，牺牲的是最旧的那个标记，不是这一天。
  upstream.publish(one_day());
  assert!(matches!(store.day("ETHUSDT",day-2).await.0,Ok(Day::Points(_))));
  assert!(slice.exists(),"刚写下的切片不许被自己挤掉");
  assert!(!marker(day).exists(),"先淘汰最旧的标记");
  assert!(marker(day-1).exists(),"还没越界就不再多扔");

  // 再来一个标记：又越界，扔的还是剩下那个标记，切片仍然在。
  upstream.withdraw();
  assert!(matches!(store.day("ETHUSDT",day-3).await.0,Ok(Day::Absent)));
  assert!(marker(day-3).exists());
  assert!(!marker(day-1).exists(),"标记先走");
  assert!(slice.exists(),"真数据比标记值钱：重下一天要 0.4 s，重问一次 404 只要一个往返");
  assert_eq!(store.disk.lock().unwrap().files.len(),2);
 }
}
