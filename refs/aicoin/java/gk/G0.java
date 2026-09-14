package gk;

import Rj.C2732n;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class G0 extends AbstractC7467h0 {
    public G0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        int iP = sVar.p();
        int iG = x().l()[0].g();
        int iG2 = x().l()[1].g();
        int iG3 = x().l()[2].g();
        boolean zB = x().r()[0].b();
        boolean zB2 = x().r()[1].b();
        List listB = Pj.a.b(new Qj.c(), new Qj.k().a(sVar, iG), iG2, false, 4, null);
        if (zB) {
            v()[0] = Sf.z.n1(nk.z.e(listB, iP));
        }
        if (zB2) {
            v()[1] = Sf.z.n1(nk.z.e(Pj.a.b(new Qj.c(), listB, iG3, false, 4, null), iP));
        }
    }
}
