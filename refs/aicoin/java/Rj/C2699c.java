package Rj;

import android.graphics.Canvas;
import android.graphics.Paint;

/* JADX INFO: renamed from: Rj.c, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2699c extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final Paint f19334l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Paint f19335m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final Paint f19336n;

    public C2699c(C2732n c2732n, String str) {
        super(c2732n, str);
        Paint paint = new Paint();
        this.f19334l = paint;
        Paint paint2 = new Paint();
        this.f19335m = paint2;
        Paint paint3 = new Paint();
        this.f19336n = paint3;
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
        AbstractC2759w0 abstractC2759w0J;
        Paint paint;
        C2765z c2765zH = j().i().h(c());
        if (c2765zH == null) {
            return;
        }
        Sj.a aVarC = c2765zH.C();
        y1 y1VarK = j().k();
        if (y1VarK == null || (abstractC2759w0J = j().j()) == null) {
            return;
        }
        int iD = c2765zH.D() - 1;
        int iF = p292ng.i.f(y1VarK.r(), 0);
        int iK = p292ng.i.k(y1VarK.q(), aVarC.size());
        if (iF >= aVarC.size() || iF >= iK) {
            return;
        }
        float fU = y1VarK.u();
        float fJ = (fU / 2) - y1VarK.J();
        while (iF < iK) {
            Sj.b bVarD = (Sj.b) Sf.z.r0(aVarC, iF);
            if (bVarD != null) {
                if (iF == iD) {
                    bVarD = nk.c.f134195a.d(bVarD);
                }
                float fS = abstractC2759w0J.S(bVarD.b());
                float fS2 = abstractC2759w0J.S(bVarD.c());
                float fS3 = abstractC2759w0J.S(bVarD.d());
                float fS4 = abstractC2759w0J.S(bVarD.a());
                float fU2 = y1VarK.u() * 0.35f;
                if (bVarD.a() > bVarD.d()) {
                    paint = this.f19334l;
                } else {
                    paint = (bVarD.a() != bVarD.d() && bVarD.a() < bVarD.d()) ? this.f19335m : this.f19336n;
                }
                Paint paint2 = paint;
                float f10 = fJ;
                canvas.drawLine(fJ, fS, f10, fS2, paint2);
                canvas.drawLine(fJ - fU2, fS3, f10, fS3, paint2);
                canvas.drawLine(f10, fS4, f10 + fU2, fS4, paint2);
                fJ = f10 + fU;
            }
            iF++;
            aVarC = aVarC;
            iD = iD;
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
        this.f19334l.setColor(aVar.r());
        this.f19335m.setColor(aVar.m());
        this.f19336n.setColor(aVar.m());
    }
}
