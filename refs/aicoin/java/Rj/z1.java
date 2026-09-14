package Rj;

import android.graphics.Canvas;

/* JADX INFO: loaded from: classes7.dex */
public final class z1 extends AbstractC2708f {
    public z1(C2732n c2732n, String str) {
        super(c2732n, str);
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        C2702d c2702dE = i().b().e(b());
        if (c2702dE == null) {
            return;
        }
        canvas.drawRect(c2702dE.n(), v());
    }
}
