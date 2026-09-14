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
import android.graphics.CornerPathEffect;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.Rect;
import android.graphics.RectF;
import gk.L0;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.ListIterator;
import java.util.Map;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.chart.data.AIWinRateItem;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class X extends AbstractC2744r0 {

    /* JADX INFO: renamed from: S, reason: collision with root package name */
    public static final a f95260S = new a(null);

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public final RectF f95261A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public final Path f95262B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public final RectF f95263C;

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public final Path f95264D;

    /* JADX INFO: renamed from: E, reason: collision with root package name */
    public final LinkedHashMap f95265E;

    /* JADX INFO: renamed from: F, reason: collision with root package name */
    public final LinkedHashMap f95266F;

    /* JADX INFO: renamed from: G, reason: collision with root package name */
    public boolean f95267G;

    /* JADX INFO: renamed from: H, reason: collision with root package name */
    public boolean f95268H;

    /* JADX INFO: renamed from: I, reason: collision with root package name */
    public int f95269I;

    /* JADX INFO: renamed from: J, reason: collision with root package name */
    public y1 f95270J;

    /* JADX INFO: renamed from: K, reason: collision with root package name */
    public AbstractC2759w0 f95271K;

    /* JADX INFO: renamed from: L, reason: collision with root package name */
    public L0 f95272L;

    /* JADX INFO: renamed from: M, reason: collision with root package name */
    public final nk.r f95273M;

    /* JADX INFO: renamed from: N, reason: collision with root package name */
    public float f95274N;

    /* JADX INFO: renamed from: O, reason: collision with root package name */
    public float f95275O;

    /* JADX INFO: renamed from: P, reason: collision with root package name */
    public KLineManager f95276P;

    /* JADX INFO: renamed from: Q, reason: collision with root package name */
    public List f95277Q;

    /* JADX INFO: renamed from: R, reason: collision with root package name */
    public List f95278R;

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final b f95279l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Paint f95280m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final Paint f95281n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final Paint f95282o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final Paint f95283p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public float f95284q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final float f95285r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public final float f95286s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public final float f95287t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public final float f95288u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public final float f95289v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public final float f95290w;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public final Paint f95291x;

    /* JADX INFO: renamed from: y, reason: collision with root package name */
    public final Rect f95292y;

    /* JADX INFO: renamed from: z, reason: collision with root package name */
    public float f95293z;

    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public final class b {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public final int f95294a;

        /* JADX INFO: renamed from: b, reason: collision with root package name */
        public final int f95295b;

        /* JADX INFO: renamed from: c, reason: collision with root package name */
        public final int f95296c;

        /* JADX INFO: renamed from: d, reason: collision with root package name */
        public final int f95297d;

        /* JADX INFO: renamed from: e, reason: collision with root package name */
        public final int f95298e;

        /* JADX INFO: renamed from: f, reason: collision with root package name */
        public final int f95299f;

        /* JADX INFO: renamed from: g, reason: collision with root package name */
        public final int f95300g;

        /* JADX INFO: renamed from: h, reason: collision with root package name */
        public final int f95301h;

        /* JADX INFO: renamed from: i, reason: collision with root package name */
        public final int f95302i;

        /* JADX INFO: renamed from: j, reason: collision with root package name */
        public final int f95303j;

        /* JADX INFO: renamed from: k, reason: collision with root package name */
        public final int f95304k;

        /* JADX INFO: renamed from: l, reason: collision with root package name */
        public final int f95305l;

        public b(X x10) {
            int color = Color.parseColor("#32A853");
            this.f95294a = color;
            int color2 = Color.parseColor("#EB4236");
            this.f95295b = color2;
            this.f95296c = U1.a.j(color, 76);
            this.f95297d = U1.a.j(color2, 76);
            int color3 = Color.parseColor("#FFAA00");
            this.f95298e = color3;
            this.f95299f = U1.a.j(color3, 76);
            this.f95300g = U1.a.j(color, 76);
            this.f95301h = U1.a.j(color2, 76);
            this.f95302i = U1.a.j(color, 22);
            this.f95303j = U1.a.j(color2, 22);
            this.f95304k = U1.a.j(color3, 76);
            this.f95305l = U1.a.j(color3, 22);
        }

        public final int a() {
            return this.f95294a;
        }

        public final int b() {
            return this.f95295b;
        }
    }

    public /* synthetic */ class c extends p167hg.x {
        public c(X x10) {
            super(x10, X.class, "klineManager", "getKlineManager()Lsp/aicoin_kline/core/KLineManager;", 0);
        }

        @Override // p313og.l
        public Object get() {
            return ((X) this.f97930b).f95276P;
        }

        @Override // p313og.h
        public void set(Object obj) {
            ((X) this.f97930b).f95276P = (KLineManager) obj;
        }
    }

    public X(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f95279l = new b(this);
        Paint paint = new Paint();
        Paint.Style style = Paint.Style.FILL;
        paint.setStyle(style);
        paint.setPathEffect(new CornerPathEffect(this.f95290w));
        this.f95280m = paint;
        Paint paint2 = new Paint();
        paint2.setStyle(style);
        paint2.setPathEffect(new CornerPathEffect(this.f95290w));
        this.f95281n = paint2;
        this.f95282o = new Paint();
        this.f95283p = new Paint();
        Paint paint3 = new Paint();
        paint3.setColor(-256);
        paint3.setStyle(Paint.Style.STROKE);
        paint3.setAntiAlias(true);
        paint3.setStrokeWidth(Xj.a.a(1.0f));
        this.f95285r = Xj.a.a(3.0f);
        this.f95286s = Xj.a.a(4.5f);
        float fA = Xj.a.a(3.0f);
        this.f95287t = fA;
        this.f95288u = Xj.a.a(1.5f);
        this.f95289v = (float) (Math.tan(0.5235987755982988d) * ((double) fA));
        this.f95290w = Xj.a.a(3.0f);
        Paint paint4 = new Paint();
        paint4.setTextSize(Xj.a.c(12.0f));
        paint4.setColor(Color.parseColor("#FFFFFF"));
        this.f95291x = paint4;
        this.f95292y = new Rect();
        this.f95261A = new RectF();
        this.f95262B = new Path();
        this.f95263C = new RectF();
        this.f95264D = new Path();
        this.f95265E = new LinkedHashMap();
        this.f95266F = new LinkedHashMap();
        this.f95269I = 60;
        this.f95273M = new nk.r();
    }

    public static final KLineManager v() {
        return KLineManager.f142490O.a();
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        AbstractC2759w0 abstractC2759w0;
        L0 l10;
        Sj.a aVarC;
        int iNextIndex;
        long j10;
        int i10;
        int i11;
        float f10;
        L0 l11;
        float f11;
        float f12;
        float f13;
        float f14;
        float f15;
        ArrayList<Sj.h> arrayList;
        y1 y1Var = this.f95270J;
        if (y1Var == null || (abstractC2759w0 = this.f95271K) == null || (l10 = this.f95272L) == null) {
            return;
        }
        C2741q c2741qB = i().b();
        if (abstractC2759w0.z() == 0.0d) {
            return;
        }
        this.f95277Q = c2741qB.f19505m;
        this.f95278R = c2741qB.f19507o;
        long jF = y1Var.F();
        long jN = y1Var.n();
        Map mapS = l10.s();
        C2765z c2765zD = l10.h().d();
        if (c2765zD == null || (aVarC = c2765zD.C()) == null || aVarC.isEmpty()) {
            return;
        }
        nk.r.b bVarC = this.f95273M.c();
        bVarC.d();
        this.f95265E.clear();
        this.f95266F.clear();
        Iterator it = mapS.entrySet().iterator();
        while (it.hasNext()) {
            List list = (List) ((Map.Entry) it.next()).getValue();
            if (!list.isEmpty()) {
                Iterator it2 = list.iterator();
                int i12 = 0;
                while (true) {
                    if (!it2.hasNext()) {
                        i12 = -1;
                    } else if (((Sj.f) it2.next()).j() < jF) {
                        i12++;
                    }
                }
                Integer numValueOf = Integer.valueOf(i12);
                if (i12 == -1) {
                    numValueOf = null;
                }
                int iIntValue = numValueOf != null ? numValueOf.intValue() : Sf.r.p(list);
                ListIterator listIterator = list.listIterator(list.size());
                while (true) {
                    if (!listIterator.hasPrevious()) {
                        iNextIndex = -1;
                    } else if (((Sj.f) listIterator.previous()).j() <= jN) {
                        iNextIndex = listIterator.nextIndex();
                    }
                }
                Integer numValueOf2 = Integer.valueOf(iNextIndex);
                if (iNextIndex == -1) {
                    numValueOf2 = null;
                }
                int iIntValue2 = numValueOf2 != null ? numValueOf2.intValue() : 0;
                if (iIntValue <= iIntValue2) {
                    List listA1 = Sf.z.a1(list, new p292ng.g(iIntValue, iIntValue2));
                    if (!listA1.isEmpty()) {
                        float fU = y1Var.u();
                        int iF = p292ng.i.f(y1Var.r(), 0);
                        long j11 = jF;
                        int iK = p292ng.i.k(y1Var.q(), aVarC.size());
                        if (iF < iK) {
                            float fJ = y1Var.J();
                            float f16 = 2;
                            this.f95284q = Xj.a.a(y1Var.z()) / f16;
                            float fU2 = (y1Var.u() / f16) - fJ;
                            long jH = y1Var.H(iF + 1) - y1Var.H(iF);
                            int i13 = 0;
                            while (iF < iK) {
                                Sj.b bVar = (Sj.b) Sf.z.r0(aVarC, iF);
                                if (bVar != null) {
                                    int i14 = iK;
                                    int i15 = i13;
                                    double dB = bVar.b();
                                    long j12 = jN;
                                    double dC = bVar.c();
                                    float fS = abstractC2759w0.S(dB);
                                    float fS2 = abstractC2759w0.S(dC);
                                    long jH2 = y1Var.H(iF);
                                    y1 y1Var2 = y1Var;
                                    AbstractC2759w0 abstractC2759w1 = abstractC2759w0;
                                    Integer num = (Integer) this.f95265E.get(Integer.valueOf(iF));
                                    int iIntValue3 = num != null ? num.intValue() : 0;
                                    Integer num2 = (Integer) this.f95266F.get(Integer.valueOf(iF));
                                    int iIntValue4 = num2 != null ? num2.intValue() : 0;
                                    List list2 = this.f95277Q;
                                    if (list2 == null || list2.isEmpty()) {
                                        j10 = jH2;
                                        i10 = 0;
                                        i11 = 0;
                                    } else {
                                        List listN = this.f95277Q;
                                        if (listN == null) {
                                            listN = Sf.r.n();
                                        }
                                        List list3 = listN;
                                        ArrayList arrayList2 = new ArrayList();
                                        for (Object obj : list3) {
                                            long j13 = jH2;
                                            long j14 = j13 + jH;
                                            long signal_time_s = ((AIWinRateItem) obj).getSignal_time_s();
                                            if (j13 <= signal_time_s && signal_time_s < j14) {
                                                arrayList2.add(obj);
                                            }
                                            jH2 = j13;
                                        }
                                        j10 = jH2;
                                        Iterator it3 = arrayList2.iterator();
                                        int i16 = 0;
                                        i10 = 0;
                                        while (it3.hasNext()) {
                                            AIWinRateItem aIWinRateItem = (AIWinRateItem) it3.next();
                                            Iterator it4 = it3;
                                            if (AbstractC7609s.f(aIWinRateItem.getSide(), "buy")) {
                                                i16++;
                                            } else {
                                                String side = aIWinRateItem.getSide();
                                                int i17 = i16;
                                                if (AbstractC7609s.f(side, "sell")) {
                                                    i10++;
                                                }
                                                i16 = i17;
                                            }
                                            it3 = it4;
                                        }
                                        i11 = i16;
                                    }
                                    List list4 = this.f95278R;
                                    if (list4 != null && !list4.isEmpty()) {
                                        List list5 = this.f95278R;
                                        if ((list5 != null ? list5.size() : 0) > 1) {
                                            List list6 = this.f95278R;
                                            if (list6 != null) {
                                                arrayList = new ArrayList();
                                                Iterator it5 = list6.iterator();
                                                while (it5.hasNext()) {
                                                    Iterator it6 = it5;
                                                    Object next = it6.next();
                                                    if (((Sj.h) next).e() == j10) {
                                                        arrayList.add(next);
                                                    }
                                                    it5 = it6;
                                                }
                                            } else {
                                                arrayList = null;
                                            }
                                            if (arrayList != null) {
                                                for (Sj.h hVar : arrayList) {
                                                    if (hVar.a() > 0) {
                                                        i11 += 2;
                                                    }
                                                    if (hVar.c() > 0) {
                                                        i10 += 2;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    switch (i11) {
                                        case 0:
                                            f10 = 0.0f;
                                            this.f95274N = Xj.a.a(0.0f);
                                            break;
                                        case 1:
                                            f10 = 0.0f;
                                            this.f95274N = Xj.a.a(13.0f);
                                            break;
                                        case 2:
                                            f10 = 0.0f;
                                            this.f95274N = Xj.a.a(23.0f);
                                            break;
                                        case 3:
                                            f10 = 0.0f;
                                            this.f95274N = Xj.a.a(38.0f);
                                            break;
                                        case 4:
                                            f10 = 0.0f;
                                            this.f95274N = Xj.a.a(50.0f);
                                            break;
                                        case 5:
                                            f10 = 0.0f;
                                            this.f95274N = Xj.a.a(62.0f);
                                            break;
                                        case 6:
                                            f10 = 0.0f;
                                            this.f95274N = Xj.a.a(76.0f);
                                            break;
                                        default:
                                            f10 = 0.0f;
                                            break;
                                    }
                                    switch (i10) {
                                        case 0:
                                            this.f95275O = Xj.a.a(f10);
                                            break;
                                        case 1:
                                            this.f95275O = Xj.a.a(13.0f);
                                            break;
                                        case 2:
                                            this.f95275O = Xj.a.a(23.0f);
                                            break;
                                        case 3:
                                            this.f95275O = Xj.a.a(33.0f);
                                            break;
                                        case 4:
                                            this.f95275O = Xj.a.a(44.0f);
                                            break;
                                        case 5:
                                            this.f95275O = Xj.a.a(55.0f);
                                            break;
                                        case 6:
                                            this.f95274N = Xj.a.a(76.0f);
                                            break;
                                    }
                                    int size = listA1.size();
                                    int i18 = i15;
                                    while (true) {
                                        if (i18 < size) {
                                            Sj.f fVar = (Sj.f) listA1.get(i18);
                                            boolean zT = l10.t(fVar);
                                            l11 = l10;
                                            boolean zY = y(fVar, this.f95269I);
                                            long j15 = j10 + jH;
                                            long j16 = fVar.j();
                                            if (j10 <= j16 && j16 < j15) {
                                                int i19 = size;
                                                int i20 = i18;
                                                Iterator it7 = it;
                                                Sj.a aVar = aVarC;
                                                this.f95291x.getTextBounds(fVar.h(), 0, fVar.h().length(), this.f95292y);
                                                if (AbstractC7609s.f(fVar.i(), "buy")) {
                                                    this.f95265E.put(Integer.valueOf(iF), Integer.valueOf(iIntValue3 + 1));
                                                    f11 = (iIntValue3 * this.f95293z) + fS2 + this.f95284q + this.f95274N;
                                                } else {
                                                    this.f95266F.put(Integer.valueOf(iF), Integer.valueOf(iIntValue4 + 1));
                                                    f11 = ((fS - this.f95284q) - (iIntValue4 * this.f95293z)) - this.f95275O;
                                                }
                                                if ((!this.f95267G || zT) && (!this.f95268H || zY)) {
                                                    if (AbstractC7609s.f(fVar.i(), "buy")) {
                                                        Paint paint = this.f95280m;
                                                        Paint paint2 = this.f95282o;
                                                        Paint paint3 = this.f95291x;
                                                        String strH = fVar.h();
                                                        paint3.getTextBounds(strH, 0, strH.length(), this.f95292y);
                                                        float fHeight = (this.f95285r * f16) + this.f95292y.height();
                                                        float fWidth = (this.f95286s * f16) + this.f95292y.width();
                                                        Path path = this.f95262B;
                                                        path.reset();
                                                        path.moveTo(fU2, f11);
                                                        path.lineTo(fU2 - this.f95289v, this.f95287t + f11);
                                                        path.lineTo(this.f95289v + fU2, this.f95287t + f11);
                                                        path.close();
                                                        canvas.drawPath(this.f95262B, paint2);
                                                        RectF rectF = this.f95261A;
                                                        float f17 = fWidth * 0.5f;
                                                        float f18 = fU2 - f17;
                                                        float f19 = this.f95287t + f11;
                                                        rectF.set(f18, f19, f17 + fU2, f19 + fHeight);
                                                        RectF rectF2 = this.f95261A;
                                                        float f20 = this.f95290w;
                                                        canvas.drawRoundRect(rectF2, f20, f20, paint);
                                                        canvas.drawText(strH, f18 + this.f95286s, (((f11 + this.f95287t) + fHeight) - this.f95285r) - this.f95288u, paint3);
                                                    } else {
                                                        Paint paint4 = this.f95281n;
                                                        Paint paint5 = this.f95283p;
                                                        Paint paint6 = this.f95291x;
                                                        String strH2 = fVar.h();
                                                        paint6.getTextBounds(strH2, 0, strH2.length(), this.f95292y);
                                                        float fHeight2 = (this.f95285r * f16) + this.f95292y.height();
                                                        float fWidth2 = (this.f95286s * f16) + this.f95292y.width();
                                                        Path path2 = this.f95264D;
                                                        path2.reset();
                                                        path2.moveTo(fU2, f11);
                                                        float f21 = f11;
                                                        path2.lineTo(fU2 - this.f95289v, f21 - this.f95287t);
                                                        path2.lineTo(this.f95289v + fU2, f21 - this.f95287t);
                                                        path2.close();
                                                        canvas.drawPath(this.f95264D, paint5);
                                                        RectF rectF3 = this.f95263C;
                                                        float f22 = fWidth2 * 0.5f;
                                                        float f23 = fU2 - f22;
                                                        float f24 = f21 - this.f95287t;
                                                        rectF3.set(f23, f24 - fHeight2, f22 + fU2, f24);
                                                        RectF rectF4 = this.f95263C;
                                                        float f25 = this.f95290w;
                                                        canvas.drawRoundRect(rectF4, f25, f25, paint4);
                                                        canvas.drawText(strH2, f23 + this.f95286s, ((f21 - this.f95287t) - this.f95285r) - this.f95288u, paint6);
                                                    }
                                                    boolean zF = AbstractC7609s.f(fVar.i(), "buy");
                                                    nk.q qVarA = nk.q.f134234e.a();
                                                    if (zF) {
                                                        RectF rectF5 = this.f95261A;
                                                        float f26 = 10;
                                                        f12 = rectF5.left - f26;
                                                        f13 = rectF5.top;
                                                        f14 = rectF5.right + f26;
                                                        f15 = rectF5.bottom;
                                                    } else {
                                                        RectF rectF6 = this.f95263C;
                                                        float f27 = 10;
                                                        f12 = rectF6.left - f27;
                                                        f13 = rectF6.top;
                                                        f14 = rectF6.right + f27;
                                                        f15 = rectF6.bottom;
                                                    }
                                                    qVarA.g(f12, f13, f14, f15);
                                                    qVarA.i(f12, f13, f14, f15);
                                                    qVarA.j(fVar);
                                                    bVarC.e(qVarA);
                                                } else {
                                                    iIntValue3 = iIntValue3;
                                                    iIntValue4 = iIntValue4;
                                                    listA1 = listA1;
                                                    fU = fU;
                                                }
                                                i18 = i20 + 1;
                                                l10 = l11;
                                                iIntValue3 = iIntValue3;
                                                size = i19;
                                                it = it7;
                                                aVarC = aVar;
                                                iIntValue4 = iIntValue4;
                                                listA1 = listA1;
                                                fU = fU;
                                            }
                                        } else {
                                            l11 = l10;
                                        }
                                    }
                                    int i21 = i18;
                                    float f28 = fU;
                                    fU2 += f28;
                                    iF++;
                                    y1Var = y1Var2;
                                    iK = i14;
                                    jN = j12;
                                    abstractC2759w0 = abstractC2759w1;
                                    l10 = l11;
                                    it = it;
                                    i13 = i21;
                                    aVarC = aVarC;
                                    listA1 = listA1;
                                    fU = f28;
                                }
                            }
                        }
                        jF = j11;
                    }
                }
            }
        }
        bVarC.b();
    }

    @Override // Rj.AbstractC2744r0
    public boolean n(String str, int i10, int i11) {
        Object objD = this.f95273M.d(i10, i11);
        if (objD == null || !(objD instanceof Sj.f)) {
            return false;
        }
        C2738p.f19487a.q((Sj.f) objD, i10, i11);
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
        c2741qB.r(KLineManager.f142490O.a(), Zj.e.c.f27603d);
        if (((KLineManager) p162hb.g.a(new c(this), new W())).V()) {
            this.f95280m.setColor(this.f95279l.b());
            this.f95281n.setColor(this.f95279l.a());
            this.f95282o.setColor(this.f95279l.b());
            this.f95283p.setColor(this.f95279l.a());
        } else {
            this.f95280m.setColor(this.f95279l.a());
            this.f95281n.setColor(this.f95279l.b());
            this.f95282o.setColor(this.f95279l.a());
            this.f95283p.setColor(this.f95279l.b());
        }
        this.f95270J = c2741qB.m(c());
        this.f95271K = c2741qB.l(b());
        AbstractC2755v abstractC2755vQ = q();
        L0 l10 = abstractC2755vQ instanceof L0 ? (L0) abstractC2755vQ : null;
        if (l10 == null) {
            return;
        }
        this.f95272L = l10;
        this.f95291x.getTextBounds("金叉", 0, 2, this.f95292y);
        this.f95293z = (2 * this.f95285r) + this.f95292y.height() + this.f95287t;
        this.f95267G = nk.n.f(27);
        this.f95268H = nk.n.f(26);
        this.f95269I = nk.n.f134230a.b();
    }

    public final boolean y(Sj.f fVar, int i10) {
        return fVar.e() == i10;
    }
}
