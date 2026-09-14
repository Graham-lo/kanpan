package fk;

import Rj.AbstractC2744r0;
import Rj.AbstractC2755v;
import Rj.AbstractC2759w0;
import Rj.C2732n;
import Rj.C2738p;
import Rj.C2741q;
import Rj.C2765z;
import Rj.y1;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import java.util.List;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.chart.data.AIWinRateItem;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: fk.m, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7388m extends AbstractC2744r0 {

    /* JADX INFO: renamed from: J, reason: collision with root package name */
    public static final a f95399J = new a(null);

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public float f95400A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public final Path f95401B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public final Path f95402C;

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public y1 f95403D;

    /* JADX INFO: renamed from: E, reason: collision with root package name */
    public AbstractC2759w0 f95404E;

    /* JADX INFO: renamed from: F, reason: collision with root package name */
    public gk.r f95405F;

    /* JADX INFO: renamed from: G, reason: collision with root package name */
    public final nk.r f95406G;

    /* JADX INFO: renamed from: H, reason: collision with root package name */
    public float f95407H;

    /* JADX INFO: renamed from: I, reason: collision with root package name */
    public KLineManager f95408I;

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final b f95409l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Paint f95410m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final Paint f95411n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final Paint f95412o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final Paint f95413p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final Paint f95414q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final Paint f95415r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public final Paint f95416s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public final Paint f95417t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public final Paint f95418u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public final Paint f95419v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public final Paint f95420w;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public final Paint f95421x;

    /* JADX INFO: renamed from: y, reason: collision with root package name */
    public final float f95422y;

    /* JADX INFO: renamed from: z, reason: collision with root package name */
    public final float f95423z;

    /* JADX INFO: renamed from: fk.m$a */
    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    /* JADX INFO: renamed from: fk.m$b */
    public final class b {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public final int f95424a;

        /* JADX INFO: renamed from: b, reason: collision with root package name */
        public final int f95425b;

        /* JADX INFO: renamed from: c, reason: collision with root package name */
        public final int f95426c;

        /* JADX INFO: renamed from: d, reason: collision with root package name */
        public final int f95427d;

        /* JADX INFO: renamed from: e, reason: collision with root package name */
        public final int f95428e;

        /* JADX INFO: renamed from: f, reason: collision with root package name */
        public final int f95429f;

        /* JADX INFO: renamed from: g, reason: collision with root package name */
        public final int f95430g;

        /* JADX INFO: renamed from: h, reason: collision with root package name */
        public final int f95431h;

        /* JADX INFO: renamed from: i, reason: collision with root package name */
        public final int f95432i;

        /* JADX INFO: renamed from: j, reason: collision with root package name */
        public final int f95433j;

        /* JADX INFO: renamed from: k, reason: collision with root package name */
        public final int f95434k;

        /* JADX INFO: renamed from: l, reason: collision with root package name */
        public final int f95435l;

        public b(C7388m c7388m) {
            int color = Color.parseColor("#32A853");
            this.f95424a = color;
            int color2 = Color.parseColor("#EB4236");
            this.f95425b = color2;
            this.f95426c = U1.a.j(color, 76);
            this.f95427d = U1.a.j(color2, 76);
            int color3 = Color.parseColor("#FFAA00");
            this.f95428e = color3;
            this.f95429f = U1.a.j(color3, 76);
            this.f95430g = U1.a.j(color, 76);
            this.f95431h = U1.a.j(color2, 76);
            this.f95432i = U1.a.j(color, 22);
            this.f95433j = U1.a.j(color2, 22);
            this.f95434k = U1.a.j(color3, 76);
            this.f95435l = U1.a.j(color3, 22);
        }

        public final int a() {
            return this.f95424a;
        }

        public final int b() {
            return this.f95430g;
        }

        public final int c() {
            return this.f95428e;
        }

        public final int d() {
            return this.f95434k;
        }

        public final int e() {
            return this.f95426c;
        }

        public final int f() {
            return this.f95432i;
        }

        public final int g() {
            return this.f95429f;
        }

        public final int h() {
            return this.f95435l;
        }

        public final int i() {
            return this.f95427d;
        }

        public final int j() {
            return this.f95433j;
        }

        public final int k() {
            return this.f95425b;
        }

        public final int l() {
            return this.f95431h;
        }
    }

    /* JADX INFO: renamed from: fk.m$c */
    public /* synthetic */ class c extends p167hg.x {
        public c(C7388m c7388m) {
            super(c7388m, C7388m.class, "klineManager", "getKlineManager()Lsp/aicoin_kline/core/KLineManager;", 0);
        }

        @Override // p313og.l
        public Object get() {
            return ((C7388m) this.f97930b).f95408I;
        }

        @Override // p313og.h
        public void set(Object obj) {
            ((C7388m) this.f97930b).f95408I = (KLineManager) obj;
        }
    }

    public C7388m(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f95409l = new b(this);
        this.f95410m = v(new Paint());
        this.f95411n = v(new Paint());
        this.f95412o = v(new Paint());
        this.f95413p = v(new Paint());
        this.f95414q = v(new Paint());
        this.f95415r = v(new Paint());
        Paint paint = new Paint();
        Paint.Style style = Paint.Style.FILL;
        paint.setStyle(style);
        this.f95416s = paint;
        Paint paint2 = new Paint();
        paint2.setStyle(style);
        this.f95417t = paint2;
        Paint paint3 = new Paint();
        paint3.setStyle(style);
        this.f95418u = paint3;
        Paint paint4 = new Paint();
        paint4.setStyle(style);
        this.f95419v = paint4;
        Paint paint5 = new Paint();
        paint5.setStyle(style);
        this.f95420w = paint5;
        Paint paint6 = new Paint();
        paint6.setStyle(style);
        this.f95421x = paint6;
        this.f95422y = Xj.a.a(12.0f);
        this.f95423z = Xj.a.a(14.0f);
        this.f95401B = new Path();
        this.f95402C = new Path();
        this.f95406G = new nk.r();
    }

    public static Paint v(Paint paint) {
        paint.setStyle(Paint.Style.STROKE);
        paint.setAntiAlias(true);
        paint.setStrokeWidth(Xj.a.a(1.0f));
        return paint;
    }

    public static final KLineManager w() {
        return KLineManager.f142490O.a();
    }

    public final void A(Canvas canvas, float f10, float f11, Paint paint, Paint paint2) {
        Path path = this.f95401B;
        path.reset();
        path.moveTo(f10, f11);
        path.lineTo(f10 - (this.f95423z * 0.5f), (this.f95422y * 0.55f) + f11);
        path.lineTo(f10 - (this.f95423z * 0.2f), (this.f95422y * 0.55f) + f11);
        path.lineTo(f10 - (this.f95423z * 0.2f), this.f95422y + f11);
        path.lineTo((this.f95423z * 0.2f) + f10, this.f95422y + f11);
        path.lineTo((this.f95423z * 0.2f) + f10, (this.f95422y * 0.55f) + f11);
        path.lineTo((this.f95423z * 0.5f) + f10, (this.f95422y * 0.55f) + f11);
        path.close();
        canvas.drawPath(this.f95401B, paint);
        canvas.drawPath(this.f95401B, paint2);
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        AbstractC2759w0 abstractC2759w0;
        gk.r rVar;
        int iP;
        int iP2;
        C2765z c2765zD;
        Sj.a aVarC;
        y1 y1Var;
        AbstractC2759w0 abstractC2759w1;
        int i10;
        int i11;
        float f10;
        List list;
        Object obj;
        gk.r rVar2;
        nk.r.b bVar;
        int i12;
        float f11;
        float f12;
        float f13;
        float f14;
        y1 y1Var2 = this.f95403D;
        if (y1Var2 == null || (abstractC2759w0 = this.f95404E) == null || (rVar = this.f95405F) == null || abstractC2759w0.z() == 0.0d) {
            return;
        }
        long jF = y1Var2.F();
        long jN = y1Var2.n();
        List listS = rVar.s();
        if (listS.isEmpty()) {
            return;
        }
        if (!listS.isEmpty() && ((AIWinRateItem) Sf.z.o0(listS)).getSignal_time_s() <= jF) {
            int iP3 = Sf.r.p(listS);
            int i13 = iP3 >> 1;
            int i14 = 0;
            while (i14 <= iP3) {
                if (jF <= ((AIWinRateItem) listS.get(i13)).getSignal_time_s()) {
                    iP3 = i13 - 1;
                } else {
                    i14 = i13 + 1;
                }
                i13 = (i14 + iP3) >> 1;
            }
            iP = p292ng.i.p(i14, 0, Sf.r.p(listS));
        } else {
            iP = -1;
        }
        Integer numValueOf = Integer.valueOf(iP);
        if (iP == -1) {
            numValueOf = null;
        }
        int iIntValue = numValueOf != null ? numValueOf.intValue() : 0;
        if (!listS.isEmpty() && ((AIWinRateItem) Sf.z.B0(listS)).getSignal_time_s() >= jN) {
            int iP4 = Sf.r.p(listS);
            int i15 = iP4 >> 1;
            int i16 = 0;
            while (i16 <= iP4) {
                if (jN >= ((AIWinRateItem) listS.get(i15)).getSignal_time_s()) {
                    i16 = i15 + 1;
                } else {
                    iP4 = i15 - 1;
                }
                i15 = (i16 + iP4) >> 1;
            }
            iP2 = p292ng.i.p(iP4, 0, Sf.r.p(listS));
        } else {
            iP2 = -1;
        }
        Integer numValueOf2 = iP2 != -1 ? Integer.valueOf(iP2) : null;
        List listA1 = Sf.z.a1(listS, new p292ng.g(iIntValue, numValueOf2 != null ? numValueOf2.intValue() : Sf.r.p(listS)));
        if (listA1.isEmpty() || (c2765zD = rVar.h().d()) == null || (aVarC = c2765zD.C()) == null || aVarC.isEmpty()) {
            return;
        }
        float fU = y1Var2.u();
        int iF = p292ng.i.f(y1Var2.r(), 0);
        int iK = p292ng.i.k(y1Var2.q(), aVarC.size());
        if (iF >= iK) {
            return;
        }
        float fJ = y1Var2.J();
        float f15 = 2;
        this.f95400A = Xj.a.a(y1Var2.z()) / f15;
        nk.r.b bVarC = this.f95406G.c();
        bVarC.d();
        float fU2 = (y1Var2.u() / f15) - fJ;
        long jH = y1Var2.H(iF + 1) - y1Var2.H(iF);
        float f16 = fU2;
        int i17 = 0;
        while (iF < iK) {
            Sj.b bVar2 = (Sj.b) Sf.z.r0(aVarC, iF);
            if (bVar2 == null) {
                break;
            }
            double dB = bVar2.b();
            float f17 = f16;
            nk.r.b bVar3 = bVarC;
            double dC = bVar2.c();
            float fS = abstractC2759w0.S(dB);
            float fS2 = abstractC2759w0.S(dC);
            long jH2 = y1Var2.H(iF);
            int size = listA1.size();
            int i18 = i17;
            int i19 = 0;
            int i20 = 0;
            while (true) {
                if (i18 >= size) {
                    y1Var = y1Var2;
                    abstractC2759w1 = abstractC2759w0;
                    break;
                }
                y1Var = y1Var2;
                AIWinRateItem aIWinRateItem = (AIWinRateItem) listA1.get(i18);
                abstractC2759w1 = abstractC2759w0;
                boolean zT = rVar.t(aIWinRateItem);
                long j10 = jH2 + jH;
                long signal_time_s = aIWinRateItem.getSignal_time_s();
                if (jH2 > signal_time_s || signal_time_s >= j10) {
                    break;
                }
                int i21 = iF;
                KLineManager kLineManager = this.f95408I;
                if (kLineManager != null) {
                    i10 = size;
                    if (kLineManager.e0() && !zT) {
                        list = listA1;
                        f17 = f17;
                        i10 = i10;
                        f15 = f15;
                        i21 = i21;
                        rVar2 = rVar;
                        bVar = bVar3;
                        i12 = i18;
                    }
                    i18 = i12 + 1;
                    bVar3 = bVar;
                    f15 = f15;
                    abstractC2759w0 = abstractC2759w1;
                    y1Var2 = y1Var;
                    rVar = rVar2;
                    iF = i21;
                    listA1 = list;
                    f17 = f17;
                    size = i10;
                } else {
                    i10 = size;
                }
                if (AbstractC7609s.f(aIWinRateItem.getSide(), "buy")) {
                    i11 = i19 + 1;
                    f10 = (i19 * this.f95422y) + this.f95400A + fS2 + this.f95407H;
                } else {
                    float f18 = ((fS - this.f95400A) - (i20 * this.f95422y)) - this.f95407H;
                    i20++;
                    i11 = i19;
                    f10 = f18;
                }
                if (AbstractC7609s.f(aIWinRateItem.getSide(), "buy")) {
                    int state = aIWinRateItem.getState();
                    if (state == 0) {
                        list = listA1;
                        obj = "buy";
                    } else if (state != 1 && state != 2) {
                        list = listA1;
                        if (state != 3) {
                            f17 = f17;
                            obj = "buy";
                            f15 = f15;
                            i10 = i10;
                            i21 = i21;
                            rVar2 = rVar;
                            bVar = bVar3;
                            i12 = i18;
                            f11 = f10;
                        } else {
                            obj = "buy";
                        }
                    } else if (zT) {
                        int i22 = i18;
                        f11 = f10;
                        list = listA1;
                        obj = "buy";
                        i10 = i10;
                        i21 = i21;
                        rVar2 = rVar;
                        bVar = bVar3;
                        i12 = i22;
                        f17 = f17;
                        f15 = f15;
                        A(canvas, f17, f11, this.f95414q, this.f95420w);
                    } else {
                        list = listA1;
                        f17 = f17;
                        obj = "buy";
                        f15 = f15;
                        i10 = i10;
                        i21 = i21;
                        rVar2 = rVar;
                        bVar = bVar3;
                        i12 = i18;
                        f11 = f10;
                        A(canvas, f17, f11, this.f95415r, this.f95421x);
                    }
                    rVar2 = rVar;
                    bVar = bVar3;
                    i12 = i18;
                    f11 = f10;
                    if (zT) {
                        A(canvas, f17, f11, this.f95410m, this.f95416s);
                    } else {
                        A(canvas, f17, f11, this.f95412o, this.f95418u);
                    }
                } else {
                    list = listA1;
                    i10 = i10;
                    obj = "buy";
                    f17 = f17;
                    i21 = i21;
                    f15 = f15;
                    rVar2 = rVar;
                    bVar = bVar3;
                    i12 = i18;
                    f11 = f10;
                    int state2 = aIWinRateItem.getState();
                    if (state2 != 0) {
                        if (state2 == 1 || state2 == 2) {
                            if (zT) {
                                x(canvas, f17, f11, this.f95414q, this.f95420w);
                            } else {
                                x(canvas, f17, f11, this.f95415r, this.f95421x);
                            }
                        } else if (state2 == 3) {
                        }
                    }
                    if (zT) {
                        x(canvas, f17, f11, this.f95411n, this.f95417t);
                    } else {
                        x(canvas, f17, f11, this.f95413p, this.f95419v);
                    }
                }
                aIWinRateItem.setNew(zT);
                boolean zF = AbstractC7609s.f(aIWinRateItem.getSide(), obj);
                nk.q qVarA = nk.q.f134234e.a();
                if (zF) {
                    float f19 = this.f95423z / f15;
                    float f20 = 10;
                    f12 = (f17 - f19) - f20;
                    f13 = f19 + f17 + f20;
                    f14 = f11;
                    f11 = this.f95422y + f11;
                } else {
                    float f21 = this.f95423z / f15;
                    float f22 = 10;
                    f12 = (f17 - f21) - f22;
                    f13 = f21 + f17 + f22;
                    f14 = f11 - this.f95422y;
                }
                qVarA.g(f12, f14, f13, f11);
                qVarA.i(f12, f14, f13, f11);
                qVarA.j(aIWinRateItem);
                bVar.e(qVarA);
                i19 = i11;
                i18 = i12 + 1;
                bVar3 = bVar;
                f15 = f15;
                abstractC2759w0 = abstractC2759w1;
                y1Var2 = y1Var;
                rVar = rVar2;
                iF = i21;
                listA1 = list;
                f17 = f17;
                size = i10;
            }
            gk.r rVar3 = rVar;
            nk.r.b bVar4 = bVar3;
            int i23 = i18;
            f16 = f17 + fU;
            iF++;
            bVarC = bVar4;
            i17 = i23;
            f15 = f15;
            abstractC2759w0 = abstractC2759w1;
            y1Var2 = y1Var;
            rVar = rVar3;
            listA1 = listA1;
        }
        bVarC.b();
    }

    @Override // Rj.AbstractC2744r0
    public boolean n(String str, int i10, int i11) {
        Object objD = this.f95406G.d(i10, i11);
        if (objD == null || !(objD instanceof AIWinRateItem)) {
            return false;
        }
        C2738p.f19487a.t((AIWinRateItem) objD);
        return true;
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        if (aVar == null) {
            return;
        }
        C2741q c2741qB = i().b();
        this.f95407H = c2741qB.r(KLineManager.f142490O.a(), Zj.e.a.f27601d);
        if (((KLineManager) p162hb.g.a(new c(this), new C7387l())).V()) {
            this.f95410m.setColor(this.f95409l.k());
            this.f95411n.setColor(this.f95409l.a());
            this.f95412o.setColor(this.f95409l.i());
            this.f95413p.setColor(this.f95409l.e());
            this.f95416s.setColor(this.f95409l.l());
            this.f95417t.setColor(this.f95409l.b());
            this.f95418u.setColor(this.f95409l.j());
            this.f95419v.setColor(this.f95409l.f());
        } else {
            this.f95410m.setColor(this.f95409l.a());
            this.f95411n.setColor(this.f95409l.k());
            this.f95412o.setColor(this.f95409l.e());
            this.f95413p.setColor(this.f95409l.i());
            this.f95416s.setColor(this.f95409l.b());
            this.f95417t.setColor(this.f95409l.l());
            this.f95418u.setColor(this.f95409l.f());
            this.f95419v.setColor(this.f95409l.j());
        }
        this.f95414q.setColor(this.f95409l.c());
        this.f95420w.setColor(this.f95409l.d());
        this.f95415r.setColor(this.f95409l.g());
        this.f95421x.setColor(this.f95409l.h());
        this.f95403D = c2741qB.m(c());
        this.f95404E = c2741qB.l(b());
        AbstractC2755v abstractC2755vQ = q();
        gk.r rVar = abstractC2755vQ instanceof gk.r ? (gk.r) abstractC2755vQ : null;
        if (rVar == null) {
            return;
        }
        this.f95405F = rVar;
    }

    public final void x(Canvas canvas, float f10, float f11, Paint paint, Paint paint2) {
        Path path = this.f95402C;
        path.reset();
        path.moveTo(f10, f11);
        path.lineTo(f10 - (this.f95423z * 0.5f), f11 - (this.f95422y * 0.55f));
        path.lineTo(f10 - (this.f95423z * 0.2f), f11 - (this.f95422y * 0.55f));
        path.lineTo(f10 - (this.f95423z * 0.2f), f11 - this.f95422y);
        path.lineTo((this.f95423z * 0.2f) + f10, f11 - this.f95422y);
        path.lineTo((this.f95423z * 0.2f) + f10, f11 - (this.f95422y * 0.55f));
        path.lineTo((this.f95423z * 0.5f) + f10, f11 - (this.f95422y * 0.55f));
        path.close();
        canvas.drawPath(this.f95402C, paint);
        canvas.drawPath(this.f95402C, paint2);
    }
}
