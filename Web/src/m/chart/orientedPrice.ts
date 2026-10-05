// 价格轴倍率横竖各记一份（只在内存里，不同步、不落盘）。移植自 iOS ChartHost.swift 的 OrientedPriceScale（424a0160）。
//
// 横屏画线台的图高不到竖屏的一半，同一个倍率在两种朝向下看起来是两回事：横屏里竖着捏出来的倍率
// 带回竖屏，竖屏的价格轴就莫名其妙被放大了。所以和根宽一样（landscapeBarSpacing）横竖各一份，转屏各回各的。
// - 第一次进某个朝向（那一份还没有）取 1.0 自动贴合，不抄另一个朝向那份；
// - 只换倍率与中心（zoom / centerFraction），轴模式和上下翻转跟着当前那份走；
// - 记下来的那份是哪个品种、哪种轴模式的也一并记着，对不上就当没有；换品种两份都作废（forget）。
import type { PriceMode, PriceTransform } from './geometry'

interface Parked { symbol: string; mode: PriceMode; zoom: number; centerFraction: number }

export class OrientedPriceScale {
  private portrait: Parked | null = null
  private landscape: Parked | null = null

  /** 转屏：把 `current` 记进离开的那个朝向，换上要去的那个朝向那一份（没有就回 1.0）。 */
  rotate(current: PriceTransform, symbol: string, wasLandscape: boolean, nowLandscape: boolean): PriceTransform {
    if (wasLandscape === nowLandscape) return current
    const leaving: Parked = { symbol, mode: current.mode, zoom: current.zoom, centerFraction: current.centerFraction }
    if (wasLandscape) this.landscape = leaving; else this.portrait = leaving
    const back = nowLandscape ? this.landscape : this.portrait
    if (back && back.symbol === symbol && back.mode === current.mode) {
      return { ...current, zoom: back.zoom, centerFraction: back.centerFraction }
    }
    return { ...current, zoom: 1, centerFraction: 0.5 }
  }

  /** 换品种：两份都作废（倍率本来就不跨品种）。 */
  forget(): void { this.portrait = null; this.landscape = null }
}
