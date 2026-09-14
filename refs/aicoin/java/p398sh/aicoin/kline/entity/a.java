package p398sh.aicoin.kline.entity;

import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
public final class a {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final String f140589a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final int f140590b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final int f140591c;

    public a(String str, int i10, int i11) {
        this.f140589a = str;
        this.f140590b = i10;
        this.f140591c = i11;
    }

    public final int a() {
        return this.f140591c;
    }

    public final int b() {
        return this.f140590b;
    }

    public final String c() {
        return this.f140589a;
    }

    public boolean equals(Object obj) {
        if (this == obj) {
            return true;
        }
        if (!(obj instanceof a)) {
            return false;
        }
        a aVar = (a) obj;
        return AbstractC7609s.f(this.f140589a, aVar.f140589a) && this.f140590b == aVar.f140590b && this.f140591c == aVar.f140591c;
    }

    public int hashCode() {
        return (((this.f140589a.hashCode() * 31) + Integer.hashCode(this.f140590b)) * 31) + Integer.hashCode(this.f140591c);
    }

    public String toString() {
        return "DrawingMenuItem(type=" + this.f140589a + ", showNameSrcId=" + this.f140590b + ", iconSrcId=" + this.f140591c + ")";
    }
}
