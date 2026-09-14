package p398sh.aicoin.kline.db;

import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
public final class i {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final String f140587a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final boolean f140588b;

    public i(String str, boolean z10) {
        this.f140587a = str;
        this.f140588b = z10;
    }

    public final String a() {
        return this.f140587a;
    }

    public final boolean b() {
        return this.f140588b;
    }

    public boolean equals(Object obj) {
        if (this == obj) {
            return true;
        }
        if (!(obj instanceof i)) {
            return false;
        }
        i iVar = (i) obj;
        return AbstractC7609s.f(this.f140587a, iVar.f140587a) && this.f140588b == iVar.f140588b;
    }

    public int hashCode() {
        return (this.f140587a.hashCode() * 31) + Boolean.hashCode(this.f140588b);
    }

    public String toString() {
        return "WinRateSelect(key=" + this.f140587a + ", isSelect=" + this.f140588b + ")";
    }
}
