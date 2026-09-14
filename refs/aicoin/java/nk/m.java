package nk;

import java.math.BigDecimal;
import java.math.RoundingMode;

/* JADX INFO: loaded from: classes7.dex */
public final class m {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final m f134229a = new m();

    public static String a(double d10, int i10, boolean z10) {
        if (Double.isInfinite(d10) || Double.isNaN(d10)) {
            return "";
        }
        BigDecimal scale = BigDecimal.valueOf(d10).setScale(p292ng.i.f(i10, 0), RoundingMode.HALF_UP);
        return z10 ? app.aicoin.trade.impl.core.attachedtpsl.e.a(scale).toPlainString() : scale.toPlainString();
    }

    public final String b(double d10) {
        if (Double.isInfinite(d10) || Double.isNaN(d10)) {
            return "";
        }
        double dAbs = Math.abs(d10);
        if (dAbs >= 1000000.0d) {
            return kk.h.a(new StringBuilder(), a(d10 / 1000000.0d, 1, true), 'M');
        }
        return dAbs >= 1000.0d ? kk.h.a(new StringBuilder(), a(d10 / 1000.0d, 1, true), 'K') : l.f134222a.t(a(d10, 5, false));
    }
}
