import os,pathlib,secrets,subprocess,time
from urllib.parse import urlsplit
root=pathlib.Path('/etc/kanpan-api');root.mkdir(mode=0o700,exist_ok=True)
envfile=root/'service.env';dbfile=root/'database.env'
if not envfile.exists():
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
MemoryMax=256M
CPUQuota=100%
TasksMax=128
[Install]
WantedBy=multi-user.target
'''
pathlib.Path('/etc/systemd/system/kanpan-api.service').write_text(unit)
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
