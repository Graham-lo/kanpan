# 看盘 · Kanpan

Swift 原生 iOS 行情与自选应用，使用币安 USDT 永续公开数据，包含加密资产和 TradFi 合约。SwiftUI 页面、UIKit/CoreGraphics 自绘图表，不依赖第三方图表库，不提供交易下单。

## 当前实现

- AICoin 为默认造型，原有11种风格共用根宽、间距、坐标、布局和手势；浅色/深色均沿用项目靛色，另提供原生纸色与暖暗配色。
- 主图 MA、EMA；常用副图 VOL、OI、MACD、KDJ、RSI。已启用输出参与自动范围，OHLC极值标签独立；参数草稿保存/取消、输出开关、轴倒置与历史十字线联动。
- 常见3–4副图一屏分配，可拖动边界调整高度，长按副图区域移动完整面板。数据展示支持K线内、顶部、跟随卡片。
- 默认进入行情末根贴绘图区右缘。正常历史拖动自由停留，两端越界只允许轻微阻尼移动，松手回到对应边界。历史焦点缩放、手动Y及自动复位保留。
- 独立原生自选页：持久化收藏、真实分类文件夹、自动分类建议、人工分类移动、长按行排序、滑动/批量删除、加号选品和按需详情。顶部直接展示较大的分类按钮，超出宽度的分类收进“…”弹出列表。行内走势图已移除，资源优先用于重要报价。
- 进程冷启动有收藏进入自选，否则打开BTC；前台在行情/自选之间切换持续订阅WS，进入后台释放，恢复后立即重连，不用磁盘旧报价冒充实时。
- 统一涨跌幅口径可选滚动24小时、上海0点、上海8点（UTC0点）。排除USD1与稳定币基础资产；TradFi不因某一时刻低成交额被隐藏。
- 官方/用户线路与两台VPS自动选择有效行情线路，健康连接保持，避免频繁切换。网关合并相同上游订阅，并限制异常资源占用；历史OI在后端按图表周期聚合、失败时备用节点接替。

- 最新报价由单一共享 QuoteBook 管理，按交易所时间与成交编号去重；换周期不借用缓存/历史 K 线收盘价；当前 WS 中带成交编号的实时价格与24小时统计分别合并。K线与OI请求带选择标识，隔离迟到请求和快速来回切换。
- 行情左上角为全部收藏快捷列表；完整品种页按交易所市场类型、板块标签筛选，独立于用户文件夹。

新增配色与数据审查记录：[护眼配色与数据完整性](docs/acceptance/护眼配色与数据完整性.md)。

## 代码与文档

| 位置 | 内容 |
| --- | --- |
| `Kanpan/Kanpan/` | 原生页面、设置、自选和图表宿主 |
| `KanpanCore/` | 坐标、布局、指标与纯Swift算法 |
| `KanpanChart/` | 自绘图表与UIKit手势 |
| `KanpanData/` | 行情WS、REST、目录、历史OI与选路 |
| [行情网关](Backend/kanpan-gateway/README.md) | 双节点共享订阅、资源预算、OI缓存与部署说明 |
| [当前复刻规格](docs/AICoin-K线复刻规格.md) | 用户最新要求、原版证据和实现约定 |
| [实现与真机验收](docs/acceptance/AICoin-base/foundation/IMPLEMENTATION.md) | 改动、测试、失败过程与未确认项 |
| [机型兼容记录](docs/acceptance/AICoin-base/compatibility/README.md) | 每轮二进制、机型清单与实际结果 |
| [原版研究报告](refs/aicoin/reports/REPORT-missing-chart-interactions.md) | iPhone实测、Android源码、实施推断分开记录 |

`prototype/`保留原交互和Claude自选设计参考；实际应用是Swift实现。早期[实施任务书](docs/实施任务书.md)中的默认风格、指标及部分布局已经被后续用户要求覆盖，应以当前复刻规格和最新验收记录为准。

## 构建与验证

Swift6、iOS17+；用Xcode打开 `Kanpan.xcworkspace`，选择 `Kanpan` scheme。当前模拟器验收使用已安装的iOS26.5运行时；机型覆盖不能替代旧版iOS运行时覆盖。

```sh
swift test --package-path KanpanCore
swift test --package-path KanpanData
swift test --package-path Kanpan/Symbols
make strict
xcodebuild build -workspace Kanpan.xcworkspace -scheme Kanpan -destination 'generic/platform=iOS Simulator'
```

App端无第三方依赖；Python网关使用独立环境与固定版本aiohttp。原版完整惯性/双指/Y缩放曲线、EMA编辑流程等尚未全部确认，不宣称1:1复刻已全部完成。自选、分类、顺序与设置持久化；K线仅有限内存和一份小型启动快照，实时报价不新增磁盘缓存。仓库不包含VPS登录配置、私钥、密码或令牌。
