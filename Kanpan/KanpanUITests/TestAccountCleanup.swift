import Foundation

/// UI 用例自造的线上测试账号，收尾时统一从这里注销。
///
/// 另起一个桌面类会话登录再删：不借用例里的令牌（跑久了可能过期），也不顶掉 app 里那台
/// 手机类会话。删不掉要打出来，不能静默留号——2026-09-23 D.7 审读发现分享、对比、注册
/// 几条用例成功也好失败也好都在线上留账号，就是因为没有人收尾、收尾的错误又被吞了。
enum TestAccounts {
  static let api = "https://kanpan.107-174-172-10.sslip.io"

  static func delete(_ name: String, password: String, api: String = api) async {
    var login = URLRequest(url: URL(string: api + "/v1/auth/login")!)
    login.httpMethod = "POST"; login.timeoutInterval = 20
    login.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let device = ["id": UUID().uuidString, "name": "UI 用例收尾",
                  "secret": UUID().uuidString + UUID().uuidString, "kind": "desktop"]
    login.httpBody = try? JSONSerialization.data(withJSONObject: ["username": name, "password": password, "device": device])
    guard let (data, _) = try? await URLSession.shared.data(for: login),
          let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let token = (body["data"] as? [String: Any])?["accessToken"] as? String else {
      // 用例里已经经界面注销过的号会走到这里（登录 401），那是正常的。
      print("测试账号收尾：\(name) 登录不上，视为已不存在")
      return
    }
    var remove = URLRequest(url: URL(string: api + "/v1/auth/account")!)
    remove.httpMethod = "DELETE"; remove.timeoutInterval = 20
    remove.setValue("application/json", forHTTPHeaderField: "Content-Type")
    remove.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
    remove.httpBody = try? JSONSerialization.data(withJSONObject: ["password": password])
    let code = ((try? await URLSession.shared.data(for: remove))?.1 as? HTTPURLResponse)?.statusCode ?? -1
    print((200..<300).contains(code) ? "测试账号收尾：已注销 \(name)" : "⚠️ 测试账号没删掉（\(code)）：\(name)")
  }
}
