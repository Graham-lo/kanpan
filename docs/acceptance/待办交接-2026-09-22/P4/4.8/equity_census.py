#!/usr/bin/env python3
"""P4.8 动态第二项：LISTINGS 点名表之外、按 stocks/<base> 直拼地址的每一个美股合约，
页面身份到底对不对。

同一轮里先抓币安 exchangeInfo 与合约现价，再逐个抓 stockanalysis 页面（间隔 300ms，
和线上 LISTING_GAP 同量级），全部原文落盘并记 sha256，供事后追溯。

判据（两条独立证据）：
  code_ok  : 线上 page_is() 的同一套规则——页面自报的代码规范化后等于 base；
  price_ok : 页面上的现价与币安合约现价之比落在 0.9–1.1（美股永续按美元每股报价，
             身份对的话两边价格只差盘前盘后与资金费基差）。
代码对、价格也对 → 身份正确；代码对、价格对不上 → 需要人工看（可能是 ADR 折股或认错公司）。
"""
import hashlib, json, os, re, sys, time, urllib.request
from datetime import datetime, timezone

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/kanpan-equity-census"
os.makedirs(os.path.join(OUT, "pages"), exist_ok=True)
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
LISTED = {"HK0700","TENCENT","HK1810","HK0625","HK0992","MEITUAN","KUAISHOU","POPMART","BYD","MINIMAX",
          "GIGADEV","ZHONGJI","ZHIPU","SKHYNIX","SAMSUNG","HYUNDAI","SAMSUNGEM","HANMI","LGELECTRONICS",
          "NAVER","CXMT","UNITREE","BRKB","QNTX"}

def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.status, r.read()

def norm(t):
    return "".join(c for c in t.upper() if c.isascii() and c.isalnum())

def identities(body):
    keys = ["symbol","db_symbol","nameFull","name","titleName","ticker","exchange_symbol"]
    out = []
    for node in body.get("nodes") or []:
        data = (node or {}).get("data")
        if not isinstance(data, list):
            continue
        for cell in data:
            if not isinstance(cell, dict):
                continue
            for k in keys:
                v = cell.get(k)
                if isinstance(v, int) and not isinstance(v, bool) and 0 <= v < len(data):
                    v = data[v]
                if isinstance(v, str):
                    c = norm(v)
                    if c and c not in out:
                        out.append(c)
    return out

def field(body, key):
    for node in body.get("nodes") or []:
        data = (node or {}).get("data")
        if not isinstance(data, list):
            continue
        for cell in data:
            if isinstance(cell, dict) and key in cell:
                v = cell[key]
                if isinstance(v, int) and not isinstance(v, bool) and 0 <= v < len(data):
                    v = data[v]
                if v is not None and not isinstance(v, (dict, list)):
                    return v
    return None

meta = {"started_at": now(), "inputs_sha256": {}}
_, ei = get("https://www.binance.com/fapi/v1/exchangeInfo")
_, px = get("https://www.binance.com/fapi/v1/ticker/price")
meta["binance_fetched_at"] = now()
open(os.path.join(OUT, "exchangeInfo.json"), "wb").write(ei)
open(os.path.join(OUT, "prices.json"), "wb").write(px)
meta["inputs_sha256"]["exchangeInfo.json"] = hashlib.sha256(ei).hexdigest()
meta["inputs_sha256"]["prices.json"] = hashlib.sha256(px).hexdigest()
prices = {r["symbol"]: float(r["price"]) for r in json.loads(px)}
rows = json.loads(ei)["symbols"]

equity = [r for r in rows if r.get("underlyingType") == "EQUITY"]
meta["equity_rows"] = len(equity)
meta["equity_trading"] = sum(1 for r in equity if r.get("status") == "TRADING")
targets, listed_rows, not_plain = [], [], []
for r in equity:
    base = (r.get("baseAsset") or "").upper()
    if base in LISTED:
        listed_rows.append(r["symbol"]); continue
    if not base or not base.isalnum():
        not_plain.append(r["symbol"]); continue
    targets.append((r["symbol"], base, r.get("status")))
meta["listed_equity_rows"] = listed_rows
meta["not_plain_ticker"] = not_plain

pages_sha = {}
results = []
seen = {}
for symbol, base, status in targets:
    if base in seen:
        res = dict(seen[base]); res["symbol"] = symbol; res["status"] = status
        res["binance_price"] = prices.get(symbol)
        results.append(res); continue
    url = f"https://stockanalysis.com/stocks/{base}/__data.json"
    res = {"symbol": symbol, "base": base, "status": status, "binance_price": prices.get(symbol), "url": url}
    body = None
    for attempt in range(2):
        try:
            code, raw = get(url)
            res["http"] = code
            body = json.loads(raw)
            fn = os.path.join(OUT, "pages", base + ".json")
            open(fn, "wb").write(raw)
            pages_sha[base] = hashlib.sha256(raw).hexdigest()
            break
        except Exception as e:
            res["http"] = getattr(e, "code", None) or type(e).__name__
            time.sleep(0.3)
    res["fetched_at"] = now()
    if body is None:
        res["verdict"] = "页面没取到"
    else:
        ids = identities(body)
        res["page_ids"] = ids[:6]
        res["name"] = field(body, "nameFull") or field(body, "name")
        res["code_ok"] = norm(base) in ids
        p = field(body, "p")
        try:
            res["page_price"] = float(p) if p is not None else None
        except (TypeError, ValueError):
            res["page_price"] = None
        res["has_marketcap"] = field(body, "marketCap") is not None
        bp = res["binance_price"]
        if res["page_price"] and bp:
            res["ratio"] = bp / res["page_price"]
            res["price_ok"] = 0.9 <= res["ratio"] <= 1.1
        else:
            res["ratio"] = None; res["price_ok"] = None
        if not ids:
            res["verdict"] = "页面无身份字段（线上按不通过留空）"
        elif not res["code_ok"]:
            res["verdict"] = "代码对不上（线上留空）"
        elif res["price_ok"] is True:
            res["verdict"] = "身份正确"
        elif res["price_ok"] is False:
            res["verdict"] = "代码对但价格对不上"
        else:
            res["verdict"] = "代码对、无价可比"
    seen[base] = res
    results.append(res)
    time.sleep(0.3)

meta["finished_at"] = now()
meta["pages_sha256"] = pages_sha
meta["targets"] = len(targets)
from collections import Counter
meta["verdicts"] = Counter(r["verdict"] for r in results)
json.dump(meta, open(os.path.join(OUT, "equity-summary.json"), "w"), ensure_ascii=False, indent=1)
json.dump(results, open(os.path.join(OUT, "equity-results.json"), "w"), ensure_ascii=False, indent=1)
print(json.dumps({k: meta[k] for k in ("started_at","finished_at","equity_rows","equity_trading","targets","verdicts")}, ensure_ascii=False))
