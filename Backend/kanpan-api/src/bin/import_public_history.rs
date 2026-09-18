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
const DEFAULT_SYMBOLS: &str = "BTCUSDT,ETHUSDT,SOLUSDT,XRPUSDT,BNBUSDT,DOGEUSDT,ADAUSDT,LINKUSDT,AVAXUSDT,SUIUSDT";

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
    Ok(env(name, &fallback.to_string()).parse().with_context(|| format!("invalid {name}"))?)
}

fn config() -> Result<Config> {
    let window = parse_usize("KANPAN_INDEX_WINDOW", 64)?;
    let stride = parse_usize("KANPAN_INDEX_STRIDE", 16)?;
    let days: i64 = env("KANPAN_INDEX_DAYS", "180").parse().context("invalid KANPAN_INDEX_DAYS")?;
    if !(32..=256).contains(&window) || stride == 0 || days <= 0 {
        bail!("index window/stride/days out of bounds");
    }
    let symbols = csv("KANPAN_INDEX_SYMBOLS", DEFAULT_SYMBOLS);
    let intervals = csv("KANPAN_INDEX_INTERVALS", "1h");
    let source = env("KANPAN_INDEX_SOURCE", "okx");
    if !matches!(source.as_str(), "binance" | "okx") {
        bail!("KANPAN_INDEX_SOURCE must be binance or okx");
    }
    if symbols.is_empty() || intervals.is_empty() {
        bail!("index symbols and intervals cannot be empty");
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
    let payload: Value = client
        .get(url)
        .query(&params)
        .send()
        .await
        .context("market gateway request failed")?
        .error_for_status()
        .context("market gateway returned an error")?
        .json()
        .await
        .context("invalid market gateway JSON")?;
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

async fn fetch_range(client: &Client, cfg: &Config, symbol: &str, interval_name: &str) -> Result<Vec<Bar>> {
    let interval = Interval::exact(interval_name).map_err(|_| anyhow::anyhow!("invalid interval"))?;
    let end = interval.floor(Utc::now());
    let start = interval.floor(end - Duration::days(cfg.days));
    let mut cursor = start;
    let mut all = Vec::new();
    while cursor < end {
        let page = fetch_page(&client, &cfg.source, &cfg.gateway, symbol, interval_name, ms(cursor), ms(end), if cfg.source == "binance" {1000} else {1500}).await?;
        if page.is_empty() {
            break;
        }
        if page[0].start != cursor {
            bail!("market gateway did not cover the requested start");
        }
        let next = page.last().unwrap().end;
        if next <= cursor {
            bail!("market gateway pagination stalled");
        }
        all.extend(page);
        cursor = next;
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
    let cfg = config()?;
    let database = std::env::var("KANPAN_DATABASE_URL").context("KANPAN_DATABASE_URL is required")?;
    let pool = PgPoolOptions::new().max_connections(4).connect(&database).await?;
    let client = Client::builder().timeout(std::time::Duration::from_secs(60)).build()?;
    let mut inserted = 0usize;
    let mut seen = 0usize;
    for interval in &cfg.intervals {
        for symbol in &cfg.symbols {
            eprintln!("indexing {}/{symbol}/{interval}", cfg.source);
            let bars = fetch_range(&client, &cfg, symbol, interval).await?;
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
    println!("public history import complete: seen={seen} inserted={inserted}");
    Ok(())
}
