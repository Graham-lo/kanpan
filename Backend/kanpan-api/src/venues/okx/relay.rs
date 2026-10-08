//! `GET /v1/market/ws/okx[?endpoint=business]` 中继的上行白名单（传输、名额、超时在 `market_relay`）。
//!
//! 手机发上来的文本帧只放行字面量 `ping`，或
//! `{"op":"subscribe"|"unsubscribe","args":[{"channel":C,"instId":I}…]}`（args 1–12 个），
//! 其余帧丢掉（不转、不断开）；放行的帧按认出来的字段重新拼，手机写进去的别的东西带不上去。
//!
//! 频道分两个端点（官方文档 WebSocket › Overview：K 线类频道 2023 年起只在 business 端点）：
//! - public（缺省）：`books` / `trades`（主力订单流）、`tickers` / `mark-price` / `funding-rate`（行情）；
//! - business：`candle1m` … `candle1Mutc`（6 小时以上用 `utc` 那一族，和币安的 UTC 桶头对齐）。
//!
//! `instId` 要是 `^[A-Z0-9]{1,20}-(USDT|USD|USDC)(-SWAP|-[0-9]{6})?$`（订单流要看现货、币本位与交割）。
//! 一条连接同时订着的 (channel, instId) 最多 [`MAX_SUBSCRIPTIONS`] 个，超了的那条订阅也丢掉。
use serde::Deserialize;
use std::collections::HashSet;

/// 一条订阅消息里最多几个 args。
pub const MAX_ARGS:usize=12;
/// 一条连接同时订着的 (channel, instId) 最多几个。订单流一只币：现货、U 本位永续、币本位永续、
/// 两个交割，各 books + trades = 10 个；行情页一只品种 ticker + 标记价 + 费率 + trades，
/// 自选页再一排 ticker（自选里几十只 OKX 品种在网关线路上都从这一条连接订）。给到 128：
/// OKX 对每条连接的硬限只有「订退合计 480 次 / 小时」，这里的上限是防一条连接把中继当成全市场转发器。
pub const MAX_SUBSCRIPTIONS:usize=128;

/// 连哪个端点。
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum Endpoint {Public,Business}
impl Endpoint {
 /// `?endpoint=` 的值；缺省 public，不认识的是 `None`。
 pub fn of(value:Option<&str>)->Option<Self> {
  match value {None|Some("public")=>Some(Self::Public),Some("business")=>Some(Self::Business),_=>None}
 }
 pub fn upstream(self)->&'static str {match self {Self::Public=>super::WS_PUBLIC,Self::Business=>super::WS_BUSINESS}}
}

/// K 线频道的周期后缀。
const CANDLE_BARS:[&str;13]=["1m","3m","5m","15m","30m","1H","2H","4H","6Hutc","12Hutc","1Dutc","1Wutc","1Mutc"];

/// 这个端点上能订的频道。
pub fn channel_ok(endpoint:Endpoint,channel:&str)->bool {
 match endpoint {
  Endpoint::Public=>matches!(channel,"books"|"trades"|"tickers"|"mark-price"|"funding-rate"),
  Endpoint::Business=>channel.strip_prefix("candle").is_some_and(|bar|CANDLE_BARS.contains(&bar)),
 }
}

/// OKX 的 instId：`^[A-Z0-9]{1,20}-(USDT|USD|USDC)(-SWAP|-[0-9]{6})?$`。
pub fn valid_inst(inst:&str)->bool {
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
pub enum Op {Subscribe,Unsubscribe}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Arg {channel:String,#[serde(rename="instId")] inst_id:String}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {op:Op,args:Vec<Arg>}

/// 手机发上来的一帧，放行之后长什么样。
#[derive(Clone,Debug,PartialEq,Eq)]
pub enum Upward {
 /// 字面量 `ping`。
 Ping,
 /// 一条订阅 / 退订：(频道, instId)。
 Request {op:Op,args:Vec<(String,String)>},
}
impl Upward {
 /// 发给上游的文本。订阅按放行后的字段重新拼。
 pub fn text(&self)->String {
  match self {
   Self::Ping=>"ping".to_owned(),
   Self::Request{op,args}=>serde_json::json!({
    "op":match op {Op::Subscribe=>"subscribe",Op::Unsubscribe=>"unsubscribe"},
    "args":args.iter().map(|(channel,inst)|serde_json::json!({"channel":channel,"instId":inst})).collect::<Vec<_>>(),
   }).to_string(),
  }
 }
}

/// 手机发上来的一帧该不该放行；不放行就是 `None`（丢掉，不断开）。
pub fn upward(endpoint:Endpoint,text:&str)->Option<Upward> {
 if text=="ping" {return Some(Upward::Ping)}
 let request:Request=serde_json::from_str(text).ok()?;
 if request.args.is_empty()||request.args.len()>MAX_ARGS {return None}
 if !request.args.iter().all(|a|channel_ok(endpoint,&a.channel)&&valid_inst(&a.inst_id)) {return None}
 Some(Upward::Request{op:request.op,args:request.args.into_iter().map(|a|(a.channel,a.inst_id)).collect()})
}

/// 一条连接上正订着的东西，用来卡「同时订着最多几个」。
#[derive(Default)]
pub struct Subscriptions {live:HashSet<(String,String)>}
impl Subscriptions {
 /// 这一帧能不能转上去；能转的话顺手记账。超了上限的订阅整条丢掉，账不动。
 pub fn admit(&mut self,frame:&Upward)->bool {
  match frame {
   Upward::Ping=>true,
   Upward::Request{op:Op::Unsubscribe,args}=>{
    for arg in args {self.live.remove(arg);}
    true
   },
   Upward::Request{op:Op::Subscribe,args}=>{
    let fresh:HashSet<(String,String)>=args.iter().filter(|a|!self.live.contains(*a)).cloned().collect();
    if self.live.len()+fresh.len()>MAX_SUBSCRIPTIONS {return false}
    self.live.extend(fresh);
    true
   },
  }
 }
}

#[cfg(test)]
mod tests {
 use super::*;
 use Endpoint::{Business,Public};

 #[test]
 fn inst_ids() {
  for good in ["BTC-USDT","BTC-USD","BTC-USDC","BTC-USDT-SWAP","BTC-USD-SWAP","BTC-USD-260925","BTC-USDT-261225","1INCH-USDT","ABCDEFGHIJKLMNOPQRST-USDT"] {
   assert!(valid_inst(good),"{good}");
  }
  for bad in ["","BTC","btc-usdt","BTC-EUR","BTC-USDT-swap","BTC-USD-2609","BTC-USD-2609250","BTC-USD_UM-261225","BTC-USD-SWAP-X","-USDT","BTC--USDT",
   "ABCDEFGHIJKLMNOPQRSTU-USDT","BTC-USDT-SWAP ","BTC-USD-26092A"] {
   assert!(!valid_inst(bad),"{bad}");
  }
 }

 #[test]
 fn endpoints() {
  assert_eq!(Endpoint::of(None),Some(Public));
  assert_eq!(Endpoint::of(Some("business")),Some(Business));
  assert_eq!(Endpoint::of(Some("private")),None);
  assert_eq!(Business.upstream(),"wss://ws.okx.com:8443/ws/v5/business");
  for c in ["books","trades","tickers","mark-price","funding-rate"] {assert!(channel_ok(Public,c)&&!channel_ok(Business,c),"{c}")}
  for c in ["candle1m","candle1H","candle4H","candle6Hutc","candle1Dutc","candle1Wutc","candle1Mutc"] {assert!(channel_ok(Business,c)&&!channel_ok(Public,c),"{c}")}
  for c in ["candle1D","candle2m","candle","books5","bbo-tbt","orders","account","trades-all"] {assert!(!channel_ok(Public,c)&&!channel_ok(Business,c),"{c}")}
 }

 #[test]
 fn upward_frames() {
  assert_eq!(upward(Public,"ping"),Some(Upward::Ping));
  let sub=upward(Public,r#"{"op":"subscribe","args":[{"channel":"books","instId":"BTC-USDT"},{"channel":"trades","instId":"BTC-USD-SWAP"}]}"#).unwrap();
  assert_eq!(sub,Upward::Request{op:Op::Subscribe,args:vec![("books".into(),"BTC-USDT".into()),("trades".into(),"BTC-USD-SWAP".into())]});
  assert_eq!(serde_json::from_str::<serde_json::Value>(&sub.text()).unwrap(),serde_json::json!({"op":"subscribe","args":[{"channel":"books","instId":"BTC-USDT"},{"channel":"trades","instId":"BTC-USD-SWAP"}]}));
  assert!(upward(Public,r#"{"op":"subscribe","args":[{"channel":"tickers","instId":"BTC-USDT-SWAP"},{"channel":"funding-rate","instId":"BTC-USDT-SWAP"}]}"#).is_some());
  assert!(upward(Business,r#"{"op":"subscribe","args":[{"channel":"candle1m","instId":"BTC-USDT-SWAP"}]}"#).is_some());
  assert_eq!(upward(Public,r#"{"op":"subscribe","args":[{"channel":"candle1m","instId":"BTC-USDT-SWAP"}]}"#),None,"K 线只在 business 上");
  assert!(matches!(upward(Public,r#"{"op":"unsubscribe","args":[{"channel":"trades","instId":"BTC-USD-260925"}]}"#),Some(Upward::Request{op:Op::Unsubscribe,..})));
  let twelve=(0..12).map(|i|format!(r#"{{"channel":"books","instId":"C{i}-USDT"}}"#)).collect::<Vec<_>>().join(",");
  assert!(upward(Public,&format!(r#"{{"op":"subscribe","args":[{twelve}]}}"#)).is_some());
  for bad in [
   "PING","ping ","pong","","{}",
   r#"{"op":"login","args":[{"apiKey":"x"}]}"#,
   r#"{"op":"subscribe","args":[]}"#,
   r#"{"op":"subscribe","args":[{"channel":"bbo-tbt","instId":"BTC-USDT"}]}"#,
   r#"{"op":"subscribe","args":[{"channel":"books5","instId":"BTC-USDT"}]}"#,
   r#"{"op":"subscribe","args":[{"channel":"books","instId":"BTC-EUR"}]}"#,
   r#"{"op":"subscribe","args":[{"channel":"books","instType":"SPOT"}]}"#,
   r#"{"op":"subscribe","args":[{"channel":"books","instId":"BTC-USDT","extra":1}]}"#,
   r#"{"op":"subscribe","id":"1","args":[{"channel":"books","instId":"BTC-USDT"}]}"#,
   r#"{"op":"Subscribe","args":[{"channel":"books","instId":"BTC-USDT"}]}"#,
   r#"{"op":"subscribe","args":{"channel":"books","instId":"BTC-USDT"}}"#,
  ] {
   assert_eq!(upward(Public,bad),None,"{bad}");
  }
  let thirteen=(0..13).map(|i|format!(r#"{{"channel":"books","instId":"C{i}-USDT"}}"#)).collect::<Vec<_>>().join(",");
  assert_eq!(upward(Public,&format!(r#"{{"op":"subscribe","args":[{thirteen}]}}"#)),None,"args 最多 12 个");
 }

 #[test]
 fn subscription_cap() {
  let mut subs=Subscriptions::default();
  let batch=|op:Op,from:usize,n:usize|Upward::Request{op,args:(from..from+n).map(|i|("books".to_string(),format!("C{i}-USDT"))).collect()};
  let mut filled=0;
  while filled<MAX_SUBSCRIPTIONS {let n=MAX_ARGS.min(MAX_SUBSCRIPTIONS-filled);assert!(subs.admit(&batch(Op::Subscribe,filled,n)));filled+=n;}
  assert!(subs.admit(&batch(Op::Subscribe,0,12)),"已经订着的再订一次不占新名额");
  assert!(!subs.admit(&batch(Op::Subscribe,MAX_SUBSCRIPTIONS,1)),"超了上限的不放");
  assert!(subs.admit(&Upward::Ping));
  assert!(subs.admit(&batch(Op::Unsubscribe,0,2)));
  assert!(subs.admit(&batch(Op::Subscribe,MAX_SUBSCRIPTIONS,2)),"退订之后腾出名额");
 }
}
