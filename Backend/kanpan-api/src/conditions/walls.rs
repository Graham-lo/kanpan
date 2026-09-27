//! 大单墙条件（`orderflowWall`），跑在 `serve` 里：主力订单流的跟踪器在这个进程。
//!
//! 三块：
//!
//! - [`refresh`] 每 10 秒读一遍所有人的活动大单提醒，按订单流 base 分组放进全局表，并保证这些 base 在跟
//!   （[`crate::orderflow_history::want`]，和手机打开这只品种时一样的按需层）；
//! - 跟踪器每评估一次簿就调一次 [`watching`] / [`observe`]（`orderflow_history` 的 evaluate 分支），
//!   在它自己的任务里、不 await、不碰库：判出来的交给一条通道；
//! - [`spawn`] 起的任务从通道里取、走 [`super::fire`]（写库、Webhook、推送）。写库失败把这条放回去重判。
//!
//! 判法（协议 2.4）：还挂着的墙名义 ≥ 门槛，且是「新的」——首次出现在 armedAt 之后，或者不在武装后第一次看到时
//! 取的基线里（那时还不够门槛、后来长上来的）。
use super::{CondAlert,Hit,Observation,Rule,units};
use crate::{AppState,apns::Apns};
use rust_decimal::prelude::ToPrimitive;
use serde_json::json;
use std::collections::{HashMap,HashSet};
use std::sync::{Arc,Mutex,OnceLock};
use std::time::Duration;
use tokio::sync::mpsc;

/// 跟踪器交过来的一面还挂着的墙（`orderflow_history` 把它私有的 `BigOrder` 摊成这个）。
#[derive(Clone,Debug,PartialEq)]
pub struct WallView {
 /// 同一面墙跨评估不变的键：交易所 / 产品 / 侧 / 价位桶。
 pub key:String,
 /// 「币安」「OKX」「Coinbase」。
 pub exchange:String,
 /// `spot` / `usdtPerp` / `coinPerp` / `delivery`。
 pub product:String,
 /// `bid` / `ask`。
 pub side:&'static str,
 /// 每一个币的价（没乘币安的倍数前缀）。
 pub price:f64,
 pub notional:f64,
 pub first_seen_ms:i64,
}

/// 一条在盯的大单提醒。
#[derive(Clone,Debug)]
pub struct Watch {
 pub alert:CondAlert,
 /// 提醒品种相对订单流 base 的倍数（`1000PEPEUSDT` 是 1000）。
 pub scale:f64,
 pub threshold:f64,
 /// 武装后第一次看到这只 base 时，已经 ≥ 门槛的老墙。None 是还没看到过。
 pub baseline:Option<HashSet<String>>,
 /// 已经判响、交出去了（等写库结果）。
 pub fired:bool,
}
impl Watch {
 pub fn new(alert:CondAlert,scale:f64)->Option<Self> {
  let Rule::Wall{threshold}=alert.rule else {return None};
  Some(Self{alert,scale,threshold:threshold.to_f64()?,baseline:None,fired:false})
 }
 /// 这一次评估的墙里有没有让它响的；有就挑名义最大的那面。
 pub fn judge(&mut self,walls:&[WallView],now:i64)->Option<Observation> {
  if self.fired {return None}
  let armed=self.alert.armed_at;
  let threshold=self.threshold;
  let baseline=self.baseline.get_or_insert_with(||walls.iter().filter(|w|w.first_seen_ms<armed&&w.notional>=threshold).map(|w|w.key.clone()).collect());
  let wall=walls.iter().filter(|w|w.notional>=threshold&&(w.first_seen_ms>=armed||!baseline.contains(&w.key)))
   .max_by(|a,b|a.notional.total_cmp(&b.notional))?;
  self.fired=true;
  let price=wall.price*self.scale;
  Some(Observation{at:now,price,
   detail:format!("{} {} {} {} @ {}",wall.exchange,product_label(&wall.product),if wall.side=="bid" {"买墙"} else {"卖墙"},units(wall.notional),crate::alerts::money(price)),
   value:json!({"exchange":wall.exchange,"product":wall.product,"side":wall.side,"price":price.to_string(),"notional":wall.notional.round().to_string(),"firstSeen":wall.first_seen_ms})})
 }
}

pub fn product_label(product:&str)->&str {
 match product {"spot"=>"现货","usdtPerp"=>"U 本位","coinPerp"=>"币本位","delivery"=>"交割",other=>other}
}

/// 提醒品种 → （订单流 base，倍数）：去计价后缀、去币安的倍数前缀。
pub fn orderflow_base(symbol:&str)->(String,f64) {
 let listed=crate::instruments::base(symbol);
 let rest=crate::orderflow_instruments::unscaled(listed);
 let scale=crate::orderflow_instruments::BINANCE_SCALED.iter().find(|(prefix,_)|rest!=listed&&listed.len()==prefix.len()+rest.len()&&listed.starts_with(prefix)).map_or(1.0,|(_,s)|*s as f64);
 (rest.to_string(),scale)
}

type Table=HashMap<String,Vec<Watch>>;
static TABLE:Mutex<Option<Table>>=Mutex::new(None);
static HITS:OnceLock<mpsc::Sender<Hit>>=OnceLock::new();

fn table()->std::sync::MutexGuard<'static,Option<Table>> {TABLE.lock().unwrap_or_else(|e|e.into_inner())}

/// 跟踪器问：这只 base 有没有人挂着大单提醒（没有就不必把墙摊出来）。
pub fn watching(base:&str)->bool {table().as_ref().is_some_and(|t|t.contains_key(base))}

/// 跟踪器每评估一次簿交一次还挂着的墙。判出来的交给 [`spawn`] 的任务去触发。
pub fn observe(base:&str,walls:&[WallView],now:i64) {
 let mut guard=table();
 let Some(list)=guard.as_mut().and_then(|t|t.get_mut(base)) else {return};
 for w in list.iter_mut() {
  if let Some(o)=w.judge(walls,now) {
   let sent=HITS.get().is_some_and(|tx|tx.try_send((w.alert.clone(),o)).is_ok());
   // 通道满了（写库卡住）：这一次不算，下一次评估再判。
   if !sent {w.fired=false}
  }
 }
}

/// 把新读出来的一轮提醒换进全局表：同一条（同 id、同武装时刻、同门槛）的基线与「已交出去」沿用。
pub fn replace(fresh:Vec<CondAlert>) {
 let mut guard=table();
 let old=guard.take().unwrap_or_default();
 let mut keep:HashMap<(uuid::Uuid,String),Watch>=old.into_values().flatten().map(|w|((w.alert.owner,w.alert.alert_id.clone()),w)).collect();
 let mut next:Table=HashMap::new();
 for alert in fresh {
  let (base,scale)=orderflow_base(&alert.symbol);
  let Some(mut w)=Watch::new(alert,scale) else {continue};
  if let Some(prev)=keep.remove(&(w.alert.owner,w.alert.alert_id.clone()))
   && prev.alert.armed_at==w.alert.armed_at&&prev.threshold==w.threshold&&prev.scale==w.scale {
   w.baseline=prev.baseline;w.fired=prev.fired;
  }
  next.entry(base).or_default().push(w);
 }
 *guard=Some(next);
}

/// 写库失败：放回去，下一次评估重判。
fn rearm(owner:uuid::Uuid,alert_id:&str) {
 if let Some(t)=table().as_mut() {for w in t.values_mut().flatten() {if w.alert.owner==owner&&w.alert.alert_id==alert_id {w.fired=false}}}
}
/// 触发成了（或者已经不是 active）：从表里拿掉。
fn forget(owner:uuid::Uuid,alert_id:&str) {
 if let Some(t)=table().as_mut() {
  for list in t.values_mut() {list.retain(|w|!(w.alert.owner==owner&&w.alert.alert_id==alert_id))}
  t.retain(|_,list|!list.is_empty());
 }
}

const REFRESH:Duration=Duration::from_secs(10);

/// 读库、换表、保证在跟。
pub async fn refresh(s:&AppState)->crate::error::Result<()> {
 let walls:Vec<CondAlert>=super::load(s).await?.into_iter().filter(|a|matches!(a.rule,Rule::Wall{..})).collect();
 let bases:HashSet<String>=walls.iter().map(|a|orderflow_base(&a.symbol).0).collect();
 replace(walls);
 let now=chrono::Utc::now().timestamp_millis();
 for base in bases {
  if !crate::orderflow_history::want(&base,now).await {tracing::warn!("Wall condition on {base}: the orderflow tracker would not track it")}
 }
 Ok(())
}

/// serve 里的大单条件：刷新循环 + 触发任务。
pub async fn run(s:AppState,apns:Option<Arc<Apns>>) {
 let (tx,mut rx)=mpsc::channel::<Hit>(256);
 // serve 只起一次；万一被 supervisor 重起，沿用第一次的发送端会让新的接收端收不到，所以换不了就只记一行。
 if HITS.set(tx).is_err() {tracing::warn!("Wall conditions restarted; hits go to the first receiver");}
 let fire_loop=async {
  while let Some((a,o))=rx.recv().await {
   match super::fire(&s,apns.as_deref(),&a,&o).await {
    Ok(_)=>forget(a.owner,&a.alert_id),
    Err(e)=>{tracing::warn!("A wall condition met its condition but could not be recorded ({e:?}); it will be judged again");rearm(a.owner,&a.alert_id)}
   }
  }
 };
 let refresh_loop=async {
  let mut tick=tokio::time::interval(REFRESH);
  tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
  loop {
   tick.tick().await;
   if let Err(e)=refresh(&s).await {tracing::warn!("Wall conditions could not be reloaded ({e:?}); keeping last round's")}
  }
 };
 tokio::join!(fire_loop,refresh_loop);
}

#[cfg(test)]
mod tests {
 use super::*;
 use serde_json::Value;

 fn alert(threshold:&str,armed_at:i64,symbol:&str)->CondAlert {
  let rule:Value=json!({"type":"orderflowWall","threshold":threshold});
  CondAlert{owner:uuid::Uuid::nil(),alert_id:format!("binance/usd_m/{symbol}/w"),symbol:symbol.into(),market:"binance/usd_m".into(),
   rule:Rule::parse(&rule).unwrap(),rule_json:rule,armed_at,title:String::new(),note:None,webhook:None,webhook_text:None}
 }
 fn wall(key:&str,notional:f64,first_seen:i64)->WallView {
  WallView{key:key.into(),exchange:"币安".into(),product:"usdtPerp".into(),side:"bid",price:84_000.0,notional,first_seen_ms:first_seen}
 }

 #[test] fn only_new_walls_fire_and_only_once() {
  let armed=1_000;
  let mut w=Watch::new(alert("5000000",armed,"BTCUSDT"),1.0).unwrap();
  // 第一次看到：一面早就在的 8M 老墙进基线、不响；一面早就在但只有 3M 的不进基线。
  assert!(w.judge(&[wall("old",8e6,500),wall("small",3e6,600)],2_000).is_none());
  // 老墙再大也不响。
  assert!(w.judge(&[wall("old",20e6,500),wall("small",3e6,600)],3_000).is_none());
  // 武装前就在、后来长过门槛的：响。
  let o=w.judge(&[wall("old",20e6,500),wall("small",12.4e6,600)],4_000).expect("长上来的算新墙");
  assert_eq!(o.detail,"币安 U 本位 买墙 12.4M @ 84,000");
  assert_eq!(o.price,84_000.0);
  assert_eq!(o.value["side"],"bid");
  // 响过就不再响。
  assert!(w.judge(&[wall("new",50e6,5_000)],5_000).is_none());
 }

 #[test] fn a_wall_first_seen_after_arming_fires_even_on_first_look() {
  let mut w=Watch::new(alert("5000000",1_000,"BTCUSDT"),1.0).unwrap();
  assert!(w.judge(&[wall("tiny",4e6,1_500)],2_000).is_none(),"不到门槛");
  let mut fresh=Watch::new(alert("5000000",1_000,"BTCUSDT"),1.0).unwrap();
  assert!(fresh.judge(&[wall("new",6e6,1_500)],2_000).is_some());
 }

 #[test] fn scaled_symbols_map_to_the_orderflow_base() {
  assert_eq!(orderflow_base("BTCUSDT"),("BTC".to_string(),1.0));
  assert_eq!(orderflow_base("1000PEPEUSDT"),("PEPE".to_string(),1000.0));
  assert_eq!(orderflow_base("1000000MOGUSDT"),("MOG".to_string(),1_000_000.0));
  assert_eq!(orderflow_base("1MBABYDOGEUSDT"),("BABYDOGE".to_string(),1_000_000.0));
  let mut w=Watch::new(alert("10000",0,"1000PEPEUSDT"),1000.0).unwrap();
  let o=w.judge(&[WallView{price:0.0000123,..wall("p",2e6,10)}],20).unwrap();
  assert!((o.price-0.0123).abs()<1e-12);
 }

 #[test] fn replacing_keeps_the_baseline_of_the_same_alert() {
  let a=alert("5000000",1_000,"ETHUSDT");
  replace(vec![a.clone()]);
  assert!(watching("ETH"));
  observe("ETH",&[wall("old",8e6,500)],2_000);
  replace(vec![a.clone()]);
  let baseline=table().as_ref().unwrap()["ETH"][0].baseline.clone();
  assert_eq!(baseline,Some(HashSet::from(["old".to_string()])));
  // 重新武装（armedAt 变了）就重取基线。
  replace(vec![CondAlert{armed_at:3_000,..a}]);
  assert_eq!(table().as_ref().unwrap()["ETH"][0].baseline,None);
  replace(vec![]);
  assert!(!watching("ETH"));
 }
}
