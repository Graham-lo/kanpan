package fk;

import Rj.AbstractC2744r0;
import Rj.AbstractC2755v;
import Rj.AbstractC2759w0;
import Rj.C2732n;
import Rj.C2741q;
import Rj.y1;
import android.graphics.Canvas;
import android.graphics.Paint;
import gk.AbstractC7467h0;
import gk.C7490t0;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class M extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final Paint f95093l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Paint f95094m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final Paint f95095n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final Paint f95096o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final Paint f95097p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final Paint f95098q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public y1 f95099r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public AbstractC2759w0 f95100s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public AbstractC7467h0 f95101t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public final boolean f95102u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public final boolean f95103v;

    public M(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f95102u = true;
        this.f95103v = true;
        Paint paint = new Paint();
        this.f95093l = paint;
        Paint.Style style = Paint.Style.STROKE;
        paint.setStyle(style);
        Paint paint2 = new Paint();
        this.f95094m = paint2;
        Paint.Style style2 = Paint.Style.FILL;
        paint2.setStyle(style2);
        Paint paint3 = new Paint();
        this.f95095n = paint3;
        paint3.setStyle(style);
        Paint paint4 = new Paint();
        this.f95096o = paint4;
        paint4.setStyle(style2);
        Paint paint5 = new Paint();
        this.f95097p = paint5;
        paint5.setStyle(style);
        paint5.setAntiAlias(true);
        paint5.setStrokeWidth(2.0f);
        Paint paint6 = new Paint();
        this.f95098q = paint6;
        paint6.setStyle(style);
        paint6.setAntiAlias(true);
        paint6.setStrokeWidth(2.0f);
        if (KLineManager.f142490O.a().f0() == 1) {
            paint3.setStrokeWidth(2.0f);
            paint.setStrokeWidth(2.0f);
        }
    }

    /* JADX WARN: Code duplicated, block: B:60:0x0160  */
    /* JADX WARN: Code duplicated, block: B:74:0x0190  */
    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        AbstractC2759w0 abstractC2759w0;
        AbstractC7467h0 abstractC7467h0;
        double d10;
        float f10;
        float f11;
        float f12;
        y1 y1Var = this.f95099r;
        if (y1Var == null || (abstractC2759w0 = this.f95100s) == null || (abstractC7467h0 = this.f95101t) == null) {
            return;
        }
        double d11 = 0.0d;
        if (abstractC2759w0.z() == 0.0d) {
            return;
        }
        double[][] dArrV = ((C7490t0) abstractC7467h0).v();
        if (dArrV.length == 0) {
            return;
        }
        float fU = y1Var.u();
        float f13 = 2;
        float f14 = (fU * f13) / 3;
        int iR = y1Var.r();
        int iQ = y1Var.q();
        float fJ = y1Var.J();
        float f15 = (fU / 6) - fJ;
        float fS = abstractC2759w0.S(0.0d);
        float f16 = (fU / f13) - fJ;
        double[] dArr = dArrV[0];
        int i10 = 1;
        double[] dArr2 = dArrV[1];
        double[] dArr3 = dArrV[2];
        float f17 = f16;
        float f18 = f14 + f15;
        int i11 = iR;
        float f19 = f15;
        float f20 = -1.0f;
        float f21 = -1.0f;
        float f22 = -1.0f;
        while (i11 < iQ) {
            if (i11 >= dArr3.length || Double.isNaN(dArr3[i11])) {
                d10 = d11;
                f10 = f18;
            } else {
                d10 = d11;
                double d12 = dArr3[i11];
                if (d12 >= d10) {
                    float fS2 = abstractC2759w0.S(d12);
                    if (Math.abs(fS - fS2) < 2.0f) {
                        float f23 = fS - i10;
                        f10 = f18;
                        canvas.drawLine(f19, f23, f10, f23, this.f95093l);
                    } else if (i11 == 0 || dArr3[i11] >= dArr3[i11 - 1]) {
                        double[] dArr4 = dArr2;
                        f11 = f19;
                        float f24 = i10;
                        nk.y.a(canvas, f11, fS2, f18 - f24, fS - f24, this.f95093l);
                        dArr2 = dArr4;
                        f10 = f18;
                    } else {
                        double[] dArr5 = dArr2;
                        float f25 = fS;
                        f11 = f19;
                        nk.y.a(canvas, f11, fS2, f18, f25, this.f95094m);
                        dArr2 = dArr5;
                        f10 = f18;
                        fS = f25;
                    }
                } else {
                    int i12 = i10;
                    double[] dArr6 = dArr2;
                    f11 = f19;
                    float fS3 = abstractC2759w0.S(d12);
                    if (Math.abs(fS3 - fS) < 2.0f) {
                        dArr2 = dArr6;
                        canvas.drawLine(f11, fS, f18, fS, this.f95095n);
                    } else {
                        dArr2 = dArr6;
                        if (i11 == 0 || dArr3[i11] >= dArr3[i11 - 1]) {
                            f10 = f18;
                            float f26 = i12;
                            nk.y.a(canvas, f11, fS, f10 - f26, fS3 - f26, this.f95095n);
                        } else {
                            nk.y.a(canvas, f11, fS, f18, fS3, this.f95096o);
                        }
                    }
                    f10 = f18;
                }
                if (i11 < dArr.length || Double.isNaN(dArr[i11])) {
                    f12 = f20;
                    f21 = f21;
                } else {
                    float fS4 = abstractC2759w0.S(dArr[i11]);
                    if (i11 <= iR || !this.f95102u || f21 == -1.0f) {
                        f12 = f20;
                    } else {
                        f12 = f20;
                        canvas.drawLine(f12, f21, f17, fS4, this.f95097p);
                    }
                    f21 = fS4;
                }
                if (i11 < dArr2.length || Double.isNaN(dArr2[i11])) {
                    f22 = f22;
                } else {
                    float fS5 = abstractC2759w0.S(dArr2[i11]);
                    if (i11 > iR && this.f95103v && f22 != -1.0f) {
                        canvas.drawLine(f12, f22, f17, fS5, this.f95098q);
                    }
                    f22 = fS5;
                }
                f19 = f11 + fU;
                f18 = f10 + fU;
                i11++;
                dArr2 = dArr2;
                f20 = f17;
                d11 = d10;
                i10 = 1;
                f17 += fU;
            }
            f11 = f19;
            if (i11 < dArr.length) {
                f12 = f20;
                f21 = f21;
            } else {
                f12 = f20;
                f21 = f21;
            }
            if (i11 < dArr2.length) {
                f22 = f22;
            } else {
                f22 = f22;
            }
            f19 = f11 + fU;
            f18 = f10 + fU;
            i11++;
            dArr2 = dArr2;
            f20 = f17;
            d11 = d10;
            i10 = 1;
            f17 += fU;
        }
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        if (aVar == null) {
            return;
        }
        this.f95093l.setColor(aVar.r());
        this.f95094m.setColor(aVar.r());
        this.f95095n.setColor(aVar.m());
        this.f95096o.setColor(aVar.m());
        C2741q c2741qB = i().b();
        c2741qB.e(b());
        this.f95099r = c2741qB.m(c());
        this.f95100s = c2741qB.l(b());
        AbstractC2755v abstractC2755vG = c2741qB.g(d());
        AbstractC7467h0 abstractC7467h0 = abstractC2755vG instanceof AbstractC7467h0 ? (AbstractC7467h0) abstractC2755vG : null;
        if (abstractC7467h0 != null) {
            this.f95101t = abstractC7467h0;
            AbstractC2755v abstractC2755vQ = q();
            AbstractC7467h0 abstractC7467h1 = abstractC2755vQ instanceof AbstractC7467h0 ? (AbstractC7467h0) abstractC2755vQ : null;
            if (abstractC7467h1 == null) {
                return;
            }
            sp.aicoin_kline.core.indicator.config.F fX = abstractC7467h1.x();
            this.f95097p.setColor(fX.k()[0].a());
            this.f95097p.setStrokeWidth(fX.k()[0].b());
            this.f95098q.setColor(fX.k()[1].a());
            this.f95098q.setStrokeWidth(fX.k()[1].b());
        }
    }
}
