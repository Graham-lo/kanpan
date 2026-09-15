"""Public historical OI cache. WS is streamed by Caddy; REST stays on the client."""
import csv
import datetime as dt
import io
import json
import math
import os
from pathlib import Path
import re
import tempfile
import threading
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.request import urlopen
from urllib.parse import urlsplit, parse_qs
import zipfile
import ipaddress
from resource_limits import HTTPGuard
from market_rest import MARKET, Unavailable

CACHE = Path(os.environ.get('KANPAN_OI_CACHE', '/var/cache/kanpan-gateway'))
LIMIT = 200 * 1024 * 1024
POOL = ThreadPoolExecutor(max_workers=8)
LOCK = threading.Lock()
PENDING = {}
PATTERN = re.compile(r'^/oi/v1/metrics/([A-Z0-9_]{1,30})/(\d{4}-\d{2}-\d{2})\.json$')
RANGE_PATTERN = re.compile(r'^/oi/v1/metrics/([A-Z0-9_]{1,30})/range$')
RANGE_SLOTS = threading.BoundedSemaphore(4)
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
    with ThreadPoolExecutor(max_workers=2) as readers:
        for base in range(first, last + 1, 2):
            for points in readers.map(read, range(base, min(base + 2, last + 1))):
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


def fetch_day(symbol, day):
    path = CACHE / f'{symbol}-{day}.json'
    try:
        data = path.read_bytes()
        os.utime(path, None)
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
        with LOCK:
            files = sorted(CACHE.glob('*.json'), key=lambda p: p.stat().st_mtime)
            size = sum(p.stat().st_size for p in files)
            for old in files:
                if size <= LIMIT:
                    break
                size -= old.stat().st_size
                old.unlink(missing_ok=True)
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

    def reply(self, status, payload, cache='no-store', hit=None):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.send_header('Cache-Control', cache)
        if status in (429, 503):
            self.send_header('Retry-After', '2')
        if hit:
            self.send_header('X-OI-Cache', hit)
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        key = self.client_address[0]
        try:
            if ipaddress.ip_address(key).is_loopback:
                key = str(ipaddress.ip_address(self.headers.get('X-Kanpan-Client-IP', key)))
        except ValueError:
            pass
        if not HTTP_GUARD.enter(key):
            return self.reply(429, b'{"error":"busy"}')
        try:
            self.get_market_data()
        finally:
            HTTP_GUARD.leave(key)

    def get_market_data(self):
        if self.path == '/chart-gateway/health':
            return self.reply(200, b'{"status":"ok","service":"kanpan-gateway"}')
        parts = urlsplit(self.path)
        if parts.path in ('/market/v1/klines', '/market/v1/ticker', '/market/v1/instruments'):
            if not RANGE_SLOTS.acquire(blocking=False):
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
                    value = MARKET.klines(source, q['symbol'], q['interval'], int(q.get('limit', '300')),
                                          int(q['startTime']) if 'startTime' in q else None,
                                          int(q['endTime']) if 'endTime' in q else None)
                elif parts.path.endswith('/ticker'):
                    if set(q) != {'symbol'} or not re.fullmatch(r'[A-Z0-9_]{1,30}', q['symbol']):
                        raise ValueError('invalid symbol')
                    value = {'source': source, 'ticker': MARKET.ticker(source, q['symbol'])}
                else:
                    if q:
                        raise ValueError('invalid query')
                    value = {'source': source, 'instruments': MARKET.exchange_info(source)}
                return self.reply(200, json.dumps(value, separators=(',', ':')).encode(), 'no-store')
            except (KeyError, ValueError, TypeError):
                return self.reply(400, b'{"error":"invalid market request"}')
            except (Unavailable, HTTPError, OSError, TimeoutError, RuntimeError):
                return self.reply(503, b'{"error":"market unavailable"}')
            finally:
                RANGE_SLOTS.release()
        range_match = RANGE_PATTERN.fullmatch(parts.path)
        if range_match:
            if not RANGE_SLOTS.acquire(blocking=False):
                return self.reply(503, b'{"error":"busy"}')
            try:
                query = parse_qs(parts.query, strict_parsing=True)
                if set(query) != {'interval', 'from', 'to'} or any(len(v) != 1 for v in query.values()):
                    raise ValueError('invalid query')
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
        self.slots = threading.BoundedSemaphore(16)
        super().__init__(*args, **kwargs)

    def process_request(self, request, address):
        request.settimeout(5)
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
    BoundedHTTPServer(('127.0.0.1', int(os.environ.get('PORT', '8792'))), Handler).serve_forever()
