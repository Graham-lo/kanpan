//! 建记录这条契约的回归（报告 B.5 的 review_contract_*）。
//!
//! 「存进去的是什么、拿回来的就该是什么」以及「不合规的东西一个字节都别落库」。
mod review_common;
use base64::{Engine,engine::general_purpose::STANDARD};
use chrono::Utc;
use review_common::*;
use serde_json::{Value,json};
use uuid::Uuid;

/// 一条**把所有可选字段都填满**的记录：原样存、原样取。
/// 顺带钉死一件事：`groupPending` 是服务端每次现算出来给客户端看的，
/// 它绝不许混进落库的那份记录里——那是两个不同的东西。
#[tokio::test]
async fn review_contract_create_roundtrip() {
 let w=boot().await;let a=signup(&w.app,"contract").await;
 let now=Utc::now().timestamp_millis();let end=now/60_000*60_000;let id=Uuid::new_v4();
 let settings=STANDARD.encode(br#"{"version":1,"fields":{"theme":"moss","redUp":true}}"#);
 let drawing=STANDARD.encode(br#"{"lines":[{"kind":"trend"}]}"#);
 let draft=json!({"id":id,
  "range":{"venue":"binance","market":"usd_m","symbol":"BTCUSDT","interval":"1m","start":end-180_000,"end":end,"bars":3},
  // 三个「我手动改过」的标记也在契约里：它们区分的是「系统给的建议」和「我自己定的」。
  "rule":{"version":"criteria-v2","direction":"short","confirmation":"trade_touch","reference":100.0,"target":90.0,"invalidation":110.0,"expires":now+7_200_000,"targetEdited":true,"invalidationEdited":false,"expiryEdited":true},
  "text":"顶背离，等一根确认","confidence":70,"origin":"interwoven","created":now,
  "chartSettings":settings,"drawingSnapshot":drawing,"originalClaimed":now-600_000});
 let (status,v)=request(&w.app,"/v1/native-review/records","POST",Some(&a.token),Some(Uuid::new_v4()),draft.clone()).await;
 assert_eq!(status,200,"{v}");
 let record=&v["data"]["record"];
 assert_eq!(record["draft"],draft,"草稿要一个字段不差地回来");
 assert_eq!(record["serverId"],id.to_string(),"服务端沿用客户端的 id，不另发一个");
 assert_eq!(record["revision"],0);
 assert_eq!(record["voided"],false);
 assert_eq!(record["eligible"],false,"资格要等建索引那一步算，不在创建时许诺");
 assert!(record["assessment"].is_null(),"还没裁定就是 null，不给一个假的初值");
 assert_eq!(record["groupPending"],false,"本品种第一条，没有可并的先例");
 // 落库的那份不带 groupPending：它是 review_records 上的一列，不是记录的一部分。
 let row=stored(&w,&a,id).await;
 assert!(row["groupPending"].is_null(),"这个字段不许写进记录里：{row}");
 assert_eq!(row["draft"],draft,"库里那份同样一字不差");
 assert_eq!(row["draft"]["chartSettings"],json!(settings),"base64 快照原样保存，不重新编码");
 // 详情页看到的和创建时回的是同一份。
 let (status,detail)=request(&w.app,&format!("/v1/native-review/records/{id}"),"GET",Some(&a.token),None,json!({})).await;
 assert_eq!(status,200,"{detail}");
 assert_eq!(detail["data"]["record"],*record);
 assert_eq!(detail["data"]["groupPending"],false);
 assert_eq!(detail["data"]["assessmentRevision"],0);
 assert!(detail["data"]["reflectionAssessmentRevision"].is_null());
 w.close().await;
}

/// 每一条不合规的输入都要被挡在门外，并且说清楚是哪一类不合规——
/// 全都回一句「证据无效」等于什么都没说。挡下来之后库里必须干干净净。
#[tokio::test]
async fn review_contract_reject_values() {
 let w=boot().await;let a=signup(&w.app,"reject").await;
 let base=||draft(&Spec{interval:"1m",..Spec::default()});
 let with=|f:&dyn Fn(&mut Value)|{let mut d=base();f(&mut d);d};
 let cases:Vec<(&str,&str,Value)>=vec![
  ("不是 USDT 本位的品种","invalid_chart_range",with(&|d|d["range"]["symbol"]=json!("BTCUSDC"))),
  ("圈了 1501 根，超过上限","invalid_chart_range",with(&|d|d["range"]["bars"]=json!(1501))),
  ("左沿没压在周期边界上","invalid_chart_range",with(&|d|{let start=d["range"]["start"].as_i64().unwrap();d["range"]["start"]=json!(start+1);})),
  ("到期时刻不在落笔之后","invalid_native_rule",with(&|d|{let created=d["created"].as_i64().unwrap();d["rule"]["expires"]=json!(created-1);})),
  ("做多却把目标定在参考价下面","invalid_native_rule",with(&|d|d["rule"]["target"]=json!(90.0))),
  ("正文超过 64 000 字节","invalid_native_record",with(&|d|d["text"]=json!("a".repeat(64_001)))),
  ("只观察，价格却是 0","invalid_native_record",with(&|d|{d["rule"]["direction"]=json!("observe");d["rule"]["reference"]=json!(0.0);})),
  ("把手也伸进了偏好白名单外的字段","invalid_chart_snapshot",with(&|d|d["chartSettings"]=json!(STANDARD.encode(br#"{"version":1,"fields":{"apiHost":"https://private.example"}}"#)))),
 ];
 for (what,code,body) in cases {
  let (status,v)=request(&w.app,"/v1/native-review/records","POST",Some(&a.token),Some(Uuid::new_v4()),body).await;
  assert_eq!(status,400,"{what}：{v}");
  assert_eq!(v["error"]["code"],code,"{what} 要说清楚是哪一类不合规：{v}");
 }
 // 草稿里多一个服务端不认识的键：整条拒收，而不是默默当没看见。
 let mut unknown=base();unknown["telepathy"]=json!(true);
 let (status,v)=request(&w.app,"/v1/native-review/records","POST",Some(&a.token),Some(Uuid::new_v4()),unknown).await;
 assert_eq!(status,400,"{v}");assert_eq!(v["error"]["code"],"invalid_payload");
 // 被挡下的请求一条记录、一条任务都不该留下。
 for table in ["review_records","review_jobs","review_episodes"] {
  let left:i64=sqlx::query_scalar(&format!("SELECT count(*) FROM {table} WHERE user_id=$1")).bind(a.id).fetch_one(&w.admin).await.unwrap();
  assert_eq!(left,0,"{table} 里不该有东西");
 }
 w.close().await;
}

/// 两端已删掉的 `showDrawings` / `subHeights`（2026-09-24）：老版本每一份快照都编着
/// `showDrawings`，把它们当「白名单外」拒掉，就等于老版本一条复盘都存不进来。
/// 放行、原样保存；真正的白名单外字段照旧拒（见上一条的 `apiHost`）。
#[tokio::test]
async fn review_contract_accepts_retired_settings_names() {
 let w=boot().await;let a=signup(&w.app,"retired").await;
 let retired=STANDARD.encode(br#"{"version":1,"fields":{"theme":"moss","showDrawings":true,"subHeights/MACD":"large"}}"#);
 let mut old=draft(&Spec{interval:"1m",..Spec::default()});old["chartSettings"]=json!(retired);
 let (status,v)=request(&w.app,"/v1/native-review/records","POST",Some(&a.token),Some(Uuid::new_v4()),old).await;
 assert_eq!(status,200,"老版本的快照带着退役字段也要能建记录：{v}");
 assert_eq!(v["data"]["record"]["draft"]["chartSettings"],json!(retired),"快照原样保存");
 let mixed=STANDARD.encode(br#"{"version":1,"fields":{"showDrawings":true,"apiHost":"https://private.example"}}"#);
 let mut bad=draft(&Spec{interval:"1m",..Spec::default()});bad["chartSettings"]=json!(mixed);
 let (status,v)=request(&w.app,"/v1/native-review/records","POST",Some(&a.token),Some(Uuid::new_v4()),bad).await;
 assert_eq!(status,400,"退役字段不是夹带私货的通行证：{v}");assert_eq!(v["error"]["code"],"invalid_chart_snapshot");
 w.close().await;
}
