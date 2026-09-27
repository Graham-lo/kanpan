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

  /// 查询串里的值只会是代号、数字、类型名；照 RFC 3986 的非保留字符之外一律转义，签的和发的是同一串。
  static func escape(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
  }
}
