import concurrent.futures, hashlib, json, subprocess, threading, time
from pathlib import Path
ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parents[2]
devices = json.loads((PROJECT / 'docs/acceptance/AICoin-base/compatibility/devices.json').read_text())
order = ['iPhone 15', 'iPad Pro 13-inch (M5)', 'iPhone 17e', 'iPhone 17 Pro', 'iPhone 17', 'iPhone 17 Pro Max', 'iPhone 16 Pro', 'iPhone 16 Plus', 'iPhone Air', 'iPad mini (A17 Pro)', 'iPad (A16)', 'iPad Air 11-inch (M4)', 'iPad Pro 11-inch (M5)']
stop = threading.Event()
lock = threading.Lock()
source = {str(p.relative_to(PROJECT)): hashlib.sha256(p.read_bytes()).hexdigest() for folder in ['Kanpan/Kanpan','Kanpan/KanpanUITests','KanpanCore/Sources','KanpanData/Sources','KanpanChart/Sources'] for p in (PROJECT/folder).rglob('*.swift')}
(ROOT/'current-r4-source-sha256.json').write_text(json.dumps(source,indent=2))

def run(name):
    if stop.is_set(): return
    device = next(d for d in devices if d['name'] == name)
    slug = name.replace(' ','-').replace('(','').replace(')','') + '-current-r4'
    bundle = ROOT/(slug+'.xcresult')
    if bundle.exists():
        print('Preserve existing',name,flush=True); return
    tests = ['testComfortPalettesAndLayout','testFavoritesDirectRowReorder']
    if name == 'iPhone 15': tests += ['testFavoritesCategoryOverflow','testLatestQuoteDoesNotRegressAcrossIntervals','testQuickFavoritesAndMarketSectors','testFourSubpanelsFitWithoutPageScroll','testLatestEdgeAndReentryCompatibility']
    cmd = ['xcodebuild','test-without-building','-workspace','Kanpan.xcworkspace','-scheme','Kanpan','-destination','platform=iOS Simulator,id='+device['udid'],'-derivedDataPath','DerivedData-codex-current-r3','-parallel-testing-enabled','NO','-resultBundlePath',str(bundle)]
    cmd += ['-only-testing:KanpanUITests/ChartFoundationUITests/'+t for t in tests]
    print('START',name,flush=True)
    begin=time.time()
    with (ROOT/(slug+'.log')).open('w') as out: rc=subprocess.call(cmd,cwd=PROJECT,stdout=out,stderr=subprocess.STDOUT)
    result={'name':name,'exitCode':rc,'seconds':round(time.time()-begin),'expectedTests':len(tests)}
    detail=subprocess.run(['xcrun','xcresulttool','get','test-results','summary','--path',str(bundle)],capture_output=True,text=True)
    if detail.returncode==0:
        data=json.loads(detail.stdout); (ROOT/(slug+'-summary.json')).write_text(detail.stdout)
        result.update({k:data.get(k) for k in ['result','passedTests','failedTests','skippedTests']})
    if result.get('passedTests')!=len(tests) or result.get('failedTests')!=0 or result.get('skippedTests')!=0: result['exitCode']=rc or 1
    with lock:
        with (ROOT/'current-r4-runs.jsonl').open('a') as out: out.write(json.dumps(result,ensure_ascii=False)+'\n')
    print('DONE',result,flush=True)
    subprocess.run(['xcrun','simctl','shutdown',device['udid']],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    if result['exitCode']: stop.set()
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    list(pool.map(run,order))
raise SystemExit(1 if stop.is_set() else 0)
