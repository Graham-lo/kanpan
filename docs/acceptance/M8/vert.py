import bmp, collections
w,h,bpp,comp,px = bmp.load('aicoin.bmp')
P=lambda x,y: px[y][x]
GRID=(0x1C,0x22,0x36); BG=(0x0C,0x10,0x1C)
def near(c,t,tol=8): return all(abs(c[i]-t[i])<=tol for i in range(3))
# 横向扫：哪些 y 整行都是 grid 色（价格网格线）
rows=[]
for y in range(100,900):
    n=sum(1 for x in range(400,1790,7) if near(P(x,y),GRID,14))
    rows.append((y,n))
tot=len(range(400,1790,7))
gridy=[y for y,n in rows if n>tot*0.7]
print("网格行 y:", gridy)
# 分隔线（比 grid 更亮的横线）也找一下：统计每行非背景占比
seps=[]
for y in range(100,900):
    n=sum(1 for x in range(400,1790,7) if not near(P(x,y),BG,10))
    if n>tot*0.85: seps.append(y)
print("非背景占比>85% 的行:", seps)
# 竖向网格线 x
colsx=[]
for x in range(380,1880):
    n=sum(1 for y in range(170,560,5) if near(P(x,y),GRID,14))
    if n>len(range(170,560,5))*0.6: colsx.append(x)
print("竖网格 x:", colsx)
