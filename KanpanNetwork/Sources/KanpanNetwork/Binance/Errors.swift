import Foundation

/// 币安的错误。REST 出错时回的是 `{"code":-1120,"msg":"Invalid interval."}`。
public struct BinanceError: Error, Sendable, Equatable, CustomStringConvertible {
  public var status: Int
  public var code: Int?
  public var msg: String?
  public var url: String?

  public init(status: Int, code: Int? = nil, msg: String? = nil, url: String? = nil) {
    self.status = status; self.code = code; self.msg = msg; self.url = url
  }

  public var description: String {
    var s = "HTTP \(status)"
    if let code { s += " code=\(code)" }
    if let msg { s += " \(msg)" }
    if let url { s += " \(url)" }
    return s
  }

  /// 归档站对「这天没有数据」的回答就是 404，不是错误，调用方要能分辨。
  public var isNotFound: Bool { status == 404 }
  /// 418 是被 ban，429 是超频。两者都读 `Retry-After`（§4.1）。
  public var isRateLimited: Bool { status == 429 || status == 418 }
  /// 地区封锁。VPS 上会遇到，手机直连不会。
  public var isGeoBlocked: Bool { status == 451 }
}

public enum FeedError: Error, Sendable, Equatable {
  case badResponse(String)
  case cancelled
  case notConnected
}
