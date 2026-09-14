import struct
def load(path):
    d=open(path,'rb').read()
    off=struct.unpack_from('<I',d,10)[0]
    hs=struct.unpack_from('<I',d,14)[0]
    w,h=struct.unpack_from('<ii',d,18)
    bpp=struct.unpack_from('<H',d,28)[0]
    comp=struct.unpack_from('<I',d,30)[0]
    flip = h>0
    h=abs(h)
    bypp=bpp//8
    row=(w*bypp+3)//4*4
    px=[]
    for y in range(h):
        sy = h-1-y if flip else y
        base=off+sy*row
        r=[]
        for x in range(w):
            b=d[base+x*bypp]; g=d[base+x*bypp+1]; rr=d[base+x*bypp+2]
            r.append((rr,g,b))
        px.append(r)
    return w,h,bpp,comp,px
