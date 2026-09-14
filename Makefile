# 看盘 —— 构建与验收入口（任务书 §13 M0）
#
#   make core-test    KanpanCore 单测（不需要 Xcode GUI，CLT 就能跑）
#   make app-test     app 与 UI 测试（需要 Xcode + 模拟器）
#   make snap         快照测试（176 张基线逐像素比对）
#   make screenshots  8 台模拟器的机型矩阵截图
#
# 为什么 core-test 这么多 -Xswiftc：Command Line Tools 不把 swift-testing 放在
# 默认搜索路径里，得手工把 framework 目录和两条 rpath 递给编译器和链接器。
# 装了完整 Xcode 之后这些参数无害（照样能编），所以不分两套。

SHELL := /bin/bash
CORE  := KanpanCore
SCHEME := Kanpan
SIM ?= iPhone 17 Pro

# swift-testing 在 CLT 下的落脚点。DEVELOPER_DIR 指向 Xcode 时这两个目录也在，
# 找不到就退回空串，让 swift 自己去默认路径找。
CLT_F := $(shell [ -d /Library/Developer/CommandLineTools/Library/Developer/Frameworks ] \
	&& echo /Library/Developer/CommandLineTools/Library/Developer/Frameworks)
CLT_L := /Library/Developer/CommandLineTools/Library/Developer/usr/lib
TESTING_FLAGS := $(if $(CLT_F),-Xswiftc -F -Xswiftc $(CLT_F) \
	-Xlinker -F -Xlinker $(CLT_F) \
	-Xlinker -rpath -Xlinker $(CLT_F) \
	-Xlinker -rpath -Xlinker $(CLT_L),)

.PHONY: core-test core-build fixtures app-test snap screenshots clean

core-test:
	cd $(CORE) && swift test --parallel $(TESTING_FLAGS)

## 零警告的 release 构建（A1.13）
core-build:
	cd $(CORE) && swift build -c release -Xswiftc -warnings-as-errors \
		$(if $(CLT_F),-Xswiftc -F -Xswiftc $(CLT_F),)

## 从定版原型重新导出黄金值 fixture（改了 prototype 才需要跑）
fixtures:
	node Tools/export-fixtures.mjs

app-test:
	xcodebuild test -scheme $(SCHEME) -destination 'platform=iOS Simulator,name=$(SIM)' | xcpretty || \
	xcodebuild test -scheme $(SCHEME) -destination 'platform=iOS Simulator,name=$(SIM)'

snap:
	xcodebuild test -scheme $(SCHEME) -destination 'platform=iOS Simulator,name=$(SIM)' \
		-only-testing:KanpanSnapshotTests

screenshots:
	bash Tools/screenshots.sh

clean:
	cd $(CORE) && swift package clean
