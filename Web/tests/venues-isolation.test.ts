// 模块边界：订单流（src/orderflow/**）只认注册表导出的通用描述，不许出现任何一家交易所的名字或域名。
// 去掉注释后逐行扫；唯一例外是 `from '../venues'` 这一行导入。新接一家只动 src/venues/。
import { describe, expect, it } from 'vitest'

const SOURCES = import.meta.glob('../src/orderflow/**/*.ts', { query: '?raw', import: 'default', eager: true }) as Record<string, string>
const BANNED = /binance|okx|coinbase|bybit|hyperliquid|\.com\b|\.xyz\b|binance\.me/i
const VENUES_IMPORT = /from\s+['"]\.\.\/venues['"]/
/** 行情层的通用件（推送分发、行情落表、身份）与电脑版页面 / 自选：按注册表走，不许写别家的名字或域名。
 *  币安是默认交易所（裸代号），它的 REST / 推送复刻代码留在 market/rest.ts、stream.ts、limit.ts，不在这份清单里 */
const GENERIC = {
  ...import.meta.glob('../src/market/{venueStream,quote,identity,state,klineCache,tail,settle}.ts', { query: '?raw', import: 'default', eager: true }),
  ...import.meta.glob('../src/pages/**/*.ts', { query: '?raw', import: 'default', eager: true }),
  ...import.meta.glob('../src/watch/widget.ts', { query: '?raw', import: 'default', eager: true }),
  ...import.meta.glob('../src/ui/common.ts', { query: '?raw', import: 'default', eager: true }),
} as Record<string, string>
const OTHERS = /okx|bybit|hyperliquid|coinbase|okx\.com|bybit\.com|hyperliquid\.xyz|coinbase\.com/i

/** 去注释（块注释保留换行好对行号；行注释不碰字符串里的 //） */
export function stripComments(src: string): string {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, m => m.replace(/[^\n]/g, ' '))
    .replace(/(^|[^:'"`\\])\/\/.*$/gm, '$1')
}

describe('订单流不认交易所', () => {
  it('src/orderflow/** 去注释后不出现交易所名与域名', () => {
    const files = Object.entries(SOURCES)
    expect(files.length).toBeGreaterThan(10)
    const hits: string[] = []
    for (const [f, src] of files) {
      stripComments(src).split('\n').forEach((line, i) => {
        if (VENUES_IMPORT.test(line)) return
        if (BANNED.test(line)) hits.push(`${f}:${i + 1}: ${line.trim()}`)
      })
    }
    expect(hits).toEqual([])
  })

  it('行情层的通用件与页面也不点名别家（2026-10-08：一家的地址、解码只在 src/venues/<id>.ts）', () => {
    const files = Object.entries(GENERIC)
    expect(files.length).toBeGreaterThan(10)
    const hits: string[] = []
    for (const [f, src] of files) {
      stripComments(src).split('\n').forEach((line, i) => { if (OTHERS.test(line)) hits.push(`${f}:${i + 1}: ${line.trim()}`) })
    }
    expect(hits).toEqual([])
  })

  it('扫描器本身会抓：字符串里的交易所名、域名；注释里的不算', () => {
    const src = "// binance 注释\nconst a = 'okx'\n/* bybit */ const u = 'wss://x.com/ws'\nconst ok = 1"
    const lines = stripComments(src).split('\n').filter(l => BANNED.test(l))
    expect(lines).toEqual(["const a = 'okx'", "            const u = 'wss://x.com/ws'"])
  })
})
