"""OKX USDT swap market adapter, sharing bounded fan-out with the Binance relay."""
import asyncio
import contextlib
import json
import math
import time
from collections import deque
from aiohttp import WSMsgType
from market_rest import MARKET, OKX_BARS, normalize_okx, Unavailable
from stream_hub import Hub


class OKXHub(Hub):
    # OKX tickers live on the public endpoint while candle channels live on the
    # business endpoint. Keep one client-facing hub, but use one bounded
    # upstream connection for each channel family.
    def __init__(self,
                 upstream='wss://ws.okx.com:8443/ws/v5/public',
                 candle_upstream='wss://ws.okx.com:8443/ws/v5/business', **kwargs):
        super().__init__(upstream=upstream, **kwargs)
        self.candle_upstream_url = candle_upstream
        self.components = {}
        self.controls = deque()
        self.kind_changed = {'ticker': asyncio.Event(), 'kline': asyncio.Event()}
        self.upstreams = set()

    def update_upstream_indicator(self):
        # Hub.observe() and the inherited health handler use this single
        # indicator; keep it representative while two family-specific sockets
        # are active.
        self.upstream = next(iter(self.upstreams), None)

    @staticmethod
    def channel_parts(channel):
        """Return (binance-style symbol, kind) for a validated client channel."""
        if channel.endswith('@ticker'):
            symbol = channel[:-len('@ticker')]
            return (symbol, 'ticker') if symbol else None
        prefix, separator, interval = channel.partition('@kline_')
        if separator and prefix and interval in OKX_BARS:
            return prefix, interval
        return None

    def replace(self, peer, desired):
        if any(self.channel_parts(channel) is None for channel in desired):
            return False
        accepted = super().replace(peer, desired)
        if accepted:
            self.kind_changed['ticker'].set()
            self.kind_changed['kline'].set()
        return accepted

    async def arguments(self, desired):
        args = set()
        for channel in desired:
            parts = self.channel_parts(channel)
            if parts is None:
                continue
            symbol, kind = parts
            try:
                item = await asyncio.to_thread(MARKET.instrument, symbol.upper())
            except (Unavailable, ValueError):
                continue
            args.add((item['instId'], 'tickers' if kind == 'ticker' else 'candle' + OKX_BARS[kind]))
        return args

    async def sync(self, upstream, family, sent, changed):
        while True:
            await changed.wait(); changed.clear()
            # The first subscription is the cold-start critical path. There
            # is nothing to coalesce before the first send; keep only a tiny
            # yield there and retain the debounce for rapid chart switches.
            await asyncio.sleep(.03 if not sent else .3)
            wanted_channels = {channel for channel in self.channels
                               if (self.channel_parts(channel)[1] == 'ticker') == (family == 'ticker')}
            if not wanted_channels:
                await asyncio.sleep(self.idle_seconds)
                if not any((self.channel_parts(channel)[1] == 'ticker') == (family == 'ticker')
                           for channel in self.channels):
                    await upstream.close(); return
                changed.set()
                continue
            wanted = await self.arguments(wanted_channels)
            for op, values in [('unsubscribe', sent - wanted), ('subscribe', wanted - sent)]:
                if values:
                    # Permit normal bursts; enforce the hourly budget without delaying every new chart.
                    now = time.monotonic()
                    while self.controls and self.controls[0] <= now - 3600:
                        self.controls.popleft()
                    if len(self.controls) >= 450:
                        await asyncio.sleep(max(0, self.controls[0] + 3600 - now))
                        changed.set()
                        break
                    self.controls.append(now)
                    await upstream.send_json({'op': op, 'args': [{'instId': i, 'channel': c} for i, c in sorted(values)]})
                    sent.update(values) if op == 'subscribe' else sent.difference_update(values)


    async def publish(self, payload):
        arg = payload.get('arg', {}); inst = arg.get('instId', '')
        parts = inst.split('-')
        if len(parts) != 3 or parts[1:] != ['USDT', 'SWAP'] or not isinstance(payload.get('data'), list):
            return
        symbol = parts[0] + 'USDT'
        for channel in tuple(self.channels):
            parts = self.channel_parts(channel)
            if parts is None or parts[0] != symbol.lower():
                continue
            _, kind = parts
            if kind == 'ticker':
                if arg.get('channel') != 'tickers':
                    continue
                for row in payload['data']:
                    if not isinstance(row, dict) or row.get('instId') != inst:
                        continue
                    frame = self.ticker_frame(channel, symbol, row)
                    if frame is None:
                        continue
                    for peer in tuple(self.channels.get(channel, ())):
                        if not peer.closing and not peer.offer(channel, frame):
                            peer.closing = True; asyncio.create_task(self.disconnect(peer, 1013))
                    self.last_market = time.monotonic()
                continue
            interval = kind
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

    @staticmethod
    def ticker_frame(channel, symbol, row):
        """Adapt one OKX `tickers` row to the existing Binance ticker envelope."""
        try:
            last = float(row['last'])
            opened = float(row['open24h'])
            high = float(row['high24h'])
            low = float(row['low24h'])
            volume = float(row['volCcy24h'])
            timestamp = int(row['ts'])
        except (KeyError, TypeError, ValueError):
            return None
        values = (last, opened, high, low, volume)
        if not all(math.isfinite(value) for value in values) or last <= 0 or opened <= 0:
            return None
        if low <= 0 or high < low or not low <= min(last, opened) <= max(last, opened) <= high or volume < 0:
            return None
        change = (last / opened - 1) * 100
        data = {
            'e': '24hrTicker', 'E': timestamp, 's': symbol,
            'o': str(row['open24h']), 'c': str(row['last']), 'P': str(change),
            'h': str(row['high24h']), 'l': str(row['low24h']), 'q': str(row['volCcy24h']),
            'C': timestamp,
        }
        return json.dumps({'stream': channel, 'source': 'okx', 'data': data}, separators=(',', ':'))

    async def keepalive(self, upstream):
        while True:
            await asyncio.sleep(10)
            await upstream.send_str('ping')

    def channels_for(self, family):
        return {channel for channel in self.channels
                if (self.channel_parts(channel)[1] == 'ticker') == (family == 'ticker')}

    async def run_upstream(self, url, family):
        backoff = 1
        while not self.closed:
            changed = self.kind_changed[family]
            if not self.channels_for(family):
                changed.clear(); await changed.wait()
                if not self.channels_for(family):
                    continue
            control = ping = None
            sent = set()
            upstream = None
            try:
                async with self.http.ws_connect(url, headers={'User-Agent': 'Kanpan-Market-Probe/1.0'}, heartbeat=20, max_msg_size=512 * 1024, compress=0) as connection:
                    upstream = connection
                    self.upstreams.add(connection)
                    self.update_upstream_indicator()
                    if family == 'kline':
                        self.components = {}
                    self.controls.clear()
                    self.upstream_connections += 1; self.last_market = time.monotonic(); self.changed.set()
                    changed.set()
                    control = asyncio.create_task(self.sync(upstream, family, sent, changed))
                    ping = asyncio.create_task(self.keepalive(upstream))
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
            except asyncio.CancelledError:
                raise
            except Exception:
                pass
            finally:
                if upstream is not None:
                    self.upstreams.discard(upstream)
                    self.update_upstream_indicator()
                for task in [control, ping]:
                    if task:
                        task.cancel()
                        with contextlib.suppress(asyncio.CancelledError, Exception):
                            await task
            if self.channels:
                await asyncio.sleep(backoff); backoff = min(30, backoff * 2)

    async def run(self):
        await asyncio.gather(
            self.run_upstream(self.upstream_url, 'ticker'),
            self.run_upstream(self.candle_upstream_url, 'kline'),
        )
