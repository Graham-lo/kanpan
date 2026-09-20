//! 报告 D.5：出错的时候，屏幕上只许出现一个固定的错误码。
//!
//! 数据库把写操作顶回来、正文根本不是 JSON、连库都连不上——这三类失败在实现里
//! 走的是完全不同的路，但对着用户的那一面必须是同一个形状：
//! `{"error":{"code":"某个固定的词"}}`。表名、SQL、连接串、源码路径、
//! 以及用户刚发上来的那段正文，一个字节都不许回显。
mod review_common;
use kanpan_api::AppState;
use review_common::*;
use serde_json::Value;
use std::time::Duration;
use uuid::Uuid;

/// 只要在正文里出现过，就说明有人把请求原样回显了。
const MARKER:&str="SECRET_NOTE_ZZZ";
/// 出现任何一个就算泄漏。大小写一律按小写比。
const LEAKS:[&str;16]=["review_records","review_jobs","review_searches","select ","insert ","update ","postgres://","127.0.0.1","/users/",".rs","constraint","violates","relation","sqlx","bearer","panic"];

/// 一条错误响应该有的样子：正文短、只有一个固定的词、什么都没漏。返回那个词。
fn clean(what:&str,status:u16,body:&str)->String {
 assert!((400..600).contains(&status),"{what}：这该是一次失败，却回了 {status}");
 assert!(body.len()<200,"{what}：错误正文不该长到能讲故事（{body}）");
 let lower=body.to_lowercase();
 for needle in LEAKS {assert!(!lower.contains(needle),"{what}：正文里漏出了「{needle}」：{body}");}
 assert!(!body.contains(MARKER),"{what}：请求正文被原样回显了：{body}");
 let v:Value=serde_json::from_str(body).unwrap_or_else(|_|panic!("{what}：错误也必须是一份 JSON：{body}"));
 let outer=v.as_object().unwrap_or_else(||panic!("{what}：{body}"));
 assert_eq!(outer.keys().collect::<Vec<_>>(),vec!["error"],"{what}：除了 error 什么都不该有：{body}");
 let inner=v["error"].as_object().unwrap_or_else(||panic!("{what}：{body}"));
 assert_eq!(inner.keys().collect::<Vec<_>>(),vec!["code"],"{what}：除了 code 什么都不该有：{body}");
 let code=inner["code"].as_str().unwrap_or_else(||panic!("{what}：{body}"));
 assert!(!code.is_empty()&&code.chars().all(|c|c.is_ascii_lowercase()||c=='_'),"{what}：错误码要是一个定值的词：{code}");
 code.to_owned()
}

/// 三类失败，一种形状。
#[tokio::test]
async fn review_errors_never_leak_internals() {
 let w=boot().await;let a=signup(&w.app,"errors").await;
 let token=Some(a.token.as_str());

 // 一、数据库把这条写操作顶了回来（临时加一条 CHECK 来造它）。
 // NOT VALID：只管以后写进来的行。这一套回归共用一个库，别的用例早就写过 BTCUSDT，
 // 校验存量会让加约束本身先失败。
 sqlx::query("ALTER TABLE review_records ADD CONSTRAINT review_records_probe CHECK (symbol<>'BTCUSDT') NOT VALID").execute(&w.admin).await.unwrap();
 let body=draft(&Spec{text:MARKER,..Spec::default()}).to_string();
 let (status,v)=text(&w.app,"/v1/native-review/records","POST",token,Some(Uuid::new_v4()),body).await;
 // 先把约束撤掉再断言：万一断言不过，也不能让这条探针留在共用的库里，
 // 否则后面每一个用例都建不成 BTCUSDT 的记录，真正的病根就被盖住了。
 sqlx::query("ALTER TABLE review_records DROP CONSTRAINT review_records_probe").execute(&w.admin).await.unwrap();
 let code=clean("约束把写操作顶了回来",status.as_u16(),&v);
 assert_eq!(code,"temporarily_unavailable","库里出的事只能说「这会儿不行」");
 assert_eq!(status.as_u16(),503);
 // 顶回来的那一条不许留下半截：整笔连同 episode、队列任务一起回滚。
 for table in ["review_records","review_episodes","review_jobs","review_operations"] {
  let left:i64=sqlx::query_scalar(&format!("SELECT count(*) FROM {table} WHERE user_id=$1")).bind(a.id).fetch_one(&w.admin).await.unwrap();
  assert_eq!(left,0,"{table} 里不该留下失败那一笔的痕迹");
 }

 // 二、正文根本不是 JSON，或者查询串、路径参数不成话。每一种都只回一个词。
 // 说明、路径、方法、幂等键、正文、该回哪个词。
 let cases=vec![
  ("正文不是 JSON","/v1/native-review/records".to_owned(),"POST",Some(Uuid::new_v4()),format!("{{\"text\":\"{MARKER}\","),"invalid_payload"),
  ("正文里有服务端不认识的字段","/v1/native-review/records".to_owned(),"POST",Some(Uuid::new_v4()),format!("{{\"telepathy\":\"{MARKER}\"}}"),"invalid_payload"),
  ("正文是一串二进制","/v1/native-review/records".to_owned(),"POST",Some(Uuid::new_v4()),"\u{0}\u{1}\u{2}".to_owned(),"invalid_payload"),
  ("没带幂等键","/v1/native-review/records".to_owned(),"POST",None,draft(&Spec::default()).to_string(),"idempotency_key_required"),
  ("查询串里有不认识的字段",format!("/v1/native-review/records?telepathy={MARKER}"),"GET",None,String::new(),"invalid_query"),
  ("游标不成话",format!("/v1/native-review/records?after={MARKER}!!"),"GET",None,String::new(),"invalid_cursor"),
  ("筛选条件不在名单里",format!("/v1/native-review/records?state={MARKER}"),"GET",None,String::new(),"invalid_filter"),
  ("路径上那个位置不是一个 id",format!("/v1/native-review/records/{MARKER}"),"GET",None,String::new(),"invalid_path"),
  ("检索进度的路径同理",format!("/v1/native-review/searches/{MARKER}"),"GET",None,String::new(),"invalid_path"),
 ];
 for (what,path,method,key,body,expect) in cases {
  let (status,v)=text(&w.app,&path,method,token,key,body).await;
  assert_eq!(clean(what,status.as_u16(),&v),expect,"{what}");
  assert_eq!(status.as_u16(),400,"{what}");
 }

 // 三、连库都连不上：另起一份指向死地址的服务，路由与鉴权跟线上完全一样。
 let pool=kanpan_api::pool_options(false).acquire_timeout(Duration::from_secs(2)).connect_lazy("postgres://nobody:nobody@127.0.0.1:1/nowhere").unwrap();
 let dead=AppState{pool,secrets:w.s.secrets.clone(),dummy_hash:w.s.dummy_hash.clone()};
 let offline=kanpan_api::router(dead.clone());
 let dark=vec![
  ("建记录","/v1/native-review/records".to_owned(),"POST",Some(Uuid::new_v4()),draft(&Spec{text:MARKER,..Spec::default()}).to_string()),
  ("列记录","/v1/native-review/records".to_owned(),"GET",None,String::new()),
  ("看战绩","/v1/native-review/statistics".to_owned(),"GET",None,String::new()),
  ("看检索进度",format!("/v1/native-review/searches/{}",Uuid::new_v4()),"GET",None,String::new()),
  // 这条不要身份，走的是另一条路；它照样要查库，也照样不许把死掉的连接说出来。
  ("能力清单","/v1/capabilities".to_owned(),"GET",None,String::new()),
 ];
 for (what,path,method,key,body) in dark {
  let (status,v)=text(&offline,&path,method,token,key,body).await;
  assert_eq!(clean(what,status.as_u16(),&v),"temporarily_unavailable","{what} 该说的是「这会儿不行」，不是为什么不行");
  assert_eq!(status.as_u16(),503,"{what}");
 }
 dead.pool.close().await;
 w.close().await;
}
