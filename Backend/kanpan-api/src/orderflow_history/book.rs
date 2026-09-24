//! 一本簿：照 KanpanCore 的 `LocalBook.swift` 与 `VenueBook.swift` 逐条移植。
//!
//! * 四种序列规则：币安现货 `U/u`（rangeOverlap）、币安合约 `U/u/pu`（previousFinalOverlap）、
//!   OKX `seqId/prevSeqId`（previousFinalExact）、Coinbase 整条连接的 `sequence_num`（strictIncrementing）。
//! * 快照不在流里的（币安）先缓冲增量、等 REST 快照对上序号；快照在流里的（OKX、Coinbase）收到首帧就绪。
//! * 本地只留中间价两侧扫描半径两倍以内的价位（`RETAIN_BPS`）。
//! * 价与量进来时已经换成「每个币」的口径（币安 `1000PEPE` 这种除掉缩放），名义美元不变。
//!
//! 和手机那份的差别只有一处：连接代号的核对放在上一层（`VenueBook`），旧连接的迟到帧在进簿之前就丢了。
use super::model::{Notional,SCAN_RADIUS_BPS};
use std::collections::{BTreeMap,BTreeSet,HashMap,VecDeque};

/// 本地簿留中间价两侧多远（扫描半径的两倍）。
pub const RETAIN_BPS:f64=2.0*SCAN_RADIUS_BPS;
/// 等快照时最多缓冲几条增量。
pub const BUFFER:usize=5_000;

#[derive(Clone,Copy,Debug,PartialEq,Eq,Hash,PartialOrd,Ord)]
pub enum Side {Bid,Ask}
impl Side {
 pub fn wire(self)->&'static str {match self {Side::Bid=>"bid",Side::Ask=>"ask"}}
 pub fn parse(text:&str)->Option<Self> {match text {"bid"=>Some(Side::Bid),"ask"=>Some(Side::Ask),_=>None}}
}

#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum Sequence {RangeOverlap,PreviousFinalOverlap,PreviousFinalExact,StrictIncrementing}

pub type Level=(f64,f64);

#[derive(Clone,Debug,Default,PartialEq)]
pub struct Snapshot {pub last:i64,pub requested:usize,pub bids:Vec<Level>,pub asks:Vec<Level>}

#[derive(Clone,Debug,Default,PartialEq)]
pub struct Delta {pub first:i64,pub last:i64,pub prev:Option<i64>,pub bids:Vec<Level>,pub asks:Vec<Level>}

/// 一笔主动成交：`hit` 是被吃掉的那一侧（主动卖吃买单 = Bid）。
#[derive(Clone,Copy,Debug,PartialEq)]
pub struct Trade {pub price:f64,pub quantity:f64,pub hit:Side}

/// 解出来的一条簿消息（照 `DepthMessage`；成交不走这里，见 `Model::trade`）。
#[derive(Clone,Debug,PartialEq)]
pub enum Message {Snapshot(Snapshot),Delta(Delta),Reset}

#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum Quality {Bootstrapping,Ready,Resyncing,Gapped}

/// 接不上了：簿已清空、标成断档。
#[derive(Debug,PartialEq,Eq)]
pub struct Gap;

/// 一侧的价位。正的有限浮点数按位比较与按值比较同序，所以用位做键、拿有序表取最优价。
///
/// 快照被截断时（币安 REST 只给 1000 档，BTC 现货合起来才盘口两侧 0.3%），比快照最远一档还远的价位
/// 本地并不知道有没有：`extent` 记快照最远那一档，`touched` 记此后增量推过的价位（含推成 0 的）。
/// 覆盖范围以内「表里没有」就是没有；以外的只有推过的才算知道。快照完整（返回的档数不到要的数、
/// 或者流里整本推来）时 `extent` 是 None，整侧都算知道。
#[derive(Clone,Debug,Default)]
struct Levels {map:BTreeMap<u64,f64>,extent:Option<f64>,touched:BTreeSet<u64>}
impl Levels {
 fn set(&mut self,price:f64,quantity:f64) {if quantity==0.0 {self.map.remove(&price.to_bits());} else {self.map.insert(price.to_bits(),quantity);}}
 fn touch(&mut self,price:f64) {if self.extent.is_some() {self.touched.insert(price.to_bits());}}
 fn best_bid(&self)->Option<f64> {self.map.last_key_value().map(|(k,_)|f64::from_bits(*k))}
 fn best_ask(&self)->Option<f64> {self.map.first_key_value().map(|(k,_)|f64::from_bits(*k))}
 /// 丢掉低于 `floor` 的。
 fn keep_from(&mut self,floor:f64) {self.map=self.map.split_off(&floor.to_bits());self.touched=self.touched.split_off(&floor.to_bits());}
 /// 丢掉高于 `ceiling` 的。
 fn keep_to(&mut self,ceiling:f64) {let _=self.map.split_off(&(ceiling.to_bits()+1));let _=self.touched.split_off(&(ceiling.to_bits()+1));}
 fn clear(&mut self) {self.map.clear();self.extent=None;self.touched.clear();}
 /// 这一档本地知不知道：覆盖范围以内都知道，以外的只有增量推过的才知道。`far_is_low`：买盘越远价越低。
 fn knows(&self,price:f64,far_is_low:bool)->bool {
  match self.extent {
   None=>true,
   Some(e)=>(if far_is_low {price>=e} else {price<=e})||self.touched.contains(&price.to_bits()),
  }
 }
}

/// 快照这一侧的覆盖范围：返回的档数够到要的数就可能被截断，最远那一档以外不算知道。
fn extent(levels:&[Level],requested:usize,far_is_low:bool)->Option<f64> {
 if levels.len()<requested {return None}
 let prices=levels.iter().filter(|(p,_)|p.is_finite()&&*p>0.0).map(|(p,_)|*p);
 if far_is_low {prices.reduce(f64::min)} else {prices.reduce(f64::max)}
}

#[derive(Clone,Debug)]
pub struct LocalBook {
 sequence:Sequence,
 pub quality:Quality,
 last:Option<i64>,
 bids:Levels,
 asks:Levels,
 retained:Option<(f64,f64)>,
}

impl LocalBook {
 pub fn new(sequence:Sequence)->Self {Self{sequence,quality:Quality::Bootstrapping,last:None,bids:Levels::default(),asks:Levels::default(),retained:None}}

 /// REST 快照对缓冲增量。`Ok(true)` 就绪，`Ok(false)` 还没有能接上的增量（等）。
 pub fn bootstrap(&mut self,s:&Snapshot,buffered:&VecDeque<Delta>)->Result<bool,Gap> {
  self.quality=Quality::Bootstrapping;
  self.last=Some(s.last);
  if s.requested==0||s.bids.len()>s.requested||s.asks.len()>s.requested {return self.fail()}
  self.bids.clear();self.asks.clear();self.retained=None;
  write(&s.bids,&mut self.bids,None);write(&s.asks,&mut self.asks,None);
  self.bids.extent=extent(&s.bids,s.requested,true);self.asks.extent=extent(&s.asks,s.requested,false);
  self.check_not_crossed()?;
  self.trim_far();
  let l=s.last;
  let found=match self.sequence {
   Sequence::PreviousFinalOverlap=>buffered.iter().position(|d|d.last>=l),
   _=>buffered.iter().position(|d|d.last>l),
  };
  let Some(index)=found else {return Ok(false)};
  let first=&buffered[index];
  let overlaps=match self.sequence {
   Sequence::RangeOverlap=>first.prev.is_none()&&first.first<=l+1&&first.last>=l+1,
   Sequence::PreviousFinalOverlap=>first.prev.is_some()&&first.first<=l&&first.last>=l,
   Sequence::PreviousFinalExact=>first.prev==Some(l),
   Sequence::StrictIncrementing=>first.prev.is_none()&&first.last==l+1,
  };
  if !overlaps {return self.fail()}
  self.apply_levels(first);
  self.last=Some(first.last);
  self.quality=Quality::Ready;
  self.check_not_crossed()?;
  for d in buffered.iter().skip(index+1) {self.apply(d)?;}
  Ok(true)
 }

 /// 就绪之后的增量。重复的（序号不前进）忽略。
 pub fn apply(&mut self,d:&Delta)->Result<(),Gap> {
  if self.quality!=Quality::Ready {return Err(Gap)}
  let Some(previous)=self.last else {return Err(Gap)};
  if d.last<=previous {return Ok(())}
  let chained=match self.sequence {
   Sequence::RangeOverlap=>d.prev.is_none()&&d.first<=previous+1&&d.last>=previous+1,
   Sequence::PreviousFinalOverlap|Sequence::PreviousFinalExact=>d.prev==Some(previous),
   Sequence::StrictIncrementing=>d.prev.is_none()&&d.first==previous+1&&d.last==d.first,
  };
  if !chained {return self.fail()}
  self.apply_levels(d);
  self.last=Some(d.last);
  self.check_not_crossed()
 }

 /// 流内权威快照：整本替换，立即就绪。
 pub fn replace(&mut self,s:&Snapshot)->Result<(),Gap> {
  if let Some(previous)=self.last&&s.last<previous {return self.fail()}
  if s.requested==0||s.bids.len()>s.requested||s.asks.len()>s.requested {return self.fail()}
  self.begin_resync();
  write(&s.bids,&mut self.bids,None);write(&s.asks,&mut self.asks,None);
  self.bids.extent=extent(&s.bids,s.requested,true);self.asks.extent=extent(&s.asks,s.requested,false);
  self.last=Some(s.last);
  self.quality=Quality::Ready;
  self.check_not_crossed()?;
  self.trim_far();
  Ok(())
 }

 pub fn begin_resync(&mut self) {
  self.quality=Quality::Resyncing;self.last=None;
  self.bids.clear();self.asks.clear();self.retained=None;
 }

 pub fn mark_gapped(&mut self) {
  self.quality=Quality::Gapped;self.last=None;
  self.bids.clear();self.asks.clear();self.retained=None;
 }

 fn fail<T>(&mut self)->Result<T,Gap> {self.mark_gapped();Err(Gap)}

 fn check_not_crossed(&mut self)->Result<(),Gap> {
  if let (Some(bid),Some(ask))=(self.bids.best_bid(),self.asks.best_ask())&&bid>=ask {return self.fail()}
  Ok(())
 }

 fn apply_levels(&mut self,d:&Delta) {
  write(&d.bids,&mut self.bids,self.retained);write(&d.asks,&mut self.asks,self.retained);
  for &(p,q) in &d.bids {if p.is_finite()&&p>0.0&&q.is_finite()&&q>=0.0 {self.bids.touch(p);}}
  for &(p,q) in &d.asks {if p.is_finite()&&p>0.0&&q.is_finite()&&q>=0.0 {self.asks.touch(p);}}
 }

 /// 这一档本地知不知道（见 `Levels`）。不知道的：不在表里不等于没了。
 pub fn knows(&self,side:Side,price:f64)->bool {
  match side {Side::Bid=>self.bids.knows(price,true),Side::Ask=>self.asks.knows(price,false)}
 }

 fn band(mid:f64,bid:f64,ask:f64)->(f64,f64) {let f=RETAIN_BPS/10_000.0;((mid*(1.0-f)).min(bid),(mid*(1.0+f)).max(ask))}

 fn trim_far(&mut self) {
  let (Some(bid),Some(ask))=(self.bids.best_bid(),self.asks.best_ask()) else {return};
  let keep=Self::band((bid+ask)/2.0,bid,ask);
  self.bids.keep_from(keep.0);self.asks.keep_to(keep.1);
  self.retained=Some(keep);
 }

 /// 中间价两侧 `bps` 以内的每一档（侧、价、量），顺手清掉留存带以外的；返回中间价，簿空一侧返回 None。
 pub fn for_each_within(&mut self,bps:f64,mut body:impl FnMut(Side,f64,f64))->Option<f64> {
  let (bid,ask)=(self.bids.best_bid()?,self.asks.best_ask()?);
  let mid=(bid+ask)/2.0;
  let f=bps/10_000.0;
  let (floor,ceiling)=(mid*(1.0-f),mid*(1.0+f));
  for (k,q) in self.bids.map.range(floor.to_bits()..) {body(Side::Bid,f64::from_bits(*k),*q)}
  for (k,q) in self.asks.map.range(..=ceiling.to_bits()) {body(Side::Ask,f64::from_bits(*k),*q)}
  let keep=Self::band(mid,bid,ask);
  self.bids.keep_from(keep.0);self.asks.keep_to(keep.1);
  self.retained=Some(keep);
  Some(mid)
 }

 #[cfg(test)]
 pub fn quantity(&self,side:Side,price:f64)->f64 {
  let levels=match side {Side::Bid=>&self.bids,Side::Ask=>&self.asks};
  levels.map.get(&price.to_bits()).copied().unwrap_or(0.0)
 }
}

fn write(levels:&[Level],side:&mut Levels,band:Option<(f64,f64)>) {
 for &(price,quantity) in levels {
  if !(price.is_finite()&&price>0.0&&quantity.is_finite()&&quantity>=0.0) {continue}
  if let Some((floor,ceiling))=band&&quantity>0.0&&(price<floor||price>ceiling) {continue}
  side.set(price,quantity);
 }
}

// ------------------------------------------------------------------ 一本簿的接续

/// 簿要上一层做什么。
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum Action {None,FetchSnapshot,Resubscribe}

/// 这本簿是哪家的哪个合约。`id` 和手机上的 `OrderFlowVenue.id` 同一个写法（`binance:usdtPerp:BTCUSDT`）。
#[derive(Clone,Debug,PartialEq)]
pub struct VenueInfo {
 pub id:String,
 pub exchange:&'static str,
 pub label:&'static str,
 pub product:&'static str,
 pub instrument:String,
 pub notional:Notional,
 /// 交易所挂牌价 ÷ 这个数 = 每个币的价（币安 `1000PEPE` 为 1000，其余为 1）。
 pub price_scale:f64,
 pub sequence:Sequence,
 pub in_band:bool,
}
impl VenueInfo {
 /// 交易所原样的价与量 → 每个币的价、与之配套的量（正向合约量乘回去，名义美元不变；反向合约是张数，不动）。
 pub fn level(&self,price:f64,quantity:f64)->Level {
  match self.notional {
   Notional::Linear(_)=>(price/self.price_scale,quantity*self.price_scale),
   Notional::Inverse(_)=>(price/self.price_scale,quantity),
  }
 }
}

/// 一个桶的合计：美元名义、桶里名义最大的那一档的名义与价。
#[derive(Clone,Copy,Debug,Default,PartialEq)]
pub struct Bucket {pub notional:f64,pub top:f64,pub price:f64}

#[derive(Clone,Debug)]
pub struct VenueBook {
 pub venue:VenueInfo,
 book:LocalBook,
 ready_since:Option<i64>,
 buffered:VecDeque<Delta>,
 pending:Option<Snapshot>,
 /// 当前连接代号：连接任务每次连上都换一个，迟到的旧帧与旧快照按它丢掉。
 pub connection:u64,
}

impl VenueBook {
 pub fn new(venue:VenueInfo)->Self {
  let book=LocalBook::new(venue.sequence);
  Self{venue,book,ready_since:None,buffered:VecDeque::new(),pending:None,connection:0}
 }
 pub fn is_ready(&self)->bool {self.book.quality==Quality::Ready&&self.ready_since.is_some()}

 /// 新连接：换代号、清簿。快照不在流里的要去拉一份。
 pub fn opened(&mut self,connection:u64)->Action {
  self.connection=connection;
  self.book.begin_resync();
  self.buffered.clear();self.pending=None;self.ready_since=None;
  if self.venue.in_band {Action::None} else {Action::FetchSnapshot}
 }

 /// 断线：回到「等重连」。
 pub fn closed(&mut self) {self.book.begin_resync();self.buffered.clear();self.pending=None;self.ready_since=None;}

 pub fn ingest(&mut self,message:Message,now:i64)->Action {
  let in_band=self.venue.in_band;
  match message {
   Message::Snapshot(s)=>match self.book.replace(&s) {
    Ok(())=>{self.ready_since=Some(now);Action::None},
    Err(_)=>{self.ready_since=None;if in_band {Action::Resubscribe} else {Action::FetchSnapshot}},
   },
   Message::Delta(d)=>{
    if self.book.quality==Quality::Ready {
     return match self.book.apply(&d) {
      Ok(())=>Action::None,
      Err(_)=>{
       self.ready_since=None;
       if in_band {return Action::Resubscribe}
       self.buffered.clear();self.buffered.push_back(d);self.pending=None;
       Action::FetchSnapshot
      },
     };
    }
    if in_band {return Action::None}
    self.buffered.push_back(d);
    while self.buffered.len()>BUFFER {self.buffered.pop_front();}
    self.try_bootstrap(now)
   },
   Message::Reset=>{
    self.book.mark_gapped();self.ready_since=None;self.buffered.clear();self.pending=None;
    if in_band {Action::Resubscribe} else {Action::FetchSnapshot}
   },
  }
 }

 /// REST 快照到了：和已缓冲的增量对序号。
 pub fn snapshot(&mut self,s:Snapshot,now:i64)->Action {self.pending=Some(s);self.try_bootstrap(now)}

 fn try_bootstrap(&mut self,now:i64)->Action {
  let Some(snapshot)=self.pending.take() else {return Action::None};
  match self.book.bootstrap(&snapshot,&self.buffered) {
   Ok(true)=>{self.buffered.clear();self.ready_since=Some(now);Action::None},
   Ok(false)=>{self.pending=Some(snapshot);Action::None},
   Err(_)=>{
    self.ready_since=None;
    self.buffered.retain(|d|d.last>snapshot.last);
    Action::FetchSnapshot
   },
  }
 }

 /// 这一档本地知不知道（快照截断时覆盖范围以外、又没推过的档不知道）。簿没就绪一律不知道。
 pub fn knows(&self,side:Side,price:f64)->bool {self.is_ready()&&self.book.knows(side,price)}

 /// 这一拍按桶合计的美元名义（中间价两侧 `radius_bps` 以内），簿没就绪返回 None。
 pub fn buckets(&mut self,step:f64,radius_bps:f64)->Option<HashMap<(Side,i64),Bucket>> {
  if !self.is_ready() {return None}
  let notional=self.venue.notional;
  let mut out:HashMap<(Side,i64),Bucket>=HashMap::new();
  let mid=self.book.for_each_within(radius_bps,|side,price,quantity| {
   let usd=notional.usd(price,quantity);
   if usd<=0.0 {return}
   let value=out.entry((side,bucket_index(price,step))).or_default();
   value.notional+=usd;
   if usd>value.top {value.top=usd;value.price=price;}
  });
  mid.map(|_|out)
 }
}

/// 价 → 桶号：floor(价 / 步长)，浮点误差 1e-9 以内就近取整（照 `BucketScheme.index`）。
pub fn bucket_index(price:f64,step:f64)->i64 {
 let x=price/step;
 let r=x.round();
 let q=if (x-r).abs()<=1e-9*r.abs().max(1.0) {r} else {x.floor()};
 if !q.is_finite()||q.abs()>=(i64::MAX/4) as f64 {return 0}
 q as i64
}

#[cfg(test)]
mod tests {
 use super::*;

 fn snap(last:i64,bids:&[Level],asks:&[Level])->Snapshot {Snapshot{last,requested:1000,bids:bids.to_vec(),asks:asks.to_vec()}}
 fn delta(first:i64,last:i64,prev:Option<i64>,bids:&[Level])->Delta {Delta{first,last,prev,bids:bids.to_vec(),asks:vec![]}}

 #[test] fn spot_bootstrap_needs_l_plus_one_and_a_gap_clears_the_book() {
  let mut book=LocalBook::new(Sequence::RangeOverlap);
  let buffered:VecDeque<Delta>=[delta(95,100,None,&[]),delta(101,103,None,&[(99.0,2.0)])].into();
  assert_eq!(book.bootstrap(&snap(100,&[(99.0,1.0)],&[(101.0,1.0)]),&buffered),Ok(true));
  assert_eq!(book.quantity(Side::Bid,99.0),2.0);
  assert_eq!(book.apply(&delta(103,103,None,&[])),Ok(()),"重复的忽略");
  assert_eq!(book.apply(&delta(106,107,None,&[])),Err(Gap));
  assert_eq!(book.quality,Quality::Gapped);
  assert_eq!(book.quantity(Side::Bid,99.0),0.0);
 }

 #[test] fn futures_need_pu_and_okx_needs_exact_prev() {
  let mut f=LocalBook::new(Sequence::PreviousFinalOverlap);
  let buffered:VecDeque<Delta>=[delta(95,101,Some(94),&[])].into();
  assert_eq!(f.bootstrap(&snap(100,&[(99.0,1.0)],&[(101.0,1.0)]),&buffered),Ok(true));
  assert_eq!(f.apply(&delta(102,105,Some(101),&[])),Ok(()));
  assert_eq!(f.apply(&delta(106,107,Some(104),&[])),Err(Gap));
  let mut okx=LocalBook::new(Sequence::PreviousFinalExact);
  okx.replace(&snap(10,&[(99.0,1.0)],&[(101.0,1.0)])).unwrap();
  assert_eq!(okx.apply(&delta(11,11,Some(10),&[])),Ok(()));
  assert_eq!(okx.apply(&delta(13,13,Some(12),&[])),Err(Gap));
  let mut cb=LocalBook::new(Sequence::StrictIncrementing);
  cb.replace(&snap(1,&[(99.0,1.0)],&[(101.0,1.0)])).unwrap();
  assert_eq!(cb.apply(&delta(2,2,None,&[])),Ok(()));
  assert_eq!(cb.apply(&delta(4,4,None,&[])),Err(Gap));
 }

 #[test] fn crossed_and_regressed_snapshots_fail_closed() {
  let mut book=LocalBook::new(Sequence::PreviousFinalExact);
  assert_eq!(book.replace(&snap(5,&[(101.0,1.0)],&[(100.0,1.0)])),Err(Gap));
  book.replace(&snap(5,&[(99.0,1.0)],&[(100.0,1.0)])).unwrap();
  assert_eq!(book.replace(&snap(4,&[(99.0,1.0)],&[(100.0,1.0)])),Err(Gap));
 }

 #[test] fn far_levels_are_dropped_and_zero_removes() {
  let mut book=LocalBook::new(Sequence::PreviousFinalExact);
  book.replace(&snap(1,&[(99.0,1.0),(50.0,9.0)],&[(101.0,1.0),(200.0,9.0)])).unwrap();
  assert_eq!(book.quantity(Side::Bid,50.0),0.0,"中间价两侧 20% 以外不留");
  assert_eq!(book.quantity(Side::Ask,200.0),0.0);
  book.apply(&delta(2,2,Some(1),&[(99.0,0.0),(98.0,3.0)])).unwrap();
  let mut seen=vec![];
  book.for_each_within(1000.0,|s,p,q|seen.push((s,p,q)));
  assert_eq!(seen,vec![(Side::Bid,98.0,3.0),(Side::Ask,101.0,1.0)]);
 }

 #[test] fn a_truncated_snapshot_only_covers_as_far_as_its_last_level() {
  // 币安 REST 快照要 1000 档只给到 1000 档：比最远那档更远的价位本地不知道，直到增量推过它。
  let mut book=LocalBook::new(Sequence::PreviousFinalExact);
  let bids:Vec<Level>=vec![(60_000.0,1.0),(59_990.0,1.0)];
  book.replace(&Snapshot{last:1,requested:2,bids:bids.clone(),asks:vec![(60_010.0,1.0)]}).unwrap();
  assert!(book.knows(Side::Bid,59_995.0),"覆盖范围以内不在表里就是没有");
  assert!(book.knows(Side::Bid,59_990.0));
  assert!(!book.knows(Side::Bid,59_500.0),"比最远一档还远：不知道");
  assert!(book.knows(Side::Ask,70_000.0),"卖盘只回了 1 档、不到要的 2 档：整侧完整");
  book.apply(&delta(2,2,Some(1),&[(59_500.0,0.0)])).unwrap();
  assert!(book.knows(Side::Bid,59_500.0),"增量推成 0 也算知道了：确实没了");
  assert!(!book.knows(Side::Bid,59_400.0));
  book.apply(&delta(3,3,Some(2),&[(59_400.0,2.0)])).unwrap();
  assert!(book.knows(Side::Bid,59_400.0)&&book.quantity(Side::Bid,59_400.0)==2.0);
  // 完整快照（档数不到要的数）整侧都知道；流里整本推来的（requested = MAX）也是。
  book.replace(&Snapshot{last:4,requested:1000,bids,asks:vec![(60_010.0,1.0)]}).unwrap();
  assert!(book.knows(Side::Bid,59_500.0)&&book.knows(Side::Bid,1.0));
  book.mark_gapped();
  assert!(book.knows(Side::Bid,1.0),"簿本身空了由上层（VenueBook::is_ready）挡");
 }

 #[test] fn bucket_floors_and_snaps_float_noise() {
  assert_eq!(bucket_index(1590.4,1.0),1590);
  assert_eq!(bucket_index(64_199.9,100.0),641);
  assert_eq!(bucket_index(0.3,0.1),3,"0.3 / 0.1 = 2.9999999999999996 要就近取成 3");
  assert_eq!(bucket_index(-0.5,1.0),-1);
 }
}
