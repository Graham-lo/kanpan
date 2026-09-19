import Foundation
import Testing

@testable import KanpanCore

/// B-T11：`underlyingType` → 品种大类这张表，服务端（Rust `kanpan-api`）和客户端各有一份，
/// 这条用例让两边对着**同一份文件**说话：
///
///   KanpanCore/Tests/KanpanCoreTests/Fixtures/underlying_kinds.json
///
/// 每行四列：交易所字段 `underlyingType`、服务端的 `kind`、客户端的资产大类与地区。
/// 服务端只断言 `kind` 那一列（它用 CARGO_MANIFEST_DIR 的相对路径读同一份文件），
/// 客户端断言后两列**并且**断言 `kind` 与客户端大类的对应关系——
/// 两边的词表不是一套（服务端把港/韩/A 股合成 `equityNamed`，把认不出来的叫 `unknown`），
/// 所以对应关系写在下面这张 `expectation` 里，不指望枚举拼写一致。
///
/// 表里只放**由 `underlyingType` 决定**的行。贵金属（XAU/XAG/XPT/XPD）是按 base 覆盖的、
/// 与类型无关，另有独立用例（`preciousMetalsStayRecognizedWithoutType`）。
/// `COMMODITY` / `INDEX` 是客户端自己多分的两档，服务端的 kind 枚举里没有对应项，
/// 也不进这张表，由 `clientOnlyRefinements` 单独钉。
@Suite("underlyingType 契约对账")
struct UnderlyingKindContractTests {
  struct Row: Decodable {
    var underlyingType: String?
    var kind: String
    var clientAsset: String
    var clientRegion: String?
  }

  /// 服务端 kind → 客户端允许的资产大类。
  static func expectation(for kind: String) -> Set<SymbolClassification.Asset>? {
    switch kind {
    case "crypto": return [.crypto]
    case "equityUS", "equityNamed": return [.equity]
    case "preMarket": return [.preMarket]
    // 服务端的 unknown（含缺 underlyingType）在客户端就是 .other + source == .unknown：
    // 客户端没有单独的 unknown 大类。
    case "other", "unknown": return [.other]
    default: return nil
    }
  }

  static func rows() throws -> [Row] {
    try JSONDecoder().decode([Row].self, from: Fixture.data("underlying_kinds"))
  }

  @Test func clientMatchesServerKindTable() throws {
    let rows = try Self.rows()
    #expect(rows.count >= 8, "对账表只有 \(rows.count) 行，少了会漏掉整类")
    for row in rows {
      let info = SymbolInfo(symbol: "NEWUSDT", base: "NEW", pricePrecision: 2, tickSize: 0.01,
                            underlyingType: row.underlyingType)
      let got = SymbolClassifier.classify(info)
      let type = row.underlyingType ?? "null"
      #expect(got.asset.rawValue == row.clientAsset,
              "underlyingType=\(type)：表里写 \(row.clientAsset)，客户端判成 \(got.asset.rawValue)")
      if let region = row.clientRegion {
        #expect(got.region.rawValue == region,
                "underlyingType=\(type)：表里写地区 \(region)，客户端判成 \(got.region.rawValue)")
      }
      guard let allowed = Self.expectation(for: row.kind) else {
        Issue.record("服务端的 kind \(row.kind) 在客户端没有对应关系（underlyingType=\(type)）")
        continue
      }
      #expect(allowed.contains(got.asset),
              "underlyingType=\(type)：服务端说 \(row.kind)，客户端判成 \(got.asset.rawValue)")
      if row.kind == "equityNamed" {
        #expect([.hk, .kr, .cn].contains(got.region),
                "equityNamed 在客户端必须落到港/韩/A 股，实际 \(got.region.rawValue)")
      }
      if row.underlyingType == nil {
        #expect(row.kind == "unknown",
                "缺 underlyingType 的行服务端应判 unknown，表里是 \(row.kind)——这正是审查 B-04 里两端唯一的分歧点")
        #expect(got.source == .unknown)
        #expect(got.asset == .other, "缺类型不再猜成加密（B-04）")
      }
    }
    // 每一类都得在表里出现过，别让某一行被悄悄删掉。
    let kinds = Set(rows.map(\.kind))
    #expect(kinds == ["crypto", "equityUS", "equityNamed", "preMarket", "other", "unknown"],
            "对账表缺了 kind：\(kinds.sorted())")
  }

  /// 客户端比服务端多分的两档：大宗商品与指数。服务端的 kind 枚举里没有它们，
  /// 所以不进对账表，但客户端这两条映射也不能漂。
  @Test func clientOnlyRefinements() {
    func asset(_ type: String) -> SymbolClassification.Asset {
      SymbolClassifier.classify(SymbolInfo(symbol: "NEWUSDT", base: "NEW", pricePrecision: 2,
                                          tickSize: 0.01, underlyingType: type)).asset
    }
    #expect(asset("COMMODITY") == .commodity)
    #expect(asset("INDEX") == .index)
  }
}
