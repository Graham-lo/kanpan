package gk;

import Rj.C2732n;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class F0 extends AbstractC7467h0 {
    public F0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        List listN = sVar.n();
        int iP = sVar.p();
        int iMin = Math.min(x().m(), w());
        for (int i10 = 0; i10 < iMin; i10++) {
            boolean zB = x().r()[i10].b();
            int iG = x().l()[i10].g();
            if (iG == 0) {
                zB = false;
            }
            if (zB) {
                v()[i10] = Sf.z.n1(nk.z.e(new Qj.l().a(listN, iG), iP));
            }
        }
    }
}
