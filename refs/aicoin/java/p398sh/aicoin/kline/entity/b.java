package p398sh.aicoin.kline.entity;

import java.util.Arrays;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
public final class b {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final int f140592a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final float[] f140593b;

    public b(int i10, float[] fArr) {
        this.f140592a = i10;
        this.f140593b = fArr;
    }

    public final int a() {
        return this.f140592a;
    }

    public final float[] b() {
        return this.f140593b;
    }

    public boolean equals(Object obj) {
        if (this == obj) {
            return true;
        }
        if (!(obj instanceof b)) {
            return false;
        }
        b bVar = (b) obj;
        return this.f140592a == bVar.f140592a && AbstractC7609s.f(this.f140593b, bVar.f140593b);
    }

    public int hashCode() {
        return (Integer.hashCode(this.f140592a) * 31) + Arrays.hashCode(this.f140593b);
    }

    public String toString() {
        return "KlineDrawingStyleEntity(iconResId=" + this.f140592a + ", lineDash=" + Arrays.toString(this.f140593b) + ")";
    }
}
