//! 复盘 worker 的积压压测（2026-09-26 后端压测）：很多人各有到期的活时，队列多久排得完。
//! 都在隔离库里跑，行情是注入的，不出网。
mod review_common;
use chrono::Utc;
use review_common::*;
use serde_json::json;
use std::sync::Arc;
use std::time::{Duration,Instant};
use uuid::Uuid;

/// 这批人的建索引任务还剩几条没做完。
async fn pending_index(w:&World,owners:&[Uuid])->i64 {
 sqlx::query_scalar("SELECT count(*) FROM review_jobs WHERE user_id=ANY($1) AND kind='index' AND NOT finished").bind(owners).fetch_one(&w.admin).await.unwrap()
}

/// 六个人各记了一笔（各一条建索引、一条裁定任务，都立刻到期）：队列要一口气排掉，
/// 不能每做一条就整体睡一觉。
///
/// 以前 worker 每做完一条都睡两秒：每个人自己的调度行本来就按两秒一条限着，全局再睡两秒，
/// 整个 worker 一秒最多判半条——六个人的六条建索引要十几秒才轮完，人数一多，
/// `trade_touch` 那种五秒一查的记录就永远追不上。
#[tokio::test(flavor="multi_thread",worker_threads=4)]
async fn a_backlog_across_owners_drains_without_a_global_pause() {
 let w=boot().await;
 let mut owners=vec![];
 for _ in 0..6 {let a=signup(&w.app,"wq").await;place(&w,&a,&Spec::default()).await;owners.push(a.id);}
 // 同一个库里别的人（这个文件只有这一条用例，但保险起见）的调度推开，队列只剩这六个人。
 sqlx::query("UPDATE review_dispatch SET next_at=CASE WHEN user_id=ANY($1) THEN now() ELSE now()+interval '1 day' END").bind(&owners).execute(&w.admin).await.unwrap();
 let s=w.s.clone();let market=Arc::new(Market::wave());
 let worker=tokio::spawn(async move {kanpan_api::review_worker::work(&s,&*market,Duration::from_secs(2)).await});
 let started=Instant::now();
 while pending_index(&w,&owners).await>0 && started.elapsed()<Duration::from_secs(15) {tokio::time::sleep(Duration::from_millis(50)).await;}
 let took=started.elapsed();let left=pending_index(&w,&owners).await;worker.abort();
 println!("review backlog: 6 owners × (index + assess), index jobs drained in {took:?}, {left} left");
 assert_eq!(left,0,"15 秒里六条建索引还剩 {left} 条");
 assert!(took<Duration::from_secs(6),"六个人各一条到期的建索引，排了 {took:?}");
 w.close().await;
}

/// 排在最前面的人手上没有能做的任务时，认领要接着看下一个人，不能空手回去。
///
/// 以前这一步回「没活」，循环就睡两秒——而排在后面的人明明有到期的任务。
/// 回归用例里早就有人撞上过（`review_stats.rs` 里要先把别人的调度推到一天后）。
#[tokio::test]
async fn an_owner_with_nothing_due_does_not_stall_the_next_one() {
 let w=boot().await;
 let idle=signup(&w.app,"wi").await;let busy=signup(&w.app,"wb").await;
 place(&w,&busy,&Spec::default()).await;
 // 闲着的人：调度行最早到期，但名下一条任务也没有。
 sqlx::query("INSERT INTO review_dispatch(user_id,next_at) VALUES($1,now()-interval '1 minute') ON CONFLICT(user_id) DO UPDATE SET next_at=EXCLUDED.next_at").bind(idle.id).execute(&w.admin).await.unwrap();
 sqlx::query("UPDATE review_dispatch SET next_at=now() WHERE user_id=$1").bind(busy.id).execute(&w.admin).await.unwrap();
 sqlx::query("UPDATE review_dispatch SET next_at=now()+interval '1 day' WHERE user_id<>ALL($1)").bind([idle.id,busy.id].as_slice()).execute(&w.admin).await.unwrap();
 assert!(run(&w,&Market::wave()).await,"排在前面的人没活，也该接着认领到后面那个人的任务");
 w.close().await;
}

/// 同上，「找相似」那条循环。
#[tokio::test]
async fn a_searcher_with_nothing_due_does_not_stall_the_next_one() {
 let w=boot().await;
 let idle=signup(&w.app,"si").await;let busy=signup(&w.app,"sb").await;
 let hour=3_600_000;let cutoff=Utc::now().timestamp_millis()/hour*hour;
 let query=json!({"range":{"venue":"binance","market":"usd_m","symbol":"BTCUSDT","interval":"1h","start":cutoff-16*hour,"end":cutoff,"bars":16},"cutoff":cutoff,"scope":"history"});
 let (status,v)=request(&w.app,"/v1/native-review/searches","POST",Some(&busy.token),Some(Uuid::new_v4()),query).await;
 assert_eq!(status,200,"{v}");
 sqlx::query("INSERT INTO search_dispatch(user_id,next_at) VALUES($1,now()-interval '1 minute') ON CONFLICT(user_id) DO UPDATE SET next_at=EXCLUDED.next_at").bind(idle.id).execute(&w.admin).await.unwrap();
 sqlx::query("UPDATE search_dispatch SET next_at=now() WHERE user_id=$1").bind(busy.id).execute(&w.admin).await.unwrap();
 sqlx::query("UPDATE search_dispatch SET next_at=now()+interval '1 day' WHERE user_id<>ALL($1)").bind([idle.id,busy.id].as_slice()).execute(&w.admin).await.unwrap();
 assert!(kanpan_api::search::run_one(&w.s,&Market::wave()).await.unwrap(),"排在前面的人没活，也该接着认领到后面那个人的检索");
 w.close().await;
}

/// 一条检索每次都做到一半就把 worker 弄没了（进程被杀、任务 panic）：它不走「行情取不到」
/// 那条数到 3 次就标失败的分支，只是租约两分钟后过期。以前认领时不看 `attempts`，
/// 它会一直被再认领到 24 小时后过期，每两分钟弄崩一次 worker。
#[tokio::test]
async fn a_search_that_keeps_killing_the_worker_is_given_up() {
 let w=boot().await;
 let who=signup(&w.app,"sk").await;
 let hour=3_600_000;let cutoff=Utc::now().timestamp_millis()/hour*hour;
 let query=json!({"range":{"venue":"binance","market":"usd_m","symbol":"BTCUSDT","interval":"1h","start":cutoff-16*hour,"end":cutoff,"bars":16},"cutoff":cutoff,"scope":"history"});
 let (status,v)=request(&w.app,"/v1/native-review/searches","POST",Some(&who.token),Some(Uuid::new_v4()),query).await;
 assert_eq!(status,200,"{v}");
 // 模拟前三次认领都在半路没了：状态停在 running、租约已过期、认领计数到了上限。
 sqlx::query("UPDATE review_searches SET status='running',attempts=$2,lease_id=gen_random_uuid(),lease_until=now()-interval '1 second' WHERE user_id=$1").bind(who.id).bind(kanpan_api::search::MAX_ATTEMPTS).execute(&w.admin).await.unwrap();
 sqlx::query("UPDATE search_dispatch SET next_at=now() WHERE user_id=$1").bind(who.id).execute(&w.admin).await.unwrap();
 sqlx::query("UPDATE search_dispatch SET next_at=now()+interval '1 day' WHERE user_id<>$1").bind(who.id).execute(&w.admin).await.unwrap();
 kanpan_api::search::run_one(&w.s,&Market::wave()).await.unwrap();
 let (state,error,attempts):(String,Option<String>,i32)=sqlx::query_as("SELECT status,error,attempts FROM review_searches WHERE user_id=$1").bind(who.id).fetch_one(&w.admin).await.unwrap();
 assert_eq!(state,"failed");assert_eq!(error.as_deref(),Some("search_failed"));
 assert_eq!(attempts,kanpan_api::search::MAX_ATTEMPTS,"放弃时不该再认领一次");
 // 之后再怎么轮也不会再被认领。
 sqlx::query("UPDATE search_dispatch SET next_at=now() WHERE user_id=$1").bind(who.id).execute(&w.admin).await.unwrap();
 assert!(!kanpan_api::search::run_one(&w.s,&Market::wave()).await.unwrap());
 w.close().await;
}
