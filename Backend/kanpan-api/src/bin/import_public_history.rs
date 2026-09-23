use anyhow::{Context, Result, bail};
use chrono::{DateTime, Duration, Utc};
use reqwest::Client;
use scorebook_core::domain::{chart_match, criteria::Bar, instrument, interval::Interval};
use serde_json::Value;
use sha2::{Digest, Sha256};
use sqlx::{Postgres, QueryBuilder, postgres::PgPoolOptions};
use uuid::Uuid;

const MARKET: &str = "usd_m";
const RENDER_VERSION: &str = "ohlc-geometry-resample64-v2";
/// 没给 `KANPAN_INDEX_SYMBOLS` 时，按币安 USDⓈ-M 24h 成交额取前这么多只（P3.8）。
const DEFAULT_TOP: usize = 30;
/// 公开 K 线一页的权重是 5（limit 500–1000），分钟上限 2400；同一台机器上 API 自己也在
/// 打币安，这里每页之后歇一下，把导入压在一分钟 ~600 权重以内。
const PAGE_PAUSE: std::time::Duration = std::time::Duration::from_millis(500);
const BINANCE: &str = "https://www.binance.com";

#[derive(Clone)]
struct Config {
    source: String,
    gateway: String,
    symbols: Vec<String>,
    intervals: Vec<String>,
    days: i64,
    window: usize,
    stride: usize,
}

fn env(name: &str, fallback: &str) -> String {
    std::env::var(name).unwrap_or_else(|_| fallback.into())
}

fn csv(name: &str, fallback: &str) -> Vec<String> {
    env(name, fallback)
        .split(',')
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .map(str::to_owned)
        .collect()
}

fn parse_usize(name: &str, fallback: usize) -> Result<usize> {
    env(name, &fallback.to_string()).parse().with_context(|| format!("invalid {name}"))
}

fn config() -> Result<Config> {
    let window = parse_usize("KANPAN_INDEX_WINDOW", 64)?;
    let stride = parse_usize("KANPAN_INDEX_STRIDE", 16)?;
    let days: i64 = env("KANPAN_INDEX_DAYS", "365").parse().context("invalid KANPAN_INDEX_DAYS")?;
    if !(32..=256).contains(&window) || stride == 0 || days <= 0 {
        bail!("index window/stride/days out of bounds");
    }
    // 空列表 = 运行时按成交额取前 DEFAULT_TOP 只（见 `top_symbols`）。
    let symbols = csv("KANPAN_INDEX_SYMBOLS", "");
    let intervals = csv("KANPAN_INDEX_INTERVALS", "15m,1h,4h,1d");
    // 默认 binance：找相似按记录的 venue 过滤 `source`，而复盘只收 binance / coinbase
    // （多交易所阶段 1），okx 来源的窗口再也不会被检索到。
    let source = env("KANPAN_INDEX_SOURCE", "binance");
    if !matches!(source.as_str(), "binance" | "okx") {
        bail!("KANPAN_INDEX_SOURCE must be binance or okx");
    }
    if intervals.is_empty() {
        bail!("index intervals cannot be empty");
    }
    for symbol in &symbols {
        if !instrument::valid_symbol(symbol) {
            bail!("invalid symbol: {symbol}");
        }
    }
    for interval in &intervals {
        Interval::exact(interval).map_err(|_| anyhow::anyhow!("invalid interval: {interval}"))?;
    }
    Ok(Config {
        source,
        gateway: env("KANPAN_MARKET_GATEWAY", "http://127.0.0.1:8792"),
        symbols,
        intervals,
        days,
        window,
        stride,
    })
}

fn ms(t: DateTime<Utc>) -> i64 {
    t.timestamp_millis()
}

fn parse_bar(row: &Value, interval: Interval) -> Result<Bar> {
    let values = row.as_array().context("bar is not an array")?;
    if values.len() < 7 {
        bail!("bar has too few fields");
    }
    let start = DateTime::from_timestamp_millis(values[0].as_i64().context("invalid bar start")?)
        .context("bar start outside timestamp range")?;
    let end = DateTime::from_timestamp_millis(values[6].as_i64().context("invalid bar close")? + 1)
        .context("bar end outside timestamp range")?;
    if interval.floor(start) != start || interval.add_bars(start, 1) != end {
        bail!("bar is not aligned to {interval}");
    }
    let text = |i: usize| -> Result<String> {
        let value = values[i].as_str().context("bar price is not text")?;
        if value.is_empty() {
            bail!("empty bar value");
        }
        Ok(value.to_owned())
    };
    Ok(Bar {
        start,
        end,
        open: text(1)?,
        high: text(2)?,
        low: text(3)?,
        close: text(4)?,
        volume: Some(text(5)?),
    })
}

// One page of a public kline endpoint: every argument is part of that URL, and
// wrapping them in a struct would only move the same eight values one line up.
#[allow(clippy::too_many_arguments)]
async fn fetch_page(client: &Client, source: &str, gateway: &str, symbol: &str, interval: &str, start: i64, end: i64, limit: usize) -> Result<Vec<Bar>> {
    let url = if source == "binance" {
        // `www.binance.com`, not `fapi.binance.com`: both market VPS sit in
        // the United States, where the API host answers 451 and the website
        // host serves the same paths with production data (`market_meta.rs`).
        "https://www.binance.com/fapi/v1/klines".to_owned()
    } else {
        format!("{gateway}/market/v1/klines")
    };
    let start_param = start.to_string();
    let end_param = (end - 1).to_string();
    let limit_param = limit.to_string();
    let mut params = vec![
        ("symbol", symbol),
        ("interval", interval),
        ("startTime", start_param.as_str()),
        ("endTime", end_param.as_str()),
        ("limit", limit_param.as_str()),
    ];
    if source != "binance" {
        params.insert(0, ("source", source));
    }
    let payload = get_json(client, &url, &params).await?;
    let rows = if source == "binance" {
        payload.as_array().context("Binance bars missing")?
    } else {
        if payload["source"] != source || payload["symbol"] != symbol || payload["interval"] != interval {
            bail!("market source identity mismatch");
        }
        payload["bars"].as_array().context("market gateway bars missing")?
    };
    let interval = Interval::exact(interval).map_err(|_| anyhow::anyhow!("invalid interval"))?;
    let bars: Vec<Bar> = rows.iter().map(|row| parse_bar(row, interval)).collect::<Result<_>>()?;
    for pair in bars.windows(2) {
        if pair[0].end != pair[1].start {
            bail!("market gateway returned a gap");
        }
    }
    Ok(bars)
}

/// 一次 GET，带限流退避：429 / 418 听 `Retry-After`（缺省 60 s），网络错与 5xx 退 5 s，
/// 各最多重试 5 次。回来的是 JSON。
async fn get_json(client: &Client, url: &str, params: &[(&str, &str)]) -> Result<Value> {
    let mut attempt = 0;
    loop {
        attempt += 1;
        let wait = match client.get(url).query(params).send().await {
            Ok(response) if response.status().is_success() => return response.json().await.context("invalid market JSON"),
            Ok(response) => {
                let status = response.status().as_u16();
                if !matches!(status, 418 | 429 | 500..=599) {
                    bail!("market request returned HTTP {status}");
                }
                let after = response.headers().get("retry-after").and_then(|v| v.to_str().ok()).and_then(|v| v.parse::<u64>().ok());
                eprintln!("market request HTTP {status}, retry-after={after:?}");
                std::time::Duration::from_secs(if status >= 500 { 5 } else { after.unwrap_or(60) })
            }
            Err(error) => {
                eprintln!("market request failed: {error}");
                std::time::Duration::from_secs(5)
            }
        };
        if attempt > 5 {
            bail!("market request kept failing: {url}");
        }
        tokio::time::sleep(wait).await;
    }
}

/// 币安 USDⓈ-M 里正在交易的 USDT 永续、标的是币（`underlyingType = COIN`，不算美股 /
/// 贵金属 / 指数这类合约），按 24h 计价成交额从大到小取前 `n` 只。
async fn top_symbols(client: &Client, n: usize) -> Result<Vec<String>> {
    let info = get_json(client, &format!("{BINANCE}/fapi/v1/exchangeInfo"), &[]).await?;
    let coins: std::collections::HashSet<String> = info["symbols"]
        .as_array()
        .context("exchangeInfo symbols missing")?
        .iter()
        .filter(|s| s["contractType"] == "PERPETUAL" && s["status"] == "TRADING" && s["quoteAsset"] == "USDT" && s["underlyingType"] == "COIN")
        .filter_map(|s| s["symbol"].as_str().map(str::to_owned))
        .collect();
    let tickers = get_json(client, &format!("{BINANCE}/fapi/v1/ticker/24hr"), &[]).await?;
    let mut ranked: Vec<(f64, String)> = tickers
        .as_array()
        .context("24hr tickers missing")?
        .iter()
        .filter_map(|t| {
            let symbol = t["symbol"].as_str()?;
            let volume = t["quoteVolume"].as_str()?.parse::<f64>().ok()?;
            (coins.contains(symbol) && instrument::valid_symbol(symbol)).then(|| (volume, symbol.to_owned()))
        })
        .collect();
    ranked.sort_by(|a, b| b.0.total_cmp(&a.0).then_with(|| a.1.cmp(&b.1)));
    let top: Vec<String> = ranked.into_iter().take(n).map(|(_, symbol)| symbol).collect();
    if top.len() < n {
        bail!("only {} tradable coin perpetuals found", top.len());
    }
    Ok(top)
}

async fn fetch_range(client: &Client, cfg: &Config, symbol: &str, interval_name: &str) -> Result<Vec<Bar>> {
    let interval = Interval::exact(interval_name).map_err(|_| anyhow::anyhow!("invalid interval"))?;
    let end = interval.floor(Utc::now());
    let start = interval.floor(end - Duration::days(cfg.days));
    let mut cursor = start;
    let mut all = Vec::new();
    while cursor < end {
        let page = fetch_page(client, &cfg.source, &cfg.gateway, symbol, interval_name, ms(cursor), ms(end), if cfg.source == "binance" {1000} else {1500}).await?;
        if page.is_empty() {
            break;
        }
        // 上市不满 `days` 天的品种：第一页从它的第一根开始，就从那儿算起；
        // 之后的每一页仍然必须严丝合缝地接上。
        if page[0].start != cursor {
            if !all.is_empty() || page[0].start < cursor {
                bail!("market gateway did not cover the requested start");
            }
            cursor = page[0].start;
        }
        let next = page.last().unwrap().end;
        if next <= cursor {
            bail!("market gateway pagination stalled");
        }
        all.extend(page);
        cursor = next;
        tokio::time::sleep(PAGE_PAUSE).await;
    }
    if all.last().is_none_or(|bar| bar.end != end) {
        bail!("market gateway did not cover the requested end");
    }
    Ok(all)
}

fn input_hash(bars: &[Bar]) -> String {
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

struct Feature {
    start: i64,
    end: i64,
    bars_count: i32,
    embedding: String,
    input_hash: String,
}

fn make_feature(bars: &[Bar]) -> Result<Feature> {
    let candles = chart_match::from_bars(bars).map_err(|e| anyhow::anyhow!("invalid geometry input: {e:?}"))?;
    let vector = chart_match::descriptor(&candles).map_err(|e| anyhow::anyhow!("descriptor failed: {e:?}"))?;
    Ok(Feature {
        start: ms(bars.first().unwrap().start),
        end: ms(bars.last().unwrap().end),
        bars_count: bars.len() as i32,
        embedding: format!("{vector:?}"),
        input_hash: input_hash(bars),
    })
}

async fn insert_windows(pool: &sqlx::PgPool, source: &str, symbol: &str, interval: &str, windows: &[&[Bar]]) -> Result<usize> {
    let features: Vec<Feature> = windows.iter().map(|bars| make_feature(bars)).collect::<Result<_>>()?;
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
        let result = query.build().execute(pool).await?;
        inserted += result.rows_affected() as usize;
    }
    Ok(inserted)
}

#[tokio::main]
async fn main() -> Result<()> {
    let mut cfg = config()?;
    let database = std::env::var("KANPAN_DATABASE_URL").context("KANPAN_DATABASE_URL is required")?;
    let pool = PgPoolOptions::new().max_connections(4).connect(&database).await?;
    let client = Client::builder().timeout(std::time::Duration::from_secs(60)).build()?;
    if cfg.symbols.is_empty() {
        if cfg.source != "binance" {
            bail!("KANPAN_INDEX_SYMBOLS is required when KANPAN_INDEX_SOURCE is not binance");
        }
        cfg.symbols = top_symbols(&client, DEFAULT_TOP).await?;
    }
    eprintln!("symbols ({}): {}", cfg.symbols.len(), cfg.symbols.join(","));
    let started = std::time::Instant::now();
    let mut inserted = 0usize;
    let mut seen = 0usize;
    let mut failed: Vec<String> = Vec::new();
    for interval in &cfg.intervals {
        for symbol in &cfg.symbols {
            eprintln!("indexing {}/{symbol}/{interval}", cfg.source);
            // 一只拉不下来不拖垮其余二十九只：记下来，最后按失败退出。
            let bars = match fetch_range(&client, &cfg, symbol, interval).await {
                Ok(bars) => bars,
                Err(error) => {
                    eprintln!("skipped {}/{symbol}/{interval}: {error:#}", cfg.source);
                    failed.push(format!("{symbol}/{interval}"));
                    continue;
                }
            };
            let windows: Vec<&[Bar]> = (0..)
                .map(|n| n * cfg.stride)
                .take_while(|offset| offset + cfg.window <= bars.len())
                .map(|offset| &bars[offset..offset + cfg.window])
                .collect();
            seen += windows.len();
            inserted += insert_windows(&pool, &cfg.source, symbol, interval, &windows).await?;
            eprintln!("indexed {}/{symbol}/{interval}: {} bars, {} windows", cfg.source, bars.len(), windows.len());
        }
    }
    println!("public history import complete: seen={seen} inserted={inserted} failed={} elapsed={}s", failed.len(), started.elapsed().as_secs());
    if !failed.is_empty() {
        bail!("failed: {}", failed.join(","));
    }
    Ok(())
}
