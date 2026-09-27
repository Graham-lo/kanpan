#!/usr/bin/env python3
"""kanpan-api 线上有界负载压测（2026-09-28）。在主 VPS 本机跑，打 127.0.0.1:8794。

只用标准库。规模：ACCOUNTS 个新注册的 test_stress_ 账号 × 两台设备（phone + tablet），
WORKERS 个线程循环打同步 / 提醒 / 复盘接口，每次请求之间随机停 THINK_MS，跑 DURATION 秒。
注册 / 登录只在开头做（Argon2 不是压测对象）；收尾（含中途护栏触发、Ctrl-C）一律注销全部测试账号。

护栏：5xx 比例超过 2%（至少 50 个请求后）、kanpan-api RSS 超过 700 MB、1 分钟负载超过 14 时立刻停。

用法：python3 load.py [--duration 300] [--workers 50] [--accounts 10] [--out result.json]
      python3 load.py --retired        # 只做退役字段验证
"""
import argparse, http.client, json, os, random, secrets, subprocess, sys, threading, time, uuid

HOST, PORT = "127.0.0.1", 8794
PASSWORD = "Stress0928pass"
lock = threading.Lock()
stop = threading.Event()


def now_ms():
    return int(time.time() * 1000)


class Client:
    """一个线程一条长连接。"""
    def __init__(self):
        self.c = None

    def req(self, method, path, token=None, body=None, headers=None):
        h = {"content-type": "application/json"}
        if token:
            h["authorization"] = "Bearer " + token
        if headers:
            h.update(headers)
        data = None if body is None else (body if isinstance(body, (bytes, str)) else json.dumps(body))
        for attempt in (0, 1):
            try:
                if self.c is None:
                    self.c = http.client.HTTPConnection(HOST, PORT, timeout=40)
                t = time.perf_counter()
                self.c.request(method, path, body=data, headers=h)
                r = self.c.getresponse()
                raw = r.read()
                ms = (time.perf_counter() - t) * 1000
                try:
                    v = json.loads(raw) if raw else None
                except ValueError:
                    v = {"nonJSON": raw[:200].decode("utf-8", "replace")}
                if r.getheader("connection", "").lower() == "close":
                    self.c.close(); self.c = None
                return r.status, v, ms
            except (http.client.HTTPException, ConnectionError, OSError) as e:
                if self.c:
                    self.c.close()
                self.c = None
                if attempt == 1:
                    return 0, {"transport": repr(e)}, 0.0


def device(kind):
    return {"id": str(uuid.uuid4()), "name": f"stress {kind}", "secret": secrets.token_hex(24), "kind": kind}


# --------------------------------------------------------------------------- 统计
class Stats:
    def __init__(self):
        self.lat = {}      # endpoint -> [ms]
        self.codes = {}    # endpoint -> {status/code: n}
        self.samples = []

    def add(self, ep, status, v, ms):
        code = str(status)
        if status >= 400 and isinstance(v, dict):
            err = v.get("error")
            if isinstance(err, dict):
                err = err.get("code")
            if err:
                code += ":" + str(err)
        if status == 0:
            code = "transport"
        with lock:
            self.lat.setdefault(ep, []).append(ms)
            d = self.codes.setdefault(ep, {})
            d[code] = d.get(code, 0) + 1

    def totals(self):
        with lock:
            n = sum(sum(d.values()) for d in self.codes.values())
            bad = sum(c for d in self.codes.values() for k, c in d.items() if k.startswith("5") or k == "transport")
        return n, bad


def pct(v, p):
    if not v:
        return None
    v = sorted(v)
    return round(v[min(len(v) - 1, int(round((len(v) - 1) * p)))], 1)


# --------------------------------------------------------------------------- VPS 采样
def sh(cmd):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=20).stdout.strip()
    except Exception as e:  # noqa
        return f"ERR {e}"


PSQL = ("set -a; . /etc/kanpan-api/database.env; set +a; docker exec kanpan-postgres psql -U \"$POSTGRES_USER\" -d kanpan -Atc "
        "\"select coalesce(state,'-'),count(*) from pg_stat_activity where datname='kanpan' group by 1 order by 1\"")


def api_rss_mb():
    pid = sh("systemctl show -p MainPID --value kanpan-api")
    for line in open(f"/proc/{pid}/status"):
        if line.startswith("VmRSS"):
            return int(line.split()[1]) // 1024
    return -1


def sample(tag):
    s = {"t": round(time.time(), 1), "tag": tag, "apiRssMB": api_rss_mb(),
         "workerRssMB": int(sh("grep VmRSS /proc/$(systemctl show -p MainPID --value kanpan-worker)/status | awk '{print $2}'") or 0) // 1024,
         "load1": float(open("/proc/loadavg").read().split()[0]),
         "memAvailMB": int(sh("free -m | awk '/Mem:/{print $7}'") or 0),
         "pg": sh(PSQL).replace("\n", " "),
         "active": sh("systemctl is-active kanpan-api kanpan-worker kanpan-gateway kanpan-stream-hub caddy").replace("\n", " ")}
    return s


def sampler(stats, every):
    while not stop.wait(every):
        s = sample("load")
        stats.samples.append(s)
        n, bad = stats.totals()
        print(f"[sample] {time.strftime('%H:%M:%S')} req={n} 5xx={bad} rss={s['apiRssMB']}MB load={s['load1']} pg={s['pg']} active={s['active']}", flush=True)
        if s["apiRssMB"] > 700 or s["load1"] > 14:
            print("[guard] RSS/负载越线，停止", flush=True); stop.set()
        if n >= 50 and bad / n > 0.02:
            print("[guard] 5xx 超过 2%，停止", flush=True); stop.set()


# --------------------------------------------------------------------------- 账号
class Dev:
    def __init__(self, user, kind, dev, token):
        self.user, self.kind, self.dev, self.token = user, kind, dev, token
        self.cursor = 0
        self.records = []
        self.logical = 0


def register_accounts(n, tag):
    c = Client(); devs = []; users = []
    for i in range(n):
        user = f"{tag}{i:02d}"
        ph = device("phone")
        st, v, ms = c.req("POST", "/v1/auth/register", body={"username": user, "password": PASSWORD, "device": ph})
        if st != 201:
            print("register failed", user, st, v); continue
        users.append((user, v["data"]["accessToken"]))
        devs.append(Dev(user, "phone", ph, v["data"]["accessToken"]))
        tb = device("tablet")
        st, v, ms = c.req("POST", "/v1/auth/login", body={"username": user, "password": PASSWORD, "device": tb})
        if st != 200:
            print("login failed", user, st, v); continue
        devs.append(Dev(user, "tablet", tb, v["data"]["accessToken"]))
    return users, devs


def delete_accounts(users):
    c = Client(); out = []
    for user, token in users:
        # 令牌 15 分钟过期；过期了就先登录一次再注销。
        st, v, _ = c.req("DELETE", "/v1/auth/account", token=token, body={"password": PASSWORD})
        if st == 401:
            s2, v2, _ = c.req("POST", "/v1/auth/login", body={"username": user, "password": PASSWORD, "device": device("desktop")})
            if s2 == 200:
                st, v, _ = c.req("DELETE", "/v1/auth/account", token=v2["data"]["accessToken"], body={"password": PASSWORD})
        out.append((user, st))
    return out


# --------------------------------------------------------------------------- 操作
THEMES = ["light", "dark", "auto"]; SKINS = ["sage", "terra", "classic"]; IVS = ["1m", "5m", "15m", "1h", "4h", "1d"]
SYMS = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "BNBUSDT", "XRPUSDT", "DOGEUSDT"]


def op(d, collection, object_id, fields, action="patch"):
    d.logical += 1
    return {"id": str(uuid.uuid4()), "collection": collection, "objectId": object_id, "deviceId": d.dev["id"],
            "baseRevision": 0, "generation": 0, "timestamp": now_ms(), "logical": d.logical, "action": action, "fields": fields}


def random_op(d, rng):
    k = rng.random()
    if k < 0.35:
        return op(d, "settings", "chart", {"theme": rng.choice(THEMES), "skin": rng.choice(SKINS),
                                            "barSpacing": float(rng.randint(2, 40)), "depth": rng.random() < 0.5, "interval": rng.choice(IVS)})
    if k < 0.75:
        n = rng.randrange(12)
        return op(d, "drawings", f"binance/usd_m/BTCUSDT/stress-{n}",
                  {"kind": "hline", "symbol": "BTCUSDT", "market": "usd_m", "venue": "binance",
                   "anchors": [{"t": now_ms() // 60000 * 60000, "p": 84000.0 + rng.randint(-2000, 2000)}],
                   "color": {"value": "#%06x" % rng.randrange(0xffffff)}, "lineWidth": float(rng.randint(1, 4)), "text": f"t{rng.randrange(10**6)}"})
    if k < 0.80:
        n = rng.randrange(12)  # 删除只落在一部分线上；删了之后的补丁是空操作
        return op(d, "drawings", f"binance/usd_m/BTCUSDT/stress-{n}", {}, action="delete") if n >= 9 else random_op(d, rng)
    s = rng.choice(SYMS)
    return op(d, "favorites", f"binance/usd_m/{s}", {"symbol": s, "market": "usd_m", "venue": "binance", "order": float(rng.randrange(100))})


def draft(sym="BTCUSDT"):
    now = now_ms(); size = 60_000; end = now // size * size
    return {"id": str(uuid.uuid4()), "range": {"venue": "binance", "market": "usd_m", "symbol": sym, "interval": "1m", "start": end - 3 * size, "end": end, "bars": 3},
            "rule": {"version": "criteria-v2", "direction": "long", "confirmation": "bar_close", "reference": 84600.0, "target": 86000.0,
                     "invalidation": 83000.0, "expires": now + 3_600_000},
            "text": "stress", "origin": "chart_first", "created": now}


WEIGHTS = [("sync.push", 28), ("sync.push.resend", 4), ("sync.changes", 18), ("sync.bootstrap", 14),
           ("alerts.listing-notices", 10), ("review.records", 10), ("review.detail", 8), ("review.statistics", 8)]


def worker(idx, dev, stats, seed, think):
    rng = random.Random(seed); c = Client(); last_batch = None
    names = [w[0] for w in WEIGHTS]; weights = [w[1] for w in WEIGHTS]
    while not stop.is_set():
        ep = rng.choices(names, weights)[0]
        if ep == "sync.push.resend" and last_batch is None:
            ep = "sync.push"
        if ep == "sync.push":
            n = rng.choice([1, 1, 2, 3, 5, 20])
            batch = {"operations": [random_op(dev, rng) for _ in range(n)]}
            st, v, ms = c.req("POST", "/v1/sync/operations", dev.token, batch)
            if st == 200:
                last_batch = (batch, v)
                dev.cursor = max(dev.cursor, max(r["cursor"] for r in v["data"]["results"]))
        elif ep == "sync.push.resend":
            batch, first = last_batch
            st, v, ms = c.req("POST", "/v1/sync/operations", dev.token, batch)
            if st == 200 and [r["operationId"] for r in v["data"]["results"]] != [r["operationId"] for r in first["data"]["results"]]:
                st = 598  # 幂等回执对不上：当成服务端错误记账（不是 HTTP 真实状态）
                v = {"error": "idempotency_result_changed"}
        elif ep == "sync.changes":
            q = f"/v1/sync/changes?cursor={dev.cursor}" + ("&collection=drawings" if rng.random() < 0.5 else "")
            st, v, ms = c.req("GET", q, dev.token)
            if st == 200:
                dev.cursor = v["data"]["cursor"]
        elif ep == "sync.bootstrap":
            q = "/v1/sync/bootstrap" + rng.choice(["", "?collection=drawings", "?collection=favorites"])
            st, v, ms = c.req("GET", q, dev.token)
        elif ep == "alerts.listing-notices":
            st, v, ms = c.req("GET", "/v1/alerts/listing-notices", dev.token)
        elif ep == "review.records":
            st, v, ms = c.req("GET", "/v1/native-review/records", dev.token)
            if st == 200:
                dev.records = [r["draft"]["id"] for r in v["data"]["records"]]
        elif ep == "review.detail":
            if not dev.records:
                continue
            st, v, ms = c.req("GET", f"/v1/native-review/records/{rng.choice(dev.records)}", dev.token)
        else:
            st, v, ms = c.req("GET", "/v1/native-review/statistics", dev.token)
        stats.add(ep, st, v, ms)
        if st >= 500 or st == 0:
            print(f"[5xx] {ep} {st} {json.dumps(v)[:300]}", flush=True)
        time.sleep(rng.uniform(*think) / 1000)


def run_load(a):
    stats = Stats(); tag = "test_stress_0928_" + secrets.token_hex(2) + "_"
    stats.samples.append(sample("before"))
    t0 = time.time()
    users, devs = register_accounts(a.accounts, tag)
    print(f"[setup] {len(users)} accounts / {len(devs)} devices in {time.time() - t0:.1f}s, prefix {tag}", flush=True)
    result = {"prefix": tag, "config": vars(a), "weights": WEIGHTS}
    try:
        c = Client()
        # 每个账号先铺一点真实数据：设置、12 条画线、6 只自选、2 条复盘。
        for d in devs[::2]:
            ops = [op(d, "settings", "chart", {"theme": "light", "skin": "sage", "interval": "1h", "barSpacing": 8.0})]
            ops += [random_op(d, random.Random(i)) for i in range(20)]
            st, v, _ = c.req("POST", "/v1/sync/operations", d.token, {"operations": ops}); stats.add("setup.push", st, v, 0)
            for _ in range(2):
                st, v, _ = c.req("POST", "/v1/native-review/records", d.token, draft(), {"idempotency-key": str(uuid.uuid4())})
                stats.add("setup.review.create", st, v, 0)
                if st != 200:
                    print("review create", st, v, flush=True)
        for d in devs:
            st, v, _ = c.req("GET", "/v1/native-review/records", d.token)
            if st == 200:
                d.records = [r["draft"]["id"] for r in v["data"]["records"]]
        smp = threading.Thread(target=sampler, args=(stats, a.sample), daemon=True); smp.start()
        threads = [threading.Thread(target=worker, args=(i, devs[i % len(devs)], stats, 1000 + i, (a.think_lo, a.think_hi)), daemon=True) for i in range(a.workers)]
        started = time.time(); print(f"[load] start {time.strftime('%H:%M:%S')} workers={a.workers}", flush=True)
        for t in threads:
            t.start()
        stop.wait(a.duration); stop.set()
        for t in threads:
            t.join(60)
        elapsed = time.time() - started
        result["elapsed"] = round(elapsed, 1)
        print(f"[load] end {time.strftime('%H:%M:%S')} elapsed {elapsed:.1f}s", flush=True)
    finally:
        stop.set()
        result["deleted"] = delete_accounts(users)
        print("[cleanup]", result["deleted"], flush=True)
    time.sleep(5)
    stats.samples.append(sample("after+5s"))
    table = {}
    for ep in sorted(stats.codes):
        lat = stats.lat[ep]; codes = stats.codes[ep]; n = sum(codes.values())
        table[ep] = {"n": n, "rps": round(n / result.get("elapsed", 1), 2), "codes": codes,
                     "p50": pct(lat, .5), "p95": pct(lat, .95), "p99": pct(lat, .99), "max": pct(lat, 1)}
    result["endpoints"] = table; result["samples"] = stats.samples
    json.dump(result, open(a.out, "w"), ensure_ascii=False, indent=1)
    for ep, r in table.items():
        print(f"{ep:26s} n={r['n']:6d} rps={r['rps']:6.2f} p50={r['p50']} p95={r['p95']} p99={r['p99']} max={r['max']} {r['codes']}")


# --------------------------------------------------------------------------- 退役字段
def run_retired(a):
    c = Client(); user = "test_retired_0928_" + secrets.token_hex(2); out = {"user": user}
    ph = device("phone")
    st, v, _ = c.req("POST", "/v1/auth/register", body={"username": user, "password": PASSWORD, "device": ph})
    assert st == 201, (st, v)
    token = v["data"]["accessToken"]
    try:
        d = Dev(user, "phone", ph, token)
        o = op(d, "settings", "chart", {"interval": "4h", "skin": "terra", "replaySpeed": 2, "timeZone": "Asia/Shanghai", "favoritesSort": "change"})
        st, v, _ = c.req("POST", "/v1/sync/operations", token, {"operations": [o]})
        out["push"] = {"status": st, "body": v}
        assert st == 200, (st, v)
        r = v["data"]["results"][0]
        assert r["operationId"] == o["id"], r
        dropped = r["droppedFields"]; out["droppedFields"] = dropped
        assert sorted(dropped) == ["favoritesSort", "replaySpeed", "timeZone"], dropped
        body = r["object"]["body"]
        assert body.get("interval") == "4h" and body.get("skin") == "terra", body
        assert not {"replaySpeed", "timeZone", "favoritesSort"} & (set(body) | set(r["object"]["fields"])), r["object"]
        # 同一 op 原样重发：回执原样返回，droppedFields 仍在
        st, v2, _ = c.req("POST", "/v1/sync/operations", token, {"operations": [o]})
        assert st == 200 and v2["data"]["results"][0] == r, (st, v2)
        out["resendIdentical"] = True
        st, v, _ = c.req("GET", "/v1/sync/bootstrap", token)
        assert st == 200, (st, v)
        objs = [x for x in v["data"]["objects"] if x["collection"] == "settings" and x["id"] == "chart"]
        assert len(objs) == 1, v
        b = objs[0]["body"]; out["bootstrapBody"] = b; out["bootstrapFieldKeys"] = sorted(objs[0]["fields"])
        assert b.get("interval") == "4h" and b.get("skin") == "terra", b
        assert not {"replaySpeed", "timeZone", "favoritesSort"} & (set(b) | set(objs[0]["fields"])), objs[0]
        out["ok"] = True
    finally:
        st, v, _ = c.req("DELETE", "/v1/auth/account", token=token, body={"password": PASSWORD})
        out["deleted"] = st
    print(json.dumps(out, ensure_ascii=False, indent=1))
    json.dump(out, open(a.out, "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--duration", type=int, default=300); p.add_argument("--workers", type=int, default=50)
    p.add_argument("--accounts", type=int, default=10); p.add_argument("--sample", type=int, default=15)
    p.add_argument("--think-lo", type=int, default=100); p.add_argument("--think-hi", type=int, default=300)
    p.add_argument("--out", default="result.json"); p.add_argument("--retired", action="store_true")
    a = p.parse_args()
    run_retired(a) if a.retired else run_load(a)
