package fk;

import Rj.AbstractC2744r0;
import Rj.AbstractC2755v;
import Rj.AbstractC2759w0;
import Rj.C2702d;
import Rj.C2732n;
import Rj.C2738p;
import Rj.C2741q;
import Rj.y1;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.PorterDuff;
import android.graphics.PorterDuffXfermode;
import android.graphics.RadialGradient;
import android.graphics.Shader;
import gk.C7472k;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.chart.data.LargeTradeInfo;
import sp.aicoin_kline.chart.data.LargeTradeItem;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: fk.d, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7379d extends AbstractC2744r0 {

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public static final a f95345A = new a(null);

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public static final float f95346B = Xj.a.a(1.0f);

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public static final float f95347C = Xj.a.a(2.0f);

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public static final float f95348D = Xj.a.a(2.5f);

    /* JADX INFO: renamed from: E, reason: collision with root package name */
    public static final float f95349E = Xj.a.a(10.0f);

    /* JADX INFO: renamed from: F, reason: collision with root package name */
    public static final float f95350F = Xj.a.a(2.5f);

    /* JADX INFO: renamed from: G, reason: collision with root package name */
    public static final float f95351G = Xj.a.a(8.0f);

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final Paint f95352l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Paint f95353m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final Paint f95354n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final Paint f95355o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final Paint f95356p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final Paint f95357q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final Paint f95358r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public final Paint f95359s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public C2702d f95360t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public y1 f95361u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public AbstractC2759w0 f95362v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public C7472k f95363w;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public List f95364x;

    /* JADX INFO: renamed from: y, reason: collision with root package name */
    public C7381f f95365y;

    /* JADX INFO: renamed from: z, reason: collision with root package name */
    public final nk.r f95366z;

    /* JADX INFO: renamed from: fk.d$a */
    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public C7379d(C2732n c2732n, String str) {
        super(c2732n, str);
        Paint paint = new Paint();
        paint.setStyle(Paint.Style.FILL_AND_STROKE);
        paint.setAntiAlias(true);
        paint.setStrokeWidth(2.0f);
        this.f95365y = new C7381f(0.0d, 0.0d, 0.0f, 7, null);
        this.f95366z = new nk.r();
        Paint paint2 = new Paint(paint);
        Paint.Style style = Paint.Style.STROKE;
        paint2.setStyle(style);
        this.f95352l = paint2;
        Paint paint3 = new Paint(paint);
        paint3.setStyle(style);
        this.f95353m = paint3;
        Paint paint4 = new Paint(paint);
        paint4.setStyle(style);
        this.f95354n = paint4;
        Paint paint5 = new Paint(paint);
        paint5.setStyle(style);
        this.f95355o = paint5;
        Paint paint6 = new Paint(paint);
        paint6.setStyle(style);
        paint6.setDither(true);
        this.f95356p = paint6;
        Paint paint7 = new Paint(paint);
        Paint.Style style2 = Paint.Style.FILL;
        paint7.setStyle(style2);
        paint7.setColor(-1);
        this.f95357q = paint7;
        Paint paint8 = new Paint(paint);
        paint8.setStyle(style2);
        paint8.setColor(-1);
        paint8.setDither(true);
        this.f95358r = paint8;
        Paint paint9 = new Paint(paint);
        paint9.setStyle(style2);
        paint9.setColor(-1);
        paint9.setDither(true);
        paint9.setXfermode(new PorterDuffXfermode(PorterDuff.Mode.DST_OUT));
        this.f95359s = paint9;
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) throws Throwable {
        AbstractC2759w0 abstractC2759w0;
        C7472k c7472k;
        nk.r.b bVar;
        C7379d c7379d = this;
        y1 y1Var = c7379d.f95361u;
        if (y1Var == null || (abstractC2759w0 = c7379d.f95362v) == null || (c7472k = c7379d.f95363w) == null) {
            return;
        }
        nk.r.b bVarC = c7379d.f95366z.c();
        bVarC.d();
        try {
            if (abstractC2759w0.z() == 0.0d) {
                bVarC.b();
                return;
            }
            Map<Long, List<LargeTradeItem>> map = c7472k.s().getMap();
            if (map == null) {
                map = Sf.N.j();
            }
            Map<Long, List<LargeTradeItem>> map2 = map;
            if (map2.isEmpty()) {
                bVarC.b();
                return;
            }
            List<LargeTradeItem> list = c7472k.s().getList();
            if (list == null) {
                list = Sf.r.n();
            }
            if (c7379d.f95364x != list) {
                c7379d.f95364x = list;
                c7379d.f95365y = C7380e.c(C7380e.f95368a, list, 0.0f, 2, null);
            }
            C7381f c7381f = c7379d.f95365y;
            float fU = y1Var.u();
            int iR = y1Var.r();
            int iQ = y1Var.q();
            float fJ = y1Var.J();
            int size = 0;
            for (int i10 = iR; i10 < iQ; i10++) {
                List<LargeTradeItem> listN = map2.get(Long.valueOf(y1Var.H(i10)));
                if (listN == null) {
                    listN = Sf.r.n();
                }
                size += listN.size();
            }
            boolean z10 = size >= 240;
            float f10 = (fU / 2) - fJ;
            int i11 = iR;
            while (i11 < iQ) {
                List<LargeTradeItem> listN2 = map2.get(Long.valueOf(y1Var.H(i11)));
                if (listN2 == null) {
                    listN2 = Sf.r.n();
                }
                List<LargeTradeItem> list2 = listN2;
                if (list2.isEmpty()) {
                    bVar = bVarC;
                } else {
                    bVar = bVarC;
                    try {
                        c7379d.v(bVar, abstractC2759w0, canvas, list2, f10, c7379d.f95360t, z10, c7381f, fU);
                    } catch (Throwable th2) {
                        th = th2;
                    }
                }
                f10 += fU;
                i11++;
                c7379d = this;
                bVarC = bVar;
            }
            bVarC.b();
            return;
        } catch (Throwable th3) {
            th = th3;
            bVar = bVarC;
        }
        bVar.b();
        throw th;
    }

    @Override // Rj.AbstractC2744r0
    public boolean n(String str, int i10, int i11) {
        Object objD = this.f95366z.d(i10, i11);
        LargeTradeInfo largeTradeInfo = null;
        LargeTradeInfo largeTradeInfo2 = objD instanceof LargeTradeInfo ? (LargeTradeInfo) objD : null;
        C2738p c2738p = C2738p.f19487a;
        if (largeTradeInfo2 != null) {
            largeTradeInfo2.setX(i10);
            largeTradeInfo = largeTradeInfo2;
        }
        c2738p.l(largeTradeInfo);
        return largeTradeInfo2 != null;
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        if (aVar == null) {
            return;
        }
        KLineManager kLineManagerA = KLineManager.f142490O.a();
        if (kLineManagerA.V()) {
            Color.parseColor("#007F65");
        } else {
            Color.parseColor("#B7004B");
        }
        if (kLineManagerA.V()) {
            Color.parseColor("#B7004B");
        } else {
            Color.parseColor("#007F65");
        }
        int color = kLineManagerA.V() ? Color.parseColor("#FF32A853") : Color.parseColor("#FFEB4236");
        int color2 = kLineManagerA.V() ? Color.parseColor("#FFEB4236") : Color.parseColor("#FF32A853");
        this.f95352l.setColor(color);
        this.f95352l.setAlpha(110);
        this.f95353m.setColor(color2);
        this.f95353m.setAlpha(110);
        this.f95354n.setColor(color);
        this.f95354n.setAlpha(4);
        this.f95355o.setColor(color2);
        this.f95355o.setAlpha(4);
        C2741q c2741qB = i().b();
        this.f95360t = c2741qB.e(b());
        this.f95361u = c2741qB.m(c());
        this.f95362v = c2741qB.l(b());
        AbstractC2755v abstractC2755vQ = q();
        C7472k c7472k = abstractC2755vQ instanceof C7472k ? (C7472k) abstractC2755vQ : null;
        if (c7472k == null) {
            return;
        }
        this.f95363w = c7472k;
    }

    public final void v(nk.r.b bVar, AbstractC2759w0 abstractC2759w0, Canvas canvas, List list, float f10, C2702d c2702d, boolean z10, C7381f c7381f, float f11) {
        Canvas canvas2;
        float f12;
        float f13;
        float f14;
        Canvas canvas3 = canvas;
        float f15 = f10;
        Iterator it = list.iterator();
        while (it.hasNext()) {
            LargeTradeItem largeTradeItem = (LargeTradeItem) it.next();
            boolean zF = AbstractC7609s.f(largeTradeItem.getTrade_type(), "bid");
            Double dN = Ah.v.n(largeTradeItem.getStart_price());
            float fS = abstractC2759w0.S(dN != null ? dN.doubleValue() : 0.0d);
            float fD = C7380e.f95368a.d(largeTradeItem, c7381f, f11);
            if (c2702d == null || (fS + fD >= c2702d.z() && fS - fD <= c2702d.p())) {
                Paint paint = zF ? this.f95353m : this.f95352l;
                Paint paint2 = zF ? this.f95355o : this.f95354n;
                int color = paint.getColor();
                if (z10) {
                    float fO = p292ng.i.o(fD * 0.055f, f95346B, f95347C);
                    float fO2 = p292ng.i.o(fD * 0.22f, f95348D, f95349E);
                    this.f95356p.setShader(null);
                    this.f95356p.setStyle(Paint.Style.FILL);
                    Paint paint3 = paint;
                    this.f95356p.setColor(Color.argb(18, Color.red(color), Color.green(color), Color.blue(color)));
                    canvas3.drawCircle(f15, fS, fD, this.f95356p);
                    paint2.clearShadowLayer();
                    paint2.setStrokeWidth(fO2);
                    paint2.setColor(Color.argb(28, Color.red(color), Color.green(color), Color.blue(color)));
                    canvas3.drawCircle(f15, fS, fD - (fO2 / 2.0f), paint2);
                    this.f95357q.setShader(null);
                    this.f95357q.setColor(Color.argb(12, Color.red(-1), Color.green(-1), Color.blue(-1)));
                    canvas3.drawCircle(f15, fS, fD * 0.52f, this.f95357q);
                    this.f95358r.setShader(null);
                    this.f95358r.setColor(Color.argb(18, Color.red(-1), Color.green(-1), Color.blue(-1)));
                    canvas3.drawCircle(f15 - (fD * 0.08f), fS - (fD * 0.1f), fD * 0.55f, this.f95358r);
                    paint3.setStrokeWidth(fO);
                    canvas3.drawCircle(f15, fS, fD - (fO / 2.0f), paint3);
                    canvas2 = canvas3;
                    f13 = f15;
                    f12 = fS;
                    f14 = fD;
                } else {
                    Paint paint4 = paint;
                    float fO3 = p292ng.i.o(0.14f * fD, f95350F, f95351G);
                    float fO4 = p292ng.i.o(fD * 0.055f, f95346B, f95347C);
                    float fO5 = p292ng.i.o(fD * 0.22f, f95348D, f95349E);
                    paint2.setStrokeWidth(fO5);
                    paint2.setColor(Color.argb(4, Color.red(color), Color.green(color), Color.blue(color)));
                    paint2.setShadowLayer(fO3, 0.0f, 0.0f, Color.argb(44, Color.red(color), Color.green(color), Color.blue(color)));
                    canvas3.drawCircle(f15, fS, fD - (fO5 / 2.0f), paint2);
                    int iSaveLayer = canvas3.saveLayer((f15 - fD) - fO3, (fS - fD) - fO3, f15 + fD + fO3, fS + fD + fO3, null);
                    this.f95356p.setStyle(Paint.Style.FILL);
                    Paint paint5 = this.f95356p;
                    Shader.TileMode tileMode = Shader.TileMode.CLAMP;
                    canvas2 = canvas;
                    f12 = fS;
                    f13 = f15;
                    paint5.setShader(new RadialGradient(f13, f12, fD, new int[]{Color.argb(18, Color.red(color), Color.green(color), Color.blue(color)), Color.argb(28, Color.red(color), Color.green(color), Color.blue(color)), Color.argb(36, Color.red(color), Color.green(color), Color.blue(color))}, new float[]{0.0f, 0.72f, 1.0f}, tileMode));
                    canvas2.drawCircle(f13, f12, fD, this.f95356p);
                    this.f95356p.setShader(null);
                    f14 = fD;
                    this.f95359s.setShader(new RadialGradient(f13, f12, 0.92f * fD, new int[]{Color.argb(255, Color.red(-1), Color.green(-1), Color.blue(-1)), Color.argb(150, Color.red(-1), Color.green(-1), Color.blue(-1)), Color.argb(0, Color.red(-1), Color.green(-1), Color.blue(-1))}, new float[]{0.0f, 0.5f, 1.0f}, tileMode));
                    canvas2.drawCircle(f13, f12, f14 * 0.88f, this.f95359s);
                    this.f95359s.setShader(null);
                    canvas2.restoreToCount(iSaveLayer);
                    this.f95357q.setShader(new RadialGradient(f15 - (fD * 0.08f), fS - (fD * 0.1f), f14 * 0.48f, new int[]{Color.argb(18, Color.red(-1), Color.green(-1), Color.blue(-1)), Color.argb(4, Color.red(-1), Color.green(-1), Color.blue(-1)), Color.argb(0, Color.red(-1), Color.green(-1), Color.blue(-1))}, new float[]{0.0f, 0.5f, 1.0f}, tileMode));
                    canvas2.drawCircle(f13, f12, f14 * 0.52f, this.f95357q);
                    this.f95357q.setShader(null);
                    this.f95358r.setShader(new RadialGradient(f13 - (f14 * 0.18f), f12 - (f14 * 0.24f), f14 * 0.58f, new int[]{Color.argb(22, Color.red(-1), Color.green(-1), Color.blue(-1)), Color.argb(8, Color.red(-1), Color.green(-1), Color.blue(-1)), Color.argb(0, Color.red(-1), Color.green(-1), Color.blue(-1))}, new float[]{0.0f, 0.58f, 1.0f}, tileMode));
                    canvas2.drawCircle(f13, f12, f14 * 0.55f, this.f95358r);
                    this.f95358r.setShader(null);
                    paint4.setStrokeWidth(fO4);
                    canvas2.drawCircle(f13, f12, f14 - (fO4 / 2.0f), paint4);
                }
                float f16 = 10;
                float f17 = (f13 - f14) - f16;
                float f18 = (f12 - f14) - f16;
                float f19 = f13 + f14 + f16;
                float f20 = f12 + f14 + f16;
                LargeTradeInfo largeTradeInfo = new LargeTradeInfo(0, largeTradeItem.getCoin_type(), largeTradeItem.getTrade_type(), largeTradeItem.getStart_price(), largeTradeItem.getStop_price(), largeTradeItem.getMax_price(), largeTradeItem.getMax_price_usd(), largeTradeItem.getSlippage_price(), largeTradeItem.getMax_amount(), largeTradeItem.getMax_vol(), largeTradeItem.getTotal_amount(), largeTradeItem.getTotal_vol(), largeTradeItem.getTotal_count(), largeTradeItem.getTotal_turnover(), largeTradeItem.getUpdate_time());
                nk.q qVarA = nk.q.f134234e.a();
                qVarA.g(f17, f18, f19, f20);
                qVarA.i(f17, f18, f19, f20);
                qVarA.j(largeTradeInfo);
                bVar.e(qVarA);
                f15 = f13;
                canvas3 = canvas2;
                it = it;
            }
        }
    }
}
