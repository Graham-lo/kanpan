//! 「找相似」的公开历史索引（`market_features`）：worker 里一条常驻循环，滚动维护。
//!
//! 2026-09-29 之前这张表只有 09-23 手动跑的一次 `import_public_history`：前 30 只 ×
//! 15m/1h/4h/1d × 365 天，窗口 64 根、步长 16，之后再没长过。1h 每只约 547 个窗口、4h 约
//! 137 个，找相似取到的 300 个「最近」候选其实离得很远，DTW 重排后几乎全落在门槛下——
//! 线上 BTC 1h（24/32/48/64 根）全是 0 条结果，4h 32 根 0 条、64 根 1 条。
//!
//! 离线复刻整条检索（描述子近邻 300 → DTW → 门槛 → 同品种去重）比过几种索引形状，
//! 结论写在 `docs/网页版-吸收-复盘与自选-2026-09-29.md`：决定性的是**窗口长度要贴近查询长度**
//! （查询多是 32 根，索引只有 64 根时两段按 64 个采样点归一化后纹理对不上），其次是
//! 1h/4h 的步长要密。所以这里按周期各给一份 [`Plan`]：
//!
//! | 周期 | 窗口长度 | 步长 |
//! |---|---|---|
//! | 15m | 32、64 | 16 |
//! | 1h | 32、48、64 | 4 |
//! | 4h | 32、48、64 | 2 |
//! | 1d | 32、64 | 1 |
//!
//! 品种是币安 U 本位里标的是币的 USDT 永续（`underlyingType = COIN`）按 24h 成交额的前
//! [`TOP`] 只，每 6 小时重排一次；历史深度 [`DAYS`] 天，和 15m 原来一样，更早的每小时删掉。
//!
//! **怎么知道缺什么**：不另开状态表。每只品种每个周期的时间轴按绝对 K 线编号切成 [`CHUNK`]
//! 根一段；这一段该有多少个窗口（每种长度、起点落在步长整数倍上、整个窗口已收盘）是算得出来的，
//! 库里实际有多少一条 `GROUP BY` 就知道。少了就把这一段（加上最长窗口 − 1 根的尾巴）取回来
//! 切一遍，`ON CONFLICT DO NOTHING` 写进去——窗口起点对齐到绝对编号，重跑幂等；原来 64/16 的
//! 窗口是新计划的子集，不会重复。取回来还是补不齐的（上市前、停牌缺根、横盘到零振幅）记在
//! 进程里，同一个「该有数」不再重取。
//!
//! **手机的行情转发永远优先**：取数走复盘那个带账本、带闸门的币安适配器（[`crate::review_market::provider`]），
//! 与找相似、复盘判定共用 `provider_budgets` 的每分钟权重账本和 [`crate::binance_gate`] 的封禁截止时间；
//! 这里只在「这一分钟整个出口已用的权重」低于上限的 [`SHARE_PERCENT`]% 时才出站，自己每分钟
//! 最多花 [`MINUTE_WEIGHT`]，每次一页（≤ 1000 根，权重 5），页间至少歇一秒；有人正在等找相似
//! （[`crate::search::busy`]）就整个让开。闸门按着、账本满了，就等到下一分钟开头再来。
//! 顺序是先滚动（每只每个周期最新那一段），再回填（1h、4h 优先，从近往远）。
use crate::AppState;
use chrono::{DateTime, Datelike, Utc};
use scorebook_core::domain::{chart_match, criteria::Bar, interval::Interval};
use scorebook_core::market::MarketDataProvider;
use serde_json::Value;
use sha2::{Digest, Sha256};
use sqlx::{PgPool, Postgres, QueryBuilder};
use std::collections::HashMap;
use std::time::Duration;
use uuid::Uuid;

pub const MARKET: &str = "usd_m";
pub const SOURCE: &str = "binance";
pub const RENDER_VERSION: &str = "ohlc-geometry-resample64-v2";
/// 索引多少只品种。
pub const TOP: usize = 40;
/// 历史深度（天）。
pub const DAYS: i64 = 365;
/// 一段多少根：928 + 最长窗口 64 − 1 = 991 ≤ 1000，一页取完、权重 5；928 是 16、4、2、1 的倍数。
pub const CHUNK: i64 = 928;
/// 这一分钟整个出口已用权重（`x-mbx-used-weight-1m`，整个 IP 的，含同机别的服务）低于
/// 账本上限的这个百分比时才出站。2026-09-29 部署后实测这台 VPS 平时每分钟就用到 750 上下
/// （订单流的深度快照占大头），分钟开头 300 多、到分钟末 750；30% 这条线一分钟里只开几秒。
pub const SHARE_PERCENT: i32 = 50;
/// 索引自己每分钟最多花这么多权重（24 页）：整个出口最坏 600 + 120 + 一次找相似 300，
/// 仍在账本上限 1200 以内。
pub const MINUTE_WEIGHT: i32 = 120;
/// 一页 K 线（limit 500–1000）的权重。
const PAGE_WEIGHT: i32 = 5;
/// 两次出站之间至少歇多久。
const PAUSE: Duration = Duration::from_secs(1);
/// 没活干、或者被闸门 / 账本挡住时睡多久。
const IDLE: Duration = Duration::from_secs(60);
/// 品种表多久重排一次。
const RERANK: Duration = Duration::from_secs(6 * 3600);
/// 一轮最多做多少段就重新数一遍库。
const ROUND: usize = 60;
/// 旧窗口多久删一次。
const PRUNE_EVERY: Duration = Duration::from_secs(3600);

/// 一个周期的索引形状。
#[derive(Clone, Copy, Debug)]
pub struct Plan {
    pub interval: &'static str,
    pub lengths: &'static [usize],
    pub stride: i64,
}
/// 回填顺序也是这张表的顺序：用户这次报的是 1h / 4h，先补它们。
pub const PLANS: [Plan; 4] = [
    Plan { interval: "1h", lengths: &[32, 48, 64], stride: 4 },
    Plan { interval: "4h", lengths: &[32, 48, 64], stride: 2 },
    Plan { interval: "1d", lengths: &[32, 64], stride: 1 },
    Plan { interval: "15m", lengths: &[32, 64], stride: 16 },
];
impl Plan {
    fn longest(&self) -> i64 {
        self.lengths.iter().copied().max().unwrap_or(64) as i64
    }
    fn step_ms(&self) -> i64 {
        Interval::exact(self.interval).ok().and_then(Interval::fixed_seconds).unwrap_or(60) * 1000
    }
}

/// 这根 K 线在绝对网格上是第几根：固定长度的周期按开盘秒数整除，月线按日历月数。
pub fn bar_number(interval: Interval, start: DateTime<Utc>) -> i64 {
    match interval.fixed_seconds() {
        Some(step) => start.timestamp().div_euclid(step),
        None => i64::from(start.year()) * 12 + i64::from(start.month0()),
    }
}

/// 把一段 K 线切成索引窗口：窗口起点落在绝对编号是 `stride` 整数倍的那根上，
/// 窗口不跨缺口（前一根的收盘时刻必须是后一根的开盘时刻）。
///
/// 起点对齐到绝对编号，是为了两次取数的起点不同时切出来的窗口仍然一模一样，
/// 唯一键撞得上、重跑不攒错位的副本（见 `import_public_history` 的历史）。
pub fn aligned_windows(bars: &[Bar], interval: Interval, window: usize, stride: usize) -> Vec<&[Bar]> {
    let stride = i64::try_from(stride.max(1)).unwrap_or(i64::MAX);
    let mut out = Vec::new();
    let mut run = 0usize;
    for end in 1..=bars.len() {
        // 一段连续的 K 线到此为止：在 [run, end) 里切。
        if end == bars.len() || bars[end - 1].end != bars[end].start {
            let part = &bars[run..end];
            out.extend(
                (0..part.len())
                    .filter(|&offset| offset + window <= part.len())
                    .filter(|&offset| bar_number(interval, part[offset].start).rem_euclid(stride) == 0)
                    .map(|offset| &part[offset..offset + window]),
            );
            run = end;
        }
    }
    out
}

pub fn input_hash(bars: &[Bar]) -> String {
    let mut hasher = Sha256::new();
    for bar in bars {
        hasher.update(bar.start.timestamp_millis().to_le_bytes());
        for value in [&bar.open, &bar.high, &bar.low, &bar.close] {
            hasher.update(value.as_bytes());
            hasher.update([0]);
        }
    }
    hex::encode(hasher.finalize())
}

pub struct Feature {
    pub start: i64,
    pub end: i64,
    pub bars_count: i32,
    pub embedding: String,
    pub input_hash: String,
}
/// 一个窗口的描述子；画不成图（横盘到零振幅、坏 OHLC）时是 `None`，这个窗口不进索引。
pub fn make_feature(bars: &[Bar]) -> Option<Feature> {
    let candles = chart_match::from_bars(bars).ok()?;
    let vector = chart_match::descriptor(&candles).ok()?;
    Some(Feature {
        start: bars.first()?.start.timestamp_millis(),
        end: bars.last()?.end.timestamp_millis(),
        bars_count: bars.len() as i32,
        embedding: format!("{vector:?}"),
        input_hash: input_hash(bars),
    })
}

/// 写进 `market_features`，已有的（同一品种、周期、起止）不动。返回新写了几行。
pub async fn insert_windows(pool: &PgPool, source: &str, symbol: &str, interval: &str, windows: &[&[Bar]]) -> sqlx::Result<usize> {
    let features: Vec<Feature> = windows.iter().filter_map(|bars| make_feature(bars)).collect();
    let mut inserted = 0usize;
    for chunk in features.chunks(200) {
        let mut query = QueryBuilder::<Postgres>::new("INSERT INTO market_features(id,market,symbol,timeframe,start_at,end_at,bars_count,model_id,render_version,embedding,input_hash,source,published) ");
        query.push_values(chunk, |mut row, feature| {
            row.push_bind(Uuid::new_v4())
                .push_bind(MARKET)
                .push_bind(symbol)
                .push_bind(interval)
                .push_bind(feature.start)
                .push_bind(feature.end)
                .push_bind(feature.bars_count)
                .push_bind(chart_match::MODEL)
                .push_bind(RENDER_VERSION)
                .push_bind(&feature.embedding)
                .push_unseparated("::vector")
                .push_bind(&feature.input_hash)
                .push_bind(source)
                .push_bind(true);
        });
        query.push(" ON CONFLICT (market,symbol,timeframe,start_at,end_at,model_id,render_version,source) DO NOTHING");
        inserted += query.build().execute(pool).await?.rows_affected() as usize;
    }
    Ok(inserted)
}

/// 第 `chunk` 段（绝对编号 `[chunk·CHUNK, (chunk+1)·CHUNK)` 里起头的窗口）该有几个窗口。
/// `from` 是最早可用的那根的编号（深度下界与上市时刻取晚者），`closed` 是第一根还没收盘的编号。
pub fn expected(plan: &Plan, chunk: i64, from: i64, closed: i64) -> usize {
    let lo = (chunk * CHUNK).max(from);
    let hi = ((chunk + 1) * CHUNK).min(closed);
    plan.lengths
        .iter()
        .map(|&len| {
            let last = (hi - 1).min(closed - len as i64); // 起点最晚到这儿，窗口才整个收盘
            if last < lo {
                return 0;
            }
            let first = lo + (plan.stride - lo.rem_euclid(plan.stride)) % plan.stride;
            if first > last { 0 } else { ((last - first) / plan.stride + 1) as usize }
        })
        .sum()
}

/// 一段要取的 K 线范围（绝对编号，左闭右开）：这一段的起点到「最后一个起点 + 最长窗口」。
pub fn fetch_span(plan: &Plan, chunk: i64, from: i64, closed: i64) -> Option<(i64, i64)> {
    let lo = (chunk * CHUNK).max(from);
    let hi = ((chunk + 1) * CHUNK + plan.longest() - 1).min(closed);
    let shortest = plan.lengths.iter().copied().min().unwrap_or(64) as i64;
    (hi - lo >= shortest).then_some((lo, hi))
}

/// 一件活：某只品种某个周期的某一段。
#[derive(Clone, Debug, PartialEq)]
pub struct Job {
    pub symbol: String,
    pub plan: usize,
    pub chunk: i64,
    pub want: usize,
    /// 要取的 K 线（绝对编号，左闭右开），见 [`fetch_span`]。
    pub span: (i64, i64),
}

/// 从「每段库里已有多少」排出这一轮要做的活：先每只每个周期最新那一段（滚动），
/// 再按 [`PLANS`] 的顺序、每个周期从近往远回填。`tried` 里记着「取过一回、还是这个该有数」
/// 的段，不再重取。
pub fn schedule(
    have: &HashMap<(String, usize), HashMap<i64, usize>>,
    symbols: &[(String, i64)],
    now_ms: i64,
    tried: &HashMap<(String, usize, i64), usize>,
) -> Vec<Job> {
    let mut rolling = Vec::new();
    let mut backfill = Vec::new();
    for (index, plan) in PLANS.iter().enumerate() {
        let step = plan.step_ms();
        let closed = now_ms.div_euclid(step);
        for (symbol, listed_ms) in symbols {
            let from = (now_ms - DAYS * 86_400_000).max(*listed_ms).div_euclid(step) + 1;
            if closed <= from {
                continue;
            }
            let counts = have.get(&(symbol.clone(), index));
            let latest = (closed - 1).div_euclid(CHUNK);
            for chunk in (from.div_euclid(CHUNK)..=latest).rev() {
                let want = expected(plan, chunk, from, closed);
                let got = counts.and_then(|c| c.get(&chunk)).copied().unwrap_or(0);
                if want == 0 || got >= want || tried.get(&(symbol.clone(), index, chunk)) == Some(&want) {
                    continue;
                }
                let Some(span) = fetch_span(plan, chunk, from, closed) else { continue };
                let job = Job { symbol: symbol.clone(), plan: index, chunk, want, span };
                if chunk == latest { rolling.push(job) } else { backfill.push(job) }
            }
        }
    }
    // 回填：同一个周期内先近后远，各品种轮着来（第一只的全年补完之前，别的也都先有最近的）。
    backfill.sort_by(|a, b| a.plan.cmp(&b.plan).then(b.chunk.cmp(&a.chunk)));
    rolling.extend(backfill);
    rolling
}

/// 标的是币的 USDT 永续，24h 成交额前 `n` 只，带上市时刻（毫秒）。
async fn top_symbols(n: usize) -> Option<Vec<(String, i64)>> {
    if crate::binance_gate::blocked() {
        return None;
    }
    let listing = crate::market_meta::exchange_info().await.ok()?;
    let mut listed: HashMap<String, i64> = HashMap::new();
    for row in listing.get("symbols")?.as_array()? {
        // 「正在交易的永续」与板块历史、预热同一个判定；只要 USDT 计价、标的是币的——
        // 美股、贵金属那些合约走势形态和币不是一个族，混进来只会拿它们当「相似」凑数。
        if crate::instruments::is_live_perpetual(row) && row["quoteAsset"] == "USDT" && row["underlyingType"] == "COIN" {
            if let Some(symbol) = row["symbol"].as_str() {
                listed.insert(symbol.to_string(), row["onboardDate"].as_i64().unwrap_or(0));
            }
        }
    }
    if crate::binance_gate::blocked() {
        return None;
    }
    let reply = crate::http::shared().get("https://www.binance.com/fapi/v1/ticker/24hr").send().await.ok()?;
    if crate::binance_gate::note_reply(&reply) || !reply.status().is_success() {
        return None;
    }
    let rows: Value = reply.json().await.ok()?;
    let mut ranked: Vec<(f64, String)> = rows
        .as_array()?
        .iter()
        .filter_map(|t| {
            let symbol = t["symbol"].as_str()?;
            listed.contains_key(symbol).then(|| (t["quoteVolume"].as_str().and_then(|v| v.parse().ok()).unwrap_or(0.0), symbol.to_string()))
        })
        .collect();
    ranked.sort_by(|a, b| b.0.total_cmp(&a.0).then(a.1.cmp(&b.1)));
    Some(ranked.into_iter().take(n).map(|(_, s)| {
        let at = listed[&s];
        (s, at)
    }).collect())
}

/// 这一分钟整个出口已用的权重还在份额以内、且账本没被封：可以出站。
/// 上限与出口名和 `provider_budget` 读同一对环境变量。
async fn budget_room(pool: &PgPool) -> sqlx::Result<bool> {
    let limit: i32 = std::env::var("KANPAN_BINANCE_WEIGHT_PER_MINUTE").ok().and_then(|v| v.parse().ok()).unwrap_or(1200);
    let egress = std::env::var("KANPAN_EGRESS_ID").unwrap_or_else(|_| "default-egress".into());
    let row: Option<(i32, bool)> = sqlx::query_as("SELECT CASE WHEN window_start=date_trunc('minute',now()) THEN used ELSE 0 END, greatest(blocked_until,'epoch'::timestamptz)>now() FROM provider_budgets WHERE egress_id=$1 AND market=$2")
        .bind(&egress)
        .bind(MARKET)
        .fetch_optional(pool)
        .await?;
    let (used, blocked) = row.unwrap_or((0, false));
    Ok(!blocked && used + PAGE_WEIGHT <= limit * SHARE_PERCENT / 100)
}

/// 每只品种每个周期、每段库里已有几个窗口（只数计划里的长度、深度以内的）。
async fn census(pool: &PgPool, symbols: &[(String, i64)], now_ms: i64) -> sqlx::Result<HashMap<(String, usize), HashMap<i64, usize>>> {
    let names: Vec<String> = symbols.iter().map(|s| s.0.clone()).collect();
    let mut out = HashMap::new();
    for (index, plan) in PLANS.iter().enumerate() {
        let step = plan.step_ms();
        let lengths: Vec<i32> = plan.lengths.iter().map(|&l| l as i32).collect();
        let since = now_ms - DAYS * 86_400_000;
        let rows: Vec<(String, i64, i64)> = sqlx::query_as("SELECT symbol,div(start_at,$1)::bigint AS chunk,count(*) FROM market_features WHERE market=$2 AND timeframe=$3 AND source=$4 AND render_version=$5 AND model_id=$6 AND symbol=ANY($7) AND bars_count=ANY($8) AND start_at>=$9 GROUP BY 1,2")
            .bind(step * CHUNK)
            .bind(MARKET)
            .bind(plan.interval)
            .bind(SOURCE)
            .bind(RENDER_VERSION)
            .bind(chart_match::MODEL)
            .bind(&names)
            .bind(&lengths)
            .bind(since)
            .fetch_all(pool)
            .await?;
        for (symbol, chunk, count) in rows {
            out.entry((symbol, index)).or_insert_with(HashMap::new).insert(chunk, count as usize);
        }
    }
    Ok(out)
}

/// 删掉深度以外的窗口（多留一天余量），每批 5000 行，免得一条大 DELETE 长时间占着表。
pub async fn prune(pool: &PgPool, now_ms: i64) -> sqlx::Result<u64> {
    let cutoff = now_ms - (DAYS + 1) * 86_400_000;
    let mut total = 0;
    for plan in PLANS {
        loop {
            let gone = sqlx::query("DELETE FROM market_features WHERE id IN (SELECT id FROM market_features WHERE market=$1 AND timeframe=$2 AND source=$3 AND render_version=$4 AND published AND end_at<$5 LIMIT 5000)")
                .bind(MARKET)
                .bind(plan.interval)
                .bind(SOURCE)
                .bind(RENDER_VERSION)
                .bind(cutoff)
                .execute(pool)
                .await?
                .rows_affected();
            total += gone;
            if gone < 5000 {
                break;
            }
        }
    }
    Ok(total)
}

/// 取一段、切窗、写库。返回新写了几行；`Err(true)` 表示「这会儿」取不到（闸门、账本、网络），
/// 这一轮该停；`Err(false)` 表示这一段本身取不到（品种下架、参数被拒），记下别再取。
async fn run_job(pool: &PgPool, market: &dyn MarketDataProvider, job: &Job) -> Result<usize, bool> {
    let plan = &PLANS[job.plan];
    let step = plan.step_ms();
    let interval = Interval::exact(plan.interval).map_err(|_| false)?;
    let (lo, hi) = job.span;
    let start = DateTime::from_timestamp_millis(lo * step).ok_or(false)?;
    let end = DateTime::from_timestamp_millis(hi * step).ok_or(false)?;
    let data = market.klines(MARKET, &job.symbol, plan.interval, start, end).await.map_err(|e| e.retry.retryable())?;
    let bars: Vec<Bar> = serde_json::from_value(data["bars"].clone()).map_err(|_| false)?;
    let mut windows = Vec::new();
    for &len in plan.lengths {
        windows.extend(aligned_windows(&bars, interval, len, plan.stride as usize).into_iter().filter(|w| {
            // 只写起点落在这一段里的：尾巴那几根是给这一段最后几个窗口凑长度的。
            bar_number(interval, w[0].start).div_euclid(CHUNK) == job.chunk
        }));
    }
    insert_windows(pool, SOURCE, &job.symbol, plan.interval, &windows).await.map_err(|e| {
        tracing::warn!("Market index: writing {} {} failed: {e}", job.symbol, plan.interval);
        true
    })
}

/// worker 里的常驻循环。`KANPAN_MARKET_INDEX=0` 关掉（手动跑 `import_public_history` 时用）。
pub async fn run(s: AppState, market: std::sync::Arc<dyn MarketDataProvider>) {
    if std::env::var("KANPAN_MARKET_INDEX").is_ok_and(|v| v == "0") {
        tracing::info!("Market index: turned off by KANPAN_MARKET_INDEX=0");
        std::future::pending::<()>().await;
    }
    let mut symbols: Vec<(String, i64)> = Vec::new();
    let mut ranked_at: Option<tokio::time::Instant> = None;
    let mut pruned_at: Option<tokio::time::Instant> = None;
    let mut tried: HashMap<(String, usize, i64), usize> = HashMap::new();
    // (这是第几分钟, 这一分钟索引自己花了多少权重)
    let mut spent: (i64, i32) = (0, 0);
    loop {
        if ranked_at.is_none_or(|t| t.elapsed() >= RERANK) || symbols.is_empty() {
            match top_symbols(TOP).await {
                Some(list) if !list.is_empty() => {
                    tracing::info!("Market index: tracking {} symbols ({}…)", list.len(), list.iter().take(5).map(|s| s.0.as_str()).collect::<Vec<_>>().join(","));
                    symbols = list;
                    ranked_at = Some(tokio::time::Instant::now());
                }
                _ => {
                    if symbols.is_empty() {
                        tokio::time::sleep(IDLE).await;
                        continue;
                    }
                }
            }
        }
        let now_ms = Utc::now().timestamp_millis();
        if pruned_at.is_none_or(|t| t.elapsed() >= PRUNE_EVERY) {
            match prune(&s.pool, now_ms).await {
                Ok(n) => {
                    if n > 0 {
                        tracing::info!("Market index: pruned {n} windows older than {DAYS} days");
                    }
                    pruned_at = Some(tokio::time::Instant::now());
                }
                Err(e) => tracing::warn!("Market index: prune failed ({e})"),
            }
        }
        let have = match census(&s.pool, &symbols, now_ms).await {
            Ok(have) => have,
            Err(e) => {
                tracing::warn!("Market index: census failed ({e})");
                tokio::time::sleep(IDLE).await;
                continue;
            }
        };
        let jobs = schedule(&have, &symbols, now_ms, &tried);
        if jobs.is_empty() {
            tokio::time::sleep(IDLE).await;
            continue;
        }
        // 一轮最多做 ROUND 段：做完重新数一遍，滚动的活不会被长长的回填队列压在后面。
        let (mut done, mut written) = (0usize, 0usize);
        for job in jobs.iter().take(ROUND) {
            // 让路：有人在等找相似、闸门按着、这一分钟整个出口用得多了、或者自己这一分钟花够了——
            // 都等到下一分钟开头（账本按分钟清零），再接着做同一张单子。
            loop {
                let minute = Utc::now().timestamp().div_euclid(60);
                if spent.0 != minute {
                    spent = (minute, 0);
                }
                let open = spent.1 + PAGE_WEIGHT <= MINUTE_WEIGHT
                    && !crate::search::busy()
                    && !crate::binance_gate::blocked()
                    && budget_room(&s.pool).await.unwrap_or_else(|e| {
                        tracing::warn!("Market index: reading the weight ledger failed ({e})");
                        false
                    });
                if open {
                    break;
                }
                tokio::time::sleep(until_next_minute()).await;
            }
            spent.1 += PAGE_WEIGHT;
            match run_job(&s.pool, &*market, job).await {
                Ok(n) => {
                    written += n;
                    done += 1;
                    tried.insert((job.symbol.clone(), job.plan, job.chunk), job.want);
                }
                // 这会儿取不到（适配器自己的账本满了、闸门、网络）：下一分钟再试这一段。
                Err(true) => tokio::time::sleep(until_next_minute()).await,
                Err(false) => {
                    tracing::warn!("Market index: {} {} chunk {} refused; skipping it", job.symbol, PLANS[job.plan].interval, job.chunk);
                    tried.insert((job.symbol.clone(), job.plan, job.chunk), job.want);
                }
            }
            tokio::time::sleep(PAUSE).await;
        }
        if done > 0 {
            tracing::info!("Market index: {done} of {} chunks fetched, {written} windows written", jobs.len());
        }
    }
}

/// 睡到下一分钟开头过两秒（币安与账本都按自然分钟清零）。
fn until_next_minute() -> Duration {
    let into = Utc::now().timestamp_millis().rem_euclid(60_000) as u64;
    Duration::from_millis(60_000 - into + 2_000)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn series(interval: Interval, first: DateTime<Utc>, count: usize) -> Vec<Bar> {
        (0..count)
            .map(|n| {
                let start = interval.add_bars(first, n as i64);
                Bar { start, end: interval.add_bars(start, 1), open: "1".into(), high: "1".into(), low: "1".into(), close: "1".into(), volume: None }
            })
            .collect()
    }
    fn keys(windows: &[&[Bar]]) -> Vec<(i64, i64)> {
        windows.iter().map(|w| (w[0].start.timestamp_millis(), w[w.len() - 1].end.timestamp_millis())).collect()
    }

    /// 两次取数的起点差了几根，重叠那段切出来的窗口必须一模一样，唯一键才撞得上。
    #[test]
    fn reruns_that_start_later_cut_the_same_windows() {
        for name in ["15m", "1h", "4h", "1d", "1w", "1M"] {
            let interval = Interval::exact(name).unwrap();
            let origin = interval.floor(DateTime::from_timestamp(1_700_000_000, 0).unwrap());
            let first = series(interval, origin, 300);
            let later = series(interval, interval.add_bars(origin, 7), 300);
            let a = keys(&aligned_windows(&first, interval, 64, 16));
            let b = keys(&aligned_windows(&later, interval, 64, 16));
            assert!(!a.is_empty() && !b.is_empty(), "{name}");
            let overlap_start = later[0].start.timestamp_millis();
            let overlap_end = first[first.len() - 1].end.timestamp_millis();
            let inside = |k: &&(i64, i64)| k.0 >= overlap_start && k.1 <= overlap_end;
            assert_eq!(a.iter().filter(inside).collect::<Vec<_>>(), b.iter().filter(inside).collect::<Vec<_>>(), "{name}");
        }
    }

    #[test]
    fn windows_are_full_length_and_start_on_the_grid() {
        let interval = Interval::exact("1h").unwrap();
        let origin = interval.floor(DateTime::from_timestamp(1_700_000_000, 0).unwrap());
        let bars = series(interval, interval.add_bars(origin, 5), 200);
        let windows = aligned_windows(&bars, interval, 64, 16);
        assert!(windows.iter().all(|w| w.len() == 64 && bar_number(interval, w[0].start) % 16 == 0));
        let starts: Vec<i64> = windows.iter().map(|w| bar_number(interval, w[0].start)).collect();
        assert!(starts.windows(2).all(|p| p[1] - p[0] == 16));
    }

    /// 缺根（停牌、维护）那一处不许被一个窗口跨过去：跨缺口的窗口画出来是假的走势。
    #[test]
    fn windows_never_span_a_gap() {
        let interval = Interval::exact("1h").unwrap();
        let origin = interval.floor(DateTime::from_timestamp(1_700_000_000, 0).unwrap());
        let mut bars = series(interval, origin, 100);
        bars.remove(50);
        let windows = aligned_windows(&bars, interval, 32, 1);
        assert!(!windows.is_empty());
        assert!(windows.iter().all(|w| w.windows(2).all(|p| p[0].end == p[1].start)));
    }

    /// 老的 64 根 / 步长 16 的窗口是新计划的子集：不会攒出第二套错位副本。
    #[test]
    fn the_old_import_is_a_subset_of_every_plan() {
        for plan in PLANS {
            assert!(plan.lengths.contains(&64), "{}", plan.interval);
            assert_eq!(16 % plan.stride, 0, "{}", plan.interval);
            assert!(CHUNK % plan.stride == 0);
            assert!(CHUNK + plan.longest() - 1 <= 1000, "一段一页取完");
        }
    }

    /// 「该有几个」与真切出来的一致：一段完整的历史切完，每段的窗口数正好等于 expected。
    #[test]
    fn expected_matches_what_the_cutter_produces() {
        for plan in PLANS {
            let interval = Interval::exact(plan.interval).unwrap();
            let step = interval.fixed_seconds().unwrap();
            let from = 1_000_000_000 / step + 3; // 故意不对齐
            let closed = from + 2 * CHUNK + 500;
            let first = DateTime::from_timestamp(from * step, 0).unwrap();
            let bars = series(interval, first, (closed - from) as usize);
            let mut per_chunk: HashMap<i64, usize> = HashMap::new();
            for &len in plan.lengths {
                for w in aligned_windows(&bars, interval, len, plan.stride as usize) {
                    *per_chunk.entry(bar_number(interval, w[0].start).div_euclid(CHUNK)).or_default() += 1;
                }
            }
            for chunk in from.div_euclid(CHUNK)..=(closed - 1).div_euclid(CHUNK) {
                assert_eq!(expected(&plan, chunk, from, closed), per_chunk.get(&chunk).copied().unwrap_or(0), "{} 第 {chunk} 段", plan.interval);
            }
        }
    }

    /// 取数范围覆盖这一段所有窗口：起点在段内、终点不超过已收盘。
    #[test]
    fn a_fetch_span_covers_every_window_of_its_chunk() {
        let plan = PLANS[0];
        let (from, closed) = (10 * CHUNK + 7, 13 * CHUNK + 20);
        for chunk in 10..=13 {
            let Some((lo, hi)) = fetch_span(&plan, chunk, from, closed) else { continue };
            assert!(lo >= from && hi <= closed && hi - lo <= 1000);
            assert!(hi >= ((chunk + 1) * CHUNK + 63).min(closed));
        }
    }

    /// 排活：先滚动（最新一段），再按 1h → 4h → 1d → 15m、从近往远回填；已补齐的、
    /// 取过一回还是这个数的不再排。
    #[test]
    fn schedule_rolls_first_then_backfills_near_to_far() {
        let now = 1_790_000_000_000i64;
        let symbols = vec![("BTCUSDT".to_string(), 0i64), ("ETHUSDT".to_string(), 0i64)];
        let jobs = schedule(&HashMap::new(), &symbols, now, &HashMap::new());
        let rolling = PLANS.len() * symbols.len();
        let latest = |p: usize| (now.div_euclid(PLANS[p].step_ms()) - 1).div_euclid(CHUNK);
        assert!(jobs[..rolling].iter().all(|j| j.chunk == latest(j.plan)), "前面全是最新一段");
        let back = &jobs[rolling..];
        assert!(back.windows(2).all(|p| p[0].plan < p[1].plan || (p[0].plan == p[1].plan && p[0].chunk >= p[1].chunk)));
        assert_eq!(back.first().map(|j| PLANS[j.plan].interval), Some("1h"));
        // 全补齐了就没活。
        let mut have = HashMap::new();
        for j in &jobs {
            have.entry((j.symbol.clone(), j.plan)).or_insert_with(HashMap::new).insert(j.chunk, j.want);
        }
        assert!(schedule(&have, &symbols, now, &HashMap::new()).is_empty());
        // 取过一回还差（停牌缺根）：同一个该有数不再排。
        let tried: HashMap<_, _> = jobs.iter().map(|j| ((j.symbol.clone(), j.plan, j.chunk), j.want)).collect();
        assert!(schedule(&HashMap::new(), &symbols, now, &tried).is_empty());
    }

    /// 上市不满一年的品种：上市之前的段不排。
    #[test]
    fn nothing_is_scheduled_before_the_listing() {
        let now = 1_790_000_000_000i64;
        let listed = now - 20 * 86_400_000;
        let jobs = schedule(&HashMap::new(), &[("NEWUSDT".to_string(), listed)], now, &HashMap::new());
        let one_hour = jobs.iter().filter(|j| PLANS[j.plan].interval == "1h").count();
        assert_eq!(one_hour, 1, "20 天的 1h 是 480 根，一段就装下");
        assert!(jobs.iter().all(|j| PLANS[j.plan].interval != "1d"), "20 根日线凑不出 32 根的窗口");
    }
}
