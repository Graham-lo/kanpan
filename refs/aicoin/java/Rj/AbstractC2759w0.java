package Rj;

import Qf.InterfaceC2632j;
import java.util.ArrayList;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.chart.Chart;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: Rj.w0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public abstract class AbstractC2759w0 extends AbstractC2721j0 {

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public static final a f19571C = new a(null);

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public boolean f19572A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public final InterfaceC2632j f19573B;

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public C2732n f19574g;

    /* JADX INFO: renamed from: h, reason: collision with root package name */
    public boolean f19575h;

    /* JADX INFO: renamed from: i, reason: collision with root package name */
    public double f19576i;

    /* JADX INFO: renamed from: j, reason: collision with root package name */
    public int f19577j;

    /* JADX INFO: renamed from: k, reason: collision with root package name */
    public int f19578k;

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public boolean f19579l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public boolean f19580m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public int f19581n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public double f19582o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public double f19583p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public double f19584q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public double f19585r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public double f19586s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public double f19587t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public double f19588u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public double f19589v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public boolean f19590w;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public int f19591x;

    /* JADX INFO: renamed from: y, reason: collision with root package name */
    public int f19592y;

    /* JADX INFO: renamed from: z, reason: collision with root package name */
    public ArrayList f19593z;

    /* JADX INFO: renamed from: Rj.w0$a */
    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }

        public final double a(double d10, double d11) {
            if (Double.isInfinite(d10) || Double.isNaN(d10) || d10 <= 0.0d || Math.abs(d10 - 1.0d) <= 0.02d) {
                return 0.5d;
            }
            double d12 = 1.0d / (2.0d * d10);
            Qf.p pVar = d10 <= 1.0d ? new Qf.p(Double.valueOf(d12 - 3.0d), Double.valueOf((1.0d - d12) + 3.0d)) : new Qf.p(Double.valueOf(d12 - 0.75d), Double.valueOf((1.0d - d12) + 0.75d));
            double dDoubleValue = ((Number) pVar.a()).doubleValue();
            double dDoubleValue2 = ((Number) pVar.b()).doubleValue();
            return p292ng.i.n(d11, Math.min(dDoubleValue, dDoubleValue2), Math.max(dDoubleValue, dDoubleValue2));
        }
    }

    public AbstractC2759w0(C2732n c2732n, String str) {
        super(str);
        this.f19574g = c2732n;
        this.f19579l = true;
        this.f19586s = 1.0d;
        this.f19587t = 0.5d;
        this.f19589v = 0.5d;
        this.f19593z = new ArrayList();
        this.f19572A = true;
        this.f19573B = Qf.k.b(new C2753u0(this));
    }

    public static final Qf.H h(AbstractC2759w0 abstractC2759w0, double d10, double d11) {
        abstractC2759w0.f19582o = d10;
        abstractC2759w0.f19583p = d11;
        abstractC2759w0.f19575h = true;
        abstractC2759w0.E();
        abstractC2759w0.V();
        abstractC2759w0.U(abstractC2759w0.q());
        return Qf.H.f17640a;
    }

    public static final C2764y0 i(AbstractC2759w0 abstractC2759w0) {
        return new C2764y0(abstractC2759w0.f19574g, new C2756v0(abstractC2759w0));
    }

    public final int A() {
        return this.f19581n;
    }

    public final double B() {
        return this.f19586s;
    }

    public final boolean C() {
        return this.f19580m;
    }

    public final boolean D(float f10) {
        double d10;
        double d11;
        if (!k()) {
            return false;
        }
        ((C2764y0) this.f19573B.getValue()).c();
        this.f19590w = false;
        double d12 = this.f19585r;
        double d13 = this.f19584q;
        double d14 = d12 - d13;
        if (d14 <= 0.0d) {
            return false;
        }
        if (this.f19580m) {
            d10 = -f10;
            d11 = this.f19576i;
        } else {
            d10 = f10;
            d11 = this.f19576i;
        }
        this.f19587t = f19571C.a(this.f19586s, ((((this.f19582o + this.f19583p) / ((double) 2)) + (d10 / d11)) - d13) / d14);
        Qf.p pVarG = g(this.f19584q, this.f19585r);
        double dDoubleValue = ((Number) pVarG.a()).doubleValue();
        double dDoubleValue2 = ((Number) pVarG.b()).doubleValue();
        this.f19582o = dDoubleValue;
        this.f19583p = dDoubleValue2;
        this.f19575h = true;
        E();
        V();
        U(q());
        return true;
    }

    public void E() {
    }

    public final boolean F() {
        Chart chartA;
        if (this.f19585r <= this.f19584q) {
            return false;
        }
        ((C2764y0) this.f19573B.getValue()).c();
        this.f19590w = false;
        this.f19586s = 1.0d;
        this.f19587t = 0.5d;
        if (AbstractC7609s.f(e().a(1), "main") && (chartA = this.f19574g.a()) != null) {
            chartA.F(false);
        }
        double d10 = this.f19584q;
        double d11 = this.f19585r;
        this.f19582o = d10;
        this.f19583p = d11;
        this.f19575h = true;
        E();
        V();
        U(q());
        return true;
    }

    public final void G(double d10) {
        this.f19576i = d10;
    }

    public final void H(boolean z10) {
        this.f19579l = z10;
    }

    public final void I(int i10) {
        this.f19592y = i10;
    }

    public final void J(int i10) {
        this.f19591x = i10;
    }

    public final void K(int i10, int i11) {
        int i12 = i10 + this.f19591x;
        int i13 = i11 - this.f19592y;
        if (this.f19577j != i12 || this.f19578k != i13 || this.f19575h || (this instanceof C2742q0)) {
            this.f19575h = true;
            if (i12 >= i13) {
                this.f19582o = this.f19583p;
                return;
            }
            this.f19577j = i12;
            this.f19578k = i13;
            V();
            U(q());
        }
    }

    public final void L(double d10, double d11) {
        boolean z10 = this.f19584q == d10 && this.f19585r == d11;
        this.f19584q = d10;
        this.f19585r = d11;
        Qf.p pVarG = g(d10, d11);
        double dDoubleValue = ((Number) pVarG.a()).doubleValue();
        double dDoubleValue2 = ((Number) pVarG.b()).doubleValue();
        if (z10 && this.f19582o == dDoubleValue && this.f19583p == dDoubleValue2) {
            return;
        }
        this.f19575h = true;
        double d12 = this.f19582o;
        double d13 = this.f19583p;
        boolean z11 = d12 >= d13;
        if ((d12 != 0.0d || d13 != 0.0d) && this.f19572A && !z11) {
            y1 y1VarM = this.f19574g.b().m(c());
            if (y1VarM == null) {
                return;
            }
            ((C2764y0) this.f19573B.getValue()).b(this.f19582o, this.f19583p, dDoubleValue, dDoubleValue2, y1VarM.F(), y1VarM.n());
            return;
        }
        this.f19582o = dDoubleValue;
        this.f19583p = dDoubleValue2;
        this.f19575h = true;
        E();
        V();
        U(q());
    }

    public final void M(boolean z10) {
        this.f19580m = z10;
    }

    public final void N(int i10) {
        this.f19581n = i10;
    }

    public int O(double d10) {
        return (int) ((d10 * this.f19576i) + 1.5d);
    }

    public final float P(double d10) {
        int i10;
        if (d10 >= this.f19583p) {
            i10 = this.f19580m ? this.f19578k : this.f19577j;
        } else {
            if (d10 > this.f19582o) {
                return S(d10);
            }
            i10 = this.f19580m ? this.f19577j : this.f19578k;
        }
        return i10;
    }

    public float Q(double d10, boolean z10) {
        if (z10) {
            double d11 = this.f19576i;
            if (d11 <= 0.0d) {
                return this.f19577j;
            }
            return (float) (((d10 - this.f19582o) * d11) + ((double) this.f19577j));
        }
        double d12 = this.f19576i;
        if (d12 <= 0.0d) {
            return this.f19577j;
        }
        return (float) (((this.f19583p - d10) * d12) + ((double) this.f19577j));
    }

    public double R(float f10) {
        if (!this.f19580m) {
            return this.f19583p - (((double) (f10 - this.f19577j)) / this.f19576i);
        }
        return (((double) (f10 - this.f19577j)) / this.f19576i) + this.f19582o;
    }

    public float S(double d10) {
        if (this.f19580m) {
            double d11 = this.f19576i;
            if (d11 <= 0.0d) {
                return this.f19577j;
            }
            return (float) (((d10 - this.f19582o) * d11) + ((double) this.f19577j));
        }
        double d12 = this.f19576i;
        if (d12 <= 0.0d) {
            return this.f19577j;
        }
        return (float) (((this.f19583p - d10) * d12) + ((double) this.f19577j));
    }

    /* JADX WARN: Code duplicated, block: B:59:0x015d  */
    public void T() {
        double dMin;
        double dMax;
        Qf.p pVar;
        C2741q c2741qB;
        y1 y1VarM;
        C2765z c2765zH;
        int iD;
        int iF;
        int iK;
        double d10;
        double d11;
        double dMin2;
        double dMax2;
        C2741q c2741qB2 = this.f19574g.b();
        AbstractC2755v abstractC2755vG = c2741qB2.g(d() + ".m");
        double d12 = -1.7976931348623157E308d;
        if (abstractC2755vG != null) {
            dMin = Math.min(Double.MAX_VALUE, abstractC2755vG.m());
            dMax = Math.max(-1.7976931348623157E308d, abstractC2755vG.j());
        } else {
            dMin = Double.MAX_VALUE;
            dMax = -1.7976931348623157E308d;
        }
        if (!AbstractC7609s.f("ds0.indic2", d())) {
            AbstractC2755v abstractC2755vG2 = c2741qB2.g(d() + ".a");
            if (abstractC2755vG2 != null) {
                dMin = Math.min(dMin, abstractC2755vG2.m());
                dMax = Math.max(dMax, abstractC2755vG2.j());
            }
        }
        if (!AbstractC7609s.f(e().a(1), "main") || !C2760w1.f19594a.j() || (y1VarM = (c2741qB = this.f19574g.b()).m(c())) == null || ((KLineManager.f142490O.a().q(14) == 0 && y1VarM.u() < 5.0f) || (c2765zH = c2741qB.h(c())) == null || c2765zH.D() <= 0)) {
            pVar = null;
        } else {
            Sj.a aVarC = c2765zH.C();
            if (!aVarC.isEmpty() && (iF = p292ng.i.f(y1VarM.r(), 0)) <= (iK = p292ng.i.k(y1VarM.y(), (iD = c2765zH.D() - 1)))) {
                if (iF <= iK) {
                    dMin2 = Double.MAX_VALUE;
                    d10 = Double.MAX_VALUE;
                    dMax2 = -1.7976931348623157E308d;
                    while (true) {
                        d11 = d12;
                        Sj.b bVarD = (Sj.b) Sf.z.r0(aVarC, iF);
                        if (bVarD != null) {
                            if (iF == iD) {
                                bVarD = nk.c.f134195a.d(bVarD);
                            }
                            Sj.b bVar = bVarD;
                            if (!Double.isNaN(bVarD.c())) {
                                dMin2 = Math.min(dMin2, bVar.c());
                            }
                            if (!Double.isNaN(bVar.b())) {
                                dMax2 = Math.max(dMax2, bVar.b());
                            }
                        }
                        if (iF == iK) {
                            break;
                        }
                        iF++;
                        d12 = d11;
                    }
                } else {
                    d10 = Double.MAX_VALUE;
                    d11 = -1.7976931348623157E308d;
                    dMin2 = Double.MAX_VALUE;
                    dMax2 = -1.7976931348623157E308d;
                }
                if (dMin2 == d10 || dMax2 == d11) {
                    pVar = null;
                } else {
                    pVar = new Qf.p(Double.valueOf(dMin2), Double.valueOf(dMax2));
                }
            } else {
                pVar = null;
            }
        }
        if (pVar != null) {
            dMin = Math.min(dMin, ((Number) pVar.c()).doubleValue());
            dMax = Math.max(dMax, ((Number) pVar.d()).doubleValue());
        }
        L(dMin, dMax);
    }

    public abstract void U(int i10);

    public void V() {
        double d10;
        double d11;
        double dZ;
        int i10 = this.f19578k;
        int i11 = this.f19577j;
        if (i10 < i11 || this.f19583p <= this.f19582o) {
            if (this.f19579l && i10 >= i11 && this.f19583p == this.f19582o) {
                d11 = i10 - i11;
                dZ = z();
            } else {
                d10 = 0.0d;
            }
            this.f19576i = d10;
        }
        d11 = i10 - i11;
        dZ = z();
        d10 = d11 / dZ;
        this.f19576i = d10;
    }

    public final void W(double d10) {
        Chart chartA;
        if (this.f19585r > this.f19584q) {
            double dMin = Math.min(16.0d, Math.max(0.03d, d10));
            if (Math.abs(dMin - 1.0d) <= 0.02d) {
                dMin = 1.0d;
            }
            if (this.f19586s != dMin || this.f19590w) {
                this.f19586s = dMin;
                if (dMin == 1.0d) {
                    this.f19587t = 0.5d;
                }
                if (AbstractC7609s.f(e().a(1), "main") && this.f19586s != 1.0d && (chartA = this.f19574g.a()) != null) {
                    chartA.F(true);
                }
                Qf.p pVarG = g(this.f19584q, this.f19585r);
                double dDoubleValue = ((Number) pVarG.a()).doubleValue();
                double dDoubleValue2 = ((Number) pVarG.b()).doubleValue();
                this.f19582o = dDoubleValue;
                this.f19583p = dDoubleValue2;
                this.f19575h = true;
                E();
                V();
                U(q());
            }
        }
    }

    public final Qf.p g(double d10, double d11) {
        if (d11 <= d10) {
            return new Qf.p(Double.valueOf(d10), Double.valueOf(d11));
        }
        double d12 = this.f19586s;
        if (d12 == 1.0d) {
            return new Qf.p(Double.valueOf(d10), Double.valueOf(d11));
        }
        double d13 = d11 - d10;
        double d14 = d13 / d12;
        if (!this.f19590w) {
            double dA = f19571C.a(d12, this.f19587t);
            if (dA != this.f19587t) {
                this.f19587t = dA;
            }
            double d15 = (d13 * dA) + d10;
            double d16 = d14 / ((double) 2);
            return new Qf.p(Double.valueOf(d15 - d16), Double.valueOf(d15 + d16));
        }
        double d17 = this.f19588u;
        double d18 = this.f19589v;
        double d19 = d17 - (d14 * d18);
        double d20 = ((((double) 1) - d18) * d14) + d17;
        if (d13 <= 0.0d) {
            this.f19587t = 0.5d;
        } else {
            this.f19587t = f19571C.a(d12, (((d19 + d20) / ((double) 2)) - d10) / d13);
        }
        return new Qf.p(Double.valueOf(d19), Double.valueOf(d20));
    }

    public final boolean j(float f10) {
        if (this.f19578k <= this.f19577j || this.f19576i <= 0.0d || this.f19585r <= this.f19584q) {
            return false;
        }
        ((C2764y0) this.f19573B.getValue()).c();
        this.f19590w = true;
        this.f19588u = (this.f19582o + this.f19583p) / ((double) 2);
        this.f19589v = 0.5d;
        return true;
    }

    public final boolean k() {
        return this.f19585r > this.f19584q && this.f19578k > this.f19577j && this.f19576i > 0.0d && this.f19586s != 1.0d;
    }

    public final void l() {
        this.f19575h = false;
    }

    public final boolean m(double d10) {
        return d10 <= this.f19583p && this.f19582o <= d10;
    }

    public final void n() {
        this.f19590w = false;
    }

    public final C2732n o() {
        return this.f19574g;
    }

    public final ArrayList p() {
        return this.f19593z;
    }

    public final int q() {
        return Math.max(0, this.f19578k - this.f19577j);
    }

    public final int r() {
        return this.f19578k;
    }

    public final double s() {
        return this.f19576i;
    }

    public final int t() {
        return this.f19577j;
    }

    public final double u() {
        return this.f19583p;
    }

    public final double v() {
        return this.f19582o;
    }

    public final int w() {
        return this.f19592y;
    }

    public final int x() {
        return this.f19591x;
    }

    public final int y(int i10, double d10) {
        return p292ng.i.f(p208jg.c.c(((double) i10) * d10 * (this.f19586s != 1.0d ? 1.8d : 1.0d)), 1);
    }

    public final double z() {
        double d10 = this.f19583p;
        double d11 = d10 - this.f19582o;
        return (this.f19579l && d11 == 0.0d) ? Math.abs(d10) : d11;
    }
}
