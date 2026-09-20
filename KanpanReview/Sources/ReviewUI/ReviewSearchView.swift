import SwiftUI
import ReviewDomain

public struct ReviewSearchView: View {
  @Bindable var feature: ReviewFeature
  public var range: ReviewRange
  public var cutoff: Int64
  @Environment(\.reviewTheme) private var t
  @Environment(\.dismiss) private var dismiss
  public init(feature: ReviewFeature, range: ReviewRange, cutoff: Int64) { self.feature = feature; self.range = range; self.cutoff = cutoff }
  public var body: some View {
    NavigationStack {
      VStack {
        Picker("范围", selection: $feature.searchScope) { Text("市场历史").tag("history"); Text("我的记录").tag("private") }.pickerStyle(.segmented).padding()
        if feature.searching && feature.matches.isEmpty {
          VStack(spacing: 16) { ProgressView(feature.searchProgress); Button("取消") { feature.cancelSearch(); dismiss() } }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        else if !feature.isConnected {
          // 没登录就一句「登录后可用」+ 一颗「登录」，不给「重试」（§2G3）——
          // 这件事不是失败，是还没轮到它，重试多少次结果都一样。
          ContentUnavailableView { Label("登录后可用", systemImage: "magnifyingglass") } actions: {
            Button("登录") { dismiss(); feature.onLogin() }
              .accessibilityIdentifier("review.search.login")
          }
        }
        else if let error = feature.searchError {
          ContentUnavailableView { Label(error, systemImage: "magnifyingglass") } actions: {
            Button("重试") { feature.search(range, cutoff: cutoff, scope: feature.searchScope) }
          }
        } else if feature.matches.isEmpty { ContentUnavailableView("没有很像的区间", systemImage: "magnifyingglass") }
        else {
          List {
            if feature.partialSearch { Text("部分行情暂缺，已列出完成比对的结果").font(.caption).foregroundStyle(t.ink3) }
            ForEach(feature.matches) { match in
            Button {
              dismiss(); feature.bookOpen = false; feature.captureOpen = false
              feature.onOpenMatch(match, cutoff)
            } label: {
              HStack {
                VStack(alignment: .leading, spacing: 5) {
                  Text(match.range.symbol + " · " + match.range.interval).fontWeight(.medium).foregroundStyle(t.ink)
                  // 相似区间大多在几个月甚至几年前，所以写全年份；时区跟着图表那一档走
                  // （审查 B-08）。原来是 `Text(Date, style: .date)`：只有日期、认设备时区，
                  // 点进去在图上看到的那一段和这一行写的日子能差一天。
                  Text(feature.fullTime(match.range.start)).font(.caption).foregroundStyle(t.ink3)
                  Text("\(match.range.bars) 根").font(.caption).foregroundStyle(t.ink3)
                }
                // 「相似 0.87」，不是「87%」（审查 B.4）。这个数是两段行情的路径差经
                // `exp(-6·cost)` 映射出来的分，没有概率含义；可它和战绩页上的胜率长得
                // 一模一样，同一个 app 里两个百分号，人会把它当成「87% 会涨」。
                Spacer(); Text("相似 " + match.scoreText).monospacedDigit().foregroundStyle(t.ink2)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(t.ink3)
              }.padding(.vertical, 5)
            }.foregroundStyle(t.ink)
              .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button { Task { await feature.saveMatch(match) } } label: { Label(feature.savedMatchIDs.contains(match.id) ? "已保存" : "保存", systemImage: "bookmark") }.tint(t.accent)
              }
            }
            if feature.searchNext != nil { Button("更多结果") { Task { await feature.loadMoreMatches() } }.disabled(feature.searching) }
          }
          .listStyle(.plain)
          .scrollContentBackground(.hidden)
          .background(t.app)
        }
      }
      .background(t.app)
      .navigationTitle("找相似").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button { dismiss() } label: { Label("返回", systemImage: "chevron.left") }
              .accessibilityIdentifier("review.search.back")
          }
        }
        .onChange(of: feature.searchScope) { _, value in feature.search(range, cutoff: cutoff, scope: value) }
        .onDisappear { feature.cancelSearch() }
    }
    .tint(t.accent)
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
  @Environment(\.reviewTheme) private var t
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
    }
    .font(.subheadline)
    .tint(t.accent)
    .padding(.horizontal, 8)
    .background(t.raised)
  }
}
