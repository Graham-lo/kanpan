package sp.aicoin_kline.chart.data;

import androidx.annotation.Keep;
import java.util.List;
import java.util.Map;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;
import p398sh.aicoin.search.data.remote.SearchRemoteDataSource;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u00002\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010$\n\u0002\u0010\t\n\u0002\u0010 \n\u0002\u0018\u0002\n\u0002\b\u000f\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B7\u0012\u001c\b\u0002\u0010\u0002\u001a\u0016\u0012\u0004\u0012\u00020\u0004\u0012\n\u0012\b\u0012\u0004\u0012\u00020\u00060\u0005\u0018\u00010\u0003\u0012\u0010\b\u0002\u0010\u0007\u001a\n\u0012\u0004\u0012\u00020\u0006\u0018\u00010\u0005¢\u0006\u0004\b\b\u0010\tJ\u001d\u0010\u0012\u001a\u0016\u0012\u0004\u0012\u00020\u0004\u0012\n\u0012\b\u0012\u0004\u0012\u00020\u00060\u0005\u0018\u00010\u0003HÆ\u0003J\u0011\u0010\u0013\u001a\n\u0012\u0004\u0012\u00020\u0006\u0018\u00010\u0005HÆ\u0003J9\u0010\u0014\u001a\u00020\u00002\u001c\b\u0002\u0010\u0002\u001a\u0016\u0012\u0004\u0012\u00020\u0004\u0012\n\u0012\b\u0012\u0004\u0012\u00020\u00060\u0005\u0018\u00010\u00032\u0010\b\u0002\u0010\u0007\u001a\n\u0012\u0004\u0012\u00020\u0006\u0018\u00010\u0005HÆ\u0001J\u0013\u0010\u0015\u001a\u00020\u00162\b\u0010\u0017\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0018\u001a\u00020\u0019HÖ\u0001J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001R.\u0010\u0002\u001a\u0016\u0012\u0004\u0012\u00020\u0004\u0012\n\u0012\b\u0012\u0004\u0012\u00020\u00060\u0005\u0018\u00010\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\n\u0010\u000b\"\u0004\b\f\u0010\rR\"\u0010\u0007\u001a\n\u0012\u0004\u0012\u00020\u0006\u0018\u00010\u0005X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u000e\u0010\u000f\"\u0004\b\u0010\u0010\u0011¨\u0006\u001c"}, d2 = {"Lsp/aicoin_kline/chart/data/LargeOrderMap;", "", "map", "", "", "", "Lsp/aicoin_kline/chart/data/LargeOrderItem;", SearchRemoteDataSource.HTTP_PARSE_KEY_ITEM_LIST, "<init>", "(Ljava/util/Map;Ljava/util/List;)V", "getMap", "()Ljava/util/Map;", "setMap", "(Ljava/util/Map;)V", "getList", "()Ljava/util/List;", "setList", "(Ljava/util/List;)V", "component1", "component2", "copy", "equals", "", "other", "hashCode", "", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class LargeOrderMap {
    private List<LargeOrderItem> list;
    private Map<Long, ? extends List<LargeOrderItem>> map;

    public LargeOrderMap() {
        this(null, null, 3, null);
    }

    public LargeOrderMap(Map<Long, ? extends List<LargeOrderItem>> map, List<LargeOrderItem> list) {
        this.map = map;
        this.list = list;
    }

    public /* synthetic */ LargeOrderMap(Map map, List list, int i10, DefaultConstructorMarker defaultConstructorMarker) {
        this((i10 & 1) != 0 ? null : map, (i10 & 2) != 0 ? null : list);
    }

    /* JADX WARN: Multi-variable type inference failed */
    public static /* synthetic */ LargeOrderMap copy$default(LargeOrderMap largeOrderMap, Map map, List list, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            map = largeOrderMap.map;
        }
        if ((i10 & 2) != 0) {
            list = largeOrderMap.list;
        }
        return largeOrderMap.copy(map, list);
    }

    public final Map<Long, List<LargeOrderItem>> component1() {
        return this.map;
    }

    public final List<LargeOrderItem> component2() {
        return this.list;
    }

    public final LargeOrderMap copy(Map<Long, ? extends List<LargeOrderItem>> map, List<LargeOrderItem> list) {
        return new LargeOrderMap(map, list);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof LargeOrderMap)) {
            return false;
        }
        LargeOrderMap largeOrderMap = (LargeOrderMap) other;
        return AbstractC7609s.f(this.map, largeOrderMap.map) && AbstractC7609s.f(this.list, largeOrderMap.list);
    }

    public final List<LargeOrderItem> getList() {
        return this.list;
    }

    public final Map<Long, List<LargeOrderItem>> getMap() {
        return this.map;
    }

    public int hashCode() {
        Map<Long, ? extends List<LargeOrderItem>> map = this.map;
        int iHashCode = (map == null ? 0 : map.hashCode()) * 31;
        List<LargeOrderItem> list = this.list;
        return iHashCode + (list != null ? list.hashCode() : 0);
    }

    public final void setList(List<LargeOrderItem> list) {
        this.list = list;
    }

    public final void setMap(Map<Long, ? extends List<LargeOrderItem>> map) {
        this.map = map;
    }

    public String toString() {
        return "LargeOrderMap(map=" + this.map + ", list=" + this.list + ')';
    }
}
