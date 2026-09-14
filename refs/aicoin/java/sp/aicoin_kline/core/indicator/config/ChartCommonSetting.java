package sp.aicoin_kline.core.indicator.config;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import java.util.List;
import kotlin.Metadata;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000&\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010 \n\u0002\u0010\u000e\n\u0002\b\u0003\n\u0002\u0010\b\n\u0002\b\u001b\n\u0002\u0010\u000b\n\u0002\b\u0004\b\u0087\b\u0018\u00002\u00020\u0001Bq\u0012\u000e\u0010\u0002\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003\u0012\u000e\u0010\u0005\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003\u0012\u000e\u0010\u0006\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\b\u0012\u000e\u0010\t\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003\u0012\u000e\u0010\n\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003\u0012\u000e\u0010\u000b\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003¢\u0006\u0004\b\f\u0010\rJ\u0011\u0010\u001a\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003HÆ\u0003J\u0011\u0010\u001b\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003HÆ\u0003J\u0011\u0010\u001c\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003HÆ\u0003J\u0010\u0010\u001d\u001a\u0004\u0018\u00010\bHÆ\u0003¢\u0006\u0002\u0010\u0013J\u0011\u0010\u001e\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003HÆ\u0003J\u0011\u0010\u001f\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003HÆ\u0003J\u0011\u0010 \u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003HÆ\u0003J\u0086\u0001\u0010!\u001a\u00020\u00002\u0010\b\u0002\u0010\u0002\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u00032\u0010\b\u0002\u0010\u0005\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u00032\u0010\b\u0002\u0010\u0006\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\b2\u0010\b\u0002\u0010\t\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u00032\u0010\b\u0002\u0010\n\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u00032\u0010\b\u0002\u0010\u000b\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u0003HÆ\u0001¢\u0006\u0002\u0010\"J\u0013\u0010#\u001a\u00020$2\b\u0010%\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010&\u001a\u00020\bHÖ\u0001J\t\u0010'\u001a\u00020\u0004HÖ\u0001R\u001e\u0010\u0002\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\u000fR\u001e\u0010\u0005\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0010\u0010\u000fR\u001e\u0010\u0006\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0011\u0010\u000fR\u001e\u0010\u0007\u001a\u0004\u0018\u00010\bX\u0086\u000e¢\u0006\u0010\n\u0002\u0010\u0016\u001a\u0004\b\u0012\u0010\u0013\"\u0004\b\u0014\u0010\u0015R\u001e\u0010\t\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0017\u0010\u000fR\u001e\u0010\n\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0018\u0010\u000fR\u001e\u0010\u000b\u001a\n\u0012\u0004\u0012\u00020\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0019\u0010\u000f¨\u0006("}, d2 = {"Lsp/aicoin_kline/core/indicator/config/ChartCommonSetting;", "", "distinctiveIndicator", "", "", "primaryIndicator", "selectedIndicator", "platformSync", "", "appDistinctiveIndicator", "appPrimaryIndicator", "appSelectedIndicator", "<init>", "(Ljava/util/List;Ljava/util/List;Ljava/util/List;Ljava/lang/Integer;Ljava/util/List;Ljava/util/List;Ljava/util/List;)V", "getDistinctiveIndicator", "()Ljava/util/List;", "getPrimaryIndicator", "getSelectedIndicator", "getPlatformSync", "()Ljava/lang/Integer;", "setPlatformSync", "(Ljava/lang/Integer;)V", "Ljava/lang/Integer;", "getAppDistinctiveIndicator", "getAppPrimaryIndicator", "getAppSelectedIndicator", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "copy", "(Ljava/util/List;Ljava/util/List;Ljava/util/List;Ljava/lang/Integer;Ljava/util/List;Ljava/util/List;Ljava/util/List;)Lsp/aicoin_kline/core/indicator/config/ChartCommonSetting;", "equals", "", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class ChartCommonSetting {

    @SerializedName("app_distinctive_indicator")
    private final List<String> appDistinctiveIndicator;

    @SerializedName("app_primary_indicator")
    private final List<String> appPrimaryIndicator;

    @SerializedName("app_selected_indicator")
    private final List<String> appSelectedIndicator;

    @SerializedName("distinctive_indicator")
    private final List<String> distinctiveIndicator;
    private Integer platformSync;

    @SerializedName("primary_indicator")
    private final List<String> primaryIndicator;

    @SerializedName("selected_indicator")
    private final List<String> selectedIndicator;

    public ChartCommonSetting(List<String> list, List<String> list2, List<String> list3, Integer num, List<String> list4, List<String> list5, List<String> list6) {
        this.distinctiveIndicator = list;
        this.primaryIndicator = list2;
        this.selectedIndicator = list3;
        this.platformSync = num;
        this.appDistinctiveIndicator = list4;
        this.appPrimaryIndicator = list5;
        this.appSelectedIndicator = list6;
    }

    /* JADX WARN: Multi-variable type inference failed */
    public static /* synthetic */ ChartCommonSetting copy$default(ChartCommonSetting chartCommonSetting, List list, List list2, List list3, Integer num, List list4, List list5, List list6, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            list = chartCommonSetting.distinctiveIndicator;
        }
        if ((i10 & 2) != 0) {
            list2 = chartCommonSetting.primaryIndicator;
        }
        if ((i10 & 4) != 0) {
            list3 = chartCommonSetting.selectedIndicator;
        }
        if ((i10 & 8) != 0) {
            num = chartCommonSetting.platformSync;
        }
        if ((i10 & 16) != 0) {
            list4 = chartCommonSetting.appDistinctiveIndicator;
        }
        if ((i10 & 32) != 0) {
            list5 = chartCommonSetting.appPrimaryIndicator;
        }
        if ((i10 & 64) != 0) {
            list6 = chartCommonSetting.appSelectedIndicator;
        }
        List list7 = list5;
        List list8 = list6;
        List list9 = list4;
        List list10 = list3;
        return chartCommonSetting.copy(list, list2, list10, num, list9, list7, list8);
    }

    public final List<String> component1() {
        return this.distinctiveIndicator;
    }

    public final List<String> component2() {
        return this.primaryIndicator;
    }

    public final List<String> component3() {
        return this.selectedIndicator;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final Integer getPlatformSync() {
        return this.platformSync;
    }

    public final List<String> component5() {
        return this.appDistinctiveIndicator;
    }

    public final List<String> component6() {
        return this.appPrimaryIndicator;
    }

    public final List<String> component7() {
        return this.appSelectedIndicator;
    }

    public final ChartCommonSetting copy(List<String> distinctiveIndicator, List<String> primaryIndicator, List<String> selectedIndicator, Integer platformSync, List<String> appDistinctiveIndicator, List<String> appPrimaryIndicator, List<String> appSelectedIndicator) {
        return new ChartCommonSetting(distinctiveIndicator, primaryIndicator, selectedIndicator, platformSync, appDistinctiveIndicator, appPrimaryIndicator, appSelectedIndicator);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof ChartCommonSetting)) {
            return false;
        }
        ChartCommonSetting chartCommonSetting = (ChartCommonSetting) other;
        return AbstractC7609s.f(this.distinctiveIndicator, chartCommonSetting.distinctiveIndicator) && AbstractC7609s.f(this.primaryIndicator, chartCommonSetting.primaryIndicator) && AbstractC7609s.f(this.selectedIndicator, chartCommonSetting.selectedIndicator) && AbstractC7609s.f(this.platformSync, chartCommonSetting.platformSync) && AbstractC7609s.f(this.appDistinctiveIndicator, chartCommonSetting.appDistinctiveIndicator) && AbstractC7609s.f(this.appPrimaryIndicator, chartCommonSetting.appPrimaryIndicator) && AbstractC7609s.f(this.appSelectedIndicator, chartCommonSetting.appSelectedIndicator);
    }

    public final List<String> getAppDistinctiveIndicator() {
        return this.appDistinctiveIndicator;
    }

    public final List<String> getAppPrimaryIndicator() {
        return this.appPrimaryIndicator;
    }

    public final List<String> getAppSelectedIndicator() {
        return this.appSelectedIndicator;
    }

    public final List<String> getDistinctiveIndicator() {
        return this.distinctiveIndicator;
    }

    public final Integer getPlatformSync() {
        return this.platformSync;
    }

    public final List<String> getPrimaryIndicator() {
        return this.primaryIndicator;
    }

    public final List<String> getSelectedIndicator() {
        return this.selectedIndicator;
    }

    public int hashCode() {
        List<String> list = this.distinctiveIndicator;
        int iHashCode = (list == null ? 0 : list.hashCode()) * 31;
        List<String> list2 = this.primaryIndicator;
        int iHashCode2 = (iHashCode + (list2 == null ? 0 : list2.hashCode())) * 31;
        List<String> list3 = this.selectedIndicator;
        int iHashCode3 = (iHashCode2 + (list3 == null ? 0 : list3.hashCode())) * 31;
        Integer num = this.platformSync;
        int iHashCode4 = (iHashCode3 + (num == null ? 0 : num.hashCode())) * 31;
        List<String> list4 = this.appDistinctiveIndicator;
        int iHashCode5 = (iHashCode4 + (list4 == null ? 0 : list4.hashCode())) * 31;
        List<String> list5 = this.appPrimaryIndicator;
        int iHashCode6 = (iHashCode5 + (list5 == null ? 0 : list5.hashCode())) * 31;
        List<String> list6 = this.appSelectedIndicator;
        return iHashCode6 + (list6 != null ? list6.hashCode() : 0);
    }

    public final void setPlatformSync(Integer num) {
        this.platformSync = num;
    }

    public String toString() {
        return "ChartCommonSetting(distinctiveIndicator=" + this.distinctiveIndicator + ", primaryIndicator=" + this.primaryIndicator + ", selectedIndicator=" + this.selectedIndicator + ", platformSync=" + this.platformSync + ", appDistinctiveIndicator=" + this.appDistinctiveIndicator + ", appPrimaryIndicator=" + this.appPrimaryIndicator + ", appSelectedIndicator=" + this.appSelectedIndicator + ')';
    }
}
