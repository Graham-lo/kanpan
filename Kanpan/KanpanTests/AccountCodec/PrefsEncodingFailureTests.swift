import Foundation
import Testing
import KanpanAccount
@testable import Kanpan

// MARK: - 偏好编码失败时不许生成同步体

/// `PrefsCodec.encoded` 失败会交 nil。账号这一侧以前走 `encode`（失败给空 `Data()`），
/// 空体一旦被当成设置推上去，服务端看到的就是「用户把所有字段都清掉了」。
/// 现在 codec 在编码失败时必须明确抛错，调用方据此跳过写盘 / 不入队。
@Suite("偏好编码失败不生成同步体") struct PrefsEncodingFailureTests {
  @Test func settingsThrowsInsteadOfEmittingAnEmptyBody() {
    #expect(throws: PersonalSyncCodec.UnencodablePrefs.self) {
      _ = try PersonalSyncCodec.settings(.defaults, encode: { _ in nil })
    }
  }

  @Test func applyThrowsInsteadOfTreatingLocalAsEmpty() throws {
    let object = try PersonalSyncCodec.settings(.defaults)
    #expect(throws: PersonalSyncCodec.UnencodablePrefs.self) {
      _ = try PersonalSyncCodec.apply(object, to: .defaults, encode: { _ in nil })
    }
  }

  @Test func defaultEncoderStillRoundTrips() throws {
    let object = try PersonalSyncCodec.settings(.defaults)
    #expect(!object.deleted)
    #expect(try PersonalSyncCodec.apply(object, to: .defaults) == .defaults)
  }
}
