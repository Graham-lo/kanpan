package nk;

import java.text.DecimalFormat;

/* JADX INFO: loaded from: classes7.dex */
public abstract class A {
    public static final float a(float f10, p292ng.g gVar) {
        int iO;
        if (f10 < gVar.k()) {
            iO = gVar.k();
        } else {
            if (f10 <= gVar.o()) {
                return f10;
            }
            iO = gVar.o();
        }
        return iO;
    }

    public static final String b(double d10, int i10) {
        DecimalFormat decimalFormat = new DecimalFormat();
        decimalFormat.setMaximumFractionDigits(i10);
        return decimalFormat.format(d10);
    }

    public static final double c(double d10, double d11, double d12) {
        return d11 == 0.0d ? d12 : d10 / d11;
    }

    public static final float d(float f10, float f11, float f12) {
        return f11 == 0.0f ? f12 : f10 / f11;
    }

    public static /* synthetic */ double e(double d10, double d11, double d12, int i10, Object obj) {
        if ((i10 & 2) != 0) {
            d12 = Double.NaN;
        }
        return c(d10, d11, d12);
    }

    public static final float f(float f10, float f11, float f12) {
        return Math.max(f11, f12) - (f10 - Math.min(f11, f12));
    }
}
