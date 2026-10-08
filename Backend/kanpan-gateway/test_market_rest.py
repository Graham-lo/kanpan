import atexit
import contextlib
import email.message
import email.utils
import itertools
import json
import shutil
import tempfile
import threading
import time
import unittest
from pathlib import Path
from market_rest import (DEMAND, BarCache, Blocked, Cooldown, PublicMarket, RateGate,
                         RateLimited, Unavailable, WARM_IDLE_SECONDS, bucket, close_time,
                         retry_after_seconds)

# Fixtures must never read or write the production bar store under
# /var/cache/kanpan-gateway, and two tests must not see each other's series.
FIXTURE_BARS = Path(tempfile.mkdtemp(prefix='kanpan-bars-test-'))
atexit.register(shutil.rmtree, FIXTURE_BARS, ignore_errors=True)
SERIAL = itertools.count()


def raw(at, price='100', volume='2.5'):
    """One Binance /fapi/v1/klines row for a 1m bar, as it arrives on the wire."""
    return [at, price, '110', '90', '105', volume, at + 59_999, '262.5', 3, '1.2', '126', '0']


class FixtureMarket(PublicMarket):
    """Answers /fapi/v1/klines the way Binance does, from an in-memory series."""
    def __init__(self, rows):
        super().__init__(); self.rows = rows; self.calls = []
        self.bars = BarCache(root=FIXTURE_BARS / str(next(SERIAL)))

    def get(self, source, path, query, ttl=1):
        self.calls.append((source, path, query.copy()))
        limit = int(query['limit'])
        rows = sorted((r for r in self.rows if r[0] <= int(query['endTime'])), key=lambda r: r[0])
        if 'startTime' in query:
            return [r for r in rows if r[0] >= int(query['startTime'])][:limit]
        return rows[-limit:]


class UncachedMarket(FixtureMarket):
    """Keeps the real request-sharing logic; only the network below it is faked."""
    get = PublicMarket.get


class FakeUpstream:
    """Stands in for one exchange host: canned replies, and a record of the wire.

    A reply is `(status, body, headers)`, or a callable returning one. Asking for
    a reply that was never provided is the failure the cooldown tests are looking
    for: a request that should never have left the process.
    """

    def __init__(self, *replies):
        self.replies = list(replies)
        self.calls = []

    def fetch(self, path, headers, timeout, limit):
        self.calls.append(path)
        if not self.replies:
            raise AssertionError('unexpected upstream request: ' + path)
        reply = self.replies.pop(0)
        return reply() if callable(reply) else reply


def wired(source, *replies):
    """A market whose only difference from production is the socket underneath."""
    market = PublicMarket()
    market.bars = BarCache(root=FIXTURE_BARS / str(next(SERIAL)))
    upstream = FakeUpstream(*replies)
    market.connections[source] = upstream
    return market, upstream


def ok(payload):
    """One successful Binance answer as it arrives on the socket."""
    return (200, json.dumps(payload, separators=(',', ':')).encode(), {})


class MarketTests(unittest.TestCase):
    def test_utc_calendar_and_week_boundaries(self):
        self.assertEqual(close_time(1_706_745_600_000, '1M'), 1_709_251_200_000)  # Feb 2024, leap year.
        self.assertEqual(bucket(1_709_510_400_000, '1w'), 1_709_510_400_000)

    def test_invalid_values_fail_instead_of_reaching_the_chart(self):
        at = bucket(1_700_000_040_000, '1m')
        for row in (raw(at, price='nan'), raw(at, price='0'), raw(at + 1), raw(at)[:5]):
            with self.assertRaises(Unavailable):
                FixtureMarket([row]).klines('binance', 'BTCUSDT', '1m', 1, end=at + 60_000)

    def test_latest_older_and_start_based_windows(self):
        end = int(time.time() * 1000) // 60_000 * 60_000
        data = [raw(end - i * 60_000) for i in range(1600)]
        market = FixtureMarket(data)
        latest = market.klines('binance', 'BTCUSDT', '1m', 300)
        self.assertEqual(latest['source'], 'binance')
        self.assertEqual(len(latest['bars']), 300)
        self.assertEqual(latest['bars'][-1][0], end)
        self.assertEqual(market.calls[0][1], '/fapi/v1/klines')
        self.assertEqual(market.calls[0][2]['limit'], 300)
        older = market.klines('binance', 'BTCUSDT', '1m', 300, end=latest['bars'][0][0] - 1)
        self.assertEqual(older['bars'][-1][0] + 60_000, latest['bars'][0][0])
        start = end - 700 * 60_000
        gap = market.klines('binance', 'BTCUSDT', '1m', 300, start=start)
        self.assertEqual(market.calls[-1][2]['startTime'], start)
        self.assertEqual(gap['bars'][0][0], start)
        self.assertEqual(gap['bars'][-1][0], start + 299 * 60_000)

    def test_history_gap_is_error_not_short_success(self):
        end = int(time.time() * 1000) // 60_000 * 60_000
        market = FixtureMarket([raw(end), raw(end - 120_000), raw(end - 180_000)])
        with self.assertRaises(Unavailable): market.klines('binance', 'BTCUSDT', '1m', 3)

    def test_unbounded_requests_rejected_before_network(self):
        market = FixtureMarket([])
        # OKX is a venue of kanpan-api now; this gateway never fetches it.
        for source, limit in [('binance', 1501), ('okx', 10), ('https://localhost', 10)]:
            with self.assertRaises(ValueError): market.klines(source, 'BTCUSDT', '1m', limit)
        self.assertEqual(market.calls, [])

    def test_response_bytes_are_cached_but_server_time_stays_fresh(self):
        end = 1_700_000_000_000 // 60_000 * 60_000
        market = FixtureMarket([raw(end - i * 60_000) for i in range(400)])
        first = market.klines_response('binance', 'BTCUSDT', '1m', 300, None, end)
        calls = len(market.calls)
        second = market.klines_response('binance', 'BTCUSDT', '1m', 300, None, end)
        # A hit re-fetches nothing and re-normalises nothing.
        self.assertEqual(len(market.calls), calls)
        self.assertEqual(first.split(b',"serverTime"')[0], second.split(b',"serverTime"')[0])
        a, b = json.loads(first), json.loads(second)
        self.assertEqual(a['bars'], b['bars'])
        self.assertLess(abs(b['serverTime'] - int(time.time() * 1000)), 5_000)

    def test_closed_pages_are_cached_far_longer_than_live_ones(self):
        market = FixtureMarket([])
        now = int(time.time() * 1000)
        self.assertEqual(market.page_ttl('1m', now, now), 1)
        self.assertEqual(market.page_ttl('1m', now - 3 * 60_000, now), 3600)
        self.assertEqual(market.page_ttl('1m', now - 3 * 86_400_000, now), 6 * 3600)
        self.assertEqual(market.klines_ttl('1m', None, None, now), 1)

    def test_geo_block_survives_cooldown_as_its_own_signal(self):
        market = FixtureMarket([])
        market.cooldown['binance'] = Cooldown(time.monotonic() + 60, 'blocked', 60, '451')
        with self.assertRaises(Blocked) as caught:
            market.check_cooldown('binance')
        self.assertEqual(caught.exception.source, 'binance')
        # A generic fault, not 403: a WAF ban is a rate limit now (see A-T06).
        market.cooldown['binance'] = Cooldown(time.monotonic() + 10, 'unavailable', 10, '500')
        with self.assertRaises(Unavailable) as other:
            market.check_cooldown('binance')
        self.assertNotIsInstance(other.exception, Blocked)
        self.assertNotIsInstance(other.exception, RateLimited)


class RateLimitTests(unittest.TestCase):
    """A-05: a stop condition must keep its category and its deadline."""

    TICKER = ('binance', '/fapi/v1/ticker/24hr', 'symbol=BTCUSDT')

    def test_upstream_429_carries_the_published_deadline(self):
        market, upstream = wired('binance', (429, b'{}', {'Retry-After': '120'}))
        with self.assertRaises(RateLimited) as caught:
            market.download(self.TICKER, 1)
        self.assertEqual((caught.exception.source, caught.exception.retry_after,
                          caught.exception.upstream_status), ('binance', 120, '429'))
        entry = market.cooldown['binance']
        self.assertEqual(entry.kind, 'rate_limited')
        self.assertGreater(entry.until - time.monotonic(), 110)
        # And a request that arrives later is told what is actually left, not 120.
        with self.assertRaises(RateLimited) as later:
            market.check_cooldown('binance')
        self.assertLessEqual(later.exception.retry_after, 120)
        self.assertEqual(upstream.calls, ['/fapi/v1/ticker/24hr?symbol=BTCUSDT'])

    def test_a_ban_without_a_header_gets_the_documented_minimum(self):
        # Binance publishes 2 minutes to 3 days for 418 and nothing for a bare
        # 429; guessing seconds is what kept the app hammering a banned IP.
        for status, expected in [(418, 120), (429, 10)]:
            market, _ = wired('binance', (status, b'{}', {}))
            with self.assertRaises(RateLimited) as caught:
                market.download(self.TICKER, 1)
            self.assertEqual((caught.exception.retry_after, caught.exception.upstream_status),
                             (expected, str(status)))

    def test_retry_after_reads_seconds_dates_and_nothing_else(self):
        self.assertEqual(retry_after_seconds({'Retry-After': '45'}), 45)
        self.assertIsNone(retry_after_seconds({}))
        self.assertIsNone(retry_after_seconds({'Retry-After': '0'}))  # not a credible invitation
        self.assertIsNone(retry_after_seconds({'Retry-After': 'soon'}))
        self.assertIsNone(retry_after_seconds({'Retry-After': email.utils.formatdate(time.time() - 60)}))
        date = email.utils.formatdate(time.time() + 300, usegmt=True)
        self.assertIn(retry_after_seconds({'Retry-After': date}), range(295, 302))
        # Real replies come back as an email.message.Message, where the case of
        # the header name is not ours to rely on.
        message = email.message.Message()
        message['retry-after'] = '7'
        self.assertEqual(retry_after_seconds(message), 7)

    def test_a_queued_request_rechecks_the_cooldown_before_the_wire(self):
        """A-T07: released from the pacing queue into a ban is not permission."""
        class QueuedGate:
            """First reserve passes; everyone behind it waits to be released."""
            def __init__(self):
                self.lock = threading.Lock()
                self.taken = 0
                self.queued = threading.Event()
                self.release = threading.Event()

            def reserve(self, patience=8.0, background=False):
                with self.lock:
                    self.taken += 1
                    first = self.taken == 1
                if first:
                    return
                self.queued.set()
                if not self.release.wait(5):
                    raise Unavailable('upstream pacing exceeded')

        gate = QueuedGate()

        def refuse():
            # Hold the first request on the wire until the second is queued
            # behind it, so the ban really is set while that one is waiting.
            self.assertTrue(gate.queued.wait(5))
            return 429, b'{}', {'Retry-After': '120'}

        market, upstream = wired('binance', refuse)
        market.gates['binance'] = gate
        failures = {}

        def attempt(name, key):
            try:
                market.download(key, 1)
            except Exception as error:  # both are expected to fail; how differs
                failures[name] = error

        first = threading.Thread(target=attempt, args=('first', self.TICKER))
        first.start()
        self.addCleanup(first.join, 5)
        while gate.taken < 1:
            time.sleep(.005)
        second = threading.Thread(target=attempt, args=(
            'second', ('binance', '/fapi/v1/klines', 'interval=1m&symbol=ETHUSDT')))
        second.start()
        self.addCleanup(second.join, 5)
        self.assertTrue(gate.queued.wait(5))
        first.join(5)
        self.assertFalse(first.is_alive())
        gate.release.set()  # the pacing slot opens only after the ban is recorded
        second.join(5)
        self.assertFalse(second.is_alive())
        self.assertIsInstance(failures['first'], RateLimited)
        self.assertIsInstance(failures['second'], RateLimited)
        self.assertEqual(failures['second'].upstream_status, '429')
        # One request went out, and the queued one never became a second.
        self.assertEqual(upstream.calls, ['/fapi/v1/ticker/24hr?symbol=BTCUSDT'])

    def test_a_rejected_request_is_not_a_rate_limit_and_cools_nothing(self):
        market, _ = wired('binance', (400, b'{"code":-1121,"msg":"Invalid symbol."}', {}))
        with self.assertRaises(Unavailable) as caught:
            market.download(self.TICKER, 1)
        self.assertNotIsInstance(caught.exception, RateLimited)
        self.assertNotIn('binance', market.cooldown)  # one bad symbol closes nothing

    def test_the_longer_deadline_wins_when_two_refusals_overlap(self):
        market, _ = wired('binance')
        market.note_cooldown('binance', 'rate_limited', 120, 429)
        market.note_cooldown('binance', 'rate_limited', 5, 429)
        self.assertEqual(market.cooldown['binance'].retry_after, 120)
        market.note_cooldown('binance', 'blocked', 600, 451)
        self.assertEqual(market.cooldown['binance'].kind, 'blocked')


class AllMarketTickerTests(unittest.TestCase):
    """A-04: the sector page needs every symbol in one answer, in one request."""

    ROW = {'symbol': 'BTCUSDT', 'lastPrice': '100', 'openPrice': '80', 'highPrice': '110',
           'lowPrice': '70', 'volume': '12.5', 'quoteVolume': '1250', 'closeTime': 2000}

    def test_the_board_is_binance_passed_through_in_the_single_quote_envelope(self):
        board = [self.ROW, dict(self.ROW, symbol='ETHUSDT')]
        market, upstream = wired('binance', ok(board), ok(self.ROW))
        answer = json.loads(market.tickers_response('binance'))
        single = json.loads(market.ticker_response('binance', 'BTCUSDT'))
        # Same envelope as one symbol: same keys, same source, symbol an empty
        # string, and the payload under the very same `ticker` key.
        self.assertEqual(set(answer), set(single))
        self.assertEqual((answer['source'], answer['symbol']), ('binance', ''))
        self.assertEqual(answer['ticker'], board)
        self.assertEqual(single['ticker'], self.ROW)
        self.assertEqual(upstream.calls, ['/fapi/v1/ticker/24hr', '/fapi/v1/ticker/24hr?symbol=BTCUSDT'])

    def test_a_second_request_inside_five_seconds_never_reaches_the_exchange(self):
        market, upstream = wired('binance', ok([self.ROW]))
        first = market.tickers_response('binance')
        second = market.tickers_response('binance')
        self.assertEqual(first, second)
        # Three phones on the sector page cost one upstream board per 5 seconds.
        self.assertEqual(upstream.calls, ['/fapi/v1/ticker/24hr'])
        self.assertGreater(market.responses[('tickers', 'binance')][0] - time.monotonic(), 4)

    def test_a_bad_source_is_rejected_before_any_work(self):
        market, upstream = wired('binance')
        for source in ('okx', 'bitmex'):
            with self.assertRaises(ValueError):
                market.tickers_response(source)
            with self.assertRaises(ValueError):
                market.ticker_response(source, 'BTCUSDT')
            with self.assertRaises(ValueError):
                market.instruments_response(source)
        self.assertEqual(upstream.calls, [])


class BarStoreTests(unittest.TestCase):
    """The store may only ever answer with the rows the network would have returned."""

    OLD = bucket(1_700_000_000_000, '1m')  # long closed, so nothing here is live

    def series(self, count=1200, end=None):
        end = self.OLD if end is None else end
        return [raw(end - i * 60_000) for i in range(count)]

    def test_overlapping_scroll_back_window_is_a_local_slice(self):
        rows = self.series()
        market = FixtureMarket(rows)
        market.klines('binance', 'BTCUSDT', '1m', 1000, end=self.OLD)
        calls = len(market.calls)
        self.assertEqual(calls, 1)  # the first window really did go upstream
        shifted = self.OLD - 137 * 60_000
        served = market.klines('binance', 'BTCUSDT', '1m', 600, end=shifted)
        self.assertEqual(len(market.calls), calls)  # not one extra request
        # And it is the same answer, bar for bar, as a node with no store at all.
        fresh = FixtureMarket(rows)
        self.assertEqual(served['bars'], fresh.klines('binance', 'BTCUSDT', '1m', 600, end=shifted)['bars'])

    def test_a_deeper_window_fetches_only_the_part_below_the_overlap(self):
        rows = self.series()
        market = FixtureMarket(rows)
        market.klines('binance', 'BTCUSDT', '1m', 600, end=self.OLD)
        calls = len(market.calls)
        deeper = self.OLD - 137 * 60_000
        served = market.klines('binance', 'BTCUSDT', '1m', 600, end=deeper)
        self.assertEqual(len(market.calls), calls + 1)
        # The one request asks only for the 137 bars below what is already held.
        asked = market.calls[-1][2]
        self.assertEqual(asked['limit'], 137)
        self.assertEqual(asked['endTime'], self.OLD - 599 * 60_000 - 1)
        fresh = FixtureMarket(rows)
        # Identical to a node with no store.
        self.assertEqual(served['bars'], fresh.klines('binance', 'BTCUSDT', '1m', 600, end=deeper)['bars'])
        self.assertEqual(len(served['bars']), 600)

    def test_live_window_is_never_served_from_the_store(self):
        end = bucket(int(time.time() * 1000), '1m')
        market = FixtureMarket(self.series(400, end))
        market.klines('binance', 'BTCUSDT', '1m', 300)
        calls = len(market.calls)
        market.klines('binance', 'BTCUSDT', '1m', 300)
        self.assertGreater(len(market.calls), calls)
        # A window ending inside the forming bar is the same live window.
        held = market.bars.window(('binance', 'BTCUSDT', '1m'), '1m', 300, None,
                                 int(time.time() * 1000), int(time.time() * 1000))
        self.assertIsNone(held)

    def test_store_declines_anything_it_does_not_fully_hold(self):
        cache = BarCache(root=FIXTURE_BARS / str(next(SERIAL)))
        key, now = ('binance', 'BTCUSDT', '1m'), self.OLD + 60_000
        bars = [[self.OLD - i * 60_000] + ['1'] * 8 for i in range(200)][::-1]
        cache.merge(key, '1m', bars)
        self.assertEqual(len(cache.window(key, '1m', 200, None, self.OLD, now)), 200)
        # One bar deeper than the run reaches: only the exchange knows the rest.
        self.assertIsNone(cache.window(key, '1m', 201, None, self.OLD, now))
        # A newer window: the run stops short of it.
        self.assertIsNone(cache.window(key, '1m', 10, None, self.OLD + 10 * 60_000, now))
        # A start-based window must begin on a bar the run actually holds.
        self.assertIsNone(cache.window(key, '1m', 10, self.OLD - 500 * 60_000, now, now))
        self.assertEqual(len(cache.window(key, '1m', 10, self.OLD - 100 * 60_000, now, now)), 10)

    def test_merge_rejects_holes_and_replaces_on_a_jump(self):
        cache = BarCache(root=FIXTURE_BARS / str(next(SERIAL)))
        key = ('binance', 'BTCUSDT', '1m')
        run = [[self.OLD - i * 60_000] + ['1'] * 8 for i in range(100)][::-1]
        cache.merge(key, '1m', run)
        cache.merge(key, '1m', [run[0], run[5]])  # a hole is not a run
        self.assertEqual(len(cache.series[key]), 100)
        far = [[self.OLD - (5_000 + i) * 60_000] + ['2'] * 8 for i in range(50)][::-1]
        cache.merge(key, '1m', far)  # a jump elsewhere in history replaces it
        self.assertEqual(len(cache.series[key]), 50)
        self.assertEqual(cache.bars, 50)

    def test_run_survives_a_restart_through_disk(self):
        root = FIXTURE_BARS / str(next(SERIAL))
        key, now = ('binance', 'BTCUSDT', '1m'), self.OLD + 60_000
        bars = [[self.OLD - i * 60_000] + ['1'] * 8 for i in range(120)][::-1]
        BarCache(root=root).merge(key, '1m', bars)
        restarted = BarCache(root=root)
        self.assertEqual(len(restarted.window(key, '1m', 120, None, self.OLD, now)), 120)

    def fill(self, cache, count=3, length=200):
        for n in range(count):
            bars = [[self.OLD - (n * 10_000 + i) * 60_000] + ['1'] * 8 for i in range(length)][::-1]
            cache.merge(('binance', 'S%d' % n, '1m'), '1m', bars)

    def test_store_is_bounded_in_both_bars_and_series(self):
        by_series = BarCache(root=FIXTURE_BARS / str(next(SERIAL)), memory=10_000, series=2)
        self.fill(by_series)
        self.assertEqual(len(by_series.series), 2)
        self.assertEqual(by_series.bars, 400)
        self.assertLessEqual(len(by_series.written), 2)  # the write clock cannot outgrow the store
        by_bars = BarCache(root=FIXTURE_BARS / str(next(SERIAL)), memory=300, series=8)
        self.fill(by_bars)
        self.assertLessEqual(by_bars.bars, 300)
        self.assertEqual(by_bars.bars, sum(len(run) for run in by_bars.series.values()))


class WarmTests(unittest.TestCase):
    """Background refresh moves the wait off the phone without extending staleness."""

    def settled(self, market, key):
        for _ in range(400):
            if key not in market.warm_active:
                return
            time.sleep(.01)
        self.fail('refresh never finished')

    def test_only_live_windows_are_kept_warm(self):
        market = FixtureMarket([])
        market.cached_response(('klines', 'live'), 1, lambda: b'{}')
        market.cached_response(('klines', 'history'), 3600, lambda: b'{}')
        self.assertIn(('klines', 'live'), market.warm)
        self.assertNotIn(('klines', 'history'), market.warm)

    def test_refresh_runs_just_before_expiry_and_not_before(self):
        market = FixtureMarket([])
        builds = []
        def build():
            builds.append(time.monotonic())
            return b'{"n":%d}' % len(builds)
        key = ('klines', 'live')
        market.cached_response(key, 1, build)
        self.assertEqual(len(builds), 1)
        self.assertEqual(market.warm_once(), 0)  # still comfortably fresh
        market.responses[key] = (time.monotonic() + .1, market.responses[key][1])
        self.assertEqual(market.warm_once(), 1)
        self.settled(market, key)
        self.assertEqual(len(builds), 2)
        # The staleness bound is unchanged: the entry still lives exactly ttl.
        self.assertLessEqual(market.responses[key][0] - time.monotonic(), 1)
        self.assertEqual(market.cached_response(key, 1, build), b'{"n":2}')
        self.assertEqual(len(builds), 2)  # the phone waited for nothing

    def test_nobody_watching_means_nothing_to_warm(self):
        market = FixtureMarket([])
        key = ('klines', 'live')
        market.cached_response(key, 1, lambda: b'{}')
        market.warm[key][0] = time.monotonic() - WARM_IDLE_SECONDS - 1
        self.assertEqual(market.warm_once(), 0)
        self.assertNotIn(key, market.warm)

    def test_a_failing_refresh_costs_the_phone_nothing_and_goes_cold(self):
        market = FixtureMarket([])
        key = ('klines', 'live')
        market.cached_response(key, 1, lambda: b'{}')
        def boom():
            raise Unavailable('binance')
        market.refresh(key, 1, boom)
        self.assertNotIn(key, market.warm_active)
        self.assertEqual(market.responses[key][1], b'{}')  # the last good answer stands
        self.assertLess(market.warm[key][0], time.monotonic() - WARM_IDLE_SECONDS + 6)


class PacingPriorityTests(unittest.TestCase):
    def test_background_work_never_takes_a_slot_a_request_is_waiting_for(self):
        gate = RateGate(.2)
        gate.reserve()  # the slot is now taken until +.2s
        order = []

        def take(background):
            gate.reserve(background=background)
            order.append('warm' if background else 'phone')

        warm = threading.Thread(target=take, args=(True,))
        warm.start()
        time.sleep(.05)  # the refresher is already queued and waiting
        phone = threading.Thread(target=take, args=(False,))
        phone.start()
        for thread in (warm, phone):
            thread.join(5)
        self.assertEqual(order, ['phone', 'warm'])

    def test_a_free_gate_still_serves_background_at_once(self):
        gate = RateGate(0)
        gate.reserve(background=True)
        self.assertEqual(gate.waiting, 0)

    def test_a_request_does_not_inherit_a_failed_background_download(self):
        # The refresher gives up for reasons of its own — it yields its pacing
        # slot, it runs while the exchange is busy. A phone that happened to ask
        # for the same window while that was in flight must still get an answer.
        market = UncachedMarket([])
        joined, attempts = threading.Event(), []

        def download(key, ttl, background=False):
            attempts.append(background)
            if background:
                joined.wait(5)
                raise Unavailable('the refresher gave up')
            return ['fresh']

        market.download = download

        def refresher():  # the refresher swallows its own failures; so does this stand-in
            DEMAND.background = True  # what PublicMarket.refresh marks its thread with
            with contextlib.suppress(Unavailable):
                market.get('binance', '/x', {})

        warm = threading.Thread(target=refresher)
        warm.start()
        self.addCleanup(warm.join, 5)
        while not market.pending:
            time.sleep(.005)
        answer = threading.Thread(target=lambda: attempts.append(market.get('binance', '/x', {})))
        answer.start()
        time.sleep(.05)  # the phone is now waiting on the refresher's future
        joined.set()
        answer.join(5)
        self.assertEqual(attempts, [True, False, ['fresh']])


class UpstreamPoolTests(unittest.TestCase):
    """A quiet spell leaves every pooled keep-alive socket dead at once."""

    def test_dead_pool_is_dropped_and_retry_uses_a_fresh_connection(self):
        import http.client, http.server, socket
        import market_rest
        accepted = []

        class Handler(http.server.BaseHTTPRequestHandler):
            protocol_version = 'HTTP/1.1'

            def do_GET(self):
                accepted.append(self.connection)
                self.send_response(200)
                self.send_header('Content-Length', '2')
                self.end_headers()
                self.wfile.write(b'ok')

            def log_message(self, *args):
                pass

        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.shutdown)
        port = server.server_address[1]
        plain = lambda host, timeout=None: http.client.HTTPConnection('127.0.0.1', port, timeout=timeout)
        original = market_rest.http.client.HTTPSConnection
        market_rest.http.client.HTTPSConnection = plain
        self.addCleanup(setattr, market_rest.http.client, 'HTTPSConnection', original)

        pool = market_rest.Upstream('exchange.invalid')
        for _ in range(3):
            connection = plain('exchange.invalid', timeout=5)
            connection.request('GET', '/')
            connection.getresponse().read()
            pool._keep(connection)
        for sock in list(accepted):  # the exchange hangs up on idle sockets
            with contextlib.suppress(OSError):
                sock.shutdown(socket.SHUT_RDWR)
        time.sleep(0.2)

        status, body, _ = pool.fetch('/', {}, 5, 100)
        self.assertEqual((status, body), (200, b'ok'))
        # The dead siblings were closed, not left for the next request to trip on.
        self.assertLessEqual(len(pool.idle), 1)


if __name__ == '__main__':
    unittest.main()
