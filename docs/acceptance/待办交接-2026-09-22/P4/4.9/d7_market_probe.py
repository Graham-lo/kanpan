#!/usr/bin/env python3
"""D.7 第一项：外部经 Caddy 到 8792 的历史 K 线，和交易所直取逐根比。

每一路记：来源、请求发出时刻（UTC）、耗时、HTTP 码、根数、首末根开盘时刻。
逐根比较的边界：两边都有、且 close_time < 两次请求里较早的那个发出时刻 的根（已收盘）必须
OHLCV 逐字段一致；最后一根未收盘的只比开盘时刻与开盘价，不比高低收量（它在两次请求之间会动）。
"""
import json, sys, time, urllib.request
from datetime import datetime, timezone

UA = "Mozilla/5.0 kanpan-d7-probe"
PUBLIC = "https://kanpan.107-174-172-10.sslip.io"

def fetch(url):
    t0 = time.time()
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            body = r.read(); code = r.status
    except urllib.error.HTTPError as e:
        body = e.read(); code = e.code
    return {"url": url, "sent_at": datetime.fromtimestamp(t0, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")[:-4] + "Z",
            "sent_ms": int(t0 * 1000), "ms": round((time.time() - t0) * 1000), "http": code, "body": body}

def gateway_rows(body):
    j = json.loads(body)
    rows = j.get("bars") or j.get("klines") or j
    return j, rows

def norm_binance(rows):
    return [(int(r[0]), float(r[1]), float(r[2]), float(r[3]), float(r[4]), float(r[5]), int(r[6])) for r in rows]

def norm_okx(rows, step):
    out = [(int(r[0]), float(r[1]), float(r[2]), float(r[3]), float(r[4]), float(r[6]) if len(r) > 6 else float(r[5]), int(r[0]) + step - 1) for r in rows]
    return sorted(out)

def compare(a, b, boundary_ms):
    ai = {r[0]: r for r in a}; bi = {r[0]: r for r in b}
    common = sorted(set(ai) & set(bi))
    closed = [t for t in common if ai[t][6] < boundary_ms]
    mism = [t for t in closed if any(abs(x - y) > 1e-9 * max(1, abs(x)) for x, y in zip(ai[t][1:6], bi[t][1:6]))]
    open_ = [t for t in common if t not in closed]
    open_mism = [t for t in open_ if abs(ai[t][1] - bi[t][1]) > 1e-9 * max(1, abs(ai[t][1]))]
    return {"common": len(common), "closed_compared": len(closed), "closed_mismatch": mism[:5], "closed_mismatch_n": len(mism),
            "open_bars": len(open_), "open_open_price_mismatch": len(open_mism),
            "first": common[0] if common else None, "last": common[-1] if common else None}

out = {"probe_started_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "runs": []}
for src, direct in [("binance", "https://fapi.binance.com/fapi/v1/klines?symbol=BTCUSDT&interval=1m&limit=100"),
                    ("okx", "https://www.okx.com/api/v5/market/candles?instId=BTC-USDT-SWAP&bar=1m&limit=100")]:
    g = fetch(f"{PUBLIC}/market/v1/klines?source={src}&symbol=BTCUSDT&interval=1m&limit=100")
    d = fetch(direct)
    run = {"source": src,
           "gateway": {k: g[k] for k in ("url", "sent_at", "ms", "http")},
           "direct": {k: d[k] for k in ("url", "sent_at", "ms", "http")}}
    try:
        gj, grow = gateway_rows(g["body"])
        run["gateway"]["envelope"] = {k: gj[k] for k in ("source", "symbol", "interval") if isinstance(gj, dict) and k in gj}
        gn = norm_binance(grow)
        if src == "binance":
            dn = norm_binance(json.loads(d["body"]))
        else:
            dn = norm_okx(json.loads(d["body"])["data"], 60000)
        run["gateway"]["bars"] = len(gn); run["direct"]["bars"] = len(dn)
        run["compare"] = compare(gn, dn, min(g["sent_ms"], d["sent_ms"]))
    except Exception as e:  # 记下来，不吞
        run["error"] = f"{type(e).__name__}: {e}"; run["gateway_head"] = g["body"][:300].decode("utf-8", "replace")
        run["direct_head"] = d["body"][:300].decode("utf-8", "replace")
    out["runs"].append(run)
h = fetch(f"{PUBLIC}/chart-gateway/health")
out["health"] = {k: h[k] for k in ("url", "sent_at", "ms", "http")}
out["health"]["body"] = h["body"][:400].decode("utf-8", "replace")
print(json.dumps(out, ensure_ascii=False, indent=1, default=str))
