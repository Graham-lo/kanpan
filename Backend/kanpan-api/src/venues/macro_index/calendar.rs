//! ICE 美元指数的交易时段与交易日，全部按美东时间（America/New_York）算。
//!
//! - 一周：周日 18:00 ET 开，周五 17:00 ET 收；
//! - 每天：17:00–18:00 ET 停一小时（周一到周四）；
//! - **交易日**：一段 18:00 → 次日 17:00 的连续交易算「次日」那一天。周日 18:00 开的那段是周一，
//!   周四 18:00 开、周五 17:00 收的那段是周五。ICE 的官方日线就是这么切的，CNBC 的 `1D` 也是。
//!
//! 夏令时手写，不引 chrono-tz：美国规则自 2007 年起固定为三月第二个周日 02:00（EST）起、
//! 十一月第一个周日 02:00（EDT）止。服务端只在 17:00 / 18:00 / 00:00 这几个钟点上换算，
//! 碰不到 01:00–02:00 那一小时的歧义。节假日不在日历里：节假日没有报价，`marketState`
//! 由「日历开着且最近十分钟有过价」判（见 `collector`），自然落到 closed。
use chrono::{DateTime,Datelike,Duration,NaiveDate,NaiveDateTime,Timelike,Weekday};

pub const MINUTE_MS:i64=60_000;
pub const HOUR_MS:i64=3_600_000;
pub const DAY_MS:i64=86_400_000;
/// 每天停盘与周五收盘的钟点（ET）。
pub const CLOSE_HOUR:u32=17;
/// 每天复盘与周日开盘的钟点（ET）。
pub const OPEN_HOUR:u32=18;

fn nth_sunday(year:i32,month:u32,n:u32)->NaiveDate {
 let first=NaiveDate::from_ymd_opt(year,month,1).unwrap_or_default();
 let to_sunday=(7-first.weekday().num_days_from_sunday())%7;
 first+Duration::days((to_sunday+7*(n-1)) as i64)
}

/// 这一年夏令时的起止（UTC 毫秒，左闭右开）：三月第二个周日 07:00 UTC（= 02:00 EST）到
/// 十一月第一个周日 06:00 UTC（= 02:00 EDT）。
pub fn dst_bounds(year:i32)->(i64,i64) {
 let at=|d:NaiveDate,h:u32|d.and_hms_opt(h,0,0).unwrap_or_default().and_utc().timestamp_millis();
 (at(nth_sunday(year,3,2),7),at(nth_sunday(year,11,1),6))
}

/// 这一刻美东相对 UTC 的偏移：夏令时 −4 小时，其余 −5 小时。
pub fn offset_ms(utc_ms:i64)->i64 {
 let year=DateTime::from_timestamp_millis(utc_ms).map(|d|d.year()).unwrap_or(1970);
 let (start,end)=dst_bounds(year);
 if (start..end).contains(&utc_ms) {-4*HOUR_MS} else {-5*HOUR_MS}
}

/// UTC 毫秒 → 美东墙上时间。
pub fn local(utc_ms:i64)->NaiveDateTime {
 DateTime::from_timestamp_millis(utc_ms+offset_ms(utc_ms)).unwrap_or_default().naive_utc()
}

/// 美东墙上时间 → UTC 毫秒。先按夏令时试，换算回去落在夏令时里就是它，否则按标准时间。
pub fn utc_of(local:NaiveDateTime)->i64 {
 let naive=local.and_utc().timestamp_millis();
 let daylight=naive+4*HOUR_MS;
 if offset_ms(daylight)==-4*HOUR_MS {daylight} else {naive+5*HOUR_MS}
}

/// 日历上此刻开不开盘。
pub fn is_open(utc_ms:i64)->bool {
 let t=local(utc_ms);
 let hour=t.hour();
 match t.weekday() {
  Weekday::Sat=>false,
  Weekday::Sun=>hour>=OPEN_HOUR,
  Weekday::Fri=>hour<CLOSE_HOUR,
  _=>hour!=CLOSE_HOUR,
 }
}

/// 这一刻（开盘中）属于哪个交易日：18:00 ET 之后算次日。
pub fn trading_date(utc_ms:i64)->NaiveDate {
 let t=local(utc_ms);
 if t.hour()>=OPEN_HOUR {t.date()+Duration::days(1)} else {t.date()}
}

fn weekday(d:NaiveDate)->bool {!matches!(d.weekday(),Weekday::Sat|Weekday::Sun)}

/// 交易日 `d` 那一段的起止（UTC 毫秒，左闭右开）：前一天 18:00 ET 到当天 17:00 ET。
pub fn session(d:NaiveDate)->(i64,i64) {
 let at=|d:NaiveDate,h:u32|utc_of(d.and_hms_opt(h,0,0).unwrap_or_default());
 (at(d-Duration::days(1),OPEN_HOUR),at(d,CLOSE_HOUR))
}

/// 此刻「当前」的交易日：开盘中就是正在走的那一段；停盘（每日一小时、周末）时是刚收完的那一段。
pub fn current_or_last(utc_ms:i64)->NaiveDate {
 if is_open(utc_ms) {return trading_date(utc_ms)}
 let mut d=local(utc_ms).date();
 for _ in 0..10 {
  if weekday(d)&&session(d).1<=utc_ms {return d}
  d-=Duration::days(1);
 }
 d
}

/// 日线 / 周线 / 月线的开盘时刻标签：交易日当天 00:00 UTC（不是那一段真正开始的 18:00 ET）。
///
/// 为什么不切在 UTC 0 点、也不写真正的 18:00 ET：日线的内容按 ICE 交易日（18:00 → 17:00 ET）
/// 聚，标签用日期本身，客户端按上海时间显示日期、按周一 00:00 UTC 聚周线、按月初聚月线时
/// 都落在同一天上；写 18:00 ET 的真实时刻，周一那根会被当成周日，周线、月线全部错一格。
pub fn day_label(d:NaiveDate)->i64 {d.and_hms_opt(0,0,0).unwrap_or_default().and_utc().timestamp_millis()}

/// 标签 → 交易日。
pub fn label_date(label_ms:i64)->NaiveDate {
 DateTime::from_timestamp_millis(label_ms).map(|d|d.date_naive()).unwrap_or_default()
}

/// CNBC 报文里的美东墙上时间串（`YYYYMMDDhhmmss`）。
pub fn cnbc_stamp(utc_ms:i64)->String {local(utc_ms).format("%Y%m%d%H%M%S").to_string()}

#[cfg(test)]
mod tests {
 use super::*;
 fn ms(s:&str)->i64 {NaiveDateTime::parse_from_str(s,"%Y-%m-%d %H:%M").unwrap().and_utc().timestamp_millis()}
 fn date(s:&str)->NaiveDate {NaiveDate::parse_from_str(s,"%Y-%m-%d").unwrap()}

 #[test] fn dst_runs_from_the_second_sunday_of_march_to_the_first_sunday_of_november() {
  assert_eq!(dst_bounds(2026),(ms("2026-03-08 07:00"),ms("2026-11-01 06:00")));
  assert_eq!(dst_bounds(2027),(ms("2027-03-14 07:00"),ms("2027-11-07 06:00")));
  assert_eq!(offset_ms(ms("2026-03-08 06:59")),-5*HOUR_MS);
  assert_eq!(offset_ms(ms("2026-03-08 07:00")),-4*HOUR_MS);
  assert_eq!(offset_ms(ms("2026-11-01 05:59")),-4*HOUR_MS);
  assert_eq!(offset_ms(ms("2026-11-01 06:00")),-5*HOUR_MS);
  assert_eq!(local(ms("2026-10-05 10:11")).format("%H:%M").to_string(),"06:11");
  assert_eq!(local(ms("2026-12-01 10:11")).format("%H:%M").to_string(),"05:11");
 }

 #[test] fn wall_clock_round_trips_on_both_sides_of_the_switch() {
  for s in ["2026-03-06 17:00","2026-03-08 18:00","2026-10-30 17:00","2026-11-01 18:00","2026-07-15 00:00","2026-12-24 00:00"] {
   let wall=NaiveDateTime::parse_from_str(s,"%Y-%m-%d %H:%M").unwrap();
   assert_eq!(local(utc_of(wall)),wall,"{s}");
  }
  // 周日 18:00 ET：夏令时那天是 22:00 UTC，换回标准时间那天是 23:00 UTC。
  assert_eq!(utc_of(NaiveDateTime::parse_from_str("2026-03-08 18:00","%Y-%m-%d %H:%M").unwrap()),ms("2026-03-08 22:00"));
  assert_eq!(utc_of(NaiveDateTime::parse_from_str("2026-11-01 18:00","%Y-%m-%d %H:%M").unwrap()),ms("2026-11-01 23:00"));
 }

 #[test] fn the_week_opens_sunday_18_and_closes_friday_17_eastern() {
  // 标准时间的周五（3 月 6 日）：16:59 ET 开，17:00 ET 收。
  assert!(is_open(ms("2026-03-06 21:59")));
  assert!(!is_open(ms("2026-03-06 22:00")));
  // 周六整天收着。
  assert!(!is_open(ms("2026-03-07 15:00")));
  // 夏令时开始那个周日：18:00 EDT = 22:00 UTC 开（标准时间下是 23:00 UTC）。
  assert!(!is_open(ms("2026-03-08 21:59")));
  assert!(is_open(ms("2026-03-08 22:00")));
  // 夏令时的周五（10 月 30 日）：17:00 EDT = 21:00 UTC 收。
  assert!(is_open(ms("2026-10-30 20:59")));
  assert!(!is_open(ms("2026-10-30 21:00")));
  // 换回标准时间那个周日（11 月 1 日）：18:00 EST = 23:00 UTC 才开。
  assert!(!is_open(ms("2026-11-01 22:30")));
  assert!(is_open(ms("2026-11-01 23:00")));
 }

 #[test] fn there_is_a_one_hour_break_every_weekday_at_17_eastern() {
  // 夏令时的周二：21:00–22:00 UTC 停。
  assert!(is_open(ms("2026-10-06 20:59")));
  assert!(!is_open(ms("2026-10-06 21:00")));
  assert!(!is_open(ms("2026-10-06 21:59")));
  assert!(is_open(ms("2026-10-06 22:00")));
  // 标准时间的周二：22:00–23:00 UTC 停。
  assert!(is_open(ms("2026-12-01 21:59")));
  assert!(!is_open(ms("2026-12-01 22:00")));
  assert!(is_open(ms("2026-12-01 23:00")));
 }

 #[test] fn a_session_belongs_to_the_day_it_closes_on() {
  // 周二 18:00 ET 之后算周三。
  assert_eq!(trading_date(ms("2026-10-06 22:00")),date("2026-10-07"));
  assert_eq!(trading_date(ms("2026-10-06 20:59")),date("2026-10-06"));
  // 周日晚上开的那段是周一。
  assert_eq!(trading_date(ms("2026-10-04 22:10")),date("2026-10-05"));
  assert_eq!(session(date("2026-10-05")),(ms("2026-10-04 22:00"),ms("2026-10-05 21:00")));
  // 跨夏令时切换的那一段：周日 18:00 EST 到周一 17:00 EST。
  assert_eq!(session(date("2026-11-02")),(ms("2026-11-01 23:00"),ms("2026-11-02 22:00")));
  // 停盘时「当前」是刚收完的那一段：每日停盘那一小时、周六、周日开盘前都是。
  assert_eq!(current_or_last(ms("2026-10-06 21:30")),date("2026-10-06"));
  assert_eq!(current_or_last(ms("2026-10-03 12:00")),date("2026-10-02"));
  assert_eq!(current_or_last(ms("2026-10-04 21:00")),date("2026-10-02"));
  assert_eq!(current_or_last(ms("2026-10-05 10:00")),date("2026-10-05"));
 }

 #[test] fn daily_bars_are_labelled_with_the_trading_date_at_utc_midnight() {
  assert_eq!(day_label(date("2026-10-05")),ms("2026-10-05 00:00"));
  assert_eq!(label_date(ms("2026-10-05 00:00")),date("2026-10-05"));
  assert_eq!(cnbc_stamp(ms("2026-10-05 10:11")),"20261005061100");
 }
}
