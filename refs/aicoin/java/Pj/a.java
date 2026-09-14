package Pj;

import Sf.r;
import java.util.ArrayList;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public abstract class a {
    public static /* synthetic */ List b(a aVar, List list, int i10, boolean z10, int i11, Object obj) {
        if (obj != null) {
            throw new UnsupportedOperationException("Super calls with default arguments not supported in this target, function: calculate");
        }
        if ((i11 & 4) != 0) {
            z10 = false;
        }
        return aVar.a(list, i10, z10);
    }

    public List a(List list, int i10, boolean z10) {
        ArrayList arrayList = new ArrayList();
        int i11 = 0;
        for (Object obj : list) {
            int i12 = i11 + 1;
            if (i11 < 0) {
                r.x();
            }
            d(obj);
            int i13 = i11 - i10;
            int iMax = Math.max(i13 + 1, 0);
            int i14 = i10 - 1;
            if (i11 > i14) {
                e(list.get(i13));
            }
            boolean z11 = i11 >= i14 || z10;
            if (iMax != i12 && z11) {
                arrayList.add(c(i10, list));
            }
            i11 = i12;
        }
        return arrayList;
    }

    public abstract Object c(int i10, List list);

    public abstract void d(Object obj);

    public abstract void e(Object obj);
}
