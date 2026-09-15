//! Personal changes only. Market candles never enter this protocol.
use crate::{AppState,auth::Identity,crypto::digest,envelope,error::{ApiError,Result}};
use axum::{Router,Json,extract::{State,Query},routing::{get,post}};
use serde::{Deserialize,Serialize};
use serde_json::{Value,json};
use sqlx::Row;
use std::collections::BTreeMap;
use uuid::Uuid;
use chrono::Utc;

#[derive(Deserialize,Serialize,Clone)]
#[serde(rename_all="camelCase",deny_unknown_fields)]
pub struct Operation {
 pub id:Uuid,pub collection:String,pub object_id:String,pub device_id:Uuid,
 pub base_revision:i64,pub generation:i64,pub timestamp:i64,pub logical:u64,
 pub action:String,#[serde(default)] pub fields:BTreeMap<String,Value>,pub import_batch:Option<Uuid>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Push {operations:Vec<Operation>}
#[derive(Deserialize,Default)]
#[serde(rename_all="camelCase",deny_unknown_fields)]
struct Scope {collection:Option<String>,prefix:Option<String>,after:Option<String>,cursor:Option<i64>}
#[derive(Serialize,Deserialize,Clone,Default)]
#[serde(rename_all="camelCase")]
struct Stamp {revision:i64,timestamp:i64,logical:u64,device_id:String,operation_id:String}
#[derive(Serialize,Deserialize,Clone)]
#[serde(rename_all="camelCase")]
pub struct Object {
 pub collection:String,pub id:String,pub body:BTreeMap<String,Value>,
 pub fields:BTreeMap<String,Value>,pub revision:i64,pub deleted:bool,pub generation:i64,
}
const COLLECTIONS:[&str;5]=["settings","drawingPreferences","drawings","favorites","groups"];
fn collection(v:&str)->Result<()> {if !COLLECTIONS.contains(&v){Err(ApiError::bad("invalid_collection"))}else{Ok(())}}
fn valid_field(c:&str,path:&str)->bool {
 if path.is_empty() || path.len()>160 || path.split('/').any(|p|p.is_empty()||p==".."||p.starts_with('_')) {return false}
 let root=path.split('/').next().unwrap_or_default();
 match c {
 "settings"=>["overlays","subs","subHeights","subHeightOverrides","params","indicatorColors","hiddenOutputs","rsiRange","portraitHeight","quickIntervals","theme","ambientTheme","styleID","redUp","priceMode","timeZone","magnet","countdown","lastLine","sinceChange","showDrawings","candleKind","gridChoice","bodyChoice","viewAnchor","priceBias","dataDisplay","crossPrice","allowMainInversion","allowSubInversion","adaptiveIndicators","compactValues","changeBasis"].contains(&root),
 "drawingPreferences"=>["favorites","magnet","continuous","styles"].contains(&root),
 "drawings"=>["kind","symbol","market","venue","anchors","color","lineWidth","dash","filled","levels","locked","hidden","created"].contains(&root),
 "favorites"=>["symbol","market","venue","groupId","order","pinned","alerts"].contains(&root),
 "groups"=>["name","order","members"].contains(&root),_=>false
 }
}
impl Operation {
 pub fn validate(&self)->Result<()> {
  collection(&self.collection)?;
  if self.object_id.is_empty()||self.object_id.len()>180||self.base_revision<0||self.generation<0||self.logical>i64::MAX as u64||self.timestamp<0
   || !matches!(self.action.as_str(),"patch"|"delete"|"restore") || self.fields.len()>256
   || self.fields.iter().any(|(k,v)|!valid_field(&self.collection,k)||!crate::sync_validation::field(&self.collection,k,v))
   || self.fields.values().any(|v|serde_json::to_vec(v).map_or(true,|s|s.len()>64_000)) {return Err(ApiError::bad("invalid_operation"))}
  Ok(())
 }
}
pub fn merge(mut object:Object,op:&Operation,now:i64)->Result<Object> {
 op.validate()?;
 if op.base_revision>object.revision || op.generation!=object.generation {return Err(ApiError::conflict("resync_required"))}
 if op.action=="restore" {
  if !object.deleted||op.base_revision!=object.revision {return Err(ApiError::conflict("resync_required"))}
  object.deleted=false;object.generation+=1;
 } else if op.action=="delete" {object.deleted=true;}
 else if object.deleted {return Ok(object)}
 let next=object.revision+1;
 if !object.deleted {
  for (path,value) in &op.fields {
   let previous=object.fields.get(path).and_then(|s|serde_json::from_value::<Stamp>(s.clone()).ok());
   if op.import_batch.is_some()&&object.body.contains_key(path) {continue}
   let stamp=Stamp{revision:next,timestamp:op.timestamp.min(now+300_000),logical:op.logical,device_id:op.device_id.to_string(),operation_id:op.id.to_string()};
   let accept=previous.as_ref().is_none_or(|old|op.base_revision>=old.revision || (stamp.timestamp,stamp.logical,&stamp.device_id,&stamp.operation_id)>(old.timestamp,old.logical,&old.device_id,&old.operation_id));
   if accept {object.body.insert(path.clone(),value.clone());object.fields.insert(path.clone(),json!(stamp));}
  }
 }
 // Dependent settings are updated and validated atomically.
 if let Some(v)=object.body.get("rsiRange") {
  if !v.as_array().is_some_and(|a|a.len()==2&&a[0].as_f64().is_some_and(|lo|lo>=0.0&&a[1].as_f64().is_some_and(|hi|hi>lo&&hi<=100.0))) {return Err(ApiError::bad("invalid_rsi_range"))}
 }
 if let Some(v)=object.body.get("lineWidth") {if !v.as_f64().is_some_and(|n|n>0.0&&n<=12.0){return Err(ApiError::bad("invalid_line_width"))}}
 crate::sync_validation::object(&object)?;
 object.revision=next;Ok(object)
}
pub fn routes()->Router<AppState> {
 Router::new().route("/v1/sync/bootstrap",get(bootstrap)).route("/v1/sync/changes",get(changes)).route("/v1/sync/operations",post(push))
}
fn object(r:&sqlx::postgres::PgRow)->Result<Object> {
 Ok(Object{collection:r.get("collection"),id:r.get("id"),body:serde_json::from_value(r.get("body"))?,fields:serde_json::from_value(r.get("fields"))?,revision:r.get("revision"),deleted:r.get("deleted"),generation:r.get("generation")})
}
async fn lock(tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,owner:Uuid)->Result<()> {
 sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))").bind(format!("sync:{owner}")).execute(&mut **tx).await?;Ok(())
}
async fn push(State(s):State<AppState>,i:Identity,Json(v):Json<Push>)->Result<Json<Value>> {
 if v.operations.is_empty()||v.operations.len()>100{return Err(ApiError::bad("invalid_batch"))}
 let mut tx=s.personal(i.user).await?;lock(&mut tx,i.user).await?;
 let device:Uuid=sqlx::query_scalar("SELECT device_id FROM account_sessions WHERE id=$1 AND user_id=$2 AND revoked_at IS NULL").bind(i.session).bind(i.user).fetch_optional(&mut *tx).await?.ok_or_else(ApiError::unauthorized)?;
 let mut results=vec![];
 for op in v.operations {
  op.validate()?;if op.device_id!=device{return Err(ApiError::bad("invalid_device"))}
  let hash=digest(serde_json::to_vec(&op)?);
  if let Some(r)=sqlx::query("SELECT digest,result FROM sync_operations WHERE user_id=$1 AND id=$2").bind(i.user).bind(op.id).fetch_optional(&mut *tx).await? {
   if r.get::<String,_>("digest")!=hash{return Err(ApiError::conflict("idempotency_mismatch"))}
   results.push(r.get::<Value,_>("result"));continue
  }
  if let Some(batch)=op.import_batch {
   sqlx::query("INSERT INTO sync_claims(batch_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING").bind(batch).bind(i.user).execute(&mut *tx).await?;
   let claimed:bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM sync_claims WHERE batch_id=$1 AND user_id=$2)").bind(batch).bind(i.user).fetch_one(&mut *tx).await?;
   if !claimed{return Err(ApiError::conflict("batch_already_claimed"))}
  }
  let row=sqlx::query("SELECT * FROM sync_objects WHERE user_id=$1 AND collection=$2 AND id=$3 FOR UPDATE").bind(i.user).bind(&op.collection).bind(&op.object_id).fetch_optional(&mut *tx).await?;
  let old=match row {Some(ref r)=>object(r)?,None=>Object{collection:op.collection.clone(),id:op.object_id.clone(),body:BTreeMap::new(),fields:BTreeMap::new(),revision:0,deleted:false,generation:0}};
  let next=merge(old.clone(),&op,Utc::now().timestamp_millis())?;
  if row.is_some()&&next.revision!=old.revision {
   sqlx::query("INSERT INTO sync_snapshots(user_id,collection,object_id,snapshot) VALUES($1,$2,$3,$4)").bind(i.user).bind(&op.collection).bind(&op.object_id).bind(json!(old)).execute(&mut *tx).await?;
  }
  sqlx::query("INSERT INTO sync_objects(user_id,collection,id,body,fields,revision,deleted,generation) VALUES($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT(user_id,collection,id) DO UPDATE SET body=excluded.body,fields=excluded.fields,revision=excluded.revision,deleted=excluded.deleted,generation=excluded.generation,changed_at=now()")
   .bind(i.user).bind(&next.collection).bind(&next.id).bind(json!(next.body)).bind(json!(next.fields)).bind(next.revision).bind(next.deleted).bind(next.generation).execute(&mut *tx).await?;
  let cursor:i64=sqlx::query_scalar("INSERT INTO sync_changes(user_id,collection,object_id,revision,deleted) VALUES($1,$2,$3,$4,$5) RETURNING sequence").bind(i.user).bind(&next.collection).bind(&next.id).bind(next.revision).bind(next.deleted).fetch_one(&mut *tx).await?;
  let result=json!({"operationId":op.id,"object":next,"cursor":cursor});
  sqlx::query("INSERT INTO sync_operations(user_id,id,digest,result) VALUES($1,$2,$3,$4)").bind(i.user).bind(op.id).bind(hash).bind(&result).execute(&mut *tx).await?;results.push(result);
 }
 tx.commit().await?;Ok(envelope(json!({"results":results,"serverTime":Utc::now().timestamp_millis()})))
}
async fn bootstrap(State(s):State<AppState>,i:Identity,Query(v):Query<Scope>)->Result<Json<Value>> {
 if let Some(c)=&v.collection{collection(c)?}
 // Default bootstrap contains only small personal settings. Histories require an explicit scope.
 let c=v.collection.unwrap_or_else(||"settings".into());
 let mut tx=s.personal(i.user).await?;lock(&mut tx,i.user).await?;
 let rows=sqlx::query("SELECT * FROM sync_objects WHERE user_id=$1 AND collection=$2 AND ($3::text IS NULL OR starts_with(id,$3)) AND ($4::text IS NULL OR id>$4) ORDER BY id LIMIT 101")
  .bind(i.user).bind(c).bind(v.prefix).bind(v.after).fetch_all(&mut *tx).await?;
 let more=rows.len()>100;let objects=rows.iter().take(100).map(object).collect::<Result<Vec<_>>>()?;
 let cursor:i64=sqlx::query_scalar("SELECT COALESCE(max(sequence),0) FROM sync_changes WHERE user_id=$1").bind(i.user).fetch_one(&mut *tx).await?;
 let next=if more {objects.last().map(|o|o.id.clone())}else{None};tx.commit().await?;
 Ok(envelope(json!({"objects":objects,"next":next,"cursor":cursor,"serverTime":Utc::now().timestamp_millis()})))
}
async fn changes(State(s):State<AppState>,i:Identity,Query(v):Query<Scope>)->Result<Json<Value>> {
 if let Some(c)=&v.collection{collection(c)?}
 let cursor=v.cursor.unwrap_or(0);if cursor<0{return Err(ApiError::bad("invalid_cursor"))}
 let mut tx=s.personal(i.user).await?;lock(&mut tx,i.user).await?;
 let rows=sqlx::query("SELECT sequence,collection,object_id,revision,deleted FROM sync_changes WHERE user_id=$1 AND sequence>$2 ORDER BY sequence LIMIT 201").bind(i.user).bind(cursor).fetch_all(&mut *tx).await?;
 let has_more=rows.len()>200;let next=rows.iter().take(200).last().map(|r|r.get::<i64,_>("sequence")).unwrap_or(cursor);
 let mut items=vec![];let mut invalidations=vec![];
 for r in rows.iter().take(200) {
  let c:String=r.get("collection");let id:String=r.get("object_id");
  let subscribed=v.collection.as_ref().is_some_and(|want|want==&c)&&v.prefix.as_ref().is_none_or(|p|id.starts_with(p));
  if subscribed {
   let current=sqlx::query("SELECT * FROM sync_objects WHERE user_id=$1 AND collection=$2 AND id=$3").bind(i.user).bind(&c).bind(&id).fetch_one(&mut *tx).await?;
   items.push(object(&current)?);
  }else{invalidations.push(json!({"collection":c,"id":id,"deleted":r.get::<bool,_>("deleted"),"revision":r.get::<i64,_>("revision")}));}
 }
 tx.commit().await?;Ok(envelope(json!({"objects":items,"invalidations":invalidations,"cursor":next,"hasMore":has_more,"serverTime":Utc::now().timestamp_millis()})))
}
