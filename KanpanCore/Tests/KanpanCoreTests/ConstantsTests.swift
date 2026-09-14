import Foundation
import Testing

@testable import KanpanCore

/// 手感常数照抄原型 `chart.js`。
///
/// 这些数字是「看盘」手感的全部来源，改一个就是换一种手感，所以钉死在测试里：
/// 谁要动，先过这一关，顺便被逼着去改原型和任务书。
@Suite("手感常数")
struct ConstantsTests {
  @Test("间距与缩放")
  func spacing() {
    #expect(Chart.minBarSpacing == 0.4)
    #expect(Chart.maxBarSpacing == 40)
    #expect(Chart.pinchMinPx == 8)
    #expect(Chart.minBarSpacing < Chart.maxBarSpacing)
    // 11 款风格的默认间距都得落在可缩放区间里，不然一进去就被夹
    for st in CandleStyle.all {
      #expect(st.spacing >= Chart.minBarSpacing && st.spacing <= Chart.maxBarSpacing, "\(st.id)")
    }
  }

  @Test("惯性")
  func fling() {
    #expect(Chart.flingTauMs == 325)
    #expect(Chart.flingMaxMs == 1400)
    #expect(Chart.flingMinPxPerMs == 0.2)
    #expect(Chart.flingMaxPxPerMs == 3)
    #expect(Chart.flingEpsPx == 0.5)
    #expect(Chart.flingMinPxPerMs < Chart.flingMaxPxPerMs)
    // fixture 里导出的也是这两个数，别两头对不上
    #expect(Fx.flingTau == Chart.flingTauMs)
  }

  @Test("视野留白")
  func gaps() {
    #expect(Chart.rightGap == 0.06, "原型 resetView：lastT + span * 0.06")
    #expect(Chart.softGive == 0.12, "原型 clamp：give = soft ? span * 0.12 : 0")
    #expect(Chart.softGive > Chart.rightGap, "回弹余量要比默认留白大，不然拖到头就硬")
    #expect(Chart.loadMoreBars == 200)
  }

  @Test("刻度密度")
  func tickDensity() {
    // 任务书 §5 正文写的是 44 / 78，原型是 46 / 74——以原型为准。
    #expect(Chart.priceLabelPx == 46)
    #expect(Chart.timeLabelPx == 74)
  }

  @Test("手势时长与位移")
  func gestures() {
    #expect(Chart.longPressMs == 320, "原型 setTimeout(…, 320)")
    #expect(Chart.longPressSlopPt == 6, "原型 moved > 6 就取消长按")
    #expect(Chart.doubleTapMs == 280)
    #expect(Chart.tapMaxMs == 200)
    #expect(Chart.panSlopPt == 4)
    #expect(Chart.panSlopPt < Chart.longPressSlopPt, "拖动要比长按更早认定，不然长按会被拖走")
    #expect(Chart.tapMaxMs < Chart.longPressMs, "轻点必须在长按之前就判完")
  }

  @Test("命中阈值")
  func hitRadii() {
    #expect(Chart.hitLinePt == 9)
    #expect(Chart.hitHandlePt == 12)
    #expect(Chart.hitHandlePt > Chart.hitLinePt, "手柄要比线身好点中，不然拖不动端点")
  }
}
