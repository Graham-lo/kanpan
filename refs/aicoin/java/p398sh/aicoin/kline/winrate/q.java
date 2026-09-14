package p398sh.aicoin.kline.winrate;

import java.util.List;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
public final class q {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final List f140738a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public boolean f140739b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final long f140740c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public final String f140741d;

    public q(List list, boolean z10, long j10, String str) {
        this.f140738a = list;
        this.f140739b = z10;
        this.f140740c = j10;
        this.f140741d = str;
    }

    public final long a() {
        return this.f140740c;
    }

    public final boolean b() {
        return this.f140739b;
    }

    public final String c() {
        return this.f140741d;
    }

    public final List d() {
        return this.f140738a;
    }

    public final void e(boolean z10) {
        this.f140739b = z10;
    }

    public boolean equals(Object obj) {
        if (this == obj) {
            return true;
        }
        if (!(obj instanceof q)) {
            return false;
        }
        q qVar = (q) obj;
        return AbstractC7609s.f(this.f140738a, qVar.f140738a) && this.f140739b == qVar.f140739b && this.f140740c == qVar.f140740c && AbstractC7609s.f(this.f140741d, qVar.f140741d);
    }

    public int hashCode() {
        return (((((this.f140738a.hashCode() * 31) + Boolean.hashCode(this.f140739b)) * 31) + Long.hashCode(this.f140740c)) * 31) + this.f140741d.hashCode();
    }

    public String toString() {
        return "WinRateResult(winRateList=" + this.f140738a + ", resetStatus=" + this.f140739b + ", latestTime=" + this.f140740c + ", tickerKey=" + this.f140741d + ")";
    }
}
