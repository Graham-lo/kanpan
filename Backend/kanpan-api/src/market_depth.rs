//! 深度快照：`GET /v1/market/depth?symbol=BTCUSDT&limit=1000`。
//!
//! 主力订单流在手机上维护一本簿：订币安合约的增量深度流 `<symbol>@depth@100ms`，再拿
//! 一份 REST 快照按 `U`/`u`/`pu` 对上序号。网关线路上的手机不能自己去拿这份快照——
//! 两台 VPS 在美国，`fapi.binance.com` 对它们回 451——所以由这里经网站主机
//! `www.binance.com/fapi/v1/depth` 取来（和 `market_meta` 里其它 fapi 路径同一个做法），
//! 出站前后都过 `binance_gate` 那条进程级的封禁截止时间。
//!
//! 这一个文件就是整个功能：参数校验、一秒缓存与并发合并、上游错误映射、单测。
//! 路由注册处（`lib.rs`）只接一行。
//!
//! 约定：
//! * 不登录、不碰数据库：行情是公开的。
//! * 币安的 JSON **原样透传**（`lastUpdateId`、`E`、`T`、`bids`、`asks`），不套
//!   `{"data":…}` 信封：手机拿它和直连线路上的同一份快照走同一个解码器。
//! * `limit` 只收 500 或 1000（币安权重 10 / 20），缺省 1000；`symbol` 只收 `[A-Z0-9]{2,30}`。
//! * 每个 (symbol, limit) 缓存一秒，并且合并正在飞的请求：一秒内几台手机切到同一只品种，
//!   上游只挨一次。失败也缓存这一秒，限流的时候不会被十台手机的重试再敲十次。
//! * 上游 451 / 429 / 418、超时、或这个出口正在被封 → 503 + `Retry-After: 2`；
//!   上游 400（没有这个合约）→ 400 `unknown_symbol`；其它 → 502。
use crate::{AppState,binance_gate,error::{ApiError,Params},market_meta};
use axum::{Json,Router,body::Bytes,http::{HeaderValue,StatusCode,header},response::{IntoResponse,Response},routing::get};
use serde::Deserialize;
use serde::de::IgnoredAny;
use serde_json::json;
use std::collections::HashMap;
use std::sync::{Arc,Mutex,OnceLock};
use std::time::Duration;
use tokio::sync::OnceCell;
use tokio::time::Instant;

const PATH:&str="/v1/market/depth";
const UPSTREAM:&str="https://www.binance.com/fapi/v1/depth";
/// 同一只品种的快照在这段时间里被复用。手机拿到快照后还要跟缓冲着的增量流对序号，
/// 一秒前的快照只意味着多丢掉几帧更早的增量，不影响对得上。
const FRESH:Duration=Duration::from_secs(1);
/// 一次取快照最多等多久。手机那边还挂着一条增量流在缓冲，等久了不如让它过两秒重来。
const TIMEOUT:Duration=Duration::from_secs(5);
/// 一个没取完就被丢下的槽位（请求在半路被客户端断开）最多留多久。
const ABANDONED:Duration=Duration::from_secs(30);
const RETRY_AFTER:&str="2";
const LIMITS:[u16;2]=[500,1000];

/// 一次取快照的结局。三种失败对手机的意义不同，所以分开：
#[derive(Clone,Debug,PartialEq)]
enum Failure {
 /// 上游说「现在不行」（451 地区限制、429 / 418 限流或封禁、超时、这个出口正被封着）。
 /// 手机该过两秒再来。
 Busy,
 /// 上游说这个合约不存在（币安对未知 symbol 回 400 `-1121`）。重试也没用。
 Unknown,
 /// 其它一切：上游 5xx、连不上、200 了但给的不是一本簿。
 Broken,
}
type Outcome=Result<Bytes,Failure>;

#[derive(Default)]
struct Slot {
 answer:OnceCell<Outcome>,
 /// 这份答案是什么时候拿到的；没拿到之前是空的，表示「还在飞」。
 done:OnceLock<Instant>,
 born:OnceLock<Instant>,
}

pub struct Depth {
 base:String,
 timeout:Duration,
 slots:Mutex<HashMap<(String,u16),Arc<Slot>>>,
}

impl Depth {
 fn new(base:impl Into<String>,timeout:Duration)->Self {Self{base:base.into(),timeout,slots:Mutex::new(HashMap::new())}}

 /// 这一只品种这一档的快照：一秒内的答案直接复用，正在飞的请求直接跟上。
 async fn snapshot(&self,symbol:&str,limit:u16)->Outcome {
  let slot={
   let mut slots=self.slots.lock().unwrap_or_else(|e|e.into_inner());
   let now=Instant::now();
   // 顺手清掉过期的：答完超过一秒的、以及飞了很久还没人答完的（发起它的请求半路被断开，
   // 后面又没人来接）。表的大小因此只和「最近一秒里被问到的品种数」有关。
   slots.retain(|_,slot| match slot.done.get() {
    Some(at)=>now.duration_since(*at)<FRESH,
    None=>slot.born.get().is_none_or(|born|now.duration_since(*born)<ABANDONED),
   });
   slots.entry((symbol.to_owned(),limit)).or_insert_with(|| {
    let slot=Slot::default();
    let _=slot.born.set(now);
    Arc::new(slot)
   }).clone()
  };
  // 第一个进来的去取，同一刻的其它请求在这里等同一个结果。发起者半路被断开时，
  // `OnceCell` 会让下一个等着的人接手去取，不会让大家一起卡住。
  slot.answer.get_or_init(|| async {
   let outcome=self.fetch(symbol,limit).await;
   let _=slot.done.set(Instant::now());
   outcome
  }).await.clone()
 }

 async fn fetch(&self,symbol:&str,limit:u16)->Outcome {
  let url=format!("{}?symbol={symbol}&limit={limit}",self.base);
  let gated=binance_gate::covers(&url);
  // 出口正被币安封着就连门都不敲：封禁期里继续敲，换来的只是封得更久。
  if gated&&binance_gate::blocked() {return Err(Failure::Busy)}
  let response=match market_meta::http().get(&url).timeout(self.timeout).send().await {
   Ok(response)=>response,
   Err(e) if e.is_timeout()=>return Err(Failure::Busy),
   Err(e)=>{tracing::warn!("Depth snapshot: upstream unreachable: {e}");return Err(Failure::Broken)}
  };
  // 429 / 418 记进那条全进程共用的截止时间，板块历史、OI 归档跟着一起歇。
  if gated {binance_gate::note_reply(&response);}
  match response.status().as_u16() {
   200=>{},
   451|429|418=>return Err(Failure::Busy),
   400=>return Err(Failure::Unknown),
   status=>{tracing::warn!("Depth snapshot: upstream answered {status}");return Err(Failure::Broken)}
  }
  let body=match response.bytes().await {
   Ok(body)=>body,
   Err(e) if e.is_timeout()=>return Err(Failure::Busy),
   Err(_)=>return Err(Failure::Broken),
  };
  // 200 也不一定是一本簿（网站前门偶尔回一张挑战页）。原样透传之前只核对形状，不改字节。
  if !is_book(&body) {tracing::warn!("Depth snapshot: upstream 200 was not an order book");return Err(Failure::Broken)}
  Ok(body)
 }
}

/// 形状对不对：有 `lastUpdateId`，`bids` / `asks` 是数组。
fn is_book(body:&[u8])->bool {
 #[derive(Deserialize)]
 struct Book {#[serde(rename="lastUpdateId")] _last_update_id:u64,#[serde(rename="bids")] _bids:Vec<IgnoredAny>,#[serde(rename="asks")] _asks:Vec<IgnoredAny>}
 serde_json::from_slice::<Book>(body).is_ok()
}

fn valid_symbol(symbol:&str)->bool {
 (2..=30).contains(&symbol.len())&&symbol.bytes().all(|b|b.is_ascii_uppercase()||b.is_ascii_digit())
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct DepthQuery {symbol:String,limit:Option<u16>}

fn answer(outcome:Outcome)->Response {
 let refuse=|status:StatusCode,code:&str|(status,Json(json!({"error":{"code":code}}))).into_response();
 match outcome {
  Ok(body)=>{
   let mut reply=body.into_response();
   let headers=reply.headers_mut();
   headers.insert(header::CONTENT_TYPE,HeaderValue::from_static("application/json"));
   // 一秒前的簿已经是旧的了；别让任何一层缓存把它存下来再发一次。
   headers.insert(header::CACHE_CONTROL,HeaderValue::from_static("no-store"));
   reply
  },
  Err(Failure::Busy)=>{
   let mut reply=refuse(StatusCode::SERVICE_UNAVAILABLE,"market_upstream_unavailable");
   reply.headers_mut().insert(header::RETRY_AFTER,HeaderValue::from_static(RETRY_AFTER));
   reply
  },
  Err(Failure::Unknown)=>refuse(StatusCode::BAD_REQUEST,"unknown_symbol"),
  Err(Failure::Broken)=>refuse(StatusCode::BAD_GATEWAY,"market_upstream_failed"),
 }
}

async fn serve(depth:&Depth,query:DepthQuery)->Response {
 if !valid_symbol(&query.symbol) {return ApiError::bad("invalid_symbol").into_response()}
 let limit=query.limit.unwrap_or(1000);
 if !LIMITS.contains(&limit) {return ApiError::bad("invalid_limit").into_response()}
 answer(depth.snapshot(&query.symbol,limit).await)
}

fn shared()->Arc<Depth> {
 static D:OnceLock<Arc<Depth>>=OnceLock::new();
 D.get_or_init(||Arc::new(Depth::new(UPSTREAM,TIMEOUT))).clone()
}

fn routes_with<S:Clone+Send+Sync+'static>(depth:Arc<Depth>)->Router<S> {
 Router::new().route(PATH,get(move|Params(query):Params<DepthQuery>| {
  let depth=depth.clone();
  async move {serve(&depth,query).await}
 }))
}
pub fn routes()->Router<AppState> {routes_with(shared())}

#[cfg(test)]
mod tests {
 use super::*;
 use axum::{body::Body,extract::{RawQuery,State},http::Request};
 use http_body_util::BodyExt;
 use std::sync::atomic::{AtomicUsize,Ordering};
 use tower::ServiceExt;

 const BOOK:&str=r#"{"lastUpdateId":11640260107234,"E":1790000000123,"T":1790000000100,"bids":[["95000.10","1.234"],["95000.00","0.500"]],"asks":[["95000.20","0.800"]]}"#;

 /// 假的币安：数被问了几次、记下最后一次的查询串，按设定的状态码 / 正文 / 延迟回答。
 struct Fake {hits:AtomicUsize,query:Mutex<String>,reply:Mutex<(u16,&'static str,Duration)>}
 async fn fake_depth(State(fake):State<Arc<Fake>>,RawQuery(query):RawQuery)->Response {
  fake.hits.fetch_add(1,Ordering::SeqCst);
  *fake.query.lock().unwrap()=query.unwrap_or_default();
  let (status,body,delay)=*fake.reply.lock().unwrap();
  tokio::time::sleep(delay).await;
  (StatusCode::from_u16(status).unwrap(),body).into_response()
 }
 /// 起一个假上游，返回它和一个指向它的 `Depth`。`path` 决定这个 URL 过不过 `binance_gate`。
 async fn upstream(path:&str,timeout:Duration)->(Arc<Fake>,Arc<Depth>) {
  let fake=Arc::new(Fake{hits:AtomicUsize::new(0),query:Mutex::new(String::new()),reply:Mutex::new((200,BOOK,Duration::ZERO))});
  let app=Router::new().fallback(fake_depth).with_state(fake.clone());
  let listener=tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
  let port=listener.local_addr().unwrap().port();
  tokio::spawn(async move {axum::serve(listener,app).await.unwrap()});
  (fake,Arc::new(Depth::new(format!("http://127.0.0.1:{port}{path}"),timeout)))
 }
 fn set(fake:&Fake,status:u16,body:&'static str,delay:Duration) {*fake.reply.lock().unwrap()=(status,body,delay);}

 async fn call(depth:&Arc<Depth>,query:&str)->(StatusCode,Option<String>,String) {
  let request=Request::builder().uri(format!("{PATH}?{query}")).body(Body::empty()).unwrap();
  let reply=routes_with::<()>(depth.clone()).oneshot(request).await.unwrap();
  let status=reply.status();
  let retry=reply.headers().get(header::RETRY_AFTER).map(|v|v.to_str().unwrap().to_owned());
  let body=reply.into_body().collect().await.unwrap().to_bytes();
  (status,retry,String::from_utf8(body.to_vec()).unwrap())
 }
 fn code(body:&str)->String {serde_json::from_str::<serde_json::Value>(body).unwrap()["error"]["code"].as_str().unwrap().to_owned()}

 #[tokio::test]
 async fn bad_parameters_are_refused_before_anything_goes_upstream() {
  let (fake,depth)=upstream("/fapi/v1/depth",TIMEOUT).await;
  let cases=[
   ("","invalid_query"),                              // 没有 symbol
   ("symbol=btcusdt","invalid_symbol"),               // 小写
   ("symbol=B","invalid_symbol"),                     // 太短
   (&*format!("symbol={}","A".repeat(31)),"invalid_symbol"),
   ("symbol=BTC-USDT","invalid_symbol"),
   ("symbol=BTC%2FUSDT","invalid_symbol"),
   ("symbol=BTC%20USDT","invalid_symbol"),
   ("symbol=%E4%B8%AD%E6%96%87","invalid_symbol"),
   ("symbol=BTCUSDT&limit=100","invalid_limit"),
   ("symbol=BTCUSDT&limit=5000","invalid_limit"),
   ("symbol=BTCUSDT&limit=0","invalid_limit"),
   ("symbol=BTCUSDT&limit=abc","invalid_query"),
   ("symbol=BTCUSDT&limit=-1","invalid_query"),
   ("symbol=BTCUSDT&limit=99999999","invalid_query"),
   ("symbol=BTCUSDT&extra=1","invalid_query"),         // 多给的参数
  ];
  for (query,expected) in cases {
   let (status,_,body)=call(&depth,query).await;
   assert_eq!(status,StatusCode::BAD_REQUEST,"{query}");
   assert_eq!(code(&body),expected,"{query}");
  }
  assert_eq!(fake.hits.load(Ordering::SeqCst),0,"参数不对的请求一次都不该打到上游");
  // 两档合法的 limit 都放行，缺省是 1000。
  for (query,sent) in [("symbol=BTCUSDT&limit=500","symbol=BTCUSDT&limit=500"),("symbol=ETHUSDT&limit=1000","symbol=ETHUSDT&limit=1000"),("symbol=1000PEPEUSDT","symbol=1000PEPEUSDT&limit=1000")] {
   let (status,_,_)=call(&depth,query).await;
   assert_eq!(status,StatusCode::OK,"{query}");
   assert_eq!(*fake.query.lock().unwrap(),sent);
  }
 }

 #[tokio::test]
 async fn the_book_is_passed_through_byte_for_byte() {
  let (_,depth)=upstream("/fapi/v1/depth",TIMEOUT).await;
  let request=Request::builder().uri(format!("{PATH}?symbol=BTCUSDT&limit=1000")).body(Body::empty()).unwrap();
  let reply=routes_with::<()>(depth).oneshot(request).await.unwrap();
  assert_eq!(reply.status(),StatusCode::OK);
  assert_eq!(reply.headers()[header::CONTENT_TYPE],"application/json");
  assert_eq!(reply.headers()[header::CACHE_CONTROL],"no-store");
  let body=reply.into_body().collect().await.unwrap().to_bytes();
  assert_eq!(&body[..],BOOK.as_bytes(),"不套信封、不改字段、不改数字的写法");
 }

 #[tokio::test]
 async fn clients_arriving_within_a_second_share_one_upstream_call() {
  let (fake,depth)=upstream("/fapi/v1/depth",TIMEOUT).await;
  // 上游慢一点，保证十个请求真的是在同一次取数的途中到达的。
  set(&fake,200,BOOK,Duration::from_millis(200));
  let calls:Vec<_>=(0..10).map(|_|{let depth=depth.clone();tokio::spawn(async move {call(&depth,"symbol=BTCUSDT&limit=1000").await})}).collect();
  for call in calls {
   let (status,_,body)=call.await.unwrap();
   assert_eq!(status,StatusCode::OK);
   assert_eq!(body,BOOK);
  }
  assert_eq!(fake.hits.load(Ordering::SeqCst),1,"同时到的十个请求只打上游一次");
  // 答完之后一秒内再来，照样用那一份。
  set(&fake,200,BOOK,Duration::ZERO);
  assert_eq!(call(&depth,"symbol=BTCUSDT&limit=1000").await.0,StatusCode::OK);
  assert_eq!(fake.hits.load(Ordering::SeqCst),1);
  // 别的品种、别的档位是另一份。
  call(&depth,"symbol=ETHUSDT&limit=1000").await;
  call(&depth,"symbol=BTCUSDT&limit=500").await;
  assert_eq!(fake.hits.load(Ordering::SeqCst),3);
  // 过了一秒，重新取。
  tokio::time::sleep(FRESH+Duration::from_millis(100)).await;
  assert_eq!(call(&depth,"symbol=BTCUSDT&limit=1000").await.0,StatusCode::OK);
  assert_eq!(fake.hits.load(Ordering::SeqCst),4,"过期的快照不再复用");
  assert!(depth.slots.lock().unwrap().len()<=2,"过期的槽位被清掉，表不会越攒越大");
 }

 #[tokio::test]
 async fn upstream_refusals_map_to_what_the_phone_should_do() {
  let (fake,depth)=upstream("/fapi/v1/depth",Duration::from_millis(300)).await;
  let cases:[(u16,&'static str,Duration,StatusCode,&str);8]=[
   (451,r#"{"code":0,"msg":"restricted location"}"#,Duration::ZERO,StatusCode::SERVICE_UNAVAILABLE,"market_upstream_unavailable"),
   (429,r#"{"code":-1003}"#,Duration::ZERO,StatusCode::SERVICE_UNAVAILABLE,"market_upstream_unavailable"),
   (418,r#"{"code":-1003}"#,Duration::ZERO,StatusCode::SERVICE_UNAVAILABLE,"market_upstream_unavailable"),
   (200,BOOK,Duration::from_secs(2),StatusCode::SERVICE_UNAVAILABLE,"market_upstream_unavailable"), // 超时
   (400,r#"{"code":-1121,"msg":"Invalid symbol."}"#,Duration::ZERO,StatusCode::BAD_REQUEST,"unknown_symbol"),
   (500,"oops",Duration::ZERO,StatusCode::BAD_GATEWAY,"market_upstream_failed"),
   (502,"",Duration::ZERO,StatusCode::BAD_GATEWAY,"market_upstream_failed"),
   (200,"<html>challenge</html>",Duration::ZERO,StatusCode::BAD_GATEWAY,"market_upstream_failed"), // 200 但不是簿
  ];
  // 每一种用一只不同的品种，免得撞上前一种留下的一秒缓存。
  for (i,(status,body,delay,expected,expected_code)) in cases.into_iter().enumerate() {
   set(&fake,status,body,delay);
   let symbol=format!("CASE{i}USDT");
   let (got,retry,reply)=call(&depth,&format!("symbol={symbol}")).await;
   assert_eq!(got,expected,"upstream {status} after {delay:?}");
   assert_eq!(code(&reply),expected_code,"upstream {status}");
   assert_eq!(retry.as_deref(),(expected==StatusCode::SERVICE_UNAVAILABLE).then_some(RETRY_AFTER),"只有 503 带 Retry-After: 2");
  }
  // 连不上：一个没人听的端口。
  let nobody=Arc::new(Depth::new("http://127.0.0.1:1/fapi/v1/depth",Duration::from_millis(300)));
  let (got,_,reply)=call(&nobody,"symbol=BTCUSDT").await;
  assert_eq!((got,code(&reply).as_str()),(StatusCode::BAD_GATEWAY,"market_upstream_failed"));
 }

 #[tokio::test]
 async fn a_failure_is_also_held_for_a_second_so_retries_do_not_hammer_upstream() {
  let (fake,depth)=upstream("/fapi/v1/depth",TIMEOUT).await;
  set(&fake,451,"{}",Duration::ZERO);
  for _ in 0..5 {assert_eq!(call(&depth,"symbol=BTCUSDT").await.0,StatusCode::SERVICE_UNAVAILABLE);}
  assert_eq!(fake.hits.load(Ordering::SeqCst),1);
  tokio::time::sleep(FRESH+Duration::from_millis(100)).await;
  set(&fake,200,BOOK,Duration::ZERO);
  assert_eq!(call(&depth,"symbol=BTCUSDT").await.0,StatusCode::OK,"一秒之后上游好了就照常答");
 }

 /// 币安的 429 要按下全进程那道闸；闸按着的时候别的品种连出站都不出。
 // 跨 await 持有是故意的：这把锁就是「同时只许一条测试碰那道进程级闸门」的实现。
 #[allow(clippy::await_holding_lock)]
 #[tokio::test]
 async fn a_binance_rate_limit_closes_the_shared_gate_for_every_symbol() {
  let _serial=binance_gate::test_lock().lock().unwrap_or_else(|e|e.into_inner());
  binance_gate::clear();
  // 路径里带 `.binance.com/`，`binance_gate::covers` 就认它是币安。
  let (fake,depth)=upstream("/www.binance.com/fapi/v1/depth",TIMEOUT).await;
  set(&fake,429,"{}",Duration::ZERO);
  let (status,retry,_)=call(&depth,"symbol=BTCUSDT").await;
  assert_eq!((status,retry.as_deref()),(StatusCode::SERVICE_UNAVAILABLE,Some(RETRY_AFTER)));
  assert!(binance_gate::blocked(),"币安的 429 按下全进程那道闸");
  set(&fake,200,BOOK,Duration::ZERO);
  assert_eq!(call(&depth,"symbol=ETHUSDT").await.0,StatusCode::SERVICE_UNAVAILABLE);
  assert_eq!(fake.hits.load(Ordering::SeqCst),1,"封禁期内别的品种不出站");
  binance_gate::clear();
  assert_eq!(call(&depth,"symbol=SOLUSDT").await.0,StatusCode::OK);
  binance_gate::clear();
 }
}
