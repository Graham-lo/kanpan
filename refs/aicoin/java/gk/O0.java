package gk;

import Rj.C2732n;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class O0 extends AbstractC7467h0 {
    public O0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        List listN = sVar.n();
        int iP = sVar.p();
        int iG = x().l()[0].g();
        int iG2 = x().l()[1].g();
        int iG3 = x().l()[2].g();
        int iG4 = x().l()[3].g();
        boolean zB = x().r()[0].b();
        boolean zB2 = x().r()[1].b();
        List listM = nk.z.m(new Qj.l().a(listN, iG), false, 1, null);
        List listA = new Qj.j().a(nk.z.e(new Qj.m().a(listM, listM, listM, iG2), iP), iG3, true);
        if (zB) {
            v()[0] = Sf.z.n1(nk.z.e(listA, iP));
        }
        if (zB2) {
            v()[1] = Sf.z.n1(nk.z.e(new Qj.j().a(listA, iG4, true), iP));
        }
    }
}
