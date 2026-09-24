# 图表底座增补实现与验收

本轮在现有未提交实现上增补；初始以研究报告 §13.4 为最新状态，最终边界补测改以新增 §14 为准，未采用 §11/12 的临时恢复清单。仓库内没有 AGENTS.md；已读上级 `/Users/mdd/zhk/AGENTS.md`，其中 Scorebook 专属构建约束不适用于看盘。机型兼容任务已按用户要求停止并交接到本任务；旧二进制矩阵不作本轮通过依据。

各阶段记录按完成时间追加，较晚的用户决定和最终验收覆盖前面的中间状态。当前兼容矩阵、源码冻结与剩余覆盖范围见 [机型兼容记录](../compatibility/README.md)。

## 保留的已有实现

- AICoin 默认风格及项目靛色；原有 11 种蜡烛造型、共用节距/实体框/坐标映射。
- 主图 MA/EMA 自动范围、独立 OHLC 极值标签、实时尾柱指标更新、共享历史选择。
- 水平硬边界、历史焦点缩放、AOSP SPLINE 惯性参考实现和自动 Y 复位入口。
- `MainScreen.heartbeat()` 已有前台每秒时钟，本轮没有重造计时器。

## 本轮落实的代码

| 文件 | 新增或修复 |
| --- | --- |
| `KanpanCore/Geometry/Layout.swift`、`Main/ChartHost.swift` | 按用户后续要求，常见3–4副图压缩分配到一屏，竖屏高度设置重分主副图；仅极小窗口/过多面板保留最低高度后的滚动。下边界拖柄连续调高、保存每指标独立权重；标题长按拖动整块面板排序。图框、裁剪、轴、触摸使用同一 Layout，无镜像尺寸常量。 |
| `ChartRenderer.swift` | 对高度独立的轴测宽；启用输出参与自动范围、隐藏输出保留槽位和颜色；自适应仅增加主图图例上方空间；百分比最新价标签使用统一基准；倒计时下方不够时改上方。 |
| `ChartRenderer+Sub.swift` | 完整面板按指标身份排序；曲线/柱/轴/触摸统一副轴倒置；小高度减少刻度密度；RSI阈值带；默认读数取各输出最后有效样本，选中时严格取共享历史列；指标数值简化。 |
| `ChartOptions.swift`、`Settings/Model/Prefs*.swift` | 数据位置、选中/收盘模式、主副轴允许翻转、自适应、简化、高度、RSI阈值和隐藏输出持久化；容错解码保持已有存档。副图可同时选七项，覆盖原版五副图并存。 |
| `IndicatorDraft.swift`、`Panels/IndicatorPanel.swift` | MA/EMA/VOL/OI/MACD/KDJ/RSI均有非空设置页；草稿参数与输出一起保存，取消/下拉退出不写入设置。保留计算依赖，只屏蔽所选输出。EMA参考用户截图12/144/169/200，不宣称原版编辑页实测。 |
| `Panels/ChartPanel.swift` | 上述设置的可操作入口；所有风格统一网格设置，原存档 `.style` 在绘图时解析成共用默认无网格。 |
| `Main/MainScreen.swift`、`ChartView.swift` | 顶部OHLC由同一选择源派生，切模式/关闭选择/移除被选副图/换品种周期清理；K线内和跟随卡片由十字线层绘制，跟随卡片按容器中点换边并限制大小；横屏标题独立行，消除MA图例遮挡。 |
| `Geometry/Clamp.swift`、`ChartView+Gesture.swift` | 少数据超宽容器使用完整400虚拟列边界；触点数量变化重新取基准并计算所有触点平均span；模式4不再把任何RIGHT边界等同最新无留白对齐；松手速度采样防止停顿后误甩；取消/离屏清临时触点/Y锚；主轴双击仅复位Y。 |
| `Geometry/PriceScale.swift`、`ChartView+Gesture.swift` | 百分比基准改为首个相交列收盘（不再用额外绘制保护列）；手动Y范围以价格域归一化中心与倍率生成，拖轴中保存范围中点锚；正常/倒置触摸正逆换算一致。 |
| `Main/ChartHost.swift`、`TopBar.swift` | iPad按钮中心命中修复；回到最新按钮位于原生图表盒子，与滚动层统一命中顺序。iPad全屏/返回，手机物理转屏。 |
| `ChartView+Gesture.swift`、`ChartRenderer.swift` | 十字线出现后按落点锁定操作：只有绘制交点44pt范围内拖线，其它位置横拖清选择并拖K线；共享交点计算覆盖主副图、倒置、选中/收盘两模式。44pt是原生可触达目标设计，不声称原版尺寸。 |
| `Binance/Endpoints.swift`、`Feed/MarketFeed.swift` | WS迁到`/market/stream`，订阅kline/ticker/markPrice；移除生产订阅中混入的旧trade及public盘口流。权威K线同步刷新末根与最新价；REST仅静默兜底，期间收到WS就丢弃过期REST快照。 |
| `AICoinBehavior.swift` | 现有实时跟随函数读取当前留白设置，不再只按默认靠右判断。 |

## 证据级别与实现取舍

- **iPhone原版实测**：来自 `REPORT-missing-chart-interactions.md` §11–13、`iphone-live-manifest.json`，本轮读取并查看高度29/30、跟随40、自适应45等原始截图。MA/EMA影响自动Y、OHLC极值独立、面板整体换位、模式残留需要修复、倒计时持续变化等均有报告证据。
- **Android源码核对**：直接读取 `Rj/M.java:135,193–217`，q12=0的释放状态取选中柱 `Sj.b.a()`，q12=1取保留触点Y，拖动中自由Y；`Sj/b.java:a()`为close。对应 `Rj/C2742q0.java:R/U`、`Rj/y1.java:593–603` 的百分比基准为 r()=floor(offset/spacing) 的close。硬边界另核 `research-gap/Rj-y1-simple.java:249–272`，触点与Y算法仍以报告 §10 核对材料为参考。
- **工程推断/改进**：竖屏相对高度公式、最小可读尺寸、卡片按容器中点换边、图例动态留白公式、负数不进入主图正价格log域、对数Y平移采用共享逆映射差值，均不是 iPhone 精确参数实测。Android父类对数平移原式不一致处没有当作iOS结论复制。RSI阈值改变底色，不强迫阈值进入曲线自动范围。
- `.style` 网格枚举只为读已有存档保留名称，不存在按风格分支的图表几何/手势实现。缩略图原视觉素材未重做。

## 自动化验证

最终包检查：`make core-test data-test app-logic-test`，Core **183**、Data **61**、Settings/Style **57**、Symbols **44**、Diagnostics **47** 项通过（`final-packages.log`）。Chart **68** 项通过（`chart-final.log`），包含主副图×正常/倒置×选中/收盘状态下十字中心拖动和远处拖图的实际触摸状态机测试。`make strict` 通过（`strict-final.log`）。

高度分配、连续调高、参数保存/取消、隐藏槽位、持久化、坐标正逆映射、历史缩放锚定与边界、触点交接、取消清理等由Core/Chart/Settings测试覆盖。机型矩阵由本任务接手，当前统一版与旧版证据分开记录在 `../compatibility/README.md`。

定向iPad Pro13回归：`iPad-Pro13-resize-fixed` **1/1**通过；`iPad-Pro13-new-gestures` **3/3**通过（十字中心/远处拖动、标题长按排序、连续实时更新）。实际界面采样约5秒内出现5份不同OHLCV，包括收盘价78658→78651.3，成交量5190.626→5191.937。不是以“WS连接成功”代替刷新验收。

## 真机验收（持续追加真实结果）

用户明确要求真机后，已与“查看看盘项目窗口”确认设备未被其它任务占用。设备：iPhone16 Pro，iOS26.6.1，原生测试截图1206×2622，不能与报告镜像尺寸混用。真机测试环境使用 `KANPAN_TEST_PROFILE=1` 内存设置，测试改动不覆盖用户已保存偏好。原版AICoin当前4h画面未更改其设置。

首轮 `device-ui.xcresult`：1通过、2失败。

- **通过**：顶部OHLC → 跟随卡片 → 关闭选择，验证顶部旧历史内容及选中价格清空；截图已导出 `device-attachments/` 并实际查看。
- **未通过**：高度测试设备服务报 `Lost connection to testmanagerd`，不能算通过；MA测试使用了英文 `Increment` 标识，但实际为 `indicator.param.0-Increment`，已据真实界面树修正。
- 二轮等待解锁时 Xcode 明确报 `Unlock iPhone to Continue`。后续结果见新增日志，不将等待或失败计作通过。

二轮 `device-ui-r2.xcresult`：高度联动与数据展示清理通过，MA输出测试误点Form整行中部而非开关，失败保留。
三轮 `device-ui-r3.xcresult`：**2/2通过**。MA草稿取消、点实际开关并确认状态变为0、保存后隐藏MA10曲线/图例；历史区实际合成横拖、双指放大、手动Y和A复位均通过。该测试观察惯性结束后窗口稳定，但不代表已测量原版惯性时序或完整多指曲线。
四轮 `device-ui-r4.xcresult` **3/3通过**，但其“滚动到末端”布局已经被用户随后提出的一屏要求取代，不能作为最终布局验收。

一屏首轮 `device-one-screen-r1` **5通过/1失败**：四副图一屏、数据模式清理、横拖/缩放/手动Y、MA取消保存、回到最新通过；边界拖动失败。第二轮 `device-one-screen-r2` 有两项失败：旧OI坐标按全图比例推算，落在新边界拖柄；拖柄坐标随布局移动损失位移。已分别改为读取实际Pane几何和从固定容器触点原点计算位移，保留失败日志。

图表最终真机回归 `device-final-r1`：**10通过/1失败**。布局、中心拖线/其它区域拖图、整面板排序、边界调高、数据清理、MA草稿、风格和手势通过；实时更新失败。当时手机网关流量命中DIRECT、无法收到行情，不能用Mac代理成功代替手机成功。后续部署VPS后复验如下。

## 实时行情故障证据

- 官方2026-03-06公告要求迁到 `/public`、`/market`、`/private`，旧地址于2026-04-23退役：[Binance迁移公告](https://www.binance.com/en/support/announcement/detail/ebf9b0aa9eca4ff3804eef6fb09ba32a)。K线/行情/标记价属于market，盘口属于public：[官方频道表](https://developers.binance.com/en/docs/catalog/core-trading-derivatives-trading-usd-s-m-futures/api/ws-streams/public)。
- 原代码“2026-09主网kline不推帧”的结论来自旧地址，应废止，不能因此以5–10秒REST轮询充当正常实时推送。旧trade/bookTicker解码及合成测试保留给历史回放，不再混订不同路由。
- 首次临时Swift/Node探针命中Surge `BinanceDirect.list,DIRECT`，TLS失败，日志仅说明该路由不可用。重新以现有项目规则覆盖的 `kanpan-feed` 进程运行（未改网络、规则或节点），新地址约16秒收到 **37条kline、8条24hrTicker、16条markPriceUpdate**；同路由同订阅旧地址 **0条**。见 `ws-market-routed.log`、`ws-legacy-routed.log`。超时主动关socket产生的末行错误不是握手失败。
- 可执行探针源码和运行说明在 `ws-probe.swift`；不得用未命中项目代理的探针结果判断市场流存活。

## 仍未确认

- 本项目真机执行的合成触点测试，与原版AICoin实测是两类证据。原版横拖方向与最新端回位已在§14补测；完整惯性、多指焦点/极限、手动Y连续曲线仍未完成，不能宣称1:1手感通过。
- 原版EMA参数页为空白，仍未证实其编辑/保存流程；本项目提供完整编辑功能不复制空白异常。
- iPhone百分比基准、收盘模式释放行为尚缺独立原版复测，本轮采用上述Android源码；精确轴刻度阶梯、极值标签全局避让、跨尺寸原版锚点仍待标定。
- 其它指标和画线工具未扩展本轮范围；原有能力保留。

## 智能行情与历史OI后端

- `MarketSocketRouter.swift`：新连接对用户配置、官方、VPS比较首条有效行情，保留获胜首帧，关闭未选连接。健康连接终生保持，不定期竞速，不因短时更快切线；只有断线、15秒没有有效数据或真实网络接口改变才重连。ping和订阅ACK不刷新有效数据期限。
- `WSClient.swift`：运行代次阻止旧连接回调污染新订阅；选路等待期间切周期，连接后按实际已订流补差，不丢掉变更。`MarketNetworkMonitor.swift`只监听可达性/接口变化；Feed保留当前图表数据和窗口，恢复后补缺。
- 网关部署于项目行情VPS，域名`kanpan.107-174-172-10.sslip.io`。两台VPS的REST均实测451，WS与历史归档可用。现有站点和其它业务规则保留；初次部署因Caddy2.6.2 admin off，在validate后短重启一次。后续OI周期更新只重启独立Python服务，未动WS/Caddy。没有修改Mac Surge规则。
- 公网WS16秒收到33 kline/7 ticker/14 markPrice，kline最大间隔792ms。`device-gateway-live` 真机**1/1通过**：1.13–5.08秒取得5份不同OHLCV，close78773.5→78773.6，volume274.302→274.499，见导出的采样。`device-gateway-period`等待锁屏后为合并新需求主动取消，没有通过结果。
- **历史OI在后端处理**：`Backend/kanpan-gateway/server.py`的`/oi/v1/metrics/{symbol}/range?interval=…&from=…&to=…`统一解析归档、去重、按请求周期取桶内最后持仓量；不求和。周一UTC、月长、闰年使用日历；1m/3m保留5m源粒度，无数据不填假值。只有历史数据走这里，实时WS和近期REST不上传后端。
- 日切片缓存200MB、8下载并发、64待处理键合并；范围请求最多4个，按2天批处理（共享网关最终版）避免多年原始数据全驻内存。客户端正常只收聚合结果，网关故障仍能走原日切片/官方归档回退。接口路径和范围有限制，不能用作任意URL代理。
- 公网2021-12-01 BTC验证：5m288点7460字节；4h6点157字节；1d1点27字节，三者末值60657.802一致。4h第一桶59795.984，区别于原始首点59230.06，证明不是把5m原始数据直接给高周期图。缓存公网约0.56秒，本机服务缓存命中约4ms。见`gateway-public-period.log`、`gateway-public-oi.log`。
- `OISource.chartSeries`接通原来被App绕过的周期管线，后端历史结果不再在手机重复解析ZIP；近期native period合并时优先近期采样。稀疏`OISeries`消除5万格截断，并严格对齐相同桶，不跨缺失月冒用旧值。前台每分钟刷新可见尾部OI，独立于倒计时开关；OI不是逐笔WS。
- `iPad-Pro13-gateway-final` **4/4通过**，含历史日线OI、实时、四副图及横屏；`device-tradfi-final`的历史OI和实时均通过。

## TradFi品种

原筛选仅允许`PERPETUAL`，真实`exchangeInfo`中MU/SNDK/SKHY/SKHYNIX均为`TRADIFI_PERPETUAL`且`TRADING`，被错误过滤。`RESTClient.swift`允许这两类USDT永续，仍排除交割/停牌/非USDT；`SymbolCatalog.swift`升级缓存结构标识，旧目录即使未满24小时也刷新，失败保留旧列表。品种页再次进入会查询缓存服务以接收更新。

真实证据`tradfi-exchange-info.log`；约16秒内四品种分别收到SNDK41、MU22、SKHY16、SKHYNIX23条K线WS。手机搜索三种用户指定品种并打开真实K线已通过，见`device-tradfi-final`。官方上市说明：[MU与SNDK](https://www.binance.com/en/support/announcement/detail/80549fadb3e447d1a859b8cedd0ccd69)。SKHY与SKHYNIX保留为两个独立合约，不按名称合并。

## 独立自选页与入口调整

`Symbols/FavoritesView.swift`是独立自选页，底栏自选取代画线，底栏仍五项；画线位于`IntervalBar`。创建/重命名/删除分类、移入分类、分类内和全部排序、取消收藏、添加品种、点击返回对应行情均接到同一`SymbolPickerModel`。删除分类把成员归回默认，不取消收藏；旧`kanpan.symbols.v1`增量迁移，收藏与最近不丢失。分类持久化及组内排序独立由`FavoriteGroupTests`验证。UI测试使用内存自选存档，避免改用户自己的收藏。

此自选页是按用户需求新增的原生界面，不声称已完成原版AICoin自选页逐像素取证。

## 原生自选与统一涨跌幅（2026-09-15追加）

`prototype/自选原型.html`是用户提供的Claude设计参考，实际页面为`Kanpan/Kanpan/Symbols/FavoritesView.swift`原生SwiftUI，没有HTML/WebView。接入紧凑品种行、24h成交额/振幅、实时价格/涨跌胶囊、分类数量/涨跌数量、排序、删除、独立详情按钮、长按行拖动与批量移动/移除。按用户最新要求已移除行内走势图及对应分钟历史请求。自选和分类保存在原有SymbolPrefs存档中，兼容旧收藏；删除分类保留其中品种，取消收藏清除分类与置顶关系。

`Main/QuoteBook.swift`为自选与可见搜索行共享一条逐品种ticker WS；前台切页持续订阅，进入后台才停止，保留既有智能线路选择。每批真实报价驱动SwiftUI更新。仅展开详情时请求分钟历史，最多2个并发，1h/4h涨跌读对应分钟开盘，缺历史显示“—”；没有模拟涨跌/随机曲线。24h高低/成交额/振幅仍是交易所滚动窗口，振幅分母为交易所24h开盘，独立于日涨跌幅设置。

设置新增“开盘时间”：24小时、上海0点、上海8点/UTC0点。国际0点与上海8点是同一时刻，不重复设选项。AICoin源码字符串依据：`refs/aicoin/res/values-zh-rCN/strings.xml`中的开盘时间/新加坡0点/国际0点条目（约6672–6673、7218、7532–7533）；公开说明 https://www.aicoin.com/zh-Hant/article/29707 。本轮未新增原版真机操作证据。`ChangeBasis`计算独立于图表百分比轴；主行情标题、横屏标题、搜索与自选使用同一口径。日开盘按需REST获取一次，收到WS价格后本地重算，跨日清除旧开盘并刷新，未取得新开盘显示“—”。设置即时存档。

进程首次启动有收藏显示自选，无收藏默认BTC；普通切后台再回来保留当前页面。底栏自选替换画线，画线进入周期条。

### 品种范围最新决定

用户明确不接USD1，并希望排除稳定币品种。2026-09-15实查币安exchangeInfo：190个`USDT/TRADIFI_PERPETUAL/TRADING`全部纳入；1个`SPCXUSD1`不纳入（用户要求）。普通USDT永续过滤明确的稳定币基础资产（USDC、FDUSD、TUSD、USDP、DAI、USDE、PYUSD、USD1、USDD），不会用名称包含USD或成交额阈值误删HYUNDAI/TradFi。接口当前实际稳定币对为USDCUSDT。全量核对清单见`tradfi-full-catalog.json`；目录schema=4使旧缓存立即刷新。回归覆盖USD1、USDC计价、USDCUSDT、交割与停牌负样本。

原生iPad首轮冷启动实时自选、上海8点涨跌幅通过；分类流程多轮在“移到分类”的测试定位失败。最终导出截图/界面树确认长按已展开，真实原因是详情VStack的accessibilityIdentifier继承覆盖了子按钮标识。详情增加独立accessibility容器，行点击与长按使用互斥手势、编辑外禁用拖动排序，随后复验。之前失败记录全部保留，不能当作通过。最终结果继续追加。

最新可执行检查：Core 187、Data 72、Symbols 47项通过（`native-final-packages.log`）；Settings增量缓存未识别新增ChangeBasis，清理该SwiftPM包的构建缓存后，Settings/Style 57、Diagnostics 47项通过（`native-final-settings-clean.log`）。Chart 68项通过（`native-final-chart.log`）；`make strict`通过（`native-final-strict.log`）；后端7项通过（`native-final-gateway.log`）。没有调宽性能断言：早期并发构建下snapshotSpeed超时结果仍保留。测试pingPong的假时钟/有限样本使用独立延长静默窗口，以免测试pong期间无行情触发无关重连；生产15秒有效行情看门狗未改。

实际客户端目录复验`native-catalog-live.log`：使用当前SymbolCatalog/REST实现，535ms取得717个符合产品范围的USDT永续，SNDK已在其中。190个TradFi为接口目录覆盖，真机逐个行情测试只覆盖SNDK/SKHY/MU，不宣称逐一跑过190个实时通道。

## 自选性能与交互最终增补（2026-09-15）

- 按用户最终决定删除自选行内走势图、真实 tick 小曲线采样缓存，以及普通可见行的分钟历史请求。资源优先用于价格、统一开盘口径的涨跌幅、成交额、24h高低与振幅。详情的1h/4h仅展开时取分钟历史；内存最多8个品种、每种245根，退出/收起取消未完成请求。没有新增磁盘报价缓存、快照数据库或后台常驻WS。
- `QuoteBook.swift`：进入前台立刻创建当前报价会话，同时开WS并为可见缺报价行补实时REST，最多4个并发、单请求5秒超时。WS先到时迟到REST不覆盖；8秒以上的过慢请求、本轮之前的请求不作为当前报价。离开后台/线路变化后清除旧报价，保持收藏和顺序。网络只在可达性/接口变化时重建，健康线路仍保持，不根据细小速度差频繁切换。
- `QuoteSession.swift`提供会话代次/每品种版本/请求有效期纯逻辑，覆盖旧REST覆盖新WS、无关品种更新、前台代次与超时边界；`SymbolPickerModelTests`覆盖清报价不清收藏，以及隐藏搜索表停止重建、打开后同步最新。
- `SymbolPickerModel`在自选页停止每笔行情重建隐藏的全市场搜索分区，重复报价不重复更新；打开搜索品种页才恢复分区实时更新。HTTP请求显式忽略本地响应缓存。自选只保存用户品种/分组/顺序，报价仍是当前网络数据。
- UI：固定价格列和行高，缺数据用静态中性占位，真实数字以0.32秒淡入；遵守减少动态效果。没有“加载中”文字、大转圈、虚构进度、随机价格或人为等待。实时状态只在收到真实WS行情后成立，握手成功不冒充行情已到。
- 自选搜索按钮使用36pt矩形命中范围，点击展开本页筛选并自动聚焦；取消清除筛选，输入去首尾空白/不区分大小写。右滑显示“删除自选”，全滑不直接删除。
- 自选编辑使用自定义状态，不混用系统EditMode的右侧删除/拖动控件。编辑开始取当前报价快照，避免右侧控件随WS排版跳动；重新连接清除该快照，退出编辑读取最新报价。副图长按命中扩大到完整曲线区域，标题、曲线、图例、刻度和交互面板整体移动；普通横拖仍用于历史平移，轴与分隔条独立处理。
- 主面板展开时，原生触摸遮罩覆盖其外部区域，第一次点击只收起；包括主图、顶栏及横屏外部区域，不向下触发十字线/搜索。`PanelDismissShield.swift`和`ChartHost`共同处理系统sheet及图表内部命中。

### 证据与未确认项

（下列 iPad 日志 2026-09-24 已删，`git show b5a4d543:<路径>` 取回）`native-editor-dismiss-ipad.log`最新自定义编辑稳定与面板外点击2/2通过；`native-right-swipe-ipad.log`右滑确认删除1/1通过；`native-direct-sort-ipad.log`普通自选行拖动和整个副图区域拖动通过，其中旧编辑控制测试失败后来已修复。`native-fresh-quotes-symbols.log`53项、`native-fresh-quotes-data.log`72项、`native-fresh-quotes-strict.log`严格构建通过。此前Core188、Chart68、Settings/Style57、Diagnostics47、后端7项见各专属记录。

正式手机存档已通过devicectl读回核对，包含用户要求22个品种和既有额外收藏SPCXUSDT，三类加密/美股/贵金属；保留既有数据，不覆盖清空。`user-favorites-final22.log`完成补MSFT/SOXL，但其普通行拖动断言失败，不计入通过。最终正常用户会话复验结果另列，不能用早期模拟器或旧二进制通过代替。

原版AICoin的真实横拖/惯性/双指缩放/手动Y精确手感曲线仍未确认，不能把本项目iPhone测试当原版对照通过；原版EMA参数页空白不作为目标，也不宣称已实测原版编辑流程。旧11机型121项属于早期底座冻结包，最后的自选迭代是定向复验，并非最新全机型121项。


### 自动分类模块与实际文件夹（最终决定）

用户最终取消“全部”“默认”和额外“自选”分类，界面只显示实际文件夹，恢复上次选择的文件夹ID。收藏首次加入时根据品种识别结果创建/复用加密、美股、贵金属、其他；不会替换人工创建分类，也不会重分配已人工移动的成员。详情与编辑仍可移动，普通行左滑新增“移到分类”，右滑确认删除。

`KanpanCore/Model/SymbolClassification.swift`独立提供资产类别、地区、原始细分标签、规则版本及依据来源；不操作UserDefaults或用户文件夹。`SymbolInfo`保留交易所underlyingType/underlyingSubType/contractType，旧目录可解码，目录schema5强制补齐元信息。`Symbols/FavoriteCategory.swift`负责当前粗粒度文件夹建议，与事实分类分离，海力士进入美股是用户明确的文件夹规则，Core仍保留KR地区事实。后续可以扩展行业/地区/资产标签，而不改写用户分类。

全量公开目录快照回归717品种：加密资产525、股票180（保留US/HK/KR/CN地区）、贵金属4、其它商品4、指数2、Pre-IPO2；事实分类均有来源，未知新增种类明确返回other/unknown。文件夹建议与事实类别不强制一一对应（例如现有加密指数建议加密，海力士归美股，其它地区股票默认其他）。公开依据`favorite-category-source.json`，全量测试fixture及`RESTTests.completeCatalogClassification`。Core191、Data73、Symbols56通过，新增文件后Symbols包旧增量索引未识别Core分类模块，清理该包后通过；原失败日志保留。`native-classification-strict.log`严格构建通过。

真机`user-session-final`图表交互1项通过（63.973秒，含五个外部点击入口、顶栏点击阻断、副图完整区域排序往返、十字中心与外部拖动）。自选轮次失败处经截图确认：第三方键盘已展示、搜索框Keyboard Focused，但测试只匹配app.keyboards，修正为真实焦点及输入结果验证。`user-keyboard-final`搜索输入/取消与价格连续变化通过阶段，冷启动第一有效报价443ms；回前台时页面被切到美股导致BTC定位失败，不把整轮计为通过。最终连续无其它操作复验另列。

### 行情网关安全检查与提交边界

网关仅公开行情，不接币安API密钥、账户、交易指令。客户端用系统URLSession证书校验，WSS到网关、HTTPS升级WS到固定币安上游，没有任意目标URL转发。历史路径限制品种与日期、并发与范围上限；实时帧不存盘。部署的历史服务已只读核验为active、loopbackOnly、DynamicUser/NoNewPrivileges/ProtectSystem=strict/ProtectHome/PrivateTmp，MemoryMax256MB。服务仍为公开入口，存在被占用带宽/连接资源的风险，不等于具有用户认证或DDoS防护；VPS是受信中转节点，而不是交易所端到端签名行情。

提交扫描未匹配私钥正文、常见访问令牌、含凭据URL或硬编码密码/密钥赋值。SSH配置、私钥、登录参数不进入仓库；客户端公开网关地址仍需保留，本身可从客户端及DNS获知，不属于管理凭据。Apple后台任务调度不保证指定时间执行，参见https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate；本轮没有用后台刷新伪装实时保活。


## 前台持续报价、删除入口和双节点收口（2026-09-15 03:30）

用户确认前台使用App不应因切页断开WS。`QuoteBook`将前后台与页面可见性分开管理：前台有收藏即持续订阅，页面关闭只取消该页的临时REST/详情任务；收藏或可见搜索行变化用原连接增退订，最多64品种，取消整市场广播。`QuoteSubscriptionPlan`覆盖前后台、跨页、去重及可见行优先。没有旧报价磁盘缓存；后台或真正重连清空旧报价，收到有效数据恢复。`MainScreen`统一传入前台/收藏状态，`SymbolPickerView`报告真实可见行。

自选左滑原“置顶”改“删除”，保留“移到分类”；右滑删除继续存在。两边滑动只展开操作，点击删除才移除。批量编辑统一为删除，不再有置顶按钮；旧pinned存档字段保留兼容，但不再覆盖用户拖动顺序或显示置顶标记。

真机`user-foreground-live` **1/1通过，43.097秒**：单次中心搜索并直接输入、实时报价连续变化、行情→自选首个可用界面已有报价，前后session均1、rows23；后台7秒再激活session2，冷首帧470ms、恢复214ms。本轮在实际网络条件下测得，不承诺任何网络都达到该时延。测试也检查左滑“删除”存在、“置顶”不存在，不删除正式收藏。更早`user-foreground-shared`因runner环境变量写到错误xctestrun结构而跳过，不能算通过；已修正后完成上面的实跑。

正式自选`user-final-live-sort` **2/2通过**：搜索实时刷新，以及普通行长按慢拖排序、结束进程冷启动后顺序保持、移动分类后恢复。该轮冷首帧550ms、后台恢复244ms。正式存档仍23品种：加密5、美股16、贵金属2，BTC在加密第一；含用户已有SPCX，未擅自移除。

新增共享网关代码见`Backend/kanpan-gateway/{stream_hub,resource_limits,server}.py`和同目录README。两台各一条固定上游，引用计数合并订阅，有限待发最新帧；来源连接/流数/控制频率/带宽有界，慢客户端隔离，宿主压力降低预算、缓慢恢复。历史OI使用同日请求合并和缓存，降低每范围工作数并限制来源；客户端`OISource`主失败后备用，保留请求周期。`MarketSocketRouter`支持备用独立HTTPS端口，保持路径/参数和健康会话不切线。匿名IP隔离不是账户认证；下行资源仍随用户数增加，未完成生产容量压测，不把100个本地假上游客户端测试称为100用户真实容量通过。

两台部署前检查现有服务和端口，备用443已有业务，因此用独立项目域名8443；既有站点保留。安装独立Python环境，备份并验证Caddy后短重启激活，未升级Caddy。各自Python3.11上19项测试通过。公网`dual-gateway-live.json`两台各2客户端实收BTC，1频道共享，退出后上游释放；2021年4h/1d OI分别6点/1点并数值一致。主节点初次备份tar因目录时间变化失败、重试SSH曾超时，均发生在切换路由前；改外部备份目录后部署通过。

最新Symbols58、Data74、后端19项通过；device build-for-testing及`make strict`通过。iPad右滑删除1/1通过（19.944秒），批量选择删除1/1通过（29.469秒），分别见`favorites-delete-final.log`、`favorites-batch-delete-final.log`。原版AICoin核心真机拖拽/惯性/双指/手动Y曲线及EMA参数页仍未完成原版对照，不因本App测试通过而宣称其行为1:1。

补充清理：离开订阅范围的搜索品种报价及时清除，仍订阅品种保持实时值；`retainQuotes`回归验证只清报价，不清收藏。正式存档最后只读检查仍23品种；用户后来调整了SOXL位置及当前美股分类，尊重该最新人工排序，不用测试旧快照覆盖。


## 最后功能：轻微边界回位与默认贴右

代码提交`310e8c1`。`AICoinBehavior.rightInset=0`；`ViewMath.dragging`在左右任一越界端使用同一有上限阻尼映射，历史中途返回正常视窗；`ChartView`抬手先判断越界，再选择回位或历史惯性。`ViewTransition.rebound`单调收敛至对应夹取边界，减少动效立即归位；`ChartProxy/MainScreen`从自选进入同品种也执行最新定位。没有把所有历史缩放固定在右侧。

2026-09-15 03:36–03:39原版iPhone镜像SNDK4h观察已写研究报告§14：默认列尾贴右、向右历史、向左越界临时空白/松手回位、重进恢复最新。最新端属于原版实测；最早端对称属于用户要求；32pt/10%和320ms参数属于实现取舍，精确原版曲线未拟合。

最终真机`user-edge-final` **2/2通过**：报价用例42.162秒、边界/历史/重进用例21.545秒。冷首帧507ms，后台恢复237ms；切页保持session1且23行实时报价。进入、最新端释放、历史中途左右拖后保留历史、同品种重进贴右均通过。两端的位移上限、方向、各自回位目标和不改span由Core参数化测试覆盖；没有声称真机遍历到交易所最早历史并完成实测。设备在测试全部结束后由用户断开，后续不再要求真机。

最终Core193、Data74、Symbols58、后端19项通过；`make strict`和最终设备构建通过。截图`final-edge.png`、`final-foreground.png`及源码/二进制哈希在`final-validation.json`。真机二进制含用户另行修改的Hntcoin显示名/图标，提交保留但不混入该外部品牌修改；差异不影响上述行为。两台共享行情服务均active，空闲内存约29MB/节点，详见`dual-gateway-resource-check.json`。

兼容性原计划明天进行，后按用户最新要求改为本轮使用模拟器完成；新矩阵结果见compatibility的release记录，旧121项不代表当前最终二进制。后续不再做真机测试。


## 追加：配色、报价数据完整性与性能

原基础包13台模拟器×16项完成，共208项，17系列17/17Pro/17ProMax/17e均包括在内；不能据此推断新增代码真机通过。

最新新增实现与根因见 [配色与数据审查](../../护眼配色与数据完整性.md)：顶栏只读共享最新ticker；全事件选择标识隔离A→B→A的迟到响应；K线同根内事件去重及REST/WS实时末根保护；OI响应品种检查和取消；七指标与全量计算核对。切换清空旧数据时只保存视野参数，换周期用原绘图区宽度计算根宽，不把整个容器宽度当绘图区。

用户后续要求的护眼仅做颜色、对比度与自动明暗配色，不增加休息提醒、大字或静止显示。另实现左上角全部收藏快捷列表和交易所板块筛选；CPU采样指向的搜索页键盘/菜单冲突也在此次回归中处理。本轮新增功能真机按用户要求留待明天，不覆盖原有23个正式收藏及人工顺序。

### 2026-09-15 分类栏与实时报价合并

自选顶部直接放用户分类，去掉双标题和页内搜索；原生宽度不足的分类进入“…”菜单，当前分类保持可见，管理/添加/移动入口保留。QuoteBook 分开维护成交编号与滚动统计快照，复用当前图实时 K 线流的有效成交版本以免退回 ticker 的两秒刷新节奏；REST/缓存蜡烛不进入报价。新回归证据与限制见 `docs/acceptance/护眼配色与数据完整性.md`。

### 2026-09-15 中午：新配色、报价隔离及分类栏真机验收

iPhone 16 Pro / iOS 26.6.1 完成 19 个不同用例，均有通过记录；两次分类测试被系统通知遮挡，保留失败证据，测试侧收起横幅后通过。补齐本项目历史横拖、双指缩放、手动 Y 功能实机证据，仍不等于原版 AICoin 精确曲线已确认。实际 App 未改代码；正式收藏存档保留并正常启动。结果见 [数据与配色验收](../../护眼配色与数据完整性.md) 和 `../../eye-colors/physical-final-summary.json`。
