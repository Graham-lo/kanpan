import Foundation

/// Prefs 解码的进程内一格记忆。
///
/// 冷启动会把同一份设置解两遍：`LaunchPrewarm.run()` 从 `UserDefaults` 解一次，
/// 只为了拿两个域名去热连接；紧接着 `AppAccountBridge.prepare(nil)` 从账号目录
/// 再解一次。`Prefs` 不小（配色、指标、周期一大摞），两遍都压在 Scene 起来之前。
///
/// 这里按**原始字节**记住上一次的解码结果：字节一样就直接还回去，一次解码都不用。
/// 只记一格——这两个调用点是紧挨着的，记多了也用不上。
/// `PrefsStore.swift` 归别的窗口改，所以收口只做在这两个调用点上，`PrefsStore.load`
/// 本身一个字没动。
@MainActor
enum PrefsDecodeCache {
  private static var cachedData: Data?
  private static var cachedValue: Prefs?

  /// 和 `PrefsStore.load(from:key:)` 等价，只是命中记忆时跳过解码。
  /// 读盘仍然只读一次（`PrefsStore.load` 内部也是读一次再解）。
  static func load(from storage: any PrefsStorage, key: String = PrefsCodec.key) -> Prefs {
    let data = storage.prefsData(forKey: key)
    if let data, data == cachedData, let cachedValue { return cachedValue }
    let value = PrefsCodec.decode(data)
    cachedData = data; cachedValue = value
    return value
  }
}
