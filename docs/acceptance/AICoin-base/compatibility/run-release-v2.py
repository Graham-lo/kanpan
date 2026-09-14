import concurrent.futures
import json
import subprocess
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parents[3]
stop = threading.Event()
lock = threading.Lock()
devices = json.loads((ROOT / "devices.json").read_text())
# Two simultaneous simulators; keep iPad coverage early and avoid memory pressure.
order = ["iPad Pro 13-inch (M5)", "iPhone 16 Plus", "iPhone 15", "iPad mini (A17 Pro)", "iPhone 16 Pro",
         "iPad (A16)", "iPhone 17", "iPad Air 11-inch (M4)",
         "iPhone 17 Pro Max", "iPad Pro 11-inch (M5)", "iPhone Air"]

def run(name):
    if stop.is_set(): return
    device = next(d for d in devices if d["name"] == name)
    slug = name.replace(" ", "-").replace("(", "").replace(")", "") + "-release-v2"
    result_path = ROOT / (slug + ".xcresult")
    if result_path.exists():
        print("EXISTS; preserve", name, flush=True)
        return
    print("START", name, flush=True)
    command = ["xcodebuild", "test-without-building", "-workspace", "Kanpan.xcworkspace",
               "-scheme", "Kanpan", "-destination", "platform=iOS Simulator,id=" + device["udid"],
               "-derivedDataPath", "DerivedData-codex-release-compat", "-parallel-testing-enabled", "NO",
               "-resultBundlePath", str(result_path), "-only-testing:KanpanUITests/AICoinBaseUITests"]
    command += ["-only-testing:KanpanUITests/ChartFoundationUITests/testHeightAndVerticalReachability",
                "-only-testing:KanpanUITests/ChartFoundationUITests/testResizeDividerWithinOneScreen",
                "-only-testing:KanpanUITests/ChartFoundationUITests/testFourSubpanelsFitWithoutPageScroll",
                "-only-testing:KanpanUITests/ChartFoundationUITests/testCrosshairCenterDragAndOutsidePan",
                "-only-testing:KanpanUITests/ChartFoundationUITests/testDragIndicatorTitleReordersCompletePane",
                "-only-testing:KanpanUITests/MainScreenUITests/testSearchButtonOpensSymbolPage",
                "-only-testing:KanpanUITests/MainScreenUITests/testLatestButtonAppearsAfterLeavingLatest",
                "-only-testing:KanpanUITests/MainScreenUITests/testIndicatorPanelOpensAndCloses",
                "-only-testing:KanpanUITests/MainScreenUITests/testSettingsPanelOpensAndCloses"]
    command += ["-only-testing:KanpanUITests/ChartFoundationUITests/testFavoritesCategoriesAndNavigation",
                "-only-testing:KanpanUITests/ChartFoundationUITests/testFavoritesDirectRowReorder",
                "-only-testing:KanpanUITests/ChartFoundationUITests/testFavoritesRightSwipeRemove",
                "-only-testing:KanpanUITests/ChartFoundationUITests/testFavoritesSearchSingleTap",
                "-only-testing:KanpanUITests/ChartFoundationUITests/testLatestEdgeAndReentryCompatibility"]
    start = time.time()
    with (ROOT / (slug + ".log")).open("w") as log:
        rc = subprocess.call(command, cwd=PROJECT, stdout=log, stderr=subprocess.STDOUT)
    summary = {"name": name, "exitCode": rc, "seconds": round(time.time() - start)}
    if result_path.exists():
        result = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result_path)], capture_output=True, text=True)
        if result.returncode == 0:
            detail = json.loads(result.stdout)
            (ROOT / (slug + "-summary.json")).write_text(result.stdout)
            summary.update({key: detail.get(key) for key in ["result", "passedTests", "failedTests", "skippedTests"]})
    if summary.get("passedTests") != 16 or summary.get("failedTests") != 0 or summary.get("skippedTests") != 0:
        rc = rc or 1
        summary["exitCode"] = rc
        summary["expectedTests"] = 16
    with lock:
        with (ROOT / "release-v2-runs.jsonl").open("a") as out: out.write(json.dumps(summary, ensure_ascii=False) + "\n")
    print("DONE", summary, flush=True)
    subprocess.run(["xcrun", "simctl", "shutdown", device["udid"]], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if rc: stop.set()

with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    list(pool.map(run, order))

# Propagate a failed matrix to callers; per-device JSON remains the evidence.
raise SystemExit(1 if stop.is_set() else 0)
