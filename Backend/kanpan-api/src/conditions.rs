//! 条件提醒（`kind:"condition"`）：费率、持仓量、均线、大单。
//!
//! 协议是 `docs/条件提醒-协议-2026-09-27.md`，这里是它的服务端那一半：
//!
//! - [`Rule`]：同步对象里 `rule` 的形状与校验（`sync_validation` 按 [`valid_rule`] 收）；
//! - 前三种（[`judge_funding`] / [`judge_open_interest`] / [`judge_ma`]）在 `kanpan-worker` 里判，
//!   [`run`] 是它们的常驻循环：费率每分钟看一眼、落在结算前 15 分钟那个窗口里判一次；持仓量每个
//!   新的 5 分钟点判一次；均线在每根 K 线收盘后几秒判，同一品种同一周期的所有提醒合一次 K 线请求；
//! - 大单在 `serve` 里判（跟踪器在那个进程），见 [`walls`]；
//! - 技术指标（2026-10-07，均线金叉死叉 / RSI 穿越 / 收盘突破，`rule` 用 `kind` 区分）也在 worker 里、
//!   按收盘判，见 [`indicators`]。
//!
//! 触发一律走 [`fire`]：`alerts::record_fired`（同一个事务置 fired + 写同步 op，`WHERE status='active'`
//! 就是「只响一次」的那道闸）→ Webhook → 推送。判定函数都是纯的（给定行情、给定时刻），
//! 循环只负责取数和排时间，这样「按时判」能在测试里直接喂数据验。
use crate::{AppState,alerts,apns::Apns,error::Result};
use rust_decimal::{Decimal,RoundingStrategy,prelude::ToPrimitive};
use serde_json::{Value,json};
use sqlx::Row;
use std::collections::{BTreeMap,HashMap,HashSet};
use std::sync::Arc;
use std::time::Duration;
use uuid::Uuid;

pub mod indicators;
pub mod walls;

// ——————————————————————————— 形状 ———————————————————————————

/// `rule` 序列化后最多几个字节。
pub const RULE_MAX_BYTES:usize=1024;
/// 均线条件能选的周期：客户端周期条的代号去掉 `1y`（币安没有年线，客户端是自己拼的）。
pub const MA_INTERVALS:[&str;13]=["1m","3m","5m","15m","30m","1h","2h","4h","6h","12h","1d","1w","1M"];
/// MA 的 N 上限。K 线一次最多取 1500 根，N + 2 根够判。
pub const MA_MAX_LENGTH:usize=1000;
/// 费率在结算前多久判。
pub const FUNDING_WINDOW_MS:i64=15*60_000;
/// 持仓量比的是多久以前。
pub const OI_SPAN_MS:i64=60*60_000;
/// 持仓量历史的点距（`openInterestHist?period=5m`）。
pub const OI_PERIOD_MS:i64=5*60_000;

#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum Side {Above,Below}
impl Side {
 fn parse(v:Option<&Value>)->Option<Self> {match v?.as_str()? {"above"=>Some(Side::Above),"below"=>Some(Side::Below),_=>None}}
}

/// 一条条件提醒的条件本体。
#[derive(Clone,Debug,PartialEq)]
pub enum Rule {
 /// 结算前 15 分钟的预测费率高于 / 低于 `rate`（比值）。
 Funding{side:Side,rate:Decimal},
 /// 1 小时持仓量（币数量）变化幅度的绝对值 ≥ `threshold`（比值）。
 OpenInterest{threshold:Decimal},
 /// `interval` 周期收盘站上 / 跌破 MA`length`。
 MaCross{interval:String,length:usize,side:Side},
 /// 出现一面名义 ≥ `threshold` 美元的新大单墙。
 Wall{threshold:Decimal},
 /// 技术指标（均线金叉死叉 / RSI 穿越 / 收盘突破）：`rule` 用 `kind` 区分，见 [`indicators`]。
 Indicator(indicators::Indicator),
 /// 更新版本的客户端写的、这一版服务端还认不得的条件：收下、存着、不判。
 Unknown(String),
}

fn decimal_in(v:Option<&Value>,lo:Decimal,hi:Decimal)->Option<Decimal> {
 v?.as_str().and_then(crate::sync_validation::decimal).filter(|d|*d>=lo&&*d<=hi)
}
fn d(text:&str)->Decimal {text.parse().expect("constant decimal")}

impl Rule {
 /// 解一个 `rule`。`None` 是「形状不对」（整条 op 该拒收）；认不得的 `type` 是 `Some(Unknown)`。
 /// 没有 `type` 的是技术指标条件（`kind` 区分，和网页端约定的线格式），交给 [`indicators::parse`]。
 pub fn parse(v:&Value)->Option<Rule> {
  let o=v.as_object()?;
  if serde_json::to_string(v).map_or(true,|t|t.len()>RULE_MAX_BYTES) {return None}
  let Some(kind)=o.get("type") else {return indicators::parse(o,v)};
  let kind=kind.as_str()?;
  if !(1..=40).contains(&kind.len())||!kind.bytes().all(|b|b.is_ascii_alphabetic()) {return None}
  Some(match kind {
   "funding"=>Rule::Funding{side:Side::parse(o.get("side"))?,rate:decimal_in(o.get("rate"),d("-0.1"),d("0.1"))?},
   "openInterestChange"=>Rule::OpenInterest{threshold:decimal_in(o.get("threshold"),d("0.001"),d("10"))?},
   "maCross"=>{
    let interval=o.get("interval")?.as_str().filter(|i|MA_INTERVALS.contains(i))?.to_string();
    let length=o.get("length")?.as_u64().filter(|n|(1..=MA_MAX_LENGTH as u64).contains(n))? as usize;
    Rule::MaCross{interval,length,side:Side::parse(o.get("side"))?}
   }
   "orderflowWall"=>Rule::Wall{threshold:decimal_in(o.get("threshold"),d("10000"),d("10000000000"))?},
   other=>Rule::Unknown(other.to_string()),
  })
 }
 /// 协议里的 `type`。
 pub fn kind(&self)->&str {
  match self {Rule::Funding{..}=>"funding",Rule::OpenInterest{..}=>"openInterestChange",Rule::MaCross{..}=>"maCross",Rule::Wall{..}=>"orderflowWall",Rule::Indicator(i)=>i.kind(),Rule::Unknown(k)=>k}
 }
 /// `{条件}`，也是默认标题去掉品种名那一段：「资金费率高于 0.05%」。
 pub fn phrase(&self)->String {
  match self {
   Rule::Funding{side,rate}=>format!("资金费率{} {}%",if *side==Side::Above {"高于"} else {"低于"},percent(*rate,6)),
   Rule::OpenInterest{threshold}=>format!("1 小时持仓量变化超过 {}%",percent(*threshold,4)),
   Rule::MaCross{interval,length,side}=>format!("{interval} 收盘{} MA{length}",if *side==Side::Above {"站上"} else {"跌破"}),
   Rule::Wall{threshold}=>format!("出现 {} 以上的大单墙",units(threshold.to_f64().unwrap_or_default())),
   Rule::Indicator(i)=>i.phrase(),
   Rule::Unknown(_)=>"条件提醒".into(),
  }
 }
}

/// `sync_validation` 用：`rule` 这个值收不收。
pub fn valid_rule(v:&Value)->bool {Rule::parse(v).is_some()}

/// 比值 → 百分数的数字部分（`0.0005` → `0.05`），最多 `dp` 位小数、去掉尾巴上的 0。
pub fn percent(ratio:Decimal,dp:u32)->String {
 (ratio*Decimal::ONE_HUNDRED).round_dp_with_strategy(dp,RoundingStrategy::MidpointAwayFromZero).normalize().to_string()
}
/// 带符号的百分数（`+6.21%` / `-3.5%`）。
fn signed_percent(ratio:Decimal,dp:u32)->String {
 let text=percent(ratio,dp);
 if ratio.is_sign_positive()&&!ratio.is_zero()&&!text.starts_with('-') {format!("+{text}%")} else {format!("{text}%")}
}
/// 金额的 K / M / B / T（`12400000` → `12.4M`，`5000000` → `5M`）。
pub fn units(v:f64)->String {
 let a=v.abs();
 let (n,u)=if a>=1e12 {(v/1e12,"T")} else if a>=1e9 {(v/1e9,"B")} else if a>=1e6 {(v/1e6,"M")} else if a>=1e3 {(v/1e3,"K")} else {(v,"")};
 let text=format!("{n:.1}");
 let text=text.strip_suffix(".0").unwrap_or(&text);
 format!("{text}{u}")
}

// ——————————————————————————— 一条提醒 ———————————————————————————

/// 内存里的一条活动条件提醒。
#[derive(Clone,Debug)]
pub struct CondAlert {
 pub owner:Uuid,pub alert_id:String,pub symbol:String,pub market:String,
 pub rule:Rule,pub rule_json:Value,pub armed_at:i64,pub title:String,
 pub note:Option<String>,pub webhook:Option<String>,pub webhook_text:Option<String>,
}
impl CondAlert {
 /// 推送标题 / Webhook `title`：客户端写的标题；空就「BTC 资金费率高于 0.05%」。
 /// 技术指标提醒一律是「BTCUSDT 15m：EMA9 上穿 SMA21」（全代号 + 条件，和网页端约定的推送文案）。
 pub fn title(&self)->String {
  if let Rule::Indicator(i)=&self.rule {return format!("{} {}",self.symbol,i.phrase())}
  if self.title.trim().is_empty() {format!("{} {}",crate::watch_move::short(&self.symbol),self.rule.phrase())} else {self.title.clone()}
 }
}

/// 一次触发时观测到的东西。
#[derive(Clone,Debug,PartialEq)]
pub struct Observation {
 /// 触发时刻（毫秒），写进 `firedAt`。
 pub at:i64,
 /// 写进 `firedPrice` 的那个价（各条件是什么见协议第 2 节）。
 pub price:f64,
 /// 推送正文 / Webhook `detail` / `{数值}`：「预测费率 0.0612% · 14 分钟后结算」。
 pub detail:String,
 /// Webhook 的 `value`。
 pub value:Value,
}

/// 一条条件提醒此刻判下来响了。
pub type Hit=(CondAlert,Observation);

/// 把所有人的活动条件提醒读出来（逐个用户开事务，同 `alerts::load` 的理由：FORCE RLS）。
/// 认不得的 `type` 留在库里、不判，每种只 warn 一次。
pub async fn load(s:&AppState)->Result<Vec<CondAlert>> {
 static WARNED:std::sync::Mutex<Option<HashSet<String>>>=std::sync::Mutex::new(None);
 let mut out=vec![];
 let mut after:Option<Uuid>=None;
 loop {
  let owners:Vec<Uuid>=sqlx::query_scalar("SELECT id FROM account_users WHERE disabled_at IS NULL AND ($1::uuid IS NULL OR id>$1) ORDER BY id LIMIT 100").bind(after).fetch_all(&s.pool).await?;
  if owners.is_empty() {break}
  for owner in &owners {
   let mut tx=match s.personal(*owner).await {Ok(tx)=>tx,Err(_)=>continue};
   let rows=sqlx::query("SELECT alert_id,symbol,market,rule,armed_at,title,note,webhook,webhook_text FROM alert_watches WHERE user_id=$1 AND status='active' AND kind='condition'")
    .bind(owner).fetch_all(&mut *tx).await?;
   tx.commit().await?;
   for r in rows {
    // 费率、持仓量、均线、大单这几样数据都只从币安来（`PREMIUM_INDEX`、`/fapi` K 线）。
    // 别家的条件提醒（客户端本不该建，例如美元指数 `macro/index`）留在库里、不判，免得拿它的
    // 代号去问币安、每分钟白发一串必败的请求。
    let market:String=r.get("market");
    if market!=alerts::BINANCE {continue}
    let rule_json:Option<Value>=r.get("rule");
    let Some(rule_json)=rule_json else {continue};
    let Some(rule)=Rule::parse(&rule_json) else {tracing::warn!("A condition alert has an unusable rule and will not be evaluated");continue};
    if let Rule::Unknown(kind)=&rule {
     let mut warned=WARNED.lock().unwrap_or_else(|e|e.into_inner());
     if warned.get_or_insert_with(HashSet::new).insert(kind.clone()) {tracing::warn!("Condition alerts of type {kind:?} are stored but this server does not evaluate them")}
     continue
    }
    out.push(CondAlert{owner:*owner,alert_id:r.get("alert_id"),symbol:r.get("symbol"),market,rule,rule_json,
     armed_at:r.get("armed_at"),title:r.get("title"),note:r.get("note"),webhook:r.get("webhook"),webhook_text:r.get("webhook_text")});
   }
  }
  after=owners.last().copied();
 }
 Ok(out)
}

// ——————————————————————————— 触发 ———————————————————————————

/// 默认的 Webhook 文案模板（条件提醒）。
pub const DEFAULT_WEBHOOK_TEXT:&str="{品种} {条件}，{数值}";

/// 推送正文：`detail`，有备注接在后面。
pub fn notice_body(o:&Observation,note:Option<&str>)->String {
 match note.map(str::trim).filter(|n|!n.is_empty()) {Some(note)=>format!("{} · {note}",o.detail),None=>o.detail.clone()}
}
/// 推送的样子（`kind:"alert"`，点开品种）。
pub fn notice(a:&CondAlert,o:&Observation)->alerts::Notice {
 alerts::Notice{title:a.title(),body:notice_body(o,a.note.as_deref()),link:format!("hkline://symbol/{}",alerts::symbol_path(&a.market,&a.symbol)),kind:"alert"}
}
/// Webhook 的 `text`。
pub fn webhook_text(a:&CondAlert,o:&Observation)->String {
 let note=a.note.as_deref().unwrap_or_default();
 alerts::render_template(a.webhook_text.as_deref(),DEFAULT_WEBHOOK_TEXT,|key|Some(match key {
  "品种"=>alerts::webhook_name(&a.market,&a.symbol),
  "代号"=>a.symbol.clone(),
  "价格"=>alerts::webhook_money(o.price),
  "目标价"=>String::new(),
  "条件"=>a.rule.phrase(),
  "数值"=>o.detail.clone(),
  "时间"=>alerts::iso_time(o.at),
  "备注"=>note.to_string(),
  _=>return None,
 }))
}
/// POST 出去的那份 JSON：价格提醒的 14 个键，外加 `rule` / `detail` / `value`（协议第 4 节）。
pub fn webhook_body(a:&CondAlert,o:&Observation)->Value {
 json!({
  "event":"alert","alertId":a.alert_id,"symbol":a.symbol,"market":a.market,
  "name":alerts::webhook_name(&a.market,&a.symbol),"title":a.title(),"condition":a.rule.kind(),
  "once":true,"target":Value::Null,"price":o.price,"firedAt":o.at,"time":alerts::iso_time(o.at),
  "note":a.note.as_deref().unwrap_or_default(),"text":webhook_text(a,o),
  "rule":a.rule_json,"detail":o.detail,"value":o.value,
 })
}

/// 触发一条：置 fired + 写同步 op（同一个事务）→ Webhook → 推送。返回「这一下真的是我触发的」。
/// 已经不是 active（暂停、已触发、删了）返回 `false`，什么都不发。
pub async fn fire(s:&AppState,apns:Option<&Apns>,a:&CondAlert,o:&Observation)->Result<bool> {
 if !alerts::record_fired(s,a.owner,&a.alert_id,Some(o.price),o.at).await? {return Ok(false)}
 if let Some(url)=a.webhook.as_deref().filter(|u|!u.is_empty()) {
  alerts::post_webhook(a.alert_id.clone(),url.to_string(),webhook_body(a,o));
 }
 let Some(apns)=apns else {
  tracing::info!("{} condition {} ({}) triggered: {}; recorded and synced, not pushed (no APNs key)",a.symbol,a.alert_id,a.rule.kind(),o.detail);
  return Ok(true)
 };
 if let Err(e)=alerts::notify(s,apns,a.owner,&notice(a,o)).await {tracing::warn!("A condition alert fired but could not be pushed ({e:?})")}
 Ok(true)
}

// ——————————————————————————— 费率 ———————————————————————————

/// `premiumIndex` 里一个品种的一行。
#[derive(Clone,Debug,PartialEq)]
pub struct Premium {pub rate:Decimal,pub mark:f64,pub next_funding:i64}

/// `premiumIndex`（全市场一次）→ 品种 → 行。没有下一次结算（交割合约、`nextFundingTime` 为 0）的不收。
pub fn parse_premium(v:&Value)->HashMap<String,Premium> {
 let mut out=HashMap::new();
 for row in v.as_array().map(Vec::as_slice).unwrap_or(&[]) {
  let (Some(symbol),Some(rate),Some(mark),Some(next))=(row["symbol"].as_str(),row["lastFundingRate"].as_str().and_then(|t|t.parse::<Decimal>().ok()),
   crate::market_meta::num(&row["markPrice"]),row["nextFundingTime"].as_i64()) else {continue};
  if next<=0 {continue}
  out.insert(symbol.to_string(),Premium{rate,mark,next_funding:next});
 }
 out
}

/// 费率：`now` 落在某条提醒那只品种的「结算前 15 分钟」窗口里、这一次结算还没判过，就判一次。
/// `judged` 记「这条提醒判过的是哪一次结算」，跨调用保留。
pub fn judge_funding(alerts:&[CondAlert],table:&HashMap<String,Premium>,now:i64,judged:&mut HashMap<String,i64>)->Vec<Hit> {
 let mut hits=vec![];
 for a in alerts {
  let Rule::Funding{side,rate}=a.rule else {continue};
  let Some(p)=table.get(&a.symbol) else {continue};
  let settle=p.next_funding;
  if now<settle-FUNDING_WINDOW_MS||now>=settle||now<a.armed_at {continue}
  if judged.get(&a.alert_id)==Some(&settle) {continue}
  judged.insert(a.alert_id.clone(),settle);
  let met=match side {Side::Above=>p.rate>=rate,Side::Below=>p.rate<=rate};
  if !met {continue}
  let minutes=(settle-now+59_999)/60_000;
  hits.push((a.clone(),Observation{at:now,price:p.mark,
   detail:format!("预测费率 {}% · {minutes} 分钟后结算",percent(p.rate,4)),
   value:json!({"rate":p.rate.normalize().to_string(),"markPrice":p.mark.to_string(),"nextFundingTime":settle})}));
 }
 hits
}

// ——————————————————————————— 持仓量 ———————————————————————————

/// `openInterestHist` 的一个点。
#[derive(Clone,Debug,PartialEq)]
pub struct OiPoint {pub at:i64,pub amount:Decimal,pub value:Decimal}
pub fn parse_open_interest(v:&Value)->Vec<OiPoint> {
 let mut out:Vec<OiPoint>=v.as_array().map(Vec::as_slice).unwrap_or(&[]).iter().filter_map(|row|Some(OiPoint{
  at:row["timestamp"].as_i64()?,amount:row["sumOpenInterest"].as_str()?.parse().ok()?,value:row["sumOpenInterestValue"].as_str()?.parse().ok()?,
 })).collect();
 out.sort_by_key(|p|p.at);
 out
}

/// 持仓量：拿最新一个点 `L` 和恰好 1 小时前的点 `P` 比，`|变化| ≥ threshold` 就响。
/// 只看 `L.at ≥ armedAt`；缺 `P` 不判。调用方保证同一个 `L` 只判一次。
pub fn judge_open_interest(alerts:&[CondAlert],symbol:&str,points:&[OiPoint],now:i64)->Vec<Hit> {
 let Some(last)=points.last() else {return vec![]};
 let Some(before)=points.iter().find(|p|p.at==last.at-OI_SPAN_MS) else {return vec![]};
 if before.amount.is_zero()||last.amount.is_zero() {return vec![]}
 let change=(last.amount-before.amount)/before.amount;
 let price=(last.value/last.amount).to_f64().unwrap_or_default();
 let mut hits=vec![];
 for a in alerts {
  let Rule::OpenInterest{threshold}=a.rule else {continue};
  if a.symbol!=symbol||last.at<a.armed_at||change.abs()<threshold {continue}
  hits.push((a.clone(),Observation{at:now,price,
   detail:format!("1 小时持仓量 {} · 现价 {}",signed_percent(change,2),alerts::money(price)),
   value:json!({"change":change.round_dp(8).normalize().to_string(),"from":before.amount.normalize().to_string(),"to":last.amount.normalize().to_string(),"at":last.at})}));
 }
 hits
}

// ——————————————————————————— 均线 ———————————————————————————

/// 一根 K 线（币安 `klines` 的一行）。
#[derive(Clone,Copy,Debug,PartialEq)]
pub struct Bar {pub open_time:i64,pub close:f64,pub close_time:i64}
pub fn parse_klines(v:&Value)->Vec<Bar> {
 v.as_array().map(Vec::as_slice).unwrap_or(&[]).iter().filter_map(|row|Some(Bar{
  open_time:row[0].as_i64()?,close:crate::market_meta::num(&row[4])?,close_time:row[6].as_i64()?,
 })).collect()
}
/// 收盘价的简单移动平均，含第 `k` 根：和客户端 `KanpanCore` 的 `sma` 一个口径。
pub fn sma(closes:&[f64],k:usize,n:usize)->Option<f64> {
 if n==0||k+1<n||k>=closes.len() {return None}
 Some(closes[k+1-n..=k].iter().sum::<f64>()/n as f64)
}

/// 均线：`bars` 里**已收盘**的最后一根 `k` 与前一根比，边沿穿过才响。
/// `bars` 只能是已收盘的（调用方把正在走的那一根剔掉）；只判收盘时刻晚于 armedAt 的。
pub fn judge_ma(alerts:&[CondAlert],symbol:&str,interval:&str,bars:&[Bar],now:i64)->Vec<Hit> {
 let Some(k)=bars.len().checked_sub(1) else {return vec![]};
 let closes:Vec<f64>=bars.iter().map(|b|b.close).collect();
 let bar=bars[k];
 let closed_at=bar.close_time+1;
 let mut hits=vec![];
 for a in alerts {
  let Rule::MaCross{interval:ref want,length,side}=a.rule else {continue};
  if a.symbol!=symbol||want!=interval||closed_at<=a.armed_at||k<length {continue}
  let (Some(now_ma),Some(prev_ma))=(sma(&closes,k,length),sma(&closes,k-1,length)) else {continue};
  let (c,p)=(closes[k],closes[k-1]);
  let crossed=match side {Side::Above=>p<prev_ma&&c>=now_ma,Side::Below=>p>prev_ma&&c<=now_ma};
  if !crossed {continue}
  hits.push((a.clone(),Observation{at:now,price:c,
   detail:format!("收盘 {} · MA{length} {}",alerts::money(c),alerts::money(now_ma)),
   value:json!({"close":c.to_string(),"ma":now_ma.to_string(),"openTime":bar.open_time,"closeTime":closed_at})}));
 }
 hits
}

/// 一组（同一品种同一周期）均线提醒的排程状态。
#[derive(Clone,Copy,Debug,Default,PartialEq)]
pub struct MaClock {
 /// 下一根收盘的时刻（正在走的那一根的 closeTime + 1）。不知道就是 None：马上取一次。
 pub next_close:Option<i64>,
 /// 上一次判过的那根的收盘时刻。
 pub judged:i64,
 /// 最早什么时候再取（重试间隔用）。
 pub not_before:i64,
}
/// 收盘后多久去取（等币安把那一根收好）。
pub const MA_SETTLE_MS:i64=2_000;
/// 取回来还没滚到新的一根时，隔多久再取。
pub const MA_RETRY_MS:i64=5_000;
/// 过了收盘这么久还没滚过去，就不再等这一根，重新对表。
pub const MA_GIVE_UP_MS:i64=60_000;
impl MaClock {
 /// 此刻该不该去取 K 线。
 pub fn due(&self,now:i64)->bool {
  now>=self.not_before&&self.next_close.is_none_or(|close|now>=close+MA_SETTLE_MS)
 }
 /// 拿一次取回来的 K 线（含正在走的那一根）更新排程，返回要判的已收盘 K 线（这一根判过了就是 None）。
 pub fn advance(&mut self,rows:&[Bar],now:i64)->Option<Vec<Bar>> {
  let forming=rows.last().filter(|b|b.close_time>=now).copied();
  let closed:Vec<Bar>=rows.iter().filter(|b|b.close_time<now).copied().collect();
  let latest=closed.last().map(|b|b.close_time+1).unwrap_or(0);
  if let Some(expected)=self.next_close && latest<expected {
   // 币安还没把那一根收好：隔一会儿再取；等太久就放弃这一根、重新对表。
   if now>=expected+MA_GIVE_UP_MS {self.next_close=forming.map(|b|b.close_time+1);self.not_before=now+MA_RETRY_MS;}
   else {self.not_before=now+MA_RETRY_MS;}
   return None
  }
  self.next_close=forming.map(|b|b.close_time+1);
  self.not_before=if self.next_close.is_some() {0} else {now+MA_RETRY_MS};
  if latest<=self.judged||closed.is_empty() {return None}
  self.judged=latest;
  Some(closed)
 }
}

// ——————————————————————————— 常驻循环（worker） ———————————————————————————

const PREMIUM_INDEX:&str="https://www.binance.com/fapi/v1/premiumIndex";
const OI_HISTORY:&str="https://www.binance.com/futures/data/openInterestHist";
const KLINES:&str="https://www.binance.com/fapi/v1/klines";
/// 多久重读一次所有人的条件提醒。新建的均线提醒最多晚这么久开始排程。
const RELOAD:Duration=Duration::from_secs(15);
/// 同一时刻最多几个 K 线 / 持仓量请求在路上。
const FETCH_PARALLEL:usize=4;

fn now_ms()->i64 {chrono::Utc::now().timestamp_millis()}

type Shared=Arc<tokio::sync::RwLock<Vec<CondAlert>>>;

/// worker 里的条件提醒：一条读库循环 + 费率、持仓量、均线三条判定循环。
pub async fn run(s:AppState,apns:Option<Arc<Apns>>) {
 let shared:Shared=Arc::default();
 tokio::join!(
  reload(&s,shared.clone()),
  funding_loop(&s,apns.as_deref(),shared.clone()),
  open_interest_loop(&s,apns.as_deref(),shared.clone()),
  ma_loop(&s,apns.as_deref(),shared.clone()),
  indicators::run(&s,apns.as_deref(),shared.clone()),
 );
}

async fn reload(s:&AppState,shared:Shared) {
 let mut tick=tokio::time::interval(RELOAD);
 tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
 loop {
  tick.tick().await;
  // 读失败沿用上一轮（一次抖动不该让所有条件提醒停判一轮）。
  match load(s).await {
   Ok(fresh)=>*shared.write().await=fresh,
   Err(e)=>tracing::warn!("Condition alerts could not be reloaded ({e:?}); keeping last round's"),
  }
 }
}

fn of_type(all:&[CondAlert],f:impl Fn(&Rule)->bool)->Vec<CondAlert> {all.iter().filter(|a|f(&a.rule)).cloned().collect()}

async fn fire_all(s:&AppState,apns:Option<&Apns>,hits:Vec<Hit>,shared:&Shared) {
 for (a,o) in hits {
  match fire(s,apns,&a,&o).await {
   Ok(_)=>shared.write().await.retain(|x|!(x.owner==a.owner&&x.alert_id==a.alert_id)),
   Err(e)=>tracing::warn!("A condition alert met its condition but could not be recorded ({e:?}); it will be judged again"),
  }
 }
}

async fn funding_loop(s:&AppState,apns:Option<&Apns>,shared:Shared) {
 let mut judged:HashMap<String,i64>=HashMap::new();
 let mut tick=tokio::time::interval(Duration::from_secs(60));
 tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
 loop {
  tick.tick().await;
  let list=of_type(&shared.read().await,|r|matches!(r,Rule::Funding{..}));
  judged.retain(|id,_|list.iter().any(|a|&a.alert_id==id));
  if list.is_empty() {continue}
  let table=match crate::market_meta::get_json(PREMIUM_INDEX).await {
   Ok(v)=>parse_premium(&v),
   Err(_)=>{tracing::warn!("Funding conditions: premiumIndex unavailable this minute");continue}
  };
  let hits=judge_funding(&list,&table,now_ms(),&mut judged);
  fire_all(s,apns,hits,&shared).await;
 }
}

/// 最新一个持仓量点应当是哪一个（`timestamp` 是那 5 分钟的开头；最新收好的是上一个 5 分钟）。
pub fn expected_oi_point(now:i64)->i64 {now-now.rem_euclid(OI_PERIOD_MS)-OI_PERIOD_MS}

async fn open_interest_loop(s:&AppState,apns:Option<&Apns>,shared:Shared) {
 use futures_util::StreamExt;
 // 品种 → 判过的最新点。
 let mut judged:HashMap<String,i64>=HashMap::new();
 let mut tick=tokio::time::interval(Duration::from_secs(30));
 tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
 loop {
  tick.tick().await;
  let list=of_type(&shared.read().await,|r|matches!(r,Rule::OpenInterest{..}));
  let symbols:Vec<String>={let mut v:Vec<String>=list.iter().map(|a|a.symbol.clone()).collect();v.sort();v.dedup();v};
  judged.retain(|symbol,_|symbols.contains(symbol));
  let now=now_ms();
  let want=expected_oi_point(now);
  let due:Vec<String>=symbols.into_iter().filter(|symbol|judged.get(symbol).is_none_or(|at|*at<want)).collect();
  if due.is_empty() {continue}
  let fetched:Vec<(String,Vec<OiPoint>)>=futures_util::stream::iter(due).map(|symbol|async move {
   let url=format!("{OI_HISTORY}?symbol={symbol}&period=5m&limit=13");
   let points=crate::market_meta::get_json(&url).await.map(|v|parse_open_interest(&v)).unwrap_or_default();
   (symbol,points)
  }).buffer_unordered(FETCH_PARALLEL).collect().await;
  let mut hits=vec![];
  for (symbol,points) in fetched {
   let Some(last)=points.last() else {continue};
   if judged.get(&symbol).is_some_and(|at|*at>=last.at) {continue}
   judged.insert(symbol.clone(),last.at);
   hits.extend(judge_open_interest(&list,&symbol,&points,now_ms()));
  }
  fire_all(s,apns,hits,&shared).await;
 }
}

async fn ma_loop(s:&AppState,apns:Option<&Apns>,shared:Shared) {
 use futures_util::StreamExt;
 let mut clocks:BTreeMap<(String,String),MaClock>=BTreeMap::new();
 let mut tick=tokio::time::interval(Duration::from_secs(1));
 tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
 loop {
  tick.tick().await;
  let list=of_type(&shared.read().await,|r|matches!(r,Rule::MaCross{..}));
  // 同一品种同一周期合成一组，K 线取够组里最长的 N + 2 根。
  let mut groups:BTreeMap<(String,String),usize>=BTreeMap::new();
  for a in &list {if let Rule::MaCross{interval,length,..}=&a.rule {
   let longest=groups.entry((a.symbol.clone(),interval.clone())).or_default();
   *longest=(*longest).max(*length);
  }}
  clocks.retain(|key,_|groups.contains_key(key));
  let now=now_ms();
  let due:Vec<((String,String),usize)>=groups.into_iter().filter(|(key,_)|clocks.get(key).is_none_or(|c|c.due(now))).collect();
  if due.is_empty() {continue}
  let fetched:Vec<((String,String),Option<Vec<Bar>>)>=futures_util::stream::iter(due).map(|((symbol,interval),longest)|async move {
   let url=format!("{KLINES}?symbol={symbol}&interval={interval}&limit={}",(longest+2).min(1500));
   let rows=crate::market_meta::get_json(&url).await.ok().map(|v|parse_klines(&v));
   ((symbol,interval),rows)
  }).buffer_unordered(FETCH_PARALLEL).collect().await;
  let mut hits=vec![];
  for (key,rows) in fetched {
   let clock=clocks.entry(key.clone()).or_default();
   let now=now_ms();
   let Some(rows)=rows else {clock.not_before=now+MA_RETRY_MS;continue};
   let Some(closed)=clock.advance(&rows,now) else {continue};
   hits.extend(judge_ma(&list,&key.0,&key.1,&closed,now));
  }
  fire_all(s,apns,hits,&shared).await;
 }
}

#[cfg(test)]
mod tests {
 use super::*;

 fn alert(rule:Value,armed_at:i64)->CondAlert {
  CondAlert{owner:Uuid::nil(),alert_id:"binance/usd_m/BTCUSDT/a".into(),symbol:"BTCUSDT".into(),market:"binance/usd_m".into(),
   rule:Rule::parse(&rule).unwrap(),rule_json:rule,armed_at,title:String::new(),note:None,webhook:None,webhook_text:None}
 }

 #[test] fn rules_parse_strictly_and_unknown_types_pass() {
  assert!(valid_rule(&json!({"type":"funding","side":"above","rate":"0.0005"})));
  assert!(valid_rule(&json!({"type":"funding","side":"below","rate":"-0.0001"})));
  assert!(!valid_rule(&json!({"type":"funding","side":"above","rate":"0.5"})),"比 10% 还大");
  assert!(!valid_rule(&json!({"type":"funding","side":"up","rate":"0.0005"})));
  assert!(!valid_rule(&json!({"type":"funding","side":"above","rate":0.0005})),"数字要是十进制字符串");
  assert!(!valid_rule(&json!({"type":"funding","side":"above","rate":"5e-4"})));
  assert!(valid_rule(&json!({"type":"openInterestChange","threshold":"0.05"})));
  assert!(!valid_rule(&json!({"type":"openInterestChange","threshold":"0.0001"})));
  assert!(valid_rule(&json!({"type":"maCross","interval":"4h","length":20,"side":"above"})));
  assert!(!valid_rule(&json!({"type":"maCross","interval":"1y","length":20,"side":"above"})),"币安没有年线");
  assert!(!valid_rule(&json!({"type":"maCross","interval":"4h","length":0,"side":"above"})));
  assert!(!valid_rule(&json!({"type":"maCross","interval":"4h","length":1001,"side":"above"})));
  assert!(!valid_rule(&json!({"type":"maCross","interval":"4h","length":20.5,"side":"above"})));
  assert!(valid_rule(&json!({"type":"orderflowWall","threshold":"5000000"})));
  assert!(!valid_rule(&json!({"type":"orderflowWall","threshold":"100"})));
  // 认不得的 type 收下（不整条拒收），已知 type 多出来的键忽略。
  assert_eq!(Rule::parse(&json!({"type":"liquidationDistance","ratio":"0.1"})),Some(Rule::Unknown("liquidationDistance".into())));
  assert!(valid_rule(&json!({"type":"funding","side":"above","rate":"0.0005","future":"x"})));
  assert!(!valid_rule(&json!({"type":"has space"})));
  assert!(!valid_rule(&json!({"side":"above"})));
  assert!(!valid_rule(&json!("funding")));
  assert!(!valid_rule(&json!({"type":"funding","side":"above","rate":"0.0005","pad":"x".repeat(1100)})),"超过 1 KB");
 }

 #[test] fn phrases_and_units_read_like_the_protocol() {
  assert_eq!(Rule::parse(&json!({"type":"funding","side":"above","rate":"0.0005"})).unwrap().phrase(),"资金费率高于 0.05%");
  assert_eq!(Rule::parse(&json!({"type":"funding","side":"below","rate":"-0.0001"})).unwrap().phrase(),"资金费率低于 -0.01%");
  assert_eq!(Rule::parse(&json!({"type":"openInterestChange","threshold":"0.05"})).unwrap().phrase(),"1 小时持仓量变化超过 5%");
  assert_eq!(Rule::parse(&json!({"type":"maCross","interval":"4h","length":20,"side":"below"})).unwrap().phrase(),"4h 收盘跌破 MA20");
  assert_eq!(Rule::parse(&json!({"type":"orderflowWall","threshold":"5000000"})).unwrap().phrase(),"出现 5M 以上的大单墙");
  assert_eq!(units(12_400_000.0),"12.4M");
  assert_eq!(units(1_500.0),"1.5K");
  assert_eq!(units(2_000_000_000.0),"2B");
  assert_eq!(signed_percent(d("0.0621"),2),"+6.21%");
  assert_eq!(signed_percent(d("-0.035"),2),"-3.5%");
  let a=alert(json!({"type":"funding","side":"above","rate":"0.0005"}),0);
  assert_eq!(a.title(),"BTC 资金费率高于 0.05%");
 }

 #[test] fn funding_is_judged_once_per_settlement_inside_the_window() {
  let settle=1_790_524_800_000;
  let a=alert(json!({"type":"funding","side":"above","rate":"0.0005"}),0);
  let table=|rate:&str|HashMap::from([("BTCUSDT".to_string(),Premium{rate:rate.parse().unwrap(),mark:84_943.0,next_funding:settle})]);
  let mut judged=HashMap::new();
  // 窗口之外不判。
  assert!(judge_funding(&[a.clone()],&table("0.001"),settle-FUNDING_WINDOW_MS-1,&mut judged).is_empty());
  assert!(judged.is_empty());
  // 窗口里第一次：判，不够线就不响，而且这一次结算不再判（后面费率涨上去也不算）。
  assert!(judge_funding(&[a.clone()],&table("0.0004"),settle-FUNDING_WINDOW_MS,&mut judged).is_empty());
  assert!(judge_funding(&[a.clone()],&table("0.001"),settle-FUNDING_WINDOW_MS+60_000,&mut judged).is_empty());
  // 下一次结算重新判。
  let next=settle+8*3_600_000;
  let later=HashMap::from([("BTCUSDT".to_string(),Premium{rate:d("0.000612"),mark:85_000.0,next_funding:next})]);
  let hits=judge_funding(&[a.clone()],&later,next-14*60_000,&mut judged);
  assert_eq!(hits.len(),1);
  assert_eq!(hits[0].1.detail,"预测费率 0.0612% · 14 分钟后结算");
  assert_eq!(hits[0].1.price,85_000.0);
  // 恰好等于阈值算过线；低于那一档对称。
  let mut fresh=HashMap::new();
  assert_eq!(judge_funding(&[a.clone()],&table("0.0005"),settle-60_000,&mut fresh).len(),1);
  let below=alert(json!({"type":"funding","side":"below","rate":"-0.0001"}),0);
  assert_eq!(judge_funding(&[below.clone()],&table("-0.0002"),settle-60_000,&mut HashMap::new()).len(),1);
  assert!(judge_funding(&[below],&table("0.0001"),settle-60_000,&mut HashMap::new()).is_empty());
  // 武装之前的窗口不算。
  let armed=alert(json!({"type":"funding","side":"above","rate":"0.0005"}),settle-60_000);
  assert!(judge_funding(&[armed],&table("0.001"),settle-120_000,&mut HashMap::new()).is_empty());
 }

 #[test] fn premium_rows_without_a_next_settlement_are_ignored() {
  let table=parse_premium(&json!([
   {"symbol":"BTCUSDT","markPrice":"84943.00000000","lastFundingRate":"0.00003866","nextFundingTime":1790524800000_i64},
   {"symbol":"BTCUSDT_261225","markPrice":"86000","lastFundingRate":"","nextFundingTime":0},
  ]));
  assert_eq!(table.len(),1);
  assert_eq!(table["BTCUSDT"].rate,d("0.00003866"));
 }

 #[test] fn open_interest_compares_the_latest_point_with_an_hour_before() {
  let a=alert(json!({"type":"openInterestChange","threshold":"0.05"}),0);
  let base=1_790_517_900_000_i64;
  let mut points:Vec<OiPoint>=(0..13).map(|i|OiPoint{at:base-(12-i)*OI_PERIOD_MS,amount:d("100"),value:d("8400000")}).collect();
  assert!(judge_open_interest(&[a.clone()],"BTCUSDT",&points,base+60_000).is_empty());
  points[12].amount=d("106.21");points[12].value=d("8998000");
  let hits=judge_open_interest(&[a.clone()],"BTCUSDT",&points,base+60_000);
  assert_eq!(hits.len(),1);
  assert!(hits[0].1.detail.starts_with("1 小时持仓量 +6.21%"),"{}",hits[0].1.detail);
  // 跌也算（绝对值）。
  points[12].amount=d("94");
  assert_eq!(judge_open_interest(&[a.clone()],"BTCUSDT",&points,base+60_000).len(),1);
  // 缺一小时前那个点不判；武装之前的点不判；别的品种不判。
  assert!(judge_open_interest(&[a.clone()],"BTCUSDT",&points[1..],base+60_000).is_empty());
  let late=alert(json!({"type":"openInterestChange","threshold":"0.05"}),base+1);
  assert!(judge_open_interest(&[late],"BTCUSDT",&points,base+60_000).is_empty());
  assert!(judge_open_interest(&[a],"ETHUSDT",&points,base+60_000).is_empty());
  assert_eq!(expected_oi_point(1_790_518_276_000),1_790_517_900_000);
 }

 fn bars(closes:&[f64],start:i64,period:i64)->Vec<Bar> {
  closes.iter().enumerate().map(|(i,c)|Bar{open_time:start+i as i64*period,close:*c,close_time:start+(i as i64+1)*period-1}).collect()
 }

 #[test] fn ma_crosses_only_on_a_real_close_edge() {
  let above=alert(json!({"type":"maCross","interval":"1h","length":3,"side":"above"}),0);
  let below=alert(json!({"type":"maCross","interval":"1h","length":3,"side":"below"}),0);
  let h=3_600_000;
  // 10,10,10,9（在 MA 下）→ 12（收上 MA）。
  let up=bars(&[10.0,10.0,10.0,9.0,12.0],0,h);
  let hits=judge_ma(&[above.clone(),below.clone()],"BTCUSDT","1h",&up,5*h);
  assert_eq!(hits.len(),1);
  assert_eq!(hits[0].0.rule,above.rule);
  assert_eq!(hits[0].1.price,12.0);
  assert!(hits[0].1.detail.starts_with("收盘 12.00 · MA3 "));
  // 一直在上面不算（要边沿）。
  assert!(judge_ma(&[above.clone()],"BTCUSDT","1h",&bars(&[10.0,11.0,12.0,13.0,14.0],0,h),5*h).is_empty());
  // 跌破对称。
  assert_eq!(judge_ma(&[below.clone()],"BTCUSDT","1h",&bars(&[10.0,10.0,10.0,11.0,8.0],0,h),5*h).len(),1);
  // 不够 N+1 根不判；周期不同不判；收盘在武装之前不判。
  assert!(judge_ma(&[above.clone()],"BTCUSDT","1h",&up[1..],5*h).len()==1,"N+1 根正好够");
  assert!(judge_ma(&[above.clone()],"BTCUSDT","1h",&up[2..],5*h).is_empty());
  assert!(judge_ma(&[above.clone()],"BTCUSDT","4h",&up,5*h).is_empty());
  let late=alert(json!({"type":"maCross","interval":"1h","length":3,"side":"above"}),5*h);
  assert!(judge_ma(&[late],"BTCUSDT","1h",&up,5*h).is_empty());
  assert_eq!(sma(&[1.0,2.0,3.0,4.0],3,2),Some(3.5));
  assert_eq!(sma(&[1.0,2.0],1,3),None);
 }

 #[test] fn ma_clock_waits_for_the_close_and_judges_each_bar_once() {
  let h=3_600_000;
  let mut clock=MaClock::default();
  assert!(clock.due(0),"不知道下一根什么时候收：马上取");
  // 第一次取：三根已收、一根在走。
  let now=3*h+10_000;
  let rows=bars(&[1.0,2.0,3.0,4.0],0,h);
  let closed=clock.advance(&rows,now).expect("第一次判最新那根已收盘的");
  assert_eq!(closed.len(),3);
  assert_eq!(clock.next_close,Some(4*h));
  assert!(!clock.due(4*h+MA_SETTLE_MS-1));
  assert!(clock.due(4*h+MA_SETTLE_MS));
  // 收盘后取回来的还缺刚收的那一根（上游滞后）：不判、5 秒后再取。
  assert!(clock.advance(&rows[..3],4*h+MA_SETTLE_MS).is_none());
  assert!(!clock.due(4*h+MA_SETTLE_MS+MA_RETRY_MS-1));
  assert!(clock.due(4*h+MA_SETTLE_MS+MA_RETRY_MS));
  // 滚过去了：判新收的那一根，同一根不判第二次。
  let rolled=bars(&[1.0,2.0,3.0,4.0,5.0],0,h);
  assert_eq!(clock.advance(&rolled,4*h+8_000).map(|b|b.len()),Some(4));
  assert!(clock.advance(&rolled,4*h+9_000).is_none());
  assert_eq!(clock.next_close,Some(5*h));
  // 收盘后新的一根还没出现在表里、但刚收的那一根在：照样判（它的收盘价已经定了）。
  let mut quiet=MaClock{next_close:Some(4*h),judged:3*h,not_before:0};
  assert_eq!(quiet.advance(&rows,4*h+MA_SETTLE_MS).map(|b|b.len()),Some(4));
  assert_eq!(quiet.next_close,None,"不知道下一根什么时候收：5 秒后再对表");
  assert!(!quiet.due(4*h+MA_SETTLE_MS+MA_RETRY_MS-1));
  // 等太久还缺：放弃这一根、重新对表。
  let mut lagging=MaClock{next_close:Some(4*h),judged:3*h,not_before:0};
  assert!(lagging.advance(&rows[..3],4*h+MA_GIVE_UP_MS).is_none());
  assert_eq!(lagging.next_close,None);
 }
}
