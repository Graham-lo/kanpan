"""Repeatable gateway benchmark. Run on the node itself, before and after a change.

Every number is wall clock as the phone would see it minus the phone's own link:
requests go to the loopback listeners, so what is measured is the gateway plus
its upstream, which is exactly the part this code controls.

    /opt/kanpan-gateway/venv/bin/python bench.py [--rest 8792] [--ws 8793]

The upstream cost is real money against the exchange rate limits, so the whole
run makes well under a hundred requests.
"""
import argparse
import asyncio
import json
import statistics
import subprocess
import time
import urllib.request

# Distinct symbols per phase: a benchmark that re-asks for the same window only
# ever measures the cache it just filled.
FIRST_SCREEN = ['ETHUSDT', 'SOLUSDT', 'BNBUSDT', 'XRPUSDT', 'ADAUSDT']
REPEAT = 'LINKUSDT'
SPACED = 'AVAXUSDT'
BACKFILL = 'DOTUSDT'
TICKER = 'ATOMUSDT'
# Never the resident channel: this phase exists to measure a cold subscription.
COLD_STREAMS = ['ETHUSDT', 'SOLUSDT', 'XRPUSDT']
REVISIT_STREAMS = ['LTCUSDT', 'TRXUSDT', 'NEARUSDT']
RESIDENT_STREAM = 'btcusdt@kline_1m'
MINUTE = 60_000


def fetch(port, path, timeout=30):
    at = time.perf_counter()
    with urllib.request.urlopen(f'http://127.0.0.1:{port}{path}', timeout=timeout) as response:
        body = response.read()
    return (time.perf_counter() - at) * 1000, body


def klines(symbol, interval='1m', limit=300, end=None):
    query = f'/market/v1/klines?source=okx&symbol={symbol}&interval={interval}&limit={limit}'
    return query + (f'&endTime={end}' if end is not None else '')


def cpu_nanos(unit):
    try:
        out = subprocess.run(['systemctl', 'show', unit, '-p', 'CPUUsageNSec'],
                             capture_output=True, text=True, timeout=10).stdout
        return int(out.strip().split('=')[1])
    except (OSError, ValueError, IndexError, subprocess.SubprocessError):
        return None


def report(name, samples, note=''):
    if not samples:
        return print(f'{name:<34} n/a {note}')
    median = statistics.median(samples)
    print(f'{name:<34} 中位 {median:8.1f} ms   全部 {[round(v) for v in samples]} {note}')
    return median


async def first_frame(port, channel, timeout=20):
    import aiohttp
    at = time.perf_counter()
    async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=timeout)) as session:
        url = f'http://127.0.0.1:{port}/market/stream?streams={channel}'
        async with session.ws_connect(url, heartbeat=20, compress=0) as ws:
            while True:
                message = await asyncio.wait_for(ws.receive(), timeout)
                if message.type is not aiohttp.WSMsgType.TEXT:
                    raise RuntimeError(f'unexpected frame {message.type}')
                if json.loads(message.data).get('stream') == channel:
                    return (time.perf_counter() - at) * 1000


async def revisit(port, channel, away=3):
    """Watch a channel, leave, come back: what switching symbols really costs."""
    await first_frame(port, channel)
    await asyncio.sleep(away)
    return await first_frame(port, channel)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--rest', type=int, default=8792)
    parser.add_argument('--ws', type=int, default=8793)
    parser.add_argument('--label', default='')
    args = parser.parse_args()
    print(f'=== kanpan gateway bench {args.label} {time.strftime("%Y-%m-%d %H:%M:%S")} ===')
    before = {unit: cpu_nanos(unit) for unit in ('kanpan-gateway.service', 'kanpan-stream-hub.service')}

    # A 首屏未命中：每个品种都是这台机器没见过的窗口。
    misses = []
    for symbol in FIRST_SCREEN:
        elapsed, body = fetch(args.rest, klines(symbol))
        assert json.loads(body)['symbol'] == symbol
        misses.append(elapsed)
    report('A 首屏未命中', misses)

    # B 立刻重取：纯命中，量的是网关自己的出手成本。
    fetch(args.rest, klines(REPEAT))
    report('B 立刻重取（命中）', [fetch(args.rest, klines(REPEAT))[0] for _ in range(5)])

    # C 间隔重取：手机真实的节奏。1 秒 TTL 过期后，看这一笔是等上游还是命中。
    spaced = []
    fetch(args.rest, klines(SPACED))
    for _ in range(4):
        time.sleep(2.5)
        spaced.append(fetch(args.rest, klines(SPACED))[0])
    report('C 间隔 2.5s 重取', spaced, '← 后台续鲜要打掉的就是这一项')

    # D/E 回补：先要一段历史，再要一段错位 90% 重叠的窗口。
    now = int(time.time() * 1000) // MINUTE * MINUTE
    end = now - 3 * 86_400_000
    deep, _ = fetch(args.rest, klines(BACKFILL, limit=1500, end=end))
    report('D 回补 1500 根', [deep])
    shifted, _ = fetch(args.rest, klines(BACKFILL, limit=1500, end=end - 137 * MINUTE))
    report('E 回补错位窗口（重叠 90%）', [shifted], '← 落盘的 K 线库要打掉的就是这一项')

    # F ticker。
    ticker_miss, _ = fetch(args.rest, f'/market/v1/ticker?source=okx&symbol={TICKER}')
    report('F ticker 未命中', [ticker_miss])

    # G 实时首帧：常驻频道之外的一条，量的是上游 socket 冷不冷。一次只是一个样本，
    # 上游抖一下就能把结论带偏，所以两项各取三次。
    try:
        report('G WS 首帧（非常驻频道）',
               [asyncio.run(first_frame(args.ws, f'{s.lower()}@kline_1m')) for s in COLD_STREAMS])
        report('G2 WS 首帧（常驻频道）',
               [asyncio.run(first_frame(args.ws, RESIDENT_STREAM)) for _ in range(3)])
        # H 真实的切换动作：看过一个频道、离开、几秒后回来。
        report('H WS 回到刚看过的频道', [asyncio.run(revisit(args.ws, f'{s.lower()}@kline_1m'))
                                for s in REVISIT_STREAMS],
               '← 频道保温要打掉的就是这一项')
    except Exception as error:  # a benchmark must never leave the service worse off
        print(f'G WS 首帧 失败：{type(error).__name__} {error}')

    for unit, start in before.items():
        end_nanos = cpu_nanos(unit)
        if start is not None and end_nanos is not None:
            print(f'{unit:<34} 本轮 CPU {(end_nanos - start) / 1e6:8.1f} ms')


if __name__ == '__main__':
    main()
