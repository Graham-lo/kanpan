import KanpanChart
import KanpanCore
import SwiftUI
import UIKit

/// 画线栏：上排是「当前状态相关」的动作，下排是工具。
///
/// 两排都靠一个横向 `ScrollView` 放可变数量的按钮，右端再钉几个固定按钮。这里有个坑：
/// 固定按钮原来是直接跟在 ScrollView 后面排的，`撤销/重做/完成` 三个 44pt 加起来 132pt，
/// 实测最后一个工具 chip（「测量」）会整块压在「撤销」底下，`hittable=false`——
/// 想点测量，点到的是撤销，用户刚画的那条线没了。所以：
///
/// 1. 滚动区显式 `.frame(maxWidth: .infinity)` + `.clipped()`，不许它把内容漏到固定区底下；
/// 2. 撤销/重做挪到上排右端，下排右端只剩「完成」，工具排的固定占用从 132pt 降到 44pt；
/// 3. 固定区左边加一条分隔线，让「这边是滚动的、那边是不动的」一眼看得出来。
///
/// 选中一条线之后的那几个动作**不在这根条上**，见 `DrawingSelectionBar`。
struct DrawingBar: View {
  @ObservedObject var controller: DrawingController
  @Environment(\.panelTheme) private var theme
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            action(controller.preferences.magnet ? "吸附开" : "吸附关", "arrow.up.and.down.and.arrow.left.and.right", "draw.magnet.quick") { controller.toggleMagnet() }
            action(controller.preferences.continuous ? "连续开" : "连续关", "repeat", "draw.continuous.quick") { controller.toggleContinuous() }
            action("管理", "square.stack", "draw.objects.quick") { controller.panel = .objects }
          }.padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .clipped()
        divider
        icon("arrow.uturn.backward", "撤销", "draw.undo", enabled: controller.canUndo) { controller.undo() }
        icon("arrow.uturn.forward", "重做", "draw.redo", enabled: controller.canRedo) { controller.redo() }
      }
      HStack(spacing: 0) {
        Button { controller.panel = .tools } label: {
          Image(systemName: "square.grid.2x2").frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("全部画线工具").accessibilityIdentifier("draw.tools")
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            ForEach(controller.preferences.favorites) { kind in
              Button(kind.shortTitle) { controller.pick(kind) }
                .padding(.horizontal, 10).frame(minHeight: 44)
                .background(controller.tool == kind ? theme.amberSoft : .clear, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(controller.tool == kind ? theme.amber : theme.ink2)
                .accessibilityIdentifier("draw.\(kind.rawValue)")
                .drawRepeatOnLongPress(controller, kind)
            }
          }.padding(.trailing, 4)
        }
        .frame(maxWidth: .infinity)
        .clipped()
        divider
        Button("完成") { controller.finish() }
          .frame(width: 52, height: 44).contentShape(Rectangle())
          .foregroundStyle(theme.amber)
          .accessibilityIdentifier("draw.finish")
      }
    }
    .font(.system(size: 12, weight: .medium)).buttonStyle(.plain)
    .foregroundStyle(theme.ink2).background(theme.raised)
    .overlay(alignment: .top) { theme.line.frame(height: 0.5) }
  }
  private var divider: some View { theme.line.frame(width: 0.5, height: 28) }
  private func icon(
    _ system: String, _ label: String, _ id: String, enabled: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: system).frame(width: 44, height: 44).contentShape(Rectangle())
    }
    .disabled(!enabled)
    .opacity(enabled ? 1 : 0.35)
    .accessibilityLabel(label).accessibilityIdentifier(id)
  }
  private func action(_ title: String, _ icon: String, _ id: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { Label(title, systemImage: icon).padding(.horizontal, 10).frame(minHeight: 44) }.accessibilityIdentifier(id)
  }
}

/// 选中一条线之后才出现的一条浮条（第二批 11）。
///
/// 原来这几个动作是**顶掉**画线栏上排那三个开关的，位置一一对应：「管理」原地变成
/// 「样式」，而「删除」正好落在手指刚刚点过的那一格上。选中通常是误触的结果，紧接着
/// 下一下就把线删了。现在它们单独一条，压在画线栏上面：开关那一排一格都不动，
/// 「删除」被推到最右端、和另外三个之间隔一条分隔线，红色，离误触点最远。
///
/// 它浮在图区下沿，不进那根 `VStack`——选中 / 取消选中是很频繁的事，多一行少一行
/// 会把整张图一跳一跳地改高，K 线看着就乱了。
///
/// 横屏用的是同一根条的**平板样式**（`flat`）：横屏它不浮在图上，而是排在图外、
/// 标题下面那一行（见 `MainScreen.landscapeBody`），所以不要圆角、阴影和左右留白，
/// 只留一条贴着的横栏和底下一根发丝线。标识符两边一模一样——横竖屏永远只有一根在场。
struct DrawingSelectionBar: View {
  @ObservedObject var controller: DrawingController
  var flat = false
  @Environment(\.panelTheme) private var theme
  var body: some View {
    if let item = controller.selected {
      HStack(spacing: 2) {
        Text(item.kind.title + (item.locked ? " · 已锁定" : ""))
          .font(.system(size: 12)).foregroundStyle(theme.ink3)
          .padding(.leading, 12).lineLimit(1)
        Spacer(minLength: 8)
        act("样式", "slider.horizontal.3", "draw.style") { controller.panel = .style }
        act(item.locked ? "解锁" : "锁定", item.locked ? "lock.open" : "lock", "draw.lock") { controller.toggleLock() }
        act("复制", "plus.square.on.square", "draw.copy") { controller.duplicate() }
        theme.line.frame(width: 0.5, height: 26).padding(.horizontal, 4)
        act("删除", "trash", "draw.delete", tint: theme.down) { controller.deleteSelected() }
          .padding(.trailing, 8)
      }
      .frame(height: flat ? 44 : 48)
      .background {
        if flat { theme.raised }
        else { RoundedRectangle(cornerRadius: 12).fill(theme.raised2) }
      }
      .overlay(alignment: flat ? .bottom : .center) {
        if flat { theme.line.frame(height: 0.5) }
        else { RoundedRectangle(cornerRadius: 12).stroke(theme.line, lineWidth: 0.5) }
      }
      .shadow(color: .black.opacity(flat ? 0 : 0.18), radius: flat ? 0 : 8, y: flat ? 0 : 2)
      .padding(.horizontal, flat ? 0 : 8)
      .buttonStyle(.plain)
      // `children: .contain` 必须写在标识之前：直接给这根 `HStack` 挂标识，
      // SwiftUI 会把它**盖到每个子按钮头上**——四个按钮全叫 `draw.selection`，
      // 「样式」「锁定」「删除」在辅助功能树里就变成了一个名字，点不中也读不清。
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("draw.selection")
    }
  }
  private func act(
    _ title: String, _ icon: String, _ id: String, tint: Color? = nil,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 2) {
        Image(systemName: icon).font(.system(size: 14))
        Text(title).font(.system(size: 10))
      }
      .foregroundStyle(tint ?? theme.ink2)
      .frame(width: 48, height: 44).contentShape(Rectangle())
    }
    .accessibilityLabel(title).accessibilityIdentifier(id)
  }
}

struct DrawingHintStrip: View {
  @ObservedObject var controller: DrawingController
  @Environment(\.panelTheme) private var theme
  var body: some View {
    if let hint = controller.hint {
      Text(hint).font(PanelFont.note).foregroundStyle(theme.ink2)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(theme.raised, in: Capsule()).allowsHitTesting(false)
    }
  }
}

/// 横屏那根 64pt 的竖栏：工具列 · 收藏的几把工具 · 撤销 / 重做 · 完成（§2E1）。
///
/// 选中一条线之后的 样式 / 锁定 / 复制 / 删除 原来也挤在这根栏上，位置还跟着选中态
/// 一跳一跳地变——刚点完「重做」，下一次同一个位置已经换成了「删除」。现在它们搬到
/// 图外顶部那条属性栏上（`DrawingSelectionBar(flat:)`），这根栏从头到尾长一个样，
/// 「完成」「撤销」不会再被顶着走。
struct DrawingRail: View {
  @ObservedObject var controller: DrawingController
  @Environment(\.panelTheme) private var theme
  var body: some View {
    ScrollView {
      VStack(spacing: 2) {
        Button("工具") { controller.panel = .tools }.accessibilityIdentifier("draw.tools")
        ForEach(controller.preferences.favorites) { kind in
          Button(kind.shortTitle) { controller.pick(kind) }.accessibilityIdentifier("draw.\(kind.rawValue)")
            .foregroundStyle(controller.tool == kind ? theme.amber : theme.ink2)
            .drawRepeatOnLongPress(controller, kind)
        }
        Button("撤销") { controller.undo() }.disabled(!controller.canUndo).accessibilityIdentifier("draw.undo")
        Button("重做") { controller.redo() }.disabled(!controller.canRedo).accessibilityIdentifier("draw.redo")
        Button("完成") { controller.finish() }.accessibilityIdentifier("draw.finish")
      }.buttonStyle(DrawingRailButton())
    }.font(.system(size: 11)).frame(width: 64).background(theme.raised).foregroundStyle(theme.ink2)
  }
}
private struct DrawingRailButton: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle()).opacity(configuration.isPressed ? 0.5 : 1)
  }
}

struct DrawingSheet: View {
  @ObservedObject var controller: DrawingController
  var panel: DrawingController.Panel
  /// 当前品种的报价小数位。价格输入框照它显示——原来是 `0...12`，BTC 的一条趋势线
  /// 端点会写成 `77017.099999999`，那串尾巴既不是用户填的也不是图上画的。
  var decimals: Int = 2
  @Environment(\.dismiss) private var dismiss
  @State private var confirmClear = false
  var body: some View {
    if panel == .style, let item = controller.selected {
      // 样式面板只占下面一截：调颜色粗细的时候得能看见改的是哪条线（第二批 10）。
      DrawingStyleEditor(controller: controller, item: item, decimals: decimals)
        .presentationDetents([.fraction(0.4), .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.4)))
    } else {
      NavigationStack {
        List {
          if panel == .tools {
            Section {
              Toggle("靠近 K 线时吸附", isOn: Binding(get: { controller.preferences.magnet }, set: { _ in controller.toggleMagnet() }))
                .accessibilityIdentifier("draw.magnet")
              Toggle("连续画线", isOn: Binding(get: { controller.preferences.continuous }, set: { _ in controller.toggleContinuous() }))
                .accessibilityIdentifier("draw.continuous")
              Button("管理画线（\(controller.items.count)）") { controller.panel = .objects }.accessibilityIdentifier("draw.objects")
            }
            ForEach(["线条", "区域", "斐波那契", "测量"], id: \.self) { group in
              Section(group) {
                ForEach(Drawing.Kind.allCases.filter { $0.group == group }) { kind in
                  HStack {
                    Button { controller.pick(kind) } label: {
                      Text(kind.title).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }
                      .accessibilityIdentifier("draw.tool.\(kind.rawValue)")
                      .drawRepeatOnLongPress(controller, kind)
                    Button { controller.toggleFavorite(kind) } label: {
                      Image(systemName: controller.preferences.favorites.contains(kind) ? "star.fill" : "star")
                        .frame(width: 44, height: 44)
                    }.accessibilityLabel("收藏" + kind.title).accessibilityIdentifier("draw.favorite.\(kind.rawValue)")
                  }.buttonStyle(.borderless)
                }
              }
            }
          } else {
            Section {
              if controller.items.isEmpty { Text("还没有画线") }
              ForEach(Array(controller.items.reversed())) { item in
                HStack {
                  Button { controller.select(item.id); dismiss() } label: {
                    VStack(alignment: .leading, spacing: 3) {
                      Text(item.kind.title + (item.locked ? " · 已锁定" : ""))
                      Text(item.a.p.formatted(.number.precision(.significantDigits(2...10))))
                        .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                  }.accessibilityIdentifier("draw.object.\(item.id)")
                  Button { controller.toggleHidden(item) } label: {
                    Image(systemName: item.hidden ? "eye.slash" : "eye").frame(width: 44, height: 44)
                  }.accessibilityLabel(item.hidden ? "显示画线" : "隐藏画线")
                }.buttonStyle(.borderless)
                .swipeActions {
                  Button("删除", role: .destructive) { controller.select(item.id); controller.deleteSelected() }
                }
              }
            }
            if !controller.items.isEmpty {
              Button(controller.items.allSatisfy(\.hidden) ? "全部显示" : "全部隐藏") { controller.hideAll() }
              Button("清空当前品种画线", role: .destructive) { confirmClear = true }.accessibilityIdentifier("draw.clear")
            }
          }
        }
        .navigationTitle(panel == .tools ? "画线工具" : "画线管理")
        .navigationBarTitleDisplayMode(.inline)
        // 出口摆左上角的「‹ 返回」，和面板、自选页、品种页同一个位置（2026-09-15）。
        // 这张表单没有「保存」语义——它改的每一项都即时生效——所以右上角不留按钮。
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button { dismiss() } label: { Label("返回", systemImage: "chevron.left") }
              .accessibilityIdentifier("draw.sheet.done")
          }
        }
        .confirmationDialog("清空当前品种的全部画线？", isPresented: $confirmClear, titleVisibility: .visible) {
          Button("清空画线", role: .destructive) { controller.clear() }
        } message: { Text("清空后可在画线栏撤销。") }
      }.presentationDetents(panel == .tools ? [.large] : [.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
  }
}

private struct DrawingStyleEditor: View {
  @ObservedObject var controller: DrawingController
  @State var item: Drawing
  var decimals: Int = 2
  @Environment(\.dismiss) private var dismiss
  @State private var levelText = ""
  var body: some View {
    NavigationStack {
      Form {
        Section("样式") {
          DrawingColorControl(title: "颜色", color: Binding(get: { item.color ?? "#D6A64F" }, set: { item.color = $0 }))
          Stepper("粗细：\(item.lineWidth, specifier: "%.1f")", value: $item.lineWidth, in: 0.5...6, step: 0.5)
          Picker("线型", selection: $item.dash) { ForEach(Drawing.Dash.allCases, id: \.self) { Text($0.title).tag($0) } }
          // 「测量」不在这儿了：它已经不是一个框，是两点之间的一条线（§2E4），没有底可填。
          if [.rectangle, .channel].contains(item.kind) { Toggle("背景填充", isOn: $item.filled) }
          Toggle("锁定位置", isOn: $item.locked)
        }
        Section("坐标") {
          ForEach(item.points.indices, id: \.self) { index in
            DatePicker("点 \(index + 1) 时间", selection: Binding(get: { Date(timeIntervalSince1970: item.points[index].t / 1000) }, set: { item.points[index].t = $0.timeIntervalSince1970 * 1000 }))
            HStack {
              Text("点 \(index + 1) 价格")
              TextField("价格", value: $item.points[index].p, format: .number.precision(.fractionLength(0...max(decimals, 2))))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier("draw.price.\(index)")
            }
          }
        }.disabled(item.locked)
        if item.kind == .fibonacci {
          Section("回撤比例") {
            TextField("0, 0.382, 0.5, 0.618, 1", text: $levelText).keyboardType(.numbersAndPunctuation)
            Text("用逗号分隔；0 为终点，1 为起点。").font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle(item.kind.title).navigationBarTitleDisplayMode(.inline)
      .onAppear { levelText = item.levels.map { String($0) }.joined(separator: ", ") }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            if item.kind == .fibonacci, let levels = parsedLevels { item.levels = levels }
            controller.update(item); dismiss()
          }.disabled(!item.isValid || (item.kind == .fibonacci && parsedLevels == nil)).accessibilityIdentifier("draw.save")
        }
      }
    }
  }
  private var parsedLevels: [Double]? {
    let parts = levelText.replacingOccurrences(of: "，", with: ",").split(separator: ",")
    let values = parts.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard !values.isEmpty, values.count == parts.count, values.count <= 24, values.allSatisfy({ $0.isFinite && abs($0) <= 10 }) else { return nil }
    return Array(Set(values)).sorted()
  }
}

/// Shared native picker + one-tap swatches, storing an explicit sRGB hex value.
struct DrawingColorControl: View {
  var title: String
  var identifierPrefix = "color"
  @Binding var color: Hex
  private let swatches: [Hex] = ["#E2B34F", "#4A90E2", "#A078D0", "#37A78F", "#E46A76", "#D88040", "#B8C4D8"]
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ColorPicker(title, selection: Binding(get: { Color(hex: color) }, set: { color = Self.hex($0) }), supportsOpacity: false)
      ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 4) {
        ForEach(swatches, id: \.self) { hex in
          Button { color = hex } label: {
            Circle().fill(Color(hex: hex)).frame(width: 22, height: 22)
              .overlay(Circle().stroke(color == hex ? Color.primary : .clear, lineWidth: 2).padding(-3))
              .frame(width: 44, height: 44).contentShape(Rectangle())
          }.buttonStyle(.borderless).accessibilityLabel(hex.value).accessibilityIdentifier("\(identifierPrefix).\(hex.value)")
        }
      }
      }
    }
  }
  static func hex(_ color: Color) -> Hex {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
    return Hex(String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded())))
  }
}

/// 「点一下画一笔，长按接着画」（§2E3）。
///
/// 画完一笔工具自己退回选择态，本来就是 `continuous == false` 时的行为；这里把
/// 那个开关和手势绑在一起：**点**＝这一把只画一笔，**长按**＝这一把一直画下去。
/// 开关本身（画线栏上的「连续开 / 连续关」、工具表里的「连续画线」）留着不动，
/// 它现在同时是这次长按的结果显示——用户按完低头一看就知道自己进了哪种模式。
///
/// 按住 0.45s 才算长按，和周期条上「长按钉住」一个数：比系统默认的 0.5s 稍快一点，
/// 又远够不着误触。
extension View {
  func drawRepeatOnLongPress(_ controller: DrawingController, _ kind: Drawing.Kind) -> some View {
    onLongPressGesture(minimumDuration: 0.45) { controller.pick(kind, repeating: true) }
  }
}
