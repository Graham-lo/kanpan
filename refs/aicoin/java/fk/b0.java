package fk;

import Rj.AbstractC2693a;
import Rj.AbstractC2755v;
import Rj.C2702d;
import Rj.C2732n;
import Rj.C2765z;
import Rj.y1;
import android.content.res.Resources;
import android.graphics.Canvas;
import gk.AbstractC7467h0;
import java.util.ArrayList;
import sp.aicoin_kline.R;

/* JADX INFO: loaded from: classes7.dex */
public final class b0 extends AbstractC2693a {

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public final ak.h f95340A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public final ArrayList f95341B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public String f95342C;

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public AbstractC7467h0 f95343D;

    /* JADX INFO: renamed from: E, reason: collision with root package name */
    public sp.aicoin_kline.core.indicator.config.F f95344E;

    public b0(C2732n c2732n, String str, String str2) {
        super(c2732n, str);
        this.f95341B = new ArrayList();
        this.f95342C = "";
        this.f95340A = new ak.h(c2732n.b(), this, str2);
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        Rj.G gH;
        C2702d c2702dD;
        AbstractC7467h0 abstractC7467h0;
        C2765z c2765zH;
        sp.aicoin_kline.core.indicator.config.F f10;
        Sj.b bVar;
        y1 y1VarK = j().k();
        if (y1VarK == null || (gH = j().h()) == null || (c2702dD = j().d()) == null || (abstractC7467h0 = this.f95343D) == null || (c2765zH = j().i().h(c())) == null || (f10 = this.f95344E) == null) {
            return;
        }
        this.f95341B.clear();
        this.f95341B.add(new AbstractC2693a.b(this.f95342C, A(), false, true, f10.n(), false, 36, null));
        int iIntValue = ((Number) p162hb.e.c(nk.n.f(13), Integer.valueOf(gH.t()), Integer.valueOf(y1VarK.D()))).intValue();
        if (!gH.B() && !y1VarK.E()) {
            iIntValue = c2765zH.D() - 1;
        }
        if (iIntValue < 0 || iIntValue >= c2765zH.B()) {
            iIntValue = c2765zH.B() - 1;
        }
        if (iIntValue >= 0 && iIntValue < c2765zH.C().size() && (bVar = (Sj.b) Sf.z.r0(c2765zH.C(), iIntValue)) != null) {
            double dF = bVar.f();
            if (!Double.isNaN(dF)) {
                this.f95341B.add(new AbstractC2693a.b(kk.h.a(new StringBuilder(), nk.h.f(nk.h.f134211a, dF, nk.l.f(nk.l.f134222a, dF, true, false, 4, null), 0, 4, null), ' '), A(), false, false, f10.n(), false, 44, null));
            }
            int iW = abstractC7467h0.w();
            for (int i10 = 0; i10 < iW; i10++) {
                if (i10 < abstractC7467h0.v().length) {
                    double[] dArr = abstractC7467h0.v()[i10];
                    if (dArr.length != 0 && iIntValue < dArr.length && i10 < f10.r().length) {
                        ek.I i11 = f10.r()[i10];
                        if (i11.b()) {
                            double d10 = dArr[iIntValue];
                            if (!Double.isNaN(d10)) {
                                String strA = i11.a();
                                if (f10.t() && i10 < f10.l().length) {
                                    strA = "MAVOL" + nk.h.d(nk.h.f134211a, f10.l()[i10].g(), String.valueOf(f10.l()[i10].g()), 0, 4, null);
                                }
                                StringBuilder sb2 = new StringBuilder();
                                sb2.append(strA + ':');
                                this.f95341B.add(new AbstractC2693a.b(kk.h.a(sb2, nk.h.f(nk.h.f134211a, d10, nk.l.f(nk.l.f134222a, d10, true, false, 4, null), 0, 4, null), ' '), x(i10), false, false, f10.n(), false, 44, null));
                            }
                        }
                    }
                }
            }
            z(canvas, c2702dD, this.f95341B);
        }
    }

    @Override // Rj.AbstractC2744r0
    public ak.h j() {
        return this.f95340A;
    }

    @Override // Rj.AbstractC2693a, Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        sp.aicoin_kline.core.indicator.config.F fX;
        super.u(aVar);
        Resources resources = i().c().getResources();
        if (resources == null) {
            return;
        }
        AbstractC2755v abstractC2755vQ = q();
        AbstractC7467h0 abstractC7467h0 = abstractC2755vQ instanceof AbstractC7467h0 ? (AbstractC7467h0) abstractC2755vQ : null;
        if (abstractC7467h0 == null || (fX = abstractC7467h0.x()) == null) {
            return;
        }
        this.f95343D = abstractC7467h0;
        this.f95344E = fX;
        StringBuffer stringBuffer = new StringBuffer();
        stringBuffer.append(resources.getString(R.string.kline_titles_volume));
        stringBuffer.append(": ");
        this.f95342C = stringBuffer.toString();
    }
}
