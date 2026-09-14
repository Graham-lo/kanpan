package sp.aicoin_kline.chart.data;

import androidx.annotation.Keep;
import java.util.List;
import kotlin.Metadata;
import p167hg.AbstractC7609s;
import p398sh.aicoin.search.data.remote.SearchRemoteDataSource;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000&\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010 \n\u0002\u0010\u000e\n\u0002\b\n\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001B)\u0012\u0012\u0010\u0002\u001a\u000e\u0012\n\u0012\b\u0012\u0004\u0012\u00020\u00040\u00030\u0003\u0012\f\u0010\u0005\u001a\b\u0012\u0004\u0012\u00020\u00040\u0003¢\u0006\u0004\b\u0006\u0010\u0007J\u0015\u0010\u000b\u001a\u000e\u0012\n\u0012\b\u0012\u0004\u0012\u00020\u00040\u00030\u0003HÆ\u0003J\u000f\u0010\f\u001a\b\u0012\u0004\u0012\u00020\u00040\u0003HÆ\u0003J/\u0010\r\u001a\u00020\u00002\u0014\b\u0002\u0010\u0002\u001a\u000e\u0012\n\u0012\b\u0012\u0004\u0012\u00020\u00040\u00030\u00032\u000e\b\u0002\u0010\u0005\u001a\b\u0012\u0004\u0012\u00020\u00040\u0003HÆ\u0001J\u0013\u0010\u000e\u001a\u00020\u000f2\b\u0010\u0010\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0011\u001a\u00020\u0012HÖ\u0001J\t\u0010\u0013\u001a\u00020\u0004HÖ\u0001R\u001d\u0010\u0002\u001a\u000e\u0012\n\u0012\b\u0012\u0004\u0012\u00020\u00040\u00030\u0003¢\u0006\b\n\u0000\u001a\u0004\b\b\u0010\tR\u0017\u0010\u0005\u001a\b\u0012\u0004\u0012\u00020\u00040\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\t¨\u0006\u0014"}, d2 = {"Lsp/aicoin_kline/chart/data/ScriptIndicHistoryData;", "", SearchRemoteDataSource.HTTP_PARSE_KEY_ITEM_LIST, "", "", "mapping", "<init>", "(Ljava/util/List;Ljava/util/List;)V", "getList", "()Ljava/util/List;", "getMapping", "component1", "component2", "copy", "equals", "", "other", "hashCode", "", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class ScriptIndicHistoryData {
    private final List<List<String>> list;
    private final List<String> mapping;

    /* JADX WARN: Multi-variable type inference failed */
    public ScriptIndicHistoryData(List<? extends List<String>> list, List<String> list2) {
        this.list = list;
        this.mapping = list2;
    }

    /* JADX WARN: Multi-variable type inference failed */
    public static /* synthetic */ ScriptIndicHistoryData copy$default(ScriptIndicHistoryData scriptIndicHistoryData, List list, List list2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            list = scriptIndicHistoryData.list;
        }
        if ((i10 & 2) != 0) {
            list2 = scriptIndicHistoryData.mapping;
        }
        return scriptIndicHistoryData.copy(list, list2);
    }

    public final List<List<String>> component1() {
        return this.list;
    }

    public final List<String> component2() {
        return this.mapping;
    }

    public final ScriptIndicHistoryData copy(List<? extends List<String>> list, List<String> mapping) {
        return new ScriptIndicHistoryData(list, mapping);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof ScriptIndicHistoryData)) {
            return false;
        }
        ScriptIndicHistoryData scriptIndicHistoryData = (ScriptIndicHistoryData) other;
        return AbstractC7609s.f(this.list, scriptIndicHistoryData.list) && AbstractC7609s.f(this.mapping, scriptIndicHistoryData.mapping);
    }

    public final List<List<String>> getList() {
        return this.list;
    }

    public final List<String> getMapping() {
        return this.mapping;
    }

    public int hashCode() {
        return this.mapping.hashCode() + (this.list.hashCode() * 31);
    }

    public String toString() {
        return "ScriptIndicHistoryData(list=" + this.list + ", mapping=" + this.mapping + ')';
    }
}
