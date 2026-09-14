package nk;

import java.math.RoundingMode;
import java.text.DecimalFormat;

/* JADX INFO: loaded from: classes7.dex */
public final class j {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final j f134218a = new j();

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public static final DecimalFormat f134219b;

    static {
        DecimalFormat decimalFormat = new DecimalFormat("#.####");
        decimalFormat.setRoundingMode(RoundingMode.FLOOR);
        f134219b = decimalFormat;
    }

    public final String a(double d10) {
        return f134219b.format(d10);
    }
}
