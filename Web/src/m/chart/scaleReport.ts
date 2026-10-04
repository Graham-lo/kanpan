// 缩放宽度什么时候报给页面落盘（iOS ChartViewport.userIsZooming / interactionEnded 的手机网页这一半）。
//
// 图上的根宽（resetSpacing）每一帧都认，换品种、换周期立刻按刚捏出来的宽度开图；
// 但「报给页面」——页面一收到就 save()：整份偏好写 localStorage、同步记脏、syncChart 重算——
// 只在手指全部离开画布的那一刻报一次。捏合一次几十帧，原来每帧都整份落盘一遍。
// 手已经抬起来之后的帧（惯性、回弹）照常即时报，页面那边对宽度没变的那些不写盘。
export class ScaleReport {
  private pending: number | null = null

  constructor(
    private readonly fingersDown: () => boolean,
    private readonly report: (barSpacing: number) => void,
  ) {}

  /** 手势这一帧量出来的根宽。手指还按着就先记下，抬手再报。 */
  note(barSpacing: number): void {
    if (this.fingersDown()) { this.pending = barSpacing; return }
    this.pending = null
    this.report(barSpacing)
  }

  /** 手指全部离开画布（含被系统取消）：欠着的那一下就此报出去。 */
  lift(): void {
    const w = this.pending
    if (w == null) return
    this.pending = null
    this.report(w)
  }

  get owed(): boolean { return this.pending != null }
}
