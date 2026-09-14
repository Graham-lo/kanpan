package Vj;

import Rj.AbstractC2744r0;
import Rj.C2732n;
import android.graphics.Canvas;

/* JADX INFO: loaded from: classes7.dex */
public final class b extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final AbstractC2744r0[] f24084l;

    public b(C2732n c2732n, String str, AbstractC2744r0[] abstractC2744r0Arr) {
        super(c2732n, str);
        this.f24084l = abstractC2744r0Arr;
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        for (AbstractC2744r0 abstractC2744r0 : this.f24084l) {
            abstractC2744r0.g(canvas);
        }
    }

    @Override // Rj.AbstractC2744r0
    public void h(Canvas canvas) {
        for (AbstractC2744r0 abstractC2744r0 : this.f24084l) {
            abstractC2744r0.h(canvas);
        }
    }

    @Override // Rj.AbstractC2744r0
    public boolean n(String str, int i10, int i11) {
        boolean z10 = false;
        for (AbstractC2744r0 abstractC2744r0 : this.f24084l) {
            if (abstractC2744r0.n(str, i10, i11)) {
                z10 = true;
            }
        }
        return z10;
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
        for (AbstractC2744r0 abstractC2744r0 : this.f24084l) {
            abstractC2744r0.t();
        }
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        for (AbstractC2744r0 abstractC2744r0 : this.f24084l) {
            abstractC2744r0.u(aVar);
        }
    }
}
