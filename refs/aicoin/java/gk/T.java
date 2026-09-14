package gk;

import Rj.C2732n;
import java.util.List;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class T extends AbstractC7467h0 {
    public T(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        Pj.d dVar = new Pj.d();
        List listN = sVar.n();
        int iW = w();
        for (int i10 = 0; i10 < iW; i10++) {
            dVar.e();
            boolean zB = x().r()[i10].b();
            int iG = x().l()[i10].g();
            if (iG == 0) {
                zB = false;
            }
            if (zB) {
                v()[i10] = Sf.z.n1(dVar.a(listN, iG, true));
            }
        }
    }

    @Override // Rj.AbstractC2755v
    public int p() {
        return KLineManager.f142490O.a().j();
    }
}
