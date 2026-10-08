//! 主力订单流的品种表：`GET /v1/market/orderflow/instruments?base=BTC`。
//!
//! 手机打开一只币（按 base 资产，例如 BTC），主力订单流要把这只币在每一家接入的交易所的现货、
//! U 本位永续、币本位永续、交割（当季 + 次季）每一本簿都订上。每一家各有自己的合约表、自己的面值
//! 口径（线性按币、反向按美元一张），手机不该自己去拉十几张全表——有的它在国内根本连不上，
//! 有的一张就好几 MB。所以由这里汇总：
//!
//! * 后台每 10 分钟把登记的每张全表（`venues::orderflow::tables()`，各家在自己的
//!   `venues/<ex>/orderflow.rs` 里登记）各拉一次，只留下这个功能要用的几列，按 base 建索引。
//!   拉失败的那一张 30 秒后再试，手上那份旧的照常用；从来没拉成功过的那一张这一次就不出现
//!   （其他照给，接口仍 200）。
//! * 请求只查内存，不出站。进程起来后第一个请求会等第一轮拉完（最多 `FIRST_WAIT`），
//!   之后再也不等。
//! * 没人用就不拉：最近 `IDLE`（1 小时）没有任何请求，各张表的后台循环在下一次该拉的时候停下
//!   （手上的表留着）；之后第一个请求照常立刻拿手上那份答复，同时把循环重新起起来、马上拉一轮。
//!
//! 返回的每一项（字段名是和客户端的约定，改名就是改协议）：
//! * `exchange`：交易所代号（各家的 `KEY`）；
//! * `product`：`spot` / `usdtPerp` / `coinPerp` / `delivery`；
//! * `instrument`：这家交易所自己的代号，原样拿去订流、取快照；
//! * `margin`：只有交割有，`usdt`（U 本位交割）或 `coin`（币本位交割）；
//! * `notional`：一个数量单位值多少——
//!   `{"kind":"linear","multiplier":m}`：名义美元 = 价格 × 数量 × m（m 是一个数量单位是多少个币）；
//!   `{"kind":"inverse","contractUsd":c}`：名义美元 = 张数 × c；
//! * `tick`：最小价格变动，按这家自己的报价；
//! * `expiryMs`：只有交割有，交割时间（毫秒）；
//! * `priceScale`：只在不等于 1 时出现。单价极小的币挂成「N 个币」一个单位（`1000PEPEUSDT`、
//!   `kPEPE`）：价格和数量都是按「N 个币」报的。这时 `priceScale=N`，换成每个币的价格 =
//!   价格 ÷ priceScale；名义美元仍按上面 linear 的算法用原始价格算（multiplier 仍是 1）。
//!
//! 各家的取舍（只列在交易的、交割只列当季与次季、现货只列 USDT / USD 计价……）写在各家的
//! `orderflow.rs` 里。已过交割时间的合约在答复时剔掉，哪怕表还没刷新。
use crate::{AppState,error::{ApiError,Params}};
use axum::{Json,Router,http::{HeaderValue,header},response::{IntoResponse,Response},routing::get};
use serde::Deserialize;
use std::sync::{Arc,Mutex,OnceLock};
use std::time::Duration;
use tokio::sync::watch;
use tokio::time::Instant;

pub use crate::venues::orderflow::{ExchangeKey,Margin,Notional,Product,SCALED_PREFIXES,Table,TableSource,Venue,scale_of,unscaled};
use crate::venues::orderflow::FETCH_TIMEOUT;

const PATH:&str="/v1/market/orderflow/instruments";

/// 一张表拉成功之后多久再拉。合约上下架一天几次，交割换季一个季度一次。
const FRESH:Duration=Duration::from_secs(10*60);
/// 一张表拉失败之后多久再试。手上的旧表照常用，所以不必急。
const RETRY:Duration=Duration::from_secs(30);
/// 进程起来后的第一个请求最多等第一轮拉多久。比路由上那层 30 秒超时短得多。
const FIRST_WAIT:Duration=Duration::from_secs(8);
/// 最近多久没有请求，后台循环就停下。
const IDLE:Duration=Duration::from_secs(60*60);
/// 答复可以被中间层缓存多久。
const CACHE_CONTROL:&str="max-age=60";

/// 一张表此刻手上的那份：(这张表要不要按「N 个币」前缀找, 表)。没拉到过是 `None`。
pub type Shelf=(bool,Option<Arc<Table>>);

// ------------------------------------------------------------------ 按 base 取

/// 从一张表里取这只币的那几行。`scaled` 的表还要看带前缀的那种（`1000PEPE` 之于 `PEPE`）。
fn rows_for(table:&Table,scaled:bool,base:&str)->Vec<Venue> {
 let mut out:Vec<Venue>=table.get(base).cloned().unwrap_or_default();
 if scaled {
  for (prefix,scale) in SCALED_PREFIXES {
   if let Some(rows)=table.get(&format!("{prefix}{base}")) {
    out.extend(rows.iter().cloned().map(|mut v|{v.price_scale=Some(scale);v}));
   }
  }
 }
 out
}

/// 按表的先后把这只币的各家各产品排成一张清单，剔掉已经过了交割时间的。
pub fn pick(tables:&[Shelf],base:&str,now_ms:i64)->Vec<Venue> {
 let mut out=Vec::new();
 for (scaled,table) in tables {
  let Some(table)=table else {continue};
  let mut rows=rows_for(table,*scaled,base);
  rows.retain(|v|v.expiry_ms.is_none_or(|at|at>now_ms));
  rows.sort_by_key(Venue::rank);
  out.extend(rows);
 }
 out
}

pub(crate) fn valid_base(base:&str)->bool {(1..=20).contains(&base.len())&&base.bytes().all(|b|b.is_ascii_uppercase()||b.is_ascii_digit())}

// ------------------------------------------------------------------ 后台拉表

#[derive(Clone,Default)]
struct Held {table:Option<Arc<Table>>,tried:bool}

/// 后台循环的节奏（测试里换成自己的）。
#[derive(Clone,Copy,Debug)]
struct Pace {
 /// 拉成功之后隔多久再拉。
 fresh:Duration,
 /// 拉失败之后隔多久再试。
 retry:Duration,
 /// 最近多久没有请求就停。
 idle:Duration,
}
const PACE:Pace=Pace{fresh:FRESH,retry:RETRY,idle:IDLE};

/// 一张表：从哪儿拉、拉到的放哪儿。循环停了表也留着。
struct Feed {source:TableSource,held:watch::Sender<Held>}

/// 最近一次请求的时间，以及每张表的循环在不在跑。放在同一把锁里，
/// 「循环判定没人要了、停下」与「请求来了、看循环在不在跑」不会错开。
struct Activity {asked:Instant,running:Vec<bool>}

struct Book {feeds:Vec<Feed>,activity:Mutex<Activity>,pace:Pace}

impl Book {
 /// 建好但不启动：第一个请求来时 `asked` 才把循环起起来。
 fn new(sources:Vec<TableSource>,pace:Pace)->Arc<Self> {
  let running=vec![false;sources.len()];
  let feeds=sources.into_iter().map(|source|Feed{source,held:watch::channel(Held::default()).0}).collect();
  Arc::new(Self{feeds,activity:Mutex::new(Activity{asked:Instant::now(),running}),pace})
 }
 /// 有人问了：记下时间，没在跑的循环（第一次，或者闲置停掉的）重新起。
 fn asked(self:&Arc<Self>) {
  let mut activity=self.activity.lock().unwrap_or_else(|e|e.into_inner());
  activity.asked=Instant::now();
  for index in 0..self.feeds.len() {
   if activity.running[index] {continue}
   activity.running[index]=true;
   crate::supervise::spawn_logged("orderflow-instruments",crate::supervise::Life::Once,run(self.clone(),index));
  }
 }
 /// 这个循环该不该停；该停就顺手把它记成不在跑。
 fn idle(&self,index:usize)->bool {
  let mut activity=self.activity.lock().unwrap_or_else(|e|e.into_inner());
  if activity.asked.elapsed()<self.pace.idle {return false}
  activity.running[index]=false;
  true
 }
}

/// 一张表的后台循环：成功隔 10 分钟再拉，失败隔 30 秒再试，旧表一直留着用；
/// 每次该拉之前看一眼，最近一小时没人问就停。
/// 循环 panic 时把「在跑」放掉，下一次有人问就能重新起。只管 panic 这一种：正常停下时
/// `idle` 已经在锁里放掉了，这里再放一次会把紧接着新起的那一条的标志也抹掉。
struct ReleaseOnPanic<'a>(&'a Book,usize);
impl Drop for ReleaseOnPanic<'_> {
 fn drop(&mut self) {
  if std::thread::panicking() {self.0.activity.lock().unwrap_or_else(|e|e.into_inner()).running[self.1]=false;}
 }
}

async fn run(book:Arc<Book>,index:usize) {
 let _release=ReleaseOnPanic(&book,index);
 let Feed{source,held}=&book.feeds[index];
 loop {
  let wait=match tokio::time::timeout(FETCH_TIMEOUT+Duration::from_secs(5),(source.fetch)()).await {
   Ok(Ok(table))=>{
    let table=Arc::new(table);
    held.send_modify(|held|{held.table=Some(table);held.tried=true;});
    book.pace.fresh
   },
   Ok(Err(e))=>{tracing::warn!("Orderflow instruments: {} table failed: {e}",source.name);held.send_modify(|held|held.tried=true);book.pace.retry},
   Err(_)=>{tracing::warn!("Orderflow instruments: {} table timed out",source.name);held.send_modify(|held|held.tried=true);book.pace.retry},
  };
  tokio::time::sleep(wait).await;
  if book.idle(index) {
   tracing::info!("Orderflow instruments: {} loop stopped, nobody asked for {:?}",source.name,book.pace.idle);
   return;
  }
 }
}

/// 那一份后台表。第一次有人问时才开始拉（测试和不用这个功能的进程不出站）。
fn book()->&'static Arc<Book> {
 static B:OnceLock<Arc<Book>>=OnceLock::new();
 B.get_or_init(||Book::new(crate::venues::orderflow::tables(),PACE))
}

/// 记下这次请求（必要时把停掉的循环起起来），然后拿各张表手上那份。只有从来没拉过的那张才等
/// （最多 `FIRST_WAIT`）；闲置停过又重起的，手上有旧表就不等。
async fn snapshot(book:&Arc<Book>)->Vec<Shelf> {
 book.asked();
 let waits=book.feeds.iter().map(|feed| {
  let mut rx=feed.held.subscribe();
  let scaled=feed.source.scaled;
  async move {
   if !rx.borrow().tried {let _=tokio::time::timeout(FIRST_WAIT,rx.wait_for(|held|held.tried)).await;}
   let table=rx.borrow().table.clone();
   (scaled,table)
  }
 });
 futures_util::future::join_all(waits).await
}

// ------------------------------------------------------------------ 路由

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct InstrumentsQuery {base:String}

fn reply(base:&str,venues:Vec<Venue>,now_ms:i64)->Response {
 let mut response=Json(serde_json::json!({"base":base,"asOfMs":now_ms,"venues":venues})).into_response();
 response.headers_mut().insert(header::CACHE_CONTROL,HeaderValue::from_static(CACHE_CONTROL));
 response
}

/// 一只 base 此刻的全部簿（服务端历史跟踪用），和接口发给手机的是同一份；顺带让表的后台循环保持在跑。
pub async fn venues(base:&str)->Vec<Venue> {
 let tables=snapshot(book()).await;
 pick(&tables,base,chrono::Utc::now().timestamp_millis())
}

/// 有没有哪家在挂这只：有 `Some(true)`，都没有 `Some(false)`；有哪张表还没拉到（判不了）`None`。
pub async fn listed(base:&str)->Option<bool> {
 let tables=snapshot(book()).await;
 listed_in(&tables,base,chrono::Utc::now().timestamp_millis())
}

pub fn listed_in(tables:&[Shelf],base:&str,now_ms:i64)->Option<bool> {
 if !pick(tables,base,now_ms).is_empty() {return Some(true)}
 tables.iter().all(|(_,t)|t.is_some()).then_some(false)
}

async fn instruments(Params(query):Params<InstrumentsQuery>)->Response {
 if !valid_base(&query.base) {return ApiError::bad("invalid_base").into_response()}
 let tables=snapshot(book()).await;
 let now=chrono::Utc::now().timestamp_millis();
 let venues=pick(&tables,&query.base,now);
 reply(&query.base,venues,now)
}

pub fn routes()->Router<AppState> {Router::new().route(PATH,get(instruments))}

#[cfg(test)]
mod tests {
 //! 五家合起来的先后与口径见 `venues::orderflow` 的测试；这里只看通用的那几样。
 use super::*;
 use serde_json::{Value,json};

 const NOW:i64=1_790_200_000_000;

 fn row(exchange:&'static str,product:Product,instrument:&str,listed:&str,expiry:Option<i64>)->Venue {
  Venue{exchange:ExchangeKey(exchange),product,instrument:instrument.into(),margin:None,notional:Notional::Linear{multiplier:1.0},tick:0.1,expiry_ms:expiry,price_scale:None,listed_base:listed.into()}
 }
 fn shelf(scaled:bool,rows:Vec<Venue>)->Shelf {(scaled,Some(Arc::new(crate::venues::orderflow::index(rows))))}
 fn fake()->Vec<Shelf> {
  vec![
   shelf(true,vec![row("a",Product::Spot,"A-BTC","BTC",None),row("a",Product::UsdtPerp,"A-BTC-P","BTC",None),row("a",Product::UsdtPerp,"A-1000PEPE","1000PEPE",None)]),
   shelf(false,vec![row("b",Product::Delivery,"B-BTC-1","BTC",Some(NOW+1)),row("b",Product::Delivery,"B-BTC-0","BTC",Some(NOW)),row("b",Product::UsdtPerp,"B-1000PEPE","1000PEPE",None)]),
  ]
 }

 #[test]
 fn tables_keep_their_order_rows_are_ranked_and_expired_ones_drop() {
  let names:Vec<String>=pick(&fake(),"BTC",NOW).into_iter().map(|v|v.instrument).collect();
  assert_eq!(names,["A-BTC-P","A-BTC","B-BTC-1"]);
 }

 #[test]
 fn only_scaled_tables_are_searched_by_prefix() {
  let pepe=pick(&fake(),"PEPE",NOW);
  assert_eq!(pepe.len(),1);
  assert_eq!((pepe[0].instrument.as_str(),pepe[0].price_scale),("A-1000PEPE",Some(1000)));
 }

 #[test]
 fn listed_is_only_false_when_every_table_says_so() {
  let tables=fake();
  assert_eq!(listed_in(&tables,"BTC",NOW),Some(true));
  assert_eq!(listed_in(&tables,"NOSUCHCOIN",NOW),Some(false));
  let mut partial=fake();
  partial[1].1=None;
  assert_eq!(listed_in(&partial,"BTC",NOW),Some(true));
  assert_eq!(listed_in(&partial,"NOSUCHCOIN",NOW),None,"有一张还没拉到：判不了");
 }

 #[test]
 fn base_is_checked() {
  for good in ["BTC","1000PEPE","A","DOGE","ABCDEFGHIJKLMNOPQRST"] {assert!(valid_base(good),"{good}");}
  for bad in ["","btc","BTC-USD","BTC_USD","ABCDEFGHIJKLMNOPQRSTU","中文","BTC USD"] {assert!(!valid_base(bad),"{bad}");}
 }

 #[tokio::test]
 async fn bad_base_is_400_and_the_reply_carries_cache_control() {
  use axum::{body::Body,http::{Request,StatusCode}};
  use http_body_util::BodyExt;
  use tower::ServiceExt;
  let app=||Router::<()>::new().route(PATH,get(instruments));
  for (query,code) in [("","invalid_query"),("base=btc","invalid_base"),("base=BTC-USDT","invalid_base"),("base=BTC&x=1","invalid_query")] {
   let reply=app().oneshot(Request::builder().uri(format!("{PATH}?{query}")).body(Body::empty()).unwrap()).await.unwrap();
   assert_eq!(reply.status(),StatusCode::BAD_REQUEST,"{query}");
   let body:Value=serde_json::from_slice(&reply.into_body().collect().await.unwrap().to_bytes()).unwrap();
   assert_eq!(body["error"]["code"],code,"{query}");
  }
  // 答复的形状（不经网络：直接拿假表拼）。
  let response=reply("BTC",pick(&fake(),"BTC",NOW),NOW);
  assert_eq!(response.headers()[header::CACHE_CONTROL],"max-age=60");
  let body:Value=serde_json::from_slice(&response.into_body().collect().await.unwrap().to_bytes()).unwrap();
  assert_eq!(body["base"],"BTC");
  assert_eq!(body["asOfMs"],NOW);
  assert_eq!(body["venues"][0],json!({"exchange":"a","product":"usdtPerp","instrument":"A-BTC-P","notional":{"kind":"linear","multiplier":1.0},"tick":0.1}));
  assert_eq!(body["venues"].as_array().unwrap().len(),3);
 }
 #[tokio::test(start_paused=true)]
 async fn the_table_loops_stop_after_an_idle_hour_and_come_back_on_the_next_request() {
  use std::sync::atomic::{AtomicUsize,Ordering};
  static FETCHES:AtomicUsize=AtomicUsize::new(0);
  let fetches=||FETCHES.load(Ordering::SeqCst);
  let source=TableSource{name:"test",exchange:ExchangeKey("test"),scaled:false,fetch:||Box::pin(async {
   FETCHES.fetch_add(1,Ordering::SeqCst);
   let mut table=Table::new();
   table.insert("BTC".into(),Vec::new());
   Ok(table)
  })};
  let minutes=|n:u64|Duration::from_secs(n*60);
  let book=Book::new(vec![source],Pace{fresh:minutes(10),retry:Duration::from_secs(30),idle:minutes(60)});
  assert_eq!(fetches(),0,"建好不拉，第一个请求来了才拉");

  // 第 0 分钟有人问：拉一轮，之后每 10 分钟一轮。
  let first=snapshot(&book).await;
  assert!(first[0].1.is_some());
  assert_eq!(fetches(),1);
  // 第 30 分钟又有人问：停的时间往后顺延到 90 分钟之后。
  tokio::time::sleep(minutes(30)+Duration::from_secs(1)).await;
  assert_eq!(fetches(),4,"0、10、20、30");
  snapshot(&book).await;
  tokio::time::sleep(minutes(60)).await;
  assert_eq!(fetches(),10,"一直拉到第 90 分钟：40、50、60、70、80、90");
  // 第 100 分钟醒来一看，最近一小时（30 分钟那次之后）没人问：不再拉，循环停了。
  tokio::time::sleep(minutes(11)).await;
  assert_eq!(fetches(),10,"第 100 分钟不再出站");
  assert!(!book.activity.lock().unwrap().running[0]);
  tokio::time::sleep(minutes(180)).await;
  assert_eq!(fetches(),10,"停了就一直停着");

  // 下一次请求：手上那份旧表立刻答复（不等），同时循环重新起、马上拉一轮。
  let asked_at=Instant::now();
  let again=snapshot(&book).await;
  assert_eq!(Instant::now(),asked_at,"不等第一轮");
  assert!(again[0].1.is_some(),"停掉时手上那份表还在");
  tokio::task::yield_now().await;
  assert_eq!(fetches(),11,"重新起来的循环马上拉一轮");
  assert!(book.activity.lock().unwrap().running[0]);
  snapshot(&book).await;
  tokio::task::yield_now().await;
  assert_eq!(fetches(),11,"在跑的循环不重复起");
 }
}
