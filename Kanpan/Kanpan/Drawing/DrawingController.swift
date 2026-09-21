import KanpanChart
import KanpanCore
import SwiftUI

@MainActor
final class DrawingController: ObservableObject {
  enum Panel: String, Identifiable { case objects, style; var id: String { rawValue } }
  /// 「绘图」工具面板开着没有。它没跟 `panel` 合在一起：横竖屏呈现方式不一样——
  /// 竖屏是半屏表单，横屏是贴边的一块卡片（见 `DrawingToolPicker`），而 `panel`
  /// 那两张（管理 / 样式）两种朝向下都是表单。
  @Published private(set) var active = false { didSet { chart?.drawingEditable = active } }
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
  @Published private(set) var previewing: ShareItem?
  private var guest: [Drawing] = []
  private var guestSymbol: String?
  private weak var chart: ChartView?
  private var store: DrawStore
  var onArchiveChange: ((DrawArchive) -> Void)?
  /// 本机把画线的几何改动过了就喊一声——画、拖、改端点、删，都算。
  ///
  /// 提醒模块接着它对账（`AlertStore.reconcile`）：线被挪过就按**同一个提醒 id**
  /// 重算 `lines` 并把 `armedAt` 拨到现在，线没了就把它的提醒一起删掉。
  /// 和 `onArchiveChange` 分开是因为那个是账号桥的同步捕获，两件事互不该等对方。
  ///
  /// **只在本机改出来的那一下响**（`write()`）。换账号（`useStorage`）和云端推下来
  /// （`publishSynced`）都不响：那两条路上画线与提醒是两摊分别换的货，谁先谁后不定，
  /// 拿新的画线去对老的提醒会当场把人家的提醒误删；而云端那一份本来就已经是
  /// 另一台设备对过账的结果，不需要这台再对一遍。
  var onGeometryChanged: ((DrawArchive) -> Void)?
  /// 记下「上次用的是哪把工具」。宿主接到 `Prefs.lastDrawTool`（随账号同步）。
  ///
  /// 它**只**用来在工具面板上把那把工具预选高亮，不是「此刻正举着笔」——
  /// 待画状态归图自己（`ChartView+Drawing`），换品种照样清掉。
  var onPickTool: ((DrawingStore.Tool) -> Void)?
  var storedArchive: DrawArchive { archive }
  private var archive: DrawArchive
  private var symbol = ""
  /// 每个品种的撤销栈，按品种分开存。
  ///
  /// 撤销栈原本只活在 `ChartView` 那个实例上，而图是随时会被重建的：竖屏切一次自选页、
  /// 进一次横屏画线工作台，`ChartBox.makeUIView` 就造一个全新的 `ChartView`——画完两笔
  /// 回来，两笔还在图上，「撤销」却是灰的（任务 3）。控制器是 `MainScreen` 里唯一那个
  /// `@StateObject`，它活得过这些重建，栈就存在它这儿，图一接上来就接回去。
  ///
  /// **空栈不占格子**：一轮下来用户会路过几百个品种，没在上面画过线的不该留下任何东西。
  private var histories: [String: DrawHistory] = [:]
  /// 上一条「刚落下、还没写字」的文字标注。只为了别把样式表反复弹出来：
  /// 用户点了取消之后 `panel` 回到 nil，`sync()` 又会跑一遍，没有这个记号就成了死循环。
  private var promptedNote: String?
  /// 品种还没换过去时先记着，等 `focus` 把那个品种的线装进图里再选。
  private var pendingHighlight: (symbol: String, id: String)?

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
    // **第一件事就是把存着的那摞取出来**，一句代码都不能排在它前面。
    //
    // 接上一张新图之后，下面每一步都可能顺手喊一遍 `sync()`：`applyPreferences()` 里的
    // `drawingMagnet` / `continuousDrawing` 两个 setter 各自会 `drawingChanged()`，
    // `setDrawings` 也会。而 `sync()` 开头就 `rememberHistory()`——那时候 `chart` 已经是
    // 这张**还空着**的新图，于是它把「这个品种的撤销栈」当场写成空，格子被撤掉。
    // 等走到下面再去读 `histories[symbol]` 就只剩一摞空的：画两笔切到自选页再回来，
    // 线还在、「撤销」却是灰的——正是任务 3 要修的那个现象，只不过病根从
    // 「栈存在图身上」挪到了「栈刚存好就被新图抹了」。
    let resumed = symbol.isEmpty ? DrawHistory() : (histories[symbol] ?? DrawHistory())
    chart?.onDrawingsChanged = nil; chart?.onDrawingStateChanged = nil
    chart?.endDrawing()
    // 覆盖层一直在场（它还要画选中态、预览线和提醒铃铛），**收不收手**另算：
    // 不在画线态时点图就只是平移 / 十字光标，点中一条旧线不会把它选中。
    chart = view; view.drawingInteractive = true; view.drawingEditable = active
    view.onDrawingsChanged = { [weak self] items in self?.persist(items) }
    view.onDrawingStateChanged = { [weak self] in self?.sync() }
    view.onDrawingLimitReached = { [weak self] in self?.full = true }
    applyPreferences()
    if !symbol.isEmpty {
      // 顺序要紧：`setDrawings` 会把撤销栈清掉（它是「整批外部替换」的语义），
      // 所以灌完线再把上面取出来的那摞接回去。
      view.setDrawings(archive[symbol])
      view.drawingHistory = resumed
    }
    applyPreview()
    sync()
  }
  func focus(_ symbol: String) {
    guard symbol != self.symbol || chart?.drawings != archive[symbol] && chart?.drawings.isEmpty == true else {
      applyPreview(); applyPendingHighlight(); return
    }
    // Every completed edit is already saved. Never write the incoming chart into the outgoing key.
    // 走之前先把这张图上的栈收进**上一个**品种的格子（`sync()` 一路都在收，这儿是最后一手）。
    rememberHistory()
    self.symbol = symbol
    let resumed = histories[symbol] ?? DrawHistory()
    chart?.setDrawings(archive[symbol])
    chart?.drawingHistory = resumed
    panel = nil; picker = false; sync()
    applyPreview(); applyPendingHighlight()
  }

  func preview(_ item: ShareItem) {
    previewing = item
    preview(item.drawings, symbol: item.symbol)
  }
  func preview(_ guest: [Drawing], symbol: String) {
    finish()
    self.guest = guest; guestSymbol = symbol
    chart?.selectedDrawingID = nil
    applyPreview()
  }
  func endPreview() {
    previewing = nil; guest = []; guestSymbol = nil
    chart?.guestDrawings = []; chart?.ownDimmed = false
  }
  private func applyPreview() {
    let matching = guestSymbol == symbol
    chart?.guestDrawings = matching ? guest : []
    chart?.ownDimmed = matching
  }
  /// 一次留下整批线，一步撤销。容量不够时整批不写，已有存档不丢。
  @discardableResult
  func append(_ incoming: [Drawing], symbol: String) -> Bool {
    let before = archive[symbol]
    let known = Set(before.map(\.id))
    let added = incoming.filter { !known.contains($0.id) }
    guard added.allSatisfy(\.isValid), before.count + added.count <= DrawArchive.perSymbolLimit else {
      full = true; return false
    }
    guard !added.isEmpty else { return true }
    var history = (self.symbol == symbol ? chart?.drawingHistory : nil) ?? histories[symbol] ?? DrawHistory()
    history.commit(before: before)
    archive[symbol] = before + added
    write()
    if self.symbol == symbol {
      chart?.setDrawings(archive[symbol]); chart?.drawingHistory = history
      applyPreview(); sync()
    }
    histories[symbol] = history
    return true
  }

  /// 把某个品种上的某条线**指出来**：只高亮，不进画线工作台。
  ///
  /// 深链专用（点提醒的通知、从提醒列表点一行）。品种可能还在路上（`MainScreen`
  /// 刚把它交给行情模块），所以先记下来，等 `focus` 到那个品种再兑现。
  func highlight(drawingID: String, symbol: String) {
    pendingHighlight = (symbol, drawingID)
    applyPendingHighlight()
  }

  private func applyPendingHighlight() {
    guard let wanted = pendingHighlight, wanted.symbol == symbol, let chart else { return }
    guard chart.drawings.contains(where: { $0.id == wanted.id }) else { return }
    pendingHighlight = nil
    chart.selectedDrawingID = wanted.id
    sync()
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
    onPickTool?(t)
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
  /// 先落同步存档，再落正式文件。**顺序不能反。**
  ///
  /// 同步存档那一份里同时装着「新的本地值」和「那条待发操作」，它是「用户刚才
  /// 要的是什么」的权威副本；`draws.json` 只是渲染用的正式文件。两次写之间断电
  /// 的话，「新存档 + 旧 draws.json」下次启动能前向补回来；反过来的
  /// 「新 draws.json + 旧存档」补不回来——存档里既没有新值也没有待发操作，
  /// 下一次拉取会拿云端那份旧的把用户刚存的几何盖回去（B2）。
  private func write() {
    onArchiveChange?(archive)
    onGeometryChanged?(archive)
    do { try store.save(archive) }
    catch { notice = "画线未能保存，原存档已保留。请检查设备存储空间。" }
  }
  func useStorage(_ store: DrawStore, archive: DrawArchive) {
    endPreview(); finish(); self.store = store; self.archive = archive; preferences = archive.preferences
    // 换的是整个账号的存档：上一个账号的撤销栈撤回去就是别人的数据，一并丢掉。
    histories.removeAll()
    chart?.setDrawings(archive[symbol]); applyPreferences(); sync()
  }
  /// 三段式里的「落盘」那一段：只写文件，内存里可见的状态一个都不动。
  /// 这一步抛错时，界面上还是老样子，等于这一批整个没发生。
  func commitSynced(_ value: DrawArchive) throws {
    guard value != archive else { return }
    try store.save(value)
  }
  /// 三段式里的「发布」那一段：内存与界面换成刚落下去的那一版。
  ///
  /// **只有当前这个品种那一桶真的变了，才去动图。** 存档是所有品种共用的一份，
  /// 别的设备上给 ETH 画了一条线，推下来整份存档就不等了；从前这里无条件调
  /// `chart.setDrawings`，而那一句会把撤销栈、选中项、半截交互态全清掉——
  /// 人正在 BTC 上画，撤销突然就撤不回去了（A-07）。
  ///
  /// 桶没变时照样更新 `archive` 与偏好：那两样本来就该跟着云端走，
  /// 它们不碰图上的编辑历史。
  func publishSynced(_ value: DrawArchive) {
    guard value != archive else { return }
    // 判据搬去了 Core（`DrawArchive.bucketChanged`），这样它能被单测盖住——
    // 这条控制器没有任何壳测试包够得着（A.5 用例 8）。
    let changed = value.bucketChanged(from: archive, symbol: symbol)
    archive = value; preferences = value.preferences
    if changed { chart?.setDrawings(value[symbol]) }
    applyPreferences(); sync()
  }
  /// 把图上那摞撤销栈收进当前品种的格子。空栈就把格子撤掉。
  private func rememberHistory() {
    guard !symbol.isEmpty, let chart else { return }
    let stack = chart.drawingHistory
    histories[symbol] = (stack.canUndo || stack.canRedo) ? stack : nil
  }

  private func sync() {
    guard let chart else { return }
    // 每一次编辑最后都会走到这儿（`onDrawingStateChanged`），在这儿收栈就不会漏。
    rememberHistory()
    tool = chart.drawTool; hint = active ? chart.drawHint : nil
    items = chart.drawings; selected = items.first { $0.id == chart.selectedDrawingID }
    // **「选中」从来不开画线工作台。** 这儿原来有一句「选中了就 `active = true`」，
    // 理由写的是「正常情况下选中线只可能发生在用户正在画线的时候」——那个前提是错的：
    // 图上的画线手势从前一接上就开着，竖屏随手点中一条旧线也会选中它，于是
    // `MainScreen` 对 `active` 的 onChange 当场把屏幕转成横屏。深链高亮那条豁免
    // （`highlightedID`）只是给这条错规矩打的补丁，一并删掉了。
    //
    // 真正该开工作台的入口——`toggle()` / `openTools()` / `pick(_:)` / `select(_:)`——
    // 每一条都自己写着 `active = true`；图自己画完一笔之后的自动选中
    // （`placeDrawPoint` 的 `commit`）也只发生在已经 `active` 的时候。所以这一句是纯多余的。
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
