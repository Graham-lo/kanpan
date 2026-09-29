import { afterEach, describe, expect, it } from 'vitest'
import { tabGuard } from '../src/app/store'

afterEach(() => tabGuard.reset())

describe('两个标签页共用一份本机状态', () => {
  it('另一页比我更近被人动过：我这份旧了，之后不再写盘', () => {
    tabGuard.touch(1000)
    expect(tabGuard.onForeignWrite(2000)).toBe('stale')
    expect(tabGuard.stale).toBe(true)
  })
  it('另一页是后台拿旧内存自动存的（它被人动得比我早）：我立刻写回去，不变旧', () => {
    tabGuard.touch(5000)
    expect(tabGuard.onForeignWrite(1000)).toBe('repair')
    expect(tabGuard.stale).toBe(false)
  })
  it('两页都没人动过：后写的那页为准，另一页让位（不会互相来回写）', () => {
    expect(tabGuard.onForeignWrite(0)).toBe('stale')
  })
  it('旧了之后，再来的写一律只算旧，不会拿旧内存去「修复」', () => {
    tabGuard.touch(1000)
    tabGuard.onForeignWrite(2000)
    tabGuard.touch(9000)
    expect(tabGuard.onForeignWrite(3000)).toBe('stale')
  })
})
