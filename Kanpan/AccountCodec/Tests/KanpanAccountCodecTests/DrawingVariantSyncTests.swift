import Foundation
import Testing
import KanpanCore
import KanpanAccount
@testable import KanpanAccountCodec

/// 「趋势线换成两端延伸」这份记忆跟着账号走（用户 2026-09-23：「云端也是需要记住的」）。
///
/// 线上长的是拍平的 `variants/<面板那一格>`，和 `styles/<工具>` 同一个形状；
/// 服务端白名单与值规则在 `Backend/kanpan-api/src/sync.rs` / `sync_validation.rs`。
@Suite("画线：每一族的画法随人走")
struct DrawingVariantSyncTests {
  /// 上行拍平、下行展开，和 `AppAccountBridge.applyPending` 走的是同一条路。
  private func roundTrip(_ archive: DrawArchive) throws -> (SyncObject, DrawingPreferences) {
    let tools = try #require(try PersonalSyncCodec.drawings(archive).first { $0.collection == "drawingPreferences" })
    let back = try KanpanAccount.JSONValue.object(PersonalSyncCodec.expand(tools.body)).decode(DrawingPreferences.self)
    return (tools, back)
  }

  @Test("换过的画法拍成 variants/<面板那一格> 发上去，拉回来还原")
  func variantsTravel() throws {
    var archive = DrawArchive()
    archive.preferences.rememberSwap(from: .trend, to: .extended)
    archive.preferences.rememberSwap(from: .vline, to: .crossLine)
    let (tools, back) = try roundTrip(archive)
    #expect(tools.body["variants/trend"] == .string("extended"))
    #expect(tools.body["variants/vline"] == .string("crossLine"))
    #expect(tools.body["variants"] == nil, "整块对象发上去服务端不认，只能发拍平的子键")
    #expect(back.variants == ["trend": .extended, "vline": .crossLine])
    #expect(back.newDrawing(tool: .trend, points: [DrawPoint(t: 1, p: 1), DrawPoint(t: 2, p: 2)]).kind == .extended)
  }

  @Test("云端那份没有 variants（老客户端推的 / 从没换过）照常读，画法退回面板那一把")
  func missingVariantsDecode() throws {
    let (tools, back) = try roundTrip(DrawArchive())
    #expect(!tools.body.keys.contains { $0.hasPrefix("variants") })
    #expect(back.variants.isEmpty)
    #expect(back.kind(for: .trend) == .trend)
  }

  @Test("三族的 variants 子键都在「替哪些字段说话」表里")
  func variantKeysAreOwned() throws {
    let owned = try #require(PersonalSyncCodec.ownedKeys["drawingPreferences"])
    for head in Drawing.Kind.palette where head.paletteHead == head {
      #expect(owned.contains("variants/" + head.rawValue), "`variants/\(head.rawValue)` 不在表里")
    }
    #expect(Drawing.Kind.palette.filter { $0.paletteHead == $0 }.count == 3)
  }
}
