/* Hkline Web · 「品种停稳」闸
 *
 * 换一只品种，首屏要的只有 K 线与 24h 行情（都立刻取）；详情里的五个慢数、持仓量副图、关键价位、
 * 订单流的深度快照这些非首屏的请求，等品种停住约半秒再发——按住方向键连切时，中间一路划过去的
 * 品种一笔都不取，只给最后停下的那只取一次。
 *
 * 用法：
 *   noteSwitch()          换了品种 / 周期时记一笔
 *   settled()             现在是不是停稳了（冷启动算停稳）
 *   whenSettled(key, fn)  停稳了再做；同一个 key 只留最后一次登记（前一只品种的活自动作废）；已经停稳就立刻做
 *   cancel(key)           撤掉还没做的
 */
export const SETTLE_MS = 500

export class Settle {
  private last = -Infinity
  private waits = new Map<string, () => void>()
  private timer: ReturnType<typeof setTimeout> | null = null

  constructor(private readonly ms = SETTLE_MS) {}

  noteSwitch(): void {
    this.last = Date.now()
    this.arm()
  }

  settled(): boolean { return Date.now() - this.last >= this.ms }

  whenSettled(key: string, fn: () => void): void {
    if (this.settled()) { this.waits.delete(key); fn(); return }
    this.waits.set(key, fn)
    this.arm()
  }

  cancel(key: string): void { this.waits.delete(key) }

  /** 还在等的有几件（测试与诊断用） */
  get pending(): number { return this.waits.size }

  private arm(): void {
    if (this.timer) { clearTimeout(this.timer); this.timer = null }
    if (!this.waits.size) return
    this.timer = setTimeout(() => { this.timer = null; this.fire() }, Math.max(0, this.last + this.ms - Date.now()))
  }

  private fire(): void {
    if (!this.settled()) { this.arm(); return }
    const fns = [...this.waits.values()]
    this.waits.clear()
    for (const f of fns) f()
  }
}

/** 全页共用一个：图表换品种、订单流、关键价位、详情都看它 */
export const settle = new Settle()
