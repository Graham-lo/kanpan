package Rj;

import Qf.InterfaceC2632j;
import java.util.ArrayList;

/* JADX INFO: renamed from: Rj.q0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2742q0 extends AbstractC2759w0 {

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public final InterfaceC2632j f19516D;

    /* JADX INFO: renamed from: E, reason: collision with root package name */
    public ArrayList f19517E;

    /* JADX INFO: renamed from: F, reason: collision with root package name */
    public double f19518F;

    public C2742q0(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f19516D = Qf.k.b(new C2739p0(c2732n));
        this.f19517E = new ArrayList();
        this.f19518F = 1.0d;
    }

    public static final y1 X(C2732n c2732n) {
        return c2732n.b().m("ds0");
    }

    @Override // Rj.AbstractC2759w0
    public int O(double d10) {
        double d11 = this.f19518F;
        if (d11 == 0.0d) {
            return 1;
        }
        return (int) (d10 * d11);
    }

    @Override // Rj.AbstractC2759w0
    public double R(float f10) {
        y1 y1VarZ = Z();
        if (y1VarZ == null) {
            return 0.0d;
        }
        double dR = super.R(f10);
        double dS = y1VarZ.s();
        return ((dR - dS) * ((double) 100)) / dS;
    }

    /* JADX WARN: Code duplicated, block: B:25:0x00a8  */
    /* JADX WARN: Code duplicated, block: B:26:0x00b1  */
    /* JADX WARN: Code duplicated, block: B:28:0x00c0  */
    /* JADX WARN: Code duplicated, block: B:37:0x010e  */
    /* JADX WARN: Code duplicated, block: B:39:0x012d  */
    /* JADX WARN: Code duplicated, block: B:41:0x014c  */
    /* JADX WARN: Code duplicated, block: B:44:0x0158 A[LOOP:2: B:35:0x00de->B:44:0x0158, LOOP_END] */
    /* JADX WARN: Code duplicated, block: B:48:0x0162  */
    /* JADX WARN: Code duplicated, block: B:51:0x016d  */
    /* JADX WARN: Code duplicated, block: B:54:0x017c  */
    /* JADX WARN: Code duplicated, block: B:56:0x018e  */
    /* JADX WARN: Code duplicated, block: B:68:0x015d A[EDGE_INSN: B:68:0x015d->B:45:0x015d BREAK  A[LOOP:2: B:35:0x00de->B:44:0x0158], SYNTHETIC] */
    /* JADX WARN: Code duplicated, block: B:69:0x015d A[EDGE_INSN: B:69:0x015d->B:45:0x015d BREAK  A[LOOP:2: B:35:0x00de->B:44:0x0158], SYNTHETIC] */
    /* JADX WARN: Code duplicated, block: B:70:0x015d A[EDGE_INSN: B:70:0x015d->B:45:0x015d BREAK  A[LOOP:2: B:35:0x00de->B:44:0x0158], SYNTHETIC] */
    /* JADX WARN: Code duplicated, block: B:71:0x0152 A[SYNTHETIC] */
    /* JADX WARN: Code duplicated, block: B:75:? A[RETURN, SYNTHETIC] */
    /* JADX WARN: Code duplicated, block: B:76:? A[RETURN, SYNTHETIC] */
    /* JADX WARN: Instruction removed from duplicated block: B:37:0x010e, please report this as an issue */
    /* JADX WARN: Instruction removed from duplicated block: B:39:0x012d, please report this as an issue */
    @Override // Rj.AbstractC2759w0
    public void U(int i10) {
        double d10;
        double dR;
        double dAbs;
        B0 b10;
        double d11;
        int iY;
        double dZ;
        int i11;
        double d12;
        double d13;
        double dPow;
        double d14;
        nk.p pVar;
        double d15;
        double d16;
        int i12;
        int i13;
        double d17;
        y1 y1VarZ = Z();
        if (y1VarZ == null) {
            return;
        }
        double dS = y1VarZ.s();
        p().clear();
        this.f19517E.clear();
        if (z() <= 0.0d || i10 < 1) {
            return;
        }
        double d18 = 100;
        double dU = ((u() - dS) / Math.abs(dS)) * d18;
        double dV = ((v() - dS) / Math.abs(dS)) * d18;
        if (r() < t() || dU <= dV) {
            if (r() < t() || dU != dV) {
                d10 = 0.0d;
            } else {
                dR = r() - t();
                dAbs = Math.abs(dU);
            }
            this.f19518F = d10;
            b10 = (B0) o().b().a(d() + "Range.m");
            if (b10 == null) {
                d11 = 0.0d;
                iY = y(b10.w(), 1.5d);
                if (i10 / iY <= 1) {
                    iY = i10 >> 1;
                }
                dZ = z();
                i11 = 0;
                while (true) {
                    d12 = d11;
                    d13 = 10.0d;
                    if (i11 <= -3 || Math.floor(dZ) >= dZ) {
                        break;
                    }
                    dZ *= 10.0d;
                    i11--;
                    d11 = d12;
                }
                while (true) {
                    dPow = Math.pow(d13, i11);
                    d14 = dPow * 1.0d;
                    pVar = nk.p.f134232a;
                    d15 = dS;
                    pVar.a("klineChart", "==> find best interval loop[" + i11 + "]: " + d14);
                    if (O(d14) <= iY) {
                        break;
                    }
                    d14 = 2.0d * dPow;
                    pVar.a("klineChart", "==> find best interval loop[" + i11 + "]: " + d14);
                    if (O(d14) <= iY) {
                        break;
                    }
                    d14 = 5.0d * dPow;
                    pVar.a("klineChart", "==> find best interval loop[" + i11 + "]: " + d14);
                    if (O(d14) > iY) {
                        break;
                    }
                    i11++;
                    if (i11 > 50) {
                        pVar.b("klineChart", "PercentageRange 进入了无限循环！！");
                        break;
                    } else {
                        dS = d15;
                        d13 = 10.0d;
                    }
                }
            } else {
                d15 = dS;
                d14 = 0.0d;
                d12 = 0.0d;
            }
            if (d14 <= d12) {
                return;
            }
            d16 = (dU - (dU % d14)) + d14;
            if (d16 - d14 == d16) {
                return;
            }
            i12 = 0;
            while (true) {
                if (p().size() < 2147483639) {
                    d17 = ((d15 * d16) / d18) + d15;
                    if (S(d17) >= t()) {
                        this.f19517E.add(Double.valueOf(d16));
                        p().add(Double.valueOf(d17));
                    }
                }
                d16 -= d14;
                i13 = i12 + 1;
                if (d16 >= dV || i13 >= 30) {
                    return;
                } else {
                    i12 = i13;
                }
            }
        } else {
            dR = r() - t();
            dAbs = dU - dV;
        }
        d10 = dR / dAbs;
        this.f19518F = d10;
        b10 = (B0) o().b().a(d() + "Range.m");
        if (b10 == null) {
            d11 = 0.0d;
            iY = y(b10.w(), 1.5d);
            if (i10 / iY <= 1) {
                iY = i10 >> 1;
            }
            dZ = z();
            i11 = 0;
            while (true) {
                d12 = d11;
                d13 = 10.0d;
                if (i11 <= -3) {
                    break;
                }
                break;
                break;
                dZ *= 10.0d;
                i11--;
                d11 = d12;
            }
            while (true) {
                dPow = Math.pow(d13, i11);
                d14 = dPow * 1.0d;
                pVar = nk.p.f134232a;
                d15 = dS;
                pVar.a("klineChart", "==> find best interval loop[" + i11 + "]: " + d14);
                if (O(d14) <= iY) {
                    break;
                    break;
                }
                d14 = 2.0d * dPow;
                pVar.a("klineChart", "==> find best interval loop[" + i11 + "]: " + d14);
                if (O(d14) <= iY) {
                    break;
                    break;
                }
                d14 = 5.0d * dPow;
                pVar.a("klineChart", "==> find best interval loop[" + i11 + "]: " + d14);
                if (O(d14) > iY) {
                    break;
                    break;
                }
                i11++;
                if (i11 > 50) {
                    pVar.b("klineChart", "PercentageRange 进入了无限循环！！");
                    break;
                } else {
                    dS = d15;
                    d13 = 10.0d;
                }
            }
        } else {
            d15 = dS;
            d14 = 0.0d;
            d12 = 0.0d;
        }
        if (d14 <= d12) {
            return;
        }
        d16 = (dU - (dU % d14)) + d14;
        if (d16 - d14 == d16) {
            return;
        }
        i12 = 0;
        while (true) {
            if (p().size() < 2147483639) {
                d17 = ((d15 * d16) / d18) + d15;
                if (S(d17) >= t()) {
                    this.f19517E.add(Double.valueOf(d16));
                    p().add(Double.valueOf(d17));
                }
            }
            d16 -= d14;
            i13 = i12 + 1;
            if (d16 >= dV) {
                return;
            } else {
                return;
            }
            i12 = i13;
        }
    }

    public final ArrayList Y() {
        return this.f19517E;
    }

    public final y1 Z() {
        return (y1) this.f19516D.getValue();
    }
}
