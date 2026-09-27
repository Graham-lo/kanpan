//! 交易复盘（`kind = "trade"`）：手机拼好的回合存进 `review_records`，worker 按 1m K 线
//! 回写持仓期间的最大浮盈 / 浮亏、平仓后 1h / 4h / 24h 的价格，以及自动截图的周期与时间窗。
//!
//! 口径只有一份：`docs/交易复盘-协议-2026-09-27.md`。字段名、幂等 id、换版规则、结果算法都照它，
//! 这里的注释只说「为什么这样落地」。
//!
//! - 和观点复盘同一张表、同一套 RLS（`personal_owner`）、同一个导出；不进 episode，不进统计，
//!   默认列表也不列（老客户端的 `ReviewRecord` 必须有 `draft`，解不开这一种）。
//! - 结果写在记录自己的 `result` 里、`revision + 1`、`review_events` 记一条 `trade_result`；
//!   新客户端按 `GET /v1/native-review/records?kind=trade` 或详情取。复盘记录本来就不走
//!   `/v1/sync`，这里也不往同步日志里另写一份（那会是第二个真相源，还得凭空起一个集合名）。
//! - 平仓后那三格按到期时刻排进现有的 `review_jobs`（`kind = trade_result`），到点再补；
//!   它不产生「待判定」：交易复盘既不进默认列表、也不进 `todo` 过滤。
use crate::{AppState,auth::Identity,envelope,error::{ApiError,Payload,Result,Route},review::{key,lock,cached,finish,event},review_market,sync_validation};
use axum::{Router,Json,extract::{State,DefaultBodyLimit},routing::post,http::HeaderMap};
use chrono::Utc;
use rust_decimal::{Decimal,RoundingStrategy};
use scorebook_core::{api::native_review::ChartRange,domain::criteria::Bar,market::MarketDataProvider};
use serde::{Deserialize,Serialize};
use base64::{Engine,engine::general_purpose::URL_SAFE_NO_PAD};
use serde_json::{Value,json};
use sha2::{Digest,Sha256};
use sqlx::{Postgres,Row,Transaction};
use uuid::Uuid;

/// `review_jobs.kind`：回写结果的那条任务。
pub const JOB:&str="trade_result";
/// 一次最多传几个回合（协议 3.2）。
pub const MAX_ROUNDS:usize=100;
/// 备注最长多少字（按字符数，协议 3.2）。
pub const NOTE_MAX_CHARS:usize=2000;
/// 上传那一条的请求体上限：100 个回合、每个带着成交明细，512 KiB 的默认上限装不下。
const UPLOAD_BODY_LIMIT:usize=6*1024*1024;
/// 拿不到 K 线的两种原因码（写进 `result.unavailable`）。
pub const KLINES_MISSING:&str="klines_missing";
/// 那根 K 线收盘之后再等多久才去取：给交易所一点落库的时间。
const SETTLE_MS:i64=30_000;
/// 该有的 K 线过了这么久还是不全，就认定交易所没有这一段（下架、太早），不再重试。
const GIVE_UP_AFTER_MS:i64=3_600_000;
/// 持仓超过这么久，浮盈浮亏改用 1h K 线（见协议 4.1）：1m 要几百页，一次任务的租约里取不完。
const MINUTE_BARS_UP_TO_MS:i64=30*86_400_000;
/// 一次向行情源要多少根：分段取、边取边算，进程里不会同时摊开整段持仓的 K 线。
const CHUNK_BARS:i64=10_000;
const MINUTE:i64=60_000;
const HOUR:i64=3_600_000;

pub fn routes()->Router<AppState> {
 Router::new()
  .route("/v1/native-review/trades",post(upload).layer(DefaultBodyLimit::max(UPLOAD_BODY_LIMIT)))
  .route("/v1/native-review/trades/{id}/note",post(note))
}

/// 协议 2.2 的幂等 id：同一个回合在哪台手机上拼出来都是同一条记录。
pub fn round_id(venue:&str,market:&str,tag:&str,symbol:&str,side:&str,first_fill:&str)->Uuid {
 let material=format!("trade-round-v1\n{venue}\n{market}\n{tag}\n{symbol}\n{side}\n{first_fill}");
 let digest=Sha256::digest(material.as_bytes());
 let mut b=[0u8;16];b.copy_from_slice(&digest[..16]);
 b[6]=(b[6]&0x0F)|0x80;b[8]=(b[8]&0x3F)|0x80;
 Uuid::from_bytes(b)
}
/// 按协议重算这个回合的 id；已经过了 `sync_validation::trade_round`，取值不会失败。
fn expected_id(r:&Value)->Uuid {
 let t=|k:&str|r[k].as_str().unwrap_or_default();
 round_id(t("venue"),t("market"),t("accountTag"),t("symbol"),t("positionSide"),r["fills"][0]["id"].as_str().unwrap_or_default())
}
/// 决定结果的那几样：变了就得清掉旧结果重算。协议写的是「open→closed、已平仓回合的成交 / 资金费变了」，
/// 资金费落在 `netPnl` 里（盈亏比要用），平仓均价落在 `closeAvgPrice` 里（平仓后涨跌要用）。
fn result_inputs(r:&Value)->Value {
 json!([r["status"],r["direction"],r["positionSide"],r["openedAt"],r["closedAt"],r["closeAvgPrice"],r["netPnl"],r["funding"],r["fills"]])
}
fn is_trade(record:&Value)->bool {record["kind"]=="trade"}
fn closed(round:&Value)->bool {round["status"]=="closed"}
/// 没算出结果之前，三列按回合本身的时间写（协议 3.1）。
fn columns_before_result(round:&Value)->(String,i64,i64) {
 let opened=round["openedAt"].as_i64().unwrap_or_default();
 (String::new(),opened,round["closedAt"].as_i64().or(round["updatedAt"].as_i64()).unwrap_or(opened))
}

#[derive(Deserialize)] struct Upload {rounds:Vec<Value>}
async fn upload(State(s):State<AppState>,i:Identity,headers:HeaderMap,Payload(body):Payload<Value>)->Result<Json<Value>> {
 let key=key(&headers)?;let now=Utc::now().timestamp_millis();
 let Upload{mut rounds}=serde_json::from_value(body.clone())?;
 if rounds.len()>MAX_ROUNDS {return Err(ApiError::bad("too_many_rounds"))}
 for r in &rounds {sync_validation::trade_round(r,now)?;}
 // id 对不上的整批拒收：那是客户端算法和协议不一致，存进来就会在两台手机上长出两份。
 for r in &mut rounds {
  let expected=expected_id(r);
  if Uuid::parse_str(r["id"].as_str().unwrap_or_default()).ok()!=Some(expected) {return Err(ApiError::bad("invalid_round_id"))}
  // 大小写不同的同一个 UUID 统一成协议的小写形式，库里只有一种写法。
  r["id"]=json!(expected.to_string());
 }
 let request=json!({"kind":"trades","rounds":rounds});
 let mut tx=s.personal(i.user).await?;lock(&mut tx,i.user).await?;
 // 重放只记 id、回当前的样子：回合带着成交明细，整份回应存进幂等表太大，而「同一个键再来一次
 // 不会多出一条」才是幂等要保证的事。
 if let Some(v)=cached(&mut tx,i.user,key,&request).await? {
  let ids:Vec<Uuid>=serde_json::from_value(v["ids"].clone())?;
  let mut records=vec![];
  for id in ids {records.push(current(&mut tx,i.user,id).await?);}
  tx.commit().await?;return Ok(envelope(json!({"records":records})))
 }
 let mut records=vec![];let mut ids=vec![];let mut schedule=false;
 for round in rounds {
  let id=expected_id(&round);ids.push(id);
  let (record,scheduled)=upsert(&mut tx,i.user,id,round,now).await?;
  schedule|=scheduled;records.push(record);
 }
 if schedule {sqlx::query("INSERT INTO review_dispatch(user_id) VALUES($1) ON CONFLICT(user_id) DO UPDATE SET next_at=least(review_dispatch.next_at,now())").bind(i.user).execute(&mut *tx).await?;}
 finish(&mut tx,i.user,key,&request,&json!({"ids":ids})).await?;
 tx.commit().await?;Ok(envelope(json!({"records":records})))
}
async fn current(tx:&mut Transaction<'_,Postgres>,owner:Uuid,id:Uuid)->Result<Value> {
 Ok(sqlx::query_scalar("SELECT record FROM review_records WHERE user_id=$1 AND id=$2").bind(owner).bind(id).fetch_one(&mut **tx).await?)
}
/// 结果任务排到现在（新建或者重置）。租约一并清掉：正在算旧版本的那一回合写回时会发现
/// 租约没了，不会把旧回合的结果盖到新回合上。
async fn schedule(tx:&mut Transaction<'_,Postgres>,owner:Uuid,id:Uuid)->Result<()> {
 sqlx::query("INSERT INTO review_jobs(user_id,id,record_id,kind) VALUES($1,$2,$3,$4) ON CONFLICT(user_id,record_id,kind) DO UPDATE SET finished=false,next_at=now(),lease_id=NULL,lease_until=NULL,attempts=0")
  .bind(owner).bind(Uuid::new_v4()).bind(id).bind(JOB).execute(&mut **tx).await?;Ok(())
}
async fn unschedule(tx:&mut Transaction<'_,Postgres>,owner:Uuid,id:Uuid)->Result<()> {
 sqlx::query("UPDATE review_jobs SET finished=true,lease_id=NULL,lease_until=NULL WHERE user_id=$1 AND record_id=$2 AND kind=$3").bind(owner).bind(id).bind(JOB).execute(&mut **tx).await?;Ok(())
}
/// 一个回合的 upsert（协议 3.2）。回来的是存下的记录，以及要不要叫醒调度。
async fn upsert(tx:&mut Transaction<'_,Postgres>,owner:Uuid,id:Uuid,round:Value,now:i64)->Result<(Value,bool)> {
 let old:Option<Value>=sqlx::query_scalar("SELECT record FROM review_records WHERE user_id=$1 AND id=$2 FOR UPDATE").bind(owner).bind(id).fetch_optional(&mut **tx).await?;
 let symbol=round["symbol"].as_str().unwrap_or_default().to_owned();
 let Some(mut record)=old else {
  let record=json!({"kind":"trade","id":id,"revision":1,"submitted":now,"updated":now,"voided":false,"round":round,"result":null,"note":null});
  let (timeframe,start,end)=columns_before_result(&round);
  // episode_id 留空、group_pending 为假：交易复盘不参与观点复盘的分组（协议 3.1）。
  sqlx::query("INSERT INTO review_records(user_id,id,record,submitted,symbol,timeframe,range_start,range_end,episode_id,group_pending) VALUES($1,$2,$3,$4,$5,$6,$7,$8,NULL,false)")
   .bind(owner).bind(id).bind(&record).bind(now).bind(&symbol).bind(timeframe).bind(start).bind(end).execute(&mut **tx).await?;
  let scheduled=closed(&round);
  if scheduled {schedule(tx,owner,id).await?;}
  event(tx,owner,id,"trade_uploaded",json!({"revision":1,"status":round["status"],"updatedAt":round["updatedAt"]})).await?;
  return Ok((record,scheduled))
 };
 // 同一个 UUID 已经是一条观点复盘：哈希撞上几乎不可能，真撞上了也不能把人家的记录盖掉。
 if !is_trade(&record) {return Err(ApiError::conflict("record_identity_conflict"))}
 let old_round=record["round"].clone();
 // 一模一样：不动。晚到的旧版本：丢掉。两种都回库里现在的样子。
 if old_round==round||round["updatedAt"].as_i64()<old_round["updatedAt"].as_i64() {return Ok((record,false))}
 let reset=result_inputs(&old_round)!=result_inputs(&round);
 let revision=record["revision"].as_i64().unwrap_or(0)+1;
 record["round"]=round.clone();record["revision"]=json!(revision);record["updated"]=json!(now);
 let mut scheduled=false;
 if reset {
  record["result"]=Value::Null;
  let (timeframe,start,end)=columns_before_result(&round);
  sqlx::query("UPDATE review_records SET timeframe=$3,range_start=$4,range_end=$5 WHERE user_id=$1 AND id=$2").bind(owner).bind(id).bind(timeframe).bind(start).bind(end).execute(&mut **tx).await?;
  if closed(&round) {schedule(tx,owner,id).await?;scheduled=true;} else {unschedule(tx,owner,id).await?;}
 } else if record["result"].is_null() {
  // 结果还没有：范围列跟着回合走（持仓中的回合 updatedAt 会变大）。
  let (_,start,end)=columns_before_result(&round);
  sqlx::query("UPDATE review_records SET range_start=$3,range_end=$4 WHERE user_id=$1 AND id=$2").bind(owner).bind(id).bind(start).bind(end).execute(&mut **tx).await?;
 }
 sqlx::query("UPDATE review_records SET record=$3,symbol=$4,changed_at=now() WHERE user_id=$1 AND id=$2").bind(owner).bind(id).bind(&record).bind(&symbol).execute(&mut **tx).await?;
 event(tx,owner,id,"trade_replaced",json!({"revision":revision,"status":round["status"],"updatedAt":round["updatedAt"],"resultCleared":reset})).await?;
 Ok((record,scheduled))
}

/// 交易复盘的翻页游标：按平仓时间倒序，持仓中的（没有平仓时间）排最前。
#[derive(Serialize,Deserialize)] struct Cursor {closed:i64,id:Uuid}
/// `GET /v1/native-review/records?kind=trade`（协议 3.2）：其余过滤参数只认 `after`、`symbol`。
/// 排序键与 0028 的部分索引逐字一致。
pub async fn list(s:AppState,owner:Uuid,after:Option<String>,symbol:Option<String>)->Result<Json<Value>> {
 let cursor=match after {
  Some(v)=>{if v.len()>200 {return Err(ApiError::bad("invalid_cursor"))}Some(serde_json::from_slice::<Cursor>(&URL_SAFE_NO_PAD.decode(v).map_err(|_|ApiError::bad("invalid_cursor"))?).map_err(|_|ApiError::bad("invalid_cursor"))?)}
  None=>None,
 };
 if symbol.as_ref().is_some_and(|s|s.len()>40) {return Err(ApiError::bad("invalid_filter"))}
 let mut tx=s.personal(owner).await?;
 let rows=sqlx::query("SELECT record,id,COALESCE((record#>>'{round,closedAt}')::bigint,9223372036854775807) AS closed FROM review_records WHERE user_id=$1 AND record->>'kind'='trade' AND ($2::bigint IS NULL OR (COALESCE((record#>>'{round,closedAt}')::bigint,9223372036854775807),id)<($2,$3)) AND ($4::text IS NULL OR symbol=$4) ORDER BY COALESCE((record#>>'{round,closedAt}')::bigint,9223372036854775807) DESC,id DESC LIMIT 51")
  .bind(owner).bind(cursor.as_ref().map(|c|c.closed)).bind(cursor.as_ref().map(|c|c.id)).bind(symbol).fetch_all(&mut *tx).await?;
 let records:Vec<Value>=rows.iter().take(50).map(|r|r.get("record")).collect();
 let next=if rows.len()>50 {let r=&rows[49];Some(URL_SAFE_NO_PAD.encode(serde_json::to_vec(&Cursor{closed:r.get("closed"),id:r.get("id")})?))} else {None};
 tx.commit().await?;Ok(envelope(json!({"records":records,"next":next})))
}

#[derive(Deserialize)] #[serde(rename_all="camelCase",deny_unknown_fields)] struct NoteInput {expected_revision:i64,text:String}
async fn note(State(s):State<AppState>,i:Identity,Route(id):Route<Uuid>,headers:HeaderMap,Payload(body):Payload<Value>)->Result<Json<Value>> {
 let key=key(&headers)?;
 let input:NoteInput=serde_json::from_value(body.clone())?;
 if input.text.chars().count()>NOTE_MAX_CHARS {return Err(ApiError::bad("invalid_note"))}
 let request=json!({"kind":"trade_note","id":id,"body":body});
 let mut tx=s.personal(i.user).await?;lock(&mut tx,i.user).await?;
 if cached(&mut tx,i.user,key,&request).await?.is_some() {
  let record=current(&mut tx,i.user,id).await?;tx.commit().await?;return Ok(envelope(json!({"record":record})))
 }
 let mut record:Value=sqlx::query_scalar("SELECT record FROM review_records WHERE user_id=$1 AND id=$2 FOR UPDATE").bind(i.user).bind(id).fetch_optional(&mut *tx).await?.filter(is_trade).ok_or_else(ApiError::missing)?;
 if record["revision"].as_i64()!=Some(input.expected_revision) {return Err(ApiError::conflict("record_revision_changed"))}
 let now=Utc::now().timestamp_millis();let revision=input.expected_revision+1;
 // 空串（只有空白也算）就是清掉。
 record["note"]=if input.text.trim().is_empty() {Value::Null} else {json!({"text":input.text,"updatedAt":now})};
 record["revision"]=json!(revision);record["updated"]=json!(now);
 sqlx::query("UPDATE review_records SET record=$3,changed_at=now() WHERE user_id=$1 AND id=$2").bind(i.user).bind(id).bind(&record).execute(&mut *tx).await?;
 event(&mut tx,i.user,id,"trade_note",json!({"revision":revision,"note":record["note"]})).await?;
 finish(&mut tx,i.user,key,&request,&json!({"id":id})).await?;
 tx.commit().await?;Ok(envelope(json!({"record":record})))
}

// ——— 结果（协议第 4 节）———

fn d(v:&Value)->Option<Decimal> {v.as_str().and_then(sync_validation::decimal)}
/// 协议第 1 节的输出形式：按位数四舍六入五成双，去掉尾随 0，零写 `"0"`。
pub fn text(v:Decimal,dp:u32)->String {
 let v=v.round_dp_with_strategy(dp,RoundingStrategy::MidpointNearestEven).normalize();
 if v.is_zero() {"0".into()} else {v.to_string()}
}
fn rounded(v:Decimal,dp:u32)->Decimal {v.round_dp_with_strategy(dp,RoundingStrategy::MidpointNearestEven)}

/// 回合里算结果要用的那几样，已经解好。
pub struct Round {pub symbol:String,pub opened:i64,pub closed:i64,pub close_avg:Decimal,pub net_pnl:Decimal,pub fills:Vec<Fill>}
#[derive(Clone,Copy)] pub struct Fill {pub time:i64,pub signed:Decimal,pub price:Decimal}
impl Round {
 pub fn parse(r:&Value)->Option<Self> {
  let fills=r["fills"].as_array()?.iter().map(|f|{
   let qty=d(&f["qty"])?;
   Some(Fill{time:f["time"].as_i64()?,signed:if f["side"]=="BUY"{qty}else{-qty},price:d(&f["price"])?})
  }).collect::<Option<Vec<_>>>()?;
  Some(Self{symbol:r["symbol"].as_str()?.into(),opened:r["openedAt"].as_i64()?,closed:r["closedAt"].as_i64()?,close_avg:d(&r["closeAvgPrice"])?,net_pnl:d(&r["netPnl"])?,fills})
 }
}
/// 持仓：有符号数量与持仓均价。
#[derive(Clone,Copy,Default)] struct Position {q:Decimal,avg:Decimal}
impl Position {
 fn apply(&mut self,f:&Fill) {
  if self.q.is_zero()||self.q.is_sign_positive()==f.signed.is_sign_positive() {
   let size=self.q.abs()+f.signed.abs();
   self.avg=(self.q.abs()*self.avg+f.signed.abs()*f.price)/size;self.q+=f.signed;
  } else {
   let next=self.q+f.signed;
   // 回合里的成交不会穿过 0（反手在客户端已经拆开）；真穿过了，多出来的那一截不属于这个回合。
   self.q=if !next.is_zero()&&next.is_sign_positive()!=self.q.is_sign_positive() {Decimal::ZERO} else {next};
  }
 }
}
/// 一个点上的浮盈、浮亏以及各自相对均价的比值（协议 4.1 的式子，按方向取号）。
fn point(p:Position,high:Decimal,low:Decimal)->(Decimal,Decimal,Decimal,Decimal) {
 let size=p.q.abs();
 if p.q.is_sign_positive() {((high-p.avg)*size,(low-p.avg)*size,(high-p.avg)/p.avg,(low-p.avg)/p.avg)}
 else {((p.avg-low)*size,(p.avg-high)*size,(p.avg-low)/p.avg,(p.avg-high)/p.avg)}
}
/// 边取 K 线边累计的极值。同值取更早的那一刻。
#[derive(Default)] pub struct Excursion {fills:usize,position:Position,fav:Option<(Decimal,Decimal,i64)>,adv:Option<(Decimal,Decimal,i64)>}
impl Excursion {
 fn consider(&mut self,(fav,adv,fav_pct,adv_pct):(Decimal,Decimal,Decimal,Decimal),at:i64) {
  if self.fav.is_none_or(|(v,_,t)|fav>v||(fav==v&&at<t)) {self.fav=Some((fav,fav_pct,at));}
  if self.adv.is_none_or(|(v,_,t)|adv<v||(adv==v&&at<t)) {self.adv=Some((adv,adv_pct,at));}
 }
 /// 喂一根 K 线（`size` 毫秒长）。K 线必须按时间顺序、首尾相接地喂。
 pub fn bar(&mut self,round:&Round,start:i64,size:i64,high:Decimal,low:Decimal) {
  let end=start+size;
  let mut last=(!self.position.q.is_zero()).then_some(self.position);
  while let Some(f)=round.fills.get(self.fills).filter(|f|f.time<end) {
   // 成交那一刻按成交价算一次，用这笔成交之前的持仓：平仓那一笔就是「以这个价平掉整仓」。
   if !self.position.q.is_zero() {let p=self.position;self.consider(point(p,f.price,f.price),f.time);}
   self.position.apply(f);
   if !self.position.q.is_zero() {last=Some(self.position);}
   self.fills+=1;
  }
  // 这根 K 线里仓位已经归零（平仓那一根）：用这根里最后一个非零状态。
  let state=if self.position.q.is_zero() {last} else {Some(self.position)};
  if let Some(p)=state {self.consider(point(p,high,low),start);}
 }
 pub fn finish(&self,round:&Round)->Value {
  let (fav,fav_pct,fav_at)=self.fav.map(|(v,p,t)|(rounded(v.max(Decimal::ZERO),8),p,t)).unwrap_or((Decimal::ZERO,Decimal::ZERO,0));
  let (adv,adv_pct,adv_at)=self.adv.map(|(v,p,t)|(rounded(v.min(Decimal::ZERO),8),p,t)).unwrap_or((Decimal::ZERO,Decimal::ZERO,0));
  let reward_risk=(!adv.is_zero()).then(||text(round.net_pnl/adv.abs(),4));
  json!({
   "maxFavorable":text(fav,8),"maxFavorablePct":if fav.is_zero(){"0".into()}else{text(fav_pct,6)},"maxFavorableAt":(!fav.is_zero()).then_some(fav_at),
   "maxAdverse":text(adv,8),"maxAdversePct":if adv.is_zero(){"0".into()}else{text(adv_pct,6)},"maxAdverseAt":(!adv.is_zero()).then_some(adv_at),
   "rewardRisk":reward_risk,
  })
 }
}
/// 自动截图的周期与时间窗（协议 4.3）。
pub fn chart(opened:i64,closed:i64,computed:i64)->Value {
 let holding=closed-opened;
 let (interval,period)=if holding<=14_400_000 {("5m",300_000)} else if holding<=172_800_000 {("1h",HOUR)} else if holding<=1_209_600_000 {("4h",14_400_000)} else {("1d",86_400_000)};
 let pad=(10*period).max(holding/4);
 let start=(opened-pad).div_euclid(period)*period;
 let end=(-(-(closed+pad)).div_euclid(period)*period).min(computed.div_euclid(period)*period);
 json!({"interval":interval,"start":start,"end":end})
}
fn range(symbol:&str,interval:&str,start:i64,end:i64,size:i64)->ChartRange {
 ChartRange{venue:"binance".into(),market:"usd_m".into(),symbol:symbol.into(),interval:interval.into(),start,end,bars:((end-start)/size) as usize}
}
/// 一段 K 线：齐了就是 `Some`，不齐（交易所没给全）是 `None`。
async fn bars(market:&dyn MarketDataProvider,symbol:&str,interval:&str,size:i64,start:i64,end:i64)->Result<Option<Vec<(i64,Decimal,Decimal,Decimal)>>> {
 let at=|t:i64|chrono::DateTime::from_timestamp_millis(t).ok_or_else(||ApiError::bad("invalid_time"));
 let data=review_market::klines(market,&range(symbol,interval,start,end,size),at(start)?,at(end)?).await?;
 let bars:Vec<Bar>=serde_json::from_value(data["bars"].clone()).unwrap_or_default();
 let mut out=Vec::with_capacity(bars.len());let mut cursor=start;
 for b in &bars {
  let (s,e)=(b.start.timestamp_millis(),b.end.timestamp_millis());
  let (Some(high),Some(low),Some(close))=(sync_validation::decimal(&b.high),sync_validation::decimal(&b.low),sync_validation::decimal(&b.close)) else {return Ok(None)};
  if s!=cursor||e!=s+size||high<low||low.is_sign_negative() {return Ok(None)}
  out.push((s,high,low,close));cursor=e;
 }
 if data["coverage_complete"]!=true||cursor!=end {return Ok(None)}
 Ok(Some(out))
}
/// 一部分结果这一回的结局。
enum Part {Done(Value),Missing(&'static str),Later(i64)}
fn later_or_missing(target:i64,now:i64)->Part {if now>target+GIVE_UP_AFTER_MS {Part::Missing(KLINES_MISSING)} else {Part::Later(now+MINUTE)}}
/// 行情源在本节点被拒（451 那一类）：记原因、一天后再试，不编数。
fn blocked_or(e:ApiError)->Result<Part> {if e.1==review_market::BLOCKED {Ok(Part::Missing(review_market::BLOCKED))} else {Err(e)}}
async fn excursion(market:&dyn MarketDataProvider,round:&Round,now:i64)->Result<Part> {
 let (interval,size)=if round.closed-round.opened<=MINUTE_BARS_UP_TO_MS {("1m",MINUTE)} else {("1h",HOUR)};
 let start=round.opened.div_euclid(size)*size;let end=round.closed.div_euclid(size)*size+size;
 // 平仓那一根还没收：到点再来。
 if now<end+SETTLE_MS {return Ok(Part::Later(end+SETTLE_MS))}
 let mut acc=Excursion::default();let mut cursor=start;
 while cursor<end {
  let stop=(cursor+CHUNK_BARS*size).min(end);
  match bars(market,&round.symbol,interval,size,cursor,stop).await {
   Ok(Some(chunk))=>for (t,high,low,_) in chunk {acc.bar(round,t,size,high,low)},
   Ok(None)=>return Ok(later_or_missing(end,now)),
   Err(e)=>return blocked_or(e),
  }
  cursor=stop;
 }
 Ok(Part::Done(acc.finish(round)))
}
/// 平仓后某一格（协议 4.2）：收盘时间 ≤ 目标时刻的最后一根 1m K 线的收盘价。
async fn after(market:&dyn MarketDataProvider,round:&Round,hours:i64,now:i64)->Result<Part> {
 let target=round.closed+hours*HOUR;
 if now<target+SETTLE_MS {return Ok(Part::Later(target+SETTLE_MS))}
 let open=target.div_euclid(MINUTE)*MINUTE-MINUTE;
 match bars(market,&round.symbol,"1m",MINUTE,open,open+MINUTE).await {
  Ok(Some(bars))=>{
   let price=bars[0].3;
   let change=(price-round.close_avg)/round.close_avg;
   Ok(Part::Done(json!({"at":target,"price":text(price,8),"changePct":text(change,6)})))
  }
  Ok(None)=>Ok(later_or_missing(target,now)),
  Err(e)=>blocked_or(e),
 }
}
/// 这一回算出来的新结果（没有可写的就是 `None`），以及下一次什么时候再来（`None` 就是全部做完）。
pub struct Plan {pub result:Option<Value>,pub next:Option<i64>}
const CELLS:[(&str,i64);3]=[("h1",1),("h4",4),("h24",24)];
fn wake(next:&mut Option<i64>,t:i64) {*next=Some(next.map_or(t,|n|n.min(t)));}
/// 已经定下来的部分不再重算；被拒的部分（`market_region_blocked`）一天后再试；`klines_missing` 是终态。
pub async fn plan(market:&dyn MarketDataProvider,round:&Round,old:&Value,now:i64)->Result<Plan> {
 let retry_blocked=now+86_400_000;
 let mut next:Option<i64>=None;
 let mut unavailable=serde_json::Map::new();
 // 浮盈浮亏
 let excursion_value=if !old.is_null()&&!old["excursion"].is_null() {old["excursion"].clone()}
  else if old["unavailable"]["excursion"]==KLINES_MISSING {unavailable.insert("excursion".into(),json!(KLINES_MISSING));Value::Null}
  else {
   match excursion(market,round,now).await? {
    Part::Done(v)=>v,
    Part::Missing(code)=>{if code!=KLINES_MISSING {wake(&mut next,retry_blocked)}unavailable.insert("excursion".into(),json!(code));Value::Null}
    // 这一部分都还没着落，整份结果先不写：客户端看到的还是「计算中」。
    Part::Later(t)=>return Ok(Plan{result:None,next:Some(t)}),
   }
  };
 let mut cells=serde_json::Map::new();
 for (name,hours) in CELLS {
  if !old.is_null()&&!old["after"][name].is_null() {cells.insert(name.into(),old["after"][name].clone());continue}
  if old["unavailable"][name]==KLINES_MISSING {cells.insert(name.into(),Value::Null);unavailable.insert(name.into(),json!(KLINES_MISSING));continue}
  let value=match after(market,round,hours,now).await? {
   Part::Done(v)=>v,
   Part::Missing(code)=>{if code!=KLINES_MISSING {wake(&mut next,retry_blocked)}unavailable.insert(name.into(),json!(code));Value::Null}
   Part::Later(t)=>{wake(&mut next,t);Value::Null}
  };
  cells.insert(name.into(),value);
 }
 let result=json!({"version":1,"computedAt":now,"excursion":excursion_value,"after":cells,"chart":chart(round.opened,round.closed,now),"unavailable":unavailable});
 // 和上一版比，除了计算时刻与截图右沿之外什么都没变（被拒之后的又一次被拒）：不换版。
 let same=|a:&Value,b:&Value|a["excursion"]==b["excursion"]&&a["after"]==b["after"]&&a["unavailable"]==b["unavailable"];
 let result=(old.is_null()||!same(&result,old)).then_some(result);
 Ok(Plan{result,next})
}

/// worker 认领到一条 `trade_result` 任务。租约与重试的口径和观点复盘那两种任务一样
/// （`review_worker::run_one`）：算的时候不占事务，写回前确认租约还在、回合没换过。
pub async fn run_job(s:&AppState,market:&dyn MarketDataProvider,owner:Uuid,job:Uuid,id:Uuid,lease:Uuid)->Result<bool> {
 let mut tx=s.personal(owner).await?;
 let record:Option<Value>=sqlx::query_scalar("SELECT record FROM review_records WHERE user_id=$1 AND id=$2").bind(owner).bind(id).fetch_optional(&mut *tx).await?;
 tx.commit().await?;
 let now=Utc::now().timestamp_millis();
 let round=record.as_ref().filter(|r|is_trade(r)&&closed(&r["round"])).and_then(|r|Round::parse(&r["round"]));
 let outcome=match (&record,&round) {
  (Some(r),Some(round))=>Some(plan(market,round,&r["result"],now).await),
  _=>None,
 };
 let mut tx=s.personal(owner).await?;
 let active:Option<Uuid>=sqlx::query_scalar("SELECT id FROM review_jobs WHERE user_id=$1 AND id=$2 AND lease_id=$3 AND lease_until>now() AND NOT finished FOR UPDATE").bind(owner).bind(job).bind(lease).fetch_optional(&mut *tx).await?;
 if active.is_none() {return Ok(true)}
 let release=|next:Option<i64>,failed:bool|sqlx::query("UPDATE review_jobs SET finished=$4,lease_id=NULL,lease_until=NULL,next_at=COALESCE(to_timestamp($5::float8/1000),now()),attempts=CASE WHEN $6 OR $4 THEN attempts ELSE 0 END WHERE user_id=$1 AND id=$2 AND lease_id=$3")
  .bind(owner).bind(job).bind(lease).bind(next.is_none()&&!failed).bind(next.map(|t|t as f64)).bind(failed);
 let next=match outcome {
  // 记录没了、换成了持仓中、或者读不出来：这条任务没有下文。
  None=>{release(None,false).execute(&mut *tx).await?;tx.commit().await?;return Ok(true)}
  Some(Err(e))=>{
   tracing::warn!(%owner,record=%id,code=e.1,"Trade result will retry");
   let at=now+60_000;release(Some(at),true).execute(&mut *tx).await?;
   sqlx::query("UPDATE review_dispatch SET next_at=least(next_at,to_timestamp($2::float8/1000)) WHERE user_id=$1").bind(owner).bind(at as f64).execute(&mut *tx).await?;
   tx.commit().await?;return Ok(true)
  }
  Some(Ok(plan))=>{
   let mut fresh:Value=sqlx::query_scalar("SELECT record FROM review_records WHERE user_id=$1 AND id=$2 FOR UPDATE").bind(owner).bind(id).fetch_one(&mut *tx).await?;
   // 算的这段时间里回合被换过（上传会重置租约，这里是第二道保险）：不写，马上重来。
   if record.as_ref().is_none_or(|r|r["round"]!=fresh["round"]) {release(Some(now),false).execute(&mut *tx).await?;tx.commit().await?;return Ok(true)}
   if let Some(result)=plan.result {
    let revision=fresh["revision"].as_i64().unwrap_or(0)+1;
    let chart=result["chart"].clone();
    fresh["result"]=result;fresh["revision"]=json!(revision);fresh["updated"]=json!(now);
    sqlx::query("UPDATE review_records SET record=$3,timeframe=$4,range_start=$5,range_end=$6,changed_at=now() WHERE user_id=$1 AND id=$2")
     .bind(owner).bind(id).bind(&fresh).bind(chart["interval"].as_str().unwrap_or_default()).bind(chart["start"].as_i64()).bind(chart["end"].as_i64()).execute(&mut *tx).await?;
    let filled:Vec<&str>=std::iter::once("excursion").chain(CELLS.iter().map(|(n,_)|*n)).filter(|p|if *p=="excursion"{!fresh["result"]["excursion"].is_null()}else{!fresh["result"]["after"][*p].is_null()}).collect();
    event(&mut tx,owner,id,"trade_result",json!({"revision":revision,"filled":filled,"unavailable":fresh["result"]["unavailable"]})).await?;
   }
   plan.next
  }
 };
 release(next,false).execute(&mut *tx).await?;
 if let Some(at)=next {sqlx::query("UPDATE review_dispatch SET next_at=least(next_at,to_timestamp($2::float8/1000)) WHERE user_id=$1").bind(owner).bind(at as f64).execute(&mut *tx).await?;}
 tx.commit().await?;Ok(true)
}

#[cfg(test)]
mod tests {
 use super::*;
 fn dec(s:&str)->Decimal {s.parse().unwrap()}
 /// 协议 2.2 的两组测试向量，两端都钉住。
 #[test] fn round_ids_match_the_protocol_vectors() {
  assert_eq!(round_id("binance","usd_m","primary","BTCUSDT","BOTH","5012345678").to_string(),"2a54e776-a993-8446-b97e-ed7561670918");
  assert_eq!(round_id("binance","usd_m","primary","ETHUSDT","SHORT","987654321").to_string(),"7482f6ac-d858-8f56-9479-152b2fd978e9");
 }
 #[test] fn decimals_print_the_protocol_way() {
  assert_eq!(text(dec("1.50"),8),"1.5");assert_eq!(text(dec("-0.000"),8),"0");
  assert_eq!(text(dec("0.0000125"),6),"0.000012","五成双：…25 → …2");
  assert_eq!(text(dec("0.0000135"),6),"0.000014");
  assert!(sync_validation::decimal("1e5").is_none());assert!(sync_validation::decimal("+1").is_none());
  assert!(sync_validation::decimal("1,000").is_none());assert!(sync_validation::decimal(".5").is_none());
  assert!(sync_validation::decimal("5.").is_none());assert_eq!(sync_validation::decimal("-35.5"),Some(dec("-35.5")));
 }
 /// 协议 4.3 的表，边界含等号；右沿不越过计算时刻。
 #[test] fn chart_windows_follow_the_holding_table() {
  let open=1_790_000_000_000i64;
  let c=chart(open,open+14_400_000,open+100*86_400_000);assert_eq!(c["interval"],"5m");
  assert_eq!(c["start"],json!((open-3_600_000).div_euclid(300_000)*300_000));
  assert_eq!(c["end"],json!(-(-(open+14_400_000+3_600_000)).div_euclid(300_000)*300_000));
  assert_eq!(chart(open,open+14_400_001,open+100*86_400_000)["interval"],"1h");
  assert_eq!(chart(open,open+172_800_000,open+100*86_400_000)["interval"],"1h");
  assert_eq!(chart(open,open+1_209_600_000,open+100*86_400_000)["interval"],"4h");
  assert_eq!(chart(open,open+1_209_600_001,open+100*86_400_000)["interval"],"1d");
  // 刚平仓：右沿停在计算时刻那一格。
  let c=chart(open,open+60_000,open+120_000);assert_eq!(c["end"],json!((open+120_000).div_euclid(300_000)*300_000));
  // 短持仓的 pad 至少十个周期。
  let c=chart(open,open+60_000,open+100*86_400_000);assert_eq!(c["start"],json!((open-3_000_000).div_euclid(300_000)*300_000));
 }
 fn round(fills:&[(i64,&str,&str,&str)],net:&str)->Round {
  Round{symbol:"BTCUSDT".into(),opened:fills[0].0,closed:fills.last().unwrap().0,close_avg:dec("0"),net_pnl:dec(net),
   fills:fills.iter().map(|(t,side,qty,price)|Fill{time:*t,signed:if *side=="BUY"{dec(qty)}else{-dec(qty)},price:dec(price)}).collect()}
 }
 /// 多头：开 1 @100，加 1 @110（均价 105），平 2 @120。
 #[test] fn long_excursion_uses_the_running_average_and_fill_points() {
  let t=1_790_000_040_000i64;let base=t-40_000;
  let r=round(&[(t,"BUY","1","100"),(t+60_000,"BUY","1","110"),(t+120_000,"SELL","2","120")],"29");
  let mut e=Excursion::default();
  e.bar(&r,base,60_000,dec("101"),dec("95"));          // q=1 avg=100：浮盈 1，浮亏 −5
  e.bar(&r,base+60_000,60_000,dec("112"),dec("104"));  // q=2 avg=105：浮盈 14，浮亏 −2
  e.bar(&r,base+120_000,60_000,dec("125"),dec("119")); // 平仓那一根：用平之前的 q=2 avg=105 → 浮盈 40
  let v=e.finish(&r);
  assert_eq!(v["maxFavorable"],"40");assert_eq!(v["maxFavorableAt"],json!(base+120_000));assert_eq!(v["maxFavorablePct"],"0.190476");
  assert_eq!(v["maxAdverse"],"-5");assert_eq!(v["maxAdverseAt"],json!(base));assert_eq!(v["maxAdversePct"],"-0.05");
  assert_eq!(v["rewardRisk"],"5.8");
 }
 /// 空头：开 2 @100，平 2 @90；浮盈看低点、浮亏看高点。
 #[test] fn short_excursion_flips_the_signs() {
  let t=1_790_000_000_000i64;
  let r=round(&[(t,"SELL","2","100"),(t+60_000,"BUY","2","90")],"20");
  let mut e=Excursion::default();
  e.bar(&r,t,60_000,dec("103"),dec("99"));
  e.bar(&r,t+60_000,60_000,dec("95"),dec("88"));
  let v=e.finish(&r);
  assert_eq!(v["maxFavorable"],"24");assert_eq!(v["maxFavorablePct"],"0.12");assert_eq!(v["maxFavorableAt"],json!(t+60_000));
  assert_eq!(v["maxAdverse"],"-6");assert_eq!(v["maxAdversePct"],"-0.03");
  assert_eq!(v["rewardRisk"],"3.3333");
 }
 /// 一路没吃过亏：浮亏 0、时刻 null、比值 "0"、盈亏比 null。
 #[test] fn no_adverse_move_means_no_reward_risk() {
  let t=1_790_000_000_000i64;
  let r=round(&[(t,"BUY","1","100"),(t+30_000,"SELL","1","105")],"5");
  let mut e=Excursion::default();e.bar(&r,t,60_000,dec("106"),dec("100"));
  let v=e.finish(&r);
  assert_eq!(v["maxAdverse"],"0");assert_eq!(v["maxAdverseAt"],Value::Null);assert_eq!(v["maxAdversePct"],"0");assert_eq!(v["rewardRisk"],Value::Null);
  assert_eq!(v["maxFavorable"],"6");
 }
}
