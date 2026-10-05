import XCTest

// ============================================================ 横屏捏合手感（2026-10-05）
//
// 横屏画线台上的三种捏法各照一张，并把「横屏自己记缩放」那条规矩钉住：
// - 横向捏开 / 捏合：根宽跟着变，竖屏那份（`Prefs.barSpacing`）不动；
// - 竖向捏（两指上下张开，纵向张开量 > 横向 1.5 倍）：只缩价格轴，根宽不动；
// - 回竖屏：图按竖屏自己那份根宽重量，不带着横屏捏出来的宽度。
//
// XCUITest 的 `pinch(withScale:velocity:)` 只按它自己的方向捏，竖向捏用 XCTest 自带的
// 合成事件记录（`XCSynthesizedEventRecord` / `XCPointerEventPath`，测试进程里才有，
// app 里没有任何对应的开关）。

@MainActor
final class LandscapePinchUITests: KanpanUICase {

  func testLandscapePinchKeepsOwnSpacing() {
    func shot(_ name: String) {
      // 横屏下取整屏（存下来是竖着的原始帧），同 `testLandscapeDrawingIndicatorPicker`。
      let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    let probe = app.descendants(matching: .any).matching(identifier: "layout.diagnostics").firstMatch
    /// `stored=…;live=…;token=…;landStored=…;landLive=…`
    func layout() -> [String: Double] {
      guard probe.exists, let text = probe.value as? String else { return [:] }
      var out: [String: Double] = [:]
      for pair in text.split(separator: ";") {
        let kv = pair.split(separator: "=", maxSplits: 1)
        if kv.count == 2, let v = Double(kv[1]) { out[String(kv[0])] = v }
      }
      return out
    }
    func spacing() -> Double { chartInfo()["spacing"] as? Double ?? 0 }
    func zoomY() -> Double { chartInfo()["zoomY"] as? Double ?? 0 }
    func note(_ name: String) {
      let a = XCTAttachment(string: "chart spacing=\(spacing()) zoomY=\(zoomY()) layout=\(layout())")
      a.name = name; a.lifetime = .keepAlways; add(a)
    }

    XCTAssertTrue(waitForLiveChart(), "\(Self.long)s 内没等到 K 线数据——这条要真数据，拿不到就是断了")
    let portraitSpacing = spacing()
    let portraitStored = layout()["stored"] ?? 0
    XCTAssertGreaterThan(portraitSpacing, 0)
    note("竖屏起点")

    XCTAssertTrue(app.tapDrawEntry(), "分析面板里没有「画线」")
    let symbol = app.descendants(matching: .any).matching(identifier: Ids.landscapeSymbol).firstMatch
    expectExists(symbol, Self.long, "点「画线」没横过去")
    XCTAssertTrue(waitUntil(timeout: Self.long) { (self.chartInfo()["subs"] as? [String])?.isEmpty == true },
                  "画线横屏里还留着副图")
    Thread.sleep(forTimeInterval: 1.0)
    let canvas = app.otherElements["chart.canvas"]
    let start = spacing()
    note("横屏起点"); shot("横屏缩放-0-起点")

    // 横向捏开：根宽变宽，竖屏那份不动。
    canvas.pinch(withScale: 2.0, velocity: 2.0)
    XCTAssertTrue(waitUntil(timeout: Self.short) { spacing() > start * 1.3 }, "捏开后根宽没变宽：\(start) → \(spacing())")
    Thread.sleep(forTimeInterval: 0.8)
    let wide = spacing()
    note("捏开"); shot("横屏缩放-1-捏开")
    XCTAssertTrue(waitUntil(timeout: Self.short) { abs((layout()["landStored"] ?? 0) - wide) < 0.6 },
                  "横屏捏完松手没落到 landscapeBarSpacing：\(layout()) 图上 \(wide)")
    XCTAssertEqual(layout()["stored"] ?? -1, portraitStored, accuracy: 0.001, "横屏里捏，竖屏那份 barSpacing 被改了：\(layout())")

    // 横向捏合：根宽变窄。
    canvas.pinch(withScale: 0.45, velocity: -2.0)
    XCTAssertTrue(waitUntil(timeout: Self.short) { spacing() < wide * 0.75 }, "捏合后根宽没变窄：\(wide) → \(spacing())")
    Thread.sleep(forTimeInterval: 0.8)
    let narrow = spacing()
    note("捏合"); shot("横屏缩放-2-捏合")
    XCTAssertEqual(layout()["stored"] ?? -1, portraitStored, accuracy: 0.001, "横屏里捏，竖屏那份 barSpacing 被改了：\(layout())")

    // 竖向捏：价格轴放大，根宽不动。
    let zoom0 = zoomY()
    let center = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
    XCTAssertTrue(Self.verticalPinch(center: center, from: 70, to: 230), "合成竖向捏没发出去（XCTest 私有事件接口变了？）")
    XCTAssertTrue(waitUntil(timeout: Self.short) { abs(zoomY() - zoom0) > 0.05 }, "竖向捏后价格轴没缩放：zoomY \(zoom0) → \(zoomY())")
    Thread.sleep(forTimeInterval: 0.8)
    note("竖向捏"); shot("横屏缩放-3-竖向捏价格轴")
    XCTAssertEqual(spacing(), narrow, accuracy: narrow * 0.05, "竖向捏把根宽也改了：\(narrow) → \(spacing())")

    // 回竖屏：按竖屏自己那份根宽重量。
    app.buttons[Ids.drawFinish].tap()
    expectExists(app.buttons[Ids.bottomMe], Self.long, "画完没自己转回竖屏")
    XCTAssertTrue(waitUntil(timeout: Self.long) { abs(spacing() - portraitSpacing) < portraitSpacing * 0.05 },
                  "回竖屏根宽没回到竖屏那份：\(portraitSpacing) → \(spacing())，\(layout())")
    note("回竖屏")
    let back = XCTAttachment(screenshot: app.screenshot()); back.name = "横屏缩放-4-回竖屏根宽不变"; back.lifetime = .keepAlways; add(back)
  }

  /// 两指在 `center` 上下对称地从相距 `from` 张到 `to`（pt，界面坐标），0.5 秒走完。
  ///
  /// 合成事件吃的是**屏幕**坐标（竖着的物理屏），不是横屏界面的坐标：每个点都先在界面里用
  /// `XCUICoordinate` 量好，再取它自己换算出来的 `screenPoint`，朝向一律按竖屏报。
  /// （2026-10-05 首跑直接拿 `frame` 算的点、报横屏朝向，两指落到了图外，什么也没捏到。）
  static func verticalPinch(center: XCUICoordinate, from: CGFloat, to: CGFloat) -> Bool {
    func screen(_ dy: CGFloat) -> CGPoint? {
      (center.withOffset(CGVector(dx: 0, dy: dy)).value(forKey: "screenPoint") as? NSValue)?.cgPointValue
    }
    guard let pathClass = NSClassFromString("XCPointerEventPath") as? NSObject.Type,
          let recordClass = NSClassFromString("XCSynthesizedEventRecord") as? NSObject.Type else { return false }
    typealias InitTouch = @convention(c) (AnyObject, Selector, CGPoint, Double) -> AnyObject
    typealias Move = @convention(c) (AnyObject, Selector, CGPoint, Double) -> Void
    typealias Lift = @convention(c) (AnyObject, Selector, Double) -> Void
    typealias InitRecord = @convention(c) (AnyObject, Selector, NSString, Int) -> AnyObject
    typealias Add = @convention(c) (AnyObject, Selector, AnyObject) -> Void
    typealias Synth = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> Bool
    func imp<T>(_ cls: NSObject.Type, _ name: String, _ type: T.Type) -> T? {
      let sel = NSSelectorFromString(name)
      guard cls.instancesRespond(to: sel) else { return nil }
      return unsafeBitCast(cls.instanceMethod(for: sel), to: type)
    }
    guard let initTouch = imp(pathClass, "initForTouchAtPoint:offset:", InitTouch.self),
          let move = imp(pathClass, "moveToPoint:atOffset:", Move.self),
          let lift = imp(pathClass, "liftUpAtOffset:", Lift.self),
          let initRecord = imp(recordClass, "initWithName:interfaceOrientation:", InitRecord.self),
          let add = imp(recordClass, "addPointerEventPath:", Add.self),
          let synth = imp(recordClass, "synthesizeWithError:", Synth.self) else { return false }
    let alloc = NSSelectorFromString("alloc")
    let steps = 10, duration = 0.5
    var paths: [AnyObject] = []
    for sign in [-1.0, 1.0] {
      guard let p0 = screen(sign * from / 2) else { return false }
      let path = initTouch(pathClass.perform(alloc).takeUnretainedValue(), NSSelectorFromString("initForTouchAtPoint:offset:"), p0, 0)
      for i in 1...steps {
        let t = Double(i) / Double(steps)
        let d = from + (to - from) * t
        guard let p = screen(sign * d / 2) else { return false }
        move(path, NSSelectorFromString("moveToPoint:atOffset:"), p, duration * t)
      }
      lift(path, NSSelectorFromString("liftUpAtOffset:"), duration + 0.05)
      paths.append(path)
    }
    // 1 = UIInterfaceOrientationPortrait：点已经是竖着的屏幕坐标。
    let record = initRecord(recordClass.perform(alloc).takeUnretainedValue(),
                            NSSelectorFromString("initWithName:interfaceOrientation:"), "vertical pinch" as NSString, 1)
    for path in paths { add(record, NSSelectorFromString("addPointerEventPath:"), path) }
    return synth(record, NSSelectorFromString("synthesizeWithError:"), nil)
  }
}
