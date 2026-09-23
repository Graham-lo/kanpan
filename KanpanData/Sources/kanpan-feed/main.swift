import Foundation
import KanpanCore
import KanpanData

// kanpan-feed —— 数据层的命令行取证工具（§13 M2 的证据都从这儿出）。
//
//   kanpan-feed BTCUSDT 1h [--minutes N]   冷启动 + 实时，末根每秒打一行
//   kanpan-feed info [SYMBOL]              exchangeInfo：品种数、tickSize
//   kanpan-feed history BTCUSDT 1h 10      向前翻 10 页，打每页时间戳
//   kanpan-feed snapshot BTCUSDT 1h        写 / 读 last.kbar，打大小和耗时
//   kanpan-feed oi BTCUSDT 1h [--days N]   两个源合成一条 OI 序列
//   kanpan-feed switch BTCUSDT             连续切 20 次，看连接 id 变不变
//   kanpan-feed churn [--symbols N]        随机 N 个品种 × 14 周期，看内存与沙盒
//
// 通用开关：--venue <交易所>（默认是默认交易所）、--route direct|gateway（默认直连）、
// --cache-root <目录>（独立冷缓存）。品种可以写裸代号，也可以写 `venue/market/SYMBOL`。

func nowStamp() -> String {
  // 本地时区的 时:分:秒.毫秒 —— 验收要按日志上的时间戳数间隔（A2.3）。
  let ms = Int64(Date().timeIntervalSince1970 * 1000)
  let off = TimeZone.current.secondsFromGMT() / 60
  let p = DateParts(ms: Double(ms), offsetMinutes: off)
  let sec = Int((ms / 1000) % 60), milli = Int(ms % 1000)
  return String(format: "%02d:%02d:%02d.%03d", p.hour, p.minute, sec, milli)
}
func say(_ s: String) { print("[\(nowStamp())] \(s)"); fflush(stdout) }
let log = FeedLog { say($0) }

/// 事件循环跑在另一个 Task 里，计数得放个 actor，不然 Swift 6 不让捕获。
actor Tally {
  var ids: Set<Int> = []
  var bars = 0
  var ticks = 0
  var prices = 0
  var firstPaintMs: Double?
  func addID(_ i: Int) { ids.insert(i) }
  func bumpBar() { bars += 1 }
  func bumpTick() -> Int { ticks += 1; return ticks }
  func bumpPrice() -> Int { prices += 1; return prices }
  func paint(_ ms: Double) { if firstPaintMs == nil { firstPaintMs = ms } }
  var summary: String {
    "末根更新 \(bars) 次，价格 \(prices) 次，行情 \(ticks) 次，首帧 " + (firstPaintMs.map { String(format: "%.0fms", $0) } ?? "无")
  }
}

func arg(_ i: Int) -> String? {
  let a = CommandLine.arguments
  return i + 1 < a.count ? a[i + 1] : nil
}
func flag(_ name: String) -> String? {
  let a = CommandLine.arguments
  guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
  return a[i + 1]
}
func has(_ name: String) -> Bool { CommandLine.arguments.contains(name) }

let env = ProcessInfo.processInfo.environment
/// 看盘自己的网关（`--route gateway` 与持仓量归档用），逗号分隔，主在前。
let gateways = (env["KANPAN_GATEWAYS"] ?? "").split(separator: ",").map(String.init)
let endpoints = MarketEndpoints(restHost: env["KANPAN_FAPI"], streamHost: env["KANPAN_STREAM"],
                                gateways: gateways)
let route = MarketRoutePolicy(rawValue: flag("--route") ?? "direct") ?? .direct
let venue = VenueRegistry.descriptor(flag("--venue") ?? "") ?? VenueRegistry.default
let provider = RouteResolver(policy: route, endpoints: endpoints, log: has("-v") ? log : .silent)
  .provider(venue: venue.id)
/// 命令行里的品种 → 品种键。裸代号归 `--venue` 那一家。
func key(_ raw: String) -> String {
  raw.contains("/") ? InstrumentID.canonical(raw)
    : InstrumentID(venue: venue.id, market: venue.market, symbol: raw).key
}
// 独立冷缓存可重复测量，避免与其它窗口共用系统临时目录。
let paths = Paths(root: flag("--cache-root").map { URL(fileURLWithPath: $0) }
  ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kanpan-feed"))

func parseInterval(_ s: String?) -> Interval {
  guard let s, let iv = Interval(rawValue: s) else { return .h1 }
  return iv
}

// ---------------------------------------------------------------- 子命令

func cmdInfo() async throws {
  // 走 SymbolCatalog 而不是裸 REST：顺带验掉 Caches 里那份 24 小时的 exchangeInfo（§4.1）。
  let catalog = SymbolCatalog(provider: provider, paths: paths, log: has("-v") ? log : .silent)
  let t0 = Date()
  var list = await catalog.all()
  if list.isEmpty { list = try await provider.instruments() }
  say("\(venue.displayName) 品种 \(list.count) 个，用时 \(Int(-t0.timeIntervalSinceNow * 1000))ms")
  // arg(1) 可能是 -v 这样的开关，别把它当品种名。
  let want = arg(1).flatMap { $0.hasPrefix("-") ? nil : $0 }?.uppercased() ?? venue.defaultSymbol
  if let s = list.first(where: { $0.symbol == key(want) }) {
    say("\(s.symbol)  base=\(s.base)  pricePrecision=\(s.pricePrecision)  qtyPrecision=\(s.quantityPrecision)  tickSize=\(s.tickSize)  小数位=\(s.priceDecimals)")
  }
  for s in list.prefix(5) { say("  \(s.symbol) tick=\(s.tickSize)") }
}

func cmdHistory(_ symbol: String, _ iv: Interval, pages: Int) async throws {
  let t0 = Date()
  let head = try await provider.klines(symbol: symbol, interval: iv, limit: provider.capabilities.maxKlines)
  say("最新一页 \(head.count) 根：\(head.first!.openTime) … \(head.last!.openTime)")
  let bars = try await provider.history(symbol: symbol, interval: iv, pages: pages, before: head.first!.openTime)
  let all = MarketSeries.dedup(bars + head)
  let secs = -t0.timeIntervalSinceNow
  say("翻 \(pages) 页共 \(bars.count) 根，合并后 \(all.count) 根，总用时 \(String(format: "%.2f", secs))s")
  var dup = 0, gap = 0
  for i in 1..<all.count {
    if all[i].openTime == all[i - 1].openTime { dup += 1 }
    if all[i].openTime - all[i - 1].openTime != provider.capabilities.source(for: iv).stepMs { gap += 1 }
  }
  say("重复 \(dup) 处，步长异常 \(gap) 处；区间 \(all.first!.openTime) … \(all.last!.openTime)")
}

func cmdSnapshot(_ symbol: String, _ iv: Interval) async throws {
  let s = try await provider.latestSeries(symbol: symbol, interval: iv, limit: provider.capabilities.maxKlines)
  let url = paths.snapshot
  let n = try Snapshot.write(s, to: url)
  say("写 \(url.path) \(n) 字节（上限 \(Snapshot.maxBytes)）")
  let t0 = Date()
  guard let back = Snapshot.read(url) else { say("读回失败"); return }
  let ms = -t0.timeIntervalSinceNow * 1000
  say("读回 \(back.count) 根，用时 \(String(format: "%.2f", ms))ms")
  let again = Snapshot.encode(back)
  let orig = try Data(contentsOf: url)
  say("逐字节一致：\(again == orig ? "是" : "否")")
  say("末根 \(back.lastTime) close=\(back.close.last ?? .nan)")
}

func cmdOI(_ symbol: String, _ iv: Interval, days: Int) async throws {
  let store = OIStore(paths: paths)
  guard provider.capabilities.hasOpenInterestHistory else { say("\(venue.displayName) 没有持仓量"); return }
  let src = OISource(provider: provider, gateways: gateways, store: store, log: log)
  let now = Int64(Date().timeIntervalSince1970 * 1000)
  let from = now - Int64(days) * 86_400_000
  let t0 = Date()
  let raw = await src.rawPoints(symbol: symbol, interval: iv, from: from, to: now, now: now)
  say("原始点 \(raw.count) 条，用时 \(String(format: "%.2f", -t0.timeIntervalSinceNow))s")
  guard !raw.isEmpty else { return }
  let ds = OISource.downsample(raw, to: iv)
  say("降采样到 \(iv.rawValue)：\(ds.count) 条，\(ds.first!.time) … \(ds.last!.time)")
  var dup = 0
  for i in 1..<ds.count where ds[i].time == ds[i - 1].time { dup += 1 }
  say("重复 \(dup) 处；缓存占用 \(await store.usage()) 字节")
}

func cmdSwitch(_ symbol: String) async throws {
  let ws = provider.makeStream(silenceMs: nil, log: log)
  let stream = await ws.start(topics: [.kline(symbol: symbol, interval: .m1)])
  let tally = Tally()
  let watch = Task {
    for await ev in stream {
      if case .connected(let id) = ev { await tally.addID(id); say("连接 #\(id)") }
    }
  }
  try await Task.sleep(nanoseconds: 2_000_000_000)
  for i in 0..<20 {
    let caps = provider.capabilities
    let iv = caps.source(for: Interval.allCases[i % Interval.allCases.count])
    let first: StreamTopic = caps.liveKlineIntervals.contains(iv) ? .kline(symbol: symbol, interval: iv) : .trade(symbol: symbol)
    await ws.replace(topics: [first] + (caps.hasTickerStream ? [.ticker(symbol: symbol)] : []))
    say("第 \(i + 1) 次切到 \(iv.rawValue)")
    try await Task.sleep(nanoseconds: 200_000_000)
  }
  try await Task.sleep(nanoseconds: 1_000_000_000)
  let ids = await tally.ids
  say("一共建立过 \(ids.count) 条连接：\(ids.sorted())")
  watch.cancel()
  await ws.stop()
}

func cmdChurn(symbols n: Int) async throws {
  // A2.12：随机切 n 个品种 × 14 周期，然后看内存缓存和沙盒。
  // 种子固定，换台机器跑出来的品种顺序一样，好对账。
  let catalog = SymbolCatalog(provider: provider, paths: paths, log: .silent)
  var list = await catalog.all()
  if list.isEmpty { list = try await provider.instruments() }
  var seed: UInt64 = 20260914
  func rnd(_ m: Int) -> Int {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return Int((seed >> 33) % UInt64(m))
  }
  var pool = list.map(\.symbol), picks: [String] = []
  while picks.count < n, !pool.isEmpty { picks.append(pool.remove(at: rnd(pool.count))) }
  say("随机 \(picks.count) 个品种：\(picks.joined(separator: " "))")

  let cache = BarCache()
  let t0 = Date()
  var loaded = 0, failed = 0
  var last = SeriesKey(picks[0], .h1)
  for sym in picks {
    for iv in Interval.allCases {
      do {
        let s = try await provider.latestSeries(symbol: sym, interval: iv, limit: provider.capabilities.maxKlines)
        await cache.put(s)
        last = SeriesKey(sym, s.interval)
        loaded += 1
      } catch { failed += 1 }
    }
    let used = await cache.totalBytes
    say("\(sym) 14 档装完，缓存 \(await cache.count) 条 / \(used / 1024) KB")
  }
  let used = await cache.totalBytes
  say("装了 \(loaded) 条序列（失败 \(failed)），用时 \(String(format: "%.1f", -t0.timeIntervalSinceNow))s")
  say("内存缓存 \(await cache.count) 条 / \(used) 字节 = \(String(format: "%.1f", Double(used) / 1048576)) MB，上限 \(BarCache.defaultLimitBytes / 1048576) MB → \(used <= BarCache.defaultLimitBytes ? "未超" : "超了")")
  let order = await cache.lruOrder
  say("LRU 最旧三条：\(order.prefix(3).map(\.description).joined(separator: " "))")
  say("LRU 最新三条：\(order.suffix(3).map(\.description).joined(separator: " "))")

  await cache.purge(keeping: last)
  say("内存警告后剩 \(await cache.count) 条：\(await cache.keys.map(\.description).joined(separator: " "))")

  // 沙盒清单：除 last.kbar 和 exchangeInfo 缓存外不该有行情文件。
  say("沙盒 \(paths.root.path)：")
  let fm = FileManager.default
  var files: [(String, Int)] = []
  // FileManager.enumerator 的迭代器在 async 上下文里不让用，直接走 subpaths。
  for sub in (try? fm.subpathsOfDirectory(atPath: paths.root.path)) ?? [] {
    let full = paths.root.appendingPathComponent(sub).path
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue else { continue }
    let n = ((try? fm.attributesOfItem(atPath: full))?[.size] as? Int) ?? 0
    files.append((sub, n))
  }
  for (f, n) in files.sorted(by: { $0.0 < $1.0 }) { say("  \(f)  \(n) 字节") }
  let kline = files.filter { !$0.0.hasSuffix("last.kbar") && !$0.0.contains("exchangeInfo") && !$0.0.hasSuffix(".oi") }
  say("合计 \(files.count) 个文件；K 线类文件 \(kline.count) 个（.oi 是 §4.3 允许的 OI 日切片）")
}

func cmdLive(_ symbol: String, _ iv: Interval, minutes: Double) async throws {
  let ws = provider.makeStream(silenceMs: nil, log: log)
  let feed = MarketFeed(provider: provider, stream: ws, cache: BarCache(), paths: paths,
                        // 命令行一次就要单页满深度（和改造前的取证口径一致）。
                        initialLimit: provider.capabilities.maxKlines, log: log)
  let events = await feed.events()
  let t0 = Date()
  let tally = Tally()

  let pump = Task {
    for await ev in events {
      switch ev.event {
      case .routing(let state): say("行情线路：\(state)")
      case .provider(let caps): say("行情源 → \(caps.venue)（上游 \(caps.upstream)）")
      case .historyError(let error): if let error { say(error) }
      case .series(let s):
        await tally.paint(-t0.timeIntervalSinceNow * 1000)
        say("序列 \(s.count) 根  \(s.firstTime) … \(s.lastTime)  末根 close=\(s.close.last ?? .nan)")
      case .lastBar(let b):
        await tally.bumpBar()
        say("末根 \(b.openTime) O=\(b.open) H=\(b.high) L=\(b.low) C=\(b.close) V=\(String(format: "%.3f", b.volume))")
      case .prepend(let n): say("前面补了 \(n) 根")
      case .ticker(let t):
        let n = await tally.bumpTick()
        if n % 10 == 1 { say("行情 last=\(t.last) 涨跌=\(t.changePercent)% 24h高=\(t.high) 低=\(t.low)") }
      case .tradeQuote:
        break
      case .markPrice(_, let price, _):
        _ = await tally.bumpPrice()
        say("标记价 \(price)")
      case .takerTail, .depth: break
      case .oi(let p): say("OI \(p.count) 条")
      case .status(let s): say("状态 → \(s.rawValue)")
      }
    }
  }
  await feed.start(symbol: symbol, interval: iv)
  say("开始：\(symbol) \(iv.rawValue)，跑 \(minutes) 分钟（Ctrl-C 停）")
  try await Task.sleep(nanoseconds: UInt64(minutes * 60 * 1e9))
  say("收工：" + (await tally.summary))
  await feed.stop()
  pump.cancel()
}

func cmdRecord(_ symbol: String, _ interval: Interval, _ count: Int, _ out: String) async throws {
  // 录一段真实报文当回放 fixture（A2.6）。一行一条原始 JSON，外加一行 meta。
  let f = URLSessionSocketFactory()
  guard let url = provider.rawStreamURL(topics: [.kline(symbol: symbol, interval: interval),
                                                 .ticker(symbol: symbol)]) else {
    say("\(venue.displayName) 不支持录原始报文"); return
  }
  say("录制 \(url.absoluteString) → \(out)")
  let s = try await f.connect(to: url)
  var lines: [String] = []
  var kl = 0, tk = 0
  let t0 = Date()
  while lines.count < count {
    switch try await s.receive() {
    case .ping: try await s.pong()
    case .closed(let w): say("连接关闭：\(w)"); throw FeedError.notConnected
    case .text(let t):
      guard t.contains("\"stream\"") else { continue }
      if t.contains("kline") { kl += 1 } else { tk += 1 }
      lines.append(t)
      if lines.count % 500 == 0 { say("已录 \(lines.count) 条") }
    }
  }
  await s.cancel()
  try lines.joined(separator: "\n").appending("\n").write(toFile: out, atomically: true, encoding: .utf8)
  say("录完 \(lines.count) 条（kline \(kl) / ticker \(tk)），用时 \(Int(-t0.timeIntervalSinceNow))s")
}

// ---------------------------------------------------------------- 入口

let a = CommandLine.arguments
guard a.count > 1 else {
  print("""
  用法：
    kanpan-feed <SYMBOL> <INTERVAL> [--minutes N]
    kanpan-feed info [SYMBOL]
    kanpan-feed history <SYMBOL> <INTERVAL> <PAGES>
    kanpan-feed snapshot <SYMBOL> <INTERVAL>
    kanpan-feed oi <SYMBOL> <INTERVAL> [--days N]
    kanpan-feed switch <SYMBOL>
    kanpan-feed churn [--symbols N]
  """)
  exit(1)
}

do {
  switch a[1] {
  case "info":
    try await cmdInfo()
  case "history":
    try await cmdHistory(key(arg(1)!.uppercased()), parseInterval(arg(2)), pages: Int(arg(3) ?? "10") ?? 10)
  case "snapshot":
    try await cmdSnapshot(key(arg(1)!.uppercased()), parseInterval(arg(2)))
  case "oi":
    try await cmdOI(key(arg(1)!.uppercased()), parseInterval(arg(2)), days: Int(flag("--days") ?? "45") ?? 45)
  case "record":
    try await cmdRecord(key(arg(1)!.uppercased()), Interval(rawValue: arg(2) ?? "1m") ?? .m1,
                        Int(flag("--count") ?? "3000") ?? 3000,
                        flag("--out") ?? "ws.jsonl")
  case "switch":
    try await cmdSwitch(key(arg(1)!.uppercased()))
  case "churn":
    try await cmdChurn(symbols: Int(flag("--symbols") ?? "30") ?? 30)
  default:
    try await cmdLive(key(a[1].uppercased()), parseInterval(arg(1)), minutes: Double(flag("--minutes") ?? "1") ?? 1)
  }
} catch {
  say("出错：\(error)")
  exit(2)
}
