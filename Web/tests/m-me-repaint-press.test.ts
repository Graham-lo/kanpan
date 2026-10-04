/* 手机网页「我的」根页、账号 › 同步、复盘本交易列表：定时 / 事件重画时手指正按着某一行，那一行不能被换掉。
 * 机制（pressGate 等松手、setHTML 同一串不重写）的行为用例在 m-pages-sectors-press；这里钉住这三处都接上了。 */
import { describe, expect, it } from 'vitest'
import me from '../src/m/pages/me.ts?raw'
import meAccount from '../src/m/pages/meAccount.ts?raw'
import reviewBook from '../src/m/pages/reviewBook.ts?raw'

const body = (src: string, start: string, end: string): string => {
  const a = src.indexOf(start); const b = src.indexOf(end, a + start.length)
  expect(a, start).toBeGreaterThanOrEqual(0); expect(b, end).toBeGreaterThan(a)
  return src.slice(a, b)
}

describe('定时重画接上 pressGate + setHTML', () => {
  it('「我的」根页：renderRoot 过 pressGate，整块写入走 setHTML', () => {
    expect(me).toMatch(/const rootGate = pressGate\(rootLayer\.body\)/)
    expect(me).toMatch(/function renderRoot\(\): void \{ rootGate\(renderRootNow\) \}/)
    const now = body(me, 'function renderRootNow', '\n  }\n')
    expect(now).toContain('setHTML(rootLayer.body,')
    expect(now).not.toContain('.innerHTML =')
  })

  it('账号 › 同步：30 秒一次的 paint 过 pressGate，「立即同步」所在整块走 setHTML', () => {
    const sync = body(meAccount, 'function buildSync', '\n}\n')
    expect(sync).toMatch(/const gate = pressGate\(body\)/)
    expect(sync).toMatch(/const paint = \(\): void => gate\(paintNow\)/)
    expect(sync).not.toContain('innerHTML =')
    expect(sync).toContain('setInterval(() => { if (!document.hidden) paint() }, 30_000)')
  })

  it('复盘本交易列表：paintTrades 过 pressGate，内容没变不重写、不重挂缩略图', () => {
    expect(reviewBook).toMatch(/const tradesGate = pressGate\(tradesList\)/)
    expect(reviewBook).toMatch(/function paintTrades\(\): void \{ tradesGate\(paintTradesNow\) \}/)
    expect(reviewBook).not.toMatch(/tradesList\.innerHTML\s*=/)
    const now = body(reviewBook, 'function paintTradesNow', '\n  }\n')
    expect(now).toContain('setHTML(tradesList,')
    expect(now).toMatch(/if \(!changed && thumbsOn === want\) return/)
  })
})
