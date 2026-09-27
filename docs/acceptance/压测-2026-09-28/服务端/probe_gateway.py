#!/usr/bin/env python3
"""在 Mac 上对线上网关做轻量只读探测（压测期间每 INTERVAL 秒一轮）。

每轮三件：REST ticker（OKX 源 BTCUSDT，网关缓存 1 秒）、/chart-gateway/stream-health、
WS /market/stream 订阅 btcusdt@kline_1m 收 2 帧就断。只用标准库；WS 手写握手。
用法：python3 probe_gateway.py --duration 420 --interval 12 --out probe.json
"""
import argparse, base64, json, os, socket, ssl, struct, time, urllib.request

HOST = "kanpan.107-174-172-10.sslip.io"


def rest(path):
    t = time.perf_counter()
    try:
        with urllib.request.urlopen(f"https://{HOST}{path}", timeout=10) as r:
            body = r.read(); st = r.status
    except urllib.error.HTTPError as e:
        body = e.read(); st = e.code
    except Exception as e:  # noqa
        return {"ok": False, "err": repr(e)[:120], "ms": round((time.perf_counter() - t) * 1000)}
    return {"ok": st == 200, "status": st, "ms": round((time.perf_counter() - t) * 1000), "bytes": len(body)}


def ws(stream="btcusdt@kline_1m", frames=2):
    t = time.perf_counter()
    try:
        raw = socket.create_connection((HOST, 443), timeout=10)
        s = ssl.create_default_context().wrap_socket(raw, server_hostname=HOST)
        key = base64.b64encode(os.urandom(16)).decode()
        s.sendall((f"GET /market/stream?streams={stream} HTTP/1.1\r\nHost: {HOST}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                   f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = s.recv(4096)
            if not chunk:
                raise IOError("closed during handshake")
            buf += chunk
        head, buf = buf.split(b"\r\n\r\n", 1)
        if b" 101 " not in head.split(b"\r\n")[0]:
            raise IOError(head.split(b"\r\n")[0].decode())
        hs = time.perf_counter()

        def need(n):
            nonlocal buf
            while len(buf) < n:
                c = s.recv(65536)
                if not c:
                    raise IOError("closed")
                buf += c
        got = 0; first = None
        while got < frames:
            need(2); b1, b2 = buf[0], buf[1]; ln = b2 & 0x7F; off = 2
            if ln == 126:
                need(4); ln = struct.unpack(">H", buf[2:4])[0]; off = 4
            elif ln == 127:
                need(10); ln = struct.unpack(">Q", buf[2:10])[0]; off = 10
            need(off + ln); payload = buf[off:off + ln]; buf = buf[off + ln:]
            op = b1 & 0x0F
            if op == 1:
                got += 1
                if first is None:
                    first = time.perf_counter()
                    json.loads(payload)
            elif op == 9:  # ping -> pong（带掩码）
                m = os.urandom(4); s.sendall(bytes([0x8A, 0x80 | len(payload)]) + m + bytes(p ^ m[i % 4] for i, p in enumerate(payload)))
            elif op == 8:
                raise IOError("server close")
        s.sendall(bytes([0x88, 0x80]) + os.urandom(4)); s.close()
        return {"ok": True, "handshakeMs": round((hs - t) * 1000), "firstFrameMs": round((first - t) * 1000), "totalMs": round((time.perf_counter() - t) * 1000)}
    except Exception as e:  # noqa
        return {"ok": False, "err": repr(e)[:160], "ms": round((time.perf_counter() - t) * 1000)}


if __name__ == "__main__":
    p = argparse.ArgumentParser(); p.add_argument("--duration", type=int, default=420); p.add_argument("--interval", type=int, default=12)
    p.add_argument("--out", default="probe.json"); a = p.parse_args()
    end = time.time() + a.duration; rounds = []
    while time.time() < end:
        r = {"t": round(time.time(), 1), "clock": time.strftime("%H:%M:%S"),
             "ticker": rest("/market/v1/ticker?source=okx&symbol=BTCUSDT"), "streamHealth": rest("/chart-gateway/stream-health"), "ws": ws()}
        rounds.append(r); print(json.dumps(r, ensure_ascii=False), flush=True)
        json.dump(rounds, open(a.out, "w"), ensure_ascii=False, indent=1)
        time.sleep(max(0, a.interval - (time.time() - r["t"])))
