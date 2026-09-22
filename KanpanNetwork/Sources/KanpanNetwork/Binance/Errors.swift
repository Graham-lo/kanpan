import Foundation

/// 币安这一支沿用的旧名字。错误本身是各家共用的 `UpstreamError`
/// （`Provider/UpstreamError.swift`），这里只留一个别名，让币安内部与老用例不必改名。
public typealias BinanceError = UpstreamError
