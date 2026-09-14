package Pj;

import Sf.z;
import java.util.ArrayList;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public final class g extends f {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final ArrayList f17174a = new ArrayList();

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final ArrayList f17175b = new ArrayList();

    @Override // Pj.f
    /* JADX INFO: renamed from: d, reason: merged with bridge method [inline-methods] */
    public Double c(int i10, int i11, int i12, int i13, List list) {
        this.f17174a.clear();
        this.f17175b.clear();
        while (i12 < i13) {
            double dDoubleValue = ((Number) list.get(i12)).doubleValue();
            this.f17174a.add(Double.valueOf(i12));
            this.f17175b.add(Double.valueOf(dDoubleValue));
            i12++;
        }
        e.a aVar = new e.a();
        e.a aVar2 = new e.a();
        e.a(z.n1(this.f17174a), z.n1(this.f17175b), aVar2, aVar);
        return Double.valueOf((Double.isNaN(aVar.f17173a) || Double.isNaN(aVar2.f17173a)) ? Double.NaN : (((double) i10) * aVar.f17173a) + aVar2.f17173a);
    }
}
