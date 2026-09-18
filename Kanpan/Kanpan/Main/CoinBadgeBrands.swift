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
      ?? chainsA[key] ?? chainsB[key]
  }

  // ---------------------------------------------------------------- 半导体与硬件

  private static let chips: [String: CoinSpec] = [
    // 美满电子：标就是一道折成 M 的粗笔画。
    "MRVL": CoinSpec(from: "#7FA8E8", to: "#1E4FA8",
                     mark: stroke(["M4.8 17.8V7.2l7.2 6.2 7.2-6.2v10.6"], 2.4)),
    // 博通做互连：三条错开的总线。
    "AVGO": CoinSpec(from: "#F0907A", to: "#B23023", mark: fill([
      "M3.4 4.4h10.2v4.4H3.4z",
      "M6.9 9.8h10.2v4.4H6.9z",
      "M10.4 15.2h10.2v4.4H10.4z"])),
    // Arm 只卖核，片子上那个口留给买家自己填：一块缺了一整个直角的方，那道内凹的台阶就是记号。
    // 原来是方片四周插八根 1.5 宽的引脚，引脚在 18px 上摊不到一个像素，整块糊成一团没有硬边的斑，
    // 跟企鹅、比特铭文那些圆润的东西全都像；缺口试过配一颗独立的小方，但那样又凑成了微软那面田字窗。
    "ARM": CoinSpec(from: "#6FC3D6", to: "#1D7A93", mark: fill([
      "M4.4 4.4h7.4v7.8h7.8v7.4H4.4z"])),
    // 阿斯麦：一束光锥打在晶圆上。
    "ASML": CoinSpec(from: "#8FB6F2", to: "#2F63C0", mark: .parts([
      Part(d: ["M8.8 3.6h6.4l-2 6.6h-2.4z"], stroke: nil),
      Part(d: ["M12 13a4.4 4.4 0 1 1 0 8.8 4.4 4.4 0 0 1 0-8.8z"], stroke: 1.8)])),
    // 应用材料做薄膜与刻蚀：一道刻出来的沟槽，上面悬着待沉积的一层膜。
    "AMAT": CoinSpec(from: "#A9C0E8", to: "#3E62A8", mark: fill([
      "M4.4 7.6h5v5.8h5.2V7.6h5v10H4.4z",
      "M9.8 3.4h4.4v2.2H9.8z"])),
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
    // 德州仪器：一枚饱满的五角星。
    "TXN": CoinSpec(from: "#EF7B7B", to: "#B3202A", mark: fill([
      "M12 2.6l2.75 6.3 6.85.66-5.15 4.55 1.49 6.72L12 17.3l-5.94 3.48 1.49-6.72L2.4 9.56l6.85-.66z"])),
    // 泰瑞达做半导体测试：一副探针台——四根短针扎在一条基板上。原来是一根光杆竖笔画
    // 加一条分离的底座，18px 下和诺基亚那根天线杆同一个骨架。坐标看着零碎是因为对齐了
    // 18px 的像素格（针 1px、缝 2px），不对齐的话四根针会糊成一团灰。
    "TER": CoinSpec(from: "#A9B8C8", to: "#4E637A", mark: fill([
      "M1.25 3.4h2.2v12.9h-2.2z",
      "M7.7 3.4h2.2v12.9H7.7z",
      "M14.15 3.4h2.2v12.9h-2.2z",
      "M20.6 3.4h2.2v12.9h-2.2z",
      "M1.25 16.3h21.55v4.3H1.25z"])),
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
    // Astera Labs 做互连：两枚接力的箭头。
    "ALAB": CoinSpec(from: "#E8A8C8", to: "#B0407A", mark: fill([
      "M4.4 5.2l6.4 6.8-6.4 6.8z",
      "M12.8 5.2l6.4 6.8-6.4 6.8z"])),
    // 应用光电做光模块：一颗光源打出一束光锥。
    "AAOI": CoinSpec(from: "#8FC0E8", to: "#2F72A8", mark: fill([
      "M3.6 9.6a2.4 2.4 0 1 1 0 4.8 2.4 2.4 0 0 1 0-4.8z",
      "M8.6 6.2l11.8 3.6v4.4L8.6 17.8z"])),
    // AXT 做化合物衬底：一根斜切下来的晶条。
    "AXTI": CoinSpec(from: "#C0C8D4", to: "#65707F", mark: fill(["M8.6 3.8h9.2l-7.4 16.4H1.4z"])),
    // 闪迪做闪存：一整片卡身，底下伸出三根插进机器的触点，触点之间是透底的缝。
    // 原来靠右上角切一刀来认，切角在 18px 上摊不到两个像素等于没切，卡身就只剩一块素方砖。
    "SNDK": CoinSpec(from: "#E8C07A", to: "#B08420", mark: fill([
      "M4.6 4.8h14.8v8.8H4.6z",
      "M4.6 13.6h3.2v5.6H4.6z",
      "M10.4 13.6h3.2v5.6h-3.2z",
      "M16.2 13.6h3.2v5.6h-3.2z"])),
    // 西部数据做硬盘：一摞碟片，最上面那张刚被抬起来。
    "WDC": CoinSpec(from: "#8FA8C8", to: "#34506E", mark: fill([
      "M5 10.2a7 2.4 0 1 1 14 0v6.6a7 2.4 0 0 1-14 0z",
      "M6.8 4.2a5.2 1.8 0 1 1 10.4 0 5.2 1.8 0 1 1-10.4 0z"])),
    // 超微做服务器：一只三层机架。
    "SMCI": CoinSpec(from: "#7FC4A8", to: "#2E7D5B", mark: .parts([
      Part(d: ["M4.6 5.4h14.8v4H4.6z", "M4.6 10h14.8v4H4.6z", "M4.6 14.6h14.8v4H4.6z"], stroke: 1.6),
      Part(d: ["M6.6 6.8a.8 .8 0 1 1 0 1.6 .8 .8 0 0 1 0-1.6z",
               "M6.6 11.4a.8 .8 0 1 1 0 1.6 .8 .8 0 0 1 0-1.6z",
               "M6.6 16a.8 .8 0 1 1 0 1.6 .8 .8 0 0 1 0-1.6z"], stroke: nil)])),
    // 戴尔做整机：一台立式主机，两道进风口加一颗电源灯。
    "DELL": CoinSpec(from: "#7FB6E8", to: "#1F5E9E", mark: .parts([
      Part(d: ["M9.6 3.8h4.8a2.2 2.2 0 0 1 2.2 2.2v12a2.2 2.2 0 0 1-2.2 2.2H9.6a2.2 2.2 0 0 1-2.2-2.2V6a2.2 2.2 0 0 1 2.2-2.2z"], stroke: 2),
      Part(d: ["M9.8 7.4h4.4v1.7H9.8z", "M9.8 10.6h4.4v1.7H9.8z",
               "M12 14.6a1.3 1.3 0 1 1 0 2.6 1.3 1.3 0 0 1 0-2.6z"], stroke: nil)])),
    // 慧与：品牌就是那只横着的方框。
    "HPE": CoinSpec(from: "#7FD4A8", to: "#1E8A5B", mark: stroke(["M4 7h16v10H4z"], 2.8)),
    // 英特尔：一枚方正的处理器，底下压一条长墩。
    "INTC": CoinSpec(from: "#7FB6E8", to: "#1050A8", mark: fill([
      "M7.4 4.8h9.2a1.8 1.8 0 0 1 1.8 1.8v7.6a1.8 1.8 0 0 1-1.8 1.8H7.4a1.8 1.8 0 0 1-1.8-1.8V6.6a1.8 1.8 0 0 1 1.8-1.8z",
      "M3.6 17.4h16.8v3.2H3.6z"])),
    // 诺基亚做连接：一根顶着信号点的天线杆。
    "NOK": CoinSpec(from: "#8FA8E8", to: "#2A4FA8", mark: fill([
      "M12 3a1.9 1.9 0 1 1 0 3.8 1.9 1.9 0 0 1 0-3.8z",
      "M10.3 7.6h3.4l2.7 12.4h-3.1l-1.3-6.4-1.3 6.4H7.6z"])),
    // 康宁做玻璃：一块立着的玻璃板，斜里划过一道高光。原来是「菱形轮廓 + 菱心」，
    // 和 Lisk 同一个骨架，18px 下就是两枚菱环；换成直角的板，高光留成一道透底的缝。
    "GLW": CoinSpec(from: "#A8C8D4", to: "#3E6070", mark: fill([
      "M7.4 4.2h9.2l-1.6 15.6H9z"
        + "M11.3 17.2L16.4 6.2h-2.6L8.7 17.2z"])),
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
    // 台积电做代工：一整片晶圆，被切割道划成四块。
    "TSM": CoinSpec(from: "#7FA8E8", to: "#1F4FA8", mark: fill([
      "M10.8 4.5A7.6 7.6 0 0 0 4.5 10.8H10.8z",
      "M13.2 4.5A7.6 7.6 0 0 1 19.5 10.8H13.2z",
      "M19.5 13.2A7.6 7.6 0 0 1 13.2 19.5V13.2z",
      "M10.8 19.5A7.6 7.6 0 0 1 4.5 13.2H10.8z"])),
    // 高通做基带：两侧对开的信号弧裹住一颗发射点。
    "QCOM": CoinSpec(from: "#7FA8E8", to: "#2F5FD0", mark: .parts([
      Part(d: ["M7.4 5.2a10 10 0 0 0 0 13.6", "M16.6 5.2a10 10 0 0 1 0 13.6",
               "M10.2 8.4a5.4 5.4 0 0 0 0 7.2", "M13.8 8.4a5.4 5.4 0 0 1 0 7.2"], stroke: 2),
      Part(d: ["M12 10.3a1.7 1.7 0 1 1 0 3.4 1.7 1.7 0 0 1 0-3.4z"], stroke: nil)])),
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
    // MongoDB 的那片叶子：顶上尖、底下圆，中间一道透底的叶脉缝把叶片劈成左窄右宽两半。
    // 原来是三层摞起来的库，18px 下三道缝糊成一块没有特征的素砖，和任何方骨架都撞。
    "MDB": CoinSpec(from: "#9FD48C", to: "#3E8B2C", mark: fill([
      "M13.4 2c3.4 4.4 6.2 9.4 6.2 13.2 0 3.6-2.6 6.4-6.2 6.4z",
      "M10.2 6.4c-2.8 3.4-4.8 7.2-4.8 10.2 0 2.6 1.8 4.4 4.8 4.4z"])),
    // Datadog：一只探头的狗。
    "DDOG": CoinSpec(from: "#C0A8E8", to: "#6A3FB0", mark: .parts([
      Part(d: ["M5.6 9.4l3-3.4v3.2h6.2l3.6-2.4v9.6h-4.6v3.6H8.2v-3.6H5.6z"], stroke: nil),
      Part(d: ["M15.8 10.6a1.2 1.2 0 1 1 0 2.4 1.2 1.2 0 0 1 0-2.4z"], stroke: nil)])),
    // Cloudflare：一朵云压在一道气流上。
    "NET": CoinSpec(from: "#F0B47A", to: "#C87A18", mark: .parts([
      Part(d: ["M8.6 15.4a3.6 3.6 0 0 1 .3-7.2 4.8 4.8 0 0 1 9 .8 3.2 3.2 0 0 1-.5 6.4z"], stroke: nil),
      Part(d: ["M3.6 18.2h12.8"], stroke: 2)])),
    // Zscaler 做安全网关：一把横挂的锁。
    "ZS": CoinSpec(from: "#8FC4E8", to: "#2F6FA8", mark: .parts([
      Part(d: ["M9.4 11.4v-1.8a2.6 2.6 0 0 1 5.2 0v1.8"], stroke: 2.2),
      Part(d: [
               "M4.2 11.4h15.6a1.8 1.8 0 0 1 1.8 1.8v5.2a1.8 1.8 0 0 1-1.8 1.8H4.2a1.8 1.8 0 0 1-1.8-1.8v-5.2a1.8 1.8 0 0 1 1.8-1.8z"], stroke: nil)])),
    // Palo Alto Networks：一枚六边形的锁。
    "PANW": CoinSpec(from: "#F0A07A", to: "#C05020", mark: .parts([
      Part(d: ["M12 3.4l7 4v9.2l-7 4-7-4V7.4z"], stroke: 1.9),
      Part(d: ["M9.6 11h4.8v4.4H9.6z"], stroke: nil),
      Part(d: ["M10.4 11V9.4a1.6 1.6 0 0 1 3.2 0V11"], stroke: 1.5)])),
    // CrowdStrike：一对相向合拢的箭镞。
    "CRWD": CoinSpec(from: "#EF8080", to: "#B02028", mark: fill([
      "M10.6 3.4v17.2L2.6 12z",
      "M13.4 3.4v17.2L21.4 12z"])),
    // GitLab：由三角拼出的那只狐狸。
    "GTLB": CoinSpec(from: "#F0A47A", to: "#C25A18", mark: fill([
      "M12 20.8L4.2 12.2l1.6-3.4 2.6 3.4h7.2l2.6-3.4 1.6 3.4z",
      "M5.8 8.6L4.4 4.2l3 2.6z",
      "M18.2 8.6l1.4-4.4-3 2.6z"])),
    // Atlassian：一对折起来的角。
    "TEAM": CoinSpec(from: "#7FA8F0", to: "#1F5FD0", mark: fill([
      "M9.8 3.6L18.8 20H12L9.8 3.6z", "M8.4 9.8L13 20H3.8L8.4 9.8z"])),
    // Palantir：三层叠起来的棱。
    "PLTR": CoinSpec(from: "#A8B4C0", to: "#3E4A56", mark: fill([
      "M12 3.6l7.4 4.6H4.6z", "M12 9.6l7.4 4.6H4.6z", "M12 15.6l7.4 4.6H4.6z"])),
    // AppLovin 手里是一整组手机应用：两枚错开叠着的应用块。
    "APP": CoinSpec(from: "#8FC4A8", to: "#2E7D5B", mark: .parts([
      Part(d: ["M8 3.6h8.4a2 2 0 0 1 2 2v8.4"], stroke: 2.2),
      Part(d: ["M5.6 8h8.4a2 2 0 0 1 2 2v8.4a2 2 0 0 1-2 2H5.6a2 2 0 0 1-2-2V10a2 2 0 0 1 2-2z"], stroke: nil)])),
    // eBay：一枚倒角的价签。
    "EBAY": CoinSpec(from: "#F0A07A", to: "#C04020", mark: fill([
      "M12.6 3.4h7a1.6 1.6 0 0 1 1.6 1.6v7a1.6 1.6 0 0 1-.47 1.13l-7.9 7.9a1.6 1.6 0 0 1-2.26 0l-7.6-7.6a1.6 1.6 0 0 1 0-2.26l7.9-7.9A1.6 1.6 0 0 1 12.6 3.4zM17.3 5.7a1.9 1.9 0 1 0 0 3.8 1.9 1.9 0 0 0 0-3.8z"])),
    // Shopify：一只购物袋。
    "SHOP": CoinSpec(from: "#9FD48C", to: "#4A8B2C", mark: .parts([
      Part(d: ["M9 9.4V7a3 3 0 0 1 6 0v2.4"], stroke: 1.8),
      Part(d: [
               "M5.4 8.2h13.2l-1.2 12H6.6zM12 11.8a2.6 2.6 0 1 0 0 5.2 2.6 2.6 0 0 0 0-5.2z"], stroke: nil)])),
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
    // 家得宝：一栋房子。
    "HD": CoinSpec(from: "#F0A07A", to: "#D06018", mark: fill([
      "M12 3.4l9 7.8h-2.7v9h-4.2v-5.4h-4.2v5.4H5.7v-9H3z"])),
    // 阿里：那张笑脸丝带。
    "BABA": CoinSpec(from: "#F0A07A", to: "#D06018", mark: .parts([
      Part(d: ["M6.4 8.8c1.8-2.6 4-3.8 6.6-3.8 3 0 5 1.6 5 3.8 0 3.4-4.2 4-4.2 6.4"], stroke: 2.1),
      Part(d: ["M6.6 13.4a2.2 2.2 0 1 1 0 4.4 2.2 2.2 0 0 1 0-4.4z",
               "M13.8 16.4a2.2 2.2 0 1 1 0 4.4 2.2 2.2 0 0 1 0-4.4z"], stroke: nil)])),
    // 拼多多：一只拎起来的菜篮。
    "PDD": CoinSpec(from: "#EF8080", to: "#C0302A", mark: .parts([
      Part(d: ["M8.4 8.6L10.2 4.4", "M15.6 8.6L13.8 4.4"], stroke: 2.0),
      Part(d: ["M3.4 9.4h17.2l-2.1 10.2H5.5z"], stroke: nil)])),
    // GameStop 卖的是游戏卡带：一盒卡带，正面挖出标签窗，底下是插进机器的那截。
    // 原来是横着的手柄，手柄上那个十字键只有 1.5 宽，18px 下全糊掉，只剩一根横胶囊，和 Zoom 那只镜头撞脸。
    "GME": CoinSpec(from: "#EF8080", to: "#B02028", mark: fill([
      "M6.6 3.6h10.8v11.6H6.6zM9 6v4.2h6V6z",
      "M9.2 15.2h5.6v4.6H9.2z"])),
    // 温迪的是个汉堡。
    "WEN": CoinSpec(from: "#EF8080", to: "#B02028", mark: fill([
      "M4.6 8.2c0-2.4 3.3-4 7.4-4s7.4 1.6 7.4 4z",
      "M4.4 10h15.2v2.6H4.4z",
      "M4.6 14.4h14.8c0 2.6-3.3 4.4-7.4 4.4s-7.4-1.8-7.4-4.4z"])),
    // 礼来：一粒胶囊。
    "LLY": CoinSpec(from: "#EF8080", to: "#C0302A", mark: .parts([
      Part(d: ["M7.6 13.2l5.6-5.6a4 4 0 0 1 5.6 5.6l-5.6 5.6a4 4 0 0 1-5.6-5.6z"], stroke: 1.9),
      Part(d: ["M10.4 10.4l5.6 5.6"], stroke: 1.9)])),
    // 默沙东是家老药厂：一只臼，一根斜插进去的杵——平口加半圆底，在 18px 上是一块有直边也有弧边的整形。
    // 原来那只锥形瓶「上窄下宽一坨」太通用，同时挤进诺基亚、Atlassian、韩美药品三家，瓶颈根本活不下来；
    // 中途试过正十字，又跟 CoreWeave 那两条编带撞成一个，所以换成这只臼。
    "MRK": CoinSpec(from: "#7FC4B8", to: "#0E7C6E", mark: fill([
      "M4.8 11.2h14.4a7.2 7.2 0 0 1-14.4 0z",
      "M18.9 1.9L11.9 8.9l2.1 2.1 7.1-7.1z"])),
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
    // Coinbase 替人托币：两枚斜着叠起来的实心币。
    "COIN": CoinSpec(from: "#7FA8F0", to: "#1652F0", mark: fill([
      "M8.2 4.6a5.8 5.8 0 1 1 0 11.6 5.8 5.8 0 0 1 0-11.6z",
      "M15.8 7.8a5.8 5.8 0 1 1 0 11.6 5.8 5.8 0 0 1 0-11.6z"])),
    // 罗宾汉：一根羽毛。
    "HOOD": CoinSpec(from: "#9FD48C", to: "#3E8B2C", mark: .parts([
      Part(d: ["M18.4 4.4c1 6.6-2.4 11-8.4 11.6l-2.8.3c.4-6.6 4.2-10.6 11.2-11.9z"], stroke: nil),
      Part(d: ["M5 20.4l5.6-6"], stroke: 2)])),
    // SoFi：三道递进的弧。
    "SOFI": CoinSpec(from: "#F0A07A", to: "#C0502A", mark: stroke([
      "M5.4 17.6a4 4 0 0 1 4-4", "M5.4 17.6a8 8 0 0 1 8-8", "M5.4 17.6a12 12 0 0 1 12-12"], 2)),
    // 摩根大通：大通那枚四块风车围出的方口。
    "JPM": CoinSpec(from: "#8FA8C8", to: "#2E4A6E", mark: fill([
      "M3.8 3.8h10.1v4.9H3.8z", "M15.3 3.8h4.9v10.1h-4.9z",
      "M10.1 15.3h10.1v4.9H10.1z", "M3.8 10.1h4.9v10.1H3.8z"])),
    // 高盛：两根柱子顶一道横梁。
    "GS": CoinSpec(from: "#A8B8C8", to: "#45607A", mark: fill([
      "M3.8 5.4h16.4v2.6H3.8z", "M6.6 9h3.2v9.4H6.6z", "M14.2 9h3.2v9.4h-3.2z",
      "M3.8 19.8h16.4v1.4H3.8z"])),
    // 黑石：三块错开的方。
    "BX": CoinSpec(from: "#9AA4B0", to: "#20262E", mark: fill([
      "M4.4 4.4h7.2v7.2H4.4z", "M12.4 8.4h7.2v7.2h-7.2z", "M4.4 12.4h7.2v7.2H4.4z"])),
    // 伯克希尔：一座三根柱子的门廊。
    "BRKB": CoinSpec(from: "#A8B4C0", to: "#3E4A56", mark: fill([
      "M12 3.6l8.8 5.2H3.2z",
      "M5 10h2.6v7.4H5z",
      "M9.4 10H12v7.4H9.4z",
      "M13.8 10h2.6v7.4h-2.6z",
      "M3.2 18.6h17.6v2.4H3.2z"])),
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
    // Strategy（原 MicroStrategy）囤币：四根越垒越高的柱。
    "MSTR": CoinSpec(from: "#8FB6E8", to: "#2F5FA8", mark: fill([
      "M4.4 13.4h2.6v6H4.4z",
      "M8.4 10.2h2.6v9.2H8.4z",
      "M13 7h2.6v12.4H13z",
      "M17 3.8h2.6v15.6H17z"])),
    // MARA 挖矿：一座圆顶矿场压在一条长墩上。
    "MARA": CoinSpec(from: "#7FC4A8", to: "#2E7D5B", mark: fill([
      "M4.6 16.4a7.4 7.4 0 0 1 14.8 0z",
      "M3.2 16.8h17.6v3.2H3.2z"])),
    // Circle：一枚实心的圆。
    "CRCL": CoinSpec(from: "#8FC4E8", to: "#2F7FC8", mark: fill(["M12 3a9 9 0 1 1 0 18 9 9 0 0 1 0-18z"])),
    // CoreWeave：两条带子编在一起——竖的那条从横的底下穿过去，交叠处断开留缝。
    // 原来是井字格，18px 下和 Stacks 那两横夹 V 一样只剩一团格子。
    "CRWV": CoinSpec(from: "#C0A8E8", to: "#6A3FB0", mark: fill([
      "M3.4 9.4h17.2v5.2H3.4z",
      "M9.6 3.4h4.8v4.6H9.6z",
      "M9.6 16h4.8v4.6H9.6z"])),
    // Bitmine：一台矿机。
    "BMNR": CoinSpec(from: "#E8C07A", to: "#A8802C", mark: .parts([
      Part(d: ["M4.4 7h15.2v10H4.4z"], stroke: 1.9),
      Part(d: ["M7.4 9.6h2.2v4.8H7.4z", "M11 9.6h2.2v4.8H11z", "M14.6 9.6h2.2v4.8h-2.2z"], stroke: nil),
      Part(d: ["M7 19.4h10"], stroke: 1.8)])),

    // ── ETF：也是一支一个记号，别让它们共用「三根柱」。
    // SPY：标普：三根柱加地平线
    "SPY": CoinSpec(from: "#B9C7E8", to: "#2F4F9E", mark: fill([
      "M6 10.5h2.8V16H6z",
      "M10.6 6.5h2.8V16h-2.8z",
      "M15.2 8.5H18V16h-2.8z",
      "M5 17.6h14v1.6H5z"
    ])),
    // QQQ：纳指：一条往上走的折线带箭头
    "QQQ": CoinSpec(from: "#9CD3EC", to: "#0F7CB6", mark: stroke([
      "M4.8 16.4l4.2-4.2 3.2 2.2 7-7",
      "M15 7.4h4.2v4.2"
    ], 2.2)),
    // SOXL：三倍做多半导体：一枚芯片，箭头从顶边冲出去。
    "SOXL": CoinSpec(from: "#F5B183", to: "#D2521E", mark: .parts([
      Part(d: [
        "M7.6 8.4h8.8v8.8H7.6z",
        "M10 17.2v2.8",
        "M14 17.2v2.8",
        "M4.8 10.8h2.8",
        "M4.8 14.8h2.8",
        "M16.4 10.8h2.8",
        "M16.4 14.8h2.8"
      ], stroke: 1.8),
      Part(d: [
        "M12 2.6l3.6 4.6h-2.1v7.6h-3V7.2h-2.1z"
      ], stroke: nil)
    ])),
    // SOXS：三倍做空半导体：一枚芯片，箭头从底边戳下去。
    "SOXS": CoinSpec(from: "#9EC2E8", to: "#2E5A9C", mark: .parts([
      Part(d: [
        "M7.6 6.8h8.8v8.8H7.6z",
        "M10 4v2.8",
        "M14 4v2.8",
        "M4.8 9.2h2.8",
        "M4.8 13.2h2.8",
        "M16.4 9.2h2.8",
        "M16.4 13.2h2.8"
      ], stroke: 1.8),
      Part(d: [
        "M12 21.4l-3.6-4.6h2.1V9.2h3v7.6h2.1z"
      ], stroke: nil)
    ])),
    // 韩国 ETF：太极的阴阳两半。
    "EWY": CoinSpec(from: "#F2A3A3", to: "#3459B5", mark: fill([
      "M12 4.2a7.8 7.8 0 0 1 0 15.6 3.9 3.9 0 0 1 0-7.8 3.9 3.9 0 0 0 0-7.8z"])),
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
    // Vertiv 做机房：一座立式机柜，开两道出风口。
    "VRT": CoinSpec(from: "#9FD48C", to: "#4A8B2C", mark: fill([
      "M7 3.4h10a1.8 1.8 0 0 1 1.8 1.8v13.6a1.8 1.8 0 0 1-1.8 1.8H7a1.8 1.8 0 0 1-1.8-1.8V5.2A1.8 1.8 0 0 1 7 3.4zM7.4 7.4v2h9.2v-2zM7.4 11.4v2h9.2v-2z"])),
    // Bloom Energy 做燃料电池：一摞极板顶着电极。
    "BE": CoinSpec(from: "#9FD48C", to: "#3E8B4C", mark: fill([
      "M10.2 2.6h3.6v2.2h-3.6z",
      "M4.6 5.2h14.8v4.4H4.6z",
      "M4.6 10.6h14.8v4.4H4.6z",
      "M4.6 16h14.8v4.4H4.6z"])),
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
    "USAR": CoinSpec(from: "#EF8080", to: "#B02028", mark: fill([
      "M5.2 18.2V11.6a6.8 6.8 0 0 1 13.6 0v6.6h-3.6v-6.6a3.2 3.2 0 0 0-6.4 0v6.6z",
      "M3.6 17.4h6.2v3H3.6z", "M14.2 17.4h6.2v3h-6.2z"])),
    // 火箭实验室：一支圆头主箭夹着两枚助推器。
    "RKLB": CoinSpec(from: "#A8B4C0", to: "#2E3A46", mark: fill([
      "M12 2.6c1.9 1.9 2.9 4.2 2.9 6.9v9.2h-5.8V9.5c0-2.7 1-5 2.9-6.9z",
      "M6.6 8.2c1 .9 1.5 2 1.5 3.4v7.1H5.1V11.6c0-1.4.5-2.5 1.5-3.4z",
      "M17.4 8.2c1 .9 1.5 2 1.5 3.4v7.1h-3V11.6c0-1.4.5-2.5 1.5-3.4z",
      "M9.4 19.6h5.2l-2.6 2.4z"])),
    // AST SpaceMobile 做天基基站：一颗带帆板的卫星。
    "ASTS": CoinSpec(from: "#8FB6E8", to: "#2F5FA8", mark: .parts([
      Part(d: ["M10 10h4v4h-4z"], stroke: nil),
      Part(d: ["M2.8 9h6.2v6H2.8z", "M15 9h6.2v6H15z"], stroke: 1.7),
      Part(d: ["M12 10V5.6", "M12 14v4.4"], stroke: 1.7)])),
    // IonQ 做离子阱：一只势阱托着一排离子。
    "IONQ": CoinSpec(from: "#C0A8E8", to: "#6A3FB0", mark: .parts([
      Part(d: ["M5.4 4.6v6.8a6.6 6.6 0 0 0 13.2 0V4.6"], stroke: 2.4),
      Part(d: ["M8.4 11a1.35 1.35 0 1 1 0 2.7 1.35 1.35 0 0 1 0-2.7z",
               "M12 11a1.35 1.35 0 1 1 0 2.7 1.35 1.35 0 0 1 0-2.7z",
               "M15.6 11a1.35 1.35 0 1 1 0 2.7 1.35 1.35 0 0 1 0-2.7z"], stroke: nil)])),
    // Tempus 做基因组：一段读出来的测序波形。
    "TEM": CoinSpec(from: "#8FC4C0", to: "#2E7D6B", mark: fill([
      "M3.4 10.6h4l2.3-4.8 3.4 11 2.5-6.2h5v3.4h-2.7l-3.7 8.2-3.4-11.2-1.5 2.6H3.4z"])),
    // Flex 做代工：一道折起来的产线。
    "FLEX": CoinSpec(from: "#8FA8C8", to: "#34506E", mark: stroke([
      "M4.4 6.6h9.2v5H4.4", "M10.4 12.4h9.2v5h-9.2"], 2)),
  ]

  // ---------------------------------------------------------------- 港股 / 韩股 / A 股

  private static let asia: [String: CoinSpec] = [
    // 腾讯：那只企鹅。两只眼睛原来是另画的一块白，压在同样是白的身子上等于没画，
    // 18px 下就是一只没脸的黑影；改成在身子那条路径里反向挖两个洞，才真的透出底色。
    "TENCENT": CoinSpec(from: "#7FC4E8", to: "#2F6FA8", mark: .parts([
      Part(d: ["M12 3.2c2.9 0 4.6 2.3 4.6 5.4 0 1.5.9 2.8 2.2 4.6 1 1.4 1 2.6.2 3.2-.9.7-2.1.2-3-.8-.5 2.2-2.1 3.6-4 3.6s-3.5-1.4-4-3.6c-.9 1-2.1 1.5-3 .8-.8-.6-.8-1.8.2-3.2 1.3-1.8 2.2-3.1 2.2-4.6 0-3.1 1.7-5.4 4.6-5.4z"
        + "M10.2 6.3a1.5 1.5 0 1 0 0 3 1.5 1.5 0 1 0 0-3z"
        + "M13.8 6.3a1.5 1.5 0 1 0 0 3 1.5 1.5 0 1 0 0-3z"], stroke: nil)])),
    // 美团：那只袋鼠的头。
    "MEITUAN": CoinSpec(from: "#F0D060", to: "#D0A000", mark: .parts([
      Part(d: ["M8.4 8.6c0-2.8 1.6-4.6 3.6-4.6s3.6 1.8 3.6 4.6v2.2c0 4.4-1.6 7-3.6 8.8-2-1.8-3.6-4.4-3.6-8.8z"], stroke: nil),
      Part(d: ["M6.2 5.2l2.6 3.6", "M17.8 5.2l-2.6 3.6"], stroke: 2)])),
    // 快手：圆角方屏里挖出一枚播放三角。
    "KUAISHOU": CoinSpec(from: "#F0A0C0", to: "#E0307A", mark: fill([
      "M8.4 4.4h7.2a4 4 0 0 1 4 4v7.2a4 4 0 0 1-4 4H8.4a4 4 0 0 1-4-4V8.4a4 4 0 0 1 4-4zM8.6 6.9v10.2l8.8-5.1z"])),
    // 小米：那块圆角方。
    "HK1810": CoinSpec(from: "#F0A07A", to: "#E04020", mark: .parts([
      Part(d: ["M6.4 6.4h11.2c.9 0 1.6.7 1.6 1.6v8c0 .9-.7 1.6-1.6 1.6H6.4c-.9 0-1.6-.7-1.6-1.6v-8c0-.9.7-1.6 1.6-1.6z"], stroke: 2),
      Part(d: ["M8.2 15.4V9.4c1.8 0 2.6.8 2.6 2.6v3.4", "M15.8 9.4v6"], stroke: 1.8)])),
    // 腾讯的港股代号走同一张牌。
    "HK0700": CoinSpec(from: "#7FC4E8", to: "#2F6FA8", mark: .parts([
      Part(d: ["M12 3.2c2.9 0 4.6 2.3 4.6 5.4 0 1.5.9 2.8 2.2 4.6 1 1.4 1 2.6.2 3.2-.9.7-2.1.2-3-.8-.5 2.2-2.1 3.6-4 3.6s-3.5-1.4-4-3.6c-.9 1-2.1 1.5-3 .8-.8-.6-.8-1.8.2-3.2 1.3-1.8 2.2-3.1 2.2-4.6 0-3.1 1.7-5.4 4.6-5.4z"
        + "M10.2 6.3a1.5 1.5 0 1 0 0 3 1.5 1.5 0 1 0 0-3z"
        + "M13.8 6.3a1.5 1.5 0 1 0 0 3 1.5 1.5 0 1 0 0-3z"], stroke: nil)])),
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
    // 三星：那枚斜着的椭圆。
    "SAMSUNG": CoinSpec(from: "#7FA8E8", to: "#1428A0", mark: stroke([
      "M4.8 15.8a6.4 4.2 -18 0 1 14.4-6.6 6.4 4.2 -18 0 1-14.4 6.6z"], 3.2)),
    // 三星电机做被动元件：一枚电感线圈——一条基线上三个连着的鼓包。原来那颗带端电极的
    // 贴片电容是个横哑铃，18px 下和 Zoom 那枚横胶囊同一个骨架。
    "SAMSUNGEM": CoinSpec(from: "#8FB6E8", to: "#2040B0", mark: fill([
      "M3 13.4a3 6 0 0 1 6 0z",
      "M9 13.4a3 6 0 0 1 6 0z",
      "M15 13.4a3 6 0 0 1 6 0z",
      "M2.4 13.4h19.2v3.8H2.4z"])),
    // 南方三星两倍做多：三星那枚斜椭圆，底下垫两道杠。
    "CSOPSAMSUNG2L": CoinSpec(from: "#9FC0E8", to: "#2A44B8", mark: fill([
      "M4.8 13.6a6.2 4 -18 0 1 14-6.4 6.2 4 -18 0 1-14 6.4z",
      "M4.6 16.8h14.8v2.1H4.6z",
      "M7 20h10v2.1H7z"])),
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
    // LG：那张笑脸，只留下巴和一只眼。
    "LGELECTRONICS": CoinSpec(from: "#EF8080", to: "#A50034", mark: .parts([
      Part(d: ["M4.8 11.4a7.2 7.2 0 0 0 14.4 0"], stroke: 3.0),
      Part(d: ["M9.4 5.6a2.1 2.1 0 1 1 0 4.2 2.1 2.1 0 0 1 0-4.2z"], stroke: nil)])),
    // NAVER：一道折成 N 的粗笔画。
    "NAVER": CoinSpec(from: "#7FD4A8", to: "#03C75A", mark: fill([
      "M5.4 4.6h4.4l4.6 7V4.6h4.2v14.8h-4.4l-4.6-7v7H5.4z"])),
    // 韩美药品：一粒从中间错开半格的胶囊。
    "HANMI": CoinSpec(from: "#8FC4D4", to: "#2E6A8A", mark: fill([
      "M11.2 3.4a3.6 3.6 0 0 1 3.6 3.6v6.2H7.6V7a3.6 3.6 0 0 1 3.6-3.6z",
      "M9.2 12.8h7.2v6.2a3.6 3.6 0 0 1-7.2 0z"])),
    // 智谱做对话模型：一只气泡。
    "ZHIPU": CoinSpec(from: "#8FB6E8", to: "#2F5FA8", mark: fill([
      "M5.2 4.6h13.6a2.2 2.2 0 0 1 2.2 2.2v7.6a2.2 2.2 0 0 1-2.2 2.2h-6.4l-5 3.8 1-3.8H5.2A2.2 2.2 0 0 1 3 14.4V6.8a2.2 2.2 0 0 1 2.2-2.2z"])),
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
    // 兆易创新做闪存：一枚缺角的裸片，左边伸出三根脚。
    "GIGADEV": CoinSpec(from: "#8FC4A8", to: "#2E7D5B", mark: fill([
      "M6.6 5.8h8.2l3.4 3.4v9.4H6.6z",
      "M2.6 8.2h4v2.2h-4z",
      "M2.6 12h4v2.2h-4z",
      "M2.6 15.8h4v2.2h-4z"])),
    // 中际旭创做光模块：一对对插的光口。
    "ZHONGJI": CoinSpec(from: "#8FC0E8", to: "#2F72A8", mark: fill([
      "M4.6 5.2h11.6l2.6 2.8-2.6 2.8H4.6z",
      "M4.6 13.2h11.6l2.6 2.8-2.6 2.8H4.6z"])),
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

  // ---------------------------------------------------------------- 链与代币
  //
  // 常看的那批币原来大多落在 `generated` 的长尾标上——散列出来的几何形每支不重样，
  // 但它回答不了「这是哪个币」。这两张表按各自的标补上真记号：门罗是那个 M 的三角、
  // Cosmos 是三环轨道、SHIB 是狗头、PENGU 是企鹅。分成两张纯粹是为了别让类型
  // 检查器在一个几十条的大字面量上卡死，和上面那几张表一个道理。

  private static let chainsA: [String: CoinSpec] = [
    // Zcash：一个厚实的 Z。
    "ZEC": CoinSpec(from: "#F4C95D", to: "#B8860B", mark: fill([
      "M6.4 4.6h11.2v3L11.2 16.4h6.4v3H6.4v-3l6.4-8.8H6.4z"])),
    // LSK：Lisk 盾形轮廓，中间一颗菱心
    "LSK": CoinSpec(from: "#7FB2F0", to: "#1F4E9A", mark: .parts([
      Part(d: [
        "M12 4l6.4 7L12 20l-6.4-9z"
      ], stroke: 2),
      Part(d: [
        "M12 8.8l2.8 3.2L12 15.8l-2.8-3.8z"
      ], stroke: nil)
    ])),
    // HYPE：Hyperliquid 两道液面波
    "HYPE": CoinSpec(from: "#9CF5DF", to: "#2FB59A", mark: stroke([
      "M4.2 9.6c2.6-3.4 5.2-3.4 7.8 0s5.2 3.4 7.8 0",
      "M4.2 15.4c2.6-3.4 5.2-3.4 7.8 0s5.2 3.4 7.8 0"
    ], 2.1)),
    // NEAR：NEAR 的斜折线 N
    "NEAR": CoinSpec(from: "#CBD2DA", to: "#3A424D", mark: stroke([
      "M6.6 18V6l10.8 12V6"
    ], 2.4)),
    // Ethena：两道并排斜下来的柱。
    "ENA": CoinSpec(from: "#8A98F5", to: "#3B4CC0", mark: fill([
      "M8.8 3.6h4.2L11 20.4H6.8z",
      "M16.6 3.6h4.2l-2 16.8h-4.2z"])),
    // Harmony：四枚圆扣成一圈。
    "ONE": CoinSpec(from: "#6FD8F2", to: "#1E8FB5", mark: fill([
      "M12 3.2a3.1 3.1 0 1 1 0 6.2 3.1 3.1 0 0 1 0-6.2z",
      "M12 14.6a3.1 3.1 0 1 1 0 6.2 3.1 3.1 0 0 1 0-6.2z",
      "M6.3 8.9a3.1 3.1 0 1 1 0 6.2 3.1 3.1 0 0 1 0-6.2z",
      "M17.7 8.9a3.1 3.1 0 1 1 0 6.2 3.1 3.1 0 0 1 0-6.2z"])),
    // PUMP：pump.fun 那粒斜放的胶囊
    "PUMP": CoinSpec(from: "#7CEBB0", to: "#1FA36A", mark: stroke([
      "M5.8 13.6l7.8-7.8a3.3 3.3 0 0 1 4.6 4.6l-7.8 7.8a3.3 3.3 0 0 1-4.6-4.6z",
      "M9.7 9.7l4.6 4.6"
    ], 2)),
    // DASH：Dash 的 D 加一横
    "DASH": CoinSpec(from: "#6CBCF2", to: "#1C75BC", mark: stroke([
      "M6.4 6.8h7.2a5.2 5.2 0 0 1 0 10.4H6.4",
      "M4.2 12h8.4"
    ], 2.2)),
    // Worldcoin：那颗虹膜球，横着两道扫描带。
    "WLD": CoinSpec(from: "#CFD4DA", to: "#2B2F35", mark: fill([
      "M12 4.2a7.8 7.8 0 1 1 0 15.6 7.8 7.8 0 0 1 0-15.6zM5.6 8.8v2.4h12.8v-2.4zM5.6 12.8v2.4h12.8v-2.4z"])),
    // AAVE：Aave 的小幽灵
    "AAVE": CoinSpec(from: "#9FD6DF", to: "#8A3E9E", mark: .parts([
      Part(d: [
        "M12 4.4c-3.8 0-6.4 2.8-6.4 6.6v8.4l2.1-1.6 2.15 1.6L12 17.8l2.15 1.6 2.15-1.6 2.1 1.6V11c0-3.8-2.6-6.6-6.4-6.6z"
      ], stroke: 1.9),
      Part(d: [
        "M9.6 9.6a1.2 1.2 0 1 1 0 2.4 1.2 1.2 0 0 1 0-2.4z",
        "M14.4 9.6a1.2 1.2 0 1 1 0 2.4 1.2 1.2 0 0 1 0-2.4z"
      ], stroke: nil)
    ])),
    // FIL：Filecoin 的 f，两道横杠
    "FIL": CoinSpec(from: "#7ED6F2", to: "#0B7FD6", mark: stroke([
      "M15 5.2c-3.2-.6-4.6 1.4-5 4.4L8.6 19",
      "M6.4 10.6h9.8",
      "M5.8 14.2h9.6"
    ], 2.1)),
    // TAO：Bittensor 的希腊字母 τ
    "TAO": CoinSpec(from: "#D3D7DD", to: "#2F343B", mark: stroke([
      "M5.8 8.4h12.4",
      "M11.6 8.4v6.6c0 2.2 1.3 3.2 3.6 2.9"
    ], 2.3)),
    // TRUMP：那顶棒球帽
    "TRUMP": CoinSpec(from: "#F2C562", to: "#1E3A8A", mark: stroke([
      "M6.6 14.6V12a5.4 5.4 0 0 1 10.8 0v2.6",
      "M4 14.6h16v2.6H4z"
    ], 2)),
    // Ondo 做代币化资产：三条逐级收窄的资产条。
    "ONDO": CoinSpec(from: "#BAC5EA", to: "#1C2E6B", mark: fill([
      "M4.8 6.2h14.4v2.8H4.8z",
      "M4.8 10.6h9.6v2.8H4.8z",
      "M4.8 15h4.8v2.8H4.8z"])),
    // XLM：Stellar 的弧加两道斜线
    "XLM": CoinSpec(from: "#CBD2DB", to: "#2A3139", mark: stroke([
      "M17.6 8.6a6.6 6.6 0 1 1-1.6-2",
      "M4.2 15.6l15.6-8.2",
      "M4.2 19.2l15.6-8.2"
    ], 2)),
    // Travala 做旅行预订：一只纸飞机。
    "AVA": CoinSpec(from: "#F5D26A", to: "#C9861E", mark: fill([
      "M3.4 11.6l17.2-7-4.4 15.8-4.2-5.4 5.8-8.2-7.2 6.4z"])),
    // IOST：两枚实心尖角，一层层往前推。
    "IOST": CoinSpec(from: "#7FA6F0", to: "#2C6DE6", mark: fill([
      "M4.6 5H8l5.4 7-5.4 7H4.6l5.4-7z",
      "M10.8 5h3.4l5.4 7-5.4 7h-3.4l5.4-7z"])),
    // 比特币现金：一个装满的区块，中间压着一枚币。
    "BCH": CoinSpec(from: "#9EDC72", to: "#2F7A2E", mark: fill([
      "M3.6 8.6h16.8v10.8H3.6zM12 11.2a2.8 2.8 0 1 0 0 5.6 2.8 2.8 0 0 0 0-5.6z"])),
    // ASTER：一枚星号
    "ASTER": CoinSpec(from: "#F2D480", to: "#C58A18", mark: stroke([
      "M12 4.8v14.4",
      "M5.8 8.4l12.4 7.2",
      "M18.2 8.4L5.8 15.6"
    ], 2.2)),
    // INJ：Injective 两道旋弧
    "INJ": CoinSpec(from: "#8BDCF2", to: "#0A7BC4", mark: stroke([
      "M6.6 8.6c2.8-3 6.4-3 9 0s2.8 6.4 0 9.2",
      "M17.4 15.4c-2.8 3-6.4 3-9 0s-2.8-6.4 0-9.2"
    ], 2)),
    // Pudgy Penguins：一只实心的胖企鹅，两只脚叉在外面。
    "PENGU": CoinSpec(from: "#A6D4F7", to: "#2F6EC7", mark: fill([
      "M12 3.4c3.3 0 5.6 3.3 5.6 7.8s-2.5 7-5.6 7-5.6-2.5-5.6-7 2.3-7.8 5.6-7.8z",
      "M6.2 18.4h4.6l-1.2 2.6H4.4z",
      "M17.8 18.4h-4.6l1.2 2.6h5.4z"])),
    // 门罗：一道折起来的山脊。
    "XMR": CoinSpec(from: "#F5A96B", to: "#C24A12", mark: fill(["M3 18.8L7.4 9.4l3 5.2L14.2 7.8 21 18.8z"])),
    // Saga：一面挂在旗杆上的燕尾旗。
    "SAGA": CoinSpec(from: "#DCCBB0", to: "#8A6A46", mark: .parts([
      Part(d: ["M6.4 3.8v16.4"], stroke: 2.4),
      Part(d: ["M7.6 4.8h11.8l-3.4 4 3.4 4H7.6z"], stroke: nil)])),
    // SHIB：柴犬：两只耳朵、脸、眼睛
    "SHIB": CoinSpec(from: "#F5B75A", to: "#D4522A", mark: .parts([
      Part(d: [
        "M6 5.6l2.6 3.2h6.8L18 5.6v6c0 3.8-2.6 6.6-6 6.6s-6-2.8-6-6.6z"
      ], stroke: 1.9),
      Part(d: [
        "M9.6 11a1.1 1.1 0 1 1 0 2.2 1.1 1.1 0 0 1 0-2.2z",
        "M14.4 11a1.1 1.1 0 1 1 0 2.2 1.1 1.1 0 0 1 0-2.2z",
        "M11 14.6h2l-1 1.4z"
      ], stroke: nil)
    ])),
    // WIF：戴帽子的狗：帽子实心，脸描边
    "WIF": CoinSpec(from: "#CFAB86", to: "#7A4E2A", mark: .parts([
      Part(d: [
        "M8.4 4.6h7.2L17 8.6H7z",
        "M5.4 8.6h13.2v2H5.4z"
      ], stroke: nil),
      Part(d: [
        "M12 11.2a5.2 5.2 0 0 1 5.2 5.2v2.6H6.8v-2.6a5.2 5.2 0 0 1 5.2-5.2z"
      ], stroke: 1.9),
      Part(d: [
        "M10.2 14.4a1 1 0 1 1 0 2 1 1 0 0 1 0-2z",
        "M13.8 14.4a1 1 0 1 1 0 2 1 1 0 0 1 0-2z"
      ], stroke: nil)
    ])),
    // Bonk 是条狗：一只爪印。
    "BONK": CoinSpec(from: "#F7B24E", to: "#E8532B", mark: fill([
      "M7 15.4a5 4.4 0 1 0 10 0 5 4.4 0 1 0-10 0z",
      "M4.4 8.2a2.2 2.2 0 1 0 4.4 0 2.2 2.2 0 1 0-4.4 0z",
      "M9.8 6a2.2 2.2 0 1 0 4.4 0 2.2 2.2 0 1 0-4.4 0z",
      "M15.2 8.2a2.2 2.2 0 1 0 4.4 0 2.2 2.2 0 1 0-4.4 0z"])),
  ]

  // ---------------------------------------------------------------- 链与代币（下半）

  private static let chainsB: [String: CoinSpec] = [
    // SEI：Sei 的 S 形涡
    "SEI": CoinSpec(from: "#E38A94", to: "#8F2233", mark: stroke([
      "M16.4 7.4c-1.4-1.8-5.6-1.8-6.4.6s3.4 3 5.2 4.2 2.4 4-.8 5.2-6-.6-7.2-2.4"
    ], 2.1)),
    // Celestia 只做底下那层数据可用性，执行留给别人：一弯月牙，缺的那一半就是它不做的部分。
    // 原来是四块方砖拼的格子，和微软那面窗、黑石那三块方同一个骨架，18px 下分不出来。
    "TIA": CoinSpec(from: "#C9B6F5", to: "#6E4CD6", mark: fill([
      "M12 3.6a8.4 8.4 0 1 1 0 16.8 8.4 8.4 0 1 1 0-16.8z"
        + "M16.6 1.6a7.8 7.8 0 1 0 0 15.6 7.8 7.8 0 1 0 0-15.6z"])),
    // JUP：带环的行星
    "JUP": CoinSpec(from: "#8FE5C0", to: "#1F9B72", mark: stroke([
      "M12 6.6a5.4 5.4 0 1 1 0 10.8 5.4 5.4 0 0 1 0-10.8z",
      "M3.4 15.2C8.2 9.4 16 7.2 20.8 8.4"
    ], 2)),
    // Lido 把质押做成液态：两滴液体。
    "LDO": CoinSpec(from: "#F0A6CD", to: "#B5326F", mark: fill([
      "M8 6c2.7 3.3 4.1 5.5 4.1 7.2a4.1 4.1 0 0 1-8.2 0C3.9 11.5 5.3 9.3 8 6z",
      "M16 9.8c2.7 3.3 4.1 5.5 4.1 7.2a4.1 4.1 0 0 1-8.2 0c0-1.7 1.4-3.9 4.1-7.2z"])),
    // Cosmos：一颗原子核，外面三粒电子。
    "ATOM": CoinSpec(from: "#B8B5E8", to: "#3F3D8C", mark: fill([
      "M12 9.2a2.9 2.9 0 1 1 0 5.8 2.9 2.9 0 0 1 0-5.8z",
      "M12 2.8a2.2 2.2 0 1 1 0 4.4 2.2 2.2 0 0 1 0-4.4z",
      "M5.2 15.4a2.2 2.2 0 1 1 0 4.4 2.2 2.2 0 0 1 0-4.4z",
      "M18.8 15.4a2.2 2.2 0 1 1 0 4.4 2.2 2.2 0 0 1 0-4.4z"])),
    // Polygon：两块错开咬合的多边形。
    "POL": CoinSpec(from: "#C8A5F5", to: "#7B3FE4", mark: fill([
      "M8.4 4.8l3.6 2.1v4.2l-3.6 2.1-3.6-2.1V6.9z",
      "M15.6 10.8l3.6 2.1v4.2l-3.6 2.1-3.6-2.1v-4.2z"])),
    // Polygon 的旧代号：两块错开咬合的多边形。
    "MATIC": CoinSpec(from: "#C8A5F5", to: "#7B3FE4", mark: fill([
      "M8.4 4.8l3.6 2.1v4.2l-3.6 2.1-3.6-2.1V6.9z",
      "M15.6 10.8l3.6 2.1v4.2l-3.6 2.1-3.6-2.1v-4.2z"])),
    // Notcoin：一块方板，一枚硬币压在角上。
    "NOT": CoinSpec(from: "#D5D9E0", to: "#2A2E35", mark: fill([
      "M4.6 4.6h10.2v10.2H4.6z",
      "M14.6 10.2a4.9 4.9 0 1 1 0 9.8 4.9 4.9 0 0 1 0-9.8z"])),
    // ETC：以太坊那颗钻石，描边、绿的
    "ETC": CoinSpec(from: "#9BD8A0", to: "#2E8B57", mark: stroke([
      "M12 3l5.6 9.1-5.6 3.3-5.6-3.3z",
      "M6.4 13.9L12 21l5.6-7.1"
    ], 1.9)),
    // Hedera：一枚圆盘压在一道长横杠上。
    "HBAR": CoinSpec(from: "#C5CAD1", to: "#25292E", mark: fill([
      "M12 3.8a5.4 5.4 0 1 1 0 10.8 5.4 5.4 0 0 1 0-10.8z",
      "M3 16.6h18v3.4H3z"])),
    // ICP：无穷环
    "ICP": CoinSpec(from: "#E9A7E0", to: "#6A2FBE", mark: stroke([
      "M7 15.5c-2.4 0-3.6-1.6-3.6-3.5S4.6 8.5 7 8.5c3.4 0 6.6 7 10 7 2.4 0 3.6-1.6 3.6-3.5S19.4 8.5 17 8.5c-3.4 0-6.6 7-10 7z"
    ], 2)),
    // Render：一块显卡，底下伸出散热脚。
    "RENDER": CoinSpec(from: "#E9A0A0", to: "#B22B2B", mark: fill([
      "M4 4.6h16a1.6 1.6 0 0 1 1.6 1.6v5.4a1.6 1.6 0 0 1-1.6 1.6H4a1.6 1.6 0 0 1-1.6-1.6V6.2A1.6 1.6 0 0 1 4 4.6z",
      "M5.4 14.4h3v4.2h-3z",
      "M10.5 14.4h3v4.2h-3z",
      "M15.6 14.4h3v4.2h-3z"])),
    // Fetch.ai 的代理是替你跑腿的：一辆小货车——一只货厢加一个斜风挡的车头，底下两只轮子。
    // 全表只有它长轮子，18px 上底边那两个圆鼓包就是认出它的地方。
    // 原来是三点连成的三角网，那个 A 形骨架和雪崩自己的商标重了；中途试过斜骨头（糊成两粒斜排的点，
    // 撞 Polygon）、张口的信封（顶上开口的方块，撞应用材料那道沟槽）、马蹄磁铁（那是美国稀土的标），都退掉了。
    "FET": CoinSpec(from: "#9CC7F5", to: "#2D63C8", mark: fill([
      "M3.4 6.6h9.6v9H3.4z",
      "M13 9.6h3.6l3.6 4v2H13z",
      "M7 14.7a2.3 2.3 0 1 1 0 4.6 2.3 2.3 0 1 1 0-4.6z",
      "M16.6 14.7a2.3 2.3 0 1 1 0 4.6 2.3 2.3 0 1 1 0-4.6z"])),
    // STX：Stacks 两横夹两个 V
    "STX": CoinSpec(from: "#B49CF0", to: "#4A3AD6", mark: stroke([
      "M5.6 9.6h12.8",
      "M5.6 14.4h12.8",
      "M8.4 4.6l3.6 5",
      "M15.6 4.6l-3.6 5",
      "M8.4 19.4l3.6-5",
      "M15.6 19.4l-3.6-5"
    ], 2)),
    // Algorand：两道叠起来的尖角。
    "ALGO": CoinSpec(from: "#CDD2D8", to: "#2C3138", mark: fill([
      "M12 2.8L20.6 11.4 17.4 14.6 12 9.2 6.6 14.6 3.4 11.4z",
      "M12 11.6L18.4 18 15.2 21.2 12 18 8.8 21.2 5.6 18z"])),
    // VET：VeChain 的 V 勾
    "VET": CoinSpec(from: "#86C6F2", to: "#1D62C6", mark: stroke([
      "M5.2 6.4l6.8 11.2 6.8-11.2",
      "M9 6.4l3 5.2"
    ], 2.2)),
    // Kaspa：三块菱形斜着连成一串。
    "KAS": CoinSpec(from: "#7FE0D0", to: "#1C9B8E", mark: fill([
      "M6.4 4.4l3.2 3.2-3.2 3.2-3.2-3.2z",
      "M12 8.8l3.2 3.2-3.2 3.2-3.2-3.2z",
      "M17.6 13.2l3.2 3.2-3.2 3.2-3.2-3.2z"])),
    // CRV：三条曲线
    "CRV": CoinSpec(from: "#F2C6A1", to: "#C86A2A", mark: stroke([
      "M4.8 18.4c3-10 5.4-12.2 14.4-13.2",
      "M4.8 18.4c5-4.2 8.4-4.2 14.4-2.2",
      "M8 18.4c2-5 5-7.2 11.2-8.2"
    ], 1.8)),
    // The Sandbox：上下两道边框夹着一只沙漏。
    "SAND": CoinSpec(from: "#8AD3F7", to: "#1E8FE0", mark: fill([
      "M5.6 3.4h12.8v2.2H5.6z",
      "M5.6 18.4h12.8v2.2H5.6z",
      "M7.4 6.2h9.2L12 12l4.6 5.8H7.4L12 12z"])),
    // AXS：Axie 的小脸：圆脸两耳
    "AXS": CoinSpec(from: "#B5C9F5", to: "#2E5BC7", mark: .parts([
      Part(d: [
        "M12 7.2a5.8 5.8 0 1 1 0 11.6 5.8 5.8 0 0 1 0-11.6z",
        "M7.6 8.6L6 4.6l4 2.2",
        "M16.4 8.6L18 4.6l-4 2.2"
      ], stroke: 1.9),
      Part(d: [
        "M9.8 12a1.1 1.1 0 1 1 0 2.2 1.1 1.1 0 0 1 0-2.2z",
        "M14.2 12a1.1 1.1 0 1 1 0 2.2 1.1 1.1 0 0 1 0-2.2z"
      ], stroke: nil)
    ])),
    // Gala Games：一颗能看见顶面的立方体。
    "GALA": CoinSpec(from: "#D2D2D6", to: "#4A4A52", mark: fill([
      "M12 3.4l8 4.6-8 4.6-8-4.6z",
      "M3.4 9.2l7.4 4.3v7.6l-7.4-4.3z",
      "M20.6 9.2l-7.4 4.3v7.6l7.4-4.3z"])),
    // Decentraland：一块地皮上立着一个方块。方块原来画成等轴立方体，
    // 那个六边形在 18px 上只剩一团圆，和 Hedera 的圆盘压横杠撞脸；改画正方，直角在小尺寸下活得下来。
    "MANA": CoinSpec(from: "#F5B0A0", to: "#C6392D", mark: fill([
      "M12 13.4l8.4 3.8-8.4 3.8-8.4-3.8z",
      "M7.6 4h8.8v9H7.6z"])),
    // Conflux 是树图：一座尖塔架在长墩上。
    "CFX": CoinSpec(from: "#CFCFD3", to: "#3B3B45", mark: fill([
      "M12 3.6L20 15H4z",
      "M4.6 17.6h14.8v3.2H4.6z"])),
    // Ordinals：一枚刻好的菱形铭牌，正中打一个孔。
    "ORDI": CoinSpec(from: "#F5B37A", to: "#C4511E", mark: fill([
      "M12 3.2l8.8 8.8-8.8 8.8L3.2 12zM12 9.2a2.9 2.9 0 1 0 0 5.8 2.9 2.9 0 0 0 0-5.8z"])),
    // ether.fi 把 ETH 质押出去，本金之外再生出一枚：两枚错开叠着的币，中间留一道透底的缝。
    // 原来是一枚实心六角螺母，六条边在 18px 上每条只占四五个像素，和 Circle 那枚实心圆一模一样。
    "ETHFI": CoinSpec(from: "#A79AF2", to: "#5638C6", mark: fill([
      "M14.6 3.6a5.4 5.4 0 1 1 0 10.8 5.4 5.4 0 1 1 0-10.8z",
      "M9.4 9.6a5.4 5.4 0 1 1 0 10.8 5.4 5.4 0 1 1 0-10.8z"
        + "M14.6 1.8a7.2 7.2 0 1 0 0 14.4 7.2 7.2 0 1 0 0-14.4z"])),
    // ETHW：以太坊上半颗钻石，底下一个 W
    "ETHW": CoinSpec(from: "#8D9BB8", to: "#3B4E73", mark: .parts([
      Part(d: [
        "M12 3l5.6 9.1-5.6 3.3-5.6-3.3z"
      ], stroke: nil),
      Part(d: [
        "M6.6 14.6l2.4 6 3-4.4 3 4.4 2.4-6"
      ], stroke: 1.9)
    ])),
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

