import UIKit
import os

// MARK: - 触觉

/// 全 app 图外的触觉都从这儿出（G11、P2.9），各管一件事：
/// 轻点 `tap`（点星、扫到头），落定 `press`（选中、拖完排序），换一档 `step`，提醒响了 `alarm`；
/// 一件事办成了（记下、判定、登录）`success`；拿掉了东西（删除、恢复默认、清缓存、退出）`warning`。
///
/// 图上自己的那几下（十字线、磁吸、缩放到边界、删画线）在 KanpanChart 的 `ChartHaptics` 里。
/// 以前这一套也住在 KanpanChart，十来个跟图表无关的页面为了震一下都得 `import KanpanChart`。
///
/// 生成器留着不重建：`prepare()` 之后系统会把 Taptic Engine 预热，每次现 new 一个
/// 第一下会晚几十毫秒。
@MainActor
enum Haptics {
  private static let light = UIImpactFeedbackGenerator(style: .light)
  private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
  private static let selection = UISelectionFeedbackGenerator()
  private static let medium = UIImpactFeedbackGenerator(style: .medium)
  private static let notice = UINotificationFeedbackGenerator()

  /// 轻点一下：加减自选这类随手的开关。
  static func tap() { trace("tap"); light.impactOccurred() }

  /// 实一点的一下：选中一只、拖完排序这类「落定」。
  static func press() { trace("press"); medium.impactOccurred() }

  /// 换了一档：换周期、扫到下一只、副图挪了一格。
  static func step() { trace("step"); selection.selectionChanged() }

  /// 提醒响了（前台）。
  static func alarm() { trace("alarm"); rigid.impactOccurred() }

  /// 一件事办成了：记下一笔、判定、登录成功。
  static func success() { trace("success"); notice.notificationOccurred(.success) }

  /// 拿掉了东西：删除、恢复默认、清缓存、退出登录。都能撤销或重来，所以是提醒不是报错。
  static func warning() { trace("warning"); notice.notificationOccurred(.warning) }

  /// 模拟器上摸不到震动，只好留一行日志证明「该震的时候真的叫了」（P2.9 验收用，仅 DEBUG）。
  /// 抓法：`/usr/bin/log stream --predicate 'subsystem == "kanpan.haptics"'`。
  private static func trace(_ kind: StaticString) {
    #if DEBUG
    os_log("haptic %{public}s", log: traceLog, type: .default, "\(kind)")
    #endif
  }
  #if DEBUG
  private static let traceLog = OSLog(subsystem: "kanpan.haptics", category: "haptics")
  #endif
}
