package Rj;

import Sf.AbstractC2804s;
import Sf.AbstractC2807v;
import Sf.AbstractC2808w;
import com.umeng.commonsdk.statistics.SdkVersion;
import java.util.ArrayList;
import java.util.Date;
import java.util.GregorianCalendar;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.chart.data.AISRLData;
import sp.aicoin_kline.chart.data.AISRLItem;
import sp.aicoin_kline.chart.data.AIWinRateItem;
import sp.aicoin_kline.chart.data.EstimatedLiqVpcRecord;
import sp.aicoin_kline.chart.data.EstimatedLiqVpcTimePoints;
import sp.aicoin_kline.chart.data.LargeOrderItem;
import sp.aicoin_kline.chart.data.ScriptDrawData;
import sp.aicoin_kline.chart.data.ScriptIndicConfig;
import sp.aicoin_kline.chart.data.drawing.DrawingItem;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: Rj.z, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2765z extends AbstractC2721j0 {

    /* JADX INFO: renamed from: N, reason: collision with root package name */
    public static final a f19647N = new a(null);

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public Map f19648A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public final ArrayList f19649B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public List f19650C;

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public List f19651D;

    /* JADX INFO: renamed from: E, reason: collision with root package name */
    public Map f19652E;

    /* JADX INFO: renamed from: F, reason: collision with root package name */
    public final LinkedHashMap f19653F;

    /* JADX INFO: renamed from: G, reason: collision with root package name */
    public AISRLData f19654G;

    /* JADX INFO: renamed from: H, reason: collision with root package name */
    public final LinkedHashMap f19655H;

    /* JADX INFO: renamed from: I, reason: collision with root package name */
    public DrawingItem[] f19656I;

    /* JADX INFO: renamed from: J, reason: collision with root package name */
    public int f19657J;

    /* JADX INFO: renamed from: K, reason: collision with root package name */
    public boolean f19658K;

    /* JADX INFO: renamed from: L, reason: collision with root package name */
    public long f19659L;

    /* JADX INFO: renamed from: M, reason: collision with root package name */
    public double f19660M;

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public long f19661g;

    /* JADX INFO: renamed from: h, reason: collision with root package name */
    public ak.d f19662h;

    /* JADX INFO: renamed from: i, reason: collision with root package name */
    public final Sj.a f19663i;

    /* JADX INFO: renamed from: j, reason: collision with root package name */
    public final Uj.d f19664j;

    /* JADX INFO: renamed from: k, reason: collision with root package name */
    public Map f19665k;

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public List f19666l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Object f19667m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public List f19668n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public List f19669o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final HashMap f19670p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final HashMap f19671q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public volatile List f19672r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public List f19673s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public List f19674t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public List f19675u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public List f19676v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public EstimatedLiqVpcTimePoints f19677w;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public List f19678x;

    /* JADX INFO: renamed from: y, reason: collision with root package name */
    public List f19679y;

    /* JADX INFO: renamed from: z, reason: collision with root package name */
    public List f19680z;

    /* JADX INFO: renamed from: Rj.z$a */
    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    /* JADX INFO: renamed from: Rj.z$b */
    public /* synthetic */ class b {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public static final /* synthetic */ int[] f19681a;

        static {
            int[] iArr = new int[X.values().length];
            try {
                iArr[X.RESET_ALL.ordinal()] = 1;
            } catch (NoSuchFieldError unused) {
            }
            try {
                iArr[X.APPEND_OR_MERGE.ordinal()] = 2;
            } catch (NoSuchFieldError unused2) {
            }
            try {
                iArr[X.REPLACE_OPEN.ordinal()] = 3;
            } catch (NoSuchFieldError unused3) {
            }
            f19681a = iArr;
        }
    }

    public C2765z(String str) {
        super(str);
        this.f19662h = ak.d.NORMAL;
        this.f19663i = new Sj.a();
        this.f19664j = new Uj.d();
        this.f19665k = new LinkedHashMap();
        this.f19666l = new ArrayList();
        this.f19667m = new Object();
        this.f19668n = Sf.r.n();
        this.f19669o = Sf.r.n();
        this.f19670p = new HashMap();
        this.f19671q = new HashMap();
        this.f19672r = Sf.r.n();
        this.f19673s = new ArrayList();
        this.f19674t = new ArrayList();
        this.f19675u = new ArrayList();
        this.f19676v = new ArrayList();
        this.f19678x = new ArrayList();
        this.f19679y = new ArrayList();
        this.f19680z = new ArrayList();
        this.f19648A = new LinkedHashMap();
        this.f19649B = new ArrayList();
        this.f19650C = Sf.r.n();
        this.f19651D = Sf.r.n();
        this.f19652E = Sf.N.j();
        this.f19653F = new LinkedHashMap();
        this.f19654G = new AISRLData(null, null, null, 7, null);
        this.f19655H = new LinkedHashMap();
        this.f19656I = new DrawingItem[0];
        this.f19657J = 1;
        this.f19660M = -1.0d;
    }

    /* JADX WARN: Multi-variable type inference failed */
    public static int g(Sj.a aVar) {
        int size = aVar.size();
        int i10 = 0;
        for (int i11 = 0; i11 < size; i11++) {
            if (!Double.isNaN(((Sj.b) aVar.get(i11)).d())) {
                i10++;
            }
        }
        return i10;
    }

    public static Qf.p h(LargeOrderItem largeOrderItem) {
        String id2 = largeOrderItem.getId();
        if (id2 != null) {
            if (Ah.y.j0(id2)) {
                id2 = null;
            }
            if (id2 != null) {
                String platform = largeOrderItem.getPlatform();
                if (platform == null) {
                    platform = "";
                }
                return Qf.w.a(platform, id2);
            }
        }
        return null;
    }

    public static LinkedHashMap i(Map map) {
        LinkedHashMap linkedHashMap = new LinkedHashMap(map.size());
        for (Map.Entry entry : Sf.z.d1(map.entrySet(), new C())) {
            linkedHashMap.put((String) entry.getKey(), (List) entry.getValue());
        }
        return linkedHashMap;
    }

    public static void k(List list, HashMap map) {
        map.clear();
        int i10 = 0;
        for (Object obj : list) {
            int i11 = i10 + 1;
            if (i10 < 0) {
                Sf.r.x();
            }
            Qf.p pVarH = h((LargeOrderItem) obj);
            if (pVarH != null) {
                map.putIfAbsent(pVarH, Integer.valueOf(i10));
            }
            i10 = i11;
        }
    }

    public static void l(List list, HashMap map, LargeOrderItem largeOrderItem) {
        Qf.p pVarH = h(largeOrderItem);
        Integer num = pVarH != null ? (Integer) map.get(pVarH) : null;
        if (num != null) {
            list.set(num.intValue(), largeOrderItem);
            return;
        }
        list.add(largeOrderItem);
        if (pVarH != null) {
            map.put(pVarH, Integer.valueOf(Sf.r.p(list)));
        }
    }

    public static void m(List list, List list2, AISRLItem aISRLItem, boolean z10) {
        if (aISRLItem.getPrice() == 0.0d) {
            return;
        }
        Iterator it = list.iterator();
        int i10 = 0;
        while (true) {
            if (!it.hasNext()) {
                i10 = -1;
                break;
            } else if (((AISRLItem) it.next()).getPrice() == aISRLItem.getPrice()) {
                break;
            } else {
                i10++;
            }
        }
        if (i10 != -1) {
            list.remove(i10);
        }
        if (aISRLItem.getAmount() == 0.0d) {
            return;
        }
        list.add(AISRLItem.copy$default(aISRLItem, 0.0d, 0.0d, null, 0, 15, null));
        if (z10) {
            AbstractC2808w.J(list2, new C2758w(aISRLItem));
        } else {
            AbstractC2808w.J(list2, new C2761x(aISRLItem));
        }
    }

    public static final boolean n(long j10, Sj.h hVar) {
        return hVar.e() == j10;
    }

    public static final boolean o(AISRLItem aISRLItem, AISRLItem aISRLItem2) {
        return aISRLItem2.getPrice() >= aISRLItem.getPrice();
    }

    public static final boolean q(AISRLItem aISRLItem, AISRLItem aISRLItem2) {
        return aISRLItem2.getPrice() <= aISRLItem.getPrice();
    }

    public final List A() {
        return this.f19675u;
    }

    public final int B() {
        return this.f19663i.size();
    }

    public final Sj.a C() {
        ak.d dVar = this.f19662h;
        return dVar == ak.d.NORMAL ? this.f19663i : this.f19664j.e(dVar);
    }

    public final int D() {
        return Math.max(0, B() - 400);
    }

    public final DrawingItem[] E() {
        return this.f19656I;
    }

    public final EstimatedLiqVpcTimePoints F() {
        return this.f19677w;
    }

    /* JADX WARN: Multi-variable type inference failed */
    public final long G() {
        if (D() == 0) {
            return 0L;
        }
        return ((Sj.b) C().get(0)).e();
    }

    public final List H() {
        return this.f19674t;
    }

    public final Map I() {
        return this.f19665k;
    }

    public final ak.d J() {
        return this.f19662h;
    }

    public final List K() {
        return this.f19672r;
    }

    public final List L() {
        return this.f19673s;
    }

    /* JADX WARN: Multi-variable type inference failed */
    public final Sj.b M() {
        if (D() == 0 || D() == 0) {
            return null;
        }
        return (Sj.b) C().get(D() - 1);
    }

    /* JADX WARN: Multi-variable type inference failed */
    public final long N() {
        if (D() == 0) {
            return 0L;
        }
        if ((D() == 0 ? null : (Sj.b) C().get(D() - 1)) == null) {
            return 0L;
        }
        return (D() != 0 ? (Sj.b) C().get(D() - 1) : null).e();
    }

    public final List O() {
        return this.f19676v;
    }

    public final LinkedHashMap P() {
        return this.f19655H;
    }

    public final List Q() {
        return this.f19666l;
    }

    public final List R() {
        return this.f19679y;
    }

    public final List S() {
        return this.f19680z;
    }

    public final Map T() {
        return this.f19652E;
    }

    public final List U() {
        return this.f19651D;
    }

    public final double V() {
        return this.f19660M;
    }

    public final Map W() {
        return this.f19648A;
    }

    public final int X() {
        return this.f19657J;
    }

    public final List Y() {
        return this.f19678x;
    }

    public final List Z() {
        return this.f19649B;
    }

    public final List a0() {
        return this.f19650C;
    }

    public final void b0(DrawingItem[] drawingItemArr) {
        this.f19656I = drawingItemArr;
    }

    public final void c0(Map map) {
        this.f19652E = map;
        ArrayList arrayList = new ArrayList(map.size());
        Iterator it = map.entrySet().iterator();
        while (it.hasNext()) {
            arrayList.add((List) ((Map.Entry) it.next()).getValue());
        }
        ArrayList arrayList2 = new ArrayList();
        for (Object obj : arrayList) {
            if (!((List) obj).isEmpty()) {
                arrayList2.add(obj);
            }
        }
        this.f19651D = arrayList2;
    }

    public final void d0(double d10) {
        if (d10 < 0.0d) {
            this.f19658K = false;
            this.f19659L = 0L;
        }
        KLineManager.f142490O.a().Q0(d10);
        this.f19660M = d10;
    }

    public final void e0(int i10) {
        this.f19657J = i10;
    }

    public final void f0(List list) {
        this.f19650C = list;
    }

    public final synchronized void g0(AISRLData aISRLData, boolean z10) {
        try {
            if (z10) {
                this.f19654G.setAmountUnit(aISRLData.getAmountUnit());
                List<AISRLItem> askList = this.f19654G.getAskList();
                List<AISRLItem> bidList = this.f19654G.getBidList();
                List<AISRLItem> askList2 = aISRLData.getAskList();
                askList.clear();
                Iterator<T> it = askList2.iterator();
                while (it.hasNext()) {
                    m(askList, bidList, (AISRLItem) it.next(), true);
                }
                List<AISRLItem> bidList2 = this.f19654G.getBidList();
                List<AISRLItem> askList3 = this.f19654G.getAskList();
                List<AISRLItem> bidList3 = aISRLData.getBidList();
                bidList2.clear();
                Iterator<T> it2 = bidList3.iterator();
                while (it2.hasNext()) {
                    m(bidList2, askList3, (AISRLItem) it2.next(), false);
                }
                List<AISRLItem> askList4 = this.f19654G.getAskList();
                if (askList4.size() > 1) {
                    AbstractC2807v.C(askList4, new A());
                }
                List<AISRLItem> bidList4 = this.f19654G.getBidList();
                if (bidList4.size() > 1) {
                    AbstractC2807v.C(bidList4, new B());
                }
            } else {
                if (!Ah.y.j0(aISRLData.getAmountUnit())) {
                    this.f19654G.setAmountUnit(aISRLData.getAmountUnit());
                }
                List<AISRLItem> askList5 = this.f19654G.getAskList();
                List<AISRLItem> bidList5 = this.f19654G.getBidList();
                Iterator<T> it3 = aISRLData.getAskList().iterator();
                while (it3.hasNext()) {
                    m(askList5, bidList5, (AISRLItem) it3.next(), true);
                }
                List<AISRLItem> bidList6 = this.f19654G.getBidList();
                List<AISRLItem> askList6 = this.f19654G.getAskList();
                Iterator<T> it4 = aISRLData.getBidList().iterator();
                while (it4.hasNext()) {
                    m(bidList6, askList6, (AISRLItem) it4.next(), false);
                }
                List<AISRLItem> askList7 = this.f19654G.getAskList();
                if (askList7.size() > 1) {
                    AbstractC2807v.C(askList7, new A());
                }
                List<AISRLItem> bidList7 = this.f19654G.getBidList();
                if (bidList7.size() > 1) {
                    AbstractC2807v.C(bidList7, new B());
                }
            }
        } catch (Throwable th2) {
            throw th2;
        }
    }

    public final void h0(List list, boolean z10) {
        this.f19675u.clear();
        this.f19675u.addAll(list);
    }

    public final void i0(lk.a aVar) {
        m0(this.f19663i, aVar, true);
    }

    public final void j(List list) {
        p167hg.M m10 = new p167hg.M();
        p167hg.M m11 = new p167hg.M();
        Iterator it = list.iterator();
        while (it.hasNext()) {
            LargeOrderItem largeOrderItem = (LargeOrderItem) it.next();
            Qf.p pVarH = h(largeOrderItem);
            if (AbstractC7609s.f(largeOrderItem.getDepth_state(), "0") || AbstractC7609s.f(largeOrderItem.getDepth_state(), SdkVersion.MINI_VERSION)) {
                if (pVarH != null && this.f19670p.containsKey(pVarH)) {
                    List listU1 = (List) m10.f97909a;
                    if (listU1 == null) {
                        listU1 = Sf.z.u1(this.f19668n);
                        m10.f97909a = listU1;
                    }
                    HashMap map = this.f19670p;
                    Integer num = (Integer) map.get(pVarH);
                    if (num != null) {
                        listU1.remove(num.intValue());
                        k(listU1, map);
                    }
                }
                List listU2 = (List) m11.f97909a;
                if (listU2 == null) {
                    listU2 = Sf.z.u1(this.f19669o);
                    m11.f97909a = listU2;
                }
                l(listU2, this.f19671q, largeOrderItem);
            } else {
                if (pVarH != null && this.f19671q.containsKey(pVarH)) {
                    List listU3 = (List) m11.f97909a;
                    if (listU3 == null) {
                        listU3 = Sf.z.u1(this.f19669o);
                        m11.f97909a = listU3;
                    }
                    HashMap map2 = this.f19671q;
                    Integer num2 = (Integer) map2.get(pVarH);
                    if (num2 != null) {
                        listU3.remove(num2.intValue());
                        k(listU3, map2);
                    }
                }
                List listU4 = (List) m10.f97909a;
                if (listU4 == null) {
                    listU4 = Sf.z.u1(this.f19668n);
                    m10.f97909a = listU4;
                }
                l(listU4, this.f19670p, largeOrderItem);
            }
        }
        List list2 = (List) m10.f97909a;
        if (list2 != null) {
            this.f19668n = list2;
        }
        List list3 = (List) m11.f97909a;
        if (list3 != null) {
            this.f19669o = list3;
        }
    }

    public final void j0(EstimatedLiqVpcTimePoints estimatedLiqVpcTimePoints) {
        Qf.p pVarA;
        if (estimatedLiqVpcTimePoints == null) {
            this.f19677w = null;
            return;
        }
        EstimatedLiqVpcTimePoints estimatedLiqVpcTimePoints2 = this.f19677w;
        if (estimatedLiqVpcTimePoints2 == null) {
            this.f19677w = estimatedLiqVpcTimePoints.copyWithValues(i(estimatedLiqVpcTimePoints.getValues()));
            return;
        }
        if (!AbstractC7609s.f(estimatedLiqVpcTimePoints2.getColumns(), estimatedLiqVpcTimePoints.getColumns()) || !AbstractC7609s.f(estimatedLiqVpcTimePoints2.getName(), estimatedLiqVpcTimePoints.getName())) {
            this.f19677w = estimatedLiqVpcTimePoints.copyWithValues(i(estimatedLiqVpcTimePoints.getValues()));
            return;
        }
        Map<String, List<EstimatedLiqVpcRecord>> values = estimatedLiqVpcTimePoints2.getValues();
        Map<String, List<EstimatedLiqVpcRecord>> values2 = estimatedLiqVpcTimePoints.getValues();
        if (values2.isEmpty()) {
            pVarA = Qf.w.a(new LinkedHashMap(values), Boolean.FALSE);
        } else {
            LinkedHashMap linkedHashMapI = i(values2);
            if (linkedHashMapI.isEmpty()) {
                pVarA = Qf.w.a(new LinkedHashMap(values), Boolean.FALSE);
            } else {
                String str = (String) Sf.z.p0(values.keySet());
                Long lR = str != null ? Ah.w.r(str) : null;
                String str2 = (String) Sf.z.C0(values.keySet());
                Long lR2 = str2 != null ? Ah.w.r(str2) : null;
                String str3 = (String) Sf.z.p0(linkedHashMapI.keySet());
                Long lR3 = str3 != null ? Ah.w.r(str3) : null;
                String str4 = (String) Sf.z.C0(linkedHashMapI.keySet());
                Long lR4 = str4 != null ? Ah.w.r(str4) : null;
                if (lR != null && lR4 != null && lR4.longValue() < lR.longValue()) {
                    LinkedHashMap linkedHashMap = new LinkedHashMap(values.size() + linkedHashMapI.size());
                    linkedHashMap.putAll(linkedHashMapI);
                    linkedHashMap.putAll(values);
                    pVarA = Qf.w.a(linkedHashMap, Boolean.TRUE);
                } else if (lR2 == null || lR3 == null || lR3.longValue() <= lR2.longValue()) {
                    LinkedHashMap linkedHashMap2 = new LinkedHashMap(values);
                    boolean z10 = false;
                    for (Map.Entry entry : linkedHashMapI.entrySet()) {
                        String str5 = (String) entry.getKey();
                        List list = (List) entry.getValue();
                        if (!AbstractC7609s.f((List) linkedHashMap2.get(str5), list)) {
                            linkedHashMap2.put(str5, list);
                            z10 = true;
                        }
                    }
                    pVarA = !z10 ? Qf.w.a(new LinkedHashMap(values), Boolean.FALSE) : Qf.w.a(i(linkedHashMap2), Boolean.TRUE);
                } else {
                    LinkedHashMap linkedHashMap3 = new LinkedHashMap(linkedHashMapI.size() + values.size());
                    linkedHashMap3.putAll(values);
                    linkedHashMap3.putAll(linkedHashMapI);
                    pVarA = Qf.w.a(linkedHashMap3, Boolean.TRUE);
                }
            }
        }
        LinkedHashMap linkedHashMap4 = (LinkedHashMap) pVarA.a();
        if (((Boolean) pVarA.b()).booleanValue()) {
            this.f19677w = estimatedLiqVpcTimePoints2.copyWithValues(linkedHashMap4);
        }
    }

    public final void k0(List list, boolean z10) {
        this.f19674t.clear();
        this.f19674t.addAll(list);
    }

    public final void l0(Map map, boolean z10, boolean z11) {
        String str;
        String str2;
        int i10 = 0;
        if (z10) {
            if (map.keySet().isEmpty()) {
                return;
            }
            Map map2 = this.f19665k;
            if (map2.isEmpty()) {
                Iterator it = map.keySet().iterator();
                while (it.hasNext()) {
                    map2.put((String) it.next(), new Sj.g(new ArrayList(), new ArrayList()));
                }
            }
            for (Map.Entry entry : map2.entrySet()) {
                Sj.g gVar = (Sj.g) map.get((String) entry.getKey());
                List listA = gVar != null ? gVar.a() : null;
                List listB = gVar != null ? gVar.b() : null;
                List listB2 = ((Sj.g) entry.getValue()).b();
                if (!listB2.isEmpty()) {
                    int i11 = 0;
                    boolean z12 = true;
                    for (Object obj : listB2) {
                        int i12 = i11 + 1;
                        if (i11 < 0) {
                            Sf.r.x();
                        }
                        String str3 = (String) obj;
                        if (listB == null || (str2 = (String) Sf.z.r0(listB, i11)) == null) {
                            str2 = "";
                        }
                        if (!AbstractC7609s.f(str3, str2)) {
                            z12 = false;
                        }
                        i11 = i12;
                    }
                    if (!z12) {
                        if (listA == null) {
                            listA = null;
                        } else {
                            int size = listA.size();
                            ArrayList arrayList = new ArrayList(size);
                            for (int i13 = 0; i13 < size; i13++) {
                                int size2 = listB2.size();
                                ArrayList arrayList2 = new ArrayList(size2);
                                for (int i14 = 0; i14 < size2; i14++) {
                                    arrayList2.add("");
                                }
                                arrayList.add(arrayList2);
                            }
                            int i15 = 0;
                            for (Object obj2 : listB2) {
                                int i16 = i15 + 1;
                                if (i15 < 0) {
                                    Sf.r.x();
                                }
                                Integer numH = nk.z.h(listB, (String) obj2);
                                int iIntValue = numH != null ? numH.intValue() : 0;
                                int i17 = 0;
                                for (Object obj3 : listA) {
                                    int i18 = i17 + 1;
                                    if (i17 < 0) {
                                        Sf.r.x();
                                    }
                                    List list = (List) arrayList.get(i17);
                                    String str4 = (String) Sf.z.r0((List) obj3, iIntValue);
                                    if (str4 == null) {
                                        str4 = "";
                                    }
                                    list.set(i15, str4);
                                    i17 = i18;
                                }
                                i15 = i16;
                            }
                            listA = arrayList;
                        }
                    }
                    if (listA == null && !listA.isEmpty()) {
                        ((Sj.g) entry.getValue()).a().addAll(0, Sf.z.r1(listA));
                    }
                } else if (listB != null) {
                    listB2.addAll(listB);
                }
                if (listA == null) {
                }
            }
            return;
        }
        int i19 = 1;
        Map map3 = this.f19665k;
        if (map3.isEmpty() || z11) {
            map3.clear();
            map3.putAll(map);
            return;
        }
        for (Map.Entry entry2 : map3.entrySet()) {
            Sj.g gVar2 = (Sj.g) map.get((String) entry2.getKey());
            List listA2 = gVar2 != null ? gVar2.a() : null;
            List listB3 = gVar2 != null ? gVar2.b() : null;
            List listA3 = ((Sj.g) entry2.getValue()).a();
            List listB4 = ((Sj.g) entry2.getValue()).b();
            int i20 = i10;
            for (Object obj4 : listB4) {
                int i21 = i20 + 1;
                if (i20 < 0) {
                    Sf.r.x();
                }
                String str5 = (String) obj4;
                if (listB3 == null || (str = (String) listB3.get(i20)) == null) {
                    str = "";
                }
                if (!AbstractC7609s.f(str5, str)) {
                    if (listA2 != null) {
                        int size3 = listA2.size();
                        ArrayList arrayList3 = new ArrayList(size3);
                        for (int i22 = i10; i22 < size3; i22++) {
                            int size4 = listB4.size();
                            ArrayList arrayList4 = new ArrayList(size4);
                            for (int i23 = i10; i23 < size4; i23++) {
                                arrayList4.add("");
                            }
                            arrayList3.add(arrayList4);
                        }
                        int i24 = i10;
                        for (Object obj5 : listB4) {
                            int i25 = i24 + 1;
                            if (i24 < 0) {
                                Sf.r.x();
                            }
                            Integer numH2 = nk.z.h(listB3, (String) obj5);
                            int iIntValue2 = numH2 != null ? numH2.intValue() : i10;
                            int i26 = i10;
                            for (Object obj6 : listA2) {
                                int i27 = i26 + 1;
                                if (i26 < 0) {
                                    Sf.r.x();
                                }
                                List list2 = (List) arrayList3.get(i26);
                                String str6 = (String) Sf.z.r0((List) obj6, iIntValue2);
                                if (str6 == null) {
                                    str6 = "";
                                }
                                list2.set(i24, str6);
                                i26 = i27;
                                i10 = 0;
                            }
                            i24 = i25;
                        }
                        listA2 = arrayList3;
                        break;
                    }
                    listA2 = null;
                    break;
                }
                i20 = i21;
            }
            if (listA2 != null && !listA2.isEmpty()) {
                if (listA2.size() > listA3.size()) {
                    listA3.clear();
                    listA3.addAll(listA2);
                } else {
                    List listK = nk.z.k(listA3);
                    int iE = ak.c.e(ak.c.f28342a, listB4, 0, 2, null);
                    Long lR = Ah.w.r((String) listK.get(iE));
                    long jLongValue = lR != null ? lR.longValue() : 0L;
                    ArrayList<List> arrayList5 = new ArrayList();
                    arrayList5.addAll(listA2);
                    Iterator it2 = listA2.iterator();
                    int i28 = 0;
                    while (true) {
                        if (!it2.hasNext()) {
                            listA3.addAll(listA2);
                            break;
                        }
                        Object next = it2.next();
                        int i29 = i28 + 1;
                        if (i28 < 0) {
                            Sf.r.x();
                        }
                        Long lR2 = Ah.w.r((String) ((List) next).get(iE));
                        if ((lR2 != null ? lR2.longValue() : 0L) == jLongValue) {
                            listA3.remove(Sf.r.p(listA3) - 1);
                            listA3.remove(Sf.r.p(listA3));
                            for (List list3 : arrayList5) {
                                if (list3 != null && !list3.isEmpty()) {
                                    listA3.add(list3);
                                }
                            }
                            break;
                        }
                        int i30 = i19;
                        if (i28 >= i30) {
                            arrayList5.remove(listA2.get(i28 - 1));
                        }
                        i19 = i30;
                        i28 = i29;
                    }
                    i10 = 0;
                }
            }
            i10 = 0;
        }
    }

    /* JADX WARN: Multi-variable type inference failed */
    public final void m0(Sj.a aVar, lk.a aVar2, boolean z10) {
        int size = aVar2.a().size();
        if (D() > 0) {
            nk.p pVar = nk.p.f134232a;
            pVar.c("updateKline", "已经有数据在本地，更新最新柱: dataRealCount = [" + D() + ']');
            Sj.b bVar = D() == 0 ? null : (Sj.b) this.f19663i.get(D() - 1);
            if (bVar == null) {
                return;
            }
            pVar.c("updateKline", "在请求返回的数据中找到该数据");
            int i10 = 0;
            Sj.b bVar2 = null;
            while (i10 < size) {
                bVar2 = (Sj.b) aVar2.a().get(i10);
                if (bVar2.e() == bVar.e()) {
                    break;
                } else {
                    i10++;
                }
            }
            if (i10 >= size) {
                if (z10) {
                    Sj.b bVar3 = (Sj.b) aVar.get(0);
                    Iterator it = aVar2.a().iterator();
                    while (it.hasNext()) {
                        if (((Sj.b) it.next()).e() < bVar3.e()) {
                            this.f19657J = 4;
                            for (int i11 = 0; i11 < size; i11++) {
                                Sj.b bVar4 = (Sj.b) aVar2.a().get((size - 1) - i11);
                                if (bVar4.e() < bVar3.e()) {
                                    aVar.add(0, new Sj.b(bVar4));
                                }
                            }
                            break;
                        }
                    }
                }
            } else {
                nk.p pVar2 = nk.p.f134232a;
                pVar2.a("updateKline", "找到了");
                if (bVar2.d() == bVar.d() && bVar2.b() == bVar.b() && bVar2.c() == bVar.c() && bVar2.a() == bVar.a() && bVar2.f() == bVar.f()) {
                    pVar2.a("updateKline", "若数据无更新UPDATE_MODE_DO_NOTHING");
                    this.f19657J = 0;
                } else {
                    this.f19657J = 2;
                    if (nk.z.a(aVar, D() - 1)) {
                        aVar.set(D() - 1, new Sj.b(bVar2));
                        pVar2.a("updateKline", "数据有更新, 更新最后一条数据");
                    }
                }
                int i12 = i10 + 1;
                pVar2.a("updateKline", "添加新数据");
                if (i12 < size) {
                    this.f19657J = 3;
                    pVar2.a("updateKline", i12 + " < " + size);
                    while (i12 < size) {
                        Sj.b bVar5 = (Sj.b) aVar2.a().get(i12);
                        Sj.b bVar6 = (Sj.b) Sf.z.r0(aVar, D() - 1);
                        if (AbstractC7609s.a(bVar5.d(), bVar6 != null ? Double.valueOf(bVar6.d()) : null) && bVar5.b() == bVar6.b() && bVar5.c() == bVar6.c() && bVar5.a() == bVar6.a() && bVar5.f() == bVar6.f() && bVar5.e() == bVar6.e()) {
                            nk.p.f134232a.a("updateKline", "若数据无更新do nothing");
                        } else {
                            nk.p.f134232a.a("updateKline", "数据有更新，添加新数据");
                            aVar.add(g(aVar), new Sj.b(bVar5));
                            long jE = ((Sj.b) aVar.get(g(aVar) - 1)).e();
                            GregorianCalendar gregorianCalendar = new GregorianCalendar();
                            gregorianCalendar.setTime(new Date(jE));
                            int i13 = 0;
                            while (i13 < 400) {
                                int i14 = i13;
                                gregorianCalendar.add(13, (int) (this.f19661g / ((long) 1000)));
                                int iG = g(aVar) + i14;
                                if (iG < aVar.size()) {
                                    aVar.set(iG, new Sj.b(gregorianCalendar.getTime().getTime(), Double.NaN, Double.NaN, Double.NaN, Double.NaN, Double.NaN));
                                }
                                i13 = i14 + 1;
                            }
                        }
                        i12++;
                    }
                }
            }
        } else {
            this.f19657J = 1;
            aVar.clear();
            this.f19664j.b();
            for (int i15 = 0; i15 < size; i15++) {
                aVar.add(new Sj.b((Sj.b) aVar2.a().get(i15)));
            }
            if (aVar2.a().size() <= 1) {
                return;
            }
            this.f19661g = ((Sj.b) aVar2.a().get(1)).e() - ((Sj.b) aVar2.a().get(0)).e();
            long jE2 = ((Sj.b) aVar2.a().get(aVar2.a().size() - 1)).e();
            GregorianCalendar gregorianCalendar2 = new GregorianCalendar();
            gregorianCalendar2.setTime(new Date(jE2));
            for (int i16 = 0; i16 < 400; i16++) {
                gregorianCalendar2.add(13, (int) (this.f19661g / ((long) 1000)));
                aVar.add(new Sj.b(gregorianCalendar2.getTime().getTime(), Double.NaN, Double.NaN, Double.NaN, Double.NaN, Double.NaN));
            }
        }
        this.f19664j.c(aVar, this.f19662h);
        int iMax = Math.max(0, aVar.size() - 400) - 1;
        if (nk.z.a(aVar, iMax)) {
            Sj.b bVar7 = (Sj.b) aVar.get(iMax);
            double d10 = this.f19664j.d(bVar7, D() - 1, bVar7.a(), this.f19662h);
            if (this.f19658K) {
                if (System.currentTimeMillis() - this.f19659L <= 10000) {
                    nk.p.f134232a.a("updateKline", "保留socket实时价，避免HTTP收盘价覆盖");
                    return;
                } else {
                    this.f19658K = false;
                    this.f19659L = 0L;
                }
            }
            this.f19658K = false;
            this.f19659L = 0L;
            d0(d10);
        }
    }

    public final void n0(ak.d dVar) {
        this.f19662h = dVar;
        this.f19664j.b();
        this.f19664j.c(this.f19663i, dVar);
    }

    public final void o0(List list, X x10) {
        synchronized (this.f19667m) {
            try {
                int i10 = b.f19681a[x10.ordinal()];
                if (i10 == 1) {
                    p(list);
                } else if (i10 == 2) {
                    j(list);
                } else {
                    if (i10 != 3) {
                        throw new Qf.n();
                    }
                    r(list);
                }
                this.f19672r = new W(this.f19668n, this.f19669o);
                Qf.H h10 = Qf.H.f17640a;
            } catch (Throwable th2) {
                throw th2;
            }
        }
    }

    public final void p(List list) {
        ArrayList arrayList = new ArrayList();
        ArrayList arrayList2 = new ArrayList();
        Iterator it = list.iterator();
        while (it.hasNext()) {
            LargeOrderItem largeOrderItem = (LargeOrderItem) it.next();
            if (AbstractC7609s.f(largeOrderItem.getDepth_state(), "0") || AbstractC7609s.f(largeOrderItem.getDepth_state(), SdkVersion.MINI_VERSION)) {
                arrayList2.add(largeOrderItem);
            } else {
                arrayList.add(largeOrderItem);
            }
        }
        this.f19668n = arrayList;
        this.f19669o = arrayList2;
        k(arrayList, this.f19670p);
        k(this.f19669o, this.f19671q);
    }

    public final void p0(List list, boolean z10) {
        if (!z10) {
            D.a(this.f19673s, list);
        } else {
            this.f19673s.clear();
            this.f19673s.addAll(list);
        }
    }

    public final void q0(List list, boolean z10) {
        this.f19676v.clear();
        this.f19676v.addAll(list);
    }

    public final void r(List list) {
        HashSet hashSet = new HashSet();
        Iterator it = list.iterator();
        while (it.hasNext()) {
            Qf.p pVarH = h((LargeOrderItem) it.next());
            if (pVarH != null) {
                hashSet.add(pVarH);
            }
        }
        HashMap map = this.f19670p;
        if (!hashSet.isEmpty()) {
            Iterator it2 = hashSet.iterator();
            while (it2.hasNext()) {
                if (map.containsKey((Qf.p) it2.next())) {
                    List list2 = this.f19668n;
                    ArrayList arrayList = new ArrayList();
                    for (Object obj : list2) {
                        if (!Sf.z.g0(hashSet, h((LargeOrderItem) obj))) {
                            arrayList.add(obj);
                        }
                    }
                    this.f19668n = arrayList;
                    k(arrayList, this.f19670p);
                    break;
                }
            }
        }
        ArrayList arrayList2 = new ArrayList();
        this.f19671q.clear();
        Iterator it3 = list.iterator();
        while (it3.hasNext()) {
            l(arrayList2, this.f19671q, (LargeOrderItem) it3.next());
        }
        this.f19669o = arrayList2;
    }

    public final void r0(LinkedHashMap linkedHashMap) {
        for (Map.Entry entry : linkedHashMap.entrySet()) {
            String str = (String) entry.getKey();
            lk.a aVar = (lk.a) entry.getValue();
            Sj.a aVar2 = (Sj.a) this.f19655H.get(str);
            if (aVar2 == null) {
                aVar2 = new Sj.a();
                this.f19655H.put(str, aVar2);
            }
            m0(aVar2, aVar, false);
        }
        int size = -1;
        for (Sj.a aVar3 : this.f19655H.values()) {
            if (size != -1 && aVar3.size() != size) {
                this.f19655H.clear();
                this.f19657J = 1;
                return;
            }
            size = aVar3.size();
        }
        this.f19663i.clear();
        this.f19664j.b();
        Iterator it = this.f19655H.entrySet().iterator();
        if (it.hasNext()) {
            this.f19663i.addAll((Sj.a) ((Map.Entry) it.next()).getValue());
        }
    }

    public final void s() {
        C().clear();
        this.f19664j.b();
        this.f19663i.clear();
        this.f19655H.clear();
    }

    public final void s0(List list, boolean z10) {
        if (z10) {
            this.f19666l.addAll(0, list);
            return;
        }
        if (this.f19666l.isEmpty()) {
            this.f19666l.addAll(list);
            return;
        }
        Sj.h hVar = (Sj.h) Sf.z.D0(this.f19666l);
        long jE = hVar != null ? hVar.e() : 0L;
        ArrayList arrayList = new ArrayList();
        arrayList.addAll(list);
        Iterator it = list.iterator();
        while (it.hasNext()) {
            Sj.h hVar2 = (Sj.h) it.next();
            if (hVar2.e() >= jE) {
                break;
            } else {
                arrayList.remove(hVar2);
            }
        }
        AbstractC2808w.J(this.f19666l, new C2763y(jE));
        this.f19666l.addAll(arrayList);
    }

    public final void t() {
        this.f19656I = new DrawingItem[0];
    }

    /* JADX WARN: Multi-variable type inference failed */
    public final void t0(List list, boolean z10) {
        if (!z10) {
            if (this.f19679y.isEmpty()) {
                this.f19679y.addAll(list);
                return;
            }
            Iterator it = list.iterator();
            while (it.hasNext()) {
                ScriptDrawData scriptDrawData = (ScriptDrawData) it.next();
                ScriptIndicConfig config = scriptDrawData.getConfig();
                String id2 = config != null ? config.getId() : null;
                List<ScriptDrawData> list2 = this.f19679y;
                ArrayList arrayList = new ArrayList(AbstractC2804s.y(list2, 10));
                for (ScriptDrawData scriptDrawData2 : list2) {
                    arrayList.add(ScriptDrawData.copy$default(scriptDrawData2, null, null, Sf.N.z(scriptDrawData2.getCalculateHistoryData()), null, 11, null));
                }
                List listU1 = Sf.z.u1(arrayList);
                LinkedHashMap linkedHashMap = new LinkedHashMap(p292ng.i.f(Sf.M.e(AbstractC2804s.y(listU1, 10)), 16));
                for (Object obj : listU1) {
                    ScriptIndicConfig config2 = ((ScriptDrawData) obj).getConfig();
                    linkedHashMap.put(config2 != null ? config2.getId() : null, obj);
                }
                ScriptDrawData scriptDrawData3 = (ScriptDrawData) linkedHashMap.get(id2);
                if (scriptDrawData3 != null) {
                    scriptDrawData3.setCalculateHistoryData(Sf.N.z(Sf.N.s(Sf.N.z(scriptDrawData.getCalculateHistoryData()), Sf.N.z(scriptDrawData3.getCalculateHistoryData()))));
                }
                this.f19679y = listU1;
            }
            return;
        }
        List<ScriptDrawData> list3 = this.f19679y;
        ArrayList arrayList2 = new ArrayList(AbstractC2804s.y(list3, 10));
        for (ScriptDrawData scriptDrawData4 : list3) {
            arrayList2.add(ScriptDrawData.copy$default(scriptDrawData4, null, null, Sf.N.z(scriptDrawData4.getCalculateHistoryData()), null, 11, null));
        }
        List<ScriptDrawData> listU2 = Sf.z.u1(arrayList2);
        Iterator it2 = list.iterator();
        while (it2.hasNext()) {
            ScriptDrawData scriptDrawData5 = (ScriptDrawData) it2.next();
            ScriptIndicConfig config3 = scriptDrawData5.getConfig();
            String id3 = config3 != null ? config3.getId() : null;
            for (ScriptDrawData scriptDrawData6 : listU2) {
                ScriptIndicConfig config4 = scriptDrawData6.getConfig();
                if (AbstractC7609s.f(id3, config4 != null ? config4.getId() : null)) {
                    Map mapZ = Sf.N.z(scriptDrawData6.getCalculateHistoryData());
                    for (Map.Entry entry : Sf.N.z(scriptDrawData5.getCalculateHistoryData()).entrySet()) {
                        Map map = (Map) mapZ.get(entry.getKey());
                        if (map == null) {
                            mapZ.put(entry.getKey(), entry.getValue());
                        } else {
                            mapZ.put(entry.getKey(), map);
                        }
                    }
                    scriptDrawData6.setCalculateHistoryData(mapZ);
                }
            }
        }
        this.f19679y = listU2;
    }

    public String toString() {
        return "" + C();
    }

    public final void u() {
        this.f19665k = new LinkedHashMap();
    }

    public final void u0(List list, boolean z10) {
        if (!z10) {
            if (this.f19680z.isEmpty()) {
                this.f19680z.addAll(list);
                return;
            }
            Iterator it = list.iterator();
            while (it.hasNext()) {
                ScriptDrawData scriptDrawData = (ScriptDrawData) it.next();
                ScriptIndicConfig config = scriptDrawData.getConfig();
                String id2 = config != null ? config.getId() : null;
                List<ScriptDrawData> list2 = this.f19680z;
                ArrayList arrayList = new ArrayList(AbstractC2804s.y(list2, 10));
                for (ScriptDrawData scriptDrawData2 : list2) {
                    arrayList.add(ScriptDrawData.copy$default(scriptDrawData2, null, null, Sf.N.z(scriptDrawData2.getCalculateHistoryData()), null, 11, null));
                }
                List listU1 = Sf.z.u1(arrayList);
                LinkedHashMap linkedHashMap = new LinkedHashMap(p292ng.i.f(Sf.M.e(AbstractC2804s.y(listU1, 10)), 16));
                for (Object obj : listU1) {
                    ScriptIndicConfig config2 = ((ScriptDrawData) obj).getConfig();
                    linkedHashMap.put(config2 != null ? config2.getId() : null, obj);
                }
                ScriptDrawData scriptDrawData3 = (ScriptDrawData) linkedHashMap.get(id2);
                if (scriptDrawData3 != null) {
                    scriptDrawData3.setCalculateHistoryData(Sf.N.z(Sf.N.s(Sf.N.z(scriptDrawData.getCalculateHistoryData()), Sf.N.z(scriptDrawData3.getCalculateHistoryData()))));
                }
                this.f19680z = listU1;
            }
            return;
        }
        List<ScriptDrawData> list3 = this.f19680z;
        ArrayList arrayList2 = new ArrayList(AbstractC2804s.y(list3, 10));
        for (ScriptDrawData scriptDrawData4 : list3) {
            arrayList2.add(ScriptDrawData.copy$default(scriptDrawData4, null, null, Sf.N.z(scriptDrawData4.getCalculateHistoryData()), null, 11, null));
        }
        List<ScriptDrawData> listU2 = Sf.z.u1(arrayList2);
        Iterator it2 = list.iterator();
        while (it2.hasNext()) {
            ScriptDrawData scriptDrawData5 = (ScriptDrawData) it2.next();
            ScriptIndicConfig config3 = scriptDrawData5.getConfig();
            String id3 = config3 != null ? config3.getId() : null;
            for (ScriptDrawData scriptDrawData6 : listU2) {
                ScriptIndicConfig config4 = scriptDrawData6.getConfig();
                if (AbstractC7609s.f(id3, config4 != null ? config4.getId() : null)) {
                    Map<String, Map<String, String>> mapZ = Sf.N.z(scriptDrawData6.getCalculateHistoryData());
                    for (Map.Entry<String, Map<String, String>> entry : scriptDrawData5.getCalculateHistoryData().entrySet()) {
                        Map<String, String> map = mapZ.get(entry.getKey());
                        if (map == null) {
                            mapZ.put(entry.getKey(), entry.getValue());
                        } else {
                            mapZ.put(entry.getKey(), map);
                        }
                    }
                    scriptDrawData6.setCalculateHistoryData(mapZ);
                }
            }
        }
        this.f19680z = listU2;
    }

    public final void v() {
        this.f19666l.clear();
    }

    public final void v0(Map map) {
        LinkedHashMap linkedHashMap = new LinkedHashMap(Sf.M.e(map.size()));
        for (Map.Entry entry : map.entrySet()) {
            linkedHashMap.put(entry.getKey(), Sf.z.V0((Iterable) entry.getValue()));
        }
        c0(linkedHashMap);
    }

    public final void w() {
        this.f19679y.clear();
    }

    /* JADX WARN: Multi-variable type inference failed */
    public final void w0(double d10) {
        int iD = D() - 1;
        if (nk.z.a(this.f19663i, iD)) {
            d10 = this.f19664j.d((Sj.b) this.f19663i.get(iD), iD, d10, this.f19662h);
        }
        boolean z10 = d10 >= 0.0d;
        this.f19658K = z10;
        this.f19659L = z10 ? System.currentTimeMillis() : 0L;
        d0(d10);
    }

    public final void x() {
        this.f19680z.clear();
    }

    public final void x0(Map map, boolean z10, boolean z11) {
        ScriptDrawData scriptDrawData;
        Map<String, Map<String, String>> linkedHashMap;
        if (z10) {
            for (Map.Entry entry : map.entrySet()) {
                String str = (String) entry.getKey();
                ScriptDrawData scriptDrawData2 = (ScriptDrawData) entry.getValue();
                if (this.f19648A.containsKey(str) && (scriptDrawData = (ScriptDrawData) this.f19648A.get(str)) != null) {
                    Map<String, Map<String, String>> mapZ = Sf.N.z(scriptDrawData.getCalculateHistoryData());
                    for (Map.Entry<String, Map<String, String>> entry2 : scriptDrawData2.getCalculateHistoryData().entrySet()) {
                        String key = entry2.getKey();
                        Map<String, String> value = entry2.getValue();
                        Map<String, String> map2 = mapZ.get(key);
                        if (map2 == null) {
                            mapZ.put(key, value);
                        } else {
                            mapZ.put(key, map2);
                        }
                    }
                    scriptDrawData.setCalculateHistoryData(mapZ);
                    this.f19648A.put(str, scriptDrawData);
                }
            }
            return;
        }
        if (this.f19648A.isEmpty()) {
            this.f19648A.putAll(map);
            return;
        }
        if (z11) {
            this.f19648A.clear();
            this.f19648A.putAll(map);
            return;
        }
        for (Map.Entry entry3 : map.entrySet()) {
            String str2 = (String) entry3.getKey();
            ScriptDrawData scriptDrawData3 = (ScriptDrawData) entry3.getValue();
            if (!this.f19648A.containsKey(str2)) {
                this.f19648A.put(str2, scriptDrawData3);
            } else if (this.f19648A.get(str2) != null) {
                Map mapZ2 = Sf.N.z(scriptDrawData3.getCalculateHistoryData());
                ScriptDrawData scriptDrawData4 = (ScriptDrawData) this.f19648A.get(str2);
                if (scriptDrawData4 == null || (linkedHashMap = scriptDrawData4.getCalculateHistoryData()) == null) {
                    linkedHashMap = new LinkedHashMap<>();
                }
                Map mapS = Sf.N.s(mapZ2, linkedHashMap);
                ScriptDrawData scriptDrawData5 = (ScriptDrawData) this.f19648A.get(str2);
                if (scriptDrawData5 != null) {
                    scriptDrawData5.setCalculateHistoryData(Sf.N.z(mapS));
                }
            }
        }
    }

    public final void y() {
        c0(Sf.N.j());
    }

    public final void y0(List list) {
        this.f19678x.clear();
        this.f19678x.addAll(list);
    }

    public final synchronized AISRLData z() {
        return this.f19654G.deepCopy();
    }

    public final void z0(List list, boolean z10) {
        List<AIWinRateItem> listV0 = Sf.z.V0(list);
        if (!z10) {
            for (AIWinRateItem aIWinRateItem : listV0) {
                String str = aIWinRateItem.getId() + ':' + aIWinRateItem.getSignal_time();
                Integer num = (Integer) this.f19653F.get(str);
                if (num != null) {
                    this.f19649B.set(num.intValue(), aIWinRateItem);
                } else {
                    this.f19649B.add(aIWinRateItem);
                    this.f19653F.put(str, Integer.valueOf(Sf.r.p(this.f19649B)));
                }
            }
            return;
        }
        this.f19649B.clear();
        this.f19649B.addAll(listV0);
        this.f19653F.clear();
        LinkedHashMap linkedHashMap = this.f19653F;
        int i10 = 0;
        for (AIWinRateItem aIWinRateItem2 : listV0) {
            linkedHashMap.put(aIWinRateItem2.getId() + ':' + aIWinRateItem2.getSignal_time(), Integer.valueOf(i10));
            i10++;
        }
    }
}
