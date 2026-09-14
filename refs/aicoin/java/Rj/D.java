package Rj;

import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import sp.aicoin_kline.chart.data.LargeTradeItem;

/* JADX INFO: loaded from: classes7.dex */
public abstract class D {
    public static final void a(List list, List list2) {
        LinkedHashMap linkedHashMap = new LinkedHashMap();
        int i10 = 0;
        for (Object obj : list) {
            int i11 = i10 + 1;
            if (i10 < 0) {
                Sf.r.x();
            }
            LargeTradeItem largeTradeItem = (LargeTradeItem) obj;
            if (!linkedHashMap.containsKey(largeTradeItem.getId())) {
                linkedHashMap.put(largeTradeItem.getId(), Integer.valueOf(i10));
            }
            i10 = i11;
        }
        Iterator it = list2.iterator();
        while (it.hasNext()) {
            LargeTradeItem largeTradeItem2 = (LargeTradeItem) it.next();
            Integer num = (Integer) linkedHashMap.get(largeTradeItem2.getId());
            if (num == null) {
                list.add(largeTradeItem2);
                linkedHashMap.put(largeTradeItem2.getId(), Integer.valueOf(Sf.r.p(list)));
            } else {
                list.set(num.intValue(), largeTradeItem2);
            }
        }
    }
}
