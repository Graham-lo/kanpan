package Rj;

import android.graphics.Canvas;
import android.graphics.Paint;
import gk.AbstractC7467h0;

/* JADX INFO: loaded from: classes7.dex */
public final class D0 extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final Paint f19067l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public y1 f19068m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public AbstractC2759w0 f19069n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public AbstractC7467h0 f19070o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public float f19071p;

    public D0(C2732n c2732n, String str) {
        super(c2732n, str);
        Paint paint = new Paint();
        this.f19067l = paint;
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(3.0f);
        paint.setAntiAlias(true);
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        AbstractC2759w0 abstractC2759w0;
        AbstractC7467h0 abstractC7467h0;
        y1 y1Var = this.f19068m;
        if (y1Var == null || (abstractC2759w0 = this.f19069n) == null || (abstractC7467h0 = this.f19070o) == null || abstractC2759w0.z() == 0.0d) {
            return;
        }
        double[] dArr = abstractC7467h0.v()[0];
        if (dArr.length != 0 && abstractC7467h0.x().r()[0].b()) {
            float fU = y1Var.u();
            int iQ = y1Var.q();
            float fU2 = (y1Var.u() / 2) - y1Var.J();
            for (int iR = y1Var.r(); iR < iQ; iR++) {
                double d10 = dArr[iR];
                float fS = abstractC2759w0.S(d10);
                if (!Double.isNaN(d10)) {
                    canvas.drawCircle(fU2, fS, this.f19071p, this.f19067l);
                }
                fU2 += fU;
            }
        }
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        ek.m[] mVarArrK;
        ek.m mVar;
        if (aVar == null) {
            return;
        }
        C2741q c2741qB = i().b();
        c2741qB.e(b());
        this.f19068m = c2741qB.m(c());
        this.f19069n = c2741qB.l(b());
        AbstractC2755v abstractC2755vQ = q();
        if (abstractC2755vQ != null && (abstractC2755vQ instanceof AbstractC7467h0)) {
            this.f19070o = (AbstractC7467h0) abstractC2755vQ;
        }
        AbstractC7467h0 abstractC7467h0 = this.f19070o;
        sp.aicoin_kline.core.indicator.config.F fX = abstractC7467h0 != null ? abstractC7467h0.x() : null;
        this.f19067l.setColor((fX == null || (mVarArrK = fX.k()) == null || (mVar = mVarArrK[0]) == null) ? aVar.b(0) : mVar.a());
        this.f19071p = nk.l.o(1, 2.0f);
    }
}
