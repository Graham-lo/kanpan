// 设备列表里的名字：鸿蒙（OpenHarmony / ArkWeb / 华为浏览器）要认出来，不能被叫成 Chrome · Linux
import { describe, expect, it } from 'vitest'
import { browserName } from '../src/account/client'

describe('browserName', () => {
  it('nova 16 自带的华为浏览器', () => {
    expect(browserName('Mozilla/5.0 (Phone; OpenHarmony 5.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 ArkWeb/4.1.6.1 Mobile HuaweiBrowser/5.1.3.300'))
      .toBe('网页 · 华为浏览器 · 鸿蒙')
  })
  it('鸿蒙上别的 ArkWeb 壳', () => {
    expect(browserName('Mozilla/5.0 (Phone; OpenHarmony 5.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 ArkWeb/4.1.6.1 Mobile'))
      .toBe('网页 · 鸿蒙浏览器 · 鸿蒙')
  })
  it('iPhone Safari、安卓 Chrome 照旧', () => {
    expect(browserName('Mozilla/5.0 (iPhone; CPU iPhone OS 26_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.6 Mobile/15E148 Safari/604.1')).toBe('网页 · Safari · iPhone')
    expect(browserName('Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Mobile Safari/537.36')).toBe('网页 · Chrome · Android')
  })
})
