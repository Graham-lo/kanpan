import Foundation
import Testing
import KanpanAccount
@testable import Kanpan

/// 账号页红字、设置页账号行只说固定的中文（压测收尾 2026-09-26，整机线移交第 6 项）。
///
/// 原来各处 `error.localizedDescription`：`AccountError` 自带中文，别的原样漏出去——
/// 作废的请求念成「(Swift.CancellationError error 1.)」，本机档案读不动念出存储类型名，
/// 断网念系统原文。现在一律过 `AccountFeature.message`。
@Suite("账号 · 错误只说固定的中文")
@MainActor
struct AccountErrorMessageTests {
  /// 一个不带 `LocalizedError` 的自家错误——本机档案读不动时抛的就是这种。
  private enum UnreadableArchive: Error { case corrupt }

  /// 界面上不许出现的东西：英文句子、类型名、错误域。
  private func leaks(_ text: String) -> Bool {
    text.contains("Error") || text.contains("error") || text.contains("operation")
      || text.contains("NSCocoa") || text.contains("Swift.") || text.range(of: "[A-Za-z]{6,}", options: .regularExpression) != nil
  }

  @Test("认得的给固定句子、作废的不念、认不得的给兜底；没有一句带类型名或系统原文")
  func mapping() {
    // 修前那几句长什么样（留作证据）：
    let before = [CancellationError() as Error, UnreadableArchive.corrupt].map(\.localizedDescription)
    #expect(before.allSatisfy(leaks), "修前的原文：\(before)")

    #expect(AccountFeature.message(AccountError.http(409, "x")) == "正在更新，本机内容已保留")
    #expect(AccountFeature.message(AccountError.reauthenticationRequired) == "登录已失效，请重新登录")
    #expect(AccountFeature.message(CancellationError()) == nil)
    #expect(AccountFeature.message(URLError(.cancelled)) == nil)
    #expect(AccountFeature.message(URLError(.timedOut)) == "连接超时，请稍后重试")
    #expect(AccountFeature.message(URLError(.notConnectedToInternet)) == "网络不可用，请检查网络后重试")
    #expect(AccountFeature.message(URLError(.cannotFindHost)) == "暂时连不上账号服务，请稍后重试")
    let decoding = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad"))
    #expect(AccountFeature.message(decoding) == AccountError.invalidResponse.localizedDescription)
    #expect(AccountFeature.message(CocoaError(.fileWriteOutOfSpace)) == AccountError.storage.localizedDescription)
    #expect(AccountFeature.message(POSIXError(.ENOSPC)) == AccountError.storage.localizedDescription)
    #expect(AccountFeature.message(UnreadableArchive.corrupt) == AccountFeature.genericFailure)
    let all: [Error] = [UnreadableArchive.corrupt, decoding, CocoaError(.fileWriteOutOfSpace),
                        POSIXError(.ENOSPC), URLError(.badServerResponse), URLError(.timedOut),
                        NSError(domain: "Kanpan.Whatever", code: 7)]
    for error in all {
      let text = AccountFeature.message(error) ?? ""
      #expect(!text.isEmpty && !leaks(text), "\(error) 念成了「\(text)」")
    }
  }

  @Test("退登时本机档案读不动：红字是固定兜底，不是类型名")
  func logoutWithUnreadableGuestArchive() async {
    let feature = AccountFeature(client: nil)
    feature.onPrepareAccount = { _ in throw UnreadableArchive.corrupt }
    await feature.logout()
    #expect(feature.error == AccountFeature.genericFailure, "红字：\(feature.error ?? "nil")")
  }

  @Test("同步报上来作废的请求不改设置页那句；认不得的错误给兜底")
  func syncStatus() {
    let feature = AccountFeature(client: nil)
    feature.syncStatus = "同步中"
    feature.report(sync: CancellationError())
    #expect(feature.syncStatus == "同步中")
    feature.report(sync: UnreadableArchive.corrupt)
    #expect(feature.syncStatus == AccountFeature.genericFailure)
    feature.report(sync: URLError(.notConnectedToInternet))
    #expect(feature.syncStatus == "网络不可用，请检查网络后重试")
  }
}
