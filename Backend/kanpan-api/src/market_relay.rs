//! 行情中继：两条 WebSocket，把手机连不上的公共行情流经这台 VPS 转一手。
//!
//! * `GET /v1/market/ws/binance?streams=a/b/c`：服务端连
//!   `wss://dstream.binance.com/stream?streams=<同样的流>`（币安合约的组合流；这一条连接同时发
//!   U 本位永续 / 交割与币本位永续 / 交割），上游的文本帧原样转给手机。网关线路上的手机连不到
//!   币安的 COIN-M 与交割流，所以主力订单流要这一条。
//! * `GET /v1/market/ws/okx`：服务端连 `wss://ws.okx.com:8443/ws/v5/public`，上游帧原样转给手机
//!   （包括 OKX 的文本 `pong`）。手机在国内直连不了 OKX。
//!
//! 为什么是 `dstream.binance.com`（2026-09-24 在 VPS 上实测）：一条连接同时发四种合约的
//! `@depth@100ms` 与 `@aggTrade`，首帧 386 ms；`dstream.binance.me` 首帧 623 ms 且 12 秒内没有
//! aggTrade。**绝对不许换成 `*.binancefuture.com`**——那是测试网。
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
//! * 两端任一端断开就两端都关。上游的 ping 由 tungstenite 自动回；对手机每 20 秒发一次 ping；
//!   上游 60 秒没有任何帧就断（手机会重连）；手机 90 秒没有任何帧（连 pong 都没有）也断，
//!   免得死在半路的手机一直占着一条上游；往手机发一帧 10 秒发不出去（手机收不动）也断。
//! * 整个进程同时在跑的中继（两条加起来）最多 `MAX_RELAYS` 条，超了 503。
//! * 不登录：行情是公开数据，和其它 `/v1/market/*` 一样。
//! * 先连上游再答 101：上游连不上时手机拿到的是 503 + `Retry-After: 2`，而不是一条升级成功
//!   却马上被关掉的连接。币安那条出站之前先看 `binance_gate`，这个出口被封着就不去敲门，
//!   握手被 429 / 418 顶回来也记进那道闸。
use crate::{AppState,binance_gate,error::{ApiError,Params}};
use axum::Router;
use axum::extract::ws::{CloseFrame,Message as Down,WebSocket,WebSocketUpgrade,rejection::WebSocketUpgradeRejection};
use axum::http::{HeaderValue,StatusCode,header};
use axum::response::{IntoResponse,Response};
use axum::routing::get;
use futures_util::{SinkExt,StreamExt};
use serde::Deserialize;
use std::collections::HashSet;
use std::sync::{Arc,OnceLock};
use std::time::Duration;
use tokio::sync::{OwnedSemaphorePermit,Semaphore};
use tokio::time::Instant;
use tokio_tungstenite::tungstenite::{self,Message as Up};

const BINANCE_PATH:&str="/v1/market/ws/binance";
const OKX_PATH:&str="/v1/market/ws/okx";
const BINANCE_UPSTREAM:&str="wss://dstream.binance.com/stream";
const OKX_UPSTREAM:&str="wss://ws.okx.com:8443/ws/v5/public";

/// 整个进程同时在跑的中继连接数上限（两条中继合计）。3 位朋友、上限约 10 人，一人开一只币
/// 最多两条，64 条是十倍的余量；再多就是有人在拿它当免费代理。
const MAX_RELAYS:usize=64;
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
 /// 多久对手机发一次 ping。
 ping:Duration,
 /// 上游多久没有任何帧就断。
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

pub struct Relay {
 binance:String,
 okx:String,
 permits:Arc<Semaphore>,
 timing:Timing,
}

impl Relay {
 fn new(binance:impl Into<String>,okx:impl Into<String>,max:usize,timing:Timing)->Self {
  Self{binance:binance.into(),okx:okx.into(),permits:Arc::new(Semaphore::new(max)),timing}
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

fn unavailable(code:&'static str)->Response {
 let mut reply=ApiError(StatusCode::SERVICE_UNAVAILABLE,code).into_response();
 reply.headers_mut().insert(header::RETRY_AFTER,HeaderValue::from_static(RETRY_AFTER));
 reply
}

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

/// 为什么结束。只用于日志。
#[derive(Debug)]
enum End {ClientLeft,ClientSilent,ClientStuck,UpstreamClosed,UpstreamSilent,UpstreamStuck}

/// 一条中继的一生：两头来回搬，直到任一头断开或沉默。
async fn pump(client:WebSocket,upstream:Upstream,kind:Kind,timing:Timing,_permit:OwnedSemaphorePermit) {
 let (mut down_tx,mut down_rx)=client.split();
 let (mut up_tx,mut up_rx)=upstream.split();
 let mut ping=tokio::time::interval_at(Instant::now()+timing.ping,timing.ping);
 let mut upstream_deadline=Instant::now()+timing.upstream_idle;
 let mut client_deadline=Instant::now()+timing.client_idle;
 let mut subscriptions=OkxSubscriptions::default();
 let end=loop {
  tokio::select! {
   frame=up_rx.next()=>{
    let message=match frame {
     Some(Ok(message))=>message,
     Some(Err(_))|None=>break End::UpstreamClosed,
    };
    upstream_deadline=Instant::now()+timing.upstream_idle;
    let out=match message {
     Up::Text(text)=>Down::Text(text.as_str().into()),
     Up::Binary(bytes)=>Down::Binary(bytes),
     Up::Close(_)=>break End::UpstreamClosed,
     // ping 由 tungstenite 在读的时候自动回 pong；pong 与原始帧不用转。
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
    if !matches!(tokio::time::timeout(timing.send,up_tx.send(Up::Text(frame.text().into()))).await,Ok(Ok(()))) {break End::UpstreamStuck}
   },
   _=ping.tick()=>{
    if !matches!(tokio::time::timeout(timing.send,down_tx.send(Down::Ping(Default::default()))).await,Ok(Ok(()))) {break End::ClientStuck}
   },
   _=tokio::time::sleep_until(upstream_deadline)=>break End::UpstreamSilent,
   _=tokio::time::sleep_until(client_deadline)=>break End::ClientSilent,
  }
 };
 tracing::debug!("Market relay: {kind:?} ended: {end:?}");
 // 两头都关。发不出去就算了，别让收尾本身卡住这个任务。
 let farewell=match end {
  End::ClientLeft|End::ClientSilent|End::ClientStuck=>None,
  _=>Some(CloseFrame{code:1013,reason:"upstream".into()}),
 };
 if let Some(frame)=farewell {let _=tokio::time::timeout(Duration::from_secs(1),down_tx.send(Down::Close(Some(frame)))).await;}
 let _=tokio::time::timeout(Duration::from_secs(1),down_tx.close()).await;
 let _=tokio::time::timeout(Duration::from_secs(1),up_tx.close()).await;
}

/// 两条中继共用的开门流程：要升级、占一个名额、连上游、再答 101。
async fn open(relay:&Relay,kind:Kind,url:String,ws:Result<WebSocketUpgrade,WebSocketUpgradeRejection>)->Response {
 let Ok(ws)=ws else {return ApiError::bad("websocket_required").into_response()};
 let Ok(permit)=relay.permits.clone().try_acquire_owned() else {return unavailable("relay_busy")};
 let upstream=match connect(&url,kind,relay.timing).await {Ok(stream)=>stream,Err(reply)=>return reply};
 let timing=relay.timing;
 ws.on_upgrade(move|client|pump(client,upstream,kind,timing,permit))
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct StreamsQuery {streams:String}

async fn binance(relay:Arc<Relay>,query:StreamsQuery,ws:Result<WebSocketUpgrade,WebSocketUpgradeRejection>)->Response {
 let Some(streams)=binance_streams(&query.streams) else {return ApiError::bad("invalid_streams").into_response()};
 let url=format!("{}?streams={}",relay.binance,streams.join("/"));
 open(&relay,Kind::Binance,url,ws).await
}

async fn okx(relay:Arc<Relay>,ws:Result<WebSocketUpgrade,WebSocketUpgradeRejection>)->Response {
 let url=relay.okx.clone();
 open(&relay,Kind::Okx,url,ws).await
}

fn routes_with<S:Clone+Send+Sync+'static>(relay:Arc<Relay>)->Router<S> {
 let for_okx=relay.clone();
 Router::new()
  .route(BINANCE_PATH,get(move|Params(query):Params<StreamsQuery>,ws:Result<WebSocketUpgrade,WebSocketUpgradeRejection>| {
   let relay=relay.clone();
   async move {binance(relay,query,ws).await}
  }))
  .route(OKX_PATH,get(move|ws:Result<WebSocketUpgrade,WebSocketUpgradeRejection>| {
   let relay=for_okx.clone();
   async move {okx(relay,ws).await}
  }))
}

fn shared()->Arc<Relay> {
 static R:OnceLock<Arc<Relay>>=OnceLock::new();
 R.get_or_init(||Arc::new(Relay::new(BINANCE_UPSTREAM,OKX_UPSTREAM,MAX_RELAYS,TIMING))).clone()
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

 /// 假上游：连上先发一帧 `hello <查询串>`，然后按路径：`/echo` 把收到的文本回成 `echo <文本>`；
 /// `/bye` 立刻关；`/quiet` 只收不发。
 async fn fake_upstream(ws:WebSocketUpgrade,uri:axum::http::Uri,RawQuery(query):RawQuery)->Response {
  let path=uri.path().to_owned();
  ws.on_upgrade(move|mut socket| async move {
   let _=socket.send(Down::Text(format!("hello {}",query.unwrap_or_default()).into())).await;
   match path.as_str() {
    "/bye"=>{let _=socket.send(Down::Close(None)).await;},
    "/echo"=>while let Some(Ok(message))=socket.recv().await {
     if let Down::Text(text)=message {if socket.send(Down::Text(format!("echo {}",text.as_str()).into())).await.is_err() {break}}
    },
    _=>while let Some(Ok(_))=socket.recv().await {},
   }
  })
 }
 async fn serve<S:Clone+Send+Sync+'static>(app:Router)->u16 {
  let listener=tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
  let port=listener.local_addr().unwrap().port();
  tokio::spawn(async move {axum::serve(listener,app).await.unwrap()});
  port
 }
 const QUICK:Timing=Timing{connect:Duration::from_secs(2),ping:Duration::from_secs(30),upstream_idle:Duration::from_secs(30),client_idle:Duration::from_secs(30),send:Duration::from_secs(2)};
 async fn relay_to(path:&str,max:usize,timing:Timing)->u16 {
  let upstream=serve::<()>(Router::new().fallback(fake_upstream)).await;
  let base=format!("ws://127.0.0.1:{upstream}{path}");
  serve::<()>(routes_with(Arc::new(Relay::new(base.clone(),base,max,timing)))).await
 }
 type Client=tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;
 async fn dial(port:u16,path:&str)->Result<Client,tungstenite::Error> {
  tokio_tungstenite::connect_async(format!("ws://127.0.0.1:{port}{path}")).await.map(|(c,_)|c)
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
  let relay=Arc::new(Relay::new("ws://127.0.0.1:1/","ws://127.0.0.1:1/",4,QUICK));
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
 async fn binance_relay_passes_frames_down_and_nothing_up() {
  let port=relay_to("/echo",4,QUICK).await;
  let mut client=dial(port,&format!("{BINANCE_PATH}?streams=btcusdt@aggTrade/btcusd_perp@depth@100ms/btcusdt@aggTrade")).await.unwrap();
  assert_eq!(next_text(&mut client,Duration::from_secs(2)).await.as_deref(),Some("hello streams=btcusdt@aggTrade/btcusd_perp@depth@100ms"),"上游拿到的是去重后的同一串流");
  client.send(Up::Text(r#"{"method":"SUBSCRIBE","params":["ethusdt@aggTrade"],"id":1}"#.into())).await.unwrap();
  assert_eq!(next_text(&mut client,Duration::from_millis(400)).await,None,"币安那条上，手机发的东西一帧都不转");
 }

 #[tokio::test]
 async fn okx_relay_forwards_only_the_whitelist() {
  let port=relay_to("/echo",4,QUICK).await;
  let mut client=dial(port,OKX_PATH).await.unwrap();
  assert_eq!(next_text(&mut client,Duration::from_secs(2)).await.as_deref(),Some("hello "));
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
  match dial(port,OKX_PATH).await {
   Err(tungstenite::Error::Http(reply))=>{
    assert_eq!(reply.status().as_u16(),503);
    assert_eq!(reply.headers()["retry-after"],"2");
   },
   other=>panic!("第二条应该 503，实际 {:?}",other.map(|_|())),
  }
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
 async fn upstream_that_cannot_be_reached_is_503_not_an_empty_socket() {
  let relay=Arc::new(Relay::new("ws://127.0.0.1:1/stream","ws://127.0.0.1:1/ws",4,QUICK));
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
