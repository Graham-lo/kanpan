package Pj;

import Sf.z;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class h extends f {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public double f17176a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public double f17177b;

    @Override // Pj.f
    /* JADX INFO: renamed from: d, reason: merged with bridge method [inline-methods] */
    public Double c(int i10, int i11, int i12, int i13, List list) {
        if (i10 != i11 - 1) {
            double dDoubleValue = ((Number) list.get(i10)).doubleValue() + (this.f17177b - this.f17176a);
            double d10 = dDoubleValue / ((double) i11);
            this.f17177b = dDoubleValue;
            this.f17176a = d10;
            return Double.valueOf(d10);
        }
        double dDoubleValue2 = 0.0d;
        while (i12 < i13) {
            dDoubleValue2 += ((Number) list.get(i12)).doubleValue();
            i12++;
        }
        this.f17177b = dDoubleValue2;
        double dC0 = z.c0(list.subList(0, i11));
        this.f17176a = dC0;
        return Double.valueOf(dC0);
    }

    public void e() {
        this.f17176a = 0.0d;
        this.f17177b = 0.0d;
    }
}
