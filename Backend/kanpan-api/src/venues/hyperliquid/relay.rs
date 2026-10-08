//! `GET /v1/market/ws/hyperliquid` 的一条连接。
//!
//! 手机 / 网页发上来的文本帧只放行这几种，其余丢掉（不转、不断开）：
//! * `{"method":"ping"}`：就地答 `{"channel":"pong"}`，不上游；
//! * `{"method":"subscribe"|"unsubscribe","subscription":{"type":"l2Book","coin":C,"nSigFigs":4}}`；
//! * `{"method":"subscribe"|"unsubscribe","subscription":{"type":"trades","coin":C}}`；
//! * `{"method":"subscribe"|"unsubscribe","subscription":{"type":"candle","coin":C,"interval":I}}`（2026-10-08，行情页 K 线）；
//! * `{"method":"subscribe"|"unsubscribe","subscription":{"type":"activeAssetCtx","coin":C}}`（标记价、费率、持仓量）。
//!
//! `C` 要是 `^[A-Za-z0-9]{1,16}$`，对象里多一个字段都不放。一条连接同时订着的最多 `MAX_TOPICS` 个，
//! 超了的订阅丢掉。订退都交给进程共用的 hub：帧按 `data.coin` 分发过来，原样下发；上游断线重连由 hub
//! 自己重订，这条连接不断、手机什么都不用做。hub 嫌这条连接收得太慢踢掉它时，以 1013 关掉手机那头。
use super::hub::{Class,Feed,Hub,Topic,valid_coin};
use axum::extract::ws::{CloseFrame,Message as Down,WebSocket};
use futures_util::{SinkExt,StreamExt};
use serde_json::Value;
use std::collections::HashSet;
use std::time::Duration;
use tokio::time::Instant;

/// 一条连接同时订着的最多几个：订单流 8 本簿 × （簿 + 成交），或者行情页一只品种
/// （K 线 + 上下文 + 成交）加自选页一排上下文（自选里几十只 Hyperliquid 品种在网关线路上都从这一条订）。给到 64：
/// hub 全进程封顶 900（官方每 IP 1000），常驻跟踪占 600，余下 300 给中继，用户是个位数。
pub const MAX_TOPICS:usize=64;
/// 这条连接在 hub 里的收帧通道能攒几帧。BTC 的 `l2Book` 约每 0.5 秒一帧、成交更密，
/// 16 个订阅一秒几十帧，攒 512 帧 ≈ 十几秒跟不上才算掉队。
const BACKLOG:usize=512;

#[derive(Clone,Debug,PartialEq,Eq)]
pub enum Upward {Ping,Sub {subscribe:bool,topic:Topic}}

fn keys_are(object:&serde_json::Map<String,Value>,want:&[&str])->bool {
 object.len()==want.len()&&want.iter().all(|k|object.contains_key(*k))
}

/// 手机发上来的一帧该不该放行；不放行是 `None`。
pub fn upward(text:&str)->Option<Upward> {
 let v:Value=serde_json::from_str(text).ok()?;
 let object=v.as_object()?;
 let method=object.get("method")?.as_str()?;
 if method=="ping" {return keys_are(object,&["method"]).then_some(Upward::Ping)}
 let subscribe=match method {"subscribe"=>true,"unsubscribe"=>false,_=>return None};
 if !keys_are(object,&["method","subscription"]) {return None}
 let subscription=object.get("subscription")?.as_object()?;
 let coin=subscription.get("coin")?.as_str()?;
 if !valid_coin(coin) {return None}
 let topic=match subscription.get("type")?.as_str()? {
  "l2Book" if keys_are(subscription,&["type","coin","nSigFigs"])&&subscription.get("nSigFigs").and_then(Value::as_u64)==Some(4)=>Topic::book(coin),
  "trades" if keys_are(subscription,&["type","coin"])=>Topic::trades(coin),
  "activeAssetCtx" if keys_are(subscription,&["type","coin"])=>Topic::asset_ctx(coin),
  "candle" if keys_are(subscription,&["type","coin","interval"])=>Topic::candle(coin,super::hub::interval(subscription.get("interval")?.as_str()?)?),
  _=>return None,
 };
 Some(Upward::Sub{subscribe,topic})
}

/// 节拍：多久 ping 一次手机、手机多久没帧就断、发一帧最多等多久。
#[derive(Clone,Copy,Debug)]
pub struct Timing {pub ping:Duration,pub client_idle:Duration,pub send:Duration}

#[derive(Debug)]
enum End {ClientLeft,ClientSilent,ClientStuck,Dropped}

/// 一条中继的一生。`held` 是它占着的名额，活多久占多久。
pub async fn serve(client:WebSocket,hub:Hub,timing:Timing,held:Box<dyn Send>) {
 let _held=held;
 let mut link=hub.join(Class::Relay,BACKLOG);
 let (mut down_tx,mut down_rx)=client.split();
 let mut topics:HashSet<Topic>=HashSet::new();
 let mut ping=tokio::time::interval_at(Instant::now()+timing.ping,timing.ping);
 let mut client_deadline=Instant::now()+timing.client_idle;
 let end=loop {
  tokio::select! {
   feed=link.rx.recv()=>match feed {
    Some(Feed::Text(text))=>{
     if !matches!(tokio::time::timeout(timing.send,down_tx.send(Down::Text(text.as_ref().into()))).await,Ok(Ok(()))) {break End::ClientStuck}
    },
    Some(Feed::Up|Feed::Down)=>{},
    None=>break End::Dropped,
   },
   frame=down_rx.next()=>{
    let message=match frame {Some(Ok(message))=>message,_=>break End::ClientLeft};
    client_deadline=Instant::now()+timing.client_idle;
    let text=match message {Down::Text(text)=>text,Down::Close(_)=>break End::ClientLeft,_=>continue};
    match upward(text.as_str()) {
     Some(Upward::Ping)=>{
      if !matches!(tokio::time::timeout(timing.send,down_tx.send(Down::Text(r#"{"channel":"pong"}"#.into()))).await,Ok(Ok(()))) {break End::ClientStuck}
     },
     Some(Upward::Sub{subscribe:true,topic})=>{
      if topics.contains(&topic)||topics.len()<MAX_TOPICS {topics.insert(topic.clone());link.handle.subscribe(topic);}
     },
     Some(Upward::Sub{subscribe:false,topic})=>{
      if topics.remove(&topic) {link.handle.unsubscribe(topic);}
     },
     None=>{},
    }
   },
   _=ping.tick()=>{
    if !matches!(tokio::time::timeout(timing.send,down_tx.send(Down::Ping(Default::default()))).await,Ok(Ok(()))) {break End::ClientStuck}
   },
   _=tokio::time::sleep_until(client_deadline)=>break End::ClientSilent,
  }
 };
 tracing::debug!("Market relay: Hyperliquid ended: {end:?}");
 if matches!(end,End::Dropped) {
  let frame=CloseFrame{code:1013,reason:"upstream".into()};
  let _=tokio::time::timeout(Duration::from_secs(1),down_tx.send(Down::Close(Some(frame)))).await;
 }
 let _=tokio::time::timeout(Duration::from_secs(1),down_tx.close()).await;
 // `link` 在这里丢掉：hub 把它订着的全部退掉。
}

#[cfg(test)]
mod tests {
 use super::*;

 #[test]
 fn upward_frames() {
  assert_eq!(upward(r#"{"method":"ping"}"#),Some(Upward::Ping));
  assert_eq!(upward(r#"{"method":"subscribe","subscription":{"type":"l2Book","coin":"BTC","nSigFigs":4}}"#),Some(Upward::Sub{subscribe:true,topic:Topic::book("BTC")}));
  assert_eq!(upward(r#"{"method":"unsubscribe","subscription":{"coin":"kPEPE","type":"trades"}}"#),Some(Upward::Sub{subscribe:false,topic:Topic::trades("kPEPE")}));
  assert_eq!(upward(r#"{"method":"subscribe","subscription":{"type":"candle","coin":"BTC","interval":"15m"}}"#),Some(Upward::Sub{subscribe:true,topic:Topic::candle("BTC","15m")}));
  assert_eq!(upward(r#"{"method":"subscribe","subscription":{"type":"activeAssetCtx","coin":"BTC"}}"#),Some(Upward::Sub{subscribe:true,topic:Topic::asset_ctx("BTC")}));
  for bad in [
   "ping","","{}",r#"{"method":"ping","id":1}"#,r#"{"method":"Ping"}"#,
   r#"{"method":"subscribe","subscription":{"type":"l2Book","coin":"BTC"}}"#,
   r#"{"method":"subscribe","subscription":{"type":"l2Book","coin":"BTC","nSigFigs":5}}"#,
   r#"{"method":"subscribe","subscription":{"type":"l2Book","coin":"BTC","nSigFigs":4.0}}"#,
   r#"{"method":"subscribe","subscription":{"type":"l2Book","coin":"BTC","nSigFigs":4,"mantissa":2}}"#,
   r#"{"method":"subscribe","subscription":{"type":"trades","coin":"BTC","x":1}}"#,
   r#"{"method":"subscribe","subscription":{"type":"trades","coin":"BTC-USD"}}"#,
   r#"{"method":"subscribe","subscription":{"type":"trades","coin":"@107"}}"#,
   r#"{"method":"subscribe","subscription":{"type":"userEvents","user":"0x0"}}"#,
   r#"{"method":"subscribe","subscription":{"type":"allMids"}}"#,
   r#"{"method":"subscribe","subscription":{"type":"candle","coin":"BTC"}}"#,
   r#"{"method":"subscribe","subscription":{"type":"candle","coin":"BTC","interval":"7m"}}"#,
   r#"{"method":"subscribe","subscription":{"type":"candle","coin":"BTC","interval":"1m","x":1}}"#,
   r#"{"method":"subscribe","subscription":{"type":"activeAssetCtx","coin":"BTC","user":"0x0"}}"#,
   r#"{"method":"subscribe","subscription":{"type":"activeAssetData","coin":"BTC","user":"0x0"}}"#,
   r#"{"method":"subscribe","subscription":{"type":"trades","coin":"BTC"},"id":1}"#,
   r#"{"method":"post","id":1,"request":{"type":"info","payload":{"type":"meta"}}}"#,
   r#"{"method":"subscribe","subscription":[{"type":"trades","coin":"BTC"}]}"#,
  ] {
   assert_eq!(upward(bad),None,"{bad}");
  }
  assert_eq!(upward(&format!(r#"{{"method":"subscribe","subscription":{{"type":"trades","coin":"{}"}}}}"#,"A".repeat(17))),None);
 }
}
