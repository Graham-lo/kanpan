package Rj;

import android.graphics.Canvas;
import android.graphics.Paint;
import java.util.Iterator;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
public final class J extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final Paint f19150l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public Paint f19151m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public boolean f19152n;

    public J(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f19150l = new Paint();
        this.f19151m = new Paint();
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        AbstractC2759w0 abstractC2759w0L;
        C2741q c2741qB = i().b();
        C2702d c2702dE = c2741qB.e(b());
        if (c2702dE == null || (abstractC2759w0L = c2741qB.l(b())) == null || c2741qB.n() == null || abstractC2759w0L.z() == 0.0d) {
            return;
        }
        boolean z10 = abstractC2759w0L instanceof C2742q0;
        if (this.f19152n) {
            int iU = c2702dE.u();
            int iY = c2702dE.y();
            c2702dE.z();
            c2702dE.p();
            Iterator it = abstractC2759w0L.p().iterator();
            while (it.hasNext()) {
                float fS = abstractC2759w0L.S(((Number) it.next()).doubleValue());
                canvas.drawLine(iU, fS, iY, fS, (AbstractC7609s.f(nk.l.k(nk.l.f134222a, Math.abs(abstractC2759w0L.R(fS)), 2, null, 4, null), "0.00") && z10) ? this.f19151m : this.f19150l);
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
        this.f19152n = nk.n.f(8);
        Paint paint = this.f19150l;
        paint.setStrokeWidth(1.0f);
        paint.setStyle(Paint.Style.STROKE);
        paint.setColor(aVar.g(1));
        Paint paint2 = new Paint(this.f19150l);
        paint2.setColor(aVar.d("value_indicator_line_color_0"));
        this.f19151m = paint2;
    }
}
