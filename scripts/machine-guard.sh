#!/usr/bin/env bash
# scripts/machine-guard.sh — 看盘：机器资源守门（2026-09-23 起）
#
# 为什么有这个东西：
#   这台 Mac 是 10 核 / 16 GB 的 M4，磁盘 460 GB。2026-09-23 中午同时开着 5 台模拟器、
#   4 个 xcodebuild（40 个 swift-frontend）、一台上限 10 GB 的 Docker 虚拟机和 8 个 Claude
#   会话：负载 54、交换区 12 GB 满、磁盘只剩 15 GB（其中 117 GB 是 57 台模拟器攒的数据）。
#   交换区没地方长，macOS 就开始强杀进程，Surge / ChatGPT / Claude 跟着崩，任务反而更慢，
#   用户只能手动停任务。用户的话：「不能再交给 mac 本身处理」。
#
#   所以把三件事收成一个脚本：
#     1. 预算：构建槽按点数记（重活 2 点、轻活 1 点，基础 BUILD_POINTS=4、空闲时 BURST_POINTS=6）、
#        最多 MAX_SIMS 台开机模拟器，磁盘至少 MIN_DISK_GB，交换区不超 MAX_SWAP_MB。
#        重活用 `run` 包着跑就会自动排队、自动 nice；本会话若困在后台节流带（遥控宿主
#        ProcessType=Background 继承下来的，只能用能效核）就交给 launchd 起，跑在正常带上；
#        Makefile 与 Tools 里的 xcodebuild / swift 已经包好。
#     2. 看门狗：launchd 每 60 秒 `tick`——受保护应用掉了就拉起、超预算又没人用的模拟器
#        关掉、孤儿构建进程杀掉、Docker 没人用就退出、编译一律降优先级、磁盘告急且没有
#        构建在跑时自动清可再生产物。
#     3. 清理：`clean` 只删能重新生成的东西（DerivedData、.build、cargo target、/tmp 构建目录、
#        关机状态模拟器里攒的数据），从不动源码、证据、TestFlight 归档与线上服务。
#
# 用法（仓库根）：
#   scripts/machine-guard.sh status                 看一眼机器；派子代理、起重活之前先跑这个
#   scripts/machine-guard.sh check                  超预算就非零退出并说明原因
#   scripts/machine-guard.sh run xcodebuild ...     占一个构建槽再跑（Makefile 已包好，直接 make）
#   scripts/machine-guard.sh sim-gc                 关掉超预算且没人引用的模拟器
#   scripts/machine-guard.sh zombie-gc              杀掉父进程已死的构建 / 模拟器残留进程
#   scripts/machine-guard.sh docker-gc              没人连 Postgres 就退出 Docker（要用时 open -a Docker）
#   scripts/machine-guard.sh clean [--sims]         删可再生产物；--sims 连关机模拟器的数据一起重置
#   scripts/machine-guard.sh protect                Surge / ChatGPT / Claude / remote-control 掉了就拉起
#   scripts/machine-guard.sh install-watchdog       装 launchd 看门狗（每 60 秒 tick）
#   scripts/machine-guard.sh uninstall-watchdog
#
# 预算都能用环境变量临时覆盖：BUILD_POINTS=6 scripts/machine-guard.sh run ...
# 动态预算：空闲内存 ≥ 35%、交换区 ≤ 4 GB、CPU 空闲 ≥ 25% 三项同时达标时，槽位自动放宽到
# BURST_POINTS=6 点（= 3 个重活）；空闲内存 ≥ 50% 再放到 BURST2_POINTS=8 点；任一项掉下去就回到基础预算（不打断在跑的）。
# 临时关掉「拉起受保护应用」：touch /tmp/kanpan-guard/protect.off

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE=/tmp/kanpan-guard
mkdir -p "$STATE/slots"
LOG="$STATE/guard.log"

# 构建槽按「点数」记：重活（xcodebuild 跑测试 / 带模拟器目标的构建，要占一台模拟器 ≈ 2.5 GB）
# 记 2 点，轻活（swift build|test、cargo、不带模拟器的 xcodebuild build，≈ 0.5–1 GB）记 1 点。
# 基础 4 点 = 2 个重活，或 1 重 + 2 轻，或 4 轻；09-23 实测 16 GB 机器上 3 重 + 2 台模拟器
# 就把空闲内存压到 31%、交换区往上长，所以放宽档也只到 6 点。
BUILD_POINTS=${BUILD_POINTS:-4}
HEAVY_WEIGHT=${HEAVY_WEIGHT:-2}
LIGHT_WEIGHT=${LIGHT_WEIGHT:-1}
MAX_SIMS=${MAX_SIMS:-2}
# 机器明显空闲时动态放宽到下面这档（内存、交换区、CPU 空闲三项同时达标才算空闲）；
# 压力一上来新槽就不再发，已经在跑的不打断。模拟器只维护两台，所以放宽档也是 2。
BURST_POINTS=${BURST_POINTS:-6}
BURST_SIMS=${BURST_SIMS:-2}
BURST_MIN_FREE_MEM_PCT=${BURST_MIN_FREE_MEM_PCT:-35}
BURST_MAX_SWAP_MB=${BURST_MAX_SWAP_MB:-4096}
BURST_MIN_CPU_IDLE_PCT=${BURST_MIN_CPU_IDLE_PCT:-25}
# 用户 09-23 傍晚：「在保证不崩溃的情况下最大限度使用资源，不要浪费」。所以再加一档：
# 空闲内存 ≥ 50%（交换区门槛与第一档相同——交换区已用量是高峰留下的滞后指标，不拿它单独卡第二档）时放到 8 点
# （= 4 个重活）。红线（MIN_FREE_MEM_PCT / MAX_SWAP_MB / MIN_DISK_GB）不动，它们才是防崩溃的那道。
BURST2_POINTS=${BURST2_POINTS:-8}
BURST2_MIN_FREE_MEM_PCT=${BURST2_MIN_FREE_MEM_PCT:-50}
BURST2_MAX_SWAP_MB=${BURST2_MAX_SWAP_MB:-4096}
MIN_DISK_GB=${MIN_DISK_GB:-40}
MAX_SWAP_MB=${MAX_SWAP_MB:-8192}
MIN_FREE_MEM_PCT=${MIN_FREE_MEM_PCT:-12}
SLOT_WAIT_SEC=${SLOT_WAIT_SEC:-2400}
SIM_GRACE_SEC=${SIM_GRACE_SEC:-600}
DOCKER_IDLE_TICKS=${DOCKER_IDLE_TICKS:-10}   # Docker 连续几次巡检（分钟）没人连 Postgres 就退出
BUILD_NICE=${BUILD_NICE:-10}
PROTECTED_APPS=(Surge ChatGPT Claude)
REMOTE_CONTROL_CMD="claude --dangerously-skip-permissions remote-control --name kanpan --permission-mode bypassPermissions"

rc_alive() { ps -Aeo args 2>/dev/null | grep -v grep | grep -q 'remote-control --name kanpan'; }
log() { printf '%s %s\n' "$(date '+%m-%d %H:%M:%S')" "$*" >> "$LOG"; }
say() { printf '%s\n' "$*"; }

# ---------------------------------------------------------------- 读数
disk_free_gb()  { df -k /System/Volumes/Data | awk 'NR==2{printf "%d",$4/1048576}'; }
swap_used_mb()  { sysctl -n vm.swapusage | sed -n 's/.*used = \([0-9]*\)\.[0-9]*M.*/\1/p'; }
free_mem_pct()  { memory_pressure 2>/dev/null | sed -n 's/.*free percentage: \([0-9]*\)%.*/\1/p'; }
load1()         { sysctl -n vm.loadavg | awk '{print $2}' | cut -d. -f1; }
build_pids()    { { pgrep -x xcodebuild; pgrep -x swift-build; pgrep -x swift-test; pgrep -x cargo; } 2>/dev/null; }
build_count()   { build_pids | wc -l | tr -d ' '; }
booted_sims()   { xcrun simctl list devices booted -j 2>/dev/null | python3 -c '
import json,sys
for v in json.load(sys.stdin)["devices"].values():
    for d in v:
        if d["state"]=="Booted": print(d["udid"]+"\t"+d["name"])'; }
booted_count()  { booted_sims | grep -c . ; }
slots_in_use()  { reap_slots; ls -1 "$STATE/slots" 2>/dev/null | wc -l | tr -d ' '; }
cpu_idle_pct()  { top -l 2 -n 0 -s 1 2>/dev/null | grep 'CPU usage' | tail -n 1 | sed -n 's/.* \([0-9]*\)\.[0-9]*% idle.*/\1/p'; }

# ---------------------------------------------------------------- 动态预算
burst_ok() {  # 机器空闲：内存、交换区、CPU 空闲三项都达标
  local mem swap idle
  mem=$(free_mem_pct); swap=$(swap_used_mb); idle=$(cpu_idle_pct)
  [ "${mem:-0}" -ge "$BURST_MIN_FREE_MEM_PCT" ] && [ "${swap:-99999}" -le "$BURST_MAX_SWAP_MB" ] && [ "${idle:-0}" -ge "$BURST_MIN_CPU_IDLE_PCT" ]
}
burst2_ok() {  # 机器非常空：在 burst_ok 之上，空闲内存再 ≥ BURST2_MIN_FREE_MEM_PCT、交换区 ≤ BURST2_MAX_SWAP_MB
  local mem swap
  mem=$(free_mem_pct); swap=$(swap_used_mb)
  [ "${mem:-0}" -ge "$BURST2_MIN_FREE_MEM_PCT" ] && [ "${swap:-99999}" -le "$BURST2_MAX_SWAP_MB" ]
}
max_points_now() { if burst_ok; then if burst2_ok; then echo "$BURST2_POINTS"; else echo "$BURST_POINTS"; fi; else echo "$BUILD_POINTS"; fi; }
max_sims_now()   { if burst_ok; then echo "$BURST_SIMS";   else echo "$MAX_SIMS";   fi; }
job_weight() {  # 这条命令算重活还是轻活
  local a="$*"
  case "$a" in
    *xcodebuild*test*|*xcodebuild*build-for-testing*) echo "$HEAVY_WEIGHT" ;;
    *xcodebuild*Simulator*|*xcodebuild*'id='*)         echo "$HEAVY_WEIGHT" ;;
    *) echo "$LIGHT_WEIGHT" ;;
  esac
}
points_in_use() {  # 活着的槽的点数之和；老格式的槽没有 weight 文件，按重活算
  reap_slots
  local s t=0
  for s in "$STATE"/slots/*/; do [ -d "$s" ] || continue; t=$((t + $(cat "$s/weight" 2>/dev/null || echo "$HEAVY_WEIGHT"))); done
  echo "$t"
}

# ---------------------------------------------------------------- 构建槽
slot_dead() {  # 槽目录里的 pid 没了，或者目录建了 60 秒还没写 pid
  local s="$1"
  if [ -f "$s/pid" ]; then ! kill -0 "$(cat "$s/pid")" 2>/dev/null
  else [ -n "$(find "$s" -maxdepth 0 -mmin +1 2>/dev/null)" ]; fi
}
reap_slots() { local s; for s in "$STATE"/slots/*/; do [ -d "$s" ] || continue; slot_dead "$s" && rm -rf "$s"; done; }
acquire_slot() {
  local w cap used s lock="$STATE/slots.lock" i
  w=$(job_weight "$@"); cap=$(max_points_now)   # 读 CPU 要两秒，放在锁外面
  for i in 1 2 3 4 5; do mkdir "$lock" 2>/dev/null && break; sleep 1; done
  [ -d "$lock" ] || return 1
  [ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ] && rmdir "$lock" 2>/dev/null && mkdir "$lock" 2>/dev/null  # 上一个持锁者死了
  used=$(points_in_use)
  if [ $((used + w)) -le "$cap" ]; then
    s="$STATE/slots/$$-$(date +%s)"
    mkdir "$s" && { echo $$ > "$s/pid"; printf '%s\n' "$*" > "$s/cmd"; echo "$w" > "$s/weight"; SLOT="$s"; rmdir "$lock"; return 0; }
  fi
  rmdir "$lock" 2>/dev/null
  return 1
}

pressure_reasons() {  # 打印超预算的原因，空则正常
  local free swap mem
  free=$(disk_free_gb); swap=$(swap_used_mb); mem=$(free_mem_pct)
  [ "${free:-0}" -ge "$MIN_DISK_GB" ]        || say "磁盘只剩 ${free} GB（预算 ≥ ${MIN_DISK_GB}），交换区没地方长"
  [ "${swap:-0}" -le "$MAX_SWAP_MB" ]        || say "交换区已用 ${swap} MB（预算 ≤ ${MAX_SWAP_MB}）"
  [ "${mem:-100}" -ge "$MIN_FREE_MEM_PCT" ]  || say "空闲内存只剩 ${mem}%（预算 ≥ ${MIN_FREE_MEM_PCT}%）"
}

# ---------------------------------------------------------------- 子命令
cmd_status() {
  local free swap mem ld b s idle mb ms mode
  free=$(disk_free_gb); swap=$(swap_used_mb); mem=$(free_mem_pct); ld=$(load1); b=$(build_count); s=$(booted_count); idle=$(cpu_idle_pct)
  mb=$(max_points_now); ms=$(max_sims_now)
  case "$mb" in
    "$BURST2_POINTS") mode="机器很空（内存 ≥ ${BURST2_MIN_FREE_MEM_PCT}%、交换 ≤ ${BURST2_MAX_SWAP_MB} MB），放宽到 ${BURST2_POINTS} 点" ;;
    "$BURST_POINTS")  mode="机器空闲，放宽到 ${BURST_POINTS} 点" ;;
    *)                mode="基础 ${BUILD_POINTS} 点" ;;
  esac
  say "负载 ${ld}（10 核）  CPU 空闲 ${idle}%  空闲内存 ${mem}%  交换区 ${swap} MB / 预算 ${MAX_SWAP_MB}  磁盘空闲 ${free} GB / 预算 ${MIN_DISK_GB}"
  say "重编译进程 ${b}  构建槽 $(points_in_use)/${mb} 点（重活 ${HEAVY_WEIGHT} 点、轻活 ${LIGHT_WEIGHT} 点；${mode}）  开机模拟器 ${s}/${ms}"
  say "  放宽条件：空闲内存 ≥ ${BURST_MIN_FREE_MEM_PCT}%、交换区 ≤ ${BURST_MAX_SWAP_MB} MB、CPU 空闲 ≥ ${BURST_MIN_CPU_IDLE_PCT}% 三项同时达标"
  local d; for d in "$STATE"/slots/*/; do [ -d "$d" ] && say "  槽 $(cat "$d/weight" 2>/dev/null || echo "$HEAVY_WEIGHT")点 pid $(cat "$d/pid" 2>/dev/null): $(head -c 100 "$d/cmd" 2>/dev/null)"; done
  booted_sims | sed 's/^/  开机: /'
  local app; for app in "${PROTECTED_APPS[@]}"; do pgrep -xq "$app" && say "  $app 在" || say "  $app 不在！"; done
  rc_alive && say "  claude remote-control 在" || say "  claude remote-control 不在！"
  [ -f "$STATE/ALERT" ] && { say "告警:"; sed 's/^/  /' "$STATE/ALERT"; }
  local r; r=$(pressure_reasons); [ -z "$r" ] || { say "超预算:"; say "$r" | sed 's/^/  /'; }
  return 0
}

cmd_check() {
  local r mb ms; r=$(pressure_reasons); mb=$(max_points_now); ms=$(max_sims_now)
  [ "$(points_in_use)" -lt "$mb" ] || r="${r}${r:+$'\n'}构建槽已占满 $(points_in_use)/${mb} 点（$(build_count) 个重编译在跑）"
  [ "$(booted_count)" -lt "$ms" ]  || r="${r}${r:+$'\n'}已有 $(booted_count) 台模拟器开着（当前预算 ${ms}）"
  if [ -n "$r" ]; then say "机器超预算，先别起重活："; say "$r" | sed 's/^/  /'; return 1; fi
  say "机器在预算内"; return 0
}

cmd_run() {
  [ $# -gt 0 ] || { say "用法: machine-guard.sh run <命令...>"; return 2; }
  # 已经在一个槽里（Makefile 目标套 Tools 脚本这种嵌套）就直接跑，不再占第二个槽，免得互相等死
  if [ -n "${KANPAN_GUARD_SLOT:-}" ]; then exec nice -n "$BUILD_NICE" "$@"; fi
  local free; free=$(disk_free_gb)
  if [ "$free" -lt "$MIN_DISK_GB" ]; then
    say "[guard] 磁盘只剩 ${free} GB，先清可再生产物"; cmd_clean --sims
    free=$(disk_free_gb)
    [ "$free" -ge "$MIN_DISK_GB" ] || { say "[guard] 清完还是只有 ${free} GB，拒绝起编译（交换区会把 macOS 逼到杀进程）。跑 scripts/machine-guard.sh status 看看谁占着"; return 3; }
  fi
  local waited=0 said=0
  until acquire_slot "$@"; do
    [ "$waited" -lt "$SLOT_WAIT_SEC" ] || { say "[guard] 等构建槽等了 ${SLOT_WAIT_SEC}s 还没轮到，放弃。占着的："; ls "$STATE/slots"; return 4; }
    [ "$said" -eq 1 ] || { say "[guard] 构建槽已满（已用 $(points_in_use) 点，这条活要 $(job_weight "$@") 点；预算 ${BUILD_POINTS} 点，机器空闲时放宽到 ${BURST_POINTS}），排队等槽…"; said=1; }
    sleep 15; waited=$((waited+15))
  done
  trap 'rm -rf "$SLOT"' EXIT INT TERM HUP
  local r
  while r=$(pressure_reasons); [ -n "$r" ]; do
    [ "$waited" -lt "$SLOT_WAIT_SEC" ] || { say "[guard] 机器压力一直没降下来，放弃："; say "$r"; return 5; }
    [ "$said" -eq 2 ] || { say "[guard] 机器超预算，占着槽等压力降下来："; say "$r" | sed 's/^/  /'; said=2; }
    sleep 15; waited=$((waited+15))
  done
  local rc
  if in_throttle_band && [ -z "${KANPAN_GUARD_DIRECT:-}" ]; then
    log "run 槽$(basename "$SLOT") $(cat "$SLOT/weight")点 pid $$ 经 launchd（本会话在后台节流带）: $*"
    run_via_launchd "$@"; rc=$?
  else
    log "run 槽$(basename "$SLOT") $(cat "$SLOT/weight")点 pid $$: $*"
    KANPAN_GUARD_SLOT="$SLOT" nice -n "$BUILD_NICE" "$@"; rc=$?
  fi
  log "done 槽$(basename "$SLOT") rc=$rc"
  return $rc
}

# ---------------------------------------------------------------- 后台节流带
# 09-23 查「任务慢了很多」的根因：遥控宿主的 LaunchAgent（~/Library/LaunchAgents/
# com.mdd.kanpan.remote-control.plist）写着 ProcessType=Background，宿主和它下面所有 Claude
# 会话、会话起的每个 xcodebuild / swift-frontend 都继承进 macOS 的后台节流带（ps -o pri 显示 4，
# taskpolicy / setpriority / launchctl asuser 都出不来），Apple Silicon 只让这一带用 6 个能效核，
# 4 个性能核一直空着（CPU 空闲常年 35–40% 就是这个）。同一段 CPU 循环：会话里 5.64 s，
# launchd 起的 0.53 s。nice 0 / 10 / 20 在带里毫无区别。
# 出路：让 launchd 替我们起进程（launchctl submit 起的是正常带 pri 20），这里把当前目录、
# 环境变量和命令原样写进一个包装脚本交给 launchd，尾随它的输出、轮询它退出、取回退出码。
# 包装脚本里仍然 renice 到 BUILD_NICE，Surge / ChatGPT / Claude 照旧比编译优先。
# plist 本身已改成 ProcessType=Standard，宿主下次重启后会话本身也不在带里了，那时这条路自动不走。
in_throttle_band() { local p; p=$(ps -o pri= -p $$ 2>/dev/null | tr -d ' '); [ -n "$p" ] && [ "$p" -lt 10 ]; }

run_via_launchd() {
  local label="kanpan-run-$$-$(date +%s)" dir="$STATE/launchd"
  mkdir -p "$dir"
  local wrap="$dir/$label.sh" out="$dir/$label.out"
  {
    echo '#!/bin/bash'
    echo "cd $(printf '%q' "$PWD") || exit 97"
    export -p | grep -vE '^declare -x (_|OLDPWD|PWD|SHLVL|PS1|BASH_[A-Z_]*|KANPAN_GUARD_SLOT)='
    echo "export KANPAN_GUARD_SLOT=$(printf '%q' "$SLOT")"
    echo "renice $BUILD_NICE -p \$\$ >/dev/null 2>&1"
    printf 'exec'; printf ' %q' "$@"; echo
  } > "$wrap"
  chmod +x "$wrap"; : > "$out"
  LAUNCHD_LABEL="$label"
  trap 'launchctl remove "$LAUNCHD_LABEL" >/dev/null 2>&1; rm -rf "$SLOT"' EXIT INT TERM HUP
  launchctl submit -l "$label" -o "$out" -e "$out" -- /bin/bash "$wrap" || { say "[guard] launchctl submit 失败，改为直接跑"; KANPAN_GUARD_SLOT="$SLOT" nice -n "$BUILD_NICE" "$@"; return $?; }
  tail -n +1 -f "$out" & local tp=$!
  local line pid st rc=1
  while :; do
    line=$(launchctl list 2>/dev/null | awk -v l="$label" '$3==l')
    pid=$(printf '%s' "$line" | awk '{print $1}'); st=$(printf '%s' "$line" | awk '{print $2}')
    if [ -z "$line" ]; then rc=99; break; fi
    if [ "$pid" = "-" ]; then rc=$st; break; fi
    sleep 2
  done
  sleep 1; kill "$tp" >/dev/null 2>&1; wait "$tp" 2>/dev/null
  launchctl remove "$label" >/dev/null 2>&1; LAUNCHD_LABEL=""
  rm -f "$wrap" "$out"
  [ "$rc" -ge 0 ] 2>/dev/null || { say "[guard] 构建被信号 $((-rc)) 终止"; rc=$((128-rc)); }
  return "$rc"
}

sim_referenced() {  # 有没有构建 / 测试 / simctl 进程正提着这台模拟器（按 UDID 或名字）
  local udid="$1" name="$2"
  ps -Aeo args 2>/dev/null | grep -E 'xcodebuild|xctest|simctl|-Runner|Kanpan\.app|KanpanEvidenceHost' \
    | grep -v machine-guard | grep -qE -- "$udid|name=$name([,' ]|$)"
}
sim_age_sec() {  # macOS 的 ps 没有 etimes，只有 [[dd-]hh:]mm:ss 形式的 etime，自己换算成秒
  ps -Aeo etime,args 2>/dev/null | grep launchd_sim | grep -F "$1" | awk '{print $1}' | head -n 1 | awk -F'[-:]' '
    { n=NF; s=$n; m=(n>=2)?$(n-1):0; h=(n>=3)?$(n-2):0; d=(n>=4)?$(n-3):0; print d*86400+h*3600+m*60+s }'
}

cmd_sim_gc() {
  local mem count line udid name age list="" max_sims
  mem=$(free_mem_pct); count=$(booted_count); max_sims=$(max_sims_now)
  while IFS=$'\t' read -r udid name; do
    [ -n "$udid" ] || continue
    sim_referenced "$udid" "$name" && continue
    age=$(sim_age_sec "$udid"); [ "${age:-0}" -ge "$SIM_GRACE_SEC" ] || continue
    list="${list}${age}\t${udid}\t${name}\n"
  done < <(booted_sims)
  [ -n "$list" ] || return 0
  printf '%b' "$list" | sort -rn | while IFS=$'\t' read -r age udid name; do
    if [ "$count" -gt "$max_sims" ] || [ "${mem:-100}" -lt "$MIN_FREE_MEM_PCT" ]; then
      xcrun simctl shutdown "$udid" >/dev/null 2>&1 && { say "[guard] 关掉闲置模拟器 $name（开了 $((age/60)) 分钟没人用）"; log "sim-gc 关 $name"; count=$((count-1)); }
    fi
  done
}

cmd_clean() {
  local sims=0; [ "${1:-}" = "--sims" ] && sims=1
  local before; before=$(disk_free_gb)
  # 守门自己的状态目录（构建槽锁）和 kanpan-guard-aside（rebase 时挪开的文件）不能删
  find /tmp -maxdepth 1 \( -name 'kanpan-*' -o -name 'p[0-9]-*' \) ! -name 'kanpan-guard*' -exec rm -rf {} + 2>/dev/null
  rm -rf "$HOME/Library/Developer/Xcode/DerivedData"/* "$HOME/Library/Caches/org.swift.swiftpm" 2>/dev/null
  # DerivedData-archive 是 TestFlight 归档与 dSYM（docs/testflight-uploads.md 按它算 90 天保留期），不删
  find "$ROOT" -maxdepth 3 -type d \( -name .build -o -name '.xcbuild*' -o \( -name 'DerivedData*' ! -name DerivedData-archive \) \) -prune -exec rm -rf {} + 2>/dev/null
  rm -rf "$ROOT/Backend/kanpan-api/target" 2>/dev/null
  if [ "$sims" -eq 1 ]; then
    xcrun simctl list devices -j 2>/dev/null | python3 -c '
import json,sys,subprocess
for v in json.load(sys.stdin)["devices"].values():
    for d in v:
        if d["state"]=="Shutdown": subprocess.run(["xcrun","simctl","erase",d["udid"]],capture_output=True)'
  fi
  say "[guard] 清理完成：磁盘空闲 ${before} GB → $(disk_free_gb) GB"; log "clean sims=$sims ${before}→$(disk_free_gb)GB"
}

cmd_protect() {
  [ -f "$STATE/protect.off" ] && return 0
  local app
  for app in "${PROTECTED_APPS[@]}"; do
    pgrep -xq "$app" || { open -a "$app" 2>/dev/null && { say "[guard] 拉起 $app"; log "拉起 $app"; }; }
  done
  if ! rc_alive; then
    osascript -e "tell application \"Terminal\" to do script \"$REMOTE_CONTROL_CMD\"" >/dev/null 2>&1 \
      && { say "[guard] 在 Terminal 里拉起 claude remote-control"; log "拉起 claude remote-control"; }
  fi
}

# 僵尸 / 孤儿：会话被杀之后残留的构建与模拟器进程，父进程已经是 launchd（ppid 1）就没人会再收它
cmd_zombie_gc() {
  local killed=0 line pid et comm
  while read -r pid et comm; do
    [ -n "$pid" ] || continue
    kill "$pid" 2>/dev/null && { say "[guard] 杀孤儿进程 $comm（pid $pid，跑了 $et）"; log "zombie-gc 杀 $comm $pid"; killed=$((killed+1)); }
  done < <(ps -Aeo pid,ppid,etime,comm | awk '$2==1' | grep -E ' (xcodebuild|xctest|swift-frontend|swift-driver|swift-build|swift-test|cargo|rustc|XCBBuildService|simctl)$' | awk '{print $1, $3, $4}')
  # 已经关机的模拟器却还留着 launchd_sim（simctl shutdown 半途被杀），直接清
  local booted; booted=$(booted_sims | cut -f1)
  while read -r pid udid; do
    [ -n "$pid" ] || continue
    printf '%s\n' "$booted" | grep -qF "$udid" && continue
    kill "$pid" 2>/dev/null && { say "[guard] 杀已关机模拟器残留的 launchd_sim $pid"; log "zombie-gc 杀 launchd_sim $pid"; killed=$((killed+1)); }
  done < <(ps -Aeo pid,args | grep launchd_sim | grep -v grep | sed -n 's/^ *\([0-9]*\) .*Devices\/\([A-F0-9-]*\)\/.*/\1 \2/p')
  # 真·僵尸态（Z）只能靠父进程收尸，父进程若是活着的会话就不动，父进程没了它也就没了
  [ "$killed" -eq 0 ] || sleep 2
  return 0
}

# Docker 按需：没人连着它里面的 Postgres（5432）就退出，要用时 open -a Docker 再开；
# 想临时保住 touch $STATE/docker.keep
cmd_docker_gc() {
  [ -f "$STATE/docker.keep" ] && return 0
  pgrep -xq 'Docker Desktop' || { rm -f "$STATE/.docker-idle"; return 0; }
  local c; c=$(netstat -an 2>/dev/null | grep -E '\.5432 ' | grep -c ESTABLISHED)
  if [ "${c:-0}" -eq 0 ]; then
    local mark="$STATE/.docker-idle" n=0
    [ -f "$mark" ] && n=$(cat "$mark")
    n=$((n+1)); printf '%s' "$n" >"$mark"
    if [ "$n" -ge "$DOCKER_IDLE_TICKS" ]; then
      osascript -e 'quit app "Docker"' >/dev/null 2>&1 && { say "[guard] Docker 连续 ${n} 分钟没人用，已退出"; log "docker-gc 退出 Docker（闲置 ${n} 分钟）"; }
      rm -f "$mark"
    fi
  else rm -f "$STATE/.docker-idle"; fi
}

renice_builds() {
  local p
  for p in $(build_pids; pgrep -x swift-frontend; pgrep -x swift-driver; pgrep -x rustc; pgrep -x XCBBuildService; pgrep -x xctest); do
    renice "$BUILD_NICE" -p "$p" >/dev/null 2>&1   # 绝对值；-n 在 macOS 上是增量，每分钟加 10 会一路加到 20
  done
}

cmd_tick() {
  cmd_protect
  renice_builds
  cmd_zombie_gc
  cmd_sim_gc
  cmd_docker_gc
  local r free
  r=$(pressure_reasons); free=$(disk_free_gb)
  if [ "$free" -lt "$MIN_DISK_GB" ] && [ "$(build_count)" -eq 0 ]; then cmd_clean --sims; r=$(pressure_reasons); fi
  if [ -n "$r" ]; then
    printf '%s\n%s\n' "$(date '+%m-%d %H:%M')" "$r" > "$STATE/ALERT"
    local last=0; [ -f "$STATE/.notified" ] && last=$(cat "$STATE/.notified")
    if [ $(( $(date +%s) - last )) -ge 900 ]; then
      osascript -e "display notification \"$(printf '%s' "$r" | head -n 1)\" with title \"看盘机器守门\"" >/dev/null 2>&1
      date +%s > "$STATE/.notified"
    fi
  else rm -f "$STATE/ALERT"; fi
  log "tick 负载$(load1) 内存$(free_mem_pct)% 交换$(swap_used_mb)MB 磁盘${free}GB 编译$(build_count) 模拟器$(booted_count)"
  [ "$(stat -f %z "$LOG" 2>/dev/null || echo 0)" -gt 2000000 ] && tail -n 2000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
  return 0
}

PLIST="$HOME/Library/LaunchAgents/com.kanpan.machine-guard.plist"
cmd_install_watchdog() {
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.kanpan.machine-guard</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$ROOT/scripts/machine-guard.sh</string><string>tick</string></array>
  <key>StartInterval</key><integer>60</integer>
  <key>RunAtLoad</key><true/>
  <key>Nice</key><integer>5</integer>
  <key>StandardOutPath</key><string>$STATE/launchd.log</string>
  <key>StandardErrorPath</key><string>$STATE/launchd.log</string>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin</string></dict>
</dict></plist>
PL
  launchctl bootout "gui/$(id -u)/com.kanpan.machine-guard" >/dev/null 2>&1
  launchctl bootstrap "gui/$(id -u)" "$PLIST" && say "[guard] 看门狗已装：每 60 秒 tick，日志 $LOG"
}
cmd_uninstall_watchdog() { launchctl bootout "gui/$(id -u)/com.kanpan.machine-guard" >/dev/null 2>&1; rm -f "$PLIST"; say "[guard] 看门狗已卸"; }

case "${1:-status}" in
  status) cmd_status ;;
  check) cmd_check ;;
  run) shift; cmd_run "$@" ;;
  sim-gc) cmd_sim_gc ;;
  zombie-gc) cmd_zombie_gc ;;
  docker-gc) cmd_docker_gc ;;
  clean) shift; cmd_clean "$@" ;;
  protect) cmd_protect ;;
  tick) cmd_tick ;;
  install-watchdog) cmd_install_watchdog ;;
  uninstall-watchdog) cmd_uninstall_watchdog ;;
  *) sed -n '2,30p' "$0"; exit 2 ;;
esac
