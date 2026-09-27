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
//! - **幅度按这只自己的波动自动定**（收设置项 E 组，2026-09-28 起不再是设置）：最近至多
//!   1440 个相邻 1 分钟收盘价的对数收益 r（开盘时刻正好差 1 分钟的两根才算），
//!   σ1 = 1.4826 × median(|r|)，σ5 = √5 · σ1，幅度 = clamp(5 · σ5, 0.5%, 10%)；不满 30 个收益
//!   用 1.5%。两端共用夹具 `contract/watch-move-threshold.json`。VPS 上币安 REST 回 451，
//!   历史只能从流里攒：断线只扔收盘价、不扔收益。
//!
//! 开关是同步设置（`settings/chart` 的 `watchMoveAlert`；老客户端的 `watchMoveThreshold`
//! 已退役，见 `sync::RETIRED_SETTINGS_FIELDS`），盯哪几只是这个人的自选（`favorites` 集合里
//! 所有没删的品种）。关掉开关，下一轮刷新（十秒内）这个人的状态整份丢掉，之后一声都不会再响。
use crate::{AppState,apns::Apns,error::Result};
use serde_json::Value;
use sqlx::{Postgres,Transaction};
use std::collections::{BTreeMap,BTreeSet};
use uuid::Uuid;

pub const BAR_MS:i64=60_000;
pub const WINDOW_MS:i64=300_000;
/// 收益不够（不满 [`MIN_RETURNS`] 个）时的幅度（百分数），即原来的出厂值。
pub const FALLBACK_THRESHOLD:f64=1.5;
/// 自动幅度的上下限（百分数）。
pub const THRESHOLD_RANGE:(f64,f64)=(0.5,10.0);
/// 至少这么多个 1 分钟收益才信得过估计。
pub const MIN_RETURNS:usize=30;
/// 最多看最近这么多个 1 分钟收益（一天）。
pub const MAX_RETURNS:usize=1440;
/// MAD → σ 的换算系数（正态下 σ = 1.4826 × MAD）。
pub const MAD_SCALE:f64=1.4826;

/// 自动幅度（百分数）：`returns` 是按时间先后排的 1 分钟对数收益，只看最后 [`MAX_RETURNS`] 个。
/// 客户端 `WatchMove.autoThreshold` 一字对一字。
pub fn auto_threshold(returns:&[f64])->f64 {
 let recent=&returns[returns.len().saturating_sub(MAX_RETURNS)..];
 let mut m:Vec<f64>=recent.iter().filter(|r|r.is_finite()).map(|r|r.abs()).collect();
 if m.len()<MIN_RETURNS {return FALLBACK_THRESHOLD}
 m.sort_by(f64::total_cmp);
 let n=m.len();
 let median=if n%2==1 {m[n/2]} else {(m[n/2-1]+m[n/2])/2.0};
 let percent=5.0*5f64.sqrt()*MAD_SCALE*median*100.0;
 if !percent.is_finite() {return FALLBACK_THRESHOLD}
 percent.clamp(THRESHOLD_RANGE.0,THRESHOLD_RANGE.1)
}

#[derive(Clone,Copy,Debug,PartialEq,Eq,PartialOrd,Ord)]
pub enum Direction {Up,Down}

#[derive(Clone,Debug,PartialEq)]
pub struct Event {pub symbol:String,pub direction:Direction,pub change:f64,pub price:f64,pub window:i64}

/// 一只品种最近几根 1 分钟收盘价，与估幅度用的收益（最近 [`MAX_RETURNS`] 个）。
#[derive(Clone,Debug)]
struct Series {closes:BTreeMap<i64,f64>,current_open:Option<i64>,current_close:Option<f64>,returns:std::collections::VecDeque<f64>,threshold:f64}
impl Default for Series {
 fn default()->Self {Self{closes:BTreeMap::new(),current_open:None,current_close:None,returns:Default::default(),threshold:FALLBACK_THRESHOLD}}
}
impl Series {
 /// 这一根收了。第一次收才记收益；前一分钟那一根也收着，才算一个收益。
 fn commit(&mut self,open:i64,close:f64) {
  let fresh=self.closes.insert(open,close).is_none();
  let Some(&previous)=self.closes.get(&(open-BAR_MS)) else {return};
  if !fresh||previous<=0.0 {return}
  self.returns.push_back((close/previous).ln());
  while self.returns.len()>MAX_RETURNS {self.returns.pop_front();}
  self.threshold=auto_threshold(self.returns.make_contiguous());
 }
 /// 断过线：收盘价与这一根作废，收益与幅度留着。
 fn forget_prices(&mut self) {self.closes.clear();self.current_open=None;self.current_close=None}
 /// 喂一口价，返回五分钟涨跌幅（小数）；参照那一根缺着就是 `None`。
 fn observe(&mut self,bar_open:i64,price:f64,closed:bool)->Option<f64> {
  if !price.is_finite()||price<=0.0 {return None}
  if self.current_open.is_some_and(|open|bar_open<open) {return None}
  if let (Some(open),Some(close))=(self.current_open,self.current_close) {
   if bar_open>open {self.commit(open,close);}
  }
  self.current_open=Some(bar_open);
  self.current_close=Some(price);
  if closed {self.commit(bar_open,price);}
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
 /// 幅度按这只自己的波动自动定（[`auto_threshold`]），再乘 `factor`（「按我的习惯自动调整」学到的
 /// 灵敏度倍数，夹在 0.5–2，出厂 1）。客户端 `WatchMove.Tracker.observe(…, sensitivity:)` 同一个乘法。
 pub fn observe(&mut self,symbol:&str,bar_open:i64,price:f64,closed:bool)->Option<Event> {self.observe_scaled(symbol,bar_open,price,closed,1.0)}
 /// 同 [`Tracker::observe`]，幅度再乘学到的灵敏度倍数。
 pub fn observe_scaled(&mut self,symbol:&str,bar_open:i64,price:f64,closed:bool,factor:f64)->Option<Event> {
  let key=symbol.to_uppercase();
  let series=self.series.entry(key.clone()).or_default();
  let change=series.observe(bar_open,price,closed)?;
  let factor=if factor.is_finite() {factor.clamp(FACTOR_MIN,FACTOR_MAX)} else {1.0};
  let limit=series.threshold*factor/100.0;
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
 /// 断过线：收盘价全扔（断线前那一根的「收盘」其实不是收盘），闸留着；估幅度的收益也留着
 /// （缺口两边不连，不会算出假收益），重连后不用再等三十分钟。
 pub fn forget_prices(&mut self) {for s in self.series.values_mut() {s.forget_prices()}}
 /// 这只现在的幅度（百分数）。没见过的品种是 [`FALLBACK_THRESHOLD`]。
 pub fn threshold(&self,symbol:&str)->f64 {self.series.get(&symbol.to_uppercase()).map_or(FALLBACK_THRESHOLD,|s|s.threshold)}
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

/// 一个开着自选波动提醒的人：自选里的品种（幅度按波动自动定，不是设置），
/// 外加「按我的习惯自动调整」学到的每只灵敏度倍数（没有就是 1）。
#[derive(Clone,Debug,PartialEq,Default)]
pub struct Mover {pub owner:Uuid,pub symbols:BTreeSet<String>,pub factors:BTreeMap<String,f64>}
impl Mover {
 pub fn factor(&self,symbol:&str)->f64 {self.factors.get(symbol).copied().unwrap_or(1.0)}
}

/// 灵敏度倍数的夹紧范围，和客户端 `LearnedDefaults.factorRange` 一致。
const FACTOR_MIN:f64=0.5;
const FACTOR_MAX:f64=2.0;

/// 这个人开着没有；开着就把**这家交易所**的自选读回来。在 `alerts::load`
/// 那个个人事务里调用，每家交易所的评估器各读各的（币安的组合流订不了 `BTC-USD`）。
/// 老客户端写的自选没有 `venue` 字段，按币安算。
pub async fn load_mover(tx:&mut Transaction<'_,Postgres>,owner:Uuid,venue:&str)->Result<Option<Mover>> {
 let settings=crate::sync::settings_body(tx,owner).await?;
 if !enabled(settings.as_ref()) {return Ok(None)}
 let favorites=crate::sync::live_objects(tx,owner,crate::sync::FAVORITES).await?;
 Ok(Some(Mover{owner,symbols:favorite_symbols(&favorites,venue),factors:learned_factors(settings.as_ref(),venue)}))
}
/// 设置里 `learnedDefaults.watchMove` 的倍数，只取这家交易所的（键是客户端的规范品种键
/// `binance/usd_m/BTCUSDT`，裸代号按币安算）。开关 `habitLearning` 明确关着就一律不用。
fn learned_factors(settings:Option<&Value>,venue:&str)->BTreeMap<String,f64> {
 let Some(body)=settings else {return BTreeMap::new()};
 if body.get("habitLearning").and_then(Value::as_bool)==Some(false) {return BTreeMap::new()}
 let Some(table)=body.get("learnedDefaults").and_then(|l|l.get("watchMove")).and_then(Value::as_object) else {return BTreeMap::new()};
 table.iter().filter_map(|(key,entry)|{
  let parts:Vec<&str>=key.split('/').collect();
  let (v,symbol)=match parts.as_slice() {[s]=>(crate::instruments::DEFAULT_VENUE,*s),[v,_,s]=>(*v,*s),_=>return None};
  if v!=venue||symbol.is_empty() {return None}
  let f=entry.get("v").and_then(Value::as_f64).filter(|f|f.is_finite())?;
  Some((symbol.to_uppercase(),f.clamp(FACTOR_MIN,FACTOR_MAX)))
 }).collect()
}
/// 自选里这家交易所的品种（大写、去重）。老客户端写的自选没有 `venue`，按裸代号的默认交易所（币安）算。
fn favorite_symbols(favorites:&[crate::sync::Object],venue:&str)->BTreeSet<String> {
 favorites.iter()
  .filter(|o|o.body.get("venue").and_then(Value::as_str).unwrap_or(crate::instruments::DEFAULT_VENUE)==venue)
  .filter_map(|o|o.body.get("symbol").and_then(Value::as_str))
  .filter(|s|!s.is_empty()).map(str::to_uppercase).collect()
}
/// 设置里开着没有（从没设过——出厂是关）。库里老 body 残留的 `watchMoveThreshold` 不看。
fn enabled(settings:Option<&Value>)->bool {
 settings.and_then(|b|b.get("watchMoveAlert")).and_then(Value::as_bool)==Some(true)
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
   if let Some(event)=tracker.observe_scaled(symbol,bar_open,price,closed,mover.factor(symbol)) {out.push((*owner,event))}
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
 fn warm(t:&mut Tracker,symbol:&str) {for n in 0..5 {t.observe(symbol,minute(n),100.0,true);}}

 #[test] fn an_upward_move_fires_once_as_up() {
  let mut t=Tracker::default();warm(&mut t,"BTCUSDT");
  let e=t.observe("BTCUSDT",minute(5),101.6,false).expect("fires");
  assert_eq!(e.direction,Direction::Up);
  assert!((e.change-0.016).abs()<1e-9);
  assert_eq!(e.window,minute(5));
  assert_eq!(title("BTCUSDT",&e),"BTC 五分钟涨 1.60%");
 }
 #[test] fn a_downward_move_fires_as_down() {
  let mut t=Tracker::default();warm(&mut t,"BTCUSDT");
  let e=t.observe("BTCUSDT",minute(5),98.4,false).expect("fires");
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
  assert!(t.observe("BTCUSDT",minute(5),101.4,false).is_none());
  assert!(t.observe("BTCUSDT",minute(5),98.6,false).is_none());
 }
 /// 缺口不当零波动，也不当大波动。
 #[test] fn a_gap_is_not_judged() {
  let mut t=Tracker::default();
  assert!(t.observe("BTCUSDT",minute(5),150.0,false).is_none(),"没有五分钟前的参照");
  let mut g=Tracker::default();
  g.observe("BTCUSDT",minute(0),100.0,true);
  g.observe("BTCUSDT",minute(4),100.0,true);
  assert!(g.observe("BTCUSDT",minute(6),120.0,false).is_none(),"第 1 分钟缺着");
  assert!(g.observe("BTCUSDT",minute(7),120.0,false).is_none(),"第 2 分钟也缺着");
 }
 #[test] fn one_notice_per_window_and_rearm_after_exit() {
  let mut t=Tracker::default();warm(&mut t,"BTCUSDT");
  assert!(t.observe("BTCUSDT",minute(5),102.0,false).is_some());
  assert!(t.observe("BTCUSDT",minute(5),103.0,false).is_none());
  assert!(t.observe("BTCUSDT",minute(5),100.5,false).is_none());
  assert!(t.observe("BTCUSDT",minute(5),102.0,false).is_none(),"同一个窗口不响第二次");
  t.observe("BTCUSDT",minute(6),102.0,true);
  for n in 7..=9 {t.observe("BTCUSDT",minute(n),102.0,true);}
  assert!(t.observe("BTCUSDT",minute(10),102.1,false).is_none());
  let e=t.observe("BTCUSDT",minute(10),104.0,false).expect("新窗口、已重新上膛");
  assert_eq!(e.window,minute(10));
 }
 #[test] fn staying_beyond_the_threshold_does_not_repeat() {
  let mut t=Tracker::default();
  let fired=(0..20).filter(|n|t.observe("BTCUSDT",minute(*n),100.0*1.01f64.powi(*n as i32),true).is_some()).count();
  assert_eq!(fired,1);
 }
 #[test] fn directions_are_independent() {
  let mut t=Tracker::default();warm(&mut t,"BTCUSDT");
  assert_eq!(t.observe("BTCUSDT",minute(5),102.0,false).map(|e|e.direction),Some(Direction::Up));
  assert_eq!(t.observe("BTCUSDT",minute(5),98.0,false).map(|e|e.direction),Some(Direction::Down));
 }
 #[test] fn stale_frames_are_ignored() {
  let mut t=Tracker::default();warm(&mut t,"BTCUSDT");
  t.observe("BTCUSDT",minute(5),100.0,false);
  assert!(t.observe("BTCUSDT",minute(3),150.0,false).is_none());
 }
 /// 两端共用的夹具：常数一致，每条用例 `auto_threshold` 与逐根喂 `Tracker` 都算出同一个幅度。
 #[test] fn every_shared_threshold_case_agrees() {
  let f:Value=serde_json::from_str(include_str!("../contract/watch-move-threshold.json")).expect("contract/watch-move-threshold.json");
  assert_eq!(f["version"],1);
  let k=&f["constants"];
  assert_eq!(k["fallbackPercent"].as_f64(),Some(FALLBACK_THRESHOLD));
  assert_eq!(k["floorPercent"].as_f64(),Some(THRESHOLD_RANGE.0));
  assert_eq!(k["ceilingPercent"].as_f64(),Some(THRESHOLD_RANGE.1));
  assert_eq!(k["minReturns"].as_u64(),Some(MIN_RETURNS as u64));
  assert_eq!(k["maxReturns"].as_u64(),Some(MAX_RETURNS as u64));
  assert_eq!(k["madScale"].as_f64(),Some(MAD_SCALE));
  let cases=f["cases"].as_array().unwrap();
  assert!(cases.len()>=8,"夹具被删薄了");
  for c in cases {
   let name=c["name"].as_str().unwrap();
   let mut closes=vec![c["start"].as_f64().unwrap()];
   for seg in c["segments"].as_array().unwrap() {
    let step=1.0+seg["stepPercent"].as_f64().unwrap()/100.0;
    for i in 0..seg["count"].as_u64().unwrap() {let last=*closes.last().unwrap();closes.push(if i%2==0 {last*step} else {last/step});}
   }
   let expect=c["expectPercent"].as_f64().unwrap();
   let returns:Vec<f64>=closes.windows(2).map(|w|(w[1]/w[0]).ln()).collect();
   assert!((auto_threshold(&returns)-expect).abs()<1e-6,"{name}：{}",c["why"]);
   let mut t=Tracker::default();
   for (n,close) in closes.iter().enumerate() {t.observe("BTCUSDT",minute(n as i64),*close,true);}
   assert!((t.threshold("BTCUSDT")-expect).abs()<1e-6,"Tracker · {name}");
  }
 }
 /// 缺口两边不连：断开的两根之间不算收益。
 #[test] fn gaps_do_not_make_returns() {
  let mut t=Tracker::default();
  for n in 0..30 {t.observe("BTCUSDT",minute(n),if n%2==0 {100.0} else {100.1},true);}
  t.observe("BTCUSDT",minute(31),120.0,true);
  assert_eq!(t.threshold("BTCUSDT"),FALLBACK_THRESHOLD);
  t.observe("BTCUSDT",minute(32),120.12,true);
  assert_ne!(t.threshold("BTCUSDT"),FALLBACK_THRESHOLD);
 }
 /// 同一根收两次（`k.x` 之后又换根）只记一个收益。
 #[test] fn a_bar_closed_twice_counts_once() {
  let mut t=Tracker::default();
  for n in 0..31 {let p=if n%2==0 {100.0} else {100.1};t.observe("BTCUSDT",minute(n),p,false);t.observe("BTCUSDT",minute(n),p,true);}
  assert_eq!(t.series["BTCUSDT"].returns.len(),30);
 }
 /// 安静的一只落到下限：0.8% 就响（原来 1.5% 一声不响）；很野的一只 5% 不响。
 #[test] fn the_threshold_follows_volatility() {
  let mut quiet=Tracker::default();
  for n in 0..60 {quiet.observe("BTCUSDT",minute(n),if n%2==0 {100.0} else {100.02},true);}
  assert_eq!(quiet.threshold("BTCUSDT"),0.5);
  assert!(quiet.observe("BTCUSDT",minute(60),100.02*1.008,false).is_some());
  let mut wild=Tracker::default();
  for n in 0..60 {wild.observe("BTCUSDT",minute(n),if n%2==0 {100.0} else {100.6},true);}
  assert!(wild.threshold("BTCUSDT")>9.0);
  assert!(wild.observe("BTCUSDT",minute(60),100.6*1.05,false).is_none());
 }
 /// 断线：收盘价作废、估出来的幅度留着。
 #[test] fn forgetting_prices_keeps_the_threshold() {
  let mut t=Tracker::default();
  for n in 0..60 {t.observe("BTCUSDT",minute(n),if n%2==0 {100.0} else {100.02},true);}
  t.forget_prices();
  assert_eq!(t.threshold("BTCUSDT"),0.5);
  assert!(t.observe("BTCUSDT",minute(60),110.0,false).is_none());
 }
 /// 出厂是关；只看开关，库里残留的老幅度不看。
 #[test] fn the_switch_comes_from_settings() {
  assert!(!enabled(None));
  assert!(!enabled(Some(&json!({}))));
  assert!(!enabled(Some(&json!({"watchMoveAlert":false,"watchMoveThreshold":2.0}))));
  assert!(enabled(Some(&json!({"watchMoveAlert":true}))));
  assert!(enabled(Some(&json!({"watchMoveAlert":true,"watchMoveThreshold":900.0}))));
 }
 fn mover(owner:u128,symbols:&[&str])->Mover {
  Mover{owner:Uuid::from_u128(owner),symbols:symbols.iter().map(|s|s.to_string()).collect(),factors:BTreeMap::new()}
 }
 /// 改自选：拿掉的品种不再判，加回来从缺口重新开始。
 #[test] fn changing_favorites_changes_what_is_watched() {
  let mut m=Movers::default();
  m.refresh(&[mover(1,&["BTCUSDT","ETHUSDT"])]);
  for n in 0..5 {m.observe("BTCUSDT",minute(n),100.0,true);m.observe("ETHUSDT",minute(n),100.0,true);}
  m.refresh(&[mover(1,&["ETHUSDT"])]);
  assert_eq!(m.symbols().into_iter().collect::<Vec<_>>(),vec!["ETHUSDT".to_string()]);
  assert!(m.observe("BTCUSDT",minute(5),110.0,false).is_empty(),"不在自选里了");
  assert_eq!(m.observe("ETHUSDT",minute(5),110.0,false).len(),1);
  m.refresh(&[mover(1,&["ETHUSDT","BTCUSDT"])]);
  assert!(m.observe("BTCUSDT",minute(6),120.0,false).is_empty(),"加回来的品种没有五分钟前的参照");
 }
 /// 关掉开关：下一轮刷新之后一声都不再响。
 #[test] fn switching_off_stops_everything() {
  let mut m=Movers::default();
  m.refresh(&[mover(1,&["BTCUSDT"]),mover(2,&["BTCUSDT"])]);
  for n in 0..5 {m.observe("BTCUSDT",minute(n),100.0,true);}
  m.refresh(&[mover(2,&["BTCUSDT"])]);
  let hits=m.observe("BTCUSDT",minute(5),110.0,false);
  assert_eq!(hits.len(),1);
  assert_eq!(hits[0].0,Uuid::from_u128(2));
  m.refresh(&[]);
  assert!(m.symbols().is_empty());
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
 /// 「按我的习惯自动调整」学到的灵敏度倍数：只取这家交易所的，夹在 0.5–2，开关关着一律不用；乘在自动幅度上。
 #[test] fn learned_factors_scale_the_threshold() {
  let body=json!({"learnedDefaults":{"watchMove":{
   "binance/usd_m/BTCUSDT":{"v":2.0,"n":3,"at":1.0},"ethusdt":{"v":0.5,"n":1,"at":1.0},
   "coinbase/spot/BTC-USD":{"v":1.6,"n":2,"at":1.0},"binance/usd_m/SOLUSDT":{"v":9.0,"n":1,"at":1.0},"bad/key":{"v":2.0,"n":1,"at":1.0}}}});
  let f=learned_factors(Some(&body),"binance");
  assert_eq!(f.get("BTCUSDT"),Some(&2.0));
  assert_eq!(f.get("ETHUSDT"),Some(&0.5));
  assert_eq!(f.get("SOLUSDT"),Some(&2.0),"越界夹回 2");
  assert_eq!(f.len(),3);
  assert_eq!(learned_factors(Some(&body),"coinbase").get("BTC-USD"),Some(&1.6));
  let mut off=body.clone();off["habitLearning"]=json!(false);
  assert!(learned_factors(Some(&off),"binance").is_empty(),"开关关着不用");
  assert!(learned_factors(None,"binance").is_empty());

  let mut m=Movers::default();
  let mut dull=mover(1,&["BTCUSDT"]);dull.factors=f.clone();
  m.refresh(&[dull,mover(2,&["BTCUSDT"])]);
  for n in 0..5 {m.observe("BTCUSDT",minute(n),100.0,true);}
  let hits=m.observe("BTCUSDT",minute(5),101.6,false);
  assert_eq!(hits.iter().map(|h|h.0).collect::<Vec<_>>(),vec![Uuid::from_u128(2)],"2× 的那位 1.6% 不响");
  let hits=m.observe("BTCUSDT",minute(5),103.1,false);
  assert_eq!(hits.iter().map(|h|h.0).collect::<Vec<_>>(),vec![Uuid::from_u128(1)],"过了 3% 才响");
 }
 #[test] fn a_reconnect_forgets_prices_but_keeps_the_gates() {
  let mut m=Movers::default();
  m.refresh(&[mover(1,&["BTCUSDT"])]);
  for n in 0..5 {m.observe("BTCUSDT",minute(n),100.0,true);}
  assert_eq!(m.observe("BTCUSDT",minute(5),102.0,false).len(),1);
  m.forget_prices();
  assert!(m.observe("BTCUSDT",minute(5),102.0,false).is_empty());
 }
}
