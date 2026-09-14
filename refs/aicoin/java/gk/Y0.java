package gk;

import Rj.C2732n;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class Y0 extends AbstractC7467h0 {
    public Y0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        int iP = sVar.p();
        List listA = sVar.A();
        List listN = sVar.n();
        int iG = x().l()[0].g();
        int iG2 = x().l()[1].g();
        boolean zB = x().r()[0].b();
        boolean zB2 = x().r()[1].b();
        ArrayList arrayList = new ArrayList();
        ArrayList arrayList2 = new ArrayList();
        ArrayList arrayList3 = new ArrayList();
        int i10 = 0;
        for (Object obj : listN) {
            int i11 = i10 + 1;
            if (i10 < 0) {
                Sf.r.x();
            }
            double dDoubleValue = ((Number) obj).doubleValue();
            if (i10 > 0) {
                int i12 = i10 - 1;
                if (dDoubleValue > ((Number) listN.get(i12)).doubleValue()) {
                    arrayList.add(listA.get(i10));
                    arrayList2.add(Double.valueOf(0.0d));
                    arrayList3.add(Double.valueOf(0.0d));
                } else if (dDoubleValue < ((Number) listN.get(i12)).doubleValue()) {
                    arrayList.add(Double.valueOf(0.0d));
                    arrayList2.add(listA.get(i10));
                    arrayList3.add(Double.valueOf(0.0d));
                } else {
                    arrayList.add(Double.valueOf(0.0d));
                    arrayList2.add(Double.valueOf(0.0d));
                    arrayList3.add(listA.get(i10));
                }
            } else {
                arrayList.add(Double.valueOf(0.0d));
                arrayList2.add(Double.valueOf(0.0d));
                arrayList3.add(Double.valueOf(0.0d));
            }
            i10 = i11;
        }
        List listB = Pj.a.b(new Qj.e(), arrayList, iG, false, 4, null);
        List listB2 = Pj.a.b(new Qj.e(), arrayList2, iG, false, 4, null);
        List listB3 = Pj.a.b(new Qj.e(), arrayList3, iG, false, 4, null);
        ArrayList arrayList4 = new ArrayList(AbstractC2804s.y(listB, 10));
        int i13 = 0;
        for (Object obj2 : listB) {
            int i14 = i13 + 1;
            if (i13 < 0) {
                Sf.r.x();
            }
            arrayList4.add(Double.valueOf((((Number) listB3.get(i13)).doubleValue() * 0.5d) + ((Number) obj2).doubleValue()));
            i13 = i14;
        }
        ArrayList arrayList5 = new ArrayList(AbstractC2804s.y(listB2, 10));
        int i15 = 0;
        for (Object obj3 : listB2) {
            int i16 = i15 + 1;
            if (i15 < 0) {
                Sf.r.x();
            }
            arrayList5.add(Double.valueOf((((Number) listB3.get(i15)).doubleValue() * 0.5d) + ((Number) obj3).doubleValue()));
            i15 = i16;
        }
        ArrayList arrayList6 = new ArrayList(AbstractC2804s.y(arrayList4, 10));
        int i17 = 0;
        for (Object obj4 : arrayList4) {
            int i18 = i17 + 1;
            if (i17 < 0) {
                Sf.r.x();
            }
            arrayList6.add(Double.valueOf(nk.A.e(((Number) obj4).doubleValue(), ((Number) arrayList5.get(i17)).doubleValue(), 0.0d, 2, null) * ((double) 100)));
            i17 = i18;
        }
        if (zB) {
            v()[0] = Sf.z.n1(nk.z.e(arrayList6, iP));
        }
        if (zB2) {
            v()[1] = Sf.z.n1(nk.z.e(Pj.a.b(new Qj.c(), arrayList6, iG2, false, 4, null), iP));
        }
    }
}
