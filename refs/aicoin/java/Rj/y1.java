package Rj;

import java.util.ArrayList;
import java.util.Iterator;
import kotlin.jvm.internal.DefaultConstructorMarker;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public class y1 extends AbstractC2721j0 {

    /* JADX INFO: renamed from: H, reason: collision with root package name */
    public static final a f19613H = new a(null);

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public boolean f19614A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public int f19615B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public final C2741q f19616C;

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public long f19617D;

    /* JADX INFO: renamed from: E, reason: collision with root package name */
    public int f19618E;

    /* JADX INFO: renamed from: F, reason: collision with root package name */
    public float f19619F;

    /* JADX INFO: renamed from: G, reason: collision with root package name */
    public float f19620G;

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public final C2732n f19621g;

    /* JADX INFO: renamed from: h, reason: collision with root package name */
    public float f19622h;

    /* JADX INFO: renamed from: i, reason: collision with root package name */
    public float f19623i;

    /* JADX INFO: renamed from: j, reason: collision with root package name */
    public float f19624j;

    /* JADX INFO: renamed from: k, reason: collision with root package name */
    public float f19625k;

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public c f19626l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final float f19627m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public int f19628n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public float f19629o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public float f19630p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public float f19631q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final KLineManager f19632r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public int f19633s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public int f19634t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public int f19635u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public int f19636v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public boolean f19637w;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public float f19638x;

    /* JADX INFO: renamed from: y, reason: collision with root package name */
    public float f19639y;

    /* JADX INFO: renamed from: z, reason: collision with root package name */
    public float f19640z;

    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public /* synthetic */ class b {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public static final /* synthetic */ int[] f19641a;

        static {
            int[] iArr = new int[c.values().length];
            try {
                iArr[c.RIGHT.ordinal()] = 1;
            } catch (NoSuchFieldError unused) {
            }
            try {
                iArr[c.CENTER.ordinal()] = 2;
            } catch (NoSuchFieldError unused2) {
            }
            f19641a = iArr;
        }
    }

    public enum c {
        LEFT,
        CENTER,
        RIGHT;


        /* JADX INFO: renamed from: e, reason: collision with root package name */
        public static final /* synthetic */ Zf.a f19646e = Zf.b.a(a());
    }

    public y1(C2732n c2732n, String str) {
        super(str);
        this.f19621g = c2732n;
        this.f19622h = 1.0f;
        this.f19626l = c.CENTER;
        this.f19627m = Xj.a.a(30.0f);
        this.f19631q = 12.0f;
        this.f19632r = KLineManager.f142490O.a();
        this.f19615B = -1;
        this.f19616C = c2732n.b();
    }

    public static /* synthetic */ float C(y1 y1Var, int i10, int i11, Object obj) {
        if (obj != null) {
            throw new UnsupportedOperationException("Super calls with default arguments not supported in this target, function: getSelectColumnCenter");
        }
        if ((i11 & 1) != 0) {
            i10 = y1Var.f19633s;
        }
        return y1Var.B(i10);
    }

    public static /* synthetic */ void R(y1 y1Var, float f10, float f11, int i10, Object obj) {
        if (obj != null) {
            throw new UnsupportedOperationException("Super calls with default arguments not supported in this target, function: scale");
        }
        if ((i10 & 2) != 0) {
            f11 = y1Var.f19623i;
        }
        y1Var.Q(f10, f11);
    }

    public final int A() {
        return this.f19615B;
    }

    public final float B(int i10) {
        return l(i10);
    }

    public final int D() {
        return this.f19633s;
    }

    public final boolean E() {
        return this.f19614A;
    }

    public final long F() {
        return H(r());
    }

    public final float G() {
        return this.f19640z;
    }

    public final long H(int i10) {
        C2765z c2765zH = this.f19616C.h(c());
        if (c2765zH == null) {
            return 0L;
        }
        Sj.a aVarC = c2765zH.C();
        if ((aVarC == null || aVarC.isEmpty()) && !nk.z.a(aVarC, i10)) {
            return 0L;
        }
        Sj.b bVar = (Sj.b) Sf.z.r0(aVarC, i10);
        return (bVar != null ? bVar.e() : 0L) / ((long) 1000);
    }

    public final int I() {
        return this.f19636v;
    }

    public final float J() {
        return -this.f19629o;
    }

    public void K(float f10) {
        if (f10 >= 0.0f) {
            float f11 = this.f19635u;
            if (f10 > f11) {
                return;
            }
            this.f19633s = (int) ((Math.min(f10, f11) + this.f19623i) / this.f19631q);
        }
    }

    public final void L() {
        float f10;
        C2702d c2702dE = this.f19616C.e(c() + ".main");
        if (c2702dE == null || this.f19635u == c2702dE.A()) {
            return;
        }
        this.f19628n = c2702dE.A() - this.f19635u;
        this.f19635u = Math.max(0, c2702dE.A());
        R(this, this.f19622h, 0.0f, 2, null);
        if (this.f19623i != (this.f19624j + this.f19628n) - (400 * this.f19631q)) {
            P();
            return;
        }
        O(-this.f19625k);
        int iQ = this.f19632r.q(18);
        if (iQ == 0) {
            f10 = this.f19627m;
        } else if (iQ != 1) {
            f10 = iQ != 2 ? this.f19627m : this.f19635u / 2;
        } else {
            f10 = (this.f19635u / 3) * 2;
        }
        O(f10);
    }

    public final boolean M() {
        float f10 = this.f19624j - this.f19623i;
        float f11 = this.f19631q;
        float f12 = f10 - (400 * f11);
        return f12 < f11 && f12 > (-f11);
    }

    public final boolean N() {
        int iR = r();
        int iY = y();
        int i10 = this.f19633s;
        return iR <= i10 && i10 <= iY;
    }

    public final boolean O(float f10) {
        float fG = g();
        float f11 = this.f19623i - f10;
        float f12 = 0.0f;
        boolean z10 = true;
        if (f11 >= 0.0f) {
            f12 = this.f19624j - fG;
            if (f11 >= f12) {
                this.f19626l = c.RIGHT;
            } else {
                this.f19626l = c.CENTER;
                z10 = false;
            }
            this.f19623i = f11;
            float f13 = this.f19631q;
            this.f19629o = (-f11) % f13;
            this.f19630p = (-(f11 + this.f19635u)) % f13;
            return z10;
        }
        this.f19626l = c.LEFT;
        f11 = f12;
        this.f19623i = f11;
        float f14 = this.f19631q;
        this.f19629o = (-f11) % f14;
        this.f19630p = (-(f11 + this.f19635u)) % f14;
        return z10;
    }

    public final void P() {
        O(0.0f);
    }

    public final void Q(float f10, float f11) {
        nk.p.f134232a.a("KlineLog", "scale = " + f10);
        this.f19622h = f10;
        float f12 = f10 * 12.0f;
        this.f19631q = f12;
        float f13 = this.f19625k;
        float f14 = f12 * this.f19634t;
        this.f19625k = f14;
        float fG = 0.0f;
        this.f19624j = Math.max(0.0f, f14 - this.f19635u);
        this.f19636v = (int) (this.f19635u / this.f19631q);
        int i10 = b.f19641a[this.f19626l.ordinal()];
        if (i10 == 1) {
            fG = this.f19624j - g();
        } else if (i10 == 2) {
            fG = Math.min((nk.A.d(this.f19623i + f11, f13, 0.0f) * f14) - f11, this.f19624j - g());
        }
        this.f19623i = fG;
        float f15 = this.f19631q;
        this.f19629o = (-fG) % f15;
        this.f19630p = (-(fG + this.f19635u)) % f15;
    }

    /* JADX WARN: Multi-variable type inference failed */
    public final void S(long j10) {
        Object obj;
        C2765z c2765zH = this.f19616C.h(c());
        if (c2765zH == null) {
            return;
        }
        Sj.a aVarC = c2765zH.C();
        if (aVarC.isEmpty()) {
            return;
        }
        if (j10 < 1000000000000L) {
            j10 *= 1000;
        }
        p292ng.g gVarO = Sf.r.o(aVarC);
        ArrayList arrayList = new ArrayList();
        for (Object obj2 : gVarO) {
            if (!((Sj.b) aVarC.get(((Number) obj2).intValue())).g()) {
                arrayList.add(obj2);
            }
        }
        Iterator it = arrayList.iterator();
        if (it.hasNext()) {
            Object next = it.next();
            if (it.hasNext()) {
                long jAbs = Math.abs(((Sj.b) aVarC.get(((Number) next).intValue())).e() - j10);
                do {
                    Object next2 = it.next();
                    long jAbs2 = Math.abs(((Sj.b) aVarC.get(((Number) next2).intValue())).e() - j10);
                    if (jAbs > jAbs2) {
                        next = next2;
                        jAbs = jAbs2;
                    }
                } while (it.hasNext());
            }
            obj = next;
        } else {
            obj = null;
        }
        Integer num = (Integer) obj;
        if (num != null) {
            int iIntValue = num.intValue();
            this.f19615B = iIntValue;
            Sj.b bVar = (Sj.b) Sf.z.r0(aVarC, iIntValue);
            if (bVar == null) {
                return;
            }
            double dA = bVar.a();
            this.f19632r.W0(bVar.e());
            KLineManager kLineManager = this.f19632r;
            if (Double.isNaN(dA)) {
                dA = 0.0d;
            }
            kLineManager.V0(dA);
            O(this.f19623i - (((iIntValue + 0.5f) * this.f19631q) - (this.f19635u / 2.0f)));
        }
    }

    public final boolean T() {
        float f10;
        if (this.f19634t <= 0 || this.f19635u <= 0) {
            return false;
        }
        h();
        O(-this.f19625k);
        int iQ = this.f19632r.q(18);
        if (iQ == 0) {
            f10 = this.f19627m;
        } else if (iQ != 1) {
            f10 = iQ != 2 ? this.f19627m : this.f19635u / 2;
        } else {
            f10 = (this.f19635u / 3) * 2;
        }
        O(f10);
        return true;
    }

    public void U(float f10) {
        if (f10 < 0.0f || !this.f19614A) {
            return;
        }
        if (f10 > this.f19635u) {
            this.f19614A = false;
        } else {
            this.f19633s = (int) ((this.f19623i + f10) / this.f19631q);
        }
    }

    public final void V(boolean z10) {
        this.f19637w = z10;
    }

    public final void W(float f10) {
        this.f19638x = f10;
    }

    public final void X(float f10) {
        this.f19639y = f10;
    }

    public final void Y(boolean z10) {
        this.f19614A = z10;
    }

    public final void Z(float f10) {
        this.f19640z = f10;
    }

    public final void a0() {
        KLineManager.f142490O.a().w0(!this.f19614A);
        this.f19614A = !this.f19614A;
    }

    public final void b0() {
        C2765z c2765zH = this.f19616C.h(c());
        if (c2765zH == null) {
            return;
        }
        float f10 = this.f19625k;
        int i10 = this.f19634t;
        int iD = c2765zH.D();
        int i11 = this.f19633s;
        float f11 = 400;
        float fMin = this.f19624j - Math.min(this.f19631q * f11, this.f19624j);
        float f12 = this.f19623i;
        int iB = c2765zH.B();
        this.f19634t = iB;
        if (iB != i10) {
            float f13 = iB * this.f19631q;
            this.f19625k = f13;
            this.f19624j = Math.max(0.0f, f13 - this.f19635u);
        }
        int iX = c2765zH.X();
        if (iX == 1) {
            if (this.f19634t != i10 || this.f19637w) {
                this.f19623i = this.f19624j;
                this.f19633s = iD - 1;
                O(f11 * this.f19631q);
                this.f19637w = false;
                return;
            }
            return;
        }
        if (iX != 3) {
            if (iX != 4) {
                return;
            }
            int i12 = iB - i10;
            if (i12 > 1) {
                this.f19623i = this.f19625k - f10;
                O(this.f19635u / 10);
            }
            int i13 = this.f19615B;
            if (i13 >= 0) {
                this.f19615B = i13 + i12;
                return;
            }
            return;
        }
        float f14 = fMin - f12;
        if (f14 != 0.0f && (f14 <= 0.0f || f14 >= this.f19631q)) {
            P();
        } else {
            this.f19623i = this.f19624j;
            O(f11 * this.f19631q);
        }
        if (i11 == iD - 2) {
            this.f19633s = iD - 1;
        }
    }

    public final float g() {
        float f10;
        int iQ = this.f19632r.q(18);
        if (iQ == 0) {
            f10 = this.f19627m;
        } else if (iQ != 1) {
            f10 = iQ != 2 ? this.f19627m : this.f19635u / 2;
        } else {
            f10 = (this.f19635u / 3) * 2;
        }
        return Math.min((400 * this.f19631q) - f10, this.f19624j);
    }

    public final void h() {
        this.f19615B = -1;
    }

    public final void i() {
    }

    /* JADX WARN: Multi-variable type inference failed */
    public final float j(long j10) {
        int iD;
        C2765z c2765zH = this.f19616C.h(c());
        if (c2765zH == null) {
            return 0.0f;
        }
        Sj.a aVarC = c2765zH.C();
        if (aVarC.isEmpty() || (iD = c2765zH.D()) <= 0) {
            return 0.0f;
        }
        long j11 = 1000;
        long jE = ((Sj.b) Sf.z.o0(aVarC)).e() / j11;
        int i10 = iD - 1;
        long jE2 = ((Sj.b) aVarC.get(i10)).e() / j11;
        if (jE != this.f19617D || this.f19625k != this.f19619F || iD != this.f19618E) {
            this.f19619F = this.f19625k;
            this.f19617D = jE;
            this.f19618E = iD;
            long j12 = jE2 - jE;
            this.f19620G = j12 > 0 ? (i10 * this.f19631q) / j12 : 0.0f;
        }
        float f10 = this.f19620G;
        if (f10 <= 0.0f) {
            return -1.0f;
        }
        float f11 = f10 * ((j10 / j11) - jE);
        float f12 = this.f19631q;
        float f13 = f11 / f12;
        float f14 = f13 % 1;
        int i11 = (int) f13;
        if (f14 > 0.999f) {
            i11++;
        }
        return (f12 / 2) + (i11 * f12);
    }

    public final C2732n k() {
        return this.f19621g;
    }

    public final float l(int i10) {
        float f10 = this.f19631q;
        return (((i10 + 1) * f10) - (f10 / 2)) - this.f19623i;
    }

    public final long m() {
        C2765z c2765zH = this.f19616C.h(c());
        if (c2765zH == null) {
            return 0L;
        }
        Sj.b bVar = (Sj.b) Sf.z.r0(c2765zH.C(), c2765zH.D() - 1);
        if (bVar != null) {
            return bVar.e();
        }
        return 0L;
    }

    public final long n() {
        return H(y());
    }

    public final float o() {
        return this.f19639y;
    }

    public final int p(long j10) {
        Sj.a aVarC;
        Object next;
        C2765z c2765zH = this.f19616C.h(c());
        if (c2765zH == null || (aVarC = c2765zH.C()) == null || aVarC.isEmpty()) {
            return 0;
        }
        Iterator<E> it = aVarC.iterator();
        do {
            if (!it.hasNext()) {
                next = null;
                break;
            }
            next = it.next();
        } while (((Sj.b) next).e() / ((long) 1000) != j10);
        Sj.b bVar = (Sj.b) next;
        if (Sf.z.g0(aVarC, bVar)) {
            return Sf.z.u0(aVarC, bVar);
        }
        return 0;
    }

    public final int q() {
        return Math.min(this.f19634t - 1, ((int) ((this.f19623i + this.f19635u) / this.f19631q)) + 2);
    }

    public final int r() {
        return Math.max(0, (int) (this.f19623i / this.f19631q));
    }

    public final double s() {
        Sj.b bVar;
        C2765z c2765zH = this.f19616C.h(c());
        if (c2765zH == null || (bVar = (Sj.b) Sf.z.r0(c2765zH.C(), r())) == null) {
            return 0.0d;
        }
        return bVar.a();
    }

    public final int t() {
        return this.f19634t;
    }

    public final float u() {
        return this.f19631q;
    }

    public final int v() {
        Sj.a aVarC;
        float f10 = this.f19635u;
        float f11 = this.f19631q;
        int iD = p208jg.c.d(((f10 - f11) + this.f19623i) / f11);
        C2765z c2765zD = this.f19621g.d();
        if (c2765zD == null || (aVarC = c2765zD.C()) == null) {
            return iD;
        }
        for (int i10 = iD; -1 < i10; i10--) {
            Sj.b bVar = (Sj.b) Sf.z.r0(aVarC, i10);
            if (bVar == null) {
                return iD;
            }
            if (!Double.isNaN(bVar.d()) && !Double.isNaN(bVar.b()) && !Double.isNaN(bVar.c()) && !Double.isNaN(bVar.a())) {
                return i10;
            }
        }
        return 0;
    }

    public final float w() {
        return this.f19623i;
    }

    public final float x() {
        return this.f19625k;
    }

    public final int y() {
        return Math.min(this.f19634t - 1, ((int) ((this.f19623i + this.f19635u) / this.f19631q)) + 1);
    }

    public final float z() {
        return this.f19622h;
    }
}
