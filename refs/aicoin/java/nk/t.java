package nk;

/* JADX INFO: loaded from: classes7.dex */
public final class t {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final t f134247a = new t();

    public final void a(double d10, String[] strArr, int i10, p146gg.o oVar) {
        double dAbs = Math.abs(d10);
        int i11 = -1;
        int iIntValue = ((Number) p162hb.e.c(d10 >= 0.0d, 1, -1)).intValue();
        if (i10 > 1) {
            double d11 = i10;
            if (dAbs >= d11 && strArr.length != 0) {
                int length = strArr.length - 1;
                while (dAbs >= d11) {
                    i11++;
                    dAbs /= d11;
                    if (i11 >= length) {
                        break;
                    }
                }
                oVar.invoke(Double.valueOf(((double) iIntValue) * dAbs), i11 >= 0 ? strArr[i11] : null);
                return;
            }
        }
        oVar.invoke(Double.valueOf(d10), null);
    }
}
