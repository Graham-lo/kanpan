#!/bin/bash
# 正式切换：美国主机 → 新加坡主机（2026-10-02 迁移的最后一步）。在 Mac 上跑，一次性。
#
# 前提只有一条：腾讯安全组已放行 TCP 443（第 0 步从美国探，探不通就不切、什么都不动）。
# 顺序：
#   1. 美国停 kanpan-api / kanpan-worker（停写），落一份最终瘦转储（和 ops/backup.sh 同一组排除表）；
#   2. 转储经 Mac 中转到新加坡（美国 → 新加坡那段链路只有几 KB/s，经 Mac 走是几十秒）；
#   3. 新加坡停 api / worker，整个 public schema 重建后 pg_restore，ops/install.py 兜一遍，起服务，查健康与账号数；
#   4. 美国的 Caddy 把旧主机名 kanpan.107-174-172-10.sslip.io 改成过渡代理：接口反代到新加坡、/web /ui 308 跳过去；
#   5. 美国停掉并禁用 api / worker / 网关 / stream-hub / 备份与推送 timer（Postgres 容器留着当温备）；
#   6. 从美国与本机各探一遍旧新两个主机名。
# 出错即停（set -e），停在哪一步看日志；第 3 步之前美国的服务只是 stop 没 disable，`ssh orderflow-vps systemctl start kanpan-api kanpan-worker` 就回滚。
set -euo pipefail
US=orderflow-vps
SG=${SG_SSH:-kanpan-sg}
SGJ=${SG_SSH_FALLBACK:-kanpan-sg-jump}
NEW=kanpan.43-160-232-253.sslip.io
OLD=kanpan.107-174-172-10.sslip.io
STAMP=$(date -u +%Y%m%d-%H%M%S)
DUMP=/tmp/kanpan-final-$STAMP.dump
log() { printf '%s cutover: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

# 0. 443 从美国探；Mac 经 Surge 的结果不作数。
code=$(ssh "$US" "curl -sS --max-time 15 -o /dev/null -w '%{http_code}' https://$NEW/chart-gateway/health" || true)
[ "$code" = 200 ] || { log "美国到 $NEW:443 不通（$code）：腾讯安全组还没放行 TCP 443，不切"; exit 2; }
ssh -o ConnectTimeout=15 -o BatchMode=yes "$SG" true 2>/dev/null || { log "$SG 直连不通，改走 $SGJ"; SG=$SGJ; }

# 1. 美国停写、落最终转储。
log "美国停 kanpan-api / kanpan-worker"
ssh "$US" 'systemctl stop kanpan-api kanpan-worker'
log "美国落最终瘦转储"
ssh "$US" "docker exec kanpan-postgres pg_dump -U kanpan_admin -d kanpan -Fc --compress=zstd:9 \
  --exclude-table-data='orderflow_heat*' --exclude-table-data=market_features \
  --exclude-table-data=orderflow_orders --exclude-table-data=orderflow_live --exclude-table-data=orderflow_flow \
  > $DUMP && ls -l $DUMP"

# 2. 美国 → Mac → 新加坡。
log "转储经 Mac 中转"
ssh "$US" "cat $DUMP" > "$DUMP"
size=$(wc -c < "$DUMP" | tr -d ' '); [ "$size" -gt 1048576 ] || { log "转储只有 $size 字节，不对，停"; exit 1; }
ssh "$SG" 'mkdir -p /home/ubuntu/incoming && cat > /home/ubuntu/incoming/final.dump' < "$DUMP"
ssh "$SG" "[ \$(wc -c < /home/ubuntu/incoming/final.dump) -eq $size ]" || { log "新加坡收到的大小不对，停"; exit 1; }

# 3. 新加坡重建并恢复。
log "新加坡恢复"
# 远端脚本先落成文件再执行，不能 `bash -s` 从 stdin 喂：中间任何一条会读 stdin 的命令（docker exec -i）
# 会把后半段脚本吞掉，bash 读到 EOF 当作正常结束——2026-10-02 第一次切换就是这样把库建空了。
ssh "$SG" 'cat > /tmp/kanpan-cutover-restore.sh' <<'EOF'
set -e
sudo systemctl stop kanpan-api kanpan-worker
sudo docker exec kanpan-postgres psql -q -U kanpan_admin -d kanpan -v ON_ERROR_STOP=1 \
  -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT USAGE ON SCHEMA public TO kanpan_app;'
sudo docker cp /home/ubuntu/incoming/final.dump kanpan-postgres:/tmp/final.dump
sudo docker exec kanpan-postgres pg_restore -U kanpan_admin -d kanpan --exit-on-error /tmp/final.dump
sudo docker exec kanpan-postgres rm /tmp/final.dump
rm -f /home/ubuntu/incoming/final.dump
cd /opt/kanpan-api && sudo python3 ops/install.py >/dev/null
sleep 5
printf 'units: '; systemctl is-active kanpan-api kanpan-worker | tr '\n' ' '; echo
printf 'health: '; curl -s --max-time 5 http://127.0.0.1:8794/health; echo
sudo docker exec kanpan-postgres psql -U kanpan_admin -d kanpan -Atc \
  "select 'users='||(select count(*) from account_users)||' sync_ops='||(select count(*) from sync_operations)||' alerts='||(select count(*) from alert_watches)||' notes='||(select count(*) from review_records)"
EOF
ssh "$SG" 'bash /tmp/kanpan-cutover-restore.sh && rm -f /tmp/kanpan-cutover-restore.sh'

# 4. 美国 Caddy：旧主机名改成过渡代理。只换 kanpan.107-174-172-10.sslip.io 那个站点块，前面的静态站不动。
log "美国 Caddy 改过渡代理"
ssh "$US" "cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.pre-sg-$STAMP && python3 - <<'PY'
import re
p='/etc/caddy/Caddyfile'; s=open(p).read()
i=s.index('https://kanpan.107-174-172-10.sslip.io {')
block='''# 2026-10-02 起只是过渡代理：真正的服务在新加坡 $NEW（见 Backend/kanpan-api/ops/cutover-sg.sh）。
# 还没更新的客户端用旧主机名也能用；网页版直接跳过去，免得 service worker 缓着两份。
https://$OLD {
    redir /web/* https://$NEW{uri} 308
    redir /ui/* https://$NEW{uri} 308
    reverse_proxy https://$NEW {
        header_up Host $NEW
    }
}
'''
s=s[:i]+block
open(p,'w').write(s)
PY
caddy validate --config /etc/caddy/Caddyfile >/dev/null && systemctl restart caddy && sleep 3 && systemctl is-active caddy"
# 美国的 Caddyfile 是 admin off，reload 要走 2019 端口的管理接口所以一定失败，只能 restart（断几秒）。

# 5. 美国停掉线上角色，Postgres 留着当温备。
log "美国禁用 api / worker / 网关 / timer"
ssh "$US" 'systemctl disable --now kanpan-api kanpan-worker kanpan-gateway kanpan-stream-hub kanpan-backup.timer kanpan-offsite-push.timer >/dev/null 2>&1; systemctl is-active kanpan-api kanpan-worker kanpan-gateway kanpan-stream-hub | tr "\n" " "; echo'

# 6. 探。
log "验证"
for h in "$NEW" "$OLD"; do
  for p in /chart-gateway/health /v1/market/meta /privacy; do
    printf '  US  → %s%s -> ' "$h" "$p"; ssh "$US" "curl -sS --max-time 15 -o /dev/null -w '%{http_code}\n' https://$h$p"
  done
  printf '  US  → %s/web/ -> ' "$h"; ssh "$US" "curl -sS --max-time 15 -o /dev/null -w '%{http_code} %{redirect_url}\n' https://$h/web/"
done
for p in /chart-gateway/health /v1/market/meta; do
  printf '  Mac → %s%s -> ' "$NEW" "$p"; curl -sS --max-time 15 -o /dev/null -w '%{http_code}\n' "https://$NEW$p"
  printf '  Mac → %s%s -> ' "$OLD" "$p"; curl -sS --max-time 15 -o /dev/null -w '%{http_code}\n' "https://$OLD$p"
done
rm -f "$DUMP"
log "完成。美国的 $DUMP 留着，确认一周没问题再删。"
