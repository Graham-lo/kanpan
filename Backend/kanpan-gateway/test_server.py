import csv
import io
import os
import json
import tempfile
import socket
import time
import unittest
from pathlib import Path
from unittest.mock import patch
import zipfile
import server
from test_market_rest import wired  # same directory: one fake upstream for both halves


def archive():
    out = io.BytesIO()
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('metrics.csv', 'create_time,symbol,sum_open_interest\n2021-12-01 00:00:00,BTCUSDT,100\n2021-12-01 00:05:00,BTCUSDT,101\n2021-12-01 00:00:00,BTCUSDT,102\n')
    return out.getvalue()


class Recorder(server.Handler):
    """The real reply path with the socket replaced: status, headers and body.

    Retry-After is chosen inside `reply`, so a test that stubbed `reply` out
    could not see the one header this contract is about.
    """

    def __init__(self, path):
        self.path = path
        self.status = None
        self.sent = []
        self.refund = False
        self.close_connection = False
        self.client_address = ('192.0.2.7', 40000)
        self.headers = {}
        self.wfile = io.BytesIO()

    def send_response(self, code, message=None):
        self.status = code

    def send_header(self, name, value):
        self.sent.append((name, str(value)))

    def end_headers(self):
        pass

    def abandoned(self):
        return False  # covered on its own by the socket test below

    def header(self, name):
        return [value for sent, value in self.sent if sent.lower() == name.lower()]

    def body(self):
        return json.loads(self.wfile.getvalue())


class UpstreamStopTests(unittest.TestCase):
    """A-T06 (Python half): the stop condition the phone receives over the wire."""

    PATH = '/market/v1/ticker?source=okx&symbol=BTCUSDT'

    def answer(self, *replies):
        market, upstream = wired('okx', *replies)
        handler = Recorder(self.PATH)
        with patch.object(server, 'MARKET', market):
            handler.get_market_data()
        self.assertEqual(len(upstream.calls), 1)  # the fetch really was attempted
        return handler

    def test_a_published_deadline_reaches_the_client_intact(self):
        handler = self.answer((429, b'{}', {'Retry-After': '120'}))
        self.assertEqual(handler.status, 429)
        self.assertEqual(handler.header('Retry-After'), ['120'])  # exactly once, not the flat 2
        self.assertEqual(handler.header('X-Kanpan-Upstream'), ['okx-limited'])
        self.assertEqual(handler.body(), {'error': 'upstream_rate_limited', 'source': 'okx',
                                          'code': 429, 'retryAfter': 120, 'upstreamStatus': '429'})

    def test_a_ban_without_a_header_still_stops_for_two_minutes(self):
        handler = self.answer((418, b'{}', {}))
        self.assertEqual(handler.status, 429)
        self.assertEqual(handler.header('Retry-After'), ['120'])
        self.assertEqual(handler.body()['retryAfter'], 120)
        self.assertEqual(handler.body()['upstreamStatus'], '418')

    def test_an_okx_business_limit_travels_as_its_own_code(self):
        handler = self.answer((200, b'{"code":"50011","msg":"Too Many Requests","data":[]}', {}))
        self.assertEqual(handler.status, 429)
        self.assertEqual(handler.header('Retry-After'), ['10'])
        self.assertEqual(handler.body()['upstreamStatus'], '50011')

    def test_a_waf_ban_is_a_rate_limit_not_a_dead_route(self):
        """A-T06: 403 is Binance's WAF banning this node -- a wait, not a fault.

        It used to share 451's cooldown and surface as a plain 503, which told
        the phone "broken, try the other gateway" when the truth was "come back
        in a minute". On the wire it is now the 429 contract, with the real
        upstream status kept so the client can tell the two apart.
        """
        handler = self.answer((403, b'{}', {}))
        self.assertEqual(handler.status, 429)
        self.assertEqual(handler.header('Retry-After'), ['60'])
        self.assertEqual(handler.header('X-Kanpan-Upstream'), ['okx-limited'])
        self.assertEqual(handler.body(), {'error': 'upstream_rate_limited', 'source': 'okx',
                                          'code': 429, 'retryAfter': 60, 'upstreamStatus': '403'})
        # A header on a 403 is obeyed like any other published deadline.
        headed = self.answer((403, b'{}', {'Retry-After': '30'}))
        self.assertEqual((headed.status, headed.body()['retryAfter']), (429, 30))

    def test_a_geographic_block_is_unchanged(self):
        handler = self.answer((451, b'{}', {}))
        self.assertEqual(handler.status, 451)
        self.assertEqual(handler.header('X-Kanpan-Upstream'), ['okx-blocked'])
        self.assertEqual(handler.body(), {'error': 'upstream_blocked', 'source': 'okx', 'code': 451})
        self.assertTrue(handler.refund)

    def test_every_other_failure_is_still_a_plain_503(self):
        handler = self.answer((500, b'{}', {}))
        self.assertEqual(handler.status, 503)
        self.assertEqual(handler.body(), {'error': 'market unavailable'})
        self.assertEqual(handler.header('Retry-After'), ['2'])

    def test_this_node_being_busy_is_a_different_429(self):
        # Same status code, opposite advice: `busy` means try the other gateway
        # now, `upstream_rate_limited` means nobody may ask the exchange yet.
        class Full:
            def enter(self, key):
                return False

            def leave(self, key, refund=False):
                pass

        handler = Recorder(self.PATH)
        with patch.object(server, 'HTTP_GUARD', Full()):
            handler.do_GET()
        self.assertEqual(handler.status, 429)
        self.assertEqual(handler.body(), {'error': 'busy'})
        self.assertEqual(handler.header('Retry-After'), ['2'])
        queued = Recorder(self.PATH)
        with patch.object(server.MARKET_SLOTS, 'acquire', return_value=False):
            queued.get_market_data()
        self.assertEqual((queued.status, queued.body()), (503, {'error': 'busy'}))
        self.assertNotEqual(handler.body()['error'], 'upstream_rate_limited')


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

    def test_eviction_reads_the_index_not_the_directory(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            for name, size, age in [('old.json', 40, 100), ('new.json', 40, 300)]:
                (root / name).write_bytes(b'x' * size)
                os.utime(root / name, (age, age))  # the sweep orders by mtime, so pin it
            index = server.CacheIndex()
            index.warm(root)
            self.assertEqual(index.bytes, 80)
            with patch.object(Path, 'glob', side_effect=AssertionError('rescanned the cache directory')):
                victims = index.store(root, root / 'fresh.json', 40, 400, 100)
            # Oldest first, and never the slice this request just produced.
            self.assertEqual(victims, [root / 'old.json'])
            self.assertEqual(index.bytes, 80)
            self.assertNotIn(root / 'old.json', index.entries)

    def test_upstream_block_is_a_stable_client_signal(self):
        handler = server.Handler.__new__(server.Handler)
        handler.refund = False
        seen = {}
        handler.reply = lambda status, payload, cache='no-store', hit=None, extra=(): seen.update(
            status=status, payload=payload, extra=list(extra))
        handler.blocked('binance')
        self.assertEqual(seen['status'], 451)
        self.assertIn(('X-Kanpan-Upstream', 'binance-blocked'), seen['extra'])
        self.assertEqual(json.loads(seen['payload']), {'error': 'upstream_blocked', 'source': 'binance', 'code': 451})
        self.assertTrue(handler.refund)  # a geo block must not spend the caller's quota

    def test_hung_up_client_skips_the_upstream_fetch(self):
        # Real sockets, with the same 30 s timeout the server sets: a timed-out
        # socket's recv() would block for the whole timeout before honouring
        # MSG_DONTWAIT, so an idle keep-alive must come back at once.
        server_side, client_side = socket.socketpair()
        try:
            server_side.settimeout(30)
            handler = server.Handler.__new__(server.Handler)
            handler.connection = server_side
            started = time.monotonic()
            self.assertFalse(handler.abandoned())  # idle keep-alive, still waiting
            self.assertLess(time.monotonic() - started, 0.5)
            client_side.sendall(b'GET / HTTP/1.1\r\n')  # pipelined bytes are not a hang-up
            self.assertFalse(handler.abandoned())
            server_side.recv(64)  # the server consumes that request line
            client_side.close()
            self.assertTrue(handler.abandoned())
        finally:
            server_side.close()

    def test_range_and_market_slots_are_separate_pools(self):
        # An OI backfill must never be able to starve klines/ticker.
        self.assertIsNot(server.RANGE_SLOTS, server.MARKET_SLOTS)
        self.assertEqual(server.RANGE_SLOTS._initial_value, 16)
        self.assertEqual(server.MARKET_SLOTS._initial_value, 16)

    def test_route_is_not_an_arbitrary_forward_proxy(self):
        self.assertIsNone(server.PATTERN.fullmatch('/oi/v1/metrics/../../secret.json'))
        self.assertIsNone(server.PATTERN.fullmatch('/oi/v1/metrics/BTCUSDT/2021-12-01.json?url=https://other.example'))


if __name__ == '__main__':
    unittest.main()
