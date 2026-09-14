package gk;

import Rj.C2732n;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: gk.x, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7497x extends AbstractC7467h0 {
    public C7497x(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        Pj.h hVar;
        B();
        int iP = sVar.p();
        Sj.a<Sj.b> aVarC = sVar.q().C();
        int iG = x().l()[0].g();
        int iG2 = x().l()[1].g();
        int iG3 = x().l()[2].g();
        int iG4 = x().l()[3].g();
        int iG5 = x().l()[4].g();
        int iG6 = x().l()[5].g();
        boolean zB = x().r()[0].b();
        boolean zB2 = x().r()[1].b();
        boolean zB3 = x().r()[2].b();
        ArrayList arrayList = new ArrayList(AbstractC2804s.y(aVarC, 10));
        for (Sj.b bVar : aVarC) {
            arrayList.add(Double.valueOf((bVar.c() + bVar.b()) / 2.0d));
        }
        Pj.h hVar2 = new Pj.h();
        if (zB) {
            hVar = hVar2;
            double[] dArrN1 = Sf.z.n1(nk.z.e(Pj.f.b(hVar, arrayList, iG, false, 4, null), iP));
            hVar.e();
            s(dArrN1, iG4);
            v()[0] = dArrN1;
        } else {
            hVar = hVar2;
        }
        if (zB2) {
            double[] dArrN2 = Sf.z.n1(nk.z.e(Pj.f.b(hVar, arrayList, iG2, false, 4, null), iP));
            hVar.e();
            s(dArrN2, iG5);
            v()[1] = dArrN2;
        }
        if (zB3) {
            double[] dArrN3 = Sf.z.n1(nk.z.e(Pj.f.b(hVar, arrayList, iG3, false, 4, null), iP));
            s(dArrN3, iG6);
            v()[2] = dArrN3;
        }
    }

    @Override // Rj.AbstractC2755v
    public int p() {
        return KLineManager.f142490O.a().j();
    }
}
