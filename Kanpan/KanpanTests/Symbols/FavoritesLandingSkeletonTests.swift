import Foundation
import SwiftUI
import Testing
@testable import Kanpan

/// 冷启动落在自选页、自选表还在路上：底上摆几行骨架（体感优化 2026-10-07）。
@Suite("自选落地 · 骨架行")
@MainActor
struct FavoritesLandingSkeletonTests {
  @Test("摆 3–5 行")
  func rowCount() {
    #expect((3...5).contains(FavoritesLandingPlaceholder.rowCount))
  }

  @Test("深浅两套皮肤下都画得出来")
  func rendersInBothThemes() {
    for dark in [false, true] {
      let theme = PanelTheme(dark: dark)
      let renderer = ImageRenderer(content: FavoritesLandingPlaceholder().environment(\.panelTheme, theme)
        .frame(width: 393, height: 700))
      #expect(renderer.uiImage != nil)
    }
  }
}
