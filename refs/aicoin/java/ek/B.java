package ek;

import Rj.C2741q;
import Sf.AbstractC2804s;
import Sf.M;
import java.util.LinkedHashMap;
import java.util.List;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class B {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final List f93318a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final LinkedHashMap f93319b;

    public B() {
        List listQ = Sf.r.q(Zj.e.d.f27604d, Zj.e.a.f27601d, Zj.e.c.f27603d, Zj.e.b.f27602d);
        this.f93318a = listQ;
        LinkedHashMap linkedHashMap = new LinkedHashMap(p292ng.i.f(M.e(AbstractC2804s.y(listQ, 10)), 16));
        for (Object obj : listQ) {
            linkedHashMap.put(obj, Integer.valueOf(this.f93318a.indexOf((Zj.e) obj)));
        }
        this.f93319b = linkedHashMap;
    }

    public final float a(KLineManager kLineManager, C2741q c2741q, Zj.e eVar) {
        Integer num = (Integer) this.f93319b.get(eVar);
        int iIntValue = num != null ? num.intValue() : 0;
        float fA = 0.0f;
        if (iIntValue < 0) {
            return 0.0f;
        }
        for (int i10 = 0; i10 < iIntValue; i10++) {
            Zj.e eVar2 = (Zj.e) this.f93318a.get(i10);
            if (eVar2.b(kLineManager, c2741q)) {
                fA = eVar2.a() + fA;
            }
        }
        return fA;
    }
}
