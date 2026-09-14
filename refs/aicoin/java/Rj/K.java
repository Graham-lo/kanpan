package Rj;

import android.graphics.Canvas;
import android.graphics.Paint;

/* JADX INFO: loaded from: classes7.dex */
public final class K extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final Paint f19162l;

    public K(C2732n c2732n, String str) {
        super(c2732n, str);
        Paint paint = new Paint();
        this.f19162l = paint;
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(2.0f);
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        y1 y1VarM;
        C2741q c2741qB = i().b();
        C2702d c2702dE = c2741qB.e(b());
        if (c2702dE == null || (y1VarM = c2741qB.m(c())) == null) {
            return;
        }
        float fO = y1VarM.o();
        if (c2702dE.m(fO)) {
            canvas.drawLine(c2702dE.u(), fO, c2702dE.y(), fO, this.f19162l);
        }
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        this.f19162l.setColor(aVar.h());
    }
}
