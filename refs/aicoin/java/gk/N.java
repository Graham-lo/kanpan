package gk;

import Rj.C2732n;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class N extends AbstractC7467h0 {
    public N(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        Qj.a aVar = new Qj.a(sVar.p(), 0.0d, 2, null);
        int iG = x().l()[0].g();
        int iG2 = x().l()[1].g();
        int iG3 = x().l()[2].g();
        boolean zB = x().r()[0].b();
        boolean zB2 = x().r()[1].b();
        List listB = Pj.a.b(aVar, sVar.n(), iG, false, 4, null);
        aVar.g();
        List listB2 = Pj.a.b(aVar, sVar.n(), iG2, false, 4, null);
        aVar.g();
        ArrayList arrayList = new ArrayList(AbstractC2804s.y(listB, 10));
        int i10 = 0;
        for (Object obj : listB) {
            int i11 = i10 + 1;
            if (i10 < 0) {
                Sf.r.x();
            }
            arrayList.add(Double.valueOf(((Number) obj).doubleValue() - ((Number) listB2.get(i10)).doubleValue()));
            i10 = i11;
        }
        if (zB) {
            v()[0] = Sf.z.n1(arrayList);
        }
        if (zB2) {
            v()[1] = Sf.z.n1(Pj.a.b(aVar, nk.z.m(arrayList, false, 1, null), iG3, false, 4, null));
        }
    }
}
