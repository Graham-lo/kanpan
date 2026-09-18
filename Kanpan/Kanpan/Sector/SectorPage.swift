import SwiftUI
import UIKit
import KanpanCore

/// 板块气泡页 ——「釉珠」整页外壳。
///
/// 底栏第四格进来的就是这一张页，它自己不做任何计算：口径在 `KanpanCore`
/// （`SectorAggregator` / `SectorSelector`），球画在 `SectorBubbleField` 里，
/// 记号在 `SectorIcon.swift`，行情由 `SectorFeed` 喂进来。这一层只负责把它们
/// 摆到同一张纸上，再管三段导航。
///
/// 三段，中间不弹任何详情浮层（用户 2026-09-18 定稿）：
///
///   一层气泡（板块）──点一颗─→ 该板块的品种列表 ──点一行─→ 行情页（宿主接手）
///
/// 没上场的板块不在气泡页上另起一块界面，只走右上角「…」→「全部板块」整页清单；
/// 兜底桶只出现在那张清单里，并且和普通板块画得一模一样。
///
/// 两个市场（加密 / 美股）是**硬切换**：各自一套基准、各自的 N/M、各自的尺子、
/// 各自的统计行，永远不共处一屏，也不为美股再开一格底栏。
struct SectorPage: View {
  /// 行情。页面只读它，并在出现 / 消失时开关它的轮询。
  var feed: SectorFeed
  /// 红涨绿跌。球身两头的色相交换只由它决定，别的什么都不改。
  var redUp: Bool
  /// 釉珠的可调参数。默认就是原型定稿那一组。
  var knobs: SectorFieldKnobs = .default
  /// 大写 base → 完整合约代号。板块聚合一路只认 base（分类表里记的就是代号），
  /// 但开行情页要的是 `BTCUSDT` 这样的全名。默认按 USDT 本位拼，宿主手里有品种表，
  /// 传一个照表查的实现能把 USDC 本位那几个也认对。
  var symbolForBase: (String) -> String = { $0 + "USDT" }
  /// 点中一行品种：交出完整 symbol（如 `BTCUSDT`），由 `MainScreen` 切过去。
  var onPickSymbol: (String) -> Void

  @Environment(\.panelTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// 停在哪个市场记在本机——这是「上次看到哪儿」，不是需要跟账号走的偏好。
  @AppStorage("sector.market") private var marketID = SectorMarket.crypto.rawValue
  /// 压在气泡页上面的那几层。空 = 只有球场。最多两层（全部板块 → 某板块的品种列表）。
  @State private var route: [Route] = []
  /// 面积分母的迟滞记忆。
  ///
  /// 它必须活过一次次重画，又不能是 `@State` 的值类型——`snapshot()` 是在 `body`
  /// 里算的，在那儿写 `@State` 会把视图再拍一遍。装在一个不被观察的盒子里，
  /// 只当上一次的读数用。换市场时清空：两个市场各有各的尺子。
  @State private var scaleMemo = ScaleMemo()

  private final class ScaleMemo { var value: Double? }

  private enum Route: Equatable {
    case all
    case list(String)
  }

  private var skin: SectorSkin { SectorSkin(theme: theme) }
  private var market: SectorMarket { SectorMarket(rawValue: marketID) ?? .crypto }

  // MARK: - 口径

  /// 这一屏的全部算料。一次算齐，三层共用——聚合和兜底桶都不便宜，
  /// 不能让每个子视图各算一遍。
  private struct Snapshot {
    /// 当前市场的板块统计（含兜底桶）。
    var stats: [SectorStat]
    /// 上场的那几颗。`SectorSelector` 自己会把兜底桶摘掉，气泡场吃不到它们。
    var selection: SectorSelection
    /// 当前市场、去重之后真有行情的品种数。
    var covered: Int
    /// 兜底桶，用来在下钻时还原成员名单。
    var buckets: [SectorFallbackBucket]
  }

  private func snapshot() -> Snapshot {
    let market = market
    let buckets = feed.fallbackBuckets(for: market)
    let quotes = feed.quotes
    let stats = SectorAggregator.stats(market: market, quotes: quotes, fallbackBuckets: buckets)
    // N/M 按市场取各自的默认档（加密 5+3、美股 3+2）。上一次的尺子传进去做迟滞。
    let selection = SectorSelector.select(stats, market: market, previousScale: scaleMemo.value)
    scaleMemo.value = selection.scalePct
    // 统计行里那个「品种」数不能拿各板块成员数相加——一个品种可以同时属于好几个
    // 板块（允许交叉归属），加起来会比实际多出一大截。这儿数的是去重之后、
    // 当前真有行情的那些。
    var seen = Set<String>()
    for def in SectorCatalog.sectors(market) {
      for base in def.members where quotes[base] != nil { seen.insert(base) }
    }
    for bucket in buckets {
      for base in bucket.members where quotes[base] != nil { seen.insert(base) }
    }
    return Snapshot(stats: stats, selection: selection, covered: seen.count, buckets: buckets)
  }

  var body: some View {
    let snap = snapshot()
    return ZStack {
      fieldLayer(snap)
      if route.contains(.all) {
        SectorAllSheet(stats: snap.stats.sorted { $0.pct > $1.pct },
                       onBack: pop, onPick: { push(.list($0.id)) })
          .transition(.opacity)
      }
      if let id = listedSector {
        listLayer(id, snap).transition(.opacity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { SectorBackdrop(skin: skin, reduceMotion: reduceMotion).ignoresSafeArea() }
    .tint(theme.amber)
    // 只是一层淡入淡出。弹跳、抖动、回弹一概没有。
    .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: route)
    .accessibilityIdentifier("sector.page")
    .onAppear { feed.setVisible(true) }
    .onDisappear { feed.setVisible(false) }
  }

  /// 最上面那一层如果是品种列表，是哪个板块。
  private var listedSector: String? {
    guard let last = route.last, case .list(let id) = last else { return nil }
    return id
  }

  // MARK: - 第一层：顶栏 + 统计行 + 球场

  private func fieldLayer(_ snap: Snapshot) -> some View {
    VStack(spacing: 0) {
      header(snap)
      SectorBubbleField(selection: snap.selection, knobs: knobs, redUp: redUp,
                        onPick: { push(.list($0.stat.id)) })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  /// 顶栏一行：标题 + 市场硬切换 +「…」，统计行贴在标题右边。
  ///
  /// 统计行照原型 `paintHeader()`：`N / M 板块 · K 品种`。这不是取数状态，
  /// 是这一屏自己的规模——上场几颗、一共几个板块、盖住了多少品种。
  ///
  /// 聚合口径那行药丸 2026-09-18 整行撤了：板块只有中位数一个口径，
  /// 不再让用户挑（也不退进「…」菜单）。
  private func header(_ snap: Snapshot) -> some View {
    HStack(spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 9) {
        Text("板块").font(skin.serif(21)).tracking(1.26).foregroundStyle(theme.ink)
        Text("\(snap.selection.picks.count) / \(snap.stats.count) 板块 · \(snap.covered) 品种")
          .font(.system(size: 10.5, design: .monospaced)).tracking(0.63)
          .foregroundStyle(skin.ink4)
          .lineLimit(1).minimumScaleFactor(0.8)
      }
      Spacer(minLength: 0)
      marketSwitch
      moreButton
    }
    .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 2)
  }

  /// 市场硬切换。两个市场永远不共处一屏，换一格就是换一整套尺子。
  private var marketSwitch: some View {
    HStack(spacing: 2) {
      marketTab(.crypto, "加密")
      marketTab(.us, "美股")
    }
    .padding(2)
    .background {
      Capsule().fill(skin.well)
        .overlay(Capsule().strokeBorder(skin.rule, lineWidth: 0.5))
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("sector.market")
  }

  private func marketTab(_ value: SectorMarket, _ title: String) -> some View {
    let on = market == value
    return Button {
      guard !on else { return }
      marketID = value.rawValue
      // 换市场就是换一整套尺子，上一档的分母不能带过去。
      scaleMemo.value = nil
      route.removeAll()
    } label: {
      Text(title).font(.system(size: 12)).tracking(0.48)
        .foregroundStyle(on ? Color.white : theme.ink3)
        .padding(.horizontal, 11).frame(height: 26)
        .background {
          if on {
            Capsule().fill(skin.accentGradient)
              .overlay(alignment: .top) { skin.topHighlight(inset: 7) }
              .shadow(color: skin.accent.opacity(skin.dark ? 0.45 : 0.32), radius: 5, x: 0, y: 2)
          }
        }
        .contentShape(Capsule())
    }.buttonStyle(.plain)
      .accessibilityLabel(title)
      .accessibilityAddTraits(on ? .isSelected : [])
      .accessibilityIdentifier("sector.market." + value.rawValue)
  }

  /// 右上角那颗「…」：没上场的板块只有这一条路。
  private var moreButton: some View {
    Button { push(.all) } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 14, weight: .medium)).foregroundStyle(theme.ink2)
        .frame(width: 30, height: 30)
        .background(skin.well, in: Circle())
        .overlay(Circle().strokeBorder(skin.rule, lineWidth: 0.5))
        .frame(width: 40, height: 40)
        .contentShape(Rectangle())
    }.buttonStyle(.plain)
      .accessibilityLabel("全部板块")
      .accessibilityIdentifier("sector.more")
  }

  // MARK: - 第三层：某个板块的品种列表

  /// 成员名单从分类表（或兜底桶）取，行情从 `feed` 取。板块本身要是整个没了行情
  /// （`stats` 里找不到它），就没有可看的东西，直接退回上一层——与其画一张空壳，
  /// 不如把人放回去。
  @ViewBuilder private func listLayer(_ id: String, _ snap: Snapshot) -> some View {
    if let stat = snap.stats.first(where: { $0.id == id }) {
      SectorSymbolList(stat: stat, members: members(of: id, snap), quotes: feed.quotes,
                       symbolForBase: symbolForBase,
                       onBack: pop, onPick: onPickSymbol)
    } else {
      Color.clear.onAppear { pop() }
    }
  }

  private func members(of id: String, _ snap: Snapshot) -> [String] {
    if let def = SectorCatalog.sector(id: id) { return def.members }
    return snap.buckets.first { $0.id == id }?.members ?? []
  }

  private func push(_ layer: Route) {
    guard route.last != layer else { return }
    route.append(layer)
  }

  private func pop() {
    guard !route.isEmpty else { return }
    route.removeLast()
  }
}

// MARK: - 派生色板

/// 板块页用到的材质与光，全部从当前皮肤推出来——这一页不写死任何一支颜色。
///
/// 口径照 `FavoritesView` 的「琉璃」：同一张底、同一根发丝线、同一档墨色，
/// 第二层的品种列表才和自选页读成同一页纸。差别只在光斑取色：自选页浅色下借的是
/// 一组写死的「天青·薄荷」，这一页按契约一律从种子推（原型 `#ground` 用的也正是
/// `--acc` / `--accB` / `--gold` 三支）。
struct SectorSkin {
  let theme: PanelTheme
  var seed: PaletteSeed { theme.seed }
  var dark: Bool { theme.dark }

  /// 深色下画不画那几团光。
  ///
  /// 原型的深色底是有强调色光晕的，但用户看过真机之后点名把自选页深色那两团去掉了
  /// （「深色模式下有两个光晕影响视觉，直接去掉」）。这一页的第二层要和自选页读成
  /// 同一张纸，所以两页一起守这条：深色只留素底加颗粒。
  static let lobesInDark = false

  /// 整页的底。取法和自选页一字不差：深色与经典白用 `ground`，青苔 / 陶土的浅色
  /// 用 `app` 那张暖白 / 冷白（自选页那两支是为「琉璃」单调的字面色，这一页按契约
  /// 只能从种子取，色相同族、明度相近）。
  var ground: Color { Color(hex: dark || Palette.isClassic(seed) ? seed.ground : seed.app) }

  /// 三团光。只在浅色下画，颜色是强调色与暖色**提到很淡**的一档——原型 `#ground`
  /// 用的就是 `--acc` / `--accB` / `--gold` 这三支，自选页浅色下那三支柔和的
  /// 天青、薄荷、淡蓝是同一个意思的手调版。直接拿饱和的强调色铺 63% 会把整页染绿，
  /// 所以先 `lift` 到接近白再铺。
  var lobes: [Color] {
    [Self.lift(seed.accent, 0.78), Self.lift(seed.amber, 0.82), Self.lift(seed.accent, 0.9)]
  }
  /// 列表不再垫玻璃之后光斑直接穿过文字，整体收 30%。和自选页同一个系数。
  func lobeOpacity(_ index: Int) -> Double { 0.9 * 0.7 }
  /// 底部同色收敛：从 22% 高度起往下渐渐回到底色，文字压在光斑上也读得清。
  var washStrength: Double { 0.7 }
  var grainOpacity: Double { dark ? 0.05 : 0.035 }

  var accent: Color { Color(hex: seed.accent) }
  var accentLift: Color { Self.lift(seed.accent, 0.42) }
  /// 液态药丸：提亮的强调 → 强调。
  var accentGradient: LinearGradient {
    LinearGradient(colors: [accentLift, accent], startPoint: .topLeading, endPoint: .bottomTrailing)
  }

  /// 玻璃：深色借近白的墨色，浅色借 `raised`（浅色种子的 raised 都是白）。
  private var pane: Color { Color(hex: dark ? seed.ink : seed.raised) }
  /// 圆按钮与分段器的槽（原型 `.mkt` / `.more` / `.back`）。
  var well: Color { Color(hex: seed.ink).opacity(dark ? 0.055 : 0.06) }
  /// 半像素的边、行与行之间那根发丝线。
  var rule: Color { Color(hex: seed.ink).opacity(dark ? 0.11 : 0.09) }
  /// 选中那颗药丸的底与边（原型 `.chip[aria-selected]`）。
  var chipOn: Color { Color(hex: dark ? seed.ink : seed.raised).opacity(dark ? 0.08 : 0.7) }
  var chipEdge: Color { Color(hex: dark ? seed.ink : seed.line).opacity(dark ? 0.165 : 1) }
  /// 比 ink3 再弱一档，给单位、微标签、统计行。
  var ink4: Color { Color(hex: seed.ink3).opacity(0.7) }

  /// 玻璃顶上那一线高光。
  func topHighlight(inset: CGFloat) -> some View {
    Capsule().fill(pane.opacity(dark ? 0.3 : 0.9))
      .frame(height: 1).padding(.horizontal, inset)
  }

  /// 标题字体。和自选页同一支：iOS 装机里没有可用的简体中文衬线体，
  /// `.serif` 让拉丁走 New York、中文走系统字，靠字号与字距把标题撑起来。
  func serif(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .serif) }

  /// 往亮里提一档：色相不动，饱和收一点、明度往上走。
  private static func lift(_ hex: Hex, _ amount: Double) -> Color {
    let rgba = hex.rgba
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(red: rgba.r, green: rgba.g, blue: rgba.b, alpha: 1)
      .getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    return Color(hue: Double(h), saturation: Double(s) * (1 - amount * 0.6),
                 brightness: Double(b) + (1 - Double(b)) * amount)
  }
}

// MARK: - 底：一块连续的材料

/// 板块页三层共用的底。
///
/// 气泡场、品种列表、全部板块都铺这一张——上层盖下来时换的是内容不是纸，
/// 整屏从头到脚读成同一块材料，上下不出拼缝。
struct SectorBackdrop: View {
  let skin: SectorSkin
  let reduceMotion: Bool
  @State private var drift = false

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      let height = geometry.size.height
      ZStack(alignment: .topLeading) {
        skin.ground
        if !skin.dark || SectorSkin.lobesInDark {
          lobe(0, size: 300, x: -95, y: -80, seconds: 22)
          lobe(1, size: 250, x: width - 170, y: 240, seconds: 27)
          lobe(2, size: 280, x: -70, y: height - 230, seconds: 31)
          LinearGradient(stops: [
            .init(color: skin.ground.opacity(0), location: 0.22),
            .init(color: skin.ground.opacity(skin.washStrength), location: 1)],
            startPoint: .top, endPoint: .bottom)
            .frame(width: width, height: height)
        }
        if let grain = SectorGrain.image {
          grain.resizable(resizingMode: .tile).opacity(skin.grainOpacity)
        }
      }
      .frame(width: width, height: height)
      .clipped()
    }
    .allowsHitTesting(false)
    .onAppear { if !reduceMotion { drift = true } }
  }

  /// 漂移只动 `offset` / `scale`，交给渲染层去跑，不会让上面的列表每帧重建。
  private func lobe(_ index: Int, size: CGFloat, x: CGFloat, y: CGFloat, seconds: Double) -> some View {
    let color = skin.lobes[index]
    let peak = skin.lobeOpacity(index)
    return RadialGradient(
      gradient: Gradient(stops: [
        .init(color: color.opacity(peak), location: 0),
        .init(color: color.opacity(peak * 0.55), location: 0.45),
        .init(color: color.opacity(0), location: 1)]),
      center: .center, startRadius: 0, endRadius: size / 2)
      .frame(width: size, height: size)
      .scaleEffect(drift ? 1.08 : 1)
      .offset(x: x + (drift ? 18 : 0), y: y + (drift ? -26 : 0))
      .animation(reduceMotion ? nil
                 : .easeInOut(duration: seconds).repeatForever(autoreverses: true), value: drift)
  }
}

/// 一张 96×96 的灰噪点，平铺当颗粒。只生成一次。
@MainActor enum SectorGrain {
  static let image: Image? = {
    let side = 96
    var bytes = [UInt8](repeating: 0, count: side * side)
    var state: UInt64 = 0x2545_F491_4F6C_DD1D
    for index in bytes.indices {
      state ^= state << 13
      state ^= state >> 7
      state ^= state << 17
      bytes[index] = UInt8(truncatingIfNeeded: state >> 33)
    }
    guard let provider = CGDataProvider(data: Data(bytes) as CFData),
          let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8,
                              bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                              provider: provider, decode: nil, shouldInterpolate: false,
                              intent: .defaultIntent) else { return nil }
    return Image(decorative: image, scale: 1)
  }()
}

// MARK: - 三层共用的零件

/// 左上角那颗返回。原型 `.back`：30 的圆片挂在 40 的可点区里。
struct SectorBackButton: View {
  let skin: SectorSkin
  let id: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "chevron.left")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(skin.theme.ink2)
        .frame(width: 30, height: 30)
        .background(skin.well, in: Circle())
        .overlay(Circle().strokeBorder(skin.rule, lineWidth: 0.5))
        .frame(width: 40, height: 40)
        .contentShape(Rectangle())
    }.buttonStyle(.plain)
      .accessibilityLabel("返回")
      .accessibilityIdentifier(id)
  }
}

/// 行与行之间那根两端渐隐的发丝线。照抄自选页。
struct SectorHairline: View {
  let skin: SectorSkin

  var body: some View {
    LinearGradient(colors: [.clear, skin.rule, skin.rule, .clear],
                   startPoint: .leading, endPoint: .trailing)
      .frame(height: 0.5).padding(.horizontal, 20)
  }
}

/// 涨跌小三角。
struct SectorTriangle: Shape {
  let up: Bool

  func path(in rect: CGRect) -> Path {
    var path = Path()
    if up {
      path.move(to: CGPoint(x: rect.midX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    } else {
      path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    }
    path.closeSubpath()
    return path
  }
}

/// `+1.23%` / `-0.45%`，两位小数带符号。
func sectorPctText(_ value: Double) -> String {
  guard value.isFinite else { return "—" }
  return (value >= 0 ? "+" : "") + toFixed(value, 2) + "%"
}
