#!/usr/bin/env bash
# 兼容验收：iPhone 15 及更新机型、iPad 系列，逐台记结果。
#
# 为什么一台一条命令、不用 xcodebuild 的多 -destination：
#   多 destination 并行跑的时候，失败只会汇总成一句「Testing failed」，
#   看不出是哪台挂的；而 A8.4 要的正是**逐机型**的结论。所以这里串行，
#   每台单独一个 .xcresult，最后打一张表。
#
# 每台跑之前先 uninstall 一次：app 的偏好是持久化的（PrefsStore 写 UserDefaults），
# 上一轮留下的风格 / 周期会让「默认态」不成立。卸掉 = 干净的第一次启动。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="${OUT:-docs/acceptance/M8/ui-test}"   # 文本日志与汇总（入库）
RES="${RES:-DerivedData/ui-test}"          # .xcresult 结果包（体积大，随 DerivedData 一起被 gitignore）
BUNDLE_ID=com.mdd.kanpan
WORKSPACE=Kanpan.xcworkspace
SCHEME=Kanpan
DD=DerivedData

DEVICES=(
  "iPhone 15"
  "iPhone 16 Pro"
  "iPhone 16 Plus"
  "iPhone 17"
  "iPhone 17 Pro Max"
  "iPhone Air"
  "iPad mini (A17 Pro)"
  "iPad (A16)"
  "iPad Air 11-inch (M4)"
  "iPad Pro 11-inch (M5)"
  "iPad Pro 13-inch (M5)"
)

mkdir -p "$OUT" "$RES"

echo "== build-for-testing =="
xcodebuild build-for-testing \
  -workspace "$WORKSPACE" -scheme "$SCHEME" \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DD" > "$OUT/build.log" 2>&1 || {
    echo "构建失败，见 $OUT/build.log"; tail -30 "$OUT/build.log"; exit 1; }

fail=0
: > "$OUT/summary.txt"
for name in "${DEVICES[@]}"; do
  slug="$(echo "$name" | tr ' ()' '---' | tr -s '-' | sed 's/-$//')"
  udid="$(xcrun simctl list devices available -j \
    | python3 -c "import json,sys;d=json.load(sys.stdin)['devices'];print(next((x['udid'] for v in d.values() for x in v if x['name']=='$name'),''))")"
  if [ -z "$udid" ]; then
    echo "✗ $name：模拟器不存在"; echo "$name	MISSING	0	0" >> "$OUT/summary.txt"; fail=1; continue
  fi
  echo "→ $name ($udid)"
  xcrun simctl bootstatus "$udid" -b > /dev/null 2>&1
  xcrun simctl uninstall "$udid" "$BUNDLE_ID" > /dev/null 2>&1

  rm -rf "$RES/$slug.xcresult"
  start=$SECONDS
  xcodebuild test-without-building \
    -workspace "$WORKSPACE" -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "$DD" \
    -resultBundlePath "$RES/$slug.xcresult" > "$OUT/$slug.log" 2>&1
  rc=$?
  dur=$((SECONDS-start))
  # 跑完就关机。八台一路 boot 下来不关，最后那台常常被系统按内存压力 SIGTERM 掉
  # （实测 iPad Pro 11-inch 在第八位上被 Terminated: 15，日志停在 ** BUILD INTERRUPTED **）。
  xcrun simctl shutdown "$udid" > /dev/null 2>&1 || true
  passed=$(grep -c "' passed (" "$OUT/$slug.log")
  failed=$(grep -c "' failed (" "$OUT/$slug.log")
  if [ $rc -eq 0 ]; then
    echo "  ✓ $passed 条通过，${dur}s"
    echo "$name	PASS	$passed	$dur" >> "$OUT/summary.txt"
  else
    echo "  ✗ 失败 $failed 条（通过 $passed），见 $OUT/$slug.log"
    grep -E "error:|XCTAssert" "$OUT/$slug.log" | head -10
    echo "$name	FAIL	$passed/$failed	$dur" >> "$OUT/summary.txt"
    fail=1
  fi
done

echo
echo "================ 逐机型结果 ================"
column -t -s $'\t' "$OUT/summary.txt"
exit $fail
