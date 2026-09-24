import KanpanChart
import KanpanCore
import SwiftUI
import UIKit

/// 成片顶上那一条要说的话：徽章 · 品种 · 周期 · 最新价 · 涨跌。
///
/// 只放这四样。发出去的那张图是给人看「什么东西、什么周期、现在多少钱」的，
/// 时间戳、线路、版本号一概不写——那是我们自己的事，写在图上只会让人去猜它的含义。
struct ChartShotHead: Equatable {
  var symbol: String
  var interval: Interval
  var price: Double?
  var decimals: Int
  var changePercent: Double?

  /// 「BTCUSDT」拆成「BTC」+「/USDT」，和顶栏一个拆法。
  var base: String {
    SymbolInfo.placeholder(symbol: symbol).base
  }
  var quote: String { SymbolInfo.placeholder(symbol: symbol).quote }
  var priceText: String { price.map { grouped(fmtPrice($0, decimals: decimals)) } ?? "—" }
}

/// 把眼前这张图离屏画成一张可以发出去的图片。
///
/// 单独一份而不是长在 `ChartHost` 里，是因为有两处要用同一张成片：面板里的
/// 「分享图片」，和「记一笔」自动附在记录上的那张（两者必须长得一模一样，
/// 否则复盘本里翻出来的图和当初发给朋友的对不上）。
///
/// 画法走 `ChartRenderer.draw(in:size:scale:)`——和屏幕上那张图是同一支笔，
/// 所以画线、指标、最新价、配色天然一致，不需要在这儿重描一遍。按同样的尺寸出图，
/// 视野（`state.view`）也就原样落在同一个位置上。截屏式的 `drawHierarchy` 不用：
/// 那会把面板、十字线、状态栏一起收进去。
@MainActor
enum ChartSnapshotRenderer {
  /// 出图倍率。2× 够清楚，也不至于让一张图大到发不出去。
  static let scale: CGFloat = 2

  /// 只画图本身。
  static func chartImage(state: ChartState, size: CGSize, scale: CGFloat = scale) -> UIImage? {
    guard size.width > 1, size.height > 1, !state.series.isEmpty else { return nil }
    var shot = state
    // 十字线是「我的手正按在这儿」，不是这张图的内容。
    shot.crosshair = nil
    let format = UIGraphicsImageRendererFormat.preferred()
    format.scale = scale
    format.opaque = true
    let renderer = ChartRenderer(state: shot)
    return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
      renderer.draw(in: ctx.cgContext, size: size, scale: scale)
    }
  }

  static func thumbnail(state: ChartState, size: CGSize) -> Data? {
    guard let image = chartImage(state: state, size: size, scale: 1) else { return nil }
    let target = CGSize(width: 600, height: 600 * size.height / size.width)
    let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
    let scaled = UIGraphicsImageRenderer(size: target, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: target))
    }
    guard let data = scaled.jpegData(compressionQuality: 0.8), data.count <= 300 * 1024 else { return nil }
    return data
  }

  /// 成片：身份条 + 图 + 右下角一个很小的字样。
  static func image(state: ChartState, size: CGSize, head: ChartShotHead,
                    theme: PanelTheme) -> UIImage? {
    guard let chart = chartImage(state: state, size: size) else { return nil }
    let card = ChartShotCard(chart: Image(uiImage: chart), chartSize: size, head: head)
      .environment(\.panelTheme, theme)
    let renderer = ImageRenderer(content: card)
    renderer.scale = scale
    renderer.isOpaque = true
    renderer.proposedSize = ProposedViewSize(width: size.width, height: nil)
    return renderer.uiImage
  }

  /// 成片的 PNG。复盘那边要的是字节（存进记录目录、传给服务端）。
  static func png(state: ChartState, size: CGSize, head: ChartShotHead,
                  theme: PanelTheme) -> Data? {
    image(state: state, size: size, head: head, theme: theme)?.pngData()
  }

  /// 出图并交给系统分享面板。画不出来（数据还没到、图还没量出尺寸）返回 false，
  /// 由调用方决定要不要说一句。
  @discardableResult
  static func share(state: ChartState, size: CGSize, head: ChartShotHead,
                    theme: PanelTheme) -> Bool {
    guard let data = png(state: state, size: size, head: head, theme: theme) else { return false }
    let name = "\(InstrumentID(head.symbol).symbol)-\(head.interval.rawValue).png"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    do { try data.write(to: url, options: .atomic) } catch { return false }
    present(url)
    return true
  }

  /// 面板是一层 sheet，点完这行它正在往下收。系统不许在它收的过程中再叠一层，
  /// 所以这儿等它收干净再上——等不到就算了，不弹任何东西。
  /// 账号页「导出我的数据」也走这一处（P3.6），全 app 只有这一个系统分享面板的入口。
  static func present(_ url: URL) {
    Task { @MainActor in
      for _ in 0..<20 {
        if let host = topViewController(), host.presentedViewController == nil,
           host.view.window != nil, !host.isBeingDismissed {
          let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
          if let pop = sheet.popoverPresentationController {
            pop.sourceView = host.view
            pop.sourceRect = CGRect(x: host.view.bounds.midX, y: host.view.bounds.maxY - 40,
                                    width: 1, height: 1)
            pop.permittedArrowDirections = []
          }
          host.present(sheet, animated: true)
          return
        }
        try? await Task.sleep(for: .milliseconds(120))
      }
    }
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first
    guard var vc = window?.rootViewController else { return nil }
    while let next = vc.presentedViewController, !next.isBeingDismissed { vc = next }
    return vc
  }
}

/// 成片的排版。
///
/// 身份条站在皮肤的底色上（`app`），图区是图自己的底（`chart.bg`）——和 app 里
/// 头部压着 K 线的关系一致，发出去的图看着就是这个 app 的一页。
private struct ChartShotCard: View {
  var chart: Image
  var chartSize: CGSize
  var head: ChartShotHead

  @Environment(\.panelTheme) private var t

  var body: some View {
    VStack(spacing: 0) {
      strip
      chart
        .resizable()
        .frame(width: chartSize.width, height: chartSize.height)
      footer
    }
    .frame(width: chartSize.width)
    .background(t.app)
  }

  // 成片是一张定稿的图，不跟系统文字大小走：字号取令牌的设计值，按固定字画
  // （`ImageRenderer` 离屏出图，跟着 Dynamic Type 放大只会让不同人发出去的图长得不一样）。
  private func fixed(_ spec: ScaledFont) -> Font {
    .system(size: spec.size, weight: spec.weight, design: spec.design)
  }

  /// 身份条：左边徽章 · 品种 · 周期，右边最新价一行、涨跌一行小字紧贴其下（和行情页顶栏
  /// 一个排法，UI 整改 P3）。原来价和一颗实心涨跌药丸横排，药丸在别处都已经拿掉了。
  private var strip: some View {
    HStack(spacing: Space.s) {
      CoinBadge(base: head.base, size: ControlMetrics.badge)
      HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
        Text(head.base)
          .font(fixed(TypeScale.heading))
          .foregroundStyle(t.ink)
        if !head.quote.isEmpty {
          Text("/" + head.quote)
            .font(fixed(TypeScale.caption2Emph))
            .foregroundStyle(t.ink3)
        }
        Text("· " + head.interval.shortLabel)
          .font(fixed(TypeScale.caption2Emph))
          .foregroundStyle(t.ink3)
      }
      .lineLimit(1)
      Spacer(minLength: Space.s)
      VStack(alignment: .trailing, spacing: 0) {
        Text(head.priceText)
          .font(fixed(TypeScale.heading))
          .monospacedDigit()
          .foregroundStyle(tint)
        // 涨跌只用「符号 + 颜色」：+2.74% / −2.74%（数学减号 U+2212），不填底。
        Text(changePercentText(head.changePercent))
          .font(fixed(TypeScale.caption2Emph))
          .monospacedDigit()
          .foregroundStyle(head.changePercent == nil ? t.ink3 : tint)
      }
      .lineLimit(1)
    }
    .padding(.horizontal, Inset.cardCompact)
    .padding(.vertical, Space.s)
  }

  /// 右下角的字样。品牌字是全 app 唯一低于 11 的字：它不是要人读的内容，只是一个落款。
  private static let brandSize: CGFloat = 10

  private var footer: some View {
    HStack(spacing: 0) {
      Spacer(minLength: 0)
      Text("Hkline")
        .font(.system(size: Self.brandSize, weight: .semibold))
        .tracking(0.6)
        .foregroundStyle(t.ink3.opacity(0.7))
    }
    .padding(.horizontal, Inset.cardCompact)
    .padding(.top, Space.xs)
    .padding(.bottom, Space.s)
  }

  private var tint: Color {
    guard let pct = head.changePercent else { return t.ink }
    return pct >= 0 ? t.up : t.down
  }
}
