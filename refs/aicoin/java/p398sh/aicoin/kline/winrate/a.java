package p398sh.aicoin.kline.winrate;

import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
public final class a {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final String f140690a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final long f140691b;

    public a(String str, long j10) {
        this.f140690a = str;
        this.f140691b = j10;
    }

    public final String a() {
        return this.f140690a;
    }

    public final long b() {
        return this.f140691b;
    }

    public boolean equals(Object obj) {
        if (this == obj) {
            return true;
        }
        if (!(obj instanceof a)) {
            return false;
        }
        a aVar = (a) obj;
        return AbstractC7609s.f(this.f140690a, aVar.f140690a) && this.f140691b == aVar.f140691b;
    }

    public int hashCode() {
        return (this.f140690a.hashCode() * 31) + Long.hashCode(this.f140691b);
    }

    public String toString() {
        return "MinusCloseParam(tickerKey=" + this.f140690a + ", time=" + this.f140691b + ")";
    }
}
