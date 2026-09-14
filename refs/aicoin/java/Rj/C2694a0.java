package Rj;

import kotlin.jvm.internal.DefaultConstructorMarker;

/* JADX INFO: renamed from: Rj.a0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2694a0 extends AbstractC2759w0 {

    /* JADX INFO: renamed from: F, reason: collision with root package name */
    public static final a f19325F = new a(null);

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public double f19326D;

    /* JADX INFO: renamed from: E, reason: collision with root package name */
    public double f19327E;

    /* JADX INFO: renamed from: Rj.a0$a */
    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public C2694a0(C2732n c2732n, String str) {
        super(c2732n, str);
    }

    @Override // Rj.AbstractC2759w0
    public void E() {
        double dLog;
        double dU = u();
        double dLog2 = -24.0d;
        if (dU == 0.0d) {
            dLog = -24.0d;
        } else {
            dLog = dU < 0.0d ? (-48.0d) - Math.log(-dU) : Math.log(dU);
        }
        this.f19326D = dLog;
        double dV = v();
        if (dV != 0.0d) {
            dLog2 = dV < 0.0d ? (-48.0d) - Math.log(-dV) : Math.log(dV);
        }
        this.f19327E = dLog2;
    }

    @Override // Rj.AbstractC2759w0
    public int O(double d10) {
        return (int) ((s() * d10) + 1.5d);
    }

    @Override // Rj.AbstractC2759w0
    public double R(float f10) {
        if (C()) {
            f10 = nk.A.f(f10, r(), t());
        }
        double dT = this.f19326D - (((double) (f10 - t())) / s());
        return dT < -24.0d ? -Math.pow(2.718281828459045d, (-48.0d) - dT) : Math.pow(2.718281828459045d, dT);
    }

    @Override // Rj.AbstractC2759w0
    public float S(double d10) {
        double dLog;
        boolean zC = C();
        if (s() <= 0.0d) {
            return zC ? r() : t();
        }
        double dT = t();
        double d11 = this.f19326D;
        if (d10 == 0.0d) {
            dLog = -24.0d;
        } else {
            dLog = d10 < 0.0d ? (-48.0d) - Math.log(-d10) : Math.log(d10);
        }
        double dS = (s() * (d11 - dLog)) + dT;
        return zC ? nk.A.f((float) dS, t(), r()) : (float) dS;
    }

    @Override // Rj.AbstractC2759w0
    public void U(int i10) {
        double d10;
        p().clear();
        if (z() <= 0.0d || i10 < 1) {
            return;
        }
        double d11 = this.f19326D - this.f19327E;
        Double dValueOf = Double.valueOf(d11);
        if (d11 == 0.0d) {
            dValueOf = null;
        }
        double dDoubleValue = dValueOf != null ? dValueOf.doubleValue() : this.f19326D;
        int iO = O(dDoubleValue / 8.0d);
        int i11 = 0;
        int i12 = 0;
        while (i12 > -10 && Math.floor(dDoubleValue) < dDoubleValue) {
            dDoubleValue *= 10.0d;
            i12--;
        }
        while (true) {
            double dPow = Math.pow(10.0d, i12);
            d10 = 1.0d * dPow;
            if (O(d10) >= iO) {
                break;
            }
            d10 = 2.0d * dPow;
            if (O(d10) >= iO) {
                break;
            }
            d10 = 5.0d * dPow;
            if (O(d10) >= iO) {
                break;
            } else {
                i12++;
            }
        }
        if (d10 <= 0.0d) {
            return;
        }
        double dFloor = Math.floor(this.f19326D / d10) * d10;
        if (dFloor - d10 == dFloor) {
            return;
        }
        do {
            if (p().size() < 2147483639) {
                p().add(Double.valueOf(dFloor < -24.0d ? -Math.pow(2.718281828459045d, (-48.0d) - dFloor) : Math.pow(2.718281828459045d, dFloor)));
            }
            dFloor -= d10;
            i11++;
            if (dFloor <= this.f19327E) {
                return;
            }
        } while (i11 < 30);
    }

    @Override // Rj.AbstractC2759w0
    public void V() {
        if (r() >= t() && u() > v()) {
            G(((double) (r() - t())) / (this.f19326D - this.f19327E));
        } else if (r() < t() || u() != v()) {
            G(0.0d);
        } else {
            G(((double) (r() - t())) / Math.abs(this.f19326D));
        }
    }
}
