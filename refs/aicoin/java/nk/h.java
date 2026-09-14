package nk;

import Qf.H;
import android.content.Context;
import java.util.Arrays;
import java.util.Locale;
import p167hg.M;
import p167hg.T;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class h {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final h f134211a = new h();

    public static final H a(M m10, int i10, double d10, String str) {
        if (str != null && str.length() != 0) {
            m10.f97909a = A.b(d10, i10) + str;
        }
        return H.f17640a;
    }

    public static String b(double d10, int i10) {
        M m10 = new M();
        KLineManager.a aVar = KLineManager.f142490O;
        Context contextW = aVar.a().w();
        if (contextW == null) {
            contextW = aVar.a().i();
        }
        l.s(contextW, d10, !l.f134222a.r(contextW), new g(m10, i10));
        return (String) m10.f97909a;
    }

    public static /* synthetic */ String d(h hVar, double d10, String str, int i10, int i11, Object obj) {
        if ((i11 & 4) != 0) {
            i10 = 2;
        }
        return hVar.c(d10, str, i10);
    }

    public static /* synthetic */ String f(h hVar, double d10, String str, int i10, int i11, Object obj) {
        if ((i11 & 4) != 0) {
            i10 = 2;
        }
        return hVar.e(d10, str, i10);
    }

    public static /* synthetic */ String i(h hVar, double d10, boolean z10, int i10, Rj.r rVar, int i11, Object obj) {
        if ((i11 & 2) != 0) {
            z10 = false;
        }
        boolean z11 = z10;
        if ((i11 & 4) != 0) {
            i10 = 2;
        }
        int i12 = i10;
        if ((i11 & 8) != 0) {
            rVar = null;
        }
        return hVar.h(d10, z11, i12, rVar);
    }

    public final String c(double d10, String str, int i10) {
        return e(d10, str, i10);
    }

    /* JADX WARN: Code duplicated, block: B:32:0x00a1  */
    public final String e(double d10, String str, int i10) {
        String str2;
        String strB;
        if (KLineManager.f142490O.a().R()) {
            if (d10 != 0.0d && Math.abs(d10) < 1.0d) {
                String str3 = d10 < 0.0d ? "-" : "";
                T t10 = T.f97914a;
                String str4 = String.format(Locale.US, "%.10f", Arrays.copyOf(new Object[]{Double.valueOf(Math.abs(d10))}, 1));
                int iF0 = Ah.y.f0(str4, '.', 0, false, 6, null);
                if (iF0 == -1) {
                    str2 = null;
                } else {
                    int i11 = iF0 + 1;
                    int i12 = 0;
                    while (i11 < str4.length() && str4.charAt(i11) == '0') {
                        i12++;
                        i11++;
                    }
                    if (i12 <= 2 || i11 >= str4.length()) {
                        str2 = null;
                    } else {
                        String strI1 = Ah.y.i1(str4.substring(i11), '0');
                        if (strI1.length() == 0) {
                            str2 = null;
                        } else {
                            str2 = str3 + "0.0{" + i12 + '}' + strI1;
                        }
                    }
                }
            } else {
                str2 = null;
            }
            if (str2 != null) {
                return str2;
            }
            if (Math.abs(d10) >= 1000.0d && (strB = b(d10, i10)) != null) {
                return strB;
            }
        }
        return str;
    }

    public final String g(double d10, Rj.r rVar) {
        return e(d10, rVar != null ? l.f134222a.j(d10, rVar) : l.f134222a.h(Double.valueOf(d10)), 2);
    }

    public final String h(double d10, boolean z10, int i10, Rj.r rVar) {
        double d11 = d10 / ((double) 1000000);
        if (Math.abs(d11) > 1.0d) {
            return A.b(d11, i10) + 'M';
        }
        double d12 = d10 / ((double) 1000);
        if (Math.abs(d12) > 1.0d) {
            return A.b(d12, i10) + 'K';
        }
        if (!z10) {
            return rVar != null ? l.f134222a.j(d10, rVar) : l.f134222a.h(Double.valueOf(d10));
        }
        return A.b(d12, i10) + 'K';
    }
}
