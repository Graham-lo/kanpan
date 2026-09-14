package sp.aicoin_kline.chart.data;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000&\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0007\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B\u0013\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0004\u0010\u0005J\u000b\u0010\b\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0015\u0010\t\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u0010\n\u001a\u00020\u000b2\b\u0010\f\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\r\u001a\u00020\u000eHÖ\u0001J\t\u0010\u000f\u001a\u00020\u0010HÖ\u0001R\u0018\u0010\u0002\u001a\u0004\u0018\u00010\u00038\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0006\u0010\u0007¨\u0006\u0011"}, d2 = {"Lsp/aicoin_kline/chart/data/EstimatedLiqVpcData;", "", "timePoints", "Lsp/aicoin_kline/chart/data/EstimatedLiqVpcTimePoints;", "<init>", "(Lsp/aicoin_kline/chart/data/EstimatedLiqVpcTimePoints;)V", "getTimePoints", "()Lsp/aicoin_kline/chart/data/EstimatedLiqVpcTimePoints;", "component1", "copy", "equals", "", "other", "hashCode", "", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class EstimatedLiqVpcData {

    @SerializedName("time_points")
    private final EstimatedLiqVpcTimePoints timePoints;

    public EstimatedLiqVpcData() {
        this(null, 1, null);
    }

    public EstimatedLiqVpcData(EstimatedLiqVpcTimePoints estimatedLiqVpcTimePoints) {
        this.timePoints = estimatedLiqVpcTimePoints;
    }

    public /* synthetic */ EstimatedLiqVpcData(EstimatedLiqVpcTimePoints estimatedLiqVpcTimePoints, int i10, DefaultConstructorMarker defaultConstructorMarker) {
        this((i10 & 1) != 0 ? null : estimatedLiqVpcTimePoints);
    }

    public static /* synthetic */ EstimatedLiqVpcData copy$default(EstimatedLiqVpcData estimatedLiqVpcData, EstimatedLiqVpcTimePoints estimatedLiqVpcTimePoints, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            estimatedLiqVpcTimePoints = estimatedLiqVpcData.timePoints;
        }
        return estimatedLiqVpcData.copy(estimatedLiqVpcTimePoints);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final EstimatedLiqVpcTimePoints getTimePoints() {
        return this.timePoints;
    }

    public final EstimatedLiqVpcData copy(EstimatedLiqVpcTimePoints timePoints) {
        return new EstimatedLiqVpcData(timePoints);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        return (other instanceof EstimatedLiqVpcData) && AbstractC7609s.f(this.timePoints, ((EstimatedLiqVpcData) other).timePoints);
    }

    public final EstimatedLiqVpcTimePoints getTimePoints() {
        return this.timePoints;
    }

    public int hashCode() {
        EstimatedLiqVpcTimePoints estimatedLiqVpcTimePoints = this.timePoints;
        if (estimatedLiqVpcTimePoints == null) {
            return 0;
        }
        return estimatedLiqVpcTimePoints.hashCode();
    }

    public String toString() {
        return "EstimatedLiqVpcData(timePoints=" + this.timePoints + ')';
    }
}
