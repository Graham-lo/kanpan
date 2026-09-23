//! P3.7 复盘交互的服务端一半：修订记录（只读）、补图（每条最多三张）、「已判定」筛选。
//!
//! 每一条都在问同一件事：别人的东西永远读不到、改不动；自己的额度不会被重发吃掉。
mod review_common;
use base64::{Engine,engine::general_purpose::STANDARD};
use review_common::*;
use serde_json::json;
use uuid::Uuid;

/// 一张最小的「JPEG」：魔数对上就收，内容服务端不解码。
fn jpeg(extra:usize)->String {let mut b=vec![0xff,0xd8,0xff,0xe0];b.resize(4+extra,7);b.push(0xff);b.push(0xd9);STANDARD.encode(b)}

#[tokio::test]
async fn review_revisions_are_private_and_ordered() {
 let w=boot().await;let a=signup(&w.app,"rev").await;let b=signup(&w.app,"rev").await;
 let id=place(&w,&a,&Spec::default()).await;
 let body=json!({"expectedRevision":0,"reflection":{"note":"第一版","nextTime":"等回踩","publishedAt":null,"revision":0},"publish":true});
 let (status,v)=request(&w.app,&format!("/v1/native-review/records/{id}/reflection"),"POST",Some(&a.token),Some(Uuid::new_v4()),body).await;
 assert_eq!(status,200,"{v}");
 let (status,v)=request(&w.app,&format!("/v1/native-review/records/{id}/revisions"),"GET",Some(&a.token),None,json!(null)).await;
 assert_eq!(status,200,"{v}");
 let kinds:Vec<&str>=v["data"]["revisions"].as_array().unwrap().iter().map(|r|r["kind"].as_str().unwrap()).collect();
 assert_eq!(kinds.first(),Some(&"created"),"第一版永远是记下时的规则：{v}");
 assert!(kinds.contains(&"reflection"),"复盘那一版要在：{v}");
 assert!(v["data"]["revisions"].as_array().unwrap().iter().all(|r|r["at"].as_i64().unwrap()>0));
 // 别人拿着 id 来问：和详情一样是 404，连「有这条记录」都不透露。
 let (status,_)=request(&w.app,&format!("/v1/native-review/records/{id}/revisions"),"GET",Some(&b.token),None,json!(null)).await;
 assert_eq!(status,404);
 let (status,_)=request(&w.app,&format!("/v1/native-review/records/{id}/revisions"),"GET",None,None,json!(null)).await;
 assert_eq!(status,401);
 w.close().await;
}

#[tokio::test]
async fn review_attachments_limit_idempotency_and_isolation() {
 let w=boot().await;let a=signup(&w.app,"att").await;let b=signup(&w.app,"att").await;
 let id=place(&w,&a,&Spec::default()).await;
 let put=|who:&Account,att:Uuid,record:Uuid,image:String|{let token=who.token.clone();let app=w.app.clone();async move {
  request(&app,"/v1/native-review/attachments","POST",Some(&token),None,json!({"id":att,"recordId":record,"image":image})).await}};
 let first=Uuid::new_v4();
 let (status,v)=put(&a,first,id,jpeg(32)).await;assert_eq!(status,200,"{v}");
 // 同一个 id 重发：不算第二张。
 let (status,v)=put(&a,first,id,jpeg(32)).await;assert_eq!(status,200,"{v}");
 for _ in 0..2 {let (status,v)=put(&a,Uuid::new_v4(),id,jpeg(64)).await;assert_eq!(status,200,"{v}");}
 let (status,v)=put(&a,Uuid::new_v4(),id,jpeg(64)).await;assert_eq!(status,409,"第四张要拒：{v}");assert_eq!(v["error"]["code"],"attachment_limit","{v}");
 // 格式与大小。
 let (status,v)=put(&a,Uuid::new_v4(),id,STANDARD.encode(b"GIF89a....")).await;assert_eq!(status,400);assert_eq!(v["error"]["code"],"invalid_attachment","{v}");
 let (status,v)=put(&a,Uuid::new_v4(),id,jpeg(5*1024*1024)).await;assert_eq!(status,400,"{v}");assert_eq!(v["error"]["code"],"attachment_too_large","{v}");
 // 列表只有元数据，三张，按上传顺序。
 let (status,v)=request(&w.app,&format!("/v1/native-review/records/{id}/attachments"),"GET",Some(&a.token),None,json!(null)).await;
 assert_eq!(status,200,"{v}");let items=v["data"]["items"].as_array().unwrap();assert_eq!(items.len(),3,"{v}");
 assert_eq!(items[0]["id"],json!(first));assert_eq!(items[0]["mime"],"image/jpeg");assert!(items[0].get("image").is_none());
 let (status,v)=request(&w.app,&format!("/v1/native-review/attachments/{first}"),"GET",Some(&a.token),None,json!(null)).await;
 assert_eq!(status,200);assert_eq!(v["data"]["image"],json!(jpeg(32)));
 // 另一个人：读不到、删不掉、也挂不到别人的记录上。
 let (status,_)=request(&w.app,&format!("/v1/native-review/attachments/{first}"),"GET",Some(&b.token),None,json!(null)).await;assert_eq!(status,404);
 let (status,_)=request(&w.app,&format!("/v1/native-review/records/{id}/attachments"),"GET",Some(&b.token),None,json!(null)).await;assert_eq!(status,404);
 let (status,v)=request(&w.app,&format!("/v1/native-review/attachments/{first}"),"DELETE",Some(&b.token),None,json!(null)).await;assert_eq!(status,200);assert_eq!(v["data"]["deleted"],false);
 let (status,_)=put(&b,Uuid::new_v4(),id,jpeg(8)).await;assert_eq!(status,404);
 // 删掉一张，额度回来一格；再删一次仍然 ok。
 let (status,v)=request(&w.app,&format!("/v1/native-review/attachments/{first}"),"DELETE",Some(&a.token),None,json!(null)).await;assert_eq!(status,200);assert_eq!(v["data"]["deleted"],true);
 let (status,v)=request(&w.app,&format!("/v1/native-review/attachments/{first}"),"DELETE",Some(&a.token),None,json!(null)).await;assert_eq!(status,200);assert_eq!(v["data"]["deleted"],false);
 let (status,v)=put(&a,Uuid::new_v4(),id,jpeg(8)).await;assert_eq!(status,200,"{v}");
 // 导出只带元数据。
 let (status,v)=request(&w.app,"/v1/auth/me/export","GET",Some(&a.token),None,json!(null)).await;
 assert_eq!(status,200);let exported=v["data"]["review"]["attachments"].as_array().unwrap();assert_eq!(exported.len(),3);assert!(exported[0].get("bytes").is_none());
 w.close().await;
}

#[tokio::test]
async fn review_decided_filter() {
 let w=boot().await;let a=signup(&w.app,"dec").await;
 let open=place(&w,&a,&Spec::default()).await;
 let done=place(&w,&a,&Spec{symbol:"ETHUSDT",..Spec::default()}).await;
 patch(&w,&a,done,"{assessment}",json!({"outcome":"target_hit"})).await;
 patch(&w,&a,done,"{reflection}",json!({"note":"对了","nextTime":"","publishedAt":1,"revision":1})).await;
 let ids=|v:&serde_json::Value|v["data"]["records"].as_array().unwrap().iter().map(|r|r["draft"]["id"].as_str().unwrap_or_default().to_string()).collect::<Vec<_>>();
 let (status,v)=request(&w.app,"/v1/native-review/records?decided=true","GET",Some(&a.token),None,json!(null)).await;
 assert_eq!(status,200,"{v}");let got=ids(&v);
 assert!(got.iter().any(|x|x==&done.to_string()),"已判定要在：{v}");assert!(!got.iter().any(|x|x==&open.to_string()),"没判定的不在：{v}");
 let (status,v)=request(&w.app,"/v1/native-review/records?todo=true","GET",Some(&a.token),None,json!(null)).await;
 assert_eq!(status,200);let got=ids(&v);assert!(got.iter().any(|x|x==&open.to_string()));assert!(!got.iter().any(|x|x==&done.to_string()));
 w.close().await;
}
