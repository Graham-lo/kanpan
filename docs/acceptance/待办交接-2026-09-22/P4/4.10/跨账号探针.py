# P4.10 线上接口层跨账号隔离探针：两个一次性账号，B 拿 A 的 id 来问，应一律 404/看不到。结束删号。
import json, secrets, time, uuid, urllib.request, urllib.error
BASE = "https://kanpan.107-174-172-10.sslip.io"
def req(path, method="GET", token=None, body=None, key=None):
    data = None if body is None else json.dumps(body).encode()
    r = urllib.request.Request(BASE + path, data=data, method=method)
    r.add_header("content-type", "application/json")
    if token: r.add_header("authorization", "Bearer " + token)
    if key: r.add_header("idempotency-key", str(key))
    try:
        with urllib.request.urlopen(r, timeout=20) as resp: return resp.status, json.loads(resp.read() or b"null")
    except urllib.error.HTTPError as e:
        txt = e.read()
        try: return e.code, json.loads(txt)
        except Exception: return e.code, {"raw": txt[:200].decode(errors="replace")}
def signup(tag):
    dev = {"id": str(uuid.uuid4()), "name": "p410 probe", "secret": secrets.token_urlsafe(32)}
    pw = "P" + secrets.token_hex(10)
    name = f"p410{tag}{secrets.token_hex(4)}"
    s, v = req("/v1/auth/register", "POST", body={"username": name, "password": pw, "device": dev})
    assert s == 201, (s, v)
    return {"name": name, "pw": pw, "dev": dev, "token": v["data"]["accessToken"], "id": v["data"]["user"]["id"]}
out = []
def check(label, got, want):
    ok = got == want; out.append(f"{'通过' if ok else '不符'}  {label}: 期望 {want}，实得 {got}"); return ok
a = signup("a"); b = signup("b")
out.append(f"账号 A={a['name']} B={b['name']}（一次性，结束删号；密码只在内存里）")
try:
    now = int(time.time() * 1000); size = 60000; end = now // size * size
    rid = str(uuid.uuid4())
    draft = {"id": rid, "range": {"venue": "binance", "market": "usd_m", "symbol": "BTCUSDT", "interval": "1m", "start": end - 3 * size, "end": end, "bars": 3},
             "rule": {"version": "criteria-v2", "direction": "long", "confirmation": "bar_close", "reference": 100.0, "target": 110.0, "invalidation": 90.0, "expires": now + 3600000},
             "text": "", "origin": "chart_first", "created": now}
    s, v = req("/v1/native-review/records", "POST", a["token"], draft, uuid.uuid4()); check("A 建复盘记录", s, 200)
    s, _ = req(f"/v1/native-review/records/{rid}", token=a["token"]); check("A 读自己的记录", s, 200)
    for p in [f"/v1/native-review/records/{rid}", f"/v1/native-review/records/{rid}/revisions", f"/v1/native-review/records/{rid}/attachments", f"/v1/native-review/records/{rid}/shot"]:
        s, _ = req(p, token=b["token"]); check(f"B 读 A 的 {p.split(rid)[1] or '详情'}", s, 404)
    s, _ = req(f"/v1/native-review/records/{rid}/void", "POST", b["token"], {"expectedRevision": 0}, uuid.uuid4()); check("B 作废 A 的记录", s, 404)
    s, v = req("/v1/native-review/records", token=b["token"]); items = (v.get("data") or {}).get("items", [])
    check("B 的列表里有没有 A 的记录", any(i.get("id") == rid for i in items), False)
    s, _ = req(f"/v1/native-review/records/{rid}", token=None); check("不带令牌读详情", s, 401)
    op = {"id": str(uuid.uuid4()), "collection": "drawings", "objectId": "binance/usd_m/BTCUSDT/p410", "deviceId": a["dev"]["id"], "baseRevision": 0, "generation": 0,
          "timestamp": int(time.time() * 1000), "logical": 0, "action": "patch", "importBatch": None,
          "fields": {"color": {"value": "#FF9900"}, "kind": "hline", "anchors": [{"t": 1.7e12, "p": 100.0}], "symbol": "BTCUSDT", "market": "usd_m", "venue": "binance"}}
    s, v = req("/v1/sync/operations", "POST", a["token"], {"operations": [op]}); check("A 推一条画线", s, 200)
    s, v = req("/v1/sync/bootstrap?collection=drawings", token=a["token"]); check("A 拉回自己的画线条数", len(v["data"]["objects"]), 1)
    s, v = req("/v1/sync/bootstrap?collection=drawings", token=b["token"]); check("B 拉画线条数（不该看到 A 的）", len(v["data"]["objects"]), 0)
    s, _ = req("/v1/sync/operations", "POST", b["token"], {"operations": [op]}); check("B 冒用 A 的设备推同一条", s, 400)
finally:
    for who in (a, b):
        s, v = req("/v1/auth/account", "DELETE", who["token"], {"password": who["pw"]}); out.append(f"删号 {who['name']}: {s}")
    s, _ = req("/v1/auth/login", "POST", body={"username": a["name"], "password": a["pw"], "device": a["dev"]}); out.append(f"删后用 A 登录: {s}（应为 401）")
print("\n".join(out))
