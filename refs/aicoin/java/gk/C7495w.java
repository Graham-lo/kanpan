package gk;

import Rj.AbstractC2755v;
import Rj.C2732n;
import Rj.C2765z;
import java.util.ArrayList;
import java.util.List;

/* JADX INFO: renamed from: gk.w, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7495w extends AbstractC2755v {

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final ArrayList f96563n;

    public C7495w(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f96563n = new ArrayList();
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
        this.f96563n.clear();
        this.f96563n.addAll(sVar.q().A());
    }

    public final List s() {
        return this.f96563n;
    }
}
