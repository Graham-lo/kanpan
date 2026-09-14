package fk;

import Rj.C2732n;
import gk.AbstractC7467h0;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class c0 extends AbstractC7467h0 {
    public c0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        Qj.a aVar = new Qj.a(sVar.p(), 0.0d, 2, null);
        List listA = sVar.A();
        int iW = w();
        for (int i10 = 0; i10 < iW; i10++) {
            aVar.g();
            int iG = x().l()[i10].g();
            boolean zB = x().r()[i10].b();
            if (iG == 0) {
                zB = false;
            }
            if (zB) {
                v()[i10] = Sf.z.n1(Pj.a.b(aVar, listA, iG, false, 4, null));
            }
        }
    }
}
