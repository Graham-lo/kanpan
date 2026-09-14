package p398sh.aicoin.kline.entity;

/* JADX INFO: loaded from: classes7.dex */
public final class c {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final int f140594a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final float f140595b;

    public c(int i10, float f10) {
        this.f140594a = i10;
        this.f140595b = f10;
    }

    public final int a() {
        return this.f140594a;
    }

    public final float b() {
        return this.f140595b;
    }

    public boolean equals(Object obj) {
        if (this == obj) {
            return true;
        }
        if (!(obj instanceof c)) {
            return false;
        }
        c cVar = (c) obj;
        return this.f140594a == cVar.f140594a && Float.compare(this.f140595b, cVar.f140595b) == 0;
    }

    public int hashCode() {
        return (Integer.hashCode(this.f140594a) * 31) + Float.hashCode(this.f140595b);
    }

    public String toString() {
        return "KlineDrawingWidthEntity(iconResId=" + this.f140594a + ", width=" + this.f140595b + ")";
    }
}
