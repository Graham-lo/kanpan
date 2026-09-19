import Foundation
import Testing
@testable import KanpanAccount

/// 档案 id 是**一处计算、两处用**：账号目录用它当路径，`Library/Caches` 下那几份
/// 「内容随当前账号派生」的行情缓存用它分目录。这一套守的是「别另发明一套 id」，
/// 以及「登录那一刻身份不许被搬家的来源目录倒回访客」。
@MainActor @Suite("档案身份", .serialized)
struct ProfileIdentityTests {
  private func temp() throws -> URL {
    let p = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true)
    return p
  }

  @Test("id 和账号目录的路径逐字相同")
  func 同一个id() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let files = try AccountFiles(root: root)
    let user = UUID()

    let guestDir = try files.directory(user: nil)
    files.activate(user: nil)
    #expect(AccountFiles.currentProfile == "local/" + files.guestBatch.uuidString.lowercased())
    #expect(guestDir.path.hasSuffix(AccountFiles.currentProfile))

    let userDir = try files.directory(user: user)
    files.activate(user: user)
    #expect(AccountFiles.currentProfile == "u-" + user.uuidString.lowercased())
    #expect(userDir.path.hasSuffix(AccountFiles.currentProfile))
  }

  /// A-01：装档案是「先把所有会失败的活干完，再一次性提交」。取目录只是把地方
  /// 准备好，那之后还有读盘、解码、ReviewStore 初始化会抛——抛了人就还留在原来
  /// 那个档案里。身份要是在取目录那一刻就改了，缓存会写进另一个人的目录。
  @Test("身份跟着提交走，不跟着取目录走")
  func 提交才换身份() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let files = try AccountFiles(root: root)
    files.activate(user: nil)
    let guest = AccountFiles.currentProfile

    let user = UUID()
    _ = try files.directory(user: user)
    #expect(AccountFiles.currentProfile == guest, "还没提交，身份一个字都不许动")

    files.activate(user: user)
    #expect(AccountFiles.currentProfile == "u-" + user.uuidString.lowercased())
  }

  /// 登录时访客草稿要搬进账号目录，`claimGuest` 得去拿那个**来源**目录。
  /// 那一次取目录不是「换档案」——它要是也记上身份，登录那一刻缓存就会写回
  /// 上一段访客批次的目录里。
  @Test("搬家取来源目录不会把身份倒回访客")
  func 搬家不改身份() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let files = try AccountFiles(root: root)
    let guest = try files.directory(user: nil); files.activate(user: nil)
    try Data("draft".utf8).write(to: guest.appendingPathComponent("symbols.json"))

    let user = UUID()
    _ = try files.directory(user: user); files.activate(user: user)   // 装上账号那份档案
    let expected = AccountFiles.currentProfile
    #expect(expected == "u-" + user.uuidString.lowercased())

    let claim = try #require(try files.claimGuest(user: user))
    #expect(claim.directory.path == guest.path)  // 来源确实是刚才那个访客目录
    #expect(AccountFiles.currentProfile == expected)  // 但身份一个字都没动
  }
}
