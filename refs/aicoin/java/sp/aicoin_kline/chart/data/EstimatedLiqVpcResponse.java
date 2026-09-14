package sp.aicoin_kline.chart.data;

import androidx.annotation.Keep;
import com.google.gson.annotations.SerializedName;
import kk.d;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000$\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\b\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0014\b\u0087\b\u0018\u00002\u00020\u0001B1\u0012\b\b\u0002\u0010\u0002\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0004\u001a\u00020\u0005\u0012\b\b\u0002\u0010\u0006\u001a\u00020\u0007\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\t¢\u0006\u0004\b\n\u0010\u000bJ\t\u0010\u0014\u001a\u00020\u0003HÆ\u0003J\t\u0010\u0015\u001a\u00020\u0005HÆ\u0003J\t\u0010\u0016\u001a\u00020\u0007HÆ\u0003J\u000b\u0010\u0017\u001a\u0004\u0018\u00010\tHÆ\u0003J3\u0010\u0018\u001a\u00020\u00002\b\b\u0002\u0010\u0002\u001a\u00020\u00032\b\b\u0002\u0010\u0004\u001a\u00020\u00052\b\b\u0002\u0010\u0006\u001a\u00020\u00072\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\tHÆ\u0001J\u0013\u0010\u0019\u001a\u00020\u00032\b\u0010\u001a\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u001b\u001a\u00020\u0007HÖ\u0001J\t\u0010\u001c\u001a\u00020\u0005HÖ\u0001R\u0011\u0010\u0002\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0011\u0010\u0004\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\u000fR\u0016\u0010\u0006\u001a\u00020\u00078\u0006X\u0087\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0010\u0010\u0011R\u0013\u0010\b\u001a\u0004\u0018\u00010\t¢\u0006\b\n\u0000\u001a\u0004\b\u0012\u0010\u0013¨\u0006\u001d"}, d2 = {"Lsp/aicoin_kline/chart/data/EstimatedLiqVpcResponse;", "", "success", "", "error", "", "errorCode", "", "data", "Lsp/aicoin_kline/chart/data/EstimatedLiqVpcData;", "<init>", "(ZLjava/lang/String;ILsp/aicoin_kline/chart/data/EstimatedLiqVpcData;)V", "getSuccess", "()Z", "getError", "()Ljava/lang/String;", "getErrorCode", "()I", "getData", "()Lsp/aicoin_kline/chart/data/EstimatedLiqVpcData;", "component1", "component2", "component3", "component4", "copy", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class EstimatedLiqVpcResponse {
    private final EstimatedLiqVpcData data;
    private final String error;

    @SerializedName("errorCode")
    private final int errorCode;
    private final boolean success;

    public EstimatedLiqVpcResponse() {
        this(false, null, 0, null, 15, null);
    }

    public EstimatedLiqVpcResponse(boolean z10, String str, int i10, EstimatedLiqVpcData estimatedLiqVpcData) {
        this.success = z10;
        this.error = str;
        this.errorCode = i10;
        this.data = estimatedLiqVpcData;
    }

    public /* synthetic */ EstimatedLiqVpcResponse(boolean z10, String str, int i10, EstimatedLiqVpcData estimatedLiqVpcData, int i11, DefaultConstructorMarker defaultConstructorMarker) {
        this((i11 & 1) != 0 ? false : z10, (i11 & 2) != 0 ? "" : str, (i11 & 4) != 0 ? 0 : i10, (i11 & 8) != 0 ? null : estimatedLiqVpcData);
    }

    public static /* synthetic */ EstimatedLiqVpcResponse copy$default(EstimatedLiqVpcResponse estimatedLiqVpcResponse, boolean z10, String str, int i10, EstimatedLiqVpcData estimatedLiqVpcData, int i11, Object obj) {
        if ((i11 & 1) != 0) {
            z10 = estimatedLiqVpcResponse.success;
        }
        if ((i11 & 2) != 0) {
            str = estimatedLiqVpcResponse.error;
        }
        if ((i11 & 4) != 0) {
            i10 = estimatedLiqVpcResponse.errorCode;
        }
        if ((i11 & 8) != 0) {
            estimatedLiqVpcData = estimatedLiqVpcResponse.data;
        }
        return estimatedLiqVpcResponse.copy(z10, str, i10, estimatedLiqVpcData);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final boolean getSuccess() {
        return this.success;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getError() {
        return this.error;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final int getErrorCode() {
        return this.errorCode;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final EstimatedLiqVpcData getData() {
        return this.data;
    }

    public final EstimatedLiqVpcResponse copy(boolean success, String error, int errorCode, EstimatedLiqVpcData data) {
        return new EstimatedLiqVpcResponse(success, error, errorCode, data);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof EstimatedLiqVpcResponse)) {
            return false;
        }
        EstimatedLiqVpcResponse estimatedLiqVpcResponse = (EstimatedLiqVpcResponse) other;
        return this.success == estimatedLiqVpcResponse.success && AbstractC7609s.f(this.error, estimatedLiqVpcResponse.error) && this.errorCode == estimatedLiqVpcResponse.errorCode && AbstractC7609s.f(this.data, estimatedLiqVpcResponse.data);
    }

    public final EstimatedLiqVpcData getData() {
        return this.data;
    }

    public final String getError() {
        return this.error;
    }

    public final int getErrorCode() {
        return this.errorCode;
    }

    public final boolean getSuccess() {
        return this.success;
    }

    public int hashCode() {
        int iHashCode = (Integer.hashCode(this.errorCode) + d.a(this.error, Boolean.hashCode(this.success) * 31, 31)) * 31;
        EstimatedLiqVpcData estimatedLiqVpcData = this.data;
        return iHashCode + (estimatedLiqVpcData == null ? 0 : estimatedLiqVpcData.hashCode());
    }

    public String toString() {
        return "EstimatedLiqVpcResponse(success=" + this.success + ", error=" + this.error + ", errorCode=" + this.errorCode + ", data=" + this.data + ')';
    }
}
