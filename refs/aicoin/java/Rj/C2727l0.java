package Rj;

import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.Rect;
import android.graphics.RectF;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.chart.data.AIWinRateItem;

/* JADX INFO: renamed from: Rj.l0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2727l0 extends AbstractC2744r0 {

    /* JADX INFO: renamed from: N, reason: collision with root package name */
    public static final a f19449N = new a(null);

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public int f19450A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public float f19451B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public final float f19452C;

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public final float f19453D;

    /* JADX INFO: renamed from: E, reason: collision with root package name */
    public final float f19454E;

    /* JADX INFO: renamed from: F, reason: collision with root package name */
    public final float f19455F;

    /* JADX INFO: renamed from: G, reason: collision with root package name */
    public final float f19456G;

    /* JADX INFO: renamed from: H, reason: collision with root package name */
    public final float f19457H;

    /* JADX INFO: renamed from: I, reason: collision with root package name */
    public float f19458I;

    /* JADX INFO: renamed from: J, reason: collision with root package name */
    public final LinkedHashMap f19459J;

    /* JADX INFO: renamed from: K, reason: collision with root package name */
    public final LinkedHashMap f19460K;

    /* JADX INFO: renamed from: L, reason: collision with root package name */
    public float f19461L;

    /* JADX INFO: renamed from: M, reason: collision with root package name */
    public float f19462M;

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final Paint f19463l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Paint f19464m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final Paint f19465n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final RectF f19466o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final Path f19467p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final RectF f19468q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final Path f19469r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public final RectF f19470s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public final Rect f19471t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public int f19472u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public int f19473v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public int f19474w;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public int f19475x;

    /* JADX INFO: renamed from: y, reason: collision with root package name */
    public int f19476y;

    /* JADX INFO: renamed from: z, reason: collision with root package name */
    public final nk.r f19477z;

    /* JADX INFO: renamed from: Rj.l0$a */
    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public C2727l0(C2732n c2732n, String str) {
        super(c2732n, str);
        Paint paint = new Paint();
        paint.setAntiAlias(true);
        paint.setDither(true);
        Paint.Style style = Paint.Style.FILL;
        paint.setStyle(style);
        this.f19463l = paint;
        Paint paint2 = new Paint();
        paint2.setAntiAlias(true);
        paint2.setDither(true);
        paint2.setStyle(style);
        this.f19464m = paint2;
        Paint paint3 = new Paint();
        paint3.setAntiAlias(true);
        paint3.setDither(true);
        paint3.setStyle(style);
        this.f19465n = paint3;
        this.f19466o = new RectF();
        this.f19467p = new Path();
        this.f19468q = new RectF();
        this.f19469r = new Path();
        this.f19470s = new RectF();
        new Rect();
        this.f19471t = new Rect();
        this.f19473v = 23;
        this.f19474w = 6;
        this.f19475x = 23;
        this.f19477z = new nk.r();
        this.f19452C = Xj.a.a(3.0f);
        this.f19453D = Xj.a.a(4.5f);
        float fA = Xj.a.a(3.0f);
        this.f19454E = fA;
        this.f19455F = Xj.a.a(1.5f);
        this.f19456G = (float) (Math.tan(0.5235987755982988d) * ((double) fA));
        this.f19457H = Xj.a.a(3.0f);
        this.f19459J = new LinkedHashMap();
        this.f19460K = new LinkedHashMap();
    }

    /* JADX WARN: Multi-variable type inference failed */
    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        y1 y1VarM;
        AbstractC2759w0 abstractC2759w0L;
        AbstractC2755v abstractC2755vG;
        Sj.a aVarC;
        nk.r.b bVar;
        float f10;
        C2727l0 c2727l0 = this;
        C2741q c2741qB = c2727l0.i().b();
        C2702d c2702dE = c2741qB.e(c2727l0.b());
        if (c2702dE == null || (y1VarM = c2741qB.m(c2727l0.c())) == null || (abstractC2759w0L = c2741qB.l(c2727l0.b())) == null) {
            return;
        }
        AbstractC2759w0 abstractC2759w0 = abstractC2759w0L.z() == 0.0d ? null : abstractC2759w0L;
        if (abstractC2759w0 == null || (abstractC2755vG = c2741qB.g(c2727l0.d())) == null || !(abstractC2755vG instanceof C2724k0)) {
            return;
        }
        List list = c2741qB.f19505m;
        List listS = ((C2724k0) abstractC2755vG).s();
        List list2 = !listS.isEmpty() ? listS : null;
        if (list2 == null) {
            return;
        }
        nk.r.b bVarC = c2727l0.f19477z.c();
        bVarC.d();
        c2727l0.f19459J.clear();
        c2727l0.f19460K.clear();
        c2727l0.f19476y = c2702dE.y();
        float fZ = y1VarM.z();
        c2727l0.f19473v = (int) p292ng.i.e(18.0f, p292ng.i.j(36.0f, 8 * fZ));
        c2727l0.f19474w = (int) p292ng.i.e(5.0f, p292ng.i.j(14.0f, 4 * fZ));
        c2727l0.f19475x = c2727l0.f19473v;
        c2727l0.f19450A = Xj.a.b(24);
        float fU = y1VarM.u();
        float fJ = y1VarM.J();
        int iR = y1VarM.r();
        int iQ = y1VarM.q();
        float f11 = 2;
        c2727l0.f19451B = Xj.a.a(y1VarM.z()) / f11;
        int size = list2.size();
        C2765z c2765zD = abstractC2755vG.h().d();
        if (c2765zD == null || (aVarC = c2765zD.C()) == null || aVarC.isEmpty()) {
            return;
        }
        long jH = y1VarM.H(iR);
        long jH2 = y1VarM.H(iR + 1) - y1VarM.H(iR);
        int i10 = 0;
        while (i10 < size && ((Sj.h) list2.get(i10)).e() < jH) {
            i10++;
        }
        if (i10 < size) {
            float f12 = (fU / f11) - fJ;
            canvas.save();
            int i11 = iR;
            canvas.clipRect(c2702dE.u(), c2702dE.z(), c2702dE.y(), c2702dE.p());
            while (i10 < size) {
                Sj.h hVar = (Sj.h) list2.get(i10);
                long jE = hVar.e();
                int iP = y1VarM.p(jE);
                if (iP > iQ) {
                    break;
                }
                float f13 = ((iP - i11) * fU) + f12;
                int iP2 = y1VarM.p(jE);
                double dB = ((Sj.b) aVarC.get(iP2)).b();
                Sj.a aVar = aVarC;
                double dC = ((Sj.b) aVarC.get(iP2)).c();
                float fS = abstractC2759w0.S(dB);
                float fS2 = abstractC2759w0.S(dC);
                Integer num = (Integer) c2727l0.f19459J.get(Integer.valueOf(iP2));
                int iIntValue = num != null ? num.intValue() : 0;
                Integer num2 = (Integer) c2727l0.f19460K.get(Integer.valueOf(iP2));
                int iIntValue2 = num2 != null ? num2.intValue() : 0;
                long jH3 = y1VarM.H(iP2);
                if (list != null) {
                    ArrayList arrayList = new ArrayList();
                    for (Object obj : list) {
                        float f14 = fS2;
                        long j10 = jH3 + jH2;
                        long signal_time_s = ((AIWinRateItem) obj).getSignal_time_s();
                        if (jH3 <= signal_time_s && signal_time_s < j10) {
                            arrayList.add(obj);
                        }
                        fS2 = f14;
                    }
                    f10 = fS2;
                    Iterator it = arrayList.iterator();
                    int i12 = 0;
                    int i13 = 0;
                    while (it.hasNext()) {
                        AIWinRateItem aIWinRateItem = (AIWinRateItem) it.next();
                        Iterator it2 = it;
                        if (AbstractC7609s.f(aIWinRateItem.getSide(), "buy")) {
                            i12++;
                        } else if (AbstractC7609s.f(aIWinRateItem.getSide(), "sell")) {
                            i13++;
                        }
                        it = it2;
                    }
                    if (i12 == 0) {
                        c2727l0.f19461L = Xj.a.a(0.0f);
                    } else if (i12 == 1) {
                        c2727l0.f19461L = Xj.a.a(11.0f);
                    } else if (i12 == 2) {
                        c2727l0.f19461L = Xj.a.a(22.0f);
                    } else if (i12 == 3) {
                        c2727l0.f19461L = Xj.a.a(38.0f);
                    } else if (i12 == 4) {
                        c2727l0.f19461L = Xj.a.a(50.0f);
                    } else if (i12 == 5) {
                        c2727l0.f19461L = Xj.a.a(58.0f);
                    }
                    if (i13 == 0) {
                        c2727l0.f19462M = Xj.a.a(0.0f);
                    } else if (i13 == 1) {
                        c2727l0.f19462M = Xj.a.a(11.0f);
                    } else if (i13 == 2) {
                        c2727l0.f19462M = Xj.a.a(22.0f);
                    } else if (i13 == 3) {
                        c2727l0.f19462M = Xj.a.a(33.0f);
                    } else if (i13 == 4) {
                        c2727l0.f19462M = Xj.a.a(44.0f);
                    } else if (i13 == 5) {
                        c2727l0.f19462M = Xj.a.a(55.0f);
                    }
                } else {
                    f10 = fS2;
                }
                int iA = hVar.a();
                int iC = hVar.c();
                Sj.j jVar = iA != 0 ? new Sj.j(jE, 1, hVar.b(), iA, null) : null;
                Sj.j jVar2 = iC != 0 ? new Sj.j(jE, 2, hVar.d(), iC, null) : null;
                if (jVar == null || !abstractC2759w0.m(jVar.a())) {
                    jVar = null;
                }
                if (jVar2 == null || !abstractC2759w0.m(jVar2.a())) {
                    jVar2 = null;
                }
                float f15 = c2727l0.f19451B;
                float f16 = c2727l0.f19458I;
                float f17 = (((fS - f15) - (iIntValue2 * f16)) - c2727l0.f19462M) - 8.0f;
                float f18 = (iIntValue * f16) + f10 + f15 + c2727l0.f19461L + 8.0f;
                c2727l0.v(canvas, bVarC, jVar2, f13, f17);
                c2727l0.v(canvas, bVarC, jVar, f13, f18);
                i10++;
                c2727l0 = this;
                f12 = f13;
                i11 = iP;
                aVarC = aVar;
            }
            bVar = bVarC;
            canvas.restore();
        } else {
            bVar = bVarC;
        }
        bVar.b();
    }

    @Override // Rj.AbstractC2744r0
    public boolean n(String str, int i10, int i11) {
        Object objD = this.f19477z.d(i10, i11);
        if (objD == null || !(objD instanceof Sj.j)) {
            return false;
        }
        C2738p.f19487a.n((Sj.j) objD);
        return true;
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        if (aVar == null) {
            return;
        }
        this.f19463l.setColor(nk.v.b(aVar, ".order_point.circle.red", ".order_point.circle.green"));
        this.f19464m.setColor(nk.v.a(aVar, ".order_point.circle.red", ".order_point.circle.green"));
        this.f19465n.setColor(aVar.d(".order_point.text_color"));
        this.f19472u = aVar.d(".order_point.shadow_color");
        i().b();
        this.f19463l.setShadowLayer(this.f19474w, 0.0f, 0.0f, this.f19472u);
        this.f19464m.setShadowLayer(this.f19474w, 0.0f, 0.0f, this.f19472u);
        this.f19465n.setTextSize(this.f19475x);
        this.f19465n.getTextBounds("B", 0, 1, this.f19471t);
        this.f19458I = (2 * this.f19452C) + this.f19471t.height() + this.f19454E;
    }

    public final void v(Canvas canvas, nk.r.b bVar, Sj.j jVar, float f10, float f11) {
        if (jVar == null || f10 > this.f19476y) {
            return;
        }
        int i10 = this.f19473v;
        float f12 = i10;
        float f13 = p292ng.i.f(i10, this.f19450A);
        nk.q qVarA = nk.q.f134234e.a();
        qVarA.g(f10 - f12, f11 - f12, f10 + f12, f12 + f11);
        qVarA.i(f10 - f13, f11 - f13, f10 + f13, f13 + f11);
        qVarA.j(jVar);
        bVar.e(qVarA);
        if (jVar.d() == 1) {
            Paint paint = this.f19463l;
            Paint paint2 = this.f19465n;
            paint2.getTextBounds("B", 0, 1, this.f19471t);
            float f14 = 2;
            float fHeight = (this.f19452C * f14) + this.f19471t.height();
            float fWidth = (f14 * this.f19453D) + this.f19471t.width();
            Path path = this.f19467p;
            path.reset();
            path.moveTo(f10, f11);
            path.lineTo(f10 - this.f19456G, this.f19454E + f11);
            path.lineTo(this.f19456G + f10, this.f19454E + f11);
            path.close();
            canvas.drawPath(this.f19467p, paint);
            float f15 = fWidth * 0.5f;
            float f16 = f10 - f15;
            this.f19466o.set(Xj.a.a(1.0f) + f16, this.f19454E + f11, (f15 + f10) - Xj.a.a(1.0f), this.f19454E + f11 + fHeight);
            RectF rectF = this.f19466o;
            float f17 = this.f19457H;
            canvas.drawRoundRect(rectF, f17, f17, paint);
            canvas.drawText("B", f16 + this.f19453D, ((((this.f19454E + f11) + fHeight) - this.f19452C) - this.f19455F) + 2.0f, paint2);
        } else if (jVar.d() == 2) {
            Paint paint3 = this.f19464m;
            Paint paint4 = this.f19465n;
            paint4.getTextBounds("S", 0, 1, this.f19471t);
            float f18 = 2;
            float fHeight2 = (this.f19452C * f18) + this.f19471t.height();
            float fWidth2 = (f18 * this.f19453D) + this.f19471t.width();
            Path path2 = this.f19469r;
            path2.reset();
            path2.moveTo(f10, f11);
            path2.lineTo(f10 - this.f19456G, f11 - this.f19454E);
            path2.lineTo(this.f19456G + f10, f11 - this.f19454E);
            path2.close();
            canvas.drawPath(this.f19469r, paint3);
            float f19 = fWidth2 * 0.5f;
            float f20 = f10 - f19;
            this.f19468q.set(Xj.a.a(1.0f) + f20, (f11 - this.f19454E) - fHeight2, (f19 + f10) - Xj.a.a(1.0f), f11 - this.f19454E);
            RectF rectF2 = this.f19468q;
            float f21 = this.f19457H;
            canvas.drawRoundRect(rectF2, f21, f21, paint3);
            canvas.drawText("S", f20 + this.f19453D, (((f11 - this.f19454E) - this.f19452C) - this.f19455F) + 2.0f, paint4);
        }
        if (this.f19475x > 0) {
            RectF rectF3 = this.f19470s;
            float f22 = this.f19473v;
            rectF3.set(f10 - f22, f11 - f22, f10 + f22, f11 + f22);
        }
    }
}
