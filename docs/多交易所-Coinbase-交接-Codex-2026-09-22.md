# 看盘 · 多交易所抽象 + Coinbase 现货接入（交接 Codex 第二线程，2026-09-22）

给 Codex（`codex exec`，`gpt-6-astra`，`xhigh`）。**这是第二条 Codex 线程**，和第一条（`docs/待办交接-Codex-2026-09-22.md`，做 P1→P4）同时进行。
你在独立工作树 `/Users/mdd/zhk/kanpan-coinbase`、分支 `multi-exchange` 上干活；第一条线程在主工作树直接推 `main`。协作规则见 §6。

用户原话（2026-09-22）：「把 coinbase 接入，把多交易所功能抽出来，不要散落代码，因为后续还需要接入其它。」
这条推翻了 `docs/不做清单.md` 里原来的「多交易所抽象 / Coinbase 不做」（已从清单删除）。**OKX 持仓量副图仍然不做**；OKX 只是币安永续在网关线路上的服务端替身，不是用户可见的交易所。

设计底稿：`git show 59c57fd:docs/多交易所行情接入方案-Coinbase现货-2026-09-17.md`（P0.5 已把它从工作树删除，git 里还在）。底稿的架构结论照用；它「需要你拍板的事」四条我已经拍了（§2）。底稿里的路径已过期，**以当前工作树为准**（例如线协议已在 `KanpanNetwork/Sources/KanpanNetwork/{Binance,Route,Transport}/`）。

先读：`docs/不做清单.md` → `AGENTS.md` → `.project-memory/PROJECT.md` → 底稿 → 本文。

---

## 1. 目标（一句话）

三个正交概念——**品种身份 `InstrumentID`（venue/market/symbol）**、**行情提供者 `MarketProvider`**、**线路 Route（直连/网关）**——从币安里拆出来；币安包成第一个 Provider，Coinbase 现货是第二个；以后接第三家 = 新建一个文件夹 + 注册表加一行 + 服务端加一条透传，其它层一个字不改。

「不散落」是硬验收：**`KanpanNetwork` 之外任何源码不得出现 `Binance*` / `Coinbase*` 类型、`fapi.binance` / `coinbase.com` 域名、`USDT` 后缀假设**（现在 `Kanpan/`、`KanpanData/`、`KanpanCore/`、`KanpanChart/`、`KanpanReview/` 里有 18 个文件引用 `Binance`，做完必须归零）。用脚本守住（§4 阶段 2）。

## 2. 已拍板的决定

| 事 | 决定 |
| --- | --- |
| Coinbase 在自选页怎么呈现 | 自选分类条上加一个固定分类 **「Coinbase」**（在「美股」之后，`FavoriteCategory` 加一个 case，其余分类不动）。行内品种名显示 `BTC/USD`，徽章按 base 币复用现有 57 个手绘记号（`BTC` 两家所同一个记号）。搜索结果里 Coinbase 品种行右侧一个灰色小字 `Coinbase`，币安品种不加标 |
| 计价 | 只收 **USD** 计价、`status == online`、`product_type == SPOT`、`view_only == false` 的对；`BTC-USDC` 这类不收 |
| 线路 | 直连 + 网关**都做**。Coinbase 的网关通道放在 **Rust `Backend/kanpan-api`**（`market_meta.rs` 那一族），不放 Python `kanpan-gateway`：REST `/market/v1/*?source=coinbase` **原样透传**（不翻成币安格式），WS `/market/coinbase/stream` 一条上游共享给所有手机、帧原样转发。「行情线路」设置仍是一个全局开关，对所有交易所生效，无自动切换 |
| OKX | 从 venue 概念退场。服务端 `review_domain.rs:5-10`、`search.rs` 的白名单改成 `binance \| coinbase`，不再把 venue 归一成 binance；`review_worker.rs:80` 的 okx 分支删除 |
| 直连可达性 | Mac 上实测 `api.coinbase.com` 200 / 0.6s、candles 200 / 0.3s（2026-09-22）。手机上真机不可用（无 Apple ID / 证书），模拟器验证直连；网关通道保证国内可用 |
| Coinbase 品种的六格 | 仓 / 费率 / 结算 三格 `—`（现货没有），市值按 base 币走现有总供应量表（表按 base 币键，`BTC` 复用），额 = 24h base 成交量 × 现价（近似，Coinbase 公开接口不给 quote 成交额），振幅 = 24h 高低（`ticker` 频道 `high_24_h / low_24_h`）。头部布局（刚定稿的两行价格块 + 六格）不动 |
| 板块页 | 只有币安参与（分类表是币安的）。Coinbase 品种不进板块，不报错 |
| 提醒 / 画线 / 复盘 / 同步 | 全部按 `InstrumentID.key` 工作，Coinbase 品种一样能画线、设提醒、做复盘、跨设备同步。复盘服务端校验（`review_worker.rs`）要能取 Coinbase K 线，不能对 coinbase 一律 `needs_verification` |
| 小数位 | `SymbolInfo.tickSize` 取 Coinbase `price_increment`（`quote_increment` 是下单最小额，不是它）；展示位数走刚统一的 `priceDecimals` |
| 周期 | 用户的 14 档全部可用：Coinbase 原生 9 档，3m 由 1m 聚、12h 由 6h 聚、1w/1M 由 1d 聚、1y 由 1M 聚（`Aggregator.bucket` + `MarketFeed` 现有 `sourceComposer` 路径）。末根实时：只有 5m 有 `candles` 频道，其它周期用 `market_trades` 在客户端拼末根 + `reconcileMs` REST 校正（`MarketFeed` 已有 `.trade` 分支） |

## 3. 模块边界（照这个放，不许散落）

```
KanpanCore/Sources/KanpanCore/Model/InstrumentID.swift        身份：venue/market/symbol，key = "venue/market/symbol"（与账号同步 id 同格式，PersonalSyncCodec.swift:109/159 已在写这个格式）
KanpanNetwork/Sources/KanpanNetwork/Provider/
  MarketProvider.swift          协议（instruments / klines / ticker / tickers / stream / openInterest 默认 unsupported）
  ProviderCapabilities.swift    nativeIntervals / maxPage / liveKlineIntervals / hasOpenInterest / hasMarkPrice / hasFunding / quoteAssets
  ProviderEvent.swift           .kline / .trade / .ticker / .status / .connected
  RouteResolver.swift           (policy, venue) → HTTPTransport + WSSocketFactory 指向直连域名或网关通道
  VenueRegistry.swift           唯一的「有哪些交易所」清单：venue id、中文/英文显示名、Provider 工厂、分类落点。接第三家只在这里加一行
KanpanNetwork/Sources/KanpanNetwork/Binance/                  现有文件原地不动 + BinanceProvider.swift 包一层
KanpanNetwork/Sources/KanpanNetwork/Coinbase/                 CoinbaseProvider / CoinbaseDTO / CoinbaseEndpoints / CoinbaseWS / CoinbaseRateLimiter
```

- `MarketFeed`、`RoutedMarketFeed`、`QuoteBook`、`MarketModel`、`SymbolCatalog`、`OISource`、`ReviewChartBridge` 只跟 `MarketProvider` + `ProviderCapabilities` 说话；`source == .binance` 之类分支全部换成能力位。
- `MarketSource`（`Route/MarketSource.swift:4`，`binance | okx`）与 `MarketRoutePolicy.source`（`:23`）删除：线路只剩 `.direct / .gateway`，「网关下币安走 OKX 替身」这件事下沉到 `RouteResolver` 里币安那一支，用户不可见。
- 每家所一份品种表缓存（`SymbolCatalog` 按 venue 分文件），`SeriesStore` 目录 `series/<venue>/<market>/`。
- 服务端同样一处注册：`kanpan-api` 里 `source=` 的分发表加 `coinbase`，透传实现放 `src/venues/coinbase.rs`（新建目录 `src/venues/`，把现有 okx 透传也挪进去 `src/venues/okx.rs`，别留在 `market_meta.rs` 里）。

## 4. 分阶段（每阶段：rebase 到 `origin/main` → 编译 + 四包 `swift test` + `make app-logic-test` + `cargo test --lib` 全绿 → 合进 `main` 并 push → 写报告）

| 阶段 | 内容 | 用户可见 |
| --- | --- | --- |
| 1 | `InstrumentID` 落地：`SymbolInfo.id` 改为 `InstrumentID`；自选 `kanpan.symbols.v1 → v2`（裸符号一律映射到 `binance/usd_m/`）、`DrawStore`、`SeriesStore`、`QuoteBook.raw`、`opens.json`/`quotes.json`、提醒、复盘键全部改 `key`；**迁移测试必写**（旧自选、旧画线、旧提醒、旧缓存一个不丢）；服务端白名单放开 | 无 |
| 2 | `MarketProvider` + `ProviderCapabilities` + `RouteResolver` + `VenueRegistry`；`BinanceProvider` 包现有代码；上面列的消费方改依赖协议；`Tools/check-venue-isolation.sh`（`KanpanNetwork/Sources/KanpanNetwork/{Binance,Coinbase}` 与 `VenueRegistry.swift` 之外 grep `Binance\|Coinbase\|fapi\.binance\|coinbase\.com\|hasSuffix("USDT")` 命中即失败）接进 `make app-logic-test` | 无。行为零变化，用现有测试兜底；`kanpan-network-changes-must-not-regress-speed`：冷启动首屏与 WS 首帧时间改前改后各量一次，写进报告，不许变慢 |
| 3 | `CoinbaseProvider`（REST 分页 350/页、秒→毫秒、字符串→Double、升序；WS `market_trades` + `ticker` / `ticker_batch`，5m 加 `candles`；聚合与末根拼装；限速器按 10 rps/IP 保守值）；`kanpan-api` 透传 + WS hub + 白名单 + 复盘 worker 取 Coinbase K 线；部署（备份 → rsync → `cargo build --release` → `ops/install.py` → `systemctl restart` → 只读验证） | 能搜到、能加自选、能看图、自选页有报价 |
| 4 | UI：自选分类「Coinbase」、行内 `BTC/USD`、搜索所标、六格按能力位 `—`、周期条与副图按能力位（OI 副图对 Coinbase 隐藏不报错）、板块页排除 | 完整体验 |
| 5 | 模拟器回归：币安品种（自选、画线、提醒、复盘、同步往返）迁移后无损；Coinbase `BTC-USD` 冷启动逐帧、1m/1h/1w 三档、切线路（直连 ↔ 网关）、断网重连；写 `docs/多交易所-接入指南.md`（**现行规格文档**：接第三家要新建哪几个文件、注册表加哪一行、服务端加哪一条，除此之外不许改别处——这份指南就是「不散落」的验收书） | — |

报告：`docs/acceptance/多交易所-2026-09-22/阶段<n>.md`（做了什么、假设、命令与退出码、截图、提交号、后端部署与只读验证结果）。全部做完再写 `总结.md`，并更新 `.project-memory/PROJECT.md`。

## 5. 硬规矩（与第一条线程相同，另加两条）

`docs/待办交接-Codex-2026-09-22.md` §0 的 11 条全部适用（不做清单、不问、只提交自己的文件、每提交可编译、只跑受影响 UI 用例、无真机只用模拟器、后端改完就部署、中文标签、不加算法选项、画布上不浮控件、跨端功能端到端）。另外：

- **不要顺手做第一条线程的活**（多空比/主动买卖比/基差、盘口、P2–P4 全部）。你碰到的 `KanpanNetwork/Binance/*` 里它正在改的东西（`EndpointQuota.futuresData`、`ExternalSeries`）原样保留、包进 `BinanceProvider`。
- 自选页是用户自己定稿的设计：只加一个分类 case，视觉一个像素不改。

## 6. 与第一条线程的协作

- 工作树：`git worktree add /Users/mdd/zhk/kanpan-coinbase -b multi-exchange origin/main`（我已建好）。所有工作在这里做；**不要进 `/Users/mdd/zhk/kanpan` 主工作树**。
- 每个阶段开始前 `git fetch && git rebase origin/main`；阶段做完、全绿后 `git checkout main && git merge --ff-only multi-exchange && git push`（在你的工作树里用 `git push origin multi-exchange:main` 也行），然后回到分支继续。冲突由你解决，**永远不许 force-push main**。
- 阶段 1 动的文件最多（身份加宽），尽快合进 main 缩短分叉；不要把阶段 1–2 攒在分支上几个小时。
- 第一条线程提交信息里带「P1/P2/P3/P4」；你的带「多交易所 阶段 n」。

## 7. Claude 的验收

每个阶段合进 main 后我会独立：阶段 1 用旧数据目录跑迁移；阶段 2 跑隔离脚本 + 量首屏；阶段 3–4 在 iPhone 16 Pro 模拟器上搜 `BTC-USD` 加自选、看 1m/1h/1w、设一条提醒、画一条线、切线路、看六格；阶段 5 抽查报告与线上只读验证。不对就打回返工。
