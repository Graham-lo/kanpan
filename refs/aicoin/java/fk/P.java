package fk;

import Rj.AbstractC2744r0;
import Rj.AbstractC2755v;
import Rj.AbstractC2759w0;
import Rj.C2702d;
import Rj.C2732n;
import Sf.AbstractC2801o;
import android.graphics.Canvas;
import android.graphics.DashPathEffect;
import android.graphics.Paint;
import android.graphics.Path;
import gk.AbstractC7467h0;

/* JADX INFO: loaded from: classes7.dex */
public final class P extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final ak.h f95123l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Path f95124m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final Paint f95125n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public sp.aicoin_kline.core.indicator.config.F f95126o;

    public P(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f95123l = new ak.h(c2732n.b(), this, null, 4, null);
        this.f95124m = new Path();
        Paint paint = new Paint(1);
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeCap(Paint.Cap.ROUND);
        this.f95125n = paint;
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        C2702d c2702dD;
        AbstractC2759w0 abstractC2759w0J;
        ek.w wVar;
        sp.aicoin_kline.core.indicator.config.F f10 = this.f95126o;
        if (f10 == null) {
            return;
        }
        sp.aicoin_kline.core.indicator.config.V v10 = f10 instanceof sp.aicoin_kline.core.indicator.config.V ? (sp.aicoin_kline.core.indicator.config.V) f10 : null;
        if ((v10 != null && v10.E()) || (c2702dD = j().d()) == null || (abstractC2759w0J = j().j()) == null || (wVar = (ek.w) AbstractC2801o.r0(f10.l(), 3)) == null) {
            return;
        }
        float fS = abstractC2759w0J.S(wVar.g());
        if (Float.isNaN(fS) || fS < c2702dD.z() - 1 || fS > c2702dD.p() + 1) {
            return;
        }
        this.f95125n.setColor(-683264);
        this.f95125n.setStrokeWidth(2.0f);
        this.f95125n.setPathEffect(new DashPathEffect(new float[]{Xj.a.a(8.0f), Xj.a.a(4.0f)}, 0.0f));
        float fU = c2702dD.u();
        float fY = c2702dD.y();
        this.f95124m.reset();
        this.f95124m.moveTo(fU, fS);
        this.f95124m.lineTo(fY, fS);
        canvas.drawPath(this.f95124m, this.f95125n);
    }

    @Override // Rj.AbstractC2744r0
    public ak.h j() {
        return this.f95123l;
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        AbstractC2755v abstractC2755vQ = q();
        AbstractC7467h0 abstractC7467h0 = abstractC2755vQ instanceof AbstractC7467h0 ? (AbstractC7467h0) abstractC2755vQ : null;
        if (abstractC7467h0 == null) {
            return;
        }
        this.f95126o = abstractC7467h0.x();
        this.f95125n.setColor(-683264);
        this.f95125n.setStrokeWidth(2.0f);
        this.f95125n.setPathEffect(new DashPathEffect(new float[]{Xj.a.a(8.0f), Xj.a.a(4.0f)}, 0.0f));
    }
}
