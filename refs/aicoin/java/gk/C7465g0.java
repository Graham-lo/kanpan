package gk;

import Rj.C2732n;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.List;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: gk.g0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7465g0 extends AbstractC7467h0 {

    /* JADX INFO: renamed from: gk.g0$a */
    public static final class a extends Pj.f {
        @Override // Pj.f
        /* JADX INFO: renamed from: d, reason: merged with bridge method [inline-methods] */
        public Double c(int i10, int i11, int i12, int i13, List list) {
            double dMax = -1.7976931348623157E308d;
            double dMin = Double.MAX_VALUE;
            while (i12 < i13) {
                dMax = Math.max(dMax, ((Sj.b) list.get(i12)).b());
                dMin = Math.min(dMin, ((Sj.b) list.get(i12)).c());
                i12++;
            }
            return Double.valueOf((dMax + dMin) / ((double) 2));
        }
    }

    public C7465g0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    public static final Qf.H D(C7465g0 c7465g0, dk.s sVar, int i10) {
        c7465g0.v()[2] = c7465g0.t(sVar.o(), -i10);
        return Qf.H.f17640a;
    }

    public static final Qf.H E(C7465g0 c7465g0, List list) {
        c7465g0.v()[0] = Sf.z.n1(list);
        return Qf.H.f17640a;
    }

    public static final Qf.H F(C7465g0 c7465g0, List list, int i10) {
        c7465g0.v()[3] = c7465g0.t(Sf.z.n1(list), i10);
        return Qf.H.f17640a;
    }

    public static final Qf.H G(C7465g0 c7465g0, List list) {
        c7465g0.v()[1] = Sf.z.n1(list);
        return Qf.H.f17640a;
    }

    public static final Qf.H H(C7465g0 c7465g0, List list, int i10) {
        c7465g0.v()[4] = c7465g0.t(Sf.z.n1(list), i10);
        return Qf.H.f17640a;
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        int iP = sVar.p();
        int i10 = 0;
        int iG = x().l()[0].g();
        int iG2 = x().l()[1].g();
        int iG3 = x().l()[2].g();
        int iG4 = x().l()[3].g();
        boolean zB = x().r()[0].b();
        boolean zB2 = x().r()[1].b();
        boolean zB3 = x().r()[2].b();
        boolean zB4 = x().r()[3].b();
        boolean zB5 = x().r()[4].b();
        List listE = nk.z.e(Pj.f.b(new a(), sVar.q().C(), iG, false, 4, null), iP);
        List listE2 = nk.z.e(Pj.f.b(new a(), sVar.q().C(), iG2, false, 4, null), iP);
        ArrayList arrayList = new ArrayList(AbstractC2804s.y(listE, 10));
        for (Object obj : listE) {
            int i11 = i10 + 1;
            if (i10 < 0) {
                Sf.r.x();
            }
            arrayList.add(Double.valueOf((((Number) listE2.get(i10)).doubleValue() + ((Number) obj).doubleValue()) / ((double) 2)));
            i10 = i11;
        }
        List listE3 = nk.z.e(Pj.f.b(new a(), sVar.q().C(), iG3, false, 4, null), iP);
        p162hb.e.d(Boolean.valueOf(zB), new C7455b0(this, listE));
        p162hb.e.d(Boolean.valueOf(zB2), new C7457c0(this, listE2));
        p162hb.e.d(Boolean.valueOf(zB3), new C7459d0(this, sVar, iG4));
        p162hb.e.d(Boolean.valueOf(zB4), new C7461e0(this, arrayList, iG4));
        p162hb.e.d(Boolean.valueOf(zB5), new C7463f0(this, listE3, iG4));
    }

    @Override // Rj.AbstractC2755v
    public int p() {
        return KLineManager.f142490O.a().j();
    }
}
