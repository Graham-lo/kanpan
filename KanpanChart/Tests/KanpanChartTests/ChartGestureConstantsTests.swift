import KanpanCore
import Testing

@testable import KanpanChart

/// 手势手感那几个数从 KanpanCore 搬到了 KanpanChart（审查 24），数值一个不许变。
@Suite("手势门槛（从 Core 搬来，数值不变）")
struct ChartGestureConstantsTests {
  @Test func valuesAreUnchanged() {
    #expect(ChartGesture.longPressMs == 400)
    #expect(ChartGesture.longPressSlopPt == 6)
    #expect(ChartGesture.panSlopPt == 4)
    #expect(ChartGesture.minPinchSpanPt == 10)
    #expect(ChartGesture.selectedHandlePt == 22)
    // 选中手柄的靶要比未选中的线体大，否则「只放大正在编辑那条」就没有意义。
    #expect(ChartGesture.selectedHandlePt > Chart.hitHandlePt)
  }
}
