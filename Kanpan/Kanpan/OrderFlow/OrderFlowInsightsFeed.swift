import Foundation
import KanpanCore

/// Visible-page polling. Every run has an identity so late responses cannot cross symbols or reopening.
@MainActor
@Observable
final class OrderFlowInsightsFeed {
  struct Response: Sendable { var page: OrderFlowInsightsPage? = nil; var bars: [Bar]? = nil }
  typealias Fetch = @MainActor (String, String) async -> Response
  private(set) var page: OrderFlowInsightsPage?
  private(set) var bars: [Bar] = []
  private(set) var unavailable = false
  private(set) var loading = false
  private(set) var symbol: String?
  @ObservationIgnored private var running: String?
  @ObservationIgnored private var generation = UUID()
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private let pollInterval: Duration

  init(pollInterval: Duration = .seconds(25)) { self.pollInterval = pollInterval }

  func run(symbol: String?, base: String?, fetch: @escaping Fetch) {
    let key = symbol.flatMap { s in base.map { s + "|" + $0 } }
    guard key != running else { return }
    task?.cancel(); task = nil
    running = key; generation = UUID()
    guard let symbol, let base else { loading = false; return }
    if self.symbol != symbol { page = nil; bars = []; unavailable = false }
    self.symbol = symbol
    loading = page == nil
    let token = generation
    task = Task { [weak self] in
      while !Task.isCancelled {
        let response = await fetch(symbol, base)
        guard !Task.isCancelled, let self, self.generation == token else { return }
        if let page = response.page, page.base == base { self.page = page; self.unavailable = false }
        else { self.unavailable = true }
        // Clear old price evidence when a refresh fails: no stale window inference.
        self.bars = response.bars ?? []
        self.loading = false
        try? await Task.sleep(for: self.pollInterval)
      }
    }
  }
}
