//! 推送：`/v1/market/stream?source=macro[&streams=dxy@ticker/dxy@kline_1m]`。
//!
//! 没有上游推送可转——采集循环把现状写进内存（`collector::state`），每变一次版本号加一；
//! 每个手机连接盯着版本号，按自己订的流把现状翻成币安组合流的帧发出去。所以：
//!
//! - 新订阅（URL 里带的、或 `SUBSCRIBE` 加的）立刻收到一份当前快照；
//! - 慢的连接不会积压：`watch` 只留最新版本，跟不上就直接跳到最新；
//! - 末根换了（新的一分钟、新的交易日……）先补发上一根的 `x:true`，再发新的一根。
//!
//! 控制报文照币安：`{"method":"SUBSCRIBE"|"UNSUBSCRIBE"|"LIST_SUBSCRIPTIONS","params":[…],"id":n}`，
//! 回 `{"result":null,"id":n}`；认不出的回 `{"error":{"code":2,"msg":…},"id":n}`。
//! 每 15 秒一帧 `{"stream":"heartbeat","data":{"e":"heartbeat","E":…,"marketState":…}}`：
//! 休市时没有行情帧，客户端的看门狗靠它判断连接还活着。
use std::collections::{BTreeMap,BTreeSet};
use std::sync::atomic::{AtomicU64,Ordering};
use std::time::Duration;
use axum::extract::ws::{Message,Utf8Bytes,WebSocket};
use futures_util::{SinkExt,StreamExt};
use serde_json::{Value,json};
use super::{SYMBOL,market_state};
use super::bars::{self,Bar,price};
use super::collector::{self,State};

/// 同时最多多少个手机连接（看盘只有几位用户，64 是挡异常的上限）。
pub const MAX_CLIENTS:u64=64;
/// 一个连接最多订多少条流（14 档 K 线 + ticker = 15，留点余量）。
pub const MAX_STREAMS:usize=32;
const HEARTBEAT:Duration=Duration::from_secs(15);
/// 回 Close 回执最多等多久（对方不收、发送缓冲满时不让这个座位一直占着）。
const CLOSE_GRACE:Duration=Duration::from_secs(2);
const WRITE_TIMEOUT:Duration=Duration::from_secs(10);
static CLIENTS:AtomicU64=AtomicU64::new(0);

/// 一条流。
#[derive(Clone,Debug,PartialEq,Eq,PartialOrd,Ord)]
pub enum Sub {Ticker,Kline(&'static str)}
impl Sub {
 /// `dxy@ticker`、`dxy@kline_1m`、`dxy@kline_1M`（代号大小写都认，周期区分大小写：`1m` 是分钟、`1M` 是月）。
 pub fn parse(name:&str)->Option<Self> {
  let (symbol,kind)=name.split_once('@')?;
  if !symbol.eq_ignore_ascii_case(SYMBOL) {return None}
  if kind=="ticker" {return Some(Self::Ticker)}
  let iv=kind.strip_prefix("kline_")?;
  bars::spec(iv).map(|s|Self::Kline(s.interval))
 }
 pub fn name(&self)->String {
  match self {Self::Ticker=>format!("{}@ticker",SYMBOL.to_ascii_lowercase()),Self::Kline(iv)=>format!("{}@kline_{iv}",SYMBOL.to_ascii_lowercase())}
 }
}

/// 一个连接已经发过什么（只在变了的时候再发）。
#[derive(Debug,Default)]
pub struct Sent {ticker:Option<Value>,klines:BTreeMap<&'static str,(Bar,bool)>}

fn ticker_data(st:&State,now:i64)->Option<Value> {
 let tk=st.ticker(now)?;
 let (p,pp)=super::change(&tk);
 Some(json!({"e":"24hrTicker","s":SYMBOL,"c":price(tk.last),"p":p,"P":pp,"o":price(tk.open),"h":price(tk.high),"l":price(tk.low),
  "v":"0","q":"0","O":tk.session_start,"C":tk.time,"prevClosePrice":tk.prev_close.map(price),
  "marketState":market_state(tk.open_now),"priceSource":tk.source.name()}))
}

fn kline_frame(sub:&Sub,iv:&'static str,b:&Bar,closed:bool,now:i64)->String {
 let span=bars::spec(iv).map(|s|s.span).unwrap_or(bars::Span::Fixed(60_000));
 json!({"stream":sub.name(),"data":{"e":"kline","E":now,"s":SYMBOL,"k":{
  "t":b.t,"T":bars::close_time(span,b.t),"s":SYMBOL,"i":iv,"f":-1,"L":-1,
  "o":price(b.o),"c":price(b.c),"h":price(b.h),"l":price(b.l),"v":"0","n":0,"x":closed,"q":"0","V":"0","Q":"0","B":"0"}}}).to_string()
}

/// 按现状算出这个连接该收的帧。`force` 时（刚订阅）不管发没发过都发一份。
pub fn frames(st:&State,subs:&BTreeSet<Sub>,sent:&mut Sent,now:i64,force:bool)->Vec<String> {
 let mut out=Vec::new();
 for sub in subs {
  match sub {
   Sub::Ticker=>{
    let Some(data)=ticker_data(st,now) else {continue};
    if force||sent.ticker.as_ref()!=Some(&data) {
     let mut framed=data.clone();
     framed["E"]=json!(now);
     out.push(json!({"stream":sub.name(),"data":framed}).to_string());
     sent.ticker=Some(data);
    }
   }
   Sub::Kline(iv)=>{
    let Some(spec)=bars::spec(iv) else {continue};
    let Some(last)=st.last else {continue};
    let open=State::open_of(&spec,last.time);
    let Some(bar)=st.bar(&spec,open) else {continue};
    let closed=bars::close_time(spec.span,open)<now;
    if let Some((prev,prev_closed))=sent.klines.get(iv).copied()&&prev.t!=open&&prev.t<open&&!prev_closed {
     let fin=st.bar(&spec,prev.t).unwrap_or(prev);
     out.push(kline_frame(sub,iv,&fin,true,now));
    }
    if force||sent.klines.get(iv)!=Some(&(bar,closed)) {
     out.push(kline_frame(sub,iv,&bar,closed,now));
     sent.klines.insert(iv,(bar,closed));
    }
   }
  }
 }
 out
}

fn heartbeat(now:i64)->String {
 let open=collector::state().ticker(now).is_some_and(|t|t.open_now);
 json!({"stream":"heartbeat","data":{"e":"heartbeat","E":now,"marketState":market_state(open)}}).to_string()
}

/// 一条控制报文的处理结果。
#[derive(Debug,PartialEq)]
pub enum Control {Subscribed(Vec<Sub>,String),Unsubscribed(Vec<Sub>,String),List(String),Error(String)}

fn error(id:&Value,msg:&str)->String {json!({"error":{"code":2,"msg":msg},"id":id}).to_string()}

pub fn parse_control(text:&str,subs:&BTreeSet<Sub>)->Control {
 let Ok(v)=serde_json::from_str::<Value>(text) else {return Control::Error(error(&Value::Null,"Invalid JSON"))};
 let id=v.get("id").cloned().unwrap_or(Value::Null);
 let method=v.get("method").and_then(Value::as_str).unwrap_or("");
 let params:Vec<&str>=v.get("params").and_then(Value::as_array).map(|a|a.iter().filter_map(Value::as_str).collect()).unwrap_or_default();
 let ok=json!({"result":null,"id":id}).to_string();
 match method {
  "SUBSCRIBE"|"UNSUBSCRIBE"=>{
   let mut list=Vec::new();
   for p in &params {
    match Sub::parse(p) {Some(s)=>list.push(s),None=>return Control::Error(error(&id,&format!("Invalid request: unknown stream {p}")))}
   }
   if method=="SUBSCRIBE" {
    let total=subs.iter().chain(list.iter()).collect::<BTreeSet<_>>().len();
    if total>MAX_STREAMS {return Control::Error(error(&id,"Invalid request: too many streams"))}
    Control::Subscribed(list,ok)
   } else {Control::Unsubscribed(list,ok)}
  }
  "LIST_SUBSCRIPTIONS"=>Control::List(json!({"result":subs.iter().map(Sub::name).collect::<Vec<_>>(),"id":id}).to_string()),
  _=>Control::Error(error(&id,"Invalid request: unknown method")),
 }
}

struct Seat;
impl Drop for Seat {fn drop(&mut self) {CLIENTS.fetch_sub(1,Ordering::Relaxed);}}

async fn send_all(sink:&mut futures_util::stream::SplitSink<WebSocket,Message>,frames:Vec<String>)->bool {
 for f in frames {
  match tokio::time::timeout(WRITE_TIMEOUT,sink.send(Message::Text(Utf8Bytes::from(f)))).await {
   Ok(Ok(()))=>{}
   _=>return false,
  }
 }
 true
}

/// 一个手机连接。`initial` 是 URL 里 `streams=` 的值（用 `/` 隔开）。
pub async fn serve_client(socket:WebSocket,initial:Option<String>) {
 if CLIENTS.fetch_add(1,Ordering::Relaxed)>=MAX_CLIENTS {
  CLIENTS.fetch_sub(1,Ordering::Relaxed);
  let mut socket=socket;
  let _=socket.send(Message::Text(Utf8Bytes::from(error(&Value::Null,"Too many connections")))).await;
  return;
 }
 let _seat=Seat;
 let (mut sink,mut source)=socket.split();
 let mut subs:BTreeSet<Sub>=initial.as_deref().unwrap_or("").split('/').filter_map(Sub::parse).take(MAX_STREAMS).collect();
 let mut sent=Sent::default();
 let mut changes=collector::changes();
 let mut beat=tokio::time::interval(HEARTBEAT);
 beat.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
 let now=||chrono::Utc::now().timestamp_millis();
 let first={let st=collector::state();frames(&st,&subs,&mut sent,now(),true)};
 if !send_all(&mut sink,first).await {return}
 loop {
  let out=tokio::select! {
   msg=source.next()=>match msg {
    Some(Ok(Message::Text(text)))=>{
     if text.len()>4096 {vec![error(&Value::Null,"Invalid request: too long")]} else {
      match parse_control(text.as_str(),&subs) {
       Control::Subscribed(list,ok)=>{
        let fresh:BTreeSet<Sub>=list.into_iter().filter(|s|!subs.contains(s)).collect();
        subs.extend(fresh.iter().cloned());
        let mut out=vec![ok];
        let st=collector::state();
        for s in &fresh {if let Sub::Kline(iv)=s {sent.klines.remove(iv);} else {sent.ticker=None;}}
        out.extend(frames(&st,&fresh,&mut sent,now(),true));
        out
       }
       Control::Unsubscribed(list,ok)=>{
        for s in list {if let Sub::Kline(iv)=&s {sent.klines.remove(iv);} else {sent.ticker=None;} subs.remove(&s);}
        vec![ok]
       }
       Control::List(reply)|Control::Error(reply)=>vec![reply],
      }
     }
    }
    // 对方先发了 Close：tungstenite 已经把回执排进发送队列，但要等下一次读或写才真正发出去。
    // 直接 break 掉 socket，回执就没出门，客户端看到的是 1006（异常断开）而不是 1000
    // （2026-10-05 服务端回归实测）。冲一次 sink 把它送出去；对方卡着不收也只等 CLOSE_GRACE。
    Some(Ok(Message::Close(_)))=>{let _=tokio::time::timeout(CLOSE_GRACE,sink.flush()).await;break}
    None|Some(Err(_))=>break,
    Some(Ok(_))=>vec![],
   },
   changed=changes.changed()=>{
    if changed.is_err() {break}
    let st=collector::state();
    frames(&st,&subs,&mut sent,now(),false)
   }
   _=beat.tick()=>{
    let mut out={let st=collector::state();frames(&st,&subs,&mut sent,now(),false)};
    out.push(heartbeat(now()));
    out
   }
  };
  if !send_all(&mut sink,out).await {break}
 }
}

#[cfg(test)]
mod tests {
 use super::*;
 use super::super::collector::Source;
 fn ms(s:&str)->i64 {chrono::NaiveDateTime::parse_from_str(s,"%Y-%m-%d %H:%M").unwrap().and_utc().timestamp_millis()}

 #[test] fn stream_names_follow_binance() {
  assert_eq!(Sub::parse("dxy@ticker"),Some(Sub::Ticker));
  assert_eq!(Sub::parse("DXY@kline_1m"),Some(Sub::Kline("1m")));
  assert_eq!(Sub::parse("dxy@kline_1M"),Some(Sub::Kline("1M")),"month, not minute");
  assert_eq!(Sub::parse("dxy@kline_8h"),None);
  assert_eq!(Sub::parse("btcusdt@ticker"),None);
  assert_eq!(Sub::Kline("1M").name(),"dxy@kline_1M");
 }

 #[test] fn control_messages_reply_like_binance() {
  let subs=BTreeSet::from([Sub::Ticker]);
  assert_eq!(parse_control(r#"{"method":"SUBSCRIBE","params":["dxy@kline_5m"],"id":7}"#,&subs),
   Control::Subscribed(vec![Sub::Kline("5m")],r#"{"id":7,"result":null}"#.to_string()));
  assert_eq!(parse_control(r#"{"method":"LIST_SUBSCRIPTIONS","id":1}"#,&subs),Control::List(r#"{"id":1,"result":["dxy@ticker"]}"#.to_string()));
  let Control::Error(e)=parse_control(r#"{"method":"SUBSCRIBE","params":["eth@ticker"],"id":2}"#,&subs) else {panic!()};
  assert!(e.contains("\"code\":2")&&e.contains("\"id\":2"));
  assert!(matches!(parse_control("nope",&subs),Control::Error(_)));
 }

 #[test] fn frames_send_snapshots_changes_and_closed_bars() {
  let mut st=State::default();
  let t=ms("2026-10-05 13:00");
  st.tick(102.0,t+SEC,Source::Official);
  let subs=BTreeSet::from([Sub::Ticker,Sub::Kline("1m")]);
  let mut sent=Sent::default();
  let first=frames(&st,&subs,&mut sent,t+2*SEC,true);
  assert_eq!(first.len(),2);
  let ticker:Value=serde_json::from_str(&first[0]).unwrap();
  assert_eq!(ticker["stream"],"dxy@ticker");
  assert_eq!(ticker["data"]["c"],"102.000");
  assert_eq!(ticker["data"]["marketState"],"open");
  let k:Value=serde_json::from_str(&first[1]).unwrap();
  assert_eq!(k["data"]["k"]["t"],t);assert_eq!(k["data"]["k"]["T"],t+59_999);assert_eq!(k["data"]["k"]["x"],false);
  // 什么都没变：不发。
  assert!(frames(&st,&subs,&mut sent,t+3*SEC,false).is_empty());
  // 下一分钟：先补上一根 x:true，再发新的一根；ticker 也变了。
  st.tick(102.5,t+MINUTE+SEC,Source::Official);
  let out=frames(&st,&subs,&mut sent,t+MINUTE+2*SEC,false);
  let parsed:Vec<Value>=out.iter().map(|f|serde_json::from_str(f).unwrap()).collect();
  assert_eq!(parsed.len(),3);
  assert_eq!(parsed[0]["data"]["c"],"102.500");
  assert_eq!((parsed[1]["data"]["k"]["t"].as_i64(),parsed[1]["data"]["k"]["x"].as_bool()),(Some(t),Some(true)));
  assert_eq!((parsed[2]["data"]["k"]["t"].as_i64(),parsed[2]["data"]["k"]["x"].as_bool()),(Some(t+MINUTE),Some(false)));
  // 时间走过了这一分钟、没有新价：心跳那一轮补发 x:true。
  let out=frames(&st,&BTreeSet::from([Sub::Kline("1m")]),&mut sent,t+3*MINUTE,false);
  let k:Value=serde_json::from_str(&out[0]).unwrap();
  assert_eq!(k["data"]["k"]["x"],true);
 }
 const SEC:i64=1000;
 const MINUTE:i64=60_000;

 /// 客户端先关：服务端要回一帧 Close（RFC 6455 §5.5.1），客户端才算干净地关上（1000）。
 /// 2026-10-05 以前服务端收到 Close 就丢掉 socket，回执留在 tungstenite 的队列里没发出去，
 /// 客户端拿到的是「对方没走关闭握手就断了」（浏览器里是 1006）。
 #[tokio::test] async fn a_client_close_is_answered_with_a_close_frame() {
  use tokio_tungstenite::tungstenite::{Error,Message as Frame,error::ProtocolError};
  let app=axum::Router::new().route("/s",axum::routing::get(|ws:axum::extract::WebSocketUpgrade|async move {ws.on_upgrade(|s|serve_client(s,None))}));
  let listener=tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();let addr=listener.local_addr().unwrap();
  tokio::spawn(async move {axum::serve(listener,app).await.unwrap()});
  let (mut client,_)=tokio_tungstenite::connect_async(format!("ws://{addr}/s")).await.unwrap();
  client.close(None).await.unwrap();
  let answer=loop {
   match tokio::time::timeout(Duration::from_secs(5),client.next()).await.expect("服务端 5 秒内没回话") {
    Some(Ok(Frame::Close(_)))=>break Ok(()),
    Some(Ok(_))=>continue,
    Some(Err(Error::Protocol(ProtocolError::ResetWithoutClosingHandshake)))=>break Err("没回 Close 就断了"),
    other=>break Err(if other.is_none() {"流结束却没见到 Close"} else {"读出错"}),
   }
  };
  assert_eq!(answer,Ok(()));
 }
}
