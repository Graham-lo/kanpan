import KanpanCore
import SwiftUI

/// 设置 › 通用 里的两行：「按我的习惯自动调整」开关，开着时下面一行「已学到的」推进一页。
/// 没有说明文字（`kanpan-ui-no-lecturing`）。推页要外层 `NavigationStack`（设置整页有）。
struct HabitSettingsRows: View {
  var store: PrefsStore

  @Environment(\.habits) private var habits
  @Environment(\.panelTheme) private var t
  @State private var showLearned = false

  var body: some View {
    let on = store.prefs.habitLearning
    VStack(spacing: 0) {
      PanelRow(name: "按我的习惯自动调整") {
        PanelSwitch(isOn: on) {
          if let habits {
            habits.setEnabled(!on)
          } else {
            store.updateByHand { $0.habitLearning = !on; if on { $0.learnedDefaults = .empty } }
          }
        }
        .accessibilityIdentifier("settings.habits")
      }
      if on {
        PanelRow(name: "已学到的", onTap: { showLearned = true }) {
          HStack(spacing: Space.xs) {
            let count = LearnedItems(store.prefs.learnedDefaults).count
            if count > 0 { Text("\(count) 项").font(PanelFont.name).monospacedDigit() }
            VectorIcon.chevronRight(ControlMetrics.chevron)
          }
          .foregroundStyle(t.ink3)
        }
        .accessibilityIdentifier("settings.habits.learned")
      }
    }
    .navigationDestination(isPresented: $showLearned) { LearnedDefaultsPage(store: store) }
  }
}

/// 「已学到的」：四组只读列表（周期 · 价格轴 · 板块 · 波动提醒），每行「学到了什么 · 依据几次」；
/// 最下面一颗红字「清除已学到的」，确认一次。
struct LearnedDefaultsPage: View {
  var store: PrefsStore

  @Environment(\.habits) private var habits
  @Environment(\.panelTheme) private var t
  @State private var confirmClear = false

  var body: some View {
    let items = LearnedItems(store.prefs.learnedDefaults)
    ScrollView {
      VStack(spacing: 0) {
        if items.isEmpty {
          Text("暂无")
            .font(PanelFont.name)
            .foregroundStyle(t.ink3)
            .frame(maxWidth: .infinity, minHeight: Inset.rowMin * 2)
            .accessibilityIdentifier("habits.learned.empty")
        } else {
          ForEach(items.groups, id: \.title) { group in
            PanelGroupTitle(text: group.title)
            ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
              PanelRow(name: row.name, meta: "依据 \(row.count) 次", divider: index < group.rows.count - 1) {
                Text(row.value).font(PanelFont.name).foregroundStyle(t.ink2)
              }
              .accessibilityElement(children: .combine)
              .accessibilityIdentifier("habits.learned." + row.id)
            }
          }
        }
        clearButton(enabled: !items.isEmpty)
          .padding(.top, Space.xl)
      }
      .padding(.top, Space.xs)
      .padding(.bottom, Space.l)
    }
    .scrollBounceBehavior(.basedOnSize)
    .background(t.app.ignoresSafeArea())
    .navigationTitle("已学到的")
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("habits.learned.page")
    .confirmationDialog("清除已学到的？", isPresented: $confirmClear, titleVisibility: .visible) {
      Button("清除", role: .destructive) {
        if let habits { habits.clearLearned() } else { store.update { $0.learnedDefaults = .empty } }
        Haptics.warning()
      }
      .accessibilityIdentifier("habits.clear.confirm")
      Button("取消", role: .cancel) {}
    }
  }

  private func clearButton(enabled: Bool) -> some View {
    Button { confirmClear = true } label: {
      Text("清除已学到的")
        .font(TypeScale.bodyEmph)
        .foregroundStyle(enabled ? t.danger : PanelDisabled.ink(t))
        .frame(maxWidth: .infinity, minHeight: Hit.min)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .accessibilityIdentifier("habits.clear")
  }
}

/// 把结论摊成「已学到的」那页要画的行。纯值，单测可直接看。
struct LearnedItems {
  struct Row: Equatable {
    var id: String
    var name: String
    var value: String
    var count: Int
  }

  struct Group {
    var title: String
    var rows: [Row]
  }

  private(set) var groups: [Group] = []

  init(_ learned: LearnedDefaults) {
    func sorted<V>(_ table: [String: V], at: (V) -> Double) -> [(key: String, value: V)] {
      table.sorted { at($0.value) != at($1.value) ? at($0.value) > at($1.value) : $0.key < $1.key }
    }
    let intervals: [Row] = sorted(learned.intervals, at: \.at).compactMap { key, c in
      guard let iv = Interval(rawValue: c.v) else { return nil }
      return Row(id: "interval." + key, name: Alert.name(of: key), value: iv.shortLabel, count: c.n)
    }
    let axis: [Row] = HabitCategory.allCases.compactMap { category in
      guard let c = learned.priceAxis[category.rawValue], let mode = PriceMode(rawValue: c.v) else { return nil }
      return Row(id: "axis." + category.rawValue, name: category.title,
                 value: mode == .log ? "对数" : "线性", count: c.n)
    }
    let sector: [Row] = SectorMarket.allCases.compactMap { market in
      guard let c = learned.sectorWindow[market.rawValue], let w = SectorWindow(rawValue: c.v) else { return nil }
      return Row(id: "sector." + market.rawValue, name: market == .crypto ? "加密" : "美股",
                 value: SectorWindowChoice.title(w), count: c.n)
    }
    // 倍数回到 1 的不列：那就是没调。
    let moves: [Row] = sorted(learned.watchMove, at: \.at).compactMap { key, f in
      guard abs(f.v - 1) > 0.001 else { return nil }
      return Row(id: "move." + key, name: Alert.name(of: key), value: f.v < 1 ? "更灵敏" : "更迟钝", count: f.n)
    }
    for (title, rows) in [("周期", intervals), ("价格轴", axis), ("板块", sector), ("波动提醒", moves)] where !rows.isEmpty {
      groups.append(Group(title: title, rows: rows))
    }
  }

  var isEmpty: Bool { groups.isEmpty }
  var count: Int { groups.reduce(0) { $0 + $1.rows.count } }
}
