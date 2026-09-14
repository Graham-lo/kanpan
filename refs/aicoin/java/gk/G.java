package gk;

import Rj.C2732n;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class G extends AbstractC7467h0 {
    public G(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        int iP = sVar.p();
        List listN = sVar.n();
        int iW = w();
        for (int i10 = 0; i10 < iW; i10++) {
            if (x().r()[i10].b()) {
                List listE = nk.z.e(Pj.a.b(new Qj.c(), listN, x().l()[i10].g(), false, 4, null), iP);
                ArrayList arrayList = new ArrayList(AbstractC2804s.y(listE, 10));
                int i11 = 0;
                for (Object obj : listE) {
                    int i12 = i11 + 1;
                    if (i11 < 0) {
                        Sf.r.x();
                    }
                    double dDoubleValue = ((Number) obj).doubleValue();
                    arrayList.add(Double.valueOf(((((Number) listN.get(i11)).doubleValue() - dDoubleValue) / dDoubleValue) * ((double) 100)));
                    i11 = i12;
                }
                v()[i10] = Sf.z.n1(arrayList);
            }
        }
    }
}
