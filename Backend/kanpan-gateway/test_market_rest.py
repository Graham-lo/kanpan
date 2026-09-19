import atexit
import contextlib
import email.message
import email.utils
import io
import itertools
import json
import shutil
import tempfile
import threading
import time
import unittest
from pathlib import Path
from market_rest import (BarCache, Blocked, Cooldown, PublicMarket, RateGate, RateLimited,
                         Unavailable, WARM_IDLE_SECONDS, bucket, close_time, normalize_okx,
                         retry_after_seconds, step_back)

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
        market.cooldown['binance'] = Cooldown(time.monotonic() + 60, 'blocked', 60, '451')
        # A generic fault, not 403: a WAF ban is a rate limit now (see A-T06).
        market.cooldown['okx'] = Cooldown(time.monotonic() + 10, 'unavailable', 10, '500')
        with self.assertRaises(Blocked) as caught:
            market.check_cooldown('binance')
        self.assertEqual(caught.exception.source, 'binance')
        with self.assertRaises(Unavailable) as other:
            market.check_cooldown('okx')
        self.assertNotIsInstance(other.exception, Blocked)
        self.assertNotIsInstance(other.exception, RateLimited)


class RateLimitTests(unittest.TestCase):
    """A-05: a stop condition must keep its category and its deadline."""

    TICKER = ('okx', '/api/v5/market/ticker', 'instId=BTC-USDT-SWAP')

    def test_upstream_429_carries_the_published_deadline(self):
        market, upstream = wired('okx', (429, b'{}', {'Retry-After': '120'}))
        with self.assertRaises(RateLimited) as caught:
            market.download(self.TICKER, 1)
        self.assertEqual((caught.exception.source, caught.exception.retry_after,
                          caught.exception.upstream_status), ('okx', 120, '429'))
        entry = market.cooldown['okx']
        self.assertEqual(entry.kind, 'rate_limited')
        self.assertGreater(entry.until - time.monotonic(), 110)
        # And a request that arrives later is told what is actually left, not 120.
        with self.assertRaises(RateLimited) as later:
            market.check_cooldown('okx')
        self.assertLessEqual(later.exception.retry_after, 120)
        self.assertEqual(upstream.calls, ['/api/v5/market/ticker?instId=BTC-USDT-SWAP'])

    def test_a_ban_without_a_header_gets_the_documented_minimum(self):
        # Binance publishes 2 minutes to 3 days for 418 and nothing for a bare
        # 429; guessing seconds is what kept the app hammering a banned IP.
        for status, expected in [(418, 120), (429, 10)]:
            market, _ = wired('okx', (status, b'{}', {}))
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

        market, upstream = wired('okx', refuse)
        market.gates['okx'] = gate
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
            'second', ('okx', '/api/v5/market/candles', 'instId=ETH-USDT-SWAP')))
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
        self.assertEqual(upstream.calls, ['/api/v5/market/ticker?instId=BTC-USDT-SWAP'])

    def test_okx_business_rate_limit_is_a_stop_not_an_empty_market(self):
        """A-T08: HTTP 200 with a limiter code."""
        market, upstream = wired('okx', (200, b'{"code":"50011","msg":"Too Many Requests","data":[]}', {}))
        with self.assertRaises(RateLimited) as caught:
            market.download(self.TICKER, 1)
        self.assertEqual((caught.exception.retry_after, caught.exception.upstream_status), (10, '50011'))
        self.assertEqual(market.cooldown['okx'].kind, 'rate_limited')
        self.assertEqual(len(upstream.calls), 1)

    def test_a_rejected_request_is_not_a_rate_limit_and_cools_nothing(self):
        market, _ = wired('okx', (200, b'{"code":"51001","msg":"Instrument ID does not exist"}', {}))
        with self.assertRaises(Unavailable) as caught:
            market.download(self.TICKER, 1)
        self.assertNotIsInstance(caught.exception, RateLimited)
        self.assertIn('51001', str(caught.exception))
        self.assertNotIn('okx', market.cooldown)  # one bad symbol closes nothing

    def test_a_refusal_never_reaches_a_caller_as_empty_data(self):
        market, _ = wired('okx', (200, b'{"code":"50013","msg":"System busy","data":[]}', {}))
        with self.assertRaises(RateLimited):
            market.get('okx', '/api/v5/market/ticker', {'instId': 'BTC-USDT-SWAP'})

    def test_the_longer_deadline_wins_when_two_refusals_overlap(self):
        market, _ = wired('okx')
        market.note_cooldown('okx', 'rate_limited', 120, 429)
        market.note_cooldown('okx', 'rate_limited', 5, 429)
        self.assertEqual(market.cooldown['okx'].retry_after, 120)
        market.note_cooldown('okx', 'blocked', 600, 451)
        self.assertEqual(market.cooldown['okx'].kind, 'blocked')


class RowMarket(FixtureMarket):
    """Answers every upstream call with one fixed OKX payload."""
    def __init__(self, rows):
        super().__init__([])
        self.payload = rows

    def get(self, source, path, query, ttl=1):
        self.calls.append((source, path, query.copy()))
        return self.payload


class OKXUnitTests(unittest.TestCase):
    """A-01 / B-04: which OKX column is allowed in which Binance field."""

    TICKER = {'instId': 'BTC-USDT-SWAP', 'last': '100', 'open24h': '100', 'high24h': '110',
              'low24h': '90', 'volCcy24h': '12.5', 'vol24h': '4321', 'ts': '2000'}

    def test_rest_ticker_publishes_coins_as_volume_and_no_turnover(self):
        """A-T09 (REST half): 12.5 coins at 100 is not a turnover of 12.5."""
        ticker = RowMarket([dict(self.TICKER)]).ticker('okx', 'BTCUSDT')
        self.assertEqual(ticker['volume'], '12.5')  # base coins, Binance's `volume`
        self.assertEqual(ticker['quoteVolume'], '')  # OKX has no 24h quote turnover
        # Neither the coin count nor an estimate of it may appear as money.
        self.assertNotIn('1250', json.dumps(ticker))
        self.assertNotIn('4321', json.dumps(ticker))  # vol24h is contracts, never published

    def test_quote_volume_is_the_empty_string_and_never_a_zero(self):
        """A-01 sorting precondition (REST half): '' means unknown, '0' means none.

        The phone sorts non-finite turnover last, and that is only a correct
        ranking because the gateway never claims a coin traded nothing: '' (and
        a missing key) decodes to NaN, while '0' would decode to a real zero and
        sort as a fact we do not have.
        """
        ticker = RowMarket([dict(self.TICKER)]).ticker('okx', 'BTCUSDT')
        self.assertEqual(ticker['quoteVolume'], '')
        self.assertIsInstance(ticker['quoteVolume'], str)
        self.assertNotEqual(ticker['quoteVolume'], '0')
        self.assertNotIn('"quoteVolume":0', json.dumps(ticker, separators=(',', ':')))
        self.assertIn('"quoteVolume":""', json.dumps(ticker, separators=(',', ':')))

    def test_candle_volume_columns_keep_their_units(self):
        """A-T10 (REST half): contracts, coins and USDT are three numbers."""
        at = bucket(1_700_000_040_000, '1m')
        row = normalize_okx([[str(at), '100', '110', '90', '105', '100', '1', '100000', '1']], '1m')[0]
        self.assertEqual(row[5], '1')  # volCcy: base coins, the chart's volume
        self.assertEqual(row[7], '100000')  # volCcyQuote: USDT turnover
        self.assertNotIn('100', (row[5], row[7]))  # vol (contracts) is published nowhere

    def test_instruments_label_coins_from_okx_fields_only(self):
        """B-T12: ADA is a coin because OKX's own row says so."""
        live = {'instType': 'SWAP', 'ctType': 'linear', 'settleCcy': 'USDT',
                'state': 'live', 'tickSz': '0.0001'}
        rows = [
            dict(live, instId='ADA-USDT-SWAP', uly='ADA-USDT', instFamily='ADA-USDT', ctValCcy='ADA'),
            # Same shape, but not a perpetual: nothing here proves an asset class.
            dict(live, instType='FUTURES', instId='XYZ-USDT-SWAP', uly='XYZ-USDT',
                 instFamily='XYZ-USDT', ctValCcy='XYZ'),
            # A perpetual whose underlying is not its own base currency.
            dict(live, instId='IDX-USDT-SWAP', uly='IDX-INDEX', instFamily='IDX-USDT', ctValCcy='IDX'),
            # No contract type at all: it does not even reach the catalogue.
            {'instType': 'SWAP', 'settleCcy': 'USDT', 'state': 'live', 'tickSz': '0.01',
             'instId': 'NOC-USDT-SWAP', 'uly': 'NOC-USDT', 'instFamily': 'NOC-USDT', 'ctValCcy': 'NOC'},
        ]
        info = RowMarket(rows).exchange_info('okx')
        table = {s['symbol']: s for s in info['symbols']}
        self.assertEqual(table['ADAUSDT']['underlyingType'], 'COIN')
        self.assertEqual(table['ADAUSDT']['underlyingSubType'], [])
        self.assertNotIn('underlyingType', table['XYZUSDT'])
        self.assertNotIn('underlyingType', table['IDXUSDT'])
        self.assertNotIn('NOCUSDT', table)
        self.assertEqual(table['ADAUSDT']['pricePrecision'], 4)

    def test_listing_state_travels_instead_of_being_flattened(self):
        """B-06's input: `preopen` and `suspend` are facts, not reasons to drop.

        The rows used to be filtered out and the survivors hard-written as
        TRADING, so the client's listing state machine saw nothing at all: a
        symbol waiting to list and a symbol halted for an hour both looked like a
        symbol that no longer exists.
        """
        def row(base, state):
            return {'instType': 'SWAP', 'ctType': 'linear', 'settleCcy': 'USDT',
                    'tickSz': '0.01', 'state': state, 'instId': base + '-USDT-SWAP',
                    'uly': base + '-USDT', 'instFamily': base + '-USDT', 'ctValCcy': base}

        rows = [row('BTC', 'live'), row('NEW', 'preopen'), row('HLT', 'suspend'),
                row('TST', 'test'), row('WAT', 'brand-new-okx-word')]
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            market = RowMarket(rows)
            table = {s['symbol']: s for s in market.exchange_info('okx')['symbols']}
            market.exchange_info('okx')  # the warning is printed once, not per refresh
        self.assertEqual(table['BTCUSDT']['status'], 'TRADING')
        self.assertEqual(table['NEWUSDT']['status'], 'PENDING_TRADING')  # not listed yet
        self.assertEqual(table['HLTUSDT']['status'], 'BREAK')  # halted, not delisted
        # A halted coin is still a coin, and still carries the rest of the row.
        self.assertEqual(table['HLTUSDT']['underlyingType'], 'COIN')
        self.assertEqual(table['HLTUSDT']['contractType'], 'PERPETUAL')
        self.assertNotIn('TSTUSDT', table)  # a sandbox contract is not a product
        self.assertNotIn('WATUSDT', table)  # never guess "tradable" for an unknown word
        # The chart of a halted symbol must still work, or BREAK is unreadable;
        # a symbol that has never traded is still not fetchable.
        # (RowMarket stubs `instrument`, so the real lookup is called directly.)
        self.assertEqual(PublicMarket.instrument(market, 'HLTUSDT')['instId'], 'HLT-USDT-SWAP')
        with self.assertRaises(Unavailable):
            PublicMarket.instrument(market, 'NEWUSDT')
        self.assertEqual(stderr.getvalue().count('brand-new-okx-word'), 1)
        self.assertIn('state', stderr.getvalue())
        self.assertNotIn('test', stderr.getvalue())  # dropping sandbox rows is expected


def okx_reply(payload):
    """One OKX V5 answer as it arrives on the socket."""
    body = json.dumps({'code': '0', 'msg': '', 'data': payload}, separators=(',', ':')).encode()
    return (200, body, {})


class AllMarketTickerTests(unittest.TestCase):
    """A-04: the sector page needs every symbol in one answer, in one request."""

    INSTRUMENT = {'instType': 'SWAP', 'ctType': 'linear', 'settleCcy': 'USDT', 'state': 'live',
                  'tickSz': '0.01'}
    ROW = {'instId': 'BTC-USDT-SWAP', 'last': '100', 'open24h': '80', 'high24h': '110',
           'low24h': '70', 'volCcy24h': '12.5', 'vol24h': '4321', 'ts': '2000'}
    WIRE = ['/api/v5/public/instruments?instType=SWAP', '/api/v5/market/tickers?instType=SWAP']

    def catalogue(self, *bases):
        return [dict(self.INSTRUMENT, instId=base + '-USDT-SWAP', uly=base + '-USDT',
                     instFamily=base + '-USDT', ctValCcy=base) for base in bases]

    def board(self, bases, rows):
        """A market whose only two upstream answers are the catalogue and the board.

        FakeUpstream raises on any further request, so "the cache held" and "the
        filter ran without a second round trip" are both checked by construction.
        """
        return wired('okx', okx_reply(self.catalogue(*bases)), okx_reply(list(rows)))

    def test_every_element_is_the_single_symbol_mapping(self):
        market, upstream = self.board(('BTC', 'ETH'), [self.ROW])
        answer = json.loads(market.tickers_response('okx'))
        single = json.loads(RowMarket([dict(self.ROW)]).ticker_response('okx', 'BTCUSDT'))
        # Same envelope as one symbol: same keys, same source, symbol an empty
        # string, and the payload under the very same `ticker` key.
        self.assertEqual(set(answer), set(single))
        self.assertEqual(answer['source'], 'okx')
        self.assertEqual(answer['symbol'], '')
        self.assertIsInstance(answer['ticker'], list)
        # And field by field the same mapping, not a second one that drifted.
        self.assertEqual(answer['ticker'], [single['ticker']])
        self.assertEqual(answer['ticker'][0], {
            'symbol': 'BTCUSDT', 'lastPrice': '100', 'openPrice': '80', 'highPrice': '110',
            'lowPrice': '70', 'volume': '12.5', 'quoteVolume': '',
            'priceChange': '20.0', 'priceChangePercent': '25.0', 'closeTime': 2000})
        self.assertEqual(upstream.calls, self.WIRE)

    def test_quote_volume_is_the_empty_string_on_every_element(self):
        """A-01 sorting precondition: the board is exactly where '0' would hurt."""
        market, _ = self.board(('BTC', 'ETH'), [self.ROW, dict(self.ROW, instId='ETH-USDT-SWAP')])
        payload = market.tickers_response('okx')
        for quote in json.loads(payload)['ticker']:
            self.assertEqual(quote['quoteVolume'], '')
        self.assertNotIn(b'"quoteVolume":0', payload)
        self.assertNotIn(b'"quoteVolume":"0"', payload)

    def test_contracts_outside_the_catalogue_are_filtered_out(self):
        market, upstream = self.board(('BTC', 'ETH', 'SOL'), [
            dict(self.ROW, instId='ETH-USDT-SWAP'),
            self.ROW,
            # Live on OKX, but this gateway never synthesised it into instruments.
            dict(self.ROW, instId='DOGE-USDT-SWAP'),
            dict(self.ROW, instId='BTC-USD-SWAP'),      # inverse: not this catalogue
            dict(self.ROW, instId='BTC-USDT-231229'),   # dated future
            # In the catalogue, but the row itself cannot be read. Dropping the
            # whole board over one bad contract would empty the sector page.
            {'instId': 'SOL-USDT-SWAP', 'last': 'n/a'},
            'not even an object',
        ])
        symbols = [q['symbol'] for q in json.loads(market.tickers_response('okx'))['ticker']]
        self.assertEqual(symbols, ['BTCUSDT', 'ETHUSDT'])  # sorted, so the bytes are stable
        self.assertEqual(upstream.calls, self.WIRE)

    def test_a_second_request_inside_five_seconds_never_reaches_okx(self):
        market, upstream = self.board(('BTC',), [self.ROW])
        first = market.tickers_response('okx')
        second = market.tickers_response('okx')
        self.assertEqual(first, second)
        # Three phones on the sector page cost one upstream board per 5 seconds.
        self.assertEqual(upstream.calls, self.WIRE)
        self.assertGreater(market.responses[('tickers', 'okx')][0] - time.monotonic(), 4)

    def test_a_bad_source_is_rejected_before_any_work(self):
        market, upstream = wired('okx')
        with self.assertRaises(ValueError):
            market.tickers_response('bitmex')
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
