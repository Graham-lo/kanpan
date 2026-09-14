import Foundation

/// 自定义 API 域名（§4.1 / A6.10）。默认 `fapi.binance.com`，
/// 换镜像域时改这一个字段——`KanpanData.BinanceHosts.fapi` 直接吃它。
///
/// 只做**形状**上的校验：通不通得连上去才知道（A6.10 是拿一个不通的域名手验的，
/// 「离线」状态由数据层报，不在这里假装能预判）。
enum APIHost {
  static let `default` = "fapi.binance.com"

  /// 不合形状就说一句为什么。合法返回 nil。
  static func reject(_ raw: String) -> String? {
    let host = normalize(raw)
    if host.isEmpty { return "域名不能为空" }
    if host.contains("/") || host.contains(" ") { return "只填域名，不要带路径或空格" }
    if host.contains(":") { return "不要带端口" }
    if !host.contains(".") { return "看起来不像一个域名" }
    if host.hasPrefix(".") || host.hasSuffix(".") || host.contains("..") { return "看起来不像一个域名" }
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
    if host.unicodeScalars.contains(where: { !allowed.contains($0) }) { return "域名里有不能用的字符" }
    return nil
  }

  static func isValid(_ raw: String) -> Bool { reject(raw) == nil }

  /// 去掉前后空白、协议头和末尾斜杠，统一小写。
  /// 用户从浏览器地址栏抄一段过来也能用。
  static func normalize(_ raw: String) -> String {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    for scheme in ["https://", "http://", "wss://", "ws://"] where s.hasPrefix(scheme) {
      s.removeFirst(scheme.count)
      break
    }
    while s.hasSuffix("/") { s.removeLast() }
    return s
  }

  /// 存档里读出来的东西：修得好就用，修不好退回默认。
  static func sanitize(_ raw: String) -> String {
    let host = normalize(raw)
    return isValid(host) ? host : `default`
  }
}
