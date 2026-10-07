import Foundation
import KanpanAccount

/// 「登录设备」那张表在本机的一份（体感优化 2026-10-07）。
///
/// 进这一页先摆上回看到的那张，再去服务端刷新：网慢的时候页面不是空的，刷新回来原地换。
/// 只是一份「上回看到的样子」，不是权威：服务端那张一回来就整张盖掉。
/// 按人记（换了账号上一个人的表不摆出来），退登就删。体量封顶 `limit` 台
/// （一个账号每类设备只许一台在线，正常也就三四行）。
struct DeviceListCache: Sendable {
  static let limit = 20
  let file: URL

  init(directory: URL) {
    file = directory.appendingPathComponent("account-devices.json")
  }

  private struct Payload: Codable {
    var user: UUID
    var devices: [AccountSessionDevice]
  }

  /// 这个人上回看到的那张；别人的、读不动的、解不开的都当没有。
  func load(for user: UUID) -> [AccountSessionDevice]? {
    guard let data = try? Data(contentsOf: file),
          let payload = try? JSONDecoder().decode(Payload.self, from: data),
          payload.user == user else { return nil }
    return Array(payload.devices.prefix(Self.limit))
  }

  func save(_ devices: [AccountSessionDevice], for user: UUID) {
    let payload = Payload(user: user, devices: Array(devices.prefix(Self.limit)))
    guard let data = try? JSONEncoder().encode(payload) else { return }
    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: file, options: .atomic)
  }

  func clear() {
    try? FileManager.default.removeItem(at: file)
  }
}
