import CoreGraphics
import Foundation
import Testing
@testable import KanpanChart

/// 图上大单签的纯函数：档位、一根一枚、翻面、退化、夹在主图里、命中、读屏
/// （档位与摆放用例照网页版 `Web/tests/orderflow-bigtags.test.ts` 移植，签的样子按手机原型）。
@Suite("大单签 · 纯函数")
struct BigTradeSignsTests {
  static let k = BigTradeTiers(t1: 100_000, t2: 300_000, t3: 1_000_000)

  static func env(
    spacing: CGFloat = 8, top: CGFloat = 24, bottom: CGFloat = 400, plotW: CGFloat = 800, avoid: [CGRect] = []
  ) -> BigTradeSignEnv {
    BigTradeSignEnv(
      tiers: k, spacing: spacing, top: top, bottom: bottom, plotW: plotW, avoid: avoid,
      measure: { CGFloat($0.count) * 6 }, text: { "\(Int(($0 / 1000).rounded()))K" })
  }

  static func bar(_ i: Int = 0, x: CGFloat = 100, hi: CGFloat = 100, lo: CGFloat = 200, buy: Double, sell: Double)
    -> BigTradeSignInput
  {
    BigTradeSignInput(index: i, t: Int64(i) * 60_000, x: x, hiY: hi, loY: lo, buy: buy, sell: sell)
  }

  // MARK: 档位

  @Test func 三档的线_不到t1不画() {
    #expect(BigTradeSigns.tier(of: 99_999, Self.k) == 0)
    #expect(BigTradeSigns.tier(of: 100_000, Self.k) == 1)
    #expect(BigTradeSigns.tier(of: 299_999, Self.k) == 1)
    #expect(BigTradeSigns.tier(of: 300_000, Self.k) == 2)
    #expect(BigTradeSigns.tier(of: 1_000_000, Self.k) == 3)
    #expect(BigTradeSigns.tier(of: 5, nil) == 0)
    #expect(BigTradeSigns.tier(of: 0, Self.k) == 0)
  }

  @Test func 分位数线性插值() {
    #expect(BigTradeSigns.quantile([1, 2, 3, 4, 5], 0.5) == 3)
    #expect(abs(BigTradeSigns.quantile([0, 10], 0.85) - 8.5) < 1e-9)
    #expect(BigTradeSigns.quantile([7], 0.99) == 7)
    #expect(BigTradeSigns.quantile([], 0.5) == 0)
  }

  @Test func 相对档位_P85_P95_三倍P95_垫下限() throws {
    let vals = (1...100).map { Double($0) * 1000 } + [0, 0, 0]
    let t = try #require(BigTradeSigns.tiers(vals, floor: 0))
    #expect(abs(t.t1 - 85_150) < 1e-6)
    #expect(abs(t.t2 - 95_050) < 1e-6)
    #expect(abs(t.t3 - 3 * 95_050) < 1e-6)
    #expect(vals.filter { $0 >= t.t1 }.count == 15)
    let floored = try #require(BigTradeSigns.tiers(vals, floor: 200_000))
    #expect(floored.t1 == 200_000)
    #expect(floored.t2 == 200_000)
    #expect(abs(floored.t3 - 3 * 95_050) < 1e-6)
    #expect(BigTradeSigns.tiers([0, 0], floor: 1) == nil)
  }

  // MARK: 一根一枚

  @Test func 一根一枚_大的那一侧_买在高点上_卖在低点下() throws {
    // 二档（30 万 ≤ 50 万 < 100 万）：实心三角，买挂最高价上方 4、尖朝上
    let a = BigTradeSigns.plan([Self.bar(buy: 500_000, sell: 150_000)], env: Self.env())
    #expect(a.count == 1)
    let s = try #require(a.first)
    #expect(s.buy && s.tier == 2 && s.mark == .triangle && s.capsule == nil && s.markAbove)
    #expect(s.markRect.maxY == 96 && s.markRect.width == 8 && s.markRect.height == 7)
    #expect(s.trianglePoints[2].y == s.markRect.minY)  // 尖朝上
    // 三档卖：三角在最低价下方 4、尖朝下，胶囊离三角尖 2
    let b = BigTradeSigns.plan([Self.bar(buy: 120_000, sell: 2_000_000)], env: Self.env())
    let t = try #require(b.first)
    #expect(!t.buy && t.tier == 3 && !t.markAbove)
    #expect(t.markRect.minY == 204)
    #expect(t.trianglePoints[2].y == t.markRect.maxY)  // 尖朝下
    let cap = try #require(t.capsule)
    #expect(cap.minY == t.markRect.maxY + 2 && cap.height == 16)
    #expect(cap.width == CGFloat("2000K".count) * 6 + 10)
    #expect(t.text == "2000K")
  }

  @Test func 一档是圆点_离高点3() throws {
    let s = try #require(BigTradeSigns.plan([Self.bar(buy: 150_000, sell: 0)], env: Self.env()).first)
    #expect(s.mark == .dot && s.tier == 1 && s.capsule == nil)
    #expect(s.markRect.size == CGSize(width: 5, height: 5))
    #expect(s.markRect.maxY == 97)
  }

  @Test func 没过线不画() {
    #expect(BigTradeSigns.plan([Self.bar(buy: 99_000, sell: 90_000)], env: Self.env()).isEmpty)
  }

  @Test func 密的周期三档也不出胶囊_稀的周期二档出胶囊() throws {
    let dense = try #require(BigTradeSigns.plan([Self.bar(buy: 2_000_000, sell: 0)], env: Self.env(spacing: 2)).first)
    #expect(dense.mark == .triangle && dense.capsule == nil)
    let sparse = try #require(BigTradeSigns.plan([Self.bar(buy: 500_000, sell: 0)], env: Self.env(spacing: 10)).first)
    #expect(sparse.capsule != nil)
    let mid = try #require(BigTradeSigns.plan([Self.bar(buy: 500_000, sell: 0)], env: Self.env(spacing: 6)).first)
    #expect(mid.capsule == nil)
  }

  // MARK: 翻面 / 退化

  @Test func 胶囊撞字_只把胶囊翻到另一侧_三角不动() throws {
    // 胶囊本侧在 71–87，三角在 89–96：盖住 70–86 只撞胶囊
    let s = try #require(
      BigTradeSigns.plan(
        [Self.bar(buy: 2_000_000, sell: 0)], env: Self.env(avoid: [CGRect(x: 0, y: 70, width: 300, height: 16)])
      ).first)
    #expect(s.buy && s.markAbove && s.markRect.maxY == 96)
    let cap = try #require(s.capsule)
    #expect(cap.minY == 213)  // 最低价 200 + 4 + 7 + 2
  }

  @Test func 三角也撞_整枚翻过去_颜色与朝向不变() throws {
    let s = try #require(
      BigTradeSigns.plan(
        [Self.bar(buy: 2_000_000, sell: 0)], env: Self.env(avoid: [CGRect(x: 0, y: 70, width: 300, height: 30)])
      ).first)
    #expect(s.buy && !s.markAbove && s.markRect.minY == 204)
    #expect(s.trianglePoints[2].y == s.markRect.minY)  // 买方仍尖朝上
    #expect(try #require(s.capsule).minY == 213)
  }

  @Test func 两侧胶囊都撞_退成本侧三角_三角也放不下就不画() throws {
    let avoid = [CGRect(x: 0, y: 70, width: 300, height: 16), CGRect(x: 0, y: 212, width: 300, height: 30)]
    let s = try #require(BigTradeSigns.plan([Self.bar(buy: 2_000_000, sell: 0)], env: Self.env(avoid: avoid)).first)
    #expect(s.mark == .triangle && s.capsule == nil && s.markAbove && s.markRect.maxY == 96)
    let all = [CGRect(x: 0, y: 70, width: 300, height: 30), CGRect(x: 0, y: 200, width: 300, height: 30)]
    #expect(BigTradeSigns.plan([Self.bar(buy: 2_000_000, sell: 0)], env: Self.env(avoid: all)).isEmpty)
  }

  @Test func 胶囊进图例那一带就翻面() throws {
    // 最高价在 50：胶囊会落在 21–37，顶到 24 以内的图例带；三角 39–46 不撞
    let s = try #require(BigTradeSigns.plan([Self.bar(hi: 50, buy: 2_000_000, sell: 0)], env: Self.env()).first)
    #expect(s.markAbove && s.markRect.minY >= 24)
    #expect(try #require(s.capsule).minY == 213)
    // 最高价贴着图例带：三角也放不下 → 整枚到最低价下方
    let t = try #require(BigTradeSigns.plan([Self.bar(hi: 30, buy: 2_000_000, sell: 0)], env: Self.env()).first)
    #expect(!t.markAbove && t.markRect.minY == 204)
  }

  @Test func 掉出主图下沿就翻到上方() throws {
    let s = try #require(
      BigTradeSigns.plan([Self.bar(hi: 100, lo: 330, buy: 0, sell: 2_000_000)], env: Self.env(bottom: 336)).first)
    #expect(!s.buy && s.markAbove)
    #expect(s.markRect.maxY == 96)
    #expect(s.trianglePoints[2].y == s.markRect.maxY)  // 卖方仍尖朝下
    // 两侧都放不下（上沿贴图例带、下沿贴主图底）：不画
    #expect(
      BigTradeSigns.plan([Self.bar(hi: 30, lo: 330, buy: 0, sell: 2_000_000)], env: Self.env(bottom: 336)).isEmpty)
  }

  @Test func 横向夹在主图里() throws {
    let s = try #require(BigTradeSigns.plan([Self.bar(x: 796, buy: 2_000_000, sell: 0)], env: Self.env()).first)
    let cap = try #require(s.capsule)
    #expect(cap.maxX <= 798 && cap.minX >= 2)
    let l = try #require(BigTradeSigns.plan([Self.bar(x: 3, buy: 2_000_000, sell: 0)], env: Self.env()).first)
    #expect(try #require(l.capsule).minX >= 2)
  }

  @Test func 胶囊让开横跨的那几根() throws {
    var e = Self.env()
    e.span = { _, _ in (hiY: 80, loY: 200) }  // 邻根更高
    let s = try #require(BigTradeSigns.plan([Self.bar(buy: 2_000_000, sell: 0)], env: e).first)
    #expect(try #require(s.capsule).maxY <= 78)
  }

  @Test func 胶囊与胶囊不叠_大的先占位() {
    let bars = (0..<6).map { Self.bar($0, x: 100 + CGFloat($0) * 8, buy: 1_000_000 + Double($0) * 1000, sell: 0) }
    let signs = BigTradeSigns.plan(bars, env: Self.env())
    #expect(signs.count == 6)
    let caps = signs.compactMap(\.capsule)
    #expect(!caps.isEmpty)
    for a in 0..<caps.count { for b in (a + 1)..<caps.count { #expect(!caps[a].intersects(caps[b])) } }
    // 金额最大的（最后一根）必然拿到胶囊
    #expect(signs.last?.capsule != nil)
    #expect(signs.map(\.index) == Array(0..<6))
  }

  @Test func 和画线文字零相交() {
    var rng = BigTradeRNG(seed: 42)
    for _ in 0..<200 {
      let avoid = (0..<4).map { _ in
        CGRect(x: rng.next(0, 700), y: rng.next(24, 380), width: rng.next(20, 120), height: rng.next(12, 20))
      }
      let bars = (0..<80).map { i -> BigTradeSignInput in
        let hi = rng.next(30, 300)
        return Self.bar(
          i, x: 4 + CGFloat(i) * 9.5, hi: hi, lo: hi + rng.next(2, 80), buy: Double(rng.next(0, 3_000_000)),
          sell: Double(rng.next(0, 3_000_000)))
      }
      let signs = BigTradeSigns.plan(bars, env: Self.env(spacing: 9.5, avoid: avoid))
      for s in signs {
        for a in avoid {
          #expect(!a.intersects(s.markRect))
          if let c = s.capsule { #expect(!a.intersects(c)) }
        }
        #expect(s.bounds.minY >= 24 && s.bounds.maxY <= 400)
      }
    }
  }

  // MARK: 命中

  @Test func 命中_44热区_取最近的那枚() throws {
    let a = Self.bar(0, x: 100, buy: 500_000, sell: 0)
    let b = Self.bar(1, x: 112, buy: 600_000, sell: 0)
    let signs = BigTradeSigns.plan([a, b], env: Self.env())
    #expect(signs.count == 2)
    let ca = signs[0].markCenter
    #expect(BigTradeSigns.hit(CGPoint(x: ca.x - 20, y: ca.y + 20), in: signs)?.index == 0)
    #expect(BigTradeSigns.hit(CGPoint(x: 107, y: ca.y), in: signs)?.index == 1)
    #expect(BigTradeSigns.hit(CGPoint(x: 104, y: ca.y), in: signs)?.index == 0)
    #expect(BigTradeSigns.hit(CGPoint(x: ca.x, y: ca.y - 30), in: signs) == nil)
    #expect(BigTradeSigns.hit(CGPoint(x: 300, y: 300), in: signs) == nil)
  }

  @Test func 命中胶囊整块() throws {
    let s = try #require(
      BigTradeSigns.plan(
        [Self.bar(buy: 2_000_000, sell: 0)], env: Self.env(avoid: [CGRect(x: 0, y: 70, width: 300, height: 16)])
      ).first)
    let cap = try #require(s.capsule)
    #expect(BigTradeSigns.hit(CGPoint(x: cap.midX, y: cap.midY), in: [s])?.index == 0)
  }

  @Test func 读屏文案() throws {
    let s = try #require(BigTradeSigns.plan([Self.bar(buy: 1_200_000, sell: 0)], env: Self.env()).first)
    #expect(BigTradeSigns.accessibilityLabel(s, time: "12:30") == "买方大单 1200K，12:30 这根")
  }
}

/// 可复现的随机数（测试里撒随机 K 线与文字框）。
struct BigTradeRNG {
  var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func nextU() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
  mutating func next(_ lo: Double, _ hi: Double) -> CGFloat {
    CGFloat(lo + (hi - lo) * Double(nextU() >> 11) / Double(1 << 53))
  }
}
