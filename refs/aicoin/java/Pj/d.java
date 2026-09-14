package Pj;

import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class d extends f {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public double f17171a = Double.NaN;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public double f17172b;

    @Override // Pj.f
    /* JADX INFO: renamed from: d, reason: merged with bridge method [inline-methods] */
    public Double c(int i10, int i11, int i12, int i13, List list) {
        if (Double.isNaN(this.f17171a)) {
            this.f17171a = 2.0d / (((double) i11) + 1.0d);
        }
        if (i10 >= i11) {
            double dDoubleValue = ((((Number) list.get(i10)).doubleValue() - this.f17172b) * this.f17171a) + this.f17172b;
            this.f17172b = dDoubleValue;
            return Double.valueOf(dDoubleValue);
        }
        double dDoubleValue2 = ((Number) list.get(i10)).doubleValue() + this.f17172b;
        this.f17172b = dDoubleValue2;
        if (i10 != i11 - 1) {
            return Double.valueOf(Double.NaN);
        }
        double d10 = dDoubleValue2 / ((double) i11);
        this.f17172b = d10;
        return Double.valueOf(d10);
    }

    public void e() {
        this.f17171a = Double.NaN;
        this.f17172b = 0.0d;
    }
}
