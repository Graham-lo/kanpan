package gk;

import Rj.C2732n;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import kotlin.jvm.functions.Function1;

/* JADX INFO: loaded from: classes7.dex */
public final class Q extends AbstractC7467h0 {
    public Q(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    public static final double D(Sj.b bVar) {
        return bVar.b();
    }

    public static final ArrayList E(Sj.a aVar, Function1 function1, boolean z10) {
        ArrayList arrayList = new ArrayList();
        int i10 = 0;
        for (Object obj : aVar) {
            int i11 = i10 + 1;
            if (i10 < 0) {
                Sf.r.x();
            }
            Sj.b bVar = (Sj.b) obj;
            if (i10 > 0) {
                double dDoubleValue = ((Number) function1.invoke(bVar)).doubleValue() - ((Number) function1.invoke(aVar.get(i10 - 1))).doubleValue();
                if (!z10) {
                    dDoubleValue = -dDoubleValue;
                }
                arrayList.add(Double.valueOf(dDoubleValue));
            }
            i10 = i11;
        }
        return arrayList;
    }

    public static final double F(Sj.b bVar) {
        return bVar.c();
    }

    /* JADX WARN: Multi-variable type inference failed */
    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        int iP = sVar.p();
        int iG = x().l()[0].g();
        boolean z10 = true;
        int iG2 = x().l()[1].g();
        boolean zB = x().r()[0].b();
        boolean zB2 = x().r()[1].b();
        boolean zB3 = x().r()[2].b();
        boolean zB4 = x().r()[3].b();
        Sj.a aVarC = sVar.q().C();
        ArrayList arrayList = new ArrayList();
        Iterator it = aVarC.iterator();
        int i10 = 0;
        while (it.hasNext()) {
            Object next = it.next();
            int i11 = i10 + 1;
            if (i10 < 0) {
                Sf.r.x();
            }
            Sj.b bVar = (Sj.b) next;
            if (i10 > 0) {
                int i12 = i10 - 1;
                arrayList.add(Double.valueOf(Math.max(bVar.b() - bVar.c(), Math.max(Math.abs(bVar.b() - ((Sj.b) aVarC.get(i12)).a()), Math.abs(bVar.c() - ((Sj.b) aVarC.get(i12)).a())))));
            }
            it = it;
            i10 = i11;
        }
        List listE = nk.z.e(Pj.f.b(new Pj.h(), arrayList, iG, false, 4, null), iP);
        ArrayList arrayListE = E(aVarC, new O(), true);
        ArrayList arrayListE2 = E(aVarC, new P(), false);
        ArrayList arrayList2 = new ArrayList();
        ArrayList arrayList3 = new ArrayList();
        int size = arrayListE.size();
        for (int i13 = 0; i13 < size; i13++) {
            double dDoubleValue = 0.0d;
            arrayList2.add(Double.valueOf((((Number) arrayListE.get(i13)).doubleValue() <= 0.0d || ((Number) arrayListE.get(i13)).doubleValue() <= ((Number) arrayListE2.get(i13)).doubleValue()) ? 0.0d : ((Number) arrayListE.get(i13)).doubleValue()));
            if (((Number) arrayListE2.get(i13)).doubleValue() > 0.0d && ((Number) arrayListE2.get(i13)).doubleValue() > ((Number) arrayListE.get(i13)).doubleValue()) {
                dDoubleValue = ((Number) arrayListE2.get(i13)).doubleValue();
            }
            arrayList3.add(Double.valueOf(dDoubleValue));
        }
        List listE2 = nk.z.e(Pj.f.b(new Pj.h(), arrayList2, iG, false, 4, null), iP);
        List listE3 = nk.z.e(Pj.f.b(new Pj.h(), arrayList3, iG, false, 4, null), iP);
        ArrayList arrayList4 = new ArrayList();
        ArrayList arrayList5 = new ArrayList();
        int i14 = 0;
        while (i14 < iP) {
            boolean z11 = z10;
            double d10 = 100;
            arrayList4.add(Double.valueOf((((Number) listE2.get(i14)).doubleValue() / ((Number) listE.get(i14)).doubleValue()) * d10));
            arrayList5.add(Double.valueOf((((Number) listE3.get(i14)).doubleValue() / ((Number) listE.get(i14)).doubleValue()) * d10));
            i14++;
            z10 = z11;
        }
        boolean z12 = z10;
        ArrayList arrayList6 = new ArrayList();
        while (iG < iP) {
            arrayList6.add(Double.valueOf(Math.abs(((Number) arrayList5.get(iG)).doubleValue() - ((Number) arrayList4.get(iG)).doubleValue()) / (((Number) arrayList4.get(iG)).doubleValue() + ((Number) arrayList5.get(iG)).doubleValue())));
            iG++;
        }
        List listB = Pj.f.b(new Pj.h(), arrayList6, iG2, false, 4, null);
        ArrayList arrayList7 = new ArrayList(AbstractC2804s.y(listB, 10));
        Iterator it2 = listB.iterator();
        while (it2.hasNext()) {
            arrayList7.add(Double.valueOf(((Number) it2.next()).doubleValue() * ((double) 100)));
        }
        if (zB) {
            v()[0] = Sf.z.n1(arrayList4);
        }
        if (zB2) {
            v()[z12 ? 1 : 0] = Sf.z.n1(arrayList5);
        }
        if (zB3) {
            v()[2] = Sf.z.n1(nk.z.e(arrayList7, iP));
        }
        if (zB4) {
            v()[3] = Sf.z.n1(nk.z.e(Pj.f.b(new Pj.h(), arrayList7, iG2, false, 4, null), iP));
        }
    }
}
