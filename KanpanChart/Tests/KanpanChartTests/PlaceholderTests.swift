import Testing

@testable import KanpanChart

@Suite("占位")
struct PlaceholderTests {
  @Test("包能编过") func builds() { #expect(true) }
}
