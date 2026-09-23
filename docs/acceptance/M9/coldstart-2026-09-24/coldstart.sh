#!/bin/bash
# M9 冷启动逐帧：同一档案先暖一次（让快照缓存落盘），然后 10 次「杀进程 → 录屏 → 冷启动 3 秒」。
set -u
DEV=${DEV:-D6C41248-C78E-46B8-B391-311F373D24A8}
OUT=${OUT:-/tmp/kanpan-pchain-m9/run}
PROFILE=${PROFILE:-$(uuidgen)}
BID=com.mdd.kanpan
mkdir -p $OUT
ts() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
export SIMCTL_CHILD_KANPAN_TEST_PROFILE=1 SIMCTL_CHILD_KANPAN_PERSISTENCE_PROFILE=$PROFILE
echo "profile $PROFILE" > $OUT/times.txt
# 暖机：第一次装机后的首启（无缓存），记下来但不计入中位数
xcrun simctl terminate $DEV $BID 2>/dev/null
xcrun simctl launch $DEV $BID >/dev/null; perl -e 'select(undef,undef,undef,15)'
for i in $(seq -w 0 10); do
  xcrun simctl terminate $DEV $BID 2>/dev/null
  perl -e 'select(undef,undef,undef,3)'
  rm -f $OUT/cold-$i.mp4
  ( xcrun simctl io $DEV recordVideo --codec h264 --force $OUT/cold-$i.mp4 2>&1 | while IFS= read -r line; do echo "$(ts) $line"; done > $OUT/rec-$i.log ) &
  # 等录屏真的开始
  for k in $(seq 1 50); do grep -q "Recording started" $OUT/rec-$i.log 2>/dev/null && break; perl -e 'select(undef,undef,undef,0.1)'; done
  perl -e 'select(undef,undef,undef,0.5)'
  t0=$(ts); xcrun simctl launch $DEV $BID >/dev/null; t1=$(ts)
  perl -e 'select(undef,undef,undef,3.5)'
  pkill -INT -f "recordVideo --codec h264 --force $OUT/cold-$i.mp4"
  perl -e 'select(undef,undef,undef,1.5)'
  echo "$i launch_cmd_start=$t0 launch_cmd_end=$t1 rec_started=$(grep 'Recording started' $OUT/rec-$i.log | head -1 | cut -d' ' -f1)" >> $OUT/times.txt
done
xcrun simctl terminate $DEV $BID 2>/dev/null
