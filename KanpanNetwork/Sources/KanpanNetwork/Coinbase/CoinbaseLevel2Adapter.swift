import Foundation
import KanpanCore

/// Coinbase 现货的 `level2`：流内 snapshot + update，恒走直连（网关的 Coinbase hub 不收 level2）。
/// 一条连接只放一本簿：`sequence_num` 是整条连接的序号，放两本就分不清谁断了档。
///
/// 同一条连接订 `level2`、`market_trades`、`heartbeats`。地址与控制帧来自 `CoinbaseVenue` / `CoinbaseWire`，
/// 解帧是 `CoinbaseDTO.level2`（Coinbase 唯一的报文解码）。
public struct CoinbaseLevel2Adapter: DepthFeedAdapter {
  public static var streamURL: URL { CoinbaseVenue.streamURL }

  public let book: DepthBook
  public var books: [DepthBook] { [book] }
  /// Coinbase 的产品代号（`BTC-USD`）。
  var symbol: String { book.venue.instrument }
  let sockets: any WSSocketFactory

  public init(book: DepthBook, sockets: any WSSocketFactory = URLSessionSocketFactory()) {
    self.book = book
    self.sockets = sockets
  }

  public var name: String { "\(CoinbaseVenue.displayName) \(symbol)" }

  public var streamURLs: [URL] { [Self.streamURL] }

  public func connect(candidate: Int) async throws -> any WSSocket {
    let socket = try await sockets.connect(to: Self.streamURL)
    do {
      for (channel, products) in [("level2", [symbol]), ("market_trades", [symbol]), ("heartbeats", [])] {
        try await socket.send(try CoinbaseWire.control("subscribe", channel: channel, products: products))
      }
    } catch {
      await socket.cancel()
      throw error
    }
    return socket
  }

  public func decode(_ text: String) -> [VenueMessage] {
    CoinbaseDTO.level2(text, book: book).map { VenueMessage(book.id, $0) }
  }
}
