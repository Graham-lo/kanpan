//! 要点引擎要的 REST 与库：起步时补一份历史（小时线、5 分钟线、持仓历史、资金费率历史、现货小时线；库里 3 天的
//! 足迹 / 爆仓分钟 / 大单），之后每 5 分钟取一次持仓、每 5 分钟取一次全市场资金费率。
//!
//! 全在一条后台任务里排队、一次一个（出站都走 `market_meta::get_json` 的币安闸门与出站节拍）。持仓与费率只用
//! 币安 U 本位永续（`openInterestHist` 是 USD 名义、带历史，断了能补）；没挂币安永续的 base 退到 OKX / Bybit /
//! Hyperliquid 的 K 线与此刻持仓，费率为 null（见报告里的限制）。
use super::super::{BINANCE,footprint,instruments::{self,Product}};
use super::events::Ended;
use super::ledger;
use super::stats::{DAY_MS,HOUR_MS};
use serde_json::Value;
use sqlx::{PgPool,Row};
use std::collections::{BTreeMap,HashMap};

const FAPI:&str="https://www.binance.com/fapi/v1";
const FUTURES_DATA:&str="https://www.binance.com/futures/data";
const SPOT:&str="https://data-api.binance.vision/api/v3";
const M:i64=60_000;

/// 这只 base 在币安的永续 / 现货代号与价格倍数（`1000PEPEUSDT` 的价是 1000 个币的价）。
#[derive(Clone,Debug,Default,PartialEq)]
pub(super) struct Symbols {pub perp:Option<(String,f64)>,pub spot:Option<(String,f64)>}

pub(super) async fn symbols(base:&str)->Symbols {
 let venues=instruments::venues(base).await;
 let find=|product:Product|venues.iter().find(|v|v.exchange==BINANCE&&v.product==product).map(|v|(v.instrument.clone(),v.price_scale.unwrap_or(1).max(1) as f64));
 Symbols{perp:find(Product::UsdtPerp),spot:find(Product::Spot)}
}

/// 一根 K 线（价已经换成每个币）。
#[derive(Clone,Copy,Debug,PartialEq)]
pub(super) struct K {pub t:i64,pub o:f64,pub h:f64,pub l:f64,pub c:f64}

/// 起步补的那一份。
#[derive(Clone,Debug,Default)]
pub(super) struct Boot {
 /// 参考永续近 25 小时的 1 分钟线（只收完的）与每分钟的净主动、成交额（币安按主动买入额：2 × 主动买 − 成交额）。
 pub minutes:Vec<K>,
 pub kflow:BTreeMap<i64,(f64,f64)>,
 /// 现货近 1 小时的 1 分钟线（现货溢价的此刻值）。
 pub spot_minutes:Vec<K>,
 pub hours:Vec<K>,
 pub fives:Vec<K>,
 pub spot_hours:Vec<K>,
 pub oi1h:Vec<(i64,f64)>,
 pub oi5:Vec<(i64,f64)>,
 pub funding:Vec<(i64,f64)>,
 /// 库里的分钟：净主动、成交额（全部家、合约 + 现货）。
 pub flow:BTreeMap<i64,(f64,f64)>,
 /// 库里的爆仓分钟：多、空、最大一笔的价。
 pub liq:BTreeMap<i64,(f64,f64,f64)>,
 /// 账本要补的那一段（`gap.0..gap.1`）里的成交（分钟、格 → 买、卖）与挂单（格 → 美元·分钟、分钟数）。
 pub fills:Vec<(i64,BTreeMap<i64,(f64,f64)>)>,
 pub walls:BTreeMap<i64,(f64,f64)>,
 /// 近 4 小时被吃 / 被撤、够得上事件的墙；近 3 天结束的墙的规模直方图（3 小时一格的起点、段、堵数）。
 pub ended:Vec<Ended>,
 pub sizes:Vec<(i64,i16,u32)>,
 pub gap:(i64,i64),
}

fn num(v:&Value)->Option<f64> {v.as_str().and_then(|s|s.parse().ok()).or_else(||v.as_f64()).filter(|x:&f64|x.is_finite())}

pub(super) fn parse_klines(v:&Value,scale:f64)->Vec<K> {
 crate::venues::binance::parse_klines(v).into_iter().map(|b|K{t:b.open_time,o:b.open/scale,h:b.high/scale,l:b.low/scale,c:b.close/scale}).collect()
}

/// 币安 1 分钟线 → (只收完的 K 线, 分钟 → (净主动, 成交额))。第 7 列成交额、第 10 列主动买入成交额（都是 USDT，不用换倍数）。
pub(super) fn parse_minutes(v:&Value,scale:f64,now:i64)->(Vec<K>,BTreeMap<i64,(f64,f64)>) {
 let mut flow=BTreeMap::new();
 for row in v.as_array().into_iter().flatten() {
  let (Some(t),Some(quote),Some(taker))=(row[0].as_i64(),num(&row[7]),num(&row[10])) else {continue};
  if t+M>now||quote<0.0||taker<0.0 {continue}
  flow.insert(t,(2.0*taker-quote,quote));
 }
 let bars=parse_klines(v,scale).into_iter().filter(|k|k.t+M<=now).collect();
 (bars,flow)
}

/// `openInterestHist`：`[{"sumOpenInterestValue":"…","timestamp":…}]` → (时刻, 美元)。
pub(super) fn parse_oi_hist(v:&Value)->Vec<(i64,f64)> {
 v.as_array().into_iter().flatten().filter_map(|r|Some((r["timestamp"].as_i64()?,num(&r["sumOpenInterestValue"])?))).filter(|(_,x)|*x>0.0).collect()
}

/// `fundingRate`：`[{"fundingTime":…,"fundingRate":"…"}]`。
pub(super) fn parse_funding_hist(v:&Value)->Vec<(i64,f64)> {
 v.as_array().into_iter().flatten().filter_map(|r|Some((r["fundingTime"].as_i64()?,num(&r["fundingRate"])?))).collect()
}

/// `premiumIndex`（全市场一次）：base → 下一期资金费率（`lastFundingRate`）。只收 U 本位（USDT 结尾）。
pub(super) fn parse_premium(v:&Value)->HashMap<String,f64> {
 let mut out=HashMap::new();
 for r in v.as_array().into_iter().flatten() {
  let (Some(symbol),Some(rate))=(r["symbol"].as_str(),num(&r["lastFundingRate"])) else {continue};
  let Some(listed)=symbol.strip_suffix("USDT").filter(|b|!b.is_empty()) else {continue};
  let (_,base)=instruments::scale_of(listed);
  out.insert(base.to_string(),rate);
 }
 out
}

async fn get(url:&str)->Option<Value> {crate::market_meta::get_json(url).await.ok()}

async fn binance_klines(root:&str,symbol:&str,interval:&str,limit:u32,scale:f64)->Vec<K> {
 let url=format!("{root}/klines?symbol={}&interval={interval}&limit={limit}",crate::instruments::url_component(symbol));
 get(&url).await.map(|v|parse_klines(&v,scale)).unwrap_or_default()
}

/// 没挂币安永续的：按 OKX → Bybit → Hyperliquid 取 K 线（代号 `XUSDT`）。
async fn other_klines(base:&str,step:i64,bars:i64)->Vec<K> {
 let now=chrono::Utc::now().timestamp();
 let key=format!("{base}USDT");
 for source in ["okx","bybit","hyperliquid"] {
  let Some(v)=crate::venues::venue(source) else {continue};
  if let Ok(rows)=v.candles(&key,step,now-step*bars,now+step).await && !rows.is_empty() {
   return rows.into_iter().map(|b|K{t:b.open_time,o:b.open,h:b.high,l:b.low,c:b.close}).collect();
  }
 }
 Vec::new()
}

/// 没挂币安永续的此刻持仓（美元）：OKX → Bybit → Hyperliquid。
pub(super) async fn other_oi(base:&str,price:Option<f64>)->Option<f64> {
 let key=format!("{base}USDT");
 for source in ["okx","bybit","hyperliquid"] {
  let Some(fut)=crate::venues::venue(source).and_then(|v|v.open_interest(&key)) else {continue};
  if let Ok(oi)=fut.await {
   let usd=oi.value.or_else(||price.map(|p|p*oi.open_interest));
   if let Some(usd)=usd.filter(|u|u.is_finite()&&*u>0.0) {return Some(usd)}
  }
 }
 None
}

/// 币安持仓历史：`period` 5m / 1h。
pub(super) async fn oi_hist(symbol:&str,period:&str,limit:u32)->Vec<(i64,f64)> {
 let url=format!("{FUTURES_DATA}/openInterestHist?symbol={}&period={period}&limit={limit}",crate::instruments::url_component(symbol));
 get(&url).await.map(|v|parse_oi_hist(&v)).unwrap_or_default()
}

pub(super) async fn funding_hist(symbol:&str,limit:u32)->Vec<(i64,f64)> {
 let url=format!("{FAPI}/fundingRate?symbol={}&limit={limit}",crate::instruments::url_component(symbol));
 get(&url).await.map(|v|parse_funding_hist(&v)).unwrap_or_default()
}

pub(super) async fn premium_all()->Option<HashMap<String,f64>> {get(&format!("{FAPI}/premiumIndex")).await.map(|v|parse_premium(&v)).filter(|m|!m.is_empty())}

/// 起步补历史：REST 一份 + 库里 3 天。`ledger_from..live_from` 是账本要补的那一段（上次落盘之后、这次开始收之前）。
pub(super) async fn boot(pool:&PgPool,base:&str,ledger_from:i64,live_from:i64,now:i64)->Boot {
 let out=std::sync::Mutex::new(Boot::default());
 boot_into(pool,base,ledger_from,live_from,now,&out).await;
 out.into_inner().unwrap_or_else(|e|e.into_inner())
}

/// 同 [`boot`]，但各路并发、谁先回来谁先写进 `out`——打开一只没在跟的品种时接口最多等 2 秒，到点就拿已经回来的那几样先算。
pub(super) async fn boot_into(pool:&PgPool,base:&str,ledger_from:i64,live_from:i64,now:i64,out:&std::sync::Mutex<Boot>) {
 let put=|f:&mut dyn FnMut(&mut Boot)|f(&mut out.lock().unwrap_or_else(|e|e.into_inner()));
 put(&mut |b|b.gap=(ledger_from,live_from));
 let s=symbols(base).await;
 let spot=async {
  if let Some((sym,scale))=&s.spot {
   let (hours,minutes)=tokio::join!(binance_klines(SPOT,sym,"1h",500,*scale),binance_klines(SPOT,sym,"1m",60,*scale));
   put(&mut |b|{b.spot_hours=hours.clone();b.spot_minutes=minutes.iter().copied().filter(|k|k.t+M<=now).collect();});
  }
 };
 let db=async {
  let mut local=Boot{gap:(ledger_from,live_from),..Boot::default()};
  if let Err(e)=read_db(pool,base,&mut local,now).await {tracing::warn!("Orderflow highlights: {base} history unreadable: {e}");}
  let mut local=Some(local);
  put(&mut |b|if let Some(l)=local.take() {b.flow=l.flow;b.liq=l.liq;b.fills=l.fills;b.walls=l.walls;b.ended=l.ended;b.sizes=l.sizes;});
 };
 match &s.perp {
  Some((sym,scale))=>{
   let scale=*scale;
   tokio::join!(
    async {
     let url=format!("{FAPI}/klines?symbol={}&interval=1m&limit=1500",crate::instruments::url_component(sym));
     if let Some(v)=get(&url).await {let (k,f)=parse_minutes(&v,scale,now);let mut kf=Some((k,f));put(&mut |b|if let Some((k,f))=kf.take() {b.minutes=k;b.kflow=f;});}
    },
    async {let v=binance_klines(FAPI,sym,"1h",500,scale).await;let mut v=Some(v);put(&mut |b|if let Some(v)=v.take() {b.hours=v;});},
    async {let v=binance_klines(FAPI,sym,"5m",300,scale).await;let mut v=Some(v);put(&mut |b|if let Some(v)=v.take() {b.fives=v;});},
    async {let v=oi_hist(sym,"1h",500).await;let mut v=Some(v);put(&mut |b|if let Some(v)=v.take() {b.oi1h=v;});},
    async {let v=oi_hist(sym,"5m",300).await;let mut v=Some(v);put(&mut |b|if let Some(v)=v.take() {b.oi5=v;});},
    async {let v=funding_hist(sym,100).await;let mut v=Some(v);put(&mut |b|if let Some(v)=v.take() {b.funding=v;});},
    spot,db,
   );
  },
  None=>{
   tokio::join!(
    async {let v:Vec<K>=other_klines(base,60,600).await.into_iter().filter(|k|k.t+M<=now).collect();let mut v=Some(v);put(&mut |b|if let Some(v)=v.take() {b.minutes=v;});},
    async {let v=other_klines(base,3600,500).await;let mut v=Some(v);put(&mut |b|if let Some(v)=v.take() {b.hours=v;});},
    async {let v=other_klines(base,300,300).await;let mut v=Some(v);put(&mut |b|if let Some(v)=v.take() {b.fives=v;});},
    async {
     let at=now.div_euclid(5*M)*5*M;
     if let Some(v)=other_oi(base,None).await {put(&mut |b|{b.oi5=vec![(at,v)];b.oi1h=vec![(at.div_euclid(HOUR_MS)*HOUR_MS,v)];});}
    },
    spot,db,
   );
  },
 }
}

/// 库里 3 天：足迹（净主动、成交额；账本缺口里的成交）、爆仓分钟、大单（账本缺口里的挂单分钟、近 3 天结束的墙）。
async fn read_db(pool:&PgPool,base:&str,b:&mut Boot,now:i64)->sqlx::Result<()> {
 let from=now-3*DAY_MS;
 let (gap_from,gap_to)=b.gap;
 let rows=sqlx::query("SELECT minute_ms,step,levels FROM orderflow_footprint WHERE base=$1 AND minute_ms>=$2 ORDER BY minute_ms").bind(base).bind(from).fetch_all(pool).await?;
 for r in rows {
  let (minute,step,bytes):(i64,f64,Vec<u8>)=(r.try_get(0)?,r.try_get(1)?,r.try_get(2)?);
  let Some(levels)=footprint::Minute::unpack(&bytes) else {continue};
  if !(step>0.0) {continue}
  let (net,vol,fills)=fold_levels(&levels,step);
  b.flow.insert(minute,(net,vol));
  if minute>=gap_from&&minute<gap_to {b.fills.push((minute,fills));}
 }
 let rows=sqlx::query("SELECT minute_ms,long_usd,short_usd,max_price FROM orderflow_liq WHERE base=$1 AND minute_ms>=$2").bind(base).bind(from).fetch_all(pool).await?;
 for r in rows {b.liq.insert(r.try_get(0)?,(r.try_get(1)?,r.try_get(2)?,r.try_get(3)?));}
 // 挂单。ETH 3 天结束的墙有 12 万多堵，不逐条读回：账本缺口里的挂单分钟按格在库里加好，规模只要直方图，
 // 逐条的只要近 4 小时被吃 / 被撤的（事件）。都走覆盖索引 (base,end_ms,first_seen_ms) INCLUDE (…)。
 let walls=sqlx::query("SELECT floor(ln(price)/ln(1.0008))::bigint AS k,\
   sum(initial_notional*(LEAST(COALESCE(end_ms,$3),$3)-GREATEST(first_seen_ms,$2))/60000.0)::float8,\
   sum((LEAST(COALESCE(end_ms,$3),$3)-GREATEST(first_seen_ms,$2))/60000.0)::float8 \
  FROM (SELECT price,first_seen_ms,end_ms,initial_notional FROM orderflow_orders WHERE base=$1 AND end_ms>=$2 AND first_seen_ms<$3 \
        UNION ALL SELECT price,first_seen_ms,NULL,initial_notional FROM orderflow_live WHERE base=$1 AND first_seen_ms<$3) o \
  WHERE price>0 AND initial_notional>0 GROUP BY 1")
  .bind(base).bind(gap_from).bind(gap_to).fetch_all(pool).await?;
 for r in walls {
  let (k,usd_min,minutes):(i64,Option<f64>,Option<f64>)=(r.try_get(0)?,r.try_get(1)?,r.try_get(2)?);
  if let (Some(u),Some(m))=(usd_min,minutes) && u>0.0 {b.walls.insert(k,(u,m));}
 }
 let sizes=sqlx::query("SELECT (end_ms/$3)*$3,floor(log(initial_notional)*16)::int4,count(*)::int8 FROM orderflow_orders \
  WHERE base=$1 AND end_ms>=$2 AND status<>'lost' AND initial_notional>0 GROUP BY 1,2")
  .bind(base).bind(from).bind(super::stats::SIZE_BLOCK_MS).fetch_all(pool).await?;
 for r in sizes {
  let (block,bin,n):(i64,i32,i64)=(r.try_get(0)?,r.try_get(1)?,r.try_get(2)?);
  b.sizes.push((block,bin as i16,n.clamp(0,i64::from(u32::MAX)) as u32));
 }
 let recent=sqlx::query("SELECT side,price,end_ms,status,initial_notional,notional,filled_notional FROM orderflow_orders \
  WHERE base=$1 AND end_ms>=$2 AND status IN ('filled','cancelled')")
  .bind(base).bind(now-super::events::WINDOW_MS).fetch_all(pool).await?;
 for r in recent {
  let (side,price,end,status):(String,f64,i64,String)=(r.try_get(0)?,r.try_get(1)?,r.try_get(2)?,r.try_get(3)?);
  let (initial,left,filled):(f64,f64,f64)=(r.try_get(4)?,r.try_get(5)?,r.try_get(6)?);
  let e=Ended{bid:side=="bid",price,initial,filled,left,cancelled:status=="cancelled",end};
  if super::events::candidate(&e) {b.ended.push(e);}
 }
 Ok(())
}

/// 足迹一分钟的各桶 → 净主动、成交额、按账本格并好的买卖额。
pub(super) fn fold_levels(levels:&BTreeMap<i64,(f64,f64)>,step:f64)->(f64,f64,BTreeMap<i64,(f64,f64)>) {
 let (mut net,mut vol)=(0.0,0.0);
 let mut fills:BTreeMap<i64,(f64,f64)>=BTreeMap::new();
 for (&i,&(buy,sell)) in levels {
  net+=buy-sell;vol+=buy+sell;
  let e=fills.entry(ledger::key((i as f64+0.5)*step)).or_insert((0.0,0.0));
  e.0+=buy;e.1+=sell;
 }
 (net,vol,fills)
}

/// 每 5 分钟的持仓：币安取 5 分钟历史最后几点（断了几点也补得上），整点再取一次小时历史；别家取此刻一点。
pub(super) async fn oi(base:&str,hourly:bool,price:Option<f64>,now:i64)->(Vec<(i64,f64)>,Vec<(i64,f64)>) {
 match symbols(base).await.perp {
  Some((sym,_))=>{
   let five=oi_hist(&sym,"5m",6).await;
   let hour=if hourly {oi_hist(&sym,"1h",3).await} else {Vec::new()};
   (five,hour)
  },
  None=>{
   let at=now.div_euclid(5*M)*5*M;
   let one:Vec<(i64,f64)>=other_oi(base,price).await.map(|v|(at,v)).into_iter().collect();
   let hour=if hourly {one.iter().map(|(t,v)|(t.div_euclid(HOUR_MS)*HOUR_MS,*v)).collect()} else {Vec::new()};
   (one,hour)
  },
 }
}

#[cfg(test)]
mod tests {
 use super::*;
 use serde_json::json;

 #[test]
 fn parses_binance_payloads() {
  let oi=json!([{"symbol":"BTCUSDT","sumOpenInterest":"1","sumOpenInterestValue":"8000000000.5","timestamp":1_700_000_000_000_i64}]);
  assert_eq!(parse_oi_hist(&oi),vec![(1_700_000_000_000,8_000_000_000.5)]);
  let f=json!([{"symbol":"BTCUSDT","fundingTime":5,"fundingRate":"0.0001"}]);
  assert_eq!(parse_funding_hist(&f),vec![(5,0.0001)]);
  let p=json!([{"symbol":"1000PEPEUSDT","lastFundingRate":"0.0005"},{"symbol":"BTCUSDC","lastFundingRate":"0.1"},{"symbol":"ETHUSDT","lastFundingRate":"-0.0002"}]);
  let m=parse_premium(&p);
  assert_eq!(m.get("PEPE"),Some(&0.0005));
  assert_eq!(m.get("ETH"),Some(&-0.0002));
  assert_eq!(m.len(),2);
  let k=json!([[1000,"2000","2100","1900","2050","1","1999","0","0","0","0","0"]]);
  assert_eq!(parse_klines(&k,1000.0),vec![K{t:1000,o:2.0,h:2.1,l:1.9,c:2.05}]);
  // 1 分钟线：净主动 = 2 × 主动买入额 − 成交额；还没收完的那根不要。
  let m=json!([[0,"1","1","1","1","5","59999","1000","9","3","600","0"],[60000,"1","1","1","1","5","119999","500","9","1","100","0"]]);
  let (bars,flow)=parse_minutes(&m,1.0,100_000);
  assert_eq!(bars.len(),1);
  assert_eq!(flow.into_iter().collect::<Vec<_>>(),vec![(0,(200.0,1000.0))]);
 }

 #[test]
 fn footprint_levels_fold_into_ledger_buckets() {
  let mut levels=BTreeMap::new();
  levels.insert(10_000,(3.0,1.0));
  levels.insert(10_001,(0.0,2.0));
  let (net,vol,fills)=fold_levels(&levels,0.01);
  assert_eq!((net,vol),(0.0,6.0));
  assert_eq!(fills.values().map(|(b,s)|b+s).sum::<f64>(),6.0);
  assert!(fills.len()<=2&&fills.keys().all(|k|ledger::low(*k)<=100.015&&ledger::high(*k)>100.005));
 }
}
