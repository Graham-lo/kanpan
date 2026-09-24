import CoreGraphics
import Foundation
import KanpanCore
import UIKit

// 主力订单流 · 图表这一层（照 CoinAnk「主力大额挂单」的横向价格带；2026-09-24 晚改手机布局）。
//
// 只画、不判定：拿到的是 `state.orderFlow`（KanpanData 的 OrderFlowFeed 算好的逐单集合，
// 还挂着的 + 已结束的），这里只管换算成横向价格带、图例「主力」一行、带上的金额标签，
// 以及轻点 / 十字线选中的那一条（描边 + 交给 app 出详情卡）。
//
// 手机布局（用户：「都挤在一起，有没有适合手机的布局设计展示」——BTC 十三本簿同时出单，
// 一单一条在 1 分钟图右缘叠成一堵墙）：
//   1. **一堵墙一条**：同一价位桶、同一侧、同一类（现货 / 合约）、时间上连成一段的单合成一段；
//      四种合约（币安 U 本位 / 币本位 / 交割、OKX 永续）是一条「合约」带，三家现货是一条「现货」带。
//      时间上断开（空档超过 max(60 秒, 一根 K 线)）就另起一段——不把空档画成墙（`OrderFlowGroup.segments`）。
//      已结束、活不过一根 K 线的段去掉（碎屑；挂着的一律留）。再把同侧同类、桶号相邻、时间上连着的段并成一堵墙
//      （2026-09-25，`OrderFlowGroup.walls`）：ETH / SOL 一堵墙在簿上摊在相邻几个桶里，不再画成几条各写各的金额。
//      左缘 = 墙里最早首见那根 K 线的左缘；右缘 = 最晚结束那根的右缘，有一单还挂着就画到主图右缘。
//   2. **按屏内排名分主次**（2026-09-25，不按门槛倍数）：横向落在这一屏、价位落在主图里的墙按画法名义从大到小排
//      （一样的先起的在前）：前 6 名「主」、第 7–18 名「次」、其余「底噪」。还挂着的墙升一级（底噪 → 次；主的名额
//      不因挂着多给）。每帧现排，结果确定。门槛调低、一屏几百条的时候，眼睛先看到的仍是这一屏最大的六堵。
//   3. **细线 + 签，垫在 K 线下面**（2026-09-25 用户看真机：「大单不许盖住 K 线，K 线是主体」「是颜色重合了把 K 线覆盖了」）：
//      首版是实心色带（粗细五档 2–8 pt，跨桶的盖住整个价位范围），压在同色蜡烛上融成一片。改成线只表示在场区间：
//      主 2 pt（还挂着的主 2.5 pt，最粗就到这儿）、次 1 pt 70%、底噪 1 pt 35%；名义大小不再靠加粗表达，
//      只体现在排名（主次）与金额签上。跨桶的墙只画代表价上一条芯线（按主的线粗），价位范围（最低桶价 …
//      最高桶价 + 步长）用段右端一枚细竖括号「]」表达：宽 3 pt、高 = 范围在屏上的高度、段色 70%；挂着的紧贴金额签
//      左侧，已结束的落在结束点处（`orderFlowBracket`）。第三版曾在整个范围垫 10% 淡底：经典深底上一堵 300 美元的墙
//      淡底铺满大半张图、另一堵叠在下半屏，整张图染成紫色，读起来像 K 线又被盖了（2026-09-25 验收），改成括号。
//      范围数字写在详情卡上。
//   4. **纵向去挤**（主、次）：按排名落线；和已落下的横向有交叠、纵向重叠（含 1 pt 间隙）的排名更后的线压成 1 pt
//      细线、不写金额——不平移、不改价位。底噪不参与。画的先后：底噪 → 整条 → 细线。
//      线细了命中区不跟着细：轻点、十字线都按至少 8 pt 高的带子算（`orderFlowHitHeight`），轻点再放到 44 pt。
//   5. **金额签**：只给「主」里没被压细的：还挂着的贴主图右缘（价格刻度列左侧、不进刻度列），已结束的放在
//      结束点右侧；签底是线色 85% 不透明、字色在近黑与白之间取对叠出来的颜色对比度高的那个（`orderFlowLabelInk`，
//      六套皮肤 × 四色 × 深浅两档都 ≥ 4.5:1，测试守着）；一屏最多 6 枚（`orderFlowLabelMax`）；
//      11 pt medium 等宽（HIG 下限，同 app 的 `TypeScale.caption2Emph`）、高 16、左右 4、圆角 4、签间至少 2。
//      签之间纵向撞了按名义让位：名义小的挪到撞上那枚的上方或下方（离自己的线最多 32 pt），挪不开就不放。
//      签画在 crossLayer：金额每拍都在抖，不能拖着底图重画（审查 31）。
//   5b. **颜色**（2026-09-25 改）：不再用皮肤涨跌色——合约的买卖单拿 `t.up / t.down` 画，压在同色蜡烛上就看不见。
//      K 线涨跌在全部六套种子里是绿 134°–165°、红 356°–6°，离两者都 ≥ 60° 的色相只剩黄（≈ 66°–74°）和
//      蓝—品红（≈ 225°–294°）两段，所以四色这样分（深底 / 浅底各一支，`Palette.orderFlowOnDark / OnLight`）：
//        合约买 = 蓝（深 #5A7DFF 227° / 浅 #0A78C2 204°）、合约卖 = 品红（深 #E04BF0 294° / 浅深梅 #8A149F 291°）——
//        合约是主角，买卖两色相差 67° / 87°；
//        现货买 = 黄（深 #CCE21E 67° / 浅橄榄黄 #76850A 67°）、现货卖 = 紫（深淡紫 #B89CFF 257° / 浅 #8566E8 254°）。
//      紫夹在蓝与品红之间（色相各差 30°–50°），靠明度拉开（两两对比 ≥ 1.44）。对图区底色全部 ≥ 3.8:1；
//      经典深底是深蓝 #0D111C，蓝选的是亮的一支（5.2:1）。守卫在 SkinPaletteTests（`orderFlowColors`）。
//      深浅两档：任何一单被吃过（成交名义 > 0）是本色；一口没成交往图区底色混 45%。红涨绿跌不影响这四色。
//   6. 显示开关（`state.orderFlowDisplay`）逐单过滤后再合并；图例「主力 买 X · 卖 Y」仍按逐单求和。
//
// 选中（`ChartOrderFlowFocus`）：十字线停在一条带上，或者轻点选中了一条（`state.orderFlowSelected`，
// 存的是那堵墙的 `OrderFlowGroupKey`——墙里最早那一段的键，含段的起点；墙续长、并进后来的段都不变，
// 并进更早的段按 `OrderFlowGroup.covers` 认回来）。选中的那条在 crossLayer 上重画一遍并描 1 pt 正文色边，
// app 按它出「一段一卡」的详情卡；这时图里的开高低收框不画。
//
// 层序（2026-09-25 改）：`draw` 在网格之后、蜡烛之前调 `drawOrderFlow`——线与范围括号垫在蜡烛、均线、画线、
// 最新价（liveLayer）下面，副图（成交量等）本来就不画大单。选中那一条（描边重画）、金额签、图例画在 crossLayer。几何（`orderFlowFrame`）按（快照、显示开关、
// 视野、布局）缓存一份，两层共用（`OrderFlowCache`）。比价（百分比坐标）与横屏画线台不画。

/// 此刻被选中的那一条合并带，交给 app 出详情卡。坐标都是图表视图坐标（pt）。
public struct ChartOrderFlowFocus: Sendable, Equatable {
  /// 最新快照里的这一段（金额、状态随快照更新）。
  public var group: OrderFlowGroup
  /// true = 轻点选中；false = 十字线停在上面。
  public var selected: Bool
  /// 卡片躲开的横坐标：十字线的 x，或选中那条带可见段的中点。
  public var anchorX: Double
  /// 这条带的中线 y 与半高（卡片不能盖住它）。
  public var bandY: Double
  public var bandHalf: Double
  public var plotW: Double
  /// 主图里能摆卡片的那一段：上沿是图例下沿 + 4，下沿是主图下沿（都是图坐标 y）。
  public var mainTop: Double
  public var mainBottom: Double
  /// 主图整块的高（卡高上限按它的 55% 算）。
  public var mainHeight: Double
  /// 快照时刻（还挂着的单算持续时长用）。
  public var asOfMs: Int64

  public init(group: OrderFlowGroup, selected: Bool, anchorX: Double, bandY: Double, bandHalf: Double, plotW: Double,
              mainTop: Double, mainBottom: Double, mainHeight: Double, asOfMs: Int64) {
    self.group = group; self.selected = selected; self.anchorX = anchorX; self.bandY = bandY; self.bandHalf = bandHalf
    self.plotW = plotW; self.mainTop = mainTop; self.mainBottom = mainBottom; self.mainHeight = mainHeight
    self.asOfMs = asOfMs
  }

  /// 卡片最宽多少、摆在带上还是带下、最高多少（`OrderFlowCardBudget`）。
  public var cardMaxWidth: Double { OrderFlowCardBudget.maxWidth(plotW: plotW) }
  public var cardPlacement: (below: Bool, maxHeight: Double) {
    OrderFlowCardBudget.placement(bandY: bandY, bandHalf: bandHalf, top: mainTop, bottom: mainBottom, mainHeight: mainHeight)
  }
}

extension ChartRenderer {
  /// 一条要画的合并带。
  struct OrderFlowBand: Equatable {
    let group: OrderFlowGroup
    let frame: CGRect
    let color: Hex
    /// 深色（被吃过）还是浅色（一口没成交）。
    let dark: Bool
    /// 被排名更前的线挤成了 1 pt 细线（不写金额）。
    let thin: Bool
    /// 屏内排名的主次。
    let role: OrderFlowRole
    /// 不透明度（主 1、次 0.7、底噪 0.35）。
    let alpha: Double
    /// 跨几个桶的「主」墙的价位范围括号「]」（最低桶价 … 最高桶价 + 步长在屏上的高度，宽 3 pt）：挂着的紧贴金额签
    /// 左侧、已结束的在结束点处，段色 70%（`orderFlowBracketAlpha`），在蜡烛下面、不占位；`frame` 是代表价上那条芯线。
    /// 单桶、次、底噪、被压细的、范围比芯线还窄的没有。
    let bracket: CGRect?
    var key: OrderFlowGroupKey { group.key }

    init(group: OrderFlowGroup, frame: CGRect, color: Hex, dark: Bool, thin: Bool, role: OrderFlowRole = .main,
         alpha: Double = 1, bracket: CGRect? = nil) {
      self.group = group; self.frame = frame; self.color = color; self.dark = dark; self.thin = thin
      self.role = role; self.alpha = alpha; self.bracket = bracket
    }
  }

  /// 屏内排名的主次：前 6 名主、第 7–18 名次、其余底噪（还挂着的底噪升成次）。
  enum OrderFlowRole: String, Equatable {
    case main, secondary, noise
  }

  /// 带右端的金额小签。
  struct OrderFlowLabel: Equatable {
    let key: OrderFlowGroupKey
    let text: String
    let frame: CGRect
    let fill: Hex
    let ink: Hex
  }

  struct OrderFlowFrame: Equatable {
    /// 画的先后排好的线：底噪在前，整条的其次（彼此不重叠），细线在后。
    var bands: [OrderFlowBand] = []
    var labels: [OrderFlowLabel] = []
    /// 可视区里还挂着（且开着显示）的大单各侧合计（逐单求和）。
    var bidTotal = 0.0
    var askTotal = 0.0
  }

  /// 按 pane / 价格区间 / 主图宽记一份色带几何（不含十字线与选中）。盒子在 `recalc` 里随输入、视野、
  /// 快照、显示开关一起换新，十字线动、选中换只换 `state.overlay`、盒子留着——plot 与 cross
  /// 两层画同一帧时也只算一遍。
  final class OrderFlowCache {
    var entries: [(pane: Pane, range: PriceRange, plotW: Double, frame: OrderFlowFrame)] = []
    /// 真算了几次（测试核对缓存有没有生效）。
    var computed = 0
  }

  /// 浅色档（一口没成交）往图区底色混的比例上限（对底不足 3:1 时少混）。
  static let orderFlowLightMix = 0.45
  /// 线粗（pt）：主 2、还挂着的主 2.5（最粗）、次与底噪 1、被挤的细线 1。
  static let orderFlowMainLine = 2.0
  static let orderFlowMainLiveLine = 2.5
  static let orderFlowSecondaryLine = 1.0
  static let orderFlowNoiseLine = 1.0
  static let orderFlowThinLine = 1.0
  /// 不透明度：主 1、次 0.7、底噪 0.35。
  static let orderFlowSecondaryAlpha = 0.7
  static let orderFlowNoiseAlpha = 0.35
  /// 跨桶主墙的价位范围括号「]」：宽 3 pt（竖笔与上下两个钩都是 1.5 pt）、段色 70%，和金额签之间留 1 pt。
  /// 首版把整个范围画成实心：BTC 1 分钟图上一堵 5 桶（500 美元）的墙高 213 pt、盖住三分之一张图的 K 线；第二版 16% 淡色
  /// + 实心芯仍压在蜡烛上面；第三版垫到蜡烛下面、10% 淡底，经典深底上两堵墙把整张图染成紫色（2026-09-25 验收）。
  /// 所以范围不再铺面，只在段右端立一枚括号。
  static let orderFlowBracketWidth = 3.0
  static let orderFlowBracketStroke = 1.5
  static let orderFlowBracketAlpha = 0.7
  static let orderFlowBracketGap = 1.0
  /// 一屏几名「主」、主加次一共几名（第 7–18 名是次）。
  static let orderFlowMainCount = 6
  static let orderFlowRankedCount = 18
  /// 判「纵向重叠」时两条线之间至少要留的空。
  static let orderFlowGap = 1.0
  /// 金额小签（2026-09-25 按 HIG 整改口径，原 8.5 pt / 高 11 / 左右 3 / 圆角 2 / 离右端 1 都不合规）：
  /// 11 pt medium 等宽（下限 11，对应 app 的 `TypeScale.caption2Emph`；常驻一只实例，`ChartFont` 的缓存按字体身份做键）、
  /// 高 16、左右各留 4（`Space.xs`）、圆角 4（`Radius.xs`）、离主图右缘 / 结束点 4、签与签之间至少 2（`Space.xxs`）。
  /// 签底半透明（85%），压到蜡烛上时还隐约透得出底下的 K 线。一屏最多 6 枚（主档就 6 名）。图表包拿不到 app 的令牌，
  /// 数值在这里照抄。
  static let orderFlowLabelFont = UIFont.monospacedSystemFont(ofSize: 11, weight: .medium)
  static let orderFlowLabelHeight = 16.0
  static let orderFlowLabelPadX = 4.0
  static let orderFlowLabelInset = 4.0
  static let orderFlowLabelRadius = 4.0
  static let orderFlowLabelGap = 2.0
  static let orderFlowLabelAlpha = 0.85
  static let orderFlowLabelMax = 6
  /// 签让位时离自己的线最多挪多远（两枚签高）；再远就读不出是哪条线的，不放。
  static let orderFlowLabelMaxShift = 32.0
  /// 命中区按至少这么高的带子算：线细了（1–2.5 pt）命中区不跟着细（2026-09-25）。
  static let orderFlowHitHeight = 8.0
  /// 十字线的竖向容差：离带边（按上面那个高算）不超过 8 pt；横向两头各放 4 pt。
  static let orderFlowHitSlop = 8.0
  static let orderFlowHitSlopX = 4.0
  /// 手指轻点的命中区至少 44 × 44 pt（HIG，2026-09-25）：带细、结束得早的带窄，
  /// 轻点时竖向容差放到 (44 − 带高) / 2、横向放到 (44 − 带宽) / 2（都不小于上面十字线那两个）。
  /// 几条带的命中区叠在一起时仍按离得最近的给，所以放宽不会点错条，只是空白处离线 22 pt 以内点下去算点中。
  static let orderFlowTouchTarget = 44.0

  /// 这一帧要不要画主力订单流：快照属于当前品种、不在比价模式。
  var orderFlowSnapshot: OrderFlowSnapshot? {
    guard let flow = state.orderFlow, !state.percentAxis,
          InstrumentID.canonical(flow.symbol) == InstrumentID.canonical(state.symbol.symbol) else { return nil }
    return flow
  }

  /// 本色（深色档）：合约买蓝、卖品红，现货买黄、卖紫；不跟皮肤涨跌色（见文件头第 5b 条）。
  func orderFlowBaseColor(side: BookSide, contract: Bool) -> Hex {
    let p = Palette.orderFlow(bg: state.colors.bg)
    return contract ? (side == .bid ? p.contractBid : p.contractAsk) : (side == .bid ? p.spotBid : p.spotAsk)
  }

  func orderFlowBaseColor(_ order: BigOrder) -> Hex {
    orderFlowBaseColor(side: order.side, contract: order.product.isContract)
  }

  /// 画出来的颜色：被吃过是本色，一口没成交往图区底色混（最多 45%，混完对底仍 ≥ 3:1，
  /// 见 `Palette.orderFlowUnfilled`——一律混 45% 的话浅底蔚蓝只剩 2.2:1，大多数单都没成交，等于整屏看不清）。
  func orderFlowColor(side: BookSide, contract: Bool, hasFill: Bool) -> Hex {
    let base = orderFlowBaseColor(side: side, contract: contract)
    return hasFill ? base : Palette.orderFlowUnfilled(base, bg: state.colors.bg, maxMix: Self.orderFlowLightMix)
  }

  func orderFlowColor(_ order: BigOrder) -> Hex {
    orderFlowColor(side: order.side, contract: order.product.isContract, hasFill: order.hasFill)
  }

  func orderFlowColor(_ group: OrderFlowGroup) -> Hex {
    orderFlowColor(side: group.side, contract: group.contract, hasFill: group.hasFill)
  }

  /// 图区底色是不是浅色（按亮度，不认皮肤名：六套种子各自的底色说了算）。
  static func isLightBackground(_ bg: Hex) -> Bool {
    let v = bg.rgba
    return 0.2126 * v.r + 0.7152 * v.g + 0.0722 * v.b > 0.5
  }

  /// 小签上的字色：近黑与白里对 `fill`（签底叠到图区底色上之后的颜色）对比度高的那个；两个都不到 4.5:1
  /// （中间亮度的品红一带，近黑 4.3、白 4.3）就用纯黑——白不到 4.5 时纯黑一定过 4.6。原来按亮度 0.5 一刀切，
  /// 深底蔚蓝 #5A7DFF 会取到白、只有 3.6:1。
  static func orderFlowLabelInk(_ fill: Hex) -> Hex {
    let dark = Palette.contrast("#141414", fill), light = Palette.contrast("#FFFFFF", fill)
    if max(dark, light) < 4.5 { return "#000000" }
    return dark >= light ? "#141414" : "#FFFFFF"
  }

  /// 金额签的横向落点（纵向让位不改它）：挂着的贴主图右缘（刻度列左侧），已结束的在结束点右侧、放不下收回主图右缘以内。
  static func orderFlowLabelX(live: Bool, lineRight: Double, width w: Double, plotW: Double) -> Double {
    let edge = plotW - orderFlowLabelInset - w
    return live ? edge : min(lineRight + orderFlowLabelInset, edge)
  }

  /// 跨桶主墙的范围括号：右缘紧贴金额签的横向落点左侧（留 1 pt）——挂着的就在签左边，已结束的正好落在结束点处
  /// （签在结束点右侧 4 pt）；这一枚签因为让位没放下也照样画在那儿。纵向是整个价位范围 `top … bottom`。
  static func orderFlowBracket(live: Bool, lineRight: Double, labelWidth w: Double, plotW: Double,
                               top: Double, bottom: Double) -> CGRect {
    let right = orderFlowLabelX(live: live, lineRight: lineRight, width: w, plotW: plotW) - orderFlowBracketGap
    return CGRect(x: right - orderFlowBracketWidth, y: top, width: orderFlowBracketWidth, height: bottom - top)
  }

  /// 金额签的宽：字宽 + 左右各 4。
  static func orderFlowLabelWidth(_ text: String) -> Double {
    Double(text.width(orderFlowLabelFont)) + 2 * orderFlowLabelPadX
  }

  /// 色带几何。同一份 state、同一套 pane / range / layout 给同一个结果。
  func orderFlowFrame(pane: Pane, range: PriceRange, L: Layout) -> OrderFlowFrame {
    orderFlowBands(pane: pane, range: range, L: L)
  }

  /// 色带几何，按 pane / range / plotW 走缓存。
  func orderFlowBands(pane: Pane, range: PriceRange, L: Layout) -> OrderFlowFrame {
    let cache = orderFlowCache
    if let hit = cache.entries.first(where: { $0.pane == pane && $0.range == range && $0.plotW == L.plotW }) {
      return hit.frame
    }
    let value = computeOrderFlowBands(pane: pane, range: range, L: L)
    cache.computed += 1
    if cache.entries.count >= 4 { cache.entries.removeFirst() }
    cache.entries.append((pane, range, L.plotW, value))
    return value
  }

  /// 一个点落在哪条带上。线只有 1–2.5 pt，命中按「以线为中线、至少 8 pt 高的带子」算（`orderFlowHitHeight`）。
  /// 横向落在带里（两头各放 4 pt）为前提：
  ///   1. 点在某条带（按命中高）的范围里（上下各放 0.5 pt）：离线最近的那条；一样近（同一价位上叠着）取名义大的，
  ///      再一样取画在上面的——被压细的小单和大单同价时，点下去出的是那堵大的（它才是这一价位上的主角）；
  ///   2. 否则离带边不超过 8 pt（轻点时放到命中区 44 pt，见 `orderFlowTouchTarget`）的里面取离得最近的；
  ///      一样近取名义大的、再取 id 小的（结果稳定）；
  ///   3. 都不沾：落在某堵跨桶主墙的范围括号上（横向放宽同上，轻点时放到 44 pt）就认那堵墙，几堵叠着取名义大的。
  ///      范围里的空白处不再算——那里已经不画东西了。
  static func orderFlowHit(_ bands: [OrderFlowBand], x: Double, y: Double, touch: Bool = false) -> OrderFlowBand? {
    let half = { (b: OrderFlowBand) in max(Double(b.frame.height), orderFlowHitHeight) / 2 }
    let slopX = { (b: OrderFlowBand) in
      touch ? max(orderFlowHitSlopX, (orderFlowTouchTarget - Double(b.frame.width)) / 2) : orderFlowHitSlopX
    }
    let slopY = { (b: OrderFlowBand) in
      touch ? max(orderFlowHitSlop, (orderFlowTouchTarget - 2 * half(b)) / 2) : orderFlowHitSlop
    }
    let inX = { (b: OrderFlowBand) in
      x >= Double(b.frame.minX) - slopX(b) && x <= Double(b.frame.maxX) + slopX(b)
    }
    let off = { (b: OrderFlowBand) in abs(y - Double(b.frame.midY)) }
    let inside = bands.enumerated().filter { inX($0.element) && off($0.element) <= half($0.element) + 0.5 }
    if let exact = inside.min(by: { a, b in
      if off(a.element) != off(b.element) { return off(a.element) < off(b.element) }
      let na = a.element.group.drawNotional, nb = b.element.group.drawNotional
      return na != nb ? na > nb : a.offset > b.offset
    }) {
      return exact.element
    }
    let gap = { (b: OrderFlowBand) in max(0, off(b) - half(b)) }
    let rank = { (a: OrderFlowBand, b: OrderFlowBand) -> Bool in
      if a.group.drawNotional != b.group.drawNotional { return a.group.drawNotional > b.group.drawNotional }
      return a.key.id < b.key.id
    }
    if let near = bands
      .filter({ inX($0) && gap($0) <= slopY($0) })
      .min(by: { a, b in
        let ga = gap(a), gb = gap(b)
        return ga != gb ? ga < gb : rank(a, b)
      }) {
      return near
    }
    return bands
      .filter { b in
        guard let r = b.bracket else { return false }
        let sx = touch ? max(orderFlowHitSlopX, (orderFlowTouchTarget - Double(r.width)) / 2) : orderFlowHitSlopX
        return x >= Double(r.minX) - sx && x <= Double(r.maxX) + sx && y >= Double(r.minY) - 0.5 && y <= Double(r.maxY) + 0.5
      }
      .min(by: rank)
  }

  /// 轻点这一下落在哪条带上（视图坐标）。只认主图的绘图区。
  public func orderFlowHit(at point: CGPoint, size: CGSize) -> OrderFlowGroup? {
    guard orderFlowSnapshot != nil, !state.series.isEmpty else { return nil }
    let L = layout(size: size)
    let x = Double(point.x), y = Double(point.y)
    guard x >= 0, x <= L.plotW, y >= L.main.y, y <= L.main.y + L.main.h else { return nil }
    let frame = orderFlowBands(pane: L.main, range: priceRange(size: size), L: L)
    return Self.orderFlowHit(frame.bands, x: x, y: y, touch: true)?.group
  }

  /// 十字线停在哪条带上：只看主图，十字线交点用 `orderFlowHit` 同样的容差。
  func orderFlowHovered(_ bands: [OrderFlowBand], pane: Pane, range: PriceRange, L: Layout) -> OrderFlowBand? {
    guard let cross = state.crosshair, cross.pane == nil, !bands.isEmpty, !state.series.isEmpty else { return nil }
    let i = min(max(0, cross.index), state.series.count - 1)
    let cy = KanpanCore.yOf(cross.price ?? state.series.close[i], pane: pane, range: range, mode: state.effectivePriceMode)
    let cx = state.view.x(Double(state.series.time(at: i)), plotW: L.plotW)
    return Self.orderFlowHit(bands, x: cx, y: cy)
  }

  /// 此刻被选中的那一条（十字线在主图上就看十字线，否则看轻点选中的那一堵）及其画出来的样子。
  /// 选中的墙不在这一屏的带里（滚出去了）时 `band` 为空，按整份快照把同侧同类的单现切一遍、并一遍墙找回那一堵；
  /// 快照里也没了就是 nil。认的顺序：键一样 → `covers`（键那一段在墙里）→ `looselyCovers`（键那一段被当碎屑去掉了，
  /// 但落在墙的桶范围与时间跨度里）。
  func orderFlowFocusBand(pane: Pane, range: PriceRange, L: Layout) -> (group: OrderFlowGroup, band: OrderFlowBand?, hovered: Bool)? {
    guard let flow = orderFlowSnapshot, flow.phase == .ready else { return nil }
    let frame = orderFlowBands(pane: pane, range: range, L: L)
    if let cross = state.crosshair {
      guard cross.pane == nil, let band = orderFlowHovered(frame.bands, pane: pane, range: range, L: L) else { return nil }
      return (band.group, band, true)
    }
    guard let key = state.orderFlowSelected else { return nil }
    if let band = frame.bands.first(where: { $0.key == key }) ?? frame.bands.first(where: { $0.group.covers(key) })
      ?? frame.bands.first(where: { $0.group.looselyCovers(key) }) {
      return (band.group, band, false)
    }
    let display = state.orderFlowDisplay
    let kind = flow.orders.filter { display.shows($0) && OrderFlowGroupKey($0).sameKind(key) }
    let walls = OrderFlowGroup.groups(kind, gapMs: orderFlowMergeGapMs, minLifeMs: orderFlowMinLifeMs,
                                      step: flow.thresholds.step)
    guard let group = walls.first(where: { $0.key == key }) ?? walls.first(where: { $0.covers(key) })
      ?? walls.first(where: { $0.looselyCovers(key) }) else { return nil }
    return (group, nil, false)
  }

  /// 这一周期的切段容差：max(60 秒, 一根 K 线)。并墙的时间容差也用它。
  var orderFlowMergeGapMs: Int64 { OrderFlowGroup.mergeGapMs(barMs: state.series.step) }

  /// 已结束的段活不过这么久就不画：一根 K 线。
  var orderFlowMinLifeMs: Int64 { max(0, state.series.step) }

  /// 这一条是不是此刻选中的那一条（选中存的键可能是墙起点前移之前的，按 `covers` 认；键那一段被当碎屑去掉了就按
  /// `looselyCovers`）。轻点同一条收起用。
  public func orderFlowIsSelected(_ group: OrderFlowGroup) -> Bool {
    state.orderFlowSelected.map { group.covers($0) || group.looselyCovers($0) } ?? false
  }

  /// 交给 app 的选中带（出详情卡用）。没选中返回 nil。
  public func orderFlowFocus(size: CGSize) -> ChartOrderFlowFocus? {
    guard !state.series.isEmpty, let flow = orderFlowSnapshot else { return nil }
    let L = layout(size: size), range = priceRange(size: size)
    guard let hit = orderFlowFocusBand(pane: L.main, range: range, L: L) else { return nil }
    let anchorX: Double
    if hit.hovered, let cross = state.crosshair {
      let i = min(max(0, cross.index), state.series.count - 1)
      anchorX = state.view.x(Double(state.series.time(at: i)), plotW: L.plotW)
    } else if let band = hit.band {
      anchorX = Double(band.frame.midX)
    } else {
      anchorX = L.plotW / 2
    }
    let bandY = hit.band.map { Double($0.frame.midY) }
      ?? KanpanCore.yOf(hit.group.price, pane: L.main, range: range, mode: state.effectivePriceMode)
    // 卡片躲开的是命中带（至少 8 pt 高），不只是那条 1–2.5 pt 的线：手指还按在线上时卡片不贴着它。
    let bandHalf = max(hit.band.map { Double($0.frame.height) } ?? Self.orderFlowMainLine, Self.orderFlowHitHeight) / 2
    return ChartOrderFlowFocus(group: hit.group, selected: !hit.hovered, anchorX: anchorX, bandY: bandY,
                               bandHalf: bandHalf, plotW: L.plotW,
                               mainTop: L.main.y + mainLegendInset(plotW: L.plotW) + 4,
                               mainBottom: L.main.y + L.main.h, mainHeight: L.main.h, asOfMs: flow.asOfMs)
  }

  private func computeOrderFlowBands(pane: Pane, range: PriceRange, L: Layout) -> OrderFlowFrame {
    guard let flow = orderFlowSnapshot, flow.phase == .ready, !flow.orders.isEmpty,
          !state.series.isEmpty, L.plotW > 0 else { return OrderFlowFrame() }
    let mode = state.effectivePriceMode
    let y = { (p: Double) in KanpanCore.yOf(p, pane: pane, range: range, mode: mode) }
    let spacing = state.view.barSpacing(step: state.series.step, plotW: L.plotW)
    let display = state.orderFlowDisplay

    // 1. 逐单：过显示开关；图例合计只算还挂着、落在主图里、横向落在这一屏的单（逐单求和，不因合并变）。
    var frame = OrderFlowFrame()
    var shown: [BigOrder] = []
    shown.reserveCapacity(flow.orders.count)
    for order in flow.orders where display.shows(order) {
      shown.append(order)
      guard order.isLive else { continue }
      let cy = y(order.price)
      guard cy.isFinite, cy >= pane.y, cy <= pane.y + pane.h,
            let x0 = orderFlowBarX(order.firstSeenMs, spacing: spacing, plotW: L.plotW)?.left, x0 < L.plotW else { continue }
      if order.side == .bid { frame.bidTotal += order.notional } else { frame.askTotal += order.notional }
    }
    guard !shown.isEmpty else { return frame }

    // 2. 按「桶 × 侧 × 类 × 时间段」切段（切段只看时间与周期，不看这一屏：段的身份跨缩放、平移稳定），
    //    去掉活不过一根 K 线的已结束段，把相邻桶、时间连着的段并成墙；再按墙的时间跨度筛出横向落在这一屏的，
    //    只对它们建组。价位：单桶的墙按代表价、跨桶的按价位范围，落在主图里才算。
    //    横向范围：墙起点那根的左缘到墙结束那根的右缘，有一单还挂着就到主图右缘。
    let gap = orderFlowMergeGapMs
    let parts = OrderFlowGroup.dropShortLived(OrderFlowGroup.segments(shown, gapMs: gap), minLifeMs: orderFlowMinLifeMs)
    var visible: [(group: OrderFlowGroup, left: Double, right: Double)] = []
    for wall in OrderFlowGroup.walls(parts, gapMs: gap) {
      guard let x0 = orderFlowBarX(wall.startMs, spacing: spacing, plotW: L.plotW)?.left else { continue }
      let x1: Double
      if let end = wall.endMs {
        guard let bar = orderFlowBarX(end, spacing: spacing, plotW: L.plotW) else { continue }
        x1 = bar.right
      } else {
        x1 = L.plotW
      }
      let left = max(0, x0), right = min(L.plotW, max(x1, x0 + 1))
      guard right > left, left < L.plotW, let group = wall.group(step: flow.thresholds.step) else { continue }
      if group.isRange {
        let a = y(group.priceLow), b = y(group.priceHigh)
        guard a.isFinite, b.isFinite, max(a, b) >= pane.y, min(a, b) <= pane.y + pane.h else { continue }
      } else {
        let cy = y(group.price)
        guard cy.isFinite, cy >= pane.y, cy <= pane.y + pane.h else { continue }
      }
      visible.append((group, left, right))
    }
    guard !visible.isEmpty else { return frame }
    // 屏内排名：画法名义从大到小，一样的先起的在前，再按键（`drawOrder`，每帧现排、结果确定）。
    visible.sort { OrderFlowGroup.drawOrder($0.group, $1.group) }

    // 3. 按排名定主次与线粗：主 2 pt（还挂着 2.5）、次 1 pt 70%、底噪 1 pt 35%。主、次按排名落线，
    //    和已落下的（整条或细线）横向交叠、纵向重叠（含 1 pt 间隙）就压成 1 pt 细线、不写金额。底噪不占位、不被压。
    //    跨桶的主墙另记价位范围（最低桶价 … 最高桶价 + 步长），在段右端立一枚范围括号；范围比线还窄就不立。括号不占位。
    var noise: [OrderFlowBand] = [], full: [OrderFlowBand] = [], thin: [OrderFlowBand] = []
    var occupied: [CGRect] = []
    for (rank, (group, left, right)) in visible.enumerated() {
      var role: OrderFlowRole = rank < Self.orderFlowMainCount ? .main
        : rank < Self.orderFlowRankedCount ? .secondary : .noise
      if role == .noise, group.isLive { role = .secondary }
      let cy = y(group.price)
      let color = orderFlowColor(group)
      let line = { (h: Double) in CGRect(x: left, y: cy - h / 2, width: right - left, height: h) }
      if role == .noise {
        noise.append(OrderFlowBand(group: group, frame: line(Self.orderFlowNoiseLine), color: color, dark: group.hasFill,
                                   thin: false, role: .noise, alpha: Self.orderFlowNoiseAlpha))
        continue
      }
      let whole: CGRect
      var bracket: CGRect?
      let alpha = role == .main ? 1 : Self.orderFlowSecondaryAlpha
      if role == .main {
        whole = line(group.isLive ? Self.orderFlowMainLiveLine : Self.orderFlowMainLine)
        if group.isRange {
          let a = y(group.priceLow), b = y(group.priceHigh)
          let top = min(a, b), bottom = max(a, b)
          if bottom - top > whole.height {
            bracket = Self.orderFlowBracket(live: group.isLive, lineRight: right,
                                            labelWidth: Self.orderFlowLabelWidth(Self.orderFlowAmount(group.notional)),
                                            plotW: L.plotW, top: top, bottom: bottom)
          }
        }
      } else {
        whole = line(Self.orderFlowSecondaryLine)
      }
      let clash = occupied.contains { r in
        r.minX < whole.maxX && r.maxX > whole.minX
          && whole.minY < r.maxY + Self.orderFlowGap && whole.maxY > r.minY - Self.orderFlowGap
      }
      let rect = clash ? line(Self.orderFlowThinLine) : whole
      occupied.append(rect)
      let band = OrderFlowBand(group: group, frame: rect, color: color, dark: group.hasFill, thin: clash, role: role,
                               alpha: alpha, bracket: clash ? nil : bracket)
      if clash { thin.append(band) } else { full.append(band) }
    }
    frame.bands = noise + full + thin
    frame.labels = orderFlowLabels(full.filter { $0.role == .main }, pane: pane, L: L, spacing: spacing)
    return frame
  }

  /// 金额签（只给「主」里没被压细的，按排名）：还挂着的贴主图右缘（价格刻度列左侧、不进刻度列）、
  /// 已结束的放在结束点右侧（放不下就往左收到主图右缘以内）；纵向居中在线上。
  /// 和已放下的签撞了（留 2 pt）：挪到撞上那枚的上方或下方，取离自己的线近的、不再撞任何一枚、
  /// 没出主图、离线不超过 32 pt 的那个位置；都不行就不放。名义大的先放，所以让位的总是名义小的。一屏最多 6 枚。
  private func orderFlowLabels(_ mains: [OrderFlowBand], pane: Pane, L: Layout, spacing: Double) -> [OrderFlowLabel] {
    let h = Self.orderFlowLabelHeight, gap = Self.orderFlowLabelGap
    let bg = state.colors.bg
    var labels: [OrderFlowLabel] = []
    let collides = { (r: CGRect) in
      labels.contains { l in
        l.frame.minX < r.maxX && l.frame.maxX > r.minX
          && r.minY < l.frame.maxY + gap && r.maxY > l.frame.minY - gap
      }
    }
    for band in mains where labels.count < Self.orderFlowLabelMax {
      let text = Self.orderFlowAmount(band.group.notional)
      let w = Self.orderFlowLabelWidth(text)
      let x = Self.orderFlowLabelX(live: band.group.isLive, lineRight: Double(band.frame.maxX), width: w, plotW: L.plotW)
      guard x >= 0 else { continue }
      let mid = Double(band.frame.midY)
      let clamp = { (top: Double) in min(max(top, pane.y), pane.y + pane.h - h) }
      var rect = CGRect(x: x, y: clamp(mid - h / 2), width: w, height: h)
      if collides(rect) {
        let hits = labels.filter { l in
          l.frame.minX < rect.maxX && l.frame.maxX > rect.minX
            && rect.minY < l.frame.maxY + gap && rect.maxY > l.frame.minY - gap
        }
        let tops = hits.flatMap { [Double($0.frame.minY) - gap - h, Double($0.frame.maxY) + gap] }
        let fits = tops
          .filter { $0 >= pane.y && $0 + h <= pane.y + pane.h && abs($0 + h / 2 - mid) <= Self.orderFlowLabelMaxShift }
          .map { CGRect(x: x, y: $0, width: w, height: h) }
          .filter { !collides($0) }
          .min { abs(Double($0.midY) - mid) < abs(Double($1.midY) - mid) }
        guard let fit = fits else { continue }
        rect = fit
      }
      let shown = mixHex(band.color, bg, 1 - Self.orderFlowLabelAlpha)
      labels.append(OrderFlowLabel(key: band.key, text: text, frame: rect, fill: band.color,
                                   ink: Self.orderFlowLabelInk(shown)))
    }
    return labels
  }

  /// 某一时刻落在哪根 K 线上，那根的左右缘。蜡烛中心落在 openTime 上（见 `drawCandles`），左右各半根。
  /// 早于整段序列的给左右都是负无穷：首见早于序列就从最左画起（夹到 0），结束早于序列就整条不画。
  private func orderFlowBarX(_ ms: Int64, spacing: Double, plotW: Double) -> (left: Double, right: Double)? {
    let b = state.series
    let t = Double(ms)
    guard t >= Double(b.firstTime) else { return (-.infinity, -.infinity) }
    var i = b.index(atTime: t)
    if Double(b.time(at: i)) > t, i > 0 { i -= 1 }
    let cx = state.view.x(Double(b.time(at: i)), plotW: plotW)
    return (cx - spacing / 2, cx + spacing / 2)
  }

  /// 此刻主图上画着的色带与小签（视图坐标）、十字线有没有停在一条上、选中的是哪一桶。只给 DEBUG 诊断与测试用。
  func orderFlowDiagnostics(size: CGSize) -> (bands: [OrderFlowBand], labels: [OrderFlowLabel], hovered: Bool,
                                               focus: ChartOrderFlowFocus?) {
    guard !state.series.isEmpty else { return ([], [], false, nil) }
    let L = layout(size: size)
    let focus = orderFlowFocus(size: size)
    let frame = orderFlowFrame(pane: L.main, range: priceRange(size: size), L: L)
    return (frame.bands, frame.labels, focus.map { !$0.selected } ?? false, focus)
  }

  /// 在 plotLayer 上画线（在蜡烛之前调，垫在 K 线下面）：底噪、整条、细线依次，最后是跨桶主墙的范围括号。
  /// 返回画了几条（给测试核对）。
  @discardableResult
  func drawOrderFlow(_ ctx: CGContext, pane: Pane, range: PriceRange, L: Layout) -> Int {
    let frame = orderFlowBands(pane: pane, range: range, L: L)
    guard !frame.bands.isEmpty else { return 0 }
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: pane.y, width: L.plotW, height: pane.h))
    for band in frame.bands {
      ctx.setAlpha(CGFloat(band.alpha))
      ctx.setFillColor(Paint.cg(band.color))
      ctx.fill(band.frame)
    }
    ctx.setAlpha(CGFloat(Self.orderFlowBracketAlpha))
    for band in frame.bands {
      guard let bracket = band.bracket else { continue }
      drawOrderFlowBracket(ctx, bracket, color: band.color)
    }
    ctx.setAlpha(1)
    ctx.restoreGState()
    return frame.bands.count
  }

  /// 在 crossLayer 上画金额签（签底 85% 不透明）。返回画了几枚。
  @discardableResult
  func drawOrderFlowLabels(_ ctx: CGContext, pane: Pane, range: PriceRange, L: Layout) -> Int {
    let frame = orderFlowBands(pane: pane, range: range, L: L)
    guard !frame.labels.isEmpty else { return 0 }
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: pane.y, width: L.plotW, height: pane.h))
    for label in frame.labels {
      ctx.setAlpha(CGFloat(Self.orderFlowLabelAlpha))
      ctx.setFillColor(Paint.cg(label.fill))
      ctx.addRoundRect(label.frame, radius: Self.orderFlowLabelRadius)
      ctx.fillPath()
      ctx.setAlpha(1)
      label.text.drawCentered(at: CGPoint(x: label.frame.midX, y: label.frame.midY), font: Self.orderFlowLabelFont,
                              color: label.ink)
    }
    ctx.restoreGState()
    return frame.labels.count
  }

  /// 在 crossLayer 上把选中的那一条再画一遍（盖过蜡烛，读得出选中的是哪条）并描 1 pt 正文色边；
  /// 跨桶的墙的范围括号也用本色（不透明）再画一遍。返回画了没有。
  @discardableResult
  func drawOrderFlowHover(_ ctx: CGContext, pane: Pane, range: PriceRange, L: Layout) -> Bool {
    guard let band = orderFlowFocusBand(pane: pane, range: range, L: L)?.band else { return false }
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: pane.y, width: L.plotW, height: pane.h))
    if let bracket = band.bracket { drawOrderFlowBracket(ctx, bracket, color: band.color) }
    ctx.setFillColor(Paint.cg(state.colors.text))
    ctx.fill(band.frame.insetBy(dx: -1, dy: -1))
    ctx.setFillColor(Paint.cg(band.color))
    ctx.fill(band.frame)
    ctx.restoreGState()
    return true
  }

  /// 范围括号「]」：右侧一道竖笔、上下两个朝左的钩，笔画 1.5 pt，整个框宽 3 pt。不透明度由调用方设。
  func drawOrderFlowBracket(_ ctx: CGContext, _ r: CGRect, color: Hex) {
    let t = Self.orderFlowBracketStroke
    ctx.setFillColor(Paint.cg(color))
    ctx.fill(CGRect(x: r.maxX - t, y: r.minY, width: t, height: r.height))
    ctx.fill(CGRect(x: r.minX, y: r.minY, width: r.width - t, height: t))
    ctx.fill(CGRect(x: r.minX, y: r.maxY - t, width: r.width - t, height: t))
  }

  /// 十字线正停在一条带上（这时详情卡顶替图里的开高低收框）。
  func orderFlowHoversBand(L: Layout, range: PriceRange) -> Bool {
    orderFlowFocusBand(pane: L.main, range: range, L: L)?.hovered == true
  }

  /// 图例「主力」那一行：跟在叠加指标的图例后面另起一行。`x`、`y` 是前面那几段画完停在哪儿。
  /// 选中的那一条写在详情卡上，图例这一行始终是「主力 ▬▬ 买 X · ▬▬ 卖 Y」（逐单求和，不因合并变）：
  /// 买、卖前面各两枚色样（合约、现货，显示开关关掉的那类不画），线色和图上一致；金额用正文色。
  func drawOrderFlowLegend(_ ctx: CGContext, pane: Pane, L: Layout, x: Double, y: Double) {
    guard let flow = orderFlowSnapshot else { return }
    let y = x > 8 ? y + 12 : y
    guard y < pane.y + min(pane.h - 6, mainLegendInset(plotW: L.plotW) - 4) else { return }
    let t = state.colors
    var x = 8.0
    let put = { (text: String, color: Hex) in
      text.drawLeft(at: CGPoint(x: x, y: y), font: ChartFont.axis, color: color)
      x += Double(text.width(ChartFont.axis)) + 4
    }
    guard flow.phase == .ready else { put("主力 …", t.text); return }
    let frame = orderFlowFrame(pane: pane, range: priceRange(size: CGSize(width: L.W, height: L.H)), L: L)
    guard frame.bidTotal > 0 || frame.askTotal > 0 else { put("主力 暂无", t.text); return }
    let display = state.orderFlowDisplay
    let swatches = { (side: BookSide) in
      let lineY = y + Double(ChartFont.axis.lineHeight) / 2 - 1
      for contract in [true, false] where contract ? display.contract : display.spot {
        ctx.setFillColor(Paint.cg(self.orderFlowBaseColor(side: side, contract: contract)))
        ctx.fill(CGRect(x: x, y: lineY, width: 8, height: 2))
        x += 10
      }
      x += 2
    }
    put("主力", t.text)
    if frame.bidTotal > 0 { swatches(.bid); put("买 " + Self.orderFlowAmount(frame.bidTotal), t.text) }
    if frame.bidTotal > 0, frame.askTotal > 0 { put("·", t.text) }
    if frame.askTotal > 0 { swatches(.ask); put("卖 " + Self.orderFlowAmount(frame.askTotal), t.text) }
  }

  /// 名义金额：K / M / B 一位小数。
  static func orderFlowAmount(_ value: Double) -> String {
    let a = abs(value)
    if a >= 1e9 { return toFixed(value / 1e9, 1) + "B" }
    if a >= 1e6 { return toFixed(value / 1e6, 1) + "M" }
    if a >= 1e3 { return toFixed(value / 1e3, 1) + "K" }
    return toFixed(value, 0)
  }
}
