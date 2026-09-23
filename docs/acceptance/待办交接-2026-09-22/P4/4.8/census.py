#!/usr/bin/env python3
"""P4.8 协议普查（动态项 1 与 3）：照 Backend/kanpan-api/src/market_meta.rs 的合表与查表规则，
用同一时刻抓下来的上游原文，逐合约算出供应量来自哪一族、CoinGecko 那一族的身份对不对。

输入（同一目录，抓取时刻见 fetched_at_supply.txt）：
  apex.json products.json cg1..cg4.json prices.json exchangeInfo2.json
输出：census-coins.csv、census-summary.json、precision.json（动态项 3）
"""
import csv, hashlib, json, math, os, re, sys

D = os.path.dirname(os.path.abspath(__file__))
QUOTES = ["FDUSD", "BUSD", "TUSD", "USDT", "USDC", "USDD", "USD"]


def load(name):
    with open(os.path.join(D, name)) as f:
        return json.load(f)


def rows(body):
    for c in [body, (body or {}).get("data") if isinstance(body, dict) else None]:
        if isinstance(c, list) and c:
            return c
    if isinstance(body, dict):
        d = body.get("data")
        if isinstance(d, dict):
            for k in ("list", "rows"):
                if isinstance(d.get(k), list) and d[k]:
                    return d[k]
        if isinstance(body.get("result"), list):
            return body["result"]
    return []


def num(v):
    try:
        x = float(v)
    except (TypeError, ValueError):
        return None
    return x if math.isfinite(x) else None


def pos(v):
    x = num(v)
    return x if x is not None and x > 0 else None


def rank(v):
    try:
        r = int(v)
    except (TypeError, ValueError):
        return None
    return r if r > 0 else None


def plain(symbol):
    clean = "".join(ch for ch in symbol.upper() if ch.isascii() and ch.isalnum())
    for suf in ("SWAP", "PERP"):
        if clean.endswith(suf) and clean[: -len(suf)]:
            clean = clean[: -len(suf)]
    return clean


def strip_multiplier(base):
    digits = len(base) - len(base.lstrip("0123456789"))
    if digits >= 4 and base.startswith("1") and set(base[1:digits]) <= {"0"}:
        rest = base[digits:]
        if len(rest) >= 2 and rest[0].isalpha():
            return rest, float(base[:digits])
    for prefix, m in (("1M", 1e6), ("1K", 1e3)):
        if base.startswith(prefix):
            rest = base[len(prefix):]
            if len(rest) >= 3 and rest[0].isalpha():
                return rest, m
    return base, 1.0


def readings(symbol):
    clean = plain(symbol)
    names = [clean]
    for q in QUOTES:
        if clean.endswith(q) and clean[: -len(q)] and clean[: -len(q)] not in names:
            names.append(clean[: -len(q)])
    return names


def empty(m):
    return all(m.get(k) is None for k in ("total", "circ", "max", "rank"))


def by_identity(assets, family):
    per_id = {}
    for a in assets:
        if not a["id"] or not a["ticker"]:
            continue
        slot = per_id.setdefault(a["id"], (a["ticker"], {"family": family, "total": None, "circ": None, "max": None, "rank": None, "id": a["id"], "price": None}))
        m = slot[1]
        for k in ("total", "circ", "max", "rank", "price"):
            if m.get(k) is None:
                m[k] = a["meta"].get(k)
    owner, out, ambiguous = {}, {}, {}
    for id_, (ticker, meta) in per_id.items():
        if empty(meta):
            continue
        if ticker in owner and owner[ticker] != id_:
            out[ticker] = None
            ambiguous.setdefault(ticker, {owner[ticker]}).add(id_)
        elif ticker not in owner:
            owner[ticker] = id_
            out[ticker] = meta
    return out, ambiguous


def main():
    apex = []
    for r in rows(load("apex.json")):
        b = r.get("baseAsset")
        if not isinstance(b, str):
            continue
        b = b.upper()
        apex.append({"id": b, "ticker": b, "meta": {"total": pos(r.get("totalSupply")), "circ": pos(r.get("circulatingSupply")), "max": pos(r.get("maxSupply")), "rank": rank(r.get("rank"))}})
    prods = []
    for r in rows(load("products.json")):
        b = r.get("b")
        if not isinstance(b, str):
            continue
        b = b.upper()
        prods.append({"id": b, "ticker": b, "meta": {"circ": pos(r.get("cs"))}})
    cg = []
    for p in (1, 2, 3, 4):
        for r in rows(load(f"cg{p}.json")):
            if not isinstance(r.get("id"), str) or not isinstance(r.get("symbol"), str):
                continue
            cg.append({"id": r["id"].lower(), "ticker": r["symbol"].upper(), "meta": {"total": pos(r.get("total_supply")), "circ": pos(r.get("circulating_supply")), "max": pos(r.get("max_supply")), "rank": rank(r.get("market_cap_rank")), "price": pos(r.get("current_price")), "name": r.get("name")}})
    # 同一代号在 CoinGecko 里的全部候选（含被判歧义的）：用来找「价格对得上的那一个」。
    cg_by_ticker = {}
    for a in cg:
        cg_by_ticker.setdefault(a["ticker"], []).append(a)

    cg_table, cg_amb = by_identity(cg, "coingecko")
    bn_table, bn_amb = by_identity(apex + prods, "binance")
    table = {t: m for t, m in cg_table.items() if m is not None}
    for t, m in bn_table.items():
        if m is None:
            table.pop(t, None)
        else:
            table[t] = m

    def lookup_fixed(symbol):
        rs = readings(symbol)
        for name in rs:
            orig = table.get(name)
            sname, mult = strip_multiplier(name)
            stripped = table.get(sname) if mult != 1.0 else None
            if orig and orig["family"] == "binance":
                return orig, name, 1.0, "binance-原名"
            if stripped and stripped["family"] == "binance":
                return stripped, sname, mult, "binance-去打包前缀"
        return lookup(symbol, weak_only=True)

    def lookup(symbol, weak_only=False):
        for name in readings(symbol):
            orig = table.get(name)
            sname, mult = strip_multiplier(name)
            stripped = table.get(sname) if mult != 1.0 else None
            if not weak_only and orig and orig["family"] == "binance":
                return orig, name, 1.0, "binance-原名"
            if not weak_only and stripped and stripped["family"] == "binance":
                return stripped, sname, mult, "binance-去打包前缀"
            if orig and stripped:
                return None, name, 1.0, "两边都只有弱证据-留空"
            if orig:
                return orig, name, 1.0, "coingecko-原名"
            if stripped:
                return stripped, sname, mult, "coingecko-去打包前缀"
        return None, None, 1.0, "查不到"

    prices = {r["symbol"]: num(r["price"]) for r in load("prices.json")}
    ex = load("exchangeInfo2.json")
    out = []
    counts = {}
    for r in ex["symbols"]:
        if r.get("underlyingType") != "COIN":
            continue
        if r.get("contractType") != "PERPETUAL" or r.get("status") != "TRADING":
            continue
        sym = r["symbol"]
        meta, ticker, mult, route = lookup(sym)
        counts[route] = counts.get(route, 0) + 1
        row = {"symbol": sym, "route": route, "ticker": ticker or "", "multiplier": mult, "binance_price": prices.get(sym)}
        if meta and meta["family"] == "coingecko":
            per_coin = row["binance_price"] / mult if row["binance_price"] else None
            cgp = meta.get("price")
            ratio = (per_coin / cgp) if (per_coin and cgp) else None
            supply = meta.get("circ") or meta.get("total")
            shown_cap = supply / mult * row["binance_price"] if (supply and row["binance_price"]) else None
            # 同代号里价格最接近币安那一个（只在 CoinGecko 前 1000 名里找得到）
            best = None
            for cand in cg_by_ticker.get(ticker, []):
                p = cand["meta"].get("price")
                if p and per_coin:
                    d = abs(math.log(per_coin / p))
                    if best is None or d < best[0]:
                        best = (d, cand)
            right = best[1] if best and best[0] < math.log(1.25) else None
            right_supply = (right["meta"].get("circ") or right["meta"].get("total")) if right else None
            right_cap = right_supply * per_coin if (right_supply and per_coin) else None
            row.update({
                "cg_id": meta["id"], "cg_price": cgp, "price_ratio": ratio,
                "identity": ("对" if ratio and abs(math.log(ratio)) < math.log(1.25) else ("错" if ratio else "无价可比")),
                "shown_cap_usd": shown_cap, "right_cg_id": right["id"] if right else "",
                "right_cap_usd": right_cap,
                "cap_error_x": (shown_cap / right_cap) if (shown_cap and right_cap) else None,
                "same_ticker_ids": "|".join(c["id"] for c in cg_by_ticker.get(ticker, [])),
            })
        m2, t2, mult2, route2 = lookup_fixed(sym)
        if m2 and m2["family"] == "coingecko":
            cgp2 = m2.get("price")
            bp = row["binance_price"]
            ok = bool(cgp2 and bp and 1 / 1.5 <= bp / (cgp2 * mult2) <= 1.5)
            route2 = route2 + ("-单价核对通过" if ok else "-单价对不上留空")
        row["route_after_fix"] = route2
        out.append(row)

    fields = ["symbol", "route", "route_after_fix", "ticker", "multiplier", "binance_price", "cg_id", "cg_price", "price_ratio", "identity", "shown_cap_usd", "right_cg_id", "right_cap_usd", "cap_error_x", "same_ticker_ids"]
    with open(os.path.join(D, "census-coins.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for row in out:
            w.writerow({k: row.get(k, "") for k in fields})
    cgrows = [r for r in out if r["route"].startswith("coingecko")]
    summary = {
        "inputs_sha256": {n: hashlib.sha256(open(os.path.join(D, n), "rb").read()).hexdigest() for n in ["apex.json", "products.json", "cg1.json", "cg2.json", "cg3.json", "cg4.json", "prices.json", "exchangeInfo2.json"]},
        "fetched_at": open(os.path.join(D, "fetched_at_supply.txt")).read().split(),
        "coin_perpetuals_trading": len(out),
        "routes": counts,
        "coingecko_rows": len(cgrows),
        "routes_after_fix": {k: sum(1 for r in out if r["route_after_fix"] == k) for k in sorted({r["route_after_fix"] for r in out})},
        "changed_by_fix": [(r["symbol"], r["route"], r["route_after_fix"]) for r in out if r["route"] != r["route_after_fix"].replace("-单价核对通过", "")],
        "coingecko_identity": {k: sum(1 for r in cgrows if r["identity"] == k) for k in ("对", "错", "无价可比")},
        "coingecko_wrong": [{k: r.get(k) for k in fields} for r in cgrows if r["identity"] != "对"],
        "binance_ambiguous_tickers": sorted(bn_amb),
        "coingecko_ambiguous_tickers_count": len(cg_amb),
    }
    cb_path = os.path.join(D, "coinbase-products.json")
    if os.path.exists(cb_path):
        cb = [p for p in load("coinbase-products.json").get("products", []) if p.get("quote_currency_id") == "USD" and p.get("status") == "online" and not p.get("is_disabled")]
        cb_rows = []
        for p in cb:
            base = p["base_currency_id"].upper()
            m, t, mult, route = lookup_fixed(base)
            price = num(p.get("price"))
            ok = None
            if m and m["family"] == "coingecko":
                cgp = m.get("price")
                ok = bool(cgp and price and 1 / 1.5 <= price / (cgp * mult) <= 1.5)
            cb_rows.append({"pair": p["product_id"], "route": route, "price": price, "cg_id": m.get("id") if m else "", "cg_price": m.get("price") if m else None, "verified": ok})
        summary["coinbase_spot_usd_online"] = len(cb_rows)
        summary["coinbase_routes"] = {k: sum(1 for r in cb_rows if r["route"] == k) for k in sorted({r["route"] for r in cb_rows})}
        summary["coinbase_coingecko_unverified"] = [r for r in cb_rows if r["verified"] is False]
        summary["inputs_sha256"]["coinbase-products.json"] = hashlib.sha256(open(cb_path, "rb").read()).hexdigest()
    json.dump(summary, open(os.path.join(D, "census-summary.json"), "w"), ensure_ascii=False, indent=1)
    print(json.dumps({k: summary[k] for k in ("coin_perpetuals_trading", "routes", "coingecko_rows", "coingecko_identity", "fetched_at")}, ensure_ascii=False))
    for r in summary["coingecko_wrong"]:
        print(r["symbol"], r["cg_id"], r["identity"], r["price_ratio"], r["right_cg_id"], r["cap_error_x"])


if __name__ == "__main__":
    main()
