//! 资源闸门（2026-09-25）：订单流跟踪只能用这台 VPS 的余量，给手机的 K 线 / 行情中继永远优先。
//!
//! * 进程自己读 `/proc/self/status`（VmRSS）与 `/proc/self/stat`（utime + stime），每 15 秒采一次；
//!   CPU 按最近一分钟的增量算（100% = 一个核跑满）。
//! * RSS > 2.5 GB（2.5×10⁹ 字节）或最近一分钟 CPU > 300% 算「超」：超的那一分钟起停止新增并卸掉热点、告警；
//!   下一分钟还超再卸山寨，再下一分钟卸固定（见 `orderflow_history.rs` 的 `Registry::gate`）；连续 10 分钟
//!   不超再一层层加回来。主币、按需（用户点开的）与行情中继一概不动。
//! * 线还要落在进程所在 cgroup 的上限（systemd 单元的 `MemoryMax` / `CPUQuota`）的四分之三以内：`ops/install.py`
//!   装的单元是 1 GB / 200%，原来的 2.5 GB / 300% 永远碰不到——内存先撞 1 GB 整个进程被 OOM 杀掉（账号、同步、
//!   行情转发一起断），CPU 被限在 200% 量不出 300%，闸门形同虚设。
//! * 卸了层之后请 glibc 把空出来的页还给系统（`malloc_trim`）：分配器默认留着，RSS 不降，闸门就一直判超、
//!   卸下的层永远加不回来。
//! * 没有 `/proc`（本机 macOS 开发）时读不到，一律当作没超。
use std::collections::VecDeque;
use std::sync::Mutex;
use std::time::{Duration,Instant};

pub const MAX_RSS_BYTES:u64=2_500_000_000;
pub const MAX_CPU_PERCENT:f64=300.0;
/// Linux 的 USER_HZ（x86_64 / arm64 都是 100）。
const CLK_TCK:f64=100.0;
const WINDOW:Duration=Duration::from_secs(60);
/// 至少攒这么长的一段才算 CPU（进程刚起来时不下结论）。
const MIN_SPAN:Duration=Duration::from_secs(10);

/// 闸门的线最多占 cgroup 上限的这么多。
const CGROUP_SHARE:f64=0.75;

/// 进程所在 cgroup 给的上限（没设就是 `None`）。
#[derive(Clone,Copy,Debug,Default,PartialEq)]
pub struct Limits {pub memory_bytes:Option<u64>,pub cpu_percent:Option<f64>}

impl Limits {
 pub fn rss_line(&self)->u64 {
  self.memory_bytes.map_or(MAX_RSS_BYTES,|m|MAX_RSS_BYTES.min((m as f64*CGROUP_SHARE) as u64))
 }
 pub fn cpu_line(&self)->f64 {
  self.cpu_percent.map_or(MAX_CPU_PERCENT,|c|MAX_CPU_PERCENT.min(c*CGROUP_SHARE))
 }
}

#[derive(Clone,Copy,Debug,Default,PartialEq)]
pub struct Load {pub rss_bytes:Option<u64>,pub cpu_percent:Option<f64>,pub limits:Limits}

impl Load {
 pub fn over(&self)->bool {
  self.rss_bytes.is_some_and(|r|r>self.limits.rss_line())||self.cpu_percent.is_some_and(|c|c>self.limits.cpu_line())
 }
 pub fn describe(&self)->String {
  let rss=self.rss_bytes.map_or("?".into(),|r|format!("{:.0} MB",r as f64/1e6));
  let cpu=self.cpu_percent.map_or("?".into(),|c|format!("{c:.0}%"));
  format!("RSS {rss} (gate {:.0} MB), CPU {cpu} (gate {:.0}%) over the last minute",self.limits.rss_line() as f64/1e6,self.limits.cpu_line())
 }
}

/// `/proc/self/cgroup`（cgroup v2 那一行 `0::/system.slice/kanpan-api.service`）→ `/sys/fs/cgroup` 下的目录。
pub fn parse_cgroup_path(cgroup:&str)->Option<&str> {
 cgroup.lines().find_map(|l|l.strip_prefix("0::")).map(str::trim)
}

/// `memory.max`：`max` 是没设。
pub fn parse_memory_max(text:&str)->Option<u64> {text.trim().parse().ok()}

/// `cpu.max`：`200000 100000` → 200%；`max 100000` 是没设。
pub fn parse_cpu_max(text:&str)->Option<f64> {
 let mut parts=text.split_whitespace();
 let quota:f64=parts.next()?.parse().ok()?;
 let period:f64=parts.next()?.parse().ok()?;
 (period>0.0).then_some(quota/period*100.0)
}

fn limits()->Limits {
 let Some(dir)=std::fs::read_to_string("/proc/self/cgroup").ok().and_then(|c|parse_cgroup_path(&c).map(|p|format!("/sys/fs/cgroup{}",p.trim_end_matches('/')))) else {return Limits::default()};
 let read=|name:&str|std::fs::read_to_string(format!("{dir}/{name}")).ok();
 Limits{memory_bytes:read("memory.max").as_deref().and_then(parse_memory_max),cpu_percent:read("cpu.max").as_deref().and_then(parse_cpu_max)}
}

/// 卸完层请分配器把空出来的页还回去，RSS 才会跟着降（只有 glibc 有这个口）。
pub fn release_free_memory() {
 #[cfg(all(target_os="linux",target_env="gnu"))]
 {
  unsafe extern "C" {fn malloc_trim(pad:usize)->std::ffi::c_int;}
  // SAFETY：glibc 的 malloc_trim 只整理分配器自己的空闲页，参数是保留的余量字节数，任何时刻从任何线程调都安全。
  unsafe {malloc_trim(0);}
 }
}

/// `VmRSS:     123456 kB` → 字节。
pub fn parse_rss(status:&str)->Option<u64> {
 let line=status.lines().find(|l|l.starts_with("VmRSS:"))?;
 let kb:u64=line.split_whitespace().nth(1)?.parse().ok()?;
 Some(kb*1024)
}

/// `/proc/self/stat` → utime + stime（时钟滴答）。进程名可能带空格和括号，从最后一个 `)` 之后数。
pub fn parse_cpu_ticks(stat:&str)->Option<u64> {
 let rest=&stat[stat.rfind(')')?+1..];
 let fields:Vec<&str>=rest.split_whitespace().collect();
 // 右括号之后第 0 个是 state（第 3 列），utime / stime 是第 14 / 15 列。
 let utime:u64=fields.get(11)?.parse().ok()?;
 let stime:u64=fields.get(12)?.parse().ok()?;
 Some(utime+stime)
}

/// 一段时间里的 CPU 百分比：`samples` 按时间先后，取窗口内最早的一个做基线。
pub fn cpu_percent(samples:&VecDeque<(Instant,u64)>)->Option<f64> {
 let (first,last)=(samples.front()?,samples.back()?);
 let span=last.0.duration_since(first.0);
 if span<MIN_SPAN {return None}
 Some(last.1.saturating_sub(first.1) as f64/CLK_TCK/span.as_secs_f64()*100.0)
}

struct Sampler {samples:VecDeque<(Instant,u64)>,last:Load}

static SAMPLER:Mutex<Sampler>=Mutex::new(Sampler{samples:VecDeque::new(),last:Load{rss_bytes:None,cpu_percent:None,limits:Limits{memory_bytes:None,cpu_percent:None}}});

/// 采一次并返回此刻的读数（由订单流的层循环每 15 秒调一次）。
pub fn sample()->Load {
 let rss=std::fs::read_to_string("/proc/self/status").ok().as_deref().and_then(parse_rss);
 let ticks=std::fs::read_to_string("/proc/self/stat").ok().as_deref().and_then(parse_cpu_ticks);
 let limits=limits();
 let now=Instant::now();
 let mut s=SAMPLER.lock().unwrap_or_else(|e|e.into_inner());
 if let Some(t)=ticks {s.samples.push_back((now,t));}
 // 留一个刚超出窗口的做基线，保证「最近一分钟」是满的一分钟。
 while s.samples.len()>2&&s.samples.get(1).is_some_and(|x|now.duration_since(x.0)>=WINDOW) {s.samples.pop_front();}
 let load=Load{rss_bytes:rss,cpu_percent:cpu_percent(&s.samples),limits};
 s.last=load;
 load
}

/// 上一次采样的读数（不出新样本）。
pub fn last()->Load {SAMPLER.lock().unwrap_or_else(|e|e.into_inner()).last}

#[cfg(test)]
mod tests {
 use super::*;

 #[test] fn parses_proc_files() {
  assert_eq!(parse_rss("Name:\tkanpan-api\nVmPeak:\t 9 kB\nVmRSS:\t  204800 kB\nThreads:\t12\n"),Some(204_800*1024));
  assert_eq!(parse_rss("Name: x\n"),None);
  let stat="4242 (kanpan api (x)) S 1 4242 4242 0 -1 4194560 100 0 0 0 1500 250 0 0 20 0 12 0 99 0 0";
  assert_eq!(parse_cpu_ticks(stat),Some(1750));
 }

 #[test] fn cpu_over_a_window_and_the_gate() {
  let t0=Instant::now();
  let mut s=VecDeque::new();
  s.push_back((t0,1_000));
  assert_eq!(cpu_percent(&s),None);
  s.push_back((t0+Duration::from_secs(5),1_500));
  assert_eq!(cpu_percent(&s),None,"不到 10 秒不下结论");
  s.push_back((t0+Duration::from_secs(60),19_000));
  // 60 秒里 18000 滴答 = 180 秒 CPU = 300%。
  assert_eq!(cpu_percent(&s).map(|c|c.round()),Some(300.0));
  let none=Limits::default();
  assert!(!Load{rss_bytes:Some(MAX_RSS_BYTES),cpu_percent:Some(300.0),limits:none}.over(),"正好在线上不算超");
  assert!(Load{rss_bytes:Some(MAX_RSS_BYTES+1),cpu_percent:None,limits:none}.over());
  assert!(Load{rss_bytes:None,cpu_percent:Some(301.0),limits:none}.over());
  assert!(!Load::default().over(),"读不到（macOS）当作没超");
 }

 #[test] fn the_gate_sits_inside_the_units_own_limits() {
  assert_eq!(parse_cgroup_path("0::/system.slice/kanpan-api.service\n"),Some("/system.slice/kanpan-api.service"));
  assert_eq!(parse_cgroup_path("12:memory:/x\n"),None,"cgroup v1 不认");
  assert_eq!(parse_memory_max("1073741824\n"),Some(1_073_741_824));
  assert_eq!(parse_memory_max("max\n"),None);
  assert_eq!(parse_cpu_max("200000 100000\n"),Some(200.0));
  assert_eq!(parse_cpu_max("max 100000\n"),None);
  // ops/install.py 的单元：MemoryMax=1G、CPUQuota=200%。
  let unit=Limits{memory_bytes:Some(1<<30),cpu_percent:Some(200.0)};
  assert_eq!((unit.rss_line(),unit.cpu_line()),(805_306_368,150.0),"线在上限的四分之三");
  assert!(Load{rss_bytes:Some(900_000_000),cpu_percent:Some(100.0),limits:unit}.over(),"原来 2.5 GB 的线在 1 GB 被 OOM 之前永远碰不到");
  assert!(Load{rss_bytes:Some(200_000_000),cpu_percent:Some(160.0),limits:unit}.over(),"原来 300% 的线在 200% 限流下永远量不到");
  assert!(!Load{rss_bytes:Some(250_000_000),cpu_percent:Some(60.0),limits:unit}.over(),"平时（README 实测）不超");
  let roomy=Limits{memory_bytes:Some(16<<30),cpu_percent:Some(800.0)};
  assert_eq!((roomy.rss_line(),roomy.cpu_line()),(MAX_RSS_BYTES,MAX_CPU_PERCENT),"上限宽的时候照旧");
  release_free_memory();
 }
}
