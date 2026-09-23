import Testing

@testable import KanpanCore

/// 同一种画法界面上只能有一个名字（2026-09-23）：样式表「画法」一排按钮上写「两端延伸」，
/// 画出来之后选中条、提醒确认条、提醒列表却叫「直线」，用户分不清是不是一回事。
/// 名字只存一份在 `Kind.title`，那排按钮直接取它。
@Suite("画线：画法在各处只有一个名字")
struct DrawingKindNameTests {
  @Test("样式表那排按钮上的字就是这种画法的名字")
  func swapLabelsAreKindTitles() {
    for head in Drawing.Kind.palette {
      for swap in head.swaps {
        for option in swap.options where option.kind != head {
          #expect(option.label == option.kind.title, "\(option.kind.rawValue)")
        }
      }
    }
  }

  @Test("向右延伸 / 两端延伸 / 十字线")
  func namesMatchTheStyleSheet() {
    #expect(Drawing.Kind.ray.title == "向右延伸")
    #expect(Drawing.Kind.extended.title == "两端延伸")
    #expect(Drawing.Kind.hray.title == "向右延伸")
    #expect(Drawing.Kind.crossLine.title == "十字线")
    #expect(Drawing.Kind.hline.swaps.first?.options.map(\.label) == ["整条", "向右延伸"])
    #expect(Drawing.Kind.trend.swaps.first?.options.map(\.label) == ["线段", "向右延伸", "两端延伸", "箭头"])
  }

  @Test("老提醒的线名显示成现在的叫法，存的 title 不动")
  func legacyAlertLineNames() {
    func alert(_ title: String) -> Alert {
      Alert(symbol: "BTCUSDT", drawingID: "d1", lines: [], condition: .touch,
            armedAt: 0, status: .active, title: title, created: 0)
    }
    #expect(alert("BTC 触到你画的直线").lineName == "两端延伸")
    #expect(alert("BTC 触到你画的射线").lineName == "向右延伸")
    #expect(alert("BTC 触到你画的水平射线").lineName == "向右延伸")
    #expect(alert("BTC 触到你画的趋势线").lineName == "趋势线")
    #expect(alert("BTC 触到你画的直线").title == "BTC 触到你画的直线")
    #expect(Alert.title(symbol: "BTCUSDT", drawingKind: .extended) == "BTC 触到你画的两端延伸")
  }
}
