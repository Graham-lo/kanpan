package nk;

import p167hg.AbstractC7609s;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class c {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final c f134195a = new c();

    public static final String c() {
        return KLineManager.f142490O.a().k();
    }

    public static final double e(double d10) {
        KLineManager kLineManagerA = KLineManager.f142490O.a();
        String strK = kLineManagerA.K();
        double D10 = kLineManagerA.D();
        return (!AbstractC7609s.f("default", strK) || D10 < 0.0d) ? d10 : D10;
    }

    public final Double a(double d10, double d11) {
        if (!Double.isNaN(d10) && !Double.isNaN(d11) && d11 != 0.0d) {
            double d12 = (d10 / d11) - ((double) 1);
            Double dValueOf = Double.valueOf(d12);
            if (!Double.isNaN(d12) && !Double.isInfinite(d12)) {
                return dValueOf;
            }
        }
        return null;
    }

    public final Double b(double d10, double d11) {
        if (Double.isNaN(d11) || d11 == 0.0d) {
            return null;
        }
        return Double.valueOf(((d10 / 100.0d) + 1.0d) * d11);
    }

    public final Sj.b d(Sj.b bVar) {
        KLineManager kLineManagerA = KLineManager.f142490O.a();
        String strK = kLineManagerA.K();
        double D10 = kLineManagerA.D();
        if (!AbstractC7609s.f("default", strK) || D10 < 0.0d) {
            return bVar;
        }
        Sj.b bVar2 = new Sj.b(bVar);
        bVar2.i(Math.max(D10, bVar.b()));
        bVar2.j(Math.min(D10, bVar.c()));
        bVar2.h(D10);
        return bVar2;
    }
}
