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

### 全量 13 台 × 49 条（基线 `9c3a79b`）

`Tools/ui-test.sh` 一次 `build-for-testing`、逐台 `test-without-building`，每台 49 条，
约 22～25 分钟。下面是那一轮跑完的原始成绩（日志在 `docs/acceptance/M8/ui-test/`）：

| 机型 | 宽度 | 结果 | 用时 |
|---|---|---|---|
| iPhone 15 | 393pt | PASS 49 | 1434s |
| iPhone 16 Pro | 402pt | PASS 49 | 1324s |
| iPhone 16 Plus | 430pt | FAIL 48 / 1 | 1376s |
| iPhone 17 | 402pt | PASS 49 | 1364s |
| iPhone 17 Pro | 402pt | FAIL 48 / 1 | 1512s |
| iPhone 17e | 393pt | FAIL 47 / 2 | 1449s |
| iPhone 17 Pro Max | 440pt | PASS 49 | 1430s |
| iPhone Air | 420pt | PASS 49 | 1396s |
| iPad mini (A17 Pro) | 744pt | FAIL 48 / 3 | 1443s |
| iPad (A16) | 820pt | FAIL 47 / 4 | 1504s |
| iPad Air 11-inch (M4) | 820pt | FAIL 48 / 3 | 1463s |
| iPad Pro 11-inch (M5) | 834pt | FAIL 45 / 6 | 1494s |
| iPad Pro 13-inch (M5) | 1024pt | FAIL 46 / 5 | 1527s |

红的分布（同一条红会在多台上现形）：

| 用例 | 出事的机型 | 归到第几条红 |
|---|---|---|
| `testDeviceHistoricalPanPinchAndManualY` | 五台 iPad 全中 | 第 7 条（捏合 pt 死区） |
| `testMAPeriodsTypedAndAddRemove` | 五台 iPad 全中 | 第 8 条（表单纸被键盘顶飞） |
| `testMAParameterCancelAndSaveOutput` | iPad (A16)、iPhone 16 Plus、17 Pro | 第 8 条同因 + 手机侧那条 |
| `testCompactChartStylesAndRotation` | 五台 iPad 全中 | 第 9 条（横屏出口问错问题） |
| `testDrawingAllToolsAndFingerTargets`、`testIntervalChipsSelectOneAtATime` | iPhone 17e | 第 6 条 |
| `testChangeBasisUpdatesFavorites`、`testFavoritesCategoriesAndNavigation` | iPad Pro 11" / 13" | **第 10 条（星的感应区）** |
| `testFavoritesCategoryOverflow` | iPad Pro 11" | 未复现，见第七节 |

矩阵跑的是基线 `9c3a79b`，第 1～6 条红在它之前就修掉了（所以这一轮只剩后面那几条现形）；
第 7～9 条在 `9be45c3` 修完并复验；第 10 条是这张表逼出来的，修在本轮最后。

## 五、顺手修掉的一颗雷

三台 iPad 第一轮各红一条，且都不是断言红，是 XCUI 当场抛
`Failed to get matching snapshot: No matches found`，位置在 `hittable()` 里的 `el.frame`。

`exists` 挡不住 `.frame`——答「在」之后、取 frame 之前的那一帧里按钮已经淡出去了。
这和那段注释里**已经挡住**的 `isHittable` 问题是同一回事，只是深了一层。
iPad 上更容易撞：图更宽、视野归位滑得更久。

改成从 `try? el.snapshot()` 这一张快照上读「在不在 / 有没有面积」——
这是这组接口里唯一会把「没这个元素」老实交成 Swift 错误的路径。改完三台重跑全过（`f26c7a6`）。

这是存量问题，不是这轮引入的；按项目规矩直接修了，没停下来请示。

## 六、全量矩阵翻出来的十一条红（都已从根因修掉）

把 13 台矩阵真跑起来之后，一共红了十一条。查到底之后分成两类：
**五条是 app 自己的缺陷**（首屏空图、自选页被标签栏吃掉一栏安全区，
以及 iPad 上那三条——双指缩放的死区、指标编辑纸被键盘顶飞导致第一下被吃掉、
搜索结果里那颗星的感应区被整行压过去），
**六条是用例的点法不对**（周期条药丸判不着、自选拖动排序、MA 输出开关，
17e 上那两条——周期条药丸与「工具」，和 MA 开关是同一个机制，
外加 iPad 上的「横屏出口」——那条是用例在 iPad 上问错了问题）。
app 那五条里，前四条各自补了会红的回归用例；第 10 条不用补——`testChangeBasisUpdatesFavorites` 与 `testFavoritesCategoriesAndNavigation` 在 iPad Pro 上本来就替它红了，只要矩阵还跑这两台，它就有人盯着。用例那六条改的是用例，一行产品代码都没动。

前六条来自手机，**后三条只在 iPad 上红**，单独放在第 7～9 条里。

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

**7. iPad 上双指怎么捏都不缩放——缩放被一条按像素密度算的死区全挡掉了（app 侧）**

`testDeviceHistoricalPanPinchAndManualY` 在两台 iPad 上稳定红在 `chart.canvas` 捏完之后
「间距没变」。先复现机制：在 app 侧给手势装了一个只进不出的累加器，把每一帧两指的
**实际间距**写进图表的无障碍 `value`（`gestureTrace`），再让用例原样捏一次。读出来的样本是：
`pinch(withScale: 1.5)` 全程最大只分开到 **≈20pt**，`scale: 2` 到 **≈28pt**，`scale: 3` 到 **≈42pt**——
XCUI 合成的两个触点起手就只隔 ≈6pt，**分开的绝对距离跟被捏的视图多大毫无关系**。

而 `ChartView+Gesture.updatePinch` 里的门槛写的是 `50.0 / displayScale`：
3x 的手机 = 16.7pt，**2x 的 iPad = 25pt**。于是 1.5 倍那一捏在 iPad 上**每一帧都被丢掉**，
手机上却刚好够得着——这就是「只有 iPad 红」的全部原因。真手指捏得开，所以人测不出来，
它是一条**只在小幅捏合时发作**的真缺陷：iPad 上轻捏一下同样不动。

同一个 `guard` 里还藏着第二颗雷：基准 `pinchD0` 只在 `pinchActive` 时才重新对齐，
于是一路被丢掉的那些帧把比例攒了起来，等间距一跨过门槛，`d / d0` 会**一次性甩出去**——
`scale: 2` 实测把 spacing 从 4 直接甩到 18.4（×4.6），图会「嘭」地跳一下。

改法两处，都在根上：

- `Chart.minPinchSpanPt = 10`，单位是 **pt（物理尺寸）**，`KanpanCore/Geometry/Constants.swift`。
  不再按 `displayScale` 换算——那等于让 2x 的 iPad 比 3x 的手机多出一截死区，
  而「两指有多近算噪声」是个物理问题，跟屏幕密度没关系。
- 低于门槛的那几帧**照样丢，但基准跟着它走**（`pinchD0 = d; pinchMid0 = m; pinchActive = false`），
  这样跨过门槛的那一帧只放大它自己那一点位移，不会把攒下来的比例甩出来。

激活用的 `abs(d - pinchD0) > 2 * panSlopPt` 没动，捏一下就缩放的误触防线还在。
改完 iPad mini 上该用例 15.8s 通过，手机侧同一条也跟着回归验证过（见第四节）。

**8. iPad 上给 MA 加周期，第一下永远只用来收键盘（app 侧）**

`testMAPeriodsTypedAndAddRemove`（iPad A16 上还多带一条 `testMAParameterCancelAndSaveOutput`）
红在「点了『添加周期』但周期数没变」。先复现机制：在用例里把**导航栏的 frame** 和
**键盘的 frame** 一起打出来，得到的是硬数字（iPad mini，屏 744×1133）：

- 指标编辑器是一张 620pt 高的表单纸，正常居中，导航栏在 **y = 256.5**；
- 数字键盘的 frame 是 `(0, 848, 744, 282)`，跟纸的下沿只重叠 **28.5pt**；
- 可键盘一起来，UIKit 把**整张纸重新居中**，导航栏跳到 **y = 86.5**——为了让开 28.5pt，
  纸整体抬了 **170pt**。

于是这一下的时序是：手指落在「添加周期」上 → 焦点离开输入框 → 键盘收起 →
**纸在手指还没抬起时落回原位** → SwiftUI `Button` 的按压跟踪把这一跳读成「手指移出去了」，
按压被取消，`action` 不触发。用户的第一下只换来一个收键盘。

排除过的三个方向（每个都实测，然后回退）：

- 去掉 `.scrollDismissesKeyboard(.interactively)`——数字一模一样，不是它；
- 换成 `.scrollDismissesKeyboard(.never)`——照样红；
- `.presentationSizing(.form.fitted(...))`——**更糟**，纸缩到键盘起来时只剩一行可见，
  `indicator.param.add` 连找都找不到了。
- 「等纸稳定再点」也不行：专门写的 `testZZZMAAddSettled`（等 frame 不再变化才点）同样红——
  因为纸是**在这一下自己引发的键盘收起里**跳的，点之前它还没开始跳。

改法：把表单里这两行从 `Button` 换成 `Text` + `contentShape(Rectangle())` + `.onTapGesture`
（`Kanpan/Panels/IndicatorPanel.swift` 的「添加周期」与「恢复默认颜色」），
并补回 `.accessibilityAddTraits(.isButton)`。**手势识别器不跟着视图跑**，纸怎么跳它都认这一下。
顺带量过：导航栏上的「保存」「取消」是 toolbar item，**不在这张纸里，不受影响**，所以没动。

这是一条真缺陷而不只是用例问题——真人在 iPad 上编指标周期时，第一下同样是废的。

**9. iPad 转个屏没有「竖屏」按钮——用例在 iPad 上问错了问题（用例侧）**

`testCompactChartStylesAndRotation` 在 iPad 上红在「横屏没有回竖屏的出口」。
查下来 app 是**按设计在跑**：iPad 横过来 `verticalSizeClass` 仍然是 `.regular`，
`landscape` 判定为假，所以根本不进横屏画线工作台，也就没有 `land.exit`；
`MainScreen.enterLandscape()` 在 iPad 上走的本来就是 `expandedChart` 而不是转屏
（横屏是画线的工作台，不是一个独立入口——这是定过的口径）。

所以改的是用例：按 `userInterfaceIdiom` 分叉（`AICoinBaseUITests:165` 已有同样的先例）。
iPad 分支反过来断言**不该**有 `land.exit`、底栏还在；手机分支保留原断言，
并且把它从原来的「断言 `land.exit` **不存在**」改成**断言它存在**——
锁了方向的手机转不回去，进了横屏却没有出口就成了单程票，只能杀进程。
iPad 上那条「画线 → 工作台」的路由由 `AICoinBaseUITests` 守着，没有漏掉。

**第 7～9 条修完之后的复验**

受影响的六条用例（`testMAPeriodsTypedAndAddRemove`、`testMAParameterCancelAndSaveOutput`、
`testIndicatorColorSaveCancelAndRestart`、`testDeviceHistoricalPanPinchAndManualY`、
`testCompactChartStylesAndRotation`、`testOutsideTapOnlyDismissesPanel`）在三台上各跑一遍，全绿：

| 机型 | 结果 | 用时 |
|---|---|---|
| iPad mini (A17 Pro) | 6/6 通过 | 188s |
| iPad (A16) | 6/6 通过 | 204s |
| iPhone 16 Pro | 6/6 通过 | 190s |

手机那一台是**防倒退**跑的：捏合的门槛从 `50/displayScale`（手机 16.7pt）改成固定 10pt，
等于把手机侧的死区也放宽了，所以必须确认手机上的缩放与画线没有跟着变松——`testDeviceHistoricalPanPinchAndManualY`
16.6s 通过，捏一下就缩放的误触防线由没动过的激活门槛（`2 * panSlopPt`）继续守着。

**10. iPad Pro 上点搜索结果里的星，加不上自选，反而跳去开图表（app 侧；矩阵跑完才翻出来的一条）**

`testChangeBasisUpdatesFavorites` 与 `testFavoritesCategoriesAndNavigation` 只在 iPad Pro 11"（834pt）
和 13"（1024pt）上红，报的是 `search.cancel` 找不到；把当时的界面树打出来才看清，搜索页早就没了，
底栏停在「图表」——也就是说点星那一下走的是**开品种**，不是**加自选**。

三台 iPad 同时探，结论很干净（`favoriteAdded` 是点完星之后回自选页看那一行在不在）：

| 机型 | 窗口宽 | 行按钮框 | 星框 | 点完星 | 加上了吗 |
|---|---|---|---|---|---|
| iPad Pro 11" (M5) | 834pt | 153…648 | 663.25…675.75 | 搜索页关了、底栏跳到图表 | **否** |
| iPad Air 11" (M4) | 820pt | 146…641 | 656.25…668.75 | 留在搜索页 | 是 |
| iPad mini (A17 Pro) | 744pt | 108…603 | 618.25…630.75 | 留在搜索页 | 是 |

三台的行宽都是 495pt（560 封顶减两侧 16pt 内边距、再减星和 10pt 间距），相对排版一模一样，
只有左边距不同——所以光看框子看不出为什么只有 Pro 会输。于是沿着星横扫一排落点，逐点记谁接走了这一下：

| 落点（相对星心） | iPad Pro 11" | iPad Air 11" |
|---|---|---|
| −40pt | 行 | 行 |
| −24pt | 行 | 行 |
| −16pt | 行 | 行 |
| −8pt | 行 | 行 |
| **0（星的正中）** | **行** | 星 |
| +6pt | 星 | 星 |

**点在星自己报出来的正中，接走这一下的却是「行」**——而行按钮的框子只到 648，
说明它的实际感应区往右溢出了二十来点。根因是两头一起夹：

- 星这一侧，`Button` 的 label 是 `StarShape().fill(...)`，`.buttonStyle(.plain)` 下 SwiftUI
  拿 **label 的路径**当感应区，那是个带凹口的 12×12 星形，能接的面积本来就只剩一小撮；
- 行这一侧，铺满整行的按钮感应区会往外溢出一截，正好压在星上。

**为什么偏偏是 Pro，这一条没查实，不写进结论。** 三台的相对几何是一模一样的：
星心离行右边缘都是 21.5pt、离星左边缘都是 6.25pt，连小数位都对得上，所以「Pro 宽一点所以重叠多一点」
这种说法是站不住的。能证到的只有两件事：**在 Pro 上点星心接走的是行**，以及**补上矩形感应区之后两台行为一致**。
触发它的那个设备侧差异（ProMotion？命中测试的时序？）没有证据，不给它安名字。
但这不影响定性——这不是测试的问题，真人在大 iPad 上点那颗星，点到的就是整行。

修法是给星按钮补一块矩形感应区、并把它从 23pt 撑到 35pt（星本身还是 15pt，视觉没动）：
`.frame(width: 15, height: 15).padding(10).contentShape(Rectangle())`。
同一把横扫尺子复测，两台的交界都回到了行与星之间该在的位置，宽度带来的差别消失：

| 落点（相对星心） | iPad Pro 11"（修后） | iPad Air 11"（修后） |
|---|---|---|
| −40pt | 行 | 行 |
| −24pt | 行 | 行 |
| −16pt | **星** | **星** |
| −8pt | 星 | 星 |
| 0 | 星 | 星 |
| +6pt | 星 | 星 |

**第 10 条修完之后的复验**

受影响的三条用例（`testChangeBasisUpdatesFavorites`、`testFavoritesCategoriesAndNavigation`、
`testFavoritesCategoryOverflow`）在三台上各跑一遍，全绿：

| 机型 | 结果 | 用时 |
|---|---|---|
| iPad Pro 11" (M5) | 3/3 通过 | 137s |
| iPhone 16 Pro | 3/3 通过 | 112s |
| iPad mini (A17 Pro) | 3/3 通过 | 129s |

手机与 mini 那两台是**防倒退**跑的：星的感应区从 23pt 撑到 35pt，行按钮相应窄了 12pt，
要确认窄屏上行本身还点得开、价格那一列没有被挤坏——三条都过，其中
`testFavoritesCategoriesAndNavigation` 走的就是「点行进图表」那条路。
`testFavoritesCategoryOverflow` 另在 iPad Pro 11" 上连跑四遍全绿（70s / 65.6s / 63.8s / 52.6s）。

## 七、未做 / 边界

- ~~**`testFavoritesCategoryOverflow` 在 iPad Pro 11" 上红过一次，但复不出来。**~~
  **2026-09-19 复现出来了，根因查实并修掉。** 详见下面第九节。

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

## 九、iPad Pro 那条边界：2026-09-19 复现出来了，根因查实

第七节原本把 `testFavoritesCategoryOverflow` 在 iPad Pro 11-inch (M5) 上那一次红记成
「红了但没查实」。2026-09-19 复现成功，根因确定，用例已改，**不是 app 的缺陷**。

### 现象是怎么发生的

矩阵那一轮的日志（`docs/acceptance/M8/ui-test/iPad-Pro-11-inch-M5.log`，第 4395 行附近；2026-09-24 已删，`git show b5a4d543:<路径>` 取回）：

```
t = 22.50s Tap "favorites.more" Button
t = 22.55s     Check for interrupting elements affecting "favorites.more" Button
t = 22.60s         Wait for com.apple.mobileslideshow to idle   ← 照片 App 抢了前台
t = 31.23s     Open com.mdd.kanpan / Activate com.mdd.kanpan    ← XCUITest 自己拉回来
t = 31.90s     Synthesize event                                 ← 这一下点击丢了
t = 32.32s Waiting 4.0s for "favorites.newGroup" Button to exist ← 菜单没开，红
```

那 8.7 秒空档不是 app 卡住，是 XCUITest 的「Check for interrupting elements」在等
**另一个 app**（照片，`com.apple.mobileslideshow`）进入 idle。被测 app 在这期间掉到后台，
XCUITest 再用 `Open` / `Activate` 把它拉回来——那一下已经合成好的点击落在刚重新激活的 app 上，
被丢掉。`com.apple.mobileslideshow` 在 13 台 × 49 条日志里**只出现过这一次**，就在挂掉的那一秒，
这就是它复不出来的原因：它要的是别的进程恰好在那一秒抢前台。

同一机制还有第二种死法：app 在后台时，XCUITest 把**我们自己的**「新建分类」弹窗当成
「打断元素」，用默认处理器点掉了「取消」，之后的「保存」自然点不到
（`Failed to compute hit point`）。

**真实用户碰不到这个现象**——用户手动切走再切回来，点击是他自己重新点的。
这是用例在「前台被抢走」这个边界上一点容错都没有。

### 怎么复现的

`xcodebuild test-without-building` 跑起来之后轮询日志，命中某一步的标记就立刻
`xcrun simctl launch <udid> com.apple.mobileslideshow`，把照片推到前台。
两个注入点各自复现出上面两种死法：

- 注入在 `Tap "favorites.more" Button`：`Computed hit point {-1, -1}` / `Not hittable`。
- 注入在 `Type '长期关注'`：`Default interruption handler attempting to dismiss alert by
  tapping …cancel-button`，接着 3 次 `Retrying Tap "保存"`，最后
  `no matches found for Descendants matching type Alert`。

### 改了什么

`Kanpan/KanpanUITests/ChartFoundationUITests.swift`：

- `ensureForeground()`：app 不在前台就 `activate()` 再等 10s，拉不回来才判红。
- `waitHittable(_:seconds:)`：先走一次 `exists && isHittable` 快路径，不成再轮询到 6s。
  前台被抢的那几秒里元素会「存在但点不动」，直接 `tap()` 抛的
  `Failed to compute hit point` 是 XCTest 自己记的失败，Swift 接不住，所以只能点之前先探。
  快路径是必须的：`XCTNSPredicateExpectation` 首次求值前先睡约 1 秒，这条用例上有二十来个
  这样的点，不走快路就是整整 +20 秒（65s → 81s）。
- `openFavoritesMenu()` / `tapFavoritesMenuAction(_:)`：最多两遍，返回 `Bool` 不断言。
  **菜单已开时绝不重点「…」**——`FavoritesView` 的「…」是自绘浮层，菜单一开就有一层
  `Color.black.opacity(0.001)` 的吃点击遮罩盖在它上面，再点一下等于把菜单关掉。
- `createGroup(_:)`：**整步**重试（清残留弹窗 → 开菜单 → 打字 → 保存 → 等胶囊出现），
  最多两遍，判据只有一个——`favorites.group.<名字>` 出没出来。
- `dismissStrayAlert()`：先摆回前台再点「取消」，模态弹窗不收掉后面的「…」永远点不动。
- 重试路径上一概不用 `XCTAssert*`：`continueAfterFailure = false` 下第一次断言失败就地终止，
  第二遍根本走不到。

`Tools/ui-test.sh`：每台开跑前 `simctl terminate` 掉照片 / 设置 / 信息，把撞上的概率先按下去；
自愈仍然靠用例侧的守卫。

**容错没有把真缺陷吞掉**：重试都有明确上限（2 遍 / 3 遍），失败信息里写明「重试一次仍然…」；
`ensureForeground()` 拉不回前台照样红；分类建不出来照样红。

### 验证

| 场次 | 机型 | 结果 |
|---|---|---|
| build-for-testing | generic/iOS Simulator | `** TEST BUILD SUCCEEDED **` |
| 干净跑（先 `uninstall`） | iPad Pro 11-inch (M5) | 0 failures，62.29s |
| 注入照片 @ `Type '长期关注'` | iPad Pro 11-inch (M5) | 0 failures，63.48s |
| 注入照片 @ `Tap "favorites.more"` | iPad Pro 11-inch (M5) | 0 failures，67.22s |
| 双注入（命中即启动，2.5s 后再来一次） | iPad Pro 11-inch (M5) | 0 failures，66.41s |
| 同一条用例 | iPhone 16 Pro | 0 failures，61.83s |

主窗口另跑了两轮独立复验（主工作树的构建产物，不是子代理那棵临时工作树）：
注入 `Tap "favorites.more"` 那一轮日志里 `t = 15.54s Wait for com.apple.mobileslideshow to idle`
→ `Open` / `Activate com.mdd.kanpan` → `Computed hit point {-1, -1}` / `Not hittable`
**机制原样复现**，而用例整步自愈、61.19s 全绿。

### 顺带澄清：另外两条红不是同一个机制，没有动它们

`testChangeBasisUpdatesFavorites` 与 `testFavoritesCategoriesAndNavigation` 在同一台 iPad 上的
`Failed to tap "search.cancel" Button: No matches found`，和前台被抢无关：

1. 两处失败上下文里**没有** `mobileslideshow`、没有等别的 app idle、也没有任何
   `Open` / `Activate com.mdd.kanpan`——app 全程没掉后台。
2. 随失败打印的可访问性树是**行情页**（`top.search`、`interval.chart`、`bottom.chart` Selected），
   说明全屏搜索层已经关掉、app 已经跳到品种页了——`search.cancel` 不是「点不中」，
   是**它已经不该存在**。

硬套前台守卫只会把一个真实的交互问题遮住，所以保持原样。
