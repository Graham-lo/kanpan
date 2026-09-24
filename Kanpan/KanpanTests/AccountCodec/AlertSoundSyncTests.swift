import Testing
@testable import Kanpan

@Suite("提醒铃声随人走")
struct AlertSoundSyncTests {
  @Test("四档上传、下行合并与旧客户端缺字段", arguments: AlertSound.allCases)
  func sync(_ sound: AlertSound) throws {
    var source = Prefs.defaults
    source.alertSound = sound
    let uploaded = try PersonalSyncCodec.settings(source)
    #expect(uploaded.body["alertSound"] == .string(sound.rawValue))
    let received = try PersonalSyncCodec.apply(uploaded, to: .defaults)
    #expect(received.alertSound == sound)
    var legacy = uploaded
    legacy.body.removeValue(forKey: "alertSound")
    #expect(try PersonalSyncCodec.apply(legacy, to: source).alertSound == sound)
  }
}
