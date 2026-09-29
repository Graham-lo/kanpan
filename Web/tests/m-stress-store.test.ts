/* 手机网页版压测：本机主档被写成非对象（null / 数字 / 数组 / 字符串）时，启动读档不能抛 */
import { afterEach, describe, expect, it, vi } from 'vitest'

afterEach(() => { vi.unstubAllGlobals(); vi.resetModules() })

describe('主档 hkline-m-v1 不是对象', () => {
  for (const raw of ['null', '42', '[1,2]', '"x"', 'true']) {
    it(`存的是 ${raw}：当空档起步，不白屏`, async () => {
      const mem = new Map([['hkline-m-v1', raw]])
      vi.stubGlobal('localStorage', { getItem: (k: string) => mem.get(k) ?? null, setItem: (k: string, v: string) => { mem.set(k, v) }, removeItem: (k: string) => { mem.delete(k) } })
      vi.resetModules()
      const store = await import('../src/m/app/store')
      expect(store.load()).toEqual({})
      expect(Array.isArray(store.st.symbols.favorites)).toBe(true)
      expect(store.st.alerts).toEqual([])
    })
  }
})
