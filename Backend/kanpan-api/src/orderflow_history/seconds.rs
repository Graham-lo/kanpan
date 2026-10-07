//! 秒线历史（2026-10-07，网页版秒级 K 线补历史）：币安 U 本位永续每一秒的开高低收、成交量与主动买量。
//!
//! * 记：跟踪任务收到的币安 U 本位永续逐笔（aggTrade，和 `flow.rs` 同一批常驻在跟的 base、同一个按成交号去重之后的入口；
//!   别家、别的产品不算）按交易所给的成交时刻（`T`，离此刻 10 秒以上不信，见 `minutes::trade_time`）分到那一秒。
//!   价、量都是币安挂牌的原样（`1000PEPEUSDT` 就是 1000 个币的价、张数），价按这只的跳价存成整数格。
//!   一秒里没有成交就没有这根。
//! * 一只 base 一分钟一行（`klines_seconds`，迁移 0051）：`symbol`、`tick` 照币安合约表，`bars` 打包成字节——
//!   哪几秒有（u64 位图），第一根的开盘格数（i64 小端），然后每根：开盘与上一根收盘差几格（zigzag 变长）、
//!   高 − 开、开 − 低、收 − 低（无符号变长）、成交量（f32）、主动买量（f32）。成交活跃的一分钟约 60 根、七八百字节。
//!   写库、合并（同一秒两份：开取先到的、收取后来的、高低取极值、量相加）、清理见 `minutes.rs`。
//! * 接口 `GET /v1/market/klines/seconds?symbol=BTCUSDT&from=&to=` → `{"symbol","bars":[[ts,o,h,l,c,量,主动买量],…]}`：
//!   `ts` 是那一秒起点的毫秒，按时间升序，闭区间 `[from,to]`。`symbol` 是币安 U 本位永续的写法；
//!   问 `PEPEUSDT` 的按每个币的价与币数报，问 `1000PEPEUSDT` 的按 1000 个币报，和币安那只合约一致。
//!   `to` 缺省此刻、`from` 缺省 `to` 前 30 分钟，超过 6 小时回 400。最近一分钟要等它过完再 3 秒才写进库。
//!   没在跟的 base 回 200 与空 `bars`，不读库、也不因此起跟。鉴权、合并读库、gzip 与 `/flow` 同一套。
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

pub(super) const PATH:&str="/v1/market/klines/seconds";
/// 只记这一家这一种产品（簿 id 的前缀）。
pub(super) const VENUE_PREFIX:&str="binance:usdtPerp:";
const TTL:Duration=Duration::from_secs(20);
const CACHE_CONTROL:&str="public, max-age=20";
const DEFAULT_SPAN_MS:i64=30*MINUTE_MS;
const MAX_SPAN_MS:i64=6*60*MINUTE_MS;
const QUEUE:usize=4096;

/// 一根秒线：价是跳价的整数倍（格数）。
#[derive(Clone,Copy,Debug,PartialEq)]
pub(super) struct Bar {pub o:i64,pub h:i64,pub l:i64,pub c:i64,pub vol:f64,pub buy:f64}

impl Bar {
 fn first(price:i64,quantity:f64,buy:bool)->Self {Self{o:price,h:price,l:price,c:price,vol:quantity,buy:if buy {quantity} else {0.0}}}
 fn add(&mut self,price:i64,quantity:f64,buy:bool) {
  self.h=self.h.max(price);self.l=self.l.min(price);self.c=price;
  self.vol+=quantity;
  if buy {self.buy+=quantity;}
 }
 /// 同一秒后来的一份：开不动、收取后来的、高低取极值、量相加。
 fn merge(&mut self,later:Bar) {
  self.h=self.h.max(later.h);self.l=self.l.min(later.l);self.c=later.c;
  self.vol+=later.vol;self.buy+=later.buy;
 }
 fn rescale(self,from:f64,to:f64)->Self {
  if from==to||!(from>0.0&&to>0.0) {return self}
  let f=|v:i64|(v as f64*from/to).round() as i64;
  Self{o:f(self.o),h:f(self.h),l:f(self.l),c:f(self.c),..self}
 }
}

/// 一分钟：合约名、跳价与各秒（0–59 → 那一根）。
#[derive(Clone,Debug,PartialEq)]
pub(super) struct Minute {pub minute_ms:i64,pub symbol:String,pub tick:f64,pub bars:BTreeMap<u8,Bar>}

impl Minute {
 pub fn pack(&self)->Vec<u8> {
  let mut out=Vec::with_capacity(16+self.bars.len()*14);
  let mask=self.bars.keys().filter(|s|**s<60).fold(0u64,|m,s|m|1<<s);
  out.extend_from_slice(&mask.to_le_bytes());
  let Some(first)=self.bars.values().next() else {return out};
  out.extend_from_slice(&first.o.to_le_bytes());
  let mut previous=first.o;
  for (_,b) in self.bars.iter().filter(|(s,_)|**s<60) {
   let (h,l)=(b.h.max(b.o).max(b.c),b.l.min(b.o).min(b.c));
   minutes::put_varint(&mut out,b.o-previous);
   minutes::put_uvarint(&mut out,(h-b.o) as u64);
   minutes::put_uvarint(&mut out,(b.o-l) as u64);
   minutes::put_uvarint(&mut out,(b.c-l) as u64);
   out.extend_from_slice(&(b.vol as f32).to_le_bytes());
   out.extend_from_slice(&(b.buy as f32).to_le_bytes());
   previous=b.c;
  }
  out
 }

 /// 打包的字节 → 各秒；坏了（截断、多出来、位图与根数对不上）回 None。
 pub fn unpack(bytes:&[u8])->Option<BTreeMap<u8,Bar>> {
  let mut r=Reader::new(bytes);
  let mask=r.u64()?;
  let mut bars=BTreeMap::new();
  if mask==0 {return r.done().then_some(bars)}
  if mask>>60!=0 {return None}
  let mut previous=r.i64()?;
  for s in (0..60u8).filter(|s|mask&(1<<s)!=0) {
   let o=previous.checked_add(r.varint()?)?;
   let h=o.checked_add(i64::try_from(r.uvarint()?).ok()?)?;
   let l=o.checked_sub(i64::try_from(r.uvarint()?).ok()?)?;
   let c=l.checked_add(i64::try_from(r.uvarint()?).ok()?)?;
   let (vol,buy)=(f64::from(r.f32()?),f64::from(r.f32()?));
   bars.insert(s,Bar{o,h,l,c,vol,buy});
   previous=c;
  }
  r.done().then_some(bars)
 }
}

static DROPPED:AtomicU64=AtomicU64::new(0);

impl Row for Minute {
 const TABLE:&'static str="klines_seconds";
 const COLUMNS:&'static str="symbol,tick,bars";
 const BUDGET:Budget=storage_budget::SECONDS;
 fn dropped()->&'static AtomicU64 {&DROPPED}
 fn minute_ms(&self)->i64 {self.minute_ms}
 fn merge(&mut self,later:Self) {
  // 合约换了（改名、换前缀）：后来的那份为准，旧的价单位对不上。
  if later.symbol!=self.symbol {*self=later;return}
  for (s,bar) in later.bars {
   let bar=bar.rescale(later.tick,self.tick);
   match self.bars.get_mut(&s) {Some(b)=>b.merge(bar),None=>{self.bars.insert(s,bar);}}
  }
 }
 fn push_binds(&self,b:&mut Separated<'_,'_,Postgres,&'static str>) {
  b.push_bind(self.symbol.clone()).push_bind(self.tick).push_bind(self.pack());
 }
 fn from_pg(row:&PgRow)->Option<Self> {
  let tick:f64=row.try_get(2).ok()?;
  let bytes:Vec<u8>=row.try_get(3).ok()?;
  (tick>0.0).then_some(())?;
  Some(Self{minute_ms:row.try_get(0).ok()?,symbol:row.try_get(1).ok()?,tick,bars:Self::unpack(&bytes)?})
 }
}

/// 这只的币安 U 本位永续：簿 id、合约名、跳价（挂牌价）、几个币一张价（`1000PEPE` 为 1000）。
#[derive(Clone,Debug,PartialEq)]
pub(super) struct Venue {pub id:String,pub symbol:String,pub tick:f64,pub scale:f64}

/// 一只 base 正在收的几分钟。
#[derive(Debug,Default)]
pub(super) struct Acc {
 venue:Option<Venue>,
 open:BTreeMap<i64,Minute>,
 /// 这一刻以前的分钟已经交出去了：晚到的算进还开着的最早那一分钟的第 0 秒。
 flushed:i64,
}

impl Acc {
 pub fn venue(&mut self,venue:Venue) {
  if venue.tick>0.0&&venue.scale>0.0 {self.venue=Some(venue);}
 }

 /// 一笔成交（簿 id、每个币的价、配套的量——和 `VenueInfo::level` 换算过的一样、是不是主动买、算在哪一刻）。不是币安 U 本位永续的不算。
 pub fn add(&mut self,venue:&str,price:f64,quantity:f64,buy:bool,at:i64) {
  let Some(v)=self.venue.as_ref().filter(|v|v.id==venue) else {return};
  // 换回挂牌的原样：价 × 几个币一张、量 ÷ 它。
  let (price,quantity)=(price*v.scale,quantity/v.scale);
  if !(price.is_finite()&&price>0.0&&quantity.is_finite()&&quantity>0.0) {return}
  let ticks=(price/v.tick).round() as i64;
  let minute=at.div_euclid(MINUTE_MS)*MINUTE_MS;
  let (minute,second)=if minute<self.flushed {(self.flushed,0)} else {(minute,(at-minute)/1000)};
  let (symbol,tick)=(v.symbol.clone(),v.tick);
  let m=self.open.entry(minute).or_insert_with(||Minute{minute_ms:minute,symbol,tick,bars:BTreeMap::new()});
  let ticks=if m.tick==tick {ticks} else {(price/m.tick).round() as i64};
  match m.bars.get_mut(&(second as u8)) {Some(b)=>b.add(ticks,quantity,buy),None=>{m.bars.insert(second as u8,Bar::first(ticks,quantity,buy));}}
 }

 pub fn roll(&mut self,now:i64)->Vec<Minute> {
  let mut out=Vec::new();
  while let Some(entry)=self.open.first_entry() && minutes::closed(*entry.key(),now) {
   let m=entry.remove();
   self.flushed=self.flushed.max(m.minute_ms+MINUTE_MS);
   out.push(m);
  }
  out
 }

 pub fn take(&mut self)->Vec<Minute> {
  let out:Vec<Minute>=std::mem::take(&mut self.open).into_values().collect();
  if let Some(last)=out.last() {self.flushed=self.flushed.max(last.minute_ms+MINUTE_MS);}
  out
 }
}

// ------------------------------------------------------------------ 写库与清理

static TX:OnceLock<mpsc::Sender<(String,Minute)>>=OnceLock::new();

pub(super) fn start(pool:PgPool) {TX.get_or_init(||minutes::channel(pool,QUEUE));}

pub(super) fn submit(base:&str,rows:Vec<Minute>) {
 if !rows.is_empty() {minutes::submit(TX.get(),base,rows);}
}

pub(super) async fn purge(pool:&PgPool,now:i64)->sqlx::Result<u64> {minutes::purge::<Minute>(pool,now).await}

// ------------------------------------------------------------------ 接口

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct SecondsQuery {symbol:String,from:Option<i64>,to:Option<i64>}

/// f32 存的量按最短的十进制写（`12.345`，不是 `12.345000267028809`）。
fn push_volume(out:&mut String,v:f64) {
 let v=v as f32;
 if v.is_finite()&&v>0.0 {out.push_str(&v.to_string())} else {out.push('0')}
}

/// `scale`：问的那个写法几个币一张价（`PEPEUSDT` 为 1、`1000PEPEUSDT` 为 1000）。
fn body(symbol:&str,scale:f64,rows:&[Minute],from:i64,to:i64)->String {
 let mut out=String::with_capacity(48+rows.iter().map(|m|m.bars.len()*64).sum::<usize>());
 out.push_str("{\"symbol\":");out.push_str(&serde_json::Value::from(symbol).to_string());
 out.push_str(",\"bars\":[");
 let mut first=true;
 for m in rows {
  let stored=minutes::parse_symbol(&m.symbol).map_or(1.0,|(_,s)|s);
  // 存的是挂牌价的格数：× 跳价 ÷ 存的那个写法几个币一张 × 问的写法几个币一张。
  let unit=m.tick/stored*scale;
  let places=minutes::decimals(unit);
  let volume=stored/scale;
  for (&s,b) in &m.bars {
   let ts=m.minute_ms+i64::from(s)*1000;
   if ts<from||ts>to {continue}
   if !first {out.push(',');}
   first=false;
   out.push('[');json_number(&mut out,ts as f64);
   for p in [b.o,b.h,b.l,b.c] {out.push(',');minutes::push_fixed(&mut out,p,unit,places);}
   out.push(',');push_volume(&mut out,b.vol*volume);
   out.push(',');push_volume(&mut out,b.buy*volume);
   out.push(']');
  }
 }
 out.push_str("]}");
 out
}

async fn read(pool:&PgPool,base:&str,from:i64,to:i64)->sqlx::Result<Vec<Minute>> {
 let rows=sqlx::query("SELECT minute_ms,symbol,tick,bars FROM klines_seconds WHERE base=$1 AND minute_ms BETWEEN $2 AND $3 ORDER BY minute_ms")
  .bind(base).bind(from.div_euclid(MINUTE_MS)*MINUTE_MS).bind(to).fetch_all(pool).await?;
 Ok(rows.iter().filter_map(Minute::from_pg).collect())
}

#[derive(Clone,Debug,PartialEq,Eq,Hash)]
struct Key {symbol:String,from:i64,to:i64,gzip:bool}

static ANSWERS:std::sync::LazyLock<Answers<Key>>=std::sync::LazyLock::new(||Answers::new(TTL));

fn answer(json:String,gzip:bool)->Result<Answer> {packed(json,gzip,CACHE_CONTROL)}

pub(super) async fn seconds(State(s):State<AppState>,headers:axum::http::HeaderMap,Params(q):Params<SecondsQuery>)->Result<Response> {
 let Some((base,scale))=minutes::parse_symbol(&q.symbol) else {return Err(ApiError::bad("invalid_symbol"))};
 let (from,to)=minutes::window(q.from,q.to,now_ms(),DEFAULT_SPAN_MS,MAX_SPAN_MS).map_err(ApiError::bad)?;
 let gzip=accepts_gzip(&headers);
 if !REGISTRY.get().is_some_and(|r|r.is_tracked(&base)) {return Ok(answer(body(&q.symbol,scale,&[],from,to),gzip)?.response())}
 let pool=POOL.get().unwrap_or(&s.pool);
 // 区间两端按秒取整，同一秒里的请求合成一次。
 let (from,to)=(from.div_euclid(1000)*1000,to.div_euclid(1000)*1000);
 let key=Key{symbol:q.symbol.clone(),from,to,gzip};
 let answer=ANSWERS.get_or_build(key,||async {
  let busy=||ApiError(axum::http::StatusCode::SERVICE_UNAVAILABLE,"temporarily_unavailable");
  let _slot=HISTORY_READS.acquire().await.map_err(|_|busy())?;
  let rows=read(pool,&base,from,to).await?;
  drop(_slot);
  answer(body(&q.symbol,scale,&rows,from,to),gzip)
 }).await?;
 Ok(answer.response())
}

#[cfg(test)]
mod tests {
 use super::*;

 fn btc()->Venue {Venue{id:"binance:usdtPerp:BTCUSDT".into(),symbol:"BTCUSDT".into(),tick:0.1,scale:1.0}}

 #[test] fn trades_make_one_bar_per_second_and_skip_quiet_seconds() {
  let mut a=Acc::default();
  a.venue(btc());
  a.add("binance:usdtPerp:BTCUSDT",60_000.0,1.0,true,60_000);
  a.add("binance:usdtPerp:BTCUSDT",60_010.5,0.5,false,60_400);
  a.add("binance:usdtPerp:BTCUSDT",59_990.0,0.25,false,60_999);
  a.add("binance:usdtPerp:BTCUSDT",60_005.0,2.0,true,60_999);
  a.add("okx:usdtPerp:BTC-USDT-SWAP",1.0,1.0,true,61_000);
  a.add("binance:spot:BTCUSDT",1.0,1.0,true,61_000);
  a.add("binance:usdtPerp:BTCUSDT",60_001.0,0.0,true,61_000);
  a.add("binance:usdtPerp:BTCUSDT",60_002.0,3.0,false,62_000);
  a.add("binance:usdtPerp:BTCUSDT",60_003.0,1.0,true,120_500);
  let done=a.roll(123_000);
  assert_eq!(done.len(),1);
  let m=&done[0];
  assert_eq!((m.minute_ms,m.symbol.as_str(),m.tick),(60_000,"BTCUSDT",0.1));
  assert_eq!(m.bars,BTreeMap::from([
   (0,Bar{o:600_000,h:600_105,l:599_900,c:600_050,vol:3.75,buy:3.0}),
   (2,Bar{o:600_020,h:600_020,l:600_020,c:600_020,vol:3.0,buy:0.0}),
  ]),"第 1 秒没有成交就没有这根");
  a.add("binance:usdtPerp:BTCUSDT",60_004.0,1.0,false,119_000);
  let rest=a.take();
  assert_eq!(rest[0].bars.keys().copied().collect::<Vec<_>>(),vec![0],"已经交出去的分钟不再单开，晚到的算进下一分钟的第 0 秒");
  assert_eq!(rest[0].bars[&0].c,600_040);
 }

 #[test] fn scaled_contracts_keep_the_listed_price_and_contract_count() {
  let mut a=Acc::default();
  a.venue(Venue{id:"binance:usdtPerp:1000PEPEUSDT".into(),symbol:"1000PEPEUSDT".into(),tick:0.0000001,scale:1000.0});
  // 跟踪任务给的是每个币的价、乘过 1000 的量。
  a.add("binance:usdtPerp:1000PEPEUSDT",0.000_012_3,5_000_000.0,true,0);
  let m=&a.take()[0];
  assert_eq!(m.bars[&0].o,123_000);
  assert_eq!(m.bars[&0].vol,5_000.0);
  let as_listed=body("1000PEPEUSDT",1000.0,std::slice::from_ref(m),0,60_000);
  assert_eq!(as_listed,r#"{"symbol":"1000PEPEUSDT","bars":[[0,0.0123,0.0123,0.0123,0.0123,5000,5000]]}"#);
  let per_coin=body("PEPEUSDT",1.0,std::slice::from_ref(m),0,60_000);
  assert_eq!(per_coin,r#"{"symbol":"PEPEUSDT","bars":[[0,0.0000123,0.0000123,0.0000123,0.0000123,5000000,5000000]]}"#);
 }

 #[test] fn bars_pack_and_unpack() {
  let m=Minute{minute_ms:0,symbol:"BTCUSDT".into(),tick:0.1,bars:BTreeMap::from([
   (0,Bar{o:600_000,h:600_105,l:599_900,c:600_050,vol:3.75,buy:3.0}),
   (2,Bar{o:600_020,h:600_020,l:600_020,c:600_020,vol:3.0,buy:0.0}),
   (59,Bar{o:500_000,h:700_000,l:400_000,c:650_000,vol:0.001,buy:0.001}),
  ])};
  let bytes=m.pack();
  assert_eq!(bytes.len(),8+8+(1+1+1+2+8)+(1+1+1+1+8)+(3+3+3+3+8));
  assert_eq!(Minute::unpack(&bytes),Some(m.bars.iter().map(|(s,b)|(*s,Bar{vol:f64::from(b.vol as f32),buy:f64::from(b.buy as f32),..*b})).collect()));
  assert_eq!(Minute::unpack(&bytes[..bytes.len()-1]),None,"截断");
  let mut extra=bytes.clone();extra.push(0);
  assert_eq!(Minute::unpack(&extra),None,"多出来");
  assert_eq!(Minute::unpack(&0u64.to_le_bytes()),Some(BTreeMap::new()));
  assert_eq!(Minute::unpack(&(1u64<<60).to_le_bytes()),None,"第 60 秒不存在");
  assert_eq!(Minute{minute_ms:0,symbol:"X".into(),tick:1.0,bars:BTreeMap::new()}.pack(),0u64.to_le_bytes().to_vec());
 }

 #[test] fn merging_keeps_the_first_open_and_the_last_close() {
  let bar=|o,h,l,c,vol|Bar{o,h,l,c,vol,buy:vol/2.0};
  let mut a=Minute{minute_ms:0,symbol:"BTCUSDT".into(),tick:0.1,bars:BTreeMap::from([(0,bar(10,12,9,11,1.0)),(1,bar(11,11,11,11,1.0))])};
  let b=Minute{minute_ms:0,symbol:"BTCUSDT".into(),tick:0.1,bars:BTreeMap::from([(1,bar(13,15,8,14,2.0)),(5,bar(14,14,14,14,1.0))])};
  a.merge(b);
  assert_eq!(a.bars,BTreeMap::from([(0,bar(10,12,9,11,1.0)),(1,Bar{o:11,h:15,l:8,c:14,vol:3.0,buy:1.5}),(5,bar(14,14,14,14,1.0))]));
  let finer=Minute{minute_ms:0,symbol:"BTCUSDT".into(),tick:0.01,bars:BTreeMap::from([(7,bar(1_000,1_010,990,1_006,1.0))])};
  a.merge(finer);
  assert_eq!(a.bars[&7],bar(100,101,99,101,1.0),"跳价不一样的换到先到那份的格上（100.6 → 101）");
  let renamed=Minute{minute_ms:0,symbol:"1000BTCUSDT".into(),tick:1.0,bars:BTreeMap::new()};
  a.merge(renamed.clone());
  assert_eq!(a,renamed,"合约换了，以后来的为准");
 }

 #[test] fn body_filters_to_the_window_and_prints_listed_prices() {
  let m=Minute{minute_ms:60_000,symbol:"BTCUSDT".into(),tick:0.1,bars:BTreeMap::from([
   (0,Bar{o:600_000,h:600_105,l:599_900,c:600_050,vol:3.75,buy:3.0}),
   (2,Bar{o:600_020,h:600_020,l:600_020,c:600_020,vol:0.1,buy:0.0}),
  ])};
  assert_eq!(body("BTCUSDT",1.0,std::slice::from_ref(&m),60_000,61_000),r#"{"symbol":"BTCUSDT","bars":[[60000,60000,60010.5,59990,60005,3.75,3]]}"#);
  assert_eq!(body("BTCUSDT",1.0,std::slice::from_ref(&m),61_000,62_000),r#"{"symbol":"BTCUSDT","bars":[[62000,60002,60002,60002,60002,0.1,0]]}"#);
  assert_eq!(body("ETHUSDT",1.0,&[],0,1),r#"{"symbol":"ETHUSDT","bars":[]}"#);
 }

 #[tokio::test] async fn writes_merge_into_existing_minutes_and_purge_keeps_three_days() {
  let Some(pool)=super::super::store::tests::isolated_pool().await else {return};
  sqlx::query("DELETE FROM klines_seconds WHERE base LIKE 'ZZK%'").execute(&pool).await.unwrap();
  sqlx::query("INSERT INTO orderflow_bases(base,since_ms,requested_ms) VALUES ('ZZK',0,0) ON CONFLICT DO NOTHING").execute(&pool).await.unwrap();
  let day=super::super::store::DAY_MS;
  let now=100*day;
  let m=|minute_ms,c|Minute{minute_ms,symbol:"ZZKUSDT".into(),tick:0.5,bars:BTreeMap::from([(3,Bar{o:10,h:12,l:9,c,vol:1.0,buy:1.0})])};
  assert_eq!(minutes::write(&pool,vec![("ZZK".into(),m(now-60_000,11)),("ZZK".into(),m(now-4*day,11))]).await.unwrap(),0);
  assert_eq!(minutes::write(&pool,vec![("ZZK".into(),m(now-60_000,10))]).await.unwrap(),1);
  let rows=read(&pool,"ZZK",now-120_000,now).await.unwrap();
  assert_eq!(rows.len(),1);
  assert_eq!(rows[0].bars[&3],Bar{o:10,h:12,l:9,c:10,vol:2.0,buy:2.0});
  assert!(purge(&pool,now).await.unwrap()>=1);
  let left:i64=sqlx::query_scalar("SELECT count(*) FROM klines_seconds WHERE base='ZZK'").fetch_one(&pool).await.unwrap();
  assert_eq!(left,1);
 }
}
