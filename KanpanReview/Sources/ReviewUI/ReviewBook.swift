import SwiftUI
import UIKit
import ReviewDomain

public struct ReviewBook: View {
  @Bindable var feature: ReviewFeature
  @Environment(\.reviewTheme) private var t
  @State private var filter = ""
  public init(feature: ReviewFeature) { self.feature = feature }
  public var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        Picker("复盘", selection: $feature.tab) {
          Text("待办").tag("todo"); Text("记录").tag("records"); Text("战绩").tag("stats")
        }.pickerStyle(.segmented).padding()
        if feature.tab == "stats" { statistics }
        else {
          List {
            if feature.draft != nil {
              Button { feature.bookOpen = false; feature.onCapture() } label: {
                Label("继续未完成的记录", systemImage: "square.and.pencil")
              }
              .listRowBackground(t.app)
            }
            if feature.tab == "todo" {
              group("待处理", records: filtered.filter { $0.needsAction })
              group("等答案", records: filtered.filter { $0.outcome == .waiting && !$0.needsAction })
            } else { group(nil, records: filtered) }
            if feature.historyLoading { ProgressView().listRowBackground(t.app) }
            if let error = feature.historyError {
              Text(error).foregroundStyle(t.ink3).listRowBackground(t.app)
              Button("重试") { Task { await feature.loadHistory(query: filter, page: feature.historyPage) } }.listRowBackground(t.app)
            }
            if filtered.isEmpty && !feature.historyLoading && feature.historyError == nil {
              // 空状态一行字就够（§2G5）。原来是一整块 `ContentUnavailableView`：一个大图标、
              // 一行标题、一行说明，占掉大半屏来说「这儿是空的」——空本身不需要这么大声。
              Button { feature.bookOpen = false; feature.onCapture() } label: {
                Text(feature.tab == "todo" ? "没有待办 · 记一笔" : "还没有记录 · 记一笔")
                  .foregroundStyle(t.ink3)
                  .frame(maxWidth: .infinity, minHeight: 44)
              }
              .listRowBackground(t.app)
              .listRowSeparator(.hidden)
              .accessibilityIdentifier("review.empty")
            }
            if feature.isConnected && (feature.historyPage > 0 || feature.nextPage != nil) {
              HStack {
                Button("上一页") { Task { await feature.loadHistory(query: filter, page: feature.historyPage - 1) } }.disabled(feature.historyPage == 0 || feature.historyLoading)
                Spacer(); Text("\(feature.historyPage + 1)").monospacedDigit(); Spacer()
                Button("下一页") { Task { await feature.loadHistory(query: filter, page: feature.historyPage + 1) } }.disabled(feature.nextPage == nil || feature.historyLoading)
              }.buttonStyle(.borderless).frame(minHeight: 44).listRowBackground(t.app)
            }
          }
          .listStyle(.plain)
          .scrollContentBackground(.hidden)
          .background(t.app)
          .searchable(text: $filter, prompt: "品种或原话")
        }
      }
      // iPad 满屏时这一列封顶居中，不然分段控件摊成 1300pt、行里的胜率被甩到一米外。
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
        }
      }
      // 「已记下 · 查看」那颗按钮先把 id 放进 `selectedRecord` 再开复盘本（§2F2），
      // 这一行负责把它翻到那条上。列表里正常点进去走的还是 `NavigationLink`，
      // 两条路互不干扰；退回列表时把 id 清掉，免得下次开复盘本又自己弹进去。
      .navigationDestination(item: $feature.selectedRecord) { id in
        ReviewRecordView(feature: feature, id: id)
      }
      .refreshable { feature.synchronize(manual: true); await feature.loadHistory(query: filter) }
      .task(id: feature.tab) { if feature.tab == "stats" { await feature.loadStatistics() } else { await feature.loadHistory(query: filter) } }
      .task(id: filter) { do { try await Task.sleep(for: .milliseconds(350)); if feature.tab != "stats" { await feature.loadHistory(query: filter) } } catch {} }
    }
    .tint(t.accent)
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
  private var statistics: some View {
    List {
      if !feature.isConnected {
        // 没登录不是「出错」，是这一页还没轮到它：一句话 + 一颗「登录」，不给「重试」——
        // 重试一百次也还是没登录（§2G3）。
        Text("登录后可用").foregroundStyle(t.ink3).listRowBackground(t.app)
        Button("登录") { feature.onLogin() }.listRowBackground(t.app)
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
          // 一笔判错算出来的那个 0% 不是战绩，是噪声；把它排版成一个大号百分数，
          // 人会真的照着它改自己的做法。够不够由服务端的 `verdict_status` 说了算，
          // 那个数它一直在算，只是以前客户端没接。
          Text(group.rateText)
            .font(group.verdict == "insufficient" ? .subheadline : .title2.monospacedDigit())
            .foregroundStyle(group.verdict == "insufficient" ? t.ink3 : t.ink)
        }
        .listRowBackground(t.app)
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(t.app)
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
        Text(record.draft.range.interval).foregroundStyle(t.ink3)
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
            LabeledContent("区间", value: "\(record.draft.range.bars) 根 · \(record.draft.range.interval)")
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
          Section("市场的答案") { Text(record.outcome.title).foregroundStyle(t.ink); if let result = record.assessment { Text(result.reason).font(.caption).foregroundStyle(t.ink3) } }
            .listRowBackground(t.raised)
          Section("现在怎么看") { TextField("当时的判断，哪些成立", text: $note, axis: .vertical).lineLimit(3...8) }
            .listRowBackground(t.raised)
          Section("下次怎么做") { TextField("同样的局面再来，改哪儿", text: $nextTime, axis: .vertical).lineLimit(2...6) }
            .listRowBackground(t.raised)
          Section {
            Button("保存草稿") { feature.saveReflection(id, note: note, nextTime: nextTime, publish: false) }
            Button("完成复盘") { feature.saveReflection(id, note: note, nextTime: nextTime, publish: true) }
          }.listRowBackground(t.raised)
          if !record.reflectionHistory.isEmpty {
            Section("历史复盘") { ForEach(Array(record.reflectionHistory.enumerated()), id: \.offset) { _, reflection in Text(reflection.note.isEmpty ? "未写内容" : reflection.note).foregroundStyle(t.ink2) } }
              .listRowBackground(t.raised)
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
  /// 一口价的小数位由品种自己说（`SymbolInfo.pricePrecision`，宿主注入给
  /// `feature.priceDecimals`），和顶栏、K 线价格轴、图上的目标线一致（审查 B-07）。
  /// 原来是「最多 8 位、能省就省」：同一张记录里目标写 `76800`、失效写 `76812.5`。
  private func price(_ value: Double, _ record: ReviewRecord) -> String {
    feature.price(value, symbol: record.draft.range.symbol)
  }
}
