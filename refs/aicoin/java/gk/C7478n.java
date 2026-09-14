package gk;

import Rj.C2732n;
import Sf.AbstractC2803q;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.List;

/* JADX INFO: renamed from: gk.n, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7478n extends W {
    public C7478n(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10);
    }

    @Override // gk.W, gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        Sj.g gVar = (Sj.g) sVar.q().I().get(D());
        List listB = gVar != null ? gVar.b() : null;
        List listA = gVar != null ? gVar.a() : null;
        ak.c cVar = ak.c.f28342a;
        C((Long[]) cVar.c(listA, listB).toArray(new Long[0]));
        if (x().r()[0].b()) {
            int iP = sVar.p();
            List listF = nk.z.f(cVar.b(listA, listB, F(0), G()), iP);
            ArrayList arrayList = new ArrayList(AbstractC2804s.y(listF, 10));
            int i10 = 0;
            for (Object obj : listF) {
                int i11 = i10 + 1;
                if (i10 < 0) {
                    Sf.r.x();
                }
                arrayList.add(Double.valueOf(i10 <= 0 ? Double.NaN : ((Number) obj).doubleValue() - ((Number) listF.get(i10 - 1)).doubleValue()));
                i10 = i11;
            }
            v()[0] = Sf.z.n1(nk.z.e(arrayList, iP));
        }
    }

    @Override // gk.W
    public String D() {
        return "position";
    }

    @Override // gk.W
    public List E() {
        return AbstractC2803q.e("close");
    }
}
