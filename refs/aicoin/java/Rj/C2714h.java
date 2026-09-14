package Rj;

import android.graphics.Canvas;
import android.graphics.Paint;
import java.util.ArrayList;

/* JADX INFO: renamed from: Rj.h, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2714h extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final Paint f19414l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Paint f19415m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final Paint f19416n;

    public C2714h(C2732n c2732n, String str) {
        super(c2732n, str);
        Paint paint = new Paint();
        this.f19414l = paint;
        Paint paint2 = new Paint();
        this.f19415m = paint2;
        Paint paint3 = new Paint();
        this.f19416n = paint3;
        paint.setStrokeWidth(2.0f);
        Paint.Style style = Paint.Style.FILL;
        paint.setStyle(style);
        paint2.setStrokeWidth(2.0f);
        paint2.setStyle(style);
        paint3.setStrokeWidth(2.0f);
        paint3.setStyle(style);
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        C2765z c2765zH;
        y1 y1VarK;
        AbstractC2759w0 abstractC2759w0J;
        AbstractC2755v abstractC2755vG = j().g();
        AbstractC2720j abstractC2720j = abstractC2755vG instanceof AbstractC2720j ? (AbstractC2720j) abstractC2755vG : null;
        if (abstractC2720j == null || (c2765zH = j().i().h(c())) == null || (y1VarK = j().k()) == null || (abstractC2759w0J = j().j()) == null) {
            return;
        }
        int iD = c2765zH.D() - 1;
        ArrayList arrayListS = abstractC2720j.s();
        if (arrayListS == null) {
            return;
        }
        int iF = p292ng.i.f(y1VarK.r(), 0);
        int iK = p292ng.i.k(y1VarK.q(), arrayListS.size());
        if (iF >= arrayListS.size() || iF >= iK) {
            return;
        }
        float fU = y1VarK.u();
        float fJ = (fU / 2) - y1VarK.J();
        while (iF < iK) {
            Sj.b bVarD = (Sj.b) Sf.z.r0(arrayListS, iF);
            if (bVarD != null) {
                if (iF == iD) {
                    bVarD = nk.c.f134195a.d(bVarD);
                }
                float fS = abstractC2759w0J.S(bVarD.b());
                float fS2 = abstractC2759w0J.S(bVarD.c());
                if (bVarD.a() > bVarD.d()) {
                    canvas.drawLine(fJ, fS, fJ, fS2, this.f19414l);
                } else if (bVarD.a() == bVarD.d()) {
                    canvas.drawLine(fJ, fS, fJ, fS2, this.f19416n);
                } else if (bVarD.a() < bVarD.d()) {
                    canvas.drawLine(fJ, fS, fJ, fS2, this.f19415m);
                }
                fJ += fU;
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
        this.f19414l.setColor(aVar.q());
        this.f19415m.setColor(aVar.l());
        this.f19416n.setColor(aVar.l());
    }
}
