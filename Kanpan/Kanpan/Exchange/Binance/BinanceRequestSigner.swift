import CryptoKit
import Foundation

/// 币安签名接口（`SIGNED`）的签名：对整条查询串做 HMAC-SHA256，Secret 当钥匙，结果写成小写十六进制，
/// 作为最后一个参数 `signature` 拼上去。Key 放在请求头 `X-MBX-APIKEY`，不进查询串。
///
/// Secret 只在这台手机的内存里参与运算，签出来的只是一串摘要；Secret 本身从不出站。
struct BinanceRequestSigner: Sendable {
  let secret: String

  func signature(for query: String) -> String {
    let key = SymmetricKey(data: Data(secret.utf8))
    let mac = HMAC<SHA256>.authenticationCode(for: Data(query.utf8), using: key)
    return mac.map { String(format: "%02x", $0) }.joined()
  }

  /// `参数…&recvWindow=…&timestamp=…&signature=…`。参数按传入顺序拼，签名覆盖的就是这一串。
  func signedQuery(_ items: [(String, String)], timestamp: Int64, recvWindow: Int) -> String {
    var all = items
    all.append(("recvWindow", String(recvWindow)))
    all.append(("timestamp", String(timestamp)))
    let query = all.map { "\($0.0)=\(Self.escape($0.1))" }.joined(separator: "&")
    return query + "&signature=" + signature(for: query)
  }

  /// 只放行 RFC 3986 的非保留字符（ASCII 字母、数字、`-._~`），其余一律按 UTF-8 百分号转义。
  ///
  /// 不能用 `CharacterSet.alphanumerics`：它把汉字等 Unicode 字母也算「字母数字」，
  /// 于是「币安人生USDT」这类代号原样进了查询串、按原文签名；而 `URL` 发出去时会把汉字转义成
  /// `%E5%B8%81…`，币安按收到的转义串验签，对不上就回 -1022（被当成 Key 失效）。
  /// 币安文档明说非 ASCII 参数要先百分号转义、再对转义后的串签名。
  static let unreserved = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

  static func escape(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
  }
}
