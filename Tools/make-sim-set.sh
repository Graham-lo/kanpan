#!/usr/bin/env bash
# 给一个窗口建一套它自己的矩阵模拟器（名字 = 机型名 + 后缀）。
#
# 为什么需要这个东西：
#   Tools/ui-test.sh 每台开跑之前都要 `simctl uninstall` 一次（为了「干净的第一次启动」）。
#   而这个工作树上经常有两个 Claude 窗口同时在跑矩阵——两轮会去 boot / uninstall / 测
#   同一批模拟器，谁的 uninstall 落在对方正在跑的那台上，对方那条用例当场就废了，
#   一轮十几个小时的活跟着作废。derived data 已经能用 DD / RES / OUT 错开，设备这一层
#   靠的就是这套带后缀的副本：ui-test.sh 的 SUFFIX 指到哪套，那个窗口就只碰那套。
#
# 为什么这套设备必须能被脚本重建、而不是手搓一次就算：
#   第一版这套矩阵是在会话里用一段一次性命令建出来的，没落盘。那意味着谁把它们删了、
#   或者换一台 Mac，就再也没有可重复的办法把它们建回来，而 ui-test.sh 的注释还在
#   暗示「照着现有同名设备建」有现成工具。这个文件就是把那句话补成真的。
#
# 为什么机型列表要从 ui-test.sh 里抠、而不是在这儿再抄一份：
#   那份两机型的 DEVICES 列表本身就是兼容性承诺，只能有一个事实来源；抄成两份，
#   哪天矩阵加一台机型，这边漏掉，那台就永远建不出副本、矩阵里永远报 MISSING。
#   至于为什么是「抠」而不是 `source`：ui-test.sh 是一条从头跑到尾的流水线，
#   source 进来会当场触发 build-for-testing 和整轮测试。所以这里只把 `DEVICES=( … )`
#   那一段文本摘出来单独 eval，取到列表，不执行它的任何其它语句。
#
# 为什么 device type 与 runtime 要逐台从现有同名设备上取：
#   identifier 里带着代次和内存档（例如 iPad Pro 11-inch (M5) 是
#   SimDeviceType.iPad-Pro-11-inch-M5-12GB），硬编码或者凭名字猜迟早会建出一台
#   规格对不上的设备，而矩阵的结论正是按机型下的。照抄现有同名设备，机型和系统版本
#   一定和原来那批一致。
#
# 幂等：同名已经存在就跳过。重名设备会让 ui-test.sh 按名字查 UDID 变成歧义
#   （到底测的是哪一台？），那正是要避免的，所以这里只新建、从不删除或覆盖。
#   本脚本也不会 boot / erase / shutdown / delete 任何设备——跑它的时候
#   隔壁窗口的矩阵很可能正占着其中几台。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Tools/ui-test.sh"
SUFFIX="${SUFFIX:- · m22}"

[ -r "$SRC" ] || { echo "✗ 找不到 $SRC，机型列表没地方取"; exit 1; }
DEVBLOCK="$(sed -n '/^DEVICES=(/,/^)/p' "$SRC")"
case "$DEVBLOCK" in
  DEVICES=\(*\)*) ;;
  *) echo "✗ 没能从 $SRC 里解析出 DEVICES 列表（那段的写法变了？）"; exit 1 ;;
esac
eval "$DEVBLOCK"
[ "${#DEVICES[@]}" -gt 0 ] || { echo "✗ 从 $SRC 解析出来的 DEVICES 是空的"; exit 1; }

echo "机型列表取自 $SRC（${#DEVICES[@]} 台），后缀 = 「$SUFFIX」"
echo

fail=0
for name in "${DEVICES[@]}"; do
  target="$name$SUFFIX"
  # 一次 list 里同时拿到「源设备的型号/系统」和「目标名字已有几台」，
  # 用 exit code 区分四种结局，避免把 UDID 和错误信息混在同一条 stdout 上。
  info="$(xcrun simctl list devices -j | SRC_NAME="$name" DST_NAME="$target" python3 -c '
import json, os, sys
src_name, dst_name = os.environ["SRC_NAME"], os.environ["DST_NAME"]
devices = json.load(sys.stdin)["devices"]
src, dst = [], []
for runtime, items in devices.items():
    for item in items:
        if item["name"] == src_name:
            src.append((item.get("deviceTypeIdentifier"), runtime))
        elif item["name"] == dst_name:
            dst.append(item["udid"])
if len(dst) > 1:
    print(" ".join(dst)); sys.exit(3)          # 重名，必须人工处理
if dst:
    print(dst[0]); sys.exit(2)                 # 已存在，跳过
if not src:
    print("源设备不存在"); sys.exit(4)
if len(src) > 1:
    print("源设备同名 %d 台，取型号有歧义" % len(src)); sys.exit(4)
if not src[0][0]:
    print("源设备没有 deviceTypeIdentifier"); sys.exit(4)
print("%s\t%s" % src[0]); sys.exit(0)          # 可以建
')"
  case $? in
    2) printf '  ✓ %-30s 已存在，跳过（%s）\n' "$target" "$info"; continue ;;
    3) printf '  ✗ %-30s 重名 %d 台，按名字查 UDID 会有歧义，请人工清理：%s\n' \
         "$target" "$(echo "$info" | wc -w | tr -d ' ')" "$info"; fail=1; continue ;;
    4) printf '  ✗ %-30s 建不了：%s（本机没有「%s」这台现成设备，无从取 device type / runtime）\n' \
         "$target" "$info" "$name"; fail=1; continue ;;
  esac
  dt="${info%%$'\t'*}"; rt="${info##*$'\t'}"
  if udid="$(xcrun simctl create "$target" "$dt" "$rt" 2>&1)"; then
    printf '  + %-30s 新建 %s\n' "$target" "$udid"
    printf '    %s\n    %s\n' "$dt" "$rt"
  else
    printf '  ✗ %-30s 创建失败：%s\n' "$target" "$udid"; fail=1
  fi
done

echo
have="$(xcrun simctl list devices | grep -c -- "$SUFFIX")"
echo "当前名字含「$SUFFIX」的设备共 $have 台（期望 ${#DEVICES[@]} 台）"
[ "$have" -eq "${#DEVICES[@]}" ] || fail=1
exit $fail
