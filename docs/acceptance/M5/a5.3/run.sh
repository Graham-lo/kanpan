#!/bin/bash
# M5 A5.3（只断 app 的网 30 秒）+ A5.4（退后台 60 秒再回来）：iPhone 16 Pro，BTCUSDT 1m
set -u
DEV=D6C41248-C78E-46B8-B391-311F373D24A8
OUT=/tmp/kanpan-pchain-a53
APP=/Users/mdd/zhk/kanpan-wt-pchain/DerivedData/Build/Products/Debug-iphonesimulator/Kanpan.app
ts() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
wait_until() { perl -MTime::HiRes=time,sleep -e 'my $t=shift; sleep($t-time) if $t>time' "$1"; }
shot() { xcrun simctl io $DEV screenshot $OUT/$1.png >/dev/null 2>&1; echo "$1 $(ts)" >> $OUT/meta.txt; }
kbar() { C=$(xcrun simctl get_app_container $DEV com.mdd.kanpan data); f=$(find "$C/Library/Caches/kanpan/tests/$PROFILE" -name 'BTCUSDT@m1.kbar' | head -1); cp "$f" $OUT/$1.kbar; echo "$1 $(ts) $f" >> $OUT/meta.txt; }
xcrun simctl boot $DEV 2>/dev/null; xcrun simctl bootstatus $DEV -b >/dev/null
xcrun simctl terminate $DEV com.mdd.kanpan 2>/dev/null
xcrun simctl install $DEV "$APP"
T0=$(date +%s); OSTART=$((T0 + 100))
PROFILE=$(uuidgen); echo "profile $PROFILE launch $T0 outage $OSTART:30" > $OUT/meta.txt

SIMCTL_CHILD_KANPAN_TEST_PROFILE=1 SIMCTL_CHILD_KANPAN_PERSISTENCE_PROFILE=$PROFILE SIMCTL_CHILD_KANPAN_LOG=1 \
SIMCTL_CHILD_KANPAN_TEST_INTERVAL=1m SIMCTL_CHILD_KANPAN_TEST_NET_OUTAGE=$OSTART:30 \
  xcrun simctl launch --console-pty $DEV com.mdd.kanpan 2>&1 | perl -MTime::HiRes=time -ne '$|=1; printf "%.3f %s", time, $_' > $OUT/app.log &
wait_until $((OSTART - 5)); shot a53-1-断网前
wait_until $((OSTART + 15)); shot a53-2-断网中
wait_until $((OSTART + 31)); shot a53-3-刚恢复
wait_until $((OSTART + 60)); shot a53-4-恢复30秒后
wait_until $((OSTART + 100)); kbar a53-after
# A5.4：切到「设置」让看盘退后台 60 秒，再切回来
BG=$((OSTART + 110)); wait_until $BG; shot a54-1-退后台前
xcrun simctl launch $DEV com.apple.Preferences >/dev/null; echo "bg $(ts)" >> $OUT/meta.txt
wait_until $((BG + 60)); xcrun simctl launch $DEV com.mdd.kanpan >/dev/null; echo "fg $(ts)" >> $OUT/meta.txt
wait_until $((BG + 61)); shot a54-2-回前台1秒
wait_until $((BG + 65)); shot a54-3-回前台5秒
wait_until $((BG + 125)); shot a54-4-回前台1分钟; kbar a54-after
xcrun simctl terminate $DEV com.mdd.kanpan
echo done $(ts) >> $OUT/meta.txt
