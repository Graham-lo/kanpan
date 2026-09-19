import Darwin
import Foundation
import XCTest

import KanpanCore

// MARK: - 末根更新的「所有权」基准（GPT Pro 二轮审查 A5）
//
// 只用 public API，不 `@testable`：同一份文件要能原样复制到改动前／改动后的代码上再跑。
//
// 量的是一件事：**一次末根更新的成本，是不是跟着历史长度 N 走**。
// 递推算术本身只碰最后 K 根（K = `tailBars`，几十根），所以时间如果随 N 线性涨，
// 涨的一定不是算术，而是数组所有权——引擎同时攥着 `states` 与 `values`，
// 两边指着同一块缓冲，写时复制（COW）就得把整列 N 个 Double 搬一遍。
//
// 「分配量」这里不用 `malloc_zone_statistics` 的 `blocks_in_use`：COW 是
// 「新开一块 + 放掉旧的一块」，活块数净变化是 0，读出来永远是 0，什么都证明不了
// （`size_allocated` 在 macOS 的 magazine zone 上恒为 0，更没用）。
// 真正要数的是**整列重新分配了几次**，所以直接盯缓冲区首地址：
// 一次更新前后某条线的 `baseAddress` 变了，就说明这条线被整列复制过一遍——
// 首地址取完立刻丢掉快照，不会因为量测本身把引用数抬起来、反过来制造 COW。
// 每次更新复制的字节数 = 变址的线数 × N × 8。

/// 把一台引擎当下发布出来的每条线（含 MACD 的柱）的缓冲区首地址取出来。
///
/// 快照只在语句内活着，取完就放——它要是被攥到下一次更新之后，
/// 量到的就是「因为在量所以复制」了。
func benchLineAddresses(_ engine: IndicatorEngine, _ ids: [IndicatorID]) -> [UInt] {
  var out: [UInt] = []
  out.reserveCapacity(16)
  for id in ids {
    guard let r = engine[id] else { continue }
    for line in r.lines {
      out.append(line.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) })
    }
    if let h = r.histogram {
      out.append(h.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) })
    }
  }
  return out
}

/// 换掉末根：同一根 K 线被新的成交价改写，正是行情每个 tick 干的事。
func benchTickedLast(_ series: BarSeries, _ r: inout BenchRNG) -> Bar {
  let last = series.bar(at: series.count - 1)
  let c = max(1, last.open * (1 + r.range(-0.012, 0.012)))
  return Bar(
    openTime: last.openTime, open: last.open,
    high: max(last.open, c) * (1 + r.range(0, 0.006)),
    low: min(last.open, c) * (1 - r.range(0, 0.006)),
    close: c, volume: last.volume + r.range(1, 50))
}

final class PerfBenchmarkTailOwnershipTests: XCTestCase {
  static let counts = [500, 2000, 5000, 10000]
  /// MA（三条）+ BOLL + MACD + KDJ + RSI（三条）＝ 15 条发布出来的列。
  static let wanted: [IndicatorID] = [.ma, .boll, .macd, .kdj, .rsi]
  static let rounds = 200
  static let warmup = 10

  func testTailUpdateOwnership() {
    print("BENCH-TABLE core.indicator.tail.ownership 指标=MA×3+BOLL+MACD+KDJ+RSI"
      + " 每档 \(Self.rounds) 次末根更新（warmup \(Self.warmup)）")
    for n in Self.counts {
      var series = benchSeries(count: n)
      var engine = IndicatorEngine()
      engine.ensure(series: series, wanted: Self.wanted, dataKey: "bench")

      var r = BenchRNG(seed: 987_654_321)
      var samples: [Double] = []
      samples.reserveCapacity(Self.rounds)
      var reallocs = 0
      var lineCount = benchLineAddresses(engine, Self.wanted).count

      for i in 0..<(Self.warmup + Self.rounds) {
        series.replaceLast(with: benchTickedLast(series, &r))
        let before = benchLineAddresses(engine, Self.wanted)
        let t = ContinuousClock.now
        engine.updateTail(series: series, dataKey: "bench")
        let dt = benchMs(t.duration(to: .now))
        benchKeep(engine[.macd])
        let after = benchLineAddresses(engine, Self.wanted)
        lineCount = after.count
        if i >= Self.warmup {
          samples.append(dt)
          reallocs += zip(before, after).reduce(0) { $0 + ($1.0 == $1.1 ? 0 : 1) }
        }
      }

      let perUpdate = Double(reallocs) / Double(Self.rounds)
      let bytes = perUpdate * Double(n) * 8
      print(String(
        format: "BENCH tail.ownership N=%5d median_ms=%.4f p90_ms=%.4f"
          + " realloc_lines_per_update=%.2f/%d copied_bytes_per_update=%.0f",
        n, benchMedian(samples), benchP90(samples), perUpdate, lineCount, bytes))
    }
  }

  /// 值语义：手里攥着的旧快照，不许被后来的更新改掉。
  ///
  /// 这条和上面的基准是一体两面——发布出来的列如果和引擎内部的状态共用一块缓冲，
  /// 又没有写时复制兜着，更新就会当着调用方的面改掉它手里的数。
  func testPublishedSnapshotIsNotMutatedByLaterUpdates() {
    var series = benchSeries(count: 1200)
    var engine = IndicatorEngine()
    engine.ensure(series: series, wanted: Self.wanted, dataKey: "snap")
    let snapshot = Dictionary(uniqueKeysWithValues: Self.wanted.map { ($0, engine[$0]!) })

    var r = BenchRNG(seed: 13579)
    for i in 0..<60 {
      if i % 3 == 2 {
        let last = series.bar(at: series.count - 1)
        let c = max(1, last.close * (1 + r.range(-0.012, 0.012)))
        series.append(Bar(
          openTime: last.openTime + series.step, open: last.close,
          high: max(last.close, c) * 1.001, low: min(last.close, c) * 0.999,
          close: c, volume: r.range(10, 5000)))
      } else {
        series.replaceLast(with: benchTickedLast(series, &r))
      }
      engine.updateTail(series: series, dataKey: "snap")
    }

    for id in Self.wanted {
      let old = snapshot[id]!
      let now = engine[id]!
      XCTAssertEqual(old.lines.count, now.lines.count, "\(id) 线数变了")
      XCTAssertEqual(old.lines[0].count, 1200, "\(id) 旧快照的长度被后来的更新改了")
      // 尾巴一定动过（不然这条测试等于没测），前缀一定没动。
      var tailMoved = false
      for (k, line) in old.lines.enumerated() {
        for i in 0..<line.count where line[i].isFinite {
          let fresh = now.lines[k][i]
          if i < 1150 {
            XCTAssertEqual(line[i], fresh, accuracy: 1e-9,
                           "\(id) 第 \(k) 条线第 \(i) 根：旧快照被改写了")
          } else if fresh != line[i] {
            tailMoved = true
          }
        }
      }
      XCTAssertTrue(tailMoved, "\(id) 更新之后尾巴一个数都没变，这条测试没测到东西")
    }
  }
}
