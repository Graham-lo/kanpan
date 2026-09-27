//! 品种状态通知（`docs/条件提醒-协议-2026-09-27.md` 第 6 节）：上新、将下架、暂停、恢复、已下架。
//!
//! worker 里每 10 分钟对一次品种表——币安 U 本位 `exchangeInfo`（永续）与 Coinbase 现货 USD 对——和上一轮存下的
//! 目录（`listing_catalog`）比，比出来的变化写成事件（`listing_events`），再扇给开了 `notifyListingChanges` 的人：
//! 上新推给所有开了开关的人，其余只推给自选里有它的人。「每人每个变化只推一次」靠 `listing_notices` 的主键：
//! 先插、插进去了才推。
//!
//! 对表是纯函数（[`binance_catalog`] / [`coinbase_catalog`] / [`diff`] / [`plausible`]），循环只管取数、落库、扇出。
use crate::{AppState,alerts,apns::Apns,auth::Identity,envelope,error::Result};
use axum::{Router,Json,extract::State,routing::get};
use serde_json::{Value,json};
use sqlx::Row;
use std::collections::{HashMap,HashSet};
use std::sync::Arc;
use std::time::Duration;
use uuid::Uuid;

/// 品种此刻的状态。
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum Listing {Trading,Pending,Halted,Delisted}
impl Listing {
 pub fn wire(self)->&'static str {match self {Listing::Trading=>"trading",Listing::Pending=>"pending",Listing::Halted=>"halted",Listing::Delisted=>"delisted"}}
 pub fn parse(text:&str)->Option<Self> {match text {"trading"=>Some(Listing::Trading),"pending"=>Some(Listing::Pending),"halted"=>Some(Listing::Halted),"delisted"=>Some(Listing::Delisted),_=>None}}
 fn live(self)->bool {matches!(self,Listing::Trading|Listing::Halted)}
}

/// 目录里的一行。
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub struct Entry {pub state:Listing,pub delivery_at:Option<i64>}
pub type Catalog=HashMap<String,Entry>;

/// 一个变化。
#[derive(Clone,Debug,PartialEq,Eq)]
pub struct Change {pub symbol:String,pub event:&'static str,pub delivery_at:Option<i64>}

/// 币安永续的「没排下架」占位（2100-01-01）。比它早的 `deliveryDate` 就是真排上了。
pub const BINANCE_NO_DELIVERY:i64=4_133_404_800_000;
const PERPETUALS:[&str;2]=["PERPETUAL","TRADIFI_PERPETUAL"];

/// 币安 U 本位 `exchangeInfo` → 永续的目录。
pub fn binance_catalog(v:&Value)->Catalog {
 let mut out=Catalog::new();
 for row in v["symbols"].as_array().map(Vec::as_slice).unwrap_or(&[]) {
  let (Some(symbol),Some(kind),Some(status))=(row["symbol"].as_str(),row["contractType"].as_str(),row["status"].as_str()) else {continue};
  if !PERPETUALS.contains(&kind) {continue}
  let state=match status {
   "TRADING"=>Listing::Trading,
   "PENDING_TRADING"=>Listing::Pending,
   "PRE_SETTLE"|"SETTLING"|"CLOSE"|"PRE_DELIVERING"|"DELIVERING"|"DELIVERED"=>Listing::Delisted,
   _=>Listing::Halted,
  };
  let delivery_at=row["deliveryDate"].as_i64().filter(|d|*d>0&&*d<BINANCE_NO_DELIVERY);
  out.insert(symbol.to_string(),Entry{state,delivery_at});
 }
 out
}

/// Coinbase 现货产品表 → USD 对的目录。
pub fn coinbase_catalog(v:&Value)->Catalog {
 let mut out=Catalog::new();
 for row in v["products"].as_array().map(Vec::as_slice).unwrap_or(&[]) {
  let Some(pair)=row["product_id"].as_str() else {continue};
  if row["quote_currency_id"].as_str()!=Some("USD") {continue}
  let status=row["status"].as_str().unwrap_or_default();
  let state=if status=="delisted" {Listing::Delisted}
   else if status=="online"&&row["is_disabled"].as_bool()!=Some(true)&&row["trading_disabled"].as_bool()!=Some(true) {Listing::Trading}
   else {Listing::Halted};
  out.insert(pair.to_ascii_uppercase(),Entry{state,delivery_at:None});
 }
 out
}

/// 这一轮拉到的表可信吗：还活着的品种数不到上一轮的一半，当成「没拉全」跳过。
pub fn plausible(previous:&Catalog,fresh:&Catalog)->bool {
 let before=previous.values().filter(|e|e.state!=Listing::Delisted).count();
 let now=fresh.values().filter(|e|e.state!=Listing::Delisted).count();
 now*2>=before
}

/// 上一轮 → 这一轮：比出变化，并给出这一轮要写回目录的样子（表里消失的记成已下架）。
pub fn diff(previous:&Catalog,fresh:&Catalog)->(Vec<Change>,Catalog) {
 let mut changes=vec![];
 let mut next=fresh.clone();
 let change=|symbol:&str,event,delivery_at|Change{symbol:symbol.to_string(),event,delivery_at};
 for (symbol,now) in fresh {
  let before=previous.get(symbol);
  match (before.map(|b|b.state),now.state) {
   (None|Some(Listing::Pending|Listing::Delisted),Listing::Trading)=>changes.push(change(symbol,"listed",None)),
   (Some(Listing::Trading),Listing::Halted)=>changes.push(change(symbol,"halted",None)),
   (Some(Listing::Halted),Listing::Trading)=>changes.push(change(symbol,"resumed",None)),
   (Some(s),Listing::Delisted) if s.live()=>changes.push(change(symbol,"delisted",None)),
   _=>{}
  }
  if let (Some(before),Some(at))=(before,now.delivery_at)
   && before.state.live()&&now.state.live()&&before.delivery_at!=Some(at) {changes.push(change(symbol,"delistScheduled",Some(at)))}
 }
 for (symbol,before) in previous {
  if fresh.contains_key(symbol) {continue}
  if before.state.live() {changes.push(change(symbol,"delisted",None))}
  next.insert(symbol.clone(),Entry{state:Listing::Delisted,delivery_at:before.delivery_at});
 }
 changes.sort_by(|a,b|(&a.symbol,a.event).cmp(&(&b.symbol,b.event)));
 (changes,next)
}

// ——————————————————————————— 文案 ———————————————————————————

pub fn venue_label(venue:&str)->&'static str {if venue=="coinbase" {"Coinbase 现货"} else {"币安合约"}}

/// 北京时间「10月3日 16:00」。
pub fn beijing(at:i64)->String {
 let offset=chrono::FixedOffset::east_opt(8*3600).expect("UTC+8");
 chrono::DateTime::from_timestamp_millis(at).map(|t|t.with_timezone(&offset).format("%-m月%-d日 %H:%M").to_string()).unwrap_or_default()
}

/// 一条事件的推送标题与正文（协议 6.3）。
pub fn texts(venue:&str,symbol:&str,event:&str,delivery_at:Option<i64>)->(String,String) {
 let label=venue_label(venue);
 match event {
  "listed"=>(format!("新上线：{symbol}"),label.to_string()),
  "delistScheduled"=>(format!("{symbol} 将下架"),match delivery_at {Some(at)=>format!("{label} · {}（北京时间）停止交易",beijing(at)),None=>label.to_string()}),
  "halted"=>(format!("{symbol} 暂停交易"),format!("{label} · 你的自选")),
  "resumed"=>(format!("{symbol} 恢复交易"),format!("{label} · 你的自选")),
  _=>(format!("{symbol} 已下架"),format!("{label} · 你的自选")),
 }
}

// ——————————————————————————— 落库 ———————————————————————————

const COINBASE_PRODUCTS:&str="https://api.coinbase.com/api/v3/brokerage/market/products?product_type=SPOT&limit=1000";
const EVERY:Duration=Duration::from_secs(600);
/// 事件发生后多久之内还推。
pub const FRESH_MS:i64=3_600_000;
/// 事件与通知留多久。
pub const KEEP_MS:i64=30*86_400_000;

fn now_ms()->i64 {chrono::Utc::now().timestamp_millis()}

async fn read_catalog(s:&AppState,venue:&str,market:&str)->Result<Catalog> {
 let rows=sqlx::query("SELECT symbol,state,delivery_at FROM listing_catalog WHERE venue=$1 AND market=$2").bind(venue).bind(market).fetch_all(&s.pool).await?;
 Ok(rows.into_iter().filter_map(|r|Some((r.get::<String,_>("symbol"),Entry{state:Listing::parse(r.get::<&str,_>("state"))?,delivery_at:r.get("delivery_at")}))).collect())
}

/// 对一家的表：比、写事件、写回目录（一个事务）。返回写了几条事件。第一次（目录是空的）只建基线。
pub async fn reconcile(s:&AppState,venue:&str,market:&str,fresh:&Catalog,now:i64)->Result<usize> {
 let previous=read_catalog(s,venue,market).await?;
 if fresh.is_empty() {return Ok(0)}
 if !previous.is_empty()&&!plausible(&previous,fresh) {
  tracing::warn!("Listing watch: {venue}/{market} returned {} live symbols against {} last round; skipping this round",fresh.len(),previous.len());
  return Ok(0)
 }
 let (changes,next)=if previous.is_empty() {(vec![],fresh.clone())} else {diff(&previous,fresh)};
 let mut tx=s.pool.begin().await?;
 for c in &changes {
  sqlx::query("INSERT INTO listing_events(venue,market,symbol,event,delivery_at,at) VALUES($1,$2,$3,$4,$5,$6)")
   .bind(venue).bind(market).bind(&c.symbol).bind(c.event).bind(c.delivery_at).bind(now).execute(&mut *tx).await?;
 }
 for (symbol,e) in &next {
  if previous.get(symbol)==Some(e) {continue}
  sqlx::query("INSERT INTO listing_catalog(venue,market,symbol,state,delivery_at) VALUES($1,$2,$3,$4,$5) \
   ON CONFLICT(venue,market,symbol) DO UPDATE SET state=excluded.state,delivery_at=excluded.delivery_at,updated_at=now()")
   .bind(venue).bind(market).bind(symbol).bind(e.state.wire()).bind(e.delivery_at).execute(&mut *tx).await?;
 }
 tx.commit().await?;
 if !changes.is_empty() {tracing::info!("Listing watch: {venue}/{market} {} change(s)",changes.len())}
 Ok(changes.len())
}

/// 一条最近的事件。
#[derive(Clone,Debug)]
struct Event {id:i64,venue:String,market:String,symbol:String,event:String,delivery_at:Option<i64>}

/// 这个人自选里的（交易所，代号）。
fn favorite_keys(objects:&[crate::sync::Object])->HashSet<(String,String)> {
 objects.iter().filter_map(|o|{
  let symbol=o.body.get("symbol")?.as_str()?.to_string();
  let venue=o.body.get("venue").and_then(Value::as_str).unwrap_or(crate::instruments::DEFAULT_VENUE).to_string();
  Some((venue,symbol))
 }).collect()
}

/// 把最近 1 小时的事件扇给开了开关的人。返回插进去（也就是该推）的条数。
pub async fn fan_out(s:&AppState,apns:Option<&Apns>,now:i64)->Result<usize> {
 let events:Vec<Event>=sqlx::query("SELECT id,venue,market,symbol,event,delivery_at FROM listing_events WHERE at>$1 ORDER BY id").bind(now-FRESH_MS).fetch_all(&s.pool).await?
  .into_iter().map(|r|Event{id:r.get("id"),venue:r.get("venue"),market:r.get("market"),symbol:r.get("symbol"),event:r.get("event"),delivery_at:r.get("delivery_at")}).collect();
 if events.is_empty() {return Ok(0)}
 let mut sent=0;
 let mut after:Option<Uuid>=None;
 loop {
  let owners:Vec<Uuid>=sqlx::query_scalar("SELECT id FROM account_users WHERE disabled_at IS NULL AND ($1::uuid IS NULL OR id>$1) ORDER BY id LIMIT 100").bind(after).fetch_all(&s.pool).await?;
  if owners.is_empty() {break}
  for owner in &owners {
   let mut tx=match s.personal(*owner).await {Ok(tx)=>tx,Err(_)=>continue};
   let on=crate::sync::settings_body(&mut tx,*owner).await?.is_some_and(|b|b.get("notifyListingChanges")==Some(&Value::Bool(true)));
   if !on {tx.commit().await?;continue}
   let favorites=favorite_keys(&crate::sync::live_objects(&mut tx,*owner,crate::sync::FAVORITES).await?);
   let mut fresh=vec![];
   for e in &events {
    if e.event!="listed"&&!favorites.contains(&(e.venue.clone(),e.symbol.clone())) {continue}
    let inserted=sqlx::query("INSERT INTO listing_notices(user_id,event_id) VALUES($1,$2) ON CONFLICT DO NOTHING").bind(owner).bind(e.id).execute(&mut *tx).await?.rows_affected();
    if inserted==1 {fresh.push(e.clone())}
   }
   tx.commit().await?;
   sent+=fresh.len();
   for e in fresh {
    let (title,body)=texts(&e.venue,&e.symbol,&e.event,e.delivery_at);
    let Some(apns)=apns else {tracing::info!("Listing notice {} {} recorded, not pushed (no APNs key)",e.symbol,e.event);continue};
    let notice=alerts::Notice{title,body,link:format!("hkline://symbol/{}",alerts::symbol_path(&format!("{}/{}",e.venue,e.market),&e.symbol)),kind:"listing"};
    if let Err(err)=alerts::notify(s,apns,*owner,&notice).await {tracing::warn!("A listing notice could not be pushed ({err:?})")}
   }
  }
  after=owners.last().copied();
 }
 Ok(sent)
}

/// 一轮：两家各对一次表、扇出、清掉 30 天前的事件。
pub async fn round(s:&AppState,apns:Option<&Apns>,binance:Option<&Value>,coinbase:Option<&Value>,now:i64)->Result<()> {
 if let Some(v)=binance {reconcile(s,"binance","usd_m",&binance_catalog(v),now).await?;}
 if let Some(v)=coinbase {reconcile(s,"coinbase","spot",&coinbase_catalog(v),now).await?;}
 fan_out(s,apns,now).await?;
 sqlx::query("DELETE FROM listing_events WHERE at<$1").bind(now-KEEP_MS).execute(&s.pool).await?;
 Ok(())
}

/// worker 里的常驻循环。
pub async fn run(s:AppState,apns:Option<Arc<Apns>>) {
 let mut tick=tokio::time::interval(EVERY);
 tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
 loop {
  tick.tick().await;
  let binance=crate::market_meta::exchange_info().await.ok();
  let coinbase=crate::market_meta::get_json(COINBASE_PRODUCTS).await.ok();
  if binance.is_none() {tracing::warn!("Listing watch: Binance exchangeInfo unavailable this round")}
  if coinbase.is_none() {tracing::warn!("Listing watch: Coinbase products unavailable this round")}
  if let Err(e)=round(&s,apns.as_deref(),binance.as_deref(),coinbase.as_ref(),now_ms()).await {tracing::warn!("Listing watch round failed ({e:?})")}
 }
}

// ——————————————————————————— 拉取 ———————————————————————————

pub fn routes()->Router<AppState> {Router::new().route("/v1/alerts/listing-notices",get(notices))}

/// `GET /v1/alerts/listing-notices`：这个人最近 30 天收到的品种状态通知，新的在前，最多 100 条。
async fn notices(State(s):State<AppState>,i:Identity)->Result<Json<Value>> {
 let mut tx=s.personal(i.user).await?;
 let rows=sqlx::query("SELECT e.id,e.venue,e.market,e.symbol,e.event,e.at,e.delivery_at FROM listing_notices n JOIN listing_events e ON e.id=n.event_id \
  WHERE n.user_id=$1 AND e.at>$2 ORDER BY e.at DESC,e.id DESC LIMIT 100").bind(i.user).bind(now_ms()-KEEP_MS).fetch_all(&mut *tx).await?;
 tx.commit().await?;
 let notices:Vec<Value>=rows.iter().map(|r|{
  let (venue,symbol,event):(String,String,String)=(r.get("venue"),r.get("symbol"),r.get("event"));
  let delivery_at:Option<i64>=r.get("delivery_at");
  let (title,body)=texts(&venue,&symbol,&event,delivery_at);
  json!({"id":r.get::<i64,_>("id"),"venue":venue,"market":r.get::<String,_>("market"),"symbol":symbol,"event":event,"at":r.get::<i64,_>("at"),
   "deliveryAt":if event=="delistScheduled" {json!(delivery_at)} else {Value::Null},"title":title,"body":body})
 }).collect();
 Ok(envelope(json!({"notices":notices})))
}

#[cfg(test)]
mod tests {
 use super::*;

 fn cat(rows:&[(&str,Listing,Option<i64>)])->Catalog {rows.iter().map(|(s,st,d)|(s.to_string(),Entry{state:*st,delivery_at:*d})).collect()}
 fn events(changes:&[Change])->Vec<(&str,&str)> {changes.iter().map(|c|(c.symbol.as_str(),c.event)).collect()}

 #[test] fn binance_rows_map_to_states() {
  let v=json!({"symbols":[
   {"symbol":"BTCUSDT","contractType":"PERPETUAL","status":"TRADING","deliveryDate":BINANCE_NO_DELIVERY},
   {"symbol":"ABCUSDT","contractType":"PERPETUAL","status":"TRADING","deliveryDate":1790985600000_i64},
   {"symbol":"NEWUSDT","contractType":"PERPETUAL","status":"PENDING_TRADING","deliveryDate":BINANCE_NO_DELIVERY},
   {"symbol":"OLDUSDT","contractType":"PERPETUAL","status":"SETTLING","deliveryDate":1790000000000_i64},
   {"symbol":"NVDAUSDT","contractType":"TRADIFI_PERPETUAL","status":"BREAK","deliveryDate":BINANCE_NO_DELIVERY},
   {"symbol":"BTCUSDT_261225","contractType":"NEXT_QUARTER","status":"TRADING","deliveryDate":1798185600000_i64},
  ]});
  let c=binance_catalog(&v);
  assert_eq!(c.len(),5,"交割合约不收");
  assert_eq!(c["BTCUSDT"],Entry{state:Listing::Trading,delivery_at:None});
  assert_eq!(c["ABCUSDT"].delivery_at,Some(1790985600000));
  assert_eq!(c["NEWUSDT"].state,Listing::Pending);
  assert_eq!(c["OLDUSDT"].state,Listing::Delisted);
  assert_eq!(c["NVDAUSDT"].state,Listing::Halted);
 }

 #[test] fn coinbase_rows_map_to_states() {
  let v=json!({"products":[
   {"product_id":"BTC-USD","quote_currency_id":"USD","status":"online","is_disabled":false,"trading_disabled":false},
   {"product_id":"BTC-USDC","quote_currency_id":"USDC","status":"online"},
   {"product_id":"XYZ-USD","quote_currency_id":"USD","status":"online","trading_disabled":true},
   {"product_id":"OLD-USD","quote_currency_id":"USD","status":"delisted"},
  ]});
  let c=coinbase_catalog(&v);
  assert_eq!(c.len(),3,"只要 USD 对");
  assert_eq!(c["BTC-USD"].state,Listing::Trading);
  assert_eq!(c["XYZ-USD"].state,Listing::Halted);
  assert_eq!(c["OLD-USD"].state,Listing::Delisted);
 }

 #[test] fn diff_names_every_transition_once() {
  use Listing::*;
  let before=cat(&[("A",Trading,None),("B",Trading,None),("C",Halted,None),("D",Pending,None),("E",Trading,None),("F",Trading,None),("G",Delisted,None),("H",Trading,Some(1))]);
  let after=cat(&[("A",Trading,None),("B",Halted,None),("C",Trading,None),("D",Trading,None),("F",Delisted,None),("G",Trading,None),("H",Trading,Some(1)),("N",Trading,None),("P",Pending,None)]);
  let (changes,next)=diff(&before,&after);
  assert_eq!(events(&changes),vec![("B","halted"),("C","resumed"),("D","listed"),("E","delisted"),("F","delisted"),("G","listed"),("N","listed")]);
  assert_eq!(next["E"].state,Delisted,"表里消失的记成已下架");
  // 再比一次：没有新变化。
  let (again,_)=diff(&next,&after);
  assert!(again.is_empty(),"{again:?}");
  // 排上下架时间。
  let scheduled=cat(&[("A",Trading,Some(1790985600000))]);
  let (c,_)=diff(&cat(&[("A",Trading,None)]),&scheduled);
  assert_eq!(c,vec![Change{symbol:"A".into(),event:"delistScheduled",delivery_at:Some(1790985600000)}]);
  assert!(diff(&scheduled,&scheduled).0.is_empty(),"同一个下架时间不重复报");
 }

 #[test] fn a_truncated_table_is_not_a_mass_delisting() {
  let before:Catalog=(0..100).map(|i|(format!("S{i}"),Entry{state:Listing::Trading,delivery_at:None})).collect();
  let after:Catalog=(0..40).map(|i|(format!("S{i}"),Entry{state:Listing::Trading,delivery_at:None})).collect();
  assert!(!plausible(&before,&after));
  let after:Catalog=(0..60).map(|i|(format!("S{i}"),Entry{state:Listing::Trading,delivery_at:None})).collect();
  assert!(plausible(&before,&after));
 }

 #[test] fn texts_follow_the_protocol() {
  assert_eq!(texts("binance","ABCUSDT","delistScheduled",Some(1790985600000)),("ABCUSDT 将下架".into(),"币安合约 · 10月3日 08:00（北京时间）停止交易".into()));
  assert_eq!(texts("coinbase","XYZ-USD","listed",None),("新上线：XYZ-USD".into(),"Coinbase 现货".into()));
  assert_eq!(texts("binance","ABCUSDT","halted",None).1,"币安合约 · 你的自选");
 }
}
