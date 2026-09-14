# AICoin 参考资料（反编译 + 真机实测）

这份目录是**当前已保存的 AICoin K 线一手研究素材**，从会话临时目录固化到仓库，
供后续接手的人（包括其它 AI agent）直接查证，不需要重新反编译。

## 来源

- APK：用户提供的 `~/Downloads/aic.apk`（AICoin 安卓版），用 jadx 反编译。
- 真机：用户本人 iPhone 上的 AICoin 专业版，经 iPhone 镜像操作并截图实测。

## 目录

| 路径 | 内容 |
| --- | --- |
| `java/Rj/` | 图表自绘层（混淆名）。核心：`y1.java` 坐标映射与列宽、`C2765z.java` 数据集、`AbstractC2759w0.java` 价格轴自动范围与 Y 缩放、`C2746s.java` 滚动/惯性、`C2723k.java`/`F0.java`/`J.java` 蜡烛几何、`M.java` 价格轴标签、`C2712g0.java` 文字基线、`C2764y0.java` 范围切换动画 |
| `java/Wj/` | 手势层。`a.java` 主手势分发（含 Y 轴缩放公式、双击恢复自动）、`b.java` 缩放检测器（AOSP `ScaleGestureDetector` 的逐字拷贝）、`c.java` 价格窗口平移 |
| `java/sp/aicoin_kline/` | 指标引擎与图表配置（**未混淆**，可读性最好，优先看这里） |
| `java/p398sh/aicoin/kline/` | K 线页业务层 |
| `res/layout/` | 216 个 K 线/图表/指标相关布局。重点：`ui_kline_frg_ticker_kline.xml`（竖屏主结构）、`ui_kline_layout_style_side_menu.xml`（K线设置面板 27 组）、`ui_kline_part_setting_bar.xml`（周期工具条）、`ui_kline_part_indicator_bar.xml`（底部指标栏）、`ui_kline_frg_kline_info.xml`（十字线信息条） |
| `res/values/colors.xml` | 全部色板（日/夜成对）。图表内部自绘用色**在 layout 里零引用**，全由 Canvas 按资源名取，必须从这里查 |
| `res/values/dimens.xml` | 全部尺寸常量 |
| `res/values-zh-rCN/strings.xml` | 中文文案（设置项名称、说明文字的权威来源） |
| `reports/REPORT-gestures.md` | 手势与缩放常量的代码级报告（895 行，含行号证据） |
| `reports/REPORT-resources.md` | 资源层（布局/色板/尺寸）的提取报告 |
| `reports/REPORT-indicators.md` | 指标参数、配色、柱体几何 |
| `reports/REPORT-candle-axis.md` | 蜡烛几何、时间轴、最新价线、十字线、极值标注 |
| `live-capture/FINDINGS.md` | **真机实测**记录（对数轴实测比值表、上下缩放实测倍率、早期记录，部分结论已纠正） |
| `live-capture/*.png` | 对应的真机镜像截图与放大裁切 |

## 证据等级（冲突时按此排序）

1. 用户本人手机上的 AICoin 实测（`live-capture/`）
2. Mac 客户端（不同代码库，只作旁证）
3. 反编译源码常量（`java/`、`res/`）
4. 推断

报告里的 `【已穷举验证】` / `【推断】` / `【未找到】` 标注就是按这个等级打的，照抄前先看标注。

## 结论汇总在哪

不要直接读这堆源码找结论——已经整理好的成品在：

- `docs/AICoin-K线复刻规格.md` —— 持续校准的复刻规格（**从这里开始读**）
- `docs/AICoin-安卓包-UI规格提取.md` —— 早期的资源层提取记录

## 2026-09-14 后续复核

优先读 `USER-CHART-PROFILE.json`、`live-capture/codex-2026-09-14/FINDINGS.md`。补齐 candle-axis/indicators 两份报告，增加 fk/gk/ek 等计算与渲染依赖、fk.M 的低层反编译核对。用户 iPhone 实测优先；Mac不能自动盖过Android源码，也不能代表iOS。全部交互尚未完成逐项实测。
