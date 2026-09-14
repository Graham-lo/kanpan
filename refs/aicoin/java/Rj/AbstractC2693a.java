package Rj;

import Sf.AbstractC2803q;
import android.content.Context;
import android.content.res.Resources;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Rect;
import gk.AbstractC7467h0;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import kotlin.jvm.functions.Function1;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.R;
import sp.aicoin_kline.chart.Chart;
import sp.aicoin_kline.chart.data.SubIndicNamePosition;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: Rj.a, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public abstract class AbstractC2693a extends AbstractC2744r0 {

    /* JADX INFO: renamed from: z, reason: collision with root package name */
    public static final C0275a f19302z = new C0275a(null);

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final int f19303l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Paint f19304m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final float f19305n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final int f19306o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public List f19307p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public int f19308q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final nk.r f19309r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public final Rect f19310s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public sp.aicoin_kline.core.indicator.config.F f19311t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public y1 f19312u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public Bitmap f19313v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public boolean f19314w;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public boolean f19315x;

    /* JADX INFO: renamed from: y, reason: collision with root package name */
    public String f19316y;

    /* JADX INFO: renamed from: Rj.a$a, reason: collision with other inner class name */
    public static final class C0275a {
        public C0275a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    /* JADX INFO: renamed from: Rj.a$b */
    public static final class b {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public String f19317a;

        /* JADX INFO: renamed from: b, reason: collision with root package name */
        public final Paint f19318b;

        /* JADX INFO: renamed from: c, reason: collision with root package name */
        public boolean f19319c;

        /* JADX INFO: renamed from: d, reason: collision with root package name */
        public boolean f19320d;

        /* JADX INFO: renamed from: e, reason: collision with root package name */
        public String f19321e;

        /* JADX INFO: renamed from: f, reason: collision with root package name */
        public boolean f19322f;

        public b(String str, Paint paint, boolean z10, boolean z11, String str2, boolean z12) {
            this.f19317a = str;
            this.f19318b = paint;
            this.f19319c = z10;
            this.f19320d = z11;
            this.f19321e = str2;
            this.f19322f = z12;
        }

        public /* synthetic */ b(String str, Paint paint, boolean z10, boolean z11, String str2, boolean z12, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this(str, paint, (i10 & 4) != 0 ? true : z10, (i10 & 8) != 0 ? false : z11, (i10 & 16) != 0 ? "" : str2, (i10 & 32) != 0 ? false : z12);
        }

        public final String a() {
            return this.f19317a;
        }

        public final String b() {
            return this.f19321e;
        }

        public final Paint c() {
            return this.f19318b;
        }

        public final boolean d() {
            return this.f19319c;
        }

        public final boolean e() {
            return this.f19320d;
        }

        public boolean equals(Object obj) {
            if (this == obj) {
                return true;
            }
            if (!(obj instanceof b)) {
                return false;
            }
            b bVar = (b) obj;
            return AbstractC7609s.f(this.f19317a, bVar.f19317a) && AbstractC7609s.f(this.f19318b, bVar.f19318b) && this.f19319c == bVar.f19319c && this.f19320d == bVar.f19320d && AbstractC7609s.f(this.f19321e, bVar.f19321e) && this.f19322f == bVar.f19322f;
        }

        public final boolean f() {
            return this.f19322f;
        }

        public final void g(String str) {
            this.f19317a = str;
        }

        public final void h(boolean z10) {
            this.f19319c = z10;
        }

        public int hashCode() {
            return Boolean.hashCode(this.f19322f) + kk.d.a(this.f19321e, (Boolean.hashCode(this.f19320d) + ((Boolean.hashCode(this.f19319c) + ((this.f19318b.hashCode() + (this.f19317a.hashCode() * 31)) * 31)) * 31)) * 31, 31);
        }

        public String toString() {
            return "InfoComponent(content=" + this.f19317a + ", paint=" + this.f19318b + ", visible=" + this.f19319c + ", isIndicName=" + this.f19320d + ", indicKey=" + this.f19321e + ", isScript=" + this.f19322f + ')';
        }
    }

    /* JADX INFO: renamed from: Rj.a$c */
    public static final class c {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public final boolean f19323a;

        /* JADX INFO: renamed from: b, reason: collision with root package name */
        public final List f19324b;

        public c(boolean z10, List list) {
            this.f19323a = z10;
            this.f19324b = list;
        }

        public final boolean a() {
            return this.f19323a;
        }

        public final List b() {
            return this.f19324b;
        }

        public boolean equals(Object obj) {
            if (this == obj) {
                return true;
            }
            if (!(obj instanceof c)) {
                return false;
            }
            c cVar = (c) obj;
            return this.f19323a == cVar.f19323a && AbstractC7609s.f(this.f19324b, cVar.f19324b);
        }

        public int hashCode() {
            return this.f19324b.hashCode() + (Boolean.hashCode(this.f19323a) * 31);
        }

        public String toString() {
            return "PreparedTextSegments(moveToNewLineFirst=" + this.f19323a + ", segments=" + this.f19324b + ')';
        }
    }

    public AbstractC2693a(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f19303l = Xj.a.d(8);
        Paint paintA = kk.c.a(true);
        paintA.setTextAlign(Paint.Align.LEFT);
        paintA.setTextSize(Xj.a.d(9));
        this.f19304m = paintA;
        Xj.a.d(2);
        this.f19305n = -paintA.getFontMetrics().top;
        int iD = Xj.a.d(11);
        this.f19306o = iD;
        this.f19307p = new ArrayList();
        this.f19309r = new nk.r();
        this.f19310s = new Rect();
        this.f19316y = "";
        this.f19308q = iD;
    }

    public static c v(String str, Paint paint, int i10, int i11, int i12) {
        List listE;
        if (str.length() == 0) {
            return new c(false, AbstractC2803q.e(""));
        }
        float fE = p292ng.i.e(i12 - i11, 1.0f);
        float fE2 = p292ng.i.e(i12 - i10, 1.0f);
        float fMeasureText = paint.measureText(str);
        if (fMeasureText <= fE2) {
            return new c(false, AbstractC2803q.e(str));
        }
        if (i10 > i11 && fMeasureText <= fE) {
            return new c(true, AbstractC2803q.e(str));
        }
        if (i10 <= i11) {
            fE = fE2;
        }
        boolean z10 = i10 > i11;
        if (str.length() == 0) {
            listE = Sf.r.n();
        } else {
            float fE3 = p292ng.i.e(fE, 1.0f);
            ArrayList arrayList = new ArrayList();
            while (str.length() > 0) {
                int iBreakText = paint.breakText(str, true, fE3, null);
                if (iBreakText <= 0) {
                    arrayList.add(Ah.A.q1(str, 1));
                    str = Ah.A.l1(str, 1);
                } else {
                    arrayList.add(str.substring(0, iBreakText));
                    str = str.substring(iBreakText);
                }
            }
            listE = arrayList;
        }
        if (listE.isEmpty()) {
            listE = AbstractC2803q.e("");
        }
        return new c(z10, listE);
    }

    public final Paint A() {
        return this.f19304m;
    }

    public int B() {
        return this.f19303l;
    }

    public int C() {
        return 0;
    }

    public final boolean D() {
        return this.f19314w;
    }

    /* JADX WARN: Multi-variable type inference failed */
    /* JADX WARN: Type inference failed for: r0v0 */
    /* JADX WARN: Type inference failed for: r0v4, types: [Qf.H] */
    /* JADX WARN: Type inference failed for: r0v5 */
    public final void E() {
        Resources resources;
        Bitmap bitmap = 0;
        bitmap = 0;
        try {
            KLineManager.a aVar = KLineManager.f142490O;
            Context contextW = aVar.a().w();
            if (contextW == null || (resources = contextW.getResources()) == null) {
                resources = aVar.a().i().getResources();
            }
            try {
                Bitmap bitmapDecodeResource = BitmapFactory.decodeResource(resources, R.mipmap.kline_hide_indic_info_icon);
                if (bitmapDecodeResource != null) {
                    if (bitmapDecodeResource.getWidth() > 0 && bitmapDecodeResource.getHeight() > 0) {
                        int iK = p292ng.i.k((int) (Math.abs(this.f19304m.getFontMetrics().ascent) + this.f19304m.getFontMetrics().descent), Xj.a.d(12));
                        this.f19313v = Bitmap.createScaledBitmap(bitmapDecodeResource, iK, iK, true);
                    }
                    bitmap = Qf.H.f17640a;
                    return;
                }
                return;
            } catch (Exception unused) {
                this.f19313v = null;
                Qf.H h10 = Qf.H.f17640a;
                return;
            }
        } catch (Exception unused2) {
            this.f19313v = bitmap;
        }
        this.f19313v = bitmap;
    }

    public final float F() {
        return this.f19305n;
    }

    public final void G(boolean z10) {
        this.f19314w = z10;
    }

    @Override // Rj.AbstractC2744r0
    public boolean n(String str, int i10, int i11) {
        Object objD = this.f19309r.d(i10, i11);
        if (objD != null) {
            KLineManager.a aVar = KLineManager.f142490O;
            if (!aVar.a().Z()) {
                return false;
            }
            y1 y1VarM = this.f19312u;
            if (y1VarM != null || (y1VarM = i().b().m(c())) != null) {
                if (y1VarM.E()) {
                    y1VarM.Y(false);
                }
                y1VarM.W(-1.0f);
                y1VarM.X(-1.0f);
            }
            if ((objD instanceof SubIndicNamePosition) && !Ah.x.y(b(), ".main", false, 2, null)) {
                SubIndicNamePosition subIndicNamePosition = (SubIndicNamePosition) objD;
                int y10 = subIndicNamePosition.getY();
                if (aVar.a().Z()) {
                    C2738p.f19487a.s();
                    Context contextC = i().c();
                    int[] iArr = new int[2];
                    Chart chartA = i().a();
                    if (chartA != null) {
                        chartA.getLocationOnScreen(iArr);
                    }
                    new S(contextC, subIndicNamePosition.isScript()).f(i().a(), 10 + iArr[0], y10 + iArr[1], subIndicNamePosition.getKey(), this.f19316y, new C2696b());
                }
                return true;
            }
        }
        return false;
    }

    @Override // Rj.AbstractC2744r0
    public int p() {
        return this.f19308q;
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        int iB;
        if (aVar == null) {
            return;
        }
        this.f19304m.setColor(aVar.u(1));
        AbstractC2755v abstractC2755vQ = q();
        AbstractC7467h0 abstractC7467h0 = abstractC2755vQ instanceof AbstractC7467h0 ? (AbstractC7467h0) abstractC2755vQ : null;
        if (abstractC7467h0 == null) {
            return;
        }
        this.f19315x = aVar.w();
        sp.aicoin_kline.core.indicator.config.F fX = abstractC7467h0.x();
        this.f19311t = fX;
        String strN = fX != null ? fX.n() : null;
        E();
        if (this.f19314w) {
            Paint paint = new Paint(this.f19304m);
            KLineManager.a aVar2 = KLineManager.f142490O;
            paint.setColor(aVar.d(aVar2.a().V() ? ".main_red.color" : ".main_green.color"));
            Qf.H h10 = Qf.H.f17640a;
            Paint paint2 = new Paint(this.f19304m);
            paint2.setColor(aVar.d(aVar2.a().V() ? ".main_green.color" : ".main_red.color"));
            this.f19307p = Sf.r.t(paint, paint2);
            return;
        }
        int i10 = (AbstractC7609s.f(strN, "MA") || AbstractC7609s.f(strN, "EMA")) ? 20 : 10;
        int i11 = 0;
        while (i11 < i10) {
            List list = this.f19307p;
            Paint paint3 = new Paint(this.f19304m);
            sp.aicoin_kline.core.indicator.config.F f10 = this.f19311t;
            if (f10 != null) {
                iB = i11 < f10.k().length ? this.f19311t.k()[i11].a() : aVar.b(i11);
            } else {
                iB = aVar.b(i11);
            }
            paint3.setColor(iB);
            list.add(paint3);
            i11++;
        }
    }

    public final void w(Rect rect, int i10) {
        rect.left = i10;
        rect.top = (int) (rect.top + this.f19305n + 5.0f);
        this.f19308q = (int) (l() + this.f19305n + 5.0f);
    }

    public final Paint x(int i10) {
        return nk.z.a(this.f19307p, i10) ? (Paint) this.f19307p.get(i10) : this.f19304m;
    }

    /* JADX WARN: Code duplicated, block: B:137:0x00bd A[SYNTHETIC] */
    /* JADX WARN: Code duplicated, block: B:29:0x00ba  */
    /* JADX WARN: Multi-variable type inference failed */
    /* JADX WARN: Type inference failed for: r19v19 */
    /* JADX WARN: Type inference failed for: r19v20 */
    /* JADX WARN: Type inference failed for: r19v21 */
    /* JADX WARN: Type inference failed for: r19v22 */
    /* JADX WARN: Type inference failed for: r19v23 */
    /* JADX WARN: Type inference failed for: r19v6 */
    /* JADX WARN: Type inference failed for: r19v7 */
    /* JADX WARN: Type inference failed for: r19v8 */
    /* JADX WARN: Type inference failed for: r19v9 */
    /* JADX WARN: Type inference failed for: r3v17 */
    /* JADX WARN: Type inference failed for: r3v18 */
    /* JADX WARN: Type inference failed for: r3v20 */
    /* JADX WARN: Type inference failed for: r3v21 */
    /* JADX WARN: Type inference failed for: r3v22 */
    /* JADX WARN: Type inference failed for: r3v36 */
    /* JADX WARN: Type inference failed for: r3v37 */
    /* JADX WARN: Type inference failed for: r45v0 */
    /* JADX WARN: Type inference failed for: r45v1 */
    /* JADX WARN: Type inference failed for: r45v2 */
    /* JADX WARN: Type inference failed for: r45v3 */
    /* JADX WARN: Type inference failed for: r45v4 */
    /* JADX WARN: Type inference failed for: r7v3 */
    public final void y(Canvas canvas, C2702d c2702d, int i10, Function1 function1) {
        List listN;
        boolean z10;
        boolean z11;
        ?? r45;
        boolean z12;
        int i11;
        int i12;
        Bitmap bitmap;
        int i13 = i10;
        boolean z13 = false;
        if (i13 == 0) {
            this.f19308q = 0;
            return;
        }
        nk.r.b bVarD = this.f19309r.c().d();
        int i14 = 0;
        int i15 = 0;
        while (i14 < i13) {
            List list = (List) function1.invoke(Integer.valueOf(i14));
            Rect rectN = c2702d.n();
            rectN.left = B() + rectN.left;
            rectN.top = C() + rectN.top + i15;
            int i16 = rectN.left;
            int iC = C() + this.f19306o;
            int i17 = 2;
            int i18 = 1;
            boolean zO = Ah.x.y(b(), ".main", z13, 2, null) ? KLineManager.f142490O.a().o() : true;
            if (zO) {
                ArrayList arrayList = new ArrayList();
                for (Object obj : list) {
                    int i19 = i17;
                    b bVar = (b) obj;
                    if (bVar.e()) {
                        z10 = z13 ? 1 : 0;
                    } else {
                        z10 = z13 ? 1 : 0;
                        String strB = bVar.b();
                        if (strB.length() > 0 ? KLineManager.f142490O.a().l(strB) : KLineManager.f142490O.a().O()) {
                            z11 = z10 ? 1 : 0;
                        }
                        if (z11) {
                            arrayList.add(obj);
                        }
                        i17 = i19;
                        z13 = z10;
                    }
                    z11 = true;
                    if (z11) {
                        arrayList.add(obj);
                    }
                    i17 = i19;
                    z13 = z10;
                }
                listN = arrayList;
            } else {
                listN = Sf.r.n();
            }
            boolean z14 = z13;
            int i20 = i17;
            Iterator it = listN.iterator();
            int i21 = z14 ? 1 : 0;
            ?? r19 = z14;
            while (it.hasNext()) {
                Object next = it.next();
                int i22 = i21 + 1;
                if (i21 < 0) {
                    Sf.r.x();
                }
                b bVar2 = (b) next;
                String strA = bVar2.a();
                Paint paintC = bVar2.c();
                Iterator it2 = it;
                int i23 = i14;
                char[] cArr = new char[i18];
                cArr[r19] = '\n';
                List listL0 = Ah.y.L0(strA, cArr, false, 0, 6, null);
                int i24 = rectN.top;
                float f10 = Float.NEGATIVE_INFINITY;
                int i25 = i24;
                ?? r10 = r19;
                int i26 = r10 == true ? 1 : 0;
                float f11 = Float.POSITIVE_INFINITY;
                float f12 = Float.POSITIVE_INFINITY;
                float f13 = Float.NEGATIVE_INFINITY;
                ?? r11 = r10;
                ?? r110 = r19;
                for (Object obj2 : listL0) {
                    int i27 = (r11 == true ? 1 : 0) + 1;
                    if (r11 < 0) {
                        Sf.r.x();
                    }
                    List list2 = listN;
                    String str = (String) obj2;
                    if (r11 > 0) {
                        rectN.left = i16;
                        float f14 = rectN.top;
                        float f15 = this.f19305n;
                        rectN.top = (int) (f14 + f15 + 5.0f);
                        iC = (int) (iC + f15 + 5.0f);
                    }
                    boolean z15 = zO;
                    c cVarV = v(str, paintC, rectN.left, i16, rectN.right);
                    if (cVarV.a()) {
                        rectN.left = i16;
                        float f16 = rectN.top;
                        float f17 = this.f19305n;
                        rectN.top = (int) (f16 + f17 + 5.0f);
                        iC = (int) (iC + f17 + 5.0f);
                    }
                    List listB = cVarV.b();
                    if (listB.isEmpty()) {
                        listB = AbstractC2803q.e("");
                    }
                    float fMax = f10;
                    List list3 = listB;
                    float fMax2 = f13;
                    float fMin = f11;
                    b bVar3 = bVar2;
                    float fMin2 = f12;
                    int i28 = i22;
                    int i29 = r110 == true ? 1 : 0;
                    ?? r12 = r11;
                    ?? r111 = r110;
                    for (Object obj3 : listB) {
                        int i30 = i29 + 1;
                        if (i29 < 0) {
                            Sf.r.x();
                        }
                        int i31 = i15;
                        String str2 = (String) obj3;
                        if (i29 > 0) {
                            rectN.left = i16;
                            float f18 = rectN.top;
                            float f19 = this.f19305n;
                            rectN.top = (int) (f18 + f19 + 5.0f);
                            iC = (int) (iC + f19 + 5.0f);
                        }
                        int i32 = i26 == 0 ? rectN.top : i25;
                        int i33 = (i26 == true ? 1 : 0) + 1;
                        float fMeasureText = paintC.measureText(str2);
                        int i34 = iC;
                        float f20 = rectN.left;
                        boolean z16 = i21 == true ? 1 : 0;
                        float f21 = rectN.top + this.f19305n;
                        nk.r.b bVar4 = bVarD;
                        Paint.FontMetrics fontMetrics = paintC.getFontMetrics();
                        if (bVar3.d()) {
                            if (str2.length() > 0 ? true : r111 == true ? 1 : 0) {
                                canvas.drawText(str2, f20, f21, paintC);
                            }
                            boolean z17 = (r12 == Sf.r.p(listL0) && i29 == Sf.r.p(list3)) ? true : r111 == true ? 1 : 0;
                            float f22 = f20 + fMeasureText;
                            r45 = r12;
                            String upperCase = bVar3.b().toUpperCase(Locale.ROOT);
                            boolean zL = upperCase.length() > 0 ? true : r111 == true ? 1 : 0 ? KLineManager.f142490O.a().l(upperCase) : KLineManager.f142490O.a().O();
                            if (bVar3.e() && z15 && z17) {
                                this.f19316y = bVar3.a();
                            }
                            if (bVar3.e() && z15 && zL && z17 && (bitmap = this.f19313v) != null) {
                                float width = bitmap.getWidth();
                                float f23 = f21 + fontMetrics.ascent;
                                float f24 = ((((f21 + fontMetrics.descent) - f23) / 2.0f) + f23) - (width / 2.0f);
                                float fD = Xj.a.d(i20);
                                float f25 = f22 + fD;
                                canvas.drawBitmap(bitmap, f25, f24, (Paint) null);
                                f22 = width + fD + f25;
                            }
                            float f26 = f22;
                            float f27 = rectN.top;
                            float f28 = 20;
                            float fAbs = Math.abs(fontMetrics.ascent) + f27 + fontMetrics.descent + f28;
                            fMin = Math.min(fMin, f20);
                            fMin2 = Math.min(fMin2, f27 - f28);
                            fMax = Math.max(fMax, f28 + f26);
                            fMax2 = Math.max(fMax2, fAbs);
                            r45 = r45;
                            if (z17) {
                                boolean z18 = i33 > 1 ? true : r111 == true ? 1 : 0;
                                int length = strA.length();
                                Rect rect = this.f19310s;
                                z12 = r111 == true ? 1 : 0;
                                paintC.getTextBounds(strA, z12 ? 1 : 0, length, rect);
                                nk.q qVarA = nk.q.f134234e.a();
                                qVarA.j(new SubIndicNamePosition(this.f19310s.width(), i32, bVar3.b(), bVar3.f(), bVar3.a()));
                                qVarA.g(fMin, fMin2, fMax, fMax2);
                                bVarD = bVar4;
                                bVarD.e(qVarA);
                                int iP = Sf.r.p(list2);
                                i12 = z16 ? 1 : 0;
                                boolean z19 = i12 < iP ? true : z12 ? 1 : 0;
                                if (z18 && z19) {
                                    i11 = i16;
                                    rectN.left = i11;
                                    float f29 = rectN.top;
                                    float f30 = this.f19305n;
                                    rectN.top = (int) (f29 + f30 + 5.0f);
                                    iC = (int) (i34 + f30 + 5.0f);
                                } else {
                                    i11 = i16;
                                    iC = i34;
                                    if (!z18) {
                                        rectN.left = (int) f26;
                                    }
                                }
                            }
                            canvas = canvas;
                            r111 = z12;
                            i26 = i33;
                            i15 = i31;
                            i25 = i32;
                            r12 = r45;
                            i16 = i11;
                            i21 = i12;
                            i29 = i30;
                        } else {
                            r45 = r12;
                        }
                        z12 = r111 == true ? 1 : 0;
                        i11 = i16;
                        iC = i34;
                        i12 = z16 ? 1 : 0;
                        bVarD = bVar4;
                        canvas = canvas;
                        r111 = z12;
                        i26 = i33;
                        i15 = i31;
                        i25 = i32;
                        r12 = r45;
                        i16 = i11;
                        i21 = i12;
                        i29 = i30;
                    }
                    canvas = canvas;
                    f13 = fMax2;
                    f10 = fMax;
                    i22 = i28;
                    r11 = i27;
                    listN = list2;
                    zO = z15;
                    f12 = fMin2;
                    bVar2 = bVar3;
                    f11 = fMin;
                    r110 = r111;
                }
                canvas = canvas;
                it = it2;
                i21 = i22;
                i14 = i23;
                i18 = 1;
                r19 = r110;
            }
            i14++;
            i13 = i10;
            z13 = r19 == true ? 1 : 0;
            i15 += iC;
        }
        bVarD.b();
        this.f19308q = i15;
    }

    /* JADX WARN: Code duplicated, block: B:27:0x00b4  */
    /* JADX WARN: Multi-variable type inference failed */
    /* JADX WARN: Type inference failed for: r10v0, types: [java.util.ArrayList] */
    /* JADX WARN: Type inference failed for: r10v1, types: [java.lang.Iterable] */
    /* JADX WARN: Type inference failed for: r10v2 */
    /* JADX WARN: Type inference failed for: r10v28, types: [java.util.List] */
    /* JADX WARN: Type inference failed for: r10v29 */
    /* JADX WARN: Type inference failed for: r10v3 */
    /* JADX WARN: Type inference failed for: r10v30 */
    /* JADX WARN: Type inference failed for: r10v31 */
    /* JADX WARN: Type inference failed for: r10v6 */
    /* JADX WARN: Type inference failed for: r21v3, types: [java.util.List] */
    public final void z(Canvas canvas, C2702d c2702d, List list) {
        ?? arrayList;
        boolean z10;
        int i10;
        int i11;
        int i12;
        int i13;
        Bitmap bitmap;
        int i14 = 1;
        char c10 = 0;
        if (list.isEmpty()) {
            this.f19308q = 0;
            return;
        }
        y1 y1VarM = i().b().m(c());
        if (y1VarM == null) {
            return;
        }
        this.f19312u = y1VarM;
        Rect rectN = c2702d.n();
        rectN.left = B() + rectN.left;
        rectN.top = C() + rectN.top;
        int i15 = rectN.left;
        this.f19308q = C() + this.f19306o;
        int i16 = 2;
        boolean zO = Ah.x.y(b(), ".main", false, 2, null) ? KLineManager.f142490O.a().o() : true;
        nk.r.b bVarD = this.f19309r.c().d();
        if (zO) {
            arrayList = new ArrayList();
            for (Object obj : list) {
                b bVar = (b) obj;
                if (bVar.e()) {
                    z10 = true;
                } else {
                    String upperCase = bVar.b().toUpperCase(Locale.ROOT);
                    if (upperCase.length() > 0 ? KLineManager.f142490O.a().l(upperCase) : KLineManager.f142490O.a().O()) {
                        z10 = false;
                    } else {
                        z10 = true;
                    }
                }
                if (z10) {
                    arrayList.add(obj);
                }
            }
        } else {
            arrayList = Sf.r.n();
        }
        Iterator it = arrayList.iterator();
        int i17 = 0;
        ?? r10 = arrayList;
        while (it.hasNext()) {
            Object next = it.next();
            int i18 = i17 + 1;
            if (i17 < 0) {
                Sf.r.x();
            }
            b bVar2 = (b) next;
            Paint paintC = bVar2.c();
            String strA = bVar2.a();
            int i19 = i16;
            char[] cArr = new char[i14];
            cArr[c10] = '\n';
            List listL0 = Ah.y.L0(strA, cArr, false, 0, 6, null);
            int i20 = rectN.top;
            float f10 = Float.NEGATIVE_INFINITY;
            int i21 = i14;
            float f11 = Float.POSITIVE_INFINITY;
            float f12 = Float.POSITIVE_INFINITY;
            int i22 = 0;
            int i23 = 0;
            float f13 = Float.NEGATIVE_INFINITY;
            ?? r11 = r10;
            for (Object obj2 : listL0) {
                int i24 = i22 + 1;
                if (i22 < 0) {
                    Sf.r.x();
                }
                String str = (String) obj2;
                if (i22 > 0) {
                    w(rectN, i15);
                }
                int i25 = i20;
                boolean z11 = zO;
                c cVarV = v(str, paintC, rectN.left, i15, rectN.right);
                if (cVarV.a()) {
                    w(rectN, i15);
                }
                List listB = cVarV.b();
                if (listB.isEmpty()) {
                    listB = AbstractC2803q.e("");
                }
                float f14 = f11;
                int i26 = i25;
                List list2 = listB;
                float fMax = f10;
                float fMax2 = f13;
                List list3 = listL0;
                float fMin = f14;
                float fMin2 = f12;
                ?? r21 = r11;
                int i27 = 0;
                for (Object obj3 : listB) {
                    int i28 = i27 + 1;
                    if (i27 < 0) {
                        Sf.r.x();
                    }
                    Iterator it2 = it;
                    String str2 = (String) obj3;
                    if (i27 > 0) {
                        w(rectN, i15);
                    }
                    b bVar3 = bVar2;
                    int i29 = i23 == 0 ? rectN.top : i26;
                    int i30 = i23 + 1;
                    float fMeasureText = paintC.measureText(str2);
                    int i31 = i18;
                    float f15 = rectN.left;
                    int i32 = i15;
                    float f16 = rectN.top + this.f19305n;
                    int i33 = i17;
                    Paint.FontMetrics fontMetrics = paintC.getFontMetrics();
                    if (bVar3.d()) {
                        if ((str2.length() > 0 ? i21 : 0) != 0) {
                            canvas.drawText(str2, f15, f16, paintC);
                        }
                        int i34 = (i22 == Sf.r.p(list3) && i27 == Sf.r.p(list2)) ? i21 : 0;
                        float f17 = f15 + fMeasureText;
                        i10 = i22;
                        String upperCase2 = bVar3.b().toUpperCase(Locale.ROOT);
                        boolean zL = (upperCase2.length() > 0 ? i21 : 0) != 0 ? KLineManager.f142490O.a().l(upperCase2) : KLineManager.f142490O.a().O();
                        if (bVar3.e() && z11 && i34 != 0) {
                            this.f19316y = bVar3.a();
                        }
                        if (bVar3.e() && z11 && zL && i34 != 0 && (bitmap = this.f19313v) != null) {
                            float width = bitmap.getWidth();
                            float f18 = f16 + fontMetrics.ascent;
                            float f19 = ((((f16 + fontMetrics.descent) - f18) / 2.0f) + f18) - (width / 2.0f);
                            float fD = Xj.a.d(i19);
                            float f20 = f17 + fD;
                            canvas.drawBitmap(bitmap, f20, f19, (Paint) null);
                            f17 = width + fD + f20;
                        }
                        float f21 = f17;
                        float f22 = rectN.top;
                        float f23 = 20;
                        float fAbs = Math.abs(fontMetrics.ascent) + f22 + fontMetrics.descent + f23;
                        fMin = Math.min(fMin, f15);
                        fMin2 = Math.min(fMin2, f22 - f23);
                        fMax = Math.max(fMax, f23 + f21);
                        fMax2 = Math.max(fMax2, fAbs);
                        i11 = i21;
                        if (i34 != 0) {
                            int i35 = i30 > i11 ? i11 : 0;
                            paintC.getTextBounds(bVar3.a(), 0, bVar3.a().length(), this.f19310s);
                            nk.q qVarA = nk.q.f134234e.a();
                            qVarA.j(new SubIndicNamePosition(this.f19310s.width(), i29, bVar3.b(), bVar3.f(), bVar3.a()));
                            qVarA.g(fMin, fMin2, fMax, fMax2);
                            bVarD.e(qVarA);
                            i13 = i33;
                            int i36 = i13 < Sf.r.p(r21) ? i11 : 0;
                            if (i35 == 0 || i36 == 0) {
                                i12 = i32;
                                if (i35 == 0) {
                                    rectN.left = (int) f21;
                                }
                            } else {
                                i12 = i32;
                                rectN.left = i12;
                                w(rectN, i12);
                            }
                        }
                        i21 = i11;
                        i15 = i12;
                        i17 = i13;
                        i23 = i30;
                        bVar2 = bVar3;
                        i27 = i28;
                        it = it2;
                        i26 = i29;
                        i18 = i31;
                        i22 = i10;
                        canvas = canvas;
                    } else {
                        i10 = i22;
                        i11 = i21;
                    }
                    i12 = i32;
                    i13 = i33;
                    i21 = i11;
                    i15 = i12;
                    i17 = i13;
                    i23 = i30;
                    bVar2 = bVar3;
                    i27 = i28;
                    it = it2;
                    i26 = i29;
                    i18 = i31;
                    i22 = i10;
                    canvas = canvas;
                }
                canvas = canvas;
                f10 = fMax;
                i20 = i26;
                r11 = r21;
                i22 = i24;
                f11 = fMin;
                f12 = fMin2;
                listL0 = list3;
                f13 = fMax2;
                zO = z11;
            }
            i16 = i19;
            i14 = i21;
            i17 = i18;
            c10 = 0;
            r10 = r11;
        }
        bVarD.b();
    }
}
