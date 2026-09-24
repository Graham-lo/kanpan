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
// 集合名只在这里写一次（审查 A4）。服务端别处要点名一个集合——评估器读设置、
// 波动提醒读自选、分享校验画线——一律用这些常量，不再手写字符串：拼错一个字母
// 不会报错，只会安静地读到「这个人什么都没有」。
pub const SETTINGS:&str="settings";
pub const DRAWING_PREFERENCES:&str="drawingPreferences";
pub const DRAWINGS:&str="drawings";
pub const FAVORITES:&str="favorites";
pub const GROUPS:&str="groups";
pub const ALERTS:&str="alerts";
pub const COLLECTIONS:[&str;6]=[SETTINGS,DRAWING_PREFERENCES,DRAWINGS,FAVORITES,GROUPS,ALERTS];
/// `settings` 集合里那一条设置对象的 id（客户端 `PersonalSyncCodec` 固定写 `chart`）。
pub const SETTINGS_OBJECT:&str="chart";
fn collection(v:&str)->Result<()> {if !COLLECTIONS.contains(&v){Err(ApiError::bad("invalid_collection"))}else{Ok(())}}
/// Settings names that used to be on the wire and were deleted from both ends (2026-09-24:
/// `showDrawings` had no switch left and nobody read it; `subHeights` had no writer since pane
/// heights became drag-to-resize `subHeightOverrides`). Production had `showDrawings:true` on
/// every settings object and `subHeights` empty on all of them, so nothing is lost.
///
/// They are **not** in `SETTINGS_FIELDS` any more: a sync push from an older build still
/// carrying them has them dropped and reported in `droppedFields`, like any unknown name. The
/// one place that refuses unknown names outright is a review chart snapshot (`review::validate`),
/// and every older build encodes `showDrawings` into every snapshot — so the snapshot check lets
/// these through instead of 400-ing every review an older build tries to save. Readers ignore
/// them: the client only applies names it still declares.
/// `favoritesExpanded` (2026-09-24, review U9): the favorites page had two detail forms for the
/// same symbol — the inline expansion and the long-press preview card. Only the card is left, so
/// the set of expanded rows has nothing to remember any more.
/// `orderFlowFilledBid/Ask`, `orderFlowCancelledBid/Ask` (2026-09-24, review item 41): the order-flow
/// display switches went from six to four — filled and cancelled are no longer split by side. The
/// client now sends `orderFlowShowFilled` / `orderFlowShowCancelled` and migrates its own archive as
/// bid || ask; stored bodies still carrying the four old names are cleaned on their next merge.
pub const RETIRED_SETTINGS_FIELDS:&[&str]=&["showDrawings","subHeights","favoritesExpanded",
 "orderFlowFilledBid","orderFlowFilledAsk","orderFlowCancelledBid","orderFlowCancelledAsk"];
/// Favorite names deleted from both ends. `pinned` (2026-09-24): the favorites page never had a
/// way to pin anything once custom groups were judged 「不做」, so `setPinned` had no caller and
/// the Widget's pinned-first ordering only ever saw an empty list. Same treatment as the settings
/// ones: an older build pushing it has it dropped and named in `droppedFields`, and stored
/// bodies still carrying it are cleaned on their next merge (see `strip_retired`).
pub const RETIRED_FAVORITE_FIELDS:&[&str]=&["pinned"];
/// Retired names, per collection.
pub fn retired_fields(c:&str)->&'static [&'static str] {
 match c {SETTINGS=>RETIRED_SETTINGS_FIELDS,FAVORITES=>RETIRED_FAVORITE_FIELDS,_=>&[]}
}
/// First path segment is a retired name in that collection (`subHeights/MACD` counts).
pub fn retired_field(c:&str,path:&str)->bool {retired_fields(c).contains(&path.split('/').next().unwrap_or_default())}
/// First path segment is a retired settings name (`subHeights/MACD` counts).
pub fn retired_settings_field(path:&str)->bool {retired_field(SETTINGS,path)}
/// Take retired names out of a stored object before it is validated and written back.
///
/// Without this, retiring a name is a trap: the value rule goes away with the name, but every
/// body already in the database still carries it (production had `showDrawings:true` on all 66
/// settings objects), so `sync_validation::object` finds a key with no rule and 400s *every*
/// later merge onto that object with `invalid_sync_value` — nothing the person changes syncs
/// again. Readers already ignore these names, so dropping them loses nothing; an older build
/// reading the cleaned body falls back to its own default, which is what production held.
pub fn strip_retired(object:&mut Object) {
 let c=object.collection.clone();
 object.body.retain(|k,_|!retired_field(&c,k));
 object.fields.retain(|k,_|!retired_field(&c,k));
}
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
 "compareSymbols",
 "overlays","subs","subHeightOverrides","params","indicatorColors","hiddenOutputs","rsiRange",
 "portraitHeight","quickIntervals","theme","skin","ambientTheme","styleID","redUp","priceMode","timeZone",
 "magnet","countdown","depth","orderFlow","lastLine","sinceChange","candleKind","gridChoice","bodyChoice",
 "viewAnchor","priceBias","dataDisplay","crossPrice","allowMainInversion","allowSubInversion",
 "adaptiveIndicators","compactValues","changeBasis","barSpacing","mainInverted","subInverted","interval",
 "keepAwake","routePolicy",
 // How the person left each page looking: sort order, which market, which tool.
 "favoritesSort","favoritesAscending","favoritesAmount","favoritesSparkline",
 // Which category the favorites page is parked on. It used to live in the phone's own symbol
 // archive (`SymbolPrefs.selectedGroupID`), so it never followed the person to a second device.
 "favoritesGroup",
 "sectorMarket","sectorWindow","sectorSort","drawToolGroup","lastDrawTool","replaySpeed","reviewSearchScope",
 "alertSound",
 // 自选五分钟波动提醒（P3.1）：开关 + 幅度（百分数）。服务端 `watch_move.rs` 读这两个。
 "watchMoveAlert","watchMoveThreshold",
 // 主力订单流（2026-09-24 逐单模型）：用户改过门槛 / 步长的那几只 base（整张表一个键），
 // 以及四个显示开关（现货 / 合约 / 已成交 / 已撤销；六合四之前按买卖拆开的四个旧键在
 // RETIRED_SETTINGS_FIELDS 里）。服务端只校验、不读。
 "orderFlowOverrides",
 "orderFlowSpot","orderFlowContract","orderFlowShowFilled","orderFlowShowCancelled",
];
// `variants/<palette tool>` is the drawing method last picked for that family in the style sheet
// (trend → extended, hline → hray, vline → crossLine): the next line from that tool is drawn that way.
pub const DRAWING_PREFERENCE_FIELDS:[&str;5]=["favorites","magnet","continuous","styles","variants"];
// `text` is the note/callout/flag caption; `created` only old archives carry.
// Checked against `contract/drawing-fields.json` (`syncFields` + `legacySyncFields`, generated from what
// the client's `PersonalSyncCodec.drawings` really sends) by `drawing_fields_are_what_the_codec_sends`.
pub const DRAWING_FIELDS:[&str;14]=["kind","symbol","market","venue","anchors","color","lineWidth","dash","filled","levels","locked","hidden","created","text"];
pub const FAVORITE_FIELDS:[&str;6]=["symbol","market","venue","groupId","order","alerts"];
pub const GROUP_FIELDS:[&str;3]=["name","order","members"];
// 提醒（方案文档 2.2 的整张表）。`condition` 的两档（`touch` / `close`）两侧评估器都判。
// `kind` 里的 `price` 只进白名单与值规则：客户端没有入口能产生它，这张表也没给它放
// 目标价的字段，所以两侧评估器都**显式**挡住它（`alerts::materialize` 的注释、客户端
// `AlertEvaluator.hit`）——要开这个入口，先去把那两处的判定实现掉。
//
// 注意 `market` 在这个集合里是 `"binance/usd_m"` 整串，而 `drawings`/`favorites` 的
// `market` 是 `"usd_m"`、场所另放在 `venue`。这不是笔误，是方案文档 2.2 写死的形状，
// 所以值规则也按集合分开写——把两者混成一条规则会让客户端发上来的整条 op 400。
pub const ALERT_FIELDS:[&str;18]=[
 "kind","symbol","market","drawingID","lines","condition","armedAt","once",
 "status","firedAt","firedPrice","dueAt","reviewID","title","created",
 // 从图上加提醒：备注、Webhook 地址、Webhook 文案模板（值规则见 sync_validation）。
 "note","webhook","webhookText",
];
pub fn allowlist(c:&str)->&'static [&'static str] {
 match c {SETTINGS=>SETTINGS_FIELDS,DRAWING_PREFERENCES=>&DRAWING_PREFERENCE_FIELDS,DRAWINGS=>&DRAWING_FIELDS,FAVORITES=>&FAVORITE_FIELDS,GROUPS=>&GROUP_FIELDS,ALERTS=>&ALERT_FIELDS,_=>&[]}
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
 if let Some(v)=object.body.get("rsiRange")
  && !v.as_array().is_some_and(|a|a.len()==2&&a[0].as_f64().is_some_and(|lo|lo>=0.0&&a[1].as_f64().is_some_and(|hi|hi>lo&&hi<=100.0))) {return Err(ApiError::bad("invalid_rsi_range"))}
 if let Some(v)=object.body.get("lineWidth")&& !v.as_f64().is_some_and(|n|n>0.0&&n<=12.0){return Err(ApiError::bad("invalid_line_width"))}
 crate::sync_validation::clear_tombstones(&mut object);
 strip_retired(&mut object);
 crate::sync_validation::object(&object)?;
 object.revision=next;Ok(object)
}
pub fn routes()->Router<AppState> {
 Router::new().route("/v1/sync/bootstrap",get(bootstrap)).route("/v1/sync/changes",get(changes)).route("/v1/sync/operations",post(push))
}
fn object(r:&sqlx::postgres::PgRow)->Result<Object> {
 Ok(Object{collection:r.get("collection"),id:r.get("id"),body:serde_json::from_value(r.get("body"))?,fields:serde_json::from_value(r.get("fields"))?,revision:r.get("revision"),deleted:r.get("deleted"),generation:r.get("generation")})
}
/// 这个人的同步日志的串行闸。评估器触发时也要先拿它（`alerts::fire`），
/// 而且要在拿行锁**之前**拿，和 `push` 同一个顺序——否则 worker 与 API 两条路
/// 会以相反的顺序拿同两把锁，那就是教科书上的死锁。
pub async fn lock(tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,owner:Uuid)->Result<()> {
 sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))").bind(format!("sync:{owner}")).execute(&mut **tx).await?;Ok(())
}
// ------------------------------------------------------------ 服务端的出入口
//
// `sync_objects` 只有这个文件直接读写（审查 A4）。服务端别的模块要看一个人同步上来的
// 东西，走 `read_object` / `live_objects`；要以服务端身份改一条，走 `apply_server_op`。
// 这样「删了的不算」「body 是 json 对象」这些约定只在一处，别处不会各写一版 SQL。

/// 一条**还活着**的同步对象（删了的当作没有）。调用方在自己的个人事务里调用。
pub async fn read_object(tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,owner:Uuid,collection:&str,id:&str)->Result<Option<Object>> {
 let row=sqlx::query("SELECT * FROM sync_objects WHERE user_id=$1 AND collection=$2 AND id=$3 AND NOT deleted")
  .bind(owner).bind(collection).bind(id).fetch_optional(&mut **tx).await?;
 row.as_ref().map(object).transpose()
}
/// 这个人某个集合里全部还活着的对象，按 id 排序。只给小集合用（自选、分组）。
pub async fn live_objects(tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,owner:Uuid,collection:&str)->Result<Vec<Object>> {
 let rows=sqlx::query("SELECT * FROM sync_objects WHERE user_id=$1 AND collection=$2 AND NOT deleted ORDER BY id")
  .bind(owner).bind(collection).fetch_all(&mut **tx).await?;
 rows.iter().map(object).collect()
}
/// 这个人的设置对象的 body（评估器取提醒声音、波动提醒的开关与幅度）。没有就是 `None`。
pub async fn settings_body(tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,owner:Uuid)->Result<Option<Value>> {
 Ok(read_object(tx,owner,SETTINGS,SETTINGS_OBJECT).await?.map(|o|json!(o.body)))
}
/// 「导出我的数据」里的同步那一段：全部活着的对象，连同字段戳与最后修改时间。
pub async fn export(tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,owner:Uuid)->Result<Value> {
 Ok(sqlx::query_scalar("SELECT coalesce(jsonb_agg(jsonb_build_object('collection',collection,'id',id,'body',body,'fields',fields,'revision',revision,'changedAt',changed_at) ORDER BY collection,id),'[]') FROM sync_objects WHERE user_id=$1 AND NOT deleted")
  .bind(owner).fetch_one(&mut **tx).await?)
}

// ------------------------------------------------------------------ 保留窗口

/// 推送回执（`sync_operations`）留多久。回执只为一件事存在：客户端发出去一条 op、
/// 没收到回话，拿同一个 op id 重发时，服务端原样交回上一次的结果而不是再合并一遍。
/// 客户端的发件箱几秒到几天内就会重试完；一个月前的回执没有人会再来要（审查 A2）。
pub const OPERATION_RETENTION_DAYS:i32=30;
/// 变更日志（`sync_changes`）留多久。现在的客户端只用 bootstrap（整页拉取）、不走
/// `/v1/sync/changes`，所以截断碰不到它们；将来走增量的客户端落后超过这个窗口，
/// 会拿到 410 `cursor_expired` 再重新 bootstrap（审查 A3）。
pub const CHANGE_RETENTION_DAYS:i32=30;

/// 这个人的回执与变更日志各按窗口截一次。maintenance 每小时对每个人调一次。
///
/// 先拿 `lock`（和 push / changes 同一把）：水位和删除必须对 `changes` 原子可见——
/// 否则一次 `changes` 可能读到旧水位、却撞上已经删掉的那几行，悄悄漏一段改动。
/// 每个人**最新的那一行变更永远不删**：bootstrap 交出去的游标是 max(sequence)，
/// 那一行没了，游标会退回 0、落到水位以下，刚 bootstrap 完的设备立刻就「过期」。
/// 返回删掉的（回执数，变更数）。
pub async fn prune(tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,owner:Uuid)->Result<(u64,u64)> {
 lock(tx,owner).await?;
 let receipts=sqlx::query("DELETE FROM sync_operations WHERE user_id=$1 AND created_at<now()-make_interval(days=>$2)")
  .bind(owner).bind(OPERATION_RETENTION_DAYS).execute(&mut **tx).await?.rows_affected();
 let changes:i64=sqlx::query_scalar("WITH gone AS (\
   DELETE FROM sync_changes WHERE user_id=$1 AND created_at<now()-make_interval(days=>$2) \
    AND sequence<(SELECT max(sequence) FROM sync_changes WHERE user_id=$1) RETURNING sequence), \
  floor AS (INSERT INTO sync_change_floors(user_id,sequence) SELECT $1,max(sequence) FROM gone HAVING count(*)>0 \
   ON CONFLICT(user_id) DO UPDATE SET sequence=GREATEST(sync_change_floors.sequence,EXCLUDED.sequence),updated_at=now() RETURNING 1) \
  SELECT count(*) FROM gone")
  .bind(owner).bind(CHANGE_RETENTION_DAYS).fetch_one(&mut **tx).await?;
 Ok((receipts,u64::try_from(changes).unwrap_or(0)))
}
/// 这个人的变更日志从哪里往后是完整的：`sequence` 不大于它的变更可能已经删掉了。
async fn floor(tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,owner:Uuid)->Result<i64> {
 Ok(sqlx::query_scalar::<_,i64>("SELECT sequence FROM sync_change_floors WHERE user_id=$1").bind(owner).fetch_optional(&mut **tx).await?.unwrap_or(0))
}
/// 游标落在水位以下：它要的那一段（cursor, floor] 可能已经不在了，只能重新 bootstrap。
/// 正好等于水位不算过期——要的是 floor 之后的，一行都没删。
fn expired(cursor:i64,floor:i64)->bool {cursor<floor}
fn cursor_expired()->ApiError {ApiError(axum::http::StatusCode::GONE,"cursor_expired")}

/// 以服务端自己的身份改一条同步对象，走的是和客户端 op 完全一样的那条路。
///
/// 评估器判定触发之后要把 `status=fired` 告诉这个人的每一台设备，而设备只认同步日志：
/// 不写 `sync_changes`，手机下次拉取时什么都收不到，界面上那条提醒会一直显示「活动」。
/// 所以这里不是直接 UPDATE 一行，而是拼一条 op 交给 `merge` ——校验、LWW 戳、
/// 游标一样都不少，客户端读到的东西和别的改动没有区别。
///
/// `device_id` 是全零：那不是任何一台真设备，客户端的「这条是我自己刚发的」判断因此
/// 不会把它当成回声丢掉。调用方必须**已经**拿了 `lock`（本文件 `push` 的同一把）。
///
/// 对象不存在就报错而不是新建：服务端只会去改一条客户端已经同步上来的提醒。
pub async fn apply_server_op(tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,owner:Uuid,collection:&str,object_id:&str,fields:BTreeMap<String,Value>)->Result<Object> {
 let row=sqlx::query("SELECT * FROM sync_objects WHERE user_id=$1 AND collection=$2 AND id=$3 FOR UPDATE").bind(owner).bind(collection).bind(object_id).fetch_optional(&mut **tx).await?;
 let Some(row)=row else {return Err(ApiError::bad("unknown_object"))};
 let old=object(&row)?;
 let now=Utc::now().timestamp_millis();
 let op=Operation{id:Uuid::new_v4(),collection:collection.into(),object_id:object_id.into(),device_id:Uuid::nil(),
  base_revision:old.revision,generation:old.generation,timestamp:now,logical:0,action:"patch".into(),fields,import_batch:None};
 let next=merge(old,&op,now)?;
 sqlx::query("INSERT INTO sync_objects(user_id,collection,id,body,fields,revision,deleted,generation) VALUES($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT(user_id,collection,id) DO UPDATE SET body=excluded.body,fields=excluded.fields,revision=excluded.revision,deleted=excluded.deleted,generation=excluded.generation,changed_at=now()")
  .bind(owner).bind(&next.collection).bind(&next.id).bind(json!(next.body)).bind(json!(next.fields)).bind(next.revision).bind(next.deleted).bind(next.generation).execute(&mut **tx).await?;
 sqlx::query("INSERT INTO sync_changes(user_id,collection,object_id,revision,deleted) VALUES($1,$2,$3,$4,$5)").bind(owner).bind(&next.collection).bind(&next.id).bind(next.revision).bind(next.deleted).execute(&mut **tx).await?;
 Ok(next)
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
  let next=merge(old,&op,Utc::now().timestamp_millis())?;
  sqlx::query("INSERT INTO sync_objects(user_id,collection,id,body,fields,revision,deleted,generation) VALUES($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT(user_id,collection,id) DO UPDATE SET body=excluded.body,fields=excluded.fields,revision=excluded.revision,deleted=excluded.deleted,generation=excluded.generation,changed_at=now()")
   .bind(i.user).bind(&next.collection).bind(&next.id).bind(json!(next.body)).bind(json!(next.fields)).bind(next.revision).bind(next.deleted).bind(next.generation).execute(&mut *tx).await?;
  // 提醒对象落库的同一口气里刷新物化表：评估器读的是 alert_watches，不是 sync_objects。
  // 放在同一个事务里，所以「同步成功了但评估器还在用旧几何」这个中间态不存在——
  // 用户把被提醒的线拖到别处、客户端用同一个 alert id 重传 lines，下一帧就是新形状。
  if next.collection==ALERTS {crate::alerts::materialize(&mut tx,i.user,&next).await?;}
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
 let c=v.collection.unwrap_or_else(||SETTINGS.into());
 let mut tx=s.personal(i.user).await?;lock(&mut tx,i.user).await?;
 // 主键 (user_id,collection,id) 就够了，前缀这一条是过滤器、不指望走索引。
 // 0007 曾经为它建过 sync_objects_prefix（…,id text_pattern_ops）：那种操作符族按字节
 // 序比较，只有在字节序下 starts_with() 才降得成范围扫；可这个库是 en_US.utf8，下面这句
 // `ORDER BY id` 走的是默认排序规则，和它对不上。于是规划器每次都选主键（边扫边出序、
 // LIMIT 101 立刻停），把前缀降级成 Filter——实测 Rows Removed by Filter: 200，那条索引
 // 从建出来到被删（0011）一次都没被用过。真要让前缀走索引，得连同 ORDER BY 一起改成
 // `COLLATE "C"`，而分页游标的顺序是协议的一部分，不值得为一个过滤条件动它。
 let rows=sqlx::query("SELECT * FROM sync_objects WHERE user_id=$1 AND collection=$2 AND ($3::text IS NULL OR starts_with(id,$3)) AND ($4::text IS NULL OR id>$4) ORDER BY id LIMIT 101")
  .bind(i.user).bind(c).bind(v.prefix).bind(v.after).fetch_all(&mut *tx).await?;
 let more=rows.len()>100;let objects=rows.iter().take(100).map(object).collect::<Result<Vec<_>>>()?;
 // 水位是兜底：prune 永远留着每个人最新的一行，正常情况下 max(sequence) 不会低于水位；
 // 真低了（手工删过日志），交出去的游标也不能一出门就是过期的。
 let cursor:i64=sqlx::query_scalar::<_,i64>("SELECT COALESCE(max(sequence),0) FROM sync_changes WHERE user_id=$1").bind(i.user).fetch_one(&mut *tx).await?
  .max(floor(&mut tx,i.user).await?);
 let next=if more {objects.last().map(|o|o.id.clone())}else{None};tx.commit().await?;
 Ok(envelope(json!({"objects":objects,"next":next,"cursor":cursor,"serverTime":Utc::now().timestamp_millis()})))
}
async fn changes(State(s):State<AppState>,i:Identity,Query(v):Query<Scope>)->Result<Json<Value>> {
 if let Some(c)=&v.collection{collection(c)?}
 let cursor=v.cursor.unwrap_or(0);if cursor<0{return Err(ApiError::bad("invalid_cursor"))}
 let mut tx=s.personal(i.user).await?;lock(&mut tx,i.user).await?;
 if expired(cursor,floor(&mut tx,i.user).await?) {return Err(cursor_expired())}
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
 /// 游标低于水位才算过期；等于水位时要的是水位之后的，一行都没删。
 #[test] fn a_cursor_below_the_floor_has_expired() {
  assert!(!expired(0,0),"从没截断过的人，游标 0 照样能从头拉");
  assert!(!expired(120,120)&&!expired(121,120));
  assert!(expired(119,120)&&expired(0,120));
  let e=cursor_expired();assert_eq!((e.0,e.1),(axum::http::StatusCode::GONE,"cursor_expired"));
 }
 /// 两个窗口都比客户端任何一次重试长得多，也不能是零（零等于每小时清空回执）。
 #[test] fn retention_windows_are_a_month() {
  assert_eq!((OPERATION_RETENTION_DAYS,CHANGE_RETENTION_DAYS),(30,30));
 }
 /// 集合名常量就是协议里的那六个，每个都有白名单；拼错的名字没有白名单。
 #[test] fn every_collection_constant_has_an_allowlist() {
  assert_eq!(COLLECTIONS,["settings","drawingPreferences","drawings","favorites","groups","alerts"]);
  for c in COLLECTIONS {assert!(!allowlist(c).is_empty(),"{c}");assert!(collection(c).is_ok())}
  assert!(allowlist("alert").is_empty()&&collection("alert").is_err());
 }
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
 /// **The drawings allowlist is what the client's codec sends, plus the keys only old archives carry.**
 ///
 /// `DRAWING_FIELDS` used to be a third hand-copy of the drawing shape. A key the client starts
 /// encoding that is missing here makes every such line 400 and jam the sync queue behind it.
 /// The contract is generated from real encodes, so it is the side that is right.
 #[test] fn drawing_fields_are_what_the_codec_sends() {
  let contract:Value=serde_json::from_str(include_str!("../contract/drawing-fields.json"))
   .expect("contract/drawing-fields.json is not valid JSON; regenerate it with `make sync-contract`");
  let mut theirs:Vec<String>=contract["syncFields"].as_array().expect("syncFields").iter()
   .map(|v|v.as_str().expect("string").to_string())
   .chain(contract["legacySyncFields"].as_object().expect("legacySyncFields").keys().cloned()).collect();
  theirs.sort();
  let mut ours:Vec<String>=DRAWING_FIELDS.iter().map(|s|s.to_string()).collect(); ours.sort();
  assert_eq!(ours,theirs,"DRAWING_FIELDS drifted from the contract's syncFields + legacySyncFields; \
   edit DRAWING_FIELDS (and give a new key a value rule in sync_validation::field)");
 }
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
   ("drawingPreferences",&["favorites","magnet","continuous","styles","variants"][..]),
   ("drawings",&["kind","symbol","market","venue","anchors","color","lineWidth","dash","filled","levels","locked","hidden","created","text"][..]),
   ("favorites",&["symbol","market","venue","groupId","order","alerts"][..]),
   ("groups",&["name","order","members"][..]),
   ("alerts",&["kind","symbol","market","drawingID","lines","condition","armedAt","once","status","firedAt","firedPrice","dueAt","reviewID","title","created",
    "note","webhook","webhookText"][..]),
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
   json!(["MA"]),json!(["VOL"]),json!(["1m"]),json!(["BTCUSDT"]),json!(["binance/usd_m/BTCUSDT"]),json!([30,70]),
   json!("1m"),json!("sage"),json!("direct"),json!("custom"),json!("crypto"),json!("today"),
   json!("change"),json!("history"),json!("medium"),json!({"value":"#112233"}),json!("default"),json!({}),
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
 /// 画线工具「这一族上次选的画法」：客户端发的是拍平的 `variants/<面板那一格>`，
 /// 要过白名单（不被当成未知字段丢掉）、过值校验，并且真的合并进对象。
 #[test] fn the_remembered_drawing_method_is_stored() {
  let fields=[("variants/trend",json!("extended")),("variants/hline",json!("hray")),("variants/vline",json!("crossLine"))];
  let operation=op("drawingPreferences",&fields);
  assert!(operation.validate().is_ok());
  assert!(operation.unknown_fields().is_empty());
  let object=applied("drawingPreferences",&fields);
  assert_eq!(object.body["variants/trend"],json!("extended"));
  assert_eq!(object.body["variants/vline"],json!("crossLine"));
  assert!(op("drawingPreferences",&[("variants/trend",json!("telekinesis"))]).validate().is_err());
 }
 /// 铃声同时通过字段白名单、值校验与实际合并。
 #[test] fn alert_sound_is_accepted_and_invalid_values_are_refused() {
  for sound in ["default","crisp","electronic","glass"] {
   let operation=op("settings",&[("alertSound",json!(sound))]);
   assert!(operation.validate().is_ok());
   assert!(operation.unknown_fields().is_empty());
   assert_eq!(applied("settings",&[("alertSound",json!(sound))]).body["alertSound"],json!(sound));
  }
  for bad in [json!("future"),json!("alert-glass.caf"),json!(null),json!(1),json!(false)] {
   assert!(op("settings",&[("alertSound",bad)]).validate().is_err());
  }
 }
 /// 自选波动提醒的两项设置：过白名单、过值规则、真的合并进去；越界的一律拒。
 #[test] fn order_flow_settings_are_accepted_and_bounded() {
  use crate::sync_validation::field;
  for key in ["orderFlowSpot","orderFlowContract","orderFlowShowFilled","orderFlowShowCancelled"] {
   assert!(SETTINGS_FIELDS.contains(&key));
   assert!(field("settings",key,&json!(false))&&!field("settings",key,&json!(0))&&!field("settings",key,&json!(null)),"{key}");
  }
  // 六合四：按买卖拆开的四个旧键退役——老版本推上来只丢字段不丢操作，存量 body 合并时洗掉。
  let old=op("settings",&[("orderFlowFilledBid",json!(false)),("orderFlowCancelledAsk",json!(false)),("orderFlowShowFilled",json!(false))]);
  assert!(old.validate().is_ok(),"老版本带着旧开关推上来不能整条 400");
  let mut dropped=old.unknown_fields();dropped.sort();
  assert_eq!(dropped,vec!["orderFlowCancelledAsk".to_string(),"orderFlowFilledBid".to_string()]);
  let mut stored=blank("settings","chart");
  stored.body.insert("orderFlowCancelledBid".into(),json!(true));
  let merged=merge(stored,&old,1_800_000_000_000).unwrap();
  assert_eq!(merged.body["orderFlowShowFilled"],json!(false));
  assert!(!merged.body.contains_key("orderFlowCancelledBid")&&!merged.body.contains_key("orderFlowFilledBid"));
  assert!(SETTINGS_FIELDS.contains(&"orderFlowOverrides"));
  for good in [json!({}),json!({"BTC":{"spot":2000000.0,"step":50}}),json!({"PEPE":{"usdtPerp":1000}}),
               json!({"XAU":{"usdtPerp":1e9,"step":0.00000001},"ETH":{"coinPerp":3e6,"delivery":4e6}})] {
   assert!(field("settings","orderFlowOverrides",&good),"{good}");
  }
  let many:serde_json::Map<String,Value>=(0..201).map(|i|(format!("C{i}"),json!({"spot":1e6}))).collect();
  for bad in [json!(null),json!([]),json!({"btc":{"spot":1e6}}),json!({"":{"spot":1e6}}),json!({"BTC-USDT":{"spot":1e6}}),
              json!({"ABCDEFGHIJKLMNOPQRSTU":{"spot":1e6}}),json!({"BTC":{}}),json!({"BTC":{"spot":999}}),
              json!({"BTC":{"spot":1.1e9}}),json!({"BTC":{"step":0}}),json!({"BTC":{"step":1e7}}),
              json!({"BTC":{"spot":"1000000"}}),json!({"BTC":{"swap":1e6}}),json!({"BTC":1e6}),Value::Object(many)] {
   assert!(!field("settings","orderFlowOverrides",&bad),"{bad}");
  }
 }
 #[test] fn watch_move_settings_are_accepted_and_bounded() {
  for (key,value) in [("watchMoveAlert",json!(true)),("watchMoveAlert",json!(false)),("watchMoveThreshold",json!(1.5)),("watchMoveThreshold",json!(0.1)),("watchMoveThreshold",json!(50))] {
   let operation=op("settings",&[(key,value.clone())]);
   assert!(operation.validate().is_ok(),"{key}={value}");
   assert!(operation.unknown_fields().is_empty(),"{key} 要在白名单里");
   assert_eq!(applied("settings",&[(key,value.clone())]).body[key],value);
  }
  for (key,bad) in [("watchMoveAlert",json!(1)),("watchMoveThreshold",json!(0)),("watchMoveThreshold",json!(51)),("watchMoveThreshold",json!("1.5")),("watchMoveThreshold",json!(null))] {
   assert!(op("settings",&[(key,bad.clone())]).validate().is_err(),"{key} 不该收 {bad}");
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
 /// 退役名字留在**已经存下的** body 里时，之后对这条对象的每一次合并都不能被它拖死：
 /// 值规则随名字删掉了，`sync_validation::object` 会把它当成没有规则的键整条 400
 /// （`invalid_sync_value`）。线上 66 份设置对象都还躺着 `showDrawings:true`。
 #[test] fn a_stored_body_with_retired_names_still_merges() {
  let mut settings=blank("settings","chart");
  settings.body.insert("showDrawings".into(),json!(true));
  settings.body.insert("subHeights".into(),json!({"MACD":"large"}));
  settings.fields.insert("showDrawings".into(),json!({"revision":1}));
  let merged=merge(settings,&op("settings",&[("barSpacing",json!(9.5))]),1_800_000_000_000)
   .unwrap_or_else(|e|panic!("merge onto an old settings body: {}",e.1));
  assert_eq!(merged.body["barSpacing"],json!(9.5));
  assert!(!merged.body.contains_key("showDrawings")&&!merged.body.contains_key("subHeights")&&!merged.fields.contains_key("showDrawings"));

  let mut favorite=blank("favorites","binance/usd_m/BTCUSDT");
  for (k,v) in [("symbol",json!("BTCUSDT")),("market",json!("usd_m")),("venue",json!("binance")),("order",json!(0)),("pinned",json!(false))] {favorite.body.insert(k.into(),v);}
  let mut move_it=op("favorites",&[("groupId",json!("crypto"))]);move_it.object_id="binance/usd_m/BTCUSDT".into();
  let merged=merge(favorite,&move_it,1_800_000_000_000).unwrap_or_else(|e|panic!("merge onto an old favorite body: {}",e.1));
  assert_eq!(merged.body["groupId"],json!("crypto"));
  assert!(!merged.body.contains_key("pinned"));
 }
 /// 老版本推上来的自选操作里带着 `pinned`：只丢这个字段，操作照常合并。
 #[test] fn retired_favorite_names_are_dropped_not_refused() {
  for name in RETIRED_FAVORITE_FIELDS {assert!(!FAVORITE_FIELDS.contains(name),"{name} 已退役，不该还在白名单里")}
  let mut operation=op("favorites",&[("symbol",json!("BTCUSDT")),("market",json!("usd_m")),("venue",json!("binance")),("order",json!(3)),("pinned",json!(true))]);
  operation.object_id="binance/usd_m/BTCUSDT".into();
  assert!(operation.validate().is_ok(),"老版本带着 pinned 推上来不能整条 400");
  assert_eq!(operation.unknown_fields(),vec!["pinned".to_string()]);
  let object=merge(blank("favorites","binance/usd_m/BTCUSDT"),&operation,1_800_000_000_000).unwrap();
  assert_eq!(object.body["order"],json!(3));
  assert!(!object.body.contains_key("pinned"));
  assert!(retired_field("favorites","pinned")&&!retired_field("settings","pinned")&&!retired_field("favorites","order"));
 }
 /// 两端删掉的 `showDrawings` / `subHeights`：老版本推上来照旧只丢字段、不丢操作，
 /// 回执里点名；它们也不许再混回白名单（不然就是没删干净）。
 #[test] fn retired_settings_names_are_dropped_not_refused() {
  for name in RETIRED_SETTINGS_FIELDS {assert!(!SETTINGS_FIELDS.contains(name),"{name} 已退役，不该还在白名单里")}
  let operation=op("settings",&[("showDrawings",json!(true)),("subHeights/MACD",json!("large")),("barSpacing",json!(9.5))]);
  assert!(operation.validate().is_ok(),"老版本带着退役字段推上来不能整条 400");
  let mut named=operation.unknown_fields();named.sort();
  assert_eq!(named,vec!["showDrawings".to_string(),"subHeights/MACD".to_string()]);
  assert!(named.iter().all(|k|retired_settings_field(k)));
  assert!(!retired_settings_field("subHeightOverrides/MACD")&&!retired_settings_field("telepathy"));
  let object=merge(blank("settings","chart"),&operation,1_800_000_000_000).unwrap();
  assert_eq!(object.body["barSpacing"],json!(9.5));
  assert!(!object.body.contains_key("showDrawings")&&!object.body.contains_key("subHeights"));
 }
}
