package Rj;

import java.util.ArrayList;

/* JADX INFO: renamed from: Rj.j, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public abstract class AbstractC2720j extends AbstractC2755v {

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public Sj.a f19431n;

    public AbstractC2720j(C2732n c2732n, String str) {
        super(c2732n, str);
    }

    @Override // Rj.AbstractC2755v
    public double i() {
        Sj.a aVar = this.f19431n;
        if (aVar != null && aVar.size() > 0) {
            return ((Sj.b) aVar.get(aVar.size() - 1)).a();
        }
        return super.i();
    }

    @Override // Rj.AbstractC2755v
    public void l(int i10, double[] dArr) {
        Sj.b bVarD;
        C2765z c2765zH = h().b().h(c());
        if (c2765zH == null) {
            return;
        }
        int iD = c2765zH.D() - 1;
        Sj.a aVar = this.f19431n;
        if (aVar == null || aVar.size() <= 0 || (bVarD = (Sj.b) Sf.z.r0(aVar, i10)) == null) {
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
        C2765z c2765zH = h().b().h(c());
        this.f19431n = c2765zH != null ? c2765zH.C() : null;
    }

    public final ArrayList s() {
        return this.f19431n;
    }
}
