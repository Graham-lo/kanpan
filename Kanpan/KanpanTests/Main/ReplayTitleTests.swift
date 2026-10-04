import Testing
import KanpanCore
@testable import Kanpan

// 交易回放 / 笔记重温页头里的品种名（2026-10-04 G 线走查）：原来直接摆交易所代号，
// 币安的代号没有分隔符，标题成了「回放 · BTCUSDT · 1 小时」。现在和顶栏、提醒总表一个写法。
@Suite("回放页头的品种名写成 BTC/USDT")
struct ReplayTitleTests {
  @Test("币安裸代号、规范键、Coinbase 带横杠的代号都拆成「基础/计价」")
  func pairTitle() {
    #expect(ReplayHeaderView.pairTitle("BTCUSDT") == "BTC/USDT")
    #expect(ReplayHeaderView.pairTitle(InstrumentID.canonical("ETHUSDT")) == "ETH/USDT")
    #expect(ReplayHeaderView.pairTitle("1000SHIBUSDT") == "1000SHIB/USDT")
    #expect(ReplayHeaderView.pairTitle("coinbase/spot/BTC-USD") == "BTC/USD")
    #expect(!ReplayHeaderView.pairTitle("SOLUSDT").contains("SOLUSDT"))
    // 图还没装上（没有品种）时不凭空写一个「/USDT」。
    #expect(ReplayHeaderView.pairTitle("") == "")
  }
}
