# 看盘 · 构建与取证入口（任务书 §13 M0）
# 约定：所有命令从仓库根跑；证据落在 docs/acceptance/。

WORKSPACE  := Kanpan.xcworkspace
SCHEME     := Kanpan
CORE       := KanpanCore
CHART      := KanpanChart
RUNTIME    := iOS
SHOTS      := docs/acceptance/shots

# 当前兼容范围：iPhone 15 及更新型号、iPad；与 Tools/ui-test.sh 保持一致。
DEVICES := \
	"iPhone 15" \
	"iPhone 16 Pro" \
	"iPhone 16 Plus" \
	"iPhone 17" \
	"iPhone 17 Pro" \
	"iPhone 17e" \
	"iPhone 17 Pro Max" \
	"iPhone Air" \
	"iPad mini (A17 Pro)" \
	"iPad (A16)" \
	"iPad Air 11-inch (M4)" \
	"iPad Pro 11-inch (M5)" \
	"iPad Pro 13-inch (M5)"

# 单台机型时用：make snap DEVICE="iPhone 16 Pro"
DEVICE ?= iPhone 16 Pro

.PHONY: help core-test network-test data-test diag-test diag-ios-test chart-build chart-test test strict app-test ui-test ui-test-one snap screenshots devices boot shutdown clean doctor evidence fixtures device-release install-release archive ipa upload

help:
	@echo "core-test    跑 KanpanCore 单测（不需要 Xcode GUI，CLT 也能跑）"
	@echo "network-test 跑 KanpanNetwork 单测（HTTP/WS 接口、币安客户端、线路与网关竞速）"
	@echo "data-test    跑 KanpanData 单测（全离线：假 transport / 假 socket / 假时钟）"
	@echo "chart-build  编 KanpanChart（UIKit，必须走 xcodebuild）"
	@echo "chart-test   跑 KanpanChart 单测（需要一台模拟器）"
	@echo "test         core-test + network-test + data-test + app-logic-test + chart-test"
	@echo "strict       两个包都按 Swift 6 严格并发 + 警告即错误编一遍（A2.13）"
	@echo "evidence     出 M3 全套取证产物到 docs/acceptance/M3/（A3.1–A3.10）"
	@echo "fixtures     从原型重新导一次定版 fixture（需要 node，产物已入库）"
	@echo "app-test     跑 app target 的测试"
	@echo "ui-test      A8.4：13 台机型跑同一套 XCUITest 用例，逐台记结果"
	@echo "ui-test-one  只跑一台（DEVICE=\"iPhone 16 Pro\"）"
	@echo "device-release  编真机 Release 包（generic/platform=iOS，签名走 -allowProvisioningUpdates）"
	@echo "install-release 把 Release 包装到第一台 connected 真机"
	@echo "archive      归档 Release 真机包到 DerivedData-archive/Kanpan-<构建号>.xcarchive（TestFlight 第一步）"
	@echo "             构建号每次上传必须递增，也用来分开历史归档和 dSYM：make archive BUILD=7；不传 BUILD 出的是 -dev 那份"
	@echo "ipa          把同一构建号的归档导成可上传的 ipa：make ipa BUILD=7（Team ID 可覆盖：TEAM_ID=XXXX）"
	@echo "upload       用 App Store Connect API Key 传同一构建号的 ipa：make upload BUILD=7（需 ASC_KEY_ID / ASC_ISSUER_ID）"
	@echo "snap         在单台模拟器上装 app 并截一张图（DEVICE=\"iPhone 16 Pro\"，RELEASE=1 走 Release 包）"
	@echo "screenshots  13 台机型全跑一遍，出 docs/acceptance/shots/"
	@echo "devices      备齐 当前范围的 13 台模拟器（缺的自动 create）"
	@echo "boot         把13 台全 boot 起来"
	@echo "doctor       打印环境信息，对 A0.1 的验收"
	@echo "clean        清 DerivedData 与 .build"

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
	cd $(CORE) && swift test $(CORE_TEST_FLAGS)

# ---------------------------------------------------------------- 网络层
# 怎么连到交易所：HTTP / WS 最小接口、币安 REST / WS 客户端与限流、行情线路（直连 / 网关）、
# 网关竞速与冷却。KanpanData 依赖它并整包 @_exported 转出去，app 照旧只 import KanpanData。
NETWORK := KanpanNetwork

network-test:
	cd $(NETWORK) && swift test $(CORE_TEST_FLAGS)

# ---------------------------------------------------------------- A2 Data
DATA := KanpanData

data-test:
	cd $(DATA) && swift test $(CORE_TEST_FLAGS)

# 绘制层 import UIKit，裸 swift build 会拿 macOS sysroot 编（-sdk 那条 flag 会被吞掉），
# 所以这里必须走 xcodebuild 指一个 iOS Simulator destination。
chart-build:
	cd $(CHART) && xcodebuild -scheme KanpanChart \
		-destination 'generic/platform=iOS Simulator' \
		-derivedDataPath .xcbuild build

chart-test:
	cd $(CHART) && xcodebuild test -scheme KanpanChart \
		-destination 'platform=iOS Simulator,name=$(DEVICE)' \
		-derivedDataPath .xcbuild

# ---------------------------------------------------------------- app 侧逻辑包
# app target（Kanpan.xcodeproj）没有 test action，补一个要改 project.pbxproj。
# 改用 SwiftPM 壳包：Sources/ 下是指向 Kanpan/Kanpan/<模块>/ 的符号链接，
# 一份代码两处编译，不会漂移。新增模块照 Symbols 的样子加一行。
SYMBOLS := Kanpan/Symbols

SETTINGS := Kanpan/Settings

symbols-test:
	cd $(SYMBOLS) && swift test $(CORE_TEST_FLAGS)

settings-test:
	cd $(SETTINGS) && swift test $(CORE_TEST_FLAGS)

DIAG := Kanpan/Diagnostics

diag-test:
	cd $(DIAG) && swift test $(CORE_TEST_FLAGS)

# 帧探针那几条只有真跑在 iOS 上才走得到（CADisplayLink / CFRunLoopObserver 在 mac
# 上编得过但量不到东西），所以单独一个 target，要起模拟器，故意不挂进 `test`。
# 真机取证前必须跑一遍。
diag-ios-test:
	cd $(DIAG) && xcodebuild test -scheme KanpanDiagnostics \
	  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath .xcbuild

app-logic-test: symbols-test settings-test diag-test

test: core-test network-test data-test app-logic-test chart-test

# A2.13：零警告零错误。警告即错误，谁也别想蒙混过去。
strict:
	cd $(CORE) && swift build -Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete
	cd $(NETWORK) && swift build -Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete
	cd $(DATA) && swift build -Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete
	cd $(CHART) && KANPAN_STRICT=1 xcodebuild -scheme KanpanChart \
		-destination 'generic/platform=iOS Simulator' -derivedDataPath .xcbuild-strict build

# ---------------------------------------------------------------- §12 M3 取证
# 绘制层的证据只能在模拟器里出（UIKit），所以取证器就是测试 target 里的三个 suite：
#   M3 取证渲染 / A3.2 几何量化 / A3.3 颜色取样
# 落盘开关是 docs/acceptance/M3/.render 标记文件（脚本建、跑完删）；没有它
# chart-test 照样跑断言但一个字节都不落盘。
evidence:
	@bash Tools/render-evidence.sh "$(DEVICE)"

# fixture 是把原型 chart.js / styles.js / data.js 原样跑一遍问出来的黄金值，
# 已入库，只有原型改动时才需要重导。
fixtures:
	node Tools/export-chart-fixtures.mjs
	@ls -l $(CHART)/Tests/KanpanChartTests/Fixtures

# 数据层取证工具（§13 M2 的证据都从这儿出）
feed:
	cd $(DATA) && swift build -c release --product kanpan-feed
	@echo "二进制：$(DATA)/.build/release/kanpan-feed"

# ---------------------------------------------------------------- app
# app target 本身没有 test action，`xcodebuild test` 会直接报
# 「Scheme Kanpan is not currently configured for the test action」，
# 原来那条末尾的 `|| true` 把这个事实吞掉了，看着像过了其实一条没跑。
# app 侧的逻辑一律由上面的壳包覆盖，这里只做编译验证。
app-test: app-logic-test build
	@echo "注意：app target 没有 test action，app 侧逻辑走 symbols-test 这类壳包。"

# ---------------------------------------------------------------- A8.4 UI 测试
# KanpanUITests（本工程里唯一的 XCTest target，其余单测一律 swift-testing）。
# 同一套用例在13 台机型上各跑一遍，逐台记结果：make ui-test
# 单台：make ui-test-one DEVICE="iPad mini (A17 Pro)"
UI_DEVICES := $(DEVICES)

ui-test:
	@bash Tools/ui-test.sh

ui-test-one:
	xcodebuild test \
		-workspace $(WORKSPACE) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(DEVICE)' \
		-derivedDataPath DerivedData

build:
	xcodebuild build \
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
	xcodebuild \
		-project Kanpan/Kanpan.xcodeproj \
		-scheme $(SCHEME) \
		-configuration Release \
		-destination 'generic/platform=iOS' \
		-derivedDataPath $(DEVICE_RELEASE_DD) \
		-allowProvisioningUpdates \
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
	@udid=$$(xcrun devicectl list devices --json-output "$(TMPDIR)devicectl.json" >/dev/null 2>&1; python3 -c "\
import json,sys;\
d=json.load(open(sys.argv[1]));\
xs=[x for x in d.get('result',{}).get('devices',[]) if x.get('connectionProperties',{}).get('tunnelState')!='unavailable' and x.get('connectionProperties',{}).get('pairingState')=='paired'];\
print(xs[0]['hardwareProperties']['udid'] if xs else '')" "$(TMPDIR)devicectl.json"); \
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
# 入会拿到分发证书之后要改的地方只有 Team ID（如果换了账号）：
#   1. 下面的 `TEAM_ID ?=`（或者临时 `make ipa TEAM_ID=XXXXXXXXXX`）
#   2. Kanpan/Kanpan.xcodeproj/project.pbxproj 里四处 `DEVELOPMENT_TEAM = 27Y32PT2HZ`
# `Kanpan/Config/ExportOptions.plist` 不用动，`ipa` 会 sed 出一份带新 Team ID 的副本。
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

archive:
	@echo "→ 归档 Release$(if $(BUILD), · 构建号 $(BUILD),（构建号用工程里的值）)"
	xcodebuild archive \
		-project Kanpan/Kanpan.xcodeproj \
		-scheme $(SCHEME) \
		-configuration Release \
		-destination 'generic/platform=iOS' \
		-archivePath $(ARCHIVE_PATH) \
		-derivedDataPath $(ARCHIVE_DD) \
		-allowProvisioningUpdates \
		$(BUILD_SETTING)
	@echo "归档：$(ARCHIVE_PATH)（dSYM 在它的 dSYMs/ 里，崩溃日志要靠它，别删）"

ipa:
	@[ -d "$(ARCHIVE_PATH)" ] || { echo "没找到 $(ARCHIVE_PATH)，先跑 make archive$(BUILD_ARG)——archive / ipa / upload 三条必须用同一个构建号"; exit 1; }
	@mkdir -p $(EXPORT_DIR)
	@sed 's/27Y32PT2HZ/$(TEAM_ID)/' Kanpan/Config/ExportOptions.plist > $(EXPORT_PLIST)
	@rm -f $(IPA) $(EXPORT_DIR)/$(SCHEME).ipa
	xcodebuild -exportArchive \
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
	@echo "\n13 台完成，图在 $(SHOTS)/"
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

clean:
	rm -rf DerivedData $(CORE)/.build $(DATA)/.build
