import asyncio
import json
import time
import unittest

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

from aiohttp import ClientSession, WSServerHandshakeError, WSMsgType, web
from stream_hub import Hub, Peer, Pending, app_for, streams, client_key
from types import SimpleNamespace
from resource_limits import Bucket, Capacity, HTTPGuard


class BudgetTests(unittest.TestCase):
    def test_bucket_and_dynamic_capacity(self):
        bucket = Bucket(2, 4, 0)
        self.assertTrue(bucket.take(4, 0))
        self.assertFalse(bucket.take(1, 0))
        self.assertTrue(bucket.take(2, 1))
        cap = Capacity(128, 1_500_000)
        cap.update(cpu=.98)
        self.assertAlmostEqual(cap.scale, .8)
        for _ in range(6): cap.update(memory_available=.01)
        self.assertEqual(cap.clients, 25)
        cap.update()
        self.assertAlmostEqual(cap.scale, .25)  # recover slowly, no capacity oscillation

    def test_latest_pending_bounded(self):
        pending = Pending(20)
        self.assertTrue(pending.put('btc', 'first'))
        self.assertTrue(pending.put('btc', 'new'))
        self.assertEqual(pending.size, 3)
        self.assertFalse(pending.put('eth', 'x' * 20))
        self.assertEqual(pending.pop('btc'), 'new')
        self.assertEqual(pending.size, 0)

    def test_stream_validation(self):
        self.assertEqual(streams(['btcusdt@ticker', 'btcusdt@ticker']), {'btcusdt@ticker'})
        for value in [['https://example.com'], ['../secret'], ['btcusdt@trade'], ['btcusdt@kline_1y'], ['x'] * 65]:
            with self.assertRaises(ValueError): streams(value)

    def test_public_peer_cannot_spoof_forwarded_identity(self):
        request = SimpleNamespace(remote='192.0.2.1', headers={'X-Kanpan-Client-IP': '192.0.2.2'})
        self.assertEqual(client_key(request), '192.0.2.1')

    def test_http_isolation_and_key_limit(self):
        guard = HTTPGuard(limit=2, concurrency=2)
        self.assertTrue(guard.enter('a', 0)); self.assertTrue(guard.enter('a', 0))
        self.assertFalse(guard.enter('a', 0))
        self.assertTrue(guard.enter('b', 0))
        self.assertFalse(guard.enter('c', 0))
        guard.leave('a'); guard.leave('a'); guard.leave('b')
        self.assertTrue(guard.enter('c', 121))

    def test_default_budget_fits_one_app_opening_many_panels(self):
        guard = HTTPGuard()
        self.assertEqual((guard.concurrency, guard.rate, guard.burst), (12, 10, 40))
        # An archive backfill alone runs eight parallel requests; the old
        # per-IP limit of two throttled a single legitimate phone.
        for _ in range(12):
            self.assertTrue(guard.enter('a', 0))
        self.assertFalse(guard.enter('a', 0))  # the runaway-client floor still holds

    def test_upstream_block_does_not_spend_the_callers_quota(self):
        guard = HTTPGuard(concurrency=2, rate=1, burst=1)
        self.assertTrue(guard.enter('a', 0))
        guard.leave('a', refund=True)  # a 451 is the exchange's answer, not a mistake
        self.assertTrue(guard.enter('a', 0))
        guard.leave('a')
        self.assertFalse(guard.enter('a', 0))


class SharedHubTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.connections = 0
        self.remote_channels = set()
        self.controls = []
        async def source(request):
            self.connections += 1
            active = set(request.query['streams'].split('/'))
            self.remote_channels = active
            ws = web.WebSocketResponse()
            await ws.prepare(request)
            async def emit():
                count = 0
                while True:
                    count += 1
                    for channel in list(active):
                        await ws.send_json({'stream': channel, 'data': {'e': '24hrTicker', 's': 'BTCUSDT', 'c': str(count)}})
                    await asyncio.sleep(.02)
            sender = asyncio.create_task(emit())
            try:
                async for msg in ws:
                    if msg.type == WSMsgType.TEXT:
                        obj = json.loads(msg.data); self.controls.append(obj)
                        if obj['method'] == 'SUBSCRIBE': active.update(obj['params'])
                        else: active.difference_update(obj['params'])
            finally:
                sender.cancel()
            return ws
        source_app = web.Application(); source_app.router.add_get('/market/stream', source)
        self.source_runner = web.AppRunner(source_app); await self.source_runner.setup()
        site = web.TCPSite(self.source_runner, '127.0.0.1', 0); await site.start()
        port = site._server.sockets[0].getsockname()[1]
        self.source_port = port
        # No resident channel and no hold here: these cases are about what
        # clients ask for, one release at a time.
        self.hub = Hub(f'http://127.0.0.1:{port}/market/stream', capacity=Capacity(128, 4_000_000),
                       idle_seconds=.05, resident=(), linger_seconds=0)
        self.runner = web.AppRunner(app_for(self.hub)); await self.runner.setup()
        site = web.TCPSite(self.runner, '127.0.0.1', 0); await site.start()
        self.url = f'http://127.0.0.1:{site._server.sockets[0].getsockname()[1]}/market/stream'
        self.http = ClientSession()
        self.extra = []

    async def asyncTearDown(self):
        # Extra hubs go first: a hub still holding a socket to the fake exchange
        # makes that server's cleanup sit out its full shutdown timeout.
        for hub in self.extra:
            await hub.close()
        await self.http.close(); await self.runner.cleanup(); await self.source_runner.cleanup()

    async def connect(self, key='192.0.2.1', channel='btcusdt@ticker'):
        return await self.http.ws_connect(self.url, params={'streams': channel}, headers={'X-Kanpan-Client-IP': key})

    async def frame(self, ws):
        while True:
            obj = await asyncio.wait_for(ws.receive_json(), 3)
            if 'stream' in obj: return obj

    async def test_shared_upstream_and_unsubscribe_reference(self):
        a = await self.connect(); b = await self.connect()
        await self.frame(a); await self.frame(b)
        self.assertEqual(self.connections, 1)
        self.assertEqual(len(self.hub.channels['btcusdt@ticker']), 2)
        await a.send_json({'method': 'UNSUBSCRIBE', 'params': ['btcusdt@ticker'], 'id': 1})
        await asyncio.sleep(.4)
        self.assertEqual(self.hub.sent, {'btcusdt@ticker'})
        self.assertEqual((await self.frame(b))['stream'], 'btcusdt@ticker')
        await a.close(); await b.close()
        await asyncio.sleep(.5)
        self.assertFalse(self.hub.channels)
        self.assertIsNone(self.hub.upstream)

    async def test_first_change_after_a_quiet_period_is_not_debounced(self):
        a = await self.connect()
        await self.frame(a)
        await asyncio.sleep(1.1)  # go quiet, so the next change is a cold start
        started = time.monotonic()
        b = await self.connect('192.0.2.3', 'ethusdt@ticker')
        while 'ethusdt@ticker' not in self.hub.sent:
            await asyncio.sleep(.005)
            if time.monotonic() - started > 3:
                self.fail('subscribe never reached upstream')
        # The old sync() slept .3s before every control frame, including the
        # cold-start one that has nothing to coalesce with.
        self.assertLess(time.monotonic() - started, .25)
        await a.close(); await b.close()

    async def test_single_source_cannot_fill_node(self):
        sockets = [await self.connect() for _ in range(12)]
        with self.assertRaises(WSServerHandshakeError) as error:
            await self.connect()
        self.assertEqual(error.exception.status, 503)
        other = await self.connect('192.0.2.2')
        self.assertIn('stream', await self.frame(other))
        for socket in sockets + [other]: await socket.close()

    async def test_invalid_control_closes_only_offender(self):
        a = await self.connect(); b = await self.connect('192.0.2.2')
        await self.frame(a); await self.frame(b)
        await a.send_json({'method': 'SUBSCRIBE', 'params': ['http://evil.test'], 'id': 1})
        for _ in range(100):
            if (await a.receive()).type in [WSMsgType.CLOSE, WSMsgType.CLOSED]: break
        self.assertEqual(a.close_code, 1008)
        self.assertIn('stream', await self.frame(b))
        await b.close()

    async def test_source_subscription_cap(self):
        peers = [Peer(None, 'a') for _ in range(3)]
        self.hub.peers.update(peers)
        try:
            for i, peer in enumerate(peers[:2]):
                self.assertTrue(self.hub.replace(peer, {f's{i}_{j}@ticker' for j in range(64)}))
            self.assertFalse(self.hub.replace(peers[2], {f'extra{j}@ticker' for j in range(64)}))
            self.assertFalse(peers[2].channels)
        finally:
            for peer in peers:
                self.hub.replace(peer, set()); self.hub.peers.remove(peer)

    async def test_control_flood_isolated(self):
        bad = await self.connect(); good = await self.connect('192.0.2.2')
        await self.frame(bad); await self.frame(good)
        for i in range(30):
            await bad.send_json({'method': 'SUBSCRIBE', 'params': ['btcusdt@ticker'], 'id': i})
        for _ in range(100):
            if (await bad.receive()).type in [WSMsgType.CLOSE, WSMsgType.CLOSED]: break
        self.assertEqual(bad.close_code, 1008)
        self.assertIn('stream', await self.frame(good))
        await good.close()

    async def test_stalled_sender_releases_only_itself(self):
        class Stalled:
            closed = False
            async def send_str(self, _): await asyncio.sleep(20)
            async def close(self, **_): self.closed = True
        peer = Peer(Stalled(), 'stalled')
        self.hub.peers.add(peer)
        self.hub.identities[peer.key] = [Bucket(16, 64), Bucket(500_000, 500_000)]
        peer.offer('btcusdt@ticker', '{}')
        await asyncio.wait_for(self.hub.send(peer), 2)
        self.assertNotIn(peer, self.hub.peers)
        self.assertTrue(peer.ws.closed)

    async def test_resident_channel_keeps_the_upstream_warm_with_no_clients(self):
        hub = Hub(self.hub.upstream_url, capacity=Capacity(8, 1_000_000), idle_seconds=.05,
                  resident={'btcusdt@kline_1m'})
        await hub.start()
        try:
            for _ in range(300):
                if hub.upstream is not None and hub.sent:
                    break
                await asyncio.sleep(.01)
            # Subscribed before the first phone arrives: that is the whole point.
            self.assertEqual(hub.sent, {'btcusdt@kline_1m'})
            self.assertFalse(hub.channels)
            stalled = hub.last_market
            await asyncio.sleep(.3)
            self.assertIsNotNone(hub.upstream)  # the old idle release let this go
            # Resident frames feed the stall watchdog, so a warm socket that went
            # quiet is still detectable with nobody watching.
            self.assertGreater(hub.last_market, stalled)
        finally:
            await hub.close()

    async def test_idle_hold_does_not_delay_the_next_client(self):
        slow = Hub(self.hub.upstream_url, capacity=Capacity(8, 1_000_000), idle_seconds=5, resident=())
        await slow.start()
        try:
            peer = Peer(None, 'a')
            slow.peers.add(peer)
            slow.replace(peer, {'btcusdt@ticker'})
            for _ in range(300):
                if 'btcusdt@ticker' in slow.sent:
                    break
                await asyncio.sleep(.01)
            slow.replace(peer, set())  # everyone leaves: the idle hold starts
            await asyncio.sleep(.2)
            started = time.monotonic()
            slow.replace(peer, {'ethusdt@ticker'})
            while 'ethusdt@ticker' not in slow.sent:
                await asyncio.sleep(.005)
                if time.monotonic() - started > 3:
                    self.fail('a client arriving during the idle hold waited for the clock')
            self.assertLess(time.monotonic() - started, 1)  # not the 5s hold
        finally:
            slow.peers.discard(peer)
            await slow.close()

    async def held(self, linger, resident=()):
        hub = Hub(self.hub.upstream_url, capacity=Capacity(8, 1_000_000), idle_seconds=.05,
                  resident=resident, linger_seconds=linger)
        await hub.start()
        self.extra.append(hub)
        return hub

    async def subscribed(self, hub, peer, channels):
        hub.replace(peer, channels)
        started = time.monotonic()
        while not channels <= hub.sent:
            await asyncio.sleep(.005)
            if time.monotonic() - started > 3:
                self.fail(f'{channels} never reached upstream')

    async def test_a_channel_is_held_upstream_after_its_last_client_leaves(self):
        hub = await self.held(5)
        peer = Peer(None, 'a')
        hub.peers.add(peer)
        self.addCleanup(hub.peers.discard, peer)
        await self.subscribed(hub, peer, {'btcusdt@ticker'})
        control = len(self.controls)
        hub.replace(peer, set())
        await asyncio.sleep(.5)
        # Still subscribed: the exchange needs about .8s to start a channel, and
        # a phone flipping symbols comes back long before that is worth paying twice.
        self.assertIn('btcusdt@ticker', hub.sent)
        self.assertFalse(hub.channels)
        self.assertEqual(hub.lingering(), {'btcusdt@ticker'})
        await self.subscribed(hub, peer, {'btcusdt@ticker'})
        self.assertFalse(hub.linger)
        self.assertEqual(len(self.controls), control)  # nothing was re-sent upstream

    async def test_a_hold_that_runs_out_releases_the_channel(self):
        # With a resident channel the socket outlives the hold, so the release
        # has to be a real UNSUBSCRIBE rather than the connection going away.
        hub = await self.held(.3, resident={'btcusdt@kline_1m'})
        peer = Peer(None, 'a')
        hub.peers.add(peer)
        self.addCleanup(hub.peers.discard, peer)
        await self.subscribed(hub, peer, {'btcusdt@ticker'})
        hub.replace(peer, set())
        started = time.monotonic()
        while 'btcusdt@ticker' in hub.sent:
            await asyncio.sleep(.01)
            if time.monotonic() - started > 3:
                self.fail('an expired hold was never released')
        self.assertGreater(time.monotonic() - started, .2)  # and not before it expired

    async def test_holds_cannot_grow_without_bound(self):
        hub = await self.held(60)
        hub.park({f'h{i}@ticker' for i in range(200)})
        self.assertEqual(len(hub.linger), 48)

    async def test_one_hundred_clients_share_one_upstream(self):
        clients = [await self.connect(f'192.0.2.{i // 10 + 1}') for i in range(100)]
        await asyncio.gather(*(self.frame(ws) for ws in clients))
        self.assertEqual(self.connections, 1)
        self.assertEqual(len(self.hub.peers), 100)
        self.assertEqual(len(self.hub.channels), 1)
        await asyncio.gather(*(ws.close() for ws in clients))


DEPTH = 'btcusdt@depth@100ms'


class DepthPendingTests(unittest.TestCase):
    def test_depth_frames_queue_in_order_while_tickers_still_coalesce(self):
        pending = Pending(12)
        for frame in ['a1', 'a2', 'a3']:
            self.assertTrue(pending.put(DEPTH, frame))
        self.assertTrue(pending.put('btcusdt@ticker', 'old'))
        self.assertTrue(pending.put('btcusdt@ticker', 'new'))
        self.assertEqual(pending.size, 9)
        self.assertFalse(pending.put(DEPTH, 'toolong'))  # the per-peer byte cap still holds
        self.assertEqual(sorted(pending.waiting()), [DEPTH, 'btcusdt@ticker'])
        self.assertEqual([pending.pop(DEPTH) for _ in range(2)], ['a1', 'a2'])
        self.assertEqual(pending.peek(DEPTH), 'a3')
        pending.put(DEPTH, 'a4')
        pending.retain({'btcusdt@ticker'})  # unsubscribing drops the whole queue
        self.assertEqual(pending.waiting(), ['btcusdt@ticker'])
        self.assertEqual(pending.pop('btcusdt@ticker'), 'new')
        self.assertEqual(pending.size, 0)

    def test_only_the_100ms_diff_stream_is_admitted(self):
        self.assertEqual(streams([DEPTH]), {DEPTH})
        for value in ['btcusdt@depth', 'btcusdt@depth@500ms', 'btcusdt@depth20@100ms', '@depth@100ms']:
            with self.assertRaises(ValueError):
                streams([value])


class DepthLaneTests(unittest.IsolatedAsyncioTestCase):
    """Depth rides Binance's /public socket, frame by frame; tickers stay on /market."""

    async def asyncSetUp(self):
        self.seen = {'market': set(), 'public': set()}
        self.connections = {'market': 0, 'public': 0}
        self.live = {'market': 0, 'public': 0}

        def source(name, frame):
            async def handler(request):
                self.connections[name] += 1
                self.live[name] += 1
                active = set(filter(None, request.query['streams'].split('/')))
                self.seen[name] |= active
                ws = web.WebSocketResponse()
                await ws.prepare(request)

                async def emit():
                    # Depth comes in bursts of back-to-back frames, the way a busy
                    # book does, so frames really pile up in a peer's Pending.
                    count, burst = 0, 25 if name == 'public' else 1
                    while True:
                        for _ in range(burst):
                            count += 1
                            for channel in list(active):
                                await ws.send_json({'stream': channel, 'data': frame(count)})
                        await asyncio.sleep(.01 if name == 'public' else .02)
                sender = asyncio.create_task(emit())
                try:
                    async for msg in ws:
                        if msg.type == WSMsgType.TEXT:
                            obj = json.loads(msg.data)
                            self.seen[name] |= set(obj['params'])
                            if obj['method'] == 'SUBSCRIBE':
                                active.update(obj['params'])
                            else:
                                active.difference_update(obj['params'])
                finally:
                    sender.cancel()
                    self.live[name] -= 1
                return ws
            return handler

        app = web.Application()
        app.router.add_get('/market/stream', source('market', lambda n: {'e': '24hrTicker', 'c': str(n)}))
        app.router.add_get('/public/stream', source('public', lambda n: {
            'e': 'depthUpdate', 'U': n * 10 + 1, 'u': (n + 1) * 10, 'pu': n * 10,
            'b': [['100.0', str(n)]], 'a': []}))
        self.source_runner = web.AppRunner(app)
        await self.source_runner.setup()
        site = web.TCPSite(self.source_runner, '127.0.0.1', 0)
        await site.start()
        base = f'http://127.0.0.1:{site._server.sockets[0].getsockname()[1]}'
        self.hub = Hub(base + '/market/stream', public_upstream=base + '/public/stream',
                       capacity=Capacity(128, 4_000_000), idle_seconds=.05, resident=(), linger_seconds=0)
        self.runner = web.AppRunner(app_for(self.hub))
        await self.runner.setup()
        site = web.TCPSite(self.runner, '127.0.0.1', 0)
        await site.start()
        self.url = f'http://127.0.0.1:{site._server.sockets[0].getsockname()[1]}/market/stream'
        self.http = ClientSession()

    async def asyncTearDown(self):
        await self.http.close()
        await self.runner.cleanup()
        await self.source_runner.cleanup()

    async def frames(self, ws, channel, count):
        found = []
        while len(found) < count:
            obj = await asyncio.wait_for(ws.receive_json(), 3)
            if obj.get('stream') == channel:
                found.append(obj['data'])
        return found

    async def test_every_diff_arrives_in_order_and_only_on_the_public_socket(self):
        ws = await self.http.ws_connect(self.url, params={'streams': 'btcusdt@ticker/' + DEPTH})
        diffs = await self.frames(ws, DEPTH, 300)  # sent 1ms apart: coalescing would leave gaps
        for before, after in zip(diffs, diffs[1:]):
            self.assertEqual(after['pu'], before['u'])
        self.assertEqual(diffs[0]['e'], 'depthUpdate')
        self.assertTrue(await self.frames(ws, 'btcusdt@ticker', 1))
        self.assertEqual(self.seen, {'market': {'btcusdt@ticker'}, 'public': {DEPTH}})
        self.assertEqual(self.connections, {'market': 1, 'public': 1})
        await ws.close()

    async def test_the_public_socket_opens_on_demand_and_closes_when_released(self):
        ws = await self.http.ws_connect(self.url, params={'streams': 'btcusdt@ticker'})
        await self.frames(ws, 'btcusdt@ticker', 1)
        self.assertEqual(self.connections['public'], 0)
        await ws.send_json({'method': 'SUBSCRIBE', 'params': [DEPTH], 'id': 1})
        await self.frames(ws, DEPTH, 5)
        await ws.send_json({'method': 'UNSUBSCRIBE', 'params': [DEPTH], 'id': 2})
        for _ in range(100):
            if self.live['public'] == 0 and self.hub.public.upstream is None:
                break
            await asyncio.sleep(.02)
        self.assertEqual(self.live['public'], 0)
        self.assertIsNotNone(self.hub.upstream)  # the ticker socket is untouched
        self.assertNotIn(DEPTH, self.seen['market'])
        await self.frames(ws, 'btcusdt@ticker', 1)
        await ws.close()
