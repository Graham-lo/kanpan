package Rj;

import android.graphics.Canvas;
import android.graphics.Paint;

/* JADX INFO: loaded from: classes7.dex */
public class F0 extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final Paint f19105l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public Paint f19106m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public boolean f19107n;

    public F0(C2732n c2732n, String str) {
        super(c2732n, str);
        Paint paint = new Paint();
        this.f19105l = paint;
        this.f19107n = true;
        Paint.Style style = Paint.Style.FILL;
        paint.setStyle(style);
        Paint paint2 = new Paint();
        this.f19106m = paint2;
        paint2.setStyle(style);
        this.f19106m.setStrokeWidth(2.0f);
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        C2702d c2702dE;
        G gI;
        String strB;
        C2741q c2741qB = i().b();
        y1 y1VarM = c2741qB.m(c());
        if (y1VarM == null || (c2702dE = c2741qB.e(b())) == null || (gI = c2741qB.i(c())) == null) {
            return;
        }
        if (nk.n.f(13)) {
            if (gI.B() && (strB = b()) != null && Ah.x.y(strB, ".main", false, 2, null)) {
                float fU = gI.u();
                canvas.drawLine(fU, c2702dE.z(), fU, c2702dE.p(), this.f19106m);
                return;
            }
            return;
        }
        if (y1VarM.D() < 0) {
            return;
        }
        float fC = y1.C(y1VarM, 0, 1, null);
        if (c2702dE.l(fC)) {
            int iZ = c2702dE.z();
            String strB2 = b();
            if (strB2 != null) {
                Ah.x.y(strB2, ".main", false, 2, null);
            }
            if (y1VarM.o() > 0.0f) {
                canvas.drawLine(fC, iZ, fC, c2702dE.p(), this.f19106m);
            } else if (y1VarM.E()) {
                canvas.drawLine(fC, iZ, fC, c2702dE.p(), this.f19105l);
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
        this.f19105l.setColor(aVar.t());
        this.f19106m.setColor(aVar.h());
    }

    public final Paint v() {
        return this.f19106m;
    }

    public final Paint w() {
        return this.f19105l;
    }

    public final void x(boolean z10) {
        this.f19107n = z10;
    }
}
