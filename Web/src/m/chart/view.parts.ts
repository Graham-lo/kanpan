// 移植自 KanpanChart/Sources/KanpanChart/ChartView.swift 的 `ChartView.Parts`（三层脏位）。
// 单独成文件，免得 gesture.ts / view.drawing.ts 与 view.ts 互相引用成环。

export const Parts = {
  /** 底图：网格、蜡烛、指标、画线、副图、轴、图例。 */
  plot: 1,
  /** 最新价线 + 右轴胶囊。 */
  live: 2,
  /** 十字线 + 读数。 */
  cross: 4,
  all: 7,
} as const
export type PartsMask = number
