package gk;

import Rj.C2732n;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.List;

/* JADX INFO: renamed from: gk.s, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7487s extends AbstractC7467h0 {
    public C7487s(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        if (x().r()[0].b()) {
            int iP = sVar.p();
            List listR = sVar.r();
            List listT = sVar.t();
            ArrayList arrayList = new ArrayList(AbstractC2804s.y(listR, 10));
            int i10 = 0;
            for (Object obj : listR) {
                int i11 = i10 + 1;
                if (i10 < 0) {
                    Sf.r.x();
                }
                arrayList.add(Double.valueOf((((Number) listT.get(i10)).doubleValue() + ((Number) obj).doubleValue()) / ((double) 2)));
                i10 = i11;
            }
            List listE = nk.z.e(Pj.a.b(new Qj.c(), arrayList, 5, false, 4, null), iP);
            List listE2 = nk.z.e(Pj.a.b(new Qj.c(), arrayList, 34, false, 4, null), iP);
            ArrayList arrayList2 = new ArrayList(AbstractC2804s.y(listE, 10));
            int i12 = 0;
            for (Object obj2 : listE) {
                int i13 = i12 + 1;
                if (i12 < 0) {
                    Sf.r.x();
                }
                arrayList2.add(Double.valueOf(((Number) obj2).doubleValue() - ((Number) listE2.get(i12)).doubleValue()));
                i12 = i13;
            }
            v()[0] = Sf.z.n1(nk.z.e(arrayList2, iP));
        }
    }
}
