package gk;

import Rj.C2732n;
import Sf.AbstractC2803q;
import java.util.List;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
public final class X extends W {
    public X(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10);
    }

    @Override // gk.W, gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        Sj.g gVar = (Sj.g) sVar.q().I().get(D());
        List listB = gVar != null ? gVar.b() : null;
        List listA = gVar != null ? gVar.a() : null;
        int i10 = 0;
        C((Long[]) ak.c.f28342a.c(listA, listB).toArray(new Long[0]));
        ek.I[] iArrR = x().r();
        int length = iArrR.length;
        int i11 = 0;
        while (i10 < length) {
            ek.I i12 = iArrR[i10];
            int i13 = i11 + 1;
            if (i12.b()) {
                v()[i11] = Sf.z.n1(ak.c.f28342a.b(listA, listB, AbstractC7609s.f(i12.a(), "FR") ? "fundingRate" : "", G()));
            }
            i10++;
            i11 = i13;
        }
    }

    @Override // gk.W
    public String D() {
        return "fr";
    }

    @Override // gk.W
    public List E() {
        return AbstractC2803q.e("fundingRate");
    }

    @Override // Rj.AbstractC2755v
    public int p() {
        return 7;
    }
}
