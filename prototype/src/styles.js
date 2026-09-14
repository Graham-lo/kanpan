/* 看盘 · 风格表
 *
 * 配色只有一套：靛。浅色一版、深色一版，所有风格共用。
 * 风格换的只是 K 线本身——形态、体积、上下影线，以及和它连着的距离：
 *
 *   形态：实心 / 涨空心 / 只描边、实体圆角、十字星时实体留多高
 *   体积：实体占一根间距的几成
 *   影线：多粗、端头平还是圆、比实体淡多少
 *   上下距离：价格上下留白、副图高、时间轴高
 *   左右距离：默认根间距、右侧价格轴宽
 *   外加网格形态和最新价线的虚实
 *
 * 图表类型从头到尾只有一种：蜡烛。
 */
;(function (global) {
  'use strict'

  // ---------------------------------------------------------------- 靛
  // 一套配色只写这些，剩下的令牌（薄纱、遮罩、投影、机身金属、开关）由它们推出来。
  function expand(t) {
    const d = t.dark
    const a = (hex, aa) => hex + aa
    return {
      css: {
        '--ground': t.ground, '--app': t.app, '--chart': t.chart,
        '--raised': t.raised, '--raised2': t.raised2,
        '--line': t.line, '--hair': d ? '#FFFFFF0A' : a(t.ink, '0F'),
        '--grid': t.grid,
        '--ink': t.ink, '--ink2': t.ink2, '--ink3': t.ink3,
        '--up': t.up, '--down': t.down,
        '--amber': t.amber,
        '--amber-soft': a(t.amber, d ? '1A' : '16'),
        '--amber-line': a(t.amber, '55'),
        '--veil': a(t.app, d ? 'EE' : 'F0'),
        '--scrim': d ? a(t.ground, 'D9') : a(t.ink, '4D'),
        '--shadow': d
          ? '0 40px 90px -30px #000, 0 0 0 1px ' + t.line + ' inset'
          : '0 30px 70px -28px ' + a(t.ink, '55') + ', 0 0 0 1px #FFFFFF60 inset',
        '--bezel': d
          ? 'linear-gradient(160deg,' + t.line + ',' + t.raised + ' 42%,' + t.ground + ')'
          : 'linear-gradient(160deg,' + t.raised2 + ',' + t.ground + ' 45%,' + t.line + ')',
        '--seg-on': d ? t.raised : '#FFFFFF',
        '--sw-off': d ? t.raised2 : t.line,
        '--sw-knob': d ? t.ink3 : '#FFFFFF',
      },
      chart: {
        bg: t.chart, grid: t.grid, axis: t.line, text: t.ink2, dim: t.ink3,
        ink: t.ink, amber: t.amber, cross: t.ink3,
        band: t.palette[4], oi: t.palette[5], oiFill: t.palette[5] + (d ? '33' : '2E'),
        chip: d ? t.ground : t.app, panel: t.app,
        crossBg: d ? t.line : t.ink, crossInk: d ? t.ink : t.app,
      },
      green: t.up, red: t.down, palette: t.palette.slice(),
    }
  }

  const INDIGO = {
    light: {
      dark: false,
      ground: '#C7CCE4', app: '#FFFFFF', chart: '#F4F6FD', raised: '#FFFFFF', raised2: '#ECEFF9',
      line: '#DCE0F0', grid: '#E4E7F5', ink: '#12163A', ink2: '#565C85', ink3: '#8B90B2',
      up: '#0E9E78', down: '#DE2E57', amber: '#B26A00',
      palette: ['#B26A00', '#4A55D6', '#0E8F73', '#C43A7E', '#7A5BD6', '#1A7FC4'],
    },
    dark: {
      dark: true,
      ground: '#07091C', app: '#0F1230', chart: '#161A3F', raised: '#1C2154', raised2: '#232858',
      line: '#2A2E6E', grid: '#232858', ink: '#EDEEF8', ink2: '#A6A9C0', ink3: '#6D719A',
      up: '#2FBF8F', down: '#F0567B', amber: '#FFB454',
      palette: ['#FFB454', '#8C95FF', '#4FD1B5', '#F78FB3', '#C8B6FF', '#7FD0FF'],
    },
  }

  // ---------------------------------------------------------------- 十一款形态
  // 默认是「墩」。每一款只改 K 线自己和它周围的距离，颜色一律靛。
  const STYLES = [
    {
      id: 'stout', name: '墩', one: '实体九成 · 圆头粗影线',
      bet: '默认。实体吃满八成六、圆角一点五，影线一点八还收圆头、比实体淡三成。一眼看清每一根。',
      geom: { bodyR: 0.86, wick: 1.8, wickCap: 'round', wickTint: 0.7, shape: 'solid', radius: 1.5, minBody: 2,
              spacing: 9.2, pad: 0.14, axisW: 58, timeH: 26, subH: 84, grid: 'h', lastDash: false },
    },
    {
      id: 'indigo', name: '靛', one: '细实体 · 半像素影线',
      bet: '密度优先。实体只占五成五，影线半个设备像素，一屏塞得下最多的根数，网格横竖都留。',
      geom: { bodyR: 0.55, wick: 0.5, wickCap: 'butt', wickTint: 1, shape: 'solid', radius: 0, minBody: 1,
              spacing: 4.8, pad: 0.08, axisW: 54, timeH: 22, subH: 74, grid: 'both', lastDash: true },
    },
    {
      id: 'glow', name: '辉', one: '圆角实体 · 无网格',
      bet: '把网格整个拿掉，实体切两点六的圆角，影线减淡到六成，只剩价格自己的形状浮在底上。',
      geom: { bodyR: 0.70, wick: 1.2, wickCap: 'round', wickTint: 0.6, shape: 'solid', radius: 2.6, minBody: 2,
              spacing: 7.2, pad: 0.12, axisW: 52, timeH: 24, subH: 72, grid: 'none', lastDash: false },
    },
    {
      id: 'airy', name: '阔', one: '上下左右全放开',
      bet: '专门赌距离：根间距 11、价格上下各留两成、副图 96、时间轴 30、右轴 62。根数少一半，呼吸多一倍。',
      geom: { bodyR: 0.58, wick: 1.0, wickCap: 'round', wickTint: 1, shape: 'solid', radius: 1, minBody: 1,
              spacing: 11, pad: 0.20, axisW: 62, timeH: 30, subH: 96, grid: 'h', lastDash: true },
    },
    {
      id: 'brick', name: '砖', one: '实体几乎满格 · 影线极淡',
      bet: '实体占到九成六、彼此只留一线缝，影线细到半像素还淡掉一半。看的是实体连成的墙。',
      geom: { bodyR: 0.96, wick: 0.5, wickCap: 'butt', wickTint: 0.45, shape: 'solid', radius: 0, minBody: 3,
              spacing: 8.4, pad: 0.12, axisW: 56, timeH: 24, subH: 78, grid: 'h', lastDash: false },
    },
    {
      id: 'needle', name: '针', one: '影线比实体还重',
      bet: '反过来：实体收到四成二，影线加粗到 2.0 收圆头。看的是插针和长影，不是实体。',
      geom: { bodyR: 0.42, wick: 2.0, wickCap: 'round', wickTint: 0.9, shape: 'solid', radius: 0.5, minBody: 2,
              spacing: 7.8, pad: 0.16, axisW: 54, timeH: 24, subH: 76, grid: 'h', lastDash: true },
    },
    {
      id: 'pill', name: '芯', one: '细胶囊 · 上下带影线',
      bet: '实体只占四成但切满圆角，成一根细胶囊；十字星也保底四像素，不会塌成一条线。',
      geom: { bodyR: 0.40, wick: 1.0, wickCap: 'round', wickTint: 1, shape: 'solid', radius: 3, minBody: 4,
              spacing: 6.6, pad: 0.10, axisW: 52, timeH: 23, subH: 72, grid: 'h', lastDash: true },
    },
    {
      id: 'paper', name: '纸', one: '涨空心 · 跌实心',
      bet: '东亚制图的老规矩：上涨留白、下跌落墨。实体放宽到六成四，只留横向网格。',
      geom: { bodyR: 0.64, wick: 0.8, wickCap: 'butt', wickTint: 1, shape: 'hollowUp', radius: 0, minBody: 1,
              spacing: 6.4, pad: 0.10, axisW: 48, timeH: 24, subH: 66, grid: 'h', lastDash: true },
    },
    {
      id: 'outline', name: '描', one: '全部只留轮廓',
      bet: '涨跌都不填实，只留一圈描边靠颜色分方向，网格收成右端一小截刻度。',
      geom: { bodyR: 0.68, wick: 0.9, wickCap: 'butt', wickTint: 0.85, shape: 'outline', radius: 0, minBody: 1,
              spacing: 7.6, pad: 0.10, axisW: 50, timeH: 22, subH: 68, grid: 'tick', lastDash: false },
    },
    {
      id: 'bone', name: '骨', one: '实体三成 · 只剩骨架',
      bet: '实体收到三成四、间距压到 3.4，影线撑起整根形态。看的是结构，不是单根情绪。',
      geom: { bodyR: 0.34, wick: 0.5, wickCap: 'butt', wickTint: 1, shape: 'solid', radius: 0, minBody: 1,
              spacing: 3.4, pad: 0.06, axisW: 44, timeH: 20, subH: 58, grid: 'tick', lastDash: true },
    },
    {
      id: 'dense', name: '密', one: '一屏塞进最多根',
      bet: '间距 2.6、留白五分、右轴 40、时间轴 18、副图 52，网格全去掉。用来看长段走势的形状。',
      geom: { bodyR: 0.62, wick: 0.5, wickCap: 'butt', wickTint: 1, shape: 'solid', radius: 0, minBody: 1,
              spacing: 2.6, pad: 0.05, axisW: 40, timeH: 18, subH: 52, grid: 'none', lastDash: true },
    },
  ]

  global.KanpanPalette = { L: expand(INDIGO.light), D: expand(INDIGO.dark) }
  global.KanpanStyles = STYLES
})(window)
