mod review_common;
use review_common::{boot,signup,request};
use serde_json::json;
use axum::{body::Body,http::Request,extract::ConnectInfo};
use http_body_util::BodyExt;
use std::net::SocketAddr;
use tower::ServiceExt;

/// 导出只含自己的东西；重置密码吊销全部旧会话、新密码能登录。
#[tokio::test]
async fn export_is_personal_and_reset_password_rotates_everything() {
 let w=boot().await;
 let a=signup(&w.app,"qa_export_a").await;let b=signup(&w.app,"qa_export_b").await;let c=signup(&w.app,"qa_export_c").await;
 let name=|id|{let admin=w.admin.clone();async move {sqlx::query_scalar::<_,String>("SELECT email FROM account_users WHERE id=$1").bind(id).fetch_one(&admin).await.unwrap()}};
 let (a_name,b_name)=(name(a.id).await,name(b.id).await);
 assert_eq!(request(&w.app,"/v1/auth/me/export","GET",None,None,json!({})).await.0,401);
 let drawing=json!({"id":"x","kind":"trend","points":[{"t":1800000000000i64,"p":100},{"t":1800003600000i64,"p":110}],"lineWidth":1.3,"dash":"solid","filled":true,"locked":false,"hidden":false,"levels":[]});
 let payload=json!({"to":b_name,"symbol":"BTCUSDT","interval":"1h","view":{"from":1800000000000i64,"to":1800003600000i64},"drawings":[drawing],"alerted":[]});
 assert_eq!(request(&w.app,"/v1/shares","POST",Some(&a.token),None,payload).await.0,200);
 let (status,v)=request(&w.app,"/v1/auth/me/export","GET",Some(&a.token),None,json!({})).await;assert_eq!(status,200,"{v}");
 let d=&v["data"];
 assert_eq!(d["format"],"hkline-export-1");assert_eq!(d["account"]["username"],json!(a_name));
 assert_eq!(d["friends"],json!([b_name]));
 assert_eq!(d["shares"][0]["direction"],"sent");assert_eq!(d["shares"][0]["with"],json!(b_name));
 assert!(v.to_string().find("password").is_none(),"凭据不进导出");
 let (_,v)=request(&w.app,"/v1/auth/me/export","GET",Some(&b.token),None,json!({})).await;assert_eq!(v["data"]["shares"][0]["direction"],"received");
 let (_,v)=request(&w.app,"/v1/auth/me/export","GET",Some(&c.token),None,json!({})).await;
 assert_eq!(v["data"]["shares"],json!([]));assert_eq!(v["data"]["friends"],json!([]));assert_eq!(v["data"]["sync"],json!([]));
 // 重置密码：旧令牌作废、旧密码不行、新密码可以。
 let fresh=kanpan_api::auth::reset_password(&w.s,&a_name).await.unwrap();
 assert_eq!(request(&w.app,"/v1/auth/me","GET",Some(&a.token),None,json!({})).await.0,401);
 let login=|password:String|{let app=w.app.clone();let user=a_name.clone();async move {
  let device=json!({"id":uuid::Uuid::new_v4(),"name":"probe","secret":kanpan_api::crypto::random_token()});
  let mut req=Request::builder().uri("/v1/auth/login").method("POST").header("content-type","application/json").body(Body::from(json!({"username":user,"password":password,"device":device}).to_string())).unwrap();
  req.extensions_mut().insert(ConnectInfo("198.51.200.9:19000".parse::<SocketAddr>().unwrap()));
  let r=app.oneshot(req).await.unwrap();let status=r.status();let _=r.into_body().collect().await;status
 }};
 assert_eq!(login("Passcode123".into()).await,401);
 assert_eq!(login(fresh).await,200);
 assert!(kanpan_api::auth::reset_password(&w.s,"no_such_user_zz").await.is_err());
 w.close().await;
}
