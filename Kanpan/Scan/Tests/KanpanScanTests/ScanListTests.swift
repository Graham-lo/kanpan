import Testing
@testable import KanpanScan

// 连续扫图的名单（§10.1）。冻结之后这张表的顺序不再变，横滑就是在这张表上走一格。

@Suite("连续扫图的名单")
struct ScanListTests {

  @Test("按冻结时的顺序走，向后是下一只、向前是上一只")
  func stepsAlongTheFrozenOrder() {
    let list = ScanList(["BTCUSDT", "ETHUSDT", "SOLUSDT"])
    #expect(list.step(from: "BTCUSDT", .next) == .move("ETHUSDT"))
    #expect(list.step(from: "ETHUSDT", .next) == .move("SOLUSDT"))
    #expect(list.step(from: "SOLUSDT", .previous) == .move("ETHUSDT"))
  }

  @Test("到头不循环，只报一声「到边了」")
  func doesNotWrapAround() {
    let list = ScanList(["BTCUSDT", "ETHUSDT"])
    #expect(list.step(from: "ETHUSDT", .next) == .edge)
    #expect(list.step(from: "BTCUSDT", .previous) == .edge)
  }

  @Test("手里这只不在名单里就什么都不做——连触感都不给")
  func staysSilentForSymbolsOutsideTheList() {
    let list = ScanList(["BTCUSDT", "ETHUSDT"])
    // 走进图之后又从顶栏搜了一只：那一只没冻结名单，这一趟就算结束了。
    #expect(list.step(from: "DOGEUSDT", .next) == .unavailable)
  }

  @Test("只有一只的名单等于没冻结")
  func oneRowIsNotScannable() {
    let list = ScanList(["BTCUSDT"])
    #expect(!list.isScannable)
    #expect(list.step(from: "BTCUSDT", .next) == .unavailable)
    #expect(ScanList([]).isScannable == false)
  }

  @Test("大小写与重复行都先收拾干净")
  func normalisesInput() {
    let list = ScanList(["btcusdt", "", "BTCUSDT", "ethusdt"])
    #expect(list.symbols == ["BTCUSDT", "ETHUSDT"])
    #expect(list.index(of: "ethusdt") == 1)
    #expect(list.step(from: "btcusdt", .next) == .move("ETHUSDT"))
  }
}
