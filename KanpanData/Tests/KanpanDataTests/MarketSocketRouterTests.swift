import Foundation
import Testing
@testable import KanpanData

// 选路本身的用例在 `KanpanNetwork` 包里；这里只剩历史 OI 网关响应的解析。
@Suite("历史OI网关解析") struct OIGatewayDecodeTests {
  @Test("历史OI网关时间戳、数值和坏响应检查")
  func archiveDecode() throws {
    let points = try OISource.decodeGateway(Data("[[1638316800000,102],[1638317100000,101]]".utf8))
    #expect(points.count == 2 && points[0].value == 102)
    #expect(throws: (any Error).self) { try OISource.decodeGateway(Data("[[1638316800000]]".utf8)) }
  }
}
