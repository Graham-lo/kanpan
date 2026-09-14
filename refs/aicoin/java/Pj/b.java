package Pj;

import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class b extends f {
    @Override // Pj.f
    /* JADX INFO: renamed from: d, reason: merged with bridge method [inline-methods] */
    public c c(int i10, int i11, int i12, int i13, List list) {
        double dMax = -1.7976931348623157E308d;
        double dMin = Double.MAX_VALUE;
        while (i12 < i13) {
            dMax = Math.max(dMax, ((Sj.b) list.get(i12)).b());
            dMin = Math.min(dMin, ((Sj.b) list.get(i12)).c());
            i12++;
        }
        return new c(dMax, dMin, (dMax + dMin) / ((double) 2));
    }
}
