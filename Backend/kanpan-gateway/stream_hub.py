"""Shared fixed-upstream public market relay. No trading/authentication API forwarding."""
import asyncio
from collections import defaultdict
import contextlib
import ipaddress
import json
import os
import re
import time
from urllib.parse import urlencode

from aiohttp import ClientSession, ClientTimeout, WSMsgType, web
from resource_limits import Bucket, Capacity, HostSampler

UPSTREAM = 'wss://fstream.binance.com/market/stream'
STREAM = re.compile(r'(?:[a-z0-9_]{1,30}@(?:ticker|markPrice@1s|kline_(?:1m|3m|5m|15m|30m|1h|2h|4h|6h|8h|12h|1d|3d|1w|1M))|!ticker@arr)\Z')


def streams(values):
    if not isinstance(values, list) or not 0 <= len(values) <= 64 or any(not isinstance(v, str) or not STREAM.fullmatch(v) for v in values):
        raise ValueError('invalid streams')
    return set(values)


def client_key(request):
    # Listener is loopback only. Caddy MUST overwrite this header with its socket peer.
    peer = request.remote or 'unknown'
    try:
        if ipaddress.ip_address(peer).is_loopback:
            value = request.headers.get('X-Kanpan-Client-IP', peer)
            return str(ipaddress.ip_address(value))
    except ValueError:
        pass
    return peer


class Pending:
    """At most one newest unsent real frame per subscribed channel; never disk cached."""
    def __init__(self, limit=512 * 1024):
        self.frames, self.size, self.limit = {}, 0, limit

    def put(self, channel, frame):
        old = self.frames.get(channel, '')
        size = self.size - len(old) + len(frame)
        if size > self.limit:
            return False
        self.frames[channel], self.size = frame, size
        return True

    def pop(self, channel):
        frame = self.frames.pop(channel)
        self.size -= len(frame)
        return frame

    def retain(self, channels):
        for channel in list(self.frames):
            if channel not in channels:
                self.pop(channel)


class Peer:
    def __init__(self, ws, key):
        self.ws, self.key = ws, key
        self.channels = set()
        self.pending = Pending()
        self.ready = asyncio.Event()
        self.control = Bucket(4, 16)
        self.sender = None
        self.closing = False

    def offer(self, channel, frame):
        if not self.pending.put(channel, frame):
            return False
        self.ready.set()
        return True


class Hub:
    def __init__(self, upstream=UPSTREAM, capacity=None, idle_seconds=2):
        self.upstream_url = upstream  # injected only by local tests, never by client requests
        # Defaults match the widened systemd budget (MemoryMax=1G) and the
        # quadrupled connection budget in /etc/kanpan-gateway/limits.env.
        self.capacity = capacity or Capacity(int(os.environ.get('MAX_CLIENTS', '512')), int(os.environ.get('EGRESS_BYTES_PER_SECOND', '6000000')))
        self.sampler = HostSampler(int(os.environ.get('MEMORY_BUDGET_BYTES', str(1024 * 1024 * 1024))), int(os.environ.get('HOST_EGRESS_BYTES_PER_SECOND', '20000000')))
        self.idle_seconds = idle_seconds
        self.peers, self.channels = set(), defaultdict(set)
        self.identities = {}
        self.attempts = {}
        self.global_bytes = Bucket(self.capacity.bytes_per_second, self.capacity.bytes_per_second)
        self.changed = asyncio.Event()
        self.upstream = self.worker = self.monitor = self.http = None
        self.sent = set()
        self.last_market = 0
        self.closed = False
        self.upstream_connections = 0

    async def start(self):
        self.http = ClientSession(timeout=ClientTimeout(total=None, sock_connect=5), trust_env=False)
        self.worker = asyncio.create_task(self.run())
        self.monitor = asyncio.create_task(self.observe())

    async def close(self):
        self.closed = True
        for peer in list(self.peers):
            await self.disconnect(peer, 1001)
        for task in [self.worker, self.monitor]:
            if task:
                task.cancel()
        for task in [self.worker, self.monitor]:
            if task:
                with contextlib.suppress(asyncio.CancelledError):
                    await task
        if self.http:
            await self.http.close()

    def admit(self, key):
        now = time.monotonic()
        if key not in self.attempts:
            self.attempts = {k: value for k, value in self.attempts.items() if now - value.at < 120}
            if len(self.attempts) >= 2048:
                return False
            self.attempts[key] = Bucket(.5, 12)
        if not self.attempts[key].take(now=now):
            return False
        count = sum(p.key == key for p in self.peers)
        return len(self.peers) < self.capacity.clients and count < min(12, max(2, self.capacity.clients // 4))

    def replace(self, peer, desired):
        if len(desired) > 64:
            return False
        others = set().union(*(p.channels for p in self.peers if p is not peer)) if self.peers else set()
        same_ip = set().union(*(p.channels for p in self.peers if p is not peer and p.key == peer.key)) if self.peers else set()
        if len(others | desired) > 512 or len(same_ip | desired) > 160:
            return False
        for channel in peer.channels - desired:
            self.channels[channel].discard(peer)
            if not self.channels[channel]:
                del self.channels[channel]
        for channel in desired - peer.channels:
            self.channels[channel].add(peer)
        peer.channels = set(desired)
        peer.pending.retain(desired)
        self.changed.set()
        return True

    async def disconnect(self, peer, code=1000):
        if peer not in self.peers:
            return
        self.replace(peer, set())
        self.peers.discard(peer)
        if not any(p.key == peer.key for p in self.peers):
            self.identities.pop(peer.key, None)
        if peer.sender and peer.sender is not asyncio.current_task():
            peer.sender.cancel()
        with contextlib.suppress(Exception):
            await asyncio.wait_for(peer.ws.close(code=code), 1)

    async def websocket(self, request):
        key = client_key(request)
        try:
            if len(request.query_string) > 4096 or set(request.query) - {'streams'}:
                raise ValueError()
            initial = streams(request.query.get('streams', '').split('/') if request.query.get('streams') else [])
        except ValueError:
            raise web.HTTPBadRequest()
        if not self.admit(key):
            raise web.HTTPServiceUnavailable(headers={'Retry-After': '5'})
        ws = web.WebSocketResponse(heartbeat=20, max_msg_size=8192, compress=False)
        peer = Peer(ws, key)
        # Reserve before upgrade awaits; parallel handshakes cannot bypass caps.
        self.peers.add(peer)
        if not self.replace(peer, initial):
            self.peers.discard(peer)
            raise web.HTTPTooManyRequests(headers={'Retry-After': '5'})
        self.identities.setdefault(key, [Bucket(16, 64), Bucket(self.capacity.bytes_per_second, 512 * 1024)])
        try:
            await ws.prepare(request)
            peer.sender = asyncio.create_task(self.send(peer))
            async for message in ws:
                if message.type != WSMsgType.TEXT:
                    break
                if not peer.control.take() or not self.identities[key][0].take():
                    await ws.close(code=1008, message=b'control rate exceeded')
                    break
                try:
                    command = json.loads(message.data)
                    if not isinstance(command, dict) or set(command) - {'method', 'params', 'id'}:
                        raise ValueError()
                    method = command.get('method')
                    values = streams(command.get('params'))
                    if method not in ['SUBSCRIBE', 'UNSUBSCRIBE']:
                        raise ValueError()
                    desired = peer.channels | values if method == 'SUBSCRIBE' else peer.channels - values
                    if not self.replace(peer, desired):
                        raise ValueError()
                    identity = command.get('id')
                    if not isinstance(identity, int) or not 0 <= identity <= 2**53:
                        raise ValueError()
                    await asyncio.wait_for(ws.send_json({'result': None, 'id': identity}), 1)
                except (ValueError, TypeError, asyncio.TimeoutError):
                    await ws.close(code=1008, message=b'invalid subscription')
                    break
        finally:
            await self.disconnect(peer)
        return ws

    async def send(self, peer):
        blocked_since = None
        try:
            while not peer.ws.closed:
                await peer.ready.wait()
                peer.ready.clear()
                for channel in list(peer.pending.frames):
                    frame = peer.pending.frames.get(channel)
                    if frame is None:
                        continue
                    budget = self.identities[peer.key][1]
                    rate = min(500_000, max(8000, self.capacity.bytes_per_second / max(1, len(self.identities))))
                    budget.rate, budget.burst = rate, max(256 * 1024, rate)
                    self.global_bytes.rate = self.capacity.bytes_per_second
                    self.global_bytes.burst = self.capacity.bytes_per_second
                    now = time.monotonic()
                    if not budget.take(len(frame), now) or not self.global_bytes.take(len(frame), now):
                        blocked_since = blocked_since or now
                        if now - blocked_since > 8:
                            await self.disconnect(peer, 1013)
                            return
                        peer.ready.set()
                        await asyncio.sleep(.05)
                        break
                    frame = peer.pending.pop(channel)
                    await asyncio.wait_for(peer.ws.send_str(frame), 1)
                    blocked_since = None
        except (asyncio.TimeoutError, ConnectionError, RuntimeError):
            await self.disconnect(peer, 1013)
        except asyncio.CancelledError:
            pass

    async def sync(self, upstream):
        identity = 0
        last_control = 0.0
        while True:
            await self.changed.wait()
            self.changed.clear()
            # The first change after a quiet second is the cold-start critical
            # path and has nothing to coalesce; only back-to-back changes back
            # off to .3 so rapid chart switching stays <= ~3 control frames/s.
            pause = .03 if time.monotonic() - last_control > 1 else .3
            await asyncio.sleep(pause)
            wanted = set(self.channels)
            if not wanted:
                await asyncio.sleep(self.idle_seconds)
                if not self.channels:
                    await upstream.close()
                    return
                wanted = set(self.channels)
            removed, added = self.sent - wanted, wanted - self.sent
            for method, values in [('UNSUBSCRIBE', removed), ('SUBSCRIBE', added)]:
                if values:
                    identity += 1
                    await upstream.send_json({'method': method, 'params': sorted(values), 'id': identity})
                    last_control = time.monotonic()
                    if method == 'SUBSCRIBE':
                        self.sent |= values
                    else:
                        self.sent -= values
                    await asyncio.sleep(pause)

    async def run(self):
        backoff = 1
        while not self.closed:
            if not self.channels:
                self.changed.clear()
                await self.changed.wait()
                if not self.channels:
                    continue
            sync = None
            try:
                initial = set(self.channels)
                url = self.upstream_url + '?' + urlencode({'streams': '/'.join(sorted(initial))})
                async with self.http.ws_connect(url, heartbeat=20, max_msg_size=2 * 1024 * 1024, compress=0) as upstream:
                    self.upstream, self.sent = upstream, initial
                    self.upstream_connections += 1
                    self.last_market = time.monotonic()
                    self.changed.set()
                    sync = asyncio.create_task(self.sync(upstream))
                    async for message in upstream:
                        if message.type != WSMsgType.TEXT:
                            break
                        try:
                            payload = json.loads(message.data)
                            channel = payload.get('stream')
                            data = payload.get('data')
                            if channel not in self.channels or not data:
                                continue
                            if not isinstance(data, (dict, list)):
                                continue
                        except (ValueError, AttributeError):
                            continue
                        self.last_market = time.monotonic()
                        backoff = 1
                        for peer in tuple(self.channels.get(channel, ())):
                            if not peer.closing and not peer.offer(channel, message.data):
                                peer.closing = True
                                asyncio.create_task(self.disconnect(peer, 1013))
            except (Exception,):
                pass  # no payload/user/IP logging; retry bounded below
            finally:
                self.upstream = None
                if sync:
                    sync.cancel()
                    with contextlib.suppress(asyncio.CancelledError, Exception):
                        await sync
            if self.channels:
                await asyncio.sleep(backoff)
                backoff = min(30, backoff * 2)

    async def observe(self):
        while True:
            await asyncio.sleep(5)
            self.capacity.update(**self.sampler.sample())
            if self.upstream and self.channels and time.monotonic() - self.last_market > 15:
                await self.upstream.close()

    async def health(self, _request):
        return web.json_response({'status': 'ok', 'service': 'kanpan-stream-hub', 'clients': len(self.peers),
                                  'channels': len(self.channels), 'capacity': self.capacity.clients,
                                  'upstreamConnected': self.upstream is not None})


def app_for(hub, okx=None):
    app = web.Application(client_max_size=8192)
    app.router.add_get('/market/stream', hub.websocket)
    app.router.add_get('/chart-gateway/stream-health', hub.health)
    if okx:
        app.router.add_get('/market/okx/stream', okx.websocket)
    async def start(_):
        await hub.start()
        if okx: await okx.start()
    async def close(_):
        await hub.close()
        if okx: await okx.close()
    app.on_startup.append(start)
    app.on_cleanup.append(close)
    return app


if __name__ == '__main__':
    from okx_hub import OKXHub
    web.run_app(app_for(Hub(), OKXHub()), host='127.0.0.1', port=int(os.environ.get('STREAM_PORT', '8793')), access_log=None, print=None)
