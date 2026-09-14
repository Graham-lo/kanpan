package gk;

import Rj.C2732n;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class L extends AbstractC7467h0 {
    public L(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        int iP = sVar.p();
        List listN = sVar.n();
        int iG = x().l()[0].g();
        int iG2 = x().l()[1].g();
        boolean zB = x().r()[0].b();
        boolean zB2 = x().r()[1].b();
        if (zB || zB2) {
            int i10 = (iG / 2) + 1;
            List listE = nk.z.e(Pj.a.b(new Qj.c(), listN, iG, false, 4, null), iP);
            ArrayList arrayList = new ArrayList(AbstractC2804s.y(listN, 10));
            int i11 = 0;
            for (Object obj : listN) {
                int i12 = i11 + 1;
                if (i11 < 0) {
                    Sf.r.x();
                }
                arrayList.add(Double.valueOf(i11 < i10 ? Double.NaN : ((Number) obj).doubleValue() - ((Number) listE.get(i11 - i10)).doubleValue()));
                i11 = i12;
            }
            if (zB) {
                v()[0] = Sf.z.n1(nk.z.e(arrayList, iP));
            }
            if (zB2) {
                v()[1] = Sf.z.n1(nk.z.e(Pj.a.b(new Qj.c(), nk.z.m(arrayList, false, 1, null), iG2, false, 4, null), iP));
            }
        }
    }
}
