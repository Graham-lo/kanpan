package gk;

import Rj.C2732n;
import java.util.List;
import kotlin.jvm.functions.Function1;

/* JADX INFO: loaded from: classes7.dex */
public abstract class W extends AbstractC7467h0 {
    public W(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, true);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        super.A(sVar);
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
            int i12 = i11 + 1;
            if (iArrR[i10].b()) {
                v()[i11] = Sf.z.n1(ak.c.f28342a.b(listA, listB, F(i11), G()));
            }
            i10++;
            i11 = i12;
        }
    }

    public abstract String D();

    public abstract List E();

    public final String F(int i10) {
        return (String) E().get(i10);
    }

    public Function1 G() {
        return null;
    }

    @Override // Rj.AbstractC2755v
    public boolean o() {
        return true;
    }
}
