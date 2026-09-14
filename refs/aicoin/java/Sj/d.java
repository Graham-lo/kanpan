package Sj;

import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
public final class d {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final double f20771a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final double f20772b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final int f20773c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public final double f20774d;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public final String f20775e;

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public final int f20776f;

    public d(double d10, double d11, int i10, double d12, String str, int i11) {
        this.f20771a = d10;
        this.f20772b = d11;
        this.f20773c = i10;
        this.f20774d = d12;
        this.f20775e = str;
        this.f20776f = i11;
    }

    public final int a() {
        return this.f20773c;
    }

    public final int b() {
        return this.f20776f;
    }

    public final double c() {
        return this.f20771a;
    }

    public final double d() {
        return this.f20772b;
    }

    public final double e() {
        return this.f20774d;
    }

    public boolean equals(Object obj) {
        if (this == obj) {
            return true;
        }
        if (!(obj instanceof d)) {
            return false;
        }
        d dVar = (d) obj;
        return Double.compare(this.f20771a, dVar.f20771a) == 0 && Double.compare(this.f20772b, dVar.f20772b) == 0 && this.f20773c == dVar.f20773c && Double.compare(this.f20774d, dVar.f20774d) == 0 && AbstractC7609s.f(this.f20775e, dVar.f20775e) && this.f20776f == dVar.f20776f;
    }

    public int hashCode() {
        return Integer.hashCode(this.f20776f) + kk.d.a(this.f20775e, (Double.hashCode(this.f20774d) + ((Integer.hashCode(this.f20773c) + ((Double.hashCode(this.f20772b) + (Double.hashCode(this.f20771a) * 31)) * 31)) * 31)) * 31, 31);
    }

    public String toString() {
        return "HeatLiquidationDrawItem(fromPrice=" + this.f20771a + ", toPrice=" + this.f20772b + ", color=" + this.f20773c + ", turnover=" + this.f20774d + ", turnoverText=" + this.f20775e + ", colorDark=" + this.f20776f + ')';
    }
}
