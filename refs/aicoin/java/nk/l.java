package nk;

import Qf.H;
import android.content.Context;
import android.content.res.Resources;
import android.util.TypedValue;
import java.math.RoundingMode;
import java.text.NumberFormat;
import java.util.Arrays;
import java.util.Locale;
import p167hg.AbstractC7609s;
import p167hg.M;
import p167hg.T;
import sp.aicoin_kline.R;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class l {

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public static String f134223b;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public static int f134226e;

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public static int f134227f;

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public static final NumberFormat f134228g;

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final l f134222a = new l();

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public static String[] f134224c = new String[0];

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public static String[] f134225d = new String[0];

    static {
        NumberFormat numberFormat = NumberFormat.getInstance();
        numberFormat.setGroupingUsed(true);
        numberFormat.setMaximumFractionDigits(2);
        numberFormat.setMinimumFractionDigits(2);
        numberFormat.setRoundingMode(RoundingMode.HALF_UP);
        f134228g = numberFormat;
    }

    public static final H a(M m10, String str, double d10, String str2) {
        StringBuilder sb2 = new StringBuilder();
        sb2.append(str);
        sb2.append(f134228g.format(d10));
        if (str2 == null) {
            str2 = "";
        }
        sb2.append(str2);
        m10.f97909a = sb2.toString();
        return H.f17640a;
    }

    public static Context b() {
        KLineManager.a aVar = KLineManager.f142490O;
        Context contextW = aVar.a().w();
        return contextW == null ? aVar.a().i() : contextW;
    }

    public static String c(Context context, Double d10, int i10, boolean z10) {
        M m10 = new M();
        m10.f97909a = "-";
        NumberFormat numberFormat = f134228g;
        numberFormat.setGroupingUsed(true);
        numberFormat.setMaximumFractionDigits(i10);
        numberFormat.setMinimumFractionDigits(((Number) p162hb.e.c(z10, 0, Integer.valueOf(i10))).intValue());
        numberFormat.setRoundingMode(RoundingMode.HALF_UP);
        if (d10.doubleValue() >= 0.0d) {
            s(context, d10.doubleValue(), false, new k(m10, ""));
        }
        return (String) m10.f97909a;
    }

    public static String d(l lVar, Context context, Double d10, boolean z10, int i10) {
        int i11 = 2;
        if ((i10 & 4) != 0) {
            double dAbs = Math.abs(d10.doubleValue());
            if (lVar.r(b()) && (dAbs >= Math.pow(10.0d, 11.0d) || ((dAbs >= Math.pow(10.0d, 7.0d) && dAbs < Math.pow(10.0d, 8.0d)) || (dAbs >= Math.pow(10.0d, 3.0d) && dAbs < Math.pow(10.0d, 4.0d))))) {
                i11 = 0;
            }
        }
        if ((i10 & 128) != 0) {
            z10 = false;
        }
        return c(context, d10, i11, z10);
    }

    public static /* synthetic */ String f(l lVar, double d10, boolean z10, boolean z11, int i10, Object obj) {
        if ((i10 & 2) != 0) {
            z10 = false;
        }
        if ((i10 & 4) != 0) {
            z11 = false;
        }
        return lVar.e(d10, z10, z11);
    }

    public static /* synthetic */ String k(l lVar, double d10, int i10, Rj.r rVar, int i11, Object obj) {
        if ((i11 & 4) != 0) {
            rVar = null;
        }
        return lVar.i(d10, i10, rVar);
    }

    public static /* synthetic */ String l(l lVar, double d10, Rj.r rVar, int i10, Object obj) {
        if ((i10 & 2) != 0) {
            rVar = null;
        }
        return lVar.j(d10, rVar);
    }

    public static /* synthetic */ String n(l lVar, double d10, int i10, int i11, int i12, Rj.r rVar, int i13, Object obj) {
        if ((i13 & 8) != 0) {
            i12 = KLineManager.f142490O.a().j();
        }
        int i14 = i12;
        if ((i13 & 16) != 0) {
            rVar = null;
        }
        return lVar.m(d10, i10, i11, i14, rVar);
    }

    public static final float o(int i10, float f10) {
        return p(KLineManager.f142490O.a().i(), i10, f10);
    }

    public static final float p(Context context, int i10, float f10) {
        return TypedValue.applyDimension(i10, f10, (context == null ? Resources.getSystem() : context.getResources()).getDisplayMetrics());
    }

    public static final void s(Context context, double d10, boolean z10, p146gg.o oVar) {
        f134222a.getClass();
        String languageTag = context.getResources().getConfiguration().locale.toLanguageTag();
        if (!AbstractC7609s.f(f134223b, languageTag)) {
            f134223b = languageTag;
            f134224c = context.getResources().getStringArray(R.array.kline_digit_gap_labels);
            f134225d = context.getResources().getStringArray(R.array.kline_digit_gap_labels_en);
            f134226e = context.getResources().getInteger(R.integer.kline_digit_gap_value);
            f134227f = context.getResources().getInteger(R.integer.kline_digit_gap_value_en);
        }
        if (z10) {
            t.f134247a.a(d10, f134225d, f134227f, oVar);
        } else {
            t.f134247a.a(d10, f134224c, f134226e, oVar);
        }
    }

    public final String e(double d10, boolean z10, boolean z11) {
        NumberFormat numberFormat = f134228g;
        numberFormat.setGroupingUsed(true);
        numberFormat.setMaximumFractionDigits(2);
        numberFormat.setMinimumFractionDigits(((Number) p162hb.e.c(z10, 0, 2)).intValue());
        numberFormat.setRoundingMode(RoundingMode.HALF_UP);
        return z11 ? d(this, b(), Double.valueOf(d10), z10, 124) : numberFormat.format(d10);
    }

    public final String g(Double d10, String str) {
        String str2;
        double dDoubleValue = d10 != null ? d10.doubleValue() : 0.0d;
        if (AbstractC7609s.f(str, "publicScript-activeTradeVolume")) {
            T t10 = T.f97914a;
            str2 = String.format(Locale.US, "%.5f", Arrays.copyOf(new Object[]{Double.valueOf(dDoubleValue)}, 1));
        } else {
            T t11 = T.f97914a;
            str2 = String.format(Locale.US, "%.10f", Arrays.copyOf(new Object[]{Double.valueOf(dDoubleValue)}, 1));
        }
        String str3 = str2;
        int iF0 = Ah.y.f0(str3, '.', 0, false, 6, null);
        if (iF0 != -1) {
            int i10 = iF0 + 1;
            int i11 = 0;
            while (i10 < str3.length() && str3.charAt(i10) == '0') {
                i11++;
                i10++;
            }
            String strSubstring = str3.substring(i10);
            if (i11 > 2) {
                str3 = "0.0{" + i11 + '}' + strSubstring;
            }
        }
        return t(str3);
    }

    public final String h(Double d10) {
        T t10 = T.f97914a;
        return t(String.format(Locale.getDefault(), "%.5f", Arrays.copyOf(new Object[]{d10}, 1)));
    }

    public final String i(double d10, int i10, Rj.r rVar) {
        if (rVar == null || !rVar.b() || d10 < rVar.a()) {
            return i10 < 0 ? s.f134244a.a(d10, 0) : s.f134244a.a(d10, i10);
        }
        return d(this, b(), Double.valueOf(d10), false, 248);
    }

    public final String j(double d10, Rj.r rVar) {
        if (rVar != null && rVar.b() && d10 >= rVar.a()) {
            return d(this, b(), Double.valueOf(d10), false, 248);
        }
        int iJ = KLineManager.f142490O.a().j();
        return s.f134244a.a(d10, iJ >= 0 ? iJ : 0);
    }

    public final String m(double d10, int i10, int i11, int i12, Rj.r rVar) {
        if (rVar != null && rVar.b() && d10 >= rVar.a()) {
            return d(this, b(), Double.valueOf(d10), false, 248);
        }
        int iMin = i12 >= 0 ? i12 < i11 ? Math.min(i10 + i12, i11) : i12 : 0;
        T t10 = T.f97914a;
        return String.format(Locale.getDefault(), "%." + iMin + 'f', Arrays.copyOf(new Object[]{Double.valueOf(d10)}, 1));
    }

    public final String q(int i10) {
        return KLineManager.f142490O.a().i().getString(i10);
    }

    public final boolean r(Context context) {
        return Ah.y.R(context.getResources().getConfiguration().locale.getLanguage(), "zh", true);
    }

    public final String t(String str) {
        if (Ah.y.g0(str, ".", 0, false, 6, null) <= 0) {
            return str;
        }
        return new Ah.l("[.]$").h(new Ah.l("0+?$").h(str, ""), "");
    }
}
