import SwiftUI
import KanpanCore

/// 品种徽章：一枚带品牌渐变的圆角方块，中间是那个品种的记号。
///
/// 记号分三层，从具体到概括：
///
/// 1. **认得出的牌子**画它自己的标——比特币的 ₿、苹果那一口、亚马逊那道笑弧。
/// 2. **认不出但知道是什么东西**的画品类标：黄金白银是一块金砖，原油是一滴油，
///    天然气是一簇火，指数和 ETF 是三根柱，个股是交易所的门廊。
/// 3. 只剩**长尾的币**才落到字母上，而且只留一个首字母。
///
/// 第 2 层是补出来的。原来只有第 1、3 层，于是 XAU 的「图标」就是「XAU」三个字母、
/// 四个字母的美股代号被砍成两个字（NVDA → NV、MRVL → MR），用户的原话是
/// 「很多品种的图标不对啊，这点你没有设计吗」。代号本来就在徽章右边用粗体写着，
/// 徽章再写一遍等于没有徽章；它该回答的是「这是个什么东西」。
///
/// 尺寸由调用方给：顶栏 29、自选行 33、复盘记录行 29、面板标题旁 24。
/// 这几个数是用户定过的（「图标有点大了显得不协调」），别再往大里调。
struct CoinBadge: View {
  var base: String
  /// 调用方手上有品种资料时把事实分类递进来，徽章就不必靠自己那张表去猜。
  var asset: SymbolClassification.Asset?
  var size: CGFloat = 29

  init(base: String, asset: SymbolClassification.Asset? = nil, size: CGFloat = 29) {
    self.base = base
    self.asset = asset
    self.size = size
  }

  /// 上色要跟着当前皮肤走（见 `BadgeTint`），所以徽章得知道现在是哪一套。
  @Environment(\.panelTheme) private var theme

  private var spec: CoinSpec { CoinSpec.of(base, asset: asset) }
  private var tint: (top: Color, bottom: Color) {
    BadgeTint.gradient(from: spec.from, to: spec.to, seed: theme.seed)
  }

  var body: some View {
    let ink = tint
    return RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
      .fill(LinearGradient(colors: [ink.top, ink.bottom],
                           startPoint: .topLeading, endPoint: .bottomTrailing))
      .frame(width: size, height: size)
      .overlay { glyph }
      // 影子只是让徽章离纸面一点点。原来是 0.34，一排徽章底下拖着一排明显的彩色影子，
      // 在青苔那种极浅的底上像洇开的墨点；收到 0.2 以内，还在，但不抢戏。
      .shadow(color: ink.bottom.opacity(theme.dark ? 0.26 : 0.18),
              radius: size * 0.17, x: 0, y: size * 0.1)
      .accessibilityHidden(true)
  }

  @ViewBuilder private var glyph: some View {
    switch spec.mark {
    case .text(let s):
      Text(s)
        .font(.system(size: size * 0.5, weight: .bold))
        .foregroundStyle(.white)
        .minimumScaleFactor(0.5)
        .lineLimit(1)
        .frame(width: size * 0.86)
    case .parts(let parts):
      ZStack {
        ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
          if let width = part.stroke {
            CoinShape(paths: part.d)
              .stroke(.white, style: StrokeStyle(lineWidth: BadgeLine.weight(width, at: size),
                                                 lineCap: .round, lineJoin: .round))
          } else {
            CoinShape(paths: part.d).fill(.white)
          }
        }
      }
      .frame(width: size * spec.inset, height: size * spec.inset)
    }
  }
}

/// 24×24 的 `viewBox` 原样拿来，等比缩到目标边长。描边宽度也跟着缩，
/// 所以 `.stroke` 里写的就是 24 格坐标系里的宽度。
private struct CoinShape: Shape {
  var paths: [String]
  func path(in rect: CGRect) -> Path {
    // 解析走 `SVGPath.parsed` 的缓存；这儿只剩一次等比变换。
    SVGPath.parsed(paths).applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
  }
}

struct CoinSpec {
  /// 一层笔画。`stroke` 给了就描边，没给就填充——一个记号可以由几层叠出来
  /// （比如 NVDA 是一圈眼眶加中间一颗瞳孔，一层描边一层填充）。
  struct Part {
    var d: [String]
    var stroke: Double?
  }
  enum Mark {
    case text(String)
    case parts([Part])
  }
  var from: Hex
  var to: Hex
  var mark: Mark
  /// 记号占徽章边长的比例。笔画铺得满的记号（金砖、门廊）要收一点，
  /// 不然贴着圆角方块的边，看着像裁掉了。
  var inset: CGFloat = 0.62

  static func fill(_ d: [String]) -> Mark { .parts([Part(d: d, stroke: nil)]) }
  static func stroke(_ d: [String], _ w: Double) -> Mark { .parts([Part(d: d, stroke: w)]) }
}

// MARK: - 品类记号

extension CoinSpec {
  /// 金砖：一块梯形的顶面加一截砖身。贵金属四个（XAU / XAG / XPT / XPD）共用，
  /// 靠渐变分金银铂钯——金子就该是金色的，这件事不能交给散列去猜。
  /// 两块面之间留一道 0.9 的缝，底色透出来才分得出顶面和身子；
  /// 贴在一起画出来只是一团白，认不出是金锭。
  static let ingot = stroke(["M8.6 7.4h6.8l4 9.2H4.6z", "M7.6 11h8.8"], 2.1)
  /// 油滴：原油（CL / BZ）。
  static let drop = stroke(
    ["M12 4.2c3.9 4.7 5.9 7.7 5.9 10.1a5.9 5.9 0 0 1-11.8 0c0-2.4 2-5.4 5.9-10.1z"], 2.1)
  /// 火苗：天然气。
  static let flame = stroke(
    ["M12 3.4c3.2 3.4 5.1 6.1 5.1 8.9a5.1 5.1 0 0 1-10.2 0c0-1.8.6-3.2 1.8-4.6 "
      + ".2 1.4.8 2.3 1.8 2.8-.4-2.8.4-5.3 1.5-7.1z"], 2.1)
}

// MARK: - 认得出的牌子

extension CoinSpec {
  /// 照原型 `COIN` 表抄来的那几支，加上后来补的品牌标。
  ///
  /// 这张表收**认得准**的牌子；个股、港股、韩股的那一批在 `CoinBadgeBrands.swift`，
  /// 两张表一先一后查。都没有的落到 `generated`，按代号散出一枚各自不同的几何标。
  private static let known: [String: CoinSpec] = [
    // ── 加密
    "BTC": CoinSpec(from: "#F9B34A", to: "#EE7A12", mark: .text("₿")),
    "ETH": CoinSpec(from: "#8F97F2", to: "#4B54C8", mark: fill([
      "M12 2.6l5.6 9.1-5.6 3.3-5.6-3.3z", "M12 21.6l5.6-7.9-5.6 3.3-5.6-3.3z"])),
    "SOL": CoinSpec(from: "#19F0A0", to: "#9945FF", mark: fill([
      "M5.4 7.4h11.4l2.2-2.6H7.6z", "M5.4 13.3h11.4l2.2-2.6H7.6z", "M5.4 19.2h11.4l2.2-2.6H7.6z"])),
    "BNB": CoinSpec(from: "#F8D661", to: "#EFB40A", mark: fill([
      "M12 3.1l2.6 2.6L12 8.3 9.4 5.7z", "M12 15.7l2.6 2.6L12 20.9l-2.6-2.6z",
      "M5.7 9.4l2.6 2.6-2.6 2.6L3.1 12z", "M18.3 9.4l2.6 2.6-2.6 2.6L15.7 12z",
      "M12 9.4l2.6 2.6-2.6 2.6L9.4 12z"])),
    "DOGE": CoinSpec(from: "#E3C368", to: "#BFA033", mark: .text("Ð")),
    "XRP": CoinSpec(from: "#5B667A", to: "#252B33", mark: stroke([
      "M6.2 5.6l3.6 3.7 1.1.5 1.1-.5 3.6-3.7", "M6.2 18.4l3.6-3.7 1.1-.5 1.1.5 3.6 3.7"], 2.1)),
    // Sui 的标就是一滴水，原来拿字母 "S" 顶着是因为解析器还不会画曲线。
    "SUI": CoinSpec(from: "#7CC6F7", to: "#3E8FF0", mark: drop),
    // Chainlink：一只六棱壳，里面锁着核。
    "LINK": CoinSpec(from: "#6AA0FF", to: "#2450D4", mark: fill([
      "M12 2.6l8.2 4.7v9.4L12 21.4l-8.2-4.7V7.3zM12 6.6L7.1 9.4v5.2l4.9 2.8 4.9-2.8V9.4z",
      "M12 9.4a2.6 2.6 0 1 1 0 5.2 2.6 2.6 0 0 1 0-5.2z"])),
    // Arbitrum：一枚切了面的宝石。
    "ARB": CoinSpec(from: "#5FA8F5", to: "#2B6FD6", mark: fill(["M7.6 4.4h8.8l3.8 5.2-8.2 10.8L3.8 9.6z"])),
    "AVAX": CoinSpec(from: "#F1616B", to: "#C42832", mark: fill([
      "M12 4.2l8.8 15.4h-5.3L12 13.4 8.5 19.6H3.2z"])),
    "ADA": CoinSpec(from: "#6FA8F0", to: "#1C4FBF", mark: .parts([
      Part(d: ["M12 9.4a2.6 2.6 0 1 1 0 5.2 2.6 2.6 0 0 1 0-5.2z"], stroke: nil),
      Part(d: ["M12 2.6a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3z",
               "M12 18.4a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3z",
               "M4.4 6.8a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3z",
               "M19.6 6.8a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3z",
               "M4.4 14.2a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3z",
               "M19.6 14.2a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3z"], stroke: nil)])),
    // Polkadot：一地的圆点。
    "DOT": CoinSpec(from: "#F583B4", to: "#D4136B", mark: fill([
      "M6 4a2.1 2.1 0 1 1 0 4.2 2.1 2.1 0 0 1 0-4.2z",
      "M12 4a2.1 2.1 0 1 1 0 4.2 2.1 2.1 0 0 1 0-4.2z",
      "M18 4a2.1 2.1 0 1 1 0 4.2 2.1 2.1 0 0 1 0-4.2z",
      "M6 9.9a2.1 2.1 0 1 1 0 4.2 2.1 2.1 0 0 1 0-4.2z",
      "M12 9.9a2.1 2.1 0 1 1 0 4.2 2.1 2.1 0 0 1 0-4.2z",
      "M18 9.9a2.1 2.1 0 1 1 0 4.2 2.1 2.1 0 0 1 0-4.2z",
      "M6 15.8a2.1 2.1 0 1 1 0 4.2 2.1 2.1 0 0 1 0-4.2z",
      "M12 15.8a2.1 2.1 0 1 1 0 4.2 2.1 2.1 0 0 1 0-4.2z",
      "M18 15.8a2.1 2.1 0 1 1 0 4.2 2.1 2.1 0 0 1 0-4.2z"])),
    // 波场：一支横着冲出去的旗标。
    "TRX": CoinSpec(from: "#EE6C6C", to: "#C1272D", mark: fill(["M4.2 3.2L20.6 12 4.2 20.8l2.6-8.8z"])),
    "LTC": CoinSpec(from: "#B9C2CC", to: "#6A7480", mark: .text("Ł")),
    // TON：一支倒三角的钻坯，中间开一道竖槽。槽原来只有 1.6 宽，18px 上摊不到一个像素，
    // 钻坯就糊成一只实心的倒三角，和美团那只袋鼠头、唯链那个 V 挤在一起；开到 2.8 才透得出底。
    "TON": CoinSpec(from: "#63C4F0", to: "#1E88C9", mark: fill([
      "M4.2 5.6h15.6L12 20.8zM10.6 8.4v8.2h2.8V8.4z"])),
    "UNI": CoinSpec(from: "#F98CC4", to: "#D1348C", mark: .parts([
      Part(d: ["M8.4 5.6v10.2", "M15.6 18.4V8.2"], stroke: 2),
      Part(d: ["M8.4 20.4l-3.2-5h6.4z", "M15.6 3.6l3.2 5h-6.4z"], stroke: nil)])),
    // Optimism：一枚厚实的圆环。
    "OP": CoinSpec(from: "#F2686E", to: "#CE1F26", mark: stroke([
      "M12 4.4a7.6 7.6 0 1 1 0 15.2 7.6 7.6 0 0 1 0-15.2z"], 3.0)),
    // Aptos：一枚圆角三角。
    "APT": CoinSpec(from: "#8E95A3", to: "#2C333F", mark: fill([
      "M12 4.2c1.1 0 2 .5 2.6 1.5l5.6 9.7c1.1 1.9-.3 4.2-2.5 4.2H6.3c-2.2 0-3.6-2.3-2.5-4.2l5.6-9.7c.6-1 1.5-1.5 2.6-1.5z"])),
    // 佩佩就是那只青蛙。原来这儿是个「P」——`₿`/`Ð`/`Ł` 是那几个币自己的货币符号，
    // 算记号；一个光秃秃的首字母不算，那是代号缩写，用户否过。
    "PEPE": CoinSpec(from: "#8CD46A", to: "#3E8B2C", mark: .parts([
      Part(d: ["M4.6 12.8c0-3.2 3.3-5.4 7.4-5.4s7.4 2.2 7.4 5.4c0 3.6-3.3 6-7.4 6s-7.4-2.4-7.4-6z",
               "M8 4a3 3 0 1 1 0 6 3 3 0 0 1 0-6z", "M16 4a3 3 0 1 1 0 6 3 3 0 0 1 0-6z",
               "M7.6 14.4c2.6 2 6.2 2 8.8 0"], stroke: 1.8),
      Part(d: ["M8 6a1 1 0 1 1 0 2 1 1 0 0 1 0-2z", "M16 6a1 1 0 1 1 0 2 1 1 0 0 1 0-2z"],
           stroke: nil)])),

    // ── 美股：只画得出名字的那几家
    "AAPL": CoinSpec(from: "#B9BFC9", to: "#61686F", mark: fill([
      "M16.8 12.7c0-2.3 1.9-3.4 2-3.5-1.1-1.6-2.7-1.8-3.3-1.8-1.4-.1-2.8.8-3.5.8s-1.8-.8-3-.8c-1.5 0-3 .9-3.8 2.3-1.6 2.8-.4 7 1.1 9.3.8 1.1 1.7 2.4 2.9 2.3 1.1 0 1.6-.7 3-.7s1.7.7 3 .7c1.2 0 2-1.1 2.8-2.3.9-1.3 1.2-2.5 1.2-2.6-.1 0-2.4-.9-2.4-3.7z",
      "M14.6 5.4c.6-.8 1.1-1.8 1-2.9-.9.1-2 .6-2.7 1.4-.6.7-1.1 1.7-1 2.7 1 .1 2.1-.5 2.7-1.2z"]), inset: 0.58),
    "MSFT": CoinSpec(from: "#7FC4F0", to: "#2B7CB8", mark: fill([
      "M4.4 4.4h7v7h-7z", "M12.6 4.4h7v7h-7z", "M4.4 12.6h7v7h-7z", "M12.6 12.6h7v7h-7z"])),
    "NVDA": CoinSpec(from: "#9BE36A", to: "#3F8A16", mark: .parts([
      Part(d: ["M4.4 12c2.9-3.7 5.4-5.5 7.6-5.5s4.7 1.8 7.6 5.5c-2.9 3.7-5.4 5.5-7.6 5.5S7.3 15.7 4.4 12z"], stroke: 1.9),
      Part(d: ["M12 9.6a2.4 2.4 0 1 1 0 4.8 2.4 2.4 0 0 1 0-4.8z"], stroke: nil)])),
    "TSLA": CoinSpec(from: "#F08080", to: "#B71C1C", mark: fill([
      "M5 6.2c2.1-1 4.4-1.5 7-1.5s4.9.5 7 1.5l-1.4 2.5c-1.3-.5-2.7-.9-4.1-1.1L12 20.2 10.5 7.6c-1.4.2-2.8.6-4.1 1.1z"])),
    "GOOGL": CoinSpec(from: "#8FB6F2", to: "#2F6BD6", mark: stroke([
      "M19.2 12.2h-7", "M19 8.1a7.4 7.4 0 1 0 .4 7"], 2.3)),
    "AMZN": CoinSpec(from: "#F6C06A", to: "#C97A16", mark: .parts([
      Part(d: ["M3.8 14.8c2.7 2.3 5.9 3.5 9 3.5 2.1 0 4.3-.5 6.2-1.6"], stroke: 2),
      Part(d: ["M17.6 15l3.6-.6-1.4 3.4z"], stroke: nil)])),
    "META": CoinSpec(from: "#7EA9F5", to: "#1D5BD6", mark: stroke([
      "M8.5 8.2c2.1 0 3.5 7.6 7 7.6 2.1 0 3.6-1.7 3.6-3.8s-1.5-3.8-3.6-3.8c-3.5 0-4.9 7.6-7 7.6-2.1 0-3.6-1.7-3.6-3.8s1.5-3.8 3.6-3.8z"], 2)),
    "NFLX": CoinSpec(from: "#EF7B7B", to: "#B81D24", mark: fill([
      "M6.9 3.8h3.5v16.4H6.9z", "M13.6 3.8h3.5v16.4h-3.5z", "M6.9 3.8h3.5l6.7 16.4h-3.5z"])),
    "AMD": CoinSpec(from: "#9BD4A0", to: "#2E7D46", mark: fill([
      "M4.4 4.4h9.8v2.7H7.1v7H4.4z", "M19.6 19.6H9.8l9.8-9.8z"])),

    // ── 预发行
    "ANTHROPIC": CoinSpec(from: "#E8A87C", to: "#C4603A", mark: stroke([
      "M12 3.4v6.4", "M12 14.2v6.4", "M3.4 12h6.4", "M14.2 12h6.4",
      "M5.9 5.9l4.5 4.5", "M13.6 13.6l4.5 4.5", "M5.9 18.1l4.5-4.5", "M13.6 10.4l4.5-4.5"], 1.8)),
    "OPENAI": CoinSpec(from: "#8FC7C0", to: "#2E7D6B", mark: stroke([
      "M12 3.6l7.3 4.2v8.4L12 20.4l-7.3-4.2V7.8z", "M12 8.4l3.4 2v4L12 16.4l-3.4-2v-4z"], 1.8)),
  ]
}

// MARK: - 品类归属

extension CoinSpec {
  /// 交易所元数据到不了的时候（顶栏在首屏就要画徽章），靠这几张表认品类。
  /// 币安那套代号是固定的，列全比猜准。
  /// XAUT / PAXG 是链上的金子，跟 XAU 一样该画金锭——它们在币安归在加密那一栏，
  /// 事实分类给的是 `.crypto`，所以只能在这儿点名。
  private static let metals: Set<String> = ["XAU", "XAG", "XPT", "XPD", "XAUT", "PAXG"]
  private static let oils: Set<String> = ["CL", "BZ"]
  private static let gas: Set<String> = ["NATGAS"]
  private static let copper: Set<String> = ["COPPER"]

  /// 材料该是材料的颜色：金子金色、白银灰白、原油近黑。这几支不参与散列。
  private static let material: [String: (Hex, Hex)] = [
    "XAU": ("#F5D07A", "#C08A1E"), "XAG": ("#C3CCD6", "#6E7B8A"),
    "XPT": ("#D6E0E4", "#7B8B93"), "XPD": ("#CBD4CF", "#73827B"),
    "XAUT": ("#F5D07A", "#C08A1E"), "PAXG": ("#F2CE85", "#B8862A"),
    "COPPER": ("#E3A778", "#A9552A"),
    "CL": ("#5A6672", "#232B33"), "BZ": ("#6B7784", "#2C343D"),
    "NATGAS": ("#7FC8E8", "#2C7BA8"),
  ]

  /// 认不出来的那些（长尾的币、没画标的股）：散列到八对备用渐变里的一对。
  /// 原型给的是一对固定的灰紫，但真表里认不出来的占大多数，全灰就等于没有徽章。
  private static let spare: [(Hex, Hex)] = [
    ("#B9B3C6", "#6E6880"), ("#8FC7C0", "#3E8178"), ("#E8B98C", "#B87333"),
    ("#9FB8E8", "#4C6CB5"), ("#D7A8C8", "#95568A"), ("#A9C98C", "#5E8A45"),
    ("#E0C27A", "#A8812C"), ("#93BCD4", "#3D7391"),
  ]

  private struct SpecKey: Hashable {
    var base: String
    var asset: SymbolClassification.Asset?
  }

  /// 品种不多（几百支），一支一条，存满一屏一屏地滚也不会涨到哪儿去。
  private static let memo = RenderMemo<SpecKey, CoinSpec>(limit: 2048)

  /// 这个品种画什么记号。
  ///
  /// 查表 + 剥数字前缀 + 散列出一枚长尾标，一趟下来要过八张字典。结果只取决于
  /// 代号和事实分类，所以按这两样记住——自选表滚一屏是二十几次查表，滚回来又是
  /// 二十几次，都是同样的答案。
  static func of(_ base: String, asset: SymbolClassification.Asset? = nil) -> CoinSpec {
    memo.value(for: SpecKey(base: base.uppercased(), asset: asset)) { resolve(base, asset: asset) }
  }

  private static func resolve(_ base: String, asset: SymbolClassification.Asset?) -> CoinSpec {
    let key = base.uppercased()
    if let hit = known[key] ?? brand(key) { return hit }
    // 「1000PEPE」「1000000BOB」这类杠杆代号：把前缀的数字剥掉再认一次品牌。
    let stripped = String(key.drop(while: \.isNumber))
    if !stripped.isEmpty, let hit = known[stripped] ?? brand(stripped) { return hit }

    let name = stripped.isEmpty ? key : stripped
    let pair = material[name] ?? spare[key.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) % spare.count }]

    // 实物商品是唯一还共用记号的一类：画的是这块东西本身，金子就该是金锭、
    // 原油就该是油滴，四支贵金属靠渐变分金银铂钯。换成各自的几何标反而认不出来。
    // 调用方递进来的事实分类优先，够不着的时候再查自己那几张表。
    if metals.contains(name) || asset == .preciousMetal {
      return CoinSpec(from: pair.0, to: pair.1, mark: ingot, inset: 0.68)
    }
    if oils.contains(name) { return CoinSpec(from: pair.0, to: pair.1, mark: drop, inset: 0.6) }
    if gas.contains(name) { return CoinSpec(from: pair.0, to: pair.1, mark: flame, inset: 0.6) }
    if copper.contains(name) {
      return CoinSpec(from: pair.0, to: pair.1, mark: ingot, inset: 0.68)
    }
    if asset == .commodity { return CoinSpec(from: pair.0, to: pair.1, mark: drop, inset: 0.6) }

    // 剩下的全走长尾标：一支一枚，见 `CoinBadgeBrands.swift`。
    //
    // 这儿原来有两条兜底，两条都被用户否掉了。先是首字母——「像 xau 展示的图标
    // 就是 xau，美股的一些展示缩写」；后是品类标，个股一律画交易所门廊、ETF 一律画
    // 三根柱——「另外美股的图标设计的不对啊」「每个品种都有单独的图标啊」。
    //
    // 两次说的是同一件事：徽章要回答「这一行是哪个品种」。一屏里每行都印着同一个
    // 图形，和每行都印着自己名字的头一个字母一样，都回答不了。所以兜底也得随代号变。
    return generated(name, pair)
  }
}

// MARK: - 徽章上色

/// 徽章的渐变：**画什么**按品种走，**上什么色**按皮肤走。
///
/// 用户在这上头交代了三句：「图标 icon 的设计要搭配整个 ui 的配色等其他的设计，
/// 要自然不要显得很突兀」「不要破坏整体的美感」「最好的效果要非常好看非常搭配」。
///
/// 所以这儿不是把所有徽章刷成一个颜色——那样一屏扫下去就分不出品种了，等于把
/// 「一个品种一个记号」又做没了。做法是把品牌原色请进当前皮肤的色带里：
///
///   · **色相留给品种**，只往皮肤主色偏一小步（12%）。比特币还是橙的、以太坊还是紫的，
///     但整排徽章的色相被轻轻往青苔的墨绿／陶土的赤陶那边拢了一点，像同一套界面里
///     长出来的东西，而不是贴上去的一排别人家的贴纸。
///   · **饱和度封顶**。Costco 的正红、AMD 的荧光绿原样铺在 `#F3F7F4` 这种极浅的底上
///     会直接跳到脸上；收进带子里它们仍是红是绿，只是不再嚷嚷。
///   · **明度收进一段窄带**。XRP、黑石那种近黑的牌子原样画出来是在浅色页面上砸两个洞，
///     抬到带子下沿就成了沉稳的深色块；反过来太亮的也压下来，免得白记号糊在上面。
///   · 深色皮肤下整体再压暗一档，浅色皮肤下留得亮一点——同一支品种在两套皮肤里
///     是同一个颜色的两种说法，不是两支颜色。
///
/// 牌子本身就是中性灰的（苹果、IBM 这种），色相留不住也不必留，直接借皮肤的灰：
/// 出来是青苔灰或陶土灰，看着仍是那块牌子，但和背景是一家的。
enum BadgeTint {
  private struct TintKey: Hashable {
    var from: Hex
    var to: Hex
    /// 只有这两项参与计算，整份 `PaletteSeed` 不必进 key（它也不是 `Hashable`）。
    var accent: Hex
    var dark: Bool
  }

  private static let memo = RenderMemo<TintKey, (top: Color, bottom: Color)>()

  /// 一对渐变端点。`from` 是左上那头（浅），`to` 是右下那头（深）。
  ///
  /// 里头是三趟 hex→HSB、几次色相插值和六次钳位，全是浮点数学。一枚徽章要算一对，
  /// 自选表一行一枚，`FavoritesView` 的光晕还要再算一次同样的值。入参只有
  /// 「品牌两端 + 皮肤主色 + 深浅」，皮肤一次会话里最多换几回，所以按 key 记住。
  static func gradient(from: Hex, to: Hex, seed: PaletteSeed) -> (top: Color, bottom: Color) {
    memo.value(for: TintKey(from: from, to: to, accent: seed.accent, dark: seed.dark)) {
      compute(from: from, to: to, seed: seed)
    }
  }

  private static func compute(from: Hex, to: Hex, seed: PaletteSeed) -> (top: Color, bottom: Color) {
    let a = hsb(from), b = hsb(to)
    let skin = hsb(seed.accent)
    let dark = seed.dark

    // 本来就没有色相的牌子：借皮肤的那一支，配一点点饱和，成一块有倾向的灰。
    if max(a.s, b.s) < 0.12 {
      let s = dark ? 0.15 : 0.13
      return (color(skin.h, s, dark ? 0.46 : 0.74), color(skin.h, s + 0.05, dark ? 0.30 : 0.52))
    }

    let hueA = pull(a.h, toward: skin.h, gold(a.h) ? 0.04 : 0.11)
    let hueB = pull(b.h, toward: skin.h, gold(b.h) ? 0.04 : 0.11)
    // 黄色掉饱和掉得比别的色相快：同样收一档，红的还是红的，黄的直接成橄榄绿，
    // 比特币的金、狗币的金、BNB 的黄会挤成同一坨土色。所以黄到橙那一段松一档。
    let give = gold(a.h) ? 0.14 : 0
    let hi = clamp(a.s, dark ? 0.20 : 0.24, (dark ? 0.56 : 0.52) + give)
    let lo = clamp(b.s, dark ? 0.26 : 0.30, (dark ? 0.66 : 0.60) + give)
    let top = clamp(a.b, dark ? 0.42 : 0.62, (dark ? 0.70 : 0.88) + (give > 0 ? 0.04 : 0))
    return (color(hueA, hi, top),
            color(hueB, lo, clamp(b.b, dark ? 0.30 : 0.46, dark ? 0.56 : 0.70)))
  }

  /// 色相往皮肤主色走一小步。走多了所有徽章会糊成一片同色，走少了又白走——
  /// 一成上下是「一眼看过去是一家的，一个个看还是各是各的」那个位置。
  ///
  /// 黄那一段要走得更少：黄的色相稍微一挪就绿，比特币的金、狗币的金、BNB 的黄
  /// 一起偏过去就是三块橄榄色，看着像发霉。金子得是金子。
  private static func pull(_ h: Double, toward target: Double, _ k: Double) -> Double {
    var d = target - h
    if d > 0.5 { d -= 1 } else if d < -0.5 { d += 1 }
    let r = h + d * k
    return r < 0 ? r + 1 : (r >= 1 ? r - 1 : r)
  }

  /// 黄到橙那一段（色相 0.07…0.20）。
  private static func gold(_ h: Double) -> Bool { h > 0.07 && h < 0.20 }

  private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
    min(max(v, min(lo, hi)), hi)
  }

  private static func color(_ h: Double, _ s: Double, _ b: Double) -> Color {
    Color(hue: h, saturation: s, brightness: b)
  }

  private struct HSB { var h, s, b: Double }

  private static func hsb(_ hex: Hex) -> HSB {
    let (r, g, bl, _) = hex.rgba
    let mx = max(r, g, bl), mn = min(r, g, bl)
    let d = mx - mn
    var h = 0.0
    if d > 0 {
      if mx == r { h = (g - bl) / d + (g < bl ? 6 : 0) } else if mx == g {
        h = (bl - r) / d + 2
      } else {
        h = (r - g) / d + 4
      }
      h /= 6
    }
    return HSB(h: h, s: mx == 0 ? 0 : d / mx, b: mx)
  }
}

// MARK: - 徽章线条

/// 徽章的笔画宽度。
///
/// 用户的话是「线条什么的都需要特调，这样整体才好看，风格才统一」。原来每个记号
/// 各写各的宽度，摊开看是 1.5 到 3.0 一路铺满——同一排里挨着的两枚，一枚细得发虚，
/// 一枚粗得糊成一块，像从两套图标里各抓了一个。
///
/// 这里做两件事：
///
/// **收进一条窄带。** 记号自己的宽度只保留两成八的差（想画细的还是细一点点），
/// 其余往 2.0 上收，最后落在 1.86…2.16 之间。这样一整屏看过去笔锋是一致的，
/// 又不至于把「眼眶那圈本来就该比瞳孔细」这种画法抹平。
///
/// **跟着徽章大小走，但不是线性。** `CoinShape` 只缩路径不缩描边，宽度是实打实的点，
/// 所以同一个数字在 24pt 的面板标题旁比在 33pt 的列表行上显得粗一大截。按边长等比缩
/// 又会让小号那枚细到发灰——字体的「光学尺寸」是一个道理。折中取 0.72 次方：
/// 33pt 上是 2.1，29pt 上 1.9，24pt 上 1.7，三种尺寸并排看粗细观感一样。
enum BadgeLine {
  /// 记号在 24 格坐标系里声明的宽度 → 这枚徽章上实际该描多粗。
  static func weight(_ declared: Double, at size: CGFloat) -> Double {
    let band = min(max(2.0 + (declared - 2.0) * 0.28, 1.86), 2.16)
    return band * pow(Double(size) / 33, 0.72)
  }
}
