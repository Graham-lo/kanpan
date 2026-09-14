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
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public class B extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final Zj.a f95003l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public AbstractC7467h0 f95004m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public Paint[] f95005n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public Paint[] f95006o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public boolean f95007p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final Paint f95008q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final Paint f95009r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public final Paint f95010s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public final Paint f95011t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public y1 f95012u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public AbstractC2759w0 f95013v;

    public /* synthetic */ class a {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public static final /* synthetic */ int[] f95014a;

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
            f95014a = iArr;
        }
    }

    public B(C2732n c2732n, String str, Zj.a aVar) {
        super(c2732n, str);
        this.f95003l = aVar;
        this.f95005n = new Paint[0];
        this.f95006o = new Paint[0];
        this.f95007p = true;
        this.f95008q = new Paint();
        this.f95009r = new Paint();
        this.f95010s = new Paint();
        this.f95011t = new Paint();
    }

    public final Paint[] A() {
        return this.f95005n;
    }

    public final void B(boolean z10) {
        this.f95007p = z10;
    }

    public final void C(Paint[] paintArr) {
        this.f95006o = paintArr;
    }

    public final void D(Paint[] paintArr) {
        this.f95005n = paintArr;
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        AbstractC7467h0 abstractC7467h0 = this.f95004m;
        if (abstractC7467h0 == null) {
            return;
        }
        Long[] lArrY = abstractC7467h0.y();
        int iW = abstractC7467h0.w();
        for (int i10 = 0; i10 < iW; i10++) {
            double[] dArr = abstractC7467h0.v()[i10];
            if (abstractC7467h0.x().r()[i10].b()) {
                v(canvas, this.f95007p ? this.f95006o[i10] : this.f95005n[i10], dArr, lArrY);
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
        this.f95004m = abstractC7467h0;
        Paint paint = this.f95008q;
        paint.setAntiAlias(false);
        paint.setColor(aVar.r());
        Paint.Style style = Paint.Style.STROKE;
        paint.setStyle(style);
        paint.setStrokeWidth(2.0f);
        Paint paint2 = this.f95009r;
        paint2.setAntiAlias(false);
        paint2.setColor(aVar.r());
        Paint.Style style2 = Paint.Style.FILL;
        paint2.setStyle(style2);
        Paint paint3 = this.f95010s;
        paint3.setAntiAlias(false);
        paint3.setColor(aVar.m());
        paint3.setStyle(style);
        paint3.setStrokeWidth(2.0f);
        Paint paint4 = this.f95011t;
        paint4.setAntiAlias(false);
        paint4.setColor(aVar.m());
        paint4.setStyle(style2);
        C2741q c2741qB = i().b();
        this.f95012u = c2741qB.m(c());
        this.f95013v = c2741qB.l(b());
        this.f95007p = KLineManager.f142490O.a().q(9) == 0;
        int iW = abstractC7467h0.w();
        if (abstractC7467h0 instanceof U0) {
            Paint[] paintArr = new Paint[iW];
            for (int i10 = 0; i10 < iW; i10++) {
                Paint paintA = kk.c.a(false);
                paintA.setStyle(Paint.Style.FILL);
                paintA.setColor(nk.b.b((String) p162hb.e.c(aVar.w(), "#B57C26", "#E69D30")));
                Qf.H h10 = Qf.H.f17640a;
                paintArr[i10] = paintA;
            }
            this.f95006o = paintArr;
            Paint[] paintArr2 = new Paint[iW];
            for (int i11 = 0; i11 < iW; i11++) {
                Paint paintA2 = kk.c.a(false);
                paintA2.setStyle(Paint.Style.STROKE);
                paintA2.setColor(nk.b.b((String) p162hb.e.c(aVar.w(), "#B57C26", "#E69D30")));
                Qf.H h11 = Qf.H.f17640a;
                paintArr2[i11] = paintA2;
            }
            this.f95005n = paintArr2;
            return;
        }
        Paint[] paintArr3 = new Paint[iW];
        for (int i12 = 0; i12 < iW; i12++) {
            Paint paintA3 = kk.c.a(false);
            paintA3.setStyle(Paint.Style.FILL);
            paintA3.setColor(aVar.b(i12));
            Qf.H h12 = Qf.H.f17640a;
            paintArr3[i12] = paintA3;
        }
        this.f95006o = paintArr3;
        Paint[] paintArr4 = new Paint[iW];
        for (int i13 = 0; i13 < iW; i13++) {
            Paint paintA4 = kk.c.a(false);
            paintA4.setStyle(Paint.Style.STROKE);
            paintA4.setStrokeWidth(2.0f);
            paintA4.setColor(aVar.b(i13));
            Qf.H h13 = Qf.H.f17640a;
            paintArr4[i13] = paintA4;
        }
        this.f95005n = paintArr4;
    }

    /* JADX WARN: Code duplicated, block: B:57:0x0102  */
    /* JADX WARN: Code duplicated, block: B:59:0x0105  */
    /* JADX WARN: Code duplicated, block: B:61:0x0108  */
    /* JADX WARN: Code duplicated, block: B:63:0x010d  */
    /* JADX WARN: Code duplicated, block: B:64:0x011a  */
    /* JADX WARN: Code duplicated, block: B:67:0x0123  */
    /* JADX WARN: Code duplicated, block: B:68:0x0127  */
    /* JADX WARN: Code duplicated, block: B:70:0x012d  */
    /* JADX WARN: Code duplicated, block: B:71:0x013a  */
    /* JADX WARN: Code duplicated, block: B:74:0x0142  */
    /* JADX WARN: Code duplicated, block: B:79:0x011d A[SYNTHETIC] */
    /* JADX WARN: Code duplicated, block: B:81:0x0150 A[SYNTHETIC] */
    public final void v(Canvas canvas, Paint paint, double[] dArr, Long[] lArr) {
        AbstractC2759w0 abstractC2759w0;
        double dDoubleValue;
        Double dN0;
        double dDoubleValue2;
        Double dN1;
        float f10;
        double d10;
        Paint paint2;
        Paint paint3;
        int i10;
        int i11;
        Paint paint4;
        y1 y1Var = this.f95012u;
        if (y1Var == null || (abstractC2759w0 = this.f95013v) == null || dArr.length == 0) {
            return;
        }
        int iR = y1Var.r();
        int iY = y1Var.y();
        float fJ = y1Var.J();
        float fU = y1Var.u();
        int i12 = 2;
        float f11 = (2 * fU) / 3;
        int i13 = 1;
        if (lArr.length == 0) {
            iR = Math.min(iR, dArr.length - 1);
            iY = Math.min(iY, dArr.length);
        }
        float f12 = (fU / 6) - fJ;
        float f13 = f11 + f12;
        float fS = abstractC2759w0.S(0.0d);
        if (lArr.length == 0) {
            dDoubleValue = dArr[p292ng.i.f(iR - 1, 0)];
        } else {
            long jH = y1Var.H(p292ng.i.f(iR - 1, 0));
            dDoubleValue = (!AbstractC2801o.V(lArr, Long.valueOf(jH)) || (dN0 = AbstractC2801o.n0(dArr, AbstractC2801o.w0(lArr, Long.valueOf(jH)))) == null) ? Double.NaN : dN0.doubleValue();
        }
        float f14 = (float) dDoubleValue;
        float f15 = f13;
        float f16 = f12;
        while (iR < iY) {
            if (lArr.length == 0) {
                dDoubleValue2 = dArr[iR];
            } else {
                long jH2 = y1Var.H(iR);
                dDoubleValue2 = (!AbstractC2801o.V(lArr, Long.valueOf(jH2)) || (dN1 = AbstractC2801o.n0(dArr, AbstractC2801o.w0(lArr, Long.valueOf(jH2)))) == null) ? Double.NaN : dN1.doubleValue();
            }
            float fS2 = abstractC2759w0.S(dDoubleValue2);
            if (fS2 > fS) {
                f10 = fS;
            } else {
                f10 = fS2;
                fS2 = fS;
            }
            Zj.a aVar = this.f95003l;
            int[] iArr = a.f95014a;
            int i14 = iArr[aVar.ordinal()];
            if (i14 != i13) {
                if (i14 == i12) {
                    d10 = dDoubleValue2;
                    paint3 = paint;
                } else {
                    if (i14 != 3) {
                        throw new Qf.n();
                    }
                    d10 = dDoubleValue2;
                    paint2 = ((double) f14) < d10 ? this.f95008q : this.f95010s;
                }
                i10 = iArr[this.f95003l.ordinal()];
                if (i10 != 1) {
                    i11 = 2;
                    if (i10 != 2) {
                        paint4 = paint;
                    } else {
                        if (i10 == 3) {
                            throw new Qf.n();
                        }
                        if (f14 < d10) {
                            paint4 = (Paint) p162hb.e.c(this.f95007p, this.f95009r, this.f95008q);
                        } else {
                            paint4 = this.f95011t;
                        }
                    }
                } else {
                    i11 = 2;
                    if (d10 > 0.0d) {
                        paint4 = (Paint) p162hb.e.c(this.f95007p, this.f95009r, this.f95008q);
                    } else {
                        paint4 = this.f95011t;
                    }
                }
                if (!Double.isNaN(d10)) {
                    float f17 = f10;
                    canvas.drawLine(f16, f10, f15, f17, paint3);
                    nk.y.a(canvas, f16, fS2, f15, f17, paint4);
                }
                f16 += fU;
                f15 += fU;
                f14 = (float) d10;
                iR++;
                int i15 = i11;
                i13 = 1;
                i12 = i15;
            } else {
                d10 = dDoubleValue2;
                paint2 = d10 > 0.0d ? this.f95008q : this.f95010s;
            }
            paint3 = paint2;
            i10 = iArr[this.f95003l.ordinal()];
            if (i10 != 1) {
                i11 = 2;
                if (i10 != 2) {
                    paint4 = paint;
                } else {
                    if (i10 == 3) {
                        throw new Qf.n();
                    }
                    if (f14 < d10) {
                        paint4 = (Paint) p162hb.e.c(this.f95007p, this.f95009r, this.f95008q);
                    } else {
                        paint4 = this.f95011t;
                    }
                }
            } else {
                i11 = 2;
                if (d10 > 0.0d) {
                    paint4 = (Paint) p162hb.e.c(this.f95007p, this.f95009r, this.f95008q);
                } else {
                    paint4 = this.f95011t;
                }
            }
            if (!Double.isNaN(d10)) {
                float f18 = f10;
                canvas.drawLine(f16, f10, f15, f18, paint3);
                nk.y.a(canvas, f16, fS2, f15, f18, paint4);
            }
            f16 += fU;
            f15 += fU;
            f14 = (float) d10;
            iR++;
            int i16 = i11;
            i13 = 1;
            i12 = i16;
        }
    }

    public final boolean w() {
        return this.f95007p;
    }

    public final Zj.a x() {
        return this.f95003l;
    }

    public final AbstractC7467h0 y() {
        return this.f95004m;
    }

    public final Paint[] z() {
        return this.f95006o;
    }
}
