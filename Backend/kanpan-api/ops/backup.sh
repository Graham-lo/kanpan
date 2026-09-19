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

# 上一次没跑完留下的半份。保留期清理只认 kanpan-*.dump，`.part` 不在那个名字里，也永远
# 不会被 mv 成正式的一份，所以它们会一直躺着——既占地方，又让下面那条空间检查越来越难过。
# 超过十二小时的直接扫掉：这个脚本一天只跑一次，十二小时以上的 .part 不可能是正在写的那
# 一份。口径跟 offsite-push.sh / offsite-pull.sh 清远端 `.part` 目录的那条对齐（-mmin +720），
# 三处都是「十二小时」；原来这里写 -mtime +1，那是「满 48 小时」，跟注释和 OFFSITE.md 说的
# 都不是一回事。
find "$folder" -name 'kanpan-*.dump.part' -mmin +720 -delete

# 再执行保留期：过期的先清掉，腾出来的地方这一轮就能用上。
#
# 这一步必须在空间检查之前，不能留在脚本末尾——末尾的话，空间不足 exit 1、pg_dump 失败、
# test -s 失败这三条路全都跳过它，于是「盘被 30 天前的旧转储占满」变成一个自锁的死结：
# 清理永远等不到一次成功的备份，备份永远等不到一次清理。放在这里，就算今天一份也备不出来，
# 该过期的也照样过期。
find "$folder" -name 'kanpan-*.dump' -mtime +30 -delete

# 然后看还有没有地方写。
#
# 没有这一步，磁盘满的那天是这样的：pg_dump 写到一半被 ENOSPC 打断，`set -e` 让脚本停在
# 那儿，`.part` 留着不动，于是「最近一份备份」还是昨天那一份，而 journal 里只有一行 psql
# 的报错——没人看的话，接下来每天都这样。
#
# 要的量是上一份的两倍：新的一份至少和上一份一样大（数据只会长），而保留期是 30 天，
# 上一份还得留在盘上，两份要同时放得下。没有上一份时按 1 MiB 兜底——比这还少的空间连
# 一个空壳转储都写不下。
previous=$(ls -1t "$folder"/kanpan-*.dump 2>/dev/null | head -n 1 || true)
if [ -n "$previous" ]; then need=$(( $(du -k "$previous" | cut -f1) * 2 )); else need=1024; fi
free=$(df -Pk "$folder" | awk 'NR==2{print $4}')
if [ "$free" -lt "$need" ]; then
 echo "kanpan backup aborted: $folder has ${free} KiB free but needs ${need} KiB (twice the last dump). Nothing was written; free space and run systemctl start kanpan-backup.service." >&2
 exit 1
fi

file="$folder/kanpan-$(date -u +%Y%m%d-%H%M%S).dump"
# 这一趟只要没走到 mv，那个 .part 就是一份写坏的转储，出门时带走它。放在 file= 之后设，
# 否则 $file 还是空的，rm 会去删当前目录下一个叫 .part 的东西。
trap 'rm -f "$file.part"' EXIT HUP INT TERM
docker exec kanpan-postgres pg_dump -U kanpan_admin -d kanpan -Fc > "$file.part"
test -s "$file.part"
mv "$file.part" "$file"
# 保留期清理已经在开头做过了（见上面那段），这里不再做第二遍。
