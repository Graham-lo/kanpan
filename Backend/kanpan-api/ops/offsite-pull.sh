#!/bin/bash
# 离机副本 · Mac 侧（拉回来）
#
# 主服务器自己的 ops/backup.sh 每天 00:00 把 pg_dump 落在 /var/backups/kanpan/，留 30 天。
# 但转储和 /etc/kanpan-api/ 里的两个 env 全在同一台机器上，那台机器没了就都没了。
# 这个脚本每天 01:00 由 launchd 叫起来，把「最新的一份转储 + service.env + database.env」
# 当作一组拉到本机 ~/kanpan-backups/<UTC 时间戳>/。
#
# 三件必须凑齐才算一份能用的备份：光有转储恢复不了账号——service.env 里的
# KANPAN_PASSWORD_PEPPER 拌在 Argon2 里、KANPAN_ENCRYPTION_KEY 用来密封刷新结果，
# 换一把就谁都登不回来，而且一点报错都不会有；database.env 里是 kanpan_admin 的口令。
# 所以下面拉完会当场验一遍，缺一样就非零退出，不让半份备份混进保留队列。
#
# 装上定时（Mac，一次即可）：
#   mkdir -p ~/kanpan-backups
#   cp /Users/mdd/zhk/kanpan/Backend/kanpan-api/ops/offsite-pull.launchd.plist \
#      ~/Library/LaunchAgents/com.mdd.kanpan.offsite-pull.plist
#   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.mdd.kanpan.offsite-pull.plist
#   launchctl enable gui/$(id -u)/com.mdd.kanpan.offsite-pull
# 立刻试跑一次：launchctl kickstart -p gui/$(id -u)/com.mdd.kanpan.offsite-pull
# 看结果：      tail -n 20 ~/kanpan-backups/pull.log
# 查状态：      launchctl print gui/$(id -u)/com.mdd.kanpan.offsite-pull
# 卸掉：        launchctl bootout gui/$(id -u)/com.mdd.kanpan.offsite-pull
# 手动跑：      bash /Users/mdd/zhk/kanpan/Backend/kanpan-api/ops/offsite-pull.sh
#
# BatchMode=yes 意味着没人能替它输口令：到 orderflow-vps 的那把私钥要么不带口令，
# 要么口令已经存进钥匙串并且 ~/.ssh/config 里写了 UseKeychain yes / AddKeysToAgent yes。
# 先手动 `ssh -o BatchMode=yes orderflow-vps true` 跑通，再装定时。
#
# 可调（环境变量）：SOURCE_HOST OFFSITE_ROOT OFFSITE_KEEP REMOTE_DUMPS REMOTE_ENV
set -euo pipefail
umask 077

HOST=${SOURCE_HOST:-orderflow-vps}
REMOTE_DUMPS=${REMOTE_DUMPS:-/var/backups/kanpan}
REMOTE_ENV=${REMOTE_ENV:-/etc/kanpan-api}
ROOT=${OFFSITE_ROOT:-$HOME/kanpan-backups}
KEEP=${OFFSITE_KEEP:-30}
MIN_DUMP=1048576                                     # 1 MiB
STAMP_GLOB='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]'

SSH_OPTS=(-o ConnectTimeout=20 -o BatchMode=yes)
die() { printf 'offsite-pull: %s\n' "$*" >&2; exit 1; }
stamp=$(date -u +%Y%m%d-%H%M%S)
stage="$ROOT/$stamp.part"
final="$ROOT/$stamp"

mkdir -p "$ROOT"; chmod 700 "$ROOT"
rm -rf "$stage"; mkdir "$stage"                      # umask 077 → 700
trap 'rm -rf "$stage"' EXIT

# 服务器上的文件名是 kanpan-YYYYMMDD-HHMMSS.dump，字典序就是时间序。
latest=$(ssh "${SSH_OPTS[@]}" "$HOST" "ls -1 $REMOTE_DUMPS/kanpan-*.dump 2>/dev/null | sort | tail -1") \
  || die "连不上 $HOST（BatchMode 下不会提示输口令；先手动跑 ssh -o BatchMode=yes $HOST true）"
[ -n "$latest" ] || die "$HOST:$REMOTE_DUMPS 下一个 kanpan-*.dump 都没有 —— 先在服务器上 systemctl start kanpan-backup.service"

name=$(basename "$latest")
scp "${SSH_OPTS[@]}" -p "$HOST:$latest" "$stage/$name"              || die "拉转储失败：$HOST:$latest"
scp "${SSH_OPTS[@]}" -p "$HOST:$REMOTE_ENV/service.env"  "$stage/"  || die "拉 $REMOTE_ENV/service.env 失败"
scp "${SSH_OPTS[@]}" -p "$HOST:$REMOTE_ENV/database.env" "$stage/"  || die "拉 $REMOTE_ENV/database.env 失败"

# 校验：三件都在、转储不是个空壳、两把钥匙不是空值。
size=$(wc -c < "$stage/$name" | tr -d ' ')
[ "$size" -gt "$MIN_DUMP" ] || die "转储只有 $size 字节（不到 1 MiB），当作没备成，不收进保留队列"
for f in service.env database.env; do
  [ -s "$stage/$f" ] || die "$f 没拉下来或者是空的"
done
for key in KANPAN_PASSWORD_PEPPER KANPAN_ENCRYPTION_KEY KANPAN_DATABASE_URL; do
  grep -Eq "^$key=[^[:space:]]" "$stage/service.env" \
    || die "service.env 里 $key 是空的 —— 没有它，拿这份备份恢复出来的库谁也登不回来"
done
grep -Eq '^POSTGRES_PASSWORD=[^[:space:]]' "$stage/database.env" || die "database.env 里 POSTGRES_PASSWORD 是空的"
chmod 600 "$stage/$name" "$stage/service.env" "$stage/database.env"

trap - EXIT
rm -rf "$final"
mv "$stage" "$final"
chmod 700 "$final"

# 保留最近 KEEP 份，更早的删掉；顺手清掉早先崩在半路留下的 .part。
pruned=0
while IFS= read -r dir; do
  [ -n "$dir" ] || continue
  rm -rf "$dir"; pruned=$((pruned + 1))
done < <(find "$ROOT" -mindepth 1 -maxdepth 1 -type d -name "$STAMP_GLOB" | sort -r | tail -n +$((KEEP + 1)))
find "$ROOT" -mindepth 1 -maxdepth 1 -type d -name '*.part' -mmin +720 -exec rm -rf {} + 2>/dev/null || true

kept=$(find "$ROOT" -mindepth 1 -maxdepth 1 -type d -name "$STAMP_GLOB" | wc -l | tr -d ' ')
printf '%s offsite-pull: %s ← %s:%s  %s MiB  共 %s 份（本轮清掉 %d 份）\n' \
  "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$final" "$HOST" "$name" \
  "$(awk -v b="$size" 'BEGIN{printf "%.1f", b/1048576}')" "$kept" "$pruned"
