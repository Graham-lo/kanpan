package gk;

import java.util.Comparator;
import java.util.Map;

/* JADX INFO: renamed from: gk.q, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7484q implements Comparator {
    @Override // java.util.Comparator
    public final int compare(Object obj, Object obj2) {
        return Uf.c.d((Double) ((Map.Entry) obj2).getKey(), (Double) ((Map.Entry) obj).getKey());
    }
}
