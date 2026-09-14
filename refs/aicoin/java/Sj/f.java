package Sj;

import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
public final class f {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final long f20783a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final double f20784b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final String f20785c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public final String f20786d;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public final String f20787e;

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public final String f20788f;

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public final String f20789g;

    /* JADX INFO: renamed from: h, reason: collision with root package name */
    public final String f20790h;

    /* JADX INFO: renamed from: i, reason: collision with root package name */
    public final String f20791i;

    /* JADX INFO: renamed from: j, reason: collision with root package name */
    public final int f20792j;

    /* JADX INFO: renamed from: k, reason: collision with root package name */
    public final String f20793k;

    public f(long j10, double d10, String str, String str2, String str3, String str4, String str5, String str6, String str7, int i10, String str8) {
        this.f20783a = j10;
        this.f20784b = d10;
        this.f20785c = str;
        this.f20786d = str2;
        this.f20787e = str3;
        this.f20788f = str4;
        this.f20789g = str5;
        this.f20790h = str6;
        this.f20791i = str7;
        this.f20792j = i10;
        this.f20793k = str8;
    }

    public final String a() {
        return this.f20789g;
    }

    public final String b() {
        return this.f20786d;
    }

    public final String c() {
        return this.f20790h;
    }

    public final String d() {
        return this.f20791i;
    }

    public final int e() {
        return this.f20792j;
    }

    public boolean equals(Object obj) {
        if (this == obj) {
            return true;
        }
        if (!(obj instanceof f)) {
            return false;
        }
        f fVar = (f) obj;
        return this.f20783a == fVar.f20783a && Double.compare(this.f20784b, fVar.f20784b) == 0 && AbstractC7609s.f(this.f20785c, fVar.f20785c) && AbstractC7609s.f(this.f20786d, fVar.f20786d) && AbstractC7609s.f(this.f20787e, fVar.f20787e) && AbstractC7609s.f(this.f20788f, fVar.f20788f) && AbstractC7609s.f(this.f20789g, fVar.f20789g) && AbstractC7609s.f(this.f20790h, fVar.f20790h) && AbstractC7609s.f(this.f20791i, fVar.f20791i) && this.f20792j == fVar.f20792j && AbstractC7609s.f(this.f20793k, fVar.f20793k);
    }

    public final double f() {
        return this.f20784b;
    }

    public final String g() {
        return this.f20793k;
    }

    public final String h() {
        return this.f20787e;
    }

    public int hashCode() {
        return this.f20793k.hashCode() + ((Integer.hashCode(this.f20792j) + kk.d.a(this.f20791i, kk.d.a(this.f20790h, kk.d.a(this.f20789g, kk.d.a(this.f20788f, kk.d.a(this.f20787e, kk.d.a(this.f20786d, kk.d.a(this.f20785c, (Double.hashCode(this.f20784b) + (Long.hashCode(this.f20783a) * 31)) * 31, 31), 31), 31), 31), 31), 31), 31)) * 31);
    }

    public final String i() {
        return this.f20785c;
    }

    public final long j() {
        return this.f20783a;
    }

    public final String k() {
        return this.f20788f;
    }

    public String toString() {
        return "IndicSignalGraphData(time=" + this.f20783a + ", price=" + this.f20784b + ", side=" + this.f20785c + ", name=" + this.f20786d + ", show=" + this.f20787e + ", triggerShow=" + this.f20788f + ", id=" + this.f20789g + ", param=" + this.f20790h + ", period=" + this.f20791i + ", periodNum=" + this.f20792j + ", remark=" + this.f20793k + ')';
    }
}
