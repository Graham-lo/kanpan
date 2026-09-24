import SwiftUI
import KanpanCore
import UIKit
import ReviewDomain

public struct ReviewBook: View {
  @Bindable var feature: ReviewFeature
  @Environment(\.reviewTheme) private var t
  @State private var filter = ""
  @State private var savedOpen = false
  public init(feature: ReviewFeature) { self.feature = feature }
  public var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        // 顶部：战绩摘要卡 + 三颗筛选（审计 §2.4）。原来是「待办 / 记录 / 战绩」三段
        // 分段控件：战绩是和记录并列的第三页，人要先切过去才知道自己打得怎么样。
        // 现在战绩浓缩成一张摘要卡常驻顶上，点开才是完整的分组战绩；下面的列表只剩
        // 「看哪一部分」这一个维度。
        summary.padding(.horizontal).padding(.top, 8)
        chips.padding(.horizontal).padding(.vertical, 10)
        List {
          if feature.draft != nil {
            Button { feature.bookOpen = false; feature.onCapture() } label: {
              Label("继续未完成的记录", systemImage: "square.and.pencil")
            }
            .listRowBackground(t.app)
          }
          switch feature.tab {
          case "todo":
            group("待处理", records: filtered.filter { $0.needsAction })
            group("等答案", records: filtered.filter { $0.outcome == .waiting && !$0.needsAction })
          case "decided": group(nil, records: filtered.filter(\.isDecided))
          default: group(nil, records: filtered)
          }
          if feature.historyLoading { ProgressView().frame(maxWidth: .infinity).listRowBackground(t.app).listRowSeparator(.hidden) }
          if let error = feature.historyError {
            Text(error).foregroundStyle(t.ink3).listRowBackground(t.app)
            Button("重试") { Task { if feature.nextPage != nil && !feature.history.isEmpty { await feature.loadMoreHistory() } else { await feature.loadHistory(query: filter) } } }.listRowBackground(t.app)
          }
          if filtered.isEmpty && !feature.historyLoading && feature.historyError == nil {
            // 空状态一行字就够（§2G5）。只是一行字，不再是「记一笔」的第三个入口（审查 U6）：
            // 记一笔只留图表设置那一行和右上角的「+」，同一件事不摆三处。
            Text(feature.tab == "todo" ? "没有待判定的" : "还没有记录")
              .foregroundStyle(t.ink3)
              .frame(maxWidth: .infinity, minHeight: 44)
              .listRowBackground(t.app)
              .listRowSeparator(.hidden)
              .accessibilityIdentifier("review.empty")
          }
          // 无限下滑：最后一行一露头就接下一页，不再有「上一页 / 下一页」。
          if feature.isConnected && feature.nextPage != nil && feature.historyError == nil {
            Color.clear.frame(height: 1)
              .listRowBackground(t.app).listRowSeparator(.hidden)
              .onAppear { Task { await feature.loadMoreHistory() } }
              .accessibilityIdentifier("review.more")
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(t.app)
        .searchable(text: $filter, prompt: "搜品种或笔记")
      }
      // iPad 满屏时这一列封顶居中，不然筛选摊成 1300pt、行里的胜率被甩到一米外。
      .readableColumn()
      .background(t.app)
      .navigationTitle("复盘").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        // 左上角统一成「‹ 返回」，和看盘其余各页一致（2026-09-15）。
        ToolbarItem(placement: .cancellationAction) {
          Button { feature.bookOpen = false } label: { Label("返回", systemImage: "chevron.left") }
            .accessibilityIdentifier("review.back")
        }
        ToolbarItemGroup(placement: .primaryAction) {
          Button { feature.bookOpen = false; feature.onCapture() } label: { Image(systemName: "plus") }.accessibilityLabel("记一笔")
            .accessibilityIdentifier("review.capture")
          // 不常用的去处收在「…」里：现在只有「已存案例」一样。
          Menu {
            // Menu 里直接放 NavigationLink 在 iOS 26 上一点就崩；菜单只翻开关，推页交给下面的 destination。
            Button { savedOpen = true } label: { Label("已存案例", systemImage: "bookmark") }
              .accessibilityIdentifier("review.menu.saved")
          } label: { Image(systemName: "ellipsis.circle") }
            .accessibilityLabel("更多")
            .accessibilityIdentifier("review.menu")
        }
      }
      // 「已记下 · 查看」、图上点记号都先把 id 放进 `selectedRecord` 再开复盘本（§2F2），
      // 这一行负责把它翻到那条上。列表里正常点进去走的还是 `NavigationLink`，
      // 两条路互不干扰；退回列表时把 id 清掉，免得下次开复盘本又自己弹进去。
      .navigationDestination(isPresented: $savedOpen) { ReviewSavedMatchesView(feature: feature) }
      .navigationDestination(item: $feature.selectedRecord) { id in
        ReviewRecordView(feature: feature, id: id)
      }
      .refreshable { feature.synchronize(manual: true); await feature.loadHistory(query: filter) }
      .task(id: feature.tab) { await feature.loadHistory(query: filter) }
      .task(id: filter) { do { try await Task.sleep(for: .milliseconds(350)); await feature.loadHistory(query: filter) } catch {} }
      // 摘要卡底部那行「判定规则」来自战绩响应；已登录就顺手拉一次。
      .task { if feature.isConnected { await feature.loadStatistics() } }
    }
    .tint(t.accent)
  }
  /// 战绩摘要卡。数字是本机这份记录现算的（离线也有）；点开是服务端算的分组战绩。
  private var summary: some View {
    let live = feature.records.filter { !$0.voided }
    let right = live.filter { $0.outcome == .realized }.count
    let wrong = live.filter { $0.outcome == .unrealized }.count
    return NavigationLink { ReviewStatisticsView(feature: feature) } label: {
      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline) {
          Text("战绩").font(.headline).foregroundStyle(t.ink)
          Spacer()
          Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(t.ink3)
        }
        HStack(spacing: 18) {
          stat("记录", live.count); stat("判对", right); stat("判错", wrong)
        }
        Text("判定规则 \(feature.ruleVersion)").font(.caption2).foregroundStyle(t.ink3)
          .accessibilityIdentifier("review.ruleVersion")
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(t.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("review.summary")
  }
  private func stat(_ title: String, _ value: Int) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("\(value)").font(.title3.monospacedDigit().weight(.semibold)).foregroundStyle(t.ink)
      Text(title).font(.caption).foregroundStyle(t.ink3)
    }
  }
  /// 「全部 · 待判定 N · 已判定」。N 和底栏、顶栏的角标是同一个数（`pendingCount`）。
  private var chips: some View {
    HStack(spacing: 8) {
      chip("全部", tag: "all")
      chip(feature.pendingCount > 0 ? "待判定 \(feature.pendingCount)" : "待判定", tag: "todo")
      chip("已判定", tag: "decided")
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("review.chips")
  }
  private func chip(_ title: String, tag: String) -> some View {
    let on = feature.tab == tag
    return Button { feature.tab = tag } label: {
      Text(title).font(.subheadline.weight(on ? .semibold : .regular)).monospacedDigit()
        .foregroundStyle(on ? t.onAccent : t.ink2)
        .padding(.horizontal, 14).frame(minHeight: 32)
        .background(on ? t.accent : t.raised, in: Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("review.chip.\(tag)")
    .accessibilityAddTraits(on ? .isSelected : [])
  }
  private var filtered: [ReviewRecord] { feature.bookRecords.filter { filter.isEmpty || $0.draft.range.symbol.localizedCaseInsensitiveContains(filter) || $0.draft.text.localizedCaseInsensitiveContains(filter) } }
  @ViewBuilder private func group(_ title: String?, records: [ReviewRecord]) -> some View {
    if !records.isEmpty {
      Section {
        ForEach(records) { record in
          NavigationLink { ReviewRecordView(feature: feature, id: record.id) } label: { ReviewRecordRow(record: record, feature: feature) }
            .listRowBackground(t.app)
        }
      } header: { if let title { Text(title).foregroundStyle(t.ink3) } }
    }
  }
}
/// 摘要卡点开的完整战绩：按同一类判断分组，样本够了才给百分比。
struct ReviewStatisticsView: View {
  @Bindable var feature: ReviewFeature
  @Environment(\.reviewTheme) private var t
  var body: some View {
    List {
      if !feature.isConnected {
        // 没登录不是「出错」，是这一页还没轮到它：一句话 + 一颗「登录」，不给「重试」——
        // 重试一百次也还是没登录（§2G3）。
        Text("登录后可用").foregroundStyle(t.ink3).listRowBackground(t.app)
        Button("登录") { feature.bookOpen = false; feature.onLogin() }.listRowBackground(t.app)
          .accessibilityIdentifier("review.stats.login")
      } else if let error = feature.statisticsError {
        Text(error).foregroundStyle(t.ink3).listRowBackground(t.app)
      } else if feature.statistics.isEmpty {
        Text("暂无已判定样本").foregroundStyle(t.ink3).listRowBackground(t.app)
      }
      ForEach(feature.statistics) { group in
        HStack {
          VStack(alignment: .leading) {
            Text(group.title).foregroundStyle(t.ink)
            Text("\(group.total) 条有效记录").font(.caption).foregroundStyle(t.ink3)
          }
          Spacer()
          // 样本够了才写百分比，不够就写「样本不足」（审查 B-07 / B.2）。
          Text(group.rateText)
            .font(group.verdict == "insufficient" ? .subheadline : .title2.monospacedDigit())
            .foregroundStyle(group.verdict == "insufficient" ? t.ink3 : t.ink)
        }
        .listRowBackground(t.app)
      }
      if feature.isConnected {
        Text("判定规则 \(feature.ruleVersion)").font(.caption2).foregroundStyle(t.ink3)
          .listRowBackground(t.app).listRowSeparator(.hidden)
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(t.app)
    .readableColumn()
    .navigationTitle("战绩").navigationBarTitleDisplayMode(.inline)
    .task { await feature.loadStatistics() }
  }
}
struct ReviewRecordRow: View {
  let record: ReviewRecord
  /// 只为了写时刻：时区那一档在 `feature` 上（和图表同一口径，审查 B-08）。
  let feature: ReviewFeature
  @Environment(\.reviewTheme) private var t
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack {
        // 短名（§2G5）：`BTCUSDT` 里后面那四个字母每行都一样，认的是前半截。
        Text(record.draft.range.shortSymbol).fontWeight(.semibold).foregroundStyle(t.ink)
        Text(Interval.shortLabel(raw: record.draft.range.interval)).foregroundStyle(t.ink3)
        Spacer()
        Text(record.outcome.title).foregroundStyle(t.accent)
      }
      Text(record.draft.text.isEmpty ? "未写原话" : record.draft.text).lineLimit(2).foregroundStyle(record.draft.text.isEmpty ? t.ink3 : t.ink2)
      HStack {
        Text(record.draft.rule.direction.title); Text(record.draft.origin.title)
        // 「把握」填了就在这儿露一个小百分比（§2F4）：当时觉得有几成，事后回看才对得上
        // 「我是不是总在七成的时候栽」。没填就不占位置。
        if let confidence = record.draft.confidence { Text("把握 \(confidence)%").monospacedDigit() }
        // 记于什么时候。跟着图表那一档时区写（审查 B-08）：原来是
        // `Text(Date, style: .date)`，只有日期、而且认设备时区——图表在「交易所」档上，
        // 同一条记录在选区标签上写 1/6、在这儿写 1/5。
        Spacer(); Text(feature.dayTime(record.draft.created))
      }.font(.caption).foregroundStyle(t.ink3)
      // 同步状态不在这儿说了（§2G1）。「已存本机 · 待同步」「同步失败」是后台的事，
      // 每条记录下面挂一行，复盘本就变成了一张同步报表。同步真出问题只在设置的账号行
      // 说一次（见 `SettingsPanel.syncMeta`）。下面这一行说的是记录本身的性质，留着。
      if !record.eligible && record.draft.rule.direction != .observe {
        Text(record.draft.originalClaimed != nil || record.submitted.map { abs($0 - record.draft.created) > 60_000 } == true ? "补记" : "核验中")
          .font(.caption).foregroundStyle(t.ink3)
      }
    }.padding(.vertical, 7)
  }
}
public struct ReviewRecordView: View {
  @Bindable var feature: ReviewFeature
  let id: UUID
  @State private var note = ""
  @State private var nextTime = ""
  @State private var confirmVoid = false
  /// 两个输入框谁在打字。按下「保存草稿 / 完成复盘」就收键盘：这一段写完了，
  /// 键盘还挂着会盖住下面的「补图」「修订记录」，而且接着去相册挑图回来，
  /// 系统会把焦点还给输入框、键盘又弹起来盖住刚补的那张图（P3.7 模拟器上实测）。
  @FocusState private var typing: Bool
  /// 记这一笔的那一刻，图上是什么样（§4.3）。没有就整格不出现。
  @State private var shot: UIImage?
  @Environment(\.reviewTheme) private var t
  public init(feature: ReviewFeature, id: UUID) { self.feature = feature; self.id = id }
  private var record: ReviewRecord? { feature.record(id) }
  public var body: some View {
    Group {
      if let record {
        List {
          Section { ReviewRecordRow(record: record, feature: feature) }.listRowBackground(t.raised)
          // 这一条有一次上传永远成不了（审查 B-02）。内容一直在本机，人只需要拍一次板。
          if let conflict = record.conflict {
            Section("没能同步") {
              Text(conflict.reason).font(.subheadline).foregroundStyle(t.ink2)
              if conflict.retryable {
                Button("用我这份") { Task { await feature.resolveConflict(id, keepLocal: true) } }
                  .accessibilityIdentifier("review.conflict.keepLocal")
                Button("用云端那份") { Task { await feature.resolveConflict(id, keepLocal: false) } }
                  .accessibilityIdentifier("review.conflict.keepRemote")
              } else {
                // 服务端不收这份内容，重发多少次都一样：只剩「留在本机」一条路。
                Button("留在本机") { Task { await feature.resolveConflict(id, keepLocal: true) } }
                  .accessibilityIdentifier("review.conflict.keepLocal")
              }
            }.listRowBackground(t.raised)
          }
          // 结论在人写完复盘之后又变过，得让他自己再看一眼。
          if record.assessmentMoved {
            Section("结果有更新") {
              Text("这条的结果在你写完复盘之后变过，再看一眼").font(.subheadline).foregroundStyle(t.ink2)
            }.listRowBackground(t.raised)
          }
          if record.groupPending == true {
            Section("这次判断") {
              Text("与最近一笔是同一次判断吗？").font(.subheadline).foregroundStyle(t.ink2)
              Button("同一次判断") { feature.resolveGroup(id, sameEpisode: true) }
              Button("独立判断") { feature.resolveGroup(id, sameEpisode: false) }
            }.listRowBackground(t.raised)
          }
          if let shot {
            Section("当时那张图") {
              Image(uiImage: shot).resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }.listRowBackground(t.raised)
          }
          Section("当时") {
            LabeledContent("区间", value: "\(record.draft.range.bars) 根 · \(Interval.shortLabel(raw: record.draft.range.interval))")
            if let confidence = record.draft.confidence {
              LabeledContent("把握", value: "\(confidence)%")
            }
            if record.draft.rule.direction != .observe {
              LabeledContent("目标", value: price(record.draft.rule.target, record))
              LabeledContent("失效", value: price(record.draft.rule.invalidation, record))
              LabeledContent("判定", value: record.draft.rule.confirmation.title)
              // 到期常跨月跨年，写全（`yyyy-MM-dd HH:mm`），时区同上。
              LabeledContent("到期", value: feature.fullTime(record.draft.rule.expires))
            }
            Button("在图上重温") { feature.bookOpen = false; feature.onOpenChart(record) }
            Button("找相似") {
              feature.searchRecord = id
              // 范围跟着人走，存在 `feature.searchScope` 里（宿主再落到偏好）。
              // 这儿原来读的是本视图自己的一个 `@State searchScope`：**没有任何 UI
              // 写它**，恒为「市场历史」，而搜索层上那颗分段控件改的是另一份状态——
              // 用户选了「我的记录」，从这颗按钮发起的第一次搜索照样按「市场历史」找。
              // 死字段已经删掉，两处合成一处。
              feature.search(record.draft.range, cutoff: record.draft.created, scope: feature.searchScope)
            }
          }.listRowBackground(t.raised)
          if feature.isConnected { ReviewAttachmentsSection(feature: feature, record: record) }
          Section("市场的答案") { Text(record.outcome.title).foregroundStyle(t.ink); if let result = record.assessment { Text(result.reason).font(.caption).foregroundStyle(t.ink3) } }
            .listRowBackground(t.raised)
          Section("现在怎么看") { TextField("当时的判断，哪些成立", text: $note, axis: .vertical).lineLimit(3...8).focused($typing).accessibilityIdentifier("review.note") }
            .listRowBackground(t.raised)
          Section("下次怎么做") { TextField("同样的局面再来，改哪儿", text: $nextTime, axis: .vertical).lineLimit(2...6).focused($typing).accessibilityIdentifier("review.nextTime") }
            .listRowBackground(t.raised)
          Section {
            Button("保存草稿") { typing = false; feature.saveReflection(id, note: note, nextTime: nextTime, publish: false) }
            Button("完成复盘") { typing = false; feature.saveReflection(id, note: note, nextTime: nextTime, publish: true) }
          }.listRowBackground(t.raised)
          if !record.reflectionHistory.isEmpty {
            Section("历史复盘") { ForEach(Array(record.reflectionHistory.enumerated()), id: \.offset) { _, reflection in Text(reflection.note.isEmpty ? "未写内容" : reflection.note).foregroundStyle(t.ink2) } }
              .listRowBackground(t.raised)
          }
          // 每一版规则 / 判定 / 复盘的完整内容，按时间排；只读，不能把旧版覆盖回来。
          if feature.isConnected && record.serverId != nil {
            Section {
              NavigationLink { ReviewRevisionsView(feature: feature, record: record) } label: { Text("修订记录").foregroundStyle(t.ink) }
                .accessibilityIdentifier("review.revisions")
            }.listRowBackground(t.raised)
          }
          if !record.voided {
            // 警示走 `danger`，不是跌色——出厂红涨绿跌时 `t.down` 是绿的（见 `ReviewTheme.danger`）。
            Section { Button("作废记录") { confirmVoid = true }.foregroundStyle(t.danger) }
              .listRowBackground(t.raised)
          }
        }
        .scrollContentBackground(.hidden)
        .background(t.app)
        .onAppear { note = record.reflection.note; nextTime = record.reflection.nextTime }
        // 两个裁定版本只住在详情响应的外层，列表里没有；打开这一页顺手补一次。
        .task(id: id) { await feature.refreshDetail(id) }
        // 本机有就直接显示；换了台设备才去服务端拉那一张。
        .task(id: id) {
          shot = feature.shot(id).flatMap(UIImage.init(data:))
          guard shot == nil else { return }
          await feature.loadShot(id)
          shot = feature.shot(id).flatMap(UIImage.init(data:))
        }
          .onDisappear { if note != record.reflection.note || nextTime != record.reflection.nextTime { feature.saveReflection(id, note: note, nextTime: nextTime, publish: false) } }
          .sheet(isPresented: $feature.searchOpen) { ReviewSearchView(feature: feature, range: record.draft.range, cutoff: record.draft.created) }
      } else { ContentUnavailableView("记录暂不可用", systemImage: "book.closed") }
    }
    .readableColumn()
    .background(t.app)
    .tint(t.accent)
    .navigationTitle("记录详情").navigationBarTitleDisplayMode(.inline)
      .confirmationDialog("作废后保留内容，退出战绩统计", isPresented: $confirmVoid) {
        Button("作废记录", role: .destructive) { feature.voidRecord(id) }
      }
  }
  /// 一口价的小数位由品种自己说（`SymbolInfo.priceDecimals`，宿主注入给
  /// `feature.priceDecimals`），和顶栏、K 线价格轴、图上的目标线一致（审查 B-07）。
  /// 原来是「最多 8 位、能省就省」：同一张记录里目标写 `76800`、失效写 `76812.5`。
  private func price(_ value: Double, _ record: ReviewRecord) -> String {
    feature.price(value, symbol: record.draft.range.key)
  }
}
