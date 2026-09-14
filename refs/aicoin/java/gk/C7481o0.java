package gk;

import Rj.C2732n;
import Sf.AbstractC2801o;
import java.util.ArrayList;
import java.util.List;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: gk.o0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7481o0 extends AbstractC7467h0 {
    public C7481o0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    public static final Qf.H D(C7481o0 c7481o0, List list, int i10) {
        c7481o0.v()[0] = Sf.z.n1(nk.z.e(list, i10));
        return Qf.H.f17640a;
    }

    public static final Qf.H E(C7481o0 c7481o0, List list, int i10) {
        c7481o0.v()[1] = Sf.z.n1(nk.z.e(list, i10));
        return Qf.H.f17640a;
    }

    public static final Qf.H F(C7481o0 c7481o0, List list, int i10) {
        c7481o0.v()[2] = Sf.z.n1(nk.z.e(list, i10));
        return Qf.H.f17640a;
    }

    /* JADX WARN: Multi-variable type inference failed */
    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        int iP = sVar.p();
        Sj.a aVarC = sVar.q().C();
        int iG = x().l()[0].g();
        double dG = x().l()[1].g();
        boolean zB = x().r()[0].b();
        boolean zB2 = x().r()[1].b();
        boolean zB3 = x().r()[2].b();
        ArrayList arrayList = new ArrayList();
        ArrayList arrayList2 = new ArrayList();
        ArrayList arrayList3 = new ArrayList();
        ArrayList arrayList4 = new ArrayList();
        int i10 = 0;
        for (Object obj : aVarC) {
            int i11 = i10 + 1;
            if (i10 < 0) {
                Sf.r.x();
            }
            Sj.b bVar = (Sj.b) obj;
            if (i10 > 0) {
                int i12 = i10 - 1;
                arrayList4.add(Double.valueOf(Math.max(bVar.b() - bVar.c(), Math.max(Math.abs(bVar.b() - ((Sj.b) aVarC.get(i12)).a()), Math.abs(bVar.c() - ((Sj.b) aVarC.get(i12)).a())))));
            } else {
                arrayList4.add(Double.valueOf(bVar.b() - bVar.c()));
            }
            zB2 = zB2;
            i10 = i11;
            zB3 = zB3;
            zB = zB;
            dG = dG;
        }
        boolean z10 = zB;
        double d10 = dG;
        boolean z11 = zB2;
        boolean z12 = zB3;
        List listA = new Pj.d().a(sVar.n(), iG, true);
        List listA2 = new Pj.d().a(arrayList4, iG, true);
        int i13 = 0;
        for (Object obj2 : listA) {
            int i14 = i13 + 1;
            if (i13 < 0) {
                Sf.r.x();
            }
            double dDoubleValue = ((Number) obj2).doubleValue();
            double dDoubleValue2 = (((Number) listA2.get(i13)).doubleValue() * d10) + dDoubleValue;
            double dDoubleValue3 = dDoubleValue - (((Number) listA2.get(i13)).doubleValue() * d10);
            arrayList3.add(Double.valueOf(dDoubleValue));
            arrayList.add(Double.valueOf(dDoubleValue2));
            arrayList2.add(Double.valueOf(dDoubleValue3));
            i13 = i14;
        }
        p162hb.e.d(Boolean.valueOf(z10), new C7475l0(this, arrayList, iP));
        p162hb.e.d(Boolean.valueOf(z11), new C7477m0(this, arrayList3, iP));
        p162hb.e.d(Boolean.valueOf(z12), new C7479n0(this, arrayList2, iP));
    }

    @Override // gk.AbstractC7467h0, Rj.AbstractC2755v
    public void l(int i10, double[] dArr) {
        if (KLineManager.f142490O.a().q(11) != 1) {
            super.l(i10, dArr);
            return;
        }
        ArrayList arrayList = new ArrayList();
        double[][] dArrV = v();
        int length = dArrV.length;
        int i11 = 0;
        while (true) {
            double dDoubleValue = Double.NaN;
            if (i11 >= length) {
                break;
            }
            Double dN0 = AbstractC2801o.n0(dArrV[i11], i10);
            if (dN0 != null) {
                dDoubleValue = dN0.doubleValue();
            }
            arrayList.add(Double.valueOf(dDoubleValue));
            i11++;
        }
        Double dM0 = Sf.z.M0(arrayList);
        double dDoubleValue2 = dM0 != null ? dM0.doubleValue() : Double.NaN;
        if (dDoubleValue2 <= 0.0d && !Double.isNaN(dDoubleValue2)) {
            dDoubleValue2 = 1.0E-6d;
        }
        dArr[0] = dDoubleValue2;
        Double dJ0 = Sf.z.J0(arrayList);
        dArr[1] = dJ0 != null ? dJ0.doubleValue() : Double.NaN;
    }

    @Override // Rj.AbstractC2755v
    public int p() {
        return KLineManager.f142490O.a().j();
    }
}
