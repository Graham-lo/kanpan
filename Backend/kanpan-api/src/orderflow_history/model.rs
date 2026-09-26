//! 逐单模型：照 KanpanCore 的 `OrderFlowModel.swift` 逐条移植（服务端只按默认门槛跟踪）。
//!
//! * 一条大单 = 某本簿 × 某一侧 × 某个价格桶，这一桶的美元名义 ≥ 该产品的门槛就算。
//! * 出现 / 消失各要连续两次评估、首尾相隔 ≥ 300 ms；出现要 ≥ 门槛，跌到门槛 × 0.5 以下才算消失。
//!   出现时刻记第一次过门槛那一拍，结束时刻记第一次跌破那一拍。
//! * 成交只认同一本簿自己的逐笔。结束时累计成交 ≥ 消失掉的名义 × 0.8 记「已成交」，否则「已撤销」。
//! * 一本簿超过 2 分钟没就绪，它还挂着的单按最后一次看到的时刻「失联结束」。
//! * 读回（进程重启）：缺席超过 2 分钟的挂单按它最后一次看到的时刻失联结束。
//!
//! 和手机那份的差别：结束的单不留在内存里，进 `ended` 这个待写队列，写进库就丢；
//! 保留多久由库那边滚动清理管。
use super::book::{Bucket,Message,Side,Trade,VenueBook,VenueInfo,bucket_index};
use serde::Serialize;
use std::collections::{HashMap,HashSet};

/// 只看每本簿中间价两侧这么远以内的价位（10%）。
pub const SCAN_RADIUS_BPS:f64=1_000.0;
/// 一本簿连续这么久没就绪，它还挂着的单按最后一次看到的时刻结束。
pub const STALE_MS:i64=120_000;
/// 一条挂着的单连续这么久落在「本地不知道」的价位上（快照没盖到、增量也没推过），就按最后一次
/// 真看到它的时刻失联结束。看不见不等于没了，所以先等；但不能无限等——它要是在我们没连上的
/// 时候就撤了，交易所不会再为这个价位推增量，原来这条单会一直挂成「进行中」。
pub const UNKNOWN_MS:i64=600_000;
const CONFIRM_SAMPLES:u32=2;
const CONFIRM_MS:i64=300;
const EXIT_RATIO:f64=0.5;
const FILLED_RATIO:f64=0.8;

// ------------------------------------------------------------------ 名义与门槛

/// 一张合约 / 一个币值多少美元（照 `OrderFlowNotional`）。
#[derive(Clone,Copy,Debug,PartialEq)]
pub enum Notional {Linear(f64),Inverse(f64)}
impl Notional {
 pub fn usd(self,price:f64,quantity:f64)->f64 {
  let v=match self {Notional::Linear(m)=>price*quantity*m,Notional::Inverse(c)=>quantity*c};
  if v.is_finite()&&v>0.0 {v} else {0.0}
 }
}

/// 一只 base 的门槛与步长（照 `OrderFlowThresholds`）。某种产品为 None = 不订这种产品。
#[derive(Clone,Copy,Debug,Default,PartialEq,Serialize)]
#[serde(rename_all="camelCase")]
pub struct Thresholds {
 pub spot:Option<f64>,
 pub usdt_perp:Option<f64>,
 pub coin_perp:Option<f64>,
 pub delivery:Option<f64>,
 pub step:Option<f64>,
}
impl Thresholds {
 pub fn of(&self,product:&str)->Option<f64> {
  match product {"spot"=>self.spot,"usdtPerp"=>self.usdt_perp,"coinPerp"=>self.coin_perp,"delivery"=>self.delivery,_=>None}
 }
}

/// 有固定表的币：（base，现货，永续，步长）。币本位永续、交割取永续那个数。
const MAJORS:[(&str,f64,f64,f64);3]=[("BTC",1_000_000.0,5_000_000.0,100.0),("ETH",1_000_000.0,5_000_000.0,1.0),("SOL",750_000.0,2_500_000.0,0.1)];
/// 非币：只订 U 本位永续，门槛 200 万。
const TRADFI_PERPETUAL:f64=2_000_000.0;
const TRADFI_STEPS:[(&str,f64);7]=[("MU",1.0),("SNDK",1.0),("SPCX",1.0),("SKHYNIX",1.0),("SKHY",0.1),("XAU",1.0),("XAG",0.1)];
/// 表里没有的币：（币安 U 本位永续 24h 成交额下限，永续门槛，现货门槛），从高到低。
const COIN_TIERS:[(f64,f64,f64);6]=[
 (10_000_000_000.0,5_000_000.0,1_000_000.0),(2_000_000_000.0,2_500_000.0,750_000.0),(500_000_000.0,1_000_000.0,300_000.0),
 (100_000_000.0,500_000.0,150_000.0),(20_000_000.0,200_000.0,60_000.0),(0.0,100_000.0,30_000.0),
];
/// 成交额不知道时用第三档。
const UNKNOWN_TIER:usize=2;

pub fn is_major(base:&str)->bool {MAJORS.iter().any(|m|m.0==base)}

fn tier(turnover:Option<f64>)->usize {
 match turnover {
  Some(t) if t.is_finite()&&t>=0.0=>COIN_TIERS.iter().position(|row|t>=row.0).unwrap_or(COIN_TIERS.len()-1),
  _=>UNKNOWN_TIER,
 }
}

/// 默认门槛（照 `OrderFlowDefaults.thresholds`）：步长可能是 None，等前一日收盘推。
pub fn defaults(base:&str,crypto:bool,turnover:Option<f64>)->Thresholds {
 if let Some(&(_,spot,perp,step))=MAJORS.iter().find(|m|m.0==base) {
  return Thresholds{spot:Some(spot),usdt_perp:Some(perp),coin_perp:Some(perp),delivery:Some(perp),step:Some(step)};
 }
 if !crypto {
  return Thresholds{usdt_perp:Some(TRADFI_PERPETUAL),step:TRADFI_STEPS.iter().find(|s|s.0==base).map(|s|s.1),..Default::default()};
 }
 let (_,perp,spot)=COIN_TIERS[tier(turnover)];
 Thresholds{spot:Some(spot),usdt_perp:Some(perp),coin_perp:Some(perp),delivery:Some(perp),step:None}
}

// ------------------------------------------------------------------ 非币的门槛：按簿深标定（2026-09-25）

/// 簿深按中间价两侧多远算（±1%）。
pub const CALIBRATION_BPS:f64=100.0;
/// 门槛 = 簿深的这个比例，再取整到 1 / 2 / 5 × 10ⁿ。
pub const CALIBRATION_SHARE:f64=0.03;
pub const CALIBRATION_MIN:f64=50_000.0;
pub const CALIBRATION_MAX:f64=2_000_000.0;
/// 簿没有全部拿到首个快照时，最多等这么久（有一本就算）。
pub const CALIBRATION_WAIT_MS:i64=8_000;

/// 线性距离最近的 1 / 2 / 5 × 10ⁿ；平局取小的那个。非正数或非有限数回 None。
///
/// 手机那份（Swift）用同一个公式，两边的数必须逐位一致：候选按从小到大比、只有严格更近才换。
pub fn round125(x:f64)->Option<f64> {
 if !x.is_finite()||x<=0.0 {return None}
 let decade=10f64.powi(x.log10().floor() as i32);
 let mut best:Option<f64>=None;
 for c in [1.0,2.0,5.0,10.0] {
  let v=c*decade;
  if best.is_none_or(|b|(v-x).abs()<(b-x).abs()) {best=Some(v)}
 }
 best
}

/// 非币（`crypto == false` 且不在 `MAJORS`）的 U 本位永续默认门槛：
/// T = round125(0.03 × D)，夹在 [5 万, 200 万]。D 为各簿中间价 ±1% 以内买卖两侧美元名义之和。
/// 没有簿（或簿深为 0）回退 200 万（`TRADFI_PERPETUAL`）。
pub fn calibrated_threshold(depth_usd:f64)->f64 {
 match round125(CALIBRATION_SHARE*depth_usd) {
  Some(t)=>t.clamp(CALIBRATION_MIN,CALIBRATION_MAX),
  None=>TRADFI_PERPETUAL,
 }
}

/// 收盘 × 0.1% 最接近的 1 / 2 / 5 × 10ⁿ，且不小于最小价格步长（照 `BucketScheme.derivedStep`）。
pub fn derived_step(close:f64,tick:Option<f64>)->Option<f64> {
 if !close.is_finite()||close<=0.0 {return None}
 let target=close*0.001;
 let decade=10f64.powf(target.log10().floor());
 let mut best=[0.5,1.0,2.0,5.0,10.0].iter().map(|c|c*decade).min_by(|a,b|(a-target).abs().total_cmp(&(b-target).abs()))?;
 if let Some(t)=tick.filter(|t|t.is_finite()&&*t>0.0) {if best<t {best=t}}
 (best.is_finite()&&best>0.0).then_some(best)
}

/// 前一个 UTC 日的零点。
pub fn reference_day(now:i64)->i64 {const DAY:i64=86_400_000;now.div_euclid(DAY)*DAY-DAY}

// ------------------------------------------------------------------ 大单

#[derive(Clone,Copy,Debug,PartialEq,Eq,Serialize)]
#[serde(rename_all="lowercase")]
pub enum Status {Live,Filled,Cancelled,Lost}
impl Status {
 pub fn wire(self)->&'static str {match self {Status::Live=>"live",Status::Filled=>"filled",Status::Cancelled=>"cancelled",Status::Lost=>"lost"}}
 pub fn parse(text:&str)->Option<Self> {match text {"live"=>Some(Status::Live),"filled"=>Some(Status::Filled),"cancelled"=>Some(Status::Cancelled),"lost"=>Some(Status::Lost),_=>None}}
}

/// 一条大单。字段名和手机上 `BigOrder` 的属性名一致（接口直接发这个形状）。
#[derive(Clone,Debug,PartialEq,Serialize)]
#[serde(rename_all="camelCase")]
pub struct BigOrder {
 #[serde(rename="venueID")] pub venue_id:String,
 /// 交易所显示名（「币安」），和手机上的 `OrderFlowVenue.label` 一致。
 pub exchange:String,
 pub product:String,
 #[serde(serialize_with="side_wire")] pub side:Side,
 pub bucket:i64,
 pub price:f64,
 pub first_seen_ms:i64,
 pub end_ms:Option<i64>,
 pub status:Status,
 pub initial_notional:f64,
 pub notional:f64,
 pub filled_notional:f64,
 pub threshold:f64,
 pub vanished_notional:Option<f64>,
}
fn side_wire<S:serde::Serializer>(side:&Side,s:S)->Result<S::Ok,S::Error> {s.serialize_str(side.wire())}

/// 读回来的一条挂单：大单本身、存盘时的步长、最后一次看到的时刻。
#[derive(Clone,Debug,PartialEq)]
pub struct Restored {pub order:BigOrder,pub step:f64,pub seen_ms:i64}

// ------------------------------------------------------------------ 模型

type Key=(Side,i64);

#[derive(Clone,Debug)]
struct Candidate {first:i64,samples:u32,initial:f64,notional:f64,price:f64,filled:f64}

#[derive(Clone,Copy,Debug)]
struct Pending {first:i64,samples:u32,remaining:f64}

#[derive(Clone,Debug)]
/// `peak`：挂着期间见过的最大名义（读回来的按首次与最后名义取大），结束判定的分母。
/// `seen`：写库的「最后一次看到」，价位不知道的时候也往前走（重启时别因为两分钟没见就判失联）；
/// `sighted`：真在簿里看到它的最后时刻，失联结束记这个；`unknown_since`：从哪一拍起看不见它的价位。
struct Live {order:BigOrder,seen:i64,sighted:i64,unknown_since:Option<i64>,ending:Option<Pending>,peak:f64}
impl Live {
 fn new(order:BigOrder,seen:i64,peak:f64)->Self {Live{order,seen,sighted:seen,unknown_since:None,ending:None,peak}}
}

/// 一本簿以及它上面的单。`book` 为 None：读回来的单所在的簿这一轮没订（交割换季、交易所下架）。
#[derive(Default)]
struct Track {book:Option<VenueBook>,live:HashMap<Key,Live>,candidates:HashMap<Key,Candidate>,seen:Option<i64>}

pub struct Model {
 pub base:String,
 pub thresholds:Thresholds,
 tracks:HashMap<String,Track>,
 started:Option<i64>,
 /// 已结束、还没写进库的单。
 pub ended:Vec<BigOrder>,
}

fn confirmed(samples:u32,first:i64,now:i64)->bool {samples>=CONFIRM_SAMPLES&&now-first>=CONFIRM_MS}

/// 跌破退出线：消失掉的那部分里成交够八成算已成交，否则已撤销。
///
/// 消失掉的 = 挂着期间见过的最大名义（`peak`）− 结束时剩下的。不用「跌破前最后一拍」：
/// 线上实测一面 340 万的现货墙十几拍里被一点点撤到 52 万，最后一拍只差 2 万，
/// 27 万的零星成交就把它判成了「已成交」；按峰值算消失了 290 万，成交不到一成——是撤的。
/// 也不用首次名义：挂出 1M、加到 5M 再撤掉，按首次算只要成交 0.8M 就判已成交，其实 4M 是撤的。
fn end(mut order:BigOrder,at:i64,remaining:f64,peak:f64)->BigOrder {
 let vanished=(peak.max(order.notional)-remaining.max(0.0)).max(0.0);
 order.vanished_notional=Some(vanished);
 order.status=if vanished>0.0&&order.filled_notional>=vanished*FILLED_RATIO {Status::Filled} else {Status::Cancelled};
 order.end_ms=Some(order.first_seen_ms.max(at));
 order
}

/// 失联结束：不判成交 / 撤单，不记消失掉的名义。
fn end_lost(mut order:BigOrder,at:i64)->BigOrder {
 order.status=Status::Lost;
 order.end_ms=Some(order.first_seen_ms.max(at));
 order.vanished_notional=None;
 order
}

impl Model {
 pub fn new(base:&str,thresholds:Thresholds)->Self {Self{base:base.to_string(),thresholds,tracks:HashMap::new(),started:None,ended:Vec::new()}}

 /// 加一本簿（同一本加两次无事发生）。
 pub fn add_venue(&mut self,venue:VenueInfo) {
  let track=self.tracks.entry(venue.id.clone()).or_default();
  if track.book.is_none() {track.book=Some(VenueBook::new(venue));}
 }
 pub fn book_mut(&mut self,id:&str)->Option<&mut VenueBook> {self.tracks.get_mut(id).and_then(|t|t.book.as_mut())}
 pub fn venue_ids(&self)->Vec<String> {self.tracks.iter().filter(|(_,t)|t.book.is_some()).map(|(id,_)|id.clone()).collect()}
 pub fn ready_count(&self)->usize {self.tracks.values().filter(|t|t.book.as_ref().is_some_and(VenueBook::is_ready)).count()}
 /// 已就绪的簿各自中间价两侧 `bps` 以内、买卖两侧美元名义之和（非币门槛标定用）。
 pub fn depth_usd(&mut self,bps:f64)->f64 {
  self.tracks.values_mut().filter_map(|t|t.book.as_mut()).filter_map(|b|b.depth_usd(bps)).sum()
 }

 /// 不评估的时候（非币标定之前）也要把就绪簿里留存带以外的档清掉——平时这件事是评估顺手做的，
 /// 跳过评估的几分钟里簿会一直长。
 pub fn trim(&mut self) {let _=self.depth_usd(0.0);}

 /// 读回库里挂着的单：步长对不上、或缺席超过 `STALE_MS` 的按最后一次看到的时刻失联结束，其余接着跟。
 pub fn restore(&mut self,rows:Vec<Restored>,now:i64) {
  let step=self.thresholds.step;
  for Restored{order,step:saved,seen_ms} in rows {
   if order.status!=Status::Live {continue}
   let same=step.is_some_and(|s|(saved-s).abs()<=s*1e-9);
   let threshold=self.thresholds.of(&order.product);
   if !same||threshold.is_none()||now-seen_ms>=STALE_MS {self.ended.push(end_lost(order,seen_ms));continue}
   let mut order=order;
   order.threshold=threshold.unwrap_or(order.threshold);
   let track=self.tracks.entry(order.venue_id.clone()).or_default();
   let peak=order.initial_notional.max(order.notional);
   track.live.insert((order.side,order.bucket),Live::new(order,seen_ms,peak));
  }
 }

 /// 门槛或步长换了（成交额换档、跨 UTC 日重算步长）。步长变了桶号全变：挂着的单全部按此刻失联结束；
 /// 只是门槛变了：挂着的单换成新门槛接着跟（不删——库里的历史保持原样），不再订的产品上的单失联结束。
 pub fn set_thresholds(&mut self,next:Thresholds,now:i64) {
  let step_changed=next.step!=self.thresholds.step;
  self.thresholds=next;
  for track in self.tracks.values_mut() {
   track.candidates.clear();
   let keys:Vec<Key>=track.live.keys().copied().collect();
   for key in keys {
    let threshold=next.of(&track.live[&key].order.product);
    match threshold {
     Some(t) if !step_changed=>{if let Some(l)=track.live.get_mut(&key) {l.order.threshold=t;}},
     _=>if let Some(l)=track.live.remove(&key) {self.ended.push(end_lost(l.order,now));},
    }
   }
  }
 }

 /// 连接代号对得上才交给簿（旧连接迟到的帧丢掉）。
 pub fn ingest(&mut self,id:&str,connection:u64,message:Message,now:i64)->super::book::Action {
  let Some(book)=self.book_mut(id) else {return super::book::Action::None};
  if !book.accepts(connection) {return super::book::Action::None}
  book.ingest(message,now)
 }

 /// 成交走单独的连接（币安 U 本位深度与成交分两路），不看连接代号，直接记进同一本簿这一侧这个桶。
 pub fn trade(&mut self,id:&str,trade:Trade) {
  let Some(step)=self.thresholds.step else {return};
  if let Some(track)=self.tracks.get_mut(id) {Self::attribute(track,trade,step);}
 }

 fn attribute(track:&mut Track,trade:Trade,step:f64) {
  let Some(book)=track.book.as_ref() else {return};
  let usd=book.venue.notional.usd(trade.price,trade.quantity);
  if usd<=0.0 {return}
  let key=(trade.hit,bucket_index(trade.price,step));
  if let Some(l)=track.live.get_mut(&key) {l.order.filled_notional+=usd;}
  if let Some(c)=track.candidates.get_mut(&key) {c.filled+=usd;}
 }

 /// 按此刻各本簿算一轮：确认出现 / 消失、结束判定、失联清理。
 pub fn evaluate(&mut self,now:i64) {
  let Some(step)=self.thresholds.step else {return};
  let started=*self.started.get_or_insert(now);
  let thresholds=self.thresholds;
  for (id,track) in self.tracks.iter_mut() {
   let Some(book)=track.book.as_mut() else {continue};
   let Some(threshold)=thresholds.of(book.venue.product).filter(|t|*t>0.0) else {continue};
   let Some((map,mid))=book.buckets(step,SCAN_RADIUS_BPS) else {continue};
   let reach=SCAN_RADIUS_BPS/10_000.0;
   // 价格已经走出扫描半径的单：不再看它，也就判不了成交还是撤单。
   let outside=|side:Side,price:f64|match side {Side::Bid=>price<mid*(1.0-reach),Side::Ask=>price>mid*(1.0+reach)};
   let (label,product)=(book.venue.label,book.venue.product);
   track.seen=Some(now);

   // 1. 还挂着的单：还在退出线上就更新，跌破就开始确认结束。
   let exit=threshold*EXIT_RATIO;
   let live_keys:HashSet<Key>=track.live.keys().copied().collect();
   let mut finished=Vec::new();
   let mut lost=Vec::new();
   for (key,l) in track.live.iter_mut() {
    match map.get(key) {
     Some(v) if v.notional>=exit=>{l.order.notional=v.notional;l.order.price=v.price;l.peak=l.peak.max(v.notional);l.seen=now;l.sighted=now;l.unknown_since=None;l.ending=None;},
     _ if outside(key.0,l.order.price)=>lost.push(*key),
     // 这一档在快照覆盖范围以外、增量也没推过（币安 1000 档快照只盖盘口两侧 0.3%，重启 / 重连后
     // 2%–10% 外读回来的单全在这里）：看不见不等于没了，既不算消失也不开始确认，等增量推到它再判；
     // 等满 `UNKNOWN_MS` 还没推到，按最后一次真看到的时刻失联结束。
     _ if !book.knows(key.0,l.order.price)=>{
      let since=*l.unknown_since.get_or_insert(now);
      if now-since>=UNKNOWN_MS {lost.push(*key)} else {l.seen=now}
     },
     other=>{
      l.unknown_since=None;
      let mut p=l.ending.unwrap_or(Pending{first:now,samples:0,remaining:0.0});
      p.samples+=1;
      p.remaining=other.map_or(0.0,|v|v.notional);  // 确认期间还在掉就按最后一拍剩的算
      if confirmed(p.samples,p.first,now) {finished.push((*key,p));} else {l.ending=Some(p);}
     },
    }
   }
   for (key,p) in finished {
    if let Some(l)=track.live.remove(&key) {self.ended.push(end(l.order,p.first,p.remaining,l.peak));}
   }
   for key in lost {
    if let Some(l)=track.live.remove(&key) {self.ended.push(end_lost(l.order,l.sighted));}
   }

   // 2. 新过门槛的桶：确认两拍才出现。这一拍刚结束的桶这一拍不起候选（照手机那份）。
   let mut touched=HashSet::new();
   for (key,v) in map.iter().filter(|(k,v)|v.notional>=threshold&&!live_keys.contains(k)) {
    touched.insert(*key);
    let Bucket{notional,price,..}=*v;
    let c=track.candidates.entry(*key).or_insert(Candidate{first:now,samples:0,initial:notional,notional,price,filled:0.0});
    c.samples+=1;c.notional=notional;c.price=price;
    if confirmed(c.samples,c.first,now) {
     let c=track.candidates.remove(key).expect("candidate just updated");
     let order=BigOrder{venue_id:id.clone(),exchange:label.to_string(),product:product.to_string(),side:key.0,bucket:key.1,
      price:c.price,first_seen_ms:c.first,end_ms:None,status:Status::Live,initial_notional:c.initial,notional:c.notional,
      filled_notional:c.filled,threshold,vanished_notional:None};
     let peak=c.initial.max(c.notional);
     track.live.insert(*key,Live::new(order,now,peak));
    }
   }
   // 这一拍没再过门槛的候选作废（「连续」两拍）。
   track.candidates.retain(|k,_|touched.contains(k));
  }
  self.expire_stale(now,started);
 }

 /// 一本簿超过 `STALE_MS` 没就绪（或这一轮根本没订到），它还挂着的单按最后一次看到时失联结束。
 fn expire_stale(&mut self,now:i64,started:i64) {
  if now-started<STALE_MS {return}
  for track in self.tracks.values_mut() {
   if now-track.seen.unwrap_or(started)<STALE_MS||track.live.is_empty() {continue}
   for (_,l) in track.live.drain() {self.ended.push(end_lost(l.order,l.sighted));}
  }
 }

 /// 断线：簿回到「等重连」。
 pub fn closed(&mut self,id:&str,connection:u64) {
  if let Some(book)=self.book_mut(id) {book.disconnected(connection)}
 }

 /// 停止跟踪：还挂着的单按最后一次看到时失联结束。
 pub fn stop(&mut self) {
  for track in self.tracks.values_mut() {
   track.candidates.clear();
   for (_,l) in track.live.drain() {self.ended.push(end_lost(l.order,l.sighted));}
  }
 }

 /// 挂着的单与各自最后一次看到的时刻（定期写库用）。
 pub fn live(&self)->Vec<(BigOrder,i64)> {
  self.tracks.values().flat_map(|t|t.live.values().map(|l|(l.order.clone(),l.seen))).collect()
 }
 pub fn live_count(&self)->usize {self.tracks.values().map(|t|t.live.len()).sum()}
 pub fn take_ended(&mut self)->Vec<BigOrder> {std::mem::take(&mut self.ended)}
}

#[cfg(test)]
mod tests {
 use super::*;
 use super::super::book::{Sequence,Snapshot};

 const T:f64=1_000_000.0;

 fn venue(id:&str,product:&'static str,notional:Notional)->VenueInfo {
  VenueInfo{id:id.into(),exchange:"coinbase",label:"Coinbase",product,instrument:id.into(),notional,price_scale:1.0,sequence:Sequence::StrictIncrementing,in_band:true}
 }
 fn thresholds()->Thresholds {Thresholds{spot:Some(T),usdt_perp:Some(5.0*T),coin_perp:Some(5.0*T),delivery:Some(5.0*T),step:Some(100.0)}}

 /// 一本快照在流里的簿：一个模型、一本簿，`book(bids,asks)` 换整本、`trade` 喂成交。
 struct Rig {m:Model,seq:i64}
 impl Rig {
  fn new()->Self {Self::with(venue("a","spot",Notional::Linear(1.0)))}
  fn with(v:VenueInfo)->Self {
   let mut m=Model::new("BTC",thresholds());
   let id=v.id.clone();
   m.add_venue(v);
   m.book_mut(&id).unwrap().opened(1);
   Self{m,seq:0}
  }
  fn book(&mut self,id:&str,bids:&[(f64,f64)],asks:&[(f64,f64)],now:i64) {
   self.seq+=1;
   let s=Snapshot{last:self.seq,requested:1000,bids:bids.to_vec(),asks:asks.to_vec()};
   self.m.ingest(id,1,Message::Snapshot(s),now);
  }
  /// 被截断的快照：要的档数正好等于给的档数（币安 REST 那种）。
  fn truncated(&mut self,id:&str,bids:&[(f64,f64)],asks:&[(f64,f64)],now:i64) {
   self.seq+=1;
   let s=Snapshot{last:self.seq,requested:bids.len().max(asks.len()),bids:bids.to_vec(),asks:asks.to_vec()};
   self.m.ingest(id,1,Message::Snapshot(s),now);
  }
  fn delta(&mut self,id:&str,bids:&[(f64,f64)],asks:&[(f64,f64)],now:i64) {
   self.seq+=1;
   let d=super::super::book::Delta{first:self.seq,last:self.seq,prev:None,bids:bids.to_vec(),asks:asks.to_vec()};
   self.m.ingest(id,1,Message::Delta(d),now);
  }
  fn trade(&mut self,id:&str,price:f64,qty:f64,hit:Side,_now:i64) {self.m.trade(id,Trade{price,quantity:qty,hit});}
  fn live(&self)->Vec<BigOrder> {self.m.live().into_iter().map(|(o,_)|o).collect()}
 }
 // 现价 60 000：卖一 60 010；一面 1.2M 的买单墙放在 59 950（桶 599）。
 const ASK:(f64,f64)=(60_010.0,1.0);
 fn wall(usd:f64)->Vec<(f64,f64)> {vec![(60_000.0,1.0),(59_950.0,usd/59_950.0)]}

 #[test] fn appearance_needs_two_samples_three_hundred_ms_apart() {
  let mut r=Rig::new();
  r.book("a",&wall(1.2*T),&[ASK],0);
  r.m.evaluate(0);
  assert!(r.live().is_empty());
  r.m.evaluate(200);
  assert!(r.live().is_empty(),"两拍但不够 300 ms");
  r.m.evaluate(300);
  let live=r.live();
  assert_eq!(live.len(),1);
  let o=&live[0];
  assert_eq!((o.side,o.bucket,o.first_seen_ms,o.status),(Side::Bid,599,0,Status::Live));
  assert_eq!(o.venue_id,"a");assert_eq!(o.exchange,"Coinbase");
  assert!((o.initial_notional-1.2*T).abs()<1.0);
 }

 #[test] fn a_single_spike_is_not_an_order() {
  let mut r=Rig::new();
  r.book("a",&wall(1.2*T),&[ASK],0);
  r.m.evaluate(0);
  r.book("a",&wall(0.1*T),&[ASK],400);
  r.m.evaluate(400);
  r.book("a",&wall(1.2*T),&[ASK],500);
  r.m.evaluate(500);
  assert!(r.live().is_empty(),"候选断了一拍要从头数");
  r.m.evaluate(800);
  assert_eq!(r.live()[0].first_seen_ms,500);
 }

 fn appear(r:&mut Rig,usd:f64)->i64 {
  r.book("a",&wall(usd),&[ASK],0);
  r.m.evaluate(0);r.m.evaluate(300);
  assert_eq!(r.live().len(),1);
  300
 }

 #[test] fn hysteresis_keeps_a_shrunk_wall_alive() {
  let mut r=Rig::new();
  appear(&mut r,1.2*T);
  r.book("a",&wall(0.6*T),&[ASK],400);
  r.m.evaluate(400);r.m.evaluate(800);r.m.evaluate(1_200);
  let live=r.live();
  assert_eq!(live.len(),1,"跌到门槛一半以上仍是同一面墙");
  assert!((live[0].notional-0.6*T).abs()<1.0);
  assert!(r.m.ended.is_empty());
 }

 #[test] fn pulled_wall_is_cancelled_at_the_first_tick_below_the_exit_line() {
  let mut r=Rig::new();
  appear(&mut r,1.2*T);
  r.book("a",&wall(0.1*T),&[ASK],1_000);
  r.m.evaluate(1_000);
  assert!(r.m.ended.is_empty(),"消失也要两拍");
  r.m.evaluate(1_300);
  let ended=r.m.take_ended();
  assert_eq!(ended.len(),1);
  let o=&ended[0];
  assert_eq!((o.status,o.end_ms),(Status::Cancelled,Some(1_000)));
  assert!((o.vanished_notional.unwrap()-1.1*T).abs()<1.0);
  assert!(r.live().is_empty());
 }

 #[test] fn eaten_wall_is_filled_by_its_own_trades() {
  let mut r=Rig::new();
  appear(&mut r,1.2*T);
  r.trade("a",59_950.0,1.0*T/59_950.0,Side::Bid,500);
  r.book("a",&[(59_900.0,1.0)],&[ASK],600);
  r.m.evaluate(600);r.m.evaluate(900);
  let o=&r.m.ended[0];
  assert_eq!(o.status,Status::Filled);
  assert!((o.filled_notional-1.0*T).abs()<1.0);
 }

 #[test] fn fills_on_the_other_side_or_another_bucket_do_not_count() {
  let mut r=Rig::new();
  appear(&mut r,1.2*T);
  r.trade("a",59_950.0,1.0*T/59_950.0,Side::Ask,500);
  r.trade("a",59_850.0,1.0*T/59_850.0,Side::Bid,500);
  r.book("a",&[(60_000.0,1.0)],&[ASK],600);
  r.m.evaluate(600);r.m.evaluate(900);
  assert_eq!(r.m.ended[0].status,Status::Cancelled);
  assert_eq!(r.m.ended[0].filled_notional,0.0);
 }

 #[test] fn fills_of_another_venue_are_not_credited() {
  let mut r=Rig::new();
  let mut other=venue("b","spot",Notional::Linear(1.0));other.instrument="b".into();
  r.m.add_venue(other);
  r.m.book_mut("b").unwrap().opened(1);
  r.book("b",&[(60_000.0,1.0)],&[ASK],0);
  appear(&mut r,1.2*T);
  r.trade("b",59_950.0,2.0*T/59_950.0,Side::Bid,500);
  assert_eq!(r.live()[0].filled_notional,0.0);
 }

 #[test] fn candidate_fills_carry_into_the_order() {
  let mut r=Rig::new();
  r.book("a",&wall(1.2*T),&[ASK],0);
  r.m.evaluate(0);
  r.trade("a",59_950.0,0.2*T/59_950.0,Side::Bid,100);
  r.m.evaluate(300);
  assert!((r.live()[0].filled_notional-0.2*T).abs()<1.0);
 }

 #[test] fn verdict_uses_the_vanished_part_not_the_initial_notional() {
  // 挂 1.2M、加到 5M 再撤：只成交 1M，不能判已成交。
  let mut r=Rig::new();
  appear(&mut r,1.2*T);
  r.book("a",&wall(5.0*T),&[ASK],400);r.m.evaluate(400);
  r.trade("a",59_950.0,1.0*T/59_950.0,Side::Bid,500);
  r.book("a",&[(60_000.0,1.0)],&[ASK],600);r.m.evaluate(600);r.m.evaluate(900);
  assert_eq!(r.m.ended[0].status,Status::Cancelled);
  // 先撤到 0.6M 再被吃掉 0.5M：消失的 1.15M 里成交 0.5M，不到八成——撤的多，判已撤销（成交比例 43%）。
  let mut r=Rig::new();
  appear(&mut r,1.2*T);
  r.book("a",&wall(0.6*T),&[ASK],400);r.m.evaluate(400);
  r.trade("a",59_950.0,0.5*T/59_950.0,Side::Bid,500);
  r.book("a",&wall(0.05*T),&[ASK],600);r.m.evaluate(600);r.m.evaluate(900);
  let o=&r.m.ended[0];
  assert_eq!(o.status,Status::Cancelled);
  assert!((o.vanished_notional.unwrap()-1.15*T).abs()<1.0);
 }

 #[test] fn gradually_pulled_wall_with_a_few_fills_is_cancelled() {
  // 线上实测的形状：3.4M 的墙十几拍里一点点撤到 0.52M（每拍都在退出线上），零星成交 0.27M，
  // 最后一拍才跌破。按「跌破前最后一拍 − 剩下的」只消失了 2 万，会误判已成交；按峰值算是撤的。
  let mut r=Rig::new();
  appear(&mut r,3.4*T);
  r.trade("a",59_950.0,0.27*T/59_950.0,Side::Bid,350);
  let mut now=400;
  for k in 0..12 {
   r.book("a",&wall((3.4-0.24*(k as f64+1.0))*T),&[ASK],now);r.m.evaluate(now);now+=100;
  }
  assert_eq!(r.live().len(),1,"0.52M 仍在退出线上");
  r.book("a",&wall(0.1*T),&[ASK],now);r.m.evaluate(now);r.m.evaluate(now+300);
  let o=&r.m.ended[0];
  assert_eq!(o.status,Status::Cancelled);
  assert!((o.vanished_notional.unwrap()-3.3*T).abs()<1.0);
  assert!((o.filled_notional-0.27*T).abs()<1.0);
 }

 #[test] fn a_wall_that_grows_then_is_eaten_is_filled_against_its_peak() {
  let mut r=Rig::new();
  appear(&mut r,1.2*T);
  r.book("a",&wall(3.0*T),&[ASK],400);r.m.evaluate(400);
  r.trade("a",59_950.0,2.6*T/59_950.0,Side::Bid,500);
  r.book("a",&wall(0.1*T),&[ASK],600);r.m.evaluate(600);r.m.evaluate(900);
  let o=&r.m.ended[0];
  assert_eq!(o.status,Status::Filled);
  assert!((o.vanished_notional.unwrap()-2.9*T).abs()<1.0);
 }

 #[test] fn inverse_contracts_count_contracts_times_face_value() {
  let mut r=Rig::with(venue("c","coinPerp",Notional::Inverse(100.0)));
  r.book("c",&[(60_000.0,1.0),(59_950.0,60_000.0)],&[ASK],0);
  r.m.evaluate(0);r.m.evaluate(300);
  let live=r.live();
  assert_eq!(live.len(),1);
  assert!((live[0].notional-6.0*T).abs()<1.0);
  assert_eq!(live[0].threshold,5.0*T);
 }

 #[test] fn a_disconnected_book_ends_its_orders_lost_at_the_last_sight() {
  let mut r=Rig::new();
  appear(&mut r,1.2*T);
  r.m.evaluate(1_000);
  r.m.closed("a",1);
  r.m.evaluate(60_000);
  assert!(r.m.ended.is_empty(),"两分钟以内不动");
  r.m.evaluate(121_000);
  let o=&r.m.ended[0];
  assert_eq!((o.status,o.end_ms,o.vanished_notional),(Status::Lost,Some(1_000),None));
 }

 #[test] fn stale_connection_frames_are_dropped() {
  let mut r=Rig::new();
  r.m.book_mut("a").unwrap().opened(2);
  r.book("a",&wall(1.2*T),&[ASK],0);
  r.m.evaluate(0);r.m.evaluate(300);
  assert!(r.live().is_empty(),"代号 1 的帧在代号 2 的连接上不作数");
 }

 #[test] fn restore_ends_long_absent_orders_and_continues_the_rest() {
  let mut r=Rig::new();
  let order=|bucket:i64|BigOrder{venue_id:"a".into(),exchange:"Coinbase".into(),product:"spot".into(),side:Side::Bid,bucket,
   price:59_950.0,first_seen_ms:0,end_ms:None,status:Status::Live,initial_notional:1.2*T,notional:1.2*T,filled_notional:0.0,threshold:T,vanished_notional:None};
  r.m.restore(vec![
   Restored{order:order(599),step:100.0,seen_ms:500_000},
   Restored{order:order(598),step:100.0,seen_ms:100_000},
   Restored{order:order(597),step:50.0,seen_ms:500_000},
  ],600_000);
  assert_eq!(r.m.ended.len(),2);
  assert!(r.m.ended.iter().all(|o|o.status==Status::Lost));
  assert_eq!(r.m.ended.iter().find(|o|o.bucket==598).unwrap().end_ms,Some(100_000));
  r.book("a",&wall(1.2*T),&[ASK],600_000);
  r.m.evaluate(600_000);
  let live=r.live();
  assert_eq!(live.len(),1);
  assert_eq!((live[0].bucket,live[0].first_seen_ms),(599,0),"读回来的那条接着跟，不另起一条");
 }

 #[test] fn restored_orders_beyond_snapshot_coverage_wait_for_a_delta() {
  // 线上实测：重启后币安 1000 档快照只盖盘口两侧 0.3%，读回来的 190 条 2%–10% 外的单
  // 一分钟内全被判成「已撤销、剩 0」。覆盖范围以外的档：不知道就不判，增量推到它再说。
  let mut r=Rig::new();
  let order=BigOrder{venue_id:"a".into(),exchange:"Coinbase".into(),product:"spot".into(),side:Side::Bid,bucket:595,
   price:59_500.0,first_seen_ms:0,end_ms:None,status:Status::Live,initial_notional:1.2*T,notional:1.2*T,filled_notional:0.0,threshold:T,vanished_notional:None};
  r.m.restore(vec![Restored{order,step:100.0,seen_ms:599_900}],600_000);
  r.truncated("a",&[(60_000.0,1.0),(59_990.0,1.0)],&[ASK],600_000);
  r.m.evaluate(600_000);r.m.evaluate(600_300);r.m.evaluate(600_600);
  assert!(r.m.ended.is_empty(),"快照没盖到 59 500：不判撤单");
  let live=r.m.live();
  assert_eq!(live.len(),1);
  assert_eq!(live[0].1,600_600,"等着的时候按看到过算，下次重启不会因为「两分钟没见」判失联");
  // 增量推到它、还在：接着跟，名义更新。
  r.delta("a",&[(59_500.0,1.5*T/59_500.0)],&[],600_700);
  r.m.evaluate(600_700);
  assert!((r.live()[0].notional-1.5*T).abs()<1.0);
  // 增量推成 0：确实没了，两拍后按撤单结束、消失的按峰值算。
  r.delta("a",&[(59_500.0,0.0)],&[],601_000);
  r.m.evaluate(601_000);r.m.evaluate(601_300);
  let o=&r.m.ended[0];
  assert_eq!((o.status,o.end_ms),(Status::Cancelled,Some(601_000)));
  assert!((o.vanished_notional.unwrap()-1.5*T).abs()<1.0);
  assert!(r.live().is_empty());
  // 一直没有增量推到它：不能永远挂着。等满 UNKNOWN_MS 按读回来时的最后一次看到失联结束。
  let mut r=Rig::new();
  let order=BigOrder{venue_id:"a".into(),exchange:"Coinbase".into(),product:"spot".into(),side:Side::Bid,bucket:595,
   price:59_500.0,first_seen_ms:0,end_ms:None,status:Status::Live,initial_notional:1.2*T,notional:1.2*T,filled_notional:0.0,threshold:T,vanished_notional:None};
  r.m.restore(vec![Restored{order,step:100.0,seen_ms:599_900}],600_000);
  r.truncated("a",&[(60_000.0,1.0),(59_990.0,1.0)],&[ASK],600_000);
  r.m.evaluate(600_000);
  r.m.evaluate(600_000+UNKNOWN_MS-1);
  assert!(r.m.ended.is_empty(),"还在等");
  r.m.evaluate(600_000+UNKNOWN_MS);
  let o=&r.m.ended[0];
  assert_eq!((o.status,o.end_ms),(Status::Lost,Some(599_900)),"按真看到的最后一刻结束，不按等待期间刷新的那个");
  assert!(r.live().is_empty());
  // 覆盖范围以内的不受影响：快照里没有就是没有。
  let mut r=Rig::new();
  let order=BigOrder{venue_id:"a".into(),exchange:"Coinbase".into(),product:"spot".into(),side:Side::Bid,bucket:599,
   price:59_995.0,first_seen_ms:0,end_ms:None,status:Status::Live,initial_notional:1.2*T,notional:1.2*T,filled_notional:0.0,threshold:T,vanished_notional:None};
  r.m.restore(vec![Restored{order,step:100.0,seen_ms:599_900}],600_000);
  r.truncated("a",&[(60_000.0,1.0),(59_990.0,1.0)],&[ASK],600_000);
  r.m.evaluate(600_000);r.m.evaluate(600_300);
  assert_eq!(r.m.ended[0].status,Status::Cancelled);
 }

#[test] fn an_order_the_price_ran_away_from_is_lost_not_cancelled() {
  // 墙在 59 950；价格涨到 67 000，扫描半径（10%）的下沿是 60 300，墙已经在外面了。
  // 原来它和「没了」一样走撤单确认，两拍后判成「已撤销、剩 0」——其实只是不看了。
  let mut r=Rig::new();
  appear(&mut r,1.2*T);
  r.m.evaluate(1_000);
  r.book("a",&[(66_990.0,1.0),(59_950.0,1.2*T/59_950.0)],&[(67_010.0,1.0)],2_000);
  r.m.evaluate(2_000);
  let o=&r.m.ended[0];
  assert_eq!((o.status,o.end_ms,o.vanished_notional),(Status::Lost,Some(1_000),None));
  assert!(r.live().is_empty());
 }

 #[test] fn step_change_ends_everything_threshold_change_keeps_it() {
  let mut r=Rig::new();
  appear(&mut r,1.2*T);
  let mut next=thresholds();next.spot=Some(2.0*T);
  r.m.set_thresholds(next,1_000);
  assert_eq!(r.live()[0].threshold,2.0*T);
  assert!(r.m.ended.is_empty());
  next.step=Some(50.0);
  r.m.set_thresholds(next,2_000);
  assert!(r.live().is_empty());
  assert_eq!(r.m.ended[0].end_ms,Some(2_000));
 }

 #[test] fn defaults_follow_the_client_table() {
  assert_eq!(defaults("BTC",true,None),Thresholds{spot:Some(T),usdt_perp:Some(5.0*T),coin_perp:Some(5.0*T),delivery:Some(5.0*T),step:Some(100.0)});
  assert_eq!(defaults("XAU",false,None),Thresholds{usdt_perp:Some(2.0*T),step:Some(1.0),..Default::default()});
  assert_eq!(defaults("TSLA",false,None).step,None);
  assert_eq!(defaults("DOGE",true,Some(3e9)).usdt_perp,Some(2.5*T));
  assert_eq!(defaults("DOGE",true,None).spot,Some(300_000.0));
  assert_eq!(defaults("X",true,Some(1.0)).spot,Some(30_000.0));
  assert_eq!(derived_step(65_000.0,None),Some(50.0));
  assert_eq!(derived_step(2.4,Some(0.01)),Some(0.01));
  assert_eq!(derived_step(0.000_012,Some(1e-9)).map(|v|(v*1e9).round()),Some(10.0));
  assert_eq!(reference_day(86_400_000*3+5),86_400_000*2);
 }

 /// 手机那份用同一组向量对账。
 #[test] fn calibration_vectors() {
  assert_eq!(round125(570_000.0),Some(500_000.0));
  assert_eq!(round125(760_000.0),Some(1_000_000.0));
  assert_eq!(round125(300_000.0),Some(200_000.0),"平局取小（和 500k 比，200k 更近）");
  assert_eq!(round125(150_000.0),Some(100_000.0),"真平局：100k 与 200k 一样远，取小");
  assert_eq!(round125(750_000.0),Some(500_000.0),"真平局：500k 与 1M 一样远，取小");
  assert_eq!(round125(1_000_000.0),Some(1_000_000.0));
  assert_eq!(round125(6_000_000.0),Some(5_000_000.0));
  assert_eq!(round125(0.0),None);
  assert_eq!(calibrated_threshold(19_000_000.0),500_000.0);
  assert_eq!(calibrated_threshold(2_000_000.0),50_000.0);
  assert_eq!(calibrated_threshold(200_000_000.0),2_000_000.0,"6M → 5M → 夹到 2M");
  assert_eq!(calibrated_threshold(100_000.0),50_000.0,"3000 → 夹到 5 万");
  assert_eq!(calibrated_threshold(0.0),2_000_000.0,"没有簿深回退 200 万");
 }

 #[test] fn order_json_uses_client_field_names() {
  let o=BigOrder{venue_id:"binance:usdtPerp:BTCUSDT".into(),exchange:"币安".into(),product:"usdtPerp".into(),side:Side::Ask,bucket:651,
   price:65_100.0,first_seen_ms:1,end_ms:Some(2),status:Status::Filled,initial_notional:5e6,notional:6e6,filled_notional:5e6,threshold:5e6,vanished_notional:Some(6e6)};
  let v=serde_json::to_value(&o).unwrap();
  for k in ["venueID","exchange","product","side","bucket","price","firstSeenMs","endMs","status","initialNotional","notional","filledNotional","threshold","vanishedNotional"] {assert!(v.get(k).is_some(),"{k}")}
  assert_eq!(v["side"],"ask");assert_eq!(v["status"],"filled");
 }
}
