//! 复盘图片的内存压测（2026-09-26 后端压测）。都在隔离库里跑。
//!
//! 这两条路的共同点是「一次请求在进程里摊开几十 MB」：一张 5 MB 的补图从请求体到
//! base64 串、解码后的字节、交给数据库的那份拷贝要摊四份；一次导出要把一个人的全部
//! 数据读成 JSON 树再序列化。单独一次都不大，要看的是「很多次同时到」时进程涨多少——
//! 线上 serve 单元 `MemoryMax=1G`，订单流跟踪也在同一个进程里，超了是整个进程一起被杀。
mod review_common;
use axum::{Router,body::{Body,Bytes},extract::ConnectInfo,http::{Request,StatusCode}};
use base64::{Engine,engine::general_purpose::STANDARD};
use http_body_util::BodyExt;
use review_common::*;
use serde_json::json;
use std::net::SocketAddr;
use std::sync::{Arc,atomic::{AtomicBool,AtomicU64,Ordering}};
use tower::ServiceExt;
use uuid::Uuid;

/// 本进程此刻实打实占着的内存（KiB）。
///
/// Linux 上就是 `ps` 的 RSS。macOS 上 RSS 不作数：分配器释放的页只打个「可回收」
/// 记号、要等系统有内存压力才真的拿走，`ps` 照样算在 RSS 里——纯 serde_json 解析
/// 一份 12 MB 再丢掉，RSS 每轮都「涨」11 MiB。所以 macOS 上读 `footprint`（活动监视器
/// 与内存压力杀进程看的就是这个数），它不算可回收页。
fn rss_kib()->u64 {
 let pid=std::process::id().to_string();
 if cfg!(target_os="macos") {
  let out=std::process::Command::new("footprint").arg(&pid).output().unwrap();
  let text=String::from_utf8_lossy(&out.stdout);
  let Some(rest)=text.split("Footprint: ").nth(1) else {return 0};
  let mut it=rest.split_whitespace();
  let n:f64=it.next().and_then(|v|v.parse().ok()).unwrap_or(0.0);
  return match it.next() {Some("GB")=>n*1048576.0,Some("MB")=>n*1024.0,Some("KB")=>n,_=>n/1024.0} as u64;
 }
 let out=std::process::Command::new("ps").args(["-o","rss=","-p",&pid]).output().unwrap();
 String::from_utf8_lossy(&out.stdout).trim().parse().unwrap_or(0)
}
fn sample_rss()->(Arc<AtomicBool>,Arc<AtomicU64>,std::thread::JoinHandle<()>) {
 let stop=Arc::new(AtomicBool::new(false));let peak=Arc::new(AtomicU64::new(0));
 let (s,p)=(stop.clone(),peak.clone());
 let h=std::thread::spawn(move||while !s.load(Ordering::SeqCst) {p.fetch_max(rss_kib(),Ordering::SeqCst);std::thread::sleep(std::time::Duration::from_millis(5));});
 (stop,peak,h)
}
/// 量内存的用例各自在一个新进程里跑。
///
/// 同一进程里前一条用例释放的内存，分配器会缓存着给后一条用：后一条的基线和峰值
/// 都被前一条的残留搅浑（实测同一条上传用例单跑涨 47 MiB、排在别的用例后面跑「涨」270）。
/// 所以每条用例先把自己在子进程里原样再跑一遍，父进程只看子进程成败。
fn in_own_process(name:&str)->bool {
 if std::env::var_os("KANPAN_STRESS_CHILD").is_some() {return true}
 let status=std::process::Command::new(std::env::current_exe().unwrap()).args([name,"--exact","--nocapture","--test-threads=1"]).env("KANPAN_STRESS_CHILD","1").status().unwrap();
 assert!(status.success(),"{name} 在独立进程里没过");
 false
}
/// 一次请求，正文是事先备好的字节（`Bytes` 克隆不拷贝），只要状态码；响应正文读完就丢。
async fn hit(app:&Router,method:&str,path:&str,token:&str,body:Bytes)->StatusCode {
 let mut req=Request::builder().uri(path).method(method).header("content-type","application/json").header("authorization",format!("Bearer {token}")).body(Body::from(body)).unwrap();
 req.extensions_mut().insert(ConnectInfo("127.0.0.1:19000".parse::<SocketAddr>().unwrap()));
 let res=app.clone().oneshot(req).await.unwrap();let status=res.status();
 drop(res.into_body().collect().await.unwrap());status
}
/// 一张接近上限的「JPEG」：魔数对上就收，内容服务端不解码。
fn big_jpeg()->String {let mut b=vec![0xff,0xd8,0xff,0xe0];b.resize(5*1024*1024-16,7);b.extend([0xff,0xd9]);STANDARD.encode(b)}

/// 一阵补图上传同时到：进程内存不能随并发数线性涨。
///
/// 请求体上限 7 MiB、单张 5 MiB，额度（每条三张）要等解码、拿锁之后才查——
/// 所以第四张起虽然都回 409，内存照样先摊开了。攻击者只要一个账号、一条记录。
#[tokio::test(flavor="multi_thread",worker_threads=8)]
async fn attachment_upload_burst_keeps_memory_bounded() {
 if !in_own_process("attachment_upload_burst_keeps_memory_bounded") {return}
 let w=boot().await;let a=signup(&w.app,"satt").await;
 let id=place(&w,&a,&Spec::default()).await;
 const BURST:usize=40;
 let image=big_jpeg();
 let bodies:Vec<Bytes>=(0..BURST).map(|_|Bytes::from(json!({"id":Uuid::new_v4(),"recordId":id,"image":image}).to_string())).collect();
 drop(image);
 // 热身一张（不算进额度之外的任何东西：同一条记录，后面只会多收两张）。
 assert_eq!(hit(&w.app,"POST","/v1/native-review/attachments",&a.token,bodies[0].clone()).await,200);
 let base=rss_kib();let (stop,peak,h)=sample_rss();let started=std::time::Instant::now();
 let mut set=tokio::task::JoinSet::new();
 for body in bodies[1..].iter().cloned() {let app=w.app.clone();let t=a.token.clone();set.spawn(async move {hit(&app,"POST","/v1/native-review/attachments",&t,body).await});}
 let mut codes=std::collections::BTreeMap::<u16,usize>::new();
 while let Some(c)=set.join_next().await {*codes.entry(c.unwrap().as_u16()).or_default()+=1;}
 stop.store(true,Ordering::SeqCst);h.join().unwrap();
 let grew=peak.load(Ordering::SeqCst).saturating_sub(base)/1024;
 println!("attachment burst: {} uploads, codes {codes:?}, RSS base {} MiB, peak +{grew} MiB, {:?}",BURST-1,base/1024,started.elapsed());
 assert_eq!(codes.get(&200).copied().unwrap_or(0),2,"额度仍然是每条三张：{codes:?}");
 assert!(codes.keys().all(|c|*c==200||*c==409),"{codes:?}");
 assert!(grew<200,"{} 张 5 MB 补图同时到，进程涨了 {grew} MiB",BURST-1);
 w.close().await;
}

/// 一阵补图下载同时到：同上，读出来的字节、base64、JSON 各一份，不能随并发线性涨。
#[tokio::test(flavor="multi_thread",worker_threads=8)]
async fn attachment_download_burst_keeps_memory_bounded() {
 if !in_own_process("attachment_download_burst_keeps_memory_bounded") {return}
 let w=boot().await;let a=signup(&w.app,"satg").await;
 let id=place(&w,&a,&Spec::default()).await;
 let att=Uuid::new_v4();
 let body=Bytes::from(json!({"id":att,"recordId":id,"image":big_jpeg()}).to_string());
 assert_eq!(hit(&w.app,"POST","/v1/native-review/attachments",&a.token,body).await,200);
 let path=format!("/v1/native-review/attachments/{att}");
 assert_eq!(hit(&w.app,"GET",&path,&a.token,Bytes::new()).await,200);
 const BURST:usize=40;
 let base=rss_kib();let (stop,peak,h)=sample_rss();let started=std::time::Instant::now();
 let mut set=tokio::task::JoinSet::new();
 for _ in 0..BURST {let app=w.app.clone();let t=a.token.clone();let p=path.clone();set.spawn(async move {hit(&app,"GET",&p,&t,Bytes::new()).await});}
 while let Some(c)=set.join_next().await {assert_eq!(c.unwrap(),200);}
 stop.store(true,Ordering::SeqCst);h.join().unwrap();
 let grew=peak.load(Ordering::SeqCst).saturating_sub(base)/1024;
 println!("attachment download burst: {BURST} downloads, RSS base {} MiB, peak +{grew} MiB, {:?}",base/1024,started.elapsed());
 assert!(grew<200,"{BURST} 次 5 MB 补图下载同时到，进程涨了 {grew} MiB");
 w.close().await;
}
