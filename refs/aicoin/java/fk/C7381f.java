package fk;

import kotlin.jvm.internal.DefaultConstructorMarker;

/* JADX INFO: renamed from: fk.f, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7381f {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final double f95381a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final double f95382b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final float f95383c;

    public C7381f(double d10, double d11, float f10) {
        this.f95381a = d10;
        this.f95382b = d11;
        this.f95383c = f10;
    }

    public /* synthetic */ C7381f(double d10, double d11, float f10, int i10, DefaultConstructorMarker defaultConstructorMarker) {
        this((i10 & 1) != 0 ? Double.NaN : d10, (i10 & 2) != 0 ? Double.NaN : d11, (i10 & 4) != 0 ? 50.0f : f10);
    }

    public final boolean a() {
        double d10 = this.f95381a;
        if (Double.isInfinite(d10) || Double.isNaN(d10)) {
            return false;
        }
        double d11 = this.f95382b;
        return (Double.isInfinite(d11) || Double.isNaN(d11)) ? false : true;
    }

    public final double b() {
        return this.f95382b;
    }

    public final float c() {
        return this.f95383c;
    }

    public final double d() {
        return this.f95381a;
    }

    public boolean equals(Object obj) {
        if (this == obj) {
            return true;
        }
        if (!(obj instanceof C7381f)) {
            return false;
        }
        C7381f c7381f = (C7381f) obj;
        return Double.compare(this.f95381a, c7381f.f95381a) == 0 && Double.compare(this.f95382b, c7381f.f95382b) == 0 && Float.compare(this.f95383c, c7381f.f95383c) == 0;
    }

    public int hashCode() {
        return Float.hashCode(this.f95383c) + ((Double.hashCode(this.f95382b) + (Double.hashCode(this.f95381a) * 31)) * 31);
    }

    public String toString() {
        return "AILargeTradeRadiusScale(minLogTurnover=" + this.f95381a + ", maxLogTurnover=" + this.f95382b + ", maxRadius=" + this.f95383c + ')';
    }
}
