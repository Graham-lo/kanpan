#!/usr/bin/env bash
# A0.2：把任务书要的八台机型在最新 iOS 运行时上备齐。
# 已经有的就不动，缺的用 simctl create 补。用法：Tools/ensure-devices.sh
set -euo pipefail

# 机型名 → devicetype 标识符。名字与原型 app.js 的 DEVICES 一一对应。
PAIRS=(
  "iPhone SE (3rd generation)|com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation"
  "iPhone 13 mini|com.apple.CoreSimulator.SimDeviceType.iPhone-13-mini"
  "iPhone 15|com.apple.CoreSimulator.SimDeviceType.iPhone-15"
  "iPhone 16 Pro|com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
  "iPhone Air|com.apple.CoreSimulator.SimDeviceType.iPhone-Air"
  "iPhone 16 Plus|com.apple.CoreSimulator.SimDeviceType.iPhone-16-Plus"
  "iPhone 17 Pro Max|com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"
  "iPad mini (A17 Pro)|com.apple.CoreSimulator.SimDeviceType.iPad-mini-A17-Pro"
)

# 取版本号最大的那个 iOS 运行时
RT=$(xcrun simctl list runtimes -j | python3 -c "
import json,sys
rs=[r for r in json.load(sys.stdin)['runtimes'] if r['isAvailable'] and r['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS')]
if not rs: raise SystemExit('没有可用的 iOS 运行时，先跑 xcodebuild -downloadPlatform iOS')
rs.sort(key=lambda r: [int(x) for x in r['version'].split('.')])
print(rs[-1]['identifier'])
")
echo "运行时：$RT"

have() {
  xcrun simctl list devices -j | python3 -c "
import json,sys
d=json.load(sys.stdin)['devices'].get('''$RT''',[])
print('yes' if any(x['name']=='''$1''' and x['isAvailable'] for x in d) else 'no')
"
}

for pair in "${PAIRS[@]}"; do
  name="${pair%%|*}"; dt="${pair##*|}"
  if [ "$(have "$name")" = yes ]; then
    echo "  = $name"
  else
    udid=$(xcrun simctl create "$name" "$dt" "$RT")
    echo "  + $name ($udid)"
  fi
done
