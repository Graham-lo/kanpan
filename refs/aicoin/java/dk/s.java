package dk;

import Qf.InterfaceC2632j;
import Rj.C2741q;
import Rj.C2765z;
import Sf.AbstractC2801o;
import Sf.AbstractC2804s;
import Sf.z;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import kotlin.jvm.functions.Function1;

/* JADX INFO: loaded from: classes7.dex */
public final class s {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final C2741q f92544a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final C2765z f92545b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final List f92546c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public final int f92547d;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public final int f92548e;

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public final InterfaceC2632j f92549f;

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public final InterfaceC2632j f92550g;

    /* JADX INFO: renamed from: h, reason: collision with root package name */
    public final InterfaceC2632j f92551h;

    /* JADX INFO: renamed from: i, reason: collision with root package name */
    public final InterfaceC2632j f92552i;

    /* JADX INFO: renamed from: j, reason: collision with root package name */
    public final InterfaceC2632j f92553j;

    /* JADX INFO: renamed from: k, reason: collision with root package name */
    public final InterfaceC2632j f92554k;

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final InterfaceC2632j f92555l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final InterfaceC2632j f92556m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final InterfaceC2632j f92557n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final InterfaceC2632j f92558o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final InterfaceC2632j f92559p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final InterfaceC2632j f92560q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final InterfaceC2632j f92561r;

    public s(C2741q c2741q, C2765z c2765z) {
        this.f92544a = c2741q;
        this.f92545b = c2765z;
        List listR1 = z.r1(c2765z.C());
        this.f92546c = listR1;
        int size = listR1.size();
        this.f92547d = size;
        this.f92548e = Math.min(c2765z.D(), size);
        this.f92549f = Qf.k.b(new a(this));
        this.f92550g = Qf.k.b(new m(this));
        this.f92551h = Qf.k.b(new n(this));
        this.f92552i = Qf.k.b(new o(this));
        this.f92553j = Qf.k.b(new p(this));
        this.f92554k = Qf.k.b(new q(this));
        this.f92555l = Qf.k.b(new r(this));
        this.f92556m = Qf.k.b(new b(this));
        this.f92557n = Qf.k.b(new c(this));
        this.f92558o = Qf.k.b(new d(this));
        this.f92559p = Qf.k.b(new j(this));
        this.f92560q = Qf.k.b(new k(this));
        this.f92561r = Qf.k.b(new l(this));
    }

    public static final double[] C(s sVar) {
        return sVar.c(new e());
    }

    public static final double D(s sVar) {
        Sj.b bVar = (Sj.b) z.r0(sVar.f92546c, sVar.f92548e - 1);
        if (bVar != null) {
            return bVar.a();
        }
        return 0.0d;
    }

    public static final List E(s sVar) {
        return AbstractC2801o.h1(sVar.z());
    }

    public static final long[] F(s sVar) {
        List list = sVar.f92546c;
        ArrayList arrayList = new ArrayList(AbstractC2804s.y(list, 10));
        Iterator it = list.iterator();
        while (it.hasNext()) {
            arrayList.add(Long.valueOf(((Sj.b) it.next()).e()));
        }
        return z.s1(arrayList);
    }

    public static final List G(s sVar) {
        return AbstractC2801o.e1(sVar.B());
    }

    public static final double[] H(s sVar) {
        return sVar.c(new f());
    }

    public static final double a(Sj.b bVar) {
        return bVar.a();
    }

    public static final List b(s sVar) {
        return AbstractC2801o.e1(sVar.o());
    }

    public static final double d(Sj.b bVar) {
        return bVar.b();
    }

    public static final double[] e(s sVar) {
        return sVar.c(new i());
    }

    public static final double f(Sj.b bVar) {
        return bVar.c();
    }

    public static final List g(s sVar) {
        return AbstractC2801o.e1(sVar.s());
    }

    public static final double h(Sj.b bVar) {
        return bVar.d();
    }

    public static final double[] i(s sVar) {
        return sVar.c(new h());
    }

    public static final double j(Sj.b bVar) {
        return bVar.f();
    }

    public static final List k(s sVar) {
        return AbstractC2801o.e1(sVar.u());
    }

    public static final double[] l(s sVar) {
        return sVar.c(new g());
    }

    public static final List m(s sVar) {
        return AbstractC2801o.e1(sVar.w());
    }

    public final List A() {
        return (List) this.f92560q.getValue();
    }

    public final double[] B() {
        return (double[]) this.f92553j.getValue();
    }

    public final double[] c(Function1 function1) {
        List list = this.f92546c;
        ArrayList arrayList = new ArrayList(AbstractC2804s.y(list, 10));
        Iterator it = list.iterator();
        while (it.hasNext()) {
            arrayList.add(Double.valueOf(((Number) function1.invoke((Sj.b) it.next())).doubleValue()));
        }
        return z.n1(arrayList);
    }

    public final List n() {
        return (List) this.f92559p.getValue();
    }

    public final double[] o() {
        return (double[]) this.f92552i.getValue();
    }

    public final int p() {
        return this.f92547d;
    }

    public final C2765z q() {
        return this.f92545b;
    }

    public final List r() {
        return (List) this.f92557n.getValue();
    }

    public final double[] s() {
        return (double[]) this.f92550g.getValue();
    }

    public final List t() {
        return (List) this.f92558o.getValue();
    }

    public final double[] u() {
        return (double[]) this.f92551h.getValue();
    }

    public final List v() {
        return (List) this.f92556m.getValue();
    }

    public final double[] w() {
        return (double[]) this.f92549f.getValue();
    }

    public final int x() {
        return this.f92548e;
    }

    public final double y() {
        return ((Number) this.f92555l.getValue()).doubleValue();
    }

    public final long[] z() {
        return (long[]) this.f92554k.getValue();
    }
}
