package fk;

import com.davemorrissey.labs.subscaleview.SubsamplingScaleImageView;
import java.util.ArrayList;
import java.util.IdentityHashMap;
import java.util.Iterator;
import java.util.List;
import java.util.TreeMap;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.chart.data.LargeOrderItem;

/* JADX INFO: loaded from: classes7.dex */
public final class I {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public List f95070a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public long f95071b = Long.MIN_VALUE;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public long f95072c = Long.MIN_VALUE;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public final ArrayList f95073d = new ArrayList();

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public final IdentityHashMap f95074e = new IdentityHashMap();

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public final IdentityHashMap f95075f = new IdentityHashMap();

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public final TreeMap f95076g = new TreeMap();

    /* JADX INFO: renamed from: h, reason: collision with root package name */
    public final TreeMap f95077h = new TreeMap();

    public static final int a(I i10, int i11, LargeOrderItem largeOrderItem) {
        Integer num = (Integer) i10.f95075f.get(largeOrderItem);
        return AbstractC7609s.g(num != null ? num.intValue() : SubsamplingScaleImageView.TILE_SIZE_AUTO, i11);
    }

    public final void b(LargeOrderItem largeOrderItem, int i10, long j10, long j11) {
        this.f95075f.put(largeOrderItem, Integer.valueOf(i10));
        Long draw_start_time = largeOrderItem.getDraw_start_time();
        long jLongValue = draw_start_time != null ? draw_start_time.longValue() : 0L;
        Long draw_miss_time = largeOrderItem.getDraw_miss_time();
        long jLongValue2 = draw_miss_time != null ? draw_miss_time.longValue() : 0L;
        TreeMap treeMap = this.f95076g;
        Long lValueOf = Long.valueOf(jLongValue);
        Object arrayList = treeMap.get(lValueOf);
        if (arrayList == null) {
            arrayList = new ArrayList();
            treeMap.put(lValueOf, arrayList);
        }
        ((List) arrayList).add(largeOrderItem);
        if (jLongValue2 != 0) {
            TreeMap treeMap2 = this.f95077h;
            Long lValueOf2 = Long.valueOf(jLongValue2);
            Object arrayList2 = treeMap2.get(lValueOf2);
            if (arrayList2 == null) {
                arrayList2 = new ArrayList();
                treeMap2.put(lValueOf2, arrayList2);
            }
            ((List) arrayList2).add(largeOrderItem);
        }
        if (AbstractC7378c.b(jLongValue, jLongValue2, j10, j11)) {
            this.f95074e.put(largeOrderItem, Boolean.TRUE);
            this.f95073d.add(largeOrderItem);
        }
    }

    public final void c(LargeOrderItem largeOrderItem, long j10, long j11) {
        if (this.f95074e.containsKey(largeOrderItem)) {
            return;
        }
        Long draw_start_time = largeOrderItem.getDraw_start_time();
        long jLongValue = draw_start_time != null ? draw_start_time.longValue() : 0L;
        Long draw_miss_time = largeOrderItem.getDraw_miss_time();
        if (AbstractC7378c.b(jLongValue, draw_miss_time != null ? draw_miss_time.longValue() : 0L, j10, j11)) {
            Integer num = (Integer) this.f95075f.get(largeOrderItem);
            int iL = Sf.r.l(this.f95073d, 0, 0, new H(this, num != null ? num.intValue() : SubsamplingScaleImageView.TILE_SIZE_AUTO), 3, null);
            if (iL < 0) {
                iL = (-iL) - 1;
            }
            this.f95073d.add(iL, largeOrderItem);
            this.f95074e.put(largeOrderItem, Boolean.TRUE);
        }
    }

    public final List d(List list, long j10, long j11) {
        long j12;
        long j13;
        int i10;
        long j14 = j10;
        long j15 = j11;
        List list2 = this.f95070a;
        if (list2 != list) {
            if ((list2 instanceof Rj.W) && (list instanceof Rj.W)) {
                Rj.W w10 = (Rj.W) list2;
                Rj.W w11 = (Rj.W) list;
                if (w10.o() == w11.o()) {
                    for (LargeOrderItem largeOrderItem : w10.q()) {
                        this.f95075f.remove(largeOrderItem);
                        this.f95074e.remove(largeOrderItem);
                        ArrayList arrayList = this.f95073d;
                        Iterator it = arrayList.iterator();
                        int i11 = 0;
                        while (true) {
                            if (!it.hasNext()) {
                                i11 = -1;
                                break;
                            }
                            if (((LargeOrderItem) it.next()) == largeOrderItem) {
                                break;
                            }
                            i11++;
                        }
                        if (i11 >= 0) {
                            arrayList.remove(i11);
                        }
                        TreeMap treeMap = this.f95076g;
                        Long draw_start_time = largeOrderItem.getDraw_start_time();
                        long jLongValue = draw_start_time != null ? draw_start_time.longValue() : 0L;
                        List list3 = (List) treeMap.get(Long.valueOf(jLongValue));
                        if (list3 == null) {
                            j13 = 0;
                        } else {
                            Iterator it2 = list3.iterator();
                            int i12 = 0;
                            while (true) {
                                if (!it2.hasNext()) {
                                    j13 = 0;
                                    i10 = -1;
                                    break;
                                }
                                j13 = 0;
                                if (((LargeOrderItem) it2.next()) == largeOrderItem) {
                                    i10 = i12;
                                    break;
                                }
                                i12++;
                            }
                            if (i10 >= 0) {
                                list3.remove(i10);
                            }
                            if (list3.isEmpty()) {
                                treeMap.remove(Long.valueOf(jLongValue));
                            }
                        }
                        Long draw_miss_time = largeOrderItem.getDraw_miss_time();
                        long jLongValue2 = draw_miss_time != null ? draw_miss_time.longValue() : j13;
                        if (jLongValue2 != j13) {
                            TreeMap treeMap2 = this.f95077h;
                            List list4 = (List) treeMap2.get(Long.valueOf(jLongValue2));
                            if (list4 != null) {
                                Iterator it3 = list4.iterator();
                                int i13 = 0;
                                while (true) {
                                    if (!it3.hasNext()) {
                                        i13 = -1;
                                        break;
                                    }
                                    if (((LargeOrderItem) it3.next()) == largeOrderItem) {
                                        break;
                                    }
                                    i13++;
                                }
                                if (i13 >= 0) {
                                    list4.remove(i13);
                                }
                                if (list4.isEmpty()) {
                                    treeMap2.remove(Long.valueOf(jLongValue2));
                                }
                            }
                        }
                    }
                    j12 = 0;
                    int i14 = 0;
                    for (Object obj : w11.q()) {
                        int i15 = i14 + 1;
                        if (i14 < 0) {
                            Sf.r.x();
                        }
                        b((LargeOrderItem) obj, w11.o().size() + i14, this.f95071b, this.f95072c);
                        i14 = i15;
                    }
                    this.f95070a = w11;
                }
            }
            this.f95070a = list;
            this.f95071b = j14;
            this.f95072c = j15;
            this.f95073d.clear();
            this.f95074e.clear();
            this.f95075f.clear();
            this.f95076g.clear();
            this.f95077h.clear();
            int i16 = 0;
            for (Object obj2 : list) {
                int i17 = i16 + 1;
                if (i16 < 0) {
                    Sf.r.x();
                }
                b((LargeOrderItem) obj2, i16, j14, j15);
                j14 = j10;
                j15 = j11;
                i16 = i17;
            }
            return this.f95073d;
        }
        j12 = 0;
        if (this.f95071b == j10 && this.f95072c == j11) {
            return this.f95073d;
        }
        for (int iP = Sf.r.p(this.f95073d); -1 < iP; iP--) {
            LargeOrderItem largeOrderItem2 = (LargeOrderItem) this.f95073d.get(iP);
            Long draw_start_time2 = largeOrderItem2.getDraw_start_time();
            long jLongValue3 = draw_start_time2 != null ? draw_start_time2.longValue() : j12;
            Long draw_miss_time2 = largeOrderItem2.getDraw_miss_time();
            if (!AbstractC7378c.b(jLongValue3, draw_miss_time2 != null ? draw_miss_time2.longValue() : j12, j10, j11)) {
                this.f95073d.remove(iP);
                this.f95074e.remove(largeOrderItem2);
            }
        }
        long j16 = this.f95072c;
        if (j11 > j16) {
            Iterator it4 = this.f95076g.subMap(Long.valueOf(j16), false, Long.valueOf(j11), true).values().iterator();
            while (it4.hasNext()) {
                Iterator it5 = ((List) it4.next()).iterator();
                while (it5.hasNext()) {
                    c((LargeOrderItem) it5.next(), j10, j11);
                }
            }
        }
        if (j10 < this.f95071b) {
            Iterator it6 = this.f95077h.subMap(Long.valueOf(j10), true, Long.valueOf(this.f95071b), false).values().iterator();
            while (it6.hasNext()) {
                Iterator it7 = ((List) it6.next()).iterator();
                while (it7.hasNext()) {
                    c((LargeOrderItem) it7.next(), j10, j11);
                }
            }
        }
        this.f95071b = j10;
        this.f95072c = j11;
        return this.f95073d;
    }
}
