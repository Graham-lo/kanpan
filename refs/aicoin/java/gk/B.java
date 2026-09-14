package gk;

import Rj.C2732n;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class B extends AbstractC7467h0 {
    public B(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    /* JADX WARN: Multi-variable type inference failed */
    /* JADX WARN: Type inference failed for: r18v0 */
    /* JADX WARN: Type inference failed for: r18v1 */
    /* JADX WARN: Type inference failed for: r18v2 */
    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        int i10;
        ?? r18;
        double dE;
        double dE2;
        B();
        int i11 = 0;
        int iG = x().l()[0].g();
        boolean zB = x().r()[0].b();
        boolean z10 = true;
        boolean zB2 = x().r()[1].b();
        List listR = sVar.r();
        List listT = sVar.t();
        List listV = sVar.v();
        List listN = sVar.n();
        double d10 = 0.0d;
        if (zB) {
            ArrayList arrayList = new ArrayList(AbstractC2804s.y(listR, 10));
            i10 = 0;
            for (Object obj : listR) {
                boolean z11 = z10;
                int i12 = i11 + 1;
                if (i11 < 0) {
                    Sf.r.x();
                }
                ((Number) obj).doubleValue();
                if (i11 < iG) {
                    dE2 = Double.NaN;
                } else {
                    double dMax = d10;
                    double dMax2 = dMax;
                    for (int i13 = (i11 - iG) + 1; i13 < i12; i13++) {
                        int i14 = i13 - 1;
                        dMax = Math.max(d10, ((Number) listR.get(i13)).doubleValue() - ((Number) listN.get(i14)).doubleValue()) + dMax;
                        dMax2 = Math.max(d10, ((Number) listN.get(i14)).doubleValue() - ((Number) listT.get(i13)).doubleValue()) + dMax2;
                    }
                    dE2 = nk.A.e(dMax, dMax2, 0.0d, 2, null) * ((double) 100);
                }
                arrayList.add(Double.valueOf(dE2));
                i11 = i12;
                z10 = z11;
                d10 = 0.0d;
            }
            r18 = z10;
            v()[0] = Sf.z.n1(arrayList);
        } else {
            i10 = 0;
            r18 = 1;
        }
        if (zB2) {
            ArrayList arrayList2 = new ArrayList(AbstractC2804s.y(listR, 10));
            int i15 = i10;
            for (Object obj2 : listR) {
                int i16 = i15 + 1;
                if (i15 < 0) {
                    Sf.r.x();
                }
                ((Number) obj2).doubleValue();
                if (i15 < iG - 1) {
                    dE = Double.NaN;
                } else {
                    double dDoubleValue = 0.0d;
                    double dDoubleValue2 = 0.0d;
                    for (int i17 = (i15 - iG) + 1; i17 < i16; i17++) {
                        dDoubleValue += ((Number) listR.get(i17)).doubleValue() - ((Number) listV.get(i17)).doubleValue();
                        dDoubleValue2 += ((Number) listV.get(i17)).doubleValue() - ((Number) listT.get(i17)).doubleValue();
                    }
                    dE = nk.A.e(dDoubleValue, dDoubleValue2, 0.0d, 2, null) * ((double) 100);
                }
                arrayList2.add(Double.valueOf(dE));
                i15 = i16;
            }
            v()[r18] = Sf.z.n1(arrayList2);
        }
    }
}
