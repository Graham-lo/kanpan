package gk;

import Rj.C2732n;
import java.util.ArrayList;
import java.util.List;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class I0 extends AbstractC7467h0 {
    public I0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    /* JADX WARN: Code duplicated, block: B:40:0x015e A[PHI: r12 r18
      0x015e: PHI (r12v6 double) = (r12v3 double), (r12v8 double) binds: [B:38:0x014e, B:31:0x0111] A[DONT_GENERATE, DONT_INLINE]
      0x015e: PHI (r18v4 double) = (r18v2 double), (r18v6 double) binds: [B:38:0x014e, B:31:0x0111] A[DONT_GENERATE, DONT_INLINE]] */
    /* JADX WARN: Multi-variable type inference failed */
    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        int iP = sVar.p();
        List listR = sVar.r();
        List listT = sVar.t();
        if (iP == 0 || listR.size() < iP || listT.size() < iP) {
            return;
        }
        double d10 = 100;
        double dE = ek.v.e(x(), 0) / d10;
        char c10 = 1;
        double dE2 = ek.v.e(x(), 1) / d10;
        Double d11 = (Double) Sf.z.q0(listR);
        double dDoubleValue = d11 != null ? d11.doubleValue() : 0.0d;
        ArrayList arrayList = new ArrayList();
        int i10 = 0;
        double dMin = dE;
        boolean z10 = true;
        double d12 = 0.0d;
        while (i10 < iP) {
            Double[] dArr = new Double[4];
            dArr[0] = listT.get(i10);
            char c11 = c10;
            int i11 = i10 - 1;
            dArr[c11] = listT.get(Math.max(0, i11));
            int i12 = i10 - 2;
            int i13 = iP;
            dArr[2] = listT.get(Math.max(0, i12));
            int i14 = i10 - 3;
            double d13 = dE;
            dArr[3] = listT.get(Math.max(0, i14));
            List listT2 = Sf.r.t(dArr);
            Double[] dArr2 = new Double[4];
            dArr2[0] = listR.get(i10);
            dArr2[c11] = listR.get(Math.max(0, i11));
            dArr2[2] = listR.get(Math.max(0, i12));
            dArr2[3] = listR.get(Math.max(0, i14));
            List listT3 = Sf.r.t(dArr2);
            Double dM0 = Sf.z.M0(listT2);
            double dDoubleValue2 = dM0 != null ? dM0.doubleValue() : 0.0d;
            Double dJ0 = Sf.z.J0(listT3);
            double dDoubleValue3 = dJ0 != null ? dJ0.doubleValue() : 0.0d;
            if (i10 == 0) {
                dDoubleValue2 = ((Number) listT.get(i10)).doubleValue();
            } else {
                double d14 = ((dDoubleValue - d12) * dMin) + d12;
                if (z10) {
                    if (dDoubleValue < ((Number) listR.get(i10)).doubleValue()) {
                        dDoubleValue = ((Number) listR.get(i10)).doubleValue();
                        dMin = Math.min(dMin + d13, dE2);
                    }
                    if (d14 > ((Number) listT.get(i10)).doubleValue()) {
                        z10 = !z10;
                        dDoubleValue = ((Number) listT.get(i10)).doubleValue();
                        dDoubleValue2 = dDoubleValue3;
                        dMin = d13;
                    } else {
                        dDoubleValue2 = d14;
                    }
                } else {
                    if (dDoubleValue > ((Number) listT.get(i10)).doubleValue()) {
                        dDoubleValue = ((Number) listT.get(i10)).doubleValue();
                        dMin = Math.min(dMin + d13, dE2);
                    }
                    if (d14 < ((Number) listR.get(i10)).doubleValue()) {
                        z10 = !z10;
                        dDoubleValue = ((Number) listR.get(i10)).doubleValue();
                        dMin = d13;
                    } else {
                        dDoubleValue2 = d14;
                    }
                }
            }
            if (Double.isNaN(((Number) listT.get(i10)).doubleValue()) || Double.isNaN(((Number) listR.get(i10)).doubleValue())) {
                dDoubleValue2 = Double.NaN;
            }
            d12 = dDoubleValue2;
            arrayList.add(Double.valueOf(d12));
            i10++;
            c10 = c11;
            iP = i13;
            dE = d13;
        }
        v()[0] = Sf.z.n1(arrayList);
    }

    @Override // Rj.AbstractC2755v
    public int p() {
        return KLineManager.f142490O.a().j();
    }
}
