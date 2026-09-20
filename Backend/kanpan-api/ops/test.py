"""Use a fresh database and a non-owner login role, never the production data."""
import os, pathlib, subprocess, uuid, shlex, secrets
from urllib.parse import urlsplit, urlunsplit
root=pathlib.Path(__file__).resolve().parents[1]
# The already running local PG container is infrastructure only; no Scorebook tables are touched.
source=pathlib.Path('/Users/mdd/zhk/scorebook-backend')
config={}
for line in (source/'.env').read_text().splitlines():
 if line.strip() and not line.startswith('#') and '=' in line:
  k,v=line.split('=',1)
  try: config[k]=shlex.split(v)[0]
  except IndexError: pass
url=urlsplit(config['DATABASE_URL'])
assert url.hostname in ('localhost','127.0.0.1') and url.port==55432
suffix=uuid.uuid4().hex[:12];name='kanpan_test_'+suffix;role='kanpan_app_'+suffix;password=secrets.token_hex(24)
command=['docker','compose','exec','-T','postgres','psql','-U','scorebook','-d','postgres','-q','-v','ON_ERROR_STOP=1']
def admin(sql):
 r=subprocess.run(command,input=sql,text=True,cwd=source,capture_output=True)
 if r.returncode: raise RuntimeError('Isolated PostgreSQL setup/cleanup failed')
admin(f"CREATE ROLE {role} LOGIN PASSWORD '{password}' NOSUPERUSER NOBYPASSRLS; CREATE DATABASE {name};")
# 夹具里有几处是拿 KANPAN_TEST_ADMIN_URL 这条连接直接摆数据的（tests/accounts.rs）。
# 复盘那几张表是 FORCE ROW LEVEL SECURITY——连表的属主都要按策略来——所以那些语句
# 能成立，靠的是这个角色本身越过 RLS。它现在是隐含前提，哪天这条 URL 换成普通属主，
# 表现不是报错而是「读到零行」：断言会静悄悄地白通过。所以在这里把前提写明白。
assert url.username and url.username.replace('_','').isalnum()
check=subprocess.run(command[:-3]+['-tAq','-c',"SELECT rolsuper OR rolbypassrls FROM pg_roles WHERE rolname='%s'"%url.username],text=True,cwd=source,capture_output=True)
if check.returncode or check.stdout.strip()!='t':
 admin(f'DROP DATABASE {name} WITH (FORCE); DROP ROLE {role};')
 raise SystemExit('中止：KANPAN_TEST_ADMIN_URL 用的角色必须能越过 RLS（超级用户或 BYPASSRLS），否则夹具读到的是零行而不是报错。')
try:
 env=dict(os.environ)
 env['KANPAN_TEST_ADMIN_URL']=urlunsplit(url._replace(path='/'+name))
 env['KANPAN_TEST_DATABASE_URL']=urlunsplit(url._replace(netloc=f'{role}:{password}@{url.hostname}:{url.port}',path='/'+name))
 env['KANPAN_TEST_ROLE']=role
 # --workspace 而不是 --package kanpan-api：领域逻辑住在 vendor/scorebook-core，
 # 复盘的判定规则就在那里，只跑 kanpan-api 等于把它那几十条单测一直晾着。
 result=subprocess.run(['cargo','test','--workspace','--','--test-threads=1'],cwd=root,env=env)
finally:
 admin(f'DROP DATABASE {name} WITH (FORCE); DROP ROLE {role};')
 print('Isolated test database and role removed.',flush=True)
raise SystemExit(result.returncode)
