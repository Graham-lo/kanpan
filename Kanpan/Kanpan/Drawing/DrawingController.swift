import KanpanChart
import KanpanCore
import SwiftUI

@MainActor
final class DrawingController: ObservableObject {
  enum Panel: String, Identifiable { case objects, style; var id: String { rawValue } }
  /// 「绘图」工具面板开着没有。它没跟 `panel` 合在一起：横竖屏呈现方式不一样——
  /// 竖屏是半屏表单，横屏是贴边的一块卡片（见 `DrawingToolPicker`），而 `panel`
  /// 那两张（管理 / 样式）两种朝向下都是表单。
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
  @Published var picker = false
  private weak var chart: ChartView?
  private var store: DrawStore
  var onArchiveChange: ((DrawArchive) -> Void)?
  var storedArchive: DrawArchive { archive }
  private var archive: DrawArchive
  private var symbol = ""
  /// 上一条「刚落下、还没写字」的文字标注。只为了别把样式表反复弹出来：
  /// 用户点了取消之后 `panel` 回到 nil，`sync()` 又会跑一遍，没有这个记号就成了死循环。
  private var promptedNote: String?

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
    chart?.setDrawings(archive[symbol]); panel = nil; picker = false; sync()
  }
  func toggle() { active.toggle(); if !active { chart?.endDrawing(); picker = false }; sync() }
  /// 开「绘图」面板。入口只有一个笔形图标，横竖屏都是它。
  func openTools() { active = true; picker = true }
  /// 选工具：**幂等**。点已经选中的那个工具就是「还是它」，不是「取消它」。
  ///
  /// 原来是 `drawTool == t ? nil : t`。画完一条想接着画同一种线，很自然会再点一下工具，
  /// 结果把工具关掉了，之后点画布什么都不发生——实测连着画 14 次只成了 7 条，
  /// 失败的那 7 次没有任何反馈。要收手有「完成」和点空白处，不需要工具按钮兼任开关。
  ///
  /// `repeating` 就是「长按 = 连续画」（§2E3）：长按把连续画**打开**，同一把工具一直画到
  /// 手动收手。连续画关着时，画完一笔工具自己退回选择态（那是图自己的行为，见
  /// `ChartView+Drawing`）。
  ///
  /// **2026-09-19 改：轻点不再把「连续」关掉。** 这儿原来写的是「两条路都在这儿把开关
  /// 摆正，免得上一次长按留下的『连续』偷偷跟着下一次轻点走」——于是画线栏上那个
  /// 「连续」开关和短按工具成了两个打架的入口：用户明明自己把连续画打开了，随手点一下
  /// 工具它就自己关了（`kanpan-one-entry-per-action`，而且正是「同一个动作两次结果
  /// 不一样」）。现在这条按「用户用手改过的状态跟着人走」翻掉：开关的值只由用户自己
  /// 动它——画线栏的「连续」、工具表里的「连续画线」，以及长按工具这一下明确的「开」。
  func pick(_ t: DrawingStore.Tool, repeating: Bool = false) {
    active = true
    chart?.selectedDrawingID = nil   // 手上拿着工具就不该还选中着上一条线
    if repeating, !preferences.continuous {
      preferences.continuous = true
      savePreferences()
    }
    chart?.drawTool = t
    panel = nil; picker = false
    sync()
  }
  func select(_ id: String) { active = true; chart?.selectedDrawingID = id; sync() }
  func deleteSelected() { chart?.deleteSelectedDrawing(); sync() }
  func finish() { chart?.endDrawing(); active = false; panel = nil; picker = false; sync() }
  func undo() { chart?.undoDrawing(); sync() }
  func redo() { chart?.redoDrawing(); sync() }
  func duplicate() { chart?.duplicateSelectedDrawing(); sync() }
  func clear() { chart?.clearDrawings(); sync() }
  func hideAll() { chart?.setAllDrawingsHidden(!items.allSatisfy(\.hidden)); sync() }
  /// 改一条线。
  ///
  /// `promoteStyle` 只有在用户**真的在样式面板上动了**颜色 / 粗细 / 线型 / 填充 / 比例时
  /// 才为 true，这时才把这条线的样式提成该类工具以后的默认。以前这儿是无条件提升的：
  /// `toggleLock()` 只是给线上了个锁，却顺手把它当前的颜色粗细写成了「以后所有趋势线
  /// 的默认样式」——用户没做任何改样式的动作，下一条线却变了样，正是「同一个动作两次
  /// 结果不一样」。锁定、隐藏、移动、改端点一律不碰 `preferences.styles`
  /// （`toggleHidden` 本来就绕开了这个方法，那个写法是对的）。
  func update(_ item: Drawing, promoteStyle: Bool = false) {
    chart?.updateDrawing(item)
    if promoteStyle {
      preferences.styles[item.kind.rawValue] = DrawingStyle(item)
      savePreferences()
    }
    sync()
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
    // 空的文字标注在图上只是一句「点这里写字」的占位。落点即开样式表，
    // 省掉「落点 → 发现没字 → 自己去找样式」这三步。
    if let note = selected, note.kind.usesText, note.text.isEmpty, promptedNote != note.id {
      promptedNote = note.id
      panel = .style
    } else if selected == nil {
      promptedNote = nil
    }
  }
}
