import KanpanChart
import KanpanCore
import SwiftUI

@MainActor
final class DrawingController: ObservableObject {
  enum Panel: String, Identifiable { case tools, objects, style; var id: String { rawValue } }
  @Published private(set) var active = false
  @Published private(set) var tool: DrawingStore.Tool?
  @Published private(set) var hint: String?
  @Published private(set) var canDelete = false
  @Published private(set) var canUndo = false
  @Published private(set) var canRedo = false
  @Published private(set) var items: [Drawing] = []
  @Published private(set) var selected: Drawing?
  @Published private(set) var preferences: DrawingPreferences
  @Published var full = false
  @Published var notice: String?
  @Published var panel: Panel?
  private weak var chart: ChartView?
  private var store: DrawStore
  var onArchiveChange: ((DrawArchive) -> Void)?
  var storedArchive: DrawArchive { archive }
  private var archive: DrawArchive
  private var symbol = ""

  init(store: DrawStore = .applicationSupport()) {
    self.store = store
    var problem: String?
    do { archive = try store.read() }
    catch { archive = DrawArchive(); problem = "暂时无法读取画线，原存档已保留。" }
    preferences = archive.preferences
    notice = problem
  }
  func attach(_ view: ChartView) {
    guard chart !== view else { return }
    chart?.onDrawingsChanged = nil; chart?.onDrawingStateChanged = nil
    chart?.endDrawing()
    chart = view; view.drawingInteractive = true
    view.onDrawingsChanged = { [weak self] items in self?.persist(items) }
    view.onDrawingStateChanged = { [weak self] in self?.sync() }
    view.onDrawingLimitReached = { [weak self] in self?.full = true }
    applyPreferences()
    if !symbol.isEmpty { view.setDrawings(archive[symbol]) }
    sync()
  }
  func focus(_ symbol: String) {
    guard symbol != self.symbol || chart?.drawings != archive[symbol] && chart?.drawings.isEmpty == true else { return }
    // Every completed edit is already saved. Never write the incoming chart into the outgoing key.
    self.symbol = symbol
    chart?.setDrawings(archive[symbol]); panel = nil; sync()
  }
  func toggle() { active.toggle(); if !active { chart?.endDrawing() }; sync() }
  /// 选工具：**幂等**。点已经选中的那个工具就是「还是它」，不是「取消它」。
  ///
  /// 原来是 `drawTool == t ? nil : t`。画完一条想接着画同一种线，很自然会再点一下工具，
  /// 结果把工具关掉了，之后点画布什么都不发生——实测连着画 14 次只成了 7 条，
  /// 失败的那 7 次没有任何反馈。要收手有「完成」和点空白处，不需要工具按钮兼任开关。
  func pick(_ t: DrawingStore.Tool) {
    active = true
    chart?.selectedDrawingID = nil   // 手上拿着工具就不该还选中着上一条线
    chart?.drawTool = t
    panel = nil
    sync()
  }
  func select(_ id: String) { active = true; chart?.selectedDrawingID = id; sync() }
  func deleteSelected() { chart?.deleteSelectedDrawing(); sync() }
  func finish() { chart?.endDrawing(); active = false; panel = nil; sync() }
  func undo() { chart?.undoDrawing(); sync() }
  func redo() { chart?.redoDrawing(); sync() }
  func duplicate() { chart?.duplicateSelectedDrawing(); sync() }
  func clear() { chart?.clearDrawings(); sync() }
  func hideAll() { chart?.setAllDrawingsHidden(!items.allSatisfy(\.hidden)); sync() }
  func update(_ item: Drawing) {
    chart?.updateDrawing(item)
    preferences.styles[item.kind.rawValue] = DrawingStyle(item)
    savePreferences(); sync()
  }
  func toggleLock() { if var item = selected { item.locked.toggle(); update(item) } }
  func toggleHidden(_ item: Drawing) { var next = item; next.hidden.toggle(); chart?.updateDrawing(next); sync() }
  func toggleFavorite(_ kind: Drawing.Kind) {
    if preferences.favorites.contains(kind) { preferences.favorites.removeAll { $0 == kind } }
    else { preferences.favorites.append(kind) }
    savePreferences()
  }
  func toggleMagnet() { preferences.magnet.toggle(); savePreferences() }
  func toggleContinuous() { preferences.continuous.toggle(); savePreferences() }
  private func applyPreferences() {
    chart?.drawingMagnet = preferences.magnet
    chart?.continuousDrawing = preferences.continuous
    chart?.drawingStyles = preferences.styles
  }
  private func savePreferences() { archive.preferences = preferences; write(); applyPreferences() }
  private func persist(_ items: [Drawing]) {
    guard !symbol.isEmpty else { return }
    archive[symbol] = items; write(); sync()
  }
  private func write() {
    do { try store.save(archive); onArchiveChange?(archive) }
    catch { notice = "画线未能保存，原存档已保留。请检查设备存储空间。" }
  }
  func useStorage(_ store: DrawStore, archive: DrawArchive) {
    finish(); self.store = store; self.archive = archive; preferences = archive.preferences
    chart?.setDrawings(archive[symbol]); applyPreferences(); sync()
  }
  func applySynced(_ value: DrawArchive) throws {
    guard value != archive else { return }
    try store.save(value); archive = value; preferences = value.preferences
    chart?.setDrawings(value[symbol]); applyPreferences(); sync()
  }
  private func sync() {
    guard let chart else { return }
    tool = chart.drawTool; hint = active ? chart.drawHint : nil
    items = chart.drawings; selected = items.first { $0.id == chart.selectedDrawingID }
    if selected != nil { active = true }
    canDelete = selected != nil; canUndo = chart.canUndoDrawing; canRedo = chart.canRedoDrawing
  }
}
