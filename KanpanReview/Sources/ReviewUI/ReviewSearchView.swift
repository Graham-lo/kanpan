import SwiftUI
import KanpanCore
import ReviewDomain

public struct ReviewSearchView: View {
  @Bindable var feature: ReviewFeature
  public var range: ReviewRange
  public var cutoff: Int64
  @Environment(\.reviewTheme) private var t
  @Environment(\.dismiss) private var dismiss
  /// 当前左划开着的是哪一行（同一时刻只开一行，见 app 的 `SwipeToDelete`）。
  @State private var openSwipe: String?
  public init(feature: ReviewFeature, range: ReviewRange, cutoff: Int64) { self.feature = feature; self.range = range; self.cutoff = cutoff }
  public var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        ReviewSegment(options: [("市场历史", "history"), ("我的记录", "private")],
                      selection: $feature.searchScope, id: "review.search.scope")
          .reviewPageInset().padding(.vertical, ReviewSpace.m)
        if feature.searching && feature.matches.isEmpty {
          VStack(spacing: ReviewSpace.l) {
            ProgressView(feature.searchProgress).font(ReviewType.body).foregroundStyle(t.ink2)
            Button("取消") { feature.cancelSearch(); dismiss() }.font(ReviewType.bodyEmph).hitTarget()
          }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        else if !feature.isConnected {
          // 没登录就一句「登录后可用」+ 一颗「登录」，不给「重试」（§2G3）——
          // 这件事不是失败，是还没轮到它，重试多少次结果都一样。
          // 不配放大镜图标（UI 整改 P3）：放大镜说的是「没找到」，这儿是「还没登录」。
          empty("登录后可用") {
            Button("登录") { dismiss(); feature.onLogin() }
              .buttonStyle(ReviewPrimaryButtonStyle())
              .accessibilityIdentifier("review.search.login")
          }
        }
        else if let error = feature.searchError {
          empty(error, tone: t.danger) {
            Button("重试") { feature.search(range, cutoff: cutoff, scope: feature.searchScope) }
              .buttonStyle(ReviewPrimaryButtonStyle())
          }
        } else if feature.matches.isEmpty { empty("没有很像的区间") { EmptyView() } }
        else {
          List {
            if feature.partialSearch {
              Text("部分行情暂缺，已列出完成比对的结果").font(ReviewType.caption).foregroundStyle(t.ink3)
                .listRowBackground(t.app)
            }
            ForEach(feature.matches) { match in
              let saved = feature.savedMatchIDs.contains(match.id)
              // 左划「保存」走 app 那份唯一的左划实现（砖底强调色、字跟皮肤走），见 `ReviewSwipe`。
              ReviewSwipe(id: "\(match.id)", open: $openSwipe,
                          trailing: [ReviewSwipeAction(id: "review.save", title: saved ? "已保存" : "保存") {
                            Task { await feature.saveMatch(match) }
                          }],
                          fullSwipe: false) { swipe in
                Button {
                  if swipe.isOpen { swipe.close(); return }
                  dismiss(); feature.bookOpen = false; feature.captureOpen = false
                  feature.onOpenMatch(match, cutoff)
                } label: {
                  ReviewMatchRow(feature: feature, match: match)
                }
                .buttonStyle(.plain)
                .reviewPageInset()
              }
              .listRowInsets(EdgeInsets())
              .listRowBackground(t.app)
            }
            if feature.searchNext != nil {
              Button("更多结果") { Task { await feature.loadMoreMatches() } }
                .font(ReviewType.bodyEmph).frame(minHeight: ReviewControl.hit)
                .disabled(feature.searching)
                .listRowBackground(t.app)
            }
          }
          .listStyle(.plain)
          .scrollContentBackground(.hidden)
          .background(t.app)
        }
      }
      .background(t.app)
      .navigationTitle("找相似").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          // 系统关闭钮（UI 整改 P3，同提醒总表）：这是一张盖上来的表，关掉回到取景卡 / 详情。
          ToolbarItem(placement: .topBarLeading) {
            Button(role: .close) { dismiss() }
              .accessibilityIdentifier("review.search.back")
          }
        }
        .onChange(of: feature.searchScope) { _, value in feature.search(range, cutoff: cutoff, scope: value) }
        .onDisappear { feature.cancelSearch() }
    }
    .tint(t.accent)
  }
  /// 空状态：一句 15 的话，下面至多一颗主按钮。不配图标——这一页的空状态没有一个是「图」
  /// 能说清楚的（没登录、出错、没命中），放大镜只会让人以为还在搜。
  private func empty<Actions: View>(_ text: String, tone: Color? = nil,
                                    @ViewBuilder actions: () -> Actions) -> some View {
    VStack(spacing: ReviewSpace.l) {
      Text(text).font(ReviewType.body).foregroundStyle(tone ?? t.ink2).multilineTextAlignment(.center)
      actions()
    }
    .reviewPageInset()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// 「找相似」结果与「已存案例」共用的一行：品种 · 周期、起点与根数，右边「相似 0.87」。
struct ReviewMatchRow: View {
  let feature: ReviewFeature
  let match: ReviewMatch
  @Environment(\.reviewTheme) private var t
  var body: some View {
    HStack(spacing: ReviewSpace.s) {
      VStack(alignment: .leading, spacing: ReviewSpace.xxs) {
        Text(match.range.shortSymbol + " · " + Interval.shortLabel(raw: match.range.interval))
          .font(ReviewType.bodyEmph).foregroundStyle(t.ink)
        // 相似区间大多在几个月甚至几年前，所以写全年份；时区跟着图表那一档走
        // （审查 B-08）。原来是 `Text(Date, style: .date)`：只有日期、认设备时区，
        // 点进去在图上看到的那一段和这一行写的日子能差一天。
        Text(feature.fullTime(match.range.start)).font(ReviewType.caption).monospacedDigit().foregroundStyle(t.ink3)
        Text("\(match.range.bars) 根").font(ReviewType.caption).foregroundStyle(t.ink3)
      }
      // 「相似 0.87」，不是「87%」（审查 B.4）。这个数是两段行情的路径差经
      // `exp(-6·cost)` 映射出来的分，没有概率含义；可它和战绩页上的胜率长得
      // 一模一样，同一个 app 里两个百分号，人会把它当成「87% 会涨」。
      Spacer(); Text("相似 " + match.scoreText).font(ReviewType.body).monospacedDigit().foregroundStyle(t.ink2)
      Image(systemName: "chevron.right").font(.system(size: ReviewControl.chevron, weight: .semibold)).foregroundStyle(t.ink3)
    }
    .padding(.vertical, ReviewSpace.s)
    .frame(minHeight: ReviewControl.hit)
    .contentShape(Rectangle())
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
      Button("退出", action: onExit).hitTarget()
      Spacer(minLength: ReviewSpace.xs)
      Button { onStep(-1) } label: { Image(systemName: "backward.end.fill").frame(width: ReviewControl.hit, height: ReviewControl.hit) }.accessibilityLabel("前一根")
      Button(action: onPlay) { Image(systemName: playing ? "pause.fill" : "play.fill").frame(width: ReviewControl.hit, height: ReviewControl.hit) }.accessibilityLabel(playing ? "暂停" : "播放")
      Button { onStep(1) } label: { Image(systemName: "forward.end.fill").frame(width: ReviewControl.hit, height: ReviewControl.hit) }.accessibilityLabel("后一根")
      Button("\(speed)×", action: onSpeed).frame(width: ReviewControl.hit, height: ReviewControl.hit)
      Spacer(minLength: ReviewSpace.xs)
      Button("判断处", action: onJudgment).padding(.horizontal, ReviewSpace.xs).hitTarget()
    }
    .font(ReviewType.body)
    .tint(t.accent)
    .padding(.horizontal, ReviewSpace.s)
    // 不再垫自己的底（UI 整改 P3）：原来一条 `raised` 横在图下面，和页面底拼出一道硬边
    // （kanpan-no-seams-one-continuous-surface）。按钮直接落在页面那块材料上。
  }
}
