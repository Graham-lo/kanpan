package Rj;

import android.graphics.Canvas;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: Rj.b0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2697b0 extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final int f19329l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final fk.M f19330m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final fk.N f19331n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final AbstractC2744r0[] f19332o;

    public C2697b0(C2732n c2732n, String str, boolean z10) {
        super(c2732n, str);
        this.f19329l = KLineManager.f142490O.a().q(14);
        fk.M m10 = new fk.M(c2732n, str);
        m10.s(z10);
        this.f19330m = m10;
        fk.N n10 = new fk.N(c2732n, str);
        n10.s(z10);
        this.f19331n = n10;
        this.f19332o = new AbstractC2744r0[]{m10, n10};
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        y1 y1VarK = j().k();
        if (y1VarK == null) {
            return;
        }
        float fU = y1VarK.u();
        int i10 = this.f19329l;
        if (i10 != 0 && i10 != 1) {
            if (i10 != 2) {
                return;
            }
            this.f19330m.g(canvas);
        } else if (fU < 7.0f) {
            this.f19331n.g(canvas);
        } else {
            this.f19330m.g(canvas);
        }
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
        for (AbstractC2744r0 abstractC2744r0 : this.f19332o) {
            abstractC2744r0.t();
        }
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        for (AbstractC2744r0 abstractC2744r0 : this.f19332o) {
            abstractC2744r0.u(aVar);
        }
    }
}
