//! K 线字符串价格 → f64 OHLC，只供形态比对（chart_match）用；
//! 记分簿网页版的出图（raster / svg）与出图请求在 vendor 时裁掉了。
use super::criteria::Bar;
pub fn numbers(bars: &[Bar]) -> Result<Vec<[f64; 4]>, String> {
    if bars.is_empty() || bars.len() > 2000 {
        return Err("chart_requires_1_to_2000_bars".into());
    }
    bars.iter()
        .map(|b| {
            let mut p = [0.0f64; 4];
            for (j, s) in [&b.open, &b.high, &b.low, &b.close].iter().enumerate() {
                p[j] = s.parse().map_err(|_| "invalid_chart_price")?;
                if !p[j].is_finite() || p[j] <= 0.0 {
                    return Err("invalid_chart_price".into());
                }
            }
            if p[1] < p[0].max(p[3]) || p[2] > p[0].min(p[3]) {
                return Err("invalid_ohlc".into());
            }
            Ok(p)
        })
        .collect()
}
