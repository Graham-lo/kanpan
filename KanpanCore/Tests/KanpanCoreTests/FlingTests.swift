import Foundation
import Testing
@testable import KanpanCore
@Suite("AICoin OverScroller参考惯性") struct FlingTests {
  @Test("速度越快距离与持续时间越长；正负对称")
  func speed() {
    let slow = FlingCurve(speedPointsPerSecond: 500)
    let fast = FlingCurve(speedPointsPerSecond: 2000)
    let negative = FlingCurve(speedPointsPerSecond: -2000)
    #expect(fast.durationMs > slow.durationMs && fast.distance > slow.distance)
    #expect(fast.distance == -negative.distance && fast.durationMs == negative.durationMs)
    #expect(FlingCurve(speedPointsPerSecond: 0).sample(elapsedMs: 0).done)
  }
  @Test("曲线单调、有限、到达终点后停止", arguments: [-3000.0, -500, 500, 3000])
  func monotonic(_ speed: Double) {
    let curve = FlingCurve(speedPointsPerSecond: speed)
    var previous = 0.0
    for i in 0...200 {
      let sample = curve.sample(elapsedMs: curve.durationMs * Double(i) / 200)
      #expect(abs(sample.pastPx) >= previous && abs(sample.pastPx) <= abs(curve.distance))
      previous = abs(sample.pastPx)
    }
    #expect(curve.sample(elapsedMs: curve.durationMs).done)
    #expect(curve.sample(elapsedMs: curve.durationMs * 2).pastPx == curve.distance)
  }
  @Test("AOSP参考数值：1000dp/s")
  func reference() {
    let curve = FlingCurve(speedPointsPerSecond: 1000)
    #expect(curve.durationMs == 555)
    #expect(curve.distance == 194)
  }
  @Test("速度取样排除过期采样")
  func velocity() {
    var v = VelocityTracker()
    v.add(x: 0, t: 0); v.add(x: 1000, t: 900)
    v.add(x: 1100, t: 950); v.add(x: 1200, t: 1000)
    #expect(abs(v.velocity - 2) < 1e-9)
    v.reset(); #expect(v.velocity == 0)
  }
}
