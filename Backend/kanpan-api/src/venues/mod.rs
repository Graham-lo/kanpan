//! 交易所在服务端的那一截：**一家一个目录，一处注册**。
//!
//! 每家交易所是一个实现了 [`Venue`] 的单元结构，登记在 [`venues`] 那张表里——那是唯一的清单：
//! 币安、OKX、Bybit、Hyperliquid、Coinbase、美元指数。`/v1/market/{raw,stream,funding,open-interest/history}`
//! 与 `market_meta` 的持仓量只按 `source=` 查表分发；同步校验认哪些 `(venue, market)`、代号长什么样，
//! 提醒的 `market` 白名单、深链与通知里的品种名、复盘支不支持、`/v1/market/meta` 的代号怎么折 base，
//! 全部问这张表，不再在各处手抄字面量。
//!
//! 一家目录里有什么（见 `docs/多交易所-接入指南.md`）：
//!
//! - `mod.rs`：SOURCE、主机、**唯一的出站节拍 `PACER`**（透传、补缺 K 线、订单流品种表、持仓量 /
//!   费率，这一家的 REST 全经它，见 [`outbound`]）、透传白名单、`candles`、持仓量 / 费率；
//! - `relay.rs`：`/v1/market/ws/<id>` 中继的上行白名单（传输与名额在 `market_relay`）；
//! - `orderflow.rs`：主力订单流的品种表；
//! - `alerts.rs`：服务端提醒评估用的 1 分钟 K 线来源（实现 `alerts::KlineFeed`）。
//!
//! 接一家：建目录，实现 [`Venue`]，在 [`venues`] 里加一行。改一家、删一家只碰它自己的目录和这一行。
//!
//! 不混源：任何一家的数据缺了就是缺了，不拿别家顶（以前 OKX 是币安永续在网关线路上的「替身」，
//! 2026-10-08 起 OKX 只答它自己的品种）。
//!
//! 挂在 `/v1/market/` 下而不是 `/market/`：后者在 Caddy 上整段归 Python 网关。
use axum::body::Bytes;
use axum::extract::{Path,Query,ws::WebSocketUpgrade};
use axum::http::StatusCode;
use axum::response::{IntoResponse,Response};
use axum::{Router,routing::get};
use serde_json::{Value,json};
use std::future::Future;
use std::pin::Pin;

pub mod binance;
pub mod bybit;
pub mod coinbase;
pub mod hyperliquid;
pub mod macro_index;
pub mod okx;
pub mod orderflow;
pub mod outbound;

use outbound::{Pacer,Upstream};

/// 装箱的 future（`Venue` 要做成 `dyn`，方法返回值只能是这个）。
pub type Fut<'a,T>=Pin<Box<dyn Future<Output=T>+Send+'a>>;

/// 一根中立的 K 线：开盘时刻（毫秒）与浮点价。提醒补缺用，谁用谁再映射。
#[derive(Clone,Debug,PartialEq)]
pub struct Bar {pub open_time:i64,pub open:f64,pub high:f64,pub low:f64,pub close:f64,pub volume:f64}
impl Bar {
 /// 价都是有限正数、高不低于低。上游偶尔给半根坏行，不让它进判定。
 pub fn sane(&self)->bool {
  [self.open,self.high,self.low,self.close].iter().all(|p|p.is_finite()&&*p>0.0)&&self.high>=self.low&&self.volume.is_finite()
 }
}

/// 一家交易所。能做的就实现，做不了的留默认（「没有」）：上层不写 `if venue ==`。
pub trait Venue:Sync {
 /// `source=` 的值，也是同步对象里的 `venue`（`okx`）。
 fn source(&self)->&'static str;
 /// 三端统一的展示缩写（用户定的文字）：币安「币安」、OKX「OKX」、Bybit「Bybit」、Hyperliquid「HL」、
 /// Coinbase「CB」、美元指数不带（空串）。通知标题、Webhook 的品种名都以它开头。
 fn short_name(&self)->&'static str;
 /// 这一家在看盘里的市场：永续一律 `usd_m`，现货 `spot`，指数 `index`。
 fn market(&self)->&'static str;
 /// 提醒对象的整串 `market`：`okx/usd_m`。
 fn market_key(&self)->&'static str;
 /// 这家的代号长什么样（同步校验、透传、提醒都按它认）。
 fn symbol_ok(&self,symbol:&str)->bool;
 /// 复盘（历史行情、找相似的公开历史）接不接这家。本次只有币安与 Coinbase。
 fn review(&self)->bool {false}
 /// 通知标题里的品种名：缩写 + 空格 + 代号（「币安 BTCUSDT」「OKX BTCUSDT」）。
 fn display(&self,symbol:&str)->String {labeled(self.short_name(),symbol)}
 /// Webhook 的 `{品种}` 与载荷里的 `name`：**不带**交易所缩写（「BTC」「BTC/USD」）。这段文本客户端
 /// `AlertMessage.swift` 前台也渲染一遍、两边要一字不差，而 KanpanCore 拿不到缩写表；Webhook 载荷又是对外接口。
 fn webhook_name(&self,symbol:&str)->String {symbol.to_owned()}
 /// 深链里写裸代号（只有币安：老客户端只认那种）；别家写完整的 `venue/market/symbol`。
 fn bare_link(&self)->bool {false}
 /// `/v1/market/meta` 怎么查这只的供应量：给出那张表认得的代号（币安合约形状 `BTCUSDT`，
 /// 或者 Coinbase 现货 `BTC-USD`）；`None` 就是不答。
 fn meta_symbol(&self,symbol:&str)->Option<String> {Some(symbol.to_owned())}
 /// 这一家唯一的出站节拍（币安不用它，见 `outbound` 的说明）。
 fn pacer(&self)->Option<&'static Pacer> {None}
 /// 这一家的 REST 主机：通用取数口按它认出该排哪一家的队。
 fn hosts(&self)->&'static [&'static str] {&[]}
 /// 一笔出站占几格节拍（Hyperliquid 按权重记，其余一律 1）。
 fn cost(&self,_path:&str,_body:Option<&Value>)->u32 {1}
 /// `GET /v1/market/raw/<path>?source=<id>&…` 原样透传。
 fn raw<'a>(&'a self,_path:&'a str,_query:&'a [(String,String)])->Fut<'a,Response> {
  Box::pin(async {outbound::refuse(StatusCode::NOT_FOUND,"unsupported_path")})
 }
 /// `POST /v1/market/raw/<path>?source=<id>` 带 JSON 正文（Hyperliquid 的 `info`）。
 fn raw_post<'a>(&'a self,_path:&'a str,_body:Bytes)->Fut<'a,Response> {
  Box::pin(async {outbound::refuse(StatusCode::METHOD_NOT_ALLOWED,"unsupported_method")})
 }
 /// `/v1/market/stream?source=<id>` 推送 hub；没有就是 `None`。
 fn stream(&self,_ws:WebSocketUpgrade,_query:&[(String,String)])->Option<Response> {None}
 /// `[start, end)`（秒）里的原生 K 线，升序；`step` 秒一根（1 分钟必须支持）。没成交的那几根
 /// 有的交易所不给，缺着就缺着。
 fn candles<'a>(&'a self,_symbol:&'a str,_step:i64,_start:i64,_end:i64)->Fut<'a,Result<Vec<Bar>,Upstream>> {
  Box::pin(async {Err(Upstream::Rejected(404))})
 }
 /// 一只的当前持仓量（`/v1/market/open-interest?source=<id>`）。
 fn open_interest<'a>(&'a self,_symbol:&'a str)->Option<Fut<'a,crate::error::Result<crate::market_meta::OpenInterest>>> {None}
 /// 整张资金费率表（`/v1/market/funding?source=<id>`），答复 `{"source":…,"rows":[{symbol,rate,nextFundingTime}]}`，
 /// `symbol` 是这一家的看盘键，`rate` 是一期的费率。一期默认 8 小时（OKX、Bybit）、不带别的键；
 /// 一期不是 8 小时的那家多带一个 `"intervalHours"`——目前只有 Hyperliquid（每小时结算，`"intervalHours":1`）。
 fn funding(&self)->Option<Fut<'static,crate::error::Result<Value>>> {None}
 /// 持仓量历史（`/v1/market/open-interest/history?source=<id>`）。
 fn oi_history<'a>(&'a self,_query:&'a [(String,String)])->Option<Fut<'a,Response>> {None}
 /// 服务端提醒评估用的 1 分钟 K 线来源。币安走 `alerts::run`（它多一条实时活动的 ticker），
 /// 美元指数读库（`alerts::run_macro`），都不经这里。
 fn alert_feed(&self)->Option<&'static dyn crate::alerts::KlineFeed> {None}
}

/// 缩写 + 空格 + 名字；缩写是空的（美元指数）就只有名字。
pub fn labeled(short:&str,name:&str)->String {if short.is_empty() {name.to_owned()} else {format!("{short} {name}")}}
/// U 本位永续的短名：去掉尾巴上的 `USDT`（没有这个尾巴就原样）。
pub fn without_usdt(symbol:&str)->&str {symbol.strip_suffix("USDT").filter(|b|!b.is_empty()).unwrap_or(symbol)}

/// 唯一的交易所清单。顺序就是搜索分区与日志里的先后。
pub fn venues()->&'static [&'static dyn Venue] {
 static ALL:[&dyn Venue;6]=[&binance::BINANCE,&okx::OKX,&bybit::BYBIT,&hyperliquid::HYPERLIQUID,&coinbase::COINBASE,&macro_index::MACRO];
 &ALL
}
/// 按 `source` / `venue` 找一家。
pub fn venue(source:&str)->Option<&'static dyn Venue> {venues().iter().copied().find(|v|v.source()==source)}
/// 按 `(venue, market)` 找一家：两段都对上才算（`binance/spot` 不是一家）。
pub fn listed(venue:&str,market:&str)->Option<&'static dyn Venue> {venues().iter().copied().find(|v|v.source()==venue&&v.market()==market)}
/// 按提醒对象的整串 `market`（`okx/usd_m`）找一家。
pub fn by_market_key(key:&str)->Option<&'static dyn Venue> {venues().iter().copied().find(|v|v.market_key()==key)}

/// 这一族路由都不读数据库（美元指数例外：库连接由它的采集任务放进模块，没起采集的备用主机上答 503），
/// 所以 API 主机与只答持仓量的备用主机挂的是同一份。
pub fn routes<S:Clone+Send+Sync+'static>()->Router<S> {
 Router::new()
  .route("/v1/market/raw/{*path}",get(raw).post(raw_post))
  .route("/v1/market/stream",get(stream))
  .route("/v1/market/funding",get(funding))
  .route("/v1/market/open-interest/history",get(oi_history))
}

fn param<'a>(query:&'a [(String,String)],key:&str)->Option<&'a str> {
 query.iter().find(|(k,_)|k==key).map(|(_,v)|v.as_str())
}
fn source_of(query:&[(String,String)])->Option<&'static dyn Venue> {param(query,"source").and_then(venue)}
fn unsupported()->Response {
 (StatusCode::BAD_REQUEST,axum::Json(json!({"error":"unsupported_source"}))).into_response()
}

async fn raw(Path(path):Path<String>,Query(query):Query<Vec<(String,String)>>)->Response {
 match source_of(&query) {Some(v)=>v.raw(&path,&query).await,None=>unsupported()}
}
/// 正文最多这么大：Hyperliquid 的 `info` 请求是几十个字节。
const RAW_BODY_MAX:usize=2048;
async fn raw_post(Path(path):Path<String>,Query(query):Query<Vec<(String,String)>>,body:Bytes)->Response {
 let Some(v)=source_of(&query) else {return unsupported()};
 if body.len()>RAW_BODY_MAX {return outbound::refuse(StatusCode::PAYLOAD_TOO_LARGE,"body_too_large")}
 v.raw_post(&path,body).await
}

/// 整张资金费率表：手机一分钟来问一次，每家各给各的。
async fn funding(Query(query):Query<Vec<(String,String)>>)->Response {
 match source_of(&query).and_then(|v|v.funding()) {
  Some(table)=>match table.await {Ok(body)=>crate::envelope(body).into_response(),Err(e)=>e.into_response()},
  None=>unsupported(),
 }
}

/// 持仓量历史。目前只有 OKX 有（rubik 统计接口）；Bybit 的走透传，Hyperliquid 没有。
async fn oi_history(Query(query):Query<Vec<(String,String)>>)->Response {
 match source_of(&query).and_then(|v|v.oi_history(&query)) {Some(answer)=>answer.await,None=>unsupported()}
}

async fn stream(ws:WebSocketUpgrade,Query(query):Query<Vec<(String,String)>>)->Response {
 // 上行帧的大小上限同中继（手机往 hub 发的只有几百字节的订阅）。
 match source_of(&query) {Some(v)=>v.stream(crate::market_relay::small_frames(ws),&query).unwrap_or_else(unsupported),None=>unsupported()}
}

/// 代号只收字母、数字和连字符：它会被拼进上游地址。
pub fn symbol_param(query:&[(String,String)])->Option<&str> {
 param(query,"symbol").filter(|s|!s.is_empty()&&s.len()<=40&&s.chars().all(|c|c.is_ascii_alphanumeric()||c=='-'))
}
pub(crate) fn bad(code:&'static str)->Response {crate::error::ApiError::bad(code).into_response()}
pub(crate) fn query_param<'a>(query:&'a [(String,String)],key:&str)->Option<&'a str> {param(query,key)}

/// 看盘键里的代号：ASCII 大写字母与数字，`len` 字节以内（OKX / Bybit 的 `BTCUSDT`、Hyperliquid 的 `KPEPE`）。
pub fn upper_alnum(symbol:&str,len:std::ops::RangeInclusive<usize>)->bool {
 len.contains(&symbol.len())&&symbol.bytes().all(|b|b.is_ascii_uppercase()||b.is_ascii_digit())
}

#[cfg(test)]
mod tests {
 use super::*;

 #[test] fn the_registry_is_the_one_list() {
  let got:Vec<(&str,&str,&str,bool)>=venues().iter().map(|v|(v.source(),v.market(),v.market_key(),v.review())).collect();
  assert_eq!(got,vec![
   ("binance","usd_m","binance/usd_m",true),("okx","usd_m","okx/usd_m",false),("bybit","usd_m","bybit/usd_m",false),
   ("hyperliquid","usd_m","hyperliquid/usd_m",false),("coinbase","spot","coinbase/spot",true),("macro","index","macro/index",false),
  ]);
  for v in venues() {assert_eq!(v.market_key(),format!("{}/{}",v.source(),v.market()),"{}",v.source())}
  assert!(listed("okx","usd_m").is_some()&&listed("okx","spot").is_none()&&listed("binance","spot").is_none());
  assert_eq!(by_market_key("bybit/usd_m").map(|v|v.source()),Some("bybit"));
  assert!(venue("ftx").is_none());
 }

 /// 每家的代号形状各认各的：同一只币在不同交易所写法不同，互相不收。
 #[test] fn each_venue_knows_its_own_symbols() {
  let ok=|s:&str,sym:&str|venue(s).unwrap().symbol_ok(sym);
  assert!(ok("binance","BTCUSDT")&&ok("okx","BTCUSDT")&&ok("bybit","1000PEPEUSDT")&&ok("hyperliquid","KPEPE")&&ok("coinbase","BTC-USD")&&ok("macro","DXY"));
  assert!(!ok("okx","BTC-USDT-SWAP")&&!ok("okx","BTCUSD")&&!ok("okx","btcusdt"),"OKX 键是币安形状的 USDT 永续");
  assert!(!ok("bybit","BTCUSD")&&!ok("bybit","BTCPERP"),"Bybit 只收 USDT 线性永续");
  assert!(!ok("hyperliquid","kPEPE")&&!ok("hyperliquid","BTC-USD")&&!ok("hyperliquid","@107"),"Hyperliquid 键是大写的 coin 名");
  assert!(!ok("coinbase","BTCUSDT")&&!ok("binance","BTC-USD"));
 }

 /// 只有每家自己的节拍管自己的主机；币安不在这里（它有自己的账本与封禁闸）。
 #[test] fn hosts_map_to_their_venue_pacer() {
  let who=|url:&str|outbound::pacer_for(url).map(|(_,v)|v.source());
  assert_eq!(who("https://www.okx.com/api/v5/public/open-interest?instType=SWAP"),Some("okx"));
  assert_eq!(who("https://api.bytick.com/v5/market/kline"),Some("bybit"));
  assert_eq!(who("https://api.hyperliquid.xyz/info"),Some("hyperliquid"));
  assert_eq!(who("https://api.coinbase.com/api/v3/brokerage/market/products"),Some("coinbase"));
  assert_eq!(who("https://api.exchange.coinbase.com/products"),Some("coinbase"));
  assert_eq!(who("https://www.binance.com/fapi/v1/klines"),None);
  assert_eq!(who("https://api.coingecko.com/api/v3/coins"),None);
  for v in venues() {for h in v.hosts() {assert_eq!(outbound::pacer_for(&format!("https://{h}/x")).map(|(_,o)|o.source()),Some(v.source()))}}
 }

 #[tokio::test] async fn dispatch_goes_by_the_table() {
  use tower::ServiceExt;
  let app=routes::<()>();
  let get=|uri:&str|axum::http::Request::builder().uri(uri).body(axum::body::Body::empty()).unwrap();
  for (uri,status) in [
   ("/v1/market/raw/x?source=ftx",400),
   ("/v1/market/raw/api/v5/account/balance?source=okx",404),
   ("/v1/market/raw/v5/order/create?source=bybit",404),
   ("/v1/market/funding?source=coinbase",400),
   ("/v1/market/open-interest/history?source=bybit&symbol=BTCUSDT&period=5m",400),
   ("/v1/market/open-interest/history?source=okx&symbol=BTCUSDT&period=1m",400),
  ] {
   assert_eq!(app.clone().oneshot(get(uri)).await.unwrap().status().as_u16(),status,"{uri}");
  }
  let post=|uri:&str,body:&'static str|axum::http::Request::builder().method("POST").uri(uri).body(axum::body::Body::from(body)).unwrap();
  assert_eq!(app.clone().oneshot(post("/v1/market/raw/info?source=okx","{}")).await.unwrap().status().as_u16(),405);
  assert_eq!(app.clone().oneshot(post("/v1/market/raw/info?source=hyperliquid",r#"{"type":"userState","user":"0x0"}"#)).await.unwrap().status().as_u16(),400);
 }

 // ---------------------------------------------------------------- 透传白名单模糊测试

 struct Rng(u64);
 impl Rng {
  fn next(&mut self)->u64 {self.0^=self.0<<13;self.0^=self.0>>7;self.0^=self.0<<17;self.0}
  fn pick<'a,T>(&mut self,from:&'a [T])->&'a T {&from[(self.next()%from.len() as u64) as usize]}
  fn chance(&mut self,percent:u64)->bool {self.next()%100<percent}
 }
 /// 一次出站：地址、查询、正文。
 type Seen=std::sync::Arc<std::sync::Mutex<Vec<(String,Vec<(String,String)>,Option<Value>)>>>;
 /// 假出站口：全部记下来，按那一家的「成功」信封答 200。
 fn recorder(seen:Seen)->outbound::fake::Answer {
  std::sync::Arc::new(move|url:&str,query:&[(String,String)],body:Option<&Value>|{
   seen.lock().unwrap().push((url.to_owned(),query.to_vec(),body.cloned()));
   outbound::fake::ok(&json!({"code":"0","retCode":0,"data":[],"result":{"list":[]}}))
  })
 }
 /// 测试自己写的一份白名单（不抄实现）：出站的每一笔都得落在这里面。
 fn egress_ok(url:&str,query:&[(String,String)])->Result<(),String> {
  let (host,path)=url.strip_prefix("https://").and_then(|r|r.split_once('/')).ok_or("不是 https 地址")?;
  let safe=|v:&str,extra:&[u8]|v.len()<=200&&v.bytes().all(|b|b.is_ascii_alphanumeric()||extra.contains(&b));
  let (paths,keys,extra):(&[&str],&[&str],&[u8])=match host {
   "www.okx.com"=>(&["api/v5/public/instruments","api/v5/market/tickers","api/v5/market/ticker","api/v5/market/candles","api/v5/market/history-candles",
     "api/v5/public/funding-rate","api/v5/public/open-interest","api/v5/public/mark-price"],&["instType","instId","instFamily","uly","bar","after","before","limit"],b"-"),
   "api.bybit.com"|"api.bytick.com"=>(&["v5/market/instruments-info","v5/market/tickers","v5/market/kline","v5/market/funding/history","v5/market/open-interest"],
     &["category","symbol","interval","intervalTime","start","end","startTime","endTime","limit","status","cursor"],b"-_=&%.:,"),
   "api.coinbase.com"=>{
    let rest=path.strip_prefix("api/v3/brokerage/market/").ok_or("Coinbase 前缀不对")?;
    let parts:Vec<&str>=rest.split('/').collect();
    let id_ok=|id:&str|!id.is_empty()&&id.len()<=40&&id.bytes().all(|b|b.is_ascii_uppercase()||b.is_ascii_digit()||b==b'-');
    let ok=match parts.as_slice() {["products"]=>true,["products",id]|["products",id,"candles"|"ticker"]=>id_ok(id),_=>false};
    if !ok {return Err(format!("Coinbase 路径 {rest}"))}
    (&[],&["product_type","product_ids","limit","offset","granularity","start","end","get_all_products"],b"-_=&%.:,")
   },
   other=>return Err(format!("主机 {other}")),
  };
  if !paths.is_empty()&&!paths.contains(&path) {return Err(format!("路径 {path}"))}
  for (k,v) in query {
   if !keys.contains(&k.as_str()) {return Err(format!("查询键 {k}"))}
   if !safe(v,extra) {return Err(format!("{k} 的值 {v:?}"))}
  }
  Ok(())
 }
 const PATH_PARTS:[&str;40]=["api","v5","market","public","tickers","ticker","candles","history-candles","instruments","mark-price","funding-rate","open-interest",
  "account","balance","trade","order","..",".","%2e%2e","%2F","%2f..%2f","TICKERS","Market","v5/market","products","BTC-USD","btc-usd","BTC-USD%2F..","candles%3Fx=1",
  "kline","instruments-info","funding","history","%E5%B8%81","%00","","BTC USD","%20","rubik","stat"];
 const KEYS:[&str;30]=["instType","instId","instFamily","uly","bar","after","before","limit","category","symbol","interval","intervalTime","start","end","startTime","endTime","status","cursor",
  "product_type","product_ids","granularity","offset","get_all_products","source","apiKey","sign","INSTTYPE","instType ","","x"];
 fn values()->Vec<String> {
  let mut v:Vec<String>=["SWAP","SPOT","BTC-USDT-SWAP","BTC-USD-SWAP","ETH-USDT-SWAP","BTC-USDT","1m","1H","1Dutc","2m","100","300","1790000000000","-1","1e9","",
   "linear","inverse","BTCUSDT","btcusdt","1","D","5min","Trading","first=1&last=2","../../x","%00","币安","1;DROP","ONE_MINUTE","BTC-USD","true","a b","\u{0}x","line\nfeed"]
   .iter().map(|s|s.to_string()).collect();
  v.push("9".repeat(21));v.push("1".repeat(20));v.push("A".repeat(201));v.push("A".repeat(200));
  v
 }
 /// 成百上千个随机组合的 GET 透传：路径（穿越、`%2F`、大小写、unicode、空段）× 查询（重复键、空值、超长、
 /// 控制字符）× 三家。断言：出站的每一笔都落在测试自己那份白名单里；没出站的一律 400 / 404；放出去的都是 200。
 #[tokio::test] async fn raw_passthrough_only_lets_the_whitelist_out() {
  use tower::ServiceExt;
  let seen:Seen=Default::default();
  let app=routes::<()>();
  let values=values();
  let (mut out,mut refused,mut unparsable)=(0usize,0usize,0usize);
  outbound::fake::UPSTREAM.scope(recorder(seen.clone()),async {
   let mut rng=Rng(0x5eed_1234_abcd_ef01);
   for round in 0..6000 {
    let source=*rng.pick(&["okx","bybit","coinbase"]);
    // 一半从真路径出发再随机改，一半纯随机拼。
    let path=if rng.chance(50) {
     let base=*rng.pick(&["api/v5/market/tickers","api/v5/market/candles","api/v5/public/instruments","v5/market/kline","v5/market/tickers","products","products/BTC-USD/candles","products/BTC-USD"]);
     match rng.next()%6 {0=>base.to_owned(),1=>format!("{base}/"),2=>format!("{base}/../account"),3=>base.replace('/',"%2F"),4=>base.to_uppercase(),_=>format!("/{base}")}
    } else {(0..1+rng.next()%5).map(|_|*rng.pick(&PATH_PARTS)).collect::<Vec<_>>().join("/")};
    let mut query=vec![format!("source={source}")];
    for _ in 0..rng.next()%6 {
     let (k,v)=(*rng.pick(&KEYS),rng.pick(&values).clone());
     let enc=|s:&str|if rng_bool(round) {crate::instruments::url_component(s)} else {s.to_owned()};
     query.push(format!("{}={}",enc(k),enc(&v)));
    }
    if rng.chance(5) {query.push(format!("source={}",rng.pick(&["okx","bybit","OKX","ftx"])))}
    if rng.chance(30) {let i=(rng.next()%query.len() as u64) as usize;query.swap(0,i)}
    // 四成从一条合法的请求出发（只有一处被随机改掉，或者原样），好让放行的那一侧也有足够多的样本。
    let (path,query)=if rng.chance(40) {
     let (p,q):(&str,&[&str])=*rng.pick(&[
      ("api/v5/market/candles",&["source=okx","instId=BTC-USDT-SWAP","bar=1m","limit=300","after=1790000000000"][..]),
      ("api/v5/market/tickers",&["source=okx","instType=SWAP"][..]),
      ("api/v5/public/instruments",&["source=okx","instType=SWAP","instFamily=BTC-USDT"][..]),
      ("v5/market/kline",&["source=bybit","category=linear","symbol=BTCUSDT","interval=1","start=1","end=2","limit=1000"][..]),
      ("v5/market/tickers",&["source=bybit","category=linear","cursor=first%3D1%26last%3D2"][..]),
      ("products/BTC-USD/candles",&["source=coinbase","granularity=ONE_MINUTE","start=1","end=2","limit=350"][..]),
      ("products",&["source=coinbase","product_type=SPOT","get_all_products=true"][..]),
     ]);
     let mut q:Vec<String>=q.iter().map(|s|s.to_string()).collect();
     if rng.chance(50) {let i=1+(rng.next()%(q.len() as u64-1)) as usize;let v=rng.pick(&values).clone();let k=q[i].split('=').next().unwrap().to_owned();q[i]=format!("{k}={}",crate::instruments::url_component(&v));}
     (p.to_owned(),q)
    } else {(path,query)};
    let uri=format!("/v1/market/raw/{path}?{}",query.join("&"));
    let Ok(request)=axum::http::Request::builder().uri(&uri).body(axum::body::Body::empty()) else {unparsable+=1;continue};
    let before=seen.lock().unwrap().len();
    let status=app.clone().oneshot(request).await.unwrap().status().as_u16();
    let after=seen.lock().unwrap().len();
    match status {
     200=>{out+=1;}
     400|404=>{refused+=1;assert_eq!(before,after,"拒了还出站：{uri}");}
     other=>panic!("{uri} 答了 {other}"),
    }
   }
  }).await;
  let seen=seen.lock().unwrap();
  for (url,query,_) in seen.iter() {
   if let Err(why)=egress_ok(url,query) {panic!("白名单外的出站（{why}）：{url} {query:?}")}
  }
  assert!(out>=100&&refused>=3000,"组合太偏：放行 {out}、拒 {refused}、拼不成请求 {unparsable}");
  eprintln!("透传模糊：放行 {out}（出站 {} 次，其余同键合流命中缓存）、拒 {refused}、拼不成请求 {unparsable}",seen.len());
 }
 fn rng_bool(round:usize)->bool {!round.is_multiple_of(3)}

 /// 具体的几条：穿越、编码过的斜杠、大小写、私有接口、空值、重复键，都不出站。
 #[tokio::test] async fn raw_traversal_and_lookalikes_never_go_out() {
  use tower::ServiceExt;
  let seen:Seen=Default::default();
  let app=routes::<()>();
  outbound::fake::UPSTREAM.scope(recorder(seen.clone()),async {
   for (uri,status) in [
    ("/v1/market/raw/api/v5/market/../account/balance?source=okx",404),
    ("/v1/market/raw/api/v5/market/tickers/../../account/balance?source=okx",404),
    ("/v1/market/raw/api%2Fv5%2Faccount%2Fbalance?source=okx",404),
    ("/v1/market/raw/API/V5/MARKET/TICKERS?source=okx",404),
    ("/v1/market/raw/api/v5/market/tickers%3FinstType=SWAP?source=okx",404),
    ("/v1/market/raw/api/v5/market/tickers?source=okx&instType=SWAP&instType=SPOT",400),
    ("/v1/market/raw/api/v5/market/tickers?source=okx&instType=",400),
    ("/v1/market/raw/api/v5/market/tickers?source=okx&instType=SWAP%00",400),
    ("/v1/market/raw/api/v5/market/candles?source=okx&instId=BTC-USDT-SWAP&limit=999999999999999999999",400),
    ("/v1/market/raw/api/v5/market/candles?source=okx&instId=%E5%B8%81-USDT-SWAP",400),
    ("/v1/market/raw/v5/market/kline?source=bybit&category=spot",400),
    ("/v1/market/raw/v5/market/kline?source=bybit&category=linear&cursor=a%20b",400),
    ("/v1/market/raw/v5/market/kline?source=bybit&category=linear&cursor=%E5%B8%81",400),
    ("/v1/market/raw/v5/user/query-api?source=bybit",404),
    ("/v1/market/raw/v5/market/..%2Fuser%2Fquery-api?source=bybit",404),
    ("/v1/market/raw/products/BTC-USD%2F..%2F..%2Forders?source=coinbase",404),
    ("/v1/market/raw/products/btc-usd/candles?source=coinbase",404),
    ("/v1/market/raw/products/BTC-USD/candles?source=coinbase&granularity=ONE%0AMINUTE",400),
    ("/v1/market/raw/products/BTC-USD/candles?source=coinbase&api_key=x",400),
    ("/v1/market/raw/products?source=Coinbase",400),
    ("/v1/market/raw/products",400),
   ] {
    let got=app.clone().oneshot(axum::http::Request::builder().uri(uri).body(axum::body::Body::empty()).unwrap()).await.unwrap().status().as_u16();
    assert_eq!(got,status,"{uri}");
   }
   // 重复的合法键照样出站（上游只认第一个），值都在白名单里。
   let ok=app.clone().oneshot(axum::http::Request::builder().uri("/v1/market/raw/v5/market/kline?source=bybit&category=linear&symbol=BTCUSDT&interval=1&cursor=first%3D1%26last%3D2").body(axum::body::Body::empty()).unwrap()).await.unwrap();
   assert_eq!(ok.status().as_u16(),200);
  }).await;
  let seen=seen.lock().unwrap();
  assert_eq!(seen.len(),1,"只有最后那一条出站：{seen:?}");
  assert_eq!(seen[0].1.iter().find(|(k,_)|k=="cursor").map(|(_,v)|v.as_str()),Some("first=1&last=2"));
 }

 /// Hyperliquid 的 POST 正文模糊：`type` 不在表里、`req` 多字段、负数 / 超大时间、超大正文、重复键、嵌套类型错，
 /// 都 400 / 413 不出站；放出去的都按认出来的字段重拼过（只有表里那几种 `type`、键一个不多）。
 #[tokio::test] async fn hyperliquid_bodies_only_let_the_whitelist_out() {
  use tower::ServiceExt;
  let seen:Seen=Default::default();
  let app=routes::<()>();
  let (mut out,mut refused)=(0usize,0usize);
  outbound::fake::UPSTREAM.scope(recorder(seen.clone()),async {
   let mut rng=Rng(0xfeed_face_cafe_beef);
   let types=["meta","metaAndAssetCtxs","allMids","candleSnapshot","fundingHistory","l2Book","userState","clearinghouseState","userFills","Meta","meta ","",
    "spotMeta","exchange","candleSnapshot\u{0}"];
   let coins=[json!("BTC"),json!("kPEPE"),json!("BTC-USD"),json!("@107"),json!(""),json!("A".repeat(17)),json!(1),json!(null),json!(["BTC"]),json!("币")];
   let times=[json!(0),json!(1),json!(-1),json!(1790000000000_i64),json!(9_999_999_999_999_i64),json!(10_000_000_000_000_i64),json!(u64::MAX),json!(1.5),json!("1"),json!(null)];
   let intervals=[json!("1m"),json!("1h"),json!("1M"),json!("7m"),json!("1H"),json!(""),json!(60)];
   for _ in 0..4000 {
    let mut body=serde_json::Map::new();
    let kind=*rng.pick(&types);
    if !rng.chance(3) {body.insert("type".into(),json!(kind));}
    let mut req=serde_json::Map::new();
    if rng.chance(70) {req.insert("coin".into(),rng.pick(&coins).clone());}
    if rng.chance(70) {req.insert("interval".into(),rng.pick(&intervals).clone());}
    if rng.chance(80) {req.insert("startTime".into(),rng.pick(&times).clone());}
    if rng.chance(40) {req.insert("endTime".into(),rng.pick(&times).clone());}
    if rng.chance(10) {req.insert(rng.pick(&["user","limit","nSigFigs","dex","x"]).to_string(),json!(5000));}
    if rng.chance(50) {body.insert("req".into(),Value::Object(req.clone()));} else {for (k,v) in req {body.insert(k,v);}}
    if rng.chance(8) {body.insert(rng.pick(&["user","dex","limit","extra"]).to_string(),json!("0x0"));}
    if rng.chance(40) {
     body=rng.pick(&[
      json!({"type":"candleSnapshot","req":{"coin":"BTC","interval":"1m","startTime":1790000000000_i64}}),
      json!({"type":"candleSnapshot","req":{"coin":"kPEPE","interval":"1h","startTime":0,"endTime":1790000000000_i64}}),
      json!({"type":"fundingHistory","coin":"ETH","startTime":1683849600076_i64}),
      json!({"type":"meta"}),json!({"type":"allMids"}),json!({"type":"metaAndAssetCtxs"}),
     ]).as_object().unwrap().clone();
     if rng.chance(50) {
      let k=rng.pick(&["coin","startTime","endTime","type","limit"]).to_string();
      let v=match k.as_str() {"coin"=>rng.pick(&coins).clone(),"type"=>json!(*rng.pick(&types)),_=>rng.pick(&times).clone()};
      match body.get_mut("req").and_then(Value::as_object_mut) {Some(req) if k!="type"=>{req.insert(k,v);},_=>{body.insert(k,v);}}
     }
    }
    let mut text=Value::Object(body).to_string();
    match rng.next()%20 {
     0=>text=format!("{text}{text}"),
     1=>text=text.replacen('{',r#"{"type":"meta","#,1),
     2=>text=format!("{text}{}"," ".repeat(3000)),
     3=>text=text.chars().take(text.len()/2).collect(),
     _=>{},
    }
    let path=*rng.pick(&["info","info","info","exchange","Info","info/","../info"]);
    let request=axum::http::Request::builder().method("POST").uri(format!("/v1/market/raw/{path}?source=hyperliquid")).body(axum::body::Body::from(text.clone())).unwrap();
    let before=seen.lock().unwrap().len();
    let status=app.clone().oneshot(request).await.unwrap().status().as_u16();
    let after=seen.lock().unwrap().len();
    match status {
     200=>out+=1,
     400|404|413=>{refused+=1;assert_eq!(before,after,"拒了还出站：{path} {text}")}
     other=>panic!("{path} {text} 答了 {other}"),
    }
   }
  }).await;
  let seen=seen.lock().unwrap();
  for (url,query,body) in seen.iter() {
   assert_eq!(url,"https://api.hyperliquid.xyz/info");
   assert!(query.is_empty());
   let body=body.as_ref().expect("POST 带正文");
   let o=body.as_object().unwrap();
   let kind=o["type"].as_str().unwrap();
   let keys:Vec<&str>=o.keys().map(String::as_str).collect();
   match kind {
    "meta"|"metaAndAssetCtxs"|"allMids"=>assert_eq!(keys,vec!["type"]),
    "candleSnapshot"=>{
     let req=o["req"].as_object().unwrap();
     assert!(keys.len()==2&&req.keys().all(|k|["coin","interval","startTime","endTime"].contains(&k.as_str())),"{body}");
     assert!(req["startTime"].as_u64().is_some_and(|t|t<=9_999_999_999_999),"{body}");
     assert!(req.get("endTime").is_none_or(|t|t.as_u64().is_some_and(|t|t<=9_999_999_999_999)),"{body}");
     assert!(req["coin"].as_str().is_some_and(|c|!c.is_empty()&&c.len()<=16&&c.bytes().all(|b|b.is_ascii_alphanumeric())),"{body}");
    },
    "fundingHistory"=>assert!(keys.iter().all(|k|["type","coin","startTime","endTime"].contains(k)),"{body}"),
    other=>panic!("type {other} 出站了：{body}"),
   }
  }
  assert!(out>=50&&refused>=2000,"组合太偏：放行 {out}、拒 {refused}");
  eprintln!("Hyperliquid 正文模糊：放行 {out}（出站 {} 次）、拒 {refused}",seen.len());
 }
}
