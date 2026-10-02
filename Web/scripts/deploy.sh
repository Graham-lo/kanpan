#!/bin/sh
# Hkline Web · 部署到 VPS 的 /var/www/kanpan/web/（Caddy 已把 /web/ 当静态目录，不改 Caddy）
# 线上地址：https://kanpan.43-160-232-253.sslip.io/web/
# 用法：从仓库根 make web-deploy，或在 Web/ 下 sh scripts/deploy.sh；SKIP_BUILD=1 跳过构建。
set -eu
cd "$(dirname "$0")/.."
# 新加坡主机的 ssh 别名。Mac 经 Surge 直连它的 22 时常被代理节点掐断，那就 SG_SSH=kanpan-sg-jump（经美国主机跳）。
SG_SSH=${SG_SSH:-kanpan-sg}

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  npm run build
fi
[ -f dist/index.html ] || { echo "dist/index.html 不存在，先构建" >&2; exit 1; }

# 1. 先传到 VPS 的临时目录
ssh "$SG_SSH" 'rm -rf /tmp/kpweb-dist && mkdir -p /tmp/kpweb-dist'
scp -r dist/* "$SG_SSH":/tmp/kpweb-dist/

# 2. 再拷进 Caddy 的静态目录、改属主、删临时目录
ssh "$SG_SSH" 'sudo install -d -o caddy -g caddy /var/www/kanpan/web && sudo cp -r /tmp/kpweb-dist/. /var/www/kanpan/web/ && sudo chown -R caddy:caddy /var/www/kanpan/web && rm -rf /tmp/kpweb-dist'

# 只读核对：线上 index.html 引用的脚本和本地这次构建的一致
want=$(grep -o 'assets/index-[^"]*\.js' dist/index.html | head -1)
got=$(curl -fsS https://kanpan.43-160-232-253.sslip.io/web/ | grep -o 'assets/index-[^"]*\.js' | head -1 || true)
if [ "$want" = "$got" ]; then echo "已上线：$want"; else echo "线上脚本是 $got，本地是 $want，可能有缓存，稍后再看" >&2; exit 1; fi

# 手机网页版（/web/m/）：同样核对入口脚本名（assets/m-*.js）
if [ -f dist/m/index.html ]; then
  want=$(grep -o 'assets/m-[^"]*\.js' dist/m/index.html | head -1)
  got=$(curl -fsS https://kanpan.43-160-232-253.sslip.io/web/m/ | grep -o 'assets/m-[^"]*\.js' | head -1 || true)
  if [ "$want" = "$got" ]; then echo "手机网页版已上线：$want"; else echo "手机网页版线上脚本是 $got，本地是 $want，可能有缓存，稍后再看" >&2; exit 1; fi
fi
