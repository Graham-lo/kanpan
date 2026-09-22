import KanpanChart
import KanpanCore
import UIKit

/// 一屏 `ChartView`，喂定版快照，画完就**什么都不做**。
///
/// 两种模式（`simctl launch --args` 选）：
/// - 不带参数：纯静止。进程里除了 `ChartView` 那条 `CADisplayLink` 没有任何定时器，
///   Time Profiler 采到的就是「静止」本身。CPU 百分比从这一路取。
/// - `--probe`：多一条 1 Hz 的观察定时器，把 `CADisplayLink` 的 `isPaused` 和
///   `timestamp` 打到 stdout。用来证明 A3.12 前半句（link 真的停了），
///   代价是自己引入了每秒一次的唤醒，所以**不拿这一路的 CPU 数当结论**。
@MainActor
final class HostViewController: UIViewController {
  private let chart = ChartView(frame: .zero)
  private let banner = UILabel()
  private let probing = ProcessInfo.processInfo.arguments.contains("--probe")

  private var built = false
  private var snapshot: HostFixture.Snapshot?

  /// 窗口：静止观察从 `windowStart` 起算，共 `windowSeconds` 秒。
  private static let settleSeconds = 5.0
  private static let windowSeconds = 30.0

  private var t0: Double = 0
  private var samples: [DisplayLinkProbe.Sample] = []
  private var windowTimer: Timer?

  override func viewDidLoad() {
    super.viewDidLoad()
    setvbuf(stdout, nil, _IOLBF, 0)

    snapshot = HostFixture.load()
    view.addSubview(chart)

    banner.numberOfLines = 0
    banner.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    banner.textAlignment = .center
    banner.isHidden = true
    view.addSubview(banner)

    if snapshot == nil {
      // 空白一屏也「静止」，但那是假证据。读不到 fixture 就把路径糊在屏幕上。
      banner.isHidden = false
      banner.textColor = .systemRed
      banner.text = "读不到定版快照\n\(HostFixture.fixturePath)"
      note("FATAL 读不到 fixture：\(HostFixture.fixturePath)")
    }

    note("模式：\(probing ? "--probe（带 1 Hz 观察定时器）" : "纯静止（无定时器）")")
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    chart.frame = view.bounds
    banner.frame = CGRect(
      x: 8, y: view.bounds.height - 92, width: view.bounds.width - 16, height: 84)
    guard !built, view.bounds.width > 0, view.bounds.height > 0 else { return }
    build()
  }

  // ---------------------------------------------------------------- 造一帧

  private func build() {
    guard let s = snapshot else { return }
    built = true

    let style = CandleStyle.default
    let subs: [IndicatorID] = [.macd, .rsi]
    let dark = traitCollection.userInterfaceStyle == .dark
    let size = view.bounds.size
    let layout = Layout(
      width: Double(size.width), height: Double(size.height), subs: subs)
    let window = ViewMath.reset(
      series: s.series, plotW: layout.plotW, spacing: AICoinBehavior.initialSpacing)

    view.backgroundColor = dark ? .black : .white
    chart.state = ChartState(
      series: s.series, symbol: s.symbolInfo, view: window,
      style: style, dark: dark, redUp: false,
      overlays: [.ma], subs: subs, timezone: .utc, oi: s.oiSeries)

    if ProcessInfo.processInfo.arguments.contains("--compare"), var state = chart.state {
      state.percentAxis = true
      state.compare = ["ETH", "SOL", "DOGE"].enumerated().map { index, name in
        let factor = Double(index + 2)
        return CompareSeries(key: "binance/usd_m/" + name + "USDT", name: name, color: state.colors.palette[index],
          open: s.open.map { $0 / factor }, close: s.close.enumerated().map { bar, value in
            value / factor * (1 + Double(index + 1) * sin(Double(bar) / 11) * 0.002)
          })
      }
      chart.state = state
    }

    note(
      "已喂快照：\(s.symbol) \(s.interval)，\(s.close.count) 根；"
        + "画布 \(Int(size.width))×\(Int(size.height))@\(Int(traitCollection.displayScale))x，"
        + "主题 \(dark ? "深" : "浅")，风格 \(style.id)")

    guard probing else {
      note("纯静止模式：这条日志之后进程不会再主动做任何事。")
      return
    }
    t0 = CACurrentMediaTime()
    schedule()
  }

  // ---------------------------------------------------------------- 观察

  private func schedule() {
    note("")
    note("      t  阶段        link      timestamp")
    // 画完第一帧后 link 应当在下一帧把自己停掉。
    after(1.0) { self.take("settled") }
    // 先证明这个观察点**看得见 link 在跑**：手动置脏，link 必须醒。
    // 不做这一步，「30 秒都是 paused」有可能只是探针本身失灵。
    after(2.0) {
      self.note("      —  poke        setNeedsRedraw(.all)")
      self.chart.setNeedsRedraw(.all)
      self.take("poked")  // 同一 runloop 回合内取，必须读到 RUNNING
    }
    after(3.0) { self.take("repaused") }
    after(Self.settleSeconds) { self.startWindow() }
  }

  private func startWindow() {
    note("      —  window      静止 \(Int(Self.windowSeconds)) 秒开始（不碰屏幕）")
    take("window")
    // 闭包参数那个 `Timer` 不是 `Sendable`，递进 `assumeIsolated` 会被 Swift 6 判成
    // 「sending 有数据竞争风险」。停表改走自己存的那份引用，参数不碰。
    let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        let now = CACurrentMediaTime() - self.t0
        self.take("window")
        if now >= Self.settleSeconds + Self.windowSeconds {
          self.windowTimer?.invalidate()
          self.windowTimer = nil
          self.finish()
        }
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    windowTimer = timer
  }

  private func finish() {
    let window = samples.filter { $0.phase == "window" }
    let running = window.filter { $0.paused == false }
    let missing = window.filter { $0.paused == nil }
    let stamps = Set(window.compactMap(\.timestamp).map { String(format: "%.6f", $0) })

    note("")
    note("== 结论 ==")
    note("静止窗口采样 \(window.count) 次（1 Hz，\(Int(Self.windowSeconds)) 秒）")
    note("其中 isPaused == false（link 在跑）：\(running.count) 次")
    note("其中 没有 link 对象：\(missing.count) 次")
    note("窗口内出现过的 link.timestamp 取值：\(stamps.count) 个 → \(stamps.sorted().joined(separator: ", "))")
    let ok = running.isEmpty && stamps.count <= 1
    note("A3.12 前半句（静止时 DisplayLink 暂停）：\(ok ? "通过" : "不通过")")

    banner.isHidden = false
    banner.textColor = traitCollection.userInterfaceStyle == .dark ? .white : .black
    banner.text =
      "A3.12 探针：窗口 \(window.count) 采样，RUNNING \(running.count) 次，"
      + "timestamp 取值 \(stamps.count) 个 → \(ok ? "PASS" : "FAIL")"
  }

  private func take(_ phase: String) {
    let s = DisplayLinkProbe.sample(chart, phase: phase, t: CACurrentMediaTime() - t0)
    samples.append(s)
    note(s.line)
  }

  private func after(_ d: Double, _ body: @escaping @MainActor () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + d) { MainActor.assumeIsolated(body) }
  }

  private func note(_ s: String) {
    print("A3.12| \(s)")
  }
}
