import re,sys,json,datetime,statistics
# 本地日志时间 → epoch ms（日志是本机时区的时:分:秒.毫秒，日期取今天）
day=datetime.date.today()
def ep(h,m,s,ms):
    return int(datetime.datetime(day.year,day.month,day.day,h,m,s,ms*1000).timestamp()*1000)
bars={}   # openTime -> list of (logms, O,H,L,C,V)
closes=[] # (logms, C)
quotes=[]
for l in open('/tmp/kanpan-pchain-a51/feed.log'):
    m=re.match(r'\[(\d+):(\d+):(\d+)\.(\d+)\] (.*)',l)
    if not m: continue
    t=ep(int(m[1]),int(m[2]),int(m[3]),int(m[4])); body=m[5]
    b=re.match(r'末根 (\d+) O=([\d.]+) H=([\d.]+) L=([\d.]+) C=([\d.]+) V=([\d.]+)',body)
    if b:
        ot=int(b[1]); bars.setdefault(ot,[]).append((t,float(b[5]),float(b[6]),float(b[2]),float(b[3]),float(b[4])))
        closes.append((t,float(b[5])))
    q=re.match(r'行情 last=([\d.]+)',body)
    if q: quotes.append((t,float(q[1])))
opens=sorted(bars)
# 末根每秒推进：同一根内相邻两次更新的间隔
gaps=[]
for ot in opens:
    ts=[x[0] for x in bars[ot]]
    gaps+= [b-a for a,b in zip(ts,ts[1:])]
gaps.sort()
# 准点追加：新根第一次出现的时刻 − 开盘时刻
appends=[bars[ot][0][0]-ot for ot in opens[1:]]
steps=[b-a for a,b in zip(opens,opens[1:])]
# 重复：同一根里 V 倒退
vback=sum(1 for ot in opens for a,b in zip(bars[ot],bars[ot][1:]) if b[2]<a[2]-1e-9)
# 对账：REST 成交价 p@T，看推送在 [T-1s, T+1s] 内出现过的收盘价里有没有离它一个步长以内的
tick=0.1
rest=[]
for l in open('/tmp/kanpan-pchain-a51/rest.log'):
    parts=l.split(' ',1)
    try: j=json.loads(parts[1]); rest.append((int(j['time']),float(j['price'])))
    except Exception: pass
seen=set(); within=0; exact=0; worst=[]
for T,p in rest:
    if (T,p) in seen: continue
    seen.add((T,p))
    cand=[c for (t,c) in closes if T-1000<=t<=T+1000]
    if not cand: continue
    d=min(abs(c-p) for c in cand)
    worst.append(d)
    if d<=tick+1e-9: within+=1
    if d<1e-9: exact+=1
# 逐根对账：推送里每根最后一版 OHLCV 对 REST /fapi/v1/klines（同源、独立请求）
import urllib.request
url='https://fapi.binance.com/fapi/v1/klines?symbol=BTCUSDT&interval=1m&startTime=%d&endTime=%d&limit=1500'%(opens[0],opens[-1])
kl={int(k[0]):k for k in json.load(urllib.request.urlopen(url,timeout=10))}
bar_cmp=[]; bar_bad=[]
for ot in opens[:-1]:           # 最后一根可能没走完，不比
    last=bars[ot][-1]; k=kl.get(ot)
    if not k: continue
    O,H,L,C=(float(k[i]) for i in (1,2,3,4))
    d=max(abs(last[3]-O),abs(last[4]-H),abs(last[5]-L),abs(last[1]-C))
    bar_cmp.append(d)
    if d>tick+1e-9: bar_bad.append((ot,last,k[1:6]))
# REST 逐笔价是否落在推送那一根最终的 [L,H] 里
inside=0; outside=[]
for T,p in seen:
    ot=T-T%60000
    if ot in bars and ot!=opens[-1]:
        last=bars[ot][-1]
        if last[5]-tick-1e-9<=p<=last[4]+tick+1e-9: inside+=1
        else: outside.append((T,p,last))
print(json.dumps({
 'bars': len(opens), 'first_open': opens[0], 'last_open': opens[-1],
 'open_step_ms_set': sorted(set(steps)),
 'updates': len(closes),
 'update_gap_ms_p50': gaps[len(gaps)//2], 'update_gap_ms_p90': gaps[int(len(gaps)*.9)], 'update_gap_ms_max': gaps[-1],
 'append_delay_ms_median': statistics.median(appends) if appends else None,
 'append_delay_ms_max': max(appends) if appends else None,
 'volume_went_back': vback,
 'rest_samples': len(seen), 'rest_matched_windows': len(worst),
 'within_one_tick': within, 'exact': exact,
 'max_diff': max(worst) if worst else None,
 'bars_compared_with_rest_klines': len(bar_cmp), 'bars_max_ohlc_diff': max(bar_cmp) if bar_cmp else None, 'bars_bad': bar_bad[:5],
 'rest_trade_inside_final_bar_range': inside, 'rest_trade_outside': outside[:5],
},ensure_ascii=False,indent=1))
