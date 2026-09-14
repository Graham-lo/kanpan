package gk;

import Rj.C2732n;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.List;

/* JADX INFO: renamed from: gk.b, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7454b extends W {
    public C7454b(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10);
    }

    @Override // gk.W, gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        int iP = sVar.p();
        Sj.g gVar = (Sj.g) sVar.q().I().get(D());
        List listB = gVar != null ? gVar.b() : null;
        List listA = gVar != null ? gVar.a() : null;
        ak.c cVar = ak.c.f28342a;
        C((Long[]) cVar.c(listA, listB).toArray(new Long[0]));
        List listF = nk.z.f(cVar.b(listA, listB, F(0), G()), iP);
        List listF2 = nk.z.f(cVar.b(listA, listB, F(1), G()), iP);
        ArrayList arrayList = new ArrayList(AbstractC2804s.y(listF2, 10));
        int i10 = 0;
        for (Object obj : listF2) {
            int i11 = i10 + 1;
            if (i10 < 0) {
                Sf.r.x();
            }
            arrayList.add(Double.valueOf(((Number) listF.get(i10)).doubleValue() + ((Number) obj).doubleValue()));
            i10 = i11;
        }
        List listE = nk.z.e(arrayList, iP);
        boolean zB = x().r()[0].b();
        boolean zB2 = x().r()[1].b();
        if (zB) {
            v()[0] = Sf.z.n1(nk.z.e(listF2, iP));
        }
        if (zB2) {
            v()[1] = Sf.z.n1(nk.z.e(listF, iP));
        }
        v()[2] = Sf.z.n1(nk.z.e(listE, iP));
    }

    @Override // gk.W
    public String D() {
        return "aibst";
    }

    @Override // gk.W
    public List E() {
        return Sf.r.q("sellCount", "buyCount");
    }
}
