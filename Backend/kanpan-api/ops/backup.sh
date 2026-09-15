#!/bin/sh
set -eu
umask 077
folder=/var/backups/kanpan
mkdir -p "$folder"
file="$folder/kanpan-$(date -u +%Y%m%d-%H%M%S).dump"
docker exec kanpan-postgres pg_dump -U kanpan_admin -d kanpan -Fc > "$file.part"
test -s "$file.part"
mv "$file.part" "$file"
find "$folder" -name 'kanpan-*.dump' -mtime +30 -delete
