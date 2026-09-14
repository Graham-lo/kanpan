package fk;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import sp.aicoin_kline.chart.data.LargeTradeItem;

/* JADX INFO: renamed from: fk.e, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7380e {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final C7380e f95368a = new C7380e();

    public static double a(List list, double d10) {
        if (list.size() == 1) {
            return ((Number) Sf.z.o0(list)).doubleValue();
        }
        double dN = p292ng.i.n(((double) (list.size() - 1)) * d10, 0.0d, list.size() - 1);
        int iFloor = (int) Math.floor(dN);
        return ((((Number) list.get(p292ng.i.k(iFloor + 1, Sf.r.p(list)))).doubleValue() - ((Number) list.get(iFloor)).doubleValue()) * (dN - ((double) iFloor))) + ((Number) list.get(iFloor)).doubleValue();
    }

    public static /* synthetic */ C7381f c(C7380e c7380e, List list, float f10, int i10, Object obj) {
        if ((i10 & 2) != 0) {
            f10 = 50.0f;
        }
        return c7380e.b(list, f10);
    }

    /* JADX WARN: Code duplicated, block: B:14:0x0043  */
    public final C7381f b(List list, float f10) {
        float fO = p292ng.i.o(f10, 20.0f, 100.0f);
        ArrayList arrayList = new ArrayList();
        Iterator it = list.iterator();
        while (it.hasNext()) {
            LargeTradeItem largeTradeItem = (LargeTradeItem) it.next();
            C7380e c7380e = f95368a;
            String total_turnover = largeTradeItem.getTotal_turnover();
            c7380e.getClass();
            Double dN = Ah.v.n(total_turnover);
            if (dN != null) {
                double dDoubleValue = dN.doubleValue();
                if (dDoubleValue <= 0.0d || Double.isInfinite(dDoubleValue) || Double.isNaN(dDoubleValue)) {
                    dN = null;
                }
            } else {
                dN = null;
            }
            if (dN != null) {
                arrayList.add(dN);
            }
        }
        List listB1 = Sf.z.b1(arrayList);
        if (listB1.isEmpty()) {
            return new C7381f(0.0d, 0.0d, fO, 3, null);
        }
        return new C7381f(Math.log10(a(listB1, 0.05d)), Math.log10(a(listB1, 0.95d)), fO);
    }

    /* JADX WARN: Code duplicated, block: B:11:0x0021  */
    public final float d(LargeTradeItem largeTradeItem, C7381f c7381f, float f10) {
        Double dN = Ah.v.n(largeTradeItem.getTotal_turnover());
        if (dN != null) {
            double dDoubleValue = dN.doubleValue();
            if (dDoubleValue <= 0.0d || Double.isInfinite(dDoubleValue) || Double.isNaN(dDoubleValue)) {
                dN = null;
            }
        } else {
            dN = null;
        }
        return e(dN, c7381f, f10);
    }

    public final float e(Double d10, C7381f c7381f, float f10) {
        float fN;
        if (d10 == null || !c7381f.a()) {
            fN = 0.0f;
        } else {
            fN = c7381f.b() <= c7381f.d() ? 0.5f : (float) p292ng.i.n((Math.log10(d10.doubleValue()) - c7381f.d()) / (c7381f.b() - c7381f.d()), 0.0d, 1.0d);
        }
        return p208jg.c.d(Math.min(c7381f.c(), p292ng.i.o((float) Math.floor((f10 - 6.0f) / 4.0f), 0.0f, 6.0f) + ((c7381f.c() - 5.0f) * fN) + 5.0f));
    }
}
