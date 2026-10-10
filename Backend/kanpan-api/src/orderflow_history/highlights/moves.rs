//! 波动异动（照 AICoin「急涨急跌」，2026-10-10）：全市场永续（四家合并到基础币，和首页榜单同一池子）每分钟扫一次价，
//! 1 分钟或 5 分钟的涨跌幅绝对值 ≥ max(下限, 这只自己近 30 天同一窗口涨跌幅绝对值的 P99.5) 就记一条。
//!
//! * 下限：1 分钟 1.0 %、5 分钟 2.5 %；这只的样本不到一天（1440 个）时阈值就是下限。
//! * 四家 24h 成交额相加不到 100 万美元的不记（死盘口一跳就是几个点）。成交额取首页榜单最近一次扫的（5 分钟一次）。
//! * 同一只、同一方向 10 分钟之内的并成一条：涨跌幅留绝对值大的那次（连同它的窗口），`atMs` 取最近那一分钟；
//!   `id` = `M:<base>:<up|down>:<第一分钟>`，并进来的不改 id。只留近 2 小时、最多 30 条。
//! * 价按家优先取一家（同榜单：币安 → Bybit → OKX → Hyperliquid）；两分钟给价的不是同一家就不比。
//!
//! 30 天分布只记下限以上的那一截：每只每个窗口每天一格「样本数 + 下限以上按 5 % 一档的计数」，P99.5 落在下限以下时
//! 阈值就是下限，所以下限以下的分布用不着。分布与这 2 小时的记录每 15 分钟进 `orderflow_highlights`（行名 `~moves`）。
//! 不推送、不出声、阈值不给用户调。
use super::market;
use super::{Answers,accepts_gzip,now_ms,packed};
use crate::AppState;
use crate::error::{ApiError,Params,Result};
use axum::extract::State as Axum;
use axum::response::Response;
use serde::Deserialize;
use serde_json::{Value,json};
use sqlx::{PgPool,Row};
use std::collections::{BTreeMap,HashMap,VecDeque};
use std::sync::{LazyLock,RwLock};
use std::time::Duration;

pub(in super::super) const PATH:&str="/v1/market/moves";
const TTL:Duration=Duration::from_secs(15);
const CACHE_CONTROL:&str="public, max-age=15";
const M:i64=60_000;
const DAY_MS:i64=1440*M;
/// 分布留多少天。
const KEEP_DAYS:i64=30;
/// 不到这么多个样本（一天的分钟数）就只用下限。
pub(super) const MIN_SAMPLES:u32=1440;
const Q:f64=0.995;
/// 两个窗口：名字、隔几分钟、下限（%）。
pub(super) const WINDOWS:[(&str,i64,f64);2]=[("1m",1,1.0),("5m",5,2.5)];
pub(super) const MIN_VOL_USD:f64=1_000_000.0;
pub(super) const MERGE_MS:i64=10*M;
pub(super) const KEEP_MS:i64=120*M;
pub(super) const MAX_ROWS:usize=30;
/// 下限以上每档宽 5 %。
const BIN:f64=1.05;
const MAX_BIN:u8=255;
/// 每分钟第几秒扫（各家的 1 分钟价已经换过）。
const SCAN_AT_MS:i64=5_000;
const PERSIST_EVERY_MS:i64=15*M;
const KEY:&str="~moves";

// ------------------------------------------------------------------ 30 天分布

/// 一天：样本数，与下限以上各档的计数。
#[derive(Clone,Debug,Default,PartialEq)]
pub(super) struct Day {pub day:i64,pub n:u32,pub tail:BTreeMap<u8,u32>}

/// 一只一个窗口近 30 天的涨跌幅绝对值分布（只记下限以上那一截）。
#[derive(Clone,Debug,Default,PartialEq)]
pub(super) struct Hist {pub days:VecDeque<Day>}

fn bin(abs:f64,floor:f64)->Option<u8> {
 (abs>=floor).then(||((abs/floor).ln()/BIN.ln()+1e-9).floor().clamp(0.0,f64::from(MAX_BIN)) as u8)
}

impl Hist {
 pub fn add(&mut self,abs:f64,floor:f64,at:i64) {
  let day=at.div_euclid(DAY_MS);
  if self.days.back().is_none_or(|d|d.day<day) {self.days.push_back(Day{day,..Day::default()});}
  while self.days.front().is_some_and(|d|d.day<=day-KEEP_DAYS) {self.days.pop_front();}
  let Some(d)=self.days.back_mut() else {return};
  d.n+=1;
  if let Some(b)=bin(abs,floor) {*d.tail.entry(b).or_default()+=1;}
 }

 /// 阈值（%）：max(下限, 近 30 天 P99.5)；样本不到 [`MIN_SAMPLES`] 就是下限。P99.5 取它所在那一档的下沿。
 pub fn threshold(&self,floor:f64,now:i64)->f64 {
  let day=now.div_euclid(DAY_MS);
  let live:Vec<&Day>=self.days.iter().filter(|d|d.day>day-KEEP_DAYS).collect();
  let n:u32=live.iter().map(|d|d.n).sum();
  if n<MIN_SAMPLES {return floor}
  // 比 P99.5 大的样本最多这么多个。
  let k=((1.0-Q)*f64::from(n)).ceil().max(1.0) as u32;
  let mut tail:BTreeMap<u8,u32>=BTreeMap::new();
  for d in &live {for (b,c) in &d.tail {*tail.entry(*b).or_default()+=c;}}
  let mut acc=0;
  for (b,c) in tail.iter().rev() {
   acc+=c;
   if acc>=k {return floor*BIN.powi(i32::from(*b))}
  }
  floor
 }

 fn newest_day(&self)->Option<i64> {self.days.back().map(|d|d.day)}
}

// ------------------------------------------------------------------ 每分钟

/// 一分钟一份价：基础币 → (给价的那一家, 价)。
pub(super) type Prices=HashMap<String,(usize,f64)>;

/// 一条异动（并过的）。`pct` 带符号（跌为负），`ratio` = |pct| ÷ 那个窗口当时的阈值。
#[derive(Clone,Debug,PartialEq)]
pub(super) struct Move {pub base:String,pub up:bool,pub window:usize,pub pct:f64,pub price:f64,pub vol:f64,pub first:i64,pub at:i64,pub ratio:f64}

impl Move {
 pub fn id(&self)->String {format!("M:{}:{}:{}",self.base,if self.up {"up"} else {"down"},self.first)}
 pub fn weight(&self,now:i64)->f64 {self.ratio*super::state::recency(now,self.at)}
 pub fn json(&self,tier:u8)->Value {
  json!({"id":self.id(),"base":self.base,"cat":"move","kind":if self.up {"moveUp"} else {"moveDown"},"window":WINDOWS[self.window].0,
   "pct":super::events::round(self.pct,2),"price":super::state::sig(self.price),"volUsd":super::events::usd(self.vol),"atMs":self.at,"tier":tier})
 }
}

/// 拿这一分钟（`ring` 最后一份）对 1 分钟前与 5 分钟前：先按旧分布算阈值、再把这个样本记进分布；
/// 过阈值且成交额够的出一条，同一只同一方向两个窗口都过时留涨跌幅大的那个。
pub(super) fn detect(ring:&VecDeque<(i64,Prices)>,hists:&mut HashMap<String,[Hist;2]>,vol:impl Fn(&str)->f64)->Vec<Move> {
 let Some((minute,now)) = ring.back() else {return Vec::new()};
 let mut best:BTreeMap<(&str,bool),Move>=BTreeMap::new();
 for (w,(_,lag,floor)) in WINDOWS.iter().enumerate() {
  let Some((_,then))=ring.iter().find(|(m,_)|*m==minute-lag*M) else {continue};
  for (base,(src,px)) in now {
   let Some((old_src,old))=then.get(base) else {continue};
   if old_src!=src || !(*old>0.0) || !(*px>0.0) {continue}
   let pct=(px/old-1.0)*100.0;
   if !pct.is_finite() {continue}
   let h=&mut hists.entry(base.clone()).or_default()[w];
   let thr=h.threshold(*floor,*minute);
   h.add(pct.abs(),*floor,*minute);
   if pct.abs()<thr {continue}
   let v=vol(base);
   if v<MIN_VOL_USD {continue}
   let m=Move{base:base.clone(),up:pct>0.0,window:w,pct,price:*px,vol:v,first:*minute,at:*minute,ratio:pct.abs()/thr};
   let key=(base.as_str(),m.up);
   if best.get(&key).is_none_or(|b|m.pct.abs()>b.pct.abs()) {best.insert(key,m);}
  }
 }
 best.into_values().collect()
}

/// 并进记录：同一只同一方向、离上一次不到 10 分钟的并成一条（留绝对值大的涨跌幅与它的窗口、最新的时刻 / 价 / 成交额，id 不变）。
pub(super) fn absorb(rows:&mut Vec<Move>,new:Move) {
 if let Some(r)=rows.iter_mut().find(|r|r.base==new.base&&r.up==new.up&&new.at>=r.at&&new.at-r.at<=MERGE_MS) {
  if new.pct.abs()>r.pct.abs() {r.pct=new.pct;r.window=new.window;r.ratio=new.ratio;}
  r.at=new.at;r.price=new.price;r.vol=new.vol;
 } else {rows.push(new);}
}

/// 只留近 2 小时、最多 30 条，新的在前。
pub(super) fn prune(rows:&mut Vec<Move>,now:i64) {
 rows.retain(|r|now-r.at<=KEEP_MS);
 rows.sort_by(|a,b|b.at.cmp(&a.at).then_with(||a.base.cmp(&b.base)).then_with(||a.up.cmp(&b.up)));
 rows.truncate(MAX_ROWS);
}

static MOVES:LazyLock<RwLock<Vec<Move>>>=LazyLock::new(||RwLock::new(Vec::new()));
static ANSWERS:LazyLock<Answers<(usize,bool)>>=LazyLock::new(||Answers::new(TTL));

/// 此刻的记录（新的在前）。
pub(super) fn current()->Vec<Move> {MOVES.read().unwrap_or_else(|e|e.into_inner()).clone()}

// ------------------------------------------------------------------ 落盘

pub(super) fn payload(hists:&HashMap<String,[Hist;2]>,rows:&[Move])->Value {
 let mut bases:Vec<&String>=hists.keys().collect();
 bases.sort();
 let h:serde_json::Map<String,Value>=bases.into_iter().map(|b|{
  let w=|h:&Hist|h.days.iter().map(|d|json!([d.day,d.n,d.tail.iter().map(|(b,c)|json!([b,c])).collect::<Vec<_>>()])).collect::<Vec<_>>();
  (b.clone(),json!([w(&hists[b][0]),w(&hists[b][1])]))
 }).collect();
 let rows:Vec<Value>=rows.iter().map(|r|json!([r.base,r.up,r.window,r.pct,r.price,r.vol,r.first,r.at,r.ratio])).collect();
 json!({"v":1,"h":h,"rows":rows})
}

pub(super) fn restore(v:&Value)->(HashMap<String,[Hist;2]>,Vec<Move>) {
 if v["v"]!=json!(1) {return Default::default()}
 let hist=|x:&Value|Hist{days:x.as_array().map(Vec::as_slice).unwrap_or_default().iter().filter_map(|d|Some(Day{
  day:d[0].as_i64()?,n:u32::try_from(d[1].as_u64()?).ok()?,
  tail:d[2].as_array()?.iter().filter_map(|t|Some((u8::try_from(t[0].as_u64()?).ok()?,u32::try_from(t[1].as_u64()?).ok()?))).collect()})).collect()};
 let hists=v["h"].as_object().map(|o|o.iter().map(|(b,w)|(b.clone(),[hist(&w[0]),hist(&w[1])])).collect()).unwrap_or_default();
 let rows=v["rows"].as_array().map(Vec::as_slice).unwrap_or_default().iter().filter_map(|r|Some(Move{
  base:r[0].as_str()?.to_string(),up:r[1].as_bool()?,window:usize::try_from(r[2].as_u64()?).ok().filter(|w|*w<WINDOWS.len())?,
  pct:r[3].as_f64()?,price:r[4].as_f64()?,vol:r[5].as_f64()?,first:r[6].as_i64()?,at:r[7].as_i64()?,ratio:r[8].as_f64()?})).collect();
 (hists,rows)
}

async fn load(pool:&PgPool)->Option<Value> {
 let row=sqlx::query("SELECT payload FROM orderflow_highlights WHERE base=$1").bind(KEY).fetch_optional(pool).await.ok()??;
 row.try_get::<sqlx::types::Json<Value>,_>(0).ok().map(|j|j.0)
}

async fn save(pool:&PgPool,payload:&Value,at:i64) {
 let r=sqlx::query("INSERT INTO orderflow_highlights(base,updated_ms,payload) VALUES($1,$2,$3) ON CONFLICT(base) DO UPDATE SET updated_ms=EXCLUDED.updated_ms,payload=EXCLUDED.payload")
  .bind(KEY).bind(at).bind(sqlx::types::Json(payload)).execute(pool).await;
 if let Err(e)=r {tracing::warn!("Market moves: save failed: {e}");}
}

pub(super) async fn run(pool:PgPool) {
 let (mut hists,rows)=load(&pool).await.map(|v|restore(&v)).unwrap_or_default();
 *MOVES.write().unwrap_or_else(|e|e.into_inner())=rows;
 let mut ring:VecDeque<(i64,Prices)>=VecDeque::new();
 let mut saved=now_ms();
 loop {
  let now=now_ms();
  let next=(now.div_euclid(M)+1)*M+SCAN_AT_MS;
  tokio::time::sleep(Duration::from_millis(u64::try_from(next-now).unwrap_or(0))).await;
  let cur=market::prices().await;
  let now=now_ms();
  if cur.is_empty() {tracing::warn!("Market moves: price scan returned nothing");continue}
  let minute=now.div_euclid(M)*M;
  ring.retain(|(m,_)|*m<minute&&minute-m<=5*M);
  ring.push_back((minute,cur.into_iter().map(|(b,c)|(b,(c.src,c.px))).collect()));
  let vol=market::turnover();
  let found=detect(&ring,&mut hists,|b|vol.get(b).copied().unwrap_or(0.0));
  {
   let mut rows=MOVES.write().unwrap_or_else(|e|e.into_inner());
   for m in found {absorb(&mut rows,m);}
   prune(&mut rows,minute);
  }
  if now-saved>=PERSIST_EVERY_MS {
   let today=now.div_euclid(DAY_MS);
   hists.retain(|_,h|h.iter().any(|h|h.newest_day().is_some_and(|d|d>today-KEEP_DAYS)));
   save(&pool,&payload(&hists,&current()),now).await;
   saved=now;
  }
 }
}

// ------------------------------------------------------------------ 接口

/// 按这一份里各行权重的三分位：前三分之一 3、中间 2、后三分之一 1（与异动一列同一规则）。
pub(super) fn rows_json(rows:&[Move],now:i64)->Vec<Value> {
 let mut order:Vec<(usize,f64)>=rows.iter().enumerate().map(|(i,r)|(i,r.weight(now))).collect();
 order.sort_by(|a,b|b.1.total_cmp(&a.1).then_with(||a.0.cmp(&b.0)));
 let mut tiers=vec![1u8;rows.len()];
 for (rank,(i,_)) in order.iter().enumerate() {tiers[*i]=super::board::tier(rank,rows.len());}
 rows.iter().zip(tiers).map(|(r,t)|r.json(t)).collect()
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(in super::super) struct MovesQuery {limit:Option<usize>}

/// 全部波动异动：`limit` 1–30（缺省 30），新的在前。
pub(in super::super) async fn market_moves(Axum(_s):Axum<AppState>,headers:axum::http::HeaderMap,Params(q):Params<MovesQuery>)->Result<Response> {
 let limit=q.limit.unwrap_or(MAX_ROWS);
 if !(1..=MAX_ROWS).contains(&limit) {return Err(ApiError::bad("invalid_limit"))}
 let gzip=accepts_gzip(&headers);
 let answer=ANSWERS.get_or_build((limit,gzip),||async move {
  let now=now_ms();
  let mut rows=current();
  rows.truncate(limit);
  let json=json!({"generatedAtMs":now,"rows":rows_json(&rows,now)});
  packed(json.to_string(),gzip,CACHE_CONTROL)
 }).await?;
 Ok(answer.response())
}

#[cfg(test)]
mod tests {
 use super::*;

 const T0:i64=100*DAY_MS;

 fn fill(h:&mut Hist,n:u32,abs:f64,floor:f64,at:i64) {for _ in 0..n {h.add(abs,floor,at);}}

 #[test]
 fn threshold_is_the_floor_until_a_day_of_samples_then_p995() {
  let mut h=Hist::default();
  // 不到一天：哪怕全是 3 %，阈值也只是下限。
  fill(&mut h,MIN_SAMPLES-1,3.0,1.0,T0);
  assert_eq!(h.threshold(1.0,T0),1.0);
  // 一天整：P99.5 在下限以上，取它那一档的下沿。
  let mut h=Hist::default();
  fill(&mut h,2000-20,0.2,1.0,T0);
  fill(&mut h,20,2.0,1.0,T0);
  let thr=h.threshold(1.0,T0);
  assert!(thr>1.9&&thr<=2.0,"{thr}");
  // 下限以上的不到 0.5 %：P99.5 落在下限以下，阈值就是下限。
  let mut h=Hist::default();
  fill(&mut h,2000-5,0.2,1.0,T0);
  fill(&mut h,5,4.0,1.0,T0);
  assert_eq!(h.threshold(1.0,T0),1.0);
 }

 #[test]
 fn samples_older_than_thirty_days_drop_out() {
  let mut h=Hist::default();
  fill(&mut h,2000,3.0,1.0,T0);
  assert!(h.threshold(1.0,T0)>2.9);
  assert_eq!(h.threshold(1.0,T0+KEEP_DAYS*DAY_MS),1.0,"a month later the old day no longer counts");
  h.add(0.1,1.0,T0+KEEP_DAYS*DAY_MS);
  assert_eq!(h.days.len(),1,"adding a sample prunes days past the window");
 }

 fn ring(rows:&[(i64,&[(&str,usize,f64)])])->VecDeque<(i64,Prices)> {
  rows.iter().map(|(m,ps)|(*m,ps.iter().map(|(b,s,p)|(b.to_string(),(*s,*p))).collect())).collect()
 }

 #[test]
 fn detects_one_and_five_minute_moves_gated_by_volume_and_source() {
  let m0=T0+10*M;
  let r=ring(&[(m0-5*M,&[("A",0,100.0),("B",0,100.0),("C",0,100.0),("D",0,100.0)]),
   (m0-M,&[("A",0,100.0),("B",0,101.0),("C",0,100.0),("D",1,100.0)]),
   (m0,&[("A",0,101.2),("B",0,102.7),("C",0,98.0),("D",0,110.0)])]);
  let mut hists=HashMap::new();
  let vol=|b:&str|if b=="C" {500_000.0} else {2e6};
  let mut got=detect(&r,&mut hists,vol);
  got.sort_by(|a,b|a.base.cmp(&b.base));
  let short:Vec<(&str,bool,&str,f64)>=got.iter().map(|m|(m.base.as_str(),m.up,WINDOWS[m.window].0,(m.pct*100.0).round()/100.0)).collect();
  // A：1 分钟 +1.2 % 过 1 % 下限；5 分钟 +1.2 % 不到 2.5 %。
  // B：1 分钟 +1.68 % 与 5 分钟 +2.7 % 都过，留大的。
  // C：-2 % 但成交额不够。D：1 分钟前那一份是别家给的价，只比 5 分钟（+10 %）。
  assert_eq!(short,vec![("A",true,"1m",1.2),("B",true,"5m",2.7),("D",true,"5m",10.0)]);
  assert!((got[1].ratio-2.7/2.5).abs()<1e-9);
  assert_eq!(hists["C"][0].days[0].n,1,"gated samples still feed the distribution");
  assert_eq!(got[0].id(),format!("M:A:up:{m0}"));
 }

 #[test]
 fn same_base_and_direction_within_ten_minutes_merge_into_one_row() {
  let mv=|base:&str,up:bool,pct:f64,w:usize,at:i64|Move{base:base.into(),up,window:w,pct,price:at as f64,vol:1e6,first:at,at,ratio:pct.abs()};
  let mut rows=Vec::new();
  absorb(&mut rows,mv("A",true,3.0,1,T0));
  absorb(&mut rows,mv("A",true,1.5,0,T0+4*M));
  absorb(&mut rows,mv("A",false,-1.2,0,T0+5*M));
  absorb(&mut rows,mv("A",true,4.0,1,T0+13*M));
  absorb(&mut rows,mv("A",true,1.1,0,T0+24*M));
  assert_eq!(rows.len(),3,"up merged twice (chain within 10 min), down separate, the 11-minute gap starts a new row");
  let first=&rows[0];
  assert_eq!((first.pct,first.window,first.at,first.first),(4.0,1,T0+13*M,T0),"larger pct kept, latest minute, id unchanged");
  assert_eq!(first.price,(T0+13*M) as f64);
  assert_eq!(first.id(),format!("M:A:up:{T0}"));
  assert_eq!(rows[2].first,T0+24*M);
  prune(&mut rows,T0+24*M);
  assert_eq!(rows.iter().map(|r|r.at).collect::<Vec<_>>(),vec![T0+24*M,T0+13*M,T0+5*M],"newest first");
  prune(&mut rows,T0+24*M+KEEP_MS+1);
  assert!(rows.is_empty(),"only the last two hours are kept");
  let mut many:Vec<Move>=(0..40).map(|i|mv(&format!("B{i}"),true,2.0,0,T0+i*M)).collect();
  prune(&mut many,T0+40*M);
  assert_eq!(many.len(),MAX_ROWS);
 }

 #[test]
 fn rows_have_the_contract_shape_and_round_trip() {
  let rows=vec![Move{base:"SOL".into(),up:false,window:0,pct:-1.2345,price:123.456789,vol:2_345_678.9,first:T0,at:T0+M,ratio:1.2345}];
  let v=rows_json(&rows,T0+M);
  for k in ["id","base","cat","kind","window","pct","price","volUsd","atMs","tier"] {assert!(v[0].get(k).is_some(),"{k}");}
  assert_eq!(v[0]["kind"],"moveDown");
  assert_eq!(v[0]["cat"],"move");
  assert_eq!(v[0]["window"],"1m");
  assert_eq!(v[0]["pct"],-1.23);
  assert_eq!(v[0]["tier"],3);
  let mut hists=HashMap::new();
  let mut h=Hist::default();
  fill(&mut h,3,2.0,1.0,T0);
  hists.insert("SOL".to_string(),[h,Hist::default()]);
  let (back_h,back_rows)=restore(&payload(&hists,&rows));
  assert_eq!(back_h,hists);
  assert_eq!(back_rows,rows);
 }
}
