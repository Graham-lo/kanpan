/* 订单流数据层 → 按品种记的成交流（chart/tradeFlow.ts）的接线，电脑网页版与手机网页版共用（不碰 DOM）。
 *
 * 两件事：
 *   · 每进一笔成交记进分钟桶 / 秒桶：浏览器这边的大单线 = 门槛 ÷ 50（tapeBase 取的那个门槛），服务端给过 bigUsd 就用服务端的；
 *   · 数据层每出一帧拍一次覆盖心跳：各家连接都开着这半秒才算盖住（大单签、累计量差、弹层的合计据此判断哪几分钟能信浏览器）。
 * 门槛 ÷ 5 是「大额」的绝对下限（签的档位地板、成交带的大额），同一条线由 tierFloor 给。
 */
import { beat, recordTrade } from '../chart/tradeFlow'
import { tapeBase } from './tape'
import type { TradeEvent } from './feed'

type ThresholdsLike = Parameters<typeof tapeBase>[0]

/** 浏览器记大单用的线：门槛 ÷ 50；没有门槛给 null（沿用 tradeFlow 里上一次的线） */
export function bigCut(th: ThresholdsLike | null | undefined): number | null {
  const tb = th ? tapeBase(th) : null
  return tb ? tb / 50 : null
}

/** 档位的绝对地板（大额）：门槛 ÷ 5；没有门槛给 0 */
export function tierFloor(th: ThresholdsLike | null | undefined): number {
  const tb = th ? tapeBase(th) : null
  return tb ? tb / 5 : 0
}

/** 进一笔成交：按品种记进成交流 */
export function recordFeedTrade(symbol: string, ev: TradeEvent, th: ThresholdsLike | null | undefined): void {
  recordTrade(symbol, ev, bigCut(th))
}

/** 数据层出一帧：连接都开着就把覆盖区间往后接 */
export function feedBeat(f: { symbol: string; debug(): { conns: { open: boolean }[] } }, now: number): void {
  const conns = f.debug().conns
  beat(f.symbol, now, conns.length > 0 && conns.every(c => c.open))
}
