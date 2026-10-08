"""Bounded public Binance USDT-M market data.

Binance only since 2026-10-08: OKX (and every other venue) is served by
kanpan-api, never by this gateway, so nothing here substitutes one exchange for
another. `source=binance` is still required on every request so the contract
keeps saying whose data it is.
"""
import bisect
from collections import deque, namedtuple, OrderedDict
from concurrent.futures import ThreadPoolExecutor
import datetime as dt
import email.utils
import http.client
import json
import math
import os
from pathlib import Path
import re
import tempfile
import threading
import time
from urllib.parse import urlencode

HOSTS = {'binance': 'fapi.binance.com'}
# Minimum spacing between two requests to one host.
INTERVALS = {'binance': .1}
SYMBOL = re.compile(r'[A-Z0-9_]{1,30}')
DAY = 86_400_000
STEPS = {'1m': 60_000, '3m': 180_000, '5m': 300_000, '15m': 900_000,
         '30m': 1_800_000, '1h': 3_600_000, '2h': 7_200_000, '4h': 14_400_000,
         '6h': 21_600_000, '8h': 28_800_000, '12h': 43_200_000,
         '1d': DAY, '3d': 3 * DAY, '1w': 7 * DAY, '1M': 30 * DAY}
# Background refresh. Only a response that expires within seconds is worth
# fetching ahead of demand, and only while someone is still asking for it.
WARM_TTL_MAX = 5
WARM_IDLE_SECONDS = 60
WARM_KEYS = 64
WARM_LEAD = .35
BARS_ROOT = Path(os.environ.get('KANPAN_BAR_CACHE',
                                os.environ.get('KANPAN_OI_CACHE', '/var/cache/kanpan-gateway') + '/bars'))
BARS_IN_MEMORY = 64_000
BARS_SERIES = 32
BARS_ON_DISK = 256 * 1024 * 1024
BARS_WRITE_INTERVAL = 30
# Binance publishes no per-step table for 418: the documented range is "2 minutes
# to 3 days", so an unheaded ban is worth the documented minimum, not seconds.
# 403 is the WAF refusing this node, which is a ban too -- not the geographic 451,
# and not a request that can be fixed by asking again in two seconds.
RATE_LIMIT_DEFAULTS = {429: 10, 418: 120, 403: 60}
# What a source-level cooldown is: when it lifts, why it exists, and what the
# phone must be told. `kind` is one of blocked / rate_limited / unavailable --
# a single bool could not tell "the exchange told us to wait 120 s" apart from
# "one request failed", and the phone needs that difference to stop retrying.
Cooldown = namedtuple('Cooldown', ('until', 'kind', 'retry_after', 'upstream_status'),
                      defaults=(0, ''))
COOLDOWN_RANK = {'unavailable': 0, 'rate_limited': 1, 'blocked': 2}


class Unavailable(Exception):
    pass


class RateLimited(Unavailable):
    """The exchange told this node to stop for a while, with a deadline.

    HTTP 429/418, or the WAF's 403. This is not a transient fault: retrying before `retry_after` only digs
    the ban deeper, so the category and the deadline travel as their own type all
    the way out to the HTTP reply instead of being flattened into a 503.
    """
    def __init__(self, source, retry_after, upstream_status):
        super().__init__('%s rate limited' % source)
        self.source = source
        # Whole seconds, and never zero: "wait no time at all" is not a stop
        # condition the phone can act on.
        self.retry_after = max(1, int(math.ceil(retry_after)))
        self.upstream_status = str(upstream_status)


class Blocked(Unavailable):
    """The exchange refused this node's region (HTTP 451), not a transient fault.

    The phone must be able to tell this apart from an overloaded upstream so it
    switches source instead of retrying, so it travels as its own type all the
    way out to the HTTP reply.
    """
    def __init__(self, source):
        super().__init__(source + ' blocked')
        self.source = source


def retry_after_seconds(headers):
    """Read Retry-After (RFC 9110): delta-seconds or an HTTP-date, else None.

    A `0` or an already-past date is treated as absent: an exchange that just
    refused us is not credibly inviting an immediate retry, so the caller's
    documented default is the safer number.
    """
    value = headers.get('Retry-After') if hasattr(headers, 'get') else None
    if not value:
        return None
    text = str(value).strip()
    if text.isdigit():
        return int(text) or None
    try:
        when = email.utils.parsedate_to_datetime(text)
    except (TypeError, ValueError):
        return None
    if when is None:
        return None
    if when.tzinfo is None:
        when = when.replace(tzinfo=dt.timezone.utc)  # HTTP-dates are GMT
    return max(0, int(math.ceil(when.timestamp() - time.time()))) or None


class RateGate:
    """Per-source pacing on a condition variable.

    The old gate was one global lock plus time.sleep(): a worker thread sat
    parked for the whole spacing interval. Waiters here release the lock, wake exactly when
    the slot opens, and give up rather than queueing without bound.
    """
    def __init__(self, interval):
        self.interval = interval
        self.condition = threading.Condition()
        self.next_at = 0.0
        self.waiting = 0

    def reserve(self, patience=8.0, background=False):
        """Take one pacing slot. Background callers take only unwanted ones.

        The refresher exists to save the phone a wait, so it must never cause
        one: while any request thread is queued here, background work stands
        aside instead of spending the slot the phone is about to need.
        """
        deadline = time.monotonic() + patience
        with self.condition:
            if not background:
                self.waiting += 1
            try:
                while True:
                    now = time.monotonic()
                    # Background work needs idle headroom, not just an open slot:
                    # a backfill holds the gate continuously, and taking the slot
                    # just before it asks again would lengthen every one of its pages.
                    free = self.next_at + (self.interval if background else 0)
                    if now >= free and not (background and self.waiting):
                        self.next_at = now + self.interval
                        self.condition.notify_all()
                        return
                    if now >= deadline:
                        raise Unavailable('upstream pacing exceeded')
                    self.condition.wait(min(max(free, now + .01), deadline) - now)
            finally:
                if not background:
                    self.waiting -= 1
                    self.condition.notify_all()  # a yielding background caller may go now


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
        """Return (status, body, response headers). Only a reused connection is retried.

        The headers come back because a 429/418 without its Retry-After is just a
        guess: the deadline the exchange published is the only accurate one.
        """
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
                reply_headers = response.headers
                overflow = len(body) > limit
                # Only a fully drained, keep-alive response leaves the socket reusable.
                if overflow or response.will_close or not response.isclosed():
                    connection.close()
                else:
                    self._keep(connection)
                if overflow:
                    raise Unavailable('response too large')
                return response.status, body, reply_headers
            except Unavailable:
                raise
            except (OSError, http.client.HTTPException) as error:
                connection.close()
                failure = error
                if not reused:
                    break  # a fresh connection failing is a real upstream fault
                # The exchange closes idle keep-alive sockets on its own clock, so a
                # quiet spell leaves every pooled connection dead at once. Retrying
                # with the next pooled one just meets the next corpse: with two or
                # more in the pool the phone got a 503 while the exchange was fine
                # (D.7, 2026-09-23: first request after idle, both sources at once).
                # One reused failure condemns the whole pool; the retry is fresh.
                self._drain()
        raise Unavailable('upstream unreachable') from failure

    def _drain(self):
        with self.lock:
            stale, self.idle = self.idle, deque()
        for connection in stale:
            connection.close()


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


class BarCache:
    """Closed bars per (source, symbol, interval), so a window is a slice.

    Closed bars can never change again, and scrolling a chart asks for windows
    that overlap the previous one almost entirely, so the second window used to
    pay a full upstream round trip (and a slot under the exchange's request
    weight) for rows this node already had. One contiguous run per series answers it locally, and the run
    is mirrored to disk so a restart or a deploy does not start from nothing.

    Only closed bars are ever kept, and a window is only served when the run
    covers it completely; anything else falls through to the network path, which
    stays the single source of truth for the live edge.
    """

    def __init__(self, root=BARS_ROOT, memory=BARS_IN_MEMORY, series=BARS_SERIES,
                 disk=BARS_ON_DISK, interval=BARS_WRITE_INTERVAL):
        self.root, self.memory, self.series_limit = Path(root), memory, series
        self.disk, self.write_interval = disk, interval
        self.lock = threading.Lock()
        self.series = OrderedDict()
        self.written = {}
        self.bars = 0

    @staticmethod
    def contiguous(bars, interval):
        return all(close_time(int(a[0]), interval) == int(b[0]) for a, b in zip(bars, bars[1:]))

    def path(self, key):
        return self.root / ('%s-%s-%s.json' % key)

    def load(self, key, interval):
        """Best effort: a missing, truncated or stale file is simply not a hit."""
        try:
            bars = json.loads(self.path(key).read_bytes())
        except (OSError, ValueError):
            return None
        if not isinstance(bars, list) or not bars or not self.contiguous(bars, interval):
            return None
        return bars

    def store(self, key, bars):
        try:
            self.root.mkdir(parents=True, exist_ok=True)
            payload = json.dumps(bars, separators=(',', ':')).encode()
            with tempfile.NamedTemporaryFile(dir=self.root, delete=False) as out:
                out.write(payload)
                temporary = out.name
            os.replace(temporary, self.path(key))
            self.evict_disk()
        except (OSError, ValueError):
            pass  # the in-memory run still works; disk is only a head start

    def evict_disk(self):
        files = []
        total = 0
        for path in self.root.glob('*.json'):
            try:
                status = path.stat()
            except OSError:
                continue
            files.append((status.st_mtime, status.st_size, path))
            total += status.st_size
        for _, size, path in sorted(files):
            if total <= self.disk:
                break
            path.unlink(missing_ok=True)
            total -= size

    def resident(self, key, interval):
        """Caller holds the lock. Returns the in-memory run, loading it once."""
        run = self.series.get(key)
        if run is None:
            run = self.load(key, interval) or []
            self.series[key] = run
            self.bars += len(run)
            self.trim()
        self.series.move_to_end(key)
        return run

    def trim(self):
        while self.series and (self.bars > self.memory or len(self.series) > self.series_limit):
            key, dropped = self.series.popitem(last=False)
            self.bars -= len(dropped)
            self.written.pop(key, None)  # bounded with the series it belongs to

    def tail(self, key, interval, limit, end, now):
        """The newest part of an end-based window this store already holds.

        Scrolling back asks for a window that overlaps the previous one on its
        newer side, so the part worth fetching is only what lies below the
        overlap. Returning that boundary shrinks the upstream request to the
        missing rows; an empty list means the store knows nothing useful.
        """
        with self.lock:
            run = self.resident(key, interval)
            if not run:
                return []
            at = bucket(end, interval)
            # A window that ends inside the forming bar belongs to the live
            # path, which is the only place that bar exists.
            if close_time(at, interval) > now:
                return []
            times = [int(r[0]) for r in run]
            index = bisect.bisect_left(times, at)
            # The run must reach the very bar the window ends on; anything else
            # would answer a different question than the exchange would.
            if index >= len(times) or times[index] != at:
                return []
            return [list(row) for row in run[max(0, index + 1 - limit):index + 1]]

    def window(self, key, interval, limit, start, end, now):
        """The exact rows `klines` would have fetched, or None to go upstream."""
        if start is None:
            chunk = self.tail(key, interval, limit, end, now)
            return chunk if len(chunk) == limit else None
        with self.lock:
            run = self.resident(key, interval)
            if not run:
                return None
            times = [int(r[0]) for r in run]
            at = bucket(start, interval)
            index = bisect.bisect_left(times, at)
            # The run must hold the very bar the window starts on; a later
            # first bar means the missing part is upstream, not here.
            if index >= len(times) or times[index] != at:
                return None
            chunk = run[index:index + limit]
            # A short answer may be genuine (a young listing) or a hole in this
            # cache; only the upstream can tell them apart, so defer.
            if len(chunk) < limit or int(chunk[-1][0]) > end:
                return None
            if close_time(int(chunk[-1][0]), interval) > now:
                return None
            return [list(row) for row in chunk]

    def merge(self, key, interval, bars):
        """Extend the run with freshly fetched closed bars."""
        if not bars or not self.contiguous(bars, interval):
            return
        with self.lock:
            run = self.resident(key, interval)
            before = len(run)
            if run:
                first, last = int(run[0][0]), int(run[-1][0])
                head, tail = int(bars[0][0]), int(bars[-1][0])
                if head <= close_time(last, interval) and close_time(tail, interval) >= first:
                    index = {int(row[0]): row for row in run}
                    index.update({int(row[0]): row for row in bars})
                    merged = [index[at] for at in sorted(index)]
                    run = merged if self.contiguous(merged, interval) else list(bars)
                else:
                    run = list(bars)  # a jump elsewhere in history: keep the newer run
            else:
                run = list(bars)
            self.series[key] = run
            self.bars += len(run) - before
            self.trim()
            # A key this process has never written is due at once. Reading the
            # absent clock as 0 only looked overdue because `time.monotonic()`
            # counts from boot on Linux; on macOS it counts from process start,
            # so the first run of every series sat unmirrored for 30s -- exactly
            # the window a deploy restart falls into.
            last = self.written.get(key)
            due = last is None or time.monotonic() - last > self.write_interval
            if due and key in self.series:
                self.written[key] = time.monotonic()
                snapshot = run
            else:
                snapshot = None
        if snapshot is not None:
            self.store(key, snapshot)


# Which kind of work the current thread is doing. Set only by the refresher and
# carried onto the paging pool, so pacing can tell demand from anticipation.
DEMAND = threading.local()


def background_now():
    return getattr(DEMAND, 'background', False)


class PublicMarket:
    def __init__(self):
        self.lock = threading.Lock()
        self.cache = OrderedDict()
        self.bytes = 0
        self.pending = {}
        self.pool = ThreadPoolExecutor(max_workers=16, thread_name_prefix='market')
        self.gates = {source: RateGate(interval) for source, interval in INTERVALS.items()}
        self.connections = {source: Upstream(host) for source, host in HOSTS.items()}
        self.cooldown = {}
        self.responses = OrderedDict()
        self.response_bytes = 0
        # Background refresh of the live window, started by the service only.
        self.warm = OrderedDict()
        self.warm_active = set()
        self.warm_pool = ThreadPoolExecutor(max_workers=4, thread_name_prefix='market-warm')
        self.warming = None
        self.bars = BarCache()

    def get(self, source, path, query, ttl=1, retry=True):
        key = (source, path, urlencode(sorted(query.items())))
        cached_bytes = None
        inherited = False
        with self.lock:
            for finished in [k for k, (task, _) in self.pending.items() if task.done()]:
                del self.pending[finished]
            cached = self.cache.get(key)
            if cached and cached[0] > time.monotonic():
                self.cache.move_to_end(key)
                cached_bytes = cached[1]
            else:
                self.check_cooldown(source)
                entry = self.pending.get(key)
                if entry is None:
                    if len(self.pending) >= 64:
                        raise Unavailable('busy')
                    background = background_now()
                    self.pending[key] = (self.pool.submit(self.download, key, ttl, background),
                                         background)
                    entry = self.pending[key]
                future, background = entry
                # The refresher stands aside at the pacing gate and may give up
                # for reasons that have nothing to do with this request. A phone
                # that joined its work must not inherit that answer.
                inherited = background and not background_now()
        if cached_bytes is not None:
            # Decoding is the expensive half of a hit. Doing it under the lock
            # made every other market request queue behind it.
            return json.loads(cached_bytes)
        try:
            return future.result(timeout=25)
        except Unavailable:
            if not (inherited and retry):
                raise
        finally:
            with self.lock:
                if future.done() and self.pending.get(key, (None, None))[0] is future:
                    del self.pending[key]
        return self.get(source, path, query, ttl, retry=False)  # this time on our own

    def check_cooldown(self, source):
        """Caller already holds self.lock, or does not need to.

        The remaining wait is recomputed from the deadline, so a request that sat
        in the pacing queue is told how long is actually left, not how long the
        exchange said when the first request was refused.
        """
        entry = self.cooldown.get(source)
        if entry is None:
            return
        remaining = entry.until - time.monotonic()
        if remaining <= 0:
            return
        if entry.kind == 'blocked':
            raise Blocked(source)
        if entry.kind == 'rate_limited':
            raise RateLimited(source, remaining, entry.upstream_status)
        raise Unavailable('upstream cooling down')

    def note_cooldown(self, source, kind, seconds, upstream_status):
        """Record why this source is closed, keeping the longest known deadline.

        Two refusals can be in flight at once. The later deadline wins, because
        letting the shorter one expire would put requests back on the wire while
        the exchange is still counting; a tie keeps the stronger category.
        """
        entry = Cooldown(time.monotonic() + seconds, kind, int(seconds), str(upstream_status))
        with self.lock:
            current = self.cooldown.get(source)
            if current is None or (entry.until, COOLDOWN_RANK[kind]) \
                    >= (current.until, COOLDOWN_RANK[current.kind]):
                self.cooldown[source] = entry

    def download(self, key, ttl, background=False):
        source, path, query = key
        self.gates[source].reserve(background=background)
        # The pacing gate can hold a request for seconds, and the answer that
        # closed this source may have arrived during that wait. Look again before
        # going out: a request admitted before the ban must not be the one that
        # extends it.
        self.check_cooldown(source)
        status, data, headers = self.connections[source].fetch(
            path + ('?' + query if query else ''),
            {'User-Agent': 'Kanpan-Market-Probe/1.0', 'Accept': 'application/json',
             'Host': HOSTS[source], 'Connection': 'keep-alive'},
            10, 2 * 1024 * 1024)
        if status != 200:
            # Three different upstream refusals, three different client actions:
            # 403/418/429 are "wait and come back" (WAF ban, IP ban, rate limit),
            # 451 is "this node can never serve you", anything else is a fault.
            if status in RATE_LIMIT_DEFAULTS:
                seconds = retry_after_seconds(headers) or RATE_LIMIT_DEFAULTS[status]
                self.note_cooldown(source, 'rate_limited', seconds, status)
                raise RateLimited(source, seconds, status)
            if status == 451:
                self.note_cooldown(source, 'blocked', 60, status)
                raise Blocked(source)
            raise Unavailable('upstream unavailable')
        value = json.loads(data)
        with self.lock:
            old = self.cache.pop(key, None)
            if old:
                self.bytes -= len(old[1])
            self.cache[key] = (time.monotonic() + ttl, data); self.bytes += len(data)
            while self.bytes > 32 * 1024 * 1024 or len(self.cache) > 512:
                _, old = self.cache.popitem(last=False); self.bytes -= len(old[1])
        return value

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
        return self.page_ttl(interval, min(end, now), now)

    def cached_response(self, key, ttl, build):
        """Cache finished response bytes, not values that must be re-encoded.

        A hit used to cost json.loads of the upstream payload plus the whole
        normalisation plus json.dumps again -- for a 1500-bar page that is the
        dominant server cost of a cached request.
        """
        with self.lock:
            hit = self.responses.get(key)
            payload = hit[1] if hit and hit[0] > time.monotonic() else None
            if payload is not None:
                self.responses.move_to_end(key)
            if ttl <= WARM_TTL_MAX:
                # Someone is watching this window right now: keep it fresh for
                # them instead of making the next request wait for the exchange.
                self.warm[key] = [time.monotonic(), ttl, build]
                self.warm.move_to_end(key)
                while len(self.warm) > WARM_KEYS:
                    self.warm.popitem(last=False)
        if payload is not None:
            return payload
        payload = build()
        self.keep(key, ttl, payload)
        return payload

    def keep(self, key, ttl, payload):
        with self.lock:
            old = self.responses.pop(key, None)
            if old:
                self.response_bytes -= len(old[1])
            self.responses[key] = (time.monotonic() + ttl, payload)
            self.response_bytes += len(payload)
            while self.response_bytes > 32 * 1024 * 1024 or len(self.responses) > 512:
                _, dropped = self.responses.popitem(last=False)
                self.response_bytes -= len(dropped[1])

    def start_warming(self):
        """Run by the service, never by a unit test: it calls the exchanges."""
        if self.warming is None or not self.warming.is_alive():
            self.warming = threading.Thread(target=self.warm_forever, name='market-warm', daemon=True)
            self.warming.start()

    def warm_forever(self):
        while True:
            try:
                self.warm_once()
            except Exception:
                pass  # a refresher that dies would silently restore the old latency
            time.sleep(.1)

    def warm_once(self):
        """Refresh every watched window that is about to expire.

        The staleness bound is unchanged -- the entry still lives exactly `ttl`
        seconds -- the waiting simply moves off the phone's request.
        """
        now = time.monotonic()
        due = []
        with self.lock:
            for key, entry in list(self.warm.items()):
                if now - entry[0] > WARM_IDLE_SECONDS:
                    del self.warm[key]
                    continue
                if key in self.warm_active:
                    continue
                held = self.responses.get(key)
                if held is None or held[0] - now <= WARM_LEAD:
                    self.warm_active.add(key)
                    due.append((key, entry[1], entry[2]))
        for key, ttl, build in due:
            self.warm_pool.submit(self.refresh, key, ttl, build)
        return len(due)

    def refresh(self, key, ttl, build):
        DEMAND.background = True
        try:
            self.keep(key, ttl, build())
        except Exception:
            # A failing refresh must not cost the phone anything: it still
            # fetches for itself, and this key goes cold shortly.
            with self.lock:
                entry = self.warm.get(key)
                if entry:
                    entry[0] = min(entry[0], time.monotonic() - WARM_IDLE_SECONDS + 5)
        finally:
            DEMAND.background = False
            with self.lock:
                self.warm_active.discard(key)

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
        if source not in HOSTS or not SYMBOL.fullmatch(symbol):
            raise ValueError('invalid request')
        return self.cached_response(('ticker', source, symbol), 1, lambda: json.dumps(
            {'source': source, 'symbol': symbol, 'ticker': self.ticker(source, symbol)},
            separators=(',', ':')).encode())

    def tickers_response(self, source):
        """Same envelope as the single quote, with `symbol` empty and an array.

        Five seconds of cache: three phones watching the sector page cost at most
        one upstream request per five seconds, and the board is a ranking, not a
        tape.
        """
        if source not in HOSTS:
            raise ValueError('invalid request')
        return self.cached_response(('tickers', source), 5, lambda: json.dumps(
            {'source': source, 'symbol': '', 'ticker': self.tickers(source)},
            separators=(',', ':')).encode())

    def instruments_response(self, source):
        if source not in HOSTS:
            raise ValueError('invalid request')
        return self.cached_response(('instruments', source), 300, lambda: json.dumps(
            {'source': source, 'instruments': self.exchange_info(source)}, separators=(',', ':')).encode())

    def validate_klines(self, source, symbol, interval, limit, start=None, end=None):
        """Cheap argument check, so a request can be rejected (or a hung-up
        client abandoned) before any upstream work starts."""
        now = int(time.time() * 1000)
        if source not in HOSTS or interval not in STEPS or not 1 <= limit <= 1500:
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
        series = (source, symbol, interval)
        answer = lambda bars: {'source': source, 'symbol': symbol, 'interval': interval,
                               'bars': bars, 'serverTime': now}
        held = []
        if not latest_window:
            # Closed bars cannot change, so the overlap a scroll-back window
            # shares with the previous one never needs the exchange twice.
            if start is not None:
                covered = self.bars.window(series, interval, limit, start, end, now)
                if covered is not None:
                    return answer(covered)
            else:
                held = self.bars.tail(series, interval, limit, end, now)
                if len(held) == limit:
                    return answer(held)
                if held:
                    # Ask the exchange only for the part below what is held.
                    end, limit = int(held[0][0]) - 1, limit - len(held)
        # One request covers any window: /fapi/v1/klines answers up to 1500 rows.
        query = {'symbol': symbol, 'interval': interval, 'limit': limit, 'endTime': end}
        if start is not None:
            query['startTime'] = start
        rows = self.get(source, '/fapi/v1/klines', query)
        for row in rows:
            valid_row(row, interval)
        rows = [r for r in rows if (start is None or int(r[0]) >= start) and int(r[0]) <= end]
        rows = rows[:limit] if start is not None else rows[-limit:]
        if held and rows:
            # The join is checked by the same rule as the rest of the window, so
            # a spliced answer is either byte-identical to the network's or an error.
            rows = rows + held
        elif held:
            rows = held
        if any(close_time(int(a[0]), interval) != int(b[0]) for a, b in zip(rows, rows[1:])):
            raise Unavailable('history has gaps')
        # Keep the closed prefix only: the newest bar of a live window is still
        # moving, and a cache that remembered it would freeze the chart.
        closed = [r for r in rows if close_time(int(r[0]), interval) <= now]
        self.bars.merge(series, interval, closed)
        return answer(rows)

    def ticker(self, source, symbol):
        return self.get(source, '/fapi/v1/ticker/24hr', {'symbol': symbol})

    def tickers(self, source):
        """The whole board in one answer, for the sector page.

        Binance's own endpoint already answers in the single-quote shape when the
        symbol is omitted, so it is passed through untouched. One request is
        also the only affordable shape: several hundred single-symbol requests
        would spend the pacing budget the chart needs.
        """
        return self.get(source, '/fapi/v1/ticker/24hr', {}, ttl=5)

    def exchange_info(self, source):
        return self.get(source, '/fapi/v1/exchangeInfo', {}, ttl=300)


MARKET = PublicMarket()
