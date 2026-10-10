//! 近 4 小时事件（§11 ④，≤ 4 条，时间倒序）：
//! * 墙被吃穿（成交 ≥ 60%）/ 墙撤单（撤 ≥ 80% 且撤时距价 ≤ 0.1%）；
//! * 主动成交集中段：5 分钟滑窗净额，连续一段 |滑窗| ≥ 近 3 天 P95（段里含局部峰）；
//! * 爆仓潮：同法，用多空爆仓合计；
//! * 持仓 5 分钟跳变 ≥ 1%（相邻同向的并成一次）；
//! * 关键价位被破（账本里的格已破，见 `ledger.rs`）。
//!
//! 重叠的同类时段并一段；同一堵墙只出一次（挂着时在价位里，结束后才变事件；几家同一价位同一刻结束的并成一条）。
use super::ledger;
use super::stats::quantile;
use std::collections::BTreeMap;

pub(super) const WINDOW_MS:i64=4*3_600_000;
pub(super) const MAX_EVENTS:usize=4;
pub(super) const SLIDE:usize=5;
pub(super) const BURST_Q:f64=0.95;
/// 分位至少要一天的分钟才算（3 天窗口没攒满时用已有的）。
pub(super) const BURST_MIN_MINUTES:usize=1440;
pub(super) const EATEN:f64=0.6;
pub(super) const CANCELLED:f64=0.8;
pub(super) const CANCEL_NEAR:f64=0.001;
pub(super) const OI_JUMP_PCT:f64=1.0;
/// 几家同一价位、这么近的时间里结束的墙算同一堵。
const SAME_WALL_MS:i64=120_000;
const M:i64=60_000;

/// 一段时段（滑窗连续过门槛的那一段）。`sum` 是段内分钟值之和，`peak` 是段里 |滑窗| 的最大值。
#[derive(Clone,Copy,Debug,PartialEq)]
pub(super) struct Span {pub from:i64,pub to:i64,pub sum:f64,pub peak:f64}

/// 5 分钟滑窗和：`s[i] = v[i-4] + … + v[i]`（开头不满 5 根的照加有的）。
pub(super) fn sliding(values:&[f64])->Vec<f64> {
 let mut out=Vec::with_capacity(values.len());
 let mut sum=0.0;
 for (i,v) in values.iter().enumerate() {
  sum+=v;
  if i>=SLIDE {sum-=values[i-SLIDE];}
  out.push(sum);
 }
 out
}

/// 门槛：|滑窗| 的 P95。分钟不到一天、或 P95 不为正时为 None（不出这一类事件）。
pub(super) fn threshold(slides:&[f64])->Option<f64> {
 if slides.len()<BURST_MIN_MINUTES {return None}
 quantile(slides.iter().map(|s|s.abs()).collect(),BURST_Q).filter(|q|*q>0.0)
}

/// `values` 是从 `t0` 起每分钟一个的序列；找 `since` 以后 |滑窗| ≥ `thr` 的连续同号段，重叠的同号段并起来。
pub(super) fn spans(t0:i64,values:&[f64],thr:f64,since:i64)->Vec<Span> {
 let slides=sliding(values);
 let mut runs:Vec<(usize,usize,f64,f64)>=Vec::new(); // 起、止（含）、号、峰
 for (i,s) in slides.iter().enumerate() {
  let t=t0+i as i64*M;
  if t<since||s.abs()<thr||*s==0.0 {continue}
  let sign=s.signum();
  match runs.last_mut() {
   Some(r) if r.1+1==i&&r.2==sign=>{r.1=i;r.3=r.3.max(s.abs());},
   _=>runs.push((i,i,sign,s.abs())),
  }
 }
 let mut out:Vec<(usize,usize,f64,f64)>=Vec::new();
 for (a,b,sign,peak) in runs {
  let from=a.saturating_sub(SLIDE-1);
  match out.last_mut() {
   // 滑窗往回看 4 分钟，两段的时段重叠就并成一段。
   Some(r) if r.2==sign&&from<=r.1=>{r.1=b;r.3=r.3.max(peak);},
   _=>out.push((from,b,sign,peak)),
  }
 }
 out.into_iter().map(|(a,b,_,peak)|Span{from:t0+a as i64*M,to:t0+(b as i64+1)*M,sum:values[a..=b].iter().sum(),peak}).collect()
}

/// 持仓跳变：相邻两点变化 ≥ 1% 的，连着同向的并成一次。回（第一跳的时刻, 最后一点的时刻, 累计变化 %）。
pub(super) fn oi_jumps(oi:&BTreeMap<i64,f64>,since:i64)->Vec<(i64,i64,f64)> {
 let points:Vec<(i64,f64)>=oi.iter().filter(|(_,v)|**v>0.0).map(|(t,v)|(*t,*v)).collect();
 let mut out:Vec<(i64,i64,f64,f64)>=Vec::new(); // 第一跳、最后一点、起点值、终点值
 let mut last_jump:Option<usize>=None;
 for (i,w) in points.windows(2).enumerate() {
  let ((_,a),(t,b))=(w[0],w[1]);
  if t<since {continue}
  let pct=(b/a-1.0)*100.0;
  if pct.abs()<OI_JUMP_PCT {continue}
  match (out.last_mut(),last_jump) {
   (Some(j),Some(prev)) if prev+1==i&&(j.3/j.2-1.0).signum()==pct.signum()=>{j.1=t;j.3=b;},
   _=>out.push((t,t,a,b)),
  }
  last_jump=Some(i);
 }
 out.into_iter().map(|(first,t,a,b)|(first,t,(b/a-1.0)*100.0)).collect()
}

/// 账本里被破的格 → 「价位被破」事件：同一侧、键相邻、15 分钟内相继破的格是同一条价位被打穿（一根大阴线会连破好几格），
/// 并成一条；`id` 用这一串里最早破的那一格（时刻 + 键），后面再并进来的格不改它。
pub(super) fn broken_events(broken:&[ledger::Broke])->Vec<Ev> {
 const SAME_BREAK_MS:i64=15*M;
 let mut sorted:Vec<&ledger::Broke>=broken.iter().collect();
 sorted.sort_by_key(|b|(b.at,b.k));
 // (第一格的时刻, 第一格的键, 最近一次破的时刻, 键的下沿, 键的上沿, 原来是支撑)
 let mut groups:Vec<(i64,i64,i64,i64,i64,bool)>=Vec::new();
 for b in sorted {
  match groups.iter_mut().rev().find(|g|g.5==b.was_support&&b.at-g.2<=SAME_BREAK_MS&&b.k>=g.3-1&&b.k<=g.4+1) {
   Some(g)=>{g.2=b.at;g.3=g.3.min(b.k);g.4=g.4.max(b.k);},
   None=>groups.push((b.at,b.k,b.at,b.k,b.k,b.was_support)),
  }
 }
 groups.into_iter().map(|(first,k,at,lo,hi,was_support)|Ev::Broken{first,k,at,low:super::state::sig(ledger::low(lo)),high:super::state::sig(ledger::high(hi)),was_support}).collect()
}

/// 结束了的一堵墙（要点引擎从写库那一步拿一份）。
#[derive(Clone,Debug,PartialEq)]
pub(super) struct Ended {pub bid:bool,pub price:f64,pub initial:f64,pub filled:f64,pub left:f64,pub cancelled:bool,pub end:i64}

/// 够不够得上墙事件的规则（不看规模、不看撤时离价多远）：成交 ≥ 60%，或撤单 ≥ 80%。
pub(super) fn candidate(e:&Ended)->bool {
 e.initial>0.0&&(e.filled/e.initial>=EATEN||(e.cancelled&&(e.initial-e.filled-e.left).max(0.0)/e.initial>=CANCELLED))
}

/// 墙事件：被吃穿 / 撤单。`px_at(t)` 给那一刻的价；`floor` 是这只的墙规模门槛（不够格的不进事件）。
/// 同一价位格、同一侧、同一类、2 分钟内结束的几条并成一条（几家同时撤 / 同一堵墙读回后又结束一次）。
pub(super) fn wall_events(ended:&[Ended],px_at:impl Fn(i64)->Option<f64>,floor:f64,since:i64)->Vec<Ev> {
 let mut out:Vec<Ev>=Vec::new();
 let mut sorted:Vec<&Ended>=ended.iter().filter(|e|e.end>=since&&e.initial>0.0&&e.price>0.0).collect();
 sorted.sort_by_key(|e|e.end);
 for e in sorted {
  let eaten=e.filled/e.initial>=EATEN;
  let cancel=!eaten&&e.cancelled&&(e.initial-e.filled-e.left).max(0.0)/e.initial>=CANCELLED
   &&px_at(e.end).is_some_and(|p|p>0.0&&((e.price-p)/p).abs()<=CANCEL_NEAR);
  if !(eaten||cancel) {continue}
  let kind=if eaten {"wallEaten"} else {"wallCancel"};
  let k=ledger::key(e.price);
  if let Some(Ev::Wall{usd,at,..})=out.iter_mut().rev().find(|x|matches!(x,Ev::Wall{kind:kk,k:kk2,bid,at,..} if *kk==kind&&*kk2==k&&*bid==e.bid&&e.end-*at<=SAME_WALL_MS)) {
   *usd+=e.initial;*at=e.end;continue;
  }
  out.push(Ev::Wall{kind,first:e.end,at:e.end,price:e.price,usd:e.initial,bid:e.bid,k});
 }
 out.retain(|e|matches!(e,Ev::Wall{usd,..} if *usd>=floor));
 out
}

/// 一条事件（结构化事实，文案由客户端按 terms.json 拼）。
#[derive(Clone,Debug,PartialEq)]
pub(super) enum Ev {
 /// `first` 是这一组里最早结束的那堵（id 用它，几家相继结束并进来不改 id）；`at` 是最后一堵结束的时刻。
 Wall{kind:&'static str,first:i64,at:i64,price:f64,usd:f64,bid:bool,k:i64},
 Flow{from:i64,to:i64,net:f64,px_pct:Option<f64>,pctile:u8},
 Liq{from:i64,to:i64,usd:f64,long:bool,px_pct:Option<f64>,pctile:u8},
 /// `first` 是第一跳的时刻，`at` 是连着同向的最后一点。
 Oi{first:i64,at:i64,pct:f64},
 /// `first` / `k` 是最早破的那一格，`at` 是这一串里最近一次破。
 Broken{first:i64,k:i64,at:i64,low:f64,high:f64,was_support:bool},
}

impl Ev {
 /// 排序用的时刻：时段取结束。
 pub fn time(&self)->i64 {
  match self {Ev::Wall{at,..}|Ev::Oi{at,..}|Ev::Broken{at,..}=>*at,Ev::Flow{to,..}|Ev::Liq{to,..}=>*to}
 }
 pub fn kind(&self)->&'static str {
  match self {Ev::Wall{kind,..}=>kind,Ev::Flow{..}=>"flowBurst",Ev::Liq{..}=>"liqWave",Ev::Oi{..}=>"oiJump",Ev::Broken{..}=>"levelBroken"}
 }
 /// 稳定、唯一的 id：只用事实开头那一刻定下来的东西（墙：最早结束的时刻 + 侧 + 价位格；时段：开始；持仓：第一跳；
 /// 价位被破：最早破的格的时刻 + 键）。时段往后延、同一组再并进来都不改它，每分钟重算出来的是同一个。
 pub fn id(&self)->String {
  match self {
   Ev::Wall{kind,first,bid,k,..}=>format!("E:{kind}:{first}:{}:{k}",if *bid {"b"} else {"s"}),
   Ev::Flow{from,..}|Ev::Liq{from,..}=>format!("E:{}:{from}",self.kind()),
   Ev::Oi{first,..}=>format!("E:oiJump:{first}"),
   Ev::Broken{first,k,..}=>format!("E:levelBroken:{first}:{k}"),
  }
 }
 pub fn json(&self,price:f64)->serde_json::Value {
  use serde_json::json;
  let dist=|p:f64|if price>0.0 {Some(round((p-price)/price*100.0,3))} else {None};
  let id=self.id();
  match self {
   Ev::Wall{kind,at,price:p,usd:amount,bid,..}=>json!({"id":id,"t":kind,"atMs":at,"price":p,"usd":usd(*amount),"side":if *bid {"buy"} else {"sell"},"distPct":dist(*p)}),
   Ev::Flow{from,to,net,px_pct,..}=>json!({"id":id,"t":"flowBurst","fromMs":from,"toMs":to,"netUsd":usd(*net),"pxPct":px_pct.map(|v|round(v,2))}),
   Ev::Liq{from,to,usd:amount,long,px_pct,..}=>json!({"id":id,"t":"liqWave","fromMs":from,"toMs":to,"usd":usd(*amount),"side":if *long {"long"} else {"short"},"pxPct":px_pct.map(|v|round(v,2))}),
   Ev::Oi{at,pct,..}=>json!({"id":id,"t":"oiJump","atMs":at,"pct":round(*pct,2)}),
   Ev::Broken{at,low,high,was_support,..}=>json!({"id":id,"t":"levelBroken","atMs":at,"low":low,"high":high,"side":if *was_support {"bid"} else {"ask"},"distPct":dist((low+high)/2.0)}),
  }
 }
}

/// 近 4 小时、≤ 4 条、时间倒序。
pub(super) fn newest(mut all:Vec<Ev>,now:i64)->Vec<Ev> {
 all.retain(|e|e.time()>=now-WINDOW_MS);
 all.sort_by(|a,b|b.time().cmp(&a.time()).then(a.kind().cmp(b.kind())).then_with(||a.id().cmp(&b.id())));
 // 兜底：同一个 id 只留一条（上面的 id 已经各不相同，这里保证客户端拿到的永远唯一）。
 let mut seen=std::collections::HashSet::new();
 all.retain(|e|seen.insert(e.id()));
 all.truncate(MAX_EVENTS);
 all
}

pub(super) fn round(v:f64,digits:i32)->f64 {let f=10f64.powi(digits);(v*f).round()/f+0.0}
/// 金额取整；`+ 0.0` 把空和（Rust 浮点 `sum` 的起点是 -0.0）写成 0 而不是 -0。
pub(super) fn usd(v:f64)->f64 {v.round()+0.0}

#[cfg(test)]
mod tests {
 use super::*;

 #[test]
 fn bursts_are_contiguous_runs_over_the_p95_and_overlaps_merge() {
  // 一天平静（每 20 分钟一笔 3），然后一段放量。
  let calm:Vec<f64>=(0..1440).map(|i|if i%20==0 {3.0} else {0.0}).collect();
  let burst_at=calm.len() as i64;
  let mut v=calm.clone();
  v.extend([50.0,50.0,50.0,0.0,0.0,0.0,40.0,40.0]);
  v.extend((0..30).map(|_|0.0));
  let thr=threshold(&sliding(&v)).unwrap();
  assert_eq!(thr,3.0);
  let found=spans(0,&v,thr+1.0,burst_at*M);
  assert_eq!(found.len(),1);
  let s=found[0];
  assert_eq!(s.from,(burst_at-4)*M,"the span starts where its first 5-minute window starts");
  assert_eq!(s.sum,230.0);
  assert_eq!(s.peak,150.0);
  // 两段之间滑窗掉到门槛以下，但时段重叠：并成一段。
  let mut w=calm;
  w.extend([50.0,0.0,0.0,0.0,0.0,0.0,0.0,50.0]);
  w.extend((0..10).map(|_|0.0));
  let merged=spans(0,&w,10.0,burst_at*M);
  assert_eq!(merged.len(),1);
  assert_eq!((merged[0].sum,merged[0].peak),(100.0,50.0));
  // 不重叠的两段是两段。
  let mut x:Vec<f64>=vec![0.0;1440];
  x.extend([50.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,50.0]);
  assert_eq!(spans(0,&x,10.0,burst_at*M).len(),2);
 }

 #[test]
 fn too_little_history_has_no_threshold() {
  assert_eq!(threshold(&sliding(&[1.0;600])),None);
  assert_eq!(threshold(&sliding(&[0.0;2000])),None,"a flat line has no positive P95");
 }

 #[test]
 fn oi_jumps_merge_consecutive_same_direction() {
  let mut oi=BTreeMap::new();
  for (i,v) in [100.0,100.2,101.5,103.0,103.1,101.0,101.1].iter().enumerate() {oi.insert(i as i64*300_000,*v);}
  let j=oi_jumps(&oi,0);
  assert_eq!(j.len(),2);
  assert_eq!((j[0].0,j[0].1),(2*300_000,3*300_000),"first jump and the last point of the run");
  assert!((j[0].2-(103.0/100.2-1.0)*100.0).abs()<1e-9);
  assert!(j[1].2 < -1.0);
 }

 #[test]
 fn walls_dedup_across_venues_and_filter_by_rule() {
  let px=|_|Some(100.0);
  let e=|price:f64,initial:f64,filled:f64,left:f64,cancelled:bool,end:i64|Ended{bid:false,price,initial,filled,left,cancelled,end};
  let ended=vec![
   e(100.05,2e6,0.0,0.0,true,10*M),   // 撤 100%，距价 0.05%：撤单
   e(100.05,1e6,0.0,0.0,true,11*M),   // 另一家同一格、一分钟后：并进上一条
   e(101.0,2e6,0.0,0.0,true,12*M),    // 距价 1%：不算
   e(100.0,2e6,1.3e6,0.0,false,13*M), // 成交 65%：吃穿
   e(100.0,2e6,1.0e6,0.0,false,14*M), // 成交 50%：不算
   e(99.0,1e5,1e5,0.0,false,15*M),    // 吃穿但太小
  ];
  let evs=wall_events(&ended,px,5e5,0);
  assert_eq!(evs.len(),2);
  assert!(matches!(evs[0],Ev::Wall{kind:"wallCancel",usd,at,first,..} if usd==3e6&&at==11*M&&first==10*M));
  assert!(matches!(evs[1],Ev::Wall{kind:"wallEaten",..}));
  assert_eq!(evs[0].id(),wall_events(&ended[..1],px,5e5,0)[0].id(),"merging a later wall does not change the id");
 }

 #[test]
 fn walls_ending_in_the_same_millisecond_at_different_prices_get_different_ids() {
  let e=|bid:bool,price:f64|Ended{bid,price,initial:2e6,filled:2e6,left:0.0,cancelled:false,end:5*M};
  let evs=wall_events(&[e(false,100.0),e(false,101.0),e(true,99.0)],|_|Some(100.0),0.0,0);
  assert_eq!(evs.len(),3);
  let ids:std::collections::HashSet<String>=evs.iter().map(Ev::id).collect();
  assert_eq!(ids.len(),3,"{ids:?}");
 }

 #[test]
 fn adjacent_buckets_breaking_together_are_one_event_with_a_stable_id() {
  let br=|k:i64,at:i64|ledger::Broke{k,at,was_support:true};
  // 一根大阴线连破三格（同一分钟两格、下一分钟一格），另有一格两小时后在别处破。
  let first=broken_events(&[br(10,5*M),br(11,5*M)]);
  let later=broken_events(&[br(10,5*M),br(11,5*M),br(9,6*M),br(40,125*M)]);
  assert_eq!(first.len(),1);
  assert_eq!(later.len(),2);
  assert_eq!(first[0].id(),later[0].id(),"a bucket joining later does not change the id");
  assert!(matches!(later[0],Ev::Broken{at,..} if at==6*M));
  assert_ne!(later[0].id(),later[1].id());
 }

 #[test]
 fn spans_and_oi_runs_keep_their_id_while_they_extend() {
  let a=Ev::Flow{from:M,to:5*M,net:1.0,px_pct:None,pctile:96};
  let b=Ev::Flow{from:M,to:9*M,net:2.0,px_pct:None,pctile:97};
  assert_eq!(a.id(),b.id());
  assert_eq!(Ev::Oi{first:M,at:2*M,pct:1.2}.id(),Ev::Oi{first:M,at:3*M,pct:2.0}.id());
  assert_ne!(a.id(),Ev::Liq{from:M,to:5*M,usd:1.0,long:true,px_pct:None,pctile:96}.id());
 }

 #[test]
 fn newest_four_in_reverse_time_within_four_hours() {
  let now=10*3_600_000;
  let evs:Vec<Ev>=(0..8).map(|i|Ev::Oi{first:now-i*3_600_000/2-1,at:now-i*3_600_000/2-1,pct:1.5}).collect();
  let kept=newest(evs,now);
  assert_eq!(kept.len(),4);
  assert!(kept.windows(2).all(|w|w[0].time()>w[1].time()));
  assert!(kept.iter().all(|e|e.time()>=now-WINDOW_MS));
 }
}
