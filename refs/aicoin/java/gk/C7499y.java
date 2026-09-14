package gk;

import Rj.C2732n;
import java.util.ArrayList;

/* JADX INFO: renamed from: gk.y, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7499y extends AbstractC7467h0 {
    public C7499y(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    /* JADX WARN: Multi-variable type inference failed */
    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        if (x().r()[0].b()) {
            int iP = sVar.p();
            Sj.a aVarC = sVar.q().C();
            int iG = x().l()[0].g();
            ArrayList arrayList = new ArrayList();
            int i10 = 0;
            for (Object obj : aVarC) {
                int i11 = i10 + 1;
                if (i10 < 0) {
                    Sf.r.x();
                }
                Sj.b bVar = (Sj.b) obj;
                if (i10 > 0) {
                    int i12 = i10 - 1;
                    arrayList.add(Double.valueOf(Math.max(bVar.b() - bVar.c(), Math.max(Math.abs(bVar.b() - ((Sj.b) aVarC.get(i12)).a()), Math.abs(bVar.c() - ((Sj.b) aVarC.get(i12)).a())))));
                } else {
                    arrayList.add(Double.valueOf(bVar.b() - bVar.c()));
                }
                i10 = i11;
            }
            v()[0] = Sf.z.n1(nk.z.e(Pj.f.b(new Qj.i(), arrayList, iG, false, 4, null), iP));
        }
    }
}
