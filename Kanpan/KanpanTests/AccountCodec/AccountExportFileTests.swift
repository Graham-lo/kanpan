import Foundation
import Testing
@testable import Kanpan

/// 审查 D-08：「导出我的数据」那份文件是这个人全部的个人数据，本机只留到分享面板收起；
/// 再导一次、退登、换号都把它清掉，不留给下一个用这台机器的人。
@MainActor
@Suite("导出我的数据 · 本机不留底", .serialized)
struct AccountExportFileTests {
  private let raw = Data(#"{"data":{"format":"hkline-export-1","user":{"email":"alice"}}}"#.utf8)

  private func files() -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: AccountFeature.exportDirectory.path)) ?? []
  }

  @Test("落在专用目录里，目录里永远只有眼下这一份")
  func onlyTheLatestExportStays() throws {
    AccountFeature.purgeExports()
    let first = try AccountFeature.writeExport(raw, now: Date(timeIntervalSince1970: 1_790_000_000))
    #expect(first.deletingLastPathComponent().standardizedFileURL == AccountFeature.exportDirectory.standardizedFileURL)
    let second = try AccountFeature.writeExport(raw, now: Date(timeIntervalSince1970: 1_790_000_000 + 86_400 * 3))
    #expect(first != second)
    #expect(files() == [second.lastPathComponent])
    let body = try JSONSerialization.jsonObject(with: Data(contentsOf: second)) as? [String: Any]
    #expect(body?["format"] as? String == "hkline-export-1")
    AccountFeature.purgeExports()
    #expect(files().isEmpty)
  }

  @Test("退登时把导出文件一并删掉")
  func logoutPurgesExports() async throws {
    _ = try AccountFeature.writeExport(raw)
    #expect(!files().isEmpty)
    let feature = AccountFeature(client: nil)
    await feature.logout()
    #expect(files().isEmpty, "退登之后上一个人的导出文件还躺在临时目录里：\(files())")
  }
}
