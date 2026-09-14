package Pj;

/* JADX INFO: loaded from: classes7.dex */
public final class c {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final double f17168a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final double f17169b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final double f17170c;

    public c(double d10, double d11, double d12) {
        this.f17168a = d10;
        this.f17169b = d11;
        this.f17170c = d12;
    }

    public final double a() {
        return this.f17169b;
    }

    public final double b() {
        return this.f17170c;
    }

    public final double c() {
        return this.f17168a;
    }

    public boolean equals(Object obj) {
        if (this == obj) {
            return true;
        }
        if (!(obj instanceof c)) {
            return false;
        }
        c cVar = (c) obj;
        return Double.compare(this.f17168a, cVar.f17168a) == 0 && Double.compare(this.f17169b, cVar.f17169b) == 0 && Double.compare(this.f17170c, cVar.f17170c) == 0;
    }

    public int hashCode() {
        return Double.hashCode(this.f17170c) + ((Double.hashCode(this.f17169b) + (Double.hashCode(this.f17168a) * 31)) * 31);
    }

    public String toString() {
        return "DcResult(up=" + this.f17168a + ", low=" + this.f17169b + ", mid=" + this.f17170c + ')';
    }
}
