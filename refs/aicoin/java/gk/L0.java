package gk;

import Rj.AbstractC2755v;
import Rj.C2732n;
import Rj.C2765z;
import Rj.y1;
import java.util.List;
import java.util.Map;

/* JADX INFO: loaded from: classes7.dex */
public final class L0 extends AbstractC2755v {

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public Map f96473n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public int f96474o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public int f96475p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public double[] f96476q;

    public L0(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f96473n = Sf.N.j();
        this.f96474o = -1;
        this.f96475p = -1;
        this.f96476q = new double[0];
    }

    @Override // Rj.AbstractC2755v
    public void l(int i10, double[] dArr) {
        Sj.b bVarD;
        double[] dArr2;
        Sj.a aVarC;
        y1 y1VarM;
        C2765z c2765zH = h().b().h(c());
        if (c2765zH == null) {
            return;
        }
        int iD = c2765zH.D() - 1;
        Sj.a aVarC2 = c2765zH.C();
        if (aVarC2.size() <= 0 || (bVarD = (Sj.b) Sf.z.r0(aVarC2, i10)) == null) {
            return;
        }
        if (i10 == iD) {
            bVarD = nk.c.f134195a.d(bVarD);
        }
        C2765z c2765zD = h().d();
        if (c2765zD == null || (aVarC = c2765zD.C()) == null || (y1VarM = h().b().m(c())) == null) {
            dArr2 = new double[]{Double.MAX_VALUE, -1.7976931348623157E308d};
        } else {
            double[] dArr3 = {Double.MAX_VALUE, -1.7976931348623157E308d};
            int iR = y1VarM.r();
            int iQ = y1VarM.q();
            if (this.f96474o == iR && this.f96475p == iQ) {
                dArr2 = this.f96476q;
            } else {
                this.f96474o = iR;
                this.f96475p = iQ;
                while (iR < iQ) {
                    Sj.b bVar = (Sj.b) Sf.z.r0(aVarC, iR);
                    double dC = bVar != null ? bVar.c() : 0.0d;
                    double dB = bVar != null ? bVar.b() : 0.0d;
                    if (!Double.isNaN(dC)) {
                        dArr3[0] = Math.min(dC, dArr3[0]);
                    }
                    if (!Double.isNaN(dB)) {
                        dArr3[1] = Math.max(dB, dArr3[1]);
                    }
                    iR++;
                }
                this.f96476q = dArr3;
                dArr2 = dArr3;
            }
        }
        double d10 = dArr2[1] - dArr2[0];
        double d11 = (d10 >= 0.0d ? d10 : 0.0d) * 0.1d;
        dArr[0] = bVarD.c() + d11;
        dArr[1] = bVarD.b() - d11;
    }

    @Override // Rj.AbstractC2755v
    public void q(dk.s sVar) {
        this.f96473n = sVar.q().T();
    }

    public final Map s() {
        return this.f96473n;
    }

    public final boolean t(Sj.f fVar) {
        Sj.f fVar2;
        List list = (List) this.f96473n.get(fVar.a());
        return (list == null || (fVar2 = (Sj.f) Sf.z.D0(list)) == null || fVar2.j() != fVar.j()) ? false : true;
    }
}
