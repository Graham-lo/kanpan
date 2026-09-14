package Rj;

import Sf.AbstractC2801o;
import android.graphics.Color;
import android.graphics.PointF;
import android.graphics.Region;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.chart.data.drawing.DrawingItem;
import sp.aicoin_kline.chart.data.drawing.DrawingPoint;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public class G extends AbstractC2721j0 {

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public static final a f19113v = new a(null);

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public static final float f19114w = Xj.a.a(9.5f);

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public final C2732n f19115g;

    /* JADX INFO: renamed from: h, reason: collision with root package name */
    public final String f19116h;

    /* JADX INFO: renamed from: i, reason: collision with root package name */
    public final KLineManager f19117i;

    /* JADX INFO: renamed from: j, reason: collision with root package name */
    public boolean f19118j;

    /* JADX INFO: renamed from: k, reason: collision with root package name */
    public boolean f19119k;

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public int f19120l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final HashMap f19121m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public boolean f19122n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public int f19123o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public float f19124p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public float f19125q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final ArrayList f19126r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public final HashMap f19127s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public DrawingItem f19128t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public DrawingItem f19129u;

    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }

        public final float a() {
            return G.f19114w;
        }
    }

    public G(C2732n c2732n, String str) {
        super(str);
        this.f19115g = c2732n;
        this.f19116h = str;
        this.f19117i = KLineManager.f142490O.a();
        this.f19121m = new HashMap();
        this.f19126r = new ArrayList();
        this.f19127s = new HashMap();
        G();
    }

    public static double g(double d10, double d11, double d12, double d13, double d14, double d15) {
        double d16 = d14 - d12;
        double d17 = d10 - d12;
        double d18 = d15 - d13;
        double d19 = d11 - d13;
        double d20 = (d18 * d19) + (d16 * d17);
        if (d20 <= 0.0d) {
            return Math.sqrt((d19 * d19) + (d17 * d17));
        }
        double d21 = (d18 * d18) + (d16 * d16);
        if (d20 >= d21) {
            double d22 = d10 - d14;
            double d23 = d11 - d15;
            return Math.sqrt((d23 * d23) + (d22 * d22));
        }
        double d24 = d20 / d21;
        double d25 = d10 - ((d16 * d24) + d12);
        double d26 = d11 - ((d18 * d24) + d13);
        return Math.sqrt((d26 * d26) + (d25 * d25));
    }

    public static boolean i(DrawingItem drawingItem) {
        if (drawingItem == null) {
            return false;
        }
        return AbstractC7609s.f(drawingItem.getName(), "CHoriSegLineObject") || AbstractC7609s.f(drawingItem.getName(), "CHoriStraightLineObject") || AbstractC7609s.f(drawingItem.getName(), "CHoriRayLineObject") || AbstractC7609s.f(drawingItem.getName(), "CVertiStraightLineObject") || AbstractC7609s.f(drawingItem.getName(), "CPriceLineObject") || AbstractC7609s.f(drawingItem.getName(), "CFibRetraceObject") || AbstractC7609s.f(drawingItem.getName(), "CFibSpiralObject") || AbstractC7609s.f(drawingItem.getName(), "CFibFansObject") || AbstractC7609s.f(drawingItem.getName(), "CFibExtensionObject") || AbstractC7609s.f(drawingItem.getName(), "CFibRetraceSegLineObject") || AbstractC7609s.f(drawingItem.getName(), "CBandLineObject") || AbstractC7609s.f(drawingItem.getName(), "CBandSegLineObject") || AbstractC7609s.f(drawingItem.getName(), "CSegLineObject") || AbstractC7609s.f(drawingItem.getName(), "CStraightLineObject") || AbstractC7609s.f(drawingItem.getName(), "CRayLineObject") || AbstractC7609s.f(drawingItem.getName(), "CArrowLineObject") || AbstractC7609s.f(drawingItem.getName(), "CTriParallelLineObject") || AbstractC7609s.f(drawingItem.getName(), "CRectangleObject") || AbstractC7609s.f(drawingItem.getName(), "CPriceDateRulerObject") || AbstractC7609s.f(drawingItem.getName(), "CPolylineObject");
    }

    public static boolean j(DrawingItem drawingItem, float f10, float f11) {
        PointF pointF;
        PointF pointF2;
        String name = drawingItem.getName();
        if (AbstractC7609s.f(name, "CRectangleObject")) {
            List<PointF> decisionPoints = drawingItem.getDecisionPoints();
            PointF pointF3 = (PointF) Sf.z.r0(decisionPoints, 0);
            if (pointF3 == null || (pointF2 = (PointF) Sf.z.r0(decisionPoints, 2)) == null) {
                return false;
            }
            float fMin = Math.min(pointF3.x, pointF2.x);
            float f12 = f19114w;
            return new Region((int) (fMin - f12), (int) (Math.min(pointF3.y, pointF2.y) - f12), (int) (Math.max(pointF3.x, pointF2.x) + f12), (int) (Math.max(pointF3.y, pointF2.y) + f12)).contains((int) f10, (int) f11);
        }
        if (!AbstractC7609s.f(name, "CPriceDateRulerObject")) {
            return false;
        }
        List<PointF> decisionPoints2 = drawingItem.getDecisionPoints();
        PointF pointF4 = (PointF) Sf.z.r0(decisionPoints2, 0);
        if (pointF4 == null || (pointF = (PointF) Sf.z.r0(decisionPoints2, 1)) == null) {
            return false;
        }
        float fMin2 = Math.min(pointF4.x, pointF.x);
        float f13 = f19114w;
        return new Region((int) (fMin2 - f13), (int) (Math.min(pointF4.y, pointF.y) - f13), (int) (Math.max(pointF4.x, pointF.x) + f13), (int) (Math.max(pointF4.y, pointF.y) + f13)).contains((int) f10, (int) f11);
    }

    public final boolean A() {
        return this.f19118j;
    }

    public final boolean B() {
        return this.f19122n;
    }

    public final boolean C(DrawingItem drawingItem, float f10, float f11) {
        if (nk.d.f134196a.e(drawingItem.getName())) {
            return j(drawingItem, f10, f11);
        }
        return r(drawingItem, f10, f11) < ((double) f19114w);
    }

    public final boolean D(double d10, double d11, double d12, double d13) {
        double d14 = d12 - d10;
        double d15 = d13 - d11;
        return Math.sqrt((d15 * d15) + (d14 * d14)) < ((double) f19114w);
    }

    public final void E() {
        DrawingItem drawingItem = this.f19128t;
        if (drawingItem == null) {
            return;
        }
        DrawingItem.Options options = drawingItem.getOptions();
        if (options == null) {
            options = new DrawingItem.Options(null, null, null, null, null, null, null, null, null, null, null, null, 4095, null);
        }
        Boolean boolIsLocked = options.isLocked();
        options.setLocked(Boolean.valueOf(!(boolIsLocked != null ? boolIsLocked.booleanValue() : false)));
        drawingItem.setOptions(options);
    }

    /* JADX WARN: Code duplicated, block: B:103:0x0343  */
    /* JADX WARN: Code duplicated, block: B:105:0x0346  */
    /* JADX WARN: Code duplicated, block: B:106:0x0348  */
    /* JADX WARN: Code duplicated, block: B:108:0x034b  */
    /* JADX WARN: Code duplicated, block: B:109:0x0350  */
    /* JADX WARN: Code duplicated, block: B:119:0x03b5  */
    /* JADX WARN: Code duplicated, block: B:125:0x03e2  */
    /* JADX WARN: Code duplicated, block: B:127:0x0403  */
    /* JADX WARN: Code duplicated, block: B:129:0x0407  */
    /* JADX WARN: Code duplicated, block: B:131:0x040e  */
    /* JADX WARN: Code duplicated, block: B:133:0x041c  */
    /* JADX WARN: Code duplicated, block: B:138:0x043a  */
    /* JADX WARN: Code duplicated, block: B:144:0x0457  */
    /* JADX WARN: Code duplicated, block: B:154:? A[RETURN, SYNTHETIC] */
    /* JADX WARN: Code duplicated, block: B:155:? A[RETURN, SYNTHETIC] */
    /* JADX WARN: Code duplicated, block: B:156:? A[RETURN, SYNTHETIC] */
    /* JADX WARN: Code duplicated, block: B:40:0x0166  */
    /* JADX WARN: Code duplicated, block: B:42:0x0187  */
    /* JADX WARN: Code duplicated, block: B:43:0x018b  */
    /* JADX WARN: Code duplicated, block: B:45:0x0199  */
    /* JADX WARN: Code duplicated, block: B:46:0x019f  */
    /* JADX WARN: Code duplicated, block: B:72:0x02ab  */
    /* JADX WARN: Code duplicated, block: B:76:0x02c0  */
    /* JADX WARN: Code duplicated, block: B:79:0x02e4  */
    /* JADX WARN: Code duplicated, block: B:81:0x02e9  */
    /* JADX WARN: Code duplicated, block: B:87:0x02fe  */
    /* JADX WARN: Code duplicated, block: B:90:0x0307  */
    /* JADX WARN: Code duplicated, block: B:92:0x0320  */
    /* JADX WARN: Code duplicated, block: B:93:0x0322  */
    /* JADX WARN: Code duplicated, block: B:96:0x0326  */
    /* JADX WARN: Code duplicated, block: B:98:0x0329  */
    /* JADX WARN: Code duplicated, block: B:99:0x032e  */
    /* JADX WARN: Code restructure failed: missing block: B:120:0x03bd, code lost:
    
        if (r4.equals("CHoriRayLineObject") == false) goto L121;
     */
    /* JADX WARN: Instruction removed from duplicated block: B:40:0x0166, please report this as an issue */
    /*
        Code decompiled incorrectly, please refer to instructions dump.
        To view partially-correct add '--show-bad-code' argument
    */
    public final void F(float r25, float r26) {
        /*
            Method dump skipped, instruction units count: 1152
            To view this dump add '--comments-level debug' option
        */
        throw new UnsupportedOperationException("Method not decompiled: Rj.G.F(float, float):void");
    }

    public final void G() {
        ArrayList arrayList;
        DrawingItem drawingItem = this.f19128t;
        if (drawingItem != null) {
            drawingItem.setSelected(false);
        }
        this.f19128t = null;
        this.f19117i.N().setValue(Boolean.FALSE);
        G gI = this.f19115g.b().i(this.f19116h);
        if (gI == null || (arrayList = gI.f19126r) == null) {
            return;
        }
        Iterator it = arrayList.iterator();
        while (it.hasNext()) {
            ((DrawingItem) it.next()).setSelected(false);
        }
    }

    public final float H(long j10) {
        C2765z c2765zD;
        y1 y1VarM;
        C2702d c2702dE = this.f19115g.b().e(this.f19116h + ".main");
        if (c2702dE == null || (c2765zD = this.f19115g.d()) == null || (y1VarM = this.f19115g.b().m(this.f19116h)) == null) {
            return 0.0f;
        }
        float fC = H.f19133a.c(c2765zD.C(), j10, y1VarM.u());
        if (fC < 0.0f) {
            return -1.0f;
        }
        return fC - (y1VarM.w() + c2702dE.u());
    }

    public final float I(double d10) {
        AbstractC2759w0 abstractC2759w0L = this.f19115g.b().l(this.f19116h + ".main");
        if (abstractC2759w0L == null) {
            return 0.0f;
        }
        return abstractC2759w0L.S(d10);
    }

    public final void J(boolean z10, int i10) {
        DrawingItem.Options options;
        DrawingItem drawingItem = this.f19128t;
        if (drawingItem == null || (options = drawingItem.getOptions()) == null) {
            return;
        }
        options.setShowBackground(Boolean.valueOf(z10));
        options.setBackground(Integer.valueOf(i10));
    }

    public final void K(int i10) {
        DrawingItem drawingItem = this.f19128t;
        if (drawingItem == null) {
            return;
        }
        DrawingItem.Options options = drawingItem.getOptions();
        if (options == null) {
            options = new DrawingItem.Options(null, null, null, null, null, null, null, null, null, null, null, null, 4095, null);
        }
        options.setLineColor(Integer.valueOf(i10));
        drawingItem.setOptions(options);
    }

    public final void L(List list) {
        DrawingItem drawingItem = this.f19128t;
        if (drawingItem == null) {
            return;
        }
        DrawingItem.Options options = drawingItem.getOptions();
        if (options == null) {
            options = new DrawingItem.Options(null, null, null, null, null, null, null, null, null, null, null, null, 4095, null);
        }
        options.setLineDash(list);
        drawingItem.setOptions(options);
    }

    public final void M(float f10) {
        DrawingItem drawingItem = this.f19128t;
        if (drawingItem == null) {
            return;
        }
        DrawingItem.Options options = drawingItem.getOptions();
        if (options == null) {
            options = new DrawingItem.Options(null, null, null, null, null, null, null, null, null, null, null, null, 4095, null);
        }
        options.setLineWidth(Float.valueOf(f10));
        drawingItem.setOptions(options);
    }

    public final long h(float f10) {
        Sj.a aVarC;
        y1 y1VarM;
        C2765z c2765zD = this.f19115g.d();
        if (c2765zD == null || (aVarC = c2765zD.C()) == null || (y1VarM = this.f19115g.b().m(this.f19116h)) == null) {
            return 0L;
        }
        return H.f19133a.b(aVarC, f10, y1VarM.u(), y1VarM.w());
    }

    public final double l(float f10) {
        AbstractC2759w0 abstractC2759w0L = this.f19115g.b().l(this.f19116h + ".main");
        if (abstractC2759w0L == null) {
            return 0.0d;
        }
        return abstractC2759w0L.R(f10);
    }

    /* JADX WARN: Code duplicated, block: B:53:0x0109  */
    public final void m(float f10, float f11) {
        Object next;
        DrawingItem drawingItem;
        DrawingItem drawingItem2;
        Object next2;
        if (this.f19117i.q(16) != 0) {
            p(f10, f11);
            return;
        }
        LinkedHashMap linkedHashMap = new LinkedHashMap();
        int i10 = 0;
        for (Object obj : this.f19126r) {
            int i11 = i10 + 1;
            if (i10 < 0) {
                Sf.r.x();
            }
            DrawingItem drawingItem3 = (DrawingItem) obj;
            if (i(drawingItem3)) {
                if (!nk.d.f134196a.e(drawingItem3.getName())) {
                    double dR = r(drawingItem3, f10, f11);
                    if (dR < f19114w) {
                        this.f19127s.put(Double.valueOf(dR), drawingItem3);
                    }
                } else if (j(drawingItem3, f10, f11)) {
                    linkedHashMap.put(Integer.valueOf(i10), drawingItem3);
                }
            }
            i10 = i11;
        }
        if (linkedHashMap.isEmpty()) {
            Iterator it = this.f19127s.entrySet().iterator();
            if (it.hasNext()) {
                next2 = it.next();
                if (it.hasNext()) {
                    double dDoubleValue = ((Number) ((Map.Entry) next2).getKey()).doubleValue();
                    do {
                        Object next3 = it.next();
                        double dDoubleValue2 = ((Number) ((Map.Entry) next3).getKey()).doubleValue();
                        if (Double.compare(dDoubleValue, dDoubleValue2) > 0) {
                            next2 = next3;
                            dDoubleValue = dDoubleValue2;
                        }
                    } while (it.hasNext());
                }
            } else {
                next2 = null;
            }
            Map.Entry entry = (Map.Entry) next2;
            if (entry != null) {
                drawingItem = (DrawingItem) entry.getValue();
            } else {
                drawingItem = null;
            }
        } else {
            Iterator it2 = linkedHashMap.entrySet().iterator();
            if (it2.hasNext()) {
                next = it2.next();
                if (it2.hasNext()) {
                    int iIntValue = ((Number) ((Map.Entry) next).getKey()).intValue();
                    do {
                        Object next4 = it2.next();
                        int iIntValue2 = ((Number) ((Map.Entry) next4).getKey()).intValue();
                        if (iIntValue > iIntValue2) {
                            next = next4;
                            iIntValue = iIntValue2;
                        }
                    } while (it2.hasNext());
                }
            } else {
                next = null;
            }
            Map.Entry entry2 = (Map.Entry) next;
            if (entry2 != null) {
                drawingItem = (DrawingItem) entry2.getValue();
            } else {
                drawingItem = null;
            }
        }
        if (i(drawingItem)) {
            if (drawingItem != null) {
                drawingItem.setSelected(true);
            }
            this.f19128t = drawingItem;
            this.f19117i.N().setValue(Boolean.TRUE);
        } else {
            this.f19128t = null;
        }
        DrawingItem drawingItem4 = this.f19128t;
        if (drawingItem4 == null) {
            Iterator it3 = this.f19126r.iterator();
            while (it3.hasNext()) {
                ((DrawingItem) it3.next()).setSelected(false);
            }
            this.f19117i.N().setValue(Boolean.FALSE);
        } else {
            if (!AbstractC7609s.f(this.f19129u, drawingItem4) && (drawingItem2 = this.f19129u) != null) {
                drawingItem2.setSelected(false);
            }
            this.f19129u = this.f19128t;
        }
        this.f19127s.clear();
    }

    public final void n() {
        this.f19126r.clear();
        C2765z c2765zD = this.f19115g.d();
        if (c2765zD != null) {
            c2765zD.b0((DrawingItem[]) this.f19126r.toArray(new DrawingItem[0]));
        }
        this.f19128t = null;
        this.f19117i.N().setValue(Boolean.FALSE);
    }

    public final void o() {
        DrawingItem drawingItem = this.f19128t;
        if (drawingItem == null) {
            return;
        }
        this.f19126r.remove(drawingItem);
        C2765z c2765zD = this.f19115g.d();
        if (c2765zD != null) {
            c2765zD.b0((DrawingItem[]) this.f19126r.toArray(new DrawingItem[0]));
        }
        this.f19128t = null;
        this.f19117i.N().setValue(Boolean.FALSE);
    }

    /* JADX WARN: Code duplicated, block: B:35:0x024d  */
    /* JADX WARN: Code duplicated, block: B:38:0x02ea  */
    /* JADX WARN: Code duplicated, block: B:41:0x02fe  */
    /* JADX WARN: Multi-variable type inference failed */
    public void p(float f10, float f11) {
        DrawingPoint[] drawingPointArr;
        int i10;
        boolean z10;
        DrawingPoint[] drawingPointArr2;
        int i11;
        DrawingItem drawingItem;
        C2765z c2765zD;
        int i12;
        C2702d c2702dE = this.f19115g.b().e(this.f19116h + ".main");
        if (c2702dE == null) {
            return;
        }
        int iQ = this.f19117i.q(16);
        nk.d dVar = nk.d.f134196a;
        String strA = dVar.a(iQ);
        int iD = dVar.d(strA);
        if (AbstractC7609s.f(strA, "CEmptyObject") || iD == 0) {
            return;
        }
        p292ng.g gVar = new p292ng.g(c2702dE.u(), c2702dE.y());
        p292ng.g gVar2 = new p292ng.g(Xj.a.d(40) + c2702dE.z(), c2702dE.p() - Xj.a.d(8));
        if (iD != 0) {
            if (iD != 1) {
                if (iD == 2) {
                    i12 = 1;
                    float f12 = 150;
                    float f13 = 50;
                    drawingPointArr = new DrawingPoint[]{new DrawingPoint(h(nk.A.a(f10 - f12, gVar)), l(nk.A.a(f11 + f13, gVar2)), 0), new DrawingPoint(h(nk.A.a(f12 + f10, gVar)), l(nk.A.a(f11 - f13, gVar2)), 0)};
                } else if (iD == 3) {
                    i12 = 1;
                    float f14 = 150;
                    float f15 = 50;
                    float f16 = f11 + f15;
                    float f17 = f14 + f10;
                    drawingPointArr = new DrawingPoint[]{new DrawingPoint(h(nk.A.a(f10 - f14, gVar)), l(nk.A.a(f16, gVar2)), 0), new DrawingPoint(h(nk.A.a(f17, gVar)), l(nk.A.a(f16, gVar2)), 0), new DrawingPoint(h(nk.A.a(f17, gVar)), l(nk.A.a(f11 - f15, gVar2)), 0)};
                } else if (iD != 4) {
                    drawingPointArr = new DrawingPoint[0];
                    strA = strA;
                    i10 = 1;
                } else {
                    float fA = nk.A.a(f10, gVar);
                    float fA2 = nk.A.a(f11, gVar2);
                    i12 = 1;
                    float f18 = 200;
                    float fA3 = nk.A.a(f10 + f18, gVar);
                    float fA4 = nk.A.a(f11 - f18, gVar2);
                    drawingPointArr = new DrawingPoint[]{new DrawingPoint(h(fA), l(fA2), 0), new DrawingPoint(h(fA3), l(fA2), 0), new DrawingPoint(h(fA3), l(fA4), 0), new DrawingPoint(h(fA), l(fA4), 0)};
                }
                i10 = i12;
            } else {
                drawingPointArr = new DrawingPoint[]{new DrawingPoint(h(nk.A.a(f10, gVar)), l(nk.A.a(f11, gVar2)), 0)};
            }
            if (iQ != i10 || iQ == 3) {
                float fA5 = nk.A.a(f10, gVar);
                float fA6 = nk.A.a(f11, gVar2);
                z10 = false;
                drawingPointArr2 = new DrawingPoint[]{new DrawingPoint(h(fA5), l(fA6), 0), new DrawingPoint(h(nk.A.a(f10 + 100, gVar)), l(fA6), 0)};
            } else {
                if (iQ != 6) {
                    if (iQ == 13) {
                        float f19 = 150;
                        drawingPointArr2 = new DrawingPoint[]{new DrawingPoint(h(nk.A.a(f10 - f19, gVar)), l(nk.A.a(f11 + f19, gVar2)), 0), new DrawingPoint(h(nk.A.a(f10 + f19, gVar)), l(nk.A.a(f11 - f19, gVar2)), 0)};
                    }
                    z10 = false;
                } else {
                    float fA7 = nk.A.a(f10, gVar);
                    drawingPointArr = new DrawingPoint[]{new DrawingPoint(h(fA7), l(nk.A.a(f11, gVar2)), 0), new DrawingPoint(h(fA7), l(nk.A.a(f11 - 160, gVar2)), 0)};
                }
                drawingPointArr2 = drawingPointArr;
                z10 = false;
            }
            Color.parseColor("#B3EEEEEE");
            int color = Color.parseColor("#1990FF");
            Color.parseColor("#00000000");
            Boolean bool = Boolean.FALSE;
            i11 = z10;
            DrawingItem drawingItem2 = new DrawingItem(drawingPointArr2, strA, "", new DrawingItem.Options(bool, Float.valueOf(1.0f), Integer.valueOf(color), null, bool, Sf.r.t(Float.valueOf(0.0f), Float.valueOf(0.0f)), null, null, null, null, null, null), true, null, 32, null);
            this.f19117i.N().setValue(Boolean.TRUE);
            drawingItem = this.f19129u;
            if (drawingItem != null) {
                drawingItem.setSelected(i11);
            }
            this.f19128t = drawingItem2;
            this.f19129u = drawingItem2;
            this.f19126r.add(drawingItem2);
            c2765zD = this.f19115g.d();
            if (c2765zD != null) {
                c2765zD.b0((DrawingItem[]) this.f19126r.toArray(new DrawingItem[i11]));
            }
            dVar.f("CEmptyObject");
            this.f19117i.U().setValue(bool);
        }
        drawingPointArr = new DrawingPoint[0];
        i10 = 1;
        if (iQ != i10) {
            float fA8 = nk.A.a(f10, gVar);
            float fA9 = nk.A.a(f11, gVar2);
            z10 = false;
            drawingPointArr2 = new DrawingPoint[]{new DrawingPoint(h(fA8), l(fA9), 0), new DrawingPoint(h(nk.A.a(f10 + 100, gVar)), l(fA9), 0)};
        } else {
            float fA10 = nk.A.a(f10, gVar);
            float fA11 = nk.A.a(f11, gVar2);
            z10 = false;
            drawingPointArr2 = new DrawingPoint[]{new DrawingPoint(h(fA10), l(fA11), 0), new DrawingPoint(h(nk.A.a(f10 + 100, gVar)), l(fA11), 0)};
        }
        Color.parseColor("#B3EEEEEE");
        int color2 = Color.parseColor("#1990FF");
        Color.parseColor("#00000000");
        Boolean bool2 = Boolean.FALSE;
        i11 = z10;
        DrawingItem drawingItem3 = new DrawingItem(drawingPointArr2, strA, "", new DrawingItem.Options(bool2, Float.valueOf(1.0f), Integer.valueOf(color2), null, bool2, Sf.r.t(Float.valueOf(0.0f), Float.valueOf(0.0f)), null, null, null, null, null, null), true, null, 32, null);
        this.f19117i.N().setValue(Boolean.TRUE);
        drawingItem = this.f19129u;
        if (drawingItem != null) {
            drawingItem.setSelected(i11);
        }
        this.f19128t = drawingItem3;
        this.f19129u = drawingItem3;
        this.f19126r.add(drawingItem3);
        c2765zD = this.f19115g.d();
        if (c2765zD != null) {
            c2765zD.b0((DrawingItem[]) this.f19126r.toArray(new DrawingItem[i11]));
        }
        dVar.f("CEmptyObject");
        this.f19117i.U().setValue(bool2);
    }

    public final void q() {
        this.f19118j = false;
        this.f19119k = false;
        this.f19120l = 0;
        this.f19121m.clear();
        this.f19122n = false;
    }

    public final double r(DrawingItem drawingItem, float f10, float f11) {
        double d10;
        List<PointF> decisionPoints = drawingItem.getDecisionPoints();
        double d11 = Double.MAX_VALUE;
        if (decisionPoints.size() < 2) {
            return Double.MAX_VALUE;
        }
        ArrayList arrayList = new ArrayList();
        String name = drawingItem.getName();
        int i10 = 0;
        if (AbstractC7609s.f(name, "CFibRetraceObject") || AbstractC7609s.f(name, "CTriParallelLineObject")) {
            d10 = Double.MAX_VALUE;
            if (decisionPoints.size() % 2 != 0) {
                return Double.MAX_VALUE;
            }
            p292ng.e eVarX = p292ng.i.x(p292ng.i.y(0, decisionPoints.size()), 2);
            int iK = eVarX.k();
            int iO = eVarX.o();
            int iQ = eVarX.q();
            if ((iQ > 0 && iK <= iO) || (iQ < 0 && iO <= iK)) {
                while (true) {
                    PointF pointF = decisionPoints.get(iK);
                    int i11 = iK + 1;
                    arrayList.add(Double.valueOf(g(f10, f11, pointF.x, pointF.y, decisionPoints.get(i11).x, decisionPoints.get(i11).y)));
                    if (iK == iO) {
                        break;
                    }
                    iK += iQ;
                }
            }
        } else {
            for (Object obj : decisionPoints) {
                int i12 = i10 + 1;
                if (i10 < 0) {
                    Sf.r.x();
                }
                PointF pointF2 = (PointF) obj;
                if (i10 < decisionPoints.size() - 1) {
                    arrayList.add(Double.valueOf(g(f10, f11, pointF2.x, pointF2.y, decisionPoints.get(i12).x, decisionPoints.get(i12).y)));
                }
                i10 = i12;
                d11 = d11;
            }
            d10 = d11;
        }
        Double dM0 = Sf.z.M0(arrayList);
        return dM0 != null ? dM0.doubleValue() : d10;
    }

    public final DrawingPoint s() {
        DrawingItem drawingItem;
        DrawingPoint[] points;
        if (!this.f19118j || (drawingItem = this.f19128t) == null || (points = drawingItem.getPoints()) == null) {
            return null;
        }
        return (DrawingPoint) AbstractC2801o.r0(points, this.f19120l);
    }

    public final int t() {
        return this.f19123o;
    }

    public final float u() {
        return this.f19124p;
    }

    public final float v() {
        return this.f19125q;
    }

    public final DrawingItem w() {
        return this.f19128t;
    }

    public final DrawingItem.Options x() {
        DrawingItem drawingItem = this.f19128t;
        if (drawingItem == null) {
            return null;
        }
        return drawingItem.getOptions();
    }

    public final boolean y(float f10, float f11) {
        this.f19121m.clear();
        boolean z10 = false;
        this.f19118j = false;
        this.f19119k = false;
        this.f19120l = 0;
        DrawingItem drawingItem = this.f19128t;
        if (drawingItem == null) {
            return false;
        }
        DrawingPoint[] points = drawingItem.getPoints();
        int length = points.length;
        int i10 = 0;
        int i11 = 0;
        while (i10 < length) {
            DrawingPoint drawingPoint = points[i10];
            int i12 = i11 + 1;
            double dH = H(drawingPoint.getX());
            double dI = I(drawingPoint.getY());
            int i13 = i10;
            int i14 = i11;
            boolean z11 = z10;
            if (D(dH, dI, f10, f11)) {
                this.f19120l = i14;
                this.f19118j = true;
            }
            i10 = i13 + 1;
            i11 = i12;
            z10 = z11;
        }
        boolean z12 = z10;
        if (!this.f19118j && C(drawingItem, f10, f11)) {
            this.f19119k = true;
        }
        if (this.f19119k) {
            DrawingPoint[] points2 = drawingItem.getPoints();
            int length2 = points2.length;
            int i15 = z12 ? 1 : 0;
            int i16 = i15;
            while (i15 < length2) {
                DrawingPoint drawingPoint2 = points2[i15];
                int i17 = i16 + 1;
                float fH = f10 - H(drawingPoint2.getX());
                float fI = f11 - I(drawingPoint2.getY());
                HashMap map = this.f19121m;
                Integer numValueOf = Integer.valueOf(i16);
                float[] fArr = new float[2];
                fArr[z12 ? 1 : 0] = fH;
                fArr[1] = fI;
                map.put(numValueOf, fArr);
                i15++;
                i16 = i17;
            }
        }
        if (this.f19118j || this.f19119k) {
            return true;
        }
        return z12;
    }

    /* JADX WARN: Code duplicated, block: B:21:0x0041 A[PHI: r1
      0x0041: PHI (r1v1 sp.aicoin_kline.chart.data.drawing.DrawingItem) = (r1v0 sp.aicoin_kline.chart.data.drawing.DrawingItem), (r1v15 sp.aicoin_kline.chart.data.drawing.DrawingItem) binds: [B:10:0x001e, B:19:0x003e] A[DONT_GENERATE, DONT_INLINE]] */
    /* JADX WARN: Code duplicated, block: B:24:0x0048  */
    /* JADX WARN: Code duplicated, block: B:27:0x0052  */
    /* JADX WARN: Code duplicated, block: B:89:0x005c A[SYNTHETIC] */
    /* JADX WARN: Code duplicated, block: B:90:0x005a A[SYNTHETIC] */
    /* JADX WARN: Code duplicated, block: B:91:? A[LOOP:3: B:25:0x004c->B:91:?, LOOP_END, SYNTHETIC] */
    public final void z() {
        Collection<DrawingItem> arrayList;
        boolean z10;
        Iterator it;
        C2765z c2765zD;
        Object next;
        Object next2;
        DrawingItem[] drawingItemArrE;
        C2765z c2765zD2 = this.f19115g.d();
        if (c2765zD2 == null || (drawingItemArrE = c2765zD2.E()) == null || (arrayList = AbstractC2801o.r1(drawingItemArrE)) == null) {
            arrayList = new ArrayList();
        }
        DrawingItem drawingItem = this.f19128t;
        if (drawingItem == null) {
            Iterator it2 = this.f19126r.iterator();
            do {
                if (!it2.hasNext()) {
                    next2 = null;
                    break;
                }
                next2 = it2.next();
            } while (!((DrawingItem) next2).isSelected());
            drawingItem = (DrawingItem) next2;
            if (drawingItem == null) {
                z10 = false;
            } else {
                if (!arrayList.isEmpty()) {
                    it = arrayList.iterator();
                    while (true) {
                        if (it.hasNext()) {
                            if (((DrawingItem) it.next()) == drawingItem) {
                                z10 = false;
                            }
                        }
                    }
                }
                z10 = true;
            }
        } else {
            if (!arrayList.isEmpty()) {
                it = arrayList.iterator();
                while (true) {
                    if (it.hasNext()) {
                        if (((DrawingItem) it.next()) == drawingItem) {
                            z10 = false;
                        }
                    }
                }
            }
            z10 = true;
        }
        for (DrawingItem drawingItem2 : arrayList) {
            Iterator it3 = this.f19126r.iterator();
            while (true) {
                if (!it3.hasNext()) {
                    next = null;
                    break;
                }
                next = it3.next();
                String id2 = ((DrawingItem) next).getId();
                if (id2.length() > 0 && AbstractC7609s.f(id2, drawingItem2.getId())) {
                    break;
                }
            }
            DrawingItem drawingItem3 = (DrawingItem) next;
            if (drawingItem3 == null) {
                this.f19126r.add(drawingItem2);
            } else if (drawingItem3 != drawingItem2) {
                if (drawingItem3.isSelected() || drawingItem3 == this.f19128t) {
                    z10 = z10 || drawingItem3 != drawingItem2;
                } else {
                    drawingItem3.copyWith(drawingItem2);
                }
            }
        }
        if (!z10 || (c2765zD = this.f19115g.d()) == null) {
            return;
        }
        c2765zD.b0((DrawingItem[]) this.f19126r.toArray(new DrawingItem[0]));
    }
}
