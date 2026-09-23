"""Order-flow channels (`<symbol>@depth@100ms`, `<symbol>@aggTrade`) for both relays.

Everything that makes these channels different from a ticker or kline lives
here, so the two hubs only carry one-line hooks:

* They are *sequences*: Binance chains depth frames by U/u/pu and OKX by
  seqId/prevSeqId, and every trade counts towards the traded volume. The
  newest-frame-only coalescing the hubs use for tickers would silently drop
  frames, so `sequenced()` channels are queued frame by frame in Pending
  instead (still inside the same per-peer byte cap).
* Binance moved order-book streams to the `/public` endpoint. Measured on the
  node on 2026-09-24: `/market/stream?streams=btcusdt@depth@100ms` delivered 0
  frames in 4 s, `/public/stream` delivered 39 with U/u/pu. The ticker/kline
  socket therefore never carries depth; `BinancePublicLane` owns a second
  upstream that only carries depth channels. Trades did not move: the same
  measurement gave `/market/stream` 123 aggTrade frames in 5 s and `/public`
  none, so aggTrade stays on the ticker/kline socket (`on_public()` is False).
* OKX `books` and `trades` frames are forwarded verbatim inside the envelope
  the phone expects, with the contract face value next to them (`okx_frame`).
"""
import asyncio
import contextlib
import json
import time
from urllib.parse import urlencode

from aiohttp import WSMsgType

SUFFIX = '@depth@100ms'
TRADES = '@aggTrade'
BINANCE_PUBLIC = 'wss://fstream.binance.com/public/stream'
OKX_CHANNEL = 'books'  # 400 levels: a snapshot first, then incremental updates
# Client channel suffix -> (hub kind, OKX channel). Same instId as the ticker.
OKX_SEQUENCED = {SUFFIX: ('books', OKX_CHANNEL), TRADES: ('trades', 'trades')}


def sequenced(channel):
    """True for channels whose frames must all arrive, in order."""
    return channel.endswith(SUFFIX) or channel.endswith(TRADES)


def on_public(channel):
    """True for the Binance channels that only the /public endpoint delivers."""
    return channel.endswith(SUFFIX)


def split(channels):
    """(Binance /public channels, everything else) of an iterable of channel names."""
    channels = set(channels)
    public = {channel for channel in channels if on_public(channel)}
    return public, channels - public


def okx_frame(channel, ct_val, raw):
    """The phone's OKX depth envelope; `raw` is the upstream message untouched.

    Without a face value the phone cannot turn contracts into coins, so no
    frame is better than a frame in the wrong unit.
    """
    if not ct_val:
        return None
    return '{"stream":%s,"source":"okx","ctVal":%s,"data":%s}' % (
        json.dumps(channel), json.dumps(str(ct_val)), raw)


class BinancePublicLane:
    """Second Binance upstream for depth channels, fanned out through the hub's peers."""

    def __init__(self, hub, url=BINANCE_PUBLIC, idle_seconds=2, stall_seconds=15):
        self.hub, self.url = hub, url  # url injected only by local tests
        self.idle_seconds, self.stall_seconds = idle_seconds, stall_seconds
        self.changed = asyncio.Event()
        self.upstream, self.sent = None, set()
        self.last = 0.0
        self.connections = 0

    def wanted(self):
        # Parked channels are included: a phone flipping back within the hold
        # gets diffs at once and only needs a fresh REST snapshot.
        return split(set(self.hub.channels) | self.hub.lingering())[0]

    def next_expiry(self):
        deadlines = [at for channel, at in self.hub.linger.items() if on_public(channel)]
        return min(deadlines) if deadlines else None

    async def run(self):
        backoff = 1
        while not self.hub.closed:
            if not self.wanted():
                self.changed.clear()
                await self.changed.wait()
                continue
            tasks = []
            try:
                initial = self.wanted()
                url = self.url + '?' + urlencode({'streams': '/'.join(sorted(initial))})
                async with self.hub.http.ws_connect(url, heartbeat=20, max_msg_size=4 * 1024 * 1024,
                                                    compress=0) as upstream:
                    self.upstream, self.sent = upstream, initial
                    self.connections += 1
                    self.last = time.monotonic()
                    tasks = [asyncio.create_task(self.sync(upstream)), asyncio.create_task(self.watch(upstream))]
                    async for message in upstream:
                        if message.type != WSMsgType.TEXT:
                            break
                        try:
                            payload = json.loads(message.data)
                            channel = payload.get('stream')
                            if not isinstance(payload.get('data'), dict):
                                continue
                        except (ValueError, AttributeError):
                            continue
                        self.last = time.monotonic()
                        backoff = 1
                        for peer in tuple(self.hub.channels.get(channel, ())):
                            if not peer.closing and not peer.offer(channel, message.data):
                                peer.closing = True
                                asyncio.create_task(self.hub.disconnect(peer, 1013))
            except asyncio.CancelledError:
                raise
            except Exception:
                pass  # no payload/user/IP logging; retry bounded below
            finally:
                self.upstream, self.sent = None, set()
                for task in tasks:
                    task.cancel()
                    with contextlib.suppress(asyncio.CancelledError, Exception):
                        await task
            if self.wanted():
                await asyncio.sleep(backoff)
                backoff = min(30, backoff * 2)

    async def sync(self, upstream):
        identity = 0
        while True:
            expiry = self.next_expiry()
            if expiry is None:
                await self.changed.wait()
            else:
                # A hold that runs out is a change nobody signals, so wake for it.
                with contextlib.suppress(asyncio.TimeoutError):
                    await asyncio.wait_for(self.changed.wait(), max(.05, expiry - time.monotonic()))
            self.changed.clear()
            await asyncio.sleep(.05)  # coalesce a burst of chart switches
            wanted = self.wanted()
            if not wanted:
                with contextlib.suppress(asyncio.TimeoutError):
                    await asyncio.wait_for(self.changed.wait(), self.idle_seconds)
                if not self.wanted():
                    await upstream.close()
                    return
                self.changed.clear()
                wanted = self.wanted()
            for method, values in [('UNSUBSCRIBE', self.sent - wanted), ('SUBSCRIBE', wanted - self.sent)]:
                if values:
                    identity += 1
                    await upstream.send_json({'method': method, 'params': sorted(values), 'id': identity})
                    self.sent = self.sent | values if method == 'SUBSCRIBE' else self.sent - values
                    await asyncio.sleep(.15)  # Binance allows 10 control messages a second

    async def watch(self, upstream):
        while True:
            await asyncio.sleep(min(5, self.stall_seconds / 3))
            if self.wanted() and time.monotonic() - self.last > self.stall_seconds:
                await upstream.close()
                return
