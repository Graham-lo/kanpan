use crate::review_domain as domain;
// Bounded, fenced work: public prices are temporary inputs, never an account history download.
use crate::{AppState,error::{ApiError,Result},review::{parse,core,event},crypto::digest};
use scorebook_core::{api::native_review::*,domain::{criteria::Bar,interval::Interval,chart_match},market::MarketDataProvider};
use chrono::Utc;
use serde_json::{Value,json};
use sqlx::Row;
use uuid::Uuid;

struct Job {owner:Uuid,id:Uuid,record:Uuid,kind:String,lease:Uuid}
/// 一条任务**连续**失败几次就不再认领。`attempts` 在认领时 +1，没做完但这一回算成功
/// （还在等行情、或者行情源被封锁这种已知情形）时归零，所以它数的是「上次成功以来认领了
/// 几次」；做完了（`finished`）就原样留着，当作这条任务一共被认领了几回。计算报错、
/// 记录读不出来、worker 半路崩掉（租约过期）都会让它一路涨上去。以前没有上限，一条
/// 坏任务每两分钟被认领一次、永远报同一个错。
pub const MAX_ATTEMPTS:i32=5;
/// 连续失败到头了：这一回不再做，把任务标成结束。
fn exhausted(attempts:i32)->bool {attempts>=MAX_ATTEMPTS}
/// 这一回的结局算不算「又失败了一次」。行情源在本节点被封锁不算：那是已知的长期状态，
/// 已经按一天一次退避，换节点或解封之后要能自己恢复，不能五天后就永远放弃。
fn counts_as_failure(error:Option<&ApiError>)->bool {error.is_some_and(|e|e.1!=crate::review_market::BLOCKED)}
/// 认领一条任务。一个人手上此刻没有能做的（全在等、全在租约里、或刚被判「失败放弃」），
/// 就换下一个到期的人，而不是空手回去让循环睡一觉：以前每遇到一个这样的人，整个队列
/// 就白等两秒。换人最多 `CLAIM_OWNERS` 次——调度行被别的事务锁着时，同一个人可能一直
/// 排在最前面，不设上限就会原地打转。
const CLAIM_OWNERS:usize=8;
async fn claim(s:&AppState)->Result<Option<Job>> {
 for _ in 0..CLAIM_OWNERS {
 let mut tx=s.pool.begin().await?;
 let owner:Option<Uuid>=sqlx::query_scalar("SELECT user_id FROM review_dispatch WHERE next_at<=now() ORDER BY next_at,user_id FOR UPDATE SKIP LOCKED LIMIT 1").fetch_optional(&mut *tx).await?;
 let Some(owner)=owner else{return Ok(None)};
 sqlx::query("UPDATE review_dispatch SET next_at=now()+interval '2 seconds' WHERE user_id=$1").bind(owner).execute(&mut *tx).await?;
 tx.commit().await?;
 let mut tx=s.personal(owner).await?;
 let row=sqlx::query("SELECT id,record_id,kind,attempts FROM review_jobs WHERE user_id=$1 AND NOT finished AND next_at<=now() AND (lease_until IS NULL OR lease_until<now()) ORDER BY next_at,id FOR UPDATE SKIP LOCKED LIMIT 1").bind(owner).fetch_optional(&mut *tx).await?;
 let Some(row)=row else {
  sqlx::query("UPDATE review_dispatch SET next_at=COALESCE((SELECT min(greatest(next_at,COALESCE(lease_until,next_at))) FROM review_jobs WHERE user_id=$1 AND NOT finished),now()+interval '1 hour') WHERE user_id=$1").bind(owner).execute(&mut *tx).await?;tx.commit().await?;continue
 };
 let id:Uuid=row.try_get("id")?;
 let attempts:i32=row.try_get("attempts")?;
 if exhausted(attempts) {
  // 标成结束（finished 且 attempts ≥ MAX_ATTEMPTS 就是「失败放弃」），租约清掉，调度往后推。
  sqlx::query("UPDATE review_jobs SET finished=true,lease_id=NULL,lease_until=NULL WHERE user_id=$1 AND id=$2").bind(owner).bind(id).execute(&mut *tx).await?;
  tx.commit().await?;
  tracing::error!(%owner,job=%id,"Review job failed {attempts} times in a row; marked failed and no longer retried");
  continue
 }
 let lease=Uuid::new_v4();
 sqlx::query("UPDATE review_jobs SET lease_id=$3,lease_until=now()+interval '120 seconds',attempts=attempts+1 WHERE user_id=$1 AND id=$2").bind(owner).bind(id).bind(lease).execute(&mut *tx).await?;
 tx.commit().await?;return Ok(Some(Job{owner,id,record:row.get("record_id"),kind:row.get("kind"),lease}))
 }
 Ok(None)
}
/// worker 的「判定」循环：有活就一条接一条地做，队列空了才睡 `idle`。
///
/// 以前是每做完一条都睡两秒（在 `main.rs` 里），整个 worker 一秒最多判半条：每个人
/// 自己的调度行本来就按两秒一条限着，全局再睡两秒，六个人各有一条到期的任务就要排
/// 十二秒，`trade_touch` 那种五秒一查的记录永远追不上。
pub async fn work(s:&AppState,market:&dyn MarketDataProvider,idle:std::time::Duration) {
 crate::supervise::poll_loop("Review",idle,||run_one(s,market)).await
}
pub async fn range_bars(market:&dyn MarketDataProvider,r:&ChartRange,cutoff:i64)->Result<Vec<Bar>> {
 let iv=core(domain::validate_range(r,cutoff))?;
 let data=crate::review_market::klines(market,r,core(domain::time(r.start))?,core(domain::time(r.end))?).await?;
 let bars:Vec<Bar>=parse(data["bars"].clone())?;
 if data["coverage_complete"]!=true || bars.len()!=r.bars || bars.first().is_none_or(|b|b.start.timestamp_millis()!=r.start) || bars.last().is_none_or(|b|b.end.timestamp_millis()!=r.end) || !valid_bars(&bars,iv) {return Err(ApiError::bad("chart_range_incomplete"))}
 Ok(bars)
}
fn valid_bars(bars:&[Bar],iv:Interval)->bool {
 bars.windows(2).all(|w|w[0].end==w[1].start) && bars.iter().all(|b|{
  let values=[&b.open,&b.high,&b.low,&b.close].map(|s|s.parse::<f64>().ok().filter(|v|v.is_finite()&&*v>0.0));
  if let [Some(o),Some(h),Some(l),Some(c)]=values {iv.floor(b.start)==b.start&&iv.add_bars(b.start,1)==b.end&&h>=o.max(c)&&l<=o.min(c)&&h>=l}else{false}
 })
}
pub fn trade_assessment(r:&NativeRecord,raw:&[Value],from:i64,until:i64,now:i64)->Result<(NativeAssessment,Option<i64>)> {
 let rule=&r.draft.rule;
 let result=|outcome:&str,reason:&str,event_at:Option<i64>|NativeAssessment{outcome:outcome.into(),reason:reason.into(),event_at,assessed_at:now};
 let mut previous=None;
 // Validate the complete segment before using even an early terminal event.
 for t in raw {
  let id=t["a"].as_i64().ok_or_else(||ApiError::bad("invalid_trade"))?;
  let at=t["T"].as_i64().ok_or_else(||ApiError::bad("invalid_trade"))?;
  if let Some((p,time))=previous&& (id!=p+1 || at<time) {return Ok((result("needs_verification","成交顺序尚不完整",None),None))}
  let price=t["p"].as_str().and_then(|s|s.parse::<f64>().ok());
  if at<from||at>until||price.is_none_or(|p|!p.is_finite()||p<=0.0) {return Err(ApiError::bad("invalid_trade"))}
  previous=Some((id,at));
 }
 for t in raw {
  let at=t["T"].as_i64().unwrap();if at>rule.expires {continue}
  let price=t["p"].as_str().unwrap().parse::<f64>().unwrap();
  let hit=if rule.direction=="long"{price>=rule.target}else{price<=rule.target};
  let lost=if rule.direction=="long"{price<=rule.invalidation}else{price>=rule.invalidation};
  if hit||lost {return Ok((result(if hit{"realized"}else{"unrealized"},if hit{"成交先达到目标"}else{"成交先达到失效价"},Some(at)),None))}
 }
 // Provider end is inclusive; next segment begins at the next millisecond, preserving ties within this one.
 if until>=rule.expires {Ok((result("unrealized","到期未达到目标",Some(rule.expires)),None))}
 else {Ok((result("waiting","等待行情",None),Some(until+1)))}
}
/// 一次裁定的输出：结论、下一次从哪儿接着看（`None` 就是原地不挪）、以及这条任务还有没有下文。
/// `settled` 是给那些「结论不是终态，但再等下去也不会有新证据」的分支留的：
/// 待核实本身不是终态（行情补齐了就能接着算），所以不能靠 outcome 分辨。
struct Verdict {assessment:NativeAssessment,checkpoint:Option<i64>,settled:bool}
/// 还有下文：写下结论，过一阵再来一次。
fn open(assessment:NativeAssessment)->Verdict {Verdict{assessment,checkpoint:None,settled:false}}
/// 没有下文了：写下结论就把任务收掉，不再留一个永远重来、永远答不了的幽灵。
fn closed(assessment:NativeAssessment)->Verdict {Verdict{assessment,checkpoint:None,settled:true}}
async fn assess(market:&dyn MarketDataProvider,r:&NativeRecord,checkpoint:Option<i64>,now:i64)->Result<Verdict> {
 let answer=|state:&str,reason:&str,at:Option<i64>|NativeAssessment{outcome:state.into(),reason:reason.into(),event_at:at,assessed_at:now};
 let rule=&r.draft.rule;
 if r.voided||rule.direction=="observe"||r.submitted>=rule.expires {return Ok(open(core(domain::evaluate(r,&[],now))?))}
 let from=checkpoint.unwrap_or(r.submitted);
 if from>now {return Ok(open(answer("waiting","等待行情",None)))}
 if rule.confirmation=="trade_touch" {
  // Leave one second for the exchange to settle the covered endpoint.
  let until=(now-1_000).min(rule.expires).min(from+30_000);
  if until<=from {return Ok(open(answer("waiting","等待行情",None)))}
  let range=&r.draft.range;
  // 逐笔按记录自己的交易所取：币安走 aggTrades，Coinbase 走它自己的成交号（同一品种上连续）。
  // 两家给出的形状一样（`raw:[{a,T,p}]` + `coverage_complete`），下面的判定不分家。
  let data=match (range.venue.as_str(),range.market.as_str()) {
   ("binance","usd_m")=>market.trades(&range.market,&range.symbol,core(domain::time(from))?,core(domain::time(until))?).await.map_err(|e|crate::review_market::refusal(&e,&range.symbol))?,
   ("coinbase","spot")=>{
    crate::review_market::coinbase_ready()?;
    crate::venues::coinbase::trades(&range.symbol,from,until).await.map_err(crate::review_market::coinbase_refusal)?
   }
   _=>return Err(ApiError::bad("invalid_chart_range")),
  };
  if data["coverage_complete"]!=true{return Ok(open(answer("needs_verification","成交数据尚不完整",None)))}
  let raw=data["raw"].as_array().ok_or_else(||ApiError::bad("invalid_trade"))?;
  let (assessment,checkpoint)=trade_assessment(r,raw,from,until,now)?;
  return Ok(Verdict{assessment,checkpoint,settled:false})
 }
 let iv=core(Interval::exact(&r.draft.range.interval))?;
 let begin=iv.ceil(core(domain::time(from))?);let end=iv.floor(core(domain::time(now.min(rule.expires)))?);
 if end<=begin {
  // 一根合规的观察收盘都排不出来（例：4h 图 09:15 提交、13:15 到期，08:00 那根在提交时
  // 已经开了所以不算，12:00 那根到期时还没收）。没有证据不等于有证据证明没达标：
  // 结论统一交给领域层（空证据 + 已到期 = 待核实），这里不再自己生一个判输。
  // 窗口已经关了，再取多少次也排不出那根不存在的 K 线，所以一并把任务收掉。
  if now>=rule.expires {return Ok(closed(core(domain::evaluate(r,&[],now))?))}
  return Ok(open(answer("waiting","等待下一根收盘",None)))
 }
 let until=end.min(iv.add_bars(begin,1000));
 let data=crate::review_market::klines(market,&r.draft.range,begin,until).await?;
 let bars:Vec<Bar>=parse(data["bars"].clone())?;
 if data["coverage_complete"]!=true||bars.first().is_none_or(|b|b.start!=begin)||bars.last().is_none_or(|b|b.end!=until)||!valid_bars(&bars,iv) {return Ok(open(answer("needs_verification","判定行情尚不完整",None)))}
 let mut segment=r.clone();segment.submitted=begin.timestamp_millis();
 let evaluation=core(domain::evaluate(&segment,&bars,now.min(until.timestamp_millis())))?;
 if evaluation.outcome=="waiting"&&now>=rule.expires&&until==end{return Ok(open(answer("unrealized","到期未达到目标",Some(rule.expires))))}
 let checkpoint=(evaluation.outcome=="waiting").then_some(until.timestamp_millis());Ok(Verdict{assessment:evaluation,checkpoint,settled:false})
}
pub async fn run_one(s:&AppState,market:&dyn MarketDataProvider)->Result<bool> {
 let Some(j)=claim(s).await? else {return Ok(false)};
 let mut tx=s.personal(j.owner).await?;
 let row=sqlx::query("SELECT record,checkpoint FROM review_records WHERE user_id=$1 AND id=$2").bind(j.owner).bind(j.record).fetch_optional(&mut *tx).await?.ok_or_else(ApiError::missing)?;
 let r:NativeRecord=parse(row.get("record"))?;let checkpoint:Option<i64>=row.get("checkpoint");tx.commit().await?;
 let now=Utc::now().timestamp_millis();
 enum Output {Index(Option<Vec<f32>>,String),Assessment(Verdict)}
 let computation=async {
  if j.kind=="index" {let bars=range_bars(market,&r.draft.range,now).await?;let vector=if bars.len()>=16 {Some(core(chart_match::descriptor(&core(chart_match::from_bars(&bars))?))?)}else{None};Ok(Output::Index(vector,digest(serde_json::to_vec(&bars)?)))}
  else {Ok::<_,ApiError>(Output::Assessment(assess(market,&r,checkpoint,now).await?))}
 }.await;
 let mut tx=s.personal(j.owner).await?;
 let active:Option<Uuid>=sqlx::query_scalar("SELECT id FROM review_jobs WHERE user_id=$1 AND id=$2 AND lease_id=$3 AND lease_until>now() AND NOT finished FOR UPDATE").bind(j.owner).bind(j.id).bind(j.lease).fetch_optional(&mut *tx).await?;
 if active.is_none(){return Ok(true)}
 let value:Value=sqlx::query_scalar("SELECT record FROM review_records WHERE user_id=$1 AND id=$2 FOR UPDATE").bind(j.owner).bind(j.record).fetch_one(&mut *tx).await?;
 let mut fresh:NativeRecord=parse(value)?;let mut done=fresh.voided;let mut delay=30i32;
 let failed=counts_as_failure(computation.as_ref().err());
 if !fresh.voided {match computation {
  Ok(Output::Index(vector,hash))=>{
   fresh.eligible=fresh.draft.original_claimed.is_none()&&(fresh.submitted-fresh.draft.created).abs()<=60_000&&fresh.draft.rule.expires>fresh.submitted&&fresh.draft.rule.direction!="observe";
   sqlx::query("UPDATE review_records SET source_verified=true,source_hash=$3,feature=$4::vector,feature_version=$5 WHERE user_id=$1 AND id=$2").bind(j.owner).bind(j.record).bind(&hash).bind(vector.as_ref().map(|v|format!("{v:?}"))).bind(vector.as_ref().map(|_|chart_match::MODEL)).execute(&mut *tx).await?;
   event(&mut tx,j.owner,j.record,"source_verified",json!({"sourceHash":hash,"eligible":fresh.eligible,"model":chart_match::MODEL})).await?;done=true;
  },
  Ok(Output::Assessment(Verdict{assessment:a,checkpoint:c,settled}))=>{
   done=settled||matches!(a.outcome.as_str(),"realized"|"unrealized"|"observation"|"voided")||fresh.submitted>=fresh.draft.rule.expires;
   let changed=fresh.assessment.as_ref().is_none_or(|old|old.outcome!=a.outcome||old.event_at!=a.event_at||old.reason!=a.reason);
   if changed {event(&mut tx,j.owner,j.record,"assessment",json!(a)).await?;
    sqlx::query("UPDATE review_records SET assessment_revision=assessment_revision+1 WHERE user_id=$1 AND id=$2").bind(j.owner).bind(j.record).execute(&mut *tx).await?;
   }
   fresh.assessment=Some(a);sqlx::query("UPDATE review_records SET checkpoint=COALESCE($3,checkpoint) WHERE user_id=$1 AND id=$2").bind(j.owner).bind(j.record).bind(c).execute(&mut *tx).await?;
   delay=if c.is_some_and(|at|at<now-60_000){2}else if fresh.draft.rule.confirmation=="trade_touch"{5}else{30};
  },
  Err(ref e)=>{
   // A regional block is not a transient fault. Retrying it every 60 seconds
   // left one permanent ghost job per record, polling an upstream that will
   // keep saying no. Back off a day instead of giving up entirely, so a node
   // failover or a lifted block still recovers without anyone intervening.
   let region=e.1==crate::review_market::BLOCKED;delay=if region{86_400}else{60};
   if j.kind=="assess"&&fresh.assessment.as_ref().is_none_or(|a|!matches!(a.outcome.as_str(),"realized"|"unrealized"|"observation")){fresh.assessment=Some(NativeAssessment{outcome:"needs_verification".into(),reason:if region{"行情源在本节点被封锁"}else{"行情待补齐"}.into(),event_at:None,assessed_at:now});}}
 }}
 sqlx::query("UPDATE review_records SET record=$3,changed_at=now() WHERE user_id=$1 AND id=$2").bind(j.owner).bind(j.record).bind(json!(fresh)).execute(&mut *tx).await?;
 sqlx::query("UPDATE review_jobs SET finished=$4,lease_id=NULL,lease_until=NULL,next_at=now()+make_interval(secs=>$5),attempts=CASE WHEN $6 OR $4 THEN attempts ELSE 0 END WHERE user_id=$1 AND id=$2 AND lease_id=$3").bind(j.owner).bind(j.id).bind(j.lease).bind(done).bind(delay).bind(failed).execute(&mut *tx).await?;
 sqlx::query("UPDATE review_dispatch SET next_at=least(next_at,now()+make_interval(secs=>$2)) WHERE user_id=$1").bind(j.owner).bind(delay).execute(&mut *tx).await?;
 tx.commit().await?;Ok(true)
}

#[cfg(test)]
mod tests {
 /// 连续五次失败之后不再认领；封锁不算失败（按天退避、能自己恢复），成功把计数归零。
 #[test] fn a_job_is_given_up_after_five_failures_in_a_row() {
  assert!(!super::exhausted(4));
  assert!(super::exhausted(super::MAX_ATTEMPTS));
  assert_eq!(super::MAX_ATTEMPTS,5);
  assert!(!super::counts_as_failure(None),"a success resets the count");
  assert!(super::counts_as_failure(Some(&crate::error::ApiError::bad("upstream"))));
  assert!(!super::counts_as_failure(Some(&crate::error::ApiError(axum::http::StatusCode::SERVICE_UNAVAILABLE,crate::review_market::BLOCKED))),"a regional block keeps its daily retry");
 }
 use super::*;
 fn record(confirmation:&str)->NativeRecord {
  let now=1_800_000_000_000i64;
  parse(json!({"draft":{"id":Uuid::new_v4(),"range":{"venue":"binance","market":"usd_m","symbol":"BTCUSDT","interval":"1m","start":now-180_000,"end":now,"bars":3},"rule":{"version":"criteria-v2","direction":"long","confirmation":confirmation,"reference":100,"target":110,"invalidation":90,"expires":now+180_000},"text":"","confidence":null,"origin":"chart_first","created":now,"chartSettings":null,"drawingSnapshot":null,"originalClaimed":null},"serverId":Uuid::new_v4(),"submitted":now,"revision":0,"assessment":null,"reflection":{"note":"","nextTime":"","publishedAt":null,"revision":0},"reflectionHistory":[],"syncError":null,"eligible":true,"voided":false})).unwrap()
 }
 fn bar(at:i64,high:f64,low:f64,close:f64)->Bar {
  Bar{start:domain::time(at).unwrap(),end:domain::time(at+60_000).unwrap(),open:"100".into(),high:high.to_string(),low:low.to_string(),close:close.to_string(),volume:Some("1".into())}
 }
 #[test] fn same_bar_two_touches_never_guesses_order() {
  let r=record("trade_touch");let at=r.submitted;
  let a=domain::evaluate(&r,&[bar(at,120.0,80.0,100.0)],at+60_000).unwrap();assert_eq!(a.outcome,"needs_verification");
 }
 #[test] fn exact_trades_choose_first_event_including_equal_timestamp() {
  let r=record("trade_touch");let at=r.submitted;
  let (a,_)=trade_assessment(&r,&[json!({"a":10,"T":at,"p":"89"}),json!({"a":11,"T":at,"p":"111"})],at,at+1_000,at+2_000).unwrap();assert_eq!(a.outcome,"unrealized");assert_eq!(a.event_at,Some(at));
 }
 #[test] fn missing_trade_id_cannot_prove_an_early_target() {
  let r=record("trade_touch");let at=r.submitted;
  let (a,c)=trade_assessment(&r,&[json!({"a":10,"T":at,"p":"111"}),json!({"a":12,"T":at+1,"p":"89"})],at,at+1_000,at+2_000).unwrap();assert_eq!(a.outcome,"needs_verification");assert!(c.is_none());
 }
 #[test] fn inclusive_trade_boundary_moves_next_checkpoint_one_millisecond() {
  let r=record("trade_touch");let at=r.submitted;let (a,c)=trade_assessment(&r,&[json!({"a":10,"T":at+30_000,"p":"100"})],at,at+30_000,at+31_000).unwrap();assert_eq!(a.outcome,"waiting");assert_eq!(c,Some(at+30_001));
 }
 #[test] fn unclosed_bar_and_submission_bar_cannot_win_bar_close() {
  let mut r=record("bar_close");let at=r.submitted;r.submitted+=1;
  let a=domain::evaluate(&r,&[bar(at,120.0,99.0,119.0),bar(at+60_000,120.0,99.0,119.0)],at+90_000).unwrap();assert_eq!(a.outcome,"waiting");
  let a=domain::evaluate(&r,&[bar(at+60_000,120.0,99.0,119.0)],at+120_000).unwrap();assert_eq!(a.outcome,"realized");assert_eq!(a.event_at,Some(at+120_000));
 }
 #[test] fn gaps_cannot_turn_expiry_into_a_loss() {
  let r=record("bar_close");let at=r.submitted;
  let a=domain::evaluate(&r,&[bar(at,102.0,99.0,100.0),bar(at+120_000,102.0,99.0,100.0)],at+180_000).unwrap();assert_eq!(a.outcome,"needs_verification");
 }
}
