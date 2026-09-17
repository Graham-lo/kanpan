import atexit
import contextlib
import itertools
import json
import shutil
import tempfile
import threading
import time
import unittest
from pathlib import Path
from market_rest import (BarCache, Blocked, PublicMarket, RateGate, Unavailable,
                         WARM_IDLE_SECONDS, bucket, close_time, normalize_okx, step_back)

# Fixtures must never read or write the production bar store under
# /var/cache/kanpan-gateway, and two tests must not see each other's series.
FIXTURE_BARS = Path(tempfile.mkdtemp(prefix='kanpan-bars-test-'))
atexit.register(shutil.rmtree, FIXTURE_BARS, ignore_errors=True)
SERIAL = itertools.count()


def raw(at, price='100', volume='2.5'):
    return [str(at), price, '110', '90', '105', '250', volume, '262.5', '1']


class FixtureMarket(PublicMarket):
    def __init__(self, rows):
        super().__init__(); self.rows = rows; self.calls = []
        self.bars = BarCache(root=FIXTURE_BARS / str(next(SERIAL)))

    def instrument(self, symbol):
        return {'instId': 'BTC-USDT-SWAP'}

    def get(self, source, path, query, ttl=1):
        self.calls.append((source, path, query.copy()))
        if path.endswith('/candles'):
            return sorted(self.rows, key=lambda row: int(row[0]), reverse=True)[:int(query['limit'])]
        return [r for r in self.rows if int(r[0]) < int(query['after'])][:int(query['limit'])]


class UncachedMarket(FixtureMarket):
    """Keeps the real request-sharing logic; only the network below it is faked."""
    get = PublicMarket.get


class CountingMarket(FixtureMarket):
    """Records how many upstream pages are in flight at the same moment."""
    def __init__(self, rows, delay=.02):
        super().__init__(rows); self.delay = delay
        self.active = 0; self.peak = 0; self.guard = threading.Lock()

    def get(self, source, path, query, ttl=1):
        with self.guard:
            self.active += 1; self.peak = max(self.peak, self.active)
        try:
            time.sleep(self.delay)
            return super().get(source, path, query, ttl)
        finally:
            with self.guard:
                self.active -= 1


class MarketTests(unittest.TestCase):
    def test_volume_uses_base_currency_not_contracts(self):
        row = normalize_okx([raw(1_700_000_040_000)], '1m')[0]
        self.assertEqual(row[5], '2.5')
        self.assertEqual(row[6], row[0] + 59_999)

    def test_utc_calendar_and_week_boundaries(self):
        self.assertEqual(close_time(1_706_745_600_000, '1M'), 1_709_251_200_000)  # Feb 2024, leap year.
        self.assertEqual(bucket(1_709_510_400_000, '1w'), 1_709_510_400_000)

    def test_partial_aggregate_cannot_invent_earlier_open(self):
        at = 1_700_006_400_000 // 28_800_000 * 28_800_000
        self.assertEqual(normalize_okx([raw(at + 14_400_000)], '8h'), [])
        rows = normalize_okx([raw(at), raw(at + 14_400_000)], '8h')
        self.assertEqual(len(rows), 1); self.assertEqual(float(rows[0][5]), 5)

    def test_invalid_values_and_duplicate_conflicts_fail(self):
        at = 1_700_000_040_000
        with self.assertRaises(Unavailable): normalize_okx([raw(at, price='nan')], '1m')
        with self.assertRaises(Unavailable): normalize_okx([raw(at), raw(at, volume='3')], '1m')

    def test_paging_and_start_based_gap_repair(self):
        end = int(time.time() * 1000) // 60_000 * 60_000
        data = [raw(end - i * 60_000) for i in range(1600)]
        market = FixtureMarket(data)
        latest = market.klines('okx', 'BTCUSDT', '1m', 300)
        self.assertEqual(latest['source'], 'okx')
        self.assertEqual(len(latest['bars']), 300)
        self.assertEqual(latest['bars'][-1][0], end)
        self.assertEqual(market.calls[0][1], '/api/v5/market/candles')
        self.assertEqual(market.calls[0][2]['limit'], 300)
        older = market.klines('okx', 'BTCUSDT', '1m', 300, end=latest['bars'][0][0] - 1)
        self.assertEqual(older['bars'][-1][0] + 60_000, latest['bars'][0][0])
        start = end - 700 * 60_000
        gap = market.klines('okx', 'BTCUSDT', '1m', 300, start=start)
        self.assertEqual(gap['bars'][0][0], start)
        self.assertEqual(gap['bars'][-1][0], start + 299 * 60_000)

    def test_history_gap_is_error_not_short_success(self):
        end = int(time.time() * 1000) // 60_000 * 60_000
        market = FixtureMarket([raw(end), raw(end - 120_000), raw(end - 180_000)])
        with self.assertRaises(Unavailable): market.klines('okx', 'BTCUSDT', '1m', 3)

    def test_unbounded_requests_rejected_before_network(self):
        market = FixtureMarket([])
        for source, limit in [('okx', 1501), ('https://localhost', 10)]:
            with self.assertRaises(ValueError): market.klines(source, 'BTCUSDT', '1m', limit)
        self.assertEqual(market.calls, [])


    def test_history_pages_run_in_parallel_without_losing_continuity(self):
        end = 1_700_000_000_000 // 60_000 * 60_000
        market = CountingMarket([raw(end - i * 60_000) for i in range(900)])
        page = market.klines('okx', 'BTCUSDT', '1m', 500, end=end)
        self.assertEqual(len(page['bars']), 500)
        self.assertEqual(page['bars'][-1][0], end)
        # Contiguity is still enforced; overlap between predicted pages is free.
        self.assertTrue(all(b[0] - a[0] == 60_000 for a, b in zip(page['bars'], page['bars'][1:])))
        self.assertGreater(market.peak, 1)  # the old loop was strictly one page at a time

    def test_month_cursors_step_by_calendar_not_thirty_days(self):
        january = 1_704_067_200_000  # 2024-01-01 UTC
        self.assertEqual(step_back(january, '1M', 1), 1_701_388_800_000)  # 2023-12-01
        self.assertEqual(step_back(january, '1M', 13), 1_669_852_800_000)  # 2022-12-01
        self.assertEqual(step_back(january, '1d', 3), january - 3 * 86_400_000)

    def test_response_bytes_are_cached_but_server_time_stays_fresh(self):
        end = 1_700_000_000_000 // 60_000 * 60_000
        market = FixtureMarket([raw(end - i * 60_000) for i in range(400)])
        first = market.klines_response('okx', 'BTCUSDT', '1m', 300, None, end)
        calls = len(market.calls)
        second = market.klines_response('okx', 'BTCUSDT', '1m', 300, None, end)
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
        market.cooldown['binance'] = (time.monotonic() + 60, True)
        market.cooldown['okx'] = (time.monotonic() + 10, False)
        with self.assertRaises(Blocked) as caught:
            market.check_cooldown('binance')
        self.assertEqual(caught.exception.source, 'binance')
        with self.assertRaises(Unavailable) as other:
            market.check_cooldown('okx')
        self.assertNotIsInstance(other.exception, Blocked)


class BarStoreTests(unittest.TestCase):
    """The store may only ever answer with the rows the network would have returned."""

    OLD = bucket(1_700_000_000_000, '1m')  # long closed, so nothing here is live

    def series(self, count=1200, end=None):
        end = self.OLD if end is None else end
        return [raw(end - i * 60_000) for i in range(count)]

    def test_overlapping_scroll_back_window_is_a_local_slice(self):
        rows = self.series()
        market = FixtureMarket(rows)
        market.klines('okx', 'BTCUSDT', '1m', 1000, end=self.OLD)
        calls = len(market.calls)
        self.assertGreater(calls, 1)  # the first window really did page upstream
        shifted = self.OLD - 137 * 60_000
        served = market.klines('okx', 'BTCUSDT', '1m', 600, end=shifted)
        self.assertEqual(len(market.calls), calls)  # not one extra request
        # And it is the same answer, bar for bar, as a node with no store at all.
        fresh = FixtureMarket(rows)
        self.assertEqual(served['bars'], fresh.klines('okx', 'BTCUSDT', '1m', 600, end=shifted)['bars'])

    def test_a_deeper_window_fetches_only_the_part_below_the_overlap(self):
        rows = self.series()
        market = FixtureMarket(rows)
        market.klines('okx', 'BTCUSDT', '1m', 600, end=self.OLD)
        calls = len(market.calls)
        deeper = self.OLD - 137 * 60_000
        served = market.klines('okx', 'BTCUSDT', '1m', 600, end=deeper)
        fetched = len(market.calls) - calls
        fresh = FixtureMarket(rows)
        # Identical to a node with no store, for a small fraction of the paging.
        self.assertEqual(served['bars'], fresh.klines('okx', 'BTCUSDT', '1m', 600, end=deeper)['bars'])
        self.assertEqual(len(served['bars']), 600)
        self.assertLess(fetched, len(fresh.calls) / 2)

    def test_live_window_is_never_served_from_the_store(self):
        end = bucket(int(time.time() * 1000), '1m')
        market = FixtureMarket(self.series(400, end))
        market.klines('okx', 'BTCUSDT', '1m', 300)
        calls = len(market.calls)
        market.klines('okx', 'BTCUSDT', '1m', 300)
        self.assertGreater(len(market.calls), calls)
        # A window ending inside the forming bar is the same live window.
        held = market.bars.window(('okx', 'BTCUSDT', '1m'), '1m', 300, None,
                                 int(time.time() * 1000), int(time.time() * 1000))
        self.assertIsNone(held)

    def test_store_declines_anything_it_does_not_fully_hold(self):
        cache = BarCache(root=FIXTURE_BARS / str(next(SERIAL)))
        key, now = ('okx', 'BTCUSDT', '1m'), self.OLD + 60_000
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
        key = ('okx', 'BTCUSDT', '1m')
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
        key, now = ('okx', 'BTCUSDT', '1m'), self.OLD + 60_000
        bars = [[self.OLD - i * 60_000] + ['1'] * 8 for i in range(120)][::-1]
        BarCache(root=root).merge(key, '1m', bars)
        restarted = BarCache(root=root)
        self.assertEqual(len(restarted.window(key, '1m', 120, None, self.OLD, now)), 120)

    def fill(self, cache, count=3, length=200):
        for n in range(count):
            bars = [[self.OLD - (n * 10_000 + i) * 60_000] + ['1'] * 8 for i in range(length)][::-1]
            cache.merge(('okx', 'S%d' % n, '1m'), '1m', bars)

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
            raise Unavailable('okx')
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
            with contextlib.suppress(Unavailable):
                market.get_as(True, 'okx', '/x', {})

        warm = threading.Thread(target=refresher)
        warm.start()
        self.addCleanup(warm.join, 5)
        while not market.pending:
            time.sleep(.005)
        answer = threading.Thread(target=lambda: attempts.append(market.get('okx', '/x', {})))
        answer.start()
        time.sleep(.05)  # the phone is now waiting on the refresher's future
        joined.set()
        answer.join(5)
        self.assertEqual(attempts, [True, False, ['fresh']])


class InstrumentIndexTests(unittest.TestCase):
    def test_instrument_table_is_decoded_once_not_per_request(self):
        market = FixtureMarket([])
        decoded = []
        live = {'settleCcy': 'USDT', 'ctType': 'linear', 'state': 'live'}
        rows = [dict(live, instId='BTC-USDT-SWAP', ctVal='0.01'), dict(live, instId='ETH-USDT-SWAP'), 'junk']
        def get(source, path, query, ttl=1):
            decoded.append(path)
            return rows
        market.get = get
        for _ in range(5):
            self.assertEqual(PublicMarket.instrument(market, 'BTCUSDT')['ctVal'], '0.01')
        self.assertEqual(len(decoded), 1)
        with self.assertRaises(Unavailable):
            PublicMarket.instrument(market, 'NOSUCHUSDT')



if __name__ == '__main__':
    unittest.main()
