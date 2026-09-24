import Foundation
import Testing
@testable import Kanpan

@Suite("提醒铃声")
struct AlertSoundTests {
  @Test("四档映射与往返持久化", arguments: AlertSound.allCases)
  func roundTrip(_ sound: AlertSound) throws {
    var prefs = Prefs.defaults
    prefs.alertSound = sound
    let data = PrefsCodec.encode(prefs)
    #expect(PrefsCodec.decode(data).alertSound == sound)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["alertSound"] as? String == sound.rawValue)
    let names: [AlertSound: String] = [.crisp: "alert-crisp.caf", .electronic: "alert-electronic.caf", .glass: "alert-glass.caf"]
    #expect(sound.fileName == names[sound])
    #expect(PrefsFieldPlan.table["alertSound"] == .synced)
  }

  @Test("缺省、未知与坏类型只回退铃声，不重置别的设置")
  func fallback() {
    for json in [#"{"skin":"terra"}"#, #"{"skin":"terra","alertSound":"future"}"#,
                 #"{"skin":"terra","alertSound":42}"#, #"{"skin":"terra","alertSound":null}"#] {
      let prefs = PrefsCodec.decode(Data(json.utf8))
      #expect(prefs.alertSound == .default)
      #expect(prefs.skin.rawValue == "terra")
    }
  }

  @Test("重新创建设置存储仍保留选择") @MainActor
  func restart() {
    let storage = InMemoryPrefsStorage()
    let store = PrefsStore(storage: storage, cache: UnavailableMarketCache())
    store.update { $0.alertSound = .glass }
    #expect(PrefsStore.load(from: storage).alertSound == .glass)
  }
}
