use crate::review_domain as domain;
// Native records are authoritative here; charts remain in the existing app/market stack.
use crate::{AppState,auth::Identity,crypto::digest,envelope,error::{ApiError,Result}};
use axum::{Router,Json,extract::{State,Path,Query},routing::{get,post},http::HeaderMap};
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
 .route("/v1/native-review/records/{id}/reflections",post(reflection))
 .route("/v1/native-review/records/{id}/void",post(void_record))
 .route("/v1/native-review/records/{id}/group",post(group))
 .route("/v1/native-review/statistics",get(stats))
}
pub fn parse<T:serde::de::DeserializeOwned>(value:Value)->Result<T> {Ok(serde_json::from_value(value)?)}
pub fn core<T>(value:scorebook_core::error::Result<T>)->Result<T> {value.map_err(|_|ApiError::bad("invalid_review_evidence"))}
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
 }
 if let Some(encoded)=&d.drawing_snapshot {
  let bytes=STANDARD.decode(encoded).map_err(|_|ApiError::bad("invalid_drawing_snapshot"))?;
  let _:Value=serde_json::from_slice(&bytes)?;
 }
 Ok(())
}
async fn create(State(s):State<AppState>,i:Identity,headers:HeaderMap,Json(input):Json<NativeDraft>)->Result<Json<Value>> {
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
#[derive(Deserialize,Default)] #[serde(deny_unknown_fields)] struct Filter {after:Option<String>,symbol:Option<String>,state:Option<String>,q:Option<String>,todo:Option<bool>}
async fn list(State(s):State<AppState>,i:Identity,Query(f):Query<Filter>)->Result<Json<Value>> {
 let cursor=if let Some(v)=f.after {if v.len()>200{return Err(ApiError::bad("invalid_cursor"))}Some(serde_json::from_slice::<Cursor>(&URL_SAFE_NO_PAD.decode(v).map_err(|_|ApiError::bad("invalid_cursor"))?)?)}else{None};
 if f.q.as_ref().is_some_and(|q|q.len()>200)||f.symbol.as_ref().is_some_and(|s|s.len()>40)||f.state.as_ref().is_some_and(|s|!matches!(s.as_str(),"waiting"|"needs_verification"|"realized"|"unrealized"|"observation"|"voided")){return Err(ApiError::bad("invalid_filter"))}
 let mut tx=s.personal(i.user).await?;
 let rows=sqlx::query("SELECT record,submitted,id,group_pending FROM review_records WHERE user_id=$1 AND ($2::bigint IS NULL OR (submitted,id)<($2,$3)) AND ($4::text IS NULL OR symbol=$4) AND ($5::text IS NULL OR CASE WHEN record->>'voided'='true' THEN 'voided' ELSE COALESCE(record#>>'{assessment,outcome}',CASE WHEN record#>>'{draft,rule,direction}'='observe' THEN 'observation' ELSE 'waiting' END) END=$5) AND ($6::text IS NULL OR strpos(lower(record#>>'{draft,text}'),lower($6))>0 OR strpos(lower(symbol),lower($6))>0) AND (NOT $7 OR (record->>'voided'='false' AND (record#>>'{draft,rule,direction}'<>'observe') AND (record#>>'{reflection,publishedAt}' IS NULL OR record#>>'{assessment,outcome}' IN ('waiting','needs_verification') OR group_pending))) ORDER BY submitted DESC,id DESC LIMIT 51")
 .bind(i.user).bind(cursor.as_ref().map(|c|c.submitted)).bind(cursor.as_ref().map(|c|c.id)).bind(f.symbol).bind(f.state).bind(f.q).bind(f.todo.unwrap_or(false)).fetch_all(&mut *tx).await?;
 let mut next=None;let mut records=vec![];
 for row in rows.iter().take(50) {let mut record:Value=row.get("record");record["groupPending"]=json!(row.get::<bool,_>("group_pending"));records.push(record);}
 if rows.len()>50 {let r=&rows[49];next=Some(URL_SAFE_NO_PAD.encode(serde_json::to_vec(&Cursor{submitted:r.get("submitted"),id:r.get("id")})?));}
 tx.commit().await?;Ok(envelope(json!({"records":records,"next":next})))
}
async fn detail(State(s):State<AppState>,i:Identity,Path(id):Path<Uuid>)->Result<Json<Value>> {
 let mut tx=s.personal(i.user).await?;
 let row=sqlx::query("SELECT record,group_pending,assessment_revision,reflection_assessment_revision FROM review_records WHERE user_id=$1 AND id=$2").bind(i.user).bind(id).fetch_optional(&mut *tx).await?.ok_or_else(ApiError::missing)?;
 let mut record:Value=row.get("record");record["groupPending"]=json!(row.get::<bool,_>("group_pending"));
 let result=json!({"record":record,"groupPending":row.get::<bool,_>("group_pending"),"assessmentRevision":row.get::<i64,_>("assessment_revision"),"reflectionAssessmentRevision":row.get::<Option<i64>,_>("reflection_assessment_revision")});tx.commit().await?;Ok(envelope(result))
}
async fn reflection(State(s):State<AppState>,i:Identity,Path(id):Path<Uuid>,headers:HeaderMap,Json(body):Json<Value>)->Result<Json<Value>> {change(&s,i.user,id,key(&headers)?,"reflection",body).await}
async fn void_record(State(s):State<AppState>,i:Identity,Path(id):Path<Uuid>,headers:HeaderMap,Json(body):Json<Value>)->Result<Json<Value>> {change(&s,i.user,id,key(&headers)?,"void",body).await}
async fn group(State(s):State<AppState>,i:Identity,Path(id):Path<Uuid>,headers:HeaderMap,Json(body):Json<Value>)->Result<Json<Value>> {change(&s,i.user,id,key(&headers)?,"group",body).await}
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
pub fn signature(d:&NativeDraft)->String {
 // Never combine different target/stop/horizon or price confirmation policies into one win rate.
 digest(serde_json::to_vec(&json!({"version":d.rule.version,"direction":d.rule.direction,"confirmation":d.rule.confirmation,"reference":d.rule.reference,"target":d.rule.target,"invalidation":d.rule.invalidation,"expires":d.rule.expires,"market":d.range.market,"symbol":d.range.symbol,"interval":d.range.interval,"origin":d.origin})).expect("finite validated rule"))
}
async fn stats(State(s):State<AppState>,i:Identity)->Result<Json<Value>> {
 let mut tx=s.personal(i.user).await?;
 // Statistics only needs the draft plus five scalars. Selecting the whole
 // record shipped every reflection and its five-deep history out of Postgres
 // and through serde on every call; the projection keeps the payload to what
 // the summary actually reads.
 let rows=sqlx::query("SELECT record->'draft' AS draft,(record->>'serverId')::uuid AS server_id,(record->>'submitted')::bigint AS submitted,COALESCE(record->'assessment'->>'outcome','pending') AS state,(record->>'eligible')::bool AS eligible,(record->>'voided')::bool AS voided,episode_id,group_pending FROM review_records WHERE user_id=$1 ORDER BY submitted,id").bind(i.user).fetch_all(&mut *tx).await?;
 let mut samples=vec![];let mut labels=BTreeMap::new();
 for row in rows {let d:NativeDraft=parse(row.get("draft"))?;let sig=signature(&d);
  labels.entry(sig.clone()).or_insert_with(||format!("{} · {} · {}",d.range.symbol,match d.origin.as_str(){"chart_first"=>"图在先","thought_first"=>"想法在先","interwoven"=>"两者交织",_=>"不确定"},if d.rule.confirmation=="bar_close"{"收盘"}else{"触价"}));
  samples.push(statistics::Sample{call_id:row.get("server_id"),claim_no:0,submitted_at:core(domain::time(row.get("submitted")))?,episode_id:Some(row.get("episode_id")),group_pending:row.get("group_pending"),signature:sig,state:row.get("state"),eligible:row.get("eligible"),voided:row.get("voided")});
 }
 let proof=statistics::summarize(&samples,0);
 let groups:Vec<Value>=proof["compatible_groups"].as_object().into_iter().flatten().map(|(id,v)|json!({"id":id,"title":labels[id],"total":v["denominator"],"correct":v["numerator"]})).collect();
 tx.commit().await?;Ok(envelope(json!({"groups":groups,"proof":proof,"ruleVersion":"criteria-v2","grouping":"confirmed_anchored_episode_exact_rule","asOf":Utc::now().timestamp_millis()})))
}
