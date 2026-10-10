"""线上同步字段冒烟：新加一个 `.synced` 设置字段、部署后端之后，用一次性测试账号验证服务端真的认它。

    python3 -I ops/sync-field-smoke.py autoLayers --good '["FVG"]' --bad '["X"]' --bad '"FVG"' --bad '["FVG","FVG"]'
    python3 -I ops/sync-field-smoke.py reviewSegment --good '"views"' --bad '"stats"' --with skin='"terra"'
    python3 -I ops/sync-field-smoke.py --retired portraitHeight=0.5 --retired routePolicy='"direct"'
    python3 -I ops/sync-field-smoke.py --inline-device

流程：注册一个随机用户名的测试账号 → 逐个推 `--good` 的值（期望 200，并从 bootstrap 读回同一个值）
→ 逐个推 `--bad` 的值（期望被拒：设置 / 画线偏好 2026-10-10 起只丢这个字段——200、回执 `invalidFields`
点名它、bootstrap 读回不是这个值；别的集合整条 400）→ 删掉这个账号 → 确认删后登录 401。
`--with 名=值`：每次推都在同一条操作里捎上这个合法字段——推坏值 / 退役键时验证「只丢坏的那个、别的照常落地」；
画线集合要整条画线才收（kind / symbol / venue / market / anchors），也靠它捎上：
    python3 -I ops/sync-field-smoke.py style --collection drawings --object binance/usd_m/BTCUSDT/smoke-1 \
      --good '{"vp":true}' --bad '[1]' --with kind='"hline"' --with symbol='"BTCUSDT"' --with venue='"binance"' \
      --with market='"usd_m"' --with anchors='[{"t":1800000000000,"p":100}]'

`--retired 名=值`：退役键（RETIRED_*_FIELDS），期望 200、`droppedFields` 点名、`invalidFields` 不点名、读回没有它。
`--inline-device`：一批两条，一条用别的设备号——`?rejections=inline` 下只拒那一条（`status:"rejected"`、
`code:"invalid_device"`）、另一条照常落地；不带这个参数的老行为仍是整批 400 `invalid_device`。
账号是一行测试数据，脚本结束时一定删（finally）；密码随机生成，不打印。
只打 `/v1/auth/*` 与 `/v1/sync/*`，不碰别人的数据；注册有每 IP 每分钟 30 次的限额，连跑别超。
"""
import argparse, json, secrets, sys, time, uuid, urllib.error, urllib.request

ap = argparse.ArgumentParser()
ap.add_argument("field", nargs="?")
ap.add_argument("--good", action="append", default=[], help="应被接受的 JSON 值，可多次")
ap.add_argument("--bad", action="append", default=[], help="应被拒的 JSON 值（400，或 200 但 invalidFields 点名），可多次")
ap.add_argument("--base", default="https://kanpan.43-160-232-253.sslip.io")
ap.add_argument("--collection", default="settings")
ap.add_argument("--object", default="chart")
ap.add_argument("--with", dest="companions", action="append", default=[], help="名=JSON：每次推都在同一条操作里捎上的合法字段，可多次")
ap.add_argument("--retired", action="append", default=[], help="名=JSON：退役键，应 200 且被丢进 droppedFields，可多次")
ap.add_argument("--inline-device", action="store_true", help="验证 ?rejections=inline 下设备号不对只拒那一条")
args = ap.parse_args()
if (args.good or args.bad) and not args.field:
    ap.error("--good / --bad 需要字段名")


def pair(raw):
    name, _, value = raw.partition("=")
    return name, json.loads(value)


companions = dict(pair(r) for r in args.companions)

user = "qa_sync_" + secrets.token_hex(4)
password = "Qa" + secrets.token_hex(8) + "1"
device = {"id": str(uuid.uuid4()), "name": "sync-field-smoke", "secret": secrets.token_hex(24), "kind": "desktop"}


def call(method, path, body=None, token=None, extra=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(args.base + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    for k, v in (extra or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw[:200].decode(errors="replace")}


def operation(fields, device_id=None):
    return {"id": str(uuid.uuid4()), "collection": args.collection, "objectId": args.object, "deviceId": device_id or device["id"],
            "baseRevision": 0, "generation": 0, "timestamp": int(time.time() * 1000), "logical": 1,
            "action": "patch", "fields": fields, "importBatch": None}


def push_ops(ops, token, query=""):
    return call("POST", "/v1/sync/operations" + query, {"operations": ops}, token, {"Idempotency-Key": str(uuid.uuid4())})


def push(value, token, field=None, extra=None):
    return push_ops([operation({**(extra or {}), (field or args.field): value})], token)


def stored_now(token, field):
    st, b = call("GET", f"/v1/sync/bootstrap?collection={args.collection}", None, token)
    objs = b.get("data", {}).get("objects", []) if st == 200 else []
    body = next((o.get("body", {}) for o in objs if o.get("id") == args.object), {})
    return st, (field in body), body.get(field)


def companions_landed(r, fields=None):
    body = r.get("object", {}).get("body", {})
    return all(body.get(k) == v for k, v in (companions if fields is None else fields).items())


results = []


def check(name, ok, detail=""):
    results.append(ok)
    print(("PASS " if ok else "FAIL ") + name + ("  " + detail if detail else ""))


st, body = call("POST", "/v1/auth/register", {"username": user, "password": password, "device": device})
check("注册测试账号", st == 201 and "accessToken" in body.get("data", {}), f"status={st} user={user}")
if st != 201:
    sys.exit(1)
token = body["data"]["accessToken"]
try:
    for raw in args.good:
        value = json.loads(raw)
        st, b = push(value, token, extra=companions)
        r = (b.get("data", {}).get("results") or [{}])[0] if st == 200 else {}
        check(f"推 {args.field}={raw} 应接受", st == 200 and args.field not in r.get("droppedFields", [args.field]),
              f"status={st} droppedFields={r.get('droppedFields')} invalidFields={r.get('invalidFields')}"
              + ("" if st == 200 else " " + json.dumps(b, ensure_ascii=False)[:160]))
        st, b = call("GET", f"/v1/sync/bootstrap?collection={args.collection}", None, token)
        objs = b.get("data", {}).get("objects", []) if st == 200 else []
        stored = next((o.get("body", {}).get(args.field) for o in objs if o.get("id") == args.object), None)
        check(f"bootstrap 读回 {args.field}={raw}", stored == value, f"status={st} stored={json.dumps(stored, ensure_ascii=False)}")
    for raw in args.bad:
        value = json.loads(raw)
        st, b = push(value, token, extra=companions)
        if st == 200:
            # 宽容集合：操作照常落地，但这个字段被丢掉、回执里点名，读回的不是这个值。
            r = (b.get("data", {}).get("results") or [{}])[0]
            stored = r.get("object", {}).get("body", {}).get(args.field)
            ok = args.field in (r.get("invalidFields") or []) and args.field in (r.get("droppedFields") or []) \
                and stored != value and companions_landed(r)
            check(f"推 {args.field}={raw} 应只丢字段", ok,
                  f"droppedFields={r.get('droppedFields')} invalidFields={r.get('invalidFields')} stored={json.dumps(stored, ensure_ascii=False)}"
                  + (f" 捎带={json.dumps({k: r.get('object', {}).get('body', {}).get(k) for k in companions}, ensure_ascii=False)}" if companions else ""))
        else:
            check(f"推 {args.field}={raw} 应 400", st == 400, f"status={st} {json.dumps(b, ensure_ascii=False)[:120]}")
    for raw in args.retired:
        name, value = pair(raw)
        st, b = push(value, token, field=name, extra=companions)
        r = (b.get("data", {}).get("results") or [{}])[0] if st == 200 else {}
        ok = st == 200 and name in (r.get("droppedFields") or []) and name not in (r.get("invalidFields") or []) \
            and name not in r.get("object", {}).get("body", {}) and companions_landed(r)
        check(f"推退役键 {raw} 应被丢", ok, f"status={st} droppedFields={r.get('droppedFields')} invalidFields={r.get('invalidFields')}")
        st, present, _ = stored_now(token, name)
        check(f"bootstrap 读回没有 {name}", st == 200 and not present, f"status={st}")
    if args.inline_device:
        other = str(uuid.uuid4())
        good_fields = companions or {"skin": "terra"}
        st, b = push_ops([operation(good_fields, other), operation(good_fields)], token)
        check("老行为：一批里有一条设备号不对 → 整批 400 invalid_device",
              st == 400 and b.get("error", {}).get("code") == "invalid_device",
              f"status={st} {json.dumps(b, ensure_ascii=False)[:120]}")
        st, b = push_ops([operation(good_fields, other), operation(good_fields)], token, "?rejections=inline")
        rs = (b.get("data", {}).get("results") or []) if st == 200 else []
        first, second = (rs + [{}, {}])[:2]
        check("?rejections=inline：设备号不对的那一条单独拒", st == 200 and first.get("status") == "rejected" and first.get("code") == "invalid_device"
              and "object" not in first, f"status={st} first={json.dumps(first, ensure_ascii=False)[:160]}")
        check("?rejections=inline：同一批另一条照常落地", "object" in second and companions_landed(second, good_fields),
              f"second.cursor={second.get('cursor')} droppedFields={second.get('droppedFields')}")
finally:
    st, b = call("DELETE", "/v1/auth/account", {"password": password}, token)
    check("删掉测试账号", st == 200, f"status={st}")
    st, b = call("POST", "/v1/auth/login", {"username": user, "password": password, "device": device})
    check("删后登录被拒", st == 401, f"status={st}")
sys.exit(0 if all(results) else 1)
