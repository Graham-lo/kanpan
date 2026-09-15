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
try:
 env=dict(os.environ)
 env['KANPAN_TEST_ADMIN_URL']=urlunsplit(url._replace(path='/'+name))
 env['KANPAN_TEST_DATABASE_URL']=urlunsplit(url._replace(netloc=f'{role}:{password}@{url.hostname}:{url.port}',path='/'+name))
 env['KANPAN_TEST_ROLE']=role
 result=subprocess.run(['cargo','test','--package','kanpan-api','--','--test-threads=1'],cwd=root,env=env)
finally:
 admin(f'DROP DATABASE {name} WITH (FORCE); DROP ROLE {role};')
 print('Isolated test database and role removed.',flush=True)
raise SystemExit(result.returncode)
