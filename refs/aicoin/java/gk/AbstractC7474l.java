package gk;

import Sf.AbstractC2801o;
import java.util.ArrayList;
import java.util.Date;
import java.util.GregorianCalendar;
import java.util.LinkedHashMap;
import java.util.List;
import sp.aicoin_kline.chart.data.LargeTradeItem;
import sp.aicoin_kline.chart.data.LargeTradeMap;

/* JADX INFO: renamed from: gk.l, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public abstract class AbstractC7474l {
    public static final LargeTradeMap a(List list, long[] jArr) {
        List<LargeTradeItem> listU1 = Sf.z.u1(list);
        Long lQ0 = AbstractC2801o.q0(jArr, 0);
        long jLongValue = lQ0 != null ? lQ0.longValue() : 0L;
        Long lQ1 = AbstractC2801o.q0(jArr, 1);
        long jLongValue2 = (lQ1 != null ? lQ1.longValue() : 0L) - jLongValue;
        if (jLongValue2 <= 0) {
            return new LargeTradeMap(null, null, 3, null);
        }
        GregorianCalendar gregorianCalendar = new GregorianCalendar();
        for (LargeTradeItem largeTradeItem : listU1) {
            Long lR = Ah.w.r(largeTradeItem.getTimestamp());
            int iK = nk.w.f134250a.k(jLongValue2, jLongValue, lR != null ? lR.longValue() : 0L);
            gregorianCalendar.setTime(new Date(jLongValue));
            long j10 = 1000;
            gregorianCalendar.add(13, iK * ((int) (jLongValue2 / j10)));
            largeTradeItem.setDraw_time(gregorianCalendar.getTime().getTime() / j10);
        }
        LinkedHashMap linkedHashMap = new LinkedHashMap();
        for (Object obj : listU1) {
            Long lValueOf = Long.valueOf(((LargeTradeItem) obj).getDraw_time());
            Object arrayList = linkedHashMap.get(lValueOf);
            if (arrayList == null) {
                arrayList = new ArrayList();
                linkedHashMap.put(lValueOf, arrayList);
            }
            ((List) arrayList).add(obj);
        }
        return new LargeTradeMap(linkedHashMap, listU1);
    }
}
