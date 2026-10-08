// 移植自 KanpanChart/Sources/KanpanChart/LegendFit.swift（2026-10-08）
//
// 图例一律单行：主图叠加、对比、副图都不再折第二行——折行会把主图的 K 线顶下去一截、副图上压住线。
// 一行放不下时先整行换短称，再放不下就把尾巴收成「+N」。十字线开着时读数换成那一根的，规则不变
// （每帧现量，字宽跟着读数走）。

import type { Hex } from './paint'
import { ChartFont, drawLeft, textWidth } from './paint'

/** 图例里的一段：全称（带参数）与短称（去参数、只留读数）。 */
export interface LegendItem {
  full: string
  short: string
  color: Hex
}

export function legendItem(full: string, short: string | null | undefined, color: Hex): LegendItem {
  return { full, short: short ?? full, color }
}

/** 读不到数（换品种那一拍、指标比序列短一截）的段不进图例。 */
export const readable = (item: LegendItem): boolean => !item.full.includes('NaN') && !item.full.includes('--')

export interface LegendLine {
  texts: { text: string; color: Hex }[]
  /** 收进「+N」的段数；0 就是全放下了。 */
  more: number
}

export const LegendFit = {
  /** 段与段之间的空隙（和原来折行版一致）。 */
  gap: 8,

  moreText(n: number): string { return '+' + n },

  /** 在 width 宽里摆一行：全称放得下用全称，否则全用短称，再放不下就留最长的短称前缀 + 「+N」。 */
  fit(all: LegendItem[], width: number, measure: (s: string) => number): LegendLine {
    const items = all.filter(readable)
    const gap = LegendFit.gap
    const total = (texts: string[]): number => texts.reduce((s, t) => s + measure(t), 0) + gap * Math.max(0, texts.length - 1)
    if (total(items.map(x => x.full)) <= width) return { texts: items.map(x => ({ text: x.full, color: x.color })), more: 0 }
    const short = items.map(x => x.short)
    if (total(short) <= width) return { texts: items.map(x => ({ text: x.short, color: x.color })), more: 0 }
    let x = 0, kept = 0
    for (let k = 0; k < short.length; k++) {
      const w = measure(short[k]) + (k > 0 ? gap : 0)
      const rest = items.length - k - 1
      const tail = rest > 0 ? gap + measure(LegendFit.moreText(rest)) : 0
      if (!(x + w + tail <= width)) break
      x += w; kept = k + 1
    }
    return { texts: items.slice(0, kept).map(it => ({ text: it.short, color: it.color })), more: items.length - kept }
  },

  /** 摆好并画出来，返回画到哪儿（下一段的起点 x）。 */
  draw(ctx: CanvasRenderingContext2D, items: LegendItem[], x: number, y: number, maxX: number, moreColor: Hex): number {
    const font = ChartFont.axis
    const line = LegendFit.fit(items, maxX - x, s => textWidth(s, font))
    let at = x
    for (const { text, color } of line.texts) {
      drawLeft(ctx, text, at, y, font, color)
      at += textWidth(text, font) + LegendFit.gap
    }
    if (line.more > 0) {
      const text = LegendFit.moreText(line.more)
      drawLeft(ctx, text, at, y, font, moreColor)
      at += textWidth(text, font) + LegendFit.gap
    }
    return at
  },
}
