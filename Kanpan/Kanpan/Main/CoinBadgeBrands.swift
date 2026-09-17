import KanpanCore
import SwiftUI

// MARK: - 个股品牌标
//
// 用户为品种徽章纠正过两次，落点不一样：
//
//   第一次「像 xau 展示的图标就是 xau，美股的一些展示缩写」——不能拿代号当图标。
//   第二次「另外美股的图标设计的不对啊」「每个品种都有单独的图标啊」——也不能
//   整类共用一个图形。当时所有个股共用一座交易所门廊，一屏美股扫下去每行都是
//   同一座房子，和每行印着自己的字母一样分不出来。
//
// 所以这张表按「一支一个记号」办，画得准优先：
//
//   · 品牌有记号的就画它的记号——苹果那一口、迪士尼三个圆、沃尔玛的火花、
//     Coinbase 的圆中方、Snowflake 的雪花、IBM 的横条。
//   · 品牌本身是纯字标、画出来只会走形的，就画这家公司**做的东西**——礼来是胶囊、
//     开拓重工是推土楔、火箭实验室是火箭、西部数据是盘片。它不是那家公司的注册标，
//     但它能把这一行和上下行分开，这才是徽章要回答的问题。
//   · 两样都够不着的长尾，走 `generated(for:)`：按代号散列出一枚每支都不一样的
//     几何标（见文件末尾）。兜底的图形也要随条目变，才叫图标。

extension CoinSpec {
  /// 查品牌标。分成几张小表纯粹是为了别让类型检查器在一个大字面量上卡死。
  static func brand(_ key: String) -> CoinSpec? {
    chips[key] ?? software[key] ?? consumer[key] ?? finance[key] ?? industry[key] ?? asia[key]
  }

  // ---------------------------------------------------------------- 半导体与硬件

  private static let chips: [String: CoinSpec] = [
    // 美满电子：标就是一道折成 M 的粗笔画。
    "MRVL": CoinSpec(from: "#7FA8E8", to: "#1E4FA8",
                     mark: stroke(["M4.8 17.8V7.2l7.2 6.2 7.2-6.2v10.6"], 2.4)),
    // 博通：一道拱，两端收在底线上。
    "AVGO": CoinSpec(from: "#F0907A", to: "#B23023",
                     mark: stroke(["M6 17.4V13a6 6 0 0 1 12 0v4.4"], 2.4)),
    // Arm 卖的是芯片核：一颗带引脚的方片。
    "ARM": CoinSpec(from: "#6FC3D6", to: "#1D7A93", mark: .parts([
      Part(d: ["M8.6 8.6h6.8v6.8H8.6z"], stroke: nil),
      Part(d: ["M10.2 5.4v3", "M13.8 5.4v3", "M10.2 15.6v3", "M13.8 15.6v3",
               "M5.4 10.2h3", "M5.4 13.8h3", "M15.6 10.2h3", "M15.6 13.8h3"], stroke: 1.5)])),
    // 阿斯麦：一束光锥打在晶圆上。
    "ASML": CoinSpec(from: "#8FB6F2", to: "#2F63C0", mark: .parts([
      Part(d: ["M8.8 3.6h6.4l-2 6.6h-2.4z"], stroke: nil),
      Part(d: ["M12 13a4.4 4.4 0 1 1 0 8.8 4.4 4.4 0 0 1 0-8.8z"], stroke: 1.8)])),
    // 应用材料：一片带定位缺口的晶圆。
    "AMAT": CoinSpec(from: "#A9C0E8", to: "#3E62A8", mark: .parts([
      Part(d: ["M12 4.6a7.4 7.4 0 1 1 0 14.8 7.4 7.4 0 0 1 0-14.8z"], stroke: 1.9),
      Part(d: ["M9.4 4.9h5.2l-2.6 3.4z"], stroke: nil)])),
    // 科磊做量测：一个十字瞄准。
    "KLAC": CoinSpec(from: "#8FC7C0", to: "#2E7D6B", mark: .parts([
      Part(d: ["M12 6.2a5.8 5.8 0 1 1 0 11.6 5.8 5.8 0 0 1 0-11.6z"], stroke: 1.8),
      Part(d: ["M12 2.8v3.2", "M12 18v3.2", "M2.8 12h3.2", "M18 12h3.2"], stroke: 1.8)])),
    // 泛林做刻蚀：一层层往下刻的同心方。
    "LRCX": CoinSpec(from: "#E8B98C", to: "#A8642C", mark: .parts([
      Part(d: ["M4.6 4.6h14.8v14.8H4.6z", "M8.4 8.4h7.2v7.2H8.4z"], stroke: 1.8)])),
    // 美光做存储：三根带缺口的存储条。
    "MU": CoinSpec(from: "#7FB6E8", to: "#1F5E9E", mark: fill([
      "M4.4 5.6h15.2v3.4h-6.4v-1.2h-2.4v1.2H4.4z",
      "M4.4 10.3h15.2v3.4h-6.4v-1.2h-2.4v1.2H4.4z",
      "M4.4 15h15.2v3.4h-6.4v-1.2h-2.4v1.2H4.4z"])),
    // 德州仪器：红圆里一道模拟波。
    "TXN": CoinSpec(from: "#EF7B7B", to: "#B3202A", mark: .parts([
      Part(d: ["M12 4.8a7.2 7.2 0 1 1 0 14.4 7.2 7.2 0 0 1 0-14.4z"], stroke: 1.9),
      Part(d: ["M7.4 13.6c1.6-4.4 3-4.4 4.6 0s3 4.4 4.6 0"], stroke: 1.8)])),
    // 泰瑞达做测试：一根探针压在焊盘上。
    "TER": CoinSpec(from: "#A9B8C8", to: "#4E637A", mark: .parts([
      Part(d: ["M12 3.6v9.8"], stroke: 2.2),
      Part(d: ["M9.6 13.4h4.8l-2.4 3.4z", "M5.4 18.2h13.2v2.2H5.4z"], stroke: nil)])),
    // 相干做激光：两束光交在一点。
    "COHR": CoinSpec(from: "#C8A8E8", to: "#6A40A8", mark: .parts([
      Part(d: ["M4.4 5.4L19.6 18.6", "M19.6 5.4L4.4 18.6"], stroke: 2.1),
      Part(d: ["M12 9.6a2.4 2.4 0 1 1 0 4.8 2.4 2.4 0 0 1 0-4.8z"], stroke: nil)])),
    // Ciena 做光传输：一根光纤上的两个节点。
    "CIEN": CoinSpec(from: "#8FD4C0", to: "#2E8A6B", mark: .parts([
      Part(d: ["M4.4 16.4c3.8 0 3.8-8.8 7.6-8.8s3.8 8.8 7.6 8.8"], stroke: 2.1),
      Part(d: ["M5.8 14.6a2 2 0 1 1 0 4 2 2 0 0 1 0-4z",
               "M18.2 14.6a2 2 0 1 1 0 4 2 2 0 0 1 0-4z"], stroke: nil)])),
    // Credo 做互连：两颗菱形扣在一起。
    "CRDO": CoinSpec(from: "#9FB8E8", to: "#3F60B8", mark: stroke([
      "M8.6 12l4-4 4 4-4 4z", "M3.4 12l4-4", "M20.6 12l-4 4"], 2)),
    // Astera Labs 做链路：三节连成一条的链。
    "ALAB": CoinSpec(from: "#E8A8C8", to: "#B0407A", mark: .parts([
      Part(d: ["M4.4 12h15.2"], stroke: 2),
      Part(d: ["M6.2 9.4a2.6 2.6 0 1 1 0 5.2 2.6 2.6 0 0 1 0-5.2z",
               "M12 9.4a2.6 2.6 0 1 1 0 5.2 2.6 2.6 0 0 1 0-5.2z",
               "M17.8 9.4a2.6 2.6 0 1 1 0 5.2 2.6 2.6 0 0 1 0-5.2z"], stroke: nil)])),
    // 应用光电做光模块：一只带尾纤的方盒。
    "AAOI": CoinSpec(from: "#8FC0E8", to: "#2F72A8", mark: .parts([
      Part(d: ["M4.6 8.8h10.2v6.4H4.6z"], stroke: nil),
      Part(d: ["M14.8 12h4.8"], stroke: 2)])),
    // AXT 长晶：一颗六方晶。
    "AXTI": CoinSpec(from: "#C0C8D4", to: "#65707F", mark: stroke([
      "M12 3.6l7.2 4.2v8.4L12 20.4l-7.2-4.2V7.8z"], 2)),
    // 闪迪：一张 SD 卡，右上角切掉一块。
    "SNDK": CoinSpec(from: "#E8C07A", to: "#B08420", mark: fill([
      "M7 4.4h7.2l3.8 3.8v11.4H7z"])),
    // 西部数据：一张盘片加磁头。
    "WDC": CoinSpec(from: "#8FA8C8", to: "#34506E", mark: .parts([
      Part(d: ["M12 4.8a7.2 7.2 0 1 1 0 14.4 7.2 7.2 0 0 1 0-14.4z"], stroke: 1.8),
      Part(d: ["M12 10.6a1.4 1.4 0 1 1 0 2.8 1.4 1.4 0 0 1 0-2.8z",
               "M14.4 6.2l4.6 3.2-1.2 1.8-4.6-3.2z"], stroke: nil)])),
    // 超微做服务器：一只三层机架。
    "SMCI": CoinSpec(from: "#7FC4A8", to: "#2E7D5B", mark: .parts([
      Part(d: ["M4.6 5.4h14.8v4H4.6z", "M4.6 10h14.8v4H4.6z", "M4.6 14.6h14.8v4H4.6z"], stroke: 1.6),
      Part(d: ["M6.6 6.8a.8 .8 0 1 1 0 1.6 .8 .8 0 0 1 0-1.6z",
               "M6.6 11.4a.8 .8 0 1 1 0 1.6 .8 .8 0 0 1 0-1.6z",
               "M6.6 16a.8 .8 0 1 1 0 1.6 .8 .8 0 0 1 0-1.6z"], stroke: nil)])),
    // 戴尔：一圈环，右上开口。
    "DELL": CoinSpec(from: "#7FB6E8", to: "#1F5E9E", mark: .parts([
      Part(d: ["M16.4 6.6a7 7 0 1 0 2.2 3.4"], stroke: 2.2),
      Part(d: ["M12 9.6a2.4 2.4 0 1 1 0 4.8 2.4 2.4 0 0 1 0-4.8z"], stroke: nil)])),
    // 慧与：一对绿色方括号。
    "HPE": CoinSpec(from: "#7FD4A8", to: "#1E8A5B", mark: fill([
      "M3.8 8.4h7.4v2.4H6.2v2.4h5v2.4H3.8z", "M12.8 8.4h7.4v2.4h-5v2.4h5v2.4h-7.4z"])),
    // 英特尔：一圈带缺口的环加一颗点。
    "INTC": CoinSpec(from: "#7FB6E8", to: "#1050A8", mark: .parts([
      Part(d: ["M15.8 5.8a7.2 7.2 0 1 0 3.2 4.6"], stroke: 2.1),
      Part(d: ["M17.6 4a1.8 1.8 0 1 1 0 3.6 1.8 1.8 0 0 1 0-3.6z"], stroke: nil)])),
    // 诺基亚做连接：一对反向箭头。
    "NOK": CoinSpec(from: "#8FA8E8", to: "#2A4FA8", mark: fill([
      "M3.6 9.2h12v-2.4l5 4-5 4V12h-12z", "M20.4 14.8h-12v2.4l-5-4 5-4V12h12z"])),
    // 康宁做玻璃：一块带高光的菱面。
    "GLW": CoinSpec(from: "#A8C8D4", to: "#3E6070", mark: .parts([
      Part(d: ["M12 3.6l7.4 8.4-7.4 8.4-7.4-8.4z"], stroke: 1.9),
      Part(d: ["M12 7.2l3.8 4.8-3.8 4.8z"], stroke: nil)])),
    // Lumentum：一束光过棱镜分开。
    "LITE": CoinSpec(from: "#C8A8E8", to: "#6A40A8", mark: .parts([
      Part(d: ["M12 4.4l6.4 11.2H5.6z"], stroke: 1.9),
      Part(d: ["M2.6 10h4.2", "M17.2 17.4h4.2", "M17.2 19.8h4.2"], stroke: 1.7)])),
    // Nebius 做云：一只立方。
    "NBIS": CoinSpec(from: "#8FB6E8", to: "#2F5FA8", mark: stroke([
      "M12 3.8l7.4 4.1v8.2L12 20.2l-7.4-4.1V7.9z", "M12 12l7.4-4.1", "M12 12v8.2", "M12 12L4.6 7.9"], 1.7)),
    // IREN 拿风电挖矿：一只三叶风车。
    "IREN": CoinSpec(from: "#8FD4C0", to: "#2E8A78", mark: .parts([
      Part(d: ["M12 11.2V3.6", "M12 12.8l6.6 3.8", "M12 12.8l-6.6 3.8"], stroke: 2.2),
      Part(d: ["M12 10.2a1.8 1.8 0 1 1 0 3.6 1.8 1.8 0 0 1 0-3.6z"], stroke: nil)])),
    // 台积电做代工：晶圆上的一组线路。
    "TSM": CoinSpec(from: "#7FA8E8", to: "#1F4FA8", mark: .parts([
      Part(d: ["M12 4.8a7.2 7.2 0 1 1 0 14.4 7.2 7.2 0 0 1 0-14.4z"], stroke: 1.8),
      Part(d: ["M8.6 8.6h6.8v6.8H8.6z"], stroke: 1.6)])),
    // 高通做基带：一圈环外面两道信号弧。
    "QCOM": CoinSpec(from: "#7FA8E8", to: "#2F5FD0", mark: .parts([
      Part(d: ["M12 7.6a4.4 4.4 0 1 1 0 8.8 4.4 4.4 0 0 1 0-8.8z"], stroke: 1.9),
      Part(d: ["M16.2 5.4a8.4 8.4 0 0 1 0 13.2", "M7.8 5.4a8.4 8.4 0 0 0 0 13.2"], stroke: 1.7)])),
  ]

  // ---------------------------------------------------------------- 软件与互联网

  private static let software: [String: CoinSpec] = [
    // Salesforce：一朵云。
    "CRM": CoinSpec(from: "#7FC4F0", to: "#1E7BC0", mark: fill([
      "M7.4 18.4a4.4 4.4 0 0 1-.5-8.8 5.6 5.6 0 0 1 10.6-1 3.9 3.9 0 0 1-.7 9.8z"])),
    // ServiceNow 做流程：三个连起来的节点。
    "NOW": CoinSpec(from: "#7FD4A8", to: "#1E8A5B", mark: .parts([
      Part(d: ["M7.4 8.6h9.2", "M7.4 8.6v6.8", "M7.4 15.4h9.2"], stroke: 2),
      Part(d: ["M7.4 5.8a2.8 2.8 0 1 1 0 5.6 2.8 2.8 0 0 1 0-5.6z",
               "M16.6 12.6a2.8 2.8 0 1 1 0 5.6 2.8 2.8 0 0 1 0-5.6z"], stroke: nil)])),
    // Snowflake：一片雪花。
    "SNOW": CoinSpec(from: "#8FD4F0", to: "#2F8FC0", mark: .parts([
      Part(d: ["M12 3.2v17.6", "M4.4 7.6l15.2 8.8", "M19.6 7.6L4.4 16.4"], stroke: 2),
      Part(d: ["M9.4 5.4L12 8l2.6-2.6", "M9.4 18.6L12 16l2.6 2.6"], stroke: 1.8)])),
    // MongoDB：一片叶子。
    "MDB": CoinSpec(from: "#9FD48C", to: "#3E8B2C", mark: .parts([
      Part(d: ["M12 3.2c3.4 3.6 5 6.6 5 9.4 0 3.4-2.2 5.6-5 6.4-2.8-.8-5-3-5-6.4 0-2.8 1.6-5.8 5-9.4z"], stroke: nil),
      Part(d: ["M12 19v2.2"], stroke: 1.8)])),
    // Datadog：一只探头的狗。
    "DDOG": CoinSpec(from: "#C0A8E8", to: "#6A3FB0", mark: .parts([
      Part(d: ["M5.6 9.4l3-3.4v3.2h6.2l3.6-2.4v9.6h-4.6v3.6H8.2v-3.6H5.6z"], stroke: nil),
      Part(d: ["M15.8 10.6a1.2 1.2 0 1 1 0 2.4 1.2 1.2 0 0 1 0-2.4z"], stroke: nil)])),
    // Cloudflare：一朵云压在一道气流上。
    "NET": CoinSpec(from: "#F0B47A", to: "#C87A18", mark: .parts([
      Part(d: ["M8.6 15.4a3.6 3.6 0 0 1 .3-7.2 4.8 4.8 0 0 1 9 .8 3.2 3.2 0 0 1-.5 6.4z"], stroke: nil),
      Part(d: ["M3.6 18.2h12.8"], stroke: 2)])),
    // Zscaler 做安全网关：一面盾。
    "ZS": CoinSpec(from: "#8FC4E8", to: "#2F6FA8", mark: .parts([
      Part(d: ["M12 3.4l7 2.6v6c0 4-3 7-7 8.6-4-1.6-7-4.6-7-8.6V6z"], stroke: 1.9),
      Part(d: ["M8.8 12.2l2.4 2.4 4-4.6"], stroke: 2)])),
    // Palo Alto Networks：一枚六边形的锁。
    "PANW": CoinSpec(from: "#F0A07A", to: "#C05020", mark: .parts([
      Part(d: ["M12 3.4l7 4v9.2l-7 4-7-4V7.4z"], stroke: 1.9),
      Part(d: ["M9.6 11h4.8v4.4H9.6z"], stroke: nil),
      Part(d: ["M10.4 11V9.4a1.6 1.6 0 0 1 3.2 0V11"], stroke: 1.5)])),
    // CrowdStrike：一对张开的翼。
    "CRWD": CoinSpec(from: "#EF8080", to: "#B02028", mark: fill([
      "M11.2 4.4v15.2L3.4 12z", "M12.8 4.4v15.2L20.6 12z"])),
    // GitLab：由三角拼出的那只狐狸。
    "GTLB": CoinSpec(from: "#F0A47A", to: "#C25A18", mark: fill([
      "M12 20.6L4 11.2l1.8-6.4 3 6.4h6.4l3-6.4L20 11.2z"])),
    // Atlassian：一对折起来的角。
    "TEAM": CoinSpec(from: "#7FA8F0", to: "#1F5FD0", mark: fill([
      "M9.8 3.6L18.8 20H12L9.8 3.6z", "M8.4 9.8L13 20H3.8L8.4 9.8z"])),
    // Palantir：三层叠起来的棱。
    "PLTR": CoinSpec(from: "#A8B4C0", to: "#3E4A56", mark: fill([
      "M12 3.6l7.4 4.6H4.6z", "M12 9.6l7.4 4.6H4.6z", "M12 15.6l7.4 4.6H4.6z"])),
    // AppLovin：一枚播放三角扣在环里。
    "APP": CoinSpec(from: "#8FC4A8", to: "#2E7D5B", mark: .parts([
      Part(d: ["M12 4.6a7.4 7.4 0 1 1 0 14.8 7.4 7.4 0 0 1 0-14.8z"], stroke: 1.9),
      Part(d: ["M10.2 8.6l6 3.4-6 3.4z"], stroke: nil)])),
    // eBay：四颗挨着的球。
    "EBAY": CoinSpec(from: "#F0A07A", to: "#C04020", mark: fill([
      "M5.6 9.8a2.6 2.6 0 1 1 0 5.2 2.6 2.6 0 0 1 0-5.2z",
      "M9.9 9.8a2.6 2.6 0 1 1 0 5.2 2.6 2.6 0 0 1 0-5.2z",
      "M14.2 9.8a2.6 2.6 0 1 1 0 5.2 2.6 2.6 0 0 1 0-5.2z",
      "M18.5 9.8a2.6 2.6 0 1 1 0 5.2 2.6 2.6 0 0 1 0-5.2z"])),
    // Shopify：一只购物袋。
    "SHOP": CoinSpec(from: "#9FD48C", to: "#4A8B2C", mark: .parts([
      Part(d: ["M5.4 8.2h13.2l-1.2 12H6.6z"], stroke: nil),
      Part(d: ["M9 9.4V7a3 3 0 0 1 6 0v2.4"], stroke: 1.8)])),
    // Uber 是路：一条路穿过一个方。
    "UBER": CoinSpec(from: "#9AA4B0", to: "#20262E", mark: .parts([
      Part(d: ["M4.6 4.6h14.8v14.8H4.6z"], stroke: 2),
      Part(d: ["M8.6 15.4l6.8-6.8"], stroke: 2.4)])),
    // DraftKings：一顶王冠。
    "DKNG": CoinSpec(from: "#7FD4A8", to: "#1E8A4B", mark: fill([
      "M3.8 8.2l3.8 3.4L12 5.4l4.4 6.2 3.8-3.4-1.8 10H5.6z"])),
    // Take-Two：两个套在一起的圆。
    "TTWO": CoinSpec(from: "#C0A8E8", to: "#6A3FB0", mark: stroke([
      "M9.2 7a5 5 0 1 1 0 10 5 5 0 0 1 0-10z",
      "M14.8 7a5 5 0 1 1 0 10 5 5 0 0 1 0-10z"], 1.9)),
    // Reddit：Snoo 的头，一根天线两只眼。
    "RDDT": CoinSpec(from: "#F0A07A", to: "#E04020", mark: .parts([
      Part(d: ["M12 8.4c4.4 0 8 2.6 8 5.8s-3.6 5.8-8 5.8-8-2.6-8-5.8 3.6-5.8 8-5.8z"], stroke: nil),
      Part(d: ["M12 8.4V5.2", "M15.4 3.4a1.8 1.8 0 1 1 0 3.6 1.8 1.8 0 0 1 0-3.6z"], stroke: 1.7)])),
    // Zoom：一台摄像机。
    "ZM": CoinSpec(from: "#8FB6F0", to: "#1F5FD0", mark: fill([
      "M4.4 8h9.2c.9 0 1.6.7 1.6 1.6v4.8c0 .9-.7 1.6-1.6 1.6H4.4c-.9 0-1.6-.7-1.6-1.6V9.6c0-.9.7-1.6 1.6-1.6z",
      "M16.4 11.2l4.8-3v7.6l-4.8-3z"])),
    // 特朗普媒体：星条。
    "DJT": CoinSpec(from: "#EF8080", to: "#B02028", mark: .parts([
      Part(d: ["M12 3.6l1.9 3.9 4.3.6-3.1 3 .7 4.3-3.8-2-3.8 2 .7-4.3-3.1-3 4.3-.6z"], stroke: nil),
      Part(d: ["M5 19.4h14"], stroke: 2)])),
    // GoPro：一台方镜头相机。
    "GPRO": CoinSpec(from: "#A8B4C0", to: "#3E4A56", mark: .parts([
      Part(d: ["M4.4 6.6h15.2v10.8H4.4z"], stroke: 2),
      Part(d: ["M12 8.8a3.2 3.2 0 1 1 0 6.4 3.2 3.2 0 0 1 0-6.4z"], stroke: 1.8)])),
    // Hims 卖处方药：一粒胶囊配一片叶。
    "HIMS": CoinSpec(from: "#8FD4C0", to: "#2E8A6B", mark: .parts([
      Part(d: ["M8.2 12.4l4.2-4.2a3 3 0 0 1 4.2 4.2l-4.2 4.2a3 3 0 0 1-4.2-4.2z"], stroke: 1.8),
      Part(d: ["M4 20c0-3.2 2-5 5-5 0 3.2-2 5-5 5z"], stroke: nil)])),
    // Oracle：一圈红色的椭圆。
    "ORCL": CoinSpec(from: "#EF8080", to: "#C0302A", mark: stroke([
      "M8.6 8a4 4 0 1 0 0 8h6.8a4 4 0 1 0 0-8z"], 2.3)),
    // IBM：八条横杠。
    "IBM": CoinSpec(from: "#7FB6E8", to: "#1F5EA8", mark: fill([
      "M4.4 5.6h15.2v1.5H4.4z", "M4.4 8.1h15.2v1.5H4.4z",
      "M4.4 10.6h15.2v1.5H4.4z", "M4.4 13.1h15.2v1.5H4.4z",
      "M4.4 15.6h15.2v1.5H4.4z", "M4.4 18.1h15.2v1.5H4.4z"])),
    // Sony 是一条围起来的带。
    "SONY": CoinSpec(from: "#A8B4C0", to: "#20262E", mark: .parts([
      Part(d: ["M3.4 7.6h17.2v8.8H3.4z"], stroke: 2.1),
      Part(d: ["M7 12h10"], stroke: 2.1)])),
  ]

  // ---------------------------------------------------------------- 消费与医药

  private static let consumer: [String: CoinSpec] = [
    // 迪士尼：三个圆。
    "DIS": CoinSpec(from: "#8FA8E8", to: "#2A3FA8", mark: fill([
      "M12 9a5 5 0 1 1 0 10 5 5 0 0 1 0-10z",
      "M6.4 3.8a3 3 0 1 1 0 6 3 3 0 0 1 0-6z",
      "M17.6 3.8a3 3 0 1 1 0 6 3 3 0 0 1 0-6z"])),
    // 可口可乐：那条飘带。
    "KO": CoinSpec(from: "#EF7B7B", to: "#B3202A", mark: .parts([
      Part(d: ["M3.4 14.6c4-5.2 8-7.8 12-7.8 2 0 3.6.5 5.2 1.4-3.6 1-6.6 2.6-9 4.8"], stroke: nil),
      Part(d: ["M20.6 9.4c-4 5.2-8 7.8-12 7.8-2 0-3.6-.5-5.2-1.4 3.6-1 6.6-2.6 9-4.8"], stroke: nil)])),
    // 好市多做仓储：一摞托盘货。
    "COST": CoinSpec(from: "#EF8080", to: "#B0202A", mark: fill([
      "M4.6 5.2h6.2v4.4H4.6z", "M13.2 5.2h6.2v4.4h-6.2z",
      "M4.6 11.4h6.2v4.4H4.6z", "M13.2 11.4h6.2v4.4h-6.2z",
      "M3.4 17.6h17.2v2.4H3.4z"])),
    // 沃尔玛：六瓣火花。
    "WMT": CoinSpec(from: "#7FC4F0", to: "#1E6FC0", mark: .parts([
      Part(d: ["M12 2.8v5.6", "M12 15.6v5.6", "M4.9 6.9l4.8 2.8", "M14.3 14.3l4.8 2.8",
               "M19.1 6.9l-4.8 2.8", "M9.7 14.3l-4.8 2.8"], stroke: 2.3)])),
    // 家得宝：一只方桶。
    "HD": CoinSpec(from: "#F0A07A", to: "#D06018", mark: .parts([
      Part(d: ["M4.8 4.8h14.4v14.4H4.8z"], stroke: 2.2),
      Part(d: ["M8.4 9.6h7.2v1.9H8.4z", "M10.8 8.4h2.4v6.4h-2.4z"], stroke: nil)])),
    // 阿里：那张笑脸丝带。
    "BABA": CoinSpec(from: "#F0A07A", to: "#D06018", mark: .parts([
      Part(d: ["M6.4 8.8c1.8-2.6 4-3.8 6.6-3.8 3 0 5 1.6 5 3.8 0 3.4-4.2 4-4.2 6.4"], stroke: 2.1),
      Part(d: ["M6.6 13.4a2.2 2.2 0 1 1 0 4.4 2.2 2.2 0 0 1 0-4.4z",
               "M13.8 16.4a2.2 2.2 0 1 1 0 4.4 2.2 2.2 0 0 1 0-4.4z"], stroke: nil)])),
    // 拼多多：两圈套着的环。
    "PDD": CoinSpec(from: "#EF8080", to: "#C0302A", mark: stroke([
      "M12 4.6a7.4 7.4 0 1 1 0 14.8 7.4 7.4 0 0 1 0-14.8z",
      "M12 8.8a3.2 3.2 0 1 1 0 6.4 3.2 3.2 0 0 1 0-6.4z"], 2)),
    // GameStop：一只手柄。
    "GME": CoinSpec(from: "#EF8080", to: "#B02028", mark: .parts([
      Part(d: ["M7.4 8h9.2a4.6 4.6 0 0 1 0 9.2H7.4a4.6 4.6 0 0 1 0-9.2z"], stroke: nil),
      Part(d: ["M8.2 12.6h2.6", "M9.5 11.3v2.6"], stroke: 1.5)])),
    // 温迪的是个汉堡。
    "WEN": CoinSpec(from: "#EF8080", to: "#B02028", mark: fill([
      "M4.6 8.2c0-2.4 3.3-4 7.4-4s7.4 1.6 7.4 4z",
      "M4.4 10h15.2v2.6H4.4z",
      "M4.6 14.4h14.8c0 2.6-3.3 4.4-7.4 4.4s-7.4-1.8-7.4-4.4z"])),
    // 礼来：一粒胶囊。
    "LLY": CoinSpec(from: "#EF8080", to: "#C0302A", mark: .parts([
      Part(d: ["M7.6 13.2l5.6-5.6a4 4 0 0 1 5.6 5.6l-5.6 5.6a4 4 0 0 1-5.6-5.6z"], stroke: 1.9),
      Part(d: ["M10.4 10.4l5.6 5.6"], stroke: 1.9)])),
    // 默沙东：一片药加十字。
    "MRK": CoinSpec(from: "#7FC4B8", to: "#0E7C6E", mark: .parts([
      Part(d: ["M12 4.6a7.4 7.4 0 1 1 0 14.8 7.4 7.4 0 0 1 0-14.8z"], stroke: 1.9),
      Part(d: ["M10.6 8.2h2.8v2.4h2.4v2.8h-2.4v2.4h-2.8v-2.4H8.2v-2.8h2.4z"], stroke: nil)])),
    // 莫德纳做 mRNA：一段双螺旋。
    "MRNA": CoinSpec(from: "#F08080", to: "#B31B1B", mark: .parts([
      Part(d: ["M8 3.6c0 5.6 8 6.8 8 12.4 0 2-1 3.4-2.6 4.4",
               "M16 3.6c0 5.6-8 6.8-8 12.4 0 2 1 3.4 2.6 4.4"], stroke: 2),
      Part(d: ["M8.6 8h6.8", "M8.6 13.2h6.8"], stroke: 1.6)])),
    // 诺和诺德的标是那头牛：一对角。
    "NVO": CoinSpec(from: "#7FA8E8", to: "#1F4FA8", mark: stroke([
      "M3.6 7.6c0 5.4 3.8 8.8 8.4 8.8s8.4-3.4 8.4-8.8",
      "M3.6 7.6c1.8-1.4 3.4-2 4.8-1.8", "M20.4 7.6c-1.8-1.4-3.4-2-4.8-1.8"], 2.1)),
  ]

  // ---------------------------------------------------------------- 金融与加密

  private static let finance: [String: CoinSpec] = [
    // Coinbase：圆里挖一个方。
    "COIN": CoinSpec(from: "#7FA8F0", to: "#1652F0", mark: .parts([
      Part(d: ["M12 4.4a7.6 7.6 0 1 1 0 15.2 7.6 7.6 0 0 1 0-15.2z"], stroke: 2.1),
      Part(d: ["M9.6 9.6h4.8v4.8H9.6z"], stroke: nil)])),
    // 罗宾汉：一根羽毛。
    "HOOD": CoinSpec(from: "#9FD48C", to: "#3E8B2C", mark: .parts([
      Part(d: ["M18.4 4.4c1 6.6-2.4 11-8.4 11.6l-2.8.3c.4-6.6 4.2-10.6 11.2-11.9z"], stroke: nil),
      Part(d: ["M5 20.4l5.6-6"], stroke: 2)])),
    // SoFi：三道递进的弧。
    "SOFI": CoinSpec(from: "#F0A07A", to: "#C0502A", mark: stroke([
      "M5.4 17.6a4 4 0 0 1 4-4", "M5.4 17.6a8 8 0 0 1 8-8", "M5.4 17.6a12 12 0 0 1 12-12"], 2)),
    // 摩根大通：一枚八角形。
    "JPM": CoinSpec(from: "#8FA8C8", to: "#2E4A6E", mark: .parts([
      Part(d: ["M8.6 3.8h6.8l5 5v6.4l-5 5H8.6l-5-5V8.8z"], stroke: 2),
      Part(d: ["M9.6 9.6h4.8v4.8H9.6z"], stroke: nil)])),
    // 高盛：两根柱子顶一道横梁。
    "GS": CoinSpec(from: "#A8B8C8", to: "#45607A", mark: fill([
      "M3.8 5.4h16.4v2.6H3.8z", "M6.6 9h3.2v9.4H6.6z", "M14.2 9h3.2v9.4h-3.2z",
      "M3.8 19.8h16.4v1.4H3.8z"])),
    // 黑石：三块错开的方。
    "BX": CoinSpec(from: "#9AA4B0", to: "#20262E", mark: fill([
      "M4.4 4.4h7.2v7.2H4.4z", "M12.4 8.4h7.2v7.2h-7.2z", "M4.4 12.4h7.2v7.2H4.4z"])),
    // 伯克希尔：一面带横带的盾。
    "BRKB": CoinSpec(from: "#A8B4C0", to: "#3E4A56", mark: .parts([
      Part(d: ["M12 3.4l7 2.6v6c0 4-3 7-7 8.6-4-1.6-7-4.6-7-8.6V6z"], stroke: 1.9),
      Part(d: ["M5.6 11h12.8v2.6H5.6z"], stroke: nil)])),
    // Visa：一枚翼形的 V。
    "V": CoinSpec(from: "#8FA8E8", to: "#1A3F9E", mark: fill([
      "M3.6 6.6h4.2L12 16.4l4.2-9.8h4.2L13.8 20h-3.6z"])),
    // PayPal：两个叠起来的 P。
    "PYPL": CoinSpec(from: "#7FB6E8", to: "#1A4FA8", mark: fill([
      "M5.4 4.4h5.8a4 4 0 0 1 0 8H8.2l-1 7.2H4z",
      "M11 8.4h4.4a4 4 0 0 1 0 8h-2.8l-1 5.2h-2.4z"])),
    "PAYP": CoinSpec(from: "#7FB6E8", to: "#1A4FA8", mark: .parts([
      Part(d: ["M3.6 7.4h16.8v11.2H3.6z"], stroke: 2),
      Part(d: ["M14.8 11.4h5.6v3.2h-5.6z"], stroke: nil)])),
    // Strategy（原 MicroStrategy）：一排高低竖条。
    "MSTR": CoinSpec(from: "#8FB6E8", to: "#2F5FA8", mark: fill([
      "M4.4 8.6h2.6v10.8H4.4z", "M8.4 5.4h2.6v14H8.4z",
      "M13 5.4h2.6v14H13z", "M17 8.6h2.6v10.8H17z"])),
    // Marathon 挖矿：一把镐。
    "MARA": CoinSpec(from: "#7FC4A8", to: "#2E7D5B", mark: .parts([
      Part(d: ["M4.4 7.6c5-3.4 10.2-3.4 15.2 0-5 1.6-10.2 1.6-15.2 0z"], stroke: nil),
      Part(d: ["M12 7v13.4"], stroke: 2.2)])),
    // Circle：一圈环。
    "CRCL": CoinSpec(from: "#8FC4E8", to: "#2F7FC8", mark: .parts([
      Part(d: ["M12 4.6a7.4 7.4 0 1 1 0 14.8 7.4 7.4 0 0 1 0-14.8z"], stroke: 2.2),
      Part(d: ["M12 10.2a1.8 1.8 0 1 1 0 3.6 1.8 1.8 0 0 1 0-3.6z"], stroke: nil)])),
    // CoreWeave：编在一起的四格。
    "CRWV": CoinSpec(from: "#C0A8E8", to: "#6A3FB0", mark: .parts([
      Part(d: ["M4.4 9.4h15.2", "M4.4 14.6h15.2", "M9.4 4.4v15.2", "M14.6 4.4v15.2"], stroke: 2)])),
    // Bitmine：一台矿机。
    "BMNR": CoinSpec(from: "#E8C07A", to: "#A8802C", mark: .parts([
      Part(d: ["M4.4 7h15.2v10H4.4z"], stroke: 1.9),
      Part(d: ["M7.4 9.6h2.2v4.8H7.4z", "M11 9.6h2.2v4.8H11z", "M14.6 9.6h2.2v4.8h-2.2z"], stroke: nil),
      Part(d: ["M7 19.4h10"], stroke: 1.8)])),
  ]

  // ---------------------------------------------------------------- 工业与能源

  private static let industry: [String: CoinSpec] = [
    // 卡特彼勒：一只推土楔。
    "CAT": CoinSpec(from: "#F0C860", to: "#B88A10", mark: fill([
      "M3.6 15.6h3.2L11 7.4h9.4v3.2h-7.4l-4.2 8.2H3.6z"])),
    // GE Vernova 做发电：一组涡轮叶。
    "GEV": CoinSpec(from: "#7FC4E8", to: "#1F7FB8", mark: .parts([
      Part(d: ["M12 10.6c0-4 1.4-6.6 4-7.6-.6 3.2-1.8 5.6-4 7.6z",
               "M13 12.6c3.6-1.8 6.4-1.8 8.4 0-3 1.6-5.8 1.6-8.4 0z",
               "M11 13.4c-.8 3.8-2.4 6.2-5 7 .2-3.2 1.8-5.6 5-7z"], stroke: nil),
      Part(d: ["M12 10.4a1.8 1.8 0 1 1 0 3.6 1.8 1.8 0 0 1 0-3.6z"], stroke: nil)])),
    // Vistra 卖电：一道闪电。
    "VST": CoinSpec(from: "#F0C860", to: "#C09010", mark: fill([
      "M13.6 2.8l-8 11h4.4l-1.6 7.4 8-11.4h-4.6z"])),
    // Vertiv 做机房散热：一只风扇。
    "VRT": CoinSpec(from: "#9FD48C", to: "#4A8B2C", mark: .parts([
      Part(d: ["M12 11.4c-1-3.4-.4-5.8 2-7.2.6 3.2.2 5.6-2 7.2z",
               "M12.6 12.4c3.4-1 5.8-.4 7.2 2-3.2.6-5.6.2-7.2-2z",
               "M11.4 12.6c-1 3.4-3 5-6 5 1.4-2.8 3.4-4.6 6-5z"], stroke: nil),
      Part(d: ["M12 10.6a1.6 1.6 0 1 1 0 3.2 1.6 1.6 0 0 1 0-3.2z"], stroke: nil)])),
    // Bloom Energy 做燃料电池：一朵四瓣。
    "BE": CoinSpec(from: "#9FD48C", to: "#3E8B4C", mark: fill([
      "M12 3.4c2.6 2 3.8 4 3.6 6-2.2.2-3.4-1.8-3.6-6z",
      "M20.6 12c-2 2.6-4 3.8-6 3.6-.2-2.2 1.8-3.4 6-3.6z",
      "M12 20.6c-2.6-2-3.8-4-3.6-6 2.2-.2 3.4 1.8 3.6 6z",
      "M3.4 12c2-2.6 4-3.8 6-3.6.2 2.2-1.8 3.4-6 3.6z"])),
    // Fluence 做储能：一块电池。
    "FLNC": CoinSpec(from: "#8FC4E8", to: "#2F6FA8", mark: .parts([
      Part(d: ["M3.6 7.4h14.2v9.2H3.6z"], stroke: 2),
      Part(d: ["M19 10.4h1.8v3.2H19z", "M11.8 8.8l-3 4.4h2.4l-1 3.6 3.6-5h-2.4z"], stroke: nil)])),
    // Ondas 做无人机：一台四旋翼。
    "ONDS": CoinSpec(from: "#A8B4C0", to: "#3E4A56", mark: .parts([
      Part(d: ["M9.8 9.8h4.4v4.4H9.8z"], stroke: nil),
      Part(d: ["M9.8 9.8L6 6", "M14.2 9.8L18 6", "M9.8 14.2L6 18", "M14.2 14.2L18 18"], stroke: 1.8),
      Part(d: ["M3.4 5.2h5.2", "M15.4 5.2h5.2", "M3.4 18.8h5.2", "M15.4 18.8h5.2"], stroke: 1.8)])),
    // USA Rare Earth 做磁材：一块马蹄磁铁。
    "USAR": CoinSpec(from: "#EF8080", to: "#B02028", mark: .parts([
      Part(d: ["M6.4 19.4V12a5.6 5.6 0 0 1 11.2 0v7.4"], stroke: 3),
      Part(d: ["M4.9 16.4h3v3h-3z", "M16.1 16.4h3v3h-3z"], stroke: nil)])),
    // 火箭实验室：一枚火箭。
    "RKLB": CoinSpec(from: "#A8B4C0", to: "#2E3A46", mark: .parts([
      Part(d: ["M12 2.6c2.4 2.6 3.6 5.6 3.6 9v4.2H8.4v-4.2c0-3.4 1.2-6.4 3.6-9z"], stroke: nil),
      Part(d: ["M8.4 12.4L5.4 18h3z", "M15.6 12.4L18.6 18h-3z", "M10.4 17.4h3.2l-1.6 4z"], stroke: nil)])),
    // AST SpaceMobile 做天基基站：一颗带帆板的卫星。
    "ASTS": CoinSpec(from: "#8FB6E8", to: "#2F5FA8", mark: .parts([
      Part(d: ["M10 10h4v4h-4z"], stroke: nil),
      Part(d: ["M2.8 9h6.2v6H2.8z", "M15 9h6.2v6H15z"], stroke: 1.7),
      Part(d: ["M12 10V5.6", "M12 14v4.4"], stroke: 1.7)])),
    // IonQ 做离子阱：一颗原子。
    "IONQ": CoinSpec(from: "#C0A8E8", to: "#6A3FB0", mark: .parts([
      Part(d: ["M12 10.4a1.8 1.8 0 1 1 0 3.6 1.8 1.8 0 0 1 0-3.6z"], stroke: nil),
      Part(d: ["M12 4.4c4.4 0 8 3.4 8 7.6s-3.6 7.6-8 7.6-8-3.4-8-7.6 3.6-7.6 8-7.6z"], stroke: 1.6),
      Part(d: ["M5.6 8.2c2.2-3.8 6.8-5.2 10.4-3.2s4.6 6.6 2.4 10.4-6.8 5.2-10.4 3.2-4.6-6.6-2.4-10.4z"], stroke: 1.6)])),
    // Tempus 做基因组：一段读出的序列。
    "TEM": CoinSpec(from: "#8FC4C0", to: "#2E7D6B", mark: .parts([
      Part(d: ["M4.4 18.6c0-4 2.6-6 7.6-6s7.6-2 7.6-6"], stroke: 2.1),
      Part(d: ["M6.6 15.4h4", "M13.4 8.6h4"], stroke: 1.8)])),
    // Flex 做代工：一道折起来的产线。
    "FLEX": CoinSpec(from: "#8FA8C8", to: "#34506E", mark: stroke([
      "M4.4 6.6h9.2v5H4.4", "M10.4 12.4h9.2v5h-9.2"], 2)),
  ]

  // ---------------------------------------------------------------- 港股 / 韩股 / A 股

  private static let asia: [String: CoinSpec] = [
    // 腾讯：那只企鹅。
    "TENCENT": CoinSpec(from: "#7FC4E8", to: "#2F6FA8", mark: .parts([
      Part(d: ["M12 3.2c2.9 0 4.6 2.3 4.6 5.4 0 1.5.9 2.8 2.2 4.6 1 1.4 1 2.6.2 3.2-.9.7-2.1.2-3-.8-.5 2.2-2.1 3.6-4 3.6s-3.5-1.4-4-3.6c-.9 1-2.1 1.5-3 .8-.8-.6-.8-1.8.2-3.2 1.3-1.8 2.2-3.1 2.2-4.6 0-3.1 1.7-5.4 4.6-5.4z"], stroke: nil),
      Part(d: ["M10.3 7.4a1.1 1.1 0 1 1 0 2.2 1.1 1.1 0 0 1 0-2.2z",
               "M13.7 7.4a1.1 1.1 0 1 1 0 2.2 1.1 1.1 0 0 1 0-2.2z"], stroke: nil)])),
    // 美团：那只袋鼠的头。
    "MEITUAN": CoinSpec(from: "#F0D060", to: "#D0A000", mark: .parts([
      Part(d: ["M8.4 8.6c0-2.8 1.6-4.6 3.6-4.6s3.6 1.8 3.6 4.6v2.2c0 4.4-1.6 7-3.6 8.8-2-1.8-3.6-4.4-3.6-8.8z"], stroke: nil),
      Part(d: ["M6.2 5.2l2.6 3.6", "M17.8 5.2l-2.6 3.6"], stroke: 2)])),
    // 快手：一道闪电扣在圆里。
    "KUAISHOU": CoinSpec(from: "#F0A0C0", to: "#E0307A", mark: .parts([
      Part(d: ["M12 4.4a7.6 7.6 0 1 1 0 15.2 7.6 7.6 0 0 1 0-15.2z"], stroke: 2),
      Part(d: ["M13 7.6l-4 5.2h2.6l-.8 3.8 4.2-5.6h-2.8z"], stroke: nil)])),
    // 小米：那块圆角方。
    "HK1810": CoinSpec(from: "#F0A07A", to: "#E04020", mark: .parts([
      Part(d: ["M6.4 6.4h11.2c.9 0 1.6.7 1.6 1.6v8c0 .9-.7 1.6-1.6 1.6H6.4c-.9 0-1.6-.7-1.6-1.6v-8c0-.9.7-1.6 1.6-1.6z"], stroke: 2),
      Part(d: ["M8.2 15.4V9.4c1.8 0 2.6.8 2.6 2.6v3.4", "M15.8 9.4v6"], stroke: 1.8)])),
    // 腾讯的港股代号走同一张牌。
    "HK0700": CoinSpec(from: "#7FC4E8", to: "#2F6FA8", mark: .parts([
      Part(d: ["M12 3.2c2.9 0 4.6 2.3 4.6 5.4 0 1.5.9 2.8 2.2 4.6 1 1.4 1 2.6.2 3.2-.9.7-2.1.2-3-.8-.5 2.2-2.1 3.6-4 3.6s-3.5-1.4-4-3.6c-.9 1-2.1 1.5-3 .8-.8-.6-.8-1.8.2-3.2 1.3-1.8 2.2-3.1 2.2-4.6 0-3.1 1.7-5.4 4.6-5.4z"], stroke: nil),
      Part(d: ["M10.3 7.4a1.1 1.1 0 1 1 0 2.2 1.1 1.1 0 0 1 0-2.2z",
               "M13.7 7.4a1.1 1.1 0 1 1 0 2.2 1.1 1.1 0 0 1 0-2.2z"], stroke: nil)])),
    // 吉利：一面盾。
    "HK0625": CoinSpec(from: "#8FA8C8", to: "#2E4A6E", mark: .parts([
      Part(d: ["M12 3.6l7 2.4v6.2c0 3.8-2.9 6.6-7 8.2-4.1-1.6-7-4.4-7-8.2V6z"], stroke: 2),
      Part(d: ["M8.6 10.4h6.8v3.2H8.6z"], stroke: nil)])),
    // 联想：一只方框。
    "HK0992": CoinSpec(from: "#EF8080", to: "#B02028", mark: .parts([
      Part(d: ["M3.6 6.6h16.8v10.8H3.6z"], stroke: 2.2),
      Part(d: ["M7.4 10.4h9.2v3.2H7.4z"], stroke: nil)])),
    // 比亚迪：一枚椭圆。
    "BYD": CoinSpec(from: "#7FA8E8", to: "#1F4FA8", mark: .parts([
      Part(d: ["M5.4 8a6.6 4 0 1 1 0 8 6.6 4 0 0 1 0-8z"], stroke: 2.1),
      Part(d: ["M9 11h6v2H9z"], stroke: nil)])),
    // 泡泡玛特卖盲盒：一只带耳朵的娃娃头。
    "POPMART": CoinSpec(from: "#7FC4C0", to: "#2E8A7B", mark: .parts([
      Part(d: ["M12 6.4a6.4 6.4 0 1 1 0 12.8 6.4 6.4 0 0 1 0-12.8z"], stroke: nil),
      Part(d: ["M7 3.4l2.6 4.4", "M17 3.4l-2.6 4.4"], stroke: 2.1)])),
    // 三星：一枚斜椭圆。
    "SAMSUNG": CoinSpec(from: "#7FA8E8", to: "#1428A0", mark: fill([
      "M4.8 15.8a6.4 4.2 -18 0 1 14.4-6.6 6.4 4.2 -18 0 1-14.4 6.6z"])),
    "SAMSUNGEM": CoinSpec(from: "#8FB6E8", to: "#2040B0", mark: .parts([
      Part(d: ["M4.8 15.8a6.4 4.2 -18 0 1 14.4-6.6 6.4 4.2 -18 0 1-14.4 6.6z"], stroke: 2)])),
    "CSOPSAMSUNG2L": CoinSpec(from: "#9FC0E8", to: "#2A44B8", mark: .parts([
      Part(d: ["M4.8 14.4a6.2 4 -18 0 1 14-6.4 6.2 4 -18 0 1-14 6.4z"], stroke: nil),
      Part(d: ["M5 19.4h14"], stroke: 2)])),
    // SK 海力士做存储：一片带触点的晶粒。
    "SKHYNIX": CoinSpec(from: "#EF8080", to: "#C0302A", mark: .parts([
      Part(d: ["M7.4 7.4h9.2v9.2H7.4z"], stroke: 2),
      Part(d: ["M10.4 4.2v3.2", "M13.6 4.2v3.2", "M10.4 16.6v3.2", "M13.6 16.6v3.2"], stroke: 1.7)])),
    "CSOPSKHYNIX2L": CoinSpec(from: "#F09090", to: "#C84038", mark: .parts([
      Part(d: ["M7.4 6.4h9.2v9.2H7.4z"], stroke: 2),
      Part(d: ["M5 19.4h14"], stroke: 2)])),
    // 现代：一枚斜着的椭圆环。
    "HYUNDAI": CoinSpec(from: "#8FB6D4", to: "#2E5A7A", mark: .parts([
      Part(d: ["M4.6 8.4a7.4 4.4 0 1 1 0 7.2 7.4 4.4 0 0 1 0-7.2z"], stroke: 2),
      Part(d: ["M9 9.6l6 4.8"], stroke: 2)])),
    // LG：一张圆脸。
    "LGELECTRONICS": CoinSpec(from: "#EF8080", to: "#A50034", mark: .parts([
      Part(d: ["M12 4.6a7.4 7.4 0 1 1 0 14.8 7.4 7.4 0 0 1 0-14.8z"], stroke: 2),
      Part(d: ["M10 9.4a1.3 1.3 0 1 1 0 2.6 1.3 1.3 0 0 1 0-2.6z"], stroke: nil),
      Part(d: ["M8.6 14.6c1.8 1.6 5 1.6 6.8 0"], stroke: 1.8)])),
    // NAVER：一道折成 N 的粗笔画。
    "NAVER": CoinSpec(from: "#7FD4A8", to: "#03C75A", mark: fill([
      "M5.4 4.6h4.4l4.6 7V4.6h4.2v14.8h-4.4l-4.6-7v7H5.4z"])),
    // 韩美药品：一粒药片加一道分割线。
    "HANMI": CoinSpec(from: "#8FC4D4", to: "#2E6A8A", mark: .parts([
      Part(d: ["M12 5.6a6.4 6.4 0 1 1 0 12.8 6.4 6.4 0 0 1 0-12.8z"], stroke: 2),
      Part(d: ["M7.4 9.4h9.2"], stroke: 1.8)])),
    // 智谱：一圈开口的环加一点。
    "ZHIPU": CoinSpec(from: "#8FB6E8", to: "#2F5FA8", mark: .parts([
      Part(d: ["M15.6 6a7.2 7.2 0 1 0 3.4 5.2"], stroke: 2.1),
      Part(d: ["M12 9.2a2.8 2.8 0 1 1 0 5.6 2.8 2.8 0 0 1 0-5.6z"], stroke: nil)])),
    // MiniMax：两道相对的折线。
    "MINIMAX": CoinSpec(from: "#C0A8E8", to: "#6A3FB0", mark: stroke([
      "M4.6 16.4V9.6l3.6 3.4 3.6-3.4v6.8", "M13.4 7.6h6" , "M16.4 7.6v11"], 2.1)),
    // 长鑫存储：一排存储颗粒。
    "CXMT": CoinSpec(from: "#7FB6C8", to: "#2E6A7A", mark: .parts([
      Part(d: ["M4.4 8.4h15.2v7.2H4.4z"], stroke: 1.9),
      Part(d: ["M7.4 10.4h2.4v3.2H7.4z", "M11 10.4h2.4v3.2H11z", "M14.6 10.4h2.4v3.2h-2.4z"], stroke: nil)])),
    // 宇树做机器人：一台四足。
    "UNITREE": CoinSpec(from: "#A8B4C0", to: "#3E4A56", mark: .parts([
      Part(d: ["M6.4 8.6h11.2v5H6.4z"], stroke: nil),
      Part(d: ["M7.6 13.6v5.4", "M10.4 13.6v5.4", "M13.6 13.6v5.4", "M16.4 13.6v5.4",
               "M15.4 8.6l2.6-3.8"], stroke: 1.9)])),
    // 兆易创新做闪存：一枚带引脚的芯片。
    "GIGADEV": CoinSpec(from: "#8FC4A8", to: "#2E7D5B", mark: .parts([
      Part(d: ["M8.4 8.4h7.2v7.2H8.4z"], stroke: 1.9),
      Part(d: ["M5.2 10.4h3.2", "M5.2 13.6h3.2", "M15.6 10.4h3.2", "M15.6 13.6h3.2"], stroke: 1.7)])),
    // 中际旭创做光模块：一对对插的光口。
    "ZHONGJI": CoinSpec(from: "#8FC0E8", to: "#2F72A8", mark: .parts([
      Part(d: ["M3.6 9.4h7.2v5.2H3.6z", "M13.2 9.4h7.2v5.2h-7.2z"], stroke: 1.9),
      Part(d: ["M10.8 12h2.4"], stroke: 2)])),
  ]
}

// MARK: - 长尾：按代号散出来的几何标
//
// 到这儿的是画不准也代表不了什么的代号——Binance 那批合成股票代号、冷门中概、
// 只有四个字母的壳。它们仍然得有各自的图标：用户的原话是「每个品种都有单独的图标啊」，
// 全类共用一座门廊等于没画。
//
// 做法是拿代号散列，**当场拼**一枚记号：一个外形套一个内芯，再配上 `spare` 里的
// 一对渐变。同一个代号每次都落在同一枚上——今天是这个样子，明天还是这个样子。
//
// 早先是从十六枚成品记号里挑一枚。七百多支合约摊下去，平均四十五支共用一枚，
// 一屏十二行里撞上三五个同图是常事——AIGENSYN / AIN / AIXBT / AKT / ALCH 曾经
// 整整齐齐五个一样的缺口环，光靠再添几枚成品是补不上的。拆成两层之后是
// 十二 × 二十四 = 二百八十八种，再乘上各不相同的配色，一屏里撞脸基本不会发生。

extension CoinSpec {
  /// 外形：十二个闭合（或近乎闭合）的几何轮廓，一律描边。
  ///
  /// 都收在 24 格画布的中间，中央留出 5.6 格见方的空当给内芯——所以随便哪个外形
  /// 配上随便哪个内芯都不会压到一起。三角形之类「上窄下宽」的形状没有收进来，
  /// 它中间留不出那块方正的空当。
  private static let outers: [Part] = [
    Part(d: ["M12 4.6a7.4 7.4 0 1 1 0 14.8 7.4 7.4 0 0 1 0-14.8z"], stroke: 2.1),
    Part(d: ["M12 4.2l6.9 4v8L12 20.2l-6.9-4v-8z"], stroke: 2.1),
    Part(d: ["M7.2 4.9h9.6a2.3 2.3 0 0 1 2.3 2.3v9.6a2.3 2.3 0 0 1-2.3 2.3H7.2"
      + "a2.3 2.3 0 0 1-2.3-2.3V7.2a2.3 2.3 0 0 1 2.3-2.3z"], stroke: 2.1),
    Part(d: ["M12 3.9l8.1 8.1-8.1 8.1L3.9 12z"], stroke: 2.1),
    Part(d: ["M12 4.2l6.6 2.5v5c0 3.9-2.7 6.6-6.6 8.3-3.9-1.7-6.6-4.4-6.6-8.3v-5z"], stroke: 2.1),
    Part(d: ["M8.9 4.4h6.2l3.9 3.9v6.2l-3.9 3.9H8.9L5 14.5V8.3z"], stroke: 2.1),
    Part(d: ["M16.8 6.4a7.3 7.3 0 1 0 2.6 4.2"], stroke: 2.2),
    Part(d: ["M12 4.1l7.5 5.45-2.87 8.85H7.37L4.5 9.55z"], stroke: 2.1),
    Part(d: ["M12 4.6a4.6 4.6 0 0 1 4.6 4.6v5.6a4.6 4.6 0 0 1-9.2 0V9.2A4.6 4.6 0 0 1 12 4.6z"],
         stroke: 2.1),
    Part(d: ["M8.1 5.6h7.8l3.9 6.4-3.9 6.4H8.1L4.2 12z"], stroke: 2.1),
    Part(d: ["M4.9 19.1v-7.1a7.1 7.1 0 0 1 14.2 0v7.1"], stroke: 2.2),
    Part(d: ["M6.4 6.6h11.2a2.2 2.2 0 0 1 2.2 2.2v6.4a2.2 2.2 0 0 1-2.2 2.2H6.4"
      + "a2.2 2.2 0 0 1-2.2-2.2V8.8a2.2 2.2 0 0 1 2.2-2.2z"], stroke: 2.1),
  ]

  /// 内芯：二十四枚小记号，全部压在中间 5.6 格的方框里。
  /// 头一枚是空的——有四分之一不到的外形就这么空着，留白也是一种样子。
  private static let cores: [Part] = [
    Part(d: [], stroke: nil),
    Part(d: ["M12 9.2a2.8 2.8 0 1 1 0 5.6 2.8 2.8 0 0 1 0-5.6z"], stroke: nil),
    Part(d: ["M9.4 9.4h5.2v5.2H9.4z"], stroke: nil),
    Part(d: ["M12 9.1l2.9 2.9-2.9 2.9L9.1 12z"], stroke: nil),
    Part(d: ["M9.2 11h5.6v2H9.2z"], stroke: nil),
    Part(d: ["M11 9.2h2v5.6h-2z"], stroke: nil),
    Part(d: ["M11 9.2h2v5.6h-2z", "M9.2 11h5.6v2H9.2z"], stroke: nil),
    Part(d: ["M10.6 10.7a1.3 1.3 0 1 1 0 2.6 1.3 1.3 0 0 1 0-2.6z",
             "M13.4 10.7a1.3 1.3 0 1 1 0 2.6 1.3 1.3 0 0 1 0-2.6z"], stroke: nil),
    Part(d: ["M12 9.3a1.3 1.3 0 1 1 0 2.6 1.3 1.3 0 0 1 0-2.6z",
             "M12 12.1a1.3 1.3 0 1 1 0 2.6 1.3 1.3 0 0 1 0-2.6z"], stroke: nil),
    Part(d: ["M9.8 10.85a1.15 1.15 0 1 1 0 2.3 1.15 1.15 0 0 1 0-2.3z",
             "M12 10.85a1.15 1.15 0 1 1 0 2.3 1.15 1.15 0 0 1 0-2.3z",
             "M14.2 10.85a1.15 1.15 0 1 1 0 2.3 1.15 1.15 0 0 1 0-2.3z"], stroke: nil),
    Part(d: ["M12 8.7a1.2 1.2 0 1 1 0 2.4 1.2 1.2 0 0 1 0-2.4z",
             "M9.8 12.9a1.2 1.2 0 1 1 0 2.4 1.2 1.2 0 0 1 0-2.4z",
             "M14.2 12.9a1.2 1.2 0 1 1 0 2.4 1.2 1.2 0 0 1 0-2.4z"], stroke: nil),
    Part(d: ["M10.3 9.15a1.15 1.15 0 1 1 0 2.3 1.15 1.15 0 0 1 0-2.3z",
             "M13.7 9.15a1.15 1.15 0 1 1 0 2.3 1.15 1.15 0 0 1 0-2.3z",
             "M10.3 12.55a1.15 1.15 0 1 1 0 2.3 1.15 1.15 0 0 1 0-2.3z",
             "M13.7 12.55a1.15 1.15 0 1 1 0 2.3 1.15 1.15 0 0 1 0-2.3z"], stroke: nil),
    Part(d: ["M12 9.2l3 5.6H9z"], stroke: nil),
    Part(d: ["M9 9.2h6L12 14.8z"], stroke: nil),
    Part(d: ["M12 9.2l3 5.6h-1.9L12 12.4l-1.1 2.4H9z"], stroke: nil),
    Part(d: ["M10.2 14.8L12.9 9.2h1.5L11.7 14.8z"], stroke: nil),
    Part(d: ["M9.8 9.2h2v3.6h3.2v2H9.8z"], stroke: nil),
    Part(d: ["M12 9.4a2.6 2.6 0 1 1 0 5.2 2.6 2.6 0 0 1 0-5.2z"], stroke: 2),
    Part(d: ["M9.2 10h5.6v1.7H9.2z", "M9.2 12.8h5.6v1.7H9.2z"], stroke: nil),
    Part(d: ["M12 9.2a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3z", "M9.4 13.3h5.2v1.6H9.4z"],
         stroke: nil),
    Part(d: ["M9.4 9.4h5.2l-5.2 5.4h5.2"], stroke: 2),
    Part(d: ["M9.2 13.8l1.9-2.6 1.8 1.8 1.9-2.8"], stroke: 2),
    Part(d: ["M12 9.2a2.8 2.8 0 0 1 0 5.6z"], stroke: nil),
    Part(d: ["M12 9.2v5.6", "M9.6 10.6l4.8 2.8", "M14.4 10.6l-4.8 2.8"], stroke: 1.9),
  ]

  /// 长尾标：代号决定套哪个外形、嵌哪枚内芯、配哪对色，一支一个样，且每次都一样。
  ///
  /// 三样各散各的（盐不同），免得被同一串字母绑在一起——那样一屏扫下去会冒出
  /// 「凡是蓝的都是六边形」这种规律，反而显得它们是同一类东西。
  static func generated(_ key: String, _ pair: (Hex, Hex)) -> CoinSpec {
    let outer = outers[scatter(key, 0x9E37) % outers.count]
    let core = cores[scatter(key, 0x85EB) % cores.count]
    return CoinSpec(from: pair.0, to: pair.1, mark: .parts([outer, core]), inset: 0.58)
  }

  /// FNV-1a，末尾再抖一下高位。原来那个 `(h * 131 + b) % 16` 只有低四位说了算，
  /// 字母相近的代号会成片落到同一枚上。
  private static func scatter(_ key: String, _ salt: UInt64) -> Int {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325 &+ salt
    for b in key.utf8 { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01b3 }
    h ^= h >> 33
    return Int(h & 0x7FFF_FFFF)
  }
}

