package fk;

import java.util.Comparator;
import sp.aicoin_kline.chart.data.AISRLItem;

/* JADX INFO: renamed from: fk.j, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7385j implements Comparator {
    @Override // java.util.Comparator
    public final int compare(Object obj, Object obj2) {
        return Uf.c.d(Double.valueOf(((AISRLItem) obj2).getAmount()), Double.valueOf(((AISRLItem) obj).getAmount()));
    }
}
