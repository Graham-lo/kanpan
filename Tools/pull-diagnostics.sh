#!/usr/bin/env bash
# M9 诊断取件：把 app 攒下来的 MetricKit payload 和帧报告从沙盒里拖出来并汇总。
#
#   Tools/pull-diagnostics.sh                       # 从当前 booted 模拟器取
#   Tools/pull-diagnostics.sh <某台模拟器的 UDID>
#   Tools/pull-diagnostics.sh ~/Downloads/Kanpan.xcappdata   # 从真机下载下来的容器取
#
# 真机怎么拿容器（**必须你本人在 Xcode 里点**，命令行拿不到）：
#   Xcode ▸ Window ▸ Devices and Simulators ▸ 选 iPhone ▸ 选中 Kanpan
#   ▸ 齿轮 ▸ Download Container… ▸ 存成 Kanpan.xcappdata ▸ 把路径传给本脚本。
#
# 汇总结果写到 docs/acceptance/M9/：
#   diagnostics.json  —— 所有 payload 的原文 + 摘要（DiagnosticsBundle 的形状）
#   frames.json       —— 所有 FrameProbe 帧报告
# 终端上同时打一张人能看的表。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="com.yj27y32.hkline"
OUT="$ROOT/docs/acceptance/M9"
ARG="${1:-booted}"

# ---- 找到 Application Support/kanpan/Diagnostics ---------------------------
if [ -d "$ARG" ] && [ "$ARG" != "booted" ]; then
  # 下载下来的 .xcappdata 是个目录，真容器在 AppData/ 下面。
  CONTAINER="$ARG"
  [ -d "$CONTAINER/AppData" ] && CONTAINER="$CONTAINER/AppData"
else
  CONTAINER=$(xcrun simctl get_app_container "$ARG" "$BUNDLE" data 2>/dev/null || true)
  if [ -z "$CONTAINER" ]; then
    echo "取不到沙盒。要么模拟器没开 / 没装 app（先 make build + Tools/snap.sh），"
    echo "要么你要的是真机——那就在 Xcode 里 Download Container，把 .xcappdata 路径传进来。"
    exit 1
  fi
fi

DIAG="$CONTAINER/Library/Application Support/kanpan/Diagnostics"
# 老版本存在大写的 Kanpan/ 下（真机分大小写，下载下来的容器里可能两棵都有）。
# 新目录没有、老目录有，就读老的。
LEGACY="$CONTAINER/Library/Application Support/Kanpan/Diagnostics"
[ ! -d "$DIAG" ] && [ -d "$LEGACY" ] && DIAG="$LEGACY"
echo "→ 容器：$CONTAINER"
if [ ! -d "$DIAG" ]; then
  echo
  echo "这个容器里还没有 Diagnostics 目录。这本身就是一条信息，不是错误："
  echo "  · MetricKit 的 payload 每天最多一份，而且**只在下次启动时**才送达，"
  echo "    模拟器上更是永远不送——所以模拟器里这里空着是正常的。"
  echo "  · 帧报告要 app 里跑过一次 FrameProbe.record(...) 才会有。"
  exit 0
fi

mkdir -p "$OUT"
python3 - "$DIAG" "$OUT" <<'PY'
import json, os, sys, datetime

diag, out = sys.argv[1], sys.argv[2]

def load_dir(d):
    rows = []
    if not os.path.isdir(d):
        return rows
    for name in sorted(os.listdir(d)):
        if not name.endswith(".json"):
            continue
        try:
            with open(os.path.join(d, name)) as f:
                rows.append((name, json.load(f)))
        except Exception as e:
            print(f"   ! 读不了 {name}：{e}")
    return rows

records = load_dir(diag)
frames = load_dir(os.path.join(diag, "frames"))

def num(x, digits=1):
    return "—" if x is None else f"{x:.{digits}f}"

# ---------------------------------------------------------------- 诊断
crash = hang = 0
worst_launch = None
latest_writes = None
for _, r in records:
    d = r.get("digest") or {}
    for inc in d.get("incidents", []):
        if inc.get("category") == "crash":
            crash += 1
        elif inc.get("category") == "hang":
            hang += 1
    p50 = (d.get("launchTimeToFirstDrawMs") or {}).get("p50")
    if p50 is not None:
        worst_launch = p50 if worst_launch is None else max(worst_launch, p50)
    w = d.get("cumulativeLogicalWritesKB")
    if w is not None:
        latest_writes = w

bundle = {
    "schema": 1,
    "generatedAt": datetime.datetime.now(datetime.timezone.utc)
        .replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "recordCount": len(records),
    "crashCount": crash,
    "hangCount": hang,
    "worstLaunchP50Ms": worst_launch,
    "latestLogicalWritesKB": latest_writes,
    # 一条记录都没有时是 null，不是 true：「没收到」不等于「没崩过」。
    "crashFree": None if not records else crash == 0,
    "records": [r for _, r in records],
}
with open(os.path.join(out, "diagnostics.json"), "w") as f:
    json.dump(bundle, f, ensure_ascii=False, indent=2, sort_keys=True)

print()
print("== MetricKit ==")
print(f"  payload 份数      {len(records)}")
print(f"  崩溃 / 挂起       {crash} / {hang}")
print(f"  最坏启动 p50      {num(worst_launch)} ms   （任务书 §11：< 400ms）")
print(f"  最近日累计写盘    {num(latest_writes)} KB")
free = bundle["crashFree"]
print(f"  崩溃报告为空      "
      f"{'判不了（一份 payload 都没收到）' if free is None else ('是' if free else '否')}")
for name, r in records:
    d = r.get("digest") or {}
    inc = d.get("incidents", [])
    tag = "、".join(f"{i.get('category')}×1" for i in inc) or "无事件"
    # 诊断 payload 的版本号在每条事件里，不在顶层。
    ver = d.get("appVersion") or (inc[0].get("version") if inc else None) or "?"
    print(f"  · {name}  {ver}  {r.get('receivedAt','?')}  {tag}")

# ---------------------------------------------------------------- 帧
fb = {
    "schema": 1,
    "generatedAt": bundle["generatedAt"],
    "reports": [r for _, r in frames],
}
verdicts = [r.get("verdict", {}).get("allPassed") for _, r in frames]
fb["allPassed"] = None if not verdicts or all(v is None for v in verdicts) \
    else all(v for v in verdicts if v is not None)
with open(os.path.join(out, "frames.json"), "w") as f:
    json.dump(fb, f, ensure_ascii=False, indent=2, sort_keys=True)

print()
print("== 帧自测（FrameProbe）==")
if not frames:
    print("  还没有帧报告。app 里没跑过 FrameProbe.record(...)。")
else:
    print(f"  {'标签':<14}{'帧数':>6}{'实测Hz':>9}{'hitch占比':>11}"
          f"{'最长hitch':>11}{'绘制p50':>10}{'绘制p99':>10}  判定")
    for _, r in frames:
        w = r.get("work") or {}
        v = r.get("verdict") or {}
        ratio = r.get("hitchRatio")
        print(f"  {r.get('label','?'):<14}{r.get('frameCount',0):>6}"
              f"{num(r.get('measuredHz')):>9}"
              f"{('—' if ratio is None else f'{ratio*100:.2f}%'):>11}"
              f"{num(r.get('worstHitchMs')):>11}"
              f"{num(w.get('p50'), 2):>10}{num(w.get('p99'), 2):>10}"
              f"  {v.get('allPassed')}")
        print(f"    设备 {r.get('device','?')}")

print()
print(f"→ {os.path.join(out, 'diagnostics.json')}")
print(f"→ {os.path.join(out, 'frames.json')}")
PY
