#!/usr/bin/env bash
# M3 取证渲染器（任务书 §12.2「快照测试」那一行）。
#
#   Tools/render-evidence.sh [机型]
#
# 真正画图的是 KanpanChart 测试 target 里的 `M3 取证渲染` / `A3.2 几何量化` /
# `A3.3 颜色取样` 三个 suite——UIKit 绘制必须在 iOS 模拟器里跑，所以走 xcodebuild，
# 没有单独的命令行二进制。
#
# 落盘的开关是 `docs/acceptance/M3/.render` 这个标记文件：本脚本跑之前建、跑完删，
# 测试里 `Evidence.outputDir` 见到它才写文件。没有它（也就是 `make chart-test`）
# 三个取证测试照样跑断言，只是一个字节都不落盘。
#
# 为什么不用环境变量：`xcodebuild test` 的 `TEST_RUNNER_<VAR>` 前缀对 SwiftPM scheme
# 的 xctest 宿主不生效，变量进不到测试进程里（实测 2026-09-14）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${1:-iPhone 16 Pro}"
OUT="$ROOT/docs/acceptance/M3"

mkdir -p "$OUT"
echo "→ 取证输出：$OUT"
echo "→ 模拟器：  $DEVICE"

# fixture 是定版快照，不在就先从原型导一遍（需要 node；产物已入库，通常不会走到这儿）
FIX="$ROOT/KanpanChart/Tests/KanpanChartTests/Fixtures"
if [ ! -f "$FIX/snapshot.json" ]; then
  echo "→ 缺 fixture，先从原型导出"
  ( cd "$ROOT" && node Tools/export-chart-fixtures.mjs )
fi

cd "$ROOT/KanpanChart"
MARKER="$OUT/.render"
: > "$MARKER"
trap 'rm -f "$MARKER"' EXIT

xcodebuild test \
  -scheme KanpanChart \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath .xcbuild

echo
echo "== 产物 =="
ls -1 "$OUT" | sed -n '1,12p'
echo "…"
printf 'png %s 张，json/csv %s 份，合计 %s\n' \
  "$(ls -1 "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ')" \
  "$(ls -1 "$OUT"/*.json "$OUT"/*.csv 2>/dev/null | wc -l | tr -d ' ')" \
  "$(du -sh "$OUT" | cut -f1)"
