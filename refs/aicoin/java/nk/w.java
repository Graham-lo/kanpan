package nk;

import Sf.N;
import androidx.p022lifecycle.CoroutineLiveDataKt;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Date;
import java.util.Map;

/* JADX INFO: loaded from: classes7.dex */
public final class w {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final w f134250a = new w();

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public static final Calendar f134251b = Calendar.getInstance();

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public static final SimpleDateFormat f134252c = new SimpleDateFormat("yyyy");

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public static final SimpleDateFormat f134253d = new SimpleDateFormat("yyyy年M月");

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public static final SimpleDateFormat f134254e = new SimpleDateFormat("M月");

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public static final SimpleDateFormat f134255f = new SimpleDateFormat("M月d");

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public static final SimpleDateFormat f134256g = new SimpleDateFormat("HH:mm");

    /* JADX INFO: renamed from: h, reason: collision with root package name */
    public static final SimpleDateFormat f134257h = new SimpleDateFormat("HH:mm:ss");

    /* JADX INFO: renamed from: i, reason: collision with root package name */
    public static final SimpleDateFormat f134258i = new SimpleDateFormat("M月d日HH:mm");

    /* JADX INFO: renamed from: j, reason: collision with root package name */
    public static final long[] f134259j = {CoroutineLiveDataKt.DEFAULT_TIMEOUT, 10000, 15000, 30000, 300000, 600000, 900000, 1800000, 3600000, 7200000, 10800000, 14400000, 21600000, 28800000, 43200000, 86400000, 172800000, 259200000, 432000000, 518400000, 777600000, 1296000000, 1382400000, 2592000000L, 5184000000L, 7776000000L, 10368000000L, 15552000000L, 31104000000L, 62208000000L, 93312000000L, 186624000000L, 373248000000L, 559872000000L, 1119744000000L, 2239488000000L, 3110400000000L};

    public static final boolean a(long j10, long j11, int i10) {
        long[] jArr = f134259j;
        if (i10 >= jArr.length) {
            return false;
        }
        int i11 = (int) (jArr[i10] / 86400000);
        f134251b.setTime(new Date(j11));
        return i11 != 0 && (j11 - j10) % jArr[i10] == 0;
    }

    public static final boolean b(long j10, long j11, long j12, int i10) {
        long[] jArr = f134259j;
        if (i10 >= jArr.length) {
            return false;
        }
        int i11 = (int) (jArr[i10] / 86400000);
        Calendar calendar = f134251b;
        calendar.setTime(new Date(j12));
        return i11 != 0 && (j12 - j10) % jArr[i10] == 0 && (j11 < jArr[8] || x(j12, j11) || calendar.get(11) == 0);
    }

    public static final boolean c(long j10, int i10, int i11) {
        long[] jArr = f134259j;
        if (i10 >= jArr.length) {
            return false;
        }
        int i12 = (int) (jArr[i10] / 2592000000L);
        Calendar calendar = f134251b;
        calendar.setTime(new Date(j10));
        return i12 != 0 && calendar.get(2) % i12 == 0 && calendar.get(5) <= i11;
    }

    public static final boolean d(long j10, long j11, int i10) {
        long[] jArr = f134259j;
        return i10 < jArr.length && (j11 - j10) % jArr[i10] == 0;
    }

    public static /* synthetic */ boolean e(long j10, int i10, int i11, int i12, Object obj) {
        if ((i12 & 4) != 0) {
            i11 = 40;
        }
        return c(j10, i10, i11);
    }

    public static final boolean f(long j10, int i10) {
        long[] jArr = f134259j;
        if (i10 >= jArr.length) {
            return false;
        }
        int i11 = (int) (jArr[i10] / 31104000000L);
        Calendar calendar = f134251b;
        calendar.setTime(new Date(j10));
        return i11 != 0 && calendar.get(1) % i11 == 0;
    }

    /* JADX WARN: Code duplicated, block: B:19:0x0036  */
    public static final Map h(long j10) {
        int i10;
        long j11;
        int i11 = 1;
        if (j10 < 60000) {
            i10 = 13;
        } else if (j10 < 3600000) {
            i10 = 12;
        } else if (j10 <= 43200000) {
            i10 = 10;
        } else if (j10 <= 1296000000) {
            i10 = 5;
        } else if (j10 < 31104000000L) {
            i10 = 2;
        } else if (j10 >= 31104000000L) {
            i10 = 1;
        } else {
            i10 = 5;
        }
        if (j10 <= 1800000) {
            j11 = j10 / 60000;
        } else {
            if (j10 > 43200000) {
                if (j10 <= 1296000000) {
                    j11 = j10 / 86400000;
                } else if (j10 < 31104000000L) {
                    int i12 = (int) (j10 / 86400000);
                    i11 = i12 / 30;
                    if (i12 % 30 > 20) {
                        i11++;
                    }
                } else if (j10 >= 31104000000L) {
                    i11 = ((int) (j10 / 86400000)) / 360;
                }
                return N.n(Qf.w.a("field", Integer.valueOf(i10)), Qf.w.a("amount", Integer.valueOf(i11)));
            }
            j11 = j10 / 3600000;
        }
        i11 = (int) j11;
        return N.n(Qf.w.a("field", Integer.valueOf(i10)), Qf.w.a("amount", Integer.valueOf(i11)));
    }

    public static final int i(long j10) {
        Calendar calendar = f134251b;
        calendar.setTime(new Date(j10));
        return calendar.get(11);
    }

    public static final boolean q(long j10) {
        Calendar calendar = f134251b;
        calendar.setTime(new Date(j10));
        return calendar.get(5) == 1;
    }

    public static final boolean r(long j10) {
        Calendar calendar = f134251b;
        calendar.setTime(new Date(j10));
        return calendar.get(6) == 1;
    }

    public static final boolean s(long j10, boolean z10) {
        Calendar calendar = f134251b;
        calendar.setTime(new Date(j10));
        if (calendar.get(11) != 0) {
            return calendar.get(11) == 8 && z10;
        }
        return true;
    }

    public static final boolean t(long j10, boolean z10) {
        Calendar calendar = f134251b;
        calendar.setTime(new Date(j10));
        return s(j10, z10) && calendar.get(5) == 1;
    }

    public static final boolean u(long j10) {
        Calendar calendar = f134251b;
        calendar.setTime(new Date(j10));
        return calendar.get(12) == 0 && calendar.get(11) == 0;
    }

    public static final boolean v(long j10) {
        Calendar calendar = f134251b;
        calendar.setTime(new Date(j10));
        return calendar.get(2) == 0;
    }

    public static final boolean w(long j10, int i10) {
        Calendar calendar = f134251b;
        calendar.setTime(new Date(j10));
        int i11 = calendar.get(11);
        int i12 = calendar.get(12);
        if (i10 <= 4) {
            return i11 == 0 && i12 == 0;
        }
        if (i10 == 6 || i10 == 8) {
            return i11 == 0 || i11 == 2;
        }
        if (10 > i10 || i10 >= 18) {
            return i11 == 0;
        }
        return i11 == 0 || i11 == 8;
    }

    public static final boolean x(long j10, long j11) {
        Calendar calendar = f134251b;
        calendar.setTime(new Date(j10));
        int i10 = calendar.get(11);
        int i11 = calendar.get(12);
        if (j11 <= 1800000) {
            return i11 == 0;
        }
        if (j11 == 10800000 || j11 == 21600000) {
            return i10 == 0 || i10 == 2;
        }
        if (j11 < 43200000 || j11 > 1296000000) {
            return i10 == 0;
        }
        return i10 == 0 || i10 == 8;
    }

    public final SimpleDateFormat g() {
        return f134255f;
    }

    public final SimpleDateFormat j() {
        return f134254e;
    }

    public final int k(long j10, long j11, long j12) {
        return (int) ((j12 - j11) / j10);
    }

    public final SimpleDateFormat l() {
        return f134257h;
    }

    public final SimpleDateFormat m() {
        return f134256g;
    }

    public final long[] n() {
        return f134259j;
    }

    public final SimpleDateFormat o() {
        return f134252c;
    }

    public final SimpleDateFormat p() {
        return f134253d;
    }
}
