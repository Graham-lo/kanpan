import hashlib, json, subprocess, time
from pathlib import Path
root = Path(__file__).resolve().parent
project = root.parents[2]
tests = ['testColdLaunchFavoritesAndLiveQuotes', 'testComfortPalettesAndLayout',
 'testFavoritesCategoryOverflow', 'testFavoritesDirectRowReorder',
 'testQuickFavoritesAndMarketSectors', 'testLatestQuoteDoesNotRegressAcrossIntervals',
 'testLiveMarketUpdatesWithinSeconds', 'testHistoricalOIUsesChartPeriod',
 'testOutsideTapOnlyDismissesPanel', 'testFourSubpanelsFitWithoutPageScroll',
 'testCrosshairCenterDragAndOutsidePan', 'testDragIndicatorTitleReordersCompletePane',
 'testDataModesClearHeaderAndSelection', 'testMAParameterCancelAndSaveOutput',
 'testDeviceHistoricalPanPinchAndManualY', 'testLatestEdgeAndReentryCompatibility',
 'testTradFiSearchAndMarketData']
source = {str(p.relative_to(project)): hashlib.sha256(p.read_bytes()).hexdigest()
 for folder in ['Kanpan/Kanpan','Kanpan/KanpanUITests','KanpanCore/Sources','KanpanData/Sources','KanpanChart/Sources']
 for p in (project/folder).rglob('*.swift')}
(root/'physical-source-sha256.json').write_text(json.dumps(source, indent=2))
products=project/'DerivedData-codex-eye-device/Build/Products/Debug-iphoneos'
binaries={str(p.relative_to(project)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [products/'Kanpan.app/Kanpan.debug.dylib',products/'KanpanUITests-Runner.app/PlugIns/KanpanUITests.xctest/KanpanUITests']}
(root/'physical-binary-sha256.json').write_text(json.dumps(binaries,indent=2))
bundle=root/'physical-r1.xcresult'
cmd=['xcodebuild','test-without-building','-workspace','Kanpan.xcworkspace','-scheme','Kanpan','-destination','platform=iOS,id=00008140-00010C902690801C','-derivedDataPath','DerivedData-codex-eye-device','-parallel-testing-enabled','NO','-resultBundlePath',str(bundle)]
cmd+=['-only-testing:KanpanUITests/ChartFoundationUITests/'+t for t in tests]
start=time.time()
with (root/'physical-r1.log').open('w') as out: code=subprocess.call(cmd,cwd=project,stdout=out,stderr=subprocess.STDOUT)
r={'device':'iPhone 16 Pro','os':'26.6.1','physical':True,'expectedTests':len(tests),'tests':tests,'exitCode':code,'seconds':round(time.time()-start),'commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=project,text=True).strip(),'workingTreeNote':'Local pre-existing display name and app icon changes included in installation; not committed with test work. Test preferences are isolated; real market network.'}
s=subprocess.run(['xcrun','xcresulttool','get','test-results','summary','--path',str(bundle)],capture_output=True,text=True)
if s.returncode==0:
 (root/'physical-r1-summary.json').write_text(s.stdout)
 d=json.loads(s.stdout);r.update({k:d.get(k) for k in ['result','passedTests','failedTests','skippedTests']})
(root/'physical-r1-run.json').write_text(json.dumps(r,indent=2))
print(json.dumps(r,indent=2),flush=True)
raise SystemExit(code)
