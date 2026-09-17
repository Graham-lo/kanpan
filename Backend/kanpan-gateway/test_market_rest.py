import json
import threading
import time
import unittest
from market_rest import (Blocked, PublicMarket, Unavailable, bucket, close_time,
                         normalize_okx, step_back)


def raw(at, price='100', volume='2.5'):
    return [str(at), price, '110', '90', '105', '250', volume, '262.5', '1']


class FixtureMarket(PublicMarket):
    def __init__(self, rows):
        super().__init__(); self.rows = rows; self.calls = []

    def instrument(self, symbol):
        return {'instId': 'BTC-USDT-SWAP'}

    def get(self, source, path, query, ttl=1):
        self.calls.append((source, path, query.copy()))
        if path.endswith('/candles'):
            return sorted(self.rows, key=lambda row: int(row[0]), reverse=True)[:int(query['limit'])]
        return [r for r in self.rows if int(r[0]) < int(query['after'])][:int(query['limit'])]


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


if __name__ == '__main__':
    unittest.main()
