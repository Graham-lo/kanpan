//! 一本簿：照 KanpanCore 的 `LocalBook.swift` 与 `VenueBook.swift` 逐条移植。
//!
//! 这里不认交易所：哪家用哪种序列规则、快照在不在流里、是不是滑动窗口簿，都由 `venues::<交易所>::orderflow`
//! 填进 `VenueInfo`（见 `venues::orderflow::book`）。
//!
//! * 五种序列规则：区间重叠 `U/u`（rangeOverlap）、上一条终号重叠 `U/u/pu`（previousFinalOverlap）、
//!   上一条终号严格相等（previousFinalExact）、逐条加一（strictIncrementing）、每帧都是整本快照（snapshotOnly）。
//! * 快照不在流里的先缓冲增量、等 REST 快照对上序号；快照在流里的收到首帧就绪。
//! * 本地只留中间价两侧扫描半径两倍以内的价位（`RETAIN_BPS`）；滑动窗口簿不裁（本来就封顶在窗口档数，见 `Levels`）。
//! * 价与量进来时已经换成「每个币」的口径（挂牌名带 1000 倍缩放的除掉缩放），名义美元不变。
//!
//! 和手机那份的差别只有一处：连接代号的核对放在上一层（`VenueBook`），旧连接的迟到帧在进簿之前就丢了。
use super::model::{Notional,SCAN_RADIUS_BPS};
use std::collections::{BTreeMap,BTreeSet,HashMap,VecDeque};

/// 本地簿留中间价两侧多远（扫描半径的两倍）。
pub const RETAIN_BPS:f64=2.0*SCAN_RADIUS_BPS;
/// 等快照时最多缓冲几条增量。
pub const BUFFER:usize=5_000;
/// 流内快照的簿开了这么久还只收到增量、没等到快照：快照那一帧被丢了（跟踪器堵住时
/// 帧会被丢），再等也等不来，重订一次。正常订上一两秒内就到。
pub const IN_BAND_SNAPSHOT_WAIT_MS:i64=60_000;

#[derive(Clone,Copy,Debug,PartialEq,Eq,Hash,PartialOrd,Ord)]
pub enum Side {Bid,Ask}
impl Side {
 pub fn wire(self)->&'static str {match self {Side::Bid=>"bid",Side::Ask=>"ask"}}
 pub fn parse(text:&str)->Option<Self> {match text {"bid"=>Some(Side::Bid),"ask"=>Some(Side::Ask),_=>None}}
}

/// 增量怎么接续（照客户端 `OrderFlowSequence`，多一种 `SnapshotOnly`）。
///
/// * `StrictIncrementing`：序号逐条加一；流内快照序号为 1 表示交易所那边重启过、整本重来（序号回到 1
///   不算倒退，按新快照整本替换）。
/// * `SnapshotOnly`：没有增量，每帧都是前若干档的整本快照，`last` 是快照时刻（毫秒）。时刻倒退的帧
///   （迟到）直接忽略、簿不动，不算断档。
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum Sequence {RangeOverlap,PreviousFinalOverlap,PreviousFinalExact,StrictIncrementing,SnapshotOnly}

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
/// 快照被截断时（REST 快照要 1000 / 5000 档、流内滑动窗口快照几十到 1000 档），比快照最远一档还远的
/// 价位本地并不知道有没有：`extent` 记快照最远那一档（覆盖区间的远端）。覆盖范围以内「表里没有」就是没有；
/// 以外的看这本簿的增量是哪一种（`window`）：
///
/// * 全簿增量：交易所为整本簿推变动，但快照以外、此后没动过的档本地永远拿不到——一个远处的价位被推过，
///   只说明那一个价位知道了，它和覆盖区间之间的档仍然不知道。所以覆盖区间不外扩，推过的价位逐个记在
///   `touched` 里（含推成 0 的）。
/// * 滑动窗口（`window` 为窗口档数）：交易所只维护前 N 档，一档被挤出窗口时推的是
///   数量 0，和真撤单长得一样（2026-09-28 客户端实测）。每帧整本快照的簿（`SnapshotOnly`）也按窗口算：
///   只给前 N 档，最深一档以外不知道。所以不看快照的覆盖区间，按表本身判：
///   表满了（到窗口档数）时只有窗口最深一档以内知道——被挤出去的那档删掉之后落在新的最深一档外面，读成
///   「不知道」；真撤掉窗口里的一档时，第 N+1 档会带着量补进来、落在更深处，撤掉的那档仍在窗口内，读成「没了」。
///   表不满说明整本簿都在窗口里，整侧都知道。窗口簿不裁留存带（裁了表就不是窗口，「最深一档」失效），
///   本来就封顶在窗口档数。与客户端 `LocalBook.knows` 的 slidingWindow 分支同一规则。
///
/// 全簿增量的快照完整（返回的档数不到要的数，或流里整本推来）时 `extent` 是 None，整侧都算知道。
#[derive(Clone,Debug,Default)]
struct Levels {map:BTreeMap<u64,f64>,extent:Option<f64>,touched:BTreeSet<u64>,window:usize}
impl Levels {
 fn set(&mut self,price:f64,quantity:f64) {if quantity==0.0 {self.map.remove(&price.to_bits());} else {self.map.insert(price.to_bits(),quantity);}}
 /// 全簿增量推到一档：在覆盖区间以外时记下这一个价位（含推成 0 的）。区间以内的、以及窗口簿，什么也不做。
 fn touch(&mut self,price:f64,far_is_low:bool) {
  if self.window>0 {return}
  let Some(e)=self.extent else {return};
  if if far_is_low {price<e} else {price>e} {self.touched.insert(price.to_bits());}
 }
 /// 覆盖区间以内（O(1)，不看逐价记下的）。
 fn covers(&self,price:f64,far_is_low:bool)->bool {
  match self.extent {None=>true,Some(e)=>if far_is_low {price>=e} else {price<=e}}
 }
 fn best_bid(&self)->Option<f64> {self.map.last_key_value().map(|(k,_)|f64::from_bits(*k))}
 fn best_ask(&self)->Option<f64> {self.map.first_key_value().map(|(k,_)|f64::from_bits(*k))}
 /// 丢掉低于 `floor` 的。
 fn keep_from(&mut self,floor:f64) {self.map=self.map.split_off(&floor.to_bits());self.touched=self.touched.split_off(&floor.to_bits());}
 /// 丢掉高于 `ceiling` 的。
 fn keep_to(&mut self,ceiling:f64) {let _=self.map.split_off(&(ceiling.to_bits()+1));let _=self.touched.split_off(&(ceiling.to_bits()+1));}
 fn clear(&mut self) {self.map.clear();self.extent=None;self.touched.clear();}
 /// 这一档本地知不知道：覆盖范围以内都知道，以外的只有增量推过的才知道。`far_is_low`：买盘越远价越低。
 /// 窗口簿：表满了只有最深一档以内知道（有序表的首尾，O(log n)），不满整侧都知道。
 fn knows(&self,price:f64,far_is_low:bool)->bool {
  if self.window>0 {
   if self.map.len()<self.window {return true}
   let deepest=if far_is_low {self.map.first_key_value()} else {self.map.last_key_value()};
   return deepest.is_none_or(|(k,_)|if far_is_low {price>=f64::from_bits(*k)} else {price<=f64::from_bits(*k)});
  }
  self.covers(price,far_is_low)||self.touched.contains(&price.to_bits())
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
 /// `sliding`：这本簿的流是滑动窗口（只维护前 N 档，见 `Levels`），由交易所描述（`VenueInfo::sliding`）给。
 pub fn new(sequence:Sequence,sliding:bool)->Self {
  // 窗口档数按快照要的档数定（`bootstrap` / `replace` 里改），拿到快照之前先记成「窗口簿、档数未定」。
  let window=if sliding {usize::MAX} else {0};
  let side=||Levels{window,..Levels::default()};
  Self{sequence,quality:Quality::Bootstrapping,last:None,bids:side(),asks:side(),retained:None}
 }

 /// REST 快照对缓冲增量。`Ok(true)` 就绪，`Ok(false)` 还没有能接上的增量（等）。
 pub fn bootstrap(&mut self,s:&Snapshot,buffered:&VecDeque<Delta>)->Result<bool,Gap> {
  self.quality=Quality::Bootstrapping;
  self.last=Some(s.last);
  if s.requested==0||s.bids.len()>s.requested||s.asks.len()>s.requested {return self.fail()}
  self.bids.clear();self.asks.clear();self.retained=None;
  write(&s.bids,&mut self.bids,None);write(&s.asks,&mut self.asks,None);
  self.bids.extent=extent(&s.bids,s.requested,true);self.asks.extent=extent(&s.asks,s.requested,false);
  self.window_from(s.requested);
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
   Sequence::SnapshotOnly=>false,
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
   Sequence::SnapshotOnly=>false,
  };
  if !chained {return self.fail()}
  self.apply_levels(d);
  self.last=Some(d.last);
  self.check_not_crossed()
 }

 /// 流内权威快照：整本替换，立即就绪。
 pub fn replace(&mut self,s:&Snapshot)->Result<(),Gap> {
  if let Some(previous)=self.last&&s.last<previous {
   // 整本快照的迟到帧：忽略，簿不动。逐条加一的序号回到 1：交易所重启，整本重来。
   if self.sequence==Sequence::SnapshotOnly {return Ok(())}
   if !(self.sequence==Sequence::StrictIncrementing&&s.last==1) {return self.fail()}
  }
  if s.requested==0||s.bids.len()>s.requested||s.asks.len()>s.requested {return self.fail()}
  self.begin_resync();
  write(&s.bids,&mut self.bids,None);write(&s.asks,&mut self.asks,None);
  self.bids.extent=extent(&s.bids,s.requested,true);self.asks.extent=extent(&s.asks,s.requested,false);
  self.window_from(s.requested);
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
  // 留存带以外的正量档不进表（`write`），也不拿来外扩覆盖区间。
  let retained=self.retained;
  let kept=|p:f64,q:f64|p.is_finite()&&p>0.0&&q.is_finite()&&q>=0.0&&!retained.is_some_and(|(f,c)|q>0.0&&(p<f||p>c));
  for &(p,q) in &d.bids {if kept(p,q) {self.bids.touch(p,true);}}
  for &(p,q) in &d.asks {if kept(p,q) {self.asks.touch(p,false);}}
 }

 /// 这一档本地知不知道（见 `Levels`）。不知道的：不在表里不等于没了。
 pub fn knows(&self,side:Side,price:f64)->bool {
  match side {Side::Bid=>self.bids.knows(price,true),Side::Ask=>self.asks.knows(price,false)}
 }

 fn band(mid:f64,bid:f64,ask:f64)->(f64,f64) {let f=RETAIN_BPS/10_000.0;((mid*(1.0-f)).min(bid),(mid*(1.0+f)).max(ask))}

 /// 窗口簿：窗口档数就是快照要的档数。
 fn window_from(&mut self,requested:usize) {
  if self.bids.window>0 {self.bids.window=requested;self.asks.window=requested;}
 }

 fn trim_far(&mut self) {
  if self.bids.window>0 {return}
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
  if self.bids.window>0 {return Some(mid)}
  let keep=Self::band(mid,bid,ask);
  self.bids.keep_from(keep.0);self.asks.keep_to(keep.1);
  self.retained=Some(keep);
  Some(mid)
 }

 /// 一侧 `[low, high]` 价位区间里的每一档（价、量）：按区间直接查，不扫整侧、不清留存带。
 pub fn for_each_between(&self,side:Side,low:f64,high:f64,mut body:impl FnMut(f64,f64)) {
  if !(low.is_finite()&&high.is_finite())||high<low {return}
  let levels=match side {Side::Bid=>&self.bids,Side::Ask=>&self.asks};
  for (k,q) in levels.map.range(low.max(0.0).to_bits()..=high.to_bits()) {body(f64::from_bits(*k),*q)}
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

/// 这本簿是哪家的哪个合约。`id` 和手机上的 `OrderFlowVenue.id` 同一个写法（`{交易所}:{产品}:{合约}`）。
/// 除 `id` / `instrument` 外都由 `venues::orderflow::book` 按交易所描述填。
#[derive(Clone,Debug,PartialEq)]
pub struct VenueInfo {
 pub id:String,
 pub exchange:&'static str,
 pub label:&'static str,
 pub product:&'static str,
 pub instrument:String,
 pub notional:Notional,
 /// 交易所挂牌价 ÷ 这个数 = 每个币的价（挂牌名带 `1000` 缩放的为 1000，其余为 1）。
 pub price_scale:f64,
 pub sequence:Sequence,
 /// 快照在流里（订上就推），不用 REST 拉。
 pub in_band:bool,
 /// 流是滑动窗口（只维护前 N 档，被挤出的推 0，见 `Levels`）。
 pub sliding:bool,
}
impl VenueInfo {
 /// 测试用：一本按给定规则接续、不订任何连接的簿。`exchange` 取 `id` 的第一段。
 #[cfg(test)]
 pub fn test(id:&str,instrument:&str,product:&'static str,notional:Notional,sequence:Sequence,in_band:bool,sliding:bool)->Self {
  let exchange:&'static str=Box::leak(id.split(':').next().unwrap_or("").to_string().into_boxed_str());
  VenueInfo{id:id.into(),exchange,label:"测试",product,instrument:instrument.into(),notional,price_scale:1.0,sequence,in_band,sliding}
 }
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

/// 一拍里按（侧，桶号）合计的桶。
pub type Buckets=HashMap<(Side,i64),Bucket>;

#[derive(Clone,Debug)]
pub struct VenueBook {
 pub venue:VenueInfo,
 book:LocalBook,
 ready_since:Option<i64>,
 buffered:VecDeque<Delta>,
 pending:Option<Snapshot>,
 /// 当前连接代号：连接任务每次连上都换一个，迟到的旧帧与旧快照按它丢掉。
 pub connection:u64,
 /// 换连接（全局序号的连接到 24 小时前平滑换新、或几条小连接并成一条）时，旧连接的代号：
 /// 交接期间两条连接推的是同一串全局序号，两边的帧都收，重复的由 `LocalBook::apply` 按序号丢掉，
 /// 簿不用重拉快照。旧连接一断（或交接完成）就清掉。
 pub previous:Option<u64>,
 /// 这本簿第几次从头开始（连上新连接、断线各加一）。REST 快照按它认：排队期间换了连接（平滑交接）
 /// 不加，排着的快照照样能用；断过线重来就加，旧快照丢掉。
 pub epoch:u64,
 /// 流内快照的簿从什么时候起在等快照（开了、断档要重订之后第一条增量的时刻）。
 waiting_since:Option<i64>,
 /// 挂在一条连着的连接上（开过、之后没断）。连着但没就绪 = 在等快照 / 重同步，簿上的单只是暂时
 /// 看不见；断着 = 真的收不到，按断线处理（见 `Model::evaluate`）。
 online:bool,
}

impl VenueBook {
 pub fn new(venue:VenueInfo)->Self {
  let book=LocalBook::new(venue.sequence,venue.sliding);
  Self{venue,book,ready_since:None,buffered:VecDeque::new(),pending:None,connection:0,previous:None,epoch:0,waiting_since:None,online:false}
 }
 pub fn is_ready(&self)->bool {self.book.quality==Quality::Ready&&self.ready_since.is_some()}
 pub fn is_online(&self)->bool {self.online}
 /// 这一轮从什么时候起就绪（没就绪为 None）。
 pub fn ready_since(&self)->Option<i64> {self.ready_since}

 /// 新连接：换代号、清簿。快照不在流里的要去拉一份。
 pub fn opened(&mut self,connection:u64)->Action {
  self.connection=connection;
  self.previous=None;
  self.online=true;
  self.epoch+=1;
  self.book.begin_resync();
  self.buffered.clear();self.pending=None;self.ready_since=None;self.waiting_since=None;
  if self.venue.in_band {Action::None} else {Action::FetchSnapshot}
 }

 /// 这条连接的帧 / 快照认不认。
 pub fn accepts(&self,connection:u64)->bool {connection==self.connection||self.previous==Some(connection)}

 /// 平滑换连接：新连接已经在推同一串序号了，簿接着用，两条连接的帧都认。
 /// 从来没在任何连接上开过（代号 0）的，按新连接从头开。只用于序号全局、快照不在流里的簿。
 pub fn handover(&mut self,connection:u64)->Action {
  if self.connection==0 {return self.opened(connection)}
  if connection!=self.connection {self.previous=Some(self.connection);self.connection=connection;}
  Action::None
 }

 /// 某条连接断了：是当前连接就回到「等重连」；只是交接中的旧连接就忘掉它。
 pub fn disconnected(&mut self,connection:u64) {
  if connection==self.connection {self.closed()} else if self.previous==Some(connection) {self.previous=None}
 }

 /// 就绪时中间价两侧 `bps` 以内买卖两侧的美元名义之和。
 pub fn depth_usd(&mut self,bps:f64)->Option<f64> {
  if !self.is_ready() {return None}
  let notional=self.venue.notional;
  let mut sum=0.0;
  self.book.for_each_within(bps,|_,price,quantity|sum+=notional.usd(price,quantity))?;
  Some(sum)
 }

 /// 断线：回到「等重连」。
 pub fn closed(&mut self) {
  self.previous=None;self.online=false;self.epoch+=1;self.book.begin_resync();self.buffered.clear();self.pending=None;self.ready_since=None;self.waiting_since=None;
 }

 pub fn ingest(&mut self,message:Message,now:i64)->Action {
  let in_band=self.venue.in_band;
  match message {
   Message::Snapshot(s)=>match self.book.replace(&s) {
    Ok(())=>{
     // 每帧整本快照的簿：就绪时刻从第一帧算起，不随每帧刷新（按就绪多久判断的规则才有意义）。
     if self.venue.sequence==Sequence::SnapshotOnly {self.ready_since.get_or_insert(now);} else {self.ready_since=Some(now);}
     self.waiting_since=None;Action::None
    },
    Err(_)=>{self.ready_since=None;self.waiting_since=None;if in_band {Action::Resubscribe} else {Action::FetchSnapshot}},
   },
   Message::Delta(d)=>{
    if self.book.quality==Quality::Ready {
     return match self.book.apply(&d) {
      Ok(())=>Action::None,
      Err(_)=>{
       self.ready_since=None;
       if in_band {self.waiting_since=None;return Action::Resubscribe}
       self.buffered.clear();self.buffered.push_back(d);self.pending=None;
       Action::FetchSnapshot
      },
     };
    }
    if in_band {
     // 增量在来、快照迟迟不到：那一帧丢了，原来就一直干等到这条连接断。
     let since=*self.waiting_since.get_or_insert(now);
     if now-since<IN_BAND_SNAPSHOT_WAIT_MS {return Action::None}
     self.waiting_since=Some(now);
     return Action::Resubscribe;
    }
    self.buffered.push_back(d);
    while self.buffered.len()>BUFFER {self.buffered.pop_front();}
    self.try_bootstrap(now)
   },
   Message::Reset=>{
    self.book.mark_gapped();self.ready_since=None;self.buffered.clear();self.pending=None;self.waiting_since=None;
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

 /// 这一拍按桶合计的美元名义（中间价两侧 `radius_bps` 以内）与此刻的中间价，簿没就绪返回 None。
 pub fn buckets(&mut self,step:f64,radius_bps:f64)->Option<(Buckets,f64)> {
  if !self.is_ready() {return None}
  let notional=self.venue.notional;
  let mut out:Buckets=HashMap::new();
  let mid=self.book.for_each_within(radius_bps,|side,price,quantity| {
   let usd=notional.usd(price,quantity);
   if usd<=0.0 {return}
   let value=out.entry((side,bucket_index(price,step))).or_default();
   value.notional+=usd;
   if usd>value.top {value.top=usd;value.price=price;}
  });
  mid.map(|mid|(out,mid))
 }
}

impl VenueBook {
 /// 单独一个桶此刻的合计（不受扫描半径限制，只要还在留存带里），簿没就绪或桶里一档都没有返回 None。
 /// 挂着的单走到扫描半径边上时用它接着看（见 `model::EXIT_RADIUS_BPS`）。
 pub fn bucket(&self,side:Side,index:i64,step:f64)->Option<Bucket> {
  if !self.is_ready()||!(step>0.0) {return None}
  // 区间两头各放宽一点，桶号的浮点就近取整（`bucket_index`）落在边上的档也收进来，再按桶号过滤。
  let (low,high)=(index as f64*step*(1.0-1e-9),(index+1) as f64*step*(1.0+1e-9));
  let notional=self.venue.notional;
  let mut out:Option<Bucket>=None;
  self.book.for_each_between(side,low,high,|price,quantity| {
   if bucket_index(price,step)!=index {return}
   let usd=notional.usd(price,quantity);
   if usd<=0.0 {return}
   let value=out.get_or_insert_with(Bucket::default);
   value.notional+=usd;
   if usd>value.top {value.top=usd;value.price=price;}
  });
  out
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
  let mut book=LocalBook::new(Sequence::RangeOverlap,false);
  let buffered:VecDeque<Delta>=[delta(95,100,None,&[]),delta(101,103,None,&[(99.0,2.0)])].into();
  assert_eq!(book.bootstrap(&snap(100,&[(99.0,1.0)],&[(101.0,1.0)]),&buffered),Ok(true));
  assert_eq!(book.quantity(Side::Bid,99.0),2.0);
  assert_eq!(book.apply(&delta(103,103,None,&[])),Ok(()),"重复的忽略");
  assert_eq!(book.apply(&delta(106,107,None,&[])),Err(Gap));
  assert_eq!(book.quality,Quality::Gapped);
  assert_eq!(book.quantity(Side::Bid,99.0),0.0);
 }

 fn futures_venue()->VenueInfo {
  VenueInfo::test("venue-a:usdtPerp:BTCUSDT","BTCUSDT","usdtPerp",Notional::Linear(1.0),Sequence::PreviousFinalOverlap,false,false)
 }

 #[test] fn handover_keeps_the_book_and_both_connections_feed_it() {
  let mut b=VenueBook::new(futures_venue());
  assert_eq!(b.opened(1),Action::FetchSnapshot);
  assert_eq!(b.ingest(Message::Delta(delta(95,101,Some(94),&[(99.0,1.0)])),0),Action::None);
  assert_eq!(b.snapshot(snap(100,&[(99.0,1.0)],&[(101.0,1.0)]),0),Action::None);
  assert!(b.is_ready());
  let epoch=b.epoch;
  assert_eq!(b.handover(2),Action::None,"换连接不重拉快照");
  assert_eq!(b.epoch,epoch,"交接不换代：排队中的快照照样认");
  assert!(b.accepts(1)&&b.accepts(2)&&!b.accepts(3));
  // 两条连接推同一串：新连接先到的 102–105，旧连接晚到的同一帧按序号丢掉。
  assert_eq!(b.ingest(Message::Delta(delta(102,105,Some(101),&[(99.0,3.0)])),1),Action::None);
  assert_eq!(b.ingest(Message::Delta(delta(102,105,Some(101),&[(99.0,3.0)])),1),Action::None);
  assert!(b.is_ready());
  b.disconnected(1);
  assert!(b.is_ready()&&!b.accepts(1),"旧连接断开只是忘掉它");
  assert_eq!(b.depth_usd(200.0),Some(99.0*3.0+101.0),"±2% 以内两侧名义");
  b.disconnected(2);
  assert!(!b.is_ready());
  assert_eq!(b.epoch,epoch+1,"真断线换代");
  let mut fresh=VenueBook::new(futures_venue());
  assert_eq!(fresh.handover(7),Action::FetchSnapshot,"没开过的簿按新连接从头开");
 }

 #[test] fn an_in_band_book_whose_snapshot_was_dropped_resubscribes() {
  let mut b=VenueBook::new(VenueInfo::test("venue-b:usdtPerp:BTC-USDT-SWAP","BTC-USDT-SWAP","usdtPerp",Notional::Linear(1.0),Sequence::PreviousFinalExact,true,true));
  assert_eq!(b.opened(3),Action::None,"流内快照：等它自己来");
  // 快照那一帧被丢了，只来增量。
  assert_eq!(b.ingest(Message::Delta(delta(11,11,Some(10),&[])),1_000),Action::None);
  assert_eq!(b.ingest(Message::Delta(delta(12,12,Some(11),&[])),1_000+IN_BAND_SNAPSHOT_WAIT_MS-1),Action::None);
  assert_eq!(b.ingest(Message::Delta(delta(13,13,Some(12),&[])),1_000+IN_BAND_SNAPSHOT_WAIT_MS),Action::Resubscribe,"等满一分钟重订");
  assert_eq!(b.ingest(Message::Delta(delta(14,14,Some(13),&[])),2_000+IN_BAND_SNAPSHOT_WAIT_MS),Action::None,"重订了再等一分钟，不连着发");
  // 快照到了：就绪，之后的增量照常接。
  assert_eq!(b.ingest(Message::Snapshot(snap(20,&[(99.0,1.0)],&[(101.0,1.0)])),3_000+IN_BAND_SNAPSHOT_WAIT_MS),Action::None);
  assert!(b.is_ready());
  assert_eq!(b.ingest(Message::Delta(delta(21,21,Some(20),&[])),10*IN_BAND_SNAPSHOT_WAIT_MS),Action::None);
  // 正常订上：快照一两秒内到，不重订。
  let mut c=b.clone();
  c.opened(4);
  assert_eq!(c.ingest(Message::Delta(delta(30,30,Some(29),&[])),0),Action::None);
  assert_eq!(c.ingest(Message::Snapshot(snap(31,&[(99.0,1.0)],&[(101.0,1.0)])),1_500),Action::None);
  assert!(c.is_ready());
 }

 #[test] fn overlap_needs_pu_and_exact_needs_the_previous_final() {
  let mut f=LocalBook::new(Sequence::PreviousFinalOverlap,false);
  let buffered:VecDeque<Delta>=[delta(95,101,Some(94),&[])].into();
  assert_eq!(f.bootstrap(&snap(100,&[(99.0,1.0)],&[(101.0,1.0)]),&buffered),Ok(true));
  assert_eq!(f.apply(&delta(102,105,Some(101),&[])),Ok(()));
  assert_eq!(f.apply(&delta(106,107,Some(104),&[])),Err(Gap));
  let mut exact=LocalBook::new(Sequence::PreviousFinalExact,true);
  exact.replace(&snap(10,&[(99.0,1.0)],&[(101.0,1.0)])).unwrap();
  assert_eq!(exact.apply(&delta(11,11,Some(10),&[])),Ok(()));
  assert_eq!(exact.apply(&delta(13,13,Some(12),&[])),Err(Gap));
  let mut cb=LocalBook::new(Sequence::StrictIncrementing,false);
  cb.replace(&snap(1,&[(99.0,1.0)],&[(101.0,1.0)])).unwrap();
  assert_eq!(cb.apply(&delta(2,2,None,&[])),Ok(()));
  assert_eq!(cb.apply(&delta(4,4,None,&[])),Err(Gap));
 }

 #[test] fn crossed_and_regressed_snapshots_fail_closed() {
  let mut book=LocalBook::new(Sequence::PreviousFinalExact,true);
  assert_eq!(book.replace(&snap(5,&[(101.0,1.0)],&[(100.0,1.0)])),Err(Gap));
  book.replace(&snap(5,&[(99.0,1.0)],&[(100.0,1.0)])).unwrap();
  assert_eq!(book.replace(&snap(4,&[(99.0,1.0)],&[(100.0,1.0)])),Err(Gap));
 }

 #[test] fn far_levels_are_dropped_and_zero_removes() {
  // 全簿增量才裁留存带（窗口簿不裁，见 `a_sliding_window_knows_only_down_to_its_deepest_level_when_full`）。
  let mut book=LocalBook::new(Sequence::PreviousFinalOverlap,false);
  book.replace(&snap(1,&[(99.0,1.0),(50.0,9.0)],&[(101.0,1.0),(200.0,9.0)])).unwrap();
  assert_eq!(book.quantity(Side::Bid,50.0),0.0,"中间价两侧 20% 以外不留");
  assert_eq!(book.quantity(Side::Ask,200.0),0.0);
  book.apply(&delta(2,2,Some(1),&[(99.0,0.0),(98.0,3.0)])).unwrap();
  let mut seen=vec![];
  book.for_each_within(1000.0,|s,p,q|seen.push((s,p,q)));
  assert_eq!(seen,vec![(Side::Bid,98.0,3.0),(Side::Ask,101.0,1.0)]);
 }

 #[test] fn a_truncated_snapshot_only_covers_as_far_as_its_last_level() {
  // REST 快照要 1000 档只给到 1000 档：比最远那档更远的价位本地不知道，直到增量推过它。
  let mut book=LocalBook::new(Sequence::PreviousFinalOverlap,false);
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

 #[test] fn a_sliding_window_knows_only_down_to_its_deepest_level_when_full() {
  // 滑动窗口只维护前 N 档（这里 N = 3）：一档被挤出窗口时推 0，和真撤单一样；表满了只有最深一档以内知道。
  let mut book=LocalBook::new(Sequence::PreviousFinalExact,true);
  book.replace(&Snapshot{last:1,requested:3,bids:vec![(60_000.0,1.0),(59_990.0,1.0),(59_900.0,5.0)],asks:vec![(60_010.0,1.0)]}).unwrap();
  assert!(book.knows(Side::Bid,59_900.0)&&book.knows(Side::Bid,59_950.0),"最深一档以内都知道");
  assert!(!book.knows(Side::Bid,59_800.0),"表满了：最深一档以外不知道");
  assert!(book.knows(Side::Ask,70_000.0),"卖盘只有 1 档 < 3：整侧都在窗口里");
  // 盘口多出一档，59 900 被挤出窗口（同一帧推 0）：它落在新的最深一档 59 990 以外，读成「不知道」而不是「没了」。
  book.apply(&delta(2,2,Some(1),&[(59_995.0,1.0),(59_900.0,0.0)])).unwrap();
  assert_eq!(book.quantity(Side::Bid,59_900.0),0.0);
  assert!(!book.knows(Side::Bid,59_900.0),"被挤出窗口：看不见，不是撤了");
  // 窗口里的 59 990 真撤了：第 N+1 档（59 900）带着量补进来、落在更深处，59 990 仍在窗口内——读成「没了」。
  book.apply(&delta(3,3,Some(2),&[(59_990.0,0.0),(59_900.0,5.0)])).unwrap();
  assert!(book.knows(Side::Bid,59_990.0)&&book.quantity(Side::Bid,59_990.0)==0.0,"真撤单：知道且没了");
  assert!(book.knows(Side::Bid,59_900.0),"补进来的那档又在窗口里了");
  // 盘口变薄、表不满：整侧都知道。
  book.apply(&delta(4,4,Some(3),&[(59_995.0,0.0)])).unwrap();
  assert!(book.knows(Side::Bid,10_000.0));
  // 窗口簿不裁留存带：远在留存带外的档也在表里（窗口本来就封顶）。
  book.apply(&delta(5,5,Some(4),&[(10_000.0,5.0)])).unwrap();
  assert_eq!(book.quantity(Side::Bid,10_000.0),5.0);
  // 全簿增量不外扩：远处推过一档只说明那一档，其间的仍不知道。
  let mut full=LocalBook::new(Sequence::PreviousFinalOverlap,false);
  let buffered:VecDeque<Delta>=[delta(95,101,Some(94),&[])].into();
  full.bootstrap(&Snapshot{last:100,requested:2,bids:vec![(60_000.0,1.0),(59_990.0,1.0)],asks:vec![(60_010.0,1.0)]},&buffered).unwrap();
  full.apply(&delta(102,102,Some(101),&[(59_600.0,2.0)])).unwrap();
  assert!(full.knows(Side::Bid,59_600.0)&&!full.knows(Side::Bid,59_700.0));
 }

 /// 逐条加一的流内快照序号回到 1（交易所重启）：整本重来，不算倒退；别的规则序号倒退照样断档。
 #[test] fn a_strict_snapshot_numbered_one_is_a_full_reset() {
  let mut book=LocalBook::new(Sequence::StrictIncrementing,true);
  book.replace(&snap(500,&[(99.0,1.0)],&[(101.0,1.0)])).unwrap();
  book.apply(&delta(501,501,None,&[(98.0,2.0)])).unwrap();
  assert_eq!(book.replace(&snap(1,&[(97.0,4.0)],&[(103.0,1.0)])),Ok(()),"序号 1：整本重来");
  assert_eq!(book.quality,Quality::Ready);
  assert_eq!((book.quantity(Side::Bid,98.0),book.quantity(Side::Bid,97.0)),(0.0,4.0),"旧簿清掉、换成新快照");
  assert_eq!(book.apply(&delta(2,2,None,&[(96.0,1.0)])),Ok(()),"之后从 2 接着加一");
  assert_eq!(book.replace(&snap(1,&[(97.0,4.0)],&[(103.0,1.0)])),Ok(()),"再重启一次也一样");
  assert_eq!(book.apply(&delta(3,3,None,&[])),Err(Gap),"从 1 跳到 3：断档");
  // 倒退但不是 1：断档。
  book.replace(&snap(10,&[(99.0,1.0)],&[(101.0,1.0)])).unwrap();
  assert_eq!(book.replace(&snap(9,&[(99.0,1.0)],&[(101.0,1.0)])),Err(Gap));
  // 只有逐条加一的规则认 1：上一条终号相等的规则序号回到 1 照样断档。
  let mut exact=LocalBook::new(Sequence::PreviousFinalExact,true);
  exact.replace(&snap(10,&[(99.0,1.0)],&[(101.0,1.0)])).unwrap();
  assert_eq!(exact.replace(&snap(1,&[(99.0,1.0)],&[(101.0,1.0)])),Err(Gap));
 }

 /// 每帧整本快照：时刻倒退的迟到帧忽略、簿不动；就绪时刻从第一帧算起，不随每帧刷新；只给前 N 档时最深一档以外不知道。
 #[test] fn snapshot_only_ignores_late_frames_and_keeps_its_ready_time() {
  let mut b=VenueBook::new(VenueInfo::test("venue-c:usdtPerp:BTC","BTC","usdtPerp",Notional::Linear(1.0),Sequence::SnapshotOnly,true,true));
  assert_eq!(b.opened(1),Action::None,"快照在流里");
  let frame=|time:i64,bid:f64|Message::Snapshot(Snapshot{last:time,requested:3,bids:vec![(bid,1.0),(bid-10.0,1.0),(bid-20.0,1.0)],asks:vec![(bid+10.0,1.0)]});
  assert_eq!(b.ingest(frame(1_000,100.0),5_000),Action::None);
  assert_eq!(b.ready_since(),Some(5_000));
  assert_eq!(b.ingest(frame(2_000,110.0),6_000),Action::None);
  assert_eq!(b.ready_since(),Some(5_000),"就绪时刻不随每帧刷新");
  assert!(b.knows(Side::Bid,90.0)&&!b.knows(Side::Bid,80.0),"三档满窗：最深一档 90 以外不知道");
  assert_eq!(b.ingest(frame(1_500,100.0),7_000),Action::None,"时刻倒退：忽略");
  assert!(b.is_ready());
  assert_eq!(b.ready_since(),Some(5_000));
  assert_eq!(b.depth_usd(10_000.0),Some(110.0+100.0+90.0+120.0),"簿还是 2000 那一帧");
  // 断线重来：就绪时刻重新算。
  b.closed();
  b.opened(2);
  assert_eq!(b.ingest(frame(3_000,110.0),9_000),Action::None);
  assert_eq!(b.ready_since(),Some(9_000));
 }

 #[test] fn bucket_floors_and_snaps_float_noise() {
  assert_eq!(bucket_index(1590.4,1.0),1590);
  assert_eq!(bucket_index(64_199.9,100.0),641);
  assert_eq!(bucket_index(0.3,0.1),3,"0.3 / 0.1 = 2.9999999999999996 要就近取成 3");
  assert_eq!(bucket_index(-0.5,1.0),-1);
 }
}
