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
    // 2026-09-24 UI 整改 P1b：从提醒总表推进来的一层，走系统导航栏（居中标题 + 系统返回），
    // 不再自绘「‹」头；四行各 44 高，选中的那一行名字与勾都用皮肤强调色。
    ScrollView {
      VStack(spacing: 0) {
        ForEach(AlertSound.allCases, id: \.self) { sound in
          let selected = store.prefs.alertSound == sound
          PanelRow(name: sound.title, highlighted: selected, onTap: {
            store.update { $0.alertSound = sound }
            preview.play(sound)
          }) {
            Image(systemName: "checkmark")
              .font(TypeScale.bodyEmph)
              .foregroundStyle(t.amber)
              .opacity(selected ? 1 : 0)
              .accessibilityHidden(true)
          }
          .accessibilityIdentifier("alerts.sound." + sound.rawValue)
          .accessibilityValue(selected ? "已选" : "未选")
          .accessibilityAddTraits(selected ? .isSelected : [])
        }
      }
      .padding(.top, Space.xs)
      .padding(.bottom, Space.l)
    }
    .scrollBounceBehavior(.basedOnSize)
    .background(t.raised.ignoresSafeArea())
    .navigationTitle("提醒铃声")
    .navigationBarTitleDisplayMode(.inline)
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
