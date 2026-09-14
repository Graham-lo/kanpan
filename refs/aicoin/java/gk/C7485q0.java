package gk;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import kotlin.jvm.functions.Function1;
import sp.aicoin_kline.chart.data.LargeOrderItem;

/* JADX INFO: renamed from: gk.q0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7485q0 {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public List f96546a = Sf.r.n();

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public List f96547b = Sf.r.n();

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final HashMap f96548c = new HashMap();

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public final HashMap f96549d = new HashMap();

    public static void a(List list, HashMap map) {
        map.clear();
        int i10 = 0;
        for (Object obj : list) {
            int i11 = i10 + 1;
            if (i10 < 0) {
                Sf.r.x();
            }
            Qf.p pVarB = AbstractC7470j.b((LargeOrderItem) obj);
            if (pVarB != null) {
                map.putIfAbsent(pVarB, Integer.valueOf(i10));
            }
            i10 = i11;
        }
    }

    public static void b(List list, HashMap map, LargeOrderItem largeOrderItem) {
        Qf.p pVarB = AbstractC7470j.b(largeOrderItem);
        Integer num = pVarB != null ? (Integer) map.get(pVarB) : null;
        if (num != null) {
            list.set(num.intValue(), largeOrderItem);
            return;
        }
        list.add(largeOrderItem);
        if (pVarB != null) {
            map.put(pVarB, Integer.valueOf(Sf.r.p(list)));
        }
    }

    public final void c() {
        this.f96546a = Sf.r.n();
        this.f96547b = Sf.r.n();
        this.f96548c.clear();
        this.f96549d.clear();
    }

    public final void d(List list, Function1 function1) {
        p167hg.M m10 = new p167hg.M();
        p167hg.M m11 = new p167hg.M();
        Iterator it = list.iterator();
        while (it.hasNext()) {
            LargeOrderItem largeOrderItem = (LargeOrderItem) it.next();
            Qf.p pVarB = AbstractC7470j.b(largeOrderItem);
            if (AbstractC7470j.f(largeOrderItem)) {
                function1.invoke(largeOrderItem);
                if (AbstractC7470j.a(largeOrderItem)) {
                    if (pVarB != null && this.f96548c.containsKey(pVarB)) {
                        List listU1 = (List) m10.f97909a;
                        if (listU1 == null) {
                            listU1 = Sf.z.u1(this.f96546a);
                            m10.f97909a = listU1;
                        }
                        HashMap map = this.f96548c;
                        Integer num = (Integer) map.get(pVarB);
                        if (num != null) {
                            listU1.remove(num.intValue());
                            a(listU1, map);
                        }
                    }
                    List listU2 = (List) m11.f97909a;
                    if (listU2 == null) {
                        listU2 = Sf.z.u1(this.f96547b);
                        m11.f97909a = listU2;
                    }
                    b(listU2, this.f96549d, largeOrderItem);
                } else {
                    if (pVarB != null && this.f96549d.containsKey(pVarB)) {
                        List listU3 = (List) m11.f97909a;
                        if (listU3 == null) {
                            listU3 = Sf.z.u1(this.f96547b);
                            m11.f97909a = listU3;
                        }
                        HashMap map2 = this.f96549d;
                        Integer num2 = (Integer) map2.get(pVarB);
                        if (num2 != null) {
                            listU3.remove(num2.intValue());
                            a(listU3, map2);
                        }
                    }
                    List listU4 = (List) m10.f97909a;
                    if (listU4 == null) {
                        listU4 = Sf.z.u1(this.f96546a);
                        m10.f97909a = listU4;
                    }
                    b(listU4, this.f96548c, largeOrderItem);
                }
            } else {
                if (pVarB != null && this.f96548c.containsKey(pVarB)) {
                    List listU5 = (List) m10.f97909a;
                    if (listU5 == null) {
                        listU5 = Sf.z.u1(this.f96546a);
                        m10.f97909a = listU5;
                    }
                    HashMap map3 = this.f96548c;
                    Integer num3 = (Integer) map3.get(pVarB);
                    if (num3 != null) {
                        listU5.remove(num3.intValue());
                        a(listU5, map3);
                    }
                }
                if (pVarB != null && this.f96549d.containsKey(pVarB)) {
                    List listU6 = (List) m11.f97909a;
                    if (listU6 == null) {
                        listU6 = Sf.z.u1(this.f96547b);
                        m11.f97909a = listU6;
                    }
                    HashMap map4 = this.f96549d;
                    Integer num4 = (Integer) map4.get(pVarB);
                    if (num4 != null) {
                        listU6.remove(num4.intValue());
                        a(listU6, map4);
                    }
                }
            }
        }
        List list2 = (List) m10.f97909a;
        if (list2 != null) {
            this.f96546a = list2;
        }
        List list3 = (List) m11.f97909a;
        if (list3 != null) {
            this.f96547b = list3;
        }
    }

    public final void e(List list, Function1 function1) {
        c();
        ArrayList arrayList = new ArrayList();
        ArrayList arrayList2 = new ArrayList();
        Iterator it = list.iterator();
        while (it.hasNext()) {
            LargeOrderItem largeOrderItem = (LargeOrderItem) it.next();
            if (AbstractC7470j.f(largeOrderItem)) {
                function1.invoke(largeOrderItem);
                if (AbstractC7470j.a(largeOrderItem)) {
                    arrayList2.add(largeOrderItem);
                } else {
                    arrayList.add(largeOrderItem);
                }
            }
        }
        this.f96546a = arrayList;
        this.f96547b = arrayList2;
        a(arrayList, this.f96548c);
        a(this.f96547b, this.f96549d);
    }

    public final void f(List list, Function1 function1) {
        ArrayList<LargeOrderItem> arrayList = new ArrayList();
        for (Object obj : list) {
            if (AbstractC7470j.f((LargeOrderItem) obj)) {
                arrayList.add(obj);
            }
        }
        HashSet hashSet = new HashSet();
        Iterator it = arrayList.iterator();
        while (it.hasNext()) {
            Qf.p pVarB = AbstractC7470j.b((LargeOrderItem) it.next());
            if (pVarB != null) {
                hashSet.add(pVarB);
            }
        }
        HashMap map = this.f96548c;
        if (!hashSet.isEmpty()) {
            Iterator it2 = hashSet.iterator();
            while (it2.hasNext()) {
                if (map.containsKey((Qf.p) it2.next())) {
                    List list2 = this.f96546a;
                    ArrayList arrayList2 = new ArrayList();
                    for (Object obj2 : list2) {
                        if (!Sf.z.g0(hashSet, AbstractC7470j.b((LargeOrderItem) obj2))) {
                            arrayList2.add(obj2);
                        }
                    }
                    this.f96546a = arrayList2;
                    a(arrayList2, this.f96548c);
                    break;
                }
            }
        }
        ArrayList arrayList3 = new ArrayList();
        this.f96549d.clear();
        for (LargeOrderItem largeOrderItem : arrayList) {
            function1.invoke(largeOrderItem);
            b(arrayList3, this.f96549d, largeOrderItem);
        }
        this.f96547b = arrayList3;
    }

    public final List g() {
        return new Rj.W(this.f96546a, this.f96547b);
    }
}
