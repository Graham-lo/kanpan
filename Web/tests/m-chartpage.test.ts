/* 手机网页版 · 行情页的纯函数（src/m/pages/chart/logic.ts 等）。口径逐条照 iOS，见 logic.ts 头注。 */
import { describe, expect, it } from 'vitest'
import * as L from '../src/m/pages/chart/logic'
import { INTERVALS } from '../src/m/app/prefs'
import { friendName, shareErrorText } from '../src/m/pages/chart/share'
import { ApiError } from '../src/account/client'

const M = '−'

describe('手机网页版 · 行情页头部', () => {
  it('涨跌行：千分位、U+2212、涨跌幅跟在后面；没数写占位', () => {
    expect(L.priceChangeText(1234.5, 1.23, 1)).toMatch(/^\+1,234\.5  \+1\.23%$/)
    expect(L.priceChangeText(-12.345, -0.5, 2)).toBe(`${M}12.35  ${M}0.50%`)
    expect(L.priceChangeText(-0.001, 0, 2).startsWith('+')).toBe(true) // 四舍五入成 0 不带负号
    expect(L.priceChangeText(null, 1, 2)).toBe(L.priceChangeText(undefined, 1, 2))
  })
  it('倍数：<10 两位、<100 一位、再大取整', () => {
    expect(L.ratioText(3.14159)).toBe('3.14')
    expect(L.ratioText(31.4159)).toBe('31.4')
    expect(L.ratioText(314.159)).toBe('314')
  })
  it('仓 / 额 / 市值：非正、不新鲜都写占位', () => {
    const dash = L.openInterestText(null)
    expect(L.openInterestText(0)).toBe(dash)
    expect(L.openInterestText(7.76e9)).toBe('7.76B')
    expect(L.turnoverText(1.03e10, true)).toBe('10.30B')
    expect(L.turnoverText(1.03e10, false)).toBe(dash)
    expect(L.marketCapValue(2e7, 80000)).toBe(1.6e12)
    expect(L.marketCapText(2e7, 80000, true)).toBe('1.60T')
    expect(L.marketCapText(null, 80000, true)).toBe(dash)
  })
  it('估值格：加密 O/M、美股 FPE（预期亏损给 P/S）、其它不摆', () => {
    expect(L.valuationCell('crypto', { oi: 8e9, supply: 2e7, price: 8e4 })).toEqual({ label: 'O/M', value: '0.50%' })
    expect(L.valuationCell('crypto', { oi: null, supply: 2e7, price: 8e4 })).toEqual({ label: 'O/M', value: null })
    expect(L.valuationCell('us', { supply: 1e9, price: 100, forwardEarnings: 4e9 })).toEqual({ label: 'FPE', value: '25.0' })
    expect(L.valuationCell('us', { supply: 1e9, price: 100, forwardEarnings: -1, revenue: 2e10 })).toEqual({ label: 'P/S', value: '5.00' })
    expect(L.valuationCell('us', { supply: 1e9, price: 100 })).toEqual({ label: 'FPE', value: null })
    expect(L.valuationCell('com', { supply: 1, price: 1 })).toBeNull()
  })
  it('费率：四位小数、带符号、零不带符号、不新鲜占位', () => {
    expect(L.fundingText(0.0001, true)).toEqual({ text: '+0.0100%', dir: 1 })
    expect(L.fundingText(-0.000059, true)).toEqual({ text: `${M}0.0059%`, dir: -1 })
    expect(L.fundingText(0.0000001, true)).toEqual({ text: '0.0000%', dir: 0 })
    expect(L.fundingText(0.0001, false).dir).toBe(0)
  })
  it('结算倒计时：过点往后滚 8 小时、≥ 32 小时不写', () => {
    const now = Date.UTC(2026, 8, 30, 3, 0)
    expect(L.fundingCountdownText(now + (4 * 60 + 19) * 60_000 + 5_000, now)).toBe('4时19分')
    expect(L.fundingCountdownText(now + 30_000, now)).toBe('<1分')
    expect(L.fundingCountdownText(now + 25 * 60_000, now)).toBe('25分')
    expect(L.fundingCountdownText(now - 60 * 60_000, now)).toBe('7时0分')
    expect(L.fundingCountdownText(now + 33 * 3_600_000, now)).toBeNull()
    expect(L.fundingCountdownText(null, now)).toBeNull()
  })
  it('停住判定：全局停住、全市场表断、这只 60 秒没新价', () => {
    const now = 1_000_000
    expect(L.isStale({ flag: true, live: true, now })).toBe(true)
    expect(L.isStale({ flag: false, live: false, now })).toBe(true)
    expect(L.isStale({ flag: false, live: true, lastTick: now - 61_000, now })).toBe(true)
    expect(L.isStale({ flag: false, live: true, lastTick: now - 5_000, now })).toBe(false)
    expect(L.isStale({ flag: false, live: null, now })).toBe(false)
  })
})

describe('手机网页版 · 扫图与周期条', () => {
  const list = ['BTCUSDT', 'ETHUSDT', 'SOLUSDT']
  it('横滑：|dx| > 44 且比竖向大 1.5 倍；左滑下一只、右滑上一只；到头不循环', () => {
    expect(L.swipeTarget(list, 'ETHUSDT', -60, 0)).toBe('SOLUSDT')
    expect(L.swipeTarget(list, 'ETHUSDT', 60, 0)).toBe('BTCUSDT')
    expect(L.swipeTarget(list, 'ETHUSDT', -40, 0)).toBeNull()
    expect(L.swipeTarget(list, 'ETHUSDT', -60, 50)).toBeNull()
    expect(L.swipeTarget(list, 'SOLUSDT', -60, 0)).toBeNull()
    expect(L.swipeTarget(list, 'XRPUSDT', -60, 0)).toBeNull()
  })
  it('钉 / 取消钉：按全表顺序、至少一档、最多六档；满了换一档', () => {
    expect(L.sortIntervals(['1d', '5m', '1h', '5m'], INTERVALS)).toEqual(['5m', '1h', '1d'])
    expect(L.toggleQuick(['5m', '1h'], '15m', INTERVALS)).toEqual({ list: ['5m', '15m', '1h'] })
    expect(L.toggleQuick(['5m', '1h'], '1h', INTERVALS)).toEqual({ list: ['5m'] })
    expect(L.toggleQuick(['1h'], '1h', INTERVALS)).toHaveProperty('refused')
    const full = ['5m', '30m', '1h', '4h', '1d', '1w'] as const
    expect(L.toggleQuick(full, '1m', INTERVALS)).toHaveProperty('refused')
    expect(L.replaceQuick(full, '30m', '1m', INTERVALS)).toEqual(['1m', '5m', '1h', '4h', '1d', '1w'])
    expect(L.replaceQuick(full, '2h', '1m', INTERVALS)).toEqual([...full])
  })
  it('横屏左栏：钉住的档 + 当前档插在该在的位置', () => {
    expect(L.railIntervals(['5m', '1h', '1d'], '4h', INTERVALS)).toEqual(['5m', '1h', '4h', '1d'])
    expect(L.railIntervals(['5m', '1h'], '1h', INTERVALS)).toEqual(['5m', '1h'])
  })
})

describe('手机网页版 · 指标与参数', () => {
  it('主图叠加开关', () => {
    expect(L.toggleOverlay(['MA'], 'BOLL')).toEqual(['MA', 'BOLL'])
    expect(L.toggleOverlay(['MA', 'BOLL'], 'MA')).toEqual(['BOLL'])
  })
  it('副图：成交量不占名额，开第四个换下最早开的', () => {
    expect(L.toggleSub(['VOL', 'OI', 'MACD'], 'RSI')).toEqual({ list: ['VOL', 'OI', 'MACD', 'RSI'], dropped: null })
    expect(L.toggleSub(['OI', 'MACD', 'RSI'], 'KDJ')).toEqual({ list: ['MACD', 'RSI', 'KDJ'], dropped: 'OI' })
    expect(L.toggleSub(['OI', 'MACD', 'RSI'], 'VOL').dropped).toBeNull()
    expect(L.toggleSub(['OI', 'MACD'], 'OI')).toEqual({ list: ['MACD'], dropped: null })
    expect(L.moveSub(['VOL', 'OI', 'MACD'], 0, 2)).toEqual(['OI', 'MACD', 'VOL'])
    expect(L.moveSub(['VOL', 'OI'], 5, 0)).toEqual(['VOL', 'OI'])
  })
  it('参数框：只收数字、最多 3 位、夹到 1…400、全角转半角', () => {
    expect(L.sanitizeParam('１2a3４')).toBe('123')
    expect(L.clampParam('999')).toBe(400)
    expect(L.clampParam('0')).toBe(1)
    expect(L.clampParam('abc')).toBeNull()
  })
})

describe('手机网页版 · 订单流门槛', () => {
  it('金额框：单位展开、科学计数、全角、最多一个小数点', () => {
    expect(L.sanitizeAmount('5M')).toBe('5000000')
    expect(L.sanitizeAmount('1.5万')).toBe('15000')
    expect(L.sanitizeAmount('2亿')).toBe('200000000')
    expect(L.sanitizeAmount('1e6')).toBe('1000000')
    expect(L.sanitizeAmount('１２.3.4')).toBe('12.34')
    expect(L.sanitizeAmount('abc')).toBe('')
  })
  it('夹值、改动表、K/M/B 读法、框里的数', () => {
    expect(L.clampAmount(10, 'spot')).toBe(L.THRESHOLD_RANGE[0])
    expect(L.clampAmount(1e12, 'usdtPerp')).toBe(L.THRESHOLD_RANGE[1])
    expect(L.clampAmount(1e-12, 'step')).toBe(L.STEP_RANGE[0])
    expect(L.mergeOverride({ spot: 1e6, step: 100 }, { usdtPerp: 3e6 }, { spot: 2e6, step: 100 })).toEqual({ usdtPerp: 3e6, spot: 2e6 })
    expect(L.mergeOverride(null, null, { step: 100 })).toEqual({ step: 100 })
    expect(L.compactAmount(5e6)).toBe('5M')
    expect(L.compactAmount(2500)).toBe('2.5K')
    expect(L.compactAmount(1.25e9)).toBe('1.25B')
    expect(L.plainNumber(100)).toBe('100')
    expect(L.plainNumber(0.0005)).toBe('0.0005')
  })
})

describe('手机网页版 · 订单流详情卡', () => {
  const g: L.CardGroup = {
    side: 'bid', contract: true, isRange: true, price: 82600, priceLow: 82400, priceHigh: 82800, step: 100,
    notional: 1.8521e8, books: [{ latest: { price: 82600, notional: 1.8521e8 } }],
    hasFill: true, isLive: true, fillRatio: 0.011, firstSeenMs: Date.UTC(2026, 8, 25, 20, 18), endMs: null,
  }
  it('聚合段写价位区间、买卖与现货合约、持续、状态', () => {
    const t = L.cardText(g, 'BTC', 1, Date.UTC(2026, 8, 29, 20, 0))
    expect(t.price).toBe('82,400 – 82,800')
    expect(t.sideTitle).toBe('委托买单')
    expect(t.kind).toBe('合约')
    expect(t.duration).toBe('持续 3 天 23 小时')
    expect(t.durationCompact).toBe('3天23时')
    expect(t.pairs[0][0]).toEqual({ label: '总金额', value: '185.21M USDT' })
    expect(t.pairs[0][1].value).toBe('2.24K BTC')
    expect(t.pairs[1][0]).toEqual({ label: '开始', value: '09-26 04:18' })
    expect(t.statusText).toBe('成交中 1.1%')
    expect(t.statusTight).toBe('成交中1.1%')
    expect(t.state).toBe('live')
  })
  it('状态：已撤单、成交一部分、全成', () => {
    expect(L.cardStatus({ isLive: false, hasFill: false, fillRatio: 0 })).toEqual({ text: '已撤单', state: 'cancelled' })
    expect(L.cardStatus({ isLive: false, hasFill: true, fillRatio: 0.4 })).toEqual({ text: '成交 40% · 撤单 60%', state: 'filled' })
    expect(L.cardStatus({ isLive: false, hasFill: true, fillRatio: 0.002 }).text).toBe('成交 0.2% · 撤单 99.8%')
    expect(L.cardStatus({ isLive: false, hasFill: true, fillRatio: 1 })).toEqual({ text: '已成交', state: 'filled' })
    expect(L.cardStatus({ isLive: true, hasFill: false, fillRatio: 0 }).text).toBe('挂单中')
  })
  it('持续、数量、步长位数', () => {
    expect(L.durationText(30_000)).toBe('不到 1 分')
    expect(L.durationText(125 * 60_000)).toBe('2 小时 5 分')
    expect(L.durationText(7 * 60_000)).toBe('7 分')
    expect(L.quantityText(12.3456)).toBe('12.35')
    expect(L.quantityText(0.123456)).toBe('0.1235')
    expect(L.stepDecimals(100)).toBe(0)
    expect(L.stepDecimals(0.05)).toBe(2)
    expect(L.percent(0.25)).toBe('25%')
    expect(L.percent(0.011)).toBe('1.1%')
  })
})

describe('手机网页版 · 十字线读数', () => {
  it('三行：时间 + 量、开高、低收（量放第一行，免得顶进右侧六格）', () => {
    const text = L.crosshairOHLC({ t: 0, o: 83446, h: 83494.7, l: 82617.8, c: 83140.1, v: 12760 }, 1, () => '2026-09-28 13:00')
    expect(text.split('\n')).toEqual(['2026-09-28 13:00', '开 83446.0  高 83494.7', '低 82617.8  收 83140.1  量 12.76K'])
  })
})

describe('手机网页版 · 分享', () => {
  it('朋友用户名：3–32 位字母数字下划线、交出去小写', () => {
    expect(friendName('  Alice_01 ')).toBe('alice_01')
    expect(friendName('ab')).toBeNull()
    expect(friendName('中文名')).toBeNull()
  })
  it('发信出错的说法', () => {
    expect(shareErrorText(new ApiError(404, 'no_such_user'))).toBe('没有这个用户名')
    expect(shareErrorText(new ApiError(400, 'cannot_send_self'))).toBe('不能发给自己')
    expect(shareErrorText(new ApiError(429, 'rate'))).toBe('发得有点快，稍后再试')
    expect(shareErrorText(new ApiError(401, 'x'))).toBe('登录已过期，重新登录后再发')
    expect(shareErrorText(new Error('net'))).toBe('暂时连不上')
  })
})

describe('手机网页版 · 画线台的话', async () => {
  const { drawHint, linePhrase } = await import('../src/m/pages/chart/drawingBench')
  it('提示语：单点工具「按住放置」、多点工具按落点数走', () => {
    expect(drawHint('hline', 0)).toBe('按住放置水平线')
    expect(drawHint('trend', 0)).toBe('按住拖动画趋势线')
    expect(drawHint('trend', 1)).toBe('选择终点')
    expect(drawHint('channel', 2)).toBe('选择通道宽度')
    expect(drawHint('position', 9)).toBe('选择止损价')
  })
  it('提醒胶囊：线在上「涨到」、在下「跌到」、两边都有都说', () => {
    expect(linePhrase([85000], 83000, 1)).toEqual({ target: '涨到 85,000.0', distance: '还差 2.41%' })
    expect(linePhrase([80000], 83000, 0)).toEqual({ target: '跌到 80,000', distance: '还差 3.61%' })
    expect(linePhrase([85000, 80000], 83000, 0)).toEqual({ target: '涨到 85,000 或跌到 80,000', distance: null })
    expect(linePhrase([], 83000, 0).target).toBe('价格达到这条线')
    expect(linePhrase([85000], null, 0).target).toBe('到 85,000')
  })
})

describe('手机网页版 · 个性化学习的类别', () => {
  const { habitCategory } = L
  it('加密 / 美股 / 贵金属 / 其它', () => {
    expect(habitCategory(undefined, 'BTC')).toBe('crypto')
    expect(habitCategory('crypto', 'ETH')).toBe('crypto')
    expect(habitCategory('us', 'NVDA')).toBe('equity')
    expect(habitCategory('com', 'XAU')).toBe('metal')
    expect(habitCategory('com', 'CL')).toBe('other')
  })
})
