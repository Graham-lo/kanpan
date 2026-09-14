package Rj;

import java.util.Comparator;
import sp.aicoin_kline.chart.data.AISRLItem;

/* JADX INFO: loaded from: classes7.dex */
public final class A implements Comparator {
    @Override // java.util.Comparator
    public final int compare(Object obj, Object obj2) {
        return Uf.c.d(Double.valueOf(((AISRLItem) obj).getPrice()), Double.valueOf(((AISRLItem) obj2).getPrice()));
    }
}
