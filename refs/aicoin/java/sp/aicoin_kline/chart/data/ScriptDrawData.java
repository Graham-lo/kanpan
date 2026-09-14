package sp.aicoin_kline.chart.data;

import androidx.annotation.Keep;
import java.util.Map;
import kotlin.Metadata;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u00008\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010%\n\u0002\u0010\u000e\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0012\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0002\b\u0003\b\u0087\b\u0018\u00002\u00020\u0001:\u0001\"BQ\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\u001e\u0010\u0006\u001a\u001a\u0012\u0004\u0012\u00020\b\u0012\u0010\u0012\u000e\u0012\u0004\u0012\u00020\b\u0012\u0004\u0012\u00020\b0\u00070\u0007\u0012\u0014\u0010\t\u001a\u0010\u0012\u0004\u0012\u00020\b\u0012\u0004\u0012\u00020\n\u0018\u00010\u0007¢\u0006\u0004\b\u000b\u0010\fJ\u000b\u0010\u0017\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u0010\u0018\u001a\u0004\u0018\u00010\u0005HÆ\u0003J!\u0010\u0019\u001a\u001a\u0012\u0004\u0012\u00020\b\u0012\u0010\u0012\u000e\u0012\u0004\u0012\u00020\b\u0012\u0004\u0012\u00020\b0\u00070\u0007HÆ\u0003J\u0017\u0010\u001a\u001a\u0010\u0012\u0004\u0012\u00020\b\u0012\u0004\u0012\u00020\n\u0018\u00010\u0007HÆ\u0003J[\u0010\u001b\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052 \b\u0002\u0010\u0006\u001a\u001a\u0012\u0004\u0012\u00020\b\u0012\u0010\u0012\u000e\u0012\u0004\u0012\u00020\b\u0012\u0004\u0012\u00020\b0\u00070\u00072\u0016\b\u0002\u0010\t\u001a\u0010\u0012\u0004\u0012\u00020\b\u0012\u0004\u0012\u00020\n\u0018\u00010\u0007HÆ\u0001J\u0013\u0010\u001c\u001a\u00020\u001d2\b\u0010\u001e\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u001f\u001a\u00020 HÖ\u0001J\t\u0010!\u001a\u00020\bHÖ\u0001R\u0013\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b\r\u0010\u000eR\u0013\u0010\u0004\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000f\u0010\u0010R2\u0010\u0006\u001a\u001a\u0012\u0004\u0012\u00020\b\u0012\u0010\u0012\u000e\u0012\u0004\u0012\u00020\b\u0012\u0004\u0012\u00020\b0\u00070\u0007X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u0011\u0010\u0012\"\u0004\b\u0013\u0010\u0014R(\u0010\t\u001a\u0010\u0012\u0004\u0012\u00020\b\u0012\u0004\u0012\u00020\n\u0018\u00010\u0007X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u0015\u0010\u0012\"\u0004\b\u0016\u0010\u0014¨\u0006#"}, d2 = {"Lsp/aicoin_kline/chart/data/ScriptDrawData;", "", "config", "Lsp/aicoin_kline/chart/data/ScriptIndicConfig;", "historyData", "Lsp/aicoin_kline/chart/data/ScriptIndicHistoryData;", "calculateHistoryData", "", "", "scriptRangeData", "Lsp/aicoin_kline/chart/data/ScriptDrawData$ScriptRangeData;", "<init>", "(Lsp/aicoin_kline/chart/data/ScriptIndicConfig;Lsp/aicoin_kline/chart/data/ScriptIndicHistoryData;Ljava/util/Map;Ljava/util/Map;)V", "getConfig", "()Lsp/aicoin_kline/chart/data/ScriptIndicConfig;", "getHistoryData", "()Lsp/aicoin_kline/chart/data/ScriptIndicHistoryData;", "getCalculateHistoryData", "()Ljava/util/Map;", "setCalculateHistoryData", "(Ljava/util/Map;)V", "getScriptRangeData", "setScriptRangeData", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "ScriptRangeData", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class ScriptDrawData {
    private Map<String, Map<String, String>> calculateHistoryData;
    private final ScriptIndicConfig config;
    private final ScriptIndicHistoryData historyData;
    private Map<String, ScriptRangeData> scriptRangeData;

    @Keep
    @Metadata(d1 = {"\u0000&\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u0006\n\u0002\b\f\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B\u001b\u0012\b\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\u0010\u0010\u000b\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\bJ\u0010\u0010\f\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\bJ&\u0010\r\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010\u000eJ\u0013\u0010\u000f\u001a\u00020\u00102\b\u0010\u0011\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0012\u001a\u00020\u0013HÖ\u0001J\t\u0010\u0014\u001a\u00020\u0015HÖ\u0001R\u0015\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\t\u001a\u0004\b\u0007\u0010\bR\u0015\u0010\u0004\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\t\u001a\u0004\b\n\u0010\b¨\u0006\u0016"}, d2 = {"Lsp/aicoin_kline/chart/data/ScriptDrawData$ScriptRangeData;", "", "highValue", "", "lowValue", "<init>", "(Ljava/lang/Double;Ljava/lang/Double;)V", "getHighValue", "()Ljava/lang/Double;", "Ljava/lang/Double;", "getLowValue", "component1", "component2", "copy", "(Ljava/lang/Double;Ljava/lang/Double;)Lsp/aicoin_kline/chart/data/ScriptDrawData$ScriptRangeData;", "equals", "", "other", "hashCode", "", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class ScriptRangeData {
        private final Double highValue;
        private final Double lowValue;

        public ScriptRangeData(Double d10, Double d11) {
            this.highValue = d10;
            this.lowValue = d11;
        }

        public static /* synthetic */ ScriptRangeData copy$default(ScriptRangeData scriptRangeData, Double d10, Double d11, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                d10 = scriptRangeData.highValue;
            }
            if ((i10 & 2) != 0) {
                d11 = scriptRangeData.lowValue;
            }
            return scriptRangeData.copy(d10, d11);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Double getHighValue() {
            return this.highValue;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Double getLowValue() {
            return this.lowValue;
        }

        public final ScriptRangeData copy(Double highValue, Double lowValue) {
            return new ScriptRangeData(highValue, lowValue);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof ScriptRangeData)) {
                return false;
            }
            ScriptRangeData scriptRangeData = (ScriptRangeData) other;
            return AbstractC7609s.f(this.highValue, scriptRangeData.highValue) && AbstractC7609s.f(this.lowValue, scriptRangeData.lowValue);
        }

        public final Double getHighValue() {
            return this.highValue;
        }

        public final Double getLowValue() {
            return this.lowValue;
        }

        public int hashCode() {
            Double d10 = this.highValue;
            int iHashCode = (d10 == null ? 0 : d10.hashCode()) * 31;
            Double d11 = this.lowValue;
            return iHashCode + (d11 != null ? d11.hashCode() : 0);
        }

        public String toString() {
            return "ScriptRangeData(highValue=" + this.highValue + ", lowValue=" + this.lowValue + ')';
        }
    }

    public ScriptDrawData(ScriptIndicConfig scriptIndicConfig, ScriptIndicHistoryData scriptIndicHistoryData, Map<String, Map<String, String>> map, Map<String, ScriptRangeData> map2) {
        this.config = scriptIndicConfig;
        this.historyData = scriptIndicHistoryData;
        this.calculateHistoryData = map;
        this.scriptRangeData = map2;
    }

    /* JADX WARN: Multi-variable type inference failed */
    public static /* synthetic */ ScriptDrawData copy$default(ScriptDrawData scriptDrawData, ScriptIndicConfig scriptIndicConfig, ScriptIndicHistoryData scriptIndicHistoryData, Map map, Map map2, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            scriptIndicConfig = scriptDrawData.config;
        }
        if ((i10 & 2) != 0) {
            scriptIndicHistoryData = scriptDrawData.historyData;
        }
        if ((i10 & 4) != 0) {
            map = scriptDrawData.calculateHistoryData;
        }
        if ((i10 & 8) != 0) {
            map2 = scriptDrawData.scriptRangeData;
        }
        return scriptDrawData.copy(scriptIndicConfig, scriptIndicHistoryData, map, map2);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final ScriptIndicConfig getConfig() {
        return this.config;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final ScriptIndicHistoryData getHistoryData() {
        return this.historyData;
    }

    public final Map<String, Map<String, String>> component3() {
        return this.calculateHistoryData;
    }

    public final Map<String, ScriptRangeData> component4() {
        return this.scriptRangeData;
    }

    public final ScriptDrawData copy(ScriptIndicConfig config, ScriptIndicHistoryData historyData, Map<String, Map<String, String>> calculateHistoryData, Map<String, ScriptRangeData> scriptRangeData) {
        return new ScriptDrawData(config, historyData, calculateHistoryData, scriptRangeData);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof ScriptDrawData)) {
            return false;
        }
        ScriptDrawData scriptDrawData = (ScriptDrawData) other;
        return AbstractC7609s.f(this.config, scriptDrawData.config) && AbstractC7609s.f(this.historyData, scriptDrawData.historyData) && AbstractC7609s.f(this.calculateHistoryData, scriptDrawData.calculateHistoryData) && AbstractC7609s.f(this.scriptRangeData, scriptDrawData.scriptRangeData);
    }

    public final Map<String, Map<String, String>> getCalculateHistoryData() {
        return this.calculateHistoryData;
    }

    public final ScriptIndicConfig getConfig() {
        return this.config;
    }

    public final ScriptIndicHistoryData getHistoryData() {
        return this.historyData;
    }

    public final Map<String, ScriptRangeData> getScriptRangeData() {
        return this.scriptRangeData;
    }

    public int hashCode() {
        ScriptIndicConfig scriptIndicConfig = this.config;
        int iHashCode = (scriptIndicConfig == null ? 0 : scriptIndicConfig.hashCode()) * 31;
        ScriptIndicHistoryData scriptIndicHistoryData = this.historyData;
        int iHashCode2 = (this.calculateHistoryData.hashCode() + ((iHashCode + (scriptIndicHistoryData == null ? 0 : scriptIndicHistoryData.hashCode())) * 31)) * 31;
        Map<String, ScriptRangeData> map = this.scriptRangeData;
        return iHashCode2 + (map != null ? map.hashCode() : 0);
    }

    public final void setCalculateHistoryData(Map<String, Map<String, String>> map) {
        this.calculateHistoryData = map;
    }

    public final void setScriptRangeData(Map<String, ScriptRangeData> map) {
        this.scriptRangeData = map;
    }

    public String toString() {
        return "ScriptDrawData(config=" + this.config + ", historyData=" + this.historyData + ", calculateHistoryData=" + this.calculateHistoryData + ", scriptRangeData=" + this.scriptRangeData + ')';
    }
}
