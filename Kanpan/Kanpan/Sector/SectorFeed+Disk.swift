import Foundation
import KanpanCore
import KanpanData

// 板块页全市场行情的落盘（Lane D3）。只在 app 里接：`SectorFeed.swift` 同时被
// `Kanpan/Sector` 那个测试包编译，那边不依赖 KanpanData，所以落到哪、怎么编码放在这儿。
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
