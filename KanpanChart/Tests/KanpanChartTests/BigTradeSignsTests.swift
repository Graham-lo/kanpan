import CoreGraphics
import Foundation
import Testing
@testable import KanpanChart

/// 图上大单与爆仓气泡的纯函数：两级门槛、泡上的字、摆放（一屏 6 枚、错层、退成点、窄根只画点、躲字与边）、
/// 命中只认泡、读屏（规格 `docs/design/大单爆仓气泡-三端规格-2026-10-08.md`，原型 `one()`）。
@Suite("大单与爆仓气泡 · 纯函数")
struct BigTradeBubblesTests {
  static let k = BigTradeTiers(dot: 100_000, bubble: 300_000)

  static func env(
    spacing: CGFloat = 8, top: CGFloat = 24, bottom: CGFloat = 400, plotW: CGFloat = 800, avoid: [CGRect] = []
  ) -> BigTradeBubbleEnv {
    BigTradeBubbleEnv(
      tiers: k, spacing: spacing, top: top, bottom: bottom, plotW: plotW, avoid: avoid,
      measure: { CGFloat($0.count) * 6 })
  }

  static func bar(_ i: Int = 0, x: CGFloat = 100, hi: CGFloat = 150, lo: CGFloat = 250, up: Double = 0, down: Double = 0)
    -> BigTradeBubbleInput
  {
    BigTradeBubbleInput(index: i, t: Int64(i) * 60_000, x: x, hiY: hi, loY: lo, up: up, down: down)
  }

  // MARK: 门槛

  @Test func 分位数线性插值() {
    #expect(BigTradeBubbles.quantile([1, 2, 3, 4, 5], 0.5) == 3)
    #expect(abs(BigTradeBubbles.quantile([0, 10], 0.9) - 9) < 1e-9)
    #expect(BigTradeBubbles.quantile([7], 0.97) == 7)
    #expect(BigTradeBubbles.quantile([], 0.5) == 0)
  }

  @Test func 两级_点线P90_泡线P97_垫下限() throws {
    let vals = (1...100).map { Double($0) * 1000 } + [0, 0, 0]
    let t = try #require(BigTradeBubbles.tiers(vals, floor: 0))
    #expect(abs(t.dot - 90_100) < 1e-6)
    #expect(abs(t.bubble - 97_030) < 1e-6)
    #expect(vals.filter { $0 >= t.dot }.count == 10)
    #expect(vals.filter { $0 >= t.bubble }.count == 3)
    let some = try #require(BigTradeBubbles.tiers(vals, floor: 95_000))
    #expect(some.dot == 95_000)
    #expect(abs(some.bubble - 97_030) < 1e-6)
    let all = try #require(BigTradeBubbles.tiers(vals, floor: 200_000))
    #expect(all.dot == 200_000 && all.bubble == 200_000, "下限两条线一起垫")
    #expect(BigTradeBubbles.tiers([0, 0], floor: 1) == nil)
  }

  @Test func 不到点线不画_到点线画点_到泡线画泡() {
    #expect(BigTradeBubbles.level(of: 99_999, Self.k) == 0)
    #expect(BigTradeBubbles.level(of: 100_000, Self.k) == 1)
    #expect(BigTradeBubbles.level(of: 299_999, Self.k) == 1)
    #expect(BigTradeBubbles.level(of: 300_000, Self.k) == 2)
    #expect(BigTradeBubbles.level(of: 5, nil) == 0)
    #expect(BigTradeBubbles.level(of: 0, Self.k) == 0)
    #expect(BigTradeBubbles.level(of: .nan, Self.k) == 0)
  }

  @Test func 泡上的字_M去掉_十万以上K取整() {
    #expect(BigTradeBubbles.bubbleText(1_234_567) == "1.2")
    #expect(BigTradeBubbles.bubbleText(12_000_000) == "12.0")
    #expect(BigTradeBubbles.bubbleText(860_400) == "860K")
    #expect(BigTradeBubbles.bubbleText(45_600) == "45.6K")
    #expect(BigTradeBubbles.bubbleText(999_700) == "1.0", "进位成一千 K 就是 1.0（M 不写）")
    #expect(BigTradeBubbles.bubbleText(2_500_000_000) == "2.5B")
    #expect(BigTradeBubbles.bubbleText(800) == "800")
  }

  // MARK: 摆放

  @Test func 上侧挂最高价之上_下侧挂最低价之下_一根上下各一枚() throws {
    let out = BigTradeBubbles.plan([Self.bar(up: 1_200_000, down: 150_000)], env: Self.env())
    #expect(out.count == 2)
    let u = try #require(out.first { $0.up }), d = try #require(out.first { !$0.up })
    #expect(out.first?.up == true, "同根向上在前")
    #expect(u.isBubble && u.text == "1.2")
    #expect(u.r >= BigTradeBubbles.bubbleBaseRadius)
    #expect(abs(u.center.y - (150 - BigTradeBubbles.bubbleStem - u.r)) < 1e-6)
    #expect(u.center.x == 100 && u.anchorY == 150)
    #expect(u.stem.from == CGPoint(x: 100, y: 150) && u.stem.to == CGPoint(x: 100, y: u.center.y + u.r))
    #expect(!d.isBubble && d.text.isEmpty)
    let dotR = BigTradeBubbles.dotRadius(spacing: 8)
    #expect(d.r == dotR)
    #expect(abs(d.center.y - (250 + BigTradeBubbles.dotStem + dotR)) < 1e-6)
  }

  @Test func 泡的半径随金额长_至少容下字() {
    var thin = Self.env()
    thin.measure = { _ in 0 }
    let small = BigTradeBubbles.plan([Self.bar(up: 300_000)], env: thin)[0]
    let big = BigTradeBubbles.plan([Self.bar(up: 900_000)], env: thin)[0]
    let huge = BigTradeBubbles.plan([Self.bar(up: 90_000_000)], env: thin)[0]
    #expect(small.r == 11)
    #expect(abs(big.r - 17) < 1e-6, "泡线三倍就长满 6")
    #expect(huge.r == 17)
    // 字宽 10 字 × 6 = 60 → 至少 34。
    let wide = BigTradeBubbleEnv(
      tiers: Self.k, spacing: 8, top: 24, bottom: 400, plotW: 800, measure: { CGFloat($0.count) * 6 },
      text: { _ in "0123456789" })
    #expect(BigTradeBubbles.plan([Self.bar(up: 300_000)], env: wide)[0].r == 34)
  }

  @Test func 一屏最多6枚泡_金额大的先占_其余退成点() {
    let bars = (0..<10).map { Self.bar($0, x: CGFloat(40 + $0 * 70), up: Double(400_000 + $0 * 100_000)) }
    let out = BigTradeBubbles.plan(bars, env: Self.env())
    #expect(out.count == 10)
    #expect(out.filter(\.isBubble).count == BigTradeBubbles.maxBubbles)
    #expect(Set(out.filter(\.isBubble).map(\.index)) == Set(4..<10))
    #expect(out.map(\.index) == Array(0..<10), "按根升序交回")
  }

  @Test func 一根窄于4全部只画点() {
    let bars = (0..<5).map { Self.bar($0, x: CGFloat(100 + $0 * 3), up: 5_000_000, down: 5_000_000) }
    let out = BigTradeBubbles.plan(bars, env: Self.env(spacing: 3))
    #expect(!out.isEmpty)
    #expect(out.allSatisfy { !$0.isBubble && $0.text.isEmpty })
    // 按整 pt 比：出厂 4 铺满后实得 3.98 也算够宽。
    let wide = [Self.bar(0, x: 100, up: 5_000_000)]
    #expect(BigTradeBubbles.plan(wide, env: Self.env(spacing: 3.98)).first?.isBubble == true)
    #expect(BigTradeBubbles.plan(wide, env: Self.env(spacing: 3.4)).first?.isBubble == false)
  }

  @Test func 同侧挨着就往外错层_不重叠() {
    let bars = (0..<3).map { Self.bar($0, x: CGFloat(100 + $0 * 8), hi: 300, up: Double(2_000_000 - $0 * 100_000)) }
    let out = BigTradeBubbles.plan(bars, env: Self.env()).filter(\.up)
    #expect(out.count == 3 && out.allSatisfy(\.isBubble))
    for a in out {
      for b in out where b.index > a.index {
        #expect(hypot(a.center.x - b.center.x, a.center.y - b.center.y) >= a.r + b.r + BigTradeBubbles.nudgeGap - 0.01)
      }
    }
    // 金额最大的那根贴着自己的柄，小的往上推。
    #expect(abs(out[0].center.y - (300 - 4 - out[0].r)) < 1e-6)
    #expect(out[1].center.y < out[0].center.y)
    // 上下两侧各错各的：下侧不因上侧挪动。
    let mixed = BigTradeBubbles.plan(
      [Self.bar(0, x: 100, up: 1_000_000), Self.bar(1, x: 104, down: 900_000)], env: Self.env())
    let d = mixed.first { !$0.up }!
    #expect(abs(d.center.y - (250 + 4 + d.r)) < 1e-6)
  }

  @Test func 泡出了窗格_退成点且不占配额() {
    // 最大那根顶到图例那一带下沿，泡放不下 → 点；其余 6 根照样成泡。
    var bars = [Self.bar(0, x: 40, hi: 40, up: 9_000_000)]
    bars += (1...6).map { Self.bar($0, x: CGFloat(40 + $0 * 70), up: Double(400_000 + $0 * 10_000)) }
    let out = BigTradeBubbles.plan(bars, env: Self.env(top: 24))
    let first = out.first { $0.index == 0 }!
    #expect(!first.isBubble)
    #expect(abs(first.center.y - (40 - 2 - first.r)) < 1e-6, "退成点后柄 2、圆心重算")
    #expect(out.filter(\.isBubble).count == 6)
    // 下侧压到主图下沿同理。
    let low = BigTradeBubbles.plan([Self.bar(lo: 390, down: 9_000_000)], env: Self.env(bottom: 400))
    #expect(low.count == 1 && !low[0].isBubble)
  }

  @Test func 贴主图左右沿的泡往里收_柄仍竖直接到圆周() throws {
    let right = try #require(BigTradeBubbles.plan([Self.bar(x: 795, up: 1_000_000)], env: Self.env(plotW: 800)).first)
    #expect(right.isBubble)
    #expect(abs(right.bounds.maxX - 800) < 1e-6 && right.x == 795)
    let (p0, p1) = right.stem
    #expect(p0 == CGPoint(x: 795, y: 150) && p1.x == 795)
    #expect(abs(hypot(p1.x - right.center.x, p1.y - right.center.y) - right.r) < 1e-6, "柄接在圆周上")
    let left = try #require(BigTradeBubbles.plan([Self.bar(x: 2, up: 1_000_000)], env: Self.env()).first)
    #expect(left.isBubble && abs(left.bounds.minX) < 1e-6)
    #expect(BigTradeBubbles.hit(CGPoint(x: 795, y: right.center.y), in: [right])?.index == 0)
  }

  @Test func 泡压到画线文字_退成点() {
    let box = CGRect(x: 80, y: 100, width: 60, height: 20)
    let out = BigTradeBubbles.plan([Self.bar(up: 1_000_000)], env: Self.env(avoid: [box]))
    #expect(out.count == 1 && !out[0].isBubble)
    #expect(!out[0].bounds.intersects(box))
  }

  @Test func 点也落不下就不画() {
    // 最高价贴着可落范围上沿：点的外框出去了。
    #expect(BigTradeBubbles.plan([Self.bar(hi: 25, up: 150_000)], env: Self.env(top: 24)).isEmpty)
    // 点压到画线文字。
    let box = CGRect(x: 90, y: 140, width: 20, height: 9)
    #expect(BigTradeBubbles.plan([Self.bar(up: 150_000)], env: Self.env(avoid: [box])).isEmpty)
    // 不到点线的不画。
    #expect(BigTradeBubbles.plan([Self.bar(up: 99_000, down: 1)], env: Self.env()).isEmpty)
  }

  // MARK: 命中

  @Test func 命中只认泡_44热区_取最近() throws {
    let out = BigTradeBubbles.plan(
      [Self.bar(0, x: 100, up: 1_000_000, down: 150_000), Self.bar(1, x: 130, up: 800_000)], env: Self.env())
    let a = try #require(out.first { $0.index == 0 && $0.up })
    let b = try #require(out.first { $0.index == 1 && $0.up })
    let dot = try #require(out.first { !$0.up })
    #expect(BigTradeBubbles.hit(a.center, in: out)?.index == 0)
    #expect(BigTradeBubbles.hit(b.center, in: out)?.index == 1)
    // 两枚热区重叠的地方取圆心近的。
    let mid = CGPoint(x: a.center.x + 12, y: a.center.y)
    #expect(BigTradeBubbles.hit(mid, in: out)?.index == 0)
    #expect(BigTradeBubbles.hit(CGPoint(x: b.center.x - 12, y: b.center.y), in: out)?.index == 1)
    // 22 以内中，出了 22 不中（泡半径小于 22 时）。
    #expect(BigTradeBubbles.hit(CGPoint(x: a.center.x - 21, y: a.center.y + 21), in: out)?.index == 0)
    #expect(BigTradeBubbles.hit(CGPoint(x: a.center.x - 23, y: a.center.y), in: out) == nil)
    // 小圆点不响应。
    #expect(BigTradeBubbles.hit(dot.center, in: out) == nil)
    #expect(BigTradeBubbles.hit(.zero, in: []) == nil)
  }

  // MARK: 读屏

  @Test func 读屏_时间_向上向下_金额() {
    let out = BigTradeBubbles.plan([Self.bar(up: 1_200_000, down: 900_000)], env: Self.env())
    let u = out.first { $0.up }!, d = out.first { !$0.up }!
    #expect(BigTradeBubbles.accessibilityLabel(u, time: "10-08 12:30", amount: "1.2M") == "10-08 12:30 向上 1.2M")
    #expect(BigTradeBubbles.accessibilityLabel(d, time: "10-08 12:30", amount: "900K") == "10-08 12:30 向下 900K")
  }
}
