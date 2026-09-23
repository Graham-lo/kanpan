import Foundation
import KanpanCore

/// 已经钻进某个板块之后，这一帧的统计里却找不到它时该怎么办。
///
/// 为什么要单列一个判断（审查 C-01）：原来那一层是「找不到就 `pop()`」。可是
/// 「找不到」有两种完全不同的来由——**板块没了**，和**这一帧行情还没到**。后者在
/// 冷启动第一帧、刚换窗口、网络抖一下的时候都会出现，而把它当成「人按了返回」
/// 的后果是：用户正看着一个板块，数据回来之前就被悄悄送回板块列表，回来也回不去
/// （路由已经被 `removeLast` 掉了，没人会替他再压一层）。
///
/// 所以退栈要有**证据**：分类表是编译进包的静态表，它说没有才算没有；兜底桶是按
/// 行情现算的，它只能当正面证据（说有就是有），说没有不算数。整帧都算不出东西的
/// 时候更是谁也别信，留在原地等。
enum SectorDrillDecision: Equatable {
  /// 这一帧有它的统计，正常画品种列表。
  case show
  /// 没有，但也没有任何证据说它不在了——留在原地等下一帧，路由不动。
  case wait
  /// 目录确认它不在了，退回上一层。
  case pop

  /// - Parameters:
  ///   - hasStat: 这一帧的 `stats` 里有没有这个板块。
  ///   - catalogKnows: `SectorCatalog` 里还认不认这个 id。静态表，与行情无关。
  ///   - bucketKnows: 这一帧的兜底桶里有没有它。按行情现算，只作正面证据。
  ///   - snapshotHasStats: 这一帧整体算出东西来了没有。整帧皆空时缺谁都只是「还没到」。
  static func decide(hasStat: Bool, catalogKnows: Bool, bucketKnows: Bool,
                     snapshotHasStats: Bool) -> SectorDrillDecision {
    if hasStat { return .show }
    if catalogKnows || bucketKnows { return .wait }
    if !snapshotHasStats { return .wait }
    return .pop
  }

  /// 同上，直接问分类表与这一帧的兜底桶。界面层用这一条。
  static func decide(id: String, stats: [SectorStat], buckets: [SectorFallbackBucket]) -> SectorDrillDecision {
    decide(hasStat: stats.contains { $0.id == id },
           catalogKnows: SectorCatalog.sector(id: id) != nil,
           bucketKnows: buckets.contains { $0.id == id },
           snapshotHasStats: !stats.isEmpty)
  }

  /// 等的时候摆在屏上的那张空壳统计：只有名字和成员数，数值一律零。
  ///
  /// 为什么不是 `Color.clear`：等待期间人得有路可走。空壳走的是同一张品种列表，
  /// 头部的板块名和返回键都在，数据一到就被真的那份换掉，中间没有第二种排版。
  static func placeholder(id: String, market: SectorMarket,
                          buckets: [SectorFallbackBucket]) -> SectorStat {
    let def = SectorCatalog.sector(id: id)
    let bucket = buckets.first { $0.id == id }
    let members = def?.members ?? bucket?.members ?? []
    return SectorStat(id: id, name: def?.name ?? bucket?.name ?? id, market: market,
                      pct: 0, memberCount: 0, staticCount: members.count,
                      // 成交额是「没有」，不是 0：写 0 头部就会印出一句「成交额 0.00」。
                      quoteVolume: .nan, isFallback: def == nil)
  }
}
