import Foundation
import Testing

@testable import KanpanDiagnostics

/// 每个用例一个独立临时目录，跑完删掉。共用一个目录会让淘汰用例互相污染。
private func makeTempDir() -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("kanpan-diag-\(UUID().uuidString)", isDirectory: true)
  try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

@Suite("诊断落盘")
struct DiagnosticsStoreTests {

  @Test("收一份 metric payload：原文和摘要都在盘上")
  func ingestMetric() throws {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = DiagnosticsStore(directory: dir)

    let record = try #require(store.ingest(PayloadFixtures.metricPayload(), kind: .metric))
    #expect(record.kind == .metric)
    #expect(record.digest?.cumulativeLogicalWritesKB == 240)
    // 原文必须原样留着：摘要抽漏了字段的时候要能回去翻。
    #expect(record.payload != nil)
    #expect(record.payloadBase64 == nil)

    // 重新从盘上读一遍：除了时间戳，其余必须一模一样。
    // `receivedAt` 落盘走 ISO8601（为了人能直接看懂文件），精度只到秒，
    // 所以往返回来差几十毫秒是**设计如此**，不是 bug——比较时按秒对。
    let back = store.records()
    #expect(back.count == 1)
    let read = try #require(back.first)
    #expect(read.id == record.id)
    #expect(read.kind == record.kind)
    #expect(read.digest == record.digest)
    #expect(read.payload == record.payload)
    #expect(abs(read.receivedAt.timeIntervalSince(record.receivedAt)) < 1)
  }

  @Test("原文里我们不看的字段也一个不少地留着")
  func keepsUnknownFields() throws {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = DiagnosticsStore(directory: dir)
    store.ingest(PayloadFixtures.metricPayload(), kind: .metric)

    let bundle = store.exportBundle()
    let data = try DiagnosticsStore.encoder.encode(bundle)
    let text = String(decoding: data, as: UTF8.self)
    // gpuMetrics / cellularConditionMetrics 是摘要不看的，但导出里必须找得到。
    #expect(text.contains("cumulativeGPUTime"))
    #expect(text.contains("cellConditionTime"))
  }

  @Test("JSON 坏掉照样存字节，退到 base64")
  func brokenPayloadStillStored() throws {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = DiagnosticsStore(directory: dir)

    let junk = Data([0x00, 0x01, 0xFF, 0xFE])
    let record = try #require(store.ingest(junk, kind: .diagnostic))
    #expect(record.digest == nil)  // 解不出摘要
    #expect(record.payload == nil)
    #expect(Data(base64Encoded: try #require(record.payloadBase64)) == junk)
  }

  @Test("导出汇总：崩溃数、最坏启动 p50、最近磁盘写入")
  func exportBundle() {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let clock = TestClock()
    let store = DiagnosticsStore(directory: dir, clock: clock.now)

    // 第一天：启动 p50 = 350
    store.ingest(PayloadFixtures.metricPayload(), kind: .metric)
    clock.advance(86_400)
    // 第二天：启动慢，p50 = 650；磁盘写入 512 kB
    store.ingest(
      PayloadFixtures.metricPayload(
        launchBuckets: [("600 ms", "700 ms", 5)], writes: "512 kB"),
      kind: .metric)
    clock.advance(60)
    store.ingest(PayloadFixtures.crashPayload(), kind: .diagnostic)
    clock.advance(60)
    store.ingest(PayloadFixtures.mixedDiagnosticPayload(), kind: .diagnostic)

    let b = store.exportBundle()
    #expect(b.recordCount == 4)
    #expect(b.crashCount == 1)
    #expect(b.hangCount == 1)
    #expect(b.worstLaunchP50Ms == 650)  // 取最坏的那天，不是最新那天
    // 诊断 payload 不带磁盘数，所以这里必须是「最近一份**有**这项的」= 512。
    #expect(b.latestLogicalWritesKB == 512)
    #expect(b.crashFree == false)
  }

  @Test("一条记录都没有时 crashFree 是 nil，不是 true")
  func emptyIsNotPass() {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = DiagnosticsStore(directory: dir)
    // P9.7 是「MetricKit 崩溃报告为空」。刚装上还没收到任何 payload 时，
    // 报 true 等于把「没测」说成「过了」。
    #expect(store.exportBundle().crashFree == nil)

    store.ingest(PayloadFixtures.cleanDiagnosticPayload(), kind: .diagnostic)
    #expect(store.exportBundle().crashFree == true)
  }

  @Test("条数超上限，从最旧的开始删")
  func prunesByCount() {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let clock = TestClock()
    let store = DiagnosticsStore(
      directory: dir, limits: .init(maxRecords: 3, maxBytes: 10 * 1024 * 1024), clock: clock.now)

    for i in 0..<6 {
      store.ingest(PayloadFixtures.metricPayload(build: "\(i)"), kind: .metric)
      clock.advance(60)
    }
    let kept = store.records()
    #expect(kept.count == 3)
    #expect(kept.compactMap { $0.digest?.appBuildVersion } == ["3", "4", "5"])
  }

  @Test("字节超上限也删最旧的，但最新那条永远留着")
  func prunesByBytes() throws {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let clock = TestClock()
    // 上限设成 1 字节：任何一份都超。这时候还把最新那份删掉的话，
    // 刚收到的崩溃报告会被自己的清理逻辑吃掉——这是最不能出的 bug。
    let store = DiagnosticsStore(
      directory: dir, limits: .init(maxRecords: 100, maxBytes: 1), clock: clock.now)

    for i in 0..<4 {
      store.ingest(PayloadFixtures.metricPayload(build: "\(i)"), kind: .metric)
      clock.advance(60)
    }
    let kept = store.records()
    #expect(kept.count == 1)
    #expect(kept.first?.digest?.appBuildVersion == "3")
  }

  @Test("同一份 payload 收两次（冷启动补收 pastPayloads），盘上只有一份")
  func ingestIsIdempotent() throws {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let clock = TestClock()
    let store = DiagnosticsStore(directory: dir, clock: clock.now)

    let crash = PayloadFixtures.crashPayload()
    #expect(store.ingest(crash, kind: .diagnostic) != nil)
    clock.advance(86_400)
    // 第二天冷启动：系统把同一份放在 pastDiagnosticPayloads 里又递了一遍。
    #expect(store.ingest(crash, kind: .diagnostic) == nil)
    // 换一个进程（新的 store 实例、索引和账本都从盘上读）也一样认得出来。
    let reopened = DiagnosticsStore(directory: dir, clock: clock.now)
    #expect(reopened.ingest(crash, kind: .diagnostic) == nil)
    #expect(reopened.exportBundle().crashCount == 1)
    #expect(reopened.records().count == 1)
    // 不同的 payload 照收。
    #expect(reopened.ingest(PayloadFixtures.metricPayload(), kind: .metric) != nil)
    #expect(reopened.records().count == 2)
  }

  @Test("键的顺序不同也算同一份；同样的字节换个 kind 是另一份")
  func fingerprintIsCanonical() throws {
    let a = Data(#"{"b":1,"a":{"y":2,"x":3}}"#.utf8)
    let b = Data(#"{"a":{"x":3,"y":2},"b":1}"#.utf8)
    func fp(_ d: Data, _ k: PayloadKind) -> String {
      DiagnosticsStore.fingerprint(
        of: try? JSONDecoder().decode(JSONValue.self, from: d), raw: d, kind: k)
    }
    #expect(fp(a, .metric) == fp(b, .metric))
    #expect(fp(a, .metric) != fp(a, .diagnostic))
  }

  @Test("被淘汰掉的那份再递过来也不回来")
  func evictedPayloadStaysEvicted() {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let clock = TestClock()
    let store = DiagnosticsStore(
      directory: dir, limits: .init(maxRecords: 2, maxBytes: 10 * 1024 * 1024), clock: clock.now)
    for i in 0..<3 {
      store.ingest(PayloadFixtures.metricPayload(build: "\(i)"), kind: .metric)
      clock.advance(60)
    }
    // build 0 已被挤掉；下次冷启动它还在 pastPayloads 里。
    #expect(store.ingest(PayloadFixtures.metricPayload(build: "0"), kind: .metric) == nil)
    #expect(store.records().compactMap { $0.digest?.appBuildVersion } == ["1", "2"])
  }

  @Test("文件名按毫秒时间戳排，ls 出来就是时间序")
  func fileNamesSortByTime() {
    let a = DiagnosticsStore.fileName(
      kind: .metric, at: Date(timeIntervalSince1970: 1000), id: "AAAAAAAA-x")
    let b = DiagnosticsStore.fileName(
      kind: .metric, at: Date(timeIntervalSince1970: 2000), id: "BBBBBBBB-x")
    #expect(a < b)
    #expect(a.hasPrefix("metric-"))
    #expect(a.hasSuffix(".json"))
  }

  @Test("写导出文件 + 占用字节 + 清空")
  func exportAndClear() throws {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = DiagnosticsStore(directory: dir)
    store.ingest(PayloadFixtures.metricPayload(), kind: .metric)
    #expect(store.diskUsageBytes() > 0)

    let out = dir.appendingPathComponent("export/M9-diagnostics.json")
    try store.writeExport(to: out)
    let back = try DiagnosticsStore.decoder.decode(
      DiagnosticsBundle.self, from: Data(contentsOf: out))
    #expect(back.recordCount == 1)

    store.removeAll()
    #expect(store.records().isEmpty)
    #expect(store.diskUsageBytes() == 0)
  }
}

@Suite("诊断中枢")
struct DiagnosticsCenterTests {

  @Test("注入的假 payload 走的是和真回调同一条路")
  func simulateReceive() throws {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let center = DiagnosticsCenter(store: DiagnosticsStore(directory: dir))

    // 模拟器上 MetricKit 永远不回调，所以这是模拟器 / mac 上唯一能验的入口。
    // 它调的就是 `store.ingest`——和 `didReceive(_:)` 里那一行一模一样。
    #expect(center.simulateReceive(PayloadFixtures.metricPayload(), kind: .metric) != nil)
    #expect(center.simulateReceive(PayloadFixtures.crashPayload(), kind: .diagnostic) != nil)

    let b = center.store.exportBundle()
    #expect(b.recordCount == 2)
    #expect(b.crashCount == 1)
    #expect(b.crashFree == false)
  }

  @Test("重复 start 是幂等的")
  func startIsIdempotent() {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let center = DiagnosticsCenter(store: DiagnosticsStore(directory: dir))
    // mac / 模拟器上 start 里的 MetricKit 分支整块被 `#if os(iOS)` 编掉，
    // 这里验的是外层的幂等开关本身不会炸、不会重复补收历史 payload。
    center.start()
    center.start()
    center.stop()
    center.stop()
    #expect(center.store.records().isEmpty)
  }
}
