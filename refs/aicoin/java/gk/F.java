package gk;

import Rj.C2732n;
import Sf.AbstractC2801o;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class F extends AbstractC7467h0 {
    public F(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        if (x().r()[0].b()) {
            int iP = sVar.p();
            List listN = sVar.n();
            int iG = x().l()[0].g();
            int iG2 = x().l()[1].g();
            List listB = Pj.a.b(new H.b(), listN, iG, false, 4, null);
            List listA = new H.d().a(listN, iG, true);
            ArrayList arrayList = new ArrayList(AbstractC2804s.y(listA, 10));
            Iterator it = listA.iterator();
            while (it.hasNext()) {
                arrayList.add(Double.valueOf(((H.c) it.next()).a()));
            }
            List listE = nk.z.e(arrayList, iP);
            ArrayList arrayList2 = new ArrayList(AbstractC2804s.y(listB, 10));
            Iterator it2 = listB.iterator();
            while (it2.hasNext()) {
                arrayList2.add(Double.valueOf(((H.a) it2.next()).a()));
            }
            double[] dArrN1 = Sf.z.n1(nk.z.e(arrayList2, iP));
            double[] dArr = new double[iP];
            int i10 = 0;
            while (true) {
                double dDoubleValue = Double.NaN;
                if (i10 >= iP) {
                    break;
                }
                Double dN0 = AbstractC2801o.n0(dArrN1, i10);
                double dDoubleValue2 = dN0 != null ? dN0.doubleValue() : Double.NaN;
                Double d10 = (Double) Sf.z.r0(listE, i10);
                if (d10 != null) {
                    dDoubleValue = d10.doubleValue();
                }
                dArr[i10] = (((double) iG2) * dDoubleValue) + dDoubleValue2;
                i10++;
            }
            double[] dArr2 = new double[iP];
            for (int i11 = 0; i11 < iP; i11++) {
                Double dN1 = AbstractC2801o.n0(dArrN1, i11);
                double dDoubleValue3 = dN1 != null ? dN1.doubleValue() : Double.NaN;
                Double d11 = (Double) Sf.z.r0(listE, i11);
                dArr2[i11] = dDoubleValue3 - (((double) iG2) * (d11 != null ? d11.doubleValue() : Double.NaN));
            }
            double[] dArr3 = new double[iP];
            for (int i12 = 0; i12 < iP; i12++) {
                Double dN2 = AbstractC2801o.n0(dArrN1, i12);
                dArr3[i12] = (dArr[i12] - dArr2[i12]) / (dN2 != null ? dN2.doubleValue() : Double.NaN);
            }
            v()[0] = dArr3;
        }
    }
}
