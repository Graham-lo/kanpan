import csv
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import zipfile
import server


def archive():
    out = io.BytesIO()
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('metrics.csv', 'create_time,symbol,sum_open_interest\n2021-12-01 00:00:00,BTCUSDT,100\n2021-12-01 00:05:00,BTCUSDT,101\n2021-12-01 00:00:00,BTCUSDT,102\n')
    return out.getvalue()


class GatewayTests(unittest.TestCase):
    def test_period_last_across_days_not_sum(self):
        day = 1638316800000
        def cached(symbol, date):
            offset = 0 if date == '2021-12-01' else server.DAY
            return json.dumps([[day + offset, 100], [day + offset + 300000, 120]]).encode(), 'HIT'
        with patch.object(server, 'cached_day', side_effect=cached):
            rows = json.loads(server.historical_series('BTCUSDT', '1d', day, day + 2 * server.DAY - 1))
            self.assertEqual(rows, [[day, 120], [day + server.DAY, 120]])
            month = json.loads(server.historical_series('BTCUSDT', '1M', day, day + 2 * server.DAY - 1))
            self.assertEqual(month, [[day, 120]])

    def test_calendar_and_all_intervals(self):
        time = 1709251199000  # 2024-02-29 23:59:59 UTC
        self.assertEqual(server.bucket_start(time, '1M'), 1706745600000)
        self.assertEqual(server.bucket_start(time, '1y'), 1704067200000)
        self.assertEqual(server.bucket_start(time, '1w'), 1708905600000)
        for interval in server.STEPS:
            bucket = server.bucket_start(time, interval)
            self.assertLessEqual(bucket, time)
            self.assertEqual(server.bucket_start(bucket, interval), bucket)

    def test_invalid_range_is_rejected_before_download(self):
        with patch.object(server, 'cached_day') as read:
            for interval, start, end in [('4h', 2, 1), ('8h', 1638316800000, 1638316800001),
                                         ('1m', 1638316800000, 1738316800000)]:
                with self.assertRaises(ValueError):
                    server.historical_series('BTCUSDT', interval, start, end)
            read.assert_not_called()

    def test_missing_day_is_a_gap(self):
        day = 1638316800000
        with patch.object(server, 'cached_day', side_effect=server.HTTPError('', 404, '', {}, None)):
            self.assertEqual(json.loads(server.historical_series('NEWUSDT', '4h', day, day + server.DAY - 1)), [])

    def test_archive_real_timestamps_and_duplicate_replacement(self):
        self.assertEqual(json.loads(server.parse_archive(archive())), [[1638316800000, 102], [1638317100000, 101]])

    def test_cache_hit_does_not_download_or_parse_again(self):
        class Response(io.BytesIO):
            pass
        with tempfile.TemporaryDirectory() as root, patch.object(server, 'CACHE', Path(root)), patch.object(server, 'urlopen', return_value=Response(archive())) as get:
            first, state = server.fetch_day('BTCUSDT', '2021-12-01')
            self.assertEqual(state, 'MISS')
            second, state = server.fetch_day('BTCUSDT', '2021-12-01')
            self.assertEqual((first, state), (second, 'HIT'))
            self.assertEqual(get.call_count, 1)

    def test_route_is_not_an_arbitrary_forward_proxy(self):
        self.assertIsNone(server.PATTERN.fullmatch('/oi/v1/metrics/../../secret.json'))
        self.assertIsNone(server.PATTERN.fullmatch('/oi/v1/metrics/BTCUSDT/2021-12-01.json?url=https://other.example'))


if __name__ == '__main__':
    unittest.main()
