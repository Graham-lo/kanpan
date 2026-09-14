import Foundation
import Compression

/// 极简 ZIP 读取（§4.5 第 5 条）。
///
/// 归档站的 metrics zip 里只有一个 deflate 条目，所以只要「本地文件头 + inflate」
/// 这一条路；不引第三方库，解压用系统 `Compression` 的 `COMPRESSION_ZLIB`
/// （Apple 这个常量是**裸 deflate**，正好是 zip 里存的东西）。
public enum Zip {
  public struct Entry: Sendable, Equatable {
    public var name: String
    public var method: UInt16          // 0 = 原样存，8 = deflate
    public var compressedSize: Int
    public var uncompressedSize: Int
    public var dataOffset: Int
  }

  public enum Failure: Error, Equatable, CustomStringConvertible {
    case notZip
    case unsupportedMethod(UInt16)
    case truncated
    case inflateFailed

    public var description: String {
      switch self {
      case .notZip: "不是 zip"
      case .unsupportedMethod(let m): "不支持的压缩方式 \(m)"
      case .truncated: "文件被截断"
      case .inflateFailed: "解压失败"
      }
    }
  }

  static let localHeader: UInt32 = 0x0403_4B50
  static let centralHeader: UInt32 = 0x0201_4B50
  static let eocd: UInt32 = 0x0605_4B50

  /// 第一个条目。优先读本地文件头；头里大小是 0（带数据描述符的写法）时回中央目录取。
  public static func firstEntry(_ data: Data) throws -> Entry {
    let b = [UInt8](data)
    guard b.count > 30, u32(b, 0) == localHeader else { throw Failure.notZip }
    let method = u16(b, 8)
    let flags = u16(b, 6)
    var csize = Int(u32(b, 18))
    var usize = Int(u32(b, 22))
    let nameLen = Int(u16(b, 26))
    let extraLen = Int(u16(b, 28))
    guard 30 + nameLen + extraLen <= b.count else { throw Failure.truncated }
    let name = String(decoding: b[30..<30 + nameLen], as: UTF8.self)
    if flags & 0x08 != 0 || csize == 0 || usize == 0 {
      if let c = try? centralSizes(b) { csize = c.compressed; usize = c.uncompressed }
    }
    let off = 30 + nameLen + extraLen
    guard off + csize <= b.count else { throw Failure.truncated }
    return Entry(name: name, method: method, compressedSize: csize, uncompressedSize: usize, dataOffset: off)
  }

  /// 从中央目录拿大小。只看第一条。
  static func centralSizes(_ b: [UInt8]) throws -> (compressed: Int, uncompressed: Int) {
    var i = b.count - 22
    while i >= 0, u32(b, i) != eocd { i -= 1 }
    guard i >= 0 else { throw Failure.notZip }
    let cdOff = Int(u32(b, i + 16))
    guard cdOff + 46 <= b.count, u32(b, cdOff) == centralHeader else { throw Failure.notZip }
    return (Int(u32(b, cdOff + 20)), Int(u32(b, cdOff + 24)))
  }

  /// 解开第一个条目。
  public static func unzipFirst(_ data: Data) throws -> Data {
    let e = try firstEntry(data)
    let body = data.subdata(in: e.dataOffset..<(e.dataOffset + e.compressedSize))
    switch e.method {
    case 0: return body
    case 8: return try inflate(body, expected: e.uncompressedSize)
    default: throw Failure.unsupportedMethod(e.method)
    }
  }

  /// 裸 deflate → 原文。`expected` 是 zip 头里写的大小；给 0 就按 8 倍猜着扩。
  public static func inflate(_ body: Data, expected: Int) throws -> Data {
    var capacity = expected > 0 ? expected : max(4096, body.count * 8)
    for _ in 0..<8 {
      var out = Data(count: capacity)
      let n = out.withUnsafeMutableBytes { dst -> Int in
        body.withUnsafeBytes { src -> Int in
          guard let d = dst.bindMemory(to: UInt8.self).baseAddress,
                let s = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
          return compression_decode_buffer(d, capacity, s, body.count, nil, COMPRESSION_ZLIB)
        }
      }
      if n > 0, n < capacity || expected > 0 {
        out.removeSubrange(n..<out.count)
        return out
      }
      if n == capacity { capacity *= 2; continue }   // 可能被截断了，再来一次
      throw Failure.inflateFailed
    }
    throw Failure.inflateFailed
  }

  static func u16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
  static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
    var v: UInt32 = 0
    for k in 0..<4 { v |= UInt32(b[i + k]) << (8 * UInt32(k)) }
    return v
  }
}
