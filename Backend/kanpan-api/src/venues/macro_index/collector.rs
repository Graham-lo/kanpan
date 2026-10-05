//! 采集：三条循环、一份内存里的现状、`macro_bars` 的读写。
//!
//! - **报价循环**：开盘时每 5 秒问一次 CNBC 报价（`.DXY` + 六个外汇对），挑出这一刻的价
//!   （官方新鲜用官方，否则用校准过的合成价），落进当前这一分钟，顺手把这一分钟所在的
//!   5 分钟、1 小时、交易日三根重算一遍，四行一条语句写库。休市时一个请求都不发。
//! - **官方 1 分钟循环**：开盘时（以及收盘后 20 分钟内）每分钟取一次 CNBC 的官方 1M，
//!   盖掉报价拼出来的那几分钟（`source=1` 的行不会再被报价拼的行改写）。
//! - **回填 / 自愈循环**：启动时一次，之后每 30 分钟一次。表里没有的档整段回填
//!   （1D 十年、1H 100 天、5M 64 天、1M 30 天，都是 CNBC 能给的上限），有的话只补最近一截；
//!   CNBC 偶尔给出坏日线（高低价包不住开收、或四价相同），用同一交易日的 1H 聚出来补。
//!
//! 上游挂了：指数退避（报价 10 秒起翻倍、封顶 5 分钟），照常用库里和内存里的最后数据答复，
//! 日志按类一小时最多一条。所有错误都只记日志，循环不退出（serve 里看着它的是 `Life::Forever`，
//! 这条任务一退出整个进程就会被 systemd 重启）。
use std::collections::{BTreeMap,BTreeSet};
use std::sync::{LazyLock,Mutex,MutexGuard,OnceLock};
use std::time::Duration;
use chrono::{Datelike,NaiveDate,Weekday};
use sqlx::PgPool;
use tokio::sync::watch;
use super::SYMBOL;
use super::bars::{self,Bar,Span,Spec};
use super::calendar::{self,DAY_MS,HOUR_MS,MINUTE_MS};
use super::cnbc::{self,BarKind,Calibration,Quiet,Snapshot};

/// 内存里留多久的 1 分钟：一个交易日 23 小时，留 26 小时够重算当天的日线和 12 小时线。
pub const MINUTES_KEPT:i64=26*HOUR_MS;
/// 内存里留多少根日线：一年最多 262 个交易日，420 根够聚当年的年线和 ticker 的昨收。
pub const DAYS_KEPT:usize=420;
/// 官方价多久没动就算不新鲜（之后改用合成价）。
pub const OFFICIAL_FRESH:i64=2*MINUTE_MS;
/// 外汇对最旧的一个多久以内才拿来合成。
pub const FX_FRESH:i64=3*MINUTE_MS;
/// 开盘时间里最后一笔价超过这么久，`marketState` 也报 `closed`（节假日 ICE 不出价）。
pub const STALE:i64=10*MINUTE_MS;

const QUOTE_EVERY:Duration=Duration::from_secs(5);
const QUOTE_BACKOFF_FIRST:Duration=Duration::from_secs(10);
const QUOTE_BACKOFF_MAX:Duration=Duration::from_secs(300);
const MINUTE_EVERY:Duration=Duration::from_secs(60);
const MINUTE_BACKOFF_MAX:Duration=Duration::from_secs(600);
const HEAL_EVERY:Duration=Duration::from_secs(30*60);
const HEAL_RETRY:Duration=Duration::from_secs(5*60);

/// 这一刻的价从哪来。
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum Source {Official,Synthetic}
impl Source {pub fn name(self)->&'static str {match self {Self::Official=>"official",Self::Synthetic=>"synthetic"}}}

/// 最后一笔价。
#[derive(Clone,Copy,Debug,PartialEq)]
pub struct Last {pub price:f64,pub time:i64,pub source:Source}

/// 要写回库里的一行。`official` 是 `source=1`：CNBC 官方 K 线；否则是报价拼出来或聚出来的。
#[derive(Clone,Copy,Debug,PartialEq)]
pub struct Row {pub interval:&'static str,pub bar:Bar,pub official:bool}

/// 24h 行情（其实是「这个交易日」行情，见 `ticker`）。
#[derive(Clone,Copy,Debug,PartialEq)]
pub struct Ticker {
 pub last:f64,pub time:i64,pub source:Source,
 pub prev_close:Option<f64>,
 pub open:f64,pub high:f64,pub low:f64,
 /// 这个交易日开盘的时刻（上一个美东 18:00）。
 pub session_start:i64,
 pub open_now:bool,
}

/// 内存里的现状。
#[derive(Debug,Default)]
pub struct State {
 /// 最近 26 小时的 1 分钟：开盘时刻 → (K 线, 是不是官方)。
 pub minutes:BTreeMap<i64,(Bar,bool)>,
 /// 最近 420 根日线：标签（交易日 00:00 UTC）→ (K 线, 是不是官方)。
 pub days:BTreeMap<i64,(Bar,bool)>,
 pub last:Option<Last>,
 /// CNBC 报价里的 `previous_day_closing`，连同报价所在的交易日。
 pub prev_close:Option<(NaiveDate,f64)>,
 pub calibration:Calibration,
}

fn agg<'a>(it:impl Iterator<Item=&'a (Bar,bool)>)->Option<Bar> {
 let mut out:Option<Bar>=None;
 for (b,_) in it {match &mut out {Some(o)=>o.absorb(b),None=>out=Some(*b)}}
 out
}

impl State {
 /// 一笔价。休市时间里的、比上一笔旧的、和上一笔同一时刻的都不收。
 /// 返回要写库的行（这一分钟是官方的话不写，它已经是对的了）。
 pub fn tick(&mut self,price:f64,time:i64,source:Source)->Vec<Row> {
  if !(price.is_finite()&&price>0.0&&calendar::is_open(time)) {return vec![]}
  if self.last.is_some_and(|l|time<=l.time) {return vec![]}
  self.last=Some(Last{price,time,source});
  let m=time.div_euclid(MINUTE_MS)*MINUTE_MS;
  let bar=match self.minutes.get_mut(&m) {
   Some((_,true))=>return vec![],
   Some((b,false))=>{b.tick(price);*b}
   None=>{let b=Bar::flat(m,price);self.minutes.insert(m,(b,false));b}
  };
  let mut rows=vec![Row{interval:"1m",bar,official:false}];
  rows.extend(self.derive(&BTreeSet::from([m])));
  self.trim(time);
  rows
 }

 /// 官方 1 分钟。收完整的（`t + 1 分钟 ≤ now`）、开盘时间里的；26 小时以内的进内存并重算
 /// 它们所在的 5 分钟 / 1 小时 / 交易日。返回要写库的行（官方行全写，聚出来的只写内存窗口里的）。
 pub fn merge_minutes(&mut self,bars:&[Bar],now:i64)->Vec<Row> {
  let mut rows=Vec::new();
  let mut touched=BTreeSet::new();
  for b in bars {
   if b.t+MINUTE_MS>now||!calendar::is_open(b.t)||!b.sane() {continue}
   rows.push(Row{interval:"1m",bar:*b,official:true});
   if b.t>=now-MINUTES_KEPT {self.minutes.insert(b.t,(*b,true));touched.insert(b.t);}
  }
  rows.extend(self.derive(&touched));
  self.trim(now);
  rows
 }

 /// 官方（或用 1H 补出来的）日线进内存。
 pub fn merge_days(&mut self,rows:&[Row]) {
  for r in rows.iter().filter(|r|r.interval=="1d") {
   if !r.official&&self.days.get(&r.bar.t).is_some_and(|(_,o)|*o) {continue}
   self.days.insert(r.bar.t,(r.bar,r.official));
  }
  while self.days.len()>DAYS_KEPT {self.days.pop_first();}
 }

 /// 这几分钟所在的 5 分钟、1 小时、交易日重算。聚出来的行一律 `source=0`：完整的官方 5M / 1H / 1D
 /// 由回填循环取来盖掉；库里已经是官方的行不会被这些改写（见 `upsert`）。
 fn derive(&mut self,touched:&BTreeSet<i64>)->Vec<Row> {
  let mut rows=Vec::new();
  for (interval,step) in [("5m",5*MINUTE_MS),("1h",HOUR_MS)] {
   let buckets:BTreeSet<i64>=touched.iter().map(|m|m.div_euclid(step)*step).collect();
   for b in buckets {
    if let Some(mut bar)=agg(self.minutes.range(b..b+step).map(|(_,v)|v)) {bar.t=b;rows.push(Row{interval,bar,official:false})}
   }
  }
  let dates:BTreeSet<NaiveDate>=touched.iter().map(|m|calendar::trading_date(*m)).collect();
  for d in dates {
   let label=calendar::day_label(d);
   if self.days.get(&label).is_some_and(|(_,o)|*o) {continue}
   let (start,end)=calendar::session(d);
   let Some(mut bar)=agg(self.minutes.range(start..end).map(|(_,v)|v)) else {continue};
   bar.t=label;
   // 内存里的分钟没盖到开盘那一段（重启后 1M 回填还没跑完）：开盘价和已有的高低沿用之前那一根。
   let covered=self.minutes.range(start..end).next().is_some_and(|(t,_)|*t<=start+HOUR_MS);
   if !covered&&let Some((prev,_))=self.days.get(&label) {bar.o=prev.o;bar.h=bar.h.max(prev.h);bar.l=bar.l.min(prev.l);}
   self.days.insert(label,(bar,false));
   rows.push(Row{interval:"1d",bar,official:false});
  }
  rows
 }

 fn trim(&mut self,now:i64) {
  let keep=now-MINUTES_KEPT;
  while self.minutes.first_key_value().is_some_and(|(t,_)|*t<keep) {self.minutes.pop_first();}
  while self.days.len()>DAYS_KEPT {self.days.pop_first();}
 }

 /// 最新官方 1 分钟的开盘时刻。
 pub fn newest_official_minute(&self)->Option<i64> {
  self.minutes.iter().rev().find(|(_,(_,o))|*o).map(|(t,_)|*t)
 }

 /// `t` 这一刻属于哪一根（日线及以上按交易日算）。
 pub fn open_of(spec:&Spec,t:i64)->i64 {
  match spec.span {
   Span::Fixed(step) if step<DAY_MS=>bars::bucket(spec.span,t),
   _=>bars::bucket(spec.span,calendar::day_label(calendar::trading_date(t))),
  }
 }

 /// 开盘时刻为 `open` 的那一根，用内存里的分钟 / 日线拼（推送用；1d 以下的从分钟拼，以上的从日线拼）。
 pub fn bar(&self,spec:&Spec,open:i64)->Option<Bar> {
  let mut b=match spec.span {
   Span::Fixed(step) if step<DAY_MS=>agg(self.minutes.range(open..open+step).map(|(_,v)|v)),
   Span::Fixed(_)=>self.days.get(&open).map(|(b,_)|*b),
   span=>agg(self.days.range(open..=bars::close_time(span,open)).map(|(_,v)|v)),
  }?;
  b.t=open;
  Some(b)
 }

 /// 最后一笔价所在那一根（推送里的「末根」）。
 pub fn live_bar(&self,spec:&Spec)->Option<Bar> {
  let last=self.last?;
  self.bar(spec,Self::open_of(spec,last.time))
 }

 /// 行情。口径是「最后一笔价所在的交易日」：开高低是这个交易日的，涨跌对的是上一个交易日的
 /// 官方收盘（CNBC 报价里的 `previous_day_closing`，没有就用库里上一根日线的收盘），
 /// 不是滚动 24 小时——美元指数的涨跌幅行业里都这么算（ICE、CNBC、Bloomberg 都对昨收）。
 pub fn ticker(&self,now:i64)->Option<Ticker> {
  let last=self.last?;
  let d=calendar::trading_date(last.time);
  let label=calendar::day_label(d);
  let prev_close=match self.prev_close {
   Some((qd,pc)) if qd==d=>Some(pc),
   _=>self.days.range(..label).next_back().map(|(_,(b,_))|b.c),
  };
  let (open,high,low)=self.days.get(&label).map(|(b,_)|(b.o,b.h.max(last.price),b.l.min(last.price))).unwrap_or((last.price,last.price,last.price));
  Some(Ticker{last:last.price,time:last.time,source:last.source,prev_close,open,high,low,
   session_start:calendar::session(d).0,open_now:calendar::is_open(now)&&now-last.time<=STALE})
 }

 /// 一次报价轮询：校准、挑价、落进分钟。返回要写库的行和这次有没有校准。
 pub fn on_quote(&mut self,snap:&Snapshot,now:i64)->(Vec<Row>,bool) {
  let official=snap.official.as_ref().filter(|q|now-q.time<=OFFICIAL_FRESH&&q.time<=now+MINUTE_MS);
  if let Some(q)=&snap.official&&let Some(pc)=q.previous_close {self.prev_close=Some((calendar::trading_date(q.time),pc));}
  let synthetic=snap.synthetic(now,FX_FRESH);
  let calibrated=match (official,synthetic) {
   (Some(o),Some((s,_)))=>self.calibration.observe(o.last,s,now),
   _=>false,
  };
  let rows=match (official,synthetic) {
   (Some(o),_)=>self.tick(o.last,o.time.min(now),Source::Official),
   (None,Some((s,_)))=>{let p=self.calibration.apply(s);self.tick(p,now,Source::Synthetic)}
   (None,None)=>vec![],
  };
  (rows,calibrated)
 }
}

// ------------------------------------------------------------------ 全局

static STATE:LazyLock<Mutex<State>>=LazyLock::new(||Mutex::new(State::default()));
static POOL:OnceLock<PgPool>=OnceLock::new();
static VERSION:LazyLock<watch::Sender<u64>>=LazyLock::new(||watch::channel(0).0);

pub fn state()->MutexGuard<'static,State> {STATE.lock().unwrap_or_else(|e|e.into_inner())}
/// raw 接口挂在不读数据库的通用路由上（`venues::routes()`），库连接由采集任务起来时放在这里。
pub fn pool()->Option<&'static PgPool> {POOL.get()}
/// 现状变了（新价、官方分钟、开收盘切换）就加一。推送 hub 盯着它。
pub fn changes()->watch::Receiver<u64> {VERSION.subscribe()}
fn bump() {VERSION.send_modify(|v|*v=v.wrapping_add(1));}

fn now_ms()->i64 {chrono::Utc::now().timestamp_millis()}

static QUOTE_ERR:Quiet=Quiet::hourly();
static MINUTE_ERR:Quiet=Quiet::hourly();
static HEAL_ERR:Quiet=Quiet::hourly();
static DB_ERR:Quiet=Quiet::hourly();
static CALIBRATED:Quiet=Quiet::hourly();

async fn write(pool:&PgPool,rows:&[Row]) {
 if rows.is_empty() {return}
 if let Err(e)=upsert(pool,rows).await&&DB_ERR.ready() {tracing::warn!("Macro bars: write failed, serving from memory ({e})")}
}

/// serve 里起。
pub fn spawn(pool:PgPool)->tokio::task::JoinHandle<()> {
 let _=POOL.set(pool.clone());
 tokio::spawn(async move {
  if let Err(e)=seed(&pool).await {tracing::warn!("Macro bars: could not seed from the table ({e})")}
  tokio::join!(quote_loop(&pool),minute_loop(&pool),heal_loop(&pool));
 })
}

/// 启动时从表里把最近的分钟、日线、最后一笔价读回内存：重启后休市期间也有价可答。
async fn seed(pool:&PgPool)->sqlx::Result<()> {
 let now=now_ms();
 let minutes:Vec<(i64,f64,f64,f64,f64,i16)>=sqlx::query_as("SELECT open_time,open,high,low,close,source FROM macro_bars WHERE symbol=$1 AND interval='1m' AND open_time>=$2 ORDER BY open_time")
  .bind(SYMBOL).bind(now-MINUTES_KEPT).fetch_all(pool).await?;
 let days:Vec<(i64,f64,f64,f64,f64,i16)>=sqlx::query_as("SELECT open_time,open,high,low,close,source FROM macro_bars WHERE symbol=$1 AND interval='1d' ORDER BY open_time DESC LIMIT $2")
  .bind(SYMBOL).bind(DAYS_KEPT as i64).fetch_all(pool).await?;
 let last:Option<(i64,f64,i16)>=sqlx::query_as("SELECT open_time,close,source FROM macro_bars WHERE symbol=$1 AND interval='1m' ORDER BY open_time DESC LIMIT 1")
  .bind(SYMBOL).fetch_optional(pool).await?;
 let mut st=state();
 for (t,o,h,l,c,src) in minutes {st.minutes.insert(t,(Bar{t,o,h,l,c},src==1));}
 for (t,o,h,l,c,src) in days {st.days.insert(t,(Bar{t,o,h,l,c},src==1));}
 if st.last.is_none()&&let Some((t,c,src))=last {
  st.last=Some(Last{price:c,time:t,source:if src==1 {Source::Official} else {Source::Synthetic}});
 }
 drop(st);
 bump();
 Ok(())
}

async fn quote_loop(pool:&PgPool) {
 let mut backoff:Option<Duration>=None;
 let mut was_open=None;
 loop {
  let now=now_ms();
  let open=calendar::is_open(now);
  if was_open!=Some(open) {was_open=Some(open);bump();}
  if !open {tokio::time::sleep(Duration::from_secs(15)).await;continue}
  match cnbc::quote().await {
   Ok(snap)=>{
    backoff=None;
    let now=now_ms();
    let ((rows,calibrated),ratio)={let mut st=state();let out=st.on_quote(&snap,now);(out,st.calibration.ratio)};
    if calibrated&&CALIBRATED.ready() {tracing::info!("Macro index: calibrated synthetic DXY, official / synthetic = {ratio:.6}")}
    write(pool,&rows).await;
    bump();
   }
   Err(e)=>{
    let next=backoff.map_or(QUOTE_BACKOFF_FIRST,|b|(b*2).min(QUOTE_BACKOFF_MAX));
    backoff=Some(next);
    if QUOTE_ERR.ready() {tracing::warn!("Macro index: CNBC quote failed, backing off {next:?} ({e})")}
   }
  }
  tokio::time::sleep(backoff.unwrap_or(QUOTE_EVERY)).await;
 }
}

async fn minute_loop(pool:&PgPool) {
 let mut backoff:Option<Duration>=None;
 loop {
  let now=now_ms();
  if calendar::is_open(now)||calendar::is_open(now-20*MINUTE_MS) {
   let newest=state().newest_official_minute();
   let from=newest.map_or(now-3*HOUR_MS,|t|t-10*MINUTE_MS).max(now-MINUTES_KEPT);
   match cnbc::bars(BarKind::M1,from,now).await {
    Ok(list)=>{
     backoff=None;
     let rows=state().merge_minutes(&list,now_ms());
     write(pool,&rows).await;
     if !rows.is_empty() {bump()}
    }
    Err(e)=>{
     let next=backoff.map_or(MINUTE_EVERY*2,|b|(b*2).min(MINUTE_BACKOFF_MAX));
     backoff=Some(next);
     if MINUTE_ERR.ready() {tracing::warn!("Macro index: CNBC 1M failed, backing off {next:?} ({e})")}
    }
   }
  }
  tokio::time::sleep(backoff.unwrap_or(MINUTE_EVERY)).await;
 }
}

async fn heal_loop(pool:&PgPool) {
 let mut first=true;
 loop {
  let wait=match heal(pool,first).await {
   Ok(n)=>{if first||n>0 {tracing::info!("Macro index: backfill wrote {n} bars")};first=false;HEAL_EVERY}
   Err(e)=>{if HEAL_ERR.ready() {tracing::warn!("Macro index: backfill will retry ({e})")};HEAL_RETRY}
  };
  tokio::time::sleep(wait).await;
 }
}

/// 一档官方 K 线的覆盖：(行数, 最新开盘时刻)。
async fn coverage(pool:&PgPool,interval:&str)->sqlx::Result<(i64,Option<i64>)> {
 sqlx::query_as("SELECT count(*),max(open_time) FROM macro_bars WHERE symbol=$1 AND interval=$2 AND source=1")
  .bind(SYMBOL).bind(interval).fetch_one(pool).await
}

/// 收完整、在开盘时间里的那几根（休市窗口里 CNBC 也会冒几根，比如 17:00–17:33 ET，丢掉）。
pub fn completed(kind:BarKind,list:Vec<Bar>,now:i64)->Vec<Row> {
 list.into_iter().filter(|b|b.t+kind.step()<=now&&calendar::is_open(b.t))
  .map(|bar|Row{interval:kind.interval(),bar,official:true}).collect()
}

/// 已经收盘、周一到周五的交易日日线；坏的（高低包不住开收的已经在解析时扔了，这里再认四价相同的）
/// 记下来等 1H 补。返回 (收下的, 要补的交易日)。
pub fn completed_days(list:Vec<Bar>,now:i64,from:i64)->(Vec<Row>,Vec<NaiveDate>) {
 let mut rows=Vec::new();
 let mut have=BTreeSet::new();
 for bar in list {
  let d=cnbc::trading_day(bar.t);
  if matches!(d.weekday(),Weekday::Sat|Weekday::Sun)||calendar::session(d).1>now {continue}
  have.insert(d);
  let flat=bar.o==bar.h&&bar.h==bar.l&&bar.l==bar.c;
  if flat {continue}
  rows.push(Row{interval:"1d",bar,official:true});
 }
 let mut repair=Vec::new();
 let mut d=calendar::trading_date(from);
 let last=calendar::current_or_last(now);
 while d<=last {
  let complete=calendar::session(d).1<=now;
  let weekday=!matches!(d.weekday(),Weekday::Sat|Weekday::Sun);
  let good=rows.iter().any(|r|r.bar.t==calendar::day_label(d));
  if complete&&weekday&&!good&&(have.contains(&d)||d>=calendar::trading_date(now-100*DAY_MS)) {repair.push(d)}
  d=d.succ_opt().unwrap_or(d);
  if d==NaiveDate::MAX {break}
 }
 (rows,repair)
}

/// 一轮回填。返回写了（或试图写）多少行。
async fn heal(pool:&PgPool,_first:bool)->anyhow::Result<usize> {
 let now=now_ms();
 let mut total=0;
 // 1H、5M、1M：表里没有就整段取（分段，单次答复小），有就从最新那根往前留一点重取。
 for (kind,depth,chunk,overlap) in [
  (BarKind::H1,100*DAY_MS,100*DAY_MS,DAY_MS),
  (BarKind::M5,64*DAY_MS,8*DAY_MS,HOUR_MS),
  (BarKind::M1,30*DAY_MS,2*DAY_MS,10*MINUTE_MS),
 ] {
  let (_,newest)=coverage(pool,kind.interval()).await?;
  let mut from=newest.map_or(now-depth,|t|(t-overlap).max(now-depth));
  while from<now {
   let until=(from+chunk).min(now);
   let list=cnbc::bars(kind,from,until).await.map_err(|e|anyhow::anyhow!("{} {e}",kind.path()))?;
   let rows=match kind {
    BarKind::M1=>state().merge_minutes(&list,now),
    _=>completed(kind,list,now),
   };
   total+=rows.len();
   upsert(pool,&rows).await?;
   from=until;
  }
 }
 // 1D：没有十年就整段取，有就重取最近 15 天（CNBC 收盘后才出当天那根）。
 let (count,_)=coverage(pool,"1d").await?;
 let from=if count<2000 {now-3660*DAY_MS} else {now-15*DAY_MS};
 let list=cnbc::bars(BarKind::D1,from,now).await.map_err(|e|anyhow::anyhow!("1D {e}"))?;
 let (mut rows,repair)=completed_days(list,now,from);
 for d in repair {
  let (start,end)=calendar::session(d);
  let hours=read(pool,"1h",Some(start),Some(end-1),true,48).await?;
  if hours.len()<12 {continue}
  if let Some(mut bar)=bars::aggregate(&hours,Span::Fixed(100*DAY_MS)).first().copied() {
   bar.t=calendar::day_label(d);
   rows.push(Row{interval:"1d",bar,official:false});
  }
 }
 total+=rows.len();
 upsert(pool,&rows).await?;
 state().merge_days(&rows);
 bump();
 Ok(total)
}

// ------------------------------------------------------------------ 库

/// 写一批行。同一键已经是官方（`source=1`）的，只有官方的新值能改它；值没变的不重写。
pub async fn upsert(pool:&PgPool,rows:&[Row])->sqlx::Result<u64> {
 let mut unique:BTreeMap<(&str,i64),&Row>=BTreeMap::new();
 for r in rows {
  if !r.bar.sane() {continue}
  // 同一批里同一键出现两次时官方的优先（ON CONFLICT 不许一条语句改同一行两次）。
  match unique.get(&(r.interval,r.bar.t)) {Some(old) if old.official&&!r.official=>{},_=>{unique.insert((r.interval,r.bar.t),r);}}
 }
 let rows:Vec<&Row>=unique.into_values().collect();
 let mut written=0;
 for part in rows.chunks(5000) {
  let mut iv=Vec::with_capacity(part.len());let mut t=Vec::with_capacity(part.len());
  let (mut o,mut h,mut l,mut c,mut src)=(Vec::new(),Vec::new(),Vec::new(),Vec::new(),Vec::new());
  for r in part {iv.push(r.interval.to_string());t.push(r.bar.t);o.push(r.bar.o);h.push(r.bar.h);l.push(r.bar.l);c.push(r.bar.c);src.push(r.official as i16);}
  written+=sqlx::query("INSERT INTO macro_bars(symbol,interval,open_time,open,high,low,close,source) \
   SELECT $1,* FROM UNNEST($2::text[],$3::int8[],$4::float8[],$5::float8[],$6::float8[],$7::float8[],$8::int2[]) \
   ON CONFLICT (symbol,interval,open_time) DO UPDATE SET open=EXCLUDED.open,high=EXCLUDED.high,low=EXCLUDED.low,close=EXCLUDED.close,source=EXCLUDED.source,updated_at=now() \
   WHERE (macro_bars.source<>1 OR EXCLUDED.source=1) \
   AND (macro_bars.open,macro_bars.high,macro_bars.low,macro_bars.close,macro_bars.source) IS DISTINCT FROM (EXCLUDED.open,EXCLUDED.high,EXCLUDED.low,EXCLUDED.close,EXCLUDED.source)")
   .bind(SYMBOL).bind(&iv).bind(&t).bind(&o).bind(&h).bind(&l).bind(&c).bind(&src)
   .execute(pool).await?.rows_affected();
 }
 Ok(written)
}

/// 读一段（开盘时刻含两端）。`ascending=false` 时取最后 `limit` 根。答复一律按时间升序。
pub async fn read(pool:&PgPool,interval:&str,from:Option<i64>,until:Option<i64>,ascending:bool,limit:i64)->sqlx::Result<Vec<Bar>> {
 let sql=if ascending {
  "SELECT open_time,open,high,low,close FROM macro_bars WHERE symbol=$1 AND interval=$2 AND ($3::int8 IS NULL OR open_time>=$3) AND ($4::int8 IS NULL OR open_time<=$4) ORDER BY open_time ASC LIMIT $5"
 } else {
  "SELECT open_time,open,high,low,close FROM macro_bars WHERE symbol=$1 AND interval=$2 AND ($3::int8 IS NULL OR open_time>=$3) AND ($4::int8 IS NULL OR open_time<=$4) ORDER BY open_time DESC LIMIT $5"
 };
 let rows:Vec<(i64,f64,f64,f64,f64)>=sqlx::query_as(sql).bind(SYMBOL).bind(interval).bind(from).bind(until).bind(limit).fetch_all(pool).await?;
 let mut out:Vec<Bar>=rows.into_iter().map(|(t,o,h,l,c)|Bar{t,o,h,l,c}).collect();
 if !ascending {out.reverse()}
 Ok(out)
}

/// 各档行数（部署验证用）。
pub async fn counts(pool:&PgPool)->sqlx::Result<Vec<(String,i64,Option<i64>)>> {
 sqlx::query_as("SELECT interval,count(*),max(open_time) FROM macro_bars WHERE symbol=$1 GROUP BY interval ORDER BY interval").bind(SYMBOL).fetch_all(pool).await
}

#[cfg(test)]
mod tests {
 use super::*;
 use super::super::cnbc::Quote;
 fn ms(s:&str)->i64 {chrono::NaiveDateTime::parse_from_str(s,"%Y-%m-%d %H:%M").unwrap().and_utc().timestamp_millis()}
 const SEC:i64=1000;

 #[test] fn ticks_build_the_minute_and_its_coarser_buckets() {
  let mut st=State::default();
  let t=ms("2026-10-05 13:02")+5*SEC; // 周一 09:02 ET
  let rows=st.tick(102.0,t,Source::Official);
  assert_eq!(rows.iter().map(|r|r.interval).collect::<Vec<_>>(),vec!["1m","5m","1h","1d"]);
  assert_eq!(rows[0].bar,Bar::flat(ms("2026-10-05 13:02"),102.0));
  assert_eq!(rows[1].bar.t,ms("2026-10-05 13:00"));
  assert_eq!(rows[3].bar.t,ms("2026-10-05 00:00"),"labelled by trading date");
  assert!(rows.iter().all(|r|!r.official));
  let rows=st.tick(102.3,t+20*SEC,Source::Official);
  assert_eq!(rows[0].bar,Bar{t:ms("2026-10-05 13:02"),o:102.0,h:102.3,l:102.0,c:102.3});
  // 旧的、同一时刻的不收。
  assert!(st.tick(101.0,t+10*SEC,Source::Official).is_empty());
  assert!(st.tick(101.0,t+20*SEC,Source::Official).is_empty());
  assert_eq!(st.last.unwrap().price,102.3);
  // 下一分钟跌一点：5 分钟那根并进来。
  let rows=st.tick(101.9,ms("2026-10-05 13:03")+SEC,Source::Synthetic);
  assert_eq!(rows[1].bar,Bar{t:ms("2026-10-05 13:00"),o:102.0,h:102.3,l:101.9,c:101.9});
  assert_eq!(st.last.unwrap().source,Source::Synthetic);
 }

 #[test] fn ticks_outside_the_session_are_dropped() {
  let mut st=State::default();
  assert!(st.tick(102.0,ms("2026-10-03 15:00"),Source::Official).is_empty(),"Saturday");
  assert!(st.tick(102.0,ms("2026-10-05 21:10"),Source::Official).is_empty(),"17:10 ET daily break");
  assert!(st.last.is_none());
  assert!(st.tick(102.0,ms("2026-10-05 22:00"),Source::Official).iter().any(|r|r.interval=="1d"&&r.bar.t==ms("2026-10-06 00:00")),"18:00 ET belongs to the next trading day");
 }

 #[test] fn official_minutes_override_tick_minutes_and_stay() {
  let mut st=State::default();
  let m=ms("2026-10-05 13:02");
  st.tick(102.0,m+5*SEC,Source::Official);
  st.tick(102.5,m+50*SEC,Source::Official);
  let official=Bar{t:m,o:102.01,h:102.6,l:101.98,c:102.4};
  // 还没收完的那一分钟不收。
  assert!(st.merge_minutes(&[official],m+30*SEC).is_empty());
  let rows=st.merge_minutes(&[official,Bar::flat(ms("2026-10-05 21:20"),1.0)],m+90*SEC);
  assert_eq!(rows[0],Row{interval:"1m",bar:official,official:true});
  assert!(!rows.iter().any(|r|r.bar.t==ms("2026-10-05 21:20")),"break-window bar dropped");
  assert_eq!(rows.iter().find(|r|r.interval=="5m").unwrap().bar.h,102.6);
  assert_eq!(st.newest_official_minute(),Some(m));
  // 之后再来的报价不改官方分钟，但最后价照记。
  assert!(st.tick(103.0,m+59*SEC,Source::Official).is_empty());
  assert_eq!(st.minutes[&m].0,official);
  assert_eq!(st.last.unwrap().price,103.0);
 }

 #[test] fn the_quote_picks_official_then_calibrated_synthetic() {
  let now=ms("2026-10-05 10:12");
  let q=|s:&str,last:f64,time:i64|Some(Quote{symbol:s.into(),last,time,previous_close:None});
  let fx=[q("EUR=",1.1204,now-60*SEC),q("JPY=",157.92,now-60*SEC),q("GBP=",1.3223,now-60*SEC),q("CAD=",1.4248,now-60*SEC),q("SEK=",10.0334,now-60*SEC),q("CHF=",0.8291,now-60*SEC)];
  let mut st=State::default();
  let snap=Snapshot{official:Some(Quote{symbol:".DXY".into(),last:102.185,time:now-16*SEC,previous_close:Some(101.932)}),fx:fx.clone()};
  let (rows,calibrated)=st.on_quote(&snap,now);
  assert!(calibrated);
  assert_eq!(rows[0].bar.c,102.185);
  assert_eq!(st.last.unwrap().source,Source::Official);
  // 官方价停在三分钟前：改用合成价 × 校准比，落在官方价附近而不是合成价本身。
  let later=now+3*MINUTE_MS;
  let fx2=fx.iter().map(|x|x.clone().map(|mut q|{q.time=later-30*SEC;q})).collect::<Vec<_>>().try_into().unwrap();
  let stale=Snapshot{official:snap.official.clone(),fx:fx2};
  let (rows,calibrated)=st.on_quote(&stale,later);
  assert!(!calibrated);
  assert!((rows[0].bar.c-102.185).abs()<1e-6,"{}",rows[0].bar.c);
  assert_eq!(st.last.unwrap().source,Source::Synthetic);
  // 两样都不新鲜：不出价。
  let (rows,_)=st.on_quote(&stale,later+10*MINUTE_MS);
  assert!(rows.is_empty());
 }

 #[test] fn the_ticker_compares_with_the_previous_trading_day_close() {
  let mut st=State::default();
  let fri=ms("2026-10-02 00:00");
  st.days.insert(fri,(Bar{t:fri,o:102.0,h:102.1,l:101.6,c:101.932},true));
  let t=ms("2026-10-05 13:00");
  st.tick(102.0,t,Source::Official);
  st.tick(102.5,t+MINUTE_MS,Source::Official);
  st.tick(102.2,t+2*MINUTE_MS,Source::Official);
  let tk=st.ticker(t+2*MINUTE_MS+SEC).unwrap();
  assert_eq!(tk.prev_close,Some(101.932),"Friday is the previous trading day for Monday");
  assert_eq!((tk.open,tk.high,tk.low,tk.last),(102.0,102.5,102.0,102.2));
  assert_eq!(tk.session_start,ms("2026-10-04 22:00"));
  assert!(tk.open_now);
  // 报价里带了昨收就用它。
  st.prev_close=Some((NaiveDate::from_ymd_opt(2026,10,5).unwrap(),101.95));
  assert_eq!(st.ticker(t+3*MINUTE_MS).unwrap().prev_close,Some(101.95));
  // 价停了十分钟以上，或者到了休市时间：closed。
  assert!(!st.ticker(t+20*MINUTE_MS).unwrap().open_now);
  assert!(!st.ticker(ms("2026-10-03 12:00")).unwrap().open_now);
 }

 #[test] fn live_bars_cover_intraday_daily_and_calendar_spans() {
  let mut st=State::default();
  for k in 0..10 {st.tick(100.0+k as f64,ms("2026-10-05 13:00")+k*MINUTE_MS,Source::Official);}
  let mon=ms("2026-10-05 00:00");
  let fri=ms("2026-10-02 00:00");
  st.days.insert(fri,(Bar{t:fri,o:90.0,h:95.0,l:89.0,c:94.0},true));
  let b=st.live_bar(&bars::spec("3m").unwrap()).unwrap();
  assert_eq!(b,Bar{t:ms("2026-10-05 13:09"),o:109.0,h:109.0,l:109.0,c:109.0});
  let b=st.live_bar(&bars::spec("15m").unwrap()).unwrap();
  assert_eq!((b.t,b.o,b.c),(ms("2026-10-05 13:00"),100.0,109.0));
  let d=st.live_bar(&bars::spec("1d").unwrap()).unwrap();
  assert_eq!((d.t,d.o,d.h),(mon,100.0,109.0));
  let w=st.live_bar(&bars::spec("1w").unwrap()).unwrap();
  assert_eq!((w.t,w.o),(mon,100.0),"new ISO week");
  let m=st.live_bar(&bars::spec("1M").unwrap()).unwrap();
  assert_eq!((m.t,m.o,m.l,m.c),(ms("2026-10-01 00:00"),90.0,89.0,109.0),"October so far, from the Friday bar");
 }

 #[test] fn daily_backfill_keeps_completed_weekdays_and_flags_bad_ones() {
  let now=ms("2026-10-05 14:00");
  let bars=vec![
   Bar{t:ms("2026-10-01 00:00"),o:1.0,h:2.0,l:0.5,c:1.5},
   Bar::flat(ms("2026-10-02 00:00"),101.0), // 四价相同：坏的
   Bar{t:ms("2026-10-05 00:00"),o:1.0,h:2.0,l:0.5,c:1.5}, // 今天还没收盘
  ];
  let (rows,repair)=completed_days(bars,now,ms("2026-09-30 12:00"));
  assert_eq!(rows.iter().map(|r|r.bar.t).collect::<Vec<_>>(),vec![ms("2026-10-01 00:00")]);
  assert_eq!(repair,vec![NaiveDate::from_ymd_opt(2026,9,30).unwrap(),NaiveDate::from_ymd_opt(2026,10,2).unwrap()]);
 }

 async fn isolated_pool()->Option<PgPool> {
  let (Ok(admin),Ok(url),Ok(role))=(std::env::var("KANPAN_TEST_ADMIN_URL"),std::env::var("KANPAN_TEST_DATABASE_URL"),std::env::var("KANPAN_TEST_ROLE")) else {
   eprintln!("Skipping the macro_bars database assertions: run ops/test.py for an isolated PostgreSQL");
   return None;
  };
  assert!(role.chars().all(|c|c.is_ascii_alphanumeric()||c=='_'));
  for target in [&admin,&url] {assert!(target.contains("@127.0.0.1:")||target.contains("@localhost:"),"tests must never target a database off this machine");}
  let admin=PgPool::connect(&admin).await.unwrap();
  sqlx::migrate!().run(&admin).await.unwrap();
  for sql in [format!("GRANT USAGE ON SCHEMA public TO {role}"),format!("GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO {role}")] {
   sqlx::query(&sql).execute(&admin).await.unwrap();
  }
  Some(PgPool::connect(&url).await.unwrap())
 }

 #[tokio::test]
 async fn official_rows_win_and_unchanged_rows_are_not_rewritten() {
  let Some(pool)=isolated_pool().await else {return};
  sqlx::query("DELETE FROM macro_bars WHERE symbol=$1").bind(SYMBOL).execute(&pool).await.unwrap();
  let m=ms("2026-10-05 13:02");
  let tick=Row{interval:"1m",bar:Bar::flat(m,102.0),official:false};
  let official=Row{interval:"1m",bar:Bar{t:m,o:102.01,h:102.6,l:101.98,c:102.4},official:true};
  assert_eq!(upsert(&pool,&[tick]).await.unwrap(),1);
  assert_eq!(upsert(&pool,&[official]).await.unwrap(),1,"official overwrites synthetic");
  assert_eq!(upsert(&pool,&[Row{bar:Bar::flat(m,99.0),..tick}]).await.unwrap(),0,"synthetic never overwrites official");
  assert_eq!(upsert(&pool,&[official]).await.unwrap(),0,"unchanged rows are left alone");
  // 同一批里同一键两次：官方的留下。
  let m2=m+MINUTE_MS;
  upsert(&pool,&[Row{interval:"1m",bar:Bar::flat(m2,1.5),official:true},Row{interval:"1m",bar:Bar::flat(m2,2.5),official:false}]).await.unwrap();
  let got=read(&pool,"1m",None,None,false,10).await.unwrap();
  assert_eq!(got,vec![official.bar,Bar::flat(m2,1.5)]);
  let got=read(&pool,"1m",Some(m2),None,true,10).await.unwrap();
  assert_eq!(got,vec![Bar::flat(m2,1.5)]);
  let src:Vec<i16>=sqlx::query_scalar("SELECT source FROM macro_bars WHERE symbol=$1 ORDER BY open_time").bind(SYMBOL).fetch_all(&pool).await.unwrap();
  assert_eq!(src,vec![1,1]);
  assert_eq!(counts(&pool).await.unwrap(),vec![("1m".to_string(),2,Some(m2))]);
  sqlx::query("DELETE FROM macro_bars WHERE symbol=$1").bind(SYMBOL).execute(&pool).await.unwrap();
 }
}
