import Foundation

/// 自定义 API 域名（§4.1 / A6.10）。默认 `fapi.binance.com`，
/// 换镜像域时改这一个字段——`KanpanData.BinanceHosts.fapi` 直接吃它。
///
/// 只做**形状**上的校验：通不通得连上去才知道（A6.10 是拿一个不通的域名手验的，
/// 「离线」状态由数据层报，不在这里假装能预判）。
enum APIHost {
  static let `default` = "fapi.binance.com"
  /// 行情推送（WebSocket）域名。和 REST 分开填：这两个在币安本来就是两台，
  /// 换镜像、走代理的时候往往只有一边通（§4.1 的两条 URL）。
  ///
  /// 默认是 `dstream.binance.me`。这个值 2026-09-18 逐条实测定下来，两条理由：
  ///
  /// 一、**它是生产盘，不是测试网**。`stream.binancefuture.com` / `fstream.binancefuture.com`
  /// 虽然挂在官方文档上，实测推的是合约测试网的数据——同一时刻它的 24h 成交额是
  /// 1214 亿、成交笔数 31.6 万，和 `testnet.binancefuture.com` 的 REST 逐字段相同，
  /// 而生产盘 `fapi.binance.com` 是 139 亿、431 万笔。测试网上大多数山寨根本没有成交，
  /// 所以 K 线和自选列表看上去「不跳」。
  ///
  /// 二、**从国内这条出口看，`fstream` 这一族只剩盘口流**。`fstream.binance.me`（直连）
  /// 与 `fstream.binance.com`（走代理）都只发 `bookTicker`/`depth`，`kline`/`ticker`/
  /// `aggTrade`/`markPrice` 订阅回 `result:null` 之后一帧不发——`/ws`、`/stream`、
  /// `/public/ws`、`/public/stream` 四种路径都试过，20~30 秒窗口里 `bookTicker` 六千多帧、
  /// `kline` 零帧。同一时刻同一出口的 `dstream.binance.me` 一切正常。
  ///
  /// 这是**按出口而异**的，不要写成「币安把合约流搬走了」：同一天美国机房的网关上
  /// 实测 `fstream.binance.com` 的 `kline_1m` 是正常出帧的（30 秒 35 帧，生产盘量级）。
  /// 所以这条只是「国内这两条出口上 `fstream` 不可用」，服务端选域名要在服务端自己测。
  ///
  /// 顺带记一个容易看错的地方：`dstream` 上 `btcusdt@aggTrade` 的 id 是 34 亿量级，
  /// 而 `fapi` 的 24hrTicker 里 `firstId`/`lastId` 是 80 亿量级——这两个本来就是
  /// 不同的序列（聚合成交 id ≠ 逐笔成交 id），不是测试网的证据。要对生产盘就对
  /// `count` 和 `quoteVolume`：实测同一时刻 `fapi` 是 3393098 笔 / 108.91 亿，
  /// `dstream.binance.me` 的 `btcusdt@ticker` 是 3393408 笔 / 108.92 亿，同一个盘。
  ///
  /// 在 `.me` 和 `.com` 之间选 `.me`：国内 DNS 解析干净（返回真实的 AWS 东京地址，没有被投毒），
  /// 可以直连，实测比走代理快——握手 361~423ms 对 785~791ms，首帧 666~762ms 对 1148~1175ms，
  /// 同时并发跑两条连接测推送延迟，直连比代理低约 30ms，收到的帧数一致（不丢帧）。
  static let defaultStream = "dstream.binance.me"

  /// 该迁走的旧推送域名。存过它们的设备要换到新默认值，否则老配置会一直把人钉死在
  /// 对国内用户不可用的域名（`fstream.binance.com`）或测试网（`*.binancefuture.com`）上。
  static let legacyStreams = [
    "fstream.binance.com",          // 国内这条出口上只剩盘口流，且本身也解析不干净
    "stream.binancefuture.com",     // 测试网
    "fstream.binancefuture.com",    // 测试网
    "dstream.binancefuture.com",    // 测试网
  ]
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

  /// 测试沙盒里用自己的一份 defaults，选法和 `PrefsStore.deviceStorage()` /
  /// `MarketRoutePolicyStore.defaults` 一致——UI 用例不会把真机上的镜像改掉。
  private static var defaults: UserDefaults {
    let env = ProcessInfo.processInfo.environment
    if env["KANPAN_TEST_PROFILE"] == "1", let profile = env["KANPAN_PERSISTENCE_PROFILE"],
       UUID(uuidString: profile) != nil, let suite = UserDefaults(suiteName: "kanpan.tests." + profile) {
      return suite
    }
    return .standard
  }

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
