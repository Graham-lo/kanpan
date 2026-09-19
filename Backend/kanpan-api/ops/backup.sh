#!/bin/sh
# 这份转储里没有密钥。/etc/kanpan-api/service.env 里的 KANPAN_PASSWORD_PEPPER 与
# KANPAN_ENCRYPTION_KEY 必须另外单独留一份、和备份分开存放：前者拌在 Argon2 里，
# 后者用来密封刷新结果——只恢复数据库、丢了这两把钥匙，所有账号都登不回来，
# 而且一点报错都不会有。ops/install.py 在 env 文件缺失而库里还有账号时会拒绝安装。
set -eu
umask 077
folder=/var/backups/kanpan
mkdir -p "$folder"
file="$folder/kanpan-$(date -u +%Y%m%d-%H%M%S).dump"
docker exec kanpan-postgres pg_dump -U kanpan_admin -d kanpan -Fc > "$file.part"
test -s "$file.part"
mv "$file.part" "$file"
find "$folder" -name 'kanpan-*.dump' -mtime +30 -delete
