package Rj;

import java.util.ArrayList;

/* JADX INFO: loaded from: classes7.dex */
public class G1 extends AbstractC2755v {

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public Sj.a f19132n;

    public G1(C2732n c2732n, String str) {
        super(c2732n, str);
    }

    @Override // Rj.AbstractC2755v
    public double i() {
        if (this.f19132n.size() > 0) {
            for (int i10 = 1; i10 < this.f19132n.size(); i10++) {
                Sj.a aVar = this.f19132n;
                double dF = ((Sj.b) aVar.get(aVar.size() - i10)).f();
                if (!Double.isNaN(dF)) {
                    return dF;
                }
            }
        }
        return super.i();
    }

    @Override // Rj.AbstractC2755v
    public void l(int i10, double[] dArr) {
        double dF = 0.0d;
        dArr[0] = 0.0d;
        Sj.a aVar = this.f19132n;
        if (aVar != null && aVar.size() > i10) {
            dF = ((Sj.b) this.f19132n.get(i10)).f();
        }
        dArr[1] = dF;
    }

    @Override // Rj.AbstractC2755v
    public void q(dk.s sVar) {
        C2765z c2765zH = h().b().h(c());
        this.f19132n = c2765zH == null ? null : c2765zH.C();
    }

    public ArrayList s() {
        return this.f19132n;
    }
}
