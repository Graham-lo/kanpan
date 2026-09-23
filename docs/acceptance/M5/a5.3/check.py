# 读 app 落盘的 1m 快照，和币安 REST 同一段 K 线逐根对：缺口、重复、时间是否等距、OHLC 是否一致
import struct, sys, json, urllib.request
def read(p):
    d=open(p,'rb').read(); o=0
    def u(fmt):
        nonlocal o; v=struct.unpack_from('<'+fmt,d,o); o+=struct.calcsize('<'+fmt); return v[0]
    assert u('I')==0x4B424152; ver=u('H')
    def s():
        nonlocal o; n=u('H'); v=d[o:o+n].decode(); o+=n; return v
    sym=s(); iv=s(); t0=u('Q'); step=u('Q'); n=u('I'); flag=u('B')
    cols=[]
    for _ in range(6 if ver==2 else 5):
        cols.append(list(struct.unpack_from('<%dd'%n,d,o))); o+=8*n
    times=list(struct.unpack_from('<%dq'%n,d,o)) if flag else [t0+i*step for i in range(n)]
    return sym,iv,times,cols
for p in sys.argv[1:]:
    sym,iv,times,cols=read(p)
    dup=len(times)-len(set(times)); gaps=[(a,b) for a,b in zip(times,times[1:]) if b-a!=60000]
    last=times[-2]  # 最后一根可能还没收盘
    url='https://fapi.binance.com/fapi/v1/klines?symbol=BTCUSDT&interval=1m&limit=60&endTime=%d'%last
    rest={int(k[0]):k for k in json.load(urllib.request.urlopen(url,timeout=10))}
    diffs=[]; checked=0
    for i,t in enumerate(times):
        if t in rest and t<=last:
            k=rest[t]; checked+=1
            dd=max(abs(cols[j][i]-float(k[j+1])) for j in range(4))
            if dd>1e-9: diffs.append((t,dd))
    print(f"{p}: {sym} {iv} {len(times)} 根 {times[0]}…{times[-1]} 重复 {dup} 不等距 {len(gaps)} {gaps[:3]} 近60根对REST {checked} 根 OHLC不一致 {len(diffs)} {diffs[:3]}")
