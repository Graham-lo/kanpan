//! 复盘那几条回归用例共用的夹具：隔离库（`ops/test.py` 建的那个）、非特权运行角色、
//! 注入式行情，外加一套「把时间线搬到过去」的工具。
//!
//! 夹具风格跟着 `accounts.rs` / `auth_security.rs`：同一个库、随机用户名、
//! `--test-threads=1` 一条一条跑。行情**从不**走真网络——所有涨跌都是用例自己写死的，
//! 否则今天绿明天红的断言等于没有断言。
//!
//! 时间线这件事要多说一句。记录只能按**真实的现在**创建（校验要过：区间不能在未来、
//! 图的右沿不能比草稿还新），可是「到期之后 worker 怎么判」又必须让到期时刻落在过去。
//! 所以这里的办法是：先老老实实走一遍 HTTP 创建，再用 [`retime`] 把这条记录的
//! 提交时刻与到期时刻整体搬到过去——worker 读的正是记录里的这几个数。
#![allow(dead_code)]
use axum::{Router,body::Body,extract::ConnectInfo,http::{Request,StatusCode}};
use chrono::{DateTime,Utc};
use http_body_util::BodyExt;
use kanpan_api::{AppState,crypto::Secrets};
use scorebook_core::{domain::criteria::Bar,error::Error,market::{MarketDataProvider,ProviderFuture}};
use serde_json::{Value,json};
use sqlx::PgPool;
use std::net::SocketAddr;
use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
use tower::ServiceExt;
use uuid::Uuid;

pub struct World {pub s:AppState,pub app:Router,pub admin:PgPool}
impl World {
 /// 用例结束就把两个池子还回去：整套测试共用一台 PostgreSQL，连接数是公共资源。
 pub async fn close(self) {self.s.pool.close().await;self.admin.close().await;}
}
/// 隔离库 + 非特权角色，和 `auth_security.rs` 的 boot 一致。
pub async fn boot()->World {
 let admin_url=std::env::var("KANPAN_TEST_ADMIN_URL").expect("Run ops/test.py; an isolated database is required");
 let admin=PgPool::connect(&admin_url).await.unwrap();sqlx::migrate!().run(&admin).await.unwrap();
 let role=std::env::var("KANPAN_TEST_ROLE").unwrap();assert!(role.chars().all(|c|c.is_ascii_alphanumeric()||c=='_'));
 for sql in [format!("GRANT USAGE ON SCHEMA public TO {role}"),format!("GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO {role}"),format!("GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO {role}")] {sqlx::query(&sql).execute(&admin).await.unwrap();}
 let pool=sqlx::postgres::PgPoolOptions::new().max_connections(5).connect(&std::env::var("KANPAN_TEST_DATABASE_URL").unwrap()).await.unwrap();
 let secrets=Arc::new(Secrets{pepper:vec![31;32],encryption:[43;32]});let dummy_hash=Arc::new(secrets.hash_password("dummy123456").unwrap());
 let s=AppState{pool,secrets,dummy_hash};let app=kanpan_api::router(s.clone());World{s,app,admin}
}
/// 一次请求。`key` 是幂等键，只有写接口要。
pub async fn request(app:&Router,path:&str,method:&str,token:Option<&str>,key:Option<Uuid>,body:Value)->(StatusCode,Value) {
 raw(app,path,method,token,key,body.to_string()).await
}
/// 同上，但正文按原样发出去——正文根本不是 JSON 的那条用例要用。
pub async fn raw(app:&Router,path:&str,method:&str,token:Option<&str>,key:Option<Uuid>,body:String)->(StatusCode,Value) {
 let (status,text)=text(app,path,method,token,key,body).await;
 (status,serde_json::from_str(&text).unwrap_or_else(|_|json!({"nonJSON":text})))
}
/// 连正文原文一起给出来：D.5 要断言「屏幕上出现的每一个字节」。
pub async fn text(app:&Router,path:&str,method:&str,token:Option<&str>,key:Option<Uuid>,body:String)->(StatusCode,String) {
 let mut req=Request::builder().uri(path).method(method).header("content-type","application/json");
 if let Some(key)=key {req=req.header("idempotency-key",key.to_string());}
 if let Some(token)=token {req=req.header("authorization",format!("Bearer {token}"));}
 let mut req=req.body(Body::from(body)).unwrap();
 req.extensions_mut().insert(ConnectInfo("127.0.0.1:19000".parse::<SocketAddr>().unwrap()));
 let result=app.clone().oneshot(req).await.unwrap();let status=result.status();
 let bytes=result.into_body().collect().await.unwrap().to_bytes();
 (status,String::from_utf8_lossy(&bytes).into_owned())
}
pub fn name(prefix:&str)->String {format!("{prefix}_{}",&Uuid::new_v4().simple().to_string()[..8])}
pub struct Account {pub token:String,pub id:Uuid}
/// 注册一个账号。注册按来源地址限额（每分钟 30 次），一套回归跑下来会超，
/// 所以每个账号自带一个不重样的对端地址，各算各的额度。
pub async fn signup(app:&Router,prefix:&str)->Account {
 static NEXT:AtomicUsize=AtomicUsize::new(0);
 let n=NEXT.fetch_add(1,Ordering::SeqCst);
 let peer=format!("198.51.{}.{}:19000",n/250%250,n%250+1);
 let device=json!({"id":Uuid::new_v4(),"name":"probe","secret":kanpan_api::crypto::random_token()});
 let body=json!({"username":name(prefix),"password":"Passcode123","device":device});
 let mut req=Request::builder().uri("/v1/auth/register").method("POST").header("content-type","application/json").body(Body::from(body.to_string())).unwrap();
 req.extensions_mut().insert(ConnectInfo(peer.parse::<SocketAddr>().unwrap()));
 let result=app.clone().oneshot(req).await.unwrap();let status=result.status();
 let bytes=result.into_body().collect().await.unwrap().to_bytes();
 let v:Value=serde_json::from_slice(&bytes).unwrap();assert_eq!(status,201,"{v}");
 Account{token:v["data"]["accessToken"].as_str().unwrap().into(),id:Uuid::parse_str(v["data"]["user"]["id"].as_str().unwrap()).unwrap()}
}

/// 注入的行情。哪一条路径回什么，由用例自己说了算。
pub enum Reply {
 /// 一整库写死的 K 线，按请求区间切一段给出去，并声明覆盖完整。
 Bars(Vec<Bar>),
 /// 同样切一段，但声明覆盖不完整。
 Partial(Vec<Bar>),
 /// 按**请求的周期**现生一段起伏的行情。几何模型那几条要的是形状不是价位，
 /// 而且同一个窗口每次生成的必须一模一样，否则「同输入同分数」就无从断言。
 Wave,
 /// 原样回一段 JSON，逐笔成交用。
 Raw(Value),
 /// 上游明确拒绝（451 那一类）：不可重试。
 Blocked,
 /// 上游这会儿不可用：可重试。
 Down,
 /// 这条路径根本不该被问到。
 Never,
}
/// 让 worker 停在「已经读出记录、还没写回结论」那一刻的闸门。
#[derive(Default)]
pub struct Gate {pub entered:tokio::sync::Notify,pub release:tokio::sync::Notify}
pub struct Market {pub klines:Reply,pub trades:Reply,calls:AtomicUsize,gate:Option<Arc<Gate>>}
impl Market {
 fn new(klines:Reply,trades:Reply)->Self {Self{klines,trades,calls:AtomicUsize::new(0),gate:None}}
 pub fn bars(v:Vec<Bar>)->Self {Self::new(Reply::Bars(v),Reply::Never)}
 pub fn partial(v:Vec<Bar>)->Self {Self::new(Reply::Partial(v),Reply::Never)}
 pub fn wave()->Self {Self::new(Reply::Wave,Reply::Never)}
 pub fn ticks(v:Value)->Self {Self::new(Reply::Never,Reply::Raw(v))}
 pub fn refusing(r:Reply)->Self {Self::new(r,Reply::Never)}
 /// 谁也不许问的行情源：用来证明某条分支根本没出站。
 pub fn silent()->Self {Self::new(Reply::Never,Reply::Never)}
 pub fn held(mut self,gate:&Arc<Gate>)->Self {self.gate=Some(gate.clone());self}
 pub fn calls(&self)->usize {self.calls.load(Ordering::SeqCst)}
}
fn cut(v:&[Bar],start:DateTime<Utc>,end:DateTime<Utc>)->Vec<Bar> {v.iter().filter(|b|b.start>=start&&b.end<=end).cloned().collect()}
fn reply(r:&Reply,interval:&str,start:DateTime<Utc>,end:DateTime<Utc>,what:&str)->scorebook_core::error::Result<Value> {
 match r {
  Reply::Bars(v)=>Ok(json!({"coverage_complete":true,"bars":cut(v,start,end)})),
  Reply::Partial(v)=>Ok(json!({"coverage_complete":false,"bars":cut(v,start,end)})),
  Reply::Wave=>Ok(json!({"coverage_complete":true,"bars":wave(interval,start.timestamp_millis(),end.timestamp_millis())})),
  Reply::Raw(v)=>Ok(v.clone()),
  Reply::Blocked=>Err(Error::bad("upstream_refused")),
  Reply::Down=>Err(Error::transient("upstream_down")),
  Reply::Never=>panic!("这条分支不该去问行情（{what}）"),
 }
}
impl MarketDataProvider for Market {
 fn klines<'a>(&'a self,_:&'a str,_:&'a str,interval:&'a str,start:DateTime<Utc>,end:DateTime<Utc>)->ProviderFuture<'a> {
  Box::pin(async move {
   self.calls.fetch_add(1,Ordering::SeqCst);
   if let Some(g)=&self.gate {g.entered.notify_one();g.release.notified().await;}
   reply(&self.klines,interval,start,end,"klines")
  })
 }
 fn trades<'a>(&'a self,_:&'a str,_:&'a str,start:DateTime<Utc>,end:DateTime<Utc>)->ProviderFuture<'a> {
  Box::pin(async move {
   self.calls.fetch_add(1,Ordering::SeqCst);
   if let Some(g)=&self.gate {g.entered.notify_one();g.release.notified().await;}
   reply(&self.trades,"",start,end,"trades")
  })
 }
 fn exchange_info<'a>(&'a self,_:&'a str)->ProviderFuture<'a> {Box::pin(async{Ok(json!({}))})}
 fn tickers_24h<'a>(&'a self,_:&'a str)->ProviderFuture<'a> {Box::pin(async{Ok(json!({}))})}
}
pub fn at(ms:i64)->DateTime<Utc> {DateTime::from_timestamp_millis(ms).unwrap()}
/// 一根 K 线。开盘价取收盘价，影线由 high/low 给出，正好满足
/// 「最高不低于实体、最低不高于实体」这条合法性检查。
pub fn bar(start:i64,size:i64,high:f64,low:f64,close:f64)->Bar {
 Bar{start:at(start),end:at(start+size),open:close.to_string(),high:high.to_string(),low:low.to_string(),close:close.to_string(),volume:Some("1".into())}
}
/// 从 start 起连续的一串 K 线，每根「最高 / 最低 / 收盘」由用例写死。
pub fn series(start:i64,size:i64,specs:&[(f64,f64,f64)])->Vec<Bar> {
 specs.iter().enumerate().map(|(n,(h,l,c))|bar(start+n as i64*size,size,*h,*l,*c)).collect()
}
/// 起伏的行情：形状只取决于这根 K 线的绝对起点，所以同一个窗口问几次都一样。
pub fn wave(interval:&str,start:i64,end:i64)->Vec<Bar> {
 let size=size(interval);let mut cursor=start;let mut bars=vec![];
 while cursor<end {
  let n=(cursor.div_euclid(size)%97) as f64;let base=100.0+n*0.3+(n*0.6).sin();
  bars.push(Bar{start:at(cursor),end:at(cursor+size),open:base.to_string(),high:(base+2.0).to_string(),low:(base-1.0).to_string(),close:(base+0.5).to_string(),volume:Some("100".into())});
  cursor+=size;
 } bars
}

/// 一条记录的骨架。默认是「1 分钟图、做多、收盘确认、100 进 110 出 90 止损」。
pub struct Spec {
 pub interval:&'static str,pub venue:&'static str,pub symbol:&'static str,
 pub direction:&'static str,pub confirmation:&'static str,
 pub reference:f64,pub target:f64,pub invalidation:f64,
 /// 草稿写下的时刻；0 表示「现在」。两条记录传同一个值，它们的规则签名才会完全相同。
 pub anchor:i64,
 /// 观察窗口长度（毫秒），从 anchor 起算。
 pub span:i64,
 /// 圈了多少根。几何检索要至少十六根。
 pub bars:usize,
 pub text:&'static str,
}
impl Default for Spec {
 fn default()->Self {Self{interval:"1m",venue:"binance",symbol:"BTCUSDT",direction:"long",confirmation:"bar_close",reference:100.0,target:110.0,invalidation:90.0,anchor:0,span:3_600_000,bars:3,text:""}}
}
/// 固定长度周期的毫秒数。用例只用这几档，别的周期（1w/1M）长度不固定，不在这里猜。
pub fn size(interval:&str)->i64 {
 match interval {"1m"=>60_000,"5m"=>300_000,"15m"=>900_000,"1h"=>3_600_000,"4h"=>14_400_000,"1d"=>86_400_000,_=>panic!("用例只用固定长度的周期")}
}
pub fn draft(spec:&Spec)->Value {
 let now=if spec.anchor>0 {spec.anchor} else {Utc::now().timestamp_millis()};
 let size=size(spec.interval);let end=now/size*size;
 json!({"id":Uuid::new_v4(),"range":{"venue":spec.venue,"market":"usd_m","symbol":spec.symbol,"interval":spec.interval,"start":end-spec.bars as i64*size,"end":end,"bars":spec.bars},
  "rule":{"version":"criteria-v2","direction":spec.direction,"confirmation":spec.confirmation,"reference":spec.reference,"target":spec.target,"invalidation":spec.invalidation,"expires":now+spec.span},
  "text":spec.text,"origin":"chart_first","created":now})
}
/// 走真正的 HTTP 建一条记录（校验、幂等、episode、两条队列任务都经过）。
pub async fn place(w:&World,a:&Account,spec:&Spec)->Uuid {
 let body=draft(spec);let (status,v)=request(&w.app,"/v1/native-review/records","POST",Some(&a.token),Some(Uuid::new_v4()),body.clone()).await;
 assert_eq!(status,200,"{v}");Uuid::parse_str(body["id"].as_str().unwrap()).unwrap()
}
/// 把一条记录的时间线整体搬到过去。worker 读的就是记录里的这三个数。
pub async fn retime(w:&World,a:&Account,id:Uuid,created:i64,submitted:i64,expires:i64) {
 sqlx::query("UPDATE review_records SET submitted=$3,record=jsonb_set(jsonb_set(jsonb_set(record,'{submitted}',to_jsonb($3::bigint)),'{draft,created}',to_jsonb($4::bigint)),'{draft,rule,expires}',to_jsonb($5::bigint)) WHERE user_id=$1 AND id=$2")
  .bind(a.id).bind(id).bind(submitted).bind(created).bind(expires).execute(&w.admin).await.unwrap();
}
/// 直接改记录里的一个字段。用来摆出「worker 会写成这样」的终态，好单测统计口径。
pub async fn patch(w:&World,a:&Account,id:Uuid,path:&str,value:Value) {
 sqlx::query(&format!("UPDATE review_records SET record=jsonb_set(record,'{path}',$3) WHERE user_id=$1 AND id=$2"))
  .bind(a.id).bind(id).bind(value).execute(&w.admin).await.unwrap();
}
/// 把队列收拢到这一条记录的这一种任务上：别的任务都收掉，这一条立刻到期，
/// 调度器只指向我。认领是 SKIP LOCKED 抢一个 owner，不这么摆就不确定跑到谁头上。
pub async fn focus(w:&World,a:&Account,id:Uuid,kind:&str) {
 sqlx::query("UPDATE review_jobs SET finished=true WHERE NOT(user_id=$1 AND record_id=$2 AND kind=$3)").bind(a.id).bind(id).bind(kind).execute(&w.admin).await.unwrap();
 sqlx::query("UPDATE review_jobs SET finished=false,lease_id=NULL,lease_until=NULL,next_at=now(),attempts=0 WHERE user_id=$1 AND record_id=$2 AND kind=$3").bind(a.id).bind(id).bind(kind).execute(&w.admin).await.unwrap();
 sqlx::query("UPDATE review_dispatch SET next_at=CASE WHEN user_id=$1 THEN now() ELSE now()+interval '1 day' END").bind(a.id).execute(&w.admin).await.unwrap();
}
/// 认领并跑掉一条任务。
pub async fn run(w:&World,market:&Market)->bool {kanpan_api::review_worker::run_one(&w.s,market).await.unwrap()}
/// 只跑这条记录的裁定任务，回来时给出库里那份记录。
pub async fn assess(w:&World,a:&Account,id:Uuid,market:&Market)->Value {
 focus(w,a,id,"assess").await;assert!(run(w,market).await,"应当认领到这条裁定任务");stored(w,a,id).await
}
/// 只跑这条记录的建索引任务（资格也是在那里定的）。
pub async fn index(w:&World,a:&Account,id:Uuid,market:&Market)->Value {
 focus(w,a,id,"index").await;assert!(run(w,market).await,"应当认领到这条建索引任务");stored(w,a,id).await
}
pub async fn stored(w:&World,a:&Account,id:Uuid)->Value {
 sqlx::query_scalar("SELECT record FROM review_records WHERE user_id=$1 AND id=$2").bind(a.id).bind(id).fetch_one(&w.admin).await.unwrap()
}
pub struct JobRow {pub finished:bool,pub delay:f64,pub leased:bool,pub attempts:i32}
pub async fn job(w:&World,a:&Account,id:Uuid,kind:&str)->JobRow {
 let row:(bool,f64,Option<Uuid>,i32)=sqlx::query_as("SELECT finished,extract(epoch from next_at-now())::float8,lease_id,attempts FROM review_jobs WHERE user_id=$1 AND record_id=$2 AND kind=$3")
  .bind(a.id).bind(id).bind(kind).fetch_one(&w.admin).await.unwrap();
 JobRow{finished:row.0,delay:row.1,leased:row.2.is_some(),attempts:row.3}
}
pub async fn stats(w:&World,a:&Account)->Value {
 let (status,v)=request(&w.app,"/v1/native-review/statistics","GET",Some(&a.token),None,json!({})).await;
 assert_eq!(status,200,"{v}");v["data"].clone()
}
/// 结论那几个字段，断言起来短一点。
pub fn outcome(record:&Value)->String {record["assessment"]["outcome"].as_str().unwrap_or("pending").to_owned()}
pub fn reason(record:&Value)->String {record["assessment"]["reason"].as_str().unwrap_or_default().to_owned()}
pub fn event_at(record:&Value)->Option<i64> {record["assessment"]["eventAt"].as_i64()}
/// 统计证明里一组的成员集合。proof 里存的是 `{"call_id":…,"claim_no":0}`。
pub fn ids(group:&Value,field:&str)->std::collections::BTreeSet<String> {
 group[field].as_array().into_iter().flatten().map(|v|v["call_id"].as_str().unwrap_or_default().to_owned()).collect()
}
/// 按标题里出现的品种找一组统计。
pub fn group_of<'a>(groups:&'a Value,symbol:&str)->&'a Value {
 groups.as_array().expect("分组是一个数组").iter().find(|g|g["title"].as_str().is_some_and(|t|t.contains(symbol))).unwrap_or_else(||panic!("没有 {symbol} 这一组：{groups}"))
}
