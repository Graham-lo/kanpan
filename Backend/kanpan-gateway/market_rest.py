"""Bounded public market data. Each response belongs to exactly one exchange."""
from collections import deque, OrderedDict
from concurrent.futures import ThreadPoolExecutor
import datetime as dt
import http.client
import json
import math
import re
import threading
import time
from urllib.parse import urlencode

HOSTS = {'binance': 'fapi.binance.com', 'okx': 'www.okx.com'}
# Per source, not shared: an OKX backfill must not delay a Binance ticker.
# OKX documents 20 requests/2s for history-candles, so stay under that.
INTERVALS = {'binance': .1, 'okx': .12}
SYMBOL = re.compile(r'[A-Z0-9_]{1,30}')
OKX_SYMBOL = re.compile(r'[A-Z0-9]{1,25}USDT')
DAY = 86_400_000
STEPS = {'1m': 60_000, '3m': 180_000, '5m': 300_000, '15m': 900_000,
         '30m': 1_800_000, '1h': 3_600_000, '2h': 7_200_000, '4h': 14_400_000,
         '6h': 21_600_000, '8h': 28_800_000, '12h': 43_200_000,
         '1d': DAY, '3d': 3 * DAY, '1w': 7 * DAY, '1M': 30 * DAY}
OKX_BARS = {'1m': '1m', '3m': '3m', '5m': '5m', '15m': '15m', '30m': '30m',
            '1h': '1H', '2h': '2H', '4h': '4H', '6h': '6Hutc', '8h': '4H',
            '12h': '12Hutc', '1d': '1Dutc', '3d': '1Dutc', '1w': '1Wutc', '1M': '1Mutc'}


class Unavailable(Exception):
    pass


class Blocked(Unavailable):
    """The exchange refused this node's region (HTTP 451), not a transient fault.

    The phone must be able to tell this apart from an overloaded upstream so it
    switches source instead of retrying, so it travels as its own type all the
    way out to the HTTP reply.
    """
    def __init__(self, source):
        super().__init__(source + ' blocked')
        self.source = source


class RateGate:
    """Per-source pacing on a condition variable.

    The old gate was one global lock plus time.sleep(): a worker thread sat
    parked for the whole spacing interval, and a Binance request waited behind
    an OKX one for no reason. Waiters here release the lock, wake exactly when
    the slot opens, and give up rather than queueing without bound.
    """
    def __init__(self, interval):
        self.interval = interval
        self.condition = threading.Condition()
        self.next_at = 0.0

    def reserve(self, patience=8.0):
        deadline = time.monotonic() + patience
        with self.condition:
            while True:
                now = time.monotonic()
                if now >= self.next_at:
                    self.next_at = now + self.interval
                    self.condition.notify_all()
                    return
                if now >= deadline:
                    raise Unavailable('upstream pacing exceeded')
                self.condition.wait(min(self.next_at, deadline) - now)


class Upstream:
    """Resident keep-alive connections per exchange host.

    Every request used to pay a fresh TCP handshake plus a TLS handshake; on the
    VPS that is most of the latency of a cached-miss kline page.
    """
    def __init__(self, host, size=8):
        self.host, self.size = host, size
        self.idle = deque()
        self.lock = threading.Lock()

    def _take(self):
        with self.lock:
            return self.idle.popleft() if self.idle else None

    def _keep(self, connection):
        with self.lock:
            if len(self.idle) >= self.size:
                connection.close()
                return
            self.idle.append(connection)

    def fetch(self, path, headers, timeout, limit):
        """Return (status, body). Only a reused connection is retried."""
        failure = None
        for _ in range(2):
            connection = self._take()
            reused = connection is not None
            if not reused:
                connection = http.client.HTTPSConnection(self.host, timeout=timeout)
            else:
                connection.timeout = timeout
                if connection.sock is not None:
                    connection.sock.settimeout(timeout)
            try:
                connection.request('GET', path, headers=headers)
                response = connection.getresponse()
                body = response.read(limit + 1)
                overflow = len(body) > limit
                # Only a fully drained, keep-alive response leaves the socket reusable.
                if overflow or response.will_close or not response.isclosed():
                    connection.close()
                else:
                    self._keep(connection)
                if overflow:
                    raise Unavailable('response too large')
                return response.status, body
            except Unavailable:
                raise
            except (OSError, http.client.HTTPException) as error:
                connection.close()
                failure = error
                if not reused:
                    break  # a fresh connection failing is a real upstream fault
        raise Unavailable('upstream unreachable') from failure


def bucket(at, interval):
    if interval == '1M':
        date = dt.datetime.fromtimestamp(at / 1000, dt.timezone.utc)
        return int(date.replace(day=1, hour=0, minute=0, second=0, microsecond=0).timestamp() * 1000)
    offset = 3 * DAY if interval == '1w' else 0
    if interval == '3d':
        offset = (2 if at >= 1_692_144_000_000 else 1) * DAY
    return (at + offset) // STEPS[interval] * STEPS[interval] - offset


def close_time(at, interval):
    if interval == '1M':
        date = dt.datetime.fromtimestamp(at / 1000, dt.timezone.utc)
        date = date.replace(year=date.year + (date.month == 12), month=date.month % 12 + 1)
        return int(date.timestamp() * 1000)
    if interval == '3d' and at < 1_692_144_000_000 < at + 3 * DAY:
        return 1_692_144_000_000
    return at + STEPS[interval]


def step_back(at, interval, count):
    """Move `count` whole bars earlier from a bar boundary.

    Parallel paging needs to know where page N starts without waiting for page
    N-1 to come back, and every OKX source bar is a fixed span except the
    calendar month.
    """
    if interval != '1M':
        return at - count * STEPS[interval]
    date = dt.datetime.fromtimestamp(at / 1000, dt.timezone.utc)
    months = date.year * 12 + date.month - 1 - count
    return int(date.replace(year=months // 12, month=months % 12 + 1).timestamp() * 1000)


def valid_row(row, interval):
    if not isinstance(row, list) or len(row) < 7:
        raise Unavailable('invalid candles')
    at = int(row[0]); values = [float(row[i]) for i in range(1, 6)]
    o, h, l, c, v = values
    if at < 0 or bucket(at, interval) != at or not all(math.isfinite(x) for x in values):
        raise Unavailable('invalid candle values')
    if min(o, h, l, c) <= 0 or v < 0 or not l <= min(o, c) <= max(o, c) <= h:
        raise Unavailable('invalid candle prices')


def normalize_okx(rows, interval):
    source = '4h' if interval == '8h' else '1d' if interval == '3d' else interval
    ordered = {}
    for r in rows:
        if len(r) != 9 or r[8] not in ('0', '1'):
            raise Unavailable('invalid OKX candle')
        at = int(r[0])
        # vol is contracts. volCcy is base currency for USDT swaps, matching the chart's volume unit.
        row = [at, r[1], r[2], r[3], r[4], r[6], close_time(at, source) - 1,
               r[7], 0, '0', '0', '0']
        valid_row(row, source)
        if at in ordered and ordered[at] != row:
            raise Unavailable('contradictory candles')
        ordered[at] = row
    ordered = [ordered[k] for k in sorted(ordered)]
    if source == interval:
        return ordered
    groups = {}
    for r in ordered:
        groups.setdefault(bucket(r[0], interval), []).append(r)
    out = []
    for at, parts in sorted(groups.items()):
        end = close_time(at, interval)
        # A missing first component is a truncated page, never a valid aggregated open.
        if parts[0][0] != at:
            continue
        if any(close_time(a[0], source) != b[0] for a, b in zip(parts, parts[1:])):
            raise Unavailable('candle gap')
        if end <= int(time.time() * 1000) and close_time(parts[-1][0], source) != end:
            continue
        out.append([at, parts[0][1], str(max(float(r[2]) for r in parts)),
                    str(min(float(r[3]) for r in parts)), parts[-1][4],
                    str(sum(float(r[5]) for r in parts)), end - 1,
                    str(sum(float(r[7]) for r in parts)), 0, '0', '0', '0'])
    return out


class PublicMarket:
    def __init__(self):
        self.lock = threading.Lock()
        self.cache = OrderedDict()
        self.bytes = 0
        self.pending = {}
        self.pool = ThreadPoolExecutor(max_workers=16, thread_name_prefix='market')
        # Paging runs on its own pool so a parallel backfill can never occupy
        # every download worker it is itself waiting on.
        self.pages = ThreadPoolExecutor(max_workers=12, thread_name_prefix='market-page')
        self.gates = {source: RateGate(interval) for source, interval in INTERVALS.items()}
        self.connections = {source: Upstream(host) for source, host in HOSTS.items()}
        self.cooldown = {}
        self.responses = OrderedDict()
        self.response_bytes = 0

    def get(self, source, path, query, ttl=1):
        key = (source, path, urlencode(sorted(query.items())))
        with self.lock:
            for finished in [k for k, task in self.pending.items() if task.done()]:
                del self.pending[finished]
            cached = self.cache.get(key)
            if cached and cached[0] > time.monotonic():
                self.cache.move_to_end(key)
                return json.loads(cached[1])
            self.check_cooldown(source)
            future = self.pending.get(key)
            if future is None:
                if len(self.pending) >= 64:
                    raise Unavailable('busy')
                future = self.pool.submit(self.download, key, ttl)
                self.pending[key] = future
        try:
            return future.result(timeout=25)
        finally:
            with self.lock:
                if future.done() and self.pending.get(key) is future:
                    del self.pending[key]

    def check_cooldown(self, source):
        """Caller already holds self.lock, or does not need to."""
        until, blocked = self.cooldown.get(source, (0, False))
        if until > time.monotonic():
            raise Blocked(source) if blocked else Unavailable('upstream cooling down')

    def download(self, key, ttl):
        source, path, query = key
        self.gates[source].reserve()
        status, data = self.connections[source].fetch(
            path + ('?' + query if query else ''),
            {'User-Agent': 'Kanpan-Market-Probe/1.0', 'Accept': 'application/json',
             'Host': HOSTS[source], 'Connection': 'keep-alive'},
            10, 2 * 1024 * 1024)
        if status != 200:
            if status in (403, 418, 429, 451):
                with self.lock:
                    self.cooldown[source] = (time.monotonic() + (60 if status in (403, 451) else 10), status == 451)
            if status == 451:
                raise Blocked(source)
            raise Unavailable('upstream unavailable')
        value = json.loads(data)
        if source == 'okx':
            if value.get('code') != '0':
                raise Unavailable('instrument unavailable')
            value = value['data']; data = json.dumps(value, separators=(',', ':')).encode()
        with self.lock:
            old = self.cache.pop(key, None)
            if old:
                self.bytes -= len(old[1])
            self.cache[key] = (time.monotonic() + ttl, data); self.bytes += len(data)
            while self.bytes > 32 * 1024 * 1024 or len(self.cache) > 512:
                _, old = self.cache.popitem(last=False); self.bytes -= len(old[1])
        return value

    def instrument(self, symbol):
        if not OKX_SYMBOL.fullmatch(symbol):
            raise ValueError('invalid symbol')
        # Exact USDT perpetuals only. Never silently substitute a spot market or multiplier token.
        inst = symbol[:-4] + '-USDT-SWAP'
        rows = self.get('okx', '/api/v5/public/instruments', {'instType': 'SWAP'}, ttl=300)
        item = next((r for r in rows if r.get('instId') == inst and r.get('settleCcy') == 'USDT'
                     and r.get('ctType') == 'linear' and r.get('state') == 'live'), None)
        if item is None:
            raise Unavailable('instrument unavailable')
        return item

    def page_ttl(self, unit, end, now):
        """How long one upstream history page stays good.

        A page whose newest bar already closed can never change again, so the
        old blanket 1s (outside the two-day rule) threw away perfectly final
        data on every scroll. Anything older than two days is kept for six
        hours; anything merely closed for an hour.
        """
        if end < now - 2 * DAY:
            return 6 * 3600
        return 3600 if end < bucket(now, unit) else 1

    def klines_ttl(self, interval, start, end, now):
        """Same rule at response granularity; a live window still gets 1s."""
        if end is None:
            return 1
        unit = '4h' if interval == '8h' else '1d' if interval == '3d' else interval
        return self.page_ttl(unit, min(end, now), now)

    def cached_response(self, key, ttl, build):
        """Cache finished response bytes, not values that must be re-encoded.

        A hit used to cost json.loads of the upstream payload plus the whole
        normalisation plus json.dumps again -- for a 1500-bar page that is the
        dominant server cost of a cached request.
        """
        with self.lock:
            hit = self.responses.get(key)
            if hit and hit[0] > time.monotonic():
                self.responses.move_to_end(key)
                return hit[1]
        payload = build()
        with self.lock:
            old = self.responses.pop(key, None)
            if old:
                self.response_bytes -= len(old[1])
            self.responses[key] = (time.monotonic() + ttl, payload)
            self.response_bytes += len(payload)
            while self.response_bytes > 32 * 1024 * 1024 or len(self.responses) > 512:
                _, dropped = self.responses.popitem(last=False)
                self.response_bytes -= len(dropped[1])
        return payload

    def klines_response(self, source, symbol, interval, limit, start=None, end=None):
        """The exact bytes the phone receives.

        serverTime is the one field that must never be stale, so what is cached
        is the response minus that field and its closing brace; the current
        timestamp is appended on every hit.
        """
        now = self.validate_klines(source, symbol, interval, limit, start, end)

        def build():
            value = self.klines(source, symbol, interval, limit, start, end)
            value.pop('serverTime', None)
            return json.dumps(value, separators=(',', ':'))[:-1].encode()

        prefix = self.cached_response(('klines', source, symbol, interval, limit, start, end),
                                      self.klines_ttl(interval, start, end, now), build)
        return prefix + b',"serverTime":' + str(now).encode() + b'}'

    def ticker_response(self, source, symbol):
        if source not in ('binance', 'okx') or not SYMBOL.fullmatch(symbol):
            raise ValueError('invalid request')
        return self.cached_response(('ticker', source, symbol), 1, lambda: json.dumps(
            {'source': source, 'ticker': self.ticker(source, symbol)}, separators=(',', ':')).encode())

    def instruments_response(self, source):
        if source not in ('binance', 'okx'):
            raise ValueError('invalid request')
        return self.cached_response(('instruments', source), 300, lambda: json.dumps(
            {'source': source, 'instruments': self.exchange_info(source)}, separators=(',', ':')).encode())

    def validate_klines(self, source, symbol, interval, limit, start=None, end=None):
        """Cheap argument check, so a request can be rejected (or a hung-up
        client abandoned) before any upstream work starts."""
        now = int(time.time() * 1000)
        if source not in ('binance', 'okx') or interval not in STEPS or not 1 <= limit <= 1500:
            raise ValueError('invalid request')
        if start is not None and start < 0 or end is not None and end < 0:
            raise ValueError('invalid time')
        if start is not None and start > min(end if end is not None else now, now):
            raise ValueError('invalid range')
        if not SYMBOL.fullmatch(symbol):
            raise ValueError('invalid symbol')
        return now

    def klines(self, source, symbol, interval, limit, start=None, end=None):
        now = self.validate_klines(source, symbol, interval, limit, start, end)
        latest_window = start is None and end is None
        end = min(end if end is not None else now, now)
        if source == 'binance':
            query = {'symbol': symbol, 'interval': interval, 'limit': limit, 'endTime': end}
            if start is not None:
                query['startTime'] = start
            rows = self.get(source, '/fapi/v1/klines', query)
            for row in rows:
                valid_row(row, interval)
        else:
            item = self.instrument(symbol)
            ratio = 2 if interval == '8h' else 3 if interval == '3d' else 1
            if latest_window and limit <= 300:
                # OKX's current-candles endpoint returns up to 300 rows in one
                # request. The old history-candles path fetched the same first
                # screen in four serial 100-row pages, adding roughly 1.2s on
                # the VPS before the phone could draw anything. Historical and
                # start/end-based requests intentionally keep the paged path.
                query = {'instId': item['instId'], 'bar': OKX_BARS[interval], 'limit': limit}
                raw = self.get(source, '/api/v5/market/candles', query, ttl=1)
                rows = normalize_okx(raw, interval)
            else:
                # Start-based consumers need the earliest page after start, not the latest page before now.
                if start is not None:
                    boundary = bucket(start, interval)
                    for _ in range(limit):
                        boundary = close_time(boundary, interval)
                    end = min(end, boundary - 1)
                wanted = min(4503, limit * ratio + ratio)
                unit = '4h' if interval == '8h' else '1d' if interval == '3d' else interval
                raw = []; cursor = close_time(bucket(end, unit), unit)
                # OKX caps history-candles at 100 rows, so a two-year 5m backfill
                # used to be dozens of strictly serial round trips. Page starts
                # are predictable (100 source bars apart), so three are in
                # flight at a time; the per-source gate still paces them.
                ttl = self.page_ttl(unit, end, now)
                remaining = (wanted + 99) // 100 + 1
                while remaining > 0 and len(raw) < wanted:
                    width = min(3, remaining)
                    cursors = [step_back(cursor, unit, 100 * k) for k in range(width)]
                    tasks = [self.pages.submit(
                        self.get, source, '/api/v5/market/history-candles',
                        {'instId': item['instId'], 'bar': OKX_BARS[interval], 'limit': 100, 'after': c}, ttl)
                        for c in cursors]
                    done = False
                    for at, task in zip(cursors, tasks):
                        page = task.result()
                        if done:
                            continue  # already past the end; drain, do not use
                        if not page:
                            done = True; continue
                        times = [int(r[0]) for r in page]
                        # A page must lie strictly before its own cursor. Pages may
                        # overlap when the symbol has holes -- normalize_okx keys by
                        # timestamp, so overlap is free and coverage stays contiguous.
                        if any(t >= at for t in times) or len(set(times)) != len(times):
                            raise Unavailable('invalid history cursor')
                        raw.extend(page); cursor = min(cursor, min(times))
                        if len(page) < 100 or (start is not None and cursor <= bucket(start, interval)):
                            done = True
                    if done:
                        break
                    remaining -= width
                rows = normalize_okx(raw, interval)
        rows = [r for r in rows if (start is None or int(r[0]) >= start) and int(r[0]) <= end]
        rows = rows[:limit] if start is not None else rows[-limit:]
        if any(close_time(int(a[0]), interval) != int(b[0]) for a, b in zip(rows, rows[1:])):
            raise Unavailable('history has gaps')
        return {'source': source, 'symbol': symbol, 'interval': interval, 'bars': rows, 'serverTime': now}

    def ticker(self, source, symbol):
        if source == 'binance':
            return self.get(source, '/fapi/v1/ticker/24hr', {'symbol': symbol})
        item = self.instrument(symbol)
        rows = self.get('okx', '/api/v5/market/ticker', {'instId': item['instId']})
        if len(rows) != 1 or rows[0].get('instId') != item['instId']:
            raise Unavailable('invalid ticker')
        r = rows[0]; last = float(r['last']); opened = float(r['open24h'])
        return {'symbol': symbol, 'lastPrice': r['last'], 'openPrice': r['open24h'],
                'highPrice': r['high24h'], 'lowPrice': r['low24h'], 'volume': r['volCcy24h'],
                'quoteVolume': '', 'priceChange': str(last - opened),
                'priceChangePercent': str((last / opened - 1) * 100 if opened else 0),
                'closeTime': int(r['ts'])}

    def exchange_info(self, source):
        if source == 'binance':
            return self.get(source, '/fapi/v1/exchangeInfo', {}, ttl=300)
        rows = self.get('okx', '/api/v5/public/instruments', {'instType': 'SWAP'}, ttl=300)
        symbols = []
        for r in rows:
            if r.get('settleCcy') != 'USDT' or r.get('ctType') != 'linear' or r.get('state') != 'live':
                continue
            parts = r['instId'].split('-')
            if len(parts) != 3 or parts[1:] != ['USDT', 'SWAP']:
                continue
            precision = len(r['tickSz'].rstrip('0').split('.')[-1]) if '.' in r['tickSz'] else 0
            symbols.append({'symbol': parts[0] + 'USDT', 'baseAsset': parts[0], 'quoteAsset': 'USDT',
                            'status': 'TRADING', 'contractType': 'PERPETUAL', 'pricePrecision': precision,
                            'quantityPrecision': 8, 'filters': [{'filterType': 'PRICE_FILTER', 'tickSize': r['tickSz']}]})
        return {'symbols': symbols}


MARKET = PublicMarket()
