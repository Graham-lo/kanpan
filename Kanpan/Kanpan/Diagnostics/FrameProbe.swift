#if os(iOS)

  import Foundation
  import QuartzCore
  import UIKit

  // ============================================================ 进程内帧耗时采集
  //
  // 任务书 P9.3 那行写着「**自埋计时** + Time Profiler」。这就是自埋的那半边。
  //
  // ## 为什么不去改 ChartView
  //
  // 最直接的做法是在 `ChartView.onFrame()` / `drawPlot` 前后各打一个时间戳。
  // 但那要改绘制层，而绘制层是 M3 已经封了的（176 张逐像素基线压着）。
  // 这里改用**完全不侵入**的办法，两条腿：
  //
  //   1. `CADisplayLink` —— 拿 `timestamp` / `targetTimestamp`。
  //      前者是上一帧显示的时刻，后者是这一帧将要显示的时刻，两者之差就是系统
  //      **当前**认定的帧间隔（会随低电量、降频、后台变，所以每帧都取，不写死 8.33）。
  //      相邻两次回调 `timestamp` 的实际间隔一旦明显大于这个值，就是掉帧。
  //
  //   2. `CFRunLoopObserver` —— 拿主线程这一帧到底忙了多久。
  //      主 runloop 一轮的形状是：`afterWaiting`（醒来）→ 各种 source / timer /
  //      DisplayLink 回调 → CoreAnimation 的 commit observer（order 2000000）
  //      → `beforeWaiting`（重新睡下）。
  //      所以「醒来 → 睡下」这一段，**恰好**盖住了 ChartView 的 `flush()`、
  //      三层 `CALayer` 的 `draw(in:)`、以及 CA 的 commit + 提交给渲染服务。
  //      在 `afterWaiting` 挂一个 order 最小的观察者、`beforeWaiting` 挂一个
  //      order 最大的观察者，一减就是这一帧的主线程忙时。
  //
  // ## 这个数是什么、不是什么
  //
  // **是**：这一帧主线程上发生的一切（手势处理 + 指标增量 + 三层绘制 + CA commit）。
  // **不是**：单独的 `drawPlot` 耗时。它是 P9.3「三层合计」的**上界**——
  // 上界 < 3ms 就说明绘制一定 < 3ms，所以用来判预算是安全的、不会放水；
  // 反过来超了，得用 Time Profiler 才知道是谁超的。
  //
  // GPU 侧完全看不到（那是渲染服务进程的事），要看只能 Instruments。
  //
  // ## 怎么用
  //
  //     FrameProbe.shared.start(label: "拖动")
  //     ...手动拖 60 秒...
  //     FrameProbe.shared.stop()          // 自动存盘
  //
  // 或者一条龙：`FrameProbe.shared.record(label: "拖动", seconds: 60)`。
  // 取证脚本 `Tools/pull-diagnostics.sh` 负责把存下来的 JSON 从沙盒里捞出来排成表。

  @MainActor
  final class FrameProbe {

    static let shared = FrameProbe()

    private let store: FrameReportStore
    private var stats = FrameStats()

    private var link: CADisplayLink?
    private var wakeObserver: CFRunLoopObserver?
    private var sleepObserver: CFRunLoopObserver?

    /// 这一轮 runloop 醒来的时刻。`afterWaiting` 写，`beforeWaiting` 读完清掉。
    private var wokeAt: Double?
    /// 这一轮 runloop 里 DisplayLink 报的帧。没有帧就说明这轮不是为了画图醒的
    /// （可能是网络回调），不记样本。
    private var pendingFrame: (timestamp: Double, target: Double)?

    private(set) var label: String = ""
    private(set) var isRunning = false

    init(store: FrameReportStore = FrameReportStore()) {
      self.store = store
    }

    var reportStore: FrameReportStore { store }

    // ---------------------------------------------------------------- 开 / 关

    /// 开始采。`label` 写清楚这段在干嘛（拖动 / 捏合 / 甩 / 静止），它会进文件名。
    func start(label: String) {
      guard !isRunning else { return }
      isRunning = true
      self.label = label
      stats.reset()
      wokeAt = nil
      pendingFrame = nil

      let l = CADisplayLink(target: Proxy(self), selector: #selector(Proxy.tick(_:)))
      // 采集期间要求满帧：不写这行的话系统可能把探针自己降到 60Hz，
      // 量出来的 measuredHz 就不是 app 真实跑的速率。
      l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
      // `.common` 而不是 `.default`：手指按在屏幕上拖的时候 runloop 在
      // `UITrackingRunLoopMode`，`.default` 下回调直接停——而拖动恰恰是 P9.2 要测的场景。
      l.add(to: .main, forMode: .common)
      link = l

      installObservers()
    }

    /// 停止采集并存盘，返回这一段的报告。没采到帧返回 nil。
    @discardableResult
    func stop() -> FrameReport? {
      guard isRunning else { return nil }
      isRunning = false

      link?.invalidate()
      link = nil
      removeObservers()

      guard !stats.isEmpty else { return nil }
      let report = stats.report(label: label, device: Self.deviceTag())
      stats.reset()
      store.save(report)
      return report
    }

    /// 采固定时长。到点自动停并回调。
    func record(
      label: String, seconds: Double, completion: (@MainActor @Sendable (FrameReport?) -> Void)? = nil
    ) {
      start(label: label)
      Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(seconds))
        // 必须先把 `stop()` 单独算出来再传。写成 `completion?(self?.stop())` 的话，
        // `completion` 为 nil 时**整个实参都不求值**（可选链短路），采集就永远停不下来——
        // 而「不带回调、到点自动存盘」正是这个方法最常见的用法。
        let report = self?.stop()
        completion?(report)
      }
    }

    // ---------------------------------------------------------------- runloop 观察者

    private func installObservers() {
      let rl = CFRunLoopGetMain()

      // order 用 Int.min / Int.max：醒来时要排在所有人**前面**，
      // 睡下时要排在所有人**后面**（尤其是 CoreAnimation 的 commit，order 2000000），
      // 否则量出来的忙时会漏掉 commit 那一段——而 commit 正是三层重绘真正发生的地方。
      let wake = CFRunLoopObserverCreateWithHandler(
        nil, CFRunLoopActivity.afterWaiting.rawValue, true, CFIndex.min
      ) { [weak self] _, _ in
        MainActor.assumeIsolated { self?.wokeAt = CACurrentMediaTime() }
      }
      let sleep = CFRunLoopObserverCreateWithHandler(
        nil, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max
      ) { [weak self] _, _ in
        MainActor.assumeIsolated { self?.closeFrame() }
      }
      CFRunLoopAddObserver(rl, wake, .commonModes)
      CFRunLoopAddObserver(rl, sleep, .commonModes)
      wakeObserver = wake
      sleepObserver = sleep
    }

    private func removeObservers() {
      let rl = CFRunLoopGetMain()
      if let o = wakeObserver { CFRunLoopRemoveObserver(rl, o, .commonModes) }
      if let o = sleepObserver { CFRunLoopRemoveObserver(rl, o, .commonModes) }
      wakeObserver = nil
      sleepObserver = nil
      wokeAt = nil
      pendingFrame = nil
    }

    fileprivate func onTick(_ link: CADisplayLink) {
      pendingFrame = (link.timestamp, link.targetTimestamp)
      // runloop 已经醒着但没走 `afterWaiting`（比如嵌套 runloop）时 `wokeAt` 是 nil，
      // 退回到「回调进来的这一刻」，这样忙时只少算不多算。
      if wokeAt == nil { wokeAt = CACurrentMediaTime() }
    }

    /// runloop 要睡了：这一帧的账在这里结。
    private func closeFrame() {
      defer {
        wokeAt = nil
        pendingFrame = nil
      }
      guard isRunning, let frame = pendingFrame, let start = wokeAt else { return }
      stats.add(
        FrameSample(
          timestamp: frame.timestamp,
          targetTimestamp: frame.target,
          callbackStart: start,
          callbackEnd: CACurrentMediaTime()))
    }

    // ---------------------------------------------------------------- 杂项

    /// `"iPhone17,1 · iOS 26.5 · 120Hz"`。证据表要靠它认是哪台机器。
    static func deviceTag() -> String {
      var sys = utsname()
      uname(&sys)
      // 先把定长 C 数组整个拷成 tuple 再取指针：直接对 `&sys.machine` 取指针，
      // 同一条语句里既读 `sys.machine` 又量它的大小，Swift 6 判成重叠访问。
      let raw = sys.machine
      let machine = withUnsafePointer(to: raw) {
        $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: raw)) {
          String(cString: $0)
        }
      }
      let hz = UIScreen.main.maximumFramesPerSecond
      return "\(machine) · iOS \(UIDevice.current.systemVersion) · \(hz)Hz"
    }

    /// `CADisplayLink` 强引用 target，直接指向探针就成环了。
    /// 这层壳弱引用——和 `ChartView.LinkProxy` 是同一个套路。
    //
    // 整个类标 `@MainActor`：`CADisplayLink` 的回调本来就在主线程（我们是
    // `add(to: .main, ...)` 的），但编译器不知道，于是 `assumeIsolated` 里
    // 捕获 `self` / `link` 会被判成「把非 Sendable 的东西送出隔离域」。
    // 标上之后 `@objc` 方法本身就是主线程隔离的，不用再 assume。
    @MainActor
    private final class Proxy {
      weak var probe: FrameProbe?
      init(_ p: FrameProbe) { probe = p }
      @objc func tick(_ link: CADisplayLink) {
        probe?.onTick(link)
      }
    }
  }

#endif
