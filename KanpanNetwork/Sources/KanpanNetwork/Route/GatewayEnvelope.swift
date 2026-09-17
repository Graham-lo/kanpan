import Foundation

/// 网关信封的一趟式扫描。
///
/// 网关回的是 `{"source":"binance","symbol":"BTCUSDT","interval":"1m","bars":[…]}`
/// 这种形状：几个 ASCII 标量字段 + 一份大载荷。原来取载荷要走三趟：
///
/// 1. `JSONSerialization.jsonObject` 把整份报文建成 Foundation 对象图
///    （1500 根 K 线约 250KB，建出来是 1500 个 `NSArray` 套 12 个 `NSNumber`/`NSString`）；
/// 2. 取出 `bars` 再 `JSONSerialization.data` **重新序列化回字节**；
/// 3. 上层 `JSONDecoder` 第三次把这些字节解成 `[KlineRow]`。
///
/// 中间那两趟纯属搬运——建了一遍对象图只为了马上扔掉。这儿改成只扫一趟字节：
/// 标量字段直接读出来，载荷记下字节区间原样切片，交给上层解一次。
/// 不建对象图、不重新序列化。
enum GatewayEnvelope {

  struct Parsed: Sendable {
    var source: String?
    var symbol: String?
    var interval: String?
    /// 载荷在原报文里的那一段字节，原样切下来的。
    var payload: Data?
  }

  /// 扫顶层对象。形状不对、或者碰上转义字符这类少见情况就返回 nil，
  /// 调用方退回老的 `JSONSerialization` 路径——宁可慢一次，不要解错。
  static func parse(_ data: Data, field: String) -> Parsed? {
    let wanted: Set<String> = ["source", "symbol", "interval", field]
    return data.withUnsafeBytes { raw -> Parsed? in
      var i = 0
      skipSpace(raw, &i)
      guard i < raw.count, raw[i] == Byte.braceOpen else { return nil }
      i += 1
      var out = Parsed()
      while true {
        skipSpace(raw, &i)
        guard i < raw.count else { return nil }
        if raw[i] == Byte.braceClose { return out }
        if raw[i] == Byte.comma { i += 1; continue }
        guard let key = readString(raw, &i) else { return nil }
        skipSpace(raw, &i)
        guard i < raw.count, raw[i] == Byte.colon else { return nil }
        i += 1
        guard let span = skipValue(raw, &i) else { return nil }
        guard wanted.contains(key) else { continue }
        if key == field {
          out.payload = Data(raw[span])
          continue
        }
        // 标量三件套只认字符串，其它形状当没读到（后面的校验自然会拦下）。
        guard raw[span.lowerBound] == Byte.quote else { continue }
        var k = span.lowerBound
        let value = readString(raw, &k)
        switch key {
        case "source": out.source = value
        case "symbol": out.symbol = value
        case "interval": out.interval = value
        default: break
        }
      }
    }
  }

  // ---------------------------------------------------------------- 扫描原语

  private enum Byte {
    static let quote: UInt8 = 0x22        // "
    static let comma: UInt8 = 0x2C        // ,
    static let colon: UInt8 = 0x3A        // :
    static let backslash: UInt8 = 0x5C    // \
    static let braceOpen: UInt8 = 0x7B    // {
    static let braceClose: UInt8 = 0x7D   // }
    static let bracketOpen: UInt8 = 0x5B  // [
    static let bracketClose: UInt8 = 0x5D // ]
  }

  private static func isSpace(_ c: UInt8) -> Bool {
    c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D
  }

  private static func skipSpace(_ b: UnsafeRawBufferPointer, _ i: inout Int) {
    while i < b.count, isSpace(b[i]) { i += 1 }
  }

  /// 读一个字符串字面量（`i` 停在开引号上），读完 `i` 停在闭引号之后。
  /// 带转义的直接放弃——信封里这几个字段都是交易所代号，纯 ASCII。
  private static func readString(_ b: UnsafeRawBufferPointer, _ i: inout Int) -> String? {
    guard i < b.count, b[i] == Byte.quote else { return nil }
    var j = i + 1
    var bytes: [UInt8] = []
    while j < b.count {
      let c = b[j]
      if c == Byte.backslash { return nil }
      if c == Byte.quote { i = j + 1; return String(decoding: bytes, as: UTF8.self) }
      bytes.append(c)
      j += 1
    }
    return nil
  }

  /// 跳过一个完整的值，返回它占的字节区间。
  private static func skipValue(_ b: UnsafeRawBufferPointer, _ i: inout Int) -> Range<Int>? {
    skipSpace(b, &i)
    guard i < b.count else { return nil }
    let start = i
    switch b[start] {
    case Byte.quote:
      var j = start + 1
      while j < b.count {
        if b[j] == Byte.backslash { j += 2; continue }
        if b[j] == Byte.quote { i = j + 1; return start..<(j + 1) }
        j += 1
      }
      return nil
    case Byte.braceOpen, Byte.bracketOpen:
      // 只数同类括号。合法 JSON 里两种括号不会交叉，所以这样就够，
      // 也省掉一个栈。字符串里的括号靠 `inString` 躲开。
      let open = b[start]
      let close = open == Byte.braceOpen ? Byte.braceClose : Byte.bracketClose
      var depth = 0
      var j = start
      var inString = false
      while j < b.count {
        let c = b[j]
        if inString {
          if c == Byte.backslash { j += 2; continue }
          if c == Byte.quote { inString = false }
          j += 1
          continue
        }
        if c == Byte.quote { inString = true; j += 1; continue }
        if c == open { depth += 1 }
        else if c == close {
          depth -= 1
          if depth == 0 { i = j + 1; return start..<(j + 1) }
        }
        j += 1
      }
      return nil
    default:
      // 数字 / true / false / null：读到分隔符为止。
      var j = start
      while j < b.count, b[j] != Byte.comma, b[j] != Byte.braceClose,
            b[j] != Byte.bracketClose, !isSpace(b[j]) { j += 1 }
      guard j > start else { return nil }
      i = j
      return start..<j
    }
  }
}
