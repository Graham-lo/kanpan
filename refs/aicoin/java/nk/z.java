package nk;

import java.util.ArrayList;
import java.util.Collection;
import java.util.Iterator;
import java.util.List;
import java.util.NoSuchElementException;

/* JADX INFO: loaded from: classes7.dex */
public abstract class z {
    public static final boolean a(Collection collection, int i10) {
        return !collection.isEmpty() && i10 >= 0 && i10 < collection.size();
    }

    public static final boolean b(double[] dArr, int i10) {
        return dArr.length != 0 && i10 >= 0 && i10 < dArr.length;
    }

    public static final List c(List list, int i10, Object obj) {
        int size = i10 - list.size();
        if (size <= 0) {
            return list;
        }
        ArrayList arrayList = new ArrayList();
        for (int i11 = 0; i11 < size; i11++) {
            arrayList.add(obj);
        }
        arrayList.addAll(list);
        return arrayList;
    }

    public static final List d(List list, int i10, Object obj) {
        int size = i10 - list.size();
        if (size <= 0) {
            return list;
        }
        ArrayList arrayList = new ArrayList();
        arrayList.addAll(list);
        for (int i11 = 0; i11 < size; i11++) {
            arrayList.add(obj);
        }
        return arrayList;
    }

    public static final List e(List list, int i10) {
        return c(list, i10, Double.valueOf(Double.NaN));
    }

    public static final List f(List list, int i10) {
        return d(list, i10, Double.valueOf(Double.NaN));
    }

    public static final int g(double[] dArr) {
        int length = dArr.length;
        do {
            length--;
            if (-1 >= length) {
                return dArr.length;
            }
        } while (Double.isNaN(dArr[length]));
        return length + 1;
    }

    public static final Integer h(List list, Object obj) {
        int iIndexOf;
        if (list == null || (iIndexOf = list.indexOf(obj)) == -1) {
            return null;
        }
        return Integer.valueOf(iIndexOf);
    }

    public static final Double i(Iterable iterable) {
        Iterator it = iterable.iterator();
        if (!it.hasNext()) {
            return null;
        }
        double dDoubleValue = ((Number) it.next()).doubleValue();
        while (it.hasNext()) {
            double dDoubleValue2 = ((Number) it.next()).doubleValue();
            if (!Double.isNaN(dDoubleValue2) && dDoubleValue < dDoubleValue2) {
                dDoubleValue = dDoubleValue2;
            }
        }
        return Double.valueOf(dDoubleValue);
    }

    public static final Double j(Iterable iterable) {
        Iterator it = iterable.iterator();
        if (!it.hasNext()) {
            return null;
        }
        double dDoubleValue = ((Number) it.next()).doubleValue();
        while (it.hasNext()) {
            double dDoubleValue2 = ((Number) it.next()).doubleValue();
            if (!Double.isNaN(dDoubleValue2) && dDoubleValue > dDoubleValue2) {
                dDoubleValue = dDoubleValue2;
            }
        }
        return Double.valueOf(dDoubleValue);
    }

    public static final List k(List list) {
        int iP = Sf.r.p(list);
        if (iP >= 0) {
            int i10 = 0;
            while (true) {
                List list2 = (List) list.get(Sf.r.p(list) - i10);
                if (list2 != null && !list2.isEmpty()) {
                    return list2;
                }
                if (i10 != iP) {
                    i10++;
                }
            }
        }
        throw new NoSuchElementException("List is empty.");
    }

    public static final List l(List list, boolean z10) {
        ArrayList arrayList = new ArrayList();
        if (!z10) {
            ArrayList arrayList2 = new ArrayList();
            for (Object obj : list) {
                if (!Double.isNaN(((Number) obj).doubleValue())) {
                    arrayList2.add(obj);
                }
            }
            return Sf.z.u1(arrayList2);
        }
        Iterator it = list.iterator();
        boolean z11 = false;
        while (it.hasNext()) {
            double dDoubleValue = ((Number) it.next()).doubleValue();
            if (!Double.isNaN(dDoubleValue) || z11) {
                arrayList.add(Double.valueOf(dDoubleValue));
                z11 = true;
            }
        }
        return arrayList;
    }

    public static /* synthetic */ List m(List list, boolean z10, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            z10 = true;
        }
        return l(list, z10);
    }
}
