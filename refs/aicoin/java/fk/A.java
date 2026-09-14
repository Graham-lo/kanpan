package fk;

import Rj.AbstractC2744r0;
import Rj.AbstractC2755v;
import Rj.AbstractC2759w0;
import Rj.C2732n;
import Rj.y1;
import Sf.AbstractC2801o;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import gk.C7465g0;

/* JADX INFO: loaded from: classes7.dex */
public class A extends AbstractC2744r0 {

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public double f94974A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public double f94975B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public float f94976C;

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public float f94977D;

    /* JADX INFO: renamed from: E, reason: collision with root package name */
    public double f94978E;

    /* JADX INFO: renamed from: F, reason: collision with root package name */
    public double f94979F;

    /* JADX INFO: renamed from: G, reason: collision with root package name */
    public float f94980G;

    /* JADX INFO: renamed from: H, reason: collision with root package name */
    public float f94981H;

    /* JADX INFO: renamed from: I, reason: collision with root package name */
    public boolean f94982I;

    /* JADX INFO: renamed from: J, reason: collision with root package name */
    public boolean f94983J;

    /* JADX INFO: renamed from: K, reason: collision with root package name */
    public int f94984K;

    /* JADX INFO: renamed from: L, reason: collision with root package name */
    public int f94985L;

    /* JADX INFO: renamed from: M, reason: collision with root package name */
    public final Paint f94986M;

    /* JADX INFO: renamed from: N, reason: collision with root package name */
    public final Paint f94987N;

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final ak.h f94988l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public Path[] f94989m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public Paint[] f94990n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public C7465g0 f94991o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public int f94992p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public int f94993q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public float f94994r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public float f94995s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public float f94996t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public float f94997u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public double f94998v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public double f94999w;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public float f95000x;

    /* JADX INFO: renamed from: y, reason: collision with root package name */
    public float f95001y;

    /* JADX INFO: renamed from: z, reason: collision with root package name */
    public double f95002z;

    public A(C2732n c2732n, String str, String str2) {
        super(c2732n, str);
        this.f94989m = new Path[0];
        this.f94990n = new Paint[0];
        this.f94982I = true;
        this.f94983J = true;
        this.f94984K = 858772146;
        this.f94985L = 854940504;
        new Path();
        Paint paint = new Paint();
        Paint.Style style = Paint.Style.FILL;
        paint.setStyle(style);
        paint.setAntiAlias(true);
        paint.setColor(854940504);
        this.f94986M = paint;
        Paint paint2 = new Paint();
        paint2.setStyle(style);
        paint2.setAntiAlias(true);
        paint2.setColor(858772146);
        this.f94987N = paint2;
        this.f94988l = new ak.h(c2732n.b(), this, str2);
    }

    /* JADX WARN: Code duplicated, block: B:48:0x014d  */
    /* JADX WARN: Code duplicated, block: B:50:0x0155  */
    /* JADX WARN: Code duplicated, block: B:52:0x01a6  */
    /* JADX WARN: Code duplicated, block: B:53:0x01a9  */
    /* JADX WARN: Code duplicated, block: B:56:0x01da  */
    /* JADX WARN: Code duplicated, block: B:57:0x01dd  */
    /* JADX WARN: Code duplicated, block: B:66:0x023f  */
    /* JADX WARN: Code duplicated, block: B:89:0x02b8 A[PHI: r22
      0x02b8: PHI (r22v2 int) = (r22v1 int), (r22v4 int), (r22v4 int) binds: [B:87:0x02b1, B:82:0x0296, B:84:0x02a4] A[DONT_GENERATE, DONT_INLINE]] */
    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        AbstractC2759w0 abstractC2759w0J;
        int i10;
        Paint paint;
        Paint paint2;
        AbstractC2759w0 abstractC2759w0J2;
        Long[] lArr;
        int i11;
        int i12;
        int i13;
        double dDoubleValue;
        int i14;
        int i15;
        int i16;
        Double dN0;
        A a10 = this;
        C7465g0 c7465g0 = a10.f94991o;
        if (c7465g0 == null) {
            return;
        }
        Long[] lArrY = c7465g0.y();
        double[] dArr = c7465g0.v()[3];
        double[] dArr2 = c7465g0.v()[4];
        y1 y1VarK = a10.f94988l.k();
        int i17 = 1;
        if (y1VarK != null && (abstractC2759w0J = a10.f94988l.j()) != null) {
            a10.f94992p = y1VarK.r();
            a10.f94993q = y1VarK.q() - 1;
            a10.f94994r = y1VarK.u();
            a10.f94995s = y1VarK.J();
            float fU = (y1VarK.u() / 2) - a10.f94995s;
            a10.f94996t = fU;
            a10.f94997u = fU + a10.f94994r;
            Double dN1 = AbstractC2801o.n0(dArr, a10.f94992p);
            a10.f94998v = dN1 != null ? dN1.doubleValue() : Double.NaN;
            Double dN2 = AbstractC2801o.n0(dArr2, a10.f94992p);
            a10.f94999w = dN2 != null ? dN2.doubleValue() : Double.NaN;
            if (!Double.isNaN(a10.f94998v) && !Double.isNaN(a10.f94999w)) {
                a10.f95000x = abstractC2759w0J.S(a10.f94998v);
                a10.f95001y = abstractC2759w0J.S(a10.f94999w);
                a10.f95002z = a10.f94998v - a10.f94999w;
                int i18 = a10.f94992p + 1;
                int i19 = a10.f94993q + 1;
                while (i18 < i19) {
                    Double dN3 = AbstractC2801o.n0(dArr, i18);
                    a10.f94974A = dN3 != null ? dN3.doubleValue() : Double.NaN;
                    Double dN4 = AbstractC2801o.n0(dArr2, i18);
                    a10.f94975B = dN4 != null ? dN4.doubleValue() : Double.NaN;
                    if (Double.isNaN(a10.f94974A) || Double.isNaN(a10.f94975B)) {
                        i10 = i17;
                        float f10 = a10.f94996t;
                        float f11 = a10.f94994r;
                        a10.f94996t = f10 + f11;
                        a10.f94997u += f11;
                        a10.f94998v = a10.f94974A;
                        a10.f94999w = a10.f94975B;
                        a10.f95002z = Double.NaN;
                    } else {
                        a10.f94976C = abstractC2759w0J.S(a10.f94974A);
                        a10.f94977D = abstractC2759w0J.S(a10.f94975B);
                        i10 = i17;
                        a10.f94978E = a10.f94974A - a10.f94975B;
                        Path path = new Path();
                        if (!Double.isNaN(a10.f95002z)) {
                            double d10 = a10.f95002z;
                            if (a10.f94978E * d10 >= 0.0d) {
                                Paint paint3 = d10 > 0.0d ? a10.f94987N : a10.f94986M;
                                int i20 = (a10.v(paint3.getColor()) ? 1 : 0) ^ i10;
                                path.moveTo(a10.f94996t, a10.f95000x);
                                float f12 = i20;
                                path.lineTo(a10.f94997u + f12, a10.f94976C);
                                path.lineTo(a10.f94997u + f12, a10.f94977D);
                                path.lineTo(a10.f94996t, a10.f95001y);
                                path.close();
                                canvas.drawPath(path, paint3);
                            } else if (!Double.isNaN(a10.f95002z)) {
                                double d11 = a10.f95002z;
                                double d12 = d11 / (d11 - a10.f94978E);
                                float f13 = a10.f94996t;
                                a10.f94979F = (((double) (a10.f94997u - f13)) * d12) + ((double) f13);
                                float f14 = a10.f95000x;
                                float f15 = (float) d12;
                                a10.f94980G = ((a10.f94976C - f14) * f15) + f14;
                                float f16 = a10.f95001y;
                                a10.f94981H = ((a10.f94977D - f16) * f15) + f16;
                                Path path2 = new Path();
                                path2.moveTo(a10.f94996t, a10.f95000x);
                                path2.lineTo((float) a10.f94979F, a10.f94980G);
                                path2.lineTo((float) a10.f94979F, a10.f94981H);
                                path2.lineTo(a10.f94996t, a10.f95001y);
                                path2.close();
                                if (a10.f95002z > 0.0d) {
                                    paint = a10.f94987N;
                                } else {
                                    paint = a10.f94986M;
                                }
                                canvas.drawPath(path2, paint);
                                Path path3 = new Path();
                                path3.moveTo((float) a10.f94979F, a10.f94980G);
                                path3.lineTo(a10.f94997u, a10.f94976C);
                                path3.lineTo(a10.f94997u, a10.f94977D);
                                path3.lineTo((float) a10.f94979F, a10.f94981H);
                                path3.close();
                                if (a10.f94978E > 0.0d) {
                                    paint2 = a10.f94987N;
                                } else {
                                    paint2 = a10.f94986M;
                                }
                                canvas.drawPath(path3, paint2);
                            }
                        } else if (!Double.isNaN(a10.f95002z)) {
                            double d13 = a10.f95002z;
                            double d14 = d13 / (d13 - a10.f94978E);
                            float f17 = a10.f94996t;
                            a10.f94979F = (((double) (a10.f94997u - f17)) * d14) + ((double) f17);
                            float f18 = a10.f95000x;
                            float f19 = (float) d14;
                            a10.f94980G = ((a10.f94976C - f18) * f19) + f18;
                            float f110 = a10.f95001y;
                            a10.f94981H = ((a10.f94977D - f110) * f19) + f110;
                            Path path4 = new Path();
                            path4.moveTo(a10.f94996t, a10.f95000x);
                            path4.lineTo((float) a10.f94979F, a10.f94980G);
                            path4.lineTo((float) a10.f94979F, a10.f94981H);
                            path4.lineTo(a10.f94996t, a10.f95001y);
                            path4.close();
                            if (a10.f95002z > 0.0d) {
                                paint = a10.f94987N;
                            } else {
                                paint = a10.f94986M;
                            }
                            canvas.drawPath(path4, paint);
                            Path path5 = new Path();
                            path5.moveTo((float) a10.f94979F, a10.f94980G);
                            path5.lineTo(a10.f94997u, a10.f94976C);
                            path5.lineTo(a10.f94997u, a10.f94977D);
                            path5.lineTo((float) a10.f94979F, a10.f94981H);
                            path5.close();
                            if (a10.f94978E > 0.0d) {
                                paint2 = a10.f94987N;
                            } else {
                                paint2 = a10.f94986M;
                            }
                            canvas.drawPath(path5, paint2);
                        }
                        float f20 = a10.f94997u;
                        a10.f94996t = f20;
                        a10.f94997u = f20 + a10.f94994r;
                        a10.f94998v = a10.f94974A;
                        a10.f94999w = a10.f94975B;
                        a10.f95000x = a10.f94976C;
                        a10.f95001y = a10.f94977D;
                        a10.f95002z = a10.f94978E;
                    }
                    i18++;
                    i17 = i10;
                    abstractC2759w0J = abstractC2759w0J;
                }
            }
        }
        int i21 = i17;
        int iW = c7465g0.w();
        int i22 = 0;
        while (i22 < iW) {
            double[] dArr3 = c7465g0.v()[i22];
            Paint paint4 = a10.f94990n[i22];
            Path path6 = a10.f94989m[i22];
            y1 y1VarK2 = a10.f94988l.k();
            if (y1VarK2 == null || (abstractC2759w0J2 = a10.f94988l.j()) == null) {
                lArr = lArrY;
                i11 = iW;
                i12 = i22;
            } else {
                int iR = y1VarK2.r();
                int iQ = y1VarK2.q();
                int i23 = lArrY.length == 0 ? i21 : 0;
                if (i23 == 0 || iR < dArr3.length) {
                    float fU2 = y1VarK2.u();
                    float fU3 = (y1VarK2.u() / 2) - y1VarK2.J();
                    path6.reset();
                    float f21 = 0.0f;
                    int i24 = iR;
                    float f22 = fU3;
                    boolean z10 = true;
                    float f23 = 0.0f;
                    while (i24 < iQ) {
                        if (i23 == 0) {
                            long jH = y1VarK2.H(i24);
                            i13 = iW;
                            if (!AbstractC2801o.V(lArrY, Long.valueOf(jH)) || (dN0 = AbstractC2801o.n0(dArr3, AbstractC2801o.w0(lArrY, Long.valueOf(jH)))) == null) {
                                dDoubleValue = Double.NaN;
                            } else {
                                dDoubleValue = dN0.doubleValue();
                            }
                        } else {
                            i13 = iW;
                            Double dN5 = AbstractC2801o.n0(dArr3, i24);
                            if (dN5 != null) {
                                dDoubleValue = dN5.doubleValue();
                            } else {
                                dDoubleValue = Double.NaN;
                            }
                        }
                        if (Double.isNaN(dDoubleValue)) {
                            f22 += fU2;
                            i14 = i22;
                            i15 = iQ;
                            i16 = i23;
                            z10 = true;
                        } else {
                            float fS = abstractC2759w0J2.S(dDoubleValue);
                            if (z10) {
                                path6.moveTo(f22, fS);
                                i14 = i22;
                                i15 = iQ;
                                i16 = i23;
                                z10 = false;
                            } else {
                                i14 = i22;
                                i15 = iQ;
                                i16 = i23;
                                float fFloatValue = ((Number) p162hb.e.c(o(), Float.valueOf(abstractC2759w0J2.S(abstractC2759w0J2.v())), Float.valueOf(abstractC2759w0J2.S(abstractC2759w0J2.u())))).floatValue();
                                float f24 = (f21 - fS) / (f23 - f22);
                                float f25 = (fFloatValue - (fS - (f24 * f22))) / f24;
                                if (f21 > fFloatValue) {
                                    path6.moveTo(f23, f21);
                                    if (fS < fFloatValue) {
                                        path6.lineTo(f25, fFloatValue);
                                    } else {
                                        path6.lineTo(f22, fS);
                                    }
                                } else if (f21 >= fFloatValue) {
                                    path6.moveTo(f23, f21);
                                    if (fS < fFloatValue) {
                                        path6.lineTo(f23, f21);
                                    } else {
                                        path6.lineTo(f22, fS);
                                    }
                                } else if (fS >= fFloatValue) {
                                    path6.moveTo(f25, fFloatValue);
                                    path6.lineTo(f22, fS);
                                }
                            }
                            f23 = f22;
                            f22 += fU2;
                            f21 = fS;
                        }
                        i24++;
                        lArrY = lArrY;
                        i22 = i14;
                        iW = i13;
                        iQ = i15;
                        i23 = i16;
                    }
                    lArr = lArrY;
                    i11 = iW;
                    i12 = i22;
                    canvas.drawPath(path6, paint4);
                } else {
                    lArr = lArrY;
                    i11 = iW;
                    i12 = i22;
                }
            }
            i22 = i12 + 1;
            c7465g0 = c7465g0;
            lArrY = lArr;
            iW = i11;
            i21 = 1;
            a10 = this;
        }
    }

    @Override // Rj.AbstractC2744r0
    public final ak.h j() {
        return this.f94988l;
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        if (aVar == null) {
            return;
        }
        AbstractC2755v abstractC2755vQ = q();
        C7465g0 c7465g0 = abstractC2755vQ instanceof C7465g0 ? (C7465g0) abstractC2755vQ : null;
        if (c7465g0 == null) {
            return;
        }
        sp.aicoin_kline.core.indicator.config.F fX = c7465g0.x();
        this.f94982I = fX.r()[5].b();
        this.f94983J = fX.r()[6].b();
        this.f94984K = fX.k()[5].a();
        this.f94985L = fX.k()[6].a();
        if (this.f94982I) {
            this.f94987N.setColor(this.f94984K);
        } else {
            this.f94987N.setColor(0);
        }
        if (this.f94983J) {
            this.f94986M.setColor(this.f94985L);
        } else {
            this.f94986M.setColor(0);
        }
        if (!fX.s()) {
            s(nk.n.d(fX.q()));
        }
        this.f94991o = c7465g0;
        int iW = c7465g0.w();
        Paint[] paintArr = new Paint[iW];
        for (int i10 = 0; i10 < iW; i10++) {
            Paint paint = new Paint();
            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeWidth(fX.k()[i10].b());
            paint.setAntiAlias(true);
            paint.setColor(fX.k()[i10].a());
            Qf.H h10 = Qf.H.f17640a;
            paintArr[i10] = paint;
        }
        this.f94990n = paintArr;
        Path[] pathArr = new Path[iW];
        for (int i11 = 0; i11 < iW; i11++) {
            pathArr[i11] = new Path();
        }
        this.f94989m = pathArr;
    }

    public final boolean v(int i10) {
        return Color.alpha(i10) < 255;
    }
}
