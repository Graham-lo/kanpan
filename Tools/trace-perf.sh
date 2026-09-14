#!/usr/bin/env bash
# M9 性能取证：一条命令把 Instruments 的 trace 录下来并导成可读的 XML。
# （任务书 §12.2「Instruments 导出」那一行；G13 是 [I]，必须真机。）
#
#   Tools/trace-perf.sh [模板] [秒数] [设备]
#   Tools/trace-perf.sh                      # Animation Hitches / 30s / 自动挑第一台真机
#   Tools/trace-perf.sh "Time Profiler" 20
#   Tools/trace-perf.sh "App Launch" 15 00008140-000C4D...
#
# 为什么要有这个脚本：Instruments 的取证全靠手点，「录了多久、用哪个模板、导出的是
# 哪一栏」全凭记忆，两次测出来的数没法比。把模板、时长、导出路径钉死在脚本里，
# 换台机器重跑一遍就是可比的。
#
# **只在真机上有意义**。模拟器的 Animation Hitches 测的是 mac 的合成器，
# 120Hz ProMotion 更是模拟不出来——任务书把 G13 标成 [I] 就是这个原因。
#
# 前提：app 已经装在那台真机上并且**正在前台跑**（脚本走 --attach）。
# 先在 Xcode 里 Run 一次，或者 `xcrun devicectl device process launch`。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${1:-Animation Hitches}"
SECONDS_TO_RECORD="${2:-30}"
DEVICE_ARG="${3:-}"
PROCESS="Kanpan"
OUT="$ROOT/docs/acceptance/M9/traces"

command -v xcrun >/dev/null || { echo "没有 xcrun，先装 Xcode"; exit 1; }
xcrun xctrace version >/dev/null 2>&1 || { echo "xctrace 不可用（需要完整 Xcode，不是 CLT）"; exit 1; }

# ---- 挑设备 ---------------------------------------------------------------
# `xctrace list devices` 的输出里，真机那段在 "== Devices ==" 之下、
# "== Simulators ==" 之上，形如：`我的 iPhone (26.5) (00008140-000C...)`。
if [ -n "$DEVICE_ARG" ]; then
  DEVICE="$DEVICE_ARG"
else
  DEVICE=$(xcrun xctrace list devices 2>/dev/null | python3 -c "
import re, sys
inside = False
for line in sys.stdin:
    if line.startswith('== Devices =='):
        inside = True; continue
    if line.startswith('=='):
        inside = False; continue
    if not inside or not line.strip():
        continue
    # 真机行长这样：\`我的 iPhone (26.5) (00008140-000C4D...)\`。
    # 这台 mac 自己那行没有系统版本括号，靠这个筛掉。
    m = re.search(r'\((\d+\.\d+(?:\.\d+)?)\)\s+\(([0-9A-Fa-f-]{8,})\)\s*$', line)
    if m:
        print(m.group(2)); break
" || true)
  if [ -z "${DEVICE:-}" ]; then
    echo "没找到连着的真机。"
    echo "把 iPhone 插上、解锁、信任这台 mac，然后："
    echo "  xcrun xctrace list devices"
    echo "把 UDID 作为第三个参数传进来。"
    exit 1
  fi
fi

STAMP=$(date +%Y%m%d-%H%M%S)
SLUG=$(echo "$TEMPLATE" | tr '[:upper:] ' '[:lower:]-')
TRACE="$OUT/$SLUG-$STAMP.trace"
mkdir -p "$OUT"

echo "→ 模板：  $TEMPLATE"
echo "→ 设备：  $DEVICE"
echo "→ 进程：  $PROCESS"
echo "→ 时长：  ${SECONDS_TO_RECORD}s"
echo "→ 落盘：  $TRACE"
echo
echo "开始录制。**现在就在手机上连续拖动 K 线**——录到的是这段时间真实发生的事，"
echo "手停着不动录出来的 0 次卡顿不算数。"
echo

xcrun xctrace record \
  --template "$TEMPLATE" \
  --device "$DEVICE" \
  --attach "$PROCESS" \
  --time-limit "${SECONDS_TO_RECORD}s" \
  --output "$TRACE"

echo
echo "== 导出 =="
# TOC 先导：它列出这份 trace 里到底有哪些表（schema 名字每个 Xcode 版本都可能改），
# 没有它就只能瞎猜 --xpath。
TOC="${TRACE%.trace}-toc.xml"
xcrun xctrace export --input "$TRACE" --toc --output "$TOC"
echo "   ✓ $(basename "$TOC")"

# 再按模板导对应的表。导不出来不算失败——trace 本身已经在盘上，Instruments 打得开。
case "$TEMPLATE" in
  "Animation Hitches")  SCHEMAS="animation-hitch-summary display-vsync-info" ;;
  "Time Profiler")      SCHEMAS="time-profile" ;;
  "App Launch")         SCHEMAS="app-launch-intervals time-profile" ;;
  *)                    SCHEMAS="" ;;
esac
for s in $SCHEMAS; do
  dst="${TRACE%.trace}-$s.xml"
  if xcrun xctrace export --input "$TRACE" \
      --xpath "/trace-toc/run[@number=\"1\"]/data/table[@schema=\"$s\"]" \
      --output "$dst" 2>/dev/null && [ -s "$dst" ]; then
    echo "   ✓ $(basename "$dst")"
  else
    rm -f "$dst"
    echo "   · 这份 trace 里没有 $s 表（看 $(basename "$TOC") 里实际有哪些）"
  fi
done

echo
echo "== 接下来 =="
echo "open \"$TRACE\"     # 用 Instruments 看"
echo "证据表里要记的三个数（Animation Hitches 模板）："
echo "  · Hitch Time Ratio（ms/s）—— 任务书 G13 要 < 1%，也就是 < 10 ms/s"
echo "  · 最长一次 hitch 的时长"
echo "  · 这段时间的实际刷新率（120 / 80 / 60，低电量模式会降）"
