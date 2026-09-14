package Rj;

import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RectF;
import sp.aicoin_kline.chart.Chart;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class C0 extends AbstractC2744r0 {

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public final RectF f19046A;

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final Paint f19047l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Paint f19048m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final Paint f19049n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final Paint f19050o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final Paint f19051p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final Paint f19052q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final Paint f19053r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public final Paint f19054s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public final int f19055t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public final float f19056u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public final int f19057v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public final int f19058w;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public final KLineManager f19059x;

    /* JADX INFO: renamed from: y, reason: collision with root package name */
    public final int f19060y;

    /* JADX INFO: renamed from: z, reason: collision with root package name */
    public final float f19061z;

    public C0(C2732n c2732n, String str) {
        super(c2732n, str);
        KLineManager.a aVar = KLineManager.f142490O;
        this.f19059x = aVar.a();
        this.f19060y = Xj.a.b(4);
        this.f19061z = Xj.a.b(4);
        this.f19046A = new RectF();
        Paint paint = new Paint();
        this.f19047l = paint;
        Paint.Style style = Paint.Style.FILL;
        paint.setStyle(style);
        Paint paint2 = new Paint();
        this.f19051p = paint2;
        paint2.setAntiAlias(true);
        paint2.setStyle(style);
        paint2.setTextAlign(Paint.Align.CENTER);
        paint2.setTextSize(nk.l.p(aVar.a().i(), 2, 9.0f));
        this.f19052q = new Paint(paint2);
        this.f19053r = new Paint(paint2);
        this.f19054s = new Paint(paint2);
        this.f19048m = new Paint(paint);
        this.f19049n = new Paint(paint);
        this.f19050o = new Paint(paint);
        Paint.FontMetrics fontMetrics = paint2.getFontMetrics();
        this.f19055t = (int) Math.ceil(fontMetrics.bottom - fontMetrics.top);
        this.f19056u = (-(((float) Math.ceil(fontMetrics.bottom - fontMetrics.top)) / 2)) - fontMetrics.top;
        this.f19057v = (int) nk.l.o(1, 1.0f);
        this.f19058w = (int) nk.l.o(1, 2.0f);
    }

    /* JADX WARN: Multi-variable type inference failed */
    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        C2765z c2765zD;
        String strF;
        AbstractC2759w0 abstractC2759w0L;
        double d10;
        Paint paint;
        Canvas canvas2;
        Paint paint2;
        this.f19046A.setEmpty();
        C2741q c2741qB = i().b();
        C2702d c2702dE = c2741qB.e(b());
        if (c2702dE == null || (c2765zD = i().d()) == null || (strF = f()) == null || (abstractC2759w0L = c2741qB.l(strF)) == null || abstractC2759w0L.z() == 0.0d) {
            return;
        }
        boolean z10 = abstractC2759w0L instanceof C2742q0;
        AbstractC2755v abstractC2755vG = c2741qB.g(strF.concat(".m"));
        if (abstractC2755vG == null) {
            return;
        }
        double dE = nk.c.e(abstractC2755vG.i());
        double dR = abstractC2759w0L.R(abstractC2759w0L.S(dE));
        Sj.a aVarC = c2765zD.C();
        if (aVarC.size() <= 0) {
            d10 = dE;
            break;
        }
        int size = aVarC.size();
        int i10 = 1;
        while (true) {
            if (i10 >= size) {
                d10 = dE;
                break;
            } else {
                if (!Double.isNaN(((Sj.b) aVarC.get(aVarC.size() - i10)).d())) {
                    d10 = ((Sj.b) aVarC.get(aVarC.size() - i10)).d();
                    break;
                }
                i10++;
            }
        }
        int iU = c2702dE.u();
        int iY = c2702dE.y();
        float fP = abstractC2759w0L.P(dE);
        float f10 = this.f19055t >> 1;
        float f11 = fP - f10;
        float f12 = fP + f10;
        KLineManager.f142490O.a().F0(iY - iU);
        if (this.f19059x.S()) {
            paint = this.f19050o;
        } else {
            paint = dE > d10 ? this.f19048m : this.f19049n;
        }
        Paint paint3 = paint;
        float f13 = iU;
        float f14 = iY;
        canvas.drawRect(f13, f11, f14, f12, paint3);
        this.f19046A.set(f13, f11, f14, f12);
        RectF rectF = this.f19046A;
        float f15 = -this.f19061z;
        rectF.inset(f15, f15);
        float f16 = this.f19060y;
        float f17 = f12 + f16;
        float f18 = this.f19055t;
        float f19 = f17 + f18;
        float f20 = fP + this.f19056u + f18 + f16;
        if (f19 > c2702dE.p()) {
            float f21 = this.f19060y;
            f19 = f11 - f21;
            float f22 = this.f19055t;
            f17 = f19 - f22;
            f20 = ((fP + this.f19056u) - f22) - f21;
        }
        float f23 = f20;
        float f24 = f17;
        float f25 = f19;
        String strC = nk.c.c();
        if (strC.length() > 0) {
            canvas2 = canvas;
            nk.y.a(canvas2, f13, f24, f14, f25, paint3);
        } else {
            canvas2 = canvas;
        }
        StringBuilder sb2 = new StringBuilder();
        nk.l lVar = nk.l.f134222a;
        String str = (String) p162hb.e.c(z10, kk.h.a(sb2, nk.l.k(lVar, dR, 2, null, 4, null), '%'), c2741qB.f19512t + lVar.j(dE, AbstractC2735o.a(i())));
        if (this.f19059x.S()) {
            paint2 = this.f19054s;
        } else {
            paint2 = dE > d10 ? this.f19052q : this.f19053r;
        }
        canvas2.drawText(str, c2702dE.q(), fP + this.f19056u, paint2);
        if (strC.length() > 0) {
            canvas2.drawText(strC, c2702dE.q(), f23, paint2);
        }
    }

    @Override // Rj.AbstractC2744r0
    public boolean n(String str, int i10, int i11) {
        if (this.f19046A.isEmpty() || !this.f19046A.contains(i10, i11)) {
            return false;
        }
        Chart chartA = i().a();
        if (chartA == null) {
            return true;
        }
        chartA.C();
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
        this.f19047l.setColor(aVar.c(5));
        this.f19048m.setColor(aVar.p());
        this.f19049n.setColor(aVar.k());
        this.f19050o.setColor(aVar.c(8));
        this.f19051p.setColor(aVar.u(12));
        this.f19052q.setColor(aVar.r());
        this.f19053r.setColor(aVar.m());
        this.f19054s.setColor(aVar.u(15));
        aVar.b(1);
    }
}
