import SwiftUI
import KanpanCore

/// 四个面板共用的零件：半屏壳、行、分段、开关、分组标题、步进器、脚注、toast。
/// 尺寸与字号全部照原型 `style.css`，改这里就是改四个面板。

// MARK: - 壳

/// 半屏面板的外壳：「‹」 + 标题 + 副标题 + 可滚动的正文（原型 `.sheet / .sheeth / .sheetb`）。
///
/// 左上角那颗「‹」不是装饰：面板被拉到全屏之后，下拉指示条还在，但整页占满屏幕，
/// 「往下拽」这件事在一个全是滚动内容的页面上不成立——实测在图表面板里拉到全屏就出不来了，
/// 只能杀进程。所以每个面板都常驻一个明确的出口。
///
/// 它原来是标题右边的文字「完成」。用户 2026-09-15 指出「很多页面左上方都没有返回按钮，
/// 你看 aicoin」——手机 AICoin 的每一层都在左上角摆一颗「‹」，出口永远在同一个位置，
/// 不用每进一页先找一遍。所以这里把出口搬到左上角，并和自选页（`favorites.back`）、
/// 品种页（`symbols.back`）统一成同一个手势。标识符仍叫 `panel.done`，UI 测试沿用。
struct PanelSheet<Content: View>: View {
  var title: String
  var subtitle: String?
  @ViewBuilder var content: () -> Content

  @Environment(\.panelTheme) private var t
  /// 横屏侧栏没有系统 `dismiss`，走主界面递进来的这一条（见 `PanelCloser`）。
  @Environment(\.panelDismiss) private var sideDismiss
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center, spacing: 6) {
        Button { PanelCloser(side: sideDismiss, sheet: dismiss)() } label: {
          Image(systemName: "chevron.left")
            .font(.system(size: 17, weight: .semibold))
            // 描边图标的点击区默认只有笔画本身，补一块 32×32 的矩形，画面不动。
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .foregroundStyle(t.amber)
        .buttonStyle(.plain)
        .accessibilityLabel("返回")
        .accessibilityIdentifier("panel.done")

        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(title).font(PanelFont.title).foregroundStyle(t.ink)
            .accessibilityIdentifier("panel.header")
          if let subtitle {
            Text(subtitle).font(PanelFont.sub).foregroundStyle(t.ink3)
          }
        }
        Spacer(minLength: 0)
      }
      // 图标自带 7pt 视觉留白，左边对齐到和正文一样的 `hPad`。
      .padding(.leading, PanelMetrics.hPad - 7)
      .padding(.trailing, PanelMetrics.hPad)
      .padding(.top, 13)
      .padding(.bottom, 10)
      .overlay(alignment: .bottom) { Rectangle().fill(t.line).frame(height: 1) }

      ScrollView {
        VStack(spacing: 0) { content() }
          .padding(.top, 4)
          .padding(.bottom, 10)
      }
      .scrollBounceBehavior(.basedOnSize)
      .accessibilityIdentifier("panel.content")
    }
    .background(t.raised)
    .accessibilityLabel(title)
  }
}

// MARK: - 行

/// 一行：左边名字（可带一行灰字），右边随便塞个控件。底下一条发丝线。
struct PanelRow<Trailing: View>: View {
  var name: String
  var meta: String?
  /// 名字前面的小色块（指标面板用）。
  var swatch: Color?
  /// 当前项用琥珀色标出来（周期面板用）。
  var highlighted: Bool = false
  var divider: Bool = true
  var onTap: (() -> Void)?
  /// 长按（§10.6 的「长按加入 / 移出常用行」）。
  var onLongPress: (() -> Void)?
  @ViewBuilder var trailing: () -> Trailing

  @Environment(\.panelTheme) private var t

  var body: some View {
    let row = HStack(spacing: PanelMetrics.rowGap) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          if let swatch {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
              .fill(swatch)
              .frame(width: 9, height: 9)
          }
          Text(name)
            .font(PanelFont.name)
            .foregroundStyle(highlighted ? t.amber : t.ink)
        }
        if let meta {
          Text(meta).font(PanelFont.meta).foregroundStyle(t.ink3)
        }
      }
      Spacer(minLength: 0)
      trailing()
    }
    .padding(.horizontal, PanelMetrics.hPad)
    .padding(.vertical, PanelMetrics.vPad)
    .contentShape(Rectangle())
    .overlay(alignment: .bottom) {
      if divider { Rectangle().fill(t.hair).frame(height: 1) }
    }

    if let onTap {
      Button(action: onTap) { row }
        .buttonStyle(.plain)
        .modifier(LongPress(action: onLongPress))
    } else {
      row.modifier(LongPress(action: onLongPress))
    }
  }
}

extension PanelRow where Trailing == EmptyView {
  init(name: String, meta: String? = nil, swatch: Color? = nil,
       highlighted: Bool = false, divider: Bool = true,
       onTap: (() -> Void)? = nil, onLongPress: (() -> Void)? = nil) {
    self.init(name: name, meta: meta, swatch: swatch, highlighted: highlighted,
              divider: divider, onTap: onTap, onLongPress: onLongPress,
              trailing: { EmptyView() })
  }
}

/// 有就挂上，没有就什么都不做——省得每处写一遍 `if let`。
private struct LongPress: ViewModifier {
  var action: (() -> Void)?

  func body(content: Content) -> some View {
    if let action {
      content.onLongPressGesture(minimumDuration: 0.32, perform: action)
    } else {
      content
    }
  }
}

// MARK: - 分段

/// 原型 `.seg`：两到三格，选中那格底色抬起来。
struct PanelSegment<Value: Hashable>: View {
  var options: [(String, Value)]
  var selection: Value
  var pick: (Value) -> Void

  @Environment(\.panelTheme) private var t

  var body: some View {
    HStack(spacing: 2) {
      ForEach(options, id: \.1) { text, value in
        let on = value == selection
        Button { pick(value) } label: {
          Text(text)
            .font(PanelFont.seg)
            .foregroundStyle(on ? t.ink : t.ink2)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
              if on {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                  .fill(t.segOn)
                  .shadow(color: .black.opacity(0.09), radius: 1, y: 1)
              }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
      }
    }
    .padding(2)
    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.raised2))
  }
}

// MARK: - 开关

/// 原型 `.sw`：44 × 26，开着是涨色。不用系统 `Toggle`，因为开着的颜色要跟涨跌对调走。
struct PanelSwitch: View {
  var isOn: Bool
  var toggle: () -> Void

  @Environment(\.panelTheme) private var t

  var body: some View {
    Button(action: toggle) {
      ZStack(alignment: isOn ? .trailing : .leading) {
        Capsule().fill(isOn ? t.switchOn : t.switchOff)
        Circle()
          .fill(isOn ? t.up : t.switchKnob)
          .frame(width: 20, height: 20)
          .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
          .padding(3)
      }
      .frame(width: 44, height: 26)
      .animation(.easeOut(duration: 0.18), value: isOn)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(.isButton)
    .accessibilityValue(isOn ? "开" : "关")
  }
}

// MARK: - 分组标题 / 脚注

/// 原型 `.groupt`：小号、加字距的灰标题。
struct PanelGroupTitle: View {
  var text: String
  @Environment(\.panelTheme) private var t

  var body: some View {
    Text(text)
      .font(PanelFont.group)
      .tracking(1)
      .foregroundStyle(t.ink3)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, PanelMetrics.hPad)
      .padding(.top, 14)
      .padding(.bottom, 6)
  }
}

/// 原型 `.note`：面板末尾那段解释。`**粗**` 会加深一档（对应原型的 `<b>`）。
struct PanelNote: View {
  var markdown: String
  @Environment(\.panelTheme) private var t

  var body: some View {
    Text(.init(markdown))
      .font(PanelFont.note)
      .lineSpacing(5)
      .foregroundStyle(t.ink3)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, PanelMetrics.hPad)
      .padding(.top, 10)
      .padding(.bottom, 2)
  }
}

// MARK: - 步进器

/// 原型 `.step`：`− 名字 12 +`。夹在 `IndicatorParamRule.range` 里，按不出非法值（A6.5）。
struct PanelStepper: View {
  var label: String
  var value: Int
  var bump: (Int) -> Void

  @Environment(\.panelTheme) private var t

  var body: some View {
    HStack(spacing: 0) {
      key("−") { bump(-1) }
        .disabled(value <= IndicatorParamRule.range.lowerBound)
      Text(label.isEmpty ? "\(value)" : "\(label) \(value)")
        .font(PanelFont.number)
        .foregroundStyle(t.ink2)
        .frame(minWidth: 34)
        .padding(.horizontal, 2)
        .padding(.vertical, 5)
        .contentTransition(.numericText())
      key("+") { bump(1) }
        .disabled(value >= IndicatorParamRule.range.upperBound)
    }
    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(t.line, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(label.isEmpty ? "参数" : label)
    .accessibilityValue("\(value)")
  }

  private func key(_ glyph: String, _ act: @escaping () -> Void) -> some View {
    Button(action: act) {
      Text(glyph)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(t.ink2)
        .frame(width: 24, height: 22)
        .background(t.raised2)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - toast

/// 原型 `toast()`：被拒绝的动作说一句就走（副图开满三个、参数越界、域名不对）。
struct PanelToast: View {
  var text: String
  @Environment(\.panelTheme) private var t

  var body: some View {
    Text(text)
      .font(PanelFont.name)
      .foregroundStyle(Color(hex: t.chart.crossInk))
      .padding(.horizontal, 14)
      .padding(.vertical, 9)
      .background(Capsule().fill(Color(hex: t.chart.crossBg)))
      .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
      .transition(.move(edge: .bottom).combined(with: .opacity))
      .accessibilityAddTraits(.isStaticText)
  }
}

/// 把 `PrefsStore.notice` 挂成一条会自己消失的 toast。
struct PanelToastLayer: ViewModifier {
  var store: PrefsStore

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .bottom) {
        if let notice = store.notice {
          PanelToast(text: notice)
            .padding(.bottom, 28)
            .task(id: notice) {
              try? await Task.sleep(for: .seconds(1.8))
              store.clearNotice()
            }
        }
      }
      .animation(.easeOut(duration: 0.18), value: store.notice)
  }
}

extension View {
  func panelToast(_ store: PrefsStore) -> some View { modifier(PanelToastLayer(store: store)) }
}
