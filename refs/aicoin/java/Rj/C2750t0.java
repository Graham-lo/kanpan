package Rj;

/* JADX INFO: renamed from: Rj.t0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2750t0 extends AbstractC2759w0 {
    public C2750t0(C2732n c2732n, String str) {
        super(c2732n, str);
    }

    @Override // Rj.AbstractC2759w0
    public void U(int i10) {
        double d10;
        p().clear();
        if (z() > 0.0d && i10 >= 1) {
            B0 b10 = (B0) o().b().a(d() + "Range.m");
            int i11 = 0;
            if (b10 != null) {
                int iY = y(b10.w(), 1.5d);
                if (i10 / iY <= 1) {
                    iY = i10 >> 1;
                }
                double dZ = z();
                int i12 = 0;
                while (i12 > -12 && Math.floor(dZ) < dZ) {
                    dZ *= 10.0d;
                    i12--;
                }
                while (true) {
                    double dPow = Math.pow(10.0d, i12);
                    double d11 = 1.0d * dPow;
                    if (O(d11) <= iY) {
                        d11 = 2.0d * dPow;
                        if (O(d11) <= iY) {
                            d10 = dPow * 5.0d;
                            if (O(d10) > iY) {
                                break;
                            } else {
                                i12++;
                            }
                        }
                    }
                    d10 = d11;
                    break;
                }
            } else {
                d10 = 0.0d;
            }
            if (d10 <= 0.0d) {
                return;
            }
            double dFloor = Math.floor(u() / d10) * d10;
            if (dFloor - d10 == dFloor) {
                return;
            }
            do {
                if (p().size() < 2147483639) {
                    p().add(Double.valueOf(dFloor));
                }
                dFloor -= d10;
                i11++;
                if (dFloor <= v()) {
                    return;
                }
            } while (i11 < 30);
        }
    }
}
