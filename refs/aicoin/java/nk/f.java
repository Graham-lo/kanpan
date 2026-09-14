package nk;

import java.math.BigDecimal;
import java.util.Locale;

/* JADX INFO: loaded from: classes7.dex */
public class f {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public int f134199a = -1;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public boolean f134200b = false;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public boolean f134201c = false;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public int f134203e = 0;

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public String f134204f = "..";

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public int f134202d = 2;

    /* JADX INFO: renamed from: i, reason: collision with root package name */
    public String f134207i = "%.2f";

    /* JADX INFO: renamed from: j, reason: collision with root package name */
    public String f134208j = "%,.2f";

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public int f134205g = 4;

    /* JADX INFO: renamed from: h, reason: collision with root package name */
    public boolean f134206h = true;

    public final int a(String str, int i10) {
        int iLastIndexOf;
        int length;
        int i11 = this.f134203e;
        if (!this.f134201c || i11 >= i10 || (iLastIndexOf = str.lastIndexOf(46)) == -1 || (length = str.length()) == 0) {
            return 0;
        }
        int i12 = length - 1;
        int iMin = i12;
        while (iMin >= 0 && str.charAt(iMin) == '0') {
            iMin--;
        }
        if (iMin == i12) {
            return 0;
        }
        if (iMin <= 0) {
            return i12;
        }
        if (i11 > 0) {
            iMin = Math.min(Math.max(iMin, iLastIndexOf + i11), i12);
        } else if (iMin == iLastIndexOf + 1) {
            iMin--;
        }
        return i12 - iMin;
    }

    public final String b(double d10, int i10, boolean z10) {
        String str;
        int i11 = this.f134205g;
        if (i11 != 4 && i10 >= 0) {
            try {
                d10 = BigDecimal.valueOf(d10).setScale(i10, i11).doubleValue();
            } catch (Exception e10) {
                e10.printStackTrace();
            }
        }
        if (z10) {
            str = this.f134200b ? this.f134208j : this.f134207i;
        } else {
            int iMax = Math.max(i10, 0);
            if (this.f134200b) {
                str = "%,." + iMax + "f";
            } else {
                str = "%." + iMax + "f";
            }
        }
        return String.format(Locale.getDefault(), str, Double.valueOf(d10));
    }

    public String c(double d10, int i10) {
        return d(d10, i10, 0);
    }

    public String d(double d10, int i10, int i11) {
        int iA;
        int i12 = this.f134199a;
        if (i12 == 0) {
            return "";
        }
        if (Math.abs(d10) < 1.0d && i11 > 0) {
            i10 += i11;
        }
        String strB = b(d10, i10, i10 == this.f134202d);
        if (i12 < 0 || strB.length() < i12) {
            int iA2 = a(strB, i10);
            if (iA2 > 0) {
                return strB.substring(0, Math.max(strB.length() - iA2, 0));
            }
        } else {
            int iA3 = a(strB, i10);
            if (strB.length() - iA3 >= i12) {
                int iLastIndexOf = strB.lastIndexOf(46);
                if (iLastIndexOf >= 0) {
                    if (iLastIndexOf == i12 || iLastIndexOf + 1 == i12) {
                        return b(d10, 0, false);
                    }
                    if (iLastIndexOf < i12) {
                        int i13 = (i12 - iLastIndexOf) - 1;
                        String strB2 = b(d10, i13, false);
                        return (!this.f134201c || i13 <= this.f134203e || (iA = a(strB2, i10)) <= 0) ? strB2 : strB2.substring(0, Math.max(strB2.length() - iA, 0));
                    }
                    if (!this.f134206h) {
                        return strB.substring(0, iLastIndexOf);
                    }
                }
                if (this.f134206h) {
                    int length = strB.length();
                    if (i12 <= 0) {
                        return "";
                    }
                    if (i12 < length) {
                        String str = this.f134204f;
                        int length2 = str.length();
                        if (length2 == i12) {
                            return str;
                        }
                        if (length2 > i12) {
                            return str.substring(0, i12);
                        }
                        return strB.substring(0, i12 - length2) + str;
                    }
                }
            } else if (iA3 > 0) {
                return strB.substring(0, Math.max(strB.length() - iA3, 0));
            }
        }
        return strB;
    }

    public f e(int i10) {
        if (i10 < 0) {
            i10 = -1;
        }
        this.f134199a = i10;
        return this;
    }
}
