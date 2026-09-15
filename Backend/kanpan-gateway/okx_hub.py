"""OKX USDT swap candle adapter, sharing bounded fan-out with the Binance relay."""
import asyncio
import contextlib
import json
import time
from collections import deque
from aiohttp import WSMsgType
from market_rest import MARKET, OKX_BARS, normalize_okx, Unavailable
from stream_hub import Hub


class OKXHub(Hub):
    def __init__(self, upstream='wss://ws.okx.com:8443/ws/v5/business', **kwargs):
        super().__init__(upstream=upstream, **kwargs)
        self.components = {}
        self.controls = deque()

    def replace(self, peer, desired):
        if any('@kline_' not in channel or channel.split('@kline_')[1] not in OKX_BARS for channel in desired):
            return False
        return super().replace(peer, desired)

    async def arguments(self, desired):
        args = set()
        for channel in desired:
            symbol, interval = channel.split('@kline_')
            try:
                item = await asyncio.to_thread(MARKET.instrument, symbol.upper())
            except (Unavailable, ValueError):
                continue
            args.add((item['instId'], 'candle' + OKX_BARS[interval]))
        return args

    async def sync(self, upstream):
        while True:
            await self.changed.wait(); self.changed.clear()
            await asyncio.sleep(.3)
            if not self.channels:
                await asyncio.sleep(self.idle_seconds)
                if not self.channels:
                    await upstream.close(); return
            wanted = await self.arguments(set(self.channels))
            for op, values in [('unsubscribe', self.sent - wanted), ('subscribe', wanted - self.sent)]:
                if values:
                    # Permit normal bursts; enforce the hourly budget without delaying every new chart.
                    now = time.monotonic()
                    while self.controls and self.controls[0] <= now - 3600:
                        self.controls.popleft()
                    if len(self.controls) >= 450:
                        await asyncio.sleep(max(0, self.controls[0] + 3600 - now))
                        self.changed.set()
                        break
                    self.controls.append(now)
                    await upstream.send_json({'op': op, 'args': [{'instId': i, 'channel': c} for i, c in sorted(values)]})
                    self.sent = self.sent | values if op == 'subscribe' else self.sent - values


    async def publish(self, payload):
        arg = payload.get('arg', {}); inst = arg.get('instId', '')
        parts = inst.split('-')
        if len(parts) != 3 or parts[1:] != ['USDT', 'SWAP'] or not isinstance(payload.get('data'), list):
            return
        symbol = parts[0] + 'USDT'
        for channel in tuple(self.channels):
            if not channel.startswith(symbol.lower() + '@kline_'):
                continue
            interval = channel.split('@kline_')[1]
            if arg.get('channel') != 'candle' + OKX_BARS[interval]:
                continue
            raw = payload['data']
            if interval in ('8h', '3d'):
                base = '4h' if interval == '8h' else '1d'
                saved = self.components.get(channel)
                if saved is None:
                    seed = await asyncio.to_thread(MARKET.klines, 'okx', symbol, base, 6)
                    saved = {r[0]: [str(r[0]), *r[1:5], '0', r[5], r[7], '1' if r[6] < int(time.time() * 1000) else '0'] for r in seed['bars']}
                for r in raw:
                    saved[int(r[0])] = r
                saved = {k: saved[k] for k in sorted(saved)[-6:]}
                self.components[channel] = saved
                raw = list(saved.values())
            rows = normalize_okx(raw, interval)
            received = int(time.time() * 1000)
            for row in rows[-2:]:
                confirmed = next((r[8] == '1' for r in raw if int(r[0]) == row[0]), False)
                if interval in ('8h', '3d'):
                    confirmed = row[6] < received and all(r[8] == '1' for r in raw if row[0] <= int(r[0]) <= row[6])
                data = {'e': 'kline', 'E': received, 's': symbol,
                        'k': {'t': row[0], 'T': row[6], 's': symbol, 'i': interval,
                              'o': row[1], 'h': row[2], 'l': row[3], 'c': row[4], 'v': row[5], 'x': confirmed}}
                frame = json.dumps({'stream': channel, 'source': 'okx', 'data': data}, separators=(',', ':'))
                for peer in tuple(self.channels.get(channel, ())):
                    if not peer.closing and not peer.offer(channel, frame):
                        peer.closing = True; asyncio.create_task(self.disconnect(peer, 1013))
            self.last_market = time.monotonic()
        self.components = {k: v for k, v in self.components.items() if k in self.channels}

    async def keepalive(self, upstream):
        while True:
            await asyncio.sleep(10)
            await upstream.send_str('ping')

    async def run(self):
        backoff = 1
        while not self.closed:
            if not self.channels:
                self.changed.clear(); await self.changed.wait()
                if not self.channels:
                    continue
            control = ping = None
            try:
                async with self.http.ws_connect(self.upstream_url, headers={'User-Agent': 'Kanpan-Market-Probe/1.0'}, heartbeat=20, max_msg_size=512 * 1024, compress=0) as upstream:
                    self.upstream = upstream; self.sent = set(); self.components = {}; self.controls.clear()
                    self.upstream_connections += 1; self.last_market = time.monotonic(); self.changed.set()
                    control = asyncio.create_task(self.sync(upstream)); ping = asyncio.create_task(self.keepalive(upstream))
                    async for message in upstream:
                        if message.type != WSMsgType.TEXT:
                            break
                        if message.data == 'pong':
                            continue
                        payload = json.loads(message.data)
                        if payload.get('event') == 'error':
                            raise ValueError('upstream subscription failed')
                        if payload.get('data'):
                            await self.publish(payload); backoff = 1
                        if control.done():
                            await control
            except Exception:
                pass
            finally:
                self.upstream = None
                for task in [control, ping]:
                    if task:
                        task.cancel()
                        with contextlib.suppress(asyncio.CancelledError, Exception):
                            await task
            if self.channels:
                await asyncio.sleep(backoff); backoff = min(30, backoff * 2)
