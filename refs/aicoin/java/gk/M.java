package gk;

import Rj.C2732n;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class M extends AbstractC7467h0 {
    public M(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        int iP = sVar.p();
        Sj.a aVarC = sVar.q().C();
        int iG = x().l()[0].g();
        boolean zB = x().r()[0].b();
        boolean zB2 = x().r()[1].b();
        boolean zB3 = x().r()[2].b();
        List listB = Pj.f.b(new Pj.b(), aVarC, iG, false, 4, null);
        if (zB) {
            double[][] dArrV = v();
            ArrayList arrayList = new ArrayList(AbstractC2804s.y(listB, 10));
            Iterator it = listB.iterator();
            while (it.hasNext()) {
                arrayList.add(Double.valueOf(((Pj.c) it.next()).b()));
            }
            dArrV[0] = Sf.z.n1(nk.z.e(arrayList, iP));
        }
        if (zB2) {
            double[][] dArrV2 = v();
            ArrayList arrayList2 = new ArrayList(AbstractC2804s.y(listB, 10));
            Iterator it2 = listB.iterator();
            while (it2.hasNext()) {
                arrayList2.add(Double.valueOf(((Pj.c) it2.next()).c()));
            }
            dArrV2[1] = Sf.z.n1(nk.z.e(arrayList2, iP));
        }
        if (zB3) {
            double[][] dArrV3 = v();
            ArrayList arrayList3 = new ArrayList(AbstractC2804s.y(listB, 10));
            Iterator it3 = listB.iterator();
            while (it3.hasNext()) {
                arrayList3.add(Double.valueOf(((Pj.c) it3.next()).a()));
            }
            dArrV3[2] = Sf.z.n1(nk.z.e(arrayList3, iP));
        }
    }

    @Override // Rj.AbstractC2755v
    public int p() {
        return KLineManager.f142490O.a().j();
    }
}
