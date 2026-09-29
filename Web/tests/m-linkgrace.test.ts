import { describe, expect, it } from 'vitest'
import { LinkGrace, linkWaiting, LINK_GRACE_MS } from '../src/m/app/linkGrace'

// 照 iOS KanpanTests/Symbols/FavoritesRowObservationTests.swift LinkGraceTests
describe('手机网页版 · 压测：推送断满 5 秒价格变灰', () => {
  it('闪断看不见；真断满 5 秒算断；中途换档不重新起算；接上 / 后台当场复原', () => {
    expect(LINK_GRACE_MS).toBe(5000)
    const link = new LinkGrace()
    const t0 = 1_000_000
    expect(link.track(true, t0)).toBe(true)
    expect(link.isDown(t0 + 1000)).toBe(false)
    link.track(false, t0 + 1000)
    expect(link.isDown(t0 + 60_000)).toBe(false)
    const t1 = t0 + 100_000
    expect(link.track(true, t1)).toBe(true)
    expect(link.track(true, t1 + 4000)).toBe(false)
    expect(link.isDown(t1 + 4900)).toBe(false)
    expect(link.isDown(t1 + 5000)).toBe(true)
    link.track(false, t1 + 9000)
    expect(link.isDown(t1 + 9000)).toBe(false)
    const back = t1 + 600_000
    expect(link.track(true, back)).toBe(true)
    expect(link.isDown(back + 1000)).toBe(false)
    expect(link.isDown(back + 5100)).toBe(true)
  })
  it('只有「前台、有流要订、却不是 open」才算在等', () => {
    expect(linkWaiting('closed', true)).toBe(true)
    expect(linkWaiting('connecting', true)).toBe(true)
    expect(linkWaiting('open', true)).toBe(false)
    expect(linkWaiting('idle', true)).toBe(false)
    expect(linkWaiting('closed', false)).toBe(false)
  })
})
