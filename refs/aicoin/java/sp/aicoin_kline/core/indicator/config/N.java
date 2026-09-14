package sp.aicoin_kline.core.indicator.config;

import Qf.InterfaceC2632j;
import Sf.AbstractC2808w;
import java.util.ArrayList;
import java.util.List;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
public abstract class N extends F {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final InterfaceC2632j f142581l = Qf.k.b(new ek.D(this));

    public static final class a {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public final String f142582a;

        /* JADX INFO: renamed from: b, reason: collision with root package name */
        public final p292ng.g f142583b;

        /* JADX INFO: renamed from: c, reason: collision with root package name */
        public final int f142584c;

        /* JADX INFO: renamed from: d, reason: collision with root package name */
        public final boolean f142585d;

        /* JADX INFO: renamed from: e, reason: collision with root package name */
        public final int f142586e;

        /* JADX INFO: renamed from: f, reason: collision with root package name */
        public final float f142587f;

        public a(String str, p292ng.g gVar, int i10, boolean z10, int i11, float f10) {
            this.f142582a = str;
            this.f142583b = gVar;
            this.f142584c = i10;
            this.f142585d = z10;
            this.f142586e = i11;
            this.f142587f = f10;
        }

        public final int a() {
            return this.f142586e;
        }

        public final int b() {
            return this.f142584c;
        }

        public final float c() {
            return this.f142587f;
        }

        public final String d() {
            return this.f142582a;
        }

        public final p292ng.g e() {
            return this.f142583b;
        }

        public boolean equals(Object obj) {
            if (this == obj) {
                return true;
            }
            if (!(obj instanceof a)) {
                return false;
            }
            a aVar = (a) obj;
            return AbstractC7609s.f(this.f142582a, aVar.f142582a) && AbstractC7609s.f(this.f142583b, aVar.f142583b) && this.f142584c == aVar.f142584c && this.f142585d == aVar.f142585d && this.f142586e == aVar.f142586e && Float.compare(this.f142587f, aVar.f142587f) == 0;
        }

        public final boolean f() {
            return this.f142585d;
        }

        public int hashCode() {
            return Float.hashCode(this.f142587f) + ((Integer.hashCode(this.f142586e) + ((Boolean.hashCode(this.f142585d) + ((Integer.hashCode(this.f142584c) + ((this.f142583b.hashCode() + (this.f142582a.hashCode() * 31)) * 31)) * 31)) * 31)) * 31);
        }

        public String toString() {
            return "MatchedElement(name=" + this.f142582a + ", range=" + this.f142583b + ", default=" + this.f142584c + ", visible=" + this.f142585d + ", color=" + this.f142586e + ", lineSize=" + this.f142587f + ')';
        }
    }

    public static final a[] z(N n10) {
        return n10.B();
    }

    public ek.w[] A() {
        return new ek.w[0];
    }

    public abstract a[] B();

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int m() {
        return ((a[]) this.f142581l.getValue()).length;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean t() {
        return true;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        a[] aVarArr = (a[]) this.f142581l.getValue();
        ArrayList arrayList = new ArrayList(aVarArr.length);
        for (a aVar : aVarArr) {
            arrayList.add(new ek.m(aVar.d(), aVar.a(), aVar.c()));
        }
        return (ek.m[]) arrayList.toArray(new ek.m[0]);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        a[] aVarArr = (a[]) this.f142581l.getValue();
        ArrayList arrayList = new ArrayList(aVarArr.length);
        for (a aVar : aVarArr) {
            arrayList.add(new ek.w(aVar.d(), aVar.e(), aVar.b(), false, 0, 24, null));
        }
        List listU1 = Sf.z.u1(arrayList);
        AbstractC2808w.E(listU1, A());
        return (ek.w[]) listU1.toArray(new ek.w[0]);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        a[] aVarArr = (a[]) this.f142581l.getValue();
        ArrayList arrayList = new ArrayList(aVarArr.length);
        for (a aVar : aVarArr) {
            arrayList.add(new ek.I(aVar.d(), aVar.f()));
        }
        return (ek.I[]) arrayList.toArray(new ek.I[0]);
    }
}
