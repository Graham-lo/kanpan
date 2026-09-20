//! 复盘裁定这条路的回归（报告 B.5 的 review_zero_observation…review_okx_daily_anchor）。
//!
//! 和 `review_worker.rs` 里那六条内嵌单测不同：这里每一条都**经过 SQL 队列**——
//! 真的建记录、真的让调度器认领一条任务、真的把结论写回库里再读出来。报告 D.6 指出
//! 那六条单测直接调 `domain::evaluate` / `trade_assessment`，绕过了异步 assess 的
//! 快捷分支，B-01 才能在满屏绿灯下活着。
mod review_common;
use chrono::Utc;
use review_common::*;
use scorebook_core::api::native_review::NativeRecord;
use serde_json::json;

/// 过去的第 n 根 K 线的开盘时刻。用例要的「到期」都必须落在过去，否则 worker 只会说等待。
fn past(interval:&str,bars_back:i64)->i64 {
 let size=size(interval);Utc::now().timestamp_millis()/size*size-bars_back*size
}

/// B-01：一根合规的观察收盘都排不出来时，不许判输。
///
/// 4 小时图，提交在 09:15（08:00 那根已经开了，按规则不算），到期在 13:15
/// （12:00 那根到期时还没收）。中间一根完整的观察收盘都没有，`end<=begin`。
/// 旧的快捷分支在这里直接写「到期未达到目标」判用户输；领域层在同样的输入下
/// （空证据 + 已到期）给的是待核实。没有证据不等于有证据证明没达标。
#[tokio::test]
async fn review_zero_observation() {
 let w=boot().await;let a=signup(&w.app,"zero").await;
 let id=place(&w,&a,&Spec{interval:"4h",..Spec::default()}).await;
 // 资格照常走建索引那条路算出来，免得「分母是 0」只是因为这条记录压根没合格。
 assert_eq!(index(&w,&a,id,&Market::wave()).await["eligible"],true);
 let base=past("4h",6);let submitted=base+75*60_000;let expires=submitted+14_400_000;
 retime(&w,&a,id,submitted,submitted,expires).await;
 let market=Market::silent();
 let record=assess(&w,&a,id,&market).await;
 assert_eq!(market.calls(),0,"窗口里排不出任何一根完整 K 线，就不该为它去取行情");
 assert_eq!(outcome(&record),"needs_verification","没有证据不等于有证据证明没达标：{record}");
 assert!(!matches!(outcome(&record).as_str(),"realized"|"unrealized"),"零有效观察绝不能判赢判输");
 // 和领域层对同一条输入的结论逐字一致——权威判断只有一份。
 let parsed:NativeRecord=serde_json::from_value(record.clone()).unwrap();
 let domain=kanpan_api::review_domain::evaluate(&parsed,&[],Utc::now().timestamp_millis()).unwrap();
 assert_eq!((outcome(&record),reason(&record)),(domain.outcome,domain.reason));
 assert!(event_at(&record).is_none(),"待核实没有事件时刻");
 // 窗口已经关了，再问多少次也排不出那根不存在的 K 线，任务要收掉，不能留一个幽灵。
 assert!(job(&w,&a,id,"assess").await.finished,"永远答不了的任务不许留在队列上");
 let stats=stats(&w,&a).await;
 assert_eq!(group_of(&stats["groups"],"BTCUSDT")["total"],0,"待核实不进正式分母：{stats}");
 w.close().await;
}

/// 第一个**有证据**的事件获胜，先目标和先失效各来一遍，eventAt 精确到那根的收盘毫秒。
#[tokio::test]
async fn review_first_proven_close() {
 let w=boot().await;let a=signup(&w.app,"first").await;
 let base=past("1h",8);let hour=3_600_000;
 for (symbol,rise,want,when) in [("BTCUSDT",true,"realized",1),("ETHUSDT",false,"unrealized",1)] {
  let id=place(&w,&a,&Spec{interval:"1h",symbol,..Spec::default()}).await;
  retime(&w,&a,id,base,base,base+3*hour).await;
  // 第一根就见分晓；后面两根一律给相反方向的极端价，证明「先到的那个」才算数。
  let bars=if rise {series(base,hour,&[(111.0,99.0,110.0),(101.0,89.0,90.0),(101.0,89.0,90.0)])}
   else {series(base,hour,&[(101.0,89.0,90.0),(111.0,99.0,110.0),(111.0,99.0,110.0)])};
  let record=assess(&w,&a,id,&Market::bars(bars)).await;
  assert_eq!(outcome(&record),want,"{symbol}：{record}");
  assert_eq!(event_at(&record),Some(base+when*hour),"eventAt 要正好是那根的收盘毫秒");
 }
 w.close().await;
}

/// 边界：提交那一刻已经开着的那根不算（差 1 毫秒也不算），到期之后才收的那根也不算。
#[tokio::test]
async fn review_bar_boundaries() {
 let w=boot().await;let a=signup(&w.app,"edge").await;
 let base=past("1h",8);let hour=3_600_000;
 // 提交晚了 1 毫秒：08:00 那根在提交时已经开着，哪怕它收在目标上也不作数。
 let late=place(&w,&a,&Spec{interval:"1h",symbol:"BTCUSDT",..Spec::default()}).await;
 retime(&w,&a,late,base,base+1,base+3*hour).await;
 let bars=series(base,hour,&[(111.0,99.0,110.0),(101.0,99.0,100.0),(101.0,99.0,100.0)]);
 let record=assess(&w,&a,late,&Market::bars(bars.clone())).await;
 assert_eq!(outcome(&record),"unrealized","提交时已开的那根不参与：{record}");
 assert_eq!(event_at(&record),Some(base+3*hour),"没达标就是到期那一刻定的");
 // 提交正好压在边界上：同一串行情，这一次 08:00 那根算数。
 let sharp=place(&w,&a,&Spec{interval:"1h",symbol:"ETHUSDT",..Spec::default()}).await;
 retime(&w,&a,sharp,base,base,base+3*hour).await;
 let record=assess(&w,&a,sharp,&Market::bars(bars)).await;
 assert_eq!(outcome(&record),"realized","压在边界上的提交把整根都算进来：{record}");
 assert_eq!(event_at(&record),Some(base+hour));
 // 到期早 1 毫秒：10:00 那根收在 11:00，比到期晚，赢不了。
 let early=place(&w,&a,&Spec{interval:"1h",symbol:"BNBUSDT",..Spec::default()}).await;
 retime(&w,&a,early,base,base,base+3*hour-1).await;
 let bars=series(base,hour,&[(101.0,99.0,100.0),(101.0,99.0,100.0),(111.0,99.0,110.0)]);
 let record=assess(&w,&a,early,&Market::bars(bars)).await;
 assert_eq!(outcome(&record),"unrealized","到期之后才收的那根不许追认：{record}");
 assert_eq!(event_at(&record),Some(base+3*hour-1),"epoch 就是 epoch，显示成哪个时区都不改它");
 w.close().await;
}

/// 缺行情一律待核实，绝不算输；补齐之后才允许进终态。
#[tokio::test]
async fn review_gap_is_not_loss() {
 let w=boot().await;let a=signup(&w.app,"gap").await;
 let base=past("1h",8);let hour=3_600_000;
 let id=place(&w,&a,&Spec{interval:"1h",..Spec::default()}).await;
 retime(&w,&a,id,base,base,base+3*hour).await;
 let full=series(base,hour,&[(101.0,99.0,100.0),(101.0,99.0,100.0),(111.0,99.0,110.0)]);
 for (what,market) in [
  ("漏首根",Market::bars(full[1..].to_vec())),
  ("漏中间",Market::bars(vec![full[0].clone(),full[2].clone()])),
  ("漏末根",Market::bars(full[..2].to_vec())),
  ("上游说自己没覆盖全",Market::partial(full.clone())),
 ] {
  let record=assess(&w,&a,id,&market).await;
  assert_eq!(outcome(&record),"needs_verification","{what}：{record}");
  assert!(event_at(&record).is_none(),"{what}：待核实不给事件时刻");
  assert!(!job(&w,&a,id,"assess").await.finished,"{what}：补得齐的缺口不该把任务关掉");
 }
 let record=assess(&w,&a,id,&Market::bars(full)).await;
 assert_eq!(outcome(&record),"realized","补齐之后才进终态：{record}");
 assert_eq!(event_at(&record),Some(base+3*hour));
 w.close().await;
}

/// 离线补录的资格边界：差 60 秒整还算，差 60 秒零 1 毫秒就不算；自报的补录时间一票否决。
/// 不合格不等于不裁定——它照样跑完，只是不进正式分母。
#[tokio::test]
async fn review_offline_eligibility() {
 let w=boot().await;let a=signup(&w.app,"offline").await;
 let base=past("1h",8);let hour=3_600_000;
 let mut ids=vec![];
 for (symbol,gap,claimed,want) in [("BTCUSDT",59_999i64,false,true),("ETHUSDT",60_000,false,true),("BNBUSDT",60_001,false,false),("SOLUSDT",0,true,false)] {
  let id=place(&w,&a,&Spec{interval:"1h",symbol,..Spec::default()}).await;
  // 想了两分钟才按保存、客户端把 created 重写成落笔那一刻——这条路仍然合格。
  retime(&w,&a,id,base-gap,base,base+3*hour).await;
  if claimed {patch(&w,&a,id,"{draft,originalClaimed}",json!(base-86_400_000)).await;}
  let record=index(&w,&a,id,&Market::wave()).await;
  assert_eq!(record["eligible"],want,"{symbol} 差 {gap} 毫秒、自报补录 {claimed}：{record}");
  ids.push((symbol,id,want));
 }
 // 合格与不合格的两条都跑完裁定，只有合格的那条进分母。
 let flat=series(base,hour,&[(101.0,99.0,100.0),(101.0,99.0,100.0),(101.0,99.0,100.0)]);
 for (symbol,id,want) in ids {
  if !matches!(symbol,"ETHUSDT"|"BNBUSDT") {continue}
  let record=assess(&w,&a,id,&Market::bars(flat.clone())).await;
  assert_eq!(outcome(&record),"unrealized","不合格也照样裁定：{record}");
  let stats=stats(&w,&a).await;
  let listed=stats["groups"].as_array().unwrap().iter().any(|g|g["title"].as_str().is_some_and(|t|t.contains(symbol)));
  assert_eq!(listed,want,"{symbol} 该不该出现在正式统计里：{stats}");
  if want {assert_eq!(group_of(&stats["groups"],symbol)["total"],1,"{stats}");}
 }
 w.close().await;
}

/// 补传时观察窗口已经结束：待核实，不凭空判错；任务就地收掉，正文与原始时间一个字不动。
#[tokio::test]
async fn review_expired_upload() {
 let w=boot().await;let a=signup(&w.app,"expired").await;
 let id=place(&w,&a,&Spec{interval:"1h",text:"补传的那一条",..Spec::default()}).await;
 let base=past("1h",8);
 retime(&w,&a,id,base,base+3_600_000,base+3_600_000).await;
 let market=Market::silent();
 let record=assess(&w,&a,id,&market).await;
 assert_eq!(market.calls(),0,"窗口早关了，不必为它出站取数");
 assert_eq!(outcome(&record),"needs_verification","{record}");
 assert_eq!(reason(&record),"补传时观察窗口已结束");
 assert!(job(&w,&a,id,"assess").await.finished,"这条任务再跑一万次也是同一句话");
 assert_eq!(record["draft"]["text"],"补传的那一条","正文原样保留");
 assert_eq!(record["submitted"],base+3_600_000,"原始时间原样保留");
 w.close().await;
}

/// 触价确认要有完整的精确成交序列才能定先后；序列不完整一律待核实。
#[tokio::test]
async fn review_trade_order() {
 let w=boot().await;let a=signup(&w.app,"trade").await;
 let base=past("1m",30);
 let touch=|symbol|Spec{interval:"1m",symbol,confirmation:"trade_touch",..Spec::default()};
 let cases=[
  ("BTCUSDT",json!([{"a":10,"T":base+1_000,"p":"111"},{"a":11,"T":base+2_000,"p":"89"}]),"realized",Some(base+1_000)),
  ("ETHUSDT",json!([{"a":10,"T":base+1_000,"p":"89"},{"a":11,"T":base+2_000,"p":"111"}]),"unrealized",Some(base+1_000)),
  // 同一毫秒的两笔：按已验证的成交序号定先后，不猜。
  ("BNBUSDT",json!([{"a":10,"T":base+1_000,"p":"89"},{"a":11,"T":base+1_000,"p":"111"}]),"unrealized",Some(base+1_000)),
  // 成交号断了一截：先目标还是先止损无从证明。
  ("SOLUSDT",json!([{"a":10,"T":base+1_000,"p":"111"},{"a":12,"T":base+2_000,"p":"89"}]),"needs_verification",None),
 ];
 for (symbol,raw,want,when) in cases {
  let id=place(&w,&a,&touch(symbol)).await;
  retime(&w,&a,id,base,base,base+3_600_000).await;
  let record=assess(&w,&a,id,&Market::ticks(json!({"coverage_complete":true,"raw":raw}))).await;
  assert_eq!(outcome(&record),want,"{symbol}：{record}");
  assert_eq!(event_at(&record),when,"{symbol}");
 }
 // 上游自己说这一段没取全：同样是待核实。
 let id=place(&w,&a,&touch("XRPUSDT")).await;
 retime(&w,&a,id,base,base,base+3_600_000).await;
 let record=assess(&w,&a,id,&Market::ticks(json!({"coverage_complete":false,"raw":[]}))).await;
 assert_eq!(outcome(&record),"needs_verification","{record}");
 assert_eq!(reason(&record),"成交数据尚不完整");
 // 只有粗 K 线时，一根同时碰到两条线，先后同样待核实——领域层这一句是上面那些的底线。
 let parsed:NativeRecord=serde_json::from_value(record).unwrap();
 let coarse=bar(base,60_000,111.0,89.0,100.0);
 let verdict=kanpan_api::review_domain::evaluate(&parsed,&[coarse],base+120_000).unwrap();
 assert_eq!(verdict.outcome,"needs_verification");
 assert_eq!(verdict.reason,"同根触达两条线，先后待核实");
 w.close().await;
}

/// OKX 的逐笔成交本建没有接：说清楚是待核实，并且**就此收手**——
/// 不许留一条每几秒重来一次、永远答不了、却被当成「还在跑」的任务。
#[tokio::test]
async fn review_okx_touch_policy() {
 let w=boot().await;let a=signup(&w.app,"okx").await;
 let id=place(&w,&a,&Spec{interval:"1m",venue:"okx",confirmation:"trade_touch",..Spec::default()}).await;
 let base=past("1m",30);
 retime(&w,&a,id,base,base,base+3_600_000).await;
 let market=Market::silent();
 let record=assess(&w,&a,id,&market).await;
 assert_eq!(market.calls(),0,"没接的能力不必去问上游");
 assert_eq!(outcome(&record),"needs_verification","{record}");
 assert_eq!(reason(&record),"成交顺序待核实");
 let row=job(&w,&a,id,"assess").await;
 assert!(row.finished,"未支持的能力不许生出一条永不完成的任务");
 assert_eq!(row.attempts,1,"它只该被认领过一次");
 assert!(!row.leased,"租约要还回去");
 assert!(!run(&w,&market).await,"队列里不该还剩下它");
 w.close().await;
}

/// 地区封锁不是抖动：退一天再来；一般的取不到才是退一分钟。两种都要把租约还回去。
#[tokio::test]
async fn review_regional_backoff() {
 let w=boot().await;let a=signup(&w.app,"blocked").await;
 let id=place(&w,&a,&Spec{interval:"1h",..Spec::default()}).await;
 let base=past("1h",8);
 retime(&w,&a,id,base,base,base+3*3_600_000).await;
 focus(&w,&a,id,"index").await;
 assert!(run(&w,&Market::refusing(Reply::Blocked)).await);
 let row=job(&w,&a,id,"index").await;
 assert!((row.delay-86_400.0).abs()<120.0,"建索引撞上封锁要退一天，实际 {} 秒",row.delay);
 assert!(!row.leased&&!row.finished,"退避不是放弃");
 let record=assess(&w,&a,id,&Market::refusing(Reply::Blocked)).await;
 assert_eq!(outcome(&record),"needs_verification","{record}");
 assert_eq!(reason(&record),"行情源在本节点被封锁");
 let row=job(&w,&a,id,"assess").await;
 assert!((row.delay-86_400.0).abs()<120.0,"裁定撞上封锁也退一天，实际 {} 秒",row.delay);
 assert!(!row.leased);
 let record=assess(&w,&a,id,&Market::refusing(Reply::Down)).await;
 assert_eq!(reason(&record),"行情待补齐","一般的不可用不是封锁：{record}");
 let row=job(&w,&a,id,"assess").await;
 assert!((row.delay-60.0).abs()<30.0,"一般的不可用退一分钟，实际 {} 秒",row.delay);
 assert!(!row.leased);
 w.close().await;
}

/// OKX 的日线锚点：一天从 UTC 零点开始，不许因为交易所在东八区就把它挪八小时。
/// 本机没有 8792 这个网关时，取不到数就是取不到数——绝不因此判错。
#[tokio::test]
async fn review_okx_daily_anchor() {
 let w=boot().await;let a=signup(&w.app,"anchor").await;
 let day=86_400_000i64;let midnight=Utc::now().timestamp_millis()/day*day;
 // 规范化之后仍旧是 UTC 日根：挪八小时的区间直接被挡在门外。
 let mut shifted=draft(&Spec{interval:"1d",venue:"okx",..Spec::default()});
 shifted["range"]["start"]=json!(midnight-4*day+8*3_600_000);
 shifted["range"]["end"]=json!(midnight-day+8*3_600_000);
 let (status,v)=request(&w.app,"/v1/native-review/records","POST",Some(&a.token),Some(uuid::Uuid::new_v4()),shifted).await;
 assert_eq!(status,400,"东八区的日界不是这里的日界：{v}");
 assert_eq!(v["error"]["code"],"invalid_chart_range");
 // 冻结区间照样收：它本来就锚在 UTC 零点上。
 let id=place(&w,&a,&Spec{interval:"1d",venue:"okx",reference:100.0,target:1_000_000_000.0,invalidation:0.000_001,..Spec::default()}).await;
 // 到期留在未来，这样无论网关在不在，都不可能出现「到期没达标」这种终态；
 // 于是断言「绝不判错」在两种环境下都成立。
 retime(&w,&a,id,midnight-3*day,midnight-3*day,Utc::now().timestamp_millis()+day).await;
 let record=assess(&w,&a,id,&Market::silent()).await;
 assert!(matches!(outcome(&record).as_str(),"needs_verification"|"waiting"),"取不到数不判错：{record}");
 assert!(event_at(&record).is_none());
 w.close().await;
}
