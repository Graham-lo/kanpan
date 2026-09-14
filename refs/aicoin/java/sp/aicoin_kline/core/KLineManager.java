package sp.aicoin_kline.core;

import Ah.w;
import Ah.y;
import Qf.H;
import Rj.C2741q;
import Rj.C2760w1;
import Sf.AbstractC2804s;
import Sf.N;
import Sf.r;
import Sf.z;
import android.content.Context;
import android.content.SharedPreferences;
import androidx.p022lifecycle.MutableLiveData;
import com.google.gson.Gson;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import kotlin.jvm.functions.Function1;
import kotlin.jvm.internal.DefaultConstructorMarker;
import nk.o;
import p167hg.AbstractC7609s;
import p167hg.C7607p;
import p292ng.i;
import sp.aicoin_kline.chart.Chart;

/* JADX INFO: loaded from: classes7.dex */
public final class KLineManager {

    /* JADX INFO: renamed from: O, reason: collision with root package name */
    public static final a f142490O = new a(null);

    /* JADX INFO: renamed from: P, reason: collision with root package name */
    public static final Gson f142491P = new Gson();

    /* JADX INFO: renamed from: Q, reason: collision with root package name */
    public static KLineManager f142492Q;

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public Context f142493A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public boolean f142494B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public boolean f142495C;

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public boolean f142496D;

    /* JADX INFO: renamed from: E, reason: collision with root package name */
    public volatile boolean f142497E;

    /* JADX INFO: renamed from: F, reason: collision with root package name */
    public volatile int f142498F;

    /* JADX INFO: renamed from: G, reason: collision with root package name */
    public boolean f142499G;

    /* JADX INFO: renamed from: H, reason: collision with root package name */
    public boolean f142500H;

    /* JADX INFO: renamed from: I, reason: collision with root package name */
    public boolean f142501I;

    /* JADX INFO: renamed from: J, reason: collision with root package name */
    public boolean f142502J;

    /* JADX INFO: renamed from: K, reason: collision with root package name */
    public boolean f142503K;

    /* JADX INFO: renamed from: L, reason: collision with root package name */
    public boolean f142504L;

    /* JADX INFO: renamed from: M, reason: collision with root package name */
    public final MutableLiveData f142505M;

    /* JADX INFO: renamed from: N, reason: collision with root package name */
    public final MutableLiveData f142506N;

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final Context f142507a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final SharedPreferences f142508b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public boolean f142509c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public boolean f142510d;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public int f142511e;

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public String f142512f;

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public String f142513g;

    /* JADX INFO: renamed from: h, reason: collision with root package name */
    public boolean f142514h;

    /* JADX INFO: renamed from: i, reason: collision with root package name */
    public double f142515i;

    /* JADX INFO: renamed from: j, reason: collision with root package name */
    public String f142516j;

    /* JADX INFO: renamed from: k, reason: collision with root package name */
    public String f142517k;

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public int f142518l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public boolean f142519m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public boolean f142520n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public String f142521o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public boolean f142522p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public boolean f142523q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public boolean f142524r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public boolean f142525s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public boolean f142526t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public double f142527u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public double f142528v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public double f142529w;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public long f142530x;

    /* JADX INFO: renamed from: y, reason: collision with root package name */
    public C2741q f142531y;

    /* JADX INFO: renamed from: z, reason: collision with root package name */
    public Chart f142532z;

    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }

        public final KLineManager a() {
            KLineManager kLineManager = KLineManager.f142492Q;
            if (kLineManager != null) {
                return kLineManager;
            }
            throw new IllegalStateException("Please initialize manager instance first");
        }

        public final void b(Context context) {
            KLineManager.f142492Q = new KLineManager(context.getApplicationContext(), null);
        }
    }

    public /* synthetic */ class b extends C7607p implements Function1 {
        public b(o oVar) {
            super(1, oVar, o.class, "getIndicatorKey", "getIndicatorKey(I)Ljava/lang/String;", 0);
        }

        @Override // kotlin.jvm.functions.Function1
        public /* bridge */ /* synthetic */ Object invoke(Object obj) {
            return t(((Number) obj).intValue());
        }

        public final String t(int i10) {
            return o.c(i10);
        }
    }

    public /* synthetic */ class c extends C7607p implements Function1 {
        public c(C2760w1 c2760w1) {
            super(1, c2760w1, C2760w1.class, "fillIndicators", "fillIndicators(Ljava/util/List;)V", 0);
        }

        @Override // kotlin.jvm.functions.Function1
        public /* bridge */ /* synthetic */ Object invoke(Object obj) {
            t((List) obj);
            return H.f17640a;
        }

        public final void t(List list) {
            ((C2760w1) this.f97930b).b(list);
        }
    }

    public /* synthetic */ class d extends C7607p implements Function1 {
        public d(o oVar) {
            super(1, oVar, o.class, "getMainIndicatorKey", "getMainIndicatorKey(I)Ljava/lang/String;", 0);
        }

        @Override // kotlin.jvm.functions.Function1
        public /* bridge */ /* synthetic */ Object invoke(Object obj) {
            return t(((Number) obj).intValue());
        }

        public final String t(int i10) {
            return o.d(i10);
        }
    }

    public /* synthetic */ class e extends C7607p implements Function1 {
        public e(C2760w1 c2760w1) {
            super(1, c2760w1, C2760w1.class, "fillMainIndicators", "fillMainIndicators(Ljava/util/List;)V", 0);
        }

        @Override // kotlin.jvm.functions.Function1
        public /* bridge */ /* synthetic */ Object invoke(Object obj) {
            t((List) obj);
            return H.f17640a;
        }

        public final void t(List list) {
            ((C2760w1) this.f97930b).c(list);
        }
    }

    public KLineManager(Context context, DefaultConstructorMarker defaultConstructorMarker) {
        this.f142507a = context;
        SharedPreferences sharedPreferences = context.getSharedPreferences("soso_kline", 0);
        this.f142508b = sharedPreferences;
        this.f142510d = true;
        this.f142511e = 2;
        this.f142512f = "";
        this.f142513g = "";
        this.f142515i = -1.0d;
        this.f142516j = "";
        this.f142517k = "default";
        this.f142521o = "on_kline";
        this.f142525s = true;
        this.f142528v = 1.0d;
        this.f142494B = true;
        this.f142501I = sharedPreferences.getBoolean("show_position_line", false);
        this.f142502J = sharedPreferences.getBoolean("show_alert_line", true);
        this.f142503K = sharedPreferences.getBoolean("show_liqui_line", true);
        this.f142504L = true;
        this.f142505M = new MutableLiveData();
        this.f142506N = new MutableLiveData();
    }

    public static void c(List list, Function1 function1, Function1 function2) {
        ArrayList arrayList = new ArrayList(AbstractC2804s.y(list, 10));
        Iterator it = list.iterator();
        while (it.hasNext()) {
            arrayList.add(function1.invoke(it.next()));
        }
        ArrayList arrayList2 = new ArrayList();
        for (Object obj : arrayList) {
            if (!AbstractC7609s.f((String) obj, "")) {
                arrayList2.add(obj);
            }
        }
        function2.invoke(arrayList2);
    }

    public static /* synthetic */ void e1(KLineManager kLineManager, String str, String str2, int i10, Object obj) {
        if ((i10 & 2) != 0) {
            str2 = "normal";
        }
        kLineManager.d1(str, str2);
    }

    public static /* synthetic */ String h0(KLineManager kLineManager, String str, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            str = "normal";
        }
        return kLineManager.g0(str);
    }

    public static final KLineManager s() {
        return f142490O.a();
    }

    public final String A() {
        String string = this.f142508b.getString("price_mode", "usd");
        return string == null ? "usd" : string;
    }

    public final void A0(C2741q c2741q) {
        this.f142531y = c2741q;
    }

    public final double B() {
        return this.f142528v;
    }

    public final void B0(boolean z10) {
        this.f142499G = z10;
    }

    public final String C() {
        return this.f142521o;
    }

    public final void C0(boolean z10) {
        this.f142510d = z10;
    }

    public final double D() {
        return this.f142515i;
    }

    public final void D0(boolean z10) {
        this.f142495C = z10;
    }

    public final List E() {
        return a("mainIndicator_REVERSAL", "0");
    }

    public final void E0(String str) {
        this.f142508b.edit().putString("price_mode", str).apply();
    }

    public final List F() {
        List listM0;
        String string = this.f142508b.getString("MAIN_SCRIPT_REVERSAL", null);
        return (string == null || (listM0 = y.M0(string, new String[]{","}, false, 0, 6, null)) == null) ? r.n() : listM0;
    }

    public final void F0(double d10) {
        this.f142527u = d10;
    }

    public final List G() {
        return C2760w1.f19594a.h();
    }

    public final void G0(double d10) {
        this.f142528v = d10;
    }

    public final boolean H() {
        return this.f142525s;
    }

    public final void H0(boolean z10) {
        this.f142509c = z10;
    }

    public final double I() {
        return this.f142529w;
    }

    public final void I0(String str) {
        this.f142521o = str;
    }

    public final long J() {
        return this.f142530x;
    }

    public final void J0(boolean z10) {
        this.f142523q = z10;
    }

    public final String K() {
        return this.f142517k;
    }

    public final void K0(boolean z10) {
        this.f142522p = z10;
    }

    public final int L() {
        return this.f142518l;
    }

    public final void L0(boolean z10) {
        this.f142508b.edit().putBoolean("show_indicator_action_popup", z10).apply();
    }

    public final String M() {
        return this.f142512f;
    }

    public final void M0(boolean z10) {
        this.f142503K = z10;
        this.f142508b.edit().putBoolean("show_liqui_line", z10).apply();
    }

    public final MutableLiveData N() {
        return this.f142505M;
    }

    public final void N0(boolean z10) {
        this.f142508b.edit().putBoolean("show_option_buttons", z10).apply();
    }

    public final boolean O() {
        return this.f142508b.getBoolean("is_hide_indic_info", false);
    }

    public final void O0(boolean z10) {
        this.f142501I = z10;
    }

    public final boolean P() {
        return this.f142520n;
    }

    public final void P0(boolean z10) {
        this.f142508b.edit().putBoolean("show_position_line", z10).apply();
    }

    public final boolean Q() {
        return this.f142514h;
    }

    public final void Q0(double d10) {
        if (AbstractC7609s.f(this.f142517k, "default")) {
            this.f142515i = d10;
        }
    }

    public final boolean R() {
        return this.f142508b.getBoolean("indicator_info_value_abbreviation_enabled", false);
    }

    public final void R0(List list) {
        this.f142508b.edit().putString("mainIndicator_REVERSAL", z.z0(list, ",", null, null, 0, null, null, 62, null)).apply();
    }

    public final boolean S() {
        return this.f142526t;
    }

    public final void S0(List list) {
        this.f142508b.edit().putString("MAIN_SCRIPT_REVERSAL", z.z0(list, ",", null, null, 0, null, null, 62, null)).apply();
    }

    public final boolean T() {
        return this.f142510d;
    }

    public final void T0(List list) {
        C2760w1.f19594a.d(list);
    }

    public final MutableLiveData U() {
        return this.f142506N;
    }

    public final void U0(boolean z10) {
        this.f142525s = z10;
    }

    public final boolean V() {
        return this.f142509c;
    }

    public final void V0(double d10) {
        this.f142529w = d10;
    }

    public final boolean W() {
        return this.f142502J;
    }

    public final void W0(long j10) {
        this.f142530x = j10;
    }

    public final boolean X() {
        return this.f142523q;
    }

    public final void X0(String str) {
        this.f142517k = str;
    }

    public final boolean Y() {
        return this.f142522p;
    }

    public final void Y0(int i10) {
        this.f142518l = i10;
    }

    public final boolean Z() {
        return this.f142508b.getBoolean("show_indicator_action_popup", true);
    }

    public final void Z0(String str) {
        this.f142512f = str;
    }

    public final List a(String str, String str2) {
        List listM0;
        String string = this.f142508b.getString(str, str2);
        if (string == null || (listM0 = y.M0(string, new String[]{","}, false, 0, 6, null)) == null) {
            return r.n();
        }
        ArrayList arrayList = new ArrayList();
        Iterator it = listM0.iterator();
        while (it.hasNext()) {
            Integer numP = w.p((String) it.next());
            if (numP != null) {
                arrayList.add(numP);
            }
        }
        return arrayList;
    }

    public final boolean a0() {
        return this.f142503K;
    }

    public final void a1(boolean z10) {
        this.f142494B = z10;
    }

    public final Map b() {
        String string = this.f142508b.getString("hide_indic_info_state", null);
        if (string == null || string.length() == 0) {
            return new LinkedHashMap();
        }
        try {
            Map map = (Map) f142491P.fromJson(string, new KLineManager$hideIndicInfoState$type$1().getType());
            return map == null ? new LinkedHashMap() : map;
        } catch (Exception unused) {
            return new LinkedHashMap();
        }
    }

    public final boolean b0() {
        return this.f142508b.getBoolean("show_option_buttons", true);
    }

    public final void b1(boolean z10) {
        this.f142519m = z10;
    }

    public final boolean c0() {
        return this.f142501I;
    }

    public final boolean c1() {
        this.f142508b.edit().putBoolean("global_indicator_expand_state", !this.f142508b.getBoolean("global_indicator_expand_state", true)).apply();
        return this.f142508b.getBoolean("global_indicator_expand_state", true);
    }

    public final boolean d0() {
        return this.f142494B;
    }

    public final void d1(String str, String str2) {
        this.f142508b.edit().putString("period_pair_" + str2, str).apply();
    }

    public final boolean e0() {
        return this.f142519m;
    }

    public final int f() {
        return this.f142508b.getInt("kline_data_info_can_callback", -1);
    }

    public final int f0() {
        int iQ = q(3);
        int i10 = this.f142518l;
        if (iQ != 0) {
            return iQ;
        }
        return i10 == 0 ? 1 : 2;
    }

    public final Chart g() {
        return this.f142532z;
    }

    public final String g0(String str) {
        Zj.c cVar = Zj.c.T15m;
        String string = this.f142508b.getString("period_pair_" + str, cVar.d());
        return string == null ? cVar.d() : string;
    }

    public final String h() {
        return this.f142513g;
    }

    public final Context i() {
        return this.f142507a;
    }

    public final void i0() {
        this.f142497E = false;
        this.f142498F = 0;
    }

    public final int j() {
        return this.f142511e;
    }

    public final void j0(boolean z10) {
        this.f142502J = z10;
        this.f142508b.edit().putBoolean("show_alert_line", z10).apply();
    }

    public final String k() {
        return this.f142516j;
    }

    public final void k0(int i10) {
        this.f142508b.edit().putInt("kline_data_info_can_callback", i10).apply();
    }

    public final boolean l(String str) {
        if (!b0()) {
            return false;
        }
        Boolean bool = (Boolean) b().get(str.toUpperCase(Locale.ROOT));
        if (bool != null) {
            return bool.booleanValue();
        }
        return false;
    }

    public final void l0(Chart chart) {
        this.f142532z = chart;
    }

    public final boolean m() {
        return this.f142496D;
    }

    public final void m0(String str) {
        this.f142513g = str;
    }

    public final boolean n() {
        return this.f142500H;
    }

    public final void n0(int i10) {
        this.f142511e = i.f(i10, 0);
    }

    public final boolean o() {
        if (b0()) {
            return this.f142508b.getBoolean("global_indicator_expand_state", true);
        }
        return true;
    }

    public final void o0(String str) {
        this.f142516j = str;
    }

    public final List p() {
        return a("indicator_INDEX", "");
    }

    public final void p0(String str, boolean z10) {
        try {
            Map mapZ = N.z(b());
            mapZ.put(str.toUpperCase(Locale.ROOT), Boolean.valueOf(z10));
            this.f142508b.edit().putString("hide_indic_info_state", f142491P.toJson(mapZ)).apply();
        } catch (Exception unused) {
        }
    }

    public final int q(int i10) {
        int iR = r(i10);
        return this.f142508b.getInt("indicator_" + i10, iR);
    }

    public final void q0(boolean z10) {
        this.f142496D = z10;
    }

    public final int r(int i10) {
        if (i10 == 0) {
            return 21;
        }
        if (i10 != 10 && i10 != 12 && i10 != 15 && i10 != 17) {
            if (i10 == 5) {
                return 48;
            }
            if (i10 != 6 && i10 != 7 && i10 != 8 && i10 != 24 && i10 != 25) {
                return 0;
            }
        }
        return 1;
    }

    public final void r0(boolean z10) {
        this.f142520n = z10;
    }

    public final void s0(boolean z10) {
        this.f142514h = z10;
    }

    public final boolean t() {
        return this.f142524r;
    }

    public final void t0(boolean z10) {
        this.f142508b.edit().putBoolean("indicator_info_value_abbreviation_enabled", z10).apply();
    }

    public final Map u() {
        String string = this.f142508b.getString("main_indic_show_state", null);
        if (string == null || string.length() == 0) {
            return new LinkedHashMap();
        }
        try {
            Map map = (Map) f142491P.fromJson(string, new KLineManager$mainIndicShowState$type$1().getType());
            return map == null ? new LinkedHashMap() : map;
        } catch (Exception unused) {
            return new LinkedHashMap();
        }
    }

    public final void u0(List list) {
        c(list, new b(o.f134231a), new c(C2760w1.f19594a));
        this.f142508b.edit().putString("indicator_INDEX", z.z0(list, ",", null, null, 0, null, null, 62, null)).apply();
    }

    public final List v() {
        return a("mainIndicator_INDEX", "");
    }

    public final void v0(int i10, int i11) {
        if (i11 == -1) {
            return;
        }
        this.f142508b.edit().putInt("indicator_" + i10, i11).apply();
    }

    public final Context w() {
        return this.f142493A;
    }

    public final void w0(boolean z10) {
        this.f142524r = z10;
    }

    public final C2741q x() {
        return this.f142531y;
    }

    public final void x0(String str, boolean z10) {
        try {
            Map mapZ = N.z(u());
            mapZ.put(str, Boolean.valueOf(z10));
            this.f142508b.edit().putString("main_indic_show_state", f142491P.toJson(mapZ)).apply();
        } catch (Exception unused) {
        }
    }

    public final boolean y() {
        return this.f142499G;
    }

    public final void y0(List list) {
        c(list, new d(o.f134231a), new e(C2760w1.f19594a));
        this.f142508b.edit().putString("mainIndicator_INDEX", z.z0(list, ",", null, null, 0, null, null, 62, null)).apply();
    }

    public final boolean z() {
        return this.f142495C;
    }

    public final void z0(Context context) {
        this.f142493A = context;
    }
}
