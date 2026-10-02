/* 手机网页版 · 「我的」各层的纯逻辑：设置页（铃声名、版本、通知提示）、账号页（导出文件名 / 正文、上次同步）、
 * 收件箱一行的字、推进去的层左沿右划返回的判定 */
import { describe, expect, it } from 'vitest'
import { SOUNDS, exportFileName, permissionHint, sortedJSON, soundTitle, syncAgo, webVersion } from '../src/m/model/formText'
import { letterTitle, shortSymbol } from '../src/m/model/inbox'
import { edgeIntent, edgeProgress, edgeShouldPop, edgeZone, inEdgeZone } from '../src/m/model/edgeSwipe'

const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 26_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.6 Mobile/15E148 Safari/604.1'
const NOVA = 'Mozilla/5.0 (Phone; OpenHarmony 7.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36 ArkWeb/6.0.0.0 Mobile HuaweiBrowser/16.0.0.300'

describe('设置', () => {
  it('铃声四档照 iOS 的顺序和名字；不认识的当默认', () => {
    expect(SOUNDS.map(([, t]) => t)).toEqual(['默认', '清脆', '电子', '玻璃'])
    expect(soundTitle('glass')).toBe('玻璃')
    expect(soundTitle('nope' as never)).toBe('默认')
  })
  it('版本：线上取入口脚本名里的哈希，开发时写开发版', () => {
    expect(webVersion('https://x/web/assets/m-B3kd_9a.js', false)).toBe('Hkline 网页版（B3kd_9a）')
    expect(webVersion(null, false)).toBe('Hkline 网页版')
    expect(webVersion('/web/src/m/main.ts', true)).toBe('Hkline 网页版（开发版）')
  })
  it('通知提示：允许了不出；拒绝了指去网站设置；iPhone 标签页里指去加到主屏幕', () => {
    expect(permissionHint('granted', IPHONE, true)).toBeNull()
    expect(permissionHint('default', NOVA, false)).toBeNull()
    expect(permissionHint('denied', NOVA, false)).toContain('网站设置')
    expect(permissionHint('unsupported', IPHONE, false)).toContain('添加到主屏幕')
    expect(permissionHint('unsupported', NOVA, false)).toContain('收不了通知')
  })
})

describe('账号', () => {
  it('导出文件名按上海日期（UTC 16 点后已是第二天）', () => {
    expect(exportFileName(Date.parse('2026-10-02T15:59:00Z'))).toBe('Hkline-我的数据-20261002.json')
    expect(exportFileName(Date.parse('2026-10-02T16:00:00Z'))).toBe('Hkline-我的数据-20261003.json')
  })
  it('导出正文：键逐层按字典序，数组顺序不动，两格缩进', () => {
    expect(sortedJSON({ b: 1, a: [{ z: 1, y: 2 }, 3] })).toBe('{\n  "a": [\n    {\n      "y": 2,\n      "z": 1\n    },\n    3\n  ],\n  "b": 1\n}')
  })
  it('上次同步：刚刚 / 分钟 / 小时 / 天；时钟往回拨不出负数', () => {
    const now = 1_800_000_000_000
    expect(syncAgo(now - 59_000, now)).toBe('刚刚')
    expect(syncAgo(now + 5_000, now)).toBe('刚刚')
    expect(syncAgo(now - 5 * 60_000, now)).toBe('5 分钟前')
    expect(syncAgo(now - 3 * 3600_000, now)).toBe('3 小时前')
    expect(syncAgo(now - 2 * 86_400_000, now)).toBe('2 天前')
  })
})

describe('收件箱一行', () => {
  it('品种短名取基础币；带 - 的取前半', () => {
    expect(shortSymbol({ symbol: 'BTCUSDT', market: 'binance/usd_m' })).toBe('BTC')
    expect(shortSymbol({ symbol: 'BTC-USD', market: 'coinbase/spot' })).toBe('BTC')
  })
  it('「谁 · 哪只 · 几条线」', () => {
    expect(letterTitle({ from: 'amy', symbol: 'ETHUSDT', market: 'binance/usd_m', drawings: [{}, {}, {}] })).toBe('amy · ETH · 3 条线')
  })
})

describe('左沿右划返回', () => {
  it('标签页里让出最左 16 给浏览器 / 系统；iOS 主屏幕模式从 0 起', () => {
    expect(edgeZone(false)).toEqual({ min: 16, max: 44 })
    expect(inEdgeZone(4, false)).toBe(false)
    expect(inEdgeZone(20, false)).toBe(true)
    expect(inEdgeZone(44, false)).toBe(false)
    expect(inEdgeZone(0, true)).toBe(true)
    expect(inEdgeZone(30, true)).toBe(false)
  })
  it('先判方向：8 点内等；横向往右才接管，纵向或往左让出去', () => {
    expect(edgeIntent(3, 4)).toBe('wait')
    expect(edgeIntent(12, 3)).toBe('claim')
    expect(edgeIntent(4, 12)).toBe('abandon')
    expect(edgeIntent(-12, 0)).toBe('abandon')
  })
  it('进度夹在 0…1', () => {
    expect(edgeProgress(-20, 400)).toBe(0)
    expect(edgeProgress(100, 400)).toBe(0.25)
    expect(edgeProgress(900, 400)).toBe(1)
    expect(edgeProgress(10, 0)).toBe(0)
  })
  it('松手：过半退；没过半但甩得快也退；往回甩弹回', () => {
    expect(edgeShouldPop(210, 400, 0)).toBe(true)
    expect(edgeShouldPop(190, 400, 0.1)).toBe(false)
    expect(edgeShouldPop(80, 400, 0.8)).toBe(true)
    expect(edgeShouldPop(300, 400, -0.5)).toBe(false)
  })
})
