package bk;

import Rj.AbstractC2720j;
import Rj.AbstractC2744r0;
import Rj.AbstractC2755v;
import Rj.AbstractC2759w0;
import Rj.C2702d;
import Rj.C2732n;
import Rj.C2741q;
import Rj.C2765z;
import Rj.y1;
import Sf.z;
import Sj.b;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import java.util.ArrayList;
import nk.c;
import nk.n;
import p292ng.i;

/* JADX INFO: loaded from: classes7.dex */
public final class a extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public boolean f74058l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Paint f74059m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final Paint f74060n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final Path f74061o;

    public a(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f74058l = true;
        Paint paint = new Paint();
        this.f74059m = paint;
        this.f74061o = new Path();
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(2.0f);
        paint.setAntiAlias(true);
        Paint paint2 = new Paint(1);
        this.f74060n = paint2;
        paint2.setStyle(Paint.Style.FILL);
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        y1 y1VarM;
        AbstractC2759w0 abstractC2759w0L;
        C2765z c2765zH;
        ArrayList arrayListS;
        C2741q c2741qB = i().b();
        C2702d c2702dE = c2741qB.e(b());
        if (c2702dE == null || (y1VarM = c2741qB.m(c())) == null || (abstractC2759w0L = c2741qB.l(b())) == null || (c2765zH = c2741qB.h(c())) == null) {
            return;
        }
        int iD = c2765zH.D() - 1;
        AbstractC2755v abstractC2755vG = c2741qB.g(d());
        if (abstractC2755vG == null || (arrayListS = ((AbstractC2720j) abstractC2755vG).s()) == null) {
            return;
        }
        int iF = i.f(y1VarM.r(), 0);
        int iK = i.k(y1VarM.q(), arrayListS.size());
        if (iF >= arrayListS.size() || iF >= iK) {
            return;
        }
        float fU = y1VarM.u();
        float fU2 = (y1VarM.u() / 2) - y1VarM.J();
        b bVar = (b) z.r0(arrayListS, iF);
        if (bVar != null) {
            float fS = abstractC2759w0L.S(bVar.a());
            float fZ = n.f(19) ? c2702dE.z() : c2702dE.p();
            this.f74061o.reset();
            this.f74061o.moveTo(fU2, fZ);
            this.f74061o.lineTo(fU2, fS);
            float f10 = 0.0f;
            float f11 = fU2;
            float f12 = f11;
            float f13 = fS;
            while (iF < iK) {
                b bVarD = (b) z.r0(arrayListS, iF);
                if (bVarD != null) {
                    if (iF == iD) {
                        bVarD = c.f134195a.d(bVarD);
                    }
                    float fS2 = abstractC2759w0L.S(bVarD.a());
                    if (!Float.isNaN(fS2)) {
                        this.f74061o.lineTo(f12, fS2);
                        f10 = f12;
                    }
                    canvas.drawLine(f11, f13, f12, fS2, this.f74059m);
                    f11 = f12;
                    f13 = fS2;
                    f12 += fU;
                }
                iF++;
                iD = iD;
            }
            this.f74061o.lineTo(f10, fZ);
            this.f74061o.close();
            if (this.f74058l) {
                canvas.drawPath(this.f74061o, this.f74060n);
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
        this.f74059m.setColor(aVar.e());
        this.f74060n.setColor(aVar.f());
    }

    public final void v(boolean z10) {
        this.f74058l = z10;
    }
}
