package fk;

import Rj.AbstractC2744r0;
import Rj.AbstractC2755v;
import Rj.AbstractC2759w0;
import Rj.C2702d;
import Rj.C2732n;
import android.graphics.Canvas;
import android.graphics.DashPathEffect;
import android.graphics.Paint;
import android.graphics.Path;
import gk.AbstractC7467h0;

/* JADX INFO: loaded from: classes7.dex */
public final class E extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final ak.h f95036l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final p292ng.c f95037m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final Path f95038n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final Paint f95039o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final Paint f95040p;

    public E(p292ng.c cVar, C2732n c2732n, String str) {
        super(c2732n, str);
        this.f95038n = new Path();
        this.f95039o = new Paint();
        this.f95040p = new Paint();
        this.f95036l = new ak.h(c2732n.b(), this, null, 4, null);
        this.f95037m = cVar;
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        C2702d c2702dD;
        AbstractC2759w0 abstractC2759w0J = j().j();
        if (abstractC2759w0J == null || (c2702dD = j().d()) == null) {
            return;
        }
        float fS = abstractC2759w0J.S(((Number) this.f95037m.d()).doubleValue());
        float fS2 = abstractC2759w0J.S(((Number) this.f95037m.g()).doubleValue());
        canvas.drawRect(c2702dD.u(), abstractC2759w0J.P(((Number) this.f95037m.g()).doubleValue()), c2702dD.y(), abstractC2759w0J.P(((Number) this.f95037m.d()).doubleValue()), this.f95039o);
        this.f95038n.reset();
        if (abstractC2759w0J.u() >= ((Number) this.f95037m.g()).doubleValue()) {
            this.f95038n.moveTo(c2702dD.u(), fS2);
            this.f95038n.lineTo(c2702dD.y(), fS2);
            canvas.drawPath(this.f95038n, this.f95040p);
        }
        if (abstractC2759w0J.v() <= ((Number) this.f95037m.d()).doubleValue()) {
            this.f95038n.moveTo(c2702dD.u(), fS);
            this.f95038n.lineTo(c2702dD.y(), fS);
            canvas.drawPath(this.f95038n, this.f95040p);
        }
    }

    @Override // Rj.AbstractC2744r0
    public ak.h j() {
        return this.f95036l;
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        if (aVar == null) {
            return;
        }
        AbstractC2755v abstractC2755vQ = q();
        if ((abstractC2755vQ instanceof AbstractC7467h0 ? (AbstractC7467h0) abstractC2755vQ : null) == null) {
            return;
        }
        Paint paint = this.f95039o;
        paint.setStyle(Paint.Style.FILL);
        paint.setColor(aVar.d(".rangeTint.content"));
        DashPathEffect dashPathEffect = new DashPathEffect(new float[]{10.0f, 8.0f}, 0.0f);
        Paint paint2 = this.f95040p;
        paint2.setAntiAlias(false);
        paint2.setStyle(Paint.Style.STROKE);
        paint2.setColor(aVar.d(".drawing.line"));
        paint2.setPathEffect(dashPathEffect);
    }
}
