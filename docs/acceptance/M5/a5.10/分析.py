# A5.1 / A5.10 / A5.2：30 分钟会话的事后分析（模拟器，Debug 包）
import json, re, statistics, subprocess, urllib.request, os, sys
D = sys.argv[1] if len(sys.argv) > 1 else '/tmp/kanpan-pchain-a510'
OCR = '/tmp/kanpan-pchain-a55/ocr'
def cpu_s(t):
    p = t.split(':'); return int(p[0]) * 60 + float(p[1])
rows = [l.split() for l in open(f'{D}/samples.txt') if l[0].isdigit()]
rows = [(int(r[0]), int(r[1]), cpu_s(r[2])) for r in rows if len(r) >= 3]
t0, rss0, c0 = rows[0]; t1, rss1, c1 = rows[-1]
mid = next(r for r in rows if r[0] - t0 >= 300)
print(f'A5.10 采样 {len(rows)} 次，跨度 {t1-t0} 秒')
print(f'  RSS 首 {rss0/1024:.1f} MB → 末 {rss1/1024:.1f} MB，增长 {(rss1-rss0)/1024:+.1f} MB；峰值 {max(r[1] for r in rows)/1024:.1f} MB')
print(f'  RSS 第 5 分钟 {mid[1]/1024:.1f} MB → 末 {rss1/1024:.1f} MB，增长 {(rss1-mid[1])/1024:+.1f} MB')
print(f'  CPU 平均 {(c1-c0)/(t1-t0)*100:.1f}%（进程 CPU 时间增量 {c1-c0:.1f} s / 墙钟 {t1-t0} s，单核百分比）')
# A5.2
ed = f'{D}/event-draw.json'
if os.path.exists(ed):
    j = json.load(open(ed))
    s = sorted(j.get('samplesMs', []))
    print(f"A5.2 样本 {len(s)}：p50 {j.get('p50')} p90 {j.get('p90')} p99 {j.get('p99')} max {j.get('max')} mean {j.get('mean')}")
    if s: print(f'  自算 p99 {s[min(len(s)-1, int(len(s)*0.99))]:.2f} ms，>16ms 的 {sum(1 for x in s if x > 16)} 个')
# A5.1：截图里的头部价 / 价格胶囊，对币安同时段逐笔成交
def agg(start, end):
    u = f'https://fapi.binance.com/fapi/v1/aggTrades?symbol=BTCUSDT&startTime={start}&endTime={end}&limit=1000'
    return json.load(urllib.request.urlopen(u, timeout=10))
num = lambda s: float(s.replace(',', ''))
print('A5.1 截图对账（头部最新价、右侧价格胶囊 各自是否等于截图前 3 秒内某笔真实成交价；并给与截图时刻最近一笔的差）')
ok = tot = 0
for l in open(f'{D}/rest-at-shot.txt'):
    n, a, b = l.split()[:3]
    png = f'{D}/shot-{n}.png'
    if not os.path.exists(png): continue
    hd = [l.split('\t')[0] for l in subprocess.run([OCR, png, '0.02,0.12,0.45,0.155'], capture_output=True, text=True).stdout.splitlines()]
    axis = [l.split('\t') for l in subprocess.run([OCR, png, '0.88,0.26,1.0,0.60'], capture_output=True, text=True).stdout.splitlines()]
    cp = [t for t, sat in axis if int(sat) > 40]   # 价格胶囊：色底白字，彩度高
    T = int(float(a) * 1000)
    tr = agg(T - 3000, int(float(b) * 1000))
    prices = {float(x['p']) for x in tr}
    last = [float(x['p']) for x in tr if x['T'] <= T]
    ref = last[-1] if last else None
    h = next((num(x) for x in hd if re.fullmatch(r'[\d,]+\.\d', x.strip())), None)
    c = next((num(x) for x in cp if re.fullmatch(r'\d+\.\d', x)), None)
    for name, v in (('头部', h), ('胶囊', c)):
        if v is None: continue
        tot += 1; hit = v in prices; ok += hit
    print(f'  {n} 头部 {h} 胶囊 {c} 截图前最近成交 {ref} 窗口成交 {len(tr)} 笔 头部在窗口内 {h in prices} 胶囊在窗口内 {c in prices} 头部差 {h - ref if h and ref else None:} 胶囊差 {c - ref if c and ref else None}')
print(f'  合计 {ok}/{tot} 个读数等于截图前 3 秒内的真实成交价（BTCUSDT 报价步长 0.1）')
