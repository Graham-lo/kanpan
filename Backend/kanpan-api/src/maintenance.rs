use crate::{AppState,error::Result};
use std::time::Duration;
use uuid::Uuid;

/// 一批最多动多少行。每一批是自己的一条语句（全局表）或自己的一个事务（个人表），
/// 删完一批歇一下再删下一批：积压了几个月的表一条 DELETE 扫完，会把锁、WAL、
/// 复制延迟一下子冲上去，还把同一张表上的正常读写堵在后面。
const BATCH:i64=5000;
/// 一轮里一步最多滚多少批（5000 × 200 = 一百万行）。再多的留给下一小时：
/// 清理是日常活，不值得为了一次清干净而一口气霸占库几十分钟。
const MAX_BATCHES:usize=200;
/// 两批之间歇多久，让别的查询插进来。
const PAUSE:Duration=Duration::from_millis(50);

/// 按批滚着做一件事，直到某一批不满（删干净了）或者到了 `MAX_BATCHES`。
/// `step(limit)` 做一批、返回这一批动了几行。返回合计动了几行。
async fn in_batches<F,Fut>(mut step:F)->Result<u64>
where F:FnMut(i64)->Fut,Fut:std::future::Future<Output=Result<u64>> {
 let mut total=0;
 for batch in 0..MAX_BATCHES {
  if batch>0 {tokio::time::sleep(PAUSE).await}
  let n=step(BATCH).await?;
  total+=n;
  if n<BATCH as u64 {return Ok(total)}
 }
 tracing::info!("Cleanup: stopped after {MAX_BATCHES} batches ({total} rows); the rest waits for the next round");
 Ok(total)
}

/// 每个人各清一遍的那几条。参数：$1 这个人，$2 这一批的上限（`BATCH`）。
///
/// 最后一条是实时活动的兜底：活动最长八小时（`live_activity::LIFETIME`），正常情况下
/// worker 的心跳到点会推一条 `event:"end"` 再把这一行删掉，用不着这里。它存在是为了
/// worker 那几个小时里没跑、或者推送一直失败的那种情形——一行永远没人管的活动登记
/// 会让心跳每一拍都为它多跑一次苹果往返。这里只删行不推送：都过了八小时了，
/// 那个活动在系统那边早就自己结束了。
const PERSONAL:[&str;3]=[
 "DELETE FROM review_searches WHERE ctid IN (SELECT ctid FROM review_searches WHERE user_id=$1 AND expires_at<now() LIMIT $2)",
 "DELETE FROM shares WHERE ctid IN (SELECT ctid FROM shares WHERE to_user=$1 AND kept_at IS NULL AND created_at<now()-interval '90 days' LIMIT $2)",
 "DELETE FROM device_push_tokens WHERE ctid IN (SELECT ctid FROM device_push_tokens WHERE user_id=$1 AND kind='liveActivity' AND COALESCE(started_at,updated_at)<now()-interval '8 hours' LIMIT $2)",
];

/// 全局的那几条，不分人。名字只用来写日志。$1 是这一批的上限（`BATCH`）。
const GLOBAL:[(&str,&str);4]=[
 // 刷新结果的保留窗。手机断网、切后台、进电梯都可能让一次刷新悬在半路，
 // 六十秒远不够一次真实的中断；留够一天，重试回来还能拿到当时那份令牌，
 // 用不着重新登录。密封件本身是加密存的，和令牌表同生共死。
 ("refresh replies","UPDATE account_tokens SET response_sealed=NULL WHERE ctid IN (SELECT ctid FROM account_tokens WHERE used_at<now()-interval '24 hours' AND response_sealed IS NOT NULL LIMIT $1)"),
 ("sessions","DELETE FROM account_sessions WHERE ctid IN (SELECT ctid FROM account_sessions WHERE expires_at<now()-interval '1 day' OR revoked_at<now()-interval '31 days' LIMIT $1)"),
 ("access tokens","DELETE FROM account_tokens WHERE ctid IN (SELECT ctid FROM account_tokens WHERE kind='access' AND expires_at<now()-interval '1 hour' LIMIT $1)"),
 ("rate limits","DELETE FROM account_limits WHERE ctid IN (SELECT ctid FROM account_limits WHERE window_start<now()-interval '1 day' AND (locked_until IS NULL OR locked_until<now()) LIMIT $1)"),
];

/// 一轮清理。**每一步各自失败、各自记日志、接着做下一步**（审查 A6）：
/// 以前任何一条 `?` 出错整轮就停了——某个人的一行坏数据、一次锁超时，
/// 就让排在后面的所有人、所有表这一小时都没人清，下一小时还是停在同一个地方。
///
/// 只有「连名单都列不出来」（库连不上）才返回 `Err`，交给 main 里的循环记一笔、
/// 一小时后再来。返回这一轮失败了几步，测试与日志用。
pub async fn cleanup(s:&AppState)->Result<usize> {
 let mut failed=0usize;
 for (name,sql) in GLOBAL {
  let step=|limit:i64|async move {Ok(sqlx::query(sql).bind(limit).execute(&s.pool).await?.rows_affected())};
  if let Err(e)=in_batches(step).await {failed+=1;tracing::warn!("Cleanup: {name} failed, moving on ({e:?})");}
 }
 let mut after:Option<Uuid>=None;
 loop {
  let owners:Vec<Uuid>=sqlx::query_scalar("SELECT id FROM account_users WHERE disabled_at IS NULL AND ($1::uuid IS NULL OR id>$1) ORDER BY id LIMIT 100").bind(after).fetch_all(&s.pool).await?;
  if owners.is_empty(){break}
  for owner in &owners {
   if let Err(e)=personal(s,*owner).await {failed+=1;tracing::warn!(%owner,"Cleanup for one person failed, moving on ({e:?})");}
  }
  after=owners.last().copied();
 }
 if failed>0 {tracing::warn!("Cleanup finished with {failed} failed step(s)")}
 Ok(failed)
}

/// 一个人的那几条。每一批是他自己的一个短事务（RLS 要求在他的身份下删）：
/// 删过期数据本来就可以分几次做完，一批失败就停在这一条，已提交的批次不会回来。
async fn personal(s:&AppState,owner:Uuid)->Result<()> {
 for sql in PERSONAL {
  in_batches(|limit|async move {
   let mut tx=s.personal(owner).await?;
   let n=sqlx::query(sql).bind(owner).bind(limit).execute(&mut *tx).await?.rows_affected();
   tx.commit().await?;Ok(n)
  }).await?;
 }
 // 同步回执与变更日志的保留窗口（审查 A2 / A3），细节见 `sync::prune`。两张表一起按批滚，
 // 任一张这一批还满着就再来一批。
 // 计数用原子量而不是 `Cell`：这一整轮清理是 worker 里 `tokio::spawn` 的一条任务，future 得是 `Send`。
 use std::sync::atomic::{AtomicU64,Ordering::Relaxed};
 let (receipts,changes)=(AtomicU64::new(0),AtomicU64::new(0));
 in_batches(|limit|{
  let (receipts,changes)=(&receipts,&changes);
  async move {
   let mut tx=s.personal(owner).await?;
   let (r,c)=crate::sync::prune(&mut tx,owner,limit).await?;
   tx.commit().await?;
   receipts.fetch_add(r,Relaxed);changes.fetch_add(c,Relaxed);
   Ok(r.max(c))
  }
 }).await?;
 let (receipts,changes)=(receipts.into_inner(),changes.into_inner());
 if receipts+changes>0 {tracing::info!(%owner,"Cleanup: {receipts} sync receipts, {changes} sync changes past their window")}
 Ok(())
}

#[cfg(test)]
mod tests {
 use super::*;

 /// 0021 删掉了同步快照表：服务端代码里不能再有 SQL 写它、清它，否则上线后那一路
 /// 每次都是「表不存在」。迁移文件本身不算。
 #[test] fn nothing_refers_to_the_dropped_snapshot_table() {
  let dropped=["sync","snapshots"].join("_");
  let dir=std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
  let mut stack=vec![dir];
  while let Some(dir)=stack.pop() {
   for entry in std::fs::read_dir(&dir).unwrap().flatten() {
    let path=entry.path();
    if path.is_dir() {stack.push(path);continue}
    if path.extension().is_some_and(|e|e=="rs") {
     let text=std::fs::read_to_string(&path).unwrap();
     for verb in ["INTO ","FROM ","UPDATE ","TABLE "] {
      assert!(!text.contains(&format!("{verb}{dropped}")),"{} 还在碰 {dropped}",path.display());
     }
    }
   }
  }
  let migration=include_str!("../migrations/0021_drop_sync_snapshots.sql");
  assert!(migration.contains(&format!("DROP TABLE IF EXISTS {dropped};")),"重跑无害");
 }
 /// **清理按批滚**：每一条语句都带一批的上限，积压再多也不会一条语句扫完整张表；
 /// 某一批不满就停，满了就接着来，到上限就留给下一轮。
 #[test] fn every_cleanup_statement_is_bounded_by_a_batch_limit() {
  for (name,sql) in GLOBAL {assert!(sql.contains("ctid IN (SELECT ctid")&&sql.contains("LIMIT $1"),"{name}: {sql}")}
  for sql in PERSONAL {assert!(sql.contains("ctid IN (SELECT ctid")&&sql.contains("LIMIT $2"),"{sql}")}
 }
 #[tokio::test(start_paused=true)] async fn batches_roll_until_one_comes_back_short_or_the_cap() {
  // 12345 行：两批满、第三批不满就停。
  let mut left=12_345u64;let mut calls=0;
  let total=in_batches(|limit|{calls+=1;let n=left.min(limit as u64);left-=n;async move {Ok(n)}}).await.unwrap();
  assert_eq!((total,calls,left),(12_345,3,0));
  // 恰好整批：多跑一批空的确认删干净了。
  let mut left=2*BATCH as u64;let mut calls=0;
  in_batches(|limit|{calls+=1;let n=left.min(limit as u64);left-=n;async move {Ok(n)}}).await.unwrap();
  assert_eq!(calls,3);
  // 删不完：到 MAX_BATCHES 就停，剩下的留给下一轮。
  let mut calls=0;
  let total=in_batches(|limit|{calls+=1;async move {Ok(limit as u64)}}).await.unwrap();
  assert_eq!((calls,total),(MAX_BATCHES,MAX_BATCHES as u64*BATCH as u64));
  // 一批出错就把错交回去（上层记一笔、接着清下一步）。
  let mut calls=0;
  assert!(in_batches(|_|{calls+=1;async move {Err::<u64,_>(crate::error::ApiError::bad("boom"))}}).await.is_err());
  assert_eq!(calls,1);
 }
 /// **八小时之后那一行活动登记一定会被清掉**，哪怕 worker 的心跳从来没能推出去。
 /// 上限和 `live_activity::LIFETIME` 是同一个数：两处写的不是同一个八小时的话，
 /// 要么心跳还在推一个已经被清掉的活动，要么一行孤儿永远留在库里。
 #[test] fn a_live_activity_row_cannot_outlive_eight_hours() {
  let sql=PERSONAL.iter().find(|s|s.contains("liveActivity")).expect("清理里有实时活动这一路");
  assert!(sql.starts_with("DELETE FROM device_push_tokens"));
  assert!(sql.matches("device_push_tokens").count()==2,"外层删、内层挑同一张表");
  assert!(sql.contains("interval '8 hours'"));
  assert_eq!(crate::live_activity::LIFETIME.as_secs(),8*60*60);
  // RLS 挡得住串号，但每一条仍旧自己带 user_id：策略是第二道闸，不是第一道。
  for sql in PERSONAL {assert!(sql.contains("$1"),"{sql}");}
  // 清活动登记只碰 liveActivity 这一种 kind：alerts 的 token 是长期的，widget 这一轮不动。
  assert!(sql.contains("kind='liveActivity'"));
  // 旧行没有 started_at（0017 之前写进去的），退回 updated_at，而不是永远不过期。
  assert!(sql.contains("COALESCE(started_at,updated_at)"));
 }
}
