#!/usr/bin/env bash
# 兼容验收：两台重点机型（16 Pro / 17 Pro Max，2026-09-23 用户定），逐台记结果。
#
# 为什么一台一条命令、不用 xcodebuild 的多 -destination：
#   多 destination 并行跑的时候，失败只会汇总成一句「Testing failed」，
#   看不出是哪台挂的；而 A8.4 要的正是**逐机型**的结论。所以这里串行，
#   每台单独一个 .xcresult，最后打一张表。
#
# 每台跑之前先 uninstall 一次：app 的偏好是持久化的（PrefsStore 写 UserDefaults），
# 上一轮留下的风格 / 周期会让「默认态」不成立。卸掉 = 干净的第一次启动。
set -uo pipefail
GUARD="${GUARD:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/machine-guard.sh run}"  # 机器资源守门：排队 + nice，见 AGENTS.md「机器资源纪律」

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="${OUT:-docs/acceptance/M8/ui-test}"   # 文本日志与汇总（入库）
# 为什么 derived data 目录要能被环境变量覆盖：
#   同一个工作树上常常还有第二个窗口在跑 xcodebuild，而它用的正是默认的 DerivedData。
#   两条流水线同时往一个 derived data 里写，模块缓存、.app、.xctestrun 会互相覆盖，
#   轻则整轮重编，重则 test-without-building 跑的是对方刚换掉的包。所以要错开的时候
#   给它一个自己的路径；默认仍是 DerivedData，单窗口的日常用法不受影响。
DD="${DD:-DerivedData}"
RES="${RES:-$DD/ui-test}"                  # .xcresult 结果包（体积大，随 DerivedData 一起被 gitignore）
# 为什么模拟器名字要能加后缀：
#   错开 derived data 之后还剩最后一处共用——**设备本身**。两个窗口各跑一轮矩阵时，
#   两轮会 boot / uninstall / 测同一批模拟器，谁的 uninstall 落在对方正在跑的那台上，
#   对方那条用例当场就废了。给每个窗口一套自己的模拟器（名字 = 机型名 + 后缀，
#   例如「iPhone 16 Pro · m22」，用 Tools/make-sim-set.sh 照着现有同名设备建一套），
#   两轮就互不相干。
#   只做后缀、不让 DEVICES 被整份替换：那份两机型的列表本身就是兼容性承诺，
#   必须留在脚本里当唯一事实来源，否则两个窗口可能在测不同的机型集，矩阵就没有意义了。
#   后缀只用于查设备；日志、summary.txt、.xcresult 一律仍按**不带后缀**的机型名命名，
#   两个窗口产出的报告因此格式一致，可以直接比对。
SUFFIX="${SUFFIX:-}"
ONLY_DEVICE="${ONLY_DEVICE:-}"            # 受影响用例可只跑一台，空值仍跑完整矩阵
ONLY_TESTING="${ONLY_TESTING:-}"
TEST_ARGS=()
if [ -n "$ONLY_TESTING" ]; then
  IFS=',' read -r -a TEST_IDS <<< "$ONLY_TESTING"
  for test_id in "${TEST_IDS[@]}"; do TEST_ARGS+=("-only-testing:$test_id"); done
fi
BUNDLE_ID=com.mdd.kanpan
WORKSPACE=Kanpan.xcworkspace
SCHEME=Kanpan

DEVICES=(
  "iPhone 16 Pro"
  "iPhone 17 Pro Max"
)

mkdir -p "$OUT" "$RES"

if [ -n "$ONLY_DEVICE" ]; then
  found=0
  for name in "${DEVICES[@]}"; do [ "$name" = "$ONLY_DEVICE" ] && found=1; done
  [ "$found" -eq 1 ] || { echo "未知机型：$ONLY_DEVICE"; exit 2; }
fi

# 真机目标（P2.14）：DEVICE_UDID=<真机 UDID> 时不跑模拟器矩阵，改跑那一台真机。
#
# 开跑之前先用 `xcrun devicectl list devices` 看它的 `transportType`，只认 `wired`（数据线）。
# 无线调试 / 断开的真机上 XCUITest 常常卡在装包、附加调试器那一步，墙钟上限到了才判红，
# 整轮白等还看不出原因——所以不是数据线就当场退出，把原因说清楚。
# PREFLIGHT_ONLY=1 只做这道连接检查（退出码 0 = 能跑，3 = 不能跑），不编译不跑用例。
DEVICE_UDID="${DEVICE_UDID:-}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-}"
if [ -n "$DEVICE_UDID" ]; then
  devjson="$(mktemp -t kanpan-devicectl)"
  # JSON 落到临时文件：让它写 /dev/stdout 会混进人类可读那份，json.load 会报 Extra data。
  xcrun devicectl list devices --json-output "$devjson" > /dev/null 2>&1
  transport="$(python3 -c "import json,sys
d=json.load(open(sys.argv[1])).get('result',{}).get('devices',[])
x=next((x for x in d if x.get('hardwareProperties',{}).get('udid')==sys.argv[2]),None)
print('MISSING' if x is None else (x.get('connectionProperties',{}).get('transportType') or 'none'))" "$devjson" "$DEVICE_UDID" 2>/dev/null)"
  rm -f "$devjson"
  case "$transport" in
    wired)
      echo "真机 $DEVICE_UDID：数据线连接（transportType: wired），可以跑" ;;
    MISSING|"")
      echo "✗ 真机 $DEVICE_UDID 不在 xcrun devicectl list devices 的列表里（没配对或 UDID 写错了），不跑"
      exit 3 ;;
    *)
      echo "✗ 真机 $DEVICE_UDID 现在的连接方式是 transportType: $transport，不是数据线（wired）。"
      echo "  无线 / 断开的真机上 UI 用例会卡在装包或附加调试器那一步，跑了也是白等，所以不跑。"
      echo "  用数据线把手机插到这台 Mac、解锁并点「信任」之后再来。"
      exit 3 ;;
  esac
  [ -z "$PREFLIGHT_ONLY" ] || exit 0

  slug="device-$DEVICE_UDID"
  echo "== build-for-testing（真机）=="
  xcodebuild build-for-testing \
    -workspace "$WORKSPACE" -scheme "$SCHEME" \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DD" > "$OUT/build-device.log" 2>&1 || {
      echo "真机构建失败，见 $OUT/build-device.log"; tail -30 "$OUT/build-device.log"; exit 1; }
  rm -rf "$RES/$slug.xcresult"
  xcodebuild test-without-building \
    -workspace "$WORKSPACE" -scheme "$SCHEME" \
    -destination "platform=iOS,id=$DEVICE_UDID" \
    -derivedDataPath "$DD" \
    "${TEST_ARGS[@]}" \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 480 \
    -maximum-test-execution-time-allowance 900 \
    -resultBundlePath "$RES/$slug.xcresult" > "$OUT/$slug.log" 2>&1
  rc=$?
  echo "真机 $DEVICE_UDID：退出码 $rc，通过 $(grep -c "' passed (" "$OUT/$slug.log") 条，失败 $(grep -c "' failed (" "$OUT/$slug.log") 条，见 $OUT/$slug.log"
  exit $rc
fi

echo "== build-for-testing =="
$GUARD xcodebuild build-for-testing \
  -workspace "$WORKSPACE" -scheme "$SCHEME" \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DD" > "$OUT/build.log" 2>&1 || {
    echo "构建失败，见 $OUT/build.log"; tail -30 "$OUT/build.log"; exit 1; }

fail=0
: > "$OUT/summary.txt"
for name in "${DEVICES[@]}"; do
  [ -z "$ONLY_DEVICE" ] || [ "$name" = "$ONLY_DEVICE" ] || continue
  slug="$(echo "$name" | tr ' ()' '---' | tr -s '-' | sed 's/-$//')"
  device="$name$SUFFIX"                    # 查设备用带后缀的名字；slug（文件名）永远不带
  udid="$(xcrun simctl list devices available -j \
    | python3 -c "import json,sys;d=json.load(sys.stdin)['devices'];print(next((x['udid'] for v in d.values() for x in v if x['name']=='$device'),''))")"
  if [ -z "$udid" ]; then
    echo "✗ $device：模拟器不存在"; echo "$name	MISSING	0	0" >> "$OUT/summary.txt"; fail=1; continue
  fi
  echo "→ $device ($udid)"
  xcrun simctl bootstatus "$udid" -b > /dev/null 2>&1
  # 开跑之前把会自己醒过来的系统 app 关掉。2026-09-18 矩阵里 iPad Pro 11" 那条红就是
  # 照片（com.apple.mobileslideshow）在点「…」的那一秒抢到前台：XCUITest 的
  # "Check for interrupting elements" 卡在等它 idle，被测 app 掉到后台，再被 Open/Activate
  # 拉回来，那一下合成的点击就丢了（详见 ChartFoundationUITests.ensureForeground 的注释）。
  # 用例这边已经加了前台守卫能自愈，这里只是把撞上的概率先按下去。
  for sysapp in com.apple.mobileslideshow com.apple.Preferences com.apple.MobileSMS; do
    xcrun simctl terminate "$udid" "$sysapp" > /dev/null 2>&1 || true
  done
  xcrun simctl uninstall "$udid" "$BUNDLE_ID" > /dev/null 2>&1

  rm -rf "$RES/$slug.xcresult"
  start=$SECONDS
  # 单条用例的墙钟上限。2026-09-21 那一轮的教训：`AccountSessionReplacedUITests`
  # 在三台机器上挂住不返回（async 用例里 `continueAfterFailure = false` 靠 ObjC
  # 异常终止，异常穿不过 async 帧，之后第一个 await 再也没回来），一条用例分别吃掉
  # 7.1 / 4.5 / 5.4 小时，后面八十多条用例一条都没跑上，等于整条矩阵作废。
  # 用例那边的根因已经修掉，这里再上一道闸：**任何**一条用例卡住，XCTest 到点就判它
  # 超时、记一条红，然后接着跑下一条。全套最长的一条正常是 150s 上下
  # （`AccountPreferenceSyncUITests`），三条流水线并行时会慢一截，所以给到 480s。
  $GUARD xcodebuild test-without-building \
    -workspace "$WORKSPACE" -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "$DD" \
    "${TEST_ARGS[@]}" \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 480 \
    -maximum-test-execution-time-allowance 900 \
    -resultBundlePath "$RES/$slug.xcresult" > "$OUT/$slug.log" 2>&1
  rc=$?
  dur=$((SECONDS-start))
  # 跑完就关机。八台一路 boot 下来不关，最后那台常常被系统按内存压力 SIGTERM 掉
  # （实测 iPad Pro 11-inch 在第八位上被 Terminated: 15，日志停在 ** BUILD INTERRUPTED **）。
  xcrun simctl shutdown "$udid" > /dev/null 2>&1 || true
  passed=$(grep -c "' passed (" "$OUT/$slug.log")
  failed=$(grep -c "' failed (" "$OUT/$slug.log")
  if [ $rc -eq 0 ]; then
    echo "  ✓ ${passed} 条通过，${dur}s"
    echo "$name	PASS	$passed	$dur" >> "$OUT/summary.txt"
  else
    echo "  ✗ 失败 ${failed} 条（通过 ${passed}），见 $OUT/$slug.log"
    grep -E "error:|XCTAssert" "$OUT/$slug.log" | head -10
    echo "$name	FAIL	$passed/$failed	$dur" >> "$OUT/summary.txt"
    fail=1
  fi
done

echo
echo "================ 逐机型结果 ================"
column -t -s $'\t' "$OUT/summary.txt"
exit $fail
