package Sj;

import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
public final class k {

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public static final a f20817e = new a(null);

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public String f20818a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public String f20819b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public String f20820c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public int f20821d;

    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public k(String str, String str2, String str3, int i10) {
        this.f20818a = str;
        this.f20819b = str2;
        this.f20820c = str3;
        this.f20821d = i10;
    }

    public final String a() {
        return this.f20818a;
    }

    public final String b() {
        return this.f20819b;
    }

    public final int c() {
        return this.f20821d;
    }

    public final String d() {
        return this.f20820c;
    }

    public boolean equals(Object obj) {
        if (this == obj) {
            return true;
        }
        if (!(obj instanceof k)) {
            return false;
        }
        k kVar = (k) obj;
        return AbstractC7609s.f(this.f20818a, kVar.f20818a) && AbstractC7609s.f(this.f20819b, kVar.f20819b) && AbstractC7609s.f(this.f20820c, kVar.f20820c) && this.f20821d == kVar.f20821d;
    }

    public int hashCode() {
        return Integer.hashCode(this.f20821d) + kk.d.a(this.f20820c, kk.d.a(this.f20819b, this.f20818a.hashCode() * 31, 31), 31);
    }

    public String toString() {
        return "WinRateTitleItem(name=" + this.f20818a + ", side=" + this.f20819b + ", time=" + this.f20820c + ", sideColorType=" + this.f20821d + ')';
    }
}
