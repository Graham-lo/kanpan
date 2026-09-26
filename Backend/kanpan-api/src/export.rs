//! 「导出我的数据」：把这个人在服务端的全部个人数据打成一份 JSON 交还给他。
//!
//! 范围按隐私政策里答应的那几样来：用户名、同步过来的自选 / 画线 / 提醒 / 设置、
//! 复盘记录与它们的事件、存下的相似案例、朋友与往来的画线分享。密码哈希、会话令牌、
//! 推送令牌这些是凭据不是数据，不导出；复盘截图、补图与分享缩略图是二进制，也不塞进 JSON
//! （补图只列元数据：哪条记录、什么格式、多大、什么时候传的）。
//!
//! 单文件、不分页：十个人以内的小服务，一个人的全部数据远小于上限；真到了 20 MB
//! 就回 413，而不是悄悄截断给一份不完整的「全部」。
use crate::{AppState,auth::{Identity,hit_limit},error::{ApiError,Result}};
use axum::{Router,extract::State,routing::get,http::{StatusCode,header},response::{IntoResponse,Response}};
use serde::Serialize;
use serde_json::value::RawValue;

pub const EXPORT_LIMIT:usize=20*1024*1024;
/// 同一时刻只做一份导出。
///
/// 一份导出要把一个人的全部数据读成 JSON 树再序列化，进程里摊开的是数据量的三倍多
/// （实测 12 MB 的数据一份摊开 ≈ 39 MiB）。额度是每人每小时十次，不管并发：以前
/// 八次同时点下去进程涨 314 MiB，几个人同时导、或者一个人连点，就够把 `MemoryMax=1G`
/// 的 serve 连同订单流一起顶掉。导出是偶尔点一次的事，排队等几百毫秒没人察觉。
static EXPORT_GATE:tokio::sync::Semaphore=tokio::sync::Semaphore::const_new(1);
/// 这个人的数据至少有多大：各表正文按文本长度相加，只算下界（不含键名与外壳）。
///
/// 数据库逐行算完只回一个数，不把任何一行搬进进程——下界已经超过上限，就不必
/// 读进来、摊开、序列化之后才发现太大（以前 80 MB 的数据回一个 413 之前进程先涨 425 MiB）。
const SIZE_FLOOR:&str="SELECT \
 (SELECT coalesce(sum(octet_length(body::text)+octet_length(fields::text)),0) FROM sync_objects WHERE user_id=$1 AND NOT deleted) \
 +(SELECT coalesce(sum(octet_length(to_jsonb(e)::text)),0) FROM review_episodes e WHERE user_id=$1) \
 +(SELECT coalesce(sum(octet_length(record::text)),0) FROM review_records WHERE user_id=$1) \
 +(SELECT coalesce(sum(octet_length(to_jsonb(e)::text)),0) FROM review_events e WHERE user_id=$1) \
 +(SELECT coalesce(sum(octet_length(match::text)),0) FROM review_saved_matches WHERE user_id=$1 AND NOT deleted) \
 +(SELECT coalesce(sum(octet_length(drawings::text)),0) FROM shares WHERE from_user=$1 OR to_user=$1)";
// 导出的外形：和别的接口一样包在 `data` 里；各段是数据库给的 JSON 原文。
#[derive(Serialize)] struct Envelope {data:Export}
#[derive(Serialize)] #[serde(rename_all="camelCase")] struct Export {format:&'static str,exported_at:chrono::DateTime<chrono::Utc>,account:Account,sync:Box<RawValue>,review:Review,friends:Box<RawValue>,shares:Box<RawValue>}
#[derive(Serialize)] #[serde(rename_all="camelCase")] struct Account {username:String,created_at:chrono::DateTime<chrono::Utc>}
#[derive(Serialize)] #[serde(rename_all="camelCase")] struct Review {episodes:Box<RawValue>,records:Box<RawValue>,events:Box<RawValue>,saved_matches:Box<RawValue>,attachments:Box<RawValue>}
fn too_large()->ApiError {ApiError(StatusCode::PAYLOAD_TOO_LARGE,"export_too_large")}

pub fn routes()->Router<AppState> {Router::new().route("/v1/auth/me/export",get(export))}

async fn export(State(s):State<AppState>,who:Identity)->Result<Response> {
 // 导出是整库扫一个人的所有表，一小时十次足够「点了没反应再点一次」。
 if !hit_limit(&s,&format!("export:{}",who.user),10,3600).await? {return Err(ApiError(StatusCode::TOO_MANY_REQUESTS,"try_later"))}
 // 先排队再开事务：排着队的请求不占连接池。
 let _slot=EXPORT_GATE.acquire().await.expect("the export gate is never closed");
 let mut tx=s.personal(who.user).await?;
 let floor:i64=sqlx::query_scalar(SIZE_FLOOR).bind(who.user).fetch_one(&mut *tx).await?;
 if floor>EXPORT_LIMIT as i64 {return Err(too_large())}
 // 每一段都在同一个 RLS 事务里、并且显式按 user_id 过滤：双保险，谁也读不到别人的行。
 let (username,created):(String,chrono::DateTime<chrono::Utc>)=sqlx::query_as("SELECT email,created_at FROM account_users WHERE id=$1").bind(who.user).fetch_one(&mut *tx).await?;
 // 每一段都让数据库直接给 JSON 原文（`::text`），进程里只转交、不解析成树：
 // 以前读成 `serde_json::Value` 再序列化，12 MB 的数据一份导出在进程里摊开 ≈ 39 MiB，
 // 而且（macOS 实测）每导一次常驻内存就多留二十来 MB 不还；原文转交则只有「原文 + 成品」两份。
 let one=|sql:&'static str| sqlx::query_scalar::<_,String>(sql).bind(who.user);
 let sync=crate::sync::export(&mut tx,who.user).await?;
 let episodes=one("SELECT coalesce(jsonb_agg(to_jsonb(e)-'user_id' ORDER BY anchor_at),'[]')::text FROM review_episodes e WHERE user_id=$1").fetch_one(&mut *tx).await?;
 let records=one("SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'submitted',submitted,'symbol',symbol,'timeframe',timeframe,'record',record,'changedAt',changed_at) ORDER BY submitted),'[]')::text FROM review_records WHERE user_id=$1").fetch_one(&mut *tx).await?;
 let events=one("SELECT coalesce(jsonb_agg(to_jsonb(e)-'user_id'),'[]')::text FROM review_events e WHERE user_id=$1").fetch_one(&mut *tx).await?;
 let saved=one("SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'match',match,'createdAt',created_at) ORDER BY created_at),'[]')::text FROM review_saved_matches WHERE user_id=$1 AND NOT deleted").fetch_one(&mut *tx).await?;
 let attachments=one("SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'recordId',record_id,'mime',mime,'size',octet_length(bytes),'createdAt',created_at) ORDER BY created_at),'[]')::text FROM review_attachments WHERE user_id=$1").fetch_one(&mut *tx).await?;
 let friends=one("SELECT coalesce(jsonb_agg(u.email ORDER BY u.email),'[]')::text FROM friendships f JOIN account_users u ON u.id=f.friend_id WHERE f.user_id=$1").fetch_one(&mut *tx).await?;
 let shares=one("SELECT coalesce(jsonb_agg(jsonb_build_object('id',s.id,'direction',CASE WHEN s.from_user=$1 THEN 'sent' ELSE 'received' END,'with',u.email,'symbol',s.symbol,'interval',s.interval,'view',jsonb_build_object('from',s.view_from,'to',s.view_to),'drawings',s.drawings,'alerted',s.alerted,'replyTo',s.reply_to,'createdAt',s.created_at,'keptAt',s.kept_at) ORDER BY s.created_at),'[]')::text FROM shares s JOIN account_users u ON u.id=CASE WHEN s.from_user=$1 THEN s.to_user ELSE s.from_user END WHERE s.from_user=$1 OR s.to_user=$1").fetch_one(&mut *tx).await?;
 tx.commit().await?;
 let raw=|text:String|RawValue::from_string(text);
 let body=Envelope{data:Export{
  format:"hkline-export-1",exported_at:chrono::Utc::now(),
  account:Account{username,created_at:created},
  sync,review:Review{episodes:raw(episodes)?,records:raw(records)?,events:raw(events)?,saved_matches:raw(saved)?,attachments:raw(attachments)?},
  friends:raw(friends)?,shares:raw(shares)?,
 }};
 // 只序列化一遍：量出来的这份就是发出去的这份（以前量一遍、`envelope` 再序列化一遍）。
 let bytes=serde_json::to_vec(&body)?;
 if bytes.len()>EXPORT_LIMIT {return Err(too_large())}
 Ok(([(header::CONTENT_TYPE,"application/json")],bytes).into_response())
}
