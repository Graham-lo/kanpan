package Rj;

import android.graphics.Rect;

/* JADX INFO: renamed from: Rj.d, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public class C2702d extends AbstractC2721j0 {

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public b f19338g;

    /* JADX INFO: renamed from: h, reason: collision with root package name */
    public a f19339h;

    /* JADX INFO: renamed from: i, reason: collision with root package name */
    public boolean f19340i;

    /* JADX INFO: renamed from: j, reason: collision with root package name */
    public int f19341j;

    /* JADX INFO: renamed from: k, reason: collision with root package name */
    public int f19342k;

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public int f19343l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public int f19344m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public int f19345n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public int f19346o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final nk.e f19347p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public boolean f19348q;

    /* JADX INFO: renamed from: Rj.d$a */
    public enum a {
        Data,
        Range,
        Timeline;


        /* JADX INFO: renamed from: e, reason: collision with root package name */
        public static final /* synthetic */ Zf.a f19353e = Zf.b.a(a());
    }

    /* JADX INFO: renamed from: Rj.d$b */
    public enum b {
        Left,
        Top,
        Right,
        Bottom,
        Fill;


        /* JADX INFO: renamed from: g, reason: collision with root package name */
        public static final /* synthetic */ Zf.a f19360g = Zf.b.a(a());
    }

    /* JADX INFO: renamed from: Rj.d$c */
    public /* synthetic */ class c extends p167hg.x {
        public c(C2702d c2702d) {
            super(c2702d, C2702d.class, "left", "getLeft()I", 0);
        }

        @Override // p313og.l
        public Object get() {
            return Integer.valueOf(((C2702d) this.f97930b).u());
        }

        @Override // p313og.h
        public void set(Object obj) {
            ((C2702d) this.f97930b).f19341j = ((Number) obj).intValue();
        }
    }

    /* JADX INFO: renamed from: Rj.d$d, reason: collision with other inner class name */
    public /* synthetic */ class C0276d extends p167hg.x {
        public C0276d(C2702d c2702d) {
            super(c2702d, C2702d.class, "top", "getTop()I", 0);
        }

        @Override // p313og.l
        public Object get() {
            return Integer.valueOf(((C2702d) this.f97930b).z());
        }

        @Override // p313og.h
        public void set(Object obj) {
            ((C2702d) this.f97930b).f19342k = ((Number) obj).intValue();
        }
    }

    /* JADX INFO: renamed from: Rj.d$e */
    public /* synthetic */ class e extends p167hg.x {
        public e(C2702d c2702d) {
            super(c2702d, C2702d.class, "right", "getRight()I", 0);
        }

        @Override // p313og.l
        public Object get() {
            return Integer.valueOf(((C2702d) this.f97930b).y());
        }

        @Override // p313og.h
        public void set(Object obj) {
            ((C2702d) this.f97930b).f19343l = ((Number) obj).intValue();
        }
    }

    /* JADX INFO: renamed from: Rj.d$f */
    public /* synthetic */ class f extends p167hg.x {
        public f(C2702d c2702d) {
            super(c2702d, C2702d.class, "bottom", "getBottom()I", 0);
        }

        @Override // p313og.l
        public Object get() {
            return Integer.valueOf(((C2702d) this.f97930b).p());
        }

        @Override // p313og.h
        public void set(Object obj) {
            ((C2702d) this.f97930b).f19344m = ((Number) obj).intValue();
        }
    }

    public C2702d(String str) {
        super(str);
        this.f19347p = new nk.e(this);
    }

    public final int A() {
        return this.f19343l - this.f19341j;
    }

    public void B(int i10, int i11, int i12, int i13, boolean z10) {
        c cVar = new c(this);
        if (((Number) cVar.get()).intValue() != i10) {
            cVar.set(Integer.valueOf(i10));
            this.f19348q = true;
        }
        C0276d c0276d = new C0276d(this);
        if (((Number) c0276d.get()).intValue() != i11) {
            c0276d.set(Integer.valueOf(i11));
            this.f19348q = true;
        }
        e eVar = new e(this);
        if (((Number) eVar.get()).intValue() != i12) {
            eVar.set(Integer.valueOf(i12));
            this.f19348q = true;
        }
        f fVar = new f(this);
        if (((Number) fVar.get()).intValue() != i13) {
            fVar.set(Integer.valueOf(i13));
            this.f19348q = true;
        }
        if (z10) {
            this.f19348q = true;
        }
    }

    public void C(C2741q c2741q, int i10, int i11) {
        if (!this.f19347p.b()) {
            H(i10, i11);
            return;
        }
        nk.e eVar = this.f19347p;
        int[] iArr = {i10, i11};
        Qf.H h10 = Qf.H.f17640a;
        eVar.a(c2741q, iArr);
    }

    public final void D(a aVar) {
        this.f19339h = aVar;
    }

    public final void E(boolean z10) {
        this.f19348q = z10;
    }

    public final void F(boolean z10) {
        this.f19340i = z10;
    }

    public final void G(b bVar) {
        this.f19338g = bVar;
    }

    public final void H(int i10, int i11) {
        this.f19345n = i10;
        this.f19346o = i11;
    }

    public final boolean k(float f10, float f11) {
        return l(f10) && m(f11);
    }

    public final boolean l(float f10) {
        return f10 >= ((float) this.f19341j) && f10 < ((float) this.f19343l);
    }

    public final boolean m(float f10) {
        return f10 >= ((float) this.f19342k) && f10 < ((float) this.f19344m);
    }

    public final Rect n() {
        return new Rect(this.f19341j, this.f19342k, this.f19343l, this.f19344m);
    }

    public final a o() {
        return this.f19339h;
    }

    public final int p() {
        return this.f19344m;
    }

    public final int q() {
        return (this.f19341j + this.f19343l) >> 1;
    }

    public final boolean r() {
        return this.f19340i;
    }

    public final b s() {
        return this.f19338g;
    }

    public final int t() {
        return this.f19344m - this.f19342k;
    }

    public String toString() {
        return "left: " + this.f19341j + " top: " + this.f19342k + " right: " + this.f19343l + " bottom: " + this.f19344m;
    }

    public final int u() {
        return this.f19341j;
    }

    public final int v() {
        return this.f19346o;
    }

    public final int w() {
        return this.f19345n;
    }

    public final int x() {
        return (this.f19342k + this.f19344m) >> 1;
    }

    public final int y() {
        return this.f19343l;
    }

    public final int z() {
        return this.f19342k;
    }
}
