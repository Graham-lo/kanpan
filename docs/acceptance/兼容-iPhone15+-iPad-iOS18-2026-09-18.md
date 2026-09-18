# 兼容一轮：iPhone 15 及以上 · 全 iPad 系列 · iOS 18 起

2026-09-18。用户定的三条口径：

1. **最低系统提到 iOS 18.0**，各 SPM 包同步，iOS 17 的兼容分支可以清掉。
2. **iPad 只做「不破」**——每一页在 iPad 全部宽度下不错位、不拉伸、可用。
   明确不做宽屏分栏／侧边并排，也明确不砍掉 iPad 支持。
3. **iOS 18 只做静态核查**，不下 18 的模拟器运行时；实测跑在本机装着的 iOS 26.5 上。

---

## 一、最低系统

| 位置 | 值 |
|---|---|
| Kanpan app target（Debug / Release） | `IPHONEOS_DEPLOYMENT_TARGET = 18.0` |
| Evidence 宿主（Debug / Release） | `18.0` |
| KanpanCore / Chart / Data / Network / Review / Account / Settings / Symbols / Diagnostics | `platforms: [.iOS(.v18), …]` |

全仓无 `17.0`、无 `.v17` 残留。落在 `a47f2d2`（app + 9 个包）与 `b952fee`
（Evidence 宿主——它链着已经提到 18 的 KanpanChart / KanpanCore，不跟着提会编不过）。

**静态核查结论**：源码里 `@available` / `#available` **一处都没有**。
（全仓 grep 到的 24 处全部落在各包 `.build/` 的生成测试壳里，与产品代码无关。）
也就是说不存在「iOS 17 走一条、18 走另一条」的分支，抬高下限不会让任何代码路径失活，
也没有留下死代码。构建侧：app 与测试包各编一遍，**0 error、0 deprecation 告警**。

## 二、iPad 静态核查

按「在 iPad 上会破」的几类成因逐条查：

| 查什么 | 结果 |
|---|---|
| `NavigationSplitView` / `navigationViewStyle` / `horizontalSizeClass` | 0 处——整套界面不按 size class 分叉，iPad 上就是 iPhone 那一套，不存在「宽屏分支没写好」 |
| 分享单／文档选择器（iPad 上不给 popover 源会**当场崩**） | `UIActivityViewController` / `ShareLink` / `UIDocumentPickerViewController` 全为 0 处，无此风险 |
| 承担版面的固定宽度（≥100pt） | 仅 `TopBar.swift:247` 的 `.frame(width: 184)`，是 2×2 仓/额/市值/费率格子的**防抖宽度**，真机上量定的，iPad 上照样不抖，保留 |
| 正文越过安全区 | 4 处 `ignoresSafeArea` 全是背景层（启动底色、极光背景、透明捕点层、横屏遮罩），**没有一处是内容** |
| 方向声明 | iPad 四向全开，iPhone 三向（不含倒置）——符合「横屏是画线工作台」的设定 |

## 三、iPad 实修

真正会「破」的是**铺满整屏的单列页**：它们的行是「左边一个名目、右边一个数」，
iPhone 上两端相距 350pt 左右扫得过来，13" iPad 横屏铺满就是 1300pt——
品种名钉在最左、价格钉在最右，中间一片空白，对不上号。这是**系统性缺陷**，不是个别页面手误。

修法是封顶而不是重排版，正好卡在「不破」这条线上：

```swift
func readableColumn(_ max: CGFloat = 560) -> some View {
  frame(maxWidth: max).frame(maxWidth: .infinity)
}
```

560pt 比最宽的 iPhone 再富余一点，所以 **iPhone 上这一层等于不存在**；页面底色仍铺在封顶外面，两侧不露白边。
`ReviewUI` 是独立的包、看不到 app 的扩展，所以那边留了同名的一份。

落到四张页（`87e7f56`）：搜索页、品种整页、复盘本、复盘记录详情。
**没有动自选分类页**——那是用户自己定稿的设计，且当时正被另一个窗口改着。

另有三处会拉伸/画错的，在 `a47f2d2` 里一并修了。

## 四、实测矩阵（iOS 26.5 运行时）

`IPadLayoutUITests` 是这道封顶的看门人：每台 iPad 上把三页走一遍，量关键控件宽度（上限 600pt =
560 封顶 + 舍入余量），顺手留截图。iPhone 上窗口本来就窄（402pt），这几条自己跳过。

| 机型 | 宽度 | 内容列封顶 | 横屏画线不画指标 | 「回到最新」 |
|---|---|---|---|---|
| iPhone 16 Pro | 402pt | 跳过（窄屏无意义） | 通过 | 通过 |
| iPad mini (A17 Pro) | 744pt | **通过** | 通过 | 通过 |
| iPad (A16) | 820pt | **通过** | 通过 | 通过 |
| iPad Air 11" (M4) | 820pt | **通过** | 通过 | 通过 |
| iPad Pro 11" (M5) | 834pt | **通过** | 通过 | 通过 |
| iPad Pro 13" (M5) | 1024pt | **通过** | 通过 | 通过 |

13" 上的截图（`iPad-搜索页`、`iPad-搜索页-有结果`、`iPad-复盘本`）目视确认：
内容列居中成一条，BTC 与 76613.80 挨在一起可读；复盘本的待办/记录/战绩分段控件不再摊成满屏。

**机型覆盖说明**：仓库的 13 台清单覆盖 iPhone 宽度 393 / 402 / 430 / 440pt 四档与全部四档 iPad。
iPhone 15 Plus、15 Pro Max、16、16e 与清单内机型同宽同 size class，不另跑。

## 五、顺手修掉的一颗雷

三台 iPad 第一轮各红一条，且都不是断言红，是 XCUI 当场抛
`Failed to get matching snapshot: No matches found`，位置在 `hittable()` 里的 `el.frame`。

`exists` 挡不住 `.frame`——答「在」之后、取 frame 之前的那一帧里按钮已经淡出去了。
这和那段注释里**已经挡住**的 `isHittable` 问题是同一回事，只是深了一层。
iPad 上更容易撞：图更宽、视野归位滑得更久。

改成从 `try? el.snapshot()` 这一张快照上读「在不在 / 有没有面积」——
这是这组接口里唯一会把「没这个元素」老实交成 Swift 错误的路径。改完三台重跑全过（`f26c7a6`）。

这是存量问题，不是这轮引入的；按项目规矩直接修了，没停下来请示。

## 六、全量矩阵翻出来的七条红（都已从根因修掉）

把 13 台矩阵真跑起来之后，一共红了七条。查到底之后分成两类：
**两条是 app 自己的缺陷**（首屏空图、自选页被标签栏吃掉一栏安全区），
**五条是用例的点法不对**（周期条药丸判不着、自选拖动排序、MA 输出开关，
以及 17e 上那两条——周期条药丸与「工具」，和 MA 开关是同一个机制）。
app 那两条各自补了会红的回归用例；用例那五条改的是用例，一行产品代码都没动。

**1. 周期条的药丸被 XCUI 判成「点不着」——是判定抖动，不是 app 的毛病（用例侧）**

现象是 `testLatestQuoteDoesNotRegressAcrossIntervals` 在点周期条时报
`Not hittable: Button, identifier: 'interval.chip.1m'` /
`Computed hit point {-1, -1} after scrolling to visible`，重试三次都一样。

**先走错了两轮，两轮都已经拆掉。** 从 xcresult 导出的无障碍层级里看到屏幕上有**两个**全屏
`Window`，第二个是键盘那层 `UITextEffectsWindow`，于是先按「关搜索页时留了一层透明窗口盖住
整个 app」去修：`f68b543` 把页面拆除推迟一个 runloop，没用；接着又写了个 `KeyboardExit`，
等 `keyboardDidHideNotification`（最多 450ms）再关页，重跑还是在同一处、同一个时间点红。
两处改动现在都已**回滚**（`f68b543` 整个 revert、`KeyboardExit` 及其四个调用点删除）——
它们既没修好问题，`KeyboardExit` 还会白白给关搜索页加上至多 450ms 的延迟。

**真正的证据是从 app 里取的。** 写了一个只在 DEBUG 下挂着的探针（`HitProbe`，取完证已删），
在卡住的那一刻遍历 `windowScene.windows`，对药丸中心那一点各做一次 `hitTest` 和
`accessibilityHitTest`。结果是：

- `#0 UIWindow` → `hitTest` 命中药丸自己的容器，`accessibilityHitTest` 落在它的无障碍节点上；
  这一对结果和界面正常时（尚未卡住）**完全一样**。
- `#1 UITextEffectsWindow` → `hitTest` 和 `accessibilityHitTest` **两个都返回 `nil`**。
  它透明、`hidden=false`、第一次用完键盘后就常驻应用整个生命周期，但它什么也不挡——
  真人的手指和 VoiceOver 的焦点从来没被它拦过。

另外两条对照也否掉了「键盘惹的祸」：`chip1m=false` 在**完全没走过搜索页**的步骤上也出现过；
通过和失败两次迭代的时间线几乎一模一样，不是「没等够」。

**根因在 XCUI 自己那一侧。** `IntervalBar` 的常用行是一个横向 `ScrollView`
（`interval.quick`），内容宽度 `max(可用宽, 自然宽)` 取的是可用宽——实测自然宽 245.3pt、
可用 263pt，**钉几档就铺满几档，从来不溢出**，所以它是一个*滚不动的滚动视图*。
`XCUIElement.tap()` 点滚动视图里的东西之前一定先做一次「滚到可见」，对滚不动的那种，
这一步算回来的命中点偶尔就是 `{-1, -1}`，XCUI 于是判它 not hittable、直接放弃。

**修法是改用例。** 新增 `XCUIApplication.tapIntervalChip(_:)`，按药丸中心的坐标点，
绕开可点性判定——和这条条上本来就在用的那几下 `swipe` 是同一个路子。
四处点药丸的地方（`ChartFoundationUITests` 三处、`MainScreenUITests` 一处）全部换过去；
`tapButton` 顺手加了一个可换的落手动作，好让「点完要等到选中」那套取证逻辑继续用。

**2. 首屏拉不到历史，图就永远钉死在「行情加载中」（`d79e0a5`）**

`testTradFiSearchAndMarketData` 的图一直空着。查下去是两条互相独立的原因叠在一起：

- `MarketFeed.writeSnapshotNow` 会把只有 1 根的序列落盘（快照 79B）。而
  `RoutedMarketFeed` 要收够 3 根才肯把这条线路的图交给界面——1 根的快照画不出第一帧，
  却把上一份能用的覆盖掉了。首屏 429 拉不到历史时正好撞上：序列里只剩 WS 推来的那一根，
  下次冷启动读回来还是一根，图就永远停在「行情加载中」。现在门槛对齐成 3 根（`snapshotFloor`），
  不到就宁可不存。
- `RoutedMarketFeed.forward` 在收到历史报错时会报一声 `.routing(.switching)`。
  可行情页收到 `.switching` 的第一件事就是 `historyError = nil`（`MarketModel.swift:268`），
  于是内部每重试一次就把「点此重试」那条横幅抹掉一次：巡检刚把它亮起来，下一发 429 回来又抹掉，
  用户最后看到的是一张空图加一句「行情加载中」，既没有错误也没有重试的路。
  历史没拉下来本来就不是换线路（线路是用户定的，这里从不换线），那一声本就不该报，去掉了。

两条都补进了 `KanpanData/Tests/KanpanDataTests/BlankChartTests.swift`，
各自把修复退回去验证过会红。

**3. 自选拖动排序抢不过整行那个按钮（`f182353`，用例侧）**

`testFavoritesBatchEditing` 的 0.6 秒长按在机器忙的时候会被 `favorites.open.BTCUSDT`
那个满宽按钮先认走。这一条是用例的问题不是 app 的问题——自选分类页是用户自己定稿的，
不动它——改成按满 1.2 秒、`.slow` 速度拖、松手前再按住 0.8 秒。
顺带修掉一个更隐蔽的错：基准 `before` 原先取在「等布局稳定」那段循环之前，量的是还没落位的坐标。

**4. 自选页外面白套的 `NavigationStack` 吃掉了标签栏让出来的安全区（`9c3a79b`，app 侧）**

这一条是第二轮矩阵翻出来的，起因是 `cb0c4c3` 把标签栏从 `VStack` 的一节改成
`MainScreen.portraitBody` 上的 `safeAreaInset`。改完之后自选页整页短了一栏，两个症状：

- **批量编辑的「删除」按不动，点下去跳去设置页。** 编辑条整条沉进标签栏里——从 xcresult
  里导出的合成事件看得很清楚，那一下点在 (348, 784)，而 `bottom.settings` 占着
  (294.7–393, 768–818)。自选的批量删除整条是坏的。
- **列表滚到底，最后一行仍压在标签栏底下推不上来。** iPhone 15 上起 5 个品种、把 BTC 和
  ETH 两行都展开，滚到头 DOGE 行的下沿停在 825pt，栏顶是 768pt。

根因不是「两层 `safeAreaInset` 没叠上」，是自选页外面套的那层 `NavigationStack`
（`FavoritesView.swift:76`）。整页没有一个 `NavigationLink`，它唯一干的事就是给自己配一条
导航栏、再用 `.toolbar(.hidden, for: .navigationBar)` 关掉——白套一层壳。可这层壳把安全区
接管了：标签栏让出来的 50pt 是加在外面那层 SwiftUI 视图的安全区上的，而 `NavigationStack`
背后的 `UINavigationController` 只认窗口自己那份，于是壳里的 `List` 和壳里那条
`safeAreaInset` 谁都没吃到。把编辑条挪到壳外面只能修一半，壳本身才是要拿掉的那个。
拿掉之后同样的展开加滚到底，DOGE 下沿 825 → 757pt，编辑条整条落在栏上面。
自选分类页是用户自己定稿的，这一改一个版面参数都没动。

回归用例：`testFavoritesBatchEditing` 原先只看「品种还在不在」，抓不住它——跳去设置页之后
两个品种都不在，那条断言是空过的，红在下一行。现在直接量两个框：编辑条的「删除」不许和
`bottom.settings` 相交。

**5. 关 MA 输出的那一下偶尔没进 app——事件丢在 XCUI 那一侧（`590724d` 之后的用例侧修复）**

`testMAParameterCancelAndSaveOutput` 在 iPhone 16 Plus 和 iPhone 17 Pro 上各红一次，
都停在同一行：点完开关之后 `output.value` 四十秒里一直是 `1`。两台机型同一行，说明不是机型的事。

**先把两个顺手的解释按掉了。** 从 xcresult 导出的合成事件里读出那一下打在 (382.7, 545.5)，
而无障碍层级里开关本体是 `{{329, 531.7}, {63, 28}}`——点在开关里面，不是点歪了；
`IndicatorPanel` 那个 `draft` 是 `init` 里建一次的 `@State`，没有任何异步重载，
所以也不是「app 把草稿刷回去了」。

**取证做进了 app。** 在一棵临时工作树里给那个 `Toggle` 的 setter 挂了一个计数器
（`indicator.setcount`，取完证已还原，没进任何提交），再写探针跑「开面板 → 点一下 → 关面板」
四十轮，就是为了把「事件没进 app」和「进了 app 又被弹回去」分开。复现到的那一次是前者：
点前点后元素的 frame 一模一样（`(20, 519.3, 390, 52.3)`）、`isHittable` 为真，
而 setter 的计数一动没动。**这一下压根没到 app**，丢在 XCUI「合成 → 投递」那一段。
孤立探针上约 3% 丢一下；整套 49 条跑下来机器更忙，矩阵里就撞到了两台。

**换个点躲不开。** 同一轮探针把目标点挪到整行文字那半边（`dx 0.25`）打了 20 次，20 次全不翻——
SwiftUI 把整行暴露成这个开关，可 Form 里真正认点击的只有右边那颗滑块。目标点只能是它。

所以改法是给用例加一颗 `flip(_:to:)`：照原点最多点三下，每下等 5 秒看值有没有过去，
三下还不过去照样红。当时 `tapButton` 上写的还是「只接受一次中心点击」，这一条没有违反它——
那条防的是拿偏移重试掩盖**产品的命中区问题**，这儿已经证明命中区是好的，丢的是测试框架自己的
事件。（后来第 6 条把这个结论推广到了 `tapButton` 本身。）
反向对照：把 `flip` 的目标点改成那个怎么点都不翻的 `dx 0.25`，三下点完准时红在
「开关点了三下还是 1」。

**6. 同一个丢事件，在 17e 上又撞到两条（`5f21b03`，用例侧）**

iPhone 17e 那一台红了两条，签名和上面第 5 条一模一样：

- `testIntervalChipsSelectOneAtATime`——从 xcresult 导出的合成事件是一对干净的按下 / 抬起，
  坐标 (27.5, 154.33)，而 1h 药丸本体是 `{{12.0, 140.3}, {31.0, 28.0}}`，**打在正中**；
  点完之后 1h 仍然是选中态，app 侧没有任何反应。
- `testDrawingAllToolsAndFingerTargets`——`t = 110.70s` 点了 `draw.tools`，
  `draw.sheet.done` 整整五秒没出来。

这不是「机器忙」：把那一轮矩阵的时间线对过，iPhone 15 的时段和我并发跑的构建完全重叠却全过，
iPhone 16 Plus 的时段（12:39–13:02）里我一个任务都没跑却红了。空闲机器上的孤立探针也复现不出来
（药丸 160 下、开关 80 下，一下没丢），只有在「反复开关面板」那种抖动下 40 次里撞到 1 次。

改法和第 5 条同源，但收到了共用的地方：`tapButton` 从「只接受一次中心点击」放宽成
**同一点最多两下**——不换点、不加偏移，第一下没反应时挂一条 `疑似丢了一次合成事件` 的附件，
两下都没反应就挂上全量层级和截图再照样红。画线工具面板那四处开法收进 `openDrawTools()`，
同样的两下。**「不换点、不加偏移」这条底线没松**：它防的是拿偏移重试掩盖产品的命中区问题，
而这儿的命中区已经被证明是好的。

对照跑在 iPhone 16 Plus 模拟器上：正向 5 条全过（310s，三条画线用例 + 周期条药丸 + 回到最新）；
反向把 `openDrawTools` 的目标点挪到 `chart.canvas`、把「回到最新」那一下换成空动作，
两条都在两下之后准时红在自己的话上（31.4s），没有变成无限重试。

## 七、未做 / 边界

- **没有下载 iOS 18 模拟器运行时**，按用户口径，18 这一侧只有静态核查；实测全在 26.5 上。
- **没有做 iPad 宽屏分栏**，按「不破」的口径，这不在这一轮范围里。
- 全量 13 台矩阵（`Tools/ui-test.sh`）跑在一棵**钉死在某一个提交上的临时工作树**里
  （`git worktree add --detach`），所以那一轮的红绿能准确归到一个 sha 上，别的窗口此刻
  还没提交的改动不会混进来。基线见第四节。

## 八、真机（不做，按用户口径）

**用户 2026-09-18 定的口径：「模拟器测完就可以了，真机不用管」。** 所以这一轮的验收基准是
模拟器矩阵，真机实测不再是收尾条件。

真机这一侧只留下一条**仍然成立的结论**：按 iOS 18.0 下限编出的真机 Debug 包，签名与安装都成功
（`Apple Development` + `iOS Team Provisioning Profile: com.mdd.kanpan`，iPhone 16 Pro / iOS 26.6.1），
说明抬高下限没有影响真机侧的构建与分发。这是抬下限这件事唯一需要真机回答的问题，它已经答了。

那三条受影响的 UI 用例**没有在真机上跑**，也不补跑：两次 runner 都是
`Early unexpected exit … before establishing connection`，`devicectl process launch` 给出的根因是
`BSErrorCodeDescription = Locked`（手机锁着屏，runner 连不上），不是代码问题；同样的三条在模拟器
矩阵里全绿。

截图存于 `docs/acceptance/兼容-2026-09-18/`。
