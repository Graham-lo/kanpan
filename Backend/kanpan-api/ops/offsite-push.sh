#!/bin/bash
# 离机副本 · 主服务器侧（推出去）
#
# ops/backup.sh 每天 00:00 把 pg_dump 落在 /var/backups/kanpan/，可它和
# /etc/kanpan-api/ 的两个 env 都在这台机器上。这个脚本 00:20 由
# kanpan-offsite-push.timer 叫起来，把「最新的一份转储 + service.env + database.env」
# 当作一组 rsync 到备用服务器的 /var/backups/kanpan-offsite/<UTC 时间戳>/。
#
# 三件必须凑成一组：光有转储恢复不了账号——KANPAN_PASSWORD_PEPPER 拌在 Argon2 里、
# KANPAN_ENCRYPTION_KEY 用来密封刷新结果，换一把就谁都登不回来且不会报错。
# 所以推之前在本机验一遍、推完在远端再验一遍，都过了才把 .part 目录改名转正——
# 保留队列里永远只有完整的那种。
#
# 装法（生成密钥、写 authorized_keys、拷单元文件）见同目录 ops/OFFSITE.md。
# 手动跑一次：  systemctl start kanpan-offsite-push.service
# 看结果：      systemctl status kanpan-offsite-push.service; journalctl -u kanpan-offsite-push -n 50
#
# 注意：这条链路会把 pepper 和 encryption key 放到备用服务器上，那台机器原本没有任何
# 密钥。所以远端目录一律 700/600、只有 root 读得到，公钥也用 from= 锁死来源地址。
# 真正的异地那一份是 Mac 上的 ops/offsite-pull.sh，这条是 Mac 关机时的兜底。
#
# 可调（环境变量）：OFFSITE_HOST OFFSITE_USER OFFSITE_KEY OFFSITE_ROOT OFFSITE_KEEP
set -euo pipefail
umask 077

OFFSITE_HOST=${OFFSITE_HOST:-96.44.162.222}
OFFSITE_USER=${OFFSITE_USER:-root}
OFFSITE_PORT=${OFFSITE_PORT:-33333}                   # 备用机的 sshd 不在 22
OFFSITE_KEY=${OFFSITE_KEY:-/root/.ssh/kanpan-offsite}
OFFSITE_ROOT=${OFFSITE_ROOT:-/var/backups/kanpan-offsite}
KEEP=${OFFSITE_KEEP:-30}
DUMPS=${DUMPS:-/var/backups/kanpan}
ENVDIR=${ENVDIR:-/etc/kanpan-api}
MIN_DUMP=1048576                                     # 1 MiB
STAMP_GLOB='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]'

die() { printf 'offsite-push: %s\n' "$*" >&2; exit 1; }
target="$OFFSITE_USER@$OFFSITE_HOST"
ssh_args="-i $OFFSITE_KEY -p $OFFSITE_PORT -o ConnectTimeout=20 -o BatchMode=yes -o IdentitiesOnly=yes"
# shellcheck disable=SC2206
SSH=(ssh $ssh_args)

[ -r "$OFFSITE_KEY" ] || die "读不到私钥 $OFFSITE_KEY —— 见 ops/OFFSITE.md 第 1 步"
command -v rsync >/dev/null || die "没装 rsync：apt-get install -y rsync"

# 先在本机把要推的三件验一遍，别把半份备份送出去。
latest=$(ls -1 "$DUMPS"/kanpan-*.dump 2>/dev/null | sort | tail -1) || true
[ -n "${latest:-}" ] || die "$DUMPS 下一个 kanpan-*.dump 都没有 —— 先 systemctl start kanpan-backup.service"
name=$(basename "$latest")
size=$(wc -c < "$latest" | tr -d ' ')
[ "$size" -gt "$MIN_DUMP" ] || die "$latest 只有 $size 字节（不到 1 MiB），当作没备成，不推"
for f in service.env database.env; do
  [ -s "$ENVDIR/$f" ] || die "$ENVDIR/$f 不在或者是空的"
done
for key in KANPAN_PASSWORD_PEPPER KANPAN_ENCRYPTION_KEY KANPAN_DATABASE_URL; do
  grep -Eq "^$key=[^[:space:]]" "$ENVDIR/service.env" \
    || die "$ENVDIR/service.env 里 $key 是空的 —— 没有它，这份备份恢复出来的库谁也登不回来"
done
grep -Eq '^POSTGRES_PASSWORD=[^[:space:]]' "$ENVDIR/database.env" || die "$ENVDIR/database.env 里 POSTGRES_PASSWORD 是空的"

stamp=$(date -u +%Y%m%d-%H%M%S)
stage="$OFFSITE_ROOT/$stamp.part"
final="$OFFSITE_ROOT/$stamp"

"${SSH[@]}" "$target" "install -d -m 700 '$OFFSITE_ROOT' '$stage'" \
  || die "连不上 $target。先认一次主机指纹：ssh-keyscan -p $OFFSITE_PORT -H $OFFSITE_HOST >> /root/.ssh/known_hosts；再试 ssh $ssh_args $target true"

# -a 里的 -p 会把本机权限照搬过去，--chmod 覆盖掉它：目录 700、文件 600，跟本机一致。
rsync -a --chmod=D700,F600 -e "ssh $ssh_args" \
  "$latest" "$ENVDIR/service.env" "$ENVDIR/database.env" "$target:$stage/" \
  || die "rsync 推送失败，$stage 留在远端没有转正"

# 一条 ssh 做完：远端复验 → 改名转正 → 只留最近 KEEP 份 → 清掉早先崩在半路的 .part。
kept=$("${SSH[@]}" "$target" "
set -eu
cd '$stage'
test \"\$(wc -c < '$name')\" -eq $size
test -s service.env
test -s database.env
grep -Eq '^KANPAN_PASSWORD_PEPPER=[^[:space:]]' service.env
grep -Eq '^KANPAN_ENCRYPTION_KEY=[^[:space:]]' service.env
grep -Eq '^POSTGRES_PASSWORD=[^[:space:]]' database.env
cd '$OFFSITE_ROOT'
rm -rf '$final'
mv '$stage' '$final'
chmod 700 '$final'
ls -1d $STAMP_GLOB/ 2>/dev/null | sed 's:/\$::' | sort -r | tail -n +$((KEEP + 1)) | xargs -r rm -rf
find . -maxdepth 1 -type d -name '*.part' -mmin +720 -exec rm -rf {} + 2>/dev/null || true
ls -1d $STAMP_GLOB/ 2>/dev/null | wc -l
") || die "远端复验或收尾失败，副本留在 $stage 没有转正"
kept=${kept//[^0-9]/}

printf '%s offsite-push: %s → %s:%s  %s MiB  远端共 %s 份\n' \
  "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$name" "$target" "$final" \
  "$(awk -v b="$size" 'BEGIN{printf "%.1f", b/1048576}')" "$kept"
