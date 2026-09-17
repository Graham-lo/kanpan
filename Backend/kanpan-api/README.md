# Kanpan personal API

Username/password registration, sessions, personal preferences, drawings, favorites and native review. Email registration/reset is disabled. Runtime data belongs to the authenticated user; PostgreSQL RLS is forced on personal tables. The runtime database role must neither own tables nor bypass RLS.

## Deployment

Build with `cargo build --release`. Copy source and binary under `/opt/kanpan-api`; run `python3 ops/install.py` as root on a host with Docker and systemd. It creates a dedicated pgvector PostgreSQL container (`kanpan-postgres`, loopback port 55434), migrates with the admin role, and grants the separate runtime role table access. Root-only secrets live in `/etc/kanpan-api/`; repeated installation reuses them. No SMTP is needed.

The API binds to `127.0.0.1:8794`; Caddy forwards `/v1/auth/*`, `/v1/sync/*`, `/v1/native-review/*`, `/v1/capabilities`, `/v1/market/*` and `/oi/v1/metrics/*`. The last of these is the historical open-interest archive, which was moved here from the Python gateway because that service read the daily zips four at a time on connections it opened per day, so a cold year of chart took 54 s. It keeps its day slices under `CacheDirectory=kanpan-api` (`KANPAN_OI_CACHE`, `KANPAN_OI_CACHE_BYTES`, 4 GiB by default) in the same format the gateway wrote, so an existing `/var/cache/private/kanpan-gateway` can simply be copied in. Without a writable cache the routes still answer; they just pay the network every time. The gateway keeps the streams and `/market/v1/*`. Do not reuse ports 8790/8791: the existing image service uses them. Services `kanpan-api` and `kanpan-worker` run as dynamic, restricted users. `kanpan-backup.timer` writes daily PostgreSQL custom-format dumps with 30-day retention. These are local server backups, not offsite disaster recovery.

The existing Scorebook services are separate. Frozen `vendor/scorebook-core` and market adapter sources are reused without modifying those services. OKX review OHLC uses the local market gateway at port 8792 with explicit source identity. No Binance candles are substituted into OKX records. Unsupported exact trade-touch evidence remains `needs_verification`.

## Public market metadata

`/v1/market/meta` and `/v1/market/open-interest` are the only routes with no
owner and no database behind them: they are a cache in front of public
upstreams, refreshed in the background and served stale while refreshing.

`meta` publishes, per contract symbol, what the phone multiplies the live price
by to get a market capitalisation. For a coin that is its supply. For the 193
perpetuals whose underlying is not a coin — US, Hong Kong, Korean and Shanghai
listings, ETFs, metals, indices and two pre-IPO names — it is
`company capitalisation in USD / that contract's own price`, which absorbs the
quote currency, the depositary ratio and dual-class structure at once. A
contract we cannot identify is left out rather than guessed at. Upstreams are
stockanalysis.com, open.er-api.com and `www.binance.com/fapi/v1/*` — note the
host: `fapi.binance.com` answers 451 from this US server, `www.binance.com`
does not. The full rule, the source table and the per-family audit are in
`docs/市值口径与数据来源-2026-09-18.md` at repository root.

`open-interest` reads Binance or OKX live; `oi_archive` keeps the history on
disk and warms its index at startup.

## Validation / current boundary

`cargo test` includes unit tests; the integration suite needs its dedicated PostgreSQL test configuration and must never target production. Tests cover username registration, session rotation/retry, isolation, field merge, deletion tombstones and private native-review search.

The public similarity index is populated by an explicit, provenance-bound history import. The current seed covers Binance and OKX USDⓈ-M 1h candles for ten liquid USDT perpetuals over the latest 180 days; it is a useful seed, not full-market coverage. Personal OHLC search is available. Exact OKX trade-touch adjudication is not available through candle data alone. See `docs/账号复盘-实施进度.md` at repository root for device evidence and remaining review interactions.

To extend the public seed on the main host, run the release importer with the API service environment loaded:

```sh
cd /opt/kanpan-api
set -a; . /etc/kanpan-api/service.env; set +a
KANPAN_INDEX_SYMBOLS=BTCUSDT,ETHUSDT \
KANPAN_INDEX_INTERVALS=1h \
KANPAN_INDEX_DAYS=180 \
target/release/import_public_history
```

The importer reads the official Binance REST endpoint when `KANPAN_INDEX_SOURCE=binance`, or the local OKX market gateway when `KANPAN_INDEX_SOURCE=okx`; it validates candle continuity and the frozen `candle-geometry-v2` descriptor, and is idempotent on the public-window identity.
