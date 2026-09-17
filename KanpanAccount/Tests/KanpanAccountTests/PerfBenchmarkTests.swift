import Foundation
import XCTest

import KanpanAccount

// MARK: - 可重复的性能基准（账号同步层）
//
// 只用 public API，不 `@testable`。`SyncStore.capture` 每次都把整份归档写回磁盘，
// 所以量的是「连续攒 30 个待同步操作」的总耗时——离线画线、批量改自选走的就是这条路。

func benchMs(_ d: Duration) -> Double {
  Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
}

func benchMedian(_ xs: [Double]) -> Double {
  let s = xs.sorted()
  guard !s.isEmpty else { return .nan }
  return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

func benchP90(_ xs: [Double]) -> Double {
  let s = xs.sorted()
  guard !s.isEmpty else { return .nan }
  let k = max(1, Int((0.9 * Double(s.count)).rounded(.up)))
  return s[min(s.count - 1, k - 1)]
}

func benchPrint(_ name: String, n: Int, _ samples: [Double]) {
  print(String(format: "BENCH %@ median_ms=%.4f p90_ms=%.4f n=%d",
               name, benchMedian(samples), benchP90(samples), n))
}

@MainActor
final class PerfBenchmarkTests: XCTestCase {

  /// 连续 `capture` 30 个操作的总耗时。每轮一个全新的临时目录，
  /// 建目录与建 store 在计时区间之外。`n` 记的是操作数，不是 K 线根数。
  func testSyncStoreCapture30() throws {
    let ops = 30
    let rounds = 20, warmup = 3
    let device = UUID(uuidString: "00000000-0000-4000-8000-0000000000BE")!
    var samples: [Double] = []

    for i in 0..<(rounds + warmup) {
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("kanpan-bench-sync-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: dir) }

      let store = try SyncStore(directory: dir)
      // 30 个互不相同的对象；`capture` 只记真变化，所以每个都得是新 body。
      var objects: [SyncObject] = []
      for k in 0..<ops {
        var o = SyncObject(collection: "drawings", id: "BENCHUSDT/line-\(k)")
        o.body["kind"] = .string("trend")
        o.body["color"] = .string("#E64553")
        o.body["t0"] = .number(Double(1_600_000_000_000 + k * 3_600_000))
        o.body["p0"] = .number(30_000 + Double(k))
        o.body["t1"] = .number(Double(1_600_000_000_000 + (k + 12) * 3_600_000))
        o.body["p1"] = .number(31_000 + Double(k))
        objects.append(o)
      }

      let t = ContinuousClock.now
      for o in objects { try store.capture(o, device: device) }
      let dt = benchMs(t.duration(to: .now))
      XCTAssertEqual(store.archive.operations.count, ops)
      if i >= warmup { samples.append(dt) }
    }
    benchPrint("account.syncstore.capture_30ops", n: ops, samples)
  }
}
