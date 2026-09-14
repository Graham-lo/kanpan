package gk;

import Rj.C2732n;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class E0 extends AbstractC7467h0 {
    public E0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        double dE;
        B();
        int iP = sVar.p();
        List listN = sVar.n();
        int iG = x().l()[0].g();
        int iG2 = x().l()[1].g();
        boolean zB = x().r()[0].b();
        boolean zB2 = x().r()[1].b();
        ArrayList arrayList = new ArrayList(AbstractC2804s.y(listN, 10));
        int i10 = 0;
        for (Object obj : listN) {
            int i11 = i10 + 1;
            if (i10 < 0) {
                Sf.r.x();
            }
            double dDoubleValue = ((Number) obj).doubleValue();
            if (i10 > iG) {
                double dDoubleValue2 = ((Number) listN.get(i10 - iG)).doubleValue();
                dE = nk.A.e(dDoubleValue - dDoubleValue2, dDoubleValue2, 0.0d, 2, null) * ((double) 100);
            } else {
                dE = Double.NaN;
            }
            arrayList.add(Double.valueOf(dE));
            i10 = i11;
        }
        if (zB) {
            v()[0] = Sf.z.n1(nk.z.e(arrayList, iP));
        }
        if (zB2) {
            v()[1] = Sf.z.n1(nk.z.e(Pj.a.b(new Qj.c(), nk.z.m(arrayList, false, 1, null), iG2, false, 4, null), iP));
        }
    }
}
