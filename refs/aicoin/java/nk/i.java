package nk;

import Sf.AbstractC2803q;
import Sf.AbstractC2804s;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import p167hg.AbstractC7609s;
import p254m.aicoin.kline.main.MainKlineFragment;

/* JADX INFO: loaded from: classes7.dex */
public final class i {

    public static final class a {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public final double f134212a;

        /* JADX INFO: renamed from: b, reason: collision with root package name */
        public final int f134213b;

        public a(double d10, int i10) {
            this.f134212a = d10;
            this.f134213b = i10;
        }

        public final int a() {
            return this.f134213b;
        }

        public boolean equals(Object obj) {
            if (this == obj) {
                return true;
            }
            if (!(obj instanceof a)) {
                return false;
            }
            a aVar = (a) obj;
            return Double.compare(this.f134212a, aVar.f134212a) == 0 && this.f134213b == aVar.f134213b;
        }

        public int hashCode() {
            return Integer.hashCode(this.f134213b) + (Double.hashCode(this.f134212a) * 31);
        }

        public String toString() {
            return "MaxData(max=" + this.f134212a + ", maxIndex=" + this.f134213b + ')';
        }
    }

    public static final class b {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public final List f134214a;

        /* JADX INFO: renamed from: b, reason: collision with root package name */
        public final List f134215b;

        public b(List list, List list2) {
            this.f134214a = list;
            this.f134215b = list2;
        }

        public final List a() {
            return this.f134215b;
        }

        public boolean equals(Object obj) {
            if (this == obj) {
                return true;
            }
            if (!(obj instanceof b)) {
                return false;
            }
            b bVar = (b) obj;
            return AbstractC7609s.f(this.f134214a, bVar.f134214a) && AbstractC7609s.f(this.f134215b, bVar.f134215b);
        }

        public int hashCode() {
            return this.f134215b.hashCode() + (this.f134214a.hashCode() * 31);
        }

        public String toString() {
            return "PeakValleyIndices(peaks=" + this.f134214a + ", valleys=" + this.f134215b + ')';
        }
    }

    public static final class c {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public final int f134216a;

        /* JADX INFO: renamed from: b, reason: collision with root package name */
        public final int f134217b;

        public c(int i10, int i11) {
            this.f134216a = i10;
            this.f134217b = i11;
        }

        public final int a() {
            return this.f134216a;
        }

        public final int b() {
            return this.f134217b;
        }

        public boolean equals(Object obj) {
            if (this == obj) {
                return true;
            }
            if (!(obj instanceof c)) {
                return false;
            }
            c cVar = (c) obj;
            return this.f134216a == cVar.f134216a && this.f134217b == cVar.f134217b;
        }

        public int hashCode() {
            return Integer.hashCode(this.f134217b) + (Integer.hashCode(this.f134216a) * 31);
        }

        public String toString() {
            return "Range(begin=" + this.f134216a + ", end=" + this.f134217b + ')';
        }
    }

    public final List a(List list) {
        List<c> listN;
        ArrayList arrayList = new ArrayList(AbstractC2804s.y(list, 10));
        Iterator it = list.iterator();
        while (it.hasNext()) {
            Map map = (Map) it.next();
            Double d10 = (Double) map.get(MainKlineFragment.KEY_AISRL_ASKS);
            double dDoubleValue = d10 != null ? d10.doubleValue() : 0.0d;
            Double d11 = (Double) map.get(MainKlineFragment.KEY_AISRL_BIDS);
            arrayList.add(Double.valueOf(dDoubleValue + (d11 != null ? d11.doubleValue() : 0.0d)));
        }
        int i10 = 1;
        double d12 = 1;
        double size = ((((double) arrayList.size()) / 3.0d) - d12) / 6.0d;
        double d13 = 2;
        int iCeil = (int) ((Math.ceil(((double) 3) * size) * d13) + d12);
        ArrayList arrayList2 = new ArrayList();
        int i11 = iCeil / 2;
        int i12 = 0;
        double d14 = 0.0d;
        while (i12 < iCeil) {
            int i13 = i12 - i11;
            double dExp = Math.exp(((double) ((-i13) * i13)) / ((d13 * size) * size));
            arrayList2.add(Double.valueOf(dExp));
            d14 += dExp;
            i12++;
            i10 = i10;
        }
        int i14 = i10;
        ArrayList arrayList3 = new ArrayList(AbstractC2804s.y(arrayList2, 10));
        Iterator it2 = arrayList2.iterator();
        while (it2.hasNext()) {
            arrayList3.add(Double.valueOf(((Number) it2.next()).doubleValue() / d14));
        }
        ArrayList arrayList4 = new ArrayList(AbstractC2804s.y(arrayList, 10));
        int i15 = 0;
        for (Object obj : arrayList) {
            int i16 = i15 + 1;
            if (i15 < 0) {
                Sf.r.x();
            }
            ((Number) obj).doubleValue();
            double dDoubleValue2 = 0.0d;
            double dDoubleValue3 = 0.0d;
            for (int i17 = 0; i17 < iCeil; i17++) {
                int i18 = (i15 - i11) + i17;
                if (i18 >= 0 && i18 < arrayList.size()) {
                    dDoubleValue2 = (((Number) arrayList3.get(i17)).doubleValue() * ((Number) arrayList.get(i18)).doubleValue()) + dDoubleValue2;
                    dDoubleValue3 = ((Number) arrayList3.get(i17)).doubleValue() + dDoubleValue3;
                }
            }
            arrayList4.add(Double.valueOf(dDoubleValue2 / dDoubleValue3));
            i15 = i16;
        }
        ArrayList arrayList5 = new ArrayList();
        ArrayList arrayList6 = new ArrayList();
        int size2 = arrayList4.size() - 1;
        int i19 = i14;
        while (i19 < size2) {
            double dDoubleValue4 = ((Number) arrayList4.get(i19)).doubleValue();
            double dDoubleValue5 = ((Number) arrayList4.get(i19 - 1)).doubleValue();
            int i20 = i19 + 1;
            double dDoubleValue6 = ((Number) arrayList4.get(i20)).doubleValue();
            if (dDoubleValue4 > dDoubleValue5 && dDoubleValue4 > dDoubleValue6) {
                arrayList5.add(Integer.valueOf(i19));
            } else if (dDoubleValue4 < dDoubleValue5 && dDoubleValue4 < dDoubleValue6) {
                arrayList6.add(Integer.valueOf(i19));
            }
            i19 = i20;
        }
        List listA = new b(arrayList5, arrayList6).a();
        int size3 = arrayList4.size();
        if (listA.isEmpty()) {
            listN = AbstractC2803q.e(new c(0, size3 - 1));
        } else {
            ArrayList arrayList7 = new ArrayList();
            if (((Number) Sf.z.o0(listA)).intValue() != 0) {
                arrayList7.add(0);
            }
            arrayList7.addAll(listA);
            int i21 = size3 - 1;
            if (((Number) Sf.z.B0(listA)).intValue() != i21) {
                arrayList7.add(Integer.valueOf(i21));
            }
            Iterator it3 = arrayList7.iterator();
            if (it3.hasNext()) {
                ArrayList arrayList8 = new ArrayList();
                Object next = it3.next();
                while (it3.hasNext()) {
                    Object next2 = it3.next();
                    arrayList8.add(new c(((Number) next).intValue(), ((Number) next2).intValue()));
                    next = next2;
                }
                listN = arrayList8;
            } else {
                listN = Sf.r.n();
            }
        }
        ArrayList arrayList9 = new ArrayList(AbstractC2804s.y(listN, 10));
        for (c cVar : listN) {
            int iB = cVar.b();
            double dDoubleValue7 = Double.MIN_VALUE;
            int i22 = -1;
            for (int iA = cVar.a(); iA < iB; iA++) {
                if (((Number) arrayList.get(iA)).doubleValue() > dDoubleValue7) {
                    dDoubleValue7 = ((Number) arrayList.get(iA)).doubleValue();
                    i22 = iA;
                }
            }
            arrayList9.add(new a(dDoubleValue7, i22));
        }
        return arrayList9;
    }
}
