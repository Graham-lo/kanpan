#!/bin/bash
# 交错冷启动测量：before=main(fa1850e) after=xchain-venue
out=/tmp/venue-s2perf
measure() { # label dir args...
  local label=$1 dir=$2; shift 2
  local root=/tmp/venue-cold-$label-$RANDOM
  rm -rf $root
  (cd $dir/KanpanData && swift run --skip-build kanpan-feed "$@" --minutes 0.25 --cache-root $root) > $out/$label.log 2>&1
  rm -rf $root
  python3 - "$out/$label.log" "$label" <<'PY'
import sys,re
def t(s):
    h,m,x=s.split(':'); return int(h)*3600+int(m)*60+float(x)
start=first=ws=None
for l in open(sys.argv[1]):
    m=re.match(r'\[(\d+:\d+:[\d.]+)\] (.*)',l)
    if not m: continue
    ts,msg=t(m.group(1)),m.group(2)
    if start is None and msg.startswith('开始'): start=ts
    if first is None and (msg.startswith('首屏') or msg.startswith('序列')): first=ts
    if ws is None and (msg.startswith('末根') or msg.startswith('标记价') or msg.startswith('行情')): ws=ts
f=lambda v: f"{(v-start)*1000:.0f}ms" if v and start else "—"
print(f"{sys.argv[2]:28s} 首屏 {f(first):>8s}  WS首帧 {f(ws):>8s}")
PY
}
export KANPAN_GATEWAYS=kanpan.107-174-172-10.sslip.io,kanpan.96-44-162-222.sslip.io:8443
B=/Users/mdd/zhk/kanpan-wt-xchain; A=/Users/mdd/zhk/kanpan-wt-xchain-venue
for r in 4 5 6 7; do
  measure before-direct-r$r $B BTCUSDT 1h
  measure after-direct-r$r $A BTCUSDT 1h
done
