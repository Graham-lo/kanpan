import json
import unittest
from unittest.mock import patch

from okx_hub import OKXHub
from resource_limits import Capacity
from stream_hub import Peer


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


if __name__ == '__main__':
    unittest.main()
