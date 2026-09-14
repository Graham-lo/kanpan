package Rj;

import java.util.ArrayList;
import java.util.List;

/* JADX INFO: renamed from: Rj.k0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public class C2724k0 extends AbstractC2755v {

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final ArrayList f19444n;

    public C2724k0(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f19444n = new ArrayList();
    }

    @Override // Rj.AbstractC2755v
    public void l(int i10, double[] dArr) {
    }

    @Override // Rj.AbstractC2755v
    public void q(dk.s sVar) {
        C2765z c2765zH = h().b().h(c());
        if (c2765zH == null || c2765zH.B() < 1) {
            return;
        }
        this.f19444n.clear();
        this.f19444n.addAll(c2765zH.Q());
    }

    public List s() {
        return this.f19444n;
    }
}
