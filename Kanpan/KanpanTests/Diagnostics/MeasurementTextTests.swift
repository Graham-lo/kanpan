import Foundation
import Testing

@testable import Kanpan

// MetricKit 把所有物理量写成 `"500 ms"` 这种带单位的字符串（见 MeasurementText.swift
// 开头的说明）。这一套件把解析的边界全钉死——它是整条诊断链上唯一会因为系统改文案
// 而碎掉的地方，碎了要第一时间知道。

@Suite("带单位字符串解析")
struct MeasurementTextTests {

  @Test("时间单位逐个换算到毫秒")
  func timeUnits() {
    #expect(MeasurementText.milliseconds("500 ms") == 500)
    #expect(MeasurementText.milliseconds("2 s") == 2000)
    #expect(MeasurementText.milliseconds("2.5 sec") == 2500)
    #expect(MeasurementText.milliseconds("1500 µs") == 1.5)
    #expect(MeasurementText.milliseconds("1500 us") == 1.5)
    #expect(MeasurementText.milliseconds("1 min") == 60_000)
  }

  @Test("`2 ms` 不能被 `s` 抢先命中")
  func longestSuffixWins() {
    // 后缀表里同时有 "ms" 和 "s"，短的先匹配就会把 2ms 算成 2000ms——
    // 差 1000 倍，而且看着是个合理的数，不会有人怀疑。
    #expect(MeasurementText.milliseconds("2 ms") == 2)
    #expect(MeasurementText.milliseconds("2 s") == 2000)
  }

  @Test("存储单位是 1000 进制，和 MXUnitStorage 一致")
  func byteUnits() {
    #expect(MeasurementText.kilobytes("12 kB") == 12)
    #expect(MeasurementText.kilobytes("3 MB") == 3000)
    // MetricKit 真出过小写 `mB` 这种拼法。
    #expect(MeasurementText.kilobytes("3 mB") == 3000)
    #expect(MeasurementText.kilobytes("2 GB") == 2_000_000)
    #expect(MeasurementText.kilobytes("500 bytes") == 0.5)
  }

  @Test("没单位按默认单位算，负数和小数都收")
  func bareNumbers() {
    #expect(MeasurementText.milliseconds("42") == 42)
    #expect(MeasurementText.milliseconds("-3.5") == -3.5)
    #expect(MeasurementText.kilobytes("0") == 0)
  }

  @Test("解析不了返回 nil，绝不返回 0")
  func failuresAreNilNotZero() {
    // 0 会被当成「这项指标很好」写进证据表，那是在说谎。
    #expect(MeasurementText.milliseconds(nil) == nil)
    #expect(MeasurementText.milliseconds("") == nil)
    #expect(MeasurementText.milliseconds("   ") == nil)
    #expect(MeasurementText.milliseconds("很快") == nil)
    #expect(MeasurementText.milliseconds("100 parsecs") == nil)
    #expect(MeasurementText.kilobytes("好多") == nil)
  }

  @Test("JSON 里已经是数字时直接收下")
  func acceptsNumbers() {
    #expect(MeasurementText.milliseconds(any: NSNumber(value: 7)) == 7)
    #expect(MeasurementText.kilobytes(any: NSNumber(value: 1.5)) == 1.5)
    #expect(MeasurementText.milliseconds(any: "8 ms") == 8)
    #expect(MeasurementText.milliseconds(any: [1, 2]) == nil)
  }
}

@Suite("直方图")
struct HistogramTests {

  /// 造一个 MXHistogram 形状的 JSON。桶故意**乱序**给，验解析会自己排。
  private func histogram(_ buckets: [(start: String, end: String, count: Int)]) -> [String: Any] {
    var values: [String: Any] = [:]
    for (i, b) in buckets.enumerated() {
      values["\(i)"] = ["bucketStart": b.start, "bucketEnd": b.end, "bucketCount": b.count]
    }
    return ["histogramNumBuckets": buckets.count, "histogramValue": values]
  }

  @Test("桶乱序进来也要按 start 排好")
  func sortsBuckets() {
    let h = ParsedHistogram.parse(
      histogram([
        ("300 ms", "400 ms", 1),
        ("100 ms", "200 ms", 5),
        ("200 ms", "300 ms", 2),
      ]), unit: .milliseconds)
    #expect(h.buckets.map(\.start) == [100, 200, 300])
    #expect(h.totalCount == 8)
  }

  @Test("分位数取命中桶的中点")
  func percentiles() throws {
    // 8 个样本：[100,200) × 5、[200,300) × 2、[300,400) × 1
    let h = ParsedHistogram.parse(
      histogram([("100 ms", "200 ms", 5), ("200 ms", "300 ms", 2), ("300 ms", "400 ms", 1)]),
      unit: .milliseconds)
    // p50 → 第 4 个样本，落在第一个桶，中点 150
    #expect(h.percentile(0.5) == 150)
    // p90 → 第 7.2 个样本。前两桶累计才 7 个，不够，落到第三桶 → 中点 350。
    // （桶粒度就是这么粗：8 个样本里 p90 只能报「最后那个桶」。）
    #expect(h.percentile(0.9) == 350)
    #expect(h.maximum == 400)
    // 加权平均：(150×5 + 250×2 + 350×1) / 8 = 200
    let mean = try #require(h.mean)
    #expect(abs(mean - 200) < 1e-9)
  }

  @Test("空直方图不产出任何数")
  func emptyHistogram() {
    let h = ParsedHistogram.parse(histogram([]), unit: .milliseconds)
    #expect(h.isEmpty)
    #expect(h.percentile(0.5) == nil)
    #expect(h.mean == nil)
    #expect(PayloadDigest.Percentiles(h) == nil)

    // 结构不对（不是字典、缺 histogramValue）也要安静地空掉，不崩。
    #expect(ParsedHistogram.parse(nil, unit: .milliseconds).isEmpty)
    #expect(ParsedHistogram.parse(["histogramNumBuckets": 3], unit: .milliseconds).isEmpty)
    #expect(ParsedHistogram.parse("不是字典", unit: .milliseconds).isEmpty)
  }

  @Test("桶边界解析不了就整桶丢掉，不是当 0")
  func badBucketDropped() {
    let h = ParsedHistogram.parse(
      histogram([("100 ms", "200 ms", 5), ("不知道", "更不知道", 99)]), unit: .milliseconds)
    #expect(h.buckets.count == 1)
    #expect(h.totalCount == 5)
  }

  @Test("存储单位的直方图走 KB 口径")
  func storageHistogram() {
    let h = ParsedHistogram.parse(
      histogram([("1 MB", "2 MB", 3)]), unit: .kilobytes)
    #expect(h.buckets.first?.start == 1000)
    #expect(h.buckets.first?.end == 2000)
  }
}
