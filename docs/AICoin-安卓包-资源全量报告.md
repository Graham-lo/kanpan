# AICoin 安卓版 K 线（看盘）UI 规格提取报告

> 来源：apktool 反编译产物 `aic/dec`。所有数值均为资源文件里的**原始值**（dp / sp / px / hex），未做换算。
> 夜间模式不使用 `values-night`，而是同一份 `res/values/colors.xml` 里 `xxx_night` 后缀的条目；
> 控件上的 `android:tag="skin:<资源名>:<属性>"` 是它的运行时换肤机制（一个 tag 可以用 `|` 串多条）。
> iOS 复刻时，`skin:` tag 相当于「这个属性要跟随主题切换」的标记。

---

## 0. 文件地图（K 线相关）

| 角色 | 文件 |
|---|---|
| 竖屏 K 线主布局 | `res/layout/ui_kline_frg_ticker_kline.xml` |
| 竖屏可滚动变体 | `res/layout/ui_kline_frg_scrollable_kline.xml` |
| 横屏 K 线主布局 | `res/layout-land/ui_kline_frg_ticker_kline.xml` |
| 横屏可滚动变体 | `res/layout-land/ui_kline_frg_scrollable_kline.xml` |
| 行情详情页内嵌 K 线（竖/横） | `res/layout/ui_kline_frg_ticker_detail_kline.xml`、`res/layout-land/ui_kline_frg_ticker_detail_kline.xml` |
| 周期栏（竖屏） | `res/layout/ui_kline_part_period_portrait.xml` |
| 周期栏（横屏） | `res/layout/ui_kline_part_period_landscape.xml` |
| 工具条（两个方向共用） | `res/layout/ui_kline_part_setting_bar.xml` |
| 十字光标信息条（竖/横） | `res/layout/ui_kline_frg_kline_info.xml`、`ui_kline_frg_kline_info_land.xml` |
| 右侧 105dp 面板 | `res/layout/ui_kline_include_kline_right.xml` |
| 底部指标栏 | `res/layout/ui_kline_part_indicator_bar.xml`、item：`ui_kline_item_indicator_bar.xml` |
| 图表浮层 | `ui_kline_part_large_order_info.xml`、`ui_kline_part_large_trade_info.xml`、`ui_kline_part_aisrl_info.xml`、`ui_kline_part_empty_data.xml` |
| 图表 View 本体 | `sp.aicoin_kline.chart.Chart`（自绘，布局里只占位 `match_parent`） |

**注意**：`res/layout/frg_land_kline.xml` 是一个**残留占位文件**，内容只有一个写着「我是K线」的 TextView，
不是真正的横屏页面。真正的横屏页面是 `res/layout-land/ui_kline_frg_ticker_kline.xml`（同名文件的 land 限定版本）。

---

## 1. 竖屏 K 线页：完整结构与尺寸

`ui_kline_frg_ticker_kline.xml` 根节点是垂直 `LinearLayout`（`match_parent`×`match_parent`），
自上而下 4 段：

```
┌─ include ui_kline_part_period_portrait      高 34dp   周期/指标/高级/设置 工具条
├─ include ui_kline_frg_kline_info            高 34dp   十字光标 OHLC 信息条（默认 gone）
├─ ConstraintLayout (weight 撑满)
│   └─ LinearLayout #kline_right (vertical)
│        ├─ ConstraintLayout #container  (height=0dp, weight=1)
│        │    ├─ FrameLayout #container_kline  (width=0dp，右边贴 stub_kline_right)
│        │    │    ├─ Chart #chart_kline        match_parent
│        │    │    ├─ ViewStub #stub_empty_data
│        │    │    ├─ include #kline_loading_view (marginTop 168dp, gone)
│        │    │    ├─ ImageView #full_screen        24dp×24dp, marginStart 15dp, gravity=start
│        │    │    ├─ TextView  #tv_back_to_last    「回到最新」 11sp
│        │    │    ├─ TextView  #tv_scale_auto      「A」 12sp
│        │    │    ├─ ImageView #iv_drawing_hide    18dp×18dp
│        │    │    ├─ ImageView #iv_show_right      20dp×20dp, padding 3dp, marginEnd 18dp
│        │    │    └─ 三个信息浮层 include
│        │    └─ include #stub_kline_right   宽 105dp, 高 match_parent, 默认 gone
│        └─ include ui_kline_part_indicator_bar   高 25dp
├─ #ll_alert_line_tip_lable  预警线气泡（gone）
└─ include ui_kline_part_online_soon  (铺满)
```

宿主页面：`res/layout/ui_ticker_frg_detail_price_kline.xml` 用一个
`FrameLayout #kline_frame`（`match_parent`）装 K 线 Fragment，上方与价格区之间有一条
`View #detail_divider` 高 **8dp**。

### 1.1 周期栏 / 工具条 `ui_kline_part_period_portrait` → `ui_kline_part_setting_bar`

外层：`LinearLayout #layout_menu`，`layout_height=@dimen/ui_kline_menu_title_item_height` = **34dp**，
背景 `@color/ui_kline_menu_bg_color`（tag `skin:ui_kline_menu_bg_color:background`）。
内层 `ui_kline_part_setting_bar` 是一个横向 `LinearLayout`，`layout_weight=1` 占满，
子项按 **weight** 分配宽度：

| 顺序 | id | 内容 | weight | 说明 |
|---|---|---|---|---|
| 1 | `btn_period_first` / `tv_period_first` | `@string/kline_indicator_title_time` =「分时」 | 1.0 | 可被用户自定义替换 |
| 2 | `btn_period_second` / `tv_period_second` | `ui_kline_period_title_min_5` =「5分」 | 1.0 | |
| 3 | `btn_period_third` / `tv_period_third` | `ui_kline_period_title_min_10` =「10分」 | 1.0 | |
| 4 | `btn_period_fourth` / `tv_period_fourth` | `ui_kline_period_title_min_15` =「15分」 | 1.0 | |
| 5 | `btn_period_fifth` / `tv_period_fifth` | `ui_kline_period_title_min_15` =「15分」 | 1.0 | XML 里默认值与第 4 项重复，运行时由代码覆盖 |
| 6 | `btn_more` / `btn_more_text` | `ui_kline_menu_more` =「更多」+ 下拉箭头 | 1.0 | 箭头 `ui_kline_indicatorspinner_selector_bg`，`marginStart=@dimen/offset_1dp`=1dp |
| 7 | `btn_indicator` / `indicator_indicator` | `ui_kline_fragment_menu_indicator_setting` =「指标」+ 箭头 | 1.0 | |
| 8 | `btn_advanced` / `indicator_advanced` | `ui_kline_fragment_menu_advanced` =「高级」+ 箭头 | 1.0 | |
| 9 | `btn_hide` / `tv_hide` | `ui_kline_common_hide` =「隐藏」 | 1.0 | `visibility=gone` |
| 10 | `btn_setting` | 仅图标 `ui_kline_main_menu_setting_icon`，尺寸 `@dimen/ui_kline_menu_item_with_icon_size` = **18dp**，居中 | **0.8** | 打开 K 线设置侧栏 |
| 11 | `btn_hide_sub` | `iv_open_sub` 开关图 **48dp×16dp** + `tv_open_sub`「副图」(`ui_kline_trade_sub_title`) | **3.2** | 副图折叠开关 |

- 每个周期 tab 底部都有一条选中指示条：`ui_kline_menu_title_tab_indicator_icon_width` = **18dp** ×
  `ui_kline_menu_title_tab_indicator_icon_height` = **2dp**，图 `ui_base_selected_tag_bottom_bar_selector`，`gravity=center|bottom`。
- 文字样式 `@style/ui_kline_KLineStyle.NewIndicatorItem`（`res/values/styles.xml` L8772）：
  `textSize=@dimen/ui_kline_menu_item_text_size` = **12sp**，`textColor=@drawable/ui_base_title_text_tint_color_selector`（选中/未选中 selector）。
- 可点区域背景 `@style/ui_kline_KLineStyle.NewIndicatorItemBg`：`@drawable/ui_base_tab_transhighlight_bg_selector`。

「更多」下拉的周期面板：`res/layout/ui_kline_period_menu_layout.xml`
- RecyclerView `rv_period_list`：`paddingLeft/Right=10dp`，`paddingTop/Bottom=@dimen/offset_8dp`=8dp
- 新增周期行：高 **30dp**，`marginTop=14dp`，`marginBottom=24dp`
  - 「新增周期」`ui_kline_menu_add_period` 12sp `sh_base_text_secondary`，`marginStart=20dp`
  - 输入框 `et_period`：`inputType=number`，`paddingStart/End=16dp`，13sp
  - 单位下拉 `tv_switcher`：宽 **74dp**，`paddingStart=16dp`/`paddingEnd=9dp`，右侧箭头 `ui_kline_period_ic_arrow_down`
  - 「添加」按钮 `btn_add`：宽 **54dp**，12sp bold，背景 `sh_base_highlight_color`
- 分割线 1px（`@dimen/offset_1px`），左右 margin 20dp
- 底部「周期设置」`ui_kline_period_manager_setting`，高 `@dimen/ui_kline_menu_period_setting_button_height` = **48dp**
- 周期单位选择弹窗 `ui_kline_popup_period_selector.xml`：**74dp × 144dp**
- 面板整体高度常量：`ui_kline_menu_period_pop_window_height` = **170dp**，`ui_kline_menu_period_item_height` = **34dp**，`ui_kline_menu_period_pop_window_margin` = **10dp**

弹窗通用（`ui_kline_pop_menu_layout.xml`）：顶部箭头 `pop_arrow` **11dp × 6dp**；
常量 `ui_kline_menu_pop_window_arrow_width/height` = **8dp / 4dp**，`ui_kline_menu_pop_window_max_width` = **400dp**，`ui_kline_menu_pop_window_margin` = **10dp**。

「高级」下拉 `res/layout/ui_kline_advanced_menu_layout.xml`（`carbon_cornerRadius=4dp`，背景 `ui_kline_menu_background_color`），条目自上而下：

| id | string | 中文 | 备注 |
|---|---|---|---|
| `tv_large_order` | `ui_kline_menu_item_large_order` | 主力大单 | 高亮色文字（VIP） |
| `tv_large_deal` | `vip_kline_pro_big_deal` | 大额成交 | 高亮色 |
| `tv_vp_vr` | `ui_kline_indicator_name_ai_cyq` | 筹码分布 | 高亮色 |
| `layout_indicator_signal` | `ui_kline_indicator_name_indicator_signal` | 信号预警 | 高亮色 |
| `layout_win_rate` | `ui_kline_indicator_name_ai_win_rate` | 指标胜率 | 高亮色 |
| `tv_drawings_mode` | `ui_kline_menu_drawing_mode` | 画线工具 | 普通色 |
| `tv_compare_kline` | `ui_kline_fragment_menu_setting_compare` | 对比K线 | |
| `tv_spread_kline` | `ui_kline_fragment_menu_setting_spread_charts` | 组合K线 | |
| `tv_trade_show` | `ui_kline_fragment_menu_setting_trade_show` | 下单显示 | |
| `tv_positioning_kline` | `ui_kline_fragment_menu_setting_positioning_kline` | 定位到k线 | |

尺寸常量：`ui_kline_menu_more_main_menu_width` = **90dp**，`..._main_menu_height` = **190dp**，
`..._main_menu_with_no_advanced_height` = **130dp**，`..._advanced_menu_width` = **145dp**，
`..._advanced_menu_height` = **190dp**，`..._advanced_menu_icon_size` = **14dp**，
`..._main_menu_icon_size` = **16dp**，`..._advanced_menu_arrow_size` = **10dp**。

「指标」下拉 `res/layout/ui_kline_indicator_menu_layout.xml`：
顶部箭头 11dp×6dp；`MagicIndicator #magIndicator_level` 作为分类 tab（`paddingStart=8dp`、`paddingEnd=15dp`），
其下 1px 分割线 `sh_base_divider_fill_color`，`marginTop=63dp`（即 tab 区高 63dp）；
右上角提示 `tv_long_click_hint` 12sp `sh_base_text_tertiary` =「长按可设置指标」，`marginRight=20dp`；
下方 `NoScrollViewPager #root_page_container`。整体弹窗高 `ui_kline_menu_indicator_menu_pop_window_height` = **355dp**。
指标项 `ui_kline_item_indicator_menu.xml`：高 `ui_kline_side_indicator_menu_item_height` = **40dp**，
字号 `ui_kline_side_indicator_menu_item_title_text_size` = **12sp**。

### 1.2 十字光标信息条 `ui_kline_frg_kline_info.xml`

`ConstraintLayout #layout_kline_data_info`，默认 `visibility=gone`：
- 高度 `@dimen/ui_kline_menu_title_item_height` = **34dp**，`paddingTop=1dp`，`paddingStart/End=18dp`
- 背景 `@color/ui_kline_info_data_bg_color`（日 `#fff7f8fa` / 夜 `#0d111c`）
- 8 个 TextView，全部 **9sp**，颜色 `@color/ui_kline_info_data_text_title_color`（日 `#ff7a8899` / 夜 `#daeaff`）
- 两行四列网格，列间距 `marginStart=18dp`，行间距 `marginTop=4dp`：

| | 列1 | 列2 | 列3 | 列4 |
|---|---|---|---|---|
| 第一行 | `tv_date` 日期 | `tv_height` 最高 | `tv_open` 开 | `tv_raise` 涨跌 |
| 第二行 | `tv_time` 时间 | `tv_low` 最低 | `tv_close` 收 | `tv_ampl` 振幅 |

横屏版 `ui_kline_frg_kline_info_land.xml` 结构完全相同，只是高度改为 `wrap_content` + `paddingTop/Bottom=5dp`。

### 1.3 图表容器与浮层

- `FrameLayout #container_kline`：宽 `0dp`，右边约束到 `stub_kline_right`（右侧面板展开时图表自动收窄）。
- `Chart #chart_kline`：`sp.aicoin_kline.chart.Chart`，`match_parent`。所有坐标轴、K 线、指标均在这个自绘 View 内，**布局文件里没有任何图表内部尺寸**（未在资源中暴露）。
- 加载态 `kline_loading_view`（`sh_base_include_empty_loading.xml`，居中 ProgressBar），竖屏 `marginTop=168dp`。
- 空数据 `ui_kline_part_empty_data.xml`：`paddingTop=15dp`，`marginLeft/Top=8dp`，`marginRight=@dimen/ui_kline_compare_info_window_right_margin`=**60dp**，
  `minHeight=@dimen/ui_kline_index_empty_view_min_height`=**200dp**，文字 14sp `ui_kline_empty_data_text_color`。
- 主力大单浮层 `ui_kline_part_large_order_info.xml`：宽 `wrap_content`、**高 210dp**，
  `marginLeft=8dp`、`marginTop=12dp`、`marginRight=60dp`，`elevation=4dp`，背景 `ui_kline_bg_kline_large_popup`；
  标题徽章 9sp（`carbon_cornerRadius=7dp`），标题下 1px 分割线（`sh_base_divider_dim_fill_2_color`，左右 margin 10dp），
  各行 `marginTop=@dimen/offset_4dp`=4dp。
- 大额成交浮层 `ui_kline_part_large_trade_info.xml`：**宽 140dp**，高 `wrap_content`，
  `paddingTop=6dp`/`paddingBottom=10dp`/`paddingStart/End=10dp`，`marginLeft=8dp`、`marginTop=12dp`、`marginRight=60dp`，`elevation=4dp`；
  买单徽章文字色写死 `#ff32a853`，字号 9sp。
- 筹码/AI 支撑压力浮层 `ui_kline_part_aisrl_info.xml`：`padding 12/10/12/10dp`，`marginLeft/Top=8dp`，`marginRight=60dp`，`elevation=10dp`；
  标题 12sp bold，明细行 10sp，行距 `marginTop=6dp` / `4dp`。
- 预警线气泡 `ll_alert_line_tip_lable`：箭头 `marginTop=-5dp`，气泡 `marginTop=-12dp`、`padding 6/4dp`、
  12sp bold 白字、背景写死 **`#1478fa`**、`carbon_cornerRadius=4dp`，文案「预警线已显示，可在设置中关闭」。

### 1.4 右侧 105dp 面板 `ui_kline_include_kline_right.xml`

- 由竖屏主布局以 `layout_width="105.0dp"`、`layout_height=match_parent`、默认 `gone` 的 `include` 挂载（id `stub_kline_right`）。
- **横屏和详情页里同一个布局改用 150dp**（`layout-land/ui_kline_frg_scrollable_kline.xml`、`ui_kline_frg_ticker_detail_kline.xml`）。
- 背景 `@color/sh_base_view_bg`。
- 顶部 tab 行 `container_tabs`：高 **16dp**，`marginTop=5dp`，三个 tab 文字 **10sp**，
  `paddingStart/End=2dp`、`paddingTop/Bottom=1dp`、彼此 `margin 2dp`、`carbon_cornerRadius=2dp`；
  选中态 = `sh_base_highlight_color` 文字 + `sh_base_transparent_highlight_color` 底，未选中 = `sh_base_text_tertiary` 文字 + `sh_base_view_bg` 底。
  - `tv_tab1` =「主力」(`ui_kline_large_order_tab`)
  - `tv_tab2` =「大额」(`ui_kline_large_trade_tab`)
  - `tv_tab3` =「筹码」(`ui_kline_large_vpvr_tab`)
- 下方 `NoScrollViewPager #view_pager` 占满剩余高度。

### 1.5 底部指标栏 `ui_kline_part_indicator_bar.xml`

- `LinearLayout #ll_bottom_indic`，高 `@dimen/ui_kline_indicator_bar_height` = **25dp**，背景 `ui_kline_menu_bg_color`。
- 左右两个 `NestedBannedRecyclerView`（横向滑动、weight 各 1.0）：
  - `bar_list_main_indicator`（主图指标），`paddingRight=@dimen/offset_5dp`=5dp
  - `bar_list_secondary_indicator`（副图指标），`paddingLeft=5dp`
- 中间竖分割线：宽 `@dimen/offset_0.5dp`=**0.5dp**，`marginTop/Bottom=@dimen/offset_6dp`=6dp，颜色 `ui_kline_indicator_bar_divider_color`（日 `#eaeaea` / 夜 `#20232e`）。
- item `ui_kline_item_indicator_bar.xml`：文字 `@dimen/font_size_tiny_high` = **11sp**，`paddingLeft/Right=10dp`，高 `match_parent`，
  颜色 selector `ui_kline_indicator_bar_selector_textcolor`。

---

## 2. 横屏（全屏）K 线页

主布局 `res/layout-land/ui_kline_frg_ticker_kline.xml`，垂直 `LinearLayout`：

```
┌─ LinearLayout #layout_menu   高 @dimen/ui_kline_menu_item_height = 37dp
│    ├─ include ui_kline_part_ticker_block     币对名 + 左右切换箭头
│    ├─ include ui_kline_part_price_block      最新价
│    ├─ include ui_kline_part_period_landscape 周期/指标/高级/设置 + 返回
│    └─ include ui_kline_frg_kline_info_land   十字光标信息条
├─ FrameLayout (match_parent)
│    ├─ Chart #chart_kline
│    ├─ ViewStub #stub_empty_data
│    ├─ #kline_loading_view (gone)
│    ├─ TextView #tv_back_to_last 「回到最新」
│    └─ 三个信息浮层 include
├─ include ui_kline_part_drawing_menu_bar               (gone)
├─ include ui_kline_part_drawing_floating_menu_bar      (gone)
└─ include ui_kline_part_drawing_magnifier_floating_menu_bar (gone)
```

横屏**没有** `full_screen`、`iv_show_right`、`tv_scale_auto`、底部指标栏——工具条合并进顶栏，
画线工具条（右侧竖条 + 底部浮动条）只在横屏挂载。

### 2.1 币对块 `ui_kline_part_period_landscape` 相关三段

`ui_kline_part_ticker_block.xml`（`marginLeft=10dp`）
- 左右翻页箭头 `image_page_left/right`：宽 `@dimen/ui_kline_menu_land_ticker_switcher_size` = **22dp**，高 `match_parent`，`padding=@dimen/offset_4dp`=4dp
- 中间两行：`text_title` 字号 `ui_kline_menu_land_ticker_name_main_title_text_size` = **13dp**（注意资源里写的是 dp 不是 sp），
  `text_sub_title` = `ui_kline_menu_land_ticker_name_sub_title_text_size` = **10dp**；
  容器 `minWidth=@dimen/ui_kline_menu_land_ticker_name_title_min_width` = **100dp**
- 文字色 `ui_kline_menuitem_landscape_ticker_title_text_color`

`ui_kline_part_price_block.xml`（`marginLeft=10dp`）
- 货币符号 `text_main_price_symbol`：`@dimen/font_size_small` = 12sp（默认 gone）
- 主价格 `text_main_price`：`@dimen/ui_kline_menu_land_main_price_text_size` = **21dp**，色 `ui_kline_menuitem_landscape_ticker_price_text_color`
- 涨跌箭头 `image_main_price_status`：`marginLeft=@dimen/offset_4dp`=4dp，与价格 baseline 对齐

`ui_kline_part_period_landscape.xml`
- 横向 `LinearLayout`，高 `@dimen/ui_kline_menu_item_height` = **37dp**，`marginLeft=10dp`，
  背景 `ui_kline_menu_bg_color`，`divider=@drawable/ui_kline_land_indicator_divider`（tag `skin:ui_kline_land_indicator_divider:divider`）
- 内含**同一个** `ui_kline_part_setting_bar`（与竖屏共用，weight 分配一致）
- 末尾追加两项：
  - 返回按钮 `ui_kline_menu_bar_landscape_back_image`：`paddingLeft/Right=@dimen/offset_8dp`=8dp，高 `match_parent`，图 `ui_kline_land_ic_back`
  - 「退出画线」`ui_kline_menu_bar_landscape_quit_drawing`（默认 gone）：14sp、`sh_base_text_secondary`，
    `padding 5/3/5/3dp`，`marginRight=8dp`，描边 `carbon_strokeWidth=1px`，色 `ui_kline_drawing_menu_quit_stroke_color`，文案「退出画线」

### 2.2 横屏可滚动变体 `layout-land/ui_kline_frg_scrollable_kline.xml`

与上面同构，差异：
- 顶栏只有 ticker + price + period 三段；十字光标信息条单独成一行（`paddingTop/Bottom=5dp`、`paddingStart/End=18dp`）
- 图表放在 `NestedScrollView #scroll_view`（`weight=1`）里
- 右侧面板 `stub_kline_right` 宽 **150dp**
- 右侧竖直画线工具条 `ui_kline_part_drawing_menu_bar` 与图表并排
- 底部浮动画线菜单 / 放大镜菜单：`layout_margin=4dp`，`alignParentBottom`

### 2.3 横屏侧边样式菜单与侧边指标菜单

- 侧栏宽度常量 `ui_kline_side_menu_width` = **255sp**（⚠️ 资源里单位写成了 sp，应按 255dp 理解；照抄原值）
- 侧栏标题栏高 `ui_kline_side_menu_title_bar_height` = **26dp**，标题字号 `ui_kline_side_menu_title_text_size` = **16sp**
- 样式菜单块行高 `ui_kline_side_style_menu_block_row_height` = **82.5dp**，
  图标 `ui_kline_side_style_menu_item_image_size` = **24dp**，
  文字 `ui_kline_side_style_menu_item_text_size` = **13sp**，
  开关按钮宽 `ui_kline_side_style_menu_switch_button_width` = **45dp**
- 侧边指标菜单：item 高 `ui_kline_side_indicator_menu_item_height` = **40dp**，字号 **12sp**；
  底栏高 `ui_kline_side_indicator_menu_bottom_bar_height` = **40dp**，底栏图标 **18dp**，底栏文字 **13sp**
- 详见第 6 节（设置面板）

---

## 3. 图表高度档位（300 / 429 / 555dp）

`res/values/dimens.xml`：

| dimen | 值 | 行号 |
|---|---|---|
| `ui_kline_short_vertical_height` | **300.0dp** | 2227 |
| `ui_kline_standard_vertical_height` | **429.0dp** | 2242 |
| `ui_kline_tall_vertical_height` | **555.0dp** | 2245 |

**这三个 dimen 在整个 `res/layout*/` 里没有任何 XML 引用**（全仓 grep 只命中 `dimens.xml` 定义处和 `public.xml` 的 id 声明）。
也就是说它们只被代码按运行时设置读取 —— 这正是「用户可选的图表高度」的实现方式：
设置项选中后，代码把对应 dimen 设为 K 线容器的高度。

对应的设置文案在 `res/values-zh-rCN/strings.xml`（L6039-6043）：

| string name | 中文 |
|---|---|
| `ui_kline_side_menu_title_chart_ticker_detail_height` | **竖屏高度** |
| `ui_kline_side_menu_title_chart_ticker_detail_height_short` | 低 |
| `ui_kline_side_menu_title_chart_ticker_detail_height_middle` | 适中 |
| `ui_kline_side_menu_title_chart_ticker_detail_height_tall` | 高 |
| `ui_kline_side_menu_title_chart_ticker_detail_height_default` | (默认) |

**结论**：这是「K线设置」里名为**竖屏高度**的三档选项 —— 低 = 300dp、适中 = 429dp、高 = 555dp，
其中带「(默认)」后缀的一档为出厂默认。
「(默认)」具体拼在哪一档后面需要看代码，从命名（`_middle` 与 `_default` 相邻、429dp 居中）判断应是**适中 = 429dp**，
此点**未在资源中直接确认**。

**控件形态（已确认）**：在「K线设置」面板 `res/layout/ui_kline_layout_style_side_menu.xml` 里，该项是一个
**SeekBar `@id/kline_height`**（`minHeight`/`maxHeight` = 2dp，左右 margin 10dp，thumb `ui_kline_ic_seekbar_thumb`），
标题为「竖屏高度」，**左右两端标签只有「低」和「高」两个**，中间档「适中」在 XML 里没有文案绑定（`max` 也由代码设置）。
所以它在 UI 上表现为一条滑杆而非三个按钮；滑杆的档位数与 300/429/555 的对应关系在代码里。

iOS 复刻建议：这三个值是**整块 K 线容器（图表 + 副图）**的高度，不含 34dp 周期栏、34dp 信息条与 25dp 指标栏；
交互上用一条三档 Slider（低 / 适中 / 高）即可。

---

## 4. 色板（日间 / 夜间成对）

> 来源：`res/values/colors.xml`。夜间值 = 同一文件里 `<同名>_night` 条目。
> 换肤实现：`com.ijoic.skinchange.lite.SkinManager`（dex 中可见 `Lcom/ijoic/skinchange/lite/SkinManager;`、`Lcom/ijoic/skin/SkinPreference;`）。
> `res/` 下只有 `drawable-night` / `color-night`，**没有 `values-night`** —— 颜色日夜切换完全靠资源名后缀替换。
> 标「未确认」= 该 token 没有 `_night` 条目（夜间沿用日间值，或由代码另行处理）。

### 4.1 背景与分割线

| token | 日间 | 夜间 | 用途（K 线布局引用次数） |
|---|---|---|---|
| `sh_base_view_bg` | `#ffffff` | `#0d111c` | 通用页面底色（**23 次**） |
| `sh_base_theme_color` | `#ffffff` | `#0d111c` | 主题底色，被 `ui_kline_menu_bg_color_night` 等间接引用 |
| `sh_base_one_background_color` | `#f7f8fa` | `#06080d` | **A 徽标底色**；3 次 |
| `sh_base_page_bg` | `#f7f8fa` | `#090c14` | 5 次 |
| `sh_base_three_background_color` | `#f5f7fa` | `#1f2126` | 1 次 |
| `sh_base_list_item_bg` | `#ffffff` | `@sh_base_theme_color_night` | 列表项底 |
| `sh_base_list_item_bg_pressed` | `#f7f8fa` | `#2a2d36` | 2 次 |
| `ui_kline_menu_bg_color` | `#ffffff` | `@sh_base_theme_color_night` | **周期栏 / 指标条 / 画线条底色**（7 次） |
| `ui_kline_menu_background_color` | `#ffffff` | `@sh_base_theme_color_night` | 下拉菜单底（7 次） |
| `ui_kline_menu_bg_with_alpha_color` | `#ecffffff` | `#ec0d111c` | 浮层菜单（92% 不透明） |
| `ui_kline_menu_parent_bg` | `#37426b` | `#303442` | 二级菜单底 |
| `ui_kline_info_data_bg_color` | `#f7f8fa` | `#0d111c` | **十字线信息条底色**（4 次） |
| `ui_kline_side_menu_title_bar_background_color` | `#f8f8f8` | `#1d1f29` | 侧边设置面板标题栏 |
| `ui_kline_scale_auto_bg_color` | `#f3f5f7` | `#303442` | 自动缩放（A）按钮底 |
| `ui_kline_settings_dialog_bg` | `#ffffff` | `#31363b` | 设置弹窗 |
| `ui_kline_btn_bg` | `#f5f7fa` | `#25282b` | 按钮底 |
| `ui_kline_click_item_bg_color_pressed` | `#08000000` | `#11ffffff` | 点按态叠加 |
| `ui_kline_compare_info_window_bg` | `#e6ffffff` | `#e6090c14` | 对比浮窗（90%） |
| `ui_kline_vpvr_empty_bg` | `#f2ffffff` | `#e500000f` | 筹码分布空态 |

分割线 / 描边：

| token | 日间 | 夜间 | 用途 |
|---|---|---|---|
| `ui_kline_indicator_bar_divider_color` | `#eaeaea` | `#20232e` | **底部指标条中间竖分隔线**（1 次） |
| `ui_kline_divider_color` | `#f2f4f7` | `#191c21` | 1 次 |
| `ui_kline_common_divider_color` | `#dadada` | `#0d111c` | 3 次 |
| `ui_kline_common_border` | `#eaeaea` | `#2b2f3d` | 通用描边（5 次） |
| `sh_base_divider_fill_color` | `#f0f4ff` | `#010203` | **最常用分隔线**（8 次） |
| `sh_base_divider_dim_fill_color` | `#dee1e5` | `#25282e` | — |
| `sh_base_divider_dim_fill_2_color` | `#f0f4ff` | `#25282e` | 大单浮窗标题分隔（2 次） |
| `sh_base_divider_dim_fill_3_color` | `#33525a66` | `#337a8899` | 20% 透明分隔 |
| `sh_base_deep_dividing_line_background_color` | `#dee1e5` | `#25282e` | 加深分隔 |
| `sh_base_block_divider` | `#f7f8fa` | `#06080d` | 区块之间的粗条（详情页 8dp 灰条用色系） |
| **`sh_base_kline_divider`** | `#33ffffff` | `#0d111c` | 布局 0 引用 → **纯代码**，横屏全屏 K 线内部分隔 |
| `ui_kline_drawing_menu_quit_stroke_color` | `#b7bfc8` | `#4a5462` | 「退出画线」按钮 1px 描边 |

### 4.2 文字层级

主层级（iOS 侧直接照抄这 4+4 个 token 即可）：

| token | 日间 | 夜间 | 说明 |
|---|---|---|---|
| `sh_base_text_primary` | `#292d33` | `#c3c7d9` | 一级正文，**K 线布局 108 次，全场最高频** |
| `sh_base_text_secondary` | `#525a66` | `#7a8899` | 二级（33 次） |
| `sh_base_text_tertiary` | `#7a8899` | `#667180` | 三级（33 次） |
| `sh_base_text_quaternary` | `#b7bfc8` | `#b7bfc8`（同值） | 四级 |
| `sh_base_one_text_color` | `#292d33` | `#c3c7d9` | 旧命名，与 primary 同值（7 次） |
| `sh_base_two_text_color` | `#525a66` | `#7a8899` | 同 secondary（3 次） |
| `sh_base_three_text_color` | `#7a8899` | `#667180` | 同 tertiary；**A 徽标文字色**（9 次） |
| `sh_base_four_text_color` | `#b7bfc8` | `#515a66` | 同 quaternary（1 次） |
| `sh_base_text_info_hint_color` | `#b7bfc8` | `#515a66` | 提示（20 次） |
| `sh_base_text_hint` | `#c7c7c7` | `#6e737a` | 输入框 hint |

K 线专用文字色：

| token | 日间 | 夜间 | 用途 |
|---|---|---|---|
| **`ui_kline_info_data_text_title_color`** | `#7a8899` | `#daeaff` | **十字线信息条的全部标签与数值**（32 次，9 个文件）。注意夜间是偏蓝的 `#daeaff`，比通用三级文字亮很多 |
| `ui_kline_info_data_text_value_color` | `#525a66` | `#525a66`（同值） | 信息条数值（未在竖屏布局使用） |
| `ui_kline_text_tertiary` | `#757575` | `#999999` | 11 次 |
| `ui_kline_text_black` | `#000000` | `#ffffff` | 3 次（未上线占位页标题） |
| `ui_kline_empty_data_text_color` | `#a3b5cc` | `#667180` | 空数据文案 |
| `ui_kline_indicator_bar_item_not_selected_text_color` | `#555555` | `#828d99` | 底部指标条未选中 |
| `ui_kline_menu_normal_tint_color` | `#555555` | `#cbddf2` | 菜单图标 tint（9 次） |
| `ui_kline_menu_selected_tint_color` | `#3b87eb` | `#2669bf` | 菜单图标选中 tint |
| `ui_kline_menuitem_landscape_ticker_title_text_color` | `#333333` | `#c0c0cf` | 横屏品种名（3 次） |
| `ui_kline_menuitem_landscape_ticker_subtitle_text_color` | `#999999` | `#747984` | 横屏交易所名 |
| `ui_kline_menuitem_landscape_ticker_price_text_color` | `#37426b` | `#c0c0cf` | 横屏主价格 |
| `ui_kline_large_trade_title_color` | `#7a8899` | `#ffffff` | 大单浮窗标题（14 次） |
| `ui_kline_large_trade_value_color` | `#292d33` | `#c3c7d9` | 大单浮窗数值（6 次） |
| `ui_kline_base_disable_color` | `#666666` | `#4d545c` | 禁用态 |

### 4.3 涨跌色

**重要结论**：这个 APK **没有** `*_rise_*` / `*_fall_*` 命名族，涨跌一律用 **green / red** 或设计系统的 **positive / danger** 命名。
「红涨绿跌 / 绿涨红跌」是**由代码取反**，不是靠两套资源名 —— 设置项见 §6.4（`settings_value_growth_color_mode_default` = 绿涨红跌 / `_reverse` = 红涨绿跌）。

| token | 日间 | 夜间 | 用途 |
|---|---|---|---|
| `sh_base_text_color_green` | `#32a852` | `#2f9347` | 全局「涨」文字基色 |
| `sh_base_text_color_red` | `#eb4236` | `#cc3333` | 全局「跌」文字基色 |
| `sh_base_text_color_red_raise` | `#eb4236` | `#eb4236`（同值） | 「红涨」模式专用，夜间不变暗 |
| `sh_base_block_fill_green` | `#32a853` | `#2f9347` | 涨色块 |
| `sh_base_block_fill_green_transparent_10` / `_50` | `#1a32a853` / `#8032a853` | `#1a2f9347` / `#802f9347` | 涨色块 10% / 50% |
| `sh_base_block_fill_red` | `#eb4236` | `#992323` | 跌色块 |
| `sh_base_block_fill_red_transparent_10` / `_50` | `#1aeb4236` / `#80eb4236` | `#1a992323` / `#80992323` | 跌色块 10% / 50% |
| `element_positive_solid_pri` | `#00a47c` | `#008866` | 设计系统「正」 |
| `element_danger_solid_pri` | `#fa5957` | `#e32b3b` | 设计系统「负」 |
| `ui_kline_large_trade_type_green_color` | `#32a853` | `#2f9347` | 大单买（代码侧） |
| `ui_kline_large_trade_type_red_color` | `#eb4236` | `#cc3333` | 大单卖（代码侧） |
| `ui_kline_deep_price_color_green` | `#007f65` | `#007f65`（同值） | 深度图买 |
| `ui_kline_deep_price_color_red` | `#b7004b` | `#b7004b`（同值） | 深度图卖 |
| `ui_kline_order_point_msg_value_text_color_green` | `#32b473` | `#16b97a` | 订单点买 |
| `ui_kline_order_point_msg_value_text_color_red` | `#e5514a` | `#ff5757` | 订单点卖 |

### 4.4 关于 `_blue` 后缀 —— 不是第三套涨跌配色

`colors.xml` 里有 635 处 `_blue`（约 286 个 token 族）。**它不是涨跌配色、也不是色盲方案，而是设计系统的第二套「中性色相」皮肤：把整套纯灰阶换成蓝调冷灰。** 证据：

1. **量化对比**：286 个 `_blue` token 与对应无后缀 token 相比，日间 **246 个完全相同、仅 37 个不同**；夜间 **248 个相同、35 个不同**。若是涨跌配色，涨跌 token 必然全变。
2. **涨跌 / 语义色逐字节相同**：`element_positive_solid_pri` 与 `_blue` 都是 `#00a47c`（夜 `#008866`）；`element_danger_solid_pri` 与 `_blue` 都是 `#fa5957`（夜 `#e32b3b`）；`chart_large_trade_positive` 与 `_blue` 都是 `#51a376`；品牌橙 `background_accent_pri_solid_default` 与 `_blue` 都是 `#fd5836`。
3. **差异全部落在中性灰族，方向一致（灰 → 蓝灰）**：

   | 无后缀 | `_blue` |
   |---|---|
   | `line_grid` `#c5c5c5` | `#c1c5d2` |
   | `line_grid_night` `#303030` | `#2b3039` |
   | `line_axis_pointer` `#eeeeee` | `#ecedf4` |
   | `background_normal_sec_solid_default` `#f6f6f6` | `#f6f6fb` |
   | `background_normal_ter_solid_active` `#dddddd` | `#d8dce8` |
   | `border_normal_solid_pri` `#d4d4d4` | `#d0d4e0` |
   | `element_normal_solid_ter` `#c5c5c5` | `#c1c5d2` |
   | `background_normal_pri_solid_default_night` `#111111` | `#0e1117` |

4. **dex 侧**：`classes5/10/11.dex` 中有成对裸字符串 `blue`、`classic`、`light`、`dark`、`default`。结合 SkinManager 的「资源名 + 后缀」机制，`classic`（无后缀，纯灰）与 `blue`（`_blue` 后缀，蓝灰）是两个并列的中性皮肤，各自再叠加 `_night`。
5. **strings 侧反证**：K 线「色调」设置只有三项（默认 / 亮调 / 暗调，L6419-6423），**没有 blue 选项文案**；`strings.xml` 里仅有的两处 "blue"（L6443、L8379）是筹码分布图例「蓝色=买量 / 黄色=卖量」，与 token 族无关。
6. **布局侧几乎不用**：全 `res/layout` 只有 2 个无关文件引用 `@color/*_blue`，K 线布局 **0 次** —— 说明 `_blue` 族完全由代码经 SkinManager 按名解析。

> **未确认**：具体从哪个 UI 入口切到 `blue` 皮肤（strings 中无对应文案），以及 `classic`/`blue` 是否由服务端下发开关。
> **iOS 复刻建议**：直接用「无后缀（classic）」这一套即可，`_blue` 可以整套忽略。

### 4.5 图表自绘专用色（layout 0 引用，全部由 Canvas 代码按名取）

| token | 日间 | 夜间 | 用途 |
|---|---|---|---|
| `line_grid` | `#c5c5c5` | `#303030` | **图表网格线** |
| `line_axis_pointer` | `#eeeeee` | `#ffffff` | **十字光标线** |
| `line_divider` | `#0d000000` | `#1affffff` | 图表内分隔（5% / 10% 透明） |
| `line_indicate_normal_color` | `#e1e4ee` | `#4d545c` | 指示线常态 |
| `line_indicate_selected_color` | `#3b87eb` | `#2669bf` | 指示线选中 |
| `chart_large_trade_positive` | `#51a376` | `#3c8060` | 大单买 |
| `chart_large_trade_danger` | `#db6876` | `#bc4865` | 大单卖 |
| `chart_large_order_buy_filled` / `_unfilled` | `#51a376` / `#4d51a376` | `#2d6046` / `#4d2d6046` | 大单已成交 / 挂单（买） |
| `chart_large_order_sell_filled` / `_unfilled` | `#db6876` / `#4ddb6876` | `#962a4e` / `#4d962a4e` | 大单已成交 / 挂单（卖） |
| `chart_footprint_positive_primary/secondary/tertiary` | `#4d00a47c` / `#b300a47c` / `#00a47c` | `#4d008866` / `#b3008866` / `#008866` | 足迹图买三阶 |
| `chart_footprint_danger_primary/secondary/tertiary` | `#4dff5359` / `#b3ff5359` / `#ff5359` | `#4dd93c43` / `#b3d93c43` / `#d93c43` | 足迹图卖三阶 |

**流动性热力图 4 套配色 × 5 阶**（日夜是**首尾反转**关系：primary↔quinary、secondary↔quaternary 互换，tertiary 不变）：

| 配色 | primary | secondary | tertiary | quaternary | quinary |
|---|---|---|---|---|---|
| 1 日 | `#e0f6bb` | `#cab000` | `#a86900` | `#782800` | `#30000c` |
| 1 夜 | `#30000c` | `#782800` | `#a86900` | `#cab000` | `#e0f6bb` |
| 2 日 | `#c5f6ff` | `#3cbbff` | `#106dff` | `#4e1daa` | `#200b22` |
| 2 夜 | `#200b22` | `#4e1daa` | `#106dff` | `#3cbbff` | `#c5f6ff` |
| 3 日 | `#ffecc4` | `#ff9729` | `#e72600` | `#860046` | `#29002e` |
| 3 夜 | `#29002e` | `#860046` | `#e72600` | `#ff9729` | `#ffecc4` |
| 4 日 | `#f8efbc` | `#69c700` | `#00895e` | `#004b4a` | `#00161e` |
| 4 夜 | `#00161e` | `#004b4a` | `#00895e` | `#69c700` | `#f8efbc` |

### 4.6 高亮色

| token | 日间 | 夜间 | 用途 |
|---|---|---|---|
| **`sh_base_highlight_color`** | `#1478fa` | `#1060c8` | **主高亮蓝**；K 线布局 **52 次**（第二高频）。「回到最新」气泡底、右侧面板选中 tab 文字、周期选中、「添加」按钮底 |
| `sh_base_transparent_highlight_color` | `#1a1478fa` | `#1a1060c8` | 高亮 10% 底（右侧面板选中 tab 背景） |
| `sh_base_highlight_dim_color` | `#105fc7` | `#105fc7`（同值） | 加深高亮 |
| `ui_kline_indicator_tips_bg` | `#4c1478fa` | `#4c1478fa`（同值） | 指标提示底（30%） |
| `ui_kline_side_menu_tag_bg_selected_color` | `#211478fa` | `#211478fa`（同值） | 侧菜单标签选中底（13%） |
| `ui_kline_master_blue_button_color` | `#3b87eb` | `#2669bf` | 蓝色按钮（6 次） |
| `ui_kline_drawing_default_line_color` | `#1990ff` | 未确认（无 `_night`） | 画线默认色 |
| `ui_kline_win_rate_win_loss_color` | `#ffaa00` | `#b27600` | 指标胜率（3 次） |
| `ui_kline_win_rate_win_loss_transparent_color` | `#1effaa00` | `#1eb27600` | 指标胜率透明底 |
| `ui_kline_vip_golden_color` | `#dbb058` | `#dab363` | VIP 金 |
| `ui_kline_date_text` | `#2c91ff` | `#2c91ff`（同值） | 日期高亮 |

> 另有两处**硬编码**颜色（不走换肤，夜间也不变），复刻时需注意：
> 预警线提示气泡底 `#1478fa`（`ui_kline_frg_ticker_kline.xml`）、大额成交浮窗买单徽标 `#ff32a853`（`ui_kline_part_large_trade_info.xml`）。

---

## 5. 周期与指标清单

来源：`res/values-zh-rCN/strings.xml`（中文值）、`res/values/strings.xml`（英文短名/代号）、`res/values/arrays.xml`。

### 5.1 全量固定周期（`kline_menu_time_*`）

| string name | 中文 |
|---|---|
| `kline_indicator_title_time` | 分时 |
| `kline_menu_time_close` | （= `kline_indicator_title_time`）分时 |
| `kline_menu_time_1m` | 1分 |
| `kline_menu_time_3m` | 3分 |
| `kline_menu_time_5m` | 5分 |
| `kline_menu_time_10m` | 10分 |
| `kline_menu_time_15m` | 15分 |
| `kline_menu_time_30m` | 30分 |
| `kline_menu_time_1h` | 1时 |
| `kline_menu_time_2h` | 2时 |
| `kline_menu_time_3h` | 3时 |
| `kline_menu_time_4h` | 4时 |
| `kline_menu_time_6h` | 6时 |
| `kline_menu_time_12h` | 12时 |
| `kline_menu_time_1d` | 1日 |
| `kline_menu_time_2d` | 2日 |
| `kline_menu_time_3d` | 3日 |
| `kline_menu_time_5d` | 5日 |
| `kline_menu_time_1w` | 周K |
| `kline_menu_time_1mn` | 月K |
| `kline_menu_time_1q` | 季K |
| `kline_menu_time_year` | 年K |

### 5.2 周期栏标题 + PRO 专属周期（`ui_kline_period_*`）

标题类：`_title_min_5`=5分、`_title_min_10`=10分、`_title_min_15`=15分、`_title_hour_1`=1时、
`_title_hour_4`=4时、`_title_day`=1日、`_title_week`=周K、`_title_month`=月K、`_title_more`=更多。

PRO 专属：`_name_1s`=1秒、`_name_30s`=30秒、`_name_5m`=5分、`_name_45m`=45分、`_name_90m`=90分、
`_name_8h`=8时、`_name_16h`=16时、`_name_32h`=32时、`_name_10d`=10日、`_name_15d`=15日、
`_name_20d`=20日、`_name_45d`=45日。
提示文案：`ui_kline_only_pro_period_message_1` =「新增1秒、30秒、8时等专属周期，助力发现更多机会」，
`ui_kline_period_no_vip_message` =「自定义周期：支持秒级别，短线获利更加准确」。

### 5.3 自定义周期与周期管理

| string name | 中文 |
|---|---|
| `ui_kline_menu_add_period` | 新增周期 |
| `ui_kline_menu_custom` | 自定义 |
| `ui_kline_period_manager_setting` | 周期设置 |
| `ui_kline_period_manager_title_selected` | 已选周期 |
| `ui_kline_period_manager_title_unselected` | 未选周期 |
| `ui_kline_period_save_tips` | 至少选择五个周期 |
| `ui_kline_period_same_period` | 已存在相同周期 |
| `ui_kline_period_added` | 已添加 |
| `ui_kline_indicator_manager_tips`（周期管理页复用） | 长按可拖动排序 |
| `vip_kline_pro_custom_period` | 自定义周期 |

周期单位（`ui_kline_popup_period_selector` 的下拉项）：
`ui_kline_menu_period_unit_second`=秒、`_minute`=分钟、`_hour`=小时、`_day`=日。
格式化：`ui_kline_period_unit_s_format`=`%d秒`、`_minus_format`=`%d分`、`_hour_format`=`%d时`、`_day_format`=`%d日`。
（`ui_kline_item_period_unit.xml` 只有一个无默认文案的 `tv_name`，单位由代码填充。）

### 5.4 主图指标

短名来自 `ui_kline_indicator_name_*`，中文全称来自 `ui_kline_indicator_setting_home_item_name_*`。

| 代号 | 中文全称 |
|---|---|
| MA | MA 移动平均线 |
| EMA | EMA 移动平均线 |
| BOLL | BOLL 布林线 |
| SAR | SAR 停损点转向指标 |
| BBI | BBI 多空指数 |
| BBW | BBW 极限宽指标 |
| ENE | ENE 轨道线 |
| DC | DC 唐奇安通道指标 |
| KC | KC 肯特纳通道 |
| Ichimoku | Ichimoku 一目均衡图 |
| Alligator | Alligator 鳄鱼指标 |
| TD | TD 狄马克序列 |
| AI-SRL | 智能撑压线 |
| VPVR | Volume Profile 筹码分布 |

主图指标**参数名**（中文标签，出自 `ui_kline_indicator_setting_*`）：
移动平均周期、标准差倍数、上轨线 / 中轨线 / 下轨线、中轨线周期、加速因子、极限价格、计算周期、
短周期 / 长周期、上通道 / 中通道 / 下通道、上限 / 下限、因数、
转换线 / 转换线周期 / 基准线 / 基准线周期 / 迟行带 / 先行带1 / 先行带2 / 先行带2周期 / 位移（Ichimoku）、
JAW 周期 / JAW 偏移 / TEETH 周期 / TEETH 偏移 / LIPS 周期 / LIPS 偏移（Alligator）、
仅显示9和13（TD）、压力线 / 支撑线（AI-SRL）、上涨背景 / 下跌背景、
「默认」= `ui_kline_indicator_setting_load_default`（恢复默认按钮）。

### 5.5 副图指标

| 代号 | 中文全称 |
|---|---|
| VOLUME | VOLUME 成交量均线 |
| TVolume | TVolume 成交量 |
| MACD | MACD 指数平滑异同移动平均线 |
| KDJ | KDJ 随机指标 |
| SKDJ | SKDJ 慢速随机指标 |
| RSI | RSI 相对强弱指标 |
| StochRSI | Stoch RSI 随机相对强弱指数 |
| WR | WR 威廉姆斯指标 |
| OBV | OBV 能量潮指标 |
| CCI | CCI 商品路径指标 |
| DMI | DMI 动向指标 |
| DMA | DMA 平行线差指标 |
| TRIX | TRIX 三重指数平滑移动平均线 |
| BIAS | BIAS 乖离率 |
| PSY | PSY 心理线指标 |
| ROC | ROC 变化速率 |
| VR | VR 成交量比率 |
| EMV | EMV 简易波动指标 |
| BRAR（即 ARBR） | BRAR 情绪指标 |
| MTM | MTM 动量指标 |
| ATR | ATR 真实波动幅度均值 |
| AO | AO 动量震荡指标 |
| DPO | DPO 区间震荡线 |
| MFI | MFI 资金流量指标 |
| SMI | SMI 压缩动量 |
| BSV | BSV 币币主动买入/卖出情况 |
| Fund-flow | Fund-flow 资金流向 |
| OI | OI 持仓量 |
| BASIS | BASIS 合约基差 |
| FR | FR 资金费率 |
| PFR | PFR 预测资金费率 |
| FTBS | FTBS 合约主动买入卖出 |
| LSUR | LSUR 多空持仓人数比 |
| MLR | MLR 杠杆多空比 |
| TTMU | TTMU 交易精英多空平均持仓比例 |
| TTSI | TTSI 交易精英趋向指标 |
| LiqHeatmap | 清算热力图 |

AICoin 特色 / AI 副图指标（短名 → 全称）：
买卖热度 → AI-BSI 买卖热度；买卖笔数 → AI-BST 买卖笔数；筹码分布 → Volume Profile 筹码分布；
资金背离 → AI-FDI AICoin 资金背离；主力大单跟踪 → AI-LargeOrder 主力大单跟踪；
大额成交 → AI-Large Trades 大额成交；爆仓统计 → AI-LI 爆仓统计；资金流向 → AI-NetVOL 资金流向；
持仓差值 → AI-PD AICoin 持仓差值；指标胜率；
另有：主动买卖额(差值)/主动买卖笔数(差值)/主动买卖量(差值)、基差(币安)/基差(欧易)、
币本位聚合持仓K线 / U本位聚合持仓K线、累积成交量增量 / 累积成交量增量(K线)、
持仓/市值、市值、资金费率(k线)、信号预警。

副图参数名：K / D / 随机指标长度 / RSI天数长度（StochRSI）、超买 / 超卖、短 / 长、指标线。

> **默认参数数值未确认。** `res/values/arrays.xml`（56 个数组，只有 `ui_kline_depth_state_array`、
> `ui_ticker_technical_indicator`、`ui_kline_drawing_color_array` 之类枚举）、`integers.xml`、
> 以及 `ui_kline_act_kline_indicator_param_setting.xml` / `ui_kline_item_indicator_param_setting.xml`
> 里参数输入框 `@id/text_indicator_value` 的 `android:text` 为空、无 hint —— MA5/10/20、MACD(12,26,9)、
> KDJ(9,3,3) 这类默认值写死在 dex 代码里，资源中取不到。iOS 侧请按行业惯例自定，或反编译 dex 补齐。

### 5.6 指标菜单分类

`ui_kline_indicator_menu_type_*`：已选/推荐、常用指标、主图指标、副图指标、趋势型、能量型、
成交量型、超买超卖、压力支撑、特色指标、合约数据、现货数据、指标胜率。

分组标题：已选指标（`_page_pick_title`）、推荐指标（`_page_hot_title`）、历史选择（`_page_history_title`）；
空态「暂无已选的%s」「暂无常用%s,」+「立即添加」；新指标角标 `NEW`。

指标管理页（`ui_kline_act_indicator_manager.xml`）：主图指标 / 副图指标 / 特色指标 /
自定义指标-我的脚本；已选主图指标 / 未选主图指标 / 已选副图指标 / 未选副图指标；
提示「长按可设置指标」「长按编辑指标」「至少选择四个指标」「额外指标最多开启五个」。

三个下拉面板标题：`ui_kline_pop_menu_title_indicator`=**K线指标**、`_style`=**图表设置**、`_advanced`=**高级功能**。

---

## 6. 图表设置面板（btn_setting 打开的「K线设置」）

### 6.1 入口与归属

| 项 | 值 |
|---|---|
| 入口按钮 | `res/layout/ui_kline_part_setting_bar.xml` 中的 `FrameLayout@id/btn_setting`，`layout_weight="0.8"`，图标 `@mipmap/ui_kline_main_menu_setting_icon`，尺寸 `ui_kline_menu_item_with_icon_size` = **18dp** |
| 打开的面板 | **`res/layout/ui_kline_layout_style_side_menu.xml`** |
| 面板标题 | `ui_kline_side_menu_title_chart_setting` = **「K线设置」**（弹层形态的标题 `ui_kline_pop_menu_title_style` = 「图表设置」） |
| 容器壳 | `ui_kline_pop_menu_layout.xml`（仅 `pop_arrow` **11dp×6dp** + `FrameLayout@id/content_holder`），style / indicator / advanced 三类菜单共用 |

> **未确认**：`btn_setting` → `ui_kline_layout_style_side_menu.xml` 的映射是「布局 + strings + dimens」三方交叉推断，dex 已混淆（`m/aicoin/kline/main/menu/{A,B,C,…}`），未做字节码级确认。但该布局是全 `res/layout` 里唯一的 style menu、也是唯一引用 `ui_kline_side_style_menu_switch_button_width` 的布局，置信度高。

### 6.2 面板结构

顶部：`RelativeLayout` 高 `sh_base_title_block_height` + `include @layout/part_common_button_back` + 标题；主体为 `NestedScrollView`（`fillViewport=true`）。分组之间用 `ui_kline_setting_bar.SideMenu.Divider`（高 **1px**，左右 margin **20dp**）。

### 6.3 全部设置项（按布局顺序）

| # | id | 中文标题 / 选项 | 控件形态 |
|---|---|---|---|
| 1 | `switch_drawing_show` | **画线显示** | 开关（drawableRight = `ui_kline_kline_menu_toggle_selector`） |
| 2 | `kline_height` | **竖屏高度**，左右端点标签「低」/「高」 | **SeekBar**（`minHeight/maxHeight=2dp`，margin 10dp，thumb `ui_kline_ic_seekbar_thumb`；`max` 在代码里设） |
| 3 | `flavor_normal` / `flavor_ave` | **类型**：K线图 / 平均K线（Heikin Ashi） | 二选一标签按钮 |
| 4 | `single_account` / `mult_account` | **下单模式设置**：单账户 / 多账户（标题 TextView `gone`） | 二选一 |
| 5 | `tv_account_setting` | **账户下单管理** | 跳转（右侧箭头图标 12dp） |
| 6 | `switch_signal` | **信号展示**（带红点） | 开关 |
| 6a | `tv_show_current_signal` | 只展示当前周期的信号 | 勾选 `sh_base_ic_check_right_selector` |
| 6b | `tv_show_latest_signal` | 只展示最新的信号 | 勾选 |
| 7 | `ll_setting_kline` / `ll_setting_top` / `ll_setting_follow` | **K线数据显示**：K线内 / 顶部 / 跟随K线 | 三选一图片卡，卡片高 **75dp** |
| 8 | `theme_light` / `theme_dark` / `theme_default` | **色调**：亮调 / 暗调 / 默认 | 三选一 |
| 9 | `stage_line` / `stage_stick` / `stage_bar` | **缩放**：线状 / 条状 / 柱状 | 三选一 |
| 10 | `kline_setting_open_time_0_clock` / `_8_clock` / `_24h` | **开盘时间**：0点 / 8点 / 24H制 | 三选一 |
| 11 | `kline_menu_stick_position_left` / `_mid` / `_right` | **拖动位置**：偏左 / 中间 / 靠右 | 三选一 |
| 12 | `y_axis_log` / `y_axis_linear` / `y_axis_percent` | **坐标**：对数 / 线性 / %（`ui_kline_menu_percent_chart` 在 zh-rCN 缺项，回落默认值 `%`） | 三选一 |
| 13 | `cross_at_close` / `cross_at_touch` | **十字线**：收盘价 / 选中价 | 二选一 |
| 14 | `up_candle_empty` / `up_candle_filled` | **K线阳线**：空心 / 实心 | 二选一 |
| 15 | `ll_up_candle_color` / `ll_down_candle_color` | **柱子颜色**：上涨 / 下跌 | 取色，行高 **40dp**，色块 **22dp**，点开 `ui_kline_popup_color_picker.xml` |
| 16 | `switch_kline_right` | **主力/大额/筹码**（即右侧 105dp 面板的总开关） | 开关（`LazyCheckBox` / `sh_base.SwitchButton`），行高 **40dp** |
| 17 | `switch_y_reversal` | **翻转主图Y轴** | 开关 |
| 18 | `switch_sub_y_reversal` | **翻转副图指标**（带 help + 红点） | 开关，help 图标 `ui_kline_menu_help_size` = **15dp** |
| 19 | `switch_last_price` | **实时价格线**（最新价线） | 开关 |
| 20 | `switch_end_countdown` | **K线结束倒计时**（带红点） | 开关 |
| 21 | `switch_alert_line` | **显示价格预警线** | 开关 |
| 22 | `switch_growth_rate` | **至今涨幅** | 开关 |
| 23 | `switch_diff_rate` | **十字线添加距实时价标签**（带 help） | 开关 |
| 24 | `switch_grid` | **网格**（坐标网格线） | 开关 |
| 25 | `switch_alert` | **十字线添加预警按钮** | 开关 |
| 26 | `switch_info_btn` | **主图指标收起和设置按钮** | 开关 |
| 27 | `switch_sub_indicator_action_popup` | **副图指标移动和设置按钮** | 开关 |
| 28 | `switch_indic_unit` | **指标参数值简化显示**（带 help，tip = `ui_kline_fragment_menu_kline_indic_tip`） | 开关 |

### 6.4 不在本面板里的几项（容易找错地方）

| 主题 | 实际位置 |
|---|---|
| **涨跌颜色（红涨绿跌 / 绿涨红跌）** | **App 全局设置**，不在 K 线设置里。`res/layout/act_me_system_growth_color_settings.xml`（`item_growth_color_mode_default` / `item_growth_color_mode_reverse`）；文案 `settings_title_growth_color`=涨跌颜色、`settings_value_growth_color_mode_default`=**绿涨红跌**、`..._reverse`=**红涨绿跌**。本面板里对应的是 #15「柱子颜色 上涨/下跌」自定义取色 |
| **成交量** | 属指标体系，不是开关。`ui_kline_indicator_setting_home_item_name_tvolume`「TVolume 成交量」、`..._volume`「VOLUME 成交量均线」，在 `ui_kline_act_indicator_manager.xml` / `ui_kline_indicator_menu_layout.xml` |
| **持仓线 / 买卖记录 / 强平线** | 「高级 → 下单显示」子菜单 `res/layout/ui_kline_order_show_menu_layout.xml`：`tv_orders_switch`=**买卖记录**、`tv_position_line`=**持仓成本线**（`iv_position_setting` 跳 `ui_kline_dialog_position_line_setting.xml`）、`tv_liqui_switch`=**预估强平线**。持仓线弹窗内：`显示位置`（K线左侧 / K线右侧）、`显示形式`（隐藏持仓量和盈亏额 / 仅显示持仓线 / 显示所有内容） |
| **画线工具** | 「高级」菜单 `tv_drawings_mode`。本面板只有 #1「画线显示」总开关 |
| **时间轴** | 无独立开关；最接近的是 #10「开盘时间」 |
| **买一/卖一价线** | **未确认 / 未找到**。zh-rCN 中「买一价/卖一价」只出现在交易、预警、行情模块，K 线设置面板无此开关 |
| **均价线** | **未确认**。K 线模块无「均价线」文案；最接近的是 `ui_kline_flavor_average`「平均K线」与 MA 指标 |
| **复权** | **不存在**（加密货币行情，全量 zh-rCN strings 无「复权」） |

「高级」菜单完整项（`ui_kline_advanced_menu_layout.xml`）：主力大单 / 大额成交 / 筹码分布 / 信号预警 / 指标胜率 / 画线工具 / 对比K线 / 组合K线 / 下单显示 / 定位到k线。

### 6.5 侧边设置面板的尺寸与样式

`res/values/dimens.xml`：

| dimen | 值 | 行号 | 引用处 |
|---|---|---|---|
| `ui_kline_side_menu_width` | **255.0sp**（单位是 sp，疑为原作者笔误） | 2235 | res 内无 XML 引用，仅代码读取 |
| `ui_kline_side_menu_title_bar_height` | 26.0dp | 2233 | 无 layout 引用 |
| `ui_kline_side_menu_title_text_size` | 16.0sp | 2234 | `SideMenu.SwitchItem` 的 textSize |
| `ui_kline_side_style_menu_block_row_height` | **82.5dp** | 2236 | res 内无 XML 引用 |
| `ui_kline_side_style_menu_item_image_size` | 24.0dp | 2237 | res 内无 XML 引用 |
| `ui_kline_side_style_menu_item_text_size` | 13.0sp | 2238 | `styles.xml:8937`（`SideMenu.Background`）、`styles.xml:8719` |
| `ui_kline_side_style_menu_switch_button_width` | **45.0dp** | 2239 | 本布局 5 处开关的 `android:minWidth` |
| `ui_kline_style_config_dialog_item_height` / `_width` | 47.0dp / 70.0dp | 2243 / 2244 | res 内无 XML 引用 |
| `ui_kline_menu_help_size` | 15.0dp | 2131 | 三处 help 图标 |

`res/values/styles.xml`：

| style | 关键属性 |
|---|---|
| `ui_kline_setting_bar.SideMenu.Background`（L8936） | 宽 **72dp**，高 wrap，上下 margin **12dp**，上下 padding **5dp**，`carbon_strokeWidth=1px`，textSize 13sp |
| `ui_kline_setting_bar.SideMenu.Title`（L8985） | textSize **15sp**，paddingLeft **20dp** |
| `ui_kline_setting_bar.SideMenu.SwitchLayout`（L8976） | 左右 padding **20dp**，上下 padding `sh_base_offset_15dp` |
| `ui_kline_setting_bar.SideMenu.Divider`（L8951） | 高 **1px**，左右 margin **20dp** |

---

## 7. 画线工具

### 7.1 归属：画线工具条只在横屏

`res/layout-land/ui_kline_frg_ticker_kline.xml`（以及 `ui_kline_frg_ticker_detail_kline.xml`、land 版 `ui_kline_frg_scrollable_kline.xml` / `ui_kline_frg_spread_kline.xml`）include 了三个画线布局，默认全部 `visibility="gone"`：

- `ui_kline_part_drawing_menu_bar` —— 左侧竖向工具条
- `ui_kline_part_drawing_floating_menu_bar` —— 选中某条线后弹出的浮动属性条
- `ui_kline_part_drawing_magnifier_floating_menu_bar` —— 放大镜模式的确定/恢复/退出条

竖屏 `res/layout/ui_kline_frg_ticker_kline.xml` **没有**画线工具条，只有 `@id/iv_drawing_hide`（**18dp**，右边距 **64dp**，图标 `ui_kline_drawing_visibility_selector`）。

### 7.2 支持的画线类型（20 种）

文案来自 `ui_kline_drawing_show_name_*`（zh-rCN L5468–5487）：

| string 后缀 | 中文 | 英文 |
|---|---|---|
| `price_line` | 价格线 | Price Line |
| `strait_line` | 直线 | Line |
| `seg_line` | 线段 | Extended |
| `ray_line` | 射线 | Ray |
| `verti_strait_line` | 垂直线 | Vertical Line |
| `hori_straight_line` | 水平直线 | Horizontal Line |
| `hori_seg_line` | 水平线段 | Horizontal Extended |
| `hori_ray_line` | 水平射线 | Horizontal Ray |
| `arrow_line` | 箭头 | Arrow |
| `horiz_segment` | 平行线段 | Parallel Lines |
| `parallel_tunnel_line` | 价格通道线 | Parallel Tunnel Line |
| `rectangle` | 矩形 | Rectangle |
| `space_time_rule` | 时空尺 | Time and Price Range |
| `fib_retrace_line` | 斐波那契回调 | Fib Retrace Line |
| `fib_ext` | 斐波那契扩展 | Trend-Based Fib Extension |
| `fib_segment` | 斐波那契线段 | Fib Retracement Line |
| `fib_straight_line` | 斐波那契直线 | Fib Retracement Extended |
| `fib_sector` | 斐波那契扇形 | Fib Fan |
| `fib_circle` | 斐波那契螺旋线 | Fib Spiral |
| `magnifier` | 放大镜 | Magnifier |

其它画线文案（zh-rCN L5458–5467）：`退出画线`、`已隐藏所有画线`、`已显示所有画线`、`确定清除包括隐藏的所有线段吗？`、`画线数量已达上限`。

### 7.3 颜色选择器

`res/values/arrays.xml:826` 的 `<array name="ui_kline_drawing_color_array">`，**13 色**（画线颜色条与「柱子颜色」选择器共用）：

`#cf1423` · `#d4380d` · `#d46b08` · `#d4b107` · `#379e0f` · `#0a979b` · `#076dd9` · `#1c39c3` · `#531dab` · `#c41d7f` · `#000000` · `#989898` · `#f2f2f2`

`res/values/colors.xml` 中的画线 token：

| 颜色名 | 日间 | 夜间 | 行号 |
|---|---|---|---|
| `ui_kline_drawing_default_line_color` | `#1990ff` | （无 `_night`） | 5712 |
| `ui_kline_drawing_menu_arrow_bg_color` | `#f2f3f5` | `#1c242e` | 5713-5714 |
| `ui_kline_drawing_menu_quit_stroke_color` | `#b7bfc8` | `#4a5462` | 5715-5716 |

取色弹窗 `ui_kline_popup_color_picker.xml`：`padding 8dp`、`layout_margin 8dp`、`elevation 4dp`、背景 `ui_kline_popup_rounded_bg`；`@id/tv_default` 文案「恢复默认」（**13sp**，`paddingTop 10dp`，`marginBottom 12dp`）；`@id/grid_colors` 为 `GridLayout rowCount=2 columnCount=10`（13 色正好两行）。

色块 item `ui_kline_part_drawing_color_menu_bar_item.xml`：色块 margin `ui_kline_menu_item_color_padding` = **10dp**；选中图标 **15dp × 15dp**（`ui_kline_menu_item_color_width`），资源 `ui_kline_drawing_color_menu_selected_icon`。

### 7.4 线型与线宽

来自 `ui_kline_part_drawing_floating_menu_bar.xml` 的两个入口 + mipmap 资源集：

- **线型** `@id/ui_kline_floating_drawing_menu_line_style`，3 档：`..._line_width_thin`（实线，默认 src）/ `..._line_style_long`（长虚线）/ `..._line_style_short`（短虚线或点线）。各带 `_night` 变体。
  - **未确认**：这三档**没有对应 string**，纯图标，中文命名是按资源名推断；「短虚线」与「点线」孰准未确认。
- **线宽** `@id/ui_kline_floating_drawing_menu_line_width`，4 档：`thin` / `normal` / `thick` / `very_thick`，各带 `_night`。
  - **未确认**：具体 px/dp 线宽数值是代码常量，res 内无对应 dimen。
- 浮动条其余按钮：`..._line_color`（取色，tint `sh_base_text_secondary`）、`..._fill`（填充）、`..._lock`（锁定，`..._lock_selector` → locked/unlock）、`..._delete`（删除）。

### 7.5 画线相关布局尺寸汇总

**`ui_kline_part_drawing_menu_bar.xml`**（左侧竖条，根 `@id/kline_drawing_menu_vertical_bar`，默认 gone）

| 元素 | 值 |
|---|---|
| 内容区 `..._content` 宽 | **56.0dp**（高 match_parent） |
| 上 / 下 / 左边框 | 各 **1px**（`offset_1px`） |
| 画线类型 RecyclerView `..._line_type` | match_parent，`marginTop` **8dp** |
| 「更多」`@id/layout_vertical_more` | 高 **20.0dp**，背景 `ui_kline_drawing_vertial_more_bg` |
| 底部三按钮（隐藏 / 清空 / 分享） | 各上下 padding **8dp**，容器 `marginBottom` **8dp** |
| 收起箭头 `..._bar_arrow` | 宽 **14dp**，上下 padding **12dp**，`scaleType=fitStart` |

**一级项** `ui_kline_part_drawing_menu_bar_line_type_item.xml`：`padding` **9dp**，宽 match_parent；展开箭头 `kline_drawing_line_type_arrow` 默认 gone，`marginRight` **3dp**；主图标默认 `ui_kline_drawing_price_line`。

**二级项** `ui_kline_part_drawing_menu_bar_line_type_child_item.xml`：`paddingLeft/Right` **18dp**，`paddingTop/Bottom` **9dp**；图标 + 名称（`marginLeft` **4dp**，色 `sh_base_text_secondary`）。

**通用项** `ui_kline_part_drawing_common_menu_bar_item.xml`：高 **40.0dp**，`padding` **10.0dp**。

**浮动属性条** `ui_kline_part_drawing_floating_menu_bar.xml`：整体 wrap_content，左右 padding **8dp**，背景 `ui_base_drawing_popup_window_shadow`；每个子项 `padding` **8dp**；线型/线宽项内图标 `marginRight` **3dp** + 箭头 `ui_kline_drawing_floating_menu_bar_item_arrow_selector`。**无固定高度 dimen，完全 wrap_content。** 在 `layout-land/ui_kline_frg_scrollable_kline.xml` 里该条 `layout_margin="4dp"` 且 `alignParentBottom`。

**放大镜条** `ui_kline_part_drawing_magnifier_floating_menu_bar.xml`：三个 TextView 各 **14.0sp**，`paddingTop/Bottom` **8dp**，`paddingStart/End` **12dp**；文案「确定」（`sh_base_highlight_color`）/「恢复」/「退出」。

**二级弹窗** `ui_kline_drawing_popup_window.xml`：容器 + RecyclerView 全 wrap_content，背景 `ui_base_drawing_popup_window_shadow`，无固定尺寸。

**全屏二级弹窗** `ui_kline_drawing_full_popup_window.xml`：容器高 match_parent，背景 `ui_kline_common_transparent`；上边框 1px、左边框 1px；RecyclerView `paddingTop` **8dp**，背景 `ui_kline_menu_bg_with_alpha_color`。

**横屏退出画线按钮**（`ui_kline_part_period_landscape.xml`）：`ui_kline_menu_bar_landscape_quit_drawing`，文案「退出画线」，**14sp**，色 `sh_base_text_secondary`，`padding 5/3/5/3dp`，`marginRight 8dp`，`carbon_strokeWidth=1px`，描边色 `ui_kline_drawing_menu_quit_stroke_color`。


---

## 8. 其它值得复刻的交互细节

> 来源：`res/layout/ui_kline_frg_ticker_kline.xml`、`res/layout/ui_kline_frg_ticker_detail_kline.xml`、`res/layout-land/ui_kline_frg_ticker_kline.xml`、`res/values/dimens.xml`。

### 8.1 图表上的悬浮控件一览（竖屏）

全部作为 `FrameLayout#container_kline` 的直接子 View 叠在图表之上，图表本身不留白，靠这些控件的 margin 定位。

| 控件 id | 作用 | 尺寸 / 字号 | 内边距 | 定位 | 配色 |
|---|---|---|---|---|---|
| `full_screen` | 进入横屏全屏 | `ui_kline_overlay_fullscreen_icon_size` = **24dp** | — | `gravity=bottom\|start`，`marginStart` = `ui_kline_overlay_fullscreen_icon_left_margin` = **15dp**，底部 `..._bottom_margin` = **10dp** | 图标 `ui_kline_full_screen_icon`（走 skin） |
| `tv_back_to_last` | 「回到最新」气泡 | 文字 **11sp** | `paddingH 4dp / paddingV 2dp` | 贴图表右下 | 文字 `carbon_white`，底 `sh_base_highlight_color`，圆角 **2dp** |
| `tv_scale_auto` | 自动缩放徽标，文案硬编码 **"A"** | **12sp**（竖屏）／**14sp**（`ui_kline_frg_ticker_detail_kline.xml` 的横屏版 `tv_land_scale_auto`） | `paddingH 6dp / paddingV 2dp` | `marginEnd` = `ui_kline_overlay_show_right_icon_left_margin` = **18dp** | 文字 `sh_base_three_text_color`，底 `sh_base_one_background_color`，圆角 **2dp** |
| `iv_drawing_hide` | 画线模式下临时隐藏画线 | `ui_kline_overlay_drawing_hide_icon_size` = **18dp** | — | 右边距 `ui_kline_overlay_drawing_hide_right_margin` = **64dp** | — |
| `iv_show_right` | 展开/收起 105dp 右侧面板 | **20dp**（竖屏）／**15dp**（详情页 `iv_land_show_right`） | `padding 3dp`（详情页 `2dp`） | `marginEnd` **18dp** | — |
| `iv_close`（`ui_kline_frg_order_and_trade.xml`） | 关闭浮层 | **16dp** | `padding 2dp` | `marginEnd` **11dp**，图标资源 `ui_kline_overlay_close_right` | — |

**横屏差异（重要）**：`res/layout-land/ui_kline_frg_ticker_kline.xml` 里**没有** `full_screen`、`iv_show_right`、`tv_scale_auto`，也没有底部指标条 —— 横屏只保留 `tv_back_to_last` 和三个 overlay include。横屏的 A 徽标与右侧面板开关只出现在「详情页横屏」布局 `ui_kline_frg_ticker_detail_kline.xml`（`tv_land_scale_auto` / `iv_land_show_right` / `stub_land_kline_right` 150dp）。

### 8.2 `tv_scale_auto` 的一组"分场景"尺寸（重点，但只能推断）

`dimens.xml` 里为 A 徽标准备了两组各 5 个值：

| 资源名 | 值 |
|---|---|
| `ui_kline_overlay_scale_auto_spacing_to_show_right` | **44dp** |
| `ui_kline_overlay_scale_auto_spacing_to_show_right_index_land` | **18dp** |
| `ui_kline_overlay_scale_auto_spacing_to_show_right_index_portrait` | **12dp** |
| `ui_kline_overlay_scale_auto_spacing_to_show_right_land` | **12dp** |
| `ui_kline_overlay_scale_auto_spacing_to_show_right_main_portrait` | **6dp** |
| `ui_kline_overlay_scale_auto_extra_lift` | **8dp** |
| `ui_kline_overlay_scale_auto_extra_lift_index_land` | **0dp** |
| `ui_kline_overlay_scale_auto_extra_lift_index_portrait` | **0dp** |
| `ui_kline_overlay_scale_auto_extra_lift_land` | **0dp** |
| `ui_kline_overlay_scale_auto_extra_lift_main_portrait` | **0dp** |

**「未确认」**：这 10 个 dimen 在 `res/layout*/` 全树中**零引用**（只出现在 `dimens.xml` 与 `public.xml`），对 `classes*.dex` 做 `strings` 搜索也没有命中 `scaleAuto` / `extraLift` / `spacingToShowRight` 之类符号，说明它们由代码按场景 `getDimensionPixelSize()` 取用。以下仅为**按命名推断**，未经代码验证：

- `spacing_to_show_right`：A 徽标右边缘到 `iv_show_right` 图标的水平间距。默认 44dp（右侧面板展开时？），主图竖屏 6dp、副图竖屏 12dp、主图横屏 12dp、副图横屏 18dp。
- `extra_lift`：A 徽标相对基准位置的额外上抬量，默认 8dp，四个具名场景均为 0dp。

复刻建议：iOS 侧把 A 徽标做成「主图/副图 × 竖屏/横屏」四种场景各自一套 trailing / bottom 常量，数值直接照抄上表；默认值 44dp/8dp 作为兜底。

### 8.3 预警线提示气泡

`ui_kline_frg_ticker_kline.xml` 中 `ll_alert_line_tip_lable`：

- 小箭头 ImageView：`marginTop = -5dp`（负 margin 顶出气泡）
- 气泡 TextView：**12sp 粗体**，白字，底色**硬编码 `#1478fa`**，`paddingH 6dp / paddingV 4dp`，圆角 **4dp**，`marginTop = -12dp`
- 文案：`预警线已显示，可在设置中关闭`

### 8.4 空数据 / 加载 / 浮窗

| 布局 | 关键数值 |
|---|---|
| `ui_kline_part_empty_data.xml` | `paddingTop 15dp`，`marginLeft/Top` = `offset_8dp`，`marginRight` = `ui_kline_compare_info_window_right_margin` **60dp**，`minHeight` = `ui_kline_index_empty_view_min_height` **200dp**，文字 14sp `ui_kline_empty_data_text_color` |
| `kline_loading_view`（在主布局内） | `marginTop` **168dp** |
| `sh_base_include_empty_loading.xml` | 居中 ProgressBar，尺寸 `sh_base_empty_loading_bg_size` |
| `ui_kline_part_large_order_info.xml`（主力大单浮窗） | 高 **210dp**，`marginLeft` offset_8dp / `marginTop` offset_12dp / `marginRight` **60dp**，`elevation 4dp`，底 `ui_kline_bg_kline_large_popup`；徽标 9sp 圆角 7dp；标题分隔线 1px `sh_base_divider_dim_fill_2_color`，左右 margin 10dp；数据行 `marginTop` offset_4dp |
| `ui_kline_part_large_trade_info.xml`（大额成交浮窗） | 宽 **140dp**，`paddingTop 6dp / Bottom 10dp / Start,End 10dp`，margin 8/12/60dp，`elevation 4dp`；买单徽标 9sp，颜色**硬编码 `#ff32a853`** |
| `ui_kline_part_aisrl_info.xml`（AI 压力支撑浮窗） | `padding 12/10/12/10dp`，margin 8/8/60dp，`elevation 10dp`；标题 12sp 粗体；数据行 10sp，首行 `marginTop 6dp`，其余 4dp |

三个浮窗都用 `marginRight = 60dp` 给右侧留出 K 线价格轴的位置，这是可以直接照搬的排版约定。

### 8.5 未上线交易对的占位页

`ui_kline_part_online_soon.xml`（`ScrollView#layout_online_soon`，默认 `gone`，`elevation/translationZ 12dp`）：

- 容器 `paddingTop 38dp / Bottom 16dp / 左右 24dp`，水平居中
- 标题 18sp 粗体 `ui_kline_text_black`；副标题 14sp
- 倒计时：4 个等宽（`weight 1`）块，每块高 **86dp**，底 `ui_kline_online_soon_time_bg`；数字 **32sp 粗体** `ui_kline_online_soon_countdown_sub_text_color`，单位 12sp `ui_kline_online_soon_unit_text_color`，单位 `marginTop 14dp`；块间冒号 32sp
- 「添加提醒」按钮：高 **42dp**，左右 padding 16dp，`marginTop 24dp`，图标 14dp + `marginEnd 6dp`，文字 14sp
- 底部两个等宽入口（最新公告 / 联系我们）：`marginTop 22dp`，图标 15×14dp / 15×16dp，文字 14sp `ui_kline_open_news_text`，`padding 8dp`

### 8.6 其它可直接照抄的约定

- **换肤**：所有需要日夜切换的属性都写成 `android:tag="skin:<资源名>:<属性>"`，多条用 `|` 连接（如 `skin:a:background|skin:b:textColor`）。iOS 侧等价物就是把颜色 token 化后按主题查表，**不要**用 `values-night` 思路做两套布局。
- **分隔线厚度**：全局用 `offset_0.5dp`（0.5dp）或 `1.0dp`/`1px` 三种，K 线区内的竖分隔线（指标条中间）用 `offset_0.5dp` + 上下 `offset_6dp` margin。
- **详情页宿主** `ui_ticker_frg_detail_price_kline.xml`：价格块 include → `stub_extra_broad` → `tv_net_error`（高 **26dp**）→ banner（高 **36dp**）→ **`View#detail_divider` 高 8dp** 的粗分隔条 → `FrameLayout#kline_frame`。那条 8dp 灰条是「行情区 / K 线区」的视觉切分，复刻时别漏。
- **字号阶梯**（`dimens.xml`，全 App 统一）：`font_size_tiny_low` 9sp、`tiny` 10sp、`tiny_high` 11sp、`small` 12sp、`normal` 14sp、`normal_high` 16sp、`large` 18sp、`large_high` 20sp、`xlarge` 22sp。K 线区用到的只有 9 / 10 / 11 / 12 / 13 / 14 / 18 / 21sp。
- **间距阶梯** `offset_*dp`：0.5, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24, 28, 30, 32, 40, 42。K 线区高频使用 4 / 5 / 6 / 8 / 10 / 12 / 18dp。
