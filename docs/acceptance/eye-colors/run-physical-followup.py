import json, plistlib, subprocess, time
from pathlib import Path
root=Path(__file__).resolve().parent
project=root.parents[2]
# Wait for the first suite to release the single connected physical device.
while not (root/'physical-r1-run.json').exists(): time.sleep(2)
products=project/'DerivedData-codex-eye-device/Build/Products'
config=plistlib.loads((products/'Kanpan_iphoneos26.5-arm64.xctestrun').read_bytes())
# This legacy gate permits the read-only user-session check selected below;
# the favorite-installation test is deliberately not selected.
config['KanpanUITests'].setdefault('EnvironmentVariables',{})['KANPAN_INSTALL_USER_FAVORITES']='1'
(products/'Kanpan-user-session.xctestrun').write_bytes(plistlib.dumps(config))
cmd=['xcodebuild','test-without-building','-xctestrun','DerivedData-codex-eye-device/Build/Products/Kanpan-user-session.xctestrun','-destination','platform=iOS,id=00008140-00010C902690801C','-parallel-testing-enabled','NO','-resultBundlePath',str(root/'physical-r2.xcresult'),'-only-testing:KanpanUITests/AICoinBaseUITests/testColdLaunchStylesAndChartInteractions','-only-testing:KanpanUITests/ChartFoundationUITests/testFavoritesCategoryOverflow','-only-testing:KanpanUITests/ChartFoundationUITests/testUserSessionFreshQuotesAndReorder']
start=time.time()
with (root/'physical-r2.log').open('w') as f: code=subprocess.call(cmd,cwd=project,stdout=f,stderr=subprocess.STDOUT)
r={'physical':True,'device':'iPhone 16 Pro','os':'26.6.1','expectedTests':3,'exitCode':code,'seconds':round(time.time()-start),'source':'physical-source-sha256.json','note':'Same compiled app/tests. Recheck notification-obstructed category test, cover styles and landscape, then read real favorites and verify live foreground/background sessions. Does not invoke favorite installation or reorder/move user rows.'}
s=subprocess.run(['xcrun','xcresulttool','get','test-results','summary','--path',str(root/'physical-r2.xcresult')],capture_output=True,text=True)
if s.returncode==0:
 (root/'physical-r2-summary.json').write_text(s.stdout)
 d=json.loads(s.stdout);r.update({k:d.get(k) for k in ['result','passedTests','failedTests','skippedTests']})
(root/'physical-r2-run.json').write_text(json.dumps(r,indent=2));print(json.dumps(r,indent=2),flush=True)
raise SystemExit(code)
