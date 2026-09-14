package Tj;

import Rj.AbstractC2755v;
import Rj.C2732n;
import dk.s;

/* JADX INFO: loaded from: classes7.dex */
public final class a extends AbstractC2755v {

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final AbstractC2755v[] f22091n;

    public a(C2732n c2732n, String str, AbstractC2755v[] abstractC2755vArr) {
        super(c2732n, str);
        this.f22091n = abstractC2755vArr;
    }

    @Override // Rj.AbstractC2755v
    public void l(int i10, double[] dArr) {
        double[] dArr2 = new double[2];
        double dMin = Double.MAX_VALUE;
        double dMax = -1.7976931348623157E308d;
        for (AbstractC2755v abstractC2755v : this.f22091n) {
            abstractC2755v.l(i10, dArr2);
            double d10 = dArr2[0];
            double d11 = dArr2[1];
            if (!Double.isNaN(d10)) {
                dMin = Math.min(d10, dMin);
            }
            if (!Double.isNaN(d11)) {
                dMax = Math.max(d11, dMax);
            }
        }
        dArr[0] = dMin;
        dArr[1] = dMax;
    }

    @Override // Rj.AbstractC2755v
    public void q(s sVar) {
        for (AbstractC2755v abstractC2755v : this.f22091n) {
            abstractC2755v.q(sVar);
        }
    }

    public final AbstractC2755v[] s() {
        return this.f22091n;
    }
}
