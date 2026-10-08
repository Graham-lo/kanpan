/* Hkline 手机网页版 · 图标（照 iOS Kanpan/Kanpan/Main/VectorIcon.swift 与 TabBar.swift 的 Path 逐字搬）
 *
 * 两类：
 *   glyph(name)  实心、带釉的记号（底栏四格、画线、记一笔）。颜色取皮肤令牌（--glaze-*），换皮肤不用重画。
 *                渐变与 iOS 一致：左上 → (0.35, 1)，按整个 24 的框算（userSpaceOnUse）。
 *   icon(name)   线框小图标（chevron / 放大镜 / 星…），描边 currentColor，线宽照 iOS。
 * 两者都返回 SVG 字符串，直接塞 innerHTML。
 */

type Item = { d: string } | { c: [number, number, number] } | { r: [number, number, number, number, number] }

function items(list: Item[]): string {
  return list.map(it => {
    if ('d' in it) return `<path d="${it.d}"/>`
    if ('c' in it) return `<circle cx="${it.c[0]}" cy="${it.c[1]}" r="${it.c[2]}"/>`
    const [x, y, w, h, r] = it.r
    return `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}"/>`
  }).join('')
}

// ───────── 线框小图标 ─────────

interface Line { box: number; w: number; items: Item[] }
const LINE = {
  chevron: { box: 12, w: 1.6, items: [{ d: 'M3 4.5 6 7.5 9 4.5' }] },
  search: { box: 18, w: 1.6, items: [{ c: [8, 8, 5.2] }, { d: 'M12 12l3.5 3.5' }] },
  star: { box: 18, w: 1.5, items: [{ d: 'M9 2.2l2 4.2 4.6.6-3.4 3.2.9 4.6L9 12.6 4.9 14.8l.9-4.6L2.4 7l4.6-.6z' }] },
  chevronRight: { box: 16, w: 1.7, items: [{ d: 'M5.5 3.5 10 8l-4.5 4.5' }] },
  chevronLeft: { box: 16, w: 1.7, items: [{ d: 'M10.5 3.5 6 8l4.5 4.5' }] },
  style: { box: 20, w: 1.5, items: [{ r: [2.5, 7, 3.6, 10.5, 1] }, { r: [8.2, 3, 3.6, 14.5, 1] }, { r: [13.9, 9, 3.6, 8.5, 1] }] },
  draw: { box: 20, w: 1.5, items: [{ d: 'M3 17 17 3' }, { c: [4.4, 15.6, 1.8] }, { c: [15.6, 4.4, 1.8] }] },
  settings: { box: 20, w: 1.5, items: [{ c: [10, 10, 2.6] }, { d: 'M10 2.6v2M10 15.4v2M2.6 10h2M15.4 10h2M4.8 4.8l1.4 1.4M13.8 13.8l1.4 1.4M15.2 4.8l-1.4 1.4M6.2 13.8l-1.4 1.4' }] },
  chart: { box: 20, w: 1.5, items: [{ r: [3.5, 6, 4, 8, 0.8] }, { d: 'M5.5 2.6v3.4M5.5 14v3.4' }, { r: [12.5, 4.5, 4, 6, 0.8] }, { d: 'M14.5 2.6v1.9M14.5 10.5v6.9' }] },
  /** SF「arrow.up.arrow.down」：自选「调整顺序」 */
  reorder: { box: 18, w: 1.6, items: [{ d: 'M6 14.5V3.5M3 6.5 6 3.5 9 6.5' }, { d: 'M12 3.5v11M9 11.5l3 3 3-3' }] },
  adjust: { box: 18, w: 1.6, items: [{ d: 'M2.5 5.5h6.4M13.6 5.5h1.9' }, { c: [11.25, 5.5, 2.1] }, { d: 'M2.5 12.5h1.9M9.1 12.5h6.4' }, { c: [6.75, 12.5, 2.1] }] },
  landscape: { box: 20, w: 1.5, items: [{ r: [2.5, 5.5, 15, 9, 1.6] }, { d: 'M7 2.6 9 4.6 7 6.6' }] },
  // —— 网页端补的几枚（iOS 那边用系统符号的地方），同一套线宽与圆头 ——
  close: { box: 16, w: 1.7, items: [{ d: 'M4 4l8 8M12 4l-8 8' }] },
  more: { box: 18, w: 1.6, items: [{ c: [4, 9, 0.9] }, { c: [9, 9, 0.9] }, { c: [14, 9, 0.9] }] },
  plus: { box: 16, w: 1.7, items: [{ d: 'M8 3v10M3 8h10' }] },
  check: { box: 16, w: 1.8, items: [{ d: 'M3.2 8.4 6.4 11.5 12.8 4.8' }] },
  trash: { box: 18, w: 1.5, items: [{ d: 'M3 5h12M7.2 5V3.4h3.6V5M4.6 5l.8 9.6c.06.8.7 1.4 1.5 1.4h4.2c.8 0 1.44-.6 1.5-1.4L13.4 5' }] },
  grip: { box: 18, w: 1.6, items: [{ d: 'M4 6.5h10M4 9h10M4 11.5h10' }] },
  question: { box: 16, w: 1.4, items: [{ c: [8, 8, 6.2] }, { d: 'M6.3 6.4c.2-1 .9-1.6 1.8-1.6 1 0 1.8.7 1.8 1.6 0 1.2-1.6 1.4-1.6 2.6' }, { c: [8.2, 11.3, 0.25] }] },
  /** 记一笔（照 iOS square.and.pencil：方框右上开口 + 一支斜笔） */
  note: { box: 18, w: 1.5, items: [{ d: 'M8.6 3.4H4.8c-.9 0-1.6.7-1.6 1.6v8.2c0 .9.7 1.6 1.6 1.6H13c.9 0 1.6-.7 1.6-1.6V9.4' }, { d: 'M13.3 2.5l2.2 2.2-6.3 6.3-2.9.7.7-2.9z' }] },
  share: { box: 18, w: 1.6, items: [{ d: 'M9 2.8v9M5.8 6 9 2.8 12.2 6' }, { d: 'M5.5 8.5H4.8c-.9 0-1.6.7-1.6 1.6v4.5c0 .9.7 1.6 1.6 1.6h8.4c.9 0 1.6-.7 1.6-1.6v-4.5c0-.9-.7-1.6-1.6-1.6h-.7' }] },
  bell: { box: 18, w: 1.5, items: [{ d: 'M4.6 12.6V8.4a4.4 4.4 0 0 1 8.8 0v4.2l1.2 1.4H3.4z' }, { d: 'M7.4 15.6a1.7 1.7 0 0 0 3.2 0' }] },
  /** 照 SF arrow.clockwise：一段 300° 的弧 + 右上箭头 */
  refresh: { box: 18, w: 1.6, items: [{ d: 'M14.2 9a5.2 5.2 0 1 1-1.6-3.75' }, { d: 'M13.2 2.6v3.2H10' }] },
} satisfies Record<string, Line>
export type IconName = keyof typeof LINE

/** 线框小图标；size 为显示边长（px），描边 currentColor */
export function icon(name: IconName, size = 17, cls = ''): string {
  const g: Line = LINE[name]
  return `<svg class="ic${cls ? ' ' + cls : ''}" width="${size}" height="${size}" viewBox="0 0 ${g.box} ${g.box}" fill="none" stroke="currentColor" stroke-width="${g.w}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${items(g.items)}</svg>`
}

// ───────── 实心带釉的记号 ─────────

type Glaze = 'accent' | 'accentLight' | 'gold'
const GLAZE: Record<Glaze, [string, string]> = {
  accent: ['--glaze-accent-a', '--glaze-accent-b'],
  accentLight: ['--glaze-accent-light-a', '--glaze-accent-light-b'],
  gold: ['--glaze-gold-a', '--glaze-gold-b'],
}
interface Layer { glaze: Glaze; items: Item[]; /** 挖空（evenodd） */ holes?: Item[] }

const STAR = 'M12 3.3c.42 0 .8.24 1 .62l2.14 4.26 4.78.69c.93.13 1.3 1.28.62 1.93l-3.45 3.28.81 4.67c.16.93-.82 1.64-1.66 1.2L12 17.76l-4.24 2.19c-.84.44-1.82-.27-1.66-1.2l.81-4.67-3.45-3.28c-.68-.65-.31-1.8.62-1.93l4.78-.69L11 3.92c.2-.38.58-.62 1-.62z'
const GLYPHS = {
  /** 图表：三根圆角蜡烛 */
  chart: [
    { glaze: 'accent', items: [{ r: [3.7, 8.6, 2.8, 4.6, 1.4] }, { r: [3, 12.4, 4.2, 8.4, 2.1] }] },
    { glaze: 'gold', items: [{ r: [9.9, 6.2, 4.2, 14.6, 2.1] }] },
    { glaze: 'accent', items: [{ r: [17.5, 6.4, 2.8, 4.4, 1.4] }, { r: [16.8, 10.2, 4.2, 10.6, 2.1] }] },
  ],
  /** 自选：圆角五角星，整颗金 */
  favorites: [{ glaze: 'gold', items: [{ d: STAR }] }],
  /** 板块分类：四颗气泡 */
  sectors: [
    { glaze: 'accent', items: [{ c: [8.1, 8.6, 5] }, { c: [15.7, 16.4, 4.4] }] },
    { glaze: 'gold', items: [{ c: [17.4, 6.6, 2.9] }] },
    { glaze: 'accentLight', items: [{ c: [6.1, 18, 2.5] }] },
  ],
  /** 我的：主色肩身 + 金色头 */
  me: [
    { glaze: 'accent', items: [{ d: 'M3.6 19.4c0-4.5 3.8-7.6 8.4-7.6s8.4 3.1 8.4 7.6v.3c0 .9-.7 1.6-1.6 1.6H5.2c-.9 0-1.6-.7-1.6-1.6v-.3z' }] },
    { glaze: 'gold', items: [{ c: [12, 6.6, 3.9] }] },
  ],
  /** 记一笔（ReviewGlyph）：主色本子挖两道横线 + 金色书签 */
  review: [
    { glaze: 'accent', items: [{ r: [4.2, 2.6, 15.6, 18.8, 3.4] }], holes: [{ r: [7.6, 12.2, 8.8, 2.3, 1.15] }, { r: [7.6, 16.1, 5.6, 2.3, 1.15] }] },
    { glaze: 'gold', items: [{ d: 'M12.6 1.9h4.2c.5 0 .9.4.9.9v7.5c0 .45-.52.7-.87.42L14.7 9.1l-2.13 1.62c-.35.28-.87.03-.87-.42V2.8c0-.5.4-.9.9-.9z' }] },
  ],
  /** 画线（IntervalDrawGlyph）：主色折线（描边）+ 金色锚点；折线单独处理 */
  draw: [{ glaze: 'gold', items: [{ c: [19.1, 5.9, 2.5] }] }],
} satisfies Record<string, Layer[]>
export type GlyphName = keyof typeof GLYPHS

let seq = 0
/** 把 SVG 形状转成一条 path d（给挖空用） */
function asPath(it: Item): string {
  if ('d' in it) return it.d
  if ('c' in it) { const [x, y, r] = it.c; return `M${x - r} ${y}a${r} ${r} 0 1 0 ${2 * r} 0a${r} ${r} 0 1 0 ${-2 * r} 0z` }
  const [x, y, w, h, r] = it.r
  return `M${x + r} ${y}h${w - 2 * r}a${r} ${r} 0 0 1 ${r} ${r}v${h - 2 * r}a${r} ${r} 0 0 1 ${-r} ${r}h${-(w - 2 * r)}a${r} ${r} 0 0 1 ${-r} ${-r}v${-(h - 2 * r)}a${r} ${r} 0 0 1 ${r} ${-r}z`
}

/** 实心带釉的记号；size 为显示边长（底栏 27，画线 / 记一笔 24） */
export function glyph(name: GlyphName, size = 27, cls = ''): string {
  const id = 'gz' + (++seq).toString(36)
  const used = new Set<Glaze>()
  const layers = GLYPHS[name] as Layer[]
  layers.forEach(l => used.add(l.glaze))
  if (name === 'draw') used.add('accent')
  // 渐变按整个 24 的框：左上 (0,0) → (0.35·24, 24)
  const defs = [...used].map(g => `<linearGradient id="${id}-${g}" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="8.4" y2="24"><stop offset="0" style="stop-color:var(${GLAZE[g][0]})"/><stop offset="1" style="stop-color:var(${GLAZE[g][1]})"/></linearGradient>`).join('')
  let body = ''
  if (name === 'draw') body += `<path d="M3.4 17.6 8.5 12.1l3.4 3 6.4-8.2" fill="none" stroke="url(#${id}-accent)" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>`
  for (const l of layers) {
    if (l.holes) body += `<path fill-rule="evenodd" fill="url(#${id}-${l.glaze})" d="${[...l.items, ...l.holes].map(asPath).join('')}"/>`
    else body += `<g fill="url(#${id}-${l.glaze})">${items(l.items)}</g>`
  }
  return `<svg class="glyph${cls ? ' ' + cls : ''}" width="${size}" height="${size}" viewBox="0 0 24 24" aria-hidden="true"><defs>${defs}</defs>${body}</svg>`
}
