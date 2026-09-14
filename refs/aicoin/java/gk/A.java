package gk;

import Rj.C2732n;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.List;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class A extends AbstractC7467h0 {
    public A(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        int iP = sVar.p();
        List listN = sVar.n();
        int iG = x().l()[0].g();
        int iG2 = x().l()[1].g();
        int iG3 = x().l()[2].g();
        int iG4 = x().l()[3].g();
        List listE = nk.z.e(Pj.a.b(new Qj.c(), listN, iG, false, 4, null), iP);
        List listE2 = nk.z.e(Pj.a.b(new Qj.c(), listN, iG2, false, 4, null), iP);
        List listE3 = nk.z.e(Pj.a.b(new Qj.c(), listN, iG3, false, 4, null), iP);
        List listE4 = nk.z.e(Pj.a.b(new Qj.c(), listN, iG4, false, 4, null), iP);
        ArrayList arrayList = new ArrayList(AbstractC2804s.y(listN, 10));
        int i10 = 0;
        for (Object obj : listN) {
            int i11 = i10 + 1;
            if (i10 < 0) {
                Sf.r.x();
            }
            ((Number) obj).doubleValue();
            arrayList.add(Double.valueOf((((Number) listE4.get(i10)).doubleValue() + (((Number) listE3.get(i10)).doubleValue() + (((Number) listE2.get(i10)).doubleValue() + ((Number) listE.get(i10)).doubleValue()))) / ((double) 4)));
            i10 = i11;
        }
        v()[0] = Sf.z.n1(arrayList);
    }

    @Override // Rj.AbstractC2755v
    public int p() {
        return KLineManager.f142490O.a().j();
    }
}
