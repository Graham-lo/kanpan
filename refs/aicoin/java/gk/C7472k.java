package gk;

import Rj.AbstractC2755v;
import Rj.C2732n;
import Rj.C2765z;
import Rj.y1;
import sp.aicoin_kline.chart.data.LargeTradeMap;

/* JADX INFO: renamed from: gk.k, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7472k extends AbstractC2755v {

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final sp.aicoin_kline.core.indicator.config.F f96525n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public volatile LargeTradeMap f96526o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final int f96527p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public y1 f96528q;

    public C7472k(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str);
        this.f96525n = f10;
        this.f96527p = f10.r().length;
        this.f96526o = new LargeTradeMap(null, null, 3, null);
        this.f96528q = c2732n.b().m("ds0");
    }

    @Override // Rj.AbstractC2755v
    public void l(int i10, double[] dArr) {
        Sj.b bVarD;
        C2765z c2765zH = h().b().h(c());
        if (c2765zH == null) {
            return;
        }
        int iD = c2765zH.D() - 1;
        Sj.a aVarC = c2765zH.C();
        if (aVarC.size() <= 0 || (bVarD = (Sj.b) Sf.z.r0(aVarC, i10)) == null) {
            return;
        }
        if (i10 == iD) {
            bVarD = nk.c.f134195a.d(bVarD);
        }
        dArr[0] = bVarD.c();
        dArr[1] = bVarD.b();
    }

    @Override // Rj.AbstractC2755v
    public void q(dk.s sVar) {
        t(sVar);
    }

    public final LargeTradeMap s() {
        return this.f96526o;
    }

    public final void t(dk.s sVar) {
        this.f96526o = AbstractC7474l.a(sVar.q().L(), sVar.z());
    }
}
