import SwiftUI
import UIKit
import KanpanCore
import KanpanData

/// 自选分类页 ——「琉璃」。
///
/// 底是三团会慢慢漂的光，上面浮着玻璃：按钮是玻璃圆片，分类是玻璃胶囊，整张列表
/// 是一张玻璃纸。颜色一律从当前皮肤的种子推（见 `LiuliSkin`），View 里不写死
/// 十六进制——唯一的例外是浅色那组「天青·薄荷」光斑，那是浅色底下专配的一组冷光，
/// 不属于任何一套皮肤。
///
/// 功能与原来那一版逐条对齐：分类切换/新建/重命名/删除/溢出、添加品种、批量编辑、
/// 排序、展开详情、右滑删除、长按拖动、进图表，`accessibilityIdentifier` 一个没换。
struct FavoritesView: View {
  @Bindable var model: SymbolPickerModel
  /// 正在进行的那次批量编辑。它住在宿主手里，不是这一页自己的 `@State`——
  /// 理由见 `FavoritesEditSession`。
  var session: FavoritesEditSession
  /// 搜索页的历史词仓。自选页自己开搜索页（见 `searching`），所以得跟着传进来。
  var history: SearchHistory
  /// 这一页上「他摆出来的样子」存在哪：排序口径、方向、涨跌额/幅、迷你走势、展开的行。
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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.panelTheme) private var theme
  /// 「查看全部 N 个品种」落到品种整页时才用得上；平时加品种一律走搜索页。
  @State private var adding = false
  /// 搜索页盖层。加自选统一在这儿做（用户 2026-09-18 定的），不用先跳回行情页。
  @State private var searching = false
  /// 品种整页是从搜索页「查看全部」进来的吗。是的话它那颗返回退回搜索页，
  /// 而不是一路退回自选页——人是从搜索页走过来的，返回就该原路走回去。
  @State private var addingFromSearch = false
  @State private var more = false
  @State private var sorting = false
  @State private var afterMore: (() -> Void)?
  @State private var moreTask: Task<Void, Never>?
  @State private var editingName = false
  @State private var renamedID: String?
  @State private var name = ""
  // 编辑模式 / 勾中的那几行 / 编辑期间冻住的报价：三项都在 `session` 上，写法照旧
  // 是直接赋值（`editing = false`、`selection.removeAll()`），调用处一个字没改。
  private var editing: Bool {
    get { session.editing }
    nonmutating set { session.editing = newValue }
  }
  private var editQuotes: [String: Ticker] {
    get { session.quotes }
    nonmutating set { session.quotes = newValue }
  }
  private var selection: Set<String> {
    get { session.selection }
    nonmutating set { session.selection = newValue }
  }
  /// 已经替它开了历史订阅的品种。页面整体消失时要逐个关掉——
  /// 行自己的 `onDisappear` 在整页被拆掉时不保证会走到。
  @State private var historyOn = Set<String>()
  /// 现在铺着哪几行，以及由它算出来的落脚点（审查 C-08）。盒子是**不被观察**的，
  /// 理由见 `FavoritesRenderedRows`。
  @State private var rows = FavoritesRenderedRows()
  /// 落脚点已经还原过了吗。还原之前不记新的——列表刚铺开时最上面那几行会先
  /// `onAppear`，那时候记下来的是「第一行」，正好把要还原的那个盖掉。
  @State private var anchorRestored = false
  // 这张表「他摆成了什么样」：排序口径、升降序、涨跌额还是涨跌幅、画不画迷你走势线、
  // 哪几行展开着详情。
  //
  // 这几项一路搬过两次家。最早是 `@State`——底栏换成常驻标签栏之后，自选页每切走
  // 一次就整个重建，排好的顺序当场退回「自选顺序」，人回来还得再排一遍。于是搬去了
  // `@AppStorage`，注释写的是「这台机器上这张表想怎么看，跟着机器走，不跟账号走」。
  //
  // **「跟着机器走」这条判断 2026-09-19 推翻了**：判据不是「它在不在设置页上」，而是
  // 「这是他改出来的习惯，还是这个对象自己的属性」。按成交额排、看涨跌额、把某几行
  // 展开着，全是前者——换台设备登同一个账号，这张表就该还是这个样子，而同一台机器上
  // 换个人登进来，就不该还是上一个人排的那个顺序。裸 `@AppStorage` 两头都反了。
  // 现在它们住在 `Prefs` 里（见 `Prefs` 末尾那一节），随账号同步，未登录记在访客档案。
  //
  // 写法照旧是直接赋值（`sort = "name"`、`expanded.removeAll()`），只是底下换成了
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
  private var expanded: Set<String> {
    get { store.prefs.favoritesExpanded }
    nonmutating set { store.update { $0.favoritesExpanded = newValue } }
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
      session.forgetScrollAnchor()
      rows.rendered.removeAll()
      rows.anchor = nil
      anchorRestored = true
    }
    group = id
  }
  /// 真正画出来的那一类：存的那个可能已经被删了，`SymbolPrefs.group(_:)` 退回第一类。
  private var selected: String? { model.prefs.group(group) }
  private var groupID: String? { selected }
  private var skin: LiuliSkin { LiuliSkin(theme: theme) }
  private var symbols: [String] {
    let source = model.prefs.favorites(in: groupID)
    var rows = source
    if !editing, sort != "custom" {
      rows.sort { a, b in
        if sort == "name" { return ascending ? a < b : a > b }
        let x = sortValue(a)
        let y = sortValue(b)
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
    .safeAreaInset(edge: .bottom, spacing: 0) { if editing { editBar } }
    .tint(theme.amber)
    .task { await model.appear() }
    .onAppear {
      // 这一页每切走一次就整个重建（`MainScreen.portraitBody` 里的 `switch tab`）。
      // 编辑还开着的时候重新露面，那份冻住的报价跟着 `session` 活了下来，但它停在
      // 切走的那一刻：离开期间新加进来的品种在它里面没有条目，行里的价格就空着。
      // 这儿按手上最新的报价重铺一次——刚重建完，没有「布局跟着 WS 抖」的顾虑。
      if editing, !model.tickers.isEmpty { editQuotes = model.tickers }
    }
    .onDisappear {
      // 走之前把落脚点交给宿主（审查 C-08）。切回来时这一页整个重建，
      // `session` 是这一页之外唯一还活着的东西。
      if let anchor = rows.anchor { session.scrollAnchor = anchor }
      moreTask?.cancel()
      model.disappear()
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
      // `editing = false` 加清空 `selection`，人正批量选着品种准备改分类，别处切一次
      // 线路，选择当场没了。编辑模式和多选只由用户自己的动作退出。
      // 编辑时那份冻结的报价（`editQuotes`）也别清，等新报价上来原地续上就是了。
      if !empty, editing { editQuotes = model.tickers }
    }
    .alert(renamedID == nil ? "新建分类" : "重命名分类", isPresented: $editingName) {
      TextField("分类名称", text: $name)
      Button("取消", role: .cancel) { }
      Button("保存") {
        if let renamedID { model.renameGroup(renamedID, name: name) }
        else if let id = model.createGroup(name) { select(id) }
      }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    .fullScreenCover(isPresented: $searching) {
      SymbolSearchView(model: model, history: history, redUp: redUp,
                       onClose: { searching = false },
                       // 搜到的比一屏多时那行「查看全部」：交给品种整页，查询词跟着过去。
                       onAll: { searching = false; addingFromSearch = true; adding = true },
                       onPicked: { searching = false },
                       // 星点亮之后跟着品种走：它落进哪一组就切到哪一组，
                       // 收起搜索页第一眼就能看见刚加的那一行。
                       onStarred: { if let group = model.prefs.groupForSymbol[$0] { select(group) } },
                       onVisible: onVisible,
                       onRowVisibility: onRowVisibility)
    }
    .sheet(isPresented: $adding) {
      // 「查看全部」走进来的那一趟，返回要退回搜索页（词留着）；别的路进来的照旧关掉。
      SymbolPickerView(model: model, redUp: redUp, onClose: {
        adding = false
        if addingFromSearch { addingFromSearch = false; searching = true }
      }, onSelect: { info in
        model.addFavorite(info.symbol, info: info)
        if let group = model.prefs.groupForSymbol[info.symbol] { select(group) }
        adding = false; addingFromSearch = false
      }, onVisible: onVisible, onRowVisibility: onRowVisibility)
    }
    .sheet(item: $moving) { request in
      NavigationStack {
        List {
          ForEach(model.prefs.groups) { group in Button(group.name) { assign(request.symbols, to: group.id) } }
        }.scrollContentBackground(.hidden).background(theme.app)
          .navigationTitle("移到分类").navigationBarTitleDisplayMode(.inline)
          .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { moving = nil } } }
      }.presentationDetents([.medium, .large]).tint(theme.amber)
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
            Text("完成").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.amber)
              .frame(maxWidth: .infinity).frame(height: 42)
              .background(skin.glassThin, in: Capsule())
              .overlay(Capsule().strokeBorder(skin.edgeSoft, lineWidth: 0.5))
              .frame(height: 46).contentShape(Rectangle())
          }.buttonStyle(.plain)
            .accessibilityLabel("完成编辑").accessibilityIdentifier("favorites.editToggle")
        } else {
          searchField
        }
        // 它装的是编辑自选、新建/重命名/删除分类、迷你走势开关——全是**这一页**的事，
        // 所以记号用「…」而不是齿轮：齿轮在标签栏最右边，那颗才是整个 app 的设置。
        circleButton("ellipsis", label: "自选菜单", id: "favorites.more") { more = true }
          .anchorPreference(key: MenuAnchors.self, value: .bounds) { ["more": $0] }
      }
      groupStrip
    }
    .padding(.horizontal, 12)
    .padding(.bottom, 2)
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
    Button { searching = true } label: {
      HStack(spacing: 7) {
        VectorIcon.search(16).foregroundStyle(theme.ink3)
        Text("搜索品种").font(.system(size: 15)).foregroundStyle(theme.ink3)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 15)
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
  }

  // MARK: - 分类分段器

  /// 一格分类占多宽：15 的名字 + 左右各 19 的内边。
  private func tabWidth(_ group: FavoriteGroup) -> CGFloat {
    let text = (group.name as NSString)
      .size(withAttributes: [.font: UIFont.systemFont(ofSize: 15, weight: .medium)]).width
    return min(150, max(72, text + 38))
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
    return Button { select(id); selection.removeAll(); expanded.removeAll() } label: {
      // 名字后面原来还挂着一个上标的数量，用户 2026-09-18 让去掉——数量在列表上面
      // 那行「N 个品种」已经写着了，格子里只留名字更干净。数量仍留在朗读标签里。
      Text(title).font(.system(size: 15, weight: .medium))
        .lineLimit(1).truncationMode(.middle)
        .foregroundStyle(on ? Color.white : theme.ink2)
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
      .background(theme.app, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(skin.edgeSoft, lineWidth: 0.5))
      .shadow(color: .black.opacity(0.14), radius: 20, y: 10)
      .offset(x: x, y: rect.maxY + 8)
      .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
  }

  // MARK: - 更多

  private func runMore(_ action: @escaping () -> Void) {
    afterMore = action; more = false
  }

  private func moreRow(_ title: String, icon: String, id: String, destructive: Bool = false,
                       action: @escaping () -> Void) -> some View {
    Button { runMore(action) } label: {
      Label(title, systemImage: icon).frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .padding(.horizontal, 16).contentShape(Rectangle())
    }.buttonStyle(.plain).foregroundStyle(destructive ? Color(hex: Palette.chart(theme.seed, redUp: false).down) : theme.ink)
      .accessibilityIdentifier(id)
  }

  /// 设置菜单。以前头一段是「更多分类」——分类条排不下的那几个；现在分类条自己
  /// 能滚，一个都不会被挤掉，这一段就撤了。
  private var moreList: some View {
    ScrollView {
      VStack(spacing: 0) {
        moreRow("新建分类", icon: "folder.badge.plus", id: "favorites.newGroup") {
          renamedID = nil; name = ""; editingName = true
        }
        moreRow(editing ? "完成编辑" : "编辑自选", icon: "pencil", id: "favorites.edit") { toggleEditing() }
        moreRow(sparkline ? "隐藏迷你走势" : "显示迷你走势", icon: sparkline ? "waveform.slash" : "waveform",
                id: "favorites.sparkline") { sparkline.toggle() }
        if let group = currentGroup {
          moreRow("重命名当前分类", icon: "square.and.pencil", id: "favorites.renameGroup") {
            renamedID = group.id; name = group.name; editingName = true
          }
          moreRow("删除当前分类", icon: "trash", id: "favorites.deleteGroup", destructive: true) { model.deleteGroup(group.id) }
        }
      }.padding(.vertical, 6)
    }.font(.system(size: 14))
      .frame(height: min(430, CGFloat(3 + (currentGroup == nil ? 0 : 2)) * 46 + 12))
  }

  /// 当前选中的那一组；没有（比如一条自选都还没加）时菜单里不摆重命名/删除。
  private var currentGroup: FavoriteGroup? { model.prefs.groups.first(where: { $0.id == selected }) }

  private func toggleEditing() {
    if editing { session.end() } else { session.begin(quotes: model.tickers) }
    expanded.removeAll()
  }

  // MARK: - 排序行

  private var sortBar: some View {
    HStack(spacing: 0) {
      Text("\(symbols.count) 个品种").font(.system(size: 10.5)).foregroundStyle(skin.ink4)
      Spacer(minLength: 0)
      Button { sorting = true } label: {
        HStack(spacing: 4) {
          Text(sortTitle).font(.system(size: 11)).foregroundStyle(theme.ink3)
          Image(systemName: sort == "custom" ? "arrow.up.arrow.down"
                : (ascending ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill"))
            .font(.system(size: 7)).foregroundStyle(theme.amber)
        }.frame(height: 28).contentShape(Rectangle())
      }.buttonStyle(.plain).disabled(editing)
        .accessibilityLabel("排序方式").accessibilityIdentifier("favorites.sort")
        .anchorPreference(key: MenuAnchors.self, value: .bounds) { ["sort": $0] }
    }.padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 4)
  }

  private var sortTitle: String {
    switch sort {
    case "name": "品种"
    case "volume": "成交额"
    case "price": "价格"
    case "change": amount ? "涨跌额" : basisTitle
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
    }.padding(.vertical, 6).font(.system(size: 14))
  }

  private func sortItem(_ title: String, key: String, useAmount: Bool? = nil) -> some View {
    let current = sort == key && (useAmount == nil || useAmount == amount)
    return Button {
      if let useAmount { amount = useAmount }
      applySort(key)
      sorting = false
    } label: {
      HStack(spacing: 8) {
        Text(title)
        Spacer(minLength: 0)
        if current {
          Image(systemName: ascending ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
            .font(.system(size: 8)).foregroundStyle(theme.amber)
        }
      }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 16).contentShape(Rectangle())
    }.buttonStyle(.plain).foregroundStyle(current ? theme.amber : theme.ink)
  }

  /// 排序键与方向：和原来那排小按钮一个逻辑——同一个键点第二次翻方向，
  /// 第三次退回自选顺序。
  private func applySort(_ key: String) {
    guard key != "custom" else { sort = "custom"; return }
    if sort != key { sort = key; ascending = key == "name" }
    else if ascending == (key == "name") { ascending.toggle() } else { sort = "custom" }
  }

  /// 编辑行布局不随每批WS报价重建；退出编辑立刻读取最新行情。
  private func displayQuote(_ symbol: String) -> Ticker? {
    editing ? editQuotes[symbol] : model.ticker(for: symbol)
  }

  private func sortValue(_ symbol: String) -> Double? {
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
    List {
      ForEach(symbols, id: \.self) { symbol in
        VStack(spacing: 0) {
          row(symbol, first: symbol == symbols.first)
          if expanded.contains(symbol), !editing { details(symbol) }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .onAppear {
          onVisible(symbol); onRowVisibility(symbol, true)
          if historyOn.insert(symbol).inserted { onHistoryVisibility(symbol, true) }
          // 有行露面就重算一次落脚点（审查 C-08）。往下滚是底下露新行，往上滚是
          // 顶上露新行，两头都走得到这儿。
          rows.rendered.insert(symbol)
          noteScrollAnchor()
        }
        .onDisappear {
          onRowVisibility(symbol, false)
          if historyOn.remove(symbol) != nil { onHistoryVisibility(symbol, false) }
          // 只摘名字，**不重算落脚点**：整页被拆掉的那一刻每一行都会走一遍这儿，
          // 边摘边算会把「最上面那行」一路推到表尾，刚记下的落脚点当场作废。
          rows.rendered.remove(symbol)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
          Button("删除自选", role: .destructive) { model.removeFavorite(symbol) }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
          Button("移到分类") { moving = MoveRequest(symbols: [symbol]) }.tint(theme.amber)
          Button("删除", role: .destructive) { model.removeFavorite(symbol) }
        }
      }
      .onMove { source, target in
        // 编辑时恢复自定义顺序，筛选时不允许把可见索引套到完整列表。
        model.moveVisible(symbols, from: source, to: target)
        sort = "custom"
      }
    }
    .listStyle(.plain)
    // 关掉系统滚动条。iOS 13 起那根灰条自己是能抓住拖的，也就是说它会吃触摸——
    // 它占的那条竖带（右边 30pt）正好压在每行最右边那颗展开箭头上，列表一滚或一重建
    // 它就闪出来，那一两秒里点箭头会没反应。这一页本来也没打算露系统滚动条。
    .scrollIndicators(.hidden)
    .scrollContentBackground(.hidden)
    .environment(\.defaultMinListRowHeight, 0)
    // List 占满剩下的整屏：长按把一行拖到最后一行下面，落点还在列表里。
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .padding(.top, 6).padding(.bottom, 8)
    .onAppear { restoreScrollAnchor(reader) }
    }
  }

  /// 记下「他现在停在哪一行」：按表的顺序取第一个还画在屏幕上的品种。
  ///
  /// 存代号不存偏移量，理由见 `FavoritesEditSession.scrollAnchor`。
  private func noteScrollAnchor() {
    guard anchorRestored else { return }
    // 按表的顺序取现在铺着的第一行。它比「看得见的第一行」要高几格（`List` 在
    // 可视区上下各多铺几行），这笔固定的差额由还原那头校准掉，见下面。
    guard let top = symbols.first(where: { rows.rendered.contains($0) }) else { return }
    // 只记在那个不被观察的盒子里。`session` 是 `@Observable`，滚动时每露一行写一次
    // 就等于把整张表重画一遍——这一页上跑着实时报价，赔不起。真正交出去是在整页
    // `onDisappear` 那一刻（见上面），那时候读一次就够了。
    rows.anchor = top
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
  private func restoreScrollAnchor(_ reader: ScrollViewProxy) {
    guard !anchorRestored else { return }
    let list = symbols
    guard let anchor = session.scrollAnchor, let wanted = list.firstIndex(of: anchor) else {
      anchorRestored = true
      return
    }
    Task { @MainActor in
      var target = wanted
      // 滚一次、看看现在铺出来的第一行是谁，差几格就往回补几格。
      //
      // 为什么要这么一道校准：记的和还原的是同一个口径（「铺着的第一行」），但
      // `scrollTo(_:anchor:.top)` 把那一行摆到的是**可视区**的顶上，而记的时候它在
      // 可视区顶上**再往上几格**。这笔差额就是列表的缓冲区厚度，所以量一次补一次
      // 就对上了。不写死格数是因为它随行高、字号、展开的详情变。
      //
      // 圈数留够、每圈等到 `List` 真把新一批行铺完：`rendered` 是靠行自己的
      // `onAppear` / `onDisappear` 攒起来的，机器忙的时候它比滚动慢半拍，量早了
      // 就会拿到上一帧的答案，于是这一圈白补、下一圈又从头补。
      //
      // 到底了就停：表尾那几行再怎么滚也到不了可视区顶上，`now` 不动就是撞了底，
      // 此时的位置已经和走之前一样（走之前他也在底上），再补只是空转。
      var previous = -1
      for _ in 0..<6 {
        try? await Task.sleep(for: .milliseconds(80))
        reader.scrollTo(list[target], anchor: .top)
        try? await Task.sleep(for: .milliseconds(220))
        guard let now = list.firstIndex(where: { rows.rendered.contains($0) }) else { break }
        let delta = wanted - now
        if delta == 0 || now == previous { break }
        previous = now
        target = min(max(target + delta, 0), list.count - 1)
      }
      anchorRestored = true
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
    let base = info?.base ?? String(symbol.dropLast(4))
    let amplitude = ticker?.amplitude24h
    let volumeText = ticker.map { $0.quoteVolume.isFinite ? fmtVol($0.quoteVolume) : "—" } ?? "—"
    let amplitudeText = amplitude.map { toFixed($0, 2) + "%" } ?? "—"
    let value = ticker?.changePercent ?? .nan
    let trend = value.isFinite ? (value >= 0 ? theme.up : theme.down) : skin.ink4
    return HStack(spacing: 10) {
      if editing {
        Button { if !selection.insert(symbol).inserted { selection.remove(symbol) } } label: {
          // 没选中的勾选框只有一圈描边，不给它一块实心命中区的话，点圆圈正中是点不着的。
          checkbox(selection.contains(symbol))
            .frame(width: 20, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(selection.contains(symbol) ? "取消选择" : "选择")
          .accessibilityIdentifier("favorites.select." + symbol)
      }
      HStack(spacing: 10) {
        badge(base)
        VStack(alignment: .leading, spacing: 4) {
          HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(base).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(theme.ink)
            Text(quoteAsset(symbol)).font(.system(size: 9, weight: .regular)).foregroundStyle(skin.ink4)
          }.lineLimit(1).minimumScaleFactor(0.75)
          Text("额 " + volumeText + "  ·  幅 " + amplitudeText)
            .font(.system(size: 10)).monospacedDigit().foregroundStyle(theme.ink3)
            .lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity, alignment: .leading)
        if !editing, sparkline {
          Sparkline(values: sparkValues(symbol), color: trend)
            .frame(width: 44, height: 24)
        }
        quote(symbol)
      }.contentShape(Rectangle())
        .onTapGesture { selectOrOpen(symbol) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("favorites.open." + symbol)
        .accessibilityAction { selectOrOpen(symbol) }
        .accessibilityAction(named: "展开详情") { toggleDetails(symbol) }
      if editing {
        Button { moving = MoveRequest(symbols: [symbol]) } label: {
          Image(systemName: "folder").font(.system(size: 13)).foregroundStyle(theme.ink3)
            .frame(width: 22, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("favorites.move." + symbol)
      } else {
        Button { toggleDetails(symbol) } label: {
          Image(systemName: expanded.contains(symbol) ? "chevron.up" : "chevron.down")
            .font(.system(size: 9, weight: .semibold)).foregroundStyle(skin.ink4)
            .frame(width: 14, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("展开详情")
          .accessibilityValue(expanded.contains(symbol) ? "已展开" : "已收起")
          .accessibilityIdentifier("favorites.expand." + symbol)
      }
    }
    // 没有纸之后行的左右内边距放宽到 20pt 上下，徽章和「自选」标题、分类段对齐同一条竖线。
    .padding(.leading, 19).padding(.trailing, 20)
    .frame(height: 66)
    .overlay(alignment: .top) {
      if !first {
        LinearGradient(colors: [.clear, skin.rule, skin.rule, .clear],
                       startPoint: .leading, endPoint: .trailing)
          .frame(height: 0.5).padding(.horizontal, 20)
      }
    }
  }

  /// 徽章：背后一团品牌色的光晕，外面一圈捕光环。
  private func badge(_ base: String) -> some View {
    let spec = CoinSpec.of(base)
    let brand = BadgeTint.gradient(from: spec.from, to: spec.to, seed: theme.seed).bottom
    return ZStack {
      RadialGradient(colors: [brand.opacity(skin.dark ? 0.34 : 0.2), brand.opacity(0)],
                     center: .center, startRadius: 2, endRadius: 24)
        .frame(width: 48, height: 48)
      CoinBadge(base: base, size: 33)
        .overlay {
          RoundedRectangle(cornerRadius: 13.7, style: .continuous)
            .strokeBorder(AngularGradient(
              gradient: Gradient(stops: [
                .init(color: brand, location: 0),
                .init(color: brand.opacity(0.2), location: 0.3),
                .init(color: brand, location: 0.55),
                .init(color: brand.opacity(0.15), location: 0.83),
                .init(color: brand, location: 1)]),
              center: .center, angle: .degrees(210)), lineWidth: 1)
            .opacity(skin.dark ? 0.6 : 0.55)
            .padding(-3.5)
        }
    }.frame(width: 33, height: 33)
  }

  private func checkbox(_ on: Bool) -> some View {
    ZStack {
      if on {
        Circle().fill(skin.accentGradient)
          .overlay(alignment: .top) { skin.topHighlight(inset: 5) }
        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
      } else {
        Circle().strokeBorder(skin.ink4, lineWidth: 1.4)
      }
    }.frame(width: 20, height: 20)
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

  private func quote(_ symbol: String) -> some View {
    let ticker = displayQuote(symbol)
    let info = model.info(for: symbol)
    // 和 `row(_:first:)` 同一个判据（审查 B-06 / 复核项 4）。
    let stale = !model.listing(of: symbol).hasLivePrice
    let price = ticker?.last ?? .nan
    // 小数位由品种自己说（`pricePrecision`）。目录里没有这个代号时走全 app 唯一那把
    // 梯子，不再在这一页写死 2 位（审查 B-07）。
    let decimals = info?.displayDecimals(for: price) ?? priceDecimalsFallback(price)
    let value: Double = stale ? .nan : (ticker?.changePercent ?? .nan)
    let change = amount && value.isFinite && price.isFinite && value > -100 ? price - price / (1 + value / 100) : value
    // `fmtPrice` 而不是 `fmtNum`：0.0000004 这种合法极小价按 2 位四舍五入会写成
    // `0.00`，那等于说这东西不值钱（审查 B-07）。
    let priceText = price.isFinite ? grouped(fmtPrice(price, decimals: decimals)) : "—"
    let tint = value.isFinite ? (value >= 0 ? theme.up : theme.down) : skin.ink4
    // 没有实时价时最后那口真价照旧摆着，只是退成次要文字色——不加标签、不弹窗。
    let priceInk: Color = stale ? skin.ink4 : (price.isFinite ? theme.ink : .clear)
    // 还没到的涨跌幅和还没到的价格用同一种骨架：一块底色，不写字。
    // 写「—」会让人以为这个品种没有涨跌幅，而不是还在路上。
    let changeText = change.isFinite ? toFixed(abs(change), amount ? decimals : 2) + (amount ? "" : "%") : "—"
    let signed = change.isFinite ? (change >= 0 ? "+" : "-") + changeText : "—"
    return VStack(alignment: .trailing, spacing: 5) {
      Text(priceText)
        .font(.system(size: 15.5, weight: .medium)).monospacedDigit()
        .lineLimit(1).minimumScaleFactor(0.7)
        .foregroundStyle(priceInk)
        .overlay(alignment: .trailing) {
          // 骨架块只表示「还在路上」。已下架 / 还没开盘的行不摆骨架，摆「—」，
          // 否则那块灰底会永远亮着，读起来像永远加载不完。
          if !price.isFinite, !stale {
            RoundedRectangle(cornerRadius: 4).fill(skin.rule).frame(width: 70, height: 13)
              .accessibilityHidden(true)
          }
        }.accessibilityIdentifier("favorites.price." + symbol)
      HStack(spacing: 4) {
        if change.isFinite {
          Triangle(up: change >= 0).fill(tint).frame(width: 6, height: 5)
            .accessibilityHidden(true)
        }
        Text(changeText)
          .font(.system(size: 11, weight: .semibold)).monospacedDigit()
          .foregroundStyle(change.isFinite ? tint : (stale ? skin.ink4 : .clear))
          .accessibilityLabel(signed)
          .accessibilityIdentifier("favorites.change." + symbol)
      }
      .padding(.horizontal, 7).frame(height: 19).frame(minWidth: 54)
      .background {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(change.isFinite ? tint.opacity(0.14) : skin.rule)
          .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(change.isFinite ? tint.opacity(0.3) : .clear, lineWidth: 0.5))
      }
    }.frame(minWidth: 86, alignment: .trailing)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.32), value: ticker != nil)
  }

  /// 价格千分位。`fmtNum` 只管小数位，逗号在这儿补。
  private func grouped(_ text: String) -> String {
    let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    var head = String(parts[0])
    let negative = head.hasPrefix("-")
    if negative { head.removeFirst() }
    guard head.count > 3 else { return text }
    var out = ""
    for (index, character) in head.reversed().enumerated() {
      if index > 0, index % 3 == 0 { out.append(",") }
      out.append(character)
    }
    let body = (negative ? "-" : "") + String(out.reversed())
    return parts.count > 1 ? body + "." + parts[1] : body
  }

  // MARK: - 展开详情

  private func details(_ symbol: String) -> some View {
    let ticker = displayQuote(symbol)
    let info = model.info(for: symbol)
    // 同一档状态（审查 B-06 / 复核项 4）：没有实时价时，凡是由实时价算出来的格子
    // 一律「—」，24 小时高 / 低 / 额也在内（审查 B.8）——摆一个上周的统计比空着更像在骗人。
    let stale = !model.listing(of: symbol).hasLivePrice
    let live = stale ? nil : ticker
    let decimals = info?.displayDecimals(for: ticker?.last ?? .nan)
      ?? priceDecimalsFallback(ticker?.last ?? .nan)
    return VStack(spacing: 12) {
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), spacing: 12) {
        // 标题一律中文，不用 H 这种英文缩写（`kanpan-ui-labels-are-chinese`）。
        cell("1小时", percent(stale ? nil : historyChange(symbol, hours: 1)))
        cell("4小时", percent(stale ? nil : historyChange(symbol, hours: 4)))
        cell(basisTitle, percent(live?.changePercent))
        cell("24小时高", number(live?.high, decimals))
        cell("24小时低", number(live?.low, decimals))
        // 缺成交额也写「—」，和紧挨着的 24 小时高 / 低同一个写法（复核项 3）。
        cell("24小时额", live.flatMap {
          $0.quoteVolume.isFinite ? fmtVol($0.quoteVolume) + " " + quoteAsset(symbol) : nil
        } ?? "—")
      }
      if let ticker = live, ticker.high > ticker.low, ticker.last.isFinite {
        GeometryReader { geometry in
          Capsule().fill(skin.rule).frame(height: 4)
          Capsule().fill(skin.accentGradient).frame(width: 2, height: 10)
            .offset(x: min(max((ticker.last - ticker.low) / (ticker.high - ticker.low), 0), 1) * max(0, geometry.size.width - 2), y: -3)
        }.frame(height: 8)
      }
      HStack(spacing: 10) {
        detailAction("移到分类", id: "favorites.move." + symbol) { moving = MoveRequest(symbols: [symbol]) }
        Spacer(minLength: 0)
        detailAction("打开行情图表", id: "favorites.open.chart." + symbol) { open(symbol) }
      }
    }.padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 16)
      .background(skin.glassThin)
      .overlay(alignment: .top) {
        LinearGradient(colors: [.clear, skin.rule, skin.rule, .clear], startPoint: .leading, endPoint: .trailing)
          .frame(height: 0.5).padding(.horizontal, 20)
      }
      .accessibilityElement(children: .contain).accessibilityIdentifier("favorites.details." + symbol)
  }

  private func detailAction(_ title: String, id: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.amber)
        .frame(height: 30).padding(.horizontal, 14)
        .background(skin.glassThin, in: Capsule())
        .overlay(Capsule().strokeBorder(skin.edgeSoft, lineWidth: 0.5))
        .contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityIdentifier(id)
  }

  private func historyChange(_ symbol: String, hours: Int) -> Double? {
    let target = Int64(Date().timeIntervalSince1970 * 1000) - Int64(hours) * 3_600_000
    guard let bar = model.historyBars[symbol]?.last(where: { $0.openTime <= target }),
          target - bar.openTime < 60_000, bar.open > 0,
          let price = displayQuote(symbol)?.last else { return nil }
    return (price / bar.open - 1) * 100
  }
  private func percent(_ value: Double?) -> String { guard let value, value.isFinite else { return "—" }; return (value >= 0 ? "+" : "") + toFixed(value, 2) + "%" }
  /// 详情里的价格格子。`fmtPrice` 兜住极小的正价（审查 B-07）。
  private func number(_ value: Double?, _ decimals: Int) -> String { guard let value, value.isFinite else { return "—" }; return grouped(fmtPrice(value, decimals: decimals)) }
  private func cell(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.system(size: 9, weight: .medium)).tracking(1.2).foregroundStyle(skin.ink4)
      Text(value).font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(theme.ink)
    }
  }

  private func toggleDetails(_ symbol: String) { if !expanded.insert(symbol).inserted { expanded.remove(symbol) } }
  private func selectOrOpen(_ symbol: String) {
    if editing { if !selection.insert(symbol).inserted { selection.remove(symbol) } }
    else { open(symbol) }
  }
  private func quoteAsset(_ symbol: String) -> String {
    model.info(for: symbol)?.quote ??
      (["USDT", "USDC", "BUSD"].first { symbol.hasSuffix($0) } ?? "USDT")
  }
  private func open(_ symbol: String) {
    // 目录里没有这个代号（刚上市、或者目录还在路上）时才临时造一行：小数位按最后
    // 看到的价退回那把共用的梯子，不再写死 2 位 / 0.01（审查 B-07）。真正的位数由
    // 行情页进图时那趟目录补查覆盖（`MarketModel.refreshInfo`，审查 B-06）。
    let quote = quoteAsset(symbol)
    let fallback = SymbolInfo(symbol: symbol,
                              base: symbol.hasSuffix(quote) ? String(symbol.dropLast(quote.count)) : symbol,
                              quote: quote,
                              pricePrecision: priceDecimalsFallback(displayQuote(symbol)?.last ?? .nan),
                              tickSize: 0)
    model.pick(model.info(for: symbol) ?? fallback)
  }
  private func assign(_ symbols: [String], to group: String?) {
    symbols.forEach { model.assign($0, to: group) }; moving = nil; selection.removeAll()
  }

  // MARK: - 空自选 / 编辑条

  private var emptyState: some View {
    VStack(spacing: 10) {
      Spacer(minLength: 0)
      Image(systemName: "plus")
        .font(.system(size: 17, weight: .medium)).foregroundStyle(skin.accent)
        .frame(width: 44, height: 44)
        .background(skin.glassThin, in: RoundedRectangle(cornerRadius: 13.6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13.6, style: .continuous)
          .strokeBorder(skin.accent.opacity(0.35), lineWidth: 1))
      Text("这一栏还空着").font(skin.serif(15.5)).foregroundStyle(theme.ink).padding(.top, 2)
      Text("加几个常看的品种，它们会在这里排好")
        .font(.system(size: 12)).foregroundStyle(theme.ink3)
      Button { searching = true } label: {
        Text("添加品种").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
          .frame(height: 36).padding(.horizontal, 20)
          .background(skin.accentGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay(alignment: .top) { skin.topHighlight(inset: 8) }
          .shadow(color: skin.accent.opacity(0.4), radius: 10, x: 0, y: 6)
      }.buttonStyle(.plain).padding(.top, 8)
      Spacer(minLength: 0)
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.top, 6).padding(.bottom, 8)
  }

  private var editBar: some View {
    HStack(spacing: 0) {
      Button(selection.count == symbols.count ? "全不选" : "全选") {
        selection = selection.count == symbols.count ? [] : Set(symbols)
      }.foregroundStyle(theme.amber)
      Spacer(minLength: 0)
      Button("移到分组") { moving = MoveRequest(symbols: Array(selection)) }
        .disabled(selection.isEmpty)
        .foregroundStyle(selection.isEmpty ? skin.ink4 : theme.amber)
      Spacer(minLength: 0)
      Button("删除", role: .destructive) {
        selection.forEach { model.removeFavorite($0) }; selection.removeAll()
      }.disabled(selection.isEmpty)
        .foregroundStyle(selection.isEmpty ? skin.ink4 : theme.down)
    }
    .buttonStyle(.plain)
    .font(.system(size: 13, weight: .semibold))
    .padding(.horizontal, 20).frame(height: 52)
    .background(skin.glass, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(skin.edgeSoft, lineWidth: 0.5))
    .overlay(alignment: .top) { skin.topHighlight(inset: 9) }
    .padding(.horizontal, 12).padding(.bottom, 8)
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
  func serif(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .serif) }

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

private struct Triangle: Shape {
  let up: Bool
  func path(in rect: CGRect) -> Path {
    var path = Path()
    if up {
      path.move(to: CGPoint(x: rect.midX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    } else {
      path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    }
    path.closeSubpath()
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

// MARK: - 正在做的那次批量编辑

/// 自选页上「他这会儿正勾着的那几个品种」：编辑模式开着没有、勾了哪几行、
/// 以及编辑期间冻住的那份报价。
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
  /// 编辑模式开着没有。只由用户自己的动作进出（「编辑自选」/「完成」/ 换账号）。
  var editing = false
  /// 勾中的那几行。
  var selection = Set<String>()
  /// 进编辑那一刻冻住的报价。编辑时整页读它而不是读实时报价，行布局才不会
  /// 随每批 WS 报价重排（见 `FavoritesView.displayQuote`）。
  var quotes: [String: Ticker] = [:]
  /// 他停在表的哪一行（审查 C-08）。
  ///
  /// 存的是**品种代号**，不是滚动偏移量：一屏能放几行随字号、随展开的详情、随
  /// 机型变，像素位置换个环境就对不上，而「他正盯着 APTUSDT 那一行」换到哪儿都成立。
  /// 和编辑会话同住一处、同一个理由——这是「一次使用里的落脚点」，不是跟着账号走的
  /// 习惯：冷启动理应从第一行看起，所以它不进 `Prefs`、不落盘。
  /// 分类切换会把它清掉：换了一类，上一类停在哪儿没有意义。
  var scrollAnchor: String?

  func begin(quotes: [String: Ticker]) {
    self.quotes = quotes
    selection.removeAll()
    editing = true
  }

  func end() {
    editing = false
    selection.removeAll()
    quotes.removeAll()
  }

  /// 换分类、换账号时把落脚点一起丢掉。
  func forgetScrollAnchor() { scrollAnchor = nil }
}

/// 列表现在铺着哪几行，以及由它算出来的落脚点（审查 C-08）。
///
/// 做成一个**普通的引用盒子、不被任何人观察**是故意的：滚动时每露一行就要写一次，
/// 写进 `@State` 或 `@Observable` 等于把整张表重画一遍，而这一页上跑着实时报价。
/// 它只在整页 `onDisappear` 那一刻被读一次，把落脚点交给 `FavoritesEditSession`。
@MainActor final class FavoritesRenderedRows {
  /// 现在铺着的那几行。注意是「铺着」不是「看得见」：`List` 在可视区上下各多铺几行。
  var rendered = Set<String>()
  /// 铺着的第一行，也就是要交出去的落脚点。
  var anchor: String?
}

/// 记下「设置」「排序」两颗按钮的位置，好让浮层菜单吊在它们下面。
private struct MenuAnchors: PreferenceKey {
  static let defaultValue: [String: Anchor<CGRect>] = [:]
  static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
    value.merge(nextValue()) { _, new in new }
  }
}
