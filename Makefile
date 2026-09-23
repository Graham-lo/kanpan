# 看盘 · 构建与取证入口（任务书 §13 M0）
# 约定：所有命令从仓库根跑；证据落在 docs/acceptance/。

# ---------------------------------------------------------------- 机器资源守门（2026-09-23）
# 所有重编译一律经 scripts/machine-guard.sh run：机器上同时最多 2 个，超了就排队；
# 一律 nice 10，让 Surge / ChatGPT / Claude 保住前台。规则见 AGENTS.md「机器资源纪律」。
GUARD      := $(CURDIR)/scripts/machine-guard.sh run
XCODEBUILD := $(GUARD) xcodebuild
SWIFT      := $(GUARD) swift

WORKSPACE  := Kanpan.xcworkspace
SCHEME     := Kanpan
CORE       := KanpanCore
CHART      := KanpanChart
RUNTIME    := iOS
SHOTS      := docs/acceptance/shots

# 重点维护的两台 16 Pro / 17 Pro Max（2026-09-23 用户定的：不再维护 13 台矩阵，机器顶不住；兼容也只认这两台 + iOS 26.6 以上与 27）；与 Tools/ui-test.sh 保持一致。
DEVICES := \
	"iPhone 16 Pro" \
	"iPhone 17 Pro Max"

# 单台机型时用：make snap DEVICE="iPhone 16 Pro"
DEVICE ?= iPhone 16 Pro

.PHONY: help doctor venue-isolation core-test network-test data-test chart-build chart-test \
	symbols-test settings-test sector-test scan-test alerts-test diag-test deeplink-test account-codec-test \
	diag-ios-test main-ios-test app-logic-test sync-contract backend-test account-test review-test test \
	test-release core-test-release network-test-release data-test-release account-test-release \
	app-logic-test-release chart-test-release main-ios-test-release review-test-release diag-ios-test-release \
	strict evidence fixtures feed app-test ui-test ui-test-one build device-release install-release \
	archive ipa upload snap screenshots devices boot shutdown clean

help:
	@echo "core-test    跑 KanpanCore 单测（不需要 Xcode GUI，CLT 也能跑）"
	@echo "network-test 跑 KanpanNetwork 单测（HTTP/WS 接口、币安客户端、线路与网关竞速）"
	@echo "data-test    跑 KanpanData 单测（全离线：假 transport / 假 socket / 假时钟）"
	@echo "chart-build  编 KanpanChart（UIKit，必须走 xcodebuild）"
	@echo "chart-test   跑 KanpanChart 单测（需要一台模拟器）"
	@echo "account-test 跑 KanpanAccount 单测（登录、退登、被顶下线、同步编解码）"
	@echo "review-test  跑 KanpanReview 单测（需要一台模拟器）"
	@echo "app-logic-test  跑 app 侧壳包（自选 / 设置 / 板块 / 诊断 / 同步字段 / 链接 / 扫图 / 提醒）+ 交易所隔离检查"
	@echo "diag-ios-test   帧探针那几条（需要一台模拟器，不挂进 test）"
	@echo "main-ios-test   主屏生命周期用例（需要一台模拟器）"
	@echo "backend-test 跑 kanpan-api 的库内单测（cargo test --lib，不需要 Postgres）"
	@echo "test         core / network / data / app-logic / chart / main-ios / account / review 全跑"
	@echo "test-release 同一套按 Release 配置再跑一遍（各目标加 -release 后缀可单跑）"
	@echo "strict       全部包按 Swift 6 严格并发 + 警告即错误编一遍（A2.13）"
	@echo "evidence     出 M3 全套取证产物到 docs/acceptance/M3/（A3.1–A3.10）"
	@echo "fixtures     从原型重新导一次定版 fixture（需要 node，产物已入库；配色那两份不重导）"
	@echo "feed         编数据层取证工具 kanpan-feed（Release）"
	@echo "sync-contract 从 PrefsFieldPlan.table 重新生成 iOS↔Rust 的 settings 字段契约（Backend/kanpan-api/contract/settings-fields.json）"
	@echo "app-test     app-logic-test + 编一遍 app（app 自己没有单元测试 target）"
	@echo "build        在模拟器上编 app（DEVICE=\"iPhone 16 Pro\"）"
	@echo "ui-test      A8.4：两台重点机型跑同一套 XCUITest 用例，逐台记结果"
	@echo "ui-test-one  只跑一台（DEVICE=\"iPhone 16 Pro\"）"
	@echo "device-release  编真机 Release 包（generic/platform=iOS，签名走 -allowProvisioningUpdates）"
	@echo "install-release 把 Release 包装到第一台 connected 真机"
	@echo "archive      归档 Release 真机包到 DerivedData-archive/Kanpan-<构建号>.xcarchive（TestFlight 第一步）"
	@echo "             构建号每次上传必须递增，也用来分开历史归档和 dSYM：make archive BUILD=7；不传 BUILD 出的是 -dev 那份"
	@echo "ipa          把同一构建号的归档导成可上传的 ipa：make ipa BUILD=7（Team ID 可覆盖：TEAM_ID=XXXX）"
	@echo "upload       用 App Store Connect API Key 传同一构建号的 ipa：make upload BUILD=7（需 ASC_KEY_ID / ASC_ISSUER_ID）"
	@echo "             传成功后自动往 docs/testflight-uploads.md 追加一行，归档与 dSYM 按它算 90 天保留期"
	@echo "snap         在单台模拟器上装 app 并截一张图（DEVICE=\"iPhone 16 Pro\"，RELEASE=1 走 Release 包）"
	@echo "screenshots  两台重点机型全跑一遍，出 docs/acceptance/shots/"
	@echo "devices      备齐两台重点模拟器（缺的自动 create）"
	@echo "boot         把两台全 boot 起来（一般不用；一次开一台）"
	@echo "shutdown     关掉所有模拟器"
	@echo "doctor       打印环境信息，对 A0.1 的验收"
	@echo "venue-isolation 交易所隔离检查（交易所名只许出现在自己的提供者目录与注册表里）"
	@echo "clean        删全部可再生产物（DerivedData、.build、cargo target、/tmp 构建目录），即 scripts/machine-guard.sh clean"

# ---------------------------------------------------------------- A0.1 环境
doctor:
	@echo "== xcodebuild =="        && xcodebuild -version
	@echo "\n== 开发者目录 =="      && xcode-select -p
	@echo "\n== 模拟器运行时 =="    && xcrun simctl list runtimes
	@echo "\n== swift =="           && swift --version

# ---------------------------------------------------------------- A0.4 Core
# 刻意不经过 xcodebuild：Core 不 import UIKit，纯 SwiftPM 就能跑。
# 验收命令：DEVELOPER_DIR=/Library/Developer/CommandLineTools make core-test
# CLT 单独发行时，SwiftPM 不会自动把 swift-testing 的框架和 lib_TestingInterop.dylib
# 加进搜索路径（Xcode 工具链会）。两条 -F / 两条 rpath 补上，CLT 下就能跑 Testing。
CLT := /Library/Developer/CommandLineTools
CLT_TESTING_FLAGS := \
	-Xswiftc -F -Xswiftc $(CLT)/Library/Developer/Frameworks \
	-Xlinker -F -Xlinker $(CLT)/Library/Developer/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT)/Library/Developer/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT)/Library/Developer/usr/lib

# DEVELOPER_DIR 指向 CLT 时才加那串 flag，指向 Xcode 时保持裸 swift test
ifeq ($(DEVELOPER_DIR),$(CLT))
	CORE_TEST_FLAGS := $(CLT_TESTING_FLAGS)
else
	CORE_TEST_FLAGS :=
endif

core-test:
	cd $(CORE) && $(SWIFT) test $(CORE_TEST_FLAGS)

# ---------------------------------------------------------------- 网络层
# 怎么连到交易所：HTTP / WS 最小接口、币安 REST / WS 客户端与限流、行情线路（直连 / 网关）、
# 网关竞速与冷却。KanpanData 依赖它但不再转出去（审查 18a）：用到网络层名字的文件自己
# `import KanpanNetwork`，app 工程也显式链它。
NETWORK := KanpanNetwork

network-test:
	cd $(NETWORK) && $(SWIFT) test $(CORE_TEST_FLAGS)

# ---------------------------------------------------------------- A2 Data
DATA := KanpanData

data-test:
	cd $(DATA) && $(SWIFT) test $(CORE_TEST_FLAGS)

# 绘制层 import UIKit，裸 swift build 会拿 macOS sysroot 编（-sdk 那条 flag 会被吞掉），
# 所以这里必须走 xcodebuild 指一个 iOS Simulator destination。
chart-build:
	cd $(CHART) && $(XCODEBUILD) -scheme KanpanChart \
		-destination 'generic/platform=iOS Simulator' \
		-derivedDataPath .xcbuild build

chart-test:
	cd $(CHART) && $(XCODEBUILD) test -scheme KanpanChart \
		-destination 'platform=iOS Simulator,name=$(DEVICE)' \
		-derivedDataPath .xcbuild

# ---------------------------------------------------------------- app 侧逻辑包
# app 工程里没有单元测试 target（`Kanpan.xcscheme` 的 test action 只挂 KanpanUITests），
# 补一个要改 project.pbxproj。改用 SwiftPM 壳包：Sources/ 下是指向 Kanpan/Kanpan/<模块>/ 的符号链接，
# 一份代码两处编译，不会漂移。新增模块照 Symbols 的样子加一行。
SYMBOLS := Kanpan/Symbols

SETTINGS := Kanpan/Settings

symbols-test:
	cd $(SYMBOLS) && $(SWIFT) test $(CORE_TEST_FLAGS)

settings-test:
	cd $(SETTINGS) && $(SWIFT) test $(CORE_TEST_FLAGS)

# 板块页那两件不吃 SwiftUI 的：取数（`SectorFeed`：换线路清行情、连着失败就丢）
# 和品种列表的值与文案（`SectorRows`：小数位听品种表的、缺数不许伪排序）。
SECTOR := Kanpan/Sector

sector-test:
	cd $(SECTOR) && $(SWIFT) test $(CORE_TEST_FLAGS)

# 连续扫图与「看细节」的纯算术（§10.1）：冻结下来的那张名单怎么走一只（`ScanList`）、
# 「看细节」该进哪一档、视野铺多宽、切回大周期时回到哪儿（`DetailZoom`）。
# 手势与按钮吃 SwiftUI，那部分的证据走模拟器。
SCAN := Kanpan/Scan

scan-test:
	cd $(SCAN) && $(SWIFT) test $(CORE_TEST_FLAGS)

# 提醒模块里不吃 SwiftUI / UIKit 的那两件：存档与对账（线被挪了按同一个 id 重算、
# 线被删了提醒跟着删）、以及那份存档的管家。纯逻辑（几何摊平、触发判定）在
# KanpanCore/Alerts，跑 core-test。
ALERTS := Kanpan/Alerts

alerts-test:
	cd $(ALERTS) && $(SWIFT) test $(CORE_TEST_FLAGS)

DIAG := Kanpan/Diagnostics

diag-test:
	cd $(DIAG) && $(SWIFT) test $(CORE_TEST_FLAGS)

# 外面进来的那条链接长什么样（`DeepLink`）。通知、桌面快捷入口、共享链接三边
# 照着同一份形态拼串，解析只有这一处，所以它的契约要有人钉着。零依赖、不吃
# SwiftUI，mac 上直接跑。
DEEPLINK := Kanpan/DeepLink

deeplink-test:
	cd $(DEEPLINK) && $(SWIFT) test $(CORE_TEST_FLAGS)

# 「这个客户端替哪些字段说话」那张表（`PersonalSyncCodec.ownedKeys`）的跑道。
# 它吃的 Prefs / SymbolPrefs 都是 internal 的，所以这个壳包把设置模型、SymbolPrefs
# 和 codec 链进同一个模块编——就是 app 靶子里它们本来的样子。
ACCOUNT_CODEC := Kanpan/AccountCodec

account-codec-test:
	cd $(ACCOUNT_CODEC) && $(SWIFT) test $(CORE_TEST_FLAGS)

# 帧探针那几条只有真跑在 iOS 上才走得到（CADisplayLink / CFRunLoopObserver 在 mac
# 上编得过但量不到东西），所以单独一个 target，要起模拟器，故意不挂进 `test`。
# 真机取证前必须跑一遍。
diag-ios-test:
	cd $(DIAG) && $(XCODEBUILD) test -scheme KanpanDiagnostics \
	  -destination 'platform=iOS Simulator,name=$(DEVICE)' -derivedDataPath .xcbuild

# 主屏那几条生命周期用例（宿主销毁收摊、合批缓冲换人就丢、转屏复位只认最后一次、
# 后台额度必须还）离不开真的 UIKit：UIApplication 的后台任务、CADisplayLink、
# 窗口挂接在 mac 上根本没有，`swift test` 连 import UIKit 都过不去，所以单独起模拟器跑。
#
# 但它**挂在 `test` 里**（审查复核项 8）：顶栏纯显示（A-T20）、报价簿（B-T10）这些
# 规则只有这一套能守，不挂进去就等于没人跑。走 xcodebuild 不是例外——`chart-test`
# 一直是这么跑的，`test` 里本来就有它。
MAIN := Kanpan/KanpanTests

main-ios-test:
	cd $(MAIN) && $(XCODEBUILD) test -scheme KanpanMain \
	  -destination 'platform=iOS Simulator,name=$(DEVICE)' -derivedDataPath .xcbuild

app-logic-test: venue-isolation symbols-test sector-test settings-test diag-test account-codec-test deeplink-test scan-test alerts-test

# 交易所隔离守卫：某家交易所的名字只许出现在它自己的提供者目录与 VenueRegistry 里。
venue-isolation:
	@Tools/check-venue-isolation.sh

# ---------------------------------------------------------------- 跨语言契约
# 「客户端会发哪些 settings 键 / 服务端认哪些」这件事，母表只有一张：
# Kanpan/Kanpan/Settings/Model/PrefsFieldPlan.swift 的 `PrefsFieldPlan.table`。
# 这条命令把它导成下面那个 JSON，iOS 与 Rust 两边的测试都读那一份对账，谁也不再手抄
# （手抄三份的代价见提交 a161bb0：服务端少认十九个字段，那个账号从此同步不上任何东西）。
#
#   加 / 删一个同步字段：改 table → make sync-contract → 两边测试自动告诉你还差什么。
#
# 走的是 settings 那条测试的「写文件」模式（KANPAN_WRITE_SYNC_CONTRACT=1），
# 不另起一个可执行：生成器和对账用的是同一段代码，不可能各说各话。
SYNC_CONTRACT := Backend/kanpan-api/contract/settings-fields.json

sync-contract:
	cd $(SETTINGS) && KANPAN_WRITE_SYNC_CONTRACT=1 $(SWIFT) test $(CORE_TEST_FLAGS) \
	  --filter theContractFileIsTheOneListBothSidesRead
	@echo "→ $(SYNC_CONTRACT) 已按 PrefsFieldPlan.table 重新生成；跑 make app-logic-test 与 (cd Backend/kanpan-api && cargo test --lib) 对账"
	@$(MAKE) --no-print-directory backend-test

# ---------------------------------------------------------------- 后端单测
# kanpan-api 的库内单测：不需要 Postgres，几秒跑完（要库的集成测试走
# Backend/kanpan-api/ops/test.py）。sync-contract 重新生成契约之后接着跑它——Rust 那一半
# 的对账就在这些单测里，不再靠人记得去手敲。cargo 在 rustup 的 keg 里、不在默认 PATH 上。
backend-test:
	cd Backend/kanpan-api && PATH="$$PATH:/opt/homebrew/opt/rustup/bin" $(GUARD) cargo test --lib

# ---------------------------------------------------------------- 账号与复盘
# 审查 C-05：这两个包过去一个都不在 `test` 里。也就是说「make test 全绿」跟
# 账号登录、退登、被顶下线、复盘评定这些东西改没改坏毫无关系——那正是报告里
# 「全测目标没有选中账号与复盘」的原话。现在都挂进去。
ACCOUNT := KanpanAccount

account-test:
	cd $(ACCOUNT) && $(SWIFT) test $(CORE_TEST_FLAGS)

# 复盘包在 mac 上 `swift test` 编不过：`ReviewUI` 吃 SwiftUI + UIKit，裸 swift build
# 会拿 macOS sysroot 去编。所以照 `main-ios-test` / `chart-test` 的老规矩起模拟器，
# 用 xcodebuild 指一个 iOS Simulator destination。
REVIEW := KanpanReview

review-test:
	cd $(REVIEW) && $(XCODEBUILD) test -scheme KanpanReview \
	  -destination 'platform=iOS Simulator,name=$(DEVICE)' -derivedDataPath .xcbuild

test: core-test network-test data-test app-logic-test chart-test main-ios-test account-test review-test

# ---------------------------------------------------------------- Release 回归
# 审查 C-05 的另一半：`Kanpan.xcscheme` 的 TestAction 是 Debug，上面那条 `test` 也全是
# Debug。于是「测试全绿」证明的只是 Debug 那个二进制，而用户手上装的是 Release。
#
# **`ENABLE_TESTABILITY=YES` 不能省。** xcodebuild 在 Release 配置下把它默认设成 NO，
# 没有它，测试目标里的 `@testable import` 一律编不过（`module was not compiled for
# testing`）。SwiftPM 的 `swift test -c release` 自己会带上这个设置，所以只有走
# xcodebuild 的那几个包需要显式写。
#
# **Debug 有、Release 没有的用例，必须单独列出来、不许并进 Release 的通过数**（报告原话）。
# 清完之后，全仓只剩这三处：
#   Kanpan/Symbols/Tests/KanpanSymbolsTests/SymbolPrefsSeedIsolationTests.swift —— 4 条。
#   它钉的是 `SymbolPrefsStore.testSeed`，而那段种子脚手架按 A-07 / C-02 只存在于 DEBUG，
#   Release 包里连代码都不该有。这 4 条在 Release 下会「为了错的理由变绿」，所以留在 DEBUG。
#   KanpanChart/Tests/KanpanChartTests/CrosshairWorkTests.swift —— 3 条（共 6 条）。
#   那 3 条读 `ChartWorkCounter` 的重算次数，而那份计数趴在渲染热路径上、只在 DEBUG 下
#   有存储，Release 里恒为 0。同文件另外 3 条验的是产品行为，两种配置都跑。
#   Kanpan/Alerts/Tests/KanpanAlertsTests/P31AlertKindsTests.swift —— 1 条。
#   它调的是 `WatchMoveMonitor.injectTestMove`（UI 用例的注入口），那个口子只在 DEBUG 里有。
# KanpanAccount 原来那 16 条（ClientHardening 8 / DeviceKind 5 / SessionLifecycle 全套）
# 已经在本轮改成白名单主机 + 自带 URLProtocol，Debug / Release 两边都是 60 条，不再有差集。
test-release: core-test-release network-test-release data-test-release app-logic-test-release \
              account-test-release chart-test-release main-ios-test-release review-test-release

core-test-release:
	cd $(CORE) && $(SWIFT) test -c release $(CORE_TEST_FLAGS)
network-test-release:
	cd $(NETWORK) && $(SWIFT) test -c release $(CORE_TEST_FLAGS)
data-test-release:
	cd $(DATA) && $(SWIFT) test -c release $(CORE_TEST_FLAGS)
account-test-release:
	cd $(ACCOUNT) && $(SWIFT) test -c release $(CORE_TEST_FLAGS)
# 和 Debug 档的 app-logic-test 同一份包清单，少一个就等于那个包的 Release 没人测。
app-logic-test-release: venue-isolation
	cd $(SYMBOLS) && $(SWIFT) test -c release $(CORE_TEST_FLAGS)
	cd $(SETTINGS) && $(SWIFT) test -c release $(CORE_TEST_FLAGS)
	cd $(SECTOR) && $(SWIFT) test -c release $(CORE_TEST_FLAGS)
	cd $(DIAG) && $(SWIFT) test -c release $(CORE_TEST_FLAGS)
	cd $(ACCOUNT_CODEC) && $(SWIFT) test -c release $(CORE_TEST_FLAGS)
	cd $(DEEPLINK) && $(SWIFT) test -c release $(CORE_TEST_FLAGS)
	cd $(SCAN) && $(SWIFT) test -c release $(CORE_TEST_FLAGS)
	cd $(ALERTS) && $(SWIFT) test -c release $(CORE_TEST_FLAGS)
chart-test-release:
	cd $(CHART) && $(XCODEBUILD) test -scheme KanpanChart \
	  -destination 'platform=iOS Simulator,name=$(DEVICE)' -derivedDataPath .xcbuild-release \
	  -configuration Release ENABLE_TESTABILITY=YES
main-ios-test-release:
	cd $(MAIN) && $(XCODEBUILD) test -scheme KanpanMain \
	  -destination 'platform=iOS Simulator,name=$(DEVICE)' -derivedDataPath .xcbuild-release \
	  -configuration Release ENABLE_TESTABILITY=YES
review-test-release:
	cd $(REVIEW) && $(XCODEBUILD) test -scheme KanpanReview \
	  -destination 'platform=iOS Simulator,name=$(DEVICE)' -derivedDataPath .xcbuild-release \
	  -configuration Release ENABLE_TESTABILITY=YES

# 帧探针那一套同样只在模拟器上成立，Release 下也得能跑（同样要 ENABLE_TESTABILITY=YES）。
diag-ios-test-release:
	cd $(DIAG) && $(XCODEBUILD) test -scheme KanpanDiagnostics \
	  -destination 'platform=iOS Simulator,name=$(DEVICE)' -derivedDataPath .xcbuild-release \
	  -configuration Release ENABLE_TESTABILITY=YES

# A2.13：零警告零错误。警告即错误，谁也别想蒙混过去。
# 覆盖全部包：五个库包、app 侧八个 mac 能编的壳包，外加三个只能在 iOS 上编的
# （KanpanChart、KanpanReview、主屏壳包 KanpanMain）。后三个走 xcodebuild，警告即错误
# 由各自 Package.swift 认 `KANPAN_STRICT=<包名>` 打开（原因见 KanpanChart/Package.swift 顶上）。
STRICT_FLAGS := -Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete
STRICT_MAC_PACKAGES := $(CORE) $(NETWORK) $(DATA) $(ACCOUNT) \
	$(SYMBOLS) $(SETTINGS) $(SECTOR) $(SCAN) $(ALERTS) $(DIAG) $(DEEPLINK) $(ACCOUNT_CODEC)

strict:
	@for p in $(STRICT_MAC_PACKAGES); do \
		echo "→ strict $$p"; \
		(cd $$p && $(SWIFT) build $(STRICT_FLAGS)) || exit 1; \
	done
	cd $(CHART) && KANPAN_STRICT=KanpanChart $(XCODEBUILD) -scheme KanpanChart \
		-destination 'generic/platform=iOS Simulator' -derivedDataPath .xcbuild-strict build
	cd $(REVIEW) && KANPAN_STRICT=KanpanReview $(XCODEBUILD) -scheme KanpanReview \
		-destination 'generic/platform=iOS Simulator' -derivedDataPath .xcbuild-strict build
	cd $(MAIN) && KANPAN_STRICT=KanpanMain $(XCODEBUILD) -scheme KanpanMain \
		-destination 'generic/platform=iOS Simulator' -derivedDataPath .xcbuild-strict build

# ---------------------------------------------------------------- §12 M3 取证
# 绘制层的证据只能在模拟器里出（UIKit），所以取证器就是测试 target 里的三个 suite：
#   M3 取证渲染 / A3.2 几何量化 / A3.3 颜色取样
# 落盘开关是 docs/acceptance/M3/.render 标记文件（脚本建、跑完删）；没有它
# chart-test 照样跑断言但一个字节都不落盘。
evidence:
	@bash Tools/render-evidence.sh "$(DEVICE)"

# fixture 是把原型 chart.js / styles.js / data.js 原样跑一遍问出来的黄金值，
# 已入库，只有原型改动时才需要重导。两个脚本各管一个包（KanpanCore 的算法黄金值 /
# KanpanChart 的几何与快照）；配色那两份（styles.json、colors.json）真源已是 Palette.swift，
# 脚本不再覆盖它们。
fixtures:
	node Tools/export-fixtures.mjs
	@ls -l $(CORE)/Tests/KanpanCoreTests/Fixtures
	node Tools/export-chart-fixtures.mjs
	@ls -l $(CHART)/Tests/KanpanChartTests/Fixtures

# 数据层取证工具（§13 M2 的证据都从这儿出）
feed:
	cd $(DATA) && $(SWIFT) build -c release --product kanpan-feed
	@echo "二进制：$(DATA)/.build/release/kanpan-feed"

# ---------------------------------------------------------------- app
# app 工程没有单元测试 target：`Kanpan.xcscheme` 的 test action 只挂 KanpanUITests（那是
# `ui-test` / `ui-test-one`）。app 侧的逻辑一律由上面的壳包覆盖，这里只做编译验证。
app-test: app-logic-test build
	@echo "注意：app 没有单元测试 target，app 侧逻辑走 symbols-test 这类壳包，界面走 ui-test。"

# ---------------------------------------------------------------- A8.4 UI 测试
# KanpanUITests（本工程里唯一的 XCTest target，其余单测一律 swift-testing）。
# 同一套用例在两台重点机型上各跑一遍，逐台记结果：make ui-test
# 单台：make ui-test-one DEVICE="iPhone 17 Pro Max"
UI_DEVICES := $(DEVICES)

ui-test:
	@bash Tools/ui-test.sh

ui-test-one:
	$(XCODEBUILD) test \
		-workspace $(WORKSPACE) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(DEVICE)' \
		-derivedDataPath DerivedData

build:
	$(XCODEBUILD) build \
		-workspace $(WORKSPACE) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(DEVICE)' \
		-derivedDataPath DerivedData

# ---------------------------------------------------------------- 真机 Release
# 到 2026-09-17 为止真机上装的一直是 Debug 包：`DerivedData-device*/Build/Products/`
# 底下只有 `Debug-iphoneos`。Debug 关了优化、开了运行时检查，用它量图表帧率等于
# 自己给自己扣分。下面两条把「编 Release 真机包 → 装到连着的那台」补齐。
#
# 注意：`make device-release` 会真的去签名（`-allowProvisioningUpdates`），
# 不要在没插机器 / 没登录开发者账号的环境里跑。
DEVICE_RELEASE_DD := DerivedData-device-release
DEVICE_RELEASE_APP := $(DEVICE_RELEASE_DD)/Build/Products/Release-iphoneos/Kanpan.app

device-release:
	$(XCODEBUILD) \
		-project Kanpan/Kanpan.xcodeproj \
		-scheme $(SCHEME) \
		-configuration Release \
		-destination 'generic/platform=iOS' \
		-derivedDataPath $(DEVICE_RELEASE_DD) \
		-allowProvisioningUpdates \
		DEVELOPMENT_TEAM=$(TEAM_ID) \
		build
	@echo "Release 真机包：$(DEVICE_RELEASE_APP)"

# 装到第一台 connected 真机。UDID 从 `xcrun devicectl list devices` 解析（JSON 落到
# 临时文件：让它写 /dev/stdout 会混进人类可读那份，json.load 会报 Extra data），
# 只认 state=connected 的那几行；一台都没有就直接报错，不去碰模拟器。
#
# 依赖 `device-release`：这一条以前不重编，改完代码直接 `make install-release` 装上去的
# 是上一次的包，真机上验出来的行为是旧的——2026-09-18 就这么白测了一轮。增量编译在
# 没有改动时只要十几秒，不值得为省这点时间冒装错包的风险。
install-release: device-release
	@[ -d "$(DEVICE_RELEASE_APP)" ] || { echo "没找到 $(DEVICE_RELEASE_APP)，先跑 make device-release"; exit 1; }
	@# 挑真机的这段 python **必须写在一行里**。原来它是按 `;\` 断成五行的，make 把续行
	@# 接起来时在每个接缝处塞了一个空格，`import` 前面于是多出空白，python3 当场
	@# `IndentationError: unexpected indent`——而外层 `$$(...)` 把它的 stderr 咽了，
	@# 只剩下一句「没有已配对且在线的真机」，看着像手机没插好。2026-09-22 手机明明
	@# 是 `available (paired)` 却装不上去，就是栽在这儿。
	@udid=$$(xcrun devicectl list devices --json-output "$(TMPDIR)devicectl.json" >/dev/null 2>&1; python3 -c "import json,sys; d=json.load(open(sys.argv[1])); xs=[x for x in d.get('result',{}).get('devices',[]) if x.get('connectionProperties',{}).get('tunnelState')!='unavailable' and x.get('connectionProperties',{}).get('pairingState')=='paired']; print(xs[0]['hardwareProperties']['udid'] if xs else '')" "$(TMPDIR)devicectl.json"); \
	[ -n "$$udid" ] || { echo "没有已配对且在线的真机（xcrun devicectl list devices 看一眼）"; exit 1; }; \
	echo "→ 装到 $$udid"; \
	xcrun devicectl device install app --device "$$udid" "$(DEVICE_RELEASE_APP)"

# ---------------------------------------------------------------- TestFlight
# 三步走：archive → ipa → upload。`device-release` 出的是能装到自己手机上的 .app，
# 交付不了 TestFlight——App Store Connect 只收归档导出的 ipa，所以这三条是另一条路，
# 不复用上面那个 DerivedData。
#
# 2026-09-19 现状：这台机器上只有**免费个人 Team**（27Y32PT2HZ），
# 只签得出 Apple Development 证书、描述文件 7 天到期。实测的卡点不在 `archive`
# 而在 `ipa`：`make archive` 会成功，但它是拿 "Apple Development: …" 那张证书
# 和 Team Provisioning Profile 签的；到 `make ipa` 要按 app-store-connect 重签时
# 就报
#     error: exportArchive No Accounts
#     error: exportArchive No profiles for 'com.mdd.kanpan' were found
# （xcodebuild 命令行里没有登录的 App Store Connect 账号，免费 Team 也生成不出
# App Store 的分发描述文件）。这是预期的，别为了让它过去把 method 改成
# development——那样导出的 ipa 传上去照样被拒。入会之后在 Xcode 里登录一次
# 付费账号，这两条报错就都没了。
#
# 换团队时只改 `TEAM_ID` 一处（或者临时 `make archive TEAM_ID=XXXXXXXXXX`）。
#
# 审查 C.7：这以前是**不成立**的。`archive` / `device-release` 都不往 xcodebuild 传
# `DEVELOPMENT_TEAM`，于是归档用的是 pbxproj 里写死的那个团队，而 `ipa` 那一步又 sed
# 出一份带新 Team ID 的 ExportOptions——归档和导出分属两个团队，导出当场失败，
# 而命令行上看起来 `TEAM_ID=新值` 明明传进去了。现在两条构建命令都显式覆盖，
# pbxproj 里那四处 `DEVELOPMENT_TEAM = 27Y32PT2HZ` 只剩下「在 Xcode 里点开也能编」的作用。
# `Kanpan/Config/ExportOptions.plist` 照旧不用动，`ipa` 会 sed 出一份带新 Team ID 的副本。
TEAM_ID ?= 27Y32PT2HZ
# 构建号。App Store Connect 不收重复的 (MARKETING_VERSION, CURRENT_PROJECT_VERSION)
# 组合，所以每传一版都得递增。工程里现在写死 CURRENT_PROJECT_VERSION = 1，
# 命令行传 BUILD 就地覆盖，不用去改 pbxproj（也就不会和别的窗口抢那个文件）：
#     make archive BUILD=7
# 不传 BUILD 时 BUILD_SETTING 整个是空的，xcodebuild 用工程里的值。
BUILD ?=
BUILD_SETTING := $(if $(BUILD),CURRENT_PROJECT_VERSION=$(BUILD),)
BUILD_ARG     := $(if $(BUILD), BUILD=$(BUILD),)
BUILD_TAG     := $(if $(BUILD),$(BUILD),dev)

ARCHIVE_DD   := DerivedData-archive
# 归档路径按构建号分开。2026-09-19 之前这里写死 Kanpan.xcarchive，磁盘上永远只有
# 一份，下一次 `make archive` 会把上一份连同它的 dSYM 一起顶掉。这是会真出事的：
# 一个 TestFlight 构建在 90 天有效期里测试者还在装着用，那期间回来的崩溃日志只能拿
# **那个构建号**的 dSYM 符号化——重编一遍出来的二进制 UUID 对不上，补不回来。而
# DerivedData-archive/ 被 .gitignore 挡在仓库外，本机独一份、没有任何备份，顶掉就没了。
# 所以现在每个构建号各占一份归档，历史自然堆积（磁盘满了自己挑旧的删，别让 make 删）。
# 不传 BUILD 的那份叫 -dev，随手覆盖无所谓：它没有唯一构建号，本来也传不上去。
ARCHIVE_PATH := $(ARCHIVE_DD)/Kanpan-$(BUILD_TAG).xcarchive
# xcodebuild -exportArchive 只收目录、导出来的 ipa 一律叫 $(SCHEME).ipa，没法直接指定
# 文件名；所以先导进各自的 export-<构建号>/（DistributionSummary.plist 那几个副产物
# 也跟着分开），再改名成带号的 ipa 摆到 $(ARCHIVE_DD) 根下，和归档对得上。
EXPORT_DIR   := $(ARCHIVE_DD)/export-$(BUILD_TAG)
EXPORT_PLIST := $(EXPORT_DIR)/ExportOptions.plist
IPA          := $(ARCHIVE_DD)/Kanpan-$(BUILD_TAG).ipa
# 上传台账（进 git，见下面 upload 上方那段注释）。
UPLOAD_LEDGER := docs/testflight-uploads.md

archive:
	@echo "→ 归档 Release$(if $(BUILD), · 构建号 $(BUILD),（构建号用工程里的值）)"
	$(XCODEBUILD) archive \
		-project Kanpan/Kanpan.xcodeproj \
		-scheme $(SCHEME) \
		-configuration Release \
		-destination 'generic/platform=iOS' \
		-archivePath $(ARCHIVE_PATH) \
		-derivedDataPath $(ARCHIVE_DD) \
		-allowProvisioningUpdates \
		DEVELOPMENT_TEAM=$(TEAM_ID) \
		$(BUILD_SETTING)
	@echo "归档：$(ARCHIVE_PATH)（dSYM 在它的 dSYMs/ 里，崩溃日志要靠它，别删）"

ipa:
	@[ -d "$(ARCHIVE_PATH)" ] || { echo "没找到 $(ARCHIVE_PATH)，先跑 make archive$(BUILD_ARG)——archive / ipa / upload 三条必须用同一个构建号"; exit 1; }
	@mkdir -p $(EXPORT_DIR)
	@sed 's/27Y32PT2HZ/$(TEAM_ID)/' Kanpan/Config/ExportOptions.plist > $(EXPORT_PLIST)
	@rm -f $(IPA) $(EXPORT_DIR)/$(SCHEME).ipa
	$(XCODEBUILD) -exportArchive \
		-archivePath $(ARCHIVE_PATH) \
		-exportOptionsPlist $(EXPORT_PLIST) \
		-exportPath $(EXPORT_DIR) \
		-allowProvisioningUpdates
	@mv $(EXPORT_DIR)/$(SCHEME).ipa $(IPA)
	@echo "ipa：$(IPA)"

# 上传走 App Store Connect API Key，不用 Apple ID + 应用专用密码：密钥不进仓库、
# 不进命令行历史，也不会因为двух步验证卡住。准备工作（只做一次）：
#   1. App Store Connect → 用户和访问 → 集成 → App Store Connect API → 生成密钥
#      （角色至少 App Manager），下载 AuthKey_XXXXXXXXXX.p8，**只能下一次**
#   2. mkdir -p ~/.appstoreconnect/private_keys && mv AuthKey_*.p8 ~/.appstoreconnect/private_keys/
#      （altool 认死这个目录，不用再传路径）
#   3. export ASC_KEY_ID=XXXXXXXXXX    # 就是文件名里那段
#      export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   # 密钥页顶上的 Issuer ID
# 少了哪一样下面各有一句中文报错，不会甩一屏 altool 的 usage 出来。
#
# 传成功之后往 $(UPLOAD_LEDGER) 追加一行，这不是「顺手记个账」，是 dSYM 的保质期表：
# 一个 TestFlight 构建有 90 天有效期，这期间测试者还装着它用，回来的崩溃日志只能拿
# **那个构建号**的 dSYM 符号化（重编一遍二进制 UUID 就对不上了，补不回来）。也就是说
# `DerivedData-archive/Kanpan-<构建号>.xcarchive` 能不能删，取决于它是哪天传上去的。
# 而这台机器上查不到这个日期：`~/Library/Logs/ContentDelivery*` 和 `~/.itmstransporter`
# ——Transporter 会留上传日志的那两个地方——在本机根本不存在（2026-09-19 实地确认过），
# 也就是说上传这件事没在本地留下任何痕迹；归档目录本身又被 .gitignore 挡在仓库外、
# 没有备份，mtime 也只说明它是哪天编的、不说明哪天传的。以前只能靠人嘴上传一句
# 「这份传过了」，换个窗口就断。所以把「哪份归档哪天传的」落进仓库里的一个纯追加文件，
# 清理磁盘的人照着它算 90 天，谁来接手都查得到。
#
# 追加那几行故意单独成一条 recipe 行摆在 altool 之后：make 里一行非零就中止这个目标，
# altool 失败根本走不到下面，台账不会留下假记录（别把它们用 `;` 接到 altool 那行去，
# 那样 altool 的退出码会被最后一条命令盖掉，传挂了照样记一笔）。
# 版本号不写死，从归档的 Info.plist 里取 —— 那是**真正打进这个 ipa 的**版本，比读工程
# 设置更贴事实；归档万一被清了，再退回 xcodebuild -showBuildSettings 问一次。
upload:
	@[ -f "$(IPA)" ] || { echo "没找到 $(IPA)，先跑 make archive$(BUILD_ARG) && make ipa$(BUILD_ARG)——archive / ipa / upload 三条必须用同一个构建号"; exit 1; }
	@[ -n "$$ASC_KEY_ID" ] || { echo "缺环境变量 ASC_KEY_ID（App Store Connect API 密钥 ID，形如 ABC123DEF4）：export ASC_KEY_ID=..."; exit 1; }
	@[ -n "$$ASC_ISSUER_ID" ] || { echo "缺环境变量 ASC_ISSUER_ID（密钥页顶上的 Issuer ID，一串 UUID）：export ASC_ISSUER_ID=..."; exit 1; }
	@[ -f "$$HOME/.appstoreconnect/private_keys/AuthKey_$$ASC_KEY_ID.p8" ] || { \
		echo "没找到私钥 ~/.appstoreconnect/private_keys/AuthKey_$$ASC_KEY_ID.p8"; \
		echo "把从 App Store Connect 下载的 .p8 放进那个目录（文件名保持 AuthKey_<KEY_ID>.p8）"; exit 1; }
	@echo "→ 上传 $(IPA)（密钥 $$ASC_KEY_ID）"
	xcrun altool --upload-app -f "$(IPA)" -t ios \
		--apiKey "$$ASC_KEY_ID" --apiIssuer "$$ASC_ISSUER_ID"
	@ver=$$(plutil -extract ApplicationProperties.CFBundleShortVersionString raw -o - "$(ARCHIVE_PATH)/Info.plist" 2>/dev/null); \
	[ -n "$$ver" ] || ver=$$(xcodebuild -showBuildSettings -project Kanpan/Kanpan.xcodeproj -scheme $(SCHEME) -configuration Release 2>/dev/null | awk '$$1=="MARKETING_VERSION" { print $$3 }'); \
	[ -n "$$ver" ] || ver="?"; \
	keep=$$(date -v+90d "+%Y-%m-%d"); \
	printf '| %s | %s | %s | %s | %s | %s |\n' \
		"$$(date "+%Y-%m-%d %H:%M")" "$$ver" "$(BUILD_TAG)" "$(ARCHIVE_PATH)" "$$(basename "$(IPA)")" "$$keep" \
		>> $(UPLOAD_LEDGER); \
	echo "已记入台账 $(UPLOAD_LEDGER)：版本 $$ver · 构建号 $(BUILD_TAG)"; \
	echo "这份归档 $(ARCHIVE_PATH) 连同里面的 dSYM 请留到 $$keep 之后再删（TestFlight 构建 90 天有效期内崩溃日志还要靠它符号化）。"
	@echo "传完了。App Store Connect 上处理完（几分钟到半小时）才会出现在 TestFlight 里。"

# ---------------------------------------------------------------- A0.3 取证
snap: build
	@mkdir -p $(SHOTS)
	@bash Tools/snap.sh "$(DEVICE)" "$(SHOTS)"

screenshots: build devices
	@mkdir -p $(SHOTS)
	@for d in $(DEVICES); do \
		bash Tools/snap.sh "$$d" "$(SHOTS)" || exit 1; \
	done
	@echo "\n两台完成，图在 $(SHOTS)/"
	@ls -1 $(SHOTS)

# ---------------------------------------------------------------- A0.2 机型
devices:
	@bash Tools/ensure-devices.sh

boot: devices
	@for d in $(DEVICES); do \
		echo "→ boot $$d"; \
		xcrun simctl boot "$$d" 2>/dev/null || true; \
		xcrun simctl bootstatus "$$d" -b >/dev/null 2>&1 || true; \
	done
	@xcrun simctl list devices | grep Booted

shutdown:
	-xcrun simctl shutdown all

# 可再生产物的清单只有一份，在守门脚本里：各包 .build、.xcbuild*、DerivedData*（留着
# DerivedData-archive）、cargo target、/tmp 构建目录（worktree 只清里面的产物）、Xcode 全局
# DerivedData 与 SwiftPM 缓存。这里不再自己列一份，免得新加一个包就漏删。
clean:
	@scripts/machine-guard.sh clean
