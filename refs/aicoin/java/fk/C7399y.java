package fk;

import Rj.AbstractC2744r0;
import Rj.AbstractC2755v;
import Rj.AbstractC2759w0;
import Rj.C2702d;
import Rj.C2732n;
import Rj.C2741q;
import Rj.C2765z;
import Rj.y1;
import Sf.AbstractC2801o;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.ListIterator;
import java.util.Locale;
import java.util.Map;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.chart.Chart;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: fk.y, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7399y extends AbstractC2744r0 {

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public static final a f95584C = new a(null);

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public static final Handler f95585D = new Handler(Looper.getMainLooper());

    /* JADX INFO: renamed from: E, reason: collision with root package name */
    public static final HashMap f95586E = new HashMap();

    /* JADX INFO: renamed from: F, reason: collision with root package name */
    public static final HashMap f95587F = new HashMap();

    /* JADX INFO: renamed from: G, reason: collision with root package name */
    public static final int f95588G = Color.parseColor("#E8ECEF");

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public final HashMap f95589A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public final ArrayList f95590B;

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public gk.V f95591l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public C2702d f95592m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public y1 f95593n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public AbstractC2759w0 f95594o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public boolean f95595p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final Paint f95596q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final Paint f95597r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public Map f95598s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public List f95599t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public final HashMap f95600u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public Sj.a f95601v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public int f95602w;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public long f95603x;

    /* JADX INFO: renamed from: y, reason: collision with root package name */
    public long f95604y;

    /* JADX INFO: renamed from: z, reason: collision with root package name */
    public final ArrayList f95605z;

    /* JADX INFO: renamed from: fk.y$a */
    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }

        public final void a(String str) {
            C7399y.f95586E.remove(str);
            C7399y.f95587F.remove(str);
        }

        public final Sj.e b(String str) {
            return (Sj.e) C7399y.f95586E.get(str);
        }

        public final boolean c(String str) {
            return C7399y.f95586E.containsKey(str);
        }

        public final void d(String str, Sj.e eVar) {
            C7399y.f95586E.put(str, eVar);
        }
    }

    /* JADX INFO: renamed from: fk.y$b */
    public static final class b {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public final int f95606a;

        /* JADX INFO: renamed from: b, reason: collision with root package name */
        public final int f95607b;

        /* JADX INFO: renamed from: c, reason: collision with root package name */
        public final float f95608c;

        /* JADX INFO: renamed from: d, reason: collision with root package name */
        public final float f95609d;

        /* JADX INFO: renamed from: e, reason: collision with root package name */
        public final float f95610e;

        /* JADX INFO: renamed from: f, reason: collision with root package name */
        public final float f95611f;

        /* JADX INFO: renamed from: g, reason: collision with root package name */
        public final String f95612g;

        /* JADX INFO: renamed from: h, reason: collision with root package name */
        public final String f95613h;

        /* JADX INFO: renamed from: i, reason: collision with root package name */
        public final int f95614i;

        public b(int i10, int i11, float f10, float f11, float f12, float f13, String str, String str2, int i12) {
            this.f95606a = i10;
            this.f95607b = i11;
            this.f95608c = f10;
            this.f95609d = f11;
            this.f95610e = f12;
            this.f95611f = f13;
            this.f95612g = str;
            this.f95613h = str2;
            this.f95614i = i12;
        }

        public final boolean a(float f10, float f11) {
            return f10 >= this.f95608c && f10 <= this.f95610e && f11 >= this.f95609d && f11 <= this.f95611f;
        }

        public final float b() {
            return this.f95611f;
        }

        public final int c() {
            return this.f95606a;
        }

        public final int d() {
            return this.f95614i;
        }

        public final String e() {
            return this.f95613h;
        }

        public boolean equals(Object obj) {
            if (this == obj) {
                return true;
            }
            if (!(obj instanceof b)) {
                return false;
            }
            b bVar = (b) obj;
            return this.f95606a == bVar.f95606a && this.f95607b == bVar.f95607b && Float.compare(this.f95608c, bVar.f95608c) == 0 && Float.compare(this.f95609d, bVar.f95609d) == 0 && Float.compare(this.f95610e, bVar.f95610e) == 0 && Float.compare(this.f95611f, bVar.f95611f) == 0 && AbstractC7609s.f(this.f95612g, bVar.f95612g) && AbstractC7609s.f(this.f95613h, bVar.f95613h) && this.f95614i == bVar.f95614i;
        }

        public final float f() {
            return this.f95609d;
        }

        public final String g() {
            return this.f95612g;
        }

        public int hashCode() {
            return Integer.hashCode(this.f95614i) + kk.d.a(this.f95613h, kk.d.a(this.f95612g, kk.a.a(this.f95611f, kk.a.a(this.f95610e, kk.a.a(this.f95609d, kk.a.a(this.f95608c, (Integer.hashCode(this.f95607b) + (Integer.hashCode(this.f95606a) * 31)) * 31, 31), 31), 31), 31), 31), 31);
        }

        public String toString() {
            return "HeatRectSlot(col=" + this.f95606a + ", row=" + this.f95607b + ", left=" + this.f95608c + ", top=" + this.f95609d + ", right=" + this.f95610e + ", bottom=" + this.f95611f + ", turnoverText=" + this.f95612g + ", midPriceText=" + this.f95613h + ", fillColor=" + this.f95614i + ')';
        }
    }

    /* JADX INFO: renamed from: fk.y$c */
    public static final class c {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public final int f95615a;

        /* JADX INFO: renamed from: b, reason: collision with root package name */
        public final float f95616b;

        /* JADX INFO: renamed from: c, reason: collision with root package name */
        public final List f95617c;

        public c(int i10, float f10, List list) {
            this.f95615a = i10;
            this.f95616b = f10;
            this.f95617c = list;
        }

        public final float a() {
            return this.f95616b;
        }

        public final int b() {
            return this.f95615a;
        }

        public final List c() {
            return this.f95617c;
        }

        public boolean equals(Object obj) {
            if (this == obj) {
                return true;
            }
            if (!(obj instanceof c)) {
                return false;
            }
            c cVar = (c) obj;
            return this.f95615a == cVar.f95615a && Float.compare(this.f95616b, cVar.f95616b) == 0 && AbstractC7609s.f(this.f95617c, cVar.f95617c);
        }

        public int hashCode() {
            return this.f95617c.hashCode() + kk.a.a(this.f95616b, Integer.hashCode(this.f95615a) * 31, 31);
        }

        public String toString() {
            return "MappedHeatColumn(dataIndex=" + this.f95615a + ", centerX=" + this.f95616b + ", records=" + this.f95617c + ')';
        }
    }

    public C7399y(C2732n c2732n, String str) {
        super(c2732n, str);
        Paint paint = new Paint();
        paint.setStyle(Paint.Style.FILL);
        paint.setAntiAlias(false);
        this.f95596q = paint;
        Paint paint2 = new Paint(1);
        paint2.setColor(-16777216);
        paint2.setTextAlign(Paint.Align.CENTER);
        paint2.setTextSize(12.0f);
        this.f95597r = paint2;
        this.f95599t = Sf.r.n();
        this.f95600u = new HashMap();
        this.f95602w = -1;
        this.f95603x = Long.MIN_VALUE;
        this.f95604y = Long.MIN_VALUE;
        this.f95605z = new ArrayList();
        this.f95589A = new HashMap();
        this.f95590B = new ArrayList();
    }

    public static final void x(String str, long j10, C7399y c7399y) {
        Long l10 = (Long) f95587F.get(str);
        if (l10 != null && l10.longValue() == j10) {
            f95584C.a(str);
            Chart chartA = c7399y.i().a();
            if (chartA != null) {
                chartA.invalidate();
            }
        }
    }

    public final b A(int i10, b bVar) {
        List<b> list = (List) this.f95589A.get(Integer.valueOf(i10));
        if (list == null) {
            return null;
        }
        float f10 = (bVar.f() + bVar.b()) / 2.0f;
        float f11 = Float.POSITIVE_INFINITY;
        b bVar2 = null;
        for (b bVar3 : list) {
            float f12 = (bVar3.f() + bVar3.b()) / 2.0f;
            if (f12 > f10 && f12 < f11) {
                bVar2 = bVar3;
                f11 = f12;
            }
        }
        if (bVar2 == null) {
            return null;
        }
        float f13 = bVar2.f() - bVar.b();
        if (f13 > 0.0f && f13 > (Math.max(bVar.b() - bVar.f(), bVar2.b() - bVar2.f()) * 0.45f) + 2.0f) {
            return null;
        }
        return bVar2;
    }

    /* JADX WARN: Code duplicated, block: B:100:0x0205  */
    /* JADX WARN: Code duplicated, block: B:102:0x0223  */
    /* JADX WARN: Code duplicated, block: B:103:0x022a  */
    /* JADX WARN: Code duplicated, block: B:112:0x0248  */
    /* JADX WARN: Code duplicated, block: B:114:0x024f  */
    /* JADX WARN: Code duplicated, block: B:116:0x0256  */
    /* JADX WARN: Code duplicated, block: B:119:0x0272  */
    /* JADX WARN: Code duplicated, block: B:121:0x027c  */
    /* JADX WARN: Code duplicated, block: B:123:0x0284  */
    /* JADX WARN: Code duplicated, block: B:126:0x028f  */
    /* JADX WARN: Code duplicated, block: B:129:0x029a  */
    /* JADX WARN: Code duplicated, block: B:130:0x02a9  */
    /* JADX WARN: Code duplicated, block: B:133:0x02b1  */
    /* JADX WARN: Code duplicated, block: B:135:0x02c5  */
    /* JADX WARN: Code duplicated, block: B:137:0x02cc  */
    /* JADX WARN: Code duplicated, block: B:138:0x02da  */
    /* JADX WARN: Code duplicated, block: B:140:0x02e1  */
    /* JADX WARN: Code duplicated, block: B:141:0x02f0  */
    /* JADX WARN: Code duplicated, block: B:145:0x02f7  */
    /* JADX WARN: Code duplicated, block: B:206:0x04ca  */
    /* JADX WARN: Code duplicated, block: B:230:0x0585 A[PHI: r1 r2 r3 r4 r5 r20 r27
      0x0585: PHI (r1v13 java.util.ArrayList) = (r1v12 java.util.ArrayList), (r1v12 java.util.ArrayList), (r1v12 java.util.ArrayList), (r1v16 java.util.ArrayList) binds: [B:134:0x02c3, B:148:0x0304, B:150:0x0308, B:247:0x0585] A[DONT_GENERATE, DONT_INLINE]
      0x0585: PHI (r2v21 float) = (r2v20 float), (r2v20 float), (r2v20 float), (r2v23 float) binds: [B:134:0x02c3, B:148:0x0304, B:150:0x0308, B:247:0x0585] A[DONT_GENERATE, DONT_INLINE]
      0x0585: PHI (r3v6 float) = (r3v5 float), (r3v5 float), (r3v5 float), (r3v8 float) binds: [B:134:0x02c3, B:148:0x0304, B:150:0x0308, B:247:0x0585] A[DONT_GENERATE, DONT_INLINE]
      0x0585: PHI (r4v3 int) = (r4v2 int), (r4v2 int), (r4v2 int), (r4v5 int) binds: [B:134:0x02c3, B:148:0x0304, B:150:0x0308, B:247:0x0585] A[DONT_GENERATE, DONT_INLINE]
      0x0585: PHI (r5v13 int) = (r5v12 int), (r5v12 int), (r5v12 int), (r5v16 int) binds: [B:134:0x02c3, B:148:0x0304, B:150:0x0308, B:247:0x0585] A[DONT_GENERATE, DONT_INLINE]
      0x0585: PHI (r20v2 Rj.w0) = (r20v1 Rj.w0), (r20v1 Rj.w0), (r20v1 Rj.w0), (r20v6 Rj.w0) binds: [B:134:0x02c3, B:148:0x0304, B:150:0x0308, B:247:0x0585] A[DONT_GENERATE, DONT_INLINE]
      0x0585: PHI (r27v4 float) = (r27v3 float), (r27v3 float), (r27v3 float), (r27v6 float) binds: [B:134:0x02c3, B:148:0x0304, B:150:0x0308, B:247:0x0585] A[DONT_GENERATE, DONT_INLINE]] */
    /* JADX WARN: Code duplicated, block: B:236:0x01ed A[SYNTHETIC] */
    /* JADX WARN: Code duplicated, block: B:238:0x01cf A[SYNTHETIC] */
    /* JADX WARN: Code duplicated, block: B:240:0x0243 A[SYNTHETIC] */
    /* JADX WARN: Code duplicated, block: B:75:0x0182  */
    /* JADX WARN: Code duplicated, block: B:76:0x018b  */
    /* JADX WARN: Code duplicated, block: B:79:0x0195  */
    /* JADX WARN: Code duplicated, block: B:93:0x01d5  */
    /* JADX WARN: Code duplicated, block: B:97:0x01fb  */
    /* JADX WARN: Code duplicated, block: B:98:0x01fe  */
    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        C2702d c2702d;
        y1 y1Var;
        gk.V v10;
        Map mapD;
        C2765z c2765zD;
        C2765z c2765z;
        float f10;
        float f11;
        boolean z10;
        Sj.b bVar;
        int i10;
        Sj.b bVar2;
        Map.Entry entry;
        Map.Entry entry2;
        ArrayList arrayList;
        ArrayList arrayList2;
        Iterator it;
        c cVar;
        c cVar2;
        int iD;
        float fJ;
        int size;
        int i11;
        float fA;
        List<Sj.d> listC;
        ArrayList arrayList3;
        float f12;
        int i12;
        int i13;
        AbstractC2759w0 abstractC2759w0;
        float f13;
        float f14;
        float fA2;
        float fA3;
        float fMin;
        float fMax;
        float f15;
        float f16;
        float f17;
        String str;
        List list;
        Long lR;
        long jLongValue;
        Integer numValueOf;
        int size2;
        int i14;
        Iterator it2;
        long j10;
        long j11;
        long jE;
        Sj.b bVar3;
        long jE2;
        String str2;
        String str3;
        ek.I i15;
        this.f95605z.clear();
        this.f95589A.clear();
        this.f95590B.clear();
        if (AbstractC7609s.f(KLineManager.f142490O.a().u().get("liqheatmap"), Boolean.FALSE)) {
            f95584C.a(c());
            return;
        }
        AbstractC2759w0 abstractC2759w1 = this.f95594o;
        if (abstractC2759w1 == null || (c2702d = this.f95592m) == null || (y1Var = this.f95593n) == null || (v10 = this.f95591l) == null || (mapD = v10.D()) == null || (c2765zD = i().d()) == null) {
            return;
        }
        Sj.a aVarC = c2765zD.C();
        if (aVarC.size() < 2 || abstractC2759w1.z() == 0.0d || mapD.isEmpty()) {
            f95584C.a(c());
            return;
        }
        float fU = y1Var.u();
        float fU2 = c2702d.u();
        float fY = c2702d.y();
        float fZ = c2702d.z();
        float fP = c2702d.p();
        gk.V v11 = this.f95591l;
        boolean z11 = ((v11 != null && (i15 = (ek.I) AbstractC2801o.r0(v11.x().r(), 1)) != null) ? i15.b() : true) && y1Var.z() >= 1.8f;
        if (this.f95598s != mapD) {
            this.f95598s = mapD;
            this.f95599t = Sf.z.d1(mapD.entrySet(), new C7400z());
        }
        List list2 = this.f95599t;
        Sj.b bVar4 = (Sj.b) Sf.z.q0(aVarC);
        long jE3 = bVar4 != null ? bVar4.e() : Long.MIN_VALUE;
        Sj.b bVar5 = (Sj.b) Sf.z.D0(aVarC);
        long jE4 = bVar5 != null ? bVar5.e() : Long.MIN_VALUE;
        int i16 = 1;
        AbstractC2759w0 abstractC2759w2 = abstractC2759w1;
        long j12 = jE4;
        if (this.f95601v == aVarC && this.f95602w == aVarC.size()) {
            c2765z = c2765zD;
            if (this.f95603x == jE3 && this.f95604y == j12) {
                f10 = fU;
                f11 = fZ;
                z10 = z11;
            }
            bVar = (Sj.b) Sf.z.q0(aVarC);
            if (bVar != null) {
                i10 = 1000;
                long jE5 = bVar.e() / ((long) 1000);
            } else {
                i10 = 1000;
            }
            bVar2 = (Sj.b) Sf.z.D0(aVarC);
            if (bVar2 != null) {
                long jE6 = bVar2.e() / ((long) i10);
            }
            entry = (Map.Entry) Sf.z.q0(list2);
            if (entry != null && (str3 = (String) entry.getKey()) != null) {
                Ah.w.r(str3);
            }
            entry2 = (Map.Entry) Sf.z.D0(list2);
            if (entry2 != null && (str2 = (String) entry2.getKey()) != null) {
                Ah.w.r(str2);
            }
            arrayList = new ArrayList();
            arrayList2 = new ArrayList();
            it = list2.iterator();
            while (it.hasNext()) {
                Map.Entry entry3 = (Map.Entry) it.next();
                str = (String) entry3.getKey();
                list = (List) entry3.getValue();
                lR = Ah.w.r(str);
                if (lR != null) {
                    jLongValue = lR.longValue();
                    numValueOf = (Integer) this.f95600u.get(lR);
                    if (numValueOf != null) {
                        size2 = aVarC.size();
                        i14 = 0;
                        while (true) {
                            if (i14 < size2) {
                                it2 = it;
                                numValueOf = null;
                                break;
                            }
                            it2 = it;
                            j10 = jLongValue;
                            int i17 = size2;
                            j11 = 1000;
                            jE = ((Sj.b) aVarC.get(i14)).e() / j11;
                            int i18 = i14 + 1;
                            bVar3 = (Sj.b) Sf.z.r0(aVarC, i18);
                            if (bVar3 != null) {
                                jE2 = bVar3.e() / j11;
                            } else {
                                jE2 = Long.MAX_VALUE;
                            }
                            if (jE > j10 && j10 < jE2) {
                                numValueOf = Integer.valueOf(i14);
                                break;
                            }
                            i14 = i18;
                            size2 = i17;
                            it = it2;
                            jLongValue = j10;
                        }
                    } else {
                        it2 = it;
                    }
                    if (numValueOf == null) {
                        arrayList.add(new c(numValueOf.intValue(), y1Var.l(numValueOf.intValue()) + fU2, list));
                    } else if (arrayList2.size() < 5) {
                        arrayList2.add(str);
                    }
                    it = it2;
                }
            }
            if (arrayList.isEmpty()) {
                f95584C.a(c());
                return;
            }
            cVar = (c) Sf.z.q0(arrayList);
            if (cVar != null) {
                cVar.b();
            }
            cVar2 = (c) Sf.z.D0(arrayList);
            if (cVar2 != null) {
                cVar2.b();
            }
            iD = c2765z.D() - 1;
            if (iD >= 0) {
                fJ = p292ng.i.j((f10 / 3) + y1Var.l(iD) + fU2, fY);
            } else {
                fJ = fY;
            }
            size = arrayList.size();
            i11 = 0;
            while (i11 < size) {
                c cVar3 = (c) arrayList.get(i11);
                fA = cVar3.a();
                listC = cVar3.c();
                if (listC.isEmpty()) {
                    arrayList3 = arrayList;
                    f12 = fJ;
                    i12 = size;
                    i13 = i11;
                    abstractC2759w0 = abstractC2759w2;
                    f13 = f11;
                    f14 = fP;
                    i16 = 1;
                } else {
                    float f18 = 0.0f;
                    if (i11 < Sf.r.p(arrayList)) {
                        fA3 = ((c) arrayList.get(i11 + 1)).a();
                    } else {
                        if (arrayList.size() >= 2) {
                            fA2 = fA - ((c) arrayList.get(i11 - 1)).a();
                        } else {
                            fA2 = f10;
                        }
                        if (fA2 <= 0.0f) {
                            fA2 = f10;
                        }
                        fA3 = fA2 + fA;
                    }
                    fMin = Math.min(fA, fA3);
                    fMax = Math.max(fA, fA3);
                    if (fMax > fMin || fMax < fU2) {
                        arrayList3 = arrayList;
                        f12 = fJ;
                        i12 = size;
                        i13 = i11;
                        abstractC2759w0 = abstractC2759w2;
                        f13 = f11;
                        f14 = fP;
                        i16 = 1;
                    } else if (fMin > fY) {
                        arrayList3 = arrayList;
                        f12 = fJ;
                        i12 = size;
                        i13 = i11;
                        abstractC2759w0 = abstractC2759w2;
                        f13 = f11;
                        f14 = fP;
                    } else {
                        float fMax2 = Math.max(fMin, fU2);
                        float fMin2 = Math.min(Math.min(fMax, fY), fJ);
                        double dB = KLineManager.f142490O.a().B();
                        int i19 = 0;
                        for (Sj.d dVar : listC) {
                            int i20 = i19 + 1;
                            float f19 = f18;
                            this.f95596q.setColor(this.f95595p ? dVar.b() : dVar.a());
                            ArrayList arrayList4 = arrayList;
                            float f20 = fJ;
                            double dMax = Math.max(dVar.c(), dVar.d()) * dB;
                            int i21 = size;
                            int i22 = i11;
                            double dMin = Math.min(dVar.c(), dVar.d()) * dB;
                            AbstractC2759w0 abstractC2759w3 = abstractC2759w2;
                            float fS = abstractC2759w3.S(dMax);
                            float fS2 = abstractC2759w3.S(dMin);
                            float fMin3 = Math.min(fS, fS2);
                            float fMax3 = Math.max(fS, fS2);
                            if (fMin3 >= fP || fMax3 <= f11) {
                                f15 = f11;
                            } else {
                                f15 = f11;
                                float fMax4 = Math.max(fMin3, f15);
                                float fMin4 = Math.min(fMax3, fP);
                                if (fMin2 > fMax2 && fMin4 > fMax4) {
                                    double dE = dVar.e() * dB;
                                    String strI = (Double.isInfinite(dE) || Double.isNaN(dE)) ? "" : nk.h.i(nk.h.f134211a, dE, false, 1, null, 10, null);
                                    float f21 = fMin2;
                                    float f22 = fMax2;
                                    int iB = cVar3.b();
                                    String str4 = "--";
                                    String str5 = Ah.y.j0(strI) ? "--" : strI;
                                    double d10 = (dMax + dMin) / 2.0d;
                                    if (!Double.isNaN(d10) && !Double.isInfinite(d10)) {
                                        int iP = p292ng.i.p(KLineManager.f142490O.a().j(), 0, 8);
                                        p167hg.T t10 = p167hg.T.f97914a;
                                        str4 = String.format(Locale.US, "%." + iP + 'f', Arrays.copyOf(new Object[]{Double.valueOf(d10)}, i16));
                                    }
                                    b bVar6 = new b(iB, i19, f22, fMax4, f21, fMin4, str5, str4, this.f95595p ? dVar.b() : dVar.a());
                                    this.f95605z.add(bVar6);
                                    HashMap map = this.f95589A;
                                    Integer numValueOf2 = Integer.valueOf(bVar6.c());
                                    Object arrayList5 = map.get(numValueOf2);
                                    if (arrayList5 == null) {
                                        arrayList5 = new ArrayList();
                                        map.put(numValueOf2, arrayList5);
                                    }
                                    List list3 = (List) arrayList5;
                                    if (list3.isEmpty()) {
                                        this.f95590B.add(Integer.valueOf(bVar6.c()));
                                    }
                                    list3.add(bVar6);
                                    canvas.drawRect(f22, fMax4, f21, fMin4, this.f95596q);
                                    f16 = f21;
                                    f17 = f22;
                                    if (z10) {
                                        float f23 = f16 - f17;
                                        float f24 = fMin4 - fMax4;
                                        if (f23 >= 36.0f && f24 >= 14.0f) {
                                            if (!(strI.length() == 0)) {
                                                float fO = p292ng.i.o(f24 * 0.42f, 8.0f, 18.0f);
                                                this.f95597r.setTextSize(fO);
                                                float fMeasureText = this.f95597r.measureText(strI);
                                                float f25 = f23 - 6.0f;
                                                if (f25 > f19) {
                                                    if (fMeasureText > f25) {
                                                        float f26 = (f25 / fMeasureText) * fO;
                                                        if (f26 >= 8.0f) {
                                                            this.f95597r.setTextSize(f26);
                                                            if (this.f95597r.measureText(strI) <= f25) {
                                                            }
                                                        }
                                                    }
                                                    int iB2 = this.f95595p ? dVar.b() : dVar.a();
                                                    this.f95597r.setColor((((float) Color.blue(iB2)) * 0.114f) + ((((float) Color.green(iB2)) * 0.587f) + (((float) Color.red(iB2)) * 0.299f)) >= 140.0f ? -16777216 : -1);
                                                    canvas.drawText(strI, (f17 + f16) / 2.0f, ((fMax4 + fMin4) / 2.0f) - ((this.f95597r.ascent() + this.f95597r.descent()) / 2.0f), this.f95597r);
                                                }
                                            }
                                        }
                                    }
                                }
                                i19 = i20;
                                f11 = f15;
                                fP = fP;
                                arrayList = arrayList4;
                                fJ = f20;
                                size = i21;
                                i11 = i22;
                                fMax2 = f17;
                                fMin2 = f16;
                                i16 = 1;
                                abstractC2759w2 = abstractC2759w3;
                                f18 = f19;
                            }
                            f16 = fMin2;
                            f17 = fMax2;
                            i19 = i20;
                            f11 = f15;
                            fP = fP;
                            arrayList = arrayList4;
                            fJ = f20;
                            size = i21;
                            i11 = i22;
                            fMax2 = f17;
                            fMin2 = f16;
                            i16 = 1;
                            abstractC2759w2 = abstractC2759w3;
                            f18 = f19;
                        }
                        arrayList3 = arrayList;
                        f12 = fJ;
                        i12 = size;
                        i13 = i11;
                        abstractC2759w0 = abstractC2759w2;
                        f13 = f11;
                        f14 = fP;
                        i16 = 1;
                    }
                }
                i11 = i13 + 1;
                f11 = f13;
                fP = f14;
                arrayList = arrayList3;
                fJ = f12;
                size = i12;
                abstractC2759w2 = abstractC2759w0;
            }
        }
        c2765z = c2765zD;
        this.f95600u.clear();
        Iterator it3 = aVarC.iterator();
        int i23 = 0;
        while (it3.hasNext()) {
            Object next = it3.next();
            int i24 = i23 + 1;
            if (i23 < 0) {
                Sf.r.x();
            }
            this.f95600u.put(Long.valueOf(((Sj.b) next).e() / ((long) 1000)), Integer.valueOf(i23));
            fU = fU;
            i23 = i24;
            it3 = it3;
            fZ = fZ;
            z11 = z11;
        }
        f10 = fU;
        f11 = fZ;
        z10 = z11;
        this.f95601v = aVarC;
        this.f95602w = aVarC.size();
        this.f95603x = jE3;
        this.f95604y = j12;
        bVar = (Sj.b) Sf.z.q0(aVarC);
        if (bVar != null) {
            i10 = 1000;
            long jE7 = bVar.e() / ((long) 1000);
        } else {
            i10 = 1000;
        }
        bVar2 = (Sj.b) Sf.z.D0(aVarC);
        if (bVar2 != null) {
            long jE8 = bVar2.e() / ((long) i10);
        }
        entry = (Map.Entry) Sf.z.q0(list2);
        if (entry != null) {
            Ah.w.r(str3);
        }
        entry2 = (Map.Entry) Sf.z.D0(list2);
        if (entry2 != null) {
            Ah.w.r(str2);
        }
        arrayList = new ArrayList();
        arrayList2 = new ArrayList();
        it = list2.iterator();
        while (it.hasNext()) {
            Map.Entry entry4 = (Map.Entry) it.next();
            str = (String) entry4.getKey();
            list = (List) entry4.getValue();
            lR = Ah.w.r(str);
            if (lR != null) {
                jLongValue = lR.longValue();
                numValueOf = (Integer) this.f95600u.get(lR);
                if (numValueOf != null) {
                    size2 = aVarC.size();
                    i14 = 0;
                    while (true) {
                        if (i14 < size2) {
                            it2 = it;
                            numValueOf = null;
                            break;
                        }
                        it2 = it;
                        j10 = jLongValue;
                        int i110 = size2;
                        j11 = 1000;
                        jE = ((Sj.b) aVarC.get(i14)).e() / j11;
                        int i111 = i14 + 1;
                        bVar3 = (Sj.b) Sf.z.r0(aVarC, i111);
                        if (bVar3 != null) {
                            jE2 = bVar3.e() / j11;
                        } else {
                            jE2 = Long.MAX_VALUE;
                        }
                        if (jE > j10) {
                        }
                        i14 = i111;
                        size2 = i110;
                        it = it2;
                        jLongValue = j10;
                    }
                } else {
                    it2 = it;
                }
                if (numValueOf == null) {
                    arrayList.add(new c(numValueOf.intValue(), y1Var.l(numValueOf.intValue()) + fU2, list));
                } else if (arrayList2.size() < 5) {
                    arrayList2.add(str);
                }
                it = it2;
            }
        }
        if (arrayList.isEmpty()) {
            f95584C.a(c());
            return;
        }
        cVar = (c) Sf.z.q0(arrayList);
        if (cVar != null) {
            cVar.b();
        }
        cVar2 = (c) Sf.z.D0(arrayList);
        if (cVar2 != null) {
            cVar2.b();
        }
        iD = c2765z.D() - 1;
        if (iD >= 0) {
            fJ = p292ng.i.j((f10 / 3) + y1Var.l(iD) + fU2, fY);
        } else {
            fJ = fY;
        }
        size = arrayList.size();
        i11 = 0;
        while (i11 < size) {
            c cVar4 = (c) arrayList.get(i11);
            fA = cVar4.a();
            listC = cVar4.c();
            if (listC.isEmpty()) {
                float f110 = 0.0f;
                if (i11 < Sf.r.p(arrayList)) {
                    fA3 = ((c) arrayList.get(i11 + 1)).a();
                } else {
                    if (arrayList.size() >= 2) {
                        fA2 = fA - ((c) arrayList.get(i11 - 1)).a();
                    } else {
                        fA2 = f10;
                    }
                    if (fA2 <= 0.0f) {
                        fA2 = f10;
                    }
                    fA3 = fA2 + fA;
                }
                fMin = Math.min(fA, fA3);
                fMax = Math.max(fA, fA3);
                if (fMax > fMin) {
                    arrayList3 = arrayList;
                    f12 = fJ;
                    i12 = size;
                    i13 = i11;
                    abstractC2759w0 = abstractC2759w2;
                    f13 = f11;
                    f14 = fP;
                    i16 = 1;
                } else {
                    arrayList3 = arrayList;
                    f12 = fJ;
                    i12 = size;
                    i13 = i11;
                    abstractC2759w0 = abstractC2759w2;
                    f13 = f11;
                    f14 = fP;
                    i16 = 1;
                }
            } else {
                arrayList3 = arrayList;
                f12 = fJ;
                i12 = size;
                i13 = i11;
                abstractC2759w0 = abstractC2759w2;
                f13 = f11;
                f14 = fP;
                i16 = 1;
            }
            i11 = i13 + 1;
            f11 = f13;
            fP = f14;
            arrayList = arrayList3;
            fJ = f12;
            size = i12;
            abstractC2759w2 = abstractC2759w0;
        }
    }

    /* JADX WARN: Code duplicated, block: B:40:0x00d6  */
    /* JADX WARN: Code duplicated, block: B:54:0x0118  */
    /* JADX WARN: Code duplicated, block: B:59:0x0126  */
    /* JADX WARN: Code duplicated, block: B:71:0x016f  */
    /* JADX WARN: Code duplicated, block: B:76:0x017d  */
    /* JADX WARN: Code duplicated, block: B:81:0x018b  */
    @Override // Rj.AbstractC2744r0
    public boolean n(String str, int i10, int i11) {
        Object objPrevious;
        boolean z10;
        b bVar;
        b bVarV;
        b bVarA;
        b bVar2;
        b bVarV2;
        b bVarA2;
        b bVar3;
        b bVar4;
        String strE;
        String strE2;
        String strG;
        String strG2;
        String strG3;
        String strG4;
        String strG5;
        String strG6;
        String strG7;
        String strG8;
        ek.I i12;
        gk.V v10 = this.f95591l;
        boolean z11 = true;
        if (!((v10 == null || (i12 = (ek.I) AbstractC2801o.r0(v10.x().r(), 0)) == null) ? true : i12.b())) {
            a aVar = f95584C;
            boolean zC = aVar.c(c());
            aVar.a(c());
            return zC;
        }
        if (this.f95605z.isEmpty()) {
            a aVar2 = f95584C;
            boolean zC2 = aVar2.c(c());
            aVar2.a(c());
            return zC2;
        }
        ArrayList arrayList = this.f95605z;
        ListIterator listIterator = arrayList.listIterator(arrayList.size());
        do {
            if (!listIterator.hasPrevious()) {
                objPrevious = null;
                break;
            }
            objPrevious = listIterator.previous();
        } while (!((b) objPrevious).a(i10, i11));
        b bVar5 = (b) objPrevious;
        if (bVar5 == null) {
            a aVar3 = f95584C;
            boolean zC3 = aVar3.c(c());
            aVar3.a(c());
            return zC3;
        }
        int iIndexOf = this.f95590B.indexOf(Integer.valueOf(bVar5.c()));
        Integer num = iIndexOf > 0 ? (Integer) this.f95590B.get(iIndexOf - 1) : null;
        Integer num2 = (iIndexOf < 0 || iIndexOf >= Sf.r.p(this.f95590B)) ? null : (Integer) this.f95590B.get(iIndexOf + 1);
        float f10 = 0.0f;
        if (num != null) {
            int iIntValue = num.intValue();
            float f11 = bVar5.f();
            float fB = bVar5.b();
            List<b> list = (List) this.f95589A.get(Integer.valueOf(iIntValue));
            if (list == null) {
                z10 = true;
                bVar = null;
            } else {
                float f12 = 0.0f;
                bVar = null;
                for (b bVar6 : list) {
                    boolean z12 = z11;
                    float fMin = Math.min(fB, bVar6.b()) - Math.max(f11, bVar6.f());
                    if (fMin > f12) {
                        f12 = fMin;
                        bVar = bVar6;
                    }
                    z11 = z12;
                }
                z10 = z11;
            }
        } else {
            z10 = true;
            bVar = null;
        }
        if (num != null) {
            int iIntValue2 = num.intValue();
            if (bVar != null) {
                bVarV = v(iIntValue2, bVar);
            } else {
                bVarV = null;
            }
        } else {
            bVarV = null;
        }
        if (num != null) {
            int iIntValue3 = num.intValue();
            if (bVar != null) {
                bVarA = A(iIntValue3, bVar);
            } else {
                bVarA = null;
            }
        } else {
            bVarA = null;
        }
        if (num2 != null) {
            int iIntValue4 = num2.intValue();
            float f13 = bVar5.f();
            float fB2 = bVar5.b();
            List<b> list2 = (List) this.f95589A.get(Integer.valueOf(iIntValue4));
            if (list2 == null) {
                bVar2 = null;
            } else {
                bVar2 = null;
                for (b bVar7 : list2) {
                    float fMin2 = Math.min(fB2, bVar7.b()) - Math.max(f13, bVar7.f());
                    if (fMin2 > f10) {
                        f10 = fMin2;
                        bVar2 = bVar7;
                    }
                }
            }
        } else {
            bVar2 = null;
        }
        if (num2 != null) {
            int iIntValue5 = num2.intValue();
            if (bVar2 != null) {
                bVarV2 = v(iIntValue5, bVar2);
            } else {
                bVarV2 = null;
            }
        } else {
            bVarV2 = null;
        }
        if (num2 != null) {
            int iIntValue6 = num2.intValue();
            if (bVar2 != null) {
                bVarA2 = A(iIntValue6, bVar2);
            } else {
                bVarA2 = null;
            }
        } else {
            bVarA2 = null;
        }
        b bVarV3 = v(bVar5.c(), bVar5);
        b bVarA3 = A(bVar5.c(), bVar5);
        if (bVarV3 == null) {
            List<b> list3 = (List) this.f95589A.get(Integer.valueOf(bVar5.c()));
            if (list3 == null) {
                bVar3 = null;
            } else {
                float f14 = (bVar5.f() + bVar5.b()) / 2.0f;
                float f15 = Float.NEGATIVE_INFINITY;
                bVar3 = null;
                for (b bVar8 : list3) {
                    float f16 = (bVar8.f() + bVar8.b()) / 2.0f;
                    if (f16 < f14 && f16 > f15) {
                        bVar3 = bVar8;
                        f15 = f16;
                    }
                }
            }
        } else {
            bVar3 = bVarV3;
        }
        if (bVarA3 == null) {
            List<b> list4 = (List) this.f95589A.get(Integer.valueOf(bVar5.c()));
            if (list4 == null) {
                bVar4 = null;
            } else {
                float f17 = (bVar5.f() + bVar5.b()) / 2.0f;
                float f18 = Float.POSITIVE_INFINITY;
                bVar4 = null;
                for (b bVar9 : list4) {
                    float f19 = (bVar9.f() + bVar9.b()) / 2.0f;
                    if (f19 > f17 && f19 < f18) {
                        bVar4 = bVar9;
                        f18 = f19;
                    }
                }
            }
        } else {
            bVar4 = bVarA3;
        }
        String str2 = "--";
        List listQ = Sf.r.q((bVarV == null || (strG8 = bVarV.g()) == null) ? "--" : strG8, (bVarV3 == null || (strG7 = bVarV3.g()) == null) ? "--" : strG7, (bVarV2 == null || (strG6 = bVarV2.g()) == null) ? "--" : strG6, (bVar == null || (strG5 = bVar.g()) == null) ? "--" : strG5, bVar5.g(), (bVar2 == null || (strG4 = bVar2.g()) == null) ? "--" : strG4, (bVarA == null || (strG3 = bVarA.g()) == null) ? "--" : strG3, (bVarA3 == null || (strG2 = bVarA3.g()) == null) ? "--" : strG2, (bVarA2 == null || (strG = bVarA2.g()) == null) ? "--" : strG);
        List listQ2 = Sf.r.q(Integer.valueOf(bVarV != null ? bVarV.d() : f95588G), Integer.valueOf(bVarV3 != null ? bVarV3.d() : f95588G), Integer.valueOf(bVarV2 != null ? bVarV2.d() : f95588G), Integer.valueOf(bVar != null ? bVar.d() : f95588G), Integer.valueOf(bVar5.d()), Integer.valueOf(bVar2 != null ? bVar2.d() : f95588G), Integer.valueOf(bVarA != null ? bVarA.d() : f95588G), Integer.valueOf(bVarA3 != null ? bVarA3.d() : f95588G), Integer.valueOf(bVarA2 != null ? bVarA2.d() : f95588G));
        if (bVar3 == null || (strE = bVar3.e()) == null) {
            strE = "--";
        }
        String strE3 = bVar5.e();
        if (bVar4 != null && (strE2 = bVar4.e()) != null) {
            str2 = strE2;
        }
        f95584C.d(c(), new Sj.e(i10, i11, listQ, listQ2, Sf.r.q(strE, strE3, str2), Sf.r.q(Integer.valueOf(bVar3 != null ? bVar3.d() : f95588G), Integer.valueOf(bVar5.d()), Integer.valueOf(bVar4 != null ? bVar4.d() : f95588G))));
        w(c());
        y1 y1Var = this.f95593n;
        if (y1Var != null) {
            if (y1Var.E()) {
                y1Var.Y(false);
            }
            y1Var.W(-1.0f);
            y1Var.X(-1.0f);
        }
        return z10;
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        if (aVar == null) {
            return;
        }
        AbstractC2755v abstractC2755vQ = q();
        gk.V v10 = abstractC2755vQ instanceof gk.V ? (gk.V) abstractC2755vQ : null;
        if (v10 == null) {
            return;
        }
        this.f95591l = v10;
        this.f95595p = aVar.w();
        C2741q c2741qB = i().b();
        this.f95592m = c2741qB.e(b());
        this.f95593n = c2741qB.m(c());
        this.f95594o = c2741qB.l(b());
    }

    public final b v(int i10, b bVar) {
        List<b> list = (List) this.f95589A.get(Integer.valueOf(i10));
        if (list == null) {
            return null;
        }
        float f10 = (bVar.f() + bVar.b()) / 2.0f;
        float f11 = Float.NEGATIVE_INFINITY;
        b bVar2 = null;
        for (b bVar3 : list) {
            float f12 = (bVar3.f() + bVar3.b()) / 2.0f;
            if (f12 < f10 && f12 > f11) {
                bVar2 = bVar3;
                f11 = f12;
            }
        }
        if (bVar2 == null) {
            return null;
        }
        float f13 = bVar.f() - bVar2.b();
        if (f13 > 0.0f && f13 > (Math.max(bVar.b() - bVar.f(), bVar2.b() - bVar2.f()) * 0.45f) + 2.0f) {
            return null;
        }
        return bVar2;
    }

    public final void w(String str) {
        long jUptimeMillis = SystemClock.uptimeMillis() + 6000;
        f95587F.put(str, Long.valueOf(jUptimeMillis));
        f95585D.postDelayed(new RunnableC7398x(str, jUptimeMillis, this), 6000L);
    }
}
