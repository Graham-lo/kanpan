import KanpanCore

/// 画线条上露哪几把工具：按这个人自己用得多少排，只露几把常用的。
///
/// 从前竖屏画线条、横屏画线台把面板上那十二把（`Drawing.Kind.palette`）全摆出来，
/// 一排挤满、横屏还要横着滚，把撤销、更多、完成这些按钮都挤到了边上（2026-10-05
/// 用户：「只展示少量常用的，根据用户的使用频率智能展示即可」）。现在条上只露
/// `portraitCount` / `dockCount` 把，其余的一把不少，都在「绘图」面板（`draw.tools`）里。
///
/// 次数记在 `Prefs.drawToolUsage`（随账号同步，同一个人换台手机条上还是那几把）：
/// 每选一次工具 +1（`counted`）。总数一过 `decayCeiling` 就整体减半，
/// 所以它量的是「最近常用」，不是「历史上用过最多」——换了画法习惯几十次之后条上就跟过来。
///
/// 不给用户设置「固定哪几把」（用户定的规矩：能自动的不做成设置）。
enum DrawingToolRank {
  /// 竖屏画线条露几把。
  static let portraitCount = 4
  /// 横屏画线台那条（`DrawingDock`）露几把。
  static let dockCount = 5
  /// 所有工具次数加起来超过它就整体减半（整数除法，减成 0 的删掉）。
  static let decayCeiling = 256

  /// 一次都没用过的工具按这个顺序补位。新人第一次打开看到的就是前几把：
  /// 趋势线、水平线、斐波那契、平行通道、测量——交易员最常用的那几样。
  static let defaultOrder: [Drawing.Kind] = [
    .trend, .hline, .fibonacci, .channel, .measure, .note, .vline, .fibExtension,
    .anchoredVWAP, .fixedVolumeProfile, .anchoredVolumeProfile, .position,
  ]

  /// 条上露哪几把（从左到右）。
  ///
  /// - 用过的按次数从多到少；次数一样按面板顺序（`Drawing.Kind.palette`）。
  /// - 没用过的按 `defaultOrder` 补齐。
  /// - `held`：这一回刚从面板里挑的、不在前几把里的那把，顶掉最后一格——
  ///   手上拿着的工具条上一定看得见、点得着第二次。
  static func shown(usage: [String: Int], count: Int, held: Drawing.Kind? = nil) -> [Drawing.Kind] {
    let palette = Drawing.Kind.palette
    let used = palette
      .compactMap { kind -> (Drawing.Kind, Int, Int)? in
        guard let n = usage[kind.rawValue], n > 0, let at = palette.firstIndex(of: kind) else { return nil }
        return (kind, n, at)
      }
      .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
      .map(\.0)
    var order = used
    for kind in defaultOrder where !order.contains(kind) { order.append(kind) }
    for kind in palette where !order.contains(kind) { order.append(kind) }
    var picked = Array(order.prefix(max(0, count)))
    if let held = held.map(head), palette.contains(held), !picked.contains(held), !picked.isEmpty {
      picked[picked.count - 1] = held
    }
    return picked
  }

  /// 选了一次 `kind` 之后的次数表。面板外的变体（射线、水平射线……）记在它那一格名下
  /// （`paletteHead`），不在面板上的不记——表里最多十二个键。
  static func counted(_ usage: [String: Int], _ kind: Drawing.Kind) -> [String: Int] {
    let kind = head(kind)
    guard Drawing.Kind.palette.contains(kind) else { return usage }
    var next = usage.filter { $0.value > 0 }
    next[kind.rawValue, default: 0] += 1
    if next.values.reduce(0, +) > decayCeiling {
      next = next.mapValues { $0 / 2 }.filter { $0.value > 0 }
    }
    return next
  }

  /// 面板上代表它的那一格：变体归到族首（射线 → 趋势线），本身就在面板上的不变。
  static func head(_ kind: Drawing.Kind) -> Drawing.Kind { kind.paletteHead ?? kind }
}
