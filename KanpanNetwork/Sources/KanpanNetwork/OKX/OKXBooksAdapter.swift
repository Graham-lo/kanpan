import Foundation
import KanpanCore

/// OKX 一条连接上的几本簿（现货 `BTC-USDT`、U 本位永续 `BTC-USDT-SWAP`、币本位永续 `BTC-USD-SWAP`、
/// 交割 `BTC-USD-260925`……），不分线路一律经 kanpan-api 的中继 `/v1/market/ws/okx`
/// （上游 public 端点，帧原样转发）——手机在国内直连不了 OKX。
///
/// 地址、保活来自 `OKXVenue`，控制帧的写法来自 `OKXWire`，解帧是 `OKXDTO.books`（OKX 唯一的报文解码）。
///
/// - 连上后自己发订阅：`{"op":"subscribe","args":[{"channel":"books","instId":…},{"channel":"trades",…}]}`。
///   中继一条订阅消息最多 12 个 args，所以一条消息最多 6 本；一条连接最多 `maxBooks` 本。
/// - OKX 30 秒没有帧就断，冷门交割可能半分钟没有变动，所以每 20 秒发一句 `ping`（中继只放行这一句），
///   回来的 `pong` 不是 JSON，解码直接忽略。
public struct OKXBooksAdapter: DepthFeedAdapter {
  /// `books` 频道每侧只维护盘口最近 400 档的滑动窗口（见 `OKXDTO.bookLevels`）。
  public static var snapshotLevels: Int { OKXDTO.bookLevels }
  /// 一条连接最多几本（一本 books + trades 两个订阅；中继每连接的订阅名额见 `relay.rs`）。
  public static let maxBooks = 12
  /// 一条订阅消息最多几本（中继 MAX_ARGS = 12，一本两个 args）。
  static let booksPerMessage = OKXVenue.maxArgsPerFrame / 2

  public let books: [DepthBook]
  /// kanpan-api 主机候选（`MarketRoute.apiHosts`，主在前）。
  let gateways: [String]
  let sockets: any WSSocketFactory
  private let byInstrument: [String: DepthBook]

  public init(books: [DepthBook], gateways: [String],
              sockets: any WSSocketFactory = URLSessionSocketFactory()) {
    self.books = Array(books.prefix(Self.maxBooks))
    self.gateways = gateways; self.sockets = sockets
    var map: [String: DepthBook] = [:]
    for book in self.books { map[book.venue.instrument] = book }
    byInstrument = map
  }

  public var name: String { "\(OKXVenue.displayName) \(books.map(\.venue.instrument).joined(separator: ","))" }

  public var streamURLs: [URL] { OKXVenue.relayStreams(hosts: gateways) }

  public var keepAlive: DepthKeepAlive? { DepthKeepAlive(text: OKXVenue.pingText, everyMs: OKXVenue.pingEveryMs) }

  /// 订阅消息（一条最多 `booksPerMessage` 本）。
  var subscribeMessages: [String] {
    stride(from: 0, to: books.count, by: Self.booksPerMessage).compactMap { start in
      let chunk = books[start..<min(start + Self.booksPerMessage, books.count)]
      let args = chunk.flatMap { book in
        [(channel: "books", instID: book.venue.instrument), (channel: "trades", instID: book.venue.instrument)]
      }
      return try? OKXWire.control(VenueControl.subscribe.rawValue, args)
    }
  }

  /// 单本重订（审查第 37 项）：这一本的序号接不上时，只退订再订它的 `books`，OKX 会给它重发一帧
  /// snapshot；同一条连接上的另外十来本不受影响。`trades` 不动（成交没有序号，不用重来）。
  /// 中继一条消息一个 arg、退订在前，订阅数不会超过它的上限。
  public func resubscribeMessages(venueID: String) -> [String]? {
    guard let book = books.first(where: { $0.id == venueID }) else { return nil }
    return [VenueControl.unsubscribe, .subscribe].compactMap { op in
      try? OKXWire.control(op.rawValue, [(channel: "books", instID: book.venue.instrument)])
    }
  }

  public func connect(candidate: Int) async throws -> any WSSocket {
    let socket = try await sockets.connect(to: try url(candidate))
    do {
      for message in subscribeMessages { try await socket.send(message) }
    } catch {
      await socket.cancel()
      throw error
    }
    return socket
  }

  public func decode(_ text: String) -> [VenueMessage] {
    OKXDTO.books(text, byInstrument: byInstrument)
  }
}
