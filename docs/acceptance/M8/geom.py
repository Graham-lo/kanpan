import bmp, collections
w,h,bpp,comp,px = bmp.load('aicoin.bmp')
P=lambda x,y: px[y][x]
UP=(0x26,0xA3,0x80); DN=(0xCF,0x3E,0x3E)
def near(c,t,tol=26): return all(abs(c[i]-t[i])<=tol for i in range(3))
def hit(c): return near(c,UP) or near(c,DN)
Y0,Y1=160,566
cols=[]
for x in range(390,1800):
    cols.append((x,sum(1 for y in range(Y0,Y1) if hit(P(x,y)))))
runs=[];cur=[]
for x,n in cols:
    if n>0: cur.append(x)
    else:
        if cur: runs.append(cur); cur=[]
if cur: runs.append(cur)
runs=[r for r in runs if 3<=len(r)<=8]
bodyW=collections.Counter(len(r) for r in runs)
starts=[r[0] for r in runs]
pitch=collections.Counter(starts[i+1]-starts[i] for i in range(len(starts)-1) if starts[i+1]-starts[i]<12)
gap=collections.Counter(runs[i+1][0]-runs[i][-1]-1 for i in range(len(runs)-1) if runs[i+1][0]-runs[i][-1]-1<8)
wickW=[]; wickLen=[]; bodyH=[]
for r in runs:
    ys=[y for y in range(Y0,Y1) if any(hit(P(x,y)) for x in r)]
    if not ys: continue
    ytop=ys[0]
    wickW.append(sum(1 for x in r if hit(P(x,ytop))))
    bys=[y for y in range(Y0,Y1) if sum(1 for x in r if hit(P(x,y)))>=len(r)-1]
    if bys: bodyH.append(bys[-1]-bys[0]+1); wickLen.append(bys[0]-ytop)
print("根数(过滤后)", len(runs))
print("实体宽 px:", bodyW.most_common(6))
print("步距 px:", pitch.most_common(6))
print("间隙 px:", gap.most_common(6))
print("影线宽 px:", collections.Counter(wickW).most_common(6))
print("实体高 px 分位:", sorted(bodyH)[len(bodyH)//10], sorted(bodyH)[len(bodyH)//2], sorted(bodyH)[-1] if bodyH else None)
print("上影长 px 中位:", sorted(wickLen)[len(wickLen)//2] if wickLen else None)
