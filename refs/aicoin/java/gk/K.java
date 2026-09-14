package gk;

import Rj.C2732n;
import java.util.ArrayList;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class K extends AbstractC7467h0 {
    public K(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        if (x().r()[0].b()) {
            int iP = sVar.p();
            int iX = sVar.x();
            int iG = x().l()[0].g();
            List listN = sVar.n();
            List listE = nk.z.e(Pj.f.b(new Qj.j(), listN, iG, false, 4, null), iP);
            ArrayList arrayList = new ArrayList();
            for (int i10 = 0; i10 < iP; i10++) {
                int i11 = (i10 - iG) + 1;
                double dAbs = 0.0d;
                int i12 = 0;
                if (i11 <= i10) {
                    while (true) {
                        if (i11 >= 0) {
                            i12++;
                            dAbs = Math.abs(((Number) listN.get(i11)).doubleValue() - ((Number) listE.get(i10)).doubleValue()) + dAbs;
                        }
                        if (i11 == i10) {
                            break;
                        } else {
                            i11++;
                        }
                    }
                }
                double d10 = dAbs / ((double) i12);
                if (i10 < iX) {
                    arrayList.add(Double.valueOf((((Number) listN.get(i10)).doubleValue() - ((Number) listE.get(i10)).doubleValue()) / (d10 * 0.015d)));
                } else {
                    arrayList.add(Double.valueOf(Double.NaN));
                }
            }
            v()[0] = Sf.z.n1(nk.z.e(arrayList, iP));
        }
    }

    @Override // gk.AbstractC7467h0, Rj.AbstractC2755v
    public void l(int i10, double[] dArr) {
        int iG = x().l()[1].g();
        int iG2 = x().l()[2].g();
        double[] dArr2 = v()[0];
        int iMax = Math.max(iG, iG2);
        int iMin = Math.min(iG, iG2);
        if (dArr2.length == 0 || dArr2.length <= i10) {
            super.l(i10, dArr);
        } else if (Double.isNaN(dArr2[i10])) {
            dArr[0] = iMin;
            dArr[1] = iMax;
        } else {
            dArr[0] = Math.min(dArr2[i10], iMin);
            dArr[1] = Math.max(dArr2[i10], iMax);
        }
    }
}
