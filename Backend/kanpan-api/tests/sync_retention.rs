//! 同步回执与变更日志的保留窗口（2026-09-24 深度审查 A2 / A3）。
//!
//! maintenance 每小时对每个人截一次：30 天前的推送回执删掉；30 天前的变更删掉，
//! 但每个人最新的那一行永远留着，删掉的最大 sequence 记成水位。`/v1/sync/changes`
//! 收到低于水位的游标回 410 `cursor_expired`，客户端重新 bootstrap。
mod review_common;
use review_common::{boot,signup,request};
use serde_json::json;
use uuid::Uuid;

fn drawing(device:Uuid,name:&str)->serde_json::Value {
 json!({"id":Uuid::new_v4(),"collection":"drawings","objectId":format!("binance/usd_m/BTCUSDT/{name}"),"deviceId":device,
  "baseRevision":0,"generation":0,"timestamp":chrono::Utc::now().timestamp_millis(),"logical":0,"action":"patch",
  "fields":{"kind":"hline","anchors":[{"t":1_700_000_000_000.0,"p":100.0}],"symbol":"BTCUSDT","market":"usd_m","venue":"binance","lineWidth":1},"importBatch":null})
}

#[tokio::test]
async fn old_receipts_and_changes_are_pruned_and_old_cursors_expire() {
 let w=boot().await;
 let a=signup(&w.app,"qa_retain").await;
 let device:Uuid=sqlx::query_scalar("SELECT device_id FROM account_sessions WHERE user_id=$1 AND revoked_at IS NULL").bind(a.id).fetch_one(&w.admin).await.unwrap();
 let ops:Vec<_>=["one","two","three"].iter().map(|n|drawing(device,n)).collect();
 let (status,v)=request(&w.app,"/v1/sync/operations","POST",Some(&a.token),None,json!({"operations":ops})).await;assert_eq!(status,200,"{v}");
 let seqs:Vec<i64>=sqlx::query_scalar("SELECT sequence FROM sync_changes WHERE user_id=$1 ORDER BY sequence").bind(a.id).fetch_all(&w.admin).await.unwrap();
 assert_eq!(seqs.len(),3);
 // 还在窗口里：一行都不动，也不立水位。
 assert_eq!(kanpan_api::maintenance::cleanup(&w.s).await.unwrap(),0);
 let receipts=|| sqlx::query_scalar::<_,i64>("SELECT count(*) FROM sync_operations WHERE user_id=$1").bind(a.id).fetch_one(&w.admin);
 assert_eq!(receipts().await.unwrap(),3);
 let floor=|| sqlx::query_scalar::<_,i64>("SELECT sequence FROM sync_change_floors WHERE user_id=$1").bind(a.id).fetch_optional(&w.admin);
 assert_eq!(floor().await.unwrap(),None);
 // 整段搬到 31 天前。
 for table in ["sync_operations","sync_changes"] {
  sqlx::query(&format!("UPDATE {table} SET created_at=now()-interval '31 days' WHERE user_id=$1")).bind(a.id).execute(&w.admin).await.unwrap();
 }
 assert_eq!(kanpan_api::maintenance::cleanup(&w.s).await.unwrap(),0,"no step failed");
 assert_eq!(receipts().await.unwrap(),0,"a month-old receipt is gone");
 let left:Vec<i64>=sqlx::query_scalar("SELECT sequence FROM sync_changes WHERE user_id=$1 ORDER BY sequence").bind(a.id).fetch_all(&w.admin).await.unwrap();
 assert_eq!(left,vec![seqs[2]],"the newest change always stays, however old");
 assert_eq!(floor().await.unwrap(),Some(seqs[1]));
 // 游标低于水位：它要的那一段已经不在了。
 for cursor in [0,seqs[0]] {
  let (status,v)=request(&w.app,&format!("/v1/sync/changes?cursor={cursor}"),"GET",Some(&a.token),None,json!({})).await;
  assert_eq!(status,410,"{v}");assert_eq!(v["error"]["code"],"cursor_expired");
 }
 // 正好在水位上：要的是水位之后的，一行没少。
 let (status,v)=request(&w.app,&format!("/v1/sync/changes?cursor={}&collection=drawings",seqs[1]),"GET",Some(&a.token),None,json!({})).await;
 assert_eq!(status,200,"{v}");assert_eq!(v["data"]["objects"].as_array().unwrap().len(),1,"{v}");assert_eq!(v["data"]["cursor"],seqs[2]);
 // bootstrap 交出去的游标一出门就是有效的，对象一个不少。
 let (_,b)=request(&w.app,"/v1/sync/bootstrap?collection=drawings","GET",Some(&a.token),None,json!({})).await;
 assert_eq!(b["data"]["cursor"],seqs[2]);assert_eq!(b["data"]["objects"].as_array().unwrap().len(),3);
 let (status,_)=request(&w.app,&format!("/v1/sync/changes?cursor={}",seqs[2]),"GET",Some(&a.token),None,json!({})).await;assert_eq!(status,200);
 // 原样再跑一轮：没有可删的，水位不动。
 assert_eq!(kanpan_api::maintenance::cleanup(&w.s).await.unwrap(),0);
 assert_eq!(floor().await.unwrap(),Some(seqs[1]));
 // 又写了一条新的：那条留着的旧变更不再是最新的，下一轮就轮到它，水位跟着往前走；
 // 新写的回执和变更在窗口里，不受影响。
 let (status,_)=request(&w.app,"/v1/sync/operations","POST",Some(&a.token),None,json!({"operations":[drawing(device,"four")]})).await;assert_eq!(status,200);
 assert_eq!(kanpan_api::maintenance::cleanup(&w.s).await.unwrap(),0);
 assert_eq!(floor().await.unwrap(),Some(seqs[2]));assert_eq!(receipts().await.unwrap(),1);
 let newest:Vec<i64>=sqlx::query_scalar("SELECT sequence FROM sync_changes WHERE user_id=$1").bind(a.id).fetch_all(&w.admin).await.unwrap();
 assert!(newest.len()==1&&newest[0]>seqs[2],"{newest:?}");
 let (status,_)=request(&w.app,&format!("/v1/sync/changes?cursor={}",seqs[1]),"GET",Some(&a.token),None,json!({})).await;assert_eq!(status,410);
 // 水位比现存最新的变更还高（有人手工删过日志）：再截一轮不会把水位拉回去，
 // 最新那一行照旧留着……
 sqlx::query("UPDATE sync_change_floors SET sequence=$2 WHERE user_id=$1").bind(a.id).bind(newest[0]+100).execute(&w.admin).await.unwrap();
 sqlx::query("UPDATE sync_changes SET created_at=now()-interval '31 days' WHERE user_id=$1").bind(a.id).execute(&w.admin).await.unwrap();
 assert_eq!(kanpan_api::maintenance::cleanup(&w.s).await.unwrap(),0);
 assert_eq!(floor().await.unwrap(),Some(newest[0]+100));
 let n:i64=sqlx::query_scalar("SELECT count(*) FROM sync_changes WHERE user_id=$1").bind(a.id).fetch_one(&w.admin).await.unwrap();assert_eq!(n,1);
 // ……而 bootstrap 的游标取两者较大的那个，交出去就不会立刻过期。
 let (_,b)=request(&w.app,"/v1/sync/bootstrap?collection=drawings","GET",Some(&a.token),None,json!({})).await;assert_eq!(b["data"]["cursor"],newest[0]+100);
 // 水位表和同步表一样按人隔离：没有上下文一行都看不见。
 let n:i64=sqlx::query_scalar("SELECT count(*) FROM sync_change_floors").fetch_one(&w.s.pool).await.unwrap();assert_eq!(n,0);
 w.close().await;
}
