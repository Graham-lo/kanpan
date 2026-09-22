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
// 起点在哪：app 入口 `KanpanApp.swift` 的 `init()` 里已经调了
// `DiagnosticsCenter.shared.start()`（订阅赶在界面起来之前，晚一次就少一天数据）。
// `start()` 幂等，重复叫没事；首次调用还会把 `MXMetricManager.shared.pastPayloads`
// 补收一遍。接线已完成，见 docs/acceptance/M9.md §6。

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
    #if canImport(MetricKit) && os(iOS)
      // 订阅本身必须同步挂上（见上面第 1 条），这一步几乎不花时间。
      // 挂 / 摘都放在锁里：`subscriber` 是 lazy var，锁外首次取值会和并发的
      // start/stop 抢着初始化，而且「started 已经是 false 但订阅还挂着」这种
      // 半截状态也只有和开关同一把锁才排得掉。回调只进 `store.ingest`（它有自己
      // 的锁），不回头拿这把，所以不会自锁。
      if first { MXMetricManager.shared.add(subscriber) }
    #endif
    lock.unlock()
    guard first else { return }

    #if canImport(MetricKit) && os(iOS)
      // `pastPayloads` / `pastDiagnosticPayloads` 是**已经交付过**的历史副本，
      // 系统留最近 24 份。首次装上订阅（或用户升级到带诊断的版本）时补收一次，
      // 否则「装了新版之前的崩溃」全看不到。重复的那些会被 id 去重吗？不会——
      // 所以只在第一次 start 时补，靠上面的 `first` 挡住。
      //
      // 补收这一段是**冷启动主线程上最贵的一笔**：最多 24 份，每份都要 JSON 化、
      // 解一遍、算摘要、写一次盘，再加一次淘汰扫描。`start()` 是在 `KanpanApp.init()`
      // 里、Scene 还没起来之前调的，压在那儿等于白等。MetricKit 真正的回调本来
      // 就不在主线程（上面第 2 条），挪到后台不改任何语义。
      Task { @MainActor in
        // payload 对象只能在这儿摸，取出字节就够了，剩下的活全丢给后台。
        let metrics = MXMetricManager.shared.pastPayloads.map { $0.jsonRepresentation() }
        let diagnostics = MXMetricManager.shared.pastDiagnosticPayloads.map { $0.jsonRepresentation() }
        guard !metrics.isEmpty || !diagnostics.isEmpty else { return }
        let store = self.store
        Task.detached(priority: .utility) {
          for data in metrics { store.ingest(data, kind: .metric) }
          for data in diagnostics { store.ingest(data, kind: .diagnostic) }
        }
      }
    #endif
  }

  /// 取消订阅。app 里用不到（进程活多久订阅多久），留给单测和预览。
  func stop() {
    lock.lock()
    defer { lock.unlock() }
    guard started else { return }
    started = false
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
