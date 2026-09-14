import Foundation

// ============================================================ MetricKit 订阅
//
// 任务书 §13 M9：「崩溃收集（MetricKit，不引 SDK）」。这里就是那个「不引 SDK」的
// 全部实现——系统框架 `MetricKit` 一个，零第三方。
//
// MetricKit 的三条铁律（踩过才知道，写在这儿省得下次再查）：
//   1. **订阅必须在启动早期就挂上**，而且要挂在一个活到进程结束的对象上。
//      `MXMetricManager` 对 subscriber 是**弱引用**，局部变量一出作用域就静悄悄
//      不再回调，也不报错。所以这里用单例。
//   2. **回调不在主线程**，而且只在 app **下次启动之后**才把攒着的 payload 交过来。
//      崩溃发生在周一、周二打开才收得到，收到那一刻不存盘就永久丢失
//      （`MXMetricManager` 不会补发第二次）。
//   3. **模拟器上永远不回调**。这是 MetricKit 的设计，不是 bug。所以模拟器上
//      唯一能验的是「注入假 payload 后落盘、摘要、导出都对」——正是单测干的事，
//      也正是 `simulateReceive(_:kind:)` 存在的理由。
//
// 起点在哪：app 入口（`KanpanApp.swift`）得调一次 `DiagnosticsCenter.shared.start()`。
// 这轮不许改入口文件，所以这一行还没接上，见 docs/acceptance/M9.md「待接线」。

#if canImport(MetricKit) && os(iOS)
  import MetricKit
#endif

/// 诊断中枢。单例，因为 `MXMetricManager` 弱引用 subscriber（见上面第 1 条）。
final class DiagnosticsCenter: @unchecked Sendable {

  static let shared = DiagnosticsCenter()

  let store: DiagnosticsStore

  private let lock = NSLock()
  private var started = false

  init(store: DiagnosticsStore = DiagnosticsStore()) {
    self.store = store
  }

  /// 挂上订阅。重复调用是安全的（幂等）。
  ///
  /// 放在 `KanpanApp.init()` 里调，越早越好：MetricKit 在 app 启动后不久就会把
  /// 上一轮攒的 payload 推过来，挂晚了那一批就错过了。
  func start() {
    lock.lock()
    let first = !started
    started = true
    lock.unlock()
    guard first else { return }

    #if canImport(MetricKit) && os(iOS)
      MXMetricManager.shared.add(subscriber)
      // `pastPayloads` / `pastDiagnosticPayloads` 是**已经交付过**的历史副本，
      // 系统留最近 24 份。首次装上订阅（或用户升级到带诊断的版本）时补收一次，
      // 否则「装了新版之前的崩溃」全看不到。重复的那些会被 id 去重吗？不会——
      // 所以只在第一次 start 时补，靠上面的 `first` 挡住。
      for p in MXMetricManager.shared.pastPayloads {
        store.ingest(p.jsonRepresentation(), kind: .metric)
      }
      for p in MXMetricManager.shared.pastDiagnosticPayloads {
        store.ingest(p.jsonRepresentation(), kind: .diagnostic)
      }
    #endif
  }

  /// 取消订阅。app 里用不到（进程活多久订阅多久），留给单测和预览。
  func stop() {
    lock.lock()
    let was = started
    started = false
    lock.unlock()
    guard was else { return }
    #if canImport(MetricKit) && os(iOS)
      MXMetricManager.shared.remove(subscriber)
    #endif
  }

  /// **注入假 payload**。单测、模拟器取证、`#Preview` 都走这条，
  /// 走的是和真回调**完全同一条**代码路径（`store.ingest`），
  /// 所以模拟器上验过的行为在真机上不会另一个样。
  @discardableResult
  func simulateReceive(_ data: Data, kind: PayloadKind) -> DiagnosticsRecord? {
    store.ingest(data, kind: kind)
  }

  #if canImport(MetricKit) && os(iOS)
    private lazy var subscriber = Subscriber(center: self)

    /// `MXMetricManagerSubscriber` 要求 `NSObject`。中枢本身不继承 NSObject
    /// （它要在非 iOS 平台上也编得过），所以单独一层壳。
    private final class Subscriber: NSObject, MXMetricManagerSubscriber {
      private let center: DiagnosticsCenter
      init(center: DiagnosticsCenter) { self.center = center }

      func didReceive(_ payloads: [MXMetricPayload]) {
        for p in payloads { center.store.ingest(p.jsonRepresentation(), kind: .metric) }
      }

      func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for p in payloads { center.store.ingest(p.jsonRepresentation(), kind: .diagnostic) }
      }
    }
  #endif
}
