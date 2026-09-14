package sp.aicoin_kline.chart.data;

import Sf.AbstractC2804s;
import Sf.AbstractC2808w;
import Sf.r;
import Sf.z;
import androidx.annotation.Keep;
import com.umeng.analytics.pro.am;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import kk.d;
import kotlin.Metadata;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u00006\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\u0010 \n\u0002\u0010\u000e\n\u0002\b\u0002\n\u0002\u0010$\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0010\u000b\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u000b\n\u0002\u0010\b\n\u0002\b\u000e\b\u0087\b\u0018\u0000 %2\u00020\u0001:\u0001&B7\u0012\f\u0010\u0004\u001a\b\u0012\u0004\u0012\u00020\u00030\u0002\u0012\u0006\u0010\u0005\u001a\u00020\u0003\u0012\u0018\u0010\b\u001a\u0014\u0012\u0004\u0012\u00020\u0003\u0012\n\u0012\b\u0012\u0004\u0012\u00020\u00070\u00020\u0006¢\u0006\u0004\b\t\u0010\nJ\u001d\u0010\u000e\u001a\b\u0012\u0004\u0012\u00020\r0\u00022\b\b\u0002\u0010\f\u001a\u00020\u000b¢\u0006\u0004\b\u000e\u0010\u000fJ\u0016\u0010\u0010\u001a\b\u0012\u0004\u0012\u00020\u00030\u0002HÆ\u0003¢\u0006\u0004\b\u0010\u0010\u0011J\u0010\u0010\u0012\u001a\u00020\u0003HÆ\u0003¢\u0006\u0004\b\u0012\u0010\u0013J\"\u0010\u0014\u001a\u0014\u0012\u0004\u0012\u00020\u0003\u0012\n\u0012\b\u0012\u0004\u0012\u00020\u00070\u00020\u0006HÆ\u0003¢\u0006\u0004\b\u0014\u0010\u0015JF\u0010\u0016\u001a\u00020\u00002\u000e\b\u0002\u0010\u0004\u001a\b\u0012\u0004\u0012\u00020\u00030\u00022\b\b\u0002\u0010\u0005\u001a\u00020\u00032\u001a\b\u0002\u0010\b\u001a\u0014\u0012\u0004\u0012\u00020\u0003\u0012\n\u0012\b\u0012\u0004\u0012\u00020\u00070\u00020\u0006HÆ\u0001¢\u0006\u0004\b\u0016\u0010\u0017J\u0010\u0010\u0018\u001a\u00020\u0003HÖ\u0001¢\u0006\u0004\b\u0018\u0010\u0013J\u0010\u0010\u001a\u001a\u00020\u0019HÖ\u0001¢\u0006\u0004\b\u001a\u0010\u001bJ\u001a\u0010\u001d\u001a\u00020\u000b2\b\u0010\u001c\u001a\u0004\u0018\u00010\u0001HÖ\u0003¢\u0006\u0004\b\u001d\u0010\u001eR\u001d\u0010\u0004\u001a\b\u0012\u0004\u0012\u00020\u00030\u00028\u0006¢\u0006\f\n\u0004\b\u0004\u0010\u001f\u001a\u0004\b \u0010\u0011R\u0017\u0010\u0005\u001a\u00020\u00038\u0006¢\u0006\f\n\u0004\b\u0005\u0010!\u001a\u0004\b\"\u0010\u0013R)\u0010\b\u001a\u0014\u0012\u0004\u0012\u00020\u0003\u0012\n\u0012\b\u0012\u0004\u0012\u00020\u00070\u00020\u00068\u0006¢\u0006\f\n\u0004\b\b\u0010#\u001a\u0004\b$\u0010\u0015¨\u0006'"}, d2 = {"Lsp/aicoin_kline/chart/data/EstimatedLiqVpcTimePointsAlt2;", "", "", "", "columns", "name", "", "Lsp/aicoin_kline/chart/data/EstimatedLiqVpcRecord;", "values", "<init>", "(Ljava/util/List;Ljava/lang/String;Ljava/util/Map;)V", "", "useLatestOnly", "Lsp/aicoin_kline/chart/data/LiQuiLineItem;", "toLiQuiLineItems", "(Z)Ljava/util/List;", "component1", "()Ljava/util/List;", "component2", "()Ljava/lang/String;", "component3", "()Ljava/util/Map;", "copy", "(Ljava/util/List;Ljava/lang/String;Ljava/util/Map;)Lsp/aicoin_kline/chart/data/EstimatedLiqVpcTimePointsAlt2;", "toString", "", "hashCode", "()I", "other", "equals", "(Ljava/lang/Object;)Z", "Ljava/util/List;", "getColumns", "Ljava/lang/String;", "getName", "Ljava/util/Map;", "getValues", "Companion", am.av, "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class EstimatedLiqVpcTimePointsAlt2 {
    private final List<String> columns;
    private final String name;
    private final Map<String, List<EstimatedLiqVpcRecord>> values;

    /* JADX WARN: Multi-variable type inference failed */
    public EstimatedLiqVpcTimePointsAlt2(List<String> list, String str, Map<String, ? extends List<EstimatedLiqVpcRecord>> map) {
        this.columns = list;
        this.name = str;
        this.values = map;
    }

    /* JADX WARN: Multi-variable type inference failed */
    public static /* synthetic */ EstimatedLiqVpcTimePointsAlt2 copy$default(EstimatedLiqVpcTimePointsAlt2 estimatedLiqVpcTimePointsAlt2, List list, String str, Map map, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            list = estimatedLiqVpcTimePointsAlt2.columns;
        }
        if ((i10 & 2) != 0) {
            str = estimatedLiqVpcTimePointsAlt2.name;
        }
        if ((i10 & 4) != 0) {
            map = estimatedLiqVpcTimePointsAlt2.values;
        }
        return estimatedLiqVpcTimePointsAlt2.copy(list, str, map);
    }

    public static /* synthetic */ List toLiQuiLineItems$default(EstimatedLiqVpcTimePointsAlt2 estimatedLiqVpcTimePointsAlt2, boolean z10, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            z10 = true;
        }
        return estimatedLiqVpcTimePointsAlt2.toLiQuiLineItems(z10);
    }

    public final List<String> component1() {
        return this.columns;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getName() {
        return this.name;
    }

    public final Map<String, List<EstimatedLiqVpcRecord>> component3() {
        return this.values;
    }

    public final EstimatedLiqVpcTimePointsAlt2 copy(List<String> columns, String name, Map<String, ? extends List<EstimatedLiqVpcRecord>> values) {
        return new EstimatedLiqVpcTimePointsAlt2(columns, name, values);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof EstimatedLiqVpcTimePointsAlt2)) {
            return false;
        }
        EstimatedLiqVpcTimePointsAlt2 estimatedLiqVpcTimePointsAlt2 = (EstimatedLiqVpcTimePointsAlt2) other;
        return AbstractC7609s.f(this.columns, estimatedLiqVpcTimePointsAlt2.columns) && AbstractC7609s.f(this.name, estimatedLiqVpcTimePointsAlt2.name) && AbstractC7609s.f(this.values, estimatedLiqVpcTimePointsAlt2.values);
    }

    public final List<String> getColumns() {
        return this.columns;
    }

    public final String getName() {
        return this.name;
    }

    public final Map<String, List<EstimatedLiqVpcRecord>> getValues() {
        return this.values;
    }

    public int hashCode() {
        return this.values.hashCode() + d.a(this.name, this.columns.hashCode() * 31, 31);
    }

    public final List<LiQuiLineItem> toLiQuiLineItems(boolean useLatestOnly) {
        List<EstimatedLiqVpcRecord> listA;
        if (!useLatestOnly || this.values.isEmpty()) {
            listA = AbstractC2804s.A(this.values.values());
        } else {
            String str = (String) z.I0(this.values.keySet());
            if (str == null) {
                return r.n();
            }
            listA = this.values.get(str);
            if (listA == null) {
                listA = r.n();
            }
        }
        ArrayList arrayList = new ArrayList();
        for (EstimatedLiqVpcRecord estimatedLiqVpcRecord : listA) {
            AbstractC2808w.D(arrayList, r.q(Double.valueOf(estimatedLiqVpcRecord.getFromPrice()), Double.valueOf(estimatedLiqVpcRecord.getToPrice())));
        }
        List listB1 = z.b1(z.h0(arrayList));
        ArrayList arrayList2 = new ArrayList(AbstractC2804s.y(listB1, 10));
        Iterator it = listB1.iterator();
        while (it.hasNext()) {
            arrayList2.add(new LiQuiLineItem(String.valueOf(((Number) it.next()).doubleValue())));
        }
        return arrayList2;
    }

    public String toString() {
        return "EstimatedLiqVpcTimePointsAlt2(columns=" + this.columns + ", name=" + this.name + ", values=" + this.values + ')';
    }
}
