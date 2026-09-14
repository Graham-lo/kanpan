package Rj;

import android.graphics.Canvas;
import android.graphics.Paint;
import gk.C7458d;
import java.util.List;
import sp.aicoin_kline.chart.data.AIHandleLineItem;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: Rj.s0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2747s0 extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public Paint f19543l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Paint f19544m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final int f19545n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final float f19546o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public int f19547p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public int f19548q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final float f19549r;

    public C2747s0(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f19543l = new Paint();
        Paint paint = new Paint();
        this.f19544m = paint;
        this.f19547p = -65536;
        this.f19548q = -16711936;
        this.f19549r = 6.0f;
        paint.setAntiAlias(true);
        paint.setStyle(Paint.Style.FILL);
        paint.setTextAlign(Paint.Align.CENTER);
        paint.setColor(-1);
        paint.setTextSize(nk.l.p(KLineManager.f142490O.a().i(), 2, 9.0f));
        Paint.FontMetrics fontMetrics = paint.getFontMetrics();
        this.f19545n = (int) Math.ceil(fontMetrics.bottom - fontMetrics.top);
        this.f19546o = (-(((float) Math.ceil(fontMetrics.bottom - fontMetrics.top)) / 2)) - fontMetrics.top;
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        C2741q c2741qB;
        C2702d c2702dE;
        String strF;
        AbstractC2759w0 abstractC2759w0L;
        Double dN;
        if (!KLineManager.f142490O.a().c0() || (c2702dE = (c2741qB = i().b()).e(b())) == null || (strF = f()) == null || (abstractC2759w0L = c2741qB.l(strF)) == null || abstractC2759w0L.z() == 0.0d) {
            return;
        }
        int iU = c2702dE.u();
        int iY = c2702dE.y();
        List<AIHandleLineItem> listA = Xj.b.f25375a.a();
        if (listA == null) {
            return;
        }
        for (AIHandleLineItem aIHandleLineItem : listA) {
            String price = aIHandleLineItem.getPrice();
            if (price != null && (dN = Ah.v.n(price)) != null) {
                double dDoubleValue = dN.doubleValue();
                if (dDoubleValue <= abstractC2759w0L.u()) {
                    if (dDoubleValue >= abstractC2759w0L.v()) {
                        this.f19543l.setColor(aIHandleLineItem.isBids() ? this.f19548q : this.f19547p);
                        float fP = abstractC2759w0L.P(dDoubleValue);
                        float f10 = this.f19545n >> 1;
                        nk.l lVar = nk.l.f134222a;
                        String strT = lVar.t(lVar.j(dDoubleValue, AbstractC2735o.a(i())));
                        Paint paint = this.f19543l;
                        float f11 = this.f19549r;
                        canvas.drawRect(iU, (fP - f10) - f11, iY, f10 + fP + f11, paint);
                        canvas.drawText(strT, c2702dE.q(), fP + this.f19546o, this.f19544m);
                    }
                }
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
        this.f19543l = paint;
        KLineManager.a aVar2 = KLineManager.f142490O;
        this.f19548q = aVar.d(aVar2.a().V() ? ".main_red.color" : ".main_green.color");
        this.f19547p = aVar.d(aVar2.a().V() ? ".main_green.color" : ".main_red.color");
        boolean z10 = q() instanceof C7458d;
    }
}
