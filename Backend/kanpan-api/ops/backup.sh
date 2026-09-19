#!/bin/sh
# 这份转储里没有密钥。/etc/kanpan-api/service.env 里的 KANPAN_PASSWORD_PEPPER 与
# KANPAN_ENCRYPTION_KEY 得和它凑成一组才恢复得了：前者拌在 Argon2 里，后者用来密封
# 刷新结果——只恢复数据库、丢了这两把钥匙，所有账号都登不回来，而且一点报错都不会有。
# ops/install.py 在 env 文件缺失而库里还有账号时会拒绝安装。
#
# 这里写下的只是本机副本：它和那两个 env 都在这台机器上，机器没了就一起没了。离机的
# 那一组（最新转储 + service.env + database.env）由两条链路各自带走，装法与恢复演练
# 都在 ops/OFFSITE.md：
#   ops/offsite-push.sh  本机 00:20 由 kanpan-offsite-push.timer 推到备用服务器
#   ops/offsite-pull.sh  Mac 每天 01:00 由 launchd 拉回 ~/kanpan-backups/
# 两条都只在「转储够大、两把钥匙非空」时才让那一份进保留队列，所以各留 30 份。
set -eu
umask 077
folder=/var/backups/kanpan
mkdir -p "$folder"
file="$folder/kanpan-$(date -u +%Y%m%d-%H%M%S).dump"
docker exec kanpan-postgres pg_dump -U kanpan_admin -d kanpan -Fc > "$file.part"
test -s "$file.part"
mv "$file.part" "$file"
find "$folder" -name 'kanpan-*.dump' -mtime +30 -delete
