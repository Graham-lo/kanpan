package fk;

import Rj.AbstractC2744r0;
import Rj.AbstractC2755v;
import Rj.AbstractC2759w0;
import Rj.C2732n;
import Rj.C2741q;
import Rj.y1;
import Sf.AbstractC2801o;
import android.graphics.Canvas;
import android.graphics.Paint;
import gk.AbstractC7467h0;
import gk.U0;

/* JADX INFO: loaded from: classes7.dex */
public class F extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final Zj.a f95041l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public Paint[] f95042m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public AbstractC7467h0 f95043n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public Paint f95044o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public Paint f95045p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final Paint f95046q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public y1 f95047r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public AbstractC2759w0 f95048s;

    public /* synthetic */ class a {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public static final /* synthetic */ int[] f95049a;

        static {
            int[] iArr = new int[Zj.a.values().length];
            try {
                iArr[Zj.a.POS_NEG.ordinal()] = 1;
            } catch (NoSuchFieldError unused) {
            }
            try {
                iArr[Zj.a.DATA.ordinal()] = 2;
            } catch (NoSuchFieldError unused2) {
            }
            try {
                iArr[Zj.a.PRE.ordinal()] = 3;
            } catch (NoSuchFieldError unused3) {
            }
            f95049a = iArr;
        }
    }

    public F(C2732n c2732n, String str, Zj.a aVar) {
        super(c2732n, str);
        this.f95041l = aVar;
        this.f95042m = new Paint[0];
        this.f95044o = new Paint();
        this.f95045p = new Paint();
        this.f95046q = new Paint();
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        AbstractC7467h0 abstractC7467h0 = this.f95043n;
        if (abstractC7467h0 == null) {
            return;
        }
        Long[] lArrY = abstractC7467h0.y();
        int iW = abstractC7467h0.w();
        for (int i10 = 0; i10 < iW; i10++) {
            double[] dArr = abstractC7467h0.v()[i10];
            if (abstractC7467h0.x().r()[i10].b()) {
                v(canvas, this.f95042m[i10], dArr, lArrY);
            }
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
        AbstractC2755v abstractC2755vQ = q();
        AbstractC7467h0 abstractC7467h0 = abstractC2755vQ instanceof AbstractC7467h0 ? (AbstractC7467h0) abstractC2755vQ : null;
        if (abstractC7467h0 == null) {
            return;
        }
        this.f95043n = abstractC7467h0;
        sp.aicoin_kline.core.indicator.config.F fX = abstractC7467h0.x();
        Paint paint = this.f95046q;
        paint.setStyle(Paint.Style.FILL);
        paint.setStrokeWidth(2.0f);
        Paint paint2 = new Paint(this.f95046q);
        paint2.setColor(aVar.r());
        this.f95044o = paint2;
        Paint paint3 = new Paint(this.f95046q);
        paint3.setColor(aVar.m());
        this.f95045p = paint3;
        C2741q c2741qB = i().b();
        this.f95047r = c2741qB.m(c());
        this.f95048s = c2741qB.l(b());
        int iW = abstractC7467h0.w();
        int i10 = 0;
        if (abstractC7467h0 instanceof U0) {
            Paint[] paintArr = new Paint[iW];
            while (i10 < iW) {
                Paint paint4 = new Paint(this.f95046q);
                paint4.setColor(nk.b.b("#E79403"));
                Qf.H h10 = Qf.H.f17640a;
                paintArr[i10] = paint4;
                i10++;
            }
            this.f95042m = paintArr;
            return;
        }
        Paint[] paintArr2 = new Paint[iW];
        while (i10 < iW) {
            Paint paint5 = new Paint(this.f95046q);
            paint5.setColor(fX.k()[i10].a());
            Qf.H h11 = Qf.H.f17640a;
            paintArr2[i10] = paint5;
            i10++;
        }
        this.f95042m = paintArr2;
    }

    public final void v(Canvas canvas, Paint paint, double[] dArr, Long[] lArr) {
        AbstractC2759w0 abstractC2759w0;
        double dDoubleValue;
        Double dN0;
        float f10;
        float f11;
        float f12;
        Paint paint2;
        Paint paint3;
        y1 y1Var = this.f95047r;
        if (y1Var == null || (abstractC2759w0 = this.f95048s) == null || dArr.length == 0) {
            return;
        }
        int iR = y1Var.r();
        int iQ = y1Var.q();
        float fJ = y1Var.J();
        float fU = y1Var.u();
        float f13 = 2;
        float f14 = (fU * f13) / 3;
        int i10 = 1;
        if (lArr.length == 0) {
            iR = Math.min(iR, dArr.length - 1);
            iQ = Math.min(iQ, dArr.length);
        }
        float f15 = (fU / 6) - fJ;
        double d10 = 0.0d;
        float fS = abstractC2759w0.S(0.0d);
        float f16 = 0.0f;
        while (iR < iQ) {
            float f17 = (f14 / f13) + f15;
            double d11 = d10;
            if (lArr.length == 0) {
                dDoubleValue = dArr[iR];
            } else {
                long jH = y1Var.H(iR);
                dDoubleValue = (!AbstractC2801o.V(lArr, Long.valueOf(jH)) || (dN0 = AbstractC2801o.n0(dArr, AbstractC2801o.w0(lArr, Long.valueOf(jH)))) == null) ? Double.NaN : dN0.doubleValue();
            }
            float fS2 = abstractC2759w0.S(dDoubleValue);
            if (fS2 > fS) {
                f11 = fS2;
                f10 = fS;
            } else {
                f10 = fS2;
                f11 = fS;
            }
            int i11 = a.f95049a[this.f95041l.ordinal()];
            if (i11 != i10) {
                if (i11 == 2) {
                    f12 = f15;
                    paint3 = paint;
                } else {
                    if (i11 != 3) {
                        throw new Qf.n();
                    }
                    f12 = f15;
                    paint2 = ((double) f16) < dDoubleValue ? this.f95044o : this.f95045p;
                }
                canvas.drawLine(f17, f10, f17, f11, paint3);
                f15 = f12 + fU;
                f16 = (float) dDoubleValue;
                iR++;
                d10 = d11;
                i10 = 1;
            } else {
                f12 = f15;
                paint2 = dDoubleValue > d11 ? this.f95044o : this.f95045p;
            }
            paint3 = paint2;
            canvas.drawLine(f17, f10, f17, f11, paint3);
            f15 = f12 + fU;
            f16 = (float) dDoubleValue;
            iR++;
            d10 = d11;
            i10 = 1;
        }
    }

    public final AbstractC7467h0 w() {
        return this.f95043n;
    }

    public final Paint[] x() {
        return this.f95042m;
    }

    public final void y(Paint[] paintArr) {
        this.f95042m = paintArr;
    }
}
