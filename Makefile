# 看盘 · 构建与取证入口（任务书 §13 M0）
# 约定：所有命令从仓库根跑；证据落在 docs/acceptance/。

WORKSPACE  := Kanpan.xcworkspace
SCHEME     := Kanpan
CORE       := KanpanCore
CHART      := KanpanChart
RUNTIME    := iOS
SHOTS      := docs/acceptance/shots

# A0.2 的八台机型，与原型 app.js 的 DEVICES 一一对应
DEVICES := \
	"iPhone SE (3rd generation)" \
	"iPhone 13 mini" \
	"iPhone 15" \
	"iPhone 16 Pro" \
	"iPhone Air" \
	"iPhone 16 Plus" \
	"iPhone 17 Pro Max" \
	"iPad mini (A17 Pro)"

# 单台机型时用：make snap DEVICE="iPhone 16 Pro"
DEVICE ?= iPhone 16 Pro

.PHONY: help core-test data-test chart-build chart-test test strict app-test snap screenshots devices boot shutdown clean doctor

help:
	@echo "core-test    跑 KanpanCore 单测（不需要 Xcode GUI，CLT 也能跑）"
	@echo "data-test    跑 KanpanData 单测（全离线：假 transport / 假 socket / 假时钟）"
	@echo "chart-build  编 KanpanChart（UIKit，必须走 xcodebuild）"
	@echo "chart-test   跑 KanpanChart 单测（需要一台模拟器）"
	@echo "test         core-test + data-test + chart-build"
	@echo "strict       两个包都按 Swift 6 严格并发 + 警告即错误编一遍（A2.13）"
	@echo "app-test     跑 app target 的测试"
	@echo "snap         在单台模拟器上装 app 并截一张图（DEVICE=\"iPhone 16 Pro\"）"
	@echo "screenshots  八台机型全跑一遍，出 docs/acceptance/shots/"
	@echo "devices      备齐 A0.2 的八台模拟器（缺的自动 create）"
	@echo "boot         把八台全 boot 起来"
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

test: core-test data-test chart-build

# A2.13：零警告零错误。警告即错误，谁也别想蒙混过去。
strict:
	cd $(CORE) && swift build -Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete
	cd $(DATA) && swift build -Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete
	cd $(CHART) && xcodebuild -scheme KanpanChart -destination 'generic/platform=iOS Simulator' \
		-derivedDataPath .xcbuild SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build

# 数据层取证工具（§13 M2 的证据都从这儿出）
feed:
	cd $(DATA) && swift build -c release --product kanpan-feed
	@echo "二进制：$(DATA)/.build/release/kanpan-feed"

# ---------------------------------------------------------------- app
app-test:
	xcodebuild test \
		-workspace $(WORKSPACE) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(DEVICE)' \
		| xcbeautify 2>/dev/null || true

build:
	xcodebuild build \
		-workspace $(WORKSPACE) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(DEVICE)' \
		-derivedDataPath DerivedData

# ---------------------------------------------------------------- A0.3 取证
snap: build
	@mkdir -p $(SHOTS)
	@bash Tools/snap.sh "$(DEVICE)" "$(SHOTS)"

screenshots: build devices
	@mkdir -p $(SHOTS)
	@for d in $(DEVICES); do \
		bash Tools/snap.sh "$$d" "$(SHOTS)" || exit 1; \
	done
	@echo "\n八台完成，图在 $(SHOTS)/"
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
