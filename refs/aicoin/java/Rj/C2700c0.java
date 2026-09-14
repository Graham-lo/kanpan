package Rj;

import android.graphics.Canvas;

/* JADX INFO: renamed from: Rj.c0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public class C2700c0 extends AbstractC2708f {
    public C2700c0(C2732n c2732n, String str) {
        super(c2732n, str);
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        C2741q c2741qB = i().b();
        C2702d c2702dE = c2741qB.e(b());
        y1 y1VarM = c2741qB.m(c());
        AbstractC2759w0 abstractC2759w0L = c2741qB.l(b());
        if (c2702dE == null || y1VarM == null || abstractC2759w0L == null) {
            return;
        }
        canvas.drawRect(c2702dE.n(), v());
    }
}
