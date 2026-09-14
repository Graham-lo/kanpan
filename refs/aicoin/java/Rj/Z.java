package Rj;

import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import gk.C7488s0;
import java.util.Iterator;
import sp.aicoin_kline.chart.data.LiQuiLineItem;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class Z extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public Paint f19291l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public Paint f19292m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final Paint f19293n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final int f19294o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final float f19295p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public C7488s0 f19296q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final int f19297r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public final int f19298s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public final float f19299t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public final float f19300u;

    public Z(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f19291l = new Paint();
        this.f19292m = new Paint();
        Paint paint = new Paint();
        this.f19293n = paint;
        this.f19297r = Color.parseColor("#E99F27");
        this.f19298s = Color.parseColor("#FFF1F0");
        int color = Color.parseColor("#E99F27");
        this.f19299t = 4.0f;
        this.f19300u = Xj.a.b(4);
        paint.setAntiAlias(true);
        paint.setStyle(Paint.Style.FILL);
        paint.setTextAlign(Paint.Align.CENTER);
        paint.setColor(color);
        paint.setTextSize(nk.l.p(KLineManager.f142490O.a().i(), 2, 9.0f));
        Paint.FontMetrics fontMetrics = paint.getFontMetrics();
        this.f19294o = (int) Math.ceil(fontMetrics.bottom - fontMetrics.top);
        this.f19295p = (-(((float) Math.ceil(fontMetrics.bottom - fontMetrics.top)) / 2)) - fontMetrics.top;
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        C2741q c2741qB;
        C2702d c2702dE;
        String strF;
        AbstractC2759w0 abstractC2759w0L;
        C7488s0 c7488s0;
        if (!KLineManager.f142490O.a().a0() || (c2702dE = (c2741qB = i().b()).e(b())) == null || (strF = f()) == null || (abstractC2759w0L = c2741qB.l(strF)) == null || (c7488s0 = this.f19296q) == null || abstractC2759w0L.z() == 0.0d || c7488s0.s().isEmpty()) {
            return;
        }
        int iU = c2702dE.u();
        int iY = c2702dE.y();
        Iterator it = c7488s0.s().iterator();
        while (it.hasNext()) {
            try {
                Double dN = Ah.v.n(((LiQuiLineItem) it.next()).getPrice());
                if (dN != null) {
                    double dDoubleValue = dN.doubleValue();
                    if (dDoubleValue <= abstractC2759w0L.u() && dDoubleValue >= abstractC2759w0L.v()) {
                        float fP = abstractC2759w0L.P(dDoubleValue);
                        float f10 = this.f19294o >> 1;
                        float f11 = this.f19299t;
                        float f12 = (fP - f10) - f11;
                        float f13 = f10 + fP + f11;
                        nk.l lVar = nk.l.f134222a;
                        String strT = lVar.t(lVar.j(dDoubleValue, AbstractC2735o.a(i())));
                        RectF rectF = new RectF(iU, f12, iY, f13);
                        float f14 = this.f19300u;
                        canvas.drawRoundRect(rectF, f14, f14, this.f19291l);
                        float f15 = this.f19300u;
                        canvas.drawRoundRect(rectF, f15, f15, this.f19292m);
                        canvas.drawText(strT, c2702dE.q(), fP + this.f19295p, this.f19293n);
                    }
                }
            } catch (Exception unused) {
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
        Paint paint = new Paint();
        paint.setStyle(Paint.Style.FILL);
        paint.setAntiAlias(true);
        paint.setColor(this.f19298s);
        this.f19291l = paint;
        Paint paint2 = new Paint();
        paint2.setStyle(Paint.Style.STROKE);
        paint2.setAntiAlias(true);
        paint2.setColor(this.f19297r);
        paint2.setStrokeWidth(2.0f);
        this.f19292m = paint2;
        AbstractC2755v abstractC2755vQ = q();
        this.f19296q = abstractC2755vQ instanceof C7488s0 ? (C7488s0) abstractC2755vQ : null;
    }
}
