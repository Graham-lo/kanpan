//! 关键价位的账本（§11 ②）：每只 base 按 8 bps 一格记账——挂单墙 ∑(金额 × 存在分钟)、主动成交额（买 / 卖分开）、
//! 爆仓额、触及次数、首次 / 末次触及。只累加，不按时钟衰减；过期只看价格：
//! * 收盘越过这一格 ≥ 0.5 × ATR(1h) 且连续 ≥ 15 分钟 → 已破：权重减半、角色翻过来（支撑变阻力），交给事件列表；
//! * 距现价 > 4 × ATR(4h) 的格留账不展示，价回来自动回到视野；
//! * 7 天没有任何记账（触及、墙、成交、爆仓）才删。
//!
//! 展示：相邻的高格合并（≤ 5 格宽），现价上下各取账本累计最大的 2 条。
use super::stats::{DAY_MS,quantile};
use std::collections::{BTreeMap,BTreeSet};

/// 一格多宽：8 bps（按对数等宽，格号 = floor(ln 价 ÷ ln 1.0008)）。
pub(super) const STEP:f64=0.0008;
/// 离开至少这么久再碰到才算又测了一次。
pub(super) const TEST_GAP_MS:i64=5*60_000;
pub(super) const BREAK_ATR:f64=0.5;
pub(super) const BREAK_HOLD_MS:i64=15*60_000;
pub(super) const VISIBLE_ATR:f64=4.0;
/// ATR 还没有时的视野：现价上下 5%。
pub(super) const VISIBLE_FALLBACK:f64=0.05;
pub(super) const FORGET_MS:i64=7*DAY_MS;
pub(super) const MAX_WIDTH:usize=5;
pub(super) const PER_SIDE:usize=2;
/// 强格：视野里权重 ≥ 这个分位。
const STRONG_Q:f64=0.75;
/// 「撤单 N%」：撤掉的占初始 ≥ 40%。
pub(super) const REDUCING:f64=0.4;

fn ln_step()->f64 {(1.0+STEP).ln()}
pub(super) fn key(price:f64)->i64 {(price.ln()/ln_step()*(1.0+1e-12)).floor() as i64}
pub(super) fn low(k:i64)->f64 {(k as f64*ln_step()).exp()}
pub(super) fn high(k:i64)->f64 {low(k+1)}

#[derive(Clone,Debug,Default,PartialEq)]
pub(super) struct Bucket {
 /// 挂单墙 ∑(美元 × 分钟)、有墙的分钟数。
 pub w:f64,pub wm:f64,
 /// 主动买 / 卖成交美元、爆仓美元。
 pub fb:f64,pub fs:f64,pub lq:f64,
 pub tests:u32,pub first:Option<i64>,pub last:Option<i64>,
 /// 最后一次有任何记账的时刻（7 天没有就删）。
 pub active:i64,
 /// 这一格此刻的角色：1 = 价从上方来（支撑），-1 = 从下方来（阻力），0 = 还没定。
 pub role:i8,
 /// 上一根没碰到它时价在哪边：1 上、-1 下、0 不知道。
 pub pos:i8,
 /// 收盘从哪一刻起一直在「已破」那一侧。
 pub beyond:Option<i64>,
 pub broken:bool,
}

impl Bucket {
 fn halve(&mut self) {self.w*=0.5;self.wm*=0.5;self.fb*=0.5;self.fs*=0.5;self.lq*=0.5;}
 fn fill(&self)->f64 {self.fb+self.fs}
}

/// 一格被破：格号、时刻、原来是不是支撑。
#[derive(Clone,Copy,Debug,PartialEq)]
pub(super) struct Broke {pub k:i64,pub at:i64,pub was_support:bool}

/// 此刻挂着的一堵墙（要点引擎每分钟从跟踪器拿一份）。
#[derive(Clone,Debug,PartialEq)]
pub(super) struct Live {pub bid:bool,pub price:f64,pub usd:f64,pub initial:f64,pub filled:f64,pub first:i64}
impl Live {
 /// 撤掉的美元：初始 − 现在 − 已成交（不为负）。
 pub fn cancelled(&self)->f64 {(self.initial-self.usd-self.filled).max(0.0)}
}

/// 结构参照位（当日高低、昨日高低、VWAP、区间两沿）：只在叠上墙 / 成交 / 爆仓时写进 refs。
#[derive(Clone,Copy,Debug,PartialEq)]
pub(super) struct Ref {pub name:&'static str,pub price:f64}

/// 合并好的一条关键价位。
#[derive(Clone,Debug,PartialEq)]
pub(super) struct Level {
 pub k:i64,pub low:f64,pub high:f64,pub bid:bool,pub dist_pct:f64,
 pub wall_usd:f64,pub wall_held_ms:i64,pub wall_state:Option<&'static str>,
 pub fill_buy:f64,pub fill_sell:f64,pub liq:f64,pub tests:u32,pub touch:(Option<i64>,Option<i64>),
 pub refs:Vec<&'static str>,pub weight:f64,
}

#[derive(Clone,Debug,Default,PartialEq)]
pub(super) struct Ledger {pub b:BTreeMap<i64,Bucket>}

impl Ledger {
 fn entry(&mut self,k:i64,at:i64,px:Option<f64>)->&mut Bucket {
  let b=self.b.entry(k).or_insert_with(||{
   let pos=match px {Some(p) if p>=high(k)=>1,Some(p) if p<low(k)=>-1,_=>0};
   Bucket{role:pos,pos,active:at,..Bucket::default()}
  });
  b.active=b.active.max(at);
  b
 }

 /// 这一分钟挂着的墙：每堵墙记「金额 × 1 分钟」，每格有墙就记一分钟。`px` 是此刻的价（新格定角色用）。
 pub fn walls(&mut self,at:i64,walls:&[Live],px:Option<f64>) {
  let mut seen=BTreeSet::new();
  for w in walls.iter().filter(|w|w.price>0.0&&w.usd.is_finite()&&w.usd>0.0) {
   let k=key(w.price);
   self.entry(k,at,px).w+=w.usd;
   seen.insert(k);
  }
  for k in seen {if let Some(b)=self.b.get_mut(&k) {b.wm+=1.0;}}
 }

 pub fn fill(&mut self,k:i64,buy:f64,sell:f64,at:i64,px:Option<f64>) {
  if !(buy.is_finite()&&sell.is_finite())||buy+sell<=0.0 {return}
  let b=self.entry(k,at,px);
  b.fb+=buy.max(0.0);b.fs+=sell.max(0.0);
 }

 pub fn liq(&mut self,price:f64,usd:f64,at:i64,px:Option<f64>) {
  if !(price>0.0&&usd.is_finite()&&usd>0.0) {return}
  self.entry(key(price),at,px).lq+=usd;
 }

 /// 一根收完的 1 分钟线：碰到的格记触及（离开 ≥ 5 分钟再碰算又测一次），没碰到的看破没破。
 pub fn bar(&mut self,t:i64,h:f64,l:f64,c:f64,atr1h:Option<f64>)->Vec<Broke> {
  let mut out=Vec::new();
  if !(h>0.0&&l>0.0&&c>0.0&&h>=l) {return out}
  let (klo,khi)=(key(l),key(h));
  for (&k,b) in &mut self.b {
   if (klo..=khi).contains(&k) {
    if b.last.is_none_or(|last|t-last>TEST_GAP_MS) {
     b.tests+=1;
     // 这一次从哪边来：从上方来的是支撑，从下方来的是阻力（破过之后回测，角色自然跟着变）。
     if b.pos!=0 {b.role=b.pos;}
    }
    b.first.get_or_insert(t);
    b.last=Some(t);
    b.active=b.active.max(t);
    b.beyond=None;
    continue;
   }
   let (lo,hi)=(low(k),high(k));
   b.pos=if l>=hi {1} else {-1};
   if b.role==0 {b.role=b.pos;}
   let Some(a)=atr1h.filter(|a|*a>0.0) else {b.beyond=None;continue};
   let beyond=match b.role {1=>c<lo-BREAK_ATR*a,-1=>c>hi+BREAK_ATR*a,_=>false};
   if !beyond {b.beyond=None;continue}
   let since=*b.beyond.get_or_insert(t);
   if t-since>=BREAK_HOLD_MS {
    let was_support=b.role==1;
    b.halve();
    b.broken=true;
    b.role= -b.role;
    b.beyond=None;
    out.push(Broke{k,at:t,was_support});
   }
  }
  out
 }

 /// 起步补洞：落盘之后到这一任开始收之前那一段的历史 K 线（`(开始时刻, 根长, 高, 低)`，按时间升序）只补触及次数与
 /// 首末触及——已破只由实时的线判。连着几根都碰到同一格算一次（相邻两根的间隔不超过根长与 5 分钟里大的那个）。
 pub fn replay(&mut self,bars:&[(i64,i64,f64,f64)]) {
  let mut last:std::collections::HashMap<i64,i64>=std::collections::HashMap::new();
  for &(t,len,h,l) in bars {
   if !(h>0.0&&l>0.0&&h>=l) {continue}
   for (&k,b) in self.b.range_mut(key(l)..=key(h)) {
    if last.insert(k,t).is_none_or(|p|t-p>len.max(TEST_GAP_MS)) {b.tests+=1;}
    b.first=Some(b.first.map_or(t,|f|f.min(t)));
    b.last=Some(b.last.map_or(t,|x|x.max(t)));
    b.active=b.active.max(t);
   }
  }
 }

 /// 7 天没有任何记账的格删掉。
 pub fn expire(&mut self,now:i64) {self.b.retain(|_,b|now-b.active<=FORGET_MS);}

 /// 一段价里（两沿的边带）累计吃单与最多触及次数。
 pub fn edge(&self,lo:f64,hi:f64)->(f64,u32) {
  if !(lo>0.0&&hi>=lo) {return (0.0,0)}
  self.b.range(key(lo)..=key(hi)).fold((0.0,0),|(f,t),(_,b)|(f+b.fill(),t.max(b.tests)))
 }

 /// 视野里（现价 ± 4 × ATR(4h)）的格。
 fn visible(&self,price:f64,atr4h:Option<f64>)->Vec<(i64,&Bucket)> {
  let reach=atr4h.filter(|a|*a>0.0).map_or(price*VISIBLE_FALLBACK,|a|VISIBLE_ATR*a);
  let (lo,hi)=((price-reach).max(price*1e-6),price+reach);
  self.b.range(key(lo)..=key(hi)).map(|(k,b)|(*k,b)).collect()
 }

 /// 展示用的关键价位：现价上下各 ≤ 2 条，按价从高到低。
 pub fn levels(&self,price:f64,atr4h:Option<f64>,live:&[Live],refs:&[Ref],now:i64)->Vec<Level> {
  if !(price>0.0) {return Vec::new()}
  let visible=self.visible(price,atr4h);
  let (sw,sf,sl)=visible.iter().fold((0.0,0.0,0.0),|(w,f,l),(_,b)|(w+b.w,f+b.fill(),l+b.lq));
  let share=|x:f64,total:f64|if total>0.0 {x/total} else {0.0};
  let weights:BTreeMap<i64,f64>=visible.iter().map(|(k,b)|(*k,share(b.w,sw)+share(b.fill(),sf)+share(b.lq,sl))).filter(|(_,w)|*w>0.0).collect();
  if weights.is_empty() {return Vec::new()}
  let values:Vec<f64>=weights.values().copied().collect();
  let floor=if values.len()>=4 {quantile(values,STRONG_Q).unwrap_or(0.0)} else {0.0};
  let strong:BTreeMap<i64,f64>=weights.iter().filter(|(_,w)|**w>=floor).map(|(k,w)|(*k,*w)).collect();
  // 从最重的格起往两边并相邻的强格，最多 5 格宽。
  let mut order:Vec<(i64,f64)>=strong.iter().map(|(k,w)|(*k,*w)).collect();
  order.sort_by(|a,b|b.1.total_cmp(&a.1).then(a.0.cmp(&b.0)));
  let mut used=BTreeSet::new();
  let mut clusters:Vec<(i64,i64,f64)>=Vec::new();
  for (peak,_) in order {
   if used.contains(&peak) {continue}
   let (mut lo,mut hi)=(peak,peak);
   used.insert(peak);
   while ((hi-lo+1) as usize)<MAX_WIDTH {
    let left=strong.get(&(lo-1)).filter(|_|!used.contains(&(lo-1))).copied();
    let right=strong.get(&(hi+1)).filter(|_|!used.contains(&(hi+1))).copied();
    match (left,right) {
     (Some(a),Some(b)) if a>=b=>{lo-=1;used.insert(lo);},
     (_,Some(_))=>{hi+=1;used.insert(hi);},
     (Some(_),None)=>{lo-=1;used.insert(lo);},
     (None,None)=>break,
    }
   }
   let weight=(lo..=hi).filter_map(|k|strong.get(&k)).sum();
   clusters.push((lo,hi,weight));
  }
  clusters.sort_by(|a,b|b.2.total_cmp(&a.2).then(a.0.cmp(&b.0)));
  let (mut bids,mut asks)=(0,0);
  let mut out=Vec::new();
  for (lo,hi,weight) in clusters {
   let (low_px,high_px)=(low(lo),high(hi));
   let mid=(low_px+high_px)/2.0;
   let bid=mid<price;
   if bid {if bids>=PER_SIDE {continue} bids+=1} else {if asks>=PER_SIDE {continue} asks+=1}
   out.push(self.level(lo,hi,weight,price,live,refs,now));
   if bids>=PER_SIDE&&asks>=PER_SIDE {break}
  }
  out.sort_by(|a,b|b.low.total_cmp(&a.low));
  out
 }

 #[allow(clippy::too_many_arguments)]
 fn level(&self,lo:i64,hi:i64,weight:f64,price:f64,live:&[Live],refs:&[Ref],now:i64)->Level {
  let (low_px,high_px)=(low(lo),high(hi));
  let mid=(low_px+high_px)/2.0;
  let buckets:Vec<&Bucket>=self.b.range(lo..=hi).map(|(_,b)|b).collect();
  let walls:Vec<&Live>=live.iter().filter(|w|w.price>=low_px&&w.price<high_px).collect();
  let wall_usd:f64=walls.iter().map(|w|w.usd).sum();
  let initial:f64=walls.iter().map(|w|w.initial).sum();
  let cancelled:f64=walls.iter().map(|w|w.cancelled()).sum();
  let wall_state=if !walls.is_empty() {Some(if initial>0.0&&cancelled/initial>=REDUCING {"reducing"} else {"live"})}
   else if buckets.iter().any(|b|b.broken) {Some("broken")} else {None};
  let wall_held_ms=match walls.iter().map(|w|w.first).min() {
   Some(first)=>(now-first).max(0),
   None=>(buckets.iter().map(|b|b.wm).fold(0.0,f64::max)*60_000.0) as i64,
  };
  let margin=|p:f64|p>=low_px*(1.0-STEP)&&p<=high_px*(1.0+STEP);
  let mut names:Vec<&'static str>=refs.iter().filter(|r|r.price>0.0&&margin(r.price)).map(|r|r.name).collect();
  names.dedup();
  Level{k:lo,low:low_px,high:high_px,bid:mid<price,dist_pct:(mid-price)/price*100.0,
   wall_usd,wall_held_ms,wall_state,
   fill_buy:buckets.iter().map(|b|b.fb).sum(),fill_sell:buckets.iter().map(|b|b.fs).sum(),liq:buckets.iter().map(|b|b.lq).sum(),
   tests:buckets.iter().map(|b|b.tests).max().unwrap_or(0),
   touch:(buckets.iter().filter_map(|b|b.first).min(),buckets.iter().filter_map(|b|b.last).max()),
   refs:names,weight}
 }
}

#[cfg(test)]
mod tests {
 use super::*;

 #[test]
 fn replay_counts_each_visit_once_and_keeps_touch_times() {
  let mut l=Ledger::default();
  let k=key(100.0);
  l.b.insert(k,Bucket{w:1.0,..Default::default()});
  l.b.insert(key(120.0),Bucket{w:1.0,..Default::default()});
  let h=60*60_000;let f=5*60_000;
  // 两根小时线连着碰（一次），离开，再用三根 5 分钟线连着碰（又一次）。
  l.replay(&[(0,h,100.2,99.8),(h,h,100.2,99.9),(2*h,h,110.0,105.0),(3*h,f,100.1,99.9),(3*h+f,f,100.1,99.9),(3*h+2*f,f,100.1,99.9)]);
  let b=&l.b[&k];
  assert_eq!(b.tests,2);
  assert_eq!((b.first,b.last),(Some(0),Some(3*h+2*f)));
  assert_eq!(l.b[&key(120.0)].tests,0);
 }
 const M:i64=60_000;

 fn wall(price:f64,usd:f64)->Live {Live{bid:true,price,usd,initial:usd,filled:0.0,first:0}}

 #[test]
 fn keys_are_eight_bps_wide() {
  let k=key(100.0);
  assert!(low(k)<=100.0&&high(k)>100.0);
  assert!((high(k)/low(k)-1.0-STEP).abs()<1e-12);
  assert_eq!(key(low(k)),k,"a bucket's own low lands in it");
 }

 #[test]
 fn accumulates_walls_fills_and_liquidations_without_decay() {
  let mut l=Ledger::default();
  for minute in 0..30 {l.walls(minute*M,&[wall(99.0,1_000_000.0),wall(99.01,500_000.0)],Some(100.0));}
  l.fill(key(99.0),2_000_000.0,500_000.0,10*M,Some(100.0));
  l.liq(99.0,300_000.0,11*M,Some(100.0));
  let b=&l.b[&key(99.0)];
  assert_eq!(b.w,30.0*1_500_000.0,"two walls in one bucket add up per minute");
  assert_eq!(b.wm,30.0,"wall minutes count the bucket once a minute");
  assert_eq!((b.fb,b.fs,b.lq),(2_000_000.0,500_000.0,300_000.0));
  assert_eq!(b.role,1,"a bucket born under the price is a support");
  // 一天之后什么都没衰减。
  l.bar(24*60*M,100.5,100.2,100.4,Some(0.5));
  assert_eq!(l.b[&key(99.0)].w,30.0*1_500_000.0);
 }

 #[test]
 fn touches_count_tests_after_five_minutes_away() {
  let mut l=Ledger::default();
  l.walls(0,&[wall(100.0,1e6)],Some(101.0));
  let k=key(100.0);
  l.bar(M,100.1,99.9,100.05,None);
  l.bar(2*M,100.1,99.9,100.05,None);
  assert_eq!(l.b[&k].tests,1,"staying on it is one test");
  l.bar(3*M,101.0,100.5,100.8,None);
  l.bar(5*M,100.1,99.95,100.0,None);
  assert_eq!(l.b[&k].tests,1,"back within 5 minutes is the same test");
  l.bar(12*M,100.1,99.95,100.0,None);
  assert_eq!(l.b[&k].tests,2);
  assert_eq!(l.b[&k].first,Some(M));
  assert_eq!(l.b[&k].last,Some(12*M));
 }

 #[test]
 fn breaks_only_after_fifteen_minutes_beyond_half_an_atr() {
  let mut l=Ledger::default();
  l.walls(0,&[wall(100.0,1e6)],Some(101.0));
  l.fill(key(100.0),4e6,0.0,0,Some(101.0));
  let k=key(100.0);
  // ATR(1h) = 2 → 要收在 100 − 1 = 99 以下。98.5 收 14 分钟后弹回去：不算破。
  for m in 1..=14 {assert!(l.bar(m*M,98.7,98.4,98.5,Some(2.0)).is_empty());}
  l.bar(15*M,99.6,99.3,99.5,Some(2.0));
  assert!(!l.b[&k].broken);
  // 连着 15 分钟（含第 16 根）收在 99 以下：已破，减半，角色翻成阻力。
  let mut broke=Vec::new();
  for m in 16..=40 {broke.extend(l.bar(m*M,98.7,98.4,98.5,Some(2.0)));}
  assert_eq!(broke,vec![Broke{k,at:31*M,was_support:true}]);
  let b=&l.b[&k];
  assert!(b.broken);
  assert_eq!(b.role,-1);
  assert_eq!(b.w,0.5e6);
  assert_eq!(b.fb,2e6);
  // 一直在下面不会再破一次。
  assert!(l.bar(60*M,98.7,98.4,98.5,Some(2.0)).is_empty());
 }

 #[test]
 fn far_buckets_are_kept_but_hidden_and_forgotten_after_seven_days() {
  let mut l=Ledger::default();
  l.walls(0,&[wall(100.0,1e6),wall(80.0,5e6)],Some(100.5));
  let levels=l.levels(100.5,Some(1.0),&[],&[],0);
  assert_eq!(levels.len(),1,"80 is more than 4 ATR away");
  assert!(l.b.contains_key(&key(80.0)),"…but stays on the books");
  // 价回到 81：80 回到视野。
  let back=l.levels(81.0,Some(1.0),&[],&[],0);
  assert!(back.iter().any(|v|v.low<=80.0&&v.high>80.0));
  l.walls(6*DAY_MS,&[wall(100.0,1e6)],Some(100.5));
  l.expire(7*DAY_MS+M);
  assert!(!l.b.contains_key(&key(80.0)),"untouched for 7 days");
  assert!(l.b.contains_key(&key(100.0)));
 }

 #[test]
 fn merges_neighbours_at_most_five_wide_and_two_per_side() {
  let mut l=Ledger::default();
  let px=100.0;
  // 下方一串 8 个相邻的强格、另外三处单格；上方三处单格；再垫 40 个弱格让 P75 落在强格以下。
  let base=key(98.0);
  for i in 0..8 {l.fill(base+i,1e6+i as f64,0.0,0,Some(px));}
  for p in [95.0,96.0,97.0,101.0,102.0,103.0] {l.fill(key(p),2e6,0.0,0,Some(px));}
  for j in 0..40 {l.fill(key(104.5)+j,1e3,0.0,0,Some(px));}
  let levels=l.levels(px,Some(3.0),&[],&[],0);
  let bids:Vec<&Level>=levels.iter().filter(|v|v.bid).collect();
  let asks:Vec<&Level>=levels.iter().filter(|v|!v.bid).collect();
  assert_eq!(bids.len(),2);
  assert_eq!(asks.len(),2);
  for v in &levels {assert!(((key(v.high*(1.0-1e-9))-v.k+1) as usize)<=MAX_WIDTH);}
  assert!(levels.windows(2).all(|w|w[0].low>w[1].low),"sorted high to low");
  assert_eq!(((key(bids[0].high*(1.0-1e-9))-bids[0].k)+1),5,"the run of eight is cut at five");
 }

 #[test]
 fn level_carries_wall_state_and_refs() {
  let mut l=Ledger::default();
  l.walls(0,&[wall(99.0,1e6)],Some(100.0));
  let live=[Live{bid:true,price:99.0,usd:5e5,initial:1e6,filled:1e5,first:-30*M}];
  let refs=[Ref{name:"dayLow",price:99.02},Ref{name:"vwap",price:101.0}];
  let v=&l.levels(100.0,Some(1.0),&live,&refs,0)[0];
  assert_eq!(v.wall_state,Some("reducing"),"40% cancelled");
  assert_eq!(v.wall_held_ms,30*M);
  assert_eq!(v.refs,vec!["dayLow"]);
  assert!(v.dist_pct<0.0);
 }
}
