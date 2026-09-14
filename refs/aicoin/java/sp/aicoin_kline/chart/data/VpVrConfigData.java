package sp.aicoin_kline.chart.data;

import androidx.annotation.Keep;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000&\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u0006\n\u0002\b\r\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0000\b\u0087\b\u0018\u00002\u00020\u0001B\u001b\u0012\b\b\u0002\u0010\u0002\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0004\u001a\u00020\u0003¢\u0006\u0004\b\u0005\u0010\u0006J\t\u0010\r\u001a\u00020\u0003HÆ\u0003J\t\u0010\u000e\u001a\u00020\u0003HÆ\u0003J\u001d\u0010\u000f\u001a\u00020\u00002\b\b\u0002\u0010\u0002\u001a\u00020\u00032\b\b\u0002\u0010\u0004\u001a\u00020\u0003HÆ\u0001J\u0013\u0010\u0010\u001a\u00020\u00112\b\u0010\u0012\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0013\u001a\u00020\u0014HÖ\u0001J\t\u0010\u0015\u001a\u00020\u0016HÖ\u0001R\u001a\u0010\u0002\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u0007\u0010\b\"\u0004\b\t\u0010\nR\u001a\u0010\u0004\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u000b\u0010\b\"\u0004\b\f\u0010\n¨\u0006\u0017"}, d2 = {"Lsp/aicoin_kline/chart/data/VpVrConfigData;", "", "volConfig1", "", "volConfig2", "<init>", "(DD)V", "getVolConfig1", "()D", "setVolConfig1", "(D)V", "getVolConfig2", "setVolConfig2", "component1", "component2", "copy", "equals", "", "other", "hashCode", "", "toString", "", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class VpVrConfigData {
    private double volConfig1;
    private double volConfig2;

    public VpVrConfigData() {
        this(0.0d, 0.0d, 3, null);
    }

    public VpVrConfigData(double d10, double d11) {
        this.volConfig1 = d10;
        this.volConfig2 = d11;
    }

    public /* synthetic */ VpVrConfigData(double d10, double d11, int i10, DefaultConstructorMarker defaultConstructorMarker) {
        this((i10 & 1) != 0 ? 0.0d : d10, (i10 & 2) != 0 ? 0.0d : d11);
    }

    public static /* synthetic */ VpVrConfigData copy$default(VpVrConfigData vpVrConfigData, double d10, double d11, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            d10 = vpVrConfigData.volConfig1;
        }
        if ((i10 & 2) != 0) {
            d11 = vpVrConfigData.volConfig2;
        }
        return vpVrConfigData.copy(d10, d11);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final double getVolConfig1() {
        return this.volConfig1;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final double getVolConfig2() {
        return this.volConfig2;
    }

    public final VpVrConfigData copy(double volConfig1, double volConfig2) {
        return new VpVrConfigData(volConfig1, volConfig2);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof VpVrConfigData)) {
            return false;
        }
        VpVrConfigData vpVrConfigData = (VpVrConfigData) other;
        return Double.compare(this.volConfig1, vpVrConfigData.volConfig1) == 0 && Double.compare(this.volConfig2, vpVrConfigData.volConfig2) == 0;
    }

    public final double getVolConfig1() {
        return this.volConfig1;
    }

    public final double getVolConfig2() {
        return this.volConfig2;
    }

    public int hashCode() {
        return Double.hashCode(this.volConfig2) + (Double.hashCode(this.volConfig1) * 31);
    }

    public final void setVolConfig1(double d10) {
        this.volConfig1 = d10;
    }

    public final void setVolConfig2(double d10) {
        this.volConfig2 = d10;
    }

    public String toString() {
        return "VpVrConfigData(volConfig1=" + this.volConfig1 + ", volConfig2=" + this.volConfig2 + ')';
    }
}
