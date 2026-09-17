# Kanpan personal API

Username/password registration, sessions, personal preferences, drawings, favorites and native review. Email registration/reset is disabled. Runtime data belongs to the authenticated user; PostgreSQL RLS is forced on personal tables. The runtime database role must neither own tables nor bypass RLS.

## Deployment

Build with `cargo build --release`. Copy source and binary under `/opt/kanpan-api`; run `python3 ops/install.py` as root on a host with Docker and systemd. It creates a dedicated pgvector PostgreSQL container (`kanpan-postgres`, loopback port 55434), migrates with the admin role, and grants the separate runtime role table access. Root-only secrets live in `/etc/kanpan-api/`; repeated installation reuses them. No SMTP is needed.

The API binds to `127.0.0.1:8794`; Caddy forwards `/v1/auth/*`, `/v1/sync/*`, `/v1/native-review/*`, `/v1/capabilities`. Do not reuse ports 8790/8791: the existing image service uses them. Services `kanpan-api` and `kanpan-worker` run as dynamic, restricted users. `kanpan-backup.timer` writes daily PostgreSQL custom-format dumps with 30-day retention. These are local server backups, not offsite disaster recovery.

The existing Scorebook services are separate. Frozen `vendor/scorebook-core` and market adapter sources are reused without modifying those services. OKX review OHLC uses the local market gateway at port 8792 with explicit source identity. No Binance candles are substituted into OKX records. Unsupported exact trade-touch evidence remains `needs_verification`.

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
