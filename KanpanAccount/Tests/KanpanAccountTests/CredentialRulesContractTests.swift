import Foundation
import Testing
@testable import KanpanAccount

/// 用户名、密码规则的跨端夹具：`Backend/kanpan-api/contract/account-credentials.json`。
///
/// 账号页和加朋友输入框边输边拿 `AccountCredentialRules` 校验、不合格就置灰；服务端
/// `auth::tests::every_shared_credential_case_agrees` 与 `share::tests::recipient_names_follow_the_shared_username_rule`
/// 对同一份夹具。两边结论不一致，就会有「按钮亮着、点了被拒」或「服务端收、按钮却灰着」。
@Suite("账号规则夹具（account-credentials.json）")
struct CredentialRulesContractTests {
  struct Fixture: Decodable {
    struct Name: Decodable { var input: String; var accepted: String? }
    struct Word: Decodable { var input: String; var ok: Bool }
    struct Rules<Case: Decodable>: Decodable { var rule: String; var cases: [Case] }
    var version: Int
    var username: Rules<Name>
    var password: Rules<Word>
  }

  static func load() throws -> Fixture {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let url = root.appendingPathComponent("Backend/kanpan-api/contract/account-credentials.json")
    return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
  }

  @Test("用户名：夹具里每一条，客户端的结论和服务端一字不差")
  func usernames() throws {
    let fixture = try Self.load()
    #expect(fixture.version == 1, "account-credentials.json 的格式版本变了，这里的读法要一起改")
    #expect(fixture.username.cases.count >= 10, "用户名夹具被删薄了")
    for c in fixture.username.cases {
      #expect(AccountCredentialRules.username(c.input) == c.accepted, "用户名 \(c.input.debugDescription)")
    }
  }

  @Test("密码：夹具里每一条，客户端的结论和服务端一字不差")
  func passwords() throws {
    let fixture = try Self.load()
    #expect(fixture.password.cases.count >= 10, "密码夹具被删薄了")
    for c in fixture.password.cases {
      #expect(AccountCredentialRules.acceptsPassword(c.input) == c.ok, "密码 \(c.input.debugDescription)")
    }
  }

  @Test("界面上那一行规则字、服务端拒绝时的说法，都是夹具里那一句")
  func ruleWording() throws {
    let fixture = try Self.load()
    #expect(AccountCredentialRules.usernameRule == fixture.username.rule)
    #expect(AccountCredentialRules.passwordRule == fixture.password.rule)
    #expect(AccountError.http(400, "invalid_username").errorDescription == fixture.username.rule)
    #expect(AccountError.http(400, "invalid_password").errorDescription == fixture.password.rule)
  }
}
