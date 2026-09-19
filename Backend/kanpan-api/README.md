# Kanpan personal API

Username/password registration, sessions, personal preferences, drawings, favorites and native review. Email registration/reset is disabled. Runtime data belongs to the authenticated user; PostgreSQL RLS is forced on personal tables. The runtime database role must neither own tables nor bypass RLS.

## Deployment

Build with `cargo build --release`. Copy source and binary under `/opt/kanpan-api`; run `python3 ops/install.py` as root on a host with Docker and systemd. It creates a dedicated pgvector PostgreSQL container (`kanpan-postgres`, loopback port 55434), migrates with the admin role, and grants the separate runtime role table access. Root-only secrets live in `/etc/kanpan-api/`; repeated installation reuses them. No SMTP is needed.

The API binds to `127.0.0.1:8794`; Caddy forwards `/v1/auth/*`, `/v1/sync/*`, `/v1/native-review/*`, `/v1/capabilities`, `/v1/market/*` and `/oi/v1/metrics/*`. The last of these is the historical open-interest archive, which was moved here from the Python gateway because that service read the daily zips four at a time on connections it opened per day, so a cold year of chart took 54 s. It keeps its day slices under `CacheDirectory=kanpan-api` (`KANPAN_OI_CACHE`, `KANPAN_OI_CACHE_BYTES`, 4 GiB by default, and `KANPAN_OI_CACHE_FILES`, 200 000 entries — the byte budget alone cannot bound a directory whose zero-byte "this day is not in the archive" markers are free, and those markers are what eviction drops first) in the same format the gateway wrote, so an existing `/var/cache/private/kanpan-gateway` can simply be copied in. Without a writable cache the routes still answer; they just pay the network every time. The gateway keeps the streams and `/market/v1/*`. Do not reuse ports 8790/8791: the existing image service uses them. Services `kanpan-api` and `kanpan-worker` run as dynamic, restricted users. `kanpan-backup.timer` writes daily PostgreSQL custom-format dumps with 30-day retention; it applies that retention and sweeps stale `.part` files at the top of the run, before the space check, so a filesystem already full of old dumps cannot lock the job out of ever clearing them; it then refuses up front, writing nothing, if the filesystem does not hold twice the last dump's size, and it removes its own half-written `.part` on any failure. These are local server backups, not offsite disaster recovery — that is `ops/OFFSITE.md`, including the restore drill, whose one rule is `pg_restore` first and `migrate` after.

The existing Scorebook services are separate. Frozen `vendor/scorebook-core` and market adapter sources are reused without modifying those services. OKX review OHLC uses the local market gateway at port 8792 with explicit source identity. No Binance candles are substituted into OKX records. Unsupported exact trade-touch evidence remains `needs_verification`.

## Public market metadata

`/v1/market/meta` and `/v1/market/open-interest` are the only routes with no
owner and no database behind them: they are a cache in front of public
upstreams, refreshed in the background and served stale while refreshing.

`meta` publishes, per contract symbol, what the phone multiplies the live price
by to get a market capitalisation. For a coin that is its supply. For a
perpetual whose underlying is not a coin — US, Hong Kong, Korean and Shanghai
listings, ETFs, metals and indices — it is
`company capitalisation in USD / that contract's own price`, which absorbs the
quote currency, the depositary ratio and dual-class structure at once. A
contract we cannot identify is left out rather than guessed at. Upstreams are
stockanalysis.com, open.er-api.com and `www.binance.com/fapi/v1/*` — note the
host: `fapi.binance.com` answers 451 from this US server, `www.binance.com`
does not. The full rule, the source table and the per-family audit are in
`docs/市值口径与数据来源-2026-09-18.md` at repository root — that document
predates this round, which removed the two pre-IPO keywords and added the
`unknown` class below.

Classification is fail-closed. Binance's `underlyingType` maps to exactly one
kind, and anything else — an absent field, an empty string, a value this build
has never seen, a contract missing from `exchangeInfo` altogether — becomes
`unknown`, which publishes nothing. The wire values are `crypto`, `equityUS`,
`equityNamed`, `preMarket`, `other` and `unknown`; `preMarket`, `other` and
`unknown` never carry a multiplier, so a pre-IPO contract is blank by
construction rather than by keyword.

Nothing published is older than its shelf life. A supply or equity multiplier
whose refresh is more than **7 days** old stops being served; the open-interest
notional price falls back to a cached quote only within **5 minutes**, and the
OKX open-interest table only within **15 minutes**. The snapshot on disk carries
the time each figure was taken, so a restart cannot reset those clocks. None of
this is visible on the wire: an expired figure is an absent field, never a stale
number and never a timestamp or a source name for the phone to render.

`GET /v1/market/meta` with no `symbols` argument answers the whole table it can
prove: every equity contract symbol in sorted order, then every coin base as
`<base>USDT` in sorted order, capped at 1000 entries — equities first so a few
hundred listings cannot be crowded out by thousands of coins. A coin base
becomes a `<base>USDT` key only when the contract of that name really is a coin
(`COINUSDT` is Coinbase, not a coin called COIN), and every row goes through the
same lookup the filtered form uses, so unknown classes and expired figures are
simply absent. The response shape is identical either way: a map from contract
symbol to that contract's fields, inside the usual `{"data":…}` envelope. Which
source a figure was adopted from is kept internally (it is what stops a
`1000`-prefixed contract from being scaled twice) and is never serialised.

`open-interest` reads Binance or OKX live; `oi_archive` keeps the history on
disk and warms its index at startup.

Every call this process makes to `binance.com` — metadata, daily closes, the
contract list behind the archive warm-up — shares one ban deadline
(`src/binance_gate.rs`). A 429 or 418 anywhere sets it, `Retry-After` is
believed, 418 never waits less than two minutes, the deadline only ever grows,
and while it stands nothing leaves for that host; a collector that hits it stops
the round instead of recording several hundred per-contract failures.
`data.binance.vision` is a different service and has its own rule: 403, a
timeout or a 5xx is only ever "not fetched", never a gap — three refusals in a
row hold that source for five minutes so a walk backwards through the calendar
cannot repeat one refusal several hundred times.

## Daily closes for sector strength

`/v1/market/sector-history` is the third ownerless route, and the only one with
a table behind it. Sector strength over five and twenty days needs the close
five and twenty complete UTC days ago; the phone divides its live price by
those. It answers `{"asof":"YYYY-MM-DD","symbols":{"BTCUSDT":{"c5":…,"c20":…}}}`
inside the usual `{"data":…}` envelope, with `Cache-Control: public,
max-age=3600`. A figure we do not have is an absent field, never a zero — the
phone divides by it — and a contract with neither figure is left out. The whole
market is about thirty kilobytes, so the served body is a process cache, rebuilt
after every collection and whenever the UTC day turns under it.

`sector_history::spawn_daily` collects at 00:10 UTC, and immediately at startup
if that day's sweep has not run. It reads the perpetuals that are `TRADING` from
`www.binance.com/fapi/v1/exchangeInfo` — the same host and the same fetch
`market_meta` uses, for the same 451 reason — then one `klines?interval=1d` per
contract at a global one request per second, backing off on 429 and 418. Today's
unfinished candle is dropped, so only settled days are stored; a contract that
fails is logged and skipped rather than failing the sweep. Rows older than a
year are deleted, and a contract that has left `exchangeInfo` keeps its history
for thirty days. Seven hundred contracts is a twelve minute sweep once a day and
about thirteen megabytes a year.

The table, `daily_close(symbol, day, close, quote_volume)`, is public market
data: no owner column and no row level security, like `market_features`. The
runtime role still neither owns it nor bypasses RLS — `ops/install.py` grants it
the four statement rights on everything in the schema after the admin role
migrates. Caddy's existing `/v1/market/*` rule already forwards the route.

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
