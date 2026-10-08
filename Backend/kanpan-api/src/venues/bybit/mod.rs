//! Bybit v5 公开行情在服务端的那一截。2026-10-08 起 Bybit 是和币安、OKX 平起平坐的一家：
//! 用户搜 Bybit 的 USDT 线性永续、加自选、看 K 线、设提醒。看盘键就是 Bybit 原生的代号（`bybit/usd_m/BTCUSDT`）。
//!
//! - `GET /v1/market/raw/<path>?source=bybit&…`：公开行情原样透传（[`raw`]，白名单见 [`ttl_of`]）；
//! - 持仓量 / 资金费率：`/v5/market/tickers?category=linear` 整表带着，抓一张答所有品种（[`tickers`]）；
//! - `candles`：提醒补缺用的原生 K 线；
//! - `relay`：`GET /v1/market/ws/bybit?category=spot|linear|inverse` 中继的上行白名单
//!   （传输、名额、超时由 `market_relay` 统一管，这里只认 Bybit 的报文）；
//! - `orderflow`：主力订单流的品种表；`alerts`：提醒评估的 1 分钟 K 线来源。
//!
//! REST 主机 `api.bybit.com`，连不上换 `api.bytick.com`；推送 `wss://stream.bybit.com/v5/public/{category}`，
//! 连不上换 `stream.bytick.com`。这一家的全部 REST 出站都排 [`PACER`]。
pub mod alerts;
pub mod orderflow;
pub mod relay;
use super::outbound::{self,Answers,Memo,Pacer,Reply,Upstream,refuse};
use super::{Bar,Fut};
use crate::error::{ApiError,Result};
use crate::market_meta::{OpenInterest,num};
use axum::http::StatusCode;
use axum::response::Response;
use serde_json::Value;
use std::collections::HashMap;
use std::time::Duration;

pub const SOURCE:&str="bybit";
/// REST 主机（按先后试）。
pub const REST_HOSTS:[&str;2]=["https://api.bybit.com","https://api.bytick.com"];
pub const HOSTS:&[&str]=&["api.bybit.com","api.bytick.com"];
/// 公开行情 WS 的主机（按先后试）。后面拼 `/{category}`。
pub const WS_BASES:[&str;2]=["wss://stream.bybit.com/v5/public","wss://stream.bytick.com/v5/public"];

/// 三个 category。
pub fn valid_category(category:&str)->bool {matches!(category,"spot"|"linear"|"inverse")}

// ------------------------------------------------------------------ 出站节拍

/// 官方文档（Rate Limit › IP Limit）：同一 IP 每 5 秒最多 600 次 HTTP 请求，所有接口合计。
/// 这里每 50 ms 一次（每秒 20 次）封顶，远在线下，也给同出口的订单流品种表留着余量。
pub static PACER:Pacer=Pacer::new(Duration::from_millis(50),Duration::from_secs(8),&[]);

async fn get(path:&str,query:&[(String,String)])->std::result::Result<Reply,Upstream> {
 outbound::send_any(&PACER,&REST_HOSTS,path,query,1).await
}
/// 订单流品种表用：一页原文（`path` 里带着查询串），要 2xx。
pub(crate) async fn rest_bytes(path:&str)->anyhow::Result<axum::body::Bytes> {
 let reply=get(path,&[]).await.map_err(|e|anyhow::anyhow!("bybit {path}: {e:?}"))?;
 anyhow::ensure!(reply.status.is_success(),"bybit {path} answered {}",reply.status);
 Ok(reply.body)
}
async fn get_json(path:&str,query:&[(&str,&str)])->std::result::Result<Value,Upstream> {
 let query:Vec<(String,String)>=query.iter().map(|(k,v)|(k.to_string(),v.to_string())).collect();
 let v=outbound::json_of(&get(path,&query).await?)?;
 // `retCode` 不是 0 就是没拿到（限流时 Bybit 也可能回 200 + 10006）。
 if v["retCode"].as_i64()!=Some(0) {return Err(if v["retCode"].as_i64()==Some(10006) {Upstream::RateLimited(Some(1))} else {Upstream::Unavailable})}
 Ok(v)
}

// ------------------------------------------------------------------ 代号

/// 看盘键：Bybit 原生的 USDT 线性永续代号（`BTCUSDT`、`1000PEPEUSDT`），大写字母数字、以 USDT 结尾。
pub fn symbol_ok(key:&str)->bool {super::upper_alnum(key,5..=40)&&key.strip_suffix("USDT").is_some_and(|b|!b.is_empty())}

// ------------------------------------------------------------------ REST 透传

/// K 线周期（`interval`）。
const INTERVALS:[&str;13]=["1","3","5","15","30","60","120","240","360","720","D","W","M"];
/// 持仓量统计周期（`intervalTime`）。
const OI_INTERVALS:[&str;6]=["5min","15min","30min","1h","4h","1d"];

fn param<'a>(query:&'a [(String,String)],key:&str)->Option<&'a str> {query.iter().find(|(k,_)|k==key).map(|(_,v)|v.as_str())}

/// 放行的路径与这条答案能给后来者用多久：品种表一分钟；整表行情两秒；带 `end` 的历史页一分钟。
fn ttl_of(path:&str,query:&[(String,String)])->Option<Duration> {
 let past=param(query,"end").or(param(query,"endTime")).is_some();
 Some(match path {
  "v5/market/instruments-info"=>Duration::from_secs(60),
  "v5/market/tickers"=>if param(query,"symbol").is_some() {Duration::from_secs(1)} else {Duration::from_secs(2)},
  "v5/market/kline"=>if past {Duration::from_secs(60)} else {Duration::from_secs(2)},
  "v5/market/funding/history"=>Duration::from_secs(30),
  "v5/market/open-interest"=>if past {Duration::from_secs(60)} else {Duration::from_secs(3)},
  _=>return None,
 })
}
fn digits(v:&str)->bool {(1..=20).contains(&v.len())&&v.bytes().all(|b|b.is_ascii_digit())}
/// 查询键与值的白名单：只看 USDT 线性永续（`category=linear`）。
fn query_ok(key:&str,value:&str)->bool {
 match key {
  "category"=>value=="linear",
  "symbol"=>symbol_ok(value),
  "interval"=>INTERVALS.contains(&value),
  "intervalTime"=>OI_INTERVALS.contains(&value),
  "start"|"end"|"startTime"|"endTime"|"limit"=>digits(value),
  "status"=>value=="Trading",
  "cursor"=>!value.is_empty(),
  _=>false,
 }
}
/// `retCode` 是 0 才留给后来者。
fn bybit_ok(reply:&Reply)->bool {
 #[derive(serde::Deserialize)] #[serde(rename_all="camelCase")] struct Code {ret_code:i64}
 serde_json::from_slice::<Code>(&reply.body).is_ok_and(|c|c.ret_code==0)
}
static ANSWERS:Answers=Answers::new();

pub async fn raw(path:&str,query:&[(String,String)])->Response {
 let Some(ttl)=ttl_of(path,query) else {return refuse(StatusCode::NOT_FOUND,"unsupported_path")};
 let Some(forward)=outbound::forward(query,query_ok) else {return refuse(StatusCode::BAD_REQUEST,"unsupported_query")};
 outbound::pass(ANSWERS.get(format!("{path}?{forward:?}"),ttl,bybit_ok,||get(path,&forward)).await)
}

// ------------------------------------------------------------------ K 线（提醒补缺）

fn interval_of(step:i64)->Option<&'static str> {
 Some(match step {60=>"1",180=>"3",300=>"5",900=>"15",1800=>"30",3600=>"60",7200=>"120",14_400=>"240",21_600=>"360",43_200=>"720",86_400=>"D",_=>return None})
}
/// 官方文档（Market › Get Kline）：一页最多 1000 根，新的在前。
const KLINE_PAGE:usize=1000;

/// 一页 K 线：`result.list` 每行 `[startTime, open, high, low, close, volume, turnover]`，都是字符串。
pub fn parse_kline(body:&Value)->Vec<Bar> {
 body["result"]["list"].as_array().into_iter().flatten().filter_map(|row|{
  let n=|i:usize|num(&row[i]);
  let bar=Bar{open_time:row[0].as_str()?.parse().ok()?,open:n(1)?,high:n(2)?,low:n(3)?,close:n(4)?,volume:n(5).unwrap_or(0.0)};
  bar.sane().then_some(bar)
 }).collect()
}

/// `[start, end)`（秒）里的 K 线，升序。`start` / `end` 两端都含，从 `end` 往回翻。
pub async fn candles(key:&str,step:i64,start:i64,end:i64)->std::result::Result<Vec<Bar>,Upstream> {
 let (Some(interval),true)=(interval_of(step),symbol_ok(key)) else {return Err(Upstream::Rejected(400))};
 let (from,until)=(start*1000,end*1000);
 let mut out:Vec<Bar>=Vec::new();
 let mut cursor=until-1;
 let limit=KLINE_PAGE.to_string();
 for _ in 0..32 {
  if cursor<from {break}
  let (s,e)=(from.to_string(),cursor.to_string());
  let page=parse_kline(&get_json("v5/market/kline",&[("category","linear"),("symbol",key),("interval",interval),("start",&s),("end",&e),("limit",&limit)]).await?);
  let Some(oldest)=page.iter().map(|b|b.open_time).min() else {break};
  let full=page.len()>=KLINE_PAGE;
  out.extend(page.into_iter().filter(|b|b.open_time>=from&&b.open_time<until));
  if !full||oldest>cursor {break}
  cursor=oldest-1;
 }
 out.sort_by_key(|b|b.open_time);out.dedup_by_key(|b|b.open_time);
 Ok(out)
}

// ------------------------------------------------------------------ 持仓量与资金费率

/// 整表一行里要的几样。
#[derive(Clone,Copy,Debug,PartialEq)]
pub struct Row {pub oi:Option<OpenInterest>,pub rate:Option<f64>,pub next_funding_time:Option<i64>}

/// `/v5/market/tickers?category=linear` 的整表（官方文档 Market › Get Tickers）：每行带
/// `openInterest`（币的个数）、`openInterestValue`（美元名义值）、`fundingRate`、`nextFundingTime`。
pub fn parse_tickers(body:&Value)->HashMap<String,Row> {
 let time=body["time"].as_i64().unwrap_or(0);
 body["result"]["list"].as_array().into_iter().flatten().filter_map(|row|{
  let symbol=row["symbol"].as_str().filter(|s|symbol_ok(s))?.to_owned();
  let oi=num(&row["openInterest"]).filter(|x|*x>=0.0).map(|amount|OpenInterest{open_interest:amount,value:num(&row["openInterestValue"]),time});
  let next=row["nextFundingTime"].as_str().and_then(|t|t.parse::<i64>().ok()).filter(|t|*t>0);
  Some((symbol,Row{oi,rate:num(&row["fundingRate"]),next_funding_time:next}))
 }).collect()
}

/// 整表十五秒内共用一份；刷不动时一刻钟内的旧表还能答（持仓量是分钟级的量）。
const TICKERS_TTL:Duration=Duration::from_secs(15);
const TICKERS_MAX_AGE:Duration=Duration::from_secs(900);
static TICKERS:Memo<HashMap<String,Row>>=Memo::new();

pub async fn tickers()->Result<std::sync::Arc<HashMap<String,Row>>> {
 TICKERS.get(TICKERS_TTL,TICKERS_MAX_AGE,||async {
  let table=parse_tickers(&get_json("v5/market/tickers",&[("category","linear")]).await?);
  if table.is_empty() {Err(Upstream::Unavailable)} else {Ok(table)}
 }).await.map_err(outbound::api_error)
}

pub async fn open_interest(key:&str)->Result<OpenInterest> {
 tickers().await?.get(key).and_then(|r|r.oi).ok_or_else(ApiError::missing)
}

/// `{"source":"bybit","rows":[{symbol,rate,nextFundingTime}]}`，和 OKX 那张同形。
pub async fn funding()->Result<Value> {
 let table=tickers().await?;
 let mut rows:Vec<(&String,f64,i64)>=table.iter().filter_map(|(s,r)|Some((s,r.rate?,r.next_funding_time?))).collect();
 rows.sort_by(|a,b|a.0.cmp(b.0));
 let rows:Vec<Value>=rows.into_iter().map(|(s,rate,next)|serde_json::json!({"symbol":s,"rate":rate,"nextFundingTime":next})).collect();
 Ok(serde_json::json!({"source":SOURCE,"rows":rows}))
}

// ------------------------------------------------------------------ 注册表里的这一家

pub struct Bybit;
pub static BYBIT:Bybit=Bybit;

impl super::Venue for Bybit {
 fn source(&self)->&'static str {SOURCE}
 fn short_name(&self)->&'static str {"Bybit"}
 fn market(&self)->&'static str {"usd_m"}
 fn market_key(&self)->&'static str {"bybit/usd_m"}
 fn symbol_ok(&self,symbol:&str)->bool {symbol_ok(symbol)}
 fn webhook_name(&self,symbol:&str)->String {super::without_usdt(symbol).to_owned()}
 fn pacer(&self)->Option<&'static Pacer> {Some(&PACER)}
 fn hosts(&self)->&'static [&'static str] {HOSTS}
 fn raw<'a>(&'a self,path:&'a str,query:&'a [(String,String)])->Fut<'a,Response> {Box::pin(raw(path,query))}
 fn candles<'a>(&'a self,symbol:&'a str,step:i64,start:i64,end:i64)->Fut<'a,std::result::Result<Vec<Bar>,Upstream>> {Box::pin(candles(symbol,step,start,end))}
 fn open_interest<'a>(&'a self,symbol:&'a str)->Option<Fut<'a,Result<OpenInterest>>> {Some(Box::pin(open_interest(symbol)))}
 fn funding(&self)->Option<Fut<'static,Result<Value>>> {Some(Box::pin(funding()))}
 fn alert_feed(&self)->Option<&'static dyn crate::alerts::KlineFeed> {Some(&alerts::FEED)}
}

#[cfg(test)]
mod tests {
 use super::*;
 use serde_json::json;

 fn q(pairs:&[(&str,&str)])->Vec<(String,String)> {pairs.iter().map(|(k,v)|(k.to_string(),v.to_string())).collect()}

 #[test] fn only_public_market_paths_and_keys_pass_through() {
  for ok in ["v5/market/instruments-info","v5/market/tickers","v5/market/kline","v5/market/funding/history","v5/market/open-interest"] {assert!(ttl_of(ok,&[]).is_some(),"{ok}")}
  for bad in ["","v5/order/create","v5/account/wallet-balance","v5/market/orderbook","v5/market/kline/x","v5/market/../order"] {assert!(ttl_of(bad,&[]).is_none(),"{bad}")}
  assert_eq!(ttl_of("v5/market/kline",&q(&[("end","1")])),Some(Duration::from_secs(60)));
  assert!(query_ok("category","linear")&&!query_ok("category","spot")&&!query_ok("category","option"));
  assert!(query_ok("symbol","1000PEPEUSDT")&&!query_ok("symbol","BTCUSD")&&!query_ok("symbol","btcusdt"));
  assert!(query_ok("interval","D")&&query_ok("interval","60")&&!query_ok("interval","1h"));
  assert!(query_ok("intervalTime","5min")&&!query_ok("intervalTime","2h"));
  assert!(query_ok("limit","1000")&&!query_ok("limit","x")&&!query_ok("api_key","k"));
 }

 /// 夹具照官方文档（Market › Get Kline 的示例答复）写：新的在前。
 #[test] fn kline_pages_parse() {
  let body=json!({"retCode":0,"retMsg":"OK","result":{"symbol":"BTCUSDT","category":"linear","list":[
   ["1670608800000","17071","17073","17027","17055.5","268611","4584465.95"],
   ["1670605200000","17071.5","17071.5","17061","17071","4177","71282.06"],
   ["1670601600000","0","1","1","1","1","1"]]},"time":1672025956592_i64});
  let bars=parse_kline(&body);
  assert_eq!(bars,vec![Bar{open_time:1_670_608_800_000,open:17071.0,high:17073.0,low:17027.0,close:17055.5,volume:268611.0},
   Bar{open_time:1_670_605_200_000,open:17071.5,high:17071.5,low:17061.0,close:17071.0,volume:4177.0}]);
  assert_eq!(interval_of(60),Some("1"));assert_eq!(interval_of(86_400),Some("D"));assert_eq!(interval_of(61),None);
 }

 /// 夹具照官方文档（Market › Get Tickers，linear 的示例答复）写。
 #[test] fn tickers_carry_open_interest_and_funding() {
  let body=json!({"retCode":0,"retMsg":"OK","result":{"category":"linear","list":[
   {"symbol":"BTCUSDT","lastPrice":"16597.00","openInterest":"373504107","openInterestValue":"6199113672.48","fundingRate":"-0.00037","nextFundingTime":"1672387200000"},
   {"symbol":"BTCPERP","lastPrice":"1","openInterest":"1","fundingRate":"0.0001","nextFundingTime":"1"},
   {"symbol":"ETHUSDT","lastPrice":"1","openInterest":"","fundingRate":"","nextFundingTime":""}]},"time":1672376496682_i64});
  let t=parse_tickers(&body);
  assert_eq!(t.len(),2,"USDC 永续不算");
  assert_eq!(t["BTCUSDT"],Row{oi:Some(OpenInterest{open_interest:373504107.0,value:Some(6199113672.48),time:1_672_376_496_682}),rate:Some(-0.00037),next_funding_time:Some(1_672_387_200_000)});
  assert_eq!(t["ETHUSDT"],Row{oi:None,rate:None,next_funding_time:None},"缺的就是缺的");
 }

 #[test] fn non_zero_ret_codes_are_not_kept() {
  let r=|b:&'static str|Reply{status:StatusCode::OK,retry_after:None,body:axum::body::Bytes::from_static(b.as_bytes())};
  assert!(bybit_ok(&r(r#"{"retCode":0,"result":{}}"#)));
  assert!(!bybit_ok(&r(r#"{"retCode":10006,"retMsg":"Too many visits!"}"#)));
 }

 #[tokio::test] async fn private_paths_and_keys_are_refused_before_going_upstream() {
  assert_eq!(raw("v5/order/create",&q(&[("source","bybit")])).await.status(),StatusCode::NOT_FOUND);
  assert_eq!(raw("v5/market/kline",&q(&[("category","linear"),("api_key","x")])).await.status(),StatusCode::BAD_REQUEST);
 }
}
