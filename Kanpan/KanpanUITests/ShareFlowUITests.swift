import XCTest

/// 两条受影响的 UI 用例。账号、分享、画线和提醒全走真后端；仅诊断读数用 DEBUG 口。
@MainActor final class ShareFlowUITests: XCTestCase {
  private let api = "https://kanpan.107-174-172-10.sslip.io"
  private var app: XCUIApplication!
  private var people: [[String: String]] = []
  private var tokens: [String] = []
  private var devices: [[String: String]] = []
  private var sharedID = ""
  private var originalIDs: [String] = []
  private var ownID = ""
  private var baseline: [String: Any] = [:]
  private var canvas: XCUIElement { app.otherElements["chart.canvas"] }

  override func setUp() async throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    if let raw = ProcessInfo.processInfo.environment["SHARE_QA_USERS"], let data = raw.data(using: .utf8) {
      people = try JSONDecoder().decode([[String: String]].self, from: data)
    } else {
      // 独立复跑时自造 qa_ 账号；密码只留在这次测试进程的内存。
      for side in ["a", "b"] {
        let name = "qa_share_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased() + side
        let password = UUID().uuidString + "a1"
        let device = newDevice()
        _ = try await request("v1/auth/register", method: "POST", body: ["username": name, "password": password, "device": device])
        people.append(["username": name, "password": password])
      }
    }
    for person in people {
      let device = newDevice(); devices.append(device)
      let data = try await request("v1/auth/login", method: "POST", body: ["username": person["username"]!, "password": person["password"]!, "device": device])
      tokens.append(try XCTUnwrap(data["accessToken"] as? String))
    }
    print("分享验收账号：\(people.map { $0["username"]! }.joined(separator: "、"))")
    try await patch(collection: "settings", id: "chart", fields: ["skin": "terra", "theme": "light", "overlays": ["MA"], "subs": ["RSI"], "params/MA": [7,21,55,100], "interval": "5m"], person: 1)
    ownID = UUID().uuidString
    let now = Date().timeIntervalSince1970 * 1000
    try await patch(collection: "drawings", id: "binance/usd_m/BTCUSDT/" + ownID,
                    fields: ["kind": "hline", "symbol": "BTCUSDT", "venue": "binance", "market": "usd_m", "anchors": [["t": now, "p": 1.0]], "lineWidth": 1.3, "dash": "solid", "filled": true, "locked": false, "hidden": false, "levels": []], person: 1)
    app = XCUIApplication()
    app.launchEnvironment = ["KANPAN_TEST_PROFILE": "1", "KANPAN_PERSISTENCE_PROFILE": UUID().uuidString,
                             "KANPAN_ACCOUNT_API_URL": api, "KANPAN_CHART_DIAGNOSTICS": "1"]
    app.launch()
    loginUI(people[1])
    tap("bottom.chart")
    XCTAssertTrue(wait(60) { self.info()["interval"] as? String == "5m" && (self.info()["drawingIDs"] as? [String] ?? []).contains(self.ownID) })
    baseline = info()
    let price = try XCTUnwrap(baseline["lastClose"] as? Double)
    try await patch(collection: "drawings", id: "binance/usd_m/BTCUSDT/" + ownID,
                    fields: ["anchors": [["t": now, "p": price * 0.998]]], person: 1)
    app.terminate(); app.launch(); tap("bottom.chart")
    XCTAssertTrue(wait(45) { (self.info()["drawingIDs"] as? [String] ?? []).contains(self.ownID) })
    let right = now - 3_600_000, left = right - 30 * 3_600_000
    originalIDs = (0..<3).map { _ in UUID().uuidString }
    let draws: [[String: Any]] = originalIDs.enumerated().map { index, id in
      ["id": id, "kind": index == 2 ? "rectangle" : "trend", "points": [["t": left, "p": price * (0.995 + Double(index) * 0.002)], ["t": right, "p": price * (1.002 + Double(index) * 0.003)]], "lineWidth": 1.3, "dash": "solid", "filled": true, "locked": false, "hidden": false, "levels": []]
    }
    let sent = try await request("v1/shares", method: "POST", body: ["to": people[1]["username"]!, "symbol": "BTCUSDT", "interval": "1h", "view": ["from": Int64(left - 10 * 3_600_000), "to": Int64(right + 10 * 3_600_000)], "drawings": draws, "alerted": [originalIDs[0]]], person: 0)
    sharedID = try XCTUnwrap(sent["id"] as? String)
    // 真正离开再回前台，触发账号桥同步后的那一次收件箱拉取。
    XCUIDevice.shared.press(.home); app.activate()
    XCTAssertTrue(app.buttons["share.open"].waitForExistence(timeout: 60), "回前台没有收件卡")
  }
  override func tearDown() async throws { app?.terminate() }

  func testPreviewKeepsOwnLayout() async throws {
    let card = app.otherElements["share.card"]
    XCTAssertFalse(card.frame.intersects(canvas.frame), "收件卡压到画布")
    // 六秒不理不会消失。
    try await Task.sleep(for: .seconds(7))
    XCTAssertTrue(card.exists)
    tap("share.open")
    XCTAssertTrue(wait(30) { (self.info()["guestIDs"] as? [String]) == self.originalIDs && self.info()["interval"] as? String == "1h" })
    assertLayout()
    XCTAssertEqual(info()["ownDimmed"] as? Bool, true)
    XCTAssertTrue((info()["drawingIDs"] as? [String] ?? []).contains(ownID))
    attach("预览保留自己的布局")
    // 客线不可选中，轻点、拖动只是图表交互。
    canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.2)).tap()
    XCTAssertFalse(app.buttons["draw.finish"].exists)
    tap("share.exit")
    XCTAssertTrue(wait(20) { self.info()["interval"] as? String == "5m" && self.info()["ownDimmed"] as? Bool == false })
    XCTAssertEqual(info()["guestIDs"] as? [String], [])
    assertLayout()
    openFromFriends()
    tap("interval.chip.4h")
    tap("share.exit")
    XCTAssertTrue(wait(20) { self.info()["interval"] as? String == "4h" })
    attach("退出还原且尊重手动换档")
    // 图表面板中的另一处落点使用同一张朋友名单。
    // 2026-09-23 起图片与画线合成一个「分享」，点开再选「画线」。
    tap("interval.chart"); tap("chart.share")
    XCTAssertTrue(app.otherElements["share.chooser"].waitForExistence(timeout: 10), "「分享」没弹出选图片还是画线")
    tap("share.lines")
    XCTAssertTrue(app.otherElements["share.picker"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.keyboards.firstMatch.exists)
    tap("share.friend." + people[0]["username"]!)
    XCTAssertTrue(wait(30) { !self.app.otherElements["share.picker"].exists })
  }

  func testKeepThenAlert() async throws {
    tap("share.open")
    XCTAssertTrue(app.buttons["share.keep"].waitForExistence(timeout: 20))
    let before = Set(info()["drawingIDs"] as? [String] ?? [])
    tap("share.keep")
    // 不在这六秒之间读整张画布，先接住问句。
    let accept = app.buttons["alert.prompt.accept"]
    XCTAssertTrue(accept.waitForExistence(timeout: 4)); accept.tap()
    XCTAssertTrue(wait(20) { (self.info()["drawingIDs"] as? [String] ?? []).count == before.count + 3 })
    let kept = Set(info()["drawingIDs"] as? [String] ?? []).subtracting(before)
    XCTAssertEqual(kept.count, 3); XCTAssertTrue(kept.isDisjoint(with: originalIDs))
    XCTAssertEqual(info()["ownDimmed"] as? Bool, false)
    XCTAssertEqual(info()["guestIDs"] as? [String], [])
    XCTAssertTrue(wait(20) { Set(self.info()["drawingAlerted"] as? [String] ?? []).intersection(kept).count == 1 })
    var found = false
    for _ in 0..<20 {
      let sync = try await request("v1/sync/bootstrap?collection=alerts", person: 1)
      let objects = sync["objects"] as? [[String: Any]] ?? []
      if let alert = objects.first(where: { object in
        guard let body = object["body"] as? [String: Any], let drawing = body["drawingID"] as? String else { return false }
        return kept.contains(drawing.components(separatedBy: "/").last ?? drawing)
      }) {
        print("留下后提醒同步证据：\(people[1]["username"]!) \(alert["id"] ?? "")")
        found = true; break
      }
      try await Task.sleep(for: .seconds(1))
    }
    XCTAssertTrue(found, "留下后提醒没有同步到服务端")
    assertLayout(); attach("留下并加入提醒")
    // 画线台上不再有纸飞机（分享只留图表设置里那一个入口）：横竖屏各看一眼。
    tap("bottom.draw")
    XCTAssertTrue(app.landscapeMarker.waitForExistence(timeout: 15))
    XCTAssertFalse(app.buttons["draw.send"].exists, "横屏画线台上还挂着纸飞机")
    // 画线进行中横屏侧栏整条收起，用手把机器转回竖屏再看一眼。
    app.rotateDrawingToPortraitByHand()
    XCTAssertTrue(app.buttons["draw.finish"].waitForExistence(timeout: 15))
    XCTAssertFalse(app.buttons["draw.send"].exists, "竖屏画线栏上还挂着纸飞机")
    tap("draw.finish")
    // 留下来的线是自己的了，从「图表 › 分享 › 画线」回发给朋友。
    tap("interval.chart"); tap("chart.share")
    XCTAssertTrue(app.otherElements["share.chooser"].waitForExistence(timeout: 10))
    tap("share.lines")
    XCTAssertTrue(app.otherElements["share.picker"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.keyboards.firstMatch.exists, "朋友面板不该自动弹键盘")
    tap("share.friend." + people[0]["username"]!)
    XCTAssertTrue(wait(30) { !self.app.otherElements["share.picker"].exists })
    let received = try await request("v1/shares/inbox", person: 0)
    XCTAssertFalse((received["items"] as? [Any] ?? []).isEmpty, "朋友没有收到回发")
    attach("留下的线从分享回发给朋友")
  }

  /// P3.5「回给他」：B 在 A 发来的那封上点「回给 A」→ 他的线留在图上 → 发送 →
  /// 服务端那封带 `replyTo` 指回原信 → A 登录后收件卡写「B 回了你」。
  func testReplyRoundTrip() async throws {
    tap("share.open")
    tap("share.reply")
    let bar = app.descendants(matching: .any)["share.replying"]
    XCTAssertTrue(bar.waitForExistence(timeout: 15), "点了「回给」没换成回信条")
    XCTAssertTrue(app.staticTexts["回给 " + people[0]["username"]!].exists)
    XCTAssertTrue(wait(20) { (self.info()["drawingIDs"] as? [String] ?? []).count >= 4 }, "他的线没留到图上")
    attach("01-回给他")
    tap("share.reply.send")
    XCTAssertTrue(wait(30) { !bar.exists }, "发送后回信条没收起")
    var reply: [String: Any]?
    for _ in 0..<20 where reply == nil {
      let inbox = try await request("v1/shares/inbox", person: 0)
      reply = (inbox["items"] as? [[String: Any]] ?? []).first { $0["replyTo"] as? String == sharedID }
      if reply == nil { try await Task.sleep(for: .seconds(1)) }
    }
    let got = try XCTUnwrap(reply, "A 的收件箱里没有带 replyTo 的回信")
    XCTAssertEqual(got["from"] as? String, people[1]["username"])
    print("回信证据：\(got["id"] ?? "") replyTo=\(sharedID)")
    // 换成 A 登录，看那张卡。
    app.terminate()
    app.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = UUID().uuidString
    app.launch()
    loginUI(people[0])
    tap("bottom.chart")
    XCUIDevice.shared.press(.home); app.activate()
    let card = app.staticTexts[people[1]["username"]! + " 回了你"]
    XCTAssertTrue(card.waitForExistence(timeout: 60), "A 的收件卡没写「B 回了你」：\(app.debugDescription)")
    attach("02-对方卡片回了你")
  }

  private func assertLayout(file: StaticString = #filePath, line: UInt = #line) {
    let current = info()
    for key in ["background", "overlays", "subs", "ma", "mode", "inverted"] {
      XCTAssertEqual(String(describing: current[key]!), String(describing: baseline[key]!), "布局变了：\(key)", file: file, line: line)
    }
  }
  private func openFromFriends() {
    tap("bottom.settings")
    let friends = app.buttons["settings.friends"]
    if !friends.isHittable { app.scrollViews.firstMatch.swipeUp() }
    tap("settings.friends")
    tap("share.item." + sharedID)
    XCTAssertTrue(app.buttons["share.exit"].waitForExistence(timeout: 20))
  }
  private func loginUI(_ person: [String: String]) {
    tap("bottom.settings"); tap("settings.account")
    let username = app.textFields["account.email"]
    XCTAssertTrue(username.waitForExistence(timeout: 10)); username.tap(); username.typeText(person["username"]!)
    let password = app.secureTextFields["account.password"]; password.tap(); password.typeText(person["password"]!)
    tap("account.submit")
    XCTAssertTrue(wait(45) { !self.app.otherElements["account.view"].exists }, "登录未完成")
  }
  private func tap(_ id: String) {
    let button = app.buttons[id]; XCTAssertTrue(button.waitForExistence(timeout: 12), id)
    button.tap()
  }
  private func info() -> [String: Any] {
    guard canvas.exists, let text = canvas.value as? String, let data = text.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return object
  }
  private func wait(_ seconds: Double, _ predicate: @escaping () -> Bool) -> Bool {
    XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)], timeout: seconds) == .completed
  }
  private func attach(_ name: String) {
    let screenshot = XCUIScreen.main.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
  }
  private func newDevice() -> [String: String] {
    ["id": UUID().uuidString, "name": "画线分享验收", "secret": UUID().uuidString + UUID().uuidString, "kind": "desktop"]
  }
  private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil, person: Int? = nil) async throws -> [String: Any] {
    var request = URLRequest(url: URL(string: api + "/" + path)!)
    request.httpMethod = method; request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let person { request.setValue("Bearer " + tokens[person], forHTTPHeaderField: "Authorization") }
    if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
    let (data, response) = try await URLSession.shared.data(for: request)
    let code = (response as! HTTPURLResponse).statusCode
    XCTAssertTrue((200..<300).contains(code), "接口失败 \(path)：\(code)")
    let decoded = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    return decoded["data"] as? [String: Any] ?? [:]
  }
  private func patch(collection: String, id: String, fields: [String: Any], person: Int) async throws {
    let snapshot = try await request("v1/sync/bootstrap?collection=" + collection, person: person)
    let old = (snapshot["objects"] as? [[String: Any]] ?? []).first { $0["id"] as? String == id }
    let operation: [String: Any] = ["id": UUID().uuidString, "collection": collection, "objectId": id,
      "deviceId": devices[person]["id"]!, "baseRevision": old?["revision"] ?? 0, "generation": old?["generation"] ?? 0,
      "timestamp": Int64(Date().timeIntervalSince1970 * 1000), "logical": 0, "action": "patch", "fields": fields]
    _ = try await request("v1/sync/operations", method: "POST", body: ["operations": [operation]], person: person)
  }
}
