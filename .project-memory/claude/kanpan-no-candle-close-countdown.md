# kanpan-no-candle-close-countdown

**项目约定**：看盘 2026-10-03 起行情页不再展示 K 线收盘倒计时（价格轴最新价标签下那行「本根收线还剩多久」），iOS、手机网页、电脑网页都去掉；头部「结算」格的资金费率结算倒计时是另一回事，保留

# 行情页不展示 K 线收盘倒计时

2026-10-03 用户说：「**行情页不再展示 k 线收盘倒计时，用户用不到**」。

这指的是 K 线图右侧价格轴上、最新价标签下面那一行「本根 K 线离收线还剩多久」的计时。
它原本照 AICoin 常开（iOS `Prefs.chartOptions` 里 `countdown = true`，手机网页与电脑网页
各自也画了一份）。从这天起三端都不画，也不做成开关让用户自己打开——按
kanpan-minimal-settings-surface，用不到的东西直接拿掉，不留设置项。

不要误伤的东西：

- **头部右侧六格里的「结算」倒计时**（资金费率下次结算还剩多久，iOS `HeaderStats.fundingCountdownText`、
  网页 `fundingCountdownText` / 电脑版「下次结算」）是用户定过的格子（见
  kanpan-header-right-block-is-six-cells），和这条无关，保留。
- **图的一秒心跳**不能跟着删：它还驱动持仓量等外部副图的到点刷新和盘口时钟，只是不再为倒计时重画。

以后有人提「加回收线倒计时」或者在审查里把它当缺失的 AICoin 功能补回来，都按这条判不做
（同 kanpan-decided-not-to-do-stays-dead）。
