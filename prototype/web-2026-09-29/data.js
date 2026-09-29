/* Hkline Web · 数据层
 *
 * 行情：浏览器直连币安 U 本位合约公开接口（REST 允许跨域），实时走 WS——
 *   页面从看盘自己的域名打开时用同源网关 /market/stream（和手机「网关」那一档是同一个服务），
 *   否则直连 fstream.binance.com。任何一步取不到就退回仓库里的 BTC 1h 夹具 + 合成数据，
 *   原型在断网时也能完整走一遍。
 * 订单流大单、复盘成交、提醒是原型里的演示数据（形状照服务端的真实字段）。
 */
(function (g) {
  'use strict'

  const REST = 'https://fapi.binance.com'
  const IV_MS = { '1m': 60e3, '3m': 180e3, '5m': 300e3, '15m': 900e3, '30m': 1800e3, '1h': 36e5, '2h': 72e5, '4h': 144e5, '6h': 216e5, '8h': 288e5, '12h': 432e5, '1d': 864e5, '1w': 6048e5, '1M': 2592e6 }
  const INTERVALS = Object.keys(IV_MS)
  const IV_LABEL = { '1m': '1分', '3m': '3分', '5m': '5分', '15m': '15分', '30m': '30分', '1h': '1小时', '2h': '2小时', '4h': '4小时', '6h': '6小时', '8h': '8小时', '12h': '12小时', '1d': '日线', '1w': '周线', '1M': '月线' }
  const IV_SHORT = { '1m': '1分', '3m': '3分', '5m': '5分', '15m': '15分', '30m': '30分', '1h': '1时', '2h': '2时', '4h': '4时', '6h': '6时', '8h': '8时', '12h': '12时', '1d': '日', '1w': '周', '1M': '月' }

  const COMMODITY = { XAU: '黄金', XAG: '白银', XPT: '铂金', XPD: '钯金', COPPER: '铜', CL: 'WTI 原油', BZ: '布伦特原油', NATGAS: '天然气' }
  const US_EXTRA = { SPY: '标普 500 ETF', QQQ: '纳指 100 ETF' }
  const CRYPTO_CN = { BTC: '比特币', ETH: '以太坊', SOL: 'Solana', XRP: '瑞波币', BNB: '币安币', DOGE: '狗狗币', HYPE: 'Hyperliquid', ZEC: '大零币', LINK: 'Chainlink', SUI: 'Sui', NEAR: 'NEAR', QNT: 'Quant', HBAR: 'Hedera', ADA: '艾达币', TRX: '波场', AVAX: '雪崩', LTC: '莱特币', TON: 'Toncoin', DOT: '波卡', PEPE: '佩佩', ENA: 'Ethena', AAVE: 'Aave', UNI: 'Uniswap', BCH: '比特币现金', ETC: '以太经典', FIL: '文件币', APT: 'Aptos', ARB: 'Arbitrum', OP: 'Optimism', WLD: 'Worldcoin', TAO: 'Bittensor', ONDO: 'Ondo', XLM: '恒星币', XMR: '门罗币', PENGU: 'Pudgy Penguins', TRUMP: '特朗普币', FARTCOIN: 'Fartcoin', VIRTUAL: 'Virtuals', XAUT: 'Tether 黄金' }

  const DEFAULT_WATCH = {
    crypto: ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'XRPUSDT', 'HYPEUSDT', 'DOGEUSDT', 'ZECUSDT', 'LINKUSDT', 'SUIUSDT', 'NEARUSDT', 'QNTUSDT', 'HBARUSDT'],
    us: ['NVDAUSDT', 'TSLAUSDT', 'SNDKUSDT', 'MUUSDT', 'AMDUSDT', 'TSMUSDT', 'COINUSDT', 'MSTRUSDT'],
    com: ['XAUUSDT', 'XAGUSDT', 'CLUSDT'],
  }

  // 徽标：一只品种一个颜色 + 首字母（原型里的替身；产品里是逐品种的真记号）
  const BADGE = { BTC: '#F7931A', ETH: '#627EEA', SOL: '#9945FF', XRP: '#23292F', HYPE: '#50D2C1', DOGE: '#C2A633', ZEC: '#E5A93D', LINK: '#2A5ADA', SUI: '#4DA2FF', NEAR: '#1E1E1E', QNT: '#585E63', HBAR: '#222222', BNB: '#F0B90B', NVDA: '#76B900', TSLA: '#CC0000', SNDK: '#E4002B', MU: '#0073CF', AMD: '#1B1B1B', TSM: '#C8102E', COIN: '#0052FF', MSTR: '#D9232E', XAU: '#C9A227', XAG: '#9EA7B3', CL: '#3D3D3D' }
  function badgeColor(base) {
    if (BADGE[base]) return BADGE[base]
    let h = 0; for (const ch of base) h = (h * 31 + ch.charCodeAt(0)) % 360
    return `hsl(${h} 55% 45%)`
  }

  const S = {
    symbols: new Map(),
    live: null,
    wsState: 'idle',
    listeners: new Set(),
  }

  function baseOf(sym) { return sym.replace(/USDT$|USDC$/, '').replace(/^1000+/, '') }
  function kindOf(base) {
    if (COMMODITY[base]) return 'com'
    if (US_EXTRA[base] || g.KP_SECTORS.usNames[base] || g.KP_SECTORS.us.some(x => x[2].includes(base))) return 'us'
    return 'crypto'
  }
  function cnOf(base, kind) {
    if (kind === 'com') return COMMODITY[base]
    if (kind === 'us') return g.KP_SECTORS.usNames[base] || US_EXTRA[base] || base
    return CRYPTO_CN[base] || ''
  }
  function decOf(str) { const i = String(str).indexOf('.'); return i < 0 ? 0 : Math.min(6, String(str).length - i - 1) }

  function put(sym, patch) {
    let s = S.symbols.get(sym)
    if (!s) {
      const base = baseOf(sym), kind = kindOf(base)
      s = { symbol: sym, base, kind, cn: cnOf(base, kind), code: base, price: null, chg: 0, pct: 0, vol: 0, fr: null, nextFunding: null, oi: null, dec: 2, color: badgeColor(base), spark: [] }
      S.symbols.set(sym, s)
    }
    Object.assign(s, patch)
    return s
  }

  async function j(url, ms = 8000) {
    const ctl = new AbortController(), t = setTimeout(() => ctl.abort(), ms)
    try { const r = await fetch(url, { signal: ctl.signal, referrerPolicy: 'no-referrer' }); if (!r.ok) throw new Error(r.status); return await r.json() }
    finally { clearTimeout(t) }
  }

  // ------------------------------------------------------------ 全市场
  async function loadUniverse() {
    try {
      const [tk, pi] = await Promise.all([j(`${REST}/fapi/v1/ticker/24hr`), j(`${REST}/fapi/v1/premiumIndex`)])
      for (const t of tk) {
        if (!/USDT$/.test(t.symbol) || +t.quoteVolume === 0) continue
        put(t.symbol, { price: +t.lastPrice, chg: +t.priceChange, pct: +t.priceChangePercent, vol: +t.quoteVolume, dec: Math.max(decOf(t.lastPrice), 1), open: +t.openPrice, closeTime: t.closeTime, hi: +t.highPrice, lo: +t.lowPrice, count: +t.count })
      }
      for (const p of pi) { const s = S.symbols.get(p.symbol); if (s) Object.assign(s, { fr: +p.lastFundingRate, nextFunding: p.nextFundingTime, mark: +p.markPrice, index: +p.indexPrice }) }
      // 收盘 24h 以上的是下架残留，过滤掉
      const now = Date.now()
      for (const [k, s] of S.symbols) if (s.closeTime && now - s.closeTime > 864e5) S.symbols.delete(k)
      S.live = true
      if (want.size && !ws) connect()
    } catch (e) {
      console.warn('[hkline] 行情接口不可达，用演示数据', e)
      seedOffline()
    }
    return S.symbols
  }
  function seedOffline() {
    const f = g.KP_FALLBACK, last = f.close[f.close.length - 1]
    const demo = { BTCUSDT: last, ETHUSDT: 2684.5, SOLUSDT: 119.2, XRPUSDT: 1.912, HYPEUSDT: 38.41, DOGEUSDT: .1621, ZECUSDT: 214.3, LINKUSDT: 13.62, SUIUSDT: 2.411, NEARUSDT: 2.106, QNTUSDT: 88.4, HBARUSDT: .1702, NVDAUSDT: 186.2, TSLAUSDT: 402.5, SNDKUSDT: 131.4, MUUSDT: 168.9, AMDUSDT: 214.7, TSMUSDT: 288.1, COINUSDT: 316.2, MSTRUSDT: 294.5, XAUUSDT: 4137.2, XAGUSDT: 48.61, CLUSDT: 61.35 }
    let seed = 7
    const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647
    for (const [sym, p] of Object.entries(demo)) {
      const pct = (rnd() - .45) * 8
      put(sym, { price: p, pct, chg: p * pct / 100, vol: 1e7 * (2 + rnd() * 300) * (sym === 'BTCUSDT' ? 40 : sym === 'ETHUSDT' ? 25 : 1), dec: p > 1000 ? 1 : p > 10 ? 2 : p > 1 ? 3 : 4, fr: (rnd() - .3) * 2e-4, nextFunding: Math.ceil(Date.now() / 288e5) * 288e5, hi: p * (1 + Math.abs(pct) / 100 + rnd() * .01), lo: p * (1 - Math.abs(pct) / 100 - rnd() * .01), count: Math.round(2e5 + rnd() * 3e6), mark: p * (1 + (rnd() - .5) * 2e-4), index: p * (1 + (rnd() - .5) * 4e-4) })
    }
    for (const base of Object.keys(g.KP_SECTORS.members).slice(0, 220)) {
      const sym = base + 'USDT'; if (S.symbols.has(sym)) continue
      const p = Math.exp(rnd() * 8 - 4), pct = (rnd() - .48) * 14
      put(sym, { price: p, pct, chg: p * pct / 100, vol: 1e6 * Math.exp(rnd() * 6), dec: p > 10 ? 2 : p > 1 ? 3 : 4, fr: (rnd() - .3) * 3e-4, hi: p * (1 + Math.abs(pct) / 100 + rnd() * .01), lo: p * (1 - Math.abs(pct) / 100 - rnd() * .01), count: Math.round(1e4 + rnd() * 4e5) })
    }
    S.live = false
  }

  // ------------------------------------------------------------ K 线
  function parse(rows) { return rows.map(r => ({ t: r[0], o: +r[1], h: +r[2], l: +r[3], c: +r[4], v: +r[7] })) }
  async function klines(sym, iv, endTime) {
    try {
      const u = `${REST}/fapi/v1/klines?symbol=${sym}&interval=${iv}&limit=1500${endTime ? `&endTime=${endTime - 1}` : ''}`
      const bars = parse(await j(u))
      if (!bars.length && !endTime) throw new Error('empty')
      attachOI(sym, iv, bars)
      return { bars, live: true }
    } catch (e) {
      if (endTime) return { bars: [], live: false }
      return { bars: synth(sym, iv), live: false }
    }
  }
  // 持仓量副图：币安只给 30 天、5m 以上的历史；原型里对齐不到的根留空
  async function attachOI(sym, iv, bars) {
    const map = { '5m': '5m', '15m': '15m', '30m': '30m', '1h': '1h', '2h': '2h', '4h': '4h', '6h': '6h', '12h': '12h', '1d': '1d' }
    if (!map[iv]) return
    try {
      const rows = await j(`${REST}/futures/data/openInterestHist?symbol=${sym}&period=${map[iv]}&limit=500`)
      const m = new Map(rows.map(r => [r.timestamp, +r.sumOpenInterestValue]))
      for (const b of bars) { const v = m.get(b.t); if (v != null) b.oi = v }
      S.listeners.forEach(fn => fn({ type: 'oi', symbol: sym, iv }))
    } catch {}
  }
  function synth(sym, iv) {
    const f = g.KP_FALLBACK, step = IV_MS[iv], n = 1000
    const s = S.symbols.get(sym), last = s?.price || f.close[f.close.length - 1]
    const k = last / f.close[f.close.length - 1]
    const now = Math.floor(Date.now() / step) * step
    const out = []
    for (let i = 0; i < n; i++) {
      const j2 = i % f.close.length
      out.push({ t: now - (n - 1 - i) * step, o: f.open[j2] * k, h: f.high[j2] * k, l: f.low[j2] * k, c: f.close[j2] * k, v: f.volume[j2] * f.close[j2] * k })
    }
    return out
  }

  // ------------------------------------------------------------ 实时
  let ws = null, want = new Set(), wsRetry = 0, pending = null
  function wsURL() {
    const onKanpan = /kanpan\./.test(location.host)
    return onKanpan ? `wss://${location.host}/market/stream?streams=` : 'wss://fstream.binance.com/stream?streams='
  }
  function setStreams(list) {
    const next = new Set(list.slice(0, 64))
    const same = next.size === want.size && [...next].every(x => want.has(x))
    want = next
    if (same && ws) return
    clearTimeout(pending); pending = setTimeout(connect, 150)
  }
  function connect() {
    if (ws) { ws.onclose = null; try { ws.close() } catch {} ws = null }
    // REST 拿不到时整页是演示数据，不再把实时推送拼到演示 K 线上（否则最后一根会跳成一根巨柱）
    if (!want.size || S.forcedOffline || S.live === false) return
    S.wsState = 'connecting'; emit({ type: 'ws' })
    ws = new WebSocket(wsURL() + [...want].join('/'))
    ws.onopen = () => { wsRetry = 0; S.wsState = 'open'; emit({ type: 'ws' }) }
    ws.onmessage = ev => {
      let m; try { m = JSON.parse(ev.data) } catch { return }
      const d = m.data || m, st = m.stream || ''
      if (d.e === '24hrTicker') {
        const s = S.symbols.get(d.s); if (!s) return
        const prev = s.price
        Object.assign(s, { price: +d.c, chg: +d.p, pct: +d.P, vol: +d.q, hi: +d.h, lo: +d.l, count: +d.n, lastTick: Date.now() })
        emit({ type: 'ticker', symbol: d.s, dir: prev == null ? 0 : Math.sign(+d.c - prev) })
      } else if (d.e === 'kline') {
        const k = d.k
        emit({ type: 'kline', symbol: d.s, iv: k.i, bar: { t: k.t, o: +k.o, h: +k.h, l: +k.l, c: +k.c, v: +k.q } })
      } else if (d.e === 'markPriceUpdate') {
        const s = S.symbols.get(d.s); if (s) Object.assign(s, { fr: +d.r, nextFunding: d.T, mark: +d.p, index: +d.i })
      }
    }
    ws.onclose = () => {
      S.wsState = 'closed'; emit({ type: 'ws' })
      if (S.forcedOffline) return
      const delay = Math.min(15000, 1000 * 2 ** wsRetry++)
      pending = setTimeout(connect, delay)
    }
    ws.onerror = () => {}
  }
  function forceOffline(on) {
    S.forcedOffline = on
    if (on) { if (ws) { ws.onclose = null; ws.close(); ws = null } S.wsState = 'closed'; emit({ type: 'ws' }) }
    else connect()
  }
  function emit(e) { S.listeners.forEach(fn => fn(e)) }
  function on(fn) { S.listeners.add(fn); return () => S.listeners.delete(fn) }

  // ------------------------------------------------------------ 演示：主力订单流大单
  // 真实数据来自 kanpan-api 的聚合簿（币安 + OKX + Coinbase 现货），这里按 K 线合成同形状的数据：
  // { price, size(美元), product: 'perp'|'spot', venue, from, to|null }，价位按步长并档，现货与合约分色
  function demoWalls(sym, bars, iv) {
    if (!bars.length) return []
    const last = bars[bars.length - 1].c, n = bars.length
    let seed = [...sym].reduce((a, c) => a * 31 + c.charCodeAt(0), 7) % 2147483647 || 7
    const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647
    const step = niceStep(last * 0.0012)
    const out = []
    for (let k = 0; k < 18; k++) {
      const side = rnd() < .5 ? -1 : 1
      const dist = (0.004 + rnd() * 0.05) * side
      const price = Math.round(last * (1 + dist) / step) * step
      const alive = rnd() < .55
      const from = bars[Math.max(0, n - 20 - Math.floor(rnd() * 160))].t
      const to = alive ? null : Math.min(bars[n - 1].t, from + Math.floor(8 + rnd() * 60) * IV_MS[iv])
      const product = rnd() < .35 ? 'spot' : 'perp'
      const size = (product === 'spot' ? 1e6 : 5e6) * (1 + rnd() * 5)
      out.push({ price, lo: price - step / 2, hi: price + step / 2, size, product, venue: product === 'spot' ? (rnd() < .5 ? 'Coinbase' : '币安') : (rnd() < .6 ? '币安' : 'OKX'), side: price < last ? 'bid' : 'ask', from, to, merged: Math.floor(1 + rnd() * 4) })
    }
    return out
  }
  function niceStep(raw) {
    const p = Math.pow(10, Math.floor(Math.log10(raw))), f = raw / p
    return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * p
  }

  // ------------------------------------------------------------ 演示：复盘成交（从真实 K 线里取点拼回合）
  function demoTrades(sym, bars, iv) {
    const out = [], n = bars.length
    if (n < 200) return out
    let seed = [...sym].reduce((a, c) => a * 31 + c.charCodeAt(0), 11) % 2147483647 || 42
    const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647
    let i = n - 60
    while (out.length < 14 && i > 80) {
      const hold = 4 + Math.floor(rnd() * 22)
      const e = i - hold - Math.floor(rnd() * 30), x = e + hold
      if (e < 40) break
      const long = rnd() < .6
      const entry = bars[e].o, exit = bars[x].c
      const qty = +(20000 / entry).toFixed(4)
      const gross = (long ? exit - entry : entry - exit) * qty
      const fee = (entry + exit) * qty * 0.0004
      out.push({ id: 'r' + out.length, symbol: sym, side: long ? 'long' : 'short', entryT: bars[e].t, exitT: bars[x].t, entry, exit, qty, gross, fee, pnl: gross - fee, fills: 1 + Math.floor(rnd() * 5), venue: rnd() < .7 ? '币安' : 'OKX' })
      i = e - 5
    }
    return out.reverse()
  }

  g.KPData = { S, IV_MS, INTERVALS, IV_LABEL, IV_SHORT, DEFAULT_WATCH, loadUniverse, klines, setStreams, on, forceOffline, demoWalls, demoTrades, put, baseOf, badgeColor, niceStep, synth }
})(window)
