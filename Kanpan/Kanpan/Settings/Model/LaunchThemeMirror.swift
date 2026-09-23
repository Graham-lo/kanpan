import Foundation

/// 「冷启动要读、但档案还没到货」的那几样东西，在本机留的一份镜像该落在哪。
///
/// 选法和 `PrefsStore.deviceStorage()` / `MarketRoutePolicyStore.defaults` 一致：
/// UI 用例各自有自己的一套 defaults，跑测不会把真机上的镜像改掉。
/// `LaunchHostMirror` 和 `LaunchThemeMirror` 共用这一份，免得两处各写一遍走样。
enum LaunchMirror {
  /// 单测专用：把整份镜像挪进**这条用例自己的**柜子。
  ///
  /// 用 task-local 而不是普通全局变量，是因为 swift-testing 默认并发跑用例：
  /// 镜像是进程级的一格 `UserDefaults`，任何一条用例只要建了 `PrefsStore` 就会
  /// 顺手把出厂皮肤镜像出去，隔壁那条正在断言「记下什么读回什么」的用例就随机变红
  /// （2026-09-19 查到的存量毛病，不是这轮改出来的）。task-local 只在当前这条用例
  /// 的任务里可见，写者各写各的。生产路径上它永远是 nil，行为一个字没变。
  @TaskLocal static var override: UserDefaults?

  /// 测试模式但**没给**有效 UUID 时共用的那一格。
  ///
  /// 以前这种情况回的是 `.standard`：跑一次 UI 用例就把这台机器（包括真机）上
  /// 「冷启动第一帧的皮肤」给改了。镜像本身是可再生的小东西，但没有任何理由让
  /// 测试去写用户那一格。名字是固定的，所以同一条用例里反复冷启动照样读得回来
  /// ——这正是启动镜像要验的东西。
  private static let sharedTestSuite = "kanpan.tests.shared"

  static var defaults: UserDefaults {
    if let override { return override }
    #if DEBUG
    let env = ProcessInfo.processInfo.environment
    if env["KANPAN_TEST_PROFILE"] == "1" {
      let profile = env["KANPAN_PERSISTENCE_PROFILE"].flatMap { UUID(uuidString: $0)?.uuidString }
      let name = profile.map { "kanpan.tests." + $0 } ?? sharedTestSuite
      if let suite = UserDefaults(suiteName: name) { return suite }
    }
    #endif
    return .standard
  }
}

/// 冷启动**第一帧底色**要用的皮肤与深浅，在本机留的一份镜像。
///
/// 病根和 `LaunchHostMirror` 是同一个：皮肤 / 深浅的真身在账号目录里的 `prefs.json`
/// （`PersonalFileStorage`），而 `MainScreen` 那个 `PrefsStore` 是在第一帧**之前**就
/// 构造好的，那一刻只有 `UserDefaults` 可读——里头根本没有 prefs 这个键，于是读出来的
/// 是**出厂值**（青苔 · 跟随系统）。没登录的人还好，访客档案在 `boot()` 里是同步装的，
/// 赶得上第一帧；登录过的人不行，账号那份要等 `account.restore()` 异步回来，于是
/// 「一个选了陶土 · 深色的人」每次冷启动都要先看一眼青苔（或者跟着系统的浅色），
/// 等账号回来再整屏换一次。这正是判据①（改过的设置在这条路上悄悄回了默认）
/// 和判据③（改完要等一下才生效）。
///
/// 所以照 `LaunchHostMirror` 的老规矩办：`PrefsStore` 每次落盘、每次换档案都顺手把
/// 皮肤与深浅镜像到本机，第一帧直接拿镜像开张，不解整份 `Prefs`，也不等账号桥。
/// 没镜像（全新安装、或升上这版的第一次启动）就按出厂值走，和原来一样，不会更差。
///
/// 和 `LaunchHostMirror` 的一点不同：域名是「这台机器所处网络的属性」，本来就不跟人走；
/// 皮肤和深浅**是跟人走的**（在 `PersonalSyncCodec.fields` 里），这儿留的只是
/// 「这台机器上最后一次落盘的那个人的皮肤」——一份给第一帧顶上用的缓存。真档案一到货
/// （`AppAccountBridge.onProfileReady`）就以档案为准，镜像随下一次落盘改过来。
///
/// 覆盖不到的那一段：**app 进程起来之前的系统启动屏**。它由系统渲染并缓存，
/// 读不到 `UserDefaults`，更读不到账号档案，只能跟系统深浅走一个写死的 asset 颜色
/// （`Assets.xcassets/LaunchBackground.colorset`，见 `Kanpan/Config/Info.plist`
/// 里 `UILaunchScreen` 那段注释）。这条线画在这儿：启动屏跟系统，第一帧起跟人。
enum LaunchThemeMirror {
  static let skinKey = "kanpan.launch.skin"
  static let themeKey = "kanpan.launch.theme"

  /// 镜像里记着的皮肤与深浅。没记过、或记的东西形状不对，都退回出厂值。
  static var choice: (skin: ThemeSkin, theme: ThemeChoice) {
    let d = LaunchMirror.defaults
    let skin = d.string(forKey: skinKey).flatMap(ThemeSkin.init(rawValue:)) ?? .fallback
    let theme = d.string(forKey: themeKey).flatMap(ThemeChoice.init(rawValue:)) ?? .fallback
    return (skin, theme)
  }

  /// 档案还没到货时先拿它顶上：一份只有皮肤与深浅当真的 `Prefs`。
  ///
  /// 只兑现这两项是有意的。其余偏好（周期、副图、域名……）各有自己的到货路径，
  /// 在这儿猜一遍只会多一次「先按镜像开、再按档案改」的抖动；底色不一样——
  /// 它是**第一帧就已经画在屏幕上**的东西，晚一拍就是用户眼里的一次闪。
  static func prefs() -> Prefs {
    var value = Prefs.defaults
    let c = choice
    value.skin = c.skin
    value.theme = c.theme
    return value
  }

  /// 落盘时同步一次。没变就不写。
  static func set(skin: ThemeSkin, theme: ThemeChoice) {
    let d = LaunchMirror.defaults
    if d.string(forKey: skinKey) != skin.rawValue { d.set(skin.rawValue, forKey: skinKey) }
    if d.string(forKey: themeKey) != theme.rawValue { d.set(theme.rawValue, forKey: themeKey) }
  }
}

/// 冷启动**第一帧停在哪一格**，在本机留的一份镜像。
///
/// 落点本来由 `MainScreen.honorProfile()` 按档案定：有自选停自选，没有停图表。
/// 可档案到货有先后——访客那份在 `boot()` 里同步装，登录用户那份要等
/// `account.restore()` 异步回来（实测约 0.2s）。`tab` 的初值又只能写死一个，
/// 于是登录过、有自选的人每次冷启动都先看一眼 BTC 图表，再跳到自选，像闪了一下。
///
/// 所以照皮肤镜像的老规矩：每次落点被档案判定，就把结论记到本机；第一帧直接拿它开张。
/// 只存一个布尔，只在本机、不同步——它是「这台机器上次判出来的落点」的缓存，
/// 档案一到货仍以档案为准（`honorProfile()` 照判一次，判得和镜像一样就等于没动）。
/// 没镜像（全新安装、或升上这版的第一次）按原来的图表开张，不会更差。
enum LaunchLandingMirror {
  static let key = "kanpan.launch.landing"

  /// 上次判定的落点是不是自选页。
  static var favorites: Bool { LaunchMirror.defaults.string(forKey: key) == "favorites" }

  /// 档案判定一次就记一次。没变就不写。
  static func set(favorites: Bool) {
    let value = favorites ? "favorites" : "chart"
    let d = LaunchMirror.defaults
    if d.string(forKey: key) != value { d.set(value, forKey: key) }
  }
}
