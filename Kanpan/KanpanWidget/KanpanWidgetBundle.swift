import SwiftUI
import WidgetKit

/// Hkline 的小组件扩展：桌面两种尺寸（自选四行 / 一只品种的折线），
/// 以及提醒「盯一个」的锁屏实时活动。
///
/// 数据全从 App Group 里那份快照读（`WidgetSnapshot`，app 刷到行情就写），
/// 刷新时自己再补一口新价（`LiveQuotes`），取不到就照快照画。
@main
struct KanpanWidgetBundle: WidgetBundle {
  var body: some Widget {
    FavoritesWidget()
    SymbolWidget()
  }
}
