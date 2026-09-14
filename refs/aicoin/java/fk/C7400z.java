package fk;

import java.util.Comparator;
import java.util.Map;

/* JADX INFO: renamed from: fk.z, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7400z implements Comparator {
    @Override // java.util.Comparator
    public final int compare(Object obj, Object obj2) {
        Long lR = Ah.w.r((String) ((Map.Entry) obj).getKey());
        Long lValueOf = Long.valueOf(lR != null ? lR.longValue() : 0L);
        Long lR2 = Ah.w.r((String) ((Map.Entry) obj2).getKey());
        return Uf.c.d(lValueOf, Long.valueOf(lR2 != null ? lR2.longValue() : 0L));
    }
}
