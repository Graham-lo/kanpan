package gk;

import Rj.C2732n;
import Rj.C2765z;
import Rj.y1;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class P0 extends AbstractC7467h0 {

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public final KLineManager f96483t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public double[][] f96484u;

    public P0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
        this.f96483t = KLineManager.f142490O.a();
        double[][] dArr = new double[2][];
        for (int i10 = 0; i10 < 2; i10++) {
            dArr[i10] = new double[0];
        }
        this.f96484u = dArr;
    }

    /* JADX WARN: Code duplicated, block: B:48:0x0132 A[PHI: r14 r17
      0x0132: PHI (r14v3 int) = (r14v1 int), (r14v5 int) binds: [B:35:0x010d, B:46:0x012f] A[DONT_GENERATE, DONT_INLINE]
      0x0132: PHI (r17v5 double) = (r17v1 double), (r17v7 double) binds: [B:35:0x010d, B:46:0x012f] A[DONT_GENERATE, DONT_INLINE]] */
    /* JADX WARN: Code duplicated, block: B:84:0x01f3 A[PHI: r6 r7
      0x01f3: PHI (r6v8 int) = (r6v7 int), (r6v10 int) binds: [B:71:0x01d0, B:82:0x01f0] A[DONT_GENERATE, DONT_INLINE]
      0x01f3: PHI (r7v11 double) = (r7v10 double), (r7v13 double) binds: [B:71:0x01d0, B:82:0x01f0] A[DONT_GENERATE, DONT_INLINE]] */
    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        double d10;
        double d11;
        double d12;
        double d13;
        B();
        int i10 = 0;
        for (int i11 = 0; i11 < 2; i11++) {
            this.f96484u[i11] = new double[0];
        }
        int iP = sVar.p();
        List listN = sVar.n();
        x().r()[0].b();
        ArrayList arrayList = new ArrayList(AbstractC2804s.y(listN, 10));
        Iterator it = listN.iterator();
        while (true) {
            d10 = 0.0d;
            if (!it.hasNext()) {
                break;
            }
            ((Number) it.next()).doubleValue();
            arrayList.add(Double.valueOf(0.0d));
        }
        List listU1 = Sf.z.u1(arrayList);
        ArrayList arrayList2 = new ArrayList(AbstractC2804s.y(listN, 10));
        Iterator it2 = listN.iterator();
        while (it2.hasNext()) {
            ((Number) it2.next()).doubleValue();
            arrayList2.add(Double.valueOf(0.0d));
        }
        List listU2 = Sf.z.u1(arrayList2);
        int i12 = 0;
        for (Object obj : listU2) {
            int i13 = i12 + 1;
            if (i12 < 0) {
                Sf.r.x();
            }
            ((Number) obj).doubleValue();
            if (i12 <= 3) {
                d13 = d10;
                listU2.set(i12, Double.valueOf(d13));
            } else if (((Number) listN.get(i12)).doubleValue() > ((Number) listN.get(i12 - 4)).doubleValue()) {
                d13 = d10;
                listU2.set(i12, Double.valueOf(((Number) listU2.get(i12 - 1)).doubleValue() + ((double) 1)));
            } else {
                d13 = d10;
                listU2.set(i12, Double.valueOf(d13));
            }
            i12 = i13;
            d10 = d13;
        }
        double d14 = d10;
        ArrayList arrayList3 = new ArrayList(AbstractC2804s.y(listU2, 10));
        int i14 = 0;
        int i15 = 0;
        double d15 = Double.NaN;
        for (Object obj2 : listU2) {
            int i16 = i14 + 1;
            if (i14 < 0) {
                Sf.r.x();
            }
            double dDoubleValue = ((Number) obj2).doubleValue();
            if (i14 >= 1) {
                if (dDoubleValue < ((Number) listU2.get(i14 - 1)).doubleValue() && (i15 = i15 + 1) > 1) {
                    d15 = dDoubleValue;
                }
                d12 = dDoubleValue - d15;
                if (d12 > 9.0d && d12 != 13.0d) {
                    d12 = Double.NaN;
                }
            } else {
                d12 = Double.NaN;
            }
            arrayList3.add(Double.valueOf(d12));
            i14 = i16;
        }
        this.f96484u[0] = Sf.z.n1(nk.z.e(arrayList3, iP));
        int i17 = 0;
        for (Object obj3 : listU1) {
            int i18 = i17 + 1;
            if (i17 < 0) {
                Sf.r.x();
            }
            ((Number) obj3).doubleValue();
            if (i17 <= 3) {
                listU1.set(i17, Double.valueOf(d14));
            } else if (((Number) listN.get(i17)).doubleValue() < ((Number) listN.get(i17 - 4)).doubleValue()) {
                listU1.set(i17, Double.valueOf(((Number) listU1.get(i17 - 1)).doubleValue() + ((double) 1)));
            } else {
                listU1.set(i17, Double.valueOf(d14));
            }
            i17 = i18;
        }
        ArrayList arrayList4 = new ArrayList(AbstractC2804s.y(listU1, 10));
        int i19 = 0;
        double d16 = Double.NaN;
        for (Object obj4 : listU1) {
            int i20 = i10 + 1;
            if (i10 < 0) {
                Sf.r.x();
            }
            double dDoubleValue2 = ((Number) obj4).doubleValue();
            if (i10 >= 1) {
                if (dDoubleValue2 < ((Number) listU1.get(i10 - 1)).doubleValue() && (i19 = i19 + 1) > 1) {
                    d16 = dDoubleValue2;
                }
                d11 = dDoubleValue2 - d16;
                if (d11 > 9.0d && d11 != 13.0d) {
                    d11 = Double.NaN;
                }
            } else {
                d11 = Double.NaN;
            }
            arrayList4.add(Double.valueOf(d11));
            i10 = i20;
        }
        this.f96484u[1] = Sf.z.n1(nk.z.e(arrayList4, iP));
    }

    public final double[][] D() {
        return this.f96484u;
    }

    @Override // gk.AbstractC7467h0, Rj.AbstractC2755v
    public void l(int i10, double[] dArr) {
        double[] dArr2;
        double d10;
        double d11;
        Sj.a aVarC;
        y1 y1VarM;
        C2765z c2765zD = h().d();
        if (c2765zD == null || (aVarC = c2765zD.C()) == null || (y1VarM = h().b().m(c())) == null) {
            dArr2 = new double[]{0.0d, 0.0d};
        } else {
            double[] dArr3 = {Double.MAX_VALUE, -1.7976931348623157E308d};
            int iQ = y1VarM.q();
            for (int iR = y1VarM.r(); iR < iQ; iR++) {
                Sj.b bVar = (Sj.b) Sf.z.r0(aVarC, iR);
                double dC = bVar != null ? bVar.c() : 0.0d;
                double dB = bVar != null ? bVar.b() : 0.0d;
                if (!Double.isNaN(dC)) {
                    dArr3[0] = Math.min(dC, dArr3[0]);
                }
                if (!Double.isNaN(dB)) {
                    dArr3[1] = Math.max(dB, dArr3[1]);
                }
            }
            dArr2 = dArr3;
        }
        double d12 = dArr2[0];
        double d13 = dArr2[1];
        double d14 = d13 - d12;
        if (this.f96483t.q(11) == 1) {
            d11 = 0.0d;
            d10 = 0.0d;
        } else {
            d10 = (-d14) * 0.1d;
            d11 = d14 * 0.1d;
        }
        dArr[0] = Math.max(0.0d, d12 + d10);
        dArr[1] = Math.max(0.0d, d13 + d11);
    }

    @Override // Rj.AbstractC2755v
    public int p() {
        return this.f96483t.j();
    }
}
