import sys, threading, http.client, http.server, socket
sys.path.insert(0, '/Users/mdd/zhk/kanpan-wt-pchain/Backend/kanpan-gateway')
import market_rest
from market_rest import Upstream, Unavailable

socks = []
class H(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def do_GET(self):
        socks.append(self.connection)
        b = b'ok'
        self.send_response(200); self.send_header('Content-Length', str(len(b))); self.end_headers(); self.wfile.write(b)
    def log_message(self, *a): pass
srv = http.server.ThreadingHTTPServer(('127.0.0.1', 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
port = srv.server_address[1]
market_rest.http.client.HTTPSConnection = lambda host, timeout=None: http.client.HTTPConnection('127.0.0.1', port, timeout=timeout)
up = Upstream('x')
# two keep-alive connections in the pool, as after two overlapping requests
conns = []
for _ in range(2):
    c = http.client.HTTPConnection('127.0.0.1', port, timeout=5); c.request('GET', '/'); r = c.getresponse(); r.read(); conns.append(c)
for c in conns: up._keep(c)
# the exchange closes idle keep-alive sockets
for s in socks:
    try: s.shutdown(socket.SHUT_RDWR)
    except OSError: pass
import time; time.sleep(0.2)
try:
    print('fetch ->', up.fetch('/', {}, 5, 100)[0])
except Unavailable as e:
    print('fetch -> Unavailable:', e, '| cause:', repr(e.__cause__))
