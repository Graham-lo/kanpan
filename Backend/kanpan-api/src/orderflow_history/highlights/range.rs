//! 区间（§11 ② 末段）：从现在往回扩 1 小时 K 线，箱子（高 − 低）≤ 3 × ATR(4h) 就继续，长度 ≥ 6 小时成立。
//! 不识别形态、不判断往哪边破。
use super::stats::{HOUR_MS,Hl};

pub(super) const RANGE_ATR:f64=3.0;
pub(super) const MIN_RANGE_MS:i64=6*HOUR_MS;

#[derive(Clone,Copy,Debug,PartialEq)]
pub(super) struct Range {pub low:f64,pub high:f64,pub since_ms:i64}

/// `hours` 按时间升序（最后一根可以是还没收完的这一小时）。ATR 没有或不为正时不成立。
pub(super) fn detect(hours:&[Hl],atr4h:Option<f64>,now:i64)->Option<Range> {
 let a=atr4h.filter(|a|*a>0.0&&a.is_finite())?;
 let (mut hi,mut lo,mut since)=(f64::NEG_INFINITY,f64::INFINITY,None);
 for b in hours.iter().rev() {
  if !(b.h>=b.l&&b.l>0.0) {break}
  let (h,l)=(hi.max(b.h),lo.min(b.l));
  if h-l>RANGE_ATR*a {break}
  hi=h;lo=l;since=Some(b.t);
 }
 let since=since?;
 (now-since>=MIN_RANGE_MS).then_some(Range{low:lo,high:hi,since_ms:since})
}

#[cfg(test)]
mod tests {
 use super::*;

 fn bar(i:i64,h:f64,l:f64)->Hl {Hl{t:i*HOUR_MS,h,l,c:(h+l)/2.0}}

 #[test]
 fn a_trend_then_a_box_starts_where_the_box_starts() {
  // 0..20 小时一路涨，20..32 小时在 120–124 来回。
  let mut hours:Vec<Hl>=(0..20).map(|i|bar(i,100.0+i as f64+1.0,100.0+i as f64)).collect();
  hours.extend((20..32).map(|i|bar(i,if i%2==0 {124.0} else {123.0},if i%2==0 {121.0} else {120.0})));
  let r=detect(&hours,Some(1.5),32*HOUR_MS).unwrap();
  assert_eq!((r.low,r.high),(120.0,124.0));
  // 往回扩到 19 号那根（119–120）箱子就成了 5，超过 3 × 1.5。
  assert_eq!(r.since_ms,20*HOUR_MS);
 }

 #[test]
 fn long_sideways_spans_all_the_history_it_has() {
  // 20 天横盘：每根在 99–101 之间摆。
  let hours:Vec<Hl>=(0..480).map(|i|bar(i,100.5+((i%5) as f64)*0.1,99.5-((i%3) as f64)*0.1)).collect();
  let r=detect(&hours,Some(1.0),480*HOUR_MS).unwrap();
  assert_eq!(r.since_ms,0);
  assert!(r.high-r.low<=3.0);
 }

 #[test]
 fn shorter_than_six_hours_or_no_atr_is_no_range() {
  let mut hours:Vec<Hl>=(0..10).map(|i|bar(i,100.0+i as f64*5.0+1.0,100.0+i as f64*5.0)).collect();
  hours.extend((10..14).map(|i|bar(i,151.0,150.0)));
  assert_eq!(detect(&hours,Some(1.0),14*HOUR_MS),None,"four hours of box");
  assert_eq!(detect(&hours,None,14*HOUR_MS),None);
 }
}
