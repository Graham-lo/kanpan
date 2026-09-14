package Rj;

import java.util.ArrayList;
import java.util.Iterator;
import kotlin.jvm.internal.DefaultConstructorMarker;
import org.apache.tika.pipes.pipesiterator.PipesIterator;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: /private/tmp/claude-501/-Users-mdd-kanpan/e5a5bf1c-f427-4144-8ae2-a961a321a4b4/scratchpad/aic/dec/classes7.dex */
public class y1 extends AbstractC0161j0 {
    public static final a H = null;
    public boolean A;
    public int B;
    public final C0181q C;
    public long D;
    public int E;
    public float F;
    public float G;
    public final C0172n g;
    public float h;
    public float i;
    public float j;
    public float k;
    public c l;
    public final float m;
    public int n;
    public float o;
    public float p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public float f29q;
    public final KLineManager r;
    public int s;
    public int t;
    public int u;
    public int v;
    public boolean w;
    public float x;
    public float y;
    public float z;

    public static final class a {
        public a(DefaultConstructorMarker r1) {
        }
    }

    public /* synthetic */ class b {
        public static final /* synthetic */ int[] a = null;

        static {
            int[] r0 = new int[c.values().length];
            r0[c.c.ordinal()] = 1;     // Catch: NoSuchFieldError -> L7
        L9:
            r0[c.b.ordinal()] = 2;     // Catch: NoSuchFieldError -> L8
        L5:
            a = r0;
        }
    }

    public static final enum c extends Enum {
        public static final c a = null;
        public static final c b = null;
        public static final c c = null;
        public static final /* synthetic */ c[] d = null;
        public static final /* synthetic */ Zf.a e = null;

        static {
            a = new c("LEFT", 0);
            b = new c("CENTER", 1);
            c = new c("RIGHT", 2);
            c[] r0 = a();
            d = r0;
            e = Zf.b.a(r0);
        }

        public c(String r1, int r2) {
            super(r1, r2);
        }

        public static final /* synthetic */ c[] a() {
            return new c[]{a, b, c};
        }

        public static c valueOf(String r1) {
            return (c) Enum.valueOf(c.class, r1);
        }

        public static c[] values() {
            return (c[]) d.clone();
        }
    }

    static {
        H = new a(null);
    }

    public y1(C0172n r1, String r2) {
        super(r2);
        this.g = r1;
        this.h = 1.0f;
        this.l = c.b;
        this.m = Xj.a.a(30.0f);
        this.f29q = 12.0f;
        this.r = KLineManager.O.a();
        this.B = -1;
        this.C = r1.b();
    }

    public static /* synthetic */ float C(y1 r0, int r1, int r2, Object r3) {
        if (r3 != null) goto L9;
        if ((r2 & 1) == 0) goto L7;
        r1 = r0.s;
    L7:
        return r0.B(r1);
    L9:
        throw new UnsupportedOperationException("Super calls with default arguments not supported in this target, function: getSelectColumnCenter");
    }

    public static /* synthetic */ void R(y1 r0, float r1, float r2, int r3, Object r4) {
        if (r4 != null) goto L9;
        if ((r3 & 2) == 0) goto L6;
        r2 = r0.i;
    L6:
        r0.Q(r1, r2);
        return;
    L9:
        throw new UnsupportedOperationException("Super calls with default arguments not supported in this target, function: scale");
    }

    public final int A() {
        return this.B;
    }

    public final float B(int r1) {
        return l(r1);
    }

    public final int D() {
        return this.s;
    }

    public final boolean E() {
        return this.A;
    }

    public final long F() {
        return H(r());
    }

    public final float G() {
        return this.z;
    }

    public final long H(int r6) {
        C0205z r0 = this.C.h(c());
        long r1 = 0;
        if (r0 != null) goto L5;
        return 0;
    L5:
        Sj.a r2 = r0.C();
        if (r2 == null) goto L10;
        if (r2.isEmpty() == true) goto L10;
    L12:
        Sj.b r7 = (Sj.b) Sf.z.r0(r2, r6);
        if (r7 == null) goto L16;
        r1 = r7.e();
    L16:
        return r1 / ((long) PipesIterator.DEFAULT_QUEUE_SIZE);
    L10:
        if (nk.z.a(r2, r6) == true) goto L12;
        return 0;
    }

    public final int I() {
        return this.v;
    }

    public final float J() {
        return -this.o;
    }

    public void K(float r3) {
        if (r3 < 0.0f) goto L9;
        float r0 = this.u;
        if (r3 > r0) goto L10;
        this.s = (int) ((Math.min(r3, r0) + this.i) / this.f29q);
        return;
    L10:
        return;
    }

    public final void L() {
        C0142d r0 = this.C.e(c() + ".main");
        if (r0 != null) goto L6;
        return;
    L6:
        if (this.u == r0.A()) goto L22;
        this.n = r0.A() - this.u;
        this.u = Math.max(0, r0.A());
        R(this, this.h, 0.0f, 2, null);
        if (this.i != ((this.j + this.n) - (400 * this.f29q))) goto L20;
        O(-this.k);
        int r1 = this.r.q(18);
        if (r1 != 0) goto L12;
        float r2 = this.m;
    L18:
        O(r2);
        return;
    L12:
        if (r1 == 1) goto L16;
        if (r1 == 2) goto L15;
        r2 = this.m;
        goto L18
    L15:
        r2 = this.u / 2;
        goto L18
    L16:
        r2 = (this.u / 3) * 2;
        goto L18
    L20:
        P();
        return;
    }

    public final boolean M() {
        float r0 = this.j - this.i;
        float r2 = this.f29q;
        float r1 = r0 - (400 * r2);
        if (r1 < r2) goto L5;
        return false;
    L5:
        if (r1 <= (-r2)) goto L10;
        return true;
    L10:
        return false;
    }

    public final boolean N() {
        int r0 = r();
        int r1 = y();
        int r2 = this.s;
        if (r0 > r2) goto L7;
        if (r2 > r1) goto L7;
        return true;
    L7:
        return false;
    }

    public final boolean O(float r5) {
        float r0 = g();
        float r1 = this.i - r5;
        float r6 = 0.0f;
        boolean r3 = true;
        if (r1 >= 0.0f) goto L6;
        this.l = c.a;
    L5:
        r1 = r6;
    L10:
        this.i = r1;
        float r2 = this.f29q;
        this.o = (-r1) % r2;
        this.p = (-(r1 + this.u)) % r2;
        return r3;
    L6:
        r6 = this.j - r0;
        if (r1 < r6) goto L9;
        this.l = c.c;
        goto L5
    L9:
        this.l = c.b;
        r3 = false;
        goto L10
    }

    public final void P() {
        O(0.0f);
    }

    public final void Q(float r5, float r6) {
        nk.p.a.a("KlineLog", "scale = " + r5);
        this.h = r5;
        float r7 = r5 * 12.0f;
        this.f29q = r7;
        float r0 = this.k;
        float r8 = r7 * this.t;
        this.k = r8;
        float r2 = 0.0f;
        this.j = Math.max(0.0f, r8 - this.u);
        this.v = (int) (this.u / this.f29q);
        int r1 = b.a[this.l.ordinal()];
        if (r1 != 1) goto L5;
        r2 = this.j - g();
    L9:
        this.i = r2;
        float r9 = this.f29q;
        this.o = (-r2) % r9;
        this.p = (-(r2 + this.u)) % r9;
        return;
    L5:
        if (r1 != 2) goto L9;
        r2 = Math.min((nk.A.d(this.i + r6, r0, 0.0f) * r8) - r6, this.j - g());
        goto L9
    }

    /* JADX WARN: Multi-variable type inference failed */
    public final void S(long r10) {
        C0205z r0 = this.C.h(c());
        if (r0 == null) goto L48;
        Sj.a r1 = r0.C();
        if (r1.isEmpty() == false) goto L9;
        return;
    L9:
        if (r10 >= 1000000000000L) goto L11;
        r10 = r10 * 1000;
    L11:
        ng.g r2 = Sf.r.o(r1);
        ArrayList r3 = new ArrayList();
        Iterator r4 = r2.iterator();
    L13:
        if (r4.hasNext() == false) goto L17;
        Object r5 = r4.next();
        if (((Sj.b) r1.get(((Number) r5).intValue())).g() == true) goto L13;
        r3.add(r5);
        goto L13
    L17:
        Iterator r6 = r3.iterator();
        if (r6.hasNext() == true) goto L20;
        Object r11 = null;
    L30:
        Integer r12 = (Integer) r11;
        if (r12 == null) goto L47;
        int r13 = r12.intValue();
        this.B = r13;
        Sj.b r14 = (Sj.b) Sf.z.r0(r1, r13);
        if (r14 == null) goto L50;
        double r7 = r14.a();
        this.r.W0(r14.e());
        KLineManager r15 = this.r;
        if (Double.isNaN(r7) == false) goto L38;
        r7 = 0.0d;
    L38:
        r15.V0(r7);
        O(this.i - (((r13 + 0.5f) * this.f29q) - (this.u / 2.0f)));
        return;
    L50:
        return;
    L47:
        return;
    L20:
        Object r8 = r6.next();
        if (r6.hasNext() == true) goto L23;
    L22:
        r11 = r8;
        goto L30
    L23:
        long r9 = Math.abs(((Sj.b) r1.get(((Number) r8).intValue())).e() - r10);
    L24:
        Object r16 = r6.next();
        long r17 = Math.abs(((Sj.b) r1.get(((Number) r16).intValue())).e() - r10);
        if (r9 <= r17) goto L28;
        r8 = r16;
        r9 = r17;
    L28:
        if (r6.hasNext() == true) goto L24;
    }

    public final boolean T() {
        if (this.t > 0) goto L5;
        return false;
    L5:
        if (this.u <= 0) goto L20;
        h();
        O(-this.k);
        int r0 = this.r.q(18);
        if (r0 != 0) goto L10;
        float r1 = this.m;
    L16:
        O(r1);
        return true;
    L10:
        if (r0 == 1) goto L14;
        if (r0 == 2) goto L13;
        r1 = this.m;
        goto L16
    L13:
        r1 = this.u / 2;
        goto L16
    L14:
        r1 = (this.u / 3) * 2;
        goto L16
    L20:
        return false;
    }

    public void U(float r2) {
        if (r2 >= 0.0f) goto L5;
        return;
    L5:
        if (this.A == true) goto L8;
        return;
    L8:
        if (r2 <= this.u) goto L11;
        this.A = false;
        return;
    L11:
        this.s = (int) ((this.i + r2) / this.f29q);
    }

    public final void V(boolean r1) {
        this.w = r1;
    }

    public final void W(float r1) {
        this.x = r1;
    }

    public final void X(float r1) {
        this.y = r1;
    }

    public final void Y(boolean r1) {
        this.A = r1;
    }

    public final void Z(float r1) {
        this.z = r1;
    }

    public final void a0() {
        KLineManager.O.a().w0(!this.A);
        this.A = !this.A;
    }

    public final void b0() {
        C0205z r0 = this.C.h(c());
        if (r0 == null) goto L45;
        float r1 = this.k;
        int r2 = this.t;
        int r3 = r0.D();
        int r4 = this.s;
        float r5 = 400;
        float r7 = this.j - Math.min(this.f29q * r5, this.j);
        float r6 = this.i;
        int r8 = r0.B();
        this.t = r8;
        if (r8 == r2) goto L8;
        float r10 = r8 * this.f29q;
        this.k = r10;
        this.j = Math.max(0.0f, r10 - this.u);
    L8:
        int r9 = r0.X();
        if (r9 == 1) goto L36;
        if (r9 != 3) goto L13;
        float r11 = r7 - r6;
        if (r11 != 0.0f) goto L26;
    L29:
        this.i = this.j;
        O(r5 * this.f29q);
    L32:
        if (r4 != (r3 - 2)) goto L43;
        this.s = r3 - 1;
        return;
    L43:
        return;
    L26:
        if (r11 > 0.0f) goto L28;
    L30:
        P();
        goto L32
    L28:
        if (r11 >= this.f29q) goto L30;
    L13:
        if (r9 != 4) goto L46;
        int r12 = r8 - r2;
        if (r12 <= 1) goto L18;
        this.i = this.k - r1;
        O(this.u / 10);
    L18:
        int r13 = this.B;
        if (r13 < 0) goto L40;
        this.B = r13 + r12;
        return;
    L40:
        return;
    L46:
        return;
    L36:
        if (this.t == r2) goto L38;
    L41:
        this.i = this.j;
        this.s = r3 - 1;
        O(r5 * this.f29q);
        this.w = false;
        return;
    L38:
        if (this.w == true) goto L41;
        return;
    }

    public final float g() {
        int r0 = this.r.q(18);
        if (r0 != 0) goto L5;
        float r1 = this.m;
    L12:
        return Math.min((400 * this.f29q) - r1, this.j);
    L5:
        if (r0 == 1) goto L9;
        if (r0 == 2) goto L8;
        r1 = this.m;
        goto L12
    L8:
        r1 = this.u / 2;
        goto L12
    L9:
        r1 = (this.u / 3) * 2;
        goto L12
    }

    public final void h() {
        this.B = -1;
    }

    /* JADX WARN: Multi-variable type inference failed */
    public final float j(long r13) {
        C0205z r0 = this.C.h(c());
        if (r0 != null) goto L5;
        return 0.0f;
    L5:
        Sj.a r2 = r0.C();
        if (r2.isEmpty() == false) goto L8;
        return 0.0f;
    L8:
        int r1 = r0.D();
        if (r1 > 0) goto L11;
        return 0.0f;
    L11:
        long r3 = ((Sj.b) Sf.z.o0(r2)).e();
        long r5 = PipesIterator.DEFAULT_QUEUE_SIZE;
        long r4 = r3 / r5;
        int r7 = r1 - 1;
        long r8 = ((Sj.b) r2.get(r7)).e() / r5;
        if (r4 == this.D) goto L14;
    L17:
        this.F = this.k;
        this.D = r4;
        this.E = r1;
        long r9 = r8 - r4;
        if (r9 <= 0) goto L20;
        float r6 = (r7 * this.f29q) / r9;
    L21:
        this.G = r6;
    L22:
        float r10 = this.G;
        if (r10 <= 0.0f) goto L29;
        float r11 = r10 * ((r13 / r5) - r4);
        float r14 = this.f29q;
        float r12 = r11 / r14;
        float r15 = r12 % 1;
        int r16 = (int) r12;
        if (r15 <= 0.999f) goto L28;
        r16 = r16 + 1;
    L28:
        return (r14 / 2) + (r16 * r14);
    L29:
        return -1.0f;
    L20:
        r6 = 0.0f;
        goto L21
    L14:
        if (this.k != this.F) goto L17;
        if (r1 == this.E) goto L22;
        goto L17
    }

    public final C0172n k() {
        return this.g;
    }

    public final float l(int r3) {
        float r0 = this.f29q;
        return (((r3 + 1) * r0) - (r0 / 2)) - this.i;
    }

    public final long m() {
        C0205z r0 = this.C.h(c());
        if (r0 != null) goto L5;
        return 0;
    L5:
        Sj.b r1 = (Sj.b) Sf.z.r0(r0.C(), r0.D() - 1);
        if (r1 != null) goto L8;
        return 0;
    L8:
        return r1.e();
    }

    public final long n() {
        return H(y());
    }

    public final float o() {
        return this.y;
    }

    public final int p(long r9) {
        C0205z r0 = this.C.h(c());
        if (r0 != null) goto L5;
        return 0;
    L5:
        Sj.a r1 = r0.C();
        if (r1 != null) goto L8;
    L22:
        return 0;
    L8:
        if (r1.isEmpty() == true) goto L22;
        Iterator<E> r2 = r1.iterator();
    L12:
        if (r2.hasNext() == false) goto L16;
        Object r3 = r2.next();
        if ((((Sj.b) r3).e() / ((long) PipesIterator.DEFAULT_QUEUE_SIZE)) != r9) goto L12;
    L17:
        Sj.b r4 = (Sj.b) r3;
        if (Sf.z.g0(r1, r4) == true) goto L21;
        return 0;
    L21:
        return Sf.z.u0(r1, r4);
    L16:
        r3 = null;
        goto L17
    }

    public final int q() {
        return Math.min(this.t - 1, ((int) ((this.i + this.u) / this.f29q)) + 2);
    }

    public final int r() {
        return Math.max(0, (int) (this.i / this.f29q));
    }

    public final double s() {
        C0205z r0 = this.C.h(c());
        if (r0 != null) goto L5;
        return 0.0d;
    L5:
        Sj.b r1 = (Sj.b) Sf.z.r0(r0.C(), r());
        if (r1 != null) goto L8;
        return 0.0d;
    L8:
        return r1.a();
    }

    public final int t() {
        return this.t;
    }

    public final float u() {
        return this.f29q;
    }

    public final int v() {
        float r0 = this.u;
        float r1 = this.f29q;
        int r2 = jg.c.d(((r0 - r1) + this.i) / r1);
        C0205z r3 = this.g.d();
        if (r3 == null) goto L32;
        Sj.a r4 = r3.C();
        if (r4 == null) goto L33;
        int r5 = r2;
    L9:
        if ((-1) >= r5) goto L23;
        Sj.b r6 = (Sj.b) Sf.z.r0(r4, r5);
        if (r6 == null) goto L34;
        if (Double.isNaN(r6.d()) == true) goto L22;
        if (Double.isNaN(r6.b()) == true) goto L22;
        if (Double.isNaN(r6.c()) == true) goto L22;
        if (Double.isNaN(r6.a()) == true) goto L22;
        return r5;
    L22:
        r5 = r5 - 1;
        goto L9
    L34:
        return r2;
    L23:
        return 0;
    L33:
        return r2;
    L32:
        return r2;
    }

    public final float w() {
        return this.i;
    }

    public final float x() {
        return this.k;
    }

    public final int y() {
        return Math.min(this.t - 1, ((int) ((this.i + this.u) / this.f29q)) + 1);
    }

    public final float z() {
        return this.h;
    }

    public final void i() {
    }
}
