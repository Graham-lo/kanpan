import Foundation
import KanpanCore
import KanpanData

// 板块页全市场行情的落盘（Lane D3）。`SectorFeed.swift` 只管取数与聚合，
// 落到哪（`KanpanData.Paths`）、怎么编码单独放在这儿。
extension SectorFeed.Cache {
  /// `Library/Caches/kanpan/sector-quotes.json`；替身上游那份在 `sources/<分区>/` 子树里，
  /// 真身和替身的数各存各的，不混。整份覆盖写，只留最新一份。
  static let disk = SectorFeed.Cache(
    load: { partition in
      QuoteSnapshot.read(url(for: partition), limit: QuoteSnapshot.marketEntries)
    },
    save: { partition, tickers in
      QuoteSnapshot.write(tickers, to: url(for: partition), limit: QuoteSnapshot.marketEntries)
    })

  static func url(for partition: String?) -> URL {
    let paths = Paths.caches()
    return partition.map { paths.source($0).sectorQuotes } ?? paths.sectorQuotes
  }
}
