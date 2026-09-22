#!/usr/bin/env bash
# A3.12 取证：静止时 DisplayLink 暂停 + CPU 占用 < 1%（任务书 M3 验收表最后一行）。
#
#   Tools/a3.12-cpu.sh            # CPU 那一轮：画一屏，静止 30 秒，Time Profiler 采样
#   Tools/a3.12-cpu.sh --probe    # DisplayLink 那一轮：1 Hz 读 ChartView 里那个 link
#   COMPARE=1 Tools/a3.12-cpu.sh # 同一夹具加三条对比线；DD 可指定独立构建目录
#
# 被测的是 Evidence/KanpanEvidenceHost——一个只有一个 ChartView、别的什么都不做的
# 最小宿主，隔开行情订阅与业务计时器，只量图表静止时的绘制开销。
#
# 为什么是 `--all-processes` 而不是 `--attach`：
#   xctrace 对模拟器进程 attach 会永久卡住（`--device <udid> --attach <pid>` 打完
#   "Attaching to..." 就再也不动，5 秒的限时等 5 分钟还在跑）；不带 --device 则报
#   "Cannot find process for provided pid"。模拟器进程在宿主机上是真实进程，
#   `--all-processes` 能连它们一起采到，事后按 pid 归并即可。实测 2026-09-14 / Xcode 26.6。
#
# 结果与说明见 docs/acceptance/M3/A3.12-cpu.md。
set -euo pipefail
GUARD="${GUARD:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/machine-guard.sh run}"  # 机器资源守门：排队 + nice，见 AGENTS.md「机器资源纪律」

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJ="$ROOT/Evidence/KanpanEvidenceHost/KanpanEvidenceHost.xcodeproj"
BUNDLE="com.mdd.kanpan.evidence"
DEVICE="${DEVICE:-iPhone 16 Pro}"
MODE="${1:-}"
OUT="${OUT:-$ROOT/docs/acceptance/M3}"
DD="${DD:-$ROOT/Evidence/KanpanEvidenceHost/.xcbuild}"
COMPARE_ARG=""
if [ "${COMPARE:-0}" = "1" ]; then COMPARE_ARG=1; fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

UDID="$(xcrun simctl list devices -j \
  | python3 -c 'import json,sys,os
d=json.load(sys.stdin)["devices"]
want=os.environ["DEVICE"]
for rt,ds in d.items():
  if "iOS" not in rt: continue
  for x in ds:
    if x["name"]==want and x["isAvailable"]:
      print(x["udid"]); raise SystemExit')"
[ -n "$UDID" ] || { echo "找不到模拟器：$DEVICE" >&2; exit 1; }
echo "→ 模拟器：$DEVICE ($UDID)"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

echo "→ 构建取证宿主"
$GUARD xcodebuild -project "$PROJ" -scheme KanpanEvidenceHost \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DD" \
  build | tail -3
APP="$DD/Build/Products/Debug-iphonesimulator/KanpanEvidenceHost.app"

xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

if [ "$MODE" = "--probe" ]; then
  echo "→ 探针轮：1 Hz 读 ChartView.link，约 40 秒"
  xcrun simctl launch --console-pty "$UDID" "$BUNDLE" --probe ${COMPARE_ARG:+--compare} 2>&1 \
    | grep --line-buffered '^A3.12|' | tee "$OUT/A3.12-displaylink.log"
  exit 0
fi

echo "→ CPU 轮：画一屏，静止 30 秒"
PID="$(xcrun simctl launch "$UDID" "$BUNDLE" ${COMPARE_ARG:+--compare} | awk -F': ' '{print $2}')"
echo "  pid=$PID"
perl -e 'select(undef,undef,undef,8)'          # 等它画完一屏并自行停掉 link
xcrun simctl io "$UDID" screenshot "$OUT/A3.12-screen.png"

cpu() { ps -o time= -p "$PID" | tr -d ' '; }
BEFORE="$(cpu)"
xcrun xctrace record --template 'Time Profiler' --all-processes \
  --time-limit 30s --no-prompt --output "$WORK/A3.12.trace" 2>/dev/null
AFTER="$(cpu)"

mkdir -p "$OUT/instruments"
rm -rf "$OUT/instruments/A3.12.trace"
cp -R "$WORK/A3.12.trace" "$OUT/instruments/A3.12.trace"   # .gitignore 不收 .trace

xcrun xctrace export --input "$WORK/A3.12.trace" --toc 2>/dev/null > "$WORK/toc.xml"
xcrun xctrace export --input "$WORK/A3.12.trace" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
  2>/dev/null > "$WORK/tp.xml"

PID="$PID" BEFORE="$BEFORE" AFTER="$AFTER" WORK="$WORK" OUT="$OUT" python3 - <<'PY'
import os, re, csv, collections
W, O = os.environ["WORK"], os.environ["OUT"]
pid = os.environ["PID"]
dur = float(re.search(r"<duration>([\d.]+)", open(W + "/toc.xml").read()).group(1))
d = open(W + "/tp.xml", encoding="utf-8", errors="replace").read()
names = {m.group(1): m.group(2) for m in re.finditer(r'<process id="(\d+)" fmt="([^"]*)"', d)}
cnt = collections.Counter()
for r in d.split("<row>")[1:]:
    i = r.find("<core"); seg = r[: i if i > 0 else len(r)]
    j = seg.rfind("<process")
    if j < 0: continue
    tag = seg[j : seg.find(">", j) + 1]
    m = re.search(r'(?:ref|id)="(\d+)"', tag)
    if m: cnt[names.get(m.group(1), "?")] += 1
host = next((k for k in cnt if f"({pid})" in k), None)
n = cnt.get(host, 0)
def sec(t):
    s = 0.0
    for x in t.split(":"): s = s * 60 + float(x)
    return s
delta = sec(os.environ["AFTER"]) - sec(os.environ["BEFORE"])
with open(O + "/A3.12-samples.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f); w.writerow(["process", "samples", "cpu_ms", "cpu_pct_of_wall"])
    # 被测进程永远排第一行，其余按采样数降序（后者只是 --all-processes 的副产物，
    # 用来证明这份 trace 确实在采样、确实覆盖到了模拟器侧）。
    w.writerow([host or f"KanpanEvidenceHost ({pid})", n, n, f"{n/10.0/dur:.3f}"])
    for k, c in cnt.most_common():
        if k == host: continue
        w.writerow([k, c, c, f"{c/10.0/dur:.3f}"])
print(f"  时长            {dur:.3f} s")
print(f"  本进程采样数     {n}（每采样 1.00 ms）")
print(f"  CPU%（Instruments）{n/10.0/dur:.3f} %")
print(f"  CPU%（ps）        {delta/dur*100:.3f} %（ps TIME 分辨率 10 ms，0.00 即 < {0.01/dur*100:.3f} %）")
print(f"  阈值 1% → {'通过' if n/10.0/dur < 1.0 and delta/dur*100 < 1.0 else '不通过'}")
PY

echo "→ trace：  $OUT/instruments/A3.12.trace"
echo "→ 采样表： $OUT/A3.12-samples.csv"
