//! 记录这一侧的并发与边界回归（报告 B.5 的 review_assess_vs_reflection…review_rls_and_alias）。
//!
//! 这里的每一条都在问同一个问题：两件事同时发生时，谁也不许把对方写掉。
mod review_common;
use chrono::Utc;
use review_common::*;
use serde_json::json;
use std::sync::Arc;
use uuid::Uuid;

/// 一条 1 小时图的记录，时间线整体搬到过去，配一串必然判赢的行情。
async fn settled(w:&World,a:&Account,symbol:&'static str)->(Uuid,i64,Vec<scorebook_core::domain::criteria::Bar>) {
 let hour=3_600_000;let base=Utc::now().timestamp_millis()/hour*hour-8*hour;
 let id=place(w,a,&Spec{interval:"1h",symbol,..Spec::default()}).await;
 retime(w,a,id,base,base,base+3*hour).await;
 (id,base,series(base,hour,&[(111.0,99.0,110.0),(101.0,99.0,100.0),(101.0,99.0,100.0)]))
}
/// 这条记录还在等人回答「要不要和上一条并成一笔」吗？
async fn pending(w:&World,id:Uuid)->bool {sqlx::query_scalar("SELECT group_pending FROM review_records WHERE id=$1").bind(id).fetch_one(&w.admin).await.unwrap()}
/// 它挂在哪一段行情上。
async fn episode(w:&World,id:Uuid)->Uuid {sqlx::query_scalar("SELECT episode_id FROM review_records WHERE id=$1").bind(id).fetch_one(&w.admin).await.unwrap()}
/// 把 worker 停在「已经读出记录、正在取行情」那一刻，返回还没落地的那个任务。
async fn halted(w:&World,market:&Arc<Market>,gate:&Arc<Gate>)->tokio::task::JoinHandle<bool> {
 let s=w.s.clone();let m=market.clone();
 let handle=tokio::spawn(async move {kanpan_api::review_worker::run_one(&s,&*m).await.unwrap()});
 gate.entered.notified().await;handle
}

/// worker 正在取行情的时候，人在手机上写完了复盘。两件事都要留下：
/// worker 写结论前会重新读一次记录，所以它落的是「最新的记录 + 新结论」，
/// 而不是它三十秒前读到的那份快照。
#[tokio::test]
async fn review_assess_vs_reflection() {
 let w=boot().await;let a=signup(&w.app,"race").await;
 let (id,_,bars)=settled(&w,&a,"BTCUSDT").await;
 focus(&w,&a,id,"assess").await;
 let gate=Arc::new(Gate::default());let market=Arc::new(Market::bars(bars).held(&gate));
 let worker=halted(&w,&market,&gate).await;
 let body=json!({"expectedRevision":0,"reflection":{"note":"追高了，下次等回踩","nextTime":"只做第一次回踩","publishedAt":null,"revision":0},"publish":true});
 let (status,v)=request(&w.app,&format!("/v1/native-review/records/{id}/reflection"),"POST",Some(&a.token),Some(Uuid::new_v4()),body).await;
 assert_eq!(status,200,"取行情期间照常能写复盘：{v}");
 assert_eq!(v["data"]["record"]["revision"],1);
 gate.release.notify_one();
 assert!(worker.await.unwrap(),"这条任务确实跑完了");
 let row=stored(&w,&a,id).await;
 assert_eq!(row["reflection"]["note"],"追高了，下次等回踩","人写的字不许被 worker 覆盖：{row}");
 assert_eq!(row["revision"],1,"版本号也不许被回退");
 assert_eq!(outcome(&row),"realized","结论同样要落地：{row}");
 assert!(row["reflection"]["publishedAt"].is_i64(),"发布时刻要留住");
 w.close().await;
}

/// 并组是比较-交换：版本对不上就拒绝，对得上才改；同一个幂等键重放不会再涨一版。
#[tokio::test]
async fn review_group_cas() {
 let w=boot().await;let a=signup(&w.app,"group").await;
 let first=place(&w,&a,&Spec::default()).await;
 let second=place(&w,&a,&Spec::default()).await;
 assert!(!pending(&w,first).await,"本品种第一条没有先例可并");
 assert!(pending(&w,second).await,"同一品种 120 小时内的第二条，先问人再算");
 assert_eq!(episode(&w,first).await,episode(&w,second).await,"问之前它们还挂在同一段行情上");
 let path=format!("/v1/native-review/records/{second}/group");
 let (status,v)=request(&w.app,&path,"POST",Some(&a.token),Some(Uuid::new_v4()),json!({"expectedRevision":7,"sameEpisode":false})).await;
 assert_eq!(status,409,"版本对不上就不许改：{v}");
 assert_eq!(v["error"]["code"],"record_revision_changed");
 assert!(pending(&w,second).await,"被拒绝的请求一个字都没改");
 let key=Uuid::new_v4();let body=json!({"expectedRevision":0,"sameEpisode":false});
 let (status,v)=request(&w.app,&path,"POST",Some(&a.token),Some(key),body.clone()).await;
 assert_eq!(status,200,"{v}");assert_eq!(v["data"]["record"]["revision"],1);
 assert_eq!(v["data"]["record"]["groupPending"],false,"答过之后就不再问了");
 assert!(!pending(&w,second).await);
 assert_ne!(episode(&w,first).await,episode(&w,second).await,"说了不是同一段，就该另起一段");
 // 同一个幂等键重放：原样回上一次的答案，版本号不许再涨一格。
 let (status,again)=request(&w.app,&path,"POST",Some(&a.token),Some(key),body).await;
 assert_eq!(status,200);assert_eq!(again,v,"重放要一模一样");
 assert_eq!(stored(&w,&a,second).await["revision"],1,"重放不许再涨一版");
 // 换一个幂等键、版本也对，但这条已经答过了。
 let (status,v)=request(&w.app,&path,"POST",Some(&a.token),Some(Uuid::new_v4()),json!({"expectedRevision":1,"sameEpisode":true})).await;
 assert_eq!(status,409,"{v}");assert_eq!(v["error"]["code"],"group_already_resolved");
 w.close().await;
}

/// worker 正在取行情的时候这条被作废了：作废赢。
/// worker 回来发现自己的租约已经作数不了，就什么都不写——它算出来的那个结论，
/// 是针对一条已经不存在的判断算的。
#[tokio::test]
async fn review_void_vs_worker() {
 let w=boot().await;let a=signup(&w.app,"void").await;
 let (id,_,bars)=settled(&w,&a,"BTCUSDT").await;
 focus(&w,&a,id,"assess").await;
 let gate=Arc::new(Gate::default());let market=Arc::new(Market::bars(bars).held(&gate));
 let worker=halted(&w,&market,&gate).await;
 let (status,v)=request(&w.app,&format!("/v1/native-review/records/{id}/void"),"POST",Some(&a.token),Some(Uuid::new_v4()),json!({"expectedRevision":0})).await;
 assert_eq!(status,200,"{v}");assert_eq!(v["data"]["record"]["voided"],true);
 gate.release.notify_one();
 assert!(worker.await.unwrap());
 let row=stored(&w,&a,id).await;
 assert_eq!(row["voided"],true);
 assert!(row["assessment"].is_null(),"作废之后不许再补一个结论上去：{row}");
 assert_eq!(row["eligible"],false,"作废的记录不进任何统计");
 assert_eq!(row["revision"],1,"版本号是人改的那一次，worker 没有再动它");
 let row=job(&w,&a,id,"assess").await;
 assert!(row.finished,"作废时队列就该清干净");
 assert!(!row.leased);
 w.close().await;
}

/// 两个人的队列互不干扰：一条任务被租走的时候，另一个 worker 只会去拿别人的那条，
/// 既不会把同一条抢两遍，也不会因为别人的任务卡住就空转。
#[tokio::test]
async fn review_queue_conflict_isolation() {
 let w=boot().await;let a=signup(&w.app,"queue_a").await;let b=signup(&w.app,"queue_b").await;
 let (mine,_,bars)=settled(&w,&a,"BTCUSDT").await;
 let (theirs,_,_)=settled(&w,&b,"ETHUSDT").await;
 // 两个人各留一条到期的裁定任务。这套回归共用一个库，别的用例留下的账号也在同一张
 // 队列表里，所以每一条都只动这两个人，并且把别人的调度推到一天后——
 // 否则「第三次进来该空手而归」量到的是别人的剩饭。
 sqlx::query("UPDATE review_jobs SET finished=true WHERE kind='index' AND user_id IN ($1,$2)").bind(a.id).bind(b.id).execute(&w.admin).await.unwrap();
 sqlx::query("UPDATE review_jobs SET finished=false,lease_id=NULL,lease_until=NULL,next_at=now(),attempts=0 WHERE kind='assess' AND user_id IN ($1,$2)").bind(a.id).bind(b.id).execute(&w.admin).await.unwrap();
 sqlx::query("UPDATE review_dispatch SET next_at=CASE WHEN user_id IN ($1,$2) THEN now() ELSE now()+interval '1 day' END").bind(a.id).bind(b.id).execute(&w.admin).await.unwrap();
 let gate=Arc::new(Gate::default());let market=Arc::new(Market::bars(bars.clone()).held(&gate));
 let worker=halted(&w,&market,&gate).await;
 // 第一条还握着租约，第二个 worker 进来：它只能拿到另一个人的那条。
 assert!(run(&w,&Market::bars(bars)).await,"另一个人的任务照常跑得动");
 // 两个人的调度都被推到两秒后，这会儿再进来一个就该空手而归——
 // 空转不是故障，抢同一条才是。
 assert!(!run(&w,&Market::silent()).await,"没有第三条任务可认领");
 gate.release.notify_one();
 assert!(worker.await.unwrap());
 for (owner,id) in [(&a,mine),(&b,theirs)] {
  let row=stored(&w,owner,id).await;
  assert_eq!(outcome(&row),"realized","{id} 该有自己的结论：{row}");
  assert_eq!(job(&w,owner,id,"assess").await.attempts,1,"一条任务只该被认领一次");
 }
 // 各看各的：谁都看不见对方那条。
 let (_,page)=request(&w.app,"/v1/native-review/records","GET",Some(&a.token),None,json!({})).await;
 let seen:Vec<_>=page["data"]["records"].as_array().unwrap().iter().map(|r|r["serverId"].as_str().unwrap().to_owned()).collect();
 assert_eq!(seen,vec![mine.to_string()],"列表里只该有自己的那条");
 w.close().await;
}

/// 三百条记录、每十条共用一个提交时刻：翻页要不重不漏，顺序要和
/// 「提交时刻降序、同刻按 id 降序」完全一致。游标只带这两个数，
/// 同刻不定序就会漏记录——这正是那条 `(user_id,submitted DESC,id DESC)` 索引的意义。
#[tokio::test]
async fn review_300_records() {
 let w=boot().await;let a=signup(&w.app,"page").await;
 for _ in 0..300 {place(&w,&a,&Spec::default()).await;}
 let base=Utc::now().timestamp_millis()-86_400_000;
 sqlx::query("WITH ordered AS (SELECT id,row_number() OVER (ORDER BY id) AS n FROM review_records WHERE user_id=$1) UPDATE review_records r SET submitted=$2+((ordered.n-1)/10)*1000 FROM ordered WHERE r.user_id=$1 AND r.id=ordered.id")
  .bind(a.id).bind(base).execute(&w.admin).await.unwrap();
 let expected:Vec<Uuid>=sqlx::query_scalar("SELECT id FROM review_records WHERE user_id=$1 ORDER BY submitted DESC,id DESC").bind(a.id).fetch_all(&w.admin).await.unwrap();
 assert_eq!(expected.len(),300);
 let mut seen=vec![];let mut cursor:Option<String>=None;let mut pages=0;
 loop {
  let path=match &cursor {Some(c)=>format!("/v1/native-review/records?after={c}"),None=>"/v1/native-review/records".into()};
  let (status,v)=request(&w.app,&path,"GET",Some(&a.token),None,json!({})).await;
  assert_eq!(status,200,"{v}");pages+=1;assert!(pages<=7,"翻页停不下来");
  for record in v["data"]["records"].as_array().unwrap() {seen.push(record["serverId"].as_str().unwrap().to_owned());}
  match v["data"]["next"].as_str() {Some(c)=>cursor=Some(c.to_owned()),None=>break}
 }
 assert_eq!(pages,6,"三百条、每页五十条");
 assert_eq!(seen.len(),300,"不重不漏");
 assert_eq!(seen.iter().collect::<std::collections::BTreeSet<_>>().len(),300,"没有一条被翻出来两次");
 assert_eq!(seen,expected.iter().map(|id|id.to_string()).collect::<Vec<_>>(),"顺序要和索引说的一致");
 let stats=stats(&w,&a).await;
 assert_eq!(stats["proof"]["claim_count"],300,"证明里的样本数就是三百");
 w.close().await;
}

/// 行级安全与两个路径别名。前者是「就算绕过接口直接连库也拿不到别人的东西」，
/// 后者是「历史上多出来的那个复数路径，和正主走同一套鉴权与版本校验」。
#[tokio::test]
async fn review_rls_and_alias() {
 let w=boot().await;let a=signup(&w.app,"owner").await;let b=signup(&w.app,"stranger").await;
 let id=place(&w,&a,&Spec{text:"只属于我",..Spec::default()}).await;
 let path=format!("/v1/native-review/records/{id}");
 assert_eq!(request(&w.app,&path,"GET",Some(&b.token),None,json!({})).await.0,404,"别人的记录就是不存在");
 for (suffix,body) in [("reflection",json!({"expectedRevision":0,"reflection":{"note":"x","nextTime":"","publishedAt":null,"revision":0},"publish":false})),("void",json!({"expectedRevision":0})),("group",json!({"expectedRevision":0,"sameEpisode":false}))] {
  let (status,v)=request(&w.app,&format!("{path}/{suffix}"),"POST",Some(&b.token),Some(Uuid::new_v4()),body).await;
  assert_eq!(status,404,"{suffix}：{v}");
 }
 // 直接拿运行角色连库：换一个人的身份，看到的行数就是零——
 // 这一层不靠接口写得对，靠的是数据库自己的策略。
 let mut tx=w.s.personal(b.id).await.unwrap();
 let visible:i64=sqlx::query_scalar("SELECT count(*) FROM review_records").fetch_one(&mut *tx).await.unwrap();
 assert_eq!(visible,0,"别人的身份下一行都看不到");
 tx.commit().await.unwrap();
 let mut tx=w.s.personal(a.id).await.unwrap();
 let visible:i64=sqlx::query_scalar("SELECT count(*) FROM review_records").fetch_one(&mut *tx).await.unwrap();
 assert_eq!(visible,1,"自己的身份下看得到自己的那条");
 tx.commit().await.unwrap();
 let anonymous:i64=sqlx::query_scalar("SELECT count(*) FROM review_records").fetch_one(&w.s.pool).await.unwrap();
 assert_eq!(anonymous,0,"没有身份就什么都不是");
 // 复数那个路径是历史遗留的别名，规矩完全一样：同一套鉴权、同一套版本校验。
 let plural=format!("{path}/reflections");let single=format!("{path}/reflection");
 let write=|note:&str,revision:i64|json!({"expectedRevision":revision,"reflection":{"note":note,"nextTime":"","publishedAt":null,"revision":0},"publish":false});
 assert_eq!(request(&w.app,&plural,"POST",Some(&b.token),Some(Uuid::new_v4()),write("偷写",0)).await.0,404,"别名也不认外人");
 let (status,v)=request(&w.app,&plural,"POST",Some(&a.token),Some(Uuid::new_v4()),write("第一遍",0)).await;
 assert_eq!(status,200,"{v}");assert_eq!(v["data"]["record"]["revision"],1);
 let (status,v)=request(&w.app,&single,"POST",Some(&a.token),Some(Uuid::new_v4()),write("拿旧版本再写",0)).await;
 assert_eq!(status,409,"两个路径共用同一个版本号：{v}");
 assert_eq!(v["error"]["code"],"record_revision_changed");
 let (status,v)=request(&w.app,&single,"POST",Some(&a.token),Some(Uuid::new_v4()),write("第二遍",1)).await;
 assert_eq!(status,200,"{v}");assert_eq!(v["data"]["record"]["reflection"]["note"],"第二遍");
 // 旧的匿名能力清单 `/v1/capabilities` 没有任何客户端调用，已删（P4.11）：
 // 删掉就得真的不在，不能留一条不要身份、还要查库的路由。
 let (status,_)=text(&w.app,"/v1/capabilities","GET",None,None,String::new()).await;
 assert_eq!(status,404,"/v1/capabilities 应该已经删掉");
 w.close().await;
}
