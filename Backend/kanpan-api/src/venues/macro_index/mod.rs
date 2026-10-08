//! 美元指数（`macro/index/DXY`）：一个只有一只品种的「交易所」。
//!
//! 和币安、Coinbase 不同，这里没有可透传的上游：服务端自己从 CNBC 采价（见 `cnbc`、`collector`），
//! 存进 `macro_bars`（永久保留），再答成币安的形状给客户端——客户端照接 Coinbase 的那套做一个
//! 提供者就行（协议见 `docs/美元指数-协议-2026-10-05.md`）。
//!
//! - `GET /v1/market/raw/instruments?source=macro`：品种表（一只）。
//! - `GET /v1/market/raw/klines?source=macro&symbol=DXY&interval=1h[&limit&startTime&endTime]`：币安 K 线数组。
//! - `GET /v1/market/raw/ticker/24hr?source=macro[&symbol=DXY]`：币安 24h 行情的字段 + `marketState` + `priceSource`。
//! - `WS /v1/market/stream?source=macro`：见 `stream`。
//!
//! 涨跌幅的口径是「对上一个交易日的官方收盘」，不是滚动 24 小时（见 `collector::State::ticker`）。
//! 交易时间是 ICE 美元指数的：美东周日 18:00 到周五 17:00，每天 17:00–18:00 休一小时（见 `calendar`）。
pub mod bars;
pub mod calendar;
pub mod cnbc;
pub mod collector;
pub mod stream;

use axum::http::{HeaderValue,StatusCode,header};
use axum::response::{IntoResponse,Response};
use serde_json::{Value,json};
use bars::price;

/// `?source=` 的值、`InstrumentID.venue`。
pub const SOURCE:&str="macro";
/// `InstrumentID.market`。
pub const MARKET:&str="index";
/// 唯一的一只。
pub const SYMBOL:&str="DXY";
pub const NAME:&str="美元指数";
/// 搜索关键字（服务端没有品种目录可挂，写进品种表给客户端的搜索用）。
pub const KEYWORDS:[&str;5]=["美元指数","DXY","USD","美元","美指"];
/// K 线一次最多给多少根（同币安）。
pub const MAX_LIMIT:usize=1500;
pub const DEFAULT_LIMIT:usize=500;

pub use collector::spawn;
pub use stream::serve_client;

fn json_body(status:StatusCode,body:&Value)->Response {
 let mut response=(status,body.to_string()).into_response();
 let headers=response.headers_mut();
 headers.insert(header::CONTENT_TYPE,HeaderValue::from_static("application/json"));
 headers.insert(header::CACHE_CONTROL,HeaderValue::from_static("no-store"));
 response
}
fn refuse(status:StatusCode,error:&str)->Response {json_body(status,&json!({"error":error}))}

fn param<'a>(query:&'a [(String,String)],key:&str)->Option<&'a str> {
 query.iter().find(|(k,_)|k==key).map(|(_,v)|v.as_str())
}

/// 涨跌额、涨跌幅（百分数，三位小数，同币安）。没有昨收时都是 `null`。
pub fn change(tk:&collector::Ticker)->(Option<String>,Option<String>) {
 match tk.prev_close {
  Some(pc) if pc>0.0=>{let d=tk.last-pc;(Some(price(d)),Some(format!("{:.3}",d/pc*100.0)))}
  _=>(None,None),
 }
}

/// `marketState`：开盘时间里、而且最后一笔价不超过 10 分钟，才是 `open`。
pub fn market_state(open:bool)->&'static str {if open {"open"} else {"closed"}}

pub fn instruments()->Value {
 json!({"symbols":[{
  "symbol":SYMBOL,"venue":SOURCE,"market":MARKET,"key":format!("{SOURCE}/{MARKET}/{SYMBOL}"),
  "displayName":NAME,"status":"TRADING","pricePrecision":3,"tickSize":"0.001",
  "filters":[{"filterType":"PRICE_FILTER","tickSize":"0.001"}],
  "baseAsset":SYMBOL,"quoteAsset":"USD","underlyingType":"INDEX","keywords":KEYWORDS,
 }]})
}

pub fn ticker_json(tk:&collector::Ticker)->Value {
 let (p,pp)=change(tk);
 json!({"symbol":SYMBOL,"lastPrice":price(tk.last),"priceChange":p,"priceChangePercent":pp,
  "prevClosePrice":tk.prev_close.map(price),"openPrice":price(tk.open),"highPrice":price(tk.high),"lowPrice":price(tk.low),
  "volume":"0","quoteVolume":"0","openTime":tk.session_start,"closeTime":tk.time,
  "marketState":market_state(tk.open_now),"priceSource":tk.source.name()})
}

fn time_param(query:&[(String,String)],key:&str)->Result<Option<i64>,()> {
 match param(query,key) {None=>Ok(None),Some(v)=>v.parse::<i64>().ok().filter(|t|*t>=0).map(Some).ok_or(())}
}

fn symbol_ok(query:&[(String,String)],required:bool)->bool {
 match param(query,"symbol") {Some(s)=>s.eq_ignore_ascii_case(SYMBOL),None=>!required}
}

async fn klines(query:&[(String,String)])->Response {
 if !symbol_ok(query,true) {return refuse(StatusCode::BAD_REQUEST,"invalid_symbol")}
 let Some(spec)=param(query,"interval").and_then(bars::spec) else {return refuse(StatusCode::BAD_REQUEST,"invalid_interval")};
 let limit=match param(query,"limit") {None=>DEFAULT_LIMIT,Some(v)=>match v.parse::<usize>() {Ok(n) if n>0=>n.min(MAX_LIMIT),_=>return refuse(StatusCode::BAD_REQUEST,"invalid_limit")}};
 let (Ok(start),Ok(end))=(time_param(query,"startTime"),time_param(query,"endTime")) else {return refuse(StatusCode::BAD_REQUEST,"invalid_time")};
 if let (Some(s),Some(e))=(start,end)&&s>e {return refuse(StatusCode::BAD_REQUEST,"invalid_time")}
 let Some(pool)=collector::pool() else {return refuse(StatusCode::SERVICE_UNAVAILABLE,"not_ready")};
 let plan=bars::plan(&spec,start,end,limit);
 match collector::read(pool,plan.source,plan.from,plan.until,plan.ascending,plan.limit).await {
  Ok(rows)=>{
   let out=bars::select(&spec,&rows,&plan,start,end,limit);
   json_body(StatusCode::OK,&Value::Array(out.iter().map(|b|bars::row(b,spec.span)).collect()))
  }
  Err(e)=>{tracing::warn!("Macro klines: read failed ({e})");refuse(StatusCode::SERVICE_UNAVAILABLE,"storage_unavailable")}
 }
}

fn ticker(query:&[(String,String)])->Response {
 if !symbol_ok(query,false) {return refuse(StatusCode::BAD_REQUEST,"invalid_symbol")}
 let now=chrono::Utc::now().timestamp_millis();
 let Some(tk)=collector::state().ticker(now) else {return refuse(StatusCode::SERVICE_UNAVAILABLE,"no_data")};
 let body=ticker_json(&tk);
 json_body(StatusCode::OK,&if param(query,"symbol").is_some() {body} else {Value::Array(vec![body])})
}

/// `/v1/market/raw/{path}?source=macro`。
pub async fn raw(path:&str,query:&[(String,String)])->Response {
 match path {
  "instruments"=>json_body(StatusCode::OK,&instruments()),
  "klines"=>klines(query).await,
  "ticker/24hr"=>ticker(query),
  _=>refuse(StatusCode::NOT_FOUND,"unsupported_path"),
 }
}

/// 注册表里的这一家。只有一只 `DXY`；没有供应量、没有持仓量，提醒读库（`alerts::run_macro`）。
pub struct Macro;
pub static MACRO:Macro=Macro;
impl super::Venue for Macro {
 fn source(&self)->&'static str {SOURCE}
 /// 不带缩写：标题就是「美元指数」。
 fn short_name(&self)->&'static str {""}
 fn market(&self)->&'static str {MARKET}
 fn market_key(&self)->&'static str {"macro/index"}
 /// 只收这一个代号，不开放成「任意大写」：服务端只采得到这一只的价，别的收下了也永远判不响。
 fn symbol_ok(&self,symbol:&str)->bool {symbol==SYMBOL}
 fn display(&self,_symbol:&str)->String {NAME.to_string()}
 fn meta_symbol(&self,_symbol:&str)->Option<String> {None}
 fn raw<'a>(&'a self,path:&'a str,query:&'a [(String,String)])->super::Fut<'a,Response> {Box::pin(raw(path,query))}
 fn stream(&self,ws:axum::extract::ws::WebSocketUpgrade,query:&[(String,String)])->Option<Response> {
  let initial=param(query,"streams").map(|s|s.chars().take(1024).collect::<String>());
  Some(ws.on_upgrade(move|socket|serve_client(socket,initial)))
 }
}

#[cfg(test)]
mod tests {
 use super::*;
 #[test] fn the_instrument_is_described_once() {
  let v=instruments();
  let s=&v["symbols"][0];
  assert_eq!(s["key"],"macro/index/DXY");
  assert_eq!(s["displayName"],"美元指数");
  assert_eq!(s["tickSize"],"0.001");
  assert_eq!(s["pricePrecision"],3);
  assert_eq!(s["keywords"].as_array().unwrap().len(),5);
 }
 #[test] fn the_ticker_reports_change_against_the_previous_close() {
  let tk=collector::Ticker{last:102.185,time:1,source:collector::Source::Official,prev_close:Some(101.932),open:101.917,high:102.535,low:101.855,session_start:0,open_now:true};
  let v=ticker_json(&tk);
  assert_eq!(v["lastPrice"],"102.185");
  assert_eq!(v["priceChange"],"0.253");
  assert_eq!(v["priceChangePercent"],"0.248");
  assert_eq!(v["marketState"],"open");
  assert_eq!(v["priceSource"],"official");
  let none=ticker_json(&collector::Ticker{prev_close:None,..tk});
  assert!(none["priceChange"].is_null());
 }
 #[tokio::test] async fn bad_requests_are_refused_before_storage() {
  let q=|v:&[(&str,&str)]|v.iter().map(|(a,b)|(a.to_string(),b.to_string())).collect::<Vec<_>>();
  assert_eq!(raw("klines",&q(&[("symbol","BTC"),("interval","1m")])).await.status(),StatusCode::BAD_REQUEST);
  assert_eq!(raw("klines",&q(&[("symbol","DXY"),("interval","8h")])).await.status(),StatusCode::BAD_REQUEST);
  assert_eq!(raw("klines",&q(&[("symbol","DXY"),("interval","1m"),("limit","0")])).await.status(),StatusCode::BAD_REQUEST);
  assert_eq!(raw("klines",&q(&[("symbol","DXY"),("interval","1m"),("startTime","9"),("endTime","1")])).await.status(),StatusCode::BAD_REQUEST);
  assert_eq!(raw("exchangeInfo",&q(&[])).await.status(),StatusCode::NOT_FOUND);
  assert_eq!(raw("instruments",&q(&[])).await.status(),StatusCode::OK);
 }
}
