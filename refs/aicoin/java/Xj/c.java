package Xj;

import Sf.z;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import p162hb.e;
import p254m.aicoin.kline.main.MainKlineFragment;
import sp.aicoin_kline.chart.data.AICYQItem;

/* JADX INFO: loaded from: classes7.dex */
public final class c {

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public static List f25379c;

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public static int f25382f;

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public static double f25383g;

    /* JADX INFO: renamed from: h, reason: collision with root package name */
    public static double f25384h;

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final c f25377a = new c();

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public static List f25378b = new ArrayList();

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public static boolean f25380d = true;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public static boolean f25381e = true;

    public final List a(AICYQItem aICYQItem, double d10) {
        double dDoubleValue;
        double dDoubleValue2;
        List listU1 = z.u1(aICYQItem.getDataList());
        if (listU1.isEmpty()) {
            return new ArrayList();
        }
        ArrayList arrayList = new ArrayList();
        int size = listU1.size();
        int i10 = 0;
        double d11 = 0.0d;
        double d12 = 0.0d;
        for (int i11 = 0; i11 < size; i11++) {
            Double d13 = (Double) ((Map) listU1.get(i11)).get(MainKlineFragment.KEY_AISRL_ASKS);
            double dDoubleValue3 = d13 != null ? d13.doubleValue() : 0.0d;
            Double d14 = (Double) ((Map) listU1.get(i11)).get(MainKlineFragment.KEY_AISRL_BIDS);
            double dDoubleValue4 = dDoubleValue3 + (d14 != null ? d14.doubleValue() : 0.0d);
            d11 += dDoubleValue4;
            if (dDoubleValue4 > d12) {
                i10 = i11;
                d12 = dDoubleValue4;
            }
        }
        double d15 = d11 * d10;
        if (i10 < 0 || i10 >= listU1.size()) {
            return new ArrayList();
        }
        int i12 = i10 - 1;
        int i13 = i10 + 1;
        arrayList.add(Integer.valueOf(i10));
        while (d12 < d15 && (i12 >= 0 || i13 < listU1.size())) {
            if (i12 >= 0) {
                Double d16 = (Double) ((Map) listU1.get(i12)).get(MainKlineFragment.KEY_AISRL_ASKS);
                double dDoubleValue5 = d16 != null ? d16.doubleValue() : 0.0d;
                Double d17 = (Double) ((Map) listU1.get(i12)).get(MainKlineFragment.KEY_AISRL_BIDS);
                dDoubleValue = dDoubleValue5 + (d17 != null ? d17.doubleValue() : 0.0d);
            } else {
                dDoubleValue = 0.0d;
            }
            if (i13 < listU1.size()) {
                Double d18 = (Double) ((Map) listU1.get(i13)).get(MainKlineFragment.KEY_AISRL_ASKS);
                double dDoubleValue6 = d18 != null ? d18.doubleValue() : 0.0d;
                Double d19 = (Double) ((Map) listU1.get(i13)).get(MainKlineFragment.KEY_AISRL_BIDS);
                dDoubleValue2 = dDoubleValue6 + (d19 != null ? d19.doubleValue() : 0.0d);
            } else {
                dDoubleValue2 = 0.0d;
            }
            if (i13 < listU1.size() && (i12 < 0 || dDoubleValue2 >= dDoubleValue)) {
                arrayList.add(Integer.valueOf(i13));
                d12 += dDoubleValue2;
                i13++;
            } else {
                if (i12 < 0) {
                    break;
                }
                arrayList.add(Integer.valueOf(i12));
                d12 += dDoubleValue;
                i12--;
            }
        }
        return arrayList;
    }

    public final void b() {
        f25384h = 0.0d;
    }

    public final double c() {
        return f25383g;
    }

    public final double d(double d10, double d11) {
        if (d11 <= 0.0d && d10 <= 0.0d) {
            return 0.0d;
        }
        if (d11 <= 0.0d || d10 <= 0.0d) {
            return ((Number) e.c(d11 > 0.0d, Double.valueOf(d11), Double.valueOf(d10))).doubleValue();
        }
        return (d11 + d10) / ((double) 2);
    }

    public final List e() {
        Double d10;
        Double d11;
        ArrayList arrayList = new ArrayList();
        Iterator it = f25378b.iterator();
        while (it.hasNext()) {
            int iIntValue = ((Number) it.next()).intValue();
            if (iIntValue > 0) {
                List list = f25379c;
                if (iIntValue < (list != null ? list.size() : 0)) {
                    List list2 = f25379c;
                    Map map = list2 != null ? (Map) list2.get(iIntValue) : null;
                    double dDoubleValue = 0.0d;
                    double dDoubleValue2 = (map == null || (d11 = (Double) map.get("from")) == null) ? 0.0d : d11.doubleValue();
                    if (map != null && (d10 = (Double) map.get("to")) != null) {
                        dDoubleValue = d10.doubleValue();
                    }
                    arrayList.add(Double.valueOf(f25377a.d(dDoubleValue2, dDoubleValue)));
                }
            }
        }
        return arrayList;
    }

    public final double f() {
        return f25384h;
    }

    public final boolean g() {
        return f25380d;
    }

    public final void h(List list) {
        f25379c = list;
    }

    public final void i(double d10) {
        f25383g = d10;
    }

    public final void j(boolean z10) {
        f25381e = z10;
    }

    public final void k(double d10) {
        f25384h = d10;
    }

    public final void l(int i10) {
        f25382f = i10;
    }

    public final void m(List list) {
        f25378b = list;
    }

    public final void n(boolean z10) {
        f25380d = z10;
    }
}
