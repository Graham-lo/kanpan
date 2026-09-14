package gk;

import Rj.C2732n;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: gk.t0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7490t0 extends AbstractC7467h0 {
    public C7490t0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        super.A(sVar);
        B();
        int iP = sVar.p();
        List listN = sVar.n();
        int iG = x().l()[0].g();
        int iG2 = x().l()[1].g();
        int iG3 = x().l()[2].g();
        boolean zB = x().r()[0].b();
        boolean zB2 = x().r()[1].b();
        boolean zB3 = x().r()[2].b();
        List listE = nk.z.e(new Pj.d().a(listN, iG, true), iP);
        List listE2 = nk.z.e(new Pj.d().a(listN, iG2, true), iP);
        ArrayList arrayList = new ArrayList(AbstractC2804s.y(listE, 10));
        int i10 = 0;
        for (Object obj : listE) {
            int i11 = i10 + 1;
            if (i10 < 0) {
                Sf.r.x();
            }
            arrayList.add(Double.valueOf(((Number) obj).doubleValue() - ((Number) listE2.get(i10)).doubleValue()));
            i10 = i11;
        }
        List listE3 = nk.z.e(arrayList, iP);
        List listE4 = nk.z.e(new Pj.d().a(nk.z.m(listE3, false, 1, null), iG3, true), iP);
        if (zB) {
            v()[0] = Sf.z.n1(nk.z.e(listE3, iP));
        }
        if (zB2) {
            v()[1] = Sf.z.n1(nk.z.e(listE4, iP));
        }
        if (zB3) {
            p292ng.g gVarY = p292ng.i.y(0, Math.min(listE3.size(), listE4.size()));
            ArrayList arrayList2 = new ArrayList(AbstractC2804s.y(gVarY, 10));
            Iterator it = gVarY.iterator();
            while (it.hasNext()) {
                int iB = ((Sf.J) it).b();
                arrayList2.add(Double.valueOf((((Number) listE3.get(iB)).doubleValue() - ((Number) listE4.get(iB)).doubleValue()) * ((double) 2)));
            }
            v()[2] = Sf.z.n1(nk.z.e(arrayList2, iP));
        }
    }

    @Override // Rj.AbstractC2755v
    public int p() {
        return KLineManager.f142490O.a().j();
    }
}
