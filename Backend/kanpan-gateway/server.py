"""Bounded public history service for OI and complete market-source fallback."""
import csv
import datetime as dt
import io
import json
import math
import os
from pathlib import Path
import re
import select
import socket
import sys
import tempfile
import threading
import time as time_module
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.request import urlopen
from urllib.parse import urlsplit, parse_qs
import zipfile
import ipaddress
from resource_limits import HTTPGuard
from market_rest import MARKET, Blocked, RateLimited, Unavailable

CACHE = Path(os.environ.get('KANPAN_OI_CACHE', '/var/cache/kanpan-gateway'))
LIMIT = 200 * 1024 * 1024
POOL = ThreadPoolExecutor(max_workers=8)
LOCK = threading.Lock()
PENDING = {}
PATTERN = re.compile(r'^/oi/v1/metrics/([A-Z0-9_]{1,30})/(\d{4}-\d{2}-\d{2})\.json$')
RANGE_PATTERN = re.compile(r'^/oi/v1/metrics/([A-Z0-9_]{1,30})/range$')
# Separate pools: an OI backfill must never starve the chart's klines/ticker
# requests, and neither may take the whole worker budget on its own.
RANGE_SLOTS = threading.BoundedSemaphore(16)
MARKET_SLOTS = threading.BoundedSemaphore(16)
# One resident pool instead of a new ThreadPoolExecutor per range request.
READERS = ThreadPoolExecutor(max_workers=32, thread_name_prefix='oi-read')
HTTP_GUARD = HTTPGuard()
DAY = 86_400_000
STEPS = {'1m': 60_000, '3m': 180_000, '5m': 300_000, '15m': 900_000,
         '30m': 1_800_000, '1h': 3_600_000, '2h': 7_200_000, '4h': 14_400_000,
         '6h': 21_600_000, '12h': 43_200_000, '1d': DAY, '1w': 7 * DAY,
         '1M': 30 * DAY, '1y': 365 * DAY}


def bucket_start(time, interval):
    if interval in ('1m', '3m'):
        return time  # Source cadence is 5m: do not invent sub-minute observations.
    if interval == '1w':
        return (time - 4 * DAY) // (7 * DAY) * (7 * DAY) + 4 * DAY
    if interval in ('1M', '1y'):
        date = dt.datetime.fromtimestamp(time / 1000, dt.timezone.utc)
        start = date.replace(month=1 if interval == '1y' else date.month,
                             day=1, hour=0, minute=0, second=0, microsecond=0)
        return int(start.timestamp() * 1000)
    return time // STEPS[interval] * STEPS[interval]


def historical_series(symbol, interval, start, end):
    """Aggregate ordered daily archives: last observation, never sum OI like volume."""
    now = int(dt.datetime.now(dt.timezone.utc).timestamp() * 1000)
    epoch = int(dt.datetime(2020, 9, 1, tzinfo=dt.timezone.utc).timestamp() * 1000)
    if interval not in STEPS or not epoch <= start <= end < now:
        raise ValueError('invalid historical range')
    if end - start > min(3660 * DAY, 20_000 * max(300_000, STEPS[interval])):
        raise ValueError('range too large')
    first = start // DAY
    last = min(end // DAY, now // DAY - 1)
    buckets = {}

    def read(day):
        date = dt.datetime.fromtimestamp(day * 86400, dt.timezone.utc).date().isoformat()
        try:
            return json.loads(cached_day(symbol, date)[0])
        except HTTPError as error:
            if error.code == 404:
                return []  # Missing days remain gaps; never persist synthetic values.
            raise

    # Bounded batches keep years of 5m raw data off the phone and out of server RAM.
    # The pool is resident: a range request no longer pays for creating and
    # tearing down two OS threads before it can read the first day.
    for base in range(first, last + 1, 4):
        for points in READERS.map(read, range(base, min(base + 4, last + 1))):
            for time, value in points:
                if start <= time <= end:
                    buckets[bucket_start(time, interval)] = value
    return json.dumps([[time, buckets[time]] for time in sorted(buckets)], separators=(',', ':')).encode()


def parse_archive(data):
    points = {}
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        for entry in archive.infolist():
            if not entry.filename.endswith('.csv'):
                continue
            if entry.file_size > 20 * 1024 * 1024:
                raise ValueError('archive too large')
            text = io.TextIOWrapper(archive.open(entry), encoding='utf-8-sig')
            for row in csv.DictReader(text):
                time = dt.datetime.fromisoformat(row['create_time']).replace(tzinfo=dt.timezone.utc)
                value = float(row['sum_open_interest'])
                if math.isfinite(value) and value >= 0:
                    points[int(time.timestamp() * 1000)] = value
    return json.dumps([[time, points[time]] for time in sorted(points)], separators=(',', ':')).encode()


class CacheIndex:
    """In-process view of the day-slice cache.

    The eviction sweep used to stat every file in the cache directory while
    holding the global lock, so one archive download blocked every other OI
    reader for the length of a full directory scan. The directory is scanned
    once (lazily, and again if the cache root is repointed) and then kept up to
    date incrementally.
    """

    def __init__(self):
        self.lock = threading.Lock()
        self.root = None
        self.entries = {}
        self.bytes = 0

    def _scan(self, root):
        entries, total = {}, 0
        for path in root.glob('*.json'):
            try:
                status = path.stat()
            except OSError:
                continue
            entries[path] = [status.st_size, status.st_mtime]
            total += status.st_size
        self.root, self.entries, self.bytes = root, entries, total

    def _ensure(self, root):
        if self.root != root:
            self._scan(root)

    def warm(self, root):
        with self.lock:
            self._scan(root)

    def touch(self, root, path, mtime):
        with self.lock:
            self._ensure(root)
            entry = self.entries.get(path)
            if entry:
                entry[1] = mtime

    def store(self, root, path, size, mtime, limit):
        """Record a freshly written slice and return the paths to unlink."""
        with self.lock:
            self._ensure(root)
            old = self.entries.get(path)
            if old:
                self.bytes -= old[0]
            self.entries[path] = [size, mtime]
            self.bytes += size
            evicted = []
            for victim in sorted(self.entries, key=lambda k: self.entries[k][1]):
                if self.bytes <= limit:
                    break
                if victim == path:
                    continue  # never drop the slice this request just produced
                self.bytes -= self.entries.pop(victim)[0]
                evicted.append(victim)
            return evicted


INDEX = CacheIndex()


def fetch_day(symbol, day):
    path = CACHE / f'{symbol}-{day}.json'
    try:
        data = path.read_bytes()
        os.utime(path, None)
        INDEX.touch(CACHE, path, time_module.time())
        return data, 'HIT'
    except FileNotFoundError:
        pass
    url = f'https://data.binance.vision/data/futures/um/daily/metrics/{symbol}/{symbol}-metrics-{day}.zip'
    with urlopen(url, timeout=15) as response:
        data = response.read(2 * 1024 * 1024 + 1)
    if len(data) > 2 * 1024 * 1024:
        raise ValueError('download too large')
    payload = parse_archive(data)
    # Only complete, nonempty historical results are cached. Failures remain retryable.
    if payload != b'[]':
        CACHE.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=CACHE, delete=False) as out:
            out.write(payload)
            temporary = out.name
        os.replace(temporary, path)
        for victim in INDEX.store(CACHE, path, len(payload), time_module.time(), LIMIT):
            victim.unlink(missing_ok=True)
    return payload, 'MISS'


def cached_day(symbol, day):
    key = (symbol, day)
    with LOCK:
        # Completed abandoned requests must not permanently fill the bounded pending table.
        for finished in [k for k, value in PENDING.items() if value.done()]:
            del PENDING[finished]
        future = PENDING.get(key)
        if future is None:
            if len(PENDING) >= 64:
                raise RuntimeError('busy')
            future = POOL.submit(fetch_day, symbol, day)
            PENDING[key] = future
    try:
        return future.result(timeout=22)
    finally:
        with LOCK:
            if future.done() and PENDING.get(key) is future:
                del PENDING[key]


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    refund = False

    def reply(self, status, payload, cache='no-store', hit=None, extra=()):
        extra = list(extra)
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.send_header('Cache-Control', cache)
        # A caller that already knows the real deadline sends it in `extra`; the
        # flat 2 s is only the fallback for this node being momentarily busy, and
        # must never override, or duplicate, an upstream's own Retry-After.
        if status in (429, 503) and not any(name.lower() == 'retry-after' for name, _ in extra):
            self.send_header('Retry-After', '2')
        if hit:
            self.send_header('X-OI-Cache', hit)
        for name, value in extra:
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(payload)

    def blocked(self, source):
        """A geographic block upstream is a stable, client-readable answer.

        It is not the caller's mistake either, so it must not spend the peer's
        quota: the phone switches source and would otherwise be rate limited
        for doing exactly the right thing.
        """
        self.refund = True
        payload = json.dumps({'error': 'upstream_blocked', 'source': source, 'code': 451},
                             separators=(',', ':')).encode()
        return self.reply(451, payload, 'no-store', extra=[('X-Kanpan-Upstream', source + '-blocked')])

    def rate_limited(self, limited):
        """The exchange told this node to stop, and the phone must hear that.

        Flattened into a 503 it looked like "this gateway is unwell", so the phone
        tried the other node and then this one again a couple of seconds later --
        the one behaviour that lengthens a ban. So it travels as 429 plus the real
        deadline in both the header and the body, and `error` says who is limited:
        `upstream_rate_limited` here versus `busy` for this node's own admission
        control, which is the same status code but the opposite advice.

        Unlike a geographic block this does not refund the caller's local quota:
        the correct response is to wait, so a client that keeps asking anyway
        should also meet this node's own limiter.
        """
        payload = json.dumps({'error': 'upstream_rate_limited', 'source': limited.source,
                              'code': 429, 'retryAfter': limited.retry_after,
                              'upstreamStatus': limited.upstream_status},
                             separators=(',', ':')).encode()
        return self.reply(429, payload, 'no-store',
                          extra=[('Retry-After', str(limited.retry_after)),
                                 ('X-Kanpan-Upstream', limited.source + '-limited')])

    def abandoned(self):
        """True once the client closed the connection: skip the upstream fetch.

        The socket carries a 30 s timeout, and a timed-out socket's recv() polls
        for readability *before* honouring MSG_DONTWAIT -- it would park this
        thread for the full timeout. So ask select() first with a zero wait;
        only a readable socket (data or EOF) is ever peeked.
        """
        try:
            readable, _, _ = select.select([self.connection], [], [], 0)
            if not readable:
                return False  # idle keep-alive: nothing pending, nothing closed
            return self.connection.recv(1, socket.MSG_PEEK | socket.MSG_DONTWAIT) == b''
        except (BlockingIOError, InterruptedError):
            return False
        except OSError:
            return True
        except (AttributeError, ValueError, TypeError):
            return False  # non-socket connection objects keep the old behaviour

    def give_up(self):
        self.close_connection = True
        self.refund = True

    def do_GET(self):
        key = self.client_address[0]
        try:
            if ipaddress.ip_address(key).is_loopback:
                key = str(ipaddress.ip_address(self.headers.get('X-Kanpan-Client-IP', key)))
        except ValueError:
            pass
        if not HTTP_GUARD.enter(key):
            return self.reply(429, b'{"error":"busy"}')
        self.refund = False
        try:
            self.get_market_data()
        finally:
            HTTP_GUARD.leave(key, refund=self.refund)

    def get_market_data(self):
        if self.path == '/chart-gateway/health':
            return self.reply(200, b'{"status":"ok","service":"kanpan-gateway"}')
        parts = urlsplit(self.path)
        if parts.path in ('/market/v1/klines', '/market/v1/ticker', '/market/v1/tickers',
                          '/market/v1/instruments'):
            # Market requests own their slots: an OI backfill cannot starve the chart.
            if not MARKET_SLOTS.acquire(blocking=False):
                return self.reply(503, b'{"error":"busy"}')
            try:
                query = parse_qs(parts.query, strict_parsing=True)
                if any(len(v) != 1 for v in query.values()):
                    raise ValueError('duplicate query')
                q = {k: v[0] for k, v in query.items()}
                source = q.pop('source')
                if source not in ('binance', 'okx'):
                    raise ValueError('invalid source')
                if parts.path.endswith('/klines'):
                    if set(q) - {'symbol', 'interval', 'limit', 'startTime', 'endTime'}:
                        raise ValueError('invalid query')
                    arguments = (source, q['symbol'], q['interval'], int(q.get('limit', '300')),
                                 int(q['startTime']) if 'startTime' in q else None,
                                 int(q['endTime']) if 'endTime' in q else None)
                    MARKET.validate_klines(*arguments)
                    if self.abandoned():
                        return self.give_up()
                    payload = MARKET.klines_response(*arguments)
                elif parts.path.endswith('/ticker'):
                    if set(q) != {'symbol'} or not re.fullmatch(r'[A-Z0-9_]{1,30}', q['symbol']):
                        raise ValueError('invalid symbol')
                    if self.abandoned():
                        return self.give_up()
                    payload = MARKET.ticker_response(source, q['symbol'])
                elif parts.path.endswith('/tickers'):
                    # Whole market, no symbol: the sector page reads one array.
                    if q:
                        raise ValueError('invalid query')
                    if self.abandoned():
                        return self.give_up()
                    payload = MARKET.tickers_response(source)
                else:
                    if q:
                        raise ValueError('invalid query')
                    if self.abandoned():
                        return self.give_up()
                    payload = MARKET.instruments_response(source)
                return self.reply(200, payload, 'no-store')
            except RateLimited as limited:
                return self.rate_limited(limited)
            except Blocked as blocked:
                return self.blocked(blocked.source)
            except (KeyError, ValueError, TypeError):
                return self.reply(400, b'{"error":"invalid market request"}')
            except (Unavailable, HTTPError, OSError, TimeoutError, RuntimeError) as error:
                # The phone only needs "unavailable"; the journal needs why, or a
                # 503 can't be told apart from a dead pool, a cooldown or pacing.
                cause = error.__cause__
                sys.stderr.write('kanpan-gateway: 503 %s: %r%s\n' % (
                    parts.path, error, ' from %r' % cause if cause else ''))
                return self.reply(503, b'{"error":"market unavailable"}')
            finally:
                MARKET_SLOTS.release()
        range_match = RANGE_PATTERN.fullmatch(parts.path)
        if range_match:
            if not RANGE_SLOTS.acquire(blocking=False):
                return self.reply(503, b'{"error":"busy"}')
            try:
                query = parse_qs(parts.query, strict_parsing=True)
                if set(query) != {'interval', 'from', 'to'} or any(len(v) != 1 for v in query.values()):
                    raise ValueError('invalid query')
                if self.abandoned():
                    return self.give_up()
                payload = historical_series(range_match[1], query['interval'][0],
                                            int(query['from'][0]), int(query['to'][0]))
                return self.reply(200, payload, 'public, max-age=3600')
            except (ValueError, KeyError):
                return self.reply(400, b'{"error":"invalid historical range"}')
            except (HTTPError, OSError, TimeoutError, RuntimeError, zipfile.BadZipFile):
                return self.reply(502, b'{"error":"archive unavailable"}')
            finally:
                RANGE_SLOTS.release()
        match = PATTERN.fullmatch(self.path)
        if not match:
            return self.reply(404, b'{"error":"not found"}')
        symbol, day = match.groups()
        try:
            date = dt.date.fromisoformat(day)
            if date < dt.date(2020, 9, 1) or date >= dt.datetime.now(dt.timezone.utc).date():
                return self.reply(404, b'{"error":"no archive for date"}')
            if self.abandoned():
                return self.give_up()
            payload, hit = cached_day(symbol, day)
            return self.reply(200, payload, 'public, max-age=86400', hit)
        except HTTPError as error:
            return self.reply(404 if error.code == 404 else 502, b'{"error":"archive unavailable"}')
        except (ValueError, KeyError, OSError, TimeoutError, RuntimeError, zipfile.BadZipFile):
            return self.reply(502, b'{"error":"archive unavailable"}')


class BoundedHTTPServer(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 32

    def __init__(self, *args, **kwargs):
        self.slots = threading.BoundedSemaphore(64)
        super().__init__(*args, **kwargs)

    def process_request(self, request, address):
        # Caddy reuses upstream connections; a 5s idle timeout closed them under
        # Caddy's feet and showed up as occasional 502s.
        request.settimeout(30)
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, address)
        except BaseException:
            self.slots.release()
            raise

    def process_request_thread(self, request, address):
        try:
            super().process_request_thread(request, address)
        finally:
            self.slots.release()


if __name__ == '__main__':
    CACHE.mkdir(parents=True, exist_ok=True)
    INDEX.warm(CACHE)  # one startup scan; every later update is incremental
    # Keep the windows people are actually watching fresh in the background, so
    # the phone's next request is a cache hit instead of an exchange round trip.
    MARKET.start_warming()
    BoundedHTTPServer(('127.0.0.1', int(os.environ.get('PORT', '8792'))), Handler).serve_forever()
