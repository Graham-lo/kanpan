package gk;

import Rj.C2732n;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class A0 extends AbstractC7467h0 {
    public A0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    /* JADX WARN: Code duplicated, block: B:19:0x00b6  */
    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        double dDoubleValue;
        B();
        int iP = sVar.p();
        int iX = sVar.x();
        List listN = sVar.n();
        List listA = sVar.A();
        int iG = x().l()[0].g();
        boolean zB = x().r()[0].b();
        boolean zB2 = x().r()[1].b();
        ArrayList arrayList = new ArrayList(AbstractC2804s.y(listN, 10));
        int i10 = 0;
        for (Object obj : listN) {
            int i11 = i10 + 1;
            if (i10 < 0) {
                Sf.r.x();
            }
            ((Number) obj).doubleValue();
            if (i10 < 1) {
                dDoubleValue = 0.0d;
            } else if (i10 >= iX) {
                dDoubleValue = Double.NaN;
            } else {
                int i12 = i10 - 1;
                if (((Number) listN.get(i10)).doubleValue() > ((Number) listN.get(i12)).doubleValue()) {
                    dDoubleValue = ((Number) listA.get(i10)).doubleValue();
                } else if (((Number) listN.get(i10)).doubleValue() < ((Number) listN.get(i12)).doubleValue()) {
                    dDoubleValue = -((Number) listA.get(i10)).doubleValue();
                } else {
                    dDoubleValue = 0.0d;
                }
            }
            arrayList.add(Double.valueOf(dDoubleValue));
            i10 = i11;
        }
        List listA2 = new Qj.n().a(arrayList);
        if (zB) {
            v()[0] = Sf.z.n1(nk.z.e(listA2, iP));
        }
        if (zB2) {
            v()[1] = Sf.z.n1(nk.z.e(Pj.a.b(new Qj.a(iP, 0.0d, 2, null), listA2, iG, false, 4, null), iP));
        }
    }
}
