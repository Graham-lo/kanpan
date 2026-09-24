import SwiftUI
import UIKit
import KanpanCore
import KanpanData
import KanpanNetwork

/// 自选分类页 ——「琉璃」。
///
/// 底是三团会慢慢漂的光，上面浮着玻璃：按钮是玻璃圆片，分类是玻璃胶囊，整张列表
/// 是一张玻璃纸。颜色一律从当前皮肤的种子推（见 `LiuliSkin`），View 里不写死
/// 十六进制——唯一的例外是浅色那组「天青·薄荷」光斑，那是浅色底下专配的一组冷光，
/// 不属于任何一套皮肤。
///
/// 这一页能做的事：切分类、删当前分类（只剩一类时不给删）、添加品种、排序、调整顺序
/// （长按拖动）、左滑「移到分类 / 取消自选」、长按看预览卡、进图表。
///
/// 2026-09-24 按「判了不做的不准收编」删掉了三样：新建分类、重命名分类（自建分组）、
/// 批量编辑（勾选多行 + 底部编辑条）。分类只剩按资产类型自动开的那几类
/// （`FavoriteCategory`），老账号里他当年建的分类照旧在、照旧能切能删。
/// 「调整顺序」留着——它是排序，不是批量编辑：进去以后长按整行就是拖动。
struct FavoritesView: View {
  @Bindable var model: SymbolPickerModel
  /// 正在进行的那次调整顺序（连同落脚点、撤销提示）。它住在宿主手里，不是这一页自己的 `@State`——
  /// 理由见 `FavoritesEditSession`。
  var session: FavoritesEditSession
  /// 搜索页的历史词仓。自选页自己开搜索页（见 `search`），所以得跟着传进来。
  var history: SearchHistory
  /// 这一页上「他摆出来的样子」存在哪：排序口径、方向、涨跌额/幅、迷你走势。
  /// 见下面那一段注释——它们和皮肤、副图高度是同一等级的偏好，跟着人走。
  var store: PrefsStore
  var redUp: Bool
  var basisTitle: String
  var updatedAt: Date?
  var feedStatus: FeedStatus
  var feedDiagnostics: String? = nil
  var onVisible: (String) -> Void
  var onRowVisibility: (String, Bool) -> Void
  var onHistoryVisibility: (String, Bool) -> Void
  /// 长按一行时那张预览卡的数据（K 线、持仓量、供应量、费率）。没有就不做长按预览——
  /// 预览里那段 K 线得有人去取，`nil` 说明这一层没人接线（预览、用例）。
  var previews: SymbolPreviewStore?
  /// 从这一页点进图表的那一刻，把**这张表当时的顺序**交出去，供顶栏横滑连续扫图
  /// （§10.1）。顺序是这一页自己算的（分类 + 排序口径 + 升降序），外面复算一遍迟早走样，
  /// 所以由这儿在开图的同一瞬间原样递出去。
  var onScanList: ([String]) -> Void = { _ in }
  /// 加了提醒的那些线（方案 §10「临近关键位置筛选」）。这一版不另立「关注线」概念：
  /// **加了提醒的线就是关注线**，所以排序里的「离提醒线最近」和行的副文案都读它。
  /// 空数组 = 这个人一条提醒都没设过，那一档排序根本不出现。
  ///
  /// 传的是值不是仓库：提醒本身很少动，而这一页每批报价都要重画，挂个 `@ObservedObject`
  /// 只会让两边互相牵连。到价判定在服务端，这儿只算「离得多远」。
  var alerts: [KanpanCore.Alert] = []
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.panelTheme) private var theme
  /// 搜索页盖层，以及它「查看全部 N 个品种」通往的品种整页（见 `SymbolSearchFlow`，
  /// 和行情页顶栏放大镜用的是同一个）。加自选统一在搜索页做（用户 2026-09-18 定的），
  /// 不用先跳回行情页；整页那颗返回原路退回搜索页。
  @State private var search = SymbolSearchFlow()
  /// 分类格里那行字此刻真的排成多大：15 按 `.subheadline` 的曲线缩放（和 `.scaled(15, .medium)`
  /// 挑的是同一条），并且吃得到根上 `.xxxLarge` 的封顶。量格宽用它，见 `tabWidth`。
  @ScaledMetric(relativeTo: .subheadline) private var tabTextSize: CGFloat = 15
  @State private var more = false
  @State private var sorting = false
  @State private var afterMore: (() -> Void)?
  @State private var moreTask: Task<Void, Never>?
  // 调整顺序开着没有 / 调整期间冻住的报价：都在 `session` 上，写法照旧是直接赋值。
  private var editing: Bool {
    get { session.editing }
    nonmutating set { session.editing = newValue }
  }
  private var editQuotes: [String: Ticker] {
    get { session.quotes }
    nonmutating set { session.quotes = newValue }
  }
  /// 已经替它开了历史订阅的品种。页面整体消失时要逐个关掉——
  /// 行自己的 `onDisappear` 在整页被拆掉时不保证会走到。
  @State private var historyOn = Set<String>()
  /// 现在划开着的是哪一行。同一时刻只许一行（见 `SwipeToDelete`）。
  @State private var openSwipe: String?
  /// 现在每一行停在哪儿，以及由它算出来的落脚点（审查 C-08）。盒子是**不被观察**的，
  /// 理由见 `FavoritesRenderedRows`。
  @State private var rows = FavoritesRenderedRows()
  /// 排好的顺序缓存。和上面那个一样是不被观察的引用盒子：命中与否不该触发重画。
  @State private var sortCache = FavoritesSortCache()
  /// 落脚点已经还原过了吗。还原之前不记新的——列表刚铺开时最上面那几行会先
  /// `onAppear`，那时候记下来的是「第一行」，正好把要还原的那个盖掉。
  @State private var anchorRestored = false
  // 这张表「他摆成了什么样」：排序口径、升降序、涨跌额还是涨跌幅、画不画迷你走势线。
  // （原来还有「哪几行展开着详情」，2026-09-24 审查 U9 把行内展开收掉了，详情只剩长按那张卡。）
  //
  // 这几项一路搬过两次家。最早是 `@State`——底栏换成常驻标签栏之后，自选页每切走
  // 一次就整个重建，排好的顺序当场退回「自选顺序」，人回来还得再排一遍。于是搬去了
  // `@AppStorage`，注释写的是「这台机器上这张表想怎么看，跟着机器走，不跟账号走」。
  //
  // **「跟着机器走」这条判断 2026-09-19 推翻了**：判据不是「它在不在设置页上」，而是
  // 「这是他改出来的习惯，还是这个对象自己的属性」。按成交额排、看涨跌额、画不画
  // 走势线，全是前者——换台设备登同一个账号，这张表就该还是这个样子，而同一台机器上
  // 换个人登进来，就不该还是上一个人排的那个顺序。裸 `@AppStorage` 两头都反了。
  // 现在它们住在 `Prefs` 里（见 `Prefs` 末尾那一节），随账号同步，未登录记在访客档案。
  //
  // 写法照旧是直接赋值（`sort = "name"`、`sparkline.toggle()`），只是底下换成了
  // `store.update`——调用处一个字都不用改。
  //
  // 2026-09-19 补：搬家的时候漏了一组——批量编辑（编辑模式 + 勾中的那几行 + 冻住的
  // 报价）还是裸 `@State`，于是「勾好几个品种 → 切去设置页什么都没碰 → 切回来」
  // 编辑模式自己退了、勾全没了。它跟排序口径不一样，不该落盘（冷启动举着三个勾
  // 进来是另一种惊悚），所以搬去了只活一次使用的 `FavoritesEditSession`。
  private var sort: String {
    get { store.prefs.favoritesSort }
    nonmutating set { store.update { $0.favoritesSort = newValue } }
  }
  private var ascending: Bool {
    get { store.prefs.favoritesAscending }
    nonmutating set { store.update { $0.favoritesAscending = newValue } }
  }
  private var amount: Bool {
    get { store.prefs.favoritesAmount }
    nonmutating set { store.update { $0.favoritesAmount = newValue } }
  }
  private var sparkline: Bool {
    get { store.prefs.favoritesSparkline }
    nonmutating set { store.update { $0.favoritesSparkline = newValue } }
  }
  @State private var moving: MoveRequest?
  private struct MoveRequest: Identifiable { let id = UUID(); let symbols: [String] }
  /// 他停在哪一类。和上面几项一样住在 `Prefs` 里（`favoritesGroup`），随账号同步——
  /// 2026-09-19 从 `SymbolPrefs.selectedGroupID` 搬过来的：停在哪一类是「把这张表摆成
  /// 什么样」，不是自选名单自己的属性。
  private var group: String {
    get { store.prefs.favoritesGroup }
    nonmutating set { store.update { $0.favoritesGroup = newValue } }
  }
  /// 切到某一类。分类可能刚被别处删掉，认不出来就什么都不做。
  private func select(_ id: String) {
    guard model.prefs.groups.contains(where: { $0.id == id }) else { return }
    // 换了一类，上一类停在哪一行没有意义（审查 C-08）。
    if group != id {
      // 不过要先把上一类停在哪儿记下来——人切回那一类时还得落回去。
      if let anchor = rows.anchor {
        session.topRow[groupID ?? ""] = anchor
        session.topOffset[groupID ?? ""] = rows.anchorOffset
      }
      session.forgetScrollAnchor()
      rows.minY.removeAll()
      rows.anchor = nil
      anchorRestored = true
    }
    group = id
  }
  /// 真正画出来的那一类：存的那个可能已经被删了，`SymbolPrefs.group(_:)` 退回第一类。
  private var selected: String? { model.prefs.group(group) }
  private var groupID: String? { selected }
  private var skin: LiuliSkin { LiuliSkin(theme: theme) }
  /// 画出来的那一份顺序。
  ///
  /// 手指按在表上（或者表还在滚）的时候用按下去那一刻冻住的那一份，抬手才换成最新的
  /// （§P3-5）。冻的只是「谁排在谁前面」——价格、涨跌那几列照旧每批报价刷新，
  /// 因为它们是每一行自己读的，不经过这儿。
  ///
  /// 冻结期间「有哪些」仍然认最新的：这五秒里被删掉的行不再画（不然点它会打到空），
  /// 新加进来的按最新的顺序补在后面。
  private var symbols: [String] {
    let fresh = sortedSymbols
    guard let held = session.heldOrder, session.frozen else { return fresh }
    let alive = Set(fresh)
    var rows = held.filter { alive.contains($0) }
    let known = Set(rows)
    rows.append(contentsOf: fresh.filter { !known.contains($0) })
    return rows
  }

  /// 按「名单 + 口径 + 报价版本」记住的那一份顺序（审查 C3）。
  ///
  /// `symbols` 一次 body 求值里要被读好多遍——每一行问一次「我是不是第一行」、
  /// 每露一行报一次可见顺序——从前每读一遍就把整张表重排一遍，一屏 N 行就是
  /// N 次 O(N log N)。现在输入没变就直接拿上一次排好的，报价来一批才重排一次。
  private var sortedSymbols: [String] {
    let source = model.prefs.favorites(in: groupID)
    // 只有按行情排的那几档才认报价版本：自选顺序、按品种名、编辑中，行情再跳顺序也不动，
    // 别让它们平白每批报价都失效一次（也别平白多挂一条对报价的观察）。
    let byQuote = !editing && sort != "custom" && sort != "name"
    let key = FavoritesSortCache.Key(
      source: source, sort: sort, ascending: ascending, amount: amount, editing: editing,
      quotes: byQuote ? model.quoteRevision : 0, alerts: sort == alertSortKey ? alerts : [])
    if let hit = sortCache.rows(for: key) { return hit }
    let rows = sortRows(source)
    sortCache.store(rows, for: key)
    return rows
  }

  private func sortRows(_ source: [String]) -> [String] {
    var rows = source
    if !editing, sort != "custom" {
      // 「离提醒线最近」要拿每一行的现价和它自己的提醒线比，一次比较算一遍太贵——
      // 先把整张表算出来，比较器只查表。别的口径用不上它，那就是一张空表。
      let distances = sort == alertSortKey ? alertDistances : [:]
      rows.sort { a, b in
        if sort == "name" { return ascending ? a < b : a > b }
        let x = sortValue(a, distances)
        let y = sortValue(b, distances)
        guard let x, x.isFinite else { return false }
        guard let y, y.isFinite else { return true }
        if x == y { return a < b }
        return ascending ? x < y : x > y
      }
    }
    return rows
  }

  var body: some View {
    // 这一页外面曾经套着一层 `NavigationStack`。整页没有一个 `NavigationLink`，
    // 它唯一干的事就是给自己配一条导航栏、再用 `.toolbar(.hidden, for: .navigationBar)`
    // 关掉——白套一层壳。可这层壳顺手把安全区接管了：`cb0c4c3` 把标签栏从 `VStack`
    // 的一节改成 `MainScreen` 那一层的 `safeAreaInset` 之后，栏让出来的那 50pt 是加在
    // 外面那层 SwiftUI 视图的安全区上的，而 `NavigationStack` 背后的
    // `UINavigationController` 只认窗口自己那份，于是整页都短了一栏：列表滚到底，最后
    // 一行仍压在标签栏底下推不上来；编辑条更是整条沉进「设置」格里——「删除」的中心
    // 落在 (348, 784)，而「设置」格占着 (294.7–393, 768–818)，点删除直接跳去设置页，
    // 自选的批量删除整条是坏的。
    //
    // 壳去掉之后，这一页老老实实吃到已经减掉标签栏的那份安全区，列表和编辑条一起归位。
    GeometryReader { geometry in
      VStack(spacing: 0) {
        FavoritesHeader(prefs: model.prefs, editing: editing, more: more,
                        theme: theme, width: geometry.size.width,
                        content: headerBar).equatable()
        sortBar
        if symbols.isEmpty { emptyState } else { listSheet }
      }
      .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
      .overlayPreferenceValue(MenuAnchors.self) { anchors in
        GeometryReader { proxy in floatingMenu(proxy: proxy, anchors: anchors) }
      }
      .animation(.easeOut(duration: 0.16), value: more)
      .animation(.easeOut(duration: 0.16), value: sorting)
    }
    .background { AuroraBackdrop(skin: skin, reduceMotion: reduceMotion).ignoresSafeArea() }
    .tint(theme.amber)
    .task { await model.appear() }
    .onAppear {
      // 这一页每切走一次就整个重建（`MainScreen.portraitBody` 里的 `switch tab`）。
      // 编辑还开着的时候重新露面，那份冻住的报价跟着 `session` 活了下来，但它停在
      // 切走的那一刻：离开期间新加进来的品种在它里面没有条目，行里的价格就空着。
      // 这儿按手上最新的报价重铺一次——刚重建完，没有「布局跟着 WS 抖」的顾虑。
      if editing, !model.tickers.isEmpty { editQuotes = model.tickers }
      rows.teardown = false
    }
    .onDisappear {
      // 走之前把落脚点交给宿主（审查 C-08）。切回来时这一页整个重建，
      // `session` 是这一页之外唯一还活着的东西。
      //
      // 先封笔再交：拆页的过程里每一行还会再报一次位置，那些是过程量。
      rows.teardown = true
      if let anchor = rows.anchor {
        session.scrollAnchor = anchor
        session.topRow[groupID ?? ""] = anchor
        session.topOffset[groupID ?? ""] = rows.anchorOffset
      }
      moreTask?.cancel()
      for symbol in historyOn { onHistoryVisibility(symbol, false) }
      historyOn.removeAll()
    }
    .onChange(of: more) { _, shown in
      guard !shown, let action = afterMore else { return }
      afterMore = nil
      moreTask?.cancel()
      moreTask = Task { @MainActor in
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        action()
      }
    }
    .onChange(of: model.tickers.isEmpty) { _, empty in
      // 报价表空掉只是数据状态——设置里直连↔网关切一下，`QuoteBook` 就 reset 一次、
      // 把整张表清空。它不是用户的动作，不该拿来推翻用户正在做的事：以前这儿顺手
      // `editing = false`，人正拖着排顺序，别处切一次线路，模式当场没了。
      // 调整顺序只由用户自己的动作退出。
      // 编辑时那份冻结的报价（`editQuotes`）也别清，等新报价上来原地续上就是了。
      if !empty, editing { editQuotes = model.tickers }
    }
    .fullScreenCover(isPresented: $search.searchShown, onDismiss: { search.searchDismissed() }) {
      SymbolSearchView(model: model, history: history, redUp: redUp,
                       onClose: { search.searchShown = false },
                       // 搜到的比一屏多时那行「查看全部」：交给品种整页，查询词跟着过去。
                       onAll: { search.showAllFromSearch() },
                       onPicked: { search.reset() },
                       // 星点亮之后跟着品种走：它落进哪一组就切到哪一组，
                       // 收起搜索页第一眼就能看见刚加的那一行。
                       onStarred: { if let group = model.prefs.groupForSymbol[$0] { select(group) } },
                       onVisible: onVisible,
                       onRowVisibility: onRowVisibility)
    }
    .sheet(isPresented: $search.allShown, onDismiss: { search.allDismissed() }) {
      // 「查看全部」走进来的，返回要等整页退完再退回搜索页（词留着）。
      SymbolPickerView(model: model, redUp: redUp, onClose: {
        search.closeAll()
      }, onSelect: { info in
        model.addFavorite(info.symbol, info: info)
        if let group = model.prefs.groupForSymbol[info.symbol] { select(group) }
        search.reset()
      }, onVisible: onVisible, onRowVisibility: onRowVisibility)
    }
    .sheet(item: $moving) { request in
      NavigationStack {
        List {
          ForEach(model.moveTargets, id: \.self) { name in Button(name) { assign(request.symbols, toCategory: name) } }
            // 行的底得**行自己**写：`scrollContentBackground` 只管表底，管不到行。
            // 只换表底的话，底已经是 `app` 了，行还是系统那张纯白圆角卡（深色是
            // `#1C1C1E` 灰卡压在墨绿黑上），卡的四条边就是一道硬边。
            // 同一条规矩另见 `AccountView.listed` 和本页列表行的注释。
            .listRowBackground(theme.raised)
        }.scrollContentBackground(.hidden).background(theme.app)
          .navigationTitle("移到分类").navigationBarTitleDisplayMode(.inline)
          .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { moving = nil } } }
      }.presentationDetents([.medium, .large]).tint(theme.amber)
        // 半屏自己那张底也得跟着皮肤：不给的话表格以外那圈仍是系统分组灰。
        .presentationBackground(theme.app)
    }
  }

  // MARK: - 头部

  /// 两行：上一行是一条长搜索框加一颗「…」，下一行整条都是分类文件夹。
  ///
  /// 2026-09-18 用户把这一页顶上的「自选」大字、数量印章、右边那条涨跌比和
  /// 「今日 N 涨 N 跌」那行小字全撤了，加自选的入口只留一个——它开的就是搜索页。
  /// 排法照推特：中间整条是搜索框，分类条自己独占一行，这样分类不必和按钮抢宽度，
  /// 也不会挤成一条乱麻。
  ///
  /// 同一天晚些时候底栏换成了常驻标签栏，这一行跟着改了两处：**左边那颗返回没了**
  /// （自选本身就是标签栏上的一格，「返回」去哪儿都说不清，换一格就是返回），
  /// **右边那颗从齿轮换回「…」**——齿轮现在归标签栏最右边那一整页，两个齿轮
  /// 一个开整页设置、一个开这一页的菜单，谁也分不出哪个是哪个。
  private var headerBar: some View {
    VStack(spacing: 6) {
      HStack(spacing: 8) {
        // 编辑中把搜索框换成「完成」：模式总得有个看得见的出口，藏进菜单要点两下才出得来。
        if editing {
          Button { toggleEditing() } label: {
            Text("完成").font(.scaled(15, .semibold)).foregroundStyle(theme.amber)
              .frame(maxWidth: .infinity).frame(height: 42)
              .background(skin.glassThin, in: Capsule())
              .overlay(Capsule().strokeBorder(skin.edgeSoft, lineWidth: 0.5))
              .frame(height: 46).contentShape(Rectangle())
          }.buttonStyle(.plain)
            .accessibilityLabel("完成调整").accessibilityIdentifier("favorites.editToggle")
        } else {
          searchField
        }
        // 它装的是调整顺序、迷你走势开关、删除当前分类——全是**这一页**的事，
        // 所以记号用「…」而不是齿轮：齿轮在标签栏最右边，那颗才是整个 app 的设置。
        circleButton("ellipsis", label: "自选菜单", id: "favorites.more") { more = true }
          .anchorPreference(key: MenuAnchors.self, value: .bounds) { ["more": $0] }
      }
      groupStrip
    }
    // 左右边距跟页面走（`Inset.page`：16 Pro 16、Pro Max 20），和下面的排序行、每一行的徽章
    // 站在同一条竖线上（UI 审查 2026-09-24：这一页原来有 12 / 22 / 19 三条左竖线）。
    .pageHorizontalInset()
    .padding(.bottom, Space.xxs)
    // 那行状态小字撤掉了，但 UI 测试要从 `favorites.feed` 上读调色板与行情线路的
    // 诊断串（它只在辅助功能树里，界面上看不见），所以把这个标识挂到整条头部上。
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("favorites.feed")
    .accessibilityValue(paletteDiagnostics)
  }

  /// 中间那条长搜索框：看着像输入框，点一下开的是整张搜索页。
  ///
  /// 这一页只有这一个「加自选」的入口（点进去在结果行上点星）。做成框而不是一颗放大镜
  /// 是用户 2026-09-18 照推特定的：框子把两头的圆按钮分开，中线不空，也一眼看得出
  /// 这里能搜。里面不放真的输入框——真输入框会在这一页起键盘，搜索页那边还要再起一次。
  private var searchField: some View {
    Button { search.openSearch() } label: {
      // 放大镜、字号、内边距和搜索页那条真框（`SymbolSearchField`）一样，点进去框不跳。
      HStack(spacing: Space.s) {
        VectorIcon.search(SymbolSearchField.iconSize).foregroundStyle(theme.ink3)
        Text("搜索品种").font(TypeScale.body).foregroundStyle(theme.ink3)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, SymbolSearchField.hPad)
      .frame(maxWidth: .infinity).frame(height: 42)
      .background(skin.glassThin, in: Capsule())
      .overlay(Capsule().strokeBorder(skin.edgeSoft, lineWidth: 0.5))
      .frame(height: 46)
      .contentShape(Rectangle())
    }.buttonStyle(.plain)
      .accessibilityLabel("添加品种").accessibilityIdentifier("favorites.add")
  }

  private func circleButton(_ icon: VectorIcon, label: String, id: String,
                            action: @escaping () -> Void) -> some View {
    circleButton(label: label, id: id, action: action) {
      icon.foregroundStyle(theme.ink)
    }
  }

  private func circleButton(_ icon: String, label: String, id: String,
                            action: @escaping () -> Void) -> some View {
    circleButton(label: label, id: id, action: action) {
      Image(systemName: icon)
        .font(.system(size: 19, weight: .regular))
        .foregroundStyle(theme.ink)
    }
  }

  /// 玻璃圆片：42 的片子挂在 46 的可点区里，两种记号（SF Symbol / 自绘线条）共用。
  /// 片子原来是 32，用户 2026-09-18 两次说太小不好点，一路放大到 42。
  private func circleButton<Icon: View>(label: String, id: String,
                                        action: @escaping () -> Void,
                                        @ViewBuilder icon: () -> Icon) -> some View {
    Button(action: action) {
      icon()
        .frame(width: 42, height: 42)
        .background(skin.glassThin, in: Circle())
        .overlay(Circle().strokeBorder(skin.edgeSoft, lineWidth: 0.5))
        .frame(width: 46, height: 46)
        .contentShape(Rectangle())
    }.buttonStyle(.plain)
      .accessibilityLabel(label).accessibilityIdentifier(id)
  }

  /// 只活在辅助功能树里的诊断串：验收用例靠它确认当前皮肤与行情线路。
  private var paletteDiagnostics: String {
    guard let feedDiagnostics else { return "" }
    return feedDiagnostics + ";background=" + theme.chart.bg.value
      + ";feed=" + String(describing: feedStatus)
      // 落脚点（审查 C-08）。只进辅助功能树，界面上看不见；`feedDiagnostics`
      // 自己就只在 DEBUG + `KANPAN_CHART_DIAGNOSTICS=1` 时才非空。
      + ";anchor=" + (session.scrollAnchor ?? "-")
      // 这一类现在（或离开时）顶上露着的那一行，以及上一次还原真正瞄的是哪一行。
      // 两者对不上就说明还原没落到位（见 `noteScrollAnchor` / `restoreScrollAnchor`）。
      + ";top=" + (session.topRow[groupID ?? ""] ?? "-")
      + ";used=" + (session.restoreAnchorUsed ?? "-")
  }

  // MARK: - 分类分段器

  /// 一格分类占多宽：名字 + 左右各 19 的内边，72–150 之间。
  ///
  /// 原来拿不缩放的 15pt 量宽、字却是 `.scaled(15)` 排的：系统字号一调大，格子还是按 15 算的宽，
  /// 名字就被截成「自…选」（UI 审查 2026-09-24 §3.3 的 bug）。现在量宽和排字用同一个字号
  /// （`tabTextSize`，做法同 `IntervalBar.textWidth`），上下限也跟着字号一起放大。
  private func tabWidth(_ group: FavoriteGroup) -> CGFloat {
    let font = UIFont.systemFont(ofSize: tabTextSize, weight: .medium)
    let text = ceil((group.name as NSString).size(withAttributes: [.font: font]).width)
    let scale = tabTextSize / 15
    return min(150 * scale, max(72 * scale, text + 38))
  }

  /// 分类文件夹：一条能横向滚的玻璃分段器。
  ///
  /// 原来这条是按剩余宽度裁的——排不下的分类折进设置菜单的「更多分类」里。现在它
  /// 自己独占头部第二行，改成横着滚：分类再多也都在这条上，往左推就能看见，菜单里
  /// 那半截也就不用留了（用户 2026-09-18：「空间都给分类文件夹」「往右边滑即可」）。
  @ViewBuilder private var groupStrip: some View {
    if model.prefs.groups.isEmpty {
      EmptyView()
    } else {
      ScrollViewReader { reader in
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 0) {
            ForEach(model.prefs.groups) { group in
              chip(group.name, id: group.id, count: model.prefs.favorites(in: group.id).count)
                .frame(width: tabWidth(group))
            }
          }
          .padding(.horizontal, 4)
          .background {
            Capsule()
              .fill(skin.glassThin)
              .overlay(Capsule().strokeBorder(skin.edgeSoft, lineWidth: 0.5))
              .frame(height: 46)
          }
          // 选中那格底下有一圈光晕，留出上下这点地方，免得被滚动区裁掉。
          .padding(.vertical, 8)
        }
        // 选中的那一格必须看得见：新建完一个分类它就立刻被选上，要是正好排在
        // 滚动区外面，用户会以为分类没建成。
        .onAppear { scrollToSelected(reader, animated: false) }
        .onChange(of: selected) { _, _ in scrollToSelected(reader, animated: true) }
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("favorites.groups")
    }
  }

  private func scrollToSelected(_ reader: ScrollViewProxy, animated: Bool) {
    guard let selected else { return }
    guard animated else { reader.scrollTo(selected, anchor: .center); return }
    withAnimation(.easeOut(duration: 0.2)) { reader.scrollTo(selected, anchor: .center) }
  }

  private func chip(_ title: String, id: String, count: Int) -> some View {
    let on = selected == id
    return Button { select(id) } label: {
      // 名字后面原来还挂着一个上标的数量，用户 2026-09-18 让去掉——数量在列表上面
      // 那行「N 个品种」已经写着了，格子里只留名字更干净。数量仍留在朗读标签里。
      Text(title).font(.system(size: tabTextSize, weight: .medium))
        .lineLimit(1).truncationMode(.middle)
        // 压在强调色上的字一律走 `badgeInk`：浅色下它就是 `#FFFFFF`（和原来的
        // `Color.white` 一个值，这一页的定稿基准图一个像素不变），深色下换成近黑的
        // `seed.ground`——深色强调色是 `#4FB69C` / `#E2874F` 那种亮色，白字压上去
        // 只有 2.5:1，读不清。
        .foregroundStyle(on ? theme.badgeInk : theme.ink2)
        .frame(maxWidth: .infinity).frame(height: 40)
        .background {
          if on {
            Capsule()
              .fill(skin.accentGradient)
              .overlay(alignment: .top) { skin.topHighlight(inset: 10) }
              .shadow(color: skin.accent.opacity(skin.dark ? 0.5 : 0.35), radius: 8, x: 0, y: 5)
          }
        }
        .frame(height: 44)
        .contentShape(Rectangle())
    }.buttonStyle(.plain)
      .accessibilityLabel(title + "，\(count)个品种")
      .accessibilityAddTraits(on ? .isSelected : [])
      .accessibilityIdentifier("favorites.group." + title)
  }

  // MARK: - 浮层菜单

  /// 设置菜单与排序菜单都画在页面自己的浮层里，不走 `.popover`。
  ///
  /// 原来这两张卡片是 `.popover(presentationCompactAdaptation(.popover))`。UIKit 为它
  /// 单独起一层承载视图，而这一页的列表是「空态 ↔ 列表」两个分支换着挂的：只要弹层
  /// 出现过一次，之后新挂上来的那张 `List` 就落在了那层的下面，画得出来却收不到触摸
  /// ——展开箭头、整行、右滑全都点不动（2026-09-18 在模拟器上复现：先开一次设置菜单
  /// 再从搜索页加第一个品种，那一行就是死的；列表先有内容时则不受影响）。浮层画在
  /// 自己的视图树里就没有这层承载视图，也顺手省掉了 iPad 上 popover 的尺寸适配。
  @ViewBuilder
  private func floatingMenu(proxy: GeometryProxy, anchors: [String: Anchor<CGRect>]) -> some View {
    if more || sorting {
      ZStack(alignment: .topLeading) {
        // 点菜单外面收起来：透明但吃点击，画面上看不出多一层。
        Color.black.opacity(0.001).ignoresSafeArea().contentShape(Rectangle())
          .onTapGesture { more = false; sorting = false }
        if more, let anchor = anchors["more"] {
          menuCard(width: 260, proxy: proxy, anchor: anchor) { moreList }
        } else if sorting, let anchor = anchors["sort"] {
          menuCard(width: 190, proxy: proxy, anchor: anchor) { sortList }
        }
      }
    }
  }

  /// 卡片吊在触发它的那颗按钮下面，右边对齐，够不着就往里收。
  private func menuCard<V: View>(width: CGFloat, proxy: GeometryProxy, anchor: Anchor<CGRect>,
                                 @ViewBuilder content: () -> V) -> some View {
    let rect = proxy[anchor]
    let x = min(max(10, rect.maxX - width), max(10, proxy.size.width - width - 10))
    return content()
      .frame(width: width)
      .background(theme.app, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).strokeBorder(skin.edgeSoft, lineWidth: 0.5))
      .shadow(color: .black.opacity(0.14), radius: 20, y: 10)
      .offset(x: x, y: rect.maxY + Space.s)
      .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
  }

  // MARK: - 更多

  private func runMore(_ action: @escaping () -> Void) {
    afterMore = action; more = false
  }

  private func moreRow(_ title: String, icon: String, id: String, destructive: Bool = false,
                       action: @escaping () -> Void) -> some View {
    Button { runMore(action) } label: {
      Label(title, systemImage: icon).frame(maxWidth: .infinity, minHeight: Hit.min, alignment: .leading)
        .padding(.horizontal, Inset.card).contentShape(Rectangle())
    }.buttonStyle(.plain).foregroundStyle(destructive ? theme.danger : theme.ink)
      .accessibilityIdentifier(id)
  }

  /// 设置菜单。以前头一段是「更多分类」——分类条排不下的那几个；现在分类条自己
  /// 能滚，一个都不会被挤掉，这一段就撤了。
  ///
  /// 「新建分类」「重命名当前分类」「编辑自选」（批量编辑）2026-09-24 撤了，理由见文件头。
  /// 原来的「编辑自选」进去以后既能勾选又能拖动，现在只剩拖动，所以改叫「调整顺序」，
  /// 和长按菜单里那一项同名——同一件事只有这两个入口。
  private var moreList: some View {
    VStack(spacing: 0) {
      moreRow(editing ? "完成调整" : "调整顺序", icon: "arrow.up.arrow.down", id: "favorites.edit") { toggleEditing() }
      moreRow(sparkline ? "隐藏迷你走势" : "显示迷你走势", icon: sparkline ? "waveform.slash" : "waveform",
              id: "favorites.sparkline") { sparkline.toggle() }
      if let group = deletableGroup {
        moreRow("删除当前分类", icon: "trash", id: "favorites.deleteGroup", destructive: true) { Haptics.warning(); model.deleteGroup(group.id) }
      }
    }.padding(.vertical, Space.s).font(TypeScale.body)
  }

  /// 菜单里那颗「删除当前分类」删的是哪一类。只剩一类（首装加第一个品种就是这样）时是
  /// `nil`：删了它，里面的品种无处可去，而且下一次加品种又会按资产类型把它开回来——
  /// 这颗按钮点了等于什么都没发生，干脆不摆。
  private var deletableGroup: FavoriteGroup? {
    guard model.prefs.groups.count > 1 else { return nil }
    return model.prefs.groups.first(where: { $0.id == selected })
  }

  private func toggleEditing() {
    if editing { session.end() } else { session.begin(quotes: model.tickers) }
  }

  // MARK: - 排序行

  private var sortBar: some View {
    HStack(spacing: 0) {
      Text("\(symbols.count) 个品种").font(TypeScale.caption2).foregroundStyle(skin.ink4)
      Spacer(minLength: 0)
      Button { sorting = true } label: {
        HStack(spacing: Space.xs) {
          Text(sortTitle).font(TypeScale.caption2).foregroundStyle(theme.ink3)
          Image(systemName: sort == "custom" ? "arrow.up.arrow.down"
                : (ascending ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill"))
            .font(.system(size: 7)).foregroundStyle(theme.amber)
        }
        // 点击区 44（原来 28）。整行也就 44 高，比原来的 10 + 28 + 4 还矮两点，字的位置不动。
        .hitTarget()
      }.buttonStyle(.plain).disabled(editing)
        .accessibilityLabel("排序方式").accessibilityIdentifier("favorites.sort")
        .anchorPreference(key: MenuAnchors.self, value: .bounds) { ["sort": $0] }
    }.pageHorizontalInset()
  }

  private var sortTitle: String {
    switch sort {
    case "name": "品种"
    case "volume": "成交额"
    case "price": "价格"
    case "change": amount ? "涨跌额" : basisTitle
    case alertSortKey: "离提醒线最近"
    default: "自选顺序"
    }
  }

  private var sortList: some View {
    VStack(spacing: 0) {
      sortItem("自选顺序", key: "custom")
      sortItem("品种", key: "name")
      sortItem("成交额", key: "volume")
      sortItem("价格", key: "price")
      sortItem(basisTitle, key: "change", useAmount: false)
      sortItem("涨跌额", key: "change", useAmount: true)
      // 一条提醒都没有的时候这一档没有意义（整张表都是「—」），干脆不出现——
      // 它是跟着「加入提醒」长出来的入口，不是一个要先看懂才知道选不选的选项。
      if !alerts.isEmpty { sortItem("离提醒线最近", key: alertSortKey) }
    }.padding(.vertical, Space.s).font(TypeScale.body)
  }

  private func sortItem(_ title: String, key: String, useAmount: Bool? = nil) -> some View {
    let current = sort == key && (useAmount == nil || useAmount == amount)
    return Button {
      if let useAmount { amount = useAmount }
      applySort(key)
      sorting = false
    } label: {
      HStack(spacing: Space.s) {
        Text(title)
        Spacer(minLength: 0)
        if current {
          Image(systemName: ascending ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
            .font(.system(size: 8)).foregroundStyle(theme.amber)
        }
      }.frame(maxWidth: .infinity, minHeight: Hit.min, alignment: .leading)
        .padding(.horizontal, Inset.card).contentShape(Rectangle())
    }.buttonStyle(.plain).foregroundStyle(current ? theme.amber : theme.ink)
  }

  /// 排序键与方向：和原来那排小按钮一个逻辑——同一个键点第二次翻方向，
  /// 第三次退回自选顺序。
  private func applySort(_ key: String) {
    guard key != "custom" else { sort = "custom"; return }
    if sort != key { sort = key; ascending = ascendingByDefault(key) }
    else if ascending == ascendingByDefault(key) { ascending.toggle() } else { sort = "custom" }
  }

  /// 这个口径第一次点的时候是「小的在前」吗。品种按字母、离提醒线按距离，
  /// 都是小的在前；价格、成交额、涨跌那几档照旧是大的在前。
  private func ascendingByDefault(_ key: String) -> Bool { key == "name" || key == alertSortKey }

  /// 「离提醒线最近」这一档的键。存进 `Prefs.favoritesSort` 的就是它。
  private var alertSortKey: String { "alert" }

  /// 每个品种离它自己最近的那条提醒线有多远（0.008 就是 0.8%）。
  ///
  /// 只算还醒着的提醒：已触发、已暂停的线不是「在等的位置」。取不到现价（停牌、
  /// 已下架）或者线压根落在别的时间段上，这个品种就不在表里——它排最后，副文案也空着。
  private var alertDistances: [String: Double] {
    guard !alerts.isEmpty else { return [:] }
    let now = Date().timeIntervalSince1970 * 1000
    var out: [String: Double] = [:]
    for (symbol, list) in Dictionary(grouping: alerts.filter(\.isActive), by: { SymbolPrefs.key($0.symbol) }) {
      guard model.listing(of: symbol).hasLivePrice,
            let price = displayQuote(symbol)?.last, price > 0, price.isFinite else { continue }
      guard let d = AlertEvaluator.nearestDistance(from: price, among: list, at: now) else { continue }
      out[symbol] = d
    }
    return out
  }

  /// 这一行要不要在副文案上写「距提醒线 x.x%」。只在按这一档排的时候写——
  /// 平时那一行是「额 … · 幅 …」，两样东西不挤在一行里。
  private func alertDistanceText(_ symbol: String) -> String? {
    guard sort == alertSortKey, let d = alertDistances[SymbolPrefs.key(symbol)] else { return nil }
    return "距提醒线 " + toFixed(d * 100, d * 100 < 10 ? 2 : 1) + "%"
  }

  /// 编辑行布局不随每批WS报价重建；退出编辑立刻读取最新行情。
  private func displayQuote(_ symbol: String) -> Ticker? {
    editing ? editQuotes[symbol] : model.ticker(for: symbol)
  }

  private func sortValue(_ symbol: String, _ distances: [String: Double]) -> Double? {
    // 「离提醒线最近」不走行情那几个字段：距离已经在 `alertDistances` 里算好了，
    // 表里没有这个品种就是「它没有在等的线」，照旧沉到末尾。
    if sort == alertSortKey { return distances[SymbolPrefs.key(symbol)] }
    // 已下架 / 还没开盘的行没有实时价可排：它的涨跌幅、成交额在界面上是「—」，
    // 拿一个界面上看不见的数去决定它排第几，用户只会觉得顺序是乱的（审查 B.5 / B-06）。
    // 这里返回 `nil`，上面那个比较器会把它沉到末尾，而且照旧留在表里。
    guard model.listing(of: symbol).hasLivePrice,
          let ticker = displayQuote(symbol) else { return nil }
    if sort == "price" { return ticker.last }
    if sort == "volume" { return ticker.quoteVolume }
    if amount, ticker.changePercent > -100 {
      return ticker.last - ticker.last / (1 + ticker.changePercent / 100)
    }
    return ticker.changePercent
  }

  // MARK: - 列表：行直接长在极光上

  /// 这里原来铺着一张玻璃纸（圆角 22、白雾填充、上沿高光、半像素描边，两侧各留 12pt）。
  /// 用户看过对比之后选了「融合」：纸的四条边把屏幕切成「底」和「纸」两层，去掉之后
  /// 头部、分类段、列表读成同一块材料。玻璃原本干的活是替文字挡光斑，现在交给
  /// `AuroraBackdrop` 底部那层同色渐变。行与行之间只剩一根两头淡出的发丝线。
  private var listSheet: some View {
    // 只加一层 `ScrollViewReader`——它不画任何东西，版面一个像素都不动（审查 C-08）。
    ScrollViewReader { reader in
      list
        // 回到这一页时落回原来那一行（审查 C-08 与 §P3-6 合成了同一条路，
        // 见 `restoreScrollAnchor`）。
        .onAppear { restoreScrollAnchor(reader) }
    }
  }

  private var list: some View {
    List {
      ForEach(symbols, id: \.self) { symbol in
        // 划开露的那三颗砖。原来这儿挂的是两条 `.swipeActions`，砖底一半是系统红
        // （`#FF3B30`，这几屏上唯一一处不跟皮肤走的颜色），砖上的字一律被 UIKit
        // 画成白的——白压系统红 3.55:1、白压 `theme.amber` 只有 2.47:1（青苔深）。
        // 而且它**没法只修一半**：光补 `.tint(theme.danger)` 会掉到 2.43:1，比不补还差。
        // 所以整个换成自己画的那一份，底走 `theme.danger` / `theme.amber`、
        // 字走 `theme.badgeInk`，机制见 `SwipeToDelete`。
        //
        // 「不许滑到底直接触发」（原来的 `allowsFullSwipe: false`）没动。文案 2026-09-24
        // 统一成「取消自选」（原来左划叫「删除」、右划叫「删除自选」、搜索页叫「移出自选」，
        // 同一件事三种叫法）。
        //
        // 右滑那一侧 2026-09-24 撤了：它露的是和左滑同一颗「取消自选」，同一个动作在这一页
        // 摆了左滑、右滑、长按三处。现在「取消自选」「移到分类」各只在左滑和长按菜单里，
        // 右滑整个不响应（`leading` 为空时行一个像素都拉不动，不会露半截）。
        SwipeToDelete(
          id: symbol, open: $openSwipe, brick: .flush,
          trailing: [
            SwipeAction(id: SwipeDeleteIDs.favoritesMove, title: "移到分类", fill: theme.amber) {
              moving = MoveRequest(symbols: [symbol])
            },
            .delete(theme, title: "取消自选") { removeFavorites([symbol]) },
          ],
          fullSwipe: false
        ) { _ in
          previewable(symbol, row(symbol, first: symbol == symbols.first))
          // 替还原那一步找到 `List` 背后的 UIKit 滚动容器（P2.4，见 `alignAnchorPixels`）。
          // 挂在行的**内容**上，不是挂在下面那几条 `listRow*` 外头——理由见下一段注释。
          .background(FavoritesScrollerProbe(rows: rows))
        }
        // 这一行的上沿在屏幕上的位置。落脚点就是从这儿算出来的（审查 C-08）：
        // 问「铺出来没有」答不了「看得见没有」，只有真位置能（见 `FavoritesRenderedRows`）。
        //
        // **这一句必须排在下面三条 `listRow*` 前面，不要挪到后面去。** 0dee684 加它的时候
        // 排在三条后面，结果是「融合」当场丢了：`.listRowBackground(Color.clear)` 和
        // `.listRowSeparator(.hidden)` 都是**行特征**，要一路往上传到 `List` 才作数，
        // 而 `.onGeometryChange` 包在外面会把它们挡住——两条同时失效，屏幕上就是每行一块
        // 不透明的白底、白底下沿再挂一根系统那根半截分隔线，和暖底拼出一条硬边
        // （违反 kanpan-no-seams-one-continuous-surface）。2026-09-22 在 iPhone 15 / iOS 26
        // 上复现并逐步验证：只把这一句挪到三条之前，白底与半截分隔线当场都没了，
        // 版面和 `docs/acceptance/兼容-2026-09-21/iPhone15-自选分类页.png` 对得上。
        // 量到的还是同一个数（行内容与行框之间 `listRowInsets` 是零），
        // `FavoritesScrollAnchorUITests.testFavoritesKeepsTheScrollPositionAcrossTabs` 照旧绿。
        .onGeometryChange(for: CGFloat.self) { proxy in
          proxy.frame(in: .global).minY
        } action: { y in
          // 这儿只记位置，**不算落脚点**：算一次要把整张表重新排一遍
          // （`symbols` 是算出来的），而这一句是每行每帧都走的。算的那一下
          // 放在滚动停下来的时候（见 `list` 上的 `onScrollPhaseChange`）。
          guard !rows.teardown else { return }
          rows.minY[symbol] = y
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .onAppear {
          onVisible(symbol); onRowVisibility(symbol, true)
          session.rowVisible(symbol, true, group: groupID ?? "", order: symbols)
          if historyOn.insert(symbol).inserted { onHistoryVisibility(symbol, true) }
        }
        .onDisappear {
          onRowVisibility(symbol, false)
          session.rowVisible(symbol, false, group: groupID ?? "", order: symbols)
          if historyOn.remove(symbol) != nil { onHistoryVisibility(symbol, false) }
          // 只摘位置，**不重算落脚点**：整页被拆掉的那一刻每一行都会走一遍这儿，
          // 边摘边算会把「最上面那行」一路推到表尾，刚记下的落脚点当场作废。
          rows.minY[symbol] = nil
        }
      }
      .onMove { source, target in
        // 编辑时恢复自定义顺序，筛选时不允许把可见索引套到完整列表。
        model.moveVisible(symbols, from: source, to: target)
        sort = "custom"
      }
    }
    .listStyle(.plain)
    // 列表自己的上沿在哪儿。行的位置是按屏幕坐标量的（见每一行的 `onGeometryChange`），
    // 拿这一条当尺子就知道哪一行被顶上切掉了。
    //
    // 量在背后垫的那张透明纸上，**不要直接挂到 `List` 身上**：2026-09-21 在
    // iPhone 15（iOS 26）上试过，让 `List` 自己去求位置（`.onGeometryChange` 挂在它身上、
    // 或者给它一个具名坐标系）这张表就滚不动了——12 下 `swipeUp` 连 13 行都没滚过去。
    // 垫一张纸量它的框，框和 `List` 一样大，结果一样，滚动不受影响。
    // 行也一律按屏幕坐标（`.global`）记：一页之内两头用的是同一把尺，差值才有意义。
    .background {
      Color.clear.onGeometryChange(for: CGFloat.self) { proxy in
        proxy.frame(in: .global).minY
      } action: { top in
        rows.listTop = top
      }
    }
    // 手指按在表上的这段时间不重排（§P3-5）。
    //
    // 两个信号各管一段：滚动阶段管「甩出去之后还在滑」那一段（手指早抬了，可行还在动，
    // 这时候换顺序和手指还按着一样糟）；`TouchWatcher` 管「按着不动 / 正要左滑 /
    // 长按等预览」那一段——那几种情况一个滚动阶段都不会发生。
    .onScrollPhaseChange { _, phase in
      session.scrolling = phase != .idle
      // 那一下要是被 `List` 自己的滚动抢走了，抬手事件就到不了 `TouchWatcher`。
      // 滚动停下来的时候顺手把冻结解开，免得一整页锁死。
      if phase == .idle {
        session.release()
        // 停稳了才记落脚点（审查 C-08）。这正是「人停在哪一行」的那一刻，
        // 而且一次滚动只算一遍——滚的过程里每帧算一遍的那版把列表卡到滚不动。
        noteScrollAnchor()
      }
    }
    .gesture(TouchWatcher { down in
      if down { session.hold(sortedSymbols) } else { session.release() }
    })
    // 关掉系统滚动条。iOS 13 起那根灰条自己是能抓住拖的，也就是说它会吃触摸——
    // 它占的那条竖带（右边 30pt）正好压在每行最右边的涨跌格上，列表一滚或一重建
    // 它就闪出来，那一两秒里点那一格会没反应。这一页本来也没打算露系统滚动条。
    .scrollIndicators(.hidden)
    .scrollContentBackground(.hidden)
    .environment(\.defaultMinListRowHeight, 0)
    // List 占满剩下的整屏：长按把一行拖到最后一行下面，落点还在列表里。
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .padding(.top, 6).padding(.bottom, 8)
  }

  /// 记下「他现在停在哪一行」：按表的顺序取第一个还画在屏幕上的品种。
  ///
  /// 存代号不存偏移量，理由见 `FavoritesEditSession.scrollAnchor`。
  private func noteScrollAnchor() {
    guard anchorRestored, !rows.teardown else { return }
    // 顶上第一个**完整露着**的品种。这儿曾经取的是「铺着的第一行」，2026-09-21 在
    // iPhone 15（iOS 26）上量出来那是两回事：手指滚停下来时顶上一行都不多铺，
    // 两者恰好重合；`scrollTo` 落地之后却多铺三四行。记的时候按前者、还原之后按后者，
    // 于是每来回一趟就往下窜一个缓冲的厚度（用例读到从 DOTUSDT 跳到 BCHUSDT，差 3 行）。
    // 现在两头问的都是 `topVisible`，同一把尺。
    guard let top = rows.topVisible(symbols) else { return }
    // 只记在那个不被观察的盒子里。`session` 是 `@Observable`，滚动时每露一行写一次
    // 就等于把整张表重画一遍——这一页上跑着实时报价，赔不起。真正交出去是在整页
    // `onDisappear` 那一刻（见上面），那时候读一次就够了。
    rows.anchor = top
    // 连同它离列表上沿差多少一起记：只按整行还原，回来会差出不到一行的零头（P2.4）。
    rows.anchorOffset = (rows.minY[top] ?? rows.listTop) - rows.listTop
    // **不要**顺手写 `session.topRow`。它看着人畜无害（界面上没有控件读它），
    // 可诊断串读，而诊断串在 UI 测试里是开着的：滚一帧写一次 `@Observable`，
    // 整页跟着重画，列表当场滚不动（2026-09-21 实测：12 下 `swipeUp` 连
    // 13 行都没滚过去）。交出去的那一下放在整页 `onDisappear` 和换分类那儿，
    // 一次就够。
  }

  /// 切回这一页时滚回原来那一行（审查 C-08）。
  ///
  /// 自选页每切走一次就整个重建（`MainScreen.portraitBody` 的 `switch tab`），
  /// 列表跟着从第一行重新铺——人滚到 APTUSDT 去了一趟设置页，回来又在 BTC 上。
  /// 落脚点活在宿主手里的 `session` 上，所以这儿只负责把它用出来。
  ///
  /// 先让一帧过去再滚：`onAppear` 这一刻 List 还没量完自己的高度，当场 `scrollTo`
  /// 会落空。滚完再等一小会儿才开始记新的落脚点——顶上那几行的 `onAppear`
  /// 会在滚动落地前先跑一遍，那时候记下来的是「第一行」。
  ///
  /// **为什么不用 `scrollPosition(id:)`。** 那一手看着正合适（框架自己报可视区顶上
  /// 那一行，写回去也是它），2026-09-20 实测在这张 `List` 上**根本不往里写**：
  /// 滚了十几下 `topRow` 始终是 `nil`，交出去的落脚点是空的，切回来自然停在表头。
  /// 它对 `ScrollView` + `LazyVStack` 才成立，`List` 这边只能自己攒。
  ///
  /// 落脚点有三个来源，按「人回来要找什么」排（审查 C-08 与 §P3-6 这一轮合流）：
  ///
  /// 1. 刚从这一页点进图的那一只，而且**走的时候它并不露着**（从别处点进去的，或者
  ///    中途滚远了）——人回来找的就是它，直接摆到屏幕中间，不做下面那道校准。
  /// 2. 这一类离开时顶上露着的那一行（按分类各记一条，A 类的锚点套到 B 类上就是乱滚）。
  /// 3. 上一轮攒下的「铺着的第一行」。
  private func restoreScrollAnchor(_ reader: ScrollViewProxy) {
    guard !anchorRestored else { return }
    let list = symbols
    let opened = session.openedSymbol
    session.openedSymbol = nil
    if let opened, !session.visibleWhenOpened.contains(opened), list.contains(opened) {
      anchorRestored = true
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(60))
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { reader.scrollTo(opened, anchor: .center) }
      }
      return
    }
    guard let anchor = session.topRow[groupID ?? ""] ?? session.scrollAnchor,
          let wanted = list.firstIndex(of: anchor) else {
      anchorRestored = true
      return
    }
    session.restoreAnchorUsed = anchor
    Task { @MainActor in
      // 滚到位，量一眼，差几行补几行。
      //
      // 为什么补这一道：`scrollTo(_:anchor:.top)` 对齐的是**滚动容器**的上沿，
      // 而人看见的上沿在它下面（这一页的头部压着一截）。2026-09-21 在 iPhone 15
      // （iOS 26）上量到的偏差是固定的一截 261pt ≈ 4 行：请求 DOTUSDT 落地后，
      // 顶上完整露着的成了它后面第 3 个 BCHUSDT。既然量得出来，就按量到的补：
      // 请求「锚点往前 k 行」那一行，k 由上一轮的实测差值来。
      //
      // 补偿走的是整行的粒度——`scrollTo` 只认行，给不了半行。所以收敛判据是
      // 「差 0 行」，一轮不到位就再来一轮，最多四轮（固定偏差两轮就够）。
      //
      // 量的那把尺和记的时候是同一把（`FavoritesRenderedRows.topVisible`），
      // 这是整件事成立的前提：两头都问「顶上完整露着的是哪一行」。
      var target = wanted
      for round in 0..<4 {
        try? await Task.sleep(for: .milliseconds(round == 0 ? 80 : 40))
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { reader.scrollTo(list[target], anchor: .top) }
        // 等这一下真的落地：`scrollTo` 之后 `List` 要重新铺行、重新量位置，
        // 太早读到的是上一帧的位置。
        try? await Task.sleep(for: .milliseconds(220))
        guard let now = rows.topVisible(list), let at = list.firstIndex(of: now) else { break }
        let off = at - wanted
        if off == 0 { break }
        target = max(0, min(list.count - 1, target - off))
      }
      // 整行对上之后再补零头（P2.4）：离开时这一行的上沿离列表上沿差多少，回来就差多少。
      // `scrollTo` 只认整行，这一截只能直接去推 UIKit 那张表的 `contentOffset`。
      if session.topRow[groupID ?? ""] == anchor, let offset = session.topOffset[groupID ?? ""] {
        for _ in 0..<2 {
          guard alignAnchorPixels(anchor, offset: offset) else { break }
          try? await Task.sleep(for: .milliseconds(120))
        }
      }
      anchorRestored = true
      // 还原期间攒下的位置是过程量，落地之后重记一次才是人真正停在的那一行。
      noteScrollAnchor()
    }
  }

  /// 把锚点行推到离列表上沿正好 `offset` 的位置。推了返回 true，已经对齐或推不动返回 false。
  ///
  /// C-08 原来只还原到「顶上是哪一行」，那一行被滚到半截的零头丢了——人切回来看到的
  /// 表整体差了小半行到一行半（P2.4）。零头按像素补：量锚点行现在的上沿，和离开时
  /// 记下的差多少就把 `contentOffset` 推多少，推的范围夹在表能滚到的两头之内。
  @discardableResult
  private func alignAnchorPixels(_ anchor: String, offset: CGFloat) -> Bool {
    guard let scroller = rows.scroller, let y = rows.minY[anchor] else { return false }
    let delta = y - (rows.listTop + offset)
    guard abs(delta) >= 0.5 else { return false }
    let inset = scroller.adjustedContentInset
    let lowest = -inset.top
    let highest = max(lowest, scroller.contentSize.height + inset.bottom - scroller.bounds.height)
    var point = scroller.contentOffset
    let wanted = min(highest, max(lowest, point.y + delta))
    guard abs(wanted - point.y) >= 0.5 else { return false }
    point.y = wanted
    scroller.setContentOffset(point, animated: false)
    return true
  }

  /// 长按一行：先弹一张卡看看这东西现在什么样，再决定做什么（§4.1）。
  ///
  /// 卡是只读的，动作全在旁边那份菜单里——「打开 / 调整顺序 / 移到分类 / 取消自选」，
  /// 后两样和这一行左滑能做的是同两件事。
  /// 调整顺序时整个不挂：那时候长按是拖动排序，两种长按不能抢同一个手势。
  ///
  /// 「调整顺序」是这张菜单欠自己的一笔：长按整行原来是 `List` 自带的拖动排序
  /// （`onMove`），这张预览卡挂上去之后那半秒的长按被 `contextMenu` 先认走了，
  /// 同一个手势没法两件事都做。所以排序没有丢，只是退到菜单里——**长按弹出来的
  /// 第一屏上就有它**，点一下进调整顺序，那儿的长按仍旧是拖动排序。
  @ViewBuilder private func previewable(_ symbol: String, _ content: some View) -> some View {
    if let previews, !editing {
      content.contextMenu {
        Button("打开") { open(symbol) }
        Button("调整顺序") { toggleEditing() }
        Menu("移到分类") {
          ForEach(model.moveTargets, id: \.self) { name in
            Button(name) { assign([symbol], toCategory: name) }
          }
        }
        Button("取消自选", role: .destructive) { removeFavorites([symbol]) }
      } preview: {
        SymbolPreviewCard(symbol: symbol, info: model.info(for: symbol),
                          ticker: displayQuote(symbol), store: previews,
                          stale: !model.listing(of: symbol).hasLivePrice,
                          recentChange: { historyChange(symbol, hours: $0) })
          .environment(\.panelTheme, theme)
      }
    } else {
      content
    }
  }

  private func row(_ symbol: String, first: Bool) -> some View {
    let info = model.info(for: symbol)
    // 这一行还有没有实时价可言，判据只有「目录里查出来的那一档」（审查 B-06 / 复核项 4）。
    // 停牌 / 已下架 / 还没开盘 / 目录里根本没有这个代号的自选**照旧留在表里**，
    // 只是最后那口真价变灰，所有由实时价算出来的数（额、幅、涨跌幅）留空——
    // 不显示、也不解释。目录还没到的时候不算，那会把整页自选一起打灰。
    let stale = !model.listing(of: symbol).hasLivePrice
    let ticker = stale ? nil : displayQuote(symbol)
    let base = info?.base ?? SymbolInfo.placeholder(symbol: symbol).base
    let amplitude = ticker?.amplitude24h
    let volumeText = ticker.map { $0.quoteVolume.isFinite ? fmtVol($0.quoteVolume) : "—" } ?? "—"
    let amplitudeText = amplitude.map { toFixed($0, 2) + "%" } ?? "—"
    let value = ticker?.changePercent ?? .nan
    let trend = value.isFinite ? (value >= 0 ? theme.up : theme.down) : skin.ink4
    let nearestAlertText = alertDistanceText(symbol)
    let quote = quoteParts(symbol)
    // 行本身（徽章、字号、药丸、左右边距、发丝线）是和板块内品种表共用的 `LiuliSymbolRow`
    // （UI 审查 2026-09-24：两份手抄已经漂开）。这一页只管往里填什么。
    return LiuliSymbolRow(
      symbol: symbol, base: base, quote: quoteLabel(symbol),
      asset: info.map { SymbolClassifier.classify($0).asset },
      isNew: NewListingMark.shows(info), first: first,
      priceText: quote.priceText, priceInk: quote.priceInk, priceSkeleton: quote.skeleton,
      priceID: "favorites.price." + symbol,
      change: quote.change, changeText: quote.changeText, changePending: !stale,
      changeID: "favorites.change." + symbol,
      openID: "favorites.open." + symbol,
      onOpen: { selectOrOpen(symbol) }
    ) {
      // 按「离提醒线最近」排的时候，这一行让位给距离；这个品种没有在等的线就空着，
      // 不写「—」也不解释——空白本身就说明它不在这张单子上（只答远近，不答方向）。
      if sort == alertSortKey {
        Text(nearestAlertText ?? " ")
          .foregroundStyle(nearestAlertText == nil ? .clear : theme.amber)
      } else {
        // 写全称（2026-09-24 审查 6.4）：单字「额 / 幅」要猜。「幅」这里是 24h 振幅
        // （`amplitude24h`），不是涨跌幅——涨跌已经在右边那格，所以写「振幅」，和顶栏一个叫法。
        Text("成交额 " + volumeText + SymbolRowText.separator + "振幅 " + amplitudeText)
          .foregroundStyle(theme.ink3)
      }
    } accessory: {
      if !editing, sparkline {
        Sparkline(values: sparkValues(symbol), color: trend)
          .frame(width: 44, height: 24)
      }
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.32), value: displayQuote(symbol) != nil)
  }

  /// 走势线取的是详情那条历史订阅里的分钟线，不另开请求。
  private func sparkValues(_ symbol: String) -> [Double] {
    guard let bars = model.historyBars[symbol], bars.count > 4 else { return [] }
    let tail = Array(bars.suffix(60))
    let step = max(1, tail.count / 30)
    var picked = stride(from: 0, to: tail.count, by: step).map { tail[$0].close }
    if let last = tail.last?.close, picked.last != last { picked.append(last) }
    return picked
  }

  /// 右边那一列要填的东西：价、价的墨色、要不要骨架、涨跌（幅或额）。
  private func quoteParts(_ symbol: String)
    -> (priceText: String, priceInk: Color, skeleton: Bool, change: Double, changeText: String) {
    let ticker = displayQuote(symbol)
    let info = model.info(for: symbol)
    // 和 `row(_:first:)` 同一个判据（审查 B-06 / 复核项 4）。
    let stale = !model.listing(of: symbol).hasLivePrice
    let price = ticker?.last ?? .nan
    // 小数位由品种自己说（`priceDecimals`，按 `tickSize` 推）。目录里没有这个代号时走全 app 唯一那把
    // 梯子，不再在这一页写死 2 位（审查 B-07）。`fmtPrice` 而不是 `fmtNum`：0.0000004 这种
    // 合法极小价按 2 位四舍五入会写成 `0.00`，那等于说这东西不值钱。
    let decimals = info?.displayDecimals(for: price) ?? priceDecimalsFallback(price)
    let value: Double = stale ? .nan : (ticker?.changePercent ?? .nan)
    let change = amount && value.isFinite && price.isFinite && value > -100 ? price - price / (1 + value / 100) : value
    // 骨架块只表示「还在路上」。已下架 / 还没开盘的行不摆骨架，摆「—」，
    // 否则那块灰底会永远亮着，读起来像永远加载不完。
    let skeleton = !price.isFinite && !stale
    // 没有实时价时最后那口真价照旧摆着，只是退成次要文字色——不加标签、不弹窗。
    let priceInk: Color = stale ? skin.ink4 : theme.ink
    // 涨跌一律带「+ / −」（UI 审查 2026-09-24：全 app 跌幅一种写法，不再用小三角说方向）。
    // 还没到的涨跌和还没到的价格用同一种骨架：药丸只剩一块底，不写字。
    let changeText = amount ? SymbolRowText.signedAmount(change, decimals: decimals)
      : changePercentText(change)
    return (SymbolRowText.price(price, decimals: decimals), priceInk, skeleton, change, changeText)
  }

  // MARK: - 近 N 小时涨跌

  /// 长按预览卡上「1小时 / 4小时」那两格（审查 U9：行内展开收掉之后，这两格搬去了卡上）。
  /// 取数还是列表为迷你走势线订的那份逐分钟走势，所以只有看过的行才有。
  private func historyChange(_ symbol: String, hours: Int) -> Double? {
    let target = Int64(Date().timeIntervalSince1970 * 1000) - Int64(hours) * 3_600_000
    guard let bar = model.historyBars[symbol]?.last(where: { $0.openTime <= target }),
          target - bar.openTime < 60_000, bar.open > 0,
          let price = displayQuote(symbol)?.last else { return nil }
    return (price / bar.open - 1) * 100
  }
  private func selectOrOpen(_ symbol: String) {
    // 有砖划开着的时候，点行任何一处都是「先把砖收回去」，不是一次正常的点击——
    // 不接这一下，人划开之后想反悔只能再划一次（`SwipeDeleteProxy` 那只手的用意）。
    if openSwipe != nil { openSwipe = nil; return }
    // 调整顺序时点一下什么都不做：那时候整行是拖动的把手，点进图表只会把人带离正在排的表。
    if !editing { open(symbol) }
  }
  private func quoteAsset(_ symbol: String) -> String {
    model.info(for: symbol)?.quote ??
      SymbolInfo.placeholder(symbol: symbol).quote
  }
  /// 行里基础币后面那一小截。代号本身带分隔的（别家现货 `BTC-USD`）写成 `BTC/USD`，
  /// 币安那种连写的代号照旧只写计价币。
  private func quoteLabel(_ symbol: String) -> String {
    let quote = quoteAsset(symbol)
    return InstrumentID(symbol).symbol.contains("-") ? "/" + quote : quote
  }
  private func open(_ symbol: String) {
    // 先冻结名单再开图：这一刻的顺序就是人眼里那张表的顺序，之后行情再跳也不改它。
    onScanList(symbols)
    // 记下「从哪一行走的、走的时候屏幕上露着哪几行」，回来照它落位（§P3-6）。
    session.rememberOpen(symbol)
    // 目录里没有这个代号（刚上市、或者目录还在路上）时才临时造一行：小数位按最后
    // 看到的价退回那把共用的梯子，不再写死 2 位 / 0.01（审查 B-07）。真正的位数由
    // 行情页进图时那趟目录补查覆盖（`MarketModel.refreshInfo`，审查 B-06）。
    let quote = quoteAsset(symbol)
    let fallback = SymbolInfo(symbol: symbol,
                              base: SymbolInfo.placeholder(symbol: symbol).base,
                              quote: quote,
                              pricePrecision: priceDecimalsFallback(displayQuote(symbol)?.last ?? .nan),
                              tickSize: 0)
    model.pick(model.info(for: symbol) ?? fallback)
  }
  /// 移到分类。移错了也给五秒反悔（P2.7）：先记下每一只原来在哪一类，撤销时逐只放回。
  ///
  /// 挑的是还没开的预设分类时，这一下顺手把它开出来；撤销时它若因此空了就一并收掉，
  /// 反悔之后分类条和移之前一模一样。
  private func assign(_ symbols: [String], toCategory name: String) {
    let model = self.model
    moving = nil
    let existed = model.prefs.groups.contains { $0.name == name }
    let target = model.prefs.groups.first { $0.name == name }?.id
    let before = symbols.compactMap { model.favoriteSnapshot($0) }.filter { target == nil || $0.group != target }
    guard !before.isEmpty, let group = model.assign(before.map(\.symbol), toCategory: name) else { return }
    session.offerUndo("已移到「\(name)」") {
      before.forEach { model.assign($0.symbol, to: $0.group) }
      if !existed, !model.prefs.groupForSymbol.values.contains(group) { model.deleteGroup(group) }
    }
  }

  /// 取消自选 —— 这一页上**唯一**的移除口子（左滑、长按菜单，都走它）。
  ///
  /// 删自选没有二次确认（每加一道确认，正常的那一次就多一次打断），代价是删错了没得救。
  /// 所以改成「先删，再给五秒反悔」：删之前把每一个的位置、分组拍下来
  /// （`SymbolPrefs.snapshot`），屏幕底下那条提示条上挂一颗「撤销」，点了就照快照原样
  /// 放回去。还原走的是和删除同一条写入路径（`commit()`），落盘和同步都照常发生。
  ///
  /// 提示条不是「告诉你成功了」，而是「这一下还能反悔」。
  private func removeFavorites(_ list: [String]) {
    let model = self.model
    let snapshots = list.compactMap { model.favoriteSnapshot($0) }
    guard !snapshots.isEmpty else { return }
    Haptics.warning()
    list.forEach { model.removeFavorite($0) }
    session.offerUndo("已移除") {
      model.restoreFavorites(snapshots)
    }
  }

  // MARK: - 空自选

  private var emptyState: some View {
    VStack(spacing: Space.m) {
      Spacer(minLength: 0)
      Image(systemName: "plus")
        .font(.system(size: 17, weight: .medium)).foregroundStyle(skin.accent)
        .frame(width: Hit.min, height: Hit.min)
        .background(skin.glassThin, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
          .strokeBorder(skin.accent.opacity(0.35), lineWidth: 1))
      Text("还没有自选").font(skin.serif(TypeScale.body.size)).foregroundStyle(theme.ink)
      Button { search.openSearch() } label: {
        Text("添加品种").font(TypeScale.controlOn).foregroundStyle(theme.badgeInk)
          .frame(height: Hit.min).padding(.horizontal, Space.xl)
          .background(skin.accentGradient, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
          .overlay(alignment: .top) { skin.topHighlight(inset: 8) }
          .shadow(color: skin.accent.opacity(0.4), radius: 10, x: 0, y: 6)
      }.buttonStyle(.plain).padding(.top, Space.s)
      Spacer(minLength: 0)
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.top, Space.s).padding(.bottom, Space.s)
  }
}

// MARK: - 派生色板

/// 「琉璃」用到的所有材质与光，全部从当前皮肤种子推出来。
///
/// 浅色的底与光斑是唯一的例外：用户定的「天青 · 薄荷」，不是皮肤原色——
/// 皮肤原色在浅底上糊成一片，冷光才托得住玻璃。
/// 经典（白）又是例外中的例外：它的底就是那张 AICoin 白，直接用种子的 `ground`，
/// 光斑仍借青苔那三团。
private struct LiuliSkin {
  let theme: PanelTheme
  var seed: PaletteSeed { theme.seed }
  var dark: Bool { theme.dark }
  private var warm: Bool { Palette.isWarm(seed) }

  private static let sageGround: Hex = "#E9F3F1"
  private static let terraGround: Hex = "#F4EFEA"
  private static let sageLobes: [Hex] = ["#A9DDF3", "#BFEFD6", "#DCEFF6"]
  private static let terraLobes: [Hex] = ["#B5D9F1", "#F5D8C3", "#D3EDE0"]

  var ground: Color {
    if dark || Palette.isClassic(seed) { return Color(hex: seed.ground) }
    return Color(hex: warm ? Self.terraGround : Self.sageGround)
  }
  /// 光斑只在浅色下画（深色的三团已按用户要求去掉，见 `AuroraBackdrop`）。
  var lobes: [Color] {
    dark ? [accent, accentLift, Color(hex: seed.amber)]
         : (warm ? Self.terraLobes : Self.sageLobes).map { Color(hex: $0) }
  }
  /// 列表不再垫玻璃之后光斑直接穿过文字，整体收 30%——最亮的那一团正好压在
  /// 最上面两三行，那几行是最常看的。
  func lobeOpacity(_ index: Int) -> Double {
    guard dark else { return 0.9 * 0.7 }
    return (index == 2 ? 0.34 : 0.55) * 0.7
  }
  /// 底部同色收敛：从 22% 高度起往下渐渐回到底色，到底部盖住七成。
  /// 头部那一截极光完整保留，越往下行越多也越稳。
  var washStrength: Double { 0.7 }
  var grainOpacity: Double { dark ? 0.05 : 0.035 }

  var accent: Color { Color(hex: seed.accent) }
  var accentLift: Color { Self.lift(seed.accent, 0.42) }
  /// 液态药丸：acc2 → acc。
  var accentGradient: LinearGradient {
    LinearGradient(colors: [accentLift, accent], startPoint: .topLeading, endPoint: .bottomTrailing)
  }
  /// 玻璃：深色借近白的墨色，浅色借 `raised`（两套浅色种子的 raised 都是白）。
  private var pane: Color { Color(hex: dark ? seed.ink : seed.raised) }
  var glass: Color { pane.opacity(dark ? 0.065 : 0.64) }
  var glassThin: Color { pane.opacity(dark ? 0.045 : 0.46) }
  var edgeSoft: Color { pane.opacity(dark ? 0.12 : 0.62) }
  var rule: Color { Color(hex: seed.ink).opacity(dark ? 0.11 : 0.09) }
  /// 比 ink3 再弱一档，给上标数字、单位、微标签。
  var ink4: Color { Color(hex: seed.ink3).opacity(0.7) }

  /// 玻璃顶上那一线高光。
  func topHighlight(inset: CGFloat) -> some View {
    Capsule().fill(pane.opacity(dark ? 0.3 : 0.9))
      .frame(height: 1).padding(.horizontal, inset)
  }

  /// 标题字体。原型上是宋体，但 iOS 装机量里没有任何一支简体中文衬线体可用——
  /// `UIFont.familyNames` 里既没有 Songti SC 也没有 Kaiti SC，New York 只管拉丁字母，
  /// 唯一在机的明朝体 Hiragino Mincho ProN 缺「选」「这」「栏」这些简体字，混排会崩。
  /// 既然说好了不打包字体文件，这里就老实用 `.serif`：拉丁走 New York，中文走系统字，
  /// 靠字号与字距把标题撑起来。
  func serif(_ size: CGFloat) -> ScaledFont { ScaledFont(size, .medium, design: .serif) }

  func lift(_ hex: Hex, _ amount: Double) -> Color { Self.lift(hex, amount) }

  /// 往亮里提一档：色相不动，饱和收一点、明度往上走——原型里 acc2 和 acc 的关系。
  private static func lift(_ hex: Hex, _ amount: Double) -> Color {
    let rgba = hex.rgba
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(red: rgba.r, green: rgba.g, blue: rgba.b, alpha: 1)
      .getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    return Color(hue: Double(h), saturation: Double(s) * (1 - amount * 0.6),
                 brightness: Double(b) + (1 - Double(b)) * amount)
  }
}

// MARK: - 底：三团会动的光

private struct AuroraBackdrop: View {
  let skin: LiuliSkin
  let reduceMotion: Bool
  @State private var drift = false

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width, height = geometry.size.height
      ZStack(alignment: .topLeading) {
        skin.ground
        // 深色下不画光斑：用户看过真机说「深色模式下有两个光晕影响视觉，直接去掉」——
        // 深底上那两团强调色的光压在最上面几行字上，像屏幕没擦干净。素底加颗粒就够。
        if !skin.dark {
          lobe(0, size: 300, x: -95, y: -80, seconds: 22)
          lobe(1, size: 250, x: width - 170, y: 240, seconds: 27)
          lobe(2, size: 280, x: -70, y: height - 230, seconds: 31)
          LinearGradient(stops: [
            .init(color: skin.ground.opacity(0), location: 0.22),
            .init(color: skin.ground.opacity(skin.washStrength), location: 1)],
            startPoint: .top, endPoint: .bottom)
            .frame(width: width, height: height)
        }
        if let grain = Grain.image {
          grain.resizable(resizingMode: .tile).opacity(skin.grainOpacity)
        }
      }
      .frame(width: width, height: height)
    }
    .allowsHitTesting(false)
    .onAppear { if !reduceMotion { drift = true } }
  }

  /// 漂移只动 `offset` / `scale`，交给渲染线程去跑，不会让列表每帧重建。
  private func lobe(_ index: Int, size: CGFloat, x: CGFloat, y: CGFloat, seconds: Double) -> some View {
    let color = skin.lobes[index]
    let peak = skin.lobeOpacity(index)
    return RadialGradient(
      gradient: Gradient(stops: [
        .init(color: color.opacity(peak), location: 0),
        .init(color: color.opacity(peak * 0.55), location: 0.45),
        .init(color: color.opacity(0), location: 1)]),
      center: .center, startRadius: 0, endRadius: size / 2)
      .frame(width: size, height: size)
      .scaleEffect(drift ? 1.08 : 1)
      .offset(x: x + (drift ? 18 : 0), y: y + (drift ? -26 : 0))
      .animation(reduceMotion ? nil
                 : .easeInOut(duration: seconds).repeatForever(autoreverses: true), value: drift)
  }
}

/// 一张 96×96 的灰噪点，平铺当颗粒。只生成一次。
@MainActor private enum Grain {
  static let image: Image? = {
    let side = 96
    var bytes = [UInt8](repeating: 0, count: side * side)
    var state: UInt64 = 0x2545_F491_4F6C_DD1D
    for index in bytes.indices {
      state ^= state << 13; state ^= state >> 7; state ^= state << 17
      bytes[index] = UInt8(truncatingIfNeeded: state >> 33)
    }
    guard let provider = CGDataProvider(data: Data(bytes) as CFData),
          let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8,
                              bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                              provider: provider, decode: nil, shouldInterpolate: false,
                              intent: .defaultIntent) else { return nil }
    return Image(decorative: image, scale: 1)
  }()
}

// MARK: - 走势线与小三角

private struct Sparkline: View {
  let values: [Double]
  let color: Color

  var body: some View {
    GeometryReader { geometry in
      let size = geometry.size
      let points = points(in: size)
      if points.count > 1 {
        ZStack {
          shape(points, closing: size.height).fill(
            LinearGradient(colors: [color.opacity(0.28), color.opacity(0)],
                           startPoint: .top, endPoint: .bottom))
          shape(points, closing: nil).stroke(
            color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
          if let last = points.last {
            Circle().fill(color).opacity(0.18).frame(width: 10, height: 10).position(last)
            Circle().fill(color).frame(width: 4.4, height: 4.4).position(last)
          }
        }
      }
    }.accessibilityHidden(true)
  }

  private func points(in size: CGSize) -> [CGPoint] {
    guard values.count > 1 else { return [] }
    let low = values.min() ?? 0, high = values.max() ?? 0
    let span = high - low
    return values.enumerated().map { index, value in
      let ratio = span == 0 ? 0.5 : (value - low) / span
      return CGPoint(x: CGFloat(index) / CGFloat(values.count - 1) * (size.width - 4) + 2,
                     y: size.height - 3 - CGFloat(ratio) * (size.height - 7))
    }
  }

  private func shape(_ points: [CGPoint], closing bottom: CGFloat?) -> Path {
    var path = Path()
    path.move(to: points[0])
    for point in points.dropFirst() { path.addLine(to: point) }
    if let bottom, let last = points.last {
      path.addLine(to: CGPoint(x: last.x, y: bottom))
      path.addLine(to: CGPoint(x: points[0].x, y: bottom))
      path.closeSubpath()
    }
    return path
  }
}

/// Keep category controls independent of row-price refreshes.
/// Keep the header's identity tied to folders/editing/theme, not row prices.
private struct FavoritesHeader<Content: View>: View, Equatable {
  let prefs: SymbolPrefs
  let editing: Bool
  let more: Bool
  let theme: PanelTheme
  let width: CGFloat
  let content: Content
  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.prefs == rhs.prefs && lhs.editing == rhs.editing && lhs.more == rhs.more
      && lhs.theme == rhs.theme && lhs.width == rhs.width
  }
  var body: some View { content }
}

// MARK: - 正在做的那次调整顺序

/// 自选页上「他这会儿正在做的事」：调整顺序开着没有、调整期间冻住的那份报价、
/// 表停在哪一行、以及「已移除 · 撤销」那条提示。
///
/// 2026-09-24 批量编辑（勾选多行 + 编辑条）撤了（「不做」清单），勾选那一份跟着删掉；
/// 下面的历史照原样留着，讲的是「为什么住在宿主手里」，对调整顺序同样成立。
///
/// **为什么不是 `FavoritesView` 自己的 `@State`**：底栏是常驻标签栏，
/// `MainScreen.portraitBody` 里那个 `switch tab` 只留当前这一格，别的页整个拆掉，
/// 自选页每切走一次就重建一遍——挂在视图上的东西跟着一起死。用户复现的就是这条路：
/// 「…」→「编辑自选」→ 勾一个品种 → 切到设置页什么都不碰 → 切回来，编辑模式自己
/// 退了、勾全没了。`68aa979` 修的是另一条路（切行情线路把报价表清空，顺手退出编辑），
/// 最常走的这条还漏着。排序口径、升降序、展开收起早就因为同一件事搬去了持久层，
/// 唯独这一组被落下。
///
/// **为什么又不落盘**：半做完的批量选择是「一个正在做的动作」，不是「他改出来的
/// 习惯」——下次冷启动进来还举着三个勾、底下还挂着「删除」，比丢了更吓人。所以它
/// 住在宿主（`MainScreen`）手里，活过视图的一次次重建（切页签、进出横屏画线工作台、
/// 切后台再回来），但只活在这一次使用里：不进 `Prefs`、不进 `PersonalFileStorage`、
/// 不进 `PersonalSyncCodec.fields`。换账号时由宿主清掉——那时候整张表都不是他的了。
@MainActor @Observable final class FavoritesEditSession {
  /// 调整顺序开着没有。只由用户自己的动作进出（「调整顺序」/「完成」/ 换账号）。
  var editing = false
  /// 进编辑那一刻冻住的报价。编辑时整页读它而不是读实时报价，行布局才不会
  /// 随每批 WS 报价重排（见 `FavoritesView.displayQuote`）。
  var quotes: [String: Ticker] = [:]
  /// 他停在表的哪一行（审查 C-08）。
  ///
  /// 存的是**品种代号**，不是滚动偏移量：一屏能放几行随字号、随
  /// 机型变，像素位置换个环境就对不上，而「他正盯着 APTUSDT 那一行」换到哪儿都成立。
  /// 和编辑会话同住一处、同一个理由——这是「一次使用里的落脚点」，不是跟着账号走的
  /// 习惯：冷启动理应从第一行看起，所以它不进 `Prefs`、不落盘。
  /// 分类切换会把它清掉：换了一类，上一类停在哪儿没有意义。
  var scrollAnchor: String?

  func begin(quotes: [String: Ticker]) {
    self.quotes = quotes
    editing = true
  }

  func end() {
    editing = false
    quotes.removeAll()
  }

  // ---------------------------------------------------------------- 已移除 · 撤销

  /// 刚说出口的那句话，和「撤销」那一下要干什么。
  ///
  /// 屏幕底下那条提示条只有一条，住在宿主上（`MainScreen.say`）；撤销具体怎么撤
  /// 是自选页的事（要还原到哪一位、哪一类）。所以这儿只当传声筒：
  /// 自选页把话和动作放进来，宿主念出去。
  private(set) var undoText = ""
  private(set) var undoAction: (() -> Void)?
  /// 每放一次自增。宿主盯的是这个计数而不是那句话本身——同一句「已移除」连着说两遍，
  /// `onChange(of: String)` 是不会响的。
  private(set) var undoStamp = 0

  func offerUndo(_ text: String, _ action: @escaping () -> Void) {
    undoText = text
    undoAction = action
    undoStamp += 1
  }

  // ---------------------------------------------------------------- 手指按着时不重排

  /// 手指按在列表上的那一刻，顺序冻在这一份上（§P3-5）。
  ///
  /// 价格和涨跌照常刷新，只有「谁排在谁前面」不动——手指底下的那一行不许在按下去到
  /// 抬起来之间换成别人。抬手之后 `symbols` 自己会用最新的那一份重排。
  private(set) var heldOrder: [String]?
  /// 按下去的时刻。收不到抬手时靠它兜底（见 `frozen`）。
  private(set) var heldAt = Date.distantPast
  /// 列表正在滚（含甩出去之后的惯性）。
  var scrolling = false

  /// 现在该不该冻着。
  ///
  /// 手指按着、或者列表还在滚，都算「正在摸这张表」。`heldAt` 是兜底：那一下被
  /// `List` 自己的手势抢走时抬手事件可能到不了这儿，超过 30 秒就当它早就抬了，
  /// 免得一整页永远冻住。
  var frozen: Bool {
    if heldOrder != nil, Date().timeIntervalSince(heldAt) < 30 { return true }
    return scrolling
  }

  func hold(_ order: [String]) {
    guard heldOrder == nil else { return }
    heldOrder = order
    heldAt = Date()
  }

  func release() {
    heldOrder = nil
    heldAt = .distantPast
  }

  // ---------------------------------------------------------------- 回到原来那一行

  /// 离开这一页时，每一类各自顶上露着的是哪一行。
  var topRow: [String: String] = [:]
  /// 和 `topRow` 同一时刻记下的：那一行的上沿离列表上沿多少 pt（P2.4）。
  /// 只在这一次使用里、同一台设备同一个字号下拿来补零头，所以存像素不违背上面
  /// 「存代号不存偏移量」的理由——代号决定落到哪一行，这个数只管那一行里的零头。
  var topOffset: [String: CGFloat] = [:]
  /// 列表上这会儿露着哪几行。整页被拆掉时它会被逐行的 `onDisappear` 清空，
  /// 所以 `topRow` 只在算得出结果时才更新——空了就保留最后一个好值。
  var visibleRows = Set<String>()
  /// 最近从这一页点进图的是哪一只，以及点进去那一刻屏幕上露着哪几行。
  /// 回来时前者不在后者里，就说明那一行已经被滚出视野了，得专门滚到它。
  var openedSymbol: String?
  var visibleWhenOpened = Set<String>()
  /// 上一次还原滚动位置时真正瞄的那一行。只给诊断串看，产品逻辑不读它。
  var restoreAnchorUsed: String?

  /// 某一行进出视野。只攒「露过面的有哪些」，给「点进图的那只当时在不在屏幕上」用。
  ///
  /// 这儿原来还顺手算一遍 `topRow`，2026-09-21 撤掉了：`onAppear` 说的是「铺出来了」，
  /// 不是「看得见」，而且整页拆的时候每一行都会走一遍 `onDisappear`，
  /// 算出来的「顶上那一行」会被一路推到表尾。现在 `topRow` 由
  /// `FavoritesView.noteScrollAnchor` 按行的真实位置写，口径和还原那头一致。
  func rowVisible(_ symbol: String, _ on: Bool, group: String, order: [String]) {
    if on { visibleRows.insert(symbol) } else { visibleRows.remove(symbol) }
  }

  func rememberOpen(_ symbol: String) {
    openedSymbol = symbol
    visibleWhenOpened = visibleRows
  }
  /// 换分类、换账号时把落脚点一起丢掉。
  func forgetScrollAnchor() { scrollAnchor = nil }
}

/// 自选表排好的那一份顺序，连同算它用的输入（审查 C3）。
///
/// 输入一样，结果就一样：名单本身、排序口径、升降序、涨跌额还是涨跌幅、在不在编辑、
/// 报价版本（`SymbolPickerModel.quoteRevision`），以及按「离提醒线最近」排时的那几条提醒。
/// 只记最近一份——这一页同一时刻只画一类、一种排法。
@MainActor final class FavoritesSortCache {
  struct Key: Equatable {
    var source: [String]
    var sort: String
    var ascending: Bool
    var amount: Bool
    var editing: Bool
    var quotes: UInt64
    var alerts: [KanpanCore.Alert]
  }
  private var key: Key?
  private var cached: [String] = []
  func rows(for key: Key) -> [String]? { self.key == key ? cached : nil }
  func store(_ rows: [String], for key: Key) { self.key = key; cached = rows }
}

/// 列表现在铺着哪几行，以及由它算出来的落脚点（审查 C-08）。
///
/// 做成一个**普通的引用盒子、不被任何人观察**是故意的：滚动时每露一行就要写一次，
/// 写进 `@State` 或 `@Observable` 等于把整张表重画一遍，而这一页上跑着实时报价。
/// 它只在整页 `onDisappear` 那一刻被读一次，把落脚点交给 `FavoritesEditSession`。
@MainActor final class FavoritesRenderedRows {
  /// 每一行的上沿在屏幕坐标里的位置。比 `listTop` 还小就是被顶上切掉了。
  ///
  /// 「铺着」和「看得见」差着一截，而落脚点要的是后者：2026-09-21 在 iPhone 15 上
  /// 量到，手指滚停下来时这两者恰好重合（上面一行都没多铺），`scrollTo` 落地之后
  /// 却多铺了三四行，只数「铺着的第一行」就会把位置整整推下去几格。
  /// 有了这份位置表，两头问的就都是同一件事：**现在顶上完整露着的是哪一行**。
  var minY: [String: CGFloat] = [:]
  /// 顶上露着的那一行，也就是要交出去的落脚点。
  var anchor: String?
  /// 落脚点那一行的上沿离列表上沿多少 pt（P2.4）。
  var anchorOffset: CGFloat = 0
  /// `List` 背后那张 UIKit 表。行里的 `FavoritesScrollerProbe` 上窗时报上来，
  /// 只给还原时补像素零头用。
  weak var scroller: UIScrollView?
  /// 整页开始拆了。拆的过程里每一行都会再报一次位置，那些位置不作数——
  /// 边拆边算会把落脚点一路推到表尾，刚记下的那个当场作废。
  var teardown = false

  /// 列表自己的上沿在屏幕上的位置。比它还高的行就是被顶上切掉的那些。
  var listTop: CGFloat = 0

  /// 按表的顺序取顶上第一个**完整露着**的品种。
  ///
  /// 被上沿切掉半格的那行不算：人眼里顶上那一行就是第一整行，
  /// 用例读的也是「整个框都在屏幕里」的第一行，两边口径要一致。
  func topVisible(_ order: [String]) -> String? {
    order.first { (minY[$0] ?? -.greatestFiniteMagnitude) >= listTop - 0.5 }
  }
}

/// 从行里往上找 `List` 背后那张 `UICollectionView`，报给 `FavoritesRenderedRows`（P2.4）。
///
/// 不画东西、不接触摸，只在上窗那一刻顺着父视图找一次。
private struct FavoritesScrollerProbe: UIViewRepresentable {
  let rows: FavoritesRenderedRows

  func makeUIView(context: Context) -> ProbeView {
    let view = ProbeView()
    view.isUserInteractionEnabled = false
    view.rows = rows
    return view
  }

  func updateUIView(_ view: ProbeView, context: Context) { view.rows = rows }

  final class ProbeView: UIView {
    weak var rows: FavoritesRenderedRows?

    override func didMoveToWindow() {
      super.didMoveToWindow()
      guard window != nil, let rows, rows.scroller == nil else { return }
      var view = superview
      while let current = view {
        if let table = current as? UICollectionView { rows.scroller = table; return }
        view = current.superview
      }
    }
  }
}

/// 只报「有没有手指按在这张表上」，从不认领这一下。
///
/// 为什么不拿 `DragGesture(minimumDistance: 0)` 去报：它会跟 `List` 自己的滚动、左滑、
/// 长按预览抢同一串触摸。抢输的那一次 SwiftUI 直接把它取消掉，`onEnded` 一次都不来，
/// 于是「冻住」再也解不开——手指早抬了，表还锁着。
///
/// 这只识别器永远停在 `.possible`：不进 `.began`，所以既不会赢、也不会让别人输
/// （`cancelsTouchesInView = false` 连触摸都不截），只是把 `touchesBegan / Ended`
/// 原样转出来。iOS 18 起 SwiftUI 直接收 `UIGestureRecognizer`（`UIGestureRecognizerRepresentable`），
/// 不用再包一层 `UIViewRepresentable`。
final class TouchWatchRecognizer: UIGestureRecognizer {
  var onChange: ((Bool) -> Void)?
  /// 还按着几根手指。多指分别按下、分别抬起时按个数配平，最后一根抬了才算「松开」。
  private var live = 0

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    live += touches.count
    if live > 0 { onChange?(true) }
  }
  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { drop(touches.count) }
  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { drop(touches.count) }
  override func reset() {
    live = 0
    onChange?(false)
  }

  private func drop(_ count: Int) {
    live = max(0, live - count)
    if live == 0 { onChange?(false) }
  }
}

struct TouchWatcher: UIGestureRecognizerRepresentable {
  var onChange: (Bool) -> Void

  func makeUIGestureRecognizer(context: Context) -> TouchWatchRecognizer {
    let recognizer = TouchWatchRecognizer()
    recognizer.cancelsTouchesInView = false
    recognizer.delaysTouchesBegan = false
    recognizer.delaysTouchesEnded = false
    recognizer.onChange = onChange
    return recognizer
  }

  func updateUIGestureRecognizer(_ recognizer: TouchWatchRecognizer, context: Context) {
    recognizer.onChange = onChange
  }

  func handleUIGestureRecognizerAction(_ recognizer: TouchWatchRecognizer, context: Context) {}
}

/// 记下「设置」「排序」两颗按钮的位置，好让浮层菜单吊在它们下面。
private struct MenuAnchors: PreferenceKey {
  static let defaultValue: [String: Anchor<CGRect>] = [:]
  static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
    value.merge(nextValue()) { _, new in new }
  }
}

/// 冷启动落在自选页、但自选表还在路上（登录用户的档案要等 `account.restore()`）
/// 那一小段里铺的底：就是自选页自己的那层底，不画空态（「这一栏还空着」只会闪一下）。
struct FavoritesLandingPlaceholder: View {
  @Environment(\.panelTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    AuroraBackdrop(skin: LiuliSkin(theme: theme), reduceMotion: reduceMotion)
      .ignoresSafeArea()
      .accessibilityIdentifier("favorites.landing")
  }
}
