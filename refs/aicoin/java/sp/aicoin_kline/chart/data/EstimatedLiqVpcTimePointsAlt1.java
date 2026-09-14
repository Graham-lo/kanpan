package sp.aicoin_kline.chart.data;

import Sf.AbstractC2804s;
import Sf.AbstractC2808w;
import Sf.r;
import Sf.z;
import androidx.annotation.Keep;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.umeng.analytics.pro.am;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import kk.d;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000>\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\u0010 \n\u0002\u0010\u000e\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0010$\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0010\u000b\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u000b\n\u0002\u0010\b\n\u0002\b\u000e\b\u0087\b\u0018\u0000 (2\u00020\u0001:\u0001)B%\u0012\f\u0010\u0004\u001a\b\u0012\u0004\u0012\u00020\u00030\u0002\u0012\u0006\u0010\u0005\u001a\u00020\u0003\u0012\u0006\u0010\u0007\u001a\u00020\u0006¢\u0006\u0004\b\b\u0010\tJ\u001f\u0010\f\u001a\u0014\u0012\u0004\u0012\u00020\u0003\u0012\n\u0012\b\u0012\u0004\u0012\u00020\u000b0\u00020\n¢\u0006\u0004\b\f\u0010\rJ\u001d\u0010\u0011\u001a\b\u0012\u0004\u0012\u00020\u00100\u00022\b\b\u0002\u0010\u000f\u001a\u00020\u000e¢\u0006\u0004\b\u0011\u0010\u0012J\u0016\u0010\u0013\u001a\b\u0012\u0004\u0012\u00020\u00030\u0002HÆ\u0003¢\u0006\u0004\b\u0013\u0010\u0014J\u0010\u0010\u0015\u001a\u00020\u0003HÆ\u0003¢\u0006\u0004\b\u0015\u0010\u0016J\u0010\u0010\u0017\u001a\u00020\u0006HÆ\u0003¢\u0006\u0004\b\u0017\u0010\u0018J4\u0010\u0019\u001a\u00020\u00002\u000e\b\u0002\u0010\u0004\u001a\b\u0012\u0004\u0012\u00020\u00030\u00022\b\b\u0002\u0010\u0005\u001a\u00020\u00032\b\b\u0002\u0010\u0007\u001a\u00020\u0006HÆ\u0001¢\u0006\u0004\b\u0019\u0010\u001aJ\u0010\u0010\u001b\u001a\u00020\u0003HÖ\u0001¢\u0006\u0004\b\u001b\u0010\u0016J\u0010\u0010\u001d\u001a\u00020\u001cHÖ\u0001¢\u0006\u0004\b\u001d\u0010\u001eJ\u001a\u0010 \u001a\u00020\u000e2\b\u0010\u001f\u001a\u0004\u0018\u00010\u0001HÖ\u0003¢\u0006\u0004\b \u0010!R\u001d\u0010\u0004\u001a\b\u0012\u0004\u0012\u00020\u00030\u00028\u0006¢\u0006\f\n\u0004\b\u0004\u0010\"\u001a\u0004\b#\u0010\u0014R\u0017\u0010\u0005\u001a\u00020\u00038\u0006¢\u0006\f\n\u0004\b\u0005\u0010$\u001a\u0004\b%\u0010\u0016R\u0017\u0010\u0007\u001a\u00020\u00068\u0006¢\u0006\f\n\u0004\b\u0007\u0010&\u001a\u0004\b'\u0010\u0018¨\u0006*"}, d2 = {"Lsp/aicoin_kline/chart/data/EstimatedLiqVpcTimePointsAlt1;", "", "", "", "columns", "name", "Lcom/google/gson/JsonObject;", "values", "<init>", "(Ljava/util/List;Ljava/lang/String;Lcom/google/gson/JsonObject;)V", "", "Lsp/aicoin_kline/chart/data/EstimatedLiqVpcRecord;", "parseValues", "()Ljava/util/Map;", "", "useLatestOnly", "Lsp/aicoin_kline/chart/data/LiQuiLineItem;", "toLiQuiLineItems", "(Z)Ljava/util/List;", "component1", "()Ljava/util/List;", "component2", "()Ljava/lang/String;", "component3", "()Lcom/google/gson/JsonObject;", "copy", "(Ljava/util/List;Ljava/lang/String;Lcom/google/gson/JsonObject;)Lsp/aicoin_kline/chart/data/EstimatedLiqVpcTimePointsAlt1;", "toString", "", "hashCode", "()I", "other", "equals", "(Ljava/lang/Object;)Z", "Ljava/util/List;", "getColumns", "Ljava/lang/String;", "getName", "Lcom/google/gson/JsonObject;", "getValues", "Companion", am.av, "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class EstimatedLiqVpcTimePointsAlt1 {

    /* JADX INFO: renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private final List<String> columns;
    private final String name;
    private final JsonObject values;

    /* JADX INFO: renamed from: sp.aicoin_kline.chart.data.EstimatedLiqVpcTimePointsAlt1$a, reason: from kotlin metadata */
    public static final class Companion {
        public Companion(DefaultConstructorMarker defaultConstructorMarker) {
        }

        /* JADX WARN: Code duplicated, block: B:15:0x0088  */
        public final Map a(JsonObject jsonObject) {
            EstimatedLiqVpcRecord estimatedLiqVpcRecord;
            LinkedHashMap linkedHashMap = new LinkedHashMap();
            Iterator<T> it = jsonObject.entrySet().iterator();
            while (it.hasNext()) {
                Map.Entry entry = (Map.Entry) it.next();
                String str = (String) entry.getKey();
                JsonElement jsonElement = (JsonElement) entry.getValue();
                if (jsonElement.isJsonArray()) {
                    JsonArray asJsonArray = jsonElement.getAsJsonArray();
                    ArrayList arrayList = new ArrayList();
                    for (JsonElement jsonElement2 : asJsonArray) {
                        if (jsonElement2.isJsonArray()) {
                            JsonArray asJsonArray2 = jsonElement2.getAsJsonArray();
                            if (asJsonArray2.size() >= 5) {
                                estimatedLiqVpcRecord = new EstimatedLiqVpcRecord(asJsonArray2.get(0).getAsString(), asJsonArray2.get(1).getAsString(), asJsonArray2.get(2).getAsDouble(), asJsonArray2.get(3).getAsDouble(), asJsonArray2.get(4).getAsDouble());
                            } else {
                                estimatedLiqVpcRecord = null;
                            }
                        } else {
                            estimatedLiqVpcRecord = null;
                        }
                        if (estimatedLiqVpcRecord != null) {
                            arrayList.add(estimatedLiqVpcRecord);
                        }
                    }
                    linkedHashMap.put(str, arrayList);
                }
            }
            return linkedHashMap;
        }
    }

    public EstimatedLiqVpcTimePointsAlt1(List<String> list, String str, JsonObject jsonObject) {
        this.columns = list;
        this.name = str;
        this.values = jsonObject;
    }

    /* JADX WARN: Multi-variable type inference failed */
    public static /* synthetic */ EstimatedLiqVpcTimePointsAlt1 copy$default(EstimatedLiqVpcTimePointsAlt1 estimatedLiqVpcTimePointsAlt1, List list, String str, JsonObject jsonObject, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            list = estimatedLiqVpcTimePointsAlt1.columns;
        }
        if ((i10 & 2) != 0) {
            str = estimatedLiqVpcTimePointsAlt1.name;
        }
        if ((i10 & 4) != 0) {
            jsonObject = estimatedLiqVpcTimePointsAlt1.values;
        }
        return estimatedLiqVpcTimePointsAlt1.copy(list, str, jsonObject);
    }

    public static /* synthetic */ List toLiQuiLineItems$default(EstimatedLiqVpcTimePointsAlt1 estimatedLiqVpcTimePointsAlt1, boolean z10, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            z10 = true;
        }
        return estimatedLiqVpcTimePointsAlt1.toLiQuiLineItems(z10);
    }

    public final List<String> component1() {
        return this.columns;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getName() {
        return this.name;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final JsonObject getValues() {
        return this.values;
    }

    public final EstimatedLiqVpcTimePointsAlt1 copy(List<String> columns, String name, JsonObject values) {
        return new EstimatedLiqVpcTimePointsAlt1(columns, name, values);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof EstimatedLiqVpcTimePointsAlt1)) {
            return false;
        }
        EstimatedLiqVpcTimePointsAlt1 estimatedLiqVpcTimePointsAlt1 = (EstimatedLiqVpcTimePointsAlt1) other;
        return AbstractC7609s.f(this.columns, estimatedLiqVpcTimePointsAlt1.columns) && AbstractC7609s.f(this.name, estimatedLiqVpcTimePointsAlt1.name) && AbstractC7609s.f(this.values, estimatedLiqVpcTimePointsAlt1.values);
    }

    public final List<String> getColumns() {
        return this.columns;
    }

    public final String getName() {
        return this.name;
    }

    public final JsonObject getValues() {
        return this.values;
    }

    public int hashCode() {
        return this.values.hashCode() + d.a(this.name, this.columns.hashCode() * 31, 31);
    }

    public final Map<String, List<EstimatedLiqVpcRecord>> parseValues() {
        return INSTANCE.a(this.values);
    }

    public final List<LiQuiLineItem> toLiQuiLineItems(boolean useLatestOnly) {
        List<EstimatedLiqVpcRecord> listA;
        Map<String, List<EstimatedLiqVpcRecord>> values = parseValues();
        if (!useLatestOnly || values.isEmpty()) {
            listA = AbstractC2804s.A(values.values());
        } else {
            String str = (String) z.I0(values.keySet());
            if (str == null) {
                return r.n();
            }
            listA = values.get(str);
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
        return "EstimatedLiqVpcTimePointsAlt1(columns=" + this.columns + ", name=" + this.name + ", values=" + this.values + ')';
    }
}
