mod review_common;
use review_common::{boot,signup,request};
use serde_json::{Value,json};
use axum::{body::Body,http::Request};
use http_body_util::BodyExt;
use tower::ServiceExt;

#[tokio::test]
async fn shares_are_private_make_friends_and_keep_independent_lines() {
 let w=boot().await;
 let a=signup(&w.app,"qa_share_a").await;let b=signup(&w.app,"qa_share_b").await;let c=signup(&w.app,"qa_share_c").await;
 let name: String=sqlx::query_scalar("SELECT email FROM account_users WHERE id=$1").bind(b.id).fetch_one(&w.admin).await.unwrap();
 let drawing=json!({"id":"original","kind":"trend","points":[{"t":1800000000000i64,"p":100},{"t":1800003600000i64,"p":110}],"lineWidth":1.3,"dash":"solid","filled":true,"locked":false,"hidden":false,"levels":[]});
 let payload=json!({"to":name,"symbol":"BTCUSDT","interval":"1h","view":{"from":1800000000000i64,"to":1800003600000i64},"drawings":[drawing],"alerted":["original"]});
 for route in ["/v1/friends","/v1/shares/inbox"] {assert_eq!(request(&w.app,route,"GET",None,None,json!({})).await.0,401);}
 let mut bad=payload.clone();bad["drawings"][0]["points"]=json!([]);
 assert_eq!(request(&w.app,"/v1/shares","POST",Some(&a.token),None,bad).await.0,400);
 let (status,result)=request(&w.app,"/v1/shares","POST",Some(&a.token),None,payload.clone()).await;assert_eq!(status,200,"{result}");
 let id=result["data"]["id"].as_str().unwrap();assert_eq!(id.len(),22);assert!(id.bytes().all(|b|b.is_ascii_alphanumeric()));
 for user in [&a,&b] {
  let (_,v)=request(&w.app,"/v1/friends","GET",Some(&user.token),None,json!({})).await;
  assert_eq!(v["data"].as_array().unwrap().len(),1,"first send makes reciprocal friends");
 }
 let (_,inbox)=request(&w.app,"/v1/shares/inbox","GET",Some(&b.token),None,json!({})).await;
 assert_eq!(inbox["data"]["items"][0]["drawings"],payload["drawings"]);
 for user in [&a,&c] {
  let (_,v)=request(&w.app,"/v1/shares/inbox","GET",Some(&user.token),None,json!({})).await;assert_eq!(v["data"]["items"],json!([]));
  assert_eq!(request(&w.app,&format!("/v1/shares/{id}/kept"),"POST",Some(&user.token),None,json!({})).await.0,404);
 }
 // 不加 WHERE 的真实 RLS 查询：第三人看不见，双方可见；无上下文看不到任何信。
 for (user,count) in [(&a,1i64),(&b,1),(&c,0)] {
  let mut tx=w.s.personal(user.id).await.unwrap();
  let n:i64=sqlx::query_scalar("SELECT count(*) FROM shares").fetch_one(&mut *tx).await.unwrap();assert_eq!(n,count);
  let n:i64=sqlx::query_scalar("SELECT count(*) FROM friendships").fetch_one(&mut *tx).await.unwrap();assert_eq!(n,count);
 }
 assert_eq!(sqlx::query_scalar::<_,i64>("SELECT count(*) FROM shares").fetch_one(&w.s.pool).await.unwrap(),0);
 let shot=vec![0xff,0xd8,0xff,0xe0,0xff,0xd9];
 for (token,expected) in [(&a.token,200),(&b.token,404),(&c.token,404)] {
  let req=Request::builder().method("PUT").uri(format!("/v1/shares/{id}/shot")).header("authorization",format!("Bearer {token}")).header("content-type","image/jpeg").body(Body::from(shot.clone())).unwrap();
  assert_eq!(w.app.clone().oneshot(req).await.unwrap().status(),expected);
 }
 for (token,expected) in [(&a.token,200),(&b.token,200),(&c.token,404)] {
  let req=Request::builder().uri(format!("/v1/shares/{id}/shot")).header("authorization",format!("Bearer {token}")).body(Body::empty()).unwrap();
  let r=w.app.clone().oneshot(req).await.unwrap();assert_eq!(r.status(),expected);if expected==200 {assert_eq!(r.into_body().collect().await.unwrap().to_bytes(),shot);}
 }
 // 留下是收件人的状态；重复操作不改时间，并可在增量拉取中收到它。
 assert_eq!(request(&w.app,&format!("/v1/shares/{id}/kept"),"POST",Some(&b.token),None,json!({})).await.0,200);
 let cursor=inbox["data"]["cursor"].as_str().unwrap().replace('+',"%2B");
 let (_,updated)=request(&w.app,&format!("/v1/shares/inbox?after={cursor}"),"GET",Some(&b.token),None,json!({})).await;
 assert!(updated["data"]["items"][0]["keptAt"].is_string());
 // 删朋友只删自己那一行，历史信还在。
 assert_eq!(request(&w.app,&format!("/v1/friends/{name}"),"DELETE",Some(&a.token),None,json!({})).await.0,200);
 let (_,v)=request(&w.app,"/v1/friends","GET",Some(&b.token),None,json!({})).await;assert_eq!(v["data"].as_array().unwrap().len(),1);
 // 90 天清理只动未留下的信。
 let (_,v)=request(&w.app,"/v1/shares","POST",Some(&a.token),None,payload).await;let disposable=v["data"]["id"].as_str().unwrap();
 sqlx::query("UPDATE shares SET created_at=now()-interval '91 days' WHERE id=$1 OR id=$2").bind(id).bind(disposable).execute(&w.admin).await.unwrap();
 kanpan_api::maintenance::cleanup(&w.s).await.unwrap();
 let left:Vec<String>=sqlx::query_scalar("SELECT id FROM shares WHERE id=$1 OR id=$2").bind(id).bind(disposable).fetch_all(&w.admin).await.unwrap();assert_eq!(left,vec![id]);
 // 发送限流：同一个账号 20 次之后被挡住。
 let mut status=0;for _ in 0..20 {let body:Value=json!({"to":name,"symbol":"BTCUSDT","interval":"1h","view":{"from":1,"to":2},"drawings":[drawing],"alerted":[]});status=request(&w.app,"/v1/shares","POST",Some(&a.token),None,body).await.0.as_u16();}
 assert_eq!(status,429);
 w.close().await;
}
