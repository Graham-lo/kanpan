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
//      括号只在整段范围（含两端横钩）都落在主图里时才画，任一端出界整枚不画、不裁；同一 x 上纵向重叠的只留名义大的
//      那枚（1 分钟 BTC 的墙比整张主图还高，裁剩的几枚叠成一根贯穿主图的竖线，2026-09-25 复验）。
//      范围数字写在详情卡上。
//   4. **纵向去挤**（主、次）：按排名落线；和已落下的横向有交叠、纵向重叠（含 1 pt 间隙）的排名更后的线压成 1 pt
//      细线、不写金额——不平移、不改价位。底噪不参与。画的先后：底噪 → 整条 → 细线。
//      线细了命中区不跟着细：轻点、十字线都按至少 8 pt 高的带子算（`orderFlowHitHeight`），轻点再放到 44 pt。
//   5. **金额签**：只给「主」里没被压细的：还挂着的贴主图右缘（价格刻度列左侧、不进刻度列），已结束的放在
//      结束点右侧；签底是线色 85% 不透明、字色在近黑与白之间取对叠出来的颜色对比度高的那个（`orderFlowLabelInk`，
//      六套皮肤 × 四色 × 深浅两档都 ≥ 4.5:1，测试守着）；一屏最多 6 枚（`orderFlowLabelMax`）；
//      11 pt medium 等宽（HIG 下限，同 app 的 `TypeScale.caption2Emph`）、高 16、左右 4、圆角 4、签间至少 2。
//      签之间纵向撞了按名义让位：名义小的挪到撞上那枚的上方或下方（离自己的线最多 32 pt），挪不开就不放。
//      挂着的签贴右缘时纵向压到最新那几根 K 线（含影线）就往左让到压着的最右一根左侧 2 pt，一直让到不压任何一根，
//      让出主图左缘就不放（2026-09-29，`orderFlowCandleDodge`）。
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
// 线、底噪、括号只画在主图图例区（`mainLegendInset`）以下（2026-09-29）：价格轴按 K 线定标，墙的价位可以落进图例那几行，
// 线会从「主力 买 … 卖 …」「均线 …」的字中间穿过去。命中、排名、图例合计照旧按整块主图算，只是图例区里不画。
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
  /// 十字线那根 K 线（影线高低、实体左右）；轻点选中时没有十字线，是 nil。卡片不盖住它。
  public var candle: OrderFlowCardBudget.Candle?

  public init(group: OrderFlowGroup, selected: Bool, anchorX: Double, bandY: Double, bandHalf: Double, plotW: Double,
              mainTop: Double, mainBottom: Double, mainHeight: Double, asOfMs: Int64,
              candle: OrderFlowCardBudget.Candle? = nil) {
    self.group = group; self.selected = selected; self.anchorX = anchorX; self.bandY = bandY; self.bandHalf = bandHalf
    self.plotW = plotW; self.mainTop = mainTop; self.mainBottom = mainBottom; self.mainHeight = mainHeight
    self.asOfMs = asOfMs; self.candle = candle
  }

  /// 卡片摆在哪、最宽最高多少、三行还是两行（`OrderFlowCardBudget.placement`：带的对面那一半、贴远端、躲十字线那根 K 线）。
  public var cardPlacement: OrderFlowCardBudget.Placement {
    OrderFlowCardBudget.placement(bandY: bandY, bandHalf: bandHalf, top: mainTop, bottom: mainBottom,
                                  mainHeight: mainHeight, plotW: plotW, anchorX: anchorX, candle: candle)
  }
  /// 卡片最宽多少（躲 K 线时会收窄）。
  public var cardMaxWidth: Double { cardPlacement.maxWidth }
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

  /// 底噪的画法（只管画，命中、选中、诊断仍按 `OrderFlowFrame.bands` 里逐条的带）：同一像素行、同色的并成一条。
  struct OrderFlowStroke: Equatable {
    var frame: CGRect
    let color: Hex
    /// 并进来的几条里排名最前的那条在底噪里的名次（0 起），超上限时按它丢。
    var rank: Int
  }

  struct OrderFlowFrame: Equatable {
    /// 画的先后排好的线：底噪在前，整条的其次（彼此不重叠），细线在后。
    var bands: [OrderFlowBand] = []
    /// 底噪实际画的那几条（`orderFlowMergeNoise`）：并过行、封过顶，按名次排。
    var noiseStrokes: [OrderFlowStroke] = []
    var labels: [OrderFlowLabel] = []
    /// 可视区里还挂着（且开着显示）的大单各侧合计（逐单求和）。
    var bidTotal = 0.0
    var askTotal = 0.0
  }

  /// 按 pane / 价格区间 / 主图宽记一份色带几何（不含十字线与选中）。盒子在 `recalc` 里随输入、视野、
  /// 快照、显示开关一起换新，十字线动、选中换只换 `state.overlay`、盒子留着——plot 与 cross
  /// 两层画同一帧时也只算一遍。
  final class OrderFlowCache {
    /// `ladder`：盘口梯那一块（金额签躲它）。深度到了 / 关了不换盒子（`recalc` 不看深度），所以它也进键。
    var entries: [(pane: Pane, range: PriceRange, plotW: Double, ladder: CGRect?, frame: OrderFlowFrame)] = []
    /// 真算了几次（测试核对缓存有没有生效）。
    var computed = 0
    /// 这个 state 下取到的那一份墙（`orderFlowEntry`），同一只盒子里只取一次。
    var entry: OrderFlowWallCache.Entry?
    /// 那一份是拿同一条道上旧快照的顶着的（后台还在算这一份）。
    var servedStale = false
    /// 底图（plot 层）是拿旧的那份画的：后台算好后要连底图一起重画，不只是 cross 层。
    var plotStale = false
  }

  /// 与视野无关的那一半：过显示开关 → 切段 → 去碎屑 → 并墙 → 建组 → 按 `drawOrder` 排好。只随快照里的单、显示开关、
  /// 步长、周期（切段容差与最短寿命）变。`OrderFlowCache` 存的是落在这一屏的几何，视野一动 `recalc` 就换新盒子，
  /// 以前连这一半一起每帧重算：2 万单时拖图一帧 20–68 ms（压测 2026-09-28，`OrderFlowPerfBenchTests`）。
  /// 所以另放一只进程内的小缓存，按内容认（单子数组先比存储是否同一块，同一份快照是 O(1)），最多留三份
  /// （主图此刻这份、上一份——新快照算好之前先拿它顶着画——和刚切走的一份）。
  ///
  /// 第二轮（2026-09-28）：快照每推来一份新的，这一半在主线程上同步重算，2 万单 1 分钟图那一帧 25–38 ms。
  /// 现在图表视图走 `lookup`：没命中就交给后台一条串行队列去算（同一把键只算一次，排队的只留最新那把），
  /// 当下先拿同一条「道」上（同品种、同显示开关、同步长、同周期）最近算好的那份画，别的品种的一份也不给；
  /// 算好了在主线程发 `readyNotification`，图表视图据此重画。
  final class OrderFlowWallCache: @unchecked Sendable {
    struct Key: Equatable, Sendable {
      /// 品种（规范名）。同一条道只认同一只：切品种那一拍，旧品种晚到的一份不能顶到新品种上。
      var symbol: String = ""
      var orders: [BigOrder]
      var display: OrderFlowDisplay
      var step: Double?
      var gapMs: Int64
      var minLifeMs: Int64

      /// 除单子以外都一样：同一只、同一种画法，只是快照换了一份。旧的那份可以先顶着画。
      func sameLane(_ o: Key) -> Bool {
        symbol == o.symbol && display == o.display && step == o.step && gapMs == o.gapMs && minLifeMs == o.minLifeMs
      }

      /// 同一条道、单子数组是同一块存储：O(1)。
      func sameStorage(_ o: Key) -> Bool {
        sameLane(o) && orders.count == o.orders.count
          && orders.withUnsafeBufferPointer { a in o.orders.withUnsafeBufferPointer { a.baseAddress == $0.baseAddress } }
      }
    }
    /// 一堵墙：建好的组，以及它（按段算的）横向起止——结束是 nil 表示有一段还挂着，画到主图右缘。
    struct Wall: Sendable {
      var group: OrderFlowGroup
      var startMs: Int64
      var endMs: Int64?
    }
    /// 一份：全部墙（按 `drawOrder` 排好），以及过了显示开关、还挂着的单（图例合计只看它们）。
    struct Entry: Sendable {
      var walls: [Wall]
      var live: [BigOrder]
    }
    /// 后台算好一份时在主线程发出（`object` 是这只缓存）。图表视图收到后看自己上一帧是不是拿旧的顶着画的，是就重画。
    static let readyNotification = Notification.Name("KanpanChart.OrderFlowWallCache.ready")
    static let shared = OrderFlowWallCache()
    static let capacity = 3

    private let capacity: Int
    private let lock = NSLock()
    /// 存着的几份与各自的代数（后请求的代数大）。挑「同一条道上的旧份」时取代数最大的，满了踢代数最小的——
    /// 先请求的那份就算晚算完、晚存进来，也不会被当成更新的那份。
    private var entries: [(key: Key, entry: Entry, generation: UInt64)] = []
    private var generation: UInt64 = 0
    /// 后台正在算的那把、排着队的那把（只留最新的一把：新快照来了，还没开算的旧快照就不必算了）。
    private var running: Key?
    private var pending: (key: Key, generation: UInt64)?
    private let queue = DispatchQueue(label: "KanpanChart.OrderFlowWallCache", qos: .userInitiated)
    /// 真算了几次（测试核对缓存有没有生效）。
    private(set) var computed = 0

    init(capacity: Int = OrderFlowWallCache.capacity) { self.capacity = capacity }

    /// 找存着的那一份（调用方持锁）：先按存储认（O(1)），认不出再逐单比内容、从新往旧比；按内容认出来的
    /// 把存着的键换成这一份数组，下一帧就能按存储认。原来按存储以外一律逐单比、从旧往新：新快照内容没变
    /// （或同样多单、只改了后面几单）时，拖图每一帧都要把两万单从头比一遍、比过两三份旧的才轮到对的那份，
    /// 一帧 0.5 ms 起（压测 2026-09-28 第二轮 D1）。
    private func hitIndex(_ key: Key) -> Int? {
      if let i = entries.firstIndex(where: { $0.key.sameStorage(key) }) { return i }
      let order = entries.indices.sorted { entries[$0].generation > entries[$1].generation }
      guard let i = order.first(where: { entries[$0].key == key }) else { return nil }
      entries[i].key = key
      return i
    }

    /// 同步取：没命中就在调用方线程上算（离屏渲染、分享图、测试走这条）。
    func entry(_ key: Key) -> Entry {
      lock.lock()
      if let i = hitIndex(key) {
        let hit = entries[i]
        lock.unlock()
        return hit.entry
      }
      generation += 1
      let g = generation
      lock.unlock()
      let entry = Self.compute(key)
      store(key, entry, generation: g)
      return entry
    }

    /// 不阻塞地取：命中给 `(那份, true)`；没命中就把这把键交给后台（在算或排着的就不再交），先给同一条道上最新的那份
    /// `(旧份, false)`，一份都没有给 nil。
    func lookup(_ key: Key) -> (entry: Entry, exact: Bool)? {
      lock.lock()
      defer { lock.unlock() }
      if let i = hitIndex(key) { return (entries[i].entry, true) }
      if running != key && pending?.key != key {
        generation += 1
        let idle = running == nil && pending == nil
        pending = (key, generation)
        if idle { queue.async { [self] in drain() } }
      }
      let stale = entries.filter { $0.key.sameLane(key) }.max { $0.generation < $1.generation }
      return stale.map { ($0.entry, false) }
    }

    /// 后台队列上：一把一把算到排空。
    private func drain() {
      while true {
        lock.lock()
        guard let next = pending else { running = nil; lock.unlock(); return }
        pending = nil
        running = next.key
        lock.unlock()
        let entry = Self.compute(next.key)
        store(next.key, entry, generation: next.generation)
        lock.lock(); running = nil; lock.unlock()
        DispatchQueue.main.async { [self] in
          NotificationCenter.default.post(name: Self.readyNotification, object: self)
        }
      }
    }

    /// 存一份。模块内可见是给测试模拟「先请求的那份晚算完」。
    func store(_ key: Key, _ entry: Entry, generation g: UInt64) {
      lock.lock()
      computed += 1
      entries.removeAll { $0.key == key }
      if entries.count >= capacity, let i = entries.indices.min(by: { entries[$0].generation < entries[$1].generation }) {
        entries.remove(at: i)
      }
      entries.append((key, entry, g))
      lock.unlock()
    }

    /// 测试用：等后台把排着的都算完（在后台队列上排一个空活，它跑到时前面的都已算完）。
    func waitUntilIdle() {
      while true {
        queue.sync {}
        lock.lock()
        let busy = running != nil || pending != nil
        lock.unlock()
        if !busy { return }
      }
    }

    static func compute(_ key: Key) -> Entry {
      let shown = key.orders.filter { key.display.shows($0) }
      let parts = OrderFlowGroup.dropShortLived(OrderFlowGroup.segments(shown, gapMs: key.gapMs), minLifeMs: key.minLifeMs)
      var walls = OrderFlowGroup.walls(parts, gapMs: key.gapMs).compactMap { wall in
        wall.group(step: key.step).map { Wall(group: $0, startMs: wall.startMs, endMs: wall.endMs) }
      }
      walls.sort { OrderFlowGroup.drawOrder($0.group, $1.group) }
      return Entry(walls: walls, live: shown.filter(\.isLive))
    }
  }

  func orderFlowWallKey(_ flow: OrderFlowSnapshot) -> OrderFlowWallCache.Key {
    .init(symbol: flow.symbol, orders: flow.orders, display: state.orderFlowDisplay,
          step: flow.thresholds.step, gapMs: orderFlowMergeGapMs, minLifeMs: orderFlowMinLifeMs)
  }

  /// 这份快照在当前显示开关、周期下的那一份（全部墙按 `drawOrder` 排好、还挂着的单），走 `OrderFlowWallCache`。
  /// 图表视图（`orderFlowPrepareInBackground`）不在主线程上算：没算好就先给同一条道上旧的那份（没有就空），
  /// 并在 `OrderFlowCache` 上记一笔「拿旧的顶着」，等后台算好再重画。同一只盒子（同一个 state）里只取一次。
  func orderFlowEntry(_ flow: OrderFlowSnapshot) -> OrderFlowWallCache.Entry {
    let box = orderFlowCache
    if let memo = box.entry { return memo }
    let key = orderFlowWallKey(flow)
    let entry: OrderFlowWallCache.Entry
    if orderFlowPrepareInBackground {
      if let found = OrderFlowWallCache.shared.lookup(key) {
        entry = found.entry
        if !found.exact { box.servedStale = true }
      } else {
        entry = .init(walls: [], live: [])
        box.servedStale = true
      }
    } else {
      entry = OrderFlowWallCache.shared.entry(key)
    }
    box.entry = entry
    return entry
  }

  func orderFlowWalls(_ flow: OrderFlowSnapshot) -> [OrderFlowWallCache.Wall] { orderFlowEntry(flow).walls }

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
  /// 底噪一屏最多画几条（并行之后）：超出的丢名义最小的。1 分钟 2 万单一屏 500 多条底噪，逐条填一遍 2.4 ms
  /// （压测 2026-09-28 第二轮 D1）；35% 的 1 pt 淡线挤成一片时多画的几百条也看不出来。
  static let orderFlowNoiseDrawMax = 200
  /// 同一行上两段横向隔得不超过这么多（pt）就算相邻、并成一条。
  static let orderFlowNoiseJoin = 0.5
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
  /// 挂着的墙的签坐在线上方，签底离线的上沿这么多（pt）；上方会进图例就翻到线下方、同样留这么多（第二轮 D3）。
  static let orderFlowLabelLineGap = 2.0
  /// 签躲 K 线时离压着的那根蜡烛这么多（pt）：挂着的往左让，签右缘离蜡烛左缘；已结束的往右让，签左缘离蜡烛右缘。
  static let orderFlowLabelCandleGap = 2.0
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

  /// 八种画法色（类 × 侧 × 深浅，下标 `(合约 ? 4 : 0) + (卖 ? 2 : 0) + (被吃过 ? 1 : 0)`），按图区底色记下来：
  /// 浅色档要二分找混色比例，八种一起算一遍 0.08 ms，原来拖图每帧都算（第二轮 D1）。
  func orderFlowPalette() -> [Hex] {
    let bg = state.colors.bg
    Self.orderFlowPaletteLock.lock()
    defer { Self.orderFlowPaletteLock.unlock() }
    if let hit = Self.orderFlowPaletteMemo[bg] { return hit }
    let palette: [Hex] = [false, true].flatMap { contract in
      [BookSide.bid, .ask].flatMap { side in [false, true].map { orderFlowColor(side: side, contract: contract, hasFill: $0) } }
    }
    if Self.orderFlowPaletteMemo.count >= 16 { Self.orderFlowPaletteMemo.removeAll() }
    Self.orderFlowPaletteMemo[bg] = palette
    return palette
  }

  private nonisolated(unsafe) static var orderFlowPaletteMemo: [Hex: [Hex]] = [:]
  private static let orderFlowPaletteLock = NSLock()

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
  /// 开着盘口时，签的横向落点躲开盘口梯（`ladder`，见 `depthEnvelope`），括号跟着签走（`mid` 是芯线的 y）。
  static func orderFlowBracket(live: Bool, lineRight: Double, labelWidth w: Double, plotW: Double,
                               top: Double, bottom: Double, mid: Double = 0, ladder: CGRect? = nil) -> CGRect {
    let x = orderFlowLabelX(live: live, lineRight: lineRight, width: w, plotW: plotW)
    let nominal = orderFlowDodgeLadder(CGRect(x: x, y: mid - orderFlowLabelHeight / 2, width: w,
                                              height: orderFlowLabelHeight), ladder: ladder)
    let right = Double(nominal.minX) - orderFlowBracketGap
    return CGRect(x: right - orderFlowBracketWidth, y: top, width: orderFlowBracketWidth, height: bottom - top)
  }

  /// 签躲 K 线横向挪了（`orderFlowCandleDodge`：挂着的往左、已结束的往右），范围括号跟着签走：右缘仍紧贴签左侧 1 pt，
  /// 纵向不动。挪过去和排名更前、已立的括号在同一 x 上纵向重叠的就不立（与 `computeOrderFlowBands` 里的去重同一规则）。
  /// 签没放下的括号留在名义落点。只有签真挪了的才重建，其余原样。
  static func orderFlowBracketsFollowLabels(_ bands: [OrderFlowBand], labels: [OrderFlowLabel]) -> [OrderFlowBand] {
    guard bands.contains(where: { $0.bracket != nil }), !labels.isEmpty else { return bands }
    var kept: [CGRect] = []
    return bands.map { band in
      guard var k = band.bracket else { return band }
      var moved = false
      if let label = labels.first(where: { $0.key == band.key }) {
        let right = Double(label.frame.minX) - orderFlowBracketGap
        if abs(Double(k.maxX) - right) > 1e-9 {
          k.origin.x = CGFloat(right) - k.width
          moved = true
        }
      }
      if kept.contains(where: { $0.minX < k.maxX && $0.maxX > k.minX && $0.minY < k.maxY && $0.maxY > k.minY }) {
        return OrderFlowBand(group: band.group, frame: band.frame, color: band.color, dark: band.dark, thin: band.thin,
                             role: band.role, alpha: band.alpha, bracket: nil)
      }
      kept.append(k)
      guard moved else { return band }
      return OrderFlowBand(group: band.group, frame: band.frame, color: band.color, dark: band.dark, thin: band.thin,
                           role: band.role, alpha: band.alpha, bracket: k)
    }
  }

  /// 签（含 2 pt 间隙）和盘口梯那一块交叠就挪到梯子左边，纵向不动。原来挂着的签贴主图右缘，
  /// 正好盖在盘口梯上（签在十字线层、在梯子上面），五档买卖读不出来（压测 2026-09-28，SOL 1m「19.9M」）。
  static func orderFlowDodgeLadder(_ r: CGRect, ladder: CGRect?) -> CGRect {
    guard let ladder else { return r }
    let g = orderFlowLabelGap
    guard r.minX < ladder.maxX, r.maxX > ladder.minX - g, r.minY < ladder.maxY + g, r.maxY > ladder.minY - g else { return r }
    return CGRect(x: ladder.minX - g - r.width, y: r.minY, width: r.width, height: r.height)
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
    let ladder = state.orderFlow == nil ? nil : depthEnvelope(pane: pane, range: range, L: L)
    if let hit = cache.entries.first(where: {
      $0.pane == pane && $0.range == range && $0.plotW == L.plotW && $0.ladder == ladder
    }) {
      return hit.frame
    }
    let value = computeOrderFlowBands(pane: pane, range: range, L: L, ladder: ladder)
    cache.computed += 1
    if cache.entries.count >= 4 { cache.entries.removeFirst() }
    cache.entries.append((pane, range, L.plotW, ladder, value))
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
  ///
  /// 轻点（`touch`）只认看得清的那几条：底噪（`.noise`，1 pt、≤ 35%）点不中——一屏几百条淡线一条挨一条，
  /// 各放一圈命中区就把整张主图铺满了，点哪儿都出卡、十字线开不出来（压测 2026-09-28，LINK 15 分钟 6000+ 单）；
  /// 44 pt 的放宽也只给主档（`.main`，一屏最多 6 条、写着金额），次档按十字线的容差。底噪照旧能用十字线停上去看。
  static func orderFlowHit(_ bands: [OrderFlowBand], x: Double, y: Double, touch: Bool = false) -> OrderFlowBand? {
    let bands = touch ? bands.filter { $0.role != .noise } : bands
    let half = { (b: OrderFlowBand) in max(Double(b.frame.height), orderFlowHitHeight) / 2 }
    let slopX = { (b: OrderFlowBand) in
      touch && b.role == .main ? max(orderFlowHitSlopX, (orderFlowTouchTarget - Double(b.frame.width)) / 2) : orderFlowHitSlopX
    }
    let slopY = { (b: OrderFlowBand) in
      touch && b.role == .main ? max(orderFlowHitSlop, (orderFlowTouchTarget - 2 * half(b)) / 2) : orderFlowHitSlop
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

  /// 轻点这一下是不是点在一根 K 线上（视图坐标）：横向落在那一根的格子里（不足 8pt 按 8pt 算），
  /// 纵向落在它的高低范围上下各放 `candleHitSlop` 以内（收盘价画法只认收盘那一点）。
  /// K 线是主体、大单只垫在蜡烛底下——点在蜡烛上要出十字线，不让位给底下那条带子的详情卡。
  public func candleHit(at point: CGPoint, size: CGSize) -> Bool {
    let s = state.series
    guard !s.isEmpty else { return false }
    let L = layout(size: size)
    let x = Double(point.x), y = Double(point.y)
    guard x >= 0, x <= L.plotW, y >= L.main.y, y <= L.main.y + L.main.h else { return false }
    let i = s.index(atTime: state.view.t(atX: x, plotW: L.plotW))
    guard s.close.indices.contains(i) else { return false }
    let spacing = state.view.barSpacing(step: s.step, plotW: L.plotW)
    let cx = state.view.x(Double(s.time(at: i)), plotW: L.plotW)
    guard abs(x - cx) <= max(spacing / 2, 4) else { return false }
    let closeOnly = state.options.kind == .line
    var hi = closeOnly ? s.close[i] : s.high[i], lo = closeOnly ? s.close[i] : s.low[i]
    // 平均 K 线画出来的那一根可能越过真实高低，一并算进去。
    if state.options.kind == .heikin, let ha = heikin?.bar(i) { hi = max(hi, ha.h); lo = min(lo, ha.l) }
    let range = priceRange(size: size), mode = state.effectivePriceMode
    let y1 = KanpanCore.yOf(hi, pane: L.main, range: range, mode: mode)
    let y2 = KanpanCore.yOf(lo, pane: L.main, range: range, mode: mode)
    return y >= min(y1, y2) - Self.candleHitSlop && y <= max(y1, y2) + Self.candleHitSlop
  }

  /// 点蜡烛的纵向容差（pt）：影线只有一两 pt 粗，手指点不那么准。
  static let candleHitSlop = 6.0

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
    // 切段、并墙都只在同侧同类里进行，所以从整份快照的墙里挑同侧同类的，和只拿这一类单现算一遍逐堵相同、先后也相同
    // （都按 `drawOrder`）；整份的那份拖图时缓存着，不再每帧、每层各切一遍（压测 2026-09-28：7–10 ms × 3 次 / 帧）。
    let walls = orderFlowWalls(flow).lazy.map(\.group).filter { $0.key.sameKind(key) }
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
    var candle: OrderFlowCardBudget.Candle?
    if hit.hovered, let cross = state.crosshair {
      let i = min(max(0, cross.index), state.series.count - 1)
      anchorX = state.view.x(Double(state.series.time(at: i)), plotW: L.plotW)
      // 十字线那根 K 线：平均 K 线换的是四个价，影线范围按画出来的那根算。
      let b = state.series
      let bar = heikin?.bar(i) ?? (o: b.open[i], h: b.high[i], l: b.low[i], c: b.close[i])
      let map = PriceMapping(range: range, mode: state.effectivePriceMode)
      let hy = map.y(bar.h, pane: L.main), ly = map.y(bar.l, pane: L.main)
      let half = max(2, state.view.barSpacing(step: b.step, plotW: L.plotW) / 2)
      if hy.isFinite, ly.isFinite {
        candle = OrderFlowCardBudget.Candle(left: anchorX - half, right: anchorX + half,
                                            top: max(L.main.y, min(hy, ly)), bottom: min(L.main.y + L.main.h, max(hy, ly)))
      }
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
                               mainBottom: L.main.y + L.main.h, mainHeight: L.main.h, asOfMs: flow.asOfMs,
                               candle: candle)
  }

  private func computeOrderFlowBands(pane: Pane, range: PriceRange, L: Layout, ladder: CGRect?) -> OrderFlowFrame {
    guard let flow = orderFlowSnapshot, flow.phase == .ready, !flow.orders.isEmpty,
          !state.series.isEmpty, L.plotW > 0 else { return OrderFlowFrame() }
    let mode = state.effectivePriceMode
    let y = { (p: Double) in KanpanCore.yOf(p, pane: pane, range: range, mode: mode) }
    let spacing = state.view.barSpacing(step: state.series.step, plotW: L.plotW)

    // 1. 逐单：图例合计只算过了显示开关、还挂着、落在主图里、横向落在这一屏的单（逐单求和，不因合并变）；
    //    挂着的那几单随墙一起在缓存里挑好，不再每帧扫整份快照。
    var frame = OrderFlowFrame()
    let entry = orderFlowEntry(flow)
    // 先按时间粗筛（两个整数比较），落在这一屏以外的不再逐条二分找 K 线：1 分钟 2 万单时挂着的两千单、
    // 三千多堵墙每帧各二分一两次，拖图一帧光这里就 0.6 ms（压测 2026-09-28 第二轮 D1）。筛法与逐条算的结果完全一致。
    let (tLo, tHi) = orderFlowVisibleTimes(spacing: spacing, plotW: L.plotW)
    // 「首见那根的左缘在主图右缘以左」恰好就是 `firstSeenMs < tHi`（见 `orderFlowVisibleTimes`），不必再逐单二分。
    for order in entry.live where order.firstSeenMs < tHi {
      let cy = y(order.price)
      guard cy.isFinite, cy >= pane.y, cy <= pane.y + pane.h else { continue }
      if order.side == .bid { frame.bidTotal += order.notional } else { frame.askTotal += order.notional }
    }

    // 2. 按「桶 × 侧 × 类 × 时间段」切段（切段只看时间与周期，不看这一屏：段的身份跨缩放、平移稳定），
    //    去掉活不过一根 K 线的已结束段，把相邻桶、时间连着的段并成墙、建组、按 `drawOrder` 排好——这一半与视野无关，
    //    走 `OrderFlowWallCache`，拖图、捏合不重算。这里只按墙的时间跨度筛出横向落在这一屏的。
    //    价位：代表价（画线的那个价）落在主图里才算。
    //    横向范围：墙起点那根的左缘到墙结束那根的右缘，有一单还挂着就到主图右缘。
    var visible: [(group: OrderFlowGroup, left: Double, right: Double)] = []
    for wall in entry.walls {
      guard wall.startMs < tHi, (wall.endMs ?? .max) >= tLo,
            let span = orderFlowWallSpan(wall, pane: pane, spacing: spacing, plotW: L.plotW, y: y) else { continue }
      visible.append((wall.group, span.left, span.right))
    }
    guard !visible.isEmpty else { return frame }
    // 屏内排名：画法名义从大到小，一样的先起的在前，再按键（`drawOrder`）。墙在缓存里已按它排好，筛出来的子序列顺序不变。

    // 3. 按排名定主次与线粗：主 2 pt（还挂着 2.5）、次 1 pt 70%、底噪 1 pt 35%。主、次按排名落线，
    //    和已落下的（整条或细线）横向交叠、纵向重叠（含 1 pt 间隙）就压成 1 pt 细线、不写金额。底噪不占位、不被压。
    //    跨桶的主墙另记价位范围（最低桶价 … 最高桶价 + 步长），在段右端立一枚范围括号；范围比线还窄、任一端出了主图、
    //    或和已立的括号在同一 x 上纵向重叠就不立（只留名义大的那枚）。括号不占线的位。
    var noise: [OrderFlowBand] = [], full: [OrderFlowBand] = [], thin: [OrderFlowBand] = []
    var noiseColor: [Int] = []
    var occupied: [CGRect] = [], brackets: [CGRect] = []
    // 颜色只有 侧 × 类 × 深浅 八种：先算好。原来每条带各算一遍 `orderFlowColor`——浅色档要二分找混色比例、
    // 每步都格式化一次十六进制串，一屏几百条带光配色就要几毫秒（压测 2026-09-28）。
    let palette = orderFlowPalette()
    let colorIndex = { (g: OrderFlowGroup) in (g.contract ? 4 : 0) + (g.side == .bid ? 0 : 2) + (g.hasFill ? 1 : 0) }
    let colorOf = { (g: OrderFlowGroup) in palette[colorIndex(g)] }
    for (rank, (group, left, right)) in visible.enumerated() {
      var role: OrderFlowRole = rank < Self.orderFlowMainCount ? .main
        : rank < Self.orderFlowRankedCount ? .secondary : .noise
      if role == .noise, group.isLive { role = .secondary }
      let cy = y(group.price)
      let color = colorOf(group)
      let line = { (h: Double) in CGRect(x: left, y: cy - h / 2, width: right - left, height: h) }
      if role == .noise {
        noise.append(OrderFlowBand(group: group, frame: line(Self.orderFlowNoiseLine), color: color, dark: group.hasFill,
                                   thin: false, role: .noise, alpha: Self.orderFlowNoiseAlpha))
        noiseColor.append(colorIndex(group))
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
          // 整段范围（含两端横钩）都落在主图里才立；任一端出界整枚不画、不裁一截——
          // 1 分钟 BTC 一堵 300 美元的墙比整张主图还高，几枚裁剩的括号叠成一根贯穿主图的竖线（2026-09-25 复验）。
          if bottom - top > whole.height, top >= pane.y, bottom <= pane.y + pane.h {
            bracket = Self.orderFlowBracket(live: group.isLive, lineRight: right,
                                            labelWidth: Self.orderFlowLabelWidth(Self.orderFlowAmount(group.notional)),
                                            plotW: L.plotW, top: top, bottom: bottom, mid: cy, ladder: ladder)
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
      // 同一 x 上和已立的括号纵向重叠的不再立（按排名先立的是名义大的）；不错开 x，签照旧紧贴。
      let kept = clash ? nil : bracket.flatMap { k in
        brackets.contains { $0.minX < k.maxX && $0.maxX > k.minX && $0.minY < k.maxY && $0.maxY > k.minY } ? nil : k
      }
      if let kept { brackets.append(kept) }
      let band = OrderFlowBand(group: group, frame: rect, color: color, dark: group.hasFill, thin: clash, role: role,
                               alpha: alpha, bracket: kept)
      if clash { thin.append(band) } else { full.append(band) }
    }
    frame.labels = orderFlowLabels(full.filter { $0.role == .main }, pane: pane, range: range, L: L, spacing: spacing,
                                   ladder: ladder)
    full = Self.orderFlowBracketsFollowLabels(full, labels: frame.labels)
    frame.bands = noise + full + thin
    frame.noiseStrokes = Self.orderFlowMergeNoise(noise, colorIndex: noiseColor, max: Self.orderFlowNoiseDrawMax)
    return frame
  }

  /// 金额签（只给「主」里没被压细的，按排名）：还挂着的贴主图右缘（价格刻度列左侧、不进刻度列）、
  /// 不进顶上图例那几行（`mainLegendInset`）、开着盘口时不压盘口梯（挪到梯子左边，`orderFlowDodgeLadder`）、
  /// 已结束的放在结束点右侧（放不下就往左收到主图右缘以内）。
  /// 签纵向压到签底下那几根 K 线（含影线）就横向让开（`orderFlowCandleDodge`）：挂着的往左让到压着的最右一根左侧 2 pt，
  /// 让出主图左缘就不放（上方让不开再试线下方）；已结束的往右让到压着的最左一根右侧 2 pt，出了主图右缘就不放。
  /// 已结束的先试五个位置——结束点右侧居中、右侧线上方、右侧线下方、结束点左侧（签在自己线的范围里）线上方、线下方——
  /// 哪个不用横向挪就用哪个（签仍贴在结束点上），都压着蜡烛才取右侧居中往右让过去的；让出主图右缘就在五处里取
  /// 盖住蜡烛面积最少的那处（密到哪儿都是蜡烛时签不能没有：金额是这堵墙最要紧的一个数，K 线只被 85% 不透明的一小块盖住）。
  /// 原来墙贴着最新价时，签正好盖住最新那几根的影线和实体；结束点就是价格穿过墙的地方，蜡烛必然在那儿，
  /// 已结束的签也照样盖着（第三轮验收截图「BTC-1m-金额签」里的「84.9M」）。
  /// 纵向：已结束的居中在线上（签在线的右边，不压线）；挂着的签底坐在线上方 2 pt（`orderFlowLabelLineGap`）——
  /// 原来也居中，签贴主图右缘正好把线最新那一截（挂单此刻的位置）盖住（第二轮 D3）；上方会进图例、或撞了已放下的签而下方不撞，就翻到线下方 2 pt。
  /// 和已放下的签撞了（留 2 pt）：挪到撞上那枚的上方或下方，取离自己本该在的位置近的、不再撞任何一枚、
  /// 没出主图、离线不超过 32 pt 的那个位置；都不行就不放。名义大的先放，所以让位的总是名义小的。一屏最多 6 枚。
  private func orderFlowLabels(_ mains: [OrderFlowBand], pane: Pane, range: PriceRange, L: Layout, spacing: Double,
                               ladder: CGRect?) -> [OrderFlowLabel] {
    let h = Self.orderFlowLabelHeight, gap = Self.orderFlowLabelGap
    // 签躲 K 线：一屏只建一次（映射、半根宽都是这一屏的），逐签只查签底下那几根。
    let candleDodge = mains.isEmpty ? nil : orderFlowCandleDodge(pane: pane, range: range, plotW: L.plotW, spacing: spacing)
    let bg = state.colors.bg
    // 签的上界是图例下沿（`mainLegendInset`，K 线定标也从这里起算）：原来夹在主图顶上，
    // 价位靠上的挂单签会盖在「均线 … / 主力 买 … 卖 …」那几行读数上。
    let ceiling = pane.y + min(mainLegendInset(plotW: L.plotW), max(0, pane.h - h))
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
      let clamp = { (top: Double) in min(max(top, ceiling), pane.y + pane.h - h) }
      let live = band.group.isLive
      let half = Double(band.frame.height) / 2, lift = Self.orderFlowLabelLineGap
      let above = mid - half - lift - h, below = mid + half + lift
      // 想放的位置（横向落点 × 签顶），按先后：
      // 挂着的：贴右缘、线上方；再线下方（上方撞了别的签、会进图例、或躲 K 线让出了主图左缘时）。
      // 已结束的：结束点右侧居中、右侧线上方、右侧线下方；再结束点左侧（签右缘 = 结束点 − 4 pt，整枚在线的横向范围里才算）
      // 线上方、线下方——这五处哪个不用横向挪就用哪个（签仍贴在结束点上）。都压着蜡烛就横向让：左侧那两处沿这条线
      // 往左滑（签左缘不出线的起点；线走过的这一段价格只在一侧，线的另一侧多半是空的），右侧居中往右让，两者取挪得少的。
      let xL = Double(band.frame.maxX) - Self.orderFlowLabelInset - w
      let wants: [(x: Double, top: Double, left: Bool)]
      if live {
        wants = (above >= ceiling ? [above, below] : [below]).map { (x, $0, false) }
      } else {
        var w0: [(x: Double, top: Double, left: Bool)] = above >= ceiling
          ? [(x, mid - h / 2, false), (x, above, false), (x, below, false)] : [(x, mid - h / 2, false), (x, below, false)]
        if xL >= max(0, Double(band.frame.minX)) {
          if above >= ceiling { w0.append((xL, above, true)) }
          w0.append((xL, below, true))
        }
        wants = w0
      }
      let preferred = wants[0].top + h / 2
      // 横向：先躲盘口梯，再躲 K 线（挂着的往左、让出主图左缘给 nil；已结束的往右、出了主图右缘给 nil）。
      // 往右让过 K 线可能正好让进盘口梯：梯子贴主图右缘，右边没地方了，这一处算放不下（压测 2026-10-03，
      // 图右边留着空白、最新那根在梯子左边十几 pt 时，BTC 1m「9.4M」落进梯子）。
      let shift = { (want: CGRect) -> CGRect? in
        let r = Self.orderFlowDodgeLadder(want, ladder: ladder)
        guard let candleDodge else { return r }
        guard let d = candleDodge.dodge(r, !live, 0), Self.orderFlowDodgeLadder(d, ladder: ladder) == d else { return nil }
        return d
      }
      let place = { (want: (x: Double, top: Double, left: Bool)) -> CGRect? in
        // 线在图例那几行里（价高出了定标区）：签夹到图例下沿后离线太远就不放，免得签认错线。
        guard let r = shift(CGRect(x: want.x, y: clamp(want.top), width: w, height: h)),
              r.minX >= 0, abs(Double(r.midY) - mid) <= Self.orderFlowLabelMaxShift else { return nil }
        // 结束点左侧的两处只在不用横向挪时算数（往右挪就回到结束点右侧那几处了）。
        if want.left, abs(Double(r.minX) - want.x) > 1e-9 { return nil }
        return r
      }
      let first: CGRect?
      if live {
        first = wants.lazy.compactMap(place).first
      } else {
        let placed = wants.compactMap { want in place(want).map { (rect: $0, moved: abs(Double($0.minX) - want.x) > 1e-9) } }
        // 五处里先取不用横向挪、也不压蜡烛的；没有就横向让：左侧线上方 / 线下方沿线往左滑到不压蜡烛为止
        // （签左缘不出线的起点，见 `orderFlowCandleDodge` 的 `floor`），右侧居中往右让过去，两者取离原位近的；
        // 都让不出去（左边滑到线头、右边出了主图），就在五处（不挪）里取盖住蜡烛面积最少的——
        // 签不能没有，金额是这堵墙最要紧的一个数。第三轮只往右让，长线的结束点撞进一片高蜡烛时右边总是让不开，
        // 签就落回压着蜡烛的那处；线身上明明空着一整段。
        let nominal = wants.compactMap { want -> CGRect? in
          let r = Self.orderFlowDodgeLadder(CGRect(x: want.x, y: clamp(want.top), width: w, height: h), ladder: ladder)
          return r.minX >= 0 && abs(Double(r.midY) - mid) <= Self.orderFlowLabelMaxShift ? r : nil
        }
        let floor = max(0, Double(band.frame.minX))
        let slid = wants.filter(\.left).compactMap { want -> (rect: CGRect, moved: Double)? in
          let r0 = Self.orderFlowDodgeLadder(CGRect(x: want.x, y: clamp(want.top), width: w, height: h), ladder: ladder)
          guard abs(Double(r0.midY) - mid) <= Self.orderFlowLabelMaxShift,
                let r = candleDodge?.dodge(r0, false, floor) else { return nil }
          return (r, abs(Double(r.minX) - want.x))
        }
        let pushed = placed.first.map { (rect: $0.rect, moved: abs(Double($0.rect.minX) - x)) }
        first = placed.first { !$0.moved }?.rect
          ?? (slid + [pushed].compactMap { $0 }).min { $0.moved < $1.moved }?.rect
          ?? nominal.min { (candleDodge?.overlap($0) ?? 0) < (candleDodge?.overlap($1) ?? 0) }
      }
      guard var rect = first else { continue }
      if collides(rect), let other = wants.dropFirst().lazy.compactMap(place).first(where: { !collides($0) }) {
        rect = other
      }
      if collides(rect) {
        let hits = labels.filter { l in
          l.frame.minX < rect.maxX && l.frame.maxX > rect.minX
            && rect.minY < l.frame.maxY + gap && rect.maxY > l.frame.minY - gap
        }
        let tops = hits.flatMap { [Double($0.frame.minY) - gap - h, Double($0.frame.maxY) + gap] }
        let fits = tops
          .filter { $0 >= ceiling && $0 + h <= pane.y + pane.h && abs($0 + h / 2 - mid) <= Self.orderFlowLabelMaxShift }
          .compactMap { shift(CGRect(x: x, y: $0, width: w, height: h)) }
          .filter { $0.minX >= 0 && !collides($0) }
          .min { abs(Double($0.midY) - preferred) < abs(Double($1.midY) - preferred) }
        guard let fit = fits else { continue }
        rect = fit
      }
      let shown = mixHex(band.color, bg, 1 - Self.orderFlowLabelAlpha)
      labels.append(OrderFlowLabel(key: band.key, text: text, frame: rect, fill: band.color,
                                   ink: Self.orderFlowLabelInk(shown)))
    }
    return labels
  }

  /// 金额签躲 K 线：给一枚签的框，签横向范围里有蜡烛（含影线；平均 K 线按画出来的那根，收盘价画法按那一截折线）
  /// 和它纵向重叠，就把签横向挪开，纵向不动；挪过去又压到下一根就接着让，直到不压任何一根。不压就原样返回。
  /// `toRight` 为假往左让：签右缘 = 压着的最右一根左缘 − 2 pt，签左缘越过 `floor` 给 nil
  /// （挂着的签 `floor` 是 0，让出主图左缘就不放；已结束的签沿线往左滑时 `floor` 是线的起点，滑到线头还压着就不放）；
  /// 为真（已结束的）往右让：签左缘 = 压着的最左一根右缘 + 2 pt，出了主图右缘（价格刻度列左侧 4 pt）给 nil。
  /// 蜡烛横向按「中心 ± 格宽 / 3 + 0.5 pt」算（实体宽是格宽的 2/3、按设备像素取整，最多多出一个像素）。
  /// 每帧拖图都会走到：先二分找到签一侧缘的那一根，再朝让的方向逐根看，看到整根落在签另一侧以外就停——只查签底下那几根。
  /// `overlap` 给一枚签的框算它盖住的蜡烛面积（pt²，各根与签相交的矩形之和）：已结束的签几处都压着时取盖得最少的那处。
  struct OrderFlowCandleProbe {
    let dodge: (CGRect, _ toRight: Bool, _ floor: Double) -> CGRect?
    let overlap: (CGRect) -> Double
  }

  func orderFlowCandleDodge(pane: Pane, range: PriceRange, plotW: Double, spacing: Double) -> OrderFlowCandleProbe {
    let b = state.series
    let n = b.count
    let view = state.view
    let map = PriceMapping(range: range, mode: state.effectivePriceMode)
    let ha = heikin
    let closeOnly = state.options.kind == .line
    let half = max(1, spacing / 3 + 0.5)
    let gap = Self.orderFlowLabelCandleGap
    let cx = { (i: Int) in view.x(Double(b.time(at: i)), plotW: plotW) }
    // 第 i 根画出来的纵向范围（y 小的在上）。
    let extent = { (i: Int) -> (top: Double, bottom: Double) in
      var hi: Double, lo: Double
      if closeOnly {
        // 收盘价折线：这一格里是前后两段各半截，端点在相邻两根收盘价的中点。
        let c = b.close[i]
        let prev = i > 0 ? (b.close[i - 1] + c) / 2 : c, next = i + 1 < n ? (b.close[i + 1] + c) / 2 : c
        hi = max(c, prev, next); lo = min(c, prev, next)
      } else if let bar = ha?.bar(i) {
        hi = bar.h; lo = bar.l
      } else {
        hi = b.high[i]; lo = b.low[i]
      }
      let y1 = map.y(hi, pane: pane), y2 = map.y(lo, pane: pane)
      return (min(y1, y2), max(y1, y2))
    }
    let limit = plotW - Self.orderFlowLabelInset
    let hits = { (i: Int, r: CGRect) -> Bool in
      let e = extent(i)
      return e.top.isFinite && e.bottom.isFinite && e.top < Double(r.maxY) && e.bottom > Double(r.minY)
    }
    let overlap = { (r: CGRect) -> Double in
      guard n > 0 else { return 0 }
      var lo = 0, hi = n
      while lo < hi {
        let mid = (lo + hi) / 2
        if cx(mid) + half > Double(r.minX) { hi = mid } else { lo = mid + 1 }
      }
      var total = 0.0
      var i = lo
      while i < n {
        let c = cx(i)
        if c - half >= Double(r.maxX) { break }
        let e = extent(i)
        if e.top.isFinite, e.bottom.isFinite {
          let dy = min(e.bottom, Double(r.maxY)) - max(e.top, Double(r.minY))
          let dx = min(c + half, Double(r.maxX)) - max(c - half, Double(r.minX))
          if dy > 0, dx > 0 { total += dx * dy }
        }
        i += 1
      }
      return total
    }
    let dodge = { (rect: CGRect, toRight: Bool, floor: Double) -> CGRect? in
      guard n > 0 else { return rect }
      var r = rect
      var lo = 0, hi = n
      if toRight {
        // 第一根右缘 > 签左缘的（右缘随下标单调增）；从它起往右看。
        while lo < hi {
          let mid = (lo + hi) / 2
          if cx(mid) + half > Double(r.minX) { hi = mid } else { lo = mid + 1 }
        }
        var i = lo
        while i < n {
          let c = cx(i)
          let right = c + half
          if c - half >= Double(r.maxX) { break }
          if right > Double(r.minX), hits(i, r) {
            r.origin.x = CGFloat(right + gap)
            if Double(r.maxX) > limit { return nil }
          }
          i += 1
        }
        return r
      }
      // 第一根左缘 ≥ 签右缘的（左缘随下标单调增）；它左边那根起往左看。
      while lo < hi {
        let mid = (lo + hi) / 2
        if cx(mid) - half >= Double(r.maxX) { hi = mid } else { lo = mid + 1 }
      }
      var i = lo - 1
      while i >= 0 {
        let c = cx(i)
        let left = c - half
        if c + half <= Double(r.minX) { break }
        if left < Double(r.maxX), hits(i, r) {
          r.origin.x = CGFloat(left - gap) - r.width
          if Double(r.minX) < floor { return nil }
        }
        i -= 1
      }
      return r
    }
    return OrderFlowCandleProbe(dodge: dodge, overlap: overlap)
  }

  /// `color` 以 `alpha` 叠在 `bg` 上读出来的颜色（不透明）。按三元组记下来：一帧只有十来种。
  static func orderFlowPremixed(_ color: Hex, alpha: Double, bg: Hex) -> Hex {
    guard alpha < 1 else { return color }
    let key = PremixKey(color: color, alpha: alpha, bg: bg)
    premixLock.lock()
    defer { premixLock.unlock() }
    if let hit = premixMemo[key] { return hit }
    let value = mixHex(color, bg, 1 - alpha)
    if premixMemo.count >= 256 { premixMemo.removeAll() }
    premixMemo[key] = value
    return value
  }

  private struct PremixKey: Hashable {
    let color: Hex, alpha: Double, bg: Hex
  }
  private nonisolated(unsafe) static var premixMemo: [PremixKey: Hex] = [:]
  private static let premixLock = NSLock()

  /// 底噪按像素行并：线顶对齐到整 pt（1 pt 线正好占一行像素，挪动不超过半 pt），同一行、同色（侧 × 类 × 深浅，
  /// `colorIndex`）、横向重叠或相隔不超过 `orderFlowNoiseJoin` 的并成一条（左右取并集，名次取最前的）；
  /// 并完超过 `max` 条就按名次留前 `max` 条（名义小的先丢）。输出按名次排。`noise` 须按名次排好。
  static func orderFlowMergeNoise(_ noise: [OrderFlowBand], colorIndex: [Int], max: Int) -> [OrderFlowStroke] {
    guard !noise.isEmpty else { return [] }
    let h = orderFlowNoiseLine
    // (颜色, 行, 左, 右, 名次)，按 颜色 → 行 → 左 排，一趟扫过去并。
    var items: [(color: Int, row: Int, left: Double, right: Double, rank: Int)] = []
    items.reserveCapacity(noise.count)
    for (rank, band) in noise.enumerated() {
      let row = Int((Double(band.frame.midY) - h / 2).rounded())
      items.append((colorIndex[rank], row, Double(band.frame.minX), Double(band.frame.maxX), rank))
    }
    items.sort { a, b in
      a.color != b.color ? a.color < b.color : a.row != b.row ? a.row < b.row : a.left < b.left
    }
    var out: [OrderFlowStroke] = []
    var cur = items[0]
    let flush = { (c: (color: Int, row: Int, left: Double, right: Double, rank: Int)) in
      out.append(OrderFlowStroke(frame: CGRect(x: c.left, y: Double(c.row), width: c.right - c.left, height: h),
                                 color: noise[c.rank].color, rank: c.rank))
    }
    for item in items.dropFirst() {
      if item.color == cur.color, item.row == cur.row, item.left <= cur.right + orderFlowNoiseJoin {
        cur.right = Swift.max(cur.right, item.right)
        if item.rank < cur.rank { cur.rank = item.rank }
      } else {
        flush(cur)
        cur = item
      }
    }
    flush(cur)
    out.sort { $0.rank < $1.rank }
    if out.count > max { out.removeSubrange(max...) }
    return out
  }

  /// 一堵墙在这一屏的横向范围：墙起点那根的左缘到墙结束那根的右缘（还挂着的到主图右缘），至少 1 pt；
  /// 横向不落在主图里、或代表价（画线的那个价）不在主图里的给 nil。
  /// 画出来的只有代表价那条线（括号要两端都在主图里才立），所以只认代表价落在主图里的墙。
  /// 原来跨桶的墙按「价位范围和主图有交集」算：代表价在主图外、线被裁掉看不见的墙照样占排名，
  /// 把看得见的墙挤出「主」那 6 位（压测 2026-09-28：BTC 1m 一屏 49 条里 5 条画在主图外）。
  private func orderFlowWallSpan(_ wall: OrderFlowWallCache.Wall, pane: Pane, spacing: Double, plotW: Double,
                                 y: (Double) -> Double) -> (left: Double, right: Double)? {
    guard let x0 = orderFlowBarX(wall.startMs, spacing: spacing, plotW: plotW)?.left else { return nil }
    let x1: Double
    if let end = wall.endMs {
      guard let bar = orderFlowBarX(end, spacing: spacing, plotW: plotW) else { return nil }
      x1 = bar.right
    } else {
      x1 = plotW
    }
    let left = max(0, x0), right = min(plotW, max(x1, x0 + 1))
    guard right > left, left < plotW else { return nil }
    let cy = y(wall.group.price)
    guard cy.isFinite, cy >= pane.y, cy <= pane.y + pane.h else { return nil }
    return (left, right)
  }

  /// 不做时间粗筛、逐墙算出这一屏落进来几堵（只给测试核对粗筛没丢墙）。
  func orderFlowFrameUnfiltered(size: CGSize) -> Int {
    guard let flow = orderFlowSnapshot, flow.phase == .ready, !state.series.isEmpty else { return 0 }
    let L = layout(size: size)
    let range = priceRange(size: size), mode = state.effectivePriceMode
    let spacing = state.view.barSpacing(step: state.series.step, plotW: L.plotW)
    let y = { (p: Double) in KanpanCore.yOf(p, pane: L.main, range: range, mode: mode) }
    return orderFlowEntry(flow).walls.filter {
      orderFlowWallSpan($0, pane: L.main, spacing: spacing, plotW: L.plotW, y: y) != nil
    }.count
  }

  /// 这一屏在时间上的粗筛界：起点 ≥ `hi` 的（起点那根的左缘已在主图右缘以外）、结束 < `lo` 的（结束那根的右缘
  /// 在 -1 pt 以左，连 1 pt 的最短线也落不进来）一定看不见。和 `orderFlowBarX` 用同一套「时刻落在哪根」，
  /// 所以筛掉的恰好是逐条算也会丢的。
  private func orderFlowVisibleTimes(spacing: Double, plotW: Double) -> (lo: Int64, hi: Int64) {
    let b = state.series
    let n = b.count
    guard n > 0 else { return (.max, .min) }
    let cx = { (i: Int) in self.state.view.x(Double(b.time(at: i)), plotW: plotW) }
    // 第一根满足 pred 的下标（pred 随下标单调由假变真）；都不满足给 n。
    let first = { (pred: (Int) -> Bool) -> Int in
      var lo = 0, hi = n
      while lo < hi {
        let mid = (lo + hi) / 2
        if pred(mid) { hi = mid } else { lo = mid + 1 }
      }
      return lo
    }
    let iL = first { cx($0) + spacing / 2 > -1 }
    let iR = first { cx($0) - spacing / 2 >= plotW }
    return (iL < n ? b.time(at: iL) : .max, iR < n ? b.time(at: iR) : .max)
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

  /// 线、底噪、括号（以及选中重画的那一条）能画到的范围：主图里图例区（`mainLegendInset`，K 线定标也从这里起算）以下。
  /// 墙的价位可以落进图例那几行（价格轴按 K 线定标），原来线就从「主力 买 … 卖 …」「均线 …」的字中间穿过去（2026-09-29）。
  func orderFlowPlotClip(pane: Pane, plotW: Double) -> CGRect {
    let top = min(max(0, mainLegendInset(plotW: plotW)), pane.h)
    return CGRect(x: 0, y: pane.y + top, width: plotW, height: pane.h - top)
  }

  /// 在 plotLayer 上画线（在蜡烛之前调，垫在 K 线下面）：底噪、整条、细线依次，最后是跨桶主墙的范围括号。
  /// 返回画了几条（给测试核对）。
  @discardableResult
  func drawOrderFlow(_ ctx: CGContext, pane: Pane, range: PriceRange, L: Layout) -> Int {
    let frame = orderFlowBands(pane: pane, range: range, L: L)
    if orderFlowCache.servedStale { orderFlowCache.plotStale = true }
    guard !frame.bands.isEmpty else { return 0 }
    ctx.saveGState()
    // 只画在图例区以下（见文件头）：墙的价位落进图例那几行时线不从字中间穿过去。
    ctx.clip(to: orderFlowPlotClip(pane: pane, plotW: L.plotW))
    // 底噪画并过行、封过顶的那几条（1 分钟一屏 500 多条 → 200 条以内）；整条、细线逐条画。
    // 半透明的线改成「先和图区底色混好、再不透明地填」：线直接画在底色（和一两道网格发丝线）上，混好的颜色
    // 与 35% / 70% 叠上去读起来一样，但不透明填是整行拷贝、半透明填要逐像素混，同样的面积快四到五倍——
    // 1 分钟一屏还挂着的次档就有两三百条、每条横贯到主图右缘，逐条半透明填要 1.9 ms（第二轮 D1）。
    // 代价：两条线交叠处不再叠深（后画的盖住先画的），线压着的网格发丝线不再透出来——1 pt 宽，看不出。
    // 按「色 × 不透明度」归好批、一批只设一次色（层内同色的挨着画：整条彼此不重叠，细线同色重叠处看不出先后）；
    // 每条仍单独 `fill(rect)`——一次 `fill([CGRect])` 走的是通用路径光栅化，实测比逐条填慢一倍（第二轮 D1）。
    let bg = state.colors.bg
    var batches: [(color: Hex, alpha: Double, rects: [CGRect])] = []
    let flushBatches = {
      for batch in batches {
        ctx.setFillColor(Paint.cg(Self.orderFlowPremixed(batch.color, alpha: batch.alpha, bg: bg)))
        for rect in batch.rects { ctx.fill(rect) }
      }
      batches.removeAll(keepingCapacity: true)
    }
    let add = { (rect: CGRect, color: Hex, alpha: Double) in
      if let i = batches.firstIndex(where: { $0.alpha == alpha && $0.color == color }) {
        batches[i].rects.append(rect)
      } else {
        batches.append((color, alpha, [rect]))
      }
    }
    for stroke in frame.noiseStrokes { add(stroke.frame, stroke.color, Self.orderFlowNoiseAlpha) }
    flushBatches()
    for band in frame.bands where band.role != .noise && !band.thin { add(band.frame, band.color, band.alpha) }
    flushBatches()
    for band in frame.bands where band.thin { add(band.frame, band.color, band.alpha) }
    flushBatches()
    ctx.setAlpha(CGFloat(Self.orderFlowBracketAlpha))
    for band in frame.bands where band.role == .main {
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
    ctx.clip(to: orderFlowPlotClip(pane: pane, plotW: L.plotW))
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

  /// 名义金额：K / M / B / T 一位小数（原来没有 T 档，图例合计过万亿写成「1000.0B」）。
  /// 单位按印出来的样子选（`volUnit(_:decimals:plainDecimals:)`）：999,960 是「1.0M」，不是「1000.0K」。
  static func orderFlowAmount(_ value: Double) -> String {
    switch volUnit(value, decimals: 1, plainDecimals: 0) {
    case .t: toFixed(value / 1e12, 1) + "T"
    case .b: toFixed(value / 1e9, 1) + "B"
    case .m: toFixed(value / 1e6, 1) + "M"
    case .k: toFixed(value / 1e3, 1) + "K"
    case .plain: toFixed(value, 0)
    }
  }
}
