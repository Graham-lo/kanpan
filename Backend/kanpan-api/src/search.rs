use crate::review_domain as domain;
use crate::{AppState,auth::Identity,error::{ApiError,Params,Payload,Result,Route},envelope,review::{key,lock,cached,finish,parse,core},review_worker::range_bars};
use axum::{Router,Json,extract::State,routing::{get,post},http::HeaderMap};
use chrono::Utc;
use scorebook_core::{api::native_review::{NativeSearch,ChartRange},domain::{chart_match,interval::Interval},market::MarketDataProvider};
use serde::{Deserialize,Serialize};
use serde_json::{Value,json};
use sqlx::Row;
use uuid::Uuid;

pub fn routes()->Router<AppState> {
 Router::new().route("/v1/native-review/searches",post(start))
 .route("/v1/native-review/searches/{id}",get(status).delete(cancel))
 .route("/v1/native-review/searches/{id}/results",get(results))
 .route("/v1/native-review/saved-matches",get(saved).post(save))
 .route("/v1/native-review/saved-matches/{id}",axum::routing::delete(remove))
 .route("/v1/capabilities",get(capabilities))
}
async fn capabilities(State(s):State<AppState>)->Result<Json<Value>> {
 let count:i64=sqlx::query_scalar("SELECT count(*) FROM market_features WHERE published AND model_id='candle-geometry-v2' AND render_version='ohlc-geometry-resample64-v2'").fetch_one(&s.pool).await?;
 Ok(envelope(json!({"reviewMarkets":["binance/usd_m","okx/usd_m"],"reviewIntervals":Interval::ALL.iter().map(|v|v.as_str()).collect::<Vec<_>>(),"search":{"model":chart_match::MODEL,"threshold":0.60,"indexedWindows":count,"anonymous":false},"screenshots":true})))
}
async fn start(State(s):State<AppState>,i:Identity,headers:HeaderMap,Payload(query):Payload<NativeSearch>)->Result<Json<Value>> {
 let id=key(&headers)?;core(domain::validate_range(&query.range,query.cutoff))?;
 if query.range.bars<16{return Err(ApiError::bad("search_range_too_short"))}
 if query.cutoff>Utc::now().timestamp_millis()||!matches!(query.scope.as_str(),"history"|"private") {return Err(ApiError::bad("invalid_search"))}
 let request=json!({"kind":"search","query":query});let mut tx=s.personal(i.user).await?;lock(&mut tx,i.user).await?;
 if let Some(v)=cached(&mut tx,i.user,id,&request).await?{return Ok(envelope(v))}
 let cancelled:bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM review_searches WHERE user_id=$1 AND id=$2 AND status='cancelled')").bind(i.user).bind(id).fetch_one(&mut *tx).await?;
 if cancelled {return Ok(envelope(json!({"id":id,"status":"cancelled","cutoff":query.cutoff})))}
 let count:i64=sqlx::query_scalar("SELECT count(*) FROM review_searches WHERE user_id=$1 AND created_at>now()-interval '1 hour'").bind(i.user).fetch_one(&mut *tx).await?;
 let active:bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM review_searches WHERE user_id=$1 AND status IN ('queued','running') AND expires_at>now())").bind(i.user).fetch_one(&mut *tx).await?;
 if count>=20||active{return Err(ApiError(axum::http::StatusCode::TOO_MANY_REQUESTS,"search_busy"))}
 sqlx::query("INSERT INTO review_searches(user_id,id,query) VALUES($1,$2,$3)").bind(i.user).bind(id).bind(json!(query)).execute(&mut *tx).await?;
 sqlx::query("INSERT INTO search_dispatch(user_id) VALUES($1) ON CONFLICT(user_id) DO UPDATE SET next_at=now()").bind(i.user).execute(&mut *tx).await?;
 let result=json!({"id":id,"status":"queued","cutoff":query.cutoff,"model":chart_match::MODEL});finish(&mut tx,i.user,id,&request,&result).await?;tx.commit().await?;Ok(envelope(result))
}
async fn status(State(s):State<AppState>,i:Identity,Route(id):Route<Uuid>)->Result<Json<Value>> {
 let mut tx=s.personal(i.user).await?;
 let row=sqlx::query("SELECT status,query,position,checked,jsonb_array_length(candidates) AS total,error FROM review_searches WHERE user_id=$1 AND id=$2 AND expires_at>now()").bind(i.user).bind(id).fetch_optional(&mut *tx).await?.ok_or_else(ApiError::missing)?;
 let q:Value=row.get("query");let result=json!({"id":id,"status":row.get::<String,_>("status"),"cutoff":q["cutoff"],"checked":row.get::<i32,_>("checked"),"processed":row.get::<i32,_>("position"),"total":row.get::<Option<i32>,_>("total"),"error":row.get::<Option<String>,_>("error")});tx.commit().await?;Ok(envelope(result))
}
async fn cancel(State(s):State<AppState>,i:Identity,Route(id):Route<Uuid>,headers:HeaderMap)->Result<Json<Value>> {
 let k=key(&headers)?;let request=json!({"kind":"cancel_search","id":id});let mut tx=s.personal(i.user).await?;lock(&mut tx,i.user).await?;
 if let Some(v)=cached(&mut tx,i.user,k,&request).await?{return Ok(envelope(v))}
 let found=sqlx::query("UPDATE review_searches SET status=CASE WHEN status IN ('queued','running') THEN 'cancelled' ELSE status END,lease_id=NULL,lease_until=NULL WHERE user_id=$1 AND id=$2").bind(i.user).bind(id).execute(&mut *tx).await?.rows_affected();
 if found==0 {sqlx::query("INSERT INTO review_searches(user_id,id,query,status) VALUES($1,$2,'{}','cancelled') ON CONFLICT DO NOTHING").bind(i.user).bind(id).execute(&mut *tx).await?;}
 let result=json!({"ok":true});finish(&mut tx,i.user,k,&request,&result).await?;tx.commit().await?;Ok(envelope(result))
}
#[derive(Deserialize,Default)] #[serde(deny_unknown_fields)] struct Page {after:Option<usize>}
async fn results(State(s):State<AppState>,i:Identity,Route(id):Route<Uuid>,Params(page):Params<Page>)->Result<Json<Value>> {
 let offset=page.after.unwrap_or(0);let mut tx=s.personal(i.user).await?;
 let row=sqlx::query("SELECT items,query,status,checked,position FROM review_searches WHERE user_id=$1 AND id=$2 AND expires_at>now()").bind(i.user).bind(id).fetch_optional(&mut *tx).await?.ok_or_else(ApiError::missing)?;
 if row.get::<String,_>("status")!="completed"{return Err(ApiError::conflict("search_not_ready"))}
 let all:Vec<Value>=parse(row.get("items"))?;if offset>all.len(){return Err(ApiError::bad("invalid_cursor"))}
 let items:Vec<_>=all.iter().skip(offset).take(20).collect();let next=(offset+items.len()<all.len()).then(||(offset+items.len()).to_string());
 let q:Value=row.get("query");let result=json!({"items":items,"next":next,"cutoff":q["cutoff"],"model":chart_match::MODEL,"partial":row.get::<i32,_>("checked")<row.get::<i32,_>("position")});tx.commit().await?;Ok(envelope(result))
}
#[derive(Deserialize)] #[serde(rename_all="camelCase",deny_unknown_fields)] struct Save {search_id:Uuid,match_id:Uuid}
async fn save(State(s):State<AppState>,i:Identity,headers:HeaderMap,Payload(input):Payload<Save>)->Result<Json<Value>> {
 let k=key(&headers)?;let req=json!({"kind":"save_match","searchId":input.search_id,"matchId":input.match_id});let mut tx=s.personal(i.user).await?;lock(&mut tx,i.user).await?;
 if let Some(v)=cached(&mut tx,i.user,k,&req).await?{return Ok(envelope(v))}
 let items:Value=sqlx::query_scalar("SELECT items FROM review_searches WHERE user_id=$1 AND id=$2 AND status='completed'").bind(i.user).bind(input.search_id).fetch_optional(&mut *tx).await?.ok_or_else(ApiError::missing)?;
 let item=items.as_array().and_then(|xs|xs.iter().find(|v|v["id"]==input.match_id.to_string())).ok_or_else(ApiError::missing)?;
 sqlx::query("INSERT INTO review_saved_matches(user_id,id,match,source_search) VALUES($1,$2,$3,$4) ON CONFLICT(user_id,id) DO UPDATE SET deleted=false,revision=review_saved_matches.revision+1").bind(i.user).bind(input.match_id).bind(item).bind(input.search_id).execute(&mut *tx).await?;
 let result=json!({"item":item});finish(&mut tx,i.user,k,&req,&result).await?;tx.commit().await?;Ok(envelope(result))
}
#[derive(Deserialize,Default)] struct SavedPage {after:Option<Uuid>}
async fn saved(State(s):State<AppState>,i:Identity,Params(p):Params<SavedPage>)->Result<Json<Value>> {
 let mut tx=s.personal(i.user).await?;
 let rows=sqlx::query("SELECT id,match,revision FROM review_saved_matches WHERE user_id=$1 AND NOT deleted AND ($2::uuid IS NULL OR id>$2) ORDER BY id LIMIT 51").bind(i.user).bind(p.after).fetch_all(&mut *tx).await?;
 let items:Vec<Value>=rows.iter().take(50).map(|r|json!({"item":r.get::<Value,_>("match"),"revision":r.get::<i64,_>("revision")})).collect();
 let next=if rows.len()>50 {Some(rows[49].get::<Uuid,_>("id"))}else{None};tx.commit().await?;Ok(envelope(json!({"items":items,"next":next})))
}
#[derive(Deserialize)] #[serde(rename_all="camelCase",deny_unknown_fields)] struct Remove {expected_revision:i64}
async fn remove(State(s):State<AppState>,i:Identity,Route(id):Route<Uuid>,headers:HeaderMap,Payload(input):Payload<Remove>)->Result<Json<Value>> {
 let k=key(&headers)?;let request=json!({"kind":"remove_match","id":id,"revision":input.expected_revision});let mut tx=s.personal(i.user).await?;lock(&mut tx,i.user).await?;
 if let Some(v)=cached(&mut tx,i.user,k,&request).await?{return Ok(envelope(v))}
 let row=sqlx::query("SELECT revision FROM review_saved_matches WHERE user_id=$1 AND id=$2 FOR UPDATE").bind(i.user).bind(id).fetch_optional(&mut *tx).await?.ok_or_else(ApiError::missing)?;
 if row.get::<i64,_>("revision")!=input.expected_revision{return Err(ApiError::conflict("match_revision_changed"))}
 sqlx::query("UPDATE review_saved_matches SET deleted=true,revision=revision+1 WHERE user_id=$1 AND id=$2").bind(i.user).bind(id).execute(&mut *tx).await?;
 let result=json!({"ok":true});finish(&mut tx,i.user,k,&request,&result).await?;tx.commit().await?;Ok(envelope(result))
}
#[derive(Serialize,Deserialize,Clone)] struct Candidate {id:Uuid,range:ChartRange}
async fn candidates(s:&AppState,owner:Uuid,q:&NativeSearch,vector:&[f32])->Result<Vec<Candidate>> {
 if q.scope=="history" && !matches!(q.range.venue.as_str(),"binance"|"okx") {return Ok(vec![])}
 let feature=format!("{vector:?}");let mut tx=s.personal(owner).await?;
 // 近邻查询的排序表达式必须是**光秃秃的一个** `列 <=> 常量`，向量索引才认得出来。
 // 原来写的是 `ORDER BY embedding<=>$1::vector,id`——多出来的这个 `,id` 让整条 ORDER BY
 // 不再是索引能供的那个形状，于是 market_features_embedding_ann 永远用不上（实测把
 // seqscan/bitmapscan/sort/incremental_sort 全禁掉，规划器宁可报错也不走它），
 // 每次检索都是全表算距离再排一遍。
 // 所以内层只按距离排 + LIMIT（这一层交给索引），把距离取出来当一列，外层再按
 // (距离, id) 定序：三百行的排序是白送的，而「同距离时谁在前」仍旧是确定的
 // ——这一条对断点续跑很要紧，position 是按这个顺序数的。
 let rows=if q.scope=="history" {
  sqlx::query("SELECT * FROM (SELECT id,symbol,market,timeframe,start_at,end_at,bars_count,embedding<=>$1::vector AS distance FROM market_features WHERE published AND model_id='candle-geometry-v2' AND render_version='ohlc-geometry-resample64-v2' AND market=$2 AND timeframe=$3 AND source=$4 AND end_at<=$5 AND symbol LIKE '%USDT' AND NOT(symbol=$6 AND start_at<$7 AND end_at>$8) ORDER BY embedding<=>$1::vector LIMIT 300) nearest ORDER BY distance,id")
  .bind(&feature).bind(&q.range.market).bind(&q.range.interval).bind(&q.range.venue).bind(q.cutoff).bind(&q.range.symbol).bind(q.range.end).bind(q.range.start).fetch_all(&mut *tx).await?
 }else{
  sqlx::query("SELECT * FROM (SELECT id,symbol,'usd_m'::text AS market,timeframe,range_start AS start_at,range_end AS end_at,(record#>>'{draft,range,bars}')::int AS bars_count,feature<=>$1::vector AS distance FROM review_records WHERE user_id=$2 AND feature IS NOT NULL AND feature_version='candle-geometry-v2' AND record->>'voided'='false' AND record#>>'{draft,range,venue}'=$8 AND timeframe=$3 AND range_end<=$4 AND submitted<=$4 AND NOT(symbol=$5 AND range_start<$7 AND range_end>$6) ORDER BY feature<=>$1::vector LIMIT 300) nearest ORDER BY distance,id")
  .bind(&feature).bind(owner).bind(&q.range.interval).bind(q.cutoff).bind(&q.range.symbol).bind(q.range.start).bind(q.range.end).bind(&q.range.venue).fetch_all(&mut *tx).await?
 };
 let values=rows.into_iter().map(|r|Candidate{id:r.get("id"),range:ChartRange{venue:q.range.venue.clone(),market:r.get("market"),symbol:r.get("symbol"),interval:r.get("timeframe"),start:r.get("start_at"),end:r.get("end_at"),bars:r.get::<i32,_>("bars_count") as usize}}).collect();tx.commit().await?;Ok(values)
}
fn sorted_unique(mut items:Vec<Value>)->Vec<Value> {
 items.sort_by(|a,b|b["score"].as_f64().unwrap_or(0.0).total_cmp(&a["score"].as_f64().unwrap_or(0.0)).then_with(||a["id"].as_str().cmp(&b["id"].as_str())));
 let mut result:Vec<Value>=vec![];
 for item in items {if result.iter().any(|v|v["range"]["symbol"]==item["range"]["symbol"]&&v["range"]["start"].as_i64()<item["range"]["end"].as_i64()&&v["range"]["end"].as_i64()>item["range"]["start"].as_i64()){continue}result.push(item)}result
}
pub async fn run_one(s:&AppState,market:&dyn MarketDataProvider)->Result<bool> {
 let mut tx=s.pool.begin().await?;
 let owner:Option<Uuid>=sqlx::query_scalar("SELECT user_id FROM search_dispatch WHERE next_at<=now() ORDER BY next_at,user_id FOR UPDATE SKIP LOCKED LIMIT 1").fetch_optional(&mut *tx).await?;
 let Some(owner)=owner else{return Ok(false)};
 sqlx::query("UPDATE search_dispatch SET next_at=now()+interval '1 second' WHERE user_id=$1").bind(owner).execute(&mut *tx).await?;tx.commit().await?;
 let mut tx=s.personal(owner).await?;
 let row=sqlx::query("SELECT * FROM review_searches WHERE user_id=$1 AND status IN ('queued','running') AND next_at<=now() AND expires_at>now() AND (lease_until IS NULL OR lease_until<now()) ORDER BY created_at,id FOR UPDATE SKIP LOCKED LIMIT 1").bind(owner).fetch_optional(&mut *tx).await?;
 let Some(row)=row else{sqlx::query("UPDATE search_dispatch SET next_at=now()+interval '10 seconds' WHERE user_id=$1").bind(owner).execute(&mut *tx).await?;tx.commit().await?;return Ok(false)};
 let id:Uuid=row.get("id");let lease=Uuid::new_v4();let q:NativeSearch=parse(row.get("query"))?;let attempts:i32=row.get("attempts");
 let old_candidates:Option<Value>=row.get("candidates");let mut position:usize=row.get::<i32,_>("position") as usize;let mut checked=row.get::<i32,_>("checked");let mut items:Vec<Value>=parse(row.get("items"))?;
 sqlx::query("UPDATE review_searches SET status='running',lease_id=$3,lease_until=now()+interval '120 seconds',attempts=attempts+1 WHERE user_id=$1 AND id=$2").bind(owner).bind(id).bind(lease).execute(&mut *tx).await?;tx.commit().await?;
 let work=async {
  let bars=range_bars(market,&q.range,q.cutoff).await?;let candles=core(chart_match::from_bars(&bars))?;
  let candidates:Vec<Candidate>=match old_candidates{Some(v)=>parse(v)?,None=>candidates(s,owner,&q,&core(chart_match::descriptor(&candles))?).await?};
  // Sixteen candidates per lease: the bound exists to let other saved records
  // progress between batches, and on a 7-core host with a handful of users the
  // old four made a search take four times as many leases as it needed to.
  for candidate in candidates.iter().skip(position).take(16) {
   if let Ok(bars)=range_bars(market,&candidate.range,q.cutoff).await {
    let score=core(chart_match::rerank(&candles,&core(chart_match::from_bars(&bars))?,false))?.score;checked+=1;
    if score>=0.60 {items.push(json!({"id":candidate.id,"range":candidate.range,"score":score,"source":q.scope}));}
   }
   position+=1;
  }
  Ok::<_,ApiError>(candidates)
 }.await;
 let mut tx=s.personal(owner).await?;
 let active:Option<Uuid>=sqlx::query_scalar("SELECT id FROM review_searches WHERE user_id=$1 AND id=$2 AND lease_id=$3 AND lease_until>now() AND status='running' FOR UPDATE").bind(owner).bind(id).bind(lease).fetch_optional(&mut *tx).await?;
 if active.is_none(){return Ok(true)}
 match work {
  Ok(candidates)=>{
   let done=position>=candidates.len();let complete=done&&(checked>0||candidates.is_empty());
   let state=if complete{"completed"}else if done{"failed"}else{"queued"};
   let error=if done&&!complete{Some("market_unavailable")}else{None};
   let output=if done{sorted_unique(items)}else{items};
   sqlx::query("UPDATE review_searches SET candidates=$4,position=$5,checked=$6,items=$7,status=$8,error=$9,attempts=0,lease_id=NULL,lease_until=NULL,next_at=now() WHERE user_id=$1 AND id=$2 AND lease_id=$3").bind(owner).bind(id).bind(lease).bind(json!(candidates)).bind(position as i32).bind(checked).bind(json!(output)).bind(state).bind(error).execute(&mut *tx).await?;
  },Err(_)=>{sqlx::query("UPDATE review_searches SET status=$4,error='market_unavailable',lease_id=NULL,lease_until=NULL,next_at=now()+interval '30 seconds' WHERE user_id=$1 AND id=$2 AND lease_id=$3").bind(owner).bind(id).bind(lease).bind(if attempts>=2{"failed"}else{"queued"}).execute(&mut *tx).await?;}
 }
 tx.commit().await?;Ok(true)
}
