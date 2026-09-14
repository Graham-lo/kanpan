package Rj;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class x1 extends AbstractC2720j {

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final int f19603o;

    public x1(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f19603o = KLineManager.f142490O.a().q(14);
    }

    @Override // Rj.AbstractC2720j, Rj.AbstractC2755v
    public void l(int i10, double[] dArr) {
        y1 y1VarM = h().b().m(c());
        if (y1VarM == null || y1VarM.u() >= 5.0f || this.f19603o != 0) {
            super.l(i10, dArr);
            return;
        }
        int iD = h().b().h(c()).D() - 1;
        if (s() == null || s().size() <= 0) {
            return;
        }
        Sj.b bVarD = (Sj.b) s().get(i10);
        if (i10 == iD) {
            bVarD = nk.c.f134195a.d(bVarD);
        }
        dArr[0] = bVarD.a();
        dArr[1] = bVarD.a();
    }
}
