# kanpan-run-only-affected-ui-tests

**项目约定**：看盘改动验证只跑受影响的真机 UI 用例，不要动辄跑整套套件，真机跑测必须开超时

看盘（Kanpan）的 `KanpanUITests` 是真机 XCUITest：每个用例都要冷启动一次 app、
等真实行情网络回第一批 K 线，单个用例 8～135 秒，三套加起来三四十个用例，
一轮就是半小时起步。我为了验证两处小改动（副图把手删除、一条过期断言）
把 `AICoinBaseUITests` / `ChartFoundationUITests` / `MainScreenUITests` 整套拉起来跑，
用户接连问了四次「测试是不是卡住了」「我看设备上很久都没被点击 app 了」
「测试又卡住了」「怎么要测试这么久」，最后直接把任务杀掉了。

所以规矩是：**改了什么就只跑覆盖它的那几个用例**。先用 grep 找出断言里出现相关
accessibility id 的用例（例如 `chart.resize` 只被 `testResizeDividerWithinOneScreen`、
`testFourSubpanelsFitWithoutPageScroll`、`testHeightAndVerticalReachability` 三个用例覆盖），
再用 `-only-testing:KanpanUITests/<类>/<用例>` 精确点名，一分钟出结果。
整套回归留给真正需要全量验收的时候，并且事先告诉用户大概要跑多久。

另外真机跑测**一定要带上超时**：
`-test-timeouts-enabled YES -maximum-test-execution-time-allowance 240`。
真机上 XCTest 在用例之间恢复设备方向时会卡死——手机平放在桌上时方向是「Face Up」，
它等竖屏永远等不到（日志里会看到 `Device orientation changed to Face Up`，
后面就再无输出）。不加超时就是无限期挂死；加了超时它会把那个用例判超时然后重启继续跑。

2026-09-17 补充：这条同样约束我派出去的实现子代理。用户在 Opus 子代理开工后又专门说了一句
「注意测试范围只测试你改动的，不要全部测试浪费时间」。所以交接说明和给子代理的提示词里都要
明确写：只用 `-only-testing:` 跑与改动直接相关的用例、每条带超时、不跑整个测试类或整套套件，
并要求回执里列出实际跑过的用例名。

2026-09-17 再补一条：连「自选页相关的八个用例」都嫌多。我把自选页整页重做后让子代理把
ChartFoundationUITests 里所有 testFavorites* 加上冷启动、涨跌口径共八条都跑一遍，用户中途打断：
「怎么还在测试，要测试这么多东西，只测试你改动的就可以了啊」。所以「受影响」的口径要更窄——
一次改动只点名一到两条直接覆盖它的用例（改了哪条断言就跑哪条，重做一张页就跑它的主路径那一条），
其余靠真机装上去看。视觉改动（字号、颜色、材质）不需要跑 UI 测试，编译通过、装机看一眼即可。
