// 画线标签用到的几种 C printf 格式（Swift `String(format:)` 走的就是 C 那一套）。
// JS 没有 printf：`toFixed` / `toExponential` 在「恰好一半」时一律往大里进，C 按二进制真值
// 四舍六入五成双；这里把 `%.Nf` 做成和 C 逐字一致（先拿 100 位定点展开判断是不是真的恰好一半），
// `%.Ng` 只在有效数字恰好一半这种极少见的情形下可能差一位（刻度和价格都碰不到）。

/** 与 C `%.{p}f` 相同，但不带符号：调用方传 |x|。 */
function fixedAbs(x: number, p: number): string {
  // 1e21 以上 `toFixed` 会退成指数写法；画线标签碰不到这种量级，照 JS 的来。
  if (x >= 1e21) return x.toFixed(p)
  const plain = x.toFixed(p)
  // 判「恰好一半」：用尽可能多的位数把二进制真值展开，看第 p 位之后是不是 5000…0。
  const digits = Math.min(100, p + 80)
  const exact = x.toFixed(digits)
  const dot = exact.indexOf('.')
  const tail = exact.slice(dot + 1 + p)
  if (!/^50*$/.test(tail)) return plain
  // 恰好一半：`toFixed` 往大里进了，C 要落到偶数上。取截断值，末位是奇数才进。
  const truncated = exact.slice(0, p === 0 ? dot : dot + 1 + p)
  const last = truncated.charCodeAt(truncated.length - 1) - 48
  if (last % 2 === 0) return truncated
  return plain
}

/** C `%.{p}f`。 */
export function cFixed(x: number, p: number): string {
  if (Number.isNaN(x)) return 'nan'
  if (!Number.isFinite(x)) return x < 0 ? '-inf' : 'inf'
  const neg = x < 0 || Object.is(x, -0)
  const body = fixedAbs(Math.abs(x), p)
  return neg ? '-' + body : body
}

/** C `%+.{p}f`：正数也写「+」。 */
export function cSignedFixed(x: number, p: number): string {
  if (Number.isNaN(x)) return 'nan'
  if (!Number.isFinite(x)) return x < 0 ? '-inf' : '+inf'
  const neg = x < 0 || Object.is(x, -0)
  return (neg ? '-' : '+') + fixedAbs(Math.abs(x), p)
}

/** C `%.{P}g`：有效数字 P 位，去掉末尾的 0，指数小于 -4 或不小于 P 时写成指数形式。 */
export function cG(x: number, P: number): string {
  if (Number.isNaN(x)) return 'nan'
  if (!Number.isFinite(x)) return x < 0 ? '-inf' : 'inf'
  const prec = P === 0 ? 1 : P
  if (x === 0) return Object.is(x, -0) ? '-0' : '0'
  const neg = x < 0
  const v = Math.abs(x)
  const e = v.toExponential(prec - 1)
  const X = parseInt(e.slice(e.indexOf('e') + 1), 10)
  let out: string
  if (X < prec && X >= -4) {
    out = stripZeros(fixedAbs(v, prec - 1 - X))
  } else {
    const [mant, exp] = e.split('e')
    const n = parseInt(exp, 10)
    const abs = Math.abs(n)
    out = stripZeros(mant) + 'e' + (n < 0 ? '-' : '+') + (abs < 10 ? '0' + abs : String(abs))
  }
  return neg ? '-' + out : out
}

function stripZeros(s: string): string {
  if (s.indexOf('.') < 0) return s
  return s.replace(/0+$/, '').replace(/\.$/, '')
}

type GraphemeSegmenter = { segment(s: string): Iterable<unknown> }
let segmenter: GraphemeSegmenter | null | undefined

/** 字素簇个数（Swift `String.count`）。没有 `Intl.Segmenter` 时按码点数。
 *  分段器只建一次：画线几何每帧每条线都要验一遍文字长度（drawingIsValid），每次 new 一个 Segmenter
 *  是满载平移时最热的一段；空串与纯 ASCII（除 \r\n 算一个字素外一字一簇）直接数，不进分段器。 */
export function graphemeCount(s: string): number {
  if (!s) return 0
  if (/^[\x00-\x7f]*$/.test(s)) return s.length - (s.match(/\r\n/g)?.length ?? 0)
  if (segmenter === undefined) {
    const Seg = (Intl as unknown as { Segmenter?: new (l?: string, o?: { granularity: string }) => GraphemeSegmenter }).Segmenter
    segmenter = Seg ? new Seg(undefined, { granularity: 'grapheme' }) : null
  }
  if (segmenter) {
    let n = 0
    for (const _ of segmenter.segment(s)) { void _; n++ }
    return n
  }
  return Array.from(s).length
}
