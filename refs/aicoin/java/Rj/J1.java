package Rj;

import android.graphics.Canvas;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class J1 extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final int f19158l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final H1 f19159m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final I1 f19160n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final AbstractC2744r0[] f19161o;

    public J1(C2732n c2732n, String str, boolean z10) {
        super(c2732n, str);
        this.f19158l = KLineManager.f142490O.a().q(14);
        H1 h10 = new H1(c2732n, str);
        h10.s(z10);
        this.f19159m = h10;
        I1 i10 = new I1(c2732n, str);
        i10.s(z10);
        this.f19160n = i10;
        this.f19161o = new AbstractC2744r0[]{h10, i10};
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        y1 y1VarK = j().k();
        if (y1VarK == null) {
            return;
        }
        float fU = y1VarK.u();
        int i10 = this.f19158l;
        if (i10 != 0 && i10 != 1) {
            if (i10 != 2) {
                return;
            }
            this.f19159m.g(canvas);
        } else if (fU < 7.0f) {
            this.f19160n.g(canvas);
        } else {
            this.f19159m.g(canvas);
        }
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
        for (AbstractC2744r0 abstractC2744r0 : this.f19161o) {
            abstractC2744r0.t();
        }
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        for (AbstractC2744r0 abstractC2744r0 : this.f19161o) {
            abstractC2744r0.u(aVar);
        }
    }
}
