import os,pathlib,secrets,subprocess,time
from urllib.parse import urlsplit
root=pathlib.Path('/etc/kanpan-api');root.mkdir(mode=0o700,exist_ok=True)
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
   '确实要从零开始（放弃所有账号）：docker volume rm kanpan-postgres 之后再装。')
 admin=secrets.token_hex(32);password=secrets.token_hex(32)
 dbfile.write_text('POSTGRES_USER=kanpan_admin\nPOSTGRES_DB=kanpan\nPOSTGRES_PASSWORD='+admin+'\n');dbfile.chmod(0o600)
 envfile.write_text('KANPAN_DATABASE_URL=postgres://kanpan_app:'+password+'@127.0.0.1:55434/kanpan\nKANPAN_PASSWORD_PEPPER='+secrets.token_hex(32)+'\nKANPAN_ENCRYPTION_KEY='+secrets.token_hex(32)+'\nKANPAN_BIND=127.0.0.1:8794\nRUST_LOG=warn\n');envfile.chmod(0o600)
else:
 config=dict(line.split('=',1) for line in envfile.read_text().splitlines() if '=' in line)
 database=dict(line.split('=',1) for line in dbfile.read_text().splitlines() if '=' in line)
 admin=database['POSTGRES_PASSWORD'];password=urlsplit(config['KANPAN_DATABASE_URL']).password
 assert password and all(c in '0123456789abcdef' for c in password)
if subprocess.run(['docker','inspect','kanpan-postgres'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode!=0:
 subprocess.run(['docker','run','-d','--name','kanpan-postgres','--restart','unless-stopped','--memory','512m','--cpus','0.75','--env-file',str(dbfile),'-p','127.0.0.1:55434:5432','-v','kanpan-postgres:/var/lib/postgresql/data','pgvector/pgvector:0.8.2-pg17'],check=True,stdout=subprocess.DEVNULL)
for _ in range(30):
 if subprocess.run(['docker','exec','kanpan-postgres','pg_isready','-h','127.0.0.1','-U','kanpan_admin','-d','kanpan'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0:break
 time.sleep(1)
def sql(query):
 p=subprocess.run(['docker','exec','-i','kanpan-postgres','psql','-q','-U','kanpan_admin','-d','kanpan','-v','ON_ERROR_STOP=1'],input=query,text=True,capture_output=True)
 if p.returncode:raise RuntimeError('Database configuration failed (details withheld)')
sql(f"DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='kanpan_app') THEN CREATE ROLE kanpan_app LOGIN PASSWORD '{password}' NOSUPERUSER NOBYPASSRLS; END IF; END $$;")
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
pathlib.Path('/etc/systemd/system/kanpan-backup.service').write_text("""[Unit]
Description=Kanpan database backup
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
subprocess.run(['systemctl','enable','--now','kanpan-api','kanpan-worker','kanpan-backup.timer'],check=True)
print('Dedicated account database and nonprivileged API enabled; no mail service.')
