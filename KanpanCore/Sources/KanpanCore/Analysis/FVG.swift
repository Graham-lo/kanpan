import Foundation

// 公允价值缺口（三根 K 线失衡缺口）。只画几何事实，不下判定。
//
// 口径三端一份：iOS 这里、手机网页与电脑网页共用 `Web/src/analysis/fvg.ts`，
// 两边对同一份黄金样例 `KanpanCoreTests/Fixtures/fvg.json` 逐位一致。参数只在 `Analysis/fvg.json`。

/// 缺口参数。**唯一一份在 `Analysis/fvg.json`**（三端共读），不开放给用户设置。
public struct FVGConfig: Codable, Sendable, Equatable {
  /// 波幅参考：最近这么多根真实波幅的简单平均（不用 Wilder 递归，只依赖本地几根，加载多少历史都一样）。
  public var trPeriod: Int
  /// 缺口高度至少是波幅参考的这么多倍，才算数。
  public var minTrRatio: Double
  /// 只保留第三根落在最近这么多根 K 线里的缺口。
  public var maxAgeBars: Int
  /// 每边（多 / 空）最多留这么多个，留最近的。
  public var perSide: Int

  public init(trPeriod: Int, minTrRatio: Double, maxAgeBars: Int, perSide: Int) {
    self.trPeriod = trPeriod
    self.minTrRatio = minTrRatio
    self.maxAgeBars = maxAgeBars
    self.perSide = perSide
  }

  /// 包里那份 `fvg.json`，解一次、常驻。
  static var url: URL? { Bundle.module.url(forResource: "fvg", withExtension: "json") }

  /// 出厂参数。资源缺了或坏了是打包事故：调试包当场断言，发布包退回「一个都不画」，不崩、也不另抄一份数。
  public static let standard: FVGConfig = {
    guard let url, let data = try? Data(contentsOf: url),
          let config = try? JSONDecoder().decode(FVGConfig.self, from: data)
    else {
      assertionFailure("KanpanCore 资源 fvg.json 缺失或解不出来")
      return FVGConfig(trPeriod: 1, minTrRatio: 0, maxAgeBars: 0, perSide: 0)
    }
    return config
  }()
}

/// 缺口方向：多头（下方留空，价格回落进来会回补）/ 空头（上方留空）。
public enum FVGSide: String, Sendable {
  case bull, bear
}

/// 一个还没被完全回补的缺口。
public struct FVGZone: Equatable, Sendable {
  public var side: FVGSide
  /// 中间那根（三根里的第二根）的开盘时间；盒子从它的左沿画起。
  public var startMs: Int64
  /// 回补收缩后剩下的上沿 / 下沿。
  public var top: Double
  public var bottom: Double
  /// 原始缺口的 50% 位置，收缩时不动。
  public var mid: Double
  /// 中线还在剩下的盒子里面（被回补过中线就不画）。
  public var midVisible: Bool

  public init(side: FVGSide, startMs: Int64, top: Double, bottom: Double, mid: Double, midVisible: Bool) {
    self.side = side
    self.startMs = startMs
    self.top = top
    self.bottom = bottom
    self.mid = mid
    self.midVisible = midVisible
  }
}

/// 算当前还在的缺口。
///
/// - `closedCount`：前多少根已收线。只有收线的 K 线能生成缺口（正在走的那根不参与生成，不会重绘），
///   但之后的每一根（含正在走的那根）都参与回补。
/// - 返回按 `startMs` 升序（同一时刻多头在前）。
public func fvgZones(bars: [Bar], closedCount: Int, config: FVGConfig = .standard) -> [FVGZone] {
  FVGScan.run(
    count: bars.count, closedCount: closedCount, config: config,
    time: { bars[$0].openTime },
    high: bars.map(\.high), low: bars.map(\.low), close: bars.map(\.close))
}

/// 同上，直接吃列式序列（图表里用的那份），不拆成单根。
public func fvgZones(series: BarSeries, closedCount: Int, config: FVGConfig = .standard) -> [FVGZone] {
  FVGScan.run(
    count: series.count, closedCount: closedCount, config: config,
    time: { series.time(at: $0) },
    high: series.high, low: series.low, close: series.close)
}

enum FVGScan {
  /// 一遍扫：到第 j 根先让它回补已有的缺口，再看它能不能（作为第三根）生成新缺口。
  /// 生成只在最近 `maxAgeBars` 根里发生，所以从那里起扫就够了，O(根数 × 在场缺口数)。
  static func run(
    count n: Int, closedCount: Int, config: FVGConfig,
    time: (Int) -> Int64, high h: [Double], low l: [Double], close c: [Double]
  ) -> [FVGZone] {
    guard config.perSide > 0 else { return [] }
    let p = max(1, config.trPeriod)
    let closed = min(max(closedCount, 0), n)
    // 波幅参考要第 i-p … i 根（第 i-p+1 根的真实波幅要用前一根收盘），所以 i ≥ p。
    let genStart = max(2, p, n - config.maxAgeBars)
    guard genStart < closed else { return [] }

    func trueRange(_ k: Int) -> Double {
      k == 0 ? h[0] - l[0] : max(h[k] - l[k], abs(h[k] - c[k - 1]), abs(l[k] - c[k - 1]))
    }

    var active: [FVGZone] = []
    for j in genStart..<n {
      // 回补：价格进到盒子里就收缩到剩下没补的部分，穿过去就删掉。
      if !active.isEmpty {
        let hj = h[j], lj = l[j]
        var w = 0
        for r in active.indices {
          var z = active[r]
          let filled: Bool
          switch z.side {
          case .bull:
            if lj < z.top { z.top = lj }
            filled = lj <= z.bottom
          case .bear:
            if hj > z.bottom { z.bottom = hj }
            filled = hj >= z.top
          }
          if !filled { active[w] = z; w += 1 }
        }
        active.removeLast(active.count - w)
      }
      guard j < closed else { continue }
      // 生成：第 j 根是第三根。
      let i = j
      var zone: FVGZone?
      if l[i] > h[i - 2] {
        zone = FVGZone(side: .bull, startMs: time(i - 1), top: l[i], bottom: h[i - 2], mid: 0, midVisible: true)
      } else if h[i] < l[i - 2] {
        zone = FVGZone(side: .bear, startMs: time(i - 1), top: l[i - 2], bottom: h[i], mid: 0, midVisible: true)
      }
      guard var z = zone else { continue }
      // 波幅参考就地算（按下标升序累加），不用前缀和：前缀和相减的舍入会随加载的历史长短变。
      var sum = 0.0
      for k in (i - p + 1)...i { sum += trueRange(k) }
      let ref = sum / Double(p)
      guard z.top - z.bottom >= config.minTrRatio * ref else { continue }
      z.mid = (z.top + z.bottom) / 2
      active.append(z)
    }

    // 在场列表按生成先后排，也就是 startMs 升序；每边留最后 perSide 个。
    var bulls: [FVGZone] = [], bears: [FVGZone] = []
    for var z in active {
      z.midVisible = z.bottom < z.mid && z.mid < z.top
      if z.side == .bull { bulls.append(z) } else { bears.append(z) }
    }
    let keepBull = bulls.suffix(config.perSide), keepBear = bears.suffix(config.perSide)
    var out: [FVGZone] = []
    out.reserveCapacity(keepBull.count + keepBear.count)
    var a = keepBull.startIndex, b = keepBear.startIndex
    while a < keepBull.endIndex || b < keepBear.endIndex {
      if b == keepBear.endIndex || (a < keepBull.endIndex && keepBull[a].startMs <= keepBear[b].startMs) {
        out.append(keepBull[a]); a += 1
      } else {
        out.append(keepBear[b]); b += 1
      }
    }
    return out
  }
}
