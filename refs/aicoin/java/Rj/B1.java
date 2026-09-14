package Rj;

import android.graphics.Canvas;
import android.graphics.Paint;
import java.util.Date;

/* JADX INFO: loaded from: classes7.dex */
public final class B1 extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final float f19040l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final float f19041m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final float f19042n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final Paint f19043o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final Paint f19044p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public C2741q f19045q;

    public B1(C2732n c2732n, String str) {
        super(c2732n, str);
        Paint paint = new Paint();
        this.f19043o = paint;
        this.f19044p = new Paint();
        paint.setTextSize(nk.l.o(2, 9.0f));
        Paint.FontMetrics fontMetrics = paint.getFontMetrics();
        float fCeil = (float) Math.ceil(fontMetrics.bottom - fontMetrics.top);
        this.f19040l = fCeil;
        this.f19041m = (-(fCeil / 2)) - fontMetrics.top;
        paint.measureText("yyyy年M月");
        nk.l.o(1, 16.0f);
        this.f19042n = nk.l.o(1, 4.0f);
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        C1 c1N;
        C2702d c2702dE;
        C2741q c2741q = this.f19045q;
        if (c2741q == null || (c1N = c2741q.n()) == null || (c2702dE = c2741q.e(b())) == null) {
            return;
        }
        float fX = c2702dE.x() + this.f19041m;
        for (A1 a10 : c1N.h()) {
            Canvas canvas2 = canvas;
            canvas2.drawLine(a10.c(), c2702dE.z(), a10.c(), this.f19042n + c2702dE.z(), this.f19044p);
            canvas2.drawText(a10.a().format(new Date(a10.b())), a10.c(), fX, this.f19043o);
            canvas = canvas2;
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
        this.f19045q = c2741qB;
        if (c2741qB.e(b()) == null || c2741qB.m(c()) == null) {
            return;
        }
        Paint paint = this.f19043o;
        paint.setAntiAlias(true);
        paint.setTextAlign(Paint.Align.CENTER);
        paint.setColor(aVar.u(5));
        Paint paint2 = this.f19044p;
        paint2.setStyle(Paint.Style.STROKE);
        paint2.setAntiAlias(false);
        paint2.setColor(aVar.g(5));
    }
}
