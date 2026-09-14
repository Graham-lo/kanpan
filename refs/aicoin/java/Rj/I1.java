package Rj;

import android.graphics.Canvas;
import android.graphics.Paint;
import java.util.ArrayList;

/* JADX INFO: loaded from: classes7.dex */
public final class I1 extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final Paint f19148l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Paint f19149m;

    public I1(C2732n c2732n, String str) {
        super(c2732n, str);
        Paint paint = new Paint();
        this.f19148l = paint;
        Paint paint2 = new Paint();
        this.f19149m = paint2;
        Paint.Style style = Paint.Style.FILL;
        paint.setStyle(style);
        paint.setStrokeWidth(2.0f);
        paint2.setStyle(style);
        paint2.setStrokeWidth(2.0f);
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        ArrayList arrayListS;
        C2741q c2741qB = i().b();
        C2702d c2702dE = c2741qB.e(b());
        y1 y1VarM = c2741qB.m(c());
        AbstractC2759w0 abstractC2759w0L = c2741qB.l(b());
        if (c2702dE == null || y1VarM == null || abstractC2759w0L == null || abstractC2759w0L.z() == 0.0d) {
            return;
        }
        AbstractC2755v abstractC2755vG = c2741qB.g(d());
        G1 g10 = abstractC2755vG instanceof G1 ? (G1) abstractC2755vG : null;
        if (g10 == null || (arrayListS = g10.s()) == null) {
            return;
        }
        float fU = y1VarM.u();
        int iF = p292ng.i.f(y1VarM.r(), 0);
        int iK = p292ng.i.k(y1VarM.q(), arrayListS.size());
        if (iF >= arrayListS.size() || iF >= iK) {
            return;
        }
        float fJ = (fU / 2) - y1VarM.J();
        float fS = abstractC2759w0L.S(0.0d);
        float f10 = fJ;
        while (iF < iK) {
            Sj.b bVar = (Sj.b) Sf.z.r0(arrayListS, iF);
            if (bVar != null) {
                float fS2 = abstractC2759w0L.S(bVar.f());
                if (bVar.a() > bVar.d()) {
                    canvas.drawLine(f10, fS2, f10, fS, this.f19148l);
                } else {
                    canvas.drawLine(f10, fS2, f10, fS, this.f19149m);
                }
                f10 += fU;
            }
            iF++;
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
        this.f19148l.setColor(aVar.r());
        this.f19149m.setColor(aVar.m());
    }
}
