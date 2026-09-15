import time
import unittest
from market_rest import PublicMarket, Unavailable, bucket, close_time, normalize_okx


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


if __name__ == '__main__':
    unittest.main()
