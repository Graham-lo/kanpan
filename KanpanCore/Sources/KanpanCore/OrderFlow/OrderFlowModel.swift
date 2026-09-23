import Foundation

// 主力订单流 · 模型。
//
// 一只品种一份：本地簿（LocalBook）+ 分桶（BucketScheme）+ 下限标定（FloorCalibration）
// + 门槛（BigOrderFilter）。交易所帧由 KanpanNetwork 的适配器解成 `DepthMessage` 喂进来，
// 连接、快照拉取、节流与落盘由 KanpanData 的 OrderFlowFeed 管。图表与 app 只看得到
// `OrderFlowSnapshot`（当前大单集合）这一种值。
//
// 快照覆盖：币安永续一次最多给 1000 档，BTC 这只大约只覆盖中间价两侧 16 bps；增量流会把之后
// 变过的价位补进簿里。重建后头 60 秒只评估快照覆盖以内的桶，之后按整本已知的簿评估。

/// 一条正在图上的大单（一个过门槛的桶）。
public struct BigOrder: Sendable, Equatable, Identifiable {
  public var side: BookSide
  public var bucketIndex: Int64
  /// 桶下沿价；桶覆盖 [low, low + width)。
  public var low: Double
  public var width: Double
  /// 此刻桶内挂单名义（计价货币）。
  public var notional: Double
  /// 首次过门槛时的名义。
  public var initialNotional: Double
  /// 首次过门槛以来被主动成交吃掉的名义。
  public var filledNotional: Double
  public var firstSeenMs: Int64

  public init(side: BookSide, bucketIndex: Int64, low: Double, width: Double, notional: Double,
              initialNotional: Double, filledNotional: Double, firstSeenMs: Int64) {
    self.side = side; self.bucketIndex = bucketIndex; self.low = low; self.width = width
    self.notional = notional; self.initialNotional = initialNotional
    self.filledNotional = filledNotional; self.firstSeenMs = firstSeenMs
  }

  public var id: String { "\(side.rawValue)\(bucketIndex)" }
  public var center: Double { low + width / 2 }
  /// 成交 / 初始；没有成交数据的线路恒为 0。
  public var fillRatio: Double { initialNotional > 0 ? filledNotional / initialNotional : 0 }
}

/// 当前大单集合——主力订单流对外唯一的值。永远不同步、不落盘。
public struct OrderFlowSnapshot: Sendable, Equatable {
  public enum Phase: Sendable, Equatable { case loading, ready }
  public var symbol: String
  public var phase: Phase
  /// 买在前（名义降序），卖在后（名义降序）。
  public var orders: [BigOrder]
  public var asOfMs: Int64

  public init(symbol: String, phase: Phase, orders: [BigOrder], asOfMs: Int64) {
    self.symbol = symbol; self.phase = phase; self.orders = orders; self.asOfMs = asOfMs
  }

  public static func loading(_ symbol: String, asOfMs: Int64 = 0) -> OrderFlowSnapshot {
    OrderFlowSnapshot(symbol: symbol, phase: .loading, orders: [], asOfMs: asOfMs)
  }

  /// 除时间戳外内容相同（用来判断要不要再发一帧）。
  public func sameContent(as other: OrderFlowSnapshot) -> Bool {
    symbol == other.symbol && phase == other.phase && orders == other.orders
  }
}

/// 一笔主动成交：`hitSide` 是被吃掉的那一侧（主动卖吃买单 = .bid）。
public struct OrderFlowTrade: Sendable, Equatable {
  public var price: Double
  public var quantity: Double
  public var hitSide: BookSide
  public var timeMs: Int64
  public init(price: Double, quantity: Double, hitSide: BookSide, timeMs: Int64) {
    self.price = price; self.quantity = quantity; self.hitSide = hitSide; self.timeMs = timeMs
  }
}

/// 适配器解出来的一条消息。三家交易所都落到这四种上。
public enum DepthMessage: Sendable, Equatable {
  /// 流内权威快照（快照随流下发的那几家）：整本替换，立即就绪。
  case snapshot(BookSnapshot)
  /// 增量；序号按整条连接计的那家，心跳、订阅回执、成交帧也各带一条空增量，用来推进连接级序号。
  case delta(BookDelta)
  case trade(OrderFlowTrade)
  /// 协议层面接不上了（例如 OKX 序号重置），需要重建。
  case reset
}

public struct OrderFlowModel: Sendable {
  public enum Action: Sendable, Equatable {
    case none
    /// 需要一份 REST 快照（币安）。
    case fetchSnapshot
    /// 需要重新订阅以拿到新的流内快照（快照在流里的那几家）。
    case resubscribe
  }

  public static let warmUpMs: Int64 = 60_000
  public static let sampleIntervalMs: Int64 = 1_000
  public static let bufferCapacity = 5_000

  public let symbol: String
  public let snapshotInBand: Bool
  public private(set) var book: LocalBook
  public private(set) var scheme: BucketScheme?
  public private(set) var calibration: FloorCalibration
  /// 标定有新样本还没落盘。
  public private(set) var calibrationDirty = false

  private var filter = BigOrderFilter()
  private var buffered: [BookDelta] = []
  private var pendingSnapshot: BookSnapshot?
  private var readySinceMs: Int64?
  private var lastSampleMs: Int64 = .min / 2
  private var connection = 0

  public init(symbol: String, sequenceModel: DepthSequenceModel, snapshotInBand: Bool,
              scheme: BucketScheme?, calibration: FloorCalibration = FloorCalibration()) {
    self.symbol = symbol
    self.snapshotInBand = snapshotInBand
    self.book = LocalBook(sequenceModel: sequenceModel)
    self.scheme = scheme
    self.calibration = calibration
  }

  public var isReady: Bool { book.quality == .ready }

  /// 桶宽变了（跨 UTC 日重算）桶号就全变了，跟踪表一并清掉。
  public mutating func setScheme(_ next: BucketScheme?) {
    if next?.widthTicks != scheme?.widthTicks || next?.tick != scheme?.tick { filter.reset() }
    scheme = next
  }

  public mutating func markCalibrationSaved() { calibrationDirty = false }

  /// 新连接建立：簿换一个连接代号重来。旧连接的迟到包因代号不符进不来。
  public mutating func connectionOpened() -> Action {
    connection += 1
    book.beginResync(connection: connection)
    buffered.removeAll()
    pendingSnapshot = nil
    readySinceMs = nil
    return snapshotInBand ? .none : .fetchSnapshot
  }

  public mutating func ingest(_ message: DepthMessage, nowMs: Int64) -> Action {
    switch message {
    case .snapshot(var snapshot):
      snapshot.connection = connection
      do {
        try book.replaceFromStreamSnapshot(snapshot)
        readySinceMs = nowMs
        return .none
      } catch {
        readySinceMs = nil
        return snapshotInBand ? .resubscribe : .fetchSnapshot
      }
    case .delta(var delta):
      delta.connection = connection
      if book.quality == .ready {
        do {
          try book.apply(delta)
          return .none
        } catch {
          readySinceMs = nil
          if snapshotInBand { return .resubscribe }
          buffered = [delta]
          pendingSnapshot = nil
          return .fetchSnapshot
        }
      }
      if snapshotInBand { return .none }
      buffered.append(delta)
      if buffered.count > Self.bufferCapacity { buffered.removeFirst(buffered.count - Self.bufferCapacity) }
      return tryBootstrap(nowMs: nowMs)
    case .trade(let trade):
      if let scheme { filter.recordTrade(trade, scheme: scheme) }
      return .none
    case .reset:
      book.markGapped(.missingLocalSequence)
      readySinceMs = nil
      buffered.removeAll()
      pendingSnapshot = nil
      return snapshotInBand ? .resubscribe : .fetchSnapshot
    }
  }

  /// REST 快照到了：和已缓冲的增量对序号。
  public mutating func applySnapshot(_ snapshot: BookSnapshot, nowMs: Int64) -> Action {
    var snapshot = snapshot
    snapshot.connection = connection
    pendingSnapshot = snapshot
    return tryBootstrap(nowMs: nowMs)
  }

  private mutating func tryBootstrap(nowMs: Int64) -> Action {
    guard let snapshot = pendingSnapshot else { return .none }
    do {
      switch try book.bootstrap(snapshot, buffered: buffered) {
      case .ready:
        buffered.removeAll()
        pendingSnapshot = nil
        readySinceMs = nowMs
        return .none
      case .waitingForOverlap:
        return .none
      }
    } catch {
      pendingSnapshot = nil
      readySinceMs = nil
      buffered.removeAll { $0.finalUpdateID <= snapshot.lastUpdateID }
      return .fetchSnapshot
    }
  }

  /// 按此刻的簿算一帧大单集合；顺带每秒记一次标定样本。
  public mutating func evaluate(nowMs: Int64) -> OrderFlowSnapshot {
    guard book.quality == .ready, let scheme, let readySince = readySinceMs,
          let view = try? book.viewWithinDistance(BigOrderFilter.scanRadiusBps) else {
      return .loading(symbol, asOfMs: nowMs)
    }
    let warm = nowMs - readySince >= Self.warmUpMs || book.coverage.state != .snapshotLimited
    let buckets = Self.aggregate(bids: view.bids, asks: view.asks, scheme: scheme,
                                 coverage: warm ? nil : book.coverage)
    let bidNotionals = buckets.filter { $0.side == .bid }.map(\.notional)
    let askNotionals = buckets.filter { $0.side == .ask }.map(\.notional)
    let bidFrame = FloorCalibration.frameFloor(bidNotionals)
    let askFrame = FloorCalibration.frameFloor(askNotionals)
    if warm, nowMs - lastSampleMs >= Self.sampleIntervalMs {
      lastSampleMs = nowMs
      if let bidFrame { calibration.record(bidFrame, side: .bid, atMs: nowMs); calibrationDirty = true }
      if let askFrame { calibration.record(askFrame, side: .ask, atMs: nowMs); calibrationDirty = true }
    }
    let orders = filter.update(buckets: buckets, reference: view.mid,
                               bidFloor: calibration.floor(.bid, nowMs: nowMs) ?? bidFrame,
                               askFloor: calibration.floor(.ask, nowMs: nowMs) ?? askFrame,
                               nowMs: nowMs)
    return OrderFlowSnapshot(symbol: symbol, phase: .ready, orders: orders, asOfMs: nowMs)
  }

  /// 价位按桶聚合成名义。给了 coverage 时，越出快照覆盖的桶（有一部分价位未知）不算。
  static func aggregate(bids: [BookLevel], asks: [BookLevel], scheme: BucketScheme,
                        coverage: BookCoverage?) -> [BucketNotional] {
    var bid: [Int64: Double] = [:], ask: [Int64: Double] = [:]
    for level in bids { bid[scheme.index(of: level.price), default: 0] += level.price * level.quantity }
    for level in asks { ask[scheme.index(of: level.price), default: 0] += level.price * level.quantity }
    let width = scheme.width
    var out: [BucketNotional] = []
    out.reserveCapacity(bid.count + ask.count)
    for (index, notional) in bid {
      let low = scheme.low(of: index)
      if let floor = coverage?.bidFloor, low < floor { continue }
      out.append(BucketNotional(side: .bid, index: index, low: low, width: width, notional: notional))
    }
    for (index, notional) in ask {
      let low = scheme.low(of: index)
      if let ceiling = coverage?.askCeiling, low + width > ceiling { continue }
      out.append(BucketNotional(side: .ask, index: index, low: low, width: width, notional: notional))
    }
    return out.sorted { $0.side == $1.side ? $0.index < $1.index : $0.side == .bid }
  }
}
