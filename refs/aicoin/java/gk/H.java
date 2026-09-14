package gk;

import Rj.C2732n;
import Rj.C2765z;
import Sf.AbstractC2801o;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class H extends AbstractC7467h0 {

    public static final class a {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public final double f96459a;

        /* JADX INFO: renamed from: b, reason: collision with root package name */
        public final double f96460b;

        public a(double d10, double d11) {
            this.f96459a = d10;
            this.f96460b = d11;
        }

        public final double a() {
            return this.f96459a;
        }

        public boolean equals(Object obj) {
            if (this == obj) {
                return true;
            }
            if (!(obj instanceof a)) {
                return false;
            }
            a aVar = (a) obj;
            return Double.compare(this.f96459a, aVar.f96459a) == 0 && Double.compare(this.f96460b, aVar.f96460b) == 0;
        }

        public int hashCode() {
            return Double.hashCode(this.f96460b) + (Double.hashCode(this.f96459a) * 31);
        }

        public String toString() {
            return "BollCandidate(ma=" + this.f96459a + ", close=" + this.f96460b + ')';
        }
    }

    public static final class b extends Pj.a {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public double f96461a;

        /* JADX INFO: renamed from: b, reason: collision with root package name */
        public double f96462b;

        @Override // Pj.a
        public /* bridge */ /* synthetic */ void d(Object obj) {
            g(((Number) obj).doubleValue());
        }

        @Override // Pj.a
        public /* bridge */ /* synthetic */ void e(Object obj) {
            h(((Number) obj).doubleValue());
        }

        @Override // Pj.a
        /* JADX INFO: renamed from: f, reason: merged with bridge method [inline-methods] */
        public a c(int i10, List list) {
            return new a(this.f96461a / ((double) i10), this.f96462b);
        }

        public void g(double d10) {
            this.f96461a += d10;
            this.f96462b = d10;
        }

        public void h(double d10) {
            this.f96461a -= d10;
        }
    }

    public static final class c {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public final double f96463a;

        public c(double d10) {
            this.f96463a = d10;
        }

        public final double a() {
            return this.f96463a;
        }

        public boolean equals(Object obj) {
            if (this == obj) {
                return true;
            }
            return (obj instanceof c) && Double.compare(this.f96463a, ((c) obj).f96463a) == 0;
        }

        public int hashCode() {
            return Double.hashCode(this.f96463a);
        }

        public String toString() {
            return "BollResult(std=" + this.f96463a + ')';
        }
    }

    public static final class d extends Pj.f {
        @Override // Pj.f
        /* JADX INFO: renamed from: d, reason: merged with bridge method [inline-methods] */
        public c c(int i10, int i11, int i12, int i13, List list) {
            double dPow = 0.0d;
            double dDoubleValue = 0.0d;
            for (int i14 = i12; i14 < i13; i14++) {
                dDoubleValue += ((Number) list.get(i14)).doubleValue();
            }
            double d10 = i11;
            double d11 = dDoubleValue / d10;
            while (i12 < i13) {
                dPow += Math.pow(((Number) list.get(i12)).doubleValue() - d11, 2.0d);
                i12++;
            }
            return new c(Math.sqrt(dPow / d10));
        }
    }

    public H(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        int iP = sVar.p();
        List listN = sVar.n();
        int iG = x().l()[0].g();
        float fB = x().l()[1].b();
        boolean zB = x().r()[0].b();
        boolean zB2 = x().r()[1].b();
        boolean zB3 = x().r()[2].b();
        List listB = Pj.a.b(new b(), listN, iG, false, 4, null);
        ArrayList arrayList = new ArrayList(AbstractC2804s.y(listB, 10));
        Iterator it = listB.iterator();
        while (it.hasNext()) {
            arrayList.add(Double.valueOf(((a) it.next()).a()));
        }
        double[] dArrN1 = Sf.z.n1(nk.z.e(arrayList, iP));
        List listA = new d().a(listN, iG, true);
        ArrayList arrayList2 = new ArrayList(AbstractC2804s.y(listA, 10));
        Iterator it2 = listA.iterator();
        while (it2.hasNext()) {
            arrayList2.add(Double.valueOf(((c) it2.next()).a()));
        }
        List listE = nk.z.e(arrayList2, iP);
        if (zB) {
            v()[0] = dArrN1;
        }
        if (zB2) {
            double[][] dArrV = v();
            double[] dArr = new double[iP];
            for (int i10 = 0; i10 < iP; i10++) {
                Double dN0 = AbstractC2801o.n0(dArrN1, i10);
                double dDoubleValue = dN0 != null ? dN0.doubleValue() : Double.NaN;
                Double d10 = (Double) Sf.z.r0(listE, i10);
                dArr[i10] = (((double) fB) * (d10 != null ? d10.doubleValue() : Double.NaN)) + dDoubleValue;
            }
            dArrV[1] = dArr;
        }
        if (zB3) {
            double[][] dArrV2 = v();
            double[] dArr2 = new double[iP];
            for (int i11 = 0; i11 < iP; i11++) {
                Double dN1 = AbstractC2801o.n0(dArrN1, i11);
                double dDoubleValue2 = dN1 != null ? dN1.doubleValue() : Double.NaN;
                Double d11 = (Double) Sf.z.r0(listE, i11);
                dArr2[i11] = dDoubleValue2 - (((double) fB) * (d11 != null ? d11.doubleValue() : Double.NaN));
            }
            dArrV2[2] = dArr2;
        }
    }

    @Override // gk.AbstractC7467h0, Rj.AbstractC2755v
    public void l(int i10, double[] dArr) {
        Sj.b bVar;
        Sj.b bVar2;
        C2765z c2765zD = h().d();
        Sj.a aVarC = c2765zD != null ? c2765zD.C() : null;
        Double dN0 = AbstractC2801o.n0(v()[0], i10);
        double dDoubleValue = dN0 != null ? dN0.doubleValue() : Double.NaN;
        Double dN1 = AbstractC2801o.n0(v()[1], i10);
        double dDoubleValue2 = dN1 != null ? dN1.doubleValue() : Double.NaN;
        Double dN2 = AbstractC2801o.n0(v()[2], i10);
        double dDoubleValue3 = dN2 != null ? dN2.doubleValue() : Double.NaN;
        double dB = (aVarC == null || (bVar2 = (Sj.b) Sf.z.r0(aVarC, i10)) == null) ? Double.NaN : bVar2.b();
        double dC = (aVarC == null || (bVar = (Sj.b) Sf.z.r0(aVarC, i10)) == null) ? Double.NaN : bVar.c();
        List listQ = Sf.r.q(Double.valueOf(dDoubleValue), Double.valueOf(dDoubleValue2), Double.valueOf(dDoubleValue3));
        Double dI = nk.z.i(listQ);
        double dDoubleValue4 = dI != null ? dI.doubleValue() : Double.NaN;
        Double dJ = nk.z.j(listQ);
        double dDoubleValue5 = dJ != null ? dJ.doubleValue() : Double.NaN;
        if (!Double.isNaN(dDoubleValue5)) {
            dC = Math.min(dDoubleValue5, dC);
        }
        if (!Double.isNaN(dDoubleValue4)) {
            dB = Math.max(dDoubleValue4, dB);
        }
        dArr[0] = dC;
        dArr[1] = dB;
    }

    @Override // Rj.AbstractC2755v
    public int p() {
        return KLineManager.f142490O.a().j();
    }
}
