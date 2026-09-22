import AVFAudio
import Combine
import SwiftUI
import UserNotifications

/// 铃声试听与实际通知共用资源；一次只播一段，不抢占其它 app 的音频。
@MainActor
final class AlertSoundPreview: ObservableObject {
  private var player: AVAudioPlayer?
  private var pending: Task<Void, Never>?
  private var notificationID: String?
  nonisolated static let category = "kanpan.alert.sound.preview"

  func play(_ sound: AlertSound) {
    stop()
    guard let name = sound.fileName else {
      // iOS 没有公开的系统默认铃声文件 URL。默认档交给通知系统，尊重已有权限。
      let id = Self.category + "." + UUID().uuidString
      notificationID = id
      pending = Task {
        guard await AlertNotifications.isAuthorized(), !Task.isCancelled else { return }
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.categoryIdentifier = Self.category
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
        if Task.isCancelled {
          UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        }
      }
      return
    }
    guard let url = Bundle.main.url(forResource: name, withExtension: nil) else { return }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.ambient, mode: .default)
      try session.setActive(true)
      player = try AVAudioPlayer(contentsOf: url)
      player?.numberOfLoops = 0
      player?.prepareToPlay()
      player?.play()
    } catch {
      stop()
    }
  }

  func stop() {
    pending?.cancel()
    pending = nil
    if let notificationID {
      UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
    }
    notificationID = nil
    player?.stop()
    player = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}

struct AlertSoundPage: View {
  var store: PrefsStore
  @Environment(\.panelTheme) private var t
  @StateObject private var preview = AlertSoundPreview()
  @State private var lifecycle: AppLifecycle.ResourceToken?

  var body: some View {
    PanelSheet(title: "提醒铃声", subtitle: nil) {
      ForEach(AlertSound.allCases, id: \.self) { sound in
        PanelRow(name: sound.title, onTap: {
          store.update { $0.alertSound = sound }
          preview.play(sound)
        }) {
          Image(systemName: "checkmark")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(t.amber)
            .opacity(store.prefs.alertSound == sound ? 1 : 0)
            .accessibilityHidden(true)
        }
        .accessibilityIdentifier("alerts.sound." + sound.rawValue)
        .accessibilityValue(store.prefs.alertSound == sound ? "已选" : "未选")
        .accessibilityAddTraits(store.prefs.alertSound == sound ? .isSelected : [])
      }
    }
    .toolbar(.hidden, for: .navigationBar)
    .onAppear {
      guard lifecycle == nil else { return }
      lifecycle = AppLifecycle.shared.registerResources(
        id: "alerts.sound.preview", leave: { [weak preview] in preview?.stop() }, enter: {})
    }
    .onDisappear {
      preview.stop()
      if let lifecycle { AppLifecycle.shared.unregisterResources(token: lifecycle) }
      lifecycle = nil
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("alerts.sound.page")
  }
}
