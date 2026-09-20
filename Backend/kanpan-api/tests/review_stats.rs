//! 统计口径与检索的回归（报告 B.5 的 review_denominator_proof / review_signature_semantics /
//! review_search_determinism）。
//!
//! 「算出来的那个百分比，到底是拿哪几条算的」必须能一条条指出来。所以这里不看比例，
//! 只看**成员名单**：分母里是哪几条、分子里是哪几条、谁被挡在外面、为什么。
mod review_common;
use chrono::Utc;
use review_common::*;
use serde_json::{Value,json};
use std::collections::BTreeSet;
use uuid::Uuid;

/// 摆出「worker 最终会写成这样」的终态。统计是纯口径问题，不必再跑一遍行情。
async fn settle(w:&World,a:&Account,id:Uuid,outcome:&str) {
 patch(w,a,id,"{eligible}",json!(true)).await;
 if !outcome.is_empty() {patch(w,a,id,"{assessment}",json!({"outcome":outcome,"reason":"回归夹具","eventAt":null,"assessedAt":0})).await;}
}
/// 回答「要不要和上一条并成一笔」。
async fn answer(w:&World,a:&Account,id:Uuid,same:bool) {
 let (status,v)=request(&w.app,&format!("/v1/native-review/records/{id}/group"),"POST",Some(&a.token),Some(Uuid::new_v4()),json!({"expectedRevision":0,"sameEpisode":same})).await;
 assert_eq!(status,200,"{v}");
}
/// 某一组在证明里的那份成员名单。
fn proof_of<'a>(stats:&'a Value,symbol:&str)->&'a Value {
 let id=group_of(&stats["groups"],symbol)["id"].as_str().expect("分组带着自己的签名").to_owned();
 &stats["proof"]["compatible_groups"][id]
}

/// 分母是谁，一条一条指出来。
///
/// 这里摆了九条记录，只有两条有资格进分母：同一段行情里的重复记录只算一条，
/// 还没答「要不要并组」的不算，待核实的不算，只观察的不算，补录超时的不算，
/// 作废的不算——但作废的那条仍旧留在证明里，不许从历史上抹掉。
#[tokio::test]
async fn review_denominator_proof() {
 let w=boot().await;let a=signup(&w.app,"denominator").await;
 let anchor=Utc::now().timestamp_millis()-1_000;
 let same=|symbol|Spec{symbol,anchor,..Spec::default()};
 // 同一套规则的三条 BTCUSDT：赢的一条、另起一段的输的一条、和输的那条挤在同一段里的重复一条。
 let win=place(&w,&a,&same("BTCUSDT")).await;settle(&w,&a,win,"realized").await;
 let loss=place(&w,&a,&same("BTCUSDT")).await;answer(&w,&a,loss,false).await;settle(&w,&a,loss,"unrealized").await;
 let dup=place(&w,&a,&same("BTCUSDT")).await;answer(&w,&a,dup,true).await;settle(&w,&a,dup,"realized").await;
 // 两条挤在同一段行情里的记录，谁先谁后要由数据说了算，不能靠「创建它们的那两毫秒」。
 patch(&w,&a,loss,"{submitted}",json!(anchor)).await;
 patch(&w,&a,dup,"{submitted}",json!(anchor+60_000)).await;
 // 还在等的一条，和一条根本还没回答并组问题的。
 let waiting=place(&w,&a,&same("ETHUSDT")).await;settle(&w,&a,waiting,"").await;
 let unanswered=place(&w,&a,&same("ETHUSDT")).await;settle(&w,&a,unanswered,"realized").await;
 // 待核实、只观察、补录超时、已作废。
 let verify=place(&w,&a,&same("SOLUSDT")).await;settle(&w,&a,verify,"needs_verification").await;
 let observe=place(&w,&a,&Spec{symbol:"XRPUSDT",direction:"observe",anchor,..Spec::default()}).await;
 patch(&w,&a,observe,"{assessment}",json!({"outcome":"observation","reason":"只记录，不判对错","eventAt":null,"assessedAt":0})).await;
 let late=place(&w,&a,&same("ADAUSDT")).await;
 patch(&w,&a,late,"{assessment}",json!({"outcome":"realized","reason":"回归夹具","eventAt":null,"assessedAt":0})).await;
 let dropped=place(&w,&a,&same("DOGEUSDT")).await;settle(&w,&a,dropped,"realized").await;
 let (status,v)=request(&w.app,&format!("/v1/native-review/records/{dropped}/void"),"POST",Some(&a.token),Some(Uuid::new_v4()),json!({"expectedRevision":0})).await;
 assert_eq!(status,200,"{v}");

 let stats=stats(&w,&a).await;
 assert_eq!(stats["proof"]["claim_count"],9,"九条都在证明里，一条都不许消失");
 assert_eq!(stats["proof"]["pending_group_claims"],1,"还没回答并组问题的只有一条");
 assert_eq!(stats["proof"]["voided_claims_retained"],1,"作废的那条留在历史里，只是不参与计算");
 let btc=proof_of(&stats,"BTCUSDT");
 assert_eq!(ids(btc,"denominator_ids"),BTreeSet::from([win.to_string(),loss.to_string()]),"分母就是这两条：{btc}");
 assert_eq!(ids(btc,"numerator_ids"),BTreeSet::from([win.to_string()]),"分子只有赢的那条");
 assert_eq!(ids(btc,"representative_ids"),BTreeSet::from([win.to_string(),loss.to_string()]),"同一段行情里的重复记录只出一个代表");
 assert_eq!(btc["denominator"],2);assert_eq!(btc["numerator"],1);assert_eq!(btc["realization_rate"],0.5);
 assert_eq!(group_of(&stats["groups"],"BTCUSDT")["total"],2);
 assert_eq!(group_of(&stats["groups"],"BTCUSDT")["correct"],1);
 // 还在等的、待核实的：有代表，但一个都不进分母。
 for symbol in ["ETHUSDT","SOLUSDT"] {
  let group=proof_of(&stats,symbol);
  assert_eq!(group["denominator"],0,"{symbol} 不该有分母：{group}");
  assert!(ids(group,"denominator_ids").is_empty());
  assert_eq!(ids(group,"representative_ids").len(),1,"{symbol} 只有一个代表（另一条还没答并组问题）");
 }
 // 只观察、补录超时、已作废：连组都不该有。
 let listed:Vec<&str>=stats["groups"].as_array().unwrap().iter().map(|g|g["title"].as_str().unwrap()).collect();
 for symbol in ["XRPUSDT","ADAUSDT","DOGEUSDT"] {
  assert!(!listed.iter().any(|t|t.contains(symbol)),"{symbol} 不该出现在统计里：{listed:?}");
 }
 assert_eq!(listed.len(),3,"总共只有三组：{listed:?}");
 // 所有分组的分母加起来，也还是只有那两条。
 let everyone:BTreeSet<String>=stats["proof"]["compatible_groups"].as_object().unwrap().values().flat_map(|g|ids(g,"denominator_ids")).collect();
 assert_eq!(everyone,BTreeSet::from([win.to_string(),loss.to_string()]),"全账号的分母合起来就这两条");
 assert_eq!(stats["grouping"],"confirmed_anchored_episode_exact_rule");
 w.close().await;
}

/// 两套口径同时存在：
/// 「这一条当时定的是什么」按绝对价格与绝对到期时刻分，一条一组，用来追溯；
/// 「我这一路打法做得怎么样」按相对幅度与观察时长的档位分，同一类放在一起数。
/// 旧字段一个不动，新口径另起名字。
#[tokio::test]
async fn review_signature_semantics() {
 let w=boot().await;let a=signup(&w.app,"signature").await;
 let now=Utc::now().timestamp_millis();
 let spec=|anchor:i64,span:i64,reference:f64,target:f64,invalidation:f64|Spec{interval:"1m",symbol:"BTCUSDT",reference,target,invalidation,anchor,span,..Spec::default()};
 // 同一类打法的两笔：都是「涨 2% 就走、跌 1% 认错、一小时内见分晓」，
 // 只是一笔在 100 块上做、另一笔在 200 块上做，到期时刻也差着几秒。
 let first=place(&w,&a,&spec(now-1_000,3_600_000,100.0,102.0,99.0)).await;
 let second=place(&w,&a,&spec(now-2_000,3_000_000,200.0,204.0,198.0)).await;
 answer(&w,&a,second,false).await;
 // 第三笔换了打法：目标一口气定在 10%。
 let third=place(&w,&a,&spec(now-3_000,3_600_000,100.0,110.0,99.0)).await;
 answer(&w,&a,third,false).await;
 settle(&w,&a,first,"realized").await;settle(&w,&a,second,"unrealized").await;settle(&w,&a,third,"realized").await;

 let stats=stats(&w,&a).await;
 // 旧口径：绝对价格与绝对到期时刻各不相同，于是三条各成一组，全是 n=1。
 let exact=stats["groups"].as_array().unwrap();
 assert_eq!(exact.len(),3,"追溯口径一条一组：{exact:?}");
 assert!(exact.iter().all(|g|g["total"]==1),"{exact:?}");
 assert!(exact.iter().all(|g|g["verdictStatus"].is_null()),"旧字段的形状一个字都不许动：{exact:?}");
 assert_eq!(stats["grouping"],"confirmed_anchored_episode_exact_rule");
 assert!(stats["proof"]["compatible_groups"].as_object().unwrap().len()==3);
 // 新口径：前两笔是同一类打法，合成一组两笔；第三笔另算。
 let groups=stats["comparableGroups"].as_array().unwrap();
 assert_eq!(groups.len(),2,"可比口径合并同类：{groups:?}");
 let pair=group_of(&stats["comparableGroups"],"BTCUSDT · 做多 · 收盘 · 目标≤ 2%");
 assert_eq!(pair["total"],2,"同一档位的两笔要数在一起：{pair}");
 assert_eq!(pair["correct"],1);
 assert_eq!(pair["verdictStatus"],"insufficient","样本还太少，不许把 50% 当结论");
 assert!(pair["title"].as_str().unwrap().contains("止损≤ 1%"),"{pair}");
 assert!(pair["title"].as_str().unwrap().contains("1小时内"),"{pair}");
 let alone=group_of(&stats["comparableGroups"],"目标≤ 13%");
 assert_eq!(alone["total"],1,"换了打法就是另一路：{alone}");
 let members=&stats["comparableProof"]["compatible_groups"][pair["id"].as_str().unwrap()];
 assert_eq!(ids(members,"denominator_ids"),BTreeSet::from([first.to_string(),second.to_string()]),"合并的是哪两笔要说得出来");
 assert_eq!(ids(members,"numerator_ids"),BTreeSet::from([first.to_string()]));
 assert_eq!(stats["comparableGrouping"],"confirmed_anchored_episode_relative_rule");
 assert_eq!(stats["comparableProof"]["claim_count"],3);
 assert_eq!(stats["ruleVersion"],"criteria-v2");
 assert!(stats["asOf"].is_i64());
 // 第三笔没进那一组，绝不能被算进去凑样本。
 assert!(!ids(members,"representative_ids").contains(&third.to_string()),"{members}");
 w.close().await;
}

/// 检索要可复现：同样的输入给同样的分数，不同周期的窗口绝不混进来，
/// 结果里也没有任何「胜率」——找形状像的图，和这套打法赢不赢是两件事。
#[tokio::test]
async fn review_search_determinism() {
 let w=boot().await;let a=signup(&w.app,"search").await;
 let hour=3_600_000;let cutoff=Utc::now().timestamp_millis()/hour*hour;
 let window=(cutoff-16*hour,cutoff);
 let vector=format!("{:?}",scorebook_core::domain::chart_match::descriptor(&scorebook_core::domain::chart_match::from_bars(&wave("1h",window.0,window.1)).unwrap()).unwrap());
 let twin=Uuid::new_v4();let decoy=Uuid::new_v4();
 for (id,symbol,timeframe,start) in [(twin,"ETHUSDT","1h",window.0),(decoy,"SOLUSDT","15m",cutoff-4*hour)] {
  sqlx::query("INSERT INTO market_features(id,market,symbol,timeframe,start_at,end_at,bars_count,model_id,render_version,embedding,input_hash,source,published) VALUES($1,'usd_m',$2,$3,$4,$5,16,'candle-geometry-v2','ohlc-geometry-resample64-v2',$6::vector,'fixture','binance',true)")
   .bind(id).bind(symbol).bind(timeframe).bind(start).bind(cutoff).bind(&vector).execute(&w.admin).await.unwrap();
 }
 // 这套回归共用一个库，别的用例注册的账号也在同一张检索调度表里。认领是「先按
 // next_at 取一个人，取到了就只看他这一摊」——别人留下的陈年调度排在前面，就会让
 // 这次认领空手而归。所以先把别人的调度推到一天后。
 sqlx::query("UPDATE search_dispatch SET next_at=now()+interval '1 day' WHERE user_id<>$1").bind(a.id).execute(&w.admin).await.unwrap();
 let query=json!({"range":{"venue":"binance","market":"usd_m","symbol":"BTCUSDT","interval":"1h","start":window.0,"end":window.1,"bars":16},"cutoff":cutoff,"scope":"history"});
 let mut runs=vec![];
 for _ in 0..2 {
  let id=Uuid::new_v4();
  let (status,v)=request(&w.app,"/v1/native-review/searches","POST",Some(&a.token),Some(id),query.clone()).await;
  assert_eq!(status,200,"{v}");assert_eq!(v["data"]["status"],"queued");
  assert!(kanpan_api::search::run_one(&w.s,&Market::wave()).await.unwrap(),"该认领到这条检索");
  let (_,job)=request(&w.app,&format!("/v1/native-review/searches/{id}"),"GET",Some(&a.token),None,json!({})).await;
  assert_eq!(job["data"]["status"],"completed","{job}");
  assert_eq!(job["data"]["checked"],1,"只有同周期的那个窗口值得比：{job}");
  let (_,result)=request(&w.app,&format!("/v1/native-review/searches/{id}/results"),"GET",Some(&a.token),None,json!({})).await;
  assert_eq!(result["data"]["partial"],false,"取全了就别说自己是残的");
  runs.push(result["data"]["items"].clone());
 }
 let items=runs[0].as_array().unwrap();
 assert_eq!(items.len(),1,"只该命中那个同周期的窗口：{items:?}");
 assert_eq!(items[0]["id"],twin.to_string());
 assert_ne!(items[0]["id"],decoy.to_string(),"15 分钟的窗口不许混进 1 小时的检索");
 assert_eq!(items[0]["range"]["interval"],"1h");
 let score=items[0]["score"].as_f64().unwrap();
 assert!((0.0..=1.0).contains(&score),"分数是个比例：{score}");
 assert!(score>=0.999,"同一个窗口自己和自己比就该是满分：{score}");
 assert_eq!(runs[0],runs[1],"同样的输入必须给出同样的分数");
 // 结果里只说「像不像」，不说「赢不赢」。
 let keys:BTreeSet<&str>=items[0].as_object().unwrap().keys().map(String::as_str).collect();
 assert_eq!(keys,BTreeSet::from(["id","range","score","source"]),"多一个字段就是多一句没被证明的话：{keys:?}");
 w.close().await;
}
