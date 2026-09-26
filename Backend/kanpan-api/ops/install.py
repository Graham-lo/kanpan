import os,pathlib,secrets,subprocess,sys,time
from urllib.parse import urlsplit
root=pathlib.Path('/etc/kanpan-api');root.mkdir(mode=0o700,exist_ok=True)
# exist_ok 不会去改一个已经存在的目录的权限，而这个目录里放的是 pepper 和加密密钥：
# 恢复演练时它常常是手工 mkdir 出来的，按 umask 就成了 755。每次都按回 700。
root.chmod(0o700)
envfile=root/'service.env';dbfile=root/'database.env'
def quiet(*command):
 return subprocess.run(command,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0
def accounts_present():
 """库里还留着账号吗。True 有、False 没有、None 问不出来（有数据但现在够不着）。"""
 if not quiet('docker','volume','inspect','kanpan-postgres'):return False
 if not quiet('docker','inspect','kanpan-postgres'):return None
 p=subprocess.run(['docker','exec','-i','kanpan-postgres','psql','-tAq','-U','kanpan_admin','-d','kanpan','-c','SELECT count(*) FROM account_users'],capture_output=True,text=True)
 if p.returncode:return False if 'does not exist' in (p.stderr or '') else None
 return int((p.stdout.strip() or '0').splitlines()[-1])>0
if not envfile.exists():
 # 没有 env 文件就现生成一把新密钥——但 KANPAN_PASSWORD_PEPPER 是拌进 Argon2 的，
 # 换一把等于把库里每个人的密码都改成没人知道的值；KANPAN_ENCRYPTION_KEY 换掉之后
 # 密封的刷新结果也再解不开。这两件事都不会报错，只会让每个人登录时被告知
 # 「用户名或密码不对」，而且旧密钥一旦没被写下来就再也补不回来。
 # 所以库里还有账号时必须停在这里，让人先去把原来那份钥匙找回来。
 if accounts_present() is not False:
  raise SystemExit(
   '中止：/etc/kanpan-api/service.env 不在，但 kanpan-postgres 的数据还在。\n'
   '现在生成的新 KANPAN_PASSWORD_PEPPER 会让所有现存密码永远验不过，\n'
   '新的 KANPAN_ENCRYPTION_KEY 会让已密封的数据永远解不开，而且不会有任何报错。\n'
   '请先把原来那份 service.env（至少是其中的 PEPPER 与 ENCRYPTION_KEY）放回 /etc/kanpan-api/，\n'
   '它和数据库备份是分开保存的两样东西，缺一不可。\n'
   '确实要从零开始（放弃所有账号）：docker volume rm kanpan-postgres 之后再装。\n'
   '（只丢了 database.env、service.env 还在，是另一回事：那种情况这个脚本会自己补一把'
   '数据库口令，PEPPER 与 ENCRYPTION_KEY 一个字都不动。）')
 admin=secrets.token_hex(32);password=secrets.token_hex(32);reset_admin=True
 dbfile.write_text('POSTGRES_USER=kanpan_admin\nPOSTGRES_DB=kanpan\nPOSTGRES_PASSWORD='+admin+'\n');dbfile.chmod(0o600)
 envfile.write_text('KANPAN_DATABASE_URL=postgres://kanpan_app:'+password+'@127.0.0.1:55434/kanpan\nKANPAN_PASSWORD_PEPPER='+secrets.token_hex(32)+'\nKANPAN_ENCRYPTION_KEY='+secrets.token_hex(32)+'\nKANPAN_BIND=127.0.0.1:8794\nRUST_LOG=warn\n');envfile.chmod(0o600)
else:
 config=dict(line.split('=',1) for line in envfile.read_text().splitlines() if '=' in line)
 password=urlsplit(config['KANPAN_DATABASE_URL']).password
 assert password and all(c in '0123456789abcdef' for c in password)
 if dbfile.exists():
  database=dict(line.split('=',1) for line in dbfile.read_text().splitlines() if '=' in line)
  admin=database['POSTGRES_PASSWORD'];reset_admin=False
 else:
  # service.env 在、database.env 不在。这是离机恢复最常见的半套状态（两份 env 是分开
  # 保存的，只带回来一份），以前到这里是一个 FileNotFoundError。
  #
  # 这一把补起来是安全的：database.env 里只有 kanpan_admin 这个数据库超级用户的口令，
  # 它不参与任何加密——换掉它没人会因此登不上。真正不能重生成的两把（拌进 Argon2 的
  # KANPAN_PASSWORD_PEPPER、密封数据用的 KANPAN_ENCRYPTION_KEY）都在 service.env 里，
  # 而那一份还在，所以这条分支一个字都不碰它。
  #
  # 但只写文件是不够的：POSTGRES_PASSWORD 只在 initdb 那一次生效，卷已经存在时容器里
  # 那个角色的口令还是旧的，而下面的 migrate 是走 127.0.0.1:55434（TCP，要口令）的。
  # 所以下面在 migrate 之前，先用容器内的 psql 把角色的口令改成这一把。
  admin=secrets.token_hex(32);reset_admin=True
  dbfile.write_text('POSTGRES_USER=kanpan_admin\nPOSTGRES_DB=kanpan\nPOSTGRES_PASSWORD='+admin+'\n');dbfile.chmod(0o600)
  print('database.env 不在，已生成一把新的数据库管理员口令；service.env 里的 PEPPER 与 ENCRYPTION_KEY 未改动。')
if subprocess.run(['docker','inspect','kanpan-postgres'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode!=0:
 subprocess.run(['docker','run','-d','--name','kanpan-postgres','--restart','unless-stopped','--memory','512m','--cpus','0.75','--env-file',str(dbfile),'-p','127.0.0.1:55434:5432','-v','kanpan-postgres:/var/lib/postgresql/data','pgvector/pgvector:0.8.2-pg17'],check=True,stdout=subprocess.DEVNULL)
for _ in range(30):
 if subprocess.run(['docker','exec','kanpan-postgres','pg_isready','-h','127.0.0.1','-U','kanpan_admin','-d','kanpan'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0:break
 time.sleep(1)
def sql(query):
 p=subprocess.run(['docker','exec','-i','kanpan-postgres','psql','-q','-U','kanpan_admin','-d','kanpan','-v','ON_ERROR_STOP=1'],input=query,text=True,capture_output=True)
 if p.returncode:raise RuntimeError('Database configuration failed (details withheld)')
# 容器内的 psql 走 Unix socket，认的是 trust，不需要口令——所以这一步在口令还没对上的
# 时候也做得到，而下一步走 TCP 的 migrate 做不到。顺序不能反。
if reset_admin:sql(f"ALTER ROLE kanpan_admin PASSWORD '{admin}';")
sql(f"DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='kanpan_app') THEN CREATE ROLE kanpan_app LOGIN PASSWORD '{password}' NOSUPERUSER NOBYPASSRLS; END IF; END $$;")
# 角色已经在的时候上面那句什么都不做，口令还是卷里原来那一把；而服务连库用的是
# service.env 里这一把。两份对不上的常见路子：卷在、service.env 是新生成的（库里没账号时
# 允许重装）、或者 service.env 从别处恢复回来。那样装完服务每次连库都是认证失败。
# 所以每次都把角色的口令与属性按 service.env 对齐一遍——幂等，口令没变时等于没做。
sql(f"ALTER ROLE kanpan_app LOGIN PASSWORD '{password}' NOSUPERUSER NOBYPASSRLS;")
# 迁移前先看有没有老事务卡着。迁移里的 CREATE INDEX／ALTER TABLE 要拿表锁，
# 而就算按 migrations/README.md 写成无锁的 CREATE INDEX CONCURRENTLY，它也要等自己开始
# 之前就已经在跑的事务全部结束；一个忘了提交的 psql 窗口就能把升级挂在那里，
# 而它挂着的时候后面的写请求照样排队。这里只做只读查询，把嫌疑打印出来就停下。
LONG_TRANSACTION_SECONDS=60
def long_transactions(seconds):
 query=("SELECT pid||' | '||coalesce(usename,'?')||' | '||coalesce(state,'?')||' | '"
  "||round(extract(epoch from now()-xact_start))||'s | '||left(regexp_replace(coalesce(query,''),'[\\s]+',' ','g'),120) "
  "FROM pg_stat_activity WHERE datname=current_database() AND pid<>pg_backend_pid() AND xact_start IS NOT NULL "
  "AND now()-xact_start>interval '%d seconds' ORDER BY xact_start"%seconds)
 p=subprocess.run(['docker','exec','-i','kanpan-postgres','psql','-tAq','-U','kanpan_admin','-d','kanpan','-c',query],capture_output=True,text=True)
 # 问不出来就不拦：这是一道提醒，不是新的失败点。
 return [line for line in p.stdout.splitlines() if line.strip()] if not p.returncode else []
def readonly(query):
 """只读地问一句。问不出来返回 None——这些都是提醒，不该变成新的失败点。"""
 p=subprocess.run(['docker','exec','-i','kanpan-postgres','psql','-tAq','-U','kanpan_admin','-d','kanpan','-c',query],capture_output=True,text=True)
 return None if p.returncode else [line for line in p.stdout.splitlines() if line.strip()]
# 迁移链的第一句是 0001 的 `CREATE EXTENSION IF NOT EXISTS vector`。pgvector 0.8.2 不是
# trusted 扩展，建它要超级用户；换句话说「用一个非特权角色跑迁移」在这条链上根本走不到
# 第二步。这台机器上 migrate 用的是 kanpan_admin（容器的 POSTGRES_USER，本身是超级用户），
# 所以全新安装没问题；但只要有人把这条 URL 换成普通角色，失败会发生在最前面、信息也不好懂。
# 这里提前说清楚。
extension=readonly("SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname='vector')::text||' '||COALESCE((SELECT rolsuper FROM pg_roles WHERE rolname='kanpan_admin')::text,'false')")
if extension and extension[0].split()==['false','false']:
 raise SystemExit('中止：库里还没有 vector 扩展，而 kanpan_admin 不是超级用户。\n'
  'migrations/0001_accounts.sql 第一句就是 CREATE EXTENSION vector，pgvector 不是 trusted 扩展，\n'
  '必须先由超级用户执行一次 `CREATE EXTENSION vector;`，之后这个脚本才跑得下去。')
# 0006 给 market_features 建的是唯一索引。它失败时 sqlx 只把 Postgres 的第一行错误往上抛，
# DETAIL 里那句「Key (…)=(…) is duplicated」会被吞掉，于是升级停在那里而看不出是哪几行。
# 所以升级前先只读地把重复自己数一遍，有就原样打出来。
if readonly("SELECT to_regclass('public.market_features') IS NOT NULL")==['t']:
 duplicates=readonly("SELECT market||' '||symbol||' '||timeframe||' '||start_at||' '||end_at||' '||model_id||' '||render_version||' '||source||' | '||count(*)||' 行 | '||array_agg(id)::text "
  "FROM market_features GROUP BY market,symbol,timeframe,start_at,end_at,model_id,render_version,source HAVING count(*)>1 ORDER BY 1")
 if duplicates:
  print('market_features 里有重复，0006 的唯一索引建不起来（sqlx 会把 Postgres 的 DETAIL 吞掉，所以先在这里列出来）：')
  for line in duplicates:print('  '+line)
  raise SystemExit('中止：先处理掉上面这些重复行（同一段行情被导入了两次，留一条即可）。本次没有执行任何迁移。')
stale=long_transactions(LONG_TRANSACTION_SECONDS)
if stale:
 print('以下事务已经开了超过 %d 秒，迁移（哪怕是 CONCURRENTLY）要等它们结束：'%LONG_TRANSACTION_SECONDS)
 for line in stale:print('  '+line)
 if '--force' not in sys.argv:
  raise SystemExit('中止：先让这些事务结束（或者确认它们无害后加 --force 重跑）。本次没有执行任何迁移。')
 print('--force：带着上面这些事务继续迁移。')
env=dict(os.environ);env['KANPAN_DATABASE_URL']='postgres://kanpan_admin:'+admin+'@127.0.0.1:55434/kanpan'
subprocess.run(['/opt/kanpan-api/target/release/kanpan-api','migrate'],env=env,check=True)
sql('GRANT USAGE ON SCHEMA public TO kanpan_app; GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO kanpan_app; GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO kanpan_app;')
unit='''[Unit]
Description=Kanpan accounts and personal sync
After=network-online.target docker.service
[Service]
DynamicUser=yes
WorkingDirectory=/opt/kanpan-api
EnvironmentFile=/etc/kanpan-api/service.env
ExecStart=/opt/kanpan-api/target/release/kanpan-api serve
Restart=on-failure
RestartSec=3
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
MemoryMax=1G
CPUQuota=200%
TasksMax=256
[Install]
WantedBy=multi-user.target
'''
# Only the API keeps a cache: it is where the open interest archive stores the
# day slices it downloads. The worker must not declare the same directory --
# each dynamic user owns its own, and the second one to start would take it.
cache='CacheDirectory=kanpan-api\nEnvironment=KANPAN_OI_CACHE=/var/cache/kanpan-api/oi\n'
pathlib.Path('/etc/systemd/system/kanpan-api.service').write_text(unit.replace('[Install]',cache+'[Install]'))
pathlib.Path('/etc/systemd/system/kanpan-worker.service').write_text(unit.replace('Kanpan accounts and personal sync','Kanpan review and maintenance worker').replace('kanpan-api serve','kanpan-api worker'))
# backup.sh 用 docker exec 去 kanpan-postgres 里 pg_dump。Persistent=true 的定时器在开机后
# 会立刻补跑错过的那一次，这时 docker 可能还没起来，那一天的备份就白白失败了。
pathlib.Path('/etc/systemd/system/kanpan-backup.service').write_text("""[Unit]
Description=Kanpan database backup
Requires=docker.service
After=docker.service
[Service]
Type=oneshot
ExecStart=/bin/sh /opt/kanpan-api/ops/backup.sh
UMask=0077
""")
pathlib.Path('/etc/systemd/system/kanpan-backup.timer').write_text("""[Unit]
Description=Daily Kanpan database backup
[Timer]
OnCalendar=daily
RandomizedDelaySec=10m
Persistent=true
[Install]
WantedBy=timers.target
""")
subprocess.run(['systemctl','daemon-reload'],check=True)
# 升级时服务早就在跑：`enable --now` 对在跑的服务什么都不做，于是 migrate 已经把表改了，
# 跑着的还是旧二进制（0021 删掉 sync_snapshots 之后旧二进制的每次推送都回 500），
# 直到有人想起来手工 restart。try-restart 只重启正在跑的那几个，没在跑的交给下一句拉起。
subprocess.run(['systemctl','try-restart','kanpan-api','kanpan-worker'],check=True)
subprocess.run(['systemctl','enable','--now','kanpan-api','kanpan-worker','kanpan-backup.timer'],check=True)
print('Dedicated account database and nonprivileged API enabled; no mail service.')
