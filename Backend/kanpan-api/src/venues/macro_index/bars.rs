//! K 线：存哪几档、14 档周期各从哪一档聚、怎么聚、怎么答成币安的行。
//!
//! 库里只存四档（`macro_bars.interval`）：`1m`、`5m`、`1h`、`1d`。其余十档在读的时候聚：
//!
//! | 周期 | 源 | 对齐 |
//! | --- | --- | --- |
//! | 1m 3m | 1m | 从 1970-01-01 00:00 UTC 起按步长切（同币安） |
//! | 5m 15m 30m | 5m | 同上 |
//! | 1h 2h 4h 6h 12h | 1h | 同上 |
//! | 1d | 1d | 交易日（18:00 → 17:00 ET），标签是交易日当天 00:00 UTC（见 `calendar::day_label`） |
//! | 1w 1M 1y | 1d | 按交易日的日期聚：周一 / 月初 / 年初 00:00 UTC |
//!
//! CNBC 没有 15 分钟以及 2h / 4h 的原生 K 线（问了回 `status:"ERROR"`），所以 15m 从 5m 聚。
use chrono::{Datelike,Duration,NaiveDate};
use serde_json::{Value,json};
use super::calendar::{self,DAY_MS,HOUR_MS,MINUTE_MS};

/// 一根 K 线。`t` 是开盘时刻（UTC 毫秒）；没有成交量（指数没有量）。
#[derive(Clone,Copy,Debug,PartialEq)]
pub struct Bar {pub t:i64,pub o:f64,pub h:f64,pub l:f64,pub c:f64}
impl Bar {
 pub fn flat(t:i64,p:f64)->Self {Self{t,o:p,h:p,l:p,c:p}}
 /// 一笔价落进这一根。
 pub fn tick(&mut self,p:f64) {self.h=self.h.max(p);self.l=self.l.min(p);self.c=p;}
 /// 后面那一根并进来（`next` 比自己晚）。
 pub fn absorb(&mut self,next:&Bar) {self.h=self.h.max(next.h);self.l=self.l.min(next.l);self.c=next.c;}
 /// 四个价都是正的有限数，高低包得住开收。
 pub fn sane(&self)->bool {
  [self.o,self.h,self.l,self.c].iter().all(|v|v.is_finite()&&*v>0.0)&&self.h>=self.o.max(self.c)&&self.l<=self.o.min(self.c)
 }
}

/// 库里存的四档。
pub const STORED:[&str;4]=["1m","5m","1h","1d"];

/// 一档周期怎么切。
#[derive(Clone,Copy,Debug,PartialEq)]
pub enum Span {Fixed(i64),Week,Month,Year}

/// 一档周期：从哪一档源聚、怎么切。
#[derive(Clone,Copy,Debug,PartialEq)]
pub struct Spec {pub interval:&'static str,pub source:&'static str,pub span:Span}

/// KanpanCore `Interval` 的 14 档（顺序照抄 `instruments::INTERVALS`）。
pub fn spec(interval:&str)->Option<Spec> {
 let (interval,source,span)=match interval {
  "1m"=>("1m","1m",Span::Fixed(MINUTE_MS)),
  "3m"=>("3m","1m",Span::Fixed(3*MINUTE_MS)),
  "5m"=>("5m","5m",Span::Fixed(5*MINUTE_MS)),
  "15m"=>("15m","5m",Span::Fixed(15*MINUTE_MS)),
  "30m"=>("30m","5m",Span::Fixed(30*MINUTE_MS)),
  "1h"=>("1h","1h",Span::Fixed(HOUR_MS)),
  "2h"=>("2h","1h",Span::Fixed(2*HOUR_MS)),
  "4h"=>("4h","1h",Span::Fixed(4*HOUR_MS)),
  "6h"=>("6h","1h",Span::Fixed(6*HOUR_MS)),
  "12h"=>("12h","1h",Span::Fixed(12*HOUR_MS)),
  "1d"=>("1d","1d",Span::Fixed(DAY_MS)),
  "1w"=>("1w","1d",Span::Week),
  "1M"=>("1M","1d",Span::Month),
  "1y"=>("1y","1d",Span::Year),
  _=>return None,
 };
 Some(Spec{interval,source,span})
}

/// 源那一档一根多长（`1d` 按 24 小时算，只用来估根数）。
pub fn source_step(source:&str)->i64 {
 match source {"1m"=>MINUTE_MS,"5m"=>5*MINUTE_MS,"1h"=>HOUR_MS,_=>DAY_MS}
}

impl Spec {
 /// 一根目标 K 线最多由几根源 K 线组成（多拿几根不要紧，少拿就凑不齐）。
 pub fn factor(&self)->usize {
  match self.span {
   Span::Fixed(step)=>((step/source_step(self.source)).max(1)) as usize,
   // 交易日只有周一到周五：一周最多 5 根、一个月最多 23 根、一年最多 262 根。
   Span::Week=>5,Span::Month=>23,Span::Year=>262,
  }
 }
}

fn date_of(t:i64)->NaiveDate {calendar::label_date(t)}
fn first_of_month(d:NaiveDate)->NaiveDate {NaiveDate::from_ymd_opt(d.year(),d.month(),1).unwrap_or(d)}
fn next_month(d:NaiveDate)->NaiveDate {
 let (y,m)=if d.month()==12 {(d.year()+1,1)} else {(d.year(),d.month()+1)};
 NaiveDate::from_ymd_opt(y,m,1).unwrap_or(d)
}

/// `t` 落在哪一根（开盘时刻）。
pub fn bucket(span:Span,t:i64)->i64 {
 match span {
  Span::Fixed(step)=>t.div_euclid(step)*step,
  Span::Week=>{let d=date_of(t);calendar::day_label(d-Duration::days(d.weekday().num_days_from_monday() as i64))}
  Span::Month=>calendar::day_label(first_of_month(date_of(t))),
  Span::Year=>calendar::day_label(NaiveDate::from_ymd_opt(date_of(t).year(),1,1).unwrap_or_default()),
 }
}

/// 开盘时刻为 `open` 的那一根的收盘时刻：下一根的开盘时刻减 1 毫秒（币安口径）。
pub fn close_time(span:Span,open:i64)->i64 {
 match span {
  Span::Fixed(step)=>open+step-1,
  Span::Week=>open+7*DAY_MS-1,
  Span::Month=>calendar::day_label(next_month(date_of(open)))-1,
  Span::Year=>calendar::day_label(NaiveDate::from_ymd_opt(date_of(open).year()+1,1,1).unwrap_or_default())-1,
 }
}

/// 按时间升序的源 K 线聚成目标周期（也升序）。开盘取第一根的开、收盘取最后一根的收。
pub fn aggregate(rows:&[Bar],span:Span)->Vec<Bar> {
 let mut out:Vec<Bar>=Vec::new();
 for r in rows {
  let b=bucket(span,r.t);
  match out.last_mut() {
   Some(last) if last.t==b=>last.absorb(r),
   _=>out.push(Bar{t:b,..*r}),
  }
 }
 out
}

/// 价格写成字符串：三位小数（`tickSize` 0.001）。
pub fn price(v:f64)->String {format!("{v:.3}")}

/// 币安 `/fapi/v1/klines` 的一行：`[openTime,open,high,low,close,volume,closeTime,quoteVolume,trades,takerBase,takerQuote,ignore]`。
/// 指数没有成交量：量、额、笔数一律 `"0"` / `0`。
pub fn row(b:&Bar,span:Span)->Value {
 json!([b.t,price(b.o),price(b.h),price(b.l),price(b.c),"0",close_time(span,b.t),"0",0,"0","0","0"])
}

/// 一次 K 线请求要从库里读哪一段源 K 线。
#[derive(Debug,PartialEq)]
pub struct Plan {pub source:&'static str,pub from:Option<i64>,pub until:Option<i64>,pub ascending:bool,pub limit:i64}

/// 币安的语义：`startTime` / `endTime` 都按开盘时刻、含端点；只给 `startTime` 时从它往后数 `limit` 根，
/// 否则取截止 `endTime`（缺省为现在）的最后 `limit` 根。
pub fn plan(spec:&Spec,start:Option<i64>,end:Option<i64>,limit:usize)->Plan {
 // 多读一根目标 K 线的量：边上那一根可能只读到一半，要扔掉。
 let limit=((limit+1)*spec.factor()) as i64;
 // 目标 K 线 `[b, b+span)` 只要开盘时刻 ≤ endTime 就算，所以源要读到这一根的末尾。
 let until=end.map(|e|close_time(spec.span,bucket(spec.span,e)));
 match start {
  // 开盘时刻早于 startTime 的那一根不算（币安口径），源从第一根开盘时刻 ≥ startTime 的那一根读起。
  Some(s)=>{
   let b=bucket(spec.span,s);
   let from=if b==s {s} else {close_time(spec.span,b)+1};
   Plan{source:spec.source,from:Some(from),until,ascending:true,limit}
  }
  None=>Plan{source:spec.source,from:None,until,ascending:false,limit},
 }
}

/// 读回来的源 K 线（升序）→ 答复里的目标 K 线。`full` 是「读满了 `plan.limit`」：
/// 那时读的那一头可能只拿到半根，扔掉。
pub fn select(spec:&Spec,rows:&[Bar],plan:&Plan,start:Option<i64>,end:Option<i64>,limit:usize)->Vec<Bar> {
 let mut out=aggregate(rows,spec.span);
 let full=rows.len() as i64>=plan.limit;
 if full {if plan.ascending {out.pop();} else if !out.is_empty() {out.remove(0);}}
 out.retain(|b|start.is_none_or(|s|b.t>=s)&&end.is_none_or(|e|b.t<=e));
 if plan.ascending {out.truncate(limit)} else if out.len()>limit {out.drain(..out.len()-limit);}
 out
}

#[cfg(test)]
mod tests {
 use super::*;
 fn ms(s:&str)->i64 {chrono::NaiveDateTime::parse_from_str(s,"%Y-%m-%d %H:%M").unwrap().and_utc().timestamp_millis()}
 fn b(t:i64,o:f64,h:f64,l:f64,c:f64)->Bar {Bar{t,o,h,l,c}}

 #[test] fn every_client_interval_has_a_stored_source() {
  for iv in crate::instruments::INTERVALS {
   let s=spec(iv).unwrap_or_else(||panic!("{iv}"));
   assert!(STORED.contains(&s.source),"{iv} is aggregated from a stored interval");
   if let Span::Fixed(step)=s.span {assert_eq!(step%source_step(s.source),0,"{iv} is a whole number of {}",s.source)}
  }
  assert!(spec("8h").is_none());
  assert_eq!(spec("15m").unwrap().source,"5m");
  assert_eq!(spec("12h").unwrap().factor(),12);
 }

 #[test] fn one_minute_bars_roll_up_into_coarser_ones() {
  let t0=ms("2026-10-05 09:30");
  let rows:Vec<Bar>=(0..7).map(|k|b(t0+k*MINUTE_MS,100.0+k as f64,101.0+k as f64,99.0+k as f64,100.5+k as f64)).collect();
  let three=aggregate(&rows,Span::Fixed(3*MINUTE_MS));
  assert_eq!(three.len(),3,"09:30, 09:33, 09:36");
  assert_eq!(three[0],b(t0,100.0,103.0,99.0,102.5));
  assert_eq!(three[2],b(t0+6*MINUTE_MS,106.0,107.0,105.0,106.5));
  // 5 分钟从 1970 起切：09:30 和 09:35 两根。
  let five=aggregate(&rows,Span::Fixed(5*MINUTE_MS));
  assert_eq!(five.iter().map(|x|x.t).collect::<Vec<_>>(),vec![t0,t0+5*MINUTE_MS]);
  assert_eq!(five[0].c,104.5);assert_eq!(five[1].o,105.0);
  // 4 小时按 UTC 0/4/8/12/16/20 点切。
  assert_eq!(bucket(Span::Fixed(4*HOUR_MS),ms("2026-10-05 09:30")),ms("2026-10-05 08:00"));
 }

 #[test] fn daily_bars_roll_up_by_trading_date_into_weeks_months_and_years() {
  // 周一 10-05 到下周一 10-12（周末没有交易日）。
  let days:Vec<Bar>=["2026-09-30","2026-10-01","2026-10-02","2026-10-05","2026-10-06","2026-10-12"].iter().enumerate()
   .map(|(k,d)|b(ms(&format!("{d} 00:00")),100.0+k as f64,102.0+k as f64,99.0,101.0+k as f64)).collect();
  let weeks=aggregate(&days,Span::Week);
  assert_eq!(weeks.iter().map(|w|w.t).collect::<Vec<_>>(),vec![ms("2026-09-28 00:00"),ms("2026-10-05 00:00"),ms("2026-10-12 00:00")]);
  assert_eq!(weeks[0],b(ms("2026-09-28 00:00"),100.0,104.0,99.0,103.0));
  assert_eq!(close_time(Span::Week,weeks[0].t),ms("2026-10-05 00:00")-1);
  let months=aggregate(&days,Span::Month);
  assert_eq!(months.iter().map(|m|m.t).collect::<Vec<_>>(),vec![ms("2026-09-01 00:00"),ms("2026-10-01 00:00")]);
  assert_eq!(close_time(Span::Month,months[0].t),ms("2026-10-01 00:00")-1);
  assert_eq!(close_time(Span::Month,ms("2026-12-01 00:00")),ms("2027-01-01 00:00")-1);
  let years=aggregate(&days,Span::Year);
  assert_eq!(years.len(),1);assert_eq!(years[0].t,ms("2026-01-01 00:00"));
  assert_eq!(close_time(Span::Year,years[0].t),ms("2027-01-01 00:00")-1);
  assert_eq!(close_time(Span::Fixed(DAY_MS),ms("2026-10-05 00:00")),ms("2026-10-06 00:00")-1);
 }

 #[test] fn rows_are_binance_kline_arrays_with_three_decimals() {
  let r=row(&b(ms("2026-10-05 09:30"),102.112,102.122,102.108,102.12),Span::Fixed(MINUTE_MS));
  assert_eq!(r,json!([ms("2026-10-05 09:30"),"102.112","102.122","102.108","102.120","0",ms("2026-10-05 09:31")-1,"0",0,"0","0","0"]));
 }

 #[test] fn the_latest_bars_drop_a_half_read_edge() {
  let s=spec("3m").unwrap();
  let t0=ms("2026-10-05 09:30");
  // 要 2 根 3m：读 (2+1)*3 = 9 根 1m（09:31–09:39），倒着读到的最早那一头 09:30 那根只有半根，扔掉；
  // 最新那根 09:39 还在走，照样给（同币安：末根是没收完的那一根）。
  let p=plan(&s,None,None,2);
  assert_eq!(p,Plan{source:"1m",from:None,until:None,ascending:false,limit:9});
  let rows:Vec<Bar>=(1..10).map(|k|Bar::flat(t0+k*MINUTE_MS,100.0+k as f64)).collect();
  let out=select(&s,&rows,&p,None,None,2);
  assert_eq!(out.iter().map(|x|x.t).collect::<Vec<_>>(),vec![t0+6*MINUTE_MS,t0+9*MINUTE_MS]);
  assert_eq!((out[0].o,out[0].c),(106.0,108.0));
  let out=select(&s,&rows,&p,None,None,5);
  assert_eq!(out.first().map(|x|x.t),Some(t0+3*MINUTE_MS),"the half-read 09:30 bucket never shows up");
  // 从 startTime 往后数：09:30 那根开盘早于 startTime，不算，源从 09:33 读起；读满了，最后一头也扔。
  let p=plan(&s,Some(t0+MINUTE_MS),None,2);
  assert_eq!(p.from,Some(t0+3*MINUTE_MS));assert!(p.ascending);
  let rows:Vec<Bar>=(3..12).map(|k|Bar::flat(t0+k*MINUTE_MS,100.0+k as f64)).collect();
  let out=select(&s,&rows,&p,Some(t0+MINUTE_MS),None,2);
  assert_eq!(out.iter().map(|x|x.t).collect::<Vec<_>>(),vec![t0+3*MINUTE_MS,t0+6*MINUTE_MS]);
  assert_eq!(plan(&spec("1M").unwrap(),Some(ms("2026-10-05 00:00")),None,1).from,Some(ms("2026-11-01 00:00")));
  assert_eq!(plan(&spec("1w").unwrap(),Some(ms("2026-10-05 00:00")),None,1).from,Some(ms("2026-10-05 00:00")));
  // endTime 落在一根中间：这一根算（开盘时刻 ≤ endTime），源读到它的末尾。
  let p=plan(&s,None,Some(t0+4*MINUTE_MS),5);
  assert_eq!(p.until,Some(t0+6*MINUTE_MS-1));
 }
}
