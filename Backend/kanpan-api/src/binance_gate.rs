//! 这个进程对币安出口只有一条封禁截止时间。
//!
//! 币安的限速是按 IP 算的：429 说这一分钟的权重用完了，418 说这个 IP 已经被封，
//! 官方写的是「2 分钟到 3 天」。原来每个调用方各自退避——`sector_history` 是每个
//! 品种都从 2 秒重新起一轮 2/4/8/16 秒，`market_meta` 干脆不看状态码——于是一轮
//! 采集里七百个品种各自去撞同一道墙，Retry-After 一路被丢掉，封禁只会越撞越久。
//!
//! 这里把它收成一条截止时间：谁撞上了就记下来，截止之前所有调用方直接跳过，
//! 不出站。采集器看到封禁就停掉本轮，下一轮再来，不把几百个品种各自记成失败。
//!
//! 管的是 `binance.com`（exchangeInfo / ticker / klines / openInterest / 那两张
//! 营销表都在这个主机名下）。`data.binance.vision` 的日切片不在这里：那是另一个
//! 服务，它的拒绝走 `oi_archive` 自己的源级冷却。
use std::sync::{Mutex,OnceLock};
use std::time::Duration;
// tokio 的 Instant：测试里 `start_paused` 一推时间，这条截止时间跟着走，
// 于是「封禁期内第二个品种不许出站」这种时序不用真的等两分钟。
use tokio::time::Instant;

/// 429 不带 Retry-After 时等多久。权重窗口是一分钟，十秒够让它过去一截。
pub const UNTOLD_429:Duration=Duration::from_secs(10);
/// 418 不带 Retry-After 时等多久，同时也是 418 的下限：官方最短封禁是两分钟，
/// 上游说「再等 1 秒」也不信。
pub const UNTOLD_418:Duration=Duration::from_secs(120);
/// 截止时间再长也不超过这个数。官方封禁上限是三天，比这更长的 Retry-After 只能
/// 是上游写错了，没有理由让这个进程按它躺到下个月。
const LONGEST:Duration=Duration::from_secs(3*24*60*60);

fn deadline()->&'static Mutex<Option<Instant>> {
 static D:OnceLock<Mutex<Option<Instant>>>=OnceLock::new();
 D.get_or_init(||Mutex::new(None))
}

/// 这个 URL 走不走这道闸。
pub fn covers(url:&str)->bool {url.contains("://www.binance.com/")||url.contains(".binance.com/")}

/// 还要等多久才能再对币安出站；`None` 表示现在可以。
pub fn wait()->Option<Duration> {
 let mut slot=deadline().lock().unwrap_or_else(|e|e.into_inner());
 let until=(*slot)?;
 let now=Instant::now();
 // 过期的截止时间当场清掉，免得每次调用都再比一遍。
 if until<=now {*slot=None;return None}
 Some(until-now)
}
/// 现在是不是还在封禁里。
pub fn blocked()->bool {wait().is_some()}

/// 按一个时长把整个出口按住。只会延长、不会缩短：两个品种先后被 418，第二个
/// 不能把第一个那条更远的截止时间改近——那正是「换个品种就重置退避」的老毛病。
pub fn hold(span:Duration) {
 let span=span.min(LONGEST);
 let until=Instant::now()+span;
 let mut slot=deadline().lock().unwrap_or_else(|e|e.into_inner());
 if slot.is_none_or(|current|current<until) {*slot=Some(until);}
}

/// 记下上游这一次的状态码。429 / 418 设封禁截止并返回 `true`，其它状态什么都不做。
pub fn note(status:u16,retry_after:Option<&str>)->bool {
 let told=retry_after.and_then(seconds);
 let span=match status {
  429=>told.unwrap_or(UNTOLD_429),
  418=>told.unwrap_or(UNTOLD_418).max(UNTOLD_418),
  _=>return false,
 };
 hold(span);
 tracing::warn!("Binance answered {status}; no call to this egress for {}s",span.min(LONGEST).as_secs());
 true
}
/// 同上，直接读一个 reqwest 回答。
pub fn note_reply(response:&reqwest::Response)->bool {
 note(response.status().as_u16(),response.headers().get(reqwest::header::RETRY_AFTER).and_then(|v|v.to_str().ok()))
}
/// 把这道闸交给 vendor 的币安适配器（复盘判定 / 找相似取数走的那一个）。
/// 原来它自己一套、不看这条截止时间：别的模块刚被 418，它照样出站把封禁撞长。
pub struct Gate;
impl scorebook_market::adapters::binance::EgressGate for Gate {
 fn wait(&self)->Option<Duration> {wait()}
 fn note(&self,status:u16,retry_after:Option<&str>) {note(status,retry_after);}
}

/// Retry-After 的秒数形式。币安发的是秒；HTTP 日期那种写法读不出来就当没说，
/// 按上面的默认值等。
fn seconds(header:&str)->Option<Duration> {
 header.trim().parse::<u64>().ok().filter(|s|*s>0).map(Duration::from_secs)
}

#[cfg(test)]
pub fn clear() {*deadline().lock().unwrap_or_else(|e|e.into_inner())=None;}
/// 摸这条全局状态的用例互相会串味，所以它们排队跑。
#[cfg(test)]
pub fn test_lock()->&'static Mutex<()> {
 static L:OnceLock<Mutex<()>>=OnceLock::new();
 L.get_or_init(||Mutex::new(()))
}

#[cfg(test)]
mod tests {
 use super::*;

 // 这把锁就是用来把「同时只许一条测试碰这道进程级闸门」这件事做实的，跨 await 持有正是
 // 它的用途：换成异步锁反而会让别的测试在 await 处插进来把闸门清掉。
 #[allow(clippy::await_holding_lock)]
 #[tokio::test(start_paused=true)]
 async fn a_ban_is_one_deadline_for_the_whole_process_and_only_ever_grows() {
  let _serial=test_lock().lock().unwrap_or_else(|e|e.into_inner());
  clear();
  assert!(!blocked(),"干净的进程不该以为自己被封了");

  // 没头的 429：按权重窗口等十秒。
  assert!(note(429,None));
  assert!(wait().is_some_and(|left|left>Duration::from_secs(9)&&left<=UNTOLD_429));
  // 紧接着一个 418：封禁只会往后推，两分钟起。
  assert!(note(418,None));
  assert!(wait().is_some_and(|left|left>Duration::from_secs(119)));
  // 上游说「再等 1 秒」也不信 418 那么短，已经记下的截止时间不许被改近。
  assert!(note(418,Some("1")));
  assert!(wait().is_some_and(|left|left>Duration::from_secs(119)));
  // 普通回答不动这条线，成功的那些请求当然也不动。
  assert!(!note(200,None));
  assert!(!note(451,None));
  assert!(wait().is_some_and(|left|left>Duration::from_secs(119)));

  // 时间过去了，闸自己开。
  tokio::time::sleep(Duration::from_secs(121)).await;
  assert!(!blocked());

  // Retry-After 说的算，荒唐的值被截到上限。
  assert!(note(429,Some("45")));
  assert!(wait().is_some_and(|left|left>Duration::from_secs(44)&&left<=Duration::from_secs(45)));
  clear();
  assert!(note(429,Some("999999999")));
  assert!(wait().is_some_and(|left|left<=LONGEST));
  clear();
  assert!(note(429,Some("not a number")),"读不出来的头当没说");
  assert!(wait().is_some_and(|left|left<=UNTOLD_429));
  clear();
 }

 #[test]
 fn only_binance_calls_wait_on_this() {
  assert!(covers("https://www.binance.com/fapi/v1/exchangeInfo"));
  assert!(covers("https://www.binance.com/bapi/apex/v1/public/apex/marketing/symbol/list"));
  assert!(!covers("https://data.binance.vision/data/futures/um/daily/metrics/ETHUSDT/x.zip"));
  assert!(!covers("https://api.coingecko.com/api/v3/coins/markets?page=1"));
  assert!(!covers("https://stockanalysis.com/stocks/NVDA/__data.json"));
  assert!(!covers("https://www.okx.com/api/v5/public/open-interest?instType=SWAP"));
 }
}
