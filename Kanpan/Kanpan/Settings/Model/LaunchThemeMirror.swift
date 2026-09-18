import Foundation

/// 「冷启动要读、但档案还没到货」的那几样东西，在本机留的一份镜像该落在哪。
///
/// 选法和 `PrefsStore.deviceStorage()` / `MarketRoutePolicyStore.defaults` 一致：
/// UI 用例各自有自己的一套 defaults，跑测不会把真机上的镜像改掉。
/// `LaunchHostMirror` 和 `LaunchThemeMirror` 共用这一份，免得两处各写一遍走样。
enum LaunchMirror {
  static var defaults: UserDefaults {
    let env = ProcessInfo.processInfo.environment
    if env["KANPAN_TEST_PROFILE"] == "1", let profile = env["KANPAN_PERSISTENCE_PROFILE"],
       UUID(uuidString: profile) != nil, let suite = UserDefaults(suiteName: "kanpan.tests." + profile) {
      return suite
    }
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
