//! chart-match-v2 geometry. Price samples live only in memory; public persistence uses
//! the fixed 192-dimensional descriptor, never this per-candle representation.
//!
//! 看盘只用到 K 线数值这一路（`from_bars` → `descriptor` / `rerank`）；记分簿网页版的
//! 截图识别（image 解码、连通域、窗格切分）、价格域比对与自由长度扫描在 vendor 时裁掉了，
//! 来历见 `vendor/scorebook-core/README`。
use crate::error::{Error, Result};
use serde::{Deserialize, Serialize};

pub const MODEL: &str = "candle-geometry-v2";
/// open/high/low/close。`shape` 永远是几何坐标（y 向上为正，像素取负），
/// `priced` 只有在价格轴拟合成功时才有，装的是真价格。
#[derive(Clone, Debug)]
pub struct Candle {
    pub shape: [f64; 4],
    pub priced: Option<[f64; 4]>,
}
impl Candle {
    pub fn new(shape: [f64; 4]) -> Self {
        Self {
            shape,
            priced: None,
        }
    }
    pub fn priced(shape: [f64; 4], priced: [f64; 4]) -> Self {
        Self {
            shape,
            priced: Some(priced),
        }
    }
}
/// 分位数；`v` 允许乱序。
fn quantile(v: &mut [f64], q: f64) -> f64 {
    v.sort_by(f64::total_cmp);
    let pos = (v.len() - 1) as f64 * q;
    let i = pos.floor() as usize;
    let j = (i + 1).min(v.len() - 1);
    v[i] + (v[j] - v[i]) * (pos - i as f64)
}
pub fn from_bars(bars: &[super::criteria::Bar]) -> Result<Vec<Candle>> {
    super::chart::numbers(bars)
        .map(|v| v.into_iter().map(|c| Candle::priced(c, c)).collect())
        .map_err(Error::bad)
}
/// 归一化到 64 个采样点。上下界取高的 98 分位 / 低的 2 分位（§5.4-4）：
/// 单根插针以前会把整张图压扁，现在它自己越界到 0..1 之外，其余部分的起伏保住。
pub fn normalized(candles: &[Candle], reverse: bool) -> Result<Vec<[f64; 4]>> {
    if candles.len() < 16
        || candles.len() > 2000
        || candles.iter().any(|c| {
            c.shape.iter().any(|v| !v.is_finite())
                || c.shape[1] < c.shape[0].max(c.shape[3])
                || c.shape[2] > c.shape[0].min(c.shape[3])
        })
    {
        return Err(Error::bad("invalid_candle_geometry"));
    }
    let mut highs: Vec<f64> = candles.iter().map(|c| c.shape[1]).collect();
    let mut lows: Vec<f64> = candles.iter().map(|c| c.shape[2]).collect();
    let mut hi = quantile(&mut highs, 0.98);
    let mut lo = quantile(&mut lows, 0.02);
    if hi - lo <= f64::EPSILON {
        // 分位数被一段长横盘吃掉了，退回绝对上下界。
        hi = *highs.last().unwrap();
        lo = lows[0];
    }
    let range = hi - lo;
    if range <= f64::EPSILON {
        return Err(Error::bad("flat_chart_geometry"));
    }
    Ok((0..64)
        .map(|i| {
            let pos = i as f64 * (candles.len() - 1) as f64 / 63.;
            let a = pos.floor() as usize;
            let b = (a + 1).min(candles.len() - 1);
            let t = pos - a as f64;
            let mut p = [0.; 4];
            for (j, v) in p.iter_mut().enumerate() {
                *v = (candles[a].shape[j] * (1. - t) + candles[b].shape[j] * t - lo) / range;
            }
            if reverse {
                [1. - p[0], 1. - p[2], 1. - p[1], 1. - p[3]]
            } else {
                p
            }
        })
        .collect())
}
pub fn descriptor(candles: &[Candle]) -> Result<Vec<f32>> {
    let series = normalized(candles, false)?;
    let mut vector = Vec::with_capacity(192);
    for (i, p) in series.iter().enumerate() {
        let center = (p[0] + p[3]) / 2.;
        let prev = if i == 0 {
            center
        } else {
            (series[i - 1][0] + series[i - 1][3]) / 2.
        };
        vector.extend([
            (center - 0.5) as f32,
            ((p[1] - p[2]) * 0.5) as f32,
            ((center - prev) * 2.) as f32,
        ]);
    }
    let norm = vector.iter().map(|v| v * v).sum::<f32>().sqrt();
    if norm <= 1e-6 {
        return Err(Error::bad("flat_chart_geometry"));
    }
    for v in &mut vector {
        *v /= norm;
    }
    Ok(vector)
}
#[derive(Clone, Serialize, Deserialize)]
pub struct MatchScore {
    pub score: f64,
    pub alignment_cost: f64,
    pub direction_consistent: bool,
    pub reverse: bool,
    pub meaning: String,
    /// 校准后的稀有度：同档位样本里低于此分的比例（§5.5-3）。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rarity: Option<f64>,
    /// 给前端的档位词来源，只回枚举值：`sure|likely|weak` 或 `很像|像|有点像` 对应的键。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub level: Option<String>,
    /// 本次比对分布里的 z 分数（§5.2 第 5 步）。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub z: Option<f64>,
}
impl MatchScore {
    fn new(score: f64, cost: f64, consistent: bool, reverse: bool, meaning: &str) -> Self {
        Self {
            score,
            alignment_cost: cost,
            direction_consistent: consistent,
            reverse,
            meaning: meaning.into(),
            rarity: None,
            level: None,
            z: None,
        }
    }
}
/// 归一化之后的带状 DTW；方向不再是断崖，而是按净涨跌差连续扣分（§5.4-5）。
fn compare(a: &[[f64; 4]], b: &[[f64; 4]], reverse: bool) -> MatchScore {
    let net = |v: &[[f64; 4]]| v[63][3] - v[0][0];
    let consistent =
        net(a).signum() == net(b).signum() || net(a).abs() < 0.08 || net(b).abs() < 0.08;
    let mut prev = [f64::INFINITY; 65];
    prev[0] = 0.;
    for i in 1usize..=64 {
        let mut row = [f64::INFINITY; 65];
        for j in i.saturating_sub(6).max(1)..=(i + 6).min(64) {
            let p = a[i - 1];
            let q = b[j - 1];
            let cost = (p[0] - q[0]).abs() * 0.25
                + (p[3] - q[3]).abs() * 0.35
                + (p[1] - q[1]).abs() * 0.2
                + (p[2] - q[2]).abs() * 0.2;
            row[j] = cost + (prev[j - 1]).min(prev[j] + 0.025).min(row[j - 1] + 0.025);
        }
        prev = row;
    }
    let cost = prev[64] / 64. + 0.15 * (net(a) - net(b)).abs();
    MatchScore::new(
        (-6. * cost).exp(),
        cost,
        consistent,
        reverse,
        "structural_similarity_not_probability",
    )
}
pub fn rerank(query: &[Candle], candidate: &[Candle], reverse: bool) -> Result<MatchScore> {
    let a = normalized(query, reverse)?;
    let b = normalized(candidate, false)?;
    Ok(compare(&a, &b, reverse))
}
#[cfg(test)]
mod tests {
    use super::*;
    fn series(n: usize) -> Vec<Candle> {
        (0..n)
            .map(|i| {
                let f = i as f64;
                let v =
                    100. + 9. * (f * 0.031).sin() + 4. * (f * 0.11).cos() + 1.5 * (f * 0.7).sin();
                let n = 100. + 9. * ((f + 1.) * 0.031).sin() + 4. * ((f + 1.) * 0.11).cos();
                Candle::new([v, v.max(n) + 0.6, v.min(n) - 0.6, n])
            })
            .collect()
    }
    /// 同一段走势比自己：分数接近 1、方向一致；反过来比（reverse）不应该同样高。
    #[test]
    fn rerank_scores_an_excerpt_against_itself_near_one() {
        let bars = series(768);
        let query = &bars[300..410];
        let same = rerank(query, query, false).unwrap();
        assert!(same.score > 0.99, "分数太低：{}", same.score);
        assert!(same.direction_consistent);
        let elsewhere = rerank(query, &bars[40..150], false).unwrap();
        assert!(elsewhere.score < same.score);
    }
    #[test]
    fn descriptor_is_a_unit_vector_of_192() {
        let v = descriptor(&series(120)).unwrap();
        assert_eq!(v.len(), 192);
        let norm = v.iter().map(|x| x * x).sum::<f32>().sqrt();
        assert!((norm - 1.).abs() < 1e-4);
    }
    #[test]
    fn too_few_or_flat_candles_are_rejected() {
        assert!(descriptor(&series(15)).is_err());
        let flat: Vec<Candle> = (0..32).map(|_| Candle::new([1., 1., 1., 1.])).collect();
        assert!(descriptor(&flat).is_err());
    }
}
