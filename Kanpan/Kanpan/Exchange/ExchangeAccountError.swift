import Foundation

/// 交易所账户（只读 API）这一摊的错误。
///
/// 每一种都带一句固定的中文文案，界面只念这一句，**不念系统或交易所的原文**：
/// 交易所回的 `msg` 是英文、还可能带着签名串或 Key 的片段，系统错误的原文是给工程师看的。
/// 写法照 `AccountFeature.message(_:)`。
enum ExchangeAccountError: Error, Equatable, Sendable {
  /// 这把 Key 开着提现、现货杠杆交易或合约交易权限。只收只读 Key，不落 Keychain。
  case notReadOnly
  /// Key 或 Secret 不对、已被删、或 IP 白名单不含这台手机。
  case invalidKey
  /// 两个输入框有空的。
  case missingCredentials
  /// 还没接入（Keychain 里没有 Key）。
  case notConnected
  /// 手机时间和交易所差太多，校正一次之后仍然被拒。
  case clockSkew
  /// 交易所限流（429）或封了 IP（418）。
  case rateLimited
  /// 交易所按地域拒绝（451）或被防火墙拦（403）。手机当前网络的出口不在交易所允许的地区。
  case regionBlocked
  /// 断网、超时。
  case offline
  /// 交易所回来的东西解不开。
  case invalidResponse
  /// 读写 Keychain 失败（包括设备重启后还没解锁、这一刻读不动）。
  case keychain
  /// 其它 HTTP 错误。
  case server(status: Int)

  /// 界面上那一句。
  var message: String {
    switch self {
    case .notReadOnly: "只收只读 Key：请关掉这把 Key 的交易与提现权限后再接入"
    case .invalidKey: "Key 或 Secret 不对，请检查后重试"
    case .missingCredentials: "请填写 API Key 与 Secret"
    case .notConnected: "还没有接入交易所账户"
    case .clockSkew: "手机时间与交易所相差太多，请打开「自动设置时间」后重试"
    case .rateLimited: "交易所暂时限制了请求，请稍后再同步"
    case .regionBlocked: "当前网络连不上交易所账户接口，请换一条网络后重试"
    case .offline: "网络不可用，请检查网络后重试"
    case .invalidResponse: "交易所返回的数据无法识别，请稍后重试"
    case .keychain: "暂时读不到本机保存的 Key，请解锁手机后重试"
    case .server: Self.genericFailure
    }
  }

  static let genericFailure = "暂未成功，请稍后重试"

  /// 任意错误 → 界面上那一句；取消返回 nil（不提示）。
  static func message(_ error: any Error) -> String? {
    switch error {
    case let value as ExchangeAccountError: return value.message
    case is CancellationError: return nil
    case let value as URLError:
      if value.code == .cancelled { return nil }
      return ExchangeAccountError.classify(value).message
    case is DecodingError: return ExchangeAccountError.invalidResponse.message
    default: return genericFailure
    }
  }

  /// 网络层错误归类。断网、超时这类都是「静默」的——后台同步遇到它们什么都不说、也不重试。
  static func classify(_ error: URLError) -> ExchangeAccountError {
    switch error.code {
    case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
         .callIsActive, .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
         .secureConnectionFailed:
      .offline
    default:
      .server(status: 0)
    }
  }

  /// 同步时遇到这一种要不要出声：断网就安静地等下一次。
  var isSilent: Bool { self == .offline }
}
