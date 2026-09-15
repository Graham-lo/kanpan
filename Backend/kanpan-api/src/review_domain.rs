//! Keep the frozen criteria engine; extend only supported venue identity.
use scorebook_core::{api::native_review::{ChartRange,NativeDraft}, domain::{native_review as core,interval::Interval},error::{Error,Result}};
pub use core::{time,evaluate};
pub fn validate_range(range:&ChartRange,cutoff:i64)->Result<Interval> {
 if !matches!(range.venue.as_str(),"binance"|"okx") {return Err(Error::bad("invalid_chart_range"))}
 let mut normalized=range.clone(); normalized.venue="binance".into();core::validate_range(&normalized,cutoff)
}
pub fn validate(draft:&NativeDraft,now:i64)->Result<()> {
 validate_range(&draft.range,now)?;
 let mut normalized=draft.clone();normalized.range.venue="binance".into();core::validate(&normalized,now)
}
