import Foundation
import SwiftUI
import Testing
@testable import Kanpan

/// 板块页第一次装好、第一趟行情还没回来：摆几行骨架，不再整块留白（体感优化 2026-10-07）。
@Suite("板块页 · 第一趟在路上的骨架")
@MainActor
struct SectorBoardSkeletonTests {
  @Test("第一趟在路上摆骨架；取数确实失败摆空态；有数摆真表")
  func contentDecision() {
    #expect(SectorBoardContent.of(showsEmptyState: false, hasStats: false) == .skeleton)
    #expect(SectorBoardContent.of(showsEmptyState: true, hasStats: false) == .failed)
    #expect(SectorBoardContent.of(showsEmptyState: false, hasStats: true) == .list)
  }

  @Test("摆 6–8 行，行与行宽度错开、每次摆出来都一样")
  func rowsAreStableAndVaried() {
    #expect((6...8).contains(SectorBoardSkeleton.rowCount))
    let widths = (0..<SectorBoardSkeleton.rowCount).map { Skeleton.width($0, base: 52, spread: 44) }
    #expect(Set(widths).count > SectorBoardSkeleton.rowCount / 2)
    #expect(widths == (0..<SectorBoardSkeleton.rowCount).map { Skeleton.width($0, base: 52, spread: 44) })
    #expect(widths.allSatisfy { $0 >= 52 && $0 <= 96 })
  }

  @Test("深浅两套皮肤下都画得出来")
  func rendersInBothThemes() {
    for dark in [false, true] {
      let theme = PanelTheme(dark: dark)
      let renderer = ImageRenderer(content: SectorBoardSkeleton().environment(\.panelTheme, theme)
        .frame(width: 393, height: 600))
      #expect(renderer.uiImage != nil)
    }
  }
}
