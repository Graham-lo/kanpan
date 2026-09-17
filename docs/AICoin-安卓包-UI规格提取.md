# AICoin 安卓包反编译 · K 线 UI 规格提取（给看盘 iOS 复刻用）

> 来源：`aic.apk`（AICoin Android），`apktool d -s` + `jadx` 静态反编译。
> 所有数值是**资源文件里的原始值**（dp / sp / hex），未做任何换算或推测。
> 标注「未确认」的条目表示资源里取不到、需要看代码或实机验证，**不要当结论用**。

## 0. 先说三个架构级结论

1. **K 线是一个原生自绘 View**：`sp.aicoin_kline.chart.Chart`（Kotlin，继承 `View`），
   主图 + 副图 + 坐标轴 + 十字光标 + 画线全在这一个 `onDraw` 里。布局文件里它只是
   `match_parent` 的占位，**图表内部的蜡烛宽度、间距、缩放上下限都不在资源里**。
   → 看盘用 UIKit 自绘单一 View 的做法和 AICoin 一致，方向没错。
2. **深度图才是 H5**：`assets/web/` 下是 Highcharts（`mode_night.js` 是它的夜间主题），只用于深度图。
3. **Flutter（`libflutter.so`/`libapp.so`）只用于 IM 和远程交易模块**，与行情/K 线无关。

## 1. 竖屏 K 线页整体结构（`res/layout/ui_kline_frg_ticker_kline.xml`）

垂直 LinearLayout，自上而下四段：

```
┌─ 周期/工具条          高 34dp   (ui_kline_part_period_portrait → ui_kline_part_setting_bar)
├─ 十字光标信息条        高 34dp   (ui_kline_frg_kline_info，默认 gone)
├─ 图表容器 (weight=1)
│    ├─ Chart #chart_kline        match_parent
│    ├─ #full_screen              24dp，gravity=start，marginStart 15dp
│    ├─ #tv_back_to_last          「回到最新」11sp，gravity=end，默认 gone
│    ├─ #tv_scale_auto            「A」12sp，gravity=end，默认 gone
│    ├─ #iv_drawing_hide          18dp
│    ├─ #iv_show_right            20dp，padding 3dp，marginEnd 18dp
│    └─ 右侧面板 #stub_kline_right  宽 105dp（横屏/详情页是 150dp），默认 gone
└─ 底部指标栏            高 25dp   (ui_kline_part_indicator_bar)
```

## 2. 三档图表高度（直接对应「K线设置 → 竖屏高度」）

| dimen | 值 | 设置项文案 |
|---|---|---|
| `ui_kline_short_vertical_height` | **300dp** | 低 |
| `ui_kline_standard_vertical_height` | **429dp** | 适中 |
| `ui_kline_tall_vertical_height` | **555dp** | 高 |

这三个 dimen **在 layout 里一次引用都没有**，只被代码在运行时读取设为容器高度——
这就是「K 线框固定大小、缩放不改变框」的实现方式，也是之前记的那条手感规则的硬证据。

文案来自 `values-zh-rCN/strings.xml`：`ui_kline_side_menu_title_chart_ticker_detail_height` =「竖屏高度」，
三档 `_short`/`_middle`/`_tall` =「低 / 适中 / 高」，另有 `_default` =「(默认)」后缀。
哪一档带「(默认)」资源里**未确认**，从命名相邻与 429 居中推测是「适中」。

**这三个值是整块 K 线容器（主图 + 副图）的高度**，不含 34dp 周期栏、34dp 信息条、25dp 指标栏。

## 3. 「A」自动定标徽章 —— 与看盘当前的「R」不一致

`#tv_scale_auto`（`ui_kline_frg_ticker_kline.xml`）：

```xml
android:text="A"
android:textSize="12.0sp"
android:textColor="@color/sh_base_three_text_color"   <!-- #ff7a8899 -->
android:background="@color/sh_base_one_background_color" <!-- #fff7f8fa -->
android:layout_gravity="end"
android:paddingTop/Bottom="2.0dp"  android:paddingStart/End="6.0dp"
android:layout_marginEnd="@dimen/ui_kline_overlay_show_right_icon_left_margin"  <!-- 18dp -->
carbon:carbon_cornerRadius="2.0dp"
android:visibility="gone"
```

即：**安卓包里这颗钮的字面是「A」（Auto），不是「R」**，而且是弱色小徽章（灰字浅底、圆角 2dp），
不是高亮按钮。最近那个 commit 里的「AiCoin 式「R」复位钮」，至少在安卓包上对不上。
（iOS 版是否不同未验证——这是安卓包的事实，不是对 iOS 版的断言。）

相关代码侧证据：`Chart` 的 Kotlin metadata 里有
`isMainYAxisScaled: Boolean` 属性和 `onMainYAxisScaleStateChanged: (Boolean) -> Unit` 回调，
徽章的显隐就是挂在这个状态上的——**手动定标时显示，点一下回自动**。

配套的浮层位置常量（`dimens.xml`）：
`ui_kline_overlay_scale_auto_extra_lift` 8dp、`..._spacing_to_show_right` 44dp、
`..._spacing_index_land` 18dp / `..._spacing_index_portrait` 12dp /
`..._spacing_land` 12dp / `..._spacing_main_portrait` 6dp。

## 4. 「回到最新」chip（`#tv_back_to_last`）

```
textSize 11sp / textColor carbon_white / background sh_base_highlight_color (#1478fa)
padding 上下 2dp、左右 4dp / cornerRadius 2dp / layout_gravity=end / 默认 gone
文案 @string/ui_kline_kline_local_back
```
与「A」徽章对比：**「回到最新」是蓝底白字的实心 chip，「A」是灰字浅底的弱徽章**，两者视觉权重明确分级。

## 5. 十字光标信息条（`ui_kline_frg_kline_info.xml`）—— 不是浮动 tooltip

AICoin **没有跟手的气泡 tooltip**，而是在图表**上方固定一条 34dp 的信息条**（默认 gone，长按十字光标时显示）：

- 高 **34dp**，`paddingTop 1dp`，`paddingStart/End 18dp`，背景 `ui_kline_info_data_bg_color`（日 `#fff7f8fa` / 夜 `#0d111c`）
- 8 个 TextView 全部 **9sp**，色 `ui_kline_info_data_text_title_color`（日 `#ff7a8899` / 夜 `#daeaff`）
- 2 行 × 4 列，列间距 18dp，行间距 4dp：

| | 列1 | 列2 | 列3 | 列4 |
|---|---|---|---|---|
| 行1 | 日期 | 最高 | 开 | 涨跌 |
| 行2 | 时间 | 最低 | 收 | 振幅 |

横屏版 `ui_kline_frg_kline_info_land.xml` 同构，高度改 `wrap_content` + 上下 padding 5dp。

## 6. 顶部周期/工具条（34dp，`ui_kline_part_setting_bar.xml`，竖横共用）

横向 LinearLayout，按 weight 分配宽度：

| # | id | 内容 | weight |
|---|---|---|---|
| 1-5 | `btn_period_first..fifth` | 分时 / 5分 / 10分 / 15分 / 15分（运行时被用户自定义覆盖） | 1.0 each |
| 6 | `btn_more` | 更多 + 下拉箭头 | 1.0 |
| 7 | `btn_indicator` | 指标 + 箭头 | 1.0 |
| 8 | `btn_advanced` | 高级 + 箭头 | 1.0 |
| 9 | `btn_hide` | 隐藏（gone） | 1.0 |
| 10 | `btn_setting` | 齿轮图标 18dp | **0.8** |
| 11 | `btn_hide_sub` | 开关图 48dp×16dp +「副图」 | **3.2** |

- 选中态 = tab 底部一条 **18dp × 2dp** 的指示条（`ui_base_selected_tag_bottom_bar_selector`，`gravity=center|bottom`）
- 文字 **12sp**，颜色走选中/未选中 selector（`ui_base_title_text_tint_color_selector`）

## 7. 底部指标栏（25dp，`ui_kline_part_indicator_bar.xml`）

- 左右两个横向滚动 RecyclerView，weight 各 1.0：左=主图指标（paddingRight 5dp），右=副图指标（paddingLeft 5dp）
- 中间竖分割线 **0.5dp**，上下 margin 6dp，色 `ui_kline_indicator_bar_divider_color`（日 `#eaeaea` / 夜 `#20232e`）
- item 文字 **11sp**，左右 padding 10dp

## 8. 色板（日 / 夜成对）

AICoin **不用 `values-night`**，而是同一份 `colors.xml` 里 `xxx` / `xxx_night` 成对条目，
控件上写 `android:tag="skin:<资源名>:<属性>"` 在运行时换肤。iOS 侧相当于「这个属性跟随主题」。

| 语义 | 日间 | 夜间 |
|---|---|---|
| 主高亮（蓝） `sh_base_highlight_color` | `#1478fa` | `#1060c8` |
| 涨（绿） `base_ui_color_green` | `#32a853` | `#268040` |
| 跌（红） `base_ui_color_red` | `#eb4236` | `#a61717` |
| 实心涨块 `sh_base_block_fill_green` | `#32a853` | `#2f9347` |
| 实心跌块 `sh_base_block_fill_red` | `#eb4236` | `#992323` |
| **行情页底 / 画布** `sh_base_view_bg` | `#ffffff` | `#0d111c` |
| **周期栏 / 指标条底** `ui_kline_menu_bg_color` | `#ffffff` | `#0d111c` |
| 列表页底（自选那一层） `sh_base_page_bg` | `#f7f8fa` | `#090c14` |
| 带蓝的浅底 `sh_base_bg_color` | `#f7f9ff` | `#0d111c` |
| 一级文字 `sh_base_one_text_color` | `#292d33` | — |
| 二级文字 `sh_base_two_text_color` | `#525a66` | — |
| 三级文字 `sh_base_three_text_color` | `#7a8899` | — |
| 四级文字 `sh_base_four_text_color` | `#b7bfc8` | `#515a66` |
| **K 线页分隔线** `ui_kline_divider_color` | `#f2f4f7` | `#191c21` |
| **周期 / 指标条分隔线** `ui_kline_indicator_bar_divider_color` | `#eaeaea` | `#20232e` |
| 通用列表分割线 `sh_base_divider_dim_fill_color` | `#dee1e5` | `#25282e` |
| 弹窗底 `sh_base_dialog_bg_fill_color` | `#ffffff` | `#202126` |
| 画线默认色 `ui_kline_drawing_default_line_color` | `#1990ff` | — |

**别拿 `sh_base_bg_color` 当行情页底。** 它是那支带蓝的浅白，K 线页根本不引用它；2026-09-17 照它
配「经典·浅」，用户在真机上一眼看出「AICoin 的白没这么白亮」。真机逐像素量过 AICoin 行情页：
标题、价格行、周期行、主图、副图全是 `#ffffff`，只有最底下的标签栏是 `#f3f3f5`。安卓侧对得上——
`sh_base_view_bg` 被引用 23 次、`ui_kline_menu_bg_color` 7 次，都是纯白。

**分割线也别拿错令牌。** 和上面同一类错误：2026-09-17 把 `sh_base_divider_dim_fill_color`
（`#dee1e5`，通用列表分割线）当成了 K 线页的分隔线，于是主图 / 时间轴 / VOL / 持仓量 / MACD
之间，加上右轴那条竖线，整屏 8 条灰线把一张纯白页面切成了格子。K 线页自己的那支是
`ui_kline_divider_color` = `#f2f4f7`（`res-full/layout-land/ui_kline_frg_ticker_detail_kline.xml:23`
里那条 1dp 竖线用的就是它），周期条 / 指标条上下那条是 `ui_kline_indicator_bar_divider_color`
= `#eaeaea`。量化对比：`#dee1e5` 离纯白的亮度差约 0.257（对比度 1.32），`#f2f4f7` 只有约 0.035
（对比度 1.04），旧值是新值的七倍。AICoin 真机镜像上同位置量到 `#f6f8fc` / `#f9fafe`
（镜像把颜色往白里洗约 12%，还原回去正是 `#f2f4f7`）。

注意涨跌块还有 `_transparent_10`（`#1a…`）和 `_transparent_50`（`#80…`）两档透明变体，
用于成交量柱/背景填充这类需要压低权重的场合。

`_blue` / `_blue_night` 那一整套（286 个 token）**不是第三套涨跌配色**，已量化确认：
日间 286 个里 246 个与无后缀完全相同，涨跌色与品牌色逐字节一致，差异 37 个全部落在中性灰族
且方向一致（纯灰 → 蓝灰）。它是设计系统的第二套「中性色相」皮肤，dex 里有成对的 `classic` / `blue`。
K 线布局对 `_blue` 的引用次数是 **0**。**iOS 侧整套忽略，只用无后缀（classic）那一套。**

## 9. 弹窗/面板尺寸常量（`dimens.xml`）

| 常量 | 值 |
|---|---|
| 周期弹窗高 / item 高 | 170dp / 34dp |
| 指标弹窗高 | 355dp |
| 「更多」主菜单 | 90dp × 190dp（无高级功能时 130dp） |
| 「高级」菜单 | 145dp × 190dp |
| 弹窗箭头 | 8dp × 4dp（实际布局里画的是 11dp × 6dp） |
| 弹窗边距 | 10dp |
| 横屏侧栏宽 | `255sp`（资源里单位写成 sp，按 255dp 理解） |
| 侧栏标题栏高 / 标题字号 | 26dp / 16sp |
| 侧边指标项高 / 字号 | 40dp / 12sp |
| 横屏顶栏高 | 37dp |

三个下拉面板标题：**K线指标 / 图表设置 / 高级功能**。

## 10. Chart 自绘 View 的公开 API（jadx，Kotlin metadata 未混淆名）

`sp/aicoin_kline/chart/Chart.java`：

```
setCurrentDataSource(String template)
onTouchEvent / computeScroll / onDraw(Canvas) / onDetachedFromWindow
isMainYAxisScaled: Boolean                       // ← 「A」徽章的状态源
onMainYAxisScaleStateChanged: (Boolean) -> Unit  // ← 手动/自动定标切换回调
onMagnifierStateChanged: () -> Unit              // ← 画线放大镜
t(baseHeight, indicatorCount, lowerThanBaseHeightAllowed): Int   // 高度分配算法
s(totalHeight, indicatorCount): Int                               // 同上
P(Map<String, g> data, loadEarlier: Boolean, refreshData: Boolean) // 数据灌入
g0(price) / b0(showBackground, bgColor) / c0(lineColor) / d0(lineDash) / e0(lineWidth)
getLastDate / getFirstDate / getDataCount / getDataRealCount
```

数据模型：`AISRLData`、`LargeOrderItem`、`LargeTradeItem`、`LiQuiLineItem`、`AIHandleLineItem`、
`AlertLineItem`、`AIWinRateItem`、`EstimatedLiqVpcTimePoints`、`ScriptDrawData`、`OutSideIndicData`、`drawing/DrawingItem`。

**`t()` / `s()` 这两个方法说明「总高度 + 副图个数 → 各段高度」是一个明确的算法**，
不是等分——值得后续把这两个方法体挖出来，看盘的主/副图高度分配可以直接照抄。

## 11. 周期清单

固定周期（`kline_menu_time_*`）：分时、1分、3分、5分、10分、15分、30分、1时、2时、3时、4时、6时、12时、
1日、2日、3日、5日、周K、月K、季K、年K。

PRO 专属：1秒、30秒、45分、90分、8时、16时、32时、10日、15日、20日、45日。
自定义周期支持秒/分钟/小时/日四种单位（`ui_kline_popup_period_selector`，74dp × 144dp）。

周期栏默认五格 + 「更多」，「周期设置」页可拖动排序，**至少选五个周期**（`ui_kline_period_save_tips`）。

## 12. 指标清单

**主图**：MA、EMA、BOLL、SAR、BBI、BBW、ENE、DC、KC、Ichimoku、Alligator、TD、AI-SRL 智能撑压线、VPVR 筹码分布。

**副图**：VOLUME、TVolume、MACD、KDJ、SKDJ、RSI、StochRSI、WR、OBV、CCI、DMI、DMA、TRIX、BIAS、PSY、
ROC、VR、EMV、BRAR、MTM、ATR、AO、DPO、MFI、SMI、BSV、Fund-flow、OI、BASIS、FR、PFR、FTBS、LSUR、MLR、
TTMU、TTSI、LiqHeatmap。

**指标默认参数值（MA5/10/20、MACD 12/26/9 等）在资源里取不到**，写死在 dex 里；
参数输入框的 `android:text` 和 hint 都是空的。要用的话得从代码里挖。

指标菜单分类：已选/推荐、常用指标、主图指标、副图指标、趋势型、能量型、成交量型、超买超卖、
压力支撑、特色指标、合约数据、现货数据、指标胜率。约束文案：「至少选择四个指标」「额外指标最多开启五个」「长按可设置指标」。

## 13. 横屏差异

横屏（`res/layout-land/ui_kline_frg_ticker_kline.xml`）顶栏高 **37dp**，把币对名、最新价、周期工具条
全部合并进一行；**没有** 全屏按钮、右侧面板开关、「A」徽章、底部指标栏。
画线工具条（右侧竖条 `ui_kline_part_drawing_menu_bar` + 底部浮动条 + 放大镜菜单）**只在横屏挂载**。

横屏顶栏元素：左右翻页箭头 22dp（padding 4dp）、币对名 13dp / 副标题 10dp（容器 minWidth 100dp）、
主价格 **21dp**、涨跌箭头 marginLeft 4dp、返回键 padding 8dp、「退出画线」14sp 描边按钮。

## 14. 图表浮层

| 浮层 | 尺寸 |
|---|---|
| 主力大单 `ui_kline_part_large_order_info` | wrap × **210dp**，margin 左8/上12/右60dp，elevation 4dp |
| 大额成交 `ui_kline_part_large_trade_info` | **宽 140dp**，padding 上6/下10/左右10dp |
| AI 撑压 `ui_kline_part_aisrl_info` | padding 12/10，标题 12sp bold，明细 10sp |
| 空数据 `ui_kline_part_empty_data` | minHeight 200dp，文字 14sp，marginRight 60dp |
| 预警线气泡 | 12sp bold 白字 / 底色写死 `#1478fa` / 圆角 4dp / marginTop -12dp |
| 加载态 | 竖屏 marginTop **168dp** |

## 15. 右侧 105dp 面板（`ui_kline_include_kline_right.xml`）

竖屏 105dp / 横屏与详情页 150dp，默认 gone，由 `#iv_show_right`（20dp）切换。
顶部三个 tab 行高 **16dp**（marginTop 5dp），文字 **10sp**，padding 左右2/上下1dp，圆角 2dp，
选中 = 高亮色字 + 透明高亮底；tab 为 **主力 / 大额 / 筹码**。

---

## 未确认 / 别当结论用

- `assets/fonts/` 里有 DIN-Regular/Medium/Bold，但 **dex 和 layout 里都没有任何引用**
  （只引用了 `fonts/digital-7.ttf`，`res/font/` 里只有 `roboto_medium_numbers.ttf`）。
  **不要据此得出「AICoin 数字用 DIN」的结论。**
- 图表内部数值（蜡烛宽度/间距、一屏根数、缩放上下限、惯性滑动参数）全在 `Chart` 的代码里，资源里没有。
- 指标默认参数同上。
- `_blue` / `_blue_night` 色板的用途。
- 三档高度里哪一档是出厂默认。

---

# 补充（全量资源挖掘完成后追加）

> 完整版见同目录 `AICoin-安卓包-资源全量报告.md`（926 行 / 9 节）。以下只列对看盘实现最有冲击的部分，
> 并订正本文上半部分的两处推测。

## 16. 订正

1. **`_blue` 不是涨跌配色**（上面第 8 节已就地改正）——它是第二套中性灰皮肤，整套忽略。
2. **「竖屏高度」在 UI 上是一条 SeekBar，不是三个按钮**：`ui_kline_layout_style_side_menu.xml` 里
   `@id/kline_height` 是 SeekBar（轨道高 2dp，margin 10dp，thumb `ui_kline_ic_seekbar_thumb`），
   左右端点只有「低」「高」两个标签，`max` 在代码里设。三档 300/429/555dp 只存在于 dimens，
   由代码读取；中间档「适中」连文案绑定都没有。所以**这是一条连续（或多档）滑杆，不是三选一**。
3. **红涨绿跌 / 绿涨红跌不在 K 线设置里**，在 App 全局设置
   （`act_me_system_growth_color_settings.xml`，`settings_value_growth_color_mode_default`=绿涨红跌 /
   `_reverse`=红涨绿跌），而且 APK 里**没有 `rise`/`fall` 命名族**，只有 green/red，取反由代码做。
   K 线设置面板里对应的是「柱子颜色 上涨/下跌」自定义取色。

## 17. 图表内部自绘用色（layout 零引用，全部由 Canvas 按名取）—— 看盘最该抄的一组

| token | 日间 | 夜间 | 用途 |
|---|---|---|---|
| `line_grid` | `#c5c5c5` | `#303030` | **图表网格线** |
| `line_axis_pointer` | `#eeeeee` | `#ffffff` | **十字光标线** |
| `line_divider` | `#0d000000`（5%黑） | `#1affffff`（10%白） | 图表内分隔 |
| `line_indicate_normal_color` | `#e1e4ee` | `#4d545c` | 指示线常态 |
| `line_indicate_selected_color` | `#3b87eb` | `#2669bf` | 指示线选中 |
| `chart_large_trade_positive` / `_danger` | `#51a376` / `#db6876` | `#3c8060` / `#bc4865` | 大单买 / 卖 |
| `ui_kline_scale_auto_bg_color` | `#f3f5f7` | `#303442` | **A 徽章底（代码侧的另一套值）** |

注意 A 徽章有两套底色来源：布局里写的是 `sh_base_one_background_color`（`#f7f8fa` / 夜 `#06080d`），
另有专门的 `ui_kline_scale_auto_bg_color`（`#f3f5f7` / 夜 `#303442`）。哪套生效未确认。

涨跌色补充（比上面第 8 节更准）：
`sh_base_text_color_green` `#32a852` / 夜 `#2f9347`；`sh_base_text_color_red` `#eb4236` / 夜 `#cc3333`；
另有 `sh_base_text_color_red_raise` `#eb4236` 夜间**不变暗**（红涨模式专用）。

两处**硬编码不换肤**的颜色：预警线气泡底 `#1478fa`、大额成交浮窗买单徽标 `#ff32a853`。

## 18. 「K线设置」面板全部 28 项（`ui_kline_layout_style_side_menu.xml`）

齿轮按钮打开的就是这个面板。按布局顺序：

| # | 中文 | 形态 |
|---|---|---|
| 1 | 画线显示 | 开关 |
| 2 | **竖屏高度**（端点「低」/「高」） | **SeekBar** |
| 3 | 类型：K线图 / 平均K线（Heikin Ashi） | 二选一 |
| 4 | 下单模式：单账户 / 多账户 | 二选一 |
| 5 | 账户下单管理 | 跳转 |
| 6 | 信号展示（+ 只展示当前周期 / 只展示最新） | 开关 + 两个勾选 |
| 7 | K线数据显示：K线内 / 顶部 / 跟随K线 | 三选一图片卡（卡高 75dp） |
| 8 | 色调：亮调 / 暗调 / 默认 | 三选一 |
| 9 | 缩放：线状 / 条状 / 柱状 | 三选一 |
| 10 | 开盘时间：0点 / 8点 / 24H制 | 三选一 |
| 11 | 拖动位置：偏左 / 中间 / 靠右 | 三选一 |
| 12 | 坐标：对数 / 线性 / % | 三选一 |
| 13 | 十字线：收盘价 / 选中价 | 二选一 |
| 14 | K线阳线：空心 / 实心 | 二选一 |
| 15 | 柱子颜色：上涨 / 下跌 | 取色（行高 40dp，色块 22dp） |
| 16 | 主力/大额/筹码（右侧面板总开关） | 开关（行高 40dp） |
| 17 | 翻转主图Y轴 | 开关 |
| 18 | 翻转副图指标 | 开关 |
| 19 | 实时价格线 | 开关 |
| 20 | K线结束倒计时 | 开关 |
| 21 | 显示价格预警线 | 开关 |
| 22 | 至今涨幅 | 开关 |
| 23 | 十字线添加距实时价标签 | 开关 |
| 24 | 网格 | 开关 |
| 25 | 十字线添加预警按钮 | 开关 |
| 26 | 主图指标收起和设置按钮 | 开关 |
| 27 | 副图指标移动和设置按钮 | 开关 |
| 28 | 指标参数值简化显示 | 开关 |

**第 7 项「K线数据显示：K线内 / 顶部 / 跟随K线」**很关键——说明上面第 5 节讲的「34dp 顶部信息条」
只是三种模式之一（「顶部」），AICoin 同时也支持「K线内」和「跟随K线」（即跟手气泡）。三种都要能切。

面板样式：标题 15sp / paddingLeft 20dp；开关行左右 padding 20dp；分组分割线 1px + 左右 margin 20dp；
开关控件 minWidth 45dp；侧栏宽 255（资源写成 sp）。

**不在这个面板里**（容易找错地方）：涨跌颜色→App 全局设置；成交量→属指标体系；
持仓成本线 / 买卖记录 / 预估强平线→「高级 → 下单显示」；画线工具→「高级」菜单。
**买一/卖一价线、均价线在整个 K 线模块不存在**；加密行情没有「复权」。

## 19. 画线工具（只在横屏）

竖屏 K 线页**没有**画线工具条，只有一个 18dp 的 `iv_drawing_hide`（右边距 64dp）。
画线的三条工具栏（左侧竖条 / 选中后的浮动属性条 / 放大镜条）只 include 在横屏布局里。

**20 种线型**：价格线、直线、线段、射线、垂直线、水平直线、水平线段、水平射线、箭头、平行线段、
价格通道线、矩形、时空尺、斐波那契回调 / 扩展 / 线段 / 直线 / 扇形 / 螺旋线、放大镜。

**13 色固定调色盘**（`arrays.xml:826`，画线颜色与「柱子颜色」共用）：
`#cf1423` `#d4380d` `#d46b08` `#d4b107` `#379e0f` `#0a979b` `#076dd9` `#1c39c3` `#531dab` `#c41d7f` `#000000` `#989898` `#f2f2f2`
取色弹窗是 `GridLayout rowCount=2 columnCount=10`，带「恢复默认」（13sp）。画线默认色 `#1990ff`。

线型 3 档（实线 / 长虚线 / 短虚线），线宽 4 档（thin/normal/thick/very_thick）——**具体数值在代码里，未确认**。
浮动属性条按钮：取色、填充、锁定、删除、线型、线宽。

左侧竖条内容区宽 **56dp**，一级项 padding 9dp，二级项左右 18dp / 上下 9dp，通用项高 40dp / padding 10dp，
底部三按钮（隐藏 / 清空 / 分享）各上下 padding 8dp，收起箭头宽 14dp。
放大镜条三个按钮 14sp，padding 8/12dp，文案「确定」/「恢复」/「退出」。

## 20. 全 App 统一的字号与间距阶梯（直接照抄）

字号：9 / 10 / 11 / 12 / 14 / 16 / 18 / 20 / 22 sp
（`font_size_tiny_low` … `font_size_xlarge`）。**K 线区实际只用到 9 / 10 / 11 / 12 / 13 / 14 / 18 / 21**。

间距 `offset_*dp`：0.5, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24, 28, 30, 32, 40, 42。
**K 线区高频只用 4 / 5 / 6 / 8 / 10 / 12 / 18dp**。

分隔线厚度全局只有三种：0.5dp、1dp、1px。

## 21. 三个浮层的排版约定

主力大单浮窗（高 210dp）、大额成交浮窗（宽 140dp）、AI 撑压浮窗，
三者 **`marginRight` 统一 60dp** —— 给右侧价格轴留位。这条约定可以直接照搬。
另：详情页里行情区与 K 线区之间有一条 **8dp** 的粗灰分隔条（`#detail_divider`），别漏。

## 22. 其它已确认 / 已排除

- `res/layout/frg_land_kline.xml` 是**废弃占位桩**（只有一个写着「我是K线」的 TextView），
  真正的横屏页是 `res/layout-land/ui_kline_frg_ticker_kline.xml`。照前者复刻会完全走偏。
- 横屏主布局里**没有** A 徽章、全屏按钮、右侧面板开关、底部指标栏；
  横屏的 A 徽章（`tv_land_scale_auto`，**14sp**）与右侧面板（150dp）只出现在**详情页横屏**布局里。
- A 徽章有 10 个分场景 dimen（间距 44/18/12/12/6dp，上抬 8/0/0/0/0dp），全树零引用、dex 也搜不到符号名，
  场景映射（主图/副图 × 竖屏/横屏）是**按命名推断，未确认**。
- 换肤机制是 `com.ijoic.skinchange.lite.SkinManager`，靠「资源名 + `_night` 后缀」在运行时替换，
  `res/` 下只有 `drawable-night` / `color-night`，**没有 `values-night`**。
  iOS 侧等价物就是颜色 token 化后按主题查表，不要做两套布局。

---

## 23. 反编译代码级发现：高度分配与 A 徽章（本节全部来自 dex 反编译，非布局推测）

前面 §2/§3 只能从布局 XML 读到「有哪些高度常量」，读不到「怎么分」。把 jadx 输出挖完之后，
下面这些是**算法本身**，可以直接照着实现。

### 23.1 主图 / 副图的高度分配：3 : 1 的整数份额

`sp.aicoin_kline.chart.Chart` 的 `s()` / `t()` 转发给 `Rj.L0`：

```java
// Rj/L0.java:226-232
public final int M(int totalHeight, int subCount) {
    return ((totalHeight / (subCount + 3)) * 3) - 40;
}

public final int N(int baseHeight, int subCount, boolean lowerThanBaseAllowed) {
    return (subCount >= 0 && (subCount >= 2 || lowerThanBaseAllowed))
        ? (subCount + 3) * (baseHeight / 4)
        : baseHeight;
}
```

含义：

- 整个图形区被切成 `副图个数 + 3` 份；**主图恒占 3 份，每个副图各占 1 份**。
- `M(h, n)` 返回主图区的**底边 y**（即主图高度）：`h/(n+3)*3 - 40`。末尾的 `-40`（px）
  是给主图底部的**日期/时间轴**留的固定余量，不随副图数变化。
- `N(base, n, allowLower)` 是反向换算：`base` 是「恰好挂 1 个副图」时的总高
  （代入 n=1 得 `4 * (base/4) = base`，自洽）。副图数 ≥2 时按 `(n+3)/4` 比例放大总高；
  只有 1 个或 0 个副图时，除非显式允许压缩（`allowLower`），否则总高保持 `base` 不变。

**对看盘的意义**：由 `N()` 可知，挂 0 个和挂 1 个副图时外框总高**完全相同**（都等于 base）；
变化只发生在框内 —— n=0 时 `M = h/3*3 - 40 = h - 40`，主图吃满；n=1 时 `M = h/4*3 - 40`，
主图退到 3/4，腾出的 1/4 给副图。从 2 个副图起，外框才按 `(n+3)/4` 整体变高。
这正是「固定框」行为在副图维度上的具体表现。

### 23.2 竖屏 K 线高度是一个 SeekBar，不是档位（对 §2 的再次订正）

```java
// p254m/aicoin/kline/common/tools/D.java:~409
public final int u(int percent) {
    double std = ...getDimensionPixelSize(R.dimen.ui_kline_standard_vertical_height); // 429dp
    return (int) (std + (((percent / 100.0d) - 0.5d) * std));
}
```

即 **`高度 = 429dp × (0.5 + percent/100)`**。

- 偏好键：`kline_height_progress`，**默认值 50**（`p398sh/aicoin/ticker/preference/f.java:129`）
  → 恰好 429dp，与 `ui_kline_standard_vertical_height` 一致。
- SeekBar 布局里没有 `android:max`，取 Android 默认 **100**，所以区间是
  **214.5dp … 643.5dp**，默认落在正中。
- 控件：`ui_kline_layout_style_side_menu.xml:18`，轨道 2dp（`minHeight`=`maxHeight`=2dp），
  四边 margin 10dp，`splitTrack=false`，thumb `ui_kline_ic_seekbar_thumb`，左右两端是
  「低 / 高」两个 `font_size_small` + `sh_base_text_tertiary` 的文字标签。
- 拖动过程中就生效：监听器只实现了 `onProgressChanged`，
  `onStartTrackingTouch` / `onStopTrackingTouch` 都是空实现，每一帧都
  `preference.O(progress)` + EventBus `post(m.aicoin.kline.common.f(progress))`
  （`kline_side_menu/Y.java:161`）。**所以是实时跟手改高，不是松手才跳。**
- 订阅侧 `TickerDetailPriceFragment.onKlineHeightChanged(...)` 把整块行情区重算：
  `n3(klineHeight) = 顶部块高 + klineHeight + ui_kline_indicator_bar_height + 分隔线高`。

**因此 §2 里列的 300dp / 555dp 档位并不存在**：`ui_kline_short_vertical_height`（300dp）
和 `ui_kline_tall_vertical_height`（555dp）在整个 dex 里**零引用**，是死常量。
真正被读的只有 `standard`（429dp），而且只作为公式的基数。

### 23.3 A 徽章（自动缩放）的运行时样式覆盖

布局里写的颜色**不是最终生效的**。`D.t(View)` 在挂载时重刷一遍：

```java
// D.java:~398
textView.setTypeface(Typeface.DEFAULT, 0);      // 强制非粗体
textView.getPaint().setFakeBoldText(false);
j0.f(textView, "kline_skin_tag", R.color.sh_base_one_text_color);   // 文字色
l0.a(textView, R.color.ui_kline_scale_auto_bg_color);               // 背景色
```

最终样式：**12sp、常规字重、文字 `sh_base_one_text_color`、底色
`ui_kline_scale_auto_bg_color`（日 `#f3f5f7` / 夜 `#303442`）、圆角 2dp、
padding 上下 2dp 左右 6dp**。这解决了 §5 里标注的「布局色 vs 代码色哪套生效未确认」。

### 23.4 A 徽章的显隐、点击与定位

```java
chart.setOnMainYAxisScaleStateChanged(cb);              // 缩放状态回调
l0.j(badge, chart.getIsMainYAxisScaled());              // 初始显隐
// 回调体：z10 ? VISIBLE : GONE
badge.setOnClickListener(v -> chart.z());               // 点击 = 恢复自动缩放
```

- **只在「主图 Y 轴被手动缩放过」时出现**，一旦点击 `chart.z()`（等价 `d(true,true)`）
  恢复自动，徽章立刻消失。它不是常驻按钮。
- 定位（`D.S(...)`，注册在 `decorView` 的 `OnLayoutChangeListener` 上，每次布局都重算）：

```java
int mainBottom = chart.s(chart.getHeight(), KLineManager.获取的副图列表.size());  // §23.1 的 M()
int anchorY    = D.Y(activity, iv_show_right, mainBottom);
lp.topMargin   = anchorY - D.X(badge) - res.getDimensionPixelSize(extraLift)
                         - res.getDimensionPixelSize(spacingToShowRight);
```

`Y()` 优先用 `iv_show_right` 已有的 `topMargin`；没有则
`mainBottom - iv_show_right高 + 18dp(ui_kline_overlay_show_right_icon_left_margin)`。
**即：A 徽章贴在主图区底边，叠在「展开右侧面板」图标的正上方**，两者共用同一条基线。

### 23.5 A 徽章的场景映射（订正 §16 里 subagent 的「主图/副图」猜测）

那 10 个 `ui_kline_overlay_scale_auto_*` dimen 其实是**三个页面 × 横竖屏**的偏移对，
`index` 指的是**指数详情页**，不是「副图 index」：

| 调用点 | 场景 | spacing_to_show_right | extra_lift |
|---|---|---|---|
| `MainKlineFragment.java:4723` | 主 K 线页 · 横屏 | `..._to_show_right` 44dp | `..._extra_lift` 8dp |
| 同上 | 主 K 线页 · 竖屏 | `..._main_portrait` 6dp | `..._extra_lift_main_portrait` 0dp |
| `IndexKlineFragment.java:1375` | 指数详情页 · 横屏 | `..._index_land` 18dp | 0dp |
| 同上 | 指数详情页 · 竖屏 | `..._index_portrait` 12dp | 0dp |
| `TickerDetailLandKlineFragment.java:796` | 行情详情 · 横屏 | `..._land` 12dp | `..._extra_lift_land` 0dp |

横屏走 `D.I()`（操作 `tv_land_scale_auto` / `iv_land_show_right`），
竖屏走 `D.P()`（操作 `tv_scale_auto` / `iv_show_right`），两者算法完全一致。

---

## 24. 蜡烛几何、缩放与惯性（全部来自 `Rj.y1` / `Wj.a` / `Wj.b` / `Rj.C2746s` 反编译）

这一节回答的是「手感」问题：一根 K 线多宽、一屏几根、双指能缩到什么程度、甩动怎么减速。

### 24.1 一根 K 线的宽度 = `scale × 12` 像素（原始 px，未做 dp 换算）

```java
// Rj/y1.java:287-305  Q(scale, focusX)
this.f19622h = scale;
this.f19631q = scale * 12.0f;              // itemWidth：每根 K 线占的横向节距（px）
this.f19625k = this.f19631q * this.f19634t; // contentWidth = 节距 × 总根数
this.f19624j = Math.max(0f, this.f19625k - this.f19635u);  // maxScrollX
this.f19636v = (int) (this.f19635u / this.f19631q);        // 一屏可见根数
this.f19629o = (-scrollX) % this.f19631q;                  // 网格的亚像素相位
```

- `f19635u` = 主图区宽度（px），`f19634t` = 数据总根数，`f19623i` = 当前横向滚动量。
- **`12.0f` 是裸像素常量，全工程只此一处，没有任何 density 换算**。也就是说 AICoin 的
  K 线节距是按**设备物理像素**定的，不是按 dp —— 同样的缩放级别，3x 屏比 2x 屏一屏能塞
  更多根。这一点和「按 dp 定宽」的常规做法相反，是有意还是历史遗留不确定，但代码事实如此。
- 默认 `scale = 1.0` ⇒ **节距 12px**。1080px 宽的主图 ⇒ **一屏约 90 根**。

### 24.2 缩放范围硬夹在 `[0.4, 10.0]`

```java
// Wj/a.java:229-236  双指缩放回调
this.f24760a = Math.max(0.4f, Math.min(this.f24760a * detector.getScaleFactor(), 10.0f));
viewport.Q(this.f24760a, detector.getFocusX());
view.invalidate();
```

换算成节距：**4.8px（最疏）… 120px（最密）**。以 1080px 宽算，
**一屏根数区间约 9 根 … 225 根**。

- 缩放**以双指中点 `getFocusX()` 为锚点**，`Q()` 里用
  `min((oldScrollRatio·newContentWidth) - focusX, maxScroll)` 把锚点下的那根 K 线钉住。
- 缩放**每帧增量累乘**（`scale *= currentSpan/previousSpan`），不是从手势起点算总比例。
- 当手势状态 `state == 2` 时直接 `return true` 忽略缩放（该状态是十字光标/画线态）。

### 24.3 缩放级别是**进程级全局**的，跨品种、跨周期共用

```java
// Rj/C2760w1.java
public static float f19600g = 1.0f;   // 全局 scale
public final float i() { return f19600g; }   // 手势开始时读
public final void l(float f) { f19600g = f; } // 手势结束时写
```

- `onScaleBegin` 读全局值作为本次手势的起点，`onScaleEnd` 把结果写回全局。
- 新建图表时 `C2757v1:1577/1631/2074` 也是从这个全局值取初值。
- 它是**静态字段，不落盘**：切品种、切周期、退出再进 K 线页都保持当前缩放；
  **杀进程后回到 1.0**。

### 24.4 双指手势用的是 AOSP `ScaleGestureDetector` 的整份拷贝（`Wj.b`），只改了两个常量

- `mMinSpan = 50`（**硬编码 50px**，AOSP 原版是 `config_minScalingSpan` ≈ 27dp）——
  双指间距小于 50px 时不触发缩放。
- `mSpanSlop = ViewConfiguration.getScaledTouchSlop() * 2` —— 与 AOSP 一致。
- 正常双指路径的 `getScaleFactor()` **就是 `currentSpan / previousSpan`**，无阻尼。
  文件里那段 `×0.5` 的衰减公式只走 `mStylusScaleEnabled` 分支（触控笔侧键单指缩放），
  手机上不会走到，**不要照抄成双指阻尼**。

### 24.5 横向甩动：系统 `OverScroller` 默认参数，零回弹

```java
// Rj/C2746s.java
this.f19535g = new OverScroller(context);                       // 默认插值器、默认摩擦
this.f19536h = ViewConfiguration.getScaledMinimumFlingVelocity(); // 50dp/s
this.f19537i = ViewConfiguration.getScaledMaximumFlingVelocity(); // 8000dp/s
...
velocityTracker.computeCurrentVelocity(1000, maxFlingVelocity);
if (Math.abs(xVelocity) > minFlingVelocity && state ∉ {2,6,8,9}) {
    scroller.fling(startX, 0, xVelocity, 0,
                   Integer.MIN_VALUE, Integer.MAX_VALUE,  // X 范围不设限
                   0, 0);                                  // overX = overY = 0
}
```

- **没有自定义摩擦系数**，就是 Android 默认的 `ViewConfiguration.getScrollFriction()`。
- `fling` 的 X 边界给到 `MIN_VALUE..MAX_VALUE`、`overX = 0`：
  **AICoin 的 K 线横向没有橡皮筋回弹**，真正的边界夹取发生在数据层
  `y1.O(dx)`（越界时把 `scrollX` 夹到 `0` 或 `maxScroll` 并返回方向标记）。
- 每帧把 `scroller.getCurrX()` 的增量喂给 `y1.O(delta)`；到左右边界时 `O()` 返回
  `LEFT`/`RIGHT` 并触发 `C2738p.m()` / `C2738p.p()`（加载更早数据 / 到达最新）。
- 手势状态 ∈ {2,6,8,9} 时**禁止甩动** —— 即十字光标、画线、放大镜等模式下只跟手不惯性。
- `ACTION_DOWN` 立即 `forceFinished(true)` 打断上一次惯性（按下即停）。

### 24.6 「还剩 400 根」是加载更多的阈值

`y1.L()` 和 `y1.M()` 里反复出现 `400 * this.f19631q`（400 根 × 节距）：

```java
public final boolean M() {   // 是否正好停在「距离最右端 400 根」的位置
    float d = (this.f19624j - this.f19623i) - (400 * this.f19631q);
    return d < this.f19631q && d > -this.f19631q;   // 容差 ±1 根
}
```

即**滚动到距最新一根还剩 400 根时**触发一次翻页/对齐逻辑。这是个固定根数，不随缩放变。

### 24.7 新 K 线产生时的自动滚动位置：三选一

`y1.L()` 末尾按设置项 `settings.q(18)` 决定新 bar 出现后视口停在哪：

| `q(18)` | 落点 |
|---|---|
| 0 | 保持原位（`f19627m`） |
| 1 | 视口宽度的 **2/3** 处 |
| 2 | 视口宽度的 **1/2** 处 |

### 24.8 指标默认参数：**APK 里没有，是服务端下发的**

`sp/aicoin_kline/core/indicator/config/` 下的 `MARemote` / `MACDRemote` / `KDJRemote` /
`BollRemote` / `RsiRemote` / `EMARemote` … 全部是 **DTO**：字段清一色
`Integer?` / `String?` / `Boolean?`，**没有任何默认值**，连线宽和线色都是 nullable。
`arrays.xml` / `strings.xml` 里也只有 `MA(5)`、`MA(10)` 这类**展示用文案**，没有参数表。

结论：**「MA 5/10/20、MACD 12/26/9、KDJ 9/3/3」这些默认值在安卓包里查不到**，
AICoin 是从服务端拉 `ChartIndicatorSetting` 下来的。看盘要自己定默认值，
照通用惯例即可，不要声称「和 AICoin 对齐」——这一项无从对齐。

---

## 25. 蜡烛实体/影线几何与落笔对齐（`Rj/C2723k.java`、`Rj/F0.java`、`Rj/J.java`）

这一节回答两个具体问题：**实体宽/影线宽和节距（12px）是什么关系**，
以及**网格线、十字线落笔有没有 +0.5 半像素、有没有按 density 取整**。

### 25.1 蜡烛：实体占节距的 2/3，影线是固定 2px

画蜡烛的是 `Rj/C2723k.java`。几何量在一次 `g(Canvas)` 里算好，之后每根 `+= 节距` 推进：

```java
float fU = y1VarM.u();              // itemWidth＝节距（= scale × 12，见 §24）
float fJ = y1VarM.J();              // = scrollX mod 节距，亚像素相位
float f20 = (fU / 6) - fJ;          // 实体左边 = w/6
float f21 = (fU / 2) - fJ;          // 影线   x = w/2（正中）
float f22 = ((fU * 2) / 3) + f20;   // 实体右边 = 2w/3 + w/6 = 5w/6
float f23 = f20;
// 循环末尾：f23 += fU; f22 += fU; f21 += fU;
```

于是：

| 量 | 表达式 | 节距 12px 时 |
|---|---|---|
| 实体左边 | `w/6` | 2px |
| 实体右边 | `5w/6` | 10px |
| **实体宽** | **`2w/3`** | **8px** |
| 左右各留的缝 | `w/6` 各一侧 | 2px + 2px |
| 影线 x | `w/2`（bar 正中） | 6px |
| **影线宽** | **固定 `strokeWidth 2.0f`，与节距无关** | 2px |

注意**影线宽是写死的 2 裸像素**，不随缩放变。所以放到最大（scale 10 ⇒ 节距 120px）时
实体有 80px 宽，影线还是 2px 一条细线；缩到最小（scale 0.4 ⇒ 节距 4.8px）时
实体 3.2px，影线 2px，两者几乎一样粗。

### 25.2 涨的实体右边要 `-1`，跌的不减

```java
// 涨（bVar.a() > bVar.d()，a()=close d()=open）：
if (bottom - top >= 2.0f) canvas.drawRect(f23, top, f22 - 1, bottom, f19440m);  // ← -1
else                      canvas.drawLine(f23, y, f22, y, f19439l);
// 跌：
if (bottom - top >= 1.0f) canvas.drawRect(f23, top, f22, bottom, f19442o);      // ← 不减
else                      canvas.drawLine(f23, y, f22, y, f19441n);
// 十字星（a() == d()）：
f19443p.setStrokeWidth(2.0f);
canvas.drawLine(f23, fS, f22, fS, f19443p);
```

极性由配色函数坐实，不是猜的：

```java
public void u(mk.a aVar) {
    f19439l.setColor(aVar.q()); f19440m.setColor(aVar.q()); f19443p.setColor(aVar.q()); // 涨色
    f19441n.setColor(aVar.l()); f19442o.setColor(aVar.l());                              // 跌色
}
```

两点值得注意：

- **「一格留 1 像素缝」这个做法 AICoin 确实有，但只用在涨的实体上。** 跌的实体画满
  `[w/6, 5w/6]`。所以密集时跌的柱子看起来比涨的宽 1px——这是实现的不对称，
  不是视觉设计。要不要抄这条 1px 是可以自己定的，但别以为 AICoin 两边都做了。
- **实体高度不足就退化成一条线**，而且涨跌阈值不一样：涨 `>= 2.0f` 才画矩形，
  跌 `>= 1.0f` 就画。退化后用的是影线画笔（strokeWidth 2.0f）画一条横线。

### 25.3 空心/实心与描边宽度是设置项

构造函数里的画笔配置：

```java
paint  (f19439l) 涨/影线： strokeWidth 2.0f
paint4 (f19441n) 跌：      FILL_AND_STROKE，strokeWidth 2.0f
paint2 (f19440m) 涨实体：  if (KLineManager.f0() == 1) strokeWidth 1.0f;
                           q(9) == 0 → FILL_AND_STROKE ; q(9) == 1 → STROKE + strokeWidth 2.0f
paint5 (f19442o) 跌实体：  if (f0() == 1) strokeWidth 1.0f
paint3 (f19443p) 十字星：  q(9) == 0 → FILL_AND_STROKE ; q(9) == 1 → STROKE
```

`q(9)` 是「实心 / 空心蜡烛」的用户设置，空心时涨的实体改成 `STROKE` + 2px 描边。
`f0() == 1` 是另一个开关，会把实体描边收到 1px。默认（`q(9)==0`）是实心。

### 25.4 落笔对齐：**全链路没有 +0.5，没有按 density 取整，也没开抗锯齿**

这是和原型有分歧的那一处，结论很干脆：**AICoin 一个对齐动作都没做，全是裸 float。**

**K 线 x**：起点 `w/6 - (scrollX mod w)`，逐根 `+= w`。`scrollX mod w` 本身就是任意小数，
所以蜡烛左右边几乎永远落在非整数像素上。没有 `Math.round`，没有 `+0.5`。

**十字线竖线**（`Rj/F0.java`）：

```java
f19105l: Style.FILL，默认 strokeWidth 0  → 1px 发丝线
f19106m: Style.FILL，strokeWidth 2.0f
float fC = y1.C(y1VarM, 0, 1, null);   // = l(selectedIndex) = (i + 0.5) × 节距 − scrollX
if (y1VarM.o() > 0.0f)  canvas.drawLine(fC, iZ, fC, c2702dE.p(), this.f19106m);
else if (y1VarM.E())    canvas.drawLine(fC, iZ, fC, c2702dE.p(), this.f19105l);
```

关键是 `fC` 来自 `y1.l(i) = (i + 0.5) × 节距 − scrollX`：**竖线钉在 bar 的中心，
不跟手指的像素走**。手指落在哪根上就吸到那根的中心，中间不做插值也不做像素对齐。
这里的 `+0.5` 是「第 i 根的中心」这个语义，**不是半像素对齐**，别混为一谈。

**网格**（`Rj/J.java`，注册为 `.g` 图层，见 `C2757v1.java:563`）：

```java
public void g(Canvas canvas) {
    boolean z10 = abstractC2759w0L instanceof C2742q0;
    if (this.f19152n) {
        int iU = c2702dE.u();  int iY = c2702dE.y();      // 左右边界
        Iterator it = abstractC2759w0L.p().iterator();     // 遍历 Y 轴刻度值
        while (it.hasNext()) {
            float fS = abstractC2759w0L.S(((Number) it.next()).doubleValue());
            canvas.drawLine(iU, fS, iY, fS,
                (AbstractC7609s.f(nk.l.k(..., Math.abs(abstractC2759w0L.R(fS)), 2, ...), "0.00") && z10)
                    ? this.f19151m : this.f19150l);
        }
    }
}
public void u(mk.a aVar) {
    this.f19152n = nk.n.f(8);              // 网格开关（用户设置第 8 项）
    Paint paint = this.f19150l;
    paint.setStrokeWidth(1.0f);            // 1 裸像素
    paint.setStyle(Paint.Style.STROKE);
    paint.setColor(aVar.g(1));
    Paint paint2 = new Paint(this.f19150l);
    paint2.setColor(aVar.d("value_indicator_line_color_0"));
    this.f19151m = paint2;
}
```

三条事实：

1. **网格只有横线，没有竖线。** 它只遍历 Y 轴刻度 `p()`，从左边界画到右边界。
   竖向的分隔完全交给时间轴刻度文字和十字线，画布上没有竖网格。
2. **strokeWidth 1.0f 是裸像素**，不是 1dp。y 值直接是 `S(刻度值)` 的浮点结果，没有取整。
3. 某条横线的值格式化成两位小数后等于 `"0.00"` 且主图是 `C2742q0` 类型时，
   换成 `value_indicator_line_color_0` 另一个颜色——即「零轴」高亮。

**抗锯齿**：`C2723k`（蜡烛）、`J`（网格）、`F0`（十字线）三个文件里
**一次 `setAntiAlias` 都没有**，即默认 `false`；而同目录下几十个其他图层
（`C2727l0`、`K1`、`Z`、`B1` 等，多是文字/曲线/圆点）都显式开了 AA。

这三件事合起来就说通了：**AICoin 的做法不是「对齐到整数像素」，而是「关掉抗锯齿」。**
关了 AA 之后，float 坐标由光栅化器按覆盖度直接判进/判出，1px 线永远是硬边的 1px，
根本不会糊成两条半透明线，所以它压根不需要半像素补偿。

### 25.5 对看盘的结论

- 实体宽用 **节距 × 2/3**，左右各留 **节距 / 6**；影线用 **固定 2px**（不随缩放变）。
- 「留 1px 缝」AICoin 只对涨的做。我们要么两边都不做、要么两边都做，别复制这个不对称。
- **对齐策略上，我们「x/y 双向 snap」和原型「只 snap x」两个选项都不是 AICoin 的做法**——
  它两个方向都不 snap。它能这么做的前提是这三层关掉了抗锯齿。所以这里要么
  「关 AA + 不 snap」（跟 AICoin 走），要么「开 AA + snap」（跟原型走），
  **不能开着 AA 又不 snap**——那才是糊的来源。iOS 上 CoreGraphics 默认开 AA，
  `CGContextSetShouldAntialias(ctx, false)` 是对应的开关。
- 十字线竖线钉 bar 中心（`(i + 0.5) × 节距 − scrollX`），不跟手指像素，这一条可以直接抄。
