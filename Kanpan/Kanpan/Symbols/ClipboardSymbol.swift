import Foundation
import KanpanCore
#if canImport(UIKit)
import UIKit
#endif

// ============================================================ 剪贴板
//
// 人常常是在别处看到一个代号才来搜的：群里发的 `SOLUSDT`、交易所网页上的
// `SOL/USDT`、推特上的 `$SOL`。他复制了一下，然后打开这个 app——这一刻我们
// 已经知道他要找什么了，不该再让他把同一个词打一遍
// （方案 `71bd340:docs/提醒与体验细节-实施方案-2026-09-20.md` 第 3 节第二件）。
//
// 规矩（都写在实现里，别放宽）：
//
// · **只在搜索页出现的那一刻看一次**。不监听、不轮询、不在后台看。
// · **`changeCount` 没变就直接跳过**，同一份剪贴板只提示一次——已经摆过一次
//   而他没点，就是不想要，再摆就是骚扰。
// · **认不出来就什么都不显示**。不摆「剪贴板里没有可识别的内容」这种话。
//
// ------------------------------------------------------------ 为什么不是「打开 SOL」
//
// 方案里写的是「认出来就在最上面摆一行『打开 SOL』」。做不到，而且是系统不让：
// 2026-09-20 在 iPhone 17e（iOS 26.5）上实测，`detectedPatterns` 这一步确实
// 不惊动人——它只回答「这看着像不像一段能搜的文字」，秒回；但**只要去取那段
// 文字本身**（`detectedValues(for: [\.probableWebSearch])`、`detectValues(for:)`、
// 或者直接读 `UIPasteboard.general.string`），系统就当场弹一个
// 「『Hkline』想从『X』粘贴 / 你允许这样做吗？」，在他按之前那个调用一直挂着
// （`string` 是同步的，还会把主线程一起挂住）。也就是说：**要在屏幕上写出
// 「SOL」这两个字，就得先弹一次询问**——为了省他一次打字而先拦他一道，
// 这笔买卖不划算，何况他可能根本没打算搜剪贴板里那个东西。
//
// 所以这一行改成系统自己的粘贴按钮（SwiftUI `PasteButton` / `UIPasteControl`）：
// 他按一下，内容直接交到 app 手里，**全程没有任何询问**——因为这一按就是他的
// 许可。按下去之后认得出来就直接开那张图，认不出来就把那段文字填进搜索框。
// 少写了一个币名，换来的是一次询问都不弹。
enum ClipboardSymbol {
  /// 把剪贴板里那段文字解析成一个合约。认不出来返回 nil。
  ///
  /// 认的形状就是搜索框认的那些（`SymbolQuery.normalize` 去分隔符 + `SymbolAliases`
  /// 的中文与拼音）：`SOLUSDT` / `SOL/USDT` / `$SOL` / `sol` / `索拉纳` / `suolana`。
  /// 但门槛比搜索高一档：只收「最匹配」和「全拼」两档。剪贴板是我们**替他猜的**，
  /// 猜错一次比不猜更烦——`USD` 这种含在一堆合约里的片段、`btb` 这种首字母缩写，
  /// 在搜索结果里列出来没问题，单独顶成一行「打开 XX」就太自作主张了。
  static func resolve(_ text: String, catalog: [SymbolInfo]) -> SymbolInfo? {
    // 整段复制的文章不看：真正的代号不会有 32 个字符。先挡掉再说，免得对着
    // 一整页文字跑一遍全表匹配。
    let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty, raw.count <= 32, !raw.contains("\n") else { return nil }
    let q = SymbolQuery.normalize(raw)
    guard !q.isEmpty else { return nil }
    let hits = SymbolQuery.match(catalog, query: q)
    guard let best = hits.first, best.tier <= .pinyinFull else { return nil }
    // 同一个词同时精确命中两个合约是不可能的（代号唯一），但全拼那一档可能
    // 撞上（「黄金」既是 PAXG 又是 XAUT）——撞了就不猜，让他自己搜。
    if hits.count > 1, hits[1].tier == best.tier { return nil }
    return best.info
  }

  #if canImport(UIKit)
  /// 上一次已经看过的那份剪贴板。`UIPasteboard.changeCount` 每换一次内容加一，
  /// 所以它既是「这份看过了」的记号，也是「同一份只摆一次」的实现。
  @MainActor private static var seen: Int?

  /// 剪贴板里有没有一段「像是能拿去搜的文字」。
  ///
  /// 只问 `detectedPatterns`——它由系统在自己家里判定，不把内容交给 app，
  /// 所以不弹「允许粘贴？」。返回 true 只表示「值得摆一个粘贴按钮」，
  /// 至于那段文字是什么，等他按了那个按钮再说（见文件头那段）。
  ///
  /// 同一份剪贴板只回答一次 true。
  @MainActor static func hasText() async -> Bool {
    let board = UIPasteboard.general
    let count = board.changeCount
    guard seen != count else { return false }
    seen = count
    let keys: Set<PartialKeyPath<UIPasteboard.DetectedValues>> = [\.probableWebSearch]
    guard let found = try? await board.detectedPatterns(for: keys) else { return false }
    return found.contains(\.probableWebSearch)
  }

  /// 测试用：把「看过」的记号清掉。
  @MainActor static func forget() { seen = nil }
  #endif
}
