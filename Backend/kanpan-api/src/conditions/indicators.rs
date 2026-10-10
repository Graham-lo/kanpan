//! 技术指标提醒（2026-10-07）：均线金叉 / 死叉、RSI 穿越阈值、收盘突破前 N 根高低点。
//!
//! 线格式是和网页端约定死的，放在提醒对象的 `rule` 里（提醒 `kind` 是 `condition`），用 `kind`
//! 区分（老的四种条件用的是 `type`，两者不会同时出现）：
//!
//! ```json
//! {"kind":"ma_cross","interval":"15m","fast":{"ma":"ema","period":9},"slow":{"ma":"sma","period":21},"direction":"up"}
//! {"kind":"rsi_level","interval":"1h","period":14,"level":70,"direction":"up"}
//! {"kind":"bar_breakout","interval":"4h","bars":20,"direction":"up"}
//! ```
//!
//! 判法：只在那个周期的 K 线**收盘**时判最新收好的那一根（[`MaClock`] 排时间），数据是币安 U 本位合约的
//! K 线；每个「品种 × 周期」在内存里留一份已收盘 K 线（够最长的那条提醒用 + 50 根），之后每根收盘只补
//! 缺的那几根，不每次重拉整段。穿越是严格的边沿：上一根 ≤、这一根 >（下穿对称），这一根恰好相等不算。
//! 响一次就完：`alerts::record_fired` 的 `WHERE status='active'` 是那道闸，这里另记一份「这次武装已经
//! 响过」（[`Fired`]）挡住重读提醒表时的竞态。
use super::{Bar,CondAlert,Hit,MA_RETRY_MS,MaClock,Observation,RULE_MAX_BYTES,Rule};
use crate::{AppState,alerts,apns::Apns};
use serde_json::{Map,Value,json};
use std::collections::{BTreeMap,HashSet};
use uuid::Uuid;

// ——————————————————————————— 形状 ———————————————————————————

/// 能选的周期（和网页端约定的七档）。
pub const INTERVALS:[&str;7]=["1m","5m","15m","30m","1h","4h","1d"];
/// 均线 / RSI 的周期数、突破看的根数：2–500。
pub const LENGTH_MIN:u64=2;
pub const LENGTH_MAX:u64=500;
/// RSI 阈值：1–99。
pub const LEVEL_MIN:f64=1.0;
pub const LEVEL_MAX:f64=99.0;
/// 缓存在「判得出」之外多留的根数。
pub const SLACK:usize=50;
/// 一份缓存最多几根（再加正在走的那一根，正好是币安一次请求的上限 1500）。
pub const CACHE_MAX:usize=1499;
/// 三种的 `kind`。
pub const KINDS:[&str;3]=["ma_cross","rsi_level","bar_breakout"];

/// 一个周期代号有多少毫秒（币安的这七档都是等长的，日线按 UTC 对齐）。
pub fn interval_ms(interval:&str)->Option<i64> {
 Some(match interval {"1m"=>60_000,"5m"=>300_000,"15m"=>900_000,"30m"=>1_800_000,"1h"=>3_600_000,"4h"=>14_400_000,"1d"=>86_400_000,_=>return None})
}

#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum MaKind {Sma,Ema}
/// 一条均线：类型 + 周期数。
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub struct Ma {pub kind:MaKind,pub period:usize}
impl Ma {
 fn label(&self)->String {format!("{}{}",match self.kind {MaKind::Sma=>"SMA",MaKind::Ema=>"EMA"},self.period)}
}

/// 一条技术指标条件。`up`：金叉 / 上穿 / 向上突破；否则死叉 / 下穿 / 向下跌破。
#[derive(Clone,Debug,PartialEq)]
pub enum Indicator {
 MaCross{interval:String,fast:Ma,slow:Ma,up:bool},
 RsiLevel{interval:String,period:usize,level:f64,up:bool},
 Breakout{interval:String,bars:usize,up:bool},
}

/// 校验不过的错误码，和 [`reason`] 里的中文一一对应。
pub mod code {
 pub const KIND:&str="indicator_kind";
 pub const TOO_LARGE:&str="indicator_rule_too_large";
 pub const INTERVAL:&str="indicator_interval";
 pub const MA:&str="indicator_ma";
 pub const MA_PERIOD:&str="indicator_ma_period";
 pub const SAME_MA:&str="indicator_same_ma";
 pub const RSI_PERIOD:&str="indicator_rsi_period";
 pub const LEVEL:&str="indicator_level";
 pub const BARS:&str="indicator_bars";
 pub const DIRECTION:&str="indicator_direction";
 pub const SYMBOL:&str="indicator_symbol";
}

/// 400 正文里跟着错误码的中文原因（`{"error":{"code":…,"message":…}}`）。
pub fn reason(code:&str)->Option<&'static str> {
 Some(match code {
  code::KIND=>"条件类型只能是 ma_cross、rsi_level、bar_breakout",
  code::TOO_LARGE=>"条件内容太长",
  code::INTERVAL=>"周期只能是 1m、5m、15m、30m、1h、4h、1d",
  code::MA=>"均线类型只能是 sma 或 ema",
  code::MA_PERIOD=>"均线周期要在 2 到 500 之间",
  code::SAME_MA=>"快线和慢线不能相同",
  code::RSI_PERIOD=>"RSI 周期要在 2 到 500 之间",
  code::LEVEL=>"RSI 阈值要在 1 到 99 之间",
  code::BARS=>"突破根数要在 2 到 500 之间",
  code::DIRECTION=>"方向只能是 up 或 down",
  code::SYMBOL=>"只支持币安 U 本位合约里正在交易的品种",
  _=>return None,
 })
}

/// 这个 `rule` 是不是三种技术指标之一（按 `kind` 认，不看其余字段对不对）。
pub fn is_indicator(v:&Value)->bool {
 v.as_object().is_some_and(|o|!o.contains_key("type")&&o.get("kind").and_then(Value::as_str).is_some_and(|k|KINDS.contains(&k)))
}

type Checked<T>=std::result::Result<T,&'static str>;

fn length(v:Option<&Value>,code:&'static str)->Checked<usize> {
 v.and_then(Value::as_u64).filter(|n|(LENGTH_MIN..=LENGTH_MAX).contains(n)).map(|n|n as usize).ok_or(code)
}
fn up(o:&Map<String,Value>)->Checked<bool> {
 match o.get("direction").and_then(Value::as_str) {Some("up")=>Ok(true),Some("down")=>Ok(false),_=>Err(code::DIRECTION)}
}
fn ma(v:Option<&Value>)->Checked<Ma> {
 let o=v.and_then(Value::as_object).ok_or(code::MA)?;
 let kind=match o.get("ma").and_then(Value::as_str) {Some("sma")=>MaKind::Sma,Some("ema")=>MaKind::Ema,_=>return Err(code::MA)};
 Ok(Ma{kind,period:length(o.get("period"),code::MA_PERIOD)?})
}

/// 严格解一条技术指标条件；不过就给出错误码（[`reason`] 有中文）。多出来的键忽略（同老条件）。
pub fn check(v:&Value)->Checked<Indicator> {
 let o=v.as_object().ok_or(code::KIND)?;
 if serde_json::to_string(v).map_or(true,|t|t.len()>RULE_MAX_BYTES) {return Err(code::TOO_LARGE)}
 let kind=o.get("kind").and_then(Value::as_str).filter(|k|KINDS.contains(k)).ok_or(code::KIND)?;
 let interval=o.get("interval").and_then(Value::as_str).filter(|i|INTERVALS.contains(i)).ok_or(code::INTERVAL)?.to_string();
 Ok(match kind {
  "ma_cross"=>{
   let (fast,slow)=(ma(o.get("fast"))?,ma(o.get("slow"))?);
   if fast==slow {return Err(code::SAME_MA)}
   Indicator::MaCross{interval,fast,slow,up:up(o)?}
  }
  "rsi_level"=>{
   let period=length(o.get("period"),code::RSI_PERIOD)?;
   let level=o.get("level").and_then(Value::as_f64).filter(|l|(LEVEL_MIN..=LEVEL_MAX).contains(l)).ok_or(code::LEVEL)?;
   Indicator::RsiLevel{interval,period,level,up:up(o)?}
  }
  _=>Indicator::Breakout{interval,bars:length(o.get("bars"),code::BARS)?,up:up(o)?},
 })
}

/// `Rule::parse` 在没有 `type` 时走这里：三种已知的严格解；格式像样但认不得的 `kind` 收下不判
/// （和老条件认不得的 `type` 一样，给以后的版本留路）；没有 `kind` 是形状不对。
pub fn parse(o:&Map<String,Value>,v:&Value)->Option<Rule> {
 let kind=o.get("kind")?.as_str()?;
 if !(1..=40).contains(&kind.len())||!kind.bytes().all(|b|b.is_ascii_lowercase()||b==b'_') {return None}
 if KINDS.contains(&kind) {check(v).ok().map(Rule::Indicator)} else {Some(Rule::Unknown(kind.to_string()))}
}

/// 校验同步 op 用：是技术指标条件、但校验不过时的错误码。
pub fn rejection(v:&Value)->Option<&'static str> {
 if is_indicator(v) {check(v).err()} else {None}
}

/// 阈值去掉尾巴上的 0：`70` → 「70」，`70.5` → 「70.5」。
fn level_text(level:f64)->String {
 let text=format!("{level:.2}");
 text.trim_end_matches('0').trim_end_matches('.').to_string()
}

impl Indicator {
 pub fn kind(&self)->&'static str {
  match self {Indicator::MaCross{..}=>"ma_cross",Indicator::RsiLevel{..}=>"rsi_level",Indicator::Breakout{..}=>"bar_breakout"}
 }
 pub fn interval(&self)->&str {
  match self {Indicator::MaCross{interval,..}|Indicator::RsiLevel{interval,..}|Indicator::Breakout{interval,..}=>interval}
 }
 /// 「15m：EMA9 上穿 SMA21」「1h：RSI(14) 上穿 70」「4h：收盘突破前 20 根最高」。
 pub fn phrase(&self)->String {
  match self {
   Indicator::MaCross{interval,fast,slow,up}=>format!("{interval}：{} {} {}",fast.label(),if *up {"上穿"} else {"下穿"},slow.label()),
   Indicator::RsiLevel{interval,period,level,up}=>format!("{interval}：RSI({period}) {} {}",if *up {"上穿"} else {"下穿"},level_text(*level)),
   Indicator::Breakout{interval,bars,up}=>if *up {format!("{interval}：收盘突破前 {bars} 根最高")} else {format!("{interval}：收盘跌破前 {bars} 根最低")},
  }
 }
 /// 判这一条至少要几根已收盘 K 线。
 pub fn minimum(&self)->usize {
  match self {
   Indicator::MaCross{fast,slow,..}=>fast.period.max(slow.period)+1,
   Indicator::RsiLevel{period,..}=>period+2,
   Indicator::Breakout{bars,..}=>bars+1,
  }
 }
 /// 缓存该留几根：够判的根数 + [`SLACK`]。EMA / RSI 是递推的，起算点离得越远越接近图上从头算的值，
 /// 给它们按 5 倍周期算「够判」；封顶 [`CACHE_MAX`]。
 pub fn capacity(&self)->usize {
  let warm=match self {
   Indicator::MaCross{fast,slow,..}=>[fast,slow].iter().map(|m|match m.kind {MaKind::Sma=>m.period+1,MaKind::Ema=>m.period*5+1}).max().unwrap_or(0),
   Indicator::RsiLevel{period,..}=>period*5+2,
   Indicator::Breakout{bars,..}=>bars+1,
  };
  (warm+SLACK).min(CACHE_MAX)
 }
}

// ——————————————————————————— 指标 ———————————————————————————

/// 一根 K 线（币安 `klines` 一行的 [0] [2] [3] [4] [6]）。
#[derive(Clone,Copy,Debug,PartialEq)]
pub struct Candle {pub open_time:i64,pub high:f64,pub low:f64,pub close:f64,pub close_time:i64}
pub fn parse_candles(v:&Value)->Vec<Candle> {
 let num=crate::market_meta::num;
 v.as_array().map(Vec::as_slice).unwrap_or(&[]).iter().filter_map(|row|Some(Candle{
  open_time:row[0].as_i64()?,high:num(&row[2])?,low:num(&row[3])?,close:num(&row[4])?,close_time:row[6].as_i64()?,
 })).collect()
}

/// 均线序列，下标和 `closes` 对齐，前 `n-1` 个是 None。SMA 同 [`super::sma`]；EMA 用前 `n` 根的 SMA 起算、
/// 之后 α = 2/(n+1) 递推（TradingView `ta.ema` 的口径）。
pub fn ma_series(closes:&[f64],m:Ma)->Vec<Option<f64>> {
 let n=m.period;
 let mut out=vec![None;closes.len()];
 if n==0||closes.len()<n {return out}
 match m.kind {
  MaKind::Sma=>for (i,slot) in out.iter_mut().enumerate().skip(n-1) {*slot=super::sma(closes,i,n)},
  MaKind::Ema=>{
   let alpha=2.0/(n as f64+1.0);
   let mut e=closes[..n].iter().sum::<f64>()/n as f64;
   out[n-1]=Some(e);
   for i in n..closes.len() {e=alpha*closes[i]+(1.0-alpha)*e;out[i]=Some(e)}
  }
 }
 out
}

/// RSI 序列（Wilder 平滑，TradingView `ta.rsi` 的口径）：第 `n` 根起有值；平均跌幅为 0 是 100，平均涨幅为 0 是 0。
pub fn rsi_series(closes:&[f64],n:usize)->Vec<Option<f64>> {
 let mut out=vec![None;closes.len()];
 if n==0||closes.len()<=n {return out}
 let value=|u:f64,d:f64|if d==0.0 {100.0} else if u==0.0 {0.0} else {100.0-100.0/(1.0+u/d)};
 let (mut u,mut d)=(0.0,0.0);
 for i in 1..=n {let c=closes[i]-closes[i-1];if c>0.0 {u+=c} else {d-=c}}
 u/=n as f64;d/=n as f64;
 out[n]=Some(value(u,d));
 for i in n+1..closes.len() {
  let c=closes[i]-closes[i-1];
  u=(u*(n as f64-1.0)+c.max(0.0))/n as f64;
  d=(d*(n as f64-1.0)+(-c).max(0.0))/n as f64;
  out[i]=Some(value(u,d));
 }
 out
}

/// 上穿：上一根 ≤、这一根 >；下穿：上一根 ≥、这一根 <。这一根恰好相等两边都不算。
pub fn crossed(prev:f64,now:f64,prev_line:f64,now_line:f64,up:bool)->bool {
 if up {prev<=prev_line&&now>now_line} else {prev>=prev_line&&now<now_line}
}

/// 拿最后一根（已收盘）K 线判一条条件；响了给出（推送正文，Webhook `value`）。
pub fn evaluate(ind:&Indicator,bars:&[Candle])->Option<(String,Value)> {
 if bars.len()<ind.minimum() {return None}
 let k=bars.len()-1;
 let closes:Vec<f64>=bars.iter().map(|b|b.close).collect();
 let c=closes[k];
 match ind {
  Indicator::MaCross{fast,slow,up,..}=>{
   let (f,s)=(ma_series(&closes,*fast),ma_series(&closes,*slow));
   let (Some(f1),Some(f0),Some(s1),Some(s0))=(f[k],f[k-1],s[k],s[k-1]) else {return None};
   if !crossed(f0,f1,s0,s1,*up) {return None}
   Some((format!("{} {} · {} {} · 收盘 {}",fast.label(),alerts::money(f1),slow.label(),alerts::money(s1),alerts::money(c)),
    json!({"fast":f1.to_string(),"slow":s1.to_string(),"close":c.to_string()})))
  }
  Indicator::RsiLevel{period,level,up,..}=>{
   let r=rsi_series(&closes,*period);
   let (Some(r1),Some(r0))=(r[k],r[k-1]) else {return None};
   if !crossed(r0,r1,*level,*level,*up) {return None}
   Some((format!("RSI({period}) {r1:.2} · 收盘 {}",alerts::money(c)),json!({"rsi":format!("{r1:.4}"),"close":c.to_string()})))
  }
  Indicator::Breakout{bars:n,up,..}=>{
   let before=&bars[k-n..k];
   if *up {
    let high=before.iter().map(|b|b.high).fold(f64::NEG_INFINITY,f64::max);
    if c<=high {return None}
    Some((format!("收盘 {} · 前 {n} 根最高 {}",alerts::money(c),alerts::money(high)),json!({"close":c.to_string(),"high":high.to_string()})))
   } else {
    let low=before.iter().map(|b|b.low).fold(f64::INFINITY,f64::min);
    if c>=low {return None}
    Some((format!("收盘 {} · 前 {n} 根最低 {}",alerts::money(c),alerts::money(low)),json!({"close":c.to_string(),"low":low.to_string()})))
   }
  }
 }
}

/// 一组（同一品种同一周期）技术指标提醒，拿这一组的已收盘 K 线判最新收好的那一根。
/// 只判收盘时刻晚于 armedAt 的（武装之前收的那一根不算）。
pub fn judge(list:&[CondAlert],symbol:&str,interval:&str,bars:&[Candle],now:i64)->Vec<Hit> {
 let Some(last)=bars.last() else {return vec![]};
 let closed_at=last.close_time+1;
 let mut hits=vec![];
 for a in list {
  let Rule::Indicator(ind)=&a.rule else {continue};
  if a.symbol!=symbol||ind.interval()!=interval||closed_at<=a.armed_at {continue}
  let Some((detail,mut value))=evaluate(ind,bars) else {continue};
  value["openTime"]=json!(last.open_time);
  value["closeTime"]=json!(closed_at);
  hits.push((a.clone(),Observation{at:now,price:last.close,detail,value}));
 }
 hits
}

/// 「这一次武装已经响过」：键是（用户，提醒，armedAt），重新武装是新的一次。
#[derive(Default,Debug)]
pub struct Fired(HashSet<(Uuid,String,i64)>);
impl Fired {
 /// 滤掉已经响过的，剩下的记成响过。
 pub fn fresh(&mut self,hits:Vec<Hit>)->Vec<Hit> {
  hits.into_iter().filter(|(a,_)|self.0.insert((a.owner,a.alert_id.clone(),a.armed_at))).collect()
 }
 /// 写库失败的放回去，下一根收盘再判。
 pub fn forget(&mut self,a:&CondAlert) {self.0.remove(&(a.owner,a.alert_id.clone(),a.armed_at));}
 /// 只留还在活动表里的（删了、暂停了、重新武装了的不必再记）。
 pub fn retain(&mut self,list:&[CondAlert]) {
  let live:HashSet<(Uuid,&str,i64)>=list.iter().map(|a|(a.owner,a.alert_id.as_str(),a.armed_at)).collect();
  self.0.retain(|(o,id,at)|live.contains(&(*o,id.as_str(),*at)));
 }
}

// ——————————————————————————— 缓存 ———————————————————————————

/// 一个「品种 × 周期」的已收盘 K 线缓存。
#[derive(Clone,Debug,Default,PartialEq)]
pub struct Series {
 /// 按开盘时间升序、首尾相接（没有缺口）。
 pub bars:Vec<Candle>,
 /// 上一次整段拉取时的容量（0 = 还没整段拉过，或者断过档）。
 pub filled_for:usize,
}
impl Series {
 /// 这次该向币安要几根（含正在走的那一根）：容量涨了、断过档、离上次太久就整段要；
 /// 否则只要缺的那几根再加两根重叠。
 pub fn limit(&self,cap:usize,interval_ms:i64,now:i64)->usize {
  let full=cap.min(CACHE_MAX)+1;
  let Some(last)=self.bars.last() else {return full};
  if self.filled_for<cap {return full}
  let missing=((now-(last.close_time+1)).max(0)/interval_ms) as usize;
  (missing+2).min(full)
 }
 /// 这次要的根数算不算整段要。
 pub fn is_full(limit:usize,cap:usize)->bool {limit>cap.min(CACHE_MAX)}
 /// 并入一次取回来的已收盘 K 线：同一根以新的为准；只留最后一段首尾相接的、最多 `cap` 根。
 /// 补的时候发现断档（中间缺了根），下一次整段重拉。
 pub fn merge(&mut self,closed:&[Candle],cap:usize,interval_ms:i64,full:bool) {
  let mut by_open:BTreeMap<i64,Candle>=self.bars.iter().map(|b|(b.open_time,*b)).collect();
  for b in closed {by_open.insert(b.open_time,*b);}
  let all:Vec<Candle>=by_open.into_values().collect();
  let mut start=all.len().saturating_sub(1);
  while start>0&&all[start].open_time-all[start-1].open_time==interval_ms {start-=1}
  let run=&all[start..];
  self.bars=run[run.len().saturating_sub(cap)..].to_vec();
  if full {self.filled_for=cap} else if start>0&&self.bars.len()<cap {self.filled_for=0}
 }
}

// ——————————————————————————— 品种 ———————————————————————————

/// `exchangeInfo` 里有没有这只、而且是正在交易的永续合约。
pub fn listed(info:&Value,symbol:&str)->bool {
 info["symbols"].as_array().is_some_and(|rows|rows.iter().any(|row|row["symbol"].as_str()==Some(symbol)&&crate::instruments::is_live_perpetual(row)))
}

/// 一条同步 op 要是把技术指标条件写进提醒，给出它的品种（提醒 id 是 `binance/usd_m/<品种>/<id>`，
/// 和 `symbol` 字段的一致性由 `sync_validation::object` 把关）。
pub fn symbol_of(collection:&str,object_id:&str,action:&str,fields:&BTreeMap<String,Value>)->Option<String> {
 if collection!=crate::sync::ALERTS||action!="patch"||!fields.get("rule").is_some_and(is_indicator) {return None}
 if let Some(s)=fields.get("symbol").and_then(Value::as_str) {return Some(s.to_string())}
 object_id.split('/').nth(2).map(str::to_string)
}

/// 推上来的品种里认不得的那几只（带着它们的 op 回 `indicator_symbol`）。合约表取不到时一只都不算
/// 认不得、照常放行（记一行日志）：不该因为币安一次抖动把用户建提醒整个挡掉——那不是这条提醒的错，
/// 回 400 会让客户端把它当坏操作隔离；真认不得的品种也只是永远不响。
///
/// 从前是「整批里有一只不认得就整批 400」（审查 2026-10-10 第 5 项）：同一批里别的设置、画线
/// 跟着一起被拒，客户端二分到最后才找到是哪一条。现在交回名单，由 `sync::push` 只拒那一条。
pub async fn unlisted(symbols:&[String])->std::collections::BTreeSet<String> {
 if symbols.is_empty() {return Default::default()}
 match crate::market_meta::exchange_info().await {
  Ok(info)=>symbols.iter().filter(|s|!listed(&info,s)).cloned().collect(),
  Err(_)=>{tracing::warn!("Indicator alerts: exchangeInfo unavailable, symbol not checked");Default::default()}
 }
}

// ——————————————————————————— 常驻循环（worker） ———————————————————————————

const KLINES:&str="https://www.binance.com/fapi/v1/klines";
/// 一组取回来的：（品种，周期），容量，要了几根，K 线（取失败是 None）。
type Fetched=((String,String),usize,usize,Option<Vec<Candle>>);

/// 一组拿到一次 K 线（含正在走的那一根）之后做的事：已收盘的并进缓存；刚滚过一根新的收盘才判，
/// 同一根只判一次，正在走的那一根永远不判。
#[allow(clippy::too_many_arguments)]
pub fn step(clock:&mut MaClock,series:&mut Series,rows:&[Candle],cap:usize,full:bool,list:&[CondAlert],symbol:&str,interval:&str,now:i64)->Vec<Hit> {
 let Some(ims)=interval_ms(interval) else {return vec![]};
 let closed:Vec<Candle>=rows.iter().filter(|b|b.close_time<now).copied().collect();
 series.merge(&closed,cap,ims,full);
 let bars:Vec<Bar>=rows.iter().map(|c|Bar{open_time:c.open_time,close:c.close,close_time:c.close_time}).collect();
 if clock.advance(&bars,now).is_none() {return vec![]}
 judge(list,symbol,interval,&series.bars,now)
}

/// 技术指标提醒的判定循环：每秒看一眼哪些「品种 × 周期」刚收盘，取 K 线、并进缓存、判。
pub(super) async fn run(s:&AppState,apns:Option<&Apns>,shared:super::Shared) {
 use futures_util::StreamExt;
 let mut clocks:BTreeMap<(String,String),MaClock>=BTreeMap::new();
 let mut cache:BTreeMap<(String,String),Series>=BTreeMap::new();
 let mut fired=Fired::default();
 let mut tick=tokio::time::interval(std::time::Duration::from_secs(1));
 tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
 loop {
  tick.tick().await;
  let list=super::of_type(&shared.read().await,|r|matches!(r,Rule::Indicator(_)));
  fired.retain(&list);
  // 同一品种同一周期合成一组，缓存按组里要得最多的那条留。
  let mut groups:BTreeMap<(String,String),usize>=BTreeMap::new();
  for a in &list {if let Rule::Indicator(ind)=&a.rule {
   let cap=groups.entry((a.symbol.clone(),ind.interval().to_string())).or_default();
   *cap=(*cap).max(ind.capacity());
  }}
  clocks.retain(|key,_|groups.contains_key(key));
  cache.retain(|key,_|groups.contains_key(key));
  let now=super::now_ms();
  let due:Vec<((String,String),usize,usize)>=groups.into_iter().filter(|(key,_)|clocks.get(key).is_none_or(|c|c.due(now))).filter_map(|(key,cap)|{
   let ims=interval_ms(&key.1)?;
   let limit=cache.get(&key).map_or(cap.min(CACHE_MAX)+1,|s|s.limit(cap,ims,now));
   Some((key,cap,limit))
  }).collect();
  if due.is_empty() {continue}
  let fetched:Vec<Fetched>=futures_util::stream::iter(due).map(|((symbol,interval),cap,limit)|async move {
   let url=format!("{KLINES}?symbol={}&interval={interval}&limit={limit}",crate::instruments::url_component(&symbol));
   let rows=crate::market_meta::get_json(&url).await.ok().map(|v|parse_candles(&v));
   ((symbol,interval),cap,limit,rows)
  }).buffer_unordered(super::FETCH_PARALLEL).collect().await;
  let mut hits=vec![];
  for (key,cap,limit,rows) in fetched {
   let clock=clocks.entry(key.clone()).or_default();
   let now=super::now_ms();
   let Some(rows)=rows else {clock.not_before=now+MA_RETRY_MS;continue};
   let series=cache.entry(key.clone()).or_default();
   hits.extend(step(clock,series,&rows,cap,Series::is_full(limit,cap),&list,&key.0,&key.1,now));
  }
  for (a,o) in fired.fresh(hits) {
   match super::fire(s,apns,&a,&o).await {
    Ok(_)=>shared.write().await.retain(|x|!(x.owner==a.owner&&x.alert_id==a.alert_id)),
    Err(e)=>{fired.forget(&a);tracing::warn!("An indicator alert met its condition but could not be recorded ({e:?}); it will be judged again at the next close")}
   }
  }
 }
}

#[cfg(test)]
mod tests {
 use super::*;

 const MA:&str=r#"{"kind":"ma_cross","interval":"15m","fast":{"ma":"ema","period":9},"slow":{"ma":"sma","period":21},"direction":"up"}"#;
 const RSI:&str=r#"{"kind":"rsi_level","interval":"1h","period":14,"level":70,"direction":"up"}"#;
 const BREAKOUT:&str=r#"{"kind":"bar_breakout","interval":"4h","bars":20,"direction":"up"}"#;
 fn v(text:&str)->Value {serde_json::from_str(text).unwrap()}
 fn with(text:&str,patch:Value)->Value {
  let mut rule=v(text);
  for (k,x) in patch.as_object().unwrap() {rule[k]=x.clone();}
  rule
 }
 fn alert_on(symbol:&str,rule:Value,armed_at:i64)->CondAlert {
  CondAlert{owner:Uuid::nil(),alert_id:format!("binance/usd_m/{symbol}/a"),symbol:symbol.into(),market:"binance/usd_m".into(),
   rule:Rule::parse(&rule).unwrap(),rule_json:rule,armed_at,title:String::new(),note:None,webhook:None,webhook_text:None}
 }
 fn candles(closes:&[f64],start:i64,period:i64)->Vec<Candle> {
  closes.iter().enumerate().map(|(i,c)|Candle{open_time:start+i as i64*period,high:*c,low:*c,close:*c,close_time:start+(i as i64+1)*period-1}).collect()
 }
 fn sma(n:usize)->Ma {Ma{kind:MaKind::Sma,period:n}}

 #[test] fn the_agreed_wire_format_parses_into_the_three_kinds() {
  let ma=Rule::parse(&v(MA)).unwrap();
  assert_eq!(ma,Rule::Indicator(Indicator::MaCross{interval:"15m".into(),fast:Ma{kind:MaKind::Ema,period:9},slow:sma(21),up:true}));
  assert_eq!(ma.kind(),"ma_cross");
  assert_eq!(Rule::parse(&v(RSI)).unwrap(),Rule::Indicator(Indicator::RsiLevel{interval:"1h".into(),period:14,level:70.0,up:true}));
  assert_eq!(Rule::parse(&v(BREAKOUT)).unwrap(),Rule::Indicator(Indicator::Breakout{interval:"4h".into(),bars:20,up:true}));
  for text in [MA,RSI,BREAKOUT] {assert!(crate::conditions::valid_rule(&v(text)));assert!(is_indicator(&v(text)));assert_eq!(rejection(&v(text)),None)}
  // 七档周期都收，别的不收。
  for i in INTERVALS {assert!(check(&with(BREAKOUT,json!({"interval":i}))).is_ok(),"{i}")}
  for i in ["3m","2h","1w","1M","15"] {assert_eq!(check(&with(BREAKOUT,json!({"interval":i}))),Err(code::INTERVAL),"{i}")}
  // 老条件照旧走 `type`；认不得但像样的 `kind` 收下不判；没有 `kind` 也没有 `type` 是形状不对。
  assert!(matches!(Rule::parse(&json!({"type":"maCross","interval":"4h","length":20,"side":"above"})),Some(Rule::MaCross{..})));
  assert_eq!(Rule::parse(&json!({"kind":"macd_cross","interval":"1h"})),Some(Rule::Unknown("macd_cross".into())));
  assert_eq!(Rule::parse(&json!({"kind":"Has Space"})),None);
  assert_eq!(Rule::parse(&json!({"interval":"1h"})),None);
  assert!(!is_indicator(&json!({"type":"funding","kind":"ma_cross"})),"有 type 的按老条件认");
 }

 #[test] fn validation_bounds_and_chinese_reasons() {
  let err=|text:&str,patch:Value|check(&with(text,patch)).err();
  // 周期 / 根数：2 和 500 收，1 和 501 不收，小数不收。
  assert_eq!(err(MA,json!({"fast":{"ma":"ema","period":2},"slow":{"ma":"sma","period":500}})),None);
  assert_eq!(err(MA,json!({"fast":{"ma":"ema","period":1}})),Some(code::MA_PERIOD));
  assert_eq!(err(MA,json!({"slow":{"ma":"sma","period":501}})),Some(code::MA_PERIOD));
  assert_eq!(err(MA,json!({"fast":{"ma":"ema","period":9.5}})),Some(code::MA_PERIOD));
  assert_eq!(err(MA,json!({"fast":{"ma":"wma","period":9}})),Some(code::MA));
  assert_eq!(err(MA,json!({"fast":"ema9"})),Some(code::MA));
  // 快慢线完全一样不收；同周期不同类型是两条线，收。
  assert_eq!(err(MA,json!({"fast":{"ma":"sma","period":21}})),Some(code::SAME_MA));
  assert_eq!(err(MA,json!({"fast":{"ma":"ema","period":21}})),None);
  assert_eq!(err(RSI,json!({"period":2})),None);
  assert_eq!(err(RSI,json!({"period":500})),None);
  assert_eq!(err(RSI,json!({"period":1})),Some(code::RSI_PERIOD));
  assert_eq!(err(RSI,json!({"period":501})),Some(code::RSI_PERIOD));
  assert_eq!(err(RSI,json!({"level":1})),None);
  assert_eq!(err(RSI,json!({"level":99})),None);
  assert_eq!(err(RSI,json!({"level":70.5})),None);
  assert_eq!(err(RSI,json!({"level":0.99})),Some(code::LEVEL));
  assert_eq!(err(RSI,json!({"level":100})),Some(code::LEVEL));
  assert_eq!(err(RSI,json!({"level":"70"})),Some(code::LEVEL));
  assert_eq!(err(BREAKOUT,json!({"bars":2})),None);
  assert_eq!(err(BREAKOUT,json!({"bars":500})),None);
  assert_eq!(err(BREAKOUT,json!({"bars":1})),Some(code::BARS));
  assert_eq!(err(BREAKOUT,json!({"bars":501})),Some(code::BARS));
  assert_eq!(err(BREAKOUT,json!({"direction":"above"})),Some(code::DIRECTION));
  assert_eq!(err(RSI,json!({"direction":null})),Some(code::DIRECTION));
  assert_eq!(err(BREAKOUT,json!({"pad":"x".repeat(1100)})),Some(code::TOO_LARGE));
  // 校验不过的同样在 `valid_rule` 里不收（整条 op 拒收）。
  assert!(!crate::conditions::valid_rule(&with(RSI,json!({"level":100}))));
  // 每个错误码都有中文原因，400 正文带出来；别的错误码不带。
  for c in [code::KIND,code::TOO_LARGE,code::INTERVAL,code::MA,code::MA_PERIOD,code::SAME_MA,code::RSI_PERIOD,code::LEVEL,code::BARS,code::DIRECTION,code::SYMBOL] {
   assert!(crate::error::message(c).is_some_and(|m|!m.is_ascii()),"{c}");
  }
  assert_eq!(crate::error::message(code::LEVEL),Some("RSI 阈值要在 1 到 99 之间"));
  assert_eq!(crate::error::message("invalid_operation"),None);
 }

 #[test] fn a_sync_op_with_a_bad_indicator_rule_is_rejected_with_its_own_code() {
  let op=|rule:Value|crate::sync::Operation{id:Uuid::nil(),collection:crate::sync::ALERTS.into(),object_id:"binance/usd_m/BTCUSDT/a".into(),device_id:Uuid::nil(),
   base_revision:0,generation:0,timestamp:1,logical:1,action:"patch".into(),fields:BTreeMap::from([("rule".to_string(),rule)]),import_batch:None};
  assert!(op(v(MA)).validate().is_ok());
  let e=op(with(MA,json!({"slow":{"ma":"ema","period":9}}))).validate().unwrap_err();
  assert_eq!((e.0,e.1),(axum::http::StatusCode::BAD_REQUEST,code::SAME_MA));
  assert_eq!(op(with(RSI,json!({"level":0}))).validate().unwrap_err().1,code::LEVEL);
  // 老条件的错误照旧是笼统的 invalid_operation。
  assert_eq!(op(json!({"type":"maCross","interval":"1y","length":20,"side":"above"})).validate().unwrap_err().1,"invalid_operation");
  // 整条提醒对象落得下去：rule 一带，kind 变成 condition。
  let mut fields=BTreeMap::from([("rule".to_string(),v(BREAKOUT)),("symbol".to_string(),json!("SOLUSDT")),("market".to_string(),json!("binance/usd_m")),
   ("status".to_string(),json!("active")),("armedAt".to_string(),json!(1)),("once".to_string(),json!(true)),("lines".to_string(),json!([]))]);
  fields.insert("kind".into(),json!("price"));
  let mut o=op(json!(null));o.object_id="binance/usd_m/SOLUSDT/x".into();o.fields=fields;
  let blank=crate::sync::Object{collection:crate::sync::ALERTS.into(),id:o.object_id.clone(),body:BTreeMap::new(),fields:BTreeMap::new(),revision:0,deleted:false,generation:0};
  let merged=crate::sync::merge(blank,&o,1_800_000_000_000).unwrap();
  assert_eq!(merged.body["kind"],"condition");
  assert_eq!(merged.body["rule"],v(BREAKOUT));
  assert_eq!(symbol_of(crate::sync::ALERTS,&o.object_id,"patch",&o.fields).as_deref(),Some("SOLUSDT"));
 }

 #[test] fn only_live_binance_perpetuals_are_accepted() {
  let info=json!({"symbols":[
   {"symbol":"BTCUSDT","contractType":"PERPETUAL","status":"TRADING"},
   {"symbol":"OLDUSDT","contractType":"PERPETUAL","status":"SETTLING"},
   {"symbol":"BTCUSDT_261225","contractType":"CURRENT_QUARTER","status":"TRADING"},
  ]});
  assert!(listed(&info,"BTCUSDT"));
  assert!(!listed(&info,"OLDUSDT"),"下架了");
  assert!(!listed(&info,"BTCUSDT_261225"),"交割合约");
  assert!(!listed(&info,"NOPEUSDT"));
  // 只有把技术指标条件写进提醒的 op 才查品种。
  let fields=|rule:Value|BTreeMap::from([("rule".to_string(),rule)]);
  assert_eq!(symbol_of("alerts","binance/usd_m/ETHUSDT/a","patch",&fields(v(RSI))).as_deref(),Some("ETHUSDT"));
  assert_eq!(symbol_of("alerts","binance/usd_m/ETHUSDT/a","delete",&fields(v(RSI))),None);
  assert_eq!(symbol_of("alerts","binance/usd_m/ETHUSDT/a","patch",&fields(json!({"type":"funding","side":"above","rate":"0.0005"}))),None);
  assert_eq!(symbol_of("alerts","binance/usd_m/ETHUSDT/a","patch",&BTreeMap::new()),None);
  assert_eq!(symbol_of("drawings","binance/usd_m/ETHUSDT/a","patch",&fields(v(RSI))),None);
 }

 #[test] fn push_titles_read_like_the_agreed_examples() {
  assert_eq!(alert_on("BTCUSDT",v(MA),0).title(),"BTCUSDT 15m：EMA9 上穿 SMA21");
  assert_eq!(alert_on("ETHUSDT",v(RSI),0).title(),"ETHUSDT 1h：RSI(14) 上穿 70");
  assert_eq!(alert_on("SOLUSDT",v(BREAKOUT),0).title(),"SOLUSDT 4h：收盘突破前 20 根最高");
  assert_eq!(alert_on("SOLUSDT",with(BREAKOUT,json!({"direction":"down"})),0).title(),"SOLUSDT 4h：收盘跌破前 20 根最低");
  assert_eq!(Rule::parse(&with(MA,json!({"direction":"down"}))).unwrap().phrase(),"15m：EMA9 下穿 SMA21");
  assert_eq!(Rule::parse(&with(RSI,json!({"direction":"down","level":30.5}))).unwrap().phrase(),"1h：RSI(14) 下穿 30.5");
  // 客户端写了标题也用这一句（推送文案是约定的）。
  let mut a=alert_on("BTCUSDT",v(MA),0);a.title="随便".into();
  assert_eq!(a.title(),"BTCUSDT 15m：EMA9 上穿 SMA21");
  assert_eq!(crate::conditions::webhook_body(&a,&Observation{at:0,price:1.0,detail:String::new(),value:json!({})})["condition"],"ma_cross");
 }

 #[test] fn indicator_series_match_the_chart_formulas() {
  let ema=ma_series(&[1.0,2.0,3.0,4.0,5.0],Ma{kind:MaKind::Ema,period:3});
  assert_eq!(ema,vec![None,None,Some(2.0),Some(3.0),Some(4.0)]);
  assert_eq!(ma_series(&[1.0,2.0,3.0,4.0],sma(2)),vec![None,Some(1.5),Some(2.5),Some(3.5)]);
  let rsi=rsi_series(&[10.0,11.0,10.0,11.0],2);
  assert_eq!(rsi,vec![None,None,Some(50.0),Some(75.0)]);
  assert_eq!(rsi_series(&[1.0,2.0,3.0],2)[2],Some(100.0),"一路涨");
  assert_eq!(rsi_series(&[3.0,2.0,1.0],2)[2],Some(0.0),"一路跌");
 }

 #[test] fn ma_cross_fires_on_the_edge_and_not_on_equality() {
  let h=900_000;
  let up=alert_on("BTCUSDT",json!({"kind":"ma_cross","interval":"15m","fast":{"ma":"sma","period":2},"slow":{"ma":"sma","period":3},"direction":"up"}),0);
  let down=alert_on("BTCUSDT",json!({"kind":"ma_cross","interval":"15m","fast":{"ma":"sma","period":2},"slow":{"ma":"sma","period":3},"direction":"down"}),0);
  let both=[up.clone(),down.clone()];
  // 上一根快线在慢线下，这一根恰好相等：不算金叉。
  let touch=candles(&[10.0,10.0,8.0,8.0,8.0],0,h);
  assert!(judge(&both,"BTCUSDT","15m",&touch,0).is_empty());
  // 再下一根从「相等」走到上方：金叉（上一根 ≤、这一根 >）。
  let cross=candles(&[10.0,10.0,8.0,8.0,8.0,9.0],0,h);
  let hits=judge(&both,"BTCUSDT","15m",&cross,6*h);
  assert_eq!(hits.len(),1);
  assert_eq!(hits[0].0.rule,up.rule);
  assert_eq!(hits[0].1.price,9.0);
  assert_eq!(hits[0].1.detail,"SMA2 8.50 · SMA3 8.33 · 收盘 9.00");
  assert_eq!(hits[0].1.value["closeTime"],json!(6*h));
  // 一直在上面不算；死叉对称。
  assert!(judge(&[up.clone()],"BTCUSDT","15m",&candles(&[1.0,2.0,3.0,4.0,5.0,6.0],0,h),0).is_empty());
  let fall=judge(&both,"BTCUSDT","15m",&candles(&[10.0,10.0,10.0,10.0,7.0],0,h),0);
  assert_eq!(fall.len(),1);
  assert_eq!(fall[0].0.rule,down.rule);
  // 不够根数、别的周期、别的品种、武装之前收的那一根：都不判。
  assert!(judge(&both,"BTCUSDT","15m",&cross[3..],0).is_empty());
  assert!(judge(&both,"BTCUSDT","1h",&cross,0).is_empty());
  assert!(judge(&both,"ETHUSDT","15m",&cross,0).is_empty());
  let late=alert_on("BTCUSDT",up.rule_json.clone(),6*h);
  assert!(judge(&[late],"BTCUSDT","15m",&cross,6*h).is_empty());
  let armed_just_before=alert_on("BTCUSDT",up.rule_json.clone(),6*h-1);
  assert_eq!(judge(&[armed_just_before],"BTCUSDT","15m",&cross,6*h).len(),1);
 }

 #[test] fn rsi_fires_when_crossing_the_level_and_not_when_landing_on_it() {
  let rule=|level:f64,up:bool|Indicator::RsiLevel{interval:"1h".into(),period:2,level,up};
  let rising=candles(&[10.0,11.0,10.0,11.0],0,3_600_000);
  // RSI 50 → 75。
  assert!(evaluate(&rule(50.0,true),&rising).is_some(),"上一根恰好在线上、这一根在上面：上穿");
  assert!(evaluate(&rule(60.0,true),&rising).is_some());
  assert!(evaluate(&rule(75.0,true),&rising).is_none(),"这一根恰好等于阈值不算");
  assert!(evaluate(&rule(76.0,true),&rising).is_none());
  assert!(evaluate(&rule(60.0,false),&rising).is_none());
  // 75 → 跌下去。
  let falling=candles(&[10.0,11.0,10.0,11.0,10.0],0,3_600_000);
  let now=rsi_series(&falling.iter().map(|b|b.close).collect::<Vec<_>>(),2)[4].unwrap();
  assert!(now<50.0);
  assert!(evaluate(&rule(50.0,false),&falling).is_some());
  assert!(evaluate(&rule(now,false),&falling).is_none(),"这一根恰好等于阈值不算");
  assert!(evaluate(&rule(50.0,true),&falling).is_none());
  let (detail,_)=evaluate(&rule(70.0,true),&candles(&[10.0,11.0,10.0,11.0],0,1)).unwrap();
  assert_eq!(detail,"RSI(2) 75.00 · 收盘 11.00");
  assert!(evaluate(&rule(50.0,true),&rising[..3]).is_none(),"不够 N+2 根");
 }

 #[test] fn breakout_needs_a_close_strictly_beyond_the_previous_n_bars() {
  let bar=|i:i64,high:f64,low:f64,close:f64|Candle{open_time:i*14_400_000,high,low,close,close_time:(i+1)*14_400_000-1};
  let up=Indicator::Breakout{interval:"4h".into(),bars:3,up:true};
  let down=Indicator::Breakout{interval:"4h".into(),bars:3,up:false};
  let base=[bar(0,99.0,1.0,50.0),bar(1,10.0,8.0,9.0),bar(2,12.0,7.0,10.0),bar(3,11.0,9.0,10.0)];
  let with_last=|last:Candle|{let mut v=base.to_vec();v.push(last);v};
  // 前 3 根（不含第 0 根）最高 12、最低 7；最新那一根自己的高低点不算数，只看收盘。
  assert!(evaluate(&up,&with_last(bar(4,15.0,5.0,12.0))).is_none(),"收盘恰好等于最高不算");
  let (detail,value)=evaluate(&up,&with_last(bar(4,12.5,11.0,12.01))).unwrap();
  assert_eq!(detail,"收盘 12.01 · 前 3 根最高 12.00");
  assert_eq!(value["high"],"12");
  assert!(evaluate(&down,&with_last(bar(4,9.0,5.0,7.0))).is_none(),"收盘恰好等于最低不算");
  assert_eq!(evaluate(&down,&with_last(bar(4,8.0,6.0,6.99))).unwrap().0,"收盘 6.99 · 前 3 根最低 7.00");
  assert!(evaluate(&up,&base[1..]).is_none(),"不够 N+1 根");
 }

 #[test] fn only_closed_bars_are_judged_and_each_close_once() {
  let h=14_400_000;
  let a=alert_on("SOLUSDT",json!({"kind":"bar_breakout","interval":"4h","bars":3,"direction":"up"}),0);
  let list=[a.clone()];
  let mut clock=MaClock::default();
  let mut series=Series::default();
  // 三根已收（10,10,10）、正在走的那一根已经冲到 20：正在走的不判。
  let mut rows=candles(&[10.0,10.0,10.0,20.0],0,h);
  assert!(step(&mut clock,&mut series,&rows,53,true,&list,"SOLUSDT","4h",3*h+5_000).is_empty());
  assert_eq!(series.bars.len(),3,"缓存只收已收盘的");
  // 它收盘了（收在 20）、新的一根开始走：判，响。
  rows.push(candles(&[20.0],4*h,h)[0]);
  let hits=step(&mut clock,&mut series,&rows,53,false,&list,"SOLUSDT","4h",4*h+MA_SETTLE);
  assert_eq!(hits.len(),1);
  assert_eq!(hits[0].1.price,20.0);
  // 同一根收盘再取一遍：不再判。
  assert!(step(&mut clock,&mut series,&rows,53,false,&list,"SOLUSDT","4h",4*h+MA_SETTLE+5_000).is_empty());
  // 只响一次：同一次武装的同一条提醒，第二次判出来也被挡掉；重新武装（armedAt 变了）是新的一次。
  let mut fired=Fired::default();
  assert_eq!(fired.fresh(hits.clone()).len(),1);
  assert!(fired.fresh(hits.clone()).is_empty());
  fired.forget(&hits[0].0);
  assert_eq!(fired.fresh(hits.clone()).len(),1,"写库失败放回去，下一次还能响");
  let mut rearmed=hits[0].clone();rearmed.0.armed_at=99;
  assert_eq!(fired.fresh(vec![rearmed.clone()]).len(),1);
  fired.retain(&[rearmed.0.clone()]);
  assert!(fired.fresh(vec![rearmed]).is_empty());
  assert_eq!(fired.fresh(hits).len(),1,"不在活动表里的记录已经清掉");
 }
 const MA_SETTLE:i64=crate::conditions::MA_SETTLE_MS;

 #[test] fn the_cache_keeps_capacity_and_only_fetches_the_gap() {
  let m=60_000;
  let ind=Indicator::MaCross{interval:"1m".into(),fast:Ma{kind:MaKind::Ema,period:9},slow:sma(21),up:true};
  assert_eq!(ind.minimum(),22);
  assert_eq!(ind.capacity(),9*5+1+SLACK);
  assert_eq!(Indicator::Breakout{interval:"4h".into(),bars:20,up:true}.capacity(),21+SLACK);
  assert_eq!(Indicator::RsiLevel{interval:"1h".into(),period:500,level:70.0,up:true}.capacity(),CACHE_MAX);
  let cap=10;
  let mut s=Series::default();
  assert_eq!(s.limit(cap,m,0),11,"空的：整段要（含正在走的那一根）");
  s.merge(&candles(&[1.0;10],0,m),cap,m,true);
  assert_eq!(s.bars.len(),10);
  // 下一根收盘后只要缺的那一根 + 两根重叠。
  let now=11*m+2_000;
  assert_eq!(s.limit(cap,m,now),3);
  s.merge(&candles(&[2.0,3.0],9*m,m),cap,m,false);
  assert_eq!(s.bars.len(),10,"封顶 cap 根");
  assert_eq!(s.bars.first().unwrap().open_time,m);
  assert_eq!(s.bars.last().unwrap().close,3.0);
  // 同一根以新取回来的为准。
  s.merge(&candles(&[4.0],10*m,m),cap,m,false);
  assert_eq!(s.bars.last().unwrap().close,4.0);
  assert_eq!(s.bars.len(),10);
  // 隔了很久（停机）：缺得比 cap 还多就整段要。
  assert_eq!(s.limit(cap,m,1_000*m),11);
  // 容量涨了（新加了一条更长的）：整段要。
  assert_eq!(s.limit(cap+5,m,11*m+2_000),16);
  // 补的时候断了档：只留断档之后的，下一次整段重拉。
  s.merge(&candles(&[5.0,6.0],20*m,m),cap,m,false);
  assert_eq!(s.bars.len(),2);
  assert_eq!(s.filled_for,0);
  assert_eq!(s.limit(cap,m,22*m+2_000),11);
  // 整段拉回来本身就短（新上市），不会反复整段重拉。
  let mut young=Series::default();
  young.merge(&candles(&[1.0;4],0,m),cap,m,true);
  assert_eq!(young.limit(cap,m,5*m+2_000),3);
  assert!(Series::is_full(11,cap)&&!Series::is_full(3,cap));
  assert_eq!(interval_ms("1d"),Some(86_400_000));
  assert_eq!(interval_ms("2h"),None);
 }

 #[test] fn binance_kline_rows_parse_into_candles() {
  let rows=json!([[1_700_000_000_000_i64,"100.0","110.5","95.25","105.75","12.3",1_700_000_899_999_i64,"0",1,"0","0","0"]]);
  assert_eq!(parse_candles(&rows),vec![Candle{open_time:1_700_000_000_000,high:110.5,low:95.25,close:105.75,close_time:1_700_000_899_999}]);
  assert!(parse_candles(&json!([["x"]])).is_empty());
 }
}
