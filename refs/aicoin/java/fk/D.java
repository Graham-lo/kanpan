package fk;

import Rj.AbstractC2744r0;
import Rj.AbstractC2755v;
import Rj.AbstractC2759w0;
import Rj.C2732n;
import Rj.y1;
import Sf.AbstractC2801o;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import gk.AbstractC7467h0;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public class D extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final ak.h f95030l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public Path[] f95031m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public Paint[] f95032n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public AbstractC7467h0 f95033o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public boolean f95034p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public boolean f95035q;

    public D(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f95031m = new Path[0];
        this.f95032n = new Paint[0];
        this.f95030l = new ak.h(c2732n.b(), this, null, 4, null);
    }

    public D(C2732n c2732n, String str, String str2) {
        super(c2732n, str);
        this.f95031m = new Path[0];
        this.f95032n = new Paint[0];
        this.f95030l = new ak.h(c2732n.b(), this, str2);
    }

    /* JADX WARN: Code duplicated, block: B:33:0x00a2 A[PHI: r20
      0x00a2: PHI (r20v2 gk.h0) = (r20v1 gk.h0), (r20v4 gk.h0), (r20v4 gk.h0) binds: [B:31:0x009b, B:25:0x007e, B:27:0x008c] A[DONT_GENERATE, DONT_INLINE]] */
    /* JADX WARN: Code duplicated, block: B:9:0x0029  */
    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        AbstractC2759w0 abstractC2759w0J;
        AbstractC7467h0 abstractC7467h0;
        Long[] lArr;
        int i10;
        AbstractC7467h0 abstractC7467h1;
        double dDoubleValue;
        int i11;
        double[] dArr;
        int i12;
        boolean z10;
        Double dN0;
        D d10 = this;
        AbstractC7467h0 abstractC7467h2 = d10.f95033o;
        if (abstractC7467h2 == null) {
            return;
        }
        Long[] lArrY = abstractC7467h2.y();
        int iW = abstractC7467h2.w();
        int i13 = 0;
        while (i13 < iW) {
            double[] dArr2 = abstractC7467h2.v()[i13];
            Paint paint = d10.f95032n[i13];
            Path path = d10.f95031m[i13];
            y1 y1VarK = d10.f95030l.k();
            if (y1VarK == null || (abstractC2759w0J = d10.f95030l.j()) == null) {
                abstractC7467h0 = abstractC7467h2;
                lArr = lArrY;
                i10 = i13;
            } else {
                int iR = y1VarK.r();
                int iQ = y1VarK.q();
                boolean z11 = lArrY.length == 0;
                if (!z11 || iR < dArr2.length) {
                    float fU = y1VarK.u();
                    float fU2 = (y1VarK.u() / 2) - y1VarK.J();
                    path.reset();
                    float f10 = 0.0f;
                    int i14 = iR;
                    float f11 = fU2;
                    boolean z12 = true;
                    float f12 = 0.0f;
                    while (i14 < iQ) {
                        if (z11) {
                            abstractC7467h1 = abstractC7467h2;
                            Double dN1 = AbstractC2801o.n0(dArr2, i14);
                            if (dN1 != null) {
                                dDoubleValue = dN1.doubleValue();
                            } else {
                                dDoubleValue = Double.NaN;
                            }
                        } else {
                            long jH = y1VarK.H(i14);
                            abstractC7467h1 = abstractC7467h2;
                            if (!AbstractC2801o.V(lArrY, Long.valueOf(jH)) || (dN0 = AbstractC2801o.n0(dArr2, AbstractC2801o.w0(lArrY, Long.valueOf(jH)))) == null) {
                                dDoubleValue = Double.NaN;
                            } else {
                                dDoubleValue = dN0.doubleValue();
                            }
                        }
                        double d11 = dDoubleValue;
                        if (Double.isNaN(d11)) {
                            f11 += fU;
                            i11 = i13;
                            dArr = dArr2;
                            i12 = iQ;
                            z10 = z11;
                            z12 = true;
                        } else {
                            float fS = abstractC2759w0J.S(d11);
                            if (z12) {
                                path.moveTo(f11, fS);
                                i11 = i13;
                                dArr = dArr2;
                                i12 = iQ;
                                z10 = z11;
                                z12 = false;
                            } else {
                                i11 = i13;
                                dArr = dArr2;
                                i12 = iQ;
                                z10 = z11;
                                float fFloatValue = ((Number) p162hb.e.c(o(), Float.valueOf(abstractC2759w0J.S(abstractC2759w0J.v())), Float.valueOf(abstractC2759w0J.S(abstractC2759w0J.u())))).floatValue();
                                float f13 = (f10 - fS) / (f12 - f11);
                                float f14 = (fFloatValue - (fS - (f13 * f11))) / f13;
                                if (f10 > fFloatValue) {
                                    path.moveTo(f12, f10);
                                    if (fS < fFloatValue) {
                                        path.lineTo(f14, fFloatValue);
                                    } else {
                                        path.lineTo(f11, fS);
                                    }
                                } else if (f10 >= fFloatValue) {
                                    path.moveTo(f12, f10);
                                    if (fS < fFloatValue) {
                                        path.lineTo(f12, f10);
                                    } else {
                                        path.lineTo(f11, fS);
                                    }
                                } else if (fS >= fFloatValue) {
                                    path.moveTo(f14, fFloatValue);
                                    path.lineTo(f11, fS);
                                }
                            }
                            f12 = f11;
                            f10 = fS;
                            f11 += fU;
                        }
                        i14++;
                        iQ = i12;
                        lArrY = lArrY;
                        i13 = i11;
                        abstractC7467h2 = abstractC7467h1;
                        dArr2 = dArr;
                        z11 = z10;
                    }
                    abstractC7467h0 = abstractC7467h2;
                    lArr = lArrY;
                    i10 = i13;
                    canvas.drawPath(path, paint);
                } else {
                    abstractC7467h0 = abstractC7467h2;
                    lArr = lArrY;
                    i10 = i13;
                }
            }
            i13 = i10 + 1;
            d10 = this;
            lArrY = lArr;
            abstractC7467h2 = abstractC7467h0;
        }
    }

    @Override // Rj.AbstractC2744r0
    public final ak.h j() {
        return this.f95030l;
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
        AbstractC7467h0 abstractC7467h0 = abstractC2755vQ instanceof AbstractC7467h0 ? (AbstractC7467h0) abstractC2755vQ : null;
        if (abstractC7467h0 == null) {
            return;
        }
        sp.aicoin_kline.core.indicator.config.F fX = abstractC7467h0.x();
        if (k() != null) {
            if (!o() && !this.f95035q) {
                s(nk.n.f(19));
            }
        } else if (!fX.s()) {
            s(nk.n.d(fX.q()));
        } else if (!o() && !this.f95035q) {
            s(nk.n.f(19));
        }
        if (this.f95035q) {
            s(true);
        }
        this.f95033o = abstractC7467h0;
        int i10 = 0;
        if (this.f95034p) {
            Paint paint = new Paint(1);
            Paint.Style style = Paint.Style.STROKE;
            paint.setStyle(style);
            paint.setStrokeWidth(2.0f);
            KLineManager.a aVar2 = KLineManager.f142490O;
            paint.setColor(aVar.d(aVar2.a().V() ? ".main_red.color" : ".main_green.color"));
            Qf.H h10 = Qf.H.f17640a;
            Paint paint2 = new Paint(1);
            paint2.setStyle(style);
            paint2.setStrokeWidth(2.0f);
            paint2.setColor(aVar.d(aVar2.a().V() ? ".main_green.color" : ".main_red.color"));
            this.f95032n = new Paint[]{paint, paint2};
            Path[] pathArr = new Path[2];
            while (i10 < 2) {
                pathArr[i10] = new Path();
                i10++;
            }
            this.f95031m = pathArr;
            return;
        }
        int iW = abstractC7467h0.w();
        Paint[] paintArr = new Paint[iW];
        for (int i11 = 0; i11 < iW; i11++) {
            Paint paint3 = new Paint();
            paint3.setStyle(Paint.Style.STROKE);
            paint3.setStrokeWidth(fX.k()[i11].b());
            paint3.setAntiAlias(true);
            paint3.setColor(fX.k()[i11].a());
            Qf.H h11 = Qf.H.f17640a;
            paintArr[i11] = paint3;
        }
        this.f95032n = paintArr;
        Path[] pathArr2 = new Path[iW];
        while (i10 < iW) {
            pathArr2[i10] = new Path();
            i10++;
        }
        this.f95031m = pathArr2;
    }

    public final void v(boolean z10) {
        this.f95035q = z10;
    }

    public final void w(boolean z10) {
        this.f95034p = z10;
    }
}
