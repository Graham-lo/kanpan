package Rj;

/* JADX INFO: loaded from: classes7.dex */
public class W1 extends AbstractC2759w0 {

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public double f19269D;

    public W1(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f19269D = 1.5d;
    }

    @Override // Rj.AbstractC2759w0
    public void T() {
        C2741q c2741qB = o().b();
        AbstractC2755v abstractC2755vG = c2741qB.g(d() + ".m");
        double dMin = Double.MAX_VALUE;
        double dMax = -1.7976931348623157E308d;
        if (abstractC2755vG != null) {
            dMin = Math.min(Double.MAX_VALUE, abstractC2755vG.m());
            dMax = Math.max(-1.7976931348623157E308d, abstractC2755vG.j());
        }
        AbstractC2755v abstractC2755vG2 = c2741qB.g(d() + ".a");
        if (abstractC2755vG2 != null) {
            dMin = Math.min(dMin, abstractC2755vG2.m());
            dMax = Math.max(dMax, abstractC2755vG2.j());
        }
        double dMax2 = Math.max(Math.abs(dMin), Math.abs(dMax));
        L(-dMax2, dMax2);
    }

    /* JADX WARN: Code duplicated, block: B:13:0x0052  */
    @Override // Rj.AbstractC2759w0
    public void U(int i10) {
        double d10;
        p().clear();
        if (z() > 0.0d && i10 >= 1) {
            B0 b10 = (B0) o().b().a(d() + "Range.m");
            if (b10 == null) {
                d10 = 0.0d;
            } else {
                double dW = ((double) b10.w()) * this.f19269D;
                if (Math.floor(((double) i10) / dW) < 2.0d) {
                    d10 = 0.0d;
                } else {
                    double dZ = z();
                    int i11 = 3;
                    while (O(dZ / ((double) i11)) > dW) {
                        i11 += 2;
                    }
                    d10 = dZ / ((double) (i11 - 2));
                }
            }
            if (d10 <= 0.0d) {
                return;
            }
            double d11 = d10 / 2.0d;
            if (d11 + d10 == d11) {
                return;
            }
            int i12 = 0;
            do {
                p().add(Double.valueOf(d11));
                p().add(Double.valueOf(-d11));
                d11 += d10;
                i12++;
                if (d11 > u()) {
                    return;
                }
            } while (i12 < 30);
        }
    }

    public void X(double d10) {
        this.f19269D = d10;
    }
}
