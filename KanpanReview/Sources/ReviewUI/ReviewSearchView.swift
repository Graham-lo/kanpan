import SwiftUI
import ReviewDomain

public struct ReviewSearchView: View {
  @Bindable var feature: ReviewFeature
  public var range: ReviewRange
  public var cutoff: Int64
  @State private var scope = "history"
  @Environment(\.dismiss) private var dismiss
  public init(feature: ReviewFeature, range: ReviewRange, cutoff: Int64) { self.feature = feature; self.range = range; self.cutoff = cutoff }
  public var body: some View {
    NavigationStack {
      VStack {
        Picker("范围", selection: $scope) { Text("市场历史").tag("history"); Text("我的记录").tag("private") }.pickerStyle(.segmented).padding()
        if feature.searching && feature.matches.isEmpty {
          VStack(spacing: 16) { ProgressView(feature.searchProgress); Button("取消") { feature.cancelSearch(); dismiss() } }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        else if let error = feature.searchError {
          ContentUnavailableView { Label(error, systemImage: "magnifyingglass") } actions: {
            Button("重试") { feature.search(range, cutoff: cutoff, scope: scope) }
            if !feature.isConnected { Button("登录") { dismiss(); feature.onLogin() } }
          }
        } else if feature.matches.isEmpty { ContentUnavailableView("没有很像的区间", systemImage: "magnifyingglass") }
        else {
          List {
            if feature.partialSearch { Text("部分行情暂缺，已列出完成比对的结果").font(.caption).foregroundStyle(.secondary) }
            ForEach(feature.matches) { match in
            Button {
              dismiss(); feature.bookOpen = false; feature.captureOpen = false
              feature.onOpenMatch(match, cutoff)
            } label: {
              HStack {
                VStack(alignment: .leading, spacing: 5) {
                  Text(match.range.symbol + " · " + match.range.interval).fontWeight(.medium)
                  Text(Date(timeIntervalSince1970: Double(match.range.start) / 1000), style: .date).font(.caption).foregroundStyle(.secondary)
                  Text("\(match.range.bars) 根").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(); Text(String(format: "相似度 %.0f%%", match.score * 100)).monospacedDigit()
                Image(systemName: "chevron.right").font(.caption)
              }.padding(.vertical, 5)
            }.foregroundStyle(.primary)
              .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button { Task { await feature.saveMatch(match) } } label: { Label(feature.savedMatchIDs.contains(match.id) ? "已保存" : "保存", systemImage: "bookmark") }.tint(.orange)
              }
            }
            if feature.searchNext != nil { Button("更多结果") { Task { await feature.loadMoreMatches() } }.disabled(feature.searching) }
          }.listStyle(.plain)
        }
      }.navigationTitle("找相似").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button { dismiss() } label: { Label("返回", systemImage: "chevron.left") }
              .accessibilityIdentifier("review.search.back")
          }
        }
        .onChange(of: scope) { _, value in feature.search(range, cutoff: cutoff, scope: value) }
        .onDisappear { feature.cancelSearch() }
    }.tint(.orange)
  }
}
public struct ReviewReplayControls: View {
  public var time: Int64
  public var playing: Bool
  public var speed: Int
  public var onStep: (Int) -> Void
  public var onPlay: () -> Void
  public var onSpeed: () -> Void
  public var onJudgment: () -> Void
  public var onExit: () -> Void
  public init(time: Int64, playing: Bool, speed: Int, onStep: @escaping (Int) -> Void, onPlay: @escaping () -> Void, onSpeed: @escaping () -> Void, onJudgment: @escaping () -> Void, onExit: @escaping () -> Void) {
    self.time = time; self.playing = playing; self.speed = speed; self.onStep = onStep; self.onPlay = onPlay; self.onSpeed = onSpeed; self.onJudgment = onJudgment; self.onExit = onExit
  }
  public var body: some View {
    HStack(spacing: 0) {
      Button("退出", action: onExit).frame(minWidth: 44, minHeight: 44)
      Spacer(minLength: 4)
      Button { onStep(-1) } label: { Image(systemName: "backward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("前一根")
      Button(action: onPlay) { Image(systemName: playing ? "pause.fill" : "play.fill").frame(width: 44, height: 44) }.accessibilityLabel(playing ? "暂停" : "播放")
      Button { onStep(1) } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("后一根")
      Button("\(speed)×", action: onSpeed).frame(width: 44, height: 44)
      Spacer(minLength: 4)
      Button("判断处", action: onJudgment).frame(minWidth: 52, minHeight: 44)
    }.font(.subheadline).tint(.orange).padding(.horizontal, 8).background(.regularMaterial)
  }
}
