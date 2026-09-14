package Rj;

import android.graphics.Canvas;
import java.util.Iterator;
import p167hg.AbstractC7609s;

/* JADX INFO: renamed from: Rj.z0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2766z0 extends AbstractC2708f {
    public C2766z0(C2732n c2732n, String str) {
        super(c2732n, str);
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        String strF;
        C2741q c2741qB = i().b();
        C2702d c2702dE = c2741qB.e(b());
        if (c2702dE == null || (strF = f()) == null || c2741qB.l(strF) == null) {
            return;
        }
        canvas.drawRect(c2702dE.n(), v());
    }

    @Override // Rj.AbstractC2744r0
    public boolean n(String str, int i10, int i11) {
        Object obj;
        Iterator it = i().b().f().iterator();
        while (true) {
            obj = null;
            if (!it.hasNext()) {
                break;
            }
            Object next = it.next();
            C2702d c2702d = (C2702d) next;
            if (i11 >= c2702d.z() && i11 <= c2702d.p() && i10 >= c2702d.u() && i10 <= c2702d.y() && c2702d.o() == C2702d.a.Range && (Ah.y.T(c2702d.b(), ".indic", false, 2, null) || Ah.y.T(c2702d.b(), ".script", false, 2, null))) {
                obj = next;
                break;
            }
        }
        C2702d c2702d2 = (C2702d) obj;
        if (c2702d2 == null || !AbstractC7609s.f(e().a(1), c2702d2.e().a(1))) {
            return false;
        }
        C2738p.f19487a.o(c2702d2.b());
        return true;
    }
}
