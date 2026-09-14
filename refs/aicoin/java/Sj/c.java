package Sj;

import Qf.p;
import Qf.w;
import Sf.AbstractC2804s;
import Sf.r;
import Sf.z;
import android.graphics.Color;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import nk.m;
import sp.aicoin_kline.chart.data.EstimatedLiqVpcRecord;

/* JADX INFO: loaded from: classes7.dex */
public final class c {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final c f20766a = new c();

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public static final List f20767b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public static final ArrayList f20768c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public static final ArrayList f20769d;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public static String f20770e;

    public static final class a implements Comparator {
        @Override // java.util.Comparator
        public final int compare(Object obj, Object obj2) {
            EstimatedLiqVpcRecord estimatedLiqVpcRecord = (EstimatedLiqVpcRecord) obj2;
            EstimatedLiqVpcRecord estimatedLiqVpcRecord2 = (EstimatedLiqVpcRecord) obj;
            return Uf.c.d(Double.valueOf(Math.max(estimatedLiqVpcRecord.getFromPrice(), estimatedLiqVpcRecord.getToPrice())), Double.valueOf(Math.max(estimatedLiqVpcRecord2.getFromPrice(), estimatedLiqVpcRecord2.getToPrice())));
        }
    }

    static {
        List listQ = r.q("#FFFFFF", "#56FFA9", "#F2FF2C", "#EE4325", "#05174D");
        f20767b = r.q("#111111", "#05174D", "#013E75", "#43CF88", "#ABF30B", "#FDFE56", "#E8EC92");
        ArrayList arrayList = new ArrayList(AbstractC2804s.y(listQ, 10));
        Iterator it = listQ.iterator();
        while (it.hasNext()) {
            arrayList.add(Integer.valueOf(Color.parseColor((String) it.next())));
        }
        f20768c = arrayList;
        List list = f20767b;
        ArrayList arrayList2 = new ArrayList(AbstractC2804s.y(list, 10));
        Iterator it2 = list.iterator();
        while (it2.hasNext()) {
            arrayList2.add(Integer.valueOf(Color.parseColor((String) it2.next())));
        }
        f20769d = arrayList2;
        f20770e = "";
    }

    public final List a(List list, double d10, double d11) {
        List<EstimatedLiqVpcRecord> listD1 = z.d1(list, new a());
        ArrayList arrayList = new ArrayList(AbstractC2804s.y(listD1, 10));
        for (EstimatedLiqVpcRecord estimatedLiqVpcRecord : listD1) {
            float fO = d11 > d10 ? p292ng.i.o((float) ((estimatedLiqVpcRecord.getTurnover() - d10) / (d11 - d10)), 0.0f, 1.0f) : 0.0f;
            double fromPrice = estimatedLiqVpcRecord.getFromPrice();
            double toPrice = estimatedLiqVpcRecord.getToPrice();
            c cVar = f20766a;
            int iC = cVar.c(fO, false);
            double turnover = estimatedLiqVpcRecord.getTurnover();
            double turnover2 = estimatedLiqVpcRecord.getTurnover();
            arrayList.add(new d(fromPrice, toPrice, iC, turnover, (Double.isNaN(turnover2) || Double.isInfinite(turnover2)) ? "" : m.f134229a.b(turnover2), cVar.c(fO, true)));
        }
        return arrayList;
    }

    public final p b(Map map) {
        Iterator it = map.values().iterator();
        double turnover = Double.POSITIVE_INFINITY;
        double turnover2 = Double.NEGATIVE_INFINITY;
        while (it.hasNext()) {
            for (EstimatedLiqVpcRecord estimatedLiqVpcRecord : (List) it.next()) {
                if (estimatedLiqVpcRecord.getTurnover() < turnover) {
                    turnover = estimatedLiqVpcRecord.getTurnover();
                }
                if (estimatedLiqVpcRecord.getTurnover() > turnover2) {
                    turnover2 = estimatedLiqVpcRecord.getTurnover();
                }
            }
        }
        return (Double.isInfinite(turnover) || Double.isNaN(turnover) || Double.isInfinite(turnover2) || Double.isNaN(turnover2)) ? w.a(Double.valueOf(0.0d), Double.valueOf(0.0d)) : w.a(Double.valueOf(turnover), Double.valueOf(turnover2));
    }

    public final int c(float f10, boolean z10) {
        ArrayList arrayList = z10 ? f20769d : f20768c;
        if (arrayList.size() < 2) {
            throw new IllegalArgumentException("Failed requirement.");
        }
        float fO = p292ng.i.o(f10, 0.0f, 1.0f);
        int size = arrayList.size();
        float f11 = fO * (size - 1);
        int iP = p292ng.i.p((int) f11, 0, size - 2);
        int iIntValue = ((Number) arrayList.get(iP)).intValue();
        int iIntValue2 = ((Number) arrayList.get(iP + 1)).intValue();
        float fO2 = p292ng.i.o(f11 - iP, 0.0f, 1.0f);
        return Color.argb(p292ng.i.p((int) (((Color.alpha(iIntValue2) - Color.alpha(iIntValue)) * fO2) + Color.alpha(iIntValue)), 0, 255), p292ng.i.p((int) (((Color.red(iIntValue2) - Color.red(iIntValue)) * fO2) + Color.red(iIntValue)), 0, 255), p292ng.i.p((int) (((Color.green(iIntValue2) - Color.green(iIntValue)) * fO2) + Color.green(iIntValue)), 0, 255), p292ng.i.p((int) (((Color.blue(iIntValue2) - Color.blue(iIntValue)) * fO2) + Color.blue(iIntValue)), 0, 255));
    }

    public final String d() {
        return f20770e;
    }

    public final void e(String str) {
        f20770e = str;
    }
}
