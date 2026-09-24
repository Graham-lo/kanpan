import Foundation
import KanpanCore
import os

/// 提醒响了往用户填的地址 POST 一份 JSON。
///
/// 身体怎么拼在 KanpanCore（`AlertWebhookPayload` / `AlertMessage`，纯函数、有单测），
/// 这儿只管发：`Content-Type: application/json`、`User-Agent: Hkline-Alerts/1`、
/// 8 秒超时；失败（连不上、超时、非 2xx）隔 3 秒再试一次，还不行就只记一条日志放弃——
/// 不弹窗、不重排队，提醒本身（震动、浮条、通知）已经照常到了用户眼前。
///
/// 谁发：app 在前台、本机 `AlertEngine` 判响的那一次由这里发；app 不在前台时是服务端
/// `alerts.rs` 判响、由服务端发。同步换下来的那种「服务端已经响过」不在这里再发一遍
/// （`AlertStore.firedLocally` 那一关），免得一件事发两次。
enum AlertWebhook {
  static let timeout: TimeInterval = 8
  static let retryDelay: Duration = .seconds(3)
  static let userAgent = "Hkline-Alerts/1"

  private static let log = Logger(subsystem: "com.kanpan.app", category: "alert-webhook")

  /// 一次发送的结果：HTTP 状态码，或者一句失败原因（中文，给「发一条测试」的浮条用）。
  enum Outcome: Sendable, Equatable {
    case status(Int)
    case failed(String)

    var ok: Bool { if case .status(let code) = self { return (200..<300).contains(code) }; return false }

    /// 「已发出」/「发送失败 · 超时」（「发一条测试」的结果走全局提示条，成功不报状态码）。
    var toast: String {
      switch self {
      case .status(let code) where (200..<300).contains(code): "已发出"
      case .status(let code): "发送失败 · \(code)"
      case .failed(let reason): "发送失败 · \(reason)"
      }
    }
  }

  /// 提醒响了：后台发，失败隔 3 秒重试一次，再失败只记日志。
  static func fire(_ alert: Alert, price: Double, decimals: Int?, at ms: Double) {
    guard let url = alert.webhook, Alert.isValidWebhook(url) else { return }
    let payload = AlertWebhookPayload(event: .alert, alert: alert, price: price, decimals: decimals, at: ms)
    Task.detached(priority: .utility) {
      let first = await post(payload, to: url)
      if first.ok { return }
      try? await Task.sleep(for: retryDelay)
      let second = await post(payload, to: url)
      if !second.ok {
        log.error("webhook \(alert.id, privacy: .public) 放弃：\(second.toast, privacy: .public)")
      }
    }
  }

  /// 「发一条测试」：同一份身体，`event` 为 `test`、价格用现价。只发一次，结果交回去说一句。
  static func test(_ alert: Alert, url: String, price: Double, decimals: Int?,
                   now: Double = Date().timeIntervalSince1970 * 1000) async -> Outcome {
    guard Alert.isValidWebhook(url) else { return .failed("地址不对") }
    var draft = alert
    draft.webhook = url
    let payload = AlertWebhookPayload(event: .test, alert: draft, price: price, decimals: decimals, at: now)
    return await post(payload, to: url.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  /// 发一次。
  static func post(_ payload: AlertWebhookPayload, to address: String) async -> Outcome {
    guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else {
      return .failed("地址不对")
    }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    do {
      request.httpBody = try payload.json()
      let (_, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse else { return .failed("没有回应") }
      return .status(http.statusCode)
    } catch let error as URLError {
      return .failed(reason(error))
    } catch {
      return .failed("发不出去")
    }
  }

  /// 不走共享会话：不带 cookie、不写缓存，超时各管各的。
  private static let session: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = timeout
    config.timeoutIntervalForResource = timeout
    config.waitsForConnectivity = false
    return URLSession(configuration: config)
  }()

  private static func reason(_ error: URLError) -> String {
    switch error.code {
    case .timedOut: "超时"
    case .notConnectedToInternet, .networkConnectionLost: "没有网络"
    case .cannotFindHost, .dnsLookupFailed: "找不到地址"
    case .cannotConnectToHost: "连不上"
    case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
         .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot: "证书不对"
    case .appTransportSecurityRequiresSecureConnection: "系统不允许明文 http"
    default: "连不上"
    }
  }
}
