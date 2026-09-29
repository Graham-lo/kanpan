// 移植自 KanpanChart/Sources/KanpanChart/ChartRenderer+OrderFlow.swift
// （占位：订单流子代理会整份替换本文件；函数签名是和 renderer.ts 约定好的接口。）
import type { ChartRenderer } from './renderer'
import type { Layout, Pane, PriceRange } from './geometry'

export function hasOrderFlow(r: ChartRenderer): boolean { return r.state.overlay.orderFlow != null }
export function drawOrderFlow(_r: ChartRenderer, _ctx: CanvasRenderingContext2D, _pane: Pane, _range: PriceRange, _L: Layout, _scale: number): number { return 0 }
export function drawOrderFlowLabels(_r: ChartRenderer, _ctx: CanvasRenderingContext2D, _pane: Pane, _range: PriceRange, _L: Layout, _scale: number): number { return 0 }
export function drawOrderFlowHover(_r: ChartRenderer, _ctx: CanvasRenderingContext2D, _pane: Pane, _range: PriceRange, _L: Layout, _scale: number): boolean { return false }
export function orderFlowHoversBand(_r: ChartRenderer, _L: Layout, _range: PriceRange): boolean { return false }
export function drawOrderFlowLegend(_r: ChartRenderer, _ctx: CanvasRenderingContext2D, _pane: Pane, _L: Layout, _x: number, _y: number): void {}
