package Rj;

import android.graphics.Canvas;
import android.graphics.DashPathEffect;
import android.graphics.Paint;
import android.graphics.Path;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: Rj.g0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2712g0 extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final float f19405l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Paint f19406m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final Paint f19407n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final Paint f19408o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final Paint f19409p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final boolean f19410q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final int f19411r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public final Path f19412s;

    public C2712g0(C2732n c2732n, String str) {
        super(c2732n, str);
        Paint paint = new Paint();
        this.f19406m = paint;
        this.f19412s = new Path();
        paint.setAntiAlias(true);
        paint.setStyle(Paint.Style.FILL);
        KLineManager.a aVar = KLineManager.f142490O;
        paint.setTextSize(nk.l.p(aVar.a().i(), 2, 9.0f));
        Paint.FontMetrics fontMetrics = paint.getFontMetrics();
        Math.ceil(fontMetrics.bottom - fontMetrics.top);
        this.f19405l = (-(((float) Math.ceil(fontMetrics.bottom - fontMetrics.top)) / 2)) - fontMetrics.top;
        Paint paint2 = new Paint();
        this.f19407n = paint2;
        Paint.Style style = Paint.Style.STROKE;
        paint2.setStyle(style);
        Paint paint3 = new Paint();
        this.f19408o = paint3;
        paint3.setStyle(style);
        paint3.setStrokeWidth(2.0f);
        paint3.setPathEffect(new DashPathEffect(new float[]{Xj.a.b(3), Xj.a.b(2)}, 0.0f));
        Paint paint4 = new Paint();
        this.f19409p = paint4;
        paint4.setStyle(style);
        paint4.setStrokeWidth(2.0f);
        this.f19410q = nk.n.f(10);
        this.f19411r = aVar.a().q(12);
    }

    /* JADX WARN: Multi-variable type inference failed */
    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        y1 y1VarM;
        AbstractC2759w0 abstractC2759w0L;
        C2765z c2765zH;
        G gI;
        C2741q c2741qB = i().b();
        C2702d c2702dE = c2741qB.e(b());
        if (c2702dE == null || (y1VarM = c2741qB.m(c())) == null || (abstractC2759w0L = c2741qB.l(b())) == null || (c2765zH = c2741qB.h(c())) == null || (gI = c2741qB.i(c())) == null || abstractC2759w0L.z() == 0.0d) {
            return;
        }
        AbstractC2755v abstractC2755vG = c2741qB.g(b() + ".m");
        if (abstractC2755vG == null) {
            return;
        }
        if (C2760w1.f19594a.j()) {
            int iQ = (y1VarM.q() + y1VarM.r()) >> 1;
            v(canvas, c2702dE, abstractC2755vG.m(), abstractC2759w0L.S(abstractC2755vG.m()), iQ, abstractC2755vG.n(), y1VarM);
            v(canvas, c2702dE, abstractC2755vG.j(), abstractC2759w0L.S(abstractC2755vG.j()), iQ, abstractC2755vG.k(), y1VarM);
        }
        if (this.f19410q) {
            float fP = abstractC2759w0L.P(nk.c.e(abstractC2755vG.i()));
            Path path = this.f19412s;
            path.reset();
            path.moveTo(c2702dE.u(), fP);
            path.lineTo(c2702dE.y(), fP);
            canvas.drawPath(this.f19412s, this.f19408o);
        }
        if (nk.n.f(13)) {
            if (gI.B()) {
                float fV = gI.v();
                if (!c2702dE.m(fV) || fV <= 0.0f) {
                    return;
                }
                canvas.drawLine(c2702dE.u(), fV, c2702dE.y(), fV, this.f19409p);
                return;
            }
            return;
        }
        float fO = y1VarM.o();
        if (c2702dE.m(fO) && fO > 0.0f) {
            canvas.drawLine(c2702dE.u(), fO, c2702dE.y(), fO, this.f19409p);
            return;
        }
        if (y1VarM.E()) {
            int i10 = this.f19411r;
            if (i10 == 0) {
                int iD = y1VarM.D();
                if (nk.z.a(c2765zH.C(), iD)) {
                    fO = abstractC2759w0L.S(((Sj.b) c2765zH.C().get(iD)).a());
                }
            } else if (i10 == 1) {
                fO = Math.max(abstractC2759w0L.x(), y1VarM.G());
            } else if (i10 == 2) {
                return;
            }
            if (c2702dE.m(fO) && fO > 0.0f && y1VarM.N()) {
                canvas.drawLine(c2702dE.u(), fO, c2702dE.y(), fO, this.f19407n);
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
        this.f19406m.setColor(aVar.u(3));
        this.f19407n.setColor(aVar.t());
        this.f19409p.setColor(aVar.h());
        this.f19408o.setColor(aVar.t());
    }

    public final void v(Canvas canvas, C2702d c2702d, double d10, float f10, int i10, int i11, y1 y1Var) {
        float f11;
        float f12;
        float f13;
        if (!c2702d.m(f10) || f10 <= 0.0f || Float.isInfinite(f10) || Float.isNaN(f10)) {
            return;
        }
        if (i11 > i10) {
            this.f19406m.setTextAlign(Paint.Align.RIGHT);
            float fL = y1Var.l(i11);
            float f14 = 6;
            f11 = fL - f14;
            f12 = f11 - 30;
            f13 = f12 - f14;
        } else {
            this.f19406m.setTextAlign(Paint.Align.LEFT);
            float fL2 = y1Var.l(i11);
            float f15 = 6;
            f11 = fL2 + f15;
            f12 = 30 + f11;
            f13 = f15 + f12;
        }
        canvas.drawLine(f11, f10, f12, f10, this.f19406m);
        canvas.drawText(nk.l.f134222a.j(d10, AbstractC2735o.a(i())), f13, f10 + this.f19405l, this.f19406m);
    }
}
