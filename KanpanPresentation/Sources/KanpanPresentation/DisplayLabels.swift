import KanpanCore

// 设置里几处档位给人看的名字。枚举本身（存档与同步的原值、算法）在 Core，
// 这里只管「界面上写什么」——Core 不再住中文文案（审查 24）。

extension TZChoice {
  /// 界面上第三档写「UTC+8」，不写「交易所」（审查 U13）：「UTC」和「交易所」并排摆着，
  /// 看起来像同一件事的两种叫法；写出偏移量，三档各是什么一眼就分得开。
  public var display: String {
    switch self {
    case .local: "本地"
    case .utc: "UTC"
    case .exchange: "UTC+8"
    }
  }
}

extension ChangeBasis {
  public var title: String {
    switch self {
    case .rolling24h: "24小时"
    case .shanghaiMidnight: "上海0点"
    case .utcMidnight: "上海8点 / UTC 0点"
    }
  }

  public var shortTitle: String {
    // 中文，不用 24H 这种英文缩写（`kanpan-ui-labels-are-chinese`）；`title` 那边
    // 一直写的是「24小时」，这儿跟上去，免得同一页上两种写法并排。
    switch self { case .rolling24h: "24小时涨跌幅"; case .shanghaiMidnight: "0点涨跌幅"; case .utcMidnight: "8点涨跌幅" }
  }
}

extension PriceMode {
  public var display: String {
    switch self {
    case .linear: "常规"
    case .log: "对数"
    case .percent: "百分比"
    }
  }
}
