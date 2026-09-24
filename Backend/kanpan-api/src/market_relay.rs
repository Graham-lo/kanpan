//! 行情中继：两条 WebSocket，把手机连不上的公共行情流经这台 VPS 转一手。
//!
//! * `GET /v1/market/ws/binance?streams=a/b/c`：服务端按产品把这些流分到币安合约的上游，各条上游的
//!   文本帧原样转给手机（组合流的帧自带 `stream` 字段，手机按它分发）：
//!   - 币本位（流名的品种部分含 `usd_`，如 `btcusd_perp`、`btcusd_260925`）→ `wss://dstream.binance.com/stream`；
//!   - U 本位的 `@depth@100ms` → `wss://fstream.binance.com/public/stream`；
//!   - U 本位的 `@aggTrade` → `wss://fstream.binance.com/market/stream`。
//!
//!   所以一条中继按流名拆成最多三条上游：用到的几条全部连上才答 101；任一条断开或沉默，
//!   整条中继（连同手机那头）一起断，手机重连——不存在「深度还在、成交已经断了」的半条中继。
//! * `GET /v1/market/ws/okx`：服务端连 `wss://ws.okx.com:8443/ws/v5/public`，上游帧原样转给手机
//!   （包括 OKX 的文本 `pong`）。手机在国内直连不了 OKX。
//!
//! 为什么这样分（2026-09-24 在 VPS 上实测，每组 12 秒、各两轮；对照币安官方「Important WebSocket
//! Change Notice」与 USDⓈ-M / COIN-M 两份 Websocket Market Streams 文档）：
//! * U 本位合约的 WS 已按数据类型拆了路由：盘口类（depth / bookTicker）只走 `/public`，aggTrade /
//!   markPrice 这类只走 `/market`，不带路由的旧地址 2026-04-23 起下线。实测 `fstream …/public/stream`
//!   上 U 本位深度 101 约 520 ms、首帧 550–610 ms，12 秒 `btcusdt@depth@100ms` 113–114 帧；
//!   `fstream …/market/stream` 上 aggTrade 101 约 510 ms、12 秒 `btcusdt@aggTrade` 90–123 帧。
//!   深度与成交混在一条 `/market` 上只到成交、混在一条 `/public` 上只到深度；不带路由的 `fstream …/stream`
//!   只到深度、一笔成交都没有。
//! * 币本位只有 `dstream.binance.com/stream` 一个入口、没有分路由：实测深度与 `btcusd_perp@aggTrade`
//!   都到，101 约 555 ms、首帧 600–650 ms。fstream 上订币本位同样只有深度没有成交。
//! * 这里以前让一条 dstream 连接同时带 U 本位与币本位。实测它当下确实也推 U 本位，但 dstream 是币本位的
//!   入口，按官方文档 U 本位属于 fstream，靠一条未文档化的行为吃饭迟早出事，所以按产品分开。
//!
//! **绝对不许换成 `*.binancefuture.com`**——那是测试网。
//!
//! 规矩：
//! * 流名白名单：每个都要是 `^[a-z0-9_]{2,40}@(depth@100ms|aggTrade)$`，最多 8 个，
//!   不合规直接 400，不升级。
//! * OKX 那条：手机发上来的文本帧只放行字面量 `ping`，或
//!   `{"op":"subscribe"|"unsubscribe","args":[{"channel":"books"|"trades","instId":"…"}…]}`
//!   （args 1–12 个，instId 要是 `^[A-Z0-9]{1,20}-(USDT|USD|USDC)(-SWAP|-[0-9]{6})?$`）；
//!   其他帧丢掉（不转、不断开）。一条连接同时订着的 (channel, instId) 最多
//!   `MAX_OKX_SUBSCRIPTIONS` 个，超了的那条订阅也丢掉。币安那条上手机发的文本帧一律丢掉
//!   ——组合流的地址就是订阅，不许再在连接里 SUBSCRIBE 别的。
//! * 任一端断开就全部关掉。上游的 ping 由 tungstenite 自动回；对手机每 20 秒发一次 ping；
//!   币安的每条上游也每 20 秒 ping 一次，回来的 pong 算「它还活着」——冷门交割合约一分钟可能一笔
//!   成交都没有，只订成交的那条上游不能因为没有数据帧就被当成死了（实测 `btcusdt_261225@aggTrade`
//!   4 秒 0 帧；三个入口对 ping 都在 130–190 ms 内回 pong）。任一条上游 60 秒没有任何帧
//!   （连 pong 都没有）就断（手机会重连）；手机 90 秒没有任何帧（连 pong 都没有）也断，免得死在半路的
//!   手机一直占着上游；往任一端发一帧 10 秒发不出去也断。
//! * 同一来源地址同时在跑的中继（两条加起来）最多 `MAX_RELAYS_PER_CLIENT` 条（16：一个家庭网络 /
//!   运营商 NAT 后面几台设备的量），超了 429 +
//!   `Retry-After`；整个进程最多 `MAX_RELAYS` 条，超了 503。来源地址用 `auth::client_ip` 取：对端是
//!   本机（前面的 Caddy）时认 `X-Forwarded-For`，否则就是对端地址。一个人开满不会把别人挤掉。
//! * 不登录：行情是公开数据，和其它 `/v1/market/*` 一样。
//! * 先连上游再答 101：上游连不上时手机拿到的是 503 + `Retry-After: 2`，而不是一条升级成功
//!   却马上被关掉的连接。币安每条上游出站之前先看 `binance_gate`，这个出口被封着就不去敲门，
//!   握手被 429 / 418 顶回来也记进那道闸。
use crate::{AppState,binance_gate,error::{ApiError,Params}};
use axum::Router;
use axum::extract::{ConnectInfo,FromRequestParts};
use axum::extract::ws::{CloseFrame,Message as Down,WebSocket,WebSocketUpgrade,rejection::WebSocketUpgradeRejection};
use axum::http::{HeaderValue,StatusCode,header,request::Parts};
use axum::response::{IntoResponse,Response};
use axum::routing::get;
use futures_util::{SinkExt,StreamExt};
use serde::Deserialize;
use std::collections::{HashMap,HashSet};
use std::net::{IpAddr,Ipv4Addr,SocketAddr};
use std::sync::{Arc,Mutex,OnceLock};
use std::time::Duration;
use tokio::sync::{OwnedSemaphorePermit,Semaphore};
use tokio::time::Instant;
use tokio_tungstenite::tungstenite::{self,Message as Up};

const BINANCE_PATH:&str="/v1/market/ws/binance";
const OKX_PATH:&str="/v1/market/ws/okx";
/// 币本位合约（永续与交割）的组合流入口。
const BINANCE_COIN_M:&str="wss://dstream.binance.com/stream";
/// U 本位合约的盘口类组合流（depth）。
const BINANCE_USDM_PUBLIC:&str="wss://fstream.binance.com/public/stream";
/// U 本位合约的成交 / 标记价格类组合流（aggTrade）。
const BINANCE_USDM_MARKET:&str="wss://fstream.binance.com/market/stream";
const OKX_UPSTREAM:&str="wss://ws.okx.com:8443/ws/v5/public";

/// 整个进程同时在跑的中继连接数上限（两条中继合计）。3 位朋友、上限约 10 人，一人开一只币
/// 最多三条，64 条是两倍的余量；再多就是有人在拿它当免费代理。
const MAX_RELAYS:usize=64;
/// 同一来源地址同时在跑的中继上限（两条中继合计）。一台设备看一只币：币安 U 本位 + 币本位各一条
/// （合约多的币 U 本位可能拆两条）+ OKX 一条 = 3–4 条，换币时旧连接还没关干净再多一条。同一个来源
/// 地址后面常常不止一台：手机 + 平板在同一个家庭网络，国内手机网络还有运营商 NAT，几台设备
/// 共用一个出口。给到 16 = 四台设备满打满算，仍只是总数 64 的四分之一，一个出口开满挤不掉别人。
const MAX_RELAYS_PER_CLIENT:usize=16;
/// 币安一条中继最多几路流。一只币的合约侧：U 本位永续 + 两个 U 本位交割 + 币本位永续 + 两个币本位交割，
/// 每个要 depth 与 aggTrade——手机按需分两条连，每条不超过 8 路。
pub const MAX_STREAMS:usize=8;
/// OKX 一条订阅消息里最多几个 args。
pub const MAX_OKX_ARGS:usize=12;
/// OKX 一条连接同时订着的 (channel, instId) 最多几个。一只币：现货、U 本位永续、币本位永续、
/// 两个交割，各 books + trades = 10 个，给到 24。
pub const MAX_OKX_SUBSCRIPTIONS:usize=24;
const RETRY_AFTER:&str="2";

#[derive(Clone,Copy,Debug)]
struct Timing {
 /// 连上游（TCP + TLS + WS 握手）最多等多久。
 connect:Duration,
 /// 多久对手机（以及币安的每条上游）发一次 ping。
 ping:Duration,
 /// 任一条上游多久没有任何帧（含 pong）就断。
 upstream_idle:Duration,
 /// 手机多久没有任何帧（含 pong）就断。
 client_idle:Duration,
 /// 往任一端发一帧最多等多久。
 send:Duration,
}
const TIMING:Timing=Timing{
 connect:Duration::from_secs(10),
 ping:Duration::from_secs(20),
 upstream_idle:Duration::from_secs(60),
 client_idle:Duration::from_secs(90),
 send:Duration::from_secs(10),
};

/// 币安的一路流该走哪条上游。
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum Lane {
 /// 币本位（永续与交割）：dstream。
 CoinM,
 /// U 本位的深度：fstream `/public`。
 UsdmDepth,
 /// U 本位的成交：fstream `/market`。
 UsdmTrades,
}
impl Lane {
 const ALL:[Lane;3]=[Lane::CoinM,Lane::UsdmDepth,Lane::UsdmTrades];
 /// 一路（已经过白名单的）流名归哪条上游：品种部分含 `usd_` 的是币本位（`btcusd_perp`、
 /// `btcusd_260925`；U 本位交割是 `btcusdt_261225`，含的是 `usdt_`），其余是 U 本位，再按深度 / 成交分。
 pub fn of(stream:&str)->Self {
  let (symbol,kind)=stream.split_once('@').unwrap_or((stream,""));
  if symbol.contains("usd_") {Self::CoinM} else if kind=="aggTrade" {Self::UsdmTrades} else {Self::UsdmDepth}
 }
}

/// 流名清单按上游分组：顺序固定（币本位、U 本位深度、U 本位成交），组内保持原顺序，没有流的组不出现。
pub fn binance_lanes(streams:&[String])->Vec<(Lane,Vec<String>)> {
 Lane::ALL.into_iter().filter_map(|lane|{
  let group:Vec<String>=streams.iter().filter(|s|Lane::of(s)==lane).cloned().collect();
  (!group.is_empty()).then_some((lane,group))
 }).collect()
}

/// 币安三条上游的地址（测试里换成本机假上游）。
#[derive(Clone,Debug)]
struct BinanceUpstreams {coin_m:String,usdm_depth:String,usdm_trades:String}
impl BinanceUpstreams {
 fn url(&self,lane:Lane)->&str {
  match lane {Lane::CoinM=>&self.coin_m,Lane::UsdmDepth=>&self.usdm_depth,Lane::UsdmTrades=>&self.usdm_trades}
 }
}

type Clients=Arc<Mutex<HashMap<IpAddr,usize>>>;

pub struct Relay {
 binance:BinanceUpstreams,
 okx:String,
 permits:Arc<Semaphore>,
 per_client:usize,
 clients:Clients,
 timing:Timing,
}

impl Relay {
 fn new(binance:BinanceUpstreams,okx:impl Into<String>,max:usize,per_client:usize,timing:Timing)->Self {
  Self{binance,okx:okx.into(),permits:Arc::new(Semaphore::new(max)),per_client,clients:Clients::default(),timing}
 }
 /// 给这个来源占一个名额；满了就是 `None`。
 fn admit(&self,ip:IpAddr)->Option<ClientSlot> {
  let mut clients=self.clients.lock().unwrap_or_else(|e|e.into_inner());
  let count=clients.entry(ip).or_insert(0);
  if *count>=self.per_client {return None}
  *count+=1;
  Some(ClientSlot{clients:self.clients.clone(),ip})
 }
}

/// 一个来源占着的一个名额；中继结束（这个值被丢掉）时还回去。
struct ClientSlot {clients:Clients,ip:IpAddr}
impl Drop for ClientSlot {
 fn drop(&mut self) {
  let mut clients=self.clients.lock().unwrap_or_else(|e|e.into_inner());
  if let Some(count)=clients.get_mut(&self.ip) {
   *count=count.saturating_sub(1);
   if *count==0 {clients.remove(&self.ip);}
  }
 }
}

/// 一条中继占着的两份名额，活多久占多久。
struct Held {_permit:OwnedSemaphorePermit,_slot:ClientSlot}

/// 这条请求的来源地址，规则见 `auth::client_ip`。拿不到对端地址（只有不带连接信息的测试会这样）
/// 就当 `0.0.0.0`：不是本机，转发头一律不信。
struct Source(IpAddr);
impl<S:Send+Sync> FromRequestParts<S> for Source {
 type Rejection=std::convert::Infallible;
 async fn from_request_parts(parts:&mut Parts,_:&S)->Result<Self,Self::Rejection> {
  let peer=parts.extensions.get::<ConnectInfo<SocketAddr>>().map(|c|c.0).unwrap_or(SocketAddr::from((Ipv4Addr::UNSPECIFIED,0)));
  Ok(Self(crate::auth::client_ip(&peer,&parts.headers)))
 }
}
// ------------------------------------------------------------------ 白名单

fn lower_symbol(s:&str)->bool {(2..=40).contains(&s.len())&&s.bytes().all(|b|b.is_ascii_lowercase()||b.is_ascii_digit()||b==b'_')}

/// 一路币安流名合不合规：`^[a-z0-9_]{2,40}@(depth@100ms|aggTrade)$`。
pub fn valid_binance_stream(stream:&str)->bool {
 let Some((symbol,kind))=stream.split_once('@') else {return false};
 lower_symbol(symbol)&&matches!(kind,"depth@100ms"|"aggTrade")
}

/// `streams` 参数 → 去重后的流名清单；有一路不合规、一路都没有、或超过 8 路就是 `None`。
pub fn binance_streams(raw:&str)->Option<Vec<String>> {
 let parts:Vec<&str>=raw.split('/').collect();
 if parts.len()>MAX_STREAMS {return None}
 let mut out:Vec<String>=Vec::with_capacity(parts.len());
 for part in parts {
  if !valid_binance_stream(part) {return None}
  if !out.iter().any(|s|s==part) {out.push(part.to_owned());}
 }
 Some(out)
}

/// OKX 的 instId：`^[A-Z0-9]{1,20}-(USDT|USD|USDC)(-SWAP|-[0-9]{6})?$`。
pub fn valid_okx_inst(inst:&str)->bool {
 let mut parts=inst.split('-');
 let (Some(base),Some(quote))=(parts.next(),parts.next()) else {return false};
 let tail=parts.next();
 if parts.next().is_some() {return false}
 (1..=20).contains(&base.len())&&base.bytes().all(|b|b.is_ascii_uppercase()||b.is_ascii_digit())
  &&matches!(quote,"USDT"|"USD"|"USDC")
  &&tail.is_none_or(|t|t=="SWAP"||(t.len()==6&&t.bytes().all(|b|b.is_ascii_digit())))
}

#[derive(Clone,Copy,Debug,PartialEq,Eq,Hash,Deserialize)]
#[serde(rename_all="lowercase")]
pub enum OkxOp {Subscribe,Unsubscribe}
#[derive(Clone,Copy,Debug,PartialEq,Eq,Hash,Deserialize)]
#[serde(rename_all="lowercase")]
pub enum OkxChannel {Books,Trades}
impl OkxChannel {fn name(self)->&'static str {match self {Self::Books=>"books",Self::Trades=>"trades"}}}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct OkxArg {channel:OkxChannel,#[serde(rename="instId")] inst_id:String}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct OkxRequest {op:OkxOp,args:Vec<OkxArg>}

/// 手机发上来的一帧，放行之后长什么样。
#[derive(Clone,Debug,PartialEq,Eq)]
pub enum OkxUpward {
 /// 字面量 `ping`。
 Ping,
 /// 一条订阅 / 退订。
 Request {op:OkxOp,args:Vec<(OkxChannel,String)>},
}
impl OkxUpward {
 /// 发给上游的文本。订阅按放行后的字段重新拼，手机写进去的别的东西一个字也带不过去。
 fn text(&self)->String {
  match self {
   Self::Ping=>"ping".to_owned(),
   Self::Request{op,args}=>serde_json::json!({
    "op":match op {OkxOp::Subscribe=>"subscribe",OkxOp::Unsubscribe=>"unsubscribe"},
    "args":args.iter().map(|(channel,inst)|serde_json::json!({"channel":channel.name(),"instId":inst})).collect::<Vec<_>>(),
   }).to_string(),
  }
 }
}

/// 手机发上来的一帧该不该放行；不放行就是 `None`（丢掉，不断开）。
pub fn okx_upward(text:&str)->Option<OkxUpward> {
 if text=="ping" {return Some(OkxUpward::Ping)}
 let request:OkxRequest=serde_json::from_str(text).ok()?;
 if request.args.is_empty()||request.args.len()>MAX_OKX_ARGS {return None}
 if !request.args.iter().all(|a|valid_okx_inst(&a.inst_id)) {return None}
 Some(OkxUpward::Request{op:request.op,args:request.args.into_iter().map(|a|(a.channel,a.inst_id)).collect()})
}

/// 一条 OKX 连接上正订着的东西，用来卡「同时订着最多几个」。
#[derive(Default)]
pub struct OkxSubscriptions {live:HashSet<(OkxChannel,String)>}
impl OkxSubscriptions {
 /// 这一帧能不能转上去；能转的话顺手记账。超了上限的订阅整条丢掉，账不动。
 pub fn admit(&mut self,frame:&OkxUpward)->bool {
  match frame {
   OkxUpward::Ping=>true,
   OkxUpward::Request{op:OkxOp::Unsubscribe,args}=>{
    for (channel,inst) in args {self.live.remove(&(*channel,inst.clone()));}
    true
   },
   OkxUpward::Request{op:OkxOp::Subscribe,args}=>{
    let fresh:HashSet<(OkxChannel,String)>=args.iter().filter(|a|!self.live.contains(*a)).cloned().collect();
    if self.live.len()+fresh.len()>MAX_OKX_SUBSCRIPTIONS {return false}
    self.live.extend(fresh);
    true
   },
  }
 }
}

// ------------------------------------------------------------------ 连接与转发

type Upstream=tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

#[derive(Clone,Copy,Debug,PartialEq,Eq)]
enum Kind {Binance,Okx}

fn refuse(status:StatusCode,code:&'static str)->Response {
 let mut reply=ApiError(status,code).into_response();
 reply.headers_mut().insert(header::RETRY_AFTER,HeaderValue::from_static(RETRY_AFTER));
 reply
}
fn unavailable(code:&'static str)->Response {refuse(StatusCode::SERVICE_UNAVAILABLE,code)}

async fn connect(url:&str,kind:Kind,timing:Timing)->Result<Upstream,Response> {
 if kind==Kind::Binance&&binance_gate::blocked() {return Err(unavailable("market_upstream_unavailable"))}
 match tokio::time::timeout(timing.connect,tokio_tungstenite::connect_async(url)).await {
  Ok(Ok((stream,_)))=>Ok(stream),
  Ok(Err(tungstenite::Error::Http(reply)))=>{
   let status=reply.status().as_u16();
   if kind==Kind::Binance {
    let retry=reply.headers().get("retry-after").and_then(|v|v.to_str().ok());
    binance_gate::note(status,retry);
   }
   tracing::warn!("Market relay: {kind:?} upstream refused the handshake with {status}");
   Err(unavailable("market_upstream_unavailable"))
  },
  Ok(Err(e))=>{tracing::warn!("Market relay: {kind:?} upstream unreachable: {e}");Err(unavailable("market_upstream_unavailable"))},
  Err(_)=>{tracing::warn!("Market relay: {kind:?} upstream handshake timed out");Err(unavailable("market_upstream_unavailable"))},
 }
}

/// 同时连一条中继要的全部上游；有一条连不上就整条 503（已经连上的随之丢掉、关闭）。
async fn connect_all(urls:&[String],kind:Kind,timing:Timing)->Result<Vec<Upstream>,Response> {
 futures_util::future::try_join_all(urls.iter().map(|url|connect(url,kind,timing))).await
}

/// 为什么结束。只用于日志。
#[derive(Debug)]
enum End {ClientLeft,ClientSilent,ClientStuck,UpstreamClosed,UpstreamSilent,UpstreamStuck}

/// 给每条上游发一帧；有一条 `send` 之内发不出去就是 `false`。
async fn send_all(sinks:&mut [futures_util::stream::SplitSink<Upstream,Up>],frame:Up,send:Duration)->bool {
 for sink in sinks.iter_mut() {
  if !matches!(tokio::time::timeout(send,sink.send(frame.clone())).await,Ok(Ok(()))) {return false}
 }
 true
}

/// 一条中继的一生：上游（一条或几条）往手机搬，OKX 那条再把手机放行的帧搬上去，
/// 直到任一端断开或沉默。
async fn pump(client:WebSocket,upstreams:Vec<Upstream>,kind:Kind,timing:Timing,_held:Held) {
 let (mut down_tx,mut down_rx)=client.split();
 let mut up_txs=Vec::with_capacity(upstreams.len());
 let mut reads=Vec::with_capacity(upstreams.len());
 for (index,upstream) in upstreams.into_iter().enumerate() {
  let (tx,rx)=upstream.split();
  up_txs.push(tx);
  // 每条上游读完（断开）时补一个 `None`：几条合在一起读，任一条走到头整条中继就结束，
  // 而不是等到最后一条也断了才发现。
  reads.push(rx.map(move|frame|(index,Some(frame))).chain(futures_util::stream::once(async move {(index,None)})).boxed());
 }
 let mut up_rx=futures_util::stream::select_all(reads);
 let mut ping=tokio::time::interval_at(Instant::now()+timing.ping,timing.ping);
 let mut upstream_deadlines=vec![Instant::now()+timing.upstream_idle;up_txs.len()];
 let mut client_deadline=Instant::now()+timing.client_idle;
 let mut subscriptions=OkxSubscriptions::default();
 let end=loop {
  let upstream_deadline=upstream_deadlines.iter().min().copied().unwrap_or(client_deadline);
  tokio::select! {
   frame=up_rx.next()=>{
    let (index,message)=match frame {
     Some((index,Some(Ok(message))))=>(index,message),
     _=>break End::UpstreamClosed,
    };
    upstream_deadlines[index]=Instant::now()+timing.upstream_idle;
    let out=match message {
     Up::Text(text)=>Down::Text(text.as_str().into()),
     Up::Binary(bytes)=>Down::Binary(bytes),
     Up::Close(_)=>break End::UpstreamClosed,
     // ping 由 tungstenite 在读的时候自动回 pong；pong（包括我们 ping 币安换回来的）只用来续期限，
     // 与原始帧一样不用转。
     Up::Ping(_)|Up::Pong(_)|Up::Frame(_)=>continue,
    };
    if !matches!(tokio::time::timeout(timing.send,down_tx.send(out)).await,Ok(Ok(()))) {break End::ClientStuck}
   },
   frame=down_rx.next()=>{
    let message=match frame {
     Some(Ok(message))=>message,
     Some(Err(_))|None=>break End::ClientLeft,
    };
    client_deadline=Instant::now()+timing.client_idle;
    let text=match message {
     Down::Text(text)=>text,
     Down::Close(_)=>break End::ClientLeft,
     _=>continue,
    };
    // 币安那条：组合流的地址就是订阅，连接里发什么都不转。
    if kind!=Kind::Okx {continue}
    let Some(frame)=okx_upward(text.as_str()) else {continue};
    if !subscriptions.admit(&frame) {continue}
    if !send_all(&mut up_txs,Up::Text(frame.text().into()),timing.send).await {break End::UpstreamStuck}
   },
   _=ping.tick()=>{
    if !matches!(tokio::time::timeout(timing.send,down_tx.send(Down::Ping(Default::default()))).await,Ok(Ok(()))) {break End::ClientStuck}
    // 币安的上游也 ping 一下：只订了冷门成交的那条可能一分钟没有数据帧，靠 pong 证明它还活着。
    // OKX 那条由手机自己发文本 `ping` 保活，照旧。
    if kind==Kind::Binance&&!send_all(&mut up_txs,Up::Ping(Default::default()),timing.send).await {break End::UpstreamStuck}
   },
   _=tokio::time::sleep_until(upstream_deadline)=>break End::UpstreamSilent,
   _=tokio::time::sleep_until(client_deadline)=>break End::ClientSilent,
  }
 };
 tracing::debug!("Market relay: {kind:?} ended: {end:?}");
 // 全部关掉。发不出去就算了，别让收尾本身卡住这个任务。
 let farewell=match end {
  End::ClientLeft|End::ClientSilent|End::ClientStuck=>None,
  _=>Some(CloseFrame{code:1013,reason:"upstream".into()}),
 };
 if let Some(frame)=farewell {let _=tokio::time::timeout(Duration::from_secs(1),down_tx.send(Down::Close(Some(frame)))).await;}
 let _=tokio::time::timeout(Duration::from_secs(1),down_tx.close()).await;
 futures_util::future::join_all(up_txs.iter_mut().map(|tx|tokio::time::timeout(Duration::from_secs(1),tx.close()))).await;
}

/// 两条中继共用的开门流程：要升级、占这个来源的名额、占全局名额、连上游、再答 101。
async fn open(relay:&Relay,kind:Kind,Source(ip):Source,urls:Vec<String>,ws:Result<WebSocketUpgrade,WebSocketUpgradeRejection>)->Response {
 let Ok(ws)=ws else {return ApiError::bad("websocket_required").into_response()};
 let Some(slot)=relay.admit(ip) else {
  tracing::info!("Market relay: {ip} already holds {} relays",relay.per_client);
  return refuse(StatusCode::TOO_MANY_REQUESTS,"relay_client_limit");
 };
 let Ok(permit)=relay.permits.clone().try_acquire_owned() else {return unavailable("relay_busy")};
 let upstreams=match connect_all(&urls,kind,relay.timing).await {Ok(streams)=>streams,Err(reply)=>return reply};
 let timing=relay.timing;
 let held=Held{_permit:permit,_slot:slot};
 ws.on_upgrade(move|client|pump(client,upstreams,kind,timing,held))
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct StreamsQuery {streams:String}

async fn binance(relay:Arc<Relay>,source:Source,query:StreamsQuery,ws:Result<WebSocketUpgrade,WebSocketUpgradeRejection>)->Response {
 let Some(streams)=binance_streams(&query.streams) else {return ApiError::bad("invalid_streams").into_response()};
 let urls=binance_lanes(&streams).into_iter().map(|(lane,group)|format!("{}?streams={}",relay.binance.url(lane),group.join("/"))).collect();
 open(&relay,Kind::Binance,source,urls,ws).await
}

async fn okx(relay:Arc<Relay>,source:Source,ws:Result<WebSocketUpgrade,WebSocketUpgradeRejection>)->Response {
 let urls=vec![relay.okx.clone()];
 open(&relay,Kind::Okx,source,urls,ws).await
}

fn routes_with<S:Clone+Send+Sync+'static>(relay:Arc<Relay>)->Router<S> {
 let for_okx=relay.clone();
 Router::new()
  .route(BINANCE_PATH,get(move|source:Source,Params(query):Params<StreamsQuery>,ws:Result<WebSocketUpgrade,WebSocketUpgradeRejection>| {
   let relay=relay.clone();
   async move {binance(relay,source,query,ws).await}
  }))
  .route(OKX_PATH,get(move|source:Source,ws:Result<WebSocketUpgrade,WebSocketUpgradeRejection>| {
   let relay=for_okx.clone();
   async move {okx(relay,source,ws).await}
  }))
}

fn shared()->Arc<Relay> {
 static R:OnceLock<Arc<Relay>>=OnceLock::new();
 R.get_or_init(||{
  let binance=BinanceUpstreams{coin_m:BINANCE_COIN_M.into(),usdm_depth:BINANCE_USDM_PUBLIC.into(),usdm_trades:BINANCE_USDM_MARKET.into()};
  Arc::new(Relay::new(binance,OKX_UPSTREAM,MAX_RELAYS,MAX_RELAYS_PER_CLIENT,TIMING))
 }).clone()
}
pub fn routes()->Router<AppState> {routes_with(shared())}

#[cfg(test)]
mod tests {
 use super::*;
 use axum::body::Body;
 use axum::extract::RawQuery;
 use axum::http::Request;
 use http_body_util::BodyExt;
 use tower::ServiceExt;

 #[test]
 fn binance_stream_names() {
  for good in ["btcusdt@depth@100ms","btcusdt@aggTrade","btcusd_perp@depth@100ms","btcusd_260925@aggTrade","btcusdt_261225@depth@100ms","1000pepeusdt@aggTrade"] {
   assert!(valid_binance_stream(good),"{good}");
  }
  for bad in ["","btcusdt","BTCUSDT@aggTrade","btcusdt@depth","btcusdt@depth@500ms","btcusdt@depth20@100ms","btcusdt@kline_1m","btcusdt@aggtrade",
   "b@aggTrade","@aggTrade",&format!("{}@aggTrade","a".repeat(41)),"btc-usdt@aggTrade","btcusdt@aggTrade ","btcusdt@aggTrade@x","!miniTicker@arr","btcusdt@forceOrder"] {
   assert!(!valid_binance_stream(bad),"{bad}");
  }
  assert_eq!(binance_streams("btcusdt@aggTrade/btcusd_perp@depth@100ms"),Some(vec!["btcusdt@aggTrade".to_owned(),"btcusd_perp@depth@100ms".to_owned()]));
  assert_eq!(binance_streams("btcusdt@aggTrade/btcusdt@aggTrade"),Some(vec!["btcusdt@aggTrade".to_owned()]),"重复的去掉");
  let eight=(0..8).map(|i|format!("s{i}usdt@aggTrade")).collect::<Vec<_>>().join("/");
  assert_eq!(binance_streams(&eight).map(|v|v.len()),Some(8));
  let nine=(0..9).map(|i|format!("s{i}usdt@aggTrade")).collect::<Vec<_>>().join("/");
  assert_eq!(binance_streams(&nine),None,"最多 8 路");
  assert_eq!(binance_streams(""),None);
  assert_eq!(binance_streams("btcusdt@aggTrade/"),None);
  assert_eq!(binance_streams("btcusdt@aggTrade/btcusdt@kline_1m"),None,"有一路不合规整条拒");
 }

 #[test]
 fn binance_streams_are_split_by_product() {
  for (stream,lane) in [
   ("btcusdt@depth@100ms",Lane::UsdmDepth),("btcusdt_261225@depth@100ms",Lane::UsdmDepth),("1000pepeusdt@depth@100ms",Lane::UsdmDepth),("btcusdc@depth@100ms",Lane::UsdmDepth),
   ("btcusdt@aggTrade",Lane::UsdmTrades),("btcusdt_260925@aggTrade",Lane::UsdmTrades),
   ("btcusd_perp@depth@100ms",Lane::CoinM),("btcusd_perp@aggTrade",Lane::CoinM),("btcusd_261225@depth@100ms",Lane::CoinM),("ethusd_260925@aggTrade",Lane::CoinM),
  ] {
   assert_eq!(Lane::of(stream),lane,"{stream}");
  }
  let streams:Vec<String>=["btcusdt@aggTrade","btcusd_perp@depth@100ms","btcusdt@depth@100ms","btcusd_perp@aggTrade","btcusdt_261225@depth@100ms"].map(String::from).into();
  let v=|l:&[&str]|l.iter().map(|s|s.to_string()).collect::<Vec<_>>();
  assert_eq!(binance_lanes(&streams),vec![
   (Lane::CoinM,v(&["btcusd_perp@depth@100ms","btcusd_perp@aggTrade"])),
   (Lane::UsdmDepth,v(&["btcusdt@depth@100ms","btcusdt_261225@depth@100ms"])),
   (Lane::UsdmTrades,v(&["btcusdt@aggTrade"])),
  ],"三组、顺序固定、组内保持原顺序");
  assert_eq!(binance_lanes(&v(&["btcusdt@depth@100ms"])),vec![(Lane::UsdmDepth,v(&["btcusdt@depth@100ms"]))],"用不到的上游不连");
 }

 #[test]
 fn okx_inst_ids() {
  for good in ["BTC-USDT","BTC-USD","BTC-USDC","BTC-USDT-SWAP","BTC-USD-SWAP","BTC-USD-260925","BTC-USDT-261225","1INCH-USDT","ABCDEFGHIJKLMNOPQRST-USDT"] {
   assert!(valid_okx_inst(good),"{good}");
  }
  for bad in ["","BTC","btc-usdt","BTC-EUR","BTC-USDT-swap","BTC-USD-2609","BTC-USD-2609250","BTC-USD_UM-261225","BTC-USD-SWAP-X","-USDT","BTC--USDT",
   "ABCDEFGHIJKLMNOPQRSTU-USDT","BTC-USDT-SWAP ","BTC-USD-26092A"] {
   assert!(!valid_okx_inst(bad),"{bad}");
  }
 }

 #[test]
 fn okx_upward_frames() {
  assert_eq!(okx_upward("ping"),Some(OkxUpward::Ping));
  let sub=okx_upward(r#"{"op":"subscribe","args":[{"channel":"books","instId":"BTC-USDT"},{"channel":"trades","instId":"BTC-USD-SWAP"}]}"#).unwrap();
  assert_eq!(sub,OkxUpward::Request{op:OkxOp::Subscribe,args:vec![(OkxChannel::Books,"BTC-USDT".into()),(OkxChannel::Trades,"BTC-USD-SWAP".into())]});
  assert_eq!(serde_json::from_str::<serde_json::Value>(&sub.text()).unwrap(),serde_json::json!({"op":"subscribe","args":[{"channel":"books","instId":"BTC-USDT"},{"channel":"trades","instId":"BTC-USD-SWAP"}]}));
  assert!(matches!(okx_upward(r#"{"op":"unsubscribe","args":[{"channel":"trades","instId":"BTC-USD-260925"}]}"#),Some(OkxUpward::Request{op:OkxOp::Unsubscribe,..})));
  let twelve=(0..12).map(|i|format!(r#"{{"channel":"books","instId":"C{i}-USDT"}}"#)).collect::<Vec<_>>().join(",");
  assert!(okx_upward(&format!(r#"{{"op":"subscribe","args":[{twelve}]}}"#)).is_some());
  for bad in [
   "PING","ping ","pong","","{}",
   r#"{"op":"login","args":[{"apiKey":"x"}]}"#,
   r#"{"op":"subscribe","args":[]}"#,
   r#"{"op":"subscribe","args":[{"channel":"tickers","instId":"BTC-USDT"}]}"#,
   r#"{"op":"subscribe","args":[{"channel":"books5","instId":"BTC-USDT"}]}"#,
   r#"{"op":"subscribe","args":[{"channel":"books","instId":"BTC-EUR"}]}"#,
   r#"{"op":"subscribe","args":[{"channel":"books","instType":"SPOT"}]}"#,
   r#"{"op":"subscribe","args":[{"channel":"books","instId":"BTC-USDT","extra":1}]}"#,
   r#"{"op":"subscribe","id":"1","args":[{"channel":"books","instId":"BTC-USDT"}]}"#,
   r#"{"op":"Subscribe","args":[{"channel":"books","instId":"BTC-USDT"}]}"#,
   r#"{"op":"subscribe","args":{"channel":"books","instId":"BTC-USDT"}}"#,
  ] {
   assert_eq!(okx_upward(bad),None,"{bad}");
  }
  let thirteen=(0..13).map(|i|format!(r#"{{"channel":"books","instId":"C{i}-USDT"}}"#)).collect::<Vec<_>>().join(",");
  assert_eq!(okx_upward(&format!(r#"{{"op":"subscribe","args":[{thirteen}]}}"#)),None,"args 最多 12 个");
 }

 #[test]
 fn okx_subscription_cap() {
  let mut subs=OkxSubscriptions::default();
  let batch=|op:OkxOp,from:usize,n:usize|OkxUpward::Request{op,args:(from..from+n).map(|i|(OkxChannel::Books,format!("C{i}-USDT"))).collect()};
  assert!(subs.admit(&batch(OkxOp::Subscribe,0,12)));
  assert!(subs.admit(&batch(OkxOp::Subscribe,12,12)));
  assert!(subs.admit(&batch(OkxOp::Subscribe,0,12)),"已经订着的再订一次不占新名额");
  assert!(!subs.admit(&batch(OkxOp::Subscribe,24,1)),"第 25 个不放");
  assert!(subs.admit(&OkxUpward::Ping));
  assert!(subs.admit(&batch(OkxOp::Unsubscribe,0,2)));
  assert!(subs.admit(&batch(OkxOp::Subscribe,24,2)),"退订之后腾出名额");
 }

 // ---------------------------------------------------------------- 端到端（本机假上游）

 /// 假上游：连上先发一帧 `hello <路径>?<查询串>`，然后按路径的第一段：`/echo` 把收到的文本回成
 /// `echo <文本>`；`/bye` 立刻关；`/quiet` 只收不发（ping 照样由 axum 自动回 pong）。
 async fn fake_upstream(ws:WebSocketUpgrade,uri:axum::http::Uri,RawQuery(query):RawQuery)->Response {
  let path=uri.path().to_owned();
  ws.on_upgrade(move|mut socket| async move {
   let _=socket.send(Down::Text(format!("hello {path}?{}",query.unwrap_or_default()).into())).await;
   let first=path.split('/').nth(1).unwrap_or_default().to_owned();
   match first.as_str() {
    "bye"=>{let _=socket.send(Down::Close(None)).await;},
    "echo"=>while let Some(Ok(message))=socket.recv().await {
     if let Down::Text(text)=message {if socket.send(Down::Text(format!("echo {}",text.as_str()).into())).await.is_err() {break}}
    },
    _=>while let Some(Ok(_))=socket.recv().await {},
   }
  })
 }
 async fn serve<S:Clone+Send+Sync+'static>(app:Router)->u16 {
  let listener=tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
  let port=listener.local_addr().unwrap().port();
  tokio::spawn(async move {axum::serve(listener,app.into_make_service_with_connect_info::<SocketAddr>()).await.unwrap()});
  port
 }
 const QUICK:Timing=Timing{connect:Duration::from_secs(2),ping:Duration::from_secs(30),upstream_idle:Duration::from_secs(30),client_idle:Duration::from_secs(30),send:Duration::from_secs(2)};
 /// 币安三条上游都指到 `<base>/cm`、`<base>/public`、`<base>/market`。
 fn lanes(base:&str)->BinanceUpstreams {
  BinanceUpstreams{coin_m:format!("{base}/cm"),usdm_depth:format!("{base}/public"),usdm_trades:format!("{base}/market")}
 }
 async fn fake()->String {format!("ws://127.0.0.1:{}",serve::<()>(Router::new().fallback(fake_upstream)).await)}
 async fn relay_with(binance:BinanceUpstreams,okx:String,max:usize,per_client:usize,timing:Timing)->u16 {
  serve::<()>(routes_with(Arc::new(Relay::new(binance,okx,max,per_client,timing)))).await
 }
 async fn relay_to(path:&str,max:usize,timing:Timing)->u16 {
  let base=format!("{}{path}",fake().await);
  relay_with(lanes(&base),base,max,max,timing).await
 }
 type Client=tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;
 async fn dial(port:u16,path:&str)->Result<Client,tungstenite::Error> {
  tokio_tungstenite::connect_async(format!("ws://127.0.0.1:{port}{path}")).await.map(|(c,_)|c)
 }
 /// 以某个来源地址来拨（本机对端 + `X-Forwarded-For`，和线上 Caddy 转进来的一样）。
 async fn dial_as(ip:&str,port:u16,path:&str)->Result<Client,tungstenite::Error> {
  use tokio_tungstenite::tungstenite::client::IntoClientRequest;
  let mut request=format!("ws://127.0.0.1:{port}{path}").into_client_request().unwrap();
  request.headers_mut().insert("x-forwarded-for",ip.parse().unwrap());
  tokio_tungstenite::connect_async(request).await.map(|(c,_)|c)
 }
 /// 拨号应该被拒，拒的状态码与 `Retry-After`。
 fn refused(result:Result<Client,tungstenite::Error>)->(u16,String) {
  match result {
   Err(tungstenite::Error::Http(reply))=>(reply.status().as_u16(),reply.headers().get("retry-after").map(|v|v.to_str().unwrap().to_owned()).unwrap_or_default()),
   other=>panic!("应该被拒，实际 {:?}",other.map(|_|())),
  }
 }
 /// 下一帧文本；跳过 ping。`None` 表示在期限内没有文本到。
 async fn next_text(client:&mut Client,within:Duration)->Option<String> {
  tokio::time::timeout(within,async {
   loop {
    match client.next().await {
     Some(Ok(Up::Text(text)))=>return Some(text.as_str().to_owned()),
     Some(Ok(Up::Ping(_)|Up::Pong(_)))=>continue,
     _=>return None,
    }
   }
  }).await.ok().flatten()
 }
 /// 这条连接在期限内被关掉了没有。
 async fn closed_within(client:&mut Client,within:Duration)->bool {
  tokio::time::timeout(within,async {
   loop {
    match client.next().await {
     Some(Ok(Up::Close(_)))|None|Some(Err(_))=>return true,
     _=>continue,
    }
   }
  }).await.unwrap_or(false)
 }

 #[tokio::test]
 async fn bad_requests_are_refused_without_upgrading() {
  let relay=Arc::new(Relay::new(lanes("ws://127.0.0.1:1"),"ws://127.0.0.1:1/",4,4,QUICK));
  let app=||routes_with::<()>(relay.clone());
  let cases=[
   (format!("{BINANCE_PATH}"),"invalid_query"),
   (format!("{BINANCE_PATH}?streams="),"invalid_streams"),
   (format!("{BINANCE_PATH}?streams=btcusdt@kline_1m"),"invalid_streams"),
   (format!("{BINANCE_PATH}?streams=BTCUSDT@aggTrade"),"invalid_streams"),
   (format!("{BINANCE_PATH}?streams={}",(0..9).map(|i|format!("s{i}usdt@aggTrade")).collect::<Vec<_>>().join("/")),"invalid_streams"),
   (format!("{BINANCE_PATH}?streams=btcusdt@aggTrade&x=1"),"invalid_query"),
   // 合规但不是 WebSocket 升级请求。
   (format!("{BINANCE_PATH}?streams=btcusdt@aggTrade"),"websocket_required"),
   (OKX_PATH.to_owned(),"websocket_required"),
  ];
  for (uri,code) in cases {
   let reply=app().oneshot(Request::builder().uri(&uri).body(Body::empty()).unwrap()).await.unwrap();
   assert_eq!(reply.status(),StatusCode::BAD_REQUEST,"{uri}");
   let body:serde_json::Value=serde_json::from_slice(&reply.into_body().collect().await.unwrap().to_bytes()).unwrap();
   assert_eq!(body["error"]["code"],code,"{uri}");
  }
 }

 #[tokio::test]
 async fn binance_relay_splits_streams_by_product_passes_frames_down_and_nothing_up() {
  let port=relay_to("/echo",4,QUICK).await;
  let streams="btcusdt@aggTrade/btcusd_perp@depth@100ms/btcusdt@aggTrade/btcusdt@depth@100ms/btcusd_260925@aggTrade/btcusdt_261225@depth@100ms";
  let mut client=dial(port,&format!("{BINANCE_PATH}?streams={streams}")).await.unwrap();
  let mut hellos=Vec::new();
  for _ in 0..3 {hellos.push(next_text(&mut client,Duration::from_secs(2)).await.unwrap());}
  hellos.sort();
  assert_eq!(hellos,vec![
   "hello /echo/cm?streams=btcusd_perp@depth@100ms/btcusd_260925@aggTrade".to_owned(),
   "hello /echo/market?streams=btcusdt@aggTrade".to_owned(),
   "hello /echo/public?streams=btcusdt@depth@100ms/btcusdt_261225@depth@100ms".to_owned(),
  ],"币本位走 dstream、U 本位深度走 /public、U 本位成交走 /market，各自拿到去重后的那一组");
  client.send(Up::Text(r#"{"method":"SUBSCRIBE","params":["ethusdt@aggTrade"],"id":1}"#.into())).await.unwrap();
  assert_eq!(next_text(&mut client,Duration::from_millis(400)).await,None,"币安那条上，手机发的东西一帧都不转");
 }

 #[tokio::test]
 async fn only_the_upstreams_in_use_are_opened() {
  let port=relay_to("/echo",4,QUICK).await;
  let mut client=dial(port,&format!("{BINANCE_PATH}?streams=btcusdt@depth@100ms")).await.unwrap();
  assert_eq!(next_text(&mut client,Duration::from_secs(2)).await.as_deref(),Some("hello /echo/public?streams=btcusdt@depth@100ms"));
  assert_eq!(next_text(&mut client,Duration::from_millis(400)).await,None,"只开了一条上游");
 }

 #[tokio::test]
 async fn when_any_binance_upstream_closes_the_whole_relay_closes() {
  let base=fake().await;
  let binance=BinanceUpstreams{coin_m:format!("{base}/echo/cm"),usdm_depth:format!("{base}/bye/public"),usdm_trades:format!("{base}/echo/market")};
  let port=relay_with(binance,format!("{base}/echo"),4,4,QUICK).await;
  let mut client=dial(port,&format!("{BINANCE_PATH}?streams=btcusd_perp@aggTrade/btcusdt@aggTrade/btcusdt@depth@100ms")).await.unwrap();
  assert!(closed_within(&mut client,Duration::from_secs(3)).await,"深度那条断了，成交与币本位两条还连着也要整条断");
 }

 #[tokio::test]
 async fn a_binance_upstream_that_cannot_be_reached_refuses_the_whole_relay() {
  let base=fake().await;
  let binance=BinanceUpstreams{coin_m:"ws://127.0.0.1:1/cm".into(),usdm_depth:format!("{base}/echo/public"),usdm_trades:format!("{base}/echo/market")};
  let port=relay_with(binance,format!("{base}/echo"),4,4,QUICK).await;
  let (status,retry)=refused(dial(port,&format!("{BINANCE_PATH}?streams=btcusdt@depth@100ms/btcusd_perp@depth@100ms")).await);
  assert_eq!((status,retry.as_str()),(503,"2"),"币本位那条连不上，不给手机半条中继");
  assert!(dial(port,&format!("{BINANCE_PATH}?streams=btcusdt@depth@100ms/btcusdt@aggTrade")).await.is_ok(),"用不到那条上游时照常连");
 }

 #[tokio::test]
 async fn a_quiet_binance_upstream_that_answers_pings_is_kept() {
  // 上游一帧数据都不发，但会回 pong：期限 300 ms、每 100 ms ping 一次，一秒后还连着。
  let port=relay_to("/quiet",4,Timing{ping:Duration::from_millis(100),upstream_idle:Duration::from_millis(300),..QUICK}).await;
  let mut client=dial(port,&format!("{BINANCE_PATH}?streams=btcusdt_261225@aggTrade/btcusd_perp@aggTrade")).await.unwrap();
  assert!(!closed_within(&mut client,Duration::from_millis(1200)).await,"冷门成交没有数据帧不等于上游死了");
 }

 #[tokio::test]
 async fn okx_relay_forwards_only_the_whitelist() {
  let port=relay_to("/echo",4,QUICK).await;
  let mut client=dial(port,OKX_PATH).await.unwrap();
  assert_eq!(next_text(&mut client,Duration::from_secs(2)).await.as_deref(),Some("hello /echo?"));
  client.send(Up::Text("ping".into())).await.unwrap();
  assert_eq!(next_text(&mut client,Duration::from_secs(2)).await.as_deref(),Some("echo ping"));
  for dropped in [r#"{"op":"login","args":[]}"#,r#"{"op":"subscribe","args":[{"channel":"tickers","instId":"BTC-USDT"}]}"#,"hello?"] {
   client.send(Up::Text(dropped.into())).await.unwrap();
  }
  client.send(Up::Text(r#"{"op":"subscribe", "args":[{"channel":"books","instId":"BTC-USD-SWAP"}]}"#.into())).await.unwrap();
  let echoed=next_text(&mut client,Duration::from_secs(2)).await.unwrap();
  let sent:serde_json::Value=serde_json::from_str(echoed.strip_prefix("echo ").unwrap()).unwrap();
  assert_eq!(sent,serde_json::json!({"op":"subscribe","args":[{"channel":"books","instId":"BTC-USD-SWAP"}]}),"前面三帧被丢掉，连接还在，合规的订阅照转");
 }

 #[tokio::test]
 async fn the_relay_count_is_capped() {
  let port=relay_to("/echo",1,QUICK).await;
  let mut first=dial(port,OKX_PATH).await.unwrap();
  assert!(next_text(&mut first,Duration::from_secs(2)).await.is_some());
  assert_eq!(refused(dial_as("198.51.100.9",port,OKX_PATH).await),(503,"2".to_owned()),"全局上限对谁都一样");
  first.close(None).await.unwrap();
  drop(first);
  // 第一条关掉后名额还回来。
  let deadline=Instant::now()+Duration::from_secs(3);
  loop {
   if dial(port,OKX_PATH).await.is_ok() {break}
   assert!(Instant::now()<deadline,"名额没有还回来");
   tokio::time::sleep(Duration::from_millis(50)).await;
  }
 }

 #[tokio::test]
 async fn each_source_address_gets_its_own_share() {
  let base=format!("{}/echo",fake().await);
  let port=relay_with(lanes(&base),base,64,2,QUICK).await;
  let binance=format!("{BINANCE_PATH}?streams=btcusdt@depth@100ms");
  let mut first=dial_as("198.51.100.7",port,&binance).await.unwrap();
  let _second=dial_as("198.51.100.7",port,OKX_PATH).await.unwrap();
  assert_eq!(refused(dial_as("198.51.100.7",port,OKX_PATH).await),(429,"2".to_owned()),"币安与 OKX 两条合计算这个来源的名额");
  assert_eq!(refused(dial_as("198.51.100.7",port,&binance).await).0,429);
  let _other=dial_as("198.51.100.8",port,&binance).await.expect("另一个来源不受影响");
  assert!(dial(port,OKX_PATH).await.is_ok(),"不带转发头的本机来源是另一份名额");
  // 关掉一条，这个来源的名额还回来。
  first.close(None).await.unwrap();
  drop(first);
  let deadline=Instant::now()+Duration::from_secs(3);
  loop {
   if dial_as("198.51.100.7",port,OKX_PATH).await.is_ok() {break}
   assert!(Instant::now()<deadline,"来源名额没有还回来");
   tokio::time::sleep(Duration::from_millis(50)).await;
  }
 }

 #[tokio::test]
 async fn upstream_that_cannot_be_reached_is_503_not_an_empty_socket() {
  let relay=Arc::new(Relay::new(lanes("ws://127.0.0.1:1"),"ws://127.0.0.1:1/ws",4,4,QUICK));
  let port=serve::<()>(routes_with(relay)).await;
  match dial(port,OKX_PATH).await {
   Err(tungstenite::Error::Http(reply))=>assert_eq!(reply.status().as_u16(),503),
   other=>panic!("应该 503，实际 {:?}",other.map(|_|())),
  }
 }

 #[tokio::test]
 async fn when_upstream_closes_the_phone_is_closed_too() {
  let port=relay_to("/bye",4,QUICK).await;
  let mut client=dial(port,OKX_PATH).await.unwrap();
  assert!(closed_within(&mut client,Duration::from_secs(3)).await);
 }

 #[tokio::test]
 async fn a_silent_upstream_is_dropped() {
  let port=relay_to("/quiet",4,Timing{upstream_idle:Duration::from_millis(300),..QUICK}).await;
  let mut client=dial(port,&format!("{BINANCE_PATH}?streams=btcusdt@aggTrade")).await.unwrap();
  assert!(next_text(&mut client,Duration::from_secs(2)).await.is_some());
  assert!(closed_within(&mut client,Duration::from_secs(3)).await,"上游沉默超过期限就断");
 }

 #[tokio::test]
 async fn the_phone_is_pinged_and_a_silent_phone_is_dropped() {
  let port=relay_to("/quiet",4,Timing{ping:Duration::from_millis(100),..QUICK}).await;
  let mut client=dial(port,OKX_PATH).await.unwrap();
  let got_ping=tokio::time::timeout(Duration::from_secs(2),async {
   loop {if let Some(Ok(Up::Ping(_)))=client.next().await {return true}}
  }).await.unwrap_or(false);
  assert!(got_ping,"服务端定时 ping 手机");
  // 手机一帧不回（这里压根不再读，tungstenite 也就不会替它回 pong）：到期就断。
  let port=relay_to("/quiet",4,Timing{client_idle:Duration::from_millis(300),..QUICK}).await;
  let mut silent=dial(port,OKX_PATH).await.unwrap();
  tokio::time::sleep(Duration::from_millis(800)).await;
  assert!(closed_within(&mut silent,Duration::from_secs(3)).await,"手机沉默超过期限就断");
 }
}
