#!/bin/bash
# M5 A5.1（界面对账）+ A5.2（事件到画完探针）+ A5.10（内存 / CPU）：iPhone 16 Pro 上 BTCUSDT 1m 开 30 分钟
set -u
DEV=D6C41248-C78E-46B8-B391-311F373D24A8
OUT=/tmp/kanpan-pchain-a510
APP=/Users/mdd/zhk/kanpan-wt-pchain/DerivedData/Build/Products/Debug-iphonesimulator/Kanpan.app
ts() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
xcrun simctl boot $DEV 2>/dev/null; xcrun simctl bootstatus $DEV -b >/dev/null
xcrun simctl terminate $DEV com.mdd.kanpan 2>/dev/null
xcrun simctl install $DEV "$APP"
PROFILE=$(uuidgen); echo "profile $PROFILE" > $OUT/meta.txt
SIMCTL_CHILD_KANPAN_TEST_PROFILE=1 SIMCTL_CHILD_KANPAN_PERSISTENCE_PROFILE=$PROFILE SIMCTL_CHILD_KANPAN_LOG=1 \
SIMCTL_CHILD_KANPAN_EVENT_DRAW_PROBE=1 SIMCTL_CHILD_KANPAN_TEST_INTERVAL=1m \
  xcrun simctl launch --console-pty $DEV com.mdd.kanpan 2>&1 | perl -MTime::HiRes=time -ne '$|=1; printf "%.3f %s", time, $_' > $OUT/app.log &
perl -e 'select(undef,undef,undef,20)'
PID=$(pgrep -f "CoreSimulator/Devices/$DEV/.*Kanpan.app/Kanpan" | head -1)
echo "app pid $PID start $(ts)" >> $OUT/meta.txt
echo "t_epoch rss_kb cputime pcpu" > $OUT/samples.txt
start=$(date +%s); i=0
while [ $(( $(date +%s) - start )) -lt 1830 ]; do
  now=$(date +%s)
  echo "$now $(ps -o rss=,time=,%cpu= -p $PID)" >> $OUT/samples.txt
  if [ $((i % 6)) -eq 0 ]; then
    n=$(printf %02d $((i/6)))
    t0=$(ts); xcrun simctl io $DEV screenshot $OUT/shot-$n.png >/dev/null 2>&1; t1=$(ts)
    echo "$n $t0 $t1 $(curl -s --max-time 3 'https://fapi.binance.com/fapi/v1/ticker/price?symbol=BTCUSDT')" >> $OUT/rest-at-shot.txt
  fi
  if [ $i -eq 2 ]; then ( xcrun xctrace record --template 'Activity Monitor' --all-processes --time-limit 60s --output $OUT/am-start.trace > $OUT/am-start.log 2>&1 & ) ; fi
  if [ $i -eq 56 ]; then ( xcrun xctrace record --template 'Activity Monitor' --all-processes --time-limit 60s --output $OUT/am-end.trace > $OUT/am-end.log 2>&1 & ) ; fi
  i=$((i+1))
  perl -e 'select(undef,undef,undef,30 - (time - '"$now"'))' 2>/dev/null
done
echo "end $(ts)" >> $OUT/meta.txt
C=$(xcrun simctl get_app_container $DEV com.mdd.kanpan data)
cp "$C/tmp/event-draw.json" $OUT/ 2>/dev/null
xcrun simctl terminate $DEV com.mdd.kanpan
echo done >> $OUT/meta.txt
