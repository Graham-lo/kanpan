//! Hyperliquid 公开行情在服务端的那一截。2026-10-08 起 Hyperliquid 是和币安、OKX 平起平坐的一家：
//! 用户搜它的永续、加自选、看 K 线、设提醒。永续是 USDC 保证金，看盘里也记 `usd_m`。
//!
//! 看盘键是 coin 名的大写（`hyperliquid/usd_m/BTC`、`KPEPE`），上游要的是原名（`kPEPE`）：凡是服务端
//! 自己拿 coin 名出站的地方（`candles`、持仓量、提醒）都先查 [`coin_name`]（从 `meta` 来，带缓存）。
//! 透传那条路上客户端说的就是上游原名，原样转。
//!
//! * `POST /v1/market/raw/info?source=hyperliquid`：`info` 接口的白名单透传（[`info_request`]）；
//! * `hub`：进程里唯一一条上游 `wss://api.hyperliquid.xyz/ws`，按 (频道, 币) 引用计数地订退，
//!   常驻跟踪与给手机 / 网页的中继共用它（Hyperliquid 的限流按 IP 算，见 `hub` 的说明）；
//! * `relay`：`GET /v1/market/ws/hyperliquid` 那条中继的上行白名单与转发；
//! * `orderflow`：主力订单流的品种表；`alerts`：提醒评估的 1 分钟 K 线来源。
//!
//! 这一家的全部 REST 出站都排 [`PACER`]（按权重记）。
pub mod alerts;
pub mod hub;
pub mod orderflow;
pub mod relay;
use super::outbound::{self,Answers,Memo,Pacer,Reply,Upstream,refuse};
use super::{Bar,Fut};
use crate::error::{ApiError,Result};
use crate::market_meta::{OpenInterest,num};
use axum::body::Bytes;
use axum::http::StatusCode;
use axum::response::Response;
use serde_json::{Map,Value,json};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

pub const SOURCE:&str="hyperliquid";
pub const INFO:&str="https://api.hyperliquid.xyz/info";
pub const HOSTS:&[&str]=&["api.hyperliquid.xyz"];

// ------------------------------------------------------------------ 出站节拍

/// 官方文档（Rate limits and user limits）：REST 每 IP 每分钟合计权重 1200；`allMids` / `l2Book` 这类权重 2，
/// 其余 `info` 请求权重 20，`candleSnapshot` 每回 60 根再加 1。节拍一格 = 权重 2，按每分钟 1000 留余量
/// （这台机器一个出口 IP 给所有用户的透传、提醒补缺、订单流品种表共用，再留两成给偶发的重试）：
/// 一格 120 ms，`meta` 这类占 10 格（1.2 秒）。
pub static PACER:Pacer=Pacer::new(Duration::from_millis(120),Duration::from_secs(12),&[]);

/// 一条 `info` 请求占几格节拍（见 [`PACER`]）。
pub fn cost_of(body:Option<&Value>)->u32 {cost_at(body,chrono::Utc::now().timestamp_millis())}

/// 官方文档（Rate limits）：`candleSnapshot` 每**返回** 60 根另加权重 1（一次最多 5000 根），
/// `fundingHistory` 每返回 20 行另加 1（一页最多 500 行）。返回多少要看问的时间段：按 `startTime`–`endTime`
/// （缺省到 `now`）÷ 周期推出最多几根 / 几行，宁多不少。以前一律按「最多 300 根」记 13 格，
/// 而透传与补缺都可以一口气要 5000 根（权重 104、52 格），节拍少记了四倍。
pub fn cost_at(body:Option<&Value>,now:i64)->u32 {
 let span=|o:&Value|{
  let start=o["startTime"].as_u64().unwrap_or(0);
  o["endTime"].as_u64().unwrap_or(now.max(0) as u64).saturating_sub(start)
 };
 let weight:u64=match body.and_then(|b|b["type"].as_str()) {
  Some("allMids"|"l2Book")=>2,
  Some("candleSnapshot")=>{
   let req=&body.expect("matched")["req"];
   let step=req["interval"].as_str().and_then(interval_ms).unwrap_or(60_000);
   20+(span(req)/step+1).min(SNAPSHOT_MAX as u64).div_ceil(60)
  },
  Some("fundingHistory")=>20+(span(body.expect("matched"))/3_600_000+1).min(FUNDING_PAGE).div_ceil(20),
  _=>20,
 };
 weight.div_ceil(2) as u32
}
/// `fundingHistory` 一页最多几行。
const FUNDING_PAGE:u64=500;
/// 周期的毫秒数（月线按 28 天算：推出来的根数只会多不会少）。
fn interval_ms(interval:&str)->Option<u64> {
 const M:u64=60_000;
 Some(match interval {"1m"=>M,"3m"=>3*M,"5m"=>5*M,"15m"=>15*M,"30m"=>30*M,"1h"=>60*M,"2h"=>120*M,"4h"=>240*M,"8h"=>480*M,"12h"=>720*M,
  "1d"=>1440*M,"3d"=>3*1440*M,"1w"=>7*1440*M,"1M"=>28*1440*M,_=>return None})
}

pub(crate) async fn info_bytes(body:&Value)->anyhow::Result<Bytes> {
 outbound::bytes(&PACER,INFO,&[],Some(body),cost_of(Some(body))).await
}
async fn info_json(body:&Value)->std::result::Result<Value,Upstream> {
 outbound::post_json(&PACER,INFO,body,cost_of(Some(body))).await
}

// ------------------------------------------------------------------ 代号

/// 看盘键：coin 名的大写（`BTC`、`KPEPE`），1–16 个 ASCII 大写字母数字。
pub fn symbol_ok(key:&str)->bool {super::upper_alnum(key,1..=16)}

/// 大写键 → 上游原名（`KPEPE` → `kPEPE`），从 `meta` 来。下架的也留着：历史 K 线还拿得到。
pub fn names_of(meta:&Value)->HashMap<String,String> {
 meta["universe"].as_array().into_iter().flatten().filter_map(|a|{
  let name=a["name"].as_str().filter(|n|hub::valid_coin(n))?;
  Some((name.to_ascii_uppercase(),name.to_owned()))
 }).collect()
}
/// 品种表十分钟一份；拉不动时一小时内的旧表还能用（上新下架一天才几次）。
static NAMES:Memo<HashMap<String,String>>=Memo::new();
pub async fn coin_name(key:&str)->std::result::Result<String,Upstream> {
 let names=NAMES.get(Duration::from_secs(600),Duration::from_secs(3600),||async {
  let table=names_of(&info_json(&json!({"type":"meta"})).await?);
  if table.is_empty() {Err(Upstream::Unavailable)} else {Ok(table)}
 }).await?;
 names.get(key).cloned().ok_or(Upstream::Rejected(404))
}

// ------------------------------------------------------------------ REST 透传（POST info）

/// K 线周期（官方 `candleSnapshot` / `candle` 订阅认的那几档）。
pub const INTERVALS:[&str;14]=["1m","3m","5m","15m","30m","1h","2h","4h","8h","12h","1d","3d","1w","1M"];

fn keys_within(object:&Map<String,Value>,required:&[&str],optional:&[&str])->bool {
 required.iter().all(|k|object.contains_key(*k))&&object.keys().all(|k|required.contains(&k.as_str())||optional.contains(&k.as_str()))
}
fn time(v:Option<&Value>)->Option<u64> {v.and_then(Value::as_u64).filter(|t|*t<=9_999_999_999_999)}

/// 手机发来的 `info` 正文放不放行：`type` 只认 `meta` / `metaAndAssetCtxs` / `allMids` / `candleSnapshot` /
/// `fundingHistory`，字段一个都不能多；放行的按认出来的字段重新拼（手机写进去的别的东西带不上去），
/// 连同这一条答案能给后来者用多久。`now` 是毫秒。
pub fn info_request(body:&[u8],now:i64)->Option<(Value,Duration)> {
 let v:Value=serde_json::from_slice(body).ok()?;
 let o=v.as_object()?;
 let kind=o.get("type")?.as_str()?;
 match kind {
  "meta"|"metaAndAssetCtxs"|"allMids"=>{
   if o.len()!=1 {return None}
   let ttl=match kind {"meta"=>Duration::from_secs(60),"metaAndAssetCtxs"=>Duration::from_secs(2),_=>Duration::from_secs(1)};
   Some((json!({"type":kind}),ttl))
  },
  "candleSnapshot"=>{
   if o.len()!=2 {return None}
   let req=o.get("req")?.as_object()?;
   if !keys_within(req,&["coin","interval","startTime"],&["endTime"]) {return None}
   let coin=req["coin"].as_str().filter(|c|hub::valid_coin(c))?;
   let interval=req["interval"].as_str().filter(|i|INTERVALS.contains(i))?;
   let start=time(req.get("startTime"))?;
   let mut out=json!({"type":kind,"req":{"coin":coin,"interval":interval,"startTime":start}});
   let mut ttl=Duration::from_secs(2);
   if req.contains_key("endTime") {
    let end=time(req.get("endTime"))?;
    out["req"]["endTime"]=json!(end);
    // 截止在一分钟以前的历史页不会再变。
    if (end as i64)<now-60_000 {ttl=Duration::from_secs(60)}
   }
   Some((out,ttl))
  },
  "fundingHistory"=>{
   if !keys_within(o,&["type","coin","startTime"],&["endTime"]) {return None}
   let coin=o["coin"].as_str().filter(|c|hub::valid_coin(c))?;
   let mut out=json!({"type":kind,"coin":coin,"startTime":time(o.get("startTime"))?});
   if o.contains_key("endTime") {out["endTime"]=json!(time(o.get("endTime"))?)}
   Some((out,Duration::from_secs(30)))
  },
  _=>None,
 }
}
/// 上游偶尔答 200 + `null`：不留给后来者。
fn hl_ok(reply:&Reply)->bool {!reply.body.starts_with(b"null")}
static ANSWERS:Answers=Answers::new();

pub async fn raw_post(path:&str,body:Bytes)->Response {
 if path!="info" {return refuse(StatusCode::NOT_FOUND,"unsupported_path")}
 let Some((request,ttl))=info_request(&body,chrono::Utc::now().timestamp_millis()) else {return refuse(StatusCode::BAD_REQUEST,"unsupported_request")};
 let cost=cost_of(Some(&request));
 outbound::pass(ANSWERS.get(request.to_string(),ttl,hl_ok,||async {outbound::send(&PACER,INFO,&[],Some(&request),cost).await}).await)
}

// ------------------------------------------------------------------ K 线（提醒补缺）

fn interval_of(step:i64)->Option<&'static str> {
 Some(match step {60=>"1m",180=>"3m",300=>"5m",900=>"15m",1800=>"30m",3600=>"1h",7200=>"2h",14_400=>"4h",28_800=>"8h",43_200=>"12h",86_400=>"1d",_=>return None})
}
/// 官方文档：一次最多给最近的 5000 根。
const SNAPSHOT_MAX:usize=5000;

/// 一根 `candleSnapshot` / `candle` 推送：`{t,T,s,i,o,c,h,l,v,n}`，价与量是字符串。
pub fn parse_candle(v:&Value)->Option<Bar> {
 let bar=Bar{open_time:v["t"].as_i64()?,open:num(&v["o"])?,high:num(&v["h"])?,low:num(&v["l"])?,close:num(&v["c"])?,volume:num(&v["v"]).unwrap_or(0.0)};
 bar.sane().then_some(bar)
}

pub async fn candles(key:&str,step:i64,start:i64,end:i64)->std::result::Result<Vec<Bar>,Upstream> {
 let Some(interval)=interval_of(step) else {return Err(Upstream::Rejected(400))};
 if !symbol_ok(key) {return Err(Upstream::Rejected(400))}
 let coin=coin_name(key).await?;
 let (from,until)=(start*1000,end*1000);
 let mut out:Vec<Bar>=Vec::new();
 let mut cursor=from;
 for _ in 0..16 {
  if cursor>=until {break}
  let page=info_json(&json!({"type":"candleSnapshot","req":{"coin":coin,"interval":interval,"startTime":cursor,"endTime":until-1}})).await?;
  let rows:Vec<Bar>=page.as_array().into_iter().flatten().filter_map(parse_candle).collect();
  let Some(last)=rows.iter().map(|b|b.open_time).max() else {break};
  let full=rows.len()>=SNAPSHOT_MAX;
  out.extend(rows.into_iter().filter(|b|b.open_time>=from&&b.open_time<until));
  if !full||last<cursor {break}
  cursor=last+step*1000;
 }
 out.sort_by_key(|b|b.open_time);out.dedup_by_key(|b|b.open_time);
 Ok(out)
}

// ------------------------------------------------------------------ 持仓量与资金费率

/// 一只的上下文。
#[derive(Clone,Copy,Debug,PartialEq)]
pub struct Ctx {pub open_interest:Option<f64>,pub mark:Option<f64>,pub funding:Option<f64>}

/// `metaAndAssetCtxs` 答 `[meta, [ctx…]]`，两个数组按下标对齐（官方文档 Perpetuals › Retrieve perpetuals
/// asset contexts）：`openInterest` 是币的个数，`funding` 是**一小时**的费率（Hyperliquid 每小时结算）。键是大写的 coin 名。
pub fn parse_ctxs(body:&Value)->HashMap<String,Ctx> {
 let (Some(universe),Some(ctxs))=(body[0]["universe"].as_array(),body[1].as_array()) else {return HashMap::new()};
 universe.iter().zip(ctxs).filter_map(|(asset,ctx)|{
  let name=asset["name"].as_str().filter(|n|hub::valid_coin(n))?;
  Some((name.to_ascii_uppercase(),Ctx{open_interest:num(&ctx["openInterest"]).filter(|x|*x>=0.0),mark:num(&ctx["markPx"]).filter(|x|*x>0.0),funding:num(&ctx["funding"])}))
 }).collect()
}
static CTXS:Memo<(i64,HashMap<String,Ctx>)>=Memo::new();
async fn ctxs()->Result<Arc<(i64,HashMap<String,Ctx>)>> {
 CTXS.get(Duration::from_secs(15),Duration::from_secs(900),||async {
  let table=parse_ctxs(&info_json(&json!({"type":"metaAndAssetCtxs"})).await?);
  if table.is_empty() {Err(Upstream::Unavailable)} else {Ok((chrono::Utc::now().timestamp_millis(),table))}
 }).await.map_err(outbound::api_error)
}

pub async fn open_interest(key:&str)->Result<OpenInterest> {
 let table=ctxs().await?;
 let ctx=table.1.get(key).ok_or_else(ApiError::missing)?;
 let coins=ctx.open_interest.ok_or_else(ApiError::missing)?;
 Ok(OpenInterest{open_interest:coins,value:ctx.mark.map(|m|m*coins),time:table.0})
}

/// 整张费率表。`rate` 是一小时的费率（和币安、OKX 的八小时不同），`intervalHours` 写明；下一次结算在下一个整点。
pub fn funding_payload(at:i64,table:&HashMap<String,Ctx>)->Value {
 let next=(at.div_euclid(3_600_000)+1)*3_600_000;
 let mut rows:Vec<(&String,f64)>=table.iter().filter_map(|(k,c)|Some((k,c.funding?))).collect();
 rows.sort_by(|a,b|a.0.cmp(b.0));
 let rows:Vec<Value>=rows.into_iter().map(|(k,rate)|json!({"symbol":k,"rate":rate,"nextFundingTime":next})).collect();
 json!({"source":SOURCE,"intervalHours":1,"rows":rows})
}

// ------------------------------------------------------------------ 注册表里的这一家

pub struct Hyperliquid;
pub static HYPERLIQUID:Hyperliquid=Hyperliquid;

impl super::Venue for Hyperliquid {
 fn source(&self)->&'static str {SOURCE}
 fn short_name(&self)->&'static str {"HL"}
 fn market(&self)->&'static str {"usd_m"}
 fn market_key(&self)->&'static str {"hyperliquid/usd_m"}
 fn symbol_ok(&self,symbol:&str)->bool {symbol_ok(symbol)}
 /// 供应量按同名的币查（`BTC` → `BTCUSDT`）。`kPEPE` 这类打包名不猜（`KAITO` 是真名），查不到就不答。
 fn meta_symbol(&self,symbol:&str)->Option<String> {Some(format!("{symbol}USDT"))}
 fn pacer(&self)->Option<&'static Pacer> {Some(&PACER)}
 fn hosts(&self)->&'static [&'static str] {HOSTS}
 fn cost(&self,_path:&str,body:Option<&Value>)->u32 {cost_of(body)}
 fn raw_post<'a>(&'a self,path:&'a str,body:Bytes)->Fut<'a,Response> {Box::pin(raw_post(path,body))}
 fn candles<'a>(&'a self,symbol:&'a str,step:i64,start:i64,end:i64)->Fut<'a,std::result::Result<Vec<Bar>,Upstream>> {Box::pin(candles(symbol,step,start,end))}
 fn open_interest<'a>(&'a self,symbol:&'a str)->Option<Fut<'a,Result<OpenInterest>>> {Some(Box::pin(open_interest(symbol)))}
 fn funding(&self)->Option<Fut<'static,Result<Value>>> {Some(Box::pin(async {let t=ctxs().await?;Ok(funding_payload(t.0,&t.1))}))}
 fn alert_feed(&self)->Option<&'static dyn crate::alerts::KlineFeed> {Some(&alerts::FEED)}
}

#[cfg(test)]
mod tests {
 use super::*;

 const NOW:i64=1_791_000_000_000;

 #[test] fn info_bodies_are_whitelisted_and_rebuilt() {
  let ok=|b:&str|info_request(b.as_bytes(),NOW).map(|(v,_)|v);
  assert_eq!(ok(r#"{"type":"meta"}"#),Some(json!({"type":"meta"})));
  assert_eq!(info_request(br#"{"type":"metaAndAssetCtxs"}"#,NOW).map(|(_,t)|t),Some(Duration::from_secs(2)));
  assert_eq!(ok(r#"{"type":"candleSnapshot","req":{"coin":"kPEPE","interval":"1m","startTime":1790000000000}}"#),
   Some(json!({"type":"candleSnapshot","req":{"coin":"kPEPE","interval":"1m","startTime":1790000000000_u64}})));
  let (_,ttl)=info_request(br#"{"type":"candleSnapshot","req":{"coin":"BTC","interval":"1h","startTime":1,"endTime":1790000000000}}"#,NOW).unwrap();
  assert_eq!(ttl,Duration::from_secs(60),"截止在过去的历史页留得久");
  assert!(ok(r#"{"type":"fundingHistory","coin":"ETH","startTime":1683849600076}"#).is_some());
  for bad in [
   r#"{"type":"userState","user":"0x0"}"#,r#"{"type":"clearinghouseState","user":"0x0"}"#,r#"{"type":"meta","dex":"x"}"#,
   r#"{"type":"candleSnapshot","req":{"coin":"BTC","interval":"7m","startTime":1}}"#,
   r#"{"type":"candleSnapshot","req":{"coin":"BTC-USD","interval":"1m","startTime":1}}"#,
   r#"{"type":"candleSnapshot","req":{"coin":"BTC","interval":"1m"}}"#,
   r#"{"type":"candleSnapshot","req":{"coin":"BTC","interval":"1m","startTime":1,"user":"0x0"}}"#,
   r#"{"type":"candleSnapshot","req":{"coin":"BTC","interval":"1m","startTime":"1"}}"#,
   r#"{"type":"fundingHistory","coin":"ETH"}"#,r#"{"type":"l2Book","coin":"BTC"}"#,"[]","null","",
  ] {assert_eq!(ok(bad),None,"{bad}")}
 }

 #[test] fn names_translate_upper_keys_back_to_the_upstream_spelling() {
  let names=names_of(&serde_json::from_str(orderflow::tests::META).unwrap());
  assert_eq!(names.get("KPEPE").map(String::as_str),Some("kPEPE"));
  assert_eq!(names.get("BTC").map(String::as_str),Some("BTC"));
  assert!(symbol_ok("KPEPE")&&!symbol_ok("kPEPE"));
 }

 /// 夹具照官方文档（Perpetuals › Retrieve perpetuals asset contexts 的示例答复）写。
 #[test] fn asset_contexts_line_up_with_the_universe() {
  let body=json!([{"universe":[{"name":"BTC","szDecimals":5,"maxLeverage":50},{"name":"kPEPE","szDecimals":0,"maxLeverage":10}]},
   [{"dayNtlVlm":"1169046.29406","funding":"0.0000125","impactPxs":["14.3047","14.3444"],"markPx":"14.3161","midPx":"14.314","openInterest":"688.11","oraclePx":"14.32","premium":"0.00031774","prevDayPx":"15.322"},
    {"funding":"","markPx":"0.01","openInterest":"100"}]]);
  let t=parse_ctxs(&body);
  assert_eq!(t["BTC"],Ctx{open_interest:Some(688.11),mark:Some(14.3161),funding:Some(0.0000125)});
  assert_eq!(t["KPEPE"].funding,None);
  let payload=funding_payload(3_600_000*5+10,&t);
  assert_eq!(payload,json!({"source":"hyperliquid","intervalHours":1,"rows":[{"symbol":"BTC","rate":0.0000125,"nextFundingTime":3_600_000*6}]}));
 }

 #[test] fn candles_parse() {
  let bar=parse_candle(&json!({"T":1681924499999_i64,"c":"29258.0","h":"29309.0","i":"15m","l":"29250.0","n":189,"o":"29295.0","s":"BTC","t":1681923600000_i64,"v":"0.98639"})).unwrap();
  assert_eq!(bar,Bar{open_time:1_681_923_600_000,open:29295.0,high:29309.0,low:29250.0,close:29258.0,volume:0.98639});
  assert_eq!(interval_of(60),Some("1m"));assert_eq!(interval_of(21_600),None);
  assert_eq!(cost_of(Some(&json!({"type":"allMids"}))),1);assert_eq!(cost_of(Some(&json!({"type":"meta"}))),10);
 }

 /// 权重按「会返回多少」记：5000 根的 K 线快照是 20 + 84 = 104 权重（52 格），不是 13 格。
 /// 每一条透传放行的正文、补缺发出的每一页，记的格数都不少于官方权重的一半（一格 = 权重 2）。
 #[test] fn weights_follow_what_comes_back() {
  let c=|v:Value|cost_at(Some(&v),NOW);
  assert_eq!(c(json!({"type":"l2Book","coin":"BTC"})),1);
  assert_eq!(c(json!({"type":"metaAndAssetCtxs"})),10);
  assert_eq!(c(json!({"type":"candleSnapshot","req":{"coin":"BTC","interval":"1m","startTime":NOW-300*60_000,"endTime":NOW}})),13,"300 根：20 + 6 → 13 格");
  assert_eq!(c(json!({"type":"candleSnapshot","req":{"coin":"BTC","interval":"1m","startTime":0}})),52,"从 0 开始、不给 endTime：封顶 5000 根，20 + 84");
  assert_eq!(c(json!({"type":"candleSnapshot","req":{"coin":"BTC","interval":"1m","startTime":NOW-60_000,"endTime":NOW-1}})),11);
  assert_eq!(c(json!({"type":"candleSnapshot","req":{"coin":"BTC","interval":"1M","startTime":0}})),17,"月线按 28 天一根算，从 1970 年起约 740 根：20 + 13");
  assert_eq!(c(json!({"type":"candleSnapshot","req":{"coin":"BTC","interval":"1m","startTime":NOW,"endTime":0}})),11,"倒着的时间段按一根记");
  assert_eq!(c(json!({"type":"fundingHistory","coin":"ETH","startTime":0})),23,"一页 500 行：20 + 25");
  assert_eq!(c(json!({"type":"fundingHistory","coin":"ETH","startTime":NOW-3_600_000})),11);
  // 补缺一页（`candles` 发的那种）与透传模糊出来的每一种合法正文：格数 × 2 ≥ 官方权重。
  let mut rng=0x1234_5678_u64;
  for _ in 0..2000 {
   rng^=rng<<13;rng^=rng>>7;rng^=rng<<17;
   let interval=INTERVALS[(rng%14) as usize];
   let step=interval_ms(interval).unwrap() as i64;
   let start=(NOW-((rng>>8)%(6000*step as u64)) as i64).max(0);
   let body=format!(r#"{{"type":"candleSnapshot","req":{{"coin":"BTC","interval":"{interval}","startTime":{start}}}}}"#);
   let (request,_)=info_request(body.as_bytes(),NOW).unwrap();
   let returned=(((NOW-start)/step)+1).min(5000) as u64;
   assert!(u64::from(c(request))*2>=20+returned.div_ceil(60),"{body}");
  }
 }

 #[tokio::test] async fn only_info_is_posted() {
  assert_eq!(raw_post("exchange",Bytes::from_static(br#"{"type":"meta"}"#)).await.status(),StatusCode::NOT_FOUND);
  assert_eq!(raw_post("info",Bytes::from_static(br#"{"type":"userFills","user":"0x0"}"#)).await.status(),StatusCode::BAD_REQUEST);
 }

 // ---------------------------------------------------------------- 补缺 K 线的极端（假上游）

 use crate::venues::outbound::fake;
 use std::sync::Mutex;
 fn snapshot(t:i64)->Value {json!({"t":t,"T":t+59_999,"s":"kPEPE","i":"1m","o":"1","c":"1.5","h":"2","l":"0.5","v":"3","n":1})}
 /// 假 Hyperliquid：`meta` 给品种表；`candleSnapshot` 按 `[startTime, endTime]` 升序给、一次最多 5000 根。
 fn hl_like(first:i64,last:i64,calls:Arc<Mutex<Vec<Value>>>)->fake::Answer {
  Arc::new(move|_:&str,_:&[(String,String)],body:Option<&Value>|{
   let body=body.cloned().unwrap_or_default();
   calls.lock().unwrap().push(body.clone());
   if body["type"]=="meta" {return fake::ok(&json!({"universe":[{"name":"BTC"},{"name":"kPEPE"}]}))}
   let (s,e)=(body["req"]["startTime"].as_i64().unwrap(),body["req"]["endTime"].as_i64().unwrap_or(i64::MAX));
   let rows:Vec<Value>=(0..).map(|i|first+i*60_000).take_while(|t|*t<=last).filter(|t|*t>=s&&*t<=e).take(5000).map(snapshot).collect();
   fake::ok(&Value::Array(rows))
  })
 }
 /// 一万两千根翻三页、一根不缺，订阅名按品种表译回原名；上游无视 `startTime` 同一页反复回、回空、回 `null`、
 /// 坏行，都停得下、收拾干净。
 #[tokio::test] async fn snapshot_paging_survives_hostile_upstreams() {
  let minute=NOW.div_euclid(60_000)*60_000;
  let calls:Arc<Mutex<Vec<Value>>>=Default::default();
  let (start,end)=((minute-12_000*60_000)/1000,minute/1000);
  let bars=fake::UPSTREAM.scope(hl_like(minute-20_000*60_000,minute,calls.clone()),candles("KPEPE",60,start,end)).await.unwrap();
  assert_eq!(bars.len(),12_000);
  assert!(bars.windows(2).all(|w|w[1].open_time-w[0].open_time==60_000));
  let pages:Vec<Value>=calls.lock().unwrap().iter().filter(|b|b["type"]=="candleSnapshot").cloned().collect();
  assert_eq!(pages.len(),3);
  assert!(pages.iter().all(|p|p["req"]["coin"]=="kPEPE"),"按原名问");
  let stuck:fake::Answer=Arc::new(move|_:&str,_:&[(String,String)],body:Option<&Value>|{
   if body.is_some_and(|b|b["type"]=="meta") {return fake::ok(&json!({"universe":[{"name":"kPEPE"}]}))}
   let mut rows:Vec<Value>=(0..5000).map(|i|snapshot(minute-12_000*60_000+i*60_000)).collect();
   rows.push(json!({"t":"bad"}));rows.push(snapshot(minute-12_000*60_000));rows.swap(1,4000);
   fake::ok(&Value::Array(rows))
  });
  let bars=fake::UPSTREAM.scope(stuck,candles("KPEPE",60,start,end)).await.unwrap();
  assert_eq!(bars.len(),5000,"无视 startTime：第二页不前进就停，重复、乱序、坏行收拾干净");
  for body in [json!([]),Value::Null] {
   let answer:fake::Answer=Arc::new(move|_:&str,_:&[(String,String)],b:Option<&Value>|{
    if b.is_some_and(|b|b["type"]=="meta") {fake::ok(&json!({"universe":[{"name":"kPEPE"}]}))} else {fake::ok(&body)}
   });
   assert_eq!(fake::UPSTREAM.scope(answer,candles("KPEPE",60,start,end)).await,Ok(vec![]));
  }
  // 品种表里没有的：不问 K 线，答「没有」。
  assert!(matches!(fake::UPSTREAM.scope(hl_like(0,0,Default::default()),candles("NOPE",60,start,end)).await,Err(Upstream::Rejected(404))));
 }
}
