//! 分位与 ATR：要点引擎里所有门槛都按品种自己的历史分位算（§11「门槛与跨品种」），不给用户调。
use std::collections::BTreeMap;

pub(super) const HOUR_MS:i64=3_600_000;
pub(super) const DAY_MS:i64=86_400_000;
/// 分位样本最多留 30 天。
pub(super) const KEEP_MS:i64=30*DAY_MS;
/// 样本跨度不够 3 天的分位一律为 null（不挡功能，攒够了自然出现）。
pub(super) const MIN_SPAN_MS:i64=3*DAY_MS;

/// 一项指标的分位样本：时刻 → 值（按小时取样，资金费率按结算时刻）。同一时刻再记一遍是覆盖。
#[derive(Clone,Debug,Default,PartialEq)]
pub(super) struct Samples(pub BTreeMap<i64,f32>);

impl Samples {
 pub fn put(&mut self,at:i64,x:f64) {
  if !x.is_finite() {return}
  self.0.insert(at,x as f32);
  let newest=self.0.last_key_value().map_or(at,|(t,_)|*t);
  while self.0.first_key_value().is_some_and(|(t,_)|*t<newest-KEEP_MS) {self.0.pop_first();}
 }
 #[cfg(test)]
 pub fn len(&self)->usize {self.0.len()}
 /// 样本跨度够不够（最早到最晚 ≥ 3 天，差一小时以内也算）。
 pub fn ready(&self)->bool {
  match (self.0.first_key_value(),self.0.last_key_value()) {
   (Some((a,_)),Some((b,_)))=>b-a>=MIN_SPAN_MS-HOUR_MS,
   _=>false,
  }
 }
 /// `x` 在样本里的分位（1–100，按并列折半算，见 [`rank`]）；跨度不够、或样本不到 [`MIN_DISTINCT`] 种值为 None。
 pub fn pctile(&self,x:f64)->Option<u8> {
  if !self.ready()||!x.is_finite() {return None}
  let values:Vec<f64>=self.0.values().map(|v|f64::from(*v)).collect();
  // 样本按 f32 存：先把 x 落到同一精度，不然和自己相等的那些样本对不上。
  rank(&values,f64::from(x as f32))
 }
 /// `x`（按样本的精度）是不是样本里出现最多的那个值——交易所默认费率这类「常态值」，永远不算异常。
 pub fn is_mode(&self,x:f64)->bool {
  let mut count:std::collections::HashMap<u32,usize>=std::collections::HashMap::new();
  for v in self.0.values() {*count.entry(v.to_bits()).or_default()+=1;}
  let Some(top)=count.values().copied().max() else {return false};
  count.get(&(x as f32).to_bits()).is_some_and(|n|*n==top)
 }
 /// 绝对值的 q 分位（背离门槛用 |净主动| 的 P60）；跨度不够或值太单一为 None。
 pub fn abs_quantile(&self,q:f64)->Option<f64> {
  if !self.ready() {return None}
  quantile_distinct(self.0.values().map(|v|f64::from(*v).abs()).collect(),q)
 }
 pub fn pairs(&self)->Vec<(i64,f32)> {self.0.iter().map(|(t,v)|(*t,*v)).collect()}
 pub fn from_pairs(pairs:&[(i64,f32)])->Self {Self(pairs.iter().filter(|(_,v)|v.is_finite()).copied().collect())}
}

/// 分位至少要这么多种不同的值才算（全是交易所默认费率这类样本，分位没有意义）。
pub(super) const MIN_DISTINCT:usize=10;

fn distinct(values:&[f64])->usize {
 let mut bits:Vec<u64>=values.iter().filter(|v|v.is_finite()).map(|v|(v+0.0).to_bits()).collect();
 bits.sort_unstable();
 bits.dedup();
 bits.len()
}

/// `x` 在 `values` 里的分位：(比它小的 + 一半和它相等的) ÷ 总数 × 100，四舍五入到 1–100（不出 0）。
/// 不到 [`MIN_DISTINCT`] 种值回 None——样本几乎全一样时「第 100 位」「第 0 位」是假的。
pub(super) fn rank(values:&[f64],x:f64)->Option<u8> {
 let values:Vec<f64>=values.iter().copied().filter(|v|v.is_finite()).collect();
 if !x.is_finite()||distinct(&values)<MIN_DISTINCT {return None}
 let less=values.iter().filter(|v|**v<x).count() as f64;
 let equal=values.iter().filter(|v|**v==x).count() as f64;
 Some((((less+0.5*equal)/values.len() as f64)*100.0).round().clamp(1.0,100.0) as u8)
}

/// 同 [`quantile`]，但不到 [`MIN_DISTINCT`] 种值回 None（拿来当「这只自己的常态」门槛的：背离 P60、爆仓中位数）。
pub(super) fn quantile_distinct(values:Vec<f64>,q:f64)->Option<f64> {
 if distinct(&values)<MIN_DISTINCT {return None}
 quantile(values,q)
}

/// 最近秩法的 q 分位（0 < q ≤ 1）。空的（或全不是有限数）回 None。
pub(super) fn quantile(mut values:Vec<f64>,q:f64)->Option<f64> {
 values.retain(|v|v.is_finite());
 if values.is_empty() {return None}
 values.sort_by(|a,b|a.total_cmp(b));
 let n=values.len();
 let i=((q*n as f64).ceil() as usize).clamp(1,n)-1;
 Some(values[i])
}

/// 一根 K 线：开始时刻、高、低、收。
#[derive(Clone,Copy,Debug,PartialEq)]
pub(super) struct Hl {pub t:i64,pub h:f64,pub l:f64,pub c:f64}

/// 简单平均的 ATR：最后 `n` 根的真实波幅（高低差与跨前收的缺口取大）求平均。根数不到 2 回 None。
pub(super) fn atr(bars:&[Hl],n:usize)->Option<f64> {
 if bars.len()<2 {return None}
 let start=bars.len().saturating_sub(n+1);
 let window=&bars[start..];
 let trs:Vec<f64>=window.windows(2).map(|w|{let (p,b)=(w[0],w[1]);(b.h-b.l).max((b.h-p.c).abs()).max((b.l-p.c).abs())}).filter(|x|x.is_finite()).collect();
 if trs.is_empty() {return None}
 Some(trs.iter().sum::<f64>()/trs.len() as f64)
}

/// 小时线并成对齐 UTC 的 4 小时线。
pub(super) fn four_hour(hours:&[Hl])->Vec<Hl> {
 let mut out:Vec<Hl>=Vec::new();
 for b in hours {
  let t=b.t.div_euclid(4*HOUR_MS)*4*HOUR_MS;
  match out.last_mut() {
   Some(last) if last.t==t=>{last.h=last.h.max(b.h);last.l=last.l.min(b.l);last.c=b.c;},
   _=>out.push(Hl{t,..*b}),
  }
 }
 out
}

/// 墙规模的直方图（只为分位，不留每一堵）：每 3 小时一格，每格按 log10 每十倍分 16 段计数；留 3 天。
/// ETH 3 天结束的墙有 12 万多堵，全留在内存里、起步全读一遍不值；分段的分辨率约 15%，做门槛与排序够了。
#[derive(Clone,Debug,Default,PartialEq)]
pub(super) struct Sizes(pub BTreeMap<i64,BTreeMap<i16,u32>>);

pub(super) const SIZE_BLOCK_MS:i64=3*HOUR_MS;
pub(super) const SIZE_KEEP_MS:i64=3*DAY_MS;
const SIZE_BINS:f64=16.0;

pub(super) fn size_bin(usd:f64)->Option<i16> {(usd.is_finite()&&usd>0.0).then(||(usd.log10()*SIZE_BINS).floor() as i16)}

impl Sizes {
 pub fn add(&mut self,at:i64,usd:f64) {self.add_n(at.div_euclid(SIZE_BLOCK_MS)*SIZE_BLOCK_MS,size_bin(usd),1);}
 pub fn add_n(&mut self,block:i64,bin:Option<i16>,n:u32) {
  let Some(bin)=bin else {return};
  *self.0.entry(block).or_default().entry(bin).or_default()+=n;
 }
 pub fn trim(&mut self,now:i64) {while self.0.first_key_value().is_some_and(|(t,_)|*t<now-SIZE_KEEP_MS) {self.0.pop_first();}}
 fn merged(&self)->BTreeMap<i16,u64> {
  let mut out:BTreeMap<i16,u64>=BTreeMap::new();
  for block in self.0.values() {for (b,n) in block {*out.entry(*b).or_default()+=u64::from(*n);}}
  out
 }
 pub fn count(&self)->u64 {self.0.values().flat_map(|b|b.values()).map(|n|u64::from(*n)).sum()}
 /// q 分位落在的那一段的下沿（美元）；空的、或不到 [`MIN_DISTINCT`] 段有数回 None。
 pub fn quantile(&self,q:f64)->Option<f64> {
  let merged=self.merged();
  let total:u64=merged.values().sum();
  if total==0||merged.len()<MIN_DISTINCT {return None}
  let need=((q*total as f64).ceil() as u64).clamp(1,total);
  let mut seen=0;
  for (b,n) in merged {seen+=n;if seen>=need {return Some(10f64.powf(f64::from(b)/SIZE_BINS))}}
  None
 }
 /// `usd` 的分位（1–100，同一段的折半算，口径同 [`rank`]）；不到 [`MIN_DISTINCT`] 段有数回 None。
 pub fn rank(&self,usd:f64)->Option<u8> {
  let merged=self.merged();
  let total:u64=merged.values().sum();
  let bin=size_bin(usd)?;
  if total==0||merged.len()<MIN_DISTINCT {return None}
  let less:u64=merged.range(..bin).map(|(_,n)|*n).sum();
  let equal=merged.get(&bin).copied().unwrap_or(0);
  Some((((less as f64+0.5*equal as f64)/total as f64)*100.0).round().clamp(1.0,100.0) as u8)
 }
}

#[cfg(test)]
mod tests {
 use super::*;

 #[test]
 fn percentile_is_null_until_three_days_of_samples() {
  let mut s=Samples::default();
  for h in 0..48 {s.put(h*HOUR_MS,h as f64);}
  assert_eq!(s.pctile(10.0),None,"two days is not enough");
  assert_eq!(s.abs_quantile(0.6),None);
  for h in 48..72 {s.put(h*HOUR_MS,h as f64);}
  // 0..=71 小时：跨度 71 小时（差一小时以内算够）。
  assert!(s.ready());
  assert_eq!(s.pctile(71.0),Some(99),"the top sample counts half of itself");
  assert_eq!(s.pctile(-1.0),Some(1),"never 0");
  assert_eq!(s.pctile(1000.0),Some(100));
  assert_eq!(s.pctile(35.5),Some(50));
 }

 #[test]
 fn samples_keep_thirty_days_and_overwrite_same_hour() {
  let mut s=Samples::default();
  for h in 0..(40*24) {s.put(h*HOUR_MS,1.0);}
  assert_eq!(s.len(),30*24+1);
  s.put(40*24*HOUR_MS-HOUR_MS,5.0);
  assert_eq!(s.len(),30*24+1);
  assert_eq!(s.0.last_key_value().map(|(_,v)|*v),Some(5.0));
 }

 #[test]
 fn quantile_and_rank() {
  let v=vec![5.0,1.0,4.0,2.0,3.0];
  assert_eq!(quantile(v.clone(),0.6),Some(3.0));
  assert_eq!(quantile(v,1.0),Some(5.0));
  assert_eq!(quantile(vec![f64::NAN],0.5),None);
  let ten:Vec<f64>=(1..=10).map(f64::from).collect();
  assert_eq!(rank(&ten,2.0),Some(15),"one below, itself counts half");
  assert_eq!(rank(&[1.0,2.0,3.0,4.0],2.0),None,"fewer than ten distinct values");
  assert_eq!(quantile_distinct(vec![1.0;50],0.9),None);
  assert_eq!(quantile(vec![1.0;50],0.9),Some(1.0));
 }

 #[test]
 fn atr_and_four_hour_bars() {
  let hours:Vec<Hl>=(0..8).map(|i|Hl{t:i*HOUR_MS,h:102.0,l:98.0,c:100.0}).collect();
  assert_eq!(atr(&hours,14),Some(4.0));
  let four=four_hour(&hours);
  assert_eq!(four.len(),2);
  assert_eq!(four[1].t,4*HOUR_MS);
  assert_eq!(atr(&hours[..1],14),None);
 }
 #[test]
 fn size_histogram_quantile_rank_and_trim() {
  let mut s=Sizes::default();
  for i in 0..90 {s.add(0,100_000.0+i as f64);}
  for _ in 0..10 {s.add(HOUR_MS,10_000_000.0);}
  assert_eq!(s.count(),100);
  assert_eq!(s.quantile(0.9),None,"two size bins are not a distribution");
  assert_eq!(s.rank(100_000.0),None);
  for i in 0..10 {s.add(2*HOUR_MS,10f64.powf(3.0+f64::from(i)*0.25));}
  assert!(s.quantile(0.5).is_some());
  assert_eq!(s.rank(1e12),Some(100));
  s.add(4*DAY_MS,1.0);
  s.trim(4*DAY_MS);
  assert_eq!(s.count(),1);
 }

 #[test]
 fn tie_heavy_series_do_not_rank_the_common_value_as_extreme() {
  // 30 天费率：九成是交易所默认的 0.005%，其余零散分布在 -0.01% … +0.02%。
  let mut s=Samples::default();
  let mut h=0;
  for i in 0..720 {
   let v=if i%10==0 {-0.0001+f64::from(i/10)*0.000_004} else {0.000_05};
   s.put(h*HOUR_MS,v);h+=1;
  }
  let p=s.pctile(0.000_05).unwrap();
  assert!((40..=90).contains(&p),"the default rate sits mid-pack, not at 100: {p}");
  assert!(s.is_mode(0.000_05));
  assert!(!s.is_mode(0.0002));
  assert_eq!(s.pctile(0.01),Some(100));
  // 全一样：没有分位。
  let mut flat=Samples::default();
  for h in 0..100 {flat.put(h*HOUR_MS,0.000_05);}
  assert_eq!(flat.pctile(0.000_05),None);
  assert_eq!(flat.abs_quantile(0.6),None);
 }
}
