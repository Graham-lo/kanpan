#!/usr/bin/env bash
# 在指定模拟器上装 app、启动、浅深各截一张。
# 用法：snap.sh "iPhone 16 Pro" docs/acceptance/shots
set -euo pipefail

DEVICE="$1"
OUT="${2:-docs/acceptance/shots}"
APP="DerivedData/Build/Products/Debug-iphonesimulator/Kanpan.app"
BUNDLE="com.mdd.kanpan"

[ -d "$APP" ] || { echo "没找到 $APP，先跑 make build"; exit 1; }

slug=$(echo "$DEVICE" | tr ' ' '-' | tr -d '()')

udid=$(xcrun simctl list devices available -j | python3 -c "
import json,sys
for rt, ds in json.load(sys.stdin)['devices'].items():
    if 'iOS' not in rt: continue
    for x in ds:
        if x['name'] == '''$DEVICE''':
            print(x['udid']); raise SystemExit
")
[ -n "$udid" ] || { echo "模拟器 '$DEVICE' 不存在"; exit 1; }

state() { xcrun simctl list devices -j | python3 -c "
import json,sys
for ds in json.load(sys.stdin)['devices'].values():
    for x in ds:
        if x['udid'] == '$udid': print(x['state']); raise SystemExit
"; }

# Booting / Shutting Down 都是中间态，在上面做 install / launch 会报 code=405。
wait_for() {
  for _ in $(seq 120); do
    [ "$(state)" = "$1" ] && return 0
    sleep 1
  done
  echo "等 $DEVICE 进入 $1 超时，当前 $(state)"; return 1
}

# bootstatus 返回只代表内核起来了，SpringBoard 和显示表面还可能没就绪：
# 这时候 screenshot 会 NSPOSIXErrorDomain code=60「Timeout waiting for screen
# surfaces」，install 会 405。所以对外部命令统统重试。
retry() {
  local n=0
  until "$@" >/dev/null 2>&1; do
    n=$((n+1))
    [ $n -ge 30 ] && { echo "失败（重试 30 次）：$*"; return 1; }
    sleep 2
  done
}

echo "→ $DEVICE ($udid)"
if [ "$(state)" != "Booted" ]; then
  [ "$(state)" = "Shutdown" ] || { xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true; wait_for Shutdown; }
  xcrun simctl boot "$udid" >/dev/null
  wait_for Booted
fi
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true

# A0.2 要的「每台 boot 后截一张空桌面」：先回到浅色的干净主屏再截。
xcrun simctl ui "$udid" appearance light >/dev/null 2>&1 || true
retry xcrun simctl io "$udid" screenshot "$OUT/M0-${slug}-desktop.png"
echo "   ✓ $OUT/M0-${slug}-desktop.png"

retry xcrun simctl install "$udid" "$APP"

for mode in light dark; do
  xcrun simctl ui "$udid" appearance "$mode" >/dev/null 2>&1 || true
  xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1 || true
  retry xcrun simctl launch "$udid" "$BUNDLE"
  sleep 3
  retry xcrun simctl io "$udid" screenshot "$OUT/M0-${slug}-${mode}.png"
  echo "   ✓ $OUT/M0-${slug}-${mode}.png"
done

xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
