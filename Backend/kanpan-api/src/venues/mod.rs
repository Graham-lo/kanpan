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
 /// Webhook 的 `{品种}`：缩写 + 空格 + 短名（「币安 BTC」）。
 fn webhook_name(&self,symbol:&str)->String {self.display(symbol)}
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
 match source_of(&query) {Some(v)=>v.stream(ws,&query).unwrap_or_else(unsupported),None=>unsupported()}
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
}
