package gk;

import Rj.C2732n;
import Rj.C2760w1;
import java.util.List;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: gk.y0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7500y0 extends AbstractC7467h0 {
    public C7500y0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        Qj.a aVar = new Qj.a(sVar.p(), 0.0d, 2, null);
        List listN = sVar.n();
        if (!C2760w1.f19594a.j()) {
            v()[1] = Sf.z.n1(Pj.a.b(aVar, listN, 60, false, 4, null));
            return;
        }
        int iW = w();
        for (int i10 = 0; i10 < iW; i10++) {
            aVar.g();
            boolean zB = x().r()[i10].b();
            int iG = x().l()[i10].g();
            if (iG == 0) {
                zB = false;
            }
            if (zB) {
                v()[i10] = Sf.z.n1(Pj.a.b(aVar, listN, iG, false, 4, null));
            }
        }
    }

    @Override // Rj.AbstractC2755v
    public int p() {
        return KLineManager.f142490O.a().j();
    }
}
