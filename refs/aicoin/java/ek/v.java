package ek;

import java.math.BigDecimal;
import java.math.RoundingMode;

/* JADX INFO: loaded from: classes7.dex */
public abstract class v {
    public static final String a(sp.aicoin_kline.core.indicator.config.F f10, int i10, boolean z10) {
        BigDecimal scale;
        String plainString;
        float fB = (z10 ? f10.l()[i10] : f10.o()[i10]).b();
        int iE = (z10 ? f10.l()[i10] : f10.o()[i10]).e();
        BigDecimal bigDecimalM = Ah.v.m(String.valueOf(fB));
        return (bigDecimalM == null || (scale = bigDecimalM.setScale(iE, RoundingMode.DOWN)) == null || (plainString = scale.toPlainString()) == null) ? new BigDecimal(String.valueOf(fB)).setScale(iE, RoundingMode.DOWN).toPlainString() : plainString;
    }

    public static final int b(sp.aicoin_kline.core.indicator.config.F f10, int i10, boolean z10) {
        return (z10 ? f10.l()[i10] : f10.o()[i10]).g();
    }

    public static final boolean c(sp.aicoin_kline.core.indicator.config.F f10, int i10, boolean z10) {
        if (z10) {
            return !f10.r()[i10].b();
        }
        return !f10.p()[i10].b();
    }

    public static final String d(sp.aicoin_kline.core.indicator.config.F f10, int i10) {
        BigDecimal scale;
        String plainString;
        float fB = f10.l()[i10].b();
        int iE = f10.l()[i10].e();
        BigDecimal bigDecimalM = Ah.v.m(String.valueOf(fB));
        return (bigDecimalM == null || (scale = bigDecimalM.setScale(iE, RoundingMode.DOWN)) == null || (plainString = scale.toPlainString()) == null) ? new BigDecimal(String.valueOf(fB)).setScale(iE, RoundingMode.DOWN).toPlainString() : plainString;
    }

    public static final double e(sp.aicoin_kline.core.indicator.config.F f10, int i10) {
        BigDecimal scale;
        float fB = f10.l()[i10].b();
        int iE = f10.l()[i10].e();
        if (iE <= 0) {
            return fB;
        }
        BigDecimal bigDecimalM = Ah.v.m(String.valueOf(fB));
        return (bigDecimalM == null || (scale = bigDecimalM.setScale(iE, RoundingMode.DOWN)) == null) ? new BigDecimal(String.valueOf(fB)).setScale(iE, RoundingMode.DOWN).doubleValue() : scale.doubleValue();
    }

    public static final int f(sp.aicoin_kline.core.indicator.config.F f10, int i10) {
        return f10.l()[i10].g();
    }

    public static final boolean g(sp.aicoin_kline.core.indicator.config.F f10, int i10) {
        return !f10.r()[i10].b();
    }

    public static final String h(sp.aicoin_kline.core.indicator.config.F f10, int i10, boolean z10) {
        BigDecimal scale;
        String plainString;
        float fB = (z10 ? f10.l()[i10] : f10.o()[i10]).b();
        int iE = (z10 ? f10.l()[i10] : f10.o()[i10]).e();
        BigDecimal bigDecimalM = Ah.v.m(String.valueOf(fB));
        return (bigDecimalM == null || (scale = bigDecimalM.setScale(iE, RoundingMode.DOWN)) == null || (plainString = scale.toPlainString()) == null) ? new BigDecimal(String.valueOf(fB)).setScale(iE, RoundingMode.DOWN).toPlainString() : plainString;
    }

    public static final int i(sp.aicoin_kline.core.indicator.config.F f10, int i10, boolean z10) {
        return (z10 ? f10.l()[i10] : f10.o()[i10]).g();
    }

    public static final boolean j(sp.aicoin_kline.core.indicator.config.F f10, int i10, boolean z10) {
        if (z10) {
            return !f10.r()[i10].b();
        }
        return !f10.p()[i10].b();
    }

    public static final void k(sp.aicoin_kline.core.indicator.config.F f10, int i10, String str, int i11) {
        BigDecimal bigDecimalM;
        if (str == null || (bigDecimalM = Ah.v.m(str)) == null) {
            return;
        }
        float fFloatValue = bigDecimalM.setScale(i11, RoundingMode.DOWN).floatValue();
        p292ng.g gVarD = f10.l()[i10].d();
        f10.l()[i10].i(p292ng.i.o(fFloatValue, gVarD.k(), gVarD.o()));
    }

    public static final void l(sp.aicoin_kline.core.indicator.config.F f10, int i10, Boolean bool) {
        if (bool != null) {
            f10.r()[i10].d(!bool.booleanValue());
        }
    }

    public static final void m(sp.aicoin_kline.core.indicator.config.F f10, int i10, Integer num) {
        if (num != null) {
            f10.l()[i10].j(p292ng.i.q(num.intValue(), f10.l()[i10].d()));
        }
    }

    public static final void n(sp.aicoin_kline.core.indicator.config.F f10, int i10, String str, int i11) {
        BigDecimal bigDecimalM;
        if (str == null || (bigDecimalM = Ah.v.m(str)) == null) {
            return;
        }
        float fFloatValue = bigDecimalM.setScale(i11, RoundingMode.DOWN).floatValue();
        p292ng.g gVarD = f10.o()[i10].d();
        f10.o()[i10].i(p292ng.i.o(fFloatValue, gVarD.k(), gVarD.o()));
    }

    public static final void o(sp.aicoin_kline.core.indicator.config.F f10, int i10, Boolean bool) {
        if (bool != null) {
            f10.p()[i10].d(!bool.booleanValue());
        }
    }

    public static final void p(sp.aicoin_kline.core.indicator.config.F f10, int i10, Integer num) {
        if (num != null) {
            f10.o()[i10].j(p292ng.i.q(num.intValue(), f10.l()[i10].d()));
        }
    }

    public static final String q(int i10) {
        return "rgba(" + ((i10 >> 16) & 255) + ", " + ((i10 >> 8) & 255) + ", " + (i10 & 255) + ", " + (((i10 >> 24) & 255) / 255.0f) + ')';
    }

    public static final Integer r(String str) {
        Ah.j jVarC;
        if (str == null || (jVarC = Ah.l.c(new Ah.l("rgba\\((\\d+),\\s*(\\d+),\\s*(\\d+),\\s*([0-9]*\\.?[0-9]+)\\)"), str, 0, 2, null)) == null) {
            return null;
        }
        Ah.j.b bVarA = jVarC.a();
        String str2 = (String) kk.j.a(bVarA, 1);
        String str3 = (String) kk.j.a(bVarA, 2);
        String str4 = (String) kk.j.a(bVarA, 3);
        String str5 = (String) kk.j.a(bVarA, 4);
        Integer numP = Ah.w.p(str2);
        int iIntValue = numP != null ? numP.intValue() : 255;
        Integer numP2 = Ah.w.p(str3);
        int iIntValue2 = numP2 != null ? numP2.intValue() : 255;
        Integer numP3 = Ah.w.p(str4);
        int iIntValue3 = numP3 != null ? numP3.intValue() : 255;
        Float fO = Ah.v.o(str5);
        return Integer.valueOf((((int) ((fO != null ? fO.floatValue() : 1.0f) * 255)) << 24) | (iIntValue << 16) | (iIntValue2 << 8) | iIntValue3);
    }
}
