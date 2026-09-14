package gk;

import Rj.C2732n;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.List;

/* JADX INFO: renamed from: gk.m, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7476m extends W {
    public C7476m(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
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
            List listF2 = nk.z.f(cVar.b(listA, listB, F(1), G()), iP);
            ArrayList arrayList = new ArrayList(AbstractC2804s.y(listF, 10));
            int i10 = 0;
            for (Object obj : listF) {
                int i11 = i10 + 1;
                if (i10 < 0) {
                    Sf.r.x();
                }
                arrayList.add(Double.valueOf(((Number) obj).doubleValue() - ((Number) listF2.get(i10)).doubleValue()));
                i10 = i11;
            }
            v()[0] = Sf.z.n1(nk.z.e(new Qj.n().a(arrayList), iP));
        }
    }

    @Override // gk.W
    public String D() {
        return "turnover";
    }

    @Override // gk.W
    public List E() {
        return Sf.r.q("buyTurnover", "sellTurnover");
    }
}
