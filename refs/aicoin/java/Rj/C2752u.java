package Rj;

import android.graphics.Canvas;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: Rj.u, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2752u extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final AbstractC2744r0 f19556l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final int f19557m;

    public C2752u(C2732n c2732n, AbstractC2744r0 abstractC2744r0) {
        super(c2732n, abstractC2744r0.d());
        this.f19556l = abstractC2744r0;
        this.f19557m = KLineManager.f142490O.a().q(14);
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        y1 y1VarK = j().k();
        if (y1VarK == null) {
            return;
        }
        if (y1VarK.u() >= 5.0f || this.f19557m != 0) {
            this.f19556l.g(canvas);
        }
    }

    @Override // Rj.AbstractC2744r0
    public void h(Canvas canvas) {
        y1 y1VarK = j().k();
        if (y1VarK == null) {
            return;
        }
        if (y1VarK.u() >= 5.0f || this.f19557m != 0) {
            this.f19556l.h(canvas);
        }
    }

    @Override // Rj.AbstractC2744r0
    public boolean n(String str, int i10, int i11) {
        y1 y1VarK = j().k();
        if (y1VarK == null) {
            return false;
        }
        if (y1VarK.u() >= 5.0f || this.f19557m != 0) {
            return this.f19556l.n(str, i10, i11);
        }
        return false;
    }

    @Override // Rj.AbstractC2744r0
    public int p() {
        y1 y1VarK = j().k();
        if (y1VarK == null) {
            return 0;
        }
        if (y1VarK.u() >= 5.0f || this.f19557m != 0) {
            return this.f19556l.p();
        }
        return 0;
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
        this.f19556l.t();
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        this.f19556l.u(aVar);
    }
}
