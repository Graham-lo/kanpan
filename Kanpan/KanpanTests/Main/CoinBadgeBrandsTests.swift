import Foundation
import KanpanCore
import SwiftUI
import Testing
@testable import Kanpan

/// 品牌标表 `Resources/CoinBadgeBrands.json`（审查第 18 项从 Swift 静态表搬过来）。
///
/// 搬家那一刻用临时对账证明过 JSON 与原来八张 Swift 表逐字段相等；表删掉以后，
/// 这里守的是「文件本身还站得住」：解得开、条数没被悄悄删、颜色和路径都合法、
/// 每条的设计依据还在，以及几支点名的品种查出来还是自己的记号。
@Suite("品种徽章表")
struct CoinBadgeBrandsTests {
  /// 只给测试读的那几样：`note` / `group` 在 app 里不解。
  private struct RawFile: Decodable {
    struct Entry: Decodable {
      var group: String
      var note: String
      var from: String
      var to: String
    }
    var about: String
    var brands: [String: Entry]
  }

  /// 条数写死：加一支、删一支都要顺手改这儿，免得哪次合并把一截表弄丢了没人发现。
  private static let expectedCount = 178

  private func raw() throws -> RawFile {
    let url = try #require(Bundle.main.url(forResource: "CoinBadgeBrands", withExtension: "json"),
                           "app 包里没有 CoinBadgeBrands.json")
    return try JSONDecoder().decode(RawFile.self, from: Data(contentsOf: url))
  }

  @Test func decodesWithExpectedCount() throws {
    let url = try #require(Bundle.main.url(forResource: "CoinBadgeBrands", withExtension: "json"))
    let file = try JSONDecoder().decode(CoinSpec.BrandFile.self, from: Data(contentsOf: url))
    #expect(file.brands.count == Self.expectedCount)
    #expect(CoinSpec.brandFile.count == Self.expectedCount)
    #expect(CoinSpec.loadBrandFile(from: .main) == file.brands)
    #expect(try raw().brands.count == Self.expectedCount)
  }

  @Test func colorsAreSixDigitHex() throws {
    let hex = /^#[0-9A-Fa-f]{6}$/
    for (key, entry) in try raw().brands {
      #expect(entry.from.wholeMatch(of: hex) != nil, "\(key) from = \(entry.from)")
      #expect(entry.to.wholeMatch(of: hex) != nil, "\(key) to = \(entry.to)")
    }
  }

  @Test func everyPathParses() {
    // `SVGPath` 碰到不认识的字母只会默默跳过，所以先查字符集，再查解出来的图形不是空的、
    // 落在 24 格画布里（按路径本身的外框算，不含曲线控制点）。画布四周各放 1 格余量：
    // TIA 的月牙是拿一枚探出右上角的圆去挖的，挖的那一枚本来就越过边一点。
    let allowed = Set("MmLlHhVvCcSsQqTtAaZz0123456789.-, ")
    let canvas = CGRect(x: -1, y: -1, width: 26, height: 26)
    for (key, spec) in CoinSpec.brandFile {
      guard case .parts(let parts) = spec.mark else { continue }
      #expect(!parts.isEmpty, "\(key) 没有笔画")
      for part in parts {
        #expect(!part.d.isEmpty, "\(key) 有一层没有路径")
        if let w = part.stroke { #expect(w > 0 && w < 6, "\(key) 描边宽 \(w)") }
        for d in part.d {
          #expect(d.first == "M" || d.first == "m", "\(key) 路径不以 M 开头：\(d)")
          #expect(Set(d).isSubset(of: allowed), "\(key) 路径有不认识的字符：\(d)")
          let box = SVGPath.parsed([d]).boundingRect
          #expect(!box.isNull && (box.width > 0 || box.height > 0), "\(key) 路径解出来是空的：\(d)")
          let outline = SVGPath.parsed([d]).cgPath.boundingBoxOfPath
          #expect(canvas.contains(outline), "\(key) 路径出了 24 格画布：\(outline)")
        }
      }
    }
  }

  @Test func everyEntryKeepsItsNote() throws {
    let file = try raw()
    #expect(!file.about.isEmpty)
    for (key, entry) in file.brands {
      #expect(!entry.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(key) 丢了设计依据")
      #expect(!entry.group.isEmpty, "\(key) 没有 group")
    }
  }

  @Test func namedSymbolsResolveToTheirOwnMark() throws {
    // 美满电子：一道折成 M 的粗笔画，描边 2.4。
    let mrvl = try #require(CoinSpec.brand("MRVL"))
    #expect(mrvl.mark == .parts([.init(d: ["M4.8 17.8V7.2l7.2 6.2 7.2-6.2v10.6"], stroke: 2.4)]))
    #expect(mrvl.from == Hex("#7FA8E8") && mrvl.to == Hex("#1E4FA8") && mrvl.inset == 0.62)
    // 博通：三条错开的总线，填充。
    let avgo = try #require(CoinSpec.brand("AVGO"))
    #expect(avgo.mark == .parts([.init(d: [
      "M3.4 4.4h10.2v4.4H3.4z", "M6.9 9.8h10.2v4.4H6.9z", "M10.4 15.2h10.2v4.4H10.4z",
    ], stroke: nil)]))
    // Zcash：一个厚实的 Z，填充。
    let zec = try #require(CoinSpec.brand("ZEC"))
    #expect(zec.mark == .parts([.init(d: ["M6.4 4.6h11.2v3L11.2 16.4h6.4v3H6.4v-3l6.4-8.8H6.4z"], stroke: nil)]))
    // Lisk：描边的盾形轮廓，中间一颗填充的菱心——两层。
    let lsk = try #require(CoinSpec.brand("LSK"))
    #expect(lsk.mark == .parts([
      .init(d: ["M12 4l6.4 7L12 20l-6.4-9z"], stroke: 2),
      .init(d: ["M12 8.8l2.8 3.2L12 15.8l-2.8-3.8z"], stroke: nil),
    ]))
    // 走 `CoinSpec.of` 这条真正的入口也是同一枚，没被 `known` 或长尾标截走。
    for key in ["MRVL", "AVGO", "ZEC", "LSK"] {
      #expect(CoinSpec.of(key) == CoinSpec.brand(key), "\(key)")
    }
    #expect(CoinSpec.brand("NOT-A-SYMBOL") == nil)
  }

  /// 比亚迪那枚椭圆原来起笔写成了左端点当顶点，整只椭圆往左偏了 6.6 格、一半出了画布，
  /// 中间那道横条戳在圈外。守住它居中。
  @Test func bydEllipseIsCentered() throws {
    let byd = try #require(CoinSpec.brand("BYD"))
    guard case .parts(let parts) = byd.mark else { Issue.record("BYD 不是笔画记号"); return }
    let ring = SVGPath.parsed(parts[0].d).cgPath.boundingBoxOfPath
    #expect(abs(ring.midX - 12) < 0.01 && abs(ring.midY - 12) < 0.01, "椭圆中心 \(ring)")
  }
}
