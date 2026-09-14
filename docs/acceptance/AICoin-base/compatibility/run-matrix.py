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
order = ["iPhone 15", "iPad mini (A17 Pro)", "iPhone 16 Pro", "iPad Pro 13-inch (M5)",
         "iPhone 16 Plus", "iPad (A16)", "iPhone 17", "iPad Air 11-inch (M4)",
         "iPhone 17 Pro Max", "iPad Pro 11-inch (M5)", "iPhone Air"]

def run(name):
    if stop.is_set(): return
    device = next(d for d in devices if d["name"] == name)
    slug = name.replace(" ", "-").replace("(", "").replace(")", "") + "-ipad-fix"
    result_path = ROOT / (slug + ".xcresult")
    if result_path.exists():
        print("EXISTS; preserve", name, flush=True)
        return
    print("START", name, flush=True)
    command = ["xcodebuild", "test-without-building", "-workspace", "Kanpan.xcworkspace",
               "-scheme", "Kanpan", "-destination", "platform=iOS Simulator,id=" + device["udid"],
               "-derivedDataPath", "DerivedData-codex-compat-final", "-parallel-testing-enabled", "NO",
               "-resultBundlePath", str(result_path), "-only-testing:KanpanUITests/AICoinBaseUITests"]
    if name in ["iPad mini (A17 Pro)", "iPad Pro 13-inch (M5)"]:
        command += ["-only-testing:KanpanUITests/MainScreenUITests"]
    else:
        command += ["-only-testing:KanpanUITests/MainScreenUITests/testIndicatorPanelOpensAndCloses",
                    "-only-testing:KanpanUITests/MainScreenUITests/testSettingsPanelOpensAndCloses"]
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
    with lock:
        with (ROOT / "ipad-fix-runs.jsonl").open("a") as out: out.write(json.dumps(summary, ensure_ascii=False) + "\n")
    print("DONE", summary, flush=True)
    subprocess.run(["xcrun", "simctl", "shutdown", device["udid"]], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if rc: stop.set()

with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    list(pool.map(run, order))
