//! 自选五分钟波动提醒的服务端那一半（P3.1）。
//!
//! 判定和客户端 `KanpanCore/Sources/KanpanCore/Alerts/WatchMove.swift` 一字对一字，只有
//! 一种，没有口径可选：
//!
//! - **五分钟涨跌幅** = 现价 ÷ 「开盘时刻 = 当前这一根 − 5 分钟」那一根 1 分钟 K 线的
//!   收盘价 − 1。两边都拿币安 1m K 线当参照，前台是 app 自己的行情流，这里是评估器那条
//!   组合流（`alerts.rs`），同一个上游。
//! - **缺口不冒充零波动**：那一根没有（刚开始盯、断过线），这一口就不判——既不响，也不
//!   把「已经回到阈值以内」记上。
//! - **去重**：同一个人、同品种、同方向、同一个对齐的五分钟窗口只响一次；响过之后要先
//!   回到阈值以内才重新上膛。
//!
//! 开关与幅度是同步设置（`settings/chart` 的 `watchMoveAlert` / `watchMoveThreshold`），
//! 盯哪几只是这个人的自选（`favorites` 集合里所有没删的品种）。关掉开关，下一轮刷新
//! （十秒内）这个人的状态整份丢掉，之后一声都不会再响。
use crate::{AppState,apns::Apns,error::Result};
use serde_json::Value;
use sqlx::{Postgres,Transaction};
use std::collections::{BTreeMap,BTreeSet};
use uuid::Uuid;

pub const BAR_MS:i64=60_000;
pub const WINDOW_MS:i64=300_000;
/// 出厂幅度（百分数）。
pub const DEFAULT_THRESHOLD:f64=1.5;
/// 用户能填的范围（百分数），`sync_validation.rs` 卡的是同一个区间。
pub const THRESHOLD_RANGE:(f64,f64)=(0.1,50.0);

/// 把幅度夹进合法区间；读不出来的退回出厂值。
pub fn clamp_threshold(v:f64)->f64 {
 if !v.is_finite() {return DEFAULT_THRESHOLD}
 v.clamp(THRESHOLD_RANGE.0,THRESHOLD_RANGE.1)
}

#[derive(Clone,Copy,Debug,PartialEq,Eq,PartialOrd,Ord)]
pub enum Direction {Up,Down}

#[derive(Clone,Debug,PartialEq)]
pub struct Event {pub symbol:String,pub direction:Direction,pub change:f64,pub price:f64,pub window:i64}

/// 一只品种最近几根 1 分钟收盘价。
#[derive(Default,Clone,Debug)]
struct Series {closes:BTreeMap<i64,f64>,current_open:Option<i64>,current_close:Option<f64>}
impl Series {
 /// 喂一口价，返回五分钟涨跌幅（小数）；参照那一根缺着就是 `None`。
 fn observe(&mut self,bar_open:i64,price:f64,closed:bool)->Option<f64> {
  if !price.is_finite()||price<=0.0 {return None}
  if self.current_open.is_some_and(|open|bar_open<open) {return None}
  if let (Some(open),Some(close))=(self.current_open,self.current_close) {
   if bar_open>open {self.closes.insert(open,close);}
  }
  self.current_open=Some(bar_open);
  self.current_close=Some(price);
  if closed {self.closes.insert(bar_open,price);}
  self.closes.retain(|open,_|*open>=bar_open-7*BAR_MS);
  let reference=*self.closes.get(&(bar_open-WINDOW_MS))?;
  (reference>0.0).then(||price/reference-1.0)
 }
}

/// 一个方向上的闸。
#[derive(Clone,Debug)]
struct Gate {armed:bool,last_window:Option<i64>}
impl Default for Gate {fn default()->Self {Self{armed:true,last_window:None}}}
impl Gate {
 fn pass(&mut self,signed:f64,threshold:f64,window:i64)->bool {
  if signed<threshold {self.armed=true;return false}
  if !self.armed||self.last_window==Some(window) {return false}
  self.armed=false;self.last_window=Some(window);true
 }
}

/// 一个人的全部状态。
#[derive(Default,Clone,Debug)]
pub struct Tracker {series:BTreeMap<String,Series>,gates:BTreeMap<(String,Direction),Gate>}
impl Tracker {
 /// `threshold` 是百分数（1.5 = 1.5%）。
 pub fn observe(&mut self,symbol:&str,bar_open:i64,price:f64,closed:bool,threshold:f64)->Option<Event> {
  let key=symbol.to_uppercase();
  let change=self.series.entry(key.clone()).or_default().observe(bar_open,price,closed)?;
  let limit=clamp_threshold(threshold)/100.0;
  let window=bar_open-bar_open.rem_euclid(WINDOW_MS);
  let mut fired=None;
  for direction in [Direction::Up,Direction::Down] {
   let signed=if direction==Direction::Up {change} else {-change};
   let gate=self.gates.entry((key.clone(),direction)).or_default();
   if gate.pass(signed,limit,window)&&fired.is_none() {
    fired=Some(Event{symbol:key.clone(),direction,change,price,window});
   }
  }
  fired
 }
 /// 只留这几只（自选改了）。拿掉的连同闸一起忘掉。
 pub fn keep(&mut self,symbols:&BTreeSet<String>) {
  self.series.retain(|s,_|symbols.contains(s));
  self.gates.retain(|(s,_),_|symbols.contains(s));
 }
 /// 断过线：收盘价全扔（断线前那一根的「收盘」其实不是收盘），闸留着。
 pub fn forget_prices(&mut self) {self.series.clear()}
}

/// 品种的短名：去掉计价币后缀。后缀表只有一份（`instruments`）；以前这里抄了四项，
/// `ETHFDUSD`、`XTUSD` 的通知标题就成了整串代号。
pub fn short(symbol:&str)->&str {crate::instruments::base(symbol)}
/// 通知标题：「BTC 五分钟涨 1.82%」。客户端 `WatchMove.title` 一字不差。
pub fn title(symbol:&str,event:&Event)->String {
 let short=short(symbol);
 let verb=if event.direction==Direction::Up {"涨"} else {"跌"};
 format!("{short} 五分钟{verb} {:.2}%",event.change.abs()*100.0)
}

/// 一个开着自选波动提醒的人：幅度 + 自选里的品种。
#[derive(Clone,Debug,PartialEq)]
pub struct Mover {pub owner:Uuid,pub threshold:f64,pub symbols:BTreeSet<String>}

/// 这个人开着没有；开着就把幅度与**这家交易所**的自选一起读回来。在 `alerts::load`
/// 那个个人事务里调用，每家交易所的评估器各读各的（币安的组合流订不了 `BTC-USD`）。
/// 老客户端写的自选没有 `venue` 字段，按币安算。
pub async fn load_mover(tx:&mut Transaction<'_,Postgres>,owner:Uuid,venue:&str)->Result<Option<Mover>> {
 let settings=crate::sync::settings_body(tx,owner).await?;
 let Some(threshold)=enabled(settings.as_ref()) else {return Ok(None)};
 let favorites=crate::sync::live_objects(tx,owner,crate::sync::FAVORITES).await?;
 Ok(Some(Mover{owner,threshold,symbols:favorite_symbols(&favorites,venue)}))
}
/// 自选里这家交易所的品种（大写、去重）。老客户端写的自选没有 `venue`，按裸代号的默认交易所（币安）算。
fn favorite_symbols(favorites:&[crate::sync::Object],venue:&str)->BTreeSet<String> {
 favorites.iter()
  .filter(|o|o.body.get("venue").and_then(Value::as_str).unwrap_or(crate::instruments::DEFAULT_VENUE)==venue)
  .filter_map(|o|o.body.get("symbol").and_then(Value::as_str))
  .filter(|s|!s.is_empty()).map(str::to_uppercase).collect()
}
/// 设置里开着就返回幅度，关着（或者从没设过——出厂是关）就是 `None`。
fn enabled(settings:Option<&Value>)->Option<f64> {
 let body=settings?;
 if body.get("watchMoveAlert").and_then(Value::as_bool)!=Some(true) {return None}
 Some(clamp_threshold(body.get("watchMoveThreshold").and_then(Value::as_f64).unwrap_or(DEFAULT_THRESHOLD)))
}

/// 评估器里所有人的波动状态。活在重连之外（和 `closes` 一样），闸不因断线而复位。
#[derive(Default)]
pub struct Movers {people:BTreeMap<Uuid,(Mover,Tracker)>}
impl Movers {
 /// 一轮刷新之后：关掉的人整份丢掉，自选改了的人只留现在的品种。
 pub fn refresh(&mut self,fresh:&[Mover]) {
  self.people.retain(|owner,_|fresh.iter().any(|m|m.owner==*owner));
  for mover in fresh {
   let entry=self.people.entry(mover.owner).or_insert_with(||(mover.clone(),Tracker::default()));
   entry.0=mover.clone();
   entry.1.keep(&mover.symbols);
  }
 }
 /// 断线重连：各人的收盘价都作废。
 pub fn forget_prices(&mut self) {for (_,tracker) in self.people.values_mut() {tracker.forget_prices()}}
 /// 所有人盯着的品种并起来（订阅要用）。
 pub fn symbols(&self)->BTreeSet<String> {self.people.values().flat_map(|(m,_)|m.symbols.iter().cloned()).collect()}
 /// 一帧 K 线：谁的哪只响了。
 pub fn observe(&mut self,symbol:&str,bar_open:i64,price:f64,closed:bool)->Vec<(Uuid,Event)> {
  let mut out=vec![];
  for (owner,(mover,tracker)) in &mut self.people {
   if !mover.symbols.contains(symbol) {continue}
   if let Some(event)=tracker.observe(symbol,bar_open,price,closed,mover.threshold) {out.push((*owner,event))}
  }
  out
 }
}

/// 响了：推给这个人的设备。没有 APNs 密钥时只留一行日志——前台那一半照样由 app 自己响。
/// `market` 是这一支评估器的 `binance/usd_m` / `coinbase/spot`，决定点开去哪一家的那只。
pub async fn notify(s:&AppState,apns:Option<&Apns>,owner:Uuid,event:&Event,market:&str) {
 let title=title(&event.symbol,event);
 let Some(apns)=apns else {
  tracing::info!("{title} (watch move); not pushed (no APNs key)");
  return
 };
 let notice=crate::alerts::Notice{title,body:format!("现价 {}",crate::alerts::money(event.price)),link:format!("hkline://symbol/{}",crate::alerts::symbol_path(market,&event.symbol)),kind:"watchMove"};
 if let Err(e)=crate::alerts::notify(s,apns,owner,&notice).await {tracing::warn!("A watch-move notice could not be pushed ({e:?})")}
}

#[cfg(test)]
mod tests {
 use super::*;
 use serde_json::json;

 const M0:i64=1_800_000_000_000-1_800_000_000_000%300_000;
 fn minute(n:i64)->i64 {M0+n*60_000}
 fn warm(t:&mut Tracker,symbol:&str) {for n in 0..5 {t.observe(symbol,minute(n),100.0,true,1.5);}}

 #[test] fn an_upward_move_fires_once_as_up() {
  let mut t=Tracker::default();warm(&mut t,"BTCUSDT");
  let e=t.observe("BTCUSDT",minute(5),101.6,false,1.5).expect("fires");
  assert_eq!(e.direction,Direction::Up);
  assert!((e.change-0.016).abs()<1e-9);
  assert_eq!(e.window,minute(5));
  assert_eq!(title("BTCUSDT",&e),"BTC 五分钟涨 1.60%");
 }
 #[test] fn a_downward_move_fires_as_down() {
  let mut t=Tracker::default();warm(&mut t,"BTCUSDT");
  let e=t.observe("BTCUSDT",minute(5),98.4,false,1.5).expect("fires");
  assert_eq!(e.direction,Direction::Down);
  assert_eq!(title("BTCUSDT",&e),"BTC 五分钟跌 1.60%");
  assert_eq!(title("ETHUSDC",&e),"ETH 五分钟跌 1.60%");
  assert_eq!(short("USDT"),"USDT");
  // Coinbase 现货：和客户端 `SymbolInfo.placeholder` 一样按横杠拆。
  assert_eq!(title("BTC-USD",&e),"BTC 五分钟跌 1.60%");
  assert_eq!(short("-USD"),"-USD");
 }
 #[test] fn a_small_move_is_quiet() {
  let mut t=Tracker::default();warm(&mut t,"BTCUSDT");
  assert!(t.observe("BTCUSDT",minute(5),101.4,false,1.5).is_none());
  assert!(t.observe("BTCUSDT",minute(5),98.6,false,1.5).is_none());
 }
 /// 缺口不当零波动，也不当大波动。
 #[test] fn a_gap_is_not_judged() {
  let mut t=Tracker::default();
  assert!(t.observe("BTCUSDT",minute(5),150.0,false,1.5).is_none(),"没有五分钟前的参照");
  let mut g=Tracker::default();
  g.observe("BTCUSDT",minute(0),100.0,true,1.5);
  g.observe("BTCUSDT",minute(4),100.0,true,1.5);
  assert!(g.observe("BTCUSDT",minute(6),120.0,false,1.5).is_none(),"第 1 分钟缺着");
  assert!(g.observe("BTCUSDT",minute(7),120.0,false,1.5).is_none(),"第 2 分钟也缺着");
 }
 #[test] fn one_notice_per_window_and_rearm_after_exit() {
  let mut t=Tracker::default();warm(&mut t,"BTCUSDT");
  assert!(t.observe("BTCUSDT",minute(5),102.0,false,1.5).is_some());
  assert!(t.observe("BTCUSDT",minute(5),103.0,false,1.5).is_none());
  assert!(t.observe("BTCUSDT",minute(5),100.5,false,1.5).is_none());
  assert!(t.observe("BTCUSDT",minute(5),102.0,false,1.5).is_none(),"同一个窗口不响第二次");
  t.observe("BTCUSDT",minute(6),102.0,true,1.5);
  for n in 7..=9 {t.observe("BTCUSDT",minute(n),102.0,true,1.5);}
  assert!(t.observe("BTCUSDT",minute(10),102.1,false,1.5).is_none());
  let e=t.observe("BTCUSDT",minute(10),104.0,false,1.5).expect("新窗口、已重新上膛");
  assert_eq!(e.window,minute(10));
 }
 #[test] fn staying_beyond_the_threshold_does_not_repeat() {
  let mut t=Tracker::default();
  let fired=(0..20).filter(|n|t.observe("BTCUSDT",minute(*n),100.0*1.01f64.powi(*n as i32),true,1.5).is_some()).count();
  assert_eq!(fired,1);
 }
 #[test] fn directions_are_independent() {
  let mut t=Tracker::default();warm(&mut t,"BTCUSDT");
  assert_eq!(t.observe("BTCUSDT",minute(5),102.0,false,1.5).map(|e|e.direction),Some(Direction::Up));
  assert_eq!(t.observe("BTCUSDT",minute(5),98.0,false,1.5).map(|e|e.direction),Some(Direction::Down));
 }
 #[test] fn stale_frames_are_ignored() {
  let mut t=Tracker::default();warm(&mut t,"BTCUSDT");
  t.observe("BTCUSDT",minute(5),100.0,false,1.5);
  assert!(t.observe("BTCUSDT",minute(3),150.0,false,1.5).is_none());
 }
 #[test] fn the_threshold_is_clamped() {
  assert_eq!(clamp_threshold(0.0),0.1);
  assert_eq!(clamp_threshold(80.0),50.0);
  assert_eq!(clamp_threshold(f64::NAN),1.5);
  assert_eq!(clamp_threshold(2.5),2.5);
 }
 /// 出厂是关；开着才有幅度，幅度读不出来退回 1.5。
 #[test] fn the_switch_and_threshold_come_from_settings() {
  assert_eq!(enabled(None),None);
  assert_eq!(enabled(Some(&json!({}))),None);
  assert_eq!(enabled(Some(&json!({"watchMoveAlert":false,"watchMoveThreshold":2.0}))),None);
  assert_eq!(enabled(Some(&json!({"watchMoveAlert":true}))),Some(1.5));
  assert_eq!(enabled(Some(&json!({"watchMoveAlert":true,"watchMoveThreshold":3.0}))),Some(3.0));
  assert_eq!(enabled(Some(&json!({"watchMoveAlert":true,"watchMoveThreshold":900.0}))),Some(50.0));
 }
 fn mover(owner:u128,threshold:f64,symbols:&[&str])->Mover {
  Mover{owner:Uuid::from_u128(owner),threshold,symbols:symbols.iter().map(|s|s.to_string()).collect()}
 }
 /// 改自选：拿掉的品种不再判，加回来从缺口重新开始。
 #[test] fn changing_favorites_changes_what_is_watched() {
  let mut m=Movers::default();
  m.refresh(&[mover(1,1.5,&["BTCUSDT","ETHUSDT"])]);
  for n in 0..5 {m.observe("BTCUSDT",minute(n),100.0,true);m.observe("ETHUSDT",minute(n),100.0,true);}
  m.refresh(&[mover(1,1.5,&["ETHUSDT"])]);
  assert_eq!(m.symbols().into_iter().collect::<Vec<_>>(),vec!["ETHUSDT".to_string()]);
  assert!(m.observe("BTCUSDT",minute(5),110.0,false).is_empty(),"不在自选里了");
  assert_eq!(m.observe("ETHUSDT",minute(5),110.0,false).len(),1);
  m.refresh(&[mover(1,1.5,&["ETHUSDT","BTCUSDT"])]);
  assert!(m.observe("BTCUSDT",minute(6),120.0,false).is_empty(),"加回来的品种没有五分钟前的参照");
 }
 /// 关掉开关：下一轮刷新之后一声都不再响。
 #[test] fn switching_off_stops_everything() {
  let mut m=Movers::default();
  m.refresh(&[mover(1,1.5,&["BTCUSDT"]),mover(2,1.5,&["BTCUSDT"])]);
  for n in 0..5 {m.observe("BTCUSDT",minute(n),100.0,true);}
  m.refresh(&[mover(2,1.5,&["BTCUSDT"])]);
  let hits=m.observe("BTCUSDT",minute(5),110.0,false);
  assert_eq!(hits.len(),1);
  assert_eq!(hits[0].0,Uuid::from_u128(2));
  m.refresh(&[]);
  assert!(m.symbols().is_empty());
 }
 /// 每个人按自己的幅度判。
 #[test] fn each_person_uses_their_own_threshold() {
  let mut m=Movers::default();
  m.refresh(&[mover(1,1.5,&["BTCUSDT"]),mover(2,5.0,&["BTCUSDT"])]);
  for n in 0..5 {m.observe("BTCUSDT",minute(n),100.0,true);}
  let hits=m.observe("BTCUSDT",minute(5),102.0,false);
  assert_eq!(hits.iter().map(|(o,_)|*o).collect::<Vec<_>>(),vec![Uuid::from_u128(1)]);
 }
 /// 断线重连之后收盘价作废，闸保留：同一个窗口回来不再响一次。
 /// 自选按交易所分：没写 `venue` 的老自选算币安，空代号不算，大小写归一、去重。
 #[test] fn favorites_are_split_by_venue() {
  let fav=|id:&str,body:serde_json::Value|crate::sync::Object{collection:crate::sync::FAVORITES.into(),id:id.into(),
   body:serde_json::from_value(body).unwrap(),fields:BTreeMap::new(),revision:1,deleted:false,generation:0};
  let all=[fav("a",serde_json::json!({"symbol":"btcusdt"})),fav("b",serde_json::json!({"symbol":"BTCUSDT","venue":"binance"})),
   fav("c",serde_json::json!({"symbol":"BTC-USD","venue":"coinbase"})),fav("d",serde_json::json!({"symbol":""})),fav("e",serde_json::json!({"venue":"binance"}))];
  assert_eq!(favorite_symbols(&all,"binance"),BTreeSet::from(["BTCUSDT".to_owned()]));
  assert_eq!(favorite_symbols(&all,"coinbase"),BTreeSet::from(["BTC-USD".to_owned()]));
 }
 #[test] fn a_reconnect_forgets_prices_but_keeps_the_gates() {
  let mut m=Movers::default();
  m.refresh(&[mover(1,1.5,&["BTCUSDT"])]);
  for n in 0..5 {m.observe("BTCUSDT",minute(n),100.0,true);}
  assert_eq!(m.observe("BTCUSDT",minute(5),102.0,false).len(),1);
  m.forget_prices();
  assert!(m.observe("BTCUSDT",minute(5),102.0,false).is_empty());
 }
}
