import Foundation
import Testing
@testable import KanpanCore

/// 指标名与出厂参数的唯一一份：`KanpanCore/Sources/KanpanCore/Indicator/indicators.json`。
/// 手机网页与电脑网页读的是同一个文件，这里守住它和 `IndicatorID` 一一对上。
@Suite("指标目录 indicators.json")
struct IndicatorCatalogTests {
  /// 直接读包里的原始 JSON（不经 `catalog` 的过滤），多出来的键也看得见。
  private func rawKeys() throws -> Set<String> {
    let url = try #require(IndicatorID.catalogURL)
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    return Set(try #require(object as? [String: Any]).keys)
  }

  @Test("每个 IndicatorID 都有一项、名字非空，也没有多出来的键")
  func everyCaseHasAnEntry() throws {
    for id in IndicatorID.allCases {
      let entry = try #require(IndicatorID.catalog[id], "\(id.rawValue) 在 indicators.json 里没有")
      #expect(!entry.name.trimmingCharacters(in: .whitespaces).isEmpty, "\(id.rawValue) 名字是空的")
    }
    #expect(try rawKeys() == Set(IndicatorID.allCases.map(\.rawValue)))
  }

  @Test("名字与出厂参数从 JSON 来")
  func readsTheSharedFile() {
    #expect(IndicatorID.macd.name == "MACD")
    #expect(IndicatorID.cvd.name == "累计量差")
    #expect(IndicatorID.vwap.name == "VWAP")
    #expect(IndicatorID.rsi.defaultParams == [14])
    #expect(IndicatorID.allCases.allSatisfy { $0.defaultParams == IndicatorID.catalog[$0]?.params })
  }

  @Test("强弱是按列表画的：条数随用户、标签按周期1…N、线名跟着周期")
  func rsiHasVariablePeriods() {
    #expect(IndicatorID.rsi.hasVariablePeriods)
    #expect(IndicatorID.rsi.paramLabels == ["周期1"])
    #expect(IndicatorID.rsi.normalizedParams([6, 12, 24]) == [6, 12, 24])
    #expect(IndicatorID.rsi.lineNames(params: [6, 12, 24]) == ["RSI6", "RSI12", "RSI24"])
    #expect(IndicatorID.rsi.guides == [30, 70])
  }
}
