// 移植自 KanpanChart/Sources/KanpanChart/ChartView+Drawing.swift 与 KanpanCore/Sources/KanpanCore/Drawing/*.swift
// （占位：画线子代理会整份替换本文件；签名是和 renderer.ts / view.ts 约定好的接口。）

import type { Layout, Pane, PriceMode, PriceRange, ViewWindow } from './geometry'
import { yOf, pOf } from './geometry'
import type { BarSeries } from './series'
import type { ChartColors } from './paint'

export interface Drawing { id: string; [k: string]: unknown }

export class DrawAxes {
  constructor(readonly o: { layout: Layout; pane: Pane; range: PriceRange; mode: PriceMode; view: ViewWindow; decimals: number }) {}
  x(t: number): number { return this.o.view.x(t, this.o.layout.plotW) }
  y(p: number): number { return yOf(p, this.o.pane, this.o.range, this.o.mode) }
  t(x: number): number { return this.o.view.t(x, this.o.layout.plotW) }
  p(y: number): number { return pOf(y, this.o.pane, this.o.range, this.o.mode) }
}

export function paintDrawing(_d: Drawing, _ctx: CanvasRenderingContext2D, _axes: DrawAxes, _colors: ChartColors, _series: BarSeries, _scale: number): void {}
