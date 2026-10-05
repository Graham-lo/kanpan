//! 上游：CNBC 的两个公开接口，以及 ICE 合成公式。
//!
//! 规格原定 Yahoo（六个外汇对的 spark + DX-Y.NYB 的 1m 对表），但 kanpan-sg 上 Yahoo 的每个主机
//! （query1 / query2 / fc.yahoo.com 拿 cookie 的那条也算）第一个请求就回 429「Edge: Too Many Requests」，
//! 这台机器的出口被 Yahoo 整段拒了。按规格的兜底条款换成 CNBC：
//!
//! - **报价** `quote.cnbc.com/quote-html-webservice/restQuote/…`：一次问 `.DXY`（ICE 官方美元指数，实时）
//!   和六个外汇对（`EUR=` 是 EURUSD、`JPY=` 是 USDJPY、`GBP=` 是 GBPUSD、`CAD=` USDCAD、`SEK=` USDSEK、
//!   `CHF=` USDCHF；外汇的 `last_time` 只到分钟）。
//! - **K 线** `ts-api.cnbc.com/harmony/app/bars/.DXY/<档>/<起>/<止>/adjusted/EST5EDT.json`：
//!   起止是美东墙上时间 `YYYYMMDDhhmmss`；档只有 `1M` `5M` `1H` `1D`（`15M` `2H` `4H` 回 `status:"ERROR"`）。
//!   能回溯多久（2026-10-05 实测）：1M 约一个月、5M 约 64 天、1H 约 100 天、1D 十年以上。
//!
//! 有官方 `.DXY` 时直接用官方价；官方价不新鲜（> 2 分钟没动）而外汇对新鲜时，用 ICE 公式合成，
//! 再乘最近一次「官方 ÷ 合成」的校准比（见 [`Calibration`]）。
use std::sync::Mutex;
use std::time::{Duration,Instant};
use chrono::{DateTime,NaiveDate,NaiveDateTime};
use serde_json::Value;
use super::bars::Bar;
use super::calendar;

/// 外汇对在 CNBC 的代号，顺序就是 [`synthetic`] 的参数顺序。
pub const PAIRS:[&str;6]=["EUR=","JPY=","GBP=","CAD=","SEK=","CHF="];
/// 官方美元指数在 CNBC 的代号。
pub const OFFICIAL:&str=".DXY";

/// ICE 美元指数的定义（ICE Futures U.S. 公布的 1973 年 3 月基期公式）：
/// `50.14348112 × EURUSD^-0.576 × USDJPY^0.136 × GBPUSD^-0.119 × USDCAD^0.091 × USDSEK^0.042 × USDCHF^0.036`。
/// 参数顺序同 [`PAIRS`]；任何一个不是正的有限数就答 `None`。
pub fn synthetic(fx:[f64;6])->Option<f64> {
 const WEIGHTS:[f64;6]=[-0.576,0.136,-0.119,0.091,0.042,0.036];
 if fx.iter().any(|v|!v.is_finite()||*v<=0.0) {return None}
 let v=fx.iter().zip(WEIGHTS).fold(50.14348112_f64,|acc,(x,w)|acc*x.powf(w));
 v.is_finite().then_some(v)
}

/// 校准：同一次轮询里官方价与合成价都新鲜时，记下 `官方 ÷ 合成`。
/// 合成价只在官方价断了的时候用，乘上这个比，补的那一段和前后官方价接得上。
/// 第一次校准之前比为 1（照规格：先发未校准的合成价）。
#[derive(Clone,Copy,Debug,PartialEq)]
pub struct Calibration {pub ratio:f64,pub at:i64}
impl Default for Calibration {fn default()->Self {Self{ratio:1.0,at:0}}}
impl Calibration {
 /// 比偏离 1 超过 5% 说明有一边报价坏了，不收。
 pub const MAX_DRIFT:f64=0.05;
 pub fn observe(&mut self,official:f64,synthetic:f64,at:i64)->bool {
  if !(official.is_finite()&&synthetic.is_finite()&&official>0.0&&synthetic>0.0) {return false}
  let ratio=official/synthetic;
  if (ratio-1.0).abs()>Self::MAX_DRIFT {return false}
  *self=Self{ratio,at};
  true
 }
 pub fn apply(&self,synthetic:f64)->f64 {synthetic*self.ratio}
 pub fn calibrated(&self)->bool {self.at>0}
}

/// 报价里的一项。
#[derive(Clone,Debug,PartialEq)]
pub struct Quote {
 pub symbol:String,
 pub last:f64,
 /// 最后成交时刻（UTC 毫秒）。
 pub time:i64,
 pub previous_close:Option<f64>,
}

/// 一次报价轮询读出来的东西。
#[derive(Clone,Debug,Default,PartialEq)]
pub struct Snapshot {pub official:Option<Quote>,pub fx:[Option<Quote>;6]}

fn number(v:&Value)->Option<f64> {
 match v {
  Value::Number(n)=>n.as_f64(),
  Value::String(s)=>s.trim().trim_start_matches('+').replace(',',"").parse().ok(),
  _=>None,
 }.filter(|x:&f64|x.is_finite())
}

/// `2026-10-05T06:11:44.000-0400` → UTC 毫秒。
pub fn quote_time(s:&str)->Option<i64> {
 DateTime::parse_from_str(s,"%Y-%m-%dT%H:%M:%S%.3f%z").ok().map(|t|t.timestamp_millis())
}

/// 报价接口的答复 → [`Snapshot`]。认不出的项、价不是正数的项跳过，不整包作废。
pub fn parse_quote(v:&Value)->Snapshot {
 let mut out=Snapshot::default();
 let items=v.pointer("/FormattedQuoteResult/FormattedQuote").and_then(Value::as_array);
 for item in items.into_iter().flatten() {
  let Some(symbol)=item.get("symbol").and_then(Value::as_str) else {continue};
  let Some(last)=item.get("last").and_then(number).filter(|x|*x>0.0) else {continue};
  let Some(time)=item.get("last_time").and_then(Value::as_str).and_then(quote_time) else {continue};
  let previous_close=item.get("previous_day_closing").and_then(number).filter(|x|*x>0.0);
  let q=Quote{symbol:symbol.to_string(),last,time,previous_close};
  if symbol==OFFICIAL {out.official=Some(q)}
  else if let Some(k)=PAIRS.iter().position(|p|*p==symbol) {out.fx[k]=Some(q)}
 }
 out
}

impl Snapshot {
 /// 六个外汇对都在、而且最旧的一个不早于 `now - max_age`：合成价和它的时刻（取最旧那一对的时刻）。
 pub fn synthetic(&self,now:i64,max_age:i64)->Option<(f64,i64)> {
  let mut fx=[0.0;6];
  let mut oldest=i64::MAX;
  for (k,q) in self.fx.iter().enumerate() {
   let q=q.as_ref()?;
   if now-q.time>max_age {return None}
   fx[k]=q.last;oldest=oldest.min(q.time);
  }
  synthetic(fx).map(|v|(v,oldest))
 }
}

/// K 线接口的一档。
#[derive(Clone,Copy,Debug,PartialEq)]
pub enum BarKind {M1,M5,H1,D1}
impl BarKind {
 pub fn path(self)->&'static str {match self {Self::M1=>"1M",Self::M5=>"5M",Self::H1=>"1H",Self::D1=>"1D"}}
 /// 库里对应的 `interval`。
 pub fn interval(self)->&'static str {match self {Self::M1=>"1m",Self::M5=>"5m",Self::H1=>"1h",Self::D1=>"1d"}}
 pub fn step(self)->i64 {match self {Self::M1=>calendar::MINUTE_MS,Self::M5=>5*calendar::MINUTE_MS,Self::H1=>calendar::HOUR_MS,Self::D1=>calendar::DAY_MS}}
}

pub fn quote_url()->String {
 let symbols=std::iter::once(OFFICIAL).chain(PAIRS).collect::<Vec<_>>().join("|");
 let symbols=symbols.replace('|',"%7C").replace('=',"%3D");
 format!("https://quote.cnbc.com/quote-html-webservice/restQuote/symbolType/symbol?symbols={symbols}&requestMethod=itv&noform=1&partnerId=2&fund=1&exthrs=1&output=json")
}

/// `[from, until]`（UTC 毫秒）换成美东墙上时间填进路径。
pub fn bars_url(kind:BarKind,from:i64,until:i64)->String {
 format!("https://ts-api.cnbc.com/harmony/app/bars/.DXY/{}/{}/{}/adjusted/EST5EDT.json",kind.path(),calendar::cnbc_stamp(from),calendar::cnbc_stamp(until))
}

/// K 线答复。`ERROR` 状态（档不支持、区间里没数据）答空表而不是报错：
/// CNBC 对「这一段没有 K 线」也是这么回的。
pub fn parse_bars(kind:BarKind,v:&Value)->Result<Vec<Bar>,String> {
 if v.get("status").and_then(Value::as_str)==Some("ERROR") {
  let msg=v.get("statusMessage").and_then(Value::as_str).unwrap_or("");
  if msg.contains("barType: null") {return Err(format!("unsupported bar type: {msg}"))}
  return Ok(Vec::new());
 }
 let Some(rows)=v.pointer("/barData/priceBars").and_then(Value::as_array) else {
  return if v.get("barData").is_some() {Ok(Vec::new())} else {Err("no barData".into())};
 };
 let mut out:Vec<Bar>=rows.iter().filter_map(|r|{
  let stamp=r.get("tradeTime").and_then(Value::as_str)?;
  let wall=NaiveDateTime::parse_from_str(stamp,"%Y%m%d%H%M%S").ok()?;
  let t=match kind {
   // 日线的 tradeTime 是交易日（美东零点）：标成那一天 00:00 UTC，见 `calendar::day_label`。
   BarKind::D1=>calendar::day_label(wall.date()),
   _=>r.get("tradeTimeinMills").and_then(Value::as_i64).unwrap_or_else(||calendar::utc_of(wall)),
  };
  let b=Bar{t,o:number(r.get("open")?)?,h:number(r.get("high")?)?,l:number(r.get("low")?)?,c:number(r.get("close")?)?};
  b.sane().then_some(b)
 }).collect();
 out.sort_by_key(|b|b.t);
 out.dedup_by_key(|b|b.t);
 Ok(out)
}

/// 日线标签 → 交易日。
pub fn trading_day(label:i64)->NaiveDate {calendar::label_date(label)}

/// 两次请求之间至少隔这么久：整个进程对 CNBC 的请求串在一起，不会突发。
pub const PACING:Duration=Duration::from_millis(1000);
/// 一次请求最多等多久。
pub const TIMEOUT:Duration=Duration::from_secs(15);
/// 答复体上限：十年日线约 0.4 MB、两天 1M 约 0.3 MB，8 MB 封顶只为挡住异常的大体。
pub const MAX_BODY:usize=8<<20;

#[derive(Debug)]
pub enum FetchError {
 /// 429 / 5xx：上游要我们慢一点。
 Throttled(u16),
 Status(u16),
 Other(String),
}
impl std::fmt::Display for FetchError {
 fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result {
  match self {Self::Throttled(s)=>write!(f,"throttled ({s})"),Self::Status(s)=>write!(f,"status {s}"),Self::Other(e)=>f.write_str(e)}
 }
}

/// GET 一个 CNBC 地址，读成 JSON。全进程串行、相邻两次至少隔 [`PACING`]。
pub async fn get(url:&str)->Result<Value,FetchError> {
 static GATE:tokio::sync::Mutex<Option<Instant>>=tokio::sync::Mutex::const_new(None);
 let mut last=GATE.lock().await;
 if let Some(at)=*last {
  let wait=PACING.saturating_sub(at.elapsed());
  if !wait.is_zero() {tokio::time::sleep(wait).await}
 }
 *last=Some(Instant::now());
 let resp=crate::http::shared().get(url).timeout(TIMEOUT).header("Accept","application/json").send().await
  .map_err(|e|FetchError::Other(e.without_url().to_string()))?;
 drop(last);
 let status=resp.status().as_u16();
 if status==429||status>=500 {return Err(FetchError::Throttled(status))}
 if status!=200 {return Err(FetchError::Status(status))}
 let mut resp=resp;
 let mut body=Vec::new();
 while let Some(chunk)=resp.chunk().await.map_err(|e|FetchError::Other(e.without_url().to_string()))? {
  if body.len()+chunk.len()>MAX_BODY {return Err(FetchError::Other("body too large".into()))}
  body.extend_from_slice(&chunk);
 }
 serde_json::from_slice(&body).map_err(|e|FetchError::Other(format!("json: {e}")))
}

pub async fn quote()->Result<Snapshot,FetchError> {get(&quote_url()).await.map(|v|parse_quote(&v))}

pub async fn bars(kind:BarKind,from:i64,until:i64)->Result<Vec<Bar>,FetchError> {
 let v=get(&bars_url(kind,from,until)).await?;
 parse_bars(kind,&v).map_err(FetchError::Other)
}

/// 日志节流：同一类消息一小时最多说一次（上游挂一夜不会刷几千行）。
pub struct Quiet {last:Mutex<Option<Instant>>,every:Duration}
impl Quiet {
 pub const fn hourly()->Self {Self{last:Mutex::new(None),every:Duration::from_secs(3600)}}
 pub fn ready(&self)->bool {
  let mut last=self.last.lock().unwrap_or_else(|e|e.into_inner());
  if last.is_some_and(|at|at.elapsed()<self.every) {return false}
  *last=Some(Instant::now());
  true
 }
}

#[cfg(test)]
mod tests {
 use super::*;
 fn fixture(name:&str)->Value {
  let text=match name {
   "quote"=>include_str!("../../../tests/fixtures/cnbc-dxy-quote.json"),
   "1m"=>include_str!("../../../tests/fixtures/cnbc-dxy-1m.json"),
   "1h"=>include_str!("../../../tests/fixtures/cnbc-dxy-1h.json"),
   "1d"=>include_str!("../../../tests/fixtures/cnbc-dxy-1d.json"),
   "15m-error"=>include_str!("../../../tests/fixtures/cnbc-dxy-15m-error.json"),
   _=>unreachable!(),
  };
  serde_json::from_str(text).unwrap()
 }
 fn ms(s:&str)->i64 {NaiveDateTime::parse_from_str(s,"%Y-%m-%d %H:%M").unwrap().and_utc().timestamp_millis()}

 #[test] fn the_ice_formula_matches_the_definition() {
  // 基期：所有汇率都是 1 时就是常数本身。
  assert!((synthetic([1.0;6]).unwrap()-50.14348112).abs()<1e-9);
  // 欧元涨 1%，指数按 -0.576 的权跌。
  let base=synthetic([1.1,150.0,1.3,1.4,10.0,0.85]).unwrap();
  let up=synthetic([1.1*1.01,150.0,1.3,1.4,10.0,0.85]).unwrap();
  assert!(((up/base).ln()-(-0.576*1.01_f64.ln())).abs()<1e-12);
  assert!(synthetic([1.1,0.0,1.3,1.4,10.0,0.85]).is_none());
  assert!(synthetic([1.1,f64::NAN,1.3,1.4,10.0,0.85]).is_none());
 }

 #[test] fn the_fixture_quote_synthesises_close_to_the_official_index() {
  let snap=parse_quote(&fixture("quote"));
  let official=snap.official.clone().unwrap();
  assert_eq!(official.last,102.185);
  assert_eq!(official.previous_close,Some(101.932));
  assert_eq!(official.time,ms("2026-10-05 10:11")+44_000);
  assert!(snap.fx.iter().all(Option::is_some));
  assert_eq!(snap.fx[1].as_ref().unwrap().last,157.92);
  let now=official.time;
  let (v,at)=snap.synthetic(now,180_000).unwrap();
  assert_eq!(at,ms("2026-10-05 10:11"),"the oldest pair's minute");
  assert!((v-102.199).abs()<0.001,"{v}");
  assert!((v/official.last-1.0).abs()<0.0005,"synthetic within 0.05% of ICE");
  // 外汇对太旧就不合成。
  assert!(snap.synthetic(now+10*60_000,180_000).is_none());
 }

 #[test] fn calibration_scales_synthetic_onto_the_official_level() {
  let mut c=Calibration::default();
  assert!(!c.calibrated());
  assert_eq!(c.apply(102.0),102.0,"raw synthetic before the first calibration");
  assert!(c.observe(102.185,102.199090637187,1));
  assert!((c.ratio-0.99986212561).abs()<1e-9);
  assert!((c.apply(102.199090637187)-102.185).abs()<1e-9);
  // 一边坏了（偏 6%）不收，保留上一次。
  assert!(!c.observe(108.0,102.0,2));
  assert_eq!(c.at,1);
  assert!(!c.observe(0.0,102.0,3));
 }

 #[test] fn minute_bars_parse_from_the_fixture() {
  let bars=parse_bars(BarKind::M1,&fixture("1m")).unwrap();
  assert_eq!(bars.len(),15);
  assert_eq!(bars[0],Bar{t:ms("2026-10-05 09:30"),o:102.112,h:102.122,l:102.108,c:102.12});
  assert_eq!(bars[0].t,1791192600000);
  assert!(bars.windows(2).all(|w|w[1].t-w[0].t==60_000));
 }

 #[test] fn hourly_bars_keep_the_et_clock_and_daily_bars_are_labelled_by_trading_date() {
  let hours=parse_bars(BarKind::H1,&fixture("1h")).unwrap();
  assert_eq!(hours.len(),8);
  // 周五 17:00 ET 那根落在休市窗口里——解析不管，采集时按日历丢。
  let friday_break=hours.iter().find(|b|b.t==ms("2026-10-02 21:00")).unwrap();
  assert!(!calendar::is_open(friday_break.t));
  assert!(calendar::is_open(ms("2026-10-04 22:00")),"Sunday 18:00 ET bar is in session");
  let days=parse_bars(BarKind::D1,&fixture("1d")).unwrap();
  assert_eq!(days.len(),10);
  assert_eq!(days[0].t,ms("2026-09-21 00:00"));
  let last=days.last().unwrap();
  assert_eq!(last.t,ms("2026-10-02 00:00"));
  assert_eq!(last.c,101.932);
  assert_eq!(trading_day(last.t),NaiveDate::from_ymd_opt(2026,10,2).unwrap());
 }

 #[test] fn an_unsupported_bar_type_is_an_error_but_an_empty_window_is_not() {
  assert!(parse_bars(BarKind::M5,&fixture("15m-error")).is_err());
  let empty=serde_json::json!({"status":"ERROR","statusMessage":"No data found"});
  assert_eq!(parse_bars(BarKind::M1,&empty).unwrap(),vec![]);
  assert!(parse_bars(BarKind::M1,&serde_json::json!({"oops":1})).is_err());
 }

 #[test] fn urls_use_eastern_wall_clock() {
  assert_eq!(bars_url(BarKind::M1,ms("2026-10-05 09:30"),ms("2026-10-05 09:45")),
   "https://ts-api.cnbc.com/harmony/app/bars/.DXY/1M/20261005053000/20261005054500/adjusted/EST5EDT.json");
  assert!(quote_url().contains("symbols=.DXY%7CEUR%3D%7CJPY%3D%7CGBP%3D%7CCAD%3D%7CSEK%3D%7CCHF%3D&"));
 }

 #[test] fn bad_quote_items_are_skipped_not_fatal() {
  let v=serde_json::json!({"FormattedQuoteResult":{"FormattedQuote":[
   {"symbol":".DXY","last":"1,02.5","last_time":"2026-10-05T06:11:44.000-0400"},
   {"symbol":"EUR=","last":"UNCH","last_time":"2026-10-05T06:11:00.000-0400"},
   {"symbol":"JPY=","last":"157.9","last_time":"garbage"}]}});
  let s=parse_quote(&v);
  assert_eq!(s.official.unwrap().last,102.5);
  assert!(s.fx.iter().all(Option::is_none));
 }
}
