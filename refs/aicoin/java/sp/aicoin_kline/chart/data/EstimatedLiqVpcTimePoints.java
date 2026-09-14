package sp.aicoin_kline.chart.data;

import Ah.v;
import Sf.AbstractC2804s;
import Sf.AbstractC2808w;
import Sf.N;
import Sf.r;
import Sf.z;
import androidx.annotation.Keep;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.annotations.SerializedName;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import kk.d;
import kk.h;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000@\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010 \n\u0002\u0010\u000e\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\t\n\u0002\u0010$\n\u0002\u0018\u0002\n\u0002\b\u0005\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000b\n\u0002\b\n\n\u0002\u0010\b\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001B1\u0012\f\u0010\u0002\u001a\b\u0012\u0004\u0012\u00020\u00040\u0003\u0012\u0006\u0010\u0005\u001a\u00020\u0004\u0012\u0006\u0010\u0006\u001a\u00020\u0007\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0004¢\u0006\u0004\b\t\u0010\nJ\u0018\u0010\u0016\u001a\u0014\u0012\u0004\u0012\u00020\u0004\u0012\n\u0012\b\u0012\u0004\u0012\u00020\u00120\u00030\u0011J\u0016\u0010\u0017\u001a\b\u0012\u0004\u0012\u00020\u00180\u00032\b\b\u0002\u0010\u0019\u001a\u00020\u001aJ \u0010\u001b\u001a\u00020\u00002\u0018\u0010\u001c\u001a\u0014\u0012\u0004\u0012\u00020\u0004\u0012\n\u0012\b\u0012\u0004\u0012\u00020\u00120\u00030\u0011J\u000f\u0010\u001d\u001a\b\u0012\u0004\u0012\u00020\u00040\u0003HÆ\u0003J\t\u0010\u001e\u001a\u00020\u0004HÆ\u0003J\t\u0010\u001f\u001a\u00020\u0007HÂ\u0003J\u000b\u0010 \u001a\u0004\u0018\u00010\u0004HÆ\u0003J9\u0010!\u001a\u00020\u00002\u000e\b\u0002\u0010\u0002\u001a\b\u0012\u0004\u0012\u00020\u00040\u00032\b\b\u0002\u0010\u0005\u001a\u00020\u00042\b\b\u0002\u0010\u0006\u001a\u00020\u00072\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0004HÆ\u0001J\u0013\u0010\"\u001a\u00020\u001a2\b\u0010#\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010$\u001a\u00020%HÖ\u0001J\t\u0010&\u001a\u00020\u0004HÖ\u0001R\u0017\u0010\u0002\u001a\b\u0012\u0004\u0012\u00020\u00040\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000b\u0010\fR\u0011\u0010\u0005\u001a\u00020\u0004¢\u0006\b\n\u0000\u001a\u0004\b\r\u0010\u000eR\u0010\u0010\u0006\u001a\u00020\u00078\u0002X\u0083\u0004¢\u0006\u0002\n\u0000R\u0013\u0010\b\u001a\u0004\u0018\u00010\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u000eR\"\u0010\u0010\u001a\u0016\u0012\u0004\u0012\u00020\u0004\u0012\n\u0012\b\u0012\u0004\u0012\u00020\u00120\u0003\u0018\u00010\u0011X\u0082\u000e¢\u0006\u0002\n\u0000R#\u0010\u0013\u001a\u0014\u0012\u0004\u0012\u00020\u0004\u0012\n\u0012\b\u0012\u0004\u0012\u00020\u00120\u00030\u00118F¢\u0006\u0006\u001a\u0004\b\u0014\u0010\u0015¨\u0006'"}, d2 = {"Lsp/aicoin_kline/chart/data/EstimatedLiqVpcTimePoints;", "", "columns", "", "", "name", "_values", "Lcom/google/gson/JsonObject;", "errorMsg", "<init>", "(Ljava/util/List;Ljava/lang/String;Lcom/google/gson/JsonObject;Ljava/lang/String;)V", "getColumns", "()Ljava/util/List;", "getName", "()Ljava/lang/String;", "getErrorMsg", "_parsedValues", "", "Lsp/aicoin_kline/chart/data/EstimatedLiqVpcRecord;", "values", "getValues", "()Ljava/util/Map;", "parseValues", "toLiQuiLineItems", "Lsp/aicoin_kline/chart/data/LiQuiLineItem;", "useLatestOnly", "", "copyWithValues", "newValues", "component1", "component2", "component3", "component4", "copy", "equals", "other", "hashCode", "", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class EstimatedLiqVpcTimePoints {
    private transient Map<String, ? extends List<EstimatedLiqVpcRecord>> _parsedValues;

    @SerializedName("values")
    private final JsonObject _values;
    private final List<String> columns;
    private final String errorMsg;
    private final String name;

    public EstimatedLiqVpcTimePoints(List<String> list, String str, JsonObject jsonObject, String str2) {
        this.columns = list;
        this.name = str;
        this._values = jsonObject;
        this.errorMsg = str2;
    }

    public /* synthetic */ EstimatedLiqVpcTimePoints(List list, String str, JsonObject jsonObject, String str2, int i10, DefaultConstructorMarker defaultConstructorMarker) {
        this(list, str, jsonObject, (i10 & 8) != 0 ? null : str2);
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    private final JsonObject get_values() {
        return this._values;
    }

    /* JADX WARN: Multi-variable type inference failed */
    public static /* synthetic */ EstimatedLiqVpcTimePoints copy$default(EstimatedLiqVpcTimePoints estimatedLiqVpcTimePoints, List list, String str, JsonObject jsonObject, String str2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            list = estimatedLiqVpcTimePoints.columns;
        }
        if ((i10 & 2) != 0) {
            str = estimatedLiqVpcTimePoints.name;
        }
        if ((i10 & 4) != 0) {
            jsonObject = estimatedLiqVpcTimePoints._values;
        }
        if ((i10 & 8) != 0) {
            str2 = estimatedLiqVpcTimePoints.errorMsg;
        }
        return estimatedLiqVpcTimePoints.copy(list, str, jsonObject, str2);
    }

    public static /* synthetic */ List toLiQuiLineItems$default(EstimatedLiqVpcTimePoints estimatedLiqVpcTimePoints, boolean z10, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            z10 = true;
        }
        return estimatedLiqVpcTimePoints.toLiQuiLineItems(z10);
    }

    public final List<String> component1() {
        return this.columns;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getName() {
        return this.name;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final String getErrorMsg() {
        return this.errorMsg;
    }

    public final EstimatedLiqVpcTimePoints copy(List<String> columns, String name, JsonObject _values, String errorMsg) {
        return new EstimatedLiqVpcTimePoints(columns, name, _values, errorMsg);
    }

    public final EstimatedLiqVpcTimePoints copyWithValues(Map<String, ? extends List<EstimatedLiqVpcRecord>> newValues) {
        JsonObject jsonObject = new JsonObject();
        for (Map.Entry<String, ? extends List<EstimatedLiqVpcRecord>> entry : newValues.entrySet()) {
            String key = entry.getKey();
            List<EstimatedLiqVpcRecord> value = entry.getValue();
            JsonArray jsonArray = new JsonArray();
            for (EstimatedLiqVpcRecord estimatedLiqVpcRecord : value) {
                JsonArray jsonArray2 = new JsonArray();
                jsonArray2.add(estimatedLiqVpcRecord.getLeverage());
                jsonArray2.add(estimatedLiqVpcRecord.getDirection());
                jsonArray2.add(Double.valueOf(estimatedLiqVpcRecord.getFromPrice()));
                jsonArray2.add(Double.valueOf(estimatedLiqVpcRecord.getToPrice()));
                jsonArray2.add(Double.valueOf(estimatedLiqVpcRecord.getTurnover()));
                jsonArray.add(jsonArray2);
            }
            jsonObject.add(key, jsonArray);
        }
        return new EstimatedLiqVpcTimePoints(this.columns, this.name, jsonObject, this.errorMsg);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof EstimatedLiqVpcTimePoints)) {
            return false;
        }
        EstimatedLiqVpcTimePoints estimatedLiqVpcTimePoints = (EstimatedLiqVpcTimePoints) other;
        return AbstractC7609s.f(this.columns, estimatedLiqVpcTimePoints.columns) && AbstractC7609s.f(this.name, estimatedLiqVpcTimePoints.name) && AbstractC7609s.f(this._values, estimatedLiqVpcTimePoints._values) && AbstractC7609s.f(this.errorMsg, estimatedLiqVpcTimePoints.errorMsg);
    }

    public final List<String> getColumns() {
        return this.columns;
    }

    public final String getErrorMsg() {
        return this.errorMsg;
    }

    public final String getName() {
        return this.name;
    }

    public final Map<String, List<EstimatedLiqVpcRecord>> getValues() {
        if (this._parsedValues == null) {
            this._parsedValues = parseValues();
        }
        Map map = this._parsedValues;
        return map == null ? N.j() : map;
    }

    public int hashCode() {
        int iHashCode = (this._values.hashCode() + d.a(this.name, this.columns.hashCode() * 31, 31)) * 31;
        String str = this.errorMsg;
        return iHashCode + (str == null ? 0 : str.hashCode());
    }

    /* JADX WARN: Code duplicated, block: B:27:0x0076  */
    /* JADX WARN: Code duplicated, block: B:39:0x0091  */
    /* JADX WARN: Code duplicated, block: B:59:0x00d9  */
    /* JADX WARN: Code duplicated, block: B:79:0x011f  */
    public final Map<String, List<EstimatedLiqVpcRecord>> parseValues() {
        String str;
        String str2;
        double dDoubleValue;
        double dDoubleValue2;
        Double dN;
        double dDoubleValue3;
        Double dN2;
        Double dN3;
        String asString;
        String asString2;
        LinkedHashMap linkedHashMap = new LinkedHashMap();
        Iterator<T> it = this._values.entrySet().iterator();
        while (it.hasNext()) {
            Map.Entry entry = (Map.Entry) it.next();
            String str3 = (String) entry.getKey();
            JsonElement jsonElement = (JsonElement) entry.getValue();
            if (jsonElement.isJsonArray()) {
                JsonArray asJsonArray = jsonElement.getAsJsonArray();
                ArrayList arrayList = new ArrayList();
                for (JsonElement jsonElement2 : asJsonArray) {
                    EstimatedLiqVpcRecord estimatedLiqVpcRecord = null;
                    if (jsonElement2.isJsonArray()) {
                        JsonArray asJsonArray2 = jsonElement2.getAsJsonArray();
                        if (asJsonArray2.size() >= 5) {
                            try {
                                JsonElement jsonElement3 = asJsonArray2.get(0);
                                if (jsonElement3 == null) {
                                    str = "";
                                } else {
                                    if (jsonElement3.isJsonNull()) {
                                        jsonElement3 = null;
                                    }
                                    if (jsonElement3 == null || (asString2 = jsonElement3.getAsString()) == null) {
                                        str = "";
                                    } else {
                                        str = asString2;
                                    }
                                }
                                JsonElement jsonElement4 = asJsonArray2.get(1);
                                if (jsonElement4 == null) {
                                    str2 = "";
                                } else {
                                    if (jsonElement4.isJsonNull()) {
                                        jsonElement4 = null;
                                    }
                                    if (jsonElement4 == null || (asString = jsonElement4.getAsString()) == null) {
                                        str2 = "";
                                    } else {
                                        str2 = asString;
                                    }
                                }
                                JsonElement jsonElement5 = asJsonArray2.get(2);
                                double d10 = 0.0d;
                                if (jsonElement5 == null) {
                                    dDoubleValue = 0.0d;
                                } else {
                                    if (jsonElement5.isJsonNull()) {
                                        jsonElement5 = null;
                                    }
                                    if (jsonElement5 == null) {
                                        dDoubleValue = 0.0d;
                                    } else if (jsonElement5.isJsonPrimitive() && jsonElement5.getAsJsonPrimitive().isNumber()) {
                                        dDoubleValue = jsonElement5.getAsDouble();
                                    } else if (jsonElement5.isJsonPrimitive() && jsonElement5.getAsJsonPrimitive().isString() && (dN3 = v.n(jsonElement5.getAsString())) != null) {
                                        dDoubleValue = dN3.doubleValue();
                                    } else {
                                        dDoubleValue = 0.0d;
                                    }
                                }
                                JsonElement jsonElement6 = asJsonArray2.get(3);
                                if (jsonElement6 == null) {
                                    dDoubleValue2 = 0.0d;
                                } else {
                                    if (jsonElement6.isJsonNull()) {
                                        jsonElement6 = null;
                                    }
                                    if (jsonElement6 == null) {
                                        dDoubleValue2 = 0.0d;
                                    } else if (jsonElement6.isJsonPrimitive() && jsonElement6.getAsJsonPrimitive().isNumber()) {
                                        dDoubleValue2 = jsonElement6.getAsDouble();
                                    } else if (jsonElement6.isJsonPrimitive() && jsonElement6.getAsJsonPrimitive().isString() && (dN2 = v.n(jsonElement6.getAsString())) != null) {
                                        dDoubleValue2 = dN2.doubleValue();
                                    } else {
                                        dDoubleValue2 = 0.0d;
                                    }
                                }
                                JsonElement jsonElement7 = asJsonArray2.get(4);
                                if (jsonElement7 != null) {
                                    if (jsonElement7.isJsonNull()) {
                                        jsonElement7 = null;
                                    }
                                    if (jsonElement7 != null) {
                                        if (jsonElement7.isJsonPrimitive() && jsonElement7.getAsJsonPrimitive().isNumber()) {
                                            dDoubleValue3 = jsonElement7.getAsDouble();
                                        } else if (jsonElement7.isJsonPrimitive() && jsonElement7.getAsJsonPrimitive().isString() && (dN = v.n(jsonElement7.getAsString())) != null) {
                                            dDoubleValue3 = dN.doubleValue();
                                        }
                                        d10 = dDoubleValue3;
                                    }
                                }
                                estimatedLiqVpcRecord = new EstimatedLiqVpcRecord(str, str2, dDoubleValue, dDoubleValue2, d10);
                            } catch (Exception unused) {
                            }
                        }
                    }
                    if (estimatedLiqVpcRecord != null) {
                        arrayList.add(estimatedLiqVpcRecord);
                    }
                }
                linkedHashMap.put(str3, arrayList);
            }
        }
        return linkedHashMap;
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
        StringBuilder sb2 = new StringBuilder("EstimatedLiqVpcTimePoints(columns=");
        sb2.append(this.columns);
        sb2.append(", name=");
        sb2.append(this.name);
        sb2.append(", _values=");
        sb2.append(this._values);
        sb2.append(", errorMsg=");
        return h.a(sb2, this.errorMsg, ')');
    }
}
