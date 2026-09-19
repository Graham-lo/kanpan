# 离机副本与恢复演练（审查项 A-08）

`kanpan-backup.timer` 每天 00:00 写一份 `pg_dump` 到主服务器自己的
`/var/backups/kanpan/`，留 30 天。问题是它和 `/etc/kanpan-api/service.env`、
`/etc/kanpan-api/database.env` 全在同一台机器上——那台机器没了，转储和钥匙一起没。

**一份能用的备份是三件东西，缺一不可：**

| 文件 | 里面是什么 | 丢了会怎样 |
| --- | --- | --- |
| `kanpan-<日期>.dump` | 账号、偏好、画线、自选、复盘 | 数据没了 |
| `service.env` | `KANPAN_PASSWORD_PEPPER`、`KANPAN_ENCRYPTION_KEY`、`KANPAN_DATABASE_URL` | 库恢复出来了，但所有人都登不回来，而且**一个错都不报**——只会被告知「用户名或密码不对」 |
| `database.env` | `kanpan_admin` 的口令 | 连不上自己的库 |

三件里只有 `service.env` 是**丢了就真的补不回来**的：`database.env` 里只有数据库超级用户的
口令，它不参与任何加密，`ops/install.py` 会自己补一把新的（见第三节第 0 步）。所以真正要
命的组合是「有转储、没 `service.env`」，`ops/install.py` 已经在 env 缺失而库里还有账号时
拒绝安装，就是为了拦住这条死路。下面两条链路把这三件当作**一组**带走：

- **`ops/offsite-push.sh`** — 主服务器 00:20 推到备用服务器 `96.44.162.222` 的
  `/var/backups/kanpan-offsite/<UTC 时间戳>/`，留 30 份。主服务器自己出事时用它。
- **`ops/offsite-pull.sh`** — Mac 每天 01:00 拉回 `~/kanpan-backups/<UTC 时间戳>/`，留 30 份。
  这才是真正的异地那一份：不同机房、不同网络、两台 VPS 一起没了也还在。

两条都在收尾前验一遍「转储 > 1 MiB、`KANPAN_PASSWORD_PEPPER` 与 `KANPAN_ENCRYPTION_KEY`
非空」，过了才把 `.part` 目录改名转正。所以保留队列里不会混进半份备份，30 份就是 30 份能用的。

> 这条链路会把 pepper 和 encryption key 放到备用服务器上——那台机器原本跑的是
> `kanpan-metrics`，一个密钥都没有。所以远端目录一律 700、文件 600，只有 root 读得到，
> 公钥也用 `from=` 锁死来源地址。这是明知道的取舍：与其让钥匙只存在于一台机器上，
> 不如让它多待在一台同样只有 root 能进的机器上。

---

## 一、主服务器 → 备用服务器（按顺序粘）

### 1. 在**主服务器**（`ssh orderflow-vps`）上生成一把专用密钥

```sh
ssh-keygen -t ed25519 -N '' -C 'kanpan-offsite' -f /root/.ssh/kanpan-offsite
chmod 600 /root/.ssh/kanpan-offsite
cat /root/.ssh/kanpan-offsite.pub
```

`-N ''` 是无口令：systemd 里没人能替它输。这把钥匙只用来推备份，不要拿去做别的。
把最后一行打印出来的公钥复制下来，下一步要用。

### 2. 在**备用服务器**（`ssh trade-vps-old`）上收下这把公钥

把下面的 `<粘贴第 1 步的公钥>` 换成刚才那一行完整内容（`ssh-ed25519 AAAA... kanpan-offsite`）：

```sh
install -d -m 700 /root/.ssh
install -d -m 700 /var/backups/kanpan-offsite
cat >> /root/.ssh/authorized_keys <<'EOF'
from="107.174.172.10",no-agent-forwarding,no-port-forwarding,no-pty,no-user-rc,no-X11-forwarding <粘贴第 1 步的公钥>
EOF
chmod 600 /root/.ssh/authorized_keys
tail -n 1 /root/.ssh/authorized_keys
```

**为什么不加 `command=` 限制。** `command="..."` 会把这把钥匙锁死在一条固定命令上，
但 rsync 的服务端不是一条固定命令：客户端每次把自己的一整串参数（`rsync --server -logDtpre.iLsfxCIvu . <路径>`）
当作远端命令发过去，参数随版本、随选项而变，写死任何一条都会让 rsync 直接失败。
而且 `offsite-push.sh` 除了 rsync 还要跑第二条 ssh 做「远端复验 → 改名转正 → 清理 30 份以外的」，
单条 `command=` 连它也一并挡掉。所以这里靠 `from="107.174.172.10"` 锁死来源地址，
再加 `no-pty,no-port-forwarding,no-agent-forwarding` 砍掉交互与转发——真要绕过它，
得先拿到这把私钥**并且**能从主服务器那个 IP 发包。

**可选加固：rrsync。** rsync 自带一个 `rrsync` 包装脚本，专门干 `command=` 干不了的事：
它解析 `$SSH_ORIGINAL_COMMAND`、确认那确实是一次 rsync 服务端调用、并把它关进指定目录。
先在备用服务器上看它在不在：

```sh
command -v rrsync; ls -l /usr/share/doc/rsync/scripts/rrsync* 2>/dev/null
```

Ubuntu 22.04 的 rsync 包把它放在 `/usr/share/doc/rsync/scripts/rrsync`（有的构建是
`rrsync.gz`），更新的版本直接装成 `/usr/bin/rrsync`。在的话：

```sh
# 只有在上面那条真的列出文件时才跑
[ -f /usr/share/doc/rsync/scripts/rrsync.gz ] && gunzip -c /usr/share/doc/rsync/scripts/rrsync.gz > /usr/local/bin/rrsync
[ -f /usr/share/doc/rsync/scripts/rrsync ]    && cp /usr/share/doc/rsync/scripts/rrsync /usr/local/bin/rrsync
chmod 755 /usr/local/bin/rrsync
```

然后 authorized_keys 里那一行的 `from=` 后面补上
`,command="/usr/local/bin/rrsync /var/backups/kanpan-offsite"`。
**但这样就只剩 rsync 能跑了**，`offsite-push.sh` 的复验/改名/清理那条 ssh 会被挡。
要走这条路就再发一把钥匙，专给管家活儿，并锁在一个自己写的脚本上：

```sh
# 备用服务器
cat > /usr/local/sbin/kanpan-offsite-housekeep <<'EOF'
#!/bin/sh
set -eu
cd /var/backups/kanpan-offsite
for d in *.part; do [ -d "$d" ] || continue; mv "$d" "${d%.part}"; chmod 700 "${d%.part}"; done
ls -1d [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]/ 2>/dev/null \
  | sed 's:/$::' | sort -r | tail -n +31 | xargs -r rm -rf
EOF
chmod 755 /usr/local/sbin/kanpan-offsite-housekeep
```

配上 `command="/usr/local/sbin/kanpan-offsite-housekeep",from="107.174.172.10",no-pty,...`
的第二把钥匙，再把 `offsite-push.sh` 里那条 ssh 换成用它。
**默认不走这条**：多一把钥匙多一处要维护，而 `from=` + `no-pty` 对只有三个用户、
两台自有 VPS 的摊子已经够了。记在这里是为了以后需要时不用重新想一遍。

### 3. 回到**主服务器**，认一次备用服务器的主机指纹并试通

```sh
ssh-keyscan -p 33333 -H 96.44.162.222 >> /root/.ssh/known_hosts
ssh -i /root/.ssh/kanpan-offsite -o BatchMode=yes -p 33333 -o IdentitiesOnly=yes root@96.44.162.222 true && echo 通了
```

脚本用的是 `BatchMode=yes`，没认过指纹会直接失败而不是停下来问。这一步必须先过。

### 4. 在**主服务器**上装脚本与单元文件

`/opt/kanpan-api` 是部署目录；仓库更新到那里之后：

```sh
cd /opt/kanpan-api
ls -l ops/offsite-push.sh ops/kanpan-offsite-push.service ops/kanpan-offsite-push.timer
cp ops/kanpan-offsite-push.service ops/kanpan-offsite-push.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now kanpan-offsite-push.timer
```

### 5. 手动跑一次，看它真的落地了

```sh
systemctl start kanpan-offsite-push.service
systemctl status kanpan-offsite-push.service --no-pager
journalctl -u kanpan-offsite-push -n 30 --no-pager
systemctl list-timers kanpan-offsite-push.timer --no-pager
```

journal 里应该有一行像
`offsite-push: kanpan-20260919-000004.dump → root@96.44.162.222:/var/backups/kanpan-offsite/20260919-002011  3.4 MiB  远端共 1 份`。
再去备用服务器眼见为实：

```sh
ssh trade-vps-old 'ls -la /var/backups/kanpan-offsite/ && ls -la /var/backups/kanpan-offsite/*/ | tail -20'
```

要看到目录 `drwx------`、三个文件 `-rw-------`，而且 `service.env`、`database.env`、
`kanpan-*.dump` 三件齐全。

> 定时用的是**服务器本地时区**（`timedatectl` 看一眼，线上是 UTC）。备份 00:00 起跑、
> 带最多 10 分钟随机延迟，所以这里定的 00:20 推的一定是当天那份。

---

## 二、Mac 侧（按顺序粘）

### 1. 先确认免口令能连上主服务器

```sh
ssh -o BatchMode=yes -o ConnectTimeout=20 orderflow-vps true && echo 通了
```

不通就是私钥带口令。launchd 里没人能替你输，两条路选一条：换一把无口令的钥匙，
或者把口令存进钥匙串并在 `~/.ssh/config` 里给 `orderflow-vps` 补上
`AddKeysToAgent yes` / `UseKeychain yes`，然后 `ssh-add --apple-use-keychain ~/.ssh/<私钥>`。

### 2. 手动试跑一次

```sh
mkdir -p ~/kanpan-backups
bash /Users/mdd/zhk/kanpan/Backend/kanpan-api/ops/offsite-pull.sh
ls -la ~/kanpan-backups/
ls -la ~/kanpan-backups/*/ | tail -20
```

应该打印一行
`… offsite-pull: /Users/mdd/kanpan-backups/20260919-171500 ← orderflow-vps:kanpan-20260919-000004.dump  3.4 MiB  共 1 份（本轮清掉 0 份）`，
并且目录 `drwx------`、三个文件 `-rw-------`。

### 3. 装上定时

```sh
cp /Users/mdd/zhk/kanpan/Backend/kanpan-api/ops/offsite-pull.launchd.plist \
   ~/Library/LaunchAgents/com.mdd.kanpan.offsite-pull.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.mdd.kanpan.offsite-pull.plist
launchctl enable gui/$(id -u)/com.mdd.kanpan.offsite-pull
launchctl print gui/$(id -u)/com.mdd.kanpan.offsite-pull | head -20
```

### 4. 让 launchd 自己跑一次（不等到 01:00）

```sh
launchctl kickstart -p gui/$(id -u)/com.mdd.kanpan.offsite-pull
sleep 30; tail -n 20 ~/kanpan-backups/pull.log
```

改了 plist 之后要先 `launchctl bootout gui/$(id -u)/com.mdd.kanpan.offsite-pull` 再重新
bootstrap，`launchctl` 不会自动重读。

### 5. 平时怎么看它有没有在跑

```sh
tail -n 5 ~/kanpan-backups/pull.log
ls -1 ~/kanpan-backups/ | tail -5
```

日志最后一行的日期不是昨天或今天，就是断了——多半是 Mac 那几天关着，或者到主服务器的
钥匙换过了。`pull.log` 只追加不轮转；大到碍事时直接 `: > ~/kanpan-backups/pull.log`。

---

## 三、恢复演练：在一台新机器上把这一组还原成一个能登录的实例

**这一节要真的做一遍。**没演练过的备份只是三个文件，不是备份。`install.py` 里那段
「env 缺失而库里还有账号就拒绝安装」的告警说的就是这件事：pepper 对不上时没有任何报错，
只有真去登一次才知道这份备份是不是活的。

**顺序只有一种：先把转储灌回来，再跑 migrations。** 反过来——让 `install.py` 先把 schema
建全、再往上灌转储——只有两种结局：`pg_restore --single-transaction` 撞上已经存在的表，整趟
回滚；或者没开 `--exit-on-error` 时把两份 schema 掺在一起，留下一个谁也说不清的库。而灌完
不跑 migrations 也一样错：上个月的转储配这个月的二进制，第一次写就撞在缺掉的列上。
下面五步就是这个顺序，第 2 步只借 `install.py` 把容器和角色建出来，真正算数的那次 migrate
在第 4 步、也就是灌完之后。

### 0. 先看清 `ops/install.py` 要什么

它认四种起手状态，差别全在密钥上：

| `/etc/kanpan-api/` 里有什么 | 它怎么做 |
| --- | --- |
| `service.env` + `database.env` 都在 | 全读，一把新密钥都不生成。恢复演练走的是这一行 |
| `service.env` 在、`database.env` 不在 | 只现生成一把新的 `kanpan_admin` 口令写回 `database.env`（目录 700 / 文件 600），并在 migrate **之前**用容器内的 psql `ALTER ROLE kanpan_admin PASSWORD` 把角色改成这一把；`KANPAN_PASSWORD_PEPPER` 与 `KANPAN_ENCRYPTION_KEY` 一个字都不动。所以只带回来半套 env 也救得回来 |
| `service.env` 不在、库里还有账号 | **中止**，并告诉你去把原来那份 env 找回来 |
| `service.env` 不在、库也是空的 | 全新安装，三把钥匙都是新的 |

（第二行为什么非得 `ALTER ROLE`：`POSTGRES_PASSWORD` 只在 initdb 那一次生效，卷已经存在时
容器里那个角色的口令还是旧的，而 migrate 是走 `127.0.0.1:55434` 的 TCP、要口令；容器内的
psql 走 Unix socket、认 trust，不要口令。所以先改角色，再 migrate，顺序不能反。）

它做的事按顺序是：

1. 按上表读或补出 `kanpan_app`（来自 `KANPAN_DATABASE_URL`）与 `kanpan_admin`
   （来自 `database.env`）这两个口令。所以 `service.env` 必须在跑它之前就位。
2. 没有 `kanpan-postgres` 容器就起一个（`pgvector/pgvector:0.8.2-pg17`，回环 55434，
   卷名 `kanpan-postgres`）。
3. 需要时先 `ALTER ROLE kanpan_admin`（见上表第二行），再建 `kanpan_app` 角色
   （口令取自 URL），然后用 `kanpan_admin` 跑
   `/opt/kanpan-api/target/release/kanpan-api migrate`，再把四种语句权限授给 `kanpan_app`。
4. 写 `kanpan-api` / `kanpan-worker` / `kanpan-backup` 的单元文件并 `enable --now`。

所以新机器上要先有：Docker、systemd、python3，以及 `/opt/kanpan-api`（源码树 + 已编译的
`target/release/kanpan-api`——路径是写死的）。它是**幂等**的，下面会跑两遍。

### 1. 把离机的那一组取到演练机

```sh
# 从 Mac 那份（挑最新的一个时间戳目录）
scp -r ~/kanpan-backups/<时间戳>/ root@<演练机>:/root/restore/
# 或者从备用服务器那份
ssh trade-vps-old 'ls -1 /var/backups/kanpan-offsite/ | tail -3'
scp -r trade-vps-old:/var/backups/kanpan-offsite/<时间戳>/ root@<演练机>:/root/restore/
```

### 2. 演练机：放好 env，跑一次 install.py

```sh
install -d -m 700 /etc/kanpan-api
install -m 600 /root/restore/service.env  /etc/kanpan-api/service.env
install -m 600 /root/restore/database.env /etc/kanpan-api/database.env   # 这一份丢了也行，见第 0 步

cd /opt/kanpan-api
python3 ops/install.py
# 它跑完会 `enable --now kanpan-api kanpan-worker kanpan-backup.timer`。三个都要停：
# 前两个连着下一步要 DROP 的库，timer 则会在演练中途（每天 00:10）给这个半恢复状态的库
# 打一份转储，那一份会挤进 30 份保留队列，还会被离机链路当成「最新一份」带走。
systemctl stop kanpan-api kanpan-worker kanpan-backup.timer
# 正式机上才有这一个（第一节装的）；演练机上没有就不用管。
systemctl stop kanpan-offsite-push.timer 2>/dev/null || true
```

这一趟要的只有两样：容器，和 `kanpan_app` 角色——转储里带着指向它的 `GRANT`，角色不在就
恢复不进去。它顺手建出来的那套空 schema 是垃圾，下一步整个库都会被 `DROP`；这一趟的
migrate 也不算数，算数的那次在第 4 步。

### 3. 演练机：把转储灌进去

```sh
systemctl stop kanpan-api kanpan-worker      # 上一步已经停过；再确认一次，有连接在就 DROP 不掉

# 要灌的是哪一份，先说清楚再用。`< /root/restore/kanpan-*.dump` 这种写法在目录里有两份
# 转储时是 ambiguous redirect（sh 直接报错不跑），只有一份时又让人以为自己选过了。
dump=$(ls -1t /root/restore/kanpan-*.dump | head -n 1)
ls -l "$dump"

docker exec -i kanpan-postgres psql -U kanpan_admin -d postgres -v ON_ERROR_STOP=1 \
  -c 'DROP DATABASE kanpan WITH (FORCE);' -c 'CREATE DATABASE kanpan OWNER kanpan_admin;'

docker exec -i kanpan-postgres pg_restore -U kanpan_admin -d kanpan \
  --exit-on-error --single-transaction --no-owner < "$dump"
```

先 `DROP` 再 `CREATE` 是为了灌进一个干净的库：第 2 步刚 migrate 出来的空表和转储里的表
会打架，而 `--single-transaction` 要求整趟不出错。转储是 `-Fc`（custom），
所以只能用 `pg_restore`，不是 `psql`。

`--no-owner` 是必须的：转储里每张表都带着 `ALTER ... OWNER TO`，写的是**备份那台机器上**的
属主名。演练机（或者重建出来的新机器）上那个角色未必叫同一个名字、也未必存在，于是
`--exit-on-error --single-transaction` 会让整趟回滚，看上去像转储坏了。`--no-owner` 让所有
对象归执行恢复的 `kanpan_admin`，权限则由第 4 步的 `install.py` 重新授给 `kanpan_app`——
两边合起来正好是这个库该有的样子。

### 4. 演练机：再跑一次 install.py——**这一趟的 migrate 才是算数的那次**

```sh
cd /opt/kanpan-api
python3 ops/install.py     # 幂等；migrate 把刚灌进去的库升到当前二进制，并重新把权限授给 kanpan_app
systemctl start kanpan-api kanpan-worker
systemctl status kanpan-api --no-pager
```

转储是那天的 schema，`/opt/kanpan-api` 里的二进制是今天的。这一趟的 `migrate` 把中间缺的
那几次迁移补上——所以**不能跳过**，哪怕上一趟已经跑过一次：上一趟跑的是那个已经被 `DROP`
掉的库。`pg_restore` 只负责把那天的样子放回来，往前走这一段是 migrations 的事。

### 5. 验收：数据在不在，钥匙对不对

```sh
# 账号数对得上吗
docker exec -i kanpan-postgres psql -tAq -U kanpan_admin -d kanpan \
  -c 'SELECT count(*) FROM account_users'
# 服务活着吗
curl -s http://127.0.0.1:8794/v1/capabilities | head -c 400; echo
```

**最关键的一步是真的登一次。**能力接口 200 只说明进程起来了，说明不了 pepper 对不对——
pepper 错的时候库照样读得出来，只是每个人的密码都验不过，一个错都不报。
拿一个已知口令的测试账号打真接口：

```sh
U=<测试账号用户名>; P=<测试账号密码>
curl -sS -X POST http://127.0.0.1:8794/v1/auth/login \
  -H 'content-type: application/json' \
  -d "{\"username\":\"$U\",\"password\":\"$P\",\"device\":{\"id\":\"$(uuidgen | tr 'A-Z' 'a-z')\",\"name\":\"restore-drill\",\"secret\":\"$(python3 -c 'import secrets;print(secrets.token_hex(24))')\"}}"
echo
```

- 回来带 `accessToken`/`refreshToken` 的信封 → **这份备份是活的**：数据、pepper、
  encryption key 三件都对上了。
- 回 `401 unauthorized` 而账号数又不是 0 → `service.env` 和这份转储不是同一组，
  或者 env 被换过。这正是必须把三件当一组拉/推、而不是各存各的的原因。

顺手再验一次同步（`KANPAN_ENCRYPTION_KEY` 走的是这条路）：拿上一步的 `accessToken`

```sh
T=<上一步的 accessToken>
curl -sS -H "authorization: Bearer $T" http://127.0.0.1:8794/v1/sync/bootstrap | head -c 400; echo
```

### 收摊（第 5 步过了之后）

演练机**不要**接进 Caddy、不要对外开端口（`KANPAN_BIND` 本来就只听 `127.0.0.1:8794`），
也不要让它的 `kanpan-backup.timer` 继续跑，否则会多出一份来路不明的转储：

```sh
systemctl disable --now kanpan-backup.timer kanpan-api kanpan-worker
systemctl disable --now kanpan-offsite-push.timer 2>/dev/null || true
docker rm -f kanpan-postgres && docker volume rm kanpan-postgres
shred -u /root/restore/* 2>/dev/null || rm -rf /root/restore
rm -rf /etc/kanpan-api
```

演练机上留着一份 pepper 就是多一个泄漏面。做完就擦干净。

**如果这不是演练、而是真在一台要继续服务的机器上恢复**，那就反过来：别擦任何东西，把第 2
步停掉的两个 timer 重新起来，否则这台机器从此不再备份、也不再往外推。

```sh
systemctl enable --now kanpan-backup.timer
systemctl enable --now kanpan-offsite-push.timer     # 第一节装过才有
systemctl list-timers 'kanpan-*' --no-pager          # 两条都该列出下一次触发时间
```

---

## 四、哪里会坏，怎么看出来

| 症状 | 原因 | 处置 |
| --- | --- | --- |
| journal 里 `offsite-push: 连不上 root@96.44.162.222` | 指纹没认 / `from=` 里的 IP 写错 / 公钥没生效 | 重做第一节第 3 步；备用服务器上 `journalctl -u ssh -n 50` 看拒绝原因 |
| `offsite-push: … 只有 N 字节（不到 1 MiB），不推` | 当天的 `pg_dump` 是空壳，多半是容器没起来 | `docker ps`、`systemctl start kanpan-backup.service` 重备一次 |
| `offsite-push: service.env 里 KANPAN_PASSWORD_PEPPER 是空的` | env 被改坏了 | **先别动**，去 Mac 或备用服务器上最近一份副本里把原值找回来 |
| `pull.log` 好几天没有新行 | Mac 关着，或者到主服务器的钥匙带口令了 | 第二节第 1 步重验一遍免口令 |
| 远端 `<时间戳>.part` 目录堆着没转正 | 复验没过或者 ssh 断在收尾那一步 | 看 journal；`.part` 超过 12 小时下一轮会自己清掉，不占保留名额 |
| `kanpan backup aborted: … needs N KiB (twice the last dump)` | `/var/backups/kanpan` 的剩余空间不够写下一份 | 这是主动停手、**没有**写出半份转储。清掉旧转储或者扩盘，再 `systemctl start kanpan-backup.service` |
| 本机 `/var/backups/kanpan` 里有 `kanpan-*.dump.part` | 上一次 `pg_dump` 没写完（容器没起来、盘满、机器重启） | 那一份是废的；下一轮开头会扫掉十二小时以上的 `.part`，要立刻重备就 `systemctl start kanpan-backup.service` |
| `install.py` 打印「database.env 不在，已生成一把新的数据库管理员口令」 | 只带回来半套 env | 正常，不用管：加密用的两把在 `service.env` 里，没被动过 |

两条链路各自独立：一条断了另一条照旧。但**两条都断了不会有人告诉你**——所以上面那两条
「平时怎么看」的命令值得偶尔手动敲一次，以及每隔一段时间把第三节的恢复演练真的走一遍。
