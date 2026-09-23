//! Venue-preserving temporary OHLC fetches: Binance through the scorebook provider,
//! Coinbase straight from its public market API (`venues::coinbase`).
use crate::{error::{ApiError,Result},review::core};
use scorebook_core::{api::native_review::ChartRange,domain::{criteria::Bar,interval::Interval},market::MarketDataProvider};
use chrono::{DateTime,Utc};
use serde_json::{Value,json};
use std::sync::OnceLock;

/// The upstream refused this node's region (HTTP 451) or the request itself.
/// Either way it will refuse again in a minute, so it must not look transient.
pub const BLOCKED:&str="market_region_blocked";
fn blocked()->ApiError {ApiError(axum::http::StatusCode::UNAVAILABLE_FOR_LEGAL_REASONS,BLOCKED)}

/// 这一次拿不到 K 线的内部原因。对外两者都还是 `market_unavailable`——响应形状
/// 不动——但它们要分开记：限流是「我们该退一步」，不可用是「该去看网关」。
#[derive(Clone,Copy,Debug,PartialEq)]
enum Refusal {RateLimited,Unavailable}
fn refused(kind:Refusal)->ApiError {
 match kind {
  Refusal::RateLimited=>tracing::warn!("Review chart: the market upstream is rate limited; not calling it again until the cooldown lapses"),
  Refusal::Unavailable=>tracing::warn!("Review chart: the market upstream did not answer"),
 }
 ApiError::bad("market_unavailable")
}
/// Coinbase 被问得太快时回 429（有时带 `Retry-After`）。这里记一格进程级的冷却：
/// 冷却里复盘 worker 不再出站，免得每 60 秒照原样再撞一次、把限流窗口越拖越长。
/// （出站本身还有 `venues::coinbase` 那道 8 次/秒的限速，两道闸各管一件事：
/// 那道管「别问太快」，这道管「被说了之后别马上再来」。）
///
/// 只有一家非币安的上游，所以冷却也只有一格。
/// 对方没说等多久时等这些。
const UNTOLD_COOLDOWN:std::time::Duration=std::time::Duration::from_secs(10);
/// 说得再离谱也不超过这个：公开端点的限流窗口是秒到分钟级的。
const LONGEST_COOLDOWN:std::time::Duration=std::time::Duration::from_secs(300);
fn gateway_cooldown()->&'static std::sync::Mutex<Option<tokio::time::Instant>> {
 static C:OnceLock<std::sync::Mutex<Option<tokio::time::Instant>>>=OnceLock::new();
 C.get_or_init(||std::sync::Mutex::new(None))
}
/// 冷却还剩多久；`None` 表示现在可以出站。
fn cooling()->Option<std::time::Duration> {
 let mut slot=gateway_cooldown().lock().unwrap_or_else(|e|e.into_inner());
 let until=(*slot)?;
 let now=tokio::time::Instant::now();
 if until<=now {*slot=None;return None}
 Some(until-now)
}
/// 记下上游让我们等多久。只延长不缩短。
fn cool_down(span:std::time::Duration) {
 let until=tokio::time::Instant::now()+span.clamp(std::time::Duration::from_secs(1),LONGEST_COOLDOWN);
 let mut slot=gateway_cooldown().lock().unwrap_or_else(|e|e.into_inner());
 if slot.is_none_or(|current|current<until) {*slot=Some(until);}
}
/// 上游这一次说等多久：先看 `Retry-After`，再看 body 里的 `retryAfter`，都没有
/// 就按默认值。
fn told_to_wait(header:Option<&str>,body:&Value)->std::time::Duration {
 let from_header=header.and_then(|v|v.trim().parse::<u64>().ok()).filter(|s|*s>0);
 let from_body=body["retryAfter"].as_f64().filter(|s|*s>0.0).map(|s|s.ceil() as u64)
  .or_else(||body["retryAfter"].as_str().and_then(|v|v.trim().parse::<u64>().ok()));
 if let Some(why)=body["error"].as_str() {tracing::warn!("The market upstream refused a review chart: {why}")}
 from_header.or(from_body).map(std::time::Duration::from_secs).unwrap_or(UNTOLD_COOLDOWN)
}
/// `venues::coinbase` 的失败 → 对外的错误。限流先记冷却。
pub fn coinbase_refusal(e:crate::venues::coinbase::Upstream)->ApiError {
 use crate::venues::coinbase::Upstream;
 match e {
  Upstream::RateLimited(secs)=>{
   cool_down(told_to_wait(secs.map(|s|s.to_string()).as_deref(),&Value::Null));
   refused(Refusal::RateLimited)
  }
  Upstream::Unavailable=>refused(Refusal::Unavailable),
  Upstream::Rejected(_)=>ApiError::bad("invalid_chart_range"),
 }
}
/// 冷却里就不出站：上游刚说过它在限流，再问一次只是让它的窗口更难走完。
pub fn coinbase_ready()->Result<()> {
 if cooling().is_some() {Err(refused(Refusal::RateLimited))} else {Ok(())}
}

/// 复盘判定、找相似取币安 K 线 / 逐笔用的那个适配器：出站前后都过
/// [`crate::binance_gate`]，跟 market_meta / sector_history / oi_archive 共用一条
/// 418 / 429 截止时间（原来它自己一套、不看这条截止时间，别的模块刚被 418 它照样出站）。
pub fn provider(pool:sqlx::PgPool)->anyhow::Result<scorebook_market::adapters::binance::Binance> {
 let market=scorebook_market::adapters::binance::Binance::new(pool)?.with_gate(std::sync::Arc::new(crate::binance_gate::Gate));
 tracing::info!("Review market data reads Binance REST at {}",market.base());
 Ok(market)
}

/// 币安适配器的一次失败折成对外的错误码。可重试的（限流、闸门按着、5xx、传输）是
/// `market_unavailable`，worker 一分钟后再来；不可重试的（451 以及别的 4xx）折成
/// BLOCKED，worker 按天退避，不再每 60 秒问一次同一个拒绝。主机已是 www.binance.com，
/// 这里不该再出现 451；真出现了说明上游改了规矩，所以记 error 让人看见。
pub fn refusal(e:&scorebook_core::error::Error,symbol:&str)->ApiError {
 if e.retry.retryable() {
  tracing::warn!(code=%e.code,symbol,"Review market data: Binance is not answering right now; will retry");
  return ApiError(axum::http::StatusCode::SERVICE_UNAVAILABLE,"market_unavailable");
 }
 tracing::error!(code=%e.code,symbol,"Review market data: Binance refused the request");
 blocked()
}

pub async fn klines(provider:&dyn MarketDataProvider,r:&ChartRange,start:DateTime<Utc>,end:DateTime<Utc>)->Result<Value> {
 // A provider error that already says "do not retry" is, on these VPS, almost
 // always Binance answering 451. Flattening it into market_unavailable made the
 // worker re-ask the same refusal every 60 seconds for the life of the record.
 match (r.venue.as_str(),r.market.as_str()) {
  ("binance","usd_m")=>provider.klines(&r.market,&r.symbol,&r.interval,start,end).await.map_err(|e|refusal(&e,&r.symbol)),
  ("coinbase","spot")=>coinbase_klines(&r.symbol,&r.interval,start,end,Utc::now().timestamp()).await,
  _=>Err(ApiError::bad("invalid_chart_range")),
 }
}

/// Coinbase 原生只有 9 档；其余从原生档聚。和客户端 `CoinbaseProvider.aggregatedFrom`
/// 是同一张表（服务端多了 8h、3d 两档，客户端没有这两个周期）。
fn coinbase_source(iv:Interval)->Interval {
 match iv {Interval::M3=>Interval::M1,Interval::H8=>Interval::H4,Interval::H12=>Interval::H6,Interval::D3|Interval::W1|Interval::Mo1=>Interval::D1,other=>other}
}
/// 源周期最后一根收了多久之后才敢把「这一根没给」当成「这一根没成交」。
/// 刚收的那一两根 Coinbase 可能还没写进 K 线表，太早补平会把真成交抹掉。
const SETTLE_SECS:i64=120;

async fn coinbase_klines(symbol:&str,interval:&str,start:DateTime<Utc>,end:DateTime<Utc>,now:i64)->Result<Value> {
 use crate::venues::coinbase as cb;
 let iv=core(Interval::exact(interval))?;
 let src=coinbase_source(iv);
 let step=src.fixed_seconds().ok_or_else(||ApiError::bad("invalid_chart_range"))?;
 coinbase_ready()?;
 // 只要已经收了的源 K 线：开盘在 `floor(now)` 之前的那些。
 let from=start.timestamp();
 let to=end.timestamp().min(now.div_euclid(step)*step);
 let fetched=if to>from {cb::candles(symbol,step,from,to).await.map_err(coinbase_refusal)?} else {vec![]};
 // 开头就缺（那几分钟没成交）：往前再看一页，找最近一根的收盘价来补。
 let lead=if fetched.first().is_none_or(|c|c.start>from)&&to>from {
  cb::candles(symbol,step,from-(cb::PAGE-1)*step,from).await.map_err(coinbase_refusal)?.last().map(|c|c.close.clone())
 } else {None};
 let (filled,mut complete)=fill_gaps(&fetched,lead,from,to,step,now);
 let bars=aggregate(&filled,iv,src,start,end)?;
 complete=complete&&bars.first().is_some_and(|b|b.start==start)&&bars.last().is_some_and(|b|b.end==end)&&bars.windows(2).all(|w|w[0].end==w[1].start);
 Ok(json!({"provider":"coinbase","bars":bars,"coverage_complete":complete}))
}

/// Coinbase 不给没成交的 K 线。中间缺的一根就是「这段时间没人成交」：按上一根的收盘价
/// 补一根平的、量为 0（和交易所自己在图上画的一样）。末尾缺的只在收了够久之后才补；
/// 开头缺而又找不到更早的收盘价，就认不完整。
fn fill_gaps(fetched:&[crate::venues::coinbase::Candle],lead:Option<String>,from:i64,to:i64,step:i64,now:i64)->(Vec<crate::venues::coinbase::Candle>,bool) {
 use crate::venues::coinbase::Candle;
 let by:std::collections::HashMap<i64,&Candle>=fetched.iter().map(|c|(c.start,c)).collect();
 let last_real=fetched.last().map(|c|c.start).unwrap_or(i64::MIN);
 let mut out=vec![];let mut previous=lead;let mut complete=true;
 let mut t=from;
 while t<to {
  if let Some(c)=by.get(&t) {previous=Some(c.close.clone());out.push((*c).clone());}
  else if t>last_real&&t+step>now-SETTLE_SECS {complete=false;break}
  else if let Some(p)=&previous {out.push(Candle{start:t,open:p.clone(),high:p.clone(),low:p.clone(),close:p.clone(),volume:"0".into()});}
  else {complete=false}
  t+=step;
 }
 (out,complete)
}

/// 源周期 → 目标周期。只收齐了的桶：一个桶里的源 K 线一根都不能少。
fn aggregate(src_bars:&[crate::venues::coinbase::Candle],iv:Interval,src:Interval,start:DateTime<Utc>,end:DateTime<Utc>)->Result<Vec<Bar>> {
 let mut out=vec![];
 let mut i=0;
 while i<src_bars.len() {
  let at=core(crate::review_domain::time(src_bars[i].start*1000))?;
  let bucket=iv.floor(at);let close_at=iv.add_bars(bucket,1);
  let mut j=i;
  while j<src_bars.len()&&src_bars[j].start*1000<close_at.timestamp_millis() {j+=1}
  let group=&src_bars[i..j];
  i=j;
  if bucket<start||close_at>end||group.len() as i64!=src.bars_between(bucket,close_at)||group[0].start!=bucket.timestamp() {continue}
  let num=|s:&String|s.parse::<f64>().unwrap_or(f64::NAN);
  let high=group.iter().map(|c|&c.high).max_by(|a,b|num(a).total_cmp(&num(b))).cloned().unwrap_or_default();
  let low=group.iter().map(|c|&c.low).min_by(|a,b|num(a).total_cmp(&num(b))).cloned().unwrap_or_default();
  let volume:f64=group.iter().map(|c|c.volume.parse::<f64>().unwrap_or(0.0)).sum();
  out.push(Bar{start:bucket,end:close_at,open:group[0].open.clone(),high,low,close:group[group.len()-1].close.clone(),
   volume:Some(if group.len()==1 {group[0].volume.clone()} else {volume.to_string()})});
 }
 Ok(out)
}

#[cfg(test)]
mod tests {
 use super::*;

 #[test]
 fn the_gateway_says_how_long_to_wait_and_we_believe_the_header_first() {
  let body=json!({"error":"upstream_rate_limited","retryAfter":30});
  assert_eq!(told_to_wait(Some("5"),&body),std::time::Duration::from_secs(5));
  assert_eq!(told_to_wait(None,&body),std::time::Duration::from_secs(30));
  assert_eq!(told_to_wait(None,&json!({"error":"busy","retryAfter":"2"})),std::time::Duration::from_secs(2));
  // 什么都没说、或者说了读不出来的东西，按默认值等，绝不当成「可以马上再来」。
  assert_eq!(told_to_wait(None,&json!({"error":"busy"})),UNTOLD_COOLDOWN);
  assert_eq!(told_to_wait(Some("soon"),&Value::Null),UNTOLD_COOLDOWN);
  assert_eq!(told_to_wait(None,&json!({"error":"busy","retryAfter":0})),UNTOLD_COOLDOWN);
 }

 /// 一个本地假币安：每个连接答一次，按顺序取 `replies` 里的回答，把请求行记下来。
 async fn fake_binance(replies:Vec<String>)->(String,std::sync::Arc<std::sync::Mutex<Vec<String>>>,tokio::task::JoinHandle<()>) {
  use tokio::io::{AsyncReadExt,AsyncWriteExt};
  let listener=tokio::net::TcpListener::bind("127.0.0.1:0").await.expect("bind");
  let base=format!("http://{}",listener.local_addr().expect("addr"));
  let seen=std::sync::Arc::new(std::sync::Mutex::new(Vec::<String>::new()));
  let log=seen.clone();
  let server=tokio::spawn(async move {
   for reply in replies {
    let Ok((mut socket,_))=listener.accept().await else {return};
    let mut buf=vec![0u8;4096];let n=socket.read(&mut buf).await.unwrap_or(0);
    let head=String::from_utf8_lossy(&buf[..n]).lines().next().unwrap_or("").to_owned();
    log.lock().unwrap().push(head);
    let _=socket.write_all(reply.as_bytes()).await;let _=socket.shutdown().await;
   }
  });
  (base,seen,server)
 }
 fn reply(status:&str,extra:&str,body:&str)->String {
  format!("HTTP/1.1 {status}\r\nContent-Type: application/json\r\n{extra}Content-Length: {}\r\nConnection: close\r\n\r\n{body}",body.len())
 }
 fn range(start:i64,end:i64,bars:usize)->ChartRange {
  serde_json::from_value(json!({"venue":"binance","market":"usd_m","symbol":"BTCUSDT","interval":"1d","start":start,"end":end,"bars":bars})).unwrap()
 }
 fn gated(base:&str)->scorebook_market::adapters::binance::Binance {
  scorebook_market::adapters::binance::Binance::without_budget(base).unwrap().with_gate(std::sync::Arc::new(crate::binance_gate::Gate))
 }

 #[test]
 fn fixture_instances_build_urls_on_their_own_host() {
  let b=scorebook_market::adapters::binance::Binance::without_budget("http://127.0.0.1:9/").unwrap();
  assert_eq!(b.url("usd_m","klines").as_deref(),Some("http://127.0.0.1:9/fapi/v1/klines"),"末尾的 / 去掉");
  assert_eq!(b.url("usd_m","aggTrades").as_deref(),Some("http://127.0.0.1:9/fapi/v1/aggTrades"));
  assert_eq!(b.url("spot","klines"),None);
 }

 // 这把锁把「同时只许一条测试碰进程级闸门」做实，跨 await 持有就是它的用途。
 #[allow(clippy::await_holding_lock)]
 #[tokio::test]
 async fn review_klines_go_through_the_shared_ban_gate() {
  let _serial=crate::binance_gate::test_lock().lock().unwrap_or_else(|e|e.into_inner());
  crate::binance_gate::clear();
  let day=86_400_000i64;let start=1_780_000_000_000i64/day*day;let end=start+2*day;
  let rows=json!([[start,"100","110","90","105","1",start+day-1],[start+day,"105","120","100","110","1",end-1]]).to_string();
  let (base,seen,server)=fake_binance(vec![
   reply("200 OK","",&rows),
   reply("451 Unavailable For Legal Reasons","",r#"{"code":0,"msg":"restricted location"}"#),
   reply("418 I'm a teapot","Retry-After: 300\r\n","{}"),
  ]).await;
  let market=gated(&base);
  let r=range(start,end,2);

  // 成功：走的是 /fapi/v1/klines，两根收好的日线都在。
  let data=klines(&market,&r,crate::review_domain::time(start).unwrap(),crate::review_domain::time(end).unwrap()).await.expect("bars");
  assert_eq!(data["bars"].as_array().map(Vec::len),Some(2));
  assert_eq!(data["coverage_complete"],true);
  assert!(seen.lock().unwrap()[0].starts_with("GET /fapi/v1/klines?symbol=BTCUSDT"),"{:?}",seen.lock().unwrap());

  // 451：不可重试，折成 BLOCKED（worker 按天退避），不按下限流闸门。
  let e=klines(&market,&r,crate::review_domain::time(start).unwrap(),crate::review_domain::time(end).unwrap()).await.unwrap_err();
  assert_eq!(e.1,BLOCKED);
  assert!(!crate::binance_gate::blocked(),"451 不是限流");

  // 418：记进进程级闸门，本次按可重试处理。
  let e=klines(&market,&r,crate::review_domain::time(start).unwrap(),crate::review_domain::time(end).unwrap()).await.unwrap_err();
  assert_eq!(e.1,"market_unavailable");
  assert!(crate::binance_gate::wait().is_some_and(|left|left>std::time::Duration::from_secs(290)),"418 的 Retry-After 按下整条出口");
  server.await.unwrap();

  // 闸门按着：连出站都不出站，照样是可重试的 market_unavailable。
  let before=seen.lock().unwrap().len();
  let e=klines(&market,&r,crate::review_domain::time(start).unwrap(),crate::review_domain::time(end).unwrap()).await.unwrap_err();
  assert_eq!(e.1,"market_unavailable");
  assert_eq!(seen.lock().unwrap().len(),before,"封禁期内不许出站");
  crate::binance_gate::clear();
 }

 #[tokio::test(start_paused=true)]
 async fn a_rate_limited_gateway_is_left_alone_until_the_cooldown_lapses() {
  *gateway_cooldown().lock().unwrap_or_else(|e|e.into_inner())=None;
  assert!(cooling().is_none());
  cool_down(std::time::Duration::from_secs(30));
  assert!(cooling().is_some_and(|left|left>std::time::Duration::from_secs(29)));
  // 第二次更短的冷却不许把已经记下的那条线拉近。
  cool_down(std::time::Duration::from_secs(1));
  assert!(cooling().is_some_and(|left|left>std::time::Duration::from_secs(28)));
  // 说得再离谱也有上限。
  cool_down(std::time::Duration::from_secs(9999));
  assert!(cooling().is_some_and(|left|left<=LONGEST_COOLDOWN));
  tokio::time::sleep(LONGEST_COOLDOWN+std::time::Duration::from_secs(1)).await;
  assert!(cooling().is_none(),"冷却过了就照常出站");
 }

 fn c(start:i64,close:&str)->crate::venues::coinbase::Candle {
  crate::venues::coinbase::Candle{start,open:close.into(),high:close.into(),low:close.into(),close:close.into(),volume:"1".into()}
 }
 #[test]
 fn coinbase_gaps_are_filled_flat_but_only_where_trades_provably_did_not_happen() {
  let now=10_000;
  // 中间缺一根：按上一根收盘价补平、量为 0。
  let (f,ok)=fill_gaps(&[c(0,"1"),c(120,"3")],None,0,180,60,now);
  assert!(ok);assert_eq!(f.iter().map(|c|(c.start,c.close.as_str(),c.volume.as_str())).collect::<Vec<_>>(),vec![(0,"1","1"),(60,"1","0"),(120,"3","1")]);
  // 末尾缺、而且刚收不久：可能只是还没写进去，不补，认不完整。
  let (f,ok)=fill_gaps(&[c(9_780,"1")],None,9_780,9_900,60,now);
  assert!(!ok);assert_eq!(f.len(),1);
  // 末尾缺、但已经收了很久：没成交，补。
  let (f,ok)=fill_gaps(&[c(0,"1")],None,0,180,60,now);
  assert!(ok);assert_eq!(f.len(),3);
  // 开头缺：有更早的收盘价就补，没有就认不完整。
  let (f,ok)=fill_gaps(&[c(60,"2")],Some("5".into()),0,120,60,now);
  assert!(ok);assert_eq!(f[0].close,"5");
  let (_,ok)=fill_gaps(&[c(60,"2")],None,0,120,60,now);
  assert!(!ok);
 }
 #[test]
 fn coinbase_weeks_are_built_from_whole_days_only() {
  let day=86_400i64;
  // 2026-09-21 是周一（周线的开盘日）。
  let monday=chrono::DateTime::parse_from_rfc3339("2026-09-21T00:00:00Z").unwrap().timestamp();
  let mut days:Vec<_>=(0..7).map(|i|{let mut x=c(monday+i*day,"10");x.high=format!("{}",20+i);x.low=format!("{}",5-i);x}).collect();
  days[6].close="11".into();
  let start=crate::review_domain::time(monday*1000).unwrap();let end=crate::review_domain::time((monday+7*day)*1000).unwrap();
  let bars=aggregate(&days,Interval::W1,Interval::D1,start,end).unwrap();
  assert_eq!(bars.len(),1);
  assert_eq!((bars[0].open.as_str(),bars[0].high.as_str(),bars[0].low.as_str(),bars[0].close.as_str()),("10","26","-1","11"));
  assert_eq!(bars[0].volume.as_deref(),Some("7"));
  // 少一天的那一周不出。
  assert!(aggregate(&days[..6],Interval::W1,Interval::D1,start,end).unwrap().is_empty());
  assert_eq!(coinbase_source(Interval::H8),Interval::H4);assert_eq!(coinbase_source(Interval::H1),Interval::H1);
 }
}
