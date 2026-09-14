package Rj;

import android.graphics.Canvas;
import android.graphics.Paint;
import java.util.ArrayList;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class H1 extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final Paint f19143l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Paint f19144m;

    public H1(C2732n c2732n, String str) {
        super(c2732n, str);
        Paint paint = new Paint();
        this.f19143l = paint;
        Paint paint2 = new Paint();
        this.f19144m = paint2;
        if (KLineManager.f142490O.a().q(9) == 0) {
            paint.setStyle(Paint.Style.FILL);
        } else {
            paint.setStyle(Paint.Style.STROKE);
        }
        paint2.setStyle(Paint.Style.FILL);
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        AbstractC2755v abstractC2755vG;
        ArrayList arrayListS;
        C2741q c2741qB = i().b();
        C2702d c2702dE = c2741qB.e(b());
        y1 y1VarM = c2741qB.m(c());
        AbstractC2759w0 abstractC2759w0L = c2741qB.l(b());
        if (c2702dE == null || y1VarM == null || abstractC2759w0L == null || abstractC2759w0L.z() == 0.0d || (abstractC2755vG = c2741qB.g(d())) == null || (arrayListS = ((G1) abstractC2755vG).s()) == null || arrayListS.isEmpty()) {
            return;
        }
        int iF = p292ng.i.f(y1VarM.r(), 0);
        int iK = p292ng.i.k(y1VarM.y(), arrayListS.size());
        if (iF >= arrayListS.size() || iF >= iK) {
            return;
        }
        float fU = y1VarM.u();
        float fJ = (fU / 6) - y1VarM.J();
        float f10 = ((2 * fU) / 3) + fJ;
        float fS = abstractC2759w0L.S(0.0d);
        float f11 = fJ;
        while (iF < iK) {
            Sj.b bVar = (Sj.b) Sf.z.r0(arrayListS, iF);
            if (bVar != null) {
                float fS2 = abstractC2759w0L.S(bVar.f());
                Paint paint = (Paint) p162hb.e.c(bVar.a() >= bVar.d(), this.f19143l, this.f19144m);
                if (!Double.isNaN(bVar.f())) {
                    float f12 = f10 - 1;
                    if (Math.abs(fS - fS2) < 1.0f) {
                        paint.setStrokeWidth(2.0f);
                        canvas.drawLine(f11, fS, f12, fS, paint);
                    } else {
                        paint.setStrokeWidth(1.0f);
                        float f13 = fS;
                        nk.y.a(canvas, f11, fS2, f12, f13, paint);
                        fS = f13;
                    }
                }
                f11 += fU;
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
        Paint paint = this.f19143l;
        paint.setColor(aVar.r());
        paint.setStrokeWidth(2.0f);
        this.f19144m.setColor(aVar.m());
    }
}
