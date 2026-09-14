package gk;

import Rj.C2732n;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class S extends AbstractC7467h0 {
    public S(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        int iP = sVar.p();
        int iX = sVar.x();
        int iG = x().l()[0].g();
        int iG2 = x().l()[1].g();
        boolean zB = x().r()[0].b();
        boolean zB2 = x().r()[1].b();
        List listR = sVar.r();
        List listT = sVar.t();
        List listA = sVar.A();
        Qj.b bVar = new Qj.b(iP, 0.0d, 2, null);
        ArrayList arrayList = new ArrayList(AbstractC2804s.y(listR, 10));
        int i10 = 0;
        for (Object obj : listR) {
            int i11 = i10 + 1;
            if (i10 < 0) {
                Sf.r.x();
            }
            arrayList.add(Double.valueOf(((Number) obj).doubleValue() - ((Number) listT.get(i10)).doubleValue()));
            i10 = i11;
        }
        Qj.b bVar2 = bVar;
        List listB = Pj.a.b(bVar2, listA, iG, false, 4, null);
        ArrayList arrayList2 = new ArrayList(AbstractC2804s.y(listA, 10));
        int i12 = 0;
        for (Object obj2 : listA) {
            int i13 = i12 + 1;
            if (i12 < 0) {
                Sf.r.x();
            }
            ((Number) obj2).doubleValue();
            arrayList2.add(Double.valueOf(((Number) listB.get(i12)).doubleValue() / ((Number) listA.get(i12)).doubleValue()));
            i12 = i13;
        }
        ArrayList arrayList3 = new ArrayList(AbstractC2804s.y(listA, 10));
        Iterator it = listA.iterator();
        int i14 = 0;
        while (true) {
            double dDoubleValue = Double.NaN;
            if (!it.hasNext()) {
                break;
            }
            Object next = it.next();
            int i15 = i14 + 1;
            if (i14 < 0) {
                Sf.r.x();
            }
            ((Number) next).doubleValue();
            if (i14 >= 1) {
                int i16 = i14 - 1;
                dDoubleValue = (((((Number) listT.get(i14)).doubleValue() + ((Number) listR.get(i14)).doubleValue()) - (((Number) listT.get(i16)).doubleValue() + ((Number) listR.get(i16)).doubleValue())) * ((double) 100)) / (((Number) listT.get(i14)).doubleValue() + ((Number) listR.get(i14)).doubleValue());
            }
            arrayList3.add(Double.valueOf(dDoubleValue));
            bVar2 = bVar2;
            i14 = i15;
        }
        bVar2.g();
        List listB2 = Pj.a.b(bVar2, arrayList, iG, false, 4, null);
        ArrayList arrayList4 = new ArrayList(AbstractC2804s.y(listA, 10));
        int i17 = 0;
        for (Object obj3 : listA) {
            int i18 = i17 + 1;
            if (i17 < 0) {
                Sf.r.x();
            }
            ((Number) obj3).doubleValue();
            arrayList4.add(Double.valueOf((Double.isNaN(((Number) arrayList3.get(i17)).doubleValue()) || i17 > iX) ? Double.NaN : (((Number) arrayList.get(i17)).doubleValue() * (((Number) arrayList2.get(i17)).doubleValue() * ((Number) arrayList3.get(i17)).doubleValue())) / ((Number) listB2.get(i17)).doubleValue()));
            i17 = i18;
        }
        List listM = nk.z.m(arrayList4, false, 1, null);
        bVar2.g();
        List listB3 = Pj.a.b(bVar2, listM, iG, false, 4, null);
        if (zB) {
            v()[0] = Sf.z.n1(listB3);
        }
        if (zB2) {
            List listM2 = nk.z.m(listB3, false, 1, null);
            bVar2.g();
            v()[1] = Sf.z.n1(Pj.a.b(bVar2, listM2, iG2, false, 4, null));
        }
    }
}
