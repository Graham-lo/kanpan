package gk;

import Rj.C2732n;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.List;

/* JADX INFO: renamed from: gk.j0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7471j0 extends AbstractC7467h0 {
    public C7471j0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        int iP = sVar.p();
        int i10 = 0;
        int iG = x().l()[0].g();
        int iG2 = x().l()[1].g();
        int iG3 = x().l()[2].g();
        boolean zB = x().r()[0].b();
        boolean zB2 = x().r()[1].b();
        boolean zB3 = x().r()[2].b();
        List listE = nk.z.e(Pj.f.b(new Qj.i(), new Qj.k().a(sVar, iG), iG2, false, 4, null), iP);
        List listE2 = nk.z.e(Pj.f.b(new Qj.i(), listE, iG3, false, 4, null), iP);
        if (zB) {
            v()[0] = Sf.z.n1(nk.z.e(listE, iP));
        }
        if (zB2) {
            v()[1] = Sf.z.n1(nk.z.e(listE2, iP));
        }
        if (zB3) {
            ArrayList arrayList = new ArrayList(AbstractC2804s.y(listE, 10));
            for (Object obj : listE) {
                int i11 = i10 + 1;
                if (i10 < 0) {
                    Sf.r.x();
                }
                arrayList.add(Double.valueOf((((double) 3) * ((Number) obj).doubleValue()) - (((Number) listE2.get(i10)).doubleValue() * ((double) 2))));
                i10 = i11;
            }
            v()[2] = Sf.z.n1(nk.z.e(arrayList, iP));
        }
    }
}
