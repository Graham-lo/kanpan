package Rj;

import android.graphics.Canvas;
import android.graphics.Rect;
import gk.C7458d;
import gk.C7468i;
import gk.C7472k;
import gk.C7482p;
import gk.C7488s0;
import gk.C7495w;
import java.util.Collection;
import java.util.HashMap;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import sp.aicoin_kline.chart.data.AISRLData;
import sp.aicoin_kline.chart.data.EstimatedLiqVpcTimePoints;
import sp.aicoin_kline.chart.data.drawing.DrawingItem;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: Rj.q, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public class C2741q {

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public List f19505m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public Map f19506n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public List f19507o;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public mk.a f19511s;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public String f19513u;

    /* JADX INFO: renamed from: i, reason: collision with root package name */
    public final HashMap f19501i = new HashMap();

    /* JADX INFO: renamed from: j, reason: collision with root package name */
    public final HashMap f19502j = new HashMap();

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public int f19508p = 0;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public boolean f19509q = false;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public final String f19512t = "";

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public boolean f19515w = false;

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final HashMap f19493a = new HashMap();

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final HashMap f19494b = new HashMap();

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final HashMap f19495c = new HashMap();

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public final LinkedHashMap f19496d = new LinkedHashMap();

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public final HashMap f19497e = new HashMap();

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public final HashMap f19498f = new HashMap();

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public final HashMap f19499g = new HashMap();

    /* JADX INFO: renamed from: h, reason: collision with root package name */
    public final HashMap f19500h = new HashMap();

    /* JADX INFO: renamed from: k, reason: collision with root package name */
    public final HashMap f19503k = new HashMap();

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public C1 f19504l = new C1();

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final Rect f19510r = new Rect();

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public final ek.B f19514v = new ek.B();

    public void A(String str, EstimatedLiqVpcTimePoints estimatedLiqVpcTimePoints) {
        C2765z c2765zH;
        if (str == null || (c2765zH = h(str)) == null) {
            return;
        }
        c2765zH.j0(estimatedLiqVpcTimePoints);
        String[] strArr = AbstractC2755v.f19561m;
        dk.s sVar = new dk.s(this, c2765zH);
        for (C2702d c2702d : f()) {
            if (str.equals(c2702d.c())) {
                for (String str2 : strArr) {
                    AbstractC2755v abstractC2755vG = g(c2702d.d() + str2);
                    if (abstractC2755vG instanceof Tj.a) {
                        for (AbstractC2755v abstractC2755v : ((Tj.a) abstractC2755vG).s()) {
                            if (abstractC2755v instanceof gk.V) {
                                abstractC2755v.q(sVar);
                            }
                        }
                    }
                }
            }
        }
    }

    public void B(String str, ak.d dVar) {
        C2765z c2765zH;
        if (str == null || (c2765zH = h(str)) == null) {
            return;
        }
        c2765zH.n0(dVar);
        y(str, null);
    }

    public void C(String str, List list, Boolean bool) {
        C2765z c2765zH;
        if (str == null || (c2765zH = h(str)) == null) {
            return;
        }
        if (list != null) {
            c2765zH.k0(list, bool.booleanValue());
        }
        String[] strArr = AbstractC2755v.f19561m;
        dk.s sVar = new dk.s(this, c2765zH);
        for (C2702d c2702d : f()) {
            if (str.equals(c2702d.c())) {
                for (String str2 : strArr) {
                    AbstractC2755v abstractC2755vG = g(c2702d.d() + str2);
                    if (abstractC2755vG instanceof Tj.a) {
                        for (AbstractC2755v abstractC2755v : ((Tj.a) abstractC2755vG).s()) {
                            if (abstractC2755v instanceof C7458d) {
                                abstractC2755v.q(sVar);
                            }
                        }
                    }
                }
            }
        }
    }

    public void D(String str, Map map, boolean z10, boolean z11) {
        C2765z c2765zH;
        if (str == null || (c2765zH = h(str)) == null) {
            return;
        }
        if (map != null) {
            c2765zH.l0(map, z10, z11);
        }
        String[] strArr = AbstractC2755v.f19561m;
        dk.s sVar = new dk.s(this, c2765zH);
        for (C2702d c2702d : f()) {
            if (str.equals(c2702d.c())) {
                for (String str2 : strArr) {
                    AbstractC2755v abstractC2755vG = g(c2702d.d() + str2);
                    if (abstractC2755vG != null && abstractC2755vG.o()) {
                        abstractC2755vG.q(sVar);
                    }
                }
            }
        }
    }

    public void E(String str, List list, X x10) {
        C2765z c2765zH;
        if (str == null || (c2765zH = h(str)) == null) {
            return;
        }
        if (list != null) {
            c2765zH.o0(list, x10);
        }
        String[] strArr = AbstractC2755v.f19561m;
        dk.s sVar = new dk.s(this, c2765zH);
        for (C2702d c2702d : f()) {
            if (str.equals(c2702d.c())) {
                for (String str2 : strArr) {
                    AbstractC2755v abstractC2755vG = g(c2702d.d() + str2);
                    if (abstractC2755vG instanceof Tj.a) {
                        for (AbstractC2755v abstractC2755v : ((Tj.a) abstractC2755vG).s()) {
                            if (abstractC2755v instanceof C7468i) {
                                if (list == null) {
                                    abstractC2755v.q(sVar);
                                } else {
                                    ((C7468i) abstractC2755v).y(sVar, list, x10);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    public void F(String str, List list, Boolean bool) {
        C2765z c2765zH;
        if (str == null || (c2765zH = h(str)) == null) {
            return;
        }
        if (list != null) {
            c2765zH.p0(list, bool.booleanValue());
        }
        String[] strArr = AbstractC2755v.f19561m;
        dk.s sVar = new dk.s(this, c2765zH);
        for (C2702d c2702d : f()) {
            if (str.equals(c2702d.c())) {
                for (String str2 : strArr) {
                    AbstractC2755v abstractC2755vG = g(c2702d.d() + str2);
                    if (abstractC2755vG instanceof Tj.a) {
                        for (AbstractC2755v abstractC2755v : ((Tj.a) abstractC2755vG).s()) {
                            if (abstractC2755v instanceof C7472k) {
                                abstractC2755v.q(sVar);
                            }
                        }
                    }
                }
            }
        }
    }

    public void G(String str, List list, Boolean bool) {
        C2765z c2765zH;
        if (str == null || (c2765zH = h(str)) == null) {
            return;
        }
        if (list != null) {
            c2765zH.q0(list, bool.booleanValue());
        }
        String[] strArr = AbstractC2755v.f19561m;
        dk.s sVar = new dk.s(this, c2765zH);
        for (C2702d c2702d : f()) {
            if (str.equals(c2702d.c())) {
                for (String str2 : strArr) {
                    AbstractC2755v abstractC2755vG = g(c2702d.d() + str2);
                    if (abstractC2755vG instanceof Tj.a) {
                        for (AbstractC2755v abstractC2755v : ((Tj.a) abstractC2755vG).s()) {
                            if (abstractC2755v instanceof C7488s0) {
                                abstractC2755v.q(sVar);
                            }
                        }
                    }
                }
            }
        }
    }

    public void H(String str, LinkedHashMap linkedHashMap) {
        C2765z c2765zH;
        if (str == null || (c2765zH = h(str)) == null || linkedHashMap == null) {
            return;
        }
        ik.f.a(linkedHashMap);
        Collection collectionValues = linkedHashMap.values();
        if (collectionValues.size() == 0) {
            c2765zH.e0(1);
            break;
        }
        Iterator it = collectionValues.iterator();
        int size = -1;
        while (true) {
            if (!it.hasNext()) {
                c2765zH.r0(linkedHashMap);
                if (c2765zH.X() != 0) {
                    break;
                } else {
                    return;
                }
            } else {
                lk.a aVar = (lk.a) it.next();
                if (aVar == null || !(size == -1 || aVar.a().size() == size)) {
                    c2765zH.e0(1);
                    break;
                }
                size = aVar.a().size();
            }
        }
        if (c2765zH.B() <= 0) {
            return;
        }
        y1 y1VarM = m(str);
        if (y1VarM != null) {
            y1VarM.b0();
        }
        String[] strArr = AbstractC2755v.f19561m;
        dk.s sVar = new dk.s(this, c2765zH);
        for (C2702d c2702d : f()) {
            if (str.equals(c2702d.c())) {
                for (String str2 : strArr) {
                    AbstractC2755v abstractC2755vG = g(c2702d.d() + str2);
                    if (abstractC2755vG != null) {
                        abstractC2755vG.q(sVar);
                    }
                }
            }
        }
    }

    public void I(String str, List list, boolean z10) {
        C2765z c2765zH;
        if (str == null || (c2765zH = h(str)) == null) {
            return;
        }
        if (list != null) {
            c2765zH.s0(list, z10);
        }
        String[] strArr = AbstractC2755v.f19561m;
        dk.s sVar = new dk.s(this, c2765zH);
        for (C2702d c2702d : f()) {
            if (str.equals(c2702d.c())) {
                for (String str2 : strArr) {
                    AbstractC2755v abstractC2755vG = g(c2702d.d() + str2);
                    if (abstractC2755vG instanceof C2724k0) {
                        abstractC2755vG.q(sVar);
                    }
                }
            }
        }
    }

    public void J(String str, List list, Boolean bool) {
        C2765z c2765zH;
        if (str == null || (c2765zH = h(str)) == null) {
            return;
        }
        if (list != null) {
            c2765zH.t0(list, bool.booleanValue());
        }
        String[] strArr = AbstractC2755v.f19561m;
        dk.s sVar = new dk.s(this, c2765zH);
        for (C2702d c2702d : f()) {
            if (str.equals(c2702d.c())) {
                for (String str2 : strArr) {
                    AbstractC2755v abstractC2755vG = g(c2702d.d() + str2);
                    if (abstractC2755vG instanceof Tj.a) {
                        for (AbstractC2755v abstractC2755v : ((Tj.a) abstractC2755vG).s()) {
                            if (abstractC2755v instanceof gk.J0) {
                                abstractC2755v.q(sVar);
                            }
                        }
                    }
                }
            }
        }
    }

    public void K(String str, List list, Boolean bool) {
        C2765z c2765zH;
        if (str == null || (c2765zH = h(str)) == null) {
            return;
        }
        if (list != null) {
            c2765zH.u0(list, bool.booleanValue());
        }
        String[] strArr = AbstractC2755v.f19561m;
        dk.s sVar = new dk.s(this, c2765zH);
        for (C2702d c2702d : f()) {
            if (str.equals(c2702d.c())) {
                for (String str2 : strArr) {
                    AbstractC2755v abstractC2755vG = g(c2702d.d() + str2);
                    if (abstractC2755vG instanceof gk.K0) {
                        abstractC2755vG.q(sVar);
                    }
                }
            }
        }
    }

    public void L(String str, Map map, Boolean bool) {
        C2765z c2765zH;
        if (str == null || (c2765zH = h(str)) == null) {
            return;
        }
        if (map != null) {
            c2765zH.v0(map);
        }
        String[] strArr = AbstractC2755v.f19561m;
        dk.s sVar = new dk.s(this, c2765zH);
        for (C2702d c2702d : f()) {
            if (str.equals(c2702d.c())) {
                for (String str2 : strArr) {
                    AbstractC2755v abstractC2755vG = g(c2702d.d() + str2);
                    if (abstractC2755vG instanceof Tj.a) {
                        for (AbstractC2755v abstractC2755v : ((Tj.a) abstractC2755vG).s()) {
                            if (abstractC2755v instanceof gk.L0) {
                                abstractC2755v.q(sVar);
                            }
                        }
                    }
                }
            }
        }
    }

    public void M(String str, Map map, Boolean bool, Boolean bool2) {
        C2765z c2765zH;
        if (str == null || (c2765zH = h(str)) == null) {
            return;
        }
        if (map != null) {
            c2765zH.x0(map, bool.booleanValue(), bool2.booleanValue());
        }
        String[] strArr = AbstractC2755v.f19561m;
        dk.s sVar = new dk.s(this, c2765zH);
        for (C2702d c2702d : f()) {
            if (str.equals(c2702d.c())) {
                for (String str2 : strArr) {
                    AbstractC2755v abstractC2755vG = g(c2702d.d() + str2);
                    if (abstractC2755vG instanceof gk.N0) {
                        abstractC2755vG.q(sVar);
                    }
                }
            }
        }
    }

    public void N(String str, List list) {
        C2765z c2765zH;
        if (str == null || (c2765zH = h(str)) == null) {
            return;
        }
        if (list != null) {
            c2765zH.y0(list);
        }
        String[] strArr = AbstractC2755v.f19561m;
        dk.s sVar = new dk.s(this, c2765zH);
        for (C2702d c2702d : f()) {
            if (str.equals(c2702d.c())) {
                for (String str2 : strArr) {
                    AbstractC2755v abstractC2755vG = g(c2702d.d() + str2);
                    if (abstractC2755vG instanceof Tj.a) {
                        for (AbstractC2755v abstractC2755v : ((Tj.a) abstractC2755vG).s()) {
                            if (abstractC2755v instanceof gk.X0) {
                                abstractC2755v.q(sVar);
                            }
                        }
                    }
                }
            }
        }
    }

    public void O(String str, List list, Boolean bool) {
        C2765z c2765zH;
        if (str == null || (c2765zH = h(str)) == null) {
            return;
        }
        this.f19515w = (list == null || list.isEmpty()) ? false : true;
        if (list != null) {
            c2765zH.z0(list, bool.booleanValue());
        }
        String[] strArr = AbstractC2755v.f19561m;
        dk.s sVar = new dk.s(this, c2765zH);
        for (C2702d c2702d : f()) {
            if (str.equals(c2702d.c())) {
                for (String str2 : strArr) {
                    AbstractC2755v abstractC2755vG = g(c2702d.d() + str2);
                    if (abstractC2755vG instanceof Tj.a) {
                        for (AbstractC2755v abstractC2755v : ((Tj.a) abstractC2755vG).s()) {
                            if (abstractC2755v instanceof gk.r) {
                                abstractC2755v.q(sVar);
                            }
                        }
                    }
                }
            }
        }
    }

    public final AbstractC2744r0 a(String str) {
        if (str == null) {
            return null;
        }
        return (AbstractC2744r0) this.f19501i.get(str);
    }

    public final void b(String str, String[] strArr, Canvas canvas) {
        if (str != null) {
            for (String str2 : strArr) {
                AbstractC2744r0 abstractC2744r0A = a(str + str2);
                if (abstractC2744r0A != null) {
                    abstractC2744r0A.g(canvas);
                }
                if (str2.equals(".b")) {
                    for (String str3 : strArr) {
                        String strA = kk.i.a(str, str3);
                        AbstractC2744r0 abstractC2744r0 = strA == null ? null : (AbstractC2744r0) this.f19502j.get(strA);
                        if (abstractC2744r0 != null) {
                            abstractC2744r0.g(canvas);
                        }
                    }
                }
            }
        }
    }

    public final void c(boolean z10) {
        if (z10) {
            this.f19497e.clear();
            this.f19503k.clear();
        }
        this.f19493a.clear();
        this.f19494b.clear();
        this.f19496d.clear();
        this.f19499g.clear();
        this.f19500h.clear();
        this.f19501i.clear();
        this.f19502j.clear();
        this.f19504l = new C1();
        this.f19509q = false;
    }

    public void d(String str, Canvas canvas) {
        if (str != null) {
            for (C2702d c2702d : f()) {
                if (c2702d != null && str.equals(c2702d.c())) {
                    if (c2702d.u() < c2702d.y() && c2702d.z() < c2702d.p()) {
                        int iSave = canvas.save();
                        canvas.clipRect(c2702d.u(), c2702d.z(), c2702d.y(), c2702d.p());
                        C2765z c2765zH = h(c2702d.c());
                        if (c2765zH != null) {
                            try {
                                if (c2765zH.B() < 1) {
                                    b(c2702d.d(), new String[]{".b"}, canvas);
                                } else {
                                    b(c2702d.d(), new String[]{".b", ".g", ".heat_liquidation", ".m", ".a", ".mrk"}, canvas);
                                }
                            } catch (Throwable th2) {
                                canvas.restoreToCount(iSave);
                                throw th2;
                            }
                        } else {
                            b(c2702d.d(), new String[]{".b"}, canvas);
                        }
                        canvas.restoreToCount(iSave);
                    }
                    c2702d.E(false);
                }
            }
            for (AbstractC2759w0 abstractC2759w0 : this.f19499g.values()) {
                if (str.equals(abstractC2759w0.c())) {
                    abstractC2759w0.l();
                }
            }
            y1 y1VarM = m(str);
            if (y1VarM != null) {
                y1VarM.i();
            }
        }
        if (str == null) {
            return;
        }
        for (C2702d c2702d2 : f()) {
            if (c2702d2 != null && str.equals(c2702d2.c()) && (c2702d2 instanceof AbstractC2705e)) {
                ((AbstractC2705e) c2702d2).J(canvas);
            }
        }
        for (C2702d c2702d3 : f()) {
            if (c2702d3 != null && str.equals(c2702d3.c())) {
                b(c2702d3.d(), new String[]{".t", ".d", ".hd", ".i", ".sub_reversal_tip", ".s", ".msk", ".drawing", ".liqui_line", ".alert_line", ".handle_line", ".kline_tag", ".heat_liquidation_window"}, canvas);
                String strD = c2702d3.d();
                String[] strArr = {".drawing"};
                if (strD != null) {
                    String str2 = strArr[0];
                    AbstractC2744r0 abstractC2744r0A = a(strD + str2);
                    if (abstractC2744r0A != null) {
                        abstractC2744r0A.h(canvas);
                    }
                    String strA = kk.i.a(strD, str2);
                    AbstractC2744r0 abstractC2744r0 = strA == null ? null : (AbstractC2744r0) this.f19502j.get(strA);
                    if (abstractC2744r0 != null) {
                        abstractC2744r0.h(canvas);
                    }
                }
                b(c2702d3.d(), new String[]{".window"}, canvas);
            }
        }
    }

    public C2702d e(String str) {
        if (str == null) {
            return null;
        }
        return (C2702d) this.f19496d.get(str);
    }

    public Collection f() {
        return this.f19496d.values();
    }

    public AbstractC2755v g(String str) {
        if (str == null) {
            return null;
        }
        return (AbstractC2755v) this.f19500h.get(str);
    }

    public C2765z h(String str) {
        if (str == null) {
            return null;
        }
        return (C2765z) this.f19494b.get(str);
    }

    public G i(String str) {
        if (str == null) {
            return null;
        }
        return (G) this.f19498f.get(str);
    }

    public ak.d j(String str) {
        C2765z c2765zH;
        return (str == null || (c2765zH = h(str)) == null) ? ak.d.NORMAL : c2765zH.J();
    }

    public U k(String str) {
        if (str == null) {
            return null;
        }
        return (U) this.f19503k.get(str);
    }

    public AbstractC2759w0 l(String str) {
        if (str == null) {
            return null;
        }
        return (AbstractC2759w0) this.f19499g.get(str);
    }

    public y1 m(String str) {
        if (str == null) {
            return null;
        }
        return (y1) this.f19497e.get(str);
    }

    public C1 n() {
        return this.f19504l;
    }

    public String o() {
        return this.f19513u;
    }

    public boolean p() {
        return this.f19515w;
    }

    public void q(String str, int i10, int i11, int i12, int i13) {
        C2765z c2765zH;
        this.f19510r.set(i10, i11, i12, i13);
        AbstractC2705e abstractC2705e = (AbstractC2705e) this.f19493a.get(str + ".root");
        if (abstractC2705e == null) {
            return;
        }
        abstractC2705e.C(this, i12 - i10, i13 - i11);
        abstractC2705e.B(i10, i11, i12, i13, false);
        y1 y1VarM = m(str);
        if (y1VarM != null) {
            y1VarM.L();
        }
        G gI = i(str);
        if (gI != null) {
            gI.z();
        }
        C1 c1N = n();
        if (c1N != null) {
            c1N.j();
        }
        if (str == null || (c2765zH = h(str)) == null || c2765zH.B() < 1) {
            return;
        }
        String[] strArr = {".m", ".a"};
        for (C2702d c2702d : f()) {
            if (str.equals(c2702d.c())) {
                for (int i14 = 0; i14 < 2; i14++) {
                    AbstractC2755v abstractC2755vG = g(c2702d.d() + strArr[i14]);
                    if (abstractC2755vG != null) {
                        abstractC2755vG.r();
                    }
                }
                AbstractC2759w0 abstractC2759w0L = l(c2702d.d());
                if (abstractC2759w0L != null) {
                    abstractC2759w0L.T();
                    abstractC2759w0L.K(c2702d.z(), c2702d.p());
                }
            }
        }
    }

    public float r(KLineManager kLineManager, Zj.e eVar) {
        return this.f19514v.a(kLineManager, this, eVar);
    }

    public void s(String str, U u10) {
        this.f19503k.put(str, u10);
    }

    public final void t(mk.a aVar) {
        this.f19511s = aVar;
        for (C2702d c2702d : f()) {
            if (c2702d instanceof AbstractC2705e) {
                ((AbstractC2705e) c2702d).L(aVar);
            }
        }
        Iterator it = this.f19502j.values().iterator();
        while (it.hasNext()) {
            ((AbstractC2744r0) it.next()).u(aVar);
        }
        Iterator it2 = this.f19501i.values().iterator();
        while (it2.hasNext()) {
            ((AbstractC2744r0) it2.next()).u(aVar);
        }
    }

    public void u(String str) {
        this.f19513u = str;
    }

    public void v() {
        Iterator it = this.f19502j.values().iterator();
        while (it.hasNext()) {
            ((AbstractC2744r0) it.next()).t();
        }
        Iterator it2 = this.f19501i.values().iterator();
        while (it2.hasNext()) {
            ((AbstractC2744r0) it2.next()).t();
        }
    }

    public void w(String str, AISRLData aISRLData, Boolean bool) {
        C2765z c2765zH;
        if (str == null || (c2765zH = h(str)) == null) {
            return;
        }
        if (aISRLData != null) {
            c2765zH.g0(aISRLData, bool.booleanValue());
        }
        String[] strArr = AbstractC2755v.f19561m;
        dk.s sVar = new dk.s(this, c2765zH);
        for (C2702d c2702d : f()) {
            if (str.equals(c2702d.c())) {
                for (String str2 : strArr) {
                    AbstractC2755v abstractC2755vG = g(c2702d.d() + str2);
                    if (abstractC2755vG instanceof Tj.a) {
                        for (AbstractC2755v abstractC2755v : ((Tj.a) abstractC2755vG).s()) {
                            if (abstractC2755v instanceof C7482p) {
                                abstractC2755v.q(sVar);
                            }
                        }
                    }
                }
            }
        }
    }

    public void x(String str, List list, Boolean bool) {
        C2765z c2765zH;
        if (str == null || (c2765zH = h(str)) == null) {
            return;
        }
        if (list != null) {
            c2765zH.h0(list, bool.booleanValue());
        }
        String[] strArr = AbstractC2755v.f19561m;
        dk.s sVar = new dk.s(this, c2765zH);
        for (C2702d c2702d : f()) {
            if (str.equals(c2702d.c())) {
                for (String str2 : strArr) {
                    AbstractC2755v abstractC2755vG = g(c2702d.d() + str2);
                    if (abstractC2755vG instanceof Tj.a) {
                        for (AbstractC2755v abstractC2755v : ((Tj.a) abstractC2755vG).s()) {
                            if (abstractC2755v instanceof C7495w) {
                                abstractC2755v.q(sVar);
                            }
                        }
                    }
                }
            }
        }
    }

    public void y(String str, lk.a aVar) {
        C2765z c2765zH;
        if (str == null || (c2765zH = h(str)) == null) {
            return;
        }
        if (aVar != null) {
            c2765zH.i0(aVar);
            if (c2765zH.X() == 0) {
                return;
            }
        } else {
            c2765zH.e0(1);
        }
        if (c2765zH.B() <= 0) {
            return;
        }
        y1 y1VarM = m(str);
        if (y1VarM != null) {
            y1VarM.b0();
        }
        String[] strArr = AbstractC2755v.f19561m;
        dk.s sVar = new dk.s(this, c2765zH);
        for (C2702d c2702d : f()) {
            if (str.equals(c2702d.c())) {
                for (String str2 : strArr) {
                    AbstractC2755v abstractC2755vG = g(c2702d.d() + str2);
                    if (abstractC2755vG != null) {
                        abstractC2755vG.q(sVar);
                    }
                }
            }
        }
    }

    public void z(String str, DrawingItem[] drawingItemArr) {
        C2765z c2765zH;
        if (str == null || (c2765zH = h(str)) == null || drawingItemArr == null) {
            return;
        }
        c2765zH.b0(drawingItemArr);
        c2765zH.e0(5);
    }
}
