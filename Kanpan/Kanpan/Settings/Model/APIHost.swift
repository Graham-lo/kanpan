import Foundation
import KanpanData

/// 自定义 API 域名（§4.1 / A6.10）。出厂值是默认交易所的 REST 域名，
/// 换镜像域时改这一个字段——默认交易所的提供者（`MarketEndpoints.restHost`）直接吃它。
///
/// 只做**形状**上的校验：通不通得连上去才知道（A6.10 是拿一个不通的域名手验的，
/// 「离线」状态由数据层报，不在这里假装能预判）。
enum APIHost {
  static let `default` = VenueRegistry.defaultRestHost
  /// 行情推送（WebSocket）域名。和 REST 分开填：这两个本来就是两台，
  /// 换镜像、走代理的时候往往只有一边通（§4.1 的两条 URL）。
  /// 出厂值怎么选出来的（逐条实测）写在默认交易所的提供者那里。
  static let defaultStream = VenueRegistry.defaultStreamHost

  /// 该迁走的旧推送域名。存过它们的设备要换到新默认值，否则老配置会一直把人钉死在
  /// 不可用的域名或测试网上。清单归默认交易所的提供者管。
  static let legacyStreams = VenueRegistry.legacyStreamHosts
  static let gateway = "kanpan.107-174-172-10.sslip.io"

  static let gatewayBackup = "kanpan.96-44-162-222.sslip.io:8443"

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

/// 冷启动热身要用的那两个域名，在本机留的一份镜像。
///
/// 域名的真身在 `Prefs.apiHost` / `Prefs.streamHost`，而设置档案早就搬进了账号目录里的
/// `prefs.json`（`AppAccountBridge`）。`LaunchPrewarm` 偏偏跑在账号桥把档案装进来之前
/// ——那一刻只有 `UserDefaults.standard` 可读，读出来的是出厂域名。于是改过域名的人
/// 每次冷启动热的都是一台他根本不会连的机器：白付一次 DNS + TLS，真正要连的那台一点
/// 没热，正好把热身想省下来的那几百毫秒又赔回去。
///
/// 按 `MarketRoutePolicyStore` 的老规矩办：域名是**这台机器所处网络的属性**
/// （`PersonalSyncCodec.keepDeviceFields` 里就有这两个，本来就不跟人走），所以在本机
/// 留一份镜像，`PrefsStore` 每次落盘顺手同步一次；热身直接读镜像，不解整份 `Prefs`，
/// 也不用等账号桥。没镜像（全新安装、或升上这版的第一次启动）就按出厂域名热——
/// 和原来一样，不会更差，而第二次冷启动开始就对了。
enum LaunchHostMirror {
  static let apiKey = "kanpan.launch.apiHost"
  static let streamKey = "kanpan.launch.streamHost"

  /// 测试沙盒里用自己的一份 defaults（见 `LaunchMirror`）——UI 用例不会把真机上的镜像改掉。
  private static var defaults: UserDefaults { LaunchMirror.defaults }

  /// 镜像里记着的两个域名。没记过、或记的东西形状不对，都退回出厂值。
  static var hosts: (api: String, stream: String) {
    let api = defaults.string(forKey: apiKey).map(APIHost.sanitize) ?? APIHost.default
    let stream = defaults.string(forKey: streamKey).flatMap { raw -> String? in
      let host = APIHost.normalize(raw)
      return APIHost.isValid(host) ? host : nil
    } ?? APIHost.defaultStream
    return (api, stream)
  }

  /// 落盘时同步一次。没变就不写。
  static func set(api: String, stream: String) {
    let d = defaults
    if d.string(forKey: apiKey) != api { d.set(api, forKey: apiKey) }
    if d.string(forKey: streamKey) != stream { d.set(stream, forKey: streamKey) }
  }
}
