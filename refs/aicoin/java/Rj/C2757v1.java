package Rj;

import ck.C6303b;
import ck.C6304c;
import ck.C6305d;
import fk.C7376a;
import fk.C7377b;
import fk.C7379d;
import fk.C7383h;
import fk.C7388m;
import fk.C7393s;
import fk.C7394t;
import fk.C7395u;
import fk.C7396v;
import fk.C7397w;
import fk.C7399y;
import gk.C7452a;
import gk.C7453a0;
import gk.C7454b;
import gk.C7456c;
import gk.C7458d;
import gk.C7460e;
import gk.C7465g0;
import gk.C7468i;
import gk.C7469i0;
import gk.C7471j0;
import gk.C7472k;
import gk.C7473k0;
import gk.C7476m;
import gk.C7478n;
import gk.C7481o0;
import gk.C7482p;
import gk.C7483p0;
import gk.C7487s;
import gk.C7488s0;
import gk.C7489t;
import gk.C7490t0;
import gk.C7491u;
import gk.C7492u0;
import gk.C7493v;
import gk.C7495w;
import gk.C7496w0;
import gk.C7497x;
import gk.C7498x0;
import gk.C7499y;
import gk.C7500y0;
import gk.C7501z;
import gk.C7502z0;
import java.text.DecimalFormat;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import org.apache.tika.metadata.DublinCore;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: Rj.v1, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2757v1 {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final C2757v1 f19568a = new C2757v1();

    /* JADX INFO: renamed from: Rj.v1$a */
    public /* synthetic */ class a {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public static final /* synthetic */ int[] f19569a;

        static {
            int[] iArr = new int[Zj.g.values().length];
            try {
                iArr[Zj.g.POSITIVE.ordinal()] = 1;
            } catch (NoSuchFieldError unused) {
            }
            try {
                iArr[Zj.g.NEGATIVE.ordinal()] = 2;
            } catch (NoSuchFieldError unused2) {
            }
            try {
                iArr[Zj.g.ZERO.ordinal()] = 3;
            } catch (NoSuchFieldError unused3) {
            }
            f19569a = iArr;
        }
    }

    public static final AbstractC2755v E(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new gk.G(c2732n, str, f10);
    }

    public static void F(C2732n c2732n, String str) {
        C2741q c2741qB = c2732n.b();
        sp.aicoin_kline.core.indicator.config.F f10 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get("publicScript-basisBinance");
        if (f10 == null) {
            throw new RuntimeException("indicatorConfig not found");
        }
        gk.C c10 = new gk.C(c2732n, kk.i.a(str, ".m"), f10);
        String strD = c10.d();
        if (strD == null) {
            c2741qB.getClass();
        } else {
            c2741qB.f19500h.put(strD, c10);
        }
        C2750t0 c2750t0 = new C2750t0(c2732n, str);
        c2750t0.M(nk.n.d(f10.q()));
        c2750t0.N(51);
        c2750t0.J(Xj.a.d(16));
        c2750t0.I(Xj.a.d(8));
        c2741qB.f19499g.put(c2750t0.d(), c2750t0);
        l(c2732n, str);
        C7395u c7395u = new C7395u(c2732n, kk.i.a(str, ".m"), "publicScript-basisBinance");
        c2741qB.f19501i.put(c7395u.d(), c7395u);
        C7394t c7394t = new C7394t(c2732n, kk.i.a(str, ".i"), "publicScript-basisBinance");
        c2741qB.f19501i.put(c7394t.d(), c7394t);
        w(c2732n, str);
        s(c2732n, str, "#.000", null);
    }

    public static final AbstractC2755v G(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new gk.H0(c2732n, str, f10);
    }

    public static void H(C2732n c2732n, String str) {
        C2741q c2741qB = c2732n.b();
        sp.aicoin_kline.core.indicator.config.F f10 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get("publicScript-basisOkex");
        if (f10 == null) {
            throw new RuntimeException("indicatorConfig not found");
        }
        gk.D d10 = new gk.D(c2732n, kk.i.a(str, ".m"), f10);
        String strD = d10.d();
        if (strD == null) {
            c2741qB.getClass();
        } else {
            c2741qB.f19500h.put(strD, d10);
        }
        C2750t0 c2750t0 = new C2750t0(c2732n, str);
        c2750t0.M(nk.n.d(f10.q()));
        c2750t0.N(50);
        c2750t0.J(Xj.a.d(16));
        c2750t0.I(Xj.a.d(8));
        c2741qB.f19499g.put(c2750t0.d(), c2750t0);
        l(c2732n, str);
        C7395u c7395u = new C7395u(c2732n, kk.i.a(str, ".m"), "publicScript-basisOkex");
        c2741qB.f19501i.put(c7395u.d(), c7395u);
        C7394t c7394t = new C7394t(c2732n, kk.i.a(str, ".i"), "publicScript-basisOkex");
        c2741qB.f19501i.put(c7394t.d(), c7394t);
        w(c2732n, str);
        s(c2732n, str, "#.000", null);
    }

    public static final AbstractC2755v I(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new gk.N(c2732n, str, f10);
    }

    public static void J(C2732n c2732n, String str) {
        C2741q c2741qB = c2732n.b();
        sp.aicoin_kline.core.indicator.config.F f10 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get("publicScript-coinContract");
        if (f10 == null) {
            throw new RuntimeException("indicatorConfig not found");
        }
        gk.I i10 = new gk.I(c2732n, kk.i.a(str, ".m"), f10);
        String strD = i10.d();
        if (strD == null) {
            c2741qB.getClass();
        } else {
            c2741qB.f19500h.put(strD, i10);
        }
        C2750t0 c2750t0 = new C2750t0(c2732n, str);
        c2750t0.M(nk.n.d(f10.q()));
        c2750t0.N(53);
        c2750t0.J(Xj.a.d(16));
        c2750t0.I(Xj.a.d(8));
        c2741qB.f19499g.put(c2750t0.d(), c2750t0);
        l(c2732n, str);
        C7395u c7395u = new C7395u(c2732n, kk.i.a(str, ".m"), "publicScript-coinContract");
        c2741qB.f19501i.put(c7395u.d(), c7395u);
        C7394t c7394t = new C7394t(c2732n, kk.i.a(str, ".i"), "publicScript-coinContract");
        c2741qB.f19501i.put(c7394t.d(), c7394t);
        w(c2732n, str);
        s(c2732n, str, "#.000", null);
    }

    public static final AbstractC2755v K(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new C7502z0(c2732n, str, f10);
    }

    public static void L(C2732n c2732n, String str) {
        C2741q c2741qB = c2732n.b();
        sp.aicoin_kline.core.indicator.config.F f10 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get("publicScript-cvd");
        if (f10 == null) {
            throw new RuntimeException("indicatorConfig not found");
        }
        gk.J j10 = new gk.J(c2732n, kk.i.a(str, ".m"), f10);
        String strD = j10.d();
        if (strD == null) {
            c2741qB.getClass();
        } else {
            c2741qB.f19500h.put(strD, j10);
        }
        C2750t0 c2750t0 = new C2750t0(c2732n, str);
        c2750t0.M(nk.n.d(f10.q()));
        c2750t0.N(46);
        c2750t0.J(Xj.a.d(16));
        c2750t0.I(Xj.a.d(8));
        c2741qB.f19499g.put(c2750t0.d(), c2750t0);
        l(c2732n, str);
        C7395u c7395u = new C7395u(c2732n, kk.i.a(str, ".m"), "publicScript-cvd");
        c2741qB.f19501i.put(c7395u.d(), c7395u);
        C7394t c7394t = new C7394t(c2732n, kk.i.a(str, ".i"), "publicScript-cvd");
        c2741qB.f19501i.put(c7394t.d(), c7394t);
        w(c2732n, str);
        s(c2732n, str, "#.000", null);
    }

    public static final AbstractC2755v M(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new gk.B(c2732n, str, f10);
    }

    public static void N(C2732n c2732n, String str) {
        if (AbstractC7609s.f(KLineManager.f142490O.a().K(), "master") || nk.n.f(17)) {
            C2741q c2741qB = c2732n.b();
            C6305d c6305d = new C6305d(c2732n, kk.i.a(str, ".drawing"));
            String strD = c6305d.d();
            if (strD == null) {
                c2741qB.getClass();
            } else {
                c2741qB.f19500h.put(strD, c6305d);
            }
            C6304c c6304c = new C6304c(c2732n, kk.i.a(str, ".drawing"));
            c6304c.r(c6305d);
            Qf.H h10 = Qf.H.f17640a;
            C2752u c2752u = new C2752u(c2732n, c6304c);
            c2741qB.f19501i.put(c2752u.d(), c2752u);
        }
    }

    public static final AbstractC2755v O(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new gk.S(c2732n, str, f10);
    }

    public static void P(C2732n c2732n, String str) {
        C2741q c2741qB = c2732n.b();
        sp.aicoin_kline.core.indicator.config.F f10 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get("publicScript-fundingRate");
        if (f10 == null) {
            throw new RuntimeException("indicatorConfig not found");
        }
        C7473k0 c7473k0 = new C7473k0(c2732n, kk.i.a(str, ".m"), f10);
        String strD = c7473k0.d();
        if (strD == null) {
            c2741qB.getClass();
        } else {
            c2741qB.f19500h.put(strD, c7473k0);
        }
        C2750t0 c2750t0 = new C2750t0(c2732n, str);
        c2750t0.M(nk.n.d(f10.q()));
        c2750t0.N(52);
        c2750t0.J(Xj.a.d(16));
        c2750t0.I(Xj.a.d(8));
        c2741qB.f19499g.put(c2750t0.d(), c2750t0);
        l(c2732n, str);
        C7395u c7395u = new C7395u(c2732n, kk.i.a(str, ".m"), "publicScript-fundingRate");
        c2741qB.f19501i.put(c7395u.d(), c7395u);
        C7394t c7394t = new C7394t(c2732n, kk.i.a(str, ".i"), "publicScript-fundingRate");
        c2741qB.f19501i.put(c7394t.d(), c7394t);
        w(c2732n, str);
        s(c2732n, str, "#.000", null);
    }

    public static final AbstractC2755v Q(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new gk.F(c2732n, str, f10);
    }

    public static void R(C2732n c2732n, String str) {
        C2741q c2741qB = c2732n.b();
        sp.aicoin_kline.core.indicator.config.F f10 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get("publicScript-usdtContract");
        if (f10 == null) {
            throw new RuntimeException("indicatorConfig not found");
        }
        gk.W0 w10 = new gk.W0(c2732n, kk.i.a(str, ".m"), f10);
        String strD = w10.d();
        if (strD == null) {
            c2741qB.getClass();
        } else {
            c2741qB.f19500h.put(strD, w10);
        }
        C2750t0 c2750t0 = new C2750t0(c2732n, str);
        c2750t0.M(nk.n.d(f10.q()));
        c2750t0.N(54);
        c2750t0.J(Xj.a.d(16));
        c2750t0.I(Xj.a.d(8));
        c2741qB.f19499g.put(c2750t0.d(), c2750t0);
        l(c2732n, str);
        C7395u c7395u = new C7395u(c2732n, kk.i.a(str, ".m"), "publicScript-usdtContract");
        c2741qB.f19501i.put(c7395u.d(), c7395u);
        C7394t c7394t = new C7394t(c2732n, kk.i.a(str, ".i"), "publicScript-usdtContract");
        c2741qB.f19501i.put(c7394t.d(), c7394t);
        w(c2732n, str);
        s(c2732n, str, "#.000", null);
    }

    public static final AbstractC2755v S(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new gk.C0(c2732n, str, f10);
    }

    public static void T(C2732n c2732n, String str) {
        C2741q c2741qB = c2732n.b();
        sp.aicoin_kline.core.indicator.config.F f10 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get("volume");
        if (f10 == null) {
            throw new RuntimeException("indicatorConfig not found");
        }
        boolean zD = nk.n.d(f10.q());
        G1 g10 = new G1(c2732n, kk.i.a(str, ".m"));
        String strD = g10.d();
        if (strD == null) {
            c2741qB.getClass();
        } else {
            c2741qB.f19500h.put(strD, g10);
        }
        fk.c0 c0Var = new fk.c0(c2732n, kk.i.a(str, ".a"), f10);
        String strD2 = c0Var.d();
        if (strD2 != null) {
            c2741qB.f19500h.put(strD2, c0Var);
        }
        C2750t0 c2750t0 = new C2750t0(c2732n, str);
        c2750t0.N(11);
        c2750t0.M(zD);
        c2750t0.J(Xj.a.d(12));
        c2750t0.I(Xj.a.d(4));
        c2741qB.f19499g.put(c2750t0.d(), c2750t0);
        l(c2732n, str);
        J1 j10 = new J1(c2732n, kk.i.a(str, ".m"), zD);
        c2741qB.f19501i.put(j10.d(), j10);
        fk.D d10 = new fk.D(c2732n, kk.i.a(str, ".a"), ".a");
        c2741qB.f19501i.put(d10.d(), d10);
        fk.b0 b0Var = new fk.b0(c2732n, kk.i.a(str, ".i"), ".a");
        c2741qB.f19501i.put(b0Var.d(), b0Var);
        w(c2732n, str);
        String str2 = str + "Range";
        C2766z0 c2766z0 = new C2766z0(c2732n, kk.i.a(str2, ".b"));
        c2741qB.f19501i.put(c2766z0.d(), c2766z0);
        B0 b10 = new B0(c2732n, kk.i.a(str2, ".m"));
        c2741qB.f19501i.put(b10.d(), b10);
        Y y10 = new Y(c2732n, kk.i.a(str2, ".d"));
        c2741qB.f19501i.put(y10.d(), y10);
        M m10 = new M(c2732n, kk.i.a(str2, ".hd"));
        m10.B(true);
        c2741qB.f19501i.put(m10.d(), m10);
    }

    public static final AbstractC2755v U(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new gk.T0(c2732n, str, f10);
    }

    public static final AbstractC2755v W(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new gk.R0(c2732n, str, f10);
    }

    public static final AbstractC2755v X(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new gk.H(c2732n, str, f10);
    }

    public static final AbstractC2755v Y(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new C7487s(c2732n, str, f10);
    }

    public static final AbstractC2755v Z(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new C7483p0(c2732n, str, f10);
    }

    public static final AbstractC2755v a(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new C7454b(c2732n, str, f10);
    }

    public static final AbstractC2755v a0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new C7501z(c2732n, str, f10);
    }

    public static final AbstractC2755v b(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new gk.X(c2732n, str, f10);
    }

    public static final AbstractC2755v b0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new gk.U0(c2732n, str, f10);
    }

    public static final AbstractC2755v c(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new gk.B0(c2732n, str, f10);
    }

    public static final AbstractC2755v c0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new gk.Y(c2732n, str, f10);
    }

    public static final AbstractC2755v d(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new gk.A0(c2732n, str, f10);
    }

    public static final AbstractC2755v d0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new C7498x0(c2732n, str, f10);
    }

    public static final AbstractC2755v e(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new gk.V0(c2732n, str, f10);
    }

    public static final AbstractC2755v e0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new gk.E(c2732n, str, f10);
    }

    public static final AbstractC2755v f(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new gk.Z0(c2732n, str, f10);
    }

    public static final AbstractC2755v f0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new C7456c(c2732n, str, f10);
    }

    public static final AbstractC2755v g(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new gk.E0(c2732n, str, f10);
    }

    public static final AbstractC2755v g0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new C7478n(c2732n, str, f10);
    }

    public static final AbstractC2755v h(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new C7499y(c2732n, str, f10);
    }

    public static final AbstractC2755v h0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new C7460e(c2732n, str, f10);
    }

    public static final AbstractC2755v i(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new gk.Z(c2732n, str, f10);
    }

    public static final AbstractC2755v i0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new C7452a(c2732n, str, f10);
    }

    public static final AbstractC2755v j(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new gk.Q(c2732n, str, f10);
    }

    public static final AbstractC2755v j0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new C7476m(c2732n, str, f10);
    }

    /* JADX WARN: Can't fix incorrect switch cases order, some code will duplicate */
    /* JADX WARN: Code duplicated, block: B:79:0x0199  */
    public static HashMap k(C2732n c2732n, String str, List list) {
        AbstractC2755v c7482p;
        C2741q c2741qB = c2732n.b();
        ArrayList arrayList = new ArrayList();
        HashMap map = new HashMap();
        Map mapU = KLineManager.f142490O.a().u();
        int size = list.size();
        for (int i10 = 0; i10 < size; i10++) {
            String str2 = (String) list.get(i10);
            if (C2703d0.f19361a.a(str2, mapU)) {
                sp.aicoin_kline.core.indicator.config.F f10 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get(str2);
                if (f10 == null) {
                    throw new RuntimeException("indicatorConfig not found");
                }
                switch (str2) {
                    case "ai_srl":
                        c7482p = new C7482p(c2732n, kk.i.a(str, ".a"), f10);
                        break;
                    case "main_script_indicator":
                        c7482p = new gk.J0(c2732n, kk.i.a(str, ".a"), f10);
                        break;
                    case "ichimoku":
                        c7482p = new C7465g0(c2732n, kk.i.a(str, ".a"), f10);
                        break;
                    case "ai_large_order":
                        c7482p = new C7468i(c2732n, kk.i.a(str, ".a"), f10);
                        break;
                    case "ai_large_trade":
                        c7482p = new C7472k(c2732n, kk.i.a(str, ".a"), f10);
                        break;
                    case "dc":
                        c7482p = new gk.M(c2732n, kk.i.a(str, ".a"), f10);
                        break;
                    case "kc":
                        c7482p = new C7481o0(c2732n, kk.i.a(str, ".a"), f10);
                        break;
                    case "ma":
                        c7482p = new C7500y0(c2732n, kk.i.a(str, ".a"), f10);
                        break;
                    case "td":
                        c7482p = new gk.P0(c2732n, kk.i.a(str, ".a"), f10);
                        break;
                    case "bbi":
                        c7482p = new gk.A(c2732n, kk.i.a(str, ".a"), f10);
                        break;
                    case "ema":
                        c7482p = new gk.T(c2732n, kk.i.a(str, ".a"), f10);
                        break;
                    case "ene":
                        c7482p = new gk.U(c2732n, kk.i.a(str, ".a"), f10);
                        break;
                    case "sar":
                        c7482p = new gk.I0(c2732n, kk.i.a(str, ".a"), f10);
                        break;
                    case "boll":
                        c7482p = new gk.H(c2732n, kk.i.a(str, ".a"), f10);
                        break;
                    case "vpvr":
                        c7482p = new gk.X0(c2732n, kk.i.a(str, ".a"), f10);
                        break;
                    case "alligator":
                        c7482p = new C7497x(c2732n, kk.i.a(str, ".a"), f10);
                        break;
                    case "ai_win_rate":
                        c7482p = new gk.r(c2732n, kk.i.a(str, ".a"), f10);
                        break;
                    default:
                        c7482p = null;
                        break;
                }
                if (c7482p != null) {
                    arrayList.add(c7482p);
                    map.put(str2, c7482p);
                }
            }
        }
        C7458d c7458d = new C7458d(c2732n, kk.i.a(str, ".a"));
        arrayList.add(c7458d);
        map.put("ai_handle_line", c7458d);
        C7495w c7495w = new C7495w(c2732n, kk.i.a(str, ".a"));
        arrayList.add(c7495w);
        map.put("main_alert_line", c7495w);
        C7488s0 c7488s0 = new C7488s0(c2732n, kk.i.a(str, ".a"));
        arrayList.add(c7488s0);
        map.put("main_liqui_line", c7488s0);
        if (list.contains("liqheatmap") && C2703d0.f19361a.a("liqheatmap", mapU)) {
            sp.aicoin_kline.core.indicator.config.F f11 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get("liqheatmap");
            if (f11 == null) {
                throw new RuntimeException("indicatorConfig not found");
            }
            gk.V v10 = new gk.V(c2732n, kk.i.a(str, ".a"), f11);
            arrayList.add(v10);
            map.put("liqheatmap", v10);
        }
        Tj.a aVar = new Tj.a(c2732n, kk.i.a(str, ".a"), (AbstractC2755v[]) arrayList.toArray(new AbstractC2755v[0]));
        String strD = aVar.d();
        if (strD == null) {
            c2741qB.getClass();
            return map;
        }
        c2741qB.f19500h.put(strD, aVar);
        return map;
    }

    public static void l(C2732n c2732n, String str) {
        C2741q c2741qB = c2732n.b();
        C2700c0 c2700c0 = new C2700c0(c2732n, kk.i.a(str, ".b"));
        c2741qB.f19501i.put(c2700c0.d(), c2700c0);
        J j10 = new J(c2732n, kk.i.a(str, ".g"));
        c2741qB.f19502j.put(j10.d(), j10);
    }

    public static void m(C2732n c2732n, String str, L0 l10, String str2, String str3) {
        String str4 = str + str3;
        n(c2732n, str4, l10, false);
        switch (str2) {
            case "publicScript-usdtContract":
                R(c2732n, str4);
                return;
            case "publicScript-basisOkex":
                H(c2732n, str4);
                return;
            case "publicScript-basisBinance":
                F(c2732n, str4);
                return;
            case "ai-bsi":
                q(c2732n, str4, str2, Zj.g.ZERO, Zj.a.POS_NEG, new C2710f1(c2732n));
                return;
            case "ai-bst":
                q(c2732n, str4, str2, Zj.g.POSITIVE, Zj.a.DATA, new C2707e1(c2732n));
                return;
            case "ai-fdi":
                q(c2732n, str4, str2, Zj.g.ZERO, Zj.a.POS_NEG, new C2704d1(c2732n));
                return;
            case "publicScript-fundingRate":
                P(c2732n, str4);
                return;
            case "tvolume":
                q(c2732n, str4, str2, Zj.g.POSITIVE, Zj.a.DATA, new C2701c1(c2732n));
                return;
            case "volume":
                T(c2732n, str4);
                return;
            case "ai-netvol":
                t(c2732n, str4, str2, false, new C2698b1(c2732n));
                return;
            case "publicScript-cvd":
                L(c2732n, str4);
                return;
            case "publicScript-coinContract":
                J(c2732n, str4);
                return;
            case "publicScript-activeTradeVolume":
                z(c2732n, str4);
                return;
            case "ao":
                q(c2732n, str4, str2, Zj.g.ZERO, Zj.a.PRE, new Z0(c2732n));
                return;
            case "fr":
                x(c2732n, str4, str2, new Y0(c2732n));
                return;
            case "vr":
                t(c2732n, str4, str2, false, new W0(c2732n));
                return;
            case "wr":
                t(c2732n, str4, str2, false, new V0(c2732n));
                return;
            case "atr":
                t(c2732n, str4, str2, false, new U0(c2732n));
                return;
            case "bbw":
                r(c2732n, str4, str2, new T0(c2732n));
                return;
            case "bsv":
                t(c2732n, str4, str2, true, new S0(c2732n));
                return;
            case "cci":
                C2741q c2741qB = c2732n.b();
                sp.aicoin_kline.core.indicator.config.F f10 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get("cci");
                if (f10 == null) {
                    throw new RuntimeException("indicatorConfig not found");
                }
                gk.K k10 = new gk.K(c2732n, kk.i.a(str4, ".m"), f10);
                ek.w[] wVarArrL = f10.l();
                String strD = k10.d();
                if (strD == null) {
                    c2741qB.getClass();
                } else {
                    c2741qB.f19500h.put(strD, k10);
                }
                C2750t0 c2750t0 = new C2750t0(c2732n, str4);
                c2750t0.M(nk.n.d(f10.q()));
                c2750t0.N(8);
                c2750t0.J(Xj.a.d(16));
                c2750t0.I(Xj.a.d(8));
                c2741qB.f19499g.put(c2750t0.d(), c2750t0);
                l(c2732n, str4);
                Vj.b bVar = new Vj.b(c2732n, kk.i.a(str4, ".m"), new AbstractC2744r0[]{new fk.E(p292ng.h.b(wVarArrL[2].g(), wVarArrL[1].g()), c2732n, kk.i.a(str4, ".m")), new fk.D(c2732n, kk.i.a(str4, ".m"))});
                c2741qB.f19501i.put(bVar.d(), bVar);
                o(c2732n, str4, null);
                s(c2732n, str4, "#.000", null);
                return;
            case "dma":
                t(c2732n, str4, str2, false, new R0(c2732n));
                return;
            case "dmi":
                t(c2732n, str4, str2, false, new Q0(c2732n));
                return;
            case "dpo":
                C2741q c2741qB2 = c2732n.b();
                sp.aicoin_kline.core.indicator.config.F f11 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get("dpo");
                if (f11 == null) {
                    throw new RuntimeException("indicatorConfig not found");
                }
                gk.L l11 = new gk.L(c2732n, kk.i.a(str4, ".m"), f11);
                String strD2 = l11.d();
                if (strD2 == null) {
                    c2741qB2.getClass();
                } else {
                    c2741qB2.f19500h.put(strD2, l11);
                }
                C2750t0 c2750t1 = new C2750t0(c2732n, str4);
                c2750t1.M(nk.n.d(f11.q()));
                c2750t1.N(29);
                c2750t1.J(Xj.a.d(16));
                c2750t1.I(Xj.a.d(8));
                c2741qB2.f19499g.put(c2750t1.d(), c2750t1);
                l(c2732n, str4);
                Vj.b bVar2 = new Vj.b(c2732n, kk.i.a(str4, ".m"), new AbstractC2744r0[]{new fk.a0(new double[]{0.0d}, c2732n, kk.i.a(str4, ".m")), new fk.D(c2732n, kk.i.a(str4, ".m"))});
                c2741qB2.f19501i.put(bVar2.d(), bVar2);
                o(c2732n, str4, null);
                s(c2732n, str4, "#.000", null);
                return;
            case "emv":
                t(c2732n, str4, str2, false, new P0(c2732n));
                return;
            case "kdj":
                C2741q c2741qB3 = c2732n.b();
                sp.aicoin_kline.core.indicator.config.F f12 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get("kdj");
                if (f12 == null) {
                    throw new RuntimeException("indicatorConfig not found");
                }
                C7471j0 c7471j0 = new C7471j0(c2732n, kk.i.a(str4, ".m"), f12);
                String strD3 = c7471j0.d();
                if (strD3 == null) {
                    c2741qB3.getClass();
                } else {
                    c2741qB3.f19500h.put(strD3, c7471j0);
                }
                V v10 = new V(c2732n, str4);
                v10.M(nk.n.d(f12.q()));
                v10.N(2);
                v10.J(Xj.a.d(8));
                v10.I(Xj.a.d(8));
                c2741qB3.f19499g.put(v10.d(), v10);
                l(c2732n, str4);
                Vj.b bVar3 = new Vj.b(c2732n, kk.i.a(str4, ".m"), new AbstractC2744r0[]{new fk.a0(new double[]{20.0d, 50.0d, 80.0d}, c2732n, kk.i.a(str4, ".m")), new fk.D(c2732n, kk.i.a(str4, ".m"))});
                c2741qB3.f19501i.put(bVar3.d(), bVar3);
                o(c2732n, str4, null);
                s(c2732n, str4, "#.0", null);
                return;
            case "mfi":
                C2741q c2741qB4 = c2732n.b();
                sp.aicoin_kline.core.indicator.config.F f13 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get("mfi");
                if (f13 == null) {
                    throw new RuntimeException("indicatorConfig not found");
                }
                C7496w0 c7496w0 = new C7496w0(c2732n, kk.i.a(str4, ".m"), f13);
                ek.w[] wVarArrL2 = f13.l();
                String strD4 = c7496w0.d();
                if (strD4 == null) {
                    c2741qB4.getClass();
                } else {
                    c2741qB4.f19500h.put(strD4, c7496w0);
                }
                C2750t0 c2750t2 = new C2750t0(c2732n, str4);
                c2750t2.M(nk.n.d(f13.q()));
                c2750t2.N(27);
                c2750t2.J(Xj.a.d(16));
                c2750t2.I(Xj.a.d(8));
                c2741qB4.f19499g.put(c2750t2.d(), c2750t2);
                l(c2732n, str4);
                Vj.b bVar4 = new Vj.b(c2732n, kk.i.a(str4, ".m"), new AbstractC2744r0[]{new fk.E(p292ng.h.b(wVarArrL2[2].g(), wVarArrL2[1].g()), c2732n, kk.i.a(str4, ".m")), new fk.D(c2732n, kk.i.a(str4, ".m"))});
                c2741qB4.f19501i.put(bVar4.d(), bVar4);
                o(c2732n, str4, null);
                s(c2732n, str4, "#.000", null);
                return;
            case "mlr":
                t(c2732n, str4, str2, true, new N0(c2732n));
                return;
            case "mtm":
                t(c2732n, str4, str2, false, new C2754u1(c2732n));
                return;
            case "obv":
                t(c2732n, str4, str2, false, new C2751t1(c2732n));
                return;
            case "pfr":
                x(c2732n, str4, str2, new C2748s1(c2732n));
                return;
            case "psy":
                t(c2732n, str4, str2, false, new C2745r1(c2732n));
                return;
            case "roc":
                t(c2732n, str4, str2, false, new C2743q1(c2732n));
                return;
            case "rsi":
                C2741q c2741qB5 = c2732n.b();
                sp.aicoin_kline.core.indicator.config.F f14 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get("rsi");
                if (f14 == null) {
                    throw new RuntimeException("indicatorConfig not found");
                }
                ek.w[] wVarArrL3 = f14.l();
                gk.F0 f15 = new gk.F0(c2732n, kk.i.a(str4, ".m"), f14);
                String strD5 = f15.d();
                if (strD5 == null) {
                    c2741qB5.getClass();
                } else {
                    c2741qB5.f19500h.put(strD5, f15);
                }
                boolean zD = nk.n.d(f14.q());
                C2750t0 c2750t3 = new C2750t0(c2732n, str4);
                c2750t3.M(zD);
                c2750t3.N(3);
                c2750t3.J(Xj.a.d(16));
                c2750t3.I(Xj.a.d(8));
                c2741qB5.f19499g.put(c2750t3.d(), c2750t3);
                l(c2732n, str4);
                Vj.b bVar5 = new Vj.b(c2732n, kk.i.a(str4, ".m"), new AbstractC2744r0[]{new fk.E(p292ng.h.b(wVarArrL3[5].g(), wVarArrL3[4].g()), c2732n, kk.i.a(str4, ".m")), new fk.D(c2732n, kk.i.a(str4, ".m")), new fk.P(c2732n, kk.i.a(str4, ".m"))});
                c2741qB5.f19501i.put(bVar5.d(), bVar5);
                o(c2732n, str4, null);
                s(c2732n, str4, "#.000", null);
                return;
            case "smi":
                t(c2732n, str4, str2, false, new C2740p1(c2732n));
                return;
            case "bias":
                t(c2732n, str4, str2, false, new C2737o1(c2732n));
                return;
            case "boll":
                C2719i1 c2719i1 = new C2719i1(c2732n);
                C2741q c2741qB6 = c2732n.b();
                sp.aicoin_kline.core.indicator.config.F f16 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get(str2);
                if (f16 == null) {
                    throw new RuntimeException("indicatorConfig not found");
                }
                boolean zD2 = nk.n.d(28);
                AbstractC2755v abstractC2755v = (AbstractC2755v) c2719i1.invoke(str4 + ".m", f16);
                String strD6 = abstractC2755v.d();
                if (strD6 == null) {
                    c2741qB6.getClass();
                } else {
                    c2741qB6.f19500h.put(strD6, abstractC2755v);
                }
                C2750t0 c2750t4 = new C2750t0(c2732n, str4);
                c2750t4.M(zD2);
                c2750t4.N(28);
                c2750t4.J(Xj.a.d(16));
                c2750t4.I(Xj.a.d(8));
                c2741qB6.f19499g.put(c2750t4.d(), c2750t4);
                l(c2732n, str4);
                fk.D d10 = new fk.D(c2732n, kk.i.a(str4, ".m"));
                d10.v(nk.n.d(28));
                Qf.H h10 = Qf.H.f17640a;
                Vj.b bVar6 = new Vj.b(c2732n, str4 + ".m", new AbstractC2744r0[]{d10, new C2699c(c2732n, kk.i.a(str4, ".m"))});
                c2741qB6.f19501i.put(bVar6.d(), bVar6);
                fk.C c10 = new fk.C(c2732n, kk.i.a(str4, ".i"));
                c10.I(true);
                c2741qB6.f19501i.put(c10.d(), c10);
                w(c2732n, str4);
                s(c2732n, str4, "#.000", null);
                return;
            case "brar":
                t(c2732n, str4, str2, false, new X0(c2732n));
                return;
            case "ftbs":
                t(c2732n, str4, str2, true, new C2734n1(c2732n));
                return;
            case "lsur":
                t(c2732n, str4, str2, true, new C2731m1(c2732n));
                return;
            case "macd":
                C2741q c2741qB7 = c2732n.b();
                sp.aicoin_kline.core.indicator.config.F f17 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get("macd");
                if (f17 == null) {
                    throw new RuntimeException("indicatorConfig not found");
                }
                boolean zD3 = nk.n.d(f17.q());
                C7490t0 c7490t0 = new C7490t0(c2732n, kk.i.a(str4, ".m"), f17);
                String strD7 = c7490t0.d();
                if (strD7 == null) {
                    c2741qB7.getClass();
                } else {
                    c2741qB7.f19500h.put(strD7, c7490t0);
                }
                W1 w10 = new W1(c2732n, str4);
                w10.M(zD3);
                w10.J(Xj.a.d(16));
                w10.I(Xj.a.d(8));
                c2741qB7.f19499g.put(w10.d(), w10);
                l(c2732n, str4);
                C2697b0 c2697b0 = new C2697b0(c2732n, kk.i.a(str4, ".m"), zD3);
                c2741qB7.f19501i.put(c2697b0.d(), c2697b0);
                fk.L l12 = new fk.L(c2732n, kk.i.a(str4, ".i"));
                c2741qB7.f19501i.put(l12.d(), l12);
                w(c2732n, str4);
                s(c2732n, str4, "#.000", null);
                return;
            case "skdj":
                C2741q c2741qB8 = c2732n.b();
                sp.aicoin_kline.core.indicator.config.F f18 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get("skdj");
                if (f18 == null) {
                    throw new RuntimeException("indicatorConfig not found");
                }
                gk.G0 g10 = new gk.G0(c2732n, kk.i.a(str4, ".m"), f18);
                String strD8 = g10.d();
                if (strD8 == null) {
                    c2741qB8.getClass();
                } else {
                    c2741qB8.f19500h.put(strD8, g10);
                }
                V v11 = new V(c2732n, str4);
                v11.M(nk.n.d(f18.q()));
                v11.N(18);
                v11.J(Xj.a.d(8));
                v11.I(Xj.a.d(8));
                c2741qB8.f19499g.put(v11.d(), v11);
                l(c2732n, str4);
                fk.D d11 = new fk.D(c2732n, kk.i.a(str4, ".m"));
                c2741qB8.f19501i.put(d11.d(), d11);
                o(c2732n, str4, null);
                s(c2732n, str4, "#.0", null);
                return;
            case "trix":
                t(c2732n, str4, str2, false, new C2728l1(c2732n));
                return;
            case "ttmu":
                t(c2732n, str4, str2, true, new C2725k1(c2732n));
                return;
            case "ttsi":
                t(c2732n, str4, str2, true, new C2722j1(c2732n));
                return;
            case "ai-li":
                q(c2732n, str4, str2, Zj.g.POSITIVE, Zj.a.DATA, new C2716h1(c2732n));
                return;
            case "ai-pd":
                q(c2732n, str4, str2, Zj.g.ZERO, Zj.a.POS_NEG, new C2713g1(c2732n));
                return;
            case "basis":
                t(c2732n, str4, str2, true, new C2695a1(c2732n));
                return;
            case "publicScript-activeTradeCount":
                C2741q c2741qB9 = c2732n.b();
                sp.aicoin_kline.core.indicator.config.F f19 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get("publicScript-activeTradeCount");
                if (f19 == null) {
                    throw new RuntimeException("indicatorConfig not found");
                }
                C7491u c7491u = new C7491u(c2732n, kk.i.a(str4, ".m"), f19);
                String strD9 = c7491u.d();
                if (strD9 == null) {
                    c2741qB9.getClass();
                } else {
                    c2741qB9.f19500h.put(strD9, c7491u);
                }
                C2750t0 c2750t5 = new C2750t0(c2732n, str4);
                c2750t5.M(nk.n.d(f19.q()));
                c2750t5.N(57);
                c2750t5.J(Xj.a.d(16));
                c2750t5.I(Xj.a.d(8));
                c2741qB9.f19499g.put(c2750t5.d(), c2750t5);
                l(c2732n, str4);
                C7395u c7395u = new C7395u(c2732n, kk.i.a(str4, ".m"), "publicScript-activeTradeCount");
                c2741qB9.f19501i.put(c7395u.d(), c7395u);
                C7394t c7394t = new C7394t(c2732n, kk.i.a(str4, ".i"), "publicScript-activeTradeCount");
                c2741qB9.f19501i.put(c7394t.d(), c7394t);
                w(c2732n, str4);
                s(c2732n, str4, "#.000", null);
                return;
            case "publicScript-activeTradeValue":
                C2741q c2741qB10 = c2732n.b();
                sp.aicoin_kline.core.indicator.config.F f20 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get("publicScript-activeTradeValue");
                if (f20 == null) {
                    throw new RuntimeException("indicatorConfig not found");
                }
                C7489t c7489t = new C7489t(c2732n, kk.i.a(str4, ".m"), f20);
                String strD10 = c7489t.d();
                if (strD10 == null) {
                    c2741qB10.getClass();
                } else {
                    c2741qB10.f19500h.put(strD10, c7489t);
                }
                C2750t0 c2750t6 = new C2750t0(c2732n, str4);
                c2750t6.M(nk.n.d(f20.q()));
                c2750t6.N(55);
                c2750t6.J(Xj.a.d(16));
                c2750t6.I(Xj.a.d(8));
                c2741qB10.f19499g.put(c2750t6.d(), c2750t6);
                l(c2732n, str4);
                C7395u c7395u2 = new C7395u(c2732n, kk.i.a(str4, ".m"), "publicScript-activeTradeValue");
                c2741qB10.f19501i.put(c7395u2.d(), c7395u2);
                C7394t c7394t2 = new C7394t(c2732n, kk.i.a(str4, ".i"), "publicScript-activeTradeValue");
                c2741qB10.f19501i.put(c7394t2.d(), c7394t2);
                w(c2732n, str4);
                s(c2732n, str4, "#.000", null);
                return;
            case "publicScript-mc":
                C2741q c2741qB11 = c2732n.b();
                sp.aicoin_kline.core.indicator.config.F f21 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get("publicScript-mc");
                if (f21 == null) {
                    throw new RuntimeException("indicatorConfig not found");
                }
                C7492u0 c7492u0 = new C7492u0(c2732n, kk.i.a(str4, ".m"), f21);
                String strD11 = c7492u0.d();
                if (strD11 == null) {
                    c2741qB11.getClass();
                } else {
                    c2741qB11.f19500h.put(strD11, c7492u0);
                }
                C2750t0 c2750t7 = new C2750t0(c2732n, str4);
                c2750t7.M(nk.n.d(f21.q()));
                c2750t7.N(48);
                c2750t7.J(Xj.a.d(16));
                c2750t7.I(Xj.a.d(8));
                c2741qB11.f19499g.put(c2750t7.d(), c2750t7);
                l(c2732n, str4);
                C7395u c7395u3 = new C7395u(c2732n, kk.i.a(str4, ".m"), "publicScript-mc");
                c2741qB11.f19501i.put(c7395u3.d(), c7395u3);
                C7394t c7394t3 = new C7394t(c2732n, kk.i.a(str4, ".i"), "publicScript-mc");
                c2741qB11.f19501i.put(c7394t3.d(), c7394t3);
                w(c2732n, str4);
                s(c2732n, str4, "#.000", null);
                return;
            case "position":
                t(c2732n, str4, str2, false, new O0(c2732n));
                return;
            case "publicScript-positionMc":
                C2741q c2741qB12 = c2732n.b();
                sp.aicoin_kline.core.indicator.config.F f22 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get("publicScript-positionMc");
                if (f22 == null) {
                    throw new RuntimeException("indicatorConfig not found");
                }
                C7453a0 c7453a0 = new C7453a0(c2732n, kk.i.a(str4, ".m"), f22);
                String strD12 = c7453a0.d();
                if (strD12 == null) {
                    c2741qB12.getClass();
                } else {
                    c2741qB12.f19500h.put(strD12, c7453a0);
                }
                C2750t0 c2750t8 = new C2750t0(c2732n, str4);
                c2750t8.M(nk.n.d(f22.q()));
                c2750t8.N(49);
                c2750t8.J(Xj.a.d(16));
                c2750t8.I(Xj.a.d(8));
                c2741qB12.f19499g.put(c2750t8.d(), c2750t8);
                l(c2732n, str4);
                C7395u c7395u4 = new C7395u(c2732n, kk.i.a(str4, ".m"), "publicScript-positionMc");
                c2741qB12.f19501i.put(c7395u4.d(), c7395u4);
                C7394t c7394t4 = new C7394t(c2732n, kk.i.a(str4, ".i"), "publicScript-positionMc");
                c2741qB12.f19501i.put(c7394t4.d(), c7394t4);
                w(c2732n, str4);
                s(c2732n, str4, "#.000", null);
                return;
            case "publicScript-cvdCandle":
                C2741q c2741qB13 = c2732n.b();
                sp.aicoin_kline.core.indicator.config.F f23 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get("publicScript-cvdCandle");
                if (f23 == null) {
                    throw new RuntimeException("indicatorConfig not found");
                }
                C7469i0 c7469i0 = new C7469i0(c2732n, kk.i.a(str4, ".m"), f23);
                String strD13 = c7469i0.d();
                if (strD13 == null) {
                    c2741qB13.getClass();
                } else {
                    c2741qB13.f19500h.put(strD13, c7469i0);
                }
                C2750t0 c2750t9 = new C2750t0(c2732n, str4);
                c2750t9.M(nk.n.d(f23.q()));
                c2750t9.N(47);
                c2750t9.J(Xj.a.d(16));
                c2750t9.I(Xj.a.d(8));
                c2741qB13.f19499g.put(c2750t9.d(), c2750t9);
                l(c2732n, str4);
                C7395u c7395u5 = new C7395u(c2732n, kk.i.a(str4, ".m"), "publicScript-cvdCandle");
                c2741qB13.f19501i.put(c7395u5.d(), c7395u5);
                C7394t c7394t5 = new C7394t(c2732n, kk.i.a(str4, ".i"), "publicScript-cvdCandle");
                c2741qB13.f19501i.put(c7394t5.d(), c7394t5);
                w(c2732n, str4);
                s(c2732n, str4, "#.000", null);
                return;
            case "fundflow":
                q(c2732n, str4, str2, Zj.g.ZERO, Zj.a.POS_NEG, new M0(c2732n));
                return;
            case "stochrsi":
                C2741q c2741qB14 = c2732n.b();
                sp.aicoin_kline.core.indicator.config.F f24 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get("stochrsi");
                if (f24 == null) {
                    throw new RuntimeException("indicatorConfig not found");
                }
                ek.w[] wVarArrL4 = f24.l();
                boolean zD4 = nk.n.d(f24.q());
                gk.O0 o10 = new gk.O0(c2732n, kk.i.a(str4, ".m"), f24);
                String strD14 = o10.d();
                if (strD14 == null) {
                    c2741qB14.getClass();
                } else {
                    c2741qB14.f19500h.put(strD14, o10);
                }
                C2750t0 c2750t10 = new C2750t0(c2732n, str4);
                c2750t10.M(zD4);
                c2750t10.N(4);
                c2750t10.J(Xj.a.d(16));
                c2750t10.I(Xj.a.d(8));
                c2741qB14.f19499g.put(c2750t10.d(), c2750t10);
                l(c2732n, str4);
                Vj.b bVar7 = new Vj.b(c2732n, kk.i.a(str4, ".m"), new AbstractC2744r0[]{new fk.E(p292ng.h.b(wVarArrL4[5].g(), wVarArrL4[4].g()), c2732n, kk.i.a(str4, ".m")), new fk.D(c2732n, kk.i.a(str4, ".m"))});
                c2741qB14.f19501i.put(bVar7.d(), bVar7);
                o(c2732n, str4, null);
                s(c2732n, str4, "#.000", null);
                return;
            default:
                return;
        }
    }

    public static void n(C2732n c2732n, String str, L0 l10, boolean z10) {
        C2741q c2741qB = c2732n.b();
        C2702d c2702d = new C2702d(str);
        c2702d.D(C2702d.a.Data);
        c2702d.F(z10);
        c2741qB.f19496d.put(c2702d.d(), c2702d);
        l10.I(c2702d);
        C2702d c2702d2 = new C2702d(kk.i.a(str, "Range"));
        c2702d2.D(C2702d.a.Range);
        c2702d2.F(z10);
        c2741qB.f19496d.put(c2702d2.d(), c2702d2);
        l10.I(c2702d2);
    }

    public static void o(C2732n c2732n, String str, Integer num) {
        C2741q c2741qB = c2732n.b();
        fk.C c10 = new fk.C(c2732n, kk.i.a(str, ".i"));
        if (num != null) {
            c10.H(num.intValue());
        }
        c2741qB.f19501i.put(c10.d(), c10);
        J0 j10 = new J0(c2732n, kk.i.a(str, ".sub_reversal_tip"));
        c2741qB.f19501i.put(j10.d(), j10);
        F0 f10 = new F0(c2732n, kk.i.a(str, ".s"));
        c2741qB.f19501i.put(f10.d(), f10);
        K k10 = new K(c2732n, kk.i.a(str, ".d"));
        c2741qB.f19501i.put(k10.d(), k10);
    }

    public static void p(C2732n c2732n, String str, String str2, float f10, boolean z10) {
        C2741q c2741qB = c2732n.b();
        if (z10) {
            y1 y1Var = new y1(c2732n, str);
            if (f10 >= 0.0f) {
                y1.R(y1Var, f10, 0.0f, 2, null);
            }
            c2741qB.f19497e.put(y1Var.d(), y1Var);
        } else {
            y1 y1VarM = c2741qB.m(str);
            if (f10 > 0.0f && y1VarM != null) {
                y1.R(y1VarM, f10, 0.0f, 2, null);
                y1VarM.P();
            }
        }
        C1 c10 = new C1(c2732n, str);
        c10.i();
        c2741qB.f19504l = c10;
        z1 z1Var = new z1(c2732n, kk.i.a(str2, ".b"));
        c2741qB.f19501i.put(z1Var.d(), z1Var);
        B1 b10 = new B1(c2732n, kk.i.a(str2, ".m"));
        c2741qB.f19501i.put(b10.d(), b10);
        D1 d10 = new D1(c2732n, kk.i.a(str2, ".s"));
        c2741qB.f19501i.put(d10.d(), d10);
    }

    /* JADX WARN: Code duplicated, block: B:40:0x0108  */
    /* JADX WARN: Code duplicated, block: B:42:0x010d  */
    /* JADX WARN: Code duplicated, block: B:48:0x011a  */
    /* JADX WARN: Code duplicated, block: B:51:0x0126  */
    /* JADX WARN: Code duplicated, block: B:53:0x012c  */
    /* JADX WARN: Code duplicated, block: B:54:0x0132  */
    /* JADX WARN: Code restructure failed: missing block: B:50:0x0120, code lost:
    
        r2 = new fk.Z(r20, r9, r24);
     */
    /*
        Code decompiled incorrectly, please refer to instructions dump.
        To view partially-correct add '--show-bad-code' argument
    */
    public static void q(Rj.C2732n r20, java.lang.String r21, java.lang.String r22, Zj.g r23, Zj.a r24, p146gg.o r25) {
        /*
            Method dump skipped, instruction units count: 373
            To view this dump add '--comments-level debug' option
        */
        throw new UnsupportedOperationException("Method not decompiled: Rj.C2757v1.q(Rj.n, java.lang.String, java.lang.String, Zj.g, Zj.a, gg.o):void");
    }

    public static void r(C2732n c2732n, String str, String str2, p146gg.o oVar) {
        C2741q c2741qB = c2732n.b();
        sp.aicoin_kline.core.indicator.config.F f10 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get(str2);
        if (f10 == null) {
            throw new RuntimeException("indicatorConfig not found");
        }
        boolean zD = nk.n.d(f10.q());
        AbstractC2755v abstractC2755v = (AbstractC2755v) oVar.invoke(str + ".m", f10);
        String strD = abstractC2755v.d();
        if (strD == null) {
            c2741qB.getClass();
        } else {
            c2741qB.f19500h.put(strD, abstractC2755v);
        }
        C2750t0 c2750t0 = new C2750t0(c2732n, str);
        c2750t0.M(zD);
        c2750t0.N(21);
        c2750t0.J(Xj.a.d(16));
        c2750t0.I(Xj.a.d(8));
        c2741qB.f19499g.put(c2750t0.d(), c2750t0);
        l(c2732n, str);
        fk.D d10 = new fk.D(c2732n, kk.i.a(str, ".m"));
        c2741qB.f19501i.put(d10.d(), d10);
        fk.C c10 = new fk.C(c2732n, kk.i.a(str, ".i"));
        c10.H(4);
        c2741qB.f19501i.put(c10.d(), c10);
        w(c2732n, str);
        s(c2732n, str, "#.000", 4);
    }

    public static void s(C2732n c2732n, String str, String str2, Integer num) {
        C2741q c2741qB = c2732n.b();
        String strA = kk.i.a(str, "Range");
        C2766z0 c2766z0 = new C2766z0(c2732n, kk.i.a(strA, ".b"));
        c2741qB.f19501i.put(c2766z0.d(), c2766z0);
        B0 b10 = new B0(c2732n, kk.i.a(strA, ".m"));
        if (str2 != null) {
            b10.y(new DecimalFormat(str2));
        }
        c2741qB.f19501i.put(b10.d(), b10);
        M m10 = new M(c2732n, kk.i.a(strA, ".hd"));
        if (num != null) {
            m10.A(num.intValue());
        }
        c2741qB.f19501i.put(m10.d(), m10);
    }

    public static void t(C2732n c2732n, String str, String str2, boolean z10, p146gg.o oVar) {
        C2741q c2741qB = c2732n.b();
        sp.aicoin_kline.core.indicator.config.F f10 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get(str2);
        if (f10 == null) {
            throw new RuntimeException("indicatorConfig not found");
        }
        AbstractC2755v abstractC2755v = (AbstractC2755v) oVar.invoke(str + ".m", f10);
        String strD = abstractC2755v.d();
        if (strD == null) {
            c2741qB.getClass();
        } else {
            c2741qB.f19500h.put(strD, abstractC2755v);
        }
        C2750t0 c2750t0 = new C2750t0(c2732n, str);
        c2750t0.N(f10.q());
        c2750t0.M(nk.n.d(f10.q()));
        c2750t0.J(Xj.a.d(16));
        c2750t0.I(Xj.a.d(8));
        c2741qB.f19499g.put(c2750t0.d(), c2750t0);
        l(c2732n, str);
        fk.D d10 = new fk.D(c2732n, kk.i.a(str, ".m"));
        d10.w(z10);
        c2741qB.f19501i.put(d10.d(), d10);
        fk.C c10 = new fk.C(c2732n, kk.i.a(str, ".i"));
        c10.G(z10);
        c2741qB.f19501i.put(c10.d(), c10);
        w(c2732n, str);
        s(c2732n, str, "#.000", null);
    }

    /* JADX WARN: Can't fix incorrect switch cases order, some code will duplicate */
    /* JADX WARN: Code duplicated, block: B:51:0x00fd  */
    /* JADX WARN: Code duplicated, block: B:66:0x0148  */
    public static void u(C2732n c2732n, String str, List list, HashMap map) {
        AbstractC2744r0 c7383h;
        C2741q c2741qB = c2732n.b();
        boolean zJ = C2760w1.f19594a.j();
        ArrayList arrayList = new ArrayList();
        boolean zF = nk.n.f(19);
        int size = list.size();
        for (int i10 = 0; i10 < size; i10++) {
            String str2 = (String) list.get(i10);
            if (AbstractC7609s.f(str2, "ai_large_order")) {
                C7377b c7377b = new C7377b(c2732n, kk.i.a(str, ".a"));
                c7377b.s(zF);
                AbstractC2755v abstractC2755v = (AbstractC2755v) map.get(str2);
                if (abstractC2755v != null) {
                    c7377b.r(abstractC2755v);
                }
                if (!AbstractC7609s.f(KLineManager.f142490O.a().u().get(str2), Boolean.FALSE)) {
                    c2741qB.f19502j.put(c7377b.d(), c7377b);
                }
            } else {
                switch (str2) {
                    case "ai_srl":
                        c7383h = new C7383h(c2732n, kk.i.a(str, ".a"));
                        break;
                    case "main_script_indicator":
                        c7383h = new fk.U(c2732n, kk.i.a(str, ".a"));
                        break;
                    case "ichimoku":
                        c7383h = new fk.A(c2732n, kk.i.a(str, ".a"), ".a");
                        break;
                    case "ai_large_trade":
                        c7383h = new C7379d(c2732n, kk.i.a(str, ".a"));
                        break;
                    case "dc":
                    case "kc":
                    case "ma":
                        c7383h = new fk.D(c2732n, kk.i.a(str, ".a"), ".a");
                        break;
                    case "td":
                        c7383h = new K0(c2732n, kk.i.a(str, ".a"));
                        break;
                    case "bbi":
                    case "ema":
                    case "ene":
                        c7383h = new fk.D(c2732n, kk.i.a(str, ".a"), ".a");
                        break;
                    case "sar":
                        c7383h = new D0(c2732n, kk.i.a(str, ".a"));
                        break;
                    case "boll":
                    case "alligator":
                        c7383h = new fk.D(c2732n, kk.i.a(str, ".a"), ".a");
                        break;
                    case "ai_win_rate":
                        c7383h = new C7388m(c2732n, kk.i.a(str, ".a"));
                        break;
                    default:
                        c7383h = null;
                        break;
                }
                if (c7383h != null) {
                    c7383h.s(zF);
                    AbstractC2755v abstractC2755v2 = (AbstractC2755v) map.get(str2);
                    if (abstractC2755v2 != null) {
                        c7383h.r(abstractC2755v2);
                    }
                    if (!zJ) {
                        arrayList.add(c7383h);
                    } else if (!AbstractC7609s.f(KLineManager.f142490O.a().u().get(str2), Boolean.FALSE)) {
                        arrayList.add(new C2752u(c2732n, c7383h));
                    }
                }
            }
        }
        arrayList.add(new C6303b(c2732n, kk.i.a(str, ".a")));
        Vj.b bVar = new Vj.b(c2732n, kk.i.a(str, ".a"), (AbstractC2744r0[]) arrayList.toArray(new AbstractC2744r0[0]));
        c2741qB.f19501i.put(bVar.d(), bVar);
    }

    public static final AbstractC2755v v(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new gk.Y0(c2732n, str, f10);
    }

    public static void w(C2732n c2732n, String str) {
        C2741q c2741qB = c2732n.b();
        J0 j10 = new J0(c2732n, kk.i.a(str, ".sub_reversal_tip"));
        c2741qB.f19501i.put(j10.d(), j10);
        F0 f10 = new F0(c2732n, kk.i.a(str, ".s"));
        c2741qB.f19501i.put(f10.d(), f10);
        K k10 = new K(c2732n, kk.i.a(str, ".d"));
        c2741qB.f19501i.put(k10.d(), k10);
    }

    public static void x(C2732n c2732n, String str, String str2, p146gg.o oVar) {
        C2741q c2741qB = c2732n.b();
        sp.aicoin_kline.core.indicator.config.F f10 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get(str2);
        if (f10 == null) {
            throw new RuntimeException("indicatorConfig not found");
        }
        AbstractC2755v abstractC2755v = (AbstractC2755v) oVar.invoke(str + ".m", f10);
        String strD = abstractC2755v.d();
        if (strD == null) {
            c2741qB.getClass();
        } else {
            c2741qB.f19500h.put(strD, abstractC2755v);
        }
        C2750t0 c2750t0 = new C2750t0(c2732n, str);
        c2750t0.M(nk.n.d(f10.q()));
        c2750t0.N(f10.q());
        c2750t0.J(Xj.a.d(16));
        c2750t0.I(Xj.a.d(8));
        c2750t0.H(true);
        c2741qB.f19499g.put(c2750t0.d(), c2750t0);
        l(c2732n, str);
        Vj.b bVar = new Vj.b(c2732n, kk.i.a(str, ".m"), new AbstractC2744r0[]{new fk.a0(new double[]{0.0d}, c2732n, kk.i.a(str, ".m")), new fk.D(c2732n, kk.i.a(str, ".m"))});
        c2741qB.f19501i.put(bVar.d(), bVar);
        o(c2732n, str, 6);
        s(c2732n, str, "#." + Ah.x.E("0", 6), 6);
    }

    public static final AbstractC2755v y(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        return new gk.D0(c2732n, str, f10);
    }

    public static void z(C2732n c2732n, String str) {
        C2741q c2741qB = c2732n.b();
        sp.aicoin_kline.core.indicator.config.F f10 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get("publicScript-activeTradeVolume");
        if (f10 == null) {
            throw new RuntimeException("indicatorConfig not found");
        }
        C7493v c7493v = new C7493v(c2732n, kk.i.a(str, ".m"), f10);
        String strD = c7493v.d();
        if (strD == null) {
            c2741qB.getClass();
        } else {
            c2741qB.f19500h.put(strD, c7493v);
        }
        C2750t0 c2750t0 = new C2750t0(c2732n, str);
        c2750t0.M(nk.n.d(f10.q()));
        c2750t0.N(56);
        c2750t0.J(Xj.a.d(16));
        c2750t0.I(Xj.a.d(8));
        c2741qB.f19499g.put(c2750t0.d(), c2750t0);
        l(c2732n, str);
        C7395u c7395u = new C7395u(c2732n, kk.i.a(str, ".m"), "publicScript-activeTradeVolume");
        c2741qB.f19501i.put(c7395u.d(), c7395u);
        C7394t c7394t = new C7394t(c2732n, kk.i.a(str, ".i"), "publicScript-activeTradeVolume");
        c2741qB.f19501i.put(c7394t.d(), c7394t);
        w(c2732n, str);
        s(c2732n, str, "#.000", null);
    }

    public final void A(C2732n c2732n, String str, String str2) {
        C2741q c2741qB = c2732n.b();
        C2765z c2765z = str2 == null ? null : (C2765z) c2741qB.f19495c.get(str2);
        if (c2765z == null) {
            c2741qB.getClass();
            c2765z = new C2765z(str2);
            if (str2 != null) {
                c2741qB.f19495c.put(str2, c2765z);
            }
        }
        if (str != null) {
            c2741qB.f19494b.put(str, c2765z);
        }
        c2741qB.y(str, null);
    }

    /* JADX WARN: Code duplicated, block: B:47:0x0152  */
    public final void B(C2732n c2732n, String str, L0 l10, boolean z10) {
        List list;
        AbstractC2744r0 c10;
        String str2 = str + ".main";
        int i10 = 0;
        n(c2732n, str2, l10, false);
        C2741q c2741qB = c2732n.b();
        x1 x1Var = new x1(c2732n, kk.i.a(str2, ".m"));
        String strD = x1Var.d();
        if (strD == null) {
            c2741qB.getClass();
        } else {
            c2741qB.f19500h.put(strD, x1Var);
        }
        List listF = C2760w1.f19594a.f();
        HashMap mapK = k(c2732n, str2, listF);
        boolean zF = nk.n.f(19);
        C2750t0 c2750t0 = new C2750t0(c2732n, str2);
        c2750t0.M(zF);
        c2750t0.J(Xj.a.d(40));
        c2750t0.I(Xj.a.d(8));
        c2741qB.f19499g.put(c2750t0.d(), c2750t0);
        l(c2732n, str2);
        C2717i c2717i = new C2717i(c2732n, kk.i.a(str2, ".m"), zF);
        c2741qB.f19501i.put(c2717i.d(), c2717i);
        u(c2732n, str2, listF, mapK);
        C2712g0 c2712g0 = new C2712g0(c2732n, kk.i.a(str2, ".d"));
        c2741qB.f19501i.put(c2712g0.d(), c2712g0);
        AbstractC2755v abstractC2755v = (AbstractC2755v) mapK.get("ai_handle_line");
        if (abstractC2755v != null) {
            c2732n.b();
            C7376a c7376a = new C7376a(c2732n, kk.i.a(str2, ".handle_line"));
            c7376a.r(abstractC2755v);
            c2741qB.f19501i.put(c7376a.d(), c7376a);
        }
        String strA = kk.i.a(str2, ".i");
        C2741q c2741qB2 = c2732n.b();
        C2706e0 c2706e0 = new C2706e0(c2732n, strA);
        ArrayList arrayList = new ArrayList();
        arrayList.add(c2706e0);
        int size = listF.size();
        int i11 = 0;
        while (i11 < size) {
            String str3 = (String) listF.get(i11);
            switch (str3.hashCode()) {
                case -1323717279:
                    list = listF;
                    c10 = !str3.equals("main_script_indicator") ? null : new fk.S(c2732n, strA);
                    break;
                case -942198617:
                    if (!str3.equals("ichimoku")) {
                        list = listF;
                    } else {
                        list = listF;
                        c10 = new fk.C(c2732n, strA, ".a");
                    }
                    break;
                case 3199:
                    if (!str3.equals(DublinCore.PREFIX_DC)) {
                        list = listF;
                    } else {
                        list = listF;
                        c10 = new fk.C(c2732n, strA, ".a");
                    }
                    break;
                case 3416:
                    if (!str3.equals("kc")) {
                        list = listF;
                    } else {
                        list = listF;
                        c10 = new fk.C(c2732n, strA, ".a");
                    }
                    break;
                case 3476:
                    if (!str3.equals("ma")) {
                        list = listF;
                    } else {
                        list = listF;
                        c10 = new fk.C(c2732n, strA, ".a");
                    }
                    break;
                case 3696:
                    if (!str3.equals("td")) {
                        list = listF;
                    } else {
                        list = listF;
                        c10 = new fk.C(c2732n, strA, ".a");
                    }
                    break;
                case 97321:
                    if (!str3.equals("bbi")) {
                        list = listF;
                    } else {
                        list = listF;
                        c10 = new fk.C(c2732n, strA, ".a");
                    }
                    break;
                case 100537:
                    if (!str3.equals("ema")) {
                        list = listF;
                    } else {
                        list = listF;
                        c10 = new fk.C(c2732n, strA, ".a");
                    }
                    break;
                case 100572:
                    if (!str3.equals("ene")) {
                        list = listF;
                    } else {
                        list = listF;
                        c10 = new fk.C(c2732n, strA, ".a");
                    }
                    break;
                case 113636:
                    if (!str3.equals("sar")) {
                        list = listF;
                    } else {
                        list = listF;
                        c10 = new fk.C(c2732n, strA, ".a");
                    }
                    break;
                case 3029645:
                    if (!str3.equals("boll")) {
                        list = listF;
                    } else {
                        list = listF;
                        c10 = new fk.C(c2732n, strA, ".a");
                    }
                    break;
                case 185869397:
                    if (!str3.equals("alligator")) {
                        list = listF;
                    } else {
                        list = listF;
                        c10 = new fk.C(c2732n, strA, ".a");
                    }
                    break;
                default:
                    list = listF;
                    break;
            }
            if (c10 != null) {
                AbstractC2755v abstractC2755v2 = (AbstractC2755v) mapK.get(str3);
                if (abstractC2755v2 != null) {
                    c10.r(abstractC2755v2);
                }
                arrayList.add(new C2752u(c2732n, c10));
            }
            i11++;
            listF = list;
            i10 = 0;
        }
        Vj.a aVar = new Vj.a(c2732n, strA, (AbstractC2744r0[]) arrayList.toArray(new AbstractC2744r0[i10]));
        c2741qB2.f19501i.put(aVar.d(), aVar);
        F0 f10 = new F0(c2732n, kk.i.a(str2, ".s"));
        c2741qB.f19501i.put(f10.d(), f10);
        String str4 = str2 + "Range";
        C2766z0 c2766z0 = new C2766z0(c2732n, kk.i.a(str4, ".b"));
        c2741qB.f19501i.put(c2766z0.d(), c2766z0);
        B0 b10 = new B0(c2732n, kk.i.a(str4, ".m"));
        b10.x(true);
        c2741qB.f19501i.put(b10.d(), b10);
        C0 c11 = new C0(c2732n, kk.i.a(str4, ".d"));
        c2741qB.f19501i.put(c11.d(), c11);
        M m10 = new M(c2732n, kk.i.a(str4, ".hd"));
        c2741qB.f19501i.put(m10.d(), m10);
        N(c2732n, str2);
        List listE = C2760w1.f19594a.e();
        int size2 = listE.size();
        while (i10 < size2) {
            m(c2732n, str, l10, (String) listE.get(i10), ".indic" + i10);
            i10++;
        }
        p(c2732n, str, kk.i.a(str, ".mainTimeline"), C2760w1.f19594a.i(), z10);
        C2741q c2741qB3 = c2732n.b();
        G g10 = new G(c2732n, str);
        c2741qB3.f19498f.put(g10.d(), g10);
    }

    public final void C(C2732n c2732n, String str, L0 l10, boolean z10) {
        AbstractC2759w0 c2750t0;
        n(c2732n, str + ".main", l10, true);
        String str2 = str + ".main";
        C2741q c2741qB = c2732n.b();
        int iQ = KLineManager.f142490O.a().q(6);
        ik.b bVar = new ik.b(c2732n, kk.i.a(str2, ".m"));
        bVar.u(ik.f.f98589a.c(iQ));
        String strD = bVar.d();
        if (strD == null) {
            c2741qB.getClass();
        } else {
            c2741qB.f19500h.put(strD, bVar);
        }
        if (iQ == 1) {
            c2750t0 = new C2750t0(c2732n, str2);
        } else {
            W1 w10 = new W1(c2732n, str2);
            w10.X(3.0d);
            c2750t0 = w10;
        }
        c2750t0.J(Xj.a.d(50));
        c2750t0.I(Xj.a.d(28));
        c2741qB.f19499g.put(c2750t0.d(), c2750t0);
        l(c2732n, str2);
        ik.a aVar = new ik.a(c2732n, kk.i.a(str2, ".m"));
        aVar.v(iQ == 0);
        c2741qB.f19501i.put(aVar.d(), aVar);
        C2730m0 c2730m0 = new C2730m0(c2732n, kk.i.a(str2, ".s"));
        c2730m0.x(false);
        c2741qB.f19501i.put(c2730m0.d(), c2730m0);
        String str3 = str2 + "Range";
        C2766z0 c2766z0 = new C2766z0(c2732n, kk.i.a(str3, ".b"));
        c2741qB.f19501i.put(c2766z0.d(), c2766z0);
        ik.c cVar = new ik.c(c2732n, kk.i.a(str3, ".m"));
        cVar.y(new DecimalFormat("0.00%"));
        c2741qB.f19501i.put(cVar.d(), cVar);
        if (iQ == 0) {
            V1 v10 = new V1(c2732n, kk.i.a(str3, ".d"));
            v10.v(new DecimalFormat("0.00%"));
            c2741qB.f19501i.put(v10.d(), v10);
        }
        String strA = kk.i.a(str, ".main");
        C2741q c2741qB2 = c2732n.b();
        C2702d c2702d = new C2702d(kk.i.a(strA, "Timeline"));
        c2702d.D(C2702d.a.Timeline);
        c2741qB2.f19496d.put(c2702d.d(), c2702d);
        l10.I(c2702d);
        float fI = C2760w1.f19594a.i();
        if (z10) {
            C2736o0 c2736o0 = new C2736o0(c2732n, str);
            if (fI >= 0.0f) {
                y1.R(c2736o0, fI, 0.0f, 2, null);
            }
            c2741qB.f19497e.put(c2736o0.d(), c2736o0);
        } else {
            y1 y1VarM = c2741qB.m(str);
            if (fI > 0.0f && y1VarM != null) {
                y1.R(y1VarM, fI, 0.0f, 2, null);
                y1VarM.P();
            }
        }
        String strA2 = kk.i.a(str, ".mainTimeline");
        z1 z1Var = new z1(c2732n, kk.i.a(strA2, ".b"));
        c2741qB.f19501i.put(z1Var.d(), z1Var);
        ik.d dVar = new ik.d(c2732n, kk.i.a(strA2, ".m"));
        c2741qB.f19501i.put(dVar.d(), dVar);
        ik.e eVar = new ik.e(c2732n, kk.i.a(strA2, ".s"));
        c2741qB.f19501i.put(eVar.d(), eVar);
        C2741q c2741qB3 = c2732n.b();
        G g10 = new G(c2732n, str);
        c2741qB3.f19498f.put(g10.d(), g10);
    }

    /* JADX WARN: Code duplicated, block: B:110:0x03b3 A[PHI: r24
      0x03b3: PHI (r24v15 java.util.List) = 
      (r24v3 java.util.List)
      (r24v5 java.util.List)
      (r24v6 java.util.List)
      (r24v7 java.util.List)
      (r24v8 java.util.List)
      (r24v9 java.util.List)
      (r24v10 java.util.List)
      (r24v11 java.util.List)
      (r24v12 java.util.List)
      (r24v13 java.util.List)
      (r24v16 java.util.List)
     binds: [B:108:0x03b0, B:101:0x0396, B:98:0x038b, B:95:0x0380, B:92:0x0377, B:89:0x036c, B:86:0x0360, B:83:0x0354, B:80:0x0348, B:77:0x033c, B:70:0x031d] A[DONT_GENERATE, DONT_INLINE]] */
    /* JADX WARN: Code duplicated, block: B:113:0x03c4 A[PHI: r24
      0x03c4: PHI (r24v19 java.util.List) = 
      (r24v2 java.util.List)
      (r24v3 java.util.List)
      (r24v4 java.util.List)
      (r24v5 java.util.List)
      (r24v6 java.util.List)
      (r24v7 java.util.List)
      (r24v8 java.util.List)
      (r24v9 java.util.List)
      (r24v10 java.util.List)
      (r24v11 java.util.List)
      (r24v12 java.util.List)
      (r24v13 java.util.List)
      (r24v14 java.util.List)
      (r24v16 java.util.List)
      (r24v20 java.util.List)
     binds: [B:112:0x03c2, B:108:0x03b0, B:104:0x039f, B:101:0x0396, B:98:0x038b, B:95:0x0380, B:92:0x0377, B:89:0x036c, B:86:0x0360, B:83:0x0354, B:80:0x0348, B:77:0x033c, B:73:0x0329, B:70:0x031d, B:64:0x02ff] A[DONT_GENERATE, DONT_INLINE]] */
    public final void D(C2732n c2732n, String str, L0 l10, boolean z10) {
        C2760w1 c2760w1;
        AbstractC2759w0 c2750t0;
        AbstractC2744r0 c2717i;
        String str2;
        List list;
        AbstractC2744r0 s10;
        String str3 = str + ".main";
        if (nk.n.f(4)) {
            C2741q c2741qB = c2732n.b();
            C2724k0 c2724k0 = new C2724k0(c2732n, kk.i.a(str3, ".msk"));
            String strD = c2724k0.d();
            if (strD == null) {
                c2741qB.getClass();
            } else {
                c2741qB.f19500h.put(strD, c2724k0);
            }
            C2752u c2752u = new C2752u(c2732n, new C2727l0(c2732n, kk.i.a(str3, ".msk")));
            c2741qB.f19501i.put(c2752u.d(), c2752u);
        }
        n(c2732n, str3, l10, true);
        C2741q c2741qB2 = c2732n.b();
        C2702d c2702d = new C2702d(kk.i.a(str3, "Timeline"));
        c2702d.D(C2702d.a.Timeline);
        c2741qB2.f19496d.put(c2702d.d(), c2702d);
        l10.I(c2702d);
        C2741q c2741qB3 = c2732n.b();
        x1 x1Var = new x1(c2732n, kk.i.a(str3, ".m"));
        String strD2 = x1Var.d();
        if (strD2 == null) {
            c2741qB3.getClass();
        } else {
            c2741qB3.f19500h.put(strD2, x1Var);
        }
        C2760w1 c2760w2 = C2760w1.f19594a;
        boolean zJ = c2760w2.j();
        List listF = zJ ? c2760w2.f() : Sf.r.t("ma");
        HashMap mapK = k(c2732n, str3, listF);
        KLineManager.a aVar = KLineManager.f142490O;
        String strK = aVar.a().K();
        int iQ = aVar.a().q(11);
        boolean zF = nk.n.f(19);
        if (AbstractC7609s.f(strK, "default")) {
            c2760w1 = c2760w2;
            c2750t0 = iQ != 1 ? iQ != 2 ? new C2750t0(c2732n, str3) : new C2742q0(c2732n, str3) : new C2694a0(c2732n, str3);
        } else {
            c2760w1 = c2760w2;
            c2750t0 = (AbstractC7609s.f(strK, "spread") && iQ == 2) ? new C2742q0(c2732n, str3) : new C2750t0(c2732n, str3);
        }
        c2750t0.M(zF);
        c2750t0.J(Xj.a.d(40));
        c2750t0.I(Xj.a.d(8));
        c2741qB3.f19499g.put(c2750t0.d(), c2750t0);
        l(c2732n, str3);
        AbstractC2755v abstractC2755v = (AbstractC2755v) mapK.get("liqheatmap");
        boolean zF2 = AbstractC7609s.f(aVar.a().u().get("liqheatmap"), Boolean.FALSE);
        if (abstractC2755v != null && !zF2) {
            C7399y c7399y = new C7399y(c2732n, kk.i.a(str3, ".heat_liquidation"));
            c7399y.r(abstractC2755v);
            c2741qB3.f19501i.put(c7399y.d(), c7399y);
            C7397w c7397w = new C7397w(c2732n, kk.i.a(str3, ".heat_liquidation_window"));
            c7397w.r(abstractC2755v);
            c2741qB3.f19501i.put(c7397w.d(), c7397w);
        }
        if (zJ) {
            c2717i = new C2717i(c2732n, kk.i.a(str3, ".m"), zF);
        } else {
            c2717i = new bk.a(c2732n, kk.i.a(str3, ".m"));
            c2717i.s(zF);
        }
        c2741qB3.f19501i.put(c2717i.d(), c2717i);
        u(c2732n, str3, listF, mapK);
        C2741q c2741qB4 = c2732n.b();
        boolean zJ2 = c2760w1.j();
        boolean zF3 = nk.n.f(19);
        ArrayList arrayList = new ArrayList();
        ArrayList arrayList2 = new ArrayList();
        if (aVar.a().q(25) == 1) {
            gk.L0 l11 = new gk.L0(c2732n, kk.i.a(str3, ".mrk"));
            arrayList2.add(l11);
            AbstractC2744r0 x10 = new fk.X(c2732n, kk.i.a(str3, ".mrk"));
            x10.r(l11);
            x10.s(zF3);
            if (zJ2) {
                x10 = new C2752u(c2732n, x10);
            }
            arrayList.add(x10);
        }
        Tj.a aVar2 = new Tj.a(c2732n, kk.i.a(str3, ".mrk"), (AbstractC2755v[]) arrayList2.toArray(new AbstractC2755v[0]));
        String strD3 = aVar2.d();
        if (strD3 == null) {
            c2741qB4.getClass();
        } else {
            c2741qB4.f19500h.put(strD3, aVar2);
        }
        Vj.b bVar = new Vj.b(c2732n, kk.i.a(str3, ".mrk"), (AbstractC2744r0[]) arrayList.toArray(new AbstractC2744r0[0]));
        c2741qB4.f19501i.put(bVar.d(), bVar);
        C2712g0 c2712g0 = new C2712g0(c2732n, kk.i.a(str3, ".d"));
        c2741qB3.f19501i.put(c2712g0.d(), c2712g0);
        AbstractC2755v abstractC2755v2 = (AbstractC2755v) mapK.get("ai_handle_line");
        if (abstractC2755v2 != null) {
            c2732n.b();
            C7376a c7376a = new C7376a(c2732n, kk.i.a(str3, ".handle_line"));
            c7376a.r(abstractC2755v2);
            c2741qB3.f19501i.put(c7376a.d(), c7376a);
        }
        AbstractC2755v abstractC2755v3 = (AbstractC2755v) mapK.get("main_alert_line");
        if (abstractC2755v3 != null) {
            c2732n.b();
            C7393s c7393s = new C7393s(c2732n, kk.i.a(str3, ".alert_line"));
            c7393s.r(abstractC2755v3);
            c2741qB3.f19501i.put(c7393s.d(), c7393s);
        }
        AbstractC2755v abstractC2755v4 = (AbstractC2755v) mapK.get("main_liqui_line");
        if (abstractC2755v4 != null) {
            c2732n.b();
            fk.J j10 = new fk.J(c2732n, kk.i.a(str3, ".liqui_line"));
            j10.r(abstractC2755v4);
            c2741qB3.f19501i.put(j10.d(), j10);
        }
        String strA = kk.i.a(str3, ".i");
        C2741q c2741qB5 = c2732n.b();
        boolean zJ3 = c2760w1.j();
        ArrayList arrayList3 = new ArrayList();
        String str4 = ".i";
        arrayList3.add(new fk.O(c2732n, strA));
        arrayList3.add(new C2711g(c2732n, strA));
        int size = listF.size();
        int i10 = 0;
        while (i10 < size) {
            int i11 = size;
            String str5 = (String) listF.get(i10);
            switch (str5.hashCode()) {
                case -1323717279:
                    list = listF;
                    if (str5.equals("main_script_indicator")) {
                        s10 = new fk.S(c2732n, strA);
                    } else {
                        s10 = null;
                    }
                    break;
                case -942198617:
                    list = listF;
                    if (str5.equals("ichimoku")) {
                        s10 = new fk.C(c2732n, strA, ".a");
                    } else {
                        s10 = null;
                    }
                    break;
                case -387915688:
                    list = listF;
                    if (str5.equals("liqheatmap")) {
                        s10 = new C7396v(c2732n, strA);
                    } else {
                        s10 = null;
                    }
                    break;
                case 3199:
                    list = listF;
                    if (str5.equals(DublinCore.PREFIX_DC)) {
                        s10 = new fk.C(c2732n, strA, ".a");
                    } else {
                        s10 = null;
                    }
                    break;
                case 3416:
                    list = listF;
                    if (str5.equals("kc")) {
                        s10 = new fk.C(c2732n, strA, ".a");
                    } else {
                        s10 = null;
                    }
                    break;
                case 3476:
                    list = listF;
                    if (str5.equals("ma")) {
                        s10 = new fk.C(c2732n, strA, ".a");
                    } else {
                        s10 = null;
                    }
                    break;
                case 3696:
                    list = listF;
                    if (str5.equals("td")) {
                        s10 = new fk.C(c2732n, strA, ".a");
                    } else {
                        s10 = null;
                    }
                    break;
                case 97321:
                    list = listF;
                    if (str5.equals("bbi")) {
                        s10 = new fk.C(c2732n, strA, ".a");
                    } else {
                        s10 = null;
                    }
                    break;
                case 100537:
                    list = listF;
                    if (str5.equals("ema")) {
                        s10 = new fk.C(c2732n, strA, ".a");
                    } else {
                        s10 = null;
                    }
                    break;
                case 100572:
                    list = listF;
                    if (str5.equals("ene")) {
                        s10 = new fk.C(c2732n, strA, ".a");
                    } else {
                        s10 = null;
                    }
                    break;
                case 113636:
                    list = listF;
                    if (str5.equals("sar")) {
                        s10 = new fk.C(c2732n, strA, ".a");
                    } else {
                        s10 = null;
                    }
                    break;
                case 3029645:
                    list = listF;
                    if (str5.equals("boll")) {
                        s10 = new fk.C(c2732n, strA, ".a");
                    } else {
                        s10 = null;
                    }
                    break;
                case 3626742:
                    list = listF;
                    if (str5.equals("vpvr")) {
                        s10 = new fk.e0(c2732n, strA);
                    } else {
                        s10 = null;
                    }
                    break;
                case 185869397:
                    list = listF;
                    if (str5.equals("alligator")) {
                        s10 = new fk.C(c2732n, strA, ".a");
                    } else {
                        s10 = null;
                    }
                    break;
                case 1600886170:
                    if (str5.equals("ai_win_rate")) {
                        s10 = new fk.g0(c2732n, strA);
                        list = listF;
                        break;
                    }
                default:
                    list = listF;
                    s10 = null;
                    break;
            }
            if (s10 != null) {
                AbstractC2755v abstractC2755v5 = (AbstractC2755v) mapK.get(str5);
                if (abstractC2755v5 != null) {
                    s10.r(abstractC2755v5);
                }
                if (zJ3) {
                    arrayList3.add(new C2752u(c2732n, s10));
                } else {
                    arrayList3.add(s10);
                }
            }
            i10++;
            listF = list;
            size = i11;
        }
        if (nk.n.f(25)) {
            H0 h10 = new H0(c2732n, strA);
            if (zJ3) {
                arrayList3.add(new C2752u(c2732n, h10));
            } else {
                arrayList3.add(h10);
            }
        }
        Vj.a aVar3 = new Vj.a(c2732n, strA, (AbstractC2744r0[]) arrayList3.toArray(new AbstractC2744r0[0]));
        c2741qB5.f19501i.put(aVar3.d(), aVar3);
        F0 f10 = new F0(c2732n, kk.i.a(str3, ".s"));
        c2741qB3.f19501i.put(f10.d(), f10);
        E0 e10 = new E0(c2732n, kk.i.a(str3, ".kline_tag"));
        c2741qB3.f19501i.put(e10.d(), e10);
        String str6 = str3 + "Range";
        C2766z0 c2766z0 = new C2766z0(c2732n, kk.i.a(str6, ".b"));
        c2741qB3.f19501i.put(c2766z0.d(), c2766z0);
        B0 b10 = new B0(c2732n, kk.i.a(str6, ".m"));
        b10.x(true);
        c2741qB3.f19501i.put(b10.d(), b10);
        C0 c10 = new C0(c2732n, kk.i.a(str6, ".d"));
        c2741qB3.f19501i.put(c10.d(), c10);
        M m10 = new M(c2732n, kk.i.a(str6, ".hd"));
        c2741qB3.f19501i.put(m10.d(), m10);
        K1 k10 = new K1(c2732n, kk.i.a(str6, ".t"));
        c2741qB3.f19501i.put(k10.d(), k10);
        C2747s0 c2747s0 = new C2747s0(c2732n, kk.i.a(str6, ".handle_line"));
        c2741qB3.f19501i.put(c2747s0.d(), c2747s0);
        AbstractC2755v abstractC2755v6 = (AbstractC2755v) mapK.get("main_liqui_line");
        if (abstractC2755v6 != null) {
            Z z11 = new Z(c2732n, kk.i.a(str6, ".liqui_line"));
            z11.r(abstractC2755v6);
            c2741qB3.f19501i.put(z11.d(), z11);
        }
        E1 e11 = new E1(c2732n, kk.i.a(str6, ".a"), str3);
        c2741qB3.f19501i.put(e11.d(), e11);
        N(c2732n, str3);
        C2760w1 c2760w3 = C2760w1.f19594a;
        List listU1 = Sf.z.u1(c2760w3.e());
        List listH = c2760w3.h();
        c2760w3.a();
        List listG = c2760w3.g();
        int size2 = listU1.size();
        for (int i12 = 0; i12 < size2; i12++) {
            listG.add(new Qf.v(Integer.valueOf(i12), listU1.get(i12), Boolean.FALSE));
        }
        int size3 = listH.size();
        for (int i13 = 0; i13 < size3; i13++) {
            Qf.p pVar = (Qf.p) listH.get(i13);
            int iIntValue = ((Number) pVar.a()).intValue();
            listG.add(p292ng.i.p(iIntValue, 0, listG.size()), new Qf.v(Integer.valueOf(iIntValue), (String) pVar.b(), Boolean.TRUE));
        }
        if (!KLineManager.f142490O.a().P()) {
            int size4 = listG.size();
            int i14 = 0;
            while (i14 < size4) {
                Qf.v vVar = (Qf.v) listG.get(i14);
                int iIntValue2 = ((Number) vVar.a()).intValue();
                String str7 = (String) vVar.b();
                if (((Boolean) vVar.c()).booleanValue()) {
                    Iterator it = listH.iterator();
                    int i15 = 0;
                    while (true) {
                        if (!it.hasNext()) {
                            i15 = -1;
                        } else if (!AbstractC7609s.f(((Qf.p) it.next()).d(), str7)) {
                            i15++;
                        }
                    }
                    if (i15 != -1) {
                        String strA2 = kk.i.a(str, ".script_indic" + i15);
                        C2741q c2741qB6 = c2732n.b();
                        sp.aicoin_kline.core.indicator.config.F f11 = (sp.aicoin_kline.core.indicator.config.F) ek.o.f93330a.b().get("sub_script_indicator");
                        if (f11 != null) {
                            Qf.p pVar2 = (Qf.p) C2760w1.f19594a.h().get(i15);
                            gk.K0 k11 = new gk.K0(c2732n, kk.i.a(strA2, ".m"), f11, (String) pVar2.d());
                            String strD4 = k11.d();
                            if (strD4 == null) {
                                c2741qB6.getClass();
                            } else {
                                c2741qB6.f19500h.put(strD4, k11);
                            }
                            boolean zE = nk.n.e(str7);
                            n(c2732n, strA2, l10, false);
                            fk.V v10 = new fk.V(c2732n, kk.i.a(strA2, ".m"), (String) pVar2.d(), zE);
                            v10.s(zE);
                            F1 f12 = new F1(c2732n, kk.i.a(strA2, ".hd"), strA2);
                            c2741qB6.f19501i.put(f12.d(), f12);
                            C2750t0 c2750t1 = new C2750t0(c2732n, strA2);
                            c2750t1.M(zE);
                            c2750t1.N(45);
                            c2750t1.J(Xj.a.d(16));
                            c2750t1.I(Xj.a.d(8));
                            c2741qB6.f19499g.put(c2750t1.d(), c2750t1);
                            l(c2732n, strA2);
                            c2741qB6.f19501i.put(v10.d(), v10);
                            str2 = str4;
                            fk.T t10 = new fk.T(c2732n, kk.i.a(strA2, str2), (String) pVar2.d(), zE);
                            c2741qB6.f19501i.put(t10.d(), t10);
                            w(c2732n, strA2);
                            s(c2732n, strA2, "#.000", null);
                        }
                    }
                    str2 = str4;
                } else {
                    str2 = str4;
                    m(c2732n, str, l10, str7, ".indic" + iIntValue2);
                }
                i14++;
                str4 = str2;
                size4 = size4;
                listG = listG;
            }
        }
        p(c2732n, str, kk.i.a(str, ".mainTimeline"), C2760w1.f19594a.i(), z10);
        C2741q c2741qB7 = c2732n.b();
        G g10 = new G(c2732n, str);
        c2741qB7.f19498f.put(g10.d(), g10);
        C2741q c2741qB8 = c2732n.b();
        fk.G g11 = new fk.G(c2732n, kk.i.a(str3, ".window"));
        c2741qB8.f19501i.put(g11.d(), g11);
    }

    public final void V(C2732n c2732n, String str, String str2, String str3) {
        int iHashCode = str.hashCode();
        if (iHashCode != -1081267614) {
            if (iHashCode != -895684237) {
                if (iHashCode != 1171402247) {
                    if (iHashCode == 1544803905 && str.equals("default")) {
                        E.f19079a.a(c2732n, str2, str3);
                        return;
                    }
                } else if (str.equals("parallel")) {
                    C2733n0.f19484a.a(c2732n, str2, str3);
                    return;
                }
            } else if (str.equals("spread")) {
                I0.f19147a.a(c2732n, str2, str3);
                return;
            }
        } else if (str.equals("master")) {
            C2709f0.f19383a.a(c2732n, str2, str3);
            return;
        }
        E.f19079a.a(c2732n, str2, str3);
    }
}
