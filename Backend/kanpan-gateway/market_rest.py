"""Bounded public market data. Each response belongs to exactly one exchange."""
from collections import OrderedDict
from concurrent.futures import ThreadPoolExecutor
import datetime as dt
import json
import math
import threading
import time
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from urllib.error import HTTPError

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
        self.pool = ThreadPoolExecutor(max_workers=4)
        self.rate = threading.Lock()
        self.next_request = 0.0
        self.cooldown = {}

    def get(self, source, path, query, ttl=1):
        key = (source, path, urlencode(sorted(query.items())))
        with self.lock:
            for finished in [k for k, task in self.pending.items() if task.done()]:
                del self.pending[finished]
            cached = self.cache.get(key)
            if cached and cached[0] > time.monotonic():
                self.cache.move_to_end(key)
                return json.loads(cached[1])
            if self.cooldown.get(source, 0) > time.monotonic():
                raise Unavailable('upstream cooling down')
            future = self.pending.get(key)
            if future is None:
                if len(self.pending) >= 32:
                    raise Unavailable('busy')
                future = self.pool.submit(self.download, key, ttl)
                self.pending[key] = future
        try:
            return future.result(timeout=15)
        finally:
            with self.lock:
                if future.done() and self.pending.get(key) is future:
                    del self.pending[key]

    def download(self, key, ttl):
        source, path, query = key
        # Shared across clients and endpoints: at most five public requests per second per node.
        with self.rate:
            now = time.monotonic(); delay = max(0, self.next_request - now)
            self.next_request = max(now, self.next_request) + .2
        if delay:
            time.sleep(delay)
        host = 'https://fapi.binance.com' if source == 'binance' else 'https://www.okx.com'
        request = Request(host + path + ('?' + query if query else ''),
                          headers={'User-Agent': 'Kanpan-Market-Probe/1.0', 'Accept': 'application/json'})
        try:
            with urlopen(request, timeout=10) as response:
                data = response.read(2 * 1024 * 1024 + 1)
        except HTTPError as error:
            if error.code in (403, 418, 429, 451):
                with self.lock:
                    self.cooldown[source] = time.monotonic() + (60 if error.code in (403, 451) else 10)
            raise Unavailable('upstream unavailable') from None
        if len(data) > 2 * 1024 * 1024:
            raise Unavailable('response too large')
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
        import re
        if not re.fullmatch(r'[A-Z0-9]{1,25}USDT', symbol):
            raise ValueError('invalid symbol')
        # Exact USDT perpetuals only. Never silently substitute a spot market or multiplier token.
        inst = symbol[:-4] + '-USDT-SWAP'
        rows = self.get('okx', '/api/v5/public/instruments', {'instType': 'SWAP'}, ttl=300)
        item = next((r for r in rows if r.get('instId') == inst and r.get('settleCcy') == 'USDT'
                     and r.get('ctType') == 'linear' and r.get('state') == 'live'), None)
        if item is None:
            raise Unavailable('instrument unavailable')
        return item

    def klines(self, source, symbol, interval, limit, start=None, end=None):
        now = int(time.time() * 1000)
        if source not in ('binance', 'okx') or interval not in STEPS or not 1 <= limit <= 1500:
            raise ValueError('invalid request')
        if start is not None and start < 0 or end is not None and end < 0:
            raise ValueError('invalid time')
        end = min(end if end is not None else now, now)
        if start is not None and start > end:
            raise ValueError('invalid range')
        import re
        if not re.fullmatch(r'[A-Z0-9_]{1,30}', symbol):
            raise ValueError('invalid symbol')
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
            # Start-based consumers need the earliest page after start, not the latest page before now.
            if start is not None:
                boundary = bucket(start, interval)
                for _ in range(limit):
                    boundary = close_time(boundary, interval)
                end = min(end, boundary - 1)
            wanted = min(4503, limit * ratio + ratio)
            raw = []; cursor = close_time(bucket(end, '4h' if interval == '8h' else '1d' if interval == '3d' else interval),
                                          '4h' if interval == '8h' else '1d' if interval == '3d' else interval)
            for _ in range((wanted + 99) // 100 + 1):
                query = {'instId': item['instId'], 'bar': OKX_BARS[interval], 'limit': min(100, wanted - len(raw)), 'after': cursor}
                if query['limit'] <= 0:
                    break
                page = self.get(source, '/api/v5/market/history-candles', query,
                                ttl=3600 if end < now - 2 * DAY else 1)
                if not page:
                    break
                times = [int(r[0]) for r in page]
                if any(t >= cursor for t in times) or len(set(times)) != len(times):
                    raise Unavailable('invalid history cursor')
                raw.extend(page); cursor = min(times)
                if start is not None and cursor <= bucket(start, interval):
                    break
                if len(page) < query['limit']:
                    break
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
