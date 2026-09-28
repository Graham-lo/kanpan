#!/bin/bash
# 升级回归：旧 tag 装包造数据 → 不卸载直接装当前包验证。
set -u
G=/Users/mdd/zhk/kanpan/scripts/machine-guard.sh
UDID=D6C41248-C78E-46B8-B391-311F373D24A8
O=/tmp/kanpan-stress-0928/upg
echo "== old build =="
cd /tmp/kanpan-oldtag
[ -n "${SKIP_OLD_BUILD:-}" ] || $G run xcodebuild build-for-testing -workspace Kanpan.xcworkspace -scheme Kanpan \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/kanpan-stress-0928/dd-old > $O/old-build.log 2>&1 || { echo OLD BUILD FAILED; tail -30 $O/old-build.log; exit 1; }
xcrun simctl bootstatus $UDID -b >/dev/null 2>&1
xcrun simctl uninstall $UDID com.yj27y32.hkline >/dev/null 2>&1
# 卸载不清钥匙串：上一轮的登录令牌会让老包一开就是登着的。
xcrun simctl keychain $UDID reset >/dev/null 2>&1
rm -f /tmp/kanpan-stress-0928/upgrade-state.txt
echo "== old seed =="
rm -rf $O/old.xcresult
$G run xcodebuild test-without-building -workspace Kanpan.xcworkspace -scheme Kanpan \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath /tmp/kanpan-stress-0928/dd-old \
  -only-testing:KanpanUITests/UpgradeSeedOldUITests -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 600 -maximum-test-execution-time-allowance 900 \
  -resultBundlePath $O/old.xcresult > $O/old-seed.log 2>&1
echo "old seed rc=$?"; grep -E "Test Case .*(passed|failed)|error:" $O/old-seed.log | tail -5
cat /tmp/kanpan-stress-0928/upgrade-state.txt 2>/dev/null || { echo NO STATE; xcrun simctl shutdown $UDID; exit 1; }
echo "== new verify (no uninstall) =="
cd /Users/mdd/zhk/kanpan
rm -rf $O/new.xcresult
$G run xcodebuild test-without-building -workspace Kanpan.xcworkspace -scheme Kanpan \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath /tmp/kanpan-stress-0928/dd \
  -only-testing:KanpanUITests/StressRegression0928UITests/testUpgradeFromBeforeTrimKeepsState -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 600 -maximum-test-execution-time-allowance 900 \
  -resultBundlePath $O/new.xcresult > $O/new-verify.log 2>&1
echo "new verify rc=$?"; grep -E "Test Case .*(passed|failed|skipped)|error:" $O/new-verify.log | tail -8
xcrun simctl shutdown $UDID >/dev/null 2>&1 || true
