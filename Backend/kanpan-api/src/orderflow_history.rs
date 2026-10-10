//! 主力订单流 · 服务端历史（2026-09-24，2026-09-25 改成分层常驻）。
//!
//! 手机上的订单流只在打开一只品种时才开始跟，关掉就断：刚打开时图上是空的，往左拖也没有。
//! 这里在 serve 进程里常驻跟踪，一单一行写进库（挂着的在 `orderflow_live`、结束的在 `orderflow_orders`）；手机打开品种先拉最近 24 小时，
//! 之后每分钟增量拉一次，往左拖再一天一天补（最多 3 天）。
//!
//! * 跟踪规则和手机那份（`OrderFlowModel.swift`）逐条一致，见 `model.rs`；簿的接续见 `book.rs`；
//!   帧的解码见 `feeds.rs`；连接池见 `hub.rs`；REST 快照队列见 `snapshots.rs`；分层见 `layers.rs`；
//!   资源闸门见 `resources.rs`；库见 `store.rs`。
//! * 只按**默认门槛**跟（`OrderFlowDefaults` 那张表 + 前一日收盘推的步长；非币按簿深标定，见下）。
//!   用户在手机上改过门槛的，手机拿到之后自己按自己的门槛过滤。
//! * 跟哪些币：主币、固定（美股 / 大宗 / 指数）、山寨（成交额前 40）、热点（四路信号，每小时）、按需（手机打开的）
//!   五层，总数最多 220 只，满了只踢按需与热点里最久没人要的；详见 `layers.rs`。
//!   `KANPAN_ORDERFLOW_LAYERS` 选开哪几层，缺省全开。
//! * **手机的行情转发永远优先**：这里的连接与 REST 全部自己开、自己限速（各家额度的一小份），
//!   资源闸门（RSS > 2.5 GB 或最近一分钟 CPU > 300%，且不超过所在 cgroup 上限的四分之三）一过就不再新增，并按热点 → 山寨 → 固定卸层，
//!   转发那一侧一概不动。
//! * 非币默认门槛：T = round125(0.03 × D)，夹 [5 万, 200 万]，D 为各 U 本位永续簿中间价 ±1% 以内买卖两侧美元之和；
//!   簿全部拿到首个快照时标定；有簿还没连上或快照还在排队就接着等（最多 10 分钟），不再有簿在等
//!   （或到了 10 分钟）之后 8 秒，用已就绪的标，之后簿都齐了再补标一次；每个 UTC 日重标一次。标定前不评估、不读回挂着的单，
//!   `/history` 回的 `thresholds.usdtPerp` 为空。一本簿都没有回退 200 万。
//! * 写库：挂着的单每 15 秒刷一次，只写新出现的、名义 / 成交 / 门槛变了 1% 以上的、以及 60 秒没写过的
//!   （刷新 `seen_ms`）；结束的单一结束就写；所有币合起来最多同时占 3 条库连接。进程重启读回挂着的单，
//!   缺席超过 2 分钟的按最后一次看到时失联结束。每小时滚动清理一次（3 天 + 20 GB 闸门）。
//! * 停机（SIGTERM）：和 axum 排空 HTTP 并行，各品种停止评估、写完手里的行，挂着的单**不结束**，
//!   一条 `UPDATE … FROM unnest` 把它们的 `seen_ms` 刷到停机那一刻，交给下次启动读回；整段最多 10 秒（见「停机」一节）。
//! * 接口 `GET /v1/market/orderflow/history?base=&from=&to=&minLifeMs=&limit=`：`to` 缺省为此刻，`from` 缺省为
//!   `to` 前 24 小时（带了 `limit` 的缺省 6 小时），区间最长 3 天；`minLifeMs`（0 到 1 天，缺省 0）滤掉存活不到它的已结束单，挂着的照回；
//!   已结束的单最多回 `limit`（1–5000）条，按出现时刻留最新的；不带 `limit` 的老请求（手机端）照旧只套 20 万行的上限，默认行为不变；
//!   挂着的（`to` 之前出现的）不受上限、不受 `from` 限制，一律全回。
//!   回 `{base, thresholds, trackedSinceMs, orders, nextBefore}`，自己压 gzip（请求带 `Accept-Encoding: gzip` 时）；
//!   `nextBefore` 是截到上限时回的最早那条已结束单的出现时刻（没截到为 null），下一页拿它当 `to` 再要。
//!   同一 (品种, from/to 所在分钟, minLifeMs, limit, 是否 gzip) 的请求只读一次库：并发的等同一次读，
//!   读完的压缩体缓存 60 秒（最多 64 份、32 MB，按最久没用的踢），区间按整分钟放宽读。
//!   没在跟的币回空表、`trackedSinceMs` 为此刻，并从这一刻开始跟（按需层）。`trackedSinceMs` 是这一段连着跟的起点：
//!   跟踪器断过十分钟以上（停掉、没人要）再起跟，从起跟那一刻重新算（0026 的 `alive_ms`）。
//! * 深度热力（网页版）：每 5 秒把每只的簿在中间价 ±5% 以内按步长分桶写进 `orderflow_heat`，
//!   接口 `GET /v1/market/orderflow/heat`，见 `heat.rs`。
//! * 大单与散户的分钟成交（网页版）：同一个跟踪任务把去重后的每笔成交按分钟记大单（≥ 门槛 / 50）与散户（< 1 万美元）的主动买卖额，
//!   写进 `orderflow_flow`，接口 `GET /v1/market/orderflow/flow`，见 `flow.rs`。
//! * 足迹图与秒线（网页版，2026-10-07）：同一批成交按交易所给的时刻记每分钟每个价位桶的主动买卖额（`orderflow_footprint`，
//!   接口 `GET /v1/market/orderflow/footprint`，见 `footprint.rs`），币安 U 本位永续的再记每秒的开高低收与量（`klines_seconds`，
//!   接口 `GET /v1/market/klines/seconds`，见 `seconds.rs`）；写库与清理共用 `minutes.rs`，各自的磁盘预算在 `storage_budget.rs`。
//! * 爆仓分钟聚合（网页版「大单」抽屉，2026-10-08）：另开三路连接收币安 U 本位 / 币本位与 OKX 的强平推送，只记在跟的 base，
//!   每分钟多空被平的美元额、笔数与最大一笔写进 `orderflow_liq`，接口 `GET /v1/market/orderflow/liq`，见 `liq.rs`。
//! * 这六条历史接口不要登录，同一来源地址同时最多 `PER_CLIENT`（24）条在处理，超了 429 `history_client_limit` + `Retry-After: 1`。
//! * 只在带库的 serve 进程里有；备用节点跑的是 metrics（没有库），不挂这条路由。
mod book;
mod favorites;
mod feeds;
mod flow;
mod footprint;
mod insights;
mod heat;
mod highlights;
mod hub;
mod layers;
mod liq;
mod minutes;
mod model;
mod resources;
mod seconds;
mod snapshots;
mod store;

use crate::AppState;
use crate::error::{ApiError,Params,Result};
use crate::orderflow_instruments::{self as instruments,Product,Venue};
use crate::venues::{binance::orderflow::KEY as BINANCE,bybit::orderflow::KEY as BYBIT,coinbase::orderflow::KEY as COINBASE,hyperliquid::orderflow::KEY as HYPERLIQUID,okx::orderflow::KEY as OKX};
use axum::extract::State;
use axum::http::{HeaderValue,header};
use axum::response::Response;
use axum::routing::get;
use axum::Router;
use book::{Action,Sequence,VenueInfo};
use feeds::Event;
use layers::Enabled;
use model::{BigOrder,Model,Notional,Restored,Thresholds};
use serde::Deserialize;
use serde_json::Value;
use sqlx::PgPool;
use std::collections::{HashMap,HashSet};
use std::sync::atomic::{AtomicBool,AtomicU8,AtomicU64,Ordering};
use std::sync::{Arc,Mutex,OnceLock};
use std::time::Duration;
use tokio::sync::{mpsc,watch};
use tokio::task::JoinHandle;

const PATH:&str="/v1/market/orderflow/history";
/// 一直跟的三只。
const ALWAYS:[&str;3]=layers::MAJORS;
/// 同时最多跟几只（五层合计）。
const MAX_BASES:usize=220;
/// 按需层（只因为有人要才跟的）最多几只。
const MAX_ON_DEMAND:usize=20;
/// 按需的多久没人要就停；山寨、热点掉榜之后再跟多久。
const IDLE_MS:i64=store::DAY_MS;
const LINGER_MS:i64=store::DAY_MS;
/// 历史接口不带 `limit` 的老请求，`from` 缺省 `to` 前多久；带了 `limit`（网页 2026-09-29 起）缺省最近 6 小时。
const DEFAULT_SPAN_MS:i64=store::DAY_MS;
const PAGED_SPAN_MS:i64=6*3_600_000;
const MAX_SPAN_MS:i64=store::RETENTION_MS;
/// 带 `limit` 的请求一页最多回几条已结束的单；挂着的不算在里面，一律全回。
/// 不带 `limit` 的老请求（手机端按 24 小时一窗取、不翻页）照旧只套 `store::MAX_ROWS`，默认行为和原来一样。
const MAX_PAGE:i64=5_000;
const EVALUATE:Duration=Duration::from_millis(500);
const FLUSH:Duration=Duration::from_secs(15);
const REFRESH:Duration=Duration::from_secs(10*60);
const THRESHOLDS_EVERY_MS:i64=60*60*1000;
const SWEEP:Duration=Duration::from_secs(10*60);
const PURGE:Duration=Duration::from_secs(60*60);
/// 快照失败之后隔多久再排：第一次 2 秒，之后每连着失败一次翻倍，最多 5 分钟；拿到一份就从头算。
/// 原来一律 2 秒：一本簿的快照一直拿不到（下架 / 结算中回 400、回的东西解析不了），它每 2 秒排一次，
/// 在限速队里（每条通道每分钟 30 份）按层抢在前面，主币上的一本就能把整条通道的配额吃光，别的簿都等不到快照。
const SNAPSHOT_RETRY_MS:i64=2_000;
const SNAPSHOT_RETRY_MAX_MS:i64=5*60_000;

/// 连着失败 `failures` 次（≥ 1）之后隔多久再排。
fn snapshot_backoff(failures:u32)->i64 {SNAPSHOT_RETRY_MS.saturating_mul(1i64<<failures.saturating_sub(1).min(20)).min(SNAPSHOT_RETRY_MAX_MS)}
/// 簿就绪撑过这么久才算真的接上了：之后再断档是新的一轮，马上重同步；撑不到就算这一轮重同步没成。
const RESYNC_STABLE_MS:i64=60_000;

/// 一次重同步（拿到的快照接不上、就绪之后断档、流内快照迟迟不来）要隔多久再做（毫秒，0 = 马上）。
/// `failures` 是这本簿连着没成的次数（和拉不到快照共用一个数）：就绪撑过 `RESYNC_STABLE_MS` 的从头算，
/// 一轮里第一次马上做，之后按 `snapshot_backoff` 往后排。
/// 原来这几条路都是马上重拉 / 重订：快照一直接不上（REST 快照落后于流、序号规则对不上）或刚就绪就断档的簿
/// 每轮只隔 0.5 秒又排一份，主币层的一本就能把整条通道每分钟 30 份的配额吃光（拉不到的那条路 2026-09-25
/// 已经退避了，这几条没有）；流内快照的簿则是一轮一次重订，OKX 按小时算的订阅次数、Coinbase 整条连接跟着耗。
fn resync_delay(failures:&mut u32,ready_since:Option<i64>,now:i64)->i64 {
 if ready_since.is_some_and(|t|now-t>=RESYNC_STABLE_MS) {*failures=0}
 *failures=failures.saturating_add(1);
 if *failures==1 {0} else {snapshot_backoff(*failures-1)}
}
/// 没变化的挂着的单多久重写一次（刷新 `seen_ms`）；须小于 `model::STALE_MS`（120 秒）。
const LIVE_REWRITE_MS:i64=60_000;
const SNAPSHOT_SETTLE:Duration=Duration::from_millis(500);
/// 非币门槛标定最多等多久（从订阅起）：满额 220 只冷启动时 U 本位快照按每分钟 30 份排，最后一份约 7 分钟后到。
const CALIBRATION_CAP_MS:i64=10*60_000;
/// 还拿不到步长（收盘没拉到）时隔多久再试。
const RESOLVE_RETRY:Duration=Duration::from_secs(30);
/// 成批起跟踪（进程启动、层重算）时两只之间隔多久：拉品种表、收盘、订阅都错开，不一口气打出去。
const START_GAP:Duration=Duration::from_millis(250);
/// 资源采样与层的节拍。
const SAMPLE:Duration=Duration::from_secs(15);
const LAYER_TICK:Duration=Duration::from_secs(60);
const HOT_EVERY_MS:i64=60*60*1000;
const FIXED_EVERY_MS:i64=10*60*1000;
/// 资源闸门连续多少分钟离线够远才放回一层（一层反复顶超时翻倍，见 [`Gate`]）。
const SHED_RECOVER_MINUTES:u32=10;
/// 放回的层反复把进程顶超时，等待最多翻到多少分钟。
const SHED_RECOVER_CAP_MINUTES:u32=120;
/// 放回之后多久之内又超算「这一层装不下」。
const SHED_FLAP_MS:i64=30*60_000;
/// 放回之后撑过多久没被再卸，等待回到 `SHED_RECOVER_MINUTES`。
const SHED_HOLD_MS:i64=60*60_000;

fn now_ms()->i64 {chrono::Utc::now().timestamp_millis()}

// ------------------------------------------------------------------ 品种表 → 簿

fn wire_product(p:Product)->&'static str {match p {Product::Spot=>"spot",Product::UsdtPerp=>"usdtPerp",Product::CoinPerp=>"coinPerp",Product::Delivery=>"delivery"}}

/// 这一行品种表接好了连接种类没有（[`info`] 认得的那几家）。
fn has_feed(v:&Venue)->bool {[BINANCE,OKX,COINBASE,BYBIT,HYPERLIQUID].contains(&v.exchange)}

/// 这只币此刻要跟的簿（品种表里接好了连接种类的那几家）。
async fn tracked_venues(base:&str)->Vec<Venue> {tracked(instruments::venues(base).await)}
fn tracked(rows:Vec<Venue>)->Vec<Venue> {tracked_with(rows,*BYBIT_SPOT_SHED.borrow())}
fn tracked_with(rows:Vec<Venue>,spot_shed:bool)->Vec<Venue> {rows.into_iter().filter(|v|has_feed(v)&&!(spot_shed&&bybit_spot(v))).collect()}
fn bybit_spot(v:&Venue)->bool {v.exchange==BYBIT&&v.product==Product::Spot}

/// 资源闸门卸的第一层是 Bybit 现货（[`shed_label`] 第 1 档）：同一只币币安 / OKX / Coinbase 的现货都在跟，
/// 它是五家里最可有可无的一份。卸下时各跟踪任务马上重取品种表（[`refresher`]），把它的簿停掉、挂着的单记失联；
/// 放回时同样马上重取、重新订上。
static BYBIT_SPOT_SHED:std::sync::LazyLock<watch::Sender<bool>>=std::sync::LazyLock::new(||watch::channel(false).0);

/// 品种表的一行 → 簿的身份。id 与手机上 `OrderFlowVenue.id` 同一个写法。
fn info(v:&Venue)->VenueInfo {
 let (exchange,label,sequence,in_band)=match v.exchange {
  BINANCE=>("binance","币安",if v.product==Product::Spot {Sequence::RangeOverlap} else {Sequence::PreviousFinalOverlap},false),
  OKX=>("okx","OKX",Sequence::PreviousFinalExact,true),
  COINBASE=>("coinbase","Coinbase",Sequence::StrictIncrementing,true),
  BYBIT=>("bybit","Bybit",Sequence::StrictIncrementing,true),
  HYPERLIQUID=>("hyperliquid","Hyperliquid",Sequence::SnapshotOnly,true),
  other=>unreachable!("{} has no feed kinds",other.0),
 };
 // 只推前 N 档、档位滑进滑出的（OKX 400、Bybit 1000、Hyperliquid 每帧整本）：窗口外的档不知道。
 let sliding=matches!(v.exchange,OKX|BYBIT|HYPERLIQUID);
 let product=wire_product(v.product);
 let notional=match v.notional {
  instruments::Notional::Linear{multiplier}=>Notional::Linear(multiplier),
  instruments::Notional::Inverse{contract_usd}=>Notional::Inverse(contract_usd),
 };
 VenueInfo{id:format!("{exchange}:{product}:{}",v.instrument),exchange,label,product,instrument:v.instrument.clone(),notional,
  price_scale:v.price_scale.unwrap_or(1).max(1) as f64,sequence,in_band,sliding}
}

// ------------------------------------------------------------------ 门槛

/// 币安 U 本位永续（门槛分档、是不是币、推步长都看它）。
fn binance_perp(venues:&[Venue])->Option<&Venue> {venues.iter().find(|v|v.exchange==BINANCE&&v.product==Product::UsdtPerp)}

/// 是不是币：主币是；跟踪器已经判过的照旧（`known`）；币安没有这只 U 本位永续的按币算；
/// 否则看它在合约表里的 `underlyingType` 是不是 COIN。合约表拿不到（`info` 为 None）回 None：不知道就不猜。
///
/// 原来拿不到合约表一律按币算：那一刻起跟的美股按币的成交额分档拿门槛、也不按簿深标定，一直错到这只停掉；
/// 每小时重算门槛时再撞上一次失败，已经在标定的美股也会被换成币的门槛。
fn crypto_kind(base:&str,perp:Option<&Venue>,known:Option<bool>,info:Option<&Value>)->Option<bool> {
 if model::is_major(base) {return Some(true)}
 if let Some(known)=known {return Some(known)}
 let Some(perp)=perp else {return Some(true)};
 let info=info?;
 Some(info["symbols"].as_array().and_then(|rows|rows.iter().find(|s|s["symbol"].as_str()==Some(perp.instrument.as_str())))
  .and_then(|s|s["underlyingType"].as_str()).is_none_or(|t|t=="COIN"))
}

async fn is_crypto(base:&str,perp:Option<&Venue>,known:Option<bool>)->Option<bool> {
 if let Some(kind)=crypto_kind(base,perp,known,None) {return Some(kind)}
 let info=crate::market_meta::exchange_info().await.ok()?;
 crypto_kind(base,perp,known,Some(&info))
}

fn number(v:&Value)->Option<f64> {
 let x=match v {Value::String(s)=>s.parse().ok()?,Value::Number(n)=>n.as_f64()?,_=>return None};
 (x as f64).is_finite().then_some(x)
}

/// 前一 UTC 日那根日线的收盘（照手机的 `previousClose`）。
fn previous_close(rows:&Value,day:i64)->Option<f64> {
 let rows=rows.as_array()?;
 let open=|r:&Value|r.get(0).and_then(|t|t.as_i64());
 let close=|r:&Value|r.get(4).and_then(number);
 rows.iter().rev().find(|r|open(r)==Some(day)).and_then(close)
  .or_else(||rows.iter().rev().find(|r|open(r).is_some_and(|t|t<day+store::DAY_MS)).and_then(close))
}

/// 按前一日收盘推步长：先看币安 U 本位永续，没有再看币安现货。都是每个币的价（去掉 `1000` 前缀的倍数）。
async fn derived_step(venues:&[Venue],day:i64)->Option<f64> {
 let spot=venues.iter().find(|v|v.exchange==BINANCE&&v.product==Product::Spot);
 for (venue,host) in [(binance_perp(venues),"https://www.binance.com/fapi/v1/klines"),(spot,"https://data-api.binance.vision/api/v3/klines")] {
  let Some(v)=venue else {continue};
  let Ok(rows)=crate::market_meta::get_json(&format!("{host}?symbol={}&interval=1d&limit=3",v.instrument)).await else {continue};
  let scale=v.price_scale.unwrap_or(1).max(1) as f64;
  if let Some(close)=previous_close(&rows,day) {
   if let Some(step)=model::derived_step(close/scale,Some(v.tick/scale)) {return Some(step)}
  }
 }
 None
}

/// 这只币此刻的默认门槛与步长（步长可能还是 None：收盘没拉到），以及它是不是币。
/// 非币的 U 本位门槛这里给的是回退值 200 万，真正用的是跟踪器按簿深标定的那个。
/// `known`：跟踪器起跟时已经判过是不是币，重算门槛时沿用；还没判过而合约表拿不到时回 None。
async fn resolve(base:&str,venues:&[Venue],now:i64,known:Option<bool>)->Option<(Thresholds,bool)> {
 let perp=binance_perp(venues);
 let crypto=is_crypto(base,perp,known).await?;
 let turnover=match perp {Some(p) if crypto&&!model::is_major(base)=>layers::turnover(&p.instrument).await,_=>None};
 let mut t=model::defaults(base,crypto,turnover);
 if t.step.is_none() {t.step=derived_step(venues,model::reference_day(now)).await;}
 Some((t,crypto))
}

// ------------------------------------------------------------------ 一只币的跟踪

/// 收件口里的一串帧按生效顺序处理：每一帧之前先把连接的开、交接、断吃掉。连接任务总是先发 Opened
/// 再推这条连接的帧，所以拿到一帧时它前面那条 Opened 已经在 `control` 里了，不会被帧抢先
/// （抢先的帧会因为簿还不认这条连接被丢掉）。
fn in_order<T>(control:&mut mpsc::UnboundedReceiver<T>,first:T,inbox:&mut mpsc::Receiver<T>,mut handle:impl FnMut(T)) {
 while let Ok(c)=control.try_recv() {handle(c);}
 handle(first);
 while let Ok(event)=inbox.try_recv() {
  while let Ok(c)=control.try_recv() {handle(c);}
  handle(event);
 }
}

/// 写库只走一个任务：挂着的与结束的按到达先后写，不会乱序把结束翻回挂着。
struct Write {step:f64,rows:Vec<(BigOrder,i64)>}
/// 跟踪任务到写库任务的通道长度。
const WRITES_QUEUE:usize=256;
/// 跟踪任务的收件口：连接任务往里 `try_send`，满了就丢帧（簿断档、重拉快照）。
const INBOX:usize=8192;

/// 所有币的写库任务合起来最多同时占这么多条库连接：连接池一共 8 条，还要留给账号、同步与读历史的请求。
/// 本地全开 154 只时，几十个跟踪任务同一时刻刷盘把池子占满，账号请求拿连接要等 2–3 秒（sqlx 慢获取告警）。
static WRITE_SLOTS:tokio::sync::Semaphore=tokio::sync::Semaphore::const_new(3);

/// 写失败之后隔多久再写：从 1 秒起翻倍，最多 1 分钟。
const WRITE_RETRY_MIN:Duration=Duration::from_secs(1);
const WRITE_RETRY_MAX:Duration=Duration::from_secs(60);
/// 跟踪停了之后还没写进去的最多再试多久（跟踪任务等写库任务结束才算收完尾，见 `Registry::stop`）。
const WRITE_DRAIN:Duration=Duration::from_secs(60);
/// 写库任务手里没有积压时多久记一次「还活着」（`orderflow_bases.alive_ms`，见 `store::continuous_since`）。
const ALIVE_EVERY:Duration=Duration::from_secs(60);
/// 一只币积压的行最多留多少：库长时间写不进去时先丢挂着的（它们一分钟之内会整行重写），再丢结束得最早的。
const PENDING_CAP:usize=50_000;

/// 还没写进库的行，一单只留一份。同一单后来的那份盖掉前面的——但结束的不被挂着的盖回去，
/// 和库里 upsert 的 `WHERE end_ms IS NULL` 同一个规矩。写失败的留在这里跟下一批一起写。
#[derive(Default)]
struct Pending {rows:HashMap<LiveKey,(f64,BigOrder,i64)>}

impl Pending {
 fn add(&mut self,w:Write) {
  for (order,seen) in w.rows {
   let key:LiveKey=(order.venue_id.clone(),order.side,order.bucket,order.first_seen_ms);
   if self.rows.get(&key).is_some_and(|(_,o,_)|o.end_ms.is_some()&&order.end_ms.is_none()) {continue}
   self.rows.insert(key,(w.step,order,seen));
  }
  if self.rows.len()>PENDING_CAP {self.shed();}
 }
 /// 超了上限：先丢挂着的，还超就丢结束得最早的。返回丢了几行。
 fn shed(&mut self)->usize {
  let before=self.rows.len();
  self.rows.retain(|_,(_,o,_)|o.end_ms.is_some());
  if self.rows.len()>PENDING_CAP {
   let mut oldest:Vec<(i64,LiveKey)>=self.rows.iter().map(|(k,(_,o,_))|(o.end_ms.unwrap_or(i64::MIN),k.clone())).collect();
   oldest.sort_unstable_by_key(|(end,_)|*end);
   for (_,key) in oldest.into_iter().take(self.rows.len()-PENDING_CAP) {self.rows.remove(&key);}
  }
  before-self.rows.len()
 }
 fn is_empty(&self)->bool {self.rows.is_empty()}
 /// 按步长分组、每组最多 500 行一批：写进去的从积压里拿掉，写失败的那一批与后面的都留着。
 fn batches(&self)->Vec<(f64,Vec<LiveKey>)> {
  let mut groups:HashMap<u64,Vec<LiveKey>>=HashMap::new();
  for (key,(step,_,_)) in &self.rows {groups.entry(step.to_bits()).or_default().push(key.clone());}
  groups.into_iter().flat_map(|(step,keys)|keys.chunks(500).map(|c|(f64::from_bits(step),c.to_vec())).collect::<Vec<_>>()).collect()
 }
 /// 一批要写的行此刻的样子（前面几批写的时候被上限丢掉的跳过）。
 fn rows_for(&self,keys:&[LiveKey])->Vec<(LiveKey,BigOrder,i64)> {
  keys.iter().filter_map(|k|self.rows.get(k).map(|(_,o,s)|(k.clone(),o.clone(),*s))).collect()
 }
 /// 这一批写进去了：从积压里拿掉——只拿掉写库期间没再变过的；变了的（新的一份、刚结束）留着下一批写。
 fn written(&mut self,rows:&[(LiveKey,BigOrder,i64)]) {
  for (k,o,s) in rows {
   if self.rows.get(k).is_some_and(|(_,now,seen)|now==o&&seen==s) {self.rows.remove(k);}
  }
 }
}

/// 等一条写库语句的时候照样收跟踪那边发来的：库慢（锁、autovacuum、慢盘，serve 的语句死线是 20 秒）时
/// 不收的话，通道一满跟踪任务就卡在 `send` 上，帧口没人收，连接任务往满的口里 `try_send` 的帧全丢。
async fn receiving<T>(work:impl std::future::Future<Output=T>,rx:&mut mpsc::Receiver<Write>,open:&mut bool,pending:&mut Pending)->T {
 tokio::pin!(work);
 loop {
  tokio::select! {
   out=&mut work=>return out,
   w=rx.recv(),if *open=>match w {Some(w)=>pending.add(w),None=>*open=false},
  }
 }
}

/// 把积压的按批写进去，写的时候照样收（见 `receiving`）。
async fn flush(pool:&PgPool,base:&str,rx:&mut mpsc::Receiver<Write>,open:&mut bool,pending:&mut Pending)->sqlx::Result<()> {
 for (step,keys) in pending.batches() {
  let rows=pending.rows_for(&keys);
  if rows.is_empty() {continue}
  let batch:Vec<(BigOrder,i64)>=rows.iter().map(|(_,o,s)|(o.clone(),*s)).collect();
  receiving(store::upsert(pool,base,step,&batch),rx,open,pending).await?;
  pending.written(&rows);
 }
 Ok(())
}

/// 一只币的写库任务。库写不进去（重启、连接池满、语句超时）时整批留着退避重写；排连接、写库、退避的时候
/// 都照常收跟踪那边发来的，不让跟踪任务卡在 `send` 上；原来失败就记一条日志丢掉，结束的单丢了，库里那行就一直挂成「进行中」。
/// 手里的都写进去了，每分钟记一次「还活着」。
async fn writer(pool:PgPool,base:String,mut rx:mpsc::Receiver<Write>) {
 let mut pending=Pending::default();
 let mut backoff=WRITE_RETRY_MIN;
 let mut open=true;
 let mut drain_until=None;
 let mut alive_at=tokio::time::Instant::now();
 loop {
  if pending.is_empty() {
   if !open {return}
   tokio::select! {
    w=rx.recv()=>match w {Some(w)=>pending.add(w),None=>return},
    _=tokio::time::sleep_until(alive_at)=>{},
   }
  }
  while let Ok(w)=rx.try_recv() {pending.add(w);}
  let result={
   // 排库连接（全进程 3 条）的时候也接着收：两百多只一起刷盘时可能要排上好一阵，这期间通道满了跟踪任务就卡在 send 上。
   let slot=loop {
    tokio::select! {
     slot=WRITE_SLOTS.acquire()=>break slot,
     w=rx.recv(),if open=>match w {Some(w)=>pending.add(w),None=>open=false},
    }
   };
   let Ok(_slot)=slot else {return};
   let mut result=flush(&pool,&base,&mut rx,&mut open,&mut pending).await;
   if result.is_ok()&&tokio::time::Instant::now()>=alive_at {
    result=receiving(store::alive(&pool,&base,now_ms()),&mut rx,&mut open,&mut pending).await;
    if result.is_ok() {alive_at=tokio::time::Instant::now()+ALIVE_EVERY;}
   }
   result
  };
  match result {
   Ok(())=>backoff=WRITE_RETRY_MIN,
   Err(e)=>{
    tracing::warn!("Orderflow history: {base} write failed ({} rows waiting, retry in {backoff:?}): {e}",pending.rows.len());
    let wake=tokio::time::Instant::now()+backoff;
    backoff=(backoff*2).min(WRITE_RETRY_MAX);
    // 等的时候接着收，不让跟踪那边的 send 堵住。
    while open {
     tokio::select! {
      _=tokio::time::sleep_until(wake)=>break,
      w=rx.recv()=>match w {Some(w)=>pending.add(w),None=>open=false},
     }
    }
    if !open {
     let until=*drain_until.get_or_insert_with(||tokio::time::Instant::now()+WRITE_DRAIN);
     if tokio::time::Instant::now()>=until {
      tracing::warn!("Orderflow history: {base} stopped with {} rows unwritten (restore / purge will close them)",pending.rows.len());
      return;
     }
     tokio::time::sleep_until(wake.min(until)).await;
    }
   },
  }
 }
}

/// 非币门槛的标定（见模块说明）。
struct Calibration {
 /// 非币才要标。
 needed:bool,
 /// 标出来的门槛与标定那天（`reference_day`）。
 value:Option<f64>,
 day:Option<i64>,
 /// 上一次标定时不是所有簿都就绪：等它们都就绪了再补标一次（只补一次）。
 partial:bool,
 /// 8 秒从哪一刻起算：订阅那一刻；之后只要还有簿没连上（币安的新簿要攒 5–15 秒成批开连接）、
 /// 或者它的快照还在排队，就往后推——这两段等待是这里的连接批次与快照限速造成的，
 /// 不该让 OKX 那一本（流内快照、立刻就绪）单独把门槛标了。最多等 `CALIBRATION_CAP_MS`。
 since:i64,
 subscribed:i64,
 /// 标定之前读回来的挂单与读库那一刻：标定之后再读回（照手机：标定前不评估、不读回）。
 /// 「缺席超过 `STALE_MS` 算失联」按读库那一刻算，不按标定那一刻——标定要等币安的快照排队，
 /// 重启时排几分钟是常事（2026-09-27 线上一次最长等 237 秒），按标定时刻算，库里最后一次
 /// 看到本来就可能落后 75 秒（`LIVE_REWRITE_MS` + 写库间隔）的单几乎全被判失联，
 /// 一两分钟后又在同一档被当成新单挂出来——每次部署非币那一千多条假失联就是这么来的。
 restored:Option<(Vec<Restored>,i64)>,
}

impl Calibration {
 /// 此刻该不该标：第一次——簿全就绪、没有簿，或者至少一本就绪且 8 秒里没有簿还在等连接 / 等快照
 /// （等了 `CALIBRATION_CAP_MS` 就不再等）；之后——跨了 UTC 日，或上次只标了一部分簿、现在都就绪了。
 fn due(&mut self,now:i64,day:i64,total:usize,ready:usize,waiting:bool)->bool {
  if !self.needed {return false}
  if self.value.is_none() {
   if waiting&&now-self.subscribed<CALIBRATION_CAP_MS {self.since=now;}
   return total==0||ready==total||(ready>=1&&now-self.since>=model::CALIBRATION_WAIT_MS)
  }
  if self.partial&&total>0&&ready==total {return true}
  self.day!=Some(day)&&ready>0
 }
}

struct Tracker {
 base:String,
 model:Model,
 events:mpsc::Sender<Event>,
 /// 连接的开、交接、断（不丢，见 `hub.rs`）。
 control:mpsc::UnboundedSender<Event>,
 open:HashSet<String>,
 /// 排着的快照：簿 → 那份请求的 epoch。
 inflight:HashMap<String,u64>,
 retry:HashMap<String,i64>,
 /// 每本簿连着失败了几次快照（拿到一份清零）。
 failures:HashMap<String,u32>,
 /// 每本簿此刻的 epoch，快照队列按它丢过期的请求。
 epochs:HashMap<String,Arc<AtomicU64>>,
 /// 每本簿最后一笔成交号（换连接的重叠期里两条连接都推同一笔，按号去重）。
 last_trade:HashMap<String,i64>,
 /// 这一分钟的大单 / 散户成交（去重之后，见 `flow.rs`）。
 flow:flow::Acc,
 /// 这几分钟的足迹（价位桶 × 主动买卖，见 `footprint.rs`）与币安 U 本位永续的秒线（见 `seconds.rs`）。
 footprint:footprint::Acc,
 insights:insights::Acc,
 seconds:seconds::Acc,
 /// 要点引擎的带子：参考永续每分钟的开高低收、现货最新价、每分钟一份挂着的墙（见 `highlights`）。
 tape:highlights::Tape,
 /// 挂着的单上次写库时的量、成交、门槛与时刻（见 `changed_live`）。
 written:HashMap<LiveKey,(f64,f64,f64,i64)>,
 priority:Arc<AtomicU8>,
 writes:mpsc::Sender<Write>,
 calibration:Calibration,
 /// 订阅按这套门槛挑产品（非币标定之前 `model.thresholds.usdt_perp` 是空的，但 U 本位永续要订）。
 planned:Thresholds,
 shared:watch::Sender<Thresholds>,
}

impl Tracker {
 fn step(&self)->f64 {self.model.thresholds.step.unwrap_or(0.0)}
 fn calibrating(&self)->bool {self.calibration.needed&&self.calibration.value.is_none()}

 fn add_venues(&mut self,venues:&[Venue]) {
  for v in venues.iter().filter(|v|self.planned.of(wire_product(v.product)).is_some()) {
   let scale=v.price_scale.unwrap_or(1).max(1) as f64;
   if v.product!=Product::Delivery {self.footprint.tick(v.tick/scale);self.insights.register(&info(v),v.tick/scale);}
   if v.exchange==BINANCE&&v.product==Product::UsdtPerp {
    self.seconds.venue(seconds::Venue{id:info(v).id,symbol:v.instrument.clone(),tick:v.tick,scale});
   }
  }
  let known:HashSet<String>=self.model.venue_ids().into_iter().collect();
  let fresh:Vec<VenueInfo>=venues.iter().filter(|v|self.planned.of(wire_product(v.product)).is_some()).map(info).filter(|v|!known.contains(&v.id)).collect();
  if fresh.is_empty() {return}
  tracing::debug!("Orderflow history: {} tracks {}",self.base,fresh.iter().map(|v|v.id.as_str()).collect::<Vec<_>>().join(", "));
  for v in &fresh {self.model.add_venue(v.clone());}
  hub::add(fresh,&self.events,&self.control);
 }

 /// 资源闸门卸下 Bybit 现货：停掉它的簿，挂着的单按最后一次看到失联结束。
 fn drop_bybit_spot(&mut self) {
  let ids:Vec<String>=self.model.venue_ids().into_iter().filter(|id|id.starts_with("bybit:spot:")).collect();
  if ids.is_empty() {return}
  for id in &ids {
   self.model.remove_venue(id);
   self.insights.remove(id,now_ms());
   self.open.remove(id);self.inflight.remove(id);self.retry.remove(id);self.failures.remove(id);self.epochs.remove(id);self.last_trade.remove(id);
  }
  tracing::debug!("Orderflow history: {} sheds {}",self.base,ids.join(", "));
  hub::remove(ids,&self.events);
 }

 fn sync_epoch(&mut self,id:&str) {
  let Some(epoch)=self.model.book_mut(id).map(|b|b.epoch) else {return};
  self.epochs.entry(id.to_string()).or_insert_with(||Arc::new(AtomicU64::new(0))).store(epoch,Ordering::Relaxed);
 }

 fn act(&mut self,venue:&str,action:Action) {
  match action {
   Action::None=>{},
   Action::Resubscribe=>hub::resubscribe(venue.to_string()),
   Action::FetchSnapshot=>self.fetch(venue,SNAPSHOT_SETTLE),
  }
 }

 /// 排一份 REST 快照（全进程一条限速队列，见 `snapshots.rs`）。同一 epoch 已经排着就不重复排。
 fn fetch(&mut self,venue:&str,settle:Duration) {
  let Some(book)=self.model.book_mut(venue) else {return};
  let (info,epoch)=(book.venue.clone(),book.epoch);
  if self.inflight.get(venue)==Some(&epoch) {return}
  self.inflight.insert(venue.to_string(),epoch);
  self.retry.remove(venue);
  self.sync_epoch(venue);
  let Some(current)=self.epochs.get(venue).cloned() else {return};
  snapshots::request(snapshots::Request{venue:info,epoch,priority:self.priority.clone(),not_before:tokio::time::Instant::now()+settle,events:self.events.clone(),current});
 }

 /// 帧或快照引出的重同步：一轮里第一次马上做，连着没成的按退避排进 `retry`（见 `resync_delay`）。
 /// 已经排着一次的不再加码（流内快照的簿等快照期间每分钟会再要一次）。
 fn resync(&mut self,venue:&str,action:Action,ready_since:Option<i64>,now:i64) {
  if action==Action::None||self.retry.contains_key(venue) {return}
  let failures=self.failures.entry(venue.to_string()).or_insert(0);
  let delay=resync_delay(failures,ready_since,now);
  if *failures==6 {tracing::warn!("Orderflow history: {venue} snapshot failed or did not line up 6 times in a row, retrying every {}s at most",SNAPSHOT_RETRY_MAX_MS/1000);}
  if delay==0 {self.act(venue,action)} else {self.retry.insert(venue.to_string(),now+delay);}
 }

 fn handle(&mut self,event:Event) {
  let now=now_ms();
  match event {
   Event::Opened{venues,connection}=>for id in venues {
    self.open.insert(id.clone());
    let action=self.model.book_mut(&id).map_or(Action::None,|b|b.opened(connection));
    self.sync_epoch(&id);
    self.act(&id,action);
   },
   // 连接池换连接（24 小时前换新、合并）：还连着的簿接着用，两条连接的帧都认；没连着的按新连接从头开。
   Event::Handover{venues,connection}=>for id in venues {
    let was_open=self.open.contains(&id);
    let action=self.model.book_mut(&id).map_or(Action::None,|b|if was_open {b.handover(connection)} else {b.opened(connection)});
    self.open.insert(id.clone());
    self.sync_epoch(&id);
    self.act(&id,action);
   },
   Event::Closed{venues,connection}=>for id in venues {
    if self.model.book_mut(&id).is_some_and(|b|b.connection==connection) {self.open.remove(&id);}
    self.model.closed(&id,connection);
    self.sync_epoch(&id);
   },
   Event::Frame{venue,connection,message}=>{
    let ready_since=self.model.book_mut(&venue).and_then(|b|b.ready_since());
    let action=self.model.ingest(&venue,connection,message,now);
    self.resync(&venue,action,ready_since,now);
   },
   Event::TradeStream{venues,connection,online}=>for id in venues {self.insights.stream(&id,connection,online,now);},
   Event::Trade{venue,trade,id,at,token}=>{
    if let Some(id)=id {
     let last=self.last_trade.entry(venue.clone()).or_insert(i64::MIN);
     if id<=*last {return}
     *last=id;
    }
    let usd=self.model.book_mut(&venue).map_or(0.0,|b|b.venue.notional.usd(trade.price,trade.quantity));
    let buy=flow::is_buy(trade.hit);
    flow::submit(&self.base,self.flow.add(usd,buy,flow::big_cut(&self.model.thresholds),now));
    // 足迹与秒线按交易所给的成交时刻分分钟、分秒（交割合约有基差，不进足迹）。
    let at=minutes::trade_time(at,now);
    self.tape.trade(&self.base,&venue,trade.price,at);
    self.insights.add(&venue,trade.price,usd,buy,token.as_deref(),at,now,flow::big_cut(&self.model.thresholds));
    if !venue.contains(":delivery:") {self.footprint.add(trade.price,usd,buy,at);}
    if venue.starts_with(seconds::VENUE_PREFIX) {self.seconds.add(&venue,trade.price,trade.quantity,buy,at);}
    self.model.trade(&venue,trade,now);
   },
   Event::Snapshot{venue,epoch,snapshot}=>{
    if self.inflight.get(&venue)==Some(&epoch) {self.inflight.remove(&venue);}
    let Some(book)=self.model.book_mut(&venue) else {return};
    // 排队期间断过线：这份是上一轮的，新一轮的请求在 opened 时已经排上了。
    if book.epoch!=epoch {return}
    match snapshot {
     Some(s)=>{let ready_since=book.ready_since();let action=book.snapshot(s,now);self.resync(&venue,action,ready_since,now);},
     None=>{
      let failures=self.failures.entry(venue.clone()).or_insert(0);
      *failures+=1;
      if *failures==6 {tracing::warn!("Orderflow history: {venue} snapshot failed or did not line up 6 times in a row, retrying every {}s at most",SNAPSHOT_RETRY_MAX_MS/1000);}
      let at=now+snapshot_backoff(*failures);
      self.retry.insert(venue,at);
     },
    }
   },
  }
 }

 /// 到点的重拉 / 重订：只管还连着、还没就绪的簿（快照在流里的重订，不在的拉 REST）。
 fn due_retries(&mut self,now:i64) {
  let due:Vec<String>=self.retry.iter().filter(|(_,at)|**at<=now).map(|(v,_)|v.clone()).collect();
  for venue in due {
   self.retry.remove(&venue);
   if !self.open.contains(&venue) {continue}
   let Some(book)=self.model.book_mut(&venue) else {continue};
   if book.is_ready() {continue}
   if book.venue.in_band {hub::resubscribe(venue)} else {self.fetch(&venue,Duration::ZERO)}
  }
 }

 /// 非币门槛：到点就标，跨 UTC 日重标。第一次标完才开始评估、读回挂着的单。
 fn calibrate(&mut self,now:i64) {
  if !self.calibration.needed {return}
  let day=model::reference_day(now);
  let books:Vec<String>=self.model.venue_ids();
  let total=books.len();
  let ready=self.model.ready_count();
  let waiting=books.iter().any(|id|!self.open.contains(id)||self.inflight.contains_key(id));
  if !self.calibration.due(now,day,total,ready,waiting) {return}
  let depth=self.model.depth_usd(model::CALIBRATION_BPS);
  let value=model::calibrated_threshold(depth);
  let first=self.calibration.value.is_none();
  self.calibration.value=Some(value);
  self.calibration.day=Some(day);
  self.calibration.partial=ready<total;
  tracing::info!("Orderflow history: {} usdtPerp threshold calibrated to {value} (±1% depth {depth:.0} USD over {ready}/{total} books)",self.base);
  let mut next=self.model.thresholds;
  next.usdt_perp=Some(value);
  if next!=self.model.thresholds {self.model.set_thresholds(next,now);}
  self.shared.send_replace(next);
  if first && let Some((rows,read_at))=self.calibration.restored.take() {
   let n=rows.len();
   self.model.restore(rows,read_at);
   if n>0 {tracing::info!("Orderflow history: {} restored {n} live orders after calibration ({} ended as lost)",self.base,self.model.ended.len());}
  }
 }

 /// 重取的品种表与门槛到了：换门槛、补订新挂牌的。
 async fn refreshed(&mut self,r:Refreshed) {
  if let Some(mut next)=r.thresholds {
   self.planned=next;
   if self.calibration.needed {next.usdt_perp=self.calibration.value;}
   if next!=self.model.thresholds {
    tracing::info!("Orderflow history: {} thresholds {:?} -> {next:?}",self.base,self.model.thresholds);
    self.model.set_thresholds(next,now_ms());
    self.shared.send_replace(next);
   }
  }
  self.add_venues(&r.venues);
  if *BYBIT_SPOT_SHED.borrow() {self.drop_bybit_spot();}
  self.write_ended().await;
  tracing::debug!("Orderflow history: {} {}/{} books ready, {} live",self.model.base,self.model.ready_count(),self.model.venue_ids().len(),self.model.live_count());
 }

 async fn write_ended(&mut self) {
  let ended=self.model.take_ended();
  if ended.is_empty() {return}
  highlights::ended(&self.base,&ended);
  let rows=ended.into_iter().map(|o|{let at=o.end_ms.unwrap_or(o.first_seen_ms);(o,at)}).collect();
  let _=self.writes.send(Write{step:self.step(),rows}).await;
 }

 async fn write_live(&mut self) {
  let rows=changed_live(self.model.live(),&mut self.written,now_ms(),LIVE_REWRITE_MS);
  if rows.is_empty() {return}
  let _=self.writes.send(Write{step:self.step(),rows}).await;
 }

 /// 停机（SIGTERM）：挂着的照旧挂着，不 `model.stop()` 判失联——下一个进程读回来接着跟。结束了还没写的、
 /// 新出现或变过还没写的交给写库任务；所有挂着的单的「最后一次看到」交回去，由 [`shutdown`] 一句 UPDATE 刷掉
 /// （原来停机前最后一次刷 `seen_ms` 可能是 60 秒前，再加停机、起跟、标定就过了 `model::STALE_MS`）。
 async fn hand_over(&mut self)->Final {
  self.write_ended().await;
  flow::submit(&self.base,self.flow.take());
  let fp=self.footprint.take();
  highlights::footprint(&self.base,&fp);
  footprint::submit(&self.base,fp);
  insights::submit(&self.base,self.insights.take(now_ms()));
  seconds::submit(&self.base,self.seconds.take());
  let live=self.model.live();
  let rows=changed_live(live.clone(),&mut self.written,now_ms(),i64::MAX);
  if !rows.is_empty() {let _=self.writes.send(Write{step:self.step(),rows}).await;}
  Final{base:self.base.clone(),live:live.into_iter().map(|(o,seen)|((o.venue_id,o.side,o.bucket,o.first_seen_ms),seen)).collect()}
 }
}

/// 一条挂着的单在库里的身份：簿、侧、桶、出现时刻。
type LiveKey=(String,book::Side,i64,i64);

/// 这一轮要写的挂着的单：新出现的、量或成交或门槛变了 1% 以上的、以及上次写已经过了 `rewrite_after`（`LIVE_REWRITE_MS`）的
/// （`seen_ms` 要赶在 `model::STALE_MS` 之前刷新，重启读回时才不会被当成失联）。220 只全开时每 15 秒整表重写
/// 一遍是本地实测里 Postgres 出现慢语句的原因，大部分墙在两次刷新之间根本没动。
fn changed_live(rows:Vec<(BigOrder,i64)>,written:&mut HashMap<LiveKey,(f64,f64,f64,i64)>,now:i64,rewrite_after:i64)->Vec<(BigOrder,i64)> {
 let moved=|a:f64,b:f64|(a-b).abs()>b.abs()*0.01;
 let mut keep=HashSet::new();
 let mut out=Vec::new();
 for (order,seen) in rows {
  let key:LiveKey=(order.venue_id.clone(),order.side,order.bucket,order.first_seen_ms);
  let fresh=(order.notional,order.filled_notional,order.threshold);
  let due=match written.get(&key) {
   None=>true,
   Some(&(n,f,t,at))=>moved(fresh.0,n)||moved(fresh.1,f)||moved(fresh.2,t)||now-at>=rewrite_after,
  };
  if due {written.insert(key.clone(),(fresh.0,fresh.1,fresh.2,now));out.push((order,seen));}
  keep.insert(key);
 }
 written.retain(|k,_|keep.contains(k));
 out
}

/// 品种表与门槛的一次重取：品种表每次都取，门槛到点才重算（`thresholds` 为 None = 这次没算或没算出步长）。
struct Refreshed {venues:Vec<Venue>,thresholds:Option<Thresholds>}

/// 每 `every` 重取一次品种表、每小时（跨 UTC 日立刻）重算一次门槛，结果发回跟踪任务。跟踪任务停了（收口关了）就退出，
/// 取到一半也不等。
/// 原来这些在跟踪任务的 select 里就地 await：网络慢时一次要几十秒到几分钟（每个请求 20 秒超时，山寨要 24h 行情与两份
/// 日线，行情那份在单飞锁后面排、失败不缓存，排在后面的挨个再超时一遍），这期间收件口没人收，连接任务往满口
/// `try_send` 的帧全丢，簿断档、重拉快照。
async fn refresher<F,Fut>(tx:mpsc::Sender<Refreshed>,every:Duration,mut fetch:F)
where F:FnMut(bool)->Fut,Fut:std::future::Future<Output=Refreshed> {
 let mut tick=tokio::time::interval_at(tokio::time::Instant::now()+every,every);
 tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
 let (mut resolved_at,mut resolved_day)=(now_ms(),model::reference_day(now_ms()));
 let mut spot_shed=BYBIT_SPOT_SHED.subscribe();
 spot_shed.mark_unchanged();
 loop {
  // Bybit 现货卸下 / 放回：不等下一拍，马上重取。
  tokio::select! {_=tx.closed()=>return,_=tick.tick()=>{},Ok(())=spot_shed.changed()=>{}}
  let now=now_ms();
  let due=now-resolved_at>=THRESHOLDS_EVERY_MS||model::reference_day(now)!=resolved_day;
  let r=tokio::select! {_=tx.closed()=>return,r=fetch(due)=>r};
  if r.thresholds.is_some() {resolved_at=now;resolved_day=model::reference_day(now);}
  if tx.send(r).await.is_err() {return}
 }
}

/// 跟踪任务的主循环：收帧、评估、刷盘；品种表与门槛由 `refresher` 在旁边取，取好了发回来就地换上。
/// 停了（`stop`）或进程要退出（`closing`，见 [`shutdown`]）把跟踪器交回去收尾；后者第二个值为 true。
#[allow(clippy::too_many_arguments)]
async fn run<F,Fut>(mut t:Tracker,mut inbox:mpsc::Receiver<Event>,mut control_rx:mpsc::UnboundedReceiver<Event>,mut stop:watch::Receiver<bool>,
 mut closing:watch::Receiver<bool>,every:Duration,fetch:F)->(Tracker,bool)
where F:FnMut(bool)->Fut+Send+'static,Fut:std::future::Future<Output=Refreshed>+Send+'static {
 let mut evaluate=tokio::time::interval(EVALUATE);
 evaluate.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
 let mut flush=tokio::time::interval_at(tokio::time::Instant::now()+FLUSH,FLUSH);
 // 深度热力的快照：对齐到墙钟 5 秒格的中间（见 `heat.rs`）。
 let mut heat_tick=tokio::time::interval_at(tokio::time::Instant::now()+heat::first_tick(now_ms()),Duration::from_millis(heat::BUCKET_MS as u64));
 heat_tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
 let (refreshed_tx,mut refreshed)=mpsc::channel::<Refreshed>(1);
 let refresher=tokio::spawn(refresher(refreshed_tx,every,fetch));
 loop {
  tokio::select! {
   // 发送端没了（只有测试里会）是 false，这一支本轮不再参与。
   true=async {closing.wait_for(|c|*c).await.is_ok()}=>{refresher.abort();return (t,true)},
   _=stop.changed()=>break,
   Some(event)=control_rx.recv()=>{t.handle(event);while let Ok(event)=control_rx.try_recv() {t.handle(event);}},
   // 一口气把排着的都吃掉再评估，别让评估插在一串帧中间。
   Some(event)=inbox.recv()=>in_order(&mut control_rx,event,&mut inbox,|event|t.handle(event)),
   _=evaluate.tick()=>{
    let now=now_ms();
    t.calibrate(now);
    if t.calibrating() {t.model.trim();} else {t.model.evaluate(now);}
    // 大单条件提醒（`conditions::walls`）：有人挂着这只 base 的才摊出来，评估完当场判，不等写库。
    if !t.calibrating()&&crate::conditions::walls::watching(&t.base) {
     let walls:Vec<crate::conditions::walls::WallView>=t.model.live().into_iter().map(|(o,_)|crate::conditions::walls::WallView{
      key:format!("{}/{}/{}/{}",o.venue_id,o.product,o.side.wire(),o.bucket),exchange:o.exchange,product:o.product,side:o.side.wire(),
      price:o.price,notional:o.notional,first_seen_ms:o.first_seen_ms}).collect();
     crate::conditions::walls::observe(&t.base,&walls,now);
    }
    t.due_retries(now);
    flow::submit(&t.base,t.flow.roll(now));
    let fp=t.footprint.roll(now);
    highlights::footprint(&t.base,&fp);
    footprint::submit(&t.base,fp);
    t.tape.roll(&t.base,now);
    if !t.calibrating() {t.tape.walls(&t.base,now,||t.model.live());}
    insights::submit(&t.base,t.insights.roll(now,flow::big_cut(&t.model.thresholds)));
    seconds::submit(&t.base,t.seconds.roll(now));
    t.write_ended().await;
   },
   _=flush.tick()=>t.write_live().await,
   _=heat_tick.tick()=>if !t.calibrating() {heat::submit(heat::snapshot(&mut t.model,now_ms()))},
   Some(r)=refreshed.recv()=>t.refreshed(r).await,
  }
 }
 refresher.abort();
 (t,false)
}

/// 拿品种表与门槛，直到步长有了。停了返回 None。
async fn prepare(base:&str,stop:&mut watch::Receiver<bool>)->Option<(Vec<Venue>,Thresholds,bool)> {
 loop {
  let venues=tracked_venues(base).await;
  let resolved=if venues.is_empty() {None} else {resolve(base,&venues,now_ms(),None).await};
  match resolved {
   Some((thresholds,crypto)) if thresholds.step.is_some()=>return Some((venues,thresholds,crypto)),
   Some((thresholds,_))=>tracing::info!("Orderflow history: {base} not ready ({} venues, step {:?}), retrying",venues.len(),thresholds.step),
   None=>tracing::info!("Orderflow history: {base} not ready ({} venues, coin or not unknown), retrying",venues.len()),
  }
  tokio::select! {_=stop.changed()=>return None,_=tokio::time::sleep(RESOLVE_RETRY)=>{}}
 }
}

async fn track(pool:PgPool,base:String,shared:watch::Sender<Thresholds>,mut stop:watch::Receiver<bool>,priority:Arc<AtomicU8>,delay:Duration,
 after:Option<JoinHandle<()>>) {
 // 上一任还在收尾：等它把结束的单写进库，再读回挂着的。
 // 等的时候被停：什么也不做，但照样等上一任收完尾再结束——注册表把这个任务当成「上一任」交给下一任等，
 // 它先走了下一任就等了个空，会和还在落库的上一任同时跑（起停反复时的链）。
 if let Some(mut previous)=after {
  tokio::select! {biased;_=stop.changed()=>{let _=previous.await;return},_=&mut previous=>{}}
 }
 if !delay.is_zero() {
  tokio::select! {_=stop.changed()=>return,_=tokio::time::sleep(delay)=>{}}
 }
 let Some((venues,thresholds,crypto))=prepare(&base,&mut stop).await else {return};
 if let Err(e)=store::start(&pool,&base,now_ms()).await {tracing::warn!("Orderflow history: {base} not recorded: {e}");}
 let needed=!crypto;
 let mut published=thresholds;
 if needed {published.usdt_perp=None;}
 shared.send_replace(published);
 let (events,inbox)=mpsc::channel::<Event>(INBOX);
 let (control,control_rx)=mpsc::unbounded_channel::<Event>();
 let (writes,rx)=mpsc::channel::<Write>(WRITES_QUEUE);
 let writer=tokio::spawn(writer(pool.clone(),base.clone(),rx));
 let mut t=Tracker{base:base.clone(),model:Model::new(&base,published),events,control,open:HashSet::new(),inflight:HashMap::new(),retry:HashMap::new(),failures:HashMap::new(),
  epochs:HashMap::new(),last_trade:HashMap::new(),flow:flow::Acc::default(),footprint:footprint::Acc::default(),insights:insights::Acc::new(&base,now_ms()),seconds:seconds::Acc::default(),tape:highlights::Tape::default(),written:HashMap::new(),priority,writes,
  calibration:Calibration{needed,value:None,day:None,partial:false,since:now_ms(),subscribed:now_ms(),restored:None},planned:thresholds,shared};
 match store::live(&pool,&base).await {
  Ok(rows) if needed=>t.calibration.restored=Some((rows,now_ms())),
  Ok(rows)=>{let n=rows.len();t.model.restore(rows,now_ms());if n>0 {tracing::info!("Orderflow history: {base} restored {n} live orders ({} ended as lost)",t.model.ended.len());}},
  Err(e)=>tracing::warn!("Orderflow history: {base} restore failed: {e}"),
 }
 t.write_ended().await;
 if let Err(e)=t.insights.restore(&pool,now_ms()).await {tracing::warn!("Orderflow insights: {base} replay checkpoint unreadable: {e}");}
 t.add_venues(&venues);
 (t.calibration.since,t.calibration.subscribed)=(now_ms(),now_ms());
 let fetch={let base=base.clone();move |due:bool|{let base=base.clone();async move {
  let venues=tracked_venues(&base).await;
  let thresholds=if due {resolve(&base,&venues,now_ms(),Some(crypto)).await.map(|(t,_)|t).filter(|t|t.step.is_some())} else {None};
  Refreshed{venues,thresholds}
 }}};
 let _active=Active::enter();
 let (mut t,closing)=run(t,inbox,control_rx,stop,CLOSING.subscribe(),REFRESH,fetch).await;
 if closing {
  let handed=t.hand_over().await;
  if let Some(tx)=FINALS.lock().unwrap_or_else(|e|e.into_inner()).as_ref() {let _=tx.send(handed);}
  drop(t);
  // 写库任务把交过去的写完（和平时停一样最多再试 `WRITE_DRAIN`；停机收尾最多等 `SHUTDOWN_LIMIT`，到点进程就退了）。
  let _=writer.await;
  return;
 }
 t.model.stop();
 t.write_ended().await;
 flow::submit(&base,t.flow.take());
 footprint::submit(&base,t.footprint.take());
 insights::submit(&base,t.insights.take(now_ms()));
 seconds::submit(&base,t.seconds.take());
 hub::remove(t.model.venue_ids(),&t.events);
 drop(t);
 // 等写库任务写完手里的（它自己最多再试 `WRITE_DRAIN`）：注册表按这个任务结束判断收尾完了。
 let _=writer.await;
 tracing::info!("Orderflow history: {base} stopped");
}

// ------------------------------------------------------------------ 停机

/// 进程要退出了（SIGTERM，也就是每一次部署）：跟踪任务不再把挂着的单判成失联，交出手里的就结束。
static CLOSING:std::sync::LazyLock<watch::Sender<bool>>=std::sync::LazyLock::new(||watch::channel(false).0);
/// 停机时跟踪任务交出来的挂着的单送到这里（[`shutdown`] 装上）。
static FINALS:Mutex<Option<mpsc::UnboundedSender<Final>>>=Mutex::new(None);
/// 读回挂着的单之后、到写库任务收完尾之前的跟踪任务有几个。
static ACTIVE:std::sync::atomic::AtomicUsize=std::sync::atomic::AtomicUsize::new(0);
/// 停机收尾整段最多多久（systemd 的 `TimeoutStopSec` 缺省 90 秒；和 HTTP 的优雅退出同时进行）。
pub const SHUTDOWN_LIMIT:Duration=Duration::from_secs(10);
/// 其中等跟踪任务交单最多多久：它们在主循环里，信号一到下一拍就交，正常几毫秒。
const SHUTDOWN_COLLECT:Duration=Duration::from_secs(2);

/// 一只 base 停机时交出来的：每条挂着的单的身份与最后一次看到的时刻。
struct Final {base:String,live:Vec<(LiveKey,i64)>}

struct Active;
impl Active {fn enter()->Self {ACTIVE.fetch_add(1,Ordering::SeqCst);Self}}
impl Drop for Active {fn drop(&mut self) {ACTIVE.fetch_sub(1,Ordering::SeqCst);}}

/// 停机收尾的结果（写进日志）。
#[derive(Debug,PartialEq)]
struct Closed {bases:usize,live:usize,refreshed:Option<u64>,writing:usize,elapsed_ms:u128}

/// 进程收到 SIGTERM 之后调用（`main.rs`，和 axum 的优雅退出同时开始）：
/// 1. 让所有跟踪任务停下、交出挂着的单（不判失联）；结束了还没写的、刚出现还没写的交给各自的写库任务；
/// 2. 一句 UPDATE 刷掉所有挂着的单的 `seen_ms`；
/// 3. 等写库任务写完；同时等爆仓分钟聚合把没写的分钟交出并写完（`liq::drained`）；
///
/// 整段最多 [`SHUTDOWN_LIMIT`]，到点不再等（没写进去的留给下次读回 / 清理收掉）。日志一行
/// `Orderflow history: shutdown …`。没有跟踪器（备用节点、测试）什么也不做。
pub async fn shutdown() {
 let Some(pool)=POOL.get() else {return};
 let (tx,rx)=mpsc::unbounded_channel();
 *FINALS.lock().unwrap_or_else(|e|e.into_inner())=Some(tx);
 CLOSING.send_replace(true);
 let expected=ACTIVE.load(Ordering::SeqCst);
 // 爆仓分钟聚合同时收尾：交出手上没写的分钟并等它们写进去，同一个上限。
 let liq_deadline=tokio::time::Instant::now()+SHUTDOWN_LIMIT;
 let (closed,liq_drained)=tokio::join!(close(pool,rx,expected,&ACTIVE,SHUTDOWN_COLLECT,SHUTDOWN_LIMIT),liq::drained(liq_deadline));
 if !insights::drained(liq_deadline).await {tracing::warn!("Orderflow insights: shutdown left unwritten minutes after {}s",SHUTDOWN_LIMIT.as_secs());}
 if !liq_drained {tracing::warn!("Orderflow liq: shutdown left unwritten minutes after {}s",SHUTDOWN_LIMIT.as_secs());}
 FINALS.lock().unwrap_or_else(|e|e.into_inner()).take();
 let Closed{bases,live,refreshed,writing,elapsed_ms}=closed;
 let refreshed=refreshed.map_or("failed".to_string(),|n|n.to_string());
 if writing==0 {
  tracing::info!("Orderflow history: shutdown kept {live} live orders on {bases} bases (seen_ms refreshed on {refreshed} rows), all writers drained in {elapsed_ms} ms");
 } else {
  tracing::warn!("Orderflow history: shutdown kept {live} live orders on {bases} bases (seen_ms refreshed on {refreshed} rows), {writing} trackers still writing after {elapsed_ms} ms; their rows are left to restore / purge");
 }
}

/// [`shutdown`] 的本体（测试直接调）：收交单（到齐 `expected` 份或 `collect` 到点）、一句 UPDATE、等 `active` 归零，整段不超过 `limit`。
async fn close(pool:&PgPool,mut rx:mpsc::UnboundedReceiver<Final>,expected:usize,active:&std::sync::atomic::AtomicUsize,collect:Duration,limit:Duration)->Closed {
 let started=tokio::time::Instant::now();
 let deadline=started+limit;
 let collected=started+collect.min(limit);
 let mut finals=Vec::new();
 while finals.len()<expected {
  tokio::select! {
   f=rx.recv()=>match f {Some(f)=>finals.push(f),None=>break},
   _=tokio::time::sleep_until(collected)=>break,
  }
 }
 while let Ok(f)=rx.try_recv() {finals.push(f);}
 let rows:Vec<store::SeenRow>=finals.iter().flat_map(|f|f.live.iter().map(|((venue,side,bucket,first),seen)|store::SeenRow{
  base:&f.base,venue_id:venue,side:*side,bucket:*bucket,first_seen_ms:*first,seen_ms:*seen})).collect();
 let refreshed=match tokio::time::timeout_at(deadline,store::refresh_seen(pool,&rows)).await {
  Ok(Ok(n))=>Some(n),
  Ok(Err(e))=>{tracing::warn!("Orderflow history: shutdown could not refresh seen_ms of {} live orders: {e}",rows.len());None},
  Err(_)=>{tracing::warn!("Orderflow history: shutdown gave up refreshing seen_ms of {} live orders at {limit:?}",rows.len());None},
 };
 while active.load(Ordering::SeqCst)>0&&tokio::time::Instant::now()<deadline {
  tokio::time::sleep(Duration::from_millis(20).min(deadline-tokio::time::Instant::now())).await;
 }
 Closed{bases:finals.len(),live:rows.len(),refreshed,writing:active.load(Ordering::SeqCst),elapsed_ms:started.elapsed().as_millis()}
}

// ------------------------------------------------------------------ 跟哪些币

/// 一只币为什么在跟，按强到弱。数值也是快照队列里的先后（小的先）。
#[derive(Clone,Copy,Debug,PartialEq,Eq,PartialOrd,Ord,Hash)]
enum Layer {Major=0,OnDemand=1,Favorite=2,Fixed=3,Alt=4,Hot=5}

impl Layer {
 fn label(self)->&'static str {match self {Layer::Major=>"majors",Layer::OnDemand=>"on-demand",Layer::Favorite=>"favorites",Layer::Fixed=>"fixed",Layer::Alt=>"alts",Layer::Hot=>"hot"}}
}

/// 资源闸门卸到第几层：0 不卸，1 卸 Bybit 现货（[`BYBIT_SPOT_SHED`]），2 再卸热点，3 再卸山寨，4 再卸固定与自选。主币与按需不卸。
fn shed_label(level:u8)->&'static str {
 match level {0=>"nothing",1=>"bybit-spot",2=>"bybit-spot+hot",3=>"bybit-spot+hot+alts",_=>"bybit-spot+hot+alts+fixed"}
}
/// 能卸几层：Bybit 现货、热点、山寨、固定。
const SHED_LEVELS:usize=4;

/// 闸门这一分钟该做什么。
#[derive(Clone,Copy,Debug,PartialEq)]
enum Step {Hold,Shed,Floor,Restore(u32)}

/// 资源闸门的状态：超了卸一层；离线够远（[`resources::Load::calm`]）连续若干分钟放回一层。
///
/// 放回的等待按层记、会翻倍（和 BGP 的路由抖动抑制、Kubernetes HPA 的缩容稳定窗一个思路）：一层放回来半小时内
/// 又把进程顶超，说明这台机器现在装不下它，下次等两倍（10 → 20 → 40 → 80 → 120 分钟封顶）；放回来撑过一小时，
/// 等待回到十分钟。原来只看「这一分钟没超」、固定等十分钟：卸了热点刚好在线下、放回来又超的时候每 13 分钟翻一次，
/// 6 小时 27 次，每次热点 30 只全部停了重起（拉品种表、收盘、订阅、排快照额度、挂着的单记失联再读回）。
#[derive(Debug)]
struct Gate {clear:u32,wait:[u32;SHED_LEVELS],restored_at:[Option<i64>;SHED_LEVELS]}

impl Default for Gate {fn default()->Self {Self{clear:0,wait:[SHED_RECOVER_MINUTES;SHED_LEVELS],restored_at:[None;SHED_LEVELS]}}}

impl Gate {
 fn step(&mut self,load:&resources::Load,shed:u8,now:i64)->Step {
  for (wait,at) in self.wait.iter_mut().zip(self.restored_at.iter_mut()) {
   if at.is_some_and(|t|now-t>=SHED_HOLD_MS) {*wait=SHED_RECOVER_MINUTES;*at=None;}
  }
  if load.over() {
   self.clear=0;
   if shed as usize>=SHED_LEVELS {return Step::Floor}
   let layer=shed as usize;
   if self.restored_at[layer].take().is_some_and(|t|now-t<SHED_FLAP_MS) {
    self.wait[layer]=(self.wait[layer]*2).min(SHED_RECOVER_CAP_MINUTES);
   }
   return Step::Shed;
  }
  if shed==0 {return Step::Hold}
  if !load.calm() {self.clear=0;return Step::Hold}
  self.clear+=1;
  let layer=shed as usize-1;
  let need=self.wait[layer];
  if self.clear<need {return Step::Hold}
  self.clear=0;
  self.restored_at[layer]=Some(now);
  Step::Restore(need)
 }
}

/// 在榜上（没有截止时刻）。
const LISTED:i64=i64::MAX;

struct Entry {
 major:bool,
 fixed:bool,
 /// 近 7 天登录过的人自选了它（[`favorites`]）。
 favorite:bool,
 /// 山寨 / 热点：在榜上为 `LISTED`，掉榜之后为掉榜时刻 + 24 小时，不在这一层为 0。
 alt_until:i64,
 hot_until:i64,
 /// 最后一次在热点榜上的时刻。
 hot_seen:i64,
 /// 最后一次有人要的时刻（没人要过为 0）。
 requested:i64,
 priority:Arc<AtomicU8>,
 stop:watch::Sender<bool>,
 thresholds:watch::Receiver<Thresholds>,
 task:JoinHandle<()>,
}

impl Entry {
 fn on_demand(&self,now:i64)->bool {self.requested>0&&now-self.requested<IDLE_MS}
 /// 此刻最强的理由（按卸层之后算）；None 就是不该再跟了。
 fn layer(&self,now:i64,shed:u8)->Option<Layer> {
  if self.major {Some(Layer::Major)}
  else if self.on_demand(now) {Some(Layer::OnDemand)}
  else if self.favorite&&shed<4 {Some(Layer::Favorite)}
  else if self.fixed&&shed<4 {Some(Layer::Fixed)}
  else if self.alt_until>now&&shed<3 {Some(Layer::Alt)}
  else if self.hot_until>now&&shed<2 {Some(Layer::Hot)}
  else {None}
 }
 /// 满了可以踢的：只因为按需或热点在跟的。
 fn evictable(&self,now:i64)->bool {!self.major&&!self.fixed&&!self.favorite&&self.alt_until<=now}
 fn wanted_at(&self)->i64 {self.requested.max(self.hot_seen)}
 fn only_on_demand(&self,now:i64)->bool {self.on_demand(now)&&!self.major&&!self.fixed&&!self.favorite&&self.alt_until<=now&&self.hot_until<=now}
 fn only_hot(&self,now:i64)->bool {self.hot_until>now&&!self.major&&!self.fixed&&!self.favorite&&self.alt_until<=now&&!self.on_demand(now)}
}

/// 各层最近一次算出来的名单（卸层恢复时重新套用）。
#[derive(Default)]
struct Lists {fixed:Vec<String>,alts:Vec<String>,hot:Vec<String>,favorites:Vec<String>}

struct Registry {
 pool:PgPool,
 entries:Mutex<HashMap<String,Entry>>,
 lists:Mutex<Lists>,
 /// 资源闸门此刻超没超（超了不再新增）。
 over:AtomicBool,
 shed:AtomicU8,
 /// 成批起跟踪时下一只排到什么时候。
 next_start:Mutex<tokio::time::Instant>,
 /// 停掉了、还在收尾（结束挂着的单、把积压写进库）的跟踪任务。同一只马上又被起跟时，新的等旧的收完尾再读回挂着的单。
 retiring:Mutex<HashMap<String,JoinHandle<()>>>,
 /// 自选层的两份来源：账号自选（10 分钟重算）与设备最近打开 / 带过的（随请求更新），合起来套 `Layer::Favorite`。
 accounts:Mutex<Vec<String>>,
 devices:Mutex<favorites::Devices>,
 device_pick:Mutex<Vec<String>>,
}

static REGISTRY:OnceLock<Arc<Registry>>=OnceLock::new();

type Entries=HashMap<String,Entry>;

impl Registry {
 fn new(pool:PgPool)->Self {
  Self{pool,entries:Mutex::new(HashMap::new()),lists:Mutex::new(Lists::default()),over:AtomicBool::new(false),shed:AtomicU8::new(0),
   next_start:Mutex::new(tokio::time::Instant::now()),retiring:Mutex::new(HashMap::new()),
   accounts:Mutex::new(Vec::new()),devices:Mutex::new(favorites::Devices::default()),device_pick:Mutex::new(Vec::new())}
 }
 fn lock(&self)->std::sync::MutexGuard<'_,Entries> {self.entries.lock().unwrap_or_else(|e|e.into_inner())}
 fn shed(&self)->u8 {self.shed.load(Ordering::Relaxed)}
 fn over(&self)->bool {self.over.load(Ordering::Relaxed)}

 fn delay(&self,immediate:bool)->Duration {
  if immediate {return Duration::ZERO}
  let mut next=self.next_start.lock().unwrap_or_else(|e|e.into_inner());
  let now=tokio::time::Instant::now();
  let at=(*next).max(now)+START_GAP;
  *next=at;
  at-now
 }

 fn start(&self,entries:&mut Entries,base:&str,now:i64,immediate:bool,tag:impl FnOnce(&mut Entry)) {
  let (stop,rx)=watch::channel(false);
  let (shared,thresholds)=watch::channel(Thresholds::default());
  let priority=Arc::new(AtomicU8::new(Layer::Hot as u8));
  let after=self.retiring.lock().unwrap_or_else(|e|e.into_inner()).remove(base);
  let task=tokio::spawn(track(self.pool.clone(),base.to_string(),shared,rx,priority.clone(),self.delay(immediate),after));
  let mut e=Entry{major:false,fixed:false,favorite:false,alt_until:0,hot_until:0,hot_seen:0,requested:0,priority,stop,thresholds,task};
  tag(&mut e);
  if let Some(layer)=e.layer(now,self.shed()) {e.priority.store(layer as u8,Ordering::Relaxed);}
  entries.insert(base.to_string(),e);
 }

 /// 停掉一只：发停止信号，任务交给 `retiring` 收尾。原来停了就不管：同一只紧接着又被要（踢出按需后马上有人看、
 /// 掉出热点又进按需），新任务读回的「挂着的单」里有旧任务正要写成失联结束的——旧的结束一落库，
 /// 新任务手里那几条再写都被 `WHERE end_ms IS NULL` 挡掉，墙还在、历史里却断在停的那一刻。
 fn stop(&self,entries:&mut Entries,base:&str,why:&str) {
  let Some(e)=entries.remove(base) else {return};
  let _=e.stop.send(true);
  tracing::info!("Orderflow history: {base} {why}");
  let mut retiring=self.retiring.lock().unwrap_or_else(|e|e.into_inner());
  retiring.retain(|_,task|!task.is_finished());
  retiring.insert(base.to_string(),e.task);
 }

 /// 满了就踢按需 / 热点里最久没人要的那只（主币、固定、山寨不踢）。踢不动返回 false。
 fn make_room(&self,entries:&mut Entries,now:i64)->bool {
  if entries.len()<MAX_BASES {return true}
  let victim=entries.iter().filter(|(_,e)|e.evictable(now)).min_by_key(|(b,e)|(e.wanted_at(),(*b).clone())).map(|(b,_)|b.clone());
  let Some(victim)=victim else {return false};
  self.stop(entries,&victim,"evicted for room");
  true
 }

 /// 有人要这只：记下时刻，没在跟就开始跟（按需层）。回此刻的门槛（还没算出来是全空）。
 fn request(&self,base:&str,now:i64)->Thresholds {
  let mut entries=self.lock();
  let shed=self.shed();
  if let Some(e)=entries.get_mut(base) {
   e.requested=now;
   if let Some(layer)=e.layer(now,shed) {e.priority.store(layer as u8,Ordering::Relaxed);}
   return *e.thresholds.borrow()
  }
  if self.over() {tracing::info!("Orderflow history: {base} requested but the resource gate is over, not tracking");return Thresholds::default()}
  let demand:Vec<(i64,String)>=entries.iter().filter(|(_,e)|e.only_on_demand(now)).map(|(b,e)|(e.requested,b.clone())).collect();
  if demand.len()>=MAX_ON_DEMAND && let Some((_,victim))=demand.into_iter().min() {self.stop(&mut entries,&victim,"evicted from on-demand for a newer request");}
  if self.make_room(&mut entries,now) {self.start(&mut entries,base,now,true,|e|e.requested=now);}
  Thresholds::default()
 }

 fn tracked(&self)->Vec<String> {self.lock().keys().cloned().collect()}
 /// 热点层此刻的名单（首页异动并进自选用）。
 fn hot_list(&self)->Vec<String> {self.lists.lock().unwrap_or_else(|e|e.into_inner()).hot.clone()}
 /// 这只此刻的步长（没在跟或还没算出来为 None）；不像 `request` 那样记「有人要」。
 fn step(&self,base:&str)->Option<f64> {self.lock().get(base).and_then(|e|e.thresholds.borrow().step)}
 fn is_tracked(&self,base:&str)->bool {self.lock().contains_key(base)}
 /// 此刻这只的门槛（没在跟为 None）。
 fn thresholds(&self,base:&str)->Option<Thresholds> {self.lock().get(base).map(|e|*e.thresholds.borrow())}

 /// 不该再跟的停掉、先后重排、热点层（含掉榜还在跟的）超过 30 只就停掉最早掉榜的。
 fn settle(&self,entries:&mut Entries,now:i64) {
  let shed=self.shed();
  let gone:Vec<String>=entries.iter().filter(|(_,e)|e.layer(now,shed).is_none()).map(|(b,_)|b.clone()).collect();
  for base in gone {self.stop(entries,&base,"no longer wanted, stopped");}
  let mut tails:Vec<(i64,String)>=entries.iter().filter(|(_,e)|e.only_hot(now)&&e.hot_until!=LISTED).map(|(b,e)|(e.hot_seen,b.clone())).collect();
  let hot=entries.values().filter(|e|e.only_hot(now)).count();
  if hot>layers::MAX_HOT {
   tails.sort();
   for (_,base) in tails.into_iter().take(hot-layers::MAX_HOT) {self.stop(entries,&base,"dropped off the hot list, cap reached");}
  }
  for e in entries.values() {if let Some(layer)=e.layer(now,shed) {e.priority.store(layer as u8,Ordering::Relaxed);}}
 }

 /// 套一层的名单：在榜的打上标记（没在跟就起），不在榜的去掉标记（山寨 / 热点改成再跟 24 小时）。
 fn apply(&self,layer:Layer,list:&[String],now:i64) {
  {
   let mut lists=self.lists.lock().unwrap_or_else(|e|e.into_inner());
   match layer {Layer::Fixed=>lists.fixed=list.to_vec(),Layer::Alt=>lists.alts=list.to_vec(),Layer::Hot=>lists.hot=list.to_vec(),Layer::Favorite=>lists.favorites=list.to_vec(),_=>{}}
  }
  let set:HashSet<&str>=list.iter().map(String::as_str).collect();
  let mut entries=self.lock();
  for (base,e) in entries.iter_mut() {
   let on=set.contains(base.as_str());
   match layer {
    Layer::Fixed=>e.fixed=on,
    Layer::Favorite=>e.favorite=on,
    Layer::Alt=>{if on {e.alt_until=LISTED} else if e.alt_until==LISTED {e.alt_until=now+LINGER_MS}},
    Layer::Hot=>{if on {e.hot_until=LISTED;e.hot_seen=now} else if e.hot_until==LISTED {e.hot_until=now+LINGER_MS}},
    _=>{},
   }
  }
  let shed=self.shed();
  let shed_here=match layer {Layer::Fixed|Layer::Favorite=>shed>=3,Layer::Alt=>shed>=2,Layer::Hot=>shed>=1,_=>false};
  let (mut started,mut refused)=(0,0);
  for base in list {
   if entries.contains_key(base) {continue}
   if shed_here||self.over()||!self.make_room(&mut entries,now) {refused+=1;continue}
   self.start(&mut entries,base,now,false,|e|match layer {
    Layer::Fixed=>e.fixed=true,
    Layer::Favorite=>e.favorite=true,
    Layer::Alt=>e.alt_until=LISTED,
    Layer::Hot=>{e.hot_until=LISTED;e.hot_seen=now},
    _=>{},
   });
   started+=1;
  }
  self.settle(&mut entries,now);
  tracing::info!("Orderflow history: {} layer {} bases ({started} started{}): {}",layer.label(),list.len(),
   if refused>0 {format!(", {refused} held back by the resource gate / cap")} else {String::new()},list.join(" "));
 }

 /// 一台设备打开 / 带了这几只（已筛过合法、挂牌）：设备那一份换了成员就马上重套自选层。
 fn touch_device(&self,device:&str,bases:&[String],now:i64) {
  let changed={
   let mut d=self.devices.lock().unwrap_or_else(|e|e.into_inner());
   d.touch(device,bases,now)&&{
    let pick=d.pick();
    let mut last=self.device_pick.lock().unwrap_or_else(|e|e.into_inner());
    if *last==pick {false} else {*last=pick;true}
   }
  };
  if changed {self.apply_favorites(now);}
 }

 /// 账号自选 + 设备那一份，套成自选层。
 fn apply_favorites(&self,now:i64) {
  let list=favorites::combine(&self.accounts.lock().unwrap_or_else(|e|e.into_inner()),&self.device_pick.lock().unwrap_or_else(|e|e.into_inner()));
  self.apply(Layer::Favorite,&list,now);
 }

 /// 热点要排除的：已经因为别的理由在跟的，加上固定与山寨名单。
 fn not_hot(&self,now:i64)->HashSet<String> {
  let mut out:HashSet<String>=self.lock().iter().filter(|(_,e)|e.major||e.fixed||e.favorite||e.alt_until>now||e.on_demand(now)).map(|(b,_)|b.clone()).collect();
  let lists=self.lists.lock().unwrap_or_else(|e|e.into_inner());
  out.extend(lists.fixed.iter().cloned());
  out.extend(lists.alts.iter().cloned());
  out.extend(lists.favorites.iter().cloned());
  out.extend(layers::MAJORS.iter().map(|m|m.to_string()));
  out
 }

 /// 每十分钟：不该再跟的停掉；意外结束的任务重起（标记不变）。
 fn sweep(&self,now:i64) {
  let mut entries=self.lock();
  self.settle(&mut entries,now);
  let dead:Vec<String>=entries.iter().filter(|(_,e)|e.task.is_finished()).map(|(b,_)|b.clone()).collect();
  for base in dead {
   let Some(old)=entries.remove(&base) else {continue};
   tracing::warn!("Orderflow history: {base} tracker ended unexpectedly, restarting");
   self.start(&mut entries,&base,now,false,|e|{e.major=old.major;e.fixed=old.fixed;e.favorite=old.favorite;e.alt_until=old.alt_until;e.hot_until=old.hot_until;e.hot_seen=old.hot_seen;e.requested=old.requested;});
  }
 }

 /// 资源闸门（每分钟）：超了就不再新增，并卸一层；放回一层的时机由 [`Gate`] 定，放回时重新套名单。
 fn gate(&self,now:i64,gate:&mut Gate) {
  let load=resources::last();
  let over=load.over();
  self.over.store(over,Ordering::Relaxed);
  let shed=self.shed();
  match gate.step(&load,shed,now) {
   Step::Shed=>{
    self.shed.store(shed+1,Ordering::Relaxed);
    BYBIT_SPOT_SHED.send_if_modified(|v|!std::mem::replace(v,true));
    tracing::warn!("Orderflow history: resource gate over ({}), shedding {}",load.describe(),shed_label(shed+1));
    let mut entries=self.lock();
    self.settle(&mut entries,now);
    drop(entries);
    // 卸下的跟踪任务要一会儿才收完尾、放掉簿；下一分钟的闸门看的是还回去之后的 RSS。
    tokio::spawn(async {tokio::time::sleep(Duration::from_secs(20)).await;resources::release_free_memory();});
   },
   Step::Floor=>tracing::warn!("Orderflow history: resource gate still over ({}) with only majors and on-demand left",load.describe()),
   Step::Restore(waited)=>{
    self.shed.store(shed-1,Ordering::Relaxed);
    if shed-1==0 {BYBIT_SPOT_SHED.send_if_modified(|v|std::mem::replace(v,false));}
    tracing::info!("Orderflow history: resource gate clear for {waited} minutes ({}), now shedding {}",load.describe(),shed_label(shed-1));
    let lists=std::mem::take(&mut *self.lists.lock().unwrap_or_else(|e|e.into_inner()));
    self.apply(Layer::Fixed,&lists.fixed,now);
    self.apply(Layer::Favorite,&lists.favorites,now);
    self.apply(Layer::Alt,&lists.alts,now);
    self.apply(Layer::Hot,&lists.hot,now);
   },
   Step::Hold=>{},
  }
 }

 /// 一行现状：各层多少只、连接数、进程负载、卸层。
 fn status(&self,now:i64)->String {
  let shed=self.shed();
  let entries=self.lock();
  let mut counts:HashMap<Layer,usize>=HashMap::new();
  for e in entries.values() {if let Some(l)=e.layer(now,shed) {*counts.entry(l).or_default()+=1;}}
  let parts:Vec<String>=[Layer::Major,Layer::OnDemand,Layer::Favorite,Layer::Fixed,Layer::Alt,Layer::Hot].iter().map(|l|format!("{} {}",l.label(),counts.get(l).copied().unwrap_or(0))).collect();
  format!("tracking {} ({}), {} connections, {}, shedding {}",entries.len(),parts.join(", "),hub::connections(),resources::last().describe(),shed_label(shed))
 }
}

/// 自选层：读近 7 天登录过的人的自选（每人 30、合起来 60），单独起任务，不挡着闸门。读不到就保持上一份名单。
async fn recompute_favorites(registry:Arc<Registry>,running:crate::supervise::Running) {
 let _running=running;
 match favorites::bases(&registry.pool).await {
  Ok(list)=>{*registry.accounts.lock().unwrap_or_else(|e|e.into_inner())=list;registry.apply_favorites(now_ms());},
  Err(e)=>tracing::warn!("Orderflow history: favorites layer unreadable, keeping the last list: {e:#}"),
 }
}

/// 热点那一路要取 150 次持仓历史（约 45 秒），单独起任务，不挡着资源采样与闸门。
async fn recompute_hot(registry:Arc<Registry>,running:crate::supervise::Running) {
 // 守卫握到函数结束：以前是末尾一句 `store(false)`，中途 panic 就跳过了，热点层从此再也不重算。
 let _running=running;
 // 合约表或行情没取到（多半是重启那一下撞上币安 429 闸门）就隔一分钟再试几次，不然这一小时热点层是空的、首页异动只剩自选。
 let mut tries=0;
 let result=loop {
  tries+=1;
  let got=hot_once(&registry).await;
  if got.is_some()||tries>=HOT_TRIES {break got}
  tokio::time::sleep(std::time::Duration::from_secs(60)).await;
 };
 match result {
  Some((hot,got,asked))=>{
   tracing::info!("Orderflow history: hot signals ready (open interest for {got}/{asked} contracts)");
   registry.apply(Layer::Hot,&hot,now_ms());
  },
  None=>tracing::warn!("Orderflow history: hot layer not recomputed after {tries} tries (contract list or tickers unavailable), keeping the last one"),
 }
}

const HOT_TRIES:u32=5;

async fn hot_once(registry:&Registry)->Option<(Vec<String>,usize,usize)> {
 async {
  let info=crate::market_meta::exchange_info().await.ok()?;
  let tickers=layers::ticker_map(&*layers::tickers().await.ok()?);
  let exclude=registry.not_hot(now_ms());
  let candidates=layers::oi_candidates(&info,&tickers,&exclude);
  let oi=layers::oi_changes(&candidates).await;
  let exclude=registry.not_hot(now_ms());
  Some((layers::pick_hot(&info,&tickers,&oi,&exclude),oi.len(),candidates.len()))
 }.await
}

/// 层的循环：每 15 秒采一次资源；每分钟过一遍闸门，到点重算固定（10 分钟对一次合约表）、山寨（UTC 0 点）、
/// 热点（每小时）。
async fn run_layers(registry:Arc<Registry>,enabled:Enabled) {
 let mut sample=tokio::time::interval(SAMPLE);
 sample.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
 let mut tick=tokio::time::interval(LAYER_TICK);
 tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
 // 0 而不是 i64::MIN：`now - i64::MIN` 会溢出（Release 下绕成负数，层永远不起）。
 let (mut fixed_at,mut hot_at,mut alts_day)=(0i64,0i64,None::<i64>);
 let mut gate=Gate::default();
 let mut missing_named:Option<Vec<String>>=None;
 let hot_running=Arc::new(AtomicBool::new(false));
 let favorites_running=Arc::new(AtomicBool::new(false));
 let mut favorites_at=0i64;
 let started=now_ms();
 let mut status_at=0i64;
 loop {
  tokio::select! {
   _=sample.tick()=>{resources::sample();},
   _=tick.tick()=>{
    let now=now_ms();
    registry.gate(now,&mut gate);
    let info=if enabled.fixed||enabled.alts||enabled.hot {
     match crate::market_meta::exchange_info().await {
      Ok(info)=>Some(info),
      Err(_)=>{tracing::warn!("Orderflow history: contract list unavailable, layers retried next minute");None},
     }
    } else {None};
    if let Some(info)=info {
     if enabled.fixed&&now-fixed_at>=FIXED_EVERY_MS {
      let (found,missing)=layers::fixed_bases(&info);
      if missing_named.as_ref()!=Some(&missing) {
       tracing::info!("Orderflow history: fixed layer {} of {} names listed on Binance; not listed, skipped: {}",found.len(),found.len()+missing.len(),
        if missing.is_empty() {"none".to_string()} else {missing.join(" ")});
       missing_named=Some(missing);
      }
      registry.apply(Layer::Fixed,&found,now);
      fixed_at=now;
     }
     let day=now.div_euclid(store::DAY_MS);
     if enabled.alts&&alts_day!=Some(day) {
      match layers::tickers().await {
       Ok(body)=>{
        let tickers=layers::ticker_map(&body);
        let fixed:HashSet<String>=layers::fixed_bases(&info).0.into_iter().collect();
        let alts=layers::pick_alts(&info,&tickers,&fixed);
        registry.apply(Layer::Alt,&alts,now);
        alts_day=Some(day);
       },
       Err(_)=>tracing::warn!("Orderflow history: tickers unavailable, alts layer retried next minute"),
      }
     }
     if enabled.hot&&now-hot_at>=HOT_EVERY_MS && let Some(claim)=crate::supervise::Running::claim(&hot_running) {
      hot_at=now;
      crate::supervise::spawn_logged("orderflow-hot",crate::supervise::Life::Once,recompute_hot(registry.clone(),claim));
     }
    }
    // 自选层不看合约表、不看 `KANPAN_ORDERFLOW_LAYERS`：登录用户的自选一直补跟。
    if now-favorites_at>=favorites::EVERY_MS && let Some(claim)=crate::supervise::Running::claim(&favorites_running) {
     favorites_at=now;
     crate::supervise::spawn_logged("orderflow-favorites",crate::supervise::Life::Once,recompute_favorites(registry.clone(),claim));
    }
    // 起来的头十分钟每分钟一行现状，之后十分钟一行。
    let every=if now-started<10*60_000 {60_000} else {10*60_000};
    if now-status_at>=every-1_000 {status_at=now;tracing::info!("Orderflow history: {}",registry.status(now));}
   },
  }
 }
}

/// 进程起来时接着跟的按需币，带着库里记的最后一次要的时刻（不是现在）：原来一律记成现在，每重启一次就把
/// 闲置的 24 小时从头算，23 小时前看过一眼的币又被多跟一整天，发版勤的时候一直跟下去、占着按需层名额。
fn resumable<'a>(recent:&'a [(String,i64)],admit:&HashSet<&str>,now:i64)->Vec<(&'a str,i64)> {
 recent.iter().filter(|(b,r)|admit.contains(b.as_str())&&now-r<IDLE_MS).take(MAX_ON_DEMAND).map(|(b,r)|(b.as_str(),*r)).collect()
}

/// 起跟踪：主币、最近 24 小时有人要过的（最多 20 只），再按 `KANPAN_ORDERFLOW_LAYERS` 起固定 / 山寨 / 热点；
/// 之后每十分钟清一遍、每小时滚动清理。
/// 订单流自己的库连接池最多几条：写库 3（`WRITE_SLOTS`，深度热力的写也在里面）+ 读历史 2（`HISTORY_READS`，读热力共用）+ 起跟 / 读回 / 记要过 / 清理 1。
const OWN_POOL:u32=6;
static POOL:OnceLock<PgPool>=OnceLock::new();

/// 订单流单开一个池子，和账号、同步、提醒等用户接口的池子（serve 共 8 条）分开：连同一个库、同一套语句死线。
/// 原来共用那 8 条，写库、读历史各有名额，但起跟读回、记要过、每小时清理都不占名额，库一慢（表锁、慢盘、清理删大批）
/// 订单流就能把 8 条全攥住，登录、同步推拉拿连接要一直等到它们放手。
fn own_pool(api:&PgPool)->PgPool {
 crate::pool_options(true).max_connections(OWN_POOL).connect_lazy_with((*api.connect_options()).clone())
}

pub fn spawn(pool:PgPool)->JoinHandle<()> {
 let pool=POOL.get_or_init(||own_pool(&pool)).clone();
 heat::start(pool.clone());
 flow::start(pool.clone());
 liq::start(pool.clone());
 footprint::start(pool.clone());
 insights::start(pool.clone());
 seconds::start(pool.clone());
 highlights::start(pool.clone());
 tokio::spawn(async move {
  let registry=REGISTRY.get_or_init(||Arc::new(Registry::new(pool.clone()))).clone();
  let enabled=Enabled::from_env();
  tracing::info!("Orderflow history: layers {} (up to {MAX_BASES} bases)",enabled.describe());
  let now=now_ms();
  let recent=store::recent_bases(&pool,now).await.unwrap_or_else(|e|{tracing::warn!("Orderflow history: recent bases unreadable: {e}");Vec::new()});
  {
   let mut entries=registry.lock();
   for base in ALWAYS {registry.start(&mut entries,base,now,false,|e|e.major=true);}
  }
  // 已经不挂了的（或者修复之前打错的代号被记进来的）不再接着跟。
  let mut admit=HashSet::new();
  for (base,_) in recent.iter().filter(|(b,_)|!ALWAYS.contains(&b.as_str())&&instruments::valid_base(b)) {
   if admitted(false,instruments::listed(base).await) {admit.insert(base.as_str());}
  }
  {
   let mut entries=registry.lock();
   for (base,requested) in resumable(&recent,&admit,now) {
    registry.start(&mut entries,base,now,false,|e|e.requested=requested);
   }
  }
  // 层的循环没有自己的状态要保（时刻都从 0 重算，第一次 tick 就把各层重新对一遍），死了原地再起。
  {let registry=registry.clone();crate::supervise::spawn_restarting("orderflow-layers",move ||run_layers(registry.clone(),enabled));}
  let mut sweep=tokio::time::interval_at(tokio::time::Instant::now()+SWEEP,SWEEP);
  // 进程起来一分钟后先清一次，之后每小时一次。
  let mut purge=tokio::time::interval_at(tokio::time::Instant::now()+Duration::from_secs(60),PURGE);
  // 热力表另起一个每分钟一次的清理（见 `heat::purge`）：预建分区、整张 DROP 过期与超预算的分区、删过期的段。删到哪记在库里，重启接着用。
  let mut heat_purge=tokio::time::interval_at(tokio::time::Instant::now()+Duration::from_secs(90),heat::PURGE_EVERY);
  heat_purge.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
  let mut heat_floors:Option<(Option<i64>,Option<i64>)>=None;
  let (mut heat_dropped,mut heat_rollup_deleted)=(0usize,0u64);
  loop {
   tokio::select! {
    _=sweep.tick()=>registry.sweep(now_ms()),
    _=heat_purge.tick()=>{
     let (raw,rollup)=match heat_floors {
      Some(floors)=>floors,
      None=>match heat::purged(&pool).await {Ok(floors)=>floors,Err(e)=>{tracing::warn!("Orderflow heat: purge progress unreadable: {e}");continue}},
     };
     match heat::purge(&pool,now_ms(),raw,rollup).await {
      Ok(done)=>{
       if !done.created.is_empty() {tracing::info!("Orderflow heat: created partitions {:?}",done.created);}
       if !done.dropped.is_empty() {tracing::info!("Orderflow heat: dropped partitions {:?}",done.dropped);}
       heat_dropped+=done.dropped.len();
       heat_rollup_deleted+=done.rollup_rows;
       heat_floors=Some((Some(done.raw_floor),Some(done.rollup_floor)));
      },
      Err(e)=>tracing::warn!("Orderflow heat: purge failed: {e}"),
     }
    },
    _=purge.tick()=>{
     let tracked=registry.tracked();
     match store::purge(&pool,now_ms(),&tracked).await {
      Ok((deleted,closed))=>tracing::info!("Orderflow history: purge deleted {deleted}, closed {closed}; table {} bytes",store::size(&pool).await.unwrap_or(-1)),
      Err(e)=>tracing::warn!("Orderflow history: purge failed: {e}"),
     }
     // 热力每分钟清理，日志仍每小时报一次这一小时一共删了多少。
     match heat::partitions(&pool).await {
      Ok(parts)=>tracing::info!("Orderflow heat: purge dropped {} partitions, rollup rows deleted {}; raw {} partitions {} bytes",
       std::mem::take(&mut heat_dropped),std::mem::take(&mut heat_rollup_deleted),parts.len(),parts.iter().map(|p|p.bytes).sum::<i64>()),
      Err(e)=>tracing::warn!("Orderflow heat: partitions unreadable: {e}"),
     }
     match flow::purge(&pool,now_ms()).await {
      Ok(deleted)=>tracing::info!("Orderflow flow: purge deleted {deleted}; table {} bytes",flow::size(&pool).await.unwrap_or(-1)),
      Err(e)=>tracing::warn!("Orderflow flow: purge failed: {e}"),
     }
     match liq::purge(&pool,now_ms()).await {
      Ok(deleted)=>tracing::info!("Orderflow liq: purge deleted {deleted}; table {} bytes",liq::size(&pool).await.unwrap_or(-1)),
      Err(e)=>tracing::warn!("Orderflow liq: purge failed: {e}"),
     }
     match footprint::purge(&pool,now_ms()).await {
      Ok(deleted)=>tracing::info!("Orderflow footprint: purge deleted {deleted}"),
      Err(e)=>tracing::warn!("Orderflow footprint: purge failed: {e}"),
     }
     match insights::purge(&pool,now_ms()).await {
      Ok(deleted)=>tracing::info!("Orderflow insights: purge deleted {deleted}"),
      Err(e)=>tracing::warn!("Orderflow insights: purge failed: {e}"),
     }
     match seconds::purge(&pool,now_ms()).await {
      Ok(deleted)=>tracing::info!("Orderflow seconds: purge deleted {deleted}"),
      Err(e)=>tracing::warn!("Orderflow seconds: purge failed: {e}"),
     }
     crate::storage_budget::report(&pool).await;
    },
   }
  }
 })
}

// ------------------------------------------------------------------ 路由

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct HistoryQuery {base:String,from:Option<i64>,to:Option<i64>,#[serde(rename="minLifeMs")] min_life_ms:Option<i64>,limit:Option<i64>}

/// 校验 `limit`：1..=`MAX_PAGE`，其余回 `invalid_query`；不给是老请求，上限照旧 `store::MAX_ROWS`。
fn page_limit(v:Option<i64>)->std::result::Result<i64,&'static str> {
 match v {None=>Ok(store::MAX_ROWS),Some(v @ 1..=MAX_PAGE)=>Ok(v),Some(_)=>Err("invalid_query")}
}

/// `minLifeMs` 最大一天：再长就没什么单剩下了，也免得任意 i64 进 SQL。
const MAX_MIN_LIFE_MS:i64=store::DAY_MS;

/// 校验 `minLifeMs`：缺省 0（不过滤），0..=一天，其余回 `invalid_query`（和解析不了的查询串同一个码）。
fn min_life(v:Option<i64>)->std::result::Result<i64,&'static str> {
 match v.unwrap_or(0) {v @ 0..=MAX_MIN_LIFE_MS=>Ok(v),_=>Err("invalid_query")}
}

/// 条件提醒（大单墙）要这只 base 在跟：和手机打开这只品种走同一条路（按需层、记进 `orderflow_bases`）。
/// 返回它此刻是否在跟（或刚起跟）；三家都没挂的不起。
pub(crate) async fn want(base:&str,now:i64)->bool {
 if !instruments::valid_base(base) {return false}
 let Some(registry)=REGISTRY.get() else {return false};
 if !admitted(registry.is_tracked(base),instruments::listed(base).await) {return false}
 registry.request(base,now);
 if let Some(pool)=POOL.get() && let Err(e)=store::touch(pool,base,now).await {tracing::warn!("Orderflow history: {base} could not be recorded as wanted: {e}")}
 registry.is_tracked(base)
}

/// 一台设备打开 / 带了这几只 base（首页异动一列的 `bases=`、要点请求）：合法、挂牌的记进自选层的设备那一份。
pub(crate) async fn touch_device(device:&str,bases:&[String],now:i64) {
 let Some(registry)=REGISTRY.get() else {return};
 let mut ok=Vec::with_capacity(bases.len());
 for b in bases {if instruments::valid_base(b)&&admitted(registry.is_tracked(b),instruments::listed(b).await) {ok.push(b.clone());}}
 registry.touch_device(device,&ok,now);
}

/// 要不要为这只 base 起跟踪、记进库：已经在跟的照旧；合约表判得了而三家都没挂的不起；判不了（表还没拉到）的放行。
fn admitted(tracked:bool,listed:Option<bool>)->bool {tracked||listed!=Some(false)}

/// 校验并补齐区间：`to` 缺省此刻，`from` 缺省 `to` 前 `span`（老请求 24 小时，带 `limit` 的 6 小时），最长 3 天。
fn window(from:Option<i64>,to:Option<i64>,now:i64,span:i64)->std::result::Result<(i64,i64),&'static str> {
 let to=to.unwrap_or(now);
 // to 是请求带来的任意 i64：i64::MIN 附近直接减会溢出（调试构建里是 panic，发布构建靠回绕碰巧判成 invalid_range）。
 let from=from.unwrap_or(to.saturating_sub(span));
 if from<0||to<0||from>to {return Err("invalid_range")}
 if to-from>MAX_SPAN_MS {return Err("range_too_long")}
 Ok((from,to))
}

async fn history(State(s):State<AppState>,headers:axum::http::HeaderMap,Params(q):Params<HistoryQuery>)->Result<Response> {
 if !instruments::valid_base(&q.base) {return Err(ApiError::bad("invalid_base"))}
 let now=now_ms();
 let (from,to)=window(q.from,q.to,now,if q.limit.is_some() {PAGED_SPAN_MS} else {DEFAULT_SPAN_MS}).map_err(ApiError::bad)?;
 let min_life=min_life(q.min_life_ms).map_err(ApiError::bad)?;
 let limit=page_limit(q.limit).map_err(ApiError::bad)?;
 // 三家都没挂的 base（打错的、早下架的）：不起跟踪、不记进 orderflow_bases。原来照样起一只按需跟踪，
 // 占着按需层的名额（满了还会把真有人在看的踢掉），prepare 每 30 秒空转一次、一跟 24 小时，重启后还会被接着跟。
 let pool=POOL.get().unwrap_or(&s.pool);
 let tracked=REGISTRY.get().is_some_and(|r|r.is_tracked(&q.base));
 let admit=admitted(tracked,instruments::listed(&q.base).await);
 let (thresholds,tracked_since)=if admit {
  let thresholds=REGISTRY.get().map(|r|r.request(&q.base,now)).unwrap_or_default();
  let (since,alive)=store::touch(pool,&q.base,now).await?;
  (thresholds,store::continuous_since(since,alive,now).max(now-MAX_SPAN_MS))
 } else {(Thresholds::default(),now)};
 // 同一窗口（按分钟取整）的请求合并成一次读库，答好的压缩体留 60 秒；读的区间放宽到整分钟（左边往前取整、
 // 右边补到这一分钟末），合并进来的每个请求拿到的都是它要的区间的超集——客户端按单号合并，多几条不要紧。
 let key=Key::new(&q.base,from,to,min_life,accepts_gzip(&headers)).limit(limit);
 let (from,to)=key.window();
 let gzip=key.gzip;
 let answer=ANSWERS.get_or_build(key,||reply(pool,&q.base,from,to,min_life,limit,thresholds,tracked_since,gzip)).await?;
 Ok(answer.response())
}

/// 客户端收不收 gzip：`Accept-Encoding` 里有 `gzip`（或 `*`）且 q 不为 0。手机的 URLSession 总是带着。
fn accepts_gzip(headers:&axum::http::HeaderMap)->bool {
 headers.get_all(header::ACCEPT_ENCODING).iter().filter_map(|v|v.to_str().ok()).flat_map(|v|v.split(',')).any(|item| {
  let mut parts=item.split(';').map(str::trim);
  let name=parts.next().unwrap_or("");
  let q=parts.find_map(|p|p.strip_prefix("q=")).map_or(Some(1.0),|q|q.trim().parse::<f32>().ok());
  (name.eq_ignore_ascii_case("gzip")||name=="*")&&q.is_some_and(|q|q>0.0)
 })
}

// ------------------------------------------------------------------ 答复缓存

/// 缓存里一份答好的体留多久。
const ANSWER_TTL:Duration=Duration::from_secs(60);
/// 最多留几份、合计多少字节（压缩后的体）；超了先扔最久没用的。单份超过总额的不留（照常回给等着的请求）。
const ANSWER_ENTRIES:usize=64;
const ANSWER_BYTES:usize=32*1024*1024;

/// 合并与缓存的键：base、起止按分钟取整、`minLifeMs`、已结束单的上限、回不回 gzip。
#[derive(Clone,Debug,PartialEq,Eq,Hash)]
struct Key {base:String,from_minute:i64,to_minute:i64,min_life:i64,limit:i64,gzip:bool}
impl Key {
 fn new(base:&str,from:i64,to:i64,min_life:i64,gzip:bool)->Self {
  Self{base:base.to_owned(),from_minute:from.div_euclid(60_000),to_minute:to.div_euclid(60_000),min_life,limit:MAX_PAGE,gzip}
 }
 fn limit(self,limit:i64)->Self {Self{limit,..self}}
 /// 这一键实际读的区间：起点那一分钟的开头到终点那一分钟的末尾。
 fn window(&self)->(i64,i64) {(self.from_minute*60_000,self.to_minute*60_000+59_999)}
}

/// 答好的体：一块一块的（压缩的或原文），合计字节数，回的 `Cache-Control`。块是 `Bytes`，发给几个请求只是加引用计数。
#[derive(Clone,Debug)]
struct Answer {chunks:Arc<[axum::body::Bytes]>,len:usize,gzip:bool,cache:&'static str}
impl Answer {
 fn response(&self)->Response {
  let chunks=self.chunks.clone();
  let mut response=Response::new(axum::body::Body::from_stream(futures_util::stream::iter((0..chunks.len()).map(move|i|Ok::<_,std::convert::Infallible>(chunks[i].clone())))));
  let headers=response.headers_mut();
  headers.insert(header::CONTENT_TYPE,HeaderValue::from_static("application/json"));
  headers.insert(header::CONTENT_LENGTH,HeaderValue::from(self.len));
  headers.insert(header::CACHE_CONTROL,HeaderValue::from_static(self.cache));
  headers.insert(header::VARY,HeaderValue::from_static("accept-encoding"));
  if self.gzip {headers.insert(header::CONTENT_ENCODING,HeaderValue::from_static("gzip"));}
  response
 }
}

/// 一个键一格：第一个到的请求读库、组答复，同时到的等它（`OnceCell`）；它失败了（或被取消）下一个等着的接着自己读。
#[derive(Default)]
struct Slot {answer:tokio::sync::OnceCell<(Answer,tokio::time::Instant)>,used:AtomicU64}

/// 历史的答复按分钟取整的窗口留 60 秒；深度热力（`heat`）也用这一套，键是它自己的、留 5 秒。
struct Answers<K> {slots:Mutex<HashMap<K,Arc<Slot>>>,tick:AtomicU64,ttl:Duration}
static ANSWERS:std::sync::LazyLock<Answers<Key>>=std::sync::LazyLock::new(||Answers::new(ANSWER_TTL));

impl<K:Clone+Eq+std::hash::Hash> Answers<K> {
 fn new(ttl:Duration)->Self {Self{slots:Mutex::new(HashMap::new()),tick:AtomicU64::new(0),ttl}}

 async fn get_or_build<F,Fut>(&self,key:K,build:F)->Result<Answer> where F:FnOnce()->Fut,Fut:std::future::Future<Output=Result<Answer>> {
  let slot={
   let mut slots=self.slots.lock().unwrap_or_else(|e|e.into_inner());
   let now=tokio::time::Instant::now();
   if slots.get(&key).is_some_and(|s|s.answer.get().is_some_and(|(_,at)|now.duration_since(*at)>=self.ttl)) {slots.remove(&key);}
   let slot=slots.entry(key).or_default().clone();
   slot.used.store(self.tick.fetch_add(1,Ordering::Relaxed)+1,Ordering::Relaxed);
   slot
  };
  let answer=slot.answer.get_or_try_init(||async {Ok::<_,ApiError>((build().await?,tokio::time::Instant::now()))}).await.map(|(a,_)|a.clone());
  drop(slot);
  self.trim();
  answer
 }

 /// 扔掉过期的、没人等着又没答成的格；再按最久没用的先扔，直到条数与字节都在额度以内。
 fn trim(&self) {
  let mut slots=self.slots.lock().unwrap_or_else(|e|e.into_inner());
  let now=tokio::time::Instant::now();
  slots.retain(|_,s|match s.answer.get() {Some((a,at))=>a.len<=ANSWER_BYTES&&now.duration_since(*at)<self.ttl,None=>Arc::strong_count(s)>1});
  loop {
   let ready=slots.iter().filter_map(|(k,s)|s.answer.get().map(|(a,_)|(k,a.len,s.used.load(Ordering::Relaxed))));
   let (mut count,mut bytes,mut oldest)=(0usize,0usize,None::<(&K,u64)>);
   for (k,len,used) in ready {
    count+=1;bytes+=len;
    if oldest.is_none_or(|(_,u)|used<u) {oldest=Some((k,used));}
   }
   if count<=ANSWER_ENTRIES&&bytes<=ANSWER_BYTES {break}
   let Some((k,_))=oldest else {break};
   let k=k.clone();
   slots.remove(&k);
  }
 }

 #[cfg(test)]
 fn cached(&self)->(usize,usize) {
  let slots=self.slots.lock().unwrap();
  slots.values().filter_map(|s|s.answer.get()).fold((0,0),|(n,b),(a,_)|(n+1,b+a.len))
 }
}

/// 组好的 JSON 装成答复（要 gzip 就压好），带给定的 `Cache-Control`。深度热力与分钟成交共用。
fn packed(json:String,gzip:bool,cache:&'static str)->Result<Answer> {
 use std::io::Write as _;
 let bytes:Vec<u8>=if gzip {
  let mut g=flate2::write::GzEncoder::new(Vec::with_capacity(json.len()/6),flate2::Compression::fast());
  g.write_all(json.as_bytes()).and_then(|_|g.finish()).map_err(|e|{tracing::warn!("Orderflow: reply not compressed: {e}");ApiError(axum::http::StatusCode::SERVICE_UNAVAILABLE,"temporarily_unavailable")})?
 } else {json.into_bytes()};
 let len=bytes.len();
 Ok(Answer{chunks:vec![axum::body::Bytes::from(bytes)].into(),len,gzip,cache})
}

/// 一个数写进 JSON：整数不带 `.0`。深度热力与分钟成交共用。
fn json_number(out:&mut String,v:f64) {
 use std::fmt::Write as _;
 if v.fract()==0.0&&v.abs()<9e15 {let _=write!(out,"{}",v as i64);} else {let _=write!(out,"{}",serde_json::Number::from_f64(v).map_or_else(||"0".to_string(),|n|n.to_string()));}
}

/// 同一时刻最多几个历史请求在读库、组答复。不带 `limit` 的老请求最多 20 万行、答复约 60 MB（带 `limit` 的已结束最多 5000 条）；
/// 接口不要登录，不限的话几个同时到就能把 serve（上限 1 GB）撑爆，还占满 8 条库连接里的一大半。深度热力也占这组名额。
static HISTORY_READS:tokio::sync::Semaphore=tokio::sync::Semaphore::const_new(2);
/// 答复按这么大一块一块攒：不攒成一整块连续内存（翻倍扩容时新旧两块同时在）。
const REPLY_CHUNK:usize=64*1024;

/// 攒答复的 JSON：写满一块封一块。
#[derive(Default)]
struct Chunks {done:Vec<axum::body::Bytes>,current:Vec<u8>,len:usize}
impl std::io::Write for Chunks {
 fn write(&mut self,buf:&[u8])->std::io::Result<usize> {
  if self.current.capacity()==0 {self.current.reserve_exact(REPLY_CHUNK);}
  self.current.extend_from_slice(buf);
  self.len+=buf.len();
  if self.current.len()>=REPLY_CHUNK {self.done.push(std::mem::take(&mut self.current).into());}
  Ok(buf.len())
 }
 fn flush(&mut self)->std::io::Result<()> {Ok(())}
}

/// 答复写到哪：原文直接攒块，gzip 边写边压再攒块（原来整块原文交给压缩层，缓存不了压好的体）。
/// 压缩前垫一层 64 KB 缓冲：serde_json 一个记号写一次，每次都进 deflate 的话 ETH 24h（3 万行、10 MB）要 0.7 s，垫了之后压缩只占零头。
#[allow(clippy::large_enum_variant)] // 一次答复一个，不值得装箱。
enum Sink {Plain(Chunks),Gzip(std::io::BufWriter<flate2::write::GzEncoder<Chunks>>)}
impl std::io::Write for Sink {
 fn write(&mut self,buf:&[u8])->std::io::Result<usize> {match self {Self::Plain(c)=>c.write(buf),Self::Gzip(g)=>g.write(buf)}}
 fn flush(&mut self)->std::io::Result<()> {Ok(())}
}

/// 读区间、组答复：一行一行从库里读、一行一行写成 JSON（要 gzip 就边写边压），不攒整张表、不经 `serde_json::Value`。
/// 形状同原来的 `{"base","thresholds","trackedSinceMs","orders":[…]}`（键的先后不同，客户端按名取）。
/// `min_life` 大于 0 时不回寿命短于它的已结束单（挂着的照回），见 `store::range_each`。
/// 已结束的最多 `limit` 条（留最新的）；末尾补 `"nextBefore"`：还有更早的没回时是回的最早那条已结束单的出现时刻，否则为 null。
#[allow(clippy::too_many_arguments)]
async fn reply(pool:&PgPool,base:&str,from:i64,to:i64,min_life:i64,limit:i64,thresholds:Thresholds,tracked_since:i64,gzip:bool)->Result<Answer> {
 use std::io::Write as _;
 let busy=||ApiError(axum::http::StatusCode::SERVICE_UNAVAILABLE,"temporarily_unavailable");
 let _slot=HISTORY_READS.acquire().await.map_err(|_|busy())?;
 let mut out=if gzip {Sink::Gzip(std::io::BufWriter::with_capacity(REPLY_CHUNK,flate2::write::GzEncoder::new(Chunks::default(),flate2::Compression::default())))} else {Sink::Plain(Chunks::default())};
 let head=serde_json::json!({"base":base,"thresholds":thresholds,"trackedSinceMs":tracked_since}).to_string();
 let _=write!(out,"{},\"orders\":[",&head[..head.len()-1]);
 let mut first=true;
 let mut failed=None;
 // 行按出现时刻升序来：第一条已结束的就是回的里面最早的那条。
 let mut earliest=None::<i64>;
 let (_,more)=store::range_each(pool,base,from,to,min_life,limit,|o| {
  if o.end_ms.is_some() {earliest.get_or_insert(o.first_seen_ms);}
  if failed.is_some() {return}
  if !first {let _=out.write_all(b",");}
  first=false;
  if let Err(e)=serde_json::to_writer(&mut out,&o) {failed=Some(e);}
 }).await?;
 if let Some(e)=failed {tracing::warn!("Orderflow history: {base} reply not serialized: {e}");return Err(busy())}
 match earliest.filter(|_|more) {
  Some(t)=>{let _=write!(out,"],\"nextBefore\":{t}}}");},
  None=>{let _=out.write_all(b"],\"nextBefore\":null}");},
 }
 let chunks=match out {
  Sink::Plain(c)=>c,
  Sink::Gzip(g)=>g.into_inner().map_err(|e|e.into_error()).and_then(|g|g.finish()).map_err(|e|{tracing::warn!("Orderflow history: {base} reply not compressed: {e}");busy()})?,
 };
 let Chunks{mut done,current,len}=chunks;
 if !current.is_empty() {done.push(current.into());}
 Ok(Answer{chunks:done.into(),len,gzip,cache:"no-cache"})
}

pub fn routes()->Router<AppState> {
 Router::new().route(PATH,get(history)).route(heat::PATH,get(heat::heat)).route(flow::PATH,get(flow::flow))
  .route(liq::PATH,get(liq::liq))
  .route(highlights::PATH,get(highlights::highlights))
  .route(highlights::BOARD_PATH,get(highlights::highlights_board))
  .route(highlights::MARKET_BOARD_PATH,get(highlights::market_board))
  .route(highlights::MOVES_PATH,get(highlights::market_moves))
  .route(insights::PATH,get(insights::insights))
  .route(footprint::PATH,get(footprint::footprint)).route(seconds::PATH,get(seconds::seconds))
  .route_layer(axum::middleware::from_fn(per_client))
}

/// 同一来源地址同时在处理的历史请求（大单 / 热力 / 分钟成交 / 足迹 / 秒线 / 爆仓六条合计）最多几条。
/// 网页十六图一屏全开时一格最多同时要两三条（热力 + 足迹或秒线 + 往前翻页），24 条够一个家庭网络几台设备同时开；
/// 读库只有 `HISTORY_READS` 两个名额，不限的话一个匿名客户端开几十条并发就把别人全挤在后面排队（2026-10-07 压测：
/// 一个来源 60 并发打秒线，别人的请求跟着排到 1.4 秒）。
const PER_CLIENT:usize=24;
static CLIENTS:std::sync::LazyLock<std::sync::Mutex<HashMap<std::net::IpAddr,usize>>>=std::sync::LazyLock::new(Default::default);

/// 一个来源占着的一条名额；请求处理完（或被超时那层半路丢掉）时还回去。
struct ClientLease(std::net::IpAddr);
impl Drop for ClientLease {
 fn drop(&mut self) {
  let mut clients=CLIENTS.lock().unwrap_or_else(|e|e.into_inner());
  if let Some(n)=clients.get_mut(&self.0) {
   *n=n.saturating_sub(1);
   if *n==0 {clients.remove(&self.0);}
  }
 }
}

/// 超过 [`PER_CLIENT`] 的立刻回 429 `history_client_limit` + `Retry-After: 1`，不进队、不占连接。
/// 来源地址按 `auth::client_ip`：对端是本机（前面的 Caddy）才认 `X-Forwarded-For` 的最后一段。
async fn per_client(req:axum::extract::Request,next:axum::middleware::Next)->axum::response::Response {
 use axum::response::IntoResponse as _;
 let peer=req.extensions().get::<axum::extract::ConnectInfo<std::net::SocketAddr>>().map(|c|c.0)
  .unwrap_or(std::net::SocketAddr::from((std::net::Ipv4Addr::UNSPECIFIED,0)));
 let ip=crate::auth::client_ip(&peer,req.headers());
 let lease={
  let mut clients=CLIENTS.lock().unwrap_or_else(|e|e.into_inner());
  let n=clients.entry(ip).or_insert(0);
  if *n>=PER_CLIENT {None} else {*n+=1;Some(ClientLease(ip))}
 };
 let Some(_lease)=lease else {
  let mut reply=ApiError(axum::http::StatusCode::TOO_MANY_REQUESTS,"history_client_limit").into_response();
  reply.headers_mut().insert(axum::http::header::RETRY_AFTER,axum::http::HeaderValue::from_static("1"));
  return reply
 };
 next.run(req).await
}

#[cfg(test)]
mod tests {
 use super::*;

 #[test] fn live_rows_are_rewritten_only_when_they_move_or_age() {
  use model::Status;
  let order=|notional:f64,filled:f64|BigOrder{venue_id:"binance:usdtPerp:BTCUSDT".into(),exchange:"币安".into(),product:"usdtPerp".into(),side:book::Side::Bid,
   bucket:599,price:59_950.0,first_seen_ms:1_000,end_ms:None,status:Status::Live,initial_notional:6e6,notional,filled_notional:filled,threshold:5e6,vanished_notional:None};
  let mut written=HashMap::new();
  assert_eq!(changed_live(vec![(order(6e6,0.0),0)],&mut written,0,LIVE_REWRITE_MS).len(),1,"新出现的写");
  assert!(changed_live(vec![(order(6.03e6,0.0),15_000)],&mut written,15_000,LIVE_REWRITE_MS).is_empty(),"动了不到 1% 不写");
  assert_eq!(changed_live(vec![(order(6.2e6,0.0),30_000)],&mut written,30_000,LIVE_REWRITE_MS).len(),1,"量动了写");
  assert_eq!(changed_live(vec![(order(6.2e6,1e5),45_000)],&mut written,45_000,LIVE_REWRITE_MS).len(),1,"成交动了写");
  assert!(changed_live(vec![(order(6.2e6,1e5),60_000)],&mut written,60_000,LIVE_REWRITE_MS).is_empty());
  assert_eq!(changed_live(vec![(order(6.2e6,1e5),105_000)],&mut written,105_000,LIVE_REWRITE_MS).len(),1,"一分钟没写过：刷新 seen_ms");
  assert!(LIVE_REWRITE_MS<model::STALE_MS);
  changed_live(Vec::new(),&mut written,120_000,LIVE_REWRITE_MS);
  assert!(written.is_empty(),"不再挂着的不留");
 }

 #[test] fn pending_writes_keep_the_latest_row_and_never_reopen_an_end() {
  use model::Status;
  let order=|bucket:i64,notional:f64,end:Option<i64>|BigOrder{venue_id:"binance:usdtPerp:BTCUSDT".into(),exchange:"币安".into(),product:"usdtPerp".into(),
   side:book::Side::Bid,bucket,price:59_950.0,first_seen_ms:1_000,end_ms:end,status:if end.is_some() {Status::Cancelled} else {Status::Live},
   initial_notional:6e6,notional,filled_notional:0.0,threshold:5e6,vanished_notional:None};
  let mut p=Pending::default();
  p.add(Write{step:100.0,rows:vec![(order(599,6e6,None),10_000),(order(598,6e6,None),10_000)]});
  // 第一批写失败留着；这期间 599 结束了、598 量变了。
  p.add(Write{step:100.0,rows:vec![(order(599,6e6,Some(20_000)),20_000)]});
  p.add(Write{step:100.0,rows:vec![(order(598,7e6,None),25_000)]});
  // 晚到的一份「599 还挂着」不能把结束盖回去。
  p.add(Write{step:100.0,rows:vec![(order(599,6e6,None),26_000)]});
  assert_eq!(p.rows.len(),2,"一单一份");
  let get=|b:i64|p.rows.values().find(|(_,o,_)|o.bucket==b).unwrap();
  assert_eq!(get(599).1.end_ms,Some(20_000));
  assert_eq!((get(598).1.notional,get(598).2),(7e6,25_000));
  // 步长不同分两批，每批最多 500 行。
  p.add(Write{step:50.0,rows:(0..1_200).map(|b|(order(10_000+b,6e6,None),30_000)).collect()});
  let batches=p.batches();
  assert!(batches.iter().all(|(_,k)|k.len()<=500));
  assert_eq!(batches.iter().filter(|(s,_)|*s==100.0).map(|(_,k)|k.len()).sum::<usize>(),2);
  assert_eq!(batches.iter().filter(|(s,_)|*s==50.0).map(|(_,k)|k.len()).sum::<usize>(),1_200);
 }

 #[test] fn pending_writes_shed_live_rows_before_ends() {
  use model::Status;
  let order=|bucket:i64,end:Option<i64>|BigOrder{venue_id:"a".into(),exchange:"币安".into(),product:"spot".into(),side:book::Side::Ask,bucket,price:1.0,
   first_seen_ms:0,end_ms:end,status:if end.is_some() {Status::Lost} else {Status::Live},initial_notional:1.0,notional:1.0,filled_notional:0.0,threshold:1.0,vanished_notional:None};
  let mut p=Pending::default();
  p.add(Write{step:1.0,rows:(0..10).map(|b|(order(b,None),0)).collect()});
  p.add(Write{step:1.0,rows:(0..PENDING_CAP as i64).map(|b|(order(100+b,Some(b)),b)).collect()});
  assert_eq!(p.rows.len(),PENDING_CAP,"挂着的先丢（一分钟内会整行重写）");
  assert!(p.rows.values().all(|(_,o,_)|o.end_ms.is_some()));
  p.add(Write{step:1.0,rows:vec![(order(-1,Some(1_000_000)),1_000_000)]});
  assert_eq!(p.rows.len(),PENDING_CAP);
  assert!(!p.rows.values().any(|(_,o,_)|o.end_ms==Some(0)),"还超就丢结束得最早的");
 }

 #[test] fn coin_or_not_is_never_guessed() {
  let perp=Venue{exchange:BINANCE,product:Product::UsdtPerp,instrument:"NVDAUSDT".into(),margin:None,
   notional:instruments::Notional::Linear{multiplier:1.0},tick:0.01,expiry_ms:None,price_scale:None,listed_base:"NVDA".into()};
  let info=serde_json::json!({"symbols":[{"symbol":"NVDAUSDT","underlyingType":"EQUITY"},{"symbol":"DOGEUSDT","underlyingType":"COIN"}]});
  assert_eq!(crypto_kind("NVDA",Some(&perp),None,Some(&info)),Some(false));
  assert_eq!(crypto_kind("NVDA",Some(&perp),None,None),None,"合约表拿不到：不知道，不按币算");
  assert_eq!(crypto_kind("NVDA",Some(&perp),Some(false),None),Some(false),"起跟时判过的，重算门槛时沿用");
  assert_eq!(crypto_kind("BTC",Some(&perp),None,None),Some(true),"主币不用查");
  assert_eq!(crypto_kind("FOO",None,None,None),Some(true),"币安没有这只永续：按币算");
  let doge=Venue{instrument:"DOGEUSDT".into(),listed_base:"DOGE".into(),..perp.clone()};
  assert_eq!(crypto_kind("DOGE",Some(&doge),None,Some(&info)),Some(true));
 }

 #[test] fn snapshot_retries_back_off_to_five_minutes() {
  assert_eq!((1..=9).map(snapshot_backoff).collect::<Vec<_>>(),vec![2_000,4_000,8_000,16_000,32_000,64_000,128_000,256_000,300_000]);
  assert_eq!(snapshot_backoff(u32::MAX),SNAPSHOT_RETRY_MAX_MS);
  // 一直拿不到的一本：一小时里只占十几份配额，不是 1800 份。
  let (mut t,mut n,mut f)=(0i64,0,1u32);
  while t<3_600_000 {t+=snapshot_backoff(f);f+=1;n+=1;}
  assert!(n<20,"{n}");
 }

 /// 重取品种表 / 门槛在网络慢时要很久（每个请求 20 秒超时；山寨要 24h 行情和两份日线，行情那份在单飞锁后面排，
 /// 失败不缓存、排在后面的挨个再超时一遍）。这期间跟踪任务照样收帧：按每秒 100 帧推，重取卡 100 秒，一帧都不丢。
 #[tokio::test(start_paused=true)] async fn a_slow_refresh_never_stops_the_tracker_draining_frames() {
  let (events,inbox)=mpsc::channel::<Event>(INBOX);
  let (control,control_rx)=mpsc::unbounded_channel::<Event>();
  let (writes,_writes_rx)=mpsc::channel::<Write>(WRITES_QUEUE);
  let (shared,_)=watch::channel(Thresholds::default());
  let thresholds=Thresholds{step:Some(1.0),..Default::default()};
  let t=Tracker{base:"ZZSLOW".into(),model:Model::new("ZZSLOW",thresholds),events:events.clone(),control,open:HashSet::new(),inflight:HashMap::new(),
   retry:HashMap::new(),failures:HashMap::new(),epochs:HashMap::new(),last_trade:HashMap::new(),flow:flow::Acc::default(),footprint:footprint::Acc::default(),insights:insights::Acc::default(),seconds:seconds::Acc::default(),tape:highlights::Tape::default(),written:HashMap::new(),priority:Arc::new(AtomicU8::new(0)),
   writes,calibration:Calibration{needed:false,value:None,day:None,partial:false,since:0,subscribed:0,restored:None},planned:thresholds,shared};
  let (stop_tx,stop)=watch::channel(false);
  let slow=|_due:bool|async {tokio::time::sleep(Duration::from_secs(100)).await;Refreshed{venues:vec![],thresholds:None}};
  let (_closing_tx,closing)=watch::channel(false);
  let tracker=tokio::spawn(run(t,inbox,control_rx,stop,closing,Duration::from_secs(1),slow));
  let (mut sent,mut dropped)=(0u32,0u32);
  for _ in 0..(120*100) {
   match events.try_send(Event::Frame{venue:"binance:usdtPerp:ZZSLOWUSDT".into(),connection:1,message:book::Message::Reset}) {
    Ok(())=>sent+=1,
    Err(_)=>dropped+=1,
   }
   tokio::time::sleep(Duration::from_millis(10)).await;
  }
  println!("重取卡 100 秒、每秒 100 帧推 120 秒：收下 {sent} 帧，丢 {dropped} 帧（收件口 {INBOX} 格）");
  stop_tx.send(true).unwrap();
  tokio::time::timeout(Duration::from_secs(200),tracker).await.expect("停了要能退出").unwrap();
  assert_eq!(dropped,0,"重取期间收件口没人收，满了丢帧");
 }

 fn tracker(base:&str)->(Tracker,mpsc::Receiver<Event>,mpsc::UnboundedReceiver<Event>,mpsc::Receiver<Write>) {
  let (events,inbox)=mpsc::channel::<Event>(INBOX);
  let (control,control_rx)=mpsc::unbounded_channel::<Event>();
  let (writes,writes_rx)=mpsc::channel::<Write>(WRITES_QUEUE);
  let (shared,_)=watch::channel(Thresholds::default());
  let thresholds=Thresholds{step:Some(100.0),usdt_perp:Some(5e6),..Default::default()};
  let t=Tracker{base:base.into(),model:Model::new(base,thresholds),events,control,open:HashSet::new(),inflight:HashMap::new(),
   retry:HashMap::new(),failures:HashMap::new(),epochs:HashMap::new(),last_trade:HashMap::new(),flow:flow::Acc::default(),footprint:footprint::Acc::default(),insights:insights::Acc::default(),seconds:seconds::Acc::default(),tape:highlights::Tape::default(),written:HashMap::new(),priority:Arc::new(AtomicU8::new(0)),
   writes,calibration:Calibration{needed:false,value:None,day:None,partial:false,since:0,subscribed:0,restored:None},planned:thresholds,shared};
  (t,inbox,control_rx,writes_rx)
 }

 /// SIGTERM：跟踪任务不把挂着的单判成失联（原来停机走的是和「不再跟」同一条路，`model.stop()` 把手里的全写成失联，
 /// 靠下一个进程读回时 `WHERE end_ms IS NULL` 以外的行都认不回来）。结束了还没写的、从没写过的交给写库任务，
 /// 所有挂着的单的最后一次看到交回去一句 UPDATE 刷掉。
 #[tokio::test(start_paused=true)] async fn sigterm_hands_live_orders_over_instead_of_ending_them() {
  use model::Status;
  let (mut t,inbox,control_rx,mut writes_rx)=tracker("ZZBYE");
  let now=now_ms();
  let order=|bucket:i64|BigOrder{venue_id:"binance:usdtPerp:ZZBYEUSDT".into(),exchange:"币安".into(),product:"usdtPerp".into(),side:book::Side::Bid,
   bucket,price:bucket as f64*100.0,first_seen_ms:now-600_000,end_ms:None,status:Status::Live,initial_notional:6e6,notional:6e6,filled_notional:0.0,
   threshold:5e6,vanished_notional:None};
  // 1、2 挂着（1 已经写过库），3 缺席太久读回来当场失联、还没写。
  t.model.restore(vec![Restored{order:order(1),step:100.0,seen_ms:now-10_000},Restored{order:order(2),step:100.0,seen_ms:now-20_000},
   Restored{order:order(3),step:100.0,seen_ms:now-10*60_000}],now);
  t.written.insert(("binance:usdtPerp:ZZBYEUSDT".into(),book::Side::Bid,1,now-600_000),(6e6,0.0,5e6,now-30_000));
  let (_stop_tx,stop)=watch::channel(false);
  let (closing_tx,closing)=watch::channel(false);
  let never=|_due:bool|std::future::pending::<Refreshed>();
  let running=tokio::spawn(run(t,inbox,control_rx,stop,closing,Duration::from_secs(600),never));
  tokio::time::sleep(Duration::from_secs(3)).await;
  closing_tx.send(true).unwrap();
  let (mut t,closing)=tokio::time::timeout(Duration::from_secs(1),running).await.expect("一拍之内交回").unwrap();
  assert!(closing);
  let handed=t.hand_over().await;
  assert_eq!(t.model.live_count(),2,"挂着的照旧挂着");
  assert_eq!(handed.base,"ZZBYE");
  let mut live:Vec<(i64,i64)>=handed.live.iter().map(|((_,_,bucket,_),seen)|(*bucket,*seen)).collect();
  live.sort();
  assert_eq!(live.iter().map(|(b,_)|*b).collect::<Vec<_>>(),vec![1,2],"两条挂着的都交回去刷 seen_ms");
  let ended=writes_rx.try_recv().unwrap();
  assert_eq!(ended.rows.iter().map(|(o,_)|(o.bucket,o.status)).collect::<Vec<_>>(),vec![(3,Status::Lost)],"没写的结束单先交写库");
  let fresh=writes_rx.try_recv().unwrap();
  assert_eq!(fresh.rows.iter().map(|(o,_)|o.bucket).collect::<Vec<_>>(),vec![2],"从没写过的挂着的交写库；写过的只刷 seen_ms");
  assert!(writes_rx.try_recv().is_err());
 }

 /// 停机收尾：收齐交单、一句 UPDATE、等写库任务；写库任务迟迟不完也在上限内返回。
 #[tokio::test] async fn shutdown_refreshes_seen_once_and_never_outlives_its_limit() {
  use model::Status;
  let Some(pool)=store::tests::isolated_pool().await else {return};
  store::tests::clear(&pool,&["ZZQ1","ZZQ2"]).await;
  let now=now_ms();
  let order=|base:&str,bucket:i64|BigOrder{venue_id:format!("binance:usdtPerp:{base}USDT"),exchange:"币安".into(),product:"usdtPerp".into(),side:book::Side::Ask,
   bucket,price:1.0,first_seen_ms:now-600_000,end_ms:None,status:Status::Live,initial_notional:6e6,notional:6e6,filled_notional:0.0,threshold:5e6,vanished_notional:None};
  store::upsert(&pool,"ZZQ1",1.0,&[(order("ZZQ1",1),now-70_000),(order("ZZQ1",2),now-70_000)]).await.unwrap();
  store::upsert(&pool,"ZZQ2",1.0,&[(order("ZZQ2",1),now-70_000)]).await.unwrap();
  let key=|base:&str,bucket:i64|->LiveKey {(format!("binance:usdtPerp:{base}USDT"),book::Side::Ask,bucket,now-600_000)};
  let (tx,rx)=mpsc::unbounded_channel();
  tx.send(Final{base:"ZZQ1".into(),live:vec![(key("ZZQ1",1),now-1_000),(key("ZZQ1",2),now-2_000)]}).unwrap();
  tx.send(Final{base:"ZZQ2".into(),live:vec![(key("ZZQ2",1),now-3_000)]}).unwrap();
  let active=std::sync::atomic::AtomicUsize::new(0);
  let closed=close(&pool,rx,2,&active,Duration::from_secs(2),Duration::from_secs(10)).await;
  assert_eq!((closed.bases,closed.live,closed.refreshed,closed.writing),(2,3,Some(3),0));
  assert!(closed.elapsed_ms<1_000,"都到齐了不空等：{} ms",closed.elapsed_ms);
  let seen:Vec<i64>=sqlx::query_scalar("SELECT seen_ms FROM orderflow_live WHERE base IN ('ZZQ1','ZZQ2') ORDER BY base,bucket").fetch_all(&pool).await.unwrap();
  assert_eq!(seen,vec![now-1_000,now-2_000,now-3_000]);
  // 少到一份、写库任务一直没完：到交单上限先刷已到的，到整段上限返回。
  let (tx,rx)=mpsc::unbounded_channel();
  tx.send(Final{base:"ZZQ2".into(),live:vec![(key("ZZQ2",1),now)]}).unwrap();
  let active=std::sync::atomic::AtomicUsize::new(1);
  let started=std::time::Instant::now();
  let closed=close(&pool,rx,2,&active,Duration::from_millis(200),Duration::from_millis(600)).await;
  let took=started.elapsed().as_millis();
  assert_eq!((closed.bases,closed.refreshed,closed.writing),(1,Some(1),1));
  assert!((600..1_500).contains(&took),"整段上限 600 ms，用了 {took} ms");
  drop(tx);
  store::tests::clear(&pool,&["ZZQ1","ZZQ2"]).await;
 }

 /// 订单流表被锁住 3 秒（同样代表慢盘、清理删大批）：订单流这边照常的一阵活——三个写库、两个读历史、六只起跟读回、
 /// 一次清理——全卡在库上。量账号这类用户接口此时拿连接要等多久：和订单流共用 serve 的 8 条（原来）对订单流单开池子。
 #[tokio::test(flavor="multi_thread",worker_threads=4)] async fn orderflow_load_never_starves_the_user_api_of_connections() {
  let Some(isolated)=store::tests::isolated_pool().await else {return};
  let options=(*isolated.connect_options()).clone();
  let mut report=Vec::new();
  for own in [false,true] {
   let api=crate::pool_options(true).connect_with(options.clone()).await.unwrap();
   let orderflow=if own {own_pool(&api)} else {api.clone()};
   let mut locker=isolated.begin().await.unwrap();
   sqlx::query("LOCK TABLE orderflow_orders IN ACCESS EXCLUSIVE MODE").execute(&mut *locker).await.unwrap();
   let mut load=tokio::task::JoinSet::new();
   let row=BigOrder{venue_id:"binance:usdtPerp:ZZPOOLUSDT".into(),exchange:"币安".into(),product:"usdtPerp".into(),side:book::Side::Bid,bucket:1,price:1.0,
    first_seen_ms:1,end_ms:None,status:model::Status::Live,initial_notional:6e6,notional:6e6,filled_notional:0.0,threshold:5e6,vanished_notional:None};
   for i in 0..3 {let (p,row)=(orderflow.clone(),row.clone());load.spawn(async move {let _=store::upsert(&p,&format!("ZZPOOL{i}"),1.0,&[(row,1)]).await;});}
   for _ in 0..2 {let p=orderflow.clone();load.spawn(async move {let _=reply(&p,"ZZPOOL",0,1,0,MAX_PAGE,Thresholds::default(),0,true).await;});}
   for i in 0..6 {let p=orderflow.clone();load.spawn(async move {let _=store::live(&p,&format!("ZZPOOL{i}")).await;});}
   {let p=orderflow.clone();load.spawn(async move {let _=store::purge(&p,0,&[]).await;});}
   tokio::time::sleep(Duration::from_millis(300)).await;
   let started=std::time::Instant::now();
   sqlx::query("SELECT 1").execute(&api).await.unwrap();
   let waited=started.elapsed().as_millis();
   locker.rollback().await.unwrap();
   while load.join_next().await.is_some() {}
   store::tests::clear(&isolated,&["ZZPOOL","ZZPOOL0","ZZPOOL1","ZZPOOL2","ZZPOOL3","ZZPOOL4","ZZPOOL5"]).await;
   println!("{}：订单流卡在库上时，用户接口拿一条连接等了 {waited} ms",if own {"订单流单开池子"} else {"共用 8 条"});
   report.push(waited);
   orderflow.close().await;api.close().await;
  }
  assert!(report[1]<500,"订单流卡住时用户接口等了 {} ms",report[1]);
 }

 #[test] fn resyncs_back_off_until_the_book_holds_for_a_minute() {
  let mut f=0u32;
  // 快照接不上 / 就绪没撑住：一轮里第一次马上，之后 2、4、8 秒……
  assert_eq!((0..5).map(|i|resync_delay(&mut f,None,i)).collect::<Vec<_>>(),vec![0,2_000,4_000,8_000,16_000]);
  // 就绪了 59 秒又断档：还算这一轮没成。
  assert_eq!(resync_delay(&mut f,Some(100_000),159_000),32_000);
  // 撑过一分钟：新的一轮，马上重同步。
  assert_eq!(resync_delay(&mut f,Some(200_000),260_000),0);
  assert_eq!(f,1);
  // 拉不到快照也记在同一个数上：接着退避，不从头算。
  f=3;
  assert_eq!(resync_delay(&mut f,None,0),snapshot_backoff(3));
  let mut f=u32::MAX;
  assert_eq!(resync_delay(&mut f,None,0),SNAPSHOT_RETRY_MAX_MS,"不溢出");
 }

 #[test] fn calibration_waits_for_every_book_to_connect_and_its_snapshot() {
  let mut c=Calibration{needed:true,value:None,day:None,partial:false,since:0,subscribed:0,restored:None};
  // OKX 一本秒就绪，币安那本还在攒连接 / 排快照：不标。
  assert!(!c.due(5_000,0,2,1,true));
  assert!(!c.due(60_000,0,2,1,true),"还在等就一直往后推");
  // 币安那本连上、快照也拿到了但还没接上序号：从这一刻起 8 秒。
  assert!(!c.due(60_000+7_999,0,2,1,false));
  assert!(c.due(60_000+8_000,0,2,1,false));
  // 两本都就绪：立刻标。
  let mut c=Calibration{needed:true,value:None,day:None,partial:false,since:0,subscribed:0,restored:None};
  assert!(c.due(3_000,0,2,2,true));
  // 等满 10 分钟还有簿在等：用就绪的那本标。
  let mut c=Calibration{needed:true,value:None,day:None,partial:false,since:0,subscribed:0,restored:None};
  assert!(!c.due(CALIBRATION_CAP_MS-1,0,2,1,true));
  assert!(c.due(CALIBRATION_CAP_MS+model::CALIBRATION_WAIT_MS,0,2,1,true));
  // 没有簿：直接标（回退 200 万）。
  let mut c=Calibration{needed:true,value:None,day:None,partial:false,since:0,subscribed:0,restored:None};
  assert!(c.due(0,0,0,0,false));
 }

 #[test] fn calibration_upgrades_once_and_renews_daily() {
  let day=86_400_000;
  let mut c=Calibration{needed:true,value:Some(50_000.0),day:Some(day),partial:true,since:0,subscribed:0,restored:None};
  assert!(!c.due(1,day,2,1,false),"同一天、还是一部分簿：不补标");
  assert!(c.due(1,day,2,2,false),"全就绪了：补标一次");
  c.partial=false;
  assert!(!c.due(1,day,2,2,false));
  assert!(c.due(1,2*day,2,2,false),"跨 UTC 日重标");
  assert!(!c.due(1,2*day,2,0,false),"一本都没就绪不重标");
  let mut crypto=Calibration{needed:false,value:None,day:None,partial:false,since:0,subscribed:0,restored:None};
  assert!(!crypto.due(0,0,0,0,false),"币不标");
 }

 /// 线上 2026-09-27 四次部署重启，每次非币那一侧一千二到一千四百条挂单在读回时被判失联、一两分钟后又在同一档
 /// 当新单冒出来（74–89% 在 25 分钟内同档复现）：非币要等标定才读回，标定等币安快照排队（一次最长 237 秒），
 /// 原来「缺席超过 `STALE_MS`」按标定那一刻算，库里本来就落后 75 秒的最后一次看到再加上停机的几十秒，全部超了。
 /// 现在按读库那一刻算：读库时还在两分钟以内的接着跟，读库时就已经缺席两分钟的照旧失联。
 #[test] fn deferred_restore_judges_absence_at_read_time_not_calibration_time() {
  use model::Status;
  let (events,_inbox)=mpsc::channel::<Event>(INBOX);
  let (control,_control_rx)=mpsc::unbounded_channel::<Event>();
  let (writes,_writes_rx)=mpsc::channel::<Write>(WRITES_QUEUE);
  let (shared,_)=watch::channel(Thresholds::default());
  let thresholds=Thresholds{step:Some(1.0),..Default::default()};
  let order=|bucket:i64|BigOrder{venue_id:"binance:usdtPerp:ZZSTOCKUSDT".into(),exchange:"币安".into(),product:"usdtPerp".into(),side:book::Side::Bid,
   bucket,price:bucket as f64,first_seen_ms:1_000,end_ms:None,status:Status::Live,initial_notional:3e5,notional:3e5,filled_notional:0.0,threshold:2e5,vanished_notional:None};
  let read_at=10_000_000;
  let rows=vec![
   Restored{order:order(100),step:1.0,seen_ms:read_at-75_000},
   Restored{order:order(90),step:1.0,seen_ms:read_at-130_000},
  ];
  let mut t=Tracker{base:"ZZSTOCK".into(),model:Model::new("ZZSTOCK",thresholds),events,control,open:HashSet::new(),inflight:HashMap::new(),
   retry:HashMap::new(),failures:HashMap::new(),epochs:HashMap::new(),last_trade:HashMap::new(),flow:flow::Acc::default(),footprint:footprint::Acc::default(),insights:insights::Acc::default(),seconds:seconds::Acc::default(),tape:highlights::Tape::default(),written:HashMap::new(),priority:Arc::new(AtomicU8::new(0)),
   writes,calibration:Calibration{needed:true,value:None,day:None,partial:false,since:read_at,subscribed:read_at,restored:Some((rows,read_at))},planned:thresholds,shared};
  t.calibrate(read_at+237_000);
  assert!(t.calibration.value.is_some(),"标定了");
  let live:Vec<i64>=t.model.live().into_iter().map(|(o,_)|o.bucket).collect();
  assert_eq!(live,vec![100],"读库时 75 秒前还看到的接着跟");
  assert_eq!(t.model.ended.len(),1);
  let lost=&t.model.ended[0];
  assert_eq!((lost.bucket,lost.status,lost.end_ms),(90,Status::Lost,Some(read_at-130_000)),"读库时已缺席两分钟以上：按最后一次看到失联");
 }

 /// 按分钟模拟闸门：只卸热点那一层时 RSS 是 `base(分钟)`，热点放回来之后它的簿三分钟里填满、再多 `hot` 字节。
 /// 返回每次放回、每次卸层的分钟，和最后卸到第几层。
 fn simulate_gate(minutes:i64,base:impl Fn(i64)->u64,hot:u64)->(Vec<i64>,Vec<i64>,u8) {
  let unit=resources::Limits{memory_bytes:Some(1<<30),cpu_percent:Some(200.0)};
  let mut gate=Gate::default();
  // 第 2 档：Bybit 现货与热点都卸了。
  let (mut shed,mut hot_since)=(2u8,None::<i64>);
  let (mut restores,mut sheds)=(Vec::new(),Vec::new());
  for m in 1..=minutes {
   let ramp=hot_since.map_or(0,|t|hot*((m-t).min(3) as u64)/3);
   let load=resources::Load{rss_bytes:Some(base(m)+ramp),cpu_percent:Some(40.0),limits:unit};
   match gate.step(&load,shed,m*60_000) {
    Step::Shed=>{shed+=1;if shed==2 {hot_since=None;}sheds.push(m);},
    Step::Restore(_)=>{shed-=1;if shed==1 {hot_since=Some(m);}restores.push(m);},
    Step::Floor|Step::Hold=>{},
   }
  }
  (restores,sheds,shed)
 }

 /// 压测（2026-09-26）：卸掉热点后余量刚好够、放回来又超——放回、超、卸、十分钟后再放回，一直翻。
 /// 每翻一次热点 30 只全部停了重起：拉品种表、收盘、订阅、快照额度排队、挂着的单全记失联再读回。
 #[test] fn the_gate_does_not_flap_a_layer_that_keeps_pushing_it_over() {
  let mb=1_000_000u64;
  // 线是 1 GB 单元的四分之三 = 805 MB；卸了热点 600 MB，热点 250 MB。
  let (restores,sheds,_)=simulate_gate(6*60,|_|600*mb,250*mb);
  eprintln!("6 小时放回 {} 次、卸层 {} 次；放回在第 {:?} 分钟",restores.len(),sheds.len(),restores);
  assert!(restores.len()<=6,"6 小时里热点被放回 {} 次（每次 30 只停了重起）",restores.len());
  assert_eq!(restores.first(),Some(&10),"第一次仍是连续十分钟不超就放回");

  // 放回来不超的层：十分钟放回，之后一直不卸。
  let (restores,sheds,shed)=simulate_gate(6*60,|_|600*mb,100*mb);
  assert_eq!((restores,sheds,shed),(vec![10],vec![],1),"热点十分钟放回；放回后离线不够远，Bybit 现货留着卸");

  // 翻过几次之后负载真的降下来了（别的占用走了）：不能永远卸着，最多等一个封顶的间隔就放回并留住。
  let (restores,_,shed)=simulate_gate(8*60,|m|if m<150 {600*mb} else {300*mb},250*mb);
  let back=*restores.last().unwrap();
  assert_eq!(shed,0,"负载降了之后热点要回来");
  assert!(back>=150&&back<=150+SHED_RECOVER_CAP_MINUTES as i64+1,"负载在第 150 分钟降下来，第 {back} 分钟才放回");

  // 贴着线下（没超、但离线不到一成五）不算清：放回来一点就超，不去试。
  let (restores,_,shed)=simulate_gate(6*60,|_|760*mb,50*mb);
  assert_eq!((restores.len(),shed),(0,2),"离线太近不放回（Bybit 现货与热点都还卸着）：{restores:?}");
 }

 #[tokio::test] async fn a_base_started_again_waits_for_its_previous_tracker() {
  let r=Registry::new(PgPool::connect_lazy("postgres://nobody@127.0.0.1:1/none").unwrap());
  let (release,wait)=tokio::sync::oneshot::channel::<()>();
  let previous=tokio::spawn(async move {let _=wait.await;});
  r.retiring.lock().unwrap().insert("ZZT".into(),previous);
  {let mut entries=r.lock();r.start(&mut entries,"ZZT",0,true,|e|e.requested=1);}
  assert!(r.retiring.lock().unwrap().is_empty(),"上一任交给了新任务");
  tokio::time::sleep(Duration::from_millis(50)).await;
  assert!(!r.lock()["ZZT"].task.is_finished(),"上一任没收完尾：新任务在等，还没去读回挂着的单");
  // 停掉：任务进 retiring 收尾。等的时候被停不做事，但要等上一任收完尾才算结束——
  // 下一任等的是它，它先走了，下一任就会赶在上一任落库之前读回挂着的单。
  {let mut entries=r.lock();r.stop(&mut entries,"ZZT","stopped by the test");}
  assert!(!r.lock().contains_key("ZZT"));
  let task=r.retiring.lock().unwrap().remove("ZZT").expect("停掉的任务留给下一任等");
  tokio::time::sleep(Duration::from_millis(50)).await;
  assert!(!task.is_finished(),"上一任还在收尾：停掉的这一任要替下一任接着等");
  drop(release);
  tokio::time::timeout(Duration::from_secs(1),task).await.unwrap().unwrap();
 }

 /// 压测（2026-09-26）：一只在按需 / 热点边上反复进出，起了停、停了起，上一任一直没收完尾。
 /// 原来等上一任的时候被停就直接返回、手里上一任的句柄随之丢掉：retiring 里记的是这个早已结束的任务，
 /// 下一任等它等了个空，和还在落库的上一任同时跑——同一只两个跟踪器，读回的挂着的单被旧任务的失联结束盖掉。
 /// 500 轮起停之后，retiring 里那一个必须还在等最早那一任；最早那一任一结束，整条链收干净、不漏任务。
 #[tokio::test(flavor="multi_thread",worker_threads=2)] async fn start_stop_churn_never_lets_two_trackers_overlap() {
  let r=Registry::new(PgPool::connect_lazy("postgres://nobody@127.0.0.1:1/none").unwrap());
  let metrics=tokio::runtime::Handle::current().metrics();
  let baseline=metrics.num_alive_tasks();
  let (release,wait)=tokio::sync::oneshot::channel::<()>();
  let finished=Arc::new(AtomicBool::new(false));
  let flag=finished.clone();
  let first=tokio::spawn(async move {let _=wait.await;flag.store(true,Ordering::SeqCst);});
  r.retiring.lock().unwrap().insert("ZZC".into(),first);
  for round in 0..500 {
   {let mut entries=r.lock();r.start(&mut entries,"ZZC",0,true,|e|e.requested=1);}
   {let mut entries=r.lock();r.stop(&mut entries,"ZZC","churn");}
   if round%50==0 {tokio::task::yield_now().await;}
  }
  tokio::time::sleep(Duration::from_millis(100)).await;
  let last=r.retiring.lock().unwrap().remove("ZZC").expect("最后一任在 retiring 里");
  assert!(!last.is_finished(),"最早那一任还没收完尾，最后一任（下一任要等的）不能已经结束");
  assert!(!finished.load(Ordering::SeqCst));
  drop(release);
  tokio::time::timeout(Duration::from_secs(5),last).await.expect("链收不干净").unwrap();
  assert!(finished.load(Ordering::SeqCst),"最后一任结束之前最早那一任必须已经结束");
  tokio::time::sleep(Duration::from_millis(50)).await;
  assert!(metrics.num_alive_tasks()<=baseline,"漏了任务：{} 个活着（起步 {baseline}）",metrics.num_alive_tasks());
 }

 #[tokio::test] async fn the_writer_keeps_taking_rows_while_it_waits_for_a_connection_slot() {
  use model::Status;
  let order=|bucket:i64|BigOrder{venue_id:"binance:usdtPerp:ZZWUSDT".into(),exchange:"币安".into(),product:"usdtPerp".into(),
   side:book::Side::Bid,bucket,price:1.0,first_seen_ms:1_000,end_ms:None,status:Status::Live,
   initial_notional:6e6,notional:6e6,filled_notional:0.0,threshold:5e6,vanished_notional:None};
  // 三条写库连接全被别的币占着。
  let held=WRITE_SLOTS.acquire_many(3).await.unwrap();
  let (tx,rx)=mpsc::channel::<Write>(2);
  let task=tokio::spawn(writer(PgPool::connect_lazy("postgres://nobody@127.0.0.1:1/none").unwrap(),"ZZW".into(),rx));
  // 远超通道容量的一串：写库任务在排连接时也要接着收，跟踪那边的 send 不能卡住。
  let sent=tokio::time::timeout(Duration::from_secs(2),async {
   for b in 0..50 {tx.send(Write{step:1.0,rows:vec![(order(b),10_000)]}).await.unwrap();}
  }).await;
  assert!(sent.is_ok(),"排连接的时候通道没人收，跟踪任务卡在 send 上");
  drop(held);
  task.abort();
 }

 /// 压测（2026-09-26）：库慢的时候（一条长事务攥着表锁、autovacuum、磁盘慢）写库任务正卡在一批 upsert 上，
 /// 跟踪那边照常每 500 ms 发一批结束的单。原来刷盘时不收：通道 256 格一满，跟踪任务卡在 `send` 上，
 /// 不再收 8192 格的帧口，连接任务往满的口里 `try_send` 的帧全丢（DROPS），簿断档、重拉快照、快照队雪崩。
 #[tokio::test(flavor="multi_thread",worker_threads=2)] async fn a_slow_database_write_never_blocks_the_tracker() {
  use model::Status;
  let Some(pool)=store::tests::isolated_pool().await else {return};
  let order=|n:i64|BigOrder{venue_id:"binance:usdtPerp:ZZSLOWUSDT".into(),exchange:"币安".into(),product:"usdtPerp".into(),
   side:book::Side::Bid,bucket:n,price:n as f64,first_seen_ms:1_000+n,end_ms:Some(2_000+n),status:Status::Cancelled,
   initial_notional:6e6,notional:6e6,filled_notional:0.0,threshold:5e6,vanished_notional:Some(6e6)};
  // 库这边：一条事务把表锁住 3 秒（写库任务的 upsert 就卡在这把锁上，和真实的慢语句一样不报错、只是不回）。
  let mut lock=pool.begin().await.unwrap();
  sqlx::query("LOCK TABLE orderflow_orders IN EXCLUSIVE MODE").execute(&mut *lock).await.unwrap();
  let (tx,rx)=mpsc::channel::<Write>(WRITES_QUEUE);
  let task=tokio::spawn(writer(pool.clone(),"ZZSLOW".into(),rx));
  tx.send(Write{step:1.0,rows:vec![(order(0),2_000)]}).await.unwrap();
  tokio::time::sleep(Duration::from_millis(200)).await;
  let hold=Duration::from_secs(3);
  let releaser=tokio::spawn(async move {tokio::time::sleep(hold).await;lock.commit().await.unwrap();});
  // 跟踪那边：两倍通道长度的结束单，一条一条发（每拍一条）。
  let started=std::time::Instant::now();
  let mut slowest=Duration::ZERO;
  for n in 1..=2*WRITES_QUEUE as i64 {
   let t=std::time::Instant::now();
   tx.send(Write{step:1.0,rows:vec![(order(n),2_000+n)]}).await.unwrap();
   slowest=slowest.max(t.elapsed());
  }
  let total=started.elapsed();
  println!("库锁 {}s 期间发 {} 批：共 {}ms，单次 send 最久 {}ms",hold.as_secs(),2*WRITES_QUEUE,total.as_millis(),slowest.as_millis());
  releaser.await.unwrap();
  drop(tx);
  tokio::time::timeout(Duration::from_secs(30),task).await.expect("写库任务收不了尾").unwrap();
  let written:i64=sqlx::query_scalar("SELECT count(*) FROM orderflow_orders WHERE base='ZZSLOW' AND end_ms IS NOT NULL").fetch_one(&pool).await.unwrap();
  store::tests::clear(&pool,&["ZZSLOW"]).await;
  assert!(slowest<Duration::from_millis(200),"库慢的时候跟踪任务卡在 send 上 {}ms",slowest.as_millis());
  assert_eq!(written,2*WRITES_QUEUE as i64+1,"锁一放，积压的全部写进去");
 }

 /// 刷盘途中同一单又来了新的一份：写进去的是旧的那份，新的那份不能跟着从积压里拿掉。
 #[test] fn a_row_updated_while_its_batch_is_being_written_stays_pending() {
  use model::Status;
  let order=|notional:f64,end:Option<i64>|BigOrder{venue_id:"v".into(),exchange:"币安".into(),product:"usdtPerp".into(),
   side:book::Side::Bid,bucket:1,price:1.0,first_seen_ms:1_000,end_ms:end,status:if end.is_some() {Status::Cancelled} else {Status::Live},
   initial_notional:6e6,notional,filled_notional:0.0,threshold:5e6,vanished_notional:None};
  let mut p=Pending::default();
  p.add(Write{step:1.0,rows:vec![(order(6e6,None),10_000),(BigOrder{bucket:2,..order(6e6,None)},10_000)]});
  let batches=p.batches();
  assert_eq!(batches.len(),1);
  let rows=p.rows_for(&batches[0].1);
  // 这一批在库里的时候：bucket 1 更新了、bucket 2 没动。
  p.add(Write{step:1.0,rows:vec![(order(7e6,Some(20_000)),20_000)]});
  p.written(&rows);
  assert_eq!(p.rows.len(),1,"没动的那行写完拿掉");
  assert_eq!(p.rows.values().next().unwrap().1.end_ms,Some(20_000),"更新过的留着下一批写");
 }

 /// 本进程此刻的常驻内存（KiB）。
 fn rss_kib()->u64 {
  let out=std::process::Command::new("ps").args(["-o","rss=","-p",&std::process::id().to_string()]).output().unwrap();
  String::from_utf8_lossy(&out.stdout).trim().parse().unwrap_or(0)
 }

 /// 压测（2026-09-26）：历史接口不要登录，一个请求就能把一只 base 三天内的单全拉回来（上限 `store::MAX_ROWS` 20 万行）。
 /// 线上 serve 单元 `MemoryMax=1G`，和订单流跟踪、账号同步在同一个进程里——几个这样的请求同时到，
 /// 整个进程不能被 OOM 杀掉。塞满 20 万行，量一个请求、四个并发请求的常驻内存峰值。
 /// 重：插 20 万行、读四遍，`python3 ops/test.py --lib -- orderflow_history::tests::history --ignored --nocapture`。
 #[ignore] #[tokio::test(flavor="multi_thread",worker_threads=4)] async fn history_reply_memory_stays_bounded_at_the_row_cap() {
  let Some(pool)=store::tests::isolated_pool().await else {return};
  let base="ZZMEM";
  store::tests::clear(&pool,&[base]).await;
  let rows=store::MAX_ROWS;
  sqlx::query("INSERT INTO orderflow_orders(base,venue_id,exchange,product,side,bucket,price,first_seen_ms,end_ms,status,initial_notional,notional,filled_notional,threshold,vanished_notional,step,seen_ms) \
   SELECT $1,'binance:usdtPerp:ZZMEMUSDT','币安','usdtPerp',CASE WHEN g%2=0 THEN 'bid' ELSE 'ask' END,g,g*1.5,1000000+g,1000000+g+60000,'cancelled',6e6,5.5e6,1.25e5,5e6,5.9e6,100,1000000+g+60000 \
   FROM generate_series(1,$2::bigint) g").bind(base).bind(rows).execute(&pool).await.unwrap();
  let (from,to)=(1_000_000,1_000_000+rows+120_000);
  let run=|pool:PgPool|async move {
   let response=reply(&pool,base,from,to,0,store::MAX_ROWS,Thresholds::default(),from,false).await.unwrap().response();
   axum::body::to_bytes(response.into_body(),usize::MAX).await.unwrap().len()
  };
  let sample=|stop:Arc<AtomicBool>,peak:Arc<AtomicU64>|std::thread::spawn(move||while !stop.load(Ordering::SeqCst) {peak.fetch_max(rss_kib(),Ordering::SeqCst);std::thread::sleep(Duration::from_millis(5));});
  let mut report=Vec::new();
  for parallel in [1usize,4] {
   let base_rss=rss_kib();
   let (stop,peak)=(Arc::new(AtomicBool::new(false)),Arc::new(AtomicU64::new(0)));
   let h=sample(stop.clone(),peak.clone());
   let started=std::time::Instant::now();
   let mut set=tokio::task::JoinSet::new();
   for _ in 0..parallel {set.spawn(run(pool.clone()));}
   let mut bytes=0;
   while let Some(n)=set.join_next().await {bytes=n.unwrap();}
   stop.store(true,Ordering::SeqCst);h.join().unwrap();
   let grew=peak.load(Ordering::SeqCst).saturating_sub(base_rss)/1024;
   println!("{parallel} 个请求 × {rows} 行：答复 {} MB，常驻内存峰值涨 {grew} MB（起步 {} MB），{} ms",bytes/1_000_000,base_rss/1024,started.elapsed().as_millis());
   report.push(grew);
  }
  store::tests::clear(&pool,&[base]).await;
  assert!(report[0]<150,"一个历史请求让常驻内存涨了 {} MB（答复本身 62 MB）",report[0]);
  assert!(report[1]<300,"四个并发的历史请求让常驻内存涨了 {} MB（serve 的上限一共 1 GB）",report[1]);
 }

 /// 计时（2026-09-28 第二轮）：照线上 ETH 24 小时的量（30,887 行、六个产品、约 1% 挂着）摆一份，
 /// 量走整条 `history` 取数路径（`ANSWERS.get_or_build` + `reply`）的首次读、缓存命中、五个并发同窗口、以及 `minLifeMs=60000`。
 /// `python3 ops/test.py --lib -- orderflow_history::tests::eth_day --ignored --nocapture`。
 #[ignore] #[tokio::test(flavor="multi_thread",worker_threads=4)] async fn eth_day_first_read_and_cache_hit() {
  let Some(pool)=store::tests::isolated_pool().await else {return};
  let base="ZZETH";
  store::tests::clear(&pool,&[base]).await;
  let (t0,day)=(1_790_000_000_000i64,86_400_000i64);
  // 六成是一分钟内就撤的，其余活几分钟到两小时；g%97==0 的挂着到现在。
  sqlx::query("INSERT INTO orderflow_orders(base,venue_id,exchange,product,side,bucket,price,first_seen_ms,end_ms,status,initial_notional,notional,filled_notional,threshold,vanished_notional,step,seen_ms) \
   SELECT $1,(ARRAY['binance:usdtPerp:ETHUSDT','binance:spot:ETHUSDT','binance:coinPerp:ETHUSD_PERP','okx:usdtPerp:ETH-USDT-SWAP','okx:spot:ETH-USDT','coinbase:spot:ETH-USD'])[1+g%6], \
    (ARRAY['币安','币安','币安','OKX','OKX','Coinbase'])[1+g%6],(ARRAY['usdtPerp','spot','coinPerp','usdtPerp','spot','spot'])[1+g%6], \
    CASE WHEN g%2=0 THEN 'bid' ELSE 'ask' END,2400+(g*31)%600,(2400+(g*31)%600)::float8, \
    $2+(g::bigint*2797)%($3-7200000), \
    CASE WHEN g%97=0 THEN NULL ELSE $2+(g::bigint*2797)%($3-7200000)+CASE WHEN g%10<6 THEN 5000+(g*131)%55000 ELSE 60000+(g::bigint*7919)%7140000 END END, \
    CASE WHEN g%97=0 THEN 'live' WHEN g%5=0 THEN 'filled' WHEN g%7=0 THEN 'lost' ELSE 'cancelled' END, \
    1e6+(g*7717)%9000000,1e6+(g*4211)%8000000,(g*977)%500000,CASE WHEN g%6 IN (1,4,5) THEN 1e6 ELSE 5e6 END,1e6+(g*3331)%7000000,1,$2+$3 \
   FROM generate_series(1,30887) g").bind(base).bind(t0).bind(day).execute(&pool).await.unwrap();
  // 挂着的按 0031 之前的写法插在历史表里：读回一次把它们搬进 `orderflow_live`（线上迁移与重启之间老进程写的那些也是这么搬的）。
  assert_eq!(store::live(&pool,base).await.unwrap().len(),30887/97);
  sqlx::query("ANALYZE orderflow_orders").execute(&pool).await.unwrap();
  sqlx::query("ANALYZE orderflow_live").execute(&pool).await.unwrap();
  let thresholds=Thresholds{spot:Some(1e6),usdt_perp:Some(5e6),coin_perp:Some(5e6),delivery:None,step:Some(1.0)};
  let (from,to)=(t0+30_000,t0+day+30_000);
  let get=|min_life:i64|{let pool=pool.clone();async move {
   let key=Key::new(base,from,to,min_life,true);
   let (from,to)=key.window();
   let started=std::time::Instant::now();
   let answer=ANSWERS.get_or_build(key,||reply(&pool,base,from,to,min_life,MAX_PAGE,thresholds,t0,true)).await.unwrap();
   (started.elapsed().as_secs_f64()*1000.0,answer.len)
  }};
  // 先把表页读进 Postgres 的缓存，量的是线上「热态」那一种（线上报告里 ETH 24h 热态 0.55 s）。
  store::range_each(&pool,base,from-60_000,to+60_000,0,store::MAX_ROWS,|_|{}).await.unwrap();
  let started=std::time::Instant::now();
  let (rows,_)=store::range_each(&pool,base,from-60_000,to+60_000,0,store::MAX_ROWS,|_|{}).await.unwrap();
  let read=started.elapsed().as_secs_f64()*1000.0;
  let (first,bytes)=get(0).await;
  let hits:Vec<f64>={let mut v=Vec::new();for _ in 0..5 {v.push(get(0).await.0);}v};
  // 五个并发、同一个新窗口（minLifeMs 不同 → 新键）：只读一次库，五个一起拿到。
  let started=std::time::Instant::now();
  let mut set=tokio::task::JoinSet::new();
  for _ in 0..5 {let g=get(60_000);set.spawn(g);}
  let mut sizes=Vec::new();
  while let Some(r)=set.join_next().await {sizes.push(r.unwrap().1);}
  let concurrent=started.elapsed().as_secs_f64()*1000.0;
  let (filtered_hit,filtered_bytes)=get(60_000).await;
  println!("ETH 24h 形状 {rows} 行：光读库 {read:.1} ms；整条路径首次 {first:.1} ms（gzip 后 {:.2} MB）；缓存命中 {} ms",bytes as f64/1e6,
   hits.iter().map(|h|format!("{h:.3}")).collect::<Vec<_>>().join(" / "));
  println!("minLifeMs=60000：五个并发同窗口共 {concurrent:.1} ms（各拿 {:.2} MB），之后命中 {filtered_hit:.3} ms",filtered_bytes as f64/1e6);
  // 带 minLifeMs 的查询仍用得上 `orderflow_orders_end`：寿命条件只是 Filter，不挡索引条件。
  // 测试库里这只 base 几乎是整张表，自动 analyze 跑过之后规划器有理由改走顺序扫（线上 ETH 只占表的一小份），
  // 所以关掉顺序扫再看——核对的是「用得上」，不是这张小表上的代价取舍。
  let mut tx=pool.begin().await.unwrap();
  sqlx::query("SET LOCAL enable_seqscan=off").execute(&mut *tx).await.unwrap();
  let plan:Vec<String>=sqlx::query_scalar(&format!("EXPLAIN {}",store::range_sql())).bind(base).bind(from).bind(to).bind(store::MAX_ROWS).bind(60_000i64)
   .fetch_all(&mut *tx).await.unwrap();
  tx.rollback().await.unwrap();
  println!("EXPLAIN（minLifeMs=60000）：\n{}",plan.join("\n"));
  let plan=plan.join("\n");
  assert!(plan.matches("orderflow_orders_end").count()>=2,"两路已结束的都该用 orderflow_orders_end：\n{plan}");
  assert!(!plan.contains("Seq Scan"),"不许顺序扫：\n{plan}");
  store::tests::clear(&pool,&[base]).await;
  assert!(sizes.iter().all(|&n|n==filtered_bytes));
  // 2026-09-29 起一页封顶 `MAX_PAGE` 条已结束的：这份 24 小时两种寿命门槛都超过五千条，两份答复都是整页，
  // 大小只差在内容上，不再比谁小；只核对都封住了（gzip 后远小于原来整窗的 0.9 MB）。
  assert!(bytes<400_000&&filtered_bytes<400_000,"封顶后的一页应在 0.4 MB 以内：{bytes} / {filtered_bytes}");
  assert!(hits.iter().all(|&h|h<5.0),"命中不碰库，应在毫秒以内：{hits:?}");
 }

 /// 边读边写出来的答复和原来整张表转 `Value` 的答复逐字段一致。
 #[tokio::test] async fn history_reply_matches_the_whole_table_shape() {
  use model::Status;
  let Some(pool)=store::tests::isolated_pool().await else {return};
  let base="ZZREPLY";
  store::tests::clear(&pool,&[base]).await;
  let order=|bucket:i64,first:i64,end:Option<i64>|BigOrder{venue_id:"binance:usdtPerp:ZZREPLYUSDT".into(),exchange:"币安".into(),product:"usdtPerp".into(),
   side:if bucket%2==0 {book::Side::Bid} else {book::Side::Ask},bucket,price:bucket as f64*0.1,first_seen_ms:first,end_ms:end,
   status:if end.is_some() {Status::Filled} else {Status::Live},initial_notional:6e6,notional:5.5e6,filled_notional:1.25e5,threshold:5e6,
   vanished_notional:end.map(|_|5.9e6)};
  let rows:Vec<(BigOrder,i64)>=(0..1_500).map(|b|(order(b,1_000+b*7,(b%3!=0).then_some(900_000+b)),900_000+b)).collect();
  store::upsert(&pool,base,0.1,&rows).await.unwrap();
  let thresholds=Thresholds{spot:Some(1e6),usdt_perp:Some(5e6),coin_perp:None,delivery:None,step:Some(0.1)};
  let response=reply(&pool,base,0,1_000_000,0,MAX_PAGE,thresholds,123,false).await.unwrap().response();
  assert_eq!(response.headers()[header::CONTENT_TYPE],"application/json");
  assert!(response.headers().get(header::CONTENT_ENCODING).is_none());
  let declared:usize=response.headers()[header::CONTENT_LENGTH].to_str().unwrap().parse().unwrap();
  let body=axum::body::to_bytes(response.into_body(),usize::MAX).await.unwrap();
  assert_eq!(body.len(),declared);
  let got:Value=serde_json::from_slice(&body).unwrap();
  let orders=store::range(&pool,base,0,1_000_000).await.unwrap();
  let want=serde_json::json!({"base":base,"thresholds":thresholds,"trackedSinceMs":123,"orders":orders,"nextBefore":null});
  // 比的是客户端收到的文本解析出来的样子：两边都过一遍「写成文本再解析」，免得 serde_json 解析浮点时的末位舍入差异混进来。
  let want:Value=serde_json::from_slice(&serde_json::to_vec(&want).unwrap()).unwrap();
  assert_eq!(got,want);
  assert_eq!(got["orders"].as_array().unwrap().len(),1_500);
  // 截到上限：挂着的 500 条全回，已结束的只回最新的 100 条；nextBefore 是其中最早的出现时刻，拿它当 to 翻下一页接得上。
  let page=|to:i64,limit:i64|{let pool=pool.clone();async move {
   let r=reply(&pool,base,0,to,0,limit,thresholds,123,false).await.unwrap().response();
   serde_json::from_slice::<Value>(&axum::body::to_bytes(r.into_body(),usize::MAX).await.unwrap()).unwrap()
  }};
  let ended_desc:Vec<i64>=(0..1_500).rev().filter(|b|b%3!=0).map(|b|1_000+b*7).collect();
  let first=page(1_000_000,100).await;
  let rows=first["orders"].as_array().unwrap();
  assert_eq!(rows.iter().filter(|o|o["endMs"].is_null()).count(),500,"挂着的不受上限");
  assert_eq!(rows.iter().filter(|o|!o["endMs"].is_null()).count(),100);
  assert_eq!(first["nextBefore"],serde_json::json!(ended_desc[99]));
  let second=page(ended_desc[99],100).await;
  let seen:HashSet<i64>=second["orders"].as_array().unwrap().iter().filter(|o|!o["endMs"].is_null()).map(|o|o["firstSeenMs"].as_i64().unwrap()).collect();
  assert_eq!(seen,ended_desc[99..199].iter().copied().collect(),"第二页从第一页最早那条接着往前（边界那条两页都有，客户端按单号合并）");
  assert_eq!(second["nextBefore"],serde_json::json!(ended_desc[198]));
  // 已结束的正好是上限以内：nextBefore 为 null。
  assert_eq!(page(1_000_000,1_000).await["nextBefore"],Value::Null);
  assert_eq!(page(1_000_000,999).await["nextBefore"],serde_json::json!(ended_desc[998]));
  // gzip 的那份解开和原文逐字节相同，头上标着 gzip、长度是压缩后的长度。
  let zipped=reply(&pool,base,0,1_000_000,0,MAX_PAGE,thresholds,123,true).await.unwrap().response();
  assert_eq!(zipped.headers()[header::CONTENT_ENCODING],"gzip");
  let declared:usize=zipped.headers()[header::CONTENT_LENGTH].to_str().unwrap().parse().unwrap();
  let packed=axum::body::to_bytes(zipped.into_body(),usize::MAX).await.unwrap();
  assert_eq!(packed.len(),declared);
  assert!(packed.len()*4<body.len(),"压缩后 {} 字节，原文 {}",packed.len(),body.len());
  let mut unpacked=Vec::new();
  std::io::Read::read_to_end(&mut flate2::read::GzDecoder::new(&packed[..]),&mut unpacked).unwrap();
  assert_eq!(unpacked,body);
  // 一行都没有也是合法的 JSON。
  for gzip in [false,true] {
   let empty=reply(&pool,"ZZNONE",0,1_000_000,0,MAX_PAGE,Thresholds::default(),0,gzip).await.unwrap().response();
   let raw=axum::body::to_bytes(empty.into_body(),usize::MAX).await.unwrap();
   let mut text=Vec::new();
   if gzip {std::io::Read::read_to_end(&mut flate2::read::GzDecoder::new(&raw[..]),&mut text).unwrap();} else {text=raw.to_vec();}
   let got:Value=serde_json::from_slice(&text).unwrap();
   assert_eq!(got["orders"],serde_json::json!([]));
  }
  store::tests::clear(&pool,&[base]).await;
 }

 #[test] fn a_restart_does_not_reset_the_idle_clock() {
  let now=10*store::DAY_MS;
  let hour=3_600_000;
  let recent=vec![("AAA".to_string(),now-23*hour),("BBB".to_string(),now-hour),("CCC".to_string(),now-2*hour)];
  let admit:HashSet<&str>=["AAA","BBB"].into_iter().collect();
  let got=resumable(&recent,&admit,now);
  assert_eq!(got,vec![("AAA",now-23*hour),("BBB",now-hour)],"库里记的时刻原样带回；没放行的不接着跟");
  // 23 小时前要过的：重启后一小时多一点就到 24 小时闲置，照常停，不因为重启再多跟一天。
  assert!(now+hour+1-got[0].1>=IDLE_MS);
  let full:Vec<(String,i64)>=(0..30).map(|i|(format!("B{i}"),now-i)).collect();
  let admit_all:HashSet<&str>=full.iter().map(|(b,_)|b.as_str()).collect();
  assert_eq!(resumable(&full,&admit_all,now).len(),MAX_ON_DEMAND);
 }

 #[test] fn connection_events_take_effect_before_the_frames_sent_after_them() {
  let (control_tx,mut control)=mpsc::unbounded_channel();
  let (frames_tx,mut inbox)=mpsc::channel(4);
  frames_tx.try_send("frame on the old connection").unwrap();
  control_tx.send("opened").unwrap();
  frames_tx.try_send("frame 1 on the new connection").unwrap();
  frames_tx.try_send("frame 2 on the new connection").unwrap();
  let first=inbox.try_recv().unwrap();
  let mut seen=Vec::new();
  in_order(&mut control,first,&mut inbox,|e|seen.push(e));
  assert_eq!(seen,["opened","frame on the old connection","frame 1 on the new connection","frame 2 on the new connection"]);
 }

 #[test] fn unlisted_bases_are_not_tracked() {
  assert!(!admitted(false,Some(false)),"三家都没挂：不跟");
  assert!(admitted(false,Some(true)));
  assert!(admitted(false,None),"表还没拉到：判不了就放行");
  assert!(admitted(true,Some(false)),"已经在跟的（刚下架）照旧");
 }

 #[test] fn page_limit_is_one_to_five_thousand() {
  assert_eq!(page_limit(None),Ok(store::MAX_ROWS),"老请求（手机端）上限照旧");
  assert_eq!(page_limit(Some(1)),Ok(1));
  assert_eq!(page_limit(Some(5_000)),Ok(5_000));
  assert_eq!(page_limit(Some(5_001)),Err("invalid_query"));
  assert_eq!(page_limit(Some(0)),Err("invalid_query"));
  assert_eq!(page_limit(Some(-3)),Err("invalid_query"));
  let now=100*store::DAY_MS;
  assert_eq!(window(None,None,now,PAGED_SPAN_MS),Ok((now-6*3_600_000,now)),"带 limit 的缺省近 6 小时");
  assert_eq!(window(None,Some(now-60_000),now,PAGED_SPAN_MS),Ok((now-60_000-6*3_600_000,now-60_000)),"翻页：to=nextBefore，往前 6 小时");
 }

 #[test] fn min_life_is_zero_to_one_day() {
  assert_eq!(min_life(None),Ok(0));
  assert_eq!(min_life(Some(0)),Ok(0));
  assert_eq!(min_life(Some(300_000)),Ok(300_000));
  assert_eq!(min_life(Some(86_400_000)),Ok(86_400_000));
  assert_eq!(min_life(Some(86_400_001)),Err("invalid_query"));
  assert_eq!(min_life(Some(-1)),Err("invalid_query"));
  assert_eq!(min_life(Some(i64::MIN)),Err("invalid_query"));
 }

 /// 查询串里的 `minLifeMs`：解析不了的、越界的都是 400 `invalid_query`，蛇形名字算多给的参数。
 #[tokio::test] async fn bad_min_life_is_400_invalid_query() {
  use axum::{body::Body,http::{Request,StatusCode}};
  use http_body_util::BodyExt;
  use tower::ServiceExt;
  let app=||Router::<()>::new().route(PATH,get(|Params(q):Params<HistoryQuery>|async move {min_life(q.min_life_ms).map_err(ApiError::bad).map(|v|v.to_string())}));
  for (query,want) in [("base=ETH",Ok("0")),("base=ETH&minLifeMs=0",Ok("0")),("base=ETH&minLifeMs=300000",Ok("300000")),("base=ETH&minLifeMs=86400000",Ok("86400000")),
   ("base=ETH&minLifeMs=86400001",Err("invalid_query")),("base=ETH&minLifeMs=-1",Err("invalid_query")),("base=ETH&minLifeMs=abc",Err("invalid_query")),
   ("base=ETH&minLifeMs=1.5",Err("invalid_query")),("base=ETH&minLifeMs=99999999999999999999",Err("invalid_query")),("base=ETH&min_life_ms=5",Err("invalid_query"))] {
   let reply=app().oneshot(Request::builder().uri(format!("{PATH}?{query}")).body(Body::empty()).unwrap()).await.unwrap();
   let status=reply.status();
   let body=reply.into_body().collect().await.unwrap().to_bytes();
   match want {
    Ok(v)=>{assert_eq!(status,StatusCode::OK,"{query}");assert_eq!(&body[..],v.as_bytes(),"{query}");},
    Err(code)=>{assert_eq!(status,StatusCode::BAD_REQUEST,"{query}");assert_eq!(serde_json::from_slice::<Value>(&body).unwrap()["error"]["code"],code,"{query}");},
   }
  }
 }

 /// 同一来源同时第 25 条起回 429 + Retry-After，别的来源不受影响；前面的做完名额就还回来。
 #[tokio::test] async fn one_source_cannot_hold_more_than_its_share_of_history_reads() {
  use axum::{body::Body,http::{Request,StatusCode}};
  use tower::ServiceExt;
  let (release,wait)=tokio::sync::watch::channel(false);
  let app=Router::<()>::new().route("/slow",get(move||{let mut wait=wait.clone();async move {let _=wait.wait_for(|v|*v).await;"ok"}})).route_layer(axum::middleware::from_fn(per_client));
  let call=|ip:&'static str|{
   let app=app.clone();
   async move {
    let mut req=Request::builder().uri("/slow").header("x-forwarded-for",ip).body(Body::empty()).unwrap();
    req.extensions_mut().insert(axum::extract::ConnectInfo(std::net::SocketAddr::from(([127,0,0,1],9))));
    app.oneshot(req).await.unwrap()
   }
  };
  let held:Vec<_>=(0..PER_CLIENT).map(|_|tokio::spawn(call("203.0.113.7"))).collect();
  while CLIENTS.lock().unwrap().get(&"203.0.113.7".parse().unwrap()).copied()!=Some(PER_CLIENT) {tokio::task::yield_now().await;}
  let over=call("203.0.113.7").await;
  assert_eq!(over.status(),StatusCode::TOO_MANY_REQUESTS);
  assert_eq!(over.headers()["retry-after"],"1");
  let other=tokio::spawn(call("198.51.100.2"));
  release.send(true).unwrap();
  assert_eq!(other.await.unwrap().status(),StatusCode::OK,"别的来源不受影响");
  for h in held {assert_eq!(h.await.unwrap().status(),StatusCode::OK);}
  assert!(!CLIENTS.lock().unwrap().contains_key(&"203.0.113.7".parse().unwrap()),"做完名额还回来、表里不留");
  assert_eq!(call("203.0.113.7").await.status(),StatusCode::OK);
 }

 #[test] fn gzip_is_sent_only_when_accepted() {
  let with=|v:&str|{let mut h=axum::http::HeaderMap::new();h.insert(header::ACCEPT_ENCODING,HeaderValue::from_str(v).unwrap());accepts_gzip(&h)};
  assert!(with("gzip, deflate, br"),"URLSession 的缺省");
  assert!(with("br;q=1.0, GZIP;q=0.5"));
  assert!(with("*"));
  assert!(!with("br"));
  assert!(!with("identity"));
  assert!(!with("gzip;q=0"));
  assert!(!with("gzip;q=0.0, br"));
  assert!(!accepts_gzip(&axum::http::HeaderMap::new()));
 }

 fn answer(tag:u8,len:usize)->Answer {Answer{chunks:vec![axum::body::Bytes::from(vec![tag;len])].into(),len,gzip:true,cache:"no-cache"}}

 #[test] fn keys_merge_within_a_minute_and_read_the_whole_minutes() {
  let a=Key::new("ETH",5*60_000,9*60_000+1,0,true);
  assert_eq!(a,Key::new("ETH",5*60_000+59_999,9*60_000+59_999,0,true),"同一分钟里的起止合成一个键");
  assert_ne!(a,Key::new("ETH",6*60_000,9*60_000,0,true));
  assert_ne!(a,Key::new("ETH",5*60_000,9*60_000,300_000,true),"minLifeMs 不同不混");
  assert_ne!(a,Key::new("ETH",5*60_000,9*60_000,0,false),"原文与 gzip 各一份");
  assert_ne!(a,Key::new("BTC",5*60_000,9*60_000,0,true));
  assert_eq!(a.window(),(5*60_000,9*60_000+59_999),"读的区间是合进来的每个请求的超集");
 }

 /// 两个同样的请求同时到：只读一次库，两个拿到同一份；59 秒内再来的直接回缓存，满 60 秒再读一次。
 #[tokio::test(start_paused=true)] async fn identical_requests_read_the_database_once_for_sixty_seconds() {
  let cache=Answers::new(ANSWER_TTL);
  let reads=AtomicU64::new(0);
  let build=|tag:u8|{let reads=&reads;move||async move {reads.fetch_add(1,Ordering::SeqCst);tokio::time::sleep(Duration::from_millis(200)).await;Ok(answer(tag,10))}};
  let key=||Key::new("ETH",0,86_400_000,0,true);
  let (a,b)=tokio::join!(cache.get_or_build(key(),build(1)),cache.get_or_build(key(),build(2)));
  assert_eq!(reads.load(Ordering::SeqCst),1,"同时到的第二个等第一个的结果");
  assert_eq!((&a.unwrap().chunks[0][..],&b.unwrap().chunks[0][..]),(&[1u8;10][..],&[1u8;10][..]));
  // 答好（读库 200 ms 之后）起算：59.9 秒还是缓存，满 60 秒重读。
  tokio::time::advance(Duration::from_millis(59_900)).await;
  let c=cache.get_or_build(key(),build(3)).await.unwrap();
  assert_eq!((reads.load(Ordering::SeqCst),c.chunks[0][0]),(1,1),"不满 60 秒：缓存");
  tokio::time::advance(Duration::from_millis(100)).await;
  let d=cache.get_or_build(key(),build(4)).await.unwrap();
  assert_eq!((reads.load(Ordering::SeqCst),d.chunks[0][0]),(2,4),"满 60 秒：重读");
  // minLifeMs 不同的不混：各读各的。
  let e=cache.get_or_build(Key::new("ETH",0,86_400_000,300_000,true),build(5)).await.unwrap();
  assert_eq!((reads.load(Ordering::SeqCst),e.chunks[0][0]),(3,5));
  let f=cache.get_or_build(key(),build(6)).await.unwrap();
  assert_eq!((reads.load(Ordering::SeqCst),f.chunks[0][0]),(3,4));
  assert_eq!(cache.cached(),(2,20));
 }

 /// 读库失败不进缓存：等着的和后来的接着自己读；第一个请求被取消（客户端断开）也一样。
 #[tokio::test(start_paused=true)] async fn failures_and_cancelled_reads_are_not_cached() {
  let cache=Answers::new(ANSWER_TTL);
  let key=||Key::new("ETH",0,1,0,true);
  let failed=cache.get_or_build(key(),||async {Err::<Answer,_>(ApiError(axum::http::StatusCode::SERVICE_UNAVAILABLE,"temporarily_unavailable"))}).await;
  assert!(failed.is_err());
  assert_eq!(cache.cached(),(0,0));
  assert!(cache.slots.lock().unwrap().is_empty(),"没人等着的空格清掉");
  let ok=cache.get_or_build(key(),||async {Ok(answer(7,3))}).await.unwrap();
  assert_eq!(ok.chunks[0][0],7);
  let cancelled=tokio::time::timeout(Duration::from_millis(50),cache.get_or_build(Key::new("SOL",0,1,0,true),||async {tokio::time::sleep(Duration::from_secs(5)).await;Ok(answer(8,3))})).await;
  assert!(cancelled.is_err());
  let next=cache.get_or_build(Key::new("SOL",0,1,0,true),||async {Ok(answer(9,3))}).await.unwrap();
  assert_eq!(next.chunks[0][0],9);
 }

 /// 条数最多 64、字节最多 32 MB，超了先扔最久没用的；单份超过 32 MB 的不留。
 #[tokio::test(start_paused=true)] async fn the_cache_is_bounded_and_drops_the_least_recently_used() {
  let cache=Answers::new(ANSWER_TTL);
  let key=|i:i64|Key::new("ETH",i*60_000,i*60_000,0,true);
  for i in 0..70 {cache.get_or_build(key(i),||async {Ok(answer(1,100))}).await.unwrap();}
  assert_eq!(cache.cached(),(ANSWER_ENTRIES,ANSWER_ENTRIES*100));
  assert!(!cache.slots.lock().unwrap().contains_key(&key(5)),"最早的几份先扔");
  assert!(cache.slots.lock().unwrap().contains_key(&key(69)));
  let cache=Answers::new(ANSWER_TTL);
  let mb=1024*1024;
  for i in 0..3 {cache.get_or_build(key(i),||async move {Ok(answer(1,10*mb))}).await.unwrap();}
  assert_eq!(cache.cached(),(3,30*mb));
  // 0 号最早，但刚用过一次（命中，不读）：再进一份超了 32 MB，扔的是 1 号。
  assert_eq!(cache.get_or_build(key(0),||async {Ok(answer(2,1))}).await.unwrap().chunks[0][0],1);
  cache.get_or_build(key(3),||async move {Ok(answer(1,10*mb))}).await.unwrap();
  let kept=|c:&Answers<Key>|->HashSet<i64> {c.slots.lock().unwrap().keys().map(|k|k.from_minute).collect()};
  assert_eq!(kept(&cache),[0,2,3].into_iter().collect());
  assert_eq!(cache.cached(),(3,30*mb));
  let huge=cache.get_or_build(key(9),||async move {Ok(answer(3,33*mb))}).await.unwrap();
  assert_eq!(huge.len,33*mb,"照常回");
  assert_eq!(kept(&cache),[0,2,3].into_iter().collect(),"但不留，也不因为它把别的挤掉");
 }

 #[test] fn window_defaults_and_limits() {
  let now=100*store::DAY_MS;
  assert_eq!(window(None,None,now,store::DAY_MS),Ok((now-store::DAY_MS,now)));
  assert_eq!(window(Some(5),Some(9),now,store::DAY_MS),Ok((5,9)));
  assert_eq!(window(None,Some(now-store::DAY_MS),now,store::DAY_MS),Ok((now-2*store::DAY_MS,now-store::DAY_MS)));
  assert_eq!(window(Some(now-3*store::DAY_MS),None,now,store::DAY_MS),Ok((now-3*store::DAY_MS,now)));
  assert_eq!(window(Some(now-3*store::DAY_MS-1),None,now,store::DAY_MS),Err("range_too_long"));
  assert_eq!(window(Some(9),Some(5),now,store::DAY_MS),Err("invalid_range"));
  assert_eq!(window(Some(-1),Some(5),now,store::DAY_MS),Err("invalid_range"));
  assert_eq!(window(None,Some(i64::MIN),now,store::DAY_MS),Err("invalid_range"),"极端的 to 不溢出");
  assert_eq!(window(Some(0),Some(i64::MAX),now,store::DAY_MS),Err("range_too_long"));
  assert_eq!(window(Some(i64::MAX),None,now,store::DAY_MS),Err("invalid_range"));
 }

 #[test] fn previous_close_prefers_the_utc_day_row() {
  let day=20*store::DAY_MS;
  let rows=serde_json::json!([[day-store::DAY_MS,"0","0","0","90"],[day,"0","0","0","100"],[day+store::DAY_MS,"0","0","0","110"]]);
  assert_eq!(previous_close(&rows,day),Some(100.0));
  let shifted=serde_json::json!([[day-3_600_000,"0","0","0","95"],[day+store::DAY_MS-3_600_000,"0","0","0","105"]]);
  assert_eq!(previous_close(&shifted,day),Some(105.0));
 }

 #[test] fn venue_ids_match_the_phone() {
  let v=Venue{exchange:BINANCE,product:Product::UsdtPerp,instrument:"1000PEPEUSDT".into(),margin:None,
   notional:instruments::Notional::Linear{multiplier:1.0},tick:0.0000001,expiry_ms:None,price_scale:Some(1000),listed_base:"1000PEPE".into()};
  let i=info(&v);
  assert_eq!((i.id.as_str(),i.label,i.price_scale,i.in_band),("binance:usdtPerp:1000PEPEUSDT","币安",1000.0,false));
  assert_eq!(i.sequence,Sequence::PreviousFinalOverlap);
  let v=Venue{exchange:COINBASE,product:Product::Spot,instrument:"BTC-USD".into(),margin:None,
   notional:instruments::Notional::Linear{multiplier:1.0},tick:0.01,expiry_ms:None,price_scale:None,listed_base:"BTC".into()};
  assert_eq!(info(&v).id,"coinbase:spot:BTC-USD");
 }

 #[test] fn bybit_spot_is_the_first_thing_shed() {
  use crate::venues::orderflow::tests::{NOW,all};
  let rows=instruments::pick(&all(),"BTC",NOW);
  let has=|rows:&[Venue]|rows.iter().any(bybit_spot);
  let full=tracked_with(rows.clone(),false);
  assert!(has(&full));
  let shed=tracked_with(rows.clone(),true);
  assert!(!has(&shed),"卸下时品种表里不再有 Bybit 现货");
  assert_eq!(shed.len()+full.iter().filter(|v|bybit_spot(v)).count(),full.len(),"别的一本不少");
  assert_eq!((shed_label(0),shed_label(1),shed_label(2)),("nothing","bybit-spot","bybit-spot+hot"));
 }

 #[test] fn btc_is_tracked_on_all_five_exchanges() {
  use crate::venues::orderflow::tests::{NOW,all};
  let rows=tracked(instruments::pick(&all(),"BTC",NOW));
  let infos:Vec<VenueInfo>=rows.iter().map(info).collect();
  let exchanges:HashSet<&str>=infos.iter().map(|i|i.exchange).collect();
  assert_eq!(exchanges,HashSet::from(["binance","okx","coinbase","bybit","hyperliquid"]));
  let labels:HashSet<&str>=infos.iter().map(|i|i.label).collect();
  assert_eq!(labels,HashSet::from(["币安","OKX","Coinbase","Bybit","Hyperliquid"]),"大单历史里的交易所名");
  // Bybit 三类都在：现货、U 本位（linear）、币本位（inverse），各自走自己那种连接。
  let bybit:HashSet<feeds::Kind>=infos.iter().filter(|i|i.exchange=="bybit").flat_map(|i|feeds::kinds_of(i).iter().copied()).collect();
  assert_eq!(bybit,HashSet::from([feeds::Kind::BybitSpot,feeds::Kind::BybitLinear,feeds::Kind::BybitInverse]));
  let hl=infos.iter().find(|i|i.exchange=="hyperliquid").unwrap();
  assert_eq!((hl.id.as_str(),hl.sequence,hl.in_band,hl.sliding),("hyperliquid:usdtPerp:BTC",Sequence::SnapshotOnly,true,true));
  assert_eq!(feeds::kinds_of(hl),&[feeds::Kind::Hyperliquid]);
  let by=infos.iter().find(|i|i.id=="bybit:usdtPerp:BTCUSDT").unwrap();
  assert_eq!((by.sequence,by.in_band,by.sliding),(Sequence::StrictIncrementing,true,true));
 }
}
