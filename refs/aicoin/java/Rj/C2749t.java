package Rj;

import android.graphics.Canvas;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: Rj.t, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2749t extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final AbstractC2744r0 f19551l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final AbstractC2744r0 f19552m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final int f19553n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final AbstractC2744r0[] f19554o;

    public C2749t(C2732n c2732n, String str, AbstractC2744r0 abstractC2744r0, AbstractC2744r0 abstractC2744r1) {
        super(c2732n, str);
        this.f19551l = abstractC2744r0;
        this.f19552m = abstractC2744r1;
        this.f19553n = KLineManager.f142490O.a().q(14);
        this.f19554o = new AbstractC2744r0[]{abstractC2744r0, abstractC2744r1};
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        y1 y1VarK = j().k();
        if (y1VarK == null) {
            return;
        }
        float fU = y1VarK.u();
        int i10 = this.f19553n;
        if (i10 != 0 && i10 != 1) {
            if (i10 != 2) {
                return;
            }
            this.f19551l.g(canvas);
        } else if (fU < 7.0f) {
            this.f19552m.g(canvas);
        } else {
            this.f19551l.g(canvas);
        }
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
        for (AbstractC2744r0 abstractC2744r0 : this.f19554o) {
            abstractC2744r0.t();
        }
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        for (AbstractC2744r0 abstractC2744r0 : this.f19554o) {
            abstractC2744r0.u(aVar);
        }
    }
}
