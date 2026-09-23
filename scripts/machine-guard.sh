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
#     1. 预算：机器上同时最多 MAX_BUILDS 个重编译、MAX_SIMS 台开机模拟器，磁盘至少
#        MIN_DISK_GB，交换区不超 MAX_SWAP_MB。重活用 `run` 包着跑就会自动排队、自动 nice；
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
# 预算都能用环境变量临时覆盖：MAX_BUILDS=3 scripts/machine-guard.sh run ...
# 临时关掉「拉起受保护应用」：touch /tmp/kanpan-guard/protect.off

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE=/tmp/kanpan-guard
mkdir -p "$STATE/slots"
LOG="$STATE/guard.log"

MAX_BUILDS=${MAX_BUILDS:-2}
MAX_SIMS=${MAX_SIMS:-2}
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

# ---------------------------------------------------------------- 构建槽
slot_dead() {  # 槽目录里的 pid 没了，或者目录建了 60 秒还没写 pid
  local s="$1"
  if [ -f "$s/pid" ]; then ! kill -0 "$(cat "$s/pid")" 2>/dev/null
  else [ -n "$(find "$s" -maxdepth 0 -mmin +1 2>/dev/null)" ]; fi
}
reap_slots() { local s; for s in "$STATE"/slots/*/; do [ -d "$s" ] || continue; slot_dead "$s" && rm -rf "$s"; done; }
acquire_slot() {
  reap_slots
  local i s
  for i in $(seq 1 "$MAX_BUILDS"); do
    s="$STATE/slots/$i"
    if mkdir "$s" 2>/dev/null; then echo $$ > "$s/pid"; printf '%s\n' "$*" > "$s/cmd"; SLOT="$s"; return 0; fi
  done
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
  local free swap mem ld b s
  free=$(disk_free_gb); swap=$(swap_used_mb); mem=$(free_mem_pct); ld=$(load1); b=$(build_count); s=$(booted_count)
  say "负载 ${ld}（10 核）  空闲内存 ${mem}%  交换区 ${swap} MB / 预算 ${MAX_SWAP_MB}  磁盘空闲 ${free} GB / 预算 ${MIN_DISK_GB}"
  say "重编译进程 ${b}  构建槽 $(slots_in_use)/${MAX_BUILDS}  开机模拟器 ${s}/${MAX_SIMS}"
  local d; for d in "$STATE"/slots/*/; do [ -d "$d" ] && say "  槽 $(basename "$d"): pid $(cat "$d/pid" 2>/dev/null) $(head -c 100 "$d/cmd" 2>/dev/null)"; done
  booted_sims | sed 's/^/  开机: /'
  local app; for app in "${PROTECTED_APPS[@]}"; do pgrep -xq "$app" && say "  $app 在" || say "  $app 不在！"; done
  rc_alive && say "  claude remote-control 在" || say "  claude remote-control 不在！"
  [ -f "$STATE/ALERT" ] && { say "告警:"; sed 's/^/  /' "$STATE/ALERT"; }
  local r; r=$(pressure_reasons); [ -z "$r" ] || { say "超预算:"; say "$r" | sed 's/^/  /'; }
  return 0
}

cmd_check() {
  local r; r=$(pressure_reasons)
  [ "$(build_count)" -lt "$MAX_BUILDS" ] || r="${r}${r:+$'\n'}已有 $(build_count) 个重编译在跑（预算 ${MAX_BUILDS}）"
  [ "$(booted_count)" -lt "$MAX_SIMS" ]  || r="${r}${r:+$'\n'}已有 $(booted_count) 台模拟器开着（预算 ${MAX_SIMS}）"
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
    [ "$said" -eq 1 ] || { say "[guard] 机器上已有 ${MAX_BUILDS} 个重编译在跑，排队等槽…"; said=1; }
    sleep 15; waited=$((waited+15))
  done
  trap 'rm -rf "$SLOT"' EXIT INT TERM HUP
  local r
  while r=$(pressure_reasons); [ -n "$r" ]; do
    [ "$waited" -lt "$SLOT_WAIT_SEC" ] || { say "[guard] 机器压力一直没降下来，放弃："; say "$r"; return 5; }
    [ "$said" -eq 2 ] || { say "[guard] 机器超预算，占着槽等压力降下来："; say "$r" | sed 's/^/  /'; said=2; }
    sleep 15; waited=$((waited+15))
  done
  log "run 槽$(basename "$SLOT") pid $$: $*"
  KANPAN_GUARD_SLOT="$SLOT" nice -n "$BUILD_NICE" "$@"
  local rc=$?
  log "done 槽$(basename "$SLOT") rc=$rc"
  return $rc
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
  local mem count line udid name age list=""
  mem=$(free_mem_pct); count=$(booted_count)
  while IFS=$'\t' read -r udid name; do
    [ -n "$udid" ] || continue
    sim_referenced "$udid" "$name" && continue
    age=$(sim_age_sec "$udid"); [ "${age:-0}" -ge "$SIM_GRACE_SEC" ] || continue
    list="${list}${age}\t${udid}\t${name}\n"
  done < <(booted_sims)
  [ -n "$list" ] || return 0
  printf '%b' "$list" | sort -rn | while IFS=$'\t' read -r age udid name; do
    if [ "$count" -gt "$MAX_SIMS" ] || [ "${mem:-100}" -lt "$MIN_FREE_MEM_PCT" ]; then
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
    renice -n "$BUILD_NICE" -p "$p" >/dev/null 2>&1
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
