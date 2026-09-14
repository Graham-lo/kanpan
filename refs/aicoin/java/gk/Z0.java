package gk;

import Rj.C2732n;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class Z0 extends AbstractC7467h0 {
    public Z0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        List list;
        B();
        int iP = sVar.p();
        List listN = sVar.n();
        List listR = sVar.r();
        List listT = sVar.t();
        int iW = w();
        int i10 = 0;
        while (i10 < iW) {
            boolean zB = x().r()[i10].b();
            int iG = x().l()[i10].g();
            if (iG == 0) {
                zB = false;
            }
            if (zB) {
                List listE = nk.z.e(Pj.f.b(new Qj.g(), listR, iG, false, 4, null), iP);
                list = listT;
                List listE2 = nk.z.e(Pj.f.b(new Qj.h(), list, iG, false, 4, null), iP);
                ArrayList arrayList = new ArrayList(AbstractC2804s.y(listN, 10));
                int i11 = 0;
                for (Object obj : listN) {
                    int i12 = i11 + 1;
                    if (i11 < 0) {
                        Sf.r.x();
                    }
                    arrayList.add(Double.valueOf(((((Number) obj).doubleValue() - ((Number) listE.get(i11)).doubleValue()) / (((Number) listE.get(i11)).doubleValue() - ((Number) listE2.get(i11)).doubleValue())) * ((double) 100)));
                    i11 = i12;
                }
                v()[i10] = Sf.z.n1(nk.z.e(arrayList, iP));
            } else {
                list = listT;
            }
            i10++;
            listT = list;
        }
    }
}
