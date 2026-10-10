//! 一只 base 的要点状态：分钟序列（3 天净主动 / 成交额 / 爆仓，26 小时价）、小时线（30 天，带净主动）、持仓、
//! 账本、分位样本、此刻挂着的墙、近 3 天结束的墙；每分钟由引擎折进新数据、算一份答复。
use super::events::{self,Ended,Ev,round,usd};
use super::fetch::{Boot,K};
use super::ledger::{self,Broke,Ledger,Live,Ref};
use super::range::{self,Range};
use super::stats::{DAY_MS,HOUR_MS,Hl,Samples,Sizes,atr,four_hour,quantile_distinct,rank};
use serde_json::{Value,json};
use std::collections::{BTreeMap,VecDeque};

pub(super) const M:i64=60_000;
/// 分钟序列：净主动 / 成交额 / 多空爆仓留 3 天（事件分位要近 3 天），价留 26 小时（24 时窗口 + 余量）。
pub(super) const FLOW_MINUTES:usize=3*1440;
pub(super) const PX_MINUTES:usize=26*60;
pub(super) const HOURS_KEEP:i64=30*DAY_MS;
pub(super) const OI5_KEEP:i64=30*HOUR_MS;
/// 背离：|涨跌| ≥ 0.5%，|净主动| ≥ 同窗口 P60。
pub(super) const DIVERGE_PX:f64=0.5;
pub(super) const DIVERGE_Q:f64=0.6;
/// 持仓 · 费率 · 现货溢价：任一项 ≥ P90 或 ≤ P10 才出。
pub(super) const EXTREME_HI:u8=90;
pub(super) const EXTREME_LO:u8=10;
/// 墙事件与首页墙价位的规模门槛：这只近 3 天结束的墙的 P90（不到 50 堵不设门槛）。
pub(super) const WALL_Q:f64=0.9;
pub(super) const WALL_MIN_SAMPLES:u64=50;
/// 数据停了多久算「停」（答复里给 staleMs）。
pub(super) const STALE_MS:i64=3*M;
/// 首页：近度按 2 小时的指数衰减；墙价位离现价 ≤ 2% 才上首页。
const RECENCY_MS:f64=2.0*3_600_000.0;

/// 首页异动一列的近度系数：每过 2 小时乘 1/e。
pub(super) fn recency(now:i64,at:i64)->f64 {(-((now-at).max(0) as f64)/RECENCY_MS).exp()}
const BOARD_LEVEL_DIST:f64=2.0;
/// 净主动的数要盖到窗口起点前后这么近才算整窗（否则 `netUsd` 为 null）。
const FLOW_SLACK_MS:i64=10*M;
/// 分钟序列里连着这么多分钟没成交就算断了（永续几乎每分钟都有成交）。
const FLOW_GAP_MINUTES:usize=10;
/// 北京时间日界（当日高低、VWAP）。
const DAY_OFFSET:i64=8*HOUR_MS;

/// 定长的分钟序列：`t0` 起每分钟一格，超出 `cap` 格丢最早的；缺的格是 `fill`。
#[derive(Clone,Debug)]
pub(super) struct Series<const N:usize> {pub t0:i64,pub v:VecDeque<[f32;N]>,cap:usize,fill:f32}

impl<const N:usize> Series<N> {
 pub fn new(cap:usize,fill:f32)->Self {Self{t0:0,v:VecDeque::new(),cap,fill}}
 pub fn is_empty(&self)->bool {self.v.is_empty()}
 pub fn end(&self)->i64 {self.t0+self.v.len() as i64*M}
 pub fn slot(&mut self,minute:i64)->Option<&mut [f32;N]> {
  let minute=minute.div_euclid(M)*M;
  let blank=[self.fill;N];
  if self.v.is_empty() {self.t0=minute;self.v.push_back(blank);}
  if minute<self.t0 {
   let back=((self.t0-minute)/M) as usize;
   if back+self.v.len()>self.cap {return None}
   for _ in 0..back {self.v.push_front(blank);}
   self.t0=minute;
  }
  let i=((minute-self.t0)/M) as usize;
  if i>=self.v.len() {
   let need=i+1-self.v.len();
   if need>=self.cap {self.v.clear();self.t0=minute;self.v.push_back(blank);}
   else {for _ in 0..need {self.v.push_back(blank);}}
  }
  while self.v.len()>self.cap {self.v.pop_front();self.t0+=M;}
  let i=((minute-self.t0)/M) as usize;
  self.v.get_mut(i)
 }
 pub fn get(&self,minute:i64)->Option<&[f32;N]> {
  if self.v.is_empty()||minute<self.t0 {return None}
  self.v.get(((minute-self.t0)/M) as usize)
 }
 /// `from..to` 里第 `i` 列之和（序列外的当 0）。
 pub fn sum(&self,i:usize,from:i64,to:i64)->f64 {
  if self.v.is_empty() {return 0.0}
  let a=((from.max(self.t0)-self.t0)/M).max(0) as usize;
  let b=((to.min(self.end())-self.t0+M-1)/M).max(0) as usize;
  (a..b.min(self.v.len())).map(|j|f64::from(self.v[j][i])).filter(|x|x.is_finite()).sum()
 }
 /// 第 `i` 列在 `t` 之前（含）最近的有限值，最多往回找 `back` 分钟。
 pub fn last_before(&self,i:usize,t:i64,back:i64)->Option<f64> {
  let mut m=t.div_euclid(M)*M;
  let stop=t-back;
  while m>=stop&&m>=self.t0 {
   if let Some(v)=self.get(m).map(|r|f64::from(r[i])).filter(|x|x.is_finite()&&*x>0.0) {return Some(v)}
   m-=M;
  }
  None
 }
}

#[derive(Clone,Copy,Debug,PartialEq)]
pub(super) struct Hour {pub o:f64,pub h:f64,pub l:f64,pub c:f64,pub net:f64}

/// 一根收完的 1 分钟线（参考永续：币安 > OKX > Bybit > Hyperliquid）与这一分钟最后的现货价。
#[derive(Clone,Copy,Debug,PartialEq)]
pub(super) struct Bar {pub t:i64,pub o:f64,pub h:f64,pub l:f64,pub c:f64,pub spot:Option<f64>}

/// 分位样本：四个窗口的净主动、持仓 1 时变化、资金费率、现货溢价。
#[derive(Clone,Debug,Default,PartialEq)]
pub(super) struct Sampled {pub n15:Samples,pub n1h:Samples,pub n4h:Samples,pub n24:Samples,pub oi:Samples,pub funding:Samples,pub premium:Samples}

/// 引擎从各处收进来、还没折进状态的一批。
#[derive(Debug,Default)]
pub(super) struct Pending {
 pub flow:BTreeMap<i64,(f64,f64)>,
 pub fills:Vec<(i64,BTreeMap<i64,(f64,f64)>)>,
 pub bars:Vec<Bar>,
 pub walls:Vec<(i64,Vec<Live>)>,
 pub ended:Vec<Ended>,
 pub liq:Vec<(i64,bool,f64,f64)>,
}

impl Pending {
 /// 引擎停着的时候别无限攒：每样最多留 3 小时左右。
 pub fn cap(&mut self) {
  const KEEP:usize=200;
  while self.flow.len()>KEEP {self.flow.pop_first();}
  if self.fills.len()>KEEP {self.fills.drain(..self.fills.len()-KEEP);}
  if self.bars.len()>KEEP {self.bars.drain(..self.bars.len()-KEEP);}
  if self.walls.len()>4 {self.walls.drain(..self.walls.len()-4);}
  if self.ended.len()>5000 {self.ended.drain(..self.ended.len()-5000);}
  if self.liq.len()>20_000 {self.liq.drain(..self.liq.len()-20_000);}
 }
}

/// 首页那一行要的：要点条数、类别、排第一那条、它的权重与时刻。
#[derive(Clone,Debug,PartialEq)]
pub(super) struct BoardItem {pub count:usize,pub cat:&'static str,pub top:Value,pub weight:f64,pub at:i64}

/// 算好的一份：答复的 JSON、首页那一行、价与 24 时涨跌。
#[derive(Clone,Debug)]
pub(super) struct Snap {pub json:Value,pub board:Option<BoardItem>,pub price:Option<f64>,pub change_pct:Option<f64>}

pub(super) struct State {
 pub base:String,
 /// 净主动、成交额、多头爆仓、空头爆仓。
 pub flow:Series<4>,
 /// 收、高、低、现货。
 pub px:Series<4>,
 pub hours:BTreeMap<i64,Hour>,
 pub oi5:BTreeMap<i64,f64>,
 pub oi1h:BTreeMap<i64,f64>,
 pub funding:Option<f64>,
 pub ledger:Ledger,
 /// 账本记到哪一刻了（落盘带着；下次起步从这里补到 `live_from`）。
 pub until:i64,
 /// 这一任第一次直接收到的分钟（库里的历史只补它之前的）。
 pub live_from:Option<i64>,
 pub samples:Sampled,
 pub live:Vec<Live>,
 /// 近 4 小时够得上事件规则的结束的墙；近 3 天结束的墙的规模直方图。
 pub ended:Vec<Ended>,
 pub sizes:Sizes,
 pub broken:Vec<Broke>,
 pub last_bar:i64,
 pub sampled:i64,
 pub booted:bool,
 pub created:i64,
 /// 账本的触及次数是不是已经按历史 K 线补过整段（落盘带着；10-10 补次数上线前落的盘没有，起步时重补一遍）。
 pub touches_backfilled:bool,
 /// 首页「持仓 · 费率 · 现货溢价」那一项从哪一刻起一直是同一类极端（`atMs` 用它，不是每分钟重算的时刻）。
 pub position_since:Option<(&'static str,i64)>,
 /// 这只是从哪一刻开始现场收的（新起跟、库里没有落过盘的才有；墙 / 吃单账本 / 爆仓要现场攒，关键价位与事件在这之后
 /// 4 小时内算「观察中」）。不落盘：重启后读回落过的盘，就不算新起跟。
 pub observing_since:Option<i64>,
}

/// 价位上几段（墙 / 吃单 / 爆仓）各自的地板：占这条价位合计不到 [`SEGMENT_SHARE`] 的不显示（写 0，客户端不画），
/// 爆仓还要过这只自己「有爆仓的分钟」的中位数；墙只要过了墙规模 P90（`wall_floor`）就留，哪怕旁边的吃单大得多。
const SEGMENT_SHARE:f64=0.02;
pub(super) fn trim_segments(v:&mut ledger::Level,liq_p50:Option<f64>,wall_floor:f64) {
 let total=v.wall_usd+v.fill_buy+v.fill_sell+v.liq;
 let share=SEGMENT_SHARE*total;
 if v.liq<share.max(liq_p50.unwrap_or(0.0)) {v.liq=0.0;}
 if v.fill_buy<share {v.fill_buy=0.0;}
 if v.fill_sell<share {v.fill_sell=0.0;}
 if v.wall_usd>0.0&&v.wall_usd<share&&v.wall_usd<wall_floor {
  v.wall_usd=0.0;
  if matches!(v.wall_state,Some("live")|Some("reducing")) {v.wall_state=None;}
 }
}

fn finite(x:f64)->Option<f64> {x.is_finite().then_some(x)}
fn pct(a:f64,b:f64)->Option<f64> {(a>0.0&&b>0.0).then(||(b/a-1.0)*100.0).and_then(finite)}
/// 价保留 6 位有效数字。
pub(super) fn sig(p:f64)->f64 {
 if p==0.0 {return 0.0} // 不发 -0
 if !p.is_finite() {return p}
 let d=6-p.abs().log10().floor() as i32-1;
 let f=10f64.powi(d);
 (p*f).round()/f
}

impl State {
 pub fn new(base:&str,now:i64)->Self {
  Self{base:base.to_string(),flow:Series::new(FLOW_MINUTES,0.0),px:Series::new(PX_MINUTES,f32::NAN),hours:BTreeMap::new(),
   oi5:BTreeMap::new(),oi1h:BTreeMap::new(),funding:None,ledger:Ledger::default(),until:0,live_from:None,samples:Sampled::default(),
   live:Vec::new(),ended:Vec::new(),sizes:Sizes::default(),broken:Vec::new(),last_bar:0,sampled:0,booted:false,created:now,
   touches_backfilled:false,position_since:None,observing_since:None}
 }

 fn mark_live(&mut self,minute:i64) {
  let m=minute.div_euclid(M)*M;
  self.live_from=Some(self.live_from.map_or(m,|x|x.min(m)));
 }

 pub fn last_close(&self)->Option<f64> {
  self.px.last_before(0,self.px.end(),30*M).or_else(||self.hours.last_key_value().map(|(_,h)|h.c).filter(|c|*c>0.0))
 }

 /// 折进一批新数据。
 pub fn fold(&mut self,p:Pending,now:i64) {
  let px=self.last_close();
  for (m,(net,vol)) in p.flow {
   self.mark_live(m);
   if let Some(s)=self.flow.slot(m) {s[0]+=net as f32;s[1]+=vol as f32;}
  }
  for (m,fills) in p.fills {for (k,(b,s)) in fills {self.ledger.fill(k,b,s,m,px);}}
  for (at,long,usd,price) in p.liq {
   self.mark_live(at);
   if let Some(s)=self.flow.slot(at) {s[if long {2} else {3}]+=usd as f32;}
   self.ledger.liq(price,usd,at,px);
  }
  for (m,walls) in p.walls {
   self.ledger.walls(m,&walls,px);
   self.live=walls;
  }
  for e in p.ended {
   self.sizes.add(e.end,e.initial);
   if events::candidate(&e) {self.ended.push(e);}
  }
  let mut bars=p.bars;
  bars.sort_by_key(|b|b.t);
  for b in bars {self.bar(b);}
  self.ledger.expire(now);
  self.trim(now);
  self.until=self.until.max(now);
 }

 fn bar(&mut self,b:Bar) {
  if !(b.c>0.0&&b.h>=b.l&&b.l>0.0) {return}
  self.mark_live(b.t);
  if let Some(s)=self.px.slot(b.t) {*s=[b.c as f32,b.h as f32,b.l as f32,b.spot.map_or(f32::NAN,|v|v as f32)];}
  let hour=b.t.div_euclid(HOUR_MS)*HOUR_MS;
  let h=self.hours.entry(hour).or_insert(Hour{o:b.o,h:b.h,l:b.l,c:b.c,net:0.0});
  h.h=h.h.max(b.h);h.l=h.l.min(b.l);h.c=b.c;
  let a=self.atr1h();
  let broke=self.ledger.bar(b.t,b.h,b.l,b.c,a);
  self.broken.extend(broke);
  self.last_bar=self.last_bar.max(b.t);
 }

 fn trim(&mut self,now:i64) {
  while self.hours.first_key_value().is_some_and(|(t,_)|*t<now-HOURS_KEEP) {self.hours.pop_first();}
  while self.oi5.first_key_value().is_some_and(|(t,_)|*t<now-OI5_KEEP) {self.oi5.pop_first();}
  while self.oi1h.first_key_value().is_some_and(|(t,_)|*t<now-HOURS_KEEP) {self.oi1h.pop_first();}
  self.ended.retain(|e|e.end>=now-events::WINDOW_MS);
  self.sizes.trim(now);
  self.broken.retain(|b|b.at>=now-events::WINDOW_MS);
 }

 /// 起步补的历史合进来（只补这一任直接收到之前的分钟，账本只补缺口）。
 pub fn apply(&mut self,b:Boot,now:i64) {
  let lf=self.live_from.unwrap_or(i64::MAX);
  let current=now.div_euclid(HOUR_MS)*HOUR_MS;
  for k in &b.hours {
   let e=self.hours.entry(k.t).or_insert(Hour{o:k.o,h:k.h,l:k.l,c:k.c,net:0.0});
   if k.t>=current {e.h=e.h.max(k.h);e.l=e.l.min(k.l);e.o=k.o;} else {e.o=k.o;e.h=k.h;e.l=k.l;e.c=k.c;}
  }
  // REST 补的分钟（1 分钟线、由它算的净主动）只补这一任开始现场收之前：现场那一分钟的足迹是 `+=` 进来的，补了就算两遍。
  let cut=lf.min(b.gap.1);
  let spot_min:BTreeMap<i64,f64>=b.spot_minutes.iter().map(|k|(k.t,k.c)).collect();
  for k in &b.minutes {
   if k.t>=cut {continue}
   if let Some(s)=self.px.slot(k.t) {
    if !s[0].is_finite() {s[0]=k.c as f32;s[1]=k.h as f32;s[2]=k.l as f32;}
    if !s[3].is_finite() && let Some(sp)=spot_min.get(&k.t) {s[3]=*sp as f32;}
   }
  }
  for k in &b.fives {
   let at=k.t+4*M;
   if at>=lf {continue}
   if let Some(s)=self.px.slot(at) && !s[0].is_finite() {*s=[k.c as f32,k.h as f32,k.l as f32,f32::NAN];}
  }
  for (t,v) in &b.oi1h {self.oi1h.insert(*t,*v);}
  for (t,v) in &b.oi5 {self.oi5.insert(*t,*v);}
  for (t,v) in &b.funding {self.samples.funding.put(*t,*v);}
  let perp:BTreeMap<i64,&K>=b.hours.iter().map(|k|(k.t,k)).collect();
  for s in &b.spot_hours {
   if let Some(p)=perp.get(&s.t) && let Some(x)=pct(p.c,s.c) {self.samples.premium.put(s.t+HOUR_MS,x);}
  }
  for (m,(net,vol)) in &b.flow {
   if *m>=lf {continue}
   if let Some(s)=self.flow.slot(*m) {s[0]=*net as f32;s[1]=*vol as f32;}
  }
  for (m,(long,short,_)) in &b.liq {
   if *m>=lf {continue}
   if let Some(s)=self.flow.slot(*m) {s[2]=*long as f32;s[3]=*short as f32;}
  }
  // 库里没有足迹的分钟（没跟过的品种全是）用 1 分钟线的主动买入额补：只有币安一家合约，比足迹（全部家、合约 + 现货）窄，但流向四行马上有数。
  for (m,(net,vol)) in &b.kflow {
   if *m>=cut {continue}
   if let Some(s)=self.flow.slot(*m) && s[1]==0.0 {s[0]=*net as f32;s[1]=*vol as f32;}
  }
  let px=self.last_close().or_else(||b.hours.last().map(|k|k.c));
  let (gap_from,gap_to)=b.gap;
  for (m,fills) in b.fills {for (k,(buy,sell)) in fills {self.ledger.fill(k,buy,sell,m,px);}}
  for (k,(usd_min,minutes)) in &b.walls {
   if *usd_min<=0.0 {continue}
   let bucket=self.ledger.b.entry(*k).or_default();
   bucket.w+=usd_min;bucket.wm+=minutes;bucket.active=bucket.active.max(gap_to);
   if bucket.role==0 && let Some(p)=px {bucket.role=if p>=ledger::high(*k) {1} else {-1};bucket.pos=bucket.role;}
  }
  for (m,(long,short,price)) in &b.liq {
   if *m>=gap_from&&*m<gap_to {self.ledger.liq(*price,long+short,*m,px);}
  }
  // 触及次数：洞里的历史 K 线（5 分钟线没盖到的更早那段用小时线）。账本还没整段补过（新起跟，或补次数上线前落的盘）
  // 就把次数清零、按账本保留的 7 天历史 K 线整段重数一遍——历史 K 线是完整的，比上一任实时数到的那几段更全，也不会重复算。
  let (replay_from,to)=if self.touches_backfilled {(gap_from,gap_to.min(lf))} else {
   for b in self.ledger.b.values_mut() {b.tests=0;}
   (now-ledger::FORGET_MS,lf.min(now))
  };
  let five_from=b.fives.first().map_or(i64::MAX,|k|k.t);
  let mut bars:Vec<(i64,i64,f64,f64)>=b.hours.iter().filter(|k|k.t>=replay_from&&k.t+HOUR_MS<=five_from.min(to)).map(|k|(k.t,HOUR_MS,k.h,k.l)).collect();
  bars.extend(b.fives.iter().filter(|k|k.t>=replay_from&&k.t+5*M<=to).map(|k|(k.t,5*M,k.h,k.l)));
  self.ledger.replay(&bars);
  self.touches_backfilled=true;
  for (block,bin,n) in &b.sizes {self.sizes.add_n(*block,Some(*bin),*n);}
  let mut seen:std::collections::HashSet<(i64,u64,u64)>=self.ended.iter().map(|e|(e.end,e.price.to_bits(),e.initial.to_bits())).collect();
  for e in b.ended {if seen.insert((e.end,e.price.to_bits(),e.initial.to_bits())) {self.ended.push(e);}}
  self.ended.sort_by_key(|e|e.end);
  self.booted=true;
  self.trim(now);
  self.backfill(now);
 }

 // ------------------------------------------------------------------ 取数

 fn hl(&self)->Vec<Hl> {self.hours.iter().map(|(t,h)|Hl{t:*t,h:h.h,l:h.l,c:h.c}).collect()}
 pub fn atr1h(&self)->Option<f64> {
  let hl:Vec<Hl>=self.hours.iter().rev().take(16).rev().map(|(t,h)|Hl{t:*t,h:h.h,l:h.l,c:h.c}).collect();
  atr(&hl,14)
 }
 pub fn atr4h(&self)->Option<f64> {
  let hl:Vec<Hl>=self.hours.iter().rev().take(4*16).rev().map(|(t,h)|Hl{t:*t,h:h.h,l:h.l,c:h.c}).collect();
  atr(&four_hour(&hl),14)
 }

 /// `t` 那一刻的价：那一刻之前最后一分钟的收；分钟序列里没有就用小时线。
 pub fn close_at(&self,t:i64)->Option<f64> {
  self.px.last_before(0,t-M,15*M).or_else(||self.hours.range(..t).next_back().map(|(_,h)|h.c).filter(|c|*c>0.0))
 }
 fn spot_at(&self,t:i64)->Option<f64> {self.px.last_before(3,t-M,15*M)}
 /// `t` 那一刻的持仓：5 分钟序列里 15 分钟以内的，否则小时序列里 2 小时以内的。
 pub fn oi_at(&self,t:i64)->Option<f64> {
  self.oi5.range(t-15*M..=t).next_back().map(|(_,v)|*v)
   .or_else(||self.oi1h.range(t-2*HOUR_MS..=t).next_back().map(|(_,v)|*v))
 }
 /// 一小时的净主动：分钟序列盖得住就用它，否则用小时线上记的。
 fn hour_net(&self,hour:i64)->f64 {
  if !self.flow.is_empty()&&hour>=self.flow.t0 {self.flow.sum(0,hour,hour+HOUR_MS)}
  else {self.hours.get(&hour).map_or(0.0,|h|h.net)}
 }
 /// `from..to` 的净主动：分钟序列以前的部分按小时线补。
 pub fn net_between(&self,from:i64,to:i64)->f64 {
  let s0=if self.flow.is_empty() {i64::MAX} else {self.flow.t0};
  let mut sum=0.0;
  if from<s0 {
   let stop=to.min(s0);
   let first=from.div_euclid(HOUR_MS)*HOUR_MS;
   sum+=self.hours.range(first..stop).filter(|(h,_)|**h>=from||from-**h<HOUR_MS/2).map(|(_,h)|h.net).sum::<f64>();
  }
  sum+self.flow.sum(0,from.max(s0),to)
 }

 /// 落盘前把分钟序列盖得住的小时的净主动写回小时线（3 天以前的只能靠它）。
 pub fn settle_hours(&mut self) {
  let keys:Vec<i64>=self.hours.keys().copied().filter(|h|!self.flow.is_empty()&&*h>=self.flow.t0).collect();
  for h in keys {let net=self.hour_net(h);if let Some(x)=self.hours.get_mut(&h) {x.net=net;}}
 }

 // ------------------------------------------------------------------ 分位样本

 /// 整点取一次样：窗口都以这个整点为终点。
 fn sample(&mut self,at:i64) {
  // 只在净主动真的盖到窗口起点时取样：REST 补的小时线净额是 0，拿来取样会让 30 天里大半是 0、P60 塌成 0。
  let start=self.flow_start();
  let covered=|from:i64|start.is_some_and(|t|t<=from+FLOW_SLACK_MS);
  if covered(at-15*M)&&at<=self.flow.end() {let v=self.flow.sum(0,at-15*M,at);self.samples.n15.put(at,v);}
  if at<=self.flow.end().max(self.last_bar+M) {
   for (w,which) in [(HOUR_MS,1),(4*HOUR_MS,2),(DAY_MS,3)] {
    if !covered(at-w) {continue}
    let v=self.net_between(at-w,at);
    match which {1=>self.samples.n1h.put(at,v),2=>self.samples.n4h.put(at,v),_=>self.samples.n24.put(at,v)}
   }
  }
  if let (Some(a),Some(b))=(self.oi_at(at-HOUR_MS),self.oi_at(at)) && let Some(x)=pct(a,b) {self.samples.oi.put(at,x);}
  if let (Some(s),Some(p))=(self.spot_at(at),self.close_at(at)) && let Some(x)=pct(p,s) {self.samples.premium.put(at,x);}
 }

 /// 过了整点就取样（漏掉的整点补上）。
 pub fn sample_due(&mut self,now:i64) {
  let hour=now.div_euclid(HOUR_MS)*HOUR_MS;
  if self.sampled==0 {self.sampled=hour-HOUR_MS;}
  let mut at=(self.sampled+HOUR_MS).max(hour-DAY_MS);
  while at<=hour {self.sample(at);at+=HOUR_MS;}
  self.sampled=hour;
 }

 /// 起步后用补回来的历史把 30 天里缺的整点样本补上（已经有的不动）。
 fn backfill(&mut self,now:i64) {
  let hour=now.div_euclid(HOUR_MS)*HOUR_MS;
  let mut at=hour-30*DAY_MS;
  while at<=hour {
   let missing=[&self.samples.n15,&self.samples.n1h,&self.samples.n4h,&self.samples.n24,&self.samples.oi].iter().any(|s|!s.0.contains_key(&at));
   if missing {self.sample(at);}
   at+=HOUR_MS;
  }
  self.sampled=hour;
 }

 // ------------------------------------------------------------------ 算答复

 /// 当日（北京时间）开始的时刻。
 fn day_start(t:i64)->i64 {(t+DAY_OFFSET).div_euclid(DAY_MS)*DAY_MS-DAY_OFFSET}

 fn refs(&self,end:i64,range:Option<Range>)->Vec<Ref> {
  let day=Self::day_start(end);
  let mut out=Vec::new();
  let span=|from:i64,to:i64|{
   let rows:Vec<&Hour>=self.hours.range(from..to).map(|(_,h)|h).collect();
   (!rows.is_empty()).then(||(rows.iter().map(|h|h.h).fold(f64::MIN,f64::max),rows.iter().map(|h|h.l).fold(f64::MAX,f64::min)))
  };
  if let Some((h,l))=span(day,end+HOUR_MS) {out.push(Ref{name:"dayHigh",price:h});out.push(Ref{name:"dayLow",price:l});}
  if let Some((h,l))=span(day-DAY_MS,day) {out.push(Ref{name:"prevDayHigh",price:h});out.push(Ref{name:"prevDayLow",price:l});}
  // VWAP：当日每分钟（高 + 低 + 收）/ 3 按全部成交额加权。
  let (mut pv,mut v)=(0.0,0.0);
  let mut m=day.max(self.px.t0);
  while m<end {
   if let (Some(p),Some(f))=(self.px.get(m),self.flow.get(m)) {
    let tp=(f64::from(p[0])+f64::from(p[1])+f64::from(p[2]))/3.0;
    let vol=f64::from(f[1]);
    if tp.is_finite()&&tp>0.0&&vol>0.0 {pv+=tp*vol;v+=vol;}
   }
   m+=M;
  }
  if v>0.0 {out.push(Ref{name:"vwap",price:pv/v});}
  if let Some(r)=range {out.push(Ref{name:"rangeHigh",price:r.high});out.push(Ref{name:"rangeLow",price:r.low});}
  out
 }

 /// 净主动从哪一刻起连续有数：从最新一分钟往回走，连着超过 [`FLOW_GAP_MINUTES`] 分钟没成交就算断了；
 /// 一直走到分钟序列开头没断，再往前接上紧挨着、净额非 0 的小时线（断一小时就停）。
 /// 库里几天前跟过一阵的足迹（分钟或小时）不能让「4 时」「区间」看起来盖住了；
 /// 刚起跟、库里又没有这只近期足迹时只有这一任收的几分钟，长窗口不能拿它当整窗的净额。
 pub fn flow_start(&self)->Option<i64> {
  let v=&self.flow.v;
  let (mut first,mut zeros,mut whole)=(None,0usize,true);
  for j in (0..v.len()).rev() {
   if v[j][1]>0.0 {first=Some(j);zeros=0;}
   else if first.is_some() {zeros+=1;if zeros>FLOW_GAP_MINUTES {whole=false;break}}
  }
  let mut start=match first {
   Some(j) if !whole=>return Some(self.flow.t0+j as i64*M),
   Some(_)=>self.flow.t0,
   None=>self.hours.iter().rev().find(|(_,h)|h.net!=0.0).map(|(t,_)|*t+HOUR_MS)?,
  };
  loop {
   let h=(start-1).div_euclid(HOUR_MS)*HOUR_MS;
   match self.hours.get(&h) {Some(x) if x.net!=0.0=>start=h,_=>break}
  }
  Some(start)
 }

 fn flow_row(&self,w:&str,from:i64,end:i64,samples:&Samples)->Value {
  let covered=self.flow_start().is_some_and(|t|t<=from+FLOW_SLACK_MS);
  let net=self.net_between(from,end);
  let px=match (self.close_at(from),self.close_at(end)) {(Some(a),Some(b))=>pct(a,b),_=>None};
  let oi=match (self.oi_at(from),self.oi_at(end)) {(Some(a),Some(b))=>pct(a,b),_=>None};
  let floor=samples.abs_quantile(DIVERGE_Q);
  let diverge=match (px,floor) {
   (Some(p),Some(f))=>covered&&net!=0.0&&p!=0.0&&net.signum()!=p.signum()&&net.abs()>=f&&p.abs()>=DIVERGE_PX,
   _=>false,
  };
  let mut row=json!({"w":w,"netUsd":covered.then(||usd(net)),"pxPct":px.map(|v|round(v,2)),"oiPct":oi.map(|v|round(v,2)),"diverge":diverge});
  if w=="range" {row["sinceMs"]=json!(from);}
  row
 }

 /// 墙的规模门槛（近 3 天结束的墙的 P90；不到 50 堵为 0）与全部规模（首页算分位）。
 fn wall_sizes(&self)->(f64,&Sizes) {
  let floor=if self.sizes.count()>=WALL_MIN_SAMPLES {self.sizes.quantile(WALL_Q).unwrap_or(0.0)} else {0.0};
  (floor,&self.sizes)
 }

 fn position(&self,end:i64)->(Value,bool,Option<(&'static str,f64)>) {
  let pct1h=match (self.oi_at(end-HOUR_MS),self.oi_at(end)) {(Some(a),Some(b))=>pct(a,b),_=>None};
  let px1h=match (self.close_at(end-HOUR_MS),self.close_at(end)) {(Some(a),Some(b))=>pct(a,b),_=>None};
  let combo=match (pct1h,px1h) {
   (Some(o),Some(p))=>Some(match (o>=0.0,p>=0.0) {(true,true)=>"oiUpPxUp",(false,true)=>"oiDownPxUp",(true,false)=>"oiUpPxDown",(false,false)=>"oiDownPxDown"}),
   _=>None,
  };
  let oi_p=pct1h.and_then(|v|self.samples.oi.pctile(v));
  let premium=match (self.spot_at(end),self.close_at(end)) {(Some(s),Some(p))=>pct(p,s),_=>None};
  let prem_p=premium.and_then(|v|self.samples.premium.pctile(v));
  let fund_p=self.funding.and_then(|v|self.samples.funding.pctile(v));
  // 等于样本里最常见的那个值（交易所默认费率这类常态）的不算异常，分位照写。
  let flag=|p:Option<u8>,x:Option<f64>,samples:&Samples|p.filter(|_|!x.is_some_and(|x|samples.is_mode(x)));
  let (oi_f,fund_f,prem_f)=(flag(oi_p,pct1h,&self.samples.oi),flag(fund_p,self.funding,&self.samples.funding),flag(prem_p,premium,&self.samples.premium));
  let extreme=|p:Option<u8>|p.is_some_and(|p|p>=EXTREME_HI||p<=EXTREME_LO);
  let show=extreme(oi_f)||extreme(fund_f)||extreme(prem_f);
  // 最极端的那一项（首页分类用）：离 50 最远，只在极端的里挑。
  let strongest=[("oi",oi_f),("funding",fund_f),("funding",prem_f)].into_iter().filter(|(_,p)|extreme(*p)).filter_map(|(c,p)|p.map(|p|(c,(f64::from(p)-50.0).abs()/50.0))).max_by(|a,b|a.1.total_cmp(&b.1));
  let v=json!({"show":show,
   "oi":{"pct1h":pct1h.map(|v|round(v,2)),"combo":combo,"pctile":oi_p},
   "funding":{"rate":self.funding,"pctile":fund_p},
   "spotPremium":{"pct":premium.map(|v|round(v,3)),"pctile":prem_p}});
  (v,show,strongest)
 }

 fn events(&self,end:i64,wall_floor:f64)->Vec<Ev> {
  let since=end-events::WINDOW_MS;
  let mut all=Vec::new();
  if !self.flow.is_empty() {
   let t0=self.flow.t0;
   let span_px=|from:i64,to:i64|match (self.close_at(from),self.close_at(to)) {(Some(a),Some(b))=>pct(a,b),_=>None};
   let net:Vec<f64>=self.flow.v.iter().map(|r|f64::from(r[0])).collect();
   let slides=events::sliding(&net);
   if let Some(thr)=events::threshold(&slides) {
    let abs:Vec<f64>=slides.iter().map(|s|s.abs()).collect();
    for s in events::spans(t0,&net,thr,since) {
     all.push(Ev::Flow{from:s.from,to:s.to,net:s.sum,px_pct:span_px(s.from,s.to),pctile:rank(&abs,s.peak).unwrap_or(95)});
    }
   }
   let liq:Vec<f64>=self.flow.v.iter().map(|r|f64::from(r[2])+f64::from(r[3])).collect();
   let slides=events::sliding(&liq);
   if let Some(thr)=events::threshold(&slides) {
    let abs:Vec<f64>=slides.iter().map(|s|s.abs()).collect();
    for s in events::spans(t0,&liq,thr,since) {
     let long=self.flow.sum(2,s.from,s.to)>=self.flow.sum(3,s.from,s.to);
     all.push(Ev::Liq{from:s.from,to:s.to,usd:s.sum,long,px_pct:span_px(s.from,s.to),pctile:rank(&abs,s.peak).unwrap_or(95)});
    }
   }
  }
  for (first,at,p) in events::oi_jumps(&self.oi5,since) {all.push(Ev::Oi{first,at,pct:p});}
  all.extend(events::wall_events(&self.ended,|t|self.close_at(t+M),wall_floor,since));
  all.extend(events::broken_events(&self.broken));
  events::newest(all,end)
 }

 /// 近 3 天有爆仓的分钟里，每分钟爆仓额的中位数（价位上的爆仓段要过它才显示）；值太单一为 None。
 fn liq_minute_p50(&self)->Option<f64> {
  quantile_distinct(self.flow.v.iter().map(|r|f64::from(r[2])+f64::from(r[3])).filter(|v|*v>0.0).collect(),0.5)
 }

 fn level_json(v:&ledger::Level)->Value {
  json!({"id":format!("L:{}",v.k),"low":sig(v.low),"high":sig(v.high),"side":if v.bid {"bid"} else {"ask"},"distPct":round(v.dist_pct,2),
   "wallUsd":usd(v.wall_usd),"wallHeldMs":v.wall_held_ms,"wallState":v.wall_state,
   "fillBuyUsd":usd(v.fill_buy),"fillSellUsd":usd(v.fill_sell),"liqUsd":usd(v.liq),"tests":v.tests,
   "touchMs":[v.touch.0,v.touch.1],"refs":v.refs})
 }

 /// 这一分钟的答复。`tracked` 是注册表此刻在不在跟。
 pub fn compute(&mut self,now:i64,tracked:bool)->Snap {
  let end=if self.last_bar>0 {self.last_bar+M} else {now.div_euclid(M)*M};
  let reference=if self.last_bar>0 {end} else {self.created};
  let stale=(now-reference>STALE_MS&&(self.last_bar>0||self.booted)).then_some(now-reference);
  let price=self.close_at(end+M).or_else(||self.last_close());
  let atr4h=self.atr4h();
  let range=range::detect(&self.hl(),atr4h,end);
  let mut rows=vec![
   self.flow_row("15m",end-15*M,end,&self.samples.n15),
   self.flow_row("1h",end-HOUR_MS,end,&self.samples.n1h),
   self.flow_row("4h",end-4*HOUR_MS,end,&self.samples.n4h),
  ];
  rows.push(match range {
   Some(r)=>self.flow_row("range",r.since_ms,end,if end-r.since_ms>=12*HOUR_MS {&self.samples.n24} else {&self.samples.n4h}),
   None=>self.flow_row("24h",end-DAY_MS,end,&self.samples.n24),
  });
  let range_json=range.map(|r|{
   let edge=(r.high-r.low)*0.15;
   let (low_fill,low_tests)=self.ledger.edge(r.low,r.low+edge);
   let (high_fill,high_tests)=self.ledger.edge(r.high-edge,r.high);
   json!({"low":sig(r.low),"high":sig(r.high),"sinceMs":r.since_ms,"lowFillUsd":usd(low_fill),"lowTests":low_tests,"highFillUsd":usd(high_fill),"highTests":high_tests})
  });
  let refs=self.refs(end,range);
  let (wall_floor,_)=self.wall_sizes();
  let liq_floor=self.liq_minute_p50();
  let mut levels=price.map(|p|self.ledger.levels(p,atr4h,&self.live,&refs,now)).unwrap_or_default();
  for v in &mut levels {trim_segments(v,liq_floor,wall_floor);}
  let (position,show,strongest)=self.position(end);
  // 同一类极端一直在，`atMs` 就停在它开始的那一分钟。
  self.position_since=match (show,strongest,self.position_since) {
   (true,Some((cat,_)),Some((was,since))) if was==cat=>Some((cat,since)),
   (true,Some((cat,_)),_)=>Some((cat,end)),
   _=>None,
  };
  let position_at=self.position_since.map_or(end,|(_,t)|t);
  let (wall_floor,sizes)=self.wall_sizes();
  let evs=if price.is_some() {self.events(end,wall_floor)} else {Vec::new()};
  let p=price.unwrap_or(0.0);
  let observing=self.observing_since.filter(|t|now-t<events::WINDOW_MS);
  let json=json!({"base":self.base,"generatedAtMs":now,"tracked":tracked,"staleMs":stale,"observingSinceMs":observing,"partial":false,
   "flow":{"rows":rows},"range":range_json,
   "levels":levels.iter().map(Self::level_json).collect::<Vec<_>>(),
   "position":position,
   "events":evs.iter().map(|e|e.json(p)).collect::<Vec<_>>()});
  let board=self.board_item(now,p,&levels,&evs,show,strongest,&position,position_at,wall_floor,sizes);
  let change_pct=match (self.close_at(end-DAY_MS),price) {(Some(a),Some(b))=>pct(a,b).map(|v|round(v,2)),_=>None};
  Snap{json,board,price:price.map(sig),change_pct}
 }

 /// 首页那一行：每条要点的权重 = 规模分位 × 近度 × 叠加系数（只用于排序）。
 #[allow(clippy::too_many_arguments)]
 fn board_item(&self,now:i64,price:f64,levels:&[ledger::Level],evs:&[Ev],show:bool,strongest:Option<(&'static str,f64)>,position:&Value,position_at:i64,wall_floor:f64,sizes:&Sizes)->Option<BoardItem> {
  let recency=|at:i64|recency(now,at);
  let size=|usd:f64|if sizes.count()>=WALL_MIN_SAMPLES {sizes.rank(usd).map_or(0.9,|r|f64::from(r)/100.0)} else {0.9};
  let mut items:Vec<(f64,&'static str,Value,i64)>=Vec::new();
  for e in evs {
   let (s,cat)=match e {
    Ev::Flow{pctile,..}|Ev::Liq{pctile,..}=>(f64::from(*pctile)/100.0,"book"),
    Ev::Wall{usd,..}=>(size(*usd),"book"),
    Ev::Oi{pct,..}=>((pct.abs()/5.0).clamp(0.5,1.0),"oi"),
    Ev::Broken{..}=>(0.8,"book"),
   };
   let mut top=e.json(price);
   top["kind"]=json!("event");
   items.push((s*recency(e.time()),cat,top,e.time()));
  }
  for v in levels.iter().filter(|v|v.wall_usd>0.0&&v.wall_usd>=wall_floor&&v.dist_pct.abs()<=BOARD_LEVEL_DIST&&matches!(v.wall_state,Some("live")|Some("reducing"))) {
   let mut top=Self::level_json(v);
   top["kind"]=json!("level");
   // 时刻 = 这堵墙最早挂出来的那一刻（没有就是最后一次触及），不是这一分钟。
   let at=v.wall_first.or(v.touch.1).unwrap_or(now);
   items.push((size(v.wall_usd)*(1.0+0.25*v.refs.len() as f64),"book",top,at));
  }
  if show && let Some((cat,s))=strongest {
   let mut top=position.clone();
   top["kind"]=json!("position");
   items.push((s,cat,top,position_at));
  }
  let count=items.len();
  let (weight,cat,top,at)=items.into_iter().max_by(|a,b|a.0.total_cmp(&b.0))?;
  Some(BoardItem{count,cat,top,weight,at})
 }

 // ------------------------------------------------------------------ 落盘

 pub fn payload(&self)->Value {
  let ledger:Vec<Value>=self.ledger.b.iter().map(|(k,b)|json!([k,b.w,b.wm,b.fb,b.fs,b.lq,b.tests,b.first,b.last,b.active,b.role,b.pos,b.broken])).collect();
  let s=&self.samples;
  let pairs=|x:&Samples|x.pairs().into_iter().map(|(t,v)|json!([t,v])).collect::<Vec<_>>();
  json!({"v":1,"until":self.until,"tb":self.touches_backfilled,"ledger":ledger,
   "samples":{"n15":pairs(&s.n15),"n1h":pairs(&s.n1h),"n4h":pairs(&s.n4h),"n24":pairs(&s.n24),"oi":pairs(&s.oi),"funding":pairs(&s.funding),"premium":pairs(&s.premium)},
   "hours":self.hours.iter().map(|(t,h)|json!([t,h.o,h.h,h.l,h.c,h.net])).collect::<Vec<_>>(),
   "oi1h":self.oi1h.iter().map(|(t,v)|json!([t,v])).collect::<Vec<_>>()})
 }

 /// 读回落盘的那份（版本不对或坏了回 None，从头攒）。
 pub fn restore(base:&str,v:&Value,now:i64)->Option<Self> {
  if v["v"].as_i64()!=Some(1) {return None}
  let mut s=Self::new(base,now);
  s.until=v["until"].as_i64()?;
  s.touches_backfilled=v["tb"].as_bool().unwrap_or(false);
  let f=|x:&Value|x.as_f64();
  let i=|x:&Value|x.as_i64();
  for r in v["ledger"].as_array()? {
   let r=r.as_array()?;
   if r.len()<13 {continue}
   s.ledger.b.insert(i(&r[0])?,ledger::Bucket{w:f(&r[1])?,wm:f(&r[2])?,fb:f(&r[3])?,fs:f(&r[4])?,lq:f(&r[5])?,tests:r[6].as_u64()? as u32,
    first:i(&r[7]),last:i(&r[8]),active:i(&r[9])?,role:i(&r[10])? as i8,pos:i(&r[11])? as i8,beyond:None,broken:r[12].as_bool()?});
  }
  let pairs=|x:&Value|->Samples {Samples::from_pairs(&x.as_array().map(|a|a.iter().filter_map(|p|Some((p[0].as_i64()?,p[1].as_f64()? as f32))).collect::<Vec<_>>()).unwrap_or_default())};
  let sm=&v["samples"];
  // 净主动样本里的 0 是 10-10 第一版拿 REST 小时线（净额 0）取的，读回时丢掉。
  let nets=|x:&Value|{let mut p=pairs(x);p.0.retain(|_,v|*v!=0.0);p};
  s.samples=Sampled{n15:nets(&sm["n15"]),n1h:nets(&sm["n1h"]),n4h:nets(&sm["n4h"]),n24:nets(&sm["n24"]),oi:pairs(&sm["oi"]),funding:pairs(&sm["funding"]),premium:pairs(&sm["premium"])};
  for r in v["hours"].as_array()? {
   let (Some(t),Some(o),Some(h),Some(l),Some(c),Some(net))=(i(&r[0]),f(&r[1]),f(&r[2]),f(&r[3]),f(&r[4]),f(&r[5])) else {continue};
   s.hours.insert(t,Hour{o,h,l,c,net});
  }
  for r in v["oi1h"].as_array()? {if let (Some(t),Some(x))=(i(&r[0]),f(&r[1])) {s.oi1h.insert(t,x);}}
  s.trim(now);
  s.ledger.expire(now);
  Some(s)
 }
}

#[cfg(test)]
mod tests {
 use super::*;

 const T0:i64=1_790_000_000_000-1_790_000_000_000%HOUR_MS;

 fn flat_state(minutes:i64,price:f64)->State {
  let mut s=State::new("TEST",T0);
  let mut p=Pending::default();
  for m in 0..minutes {
   let t=T0+m*M;
   p.bars.push(Bar{t,o:price,h:price*1.0005,l:price*0.9995,c:price,spot:Some(price*1.0001)});
   p.flow.insert(t,(1000.0,5000.0));
  }
  s.fold(p,T0+minutes*M);
  s
 }

 #[test]
 fn series_grows_trims_and_prepends() {
  let mut s:Series<1>=Series::new(10,0.0);
  s.slot(5*M).unwrap()[0]=1.0;
  s.slot(2*M).unwrap()[0]=2.0;
  assert_eq!(s.t0,2*M);
  s.slot(14*M).unwrap()[0]=3.0;
  assert_eq!(s.v.len(),10);
  assert_eq!(s.t0,5*M);
  assert_eq!(s.sum(0,0,100*M),4.0);
  assert!(s.slot(0).is_none(),"older than the window");
  s.slot(1000*M).unwrap()[0]=9.0;
  assert_eq!((s.t0,s.v.len()),(1000*M,1),"a jump past the window starts over");
 }

 #[test]
 fn divergence_needs_opposite_signs_size_and_half_a_percent() {
  let mut s=flat_state(90,100.0);
  // 近 4 天的 1 时样本：|净主动| 0..100 万。
  for h in 0..96 {s.samples.n1h.put(T0-h*HOUR_MS,(h as f64)*10_000.0);}
  // 最后一小时：大量净卖出、价格涨 1%。
  let mut p=Pending::default();
  for m in 90..150 {
   let t=T0+m*M;
   let px=100.0*(1.0+0.01*(m-90) as f64/60.0);
   p.bars.push(Bar{t,o:px,h:px,l:px,c:px,spot:None});
   p.flow.insert(t,(-50_000.0,60_000.0));
  }
  s.fold(p,T0+150*M);
  let end=s.last_bar+M;
  let row=s.flow_row("1h",end-HOUR_MS,end,&s.samples.n1h);
  assert_eq!(row["diverge"],json!(true),"{row}");
  // 同样的净卖出、价格只动 0.3%：不标。
  let mut quiet=flat_state(90,100.0);
  quiet.samples=s.samples.clone();
  let mut p=Pending::default();
  for m in 90..150 {let t=T0+m*M;let px=100.0+0.3*(m-90) as f64/60.0;p.bars.push(Bar{t,o:px,h:px,l:px,c:px,spot:None});p.flow.insert(t,(-50_000.0,60_000.0));}
  quiet.fold(p,T0+150*M);
  let end=quiet.last_bar+M;
  assert_eq!(quiet.flow_row("1h",end-HOUR_MS,end,&quiet.samples.n1h)["diverge"],json!(false));
  // 历史不够 3 天：P60 为 null，不标。
  let mut young=flat_state(90,100.0);
  for h in 0..24 {young.samples.n1h.put(T0-h*HOUR_MS,1.0);}
  let mut p=Pending::default();
  for m in 90..150 {let t=T0+m*M;let px=100.0*(1.0+0.01*(m-90) as f64/60.0);p.bars.push(Bar{t,o:px,h:px,l:px,c:px,spot:None});p.flow.insert(t,(-50_000.0,60_000.0));}
  young.fold(p,T0+150*M);
  let end=young.last_bar+M;
  assert_eq!(young.flow_row("1h",end-HOUR_MS,end,&young.samples.n1h)["diverge"],json!(false));
 }

 #[test]
 fn compute_has_the_contract_shape_with_insufficient_history() {
  let mut s=flat_state(300,50_000.0);
  let snap=s.compute(T0+300*M+5_000,true);
  let j=&snap.json;
  assert_eq!(j["base"],"TEST");
  assert_eq!(j["tracked"],true);
  assert_eq!(j["staleMs"],Value::Null);
  let rows=j["flow"]["rows"].as_array().unwrap();
  assert_eq!(rows.len(),4);
  assert_eq!(rows[0]["w"],"15m");
  assert_eq!(rows[0]["netUsd"],json!(15_000.0));
  assert_eq!(rows[3]["w"],"24h","five hours of box is shorter than six");
  assert_eq!(rows[2]["netUsd"],json!(240_000.0),"four hours of flow cover the 4h row");
  assert_eq!(rows[3]["netUsd"],Value::Null,"five hours of flow do not cover a day: no partial sum");
  assert_eq!(rows[3]["diverge"],false);
  assert_eq!(j["position"]["oi"]["pctile"],Value::Null);
  assert_eq!(j["position"]["show"],false);
  assert!(j["events"].as_array().unwrap().is_empty());
  assert_eq!(snap.price,Some(50_000.0));
 }

 #[test]
 fn flow_coverage_stops_at_the_first_gap() {
  let mut s=flat_state(20,10.0);
  assert_eq!(s.flow_start(),Some(T0));
  let hour=|net:f64|Hour{o:10.0,h:10.0,l:10.0,c:10.0,net};
  s.hours.insert(T0-HOUR_MS,hour(5.0));
  s.hours.insert(T0-2*HOUR_MS,hour(-3.0));
  assert_eq!(s.flow_start(),Some(T0-2*HOUR_MS),"footprint hours right before the minutes extend coverage");
  s.hours.insert(T0-3*HOUR_MS,hour(0.0));
  s.hours.insert(T0-30*HOUR_MS,hour(7.0));
  assert_eq!(s.flow_start(),Some(T0-2*HOUR_MS),"a REST hour without direction or an older stretch after a gap does not");
  let j=s.compute(T0+20*M+5_000,true).json;
  let rows=j["flow"]["rows"].as_array().unwrap();
  assert_eq!(rows[0]["netUsd"],json!(15_000.0));
  assert_eq!(rows[1]["netUsd"],json!(20_000.0+5.0),"1h reaches back into the hour it mostly covers");
  assert_eq!(rows[2]["netUsd"],Value::Null,"4h starts before the gap");
 }

 #[test]
 fn flow_coverage_stops_at_a_gap_inside_the_minutes() {
  let mut s=flat_state(20,10.0);
  let mut p=Pending::default();
  for m in 100..130 {
   let t=T0+m*M;
   p.bars.push(Bar{t,o:10.0,h:10.0,l:10.0,c:10.0,spot:None});
   p.flow.insert(t,(1000.0,5000.0));
  }
  s.fold(p,T0+130*M);
  s.hours.insert(T0-HOUR_MS,Hour{o:10.0,h:10.0,l:10.0,c:10.0,net:5.0});
  assert_eq!(s.flow_start(),Some(T0+100*M),"an old stretch before an 80-minute hole does not count");
  let j=s.compute(T0+130*M+5_000,true).json;
  let rows=j["flow"]["rows"].as_array().unwrap();
  assert_eq!(rows[0]["netUsd"],json!(15_000.0));
  assert_eq!(rows[1]["netUsd"],Value::Null);
 }

 #[test]
 fn event_ids_are_unique_and_the_same_on_every_recompute() {
  let mut s=flat_state(300,100.0);
  let k=ledger::key(99.0);
  // 一根大阴线同一分钟连破两格、下一分钟再破一格；两堵不同价的墙在同一毫秒被吃穿。
  s.broken=vec![Broke{k,at:T0+200*M,was_support:true},Broke{k:k+1,at:T0+200*M,was_support:true},Broke{k:k-1,at:T0+201*M,was_support:true}];
  let eaten=|price:f64|Ended{bid:false,price,initial:2e6,filled:2e6,left:0.0,cancelled:false,end:T0+250*M+123};
  s.ended=vec![eaten(100.5),eaten(101.0)];
  let ids=|s:&mut State,now:i64|{
   let snap=s.compute(now,true);
   (snap.json["events"].as_array().unwrap().iter().map(|e|(e["id"].as_str().unwrap().to_string(),e["t"].as_str().unwrap().to_string())).collect::<Vec<_>>(),snap.board.map(|b|b.at))
  };
  let (first,at1)=ids(&mut s,T0+300*M+5_000);
  let (again,at2)=ids(&mut s,T0+303*M+5_000);
  let unique:std::collections::HashSet<&String>=first.iter().map(|(id,_)|id).collect();
  assert_eq!(unique.len(),first.len(),"{first:?}");
  assert_eq!(first.iter().filter(|(_,t)|t=="levelBroken").count(),1,"three buckets of one level broke: one event, not re-emitted");
  assert_eq!(first.iter().filter(|(_,t)|t=="wallEaten").count(),2);
  assert_eq!(first,again,"same data, same ids");
  assert_eq!(at1,at2);
  assert_eq!(at1,Some(T0+250*M+123),"atMs is the fact's time, not the recompute's");
 }

 #[test]
 fn position_at_is_when_the_extreme_started_and_the_mode_is_never_extreme() {
  let mut s=flat_state(300,100.0);
  // 30 天费率：600 个零散的低值 + 120 个交易所默认值（默认值排在 P92，但它是常态）。
  for i in 0..720 {
   let v=if i<600 {f64::from(i)*5e-8} else {5e-5};
   s.samples.funding.put(T0-(720-i64::from(i))*HOUR_MS,v);
  }
  s.funding=Some(5e-5);
  let snap=s.compute(T0+300*M+5_000,true);
  assert!(snap.json["position"]["funding"]["pctile"].as_u64().unwrap()>=90);
  assert_eq!(snap.json["position"]["show"],false,"the default rate is the mode: not flagged");
  assert!(snap.board.is_none());
  s.funding=Some(0.01);
  let a=s.compute(T0+300*M+5_000,true).board.unwrap();
  assert_eq!((a.cat,a.at),("funding",T0+300*M));
  let mut p=Pending::default();
  p.bars.push(Bar{t:T0+300*M,o:100.0,h:100.0,l:100.0,c:100.0,spot:None});
  s.fold(p,T0+301*M);
  let b=s.compute(T0+301*M+5_000,true).board.unwrap();
  assert_eq!(b.at,T0+300*M,"still the minute it became extreme");
 }

 #[test]
 fn level_segments_below_their_floor_are_zeroed() {
  let level=|wall:f64,fill:f64,liq:f64|ledger::Level{k:0,low:1.0,high:1.01,bid:true,dist_pct:-1.0,wall_usd:wall,wall_held_ms:0,
   wall_state:Some("live"),wall_first:Some(1),fill_buy:fill,fill_sell:fill*0.01,liq,tests:3,touch:(None,None),refs:vec![],weight:1.0};
  let mut v=level(103_000.0,4_300_000.0,456.0);
  trim_segments(&mut v,Some(20_000.0),50_000.0);
  assert_eq!((v.wall_usd,v.liq,v.fill_sell),(103_000.0,0.0,0.0),"wall passes its P90, liq is noise, a 1% fill side is noise");
  let mut v=level(50_000.0,4_300_000.0,200_000.0);
  trim_segments(&mut v,Some(20_000.0),200_000.0);
  assert_eq!((v.wall_usd,v.wall_state,v.liq),(0.0,None,200_000.0),"small wall below both floors goes; liq above both stays");
  let mut v=level(0.0,1_000_000.0,15_000.0);
  trim_segments(&mut v,Some(20_000.0),0.0);
  assert_eq!(v.liq,0.0,"below the symbol's own liquidation-minute median");
 }

 #[test]
 fn touches_are_recounted_once_for_ledgers_saved_before_the_backfill() {
  let mut s=flat_state(10,100.0);
  let k=ledger::key(99.0);
  let mut b=Boot{gap:(T0-HOUR_MS,T0),..Boot::default()};
  b.walls.insert(k,(600.0,10.0));
  b.hours=vec![K{t:T0-30*HOUR_MS,o:100.0,h:100.0,l:98.9,c:100.0},K{t:T0-20*HOUR_MS,o:100.0,h:100.0,l:98.9,c:100.0},K{t:T0-2*HOUR_MS,o:100.0,h:100.0,l:99.5,c:100.0}];
  s.apply(b,T0+10*M);
  assert!(s.touches_backfilled);
  assert_eq!(s.ledger.b[&k].tests,2,"both touches a day and more back count, not only the gap");
  // 下一任：落过盘带着标记，只补洞，不重复数。
  let mut again=State::restore("TEST",&s.payload(),T0+20*M).unwrap();
  assert!(again.touches_backfilled);
  let mut b=Boot{gap:(T0+10*M,T0+20*M),..Boot::default()};
  b.hours=vec![K{t:T0-30*HOUR_MS,o:100.0,h:100.0,l:98.9,c:100.0}];
  again.apply(b,T0+20*M);
  assert_eq!(again.ledger.b[&k].tests,2);
  // 标记之前落的盘：次数清零按历史重数（不会在原来的基础上再加）。
  let mut legacy=State::restore("TEST",&s.payload(),T0+20*M).unwrap();
  legacy.touches_backfilled=false;
  let mut b=Boot{gap:(T0+10*M,T0+20*M),..Boot::default()};
  b.hours=vec![K{t:T0-30*HOUR_MS,o:100.0,h:100.0,l:98.9,c:100.0}];
  legacy.apply(b,T0+20*M);
  assert_eq!(legacy.ledger.b[&k].tests,1);
 }

 #[test]
 fn payload_round_trips() {
  let mut s=flat_state(120,10.0);
  s.ledger.walls(T0,&[Live{bid:true,price:9.9,usd:1e6,initial:1e6,filled:0.0,first:T0}],Some(10.0));
  s.samples.funding.put(T0,0.0001);
  s.settle_hours();
  let back=State::restore("TEST",&s.payload(),T0+120*M).unwrap();
  assert_eq!(back.ledger,s.ledger);
  assert_eq!(back.samples.funding,s.samples.funding);
  assert_eq!(back.hours.len(),2);
  assert_eq!(back.hours[&T0].net,60.0*1000.0);
  assert!(State::restore("TEST",&json!({"v":2}),T0).is_none());
 }

 #[test]
 fn boot_history_only_fills_before_live_minutes() {
  let mut s=flat_state(10,100.0);
  let mut b=Boot{gap:(T0-HOUR_MS,T0),..Boot::default()};
  b.flow.insert(T0-M,(7.0,7.0));
  b.flow.insert(T0+M,(999.0,999.0));
  b.fills.push((T0-2*M,[(ledger::key(99.0),(5.0,1.0))].into_iter().collect()));
  b.walls.insert(ledger::key(98.0),(600.0,10.0));
  s.apply(b,T0+10*M);
  assert_eq!(s.flow.get(T0-M).map(|r|r[0]),Some(7.0));
  assert_eq!(s.flow.get(T0+M).map(|r|r[0]),Some(1000.0),"live minutes are not overwritten");
  assert_eq!(s.ledger.b[&ledger::key(99.0)].fb,5.0);
  assert_eq!(s.ledger.b[&ledger::key(98.0)].w,600.0);
  assert_eq!(s.ledger.b[&ledger::key(98.0)].role,1);
  assert!(s.booted);
 }
}
