//! 足迹图历史（2026-10-07，网页版足迹图补历史）：每一分钟、每一个价位桶里主动买与主动卖各成交了多少美元。
//!
//! * 记：跟踪任务收到的每一笔成交（和 `flow.rs` 同一批常驻在跟的 base、同一个去重之后的入口，三家现货与永续；
//!   交割合约有基差，价对不上，不算）按交易所给的成交时刻（离此刻 10 秒以上不信，见 `minutes::trade_time`）分到那一分钟，
//!   每个币的价落进桶 `floor(价 ÷ 步长)`，主动买（吃卖一）/ 主动卖（吃买一）分开加美元额。
//! * 步长：一分钟开头取这一刻价 × 0.0002，取到最近的 1 / 2 / 5 × 10ⁿ，不小于这只几家里最小的跳价；
//!   价在原步长的 0.6–1.8 倍之间走的时候不换（免得在 2 与 5 的分界上来回跳）。步长写在这一行上，同一分钟内不变。
//! * 一只 base 一分钟一行（`orderflow_footprint`，迁移 0051）：`levels` 打包成字节——第一个桶号（i64 小端），
//!   然后每档：桶号与上一档的差（无符号变长整数）、买额（f32）、卖额（f32）。BTC 一分钟一两百档、约 2 KB。
//!   写库、合并、清理见 `minutes.rs`；同一分钟两份步长不一样（停机交出的半分钟和重启后的另半分钟恰好换了步长）的按桶的中点并到粗的那个上。
//! * 接口 `GET /v1/market/orderflow/footprint?symbol=BTCUSDT&from=&to=` →
//!   `{"symbol","step","minutes":[{"t":分钟起点毫秒,"rows":[[价,主动买美元,主动卖美元],…]},…]}`：
//!   `price` 是桶的下沿、按价升序；`symbol` 是币安 U 本位永续的写法，`1000PEPEUSDT` 的价按 1000 个币报。
//!   `to` 缺省此刻、`from` 缺省 `to` 前 1 小时，超过 24 小时回 400；两端按分钟向下取整，闭区间。
//!   区间里步长不止一个（价走出了 0.6–1.8 倍）的，整段按最粗的那个报，细的按桶中点并过去；`step` 是那个最粗的。
//!   没在跟的 base 回 200、`step:null`、空 `minutes`，不读库、也不因此起跟。美元额取整，两边都取整成 0 的档不报。
//!   鉴权、合并读库、gzip 与 `/flow` 同一套：不要登录，同样的请求 20 秒内合成一次读库，答复带 `Cache-Control: public, max-age=20`，读库占 `HISTORY_READS`。
use super::minutes::{self,MINUTE_MS,Reader,Row};
use super::{Answer,Answers,HISTORY_READS,POOL,REGISTRY,accepts_gzip,json_number,now_ms,packed};
use crate::AppState;
use crate::error::{ApiError,Params,Result};
use crate::storage_budget::{self,Budget};
use axum::extract::State;
use axum::response::Response;
use serde::Deserialize;
use sqlx::postgres::{PgPool,PgRow,Postgres};
use sqlx::query_builder::Separated;
use sqlx::Row as _;
use std::collections::BTreeMap;
use std::sync::OnceLock;
use std::sync::atomic::AtomicU64;
use std::time::Duration;
use tokio::sync::mpsc;

pub(super) const PATH:&str="/v1/market/orderflow/footprint";
/// 步长 ≈ 价 × 这个数（万分之二）。
const STEP_RATIO:f64=0.000_2;
/// 价在原步长的这个倍数范围里走不换步长。
const KEEP_BELOW:f64=0.6;
const KEEP_ABOVE:f64=1.8;
const TTL:Duration=Duration::from_secs(20);
const CACHE_CONTROL:&str="public, max-age=20";
const DEFAULT_SPAN_MS:i64=60*MINUTE_MS;
const MAX_SPAN_MS:i64=24*60*MINUTE_MS;
const QUEUE:usize=4096;

/// 取到最近的 1 / 2 / 5 × 10ⁿ（线性距离最近；1.5、3.5、7.5 是分界）。
pub(super) fn nice(x:f64)->f64 {
 if !(x.is_finite()&&x>0.0) {return 0.0}
 let e=x.log10().floor() as i32;
 let m=x/10f64.powi(e);
 let c=[1.0,2.0,5.0,10.0].into_iter().min_by(|a:&f64,b:&f64|(m-a).abs().total_cmp(&(m-b).abs())).unwrap_or(1.0);
 // 负的指数用除法，`2 ÷ 10⁹` 比 `2 × 10⁻⁹` 更贴近十进制的 2e-9。
 if e>=0 {c*10f64.powi(e)} else {c/10f64.powi(-e)}
}

/// 这一刻的步长：价 × 万分之二取整到 1/2/5，不小于跳价 `tick`；原来的步长还在 0.6–1.8 倍范围里就不换。
pub(super) fn step(price:f64,tick:f64,current:Option<f64>)->f64 {
 let raw=price*STEP_RATIO;
 let floor=|s:f64|if tick>0.0 {s.max(tick)} else {s};
 if let Some(c)=current.filter(|c|*c>0.0) && raw>=c*KEEP_BELOW && raw<=c*KEEP_ABOVE {return floor(c)}
 floor(nice(raw))
}

/// 价落在第几个桶：`floor(价 ÷ 步长)`，正好压在边上的（`60010 ÷ 10` 算出 6000.999…）往上靠。
pub(super) fn bucket(price:f64,step:f64)->i64 {(price/step*(1.0+1e-9)).floor() as i64}

fn same_step(a:f64,b:f64)->bool {(a-b).abs()<=1e-9*a.abs().max(b.abs())}

/// 一分钟：步长与各桶（桶号 → 主动买美元，主动卖美元）。
#[derive(Clone,Debug,PartialEq)]
pub(super) struct Minute {pub minute_ms:i64,pub step:f64,pub levels:BTreeMap<i64,(f64,f64)>}

impl Minute {
 fn new(minute_ms:i64,step:f64)->Self {Self{minute_ms,step,levels:BTreeMap::new()}}

 fn add(&mut self,price:f64,usd:f64,buy:bool) {
  let level=self.levels.entry(bucket(price,self.step)).or_default();
  if buy {level.0+=usd} else {level.1+=usd}
 }

 /// 各桶换到更粗的步长 `to` 上：按桶的中点重新落桶。
 fn rebucket(&self,to:f64)->BTreeMap<i64,(f64,f64)> {
  if same_step(self.step,to) {return self.levels.clone()}
  let mut out:BTreeMap<i64,(f64,f64)>=BTreeMap::new();
  for (&i,&(buy,sell)) in &self.levels {
   let level=out.entry(((i as f64+0.5)*self.step/to).floor() as i64).or_default();
   level.0+=buy;level.1+=sell;
  }
  out
 }

 pub fn pack(&self)->Vec<u8> {
  let mut out=Vec::with_capacity(8+self.levels.len()*10);
  let Some((&first,_))=self.levels.first_key_value() else {return out};
  out.extend_from_slice(&first.to_le_bytes());
  let mut previous=first;
  for (&i,&(buy,sell)) in &self.levels {
   minutes::put_uvarint(&mut out,(i-previous) as u64);
   out.extend_from_slice(&(buy as f32).to_le_bytes());
   out.extend_from_slice(&(sell as f32).to_le_bytes());
   previous=i;
  }
  out
 }

 /// 打包的字节 → 各桶；坏了（截断、桶号倒退）回 None。
 pub fn unpack(bytes:&[u8])->Option<BTreeMap<i64,(f64,f64)>> {
  let mut levels=BTreeMap::new();
  if bytes.is_empty() {return Some(levels)}
  let mut r=Reader::new(bytes);
  let mut i=r.i64()?;
  let mut first=true;
  while !r.done() {
   let delta=r.uvarint()?;
   if !first&&delta==0 {return None}
   i=i.checked_add(i64::try_from(delta).ok()?)?;
   first=false;
   levels.insert(i,(f64::from(r.f32()?),f64::from(r.f32()?)));
  }
  Some(levels)
 }
}

static DROPPED:AtomicU64=AtomicU64::new(0);

impl Row for Minute {
 const TABLE:&'static str="orderflow_footprint";
 const COLUMNS:&'static str="step,levels";
 const BUDGET:Budget=storage_budget::FOOTPRINT;
 fn dropped()->&'static AtomicU64 {&DROPPED}
 fn minute_ms(&self)->i64 {self.minute_ms}
 fn merge(&mut self,later:Self) {
  let to=self.step.max(later.step);
  let mut levels=self.rebucket(to);
  for (i,(buy,sell)) in later.rebucket(to) {
   let level=levels.entry(i).or_default();
   level.0+=buy;level.1+=sell;
  }
  self.step=to;
  self.levels=levels;
 }
 fn push_binds(&self,b:&mut Separated<'_,'_,Postgres,&'static str>) {
  b.push_bind(self.step).push_bind(self.pack());
 }
 fn from_pg(row:&PgRow)->Option<Self> {
  let step:f64=row.try_get(1).ok()?;
  let bytes:Vec<u8>=row.try_get(2).ok()?;
  (step>0.0).then_some(())?;
  Some(Self{minute_ms:row.try_get(0).ok()?,step,levels:Self::unpack(&bytes)?})
 }
}

/// 一只 base 正在收的几分钟（交易所时刻可能落在上一分钟，所以不止一分钟开着）。
#[derive(Debug,Default)]
pub(super) struct Acc {
 /// 这只几家（不含交割）里最小的跳价（每个币的价）。
 tick:f64,
 step:Option<f64>,
 open:BTreeMap<i64,Minute>,
 /// 这一刻以前的分钟已经交出去了：再来的晚到成交算进还开着的最早那一分钟，不再单开一份去和库里合并。
 flushed:i64,
}

impl Acc {
 /// 记下一家的跳价（每个币的价），取最小的。
 pub fn tick(&mut self,tick:f64) {
  if tick.is_finite()&&tick>0.0&&(self.tick==0.0||tick<self.tick) {self.tick=tick;}
 }

 /// 一笔成交：每个币的价、美元额、是不是主动买、算在哪一刻（`minutes::trade_time`）。
 pub fn add(&mut self,price:f64,usd:f64,buy:bool,at:i64) {
  if !(price.is_finite()&&price>0.0&&usd.is_finite()&&usd>0.0) {return}
  let minute=at.div_euclid(MINUTE_MS)*MINUTE_MS;
  let minute=minute.max(self.flushed);
  let (tick,current)=(self.tick,self.step);
  let m=self.open.entry(minute).or_insert_with(||Minute::new(minute,step(price,tick,current)));
  self.step=Some(m.step);
  m.add(price,usd,buy);
 }

 /// 收完的分钟（过完再等 `GRACE_MS`）交出去。
 pub fn roll(&mut self,now:i64)->Vec<Minute> {
  let mut out=Vec::new();
  while let Some(entry)=self.open.first_entry() && minutes::closed(*entry.key(),now) {
   let m=entry.remove();
   self.flushed=self.flushed.max(m.minute_ms+MINUTE_MS);
   out.push(m);
  }
  out
 }

 /// 停的时候：没收完的也交出去（下一个进程接着收的另半分钟写库时合并）。
 pub fn take(&mut self)->Vec<Minute> {
  let out:Vec<Minute>=std::mem::take(&mut self.open).into_values().collect();
  if let Some(last)=out.last() {self.flushed=self.flushed.max(last.minute_ms+MINUTE_MS);}
  out
 }
}

// ------------------------------------------------------------------ 写库与清理

static TX:OnceLock<mpsc::Sender<(String,Minute)>>=OnceLock::new();

/// 起写库任务（serve 进程起订单流时一次）。
pub(super) fn start(pool:PgPool) {TX.get_or_init(||minutes::channel(pool,QUEUE));}

pub(super) fn submit(base:&str,rows:Vec<Minute>) {
 if !rows.is_empty() {minutes::submit(TX.get(),base,rows);}
}

pub(super) async fn purge(pool:&PgPool,now:i64)->sqlx::Result<u64> {minutes::purge::<Minute>(pool,now).await}

// ------------------------------------------------------------------ 接口

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct FootprintQuery {symbol:String,from:Option<i64>,to:Option<i64>}

fn body(symbol:&str,scale:f64,rows:&[Minute])->String {
 let step=rows.iter().map(|m|m.step).fold(0.0,f64::max);
 let unit=step*scale;
 let places=minutes::decimals(unit);
 let mut out=String::with_capacity(64+rows.iter().map(|m|24+m.levels.len()*32).sum::<usize>());
 out.push_str("{\"symbol\":");out.push_str(&serde_json::Value::from(symbol).to_string());
 out.push_str(",\"step\":");
 if rows.is_empty() {out.push_str("null")} else {minutes::push_fixed(&mut out,1,unit,places)}
 out.push_str(",\"minutes\":[");
 for (n,m) in rows.iter().enumerate() {
  if n>0 {out.push(',');}
  out.push_str("{\"t\":");json_number(&mut out,m.minute_ms as f64);
  out.push_str(",\"rows\":[");
  let mut first=true;
  for (i,(buy,sell)) in m.rebucket(step) {
   let (buy,sell)=(buy.round(),sell.round());
   if buy<=0.0&&sell<=0.0 {continue}
   if !first {out.push(',');}
   first=false;
   out.push('[');minutes::push_fixed(&mut out,i,unit,places);
   out.push(',');json_number(&mut out,buy.max(0.0));
   out.push(',');json_number(&mut out,sell.max(0.0));
   out.push(']');
  }
  out.push_str("]}");
 }
 out.push_str("]}");
 out
}

async fn read(pool:&PgPool,base:&str,from:i64,to:i64)->sqlx::Result<Vec<Minute>> {
 let rows=sqlx::query("SELECT minute_ms,step,levels FROM orderflow_footprint WHERE base=$1 AND minute_ms BETWEEN $2 AND $3 ORDER BY minute_ms")
  .bind(base).bind(from).bind(to).fetch_all(pool).await?;
 Ok(rows.iter().filter_map(Minute::from_pg).collect())
}

#[derive(Clone,Debug,PartialEq,Eq,Hash)]
struct Key {symbol:String,from:i64,to:i64,gzip:bool}

static ANSWERS:std::sync::LazyLock<Answers<Key>>=std::sync::LazyLock::new(||Answers::new(TTL));

fn answer(json:String,gzip:bool)->Result<Answer> {packed(json,gzip,CACHE_CONTROL)}

pub(super) async fn footprint(State(s):State<AppState>,headers:axum::http::HeaderMap,Params(q):Params<FootprintQuery>)->Result<Response> {
 let Some((base,scale))=minutes::parse_symbol(&q.symbol) else {return Err(ApiError::bad("invalid_symbol"))};
 let (from,to)=minutes::window(q.from,q.to,now_ms(),DEFAULT_SPAN_MS,MAX_SPAN_MS).map_err(ApiError::bad)?;
 let floor=|v:i64|v.div_euclid(MINUTE_MS)*MINUTE_MS;
 let (from,to)=(floor(from),floor(to));
 let gzip=accepts_gzip(&headers);
 if !REGISTRY.get().is_some_and(|r|r.is_tracked(&base)) {return Ok(answer(body(&q.symbol,scale,&[]),gzip)?.response())}
 let pool=POOL.get().unwrap_or(&s.pool);
 let key=Key{symbol:q.symbol.clone(),from,to,gzip};
 let answer=ANSWERS.get_or_build(key,||async {
  let busy=||ApiError(axum::http::StatusCode::SERVICE_UNAVAILABLE,"temporarily_unavailable");
  let _slot=HISTORY_READS.acquire().await.map_err(|_|busy())?;
  let rows=read(pool,&base,from,to).await?;
  drop(_slot);
  answer(body(&q.symbol,scale,&rows),gzip)
 }).await?;
 Ok(answer.response())
}

#[cfg(test)]
mod tests {
 use super::*;

 #[test] fn steps_round_to_one_two_five_and_respect_the_tick() {
  assert_eq!(nice(12.0),10.0);
  assert_eq!(nice(0.5),0.5);
  assert_eq!(nice(0.0034),0.002);
  assert_eq!(nice(0.0036),0.005);
  assert_eq!(nice(7.6),10.0);
  assert_eq!(nice(2.2e-9),2e-9);
  assert_eq!(step(60_000.0,0.01,None),10.0,"BTC 6 万：12 → 10");
  assert_eq!(step(2_500.0,0.01,None),0.5,"ETH 2500：0.5");
  assert_eq!(step(0.000_011,1e-10,None),2e-9,"PEPE 按每个币的价");
  assert_eq!(step(100.0,0.1,None),0.1,"不小于跳价：0.02 → 0.1");
  assert_eq!(step(75_000.0,0.01,Some(10.0)),10.0,"15 还在 1.8 倍以内，不换");
  assert_eq!(step(95_000.0,0.01,Some(10.0)),20.0,"19 出了 1.8 倍，换成 20");
  assert_eq!(step(29_000.0,0.01,Some(10.0)),5.0,"5.8 出了 0.6 倍，换成 5");
  assert_eq!(bucket(60_010.0,10.0),6_001,"压在边上的算上面那个桶");
  assert_eq!(bucket(60_009.99,10.0),6_000);
  assert_eq!(bucket(0.3,0.1),3);
 }

 #[test] fn trades_aggregate_per_minute_and_bucket_by_side() {
  let mut a=Acc::default();
  a.tick(0.1);a.tick(0.01);a.tick(0.0);
  a.add(60_001.0,1_000.0,true,60_000);
  a.add(60_009.9,500.0,false,60_500);
  a.add(60_010.0,200.0,true,61_000);
  a.add(60_010.0,0.0,true,61_000);
  a.add(f64::NAN,1.0,true,61_000);
  a.add(60_020.0,300.0,false,119_999);
  a.add(60_030.0,50.0,true,120_000);
  assert!(a.roll(122_999).is_empty(),"过完一分钟再等 3 秒");
  let done=a.roll(123_000);
  assert_eq!(done.len(),1);
  assert_eq!(done[0],Minute{minute_ms:60_000,step:10.0,levels:BTreeMap::from([(6_000,(1_000.0,500.0)),(6_001,(200.0,0.0)),(6_002,(0.0,300.0))])});
  a.add(60_040.0,70.0,false,110_000);
  let rest=a.take();
  assert_eq!(rest.len(),1,"已经交出去的分钟不再单开：晚到的算进还开着的那一分钟");
  assert_eq!(rest[0].levels,BTreeMap::from([(6_003,(50.0,0.0)),(6_004,(0.0,70.0))]));
  assert!(a.take().is_empty());
 }

 #[test] fn levels_pack_and_unpack() {
  let m=Minute{minute_ms:0,step:10.0,levels:BTreeMap::from([(-3,(1.5,0.0)),(6_000,(1_000.0,500.0)),(6_001,(200.0,0.0)),(9_000_000,(0.0,123_456.0))])};
  let bytes=m.pack();
  assert_eq!(bytes.len(),8+(1+8)+(2+8)+(1+8)+(4+8));
  assert_eq!(Minute::unpack(&bytes),Some(m.levels.clone()));
  assert_eq!(Minute::unpack(&[]),Some(BTreeMap::new()));
  assert_eq!(Minute::unpack(&bytes[..bytes.len()-1]),None,"截断的读不回来");
  let mut repeated=6_000i64.to_le_bytes().to_vec();
  for _ in 0..2 {repeated.push(0);repeated.extend_from_slice(&[0;8]);}
  assert_eq!(Minute::unpack(&repeated),None,"同一个桶出现两次是坏的");
 }

 #[test] fn merging_adds_levels_and_moves_finer_steps_onto_the_coarser() {
  let mut a=Minute{minute_ms:0,step:5.0,levels:BTreeMap::from([(12_000,(10.0,0.0)),(12_001,(5.0,1.0))])};
  let b=Minute{minute_ms:0,step:10.0,levels:BTreeMap::from([(6_000,(1.0,2.0)),(6_001,(0.0,4.0))])};
  a.merge(b);
  assert_eq!(a.step,10.0);
  assert_eq!(a.levels,BTreeMap::from([(6_000,(16.0,3.0)),(6_001,(0.0,4.0))]));
  let rows=minutes::merge(vec![("BTC".to_string(),Minute{minute_ms:0,step:1.0,levels:BTreeMap::from([(1,(1.0,0.0))])}),
   ("BTC".to_string(),Minute{minute_ms:0,step:1.0,levels:BTreeMap::from([(1,(2.0,0.0))])})]);
  assert_eq!(rows.len(),1);
  assert_eq!(rows[0].1.levels[&1],(3.0,0.0));
 }

 #[test] fn body_has_the_agreed_shape() {
  let rows=[
   Minute{minute_ms:60_000,step:0.5,levels:BTreeMap::from([(5_000,(1_000.2,0.1)),(5_001,(0.1,0.2)),(5_003,(0.0,99.6))])},
   Minute{minute_ms:120_000,step:1.0,levels:BTreeMap::from([(2_501,(10.0,0.0))])},
  ];
  assert_eq!(body("ETHUSDT",1.0,&rows),r#"{"symbol":"ETHUSDT","step":1,"minutes":[{"t":60000,"rows":[[2500,1000,0],[2501,0,100]]},{"t":120000,"rows":[[2501,10,0]]}]}"#);
  let pepe=[Minute{minute_ms:0,step:2e-9,levels:BTreeMap::from([(5_500,(7.0,8.0))])}];
  assert_eq!(body("1000PEPEUSDT",1000.0,&pepe),r#"{"symbol":"1000PEPEUSDT","step":0.000002,"minutes":[{"t":0,"rows":[[0.011,7,8]]}]}"#);
  assert_eq!(body("BTCUSDT",1.0,&[]),r#"{"symbol":"BTCUSDT","step":null,"minutes":[]}"#);
 }

 #[tokio::test] async fn writes_merge_into_existing_minutes_and_purge_keeps_three_days() {
  let Some(pool)=super::super::store::tests::isolated_pool().await else {return};
  sqlx::query("DELETE FROM orderflow_footprint WHERE base LIKE 'ZZF%'").execute(&pool).await.unwrap();
  sqlx::query("INSERT INTO orderflow_bases(base,since_ms,requested_ms) VALUES ('ZZF',0,0) ON CONFLICT DO NOTHING").execute(&pool).await.unwrap();
  let now=100*super::super::store::DAY_MS;
  let m=|minute_ms,buy|Minute{minute_ms,step:1.0,levels:BTreeMap::from([(7,(buy,1.0))])};
  assert_eq!(minutes::write(&pool,vec![("ZZF".into(),m(now-60_000,1.0)),("ZZF".into(),m(now-4*super::super::store::DAY_MS,1.0))]).await.unwrap(),0);
  assert_eq!(minutes::write(&pool,vec![("ZZF".into(),m(now-60_000,2.0))]).await.unwrap(),1,"同一分钟再来：读出来合并");
  let rows=read(&pool,"ZZF",now-120_000,now).await.unwrap();
  assert_eq!(rows,vec![Minute{minute_ms:now-60_000,step:1.0,levels:BTreeMap::from([(7,(3.0,2.0))])}]);
  assert!(purge(&pool,now).await.unwrap()>=1);
  let left:i64=sqlx::query_scalar("SELECT count(*) FROM orderflow_footprint WHERE base='ZZF'").fetch_one(&pool).await.unwrap();
  assert_eq!(left,1,"3 天以前的删掉");
 }
}
