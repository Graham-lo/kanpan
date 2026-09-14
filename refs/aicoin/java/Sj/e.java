package Sj;

import java.util.List;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
public final class e {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final float f20777a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final float f20778b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final List f20779c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public final List f20780d;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public final List f20781e;

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public final List f20782f;

    public e(float f10, float f11, List list, List list2, List list3, List list4) {
        this.f20777a = f10;
        this.f20778b = f11;
        this.f20779c = list;
        this.f20780d = list2;
        this.f20781e = list3;
        this.f20782f = list4;
    }

    public final float a() {
        return this.f20777a;
    }

    public final float b() {
        return this.f20778b;
    }

    public final List c() {
        return this.f20781e;
    }

    public final List d() {
        return this.f20779c;
    }

    public final List e() {
        return this.f20780d;
    }

    public boolean equals(Object obj) {
        if (this == obj) {
            return true;
        }
        if (!(obj instanceof e)) {
            return false;
        }
        e eVar = (e) obj;
        return Float.compare(this.f20777a, eVar.f20777a) == 0 && Float.compare(this.f20778b, eVar.f20778b) == 0 && AbstractC7609s.f(this.f20779c, eVar.f20779c) && AbstractC7609s.f(this.f20780d, eVar.f20780d) && AbstractC7609s.f(this.f20781e, eVar.f20781e) && AbstractC7609s.f(this.f20782f, eVar.f20782f);
    }

    public int hashCode() {
        return this.f20782f.hashCode() + ((this.f20781e.hashCode() + ((this.f20780d.hashCode() + ((this.f20779c.hashCode() + kk.a.a(this.f20778b, Float.hashCode(this.f20777a) * 31, 31)) * 31)) * 31)) * 31);
    }

    public String toString() {
        return "HeatLiquidationInfoWindowState(anchorX=" + this.f20777a + ", anchorY=" + this.f20778b + ", turnoverGrid=" + this.f20779c + ", turnoverGridColors=" + this.f20780d + ", priceColumn=" + this.f20781e + ", priceColumnColors=" + this.f20782f + ')';
    }
}
