//! Bybit 中继的上行白名单：手机发上来的文本帧只放行
//! `{"op":"ping"}`（可带 `req_id`）与 `{"op":"subscribe"|"unsubscribe","args":[…]}`，
//! 每个 arg 要是 `^(orderbook\.(1|50|200|500|1000)|publicTrade|tickers|kline\.(1|3|5|15|30|60|120|240|360|720|D|W|M))\.[A-Z0-9]{2,30}$`
//! （盘口、逐笔给主力订单流；行情、K 线给行情页，2026-10-08），一条 1–10 个
//! （Bybit 现货的硬限，三个 category 统一按 10）；一条连接同时订着的 topic 最多 `MAX_TOPICS` 个。
//! 其余帧丢掉（不转、不断开）。放行的帧按认出来的字段重新拼，手机写进去的别的东西带不上去。
use serde_json::{Value,json};
use std::collections::HashSet;

/// 一条订阅消息里最多几个 args。
pub const MAX_ARGS:usize=10;
/// 一条连接同时订着的 topic 最多几个：订单流 12 本簿 × （簿 + 成交），或者行情页一只品种
/// （行情 + 一档 K 线 + 成交）加自选页一排行情。给到 48。
pub const MAX_TOPICS:usize=48;

/// K 线周期。
const KLINE_INTERVALS:[&str;13]=["1","3","5","15","30","60","120","240","360","720","D","W","M"];

/// 一个 topic 合不合规。
pub fn valid_topic(topic:&str)->bool {
 let (head,symbol)=match topic.rsplit_once('.') {Some(parts)=>parts,None=>return false};
 let head_ok=match head.strip_prefix("orderbook.") {
  Some(depth)=>matches!(depth,"1"|"50"|"200"|"500"|"1000"),
  None=>head=="publicTrade"||head=="tickers"||head.strip_prefix("kline.").is_some_and(|i|KLINE_INTERVALS.contains(&i)),
 };
 head_ok&&(2..=30).contains(&symbol.len())&&symbol.bytes().all(|b|b.is_ascii_uppercase()||b.is_ascii_digit())
}

fn valid_req_id(id:&str)->bool {(1..=36).contains(&id.len())&&id.bytes().all(|b|b.is_ascii_alphanumeric()||b==b'-'||b==b'_')}

#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum Op {Subscribe,Unsubscribe}

/// 放行之后的一帧。
#[derive(Clone,Debug,PartialEq,Eq)]
pub enum Upward {
 Ping {req_id:Option<String>},
 Request {op:Op,args:Vec<String>,req_id:Option<String>},
}

impl Upward {
 /// 发给上游的文本。
 pub fn text(&self)->String {
  let mut v=match self {
   Self::Ping{..}=>json!({"op":"ping"}),
   Self::Request{op,args,..}=>json!({"op":match op {Op::Subscribe=>"subscribe",Op::Unsubscribe=>"unsubscribe"},"args":args}),
  };
  let (Self::Ping{req_id}|Self::Request{req_id,..})=self;
  if let Some(id)=req_id {v["req_id"]=json!(id);}
  v.to_string()
 }
}

/// 手机发上来的一帧该不该放行；不放行是 `None`。
pub fn upward(text:&str)->Option<Upward> {
 let v:Value=serde_json::from_str(text).ok()?;
 let object=v.as_object()?;
 if object.keys().any(|k|!matches!(k.as_str(),"op"|"args"|"req_id")) {return None}
 let req_id=match object.get("req_id") {
  None=>None,
  Some(Value::String(id)) if valid_req_id(id)=>Some(id.clone()),
  Some(_)=>return None,
 };
 match object.get("op")?.as_str()? {
  "ping"=>object.get("args").is_none().then_some(Upward::Ping{req_id}),
  op @ ("subscribe"|"unsubscribe")=>{
   let args=object.get("args")?.as_array()?;
   if args.is_empty()||args.len()>MAX_ARGS {return None}
   let mut out=Vec::with_capacity(args.len());
   for arg in args {
    let topic=arg.as_str()?;
    if !valid_topic(topic) {return None}
    if !out.iter().any(|t|t==topic) {out.push(topic.to_owned());}
   }
   let op=if op=="subscribe" {Op::Subscribe} else {Op::Unsubscribe};
   Some(Upward::Request{op,args:out,req_id})
  },
  _=>None,
 }
}

/// 一条连接上正订着的 topic，用来卡「同时订着最多几个」。
#[derive(Default)]
pub struct Subscriptions {live:HashSet<String>}
impl Subscriptions {
 /// 这一帧能不能转上去；能转就顺手记账。超了上限的订阅整条丢掉，账不动。
 pub fn admit(&mut self,frame:&Upward)->bool {
  match frame {
   Upward::Ping{..}=>true,
   Upward::Request{op:Op::Unsubscribe,args,..}=>{
    for topic in args {self.live.remove(topic);}
    true
   },
   Upward::Request{op:Op::Subscribe,args,..}=>{
    let fresh=args.iter().filter(|t|!self.live.contains(*t)).count();
    if self.live.len()+fresh>MAX_TOPICS {return false}
    self.live.extend(args.iter().cloned());
    true
   },
  }
 }
}

#[cfg(test)]
mod tests {
 use super::*;

 #[test]
 fn topics() {
  for good in ["orderbook.1.BTCUSDT","orderbook.50.BTCUSD","orderbook.200.ETHUSDT","orderbook.500.BTCUSDH26","orderbook.1000.1000PEPEUSDT","publicTrade.BTCUSDT","publicTrade.AB",&format!("publicTrade.{}","A".repeat(30)),
   "tickers.BTCUSDT","kline.1.BTCUSDT","kline.D.BTCUSDT","kline.240.1000PEPEUSDT"] {
   assert!(valid_topic(good),"{good}");
  }
  for bad in ["","orderbook.BTCUSDT","orderbook.100.BTCUSDT","orderbook.1000.btcusdt","publicTrade.B","allLiquidation.BTCUSDT","kline.2.BTCUSDT","kline.1h.BTCUSDT","kline.BTCUSDT","tickers.btcusdt","liquidation.BTCUSDT",
   &format!("publicTrade.{}","A".repeat(31)),"publicTrade.BTC-USDT","publicTrade.BTCUSDT ","orderbook.1000.BTC.USDT","publictrade.BTCUSDT"] {
   assert!(!valid_topic(bad),"{bad}");
  }
 }

 #[test]
 fn upward_frames() {
  assert_eq!(upward(r#"{"op":"ping"}"#),Some(Upward::Ping{req_id:None}));
  let ping=upward(r#"{"op":"ping","req_id":"k-1"}"#).unwrap();
  assert_eq!(serde_json::from_str::<Value>(&ping.text()).unwrap(),json!({"op":"ping","req_id":"k-1"}));
  let sub=upward(r#"{"op":"subscribe","args":["orderbook.1000.BTCUSDT","publicTrade.BTCUSDT","publicTrade.BTCUSDT"]}"#).unwrap();
  assert_eq!(sub,Upward::Request{op:Op::Subscribe,args:vec!["orderbook.1000.BTCUSDT".into(),"publicTrade.BTCUSDT".into()],req_id:None},"重复的去掉");
  assert_eq!(serde_json::from_str::<Value>(&sub.text()).unwrap(),json!({"op":"subscribe","args":["orderbook.1000.BTCUSDT","publicTrade.BTCUSDT"]}));
  assert!(matches!(upward(r#"{"op":"unsubscribe","args":["orderbook.1000.BTCUSD"],"req_id":"x"}"#),Some(Upward::Request{op:Op::Unsubscribe,..})));
  let ten=(0..10).map(|i|format!(r#""publicTrade.C{i}USDT""#)).collect::<Vec<_>>().join(",");
  assert!(upward(&format!(r#"{{"op":"subscribe","args":[{ten}]}}"#)).is_some());
  let eleven=(0..11).map(|i|format!(r#""publicTrade.C{i}USDT""#)).collect::<Vec<_>>().join(",");
  assert_eq!(upward(&format!(r#"{{"op":"subscribe","args":[{eleven}]}}"#)),None,"一条最多 10 个");
  for bad in [
   "ping","","{}",r#"{"op":"PING"}"#,r#"{"op":"ping","args":[]}"#,r#"{"op":"ping","req_id":5}"#,
   r#"{"op":"ping","req_id":"has space"}"#,
   r#"{"op":"auth","args":["key",1,"sig"]}"#,
   r#"{"op":"subscribe","args":[]}"#,
   r#"{"op":"subscribe","args":"publicTrade.BTCUSDT"}"#,
   r#"{"op":"subscribe","args":["kline.7.BTCUSDT"]}"#,
   r#"{"op":"subscribe","args":["allLiquidation.BTCUSDT"]}"#,
   r#"{"op":"subscribe","args":["publicTrade.BTCUSDT",{"x":1}]}"#,
   r#"{"op":"subscribe","args":["publicTrade.BTCUSDT"],"extra":1}"#,
   r#"{"op":"Subscribe","args":["publicTrade.BTCUSDT"]}"#,
  ] {
   assert_eq!(upward(bad),None,"{bad}");
  }
 }

 #[test]
 fn subscription_cap() {
  let mut subs=Subscriptions::default();
  let batch=|op:Op,from:usize,n:usize|Upward::Request{op,args:(from..from+n).map(|i|format!("publicTrade.C{i}USDT")).collect(),req_id:None};
  let mut filled=0;
  while filled<MAX_TOPICS {let n=MAX_ARGS.min(MAX_TOPICS-filled);assert!(subs.admit(&batch(Op::Subscribe,filled,n)));filled+=n;}
  assert!(subs.admit(&batch(Op::Subscribe,0,10)),"已经订着的再订不占新名额");
  assert!(!subs.admit(&batch(Op::Subscribe,MAX_TOPICS,1)),"超了上限的不放");
  assert!(subs.admit(&Upward::Ping{req_id:None}));
  assert!(subs.admit(&batch(Op::Unsubscribe,0,2)));
  assert!(subs.admit(&batch(Op::Subscribe,MAX_TOPICS,2)),"退订之后腾出名额");
 }
}
