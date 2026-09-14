package gk;

import Rj.C2732n;
import Sf.AbstractC2801o;
import java.util.ArrayList;
import java.util.Iterator;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class U extends AbstractC7467h0 {
    public U(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        int iP = sVar.p();
        int iG = x().l()[0].g();
        int i10 = 1;
        double dG = x().l()[1].g();
        double dG2 = x().l()[2].g();
        boolean zB = x().r()[0].b();
        boolean zB2 = x().r()[1].b();
        boolean zB3 = x().r()[2].b();
        ArrayList arrayList = new ArrayList();
        ArrayList arrayList2 = new ArrayList();
        ArrayList arrayList3 = new ArrayList();
        Iterator it = Pj.a.b(new Qj.c(), sVar.n(), iG, false, 4, null).iterator();
        while (it.hasNext()) {
            double dDoubleValue = ((Number) it.next()).doubleValue();
            double d10 = i10;
            int i11 = i10;
            double d11 = dG;
            double d12 = 100;
            double d13 = ((d11 / d12) + d10) * dDoubleValue;
            double d14 = (d10 - (dG2 / d12)) * dDoubleValue;
            arrayList.add(Double.valueOf(d13));
            arrayList2.add(Double.valueOf(d14));
            arrayList3.add(Double.valueOf((d13 + d14) / ((double) 2)));
            i10 = i11;
            dG = d11;
        }
        int i12 = i10;
        if (zB) {
            v()[0] = Sf.z.n1(nk.z.c(arrayList3, iP, Double.valueOf(Double.NaN)));
        }
        if (zB2) {
            v()[i12] = Sf.z.n1(nk.z.c(arrayList, iP, Double.valueOf(Double.NaN)));
        }
        if (zB3) {
            v()[2] = Sf.z.n1(nk.z.c(arrayList2, iP, Double.valueOf(Double.NaN)));
        }
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
