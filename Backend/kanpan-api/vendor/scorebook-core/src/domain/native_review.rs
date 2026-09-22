use crate::{api::native_review::*, domain::{criteria::Bar, interval::Interval}, error::{Error, Result}};
use chrono::{DateTime, Utc};

pub fn time(ms: i64) -> Result<DateTime<Utc>> { DateTime::from_timestamp_millis(ms).ok_or_else(|| Error::bad("invalid_time")) }
pub fn validate_range(range: &ChartRange, cutoff: i64) -> Result<Interval> {
    let interval = Interval::exact(&range.interval)?;
    if !matches!((range.venue.as_str(),range.market.as_str()), ("binance","usd_m") | ("coinbase","spot"))
        || range.symbol.len() > 40 || range.symbol.is_empty()
        || !range.symbol.chars().all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == '-')
        || (range.venue == "binance" && (!range.symbol.ends_with("USDT") || range.symbol.contains('-')))
        || (range.venue == "coinbase" && !range.symbol.ends_with("-USD"))
        || range.start >= range.end || range.end > cutoff || !(3..=1500).contains(&range.bars)
        || interval.bars_between(time(range.start)?, time(range.end)?) != range.bars as i64 {
        return Err(Error::bad("invalid_chart_range"));
    }
    Ok(interval)
}
pub fn validate(draft: &NativeDraft, now: i64) -> Result<()> {
    validate_range(&draft.range, now)?;
    let r = &draft.rule;
    if r.version != "criteria-v2" || !matches!(r.direction.as_str(), "long" | "short" | "observe")
        || !matches!(r.confirmation.as_str(), "bar_close" | "trade_touch")
        || !matches!(draft.origin.as_str(), "chart_first" | "thought_first" | "interwoven" | "unknown")
        || draft.confidence.is_some_and(|v| ![50,60,70,80,90].contains(&v))
        || draft.created > now + 60_000 || draft.created < 0 || draft.text.len() > 64_000
        || draft.chart_settings.as_ref().is_some_and(|v| v.len() > 128_000)
        || draft.drawing_snapshot.as_ref().is_some_and(|v| v.len() > 256_000)
        || ![r.reference,r.target,r.invalidation].iter().all(|v| v.is_finite() && *v > 0.0) {
        return Err(Error::bad("invalid_native_record"));
    }
    if r.direction != "observe" && (r.expires <= draft.created || r.expires > draft.created + 366 * 86_400_000
       || (r.direction == "long" && !(r.target > r.reference && r.invalidation < r.reference))
       || (r.direction == "short" && !(r.target < r.reference && r.invalidation > r.reference))) {
        return Err(Error::bad("invalid_native_rule"));
    }
    Ok(())
}
/// First proven terminal event wins. Missing path data never receives a guessed ordering.
pub fn evaluate(record: &NativeRecord, bars: &[Bar], now: i64) -> Result<NativeAssessment> {
    let r = &record.draft.rule;
    let answer = |outcome: &str, reason: &str, at: Option<i64>| NativeAssessment { outcome: outcome.into(), reason: reason.into(), event_at: at, assessed_at: now };
    if record.voided { return Ok(answer("voided", "已作废", None)); }
    if r.direction == "observe" { return Ok(answer("observation", "只记录，不判对错", None)); }
    let start = record.submitted;
    if start >= r.expires { return Ok(answer("needs_verification", "补传时观察窗口已结束", None)); }
    let interval = Interval::exact(&record.draft.range.interval)?;
    let target = |p: f64| if r.direction == "long" { p >= r.target } else { p <= r.target };
    let invalid = |p: f64| if r.direction == "long" { p <= r.invalidation } else { p >= r.invalidation };
    let mut previous = None;
    let mut seen = false;
    for bar in bars {
        let from = bar.start.timestamp_millis(); let to = bar.end.timestamp_millis();
        if to <= start || from >= now.min(r.expires) { continue; }
        if let Some(end) = previous && from != end { return Ok(answer("needs_verification", "观察行情有缺口", Some(from))); }
        previous = Some(to);
        if r.confirmation == "bar_close" {
            // An already-open bar at submission is excluded, including its eventual close.
            if from < start { continue; }
            if !seen && from > interval.ceil(time(start)?).timestamp_millis() { return Ok(answer("needs_verification", "缺少观察开始后的行情", None)); }
            seen = true;
            if to > now.min(r.expires) { continue; }
            let p = bar.close.parse::<f64>().map_err(|_| Error::bad("invalid_market_price"))?;
            if !p.is_finite() { return Err(Error::bad("invalid_market_price")); }
            if target(p) { return Ok(answer("realized", "收盘先达到目标", Some(to))); }
            if invalid(p) { return Ok(answer("unrealized", "收盘先达到失效价", Some(to))); }
        } else {
            if from < start || to > now.min(r.expires) {
                // Partial bars require exact trades; caller may replace with proven finer evidence.
                return Ok(answer("needs_verification", "边界成交顺序待核实", None));
            }
            if !seen && from != start { return Ok(answer("needs_verification", "缺少起始成交证据", None)); }
            seen = true;
            let high = bar.high.parse::<f64>().map_err(|_| Error::bad("invalid_market_price"))?;
            let low = bar.low.parse::<f64>().map_err(|_| Error::bad("invalid_market_price"))?;
            let hit = target(high) || target(low); let lost = invalid(high) || invalid(low);
            if hit && lost { return Ok(answer("needs_verification", "同根触达两条线，先后待核实", Some(from))); }
            if hit { return Ok(answer("realized", "先触达目标", Some(to))); }
            if lost { return Ok(answer("unrealized", "先触达失效价", Some(to))); }
        }
    }
    if now >= r.expires {
        let end = previous.unwrap_or(start);
        let required = interval.floor(time(r.expires)?).timestamp_millis();
        if !seen || end < required { return Ok(answer("needs_verification", "到期行情不完整", None)); }
        return Ok(answer("unrealized", "到期未达到目标", Some(r.expires)));
    }
    Ok(answer("waiting", "等待行情", None))
}
