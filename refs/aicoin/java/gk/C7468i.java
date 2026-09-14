package gk;

import Rj.AbstractC2755v;
import Rj.C2732n;
import Rj.C2765z;
import Rj.y1;
import java.util.List;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.chart.data.LargeOrderItem;
import sp.aicoin_kline.chart.data.LargeOrderMap;

/* JADX INFO: renamed from: gk.i, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7468i extends AbstractC2755v {

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final sp.aicoin_kline.core.indicator.config.F f96517n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public volatile LargeOrderMap f96518o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final int f96519p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public y1 f96520q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final C7485q0 f96521r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public List f96522s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public C7486r0 f96523t;

    /* JADX INFO: renamed from: gk.i$a */
    public /* synthetic */ class a {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public static final /* synthetic */ int[] f96524a;

        static {
            int[] iArr = new int[Rj.X.values().length];
            try {
                iArr[Rj.X.RESET_ALL.ordinal()] = 1;
            } catch (NoSuchFieldError unused) {
            }
            try {
                iArr[Rj.X.APPEND_OR_MERGE.ordinal()] = 2;
            } catch (NoSuchFieldError unused2) {
            }
            try {
                iArr[Rj.X.REPLACE_OPEN.ordinal()] = 3;
            } catch (NoSuchFieldError unused3) {
            }
            f96524a = iArr;
        }
    }

    public C7468i(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str);
        this.f96517n = f10;
        this.f96518o = new LargeOrderMap(null, null, 3, null);
        this.f96521r = new C7485q0();
        this.f96523t = C7486r0.f96556c.a();
        this.f96519p = f10.r().length;
        this.f96520q = c2732n.b().m("ds0");
    }

    public static final Qf.H s(C7486r0 c7486r0, LargeOrderItem largeOrderItem) {
        AbstractC7470j.d(largeOrderItem, c7486r0);
        return Qf.H.f17640a;
    }

    public static final Qf.H u(C7486r0 c7486r0, LargeOrderItem largeOrderItem) {
        AbstractC7470j.d(largeOrderItem, c7486r0);
        return Qf.H.f17640a;
    }

    public static final Qf.H v(C7486r0 c7486r0, LargeOrderItem largeOrderItem) {
        AbstractC7470j.d(largeOrderItem, c7486r0);
        return Qf.H.f17640a;
    }

    @Override // Rj.AbstractC2755v
    public void l(int i10, double[] dArr) {
        C2765z c2765zH;
        Sj.b bVarD;
        if (dArr.length >= 2 && (c2765zH = h().b().h(c())) != null) {
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
    }

    @Override // Rj.AbstractC2755v
    public void q(dk.s sVar) {
        x(sVar);
    }

    public final void t(List list, C7486r0 c7486r0) {
        this.f96522s = list;
        this.f96523t = c7486r0;
        if (c7486r0.d()) {
            this.f96521r.e(list, new C7466h(c7486r0));
            this.f96518o = new LargeOrderMap(null, this.f96521r.g(), 1, null);
        } else {
            this.f96521r.c();
            this.f96518o = new LargeOrderMap(null, null, 3, null);
        }
    }

    public final LargeOrderMap w() {
        return this.f96518o;
    }

    public final void x(dk.s sVar) {
        List listK = sVar.q().K();
        C7486r0 c7486r0C = AbstractC7470j.c(sVar);
        if (listK == this.f96522s && AbstractC7609s.f(c7486r0C, this.f96523t)) {
            return;
        }
        t(listK, c7486r0C);
    }

    public final void y(dk.s sVar, List list, Rj.X x10) {
        C7486r0 c7486r0C = AbstractC7470j.c(sVar);
        if (x10 == Rj.X.RESET_ALL || this.f96522s == null || !AbstractC7609s.f(c7486r0C, this.f96523t)) {
            t(sVar.q().K(), c7486r0C);
            return;
        }
        int i10 = a.f96524a[x10.ordinal()];
        if (i10 != 1) {
            if (i10 == 2) {
                this.f96521r.d(list, new C7464g(c7486r0C));
            } else {
                if (i10 != 3) {
                    throw new Qf.n();
                }
                this.f96521r.f(list, new C7462f(c7486r0C));
            }
        }
        this.f96522s = sVar.q().K();
        this.f96518o = new LargeOrderMap(null, this.f96521r.g(), 1, null);
    }
}
