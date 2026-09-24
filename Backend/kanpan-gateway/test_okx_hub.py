import json
import time
import unittest
from unittest.mock import patch

# The WS half of the gateway lives on aiohttp, so this module cannot even be
# imported without it. A bare ImportError here reads like "the WS tests are
# broken"; it actually means the wrong interpreter was used. Skip with the fix
# in the message instead -- and never let the suite look green when this
# happens by accident, so the reason is spelled out in full.
try:
    import aiohttp  # noqa: F401  (imported for the check, used via the modules below)
except ImportError as missing:  # pragma: no cover - depends on the interpreter
    raise unittest.SkipTest(
        '%s: run the suite with the gateway venv that has aiohttp installed '
        '(python3 -m venv .venv && .venv/bin/pip install -r requirements.txt, '
        'then .venv/bin/python -m unittest) -- see README' % missing)

from market_rest import bucket
from okx_hub import OKXHub
from resource_limits import Capacity
from stream_hub import Peer

# One closed 1m bar: 100 contracts, 1 coin, 100000 USDT.
CANDLE_AT = bucket(1_700_000_040_000, '1m')
CANDLE = [str(CANDLE_AT), '100', '110', '90', '105', '100', '1', '100000', '1']
TICKER = {'instId': 'BTC-USDT-SWAP', 'last': '100', 'open24h': '100', 'high24h': '110',
          'low24h': '90', 'volCcy24h': '12.5', 'vol24h': '4321', 'ts': '2000'}


class OKXHubTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.hub = OKXHub(capacity=Capacity(16, 1_000_000))
        self.peer = Peer(None, '192.0.2.1')
        self.hub.peers.add(self.peer)

        def instrument(symbol):
            return {'instId': symbol[:-4] + '-USDT-SWAP'}

        self.instrument_patch = patch('okx_hub.MARKET.instrument', side_effect=instrument)
        self.instrument_patch.start()

    def tearDown(self):
        self.instrument_patch.stop()

    def test_replace_accepts_ticker_and_kline_but_not_other_channels(self):
        self.assertEqual(OKXHub.channel_parts('btcusdt@ticker'), ('btcusdt', 'ticker'))
        self.assertEqual(OKXHub.channel_parts('ethusdt@kline_1m'), ('ethusdt', '1m'))
        self.assertIsNone(OKXHub.channel_parts('btcusdt@markPrice@1s'))
        self.assertTrue(self.hub.replace(self.peer, {'btcusdt@ticker', 'ethusdt@kline_1m'}))
        self.assertFalse(self.hub.replace(self.peer, {'btcusdt@bookTicker'}))
        self.assertEqual(self.peer.channels, {'btcusdt@ticker', 'ethusdt@kline_1m'})

    async def test_arguments_map_to_okx_channels(self):
        args = await self.hub.arguments({'btcusdt@ticker', 'ethusdt@kline_1m'})
        self.assertEqual(args, {('BTC-USDT-SWAP', 'tickers'), ('ETH-USDT-SWAP', 'candle1m')})

    async def test_ticker_is_normalized_to_existing_wire_format(self):
        self.assertTrue(self.hub.replace(self.peer, {'btcusdt@ticker'}))
        await self.hub.publish({
            'arg': {'instId': 'BTC-USDT-SWAP', 'channel': 'tickers'},
            'data': [{
                'instId': 'BTC-USDT-SWAP', 'last': '105', 'open24h': '100',
                'high24h': '110', 'low24h': '90', 'volCcy24h': '12.5', 'ts': '2000',
            }],
        })

        frame = json.loads(self.peer.pending.frames['btcusdt@ticker'])
        self.assertEqual(frame['source'], 'okx')
        self.assertEqual(frame['stream'], 'btcusdt@ticker')
        self.assertEqual(frame['data']['e'], '24hrTicker')
        self.assertEqual(frame['data']['s'], 'BTCUSDT')
        self.assertEqual(frame['data']['c'], '105')
        self.assertEqual(frame['data']['o'], '100')
        self.assertAlmostEqual(float(frame['data']['P']), 5.0)
        self.assertEqual(frame['data']['C'], 2000)

    async def frame(self, channel, payload):
        self.assertTrue(self.hub.replace(self.peer, {channel}))
        await self.hub.publish(payload)
        self.assertIn(channel, self.peer.pending.frames)
        return json.loads(self.peer.pending.frames[channel])

    async def ticker(self, **overrides):
        return await self.frame('btcusdt@ticker', {
            'arg': {'instId': 'BTC-USDT-SWAP', 'channel': 'tickers'},
            'data': [dict(TICKER, **overrides)]})

    async def candle(self, *rows):
        return await self.frame('btcusdt@kline_1m', {
            'arg': {'instId': 'BTC-USDT-SWAP', 'channel': 'candle1m'},
            'data': [list(row) for row in rows]})

    async def test_ticker_turnover_is_never_a_coin_count(self):
        """A-T09 (WS half): 12.5 coins at 100 each is not a turnover of 12.5."""
        data = (await self.ticker())['data']
        self.assertEqual(data['v'], '12.5')  # base coins, Binance's `v`
        self.assertFalse(data.get('q'))  # OKX publishes no 24h quote turnover
        # Not the coin count, not an estimate of it, and never the contract count.
        self.assertNotIn('1250', json.dumps(data))
        self.assertNotIn('4321', json.dumps(data))

    async def test_ticker_q_is_the_empty_string_and_never_a_zero(self):
        """A-01 sorting precondition (WS half): '' means unknown, '0' means none.

        The phone sorts non-finite turnover last. That ranking is only honest
        because this frame never claims a coin traded zero: `q` is the empty
        string, which `StreamPayload.d` turns into NaN. A '0' would decode to a
        real number and put an unknown turnover ahead of a known small one.
        """
        data = (await self.ticker())['data']
        self.assertEqual(data['q'], '')
        self.assertIsInstance(data['q'], str)
        self.assertNotEqual(data['q'], '0')
        frame = json.dumps(data, separators=(',', ':'))
        self.assertIn('"q":""', frame)
        self.assertNotIn('"q":"0"', frame)
        self.assertNotIn('"q":0', frame)

    async def test_rest_and_ws_say_the_same_thing_about_one_row(self):
        """A-T09: the two routes may not disagree about the same OKX ticker."""
        from test_market_rest import RowMarket  # same directory, same fixtures
        rest = RowMarket([dict(TICKER)]).ticker('okx', 'BTCUSDT')
        ws = (await self.ticker())['data']
        self.assertEqual(ws['v'], rest['volume'])
        # Both say "no turnover": absent or empty decodes to NaN on the phone,
        # and NaN is kept out of the money sort either way.
        self.assertFalse(ws.get('q'))
        self.assertFalse(rest['quoteVolume'])

    async def test_candle_volume_columns_keep_their_units(self):
        """A-T10 (WS half): coins in `v`, USDT in `q`, contracts nowhere."""
        k = (await self.candle(CANDLE))['data']['k']
        self.assertEqual(k['v'], '1')
        self.assertEqual(k['q'], '100000')
        self.assertNotIn('100', (k['v'], k['q']))

    async def test_confirm_becomes_closed_and_ticker_time_is_not_an_open_time(self):
        """A-T11: `confirm` 0/1 is `x`, and 2000 ms is a ticker's clock."""
        k = (await self.candle(CANDLE[:8] + ['0']))['data']['k']
        self.assertIs(k['x'], False)
        self.assertEqual(k['t'], CANDLE_AT)
        self.assertEqual(k['T'], CANDLE_AT + 59_999)
        closed = (await self.candle(CANDLE))['data']['k']
        self.assertIs(closed['x'], True)
        # The tickers channel carries its own timestamp; a candle's open time
        # comes from the candle row and nowhere else.
        ticker = await self.ticker()
        self.assertEqual((ticker['data']['E'], ticker['data']['C']), (2000, 2000))
        event = (await self.candle(CANDLE))['data']
        self.assertNotEqual(event['E'], 2000)
        self.assertLess(abs(event['E'] - int(time.time() * 1000)), 5_000)
        self.assertEqual(event['k']['t'], CANDLE_AT)

    async def test_invalid_ticker_is_not_forwarded(self):
        self.assertTrue(self.hub.replace(self.peer, {'btcusdt@ticker'}))
        await self.hub.publish({
            'arg': {'instId': 'BTC-USDT-SWAP', 'channel': 'tickers'},
            'data': [{
                'instId': 'BTC-USDT-SWAP', 'last': 'NaN', 'open24h': '100',
                'high24h': '110', 'low24h': '90', 'volCcy24h': '12.5', 'ts': '2000',
            }],
        })
        self.assertNotIn('btcusdt@ticker', self.peer.pending.frames)


class OKXOrderFlowRemovedTests(unittest.TestCase):
    """Order-flow depth and trades moved to kanpan-api's /v1/market/ws/okx relay
    (2026-09-24); the OKX substitute only carries tickers and candles."""

    def test_depth_and_trade_channels_are_refused(self):
        hub = OKXHub(capacity=Capacity(16, 1_000_000))
        peer = Peer(None, '192.0.2.1')
        hub.peers.add(peer)
        for channel in ('btcusdt@depth@100ms', 'btcusdt@aggTrade'):
            self.assertIsNone(OKXHub.channel_parts(channel))
            self.assertFalse(hub.replace(peer, {channel, 'btcusdt@ticker'}))
        self.assertFalse(hub.channels)
        self.assertEqual(OKXHub.OKX_CHANNELS, {'ticker': 'tickers'})


if __name__ == '__main__':
    unittest.main()
