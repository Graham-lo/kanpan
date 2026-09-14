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

/* JADX INFO: loaded from: classes7.dex */
public final class N extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final Paint f95104l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Paint f95105m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final Paint f95106n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final Paint f95107o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public y1 f95108p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public AbstractC2759w0 f95109q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public AbstractC2755v f95110r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public final boolean f95111s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public final boolean f95112t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public final boolean f95113u;

    public N(C2732n c2732n, String str) {
        super(c2732n, str);
        Paint paint = new Paint();
        this.f95104l = paint;
        Paint paint2 = new Paint();
        this.f95105m = paint2;
        this.f95111s = true;
        this.f95112t = true;
        this.f95113u = true;
        Paint.Style style = Paint.Style.FILL;
        paint.setStyle(style);
        paint2.setStyle(style);
        paint.setStrokeWidth(2.0f);
        paint2.setStrokeWidth(2.0f);
        Paint paint3 = new Paint();
        this.f95106n = paint3;
        Paint.Style style2 = Paint.Style.STROKE;
        paint3.setStyle(style2);
        paint3.setAntiAlias(true);
        paint3.setStrokeWidth(2.0f);
        Paint paint4 = new Paint();
        this.f95107o = paint4;
        paint4.setStyle(style2);
        paint4.setAntiAlias(true);
        paint4.setStrokeWidth(2.0f);
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        AbstractC2759w0 abstractC2759w0;
        AbstractC2755v abstractC2755v;
        double d10;
        float f10;
        double[] dArr;
        float f11;
        double[] dArr2;
        y1 y1Var = this.f95108p;
        if (y1Var == null || (abstractC2759w0 = this.f95109q) == null || (abstractC2755v = this.f95110r) == null) {
            return;
        }
        double d11 = 0.0d;
        if (abstractC2759w0.z() == 0.0d) {
            return;
        }
        double[][] dArrV = ((C7490t0) abstractC2755v).v();
        if (dArrV.length == 0) {
            return;
        }
        float fU = y1Var.u();
        int iR = y1Var.r();
        int iQ = y1Var.q();
        float fJ = y1Var.J();
        float f12 = (fU / 10) - fJ;
        float fS = abstractC2759w0.S(0.0d);
        float f13 = (fU / 2) - fJ;
        double[] dArr3 = dArrV[0];
        double[] dArr4 = dArrV[1];
        double[] dArr5 = dArrV[2];
        int i10 = iR;
        float f14 = -1.0f;
        float f15 = -1.0f;
        float f16 = -1.0f;
        while (true) {
            float f17 = f13;
            if (i10 >= iQ) {
                return;
            }
            if (i10 >= dArr5.length || Double.isNaN(dArr5[i10])) {
                d10 = d11;
                f10 = f12;
                i10 = i10;
                dArr = dArr4;
            } else {
                d10 = d11;
                double d12 = dArr5[i10];
                if (d12 >= d10) {
                    dArr2 = dArr4;
                    float fS2 = abstractC2759w0.S(d12);
                    Paint paint = this.f95104l;
                    if (this.f95113u) {
                        dArr = dArr2;
                        canvas.drawLine(f17, fS2, f17, fS, paint);
                    }
                    f10 = f12;
                } else {
                    dArr2 = dArr4;
                    float fS3 = abstractC2759w0.S(d12);
                    Paint paint2 = this.f95105m;
                    if (this.f95113u) {
                        i10 = i10;
                        float f18 = fS;
                        dArr = dArr2;
                        f10 = f12;
                        canvas.drawLine(f10, f18, f12, fS3, paint2);
                        fS = f18;
                    }
                }
                dArr = dArr2;
                f10 = f12;
            }
            if (i10 >= dArr3.length || Double.isNaN(dArr3[i10])) {
                f11 = f15;
            } else {
                float fS4 = abstractC2759w0.S(dArr3[i10]);
                if (i10 > iR && this.f95111s && f15 != -1.0f) {
                    canvas.drawLine(f14, f15, f17, fS4, this.f95106n);
                }
                f11 = fS4;
            }
            if (i10 >= dArr.length || Double.isNaN(dArr[i10])) {
                f16 = f16;
            } else {
                float fS5 = abstractC2759w0.S(dArr[i10]);
                if (i10 > iR && this.f95112t && f16 != -1.0f) {
                    canvas.drawLine(f14, f16, f17, fS5, this.f95107o);
                }
                f16 = fS5;
            }
            float f19 = f10 + fU;
            f13 = f17 + fU;
            dArr4 = dArr;
            f15 = f11;
            f12 = f19;
            f14 = f17;
            i10++;
            d11 = d10;
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
        this.f95104l.setColor(aVar.r());
        this.f95105m.setColor(aVar.m());
        AbstractC2755v abstractC2755vQ = q();
        AbstractC7467h0 abstractC7467h0 = abstractC2755vQ instanceof AbstractC7467h0 ? (AbstractC7467h0) abstractC2755vQ : null;
        if (abstractC7467h0 == null) {
            return;
        }
        sp.aicoin_kline.core.indicator.config.F fX = abstractC7467h0.x();
        this.f95106n.setColor(fX.k()[0].a());
        this.f95107o.setColor(fX.k()[0].a());
        C2741q c2741qB = i().b();
        c2741qB.e(b());
        this.f95108p = c2741qB.m(c());
        this.f95109q = c2741qB.l(b());
        this.f95110r = c2741qB.g(d());
    }
}
