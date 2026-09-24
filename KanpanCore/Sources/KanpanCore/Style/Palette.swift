import Foundation

/// 颜色。Core 不碰 UIKit，所以用 8 位十六进制字符串存，取用时再转 RGBA。
public struct Hex: Sendable, Equatable, Hashable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
  /// 原样的 `#RRGGBB` 或 `#RRGGBBAA`，和原型字符串逐字相同。
  public let value: String

  public init(_ value: String) { self.value = value }
  public init(stringLiteral value: String) { self.init(value) }
  public var description: String { value }

  /// 归一化后的 RGBA，0…1。解析不了就是透明黑。
  /// 0–255 的四个通道。混色、解析都走这里，免得在浮点上来回换。
  public var bytes: (r: Int, g: Int, b: Int, a: Int) {
    var hex = Substring(value)
    if hex.hasPrefix("#") { hex = hex.dropFirst() }
    let d = hex.compactMap { $0.hexDigitValue }
    guard d.count >= 6 else { return (0, 0, 0, 255) }
    let a = d.count >= 8 ? d[6] * 16 + d[7] : 255
    return (d[0] * 16 + d[1], d[2] * 16 + d[3], d[4] * 16 + d[5], a)
  }

  public var rgba: (r: Double, g: Double, b: Double, a: Double) {
    var s = Substring(value)
    if s.hasPrefix("#") { s = s.dropFirst() }
    guard s.count == 6 || s.count == 8, let n = UInt32(s, radix: 16) else { return (0, 0, 0, 0) }
    if s.count == 6 {
      return (Double((n >> 16) & 0xFF) / 255, Double((n >> 8) & 0xFF) / 255, Double(n & 0xFF) / 255, 1)
    }
    return (Double((n >> 24) & 0xFF) / 255, Double((n >> 16) & 0xFF) / 255,
            Double((n >> 8) & 0xFF) / 255, Double(n & 0xFF) / 255)
  }

  /// 叠一层 alpha（两位十六进制，和原型 `a(hex, aa)` 一样是字符串拼接）。
  public func alpha(_ aa: String) -> Hex { Hex(value + aa) }
}

/// 三套皮肤：青苔（冷，出厂）、陶土（暖）、经典（白）。
///
/// 皮肤是谁，由种子**自己报**，不再拿颜色去比。以前 `isWarm` / `isClassic` 是拿 `ground`
/// 和陶土、经典两套种子的底色逐字比出来的（审查 2026-09-24 §1.4）：哪天给经典的底换一支
/// 更准的白，「它是不是经典」这个判断就悄悄翻了——自选页、板块页的底跟着换错，而且没有
/// 任何一条测试会红。存档与同步走 rawValue，三个名字都不能改。
public enum Skin: String, Sendable, Codable, CaseIterable, Hashable {
  case sage, terra, classic
}

/// 一套配色的原始令牌。
///
/// `amber` 是**画在图上**的那支暖色（BOLL 中轴、画线手柄）；`accent` 是**界面**的强调色
/// （选中的周期、底栏当前项、面板里的动作字）。两者分开是因为这一版的两套配色里，
/// 界面强调色是配色自己的主色（青苔的墨绿、陶土的赤陶），而图上那支暖色仍要和
/// K 线、均线区分得开——合成一支的话，要么图上多一支绿线和涨色撞，要么界面变土黄。
public struct PaletteSeed: Sendable, Equatable {
  /// 这套种子属于哪张皮肤。冷暖、是不是「经典」都只问它。
  public var skin: Skin
  public var dark: Bool
  public var ground, app, chart, raised, raised2: Hex
  public var line, grid, hair: Hex
  public var ink, ink2, ink3: Hex
  public var up, down, amber: Hex
  /// 界面强调色。
  public var accent: Hex
  /// **警示色：删除、注销、报错这类「不可逆 / 出事了」的动作字。**
  ///
  /// 单开一支是被一个真 bug 逼出来的：画线栏上那个「删除」原来取 `down`（跌色），
  /// 想的是「跌 = 红 = 危险」。可看盘的涨跌色是照 AICoin 手机端来的，出厂就是
  /// **红涨绿跌**（`Prefs.redUp` 默认 `true`），于是跌色是**绿的**——选中一条线之后，
  /// 那个「删除」读起来像「确认 / 通过」。而且它还跟着用户的涨跌开关翻：同一个按钮
  /// 今天红明天绿，取决于一个跟删除毫无关系的设置。
  ///
  /// 所以警示是警示、涨跌是涨跌，两件事各有各的令牌。这一支**不参与 `redUp` 对调**，
  /// 也不出现在图上（`ChartColors` 里没有它）——图上的颜色是 AICoin 那一套，不动。
  /// 六套各配一档：浅色是压深的砖红（青苔偏冷、陶土偏暖、经典取中性正红），
  /// 深色各自提亮，都过 4.5:1。
  public var danger: Hex
  public var palette: [Hex]
  /// 副图线（MAVOL / DIF、DEA / RSI）依次取色。不给就跟主图 `palette` 同一组。
  /// AICoin 的副图线走的是它自己那张「槽位色板」（青绿、黄、紫、蓝…），和主图均线
  /// 按周期挑的颜色不是一个顺序，所以「经典」得单独给一组。
  public var sub: [Hex]

  public init(skin: Skin, dark: Bool, ground: Hex, app: Hex, chart: Hex, raised: Hex, raised2: Hex,
              line: Hex, grid: Hex, hair: Hex, ink: Hex, ink2: Hex, ink3: Hex,
              up: Hex, down: Hex, amber: Hex, accent: Hex? = nil, danger: Hex, palette: [Hex],
              sub: [Hex]? = nil) {
    self.skin = skin
    self.dark = dark
    self.ground = ground; self.app = app; self.chart = chart
    self.raised = raised; self.raised2 = raised2
    self.line = line; self.grid = grid; self.hair = hair
    self.ink = ink; self.ink2 = ink2; self.ink3 = ink3
    self.up = up; self.down = down; self.amber = amber
    self.accent = accent ?? amber
    self.danger = danger
    self.palette = palette
    self.sub = sub ?? palette
  }
}

/// 图表用色（原型 `expand(t).chart` 加上几个常用的派生令牌）。
public struct ChartColors: Sendable, Equatable {
  public var bg, grid, axis, text, dim, ink, amber, cross: Hex
  public var band, oi, oiFill: Hex
  public var chip, panel: Hex
  public var crossBg, crossInk: Hex
  /// 比网格还淡一层的发丝线。
  public var hair: Hex
  public var amberSoft, amberLine: Hex
  /// 涨 / 跌。注意这两个会被「红涨绿跌」开关对调。
  public var up, down: Hex
  /// 主图指标线（MA / EMA / BOLL）依次取色。
  public var palette: [Hex]
  /// 副图线（MAVOL / DIF、DEA / RSI…）依次取色。青苔、陶土和 `palette` 同一组；
  /// 经典按 AICoin 的槽位色板另给一组。
  public var sub: [Hex]
}

/// 三套配色：青苔（冷，出厂）、陶土（暖）与经典（白），各有浅深两版。
///
/// K 线与指标的**画法**一个像素都不改——这里换的只有颜色。蜡烛的宽度、间距、
/// 副图的分区、读数那一行的排布全在 `KanpanChart` 里，和这份表没有关系。
///
/// **画布只有「经典」不跟皮肤走。** 2026-09-17 曾把 K 线绘图区（主图 + 副图 + 坐标轴）
/// 一律固定成 AICoin 那套白 / 深蓝，理由是染过底的画布会让蜡烛和均线压在一层带色的面上。
/// 2026-09-18 用户推翻了这条：「既然现在有了经典这个风格复刻了 aicoin，那么青苔冷和陶土暖的
/// k 线指标展示区域也不再用 aicoin 那种白色的颜色。会显得特别割接这是最大的原因之一」
/// 「还是用之前那两种风格的背景颜色即可，这样整体就搭配了」。
///
/// 所以现在：**想要原汁原味的 AICoin 就切「经典」**，那一套一个像素不差；青苔和陶土是两套
/// 自己的皮肤，图区的底、网格、分隔线、轴文字全跟着种子走（见 `Palette.canvas(_:)`），
/// 整屏不再在图区的四条边上各切一刀。
///
/// 种子里仍带着涨跌色、`amber`、MA 那组 `palette` 和副图那组 `sub`，因为涨跌与 MA 色在头部胶囊、
/// 自选列表里也出现，图里图外必须是同一个红、同一个绿。但**浅色下这几组三套皮肤完全一样，都是
/// AICoin 手机端的那套**（`aicoinDayUp` / `aicoinDayDown` / `aicoinDayMA` / `aicoinSlots`）：用户 2026-09-17
/// 看完真机说「浅色所有模式下的 K 线颜色都统一成 AICoin 那种」「以后不再另起一套」。皮肤要融的是
/// 图外，不是图。深色版 AICoin 没在真机量过，青苔 / 陶土深色暂时还各带自己的一组。
/// 种子里的 `chart` 字段就是画布底色（经典的那支正好等于 AICoin 的白 / 深蓝，所以两条路同归）。
public enum Palette: Sendable {
  // ---------------------------------------------------------------- 青苔（冷）

  /// 青苔 · 浅。全新安装就是这一套。
  public static let sageSeed = PaletteSeed(
    skin: .sage, dark: false,
    ground: "#C3D6CA", app: "#F3F7F4", chart: "#F3F7F4", raised: "#FFFFFF", raised2: "#E7EFE9",
    line: "#D6E3DA", grid: "#E2EBE5", hair: "#14211B0F",
    ink: "#14211B", ink2: "#4E6158", ink3: "#606F67",
    up: aicoinDayUp, down: aicoinDayDown, amber: "#B57C28", accent: "#2E7D6B", danger: sageDanger,
    palette: aicoinDayMA, sub: aicoinSlots)

  /// 青苔 · 深。
  public static let sageNightSeed = PaletteSeed(
    skin: .sage, dark: true,
    ground: "#060A08", app: "#0B120F", chart: "#0B120F", raised: "#131C18", raised2: "#1A241F",
    line: "#25332C", grid: "#1A241F", hair: "#FFFFFF0A",
    ink: "#E9F2EC", ink2: "#A5B8AE", ink3: "#7B8D85",
    up: "#4FB69C", down: "#E36159", amber: "#E0A544", accent: "#4FB69C", danger: sageNightDanger,
    palette: ["#E0A544", "#7D9AE8", "#4FB69C", "#E894B4", "#BDAEDC", "#7FD0FF"])

  // ---------------------------------------------------------------- 陶土（暖）

  /// 陶土 · 浅。
  public static let terraSeed = PaletteSeed(
    skin: .terra, dark: false,
    ground: "#D9C7B4", app: "#FBF6F0", chart: "#FBF6F0", raised: "#FFFFFF", raised2: "#F2E8DE",
    line: "#E7DACB", grid: "#F0E6DA", hair: "#241A130F",
    ink: "#241A13", ink2: "#6E5C4D", ink3: "#756659",
    up: aicoinDayUp, down: aicoinDayDown, amber: "#B37B25", accent: "#B25735", danger: terraDanger,
    palette: aicoinDayMA, sub: aicoinSlots)

  /// 陶土 · 深。
  public static let terraNightSeed = PaletteSeed(
    skin: .terra, dark: true,
    ground: "#0C0805", app: "#16100C", chart: "#16100C", raised: "#211812", raised2: "#2A1F17",
    line: "#37281D", grid: "#2A1F17", hair: "#FFFFFF0A",
    ink: "#F7EFE6", ink2: "#C2AC98", ink3: "#958576",
    up: "#3FA783", down: "#E0584A", amber: "#E0A544", accent: "#E2874F", danger: terraNightDanger,
    palette: ["#E0A544", "#9B8AE0", "#3FA783", "#E894B4", "#C0AEE0", "#85B8D6"])

  // ---------------------------------------------------------------- 经典（白）

  /// 经典 · 浅。青苔的文字与强调色原样，底换成 AICoin 的白。
  ///
  /// **行情页底是纯白，不是带蓝的白。** 2026-09-17 第一版把 `app` 写成了 `#F7F9FF`，那是安卓包里的
  /// `sh_base_bg_color`，K 线页根本不用它；用户在真机上一眼看出「AICoin 的白没这么白亮」。逐像素实测
  /// 他手机上的 AICoin 行情页：顶部标题、价格行、周期行、主图、副图**全是 `#FFFFFF`**，只有最底下的
  /// 标签栏是 `#F3F3F5`。安卓资源对得上——`sh_base_view_bg` = `#ffffff`（通用页面底，引用 23 次）、
  /// `ui_kline_menu_bg_color` = `#ffffff`（周期栏 / 指标条 / 画线条底，7 次）。`#F7F9FF` 那支蓝白既不是
  /// AICoin 的页面底，又让纯白的画布在上面显成一块更亮的补丁，正好犯了「整屏一块连续材料」那条。
  ///
  /// 所以：页面与画布 `#FFFFFF`（`sh_base_view_bg`），再往下一层的自选页底 `#F7F8FA`
  /// （`sh_base_page_bg`，中性灰、不带蓝），徽章底 `#F3F5F7`（`ui_kline_scale_auto_bg_color`），
  /// 分割线 `#EAEAEA`（`ui_kline_indicator_bar_divider_color`，就是 AICoin 周期 / 指标条上下那条）——
  /// 不要再拿通用列表的 `sh_base_divider_dim_fill_color` = `#DEE1E5`，那支在纯白页面上明显发灰。
  /// 涨跌与指标线色跟青苔 / 陶土浅色一样都是 AICoin 的（见 `aicoinDayUp` 一组）。
  public static let classicSeed = PaletteSeed(
    skin: .classic, dark: false,
    ground: "#F7F8FA", app: "#FFFFFF", chart: "#FFFFFF", raised: "#FFFFFF", raised2: "#F3F5F7",
    line: "#EAEAEA", grid: "#EAEAEA", hair: "#14211B0F",
    ink: "#14211B", ink2: "#4E6158", ink3: "#606F67",
    up: aicoinDayUp, down: aicoinDayDown, amber: "#B57C28", accent: "#2E7D6B", danger: classicDanger,
    palette: aicoinDayMA, sub: aicoinSlots)

  /// 经典 · 深。底是 AICoin 夜间的 `#0D111C`（`sh_base_view_bg_night`）/ `#090C14`
  /// （`sh_base_page_bg_night`）/ `#202126` / `#303442` / `#20232E`
  /// （`ui_kline_indicator_bar_divider_color_night`）；
  /// 涨跌取安卓包 `sh_base_text_color_green_night` / `_red_night`（`#2F9347` / `#CC3333`），
  /// 指标线沿用安卓默认槽位色。深色这组没在真机上量过（镜像后台点不动，切不了夜间模式）。
  public static let classicNightSeed = PaletteSeed(
    skin: .classic, dark: true,
    ground: "#090C14", app: "#0D111C", chart: "#0D111C", raised: "#202126", raised2: "#303442",
    line: "#20232E", grid: "#20232E", hair: "#FFFFFF0A",
    ink: "#E9F2EC", ink2: "#A5B8AE", ink3: "#7B8D85",
    up: "#2F9347", down: "#CC3333", amber: "#E0A544", accent: "#4FB69C", danger: classicNightDanger,
    palette: ["#FFB400", "#E849B9", "#B2DF8A", "#FB9A99", "#1478C8", "#2FD2B2"],
    sub: aicoinNightSlots)

  // ---------------------------------------------------------------- 警示色

  /// 三套皮肤各自的警示色（见 `PaletteSeed.danger`）。
  ///
  /// 都是红的——「危险」这一档的红是全世界通用的读法，改不得；能调的只有它**是哪一支红**。
  /// 所以三套各按自己的调子偏一点：青苔往冷里偏（带一点蓝的砖红），陶土往暖里偏
  /// （偏赭的陶红，和它的赤陶强调色是一家人），经典取不偏不倚的正红（那一套本来就是
  /// 照 AICoin 复刻的中性皮肤）。
  ///
  /// 六支都刻意**压暗 / 提亮到离蜡烛那支红（浅色 `#E64552`）足够远**：删除按钮不该和
  /// 图上的涨跌读成同一支颜色，否则换个皮肤就又分不清「这是危险还是行情」。
  /// 落在各自的 `app` / `raised` / `raised2` 上都在 4.4:1 以上（见 `SkinPaletteTests`）。
  public static let sageDanger: Hex = "#B93A2E"
  public static let sageNightDanger: Hex = "#F08A80"
  public static let terraDanger: Hex = "#AE3F2A"
  public static let terraNightDanger: Hex = "#F0947C"
  public static let classicDanger: Hex = "#C62828"
  public static let classicNightDanger: Hex = "#EF7A72"

  // ---------------------------------------------------------------- AICoin 的 K 线色

  /// AICoin iPhone 端浅色的蜡烛涨跌色。用户 2026-09-17 的手机截图逐像素统计的众数
  /// （比安卓包 `#32A853` / `#EB4236` 略亮）；顶栏最新价、涨跌幅胶囊也用这两支（实测 `#34A756`，同一支）。
  public static let aicoinDayUp: Hex = "#36B257"
  public static let aicoinDayDown: Hex = "#E64552"
  /// AICoin 主图 MA 依次取的色：MA10 黄、MA30 紫、MA120 绿、MA256 珊瑚（用户手机上这四条占槽位
  /// 第 2、3、5、6 格），后两格给第五、六条均线和 BOLL 带 / 持仓量用。
  public static let aicoinDayMA: [Hex] = ["#FFB400", "#E849B9", "#6EBF26", "#F55B58", "#1478C8", "#2FD2B2"]

  /// AICoin 指标线的槽位色板前六格：青绿、黄、紫、蓝、绿、珊瑚。安卓包
  /// `refs/aicoin/java/sp/aicoin_kline/core/indicator/config/L.java` 里 MA1…MA6 的默认色就是
  /// `#2FD2B2 #FFB400 #E849B9 #1478C8 #B2DF8A #FB9A99`，MAVOL / RSI / BOLL 和 MACD 的
  /// DIF、DEA、MACD 三条线全按这个顺序取；主图 MA(10,30,120,256) 在用户手机上占的是
  /// 第 2、3、5、6 格。用户 iPhone 浅色截图逐像素实测：DIF `#2FD2B2`、DEA `#FFB400`、
  /// MA30 `#E849B9` 和安卓常量逐位相同，第 5、6 格 iOS 浅色用的是压深的 `#6EBF26` / `#F55B58`
  /// （浅绿、珊瑚压在白底上看不清），深色沿用安卓常量——深色没在真机上量过。
  public static let aicoinSlots: [Hex] = ["#2FD2B2", "#FFB400", "#E849B9", "#1478C8", "#6EBF26", "#F55B58"]
  public static let aicoinNightSlots: [Hex] = ["#2FD2B2", "#FFB400", "#E849B9", "#1478C8", "#B2DF8A", "#FB9A99"]

  /// 「浅 / 深」这两个词在代码里到处都是，指的就是出厂那一套的两版。
  public static let lightSeed = sageSeed
  public static let darkSeed = sageNightSeed

  /// 某张皮肤的浅 / 深那一套种子。全仓挑种子只走这一处。
  public static func seed(_ skin: Skin, dark: Bool) -> PaletteSeed {
    switch skin {
    case .sage: dark ? sageNightSeed : sageSeed
    case .terra: dark ? terraNightSeed : terraSeed
    case .classic: dark ? classicNightSeed : classicSeed
    }
  }

  /// 暖色那一套（陶土）。渐变、徽章那几处要按冷暖分别让一让。
  public static func isWarm(_ t: PaletteSeed) -> Bool { t.skin == .terra }

  /// K 线色是不是 AICoin 那套（浅色三套皮肤都是，深色只有经典）。对比度那几条测试对这些种子不设限：
  /// 它们的目标是「跟 AICoin 一样」，`#FFB400` 在白底上只有 1.8:1 也照抄。
  public static func usesAICoinKLine(_ t: PaletteSeed) -> Bool { !t.dark || t.skin == .classic }

  /// 白底那一套（经典）。自选页的浅色底不再借「天青」，直接用种子自己的白。
  public static func isClassic(_ t: PaletteSeed) -> Bool { t.skin == .classic }

  /// 小字用的第三级墨色。六套种子都是手配的，直接用。
  public static func secondaryInk(_ t: PaletteSeed) -> Hex { t.ink3 }

  public static func contrast(_ foreground: Hex, _ background: Hex) -> Double {
    func luminance(_ c: Hex) -> Double {
      let v = c.rgba
      func linear(_ n: Double) -> Double { n <= 0.04045 ? n / 12.92 : pow((n + 0.055) / 1.055, 2.4) }
      return 0.2126 * linear(v.r) + 0.7152 * linear(v.g) + 0.0722 * linear(v.b)
    }
    let a = luminance(foreground), b = luminance(background)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
  }

  public static func mix(_ a: Hex, _ b: Hex, amount: Double) -> Hex {
    let x = a.bytes, y = b.bytes, f = min(1, max(0, amount))
    func channel(_ a: Int, _ b: Int) -> Int { Int((Double(a) * f + Double(b) * (1 - f)).rounded()) }
    return Hex(String(format: "#%02X%02X%02X", channel(x.r,y.r), channel(x.g,y.g), channel(x.b,y.b)))
  }

  public static func readable(_ text: Hex, on surfaces: [Hex], toward ink: Hex) -> Hex {
    for step in 0...100 {
      let candidate = mix(text, ink, amount: 1 - Double(step) / 100)
      if surfaces.allSatisfy({ contrast(candidate, $0) >= 4.5 }) { return candidate }
    }
    return ink
  }

  /// 由原始令牌推出图表用色，逐行对应原型 `expand()`。
  ///
  /// `ChartState.colors` 是个计算属性，画一帧要读几十次；每读一次 `expanded` 就重拼
  /// 一遍 `.alpha()` 的十六进制串、重建一次调色板数组。可全仓一共就六套种子，
  /// 结果永远是那十二份（六套 × 红涨 / 绿涨）。
  ///
  /// 所以这十二份在第一次用到时一次算好，之后是**只读**的表：按（皮肤, 深浅, 红涨）直接
  /// 定位到那一格，再核一眼种子确实就是那一套，不加锁、不线性扫（审查 2026-09-24 §5）。
  /// 以前是一张加锁的可变小表，每取一次色都要上锁、逐个比种子。
  /// 表外的种子（只有用例会造）现算，不缓存。
  public static func chart(_ t: PaletteSeed, redUp: Bool = false) -> ChartColors {
    let hit = chartTable[chartSlot(t.skin, dark: t.dark, redUp: redUp)]
    return hit.seed == t ? hit.value : derive(t, redUp: redUp)
  }

  private static func chartSlot(_ skin: Skin, dark: Bool, redUp: Bool) -> Int {
    let row = switch skin { case .sage: 0; case .terra: 1; case .classic: 2 }
    return row * 4 + (dark ? 2 : 0) + (redUp ? 1 : 0)
  }

  private static let chartTable: [(seed: PaletteSeed, value: ChartColors)] = {
    var table: [(seed: PaletteSeed, value: ChartColors)] = []
    for skin in [Skin.sage, .terra, .classic] {  // 与 chartSlot 的行号同序
      for dark in [false, true] {
        for redUp in [false, true] {
          let s = seed(skin, dark: dark)
          table.append((s, derive(s, redUp: redUp)))
        }
      }
    }
    return table
  }()

  private static func derive(_ t: PaletteSeed, redUp: Bool) -> ChartColors {
    var result = expanded(t)
    if redUp { swap(&result.up, &result.down) }
    return result
  }

  /// 画布那几样固定色。日 / 夜各一套，和皮肤无关。
  ///
  /// 取自 `71bd340:docs/AICoin-安卓包-UI规格提取.md`（页面底、分割线、三 / 四级文字、`line_grid`）
  /// 与 `docs/acceptance/M8/aicoin-对比.md` §4 的实测值。
  public struct ChartCanvas: Sendable, Equatable {
    public var bg, grid, axis, text, dim, ink, cross: Hex
  }

  /// 白天的画布。
  ///
  /// `axis` 是主图 / 时间轴 / 各副图之间那几条结构分隔线，**必须用 K 线页自己的
  /// `ui_kline_divider_color` = `#F2F4F7`**，不是通用列表分割线 `sh_base_divider_dim_fill_color`
  /// = `#DEE1E5`。这跟当初把页面底错拿成 `sh_base_bg_color` = `#F7F9FF` 是同一类错误：
  /// 名字像就拿，没去量 K 线页那一像素。`ui_kline_frg_ticker_detail_kline.xml:23` 里那条
  /// 1dp 的竖线用的就是 `ui_kline_divider_color`。
  ///
  /// 量给的结论：`#DEE1E5` 离纯白的亮度差约 0.257（对比度 1.32），`#F2F4F7` 只有约 0.035
  /// （对比度 1.04）——旧值是新值的七倍，而整屏有 8 条这样的线，等于把一张纯白的页面
  /// 切成一格一格，正犯「整屏要读成一块连续的材料」那条。AICoin 真机镜像上同位置量到
  /// `#F6F8FC` / `#F9FAFE`（镜像会往白里洗约 12%，还原回去正好是 `#F2F4F7`）。
  ///
  /// `grid` 仍是 `line_grid` = `#C5C5C5`：那是用户主动打开网格时才画的价格网格线和 MACD 零轴，
  /// AICoin 默认也不画网格，两边这一项没有分歧。
  ///
  /// `cross` 是唯一没照抄的一项：AICoin 那份表里日间十字线写的是 `#EEEEEE`，那是画在
  /// 深底上的值，落到 `#FFFFFF` 的画布上等于看不见。取和轴文字同一档的灰蓝，
  /// 权重跟换肤前的 `ink3` 一致。
  public static let dayCanvas = ChartCanvas(
    bg: "#FFFFFF", grid: "#C5C5C5", axis: "#F2F4F7",
    text: "#7A8899", dim: "#B7BFC8", ink: "#292D33", cross: "#7A8899")

  /// 夜里的画布。轴文字仍用 `#7A8899`——在 `#0D111C` 上对比度约 5:1，过得去；
  /// 夜间那组更暗的 `#515A66` 留给 `dim` 这类次要读数。
  ///
  /// `axis` 同样改成 K 线页自己的 `ui_kline_divider_color_night` = `#191C21`，
  /// 原来的 `#25282E` 是通用列表分割线 `sh_base_divider_dim_fill_color_night`。
  /// 深色这组没在真机上量过（镜像里切不了 AICoin 的夜间模式），只按安卓常量对齐。
  public static let nightCanvas = ChartCanvas(
    bg: "#0D111C", grid: "#1C2236", axis: "#191C21",
    text: "#7A8899", dim: "#515A66", ink: "#E6EAF2", cross: "#FFFFFF")

  /// 图区那几样（底、网格、结构分隔线、轴文字、次要读数、主文字、十字线）。
  ///
  /// **只有「经典」照抄 AICoin。** 2026-09-17 定过一版「画布一律固定成 AICoin 那套白 / 深蓝，
  /// 不跟皮肤走」，理由是染过底的画布会让蜡烛和均线压在一层带色的面上。2026-09-18 用户推翻了
  /// 这条，理由比当初那条更硬：「既然现在有了经典这个风格复刻了 aicoin，那么青苔冷和陶土暖的
  /// k 线指标展示区域也不再用 aicoin 那种白色的颜色。会显得特别割接这是最大的原因之一」。
  /// 想要原汁原味的 AICoin 就切「经典」——那一套仍然一个像素不差；青苔和陶土是两套自己的皮肤，
  /// 图区跟着皮肤染，整屏才不会在图区的四条边上各切一刀
  /// （`kanpan-no-seams-one-continuous-surface`）。
  ///
  /// 跟着皮肤走的时候，线与字也得换成皮肤自己的那几支：AICoin 的分隔线 `#F2F4F7` 落在
  /// 青苔的 `#F3F7F4` 上等于没画，轴文字那支蓝灰 `#7A8899` 压在带绿的底上也不是一家人。
  /// 对应关系照搬 AICoin 里的**轻重次序**——网格比结构分隔线重，所以网格取 `line`、
  /// 分隔线取更淡的 `grid`。
  public static func canvas(_ t: PaletteSeed) -> ChartCanvas {
    let base = t.dark ? nightCanvas : dayCanvas
    guard !isClassic(t) else { return base }
    return ChartCanvas(bg: t.chart, grid: t.line, axis: t.grid,
                       text: t.ink3, dim: t.ink3.alpha(t.dark ? "8C" : "99"),
                       ink: t.ink, cross: t.ink2)
  }

  private static func expanded(_ t: PaletteSeed) -> ChartColors {
    let d = t.dark
    let c = canvas(t)
    return ChartColors(
      bg: c.bg, grid: c.grid, axis: c.axis, text: c.text, dim: c.dim,
      ink: c.ink, amber: t.amber, cross: c.cross,
      band: t.palette[4], oi: t.palette[5], oiFill: t.palette[5].alpha(d ? "33" : "2E"),
      chip: d ? t.ground : t.app, panel: t.app,
      crossBg: d ? t.line : t.ink, crossInk: d ? t.ink : t.app,
      hair: t.hair,
      amberSoft: t.amber.alpha(d ? "1A" : "16"), amberLine: t.amber.alpha("55"),
      up: t.up, down: t.down,
      palette: t.palette, sub: t.sub)
  }

  public static func chart(dark: Bool, redUp: Bool = false) -> ChartColors {
    chart(dark ? darkSeed : lightSeed, redUp: redUp)
  }

  /// 遮罩与薄纱，弹层用。
  public static func veil(_ t: PaletteSeed) -> Hex { t.app.alpha(t.dark ? "EE" : "F0") }
  public static func scrim(_ t: PaletteSeed) -> Hex { t.dark ? t.ground.alpha("D9") : t.ink.alpha("4D") }
}
