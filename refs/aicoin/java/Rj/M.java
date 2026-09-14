package Rj;

import Qf.InterfaceC2632j;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import java.text.DecimalFormat;
import kotlin.jvm.internal.DefaultConstructorMarker;
import sp.aicoin_kline.R;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class M extends AbstractC2744r0 {

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public static final a f19192C = new a(null);

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public boolean f19193A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public final nk.r f19194B;

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final InterfaceC2632j f19195l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final DecimalFormat f19196m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public int f19197n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public b f19198o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public boolean f19199p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final Paint f19200q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final Paint f19201r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public final int f19202s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public final float f19203t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public final int f19204u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public final int f19205v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public int f19206w;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public final int f19207x;

    /* JADX INFO: renamed from: y, reason: collision with root package name */
    public final Paint f19208y;

    /* JADX INFO: renamed from: z, reason: collision with root package name */
    public final Paint f19209z;

    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public enum b {
        Polygon,
        Arrow;


        /* JADX INFO: renamed from: d, reason: collision with root package name */
        public static final /* synthetic */ Zf.a f19213d = Zf.b.a(a());
    }

    public /* synthetic */ class c {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public static final /* synthetic */ int[] f19214a;

        static {
            int[] iArr = new int[b.values().length];
            try {
                iArr[b.Polygon.ordinal()] = 1;
            } catch (NoSuchFieldError unused) {
            }
            try {
                iArr[b.Arrow.ordinal()] = 2;
            } catch (NoSuchFieldError unused2) {
            }
            f19214a = iArr;
        }
    }

    public M(C2732n c2732n, String str) {
        super(c2732n, str);
        InterfaceC2632j interfaceC2632jB = Qf.k.b(new L());
        this.f19195l = interfaceC2632jB;
        this.f19196m = new DecimalFormat("0.00");
        this.f19197n = ((KLineManager) interfaceC2632jB.getValue()).j();
        this.f19198o = b.Polygon;
        Paint paint = new Paint();
        this.f19200q = paint;
        Paint paint2 = new Paint();
        this.f19208y = paint2;
        Paint paint3 = new Paint();
        this.f19209z = paint3;
        this.f19194B = new nk.r();
        Paint.Style style = Paint.Style.FILL;
        paint.setStyle(style);
        Paint paint4 = new Paint();
        paint4.setAntiAlias(true);
        paint4.setStyle(style);
        paint4.setTextAlign(Paint.Align.CENTER);
        KLineManager.a aVar = KLineManager.f142490O;
        paint4.setTextSize(nk.l.p(aVar.a().i(), 2, 9.0f));
        this.f19201r = paint4;
        paint2.setStyle(style);
        paint3.setAntiAlias(true);
        paint3.setStyle(style);
        paint3.setTextSize(nk.l.p(aVar.a().i(), 2, 9.0f));
        Paint.FontMetrics fontMetrics = paint4.getFontMetrics();
        this.f19202s = (int) Math.ceil(fontMetrics.bottom - fontMetrics.top);
        this.f19203t = (-(((float) Math.ceil(fontMetrics.bottom - fontMetrics.top)) / 2)) - fontMetrics.top;
        this.f19204u = (int) nk.l.o(1, 1.0f);
        this.f19205v = (int) nk.l.o(1, 2.0f);
        this.f19207x = aVar.a().q(12);
    }

    public static final KLineManager x() {
        return KLineManager.f142490O.a();
    }

    public final void A(int i10) {
        this.f19197n = i10;
    }

    public final void B(boolean z10) {
        this.f19199p = z10;
    }

    /* JADX WARN: Code duplicated, block: B:102:0x01ec  */
    /* JADX WARN: Code duplicated, block: B:82:0x016c  */
    /* JADX WARN: Code duplicated, block: B:83:0x0177  */
    /* JADX WARN: Code duplicated, block: B:96:0x01cd  */
    /* JADX WARN: Code duplicated, block: B:98:0x01d9  */
    /* JADX WARN: Multi-variable type inference failed */
    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        C2765z c2765zH;
        G gI;
        y1 y1VarM;
        String strF;
        AbstractC2759w0 abstractC2759w0L;
        double dA;
        float fS;
        double dV;
        Double dValueOf;
        nk.r.b bVar;
        this.f19193A = false;
        C2741q c2741qB = i().b();
        C2702d c2702dE = c2741qB.e(b());
        if (c2702dE == null || (c2765zH = c2741qB.h(c())) == null || (gI = c2741qB.i(c())) == null || (y1VarM = c2741qB.m(c())) == null || (strF = f()) == null || (abstractC2759w0L = c2741qB.l(strF)) == null) {
            return;
        }
        C2702d c2702dE2 = c2741qB.e(c() + ".mainRange");
        if (c2702dE2 == null || abstractC2759w0L.z() == 0.0d) {
            return;
        }
        boolean z10 = abstractC2759w0L instanceof C2742q0;
        if (nk.n.f(13)) {
            if (gI.B()) {
                float fV = gI.v();
                double dR = abstractC2759w0L.R(fV);
                float f10 = (float) dR;
                if (f10 != Float.POSITIVE_INFINITY && f10 != Float.NEGATIVE_INFINITY && c2702dE.m(fV) && fV > 0.0f) {
                    v(dR, fV, c2741qB, c2702dE, canvas, z10);
                    return;
                }
                return;
            }
            return;
        }
        nk.r.b bVarC = this.f19194B.c();
        bVarC.d();
        float fO = y1VarM.o();
        double dR2 = abstractC2759w0L.R(fO);
        float f11 = (float) dR2;
        if (f11 == Float.POSITIVE_INFINITY || f11 == Float.NEGATIVE_INFINITY) {
            return;
        }
        boolean z11 = c2702dE.m(fO) && fO > 0.0f;
        boolean z12 = this.f19207x != 2 && Ah.y.T(strF, "main", false, 2, null) && y1VarM.E() && y1VarM.N();
        if (!z11) {
            if (z12) {
                int i10 = this.f19207x;
                if (i10 == 0) {
                    int iD = y1VarM.D();
                    if (nk.z.a(c2765zH.C(), iD)) {
                        dA = ((Sj.b) c2765zH.C().get(iD)).a();
                        fS = abstractC2759w0L.S(dA);
                    }
                } else {
                    if (i10 != 1) {
                        return;
                    }
                    if (c2702dE.m(y1VarM.G())) {
                        float fMax = Math.max(abstractC2759w0L.x(), y1VarM.G());
                        double dR3 = abstractC2759w0L.R(fMax);
                        fS = fMax;
                        dA = dR3;
                    }
                }
                dV = v(dA, fS, c2741qB, c2702dE, canvas, z10);
                if (z10) {
                    dValueOf = nk.c.f134195a.b(dA, y1VarM.s());
                } else {
                    dValueOf = Double.valueOf(dV);
                }
                if (i().e().getSettings().c() && Ah.y.T(c2702dE.b(), "main", false, 2, null) && c2702dE2.m(fS) && ((KLineManager) this.f19195l.getValue()).q(24) == 1) {
                    float f12 = this.f19202s >> 1;
                    bVar = bVarC;
                    z(fS - f12, fS + f12, dValueOf != null ? w(dValueOf.doubleValue(), c2765zH) : null, c2702dE, canvas, bVar, dV, true);
                } else {
                    bVar = bVarC;
                    if (Ah.y.T(c2702dE.b(), "main", false, 2, null) && c2702dE2.m(fS)) {
                        float f13 = this.f19202s >> 1;
                        z(fS - f13, fS + f13, dValueOf != null ? w(dValueOf.doubleValue(), c2765zH) : null, c2702dE, canvas, bVar, dV, false);
                    }
                }
                bVar.b();
            }
            return;
        }
        fO = y1VarM.o();
        fS = fO;
        dA = dR2;
        dV = v(dA, fS, c2741qB, c2702dE, canvas, z10);
        if (z10) {
            dValueOf = nk.c.f134195a.b(dA, y1VarM.s());
        } else {
            dValueOf = Double.valueOf(dV);
        }
        if (i().e().getSettings().c()) {
            bVar = bVarC;
            if (Ah.y.T(c2702dE.b(), "main", false, 2, null)) {
                float f14 = this.f19202s >> 1;
                z(fS - f14, fS + f14, dValueOf != null ? w(dValueOf.doubleValue(), c2765zH) : null, c2702dE, canvas, bVar, dV, false);
            }
        } else {
            bVar = bVarC;
            if (Ah.y.T(c2702dE.b(), "main", false, 2, null)) {
                float f15 = this.f19202s >> 1;
                z(fS - f15, fS + f15, dValueOf != null ? w(dValueOf.doubleValue(), c2765zH) : null, c2702dE, canvas, bVar, dV, false);
            }
        }
        bVar.b();
    }

    @Override // Rj.AbstractC2744r0
    public boolean n(String str, int i10, int i11) {
        Object objD = this.f19194B.d(i10, i11);
        Double d10 = objD instanceof Double ? (Double) objD : null;
        if (this.f19193A && d10 != null) {
            C2765z c2765zD = i().d();
            C2738p.f19487a.b(d10.doubleValue(), nk.l.n(nk.l.f134222a, d10.doubleValue(), 0, 9, 0, AbstractC2735o.a(i()), 8, null), d10.doubleValue() >= (c2765zD != null ? c2765zD.V() : -1.0d) ? "up" : "down");
        }
        return false;
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        if (aVar == null) {
            return;
        }
        this.f19200q.setColor(aVar.c(3));
        this.f19201r.setColor(aVar.u(14));
        this.f19206w = aVar.b(1);
        this.f19208y.setColor(aVar.c(7));
        this.f19209z.setColor(aVar.u(13));
    }

    public final double v(double d10, float f10, C2741q c2741q, C2702d c2702d, Canvas canvas, boolean z10) {
        double dDoubleValue;
        String str;
        int iU = c2702d.u() + this.f19204u;
        int i10 = (this.f19202s >> 2) + iU;
        int iY = c2702d.y() - this.f19205v;
        boolean zF = nk.n.f(13);
        String str2 = (String) p162hb.e.c(z10, "%", "");
        Paint paint = new Paint(this.f19200q);
        Paint paint2 = new Paint(this.f19201r);
        if (zF) {
            KLineManager.a aVar = KLineManager.f142490O;
            paint.setColor(((Number) p162hb.e.c(aVar.a().f0() == 1, Integer.valueOf(Color.parseColor("#7A8799")), Integer.valueOf(Color.parseColor("#4A5462")))).intValue());
            paint2.setColor(((Number) p162hb.e.c(aVar.a().f0() == 1, Integer.valueOf(Color.parseColor("#FFFFFF")), Integer.valueOf(Color.parseColor("#C3C7D9")))).intValue());
        }
        int i11 = c.f19214a[this.f19198o.ordinal()];
        if (i11 != 1) {
            if (i11 != 2) {
                throw new Qf.n();
            }
            int color = this.f19201r.getColor();
            this.f19201r.setColor(this.f19206w);
            float f11 = this.f19202s >> 2;
            float f12 = f10 - f11;
            float f13 = f10 + f11;
            float f14 = iU;
            float f15 = i10;
            canvas.drawLine(f14, f10, f15, f12, this.f19201r);
            canvas.drawLine(f14, f10, iU + (this.f19202s >> 1), f10, this.f19201r);
            canvas.drawLine(f14, f10, f15, f13, this.f19201r);
            this.f19201r.setTextAlign(Paint.Align.LEFT);
            canvas.drawText(kk.i.a(this.f19199p ? nk.h.i(nk.h.f134211a, d10, false, 0, null, 14, null) : nk.j.f134218a.a(d10), str2), (this.f19202s * 0.6f) + f14, f10 + this.f19203t, this.f19201r);
            this.f19201r.setColor(color);
            return 0.0d;
        }
        float f16 = this.f19202s >> 1;
        canvas.drawRect(iU, f10 - f16, iY, f10 + f16, paint);
        if (this.f19199p) {
            String strI = nk.h.i(nk.h.f134211a, d10, false, 0, null, 14, null);
            Double dN = Ah.v.n(strI);
            dDoubleValue = dN != null ? dN.doubleValue() : 0.0d;
            str = c2741q.f19512t + strI;
        } else {
            String strM = nk.l.f134222a.m(d10, 0, 9, ((Number) p162hb.e.c(z10, 2, Integer.valueOf(this.f19197n))).intValue(), AbstractC2735o.a(i()));
            Double dN2 = Ah.v.n(strM);
            dDoubleValue = dN2 != null ? dN2.doubleValue() : 0.0d;
            str = c2741q.f19512t + strM;
        }
        canvas.drawText(kk.i.a(str, str2), c2702d.q(), f10 + this.f19203t, paint2);
        return dDoubleValue;
    }

    public final String w(double d10, C2765z c2765z) {
        double dA;
        if (!((KLineManager) this.f19195l.getValue()).X()) {
            return null;
        }
        Sj.b bVarM = c2765z.M();
        if (bVarM == null) {
            Sj.b bVar = (Sj.b) Sf.z.D0(c2765z.C());
            if (bVar != null) {
                dA = bVar.a();
            }
            return null;
        }
        dA = bVarM.a();
        Double dA2 = nk.c.f134195a.a(d10, nk.c.e(dA));
        if (dA2 != null) {
            return this.f19196m.format(dA2.doubleValue() * ((double) 100)) + '%';
        }
        return null;
    }

    public final void y(float f10, float f11, C2702d c2702d, Canvas canvas, nk.r.b bVar, double d10) {
        float fU = c2702d.u() + this.f19204u;
        float fY = c2702d.y() - this.f19205v;
        canvas.drawRect(fU, f10, fY, f11, this.f19208y);
        float f12 = ((f11 - f10) / 2) + f10;
        String string = i().c().getResources().getString(R.string.kline_alert_control_text);
        Rect rect = new Rect();
        this.f19209z.getTextBounds(string, 0, string.length(), rect);
        canvas.drawText(string, ((c2702d.A() - rect.width()) / 2.0f) + fU, f12 + this.f19203t, this.f19209z);
        this.f19193A = true;
        nk.q qVarA = nk.q.f134234e.a();
        float fB = Xj.a.b(10);
        float f13 = f10 - fB;
        float f14 = fB + f11;
        qVarA.g(fU, f13, fY, f14);
        qVarA.i(fU, f13, fY, f14);
        qVarA.j(Double.valueOf(d10));
        bVar.e(qVarA);
    }

    /* JADX WARN: Multi-variable type inference failed */
    public final void z(float f10, float f11, String str, C2702d c2702d, Canvas canvas, nk.r.b bVar, double d10, boolean z10) {
        float f12;
        float f13;
        int i10 = (str == null || str.length() == 0) ? 1 : 0;
        int i11 = i10 ^ 1;
        if (i10 == 0 || z10) {
            float f14 = this.f19202s;
            float f15 = (i11 + (z10 ? 1 : 0)) * f14;
            boolean z11 = (((f11 + f15) > ((float) c2702d.p()) ? 1 : ((f11 + f15) == ((float) c2702d.p()) ? 0 : -1)) <= 0) == true || !(((f10 - f15) > ((float) c2702d.z()) ? 1 : ((f10 - f15) == ((float) c2702d.z()) ? 0 : -1)) >= 0) == true;
            if (!z11) {
                f11 = 0.0f;
            }
            float f16 = z11 ? 0.0f : f10;
            if (!z11) {
                if (i10 == 0) {
                    f12 = f16 - f14;
                    if (str == null) {
                        str = "";
                    }
                    Paint paint = this.f19200q;
                    Paint paint2 = this.f19201r;
                    canvas.drawRect(c2702d.u() + this.f19204u, f12, c2702d.y() - this.f19205v, f16, paint);
                    canvas.drawText(str, c2702d.q(), ((f16 - f12) / 2) + f12 + this.f19203t, paint2);
                } else {
                    f12 = f16;
                }
                if (z10) {
                    y(f12 - f14, f12, c2702d, canvas, bVar, d10);
                    return;
                }
                return;
            }
            if (i10 == 0) {
                float f17 = f11 + f14;
                if (str == null) {
                    str = "";
                }
                Paint paint3 = this.f19200q;
                Paint paint4 = this.f19201r;
                float f18 = f11;
                canvas.drawRect(c2702d.u() + this.f19204u, f18, c2702d.y() - this.f19205v, f17, paint3);
                canvas.drawText(str, c2702d.q(), ((f17 - f18) / 2) + f18 + this.f19203t, paint4);
                f13 = f17;
            } else {
                f13 = f11;
            }
            if (z10) {
                y(f13, f13 + f14, c2702d, canvas, bVar, d10);
            }
        }
    }
}
