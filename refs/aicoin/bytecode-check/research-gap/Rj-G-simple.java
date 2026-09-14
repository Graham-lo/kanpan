package Rj;

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
import org.apache.tika.utils.StringUtils;
import org.bouncycastle.asn1.x509.DisplayText;
import sp.aicoin_kline.chart.data.drawing.DrawingItem;
import sp.aicoin_kline.chart.data.drawing.DrawingPoint;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: /private/tmp/claude-501/-Users-mdd-kanpan/e5a5bf1c-f427-4144-8ae2-a961a321a4b4/scratchpad/aic/dec/classes7.dex */
public class G extends AbstractC0161j0 {
    public static final a v = null;
    public static final float w = 0.0f;
    public final C0172n g;
    public final String h;
    public final KLineManager i;
    public boolean j;
    public boolean k;
    public int l;
    public final HashMap m;
    public boolean n;
    public int o;
    public float p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public float f13q;
    public final ArrayList r;
    public final HashMap s;
    public DrawingItem t;
    public DrawingItem u;

    public static final class a {
        public a(DefaultConstructorMarker r1) {
        }

        public final float a() {
            return G.k();
        }
    }

    static {
        v = new a(null);
        w = Xj.a.a(9.5f);
    }

    public G(C0172n r1, String r2) {
        super(r2);
        this.g = r1;
        this.h = r2;
        this.i = KLineManager.O.a();
        this.m = new HashMap();
        this.r = new ArrayList();
        this.s = new HashMap();
        G();
    }

    public static double g(double r12, double r14, double r16, double r18, double r20, double r22) {
        double r0 = r20 - r16;
        double r2 = r12 - r16;
        double r6 = r22 - r18;
        double r8 = r14 - r18;
        double r10 = r6 * r8;
        double r11 = r10 + (r0 * r2);
        if (r11 > 0.0d) goto L6;
        double r9 = r8 * r8;
        return Math.sqrt(r9 + (r2 * r2));
    L6:
        double r4 = r6 * r6;
        double r5 = r4 + (r0 * r0);
        if (r11 < r5) goto L10;
        double r13 = r12 - r20;
        double r15 = r14 - r22;
        double r17 = r15 * r15;
        return Math.sqrt(r17 + (r13 * r13));
    L10:
        double r19 = r11 / r5;
        double r110 = r12 - ((r0 * r19) + r16);
        double r111 = r14 - ((r6 * r19) + r18);
        double r112 = r111 * r111;
        return Math.sqrt(r112 + (r110 * r110));
    }

    public static boolean i(DrawingItem r3) {
        if (r3 != null) goto L6;
        return false;
    L6:
        if (hg.s.f(r3.getName(), "CHoriSegLineObject") == false) goto L8;
        return true;
    L8:
        if (hg.s.f(r3.getName(), "CHoriStraightLineObject") == false) goto L10;
        return true;
    L10:
        if (hg.s.f(r3.getName(), "CHoriRayLineObject") == false) goto L12;
        return true;
    L12:
        if (hg.s.f(r3.getName(), "CVertiStraightLineObject") == false) goto L14;
        return true;
    L14:
        if (hg.s.f(r3.getName(), "CPriceLineObject") == false) goto L16;
        return true;
    L16:
        if (hg.s.f(r3.getName(), "CFibRetraceObject") == false) goto L18;
        return true;
    L18:
        if (hg.s.f(r3.getName(), "CFibSpiralObject") == false) goto L20;
        return true;
    L20:
        if (hg.s.f(r3.getName(), "CFibFansObject") == false) goto L22;
        return true;
    L22:
        if (hg.s.f(r3.getName(), "CFibExtensionObject") == false) goto L24;
        return true;
    L24:
        if (hg.s.f(r3.getName(), "CFibRetraceSegLineObject") == false) goto L26;
        return true;
    L26:
        if (hg.s.f(r3.getName(), "CBandLineObject") == false) goto L28;
        return true;
    L28:
        if (hg.s.f(r3.getName(), "CBandSegLineObject") == false) goto L30;
        return true;
    L30:
        if (hg.s.f(r3.getName(), "CSegLineObject") == false) goto L32;
        return true;
    L32:
        if (hg.s.f(r3.getName(), "CStraightLineObject") == false) goto L34;
        return true;
    L34:
        if (hg.s.f(r3.getName(), "CRayLineObject") == false) goto L36;
        return true;
    L36:
        if (hg.s.f(r3.getName(), "CArrowLineObject") == false) goto L38;
        return true;
    L38:
        if (hg.s.f(r3.getName(), "CTriParallelLineObject") == false) goto L40;
        return true;
    L40:
        if (hg.s.f(r3.getName(), "CRectangleObject") == false) goto L42;
        return true;
    L42:
        if (hg.s.f(r3.getName(), "CPriceDateRulerObject") == false) goto L44;
        return true;
    L44:
        if (hg.s.f(r3.getName(), "CPolylineObject") == true) goto L67;
        return false;
    L67:
        return true;
    }

    public static boolean j(DrawingItem r6, float r7, float r8) {
        String r0 = r6.getName();
        if (hg.s.f(r0, "CRectangleObject") == false) goto L13;
        List<PointF> r9 = r6.getDecisionPoints();
        PointF r1 = (PointF) Sf.z.r0(r9, 0);
        if (r1 != null) goto L7;
        return false;
    L7:
        PointF r10 = (PointF) Sf.z.r0(r9, 2);
        if (r10 != null) goto L10;
        return false;
    L10:
        float r2 = Math.min(r1.x, r10.x);
        float r3 = w;
        float r4 = Math.min(r1.y, r10.y) - r3;
        float r5 = Math.max(r1.x, r10.x) + r3;
        float r11 = Math.max(r1.y, r10.y) + r3;
        return new Region((int) (r2 - r3), (int) r4, (int) r5, (int) r11).contains((int) r7, (int) r8);
    L13:
        if (hg.s.f(r0, "CPriceDateRulerObject") == false) goto L22;
        List<PointF> r12 = r6.getDecisionPoints();
        PointF r13 = (PointF) Sf.z.r0(r12, 0);
        if (r13 != null) goto L17;
        return false;
    L17:
        PointF r14 = (PointF) Sf.z.r0(r12, 1);
        if (r14 != null) goto L20;
        return false;
    L20:
        float r15 = Math.min(r13.x, r14.x);
        float r16 = w;
        float r17 = Math.min(r13.y, r14.y) - r16;
        float r18 = Math.max(r13.x, r14.x) + r16;
        float r19 = Math.max(r13.y, r14.y) + r16;
        return new Region((int) (r15 - r16), (int) r17, (int) r18, (int) r19).contains((int) r7, (int) r8);
    L22:
        return false;
    }

    public static final /* synthetic */ float k() {
        return w;
    }

    public final boolean A() {
        return this.j;
    }

    public final boolean B() {
        return this.n;
    }

    public final boolean C(DrawingItem r3, float r4, float r5) {
        if (nk.d.a.e(r3.getName()) == false) goto L7;
        return j(r3, r4, r5);
    L7:
        if (r(r3, r4, r5) >= w) goto L10;
        return true;
    L10:
        return false;
    }

    public final boolean D(double r1, double r3, double r5, double r7) {
        double r6 = r5 - r1;
        double r8 = r7 - r3;
        if (Math.sqrt((r8 * r8) + (r6 * r6)) >= w) goto L6;
        return true;
    L6:
        return false;
    }

    public final void E() {
        DrawingItem r1 = this.t;
        if (r1 != null) goto L5;
        return;
    L5:
        DrawingItem.Options r2 = r1.getOptions();
        if (r2 != null) goto L8;
        r2 = new DrawingItem.Options(null, null, null, null, null, null, null, null, null, null, null, null, 4095, null);
    L8:
        Boolean r3 = r2.isLocked();
        if (r3 == null) goto L11;
        boolean r4 = r3.booleanValue();
    L12:
        r2.setLocked(Boolean.valueOf(!r4));
        r1.setOptions(r2);
        return;
    L11:
        r4 = false;
        goto L12
    }

    public final void F(float r25, float r26) {
        C0142d r1 = this.g.b().e(this.h + ".main");
        if (r1 == null) goto L157;
        DrawingItem r2 = this.t;
        if (r2 == null) goto L158;
        DrawingItem.Options r4 = r2.getOptions();
        if (r4 == null) goto L13;
        Boolean r5 = r4.isLocked();
        if (r5 == null) goto L13;
        boolean r6 = r5.booleanValue();
    L14:
        if (r6 == true) goto L159;
        String r7 = r2.getName();
        PointF r8 = new PointF(r25, r26);
        int r9 = 40;
        if (this.j == false) goto L20;
        float r10 = Math.max(Math.min(r8.x, r1.y()), r1.u());
        float r3 = Math.max(Math.min(r8.y, r1.p() - Xj.a.d(8)), r1.z() + Xj.a.d(40));
        float r16 = 0.0f;
    L37:
        PointF r11 = new PointF(r10, r3);
    L38:
        float r12 = r11.x;
        float r13 = r11.y;
        boolean r14 = true;
        if (this.j == false) goto L128;
        long r15 = h(r12);
        AbstractC0199w0 r17 = this.g.b().l(this.h + ".main");
        if (r17 != null) goto L43;
        double r18 = 0.0d;
    L73:
        this.n = true;
        y1 r19 = this.g.b().m(this.h);
        if (r19 == null) goto L77;
        this.p = H(r15);
        this.f13q = I(r18);
        float r20 = r19.w();
        this.o = (int) ((r20 + this.p) / r19.u());
    L77:
        int r21 = r7.hashCode();
        if (r21 != (-1407425220)) goto L80;
        double r22 = r18;
        if (r7.equals("CHoriRayLineObject") == true) goto L123;
    L121:
        r2.getPoints()[this.l] = new DrawingPoint(r15, r22, 0);
        return;
    L123:
        long r110 = r2.getPoints()[1 - this.l].getX();
        if (r15 == r110) goto L154;
        r2.getPoints()[this.l] = new DrawingPoint(r15, r22, 0);
        r2.getPoints()[1 - this.l] = new DrawingPoint(r110, r22, 0);
        return;
    L154:
        return;
    L80:
        if (r21 == (-283576629)) goto L88;
        if (r21 == 1095856039) goto L85;
    L83:
        r22 = r18;
        goto L121
    L85:
        if (r7.equals("CHoriSegLineObject") == false) goto L83;
        r22 = r18;
        goto L123
    L88:
        if (r7.equals("CRectangleObject") == false) goto L83;
        double r23 = r18;
        r2.getPoints()[this.l] = new DrawingPoint(r15, r18, 0);
        int r24 = this.l - 1;
        Integer r27 = Integer.valueOf(r24);
        if (r24 < 0) goto L93;
        boolean r28 = true;
    L94:
        if (r28 == true) goto L97;
        r27 = null;
    L97:
        if (r27 == null) goto L99;
        int r29 = r27.intValue();
    L100:
        int r30 = this.l + 1;
        Integer r31 = Integer.valueOf(r30);
        if (r30 < r2.getPoints().length) goto L104;
        r14 = false;
    L104:
        if (r14 == false) goto L106;
        Integer r32 = r31;
    L107:
        if (r32 == null) goto L109;
        int r33 = r32.intValue();
    L110:
        int r34 = this.l;
        if (r34 != 0) goto L113;
    L117:
        r2.getPoints()[r29] = new DrawingPoint(r15, r2.getPoints()[r29].getY(), 0);
        r2.getPoints()[r33] = new DrawingPoint(r2.getPoints()[r33].getX(), r23, 0);
        return;
    L113:
        if (r34 == 2) goto L117;
        r2.getPoints()[r29] = new DrawingPoint(r2.getPoints()[r29].getX(), r23, 0);
        r2.getPoints()[r33] = new DrawingPoint(r15, r2.getPoints()[r33].getY(), 0);
        return;
    L109:
        r33 = 0;
        goto L110
    L106:
        r32 = null;
        goto L107
    L99:
        r29 = r2.getPoints().length - 1;
        goto L100
    L93:
        r28 = false;
        goto L94
    L43:
        y1 r35 = this.g.b().m(this.h);
        if (r35 != null) goto L46;
        r18 = r17.R(r13);
        goto L73
    L46:
        int r36 = (int) ((r35.w() + r12) / r35.u());
        C0205z r37 = this.g.d();
        if (r37 == null) goto L72;
        Sj.a r38 = r37.C();
        if (r38 == null) goto L72;
        Sj.b r39 = (Sj.b) Sf.z.r0(r38, r36);
        if (r39 == null) goto L72;
        float r40 = I(r39.d());
        float r111 = I(r39.b());
        float r112 = I(r39.c());
        float r41 = I(r39.a());
        float r113 = Math.abs(r13 - r40);
        float r114 = Math.abs(r13 - r111);
        float r115 = Math.abs(r13 - r112);
        float r116 = Math.abs(r13 - r41);
        int r42 = Xj.a.b(6);
        Iterator r43 = Sf.N.l(new Qf.p[]{Qf.w.a(Float.valueOf(r113), Float.valueOf(r40)), Qf.w.a(Float.valueOf(r114), Float.valueOf(r111)), Qf.w.a(Float.valueOf(r115), Float.valueOf(r112)), Qf.w.a(Float.valueOf(r116), Float.valueOf(r41))}).entrySet().iterator();
        if (r43.hasNext() == true) goto L56;
        Object r44 = null;
    L65:
        Map.Entry r45 = (Map.Entry) r44;
        if (r45 != null) goto L69;
        r18 = r17.R(r13);
        goto L73
    L69:
        if (((Number) r45.getKey()).floatValue() >= r42) goto L71;
        r18 = r17.R(((Number) r45.getValue()).floatValue());
        goto L73
    L71:
        r18 = r17.R(r13);
        goto L73
    L56:
        r44 = r43.next();
        if (r43.hasNext() == false) goto L65;
        float r117 = ((Number) ((Map.Entry) r44).getKey()).floatValue();
    L60:
        Object r118 = r43.next();
        float r119 = ((Number) ((Map.Entry) r118).getKey()).floatValue();
        if (Float.compare(r117, r119) <= 0) goto L64;
        r44 = r118;
        r117 = r119;
    L64:
        if (r43.hasNext() == true) goto L60;
    L72:
        r18 = r17.R(r13);
        goto L73
    L128:
        if (this.k == false) goto L155;
        this.n = false;
        if (r12 < r16) goto L156;
        ArrayList r46 = new ArrayList();
        DrawingPoint[] r47 = r2.getPoints();
        int r48 = r47.length;
        int r49 = 0;
        int r50 = 0;
    L132:
        if (r49 >= r48) goto L146;
        DrawingPoint r120 = r47[r49];
        int r121 = r50 + 1;
        float[] r122 = (float[]) this.m.get(Integer.valueOf(r50));
        if (r122 == null) goto L138;
        Float r123 = Sf.o.o0(r122, 0);
        if (r123 == null) goto L138;
        float r124 = r123.floatValue();
    L139:
        float r125 = r12 - r124;
        float[] r51 = (float[]) this.m.get(Integer.valueOf(r50));
        if (r51 == null) goto L144;
        Float r52 = Sf.o.o0(r51, 1);
        if (r52 == null) goto L144;
        float r53 = r52.floatValue();
    L145:
        r46.add(new DrawingPoint(h(r125), l(r13 - r53), 0));
        r49 = r49 + 1;
        r50 = r121;
    L144:
        r53 = r16;
    L138:
        r124 = r16;
        goto L139
    L146:
        r2.setPoints((DrawingPoint[]) r46.toArray(new DrawingPoint[0]));
        return;
    L156:
        return;
    L155:
        return;
    L20:
        if (this.k == false) goto L36;
        y1 r54 = this.g.b().m(this.h);
        if (r54 != null) goto L24;
        r11 = new PointF(0.0f, 0.0f);
        r16 = 0.0f;
        goto L38
    L24:
        float r126 = r54.w();
        float r127 = r54.u();
        Iterator r128 = this.m.entrySet().iterator();
        float r129 = -3.4028235E38f;
        float r130 = Float.MAX_VALUE;
    L26:
        if (r128.hasNext() == false) goto L28;
        Map.Entry r131 = (Map.Entry) r128.next();
        r129 = Math.max(((float[]) r131.getValue())[0], r129);
        r130 = Math.min(((float[]) r131.getValue())[0], r130);
        r9 = r9;
        goto L26
    L28:
        int r210 = r9;
        float r55 = r54.x();
        float r132 = r8.x;
        int r56 = (int) (((r132 - r129) + r126) / r127);
        int r133 = (int) (((r132 - r130) + r126) / r127);
        r16 = 0.0f;
        float r134 = Math.max(Math.min(r132, r1.y()), r1.u());
        r3 = Math.max(Math.min(r8.y, r1.p() - Xj.a.d(8)), r1.z() + Xj.a.d(r210));
        if (r56 >= 0) goto L31;
        float r57 = Math.max(r134, r129 - r126);
    L33:
        if (r133 < r54.t()) goto L35;
        r10 = Math.min(r57, ((r55 + r130) - r126) - 100);
        goto L37
    L35:
        r10 = r57;
        goto L37
    L31:
        r57 = r134;
        goto L33
    L36:
        r16 = 0.0f;
        r3 = 0.0f;
        r10 = 0.0f;
        goto L37
    L159:
        return;
    L13:
        r6 = false;
        goto L14
    L158:
        return;
    }

    public final void G() {
        DrawingItem r0 = this.t;
        if (r0 == null) goto L5;
        r0.setSelected(false);
    L5:
        this.t = null;
        this.i.N().setValue(Boolean.FALSE);
        G r1 = this.g.b().i(this.h);
        if (r1 == null) goto L14;
        ArrayList r2 = r1.r;
        if (r2 == null) goto L16;
        Iterator r3 = r2.iterator();
    L12:
        if (r3.hasNext() == false) goto L17;
        ((DrawingItem) r3.next()).setSelected(false);
        goto L12
    L17:
        return;
    L16:
        return;
    }

    public final float H(long r7) {
        C0142d r0 = this.g.b().e(this.h + ".main");
        if (r0 != null) goto L5;
        return 0.0f;
    L5:
        C0205z r2 = this.g.d();
        if (r2 != null) goto L8;
        return 0.0f;
    L8:
        y1 r3 = this.g.b().m(this.h);
        if (r3 != null) goto L11;
        return 0.0f;
    L11:
        float r8 = H.a.c(r2.C(), r7, r3.u());
        if (r8 >= 0.0f) goto L16;
        return -1.0f;
    L16:
        return r8 - (r3.w() + r0.u());
    }

    public final float I(double r4) {
        AbstractC0199w0 r0 = this.g.b().l(this.h + ".main");
        if (r0 != null) goto L7;
        return 0.0f;
    L7:
        return r0.S(r4);
    }

    public final void J(boolean r2, int r3) {
        DrawingItem r0 = this.t;
        if (r0 == null) goto L10;
        DrawingItem.Options r1 = r0.getOptions();
        if (r1 == null) goto L9;
        r1.setShowBackground(Boolean.valueOf(r2));
        r1.setBackground(Integer.valueOf(r3));
        return;
    L9:
        return;
    }

    public final void K(int r19) {
        DrawingItem r1 = this.t;
        if (r1 != null) goto L5;
        return;
    L5:
        DrawingItem.Options r2 = r1.getOptions();
        if (r2 != null) goto L8;
        Boolean r4 = null;
        Float r5 = null;
        Integer r6 = null;
        Integer r7 = null;
        Boolean r8 = null;
        List r9 = null;
        String r10 = null;
        Float r11 = null;
        Integer r12 = null;
        Integer r13 = null;
        Float r14 = null;
        List r15 = null;
        r2 = new DrawingItem.Options(r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15, 4095, null);
    L8:
        r2.setLineColor(Integer.valueOf(r19));
        r1.setOptions(r2);
    }

    public final void L(List r19) {
        DrawingItem r1 = this.t;
        if (r1 != null) goto L5;
        return;
    L5:
        DrawingItem.Options r2 = r1.getOptions();
        if (r2 != null) goto L8;
        Boolean r4 = null;
        Float r5 = null;
        Integer r6 = null;
        Integer r7 = null;
        Boolean r8 = null;
        List r9 = null;
        String r10 = null;
        Float r11 = null;
        Integer r12 = null;
        Integer r13 = null;
        Float r14 = null;
        List r15 = null;
        r2 = new DrawingItem.Options(r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15, 4095, null);
    L8:
        r2.setLineDash(r19);
        r1.setOptions(r2);
    }

    public final void M(float r19) {
        DrawingItem r1 = this.t;
        if (r1 != null) goto L5;
        return;
    L5:
        DrawingItem.Options r2 = r1.getOptions();
        if (r2 != null) goto L8;
        Boolean r4 = null;
        Float r5 = null;
        Integer r6 = null;
        Integer r7 = null;
        Boolean r8 = null;
        List r9 = null;
        String r10 = null;
        Float r11 = null;
        Integer r12 = null;
        Integer r13 = null;
        Float r14 = null;
        List r15 = null;
        r2 = new DrawingItem.Options(r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15, 4095, null);
    L8:
        r2.setLineWidth(Float.valueOf(r19));
        r1.setOptions(r2);
    }

    public final long h(float r6) {
        C0205z r0 = this.g.d();
        if (r0 == null) goto L12;
        Sj.a r1 = r0.C();
        if (r1 == null) goto L12;
        y1 r3 = this.g.b().m(this.h);
        if (r3 != null) goto L11;
        return 0;
    L11:
        return H.a.b(r1, r6, r3.u(), r3.w());
    L12:
        return 0;
    }

    public final double l(float r4) {
        AbstractC0199w0 r0 = this.g.b().l(this.h + ".main");
        if (r0 != null) goto L7;
        return 0.0d;
    L7:
        return r0.R(r4);
    }

    public final void m(float r11, float r12) {
        if (this.i.q(16) != 0) goto L75;
        LinkedHashMap r0 = new LinkedHashMap();
        Iterator r1 = this.r.iterator();
        int r3 = 0;
    L6:
        if (r1.hasNext() == false) goto L22;
        Object r4 = r1.next();
        int r5 = r3 + 1;
        if (r3 >= 0) goto L10;
        Sf.r.x();
    L10:
        DrawingItem r6 = (DrawingItem) r4;
        if (i(r6) == false) goto L20;
        if (nk.d.a.e(r6.getName()) == true) goto L15;
        double r7 = r(r6, r11, r12);
        if (r7 >= w) goto L20;
        this.s.put(Double.valueOf(r7), r6);
        goto L20
    L15:
        if (j(r6, r11, r12) == false) goto L20;
        r0.put(Integer.valueOf(r3), r6);
    L20:
        r3 = r5;
        goto L6
    L22:
        if (r0.isEmpty() == false) goto L38;
        Iterator r13 = this.s.entrySet().iterator();
        if (r13.hasNext() == true) goto L26;
        Object r14 = null;
    L35:
        Map.Entry r15 = (Map.Entry) r14;
        if (r15 == null) goto L53;
        DrawingItem r16 = (DrawingItem) r15.getValue();
    L55:
        if (i(r16) == false) goto L59;
        if (r16 == null) goto L58;
        r16.setSelected(true);
    L58:
        this.t = r16;
        this.i.N().setValue(Boolean.TRUE);
    L60:
        DrawingItem r17 = this.t;
        if (r17 != null) goto L68;
        Iterator r18 = this.r.iterator();
    L64:
        if (r18.hasNext() == false) goto L66;
        ((DrawingItem) r18.next()).setSelected(false);
        goto L64
    L66:
        this.i.N().setValue(Boolean.FALSE);
    L73:
        this.s.clear();
        return;
    L68:
        if (hg.s.f(this.u, r17) == true) goto L72;
        DrawingItem r19 = this.u;
        if (r19 == null) goto L72;
        r19.setSelected(false);
    L72:
        this.u = this.t;
        goto L73
    L59:
        this.t = null;
    L53:
        r16 = null;
        goto L55
    L26:
        r14 = r13.next();
        if (r13.hasNext() == false) goto L35;
        double r8 = ((Number) ((Map.Entry) r14).getKey()).doubleValue();
    L30:
        Object r2 = r13.next();
        double r9 = ((Number) ((Map.Entry) r2).getKey()).doubleValue();
        if (Double.compare(r8, r9) <= 0) goto L34;
        r14 = r2;
        r8 = r9;
    L34:
        if (r13.hasNext() == true) goto L30;
    L38:
        Iterator r10 = r0.entrySet().iterator();
        if (r10.hasNext() == true) goto L41;
        Object r110 = null;
    L50:
        Map.Entry r111 = (Map.Entry) r110;
        if (r111 == null) goto L53;
        r16 = (DrawingItem) r111.getValue();
        goto L55
    L41:
        r110 = r10.next();
        if (r10.hasNext() == false) goto L50;
        int r112 = ((Number) ((Map.Entry) r110).getKey()).intValue();
    L45:
        Object r20 = r10.next();
        int r21 = ((Number) ((Map.Entry) r20).getKey()).intValue();
        if (r112 <= r21) goto L49;
        r110 = r20;
        r112 = r21;
    L49:
        if (r10.hasNext() == true) goto L45;
    L75:
        p(r11, r12);
    }

    public final void n() {
        this.r.clear();
        C0205z r0 = this.g.d();
        if (r0 == null) goto L5;
        r0.b0((DrawingItem[]) this.r.toArray(new DrawingItem[0]));
    L5:
        this.t = null;
        this.i.N().setValue(Boolean.FALSE);
    }

    public final void o() {
        DrawingItem r0 = this.t;
        if (r0 != null) goto L5;
        return;
    L5:
        this.r.remove(r0);
        C0205z r1 = this.g.d();
        if (r1 == null) goto L8;
        r1.b0((DrawingItem[]) this.r.toArray(new DrawingItem[0]));
    L8:
        this.t = null;
        this.i.N().setValue(Boolean.FALSE);
    }

    /* JADX WARN: Multi-variable type inference failed */
    public void p(float r35, float r36) {
        C0142d r3 = this.g.b().e(this.h + ".main");
        if (r3 == null) goto L45;
        int r4 = this.i.q(16);
        nk.d r5 = nk.d.a;
        String r8 = r5.a(r4);
        int r6 = r5.d(r8);
        if (hg.s.f(r8, "CEmptyObject") == true) goto L44;
        if (r6 == 0) goto L46;
        ng.g r7 = new ng.g(r3.u(), r3.y());
        ng.g r9 = new ng.g(Xj.a.d(40) + r3.z(), r3.p() - Xj.a.d(8));
        if (r6 == 0) goto L24;
        if (r6 != 1) goto L13;
        DrawingPoint[] r10 = {new DrawingPoint(h(nk.A.a(r35, r7)), l(nk.A.a(r36, r9)), 0)};
    L23:
        int r11 = 1;
    L25:
        if (r4 == r11) goto L35;
        if (r4 == 3) goto L35;
        if (r4 != 6) goto L30;
        float r1 = nk.A.a(r35, r7);
        r10 = new DrawingPoint[]{new DrawingPoint(h(r1), l(nk.A.a(r36, r9)), 0), new DrawingPoint(h(r1), l(nk.A.a(r36 - 160, r9)), 0)};
    L31:
        DrawingPoint[] r12 = r10;
    L32:
        boolean r16 = false;
    L36:
        Color.parseColor("#B3EEEEEE");
        int r2 = Color.parseColor("#1990FF");
        Color.parseColor("#00000000");
        Boolean r22 = Boolean.FALSE;
        int r13 = r16;
        DrawingItem r14 = new DrawingItem(r12, r8, StringUtils.EMPTY, new DrawingItem.Options(r22, Float.valueOf(1.0f), Integer.valueOf(r2), null, r22, Sf.r.t(new Float[]{Float.valueOf(0.0f), Float.valueOf(0.0f)}), null, null, null, null, null, null), true, null, 32, null);
        this.i.N().setValue(Boolean.TRUE);
        DrawingItem r15 = this.u;
        if (r15 == null) goto L39;
        r15.setSelected(r13);
    L39:
        this.t = r14;
        this.u = r14;
        this.r.add(r14);
        C0205z r17 = this.g.d();
        if (r17 == null) goto L42;
        r17.b0((DrawingItem[]) this.r.toArray(new DrawingItem[r13]));
    L42:
        r5.f("CEmptyObject");
        this.i.U().setValue(r22);
        return;
    L30:
        if (r4 != 13) goto L31;
        float r18 = 150;
        r12 = new DrawingPoint[]{new DrawingPoint(h(nk.A.a(r35 - r18, r7)), l(nk.A.a(r36 + r18, r9)), 0), new DrawingPoint(h(nk.A.a(r35 + r18, r7)), l(nk.A.a(r36 - r18, r9)), 0)};
    L35:
        float r19 = nk.A.a(r35, r7);
        float r20 = nk.A.a(r36, r9);
        r16 = false;
        r12 = new DrawingPoint[]{new DrawingPoint(h(r19), l(r20), 0), new DrawingPoint(h(nk.A.a(r35 + 100, r7)), l(r20), 0)};
        goto L36
    L13:
        if (r6 == 2) goto L21;
        if (r6 != 3) goto L16;
        int r110 = 1;
        float r21 = 150;
        float r111 = 50;
        float r112 = r36 + r111;
        float r23 = r21 + r35;
        r10 = new DrawingPoint[]{new DrawingPoint(h(nk.A.a(r35 - r21, r7)), l(nk.A.a(r112, r9)), 0), new DrawingPoint(h(nk.A.a(r23, r7)), l(nk.A.a(r112, r9)), 0), new DrawingPoint(h(nk.A.a(r23, r7)), l(nk.A.a(r36 - r111, r9)), 0)};
    L19:
        r11 = r110;
        goto L25
    L16:
        if (r6 == 4) goto L18;
        r10 = new DrawingPoint[0];
        r8 = r8;
        r11 = 1;
        goto L25
    L18:
        float r24 = nk.A.a(r35, r7);
        float r113 = nk.A.a(r36, r9);
        r110 = 1;
        float r114 = DisplayText.DISPLAY_TEXT_MAXIMUM_SIZE;
        float r115 = nk.A.a(r35 + r114, r7);
        float r116 = nk.A.a(r36 - r114, r9);
        r10 = new DrawingPoint[]{new DrawingPoint(h(r24), l(r113), 0), new DrawingPoint(h(r115), l(r113), 0), new DrawingPoint(h(r115), l(r116), 0), new DrawingPoint(h(r24), l(r116), 0)};
        goto L19
    L21:
        r110 = 1;
        float r25 = 150;
        float r26 = 50;
        r10 = new DrawingPoint[]{new DrawingPoint(h(nk.A.a(r35 - r25, r7)), l(nk.A.a(r36 + r26, r9)), 0), new DrawingPoint(h(nk.A.a(r25 + r35, r7)), l(nk.A.a(r36 - r26, r9)), 0)};
        goto L19
    L24:
        r10 = new DrawingPoint[0];
        goto L23
    L46:
        return;
    L44:
        return;
    }

    public final void q() {
        this.j = false;
        this.k = false;
        this.l = 0;
        this.m.clear();
        this.n = false;
    }

    public final double r(DrawingItem r25, float r26, float r27) {
        List<PointF> r2 = r25.getDecisionPoints();
        double r4 = Double.MAX_VALUE;
        if (r2.size() >= 2) goto L5;
        return Double.MAX_VALUE;
    L5:
        ArrayList r3 = new ArrayList();
        String r7 = r25.getName();
        int r9 = 0;
        if (hg.s.f(r7, "CFibRetraceObject") == false) goto L8;
    L9:
        double r22 = Double.MAX_VALUE;
        if ((r2.size() % 2) == 0) goto L25;
        return Double.MAX_VALUE;
    L25:
        ng.e r5 = ng.i.x(ng.i.y(0, r2.size()), 2);
        int r6 = r5.k();
        int r8 = r5.o();
        int r10 = r5.q();
        if (r10 <= 0) goto L28;
        if (r6 > r8) goto L28;
    L30:
        PointF r11 = r2.get(r6);
        int r12 = r6 + 1;
        r3.add(Double.valueOf(g(r26, r27, r11.x, r11.y, r2.get(r12).x, r2.get(r12).y)));
        if (r6 == r8) goto L33;
        r6 = r6 + r10;
    L33:
        Double r0 = Sf.z.M0(r3);
        if (r0 != null) goto L36;
        return r22;
    L36:
        return r0.doubleValue();
    L28:
        if (r10 >= 0) goto L33;
        if (r8 > r6) goto L33;
    L8:
        if (hg.s.f(r7, "CTriParallelLineObject") == true) goto L9;
        Iterator<T> r13 = r2.iterator();
    L12:
        if (r13.hasNext() == false) goto L21;
        Object r14 = r13.next();
        int r15 = r9 + 1;
        if (r9 >= 0) goto L16;
        Sf.r.x();
    L16:
        PointF r16 = (PointF) r14;
        if (r9 >= (r2.size() - 1)) goto L20;
        r3.add(Double.valueOf(g(r26, r27, r16.x, r16.y, r2.get(r15).x, r2.get(r15).y)));
    L20:
        r9 = r15;
        r4 = r4;
        goto L12
    L21:
        r22 = r4;
        goto L33
    }

    public final DrawingPoint s() {
        if (this.j == true) goto L5;
        return null;
    L5:
        DrawingItem r0 = this.t;
        if (r0 == null) goto L11;
        DrawingPoint[] r1 = r0.getPoints();
        if (r1 == null) goto L11;
        return (DrawingPoint) Sf.o.r0(r1, this.l);
    L11:
        return null;
    }

    public final int t() {
        return this.o;
    }

    public final float u() {
        return this.p;
    }

    public final float v() {
        return this.f13q;
    }

    public final DrawingItem w() {
        return this.t;
    }

    public final DrawingItem.Options x() {
        DrawingItem r0 = this.t;
        if (r0 != null) goto L7;
        return null;
    L7:
        return r0.getOptions();
    }

    public final boolean y(float r22, float r23) {
        this.m.clear();
        boolean r12 = false;
        this.j = false;
        this.k = false;
        this.l = 0;
        DrawingItem r13 = this.t;
        if (r13 != null) goto L5;
        return false;
    L5:
        DrawingPoint[] r14 = r13.getPoints();
        int r15 = r14.length;
        int r1 = 0;
        int r2 = 0;
    L6:
        if (r1 >= r15) goto L11;
        DrawingPoint r3 = r14[r1];
        int r16 = r2 + 1;
        double r4 = H(r3.getX());
        double r6 = I(r3.getY());
        int r5 = r1;
        int r7 = r2;
        boolean r18 = r12;
        if (D(r4, r6, r22, r23) == false) goto L10;
        this.l = r7;
        this.j = true;
    L10:
        r1 = r5 + 1;
        r2 = r16;
        r12 = r18;
        goto L6
    L11:
        boolean r19 = r12;
        if (this.j == true) goto L17;
        if (C(r13, r22, r23) == false) goto L17;
        this.k = true;
    L17:
        if (this.k == false) goto L22;
        DrawingPoint[] r8 = r13.getPoints();
        int r9 = r8.length;
        int r10 = r19 ? 1 : 0;
        int r11 = r10;
    L19:
        if (r10 >= r9) goto L22;
        DrawingPoint r17 = r8[r10];
        int r20 = r11 + 1;
        float r21 = r22 - H(r17.getX());
        float r24 = r23 - I(r17.getY());
        HashMap r25 = this.m;
        Integer r26 = Integer.valueOf(r11);
        float[] r110 = new float[2];
        r110[r19 ? 1 : 0] = r21;
        r110[1] = r24;
        r25.put(r26, r110);
        r10 = r10 + 1;
        r11 = r20;
    L22:
        if (this.j == false) goto L24;
    L27:
        return true;
    L24:
        if (this.k == true) goto L27;
        return r19;
    }

    public final void z() {
        C0205z r0 = this.g.d();
        if (r0 == null) goto L8;
        DrawingItem[] r1 = r0.E();
        if (r1 == null) goto L8;
        Collection r2 = Sf.o.r1(r1);
        if (r2 == null) goto L8;
    L9:
        DrawingItem r3 = this.t;
        if (r3 != null) goto L22;
        Iterator r4 = this.r.iterator();
    L13:
        if (r4.hasNext() == false) goto L17;
        Object r5 = r4.next();
        if (((DrawingItem) r5).isSelected() == false) goto L13;
    L18:
        r3 = (DrawingItem) r5;
        if (r3 != null) goto L22;
    L29:
        boolean r6 = false;
    L31:
        Iterator r7 = r2.iterator();
    L33:
        if (r7.hasNext() == false) goto L59;
        DrawingItem r8 = (DrawingItem) r7.next();
        Iterator r9 = this.r.iterator();
    L36:
        if (r9.hasNext() == false) goto L42;
        Object r10 = r9.next();
        String r11 = ((DrawingItem) r10).getId();
        if (r11.length() <= 0) goto L36;
        if (hg.s.f(r11, r8.getId()) == false) goto L36;
    L43:
        DrawingItem r12 = (DrawingItem) r10;
        if (r12 != null) goto L45;
        this.r.add(r8);
        goto L33
    L45:
        if (r12 == r8) goto L33;
        if (r12.isSelected() == true) goto L53;
        if (r12 == this.t) goto L53;
        r12.copyWith(r8);
    L53:
        if (r6 == true) goto L57;
        if (r12 != r8) goto L57;
        r6 = false;
    L57:
        r6 = true;
        goto L33
    L42:
        r10 = null;
        goto L43
    L59:
        if (r6 == false) goto L92;
        C0205z r13 = this.g.d();
        if (r13 == null) goto L93;
        r13.b0((DrawingItem[]) this.r.toArray(new DrawingItem[0]));
        return;
    L93:
        return;
    L92:
        return;
    L17:
        r5 = null;
    L22:
        if (r2.isEmpty() == true) goto L30;
        Iterator r14 = r2.iterator();
    L26:
        if (r14.hasNext() == false) goto L30;
        if (((DrawingItem) r14.next()) != r3) goto L26;
    L30:
        r6 = true;
    L8:
        r2 = new ArrayList();
        goto L9
    }
}
