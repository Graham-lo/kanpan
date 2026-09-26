//! 后台任务的看守：任何一条该常驻的后台任务死了（panic、或者本该永远转的循环返回了），
//! 记一条 error，然后让整个进程以非零码退出，交给 systemd 的 `Restart=on-failure` 拉起。
//!
//! 为什么不就地重启那一条：原来 `serve` 里的 `spawn_refresh / spawn_daily / spawn_warm`
//! 把 JoinHandle 直接丢掉，worker 的四个循环 `join!` 在一起——任何一条 panic 了，
//! 进程照样活着、端口照样开着、systemd 看它一切正常，那条任务却已经静默地没了
//! （行业表不再刷新、日收盘不再采集、提醒不再评估），日志里只有一行被淹掉的 panic。
//! 进程级重启把「这条任务的状态是不是还干净」这个问题一并交给了一个全新的进程，
//! 也让 `NRestarts` 成为一个看得见的计数。
use std::future::Future;
use std::sync::{Arc,OnceLock,atomic::{AtomicBool,Ordering}};
use std::time::Duration;
use tokio::sync::mpsc;

/// 进程里那个 Supervisor 的报丧通道，给 [`spawn_essential`] 用。只有 main 调了
/// [`Supervisor::adopt_essentials`] 才有；测试里没有，那时只记 error 日志。
static ESSENTIAL:OnceLock<mpsc::UnboundedSender<String>>=OnceLock::new();

/// 一条后台任务该活多久。
#[derive(Clone,Copy,Debug,PartialEq)]
pub enum Life {
 /// 永远转的循环：它返回了就是出事了。
 Forever,
 /// 做完一次就该结束的（比如持仓量存档的预热）：正常结束不算事，panic 才算。
 Once,
}

pub struct Supervisor {tx:mpsc::UnboundedSender<String>,rx:mpsc::UnboundedReceiver<String>}
impl Default for Supervisor {fn default()->Self {Self::new()}}
impl Supervisor {
 pub fn new()->Self {let (tx,rx)=mpsc::unbounded_channel();Self{tx,rx}}
 /// 起一条后台任务并看着它。
 pub fn spawn<F>(&self,name:&'static str,life:Life,task:F) where F:Future<Output=()>+Send+'static {
  self.watch(name,life,tokio::spawn(task))
 }
 /// 让模块里自己起的那些「全局单例」任务（[`spawn_essential`]）死了也报到这里来。
 /// main 在起服务 / worker 时调一次；进程里只认第一个。
 pub fn adopt_essentials(&self) {let _=ESSENTIAL.set(self.tx.clone());}
 /// 看着一条已经起好的任务。
 pub fn watch(&self,name:&'static str,life:Life,handle:tokio::task::JoinHandle<()>) {
  let tx=self.tx.clone();
  tokio::spawn(async move {
   if let Some(why)=verdict(life,handle.await) {
    tracing::error!(task=name,"Background task died: {why}; exiting so systemd restarts the process");
    let _=tx.send(format!("background task `{name}` {why}"));
   }
  });
 }
 /// 等到第一条任务死掉，返回它的死因。一条都没死就一直等下去。
 pub async fn failure(mut self)->anyhow::Error {
  match self.rx.recv().await {
   Some(why)=>anyhow::anyhow!(why),
   // 自己手里还握着一个 tx，通道不会关；走到这里只能是逻辑错了，照样当成出事。
   None=>anyhow::anyhow!("background supervisor lost its channel"),
  }
 }
}

/// 后台任务死了之后，留给在途请求收尾的时间。过了还没收干净就直接退出。
pub const DRAIN:std::time::Duration=std::time::Duration::from_secs(10);
/// 死因的存放处：`shutdown` 的信号 future 把它写进去，`serve` 返回之后取出来当退出原因。
pub type Cause=std::sync::Arc<std::sync::Mutex<Option<anyhow::Error>>>;
/// 该收尾退出的那一下：Ctrl-C（SIGINT），或者 SIGTERM。
///
/// systemd 的 `stop` / `restart`（也就是每一次部署）发的是 SIGTERM。以前这里只听 Ctrl-C，
/// 而 tokio 不替 SIGTERM 装处理器，于是它按默认动作当场杀掉进程：`with_graceful_shutdown`
/// 与 [`DRAIN`] 在线上一次都没走到过，在途请求（登录、同步推送）全被重置。
///
/// SIGTERM 的处理器在这个函数**被调用时**就装好，不等返回的 future 第一次被轮询：
/// 否则起服务到第一次轮询之间来的 SIGTERM 仍是默认动作。所以要在运行时里调用。
pub fn stop_signal()->impl Future<Output=()>+Send+'static {
 #[cfg(unix)]
 let term=tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate());
 async move {
  #[cfg(unix)]
  match term {
   Ok(mut term)=>{tokio::select! {_=tokio::signal::ctrl_c()=>{},_=term.recv()=>{}}}
   Err(e)=>{tracing::error!("SIGTERM handler unavailable ({e}); only Ctrl-C stops gracefully");let _=tokio::signal::ctrl_c().await;}
  }
  #[cfg(not(unix))]
  {let _=tokio::signal::ctrl_c().await;}
 }
}
impl Supervisor {
 /// 给 axum `with_graceful_shutdown` 用的信号：[`stop_signal`]（Ctrl-C 或 SIGTERM），或者某条后台任务死了。
 /// 后者把死因写进返回的 [`Cause`]，并挂一个 [`DRAIN`] 的兜底——在途请求收不干净
 /// 也不会让一个少了后台任务的进程一直挂着。
 pub fn shutdown(self)->(impl Future<Output=()>+Send+'static,Cause) {
  let stop=stop_signal();
  let cause:Cause=Default::default();
  let slot=cause.clone();
  (async move {
   tokio::select! {
    _=stop=>{}
    e=self.failure()=>{
     *slot.lock().unwrap_or_else(|p|p.into_inner())=Some(e);
     tokio::spawn(async {
      tokio::time::sleep(DRAIN).await;
      tracing::error!("In-flight requests did not drain within {DRAIN:?} after a background task died; exiting");
      std::process::exit(1);
     });
    }
   }
  },cause)
 }
}
/// `serve` 结束之后：是因为后台任务死了，就把死因当错误返回（main 以非零码退出）。
pub fn outcome(cause:&Cause)->anyhow::Result<()> {
 match cause.lock().unwrap_or_else(|p|p.into_inner()).take() {Some(e)=>Err(e),None=>Ok(())}
}

/// 起一条后台任务，死得不对（panic；`Forever` 的还包括返回了）就记一条 error。
///
/// 给那些「死了下一次有人要时会重新起」的任务用：它们不值得拖着整个进程重启，
/// 但以前是裸 `tokio::spawn`、JoinHandle 丢掉，panic 了日志里什么都没有。
pub fn spawn_logged<F>(name:&'static str,life:Life,task:F) where F:Future<Output=()>+Send+'static {
 let handle=tokio::spawn(task);
 tokio::spawn(async move {
  if let Some(why)=verdict(life,handle.await) {tracing::error!(task=name,"Background task died: {why}");}
 });
}

/// 模块里自己起的全局单例循环（连接池的管家、各家行情的分发中枢之类）：它们一死，这一摊
/// 就静默地停了（手里的发送端还在，命令发进去没人收），又没法原地重建（状态全在它自己手里）。
/// 所以按 `Supervisor` 的同一个规矩办：记 error，报给进程的 Supervisor，由它收尾退出、
/// systemd 拉起一个干净的进程。没有 Supervisor（测试）时只记日志。
pub fn spawn_essential<F>(name:&'static str,task:F) where F:Future<Output=()>+Send+'static {
 let handle=tokio::spawn(task);
 tokio::spawn(async move {
  if let Some(why)=verdict(Life::Forever,handle.await) {
   tracing::error!(task=name,"Essential background task died: {why}");
   if let Some(tx)=ESSENTIAL.get() {let _=tx.send(format!("background task `{name}` {why}"));}
  }
 });
}

/// 一条无状态的常驻循环：死了（panic 或返回）记 error，歇一会儿原地再起。连着死得快就
/// 越歇越久（1 秒起、翻倍、封顶 1 分钟）；活过 5 分钟再死，从 1 秒重新算。
pub fn spawn_restarting<M,F>(name:&'static str,make:M) where M:Fn()->F+Send+'static,F:Future<Output=()>+Send+'static {
 tokio::spawn(async move {
  let mut backoff=RESTART_FIRST;
  loop {
   let born=tokio::time::Instant::now();
   let why=verdict(Life::Forever,tokio::spawn(make()).await).unwrap_or_default();
   if born.elapsed()>=RESTART_HEALTHY {backoff=RESTART_FIRST}
   tracing::error!(task=name,"Background task died: {why}; restarting in {backoff:?}");
   tokio::time::sleep(backoff).await;
   backoff=(backoff*2).min(RESTART_MAX);
  }
 });
}
const RESTART_FIRST:Duration=Duration::from_secs(1);
const RESTART_MAX:Duration=Duration::from_secs(60);
const RESTART_HEALTHY:Duration=Duration::from_secs(300);

/// 「有一个在跑」的标志，拿到了就握着，**怎么结束都放掉**：正常返回、提前 return、panic。
/// 以前是函数末尾手写一句 `store(false)`，任务一 panic 这句就跳过了，标志永远是 true，
/// 那件事在这个进程里再也起不来。
pub struct Running(Arc<AtomicBool>);
impl Running {
 /// 标志空着就占上；已经有人在跑就返回 None。
 pub fn claim(flag:&Arc<AtomicBool>)->Option<Self> {
  (!flag.swap(true,Ordering::AcqRel)).then(||Self(flag.clone()))
 }
}
impl Drop for Running {fn drop(&mut self) {self.0.store(false,Ordering::Release)}}

/// 一条任务结束的方式算不算出事；算就给出一句死因。
fn verdict(life:Life,outcome:Result<(),tokio::task::JoinError>)->Option<String> {
 match outcome {
  Ok(())=>(life==Life::Forever).then(||"returned, but it is meant to run forever".to_owned()),
  Err(e) if e.is_panic()=>{
   let payload=e.into_panic();
   let message=payload.downcast_ref::<&str>().map(|s|(*s).to_owned()).or_else(||payload.downcast_ref::<String>().cloned()).unwrap_or_else(||"(non-string payload)".into());
   Some(format!("panicked: {message}"))
  }
  Err(e)=>Some(format!("was cancelled: {e}")),
 }
}

#[cfg(test)]
mod tests {
 use super::*;
 use std::time::Duration;

 /// systemd 停服发的是 SIGTERM：它必须走进优雅关闭，而不是按默认动作当场杀掉进程
 /// （那样这条测试连同整个测试进程都会死掉）。
 #[cfg(unix)]
 #[tokio::test]
 async fn sigterm_starts_the_graceful_shutdown() {
  let (stop,cause)=Supervisor::new().shutdown();
  let status=std::process::Command::new("kill").args(["-TERM",&std::process::id().to_string()]).status().unwrap();
  assert!(status.success());
  tokio::time::timeout(Duration::from_secs(5),stop).await.expect("SIGTERM 要让 with_graceful_shutdown 的信号落下");
  assert!(outcome(&cause).is_ok(),"停服不是后台任务死了，退出码是 0");
 }

 #[tokio::test]
 async fn a_panicking_task_is_reported_by_name() {
  let s=Supervisor::new();
  s.spawn("steady",Life::Forever,async {loop {tokio::time::sleep(Duration::from_secs(3600)).await}});
  s.spawn("boom",Life::Forever,async {panic!("NaiveDateTime + TimeDelta overflowed")});
  let e=tokio::time::timeout(Duration::from_secs(5),s.failure()).await.expect("reported");
  let text=e.to_string();
  assert!(text.contains("`boom`")&&text.contains("overflowed"),"{text}");
 }

 #[tokio::test]
 async fn a_forever_loop_that_returns_is_a_failure_but_a_one_shot_is_not() {
  let s=Supervisor::new();
  s.spawn("warm",Life::Once,async {});
  s.spawn("refresh",Life::Forever,async {tokio::time::sleep(Duration::from_millis(20)).await});
  let e=tokio::time::timeout(Duration::from_secs(5),s.failure()).await.expect("reported");
  assert!(e.to_string().contains("`refresh` returned"),"{e}");
 }

 #[tokio::test]
 async fn nothing_dying_means_waiting_forever() {
  let s=Supervisor::new();
  s.spawn("warm",Life::Once,async {});
  let handle=tokio::spawn(async {std::future::pending::<()>().await});
  s.watch("idle",Life::Forever,handle);
  assert!(tokio::time::timeout(Duration::from_millis(100),s.failure()).await.is_err(),"one-shot finishing cleanly is not a death");
 }

 /// 标志随守卫走：panic 了也放掉，下一次还能占上。
 #[tokio::test]
 async fn a_running_flag_is_released_even_when_the_task_panics() {
  let flag=Arc::new(AtomicBool::new(false));
  let claim=Running::claim(&flag).expect("free");
  assert!(Running::claim(&flag).is_none(),"only one at a time");
  let outcome=tokio::spawn(async move {let _claim=claim;panic!("hot layer blew up")}).await;
  assert!(outcome.is_err());
  assert!(!flag.load(Ordering::Acquire),"released by the panic's unwind");
  assert!(Running::claim(&flag).is_some(),"and can be claimed again");
 }

 /// 无状态的常驻循环 panic 之后原地再起；第二次起来的那一条正常转下去。
 #[tokio::test(start_paused=true)]
 async fn a_restarting_loop_comes_back_after_a_panic() {
  let starts=Arc::new(std::sync::atomic::AtomicUsize::new(0));
  let counter=starts.clone();
  spawn_restarting("layers",move ||{
   let n=counter.fetch_add(1,Ordering::SeqCst);
   async move {if n==0 {panic!("first run dies")} std::future::pending::<()>().await}
  });
  tokio::time::sleep(Duration::from_secs(5)).await;
  assert_eq!(starts.load(Ordering::SeqCst),2,"restarted once, then kept running");
 }

 /// 全局单例死了：没有 Supervisor 时只记日志、不 panic 不退出（测试进程还活着就是证明）；
 /// 有 Supervisor 时报到它那里去。
 #[tokio::test]
 async fn an_essential_task_reports_its_death_to_the_adopting_supervisor() {
  let s=Supervisor::new();
  s.adopt_essentials();
  spawn_essential("hub",async {panic!("manager blew up")});
  // 别的测试也可能先占了 ESSENTIAL；只在它就是这个 Supervisor 时断言收到。
  if ESSENTIAL.get().is_some_and(|tx|tx.same_channel(&s.tx)) {
   let e=tokio::time::timeout(Duration::from_secs(5),s.failure()).await.expect("reported");
   assert!(e.to_string().contains("`hub` panicked: manager blew up"),"{e}");
  }
 }

 #[test]
 fn panics_with_a_formatted_message_keep_it() {
  let rt=tokio::runtime::Builder::new_current_thread().build().unwrap();
  let outcome=rt.block_on(async {tokio::spawn(async {let n=3;panic!("bad {n}")}).await});
  assert_eq!(verdict(Life::Once,outcome).as_deref(),Some("panicked: bad 3"));
 }
}

/// 轮询型后台循环的共同骨架：`step` 回 `Ok(true)`（这一步做了事）就立刻做下一步，
/// 回 `Ok(false)`（没活）或出错才睡 `idle`。
///
/// 「每一步之后都睡」会把吞吐钉死在一步一个 `idle`，积压时越排越长；「做完就接着做」
/// 由 `step` 自己保证不空转——它回 `true` 必须是真的认领到、做掉了一件事。
pub async fn poll_loop<F,Fut>(name:&'static str,idle:std::time::Duration,mut step:F) where F:FnMut()->Fut,Fut:Future<Output=crate::error::Result<bool>> {
 loop {
  match step().await {
   Ok(true)=>tokio::task::yield_now().await,
   Ok(false)=>tokio::time::sleep(idle).await,
   Err(e)=>{tracing::warn!("{name} work will retry ({e:?})");tokio::time::sleep(idle).await}
  }
 }
}
