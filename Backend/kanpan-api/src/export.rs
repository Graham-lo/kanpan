//! 「导出我的数据」：把这个人在服务端的全部个人数据打成一份 JSON 交还给他。
//!
//! 范围按隐私政策里答应的那几样来：用户名、同步过来的自选 / 画线 / 提醒 / 设置、
//! 复盘记录与它们的事件、存下的相似案例、朋友与往来的画线分享。密码哈希、会话令牌、
//! 推送令牌这些是凭据不是数据，不导出；复盘截图、补图与分享缩略图是二进制，也不塞进 JSON
//! （补图只列元数据：哪条记录、什么格式、多大、什么时候传的）。
//!
//! 单文件、不分页：十个人以内的小服务，一个人的全部数据远小于上限；真到了 20 MB
//! 就回 413，而不是悄悄截断给一份不完整的「全部」。
use crate::{AppState,auth::{Identity,hit_limit},envelope,error::{ApiError,Result}};
use axum::{Router,Json,extract::State,routing::get,http::StatusCode};
use serde_json::{Value,json};

pub const EXPORT_LIMIT:usize=20*1024*1024;

pub fn routes()->Router<AppState> {Router::new().route("/v1/auth/me/export",get(export))}

async fn export(State(s):State<AppState>,who:Identity)->Result<Json<Value>> {
 // 导出是整库扫一个人的所有表，一小时十次足够「点了没反应再点一次」。
 if !hit_limit(&s,&format!("export:{}",who.user),10,3600).await? {return Err(ApiError(StatusCode::TOO_MANY_REQUESTS,"try_later"))}
 let mut tx=s.personal(who.user).await?;
 // 每一段都在同一个 RLS 事务里、并且显式按 user_id 过滤：双保险，谁也读不到别人的行。
 let (username,created):(String,chrono::DateTime<chrono::Utc>)=sqlx::query_as("SELECT email,created_at FROM account_users WHERE id=$1").bind(who.user).fetch_one(&mut *tx).await?;
 let one=|sql:&'static str| sqlx::query_scalar::<_,Value>(sql).bind(who.user);
 let sync=one("SELECT coalesce(jsonb_agg(jsonb_build_object('collection',collection,'id',id,'body',body,'fields',fields,'revision',revision,'changedAt',changed_at) ORDER BY collection,id),'[]') FROM sync_objects WHERE user_id=$1 AND NOT deleted").fetch_one(&mut *tx).await?;
 let episodes=one("SELECT coalesce(jsonb_agg(to_jsonb(e)-'user_id' ORDER BY anchor_at),'[]') FROM review_episodes e WHERE user_id=$1").fetch_one(&mut *tx).await?;
 let records=one("SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'submitted',submitted,'symbol',symbol,'timeframe',timeframe,'record',record,'changedAt',changed_at) ORDER BY submitted),'[]') FROM review_records WHERE user_id=$1").fetch_one(&mut *tx).await?;
 let events=one("SELECT coalesce(jsonb_agg(to_jsonb(e)-'user_id'),'[]') FROM review_events e WHERE user_id=$1").fetch_one(&mut *tx).await?;
 let saved=one("SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'match',match,'createdAt',created_at) ORDER BY created_at),'[]') FROM review_saved_matches WHERE user_id=$1 AND NOT deleted").fetch_one(&mut *tx).await?;
 let attachments=one("SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'recordId',record_id,'mime',mime,'size',octet_length(bytes),'createdAt',created_at) ORDER BY created_at),'[]') FROM review_attachments WHERE user_id=$1").fetch_one(&mut *tx).await?;
 let friends=one("SELECT coalesce(jsonb_agg(u.email ORDER BY u.email),'[]') FROM friendships f JOIN account_users u ON u.id=f.friend_id WHERE f.user_id=$1").fetch_one(&mut *tx).await?;
 let shares=one("SELECT coalesce(jsonb_agg(jsonb_build_object('id',s.id,'direction',CASE WHEN s.from_user=$1 THEN 'sent' ELSE 'received' END,'with',u.email,'symbol',s.symbol,'interval',s.interval,'view',jsonb_build_object('from',s.view_from,'to',s.view_to),'drawings',s.drawings,'alerted',s.alerted,'replyTo',s.reply_to,'createdAt',s.created_at,'keptAt',s.kept_at) ORDER BY s.created_at),'[]') FROM shares s JOIN account_users u ON u.id=CASE WHEN s.from_user=$1 THEN s.to_user ELSE s.from_user END WHERE s.from_user=$1 OR s.to_user=$1").fetch_one(&mut *tx).await?;
 tx.commit().await?;
 let body=json!({
  "format":"hkline-export-1","exportedAt":chrono::Utc::now(),
  "account":{"username":username,"createdAt":created},
  "sync":sync,"review":{"episodes":episodes,"records":records,"events":events,"savedMatches":saved,"attachments":attachments},
  "friends":friends,"shares":shares,
 });
 if serde_json::to_vec(&body)?.len()>EXPORT_LIMIT {return Err(ApiError(StatusCode::PAYLOAD_TOO_LARGE,"export_too_large"))}
 Ok(envelope(body))
}
