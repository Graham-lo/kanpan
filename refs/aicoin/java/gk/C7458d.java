package gk;

import Rj.AbstractC2755v;
import Rj.C2732n;
import Rj.C2765z;
import java.util.ArrayList;
import java.util.List;

/* JADX INFO: renamed from: gk.d, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7458d extends AbstractC2755v {

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final ArrayList f96498n;

    public C7458d(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f96498n = new ArrayList();
    }

    @Override // Rj.AbstractC2755v
    public void l(int i10, double[] dArr) {
        Sj.b bVarD;
        C2765z c2765zH = h().b().h(c());
        if (c2765zH == null) {
            return;
        }
        int iD = c2765zH.D() - 1;
        Sj.a aVarC = c2765zH.C();
        if (aVarC.size() <= 0 || (bVarD = (Sj.b) Sf.z.r0(aVarC, i10)) == null) {
            return;
        }
        if (i10 == iD) {
            bVarD = nk.c.f134195a.d(bVarD);
        }
        dArr[0] = bVarD.c();
        dArr[1] = bVarD.b();
    }

    @Override // Rj.AbstractC2755v
    public void q(dk.s sVar) {
        t(sVar);
    }

    public final List s() {
        return this.f96498n;
    }

    public final void t(dk.s sVar) {
        u();
        this.f96498n.addAll(sVar.q().H());
        Xj.b.f25375a.b(sVar.q().H());
    }

    public final void u() {
        this.f96498n.clear();
    }
}
