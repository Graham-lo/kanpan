import Foundation
import KanpanAccount
import KanpanCore
import ReviewData

/// 没有界面时，交易所回合往哪儿传（审查 E·待核实五）。
///
/// 后台刷新（`BGAppRefreshTask`）把 app 拉起时场景不连，`MainScreen` 不建——复盘本、
/// 账号、账号桥都是它的状态，一个都不在，`AccountFiles.currentProfile` 也还是空串。
/// 交易所桥拉到新回合，得自己知道两件事：
/// - **此刻是谁的档案**（`profile`）：判这批回合给不给这个人、传不传进他的账号，
///   和账号桥装档案用的是同一个口径（`AccountFiles.profileID`）。
/// - **怎么传**（`upload`）：和复盘本同一条路——同一个档案目录下的 `TradeReviewStore`、
///   钉住这个人的 `ScorebookClient`、`TradeSync.upload`。传完的标记落在同一份
///   `trades-v1.json` 里，回前台复盘本读到的就是「已经传过」，不会再传一遍。
///   没登录、或者钥匙串这会儿读不动（没有令牌）时没有这一项：只拉不传。
struct ExchangeReviewUplink {
  var profile: String
  var upload: (@MainActor ([TradeRound]) async -> Void)?

  /// 登录着的人：按他的档案目录与上传通道把回合交给服务端。
  @MainActor static func signedIn(profile: String, directory: URL, client: ScorebookClient) -> ExchangeReviewUplink {
    let store = TradeReviewStore(directory: directory)
    return ExchangeReviewUplink(profile: profile, upload: { rounds in
      _ = await TradeSync.upload(rounds, store: store, client: client)
    })
  }

  /// 正式装配：读账号根目录的登记簿、钥匙串里的会话。
  ///
  /// 账号客户端照 `AccountFeature` 的口径造（线上地址、钥匙串服务名、测试档案那几条岔路
  /// 都只在它那儿），这儿只取它的 `client`，不另抄一份配置。
  @MainActor static func resolve() async -> ExchangeReviewUplink? {
    guard let files = try? AccountFiles(root: AccountsRoot.url) else { return nil }
    guard let api = AccountFeature().client else {
      return ExchangeReviewUplink(profile: files.profileID(user: nil), upload: nil)
    }
    if let user = await api.savedUser() {
      let profile = files.profileID(user: user.id)
      guard let directory = try? files.directory(user: user.id) else {
        return ExchangeReviewUplink(profile: profile, upload: nil)
      }
      // 钉住这个人：换号之后还在途的那一趟当场取消，不带着下一个人的令牌出门（和账号桥同一个做法）。
      let owner = user.id
      let client = ScorebookClient { path, method, body, key in
        try await api.data(path, method: method, body: body, key: key, owner: owner)
      }
      return signedIn(profile: profile, directory: directory, client: client)
    }
    // 钥匙串读不动（锁屏后被拉起之类）：按上次装的那个人认档案，回合照常拉、照常归他，
    // 只是这一轮没有令牌传不了，回前台由复盘本补传。
    if await api.credentialsUnavailable, let last = files.lastOwner {
      return ExchangeReviewUplink(profile: files.profileID(user: last.id), upload: nil)
    }
    return ExchangeReviewUplink(profile: files.profileID(user: nil), upload: nil)
  }
}
