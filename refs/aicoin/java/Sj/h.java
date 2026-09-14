package Sj;

/* JADX INFO: loaded from: classes7.dex */
public final class h {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final long f20796a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final double f20797b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final double f20798c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public final int f20799d;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public final int f20800e;

    public h(long j10, double d10, double d11, int i10, int i11) {
        this.f20796a = j10;
        this.f20797b = d10;
        this.f20798c = d11;
        this.f20799d = i10;
        this.f20800e = i11;
    }

    public final int a() {
        return this.f20799d;
    }

    public final double b() {
        return this.f20797b;
    }

    public final int c() {
        return this.f20800e;
    }

    public final double d() {
        return this.f20798c;
    }

    public final long e() {
        return this.f20796a;
    }

    public boolean equals(Object obj) {
        if (this == obj) {
            return true;
        }
        if (!(obj instanceof h)) {
            return false;
        }
        h hVar = (h) obj;
        return this.f20796a == hVar.f20796a && Double.compare(this.f20797b, hVar.f20797b) == 0 && Double.compare(this.f20798c, hVar.f20798c) == 0 && this.f20799d == hVar.f20799d && this.f20800e == hVar.f20800e;
    }

    public int hashCode() {
        return Integer.hashCode(this.f20800e) + ((Integer.hashCode(this.f20799d) + ((Double.hashCode(this.f20798c) + ((Double.hashCode(this.f20797b) + (Long.hashCode(this.f20796a) * 31)) * 31)) * 31)) * 31);
    }

    public String toString() {
        return "OrderNumItem(time=" + this.f20796a + ", buyPrice=" + this.f20797b + ", sellPrice=" + this.f20798c + ", buyNum=" + this.f20799d + ", sellNum=" + this.f20800e + ')';
    }
}
