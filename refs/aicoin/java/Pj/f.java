package Pj;

import Sf.r;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public abstract class f {
    public static /* synthetic */ List b(f fVar, List list, int i10, boolean z10, int i11, Object obj) {
        if (obj != null) {
            throw new UnsupportedOperationException("Super calls with default arguments not supported in this target, function: calculate");
        }
        if ((i11 & 4) != 0) {
            z10 = false;
        }
        return fVar.a(list, i10, z10);
    }

    public List a(List list, int i10, boolean z10) {
        List list2;
        int i11;
        ArrayList arrayList = new ArrayList();
        Iterator it = list.iterator();
        int i12 = 0;
        while (it.hasNext()) {
            it.next();
            int i13 = i12 + 1;
            if (i12 < 0) {
                r.x();
            }
            boolean z11 = true;
            int iMax = Math.max((i12 - i10) + 1, 0);
            if (i12 < i10 - 1 && !z10) {
                z11 = false;
            }
            if (iMax == i13 || !z11) {
                list2 = list;
                i11 = i10;
            } else {
                list2 = list;
                i11 = i10;
                arrayList.add(c(i12, i11, iMax, i13, list2));
            }
            i10 = i11;
            i12 = i13;
            list = list2;
        }
        return arrayList;
    }

    public abstract Object c(int i10, int i11, int i12, int i13, List list);
}
