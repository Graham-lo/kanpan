import KanpanChart
import KanpanCore
import SwiftUI
import UIKit

/// 画线栏：上排是「当前状态相关」的动作，下排是工具。
///
/// 右端钉着几个固定按钮，左边那一段放可变数量的东西。这里有个坑：固定按钮原来是直接
/// 跟在滚动区后面排的，`撤销/重做/完成` 三个 44pt 加起来 132pt，实测最后一个工具
/// chip（「测量」）会整块压在「撤销」底下，`hittable=false`——想点测量，点到的是撤销，
/// 用户刚画的那条线没了。所以：
///
/// 1. 左边那一段显式 `.frame(maxWidth: .infinity)` + `.clipped()`，不许它把内容漏到固定区底下；
/// 2. 撤销/重做挪到上排右端，下排右端只剩「完成」，工具排的固定占用从 132pt 降到 44pt；
/// 3. 固定区左边加一条分隔线，让「这边是可变的、那边是不动的」一眼看得出来。
///
/// **工具排：放得下就铺满，放不下才滚动（2026-09-21）。** 从前它一律是滚动区，
/// 393pt 上出厂那几把正好把第四把「回撤」切在字中间——切口没有任何「后面还有」的提示，
/// 这把工具在最窄的机型上等于不存在。现在按周期条那套来：`ViewThatFits` 先试一套不滚动、
/// 各档等分铺满剩余宽度的排法，真放不下（用户钉了很多把）才退回滚动，并且右缘加一层
/// 渐隐——被裁的那把是淡出去的，不是被切成半个字。字号、图标、文字一个都没缩。
///
/// **选中一条线之后，上排左边那一段换成 `DrawingSelectionBar`**：三个开关让位，
/// 撤销/重做原地不动。行数和总高度一个 pt 不变，所以图表不会跟着跳；那几个动作也就
/// 不必再浮在画布上（`kanpan-no-floating-controls-over-chart`）。
struct DrawingBar: View {
  @ObservedObject var controller: DrawingController
  var onSend: (() -> Void)?
  var sendEnabled = true
  @Environment(\.panelTheme) private var theme
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        if controller.selected != nil {
          DrawingSelectionBar(controller: controller)
        } else {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
              action(controller.preferences.magnet ? "吸附开" : "吸附关", "arrow.up.and.down.and.arrow.left.and.right", "draw.magnet.quick") { controller.toggleMagnet() }
              action(controller.preferences.continuous ? "连续开" : "连续关", "repeat", "draw.continuous.quick") { controller.toggleContinuous() }
              action("管理", "square.stack", "draw.objects.quick") { controller.panel = .objects }
            }.padding(.horizontal, 8)
          }
          .frame(maxWidth: .infinity)
          .clipped()
        }
        divider
        icon("arrow.uturn.backward", "撤销", "draw.undo", enabled: controller.canUndo) { controller.undo() }
        icon("arrow.uturn.forward", "重做", "draw.redo", enabled: controller.canRedo) { controller.redo() }
        if let onSend {
          icon("paperplane", "发给朋友", "draw.send", enabled: true, action: onSend)
            .opacity(sendEnabled ? 1 : 0.35)
        }
      }
      // 选中 / 取消选中是很频繁的事：这一换不带动画，免得开关和选中栏互相甩进甩出。
      .animation(nil, value: controller.selected?.id)
      HStack(spacing: 0) {
        Button { controller.openTools() } label: {
          Image(systemName: "pencil.line").frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("全部画线工具").accessibilityIdentifier("draw.tools")
        tools
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

  /// 面板上那十二把工具，按同一个顺序摆。三套候选排法从宽松到紧凑，都放不下才滚动。
  ///
  /// 原来这排 chip 摆的是用户收藏的那几把。收藏是 41 把工具时代的解法——翻不到就先收起来；
  /// 砍到十二把之后面板一屏就是全部，收藏没有了要解决的问题，这排也就直接摆全量
  /// （`Drawing.Kind.palette`），省掉「先去收藏、这排才有」这一道。
  ///
  /// 三套铺满的差别只在留白（chip 之间的最小间距与各自的内边距），chip 自己的字号和
  /// 记号大小三套一个数：挤不下时让出来的是空隙，不是内容。
  private var tools: some View {
    ViewThatFits(in: .horizontal) {
      filledTools(spacing: 6, pad: 10)
      filledTools(spacing: 4, pad: 6)
      filledTools(spacing: 2, pad: 2)
      scrollingTools
    }
    .frame(maxWidth: .infinity)
  }

  /// 铺满的那套排法：**多出来的宽度摊给 chip 之间的空隙**，chip 自己按内容该多宽多宽。
  ///
  /// 不能拿 `.frame(maxWidth: .infinity)` 等分——出厂那几把宽窄不一（「趋势线」三个字，
  /// 「矩形」两个字），等分会让宽的那两把恰好差几个点，`Text` 当场截成「趋…」，
  /// 那正是这次要修的毛病换了个样子。
  private func filledTools(spacing: Double, pad: Double) -> some View {
    HStack(spacing: 0) {
      ForEach(Drawing.Kind.palette) { kind in
        if kind != Drawing.Kind.palette.first { Spacer(minLength: spacing) }
        toolChip(kind, pad: pad)
      }
    }.padding(.horizontal, 4)
  }

  private var scrollingTools: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        ForEach(Drawing.Kind.palette) { kind in toolChip(kind, pad: 10) }
      }.padding(.trailing, 4)
    }
    .frame(maxWidth: .infinity)
    // `.clipped()` 管的是 hit-test（见上面第 1 条，不许删）；渐隐只管看的那一层，
    // 让右缘被裁的那把淡出去、一眼看得出「还能往左划」。
    .clipped()
    .mask(LinearGradient(
      stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9),
              .init(color: .black.opacity(0), location: 1)],
      startPoint: .leading, endPoint: .trailing))
  }

  /// 一把工具：记号在前、短名在后——横屏那根栏和这排 chip 认的是同一套形状（`DrawKindGlyph`）。
  ///
  private func toolChip(_ kind: Drawing.Kind, pad: Double) -> some View {
    Button { controller.pick(kind) } label: {
      HStack(spacing: 5) { DrawKindGlyph(kind: kind, size: 18); Text(kind.shortTitle).fixedSize() }
    }
    .padding(.horizontal, pad).frame(minHeight: 44)
    .background(controller.tool == kind ? theme.amberSoft : .clear, in: RoundedRectangle(cornerRadius: 8))
    .foregroundStyle(controller.tool == kind ? theme.amber : theme.ink2)
    .contentShape(Rectangle())
    .accessibilityIdentifier("draw.\(kind.rawValue)")
    .drawRepeatOnLongPress(controller, kind)
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

/// 选中一条线之后才出现的那几个动作：样式 / 锁定 / 复制 / 删除（第二批 11）。
///
/// 最早它们是**顶掉**画线栏上排那三个开关的，位置一一对应：「管理」原地变成「样式」，
/// 而「删除」正好落在手指刚刚点过的那一格上。选中通常是误触的结果，紧接着下一下就把
/// 线删了。所以这几个动作现在的排法是：线名在最左（提示而已，窄了就省略号收掉），
/// 「删除」推到最右端、和另外三个之间隔一条分隔线、警示色（`theme.danger`），离误触点最远。
///
/// **警示色不是跌色。** 这儿原来写的是 `theme.down`，想的是「跌 = 红 = 危险」——可看盘
/// 出厂就是红涨绿跌，跌色是**绿的**，于是这个「删除」在真机上是个绿按钮，读起来像
/// 「确认 / 通过」。涨跌色是行情的读数，不是语义色；警示走 `theme.danger`（见 `PaletteSeed.danger`）。
///
/// **2026-09-21 它不再浮在图上。** 中间那一版把它做成压在画线栏上面的一条浮条，
/// 理由是「多一行少一行会把整张图一跳一跳地改高」——可竖屏它正好盖掉半行 MACD 图例，
/// 和「K 线画布上不浮任何控件」（`kanpan-no-floating-controls-over-chart`）直接冲突。
/// 现在两个都要：
///
/// - **竖屏（`inline`）**：它占掉画线栏上排左边那一段，也就是三个开关原来的位置，
///   撤销/重做仍在右端原地。栏的行数与总高度一个 pt 不变，图表不会跳，它也不碰画布。
///   自己不铺底——底是画线栏的（`theme.raised`）。
/// - **横屏（`landscape`）**：排在图外、标题下面那一行（见 `MainScreen.landscapeBody`），
///   贴一条横栏加底下一根发丝线，没有圆角阴影和左右留白。
///
/// 标识符两边一模一样（`draw.selection` / `draw.style` / `draw.lock` / `draw.copy` /
/// `draw.delete`）——横竖屏永远只有一根在场。
struct DrawingSelectionBar: View {
  /// 它排在哪儿。两套只差外壳：里头那几个动作、顺序和标识符完全一样。
  enum Placement { case inline, landscape }
  @ObservedObject var controller: DrawingController
  var placement: Placement = .inline
  @Environment(\.panelTheme) private var theme
  private var landscape: Bool { placement == .landscape }
  var body: some View {
    if let item = controller.selected {
      HStack(spacing: 2) {
        Text(item.kind.title + (item.locked ? " · 已锁定" : ""))
          .font(.system(size: 12)).foregroundStyle(theme.ink3)
          .padding(.leading, landscape ? 12 : 8).lineLimit(1).truncationMode(.tail)
          // 名字是提示不是功能：宽度不够先收它，四个动作一个都不许挤掉。
          .layoutPriority(-1)
        Spacer(minLength: 4)
        act("样式", "slider.horizontal.3", "draw.style") { controller.panel = .style }
        act(item.locked ? "解锁" : "锁定", item.locked ? "lock.open" : "lock", "draw.lock") { controller.toggleLock() }
        act("复制", "plus.square.on.square", "draw.copy") { controller.duplicate() }
        theme.line.frame(width: 0.5, height: 26).padding(.horizontal, 4)
        act("删除", "trash", "draw.delete", tint: theme.danger) { controller.deleteSelected() }
          .padding(.trailing, landscape ? 8 : 2)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 44)
      .background { if landscape { theme.raised } }
      .overlay(alignment: .bottom) { if landscape { theme.line.frame(height: 0.5) } }
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

/// 横屏画线工作台底下那根横条：笔形入口 + 收藏的几把工具 + 几个常驻动作（§2E5）。
///
/// 这根条改过三轮，每一轮都是位置和入口数量的取舍：
///
/// 1. 最早是右边一列**文字按钮**——「工具」「趋势线」「撤销」「重做」「完成」，工具只有
///    一个入口，点开是一张盖住整张图的半屏表单；
/// 2. 照 AICoin 改成右边一列**分类图标**，点开向左弹一条那一类的清单；
/// 3. 现在照 TradingView 收成**底部一横条**，工具入口是一个笔形图标，点开是那张自带
///    搜索和分类的「绘图」面板（`DrawingToolPicker`）。
///
/// 从竖栏挪到底部是尺寸算出来的，不只是照抄：工具全量对齐 TV 之后要在栏上摆的东西有
/// 十四五个，横屏可用高度只有 390pt 上下，竖着摆必然要滚动——而横屏的**宽**有 850pt，
/// 横着摆绰绰有余。手也顺：横握手机时两个拇指都停在下沿，右栏顶上那几格恰恰是最难够的。
///
/// 条上留下的都是**画的过程中要反复点**的东西，它们不该藏进面板里：收藏的工具一格一个、
/// 形状即按钮（`DrawKindGlyph`），吸附 / 连续两个开关，以及撤销 / 重做 / 隐藏 / 管理 / 完成。
///
/// 「清空」没上条。AICoin 把它和「隐藏」并排放，但那是一下就把整个品种的线全删掉的动作，
/// 紧挨着一个每天要点很多次的「隐藏」太险——它留在「管理」里，那儿有确认。
struct DrawingDock: View {
  @ObservedObject var controller: DrawingController
  var onSend: (() -> Void)?
  var sendEnabled = true
  @Environment(\.panelTheme) private var theme
  @Environment(\.displayScale) private var displayScale
  private static let height: Double = 46

  var body: some View {
    HStack(spacing: 0) {
      toolsButton
      divider
      // 工具放在滚动区里：十二把在横屏这根条上也摆不下，但右边那几个固定动作
      // 一个都不能被挤没（竖屏那根条踩过这个坑，见 `DrawingBar` 顶上那段）。
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 2) {
          ForEach(Drawing.Kind.palette) { kind in toolButton(kind) }
        }.padding(.horizontal, 4)
      }
      .frame(maxWidth: .infinity)
      .clipped()
      divider
      toggleButton("吸附", "arrow.up.and.down.and.arrow.left.and.right", "draw.magnet.quick",
                   on: controller.preferences.magnet) { controller.toggleMagnet() }
      toggleButton("连续", "repeat", "draw.continuous.quick",
                   on: controller.preferences.continuous) { controller.toggleContinuous() }
      divider
      iconButton("arrow.uturn.backward", "撤销", "draw.undo", enabled: controller.canUndo) { controller.undo() }
      iconButton("arrow.uturn.forward", "重做", "draw.redo", enabled: controller.canRedo) { controller.redo() }
      let allHidden = !controller.items.isEmpty && controller.items.allSatisfy(\.hidden)
      iconButton(allHidden ? "eye.slash" : "eye", allHidden ? "全部显示" : "全部隐藏", "draw.hideAll",
                 enabled: !controller.items.isEmpty) { controller.hideAll() }
      iconButton("square.stack", "管理画线", "draw.objects.quick") { controller.panel = .objects }
      if let onSend {
        iconButton("paperplane", "发给朋友", "draw.send", action: onSend).opacity(sendEnabled ? 1 : 0.35)
      }
      divider
      Button("完成") { controller.finish() }
        .frame(width: 56, height: Self.height).contentShape(Rectangle())
        .foregroundStyle(theme.amber).font(.system(size: 12, weight: .medium))
        .accessibilityIdentifier("draw.finish")
    }
    .font(.system(size: 10))
    .buttonStyle(.plain)
    .frame(height: Self.height)
    .background(theme.raised)
    .foregroundStyle(theme.ink2)
    .overlay(alignment: .top) { theme.line.frame(height: 1 / displayScale) }
  }

  private var divider: some View { theme.line.frame(width: 1 / displayScale, height: 26) }

  /// 笔形入口。手里拿着的工具不在这根条上时它也亮着，并且写上那把工具的名字——
  /// 不然换了一把这条上没摆的线（长按重复画留下的，或者老版本存的），
  /// 条上没有任何一格是亮的，看不出手里正拿着东西。
  private var toolsButton: some View {
    let held = controller.tool.flatMap { Drawing.Kind.palette.contains($0) ? nil : $0.shortTitle }
    return Button { controller.openTools() } label: {
      VStack(spacing: 1) {
        Image(systemName: "pencil.line").font(.system(size: 17))
        Text(held ?? "工具").lineLimit(1).minimumScaleFactor(0.8)
      }.frame(width: 54, height: Self.height).contentShape(Rectangle())
    }
    .foregroundStyle(held != nil || controller.picker ? theme.amber : theme.ink2)
    .background(controller.picker ? theme.amberSoft : .clear)
    .accessibilityLabel("全部画线工具").accessibilityIdentifier("draw.tools")
  }

  private func toolButton(_ kind: Drawing.Kind) -> some View {
    Button { controller.pick(kind) } label: {
      VStack(spacing: 1) {
        DrawKindGlyph(kind: kind, size: 20)
        Text(kind.shortTitle).lineLimit(1).minimumScaleFactor(0.8)
      }.frame(minWidth: 46, minHeight: Self.height).padding(.horizontal, 2).contentShape(Rectangle())
    }
    .foregroundStyle(controller.tool == kind ? theme.amber : theme.ink2)
    .background(controller.tool == kind ? theme.amberSoft : .clear, in: RoundedRectangle(cornerRadius: 8))
    .accessibilityLabel(kind.title)
    .accessibilityIdentifier("draw.\(kind.rawValue)")
    .drawRepeatOnLongPress(controller, kind)
  }

  private func toggleButton(_ title: String, _ icon: String, _ id: String, on: Bool,
                            action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(spacing: 1) {
        Image(systemName: icon).font(.system(size: 13))
        Text(title).lineLimit(1)
      }.frame(width: 44, height: Self.height).contentShape(Rectangle())
    }
    .foregroundStyle(on ? theme.amber : theme.ink3)
    .accessibilityLabel(title + (on ? "开" : "关"))
    .accessibilityIdentifier(id)
  }

  private func iconButton(_ icon: String, _ label: String, _ id: String, enabled: Bool = true,
                          action: @escaping () -> Void) -> some View {
    Button(action: action) {
      // 命中区不能低于 44×44。
      Image(systemName: icon).font(.system(size: 15))
        .frame(width: 44, height: Self.height).contentShape(Rectangle())
    }
    .disabled(!enabled).opacity(enabled ? 1 : 0.35)
    .accessibilityLabel(label).accessibilityIdentifier(id)
  }
}

struct DrawingSheet: View {
  @ObservedObject var controller: DrawingController
  var panel: DrawingController.Panel
  /// 当前品种的报价小数位。价格输入框照它显示——原来是 `0...12`，BTC 的一条趋势线
  /// 端点会写成 `77017.099999999`，那串尾巴既不是用户填的也不是图上画的。
  var decimals: Int = 2
  @Environment(\.dismiss) private var dismiss
  @Environment(\.panelTheme) private var theme
  @State private var confirmClear = false
  /// 当前左划开着的是哪一行。一张表同一时刻只许开一行（见 `SwipeToDelete`）。
  @State private var openSwipe: String?
  var body: some View {
    if panel == .style, let item = controller.selected {
      // 样式面板只占下面一截：调颜色粗细的时候得能看见改的是哪条线（第二批 10）。
      DrawingStyleEditor(controller: controller, item: item, decimals: decimals)
        .presentationDetents([.fraction(0.4), .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.4)))
        .presentationBackground(theme.app)
    } else {
      NavigationStack {
        List {
          Section {
              if controller.items.isEmpty { Text("还没有画线").foregroundStyle(theme.ink2) }
              // 左划删除走 `SwipeToDelete`，和提醒总表同一个零件。
              //
              // 这儿原来用的是系统的 `.swipeActions`，砖底靠 `.tint(theme.danger)` 盖，
              // 砖上的字写着 `Text("删除").foregroundStyle(theme.badgeInk)`。
              // 2026-09-22 在 iPhone 15 / 青苔深上量了一遍：**字色那一半根本没生效**。
              // 砖底确实是 `#F08A80`（`.tint` 管用），但字的像素里 `#FFFFFF` 218 个、
              // `#060A08` 一个都没有，对比度 2.43:1；同一屏上提醒总表那块砖是
              // 8.20:1。原因不是「被别的样式盖过去」，而是 SwiftUI 只把 label 里的
              // **字符串**取走塞进 `UIContextualAction.title`，整棵 SwiftUI 子树连同
              // `foregroundStyle` 一起丢掉，字是 UIKit 画的，一律白色——无障碍树里
              // 那颗按钮是叶子、里头一个 StaticText 都没有，就是这件事的旁证。
              //
              // 所以这一处的字色在 `.swipeActions` 上没有干净的解法。原生带的两样
              // 东西（滑到底直接触发、VoiceOver 的破坏性语义与收拢动画）没有丢，
              // 都在 `SwipeToDelete` 里补齐了，那儿有逐条说明。
              ForEach(Array(controller.items.reversed())) { item in
                SwipeToDelete(id: item.id, open: $openSwipe, brick: .pill,
                              trailing: [.delete(theme) {
                                controller.select(item.id); controller.deleteSelected()
                              }]) { swipe in
                  HStack {
                    Button {
                      // 划开着的时候点行不是「选中这条线」，是「先把砖收回去」。
                      if swipe.isOpen { swipe.close() } else { controller.select(item.id); dismiss() }
                    } label: {
                      VStack(alignment: .leading, spacing: 3) {
                        Text(item.kind.title + (item.locked ? " · 已锁定" : ""))
                        // 价格的写法全 app 一个口径：品种自己的小数位 + 极小正价自动多给
                        // 几位（审查 B-07）。原来这儿按「有效数字 2–10 位」写，同一条线
                        // 在图上和在这张清单里能差出好几位。
                        Text(fmtPrice(item.a.p, decimals: decimals))
                          .font(.caption).foregroundStyle(theme.ink3)
                      }.frame(maxWidth: .infinity, alignment: .leading)
                    }.accessibilityIdentifier("draw.object.\(item.id)")
                    Button {
                      if swipe.isOpen { swipe.close() } else { controller.toggleHidden(item) }
                    } label: {
                      Image(systemName: item.hidden ? "eye.slash" : "eye").frame(width: 44, height: 44)
                    }.accessibilityLabel(item.hidden ? "显示画线" : "隐藏画线")
                  }.buttonStyle(.borderless)
                  // 行内的留白原来由 `List` 自己的 `listRowInsets` 给。砖块要够得着
                  // 行的右沿，那份内缩必须清掉，改由行内容自己补回同样的量。
                  .padding(.leading, 16)
                  .padding(.trailing, 4)
                  .padding(.vertical, 12)
                }
                .listRowInsets(EdgeInsets())
                // 内缩清掉之后分隔线会顶到最左边，按原来的量把它推回去。
                .alignmentGuide(.listRowSeparatorLeading) { _ in 16 }
              }
            }
            .listRowBackground(theme.raised)
          if !controller.items.isEmpty {
            Section {
              Button(controller.items.allSatisfy(\.hidden) ? "全部显示" : "全部隐藏") { controller.hideAll() }
              // 这一行不留 `role: .destructive`：表里的破坏性按钮，role 的作用只有
              // 「把字染成系统红」，而系统红是这一屏上唯一不跟皮肤走的颜色。改用
              // `theme.danger`（同 `ReviewBook` 的「作废记录」、`AlertListPage` 的删除）。
              // 破坏性语义没丢——真正不可逆的那一下在紧接着的确认弹窗里，
              // 那颗「清空画线」仍是 destructive（系统弹窗自己画，染不了也不该染）。
              Button("清空当前品种画线") { confirmClear = true }
                .foregroundStyle(theme.danger)
                .accessibilityIdentifier("draw.clear")
            }
            .listRowBackground(theme.raised)
          }
        }
        // 这张 `List` 原来一个主题令牌都没接：三套皮肤下它长得一模一样，一张系统灰白
        // 的表压在身后那张跟着皮肤走的页面上，读成两张纸。接法照 `IndicatorPanel`
        // 那张编辑表：表底 `app`、行底 `raised`（行底是**行**的属性，挂在 `List`
        // 上不生效）、导航栏也取 `app`、半屏自己的底也给 `app`。
        //
        // 导航栏和表底必须是**同一支色**。给 `raised` 的那一版在青苔浅色下是
        // `#FFFFFF` 压着 `#F3F7F4`（亮度比 1.08），导航栏下沿横出一道看得见的
        // 明度台阶；六套皮肤里只有经典浅色（两支都是 `#FFFFFF`）碰巧看不出来。
        // 整屏要读成一块连续的材料，所以这儿不留台阶。
        .scrollContentBackground(.hidden)
        .background(theme.app)
        .navigationTitle("画线管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.app, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
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
      }.tint(theme.amber)
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationBackground(theme.app)
    }
  }

}

private struct DrawingStyleEditor: View {
  @ObservedObject var controller: DrawingController
  @State var item: Drawing
  var decimals: Int = 2
  @Environment(\.dismiss) private var dismiss
  @Environment(\.panelTheme) private var theme
  @State private var levelText = ""
  /// 进来那一刻这条线的样式。保存时拿它比一比，只有真的动过才把新样式提成该类默认。
  @State private var original: DrawingStyle?
  var body: some View {
    NavigationStack {
      Form {
        // 分节标题走 `PanelFormSectionTitle`（和 `IndicatorEditor` 同一个定义）：
        // 内建的 `Section("字面量")` 那一行是系统 secondary label 灰，换皮肤不动，
        // 在一张已经全部换过肤的表上，它是唯一一处三套皮肤长得一样的字。
        Section {
          DrawingColorControl(title: "颜色", color: Binding(get: { item.color ?? "#D6A64F" }, set: { item.color = $0 }))
          LineWidthPicker(width: $item.lineWidth)
          Picker("线型", selection: $item.dash) { ForEach(Drawing.Dash.allCases, id: \.self) { Text($0.title).tag($0) } }
          if item.kind.usesFill { Toggle("背景填充", isOn: $item.filled) }
          Toggle("锁定位置", isOn: $item.locked)
          // 「换一种画法」：同一族里形状一样，只差延伸到哪儿、端点画不画箭头。
          // 面板上只摆十二把，射线 / 直线 / 水平射线 / 箭头 / 十字线就活在这几行里——
          // 用户是看着图上那条线换的，不用先认识五个名字。
          ForEach(item.kind.swaps) { swap in
            DrawingKindSwapRow(swap: swap, kind: swapBinding(swap))
          }
        } header: {
          PanelFormSectionTitle(text: "样式")
        }
        .listRowBackground(theme.raised)
        Section {
          ForEach(item.points.indices, id: \.self) { index in
            DatePicker("点 \(index + 1) 时间", selection: Binding(get: { Date(timeIntervalSince1970: item.points[index].t / 1000) }, set: { item.points[index].t = $0.timeIntervalSince1970 * 1000 }))
            HStack {
              Text("点 \(index + 1) 价格")
              TextField("价格", value: $item.points[index].p, format: .number.precision(.fractionLength(max(0, decimals))))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier("draw.price.\(index)")
            }
          }
        } header: {
          PanelFormSectionTitle(text: "坐标")
        }
        .disabled(item.locked)
        .listRowBackground(theme.raised)
        if item.kind.usesText {
          Section {
            TextField("写点什么", text: $item.text, axis: .vertical).lineLimit(1...4)
              .accessibilityIdentifier("draw.note.text")
            Text("最多 \(Drawing.textLimit) 个字。").font(.caption).foregroundStyle(theme.ink3)
          } header: {
            PanelFormSectionTitle(text: "文字")
          }
          .listRowBackground(theme.raised)
        }
        if item.kind.usesLevels {
          Section {
            TextField("0, 0.382, 0.5, 0.618, 1", text: $levelText).keyboardType(.numbersAndPunctuation)
            Text(item.kind == .fibExtension ? "用逗号分隔；从起算点 C 往外按 A→B 的幅度乘出来。"
                 : "用逗号分隔；0 为终点，1 为起点。").font(.caption).foregroundStyle(theme.ink3)
          } header: {
            PanelFormSectionTitle(text: item.kind == .fibExtension ? "扩展比例" : "回撤比例")
          }
          .listRowBackground(theme.raised)
        }
      }
      // 这张 `Form` 原来整张都是系统灰白——底、分节卡片、导航栏一个令牌都没接。
      // 从前那句「这张表是系统 `Form`」的就地豁免不成立：`IndicatorPanel` 那张同样是
      // 系统 `Form`，照样接了主题（表底 `app` / 行底 `raised` / 导航栏 `app`），
      // 留着 `Form` 只是为了它给的分节、左滑和键盘避让，不是为了留一张白纸。
      .scrollContentBackground(.hidden)
      .background(theme.app)
      .navigationTitle(item.kind.title).navigationBarTitleDisplayMode(.inline)
      // 导航栏和表底同取 `app`，中间不留明度台阶（同「画线管理」那张，理由见那儿）。
      .toolbarBackground(theme.app, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .onAppear {
        levelText = item.levels.map { String($0) }.joined(separator: ", ")
        if original == nil { original = DrawingStyle(item) }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            if item.kind.usesLevels, let levels = parsedLevels { item.levels = levels }
            // 只有颜色 / 粗细 / 线型 / 填充 / 比例真的动过，才把它提成这类工具以后的默认。
            // 只挪了端点、改了文字、上了个锁的，别人下次画的线不该跟着变。
            controller.update(item, promoteStyle: DrawingStyle(item) != original); dismiss()
          }.disabled(!item.isValid || (item.kind.usesLevels && parsedLevels == nil)).accessibilityIdentifier("draw.save")
        }
      }
    }
    .tint(theme.amber)
  }
  /// 换画法那一排绑的是 `item.kind` 本身。
  ///
  /// 同一族里点数一样（`Drawing.Kind.swaps` 那段注释说的就是这条），所以这里只换 kind、
  /// 不动 `points`；点数要是对不上，`DrawingController.update` 会把整次修改**悄悄丢掉**。
  /// 当前这条线的 kind 不在这一排里时（比如已经换成了箭头，再看「延伸」那一排），
  /// 读回第一项，等于「先回到不延伸再说」，而不是让选择器空着。
  private func swapBinding(_ swap: Drawing.KindSwap) -> Binding<Drawing.Kind> {
    Binding(
      get: { swap.options.contains { $0.kind == item.kind } ? item.kind : swap.options[0].kind },
      set: { item.kind = $0 })
  }
  private var parsedLevels: [Double]? {
    let parts = levelText.replacingOccurrences(of: "，", with: ",").split(separator: ",")
    let values = parts.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard !values.isEmpty, values.count == parts.count, values.count <= 24, values.allSatisfy({ $0.isFinite && abs($0) <= 10 }) else { return nil }
    return Array(Set(values)).sorted()
  }
}

/// 「换一种画法」那一排：一族最多四种，直接摊开摆在表里，点哪个就是哪个。
///
/// 原来是系统 `Picker` 的弹出菜单。样式表起手停在 0.4 屏高，这一行贴着面板下沿，
/// 菜单只能往上弹，靠上的几项（「向右延伸」）落到面板外、压在被调暗的图表上——
/// 模拟器上连 XCTest 都判它「点不到」（2026-09-23）。选项少、字短，摊成一排放得下，
/// 还省掉「先点开菜单」那一下；放不下时（大字号）换成标题在上、一排在下。
/// 选中态和「粗细」那排同一支笔（`ink` 淡底 + 描边），不用强调色，免得和「保存」抢眼。
struct DrawingKindSwapRow: View {
  let swap: Drawing.KindSwap
  @Binding var kind: Drawing.Kind
  @Environment(\.panelTheme) private var theme

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 0) {
        Text(swap.title)
        Spacer(minLength: 8)
        options
      }
      VStack(alignment: .leading, spacing: 8) {
        Text(swap.title)
        options
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("draw.swap")
  }

  private var options: some View {
    HStack(spacing: 4) {
      ForEach(swap.options) { option in
        let on = option.kind == kind
        Button { kind = option.kind } label: {
          Text(option.label)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(on ? theme.ink : theme.ink2)
            .padding(.horizontal, 10)
            .frame(minWidth: 44, minHeight: 34)
            .background(on ? theme.ink.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(on ? theme.ink.opacity(0.55) : .clear, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("draw.swap.\(option.kind.rawValue)")
      }
    }
  }
}

/// 粗细：四条不同粗细的短线，点哪条就是哪条。
///
/// 2026-09-20 用户的话是「非必要这种加减的一律不要出现，非常影响体验」——粗细原来是
/// 0.5…6 步进 0.5 的加减器，十一档里真正用得上的只有几档，还得一下一下按着看。
/// 现在只留四档，选中的那条自己就是样张，不用先读懂数字再想象它多粗。
struct LineWidthPicker: View {
  @Binding var width: Double
  @Environment(\.panelTheme) private var theme
  /// 四档：细、常用、重、最重。存档里别的值（老画线的 1.3）按最近的一档显示。
  static let options: [Double] = [1, 1.5, 2, 3]

  private var selected: Double {
    Self.options.min { abs($0 - width) < abs($1 - width) } ?? Self.options[0]
  }

  var body: some View {
    HStack(spacing: 0) {
      Text("粗细")
      Spacer(minLength: 8)
      ForEach(Self.options, id: \.self) { w in
        Button { width = w } label: {
          RoundedRectangle(cornerRadius: w / 2, style: .continuous)
            .fill(theme.ink)
            .frame(width: 26, height: w)
            .frame(width: 44, height: 34)
            // 选中的记号用皮肤自己的墨色 `ink`，和上面那排色卡的选中圈同一支笔。
            // （原来写的是 `Color.primary`，理由是「这张表是系统 `Form`」——现在这张表
            //   已经接了主题，系统的黑白反而是这一屏上唯一不跟皮肤走的那支。
            //   仍然不用强调色：这四档是样张不是开关，用强调色会和「保存」抢眼。）
            .background(selected == w ? theme.ink.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(selected == w ? theme.ink.opacity(0.55) : .clear, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("粗细 \(w.formatted())")
        .accessibilityAddTraits(selected == w ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("draw.width.\(w.formatted())")
      }
    }
  }
}

/// Shared native picker + one-tap swatches, storing an explicit sRGB hex value.
struct DrawingColorControl: View {
  var title: String
  var identifierPrefix = "color"
  @Binding var color: Hex
  @Environment(\.panelTheme) private var theme
  private let swatches: [Hex] = ["#E2B34F", "#4A90E2", "#A078D0", "#37A78F", "#E46A76", "#D88040", "#B8C4D8"]
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ColorPicker(title, selection: Binding(get: { Color(hex: color) }, set: { color = Self.hex($0) }), supportsOpacity: false)
      ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 4) {
        ForEach(swatches, id: \.self) { hex in
          Button { color = hex } label: {
            Circle().fill(Color(hex: hex)).frame(width: 22, height: 22)
              // 选中圈走皮肤的墨色，不用系统的黑白（同 `LineWidthPicker`）。
              .overlay(Circle().stroke(color == hex ? theme.ink : .clear, lineWidth: 2).padding(-3))
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
/// 画完一笔工具自己退回选择态，本来就是 `continuous == false` 时的行为；长按则把
/// 「连续」打开，同一把工具一直画下去。
///
/// **2026-09-19 改：长按只负责「开」，轻点不再负责「关」。** 这儿原来写着「开关本身
/// 留着不动，它现在同时是这次长按的结果显示」——把画线栏上那个「连续」开关重定义成了
/// 长按的回显，于是用户自己打开连续画之后随手点一下工具，它就自己关了。同一个知识点
/// 不能有两个打架的入口（`kanpan-one-entry-per-action`），而且「我打开了连续画线，
/// 画一条它自己关了」正是「同一个动作两次结果不一样」。现在开关的值只由用户自己动它，
/// 长按是其中一条明确的「打开」路径。
///
/// 按住 0.45s 才算长按，和周期条上「长按钉住」一个数：比系统默认的 0.5s 稍快一点，
/// 又远够不着误触。
extension View {
  func drawRepeatOnLongPress(_ controller: DrawingController, _ kind: Drawing.Kind) -> some View {
    onLongPressGesture(minimumDuration: 0.45) { controller.pick(kind, repeating: true) }
  }
}
