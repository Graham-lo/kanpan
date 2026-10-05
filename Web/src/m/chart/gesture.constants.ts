// 移植自 KanpanChart/Sources/KanpanChart/ChartGesture.swift 的手势门槛常量。
// 单独成文件（同 view.parts.ts）：view.drawing.ts 在模块顶层就要读 panSlopPt，而 gesture.ts →
// renderer.orderflow.ts → drawing.ts → view.drawing.ts 成环，从 gesture.ts 取时它还没初始化完（undefined）。

export const ChartGesture = {
  longPressMs: 400,
  longPressSlopPt: 6,
  panSlopPt: 4,
  minPinchSpanPt: 10,
  /** 捏合死区：横 / 纵张开量各自变化超过 3pt 才算捏（iOS a8012401；从前是斜线距离 2×panSlopPt = 8pt）。 */
  pinchSlopPt: 3,
  selectedHandlePt: 22,
} as const
