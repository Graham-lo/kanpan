import bmp, collections
w,h,bpp,comp,px = bmp.load('aicoin.bmp')
P=lambda x,y: px[y][x]
UP=(0x26,0xA3,0x80); DN=(0xCF,0x3E,0x3E)
def near(c,t,tol=26): return all(abs(c[i]-t[i])<=tol for i in range(3))
def hit(c): return near(c,UP) or near(c,DN)

Y0,Y1=160,566
cols=[]
for x in range(390,1800):
    n=sum(1 for y in range(Y0,Y1) if hit(P(x,y)))
    cols.append((x,n))

runs=[]; cur=[]
for x,n in cols:
    if n>0: cur.append(x)
    else:
        if cur: runs.append(cur); cur=[]
if cur: runs.append(cur)

body=[]; wick=[]; widths=[]
for r in runs:
    widths.append(len(r))
    if len(r)<4: continue
    mid=r[len(r)//2]
    for y in range(Y0,Y1):
        c=P(mid,y)
        if not hit(c): continue
        l=P(mid-2,y); rr=P(mid+2,y)
        if hit(l) and hit(rr): body.append(c)
        elif not hit(l) and not hit(rr): wick.append(c)

top=lambda L,k=6: collections.Counter(L).most_common(k)
print("簇宽分布:", collections.Counter(widths).most_common(8))
print("实体色 top:", [(f"#{r:02X}{g:02X}{b:02X}",n) for (r,g,b),n in top(body)])
print("影线色 top:", [(f"#{r:02X}{g:02X}{b:02X}",n) for (r,g,b),n in top(wick)])
print("样本 实体",len(body),"影线",len(wick))
