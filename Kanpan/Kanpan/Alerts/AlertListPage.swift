import KanpanCore
import SwiftUI

/// 提醒总表（方案 2.3 的「管理」）。
///
/// 全 app 管提醒只有这一处：改条件在这儿，删在这儿，重新上膛也在这儿。
/// 图上那枚小铃铛只表示「这条线挂着提醒」，点它不弹任何菜单——同一个动作
/// 只留一个入口（`kanpan-one-entry-per-action`）。
///
/// 跨品种的一张表，不按品种分段：用户来这儿是为了「我一共挂了几条、哪条响了」，
/// 按品种切成几堆反而要翻。
struct AlertListPage: View {
  @ObservedObject var store: AlertStore
  /// 点一行：去那条线上。宿主接成深链（`DeepLink.drawing`）。
  var onOpen: (KanpanCore.Alert) -> Void
  /// 时间按用户在设置里选的那档时区写。
  var zone: TZOffset = .system

  @Environment(\.panelTheme) private var t

  var body: some View {
    PanelSheet(title: "提醒", subtitle: nil, asPage: false) {
      if store.all.isEmpty {
        empty
      } else {
        ForEach(store.sorted) { alert in
          AlertRow(alert: alert,
                   onOpen: { onOpen(alert) },
                   onRearm: { store.rearm(id: alert.id) },
                   onCondition: { store.setCondition($0, id: alert.id) },
                   onDelete: { store.remove(id: alert.id) },
                   zone: zone)
        }
      }
    }
    // 「这张表在不在」的记号。**`children: .contain` 那一句不能省**：光写
    // `accessibilityIdentifier` 会把这个名字往下盖到每个子元素上，表头那颗「‹」的
    // `panel.done` 在无障碍树里就成了 `alerts.page`（和 `DisplaySettingsSection`
    // 那一排配色卡踩过的是同一个坑）。后果是这张表**关不掉**——UI 用例换皮肤那一步
    // 一直盖着同一张表截图，sage 与 terra 两张 PNG 逐字节相同。`.contain` 让它只当
    // 一个容器，子元素各留各的名字。`AlertPromptBar` 那一条也是这么写的。
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("alerts.page")
  }

  private var empty: some View {
    VStack(spacing: 6) {
      Image(systemName: "bell").font(.system(size: 22, weight: .light)).foregroundStyle(t.ink3)
      Text("还没有提醒").font(PanelFont.name).foregroundStyle(t.ink3)
      Text("在图上画一条线，画完那一下就能加").font(PanelFont.meta).foregroundStyle(t.ink3)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 48)
  }
}

/// 一行：徽章 + 品种 + 线种 + 状态。左划删除。
private struct AlertRow: View {
  var alert: KanpanCore.Alert
  var onOpen: () -> Void
  var onRearm: () -> Void
  var onCondition: (KanpanCore.Alert.Condition) -> Void
  var onDelete: () -> Void
  var zone: TZOffset

  @Environment(\.panelTheme) private var t
  /// 左划出来的那一段。只认一根手指的水平位移，纵向滚动不受影响。
  @State private var offset: CGFloat = 0
  private static let revealed: CGFloat = -76

  var body: some View {
    ZStack(alignment: .trailing) {
      Button(role: .destructive) { withAnimation(.easeOut(duration: 0.16)) { offset = 0 }; onDelete() } label: {
        Text("删除")
          .font(PanelFont.seg)
          .foregroundStyle(.white)
          .frame(width: -Self.revealed, height: 52)
          .background(t.down)
      }
      .buttonStyle(.plain)
      .opacity(offset < -4 ? 1 : 0)

      row
        // 这层底是给左划用的（划开时下面不能透出「删除」那块红）。颜色必须和面板
        // 自己的底一样（`PanelSheet` 用的是 `raised`），拿 `t.app` 会在行与行以下
        // 的空白之间切出一道硬边——整屏要读成一块连续的材料。
        .background(t.raised)
        .offset(x: offset)
        .gesture(
          DragGesture(minimumDistance: 12)
            .onChanged { g in
              guard abs(g.translation.width) > abs(g.translation.height) else { return }
              offset = max(Self.revealed, min(0, g.translation.width + (offset < -4 ? Self.revealed : 0)))
            }
            .onEnded { g in
              withAnimation(.easeOut(duration: 0.16)) {
                offset = g.translation.width < -36 ? Self.revealed : 0
              }
            }
        )
    }
    .clipped()
  }

  private var row: some View {
    PanelRow(name: title, meta: meta, onTap: { offset == 0 ? onOpen() : close() }) {
      if alert.status == .fired {
        Button(action: { close(); onRearm() }) {
          Text("再次提醒")
            .font(PanelFont.seg)
            .foregroundStyle(t.badgeInk)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(t.amber))
        }
        .buttonStyle(.plain)
      } else {
        // 「触碰时 / 收盘穿过后」这个选择**只住在这一行**。画完线那一下不问，
        // 图上也没有第二处能改（方案 2.3）。
        Menu {
          ForEach([KanpanCore.Alert.Condition.touch, .close], id: \.self) { c in
            Button(c.title) { onCondition(c) }
          }
        } label: {
          HStack(spacing: 3) {
            Text(alert.condition.title).font(PanelFont.seg)
            VectorIcon.chevron(9, w: 1.7)
          }.foregroundStyle(t.amber)
        }
        .accessibilityIdentifier("alerts.condition")
      }
    }
    .overlay(alignment: .leading) {
      CoinBadge(base: KanpanCore.Alert.base(of: alert.symbol), size: 24)
        .padding(.leading, PanelMetrics.hPad - 30)
        .allowsHitTesting(false)
    }
    .padding(.leading, 30)
  }

  private func close() { withAnimation(.easeOut(duration: 0.16)) { offset = 0 } }

  private var title: String {
    let base = KanpanCore.Alert.base(of: alert.symbol)
    guard let name = alert.lineName else { return base }
    return base + " · " + name
  }

  private var meta: String {
    switch alert.status {
    case .fired:
      guard let at = alert.firedAt else { return "已触发" }
      return "已触发 · " + ReviewLabels.dayTime(ms: Int64(at), offsetMinutes: zone)
    case .paused: return "已暂停"
    case .active: return alert.condition == .touch ? "等它碰到" : "等它收盘穿过"
    }
  }
}
