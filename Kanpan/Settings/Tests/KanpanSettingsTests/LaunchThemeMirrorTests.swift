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

  /// 每条用例自己收拾干净，免得互相串味，也免得把跑测这台机器上的镜像留成脏值。
  private func wipe() {
    let d = LaunchMirror.defaults
    d.removeObject(forKey: LaunchThemeMirror.skinKey)
    d.removeObject(forKey: LaunchThemeMirror.themeKey)
  }

  @Test("没记过就按出厂值走：青苔 · 跟随系统")
  func 空镜像退回出厂() {
    wipe()
    #expect(LaunchThemeMirror.choice.skin == ThemeSkin.fallback)
    #expect(LaunchThemeMirror.choice.theme == ThemeChoice.fallback)
    #expect(LaunchThemeMirror.prefs().skin == Prefs.defaults.skin)
    #expect(LaunchThemeMirror.prefs().theme == Prefs.defaults.theme)
  }

  @Test("记下什么读回什么")
  func 往返() {
    wipe()
    LaunchThemeMirror.set(skin: .terra, theme: .dark)
    #expect(LaunchThemeMirror.choice.skin == .terra)
    #expect(LaunchThemeMirror.choice.theme == .dark)
    #expect(LaunchThemeMirror.prefs().skin == .terra)
    #expect(LaunchThemeMirror.prefs().theme == .dark)
    wipe()
  }

  @Test("镜像里写了别的东西不算数，退回出厂而不是崩")
  func 脏值() {
    wipe()
    LaunchMirror.defaults.set("不是皮肤", forKey: LaunchThemeMirror.skinKey)
    LaunchMirror.defaults.set(42, forKey: LaunchThemeMirror.themeKey)
    #expect(LaunchThemeMirror.choice.skin == ThemeSkin.fallback)
    #expect(LaunchThemeMirror.choice.theme == ThemeChoice.fallback)
    wipe()
  }

  @Test("只兑现皮肤与深浅，别的偏好一个字不猜")
  func 只管底色() {
    wipe()
    LaunchThemeMirror.set(skin: .classic, theme: .light)
    let p = LaunchThemeMirror.prefs()
    #expect(p.skin == .classic)
    #expect(p.theme == .light)
    #expect(p.interval == Prefs.defaults.interval)
    #expect(p.apiHost == Prefs.defaults.apiHost)
    #expect(p.subs == Prefs.defaults.subs)
    wipe()
  }

  @Test("落一次盘就把皮肤与深浅镜像出来")
  @MainActor
  func 落盘时同步() {
    wipe()
    let store = PrefsStore(storage: InMemoryPrefsStorage(), cache: UnavailableMarketCache())
    store.update { $0.skin = .terra; $0.theme = .dark }
    #expect(LaunchThemeMirror.choice.skin == .terra)
    #expect(LaunchThemeMirror.choice.theme == .dark)
    wipe()
  }

  /// 登录的人那份档案是 `AppAccountBridge` 异步装进来的，走的是 `useStorage`。
  /// 它也得把镜像改过来，否则「下次冷启动先闪一屏上一个人的皮肤」。
  @Test("换档案（登录 / 退登）也把镜像改过来")
  @MainActor
  func 换档案时同步() {
    wipe()
    let store = PrefsStore(storage: InMemoryPrefsStorage(), cache: UnavailableMarketCache())
    var mine = Prefs.defaults
    mine.skin = .classic
    mine.theme = .dark
    store.useStorage(InMemoryPrefsStorage(), prefs: mine)
    #expect(LaunchThemeMirror.choice.skin == .classic)
    #expect(LaunchThemeMirror.choice.theme == .dark)
    wipe()
  }

  /// 这是 `MainScreen` 那一行真正依赖的东西：柜子是空的就从镜像起步。
  @Test("柜子空着时从镜像起步，有存档时一个字不掺")
  @MainActor
  func 空柜子拿镜像起步() {
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
