package Vj;

import Rj.AbstractC2744r0;
import Rj.C2711g;
import Rj.C2732n;
import android.graphics.Canvas;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class a extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final AbstractC2744r0[] f24083l;

    public a(C2732n c2732n, String str, AbstractC2744r0[] abstractC2744r0Arr) {
        super(c2732n, str);
        this.f24083l = abstractC2744r0Arr;
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        int iSave = canvas.save();
        KLineManager.f142490O.a().i0();
        for (AbstractC2744r0 abstractC2744r0 : this.f24083l) {
            abstractC2744r0.g(canvas);
            int iL = abstractC2744r0.l();
            KLineManager.a aVar = KLineManager.f142490O;
            if ((AbstractC7609s.f(aVar.a().C(), "on_top") || AbstractC7609s.f(aVar.a().C(), "on_window")) && (abstractC2744r0 instanceof C2711g)) {
                iL = 0;
            }
            if (iL > 0) {
                canvas.translate(0.0f, iL);
            }
        }
        canvas.restoreToCount(iSave);
    }

    @Override // Rj.AbstractC2744r0
    public void h(Canvas canvas) {
        int iSave = canvas.save();
        for (AbstractC2744r0 abstractC2744r0 : this.f24083l) {
            abstractC2744r0.h(canvas);
            int iL = abstractC2744r0.l();
            KLineManager.a aVar = KLineManager.f142490O;
            if ((AbstractC7609s.f(aVar.a().C(), "on_top") || AbstractC7609s.f(aVar.a().C(), "on_window")) && (abstractC2744r0 instanceof C2711g)) {
                iL = 0;
            }
            if (iL > 0) {
                canvas.translate(0.0f, iL);
            }
        }
        canvas.restoreToCount(iSave);
    }

    @Override // Rj.AbstractC2744r0
    public boolean n(String str, int i10, int i11) {
        for (AbstractC2744r0 abstractC2744r0 : this.f24083l) {
            if (abstractC2744r0.n(str, i10, i11)) {
                return true;
            }
        }
        return false;
    }

    @Override // Rj.AbstractC2744r0
    public int p() {
        int i10 = 0;
        for (AbstractC2744r0 abstractC2744r0 : this.f24083l) {
            int iL = abstractC2744r0.l();
            KLineManager.a aVar = KLineManager.f142490O;
            if ((AbstractC7609s.f(aVar.a().C(), "on_top") || AbstractC7609s.f(aVar.a().C(), "on_window")) && (abstractC2744r0 instanceof C2711g)) {
                iL = 0;
            }
            if (iL > 0) {
                i10 += iL;
            }
        }
        return i10;
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
        for (AbstractC2744r0 abstractC2744r0 : this.f24083l) {
            abstractC2744r0.t();
        }
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        for (AbstractC2744r0 abstractC2744r0 : this.f24083l) {
            abstractC2744r0.u(aVar);
        }
    }
}
