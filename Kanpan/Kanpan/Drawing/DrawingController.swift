import KanpanChart
import KanpanCore
import SwiftUI

/// 画线态的外壳状态（§13 A7）。
///
/// 线本身归 `ChartView` 管（存在 `ChartState.drawings` 里，手势也在那边），这里只做
/// 三件外壳的事：底栏该亮哪一颗、提示条写什么、以及**按品种落盘**。
///
/// 为什么不把线放进这个对象：视野和线都得跟着手指每帧变，穿一趟 SwiftUI 的 diff 太贵
/// ——和 `ChartHost` 里「视野归图自己管」是同一个理由。这里只在事情发生之后被叫一次。
@MainActor
final class DrawingController: ObservableObject {
  /// 画线态开着（底栏露出来）。
  @Published private(set) var active = false
  @Published private(set) var tool: DrawingStore.Tool?
  /// 图区顶部那一行提示；`nil` 就不显示（§10.8）。
  @Published private(set) var hint: String?
  @Published private(set) var canDelete = false
  @Published private(set) var canUndo = false
  @Published private(set) var canRedo = false
  /// 这个品种画满 50 条了（A7.7）。外面弹一句就把它清掉。
  @Published var full = false

  private weak var chart: ChartView?
  private let store: DrawStore
  private var archive: DrawArchive
  private var symbol = ""

  init(store: DrawStore = .applicationSupport()) {
    self.store = store
    self.archive = store.load()
  }

  // MARK: - 接线

  /// `ChartHost` 造好视图之后把图交过来。同一张视图只接一次。
  func attach(_ view: ChartView) {
    guard chart !== view else { return }
    chart = view
    view.drawingInteractive = true
    view.onDrawingsChanged = { [weak self] items in self?.persist(items) }
    view.onDrawingStateChanged = { [weak self] in self?.sync() }
    view.onDrawingLimitReached = { [weak self] in self?.full = true }
    if !symbol.isEmpty { view.setDrawings(archive[symbol]) }
    sync()
  }

  /// 换品种：先把手上这份存了，再把新品种的读进图里（A7.7）。
  func focus(_ symbol: String) {
    guard symbol != self.symbol else { return }
    if let chart, !self.symbol.isEmpty { persist(chart.drawings) }
    self.symbol = symbol
    chart?.setDrawings(archive[symbol])
    sync()
  }

  // MARK: - 底栏

  /// 工具栏上的「画线」。再点一次收起来，收起时退出画线态（原型 `tDraw`）。
  func toggle() {
    active.toggle()
    if !active { chart?.endDrawing() }
    sync()
  }

  /// 选工具。点已经亮着的那颗就松开（原型 `data-draw` 的 onclick）。
  func pick(_ t: DrawingStore.Tool) {
    chart?.drawTool = chart?.drawTool == t ? nil : t
    sync()
  }

  func deleteSelected() {
    chart?.deleteSelectedDrawing()
    sync()
  }

  /// 「完成」：退出画线态，线全留着（A7.6）。
  func finish() {
    chart?.endDrawing()
    active = false
    sync()
  }

  func undo() {
    chart?.undoDrawing()
    sync()
  }

  func redo() {
    chart?.redoDrawing()
    sync()
  }

  // MARK: - 落盘

  /// 每次增删改都整份重写。画线全部加起来几 KB，比记增量省心，也不会写到一半断电。
  private func persist(_ items: [Drawing]) {
    guard !symbol.isEmpty else { return }
    archive[symbol] = items
    try? store.save(archive)
    sync()
  }

  private func sync() {
    guard let chart else { return }
    tool = chart.drawTool
    hint = active ? chart.drawHint : nil
    canDelete = chart.selectedDrawingID != nil
    canUndo = chart.canUndoDrawing
    canRedo = chart.canRedoDrawing
  }
}
