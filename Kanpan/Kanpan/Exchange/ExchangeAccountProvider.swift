import Foundation
import KanpanCore
import KanpanNetwork

// 交易所账户（只读 API）→ 自动复盘。
//
// 用户 2026-09-27 定的方向：只读交易所 API「不是显示在上面，而是做成自动复盘，直接帮用户处理」。
// 所以这一摊只干一件事：把账户里的成交、资金费拉回来，交给 `KanpanCore` 的 `RoundBuilder`
// 拼成回合，每个回合变成一条交易复盘。仓位、开仓价、成交点**不上主图**（`docs/不做清单.md`）。
//
// 为什么在手机上拉、不交给服务端：
// - Key 只存本机 Keychain（`deviceOnly`），从头到尾不离开手机，服务端不经手任何账户凭据；
// - 服务端（VPS）在美国，币安对美区 IP 的账户端点回 451，服务端既不能也不需要碰用户的账户接口。
// 所以账户请求一律走交易所的直连域名，**不走看盘网关**，和用户选的行情线路无关。
//
// 按交易所插拔：每一家实现一个 `ExchangeAccountProvider`，放在 `Exchange/<交易所>/` 里，
// 在 `ExchangeAccountRegistry` 登记。这一层（协议、同步、凭据）不点任何一家的名字
// （`Tools/check-venue-isolation.sh` 守着）。第一期只有币安 U 本位合约。
// 协议文档：`docs/交易复盘-协议-2026-09-27.md`。

/// 用户贴进来的一把只读 Key。
struct ExchangeCredentials: Codable, Sendable, Equatable {
  var apiKey: String
  var secret: String

  /// 界面上显示的尾号四位（接入之后只给看这个）。
  var keySuffix: String { String(apiKey.suffix(4)) }

  /// 去掉首尾空白与换行（从别处复制过来常带一个换行）。
  var trimmed: ExchangeCredentials {
    ExchangeCredentials(apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                        secret: secret.trimmingCharacters(in: .whitespacesAndNewlines))
  }
}

/// 一次拉取的结果：成交、资金费、以及拼回合要的上下文（当前杠杆、标记价、当前持仓）。
struct ExchangeAccountBatch: Sendable {
  var fills: [Fill] = []
  var funding: [FundingEntry] = []
  /// 品种 → 当前杠杆。
  var leverage: [String: Int] = [:]
  /// 合约代号 → 标记价（BNB 手续费折算用）。
  var markPrices: [String: Decimal] = [:]
  /// 当前持仓（有符号），第一次回溯时推窗口起点有没有旧仓用。
  var positions: [PositionKey: Decimal] = [:]
  /// 这一批的截止时刻（交易所时间，毫秒）：持仓快照对应的时点，成交与资金费都只拉到这里。
  /// 同步层把它记成水位；交易所给不出时为 nil，退回手机时间。
  var asOf: Int64? = nil
}

/// 一家交易所的只读账户接口。
///
/// 实现方只许用只读端点：查 Key 权限、查资金流水、查成交、查持仓。下单、撤单、划转、提现一概不许出现
/// ——`ExchangeEndpointScanTests` 扫源码守着，不是靠自觉。
protocol ExchangeAccountProvider: Sendable {
  /// `InstrumentID.venue` / `.market`（与多交易所模块对齐）。
  var venue: String { get }
  var market: String { get }

  /// 接入前的只读校验：Key 有任何交易、提现权限就抛 `ExchangeAccountError.notReadOnly`。
  func verifyReadOnly() async throws

  /// 拉 `from` 之后的成交与资金费，外加当前持仓、杠杆、标记价（毫秒，含两端）。
  ///
  /// `to` 是手机时间，只当提示：实现方应当先拿持仓快照，成交与资金费只拉到快照时刻、并把它填进
  /// `asOf`——否则拉成交期间又成交的一笔会只出现在持仓里，凭空多出一份「旧仓」。
  func fetch(from: Int64, to: Int64) async throws -> ExchangeAccountBatch
}

/// 账户请求的传输层：要带请求头（Key），所以不能复用行情那条只会 GET URL 的 `HTTPTransport`。
protocol ExchangeHTTP: Sendable {
  func send(_ request: URLRequest) async throws -> HTTPReply
}

struct URLSessionExchangeHTTP: ExchangeHTTP {
  var session: URLSession = .shared

  func send(_ request: URLRequest) async throws -> HTTPReply {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw ExchangeAccountError.invalidResponse }
    var headers: [String: String] = [:]
    for (k, v) in http.allHeaderFields {
      if let k = k as? String, let v = v as? String { headers[k.lowercased()] = v }
    }
    return HTTPReply(status: http.statusCode, headers: headers, body: data)
  }
}
