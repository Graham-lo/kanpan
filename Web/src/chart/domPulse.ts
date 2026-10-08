/* Hkline Web · 推送驱动的 DOM 读数统一节拍
 *
 * 画布每帧照画（K 线、价格轴上的最新价跟着每一笔走）；推送改出来的 DOM 文字——图例读数、右侧详情、自选 / 板块行——
 * 不赶推送到的那一帧，攒到节拍边界上、所有格子和面板在同一帧一起写：一帧写一次 = 一次排版、一次样式重算。
 *
 * 2026-10-09 十六图 C13「常态 10 秒」实测：原来每来一笔就排一帧——当前品种的逐笔成交一秒几十笔、十六格 K 线流各一秒 4 次，
 * 无头 Chrome 跑满 60 帧时一秒 20 多次排版、40 多次样式重算（3d084e75 那一版今天测同样是 235 次 / 378 次），
 * 次数跟着行情活跃度和帧率走、没有上限；自选行的闪色是主线程动画（150 ms ≈ 9 帧逐帧重算），
 * 跳一次闪一次时几十行错开着闪，几乎每帧都在重算。
 *
 * 节拍：图例与详情 250 ms（推送最快也是 K 线流 250 ms 一拍，人眼看不出慢）；自选 / 板块行一秒一批（同一秒的闪色一起播完）。
 * 鼠标十字线、拖动、滚轮这些交互引起的图例更新不走节拍，当帧就写。 */

/** 图例读数、右侧详情 */
export const DOM_MS = 250
/** 自选 / 板块的报价行 */
export const ROW_MS = 1000

/** 时刻 t（requestAnimationFrame 的帧时间戳）落在第几拍：同一帧里各处拿到的是同一个时间戳，拍号一致 */
export const pulseSlot = (t: number, ms = DOM_MS): number => Math.floor(t / ms)

/** 欠着的写入：在拍号 N 里欠下的，到第一帧拍号 > N 时才写——各处欠下的都落在同一帧（下一拍的第一帧） */
export class PulseDebt {
  private owed = -1
  constructor(private readonly ms: number) {}
  /** 记一笔欠账（已经欠着的不改拍号，免得一直往后推） */
  owe(now: number): void { if (this.owed < 0) this.owed = pulseSlot(now, this.ms) }
  get owing(): boolean { return this.owed >= 0 }
  /** 这一帧（帧时间戳 ts）该不该还：到了就清账、返回 true */
  due(ts: number): boolean {
    if (this.owed < 0 || pulseSlot(ts, this.ms) <= this.owed) return false
    this.owed = -1
    return true
  }
}
