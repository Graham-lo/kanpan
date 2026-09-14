package Rj;

import Sf.AbstractC2801o;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import gk.AbstractC7467h0;
import kotlin.jvm.internal.DefaultConstructorMarker;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class K0 extends AbstractC2744r0 {

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public static final a f19163x = new a(null);

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final Paint f19164l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public Paint f19165m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public Paint f19166n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public Paint f19167o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public Paint f19168p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public Paint f19169q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public Paint f19170r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public final Paint f19171s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public y1 f19172t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public AbstractC2759w0 f19173u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public AbstractC7467h0 f19174v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public boolean f19175w;

    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public K0(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f19164l = new Paint();
        this.f19165m = new Paint();
        this.f19166n = new Paint();
        this.f19167o = new Paint();
        this.f19168p = new Paint();
        this.f19169q = new Paint();
        this.f19170r = new Paint();
        this.f19171s = new Paint();
    }

    public static void v(Canvas canvas, float f10, float f11, float f12, float f13, float f14, Paint paint) {
        Path path = new Path();
        path.moveTo(f10, f11 + f14);
        float f15 = f12 / 4;
        float f16 = (f13 / 5) + f11 + f14;
        path.lineTo(f10 - f15, f16);
        float f17 = f12 / 2;
        float f18 = f10 - f17;
        path.lineTo(f18, f16);
        float f19 = f11 + f13 + f14;
        path.lineTo(f18, f19);
        float f20 = f17 + f10;
        path.lineTo(f20, f19);
        path.lineTo(f20, f16);
        path.lineTo(f10 + f15, f16);
        path.close();
        canvas.drawPath(path, paint);
    }

    public static void w(Canvas canvas, float f10, float f11, float f12, float f13, Paint paint) {
        Path path = new Path();
        path.moveTo(f10, f11 + f13);
        float f14 = f12 / 2;
        float f15 = f11 + f14 + f13;
        path.lineTo(f10 - f14, f15);
        path.lineTo(f10, f11 + f12 + f13);
        path.lineTo(f14 + f10, f15);
        path.close();
        canvas.drawPath(path, paint);
        Path path2 = new Path();
        float f16 = 0.35f * f12;
        float f17 = f10 - f16;
        float f18 = (0.146f * f12) + f11 + f13;
        path2.moveTo(f17, f18);
        float f19 = (f12 * 0.854f) + f11 + f13;
        path2.lineTo(f17, f19);
        float f20 = f10 + f16;
        path2.lineTo(f20, f19);
        path2.lineTo(f20, f18);
        path2.close();
        canvas.drawPath(path2, paint);
    }

    public static void x(Canvas canvas, float f10, float f11, float f12, float f13, float f14, Paint paint) {
        Path path = new Path();
        path.moveTo(f10, f11 - f14);
        float f15 = f12 / 4;
        float f16 = (f11 - (f13 / 5)) - f14;
        path.lineTo(f10 - f15, f16);
        float f17 = f12 / 2;
        float f18 = f10 - f17;
        path.lineTo(f18, f16);
        float f19 = (f11 - f13) - f14;
        path.lineTo(f18, f19);
        float f20 = f17 + f10;
        path.lineTo(f20, f19);
        path.lineTo(f20, f16);
        path.lineTo(f10 + f15, f16);
        path.close();
        canvas.drawPath(path, paint);
    }

    public static void y(Canvas canvas, float f10, float f11, float f12, float f13, Paint paint) {
        Path path = new Path();
        path.moveTo(f10, f11 - f13);
        float f14 = f12 / 2;
        float f15 = (f11 - f14) - f13;
        path.lineTo(f10 - f14, f15);
        path.lineTo(f10, (f11 - f12) - f13);
        path.lineTo(f14 + f10, f15);
        path.close();
        canvas.drawPath(path, paint);
        Path path2 = new Path();
        float f16 = 0.35f * f12;
        float f17 = f10 - f16;
        float f18 = (f11 - (0.146f * f12)) - f13;
        path2.moveTo(f17, f18);
        float f19 = (f11 - (f12 * 0.854f)) - f13;
        path2.lineTo(f17, f19);
        float f20 = f10 + f16;
        path2.lineTo(f20, f19);
        path2.lineTo(f20, f18);
        path2.close();
        canvas.drawPath(path2, paint);
    }

    /* JADX WARN: Code duplicated, block: B:130:0x02b7  */
    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        AbstractC2759w0 abstractC2759w0;
        Sj.a aVarC;
        double[] dArr;
        double[] dArr2;
        int i10;
        int i11;
        float f10;
        float f11;
        Canvas canvas2;
        int i12;
        float f12;
        float f13;
        float f14;
        int i13;
        y1 y1Var = this.f19172t;
        if (y1Var == null || (abstractC2759w0 = this.f19173u) == null) {
            return;
        }
        AbstractC7467h0 abstractC7467h0 = this.f19174v;
        gk.P0 p10 = abstractC7467h0 instanceof gk.P0 ? (gk.P0) abstractC7467h0 : null;
        if (p10 == null || abstractC2759w0.z() == 0.0d) {
            return;
        }
        boolean zF = nk.n.f(19);
        C2765z c2765zD = p10.h().d();
        if (c2765zD == null || (aVarC = c2765zD.C()) == null || (dArr = (double[]) AbstractC2801o.r0(p10.D(), 0)) == null || (dArr2 = (double[]) AbstractC2801o.r0(p10.D(), 1)) == null) {
            return;
        }
        if (dArr.length == 0 && dArr2.length == 0) {
            return;
        }
        float fU = y1Var.u();
        int iF = p292ng.i.f(y1Var.r(), 0);
        int iK = p292ng.i.k(y1Var.q(), aVarC.size());
        if (iF >= iK) {
            return;
        }
        float fJ = y1Var.J();
        float fA = Xj.a.a(11.0f);
        float fA2 = Xj.a.a(9.0f);
        float f15 = 2;
        float fA3 = Xj.a.a(y1Var.z()) / f15;
        float fA4 = Xj.a.a(13.0f);
        float fU2 = (y1Var.u() / f15) - fJ;
        while (iF < iK) {
            Sj.b bVar = (Sj.b) Sf.z.r0(aVarC, iF);
            if (bVar == null) {
                return;
            }
            double[] dArr3 = dArr2;
            double dB = bVar.b();
            double[] dArr4 = dArr;
            double dC = bVar.c();
            y1 y1Var2 = y1Var;
            this.f19171s.setTextSize(Xj.a.d(9));
            Double dN0 = AbstractC2801o.n0(dArr4, iF);
            Double dN1 = AbstractC2801o.n0(dArr3, iF);
            if (dN0 == null || Double.isNaN(dN0.doubleValue())) {
                i10 = iF;
                i11 = iK;
            } else {
                i10 = iF;
                i11 = iK;
                int i14 = (int) dArr4[i10];
                float fS = abstractC2759w0.S(dB);
                if (i14 != 0) {
                    if (i14 == 9 || i14 == 13) {
                        i14 = i14;
                        i11 = i11;
                        f15 = f15;
                        f13 = fS;
                        fU2 = fU2;
                        if (zF) {
                            f14 = fA3;
                            canvas = canvas;
                            w(canvas, fU2, f13, fA4, f14, this.f19166n);
                        } else {
                            f14 = fA3;
                            canvas = canvas;
                            y(canvas, fU2, f13, fA4, f14, this.f19166n);
                        }
                        fA3 = f14;
                    } else if (y1Var2.z() <= 1.5d || this.f19175w) {
                        i14 = i14;
                        i11 = i11;
                        f15 = f15;
                        f13 = fS;
                        fU2 = fU2;
                        canvas = canvas;
                    } else if (zF) {
                        f15 = f15;
                        canvas = canvas;
                        f13 = fS;
                        fU2 = fU2;
                        v(canvas, fU2, f13, fA2, fA, fA3, this.f19165m);
                    } else {
                        f15 = f15;
                        f13 = fS;
                        fU2 = fU2;
                        canvas = canvas;
                        x(canvas, fU2, f13, fA2, fA, fA3, this.f19165m);
                    }
                    float f16 = zF ? (((fA4 * 0.854f) + f13) + fA3) - (this.f19170r.getFontMetrics().descent / f15) : ((f13 - (fA4 * 0.146f)) - fA3) - (this.f19169q.getFontMetrics().descent / f15);
                    fA3 = fA3;
                    if (y1Var2.z() <= 1.5d || this.f19175w) {
                        i13 = 9;
                        if (i14 == 9 || i14 == 13) {
                        }
                    } else {
                        i13 = 9;
                    }
                    this.f19169q.setTextSize(Xj.a.d(i13));
                    canvas.drawText(String.valueOf(i14), fU2, f16, (Paint) p162hb.e.c(i14 == i13 || i14 == 13, this.f19171s, this.f19169q));
                } else {
                    i11 = i11;
                }
                if (dN1 != null || Double.isNaN(dN1.doubleValue())) {
                    f10 = fA4;
                    fA3 = fA3;
                } else {
                    int i15 = (int) dArr3[i10];
                    float fS2 = abstractC2759w0.S(dC);
                    if (i15 != 0) {
                        if (i15 == 9 || i15 == 13) {
                            float f17 = fA3;
                            if (zF) {
                                f11 = f17;
                                canvas2 = canvas;
                                f10 = fA4;
                                y(canvas2, fU2, fS2, f10, f11, this.f19168p);
                            } else {
                                f11 = f17;
                                f10 = fA4;
                                canvas2 = canvas;
                                w(canvas2, fU2, fS2, f10, f11, this.f19168p);
                            }
                            fA3 = f11;
                        } else if (y1Var2.z() <= 1.5d || this.f19175w) {
                            canvas2 = canvas;
                            f10 = fA4;
                            fA3 = fA3;
                        } else {
                            if (zF) {
                                f12 = fA;
                                fA3 = fA3;
                                x(canvas, fU2, fS2, fA2, f12, fA3, this.f19167o);
                                canvas2 = canvas;
                            } else {
                                f12 = fA;
                                fA3 = fA3;
                                canvas2 = canvas;
                                v(canvas2, fU2, fS2, fA2, f12, fA3, this.f19167o);
                            }
                            fA = f12;
                            f10 = fA4;
                        }
                        float f18 = zF ? ((fS2 - (f10 * 0.146f)) - fA3) - (this.f19169q.getFontMetrics().descent / f15) : (((f10 * 0.854f) + fS2) + fA3) - (this.f19170r.getFontMetrics().descent / f15);
                        if (y1Var2.z() <= 1.5d || this.f19175w) {
                            i12 = 9;
                            if (i15 == 9 || i15 == 13) {
                            }
                        } else {
                            i12 = 9;
                        }
                        this.f19170r.setTextSize(Xj.a.d(i12));
                        canvas2.drawText(String.valueOf(i15), fU2, f18, (Paint) p162hb.e.c(i15 == i12 || i15 == 13, this.f19171s, this.f19170r));
                    } else {
                        f10 = fA4;
                        fA3 = fA3;
                    }
                }
                fU2 += fU;
                iF = i10 + 1;
                fA4 = f10;
                fA = fA;
                iK = i11;
                f15 = f15;
                dArr = dArr4;
                y1Var = y1Var2;
                dArr2 = dArr3;
                fA2 = fA2;
            }
            fA = fA;
            if (dN1 != null) {
                f10 = fA4;
                fA3 = fA3;
            } else {
                f10 = fA4;
                fA3 = fA3;
            }
            fU2 += fU;
            iF = i10 + 1;
            fA4 = f10;
            fA = fA;
            iK = i11;
            f15 = f15;
            dArr = dArr4;
            y1Var = y1Var2;
            dArr2 = dArr3;
            fA2 = fA2;
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
        C2741q c2741qB = i().b();
        KLineManager kLineManagerA = KLineManager.f142490O.a();
        int color = kLineManagerA.V() ? Color.parseColor("#6629AC4E") : Color.parseColor("#66CC1414");
        int color2 = kLineManagerA.V() ? Color.parseColor("#66CC1414") : Color.parseColor("#6629AC4E");
        Paint paint = this.f19164l;
        paint.setStrokeWidth(2.0f);
        paint.setAntiAlias(true);
        Paint paint2 = new Paint(this.f19164l);
        Paint.Style style = Paint.Style.STROKE;
        paint2.setStyle(style);
        paint2.setColor(aVar.r());
        this.f19165m = paint2;
        Paint paint3 = new Paint(this.f19164l);
        Paint.Style style2 = Paint.Style.FILL;
        paint3.setStyle(style2);
        paint3.setColor(color2);
        this.f19166n = paint3;
        Paint paint4 = new Paint(this.f19164l);
        paint4.setStyle(style);
        paint4.setColor(aVar.m());
        this.f19167o = paint4;
        Paint paint5 = new Paint(this.f19164l);
        paint5.setStyle(style2);
        paint5.setColor(color);
        this.f19168p = paint5;
        Paint paint6 = this.f19171s;
        paint6.setStyle(style2);
        paint6.setAntiAlias(true);
        paint6.setTextSize(Xj.a.d(10));
        paint6.setTextAlign(Paint.Align.CENTER);
        paint6.setColor(-1);
        Paint paint7 = new Paint(this.f19171s);
        paint7.setColor(aVar.r());
        this.f19169q = paint7;
        Paint paint8 = new Paint(this.f19171s);
        paint8.setColor(aVar.m());
        this.f19170r = paint8;
        this.f19172t = c2741qB.m(c());
        this.f19173u = c2741qB.l(b());
        AbstractC2755v abstractC2755vQ = q();
        if (abstractC2755vQ == null || !(abstractC2755vQ instanceof AbstractC7467h0)) {
            return;
        }
        AbstractC7467h0 abstractC7467h0 = (AbstractC7467h0) abstractC2755vQ;
        this.f19174v = abstractC7467h0;
        this.f19175w = abstractC7467h0.x().r()[0].b();
    }
}
