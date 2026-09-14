package gk;

import Rj.C2732n;
import Sf.AbstractC2801o;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class D0 extends AbstractC7467h0 {
    public D0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        int iP = sVar.p();
        List listN = sVar.n();
        boolean z10 = false;
        int iG = x().l()[0].g();
        boolean z11 = true;
        int iG2 = x().l()[1].g();
        boolean zB = x().r()[0].b();
        boolean zB2 = x().r()[1].b();
        double[] dArr = new double[iP];
        for (int i10 = 0; i10 < iP; i10++) {
            dArr[i10] = Double.NaN;
        }
        if (listN.size() < iG) {
            return;
        }
        double d10 = 0.0d;
        int i11 = 1;
        while (i11 < iG) {
            boolean z12 = z10;
            if (((Number) listN.get(i11)).doubleValue() > ((Number) listN.get(i11 - 1)).doubleValue()) {
                d10 += 1.0d;
            }
            i11++;
            z10 = z12;
        }
        boolean z13 = z10;
        int size = listN.size();
        int i12 = iG;
        while (i12 < size) {
            boolean z14 = z11;
            if (((Number) listN.get(i12)).doubleValue() > ((Number) listN.get(i12 - 1)).doubleValue()) {
                d10 += 1.0d;
            }
            dArr[i12] = !Double.isNaN(((Number) listN.get(i12)).doubleValue()) ? (d10 / ((double) iG)) * 100.0d : Double.NaN;
            int i13 = i12 - iG;
            if (((Number) listN.get(i13 + 1)).doubleValue() > ((Number) listN.get(i13)).doubleValue()) {
                d10 -= 1.0d;
            }
            i12++;
            z11 = z14;
        }
        boolean z15 = z11;
        if (zB) {
            v()[z13 ? 1 : 0] = dArr;
        }
        if (zB2) {
            v()[z15 ? 1 : 0] = Sf.z.n1(nk.z.e(Pj.f.b(new Qj.j(), AbstractC2801o.e1(dArr), iG2, false, 4, null), iP));
        }
    }
}
