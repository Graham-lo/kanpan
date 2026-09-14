package gk;

import Rj.C2732n;

/* JADX INFO: renamed from: gk.w0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7496w0 extends AbstractC7467h0 {
    public C7496w0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    public static final Qf.H D(dk.s sVar, C7496w0 c7496w0) {
        int iP = sVar.p();
        c7496w0.v()[0] = Sf.z.n1(nk.z.e(new Qj.f().a(sVar, c7496w0.x().l()[0].g()), iP));
        return Qf.H.f17640a;
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        p162hb.e.d(Boolean.valueOf(x().r()[0].b()), new C7494v0(sVar, this));
    }

    @Override // gk.AbstractC7467h0, Rj.AbstractC2755v
    public void l(int i10, double[] dArr) {
        dArr[0] = 0.0d;
        dArr[1] = 100.0d;
    }
}
