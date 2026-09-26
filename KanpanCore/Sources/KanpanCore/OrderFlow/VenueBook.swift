import Foundation

// 主力订单流 · 一本簿的接续。
//
// 每本簿各守各的序列规则、各拉各的快照：连上就换一个连接代号，快照不在流里的那家（币安）
// 先缓冲增量、等 REST 快照对上序号；快照在流里的（OKX 与美国那家现货）收到首帧就绪。
// 接不上就回一个 `Action` 让 KanpanData 去重拉快照或重订。

/// 一本簿：连接代号、缓冲增量、快照对序号、就绪时刻。
public struct VenueBook: Sendable {
  public let venue: OrderFlowVenue
  public private(set) var book: LocalBook
  public private(set) var readySinceMs: Int64?
  private var buffered: [BookDelta] = []
  private var pendingSnapshot: BookSnapshot?
  private var connection = 0

  public init(venue: OrderFlowVenue) {
    self.venue = venue
    self.book = LocalBook(sequenceModel: venue.sequenceModel)
    book.retainBps = Self.retainBps
  }

  /// 本地簿只留中间价两侧扫描半径两倍以内的价位（审查第 36 项）。
  public static let retainBps = 2 * OrderFlowDefaults.scanRadiusBps

  var snapshotInBand: Bool { venue.snapshotInBand }
  public var isReady: Bool { book.quality == .ready }

  /// 这一档本地知不知道（快照截断时覆盖范围以外、又没推过的档不知道）。簿没就绪一律不知道。
  func knows(_ side: BookSide, price: Double) -> Bool {
    book.quality == .ready && readySinceMs != nil && book.knows(side, price: price)
  }

  /// 新连接建立：簿换一个连接代号重来。旧连接的迟到包因代号不符进不来。
  mutating func connectionOpened() -> OrderFlowModel.Action {
    connection += 1
    book.beginResync(connection: connection)
    buffered.removeAll()
    pendingSnapshot = nil
    readySinceMs = nil
    return snapshotInBand ? .none : .fetchSnapshot
  }

  /// 成交不归簿管，由 OrderFlowModel 在进来之前截走。
  mutating func ingest(_ message: DepthMessage, nowMs: Int64) -> OrderFlowModel.Action {
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
      if buffered.count > OrderFlowModel.bufferCapacity {
        buffered.removeFirst(buffered.count - OrderFlowModel.bufferCapacity)
      }
      return tryBootstrap(nowMs: nowMs)
    case .trade:
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
  ///
  /// 簿已经就绪（这条连接上一份快照接上了、之后一直按增量走）时迟到的快照一律不理：它只会比簿旧，
  /// 拿它去 bootstrap 会把就绪的簿整本盖回旧快照、打回「拉快照中」，接着第一条增量对不上又要再拉一份。
  mutating func applySnapshot(_ snapshot: BookSnapshot, nowMs: Int64) -> OrderFlowModel.Action {
    guard !isReady else { return .none }
    var snapshot = snapshot
    snapshot.connection = connection
    pendingSnapshot = snapshot
    return tryBootstrap(nowMs: nowMs)
  }

  private mutating func tryBootstrap(nowMs: Int64) -> OrderFlowModel.Action {
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

  /// 这一拍按桶合计的美元名义：中间价两侧 `radiusBps` 以内的全部价位，一侧一桶一条，
  /// 顺带记下每桶里名义最大的那一档的价（大单画在这个价上）。簿没就绪返回 nil。
  mutating func buckets(scheme: BucketScheme, radiusBps: Double) -> [BucketKey: BucketValue]? {
    guard book.quality == .ready, readySinceMs != nil else { return nil }
    let notional = venue.notional
    var out: [BucketKey: BucketValue] = [:]
    let mid = book.forEachLevel(withinBps: radiusBps) { side, price, quantity in
      let usd = notional.usd(price: price, quantity: quantity)
      guard usd > 0 else { return }
      let key = BucketKey(side: side, index: scheme.index(of: price))
      var value = out[key] ?? BucketValue()
      value.notional += usd
      if usd > value.topLevel { value.topLevel = usd; value.price = price }
      out[key] = value
    }
    return mid == nil ? nil : out
  }

  /// 中间价两侧 `bps` 以内、买卖两侧全部价位的美元名义之和；簿没就绪返回 nil。标定非币默认门槛用。
  mutating func depthUSD(withinBps bps: Double) -> Double? {
    guard book.quality == .ready, readySinceMs != nil else { return nil }
    let notional = venue.notional
    var total = 0.0
    let mid = book.forEachLevel(withinBps: bps) { _, price, quantity in
      let usd = notional.usd(price: price, quantity: quantity)
      if usd > 0 { total += usd }
    }
    return mid == nil ? nil : total
  }
}

/// 桶键：一侧一桶。
struct BucketKey: Hashable, Sendable {
  var side: BookSide
  var index: Int64
}

struct BucketValue: Sendable {
  var notional = 0.0
  /// 桶里名义最大的一档的名义与价。
  var topLevel = 0.0
  var price = 0.0
}
