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
// One enumerable allowlist per collection, mirroring what iOS actually sends.
//
// `settings` is not a hand-copy any more: it must equal, name for name, the `wireKeys` array
// in `contract/settings-fields.json`, which `make sync-contract` generates from the single
// table on the client (`PrefsFieldPlan.table`, Kanpan/Kanpan/Settings/Model/PrefsFieldPlan.swift).
// `the_allowlist_is_what_ios_sends` reads that file with `include_str!` and fails loudly on any
// drift, so the two sides can no longer disagree in silence — which is exactly how commit
// a161bb0 happened: this list was nineteen names short, and because an operation carrying an
// unknown field used to be refused whole, that account never synced anything again.
//
// A name here still needs a value rule in `sync_validation::field`, or the field is a poison
// pill: the `_=>false` fallthrough 400s the whole operation. `every_wire_key_has_a_value_rule`
// is the guard for that half.
//
// A slice rather than `[&str;N]`: adding a field should not also mean editing a length.
pub const SETTINGS_FIELDS:&[&str]=&[
 "overlays","subs","subHeights","subHeightOverrides","params","indicatorColors","hiddenOutputs","rsiRange",
 "portraitHeight","quickIntervals","theme","skin","ambientTheme","styleID","redUp","priceMode","timeZone",
 "magnet","countdown","lastLine","sinceChange","showDrawings","candleKind","gridChoice","bodyChoice",
 "viewAnchor","priceBias","dataDisplay","crossPrice","allowMainInversion","allowSubInversion",
 "adaptiveIndicators","compactValues","changeBasis","barSpacing","mainInverted","subInverted","interval",
 "keepAwake","routePolicy",
 // How the person left each page looking: sort order, which market, which tool.
 "favoritesSort","favoritesAscending","favoritesAmount","favoritesSparkline","favoritesExpanded",
 // Which category the favorites page is parked on. It used to live in the phone's own symbol
 // archive (`SymbolPrefs.selectedGroupID`), so it never followed the person to a second device.
 "favoritesGroup",
 "sectorMarket","sectorWindow","sectorSort","drawToolGroup","lastDrawTool","replaySpeed","reviewSearchScope",
];
pub const DRAWING_PREFERENCE_FIELDS:[&str;4]=["favorites","magnet","continuous","styles"];
// `text` is the note/callout/flag caption; `created` only old archives carry.
pub const DRAWING_FIELDS:[&str;14]=["kind","symbol","market","venue","anchors","color","lineWidth","dash","filled","levels","locked","hidden","created","text"];
pub const FAVORITE_FIELDS:[&str;7]=["symbol","market","venue","groupId","order","pinned","alerts"];
pub const GROUP_FIELDS:[&str;3]=["name","order","members"];
pub fn allowlist(c:&str)->&'static [&'static str] {
 match c {"settings"=>SETTINGS_FIELDS,"drawingPreferences"=>&DRAWING_PREFERENCE_FIELDS,"drawings"=>&DRAWING_FIELDS,"favorites"=>&FAVORITE_FIELDS,"groups"=>&GROUP_FIELDS,_=>&[]}
}
// Malformed paths are rejected; unknown-but-well-formed names are only dropped.
fn valid_path(path:&str)->bool {!path.is_empty() && path.len()<=160 && !path.split('/').any(|p|p.is_empty()||p==".."||p.starts_with('_'))}
fn known_field(c:&str,path:&str)->bool {allowlist(c).contains(&path.split('/').next().unwrap_or_default())}
impl Operation {
 /// Well-formed paths this server has never heard of. A newer client always runs
 /// ahead of a deployed server, and rejecting the whole operation left it in the
 /// client's queue forever, so the field is dropped and reported back instead.
 pub fn unknown_fields(&self)->Vec<String> {
  self.fields.keys().filter(|k|!known_field(&self.collection,k)).cloned().collect()
 }
 pub fn validate(&self)->Result<()> {
  collection(&self.collection)?;
  if self.object_id.is_empty()||self.object_id.len()>180||self.base_revision<0||self.generation<0||self.logical>i64::MAX as u64||self.timestamp<0
   || !matches!(self.action.as_str(),"patch"|"delete"|"restore") || self.fields.len()>256
   || self.fields.keys().any(|k|!valid_path(k))
   || self.fields.iter().any(|(k,v)|known_field(&self.collection,k)&&!crate::sync_validation::field(&self.collection,k,v))
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
   if !known_field(&op.collection,path) {continue}
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
 crate::sync_validation::clear_tombstones(&mut object);
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
  // `droppedFields` is always present, so a client can tell "this server does not
  // report drops" (field absent) from "nothing was dropped" (empty list). Older
  // clients decode it as an unknown key and ignore it.
  let result=json!({"operationId":op.id,"object":next,"cursor":cursor,"droppedFields":op.unknown_fields()});
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
 // One join instead of one query per changed row. A device coming back after a
 // long trip made up to 201 extra round trips inside a single locked
 // transaction, which is also how long every other device of that user waited.
 // The join condition carries the subscription filter, so a row outside the
 // scope simply has no object attached and stays an invalidation.
 let rows=sqlx::query("SELECT c.sequence,c.collection,c.object_id,c.revision,c.deleted,o.body AS current_body,o.fields AS current_fields,o.revision AS current_revision,o.deleted AS current_deleted,o.generation AS current_generation FROM sync_changes c LEFT JOIN sync_objects o ON o.user_id=c.user_id AND o.collection=c.collection AND o.id=c.object_id AND c.collection IS NOT DISTINCT FROM $3::text AND ($4::text IS NULL OR starts_with(c.object_id,$4)) WHERE c.user_id=$1 AND c.sequence>$2 ORDER BY c.sequence LIMIT 201")
  .bind(i.user).bind(cursor).bind(v.collection.as_deref()).bind(v.prefix.as_deref()).fetch_all(&mut *tx).await?;
 let has_more=rows.len()>200;let next=rows.iter().take(200).last().map(|r|r.get::<i64,_>("sequence")).unwrap_or(cursor);
 let mut items=vec![];let mut invalidations=vec![];
 for r in rows.iter().take(200) {
  let c:String=r.get("collection");let id:String=r.get("object_id");
  let subscribed=v.collection.as_ref().is_some_and(|want|want==&c)&&v.prefix.as_ref().is_none_or(|p|id.starts_with(p));
  if subscribed {
   // Absent here means the object row vanished under us, which the old
   // fetch_one reported the same way.
   let body:Option<Value>=r.get("current_body");let body=body.ok_or(sqlx::Error::RowNotFound)?;
   items.push(Object{collection:c,id,body:serde_json::from_value(body)?,fields:serde_json::from_value(r.get::<Value,_>("current_fields"))?,revision:r.get("current_revision"),deleted:r.get("current_deleted"),generation:r.get("current_generation")});
  }else{invalidations.push(json!({"collection":c,"id":id,"deleted":r.get::<bool,_>("deleted"),"revision":r.get::<i64,_>("revision")}));}
 }
 tx.commit().await?;Ok(envelope(json!({"objects":items,"invalidations":invalidations,"cursor":next,"hasMore":has_more,"serverTime":Utc::now().timestamp_millis()})))
}

#[cfg(test)]
mod tests {
 use super::*;
 fn op(collection:&str,fields:&[(&str,Value)])->Operation {
  Operation{id:Uuid::nil(),collection:collection.into(),object_id:"chart".into(),device_id:Uuid::nil(),
   base_revision:0,generation:0,timestamp:1,logical:1,action:"patch".into(),
   fields:fields.iter().map(|(k,v)|((*k).to_string(),v.clone())).collect(),import_batch:None}
 }
 fn blank(collection:&str,id:&str)->Object {
  Object{collection:collection.into(),id:id.into(),body:BTreeMap::new(),fields:BTreeMap::new(),revision:0,deleted:false,generation:0}
 }
 fn applied(collection:&str,fields:&[(&str,Value)])->Object {merge(blank(collection,"chart"),&op(collection,fields),1_800_000_000_000).unwrap()}
 /// The cross-language contract, generated from the client's one table by `make sync-contract`.
 ///
 /// Compiled in, not read at run time: `include_str!` resolves against this source file, so the
 /// test cannot be broken by whatever directory cargo happens to be invoked from, and a missing
 /// or unparseable contract is a compile error rather than a test that quietly skips.
 const CONTRACT:&str=include_str!("../contract/settings-fields.json");

 /// The wire keys the contract says exist, sorted.
 fn contract_wire_keys()->Vec<String> {
  let contract:Value=serde_json::from_str(CONTRACT)
   .expect("contract/settings-fields.json is not valid JSON; regenerate it with `make sync-contract`");
  assert_eq!(contract["version"],json!(1),
   "contract/settings-fields.json is a format version this test does not know how to read; \
    update both readers (Swift SettingsFieldContract and this test) together");
  let mut keys:Vec<String>=contract["wireKeys"].as_array()
   .expect("contract/settings-fields.json has no `wireKeys` array")
   .iter().map(|v|v.as_str().expect("`wireKeys` must be strings").to_string()).collect();
  keys.sort_unstable();
  keys
 }

 /// **`SETTINGS_FIELDS` ≡ the contract's `wireKeys`, name for name.**
 ///
 /// The settings half used to be a hand-copy of a hand-copy: the same 53 strings lived here, in
 /// `SETTINGS_FIELDS`, and a third time in the iOS test. Three copies only work while three
 /// people all remember to edit them together, and commit a161bb0 is what it costs when they do
 /// not. Now both sides read `contract/settings-fields.json`, which is generated from
 /// `PrefsFieldPlan.table` — the one place a field is declared.
 ///
 /// The other four collections have no client-side table to generate from, so they keep the
 /// written-twice trick: the expectation below is a second copy on purpose.
 #[test] fn the_allowlist_is_what_ios_sends() {
  let mut have:Vec<String>=allowlist("settings").iter().map(|s|s.to_string()).collect();
  have.sort_unstable();
  let want=contract_wire_keys();
  let missing:Vec<_>=want.iter().filter(|k|!have.contains(k)).collect();
  let extra:Vec<_>=have.iter().filter(|k|!want.contains(k)).collect();
  assert!(missing.is_empty()&&extra.is_empty(),
   "settings allowlist drifted from contract/settings-fields.json.\n\
    in the contract, missing from SETTINGS_FIELDS: {missing:?}\n\
    in SETTINGS_FIELDS, not in the contract:       {extra:?}\n\
    The contract is generated from the client's `PrefsFieldPlan.table`, so it is the side that \
    is right: add each missing name to SETTINGS_FIELDS *and* a value rule for it in \
    sync_validation::field (a name without a rule 400s the whole operation). Only if the \
    contract itself is stale — because someone edited PrefsFieldPlan.table without \
    regenerating — run `make sync-contract` from the repo root first.");

  let expected=[
   ("drawingPreferences",&["favorites","magnet","continuous","styles"][..]),
   ("drawings",&["kind","symbol","market","venue","anchors","color","lineWidth","dash","filled","levels","locked","hidden","created","text"][..]),
   ("favorites",&["symbol","market","venue","groupId","order","pinned","alerts"][..]),
   ("groups",&["name","order","members"][..]),
  ];
  for (collection,want) in expected {
   let (mut have,mut want)=(allowlist(collection).to_vec(),want.to_vec());
   have.sort_unstable();want.sort_unstable();
   assert_eq!(have,want,
    "{collection} allowlist drifted. iOS sends `PersonalSyncCodec.drawings`/`symbols` for these; \
     a field added there needs one line in \
     sync::{{DRAWING_PREFERENCE,DRAWING,FAVORITE,GROUP}}_FIELDS, one line in this expectation, \
     and a value rule in sync_validation::field — or the setting silently never reaches the \
     person's other device.");
  }
 }

 /// **Every wire key also has a value rule.** A name on the allowlist that
 /// `sync_validation::field` has no arm for is a poison pill: the `_=>false` fallthrough makes
 /// `validate` reject the *whole* operation with a 400, the client quarantines it, and every
 /// later preference queues up behind it. Being on the allowlist is only half of "supported".
 ///
 /// `field` takes a value, so the only honest way to ask "is there a rule for this name?" is to
 /// offer it values and see whether any is accepted. The probes below cover every shape the
 /// settings rules accept today, at the three path depths settings fields use (top level,
 /// `key/<indicator>`, `key/<indicator>/<slot>`). A new field whose rule accepts none of them
 /// fails here — add a probe for it in the same commit that adds the rule.
 #[test] fn every_wire_key_has_a_value_rule() {
  let probes=[
   json!(true),json!(""),json!(0.5),json!(1),json!(4.0),json!([5]),
   json!(["MA"]),json!(["VOL"]),json!(["1m"]),json!(["BTCUSDT"]),json!([30,70]),
   json!("1m"),json!("sage"),json!("direct"),json!("custom"),json!("crypto"),json!("today"),
   json!("change"),json!("history"),json!("medium"),json!({"value":"#112233"}),
  ];
  let accepts=|key:&str|{
   [key.to_string(),format!("{key}/MA"),format!("{key}/MA/0")].iter()
    .any(|path|probes.iter().any(|v|crate::sync_validation::field("settings",path,v)))
  };
  // The probe sweep would be vacuous if `field` said yes to anything, so prove it discriminates.
  assert!(!accepts("telepathy"),"a name with no rule must be refused for every probe");
  for key in contract_wire_keys() {
   assert!(accepts(&key),
    "`{key}` is on the settings allowlist but sync_validation::field has no rule that accepts \
     any probe value for it. Either the rule is missing — and the field is a poison pill that \
     400s every operation carrying it (see commit a161bb0) — or its rule is real and none of \
     the probes in this test fit its shape, in which case add one.");
  }
 }
 /// The bug this whole allowlist pass is about: one pinch on the chart used to come back
 /// 400, sit in the client's outbox and block every later preference behind it.
 #[test] fn pinching_the_chart_now_reaches_the_server() {
  let object=applied("settings",&[("barSpacing",json!(9.5)),("skin",json!("terra")),("interval",json!("15m"))]);
  assert_eq!(object.body["barSpacing"],json!(9.5));
  assert_eq!(object.body["skin"],json!("terra"));
  assert_eq!(object.revision,1);
 }
 /// A newer client always runs ahead of a deployed server. The unknown name is dropped and
 /// named in the receipt; everything else in the same operation still merges.
 #[test] fn a_name_this_server_never_heard_of_loses_the_field_not_the_operation() {
  let operation=op("settings",&[("barSpacing",json!(9.5)),("telepathy",json!(true))]);
  assert!(operation.validate().is_ok());
  assert_eq!(operation.unknown_fields(),vec!["telepathy".to_string()]);
  let object=merge(blank("settings","chart"),&operation,1_800_000_000_000).unwrap();
  assert_eq!(object.body["barSpacing"],json!(9.5));
  assert!(!object.body.contains_key("telepathy"));
  assert!(!object.fields.contains_key("telepathy"));
 }
 /// Unknown *names* are forgiven. Known names with impossible values are not.
 #[test] fn a_value_that_cannot_be_right_is_still_refused() {
  for bad in [json!(0.0),json!(4000.0),json!("wide"),json!(f64::MAX)] {
   assert!(op("settings",&[("barSpacing",bad.clone())]).validate().is_err(),"barSpacing {bad} should be refused");
  }
  assert!(op("settings",&[("skin",json!("neon"))]).validate().is_err());
  assert!(op("settings",&[("interval",json!("7h"))]).validate().is_err());
  assert!(op("settings",&[("replaySpeed",json!(3))]).validate().is_err());
  assert!(op("settings",&[("keepAwake",json!("yes"))]).validate().is_err());
 }
 #[test] fn a_malformed_path_is_still_refused() {
  for path in ["","../secrets","params/../..","_internal","a//b",&"x".repeat(161)] {
   assert!(op("settings",&[(path,json!(true))]).validate().is_err(),"path {path:?} should be refused");
  }
 }
 #[test] fn bulk_and_oversized_payloads_are_still_refused() {
  assert!(op("settings",&[("telepathy",json!("x".repeat(70_000)))]).validate().is_err());
  let many:Vec<_>=(0..257).map(|i|(format!("f{i}"),json!(true))).collect();
  let mut operation=op("settings",&[]);operation.fields=many.into_iter().collect();
  assert!(operation.validate().is_err());
  let mut wrong=op("settings",&[]);wrong.collection="secrets".into();
  assert!(wrong.validate().is_err());
  let mut action=op("settings",&[]);action.action="drop".into();
  assert!(action.validate().is_err());
 }
 /// Dropping a field must not pretend the value landed: the receipt has to carry the name
 /// so the client keeps its dirty mark and retries the value later.
 #[test] fn a_dropped_field_keeps_its_name_in_the_receipt() {
  let operation=op("settings",&[("telepathy",json!(true)),("moodRing",json!("blue"))]);
  let mut named=operation.unknown_fields();named.sort();
  assert_eq!(named,vec!["moodRing".to_string(),"telepathy".to_string()]);
  assert!(op("settings",&[("barSpacing",json!(9.5))]).unknown_fields().is_empty());
 }
}
