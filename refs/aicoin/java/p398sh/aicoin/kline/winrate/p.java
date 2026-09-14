package p398sh.aicoin.kline.winrate;

import java.util.List;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
public final class p {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final String f140735a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final List f140736b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final long f140737c;

    public p(String str, List list, long j10) {
        this.f140735a = str;
        this.f140736b = list;
        this.f140737c = j10;
    }

    public final long a() {
        return this.f140737c;
    }

    public final List b() {
        return this.f140736b;
    }

    public final String c() {
        return this.f140735a;
    }

    public boolean equals(Object obj) {
        if (this == obj) {
            return true;
        }
        if (!(obj instanceof p)) {
            return false;
        }
        p pVar = (p) obj;
        return AbstractC7609s.f(this.f140735a, pVar.f140735a) && AbstractC7609s.f(this.f140736b, pVar.f140736b) && this.f140737c == pVar.f140737c;
    }

    public int hashCode() {
        return (((this.f140735a.hashCode() * 31) + this.f140736b.hashCode()) * 31) + Long.hashCode(this.f140737c);
    }

    public String toString() {
        return "WinRateRequestParam(symbol=" + this.f140735a + ", signals=" + this.f140736b + ", latestTime=" + this.f140737c + ")";
    }
}
