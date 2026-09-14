import json, subprocess, time
from pathlib import Path
root=Path(__file__).resolve().parent
project=root.parents[2]
# Run after a simulator slot is free; prior failures remain in their evidence bundles.
bundle=root/'iphone15-final.xcresult'
cmd=['xcodebuild','test-without-building','-workspace','Kanpan.xcworkspace','-scheme','Kanpan','-destination','platform=iOS Simulator,id=3749DE35-5582-4066-8C14-9767B5559B70','-derivedDataPath','DerivedData-codex-current-r5','-parallel-testing-enabled','NO','-resultBundlePath',str(bundle),'-only-testing:KanpanUITests/ChartFoundationUITests/testFavoritesCategoryOverflow','-only-testing:KanpanUITests/ChartFoundationUITests/testQuickFavoritesAndMarketSectors']
start=time.time()
with (root/'iphone15-final.log').open('w') as f: rc=subprocess.call(cmd,cwd=project,stdout=f,stderr=subprocess.STDOUT)
summary=subprocess.run(['xcrun','xcresulttool','get','test-results','summary','--path',str(bundle)],capture_output=True,text=True)
if summary.returncode==0:
    (root/'iphone15-final-summary.json').write_text(summary.stdout)
    data=json.loads(summary.stdout)
    print({k:data.get(k) for k in ['result','passedTests','failedTests','skippedTests']},flush=True)
    if data.get('passedTests')!=2 or data.get('failedTests')!=0 or data.get('skippedTests')!=0: rc=rc or 1
subprocess.run(['xcrun','simctl','shutdown','3749DE35-5582-4066-8C14-9767B5559B70'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
(root/'iphone15-final-run.json').write_text(json.dumps({'exitCode':rc,'seconds':round(time.time()-start),'expectedTests':2},indent=2))
raise SystemExit(rc)
