import Foundation

/// UI 种子保留旧版裸代号；定位符使用迁移后的完整身份。
func testInstrumentKey(_ symbol: String) -> String {
  symbol.contains("/") ? symbol : "binance/usd_m/" + symbol.uppercased()
}
