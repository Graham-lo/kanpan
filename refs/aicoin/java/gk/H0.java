package gk;

import Rj.C2732n;
import Sf.AbstractC2801o;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class H0 extends AbstractC7467h0 {

    public static final class a extends Pj.f {
        @Override // Pj.f
        /* JADX INFO: renamed from: d, reason: merged with bridge method [inline-methods] */
        public Double c(int i10, int i11, int i12, int i13, List list) {
            double dMin = Double.MAX_VALUE;
            double dMax = -1.7976931348623157E308d;
            double dA = 0.0d;
            for (int i14 = i12; i14 < i13; i14++) {
                dA += ((Sj.b) list.get(i14)).a();
                dMax = Math.max(((Sj.b) list.get(i14)).b(), dMax);
                dMin = Math.min(((Sj.b) list.get(i14)).c(), dMin);
            }
            return Double.valueOf(((Sj.b) list.get(i10)).a() - AbstractC2801o.Q(new double[]{AbstractC2801o.Q(new double[]{dMax, dMin}), dA / ((double) i11)}));
        }
    }

    public H0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        if (x().r()[0].b()) {
            int iP = sVar.p();
            int iG = x().l()[0].g();
            v()[0] = Sf.z.n1(nk.z.e(Pj.f.b(new Pj.g(), Pj.f.b(new a(), sVar.q().C(), iG, false, 4, null), iG, false, 4, null), iP));
        }
    }
}
