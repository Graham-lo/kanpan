package Rj;

import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import java.util.Iterator;
import kotlin.jvm.internal.DefaultConstructorMarker;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class K1 extends AbstractC2744r0 {

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public static final int f19176u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public static final int f19177v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public static final int f19178w;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public static final int f19179x;

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public Paint f19180l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public Paint f19181m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final Paint f19182n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final int f19183o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final float f19184p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final KLineManager f19185q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public boolean f19186r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public int f19187s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public final sp.aicoin_kline.core.indicator.config.F f19188t;

    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    static {
        new a(null);
        f19176u = Color.parseColor("#FFB7BFC8");
        f19177v = Color.parseColor("#515A66");
        f19178w = Color.parseColor("#FF7A8899");
        f19179x = Color.parseColor("#FF667180");
    }

    public K1(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f19180l = new Paint();
        this.f19181m = new Paint();
        KLineManager.a aVar = KLineManager.f142490O;
        this.f19185q = aVar.a();
        this.f19186r = true;
        this.f19187s = Color.parseColor("#FF25282B");
        Paint paint = new Paint();
        this.f19182n = paint;
        paint.setAntiAlias(true);
        paint.setStyle(Paint.Style.FILL);
        paint.setTextAlign(Paint.Align.CENTER);
        paint.setColor(Color.parseColor("#7A8899"));
        paint.setTextSize(nk.l.p(aVar.a().i(), 2, 9.0f));
        Paint.FontMetrics fontMetrics = paint.getFontMetrics();
        this.f19183o = (int) Math.ceil(fontMetrics.bottom - fontMetrics.top);
        this.f19184p = (-(((float) Math.ceil(fontMetrics.bottom - fontMetrics.top)) / 2)) - fontMetrics.top;
        nk.l.o(1, 1.0f);
        nk.l.o(1, 2.0f);
        this.f19188t = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get("vpvr");
    }

    /* JADX WARN: Code duplicated, block: B:50:0x00fc  */
    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        String strF;
        Canvas canvas2;
        C2741q c2741qB = i().b();
        C2702d c2702dE = c2741qB.e(b());
        if (c2702dE == null || (strF = f()) == null) {
            return;
        }
        sp.aicoin_kline.core.indicator.config.F f10 = this.f19188t;
        if (f10 != null) {
            this.f19186r = f10.r()[0].b();
        }
        AbstractC2759w0 abstractC2759w0L = c2741qB.l(strF);
        if (abstractC2759w0L == null || abstractC2759w0L.z() == 0.0d) {
            return;
        }
        int iU = c2702dE.u();
        int iY = c2702dE.y();
        Xj.c cVar = Xj.c.f25377a;
        if (cVar.g() && this.f19185q.d0()) {
            boolean z10 = this.f19185q.f0() == 1;
            int i10 = z10 ? f19176u : f19177v;
            int i11 = z10 ? f19178w : f19179x;
            Iterator it = cVar.e().iterator();
            while (it.hasNext()) {
                double dDoubleValue = ((Number) it.next()).doubleValue();
                if (dDoubleValue > 0.0d) {
                    v(canvas, abstractC2759w0L, c2702dE, dDoubleValue, i10);
                }
            }
            if (this.f19186r) {
                canvas2 = canvas;
            } else {
                Xj.c cVar2 = Xj.c.f25377a;
                if (cVar2.c() > 0.0d) {
                    float fP = abstractC2759w0L.P(cVar2.c());
                    float f11 = this.f19183o >> 1;
                    float f12 = fP - f11;
                    float f13 = fP + f11;
                    this.f19182n.setColor(Color.parseColor("#3B87EB"));
                    Paint paint = this.f19181m;
                    if (paint != null) {
                        paint.setColor(this.f19187s);
                    }
                    Paint paint2 = this.f19181m;
                    if (paint2 != null) {
                        canvas.drawRect(iU, f12, iY, f13, paint2);
                    }
                    canvas2 = canvas;
                    canvas2.drawText(nk.A.b(cVar2.c(), KLineManager.f142490O.a().j()), c2702dE.q(), fP + this.f19184p, this.f19182n);
                } else {
                    canvas2 = canvas;
                }
            }
            v(canvas2, abstractC2759w0L, c2702dE, Xj.c.f25377a.f(), i11);
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
        Paint paint = new Paint();
        Paint.Style style = Paint.Style.FILL;
        paint.setStyle(style);
        paint.setColor(aVar.s());
        paint.setAntiAlias(true);
        this.f19180l = paint;
        this.f19187s = aVar.s();
        Paint paint2 = new Paint();
        paint2.setStyle(style);
        paint2.setColor(aVar.s());
        paint2.setAntiAlias(true);
        this.f19181m = paint2;
    }

    public final void v(Canvas canvas, AbstractC2759w0 abstractC2759w0, C2702d c2702d, double d10, int i10) {
        if (d10 <= 0.0d) {
            return;
        }
        float fP = abstractC2759w0.P(d10);
        float f10 = this.f19183o >> 1;
        this.f19182n.setColor(-1);
        this.f19180l.setColor(i10);
        canvas.drawRect(c2702d.u(), fP - f10, c2702d.y(), fP + f10, this.f19180l);
        canvas.drawText(nk.A.b(d10, KLineManager.f142490O.a().j()), c2702d.q(), fP + this.f19184p, this.f19182n);
    }
}
