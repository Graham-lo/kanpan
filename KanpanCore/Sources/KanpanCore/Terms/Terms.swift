import Foundation

/// 「大单与爆仓」三端共用的用词。**唯一一份在 `Terms/terms.json`**（三端共读：iOS 这里、
/// 手机网页与电脑网页 `Web/src/terms.ts`），改字只改那一个文件；界面代码里不再写这些字面量。
///
/// 模板里的 `{n}` `{t}` `{v}` `{h}` `{side}` 用 `fill` 填。
public enum BigTradeTerm: String, CaseIterable, Sendable {
  case title
  case listTitle
  case chartMarks
  case bigTrade
  case buy
  case sell
  case buyShort
  case sellShort
  case buyCount
  case sellCount
  case count
  case net
  case netBuy
  case netSell
  case todayNet
  case cumNet
  case barNet
  case maxSingle
  case trades
  case source
  case summary
  case currentBar
  case staleSince
  case noBigTrade
  case currentNoBigTrade
  case hourNoBigTrade
  case noTradeData
  case historyOnly
  case untracked
  case threshold
  case thresholdValue
  case hour
  case hours
  case today
  case day
  case recentBars
  case perBar
  case levels
  case levelsRange
  case wall
  case buyWall
  case sellWall
  case up
  case down
  case liq
  case longLiq
  case shortLiq
  case long
  case short
  case longMark
  case shortMark
  case noLiqToday
  case noLiqData
  case todayMaxLiq
  case spot
  case perp
  case delivery
  case contract
  case auto
  case step
  case collapse
  case yesterday
  case todayDay
  case now
  case open
  case statusLive
  case statusFilling
  case statusFilled
  case statusPartFilled
  case statusCancelled
  case statusLost
  case statusEnded
  case held
  case signA11y
  case barsA11y
  case liqDayA11y

  /// 这一项的字（没有占位符的直接用）。
  public var text: String { Terms.table["bigTrade"]?[rawValue] ?? rawValue }

  /// 填好占位符的字：`BigTradeTerm.buyCount.fill(["n": "12"])` →「买 12 笔」。
  public func fill(_ args: [String: String]) -> String {
    args.reduce(text) { $0.replacingOccurrences(of: "{" + $1.key + "}", with: $1.value) }
  }
}

/// 「分析」里自动画的那几样的用词，同在 `terms.json`（`analysis` 组；网页那边是 `AN`）。
public enum AnalysisTerm: String, CaseIterable, Sendable {
  /// 公允价值缺口。
  case fvg

  /// 这一项的字。
  public var text: String { Terms.table["analysis"]?[rawValue] ?? rawValue }
}

/// 首页「异动 · 榜单」与行情页上滑「盘口要点」的用词，同在 `terms.json`（`highlights` 组；手机网页读同一份）。
/// 接口只发枚举键，中文全在这一组；模板占位符用 `fill` 填。
public enum HighlightTerm: String, CaseIterable, Sendable {
  case home
  case moves
  case board
  case `all`
  case catBook
  case catOi
  case catFunding
  case catMove
  case moveUp
  case moveDown
  case moveVol
  case segChange
  case segOi
  case segSectors
  case rankGainers
  case rankLosers
  case rankOiUp
  case rankOiDown
  case favScope
  case hotScope
  case guestHint
  case updatedAt
  case stoppedAt
  case calmTitle
  case calmSub
  case newMoves
  case offline
  case failed
  case retry
  case noRows
  case addFavorite
  case justNow
  case minutesAgo
  case hoursAgo
  case boardOi
  case boardGainers
  case boardLosers
  case collapse
  case win1h
  case win4h
  case win24h
  case entry
  case title
  case staleSince
  case flow
  case flowCaption
  case netTaker
  case price
  case oi
  case w15m
  case w1h
  case w4h
  case w24h
  case wRange
  case diverge
  case flowLine
  case levels
  case wall
  case fill
  case liq
  case now
  case dist
  case distPrice
  case `range`
  case rangeAge
  case rangeEdges
  case rangeLowEdge
  case rangeHighEdge
  case above
  case below
  case buyZone
  case sellZone
  case wallMeta
  case fillMeta
  case liqMeta
  case tests
  case heldFor
  case minutes
  case hours
  case days
  case fillBuySell
  case touch
  case overlap
  case unbroken
  case atPrice
  case wallLive
  case wallReducing
  case wallBroken
  case back
  case refDayHigh
  case refDayLow
  case refPrevDayHigh
  case refPrevDayLow
  case refVwap
  case refRangeHigh
  case refRangeLow
  case position
  case positionCaption
  case oi1h
  case funding
  case spotPremium
  case oiUpPxUp
  case oiDownPxUp
  case oiUpPxDown
  case oiDownPxDown
  case pctile
  case events
  case eventsCaption
  case buyWall
  case sellWall
  case wallEaten
  case wallCancel
  case takerBuy
  case takerSell
  case longLiq
  case shortLiq
  case oi5m
  case broken
  case pricePct
  case oiPct
  case window4h
  case untracked
  case quiet
  case observing

  /// 这一项的字。
  public var text: String { Terms.table["highlights"]?[rawValue] ?? rawValue }

  /// 填好占位符的字：`HighlightTerm.tests.fill(["n": "2"])` →「测 2 次」。
  public func fill(_ args: [String: String]) -> String {
    args.reduce(text) { $0.replacingOccurrences(of: "{" + $1.key + "}", with: $1.value) }
  }
}

/// 包里那份 `terms.json`，解一次、常驻。
public enum Terms {
  static var url: URL? { Bundle.module.url(forResource: "terms", withExtension: "json") }

  /// 资源缺了或坏了是打包事故：调试包当场断言，发布包退回键名，不崩。
  static let table: [String: [String: String]] = {
    guard let url, let data = try? Data(contentsOf: url),
          let raw = try? JSONDecoder().decode([String: [String: String]].self, from: data)
    else {
      assertionFailure("KanpanCore 资源 terms.json 缺失或解不出来")
      return [:]
    }
    return raw
  }()
}
