package Rj;

import Sf.AbstractC2789c;
import java.util.List;
import sp.aicoin_kline.chart.data.LargeOrderItem;

/* JADX INFO: loaded from: classes7.dex */
public final class W extends AbstractC2789c {

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final List f19266b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final List f19267c;

    public W(List list, List list2) {
        this.f19266b = list;
        this.f19267c = list2;
    }

    @Override // Sf.AbstractC2787a
    public int a() {
        return this.f19267c.size() + this.f19266b.size();
    }

    @Override // Sf.AbstractC2787a, java.util.Collection, java.util.List
    public final /* bridge */ boolean contains(Object obj) {
        if (obj instanceof LargeOrderItem) {
            return d((LargeOrderItem) obj);
        }
        return false;
    }

    public /* bridge */ boolean d(LargeOrderItem largeOrderItem) {
        return super.contains(largeOrderItem);
    }

    @Override // Sf.AbstractC2789c, java.util.List
    /* JADX INFO: renamed from: g, reason: merged with bridge method [inline-methods] */
    public LargeOrderItem get(int i10) {
        return i10 < this.f19266b.size() ? (LargeOrderItem) this.f19266b.get(i10) : (LargeOrderItem) this.f19267c.get(i10 - this.f19266b.size());
    }

    @Override // Sf.AbstractC2789c, java.util.List
    public final /* bridge */ int indexOf(Object obj) {
        if (obj instanceof LargeOrderItem) {
            return s((LargeOrderItem) obj);
        }
        return -1;
    }

    @Override // Sf.AbstractC2789c, java.util.List
    public final /* bridge */ int lastIndexOf(Object obj) {
        if (obj instanceof LargeOrderItem) {
            return t((LargeOrderItem) obj);
        }
        return -1;
    }

    public final List o() {
        return this.f19266b;
    }

    public final List q() {
        return this.f19267c;
    }

    public /* bridge */ int s(LargeOrderItem largeOrderItem) {
        return super.indexOf(largeOrderItem);
    }

    public /* bridge */ int t(LargeOrderItem largeOrderItem) {
        return super.lastIndexOf(largeOrderItem);
    }
}
