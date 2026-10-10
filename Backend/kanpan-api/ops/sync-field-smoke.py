"""线上同步字段冒烟：新加一个 `.synced` 设置字段、部署后端之后，用一次性测试账号验证服务端真的认它。

    python3 -I ops/sync-field-smoke.py autoLayers --good '["FVG"]' --bad '["X"]' --bad '"FVG"' --bad '["FVG","FVG"]'

流程：注册一个随机用户名的测试账号 → 逐个推 `--good` 的值（期望 200，并从 bootstrap 读回同一个值）
→ 逐个推 `--bad` 的值（期望 400 invalid_operation）→ 删掉这个账号 → 确认删后登录 401。
账号是一行测试数据，脚本结束时一定删（finally）；密码随机生成，不打印。
只打 `/v1/auth/*` 与 `/v1/sync/*`，不碰别人的数据；注册有每 IP 每分钟 30 次的限额，连跑别超。
"""
import argparse, json, secrets, sys, time, uuid, urllib.error, urllib.request

ap = argparse.ArgumentParser()
ap.add_argument("field")
ap.add_argument("--good", action="append", default=[], help="应被接受的 JSON 值，可多次")
ap.add_argument("--bad", action="append", default=[], help="应被 400 拒绝的 JSON 值，可多次")
ap.add_argument("--base", default="https://kanpan.43-160-232-253.sslip.io")
ap.add_argument("--collection", default="settings")
ap.add_argument("--object", default="chart")
args = ap.parse_args()

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


def push(value, token):
    op = {"id": str(uuid.uuid4()), "collection": args.collection, "objectId": args.object, "deviceId": device["id"],
          "baseRevision": 0, "generation": 0, "timestamp": int(time.time() * 1000), "logical": 1,
          "action": "patch", "fields": {args.field: value}, "importBatch": None}
    return call("POST", "/v1/sync/operations", {"operations": [op]}, token, {"Idempotency-Key": str(uuid.uuid4())})


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
        st, b = push(value, token)
        check(f"推 {args.field}={raw} 应接受", st == 200, f"status={st} {json.dumps(b, ensure_ascii=False)[:160]}")
        st, b = call("GET", f"/v1/sync/bootstrap?collection={args.collection}", None, token)
        objs = b.get("data", {}).get("objects", []) if st == 200 else []
        stored = next((o.get("body", {}).get(args.field) for o in objs if o.get("id") == args.object), None)
        check(f"bootstrap 读回 {args.field}={raw}", stored == value, f"status={st} stored={json.dumps(stored, ensure_ascii=False)}")
    for raw in args.bad:
        st, b = push(json.loads(raw), token)
        check(f"推 {args.field}={raw} 应 400", st == 400, f"status={st} {json.dumps(b, ensure_ascii=False)[:120]}")
finally:
    st, b = call("DELETE", "/v1/auth/account", {"password": password}, token)
    check("删掉测试账号", st == 200, f"status={st}")
    st, b = call("POST", "/v1/auth/login", {"username": user, "password": password, "device": device})
    check("删后登录被拒", st == 401, f"status={st}")
sys.exit(0 if all(results) else 1)
