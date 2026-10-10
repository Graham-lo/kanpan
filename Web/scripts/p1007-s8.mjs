// Hkline Web · 2026-10-07 压测与回归 第八节：CSV 导出（十六图、每格「全部已加载」）
//   每格：行数 = 图上装的根数；每行列数 = 表头列数；表头含基础列 + 这一格挂着的每条指标线（中文名不乱码）；
//   UTF-8 BOM、CRLF；文件名 = 品种_周期_首根_末根；首末行与图上的 K 线一致；指标列末行与图上算的那条线一致。
//   跑法：node scripts/p1007-s8.mjs
import fs from 'node:fs'
import { URL_, BASE, OUT, open, cellsOf, waitCells, sleep, ok, note, flush, setTag, shot, DATA, browserDown } from './p1007-lib.mjs'

setTag('s8-csv')
const cells = [
  { symbol: 'BTCUSDT', iv: '1m', footprint: true }, { symbol: 'ETHUSDT', iv: '1m', range: true }, { symbol: 'SOLUSDT', iv: '15m', ha: true }, { symbol: 'BNBUSDT', iv: '1s' },
  { symbol: 'XRPUSDT', iv: '5m' }, { symbol: 'DOGEUSDT', iv: '15m' }, { symbol: 'BTCUSDT', iv: '1h' }, { symbol: 'ETHUSDT', iv: '4h' },
  { symbol: 'SOLUSDT', iv: '1d' }, { symbol: 'BNBUSDT', iv: '1m' }, { symbol: 'XRPUSDT', iv: '1s' }, { symbol: 'ADAUSDT', iv: '15m' },
  { symbol: 'BTCUSDT', iv: '1w' }, { symbol: 'LINKUSDT', iv: '30m' }, { symbol: 'AVAXUSDT', iv: '2h' }, { symbol: 'TRXUSDT', iv: '3m' },
]
const ind = { ma: true, ema: false, boll: true, vol: true, subs: ['macd', 'rsi', 'kdj'] }
const state = { ...BASE, layout: '16', cells, ind, pinned: ['1m', '15m', '1h', '4h', '1d'] }
// 每个开着的指标应出的列（名字前缀 → 条数）：均线 4 条周期、布林带 3 轨、平滑异同 快 / 慢 / 柱、相对强弱 1、随机指标 K/D/J
const WANT = [['均线 ', 4], ['布林带', 3], ['平滑异同', 3], ['相对强弱', 1], ['随机指标', 3]]
const BASE_COLS = ['时间', '开盘', '最高', '最低', '收盘', '成交额']

const PROBE = () => {
  window.__q = {
    cells: () => {
      let got = null
      const orig = Array.prototype.map
      Array.prototype.map = function (...a) { if (!got && this.length && this[0] && this[0].chart && this[0].host) got = this; return orig.apply(this, a) }
      try { window.__cells?.() } catch { /* 无 */ } finally { Array.prototype.map = orig }
      return got
    },
  }
  /** 第 i 格：首末根、根数、价格小数位、均线末值（对 CSV 用） */
  window.__q.snap = i => {
    const ch = window.__q.cells()[i].chart, b = ch.bars, last = b[b.length - 1]
    return { n: b.length, dec: ch.meta.dec, first: b[0], last, ma: ch.series.ma?.map(s => s[s.length - 1]) ?? null, macd: ch.series.macd?.map(s => s[s.length - 1]) ?? null }
  }
}

const { ctx, page, errs } = await open(state)
await ctx.addInitScript(PROBE)
await page.reload({ waitUntil: 'domcontentloaded' })
ok('8.0', '十六格出图', await waitCells(page, 16, 20, 90000), (await cellsOf(page)).map(c => `${c.symbol}/${c.iv}:${c.bars}`).join(' '))
await sleep(4000)
await shot(page, 's8-十六图导出前')

const shIso = t => { const d = new Date(t + 8 * 36e5); return d.toISOString().slice(0, 19) + '+08:00' }
const stamp = t => { const d = new Date(t + 8 * 36e5).toISOString(); return d.slice(0, 4) + d.slice(5, 7) + d.slice(8, 10) + '-' + d.slice(11, 13) + d.slice(14, 16) }
const res = []
for (let i = 0; i < 16; i++) {
  const dlP = page.waitForEvent('download', { timeout: 15000 })
  // 先按底栏「导出」开菜单，再点「全部已加载」；快照在同一个任务里取（之后推送进来的一根不算）
  const menu = await page.evaluate(i => {
    // 全局底栏作用于当前格：先把第 i 格设成当前格（格子 mousedown），再点底栏「导出」
    const h = document.querySelectorAll('.chart-cell')[i].querySelector('.canvas-host')
    h.dispatchEvent(new MouseEvent('mousedown', { bubbles: true })); window.dispatchEvent(new MouseEvent('mouseup', { bubbles: true }))
    document.querySelector('#chartFoot [data-act="export"]').click()
    const items = [...document.querySelectorAll('.menu .mi')]
    const it = items.find(x => x.querySelector('.label')?.textContent.trim() === '全部已加载')
    const sc = it?.textContent.replace('全部已加载', '').trim()
    const snap = window.__q.snap(i)
    it?.click()
    return { sc, snap, labels: items.map(x => x.textContent.trim()) }
  }, i)
  const dl = await dlP.catch(() => null)
  if (!dl) { res.push({ i, err: '没下载', menu }); continue }
  const buf = fs.readFileSync(await dl.path())
  const name = dl.suggestedFilename()
  fs.writeFileSync(`${OUT}logs/${name}`, buf)
  const bom = buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf
  const txt = buf.toString('utf8').replace(/^﻿/, '')
  const crlf = !/[^\r]\n/.test(txt) && txt.endsWith('\r\n')
  const lines = txt.split('\r\n').filter(Boolean)
  const head = lines[0].split(','), rows = lines.slice(1).map(l => l.split(','))
  const widthOk = rows.every(r => r.length === head.length)
  const s = menu.snap, c = cells[i]
  const indCols = head.filter(h => !['时间', '开盘', '最高', '最低', '收盘', '成交量', '成交额', '主动买入额'].includes(h))
  const wantOk = WANT.every(([p, k]) => indCols.filter(h => h.startsWith(p)).length === k) && indCols.length === WANT.reduce((a, [, k]) => a + k, 0)
  const num = (v, d) => +(+v).toFixed(d)
  const rowEq = (r, b) => r[0] === shIso(b.t) && +r[1] === num(b.o, s.dec) && +r[2] === num(b.h, s.dec) && +r[3] === num(b.l, s.dec) && +r[4] === num(b.c, s.dec)
  const maIdx = head.findIndex(h => h.startsWith('均线 ')), last = rows[rows.length - 1]
  const maOk = !s.ma || s.ma.every((v, k) => v == null ? last[maIdx + k] === '' : Math.abs(+last[maIdx + k] - v) <= Math.abs(v) * 1e-9 + 10 ** -(s.dec + 4))
  const nameOk = name === `${c.symbol}_${c.iv}_${stamp(s.first.t)}_${stamp(s.last.t)}.csv`
  res.push({ i, cell: `${c.symbol}/${c.iv}${c.footprint ? '·足迹' : c.range ? '·等幅' : c.ha ? '·平均' : ''}`, name, nameOk, bom, crlf, rows: rows.length, n: s.n, sc: menu.sc, cols: head.length, widthOk, bad: head.some(h => h.includes('�')), baseOk: BASE_COLS.every(h => head.includes(h)), wantOk, indCols, firstOk: rowEq(rows[0], s.first), lastOk: rowEq(last, s.last), maOk, head: lines[0] })
  await page.keyboard.press('Escape').catch(() => {})
  await sleep(250)
}
DATA.csv = res
for (const r of res) {
  if (r.err) { ok('8.1', `第 ${r.i + 1} 格导出`, false, r.err + ' 菜单 ' + JSON.stringify(r.menu.labels)); continue }
  ok('8.1', `第 ${r.i + 1} 格 ${r.cell}：行数 = 图上根数，每行列数一致`, r.rows === r.n && r.widthOk && r.sc === `${r.n} 根`, `${r.rows} 行 / 图上 ${r.n} 根（菜单写「${r.sc}」），${r.cols} 列`)
  ok('8.2', `第 ${r.i + 1} 格：表头 = 基础列 + 14 条指标线（中文不乱码）`, r.baseOk && r.wantOk && !r.bad, r.head)
  ok('8.3', `第 ${r.i + 1} 格：BOM + CRLF、文件名、首末行与图上一致、均线末值一致`, r.bom && r.crlf && r.nameOk && r.firstOk && r.lastOk && r.maOk, `${r.name}；BOM ${r.bom} CRLF ${r.crlf} 名 ${r.nameOk} 首 ${r.firstOk} 末 ${r.lastOk} 均线 ${r.maOk}`)
}
const all = res.filter(r => !r.err)
note('8.4', '十六格合计', `${all.length} 个文件、${all.reduce((a, r) => a + r.rows, 0)} 行；文件存在 logs/（不进仓库）`)
ok('8.5', '整段控制台无报错', !errs.length, errs.slice(0, 3).join(' | '))
flush()
await browserDown()
console.log('地址', URL_)
