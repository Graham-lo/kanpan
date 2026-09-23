use crate::review_domain as domain;
// Native records are authoritative here; charts remain in the existing app/market stack.
use crate::{AppState,auth::Identity,crypto::digest,envelope,error::{ApiError,Params,Payload,Result,Route}};
use axum::{Router,Json,extract::{State,DefaultBodyLimit},routing::{get,post},http::HeaderMap};
use base64::{Engine,engine::general_purpose::{STANDARD,URL_SAFE_NO_PAD}};
use chrono::Utc;
use scorebook_core::{api::native_review::*,domain::{statistics}};
use serde::{Deserialize,Serialize};
use serde_json::{Value,json};
use sqlx::{Row,Postgres,Transaction};
use uuid::Uuid;
use std::collections::BTreeMap;

pub fn routes()->Router<AppState> {
 Router::new().route("/v1/native-review/records",get(list).post(create))
 .route("/v1/native-review/records/{id}",get(detail))
 .route("/v1/native-review/records/{id}/reflection",post(reflection))
 .route("/v1/native-review/records/{id}/void",post(void_record))
 .route("/v1/native-review/records/{id}/group",post(group))
 // 这一条走自己的体积上限：整套 API 的默认是 512 KiB，而一张 2× 缩放的行情截图
 // base64 之后三四百 KB 起步。限在 3 MiB——解码后必须 ≤ 2 MiB（见 `shot_put`），
 // 3 MiB 正好兜住 base64 的 4/3 膨胀加 JSON 外壳，再多一个字节都不收。
 .route("/v1/native-review/records/{id}/shot",post(shot_put).get(shot_get)
  .layer(DefaultBodyLimit::max(3*1024*1024)))
 .route("/v1/native-review/statistics",get(stats))
 // 修订记录（P3.7）：这一条记录从记下到现在的每一版规则 / 判定 / 复盘，只读。
 .route("/v1/native-review/records/{id}/revisions",get(revisions))
 // 补图（P3.7）：人事后从相册里挑的图，一条记录最多三张。上传那一条单独放宽体积：
 // 单张解码后 ≤ 5 MiB，base64 膨胀 4/3 再加 JSON 外壳，7 MiB 正好兜住。
 .route("/v1/native-review/records/{id}/attachments",get(attachments))
 .route("/v1/native-review/attachments",post(attachment_put).layer(DefaultBodyLimit::max(ATTACHMENT_BODY_LIMIT)))
 .route("/v1/native-review/attachments/{id}",get(attachment_get).delete(attachment_delete))
}
pub fn parse<T:serde::de::DeserializeOwned>(value:Value)->Result<T> {Ok(serde_json::from_value(value)?)}
/// 领域层的校验码就是服务端的真话：原样透出来，客户端才知道是区间不对、规则不对
/// 还是周期不支持，而不是永远一句 invalid_review_evidence。名单外的一律折成旧码：
/// 错误码是契约的一部分，不能跟着领域库里一句 `Error::bad` 就长出新的一个。
pub fn core<T>(value:scorebook_core::error::Result<T>)->Result<T> {value.map_err(|e|ApiError::bad(match e.code.as_str() {
 "invalid_chart_range"=>"invalid_chart_range","unsupported_interval"=>"unsupported_interval",
 "invalid_native_record"=>"invalid_native_record","invalid_native_rule"=>"invalid_native_rule",
 "invalid_time"=>"invalid_time","invalid_market_price"=>"invalid_market_price",
 _=>"invalid_review_evidence"}))}
pub fn key(headers:&HeaderMap)->Result<Uuid> {headers.get("idempotency-key").and_then(|h|h.to_str().ok()).and_then(|s|Uuid::parse_str(s).ok()).ok_or_else(||ApiError::bad("idempotency_key_required"))}
pub async fn lock(tx:&mut Transaction<'_,Postgres>,owner:Uuid)->Result<()> {
 sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))").bind(format!("review:{owner}")).execute(&mut **tx).await?;Ok(())
}
pub async fn cached(tx:&mut Transaction<'_,Postgres>,owner:Uuid,key:Uuid,body:&Value)->Result<Option<Value>> {
 if let Some(row)=sqlx::query("SELECT digest,result FROM review_operations WHERE user_id=$1 AND id=$2").bind(owner).bind(key).fetch_optional(&mut **tx).await? {
  if row.get::<String,_>("digest")!=digest(serde_json::to_vec(body)?) {return Err(ApiError::conflict("idempotency_mismatch"))}
  return Ok(Some(row.get("result")))
 } Ok(None)
}
pub async fn finish(tx:&mut Transaction<'_,Postgres>,owner:Uuid,key:Uuid,body:&Value,result:&Value)->Result<()> {
 sqlx::query("INSERT INTO review_operations(user_id,id,digest,result) VALUES($1,$2,$3,$4)").bind(owner).bind(key).bind(digest(serde_json::to_vec(body)?)).bind(result).execute(&mut **tx).await?;Ok(())
}
pub async fn event(tx:&mut Transaction<'_,Postgres>,owner:Uuid,id:Uuid,kind:&str,body:Value)->Result<()> {
 sqlx::query("INSERT INTO review_events(user_id,id,record_id,kind,body) VALUES($1,$2,$3,$4,$5)").bind(owner).bind(Uuid::new_v4()).bind(id).bind(kind).bind(body).execute(&mut **tx).await?;Ok(())
}
fn validate(d:&NativeDraft,now:i64)->Result<()> {
 core(domain::validate(d,now))?;
 let iv=core(domain::validate_range(&d.range,now))?;
 let start=core(domain::time(d.range.start))?;let end=core(domain::time(d.range.end))?;
 if iv.floor(start)!=start || iv.floor(end)!=end || d.range.end>d.created+60_000 {return Err(ApiError::bad("invalid_chart_range"))}
 if let Some(encoded)=&d.chart_settings {
  let bytes=STANDARD.decode(encoded).map_err(|_|ApiError::bad("invalid_chart_snapshot"))?;
  let v:Value=serde_json::from_slice(&bytes)?;
  if v["version"]!=1 || v.as_object().is_none_or(|o|o.keys().any(|k|k!="version"&&k!="fields")) {return Err(ApiError::bad("invalid_chart_snapshot"))}
  let fields:BTreeMap<String,Value>=parse(v["fields"].clone())?;
  let op=crate::sync::Operation{id:Uuid::nil(),collection:"settings".into(),object_id:"prefs".into(),device_id:Uuid::nil(),base_revision:0,generation:0,timestamp:now,logical:0,action:"patch".into(),fields,import_batch:None};op.validate()?;
  // A snapshot is stored whole and never merged, so there is no receipt to report a dropped
  // field on: an unfamiliar key here is refused outright rather than silently kept.
  if !op.unknown_fields().is_empty() {return Err(ApiError::bad("invalid_chart_snapshot"))}
 }
 if let Some(encoded)=&d.drawing_snapshot {
  let bytes=STANDARD.decode(encoded).map_err(|_|ApiError::bad("invalid_drawing_snapshot"))?;
  let _:Value=serde_json::from_slice(&bytes)?;
 }
 Ok(())
}
async fn create(State(s):State<AppState>,i:Identity,headers:HeaderMap,Payload(input):Payload<NativeDraft>)->Result<Json<Value>> {
 let key=key(&headers)?;let now=Utc::now().timestamp_millis();validate(&input,now)?;
 let request=json!({"kind":"create","draft":input});
 let mut tx=s.personal(i.user).await?;lock(&mut tx,i.user).await?;
 if let Some(v)=cached(&mut tx,i.user,key,&request).await? {return Ok(envelope(v))}
 if let Some(old)=sqlx::query_scalar::<_,Value>("SELECT record FROM review_records WHERE user_id=$1 AND id=$2").bind(i.user).bind(input.id).fetch_optional(&mut *tx).await? {
  if old["draft"]!=json!(input){return Err(ApiError::conflict("record_identity_conflict"))}
  let response=json!({"record":old});finish(&mut tx,i.user,key,&request,&response).await?;tx.commit().await?;return Ok(envelope(response))
 }
 // Same anchored 120-hour episode policy as Scorebook. A suggested link is not a confirmed sample.
 let prior:Option<Uuid>=sqlx::query_scalar("SELECT id FROM review_episodes WHERE user_id=$1 AND symbol=$2 AND market=$3 AND anchor_at<=$4 AND end_at>=$4 ORDER BY anchor_at DESC,id DESC LIMIT 1")
  .bind(i.user).bind(&input.range.symbol).bind(&input.range.market).bind(now).fetch_optional(&mut *tx).await?;
 let episode=prior.unwrap_or_else(Uuid::new_v4);
 if prior.is_none() {sqlx::query("INSERT INTO review_episodes(user_id,id,symbol,market,anchor_at,end_at) VALUES($1,$2,$3,$4,$5,$6)").bind(i.user).bind(episode).bind(&input.range.symbol).bind(&input.range.market).bind(now).bind(now+120*3_600_000).execute(&mut *tx).await?;}
 let id=input.id;
 let record=NativeRecord{draft:input,server_id:id,submitted:now,revision:0,assessment:None,reflection:NativeReflection::default(),reflection_history:vec![],sync_error:None,eligible:false,voided:false};
 sqlx::query("INSERT INTO review_records(user_id,id,record,submitted,symbol,timeframe,range_start,range_end,episode_id,group_pending) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)")
 .bind(i.user).bind(id).bind(json!(record)).bind(now).bind(&record.draft.range.symbol).bind(&record.draft.range.interval).bind(record.draft.range.start).bind(record.draft.range.end).bind(episode).bind(prior.is_some()).execute(&mut *tx).await?;
 for kind in ["index","assess"] {sqlx::query("INSERT INTO review_jobs(user_id,id,record_id,kind) VALUES($1,$2,$3,$4)").bind(i.user).bind(Uuid::new_v4()).bind(id).bind(kind).execute(&mut *tx).await?;}
 sqlx::query("INSERT INTO review_dispatch(user_id) VALUES($1) ON CONFLICT(user_id) DO UPDATE SET next_at=least(review_dispatch.next_at,now())").bind(i.user).execute(&mut *tx).await?;
 event(&mut tx,i.user,id,"created",json!({"draft":record.draft,"submitted":now,"ruleVersion":"criteria-v2","groupPending":prior.is_some()})).await?;
 let mut visible=json!(record);visible["groupPending"]=json!(prior.is_some());
 let response=json!({"record":visible});finish(&mut tx,i.user,key,&request,&response).await?;tx.commit().await?;Ok(envelope(response))
}
#[derive(Serialize,Deserialize)] struct Cursor {submitted:i64,id:Uuid}
#[derive(Deserialize,Default)] #[serde(deny_unknown_fields)] struct Filter {after:Option<String>,symbol:Option<String>,state:Option<String>,q:Option<String>,todo:Option<bool>,decided:Option<bool>}
async fn list(State(s):State<AppState>,i:Identity,Params(f):Params<Filter>)->Result<Json<Value>> {
 let cursor=if let Some(v)=f.after {if v.len()>200{return Err(ApiError::bad("invalid_cursor"))}Some(serde_json::from_slice::<Cursor>(&URL_SAFE_NO_PAD.decode(v).map_err(|_|ApiError::bad("invalid_cursor"))?)?)}else{None};
 if f.q.as_ref().is_some_and(|q|q.len()>200)||f.symbol.as_ref().is_some_and(|s|s.len()>40)||f.state.as_ref().is_some_and(|s|!matches!(s.as_str(),"waiting"|"needs_verification"|"realized"|"unrealized"|"observation"|"voided")){return Err(ApiError::bad("invalid_filter"))}
 let mut tx=s.personal(i.user).await?;
 let rows=sqlx::query("SELECT record,submitted,id,group_pending FROM review_records WHERE user_id=$1 AND ($2::bigint IS NULL OR (submitted,id)<($2,$3)) AND ($4::text IS NULL OR symbol=$4) AND ($5::text IS NULL OR CASE WHEN record->>'voided'='true' THEN 'voided' ELSE COALESCE(record#>>'{assessment,outcome}',CASE WHEN record#>>'{draft,rule,direction}'='observe' THEN 'observation' ELSE 'waiting' END) END=$5) AND ($6::text IS NULL OR strpos(lower(record#>>'{draft,text}'),lower($6))>0 OR strpos(lower(symbol),lower($6))>0) AND (NOT $7 OR (record->>'voided'='false' AND (record#>>'{draft,rule,direction}'<>'observe') AND (record#>>'{reflection,publishedAt}' IS NULL OR record#>>'{assessment,outcome}' IN ('waiting','needs_verification') OR group_pending))) AND (NOT $8 OR (record->>'voided'='false' AND record#>>'{reflection,publishedAt}' IS NOT NULL AND NOT group_pending AND COALESCE(record#>>'{assessment,outcome}','') NOT IN ('waiting','needs_verification'))) ORDER BY submitted DESC,id DESC LIMIT 51")
 .bind(i.user).bind(cursor.as_ref().map(|c|c.submitted)).bind(cursor.as_ref().map(|c|c.id)).bind(f.symbol).bind(f.state).bind(f.q).bind(f.todo.unwrap_or(false)).bind(f.decided.unwrap_or(false)).fetch_all(&mut *tx).await?;
 let mut next=None;let mut records=vec![];
 for row in rows.iter().take(50) {let mut record:Value=row.get("record");record["groupPending"]=json!(row.get::<bool,_>("group_pending"));records.push(record);}
 if rows.len()>50 {let r=&rows[49];next=Some(URL_SAFE_NO_PAD.encode(serde_json::to_vec(&Cursor{submitted:r.get("submitted"),id:r.get("id")})?));}
 tx.commit().await?;Ok(envelope(json!({"records":records,"next":next})))
}
async fn detail(State(s):State<AppState>,i:Identity,Route(id):Route<Uuid>)->Result<Json<Value>> {
 let mut tx=s.personal(i.user).await?;
 let row=sqlx::query("SELECT record,group_pending,assessment_revision,reflection_assessment_revision FROM review_records WHERE user_id=$1 AND id=$2").bind(i.user).bind(id).fetch_optional(&mut *tx).await?.ok_or_else(ApiError::missing)?;
 let mut record:Value=row.get("record");record["groupPending"]=json!(row.get::<bool,_>("group_pending"));
 // 有没有那张图（§4.3）。不把图本身塞进详情：它几百 KB，而详情是翻记录时
 // 一条一条要的；客户端看见 `hasShot` 再去取那一条路径，本地有缓存就根本不去。
 let has_shot:bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM review_shots WHERE user_id=$1 AND record_id=$2)").bind(i.user).bind(id).fetch_one(&mut *tx).await?;
 let result=json!({"record":record,"groupPending":row.get::<bool,_>("group_pending"),"assessmentRevision":row.get::<i64,_>("assessment_revision"),"reflectionAssessmentRevision":row.get::<Option<i64>,_>("reflection_assessment_revision"),"hasShot":has_shot});tx.commit().await?;Ok(envelope(result))
}
async fn reflection(State(s):State<AppState>,i:Identity,Route(id):Route<Uuid>,headers:HeaderMap,Payload(body):Payload<Value>)->Result<Json<Value>> {change(&s,i.user,id,key(&headers)?,"reflection",body).await}
async fn void_record(State(s):State<AppState>,i:Identity,Route(id):Route<Uuid>,headers:HeaderMap,Payload(body):Payload<Value>)->Result<Json<Value>> {change(&s,i.user,id,key(&headers)?,"void",body).await}
async fn group(State(s):State<AppState>,i:Identity,Route(id):Route<Uuid>,headers:HeaderMap,Payload(body):Payload<Value>)->Result<Json<Value>> {change(&s,i.user,id,key(&headers)?,"group",body).await}
#[derive(Deserialize)] #[serde(rename_all="camelCase",deny_unknown_fields)] struct GroupChange {expected_revision:i64,same_episode:bool}
async fn change(s:&AppState,owner:Uuid,id:Uuid,key:Uuid,kind:&str,body:Value)->Result<Json<Value>> {
 let request=json!({"id":id,"kind":kind,"body":body});let mut tx=s.personal(owner).await?;lock(&mut tx,owner).await?;
 if let Some(v)=cached(&mut tx,owner,key,&request).await? {return Ok(envelope(v))}
 let row=sqlx::query("SELECT record,group_pending,assessment_revision FROM review_records WHERE user_id=$1 AND id=$2 FOR UPDATE").bind(owner).bind(id).fetch_optional(&mut *tx).await?.ok_or_else(ApiError::missing)?;
 let mut record:NativeRecord=parse(row.get("record"))?;
 if body["expectedRevision"].as_i64()!=Some(record.revision){return Err(ApiError::conflict("record_revision_changed"))}
 if record.voided {return Err(ApiError::conflict("record_voided"))}
 match kind {
 "reflection"=>{let input:NativeReflectionInput=parse(body.clone())?;
  if input.reflection.note.len()>32_000||input.reflection.next_time.len()>32_000||(input.publish&&input.reflection.note.trim().is_empty()){return Err(ApiError::bad("invalid_reflection"))}
  if record.reflection.published_at.is_some() {record.reflection_history.push(record.reflection.clone());}
  record.reflection=input.reflection;record.reflection.revision=record.revision+1;record.reflection.published_at=input.publish.then(||Utc::now().timestamp_millis());
  sqlx::query("UPDATE review_records SET reflection_assessment_revision=$3 WHERE user_id=$1 AND id=$2").bind(owner).bind(id).bind(input.publish.then(||row.get::<i64,_>("assessment_revision"))).execute(&mut *tx).await?;
 },
 "void"=>{let _:NativeChange=parse(body.clone())?;record.voided=true;record.eligible=false;
  sqlx::query("UPDATE review_jobs SET finished=true,lease_id=NULL,lease_until=NULL WHERE user_id=$1 AND record_id=$2").bind(owner).bind(id).execute(&mut *tx).await?;
 },
 "group"=>{let v:GroupChange=parse(body.clone())?;let _=v.expected_revision;
  if !row.get::<bool,_>("group_pending"){return Err(ApiError::conflict("group_already_resolved"))}
  if !v.same_episode {
   let ep=Uuid::new_v4();sqlx::query("INSERT INTO review_episodes(user_id,id,symbol,market,anchor_at,end_at) VALUES($1,$2,$3,$4,$5,$6)").bind(owner).bind(ep).bind(&record.draft.range.symbol).bind(&record.draft.range.market).bind(record.submitted).bind(record.submitted+120*3_600_000).execute(&mut *tx).await?;
   sqlx::query("UPDATE review_records SET episode_id=$3 WHERE user_id=$1 AND id=$2").bind(owner).bind(id).bind(ep).execute(&mut *tx).await?;
  }
  sqlx::query("UPDATE review_records SET group_pending=false WHERE user_id=$1 AND id=$2").bind(owner).bind(id).execute(&mut *tx).await?;
 },_=>return Err(ApiError::bad("invalid_change"))}
 record.revision+=1;
 // The event is authoritative history; cap only the inline preview to bound mobile downloads.
 event(&mut tx,owner,id,kind,json!({"body":body,"revision":record.revision,"assessmentRevision":row.get::<i64,_>("assessment_revision")})).await?;
 if record.reflection_history.len()>5 {record.reflection_history.drain(..record.reflection_history.len()-5);}
 sqlx::query("UPDATE review_records SET record=$3,changed_at=now() WHERE user_id=$1 AND id=$2").bind(owner).bind(id).bind(json!(record)).execute(&mut *tx).await?;
 let mut visible=json!(record);visible["groupPending"]=json!(kind!="group"&&row.get::<bool,_>("group_pending"));
 let result=json!({"record":visible});finish(&mut tx,owner,key,&request,&result).await?;tx.commit().await?;Ok(envelope(result))
}
/// 「记一笔」自动存下来的那张图（§4.3）。
///
/// 只有两个动作：放上去、取回来。它不进 `review_operations` 那套幂等表，
/// 也不碰 `record.revision`——图是记录的附属物，不是对记录内容的一次修改，
/// 拿版本号去锁它只会让「补传一张图」被别的设备的一次复盘编辑挤掉。
/// 同一条记录重复上传就是覆盖（`ON CONFLICT DO UPDATE`），天然幂等。
#[derive(Deserialize)] #[serde(rename_all="camelCase",deny_unknown_fields)] struct ShotInput {image:String}
/// 收下来之前认一眼魔数：只收 PNG 与 JPEG。
///
/// 不是为了「格式好看」，是因为这几个字节最后会原样发回给客户端去渲染——
/// 让任意字节流冒充图片存进来，等于给自己开一条存任意二进制的通道。
fn shot_mime(bytes:&[u8])->Option<&'static str> {
 if bytes.starts_with(&[0x89,b'P',b'N',b'G',0x0d,0x0a,0x1a,0x0a]) {return Some("image/png")}
 if bytes.starts_with(&[0xff,0xd8,0xff]) {return Some("image/jpeg")}
 None
}
const SHOT_MAX_BYTES:usize=2*1024*1024;
async fn shot_put(State(s):State<AppState>,i:Identity,Route(id):Route<Uuid>,Payload(input):Payload<ShotInput>)->Result<Json<Value>> {
 let bytes=STANDARD.decode(input.image.as_bytes()).map_err(|_|ApiError::bad("invalid_shot"))?;
 if bytes.is_empty()||bytes.len()>SHOT_MAX_BYTES {return Err(ApiError::bad("shot_too_large"))}
 let mime=shot_mime(&bytes).ok_or_else(||ApiError::bad("invalid_shot"))?;
 let mut tx=s.personal(i.user).await?;
 // 记录得先在：没有这一条就没有「这一条的图」，外键也是这么定的，但先查一次
 // 才能回 404 而不是一个数据库约束错误。
 if sqlx::query_scalar::<_,Uuid>("SELECT id FROM review_records WHERE user_id=$1 AND id=$2").bind(i.user).bind(id).fetch_optional(&mut *tx).await?.is_none() {return Err(ApiError::missing())}
 sqlx::query("INSERT INTO review_shots(user_id,record_id,mime,bytes) VALUES($1,$2,$3,$4) ON CONFLICT(user_id,record_id) DO UPDATE SET mime=EXCLUDED.mime,bytes=EXCLUDED.bytes,created_at=now()")
  .bind(i.user).bind(id).bind(mime).bind(&bytes).execute(&mut *tx).await?;
 tx.commit().await?;Ok(envelope(json!({"ok":true})))
}
async fn shot_get(State(s):State<AppState>,i:Identity,Route(id):Route<Uuid>)->Result<Json<Value>> {
 let mut tx=s.personal(i.user).await?;
 let row=sqlx::query("SELECT mime,bytes FROM review_shots WHERE user_id=$1 AND record_id=$2").bind(i.user).bind(id).fetch_optional(&mut *tx).await?.ok_or_else(ApiError::missing)?;
 let bytes:Vec<u8>=row.get("bytes");let mime:String=row.get("mime");
 tx.commit().await?;Ok(envelope(json!({"image":STANDARD.encode(bytes),"mime":mime})))
}
/// 一条记录的全部修订（P3.7）：`review_events` 按时间排好原样给出。
///
/// 记录里内联的 `reflectionHistory` 只留最近五版（给列表省流量），权威历史一直是
/// 事件表——每一次记下、判定、复盘、作废、分组都各写了一条。这里只读，没有
/// 「恢复到这一版」：旧版本只能看，不能覆盖回当前记录。
///
/// 先确认这条记录是这个人的（查不到就 404，和详情同一个口径），再按 user_id 取事件；
/// 两道都在 `personal` 事务里，RLS 兜底。
async fn revisions(State(s):State<AppState>,i:Identity,Route(id):Route<Uuid>)->Result<Json<Value>> {
 let mut tx=s.personal(i.user).await?;
 if sqlx::query_scalar::<_,Uuid>("SELECT id FROM review_records WHERE user_id=$1 AND id=$2").bind(i.user).bind(id).fetch_optional(&mut *tx).await?.is_none() {return Err(ApiError::missing())}
 let rows=sqlx::query("SELECT kind,body,(extract(epoch from created_at)*1000)::bigint AS at FROM review_events WHERE user_id=$1 AND record_id=$2 ORDER BY created_at,id").bind(i.user).bind(id).fetch_all(&mut *tx).await?;
 let items:Vec<Value>=rows.iter().map(|r|json!({"kind":r.get::<String,_>("kind"),"at":r.get::<i64,_>("at"),"body":r.get::<Value,_>("body")})).collect();
 tx.commit().await?;Ok(envelope(json!({"revisions":items})))
}
/// 补图（P3.7）。
///
/// 和「记一笔」那张自动截图（`shot_put`）一样只认 PNG / JPEG 魔数，一样不碰
/// `record.revision`：图是记录的附属物，不是对记录内容的一次修改。
///
/// 幂等靠客户端给的 `id`：同一个 id 再传一次，库里已经有了就原样回 `ok`，
/// 不算第四张——网络抖一下重发，不能把人的额度吃掉。
pub const ATTACHMENT_MAX_BYTES:usize=5*1024*1024;
pub const ATTACHMENTS_PER_RECORD:i64=3;
const ATTACHMENT_BODY_LIMIT:usize=7*1024*1024;
#[derive(Deserialize)] #[serde(rename_all="camelCase",deny_unknown_fields)] struct AttachmentInput {id:Uuid,record_id:Uuid,image:String}
async fn attachment_put(State(s):State<AppState>,i:Identity,Payload(input):Payload<AttachmentInput>)->Result<Json<Value>> {
 let bytes=STANDARD.decode(input.image.as_bytes()).map_err(|_|ApiError::bad("invalid_attachment"))?;
 if bytes.is_empty() {return Err(ApiError::bad("invalid_attachment"))}
 if bytes.len()>ATTACHMENT_MAX_BYTES {return Err(ApiError::bad("attachment_too_large"))}
 let mime=shot_mime(&bytes).ok_or_else(||ApiError::bad("invalid_attachment"))?;
 let mut tx=s.personal(i.user).await?;lock(&mut tx,i.user).await?;
 if sqlx::query_scalar::<_,Uuid>("SELECT id FROM review_records WHERE user_id=$1 AND id=$2").bind(i.user).bind(input.record_id).fetch_optional(&mut *tx).await?.is_none() {return Err(ApiError::missing())}
 if let Some(owner)=sqlx::query_scalar::<_,Uuid>("SELECT record_id FROM review_attachments WHERE user_id=$1 AND id=$2").bind(i.user).bind(input.id).fetch_optional(&mut *tx).await? {
  // 同一个 id 挂在另一条记录上：这不是重发，是客户端把 id 用串了。
  if owner!=input.record_id {return Err(ApiError::conflict("attachment_identity_conflict"))}
  tx.commit().await?;return Ok(envelope(json!({"ok":true,"id":input.id})))
 }
 let count:i64=sqlx::query_scalar("SELECT count(*) FROM review_attachments WHERE user_id=$1 AND record_id=$2").bind(i.user).bind(input.record_id).fetch_one(&mut *tx).await?;
 if count>=ATTACHMENTS_PER_RECORD {return Err(ApiError::conflict("attachment_limit"))}
 sqlx::query("INSERT INTO review_attachments(user_id,id,record_id,mime,bytes) VALUES($1,$2,$3,$4,$5)").bind(i.user).bind(input.id).bind(input.record_id).bind(mime).bind(&bytes).execute(&mut *tx).await?;
 tx.commit().await?;Ok(envelope(json!({"ok":true,"id":input.id})))
}
/// 这一条记录挂了哪几张补图：只给元数据，图本身按 id 一张一张取。
async fn attachments(State(s):State<AppState>,i:Identity,Route(id):Route<Uuid>)->Result<Json<Value>> {
 let mut tx=s.personal(i.user).await?;
 if sqlx::query_scalar::<_,Uuid>("SELECT id FROM review_records WHERE user_id=$1 AND id=$2").bind(i.user).bind(id).fetch_optional(&mut *tx).await?.is_none() {return Err(ApiError::missing())}
 let rows=sqlx::query("SELECT id,mime,octet_length(bytes) AS size,(extract(epoch from created_at)*1000)::bigint AS at FROM review_attachments WHERE user_id=$1 AND record_id=$2 ORDER BY created_at,id").bind(i.user).bind(id).fetch_all(&mut *tx).await?;
 let items:Vec<Value>=rows.iter().map(|r|json!({"id":r.get::<Uuid,_>("id"),"recordId":id,"mime":r.get::<String,_>("mime"),"size":r.get::<i32,_>("size"),"createdAt":r.get::<i64,_>("at")})).collect();
 tx.commit().await?;Ok(envelope(json!({"items":items})))
}
async fn attachment_get(State(s):State<AppState>,i:Identity,Route(id):Route<Uuid>)->Result<Json<Value>> {
 let mut tx=s.personal(i.user).await?;
 let row=sqlx::query("SELECT mime,bytes FROM review_attachments WHERE user_id=$1 AND id=$2").bind(i.user).bind(id).fetch_optional(&mut *tx).await?.ok_or_else(ApiError::missing)?;
 let bytes:Vec<u8>=row.get("bytes");let mime:String=row.get("mime");
 tx.commit().await?;Ok(envelope(json!({"image":STANDARD.encode(bytes),"mime":mime})))
}
/// 删一张补图。已经没了也回 `ok`：删除是幂等的，重发不该变成一个错误。
async fn attachment_delete(State(s):State<AppState>,i:Identity,Route(id):Route<Uuid>)->Result<Json<Value>> {
 let mut tx=s.personal(i.user).await?;
 let gone=sqlx::query("DELETE FROM review_attachments WHERE user_id=$1 AND id=$2").bind(i.user).bind(id).execute(&mut *tx).await?.rows_affected();
 tx.commit().await?;Ok(envelope(json!({"ok":true,"deleted":gone>0})))
}
pub fn signature(d:&NativeDraft)->String {
 // Never combine different target/stop/horizon or price confirmation policies into one win rate.
 digest(serde_json::to_vec(&json!({"version":d.rule.version,"direction":d.rule.direction,"confirmation":d.rule.confirmation,"reference":d.rule.reference,"target":d.rule.target,"invalidation":d.rule.invalidation,"expires":d.rule.expires,"market":d.range.market,"symbol":d.range.symbol,"interval":d.range.interval,"origin":d.origin})).expect("finite validated rule"))
}
/// 可比统计的身份。冻结的单笔规则身份（上面的 `signature`）回答的是「这条记录
/// 当时定的是什么」，它必须带绝对价格和绝对到期时刻；而「我这一路打法做得怎么样」
/// 要的是同一类样本放在一起数。绝对 expires 让同一套做法每提交一次就碎成一组，于是
/// 满屏 n=1 的 0%／100%。这里换成相对幅度与观察时长的档位：档位是固定的，不给用户选，
/// 也不跨方向、跨确认方式、跨品种周期混。
const MOVE_TIERS:[f64;8]=[0.005,0.01,0.02,0.03,0.05,0.08,0.13,0.21];
const MOVE_LABELS:[&str;9]=["≤ 0.5%","≤ 1%","≤ 2%","≤ 3%","≤ 5%","≤ 8%","≤ 13%","≤ 21%","> 21%"];
const SPAN_TIERS:[i64;7]=[3_600_000,14_400_000,43_200_000,86_400_000,259_200_000,604_800_000,2_592_000_000];
const SPAN_LABELS:[&str;8]=["1小时内","4小时内","12小时内","1天内","3天内","1周内","1个月内","1个月以上"];
fn move_tier(reference:f64,price:f64)->usize {
 let distance=((price-reference)/reference).abs();
 if !distance.is_finite() {return MOVE_TIERS.len()}
 // 浮点：(102-100)/100 算出来比 0.02 大一点点，不能因此掉到下一档。
 MOVE_TIERS.iter().position(|t|distance<=t*(1.0+1e-9)).unwrap_or(MOVE_TIERS.len())
}
fn span_tier(span:i64)->usize {SPAN_TIERS.iter().position(|t|span<=*t).unwrap_or(SPAN_TIERS.len())}
pub fn comparable_signature(d:&NativeDraft)->String {
 digest(serde_json::to_vec(&json!({"version":d.rule.version,"direction":d.rule.direction,"confirmation":d.rule.confirmation,"market":d.range.market,"symbol":d.range.symbol,"interval":d.range.interval,"targetTier":move_tier(d.rule.reference,d.rule.target),"invalidationTier":move_tier(d.rule.reference,d.rule.invalidation),"spanTier":span_tier(d.rule.expires-d.created)})).expect("finite validated rule"))
}
fn comparable_title(d:&NativeDraft)->String {
 format!("{} · {} · {} · 目标{} · 止损{} · {}",d.range.symbol,
  match d.rule.direction.as_str(){"long"=>"做多","short"=>"做空",_=>"只观察"},
  if d.rule.confirmation=="bar_close"{"收盘"}else{"触价"},
  MOVE_LABELS[move_tier(d.rule.reference,d.rule.target)],MOVE_LABELS[move_tier(d.rule.reference,d.rule.invalidation)],
  SPAN_LABELS[span_tier(d.rule.expires-d.created)])
}
async fn stats(State(s):State<AppState>,i:Identity)->Result<Json<Value>> {
 let mut tx=s.personal(i.user).await?;
 // Statistics only needs the draft plus five scalars. Selecting the whole
 // record shipped every reflection and its five-deep history out of Postgres
 // and through serde on every call; the projection keeps the payload to what
 // the summary actually reads.
 let rows=sqlx::query("SELECT record->'draft' AS draft,(record->>'serverId')::uuid AS server_id,(record->>'submitted')::bigint AS submitted,COALESCE(record->'assessment'->>'outcome','pending') AS state,(record->>'eligible')::bool AS eligible,(record->>'voided')::bool AS voided,episode_id,group_pending FROM review_records WHERE user_id=$1 ORDER BY submitted,id").bind(i.user).fetch_all(&mut *tx).await?;
 let mut samples=vec![];let mut comparable=vec![];let mut labels=BTreeMap::new();let mut comparable_labels=BTreeMap::new();
 for row in rows {let d:NativeDraft=parse(row.get("draft"))?;let sig=signature(&d);let relative=comparable_signature(&d);
  labels.entry(sig.clone()).or_insert_with(||format!("{} · {} · {}",d.range.symbol,match d.origin.as_str(){"chart_first"=>"图在先","thought_first"=>"想法在先","interwoven"=>"两者交织",_=>"不确定"},if d.rule.confirmation=="bar_close"{"收盘"}else{"触价"}));
  comparable_labels.entry(relative.clone()).or_insert_with(||comparable_title(&d));
  let sample=statistics::Sample{call_id:row.get("server_id"),claim_no:0,submitted_at:core(domain::time(row.get("submitted")))?,episode_id:Some(row.get("episode_id")),group_pending:row.get("group_pending"),signature:sig,state:row.get("state"),eligible:row.get("eligible"),voided:row.get("voided")};
  comparable.push(statistics::Sample{signature:relative,..sample.clone()});samples.push(sample);
 }
 let proof=statistics::summarize(&samples,0);let comparable_proof=statistics::summarize(&comparable,0);
 // 分组只有一份形状；可比的那一份多带一个领域层算好的「样本够不够」，
 // 客户端才能在 n 太小的时候不把单样本的 100% 当结论展示。
 let shape=|source:&Value,titles:&BTreeMap<String,String>,verdict:bool|->Vec<Value>{source["compatible_groups"].as_object().into_iter().flatten().map(|(id,v)|{
  let mut group=json!({"id":id,"title":titles[id],"total":v["denominator"],"correct":v["numerator"]});
  if verdict {group["verdictStatus"]=v["verdict_status"].clone();}group
 }).collect()};
 let groups=shape(&proof,&labels,false);let comparable_groups=shape(&comparable_proof,&comparable_labels,true);
 tx.commit().await?;Ok(envelope(json!({"groups":groups,"proof":proof,"ruleVersion":"criteria-v2","grouping":"confirmed_anchored_episode_exact_rule","asOf":Utc::now().timestamp_millis(),
  "comparableGroups":comparable_groups,"comparableProof":comparable_proof,"comparableGrouping":"confirmed_anchored_episode_relative_rule"})))
}
