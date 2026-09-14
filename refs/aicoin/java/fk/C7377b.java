package fk;

import Rj.AbstractC2744r0;
import Rj.AbstractC2755v;
import Rj.AbstractC2759w0;
import Rj.C2732n;
import Rj.C2738p;
import Rj.C2741q;
import Rj.y1;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import gk.C7468i;
import java.util.HashMap;
import java.util.List;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.chart.data.LargeOrderItem;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: fk.b, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7377b extends AbstractC2744r0 {

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public static final a f95329v = new a(null);

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final Paint f95330l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Paint f95331m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final Paint f95332n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final Paint f95333o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public y1 f95334p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public AbstractC2759w0 f95335q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public C7468i f95336r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public final nk.r f95337s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public final HashMap f95338t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public final I f95339u;

    /* JADX INFO: renamed from: fk.b$a */
    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public C7377b(C2732n c2732n, String str) {
        super(c2732n, str);
        Paint paint = new Paint();
        paint.setStyle(Paint.Style.FILL_AND_STROKE);
        paint.setAntiAlias(true);
        paint.setStrokeWidth(2.0f);
        this.f95330l = new Paint(paint);
        this.f95331m = new Paint(paint);
        this.f95332n = new Paint(paint);
        this.f95333o = new Paint(paint);
        this.f95337s = new nk.r();
        this.f95338t = new HashMap();
        this.f95339u = new I();
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) throws Throwable {
        AbstractC2759w0 abstractC2759w0;
        C7468i c7468i;
        nk.r.b bVar;
        long j10;
        long jLongValue;
        int iIntValue;
        int iIntValue2;
        C7377b c7377b = this;
        y1 y1Var = c7377b.f95334p;
        if (y1Var == null || (abstractC2759w0 = c7377b.f95335q) == null || (c7468i = c7377b.f95336r) == null) {
            return;
        }
        nk.r.b bVarD = c7377b.f95337s.c().d();
        try {
            if (abstractC2759w0.z() == 0.0d) {
                bVarD.b();
                return;
            }
            long jF = y1Var.F();
            long jN = y1Var.n();
            int iR = y1Var.r();
            int iY = y1Var.y();
            float fU = y1Var.u();
            float fJ = (fU / 2) - y1Var.J();
            int iV = y1Var.v();
            c7377b.f95338t.clear();
            if (iR <= iY) {
                int i10 = iR;
                while (true) {
                    c7377b.f95338t.put(Long.valueOf(y1Var.H(i10)), Integer.valueOf(i10));
                    if (i10 == iY) {
                        break;
                    } else {
                        i10++;
                    }
                }
            }
            List<LargeOrderItem> list = c7468i.w().getList();
            if (list == null) {
                list = Sf.r.n();
            }
            for (LargeOrderItem largeOrderItem : c7377b.f95339u.d(list, jF, jN)) {
                Long draw_start_time = largeOrderItem.getDraw_start_time();
                long jLongValue2 = draw_start_time != null ? draw_start_time.longValue() : 0L;
                Long draw_miss_time = largeOrderItem.getDraw_miss_time();
                if (draw_miss_time != null) {
                    jLongValue = draw_miss_time.longValue();
                    j10 = jN;
                } else {
                    j10 = jN;
                    jLongValue = 0;
                }
                if (AbstractC7378c.b(jLongValue2, jLongValue, jF, j10)) {
                    if (jLongValue2 < jF) {
                        iIntValue = iR;
                    } else {
                        Integer num = (Integer) c7377b.f95338t.get(Long.valueOf(jLongValue2));
                        if (num != null) {
                            iIntValue = num.intValue();
                        } else {
                            c7377b = this;
                        }
                    }
                    if (jLongValue == 0 || jLongValue > j10) {
                        iIntValue2 = iV;
                    } else {
                        Integer num2 = (Integer) c7377b.f95338t.get(Long.valueOf(jLongValue));
                        if (num2 != null) {
                            iIntValue2 = num2.intValue();
                        } else {
                            continue;
                        }
                    }
                    float f10 = ((iIntValue - iR) * fU) + fJ;
                    int i11 = iIntValue;
                    bVar = bVarD;
                    float f11 = fU;
                    try {
                        c7377b.v(bVar, abstractC2759w0, canvas, largeOrderItem, f11, f10, i11, iIntValue2);
                        c7377b = this;
                        bVarD = bVar;
                        fU = f11;
                    } catch (Throwable th2) {
                        th = th2;
                    }
                }
                jF = jF;
                jN = j10;
            }
            bVarD.b();
            return;
        } catch (Throwable th3) {
            th = th3;
            bVar = bVarD;
        }
        bVar.b();
        throw th;
    }

    @Override // Rj.AbstractC2744r0
    public boolean n(String str, int i10, int i11) {
        Object objD = this.f95337s.d(i10, i11);
        LargeOrderItem largeOrderItem = objD instanceof LargeOrderItem ? (LargeOrderItem) objD : null;
        C2738p.f19487a.k(largeOrderItem != null ? AbstractC7378c.a(largeOrderItem, i10) : null);
        return largeOrderItem != null;
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        if (aVar == null) {
            return;
        }
        boolean zV = KLineManager.f142490O.a().V();
        int color = Color.parseColor(zV ? "#007F65" : "#B7004B");
        int color2 = Color.parseColor(zV ? "#B7004B" : "#007F65");
        int color3 = Color.parseColor(zV ? "#8C007F65" : "#8CB7004B");
        int color4 = Color.parseColor(zV ? "#8CB7004B" : "#8C007F65");
        this.f95330l.setColor(color);
        this.f95331m.setColor(color2);
        this.f95332n.setColor(color3);
        this.f95333o.setColor(color4);
        C2741q c2741qB = i().b();
        this.f95334p = c2741qB.m(c());
        this.f95335q = c2741qB.l(b());
        AbstractC2755v abstractC2755vQ = q();
        this.f95336r = abstractC2755vQ instanceof C7468i ? (C7468i) abstractC2755vQ : null;
    }

    public final void v(nk.r.b bVar, AbstractC2759w0 abstractC2759w0, Canvas canvas, LargeOrderItem largeOrderItem, float f10, float f11, int i10, int i11) {
        float f12 = i11 == i10 ? f10 + f11 : ((i11 - i10) * f10) + f11;
        if (f12 < f11) {
            return;
        }
        boolean zF = AbstractC7609s.f(largeOrderItem.getDepth_type(), "bid");
        Double fake_price_double = largeOrderItem.getFake_price_double();
        float fS = abstractC2759w0.S(fake_price_double != null ? fake_price_double.doubleValue() : 0.0d);
        Double depth_price_double = largeOrderItem.getDepth_price_double();
        float fS2 = abstractC2759w0.S(depth_price_double != null ? depth_price_double.doubleValue() : 0.0d);
        float fAbs = Math.abs(fS2 - fS);
        float f13 = zF ? fS2 : fS2 - fAbs;
        if (zF) {
            fS2 += fAbs;
        }
        float f14 = fS2;
        Integer depth_state_int = largeOrderItem.getDepth_state_int();
        boolean z10 = (depth_state_int != null && depth_state_int.intValue() == 0) || AbstractC7609s.f(largeOrderItem.getDepth_state(), "3");
        canvas.drawRect(f11, f13, f12, f14, zF ? (Paint) p162hb.e.c(z10, this.f95333o, this.f95331m) : (Paint) p162hb.e.c(z10, this.f95332n, this.f95330l));
        float f15 = 10;
        float fMin = Math.min(f11, f12) - f15;
        float fMin2 = Math.min(f13, f14) - f15;
        float fMax = Math.max(f11, f12) + f15;
        float fMax2 = Math.max(f13, f14) + f15;
        nk.q qVarA = nk.q.f134234e.a();
        qVarA.g(fMin, fMin2, fMax, fMax2);
        qVarA.i(fMin, fMin2, fMax, fMax2);
        qVarA.j(largeOrderItem);
        bVar.e(qVarA);
    }
}
