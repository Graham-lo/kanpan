import Testing

@testable import KanpanCore

/// A1.5：惯性曲线与原型逐点相等，`done` 判定也一致。
@Suite("惯性")
struct FlingTests {
  @Test("曲线与原型全等", arguments: Fx.fling.indices)
  func curveMatchesPrototype(_ ri: Int) {
    let row = Fx.fling[ri]
    for pt in row.points {
      let s = flingAt(speedPxPerMs: row.speed, elapsedMs: pt[0], tauMs: Fx.flingTau)
      #expect(abs(s.pastPx - pt[1]) <= 1e-9, "v=\(row.speed) t=\(pt[0]) want \(pt[1]) got \(s.pastPx)")
      #expect(s.done == (pt[2] == 1), "v=\(row.speed) t=\(pt[0]) done 判定不同")
    }
  }

  @Test("常数与任务书一致")
  func constants() {
    #expect(Chart.flingTauMs == 325)
    #expect(Chart.flingMaxMs == 1400)
    #expect(Chart.flingEpsPx == 0.5)
    #expect(Chart.flingMinPxPerMs == 0.2)
    #expect(Chart.flingMaxPxPerMs == 3)
    #expect(Fx.flingTau == Chart.flingTauMs, "fixture 的 τ 和常数不一致")
  }

  /// 位移单调逼近总位移，且永不超过它。
  @Test("位移单调且有上界", arguments: [-3.0, -1.2, -0.25, 0.25, 1.2, 3.0])
  func monotone(_ v: Double) {
    let total = v * Chart.flingTauMs
    var prev = 0.0
    for i in 0...400 {
      let s = flingAt(speedPxPerMs: v, elapsedMs: Double(i) * 5)
      #expect(abs(s.pastPx) <= abs(total) + 1e-9, "t=\(i * 5) 冲过头")
      #expect(abs(s.pastPx) >= abs(prev) - 1e-9, "t=\(i * 5) 倒退")
      prev = s.pastPx
    }
    #expect(flingAt(speedPxPerMs: v, elapsedMs: Chart.flingMaxMs).done, "到 maxMs 还没停")
    #expect(flingAt(speedPxPerMs: v, elapsedMs: 0).pastPx == 0)
  }

  /// 慢于 0.2 px/ms 不算甩；快多少都算，只是速度要封顶（原型 `onUp`）。
  @Test("甩不甩的门槛")
  func threshold() {
    #expect(!isFling(speedPxPerMs: 0.19))
    #expect(isFling(speedPxPerMs: 0.2))
    #expect(isFling(speedPxPerMs: -1.5))
    #expect(isFling(speedPxPerMs: 99))
    #expect(!isFling(speedPxPerMs: 0))
    #expect(flingSpeed(99) == Chart.flingMaxPxPerMs)
    #expect(flingSpeed(-99) == -Chart.flingMaxPxPerMs)
    #expect(flingSpeed(1.25) == 1.25)
    #expect(flingSpeed(-0.4) == -0.4)
  }

  /// 速度只看最近 100 ms：更早的采样不该拖慢结果。
  @Test("速度取样窗口")
  func velocityWindow() {
    var t = VelocityTracker()
    t.add(x: 0, t: 0)
    t.add(x: 1000, t: 50)      // 远古的一大步，应当被丢掉
    t.add(x: 1000, t: 900)
    t.add(x: 1100, t: 950)
    t.add(x: 1200, t: 1000)
    #expect(abs(t.velocity - 2) < 1e-9, "取到 \(t.velocity)")
    t.reset()
    #expect(t.velocity == 0)
  }

  /// 甩出去的速度要按上限截断，不然一帧能飞出几屏。
  @Test("速度上限")
  func speedCap() {
    #expect(flingSpeed(12) == Chart.flingMaxPxPerMs)
    #expect(flingAt(speedPxPerMs: flingSpeed(12), elapsedMs: 1e9).done)
  }
}
