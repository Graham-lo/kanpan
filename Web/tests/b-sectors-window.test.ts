import { describe, expect, it } from 'vitest'
import { pickWindow, shownWindow } from '../src/sectors/window'

describe('板块页今日 / 5 日的临时改看', () => {
  it('从图表点进来临时看今日后，点「5 日」能回到 5 日，且不用重存偏好', () => {
    const c = { want: 'd5' as const, once: 'today' as const }
    expect(shownWindow(c)).toBe('today')
    const p = pickWindow(c, 'd5')
    expect(p).toEqual({ next: { want: 'd5', once: null }, save: false })
  })
  it('临时看今日时点「今日」是确认当前，不动偏好', () => {
    expect(pickWindow({ want: 'd5', once: 'today' }, 'today')).toBeNull()
  })
  it('没有临时改看时按偏好走，换档才存', () => {
    expect(pickWindow({ want: 'today', once: null }, 'd5')).toEqual({ next: { want: 'd5', once: null }, save: true })
    expect(pickWindow({ want: 'today', once: null }, 'today')).toBeNull()
  })
})
