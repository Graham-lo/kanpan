import Testing
import Foundation
import KanpanCore
import KanpanData
@testable import KanpanSettings

/// 冷启动第一帧的底色：皮肤与深浅的本机镜像。
///
/// 要守的那件事：一个选了「陶土 · 深色」的人，冷启动第一帧就该是陶土的深色，
/// 而不是先铺一屏出厂的青苔（或跟着系统的浅色）、等账号档案异步回来再整屏换一次。
/// 那一次换在用户眼里就是一闪（判据①改过的设置悄悄回了默认、③改完要等一下才生效）。
@Suite("首帧底色镜像", .serialized)
struct LaunchThemeMirrorTests {

  /// 这个套件断言的是一格**进程级**的镜像，而任何一条用例只要建了 `PrefsStore`
  /// 就会顺手往那一格写出厂皮肤。swift-testing 默认并发跑，隔壁套件的写就会
  /// 随机把这里的断言打红。所以整套挪进自己的柜子（`LaunchMirror.override`），
  /// 各写各的，互不串味。
  static let box = UserDefaults(suiteName: "kanpan.tests.launch-theme-mirror")!

  /// 每条用例自己收拾干净，免得互相串味，也免得把跑测这台机器上的镜像留成脏值。
  private func wipe() {
    let d = LaunchMirror.defaults
    d.removeObject(forKey: LaunchThemeMirror.skinKey)
    d.removeObject(forKey: LaunchThemeMirror.themeKey)
  }

  @Test("没记过就按出厂值走：青苔 · 跟随系统")
  func 空镜像退回出厂() {
    LaunchMirror.$override.withValue(Self.box) {
      wipe()
      #expect(LaunchThemeMirror.choice.skin == ThemeSkin.fallback)
      #expect(LaunchThemeMirror.choice.theme == ThemeChoice.fallback)
      #expect(LaunchThemeMirror.prefs().skin == Prefs.defaults.skin)
      #expect(LaunchThemeMirror.prefs().theme == Prefs.defaults.theme)
    }
  }

  @Test("记下什么读回什么")
  func 往返() {
    LaunchMirror.$override.withValue(Self.box) {
      wipe()
      LaunchThemeMirror.set(skin: .terra, theme: .dark)
      #expect(LaunchThemeMirror.choice.skin == .terra)
      #expect(LaunchThemeMirror.choice.theme == .dark)
      #expect(LaunchThemeMirror.prefs().skin == .terra)
      #expect(LaunchThemeMirror.prefs().theme == .dark)
      wipe()
    }
  }

  @Test("镜像里写了别的东西不算数，退回出厂而不是崩")
  func 脏值() {
    LaunchMirror.$override.withValue(Self.box) {
      wipe()
      LaunchMirror.defaults.set("不是皮肤", forKey: LaunchThemeMirror.skinKey)
      LaunchMirror.defaults.set(42, forKey: LaunchThemeMirror.themeKey)
      #expect(LaunchThemeMirror.choice.skin == ThemeSkin.fallback)
      #expect(LaunchThemeMirror.choice.theme == ThemeChoice.fallback)
      wipe()
    }
  }

  @Test("只兑现皮肤与深浅，别的偏好一个字不猜")
  func 只管底色() {
    LaunchMirror.$override.withValue(Self.box) {
      wipe()
      LaunchThemeMirror.set(skin: .classic, theme: .light)
      let p = LaunchThemeMirror.prefs()
      #expect(p.skin == .classic)
      #expect(p.theme == .light)
      #expect(p.interval == Prefs.defaults.interval)
      #expect(p.routePolicy == Prefs.defaults.routePolicy)
      #expect(p.subs == Prefs.defaults.subs)
      wipe()
    }
  }

  @Test("落一次盘就把皮肤与深浅镜像出来")
  @MainActor
  func 落盘时同步() {
    LaunchMirror.$override.withValue(Self.box) {
      wipe()
      let store = PrefsStore(storage: InMemoryPrefsStorage(), cache: UnavailableMarketCache())
      store.update { $0.skin = .terra; $0.theme = .dark }
      #expect(LaunchThemeMirror.choice.skin == .terra)
      #expect(LaunchThemeMirror.choice.theme == .dark)
      wipe()
    }
  }

  /// 登录的人那份档案是 `AppAccountBridge` 异步装进来的，走的是 `useStorage`。
  /// 它也得把镜像改过来，否则「下次冷启动先闪一屏上一个人的皮肤」。
  @Test("换档案（登录 / 退登）也把镜像改过来")
  @MainActor
  func 换档案时同步() {
    LaunchMirror.$override.withValue(Self.box) {
      wipe()
      let store = PrefsStore(storage: InMemoryPrefsStorage(), cache: UnavailableMarketCache())
      var mine = Prefs.defaults
      mine.skin = .classic
      mine.theme = .dark
      store.useStorage(InMemoryPrefsStorage(), prefs: mine, arrival: .ownerSwitched)
      #expect(LaunchThemeMirror.choice.skin == .classic)
      #expect(LaunchThemeMirror.choice.theme == .dark)
      wipe()
    }
  }

  /// 这是 `MainScreen` 那一行真正依赖的东西：柜子是空的就从镜像起步。
  @Test("柜子空着时从镜像起步，有存档时一个字不掺")
  @MainActor
  func 空柜子拿镜像起步() {
    LaunchMirror.$override.withValue(Self.box) {
      wipe()
      LaunchThemeMirror.set(skin: .terra, theme: .dark)

      let empty = InMemoryPrefsStorage()
      let cold = PrefsStore(storage: empty, cache: UnavailableMarketCache(),
                            fallback: LaunchThemeMirror.prefs())
      #expect(cold.prefs.skin == .terra)
      #expect(cold.prefs.theme == .dark)

      // 柜子里有存档：以存档为准，镜像只是个起点，不许覆盖真档案。
      let filled = InMemoryPrefsStorage()
      var saved = Prefs.defaults
      saved.skin = .sage
      saved.theme = .light
      filled.setPrefsData(PrefsCodec.encode(saved), forKey: PrefsCodec.key)
      let warm = PrefsStore(storage: filled, cache: UnavailableMarketCache(),
                            fallback: LaunchThemeMirror.prefs())
      #expect(warm.prefs.skin == .sage)
      #expect(warm.prefs.theme == .light)
      wipe()
    }
  }

  /// 同一台机器上两个人轮着用，冷启动那一帧读到的是谁。
  ///
  /// 镜像本来就只是「这台机器上最后一次落盘的那个人的皮肤」——一份给第一帧顶上用的缓存，
  /// 它不认识账号。所以 A（陶土 · 深色）用过之后换 B（经典 · 浅色）来开，
  /// **B 的第一帧是 A 的陶土**：B 的档案要等 `AppAccountBridge` 那条异步链
  /// （`account.restore()` → `onProfileReady` → `useStorage`）回来才到货，
  /// 而第一帧在那之前就画出去了。这一帧不是 bug，是这份缓存已知且可接受的取舍
  /// ——不装镜像的话那一帧是出厂的青苔，一样不是 B 的，还连 A 自己都伺候不了。
  ///
  /// 真正要守的是它**只错一帧、并且会自愈**：
  ///
  /// - 第 3 步：B 的档案一到货，内存里当场换成 B，**镜像也跟着变成 B**；
  /// - 第 4 步：所以 B 的下一次冷启动，第一帧就已经是 B 的经典，不会再闪一下 A 的陶土。
  ///
  /// 断言的重点在 3 和 4。第 2 步那句写成显式断言，只是为了把「那一帧是 A」摆在明面上，
  /// 而不是让它成为一件没人知道、改坏了也没人发现的行为。
  @Test("同机换号：第一帧还是上一个人的，档案一到货就自愈，下次冷启动不再闪")
  @MainActor
  func 同机两个账号轮换() {
    LaunchMirror.$override.withValue(Self.box) {
      wipe()

      // 1. A 这一轮：A 在这台机器上用过，落了盘，镜像里留下的是 A 的。
      let aStore = PrefsStore(storage: InMemoryPrefsStorage(), cache: UnavailableMarketCache())
      aStore.update { $0.skin = .terra; $0.theme = .dark }
      #expect(LaunchThemeMirror.choice.skin == .terra)
      #expect(LaunchThemeMirror.choice.theme == .dark)

      // 2. app 被杀掉，B 来开。柜子是空的（账号目录里那份还没到货），
      //    第一帧只有镜像可读——读到的是 A 的陶土 · 深色。这一帧就是取舍本身。
      let store = PrefsStore(storage: InMemoryPrefsStorage(), cache: UnavailableMarketCache(),
                             fallback: LaunchThemeMirror.prefs())
      #expect(store.prefs.skin == .terra)
      #expect(store.prefs.theme == .dark)

      // 3. B 的档案到货（`AppAccountBridge.onProfileReady` → `useStorage`）：
      //    内存里当场换成 B，镜像也必须跟着改成 B——这是「下次冷启动不再闪 A」的保证。
      var b = Prefs.defaults
      b.skin = .classic
      b.theme = .light
      store.useStorage(InMemoryPrefsStorage(), prefs: b, arrival: .ownerSwitched)
      #expect(store.prefs.skin == .classic)
      #expect(store.prefs.theme == .light)
      #expect(LaunchThemeMirror.choice.skin == .classic)
      #expect(LaunchThemeMirror.choice.theme == .light)

      // 4. B 的下一次冷启动：同样是空柜子 + 镜像起步，这次第一帧就已经是 B 的了。
      let again = PrefsStore(storage: InMemoryPrefsStorage(), cache: UnavailableMarketCache(),
                             fallback: LaunchThemeMirror.prefs())
      #expect(again.prefs.skin == .classic)
      #expect(again.prefs.theme == .light)

      wipe()
    }
  }
}
